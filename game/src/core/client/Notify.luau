--!strict
-- Experience notification opt-in prompt, client side (docs/33). Policy lives on the server (server/Notify).
-- Call Notify.offer() at a happy moment (rare find, record, daily reward). It shows Roblox's own opt-in prompt only if
--   1. the server allows it now (play time, cooldown days, max asks, not opted in), and
--   2. ExperienceNotificationService:CanPromptOptInAsync() returns true.
-- Never forced: no reward for opting in, nothing is blocked, one prompt at a time.

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Core.Net)

local Notify = {}

local remote: RemoteFunction? = nil
local busy = false

local function getRemote(): RemoteFunction?
	if remote then
		return remote
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("CoreNotify")
	if r and r:IsA("RemoteFunction") then
		remote = r
	end
	return remote
end

-- Optional: wait for the remote at boot (call once if the server uses Notify)
function Notify.init()
	task.spawn(function()
		local r = Net.client({ CoreNotify = { kind = "function", args = { "string", "boolean" } } })
		remote = r.CoreNotify :: RemoteFunction
	end)
end

function Notify.offer()
	if busy then
		return
	end
	local r = getRemote()
	if not r then
		return
	end
	busy = true
	task.spawn(function()
		local okCan, can = pcall(function()
			return ExperienceNotificationService:CanPromptOptInAsync()
		end)
		if not okCan or not can then
			busy = false
			return
		end
		local okAsk, allowed = pcall(function()
			return (r :: RemoteFunction):InvokeServer("ask", false)
		end)
		if not okAsk or allowed ~= true then
			busy = false
			return
		end
		local conn: RBXScriptConnection? = nil
		conn = ExperienceNotificationService.OptInPromptClosed:Connect(function()
			if conn then
				conn:Disconnect()
			end
			-- after opting in, CanPromptOptInAsync turns false: report that as opted in
			local okAfter, stillCan = pcall(function()
				return ExperienceNotificationService:CanPromptOptInAsync()
			end)
			pcall(function()
				(r :: RemoteFunction):InvokeServer("result", okAfter and stillCan == false)
			end)
			busy = false
		end)
		local okPrompt = pcall(function()
			ExperienceNotificationService:PromptOptIn()
		end)
		if not okPrompt then
			if conn then
				conn:Disconnect()
			end
			busy = false
		end
	end)
end

return Notify
