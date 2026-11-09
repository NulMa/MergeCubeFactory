--!strict
-- Experience notification opt-in flow, server side (docs/32 §3-4, docs/33). Core server module.
-- ExperienceNotificationService:CanPromptOptInAsync / PromptOptIn are client APIs (Creator Hub
-- ExperienceNotificationService page), so the prompt itself is shown by client/Notify. This module owns the policy
-- (core/shared/NotifyRules) and the saved state, so the client can never prompt more often than allowed.
--   Notify.init({ getData = function(player) return Data.get(player) end, playSeconds = function(player) ... end })
-- Saved in data.notify = { asked, lastAt, optedIn } (created on first use; ProfileStore saves it with the rest).
-- Remote Remotes.CoreNotify (function, args "string","boolean"):
--   ("ask", false)      -> true if the client may prompt now (the ask is recorded)
--   ("result", optedIn) -> stores the outcome after the prompt closed
-- Sending notifications is done outside the game (Open Cloud user notifications); not part of this module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Core.Net)
local NotifyRules = require(ReplicatedStorage.Core.NotifyRules)

local Notify = {}

export type Options = {
	getData: (player: Player) -> { [string]: any }?,
	playSeconds: (player: Player) -> number,
	minPlay: number?,
	cooldownDays: number?,
	maxAsks: number?,
}

local started = false

local function stateOf(data: { [string]: any }): NotifyRules.State
	local s = data.notify
	if type(s) ~= "table" then
		s = {}
		data.notify = s
	end
	return s
end

function Notify.init(opts: Options)
	if started then
		return
	end
	started = true
	local server = Net.serve({ CoreNotify = { kind = "function", args = { "string", "boolean" } } })
	server.on("CoreNotify", function(player: Player, action: string, value: boolean): boolean
		local data = opts.getData(player)
		if not data then
			return false
		end
		local s = stateOf(data)
		if action == "ask" then
			local now = os.time()
			if NotifyRules.allowed(s, now, opts.playSeconds(player), opts) then
				NotifyRules.record(s, now)
				return true
			end
			return false
		elseif action == "result" then
			if value then
				s.optedIn = true
			end
			return true
		end
		return false
	end)
end

return Notify
