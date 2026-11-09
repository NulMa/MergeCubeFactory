--!strict
-- lune run tests/core/EventRules.spec.luau (game 디렉터리에서)
local T = require("../T")
local E = require("../Require")("src/core/shared/EventRules")

T.eq("delay min", E.randomDelay(10, 20, 0), 10)
T.eq("delay mid", E.randomDelay(10, 20, 0.5), 15)
T.eq("delay clamps", E.randomDelay(10, 20, 3), 20)

local list = { { id = "a", weight = 1 }, { id = "b", weight = 1 } }
T.eq("pick low", E.pickId(list, 0), "a")
T.eq("pick high", E.pickId(list, 0.75), "b")
T.eq("pick r=1 clamps", E.pickId(list, 1), "b")
T.eq("pick empty", E.pickId({}, 0.5), "")

T.eq("decay base", E.gaugeDecay(10, 2, 1, 0, 1), 8)
T.eq("decay passive", E.gaugeDecay(10, 1, 1, 3, 1), 6)
T.eq("decay floor 0", E.gaugeDecay(1, 5, 1, 0, 1), 0)
T.eq("decay ignores negative passive", E.gaugeDecay(10, 1, 1, -5, 1), 9)

T.eq("mult none", E.stackMult({}, 10), 1)
T.eq("mult stack", E.stackMult({ 2, 3 }, 10), 6)
T.eq("mult cap", E.stackMult({ 5, 3 }, 10), 10)

T.eq("announce fraction", E.announceLevel(12, 0.8, 6), 10)
T.eq("announce min", E.announceLevel(5, 0.8, 6), 6)

local h = {}
T.ok("rate 1", E.rateLimit(h, 0, 2, 10))
T.ok("rate 2", E.rateLimit(h, 1, 2, 10))
T.ok("rate full", not E.rateLimit(h, 2, 2, 10))
T.ok("rate window frees", E.rateLimit(h, 10, 2, 10))

T.eq("clock", E.clock(32), "0:32")
T.eq("clock rounds up", E.clock(59.1), "1:00")
T.eq("clock negative", E.clock(-3), "0:00")
T.eq("clock minutes", E.clock(605), "10:05")

T.near(
	"expected value",
	E.expectedValue({ { v = 10, weight = 3 }, { v = 2, weight = 1 } }, function(e: any): number
		return e.v
	end),
	8
)
T.near("income boost", E.incomeBoost(120, 0.5, 600), 0.1)
T.done()
