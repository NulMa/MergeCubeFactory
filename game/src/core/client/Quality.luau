--!strict
-- Effect quality on this client (docs/33). Rules and numbers: core/shared/QualityRules (Lune-tested).
-- Default is HIGH with no auto detection, so a game that never calls Quality.start() gets every effect as designed
-- (Merge Cube Factory today). New games call Quality.start() at boot: the device cap comes from the player's
-- graphics setting and memory hints, then the tier follows the frame rate (down after 4 s under 40 fps,
-- up after 30 s over 57 fps). Quality.set("low"|"medium"|"high"|nil) is a manual override (nil = auto).
-- Fx.burst and Reveal ask Quality before spending:
--   Quality.particles(n)     -> how many particles to emit now (scaled + per-second budget; HIGH = n)
--   Quality.acquire(kind)    -> false when too many "beam"/"part" effects are alive; call Quality.release(kind) after
--   Quality.tier()           -> 1 low, 2 medium, 3 high;  Quality.maxReveal() -> highest full reveal level

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QualityRules = require(ReplicatedStorage.Core.QualityRules)
local Signal = require(ReplicatedStorage.Core.Signal)

local Quality = {}

Quality.changed = Signal.new() -- (tier: number)

local state = QualityRules.newState(QualityRules.HIGH)
local override: number? = nil
local budget = QualityRules.newBudget()
local alive: { [string]: number } = {}
local started = false

local function current(): number
	return override or state.tier
end

function Quality.tier(): number
	return current()
end

function Quality.name(): string
	return QualityRules.NAMES[current()]
end

function Quality.isHigh(): boolean
	return current() >= QualityRules.HIGH
end

function Quality.maxReveal(): number
	return QualityRules.MAX_REVEAL[current()]
end

function Quality.particles(n: number): number
	return QualityRules.particles(budget, current(), n, os.clock())
end

local LIMITS: { [string]: { number } } = {
	beam = QualityRules.MAX_BEAMS,
	part = QualityRules.MAX_PARTS,
}

-- Reserve one slot of a capped effect kind. Unknown kinds are never capped.
function Quality.acquire(kind: string): boolean
	local limits = LIMITS[kind]
	local n = alive[kind] or 0
	if limits and n >= limits[current()] then
		return false
	end
	alive[kind] = n + 1
	return true
end

function Quality.release(kind: string)
	alive[kind] = math.max(0, (alive[kind] or 0) - 1)
end

-- Manual override from a settings toggle: "low" | "medium" | "high", or nil for auto
function Quality.set(name: string?)
	local before = current()
	override = if name then table.find(QualityRules.NAMES, name) else nil
	if current() ~= before then
		Quality.changed:Fire(current())
	end
end

local function hints(): QualityRules.Hints
	local h: QualityRules.Hints = {}
	pcall(function()
		local gs = UserSettings():GetService("UserGameSettings")
		local q = gs.SavedQualityLevel
		h.savedQuality = if q == Enum.SavedQualitySetting.Automatic then 0 else q.Value
	end)
	pcall(function()
		local uis = game:GetService("UserInputService")
		h.touch = uis.TouchEnabled and not uis.KeyboardEnabled
	end)
	pcall(function()
		h.memoryMb = game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	return h
end

-- Start auto detection (once). opts.cap: highest tier the game allows on any device
function Quality.start(opts: { cap: number? }?)
	if started then
		return
	end
	started = true
	local cap = math.min(QualityRules.capFromHints(hints()), (opts and opts.cap) or QualityRules.HIGH)
	local before = current()
	state = QualityRules.newState(cap)
	if current() ~= before then
		Quality.changed:Fire(current())
	end
	RunService.RenderStepped:Connect(function(dt: number)
		local before2 = current()
		QualityRules.step(state, dt)
		if current() ~= before2 then
			Quality.changed:Fire(current())
		end
	end)
	-- memory can grow during play: re-check the cap now and then
	task.spawn(function()
		while true do
			task.wait(30)
			local b = current()
			QualityRules.setCap(state, math.min(state.cap, QualityRules.capFromHints(hints())))
			if current() ~= b then
				Quality.changed:Fire(current())
			end
		end
	end)
end

return Quality
