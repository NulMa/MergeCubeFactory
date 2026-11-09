--!strict
-- lune run tests/merge/Pets.spec.luau (game 디렉터리에서)
-- 펫 뽑기 규칙 (shared/Pets) + 리버스 러시·낮은 등급 보정 (shared/Economy). docs/24_PETS.md

local process = require("@lune/process")
local Require = require("../Require")
local P = Require("src/merge/shared/Pets")
local E = require("../../src/merge/shared/Economy")

local passed, failed = 0, 0

local function ok(name: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print(`FAIL  {name}{if detail then ": " .. detail else ""}`)
	end
end

local function eq(name: string, got: any, want: any)
	ok(name, got == want, `got {got}, want {want}`)
end

-- 알마다 비중 합 100, 펫 6마리
for _, egg in P.EGGS do
	local sum = 0
	local list = P.eggPets(egg.id)
	for _, p in list do
		sum += p.weight
	end
	ok(`{egg.id} weights = 100`, math.abs(sum - 100) < 1e-9, tostring(sum))
	eq(`{egg.id} has 6 pets`, #list, 6)
end

-- 펫 id 중복 없음, 등급 유효
local seen = {}
for _, p in P.LIST do
	ok(`unique {p.id}`, not seen[p.id])
	seen[p.id] = true
	ok(`rarity {p.id}`, P.rarity(p.rarity).id == p.rarity)
	ok(`look {p.id}`, p.model ~= nil or p.mesh ~= nil or p.cube ~= nil)
end

-- 뽑기: r=0 → 첫 펫, r→1 → 마지막 펫, 확률 합 1
eq("roll 0", P.roll("starter", 0), "cube")
eq("roll ~1", P.roll("starter", 0.99999), "snowman")
eq("roll mid", P.roll("starter", 0.5), "chick")
local total = 0
for _, p in P.eggPets("mythic") do
	total += P.chance(p.id)
end
ok("chance sums to 1", math.abs(total - 1) < 1e-9)

-- 보너스: 알 기본값 × 희귀도 × 별
local function near(name: string, got: number, want: number)
	ok(name, math.abs(got - want) < 1e-9, `got {got}, want {want}`)
end
near("starter common ★1", P.bonus("cube", 1), 0.015)
near("starter common ★2", P.bonus("cube", 2), 0.015 * 2.5)
near("mythic mythic ★3", P.bonus("rainbowcube", 3), 0.065 * 9 * 6)
near("total", P.totalBonus({ { id = "cube", star = 1 }, { id = "tiger", star = 2 } }), 0.015 + 0.065 * 2.2 * 2.5)
-- 같은 희귀도면 뒤 알이 항상 더 높다, 각 알의 최고 펫은 앞 알의 최고 펫보다 높다
ok("epic: safari > starter", P.bonus("elephant", 1) > P.bonus("snowman", 1))
local prevTop = 0
for _, egg in P.EGGS do
	local top = 0
	for _, p in P.eggPets(egg.id) do
		top = math.max(top, P.bonus(p.id, 1))
	end
	ok(`{egg.id} top rises`, top > prevTop, `{top} <= {prevTop}`)
	prevTop = top
end
ok("better: star", P.better({ id = "cube", star = 2 }, { id = "cube", star = 1 }))
ok("better: rarity", P.better({ id = "tiger", star = 1 }, { id = "cube", star = 2 }))

-- 조각: 띠마다 +1
eq("shards T1", P.shardsForMerge(1), 1)
eq("shards T5", P.shardsForMerge(5), 1)
eq("shards T6", P.shardsForMerge(6), 2)
eq("shards T40", P.shardsForMerge(40), 8)
eq("release starter", P.releaseValue("cube"), 5)

-- 리버스 러시
eq("no rush at 0 rebirths", E.rushMult(0, 1), 1)
eq("rush until", E.rushUntil(1), E.tierCeiling(0) - E.RUSH_GAP)
eq("rush active", E.rushMult(1, 5), E.RUSH_MULT)
eq("rush over", E.rushMult(1, E.rushUntil(1)), 1)
eq("start tier r1", E.startTier(1), 2)
eq("start tier capped", E.startTier(14), E.START_TIER_MAX)
ok("start tier ≤ cap", E.startTier(2) <= E.tierCap(2))

-- 낮은 등급 보정
eq("low luck same tier", E.lowTierLuck(5, 5), 1)
eq("low luck above", E.lowTierLuck(8, 5), 1)
eq("low luck 2 below", E.lowTierLuck(3, 5), 2)
eq("low luck capped", E.lowTierLuck(1, 30), E.LOW_TIER_LUCK_MAX)

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
