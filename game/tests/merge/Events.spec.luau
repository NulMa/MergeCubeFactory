--!strict
-- lune run tests/merge/Events.spec.luau (game 디렉터리에서)
-- 황금 큐브·머지 피버·서버 알림의 순수 공식 (shared/EventsConfig) 확인. docs/17_EVENTS.md

local process = require("@lune/process")
local E = require("../Require")("src/merge/shared/EventsConfig")

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

-- 보상표 ------------------------------------------------------------------------
eq("reward weights sum 100", E.totalWeight(), 100)
eq("pick 0 → cash", E.pickReward(0), "cash")
eq("pick 0.449 → cash", E.pickReward(0.449), "cash")
eq("pick 0.45 → frenzy", E.pickReward(0.45), "frenzy")
eq("pick 0.799 → frenzy", E.pickReward(0.799), "frenzy")
eq("pick 0.80 → storm", E.pickReward(0.80), "storm")
eq("pick 0.92 → rain", E.pickReward(0.92), "rain")
eq("pick 0.98 → jackpot", E.pickReward(0.98), "jackpot")
eq("pick 1 (clamped) → jackpot", E.pickReward(1), "jackpot")

-- 표본 비율이 가중치와 맞는지 (고정 시드)
do
	-- Lune에는 Random이 없어 Park–Miller LCG (곱이 2^53 안에 들어감)
	local seed = 42
	local function nextNumber(): number
		seed = (seed * 48271) % 2147483647
		return seed / 2147483647
	end
	local n = 200000
	local hits: { [string]: number } = {}
	for _ = 1, n do
		local id = E.pickReward(nextNumber())
		hits[id] = (hits[id] or 0) + 1
	end
	for _, rw in E.REWARDS do
		local got = (hits[rw.id] or 0) / n * 100
		ok(`sample {rw.id} ≈ {rw.weight}%`, math.abs(got - rw.weight) < 0.5, `got {got}`)
	end
end

-- 등장 간격 -------------------------------------------------------------------------
eq("delay r=0 → 4 min", E.goldenDelay(0), 240)
eq("delay r=1 → 10 min", E.goldenDelay(1), 600)
eq("delay clamps", E.goldenDelay(5), 600)

-- 현금 ---------------------------------------------------------------------------
eq("cash floor", E.cashBurst(0), E.CASH_FLOOR)
eq("cash 150 s", E.cashBurst(1000), 150000)

-- 큐브 보상 등급 (MAX_TIER는 인자: 12든 36이든 같은 규칙) ---------------------------------
eq("rain best-1", E.rainTier(8, 7, 12), 7)
eq("rain capped by dropper+2 (after rebirth)", E.rainTier(11, 1, 12), 3)
eq("rain never MAX", E.rainTier(12, 11, 12), 11)
eq("rain at least 1", E.rainTier(1, 1, 12), 1)
eq("rain with 36 tiers", E.rainTier(30, 20, 36), 22)
eq("jackpot best+1", E.jackpotTier(9, 12), 10)
eq("jackpot capped", E.jackpotTier(12, 12), 12)
eq("jackpot 36 tiers", E.jackpotTier(30, 36), 31)

-- 피버 -----------------------------------------------------------------------------
eq("decay idle", E.feverDecay(10, 2, 0), 8)
eq("decay passive", E.feverDecay(10, 1, 3), 6)
eq("decay floor 0", E.feverDecay(1, 5, 2), 0)
do
	-- 방치: 초당 투하 3회 → 합치기 약 3회/초가 그대로 감쇠와 상쇄 → 30초 뒤에도 목표 미달
	local g = 0
	for _ = 1, 30 do
		g += 3
		g = E.feverDecay(g, 1, 3)
	end
	ok("passive merges alone never reach FEVER", g < E.FEVER_GOAL, `gauge {g}`)
	-- 직접 투하(0.4초 쿨다운 = 2.5회/초)를 더하면 약 20초에 도달
	g = 0
	local t = 0
	while g < E.FEVER_GOAL and t < 120 do
		g += 3 + 2.5
		g = E.feverDecay(g, 1, 3)
		t += 1
	end
	ok("active tapping reaches FEVER in 10..40 s", t >= 10 and t <= 40, `t {t}`)
end
do
	local dps = E.dropsPerSecond({ 2, 1 }, { 0, 0.15 }, 1)
	ok("drops/s", math.abs(dps - (0.5 + 1.15)) < 1e-9, `got {dps}`)
	local storm = E.dropsPerSecond({ 2, 1 }, { 0, 0.15 }, E.STORM_SCALE)
	ok("storm triples drops/s", math.abs(storm - dps * 3) < 1e-9, `got {storm}`)
end

-- 배수 -----------------------------------------------------------------------------
eq("no buff", E.buffMult(false, false), 1)
eq("frenzy", E.buffMult(true, false), E.FRENZY_MULT)
eq("fever", E.buffMult(false, true), E.FEVER_MULT)
eq("frenzy+fever capped", E.buffMult(true, true), math.min(E.MULT_CAP, E.FRENZY_MULT * E.FEVER_MULT))

-- 알림 -----------------------------------------------------------------------------
eq("announce tier 12 → 10", E.announceTier(12), 10)
eq("announce tier 36 → 29", E.announceTier(36), 29)
eq("announce tier min", E.announceTier(5), E.ANNOUNCE_MIN_TIER)
do
	local h = {}
	ok("limit 1", E.rateLimit(h, 0, 3, 60))
	ok("limit 2", E.rateLimit(h, 1, 3, 60))
	ok("limit 3", E.rateLimit(h, 2, 3, 60))
	ok("limit 4 blocked", not E.rateLimit(h, 3, 3, 60))
	ok("window passes", E.rateLimit(h, 60, 3, 60))
	eq("history pruned", #h, 3)
end

eq("clock 32", E.clock(32), "0:32")
eq("clock 300", E.clock(300), "5:00")
eq("clock rounds up", E.clock(0.2), "0:01")
eq("clock negative", E.clock(-3), "0:00")

-- 경제 영향 (docs/15 §4: 황금 큐브 총수입 +15~25%) ---------------------------------------
-- 근사: DROP STORM 20초 = 수입 20초치, TIER RAIN 큐브 1개 = 15초치, JACKPOT = 120초치
do
	local ev = E.expectedGoldenSeconds(20, 15, 120)
	local full = E.goldenIncomeBoost(ev, 1)
	local typical = E.goldenIncomeBoost(ev, 0.7)
	ok("golden boost at 100% catch ≤ 30%", full <= 0.30, `{full}`)
	ok("golden boost at 70% catch in 15..25%", typical >= 0.15 and typical <= 0.25, `{typical}`)
	print(string.format("      EV %.1f s/cube, boost full %.1f%%, 70%% catch %.1f%%", ev, full * 100, typical * 100))
end

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
