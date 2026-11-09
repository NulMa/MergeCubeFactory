--!strict
-- lune run tests/core/Schedule.spec.luau (game 디렉터리에서)
local T = require("../T")
local Require = require("../Require")
local Schedule = Require("src/core/shared/Schedule")
local Offline = Require("src/core/shared/Offline")

-- 2026-10-31 is a Saturday. Unix day for 2026-10-31 = 20757
local SAT = 20757 * 86400
T.eq("weekday saturday", Schedule.weekday(SAT), 6)
T.eq("weekday thursday epoch", Schedule.weekday(0), 4)

local def = {
	daily = {
		{ id = "comet", hour = 12, duration = 1800 },
		{ id = "comet", hour = 20, minute = 30, duration = 1800 },
	},
	weekly = { { id = "eclipse", weekday = 6, hour = 18, duration = 3600 } },
}

T.eq("saturday has 3 slots", #Schedule.onDay(def, 20757), 3)
T.eq("friday has 2 slots", #Schedule.onDay(def, 20756), 2)

local noon = SAT + 12 * 3600
T.eq("not active before", Schedule.active(def, noon - 1), nil)
local a = Schedule.active(def, noon + 60) :: any
T.ok("active comet", a ~= nil and a.id == "comet" and a.endsAt == noon + 1800)
T.eq("ends exclusive", Schedule.active(def, noon + 1800), nil)
local n = Schedule.next(def, noon + 1800) :: any
T.ok("next is eclipse 18:00", n.id == "eclipse" and n.startsAt == SAT + 18 * 3600)
local st = Schedule.status(def, SAT + 18 * 3600 + 600) :: any
T.ok("status running eclipse", st.running and st.id == "eclipse" and st.seconds == 3000)
local st2 = Schedule.status(def, SAT + 23 * 3600) :: any
T.ok("status next tomorrow noon", not st2.running and st2.id == "comet" and st2.seconds == 13 * 3600)
-- evening slot crossing midnight is still active after 00:00
local late = { daily = { { id = "late", hour = 23, minute = 45, duration = 1800 } } }
T.ok("active across midnight", (Schedule.active(late, SAT + 86400 + 300) :: any).id == "late")
T.eq("empty schedule", Schedule.next({}, SAT), nil)

-- restock cycles: same stock on every server for the same cycle
local idx, endsAt = Schedule.cycle(300, SAT + 299)
T.ok("cycle index/end", idx == (SAT + 299) // 300 and endsAt == (idx + 1) * 300)
local items = {
	{ id = "seed_basic", min = 5, max = 10 },
	{ id = "seed_rare", chance = 0.3, min = 1, max = 2 },
	{ id = "seed_mythic", chance = 0.02 },
}
local s1, s2 = Schedule.stock(items, idx, 7), Schedule.stock(items, idx, 7)
local same = #s1 == #s2
for i, e in s1 do
	same = same and s2[i].id == e.id and s2[i].qty == e.qty
end
T.ok("stock deterministic", same)
T.ok("basic always present", s1[1].id == "seed_basic" and s1[1].qty >= 5 and s1[1].qty <= 10)
local rare, mythic = 0, 0
for c = 1, 2000 do
	for _, e in Schedule.stock(items, c, 7) do
		if e.id == "seed_rare" then
			rare += 1
		elseif e.id == "seed_mythic" then
			mythic += 1
		end
	end
end
T.ok(`rare ~30% ({rare}/2000)`, rare > 520 and rare < 680)
T.ok(`mythic ~2% ({mythic}/2000)`, mythic > 15 and mythic < 70)
local differs = 0
for c = 1, 50 do
	if Schedule.stock(items, c, 7)[1].qty ~= Schedule.stock(items, c, 8)[1].qty then
		differs += 1
	end
end
T.ok(`salt changes stock ({differs}/50 cycles differ)`, differs > 20)

T.eq("clock m:ss", Schedule.clock(75), "1:15")
T.eq("clock h:mm:ss", Schedule.clock(3723), "1:02:03")
T.eq("clock rounds up", Schedule.clock(0.2), "0:01")

-- offline settlement
local r = Offline.settle({ lastSeen = 1000, now = 1000 + 3600, rate = 10, cap = 4 * 3600, efficiency = 0.1 })
T.ok("offline 1h at 10%", r.amount == 3600 and r.seconds == 3600 and not r.capped)
local c = Offline.settle({ lastSeen = 0, now = 10 * 3600, rate = 1, cap = 4 * 3600 })
T.ok("offline capped", c.seconds == 4 * 3600 and c.amount == 4 * 3600 and c.capped)
T.eq("offline first visit", Offline.settle({ now = 5000, rate = 5, cap = 100 }).amount, 0)
T.eq("offline clock backwards", Offline.settle({ lastSeen = 9000, now = 5000, rate = 5, cap = 100 }).amount, 0)
T.eq("offline short absence", Offline.settle({ lastSeen = 1000, now = 1030, rate = 5, cap = 100 }).amount, 0)
T.eq("offline NaN rate", Offline.settle({ lastSeen = 0, now = 5000, rate = 0 / 0, cap = 100 }).amount, 0)
T.eq(
	"offline efficiency clamp",
	Offline.settle({ lastSeen = 0, now = 100, rate = 1, cap = 100, efficiency = 5 }).amount,
	100
)
T.eq("progress half", Offline.progress(100, 50, 125), 0.5)
T.eq("progress done", Offline.progress(100, 50, 999), 1)
T.eq("remaining", Offline.remaining(100, 50, 120), 30)
T.done()
