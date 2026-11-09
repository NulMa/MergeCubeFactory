--!strict
-- Offline earnings settlement (docs/02 §4 "오프라인 수익 무제한 금지", docs/33). Pure, Lune-tested.
-- On join the server calls Offline.settle with the saved lastSeen and the player's rate, credits `amount`
-- through its Ledger, then saves lastSeen = now. Server time only (os.time()); never trust a client clock.
--   cap: maximum credited seconds (e.g. 4 h). efficiency: share of the online rate (e.g. 0.1).
--   minAway: shorter absences pay nothing (rejoin spam, server hops).

local Offline = {}

export type Input = {
	lastSeen: number?, -- unix seconds saved at last leave (nil = first visit)
	now: number,
	rate: number, -- earnings per second while online
	cap: number, -- seconds
	efficiency: number?, -- default 1
	minAway: number?, -- default 60
}
export type Result = {
	away: number, -- real seconds away (0 when unknown or clock went backwards)
	seconds: number, -- seconds paid (after cap)
	amount: number, -- whole units to credit
	capped: boolean, -- true when away > cap (UI can say "max reached, come back sooner")
}

function Offline.settle(i: Input): Result
	local last = i.lastSeen
	if last == nil or i.now <= last or i.rate ~= i.rate or i.rate <= 0 then
		return { away = 0, seconds = 0, amount = 0, capped = false }
	end
	local away = i.now - last
	if away < (i.minAway or 60) then
		return { away = away, seconds = 0, amount = 0, capped = false }
	end
	local seconds = math.min(away, math.max(0, i.cap))
	local amount = math.floor(i.rate * seconds * math.clamp(i.efficiency or 1, 0, 1))
	return { away = away, seconds = seconds, amount = amount, capped = away > i.cap }
end

-- Timers that kept running while away (growth, hatching): progress 0..1 of a timer started at startedAt
function Offline.progress(startedAt: number, duration: number, now: number): number
	if duration <= 0 then
		return 1
	end
	return math.clamp((now - startedAt) / duration, 0, 1)
end

-- Seconds left on a timer (0 when done)
function Offline.remaining(startedAt: number, duration: number, now: number): number
	return math.max(0, startedAt + duration - now)
end

return Offline
