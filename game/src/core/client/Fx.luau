--!strict
-- 연출(타격감) 엔진 — Cubika Fx.luau의 3D판. Core client module (docs/33).
--   * 소리: 목소리 칸 풀(위치 소리는 Attachment째). 키 → id 표는 게임이 Fx.configure({ sounds })로 넣는다.
--   * 파티클: 텍스처(Fx.configure images, 없으면 Roblox 내장 텍스처) ParticleEmitter 풀. 위치만 옮겨 Emit.
--   * 고스트·충격파: 풀에서 꺼내 쓰는 섬광 큐브·바닥 고리.
--   * 카메라: trauma 누적/감쇠 흔들림(세기 = trauma²) + FOV 펀치 + 줌. 화면 섬광·어둡게.
--   * 배너: 화면 가운데 위 큰 글자 (대기열).
-- 모든 연출은 클라이언트 전용(서버 비용 0). 파티클 수는 Quality 상한을 거친다 (high = 그대로).
-- Game setup at boot: Fx.configure({ sounds = {...}, soundMax = {...}, images = {...}, bannerHold = fn })
-- Standard sound keys used by core (Reveal etc.): Pop, Chime, Sparkle, Whoosh, Thump, Coin, LevelUp, Fanfare, Boom, Impact.
-- Standard image keys: Chunk, Sparkle, Glow, Puff (particles), Ring (shockwave decal), FaceHappy (ghost face decal).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)
local Quality = require(script.Parent.Quality)

local player = Players.LocalPlayer
local Fx = {}

export type Options = {
	sounds: { [string]: string }?, -- key -> SoundId
	soundMax: { [string]: number }?, -- key -> max length (s) before a short fade
	soundMaxDefault: number?,
	images: { [string]: string }?, -- key -> texture id (see header)
	bannerHold: (() -> boolean)?, -- true = keep queued banners waiting (e.g. during a boss fight)
}

local folder = Instance.new("Folder")
folder.Name = "ClientFx"
folder.Parent = workspace
Fx.folder = folder

local function tween(
	inst: Instance,
	dur: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(dur, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end
Fx.tween = tween

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
Fx.lighten = lighten

-- 게임이 넣는 표 (Fx.configure)
local images: { [string]: string } = {}
-- 내장 텍스처 (게임이 이미지를 안 넣었을 때): Roblox 클라이언트에 들어 있는 파티클 텍스처
local BUILTIN_IMAGES: { [string]: string } = {
	Chunk = "rbxasset://textures/particles/sparkles_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Glow = "rbxasset://textures/particles/fire_main.dds",
	Puff = "rbxasset://textures/particles/smoke_main.dds",
}
local function image(key: string): string
	return images[key] or BUILTIN_IMAGES[key] or ""
end
Fx.image = image

local bannerHold: (() -> boolean)? = nil

------------------------------------------------------------------------
-- 소리
------------------------------------------------------------------------

local SOUND_IDS: { [string]: string } = {}

-- 효과음 최대 길이(초). maxLen을 안 넘겨도 이 길이에서 짧게 페이드아웃한다 — 긴 소리가 남지 않게 (플레이테스트 2026-10-18).
local SOUND_MAX: { [string]: number } = {}
local soundMaxDefault = 0.6

-- 소리 키 등록 (configure 뒤에 하나씩 더할 때). maxLen = 길이 상한
function Fx.registerSound(key: string, id: string, maxLen: number?)
	SOUND_IDS[key] = id
	if maxLen then
		SOUND_MAX[key] = maxLen
	end
end

function Fx.hasSound(key: string): boolean
	local id = SOUND_IDS[key]
	return id ~= nil and id ~= ""
end

local soundAnchor = Instance.new("Part")
soundAnchor.Name = "SoundAnchor"
soundAnchor.Anchored = true
soundAnchor.CanCollide = false
soundAnchor.CanQuery = false
soundAnchor.CanTouch = false
soundAnchor.Transparency = 1
soundAnchor.Size = Vector3.one
soundAnchor.Parent = folder

-- 같은 소리를 동시에 여러 번 낼 수 있게 목소리 칸(Sound, 위치 소리는 Attachment째) 풀을 돌려 쓴다.
-- 2026-10-21 고등급 렉: 후반(드로퍼 8개·초당 합치기 ~22)엔 소리마다 Sound+Attachment를 만들고 지워 초당 70개가 생겼다.
-- 칸이 모자라면 가장 오래된 소리를 끊고 쓴다 (그만큼 겹친 소리는 어차피 묻힌다).
-- throttle: 같은 키를 초당 너무 많이 내지 않도록 (투하·착지는 초당 수십 번 일어남)
local lastPlayed: { [string]: number } = {}
local VOICES = 24
type Voice = { s: Sound, a: Attachment?, started: number, fade: Tween?, token: number }
local posVoices: { Voice } = {}
local flatVoices: { Voice } = {}
local function voice(list: { Voice }, positional: boolean): Voice
	local oldest: Voice? = nil
	for _, v in list do
		if not v.s.IsPlaying then
			return v
		end
		if not oldest or v.started < oldest.started then
			oldest = v
		end
	end
	if oldest and #list >= VOICES then
		return oldest
	end
	local s = Instance.new("Sound")
	s.RollOffMaxDistance = 180
	s.RollOffMinDistance = 20
	local v: Voice = { s = s, a = nil, started = 0, fade = nil, token = 0 }
	if positional then
		local a = Instance.new("Attachment")
		a.Parent = soundAnchor
		s.Parent = a
		v.a = a
	else
		s.Parent = SoundService
	end
	table.insert(list, v)
	return v
end
-- maxLen: 그 시간 뒤 짧게 페이드아웃해 끊는다
function Fx.sound(key: string, at: Vector3?, volume: number, pitch: number?, minGap: number?, maxLen: number?)
	local id = SOUND_IDS[key]
	if not id or id == "" then
		return
	end
	local now = os.clock()
	if minGap and now - (lastPlayed[key] or 0) < minGap then
		return
	end
	lastPlayed[key] = now
	local v = voice(if at then posVoices else flatVoices, at ~= nil)
	local s = v.s
	if v.fade then
		v.fade:Cancel()
		v.fade = nil
	end
	s:Stop()
	v.token += 1
	v.started = now
	local token = v.token
	if at and v.a then
		v.a.WorldPosition = at
	end
	if s.SoundId ~= id then
		s.SoundId = id
	end
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.TimePosition = 0
	s:Play()
	local cap = SOUND_MAX[key] or soundMaxDefault
	local len = if maxLen then math.min(maxLen, cap) else cap
	task.delay(len, function()
		-- 그 사이 다른 소리가 이 칸을 가져갔으면 건드리지 않는다
		if v.token == token and s.IsPlaying then
			v.fade = tween(s, 0.08, { Volume = 0 })
			task.delay(0.09, function()
				if v.token == token then
					s:Stop()
					v.fade = nil
				end
			end)
		end
	end)
end

------------------------------------------------------------------------
-- 파티클
------------------------------------------------------------------------

local emitterHost = Instance.new("Part")
emitterHost.Name = "EmitterHost"
emitterHost.Anchored = true
emitterHost.CanCollide = false
emitterHost.CanQuery = false
emitterHost.CanTouch = false
emitterHost.Transparency = 1
emitterHost.Size = Vector3.one
emitterHost.Parent = folder

-- texture = images 키 (Fx.configure) 또는 rbxasset/rbxassetid 주소
export type EmitterDef = {
	texture: string,
	lifetime: NumberRange,
	speed: NumberRange,
	spread: Vector2,
	drag: number,
	accel: Vector3,
	rot: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence,
	light: number,
	orientation: Enum.ParticleOrientation?,
}

local function ns(points: { { number } }): NumberSequence
	local kp = {}
	for _, p in points do
		table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kp)
end
Fx.ns = ns

local DEFS: { [string]: EmitterDef } = {
	-- 파편 (중력으로 떨어지는 색종이)
	Chunk = {
		texture = "Chunk",
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(18, 34),
		spread = Vector2.new(180, 180),
		drag = 2.5,
		accel = Vector3.new(0, -60, 0),
		rot = NumberRange.new(-400, 400),
		size = ns({ { 0, 1 }, { 0.8, 0.8 }, { 1, 0 } }),
		transparency = ns({ { 0, 0 }, { 0.75, 0 }, { 1, 1 } }),
		light = 0.3,
	},
	-- 반짝이 별
	Sparkle = {
		texture = "Sparkle",
		lifetime = NumberRange.new(0.4, 0.9),
		speed = NumberRange.new(8, 22),
		spread = Vector2.new(180, 180),
		drag = 4,
		accel = Vector3.new(0, 6, 0),
		rot = NumberRange.new(-90, 90),
		size = ns({ { 0, 0.4 }, { 0.2, 1.4 }, { 1, 0 } }),
		transparency = ns({ { 0, 0 }, { 1, 1 } }),
		light = 1,
	},
	-- 중심 섬광
	Glow = {
		texture = "Glow",
		lifetime = NumberRange.new(0.25, 0.3),
		speed = NumberRange.new(0, 0),
		spread = Vector2.new(0, 0),
		drag = 0,
		accel = Vector3.zero,
		rot = NumberRange.new(0, 0),
		size = ns({ { 0, 2 }, { 0.3, 6 }, { 1, 8 } }),
		transparency = ns({ { 0, 0.1 }, { 1, 1 } }),
		light = 1,
	},
	-- 먼지 (착지·투하)
	Puff = {
		texture = "Puff",
		lifetime = NumberRange.new(0.35, 0.6),
		speed = NumberRange.new(6, 12),
		spread = Vector2.new(90, 10),
		drag = 5,
		accel = Vector3.new(0, 3, 0),
		rot = NumberRange.new(-60, 60),
		size = ns({ { 0, 1 }, { 1, 3 } }),
		transparency = ns({ { 0, 0.35 }, { 1, 1 } }),
		light = 0,
	},
}

-- 게임 전용 파티클 종류 추가 (예: 꽃잎, 불씨). 처음 burst할 때 만든다
function Fx.defineEmitter(key: string, def: EmitterDef)
	DEFS[key] = def
end

local emitters: { [string]: ParticleEmitter } = {}
local attachments: { [string]: Attachment } = {}

local function emitter(key: string): (ParticleEmitter, Attachment)
	local e = emitters[key]
	if e then
		return e, attachments[key]
	end
	local d = DEFS[key]
	local a = Instance.new("Attachment")
	a.Name = key
	a.Parent = emitterHost
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = if string.find(d.texture, "://") then d.texture else image(d.texture)
	pe.Enabled = false
	pe.Lifetime = d.lifetime
	pe.Speed = d.speed
	pe.SpreadAngle = d.spread
	pe.Drag = d.drag
	pe.Acceleration = d.accel
	pe.RotSpeed = d.rot
	pe.Rotation = NumberRange.new(0, 360)
	pe.Size = d.size
	pe.Transparency = d.transparency
	pe.LightEmission = d.light
	pe.LightInfluence = 0
	pe.LockedToPart = false
	pe.EmissionDirection = Enum.NormalId.Top
	if d.orientation then
		pe.Orientation = d.orientation
	end
	pe.Parent = a
	emitters[key] = pe
	attachments[key] = a
	return pe, a
end

-- key 파티클 n개를 at에서 방출. scale은 Size 배율, color는 틴트. 개수는 Quality 상한을 거친다 (high = 그대로)
function Fx.burst(key: string, at: Vector3, n: number, scale: number?, color: Color3?)
	local count = Quality.particles(math.max(1, math.floor(n)))
	if count <= 0 then
		return
	end
	local pe, a = emitter(key)
	a.WorldPosition = at
	local d = DEFS[key]
	local s = scale or 1
	if s ~= 1 then
		local kp = {}
		for _, k in d.size.Keypoints do
			table.insert(kp, NumberSequenceKeypoint.new(k.Time, k.Value * s))
		end
		pe.Size = NumberSequence.new(kp)
	else
		pe.Size = d.size
	end
	pe.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
	pe:Emit(count)
end

-- 슬로모션 느낌: 풀의 모든 파티클 시간 배율 (1 = 보통). Reveal 5단계가 쓴다
function Fx.particleTime(scale: number)
	for _, pe in emitters do
		pe.TimeScale = scale
	end
end

------------------------------------------------------------------------
-- 카메라 흔들림 / FOV 펀치 / 화면 섬광
------------------------------------------------------------------------

local trauma = 0
local fovKick = 0
local fovZoom = 0 -- 공개 연출 중 천천히 당겨 들어가는 줌 (도)
local baseFov: number? = nil
local lastShakeOffset = CFrame.identity

-- 2026-10-25 사용자 "드롭수 조금만 많아져도 화면 흔들림 연출이 너무 많아서 어지러움": 더하지 않고 큰 쪽만 남긴다.
-- 자주 나는 작은 흔들림(SMALL_SHAKE 미만)은 절반 세기 + SMALL_GAP초에 한 번만
local SMALL_SHAKE = 0.3
local SMALL_GAP = 0.6
local lastSmall = 0

-- 접근성 상한 (플레이어 설정). 기본 1 = 그대로 (Merge는 부르지 않음).
--   flash: 섬광 알파 상한 (0.4 = 섬광 줄이기), shake: 흔들림 배율 (0 = 흔들림 끔, holdShake 포함), fov: FOV 펀치 배율
-- Fx.setLimits({ shake = 0 })  /  Fx.setLimits({ flash = 0.4, fov = 0.3 }). 준 키만 바뀐다.
local limits = { flash = 1, shake = 1, fov = 1 }
function Fx.setLimits(l: { flash: number?, shake: number?, fov: number? })
	limits.flash = l.flash or limits.flash
	limits.shake = l.shake or limits.shake
	limits.fov = l.fov or limits.fov
end

function Fx.shake(amount: number)
	if limits.shake <= 0 then
		return
	end
	amount *= limits.shake
	if amount < SMALL_SHAKE then
		local now = os.clock()
		if now - lastSmall < SMALL_GAP then
			return
		end
		lastSmall = now
		amount *= 0.5
	end
	trauma = math.max(trauma, math.min(1, amount))
end

-- 흔들림을 최소 amount로 유지 (긴 연출 중 매 프레임 부름. 작은 흔들림 규칙을 거치지 않음)
function Fx.holdShake(amount: number)
	trauma = math.max(trauma, amount * limits.shake)
end

function Fx.fovPunch(degrees: number)
	fovKick = math.min(12, fovKick + degrees * limits.fov)
end

-- 천천히 당겨 들어가는 줌 (도). 0이면 원래대로
function Fx.setZoom(degrees: number)
	fovZoom = degrees
end

RunService:BindToRenderStep("CoreFxCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- 이전 프레임 흔들림 제거는 카메라 스크립트가 매 프레임 CFrame을 다시 쓰므로 필요 없다
	trauma = math.max(0, trauma - dt * 1.6)
	if trauma > 0 then
		local s = trauma * trauma
		local t = os.clock() * 28
		lastShakeOffset = CFrame.new(math.noise(t, 1) * s * 1.2, math.noise(t, 2) * s * 1.2, 0)
			* CFrame.Angles(0, 0, math.noise(t, 3) * s * 0.06)
		cam.CFrame *= lastShakeOffset
	end
	if baseFov == nil then
		baseFov = cam.FieldOfView
	end
	fovKick = math.max(0, fovKick - dt * 30)
	cam.FieldOfView = (baseFov :: number) - fovKick - fovZoom
end)

local flashGui = Instance.new("ScreenGui")
flashGui.Name = "FxFlash"
flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 50
flashGui.ResetOnSpawn = false
flashGui.Parent = player:WaitForChild("PlayerGui")
Fx.flashGui = flashGui
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.Active = false
flashFrame.Parent = flashGui

function Fx.screenFlash(color: Color3, alpha: number, dur: number)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - math.min(alpha, limits.flash)
	tween(flashFrame, dur, { BackgroundTransparency = 1 })
end

-- 화면 어둡게 (가장자리부터, 비네트). transparency 1 = 끔
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = false
dim.ZIndex = 0 -- 섬광(flashFrame)보다 아래
dim.Parent = flashGui
local dimGrad = Instance.new("UIGradient")
-- 가운데는 밝게, 위아래 가장자리는 어둡게 (비네트 느낌)
dimGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.35, 0.55),
	NumberSequenceKeypoint.new(0.5, 0.75),
	NumberSequenceKeypoint.new(0.65, 0.55),
	NumberSequenceKeypoint.new(1, 0),
})
dimGrad.Rotation = 90
dimGrad.Parent = dim

function Fx.dim(transparency: number, dur: number)
	tween(dim, dur, { BackgroundTransparency = transparency })
end

------------------------------------------------------------------------
-- 월드 연출 조각
------------------------------------------------------------------------

local function fxPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end
Fx.part = fxPart

-- 섬광 큐브·충격파 고리는 풀에서 꺼내 쓰고 끝나면 숨겨 돌려놓는다 (2026-10-21 고등급 렉: 초당 Part+Decal 60여 개를 만들고 지웠다)
type FxPiece = { p: Part, d: Decal }
local HIDDEN = CFrame.new(0, -500, 0)
local ghostPool: { FxPiece } = {}
local ringPool: { FxPiece } = {}
local function release(pool: { FxPiece }, piece: FxPiece)
	piece.p.Transparency = 1
	piece.d.Transparency = 1
	piece.p.CFrame = HIDDEN
	table.insert(pool, piece)
end

-- 섬광 큐브: 흰색 → color, 부풀었다 줄며 사라짐 + 얼굴(FaceHappy)
function Fx.ghost(at: Vector3, size: number, color: Color3, big: boolean)
	local piece = table.remove(ghostPool)
	if not piece then
		local np = fxPart({ Material = Enum.Material.Neon, CFrame = HIDDEN, Transparency = 1 })
		local nd = Instance.new("Decal")
		nd.Texture = image("FaceHappy")
		nd.Face = Enum.NormalId.Front
		nd.Parent = np
		piece = { p = np, d = nd }
	end
	local pc = piece :: FxPiece
	local p, face = pc.p, pc.d
	p.Size = Vector3.one * size * 1.05
	p.CFrame = CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	p.Color = Color3.new(1, 1, 1)
	-- 큰 것일수록 반투명하게: 화면을 가리지 않도록 (플레이테스트 2026-10-18)
	p.Transparency = math.clamp((size - 3) / 12, 0.1, 0.55)
	face.Transparency = 0
	local peak = if big then 1.25 else 1.3
	tween(p, 0.08, { Size = Vector3.one * size * peak, Color = lighten(color, 0.4) }, Enum.EasingStyle.Back)
	task.delay(0.08, function()
		tween(
			p,
			0.28,
			{ Size = Vector3.one * size * 0.9, Transparency = 1 },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		tween(face, 0.28, { Transparency = 1 })
	end)
	task.delay(0.5, function()
		release(ghostPool, pc)
	end)
end

-- 바닥 충격파 고리 (Ring 텍스처)
function Fx.ring(at: Vector3, radius: number, color: Color3, dur: number)
	local piece = table.remove(ringPool)
	if not piece then
		local np = fxPart({ CFrame = HIDDEN, Transparency = 1 })
		local nd = Instance.new("Decal")
		nd.Texture = image("Ring")
		nd.Face = Enum.NormalId.Top
		nd.Parent = np
		piece = { p = np, d = nd }
	end
	local pc = piece :: FxPiece
	local p, d = pc.p, pc.d
	p.Size = Vector3.new(1, 0.05, 1)
	p.CFrame = CFrame.new(at)
	d.Color3 = lighten(color, 0.3)
	d.Transparency = 0
	tween(p, dur, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }, Enum.EasingStyle.Quart)
	tween(d, dur, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(dur + 0.05, function()
		release(ringPool, pc)
	end)
end

-- 떠오르는 글자 (등급 달성, 콤보, 획득 금액)
function Fx.popup(at: Vector3, text: Loc.Text, color: Color3, scale: number, life: number?)
	local holder = fxPart({ Size = Vector3.one, CFrame = CFrame.new(at), Transparency = 1 })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240 * scale, 70 * scale)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Parent = holder
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	Ui.font(l, "title")
	l.TextScaled = true
	Loc.apply(l, text)
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.fromRGB(30, 24, 40)
	l.TextStrokeTransparency = 0
	l.Parent = bb
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.2
	uiScale.Parent = l
	tween(uiScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	local dur = life or 0.9
	tween(holder, dur, { CFrame = CFrame.new(at + Vector3.new(0, 4 + scale * 2, 0)) }, Enum.EasingStyle.Quad)
	task.delay(dur * 0.55, function()
		tween(l, dur * 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(dur + 0.05, function()
		holder:Destroy()
	end)
end

function Fx.nearCamera(at: Vector3, dist: number): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - at).Magnitude <= dist
end

------------------------------------------------------------------------
-- UI 반응
------------------------------------------------------------------------

-- 장음계 (구매 연속음, 공개 차임)
Fx.SCALE_UP = { 0, 2, 4, 5, 7, 9, 11, 12 }

-- 구매 성공 (UI): 카칭 + 버튼 튕김
-- 연속 구매일수록 음높이가 장음계로 올라감(최대 1옥타브), 1.5초 쉬면 처음부터 (docs/14 §3.3-3)
local streak, streakAt = 0, 0
function Fx.purchase(button: GuiObject?)
	local now = os.clock()
	streak = if now - streakAt <= 1.5 then math.min(streak + 1, #Fx.SCALE_UP) else 1
	streakAt = now
	Fx.sound("Coin", nil, 0.45, 2 ^ (Fx.SCALE_UP[streak] / 12))
	Ui.sound("purchase") -- theme layer on top (default: none)
	if button then
		local s = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = button
		s.Scale = 1.15
		tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Elastic)
	end
end

-- HUD 숫자 튕김 (돈이 크게 늘 때)
function Fx.bump(gui: GuiObject, amount: number)
	local s = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = gui
	s.Scale = 1 + amount
	tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

------------------------------------------------------------------------
-- 화면 배너 (기록 갱신·최고 등급): 가운데 위, 햇살 회전 + 아이콘 + 큰 글자 (docs/18 §3)
------------------------------------------------------------------------

local bannerGui = Instance.new("ScreenGui")
bannerGui.Name = "FxBanner"
bannerGui.IgnoreGuiInset = true
bannerGui.DisplayOrder = 45
bannerGui.ResetOnSpawn = false
bannerGui.Parent = player:WaitForChild("PlayerGui")
Ui.fitScale(bannerGui)
local bannerQueue: { () -> () } = {}
local bannerBusy = false

local function nextBanner()
	-- 게임이 잠시 미루라고 하면(예: 보스 레이드 중) 1초마다 다시 본다
	if bannerQueue[1] and bannerHold and bannerHold() then
		bannerBusy = true
		task.delay(1, nextBanner)
		return
	end
	local job = table.remove(bannerQueue, 1)
	if not job then
		bannerBusy = false
		return
	end
	bannerBusy = true
	job()
end

-- text·sub: 영어 원문(자동 번역) 또는 Loc.msg(키, 매개변수). iconName: Ui 아이콘 이름 (Sunburst 배경은 있으면)
function Fx.banner(text: Loc.Text, iconName: string, color: Color3, sub: Loc.Text)
	table.insert(bannerQueue, function()
		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.3)
		root.Size = UDim2.fromOffset(520, 150)
		root.BackgroundTransparency = 1
		root.Parent = bannerGui
		local scale = Instance.new("UIScale")
		scale.Scale = 0.2
		scale.Parent = root
		local burst = Ui.icon("Sunburst", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(340, 340),
			ImageColor3 = lighten(color, 0.3),
			ImageTransparency = 0.25,
			Parent = root,
		})
		if burst then
			Ui.spin(burst, 40)
		end
		local icon = Ui.icon(iconName, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 30),
			Size = UDim2.fromOffset(84, 84),
			Parent = root,
		})
		local subLabel = Instance.new("TextLabel")
		subLabel.AnchorPoint = Vector2.new(0.5, 0)
		subLabel.Position = UDim2.fromOffset(260, 28)
		subLabel.Size = UDim2.fromOffset(420, 32)
		subLabel.BackgroundTransparency = 1
		Ui.font(subLabel, "title")
		subLabel.TextScaled = true
		Loc.apply(subLabel, sub)
		subLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
		subLabel.TextStrokeTransparency = 0
		subLabel.Parent = root
		local main = Instance.new("TextLabel")
		main.AnchorPoint = Vector2.new(0.5, 0)
		main.Position = UDim2.fromOffset(260, 60)
		main.Size = UDim2.fromOffset(520, 76)
		main.BackgroundTransparency = 1
		Ui.font(main, "title")
		main.TextScaled = true
		Loc.apply(main, text)
		main.TextColor3 = lighten(color, 0.2)
		main.Parent = root
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(30, 24, 40)
		stroke.Parent = main
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 220, 120))
		grad.Rotation = 90
		grad.Parent = main
		tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(3, function()
			tween(scale, 0.3, { Scale = 0.6 })
			for _, g in { main, subLabel } do
				tween(g, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
			tween(stroke, 0.3, { Transparency = 1 })
			for _, g in { burst, icon } do
				if g then
					tween(g, 0.3, { ImageTransparency = 1 })
				end
			end
			task.delay(0.35, function()
				root:Destroy()
				nextBanner()
			end)
		end)
	end)
	if not bannerBusy then
		nextBanner()
	end
end

------------------------------------------------------------------------
-- 설정
------------------------------------------------------------------------

-- Game setup, once at boot (before the first effect)
function Fx.configure(opts: Options)
	if opts.sounds then
		for k, v in opts.sounds do
			SOUND_IDS[k] = v
		end
	end
	if opts.soundMax then
		for k, v in opts.soundMax do
			SOUND_MAX[k] = v
		end
	end
	if opts.soundMaxDefault then
		soundMaxDefault = opts.soundMaxDefault
	end
	if opts.images then
		for k, v in opts.images do
			images[k] = v
		end
	end
	if opts.bannerHold then
		bannerHold = opts.bannerHold
	end
end

return Fx
