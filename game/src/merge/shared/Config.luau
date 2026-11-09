--!strict
-- 머지 팩토리 프로토타입 설정 (경제 공식은 Economy.luau, 여기는 월드·표현·상품 id)

local AssetIds = require(script.Parent.AssetIds)
local Economy = require(script.Parent.Economy)

local Config = {}

Config.DATA_STORE = "MergeCubeFactory_Live1" -- 2026-10-18 출시용으로 새로 시작 (테스트 데이터는 Proto1에 남음)
-- Studio(API 접근 켬)에서 테스트 구매·저장을 시험할 때 실서비스 저장소를 건드리지 않도록 이름 뒤에 붙인다 (docs/19 A3)
Config.STUDIO_STORE_SUFFIX = if game:GetService("RunService"):IsStudio() then "_Studio" else ""

-- 월드 배치: 원형으로 8플롯
Config.PLOT_COUNT = 8
Config.PLOT_RADIUS = 140 -- 중심에서 각 플롯 중심까지 (studs)
Config.TRAY_SIZE = Vector3.new(40, 16, 40) -- 내부 폭 x 벽 높이 x 깊이
Config.WALL_THICKNESS = 2
Config.DROP_HEIGHT = 20 -- 트레이 바닥 위 드로퍼 높이. 벽(16) 바로 위: 높으면 기본 카메라에서 드로퍼와 업그레이드 카드가 화면 밖 (2026-10-18)
Config.PLATFORM_SIZE = Vector3.new(80, 2, 80)
-- 시점 비컨: 트레이 앞 (플롯 중심에서 +Z). 위에 서면 공장 전체 시점, 벗어나면 일반 카메라 (client/CameraView)
Config.VIEW_PAD_Z = 35
Config.VIEW_PAD_RADIUS = 4.5

-- 큐브: 등급별 한 변 (studs). 초반엔 빠르게 커지고 약 5.6스터드에서 멈춘다 (docs/13 §8).
-- 트레이 40×40(강화 Lv8이면 56×56)에 큐브 50~114개가 한두 층 안에 들어가야 하므로 크기는 포화시키고, 높은 등급은 색·재질·빛으로 구분한다.
-- (7.6 → 5.6: "19단계인데 꽉 차서 알아보기 어렵고 병합이 막힌다" 2026-10-19)
-- 2026-10-25 사용자 "큐브 크기가 너무 거대함, 등급 구간별 크기 일정화… t26정도인데도 트레이가 꽉차서 넘침":
-- 5등급 띠마다 같은 크기, 띠마다 +CUBE_SIZE_STEP (T1-5 2.2 … T26-30 3.95 … T36-40 4.65). 예전엔 T26 ≈ 5.47
Config.CUBE_SIZE_MIN = 2.2
Config.CUBE_SIZE_STEP = 0.35
Config.CUBE_SIZE_MAX = 4.65
function Config.cubeSize(tier: number): number
	local band = (math.max(1, tier) - 1) // 5
	return math.min(Config.CUBE_SIZE_MIN + Config.CUBE_SIZE_STEP * band, Config.CUBE_SIZE_MAX)
end

-- 등급 띠: 5등급씩 같은 재질, 띠 안에서는 색으로 구분. 띠가 바뀌면 재질·빛이 한 단계 화려해진다.
-- glow = 큐브 안 PointLight 밝기(0이면 없음), range = 빛 반경, sparkle = 반짝이 입자(최상위 띠만)
-- 재질은 Studio에서 비교해 골랐다(2026-10-18): ForceField는 거의 투명해 안 보이고, Glass는 밝은 색을 하얗게 바래게 하며,
-- CrackedLava는 색이 묻힌다. 그래서 Glass·Neon 띠는 진한 색을 쓴다.
export type TierBand = {
	name: string,
	material: Enum.Material,
	reflectance: number,
	glow: number,
	range: number,
	sparkle: boolean?,
	colors: { Color3 },
}
Config.TIER_BANDS = {
	{
		name = "BASIC", -- 1~5 (예전 팔레트 그대로)
		material = Enum.Material.SmoothPlastic,
		reflectance = 0,
		glow = 0,
		range = 0,
		colors = {
			Color3.fromRGB(236, 235, 246),
			Color3.fromRGB(140, 220, 160),
			Color3.fromRGB(110, 190, 255),
			Color3.fromRGB(255, 209, 61),
			Color3.fromRGB(255, 150, 80),
		},
	},
	{
		name = "CANDY", -- 6~10
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.15,
		glow = 0,
		range = 0,
		colors = {
			Color3.fromRGB(240, 90, 110),
			Color3.fromRGB(200, 110, 255),
			Color3.fromRGB(90, 230, 230),
			Color3.fromRGB(255, 120, 200),
			Color3.fromRGB(150, 255, 90),
		},
	},
	{
		name = "GEM", -- 11~15
		material = Enum.Material.Glass,
		reflectance = 0.3,
		glow = 0,
		range = 0,
		colors = {
			Color3.fromRGB(230, 150, 20),
			Color3.fromRGB(20, 60, 200),
			Color3.fromRGB(10, 150, 80),
			Color3.fromRGB(190, 10, 40),
			Color3.fromRGB(120, 40, 190),
		},
	},
	{
		name = "METAL", -- 16~20
		material = Enum.Material.Metal,
		reflectance = 0.35,
		glow = 0,
		range = 0,
		colors = {
			Color3.fromRGB(175, 110, 55),
			Color3.fromRGB(205, 120, 80),
			Color3.fromRGB(200, 205, 215),
			Color3.fromRGB(255, 200, 50),
			Color3.fromRGB(225, 235, 245),
		},
	},
	{
		name = "NEON", -- 21~25
		material = Enum.Material.Neon,
		reflectance = 0,
		glow = 0,
		range = 0,
		colors = {
			Color3.fromRGB(220, 220, 0),
			Color3.fromRGB(230, 0, 50),
			Color3.fromRGB(0, 70, 255),
			Color3.fromRGB(0, 210, 70),
			Color3.fromRGB(255, 90, 0),
		},
	},
	{
		name = "SHINE", -- 26~30
		material = Enum.Material.Foil,
		reflectance = 0.3,
		glow = 1,
		range = 8,
		colors = {
			Color3.fromRGB(80, 230, 210),
			Color3.fromRGB(90, 150, 255),
			Color3.fromRGB(170, 100, 255),
			Color3.fromRGB(255, 100, 200),
			Color3.fromRGB(255, 210, 90),
		},
	},
	{
		name = "COSMIC", -- 31~35
		material = Enum.Material.Neon,
		reflectance = 0,
		glow = 2,
		range = 10,
		colors = {
			Color3.fromRGB(0, 90, 130),
			Color3.fromRGB(90, 0, 140),
			Color3.fromRGB(20, 20, 120),
			Color3.fromRGB(130, 0, 80),
			Color3.fromRGB(50, 10, 90),
		},
	},
	{
		name = "MYTHIC", -- 36~40
		material = Enum.Material.Neon,
		reflectance = 0,
		glow = 3,
		range = 14,
		sparkle = true,
		colors = {
			Color3.fromRGB(255, 110, 30),
			Color3.fromRGB(40, 230, 120),
			Color3.fromRGB(255, 215, 90),
			Color3.fromRGB(120, 80, 255),
			Color3.fromRGB(255, 60, 255),
		},
	},
} :: { TierBand }
Config.BAND_SIZE = 5

-- 등급 → 띠 (범위 밖 등급은 양 끝 띠)
function Config.tierBand(tier: number): TierBand
	local i = math.clamp((tier - 1) // Config.BAND_SIZE + 1, 1, #Config.TIER_BANDS)
	return Config.TIER_BANDS[i]
end

-- 모든 등급의 색 (클라이언트가 Config.TIER_COLORS[tier]로 바로 읽는다)
Config.TIER_COLORS = {} :: { Color3 }
for tier = 1, Economy.MAX_TIER do
	local band = Config.tierBand(tier)
	Config.TIER_COLORS[tier] = band.colors[(tier - 1) % Config.BAND_SIZE + 1]
end
Config.TIER_NAMES = Economy.TIER_NAMES

-- 등급별 표정 (큐브 정면·뒷면 Decal). 같은 등급은 늘 같은 얼굴이라 알아보기 쉽고, 등급이 오르면 얼굴이 바뀐다.
-- AssetIds.Faces(16종, tools/make_fx_assets.py의 FACE_SET 순서)를 등급 순으로 순환한다.
function Config.faceFor(tier: number): string
	local faces: { string } = AssetIds.Faces
	if #faces == 0 then
		return AssetIds.Images.Face
	end
	return faces[(math.max(tier, 1) - 1) % #faces + 1]
end

-- 큐브 파트에 등급 재질·반사·빛 적용 (서버 styleCube가 부른다. 색·크기는 styleCube가 정함)
function Config.applyTierLook(part: BasePart, tier: number)
	local band = Config.tierBand(tier)
	part.Material = band.material
	part.Reflectance = band.reflectance
	local light = part:FindFirstChild("Glow") :: PointLight?
	if band.glow > 0 then
		if not light then
			local l = Instance.new("PointLight")
			l.Name = "Glow"
			l.Shadows = false
			l.Parent = part
			light = l
		end
		local l = light :: PointLight
		l.Color = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
		l.Brightness = band.glow
		l.Range = band.range
	elseif light then
		light:Destroy()
	end
	local sparkles = part:FindFirstChild("Sparkle") :: Sparkles?
	if band.sparkle then
		local sp = sparkles or Instance.new("Sparkles")
		sp.Name = "Sparkle"
		sp.SparkleColor = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
		sp.Parent = part
	elseif sparkles then
		sparkles:Destroy()
	end
end

-- 합치기 판정: 같은 등급, 중심 거리 <= 한 변 × 이 값, 둘 다 생성 후 MERGE_MIN_AGE 초 지남
Config.MERGE_DISTANCE = 1.2
Config.MERGE_MIN_AGE = 0.3
Config.MERGE_SCAN_INTERVAL = 0.1
-- 자석: 멈춘(속도 < REST_SPEED) 같은 등급 쌍을 INTERVAL초마다 서로에게 점프(상승속도 HOP)
Config.MAGNET_INTERVAL = 0.8
Config.MAGNET_REST_SPEED = 1.5
Config.MAGNET_HOP = 30
-- 높은 등급일수록 자석이 조금 세다 (2026-10-20 사용자): 더 자주 뛰고, 덜 멈춰도 끌린다. T1 = 기본, T40 ≈ 간격 0.42초·멈춤 기준 3.4
function Config.magnetInterval(tier: number): number
	return math.max(0.4, Config.MAGNET_INTERVAL / (1 + 0.024 * (tier - 1)))
end
function Config.magnetRest(tier: number): number
	return math.min(3.5, Config.MAGNET_REST_SPEED * (1 + 0.032 * (tier - 1)))
end
Config.MANUAL_DROP_COOLDOWN = 0.4
-- 데이터 큐브 (docs/27 단계 4): 서버는 큐브를 데이터(TraySim)로만 들고, 클라이언트가 로컬 파트를 만들어 보간한다.
-- false면 예전처럼 서버 Part + Roblox 물리 (PartBackend, 롤백용). 저장 형식은 같다
Config.DATA_CUBES = true

-- 협동 보너스: 내 플롯 위에 다른 플레이어가 있으면
Config.TEAM_BONUS = { [1] = 0.2, [2] = 0.35, [3] = 0.5 }

-- 상품·패스 id는 shared/Shop.luau (docs/03 §2)

-- 변이 겉모습 (docs/16 §1). 확률·배수는 Economy.VARIANTS
--   blend: 등급 색을 color 쪽으로 섞는 비율, cycle: 클라이언트가 색을 무지개로 돌림(태그 RainbowCube)
--   shell: ForceField 껍데기, sparkle: 반짝이 파티클, light: 빛
--   outline: 모서리 테두리(SelectionBox) 색 — 등급 띠(Metal/Neon 재질)와 한눈에 구분되는 표식
--   particle: 변이 고유 입자 "glint"(번쩍임) | "orb"(떠오르는 빛방울) | "prism"(여러 색 반짝이) | "star"(소용돌이 별)
--             | "vortex"(맴도는 별무리 + 납작한 강착 고리) | "halo"(금빛 고리 + 솟는 빛줄기 + 뒤에서 도는 햇살)
--   pulse: 테두리·껍데기가 outline 색과 이 색 사이를 오감(클라이언트), glow: 빛 밝기(기본 1.2)
export type VariantStyle = {
	label: string,
	tag: Color3,
	outline: Color3,
	particle: string,
	material: Enum.Material,
	color: Color3?,
	blend: number,
	reflectance: number,
	sparkle: boolean,
	light: boolean,
	shell: boolean,
	cycle: boolean,
	pulse: Color3?,
	glow: number?,
	shellMaterial: Enum.Material?, -- 기본 ForceField
	shellTransparency: number?,
	shellScale: number?, -- 기본 1.08
}
Config.VARIANT_STYLE = {
	Metallic = {
		label = "METALLIC",
		tag = Color3.fromRGB(210, 220, 235),
		outline = Color3.fromRGB(255, 255, 255),
		particle = "glint",
		material = Enum.Material.Metal,
		color = Color3.fromRGB(205, 212, 225),
		blend = 0.45,
		reflectance = 0.3,
		sparkle = true,
		light = false,
		shell = false,
		cycle = false,
	},
	Neon = {
		label = "NEON",
		tag = Color3.fromRGB(120, 255, 240),
		outline = Color3.fromRGB(80, 255, 230),
		particle = "orb",
		material = Enum.Material.Neon,
		blend = 0,
		reflectance = 0,
		sparkle = true,
		light = true,
		shell = false,
		cycle = false,
	},
	Rainbow = {
		label = "RAINBOW",
		tag = Color3.fromRGB(255, 160, 220),
		outline = Color3.fromRGB(255, 120, 200),
		particle = "prism",
		material = Enum.Material.SmoothPlastic,
		blend = 0,
		reflectance = 0.15,
		sparkle = true,
		light = true,
		shell = false,
		cycle = true,
	},
	Galaxy = {
		label = "GALAXY",
		tag = Color3.fromRGB(190, 150, 255),
		outline = Color3.fromRGB(170, 120, 255),
		particle = "star",
		material = Enum.Material.Glass,
		color = Color3.fromRGB(45, 25, 110), -- 짙은 보라 위에 색이 살짝 돎 (0.6이면 하늘색으로 보였다, 플레이테스트 2026-10-18)
		blend = 0.75,
		reflectance = 0.2,
		sparkle = true,
		light = true,
		shell = true,
		cycle = true,
	},
	-- Cosmic: 거의 검은 남보라 유리 몸통 + 둘레를 도는 별무리 + 수평으로 퍼지는 강착 고리 + 보라↔청록 맥동
	Cosmic = {
		label = "COSMIC",
		tag = Color3.fromRGB(140, 200, 255),
		outline = Color3.fromRGB(170, 80, 255),
		pulse = Color3.fromRGB(60, 235, 255),
		particle = "vortex",
		material = Enum.Material.SmoothPlastic, -- 유리 껍데기 안의 유리는 안 그려지므로 몸통은 플라스틱
		color = Color3.fromRGB(10, 6, 34),
		blend = 0.9,
		reflectance = 0.2,
		sparkle = true,
		light = true,
		glow = 2.5,
		shell = true,
		shellMaterial = Enum.Material.Glass, -- 짙은 유리 껍데기 = 사건의 지평선 (ForceField는 하늘색으로 떠 보였다)
		shellTransparency = 0.45,
		shellScale = 1.16,
		cycle = false,
	},
	-- Divine: 흰 금빛 몸통 + 머리 위 금빛 고리 + 위로 솟는 빛줄기 + 뒤에서 도는 햇살 + 강한 빛
	Divine = {
		label = "DIVINE",
		tag = Color3.fromRGB(255, 225, 120),
		outline = Color3.fromRGB(255, 200, 60),
		pulse = Color3.fromRGB(255, 255, 235),
		particle = "halo",
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(255, 222, 130),
		blend = 0.8,
		reflectance = 0.25,
		sparkle = true,
		light = true,
		glow = 3.5,
		shell = true,
		cycle = false,
	},
} :: { [string]: VariantStyle }

-- 꾸미기 (docs/16 §3). 칸마다 첫 번째 조건 없는 항목이 기본값.
--   codex = 도감 발견 칸 수로 해금(무료), gems = 젬으로 구매(확정). 확률 상품 없음.
export type Cosmetic = {
	id: string,
	slot: string, -- "bat" | "aura" | "trail" | "tray" | "dropper"
	name: string,
	codex: number?,
	gems: number?,
	color: Color3?,
	material: Enum.Material?,
	colors: { Color3 }?,
	rainbow: boolean?,
	aura: boolean?,
	band: Color3?, -- 배트 스킨: 띠 색 (color·material = 몸통)
	shop: string?, -- 상점 전용: Shop 항목 key (그걸 사야 받음)
	mesh: MeshDef?, -- 배트·펫: Creator Store 메시 (SpecialMesh로 붙임, 스크립트 없음)
	texture: string?, -- 오라 입자·꼬리 무늬: AssetIds.Images 키 또는 rbxasset:// 경로
	rise: number?, -- 오라: 입자 위아래 가속 (+ 위로, - 아래로 떨어짐)
	cube: boolean?, -- 펫: 우리 큐브 캐릭터 (메시 대신 얼굴 큐브)
	hitSound: string?, -- 배트: 명중 소리 키 (Fx SOUND_IDS, 없으면 알루미늄 '팅')
	tier: number?, -- 오라 단계 (1부터, 앞 단계를 가져야 살 수 있음)
}
-- Creator Store 무료·스크립트 없는 메시 (2026-10-19, 사용자 "치장요소가 색깔놀이인 게 너무 많음, 에셋 구해서 다양화").
-- size = 메시 원래 크기(MeshSize, Studio에서 측정). 가장 긴 축을 배트 길이/펫 크기(len)에 맞춰 같은 비율로 키운다.
-- 가장 긴 축을 배트 방향(Y)으로 돌리고, flip이면 위아래를 뒤집는다 (손잡이 쪽이 손에 오게). yaw = 펫이 앞을 보게 돌리는 각도
-- 다른 게임 IP(펫 시뮬레이터, 마인크래프트 등)를 베낀 모델은 쓰지 않는다. source에 출처를 남긴다
export type MeshDef = {
	id: number,
	tex: number?,
	size: Vector3,
	len: number?,
	flip: boolean?,
	yaw: number?,
	source: string,
}
-- bat·aura 추가 (2026-10-19): 배트 스킨, 오라는 꼬리와 따로 (둘 다 장착 가능)
-- pet·island 추가 (2026-10-19): 따라다니는 작은 친구 / 공장 섬 바닥 (사용자 "공장 바닥, 큐브 스포너, 섬 바닥까지 바꿀 수 있으면")
Config.COSMETIC_SLOTS = { "bat", "aura", "trail", "tray", "dropper", "island" }
Config.COSMETICS = {
	{
		id = "tray_classic",
		slot = "tray",
		name = "Classic Tray",
		color = Color3.fromRGB(48, 46, 73),
		material = Enum.Material.SmoothPlastic,
	},
	{
		id = "tray_marble",
		slot = "tray",
		name = "Marble Tray",
		codex = 3,
		color = Color3.fromRGB(232, 228, 238),
		material = Enum.Material.Marble,
	},
	{
		id = "tray_ice",
		slot = "tray",
		name = "Ice Rink",
		gems = 60,
		color = Color3.fromRGB(170, 215, 255),
		material = Enum.Material.Ice,
	},
	{
		id = "tray_neon",
		slot = "tray",
		name = "Neon Grid",
		codex = 10,
		color = Color3.fromRGB(40, 50, 130),
		material = Enum.Material.Neon,
	},
	{
		id = "tray_gold",
		slot = "tray",
		name = "Gold Vault",
		gems = 200,
		color = Color3.fromRGB(255, 200, 70),
		material = Enum.Material.Foil,
	},
	{
		id = "tray_garden",
		slot = "tray",
		name = "Garden Lawn",
		codex = 6,
		color = Color3.fromRGB(110, 190, 90),
		material = Enum.Material.Grass,
	},
	{
		id = "tray_deck",
		slot = "tray",
		name = "Wooden Deck",
		codex = 14,
		color = Color3.fromRGB(190, 140, 90),
		material = Enum.Material.WoodPlanks,
	},
	{
		id = "tray_beach",
		slot = "tray",
		name = "Sunny Beach",
		gems = 50,
		color = Color3.fromRGB(240, 215, 150),
		material = Enum.Material.Sand,
	},
	{
		id = "tray_castle",
		slot = "tray",
		name = "Castle Floor",
		codex = 45,
		color = Color3.fromRGB(150, 150, 160),
		material = Enum.Material.Cobblestone,
	},
	{
		id = "tray_lava",
		slot = "tray",
		name = "Lava Floor",
		gems = 150,
		color = Color3.fromRGB(255, 110, 50),
		material = Enum.Material.CrackedLava,
	},
	{ id = "dropper_steel", slot = "dropper", name = "Steel Dropper", material = Enum.Material.Metal },
	{
		id = "dropper_wood",
		slot = "dropper",
		name = "Wooden Crate",
		codex = 8,
		material = Enum.Material.WoodPlanks,
	},
	{
		id = "dropper_brick",
		slot = "dropper",
		name = "Brick Chimney",
		codex = 30,
		material = Enum.Material.Brick,
	},
	{ id = "dropper_ice", slot = "dropper", name = "Ice Block", gems = 60, material = Enum.Material.Ice },
	{
		id = "dropper_lava",
		slot = "dropper",
		name = "Lava Dropper",
		gems = 120,
		material = Enum.Material.CrackedLava,
	},
	-- 섬 바닥 (공장 땅 Platform). 기본 = 잔디
	{
		id = "island_grass",
		slot = "island",
		name = "Grass Island",
		color = Color3.fromRGB(110, 170, 95),
		material = Enum.Material.Grass,
	},
	{
		id = "island_sand",
		slot = "island",
		name = "Desert Island",
		codex = 4,
		color = Color3.fromRGB(235, 205, 140),
		material = Enum.Material.Sand,
	},
	{
		id = "island_snow",
		slot = "island",
		name = "Snow Island",
		codex = 16,
		color = Color3.fromRGB(240, 245, 255),
		material = Enum.Material.Snow,
	},
	{
		id = "island_candy",
		slot = "island",
		name = "Candy Island",
		gems = 80,
		color = Color3.fromRGB(255, 175, 215),
		material = Enum.Material.SmoothPlastic,
	},
	{
		id = "island_stone",
		slot = "island",
		name = "Stone Island",
		codex = 38,
		color = Color3.fromRGB(130, 130, 140),
		material = Enum.Material.Slate,
	},
	{
		id = "island_volcano",
		slot = "island",
		name = "Volcano Island",
		gems = 160,
		color = Color3.fromRGB(70, 60, 60),
		material = Enum.Material.Basalt,
	},
	{
		id = "island_crystal",
		slot = "island",
		name = "Crystal Island",
		codex = 95,
		color = Color3.fromRGB(150, 120, 255),
		material = Enum.Material.Glass,
	},
	{
		id = "dropper_plate",
		slot = "dropper",
		name = "Diamond Plate",
		gems = 40,
		material = Enum.Material.DiamondPlate,
	},
	{ id = "dropper_neon", slot = "dropper", name = "Neon Dropper", codex = 5, material = Enum.Material.Neon },
	{ id = "dropper_glass", slot = "dropper", name = "Crystal Dropper", codex = 20, material = Enum.Material.Glass },
	{ id = "trail_none", slot = "trail", name = "No Trail" },
	{
		id = "trail_sparkle",
		slot = "trail",
		name = "Sparkle Trail",
		codex = 1,
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 220, 255) },
	},
	{
		id = "trail_gold",
		slot = "trail",
		name = "Gold Trail",
		gems = 80,
		colors = { Color3.fromRGB(255, 235, 130), Color3.fromRGB(255, 160, 40) },
	},
	{ id = "trail_rainbow", slot = "trail", name = "Rainbow Trail", codex = 30, rainbow = true },
	{
		id = "trail_hearts",
		slot = "trail",
		name = "Heart Trail",
		codex = 22,
		texture = "PHeart",
		colors = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 200, 220) },
	},
	{
		id = "trail_notes",
		slot = "trail",
		name = "Music Trail",
		gems = 70,
		texture = "PNote",
		colors = { Color3.fromRGB(120, 230, 255), Color3.fromRGB(190, 140, 255) },
	},
	{
		id = "trail_snow",
		slot = "trail",
		name = "Snowflake Trail",
		codex = 75,
		texture = "PSnow",
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 210, 255) },
	},
	{
		id = "trail_starter",
		slot = "trail",
		name = "Starter Trail",
		shop = "starter",
		colors = { Color3.fromRGB(255, 140, 190), Color3.fromRGB(255, 230, 120) },
	},
	-- 배트 스킨 (몸통 색·재질 + 띠 색). 기본 = 알루미늄
	{
		id = "bat_aluminum",
		slot = "bat",
		name = "Aluminum Bat",
		color = Color3.fromRGB(232, 236, 244),
		material = Enum.Material.Metal,
		band = Color3.fromRGB(230, 60, 60),
	},
	{
		id = "bat_wood",
		hitSound = "HitWood", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Classic Wood",
		codex = 3,
		color = Color3.fromRGB(225, 180, 115),
		material = Enum.Material.Wood,
		band = Color3.fromRGB(40, 40, 46),
	},
	{
		id = "bat_neon",
		hitSound = "HitZap", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Neon Bat",
		codex = 25,
		color = Color3.fromRGB(255, 80, 200),
		material = Enum.Material.Neon,
		band = Color3.fromRGB(90, 255, 230),
	},
	{
		id = "bat_gold",
		hitSound = "HitGold", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Golden Bat",
		gems = 120,
		color = Color3.fromRGB(255, 200, 70),
		material = Enum.Material.Foil,
		band = Color3.fromRGB(40, 30, 20),
	},
	{
		id = "bat_crystal",
		hitSound = "HitGlass", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Crystal Bat",
		codex = 50,
		color = Color3.fromRGB(170, 230, 255),
		material = Enum.Material.Glass,
		band = Color3.fromRGB(255, 255, 255),
	},
	{
		id = "bat_rainbow",
		hitSound = "HitRainbow", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Rainbow Bat",
		codex = 100,
		rainbow = true,
		color = Color3.fromRGB(255, 120, 120),
		material = Enum.Material.SmoothPlastic,
		band = Color3.fromRGB(255, 255, 255),
	},
	-- 메시 배트 (Creator Store, 스크립트 없음)
	{
		id = "bat_fish",
		hitSound = "HitSquish", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Fish Slap",
		codex = 8,
		mesh = {
			id = 1725219705,
			tex = 1725222355,
			size = Vector3.new(0.243, 2.087, 5.061),
			source = "1725227984 Fish (username723844789)",
		},
	},
	{
		id = "bat_baguette",
		hitSound = "HitCrunch", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Baguette",
		codex = 18,
		mesh = {
			id = 3152275648,
			tex = 3152275671,
			size = Vector3.new(45.73, 12.12, 18.31),
			source = "4141592552 Baguette (bearduckmonkey)",
		},
	},
	{
		id = "bat_cane",
		hitSound = "HitBoing", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Candy Cane",
		codex = 35,
		mesh = {
			id = 4484615596,
			tex = 4484591908,
			size = Vector3.new(4.263, 3.888, 0.717),
			source = "4517715767 Candy Cane (Conigin)",
		},
	},
	{
		id = "bat_pan",
		hitSound = "HitClang", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Frying Pan",
		gems = 90,
		mesh = {
			id = 6332687710,
			tex = 6332687750,
			size = Vector3.new(3.548, 0.624, 5.63),
			source = "7931126583 Frying Pan (iiMonkeyBeast)",
		},
	},
	{
		id = "bat_hammer",
		hitSound = "HitHammer", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Builder Hammer",
		codex = 70,
		mesh = {
			id = 16198309,
			tex = 16198294,
			size = Vector3.new(0.913, 0.213, 1.862),
			flip = true,
			source = "14596118279 Classic Hammer (Roblox gear mesh)",
		},
	},
	{
		id = "bat_chicken",
		hitSound = "HitSqueak", -- 배트별 타격음 (tools/make_fx_assets.py batskins)
		slot = "bat",
		name = "Rubber Chicken",
		gems = 180,
		mesh = {
			id = 75495332,
			tex = 75495466,
			size = Vector3.new(0.552, 0.537, 2.01),
			flip = true,
			source = "76509683 Rubber Chicken Tool (Roblox gear mesh)",
		},
	},
	-- 펫은 꾸미기에서 빠져 펫 뽑기로 옮김 (2026-10-19, shared/Pets · docs/24). 예전 소유분은 server/Pets.ensure가 옮김
	-- 오라 (몸 주위 반짝이). 기본 = 없음
	-- 2026-10-19 단계식: 젬으로만, 앞 단계를 가져야 다음 단계를 산다. 단계가 높을수록 화려하고 배트 넉백 저항(Economy.auraResist)
	-- Galaxy는 Collector 패스로도 받는다(예전 약속 유지). 예전 도감 해금분은 Collection.migrate가 소유로 옮김
	{ id = "aura_none", slot = "aura", name = "No Aura" },
	{
		id = "aura_bubbles",
		slot = "aura",
		name = "Bubble Aura",
		tier = 1,
		gems = 20,
		aura = true,
		texture = "PBubble",
		rise = 1.5,
		colors = { Color3.fromRGB(170, 230, 255), Color3.fromRGB(220, 250, 255) },
	},
	{
		id = "aura_hearts",
		slot = "aura",
		name = "Heart Aura",
		tier = 2,
		gems = 30,
		aura = true,
		texture = "PHeart",
		rise = 2,
		colors = { Color3.fromRGB(255, 110, 160), Color3.fromRGB(255, 190, 215) },
	},
	{
		id = "aura_blossom",
		slot = "aura",
		name = "Blossom Aura",
		tier = 3,
		gems = 45,
		aura = true,
		texture = "PFlower",
		rise = -1.5,
		colors = { Color3.fromRGB(255, 180, 210), Color3.fromRGB(255, 255, 255) },
	},
	{
		id = "aura_ember",
		slot = "aura",
		name = "Ember Aura",
		tier = 4,
		gems = 60,
		aura = true,
		colors = { Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 40) },
	},
	{
		id = "aura_snow",
		slot = "aura",
		name = "Snowfall Aura",
		tier = 5,
		gems = 80,
		aura = true,
		texture = "PSnow",
		rise = -3,
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 220, 255) },
	},
	{
		id = "aura_frost",
		slot = "aura",
		name = "Frost Aura",
		tier = 6,
		gems = 100,
		aura = true,
		colors = { Color3.fromRGB(230, 250, 255), Color3.fromRGB(110, 190, 255) },
	},
	{
		id = "aura_notes",
		slot = "aura",
		name = "Music Aura",
		tier = 7,
		gems = 125,
		aura = true,
		texture = "PNote",
		rise = 2.5,
		colors = { Color3.fromRGB(120, 230, 255), Color3.fromRGB(200, 140, 255) },
	},
	{
		id = "aura_star",
		slot = "aura",
		name = "Star Aura",
		tier = 8,
		gems = 150,
		aura = true,
		colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(190, 150, 255) },
	},
	{
		id = "aura_storm",
		slot = "aura",
		name = "Storm Aura",
		tier = 9,
		gems = 180,
		aura = true,
		texture = "PBolt",
		rise = 0,
		colors = { Color3.fromRGB(255, 240, 120), Color3.fromRGB(160, 220, 255) },
	},
	{
		id = "aura_flame",
		slot = "aura",
		name = "Flame Aura",
		tier = 10,
		gems = 220,
		aura = true,
		texture = "rbxasset://textures/particles/fire_main.dds",
		rise = 6,
		colors = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 30) },
	},
	{
		id = "aura_galaxy",
		slot = "aura",
		name = "Galaxy Aura",
		tier = 11,
		gems = 260,
		aura = true,
		colors = { Color3.fromRGB(120, 80, 255), Color3.fromRGB(80, 220, 255) },
	},
	{
		id = "aura_divine",
		slot = "aura",
		name = "Divine Aura",
		tier = 12,
		gems = 300,
		aura = true,
		rainbow = true,
	},
} :: { Cosmetic }

function Config.cosmetic(id: string): Cosmetic?
	for _, c in Config.COSMETICS do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- 칸의 기본 꾸미기 (조건 없는 첫 항목)
function Config.defaultCosmetic(slot: string): Cosmetic
	for _, c in Config.COSMETICS do
		if c.slot == slot and not c.codex and not c.gems and not c.shop then
			return c
		end
	end
	error("no default cosmetic for " .. slot)
end

-- Cubika에서 업로드한 효과음 (Nurimalol 소유, 같은 계정으로 게시하면 그대로 동작)
Config.SOUNDS = {
	Drop = "rbxassetid://111329435266833",
	Merged = "rbxassetid://137741791433609",
	Land = "rbxassetid://110704827800998",
	UiClick = "rbxassetid://126511035483093",
	CashRegister = "rbxassetid://9113728049", -- ProSoundEffects (docs/08)
	-- 큰 합치기 저음 (Roblox 라이선스 파트너 음원, 모든 경험 무료)
	Impact = "rbxassetid://9126009571", -- "Subwoofer Impact Deep Rumbling Pops Booming 2" ProSoundEffects 0.8s
	Boom = "rbxassetid://9113551983", -- "Boom Thump Rattling Impacts Light Crunch 4" ProSoundEffects 1.6s
}
Config.BGM = "rbxassetid://1839406050" -- "Happy Game" APMOfficial (docs/08)

-- AI 플레이어 (server/Bots, 2026-10-24 사용자: "플레이어 수가 미달이라면 ai 플레이어도 조금 넣어볼까,
-- 공장 성장보다는 훔치기나 지키기를 간헐적으로 시도하거나 맵을 돌아다니는 방향으로")
-- 이름에 [BOT]·표지판에 (Bot). Players에 없어서 접속자 수·랭킹·추천 지표에 안 들어간다
Config.BOTS = {
	ENABLED = true,
	FILL_TO = 4, -- 사람 + 봇이 이 수가 될 때까지 (사람 0명이면 봇도 0)
	MAX = 3,
	STEAL_EVERY = { 90, 180 }, -- 봇 하나가 훔치러 가는 간격 (초, 무작위)
	VICTIM_COOLDOWN = 300, -- 같은 사람을 다시 털기까지 (초)
	STEAL_NEWBIES = false, -- 리버스 0회 사람은 털지 않는다 (사람끼리의 첫 판 보호와 같게)
	DEFEND_CHANCE = 0.75, -- 자기 트레이를 털리면 쫓아갈 확률
	DEFEND_DELAY = 1.5, -- 알아채기까지 (초)
	DROP_EVERY = 2.5, -- 봇 공장 드로퍼 (초)
	TRAY_MAX = 28, -- 봇 트레이 큐브 수 상한
	-- 봇 수준 (사용자 2026-10-25 "접속 유저 평균치 + 상한, 드롭하는 큐브는 좀 낮게"): 사람들 평균에 맞추되 넘지 않는다
	TOP_BELOW = 1, -- 봇 최고 등급(합치기 상한) = 사람 최고 등급 평균 - 이것
	TOP_MAX = 26, -- 봇 최고 등급 절대 상한
	DROP_BELOW = 2, -- 봇 드롭 등급 = 사람 드로퍼 최고 등급 평균 - 이것
}

-- Studio 전용: 진행 확인용 현금 배수 (게시 빌드에서는 무시)
Config.STUDIO_CASH_MULT = 1

return Config
