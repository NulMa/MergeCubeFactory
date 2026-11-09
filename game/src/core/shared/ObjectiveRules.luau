--!strict
-- Onboarding step rules (docs/33 §11-3). Pure module (Lune-tested: tests/core/ObjectiveRules.spec.luau).
-- The game defines 3-6 steps that teach the core loop; the server (CoreServer/Objective) saves the state and
-- calls advance() when the game reports an event. Steps are done in order; only the current step counts.
--
--   local STEPS = {
--     { id = "plant", text = "Plant a seed", count = 1, reward = { text = "+50 coins" } },
--     { id = "harvest", text = "Harvest 3 plants", count = 3 },
--   }
--   local s = ObjectiveRules.new()
--   local done = ObjectiveRules.advance(STEPS, s, "plant")   -- -> the finished step (or nil)

local ObjectiveRules = {}

export type Step = {
	id: string,
	text: any, -- English text or { key, args } (client Loc renders it)
	count: number?, -- how many reports finish the step (default 1)
	reward: any?, -- game data (server pays it in onReward); { text = "+50" } is shown on the tracker
	client: boolean?, -- true: the client may report it (UI-only steps like "open the shop")
	[string]: any,
}

-- Saved state (data.objective): i = current step index (#steps + 1 = all done), n = progress on that step
export type State = { i: number, n: number }

function ObjectiveRules.new(): State
	return { i = 1, n = 0 }
end

local function need(step: Step): number
	return math.max(1, math.floor(step.count or 1))
end
ObjectiveRules.need = need

-- Repair saved data (missing, wrong types, steps list got shorter or longer)
function ObjectiveRules.sanitize(steps: { Step }, s: any): State
	if type(s) ~= "table" then
		return ObjectiveRules.new()
	end
	local i = if type(s.i) == "number" and s.i == s.i then math.floor(s.i) else 1
	local n = if type(s.n) == "number" and s.n == s.n then math.floor(s.n) else 0
	i = math.clamp(i, 1, #steps + 1)
	local step = steps[i]
	n = if step then math.clamp(n, 0, need(step) - 1) else 0
	s.i, s.n = i, n
	return s :: State
end

function ObjectiveRules.current(steps: { Step }, s: State): (Step?, number)
	return steps[s.i], s.i
end

function ObjectiveRules.isDone(steps: { Step }, s: State): boolean
	return s.i > #steps
end

-- Report `amount` (default 1) of event `id`. Only the current step moves. Returns the step it finished, or nil.
-- Extra progress does not spill into the next step (each step teaches one action).
function ObjectiveRules.advance(steps: { Step }, s: State, id: string, amount: number?): Step?
	local step = steps[s.i]
	if not step or step.id ~= id then
		return nil
	end
	local add = math.max(0, math.floor(amount or 1))
	if add == 0 then
		return nil
	end
	s.n += add
	if s.n >= need(step) then
		s.i += 1
		s.n = 0
		return step
	end
	return nil
end

-- Jump past steps the player already knows (e.g. a returning player who already owns plants): finish up to `id`.
function ObjectiveRules.skipTo(steps: { Step }, s: State, id: string): boolean
	for i, step in steps do
		if step.id == id then
			if i > s.i then
				s.i, s.n = i, 0
				return true
			end
			return false
		end
	end
	return false
end

-- Overall progress: finished steps, total, fraction 0..1 (partial credit inside the current step)
function ObjectiveRules.progress(steps: { Step }, s: State): (number, number, number)
	local total = #steps
	if total == 0 then
		return 0, 0, 1
	end
	local doneCount = math.min(s.i - 1, total)
	local step = steps[s.i]
	local part = if step then s.n / need(step) else 0
	return doneCount, total, math.min(1, (doneCount + part) / total)
end

-- What the client tracker needs (no functions, safe to send over a remote)
export type View = {
	id: string?,
	text: any?,
	index: number,
	total: number,
	n: number,
	need: number,
	reward: any?,
	done: boolean,
}
function ObjectiveRules.view(steps: { Step }, s: State): View
	local step = steps[s.i]
	local rewardText = nil
	if step and type(step.reward) == "table" then
		rewardText = step.reward.text
	elseif step and type(step.reward) == "string" then
		rewardText = step.reward
	end
	return {
		id = step and step.id,
		text = step and step.text,
		index = math.min(s.i, #steps),
		total = #steps,
		n = s.n,
		need = if step then need(step) else 0,
		reward = rewardText,
		done = step == nil,
	}
end

return ObjectiveRules
