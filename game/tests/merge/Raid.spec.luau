--!strict
-- lune run tests/merge/Raid.spec.luau (game 디렉터리에서)
-- 보스 레이드 규칙(shared/Raid)과 접속 중 가속(shared/Online), 출석·퀘스트 목표(shared/Daily).

local process = require("@lune/process")
local Raid = require("../../src/merge/shared/Raid")
local Online = require("../../src/core/shared/Online")
local Daily = require("../Require")("src/merge/shared/Daily")

local passed, failed = 0, 0

local function ok(name: string, cond: boolean)
	if cond then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print("FAIL  " .. name)
	end
end

-- 보스 체력: 혼자여도 최소값, 사람이 늘면 조금씩 (2배 인원 ≠ 2배 체력)
ok("hp solo floor", Raid.hp(1) == Raid.MIN_HP)
ok("hp 0 players", Raid.hp(0) == Raid.MIN_HP)
ok("hp grows", Raid.hp(4) > Raid.hp(2) and Raid.hp(2) > Raid.hp(1))
ok("hp sublinear", Raid.hp(2) < 2 * Raid.hp(1) * 0.9 and Raid.hp(8) < 2 * Raid.hp(4) * 0.9)
-- 여럿이 해도 패턴을 몇 번은 보게 (0레벨 배트로 쉬지 않고 때려도 20초 이상)
ok("group not instant", Raid.hp(8) / 8 * Raid.HIT_GAP >= 20 and Raid.hp(20) / 20 * Raid.HIT_GAP >= 15)
-- 혼자서도 제한 시간 안에 잡을 수 있어야 한다 (0레벨 배트 간격 × 체력 < 제한 시간의 70%, 패턴 피하는 시간 여유)
ok("solo winnable", Raid.hp(1) * Raid.HIT_GAP < Raid.FIGHT * 0.7)
ok("group winnable", Raid.hp(8) / 8 * Raid.HIT_GAP < Raid.FIGHT * 0.7)

-- 크리티컬: 기본 5%, 높은 배트일수록 ↑, 모두 1 미만
ok("crit base", Raid.critChance(nil) == Raid.CRIT_BASE and Raid.critChance("bat_aluminum") == Raid.CRIT_BASE)
ok("crit better bat", Raid.critChance("bat_rainbow") > Raid.critChance("bat_wood"))
ok("crit unknown bat", Raid.critChance("nope") == Raid.CRIT_BASE)

-- 보스 로테이션: 3~4종, 차례로 돌고 처음으로, 패턴이 서로 다름
ok("bosses 3-4", #Raid.BOSSES >= 3 and #Raid.BOSSES <= 4)
ok(
	"boss rotation",
	Raid.bossAt(0) == Raid.BOSSES[1]
		and Raid.bossAt(1) == Raid.BOSSES[2]
		and Raid.bossAt(#Raid.BOSSES) == Raid.BOSSES[1]
)
local KNOWN = { slam = true, meteor = true, laser = true, pounce = true, storm = true, spokes = true }
local seen: { [string]: boolean } = {}
local allKnown = true
for _, b in Raid.BOSSES do
	local key = table.concat(b.patterns, "+")
	allKnown = allKnown and not seen[key] and #b.patterns >= 2
	seen[key] = true
	for _, p in b.patterns do
		allKnown = allKnown and KNOWN[p] == true
	end
end
ok("boss patterns differ", allKnown)
ok("boss lookup", Raid.boss("storm").id == "storm" and Raid.boss("nope") == Raid.BOSSES[1])
-- 덮치기 경고 시간 안에 원 밖으로 걸어 나갈 수 있어야 한다 (기본 걷기 16)
ok("pounce escapable", Raid.POUNCE_R < 16 * Raid.POUNCE_WARN)

-- 코인
ok("coins below min hits", Raid.coins(true, Raid.MIN_HITS - 1) == 0)
ok("coins win flat", Raid.coins(true, Raid.MIN_HITS) == Raid.WIN_COINS and Raid.coins(true, 500) == Raid.WIN_COINS)
ok("coins lose none", Raid.coins(false, 30) == 0 and Raid.coins(false, 30, true) == 0)
ok("coins out contribution", Raid.coins(true, 30, true) == math.max(1, math.floor(Raid.WIN_COINS * 0.1 + 0.5)))
ok("coins out needs hits", Raid.coins(true, Raid.MIN_HITS - 1, true) == 0)

-- 강화
ok("effect none", Raid.effect(nil, "income") == 0)
ok("effect income", math.abs(Raid.effect({ income = 3 }, "income") - 0.3) < 1e-9)
ok("effect clamps", Raid.effect({ speed = 999 }, "speed") == 6 * 0.05)
ok("effect unknown", Raid.effect({ x = 3 }, "x") == 0)
ok("cost flat", Raid.cost(0) == Raid.cost(4) and Raid.cost(0) == Raid.COST)
ok("cost income+", Raid.cost(3, "income2") == 100 and Raid.cost(3, "speed") == Raid.COST)
ok("income+ locked", not Raid.unlocked({ income = 9 }, "income2") and Raid.unlocked({ income = 10 }, "income2"))
ok("income+ uncapped", math.abs(Raid.incomeBonus({ income = 10, income2 = 50 }) - 2) < 1e-9)
ok("guard shortens stun", Raid.stunFor(0.5) < Raid.STUN and Raid.stunFor(0) == Raid.STUN)
ok("spoke stripe covers hit", Raid.SPOKE_STRIPE / 2 >= Raid.SPOKE_HIT)
ok("resist cap", Raid.combineResist(0.6, 0.5) == Raid.RESIST_CAP)
ok("resist combine", math.abs(Raid.combineResist(0.2, 0.5) - 0.6) < 1e-9)

-- 온라인 연속 보너스
ok("streak 0", Online.streakBonus(0) == 0)
ok("streak 5m", Online.streakBonus(5 * 60) == 0.1)
ok("streak 31m", Online.streakBonus(31 * 60) == 0.5)
local nextIn, nextBonus = Online.streakNext(60)
ok("streak next", nextIn == 4 * 60 and nextBonus == 0.1)
ok("streak max next nil", Online.streakNext(3600) == nil)

-- 콤보 현금
ok("combo 2 nothing", Online.comboSeconds(2) == 0)
ok("combo 3", Online.comboSeconds(3) == Online.COMBO_STEP)
ok("combo cap", Online.comboSeconds(500) == Online.COMBO_CAP)
ok("box cash floor", Online.boxCash(0) == Online.BOX_CASH_MIN)

-- 출석·퀘스트 목표
ok("login cycles", Daily.nextLogin(0) == 1 and Daily.nextLogin(7) == 1 and Daily.nextLogin(3) == 4)
ok("login 7 days", #Daily.LOGIN == 7)
local merge = Daily.quest("merge") :: Daily.Quest
local tap = Daily.quest("tap") :: Daily.Quest
ok("quest target r0", Daily.questTarget(merge, 0) == merge.target)
ok("quest target scales", Daily.questTarget(merge, 4) > merge.target)
ok("quest target cap", Daily.questTarget(merge, 99) == Daily.questTarget(merge, Daily.QUEST_SCALE_MAX_REBIRTHS))
ok("quest fixed", Daily.questTarget(tap, 8) == tap.target)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
