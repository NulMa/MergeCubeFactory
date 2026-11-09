--!strict
-- lune run tests/merge/Economy.spec.luau (game 디렉터리에서)
-- 경제 공식이 tools/pacing_sim.py MergeGarden와 같은 값을 내는지, 정책 상한이 지켜지는지 확인.

local process = require("@lune/process")
local Economy = require("../../src/merge/shared/Economy")

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

local function near(name: string, got: number, want: number)
	ok(name, math.abs(got - want) <= math.abs(want) * 1e-9, `got {got}, want {want}`)
end

local k = Economy.COST_SCALE

-- 보정값이 들어가 있어야 한다 (1이면 자리표시 그대로)
ok("COST_SCALE calibrated", k > 1)

-- ramp: 0단계는 보정 없음 → 첫 구매가 몇 초 안에 (docs/13 첫 세션 표)
near("speedCost lv0 unscaled", Economy.speedCost(1, 0), 10)
near("tierCost tier1 unscaled", Economy.tierCost(1), 40)
near("slotCost first unscaled", Economy.slotCost(Economy.START_DROPPERS), 300)
near("incubatorCost first unscaled", Economy.incubatorCost(Economy.START_INCUBATORS), 150)
-- 완전 적용 단계 = 시뮬과 같은 식
near("speedCost lv6 full k", Economy.speedCost(2, 6), 10 * 1.55 ^ 6 * 1.3 * k)
near("tierCost tier4 full k", Economy.tierCost(4), 40 * 7 ^ 3 * k)
near("slotCost +3 full k", Economy.slotCost(Economy.START_DROPPERS + 3), 300 * 9 ^ 3 * k)
near("rebirthCost r5", Economy.rebirthCost(5), 2e4 * 12 ^ 5 * k)
near("rebirthCost r2 (ramped)", Economy.rebirthCost(2), 2e4 * 12 ^ 2 * k ^ (3 / 6))
near("rebirthCost r0 (ramped)", Economy.rebirthCost(0), 2e4 * k ^ (1 / 6))
near("rebirthCost r1 (ramped)", Economy.rebirthCost(1), 2e4 * 12 * k ^ (2 / 6))
-- 판 업그레이드 비용은 리버스마다 RUN_GROWTH(3)배, 유지되는 부화 속도는 그대로 (docs/13 §8)
near("runScale r0", Economy.runScale(0), 1)
near("runScale r3", Economy.runScale(3), 27)
near("speedCost r2", Economy.speedCost(1, 0, 2), 10 * 9)
near("tierCost r1", Economy.tierCost(1, 1), 40 * 3)
near("slotCost r1", Economy.slotCost(Economy.START_DROPPERS, 1), 300 * 3)
near("upgradeCost polish kept, unscaled", Economy.upgradeCost("polish", 0, 2) :: number, 500) -- 2026-10-20 팩토리 강화 유지
near("upgradeCost hatch kept, unscaled", Economy.upgradeCost("hatch", 0, 5) :: number, 1000)

-- 비용은 단계마다 증가해야 한다 (구매 순서가 꼬이지 않게)
local monotonic = true
for lv = 0, Economy.MAX_SPEED_LV - 1 do
	if Economy.speedCost(1, lv + 1) <= Economy.speedCost(1, lv) then
		monotonic = false
	end
end
ok("speedCost monotonic", monotonic)

-- 방치 수입: 10% × 최대 4시간 (docs/13 §4)
near("offline 1h", Economy.offlineEarnings(100, 3600), 100 * 0.1 * 3600)
near("offline capped at 4h", Economy.offlineEarnings(100, 48 * 3600), 100 * 0.1 * 4 * 3600)
near("offline negative away", Economy.offlineEarnings(100, -50), 0)

-- 코어
near("corePayout tier5", Economy.corePayout(50, 5), 50 * 120 * 0.6)
near("corePayout tier4 none", Economy.corePayout(50, 4), 0)
ok("steal protects top 2", Economy.stealProtectedFrom({ 3, 9, 9, 7, 5 }) == 7)
ok("steal protect one tier", Economy.stealProtectedFrom({ 4, 4 }) == 4)
near("corePayout capped", Economy.corePayout(50, 20), 50 * Economy.CORE_PAYOUT_CAP)
near("corePayout scale", Economy.corePayout(50, 5, 0.5), 50 * 60 * 0.6)

-- 머지 규칙
ok("canMerge same", Economy.canMerge(3, 3))
ok("canMerge diff", not Economy.canMerge(3, 4))
ok("canMerge max tier blocked", not Economy.canMerge(Economy.MAX_TIER, Economy.MAX_TIER))
near("combo 1", Economy.comboMultiplier(1), 1)
near("combo 3", Economy.comboMultiplier(3), 2)
near("combo cap", Economy.comboMultiplier(20), 3)
ok("tierCap r0", Economy.tierCap(0) == 6)
ok("tierCap capped", Economy.tierCap(99) == Economy.MAX_TIER - 1)

-- 등급 사다리 v3 (docs/13 §8): 40등급, 리버스마다 합치기 상한 +2 → 마지막 리버스에서 40
ok("MAX_TIER 40", Economy.MAX_TIER == 40)
ok("ceiling r0", Economy.tierCeiling(0) == 12)
ok("ceiling r1", Economy.tierCeiling(1) == 14)
-- +3/리버스 (2026-10-19, docs/13 §9.4): 10번째 리버스에서 T40, 남은 리버스는 수입 배수만
ok("ceiling reaches MAX_TIER by MAX_REBIRTH", Economy.tierCeiling(Economy.MAX_REBIRTH) == Economy.MAX_TIER)
ok("ceiling r14 = MAX_TIER", Economy.tierCeiling(14) == Economy.MAX_TIER)
ok("ceiling r13 below MAX_TIER", Economy.tierCeiling(13) < Economy.MAX_TIER)
ok("dropper cap follows ceiling", Economy.tierCap(10) == Economy.tierCeiling(10) - Economy.DROPPER_GAP)
ok("rebirth needs ceiling cube", not Economy.canRebirth(3, Economy.tierCeiling(3) - 1))
ok("rebirth with ceiling cube", Economy.canRebirth(3, Economy.tierCeiling(3)))
ok("no rebirth past max", not Economy.canRebirth(Economy.MAX_REBIRTH, Economy.MAX_TIER))
ok("canMerge below ceiling", Economy.canMerge(11, 11, Economy.tierCeiling(0)))
ok("canMerge at ceiling blocked", not Economy.canMerge(12, 12, Economy.tierCeiling(0)))
do
	local capOk = true
	for r = 0, Economy.MAX_REBIRTH do
		if Economy.tierCap(r) >= Economy.tierCeiling(r) then
			capOk = false
		end
	end
	ok("dropper cap stays below merge ceiling", capOk)
end
ok("tier names cover every tier", #Economy.TIER_NAMES == Economy.MAX_TIER)
do
	local coresOk = true
	for tier = 5, Economy.MAX_TIER do
		local c = Economy.CORES[tier]
		if not c or c.seconds <= 0 or c.seconds > 12 * 3600 or c.bonus <= 0 or c.name == "" then
			coresOk = false
		end
	end
	ok("cores for tiers 5..MAX", coresOk)
end
near("core 13 = 8h30m", Economy.CORES[13].seconds, 28800 + 1800)
near("core 40 capped 12h", Economy.CORES[40].seconds, 43200)
near("core 40 bonus", Economy.CORES[40].bonus, 0.06 + 0.01 * 28)
ok("core 40 name", Economy.CORES[40].name == "Infinity")
near("tierCost tier20 full k", Economy.tierCost(20), 40 * 7 ^ 19 * k)
ok("dropInterval floor", Economy.dropInterval(99) == 0.4)

-- 업그레이드 v2 (docs/14)
near("polish 0", Economy.polishMult(0), 1)
near("polish 9", Economy.polishMult(9), 1.9)
near("polish 10 milestone x2", Economy.polishMult(10), 4)
near("polish 20", Economy.polishMult(20), 12)
near("lucky 5", Economy.luckyChance(5), 0.1)
ok("tap 0 = tier 1", Economy.tapTier(0) == 1)
near("hatch 10", Economy.hatchScale(10), 0.5)
near("double 4", Economy.doubleDropChance(4), 0)
near("double 5", Economy.doubleDropChance(5), 0.15)
near("double 15", Economy.doubleDropChance(15), 0.45)
ok("upgradeCost max nil", Economy.upgradeCost("polish", 20) == nil)
ok("upgradeCost unknown nil", Economy.upgradeCost("nope", 0) == nil)
near("upgradeCost polish 0", Economy.upgradeCost("polish", 0) :: number, 500)
do
	local monotonic = true
	for _, id in Economy.UPGRADE_ORDER do
		local def = Economy.UPGRADES[id]
		for lv = 1, def.max - 1 do
			if (Economy.upgradeCost(id, lv) :: number) <= (Economy.upgradeCost(id, lv - 1) :: number) then
				monotonic = false
			end
		end
	end
	ok("upgradeCost monotonic", monotonic)
end
ok("nextMilestone", Economy.nextMilestone({ 10, 20 }, 10) == 20)
ok("nextMilestone done", Economy.nextMilestone({ 10, 20 }, 20) == nil)
ok("nextMilestone none", Economy.nextMilestone(nil, 0) == nil)

-- 섞기 충전
do
	local I = Economy.SHUFFLE_INTERVAL
	local f, at = Economy.shuffleRegen(0, 1000, 1000 + I - 1)
	ok("shuffle not yet", f == 0 and at == 1000)
	f, at = Economy.shuffleRegen(0, 1000, 1000 + I + 5)
	ok("shuffle +1 keeps remainder", f == 1 and at == 1000 + I)
	f, at = Economy.shuffleRegen(1, 1000, 1000 + I * 10)
	ok("shuffle capped", f == Economy.SHUFFLE_FREE_CAP and at == 1000 + I * 10)
	f, at = Economy.shuffleRegen(Economy.SHUFFLE_FREE_CAP, 5, 999)
	ok("shuffle at cap holds clock", f == Economy.SHUFFLE_FREE_CAP and at == 999)
end

-- 변이 (docs/16)
do
	local V = Economy.VARIANTS
	local N = Economy.NORMAL
	local rainbow = Economy.variantIndex("Divine") -- 가장 드문 변이
	ok("variant ids", V[N].id == "Normal" and rainbow == #V)
	-- 사다리 순서 (2026-10-18 확장): Galaxy 위에 Cosmic·Divine
	local ladder = { "Normal", "Metallic", "Neon", "Rainbow", "Galaxy", "Cosmic", "Divine" }
	local ordered = #V == #ladder
	for i, id in ladder do
		if not V[i] or V[i].id ~= id then
			ordered = false
		end
	end
	ok("variant ladder order", ordered)
	local dropFifth, gemsRise = true, true
	for i = 2, #V do
		if math.abs(V[i].dropChance - V[i].chance / 5) > 1e-12 then
			dropFifth = false
		end
		if V[i].gems <= V[i - 1].gems then
			gemsRise = false
		end
	end
	ok("dropChance = chance / 5", dropFifth)
	ok("rarer = more first-find gems", gemsRise)
	-- 첫 특별 큐브는 초반 몇 분 안에: 합치기 100번이면 90% 넘게 하나는 나온다
	local any = 0
	for i = 2, #V do
		any += V[i].chance
	end
	ok("first special early", 1 - (1 - any) ^ 100 > 0.9, `{any}`)
	-- 굴리기 경계: 가장 드문 것부터 누적 확률 순서
	local galaxy, cosmic = Economy.variantIndex("Galaxy"), Economy.variantIndex("Cosmic")
	ok("roll boundary divine", Economy.rollVariant(V[rainbow].chance * 0.99, false) == rainbow)
	ok("roll boundary cosmic", Economy.rollVariant(V[rainbow].chance * 1.01, false) == cosmic)
	ok(
		"roll boundary galaxy",
		Economy.rollVariant(V[rainbow].chance + V[cosmic].chance + V[galaxy].chance * 0.5, false) == galaxy
	)
	ok("fusion galaxy -> cosmic", Economy.inheritVariant(galaxy, galaxy) == cosmic)
	ok("fusion cosmic -> divine", Economy.inheritVariant(cosmic, cosmic) == rainbow)
	ok("divine fades to cosmic", Economy.inheritVariant(rainbow, galaxy) == cosmic)
	ok("toast from cosmic up", Economy.TOAST_VARIANT == cosmic)
	ok("variantIndex unknown -> Normal", Economy.variantIndex("Nope") == N and Economy.variantIndex(nil) == N)
	local rising = true
	for i = 2, #V do
		if V[i].mult <= V[i - 1].mult or (i > 2 and V[i].chance >= V[i - 1].chance) then
			rising = false
		end
	end
	ok("variants: rarer = bigger mult", rising)
	-- 굴리기: 0에 가까우면 가장 드문 것, 1에 가까우면 일반
	ok("roll tiny r -> rarest", Economy.rollVariant(0, false) == rainbow)
	ok("roll high r -> normal", Economy.rollVariant(0.999, false) == N)
	ok("roll drop is rarer", Economy.rollVariant(V[rainbow].chance * 0.9, true) ~= rainbow)
	ok("roll luck scales", Economy.rollVariant(V[rainbow].chance * 1.5, false, 2) == rainbow)
	-- 이어받기: 좋은 쪽이 한 단계 약해짐, 같은 변이끼리는 융합(한 단계 위), 일반끼리는 일반
	ok("inherit normal+normal", Economy.inheritVariant(N, N) == N)
	ok("inherit fades one step", Economy.inheritVariant(rainbow, N) == rainbow - 1)
	ok("inherit metallic fades to normal", Economy.inheritVariant(2, N) == N)
	ok("inherit fusion", Economy.inheritVariant(2, 2) == 3)
	ok("inherit fusion capped", Economy.inheritVariant(rainbow, rainbow) == rainbow)
	ok("merge keeps better of roll/inherit", Economy.mergeVariant(rainbow, N, 2) == rainbow - 1)
	ok("merge roll wins", Economy.mergeVariant(N, N, 3) == 3)
	-- 수입: 큐브마다 변이 배수
	near("cubeValue", Economy.cubeValue(3, rainbow), 2.4 ^ 2 * V[rainbow].mult)
	near(
		"trayIncomeOf",
		Economy.trayIncomeOf({ { tier = 1, variant = N }, { tier = 2, variant = 2 } }, 1.5),
		(1 + 2.4 * V[2].mult) * 1.5
	)
	near(
		"trayIncomeOf normal == trayIncome",
		Economy.trayIncomeOf({ { tier = 4, variant = N }, { tier = 4, variant = N } }, 2),
		Economy.trayIncome({ [4] = 2 }, 2)
	)
	-- 기대 배수: 높은 등급에서 수렴, 경제가 무너지지 않는 범위 (docs/16 §4)
	local means = Economy.variantMeanByTier(Economy.MAX_TIER)
	local top = means[#means]
	ok("variant mean > 1", means[1] > 1 and top > means[1], `top {top}`)
	ok("variant mean bounded (< 2)", top < 2, `top {top}`)
	ok("variant mean converges", math.abs(top - means[#means - 1]) < 0.02)
	-- 저장 형식: 예전 숫자 목록과 호환
	local t1, v1 = Economy.unpackCube(7)
	ok("unpack legacy number", t1 == 7 and v1 == N)
	ok("pack normal is number", Economy.packCube(5, N) == 5)
	local t2, v2 = Economy.unpackCube(Economy.packCube(9, rainbow))
	ok("pack/unpack variant", t2 == 9 and v2 == rainbow)
	local t3 = Economy.unpackCube("junk")
	ok("unpack junk", t3 == nil)
end

-- 도감·젬
do
	local total = Economy.codexTotal()
	ok("codexTotal", total == Economy.MAX_TIER * (#Economy.VARIANTS - 1))
	ok("codexTotal 240", total == 240)
	local risingCount = true
	for i = 2, #Economy.CODEX_MILESTONES do
		if Economy.milestoneCount(i) <= Economy.milestoneCount(i - 1) then
			risingCount = false
		end
	end
	ok("milestones strictly rising (within total)", risingCount)
	ok("codexKey", Economy.codexKey(7, Economy.variantIndex("Rainbow")) == "7:Rainbow")
	ok("last milestone = all", Economy.milestoneCount(#Economy.CODEX_MILESTONES) == total)
	local c, g = Economy.codexReward(0, 0)
	ok("no reward at 0", c == 0 and g == 0)
	c, g = Economy.codexReward(0, 5)
	ok("reward up to 5", c == 3 and g == 10 + 10 + 15, `{c} {g}`)
	c, g = Economy.codexReward(3, 5)
	ok("reward not twice", c == 3 and g == 0)
	c, g = Economy.codexReward(0, total)
	local all = 0
	for _, m in Economy.CODEX_MILESTONES do
		all += m.gems
	end
	ok("reward all", c == #Economy.CODEX_MILESTONES and g == all)
	ok("cosmetic default", Economy.cosmeticUnlocked(nil, nil, 0, false))
	ok("cosmetic gems needs owned", not Economy.cosmeticUnlocked(nil, 50, 99, false))
	ok("cosmetic codex", Economy.cosmeticUnlocked(5, nil, 5, false) and not Economy.cosmeticUnlocked(5, nil, 4, false))
	ok("cosmetic codex capped by total", Economy.cosmeticUnlocked(1e9, nil, total, false))
end

-- 이동 속도·훔친 큐브 운반 속도 (docs/22)
near("move speed lv0", Economy.moveSpeed(0), 16)
near("move speed lv10", Economy.moveSpeed(10), 28)
near("carry at or below best", Economy.carrySpeed(16, 5, 8), 16 * 0.8)
near("carry 3 tiers over best", Economy.carrySpeed(16, 11, 8), 16 * 0.8 * 0.64)
near("carry floor", Economy.carrySpeed(16, 30, 8), 16 * 0.8 * 0.35)
near("aura resist none", Economy.auraResist(0), 0)
near("aura resist tier 6", Economy.auraResist(6), 0.3)
near("aura resist max", Economy.auraResist(12), 0.6)
near("aura resist clamps", Economy.auraResist(20), 0.6)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
