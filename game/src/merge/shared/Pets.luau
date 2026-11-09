--!strict
-- 펫 뽑기 (docs/24): 큐브를 합칠 때 생기는 조각(Shards)으로만 알을 깐다. 조각은 Robux로 팔지 않는다
-- (유료 랜덤 금지 규칙). 펫마다 등급(희귀도)이 있고, 장착한 펫의 % 합이 수입에 곱해진다.
-- 같은 펫·같은 별 3마리 = 다음 별 1마리 (★1 → ★2 → ★3). 별이 오르면 같은 모델에 오라가 붙고 %가 커진다.
-- 순수 모듈 (Roblox API 없음, Lune 테스트 대상). 가중 뽑기·확률은 core/shared/Rarity

local Rarity = require(script.Parent.Parent.Core.Rarity)

local Pets = {}

-- Lune 테스트에는 Color3·Vector3가 없다: 있으면 만들고, 없으면 nil (테스트는 색·크기를 안 봄)
local function rgb(r: number, g: number, b: number): Color3
	local ok, c = pcall(function()
		return Color3.fromRGB(r, g, b)
	end)
	return if ok then c else nil :: any
end
local function vec(x: number, y: number, z: number): Vector3
	local ok, v = pcall(function()
		return Vector3.new(x, y, z)
	end)
	return if ok then v else nil :: any
end

Pets.EQUIP_SLOTS = 3
Pets.INVENTORY_CAP = 60
Pets.MAX_STAR = 3
Pets.FUSE_COUNT = 3
Pets.RELEASE_REFUND = 0.1 -- 놓아주기: 그 펫이 나오는 알 값의 10%를 조각으로 돌려줌
-- 별 배율: ★2 = 3마리를 1칸에 (칸 효율 ↑), ★3 = 9마리분
Pets.STAR_MULT = { 1, 2.5, 6 }

-- 보너스 = 알 기본값(EGGS.base) × 희귀도 배율(mult) × 별 배율 (2026-10-19 "높은 티어 펫일수록 %가 올라야")
-- 예전(희귀도만)은 시작 알 Epic과 사파리 알 Epic이 같은 15%였다. 최고치는 신화 알 Mythic ★1 58.5%, ★3 351%. 성장 체감을 위해 일부러 크게 둔다(사용자 2026-10-19, 문제가 되면 후반 비용을 올린다)
export type Rarity = { id: string, name: string, mult: number, color: Color3 }
Pets.RARITIES = {
	{ id = "common", name = "Common", mult = 1, color = rgb(200, 205, 215) },
	{ id = "uncommon", name = "Uncommon", mult = 1.5, color = rgb(110, 220, 120) },
	{ id = "rare", name = "Rare", mult = 2.2, color = rgb(90, 170, 255) },
	{ id = "epic", name = "Epic", mult = 3.2, color = rgb(190, 110, 255) },
	{ id = "legendary", name = "Legendary", mult = 5, color = rgb(255, 190, 50) },
	{ id = "mythic", name = "Mythic", mult = 9, color = rgb(255, 80, 140) },
} :: { Rarity }
local RARITY_INDEX: { [string]: number } = {}
for i, r in Pets.RARITIES do
	RARITY_INDEX[r.id] = i
end

-- look:
--   model = PetModels 키(블록·메시 조각 모음, Creator Store 무료 모델에서 옮김. 출처는 PetModels 주석)
--   mesh = 메시 하나 (예전 꾸미기 펫)
--   cube = 우리 큐브 캐릭터 (색·재질), rainbow = 색이 계속 돈다
-- yaw: 모델 앞을 진행 방향(-Z)으로 돌리는 각도
export type PetDef = {
	id: string,
	name: string,
	rarity: string,
	egg: string,
	weight: number, -- 그 알 안에서의 비중 (알별 합 100)
	model: string?,
	mesh: { id: number, tex: number?, size: Vector3, source: string }?,
	cube: { color: Color3, material: string?, rainbow: boolean? }?,
	yaw: number?,
	len: number?, -- 가장 긴 변 (기본 2.4)
}

export type EggDef = { id: string, name: string, cost: number, base: number, color: Color3, icon: string }
Pets.EGGS = {
	{ id = "starter", name = "Starter Egg", cost = 50, base = 0.015, color = rgb(240, 235, 220), icon = "Egg1" },
	{ id = "farm", name = "Farm Egg", cost = 250, base = 0.021, color = rgb(150, 220, 110), icon = "Egg2" },
	{ id = "forest", name = "Forest Egg", cost = 1200, base = 0.029, color = rgb(70, 160, 90), icon = "Egg3" },
	{ id = "safari", name = "Safari Egg", cost = 6000, base = 0.039, color = rgb(240, 190, 80), icon = "Egg4" },
	{ id = "ocean", name = "Ocean Egg", cost = 30000, base = 0.05, color = rgb(80, 170, 255), icon = "Egg5" },
	{ id = "mythic", name = "Mythic Egg", cost = 150000, base = 0.065, color = rgb(200, 90, 255), icon = "Egg6" },
} :: { EggDef }

Pets.LIST = {
	-- Starter
	{
		id = "cube",
		name = "Cube Buddy",
		rarity = "common",
		egg = "starter",
		weight = 40,
		cube = { color = rgb(255, 215, 90) },
	},
	{
		id = "chick",
		name = "Chick",
		rarity = "common",
		egg = "starter",
		weight = 30,
		mesh = {
			id = 8130151173,
			tex = 8130155382,
			size = vec(0.1004, 0.1378, 0.1466),
			source = "8130161591 chick (EerieBun)",
		},
		len = 2,
	},
	{
		id = "duck",
		name = "Rubber Duck",
		rarity = "uncommon",
		egg = "starter",
		weight = 15,
		mesh = {
			id = 9419831,
			tex = 9419827,
			size = vec(0.972, 1.035, 1.401),
			source = "5134201685 Rubber Duck (Kenekaise)",
		},
		yaw = 90,
		len = 2,
	},
	{ id = "piggy", name = "Piggy", rarity = "uncommon", egg = "starter", weight = 10, model = "piggy" },
	{
		id = "frog",
		yaw = 180,
		name = "Frog",
		rarity = "rare",
		egg = "starter",
		weight = 4.5,
		mesh = {
			id = 12250427652,
			tex = 12250359768,
			size = vec(5.89, 5.146, 3.865),
			source = "12250443898 frog plush (MasterOfStocks)",
		},
	},
	{ id = "snowman", name = "Snowy", rarity = "epic", egg = "starter", weight = 0.5, model = "snowman", yaw = 180 },
	-- Farm
	{ id = "chicken", name = "Chicken", rarity = "common", egg = "farm", weight = 40, model = "chicken" },
	{ id = "sheep", name = "Sheep", rarity = "common", egg = "farm", weight = 30, model = "sheep", yaw = 180 },
	{ id = "pup", name = "Cube Pup", rarity = "uncommon", egg = "farm", weight = 15, model = "pup", yaw = 180 },
	{ id = "bunny", name = "Cube Bunny", rarity = "uncommon", egg = "farm", weight = 10, model = "bunny", yaw = -90 },
	{ id = "turtle", name = "Turtle", rarity = "rare", egg = "farm", weight = 4.5, model = "turtle", yaw = 180 },
	{
		id = "jelly",
		name = "Jellyfish",
		rarity = "epic",
		egg = "farm",
		weight = 0.5,
		mesh = {
			id = 32539199,
			tex = 32539212,
			size = vec(1.392, 1.608, 1.392),
			source = "161258065 Jellyfish (LennoxNova)",
		},
	},
	-- Forest
	{ id = "deer", name = "Deer", rarity = "common", egg = "forest", weight = 40, model = "deer", yaw = 180 },
	{ id = "wolf", name = "Wolf", rarity = "common", egg = "forest", weight = 30, model = "wolf", yaw = 180 },
	{ id = "hoppy", name = "Hoppy", rarity = "uncommon", egg = "forest", weight = 15, model = "hoppy" },
	{ id = "panda", name = "Panda", rarity = "uncommon", egg = "forest", weight = 10, model = "panda", yaw = -90 },
	{ id = "grizzly", name = "Grizzly", rarity = "rare", egg = "forest", weight = 4.5, model = "grizzly", yaw = -90 },
	{
		id = "ghostcat",
		name = "Ghost Cat",
		rarity = "epic",
		egg = "forest",
		weight = 0.5,
		mesh = {
			id = 301994229,
			tex = 301994262,
			size = vec(3.038, 4.71, 3.79),
			source = "302828670 Ghost Cat (tucann)",
		},
	},
	-- Safari
	{ id = "zebra", name = "Zebra", rarity = "common", egg = "safari", weight = 40, model = "zebra", yaw = 180 },
	{ id = "hyena", name = "Hyena", rarity = "common", egg = "safari", weight = 30, model = "hyena", yaw = 180 },
	{
		id = "ostrich",
		name = "Ostrich",
		rarity = "uncommon",
		egg = "safari",
		weight = 15,
		model = "ostrich",
		yaw = 180,
	},
	{ id = "hippo", name = "Hippo", rarity = "uncommon", egg = "safari", weight = 10, model = "hippo", yaw = 180 },
	{ id = "lion", name = "Lion", rarity = "rare", egg = "safari", weight = 4.5, model = "lion", yaw = 180 },
	{ id = "elephant", name = "Elephant", rarity = "epic", egg = "safari", weight = 0.5, model = "elephant" },
	-- Ocean
	{ id = "penguin", name = "Penguin", rarity = "common", egg = "ocean", weight = 40, model = "penguin", yaw = 180 },
	{ id = "polar", name = "Polar Bear", rarity = "common", egg = "ocean", weight = 30, model = "polar", yaw = -90 },
	{ id = "slime", name = "Slime Cube", rarity = "uncommon", egg = "ocean", weight = 15, model = "slime" },
	{ id = "shark", name = "Shark", rarity = "rare", egg = "ocean", weight = 10, model = "shark", yaw = 180 },
	{ id = "croc", name = "Crocodile", rarity = "epic", egg = "ocean", weight = 4.5, model = "croc", yaw = 180 },
	{
		id = "ufo",
		name = "Mini UFO",
		rarity = "legendary",
		egg = "ocean",
		weight = 0.5,
		mesh = {
			id = 161270281,
			tex = 161270249,
			size = vec(5.65, 2.059, 5.658),
			source = "16649289823 Ufo Mesh (Memes_AltAccount)",
		},
	},
	-- Mythic
	{ id = "giraffe", name = "Giraffe", rarity = "rare", egg = "mythic", weight = 40, model = "giraffe", yaw = 180 },
	{ id = "tiger", name = "Tiger", rarity = "rare", egg = "mythic", weight = 30, model = "tiger", yaw = 180 },
	{ id = "rhino", name = "Rhino", rarity = "epic", egg = "mythic", weight = 20, model = "rhino", yaw = 180 },
	{
		id = "goldcube",
		name = "Golden Cube",
		rarity = "legendary",
		egg = "mythic",
		weight = 6,
		cube = { color = rgb(255, 200, 60), material = "Foil" },
	},
	{
		id = "basilisk",
		name = "Basilisk",
		rarity = "legendary",
		egg = "mythic",
		weight = 3.5,
		model = "basilisk",
		yaw = 180,
		len = 3.4,
	},
	{
		id = "rainbowcube",
		name = "Rainbow Cube",
		rarity = "mythic",
		egg = "mythic",
		weight = 0.5,
		cube = { color = rgb(255, 120, 200), material = "Neon", rainbow = true },
	},
} :: { PetDef }

local BY_ID: { [string]: PetDef } = {}
for _, p in Pets.LIST do
	BY_ID[p.id] = p
end
local EGG_BY_ID: { [string]: EggDef } = {}
for _, e in Pets.EGGS do
	EGG_BY_ID[e.id] = e
end

function Pets.get(id: string): PetDef?
	return BY_ID[id]
end

function Pets.egg(id: string): EggDef?
	return EGG_BY_ID[id]
end

function Pets.rarity(id: string): Rarity
	return Pets.RARITIES[RARITY_INDEX[id] or 1]
end

function Pets.rarityIndex(id: string): number
	return RARITY_INDEX[id] or 1
end

-- 알 하나의 펫 목록 (비중 순서 그대로)
function Pets.eggPets(eggId: string): { PetDef }
	local out = {}
	for _, p in Pets.LIST do
		if p.egg == eggId then
			table.insert(out, p)
		end
	end
	return out
end

-- r ∈ [0, 1) → 펫 id. 확률표는 화면에 그대로 공개한다 (Pets.chance)
function Pets.roll(eggId: string, r: number): string?
	local p = Rarity.pick(Pets.eggPets(eggId), r)
	return if p then p.id else nil
end

function Pets.chance(id: string): number
	local p = BY_ID[id]
	if not p then
		return 0
	end
	return Rarity.chance(Pets.eggPets(p.egg), p)
end

-- 펫 하나의 수입 보너스 (0.04 = +4%)
function Pets.bonus(id: string, star: number): number
	local p = BY_ID[id]
	if not p then
		return 0
	end
	local egg = Pets.egg(p.egg)
	local base = if egg then egg.base else 0.015
	return base * Pets.rarity(p.rarity).mult * (Pets.STAR_MULT[math.clamp(star, 1, Pets.MAX_STAR)] or 1)
end

-- 펫 한 마리 = { id, star }. 장착한 펫들의 보너스 합 → 수입 배수 (1 + 합)
export type Pet = { id: string, star: number }
function Pets.totalBonus(pets: { Pet }): number
	local sum = 0
	for _, p in pets do
		sum += Pets.bonus(p.id, p.star)
	end
	return sum
end

-- 큐브 합치기 1번에 생기는 조각: 등급 띠(5등급)마다 +1 (T1~5 = 1, T36~40 = 8)
function Pets.shardsForMerge(tier: number): number
	return 1 + (math.max(tier, 1) - 1) // 5
end

function Pets.releaseValue(id: string): number
	local p = BY_ID[id]
	local e = p and EGG_BY_ID[p.egg]
	return if e then math.max(1, math.floor(e.cost * Pets.RELEASE_REFUND)) else 0
end

-- 보너스가 큰 순으로 (같으면 별 → 희귀도 → id)
function Pets.better(a: Pet, b: Pet): boolean
	local ba, bb = Pets.bonus(a.id, a.star), Pets.bonus(b.id, b.star)
	if ba ~= bb then
		return ba > bb
	end
	if a.star ~= b.star then
		return a.star > b.star
	end
	return a.id < b.id
end

return Pets
