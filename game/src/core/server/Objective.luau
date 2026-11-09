--!strict
-- Onboarding objectives, server side (docs/33 §11-3). Opt-in core server module (Merge does not use it).
-- The game owns the steps and decides when they happen; this module saves progress, pays rewards through the
-- game's callback and pushes the tracker state to the client (CoreClient/Objective).
--
--   Objective.init({
--     steps = STEPS,                                   -- ObjectiveRules.Step list (3-6 steps)
--     getData = function(player) return Data.get(player) end,  -- saved in data[key] (default "objective")
--     onReward = function(player, step) Ledger.credit(player, "cash", 50, "Gameplay", "tutorial_" .. step.id) end,
--     target = function(player, step) return plot.SeedShop end,  -- world target for the guide beam (optional)
--     nextGoal = function(player) return { text = "Next: rebirth at 1M", target = rebirthPad } end, -- after the steps
--   })
--   Objective.report(player, "harvest", 1)  -- the game's completion checks call this
--   Objective.push(player)                    -- resend (e.g. nextGoal changed)
-- Steps with client = true may also be reported by the client (UI-only steps such as "open the shop").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Core.Net)
local Rules = require(ReplicatedStorage.Core.ObjectiveRules)

local Objective = {}

export type Goal = { text: any, target: any?, progress: number? } -- target: Instance (BasePart/Attachment/Model) or Vector3
export type Options = {
	steps: { Rules.Step },
	getData: (Player) -> { [string]: any }?,
	key: string?,
	onReward: ((Player, Rules.Step) -> ())?,
	onStep: ((Player, Rules.Step?) -> ())?, -- the new current step (nil = all done)
	target: ((Player, Rules.Step) -> any)?,
	nextGoal: ((Player) -> Goal?)?,
}

Objective.SPEC = {
	CoreObjective = { kind = "event" }, -- server -> client: view
	CoreObjectiveDo = { kind = "event", args = { "string" } }, -- client -> server: report a client step
}

local opts: Options? = nil
local server: Net.Server? = nil

local function stateOf(player: Player): Rules.State?
	local o = opts
	if not o then
		return nil
	end
	local data = o.getData(player)
	if not data then
		return nil
	end
	local key = o.key or "objective"
	data[key] = Rules.sanitize(o.steps, data[key])
	return data[key]
end

function Objective.push(player: Player)
	local o, s = opts, server
	if not o or not s then
		return
	end
	local st = stateOf(player)
	if not st then
		return
	end
	local view: { [string]: any } = Rules.view(o.steps, st) :: any
	local step = o.steps[st.i]
	if step and o.target then
		local ok, t = pcall(o.target, player, step)
		view.target = if ok then t else nil
	end
	if not step and o.nextGoal then
		local ok, g = pcall(o.nextGoal, player)
		if ok and g then
			view.goal = g.text
			view.target = g.target
			view.goalProgress = g.progress
		end
	end
	s.fire("CoreObjective", player, view)
end

function Objective.report(player: Player, id: string, amount: number?): boolean
	local o = opts
	if not o then
		return false
	end
	local st = stateOf(player)
	if not st then
		return false
	end
	local done = Rules.advance(o.steps, st, id, amount)
	if done then
		if o.onReward and done.reward ~= nil then
			task.spawn(o.onReward, player, done)
		end
		if o.onStep then
			task.spawn(o.onStep, player, o.steps[st.i])
		end
		Objective.push(player)
		return true
	elseif o.steps[st.i] and o.steps[st.i].id == id then
		Objective.push(player) -- count moved
	end
	return false
end

-- Returning players who already did a step's action: skip ahead (no rewards for the skipped steps)
function Objective.skipTo(player: Player, id: string)
	local o = opts
	local st = stateOf(player)
	if o and st and Rules.skipTo(o.steps, st, id) then
		Objective.push(player)
	end
end

function Objective.isDone(player: Player): boolean
	local o = opts
	local st = stateOf(player)
	return o ~= nil and st ~= nil and Rules.isDone(o.steps, st)
end

function Objective.current(player: Player): Rules.Step?
	local o = opts
	local st = stateOf(player)
	return if o and st then o.steps[st.i] else nil
end

function Objective.init(o: Options)
	if server then
		return
	end
	opts = o
	local s = Net.serve(Objective.SPEC :: any)
	server = s
	s.on("CoreObjectiveDo", function(player: Player, id: string)
		if id == "?" then -- client tracker is ready: send the current state
			Objective.push(player)
			return
		end
		local step = Objective.current(player)
		if step and step.client and step.id == id then
			Objective.report(player, id, 1)
		end
	end)
	-- first push once the game has loaded data: the game calls Objective.push(player) after Data.onLoaded,
	-- and we also retry a few times in case it forgets.
	Players.PlayerAdded:Connect(function(player)
		for _ = 1, 20 do
			task.wait(1)
			if not player.Parent then
				return
			end
			if o.getData(player) then
				Objective.push(player)
				return
			end
		end
	end)
end

return Objective
