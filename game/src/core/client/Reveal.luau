--!strict
-- Rarity-tiered acquisition cinematics (docs/32 §3-1, docs/33). Core client module.
-- One call per acquisition: Reveal.play(level, { name, color, at?, model?, odds?, sub?, icon?, sting? })
-- level 0..5 (use Rarity.level(p) or Reveal.levelFor(p) for the default 1 / 10 / 1K / 100K / 1M ladder):
--   1 sparkle            sparkle burst + chime + small popup
--   2 beam + popup       + light pillar + shock ring + bigger popup
--   3 dim + beam + shake screen dims from the edges, rising chimes, beam widens, camera shakes, FOV punch, flash,
--                        center banner
--   4 sky split          + sky tint, a glowing rift tears across the sky with a light shaft down to the item,
--                        rainbow flashes, music sting (the server-wide banner comes from the game server:
--                        server Banner.announce, see client Banner)
--   5 full cinematic     3 s: letterbox bars, slow-motion (particle time + music pitch), camera orbits the item,
--                        particle spiral bursts, sky split, unique sting, giant title, final flash
-- Everything is procedural or uses the game's registered Fx sounds/images (no third-party models).
-- Quality: levels above Quality.maxReveal() are shortened (low: max 3, medium: max 4), beams and sky pieces
-- are only spawned while Quality.acquire allows. Reveal.setSkip(true) (player setting) caps every reveal at 2.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Rarity = require(ReplicatedStorage.Core.Rarity)
local Fx = require(script.Parent.Fx)
local Ui = require(script.Parent.Ui)
local Hype = require(script.Parent.Hype)
local Loc = require(script.Parent.Loc)
local Quality = require(script.Parent.Quality)

local player = Players.LocalPlayer

local Reveal = {}

export type Options = {
	name: Loc.Text, -- item name ("GALAXY AURA")
	color: Color3,
	at: Vector3?, -- world position (default: in front of the local character)
	model: Instance?, -- the item in the world; the camera looks at it in level 5
	odds: string?, -- "1 in 1,000,000" (Rarity.oneIn)
	sub: Loc.Text?, -- banner subtitle (default odds or "NEW!")
	icon: string?, -- Ui icon for the banner (default "Star")
	sting: string?, -- Fx sound key for level 4-5 (default "Fanfare")
	music: Sound?, -- background music to duck / slow (default: first playing looped Sound in SoundService)
	onDone: (() -> ())?,
	noBanner: boolean?, -- the game shows its own result card: skip the level 3-5 result banner (the level 5 title stays)
	soft: boolean?, -- keep the scene bright: light edge dim, no dark sky tint, half-strength white flash (the card and lights carry it)
	shaftAbove: number?, -- the sky-split light shaft stops this many studs above `at` (keeps a worn item, e.g. an aura, visible)
}

local skip = false
local busy = 0 -- running level 4-5 reveals

function Reveal.setSkip(on: boolean)
	skip = on
end

function Reveal.levelFor(p: number): number
	return Rarity.level(p)
end

local function rootPos(): Vector3
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position + root.CFrame.LookVector * 6 + Vector3.new(0, 2, 0)
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position + cam.CFrame.LookVector * 20 else Vector3.zero
end

local function modelPos(model: Instance?): Vector3?
	if not model or not model.Parent then
		return nil
	end
	if model:IsA("BasePart") then
		return model.Position
	elseif model:IsA("Model") then
		return model:GetPivot().Position
	elseif model:IsA("Attachment") then
		return model.WorldPosition
	end
	return nil
end

local function findMusic(): Sound?
	for _, s in SoundService:GetDescendants() do
		if s:IsA("Sound") and s.Looped and s.IsPlaying then
			return s
		end
	end
	return nil
end

local function chimes(count: number, span: number, volume: number)
	for i = 1, count do
		task.delay(span * (1 - (1 - i / count) ^ 1.6), function()
			local step = Fx.SCALE_UP[math.min(i, #Fx.SCALE_UP)]
			Fx.sound("Chime", nil, volume + i * 0.04, 2 ^ (step / 12))
		end)
	end
end

-- vertical light pillar at pos; returns a stop function (nil if the beam cap is full)
local function beam(pos: Vector3, color: Color3, width: number, life: number): (() -> ())?
	if not Quality.acquire("beam") then
		return nil
	end
	local pillar = Fx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(120, width * 0.4, width * 0.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 58, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Fx.lighten(color, 0.45),
		Material = Enum.Material.Neon,
		Transparency = 0.9,
	})
	Fx.tween(pillar, life * 0.35, { Size = Vector3.new(120, width, width), Transparency = 0.45 })
	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		Fx.tween(pillar, 0.35, { Size = Vector3.new(120, width * 1.8, width * 1.8), Transparency = 1 })
		task.delay(0.4, function()
			pillar:Destroy()
			Quality.release("beam")
		end)
	end
	task.delay(life, stop)
	return stop
end

local function rainbow(times: number, alpha: number)
	for i = 0, times - 1 do
		task.delay(i * 0.12, function()
			Fx.screenFlash(Color3.fromHSV((i / times) % 1, 0.55, 1), alpha, 0.35)
		end)
	end
end

-- Sky split: tint the world, tear a glowing zigzag rift across the sky, drop a light shaft to pos
local function skySplit(pos: Vector3, color: Color3, hold: number, shaftAbove: number?, soft: boolean?)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "RevealTint"
	cc.Parent = Lighting
	Fx.tween(cc, 0.4, {
		TintColor = Fx.lighten(color, if soft then 0.85 else 0.55),
		Brightness = if soft then 0.02 else -0.12,
		Contrast = if soft then 0.08 else 0.15,
		Saturation = 0.2,
	})
	task.delay(hold, function()
		Fx.tween(cc, 0.8, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 })
		task.delay(0.85, function()
			cc:Destroy()
		end)
	end)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local tier = Quality.tier()
	local segments = if tier >= 3 then 9 elseif tier == 2 then 5 else 0
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local right = flat:Cross(Vector3.yAxis)
	local center = cam.CFrame.Position + flat * 260 + Vector3.new(0, 150, 0)
	local pieces: { BasePart } = {}
	local prev = center - right * 160
	for i = 1, segments do
		if not Quality.acquire("part") then
			break
		end
		local nextPoint = center
			- right * 160
			+ right * (320 * i / segments)
			+ Vector3.new(0, (if i % 2 == 0 then 1 else -1) * (14 + math.random() * 22), 0)
		local mid = (prev + nextPoint) / 2
		local len = (nextPoint - prev).Magnitude
		local seg = Fx.part({
			Size = Vector3.new(0.4, 0.4, len + 2),
			CFrame = CFrame.lookAt(mid, nextPoint),
			Color = Fx.lighten(color, 0.7),
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})
		table.insert(pieces, seg)
		task.delay(i * 0.04, function()
			Fx.tween(seg, 0.5, { Size = Vector3.new(7, 7, len + 2) }, Enum.EasingStyle.Back)
		end)
		prev = nextPoint
	end
	-- light shaft from the rift down to the item
	local shaft: BasePart? = nil
	if tier >= 2 and Quality.acquire("beam") then
		local top = center
		local foot = pos + Vector3.new(0, shaftAbove or 0, 0)
		local len = (top - foot).Magnitude
		local s = Fx.part({
			Size = Vector3.new(2, 2, len),
			CFrame = CFrame.lookAt((top + foot) / 2, foot),
			Color = Fx.lighten(color, 0.5),
			Material = Enum.Material.Neon,
			Transparency = 0.8,
		})
		Fx.tween(s, 0.5, { Size = Vector3.new(14, 14, len), Transparency = 0.45 })
		shaft = s
	end
	task.delay(hold, function()
		for _, p in pieces do
			Fx.tween(p, 0.6, { Size = Vector3.new(0.2, 0.2, p.Size.Z), Transparency = 1 })
		end
		if shaft then
			Fx.tween(shaft, 0.6, { Transparency = 1 })
		end
		task.delay(0.65, function()
			for _, p in pieces do
				p:Destroy()
				Quality.release("part")
			end
			if shaft then
				shaft:Destroy()
				Quality.release("beam")
			end
		end)
	end)
end

-- Letterbox bars + big title (level 5)
local cineGui = Instance.new("ScreenGui")
cineGui.Name = "RevealCinema"
cineGui.IgnoreGuiInset = true
cineGui.DisplayOrder = 44 -- under the Fx banner (45) and flash (50)
cineGui.ResetOnSpawn = false
cineGui.Parent = player:WaitForChild("PlayerGui")

local function bar(top: boolean): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 0)
	f.AnchorPoint = Vector2.new(0, if top then 0 else 1)
	f.Position = UDim2.fromScale(0, if top then 0 else 1)
	f.Parent = cineGui
	return f
end
local topBar, bottomBar = bar(true), bar(false)

local function letterbox(on: boolean)
	local h = if on then 0.13 else 0
	Fx.tween(topBar, 0.35, { Size = UDim2.fromScale(1, h) })
	Fx.tween(bottomBar, 0.35, { Size = UDim2.fromScale(1, h) })
end

local function title(text: Loc.Text, sub: string?, color: Color3, life: number)
	local main = Instance.new("TextLabel")
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.78)
	main.Size = UDim2.fromScale(0.8, 0.12)
	main.BackgroundTransparency = 1
	Ui.font(main, "title")
	main.TextScaled = true
	main.TextColor3 = Fx.lighten(color, 0.25)
	main.TextStrokeTransparency = 0
	main.TextTransparency = 1
	Loc.apply(main, text)
	main.Parent = cineGui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Fx.lighten(color, 0.1))
	grad.Rotation = 90
	grad.Parent = main
	local subLabel: TextLabel? = nil
	if sub then
		local s = Instance.new("TextLabel")
		s.AnchorPoint = Vector2.new(0.5, 0)
		s.Position = UDim2.fromScale(0.5, 0.84)
		s.Size = UDim2.fromScale(0.5, 0.05)
		s.BackgroundTransparency = 1
		Ui.font(s, "title")
		s.TextScaled = true
		s.TextColor3 = Color3.fromRGB(255, 240, 200)
		s.TextStrokeTransparency = 0
		s.TextTransparency = 1
		Loc.apply(s, sub)
		s.Parent = cineGui
		subLabel = s
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1.6
	scale.Parent = main
	Fx.tween(main, 0.3, { TextTransparency = 0 })
	Fx.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	if subLabel then
		Fx.tween(subLabel, 0.3, { TextTransparency = 0 })
	end
	task.delay(life, function()
		Fx.tween(main, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		if subLabel then
			Fx.tween(subLabel, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		task.delay(0.45, function()
			main:Destroy()
			if subLabel then
				subLabel:Destroy()
			end
		end)
	end)
end

-- Camera orbit around pos for dur seconds, then hand the camera back
local function orbit(pos: Vector3, dur: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local prevType = cam.CameraType
	local start = cam.CFrame
	local offset = start.Position - pos
	local dist = math.clamp(offset.Magnitude, 12, 28)
	local startAng = math.atan2(offset.X, offset.Z)
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	RunService:BindToRenderStep("RevealOrbit", Enum.RenderPriority.Camera.Value, function()
		local t = os.clock() - t0
		local k = math.clamp(t / dur, 0, 1)
		local ease = 1 - (1 - k) ^ 2
		local ang = startAng + ease * math.rad(110)
		local d = dist * (1 - 0.25 * ease)
		local eye = pos + Vector3.new(math.sin(ang) * d, 4 + 3 * ease, math.cos(ang) * d)
		cam.CFrame = CFrame.lookAt(eye, pos)
	end)
	task.delay(dur, function()
		RunService:UnbindFromRenderStep("RevealOrbit")
		cam.CameraType = prevType
		if prevType == Enum.CameraType.Scriptable then
			cam.CFrame = start
		end
	end)
end

local function spiral(pos: Vector3, color: Color3, dur: number)
	local steps = 12
	for i = 0, steps - 1 do
		task.delay(dur * i / steps, function()
			local ang = i / steps * math.pi * 4
			local r = 3 + i * 0.6
			local p = pos + Vector3.new(math.cos(ang) * r, i * 0.5, math.sin(ang) * r)
			Fx.burst("Sparkle", p, 10, 1.2, Color3.fromHSV((i / steps) % 1, 0.5, 1))
			Fx.burst("Glow", p, 1, 1.5, Fx.lighten(color, 0.4))
		end)
	end
end

function Reveal.play(level: number, opts: Options)
	level = math.clamp(math.floor(level), 0, 5)
	if skip then
		level = math.min(level, 2)
	end
	-- never stack cinematics: a big reveal while another is running plays small
	if busy > 0 and level >= 4 then
		level = 2
	end
	level = math.min(level, math.max(Quality.maxReveal(), 2))
	if level <= 0 then
		if opts.onDone then
			task.defer(opts.onDone)
		end
		return
	end
	local color = opts.color
	local pos = modelPos(opts.model) or opts.at or rootPos()
	local sub: Loc.Text = opts.sub or opts.odds or "NEW!"

	if level == 1 then
		Fx.sound("Sparkle", pos, 0.45, 1.3)
		Fx.burst("Sparkle", pos, 12, 0.9, Fx.lighten(color, 0.4))
		Fx.popup(pos + Vector3.new(0, 3, 0), opts.name, Fx.lighten(color, 0.2), 0.9, 1.1)
		if opts.onDone then
			task.delay(1, opts.onDone)
		end
		return
	end

	if level == 2 then
		Fx.sound("Chime", pos, 0.55, 1.2)
		Fx.sound("Sparkle", pos, 0.5, 1.1)
		beam(pos, color, 3, 1.4)
		Fx.ring(pos - Vector3.new(0, 2, 0), 10, color, 0.6)
		Fx.burst("Sparkle", pos, 24, 1.1, Fx.lighten(color, 0.4))
		Fx.burst("Glow", pos, 1, 2, Fx.lighten(color, 0.3))
		Fx.popup(pos + Vector3.new(0, 4, 0), opts.name, Fx.lighten(color, 0.2), 1.3, 1.5)
		if opts.odds then
			task.delay(0.3, function()
				Fx.popup(pos + Vector3.new(0, 6.5, 0), opts.odds :: string, Color3.fromRGB(255, 240, 200), 0.9, 1.4)
			end)
		end
		Fx.shake(0.12)
		if opts.onDone then
			task.delay(1.5, opts.onDone)
		end
		return
	end

	-- 3+: build-up then burst
	Hype.spent(math.min(level, 4))
	local big = level >= 4
	if big then
		busy += 1
	end
	local buildUp = if level >= 5 then 1.6 elseif big then 1.2 else 0.9
	local music = opts.music or findMusic()
	local musicVolume = if music then music.Volume else 0
	local musicSpeed = if music then music.PlaybackSpeed else 1
	if music then
		Fx.tween(music, 0.4, { Volume = musicVolume * 0.2 })
	end
	Fx.dim(if opts.soft then 0.88 else 0.3, 0.4)
	Fx.sound("Whoosh", nil, 0.45, 0.5)
	chimes(if level >= 5 then 8 else 6, buildUp, 0.3)
	local stopBeam = beam(pos, color, 2.5, buildUp + 0.8)
	if level >= 5 then
		letterbox(true)
		Fx.particleTime(0.35)
		if music then
			Fx.tween(music, 0.6, { PlaybackSpeed = musicSpeed * 0.8 })
		end
		orbit(pos, buildUp + 1.6)
	end
	if big then
		skySplit(pos, color, buildUp + (if level >= 5 then 1.8 else 1.2), opts.shaftAbove, opts.soft)
	end
	local t0 = os.clock()
	-- The build-up loop must never write the zoom after the moment clears it. task.delay and RenderStepped run on
	-- different clocks, so a frame could land after the moment with k just under 1 (or the k >= 1 frame itself) and
	-- leave the camera zoomed in (70 -> 62). The moment disconnects the loop first, then clears the zoom.
	local building = true
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not building then
			return
		end
		local k = math.clamp((os.clock() - t0) / buildUp, 0, 1)
		Fx.setZoom(k * (if level >= 5 then 14 else 8))
		Fx.holdShake(k * (if big then 0.45 else 0.3))
		if math.random() < dt * 18 then
			Fx.burst("Sparkle", pos + Vector3.new(0, 1, 0), 2, 0.5 + k, Fx.lighten(color, 0.5))
		end
	end)

	task.delay(buildUp, function()
		-- the moment
		building = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		Fx.setZoom(0)
		Fx.fovPunch(if level >= 5 then 12 elseif big then 10 else 7)
		Fx.screenFlash(Color3.new(1, 1, 1), (if big then 0.9 else 0.7) * (if opts.soft then 0.45 else 1), 0.6)
		Fx.shake(if big then 0.7 else 0.45)
		Fx.sound("Boom", nil, 0.55, if level >= 5 then 0.8 else 0.95)
		Fx.sound(opts.sting or "Fanfare", nil, 0.7, if level >= 5 then 0.9 else 1)
		if level >= 5 then
			Fx.sound("LevelUp", nil, 0.5, 0.8)
		end
		Fx.burst("Glow", pos, 3, 4, Fx.lighten(color, 0.3))
		Fx.burst("Sparkle", pos, if big then 60 else 36, 1.6, Fx.lighten(color, 0.4))
		Fx.burst("Chunk", pos, if big then 40 else 20, 1.3, color)
		Fx.ring(pos - Vector3.new(0, 2, 0), if big then 40 else 24, color, 0.8)
		if big then
			rainbow(if level >= 5 then 10 else 6, if opts.soft then 0.2 else 0.4)
		end
		if level >= 5 then
			spiral(pos, color, 1.4)
			title(opts.name, opts.odds, color, 2.2)
		elseif not opts.noBanner then
			Fx.banner(opts.name, opts.icon or "Star", color, sub)
		end
		if stopBeam then
			task.delay(0.4, stopBeam)
		end
		local after = if level >= 5 then 1.6 else 0.5
		task.delay(after, function()
			Fx.dim(1, 0.5)
			if level >= 5 then
				letterbox(false)
				Fx.particleTime(1)
				if not opts.noBanner then
					Fx.banner(opts.name, opts.icon or "Star", color, sub)
				end
			end
			if music then
				Fx.tween(music, 1.5, { Volume = musicVolume, PlaybackSpeed = musicSpeed })
			end
			if big then
				busy -= 1
			end
			if opts.onDone then
				opts.onDone()
			end
		end)
	end)
end

return Reveal
