--!strict
-- lune run tests/core/Rarity.spec.luau (game 디렉터리에서)
local T = require("../T")
local Require = require("../Require")
local Rarity = Require("src/core/shared/Rarity")

local list = {
	{ id = "a", weight = 90 },
	{ id = "b", weight = 9 },
	{ id = "c", weight = 1 },
}

T.eq("total", Rarity.total(list), 100)
T.eq("pick 0", (Rarity.pick(list, 0) :: any).id, "a")
T.eq("pick 0.8999", (Rarity.pick(list, 0.8999) :: any).id, "a")
T.eq("pick 0.9", (Rarity.pick(list, 0.9) :: any).id, "b")
T.eq("pick 0.995", (Rarity.pick(list, 0.995) :: any).id, "c")
T.eq("pick ~1 falls to last", (Rarity.pick(list, 0.9999999) :: any).id, "c")
T.eq("pick empty", Rarity.pick({}, 0.5), nil)
T.eq(
	"zero weight never picked",
	(Rarity.pick({ { id = "x", weight = 0 }, { id = "y", weight = 1 } }, 0) :: any).id,
	"y"
)
T.near("chance", Rarity.chance(list, list[2]), 0.09)

-- display strings
T.eq("oneIn 1/10", Rarity.oneIn(0.1), "1 in 10")
T.eq("oneIn 1/1M", Rarity.oneIn(1e-6), "1 in 1,000,000")
T.eq("oneIn rounds", Rarity.oneIn(0.00035), "1 in 2,857")
T.eq("oneIn 0", Rarity.oneIn(0), "1 in ∞")
T.eq("commas small", Rarity.commas(999), "999")
T.eq("commas 1000", Rarity.commas(1000), "1,000")
T.eq("commas 123456", Rarity.commas(123456), "123,456")
T.eq("percent 45%", Rarity.percent(0.45), "45%")
T.eq("percent 0.5%", Rarity.percent(0.005), "0.5%")
T.eq("percent 1/1M", Rarity.percent(1e-6), "0.0001%")
T.eq("percent 1/3", Rarity.percent(1 / 3), "33.3%")
T.eq("percent 100", Rarity.percent(1), "100%")
T.eq("percent 0", Rarity.percent(0), "0%")
local rows = Rarity.rows(list)
T.ok("rows", #rows == 3 and rows[3].oneIn == "1 in 100" and rows[1].percent == "90%")

-- deterministic rng
local r1, r2 = Rarity.rng(42), Rarity.rng(42)
local same, inRange = true, true
for _ = 1, 1000 do
	local a, b = r1(), r2()
	same = same and a == b
	inRange = inRange and a >= 0 and a < 1
end
T.ok("rng same seed same sequence", same)
T.ok("rng in [0,1)", inRange)
T.ok("rng different seeds differ", Rarity.rng(1)() ~= Rarity.rng(2)())
T.ok("seed mixes", Rarity.seed(1, 2) ~= Rarity.seed(2, 1))
T.eq("seed deterministic", Rarity.seed(20000, 3), Rarity.seed(20000, 3))
-- precision: the old mixer lost bits past 2^53 so these collapsed to one seed
local uid = 4012345678
T.ok("seed last arg 7 vs 8 differ", Rarity.seed(42, uid, 0, 7) ~= Rarity.seed(42, uid, 0, 8))
local seen, distinct = {}, true
for a = 1, 40 do
	for b = 1, 40 do
		local s = Rarity.seed(123456789, uid + a, b)
		if seen[s] then
			distinct = false
		end
		seen[s] = true
	end
end
T.ok("seed 1600 big-input combos all distinct", distinct)
T.ok("seed big value split (v and v + M differ)", Rarity.seed(5, 7) ~= Rarity.seed(5, 7 + 2147483647))
T.ok("seed negative ok", Rarity.seed(-3) ~= Rarity.seed(3) and Rarity.seed(-3) >= 0)
local s = Rarity.seed(2 ^ 52, 99, 2 ^ 40)
T.ok("seed in range", s >= 0 and s < 2147483647 and s == math.floor(s))

-- distribution sanity: 100k rolls of the 90/9/1 table
local rng = Rarity.rng(7)
local counts = { a = 0, b = 0, c = 0 }
for _ = 1, 100000 do
	local e = Rarity.roll(list, rng) :: any
	counts[e.id] += 1
end
T.ok(`distribution a {counts.a}`, math.abs(counts.a / 100000 - 0.9) < 0.01)
T.ok(`distribution c {counts.c}`, math.abs(counts.c / 100000 - 0.01) < 0.002)

-- boost keeps fields, multiplies weights
local boosted = Rarity.boost(list, function(e: any): number
	return if e.id == "c" then 10 else 1
end)
T.ok("boost copy", boosted[3].weight == 10 and list[3].weight == 1 and (boosted[3] :: any).id == "c")
T.near("boost chance", Rarity.chance(boosted, boosted[3]), 10 / 109)

-- reveal levels
T.eq("level common", Rarity.level(0.5), 1)
T.eq("level 1/10", Rarity.level(0.1), 2)
T.eq("level 1/999", Rarity.level(1 / 999), 2)
T.eq("level 1/1000", Rarity.level(0.001), 3)
T.eq("level 1/100k", Rarity.level(1e-5), 4)
T.eq("level 1/1M", Rarity.level(1e-6), 5)
T.eq("level custom ladder", Rarity.level(0.01, { 2, 50 }), 2)
T.done()
