--!strict
-- 월드 꾸밈 (2026-10-18 사용자 요청): 가운데 광장 섬 + 전체 유저 랭킹 게시판 + 플롯으로 가는 다리 + 나무·바위·떠 있는 큐브.
-- 전부 서버에서 한 번 만드는 고정 파트(앵커). 나무·바위·섬 받침은 Creator Store 메시(server/Decor, 스크립트 없음). 랭킹은 Leaderboard 캐시를 10초마다 그린다.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local RankBoards = require(Shared.RankBoards)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Leaderboard = require(script.Parent.Leaderboard)
local Decor = require(script.Parent.Decor)

local World = {}

local TOP = 1 -- 플롯 받침 윗면 높이 (Plots: 받침 중심 y=0, 두께 2)
local PLAZA_R = 50
local rng = Random.new(20261018) -- 서버마다 같은 배치

local folder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = props.Parent or folder
	return p
end

-- 바닥에 누운 원판 (실린더 축 X → 세움)
local function disc(at: Vector3, radius: number, thick: number, color: Color3, material: Enum.Material): Part
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, radius * 2, radius * 2),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

------------------------------------------------------------------------
-- 소품
------------------------------------------------------------------------

local LEAF_COLORS = {
	Color3.fromRGB(110, 210, 90),
	Color3.fromRGB(80, 190, 110),
	Color3.fromRGB(255, 160, 200), -- 벚꽃
	Color3.fromRGB(255, 200, 90), -- 가을
}

-- 솜사탕 나무 잎 (기존 파스텔 큐브 톤에 맞춤)
local CANDY_COLORS = {
	Color3.fromRGB(255, 180, 215), -- 분홍
	Color3.fromRGB(200, 175, 255), -- 라벤더
	Color3.fromRGB(160, 225, 255), -- 하늘
	Color3.fromRGB(170, 240, 200), -- 민트
}

-- 나무·바위 (2026-10-19 "기본 도형으로 만들어서 별로, 에셋 찾아서 써라"): Creator Store 메시 (server/Decor, 출처는 거기)
-- 나무: 둥근 나무(텍스처) 35%, 색 바꾼 나무 40%(초록·벚꽃·가을·파스텔 솜사탕), 야자 25%. leaf를 주면 그 색의 나무
local function tree(at: Vector3, scale: number, leaf: Color3?)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local h = rng:NextNumber(13, 16) * scale
	if leaf then
		Decor.spawn("treeXenon", at, h, yaw, folder, leaf)
		return
	end
	local roll = rng:NextNumber()
	if roll < 0.35 then
		Decor.spawn("treeAndy", at, h, yaw, folder)
	elseif roll < 0.75 then
		local pool = if rng:NextNumber() < 0.5 then LEAF_COLORS else CANDY_COLORS
		Decor.spawn("treeXenon", at, h, yaw, folder, pool[rng:NextInteger(1, #pool)])
	else
		Decor.spawn("palm", at, h * 1.1, yaw, folder)
	end
end

-- 바위 톤 (따뜻한 회색 ~ 푸른 회색)
local ROCK_TONES = {
	Color3.fromRGB(150, 150, 165),
	Color3.fromRGB(135, 128, 120),
	Color3.fromRGB(170, 165, 158),
}

-- 바위 무더기: 큰 바위 + 작은 바위 둘 (같은 로우폴리 바위 메시를 톤·크기만 바꿈)
local function rock(at: Vector3, scale: number)
	local tone = ROCK_TONES[rng:NextInteger(1, #ROCK_TONES)]
	Decor.spawn("rock", at - Vector3.new(0, 0.8, 0), 4 * scale, rng:NextNumber(0, math.pi * 2), folder, tone)
	local a = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	Decor.spawn(
		"rock",
		at + dir * 3 * scale - Vector3.new(0, 0.6, 0),
		2 * scale,
		a,
		folder,
		tone:Lerp(Color3.new(1, 1, 1), 0.1)
	)
	Decor.spawn("rock", at - dir * 2.6 * scale - Vector3.new(0, 0.4, 0), 1.2 * scale, -a, folder, tone)
end

local function flowers(at: Vector3, radius: number)
	disc(at + Vector3.new(0, 0.3, 0), radius, 0.6, Color3.fromRGB(110, 75, 50), Enum.Material.Ground)
	for _ = 1, math.floor(radius * 2.5) do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, radius - 0.6)
		part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			Position = at + Vector3.new(math.cos(a) * d, 1, math.sin(a) * d),
			Color = Color3.fromHSV(rng:NextNumber(), 0.55, 1),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end
end

local function lamp(at: Vector3)
	part({
		Name = "LampPost",
		Size = Vector3.new(0.8, 9, 0.8),
		Position = at + Vector3.new(0, 4.5, 0),
		Color = Color3.fromRGB(60, 55, 80),
		Material = Enum.Material.Metal,
	})
	local bulb = part({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		Position = at + Vector3.new(0, 9.6, 0),
		Color = Color3.fromRGB(255, 230, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 220, 150)
	light.Parent = bulb
end

local function bench(at: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(at, at + facing)
	part({
		Name = "BenchSeat",
		Size = Vector3.new(6, 0.5, 2),
		CFrame = cf * CFrame.new(0, 1.6, 0),
		Color = Color3.fromRGB(190, 130, 80),
		Material = Enum.Material.Wood,
	})
	part({
		Name = "BenchBack",
		Size = Vector3.new(6, 2, 0.4),
		CFrame = cf * CFrame.new(0, 2.8, 1),
		Color = Color3.fromRGB(170, 115, 70),
		Material = Enum.Material.Wood,
	})
	for _, x in { -2.5, 2.5 } do
		part({
			Name = "BenchLeg",
			Size = Vector3.new(0.4, 1.4, 1.6),
			CFrame = cf * CFrame.new(x, 0.7, 0),
			Color = Color3.fromRGB(60, 55, 80),
			Material = Enum.Material.Metal,
		})
	end
end

-- 웃는 장식 큐브 (게임 큐브와 같은 얼굴). bob이면 위아래로 둥실
local function faceCube(at: Vector3, size: number, color: Color3, tier: number, bob: boolean, spin: boolean): Part
	local p = part({
		Name = "DecoCube",
		Size = Vector3.one * size,
		CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local d = Instance.new("Decal")
		d.Name = "Face"
		d.Texture = Config.faceFor(tier)
		d.Face = face
		d.Parent = p
	end
	if bob then
		local info = TweenInfo.new(rng:NextNumber(2.5, 4), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(p, info, { CFrame = p.CFrame + Vector3.new(0, size * 0.25, 0) }):Play()
	end
	if spin then
		local info = TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
		TweenService:Create(p, info, { Orientation = p.Orientation + Vector3.new(0, 360, 0) }):Play()
	end
	return p
end

------------------------------------------------------------------------
-- 랭킹 게시판 (광장 가운데). 보드마다 한 면: 제목 + 상위 10명, 1~3위는 얼굴 사진
------------------------------------------------------------------------

type BoardGui = { rows: { { rank: TextLabel, name: TextLabel, value: TextLabel, photo: ImageLabel? } }, sub: TextLabel }
local boards: { [string]: BoardGui } = {}
local photoCache: { [number]: string } = {}
local ROWS = 10

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function makeBoard(cf: CFrame, title: string, accent: Color3): BoardGui
	local w, h = 26, 30
	local board = part({
		Name = "RankBoard",
		Size = Vector3.new(w, h, 1),
		CFrame = cf * CFrame.new(0, h / 2, 0),
		Color = Color3.fromRGB(35, 30, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	-- 테두리 (네온)
	for _, spec in
		{
			{ Vector3.new(w + 1, 1, 1.3), Vector3.new(0, h / 2, 0) },
			{ Vector3.new(w + 1, 1, 1.3), Vector3.new(0, -h / 2, 0) },
			{ Vector3.new(1, h + 1, 1.3), Vector3.new(w / 2, 0, 0) },
			{ Vector3.new(1, h + 1, 1.3), Vector3.new(-w / 2, 0, 0) },
		}
	do
		part({
			Name = "BoardFrame",
			Size = spec[1],
			CFrame = board.CFrame * CFrame.new(spec[2]),
			Color = accent,
			Material = Enum.Material.Neon,
		})
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(520, 600)
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Parent = board
	label(gui, {
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 8),
		Text = title,
		TextColor3 = accent,
	})
	local sub = label(gui, {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 76),
		Text = "ALL SERVERS",
		TextColor3 = Color3.fromRGB(200, 195, 230),
	})
	local rows = {}
	for i = 1, ROWS do
		local y = 108 + (i - 1) * 48
		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(1, -20, 0, 44)
		bg.Position = UDim2.fromOffset(10, y)
		bg.BackgroundColor3 = if i == 1
			then Color3.fromRGB(120, 95, 30)
			elseif i == 2 then Color3.fromRGB(90, 90, 110)
			elseif i == 3 then Color3.fromRGB(110, 70, 45)
			else Color3.fromRGB(50, 45, 80)
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = bg
		local rank = label(bg, {
			Size = UDim2.fromOffset(56, 36),
			Position = UDim2.fromOffset(4, 4),
			Text = `#{i}`,
			TextColor3 = if i <= 3 then Color3.fromRGB(255, 220, 90) else Color3.new(1, 1, 1),
		})
		local photo: ImageLabel? = nil
		if i <= 3 then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromOffset(38, 38)
			img.Position = UDim2.fromOffset(62, 3)
			img.BackgroundColor3 = Color3.fromRGB(30, 25, 50)
			img.Parent = bg
			local c2 = Instance.new("UICorner")
			c2.CornerRadius = UDim.new(1, 0)
			c2.Parent = img
			photo = img
		end
		local name = label(bg, {
			Size = UDim2.new(1, -260, 0, 32),
			Position = UDim2.fromOffset(if i <= 3 then 108 else 66, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "-",
		})
		local value = label(bg, {
			Size = UDim2.fromOffset(150, 32),
			Position = UDim2.new(1, -158, 0, 6),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(130, 240, 150),
			Text = "",
		})
		table.insert(rows, { rank = rank, name = name, value = value, photo = photo })
	end
	return { rows = rows, sub = sub }
end

local function photoOf(userId: number): string
	local cached = photoCache[userId]
	if cached then
		return cached
	end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	local result = if ok and url then url else ""
	photoCache[userId] = result
	return result
end

local function refreshBoards()
	for _, b in RankBoards do
		local gui = boards[b.id]
		if not gui then
			continue
		end
		local list, live = Leaderboard.top(b.id)
		gui.sub.Text = if live then "ALL SERVERS" else "THIS SERVER"
		for i, row in gui.rows do
			local e = list[i]
			row.name.Text = if e then e.name else "-"
			row.value.Text = if not e
				then ""
				elseif b.id == "income" then `${Format.short(e.value)}/s`
				else Format.short(e.value)
			if row.photo then
				row.photo.Image = if e and e.userId > 0 then photoOf(e.userId) else ""
				row.photo.Visible = e ~= nil
			end
		end
	end
end

------------------------------------------------------------------------
-- 배치
------------------------------------------------------------------------

local function plaza()
	local base = Vector3.new(0, TOP, 0)
	-- 섬: 모래 테두리 + 잔디 + 돌바닥 원 두 겹
	disc(base - Vector3.new(0, 3.2, 0), PLAZA_R + 6, 5.6, Color3.fromRGB(235, 215, 160), Enum.Material.Sand)
	disc(base - Vector3.new(0, 1, 0), PLAZA_R, 2, Color3.fromRGB(110, 170, 95), Enum.Material.Grass)
	disc(base + Vector3.new(0, 0.05, 0), PLAZA_R * 0.62, 0.3, Color3.fromRGB(215, 205, 190), Enum.Material.Pebble)
	disc(base + Vector3.new(0, 0.12, 0), PLAZA_R * 0.42, 0.3, Color3.fromRGB(190, 175, 220), Enum.Material.Slate)
	-- 가운데 받침 + 황금 큐브 조형물 (천천히 돌며 둥실)
	disc(base + Vector3.new(0, 1, 0), 9, 2, Color3.fromRGB(80, 70, 120), Enum.Material.Marble)
	disc(base + Vector3.new(0, 2.2, 0), 7, 0.5, Color3.fromRGB(255, 210, 90), Enum.Material.Neon)
	-- 게시판(높이 ~35) 위에 떠서 어느 플롯에서도 보이는 랜드마크
	local statue = faceCube(base + Vector3.new(0, 52, 0), 10, Color3.fromRGB(255, 200, 60), 8, false, true)
	statue.Material = Enum.Material.Metal
	statue.Reflectance = 0.25
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
	sparkle.Size = NumberSequence.new(1, 0)
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Parent = statue
	local glow = Instance.new("PointLight")
	glow.Range = 40
	glow.Brightness = 2
	glow.Color = Color3.fromRGB(255, 220, 140)
	glow.Parent = statue

	-- 게시판 두 개: 조형물 앞뒤, 바깥을 향함
	local accents = { Color3.fromRGB(255, 209, 61), Color3.fromRGB(120, 220, 255) }
	for i, b in RankBoards do
		if (b :: any).plaza == false then
			continue
		end
		local side = if i == 1 then 1 else -1
		local at = base + Vector3.new(0, 0.3, side * 16)
		local cf = CFrame.lookAt(at, at + Vector3.new(0, 0, side * 10))
		-- 받침 다리
		for _, x in { -10, 10 } do
			part({
				Name = "BoardLeg",
				Size = Vector3.new(1.5, 4, 1.5),
				CFrame = cf * CFrame.new(x, 2, 0),
				Color = Color3.fromRGB(60, 55, 80),
				Material = Enum.Material.Metal,
			})
		end
		boards[b.id] = makeBoard(cf * CFrame.new(0, 4, 0), b.title, accents[i])
	end

	-- 가로등 8개 + 벤치 + 화단 + 나무 (다리 방향은 비운다)
	for i = 1, Config.PLOT_COUNT do
		local a = (i - 0.5) / Config.PLOT_COUNT * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		lamp(base + dir * (PLAZA_R * 0.62 + 2))
		if i % 2 == 0 then
			bench(base + dir * (PLAZA_R * 0.5), -dir)
			flowers(base + dir * (PLAZA_R * 0.82), 3.5)
		else
			tree(base + dir * (PLAZA_R * 0.84), rng:NextNumber(0.9, 1.3))
		end
	end
end

-- 광장 → 플롯 다리 (나무 판자 + 난간 기둥)
local function bridges()
	for i = 1, Config.PLOT_COUNT do
		local a = (i - 1) / Config.PLOT_COUNT * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		-- 정사각 받침의 가장자리까지 (대각선 플롯은 더 멀리 있음)
		local half = Config.PLATFORM_SIZE.X / 2
		local edge = Config.PLOT_RADIUS - half / math.max(math.abs(dir.X), math.abs(dir.Z))
		local from = dir * (PLAZA_R - 2) + Vector3.new(0, TOP - 0.4, 0)
		local to = dir * (edge + 2) + Vector3.new(0, TOP - 0.4, 0)
		local len = (to - from).Magnitude
		local cf = CFrame.lookAt((from + to) / 2, to)
		part({
			Name = "Bridge",
			Size = Vector3.new(10, 1, len),
			CFrame = cf,
			Color = Color3.fromRGB(190, 135, 85),
			Material = Enum.Material.WoodPlanks,
		})
		for z = -len / 2 + 3, len / 2 - 3, 8 do
			for _, x in { -5.2, 5.2 } do
				part({
					Name = "Rail",
					Size = Vector3.new(0.8, 3, 0.8),
					CFrame = cf * CFrame.new(x, 1.8, z),
					Color = Color3.fromRGB(150, 100, 60),
					Material = Enum.Material.Wood,
				})
			end
		end
	end
end

-- 플롯 뒤쪽 모서리 나무, 바다 위 작은 섬, 떠 있는 큐브
local function scenery()
	for i = 1, Config.PLOT_COUNT do
		local a = (i - 1) / Config.PLOT_COUNT * math.pi * 2
		local c = Vector3.new(math.cos(a), 0, math.sin(a)) * Config.PLOT_RADIUS
		local half = Config.PLATFORM_SIZE.X / 2 - 4
		-- 플롯 뒤쪽(-Z) 두 모서리 + 오른쪽 앞 화단 (앞 왼쪽은 점프 패드, 가운데 앞은 시점 비컨)
		tree(c + Vector3.new(-half, TOP, -half), rng:NextNumber(0.9, 1.2))
		tree(c + Vector3.new(half, TOP, -half), rng:NextNumber(0.9, 1.2))
		flowers(c + Vector3.new(half - 2, TOP, half - 2), 3)
		rock(c + Vector3.new(half, TOP + 0.5, 6), 0.7)
	end
	-- 플롯 사이 바다의 작은 섬 (나무 + 바위) 과 둥실 큐브
	for i = 1, Config.PLOT_COUNT do
		local a = (i - 0.5) / Config.PLOT_COUNT * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local islet = dir * (Config.PLOT_RADIUS + rng:NextNumber(-10, 25))
		local isletR = rng:NextNumber(9, 13)
		disc(islet + Vector3.new(0, -3, 0), isletR, 3, Color3.fromRGB(235, 215, 160), Enum.Material.Sand)
		-- 물가의 젖은 모래 띠
		disc(islet + Vector3.new(0, -3.85, 0), isletR + 1.6, 0.6, Color3.fromRGB(205, 180, 130), Enum.Material.Sand)
		tree(islet + Vector3.new(rng:NextNumber(-3, 3), -1.5, rng:NextNumber(-3, 3)), rng:NextNumber(1, 1.5))
		rock(islet + Vector3.new(5, -1, -4), 1)
		local band = Config.TIER_COLORS[rng:NextInteger(1, 24)] or Color3.new(1, 1, 1)
		faceCube(
			dir * (Config.PLOT_RADIUS + 70) + Vector3.new(0, rng:NextNumber(4, 14), 0),
			rng:NextNumber(7, 12),
			band,
			rng:NextInteger(1, 16),
			true,
			false
		)
	end
	-- 바깥 먼 바다에 큰 큐브 몇 개 (지평선 장식)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		faceCube(
			dir * rng:NextNumber(280, 320) + Vector3.new(0, rng:NextNumber(8, 30), 0),
			rng:NextNumber(18, 28),
			Color3.fromHSV(rng:NextNumber(), 0.45, 1),
			rng:NextInteger(1, 16),
			true,
			false
		)
	end
end

local function lighting()
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.25
	atm.Haze = 1
	atm.Color = Color3.fromRGB(200, 220, 255)
	atm.Decay = Color3.fromRGB(150, 170, 230)
	atm.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 16
	bloom.Threshold = 2
	bloom.Parent = Lighting
end

function World.init()
	folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = workspace
	plaza()
	bridges()
	scenery()
	lighting()
	task.spawn(function()
		while true do
			task.wait(2) -- 첫 캐시가 채워진 뒤
			pcall(refreshBoards)
			task.wait(8)
		end
	end)
end

return World
