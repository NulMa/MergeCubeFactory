--!strict
-- When may we show the experience-notification opt-in prompt? Pure, Lune-tested (tests/core/Notify.spec).
-- Never forced: only after some play time, at most maxAsks times per account, with days between asks,
-- and never again once the player opted in. server/Notify stores the state in player data.

local NotifyRules = {}

export type State = { asked: number?, lastAt: number?, optedIn: boolean? }
export type Options = { minPlay: number?, cooldownDays: number?, maxAsks: number? }

NotifyRules.MIN_PLAY = 600 -- seconds played this session
NotifyRules.COOLDOWN_DAYS = 3
NotifyRules.MAX_ASKS = 3

function NotifyRules.allowed(s: State, now: number, playSeconds: number, o: Options?): boolean
	local opts: Options = o or {}
	if s.optedIn then
		return false
	end
	if playSeconds < (opts.minPlay or NotifyRules.MIN_PLAY) then
		return false
	end
	if (s.asked or 0) >= (opts.maxAsks or NotifyRules.MAX_ASKS) then
		return false
	end
	if s.lastAt and now - s.lastAt < (opts.cooldownDays or NotifyRules.COOLDOWN_DAYS) * 86400 then
		return false
	end
	return true
end

-- Record one prompt (call when the server allowed it)
function NotifyRules.record(s: State, now: number)
	s.asked = (s.asked or 0) + 1
	s.lastAt = now
end

return NotifyRules
