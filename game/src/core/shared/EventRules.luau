--!strict
-- Neutral formulas for in-server events (bonus drops, fever gauges, buffs, announcements). docs/17, docs/33.
-- Pure, Lune-tested (tests/core/EventRules.spec). Games keep their own numbers (Merge: shared/EventsConfig).

local Rarity = require(script.Parent.Rarity)

local EventRules = {}

-- Uniform delay in [min, max] for r in [0, 1) (e.g. next bonus drop)
function EventRules.randomDelay(min: number, max: number, r: number): number
	return min + (max - min) * math.clamp(r, 0, 1)
end

-- Weighted reward id (free random only). r is clamped below 1 so r = 1 never falls off the table
function EventRules.pickId(list: { any }, r: number): string
	local e = Rarity.pick(list, math.clamp(r, 0, 0.999999))
	return if e then e.id else ""
end

-- Gauge that drains over time. decay/s = base + passiveRate x passiveK
-- (passive progress cancels out, so only active play fills it)
function EventRules.gaugeDecay(gauge: number, dt: number, base: number, passiveRate: number, passiveK: number): number
	local rate = base + math.max(0, passiveRate) * passiveK
	return math.max(0, gauge - rate * dt)
end

-- Product of active buff multipliers, capped
function EventRules.stackMult(mults: { number }, cap: number): number
	local m = 1
	for _, k in mults do
		m *= k
	end
	return math.min(m, cap)
end

-- Level that triggers a server announcement: fraction of the top level, at least minLevel
function EventRules.announceLevel(maxLevel: number, fraction: number, minLevel: number): number
	return math.max(minLevel, math.floor(maxLevel * fraction + 0.5))
end

-- Sliding window limit: drops entries older than window from history; if fewer than max remain,
-- records now and returns true
function EventRules.rateLimit(history: { number }, now: number, max: number, window: number): boolean
	for i = #history, 1, -1 do
		if now - history[i] >= window then
			table.remove(history, i)
		end
	end
	if #history >= max then
		return false
	end
	table.insert(history, now)
	return true
end

-- Seconds left -> "0:32" (minutes:seconds, rounded up)
function EventRules.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Expected value of a weighted table: sum of p(entry) x valueOf(entry), in list order
function EventRules.expectedValue(list: { any }, valueOf: (any) -> number): number
	local total = Rarity.total(list)
	local ev = 0
	for _, e in list do
		ev += e.weight / total * valueOf(e)
	end
	return ev
end

-- Income share of a recurring bonus: value (in income-seconds) x catch rate / cycle seconds
function EventRules.incomeBoost(evSeconds: number, catchRate: number, cycleSeconds: number): number
	return evSeconds * catchRate / cycleSeconds
end

return EventRules
