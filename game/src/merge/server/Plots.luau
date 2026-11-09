--!strict
-- 플롯(섬) 그레이박스 생성과 배정. 8개를 원형으로 배치한다.
-- 각 플롯: 받침 + 유리벽 트레이 + 드로퍼 자리 8개 + 이름표. 큐브는 Plot.Cubes 폴더에 들어간다.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Game.Config)
local Decor = require(script.Parent.Decor)

export type Plot = {
	index: number,
	model: Model,
	center: Vector3, -- 트레이 바닥 윗면 중심
	cubes: Folder,
	dropperParts: { BasePart },
	sign: TextLabel,
	avatar: ImageLabel, -- 공장 위에 뜨는 주인 아바타 얼굴 (rbxthumb 헤드샷)
	owner: Player?,
	bot: string?, -- AI 플레이어(server/Bots)가 쓰는 중이면 그 이름. 사람이 오면 비켜 준다
	walls: { BasePart },
	guards: { BasePart }, -- 벽 위로 이어지는 보이지 않는 벽 4 + 천장 (큐브만 막음)
	floor: BasePart,
	padOut: BasePart, -- 트레이 안 구석 점프 패드 (폭이 바뀌면 따라 옮김)
	width: number, -- 지금 트레이 내부 폭 (트레이 확장 강화로 커짐)
}

local Plots = {}

local plots: { Plot } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- 트레이 위 드로퍼 자리: 4 x 2 격자. 해금 순서는 가운데부터 바깥으로, 앞뒤 번갈아
-- (뒷줄부터 채우면 큐브가 뒷벽에 몰려 카메라에서 HUD에 가려진다 — 플레이테스트 2026-10-18)
local function dropperOffsets(): { Vector3 }
	local half = Config.TRAY_SIZE.X / 2
	local inner, outer = half * 0.25, half * 0.75
	local back, front = -half * 0.35, half * 0.35
	local order = {
		{ -inner, back },
		{ inner, front },
		{ inner, back },
		{ -inner, front },
		{ -outer, back },
		{ outer, front },
		{ outer, back },
		{ -outer, front },
	}
	local out = {}
	for _, xz in order do
		table.insert(out, Vector3.new(xz[1], Config.DROP_HEIGHT, xz[2]))
	end
	return out
end

-- 큐브 탈출 방지: 유리벽 위로 GUARD_TOP까지 보이지 않는 벽 + 천장.
-- 충돌 그룹 TrayGuard는 Cubes하고만 부딪힌다(플레이어·점프 패드 비행은 통과, Factory.init)
local GUARD_TOP = 48
Plots.GUARD_TOP = GUARD_TOP -- 데이터 큐브(SimBackend)의 천장 높이도 이것 (트레이 바닥 윗면 기준)
local function guardSpec(width: number): { { Vector3 } }
	local h0 = Config.TRAY_SIZE.Y
	local gh = GUARD_TOP - h0
	local t = Config.WALL_THICKNESS
	local y = h0 + gh / 2
	return {
		{ Vector3.new(width / 2 + t / 2, y, 0), Vector3.new(t, gh, width + t * 2) },
		{ Vector3.new(-width / 2 - t / 2, y, 0), Vector3.new(t, gh, width + t * 2) },
		{ Vector3.new(0, y, width / 2 + t / 2), Vector3.new(width, gh, t) },
		{ Vector3.new(0, y, -width / 2 - t / 2), Vector3.new(width, gh, t) },
		{ Vector3.new(0, GUARD_TOP + t / 2, 0), Vector3.new(width + t * 2, t, width + t * 2) },
	}
end

-- 섬 밑받침 (2026-10-19 "섬 두께를 늘려서 밑에 깔아두자, 지금은 허공에 떠 있다"):
-- 받침(바닥 y=-1)과 바다 판(Baseplate 윗면 y=-4) 사이가 비어 떠 보였다. 흙 층을 바다 속까지 내리고
-- 물가에 바위 테두리와 모래톱을 둘러 섬이 바다에 박혀 있게 보이게 한다. 꾸밈 전용(충돌·조회 없음)
-- (2026-10-19 "바위·모래가 전부 사각형이라 밋밋하다"): 모래톱은 원판을 겹쳐 물결 같은 둥근 테두리로,
-- 바위는 공·기울인 블록을 겹친 몽돌 무더기 + 조약돌로, 받침 가장자리엔 풀 덩어리를 늘어뜨린다.
-- 바위는 Creator Store 로우폴리 바위 메시 (2026-10-19 "기본 도형 말고 에셋으로", 풀 덩어리는 뺌).
-- 플롯당 파트 약 78개 (흙 1, 모래 41, 바위 36)
local DIRT = Color3.fromRGB(125, 90, 60)
local SAND = Color3.fromRGB(240, 220, 165)
local WET_SAND = Color3.fromRGB(205, 180, 130)
local GRASS = Color3.fromRGB(110, 170, 95) -- build의 Platform 색과 같게
local ROCK_TONES = {
	Color3.fromRGB(150, 144, 138),
	Color3.fromRGB(160, 162, 178),
	Color3.fromRGB(185, 175, 160),
}
local WHITE = Color3.new(1, 1, 1)

local function underside(model: Model, base: Vector3, seed: number)
	local rng = Random.new(seed)
	local w = Config.PLATFORM_SIZE.X
	local top = base.Y - Config.PLATFORM_SIZE.Y / 2
	local water = top - 3 -- 바다 판(Baseplate) 윗면
	local function piece(props: { [string]: any })
		local p = part(props)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
	end
	-- 세운 원판 (실린더 축 X → 위로)
	local function disc(at: Vector3, radius: number, thick: number, color: Color3)
		piece({
			Name = "Shore",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thick, radius * 2, radius * 2),
			CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Sand,
			CastShadow = false,
		})
	end
	-- 변(side 0~3) 좌표계: x는 변을 따라, z는 바깥쪽으로
	local function edge(side: number, along: number, out: number, y: number): Vector3
		local cf = CFrame.new(base.X, y, base.Z) * CFrame.Angles(0, side * math.pi / 2, 0)
		return (cf * CFrame.new(along, 0, w / 2 + out)).Position
	end
	-- 사방으로 기울인 블록 = 각진 바위 한 덩이
	local function stone(at: Vector3, size: Vector3, color: Color3)
		piece({
			Name = "Rock",
			Size = size,
			CFrame = CFrame.new(at)
				* CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.7, 0.7)),
			Color = color,
			Material = Enum.Material.Slate,
		})
	end
	local function pebble(at: Vector3, d: number, color: Color3, material: Enum.Material?)
		piece({
			Name = "Pebble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * d,
			Position = at,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CastShadow = false,
		})
	end

	-- 흙: 받침 바로 밑부터 바다 판 속까지
	local depth = 8
	piece({
		Name = "Dirt",
		Size = Vector3.new(w - 0.6, depth, w - 0.6),
		CFrame = CFrame.new(base.X, top - depth / 2, base.Z),
		Color = DIRT,
		Material = Enum.Material.Ground,
		CastShadow = false,
	})

	-- 모래톱: 얇은 바닥 판 위로 크기가 제각각인 원판을 변마다 4개 + 모서리 1개씩 겹쳐 둥근 물가를 만든다.
	-- 원판마다 한 뼘 넓은 젖은 모래 원판을 아래에 깔아 물가 띠를 그린다
	local sandTop = water + 0.6
	piece({
		Name = "Shore",
		Size = Vector3.new(w + 3, 0.8, w + 3),
		CFrame = CFrame.new(base.X, sandTop - 0.45, base.Z),
		Color = SAND,
		Material = Enum.Material.Sand,
		CastShadow = false,
	})
	local spots: { Vector3 } = {}
	local radii: { number } = {}
	for side = 0, 3 do
		for k = 1, 5 do
			local corner = k == 5 -- 모서리
			local along = if corner then w / 2 else (k - 0.5) / 4 * w - w / 2 + rng:NextNumber(-4, 4)
			table.insert(spots, edge(side, along, if corner then 0 else rng:NextNumber(-0.5, 1.2), 0))
			table.insert(radii, if corner then rng:NextNumber(5, 7) else rng:NextNumber(4.5, 7))
		end
	end
	for i, at in spots do
		local r = radii[i]
		local tint = SAND:Lerp(WHITE, rng:NextNumber(0, 0.12))
		disc(Vector3.new(at.X, sandTop - 0.4 + rng:NextNumber(0, 0.15), at.Z), r, 0.8, tint)
		disc(Vector3.new(at.X, water + 0.05, at.Z), r + rng:NextNumber(1.2, 2), 0.6, WET_SAND)
	end

	-- 바위 (2026-10-19 "기본 도형 말고 에셋으로"): 로우폴리 바위 메시 하나를 톤·크기·방향만 바꿔 쓴다 (server/Decor).
	-- 변마다 물가 무더기 3곳(큰 바위 + 작은 바위) + 모서리 하나 + 물속에 반쯤 잠긴 바위 하나
	local function boulder(at: Vector3, h: number)
		Decor.spawn("rock", at, h, rng:NextNumber(0, math.pi * 2), model, ROCK_TONES[rng:NextInteger(1, #ROCK_TONES)])
	end
	for side = 0, 3 do
		for k = 1, 3 do
			local along = (k - 0.5) / 3 * w - w / 2 + rng:NextNumber(-6, 6)
			boulder(edge(side, along, rng:NextNumber(0.5, 2.5), sandTop - 0.6), rng:NextNumber(3, 4.5))
			local dir = if rng:NextNumber() < 0.5 then -1 else 1
			boulder(
				edge(side, along + rng:NextNumber(3, 4.5) * dir, rng:NextNumber(2.5, 4), sandTop - 0.3),
				rng:NextNumber(1.3, 2)
			)
		end
		boulder(edge(side, w / 2, rng:NextNumber(1, 2), sandTop - 0.8), rng:NextNumber(4, 5.5))
		boulder(edge(side, rng:NextNumber(-w / 3, w / 3), rng:NextNumber(7, 9), water - 1.5), rng:NextNumber(2.5, 3.5))
	end
end

local function build(index: number): Plot
	local angle = (index - 1) / Config.PLOT_COUNT * math.pi * 2
	local base = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.PLOT_RADIUS
	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local platform = part({
		Name = "Platform",
		Size = Config.PLATFORM_SIZE,
		Position = base,
		Color = Color3.fromRGB(110, 170, 95),
		Material = Enum.Material.Grass,
	})
	platform.Parent = model
	underside(model, base, 1000 + index)

	local floorTop = base.Y + Config.PLATFORM_SIZE.Y / 2
	local tray = Config.TRAY_SIZE
	local t = Config.WALL_THICKNESS
	local center = Vector3.new(base.X, floorTop, base.Z)
	local floor = part({
		Name = "TrayFloor",
		Size = Vector3.new(tray.X + t * 2, 1, tray.Z + t * 2),
		Position = center + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(48, 46, 73),
		Material = Enum.Material.SmoothPlastic,
	})
	floor.Parent = model
	center += Vector3.new(0, 1, 0) -- 트레이 바닥 윗면

	local walls = {
		{ Vector3.new(tray.X / 2 + t / 2, tray.Y / 2, 0), Vector3.new(t, tray.Y, tray.Z + t * 2) },
		{ Vector3.new(-tray.X / 2 - t / 2, tray.Y / 2, 0), Vector3.new(t, tray.Y, tray.Z + t * 2) },
		{ Vector3.new(0, tray.Y / 2, tray.Z / 2 + t / 2), Vector3.new(tray.X, tray.Y, t) },
		{ Vector3.new(0, tray.Y / 2, -tray.Z / 2 - t / 2), Vector3.new(tray.X, tray.Y, t) },
	}
	local guardParts: { BasePart } = {}
	for i, g in guardSpec(tray.X) do
		local guard = part({
			Name = "TrayGuard" .. i,
			Size = g[2],
			Position = center + g[1],
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		guard.CollisionGroup = "TrayGuard"
		guard.Parent = model
		table.insert(guardParts, guard)
	end
	local wallParts: { BasePart } = {}
	for i, w in walls do
		local wall = part({
			Name = "Wall" .. i,
			Size = w[2],
			Position = center + w[1],
			Color = Color3.fromRGB(180, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.6,
		})
		wall.Parent = model
		table.insert(wallParts, wall)
	end

	local dropperParts: { BasePart } = {}
	for i, offset in dropperOffsets() do
		local d = part({
			Name = "Dropper" .. i,
			Size = Vector3.new(4, 3, 4),
			Position = center + offset + Vector3.new(0, 2, 0),
			Color = Color3.fromRGB(90, 90, 110),
			Material = Enum.Material.Metal,
			Transparency = 0.8, -- 잠긴 자리는 흐리게, 해금되면 Factory가 0으로
			CanCollide = false,
		})
		d.Parent = model
		table.insert(dropperParts, d)
	end

	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		-- 뒷벽 바로 위. 픽셀 고정 크기면 내 화면 상단 HUD와 겹쳐서 스터드 단위로 (멀수록 작게)
		Position = center + Vector3.new(0, tray.Y + 2.5, -tray.Z / 2 - t),
		Transparency = 1,
		CanCollide = false,
	})
	signPart.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(26, 5)
	billboard.MaxDistance = 250
	billboard.Parent = signPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "Empty factory"
	label.Parent = billboard

	-- 주인 얼굴: 이름표 위에 동그란 아바타 헤드샷 (사용자 요청 2026-10-19). 빈 공장이면 숨김
	local faceGui = Instance.new("BillboardGui")
	faceGui.Name = "OwnerFace"
	faceGui.Size = UDim2.fromScale(12, 12)
	faceGui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0) -- 드로퍼 강화 카드보다 위
	faceGui.MaxDistance = 250
	faceGui.Enabled = false
	faceGui.Parent = signPart
	local faceRing = Instance.new("Frame")
	faceRing.Size = UDim2.fromScale(1, 1)
	faceRing.BackgroundColor3 = Color3.fromRGB(255, 209, 61)
	faceRing.Parent = faceGui
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = faceRing
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(30, 24, 40)
	ringStroke.Thickness = 3
	ringStroke.Parent = faceRing
	local avatar = Instance.new("ImageLabel")
	avatar.Size = UDim2.fromScale(0.88, 0.88)
	avatar.Position = UDim2.fromScale(0.5, 0.5)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.BackgroundColor3 = Color3.fromRGB(52, 49, 80)
	avatar.Image = ""
	avatar.Parent = faceRing
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	-- 시점 비컨: 바닥에 빛나는 원 + 위로 올라가는 빛 + "FACTORY VIEW" 글자
	local padPos = Vector3.new(base.X, floorTop + 0.15, base.Z + Config.VIEW_PAD_Z)
	local pad = part({
		Name = "ViewPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, Config.VIEW_PAD_RADIUS * 2, Config.VIEW_PAD_RADIUS * 2),
		CFrame = CFrame.new(padPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 200, 255),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
	})
	pad.Parent = model
	local ring = part({
		Name = "ViewPadRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, Config.VIEW_PAD_RADIUS * 2 + 1.2, Config.VIEW_PAD_RADIUS * 2 + 1.2),
		CFrame = CFrame.new(padPos - Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 150, 230),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	ring.Parent = model
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glow.Color = ColorSequence.new(Color3.fromRGB(150, 230, 255))
	glow.Size = NumberSequence.new(0.6, 0)
	glow.Lifetime = NumberRange.new(1, 1.6)
	glow.Rate = 8
	glow.Speed = NumberRange.new(3, 5)
	glow.SpreadAngle = Vector2.new(10, 10)
	glow.EmissionDirection = Enum.NormalId.Right -- 실린더는 X축이 위
	glow.LightEmission = 1
	glow.Parent = pad
	local padSign = Instance.new("BillboardGui")
	padSign.Size = UDim2.fromScale(10, 1.6)
	-- 오프셋은 파트 축 기준이다. 실린더를 Z로 90° 눕혀서 파트 X축 = 월드 위쪽 (Y로 주면 옆으로 밀려 원과 겹쳤음, 2026-10-19)
	padSign.StudsOffsetWorldSpace = Vector3.new(7, 0, 0) -- 캐릭터 머리 위
	padSign.MaxDistance = 80
	padSign.Parent = pad
	local padText = Instance.new("TextLabel")
	padText.Size = UDim2.fromScale(1, 1)
	padText.BackgroundTransparency = 1
	padText.Font = Enum.Font.FredokaOne
	padText.TextScaled = true
	padText.Text = "FACTORY VIEW"
	padText.TextColor3 = Color3.fromRGB(170, 235, 255)
	padText.TextStrokeTransparency = 0.2
	padText.Parent = padSign

	-- 점프 패드: 밖(앞 왼쪽) → 트레이 안으로, 안(앞 왼쪽 구석) → 시점 비컨으로. 발사는 클라(client/JumpPads)
	local function jumpPad(name: string, kind: string, at: Vector3, color: Color3): Part
		local p = part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 5, 5),
			CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		p:SetAttribute("JumpPad", kind)
		local arrow = Instance.new("BillboardGui")
		arrow.Size = UDim2.fromScale(4, 2)
		arrow.StudsOffsetWorldSpace = Vector3.new(2.5, 0, 0) -- 파트 X축 = 월드 위 (눕힌 실린더)
		arrow.MaxDistance = 70
		arrow.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = if kind == "in" then "JUMP IN!" else "JUMP OUT"
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.2
		t.Parent = arrow
		p.Parent = model
		return p
	end
	jumpPad("JumpPadIn", "in", Vector3.new(base.X - 33, floorTop + 0.3, base.Z + 26), Color3.fromRGB(255, 170, 80))
	local padOut = jumpPad(
		"JumpPadOut",
		"out",
		center + Vector3.new(-tray.X / 2 + 3.5, 0.3, tray.Z / 2 - 3.5),
		Color3.fromRGB(120, 255, 160)
	)

	local cubes = Instance.new("Folder")
	cubes.Name = "Cubes"
	cubes.Parent = model

	model:SetAttribute("PlotIndex", index)
	model.Parent = workspace:FindFirstChild("Plots")
		or (function()
			local f = Instance.new("Folder")
			f.Name = "Plots"
			f.Parent = workspace
			return f
		end)()

	return {
		index = index,
		model = model,
		center = center,
		cubes = cubes,
		dropperParts = dropperParts,
		sign = label,
		avatar = avatar,
		owner = nil,
		bot = nil,
		walls = wallParts,
		guards = guardParts,
		floor = floor,
		padOut = padOut,
		width = tray.X,
	}
end

-- 트레이 폭 바꾸기 (정사각형 유지). 벽·바닥만 옮기고 드로퍼 자리는 그대로
function Plots.setWidth(plot: Plot, width: number)
	if plot.width == width then
		return
	end
	plot.width = width
	local h = Config.TRAY_SIZE.Y
	local t = Config.WALL_THICKNESS
	local c = plot.center
	local spec = {
		{ Vector3.new(width / 2 + t / 2, h / 2, 0), Vector3.new(t, h, width + t * 2) },
		{ Vector3.new(-width / 2 - t / 2, h / 2, 0), Vector3.new(t, h, width + t * 2) },
		{ Vector3.new(0, h / 2, width / 2 + t / 2), Vector3.new(width, h, t) },
		{ Vector3.new(0, h / 2, -width / 2 - t / 2), Vector3.new(width, h, t) },
	}
	for i, w in spec do
		plot.walls[i].Size = w[2]
		plot.walls[i].Position = c + w[1]
	end
	for i, g in guardSpec(width) do
		plot.guards[i].Size = g[2]
		plot.guards[i].Position = c + g[1]
	end
	plot.floor.Size = Vector3.new(width + t * 2, 1, width + t * 2)
	plot.padOut.CFrame = CFrame.new(c + Vector3.new(-width / 2 + 3.5, 0.3, width / 2 - 3.5))
		* CFrame.Angles(0, 0, math.rad(90))
end

function Plots.init()
	-- 충돌 그룹: 플레이어는 큐브와 부딪히지 않음(배트로만 밀기), 가드 벽은 큐브만 막음 (2026-10-18 사용자 요청)
	local PhysicsService = game:GetService("PhysicsService")
	for _, name in { "Cubes", "Players", "TrayGuard" } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Cubes", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("TrayGuard", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("TrayGuard", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("TrayGuard", "TrayGuard", false)
	for i = 1, Config.PLOT_COUNT do
		table.insert(plots, build(i))
	end
end

-- 봇 자리 비우기 (server/Bots가 넣는다): 그 봇을 치우고 Plots.release까지 해야 한다
local evictBot: ((Plot) -> ())? = nil
function Plots.setEvict(f: (Plot) -> ())
	evictBot = f
end

function Plots.claim(player: Player): Plot?
	-- 빈 플롯이 없으면 봇 하나를 내보내고 그 자리를 쓴다 (사람이 봇 때문에 튕기지 않게)
	local free = false
	for _, plot in plots do
		if plot.owner == nil and plot.bot == nil then
			free = true
			break
		end
	end
	if not free and evictBot then
		for _, plot in plots do
			if plot.owner == nil and plot.bot ~= nil then
				evictBot(plot)
				break
			end
		end
	end
	for _, plot in plots do
		if plot.owner == nil and plot.bot == nil then
			plot.owner = player
			plot.sign.Text = player.DisplayName .. "'s Factory"
			plot.avatar.Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=420&h=420`
			local face = plot.avatar:FindFirstAncestorOfClass("BillboardGui")
			if face then
				face.Enabled = true
			end
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			return plot
		end
	end
	return nil
end

-- AI 플레이어 자리: 표지판에 (Bot)을 붙여 사람인 척하지 않는다. 빈 플롯이 없으면 nil
function Plots.claimBot(name: string): Plot?
	for _, plot in plots do
		if plot.owner == nil and plot.bot == nil then
			plot.bot = name
			plot.sign.Text = `{name}'s Factory (Bot)`
			plot.model:SetAttribute("BotName", name)
			return plot
		end
	end
	return nil
end

function Plots.freeCount(): number
	local n = 0
	for _, plot in plots do
		if plot.owner == nil and plot.bot == nil then
			n += 1
		end
	end
	return n
end

function Plots.all(): { Plot }
	return plots
end

function Plots.release(plot: Plot)
	plot.owner = nil
	plot.bot = nil
	plot.model:SetAttribute("BotName", nil)
	plot.sign.Text = "Empty factory"
	plot.avatar.Image = ""
	local face = plot.avatar:FindFirstAncestorOfClass("BillboardGui")
	if face then
		face.Enabled = false
	end
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.model:SetAttribute("StealLockUntil", nil)
	plot.cubes:ClearAllChildren()
	Plots.setWidth(plot, Config.TRAY_SIZE.X)
	for _, d in plot.dropperParts do
		d.Transparency = 0.8
	end
end

-- 플롯 위(트레이 주변)에 있는 다른 플레이어 수 → 협동 보너스
function Plots.visitors(plot: Plot): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= plot.owner then
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - plot.center).Magnitude < Config.PLATFORM_SIZE.X * 0.6 then
				n += 1
			end
		end
	end
	return n
end

-- 친구 보너스 (2026-10-20): 내가 서 있는 공장(내 것이든 친구 것이든)에 함께 있는 친구 수.
-- 양쪽이 같은 공장에 있으면 서로 센다 → 방문한 사람도 주인도 보너스를 받는다
local function rootPos(p: Player): Vector3?
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function plotAt(pos: Vector3): Plot?
	for _, plot in plots do
		if (pos - plot.center).Magnitude < Config.PLATFORM_SIZE.X * 0.6 then
			return plot
		end
	end
	return nil
end

function Plots.friendsTogether(player: Player, areFriends: (Player, Player) -> boolean): number
	local pos = rootPos(player)
	local here = pos and plotAt(pos)
	if not here then
		return 0
	end
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and areFriends(player, other) then
			local opos = rootPos(other)
			if opos and plotAt(opos) == here then
				n += 1
			end
		end
	end
	return n
end

-- 캐릭터를 플롯 가장자리로 (트레이 앞)
function Plots.spawnCFrame(plot: Plot): CFrame
	-- 시점 비컨 바로 옆(비컨 위에 스폰하면 접속하자마자 공장 전체 시점이 되어 어색했다), 트레이를 바라봄
	local front = plot.center + Vector3.new(11, 4, Config.VIEW_PAD_Z + 1)
	return CFrame.lookAt(front, front - Vector3.zAxis)
end

return Plots
