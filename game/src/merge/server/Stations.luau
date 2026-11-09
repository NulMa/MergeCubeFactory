--!strict
-- 광장 발판 (2026-10-20 사용자 "버튼이 너무 많아질 것 같으면 중앙 광장에 오브젝트 + 비컨, 위에 올라갈 때만 탭"):
--   BOSS SHOP (보스 코인 강화), PET EGGS (알 뽑기). 발판 위 공중에 상징 오브젝트, 하늘로 빛기둥.
--   서버는 모양만 만든다. 올라섰는지는 클라(client/Stations)가 재고 패널을 연다 (상점 구매는 원래 원격 그대로 검증).
--   workspace.Stations.<Kind> 모델: 속성 Kind, Radius, Center(Vector3)

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Game.Config)
local Economy = require(ReplicatedStorage.Game.Economy)

local Stations = {}

local RADIUS = 5.5 -- 발판 반지름 (studs)
local RING = 24 -- 광장 가운데에서 발판까지 (게시판 z±16·벤치·가로등 사이 빈자리)

type Def = { kind: string, title: string, sub: string, color: Color3, angle: number }
local DEFS: { Def } = {
	{
		kind = "boss",
		title = "BOSS SHOP",
		sub = "Spend BOSS COINS",
		color = Color3.fromRGB(170, 90, 255),
		angle = math.rad(22.5),
	},
	{
		kind = "eggs",
		title = "PET EGGS",
		sub = "Hatch pets with shards",
		color = Color3.fromRGB(90, 220, 140),
		angle = math.rad(202.5),
	},
}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- 둥실 떠서 천천히 도는 상징 (Tween 반복, 스크립트 없음)
local function floaty(p: BasePart, spin: boolean)
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(p, info, { Position = p.Position + Vector3.new(0, 0.8, 0) }):Play()
	if spin then
		TweenService:Create(p, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
			Orientation = p.Orientation + Vector3.new(0, 360, 0),
		}):Play()
	end
end

-- 보스 코인 상점: 작은 보스 큐브 (보라 + 얼굴 + 금 왕관 테)
local function bossIcon(model: Model, at: Vector3, color: Color3)
	local cube = part(model, {
		Name = "Icon",
		Size = Vector3.one * 3.4,
		CFrame = CFrame.new(at),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local d = Instance.new("Decal")
		d.Texture = Config.faceFor(Economy.MAX_TIER)
		d.Face = face
		d.Parent = cube
	end
	local crown = part(model, {
		Name = "Crown",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 4.2, 4.2),
		CFrame = CFrame.new(at + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 205, 60),
		Material = Enum.Material.Metal,
	})
	floaty(cube, true)
	floaty(crown, false)
end

-- 알 상점: 큰 알 (점박이 대신 은은한 빛)
local function eggIcon(model: Model, at: Vector3, color: Color3)
	local egg = part(model, {
		Name = "Icon",
		Size = Vector3.new(3.2, 4.2, 3.2),
		CFrame = CFrame.new(at),
		Color = Color3.fromRGB(255, 250, 235),
		Material = Enum.Material.SmoothPlastic,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local band = part(model, {
		Name = "Band",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 3.35, 3.35),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
	})
	floaty(egg, true)
	floaty(band, false)
end

local function build(folder: Folder, def: Def, center: Vector3)
	local dir = Vector3.new(math.cos(def.angle), 0, math.sin(def.angle))
	local at = center + dir * RING
	local model = Instance.new("Model")
	model.Name = def.kind
	model:SetAttribute("Kind", def.kind)
	model:SetAttribute("Radius", RADIUS)
	model:SetAttribute("Center", at)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	-- 발판: 빛나는 테 + 짙은 판 (살짝 솟아 밟는 느낌)
	part(model, {
		Name = "PadRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, RADIUS * 2 + 0.8, RADIUS * 2 + 0.8),
		CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)) * flat,
		Color = def.color,
		Material = Enum.Material.Neon,
		CanCollide = true,
	})
	part(model, {
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, RADIUS * 2, RADIUS * 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * flat,
		Color = Color3.fromRGB(45, 40, 60),
		Material = Enum.Material.Slate,
		CanCollide = true,
	})
	-- 빛기둥 (비컨): 멀리서도 보이게 하늘로
	local beam = part(model, {
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(120, 2.2, 2.2),
		CFrame = CFrame.new(at + Vector3.new(0, 72, 0)) * flat,
		Color = def.color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	})
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = beam
	-- 상징 (머리 위)
	local iconAt = at + Vector3.new(0, 9, 0)
	if def.kind == "boss" then
		bossIcon(model, iconAt, def.color)
	else
		eggIcon(model, iconAt, def.color)
	end
	-- 이름표
	local anchor = part(model, {
		Name = "LabelAnchor",
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(at + Vector3.new(0, 13.5, 0)),
		Transparency = 1,
	})
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 64)
	bb.MaxDistance = 400 -- 공장(광장에서 약 140)에서도 이름이 보이게 (2026-10-21 리뷰)
	bb.LightInfluence = 0
	bb.Parent = anchor
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = def.color
	title.TextStrokeTransparency = 0
	title.Text = def.title
	title.Parent = bb
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.3
	sub.Text = `{def.sub} · STEP ON THE PAD`
	sub.Parent = bb
	model.Parent = folder
end

function Stations.init(center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Stations"
	for _, def in DEFS do
		build(folder, def, center)
	end
	folder.Parent = workspace
end

return Stations
