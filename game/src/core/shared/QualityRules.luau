--!strict
-- Effect quality tiers and caps (docs/28 §2 "연출은 상한을 두고 넘으면 가볍게", docs/32 §3-1). Pure, Lune-tested.
-- client/Quality feeds frame times and device hints into these rules; Fx and Reveal ask Quality before spending.
-- Tiers: 1 = low, 2 = medium, 3 = high. High keeps every effect as designed (no scaling, no particle budget).

local QualityRules = {}

QualityRules.LOW, QualityRules.MEDIUM, QualityRules.HIGH = 1, 2, 3
QualityRules.NAMES = { "low", "medium", "high" }

-- Per tier (index = tier)
QualityRules.PARTICLE_SCALE = { 0.35, 0.65, 1 } -- multiply particle counts
QualityRules.PARTICLES_PER_SEC = { 250, 700, math.huge } -- emitted particles per second, all effects together
QualityRules.MAX_BEAMS = { 1, 3, 8 } -- concurrent light beams / pillars (Reveal)
QualityRules.MAX_PARTS = { 40, 120, 400 } -- concurrent temporary effect parts (beams, shards, sky pieces)
QualityRules.MAX_REVEAL = { 3, 4, 5 } -- highest reveal level played as designed (higher ones are shortened)

-- Auto tier from frame rate (hysteresis so it does not flicker)
QualityRules.DOWN_FPS = 40 -- average below this ...
QualityRules.DOWN_HOLD = 4 -- ... for this many seconds -> one tier down
QualityRules.UP_FPS = 57 -- average above this ...
QualityRules.UP_HOLD = 30 -- ... for this many seconds -> one tier up (never above the device cap)
QualityRules.SMOOTH = 0.5 -- seconds of smoothing for the average

export type Hints = {
	savedQuality: number?, -- player's graphics setting 1..10 (0 or nil = automatic)
	touch: boolean?, -- phone / tablet
	memoryMb: number?, -- client memory in use (Stats:GetTotalMemoryUsageMb)
}

-- Highest tier this device may use, from hints only (FPS can still lower it)
function QualityRules.capFromHints(h: Hints): number
	local cap = QualityRules.HIGH
	local q = h.savedQuality or 0
	if q >= 1 and q <= 3 then
		cap = QualityRules.LOW
	elseif q >= 4 and q <= 6 then
		cap = QualityRules.MEDIUM
	end
	if h.touch and h.memoryMb then
		-- phones that already use a lot of memory: keep effects lighter (memory pressure crashes mobile clients)
		if h.memoryMb >= 2600 then
			cap = math.min(cap, QualityRules.LOW)
		elseif h.memoryMb >= 1600 then
			cap = math.min(cap, QualityRules.MEDIUM)
		end
	end
	return cap
end

export type State = {
	tier: number,
	cap: number,
	fps: number, -- smoothed
	lowFor: number, -- seconds the average has been below DOWN_FPS
	highFor: number, -- seconds above UP_FPS
}

function QualityRules.newState(cap: number): State
	return { tier = cap, cap = cap, fps = 60, lowFor = 0, highFor = 0 }
end

-- Feed one frame (dt seconds). Returns true when the tier changed.
function QualityRules.step(s: State, dt: number): boolean
	if dt <= 0 then
		return false
	end
	local k = math.min(1, dt / QualityRules.SMOOTH)
	s.fps += (1 / dt - s.fps) * k
	if s.fps < QualityRules.DOWN_FPS then
		s.lowFor += dt
		s.highFor = 0
	elseif s.fps > QualityRules.UP_FPS then
		s.highFor += dt
		s.lowFor = 0
	else
		s.lowFor = 0
		s.highFor = 0
	end
	if s.lowFor >= QualityRules.DOWN_HOLD and s.tier > QualityRules.LOW then
		s.tier -= 1
		s.lowFor = 0
		return true
	end
	if s.highFor >= QualityRules.UP_HOLD and s.tier < s.cap then
		s.tier += 1
		s.highFor = 0
		return true
	end
	return false
end

-- Lower the cap (e.g. new memory hint). Tier follows it down at once.
function QualityRules.setCap(s: State, cap: number): boolean
	s.cap = math.clamp(cap, QualityRules.LOW, QualityRules.HIGH)
	if s.tier > s.cap then
		s.tier = s.cap
		return true
	end
	return false
end

-- Per-second particle budget. Returns how many of n may be emitted now (scaled by tier).
export type Budget = { since: number, used: number }
function QualityRules.newBudget(): Budget
	return { since = -math.huge, used = 0 }
end
function QualityRules.particles(b: Budget, tier: number, n: number, now: number): number
	local scale = QualityRules.PARTICLE_SCALE[tier] or 1
	local want = if scale >= 1 then n else math.floor(n * scale + 0.5)
	local perSec = QualityRules.PARTICLES_PER_SEC[tier] or math.huge
	if perSec == math.huge then
		return want
	end
	if now - b.since >= 1 then
		b.since, b.used = now, 0
	end
	local allowed = math.clamp(perSec - b.used, 0, want)
	b.used += allowed
	return allowed
end

return QualityRules
