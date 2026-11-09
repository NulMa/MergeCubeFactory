--!strict
-- lune run tests/merge/Daily.spec.luau (game 디렉터리에서)
-- 접속 선물·일일 퀘스트 규칙 (shared/Daily). docs/23_DAILY.md

local process = require("@lune/process")
local Require = require("../Require")
local D = Require("src/merge/shared/Daily")

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

-- 작은 선물 ------------------------------------------------------------------------
eq("small 0s → 0", D.smallReady(0, 0), 0)
eq("small 179s → 0", D.smallReady(179, 0), 0)
eq("small 180s → 1", D.smallReady(180, 0), 1)
eq("small 600s, 1 claimed → 2", D.smallReady(600, 1), 2)
eq("small capped at 20", D.smallReady(99999, 0), D.SMALL_MAX)
eq("small next at 0s", D.smallNextIn(0), 180)
eq("small next at 200s", D.smallNextIn(200), 160)
eq("small next after cap", D.smallNextIn(D.SMALL_EVERY * D.SMALL_MAX), nil)
eq("small roll 0 → steal", D.rollSmall(0), "steal")
eq("small roll 0.07 → golden", D.rollSmall(0.07), "golden")
eq("small roll 0.5 → cash", D.rollSmall(0.5), "cash")
eq("small roll 0.9999 → cash", D.rollSmall(0.9999), "cash")
eq("small cash floor", D.smallCash(0), D.SMALL_CASH_MIN)
eq("small cash scales", D.smallCash(1000), 20000)

-- 큰 선물 --------------------------------------------------------------------------
eq("big 899s → 0", D.bigReady(899, 0), 0)
eq("big 900s → 1", D.bigReady(900, 0), 1)
eq("big 3600s, 2 claimed → 2", D.bigReady(3600, 2), 2)
eq("big next at 1000s", D.bigNextIn(1000), 800)
eq("big next after 60 min", D.bigNextIn(3600), nil)
eq("big roll 0 → steal", D.rollBig(0), "steal")
eq("big roll 0.4 → golden", D.rollBig(0.4), "golden")
eq("big roll 0.7 → gems_s", D.rollBig(0.7), "gems_s")
eq("big roll 0.95 → gems_l", D.rollBig(0.95), "gems_l")

-- 젬 상한: 큰 선물 4개가 전부 큰 젬이어도 하루 젬이 적다 --------------------------
local maxGiftGems = #D.BIG_AT * D.GEMS_L
local questGems = D.QUEST_COUNT * D.QUEST_GEMS + D.BONUS_GEMS
ok("daily gems stay small", maxGiftGems + questGems <= 45, `{maxGiftGems + questGems}`)

-- 퀘스트 ---------------------------------------------------------------------------
for day = 20000, 20400 do
	local q = D.questsFor(day)
	local seen = {}
	local good = #q == D.QUEST_COUNT
	for _, id in q do
		if seen[id] or not D.quest(id) then
			good = false
		end
		seen[id] = true
	end
	if not good then
		ok(`quests day {day} distinct`, false)
		break
	end
end
ok("quests deterministic", table.concat(D.questsFor(20380), ",") == table.concat(D.questsFor(20380), ","))
do
	local late = true
	for day = 20380, 20480 do
		for _, id in D.questsFor(day, 10) do
			late = late and id ~= "upgrade"
		end
	end
	ok("upgrade quest skipped late", late)
end
ok("quests vary by day", table.concat(D.questsFor(20380), ",") ~= table.concat(D.questsFor(20381), ","))
local counts = {}
for day = 20000, 20999 do
	for _, id in D.questsFor(day) do
		counts[id] = (counts[id] or 0) + 1
	end
end
for _, q in D.QUESTS do
	ok(`quest {q.id} appears`, (counts[q.id] or 0) > 250, tostring(counts[q.id]))
end
eq("day of epoch+1d", D.dayOf(86400 + 5), 1)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
