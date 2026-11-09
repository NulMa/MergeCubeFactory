--!strict
-- Fixed-time live events and shared restock cycles (docs/32 §3-4, docs/33). Pure, Lune-tested (tests/core/Schedule).
-- All times are UTC unix seconds. Every server computes the same answer from the same clock, so events start
-- together everywhere and every server shows the same shop stock and countdown (no DataStore / MessagingService).
-- Use the shared clock: server os.time() / workspace:GetServerTimeNow(), client workspace:GetServerTimeNow().
--
--   local def = {
--     daily = { { id = "comet", hour = 12, minute = 0, duration = 1800 }, { id = "comet", hour = 20, duration = 1800 } },
--     weekly = { { id = "eclipse", weekday = 6, hour = 18, duration = 3600 } }, -- weekday 0 = Sunday .. 6 = Saturday
--   }
--   Schedule.active(def, now) -> occurrence or nil;  Schedule.next(def, now) -> next occurrence
--   Schedule.cycle(300, now) -> index, endsAt;  Schedule.stock(items, index, salt) -> same list on every server

local Rarity = require(script.Parent.Rarity)

local Schedule = {}

export type Slot = {
	id: string,
	hour: number, -- 0..23 UTC
	minute: number?,
	duration: number, -- seconds
	weekday: number?, -- weekly slots only: 0 = Sunday .. 6 = Saturday (UTC)
	data: any?, -- free field for the game (multipliers, weather, ...)
}
export type Def = { daily: { Slot }?, weekly: { Slot }? }
export type Occurrence = { id: string, startsAt: number, endsAt: number, slot: Slot }

local DAY = 86400

function Schedule.dayOf(t: number): number
	return t // DAY
end

-- 0 = Sunday .. 6 = Saturday (1970-01-01 was a Thursday)
function Schedule.weekday(t: number): number
	return (t // DAY + 4) % 7
end

-- Occurrences that start on UTC day d, in time order
function Schedule.onDay(def: Def, d: number): { Occurrence }
	local out: { Occurrence } = {}
	local function add(s: Slot)
		local start = d * DAY + s.hour * 3600 + (s.minute or 0) * 60
		table.insert(out, { id = s.id, startsAt = start, endsAt = start + s.duration, slot = s })
	end
	local daily: { Slot } = def.daily or {}
	for _, s in daily do
		add(s)
	end
	local wd = (d + 4) % 7
	local weekly: { Slot } = def.weekly or {}
	for _, s in weekly do
		if s.weekday == wd then
			add(s)
		end
	end
	table.sort(out, function(a, b)
		if a.startsAt ~= b.startsAt then
			return a.startsAt < b.startsAt
		end
		return a.id < b.id
	end)
	return out
end

-- The event running at now (the one that started last if several overlap), or nil
function Schedule.active(def: Def, now: number): Occurrence?
	local best: Occurrence? = nil
	local d = Schedule.dayOf(now)
	for day = d - 2, d do -- slots last at most two days
		for _, o in Schedule.onDay(def, day) do
			if o.startsAt <= now and now < o.endsAt and (best == nil or o.startsAt >= best.startsAt) then
				best = o
			end
		end
	end
	return best
end

-- The next event that starts after now (within 8 days), or nil when the schedule is empty
function Schedule.next(def: Def, now: number): Occurrence?
	local d = Schedule.dayOf(now)
	for day = d, d + 8 do
		for _, o in Schedule.onDay(def, day) do
			if o.startsAt > now then
				return o
			end
		end
	end
	return nil
end

-- What a countdown should show: running event (ends in) or the next one (starts in)
export type Status = { running: boolean, id: string, seconds: number, occurrence: Occurrence }
function Schedule.status(def: Def, now: number): Status?
	local a = Schedule.active(def, now)
	if a then
		return { running = true, id = a.id, seconds = a.endsAt - now, occurrence = a }
	end
	local n = Schedule.next(def, now)
	if n then
		return { running = false, id = n.id, seconds = n.startsAt - now, occurrence = n }
	end
	return nil
end

-- Restock cycles: cycle index and the time it ends. Same on every server.
function Schedule.cycle(period: number, now: number): (number, number)
	local index = now // period
	return index, (index + 1) * period
end

-- Shop stock for one cycle. item.chance (0..1, default 1) = appears this cycle; quantity in [min, max].
-- Deterministic: same items + index + salt -> same stock everywhere. salt = per-game / per-shop number.
export type StockItem = { id: string, chance: number?, min: number?, max: number? }
export type Stocked = { id: string, qty: number }
function Schedule.stock(items: { StockItem }, index: number, salt: number): { Stocked }
	local rng = Rarity.rng(Rarity.seed(index, salt))
	local out: { Stocked } = {}
	for _, it in items do
		local appear = rng() < (it.chance or 1)
		local lo = it.min or 1
		local hi = math.max(lo, it.max or lo)
		local qty = lo + math.floor(rng() * (hi - lo + 1))
		if appear and qty > 0 then
			table.insert(out, { id = it.id, qty = qty })
		end
	end
	return out
end

-- Seconds -> "1:02:03" / "12:34" / "0:05"
function Schedule.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	if h > 0 then
		return string.format("%d:%02d:%02d", h, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

return Schedule
