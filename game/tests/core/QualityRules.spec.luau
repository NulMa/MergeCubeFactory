--!strict
-- lune run tests/core/QualityRules.spec.luau (game 디렉터리에서)
local T = require("../T")
local Q = require("../Require")("src/core/shared/QualityRules")

-- caps from hints
T.eq("cap default high", Q.capFromHints({}), Q.HIGH)
T.eq("cap auto setting high", Q.capFromHints({ savedQuality = 0 }), Q.HIGH)
T.eq("cap low setting", Q.capFromHints({ savedQuality = 2 }), Q.LOW)
T.eq("cap mid setting", Q.capFromHints({ savedQuality = 5 }), Q.MEDIUM)
T.eq("cap high setting", Q.capFromHints({ savedQuality = 9 }), Q.HIGH)
T.eq("cap phone memory medium", Q.capFromHints({ touch = true, memoryMb = 1800 }), Q.MEDIUM)
T.eq("cap phone memory low", Q.capFromHints({ touch = true, memoryMb = 3000 }), Q.LOW)
T.eq("cap pc memory ignored", Q.capFromHints({ touch = false, memoryMb = 3000 }), Q.HIGH)

-- steady 60 fps keeps high
local s = Q.newState(Q.HIGH)
local changed = false
for _ = 1, 600 do
	changed = Q.step(s, 1 / 60) or changed
end
T.ok("60fps stays high", s.tier == Q.HIGH and not changed)

-- a short hitch does not drop
for _ = 1, 30 do
	Q.step(s, 1 / 20) -- 1.5 s at 20 fps
end
for _ = 1, 120 do
	Q.step(s, 1 / 60)
end
T.eq("short hitch keeps high", s.tier, Q.HIGH)

-- sustained 25 fps drops one tier after DOWN_HOLD, then another
local t = 0
while s.tier == Q.HIGH and t < 20 do
	Q.step(s, 1 / 25)
	t += 1 / 25
end
T.ok(
	`drops to medium after ~{math.floor(t * 10) / 10}s`,
	s.tier == Q.MEDIUM and t >= Q.DOWN_HOLD and t < Q.DOWN_HOLD + 2
)
for _ = 1, 25 * 6 do
	Q.step(s, 1 / 25)
end
T.eq("drops to low", s.tier, Q.LOW)
for _ = 1, 25 * 10 do
	Q.step(s, 1 / 25)
end
T.eq("never below low", s.tier, Q.LOW)

-- recovers slowly, never above cap
local up = 0
while s.tier == Q.LOW and up < 100 do
	Q.step(s, 1 / 60)
	up += 1 / 60
end
T.ok(`recovers after ~{math.floor(up)}s`, s.tier == Q.MEDIUM and up >= Q.UP_HOLD)
local capped = Q.newState(Q.MEDIUM)
for _ = 1, 60 * 120 do
	Q.step(capped, 1 / 60)
end
T.eq("stays at device cap", capped.tier, Q.MEDIUM)
T.ok("setCap lowers tier", Q.setCap(capped, Q.LOW) and capped.tier == Q.LOW)
T.ok("ignores dt 0", not Q.step(capped, 0))

-- particle budget
local b = Q.newBudget()
T.eq("high passes through", Q.particles(b, Q.HIGH, 37, 0), 37)
T.eq("high never budgets", Q.particles(b, Q.HIGH, 100000, 0), 100000)
local m = Q.newBudget()
T.eq("medium scales", Q.particles(m, Q.MEDIUM, 20, 0), 13)
local low = Q.newBudget()
local total = 0
for _ = 1, 100 do
	total += Q.particles(low, Q.LOW, 10, 0.5)
end
T.eq("low budget per second", total, Q.PARTICLES_PER_SEC[Q.LOW])
T.ok("budget refills next second", Q.particles(low, Q.LOW, 10, 1.6) > 0)
T.done()
