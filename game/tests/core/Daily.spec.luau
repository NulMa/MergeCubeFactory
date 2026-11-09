--!strict
-- lune run tests/core/Daily.spec.luau (game 디렉터리에서)
-- core Daily rules with a made-up game (reward kinds are just strings the game grants itself).
local T = require("../T")
local Require = require("../Require")
local Daily = Require("src/core/shared/Daily")

local rules = Daily.new({
	smallEvery = 60,
	smallMax = 3,
	smallTable = { { id = "coins", weight = 3 }, { id = "seed", weight = 1 } },
	bigAt = { 600, 1200 },
	bigTable = { { id = "gems", weight = 1 } },
	questCount = 2,
	quests = {
		{ id = "plant", target = 10, text = "Plant seeds", scale = true },
		{ id = "sell", target = 5, text = "Sell flowers" },
		{ id = "water", target = 20, text = "Water plants", maxLevel = 2 },
	},
	scaleStep = 0.5,
	scaleMaxLevel = 4,
	login = {
		{ kind = "coins", amount = 100, text = "100 COINS" },
		{ kind = "seed", amount = 1, text = "RARE SEED" },
	},
	seedSalt = 777,
})

T.eq("dayOf", Daily.dayOf(86400 * 3 + 5), 3)
T.eq("secondsToNextDay", Daily.secondsToNextDay(86400 * 3 + 5), 86395)
T.eq("incomeReward floor", Daily.incomeReward(1.5, 10, 0), 15)
T.eq("incomeReward min", Daily.incomeReward(0, 10, 50), 50)

T.eq("roll small low", rules.rollSmall(0), "coins")
T.eq("roll small high", rules.rollSmall(0.8), "seed")
T.eq("roll big", rules.rollBig(0.5), "gems")

T.eq("small ready 0", rules.smallReady(59, 0), 0)
T.eq("small ready 2", rules.smallReady(130, 0), 2)
T.eq("small ready capped", rules.smallReady(10000, 1), 2)
T.eq("small next", rules.smallNextIn(130), 50)
T.eq("small next done", rules.smallNextIn(180), nil)
T.eq("big ready", rules.bigReady(1300, 1), 1)
T.eq("big next", rules.bigNextIn(700), 500)
T.eq("big next done", rules.bigNextIn(1200), nil)

local plant = rules.quest("plant") :: any
T.eq("quest lookup", plant.target, 10)
T.eq("quest missing", rules.quest("nope"), nil)
T.eq("target level 0", rules.questTarget(plant, 0), 10)
T.eq("target level 2", rules.questTarget(plant, 2), 20)
T.eq("target capped", rules.questTarget(plant, 99), 30)
T.eq("unscaled target", rules.questTarget(rules.quest("sell") :: any, 9), 5)

local a, b = rules.questsFor(20000, 0), rules.questsFor(20000, 0)
T.ok("quests deterministic", #a == 2 and a[1] == b[1] and a[2] == b[2] and a[1] ~= a[2])
local hasWater = false
for day = 20000, 20050 do
	for _, id in rules.questsFor(day, 3) do
		hasWater = hasWater or id == "water"
	end
end
T.ok("maxLevel filters quests", not hasWater)

T.eq("login first", rules.nextLogin(0), 1)
T.eq("login wraps", rules.nextLogin(2), 1)
T.done()
