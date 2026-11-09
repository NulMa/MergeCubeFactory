--!strict
-- Player profile card, server side (docs/33 §11-4). Opt-in core server module; client = CoreClient/Profile.
--   Profile.init({
--     stats = function(target, viewer) return {
--       { icon = "⭐", label = "Rebirths", value = data.rebirths },
--       { icon = "💰", label = "Total earned", value = data.totalCash },
--       { icon = "📖", label = "Index", value = 42, unit = "%" },
--       { icon = "⏱", label = "Playtime", value = Profile.playtime(target) },
--     } end,
--     title = function(target) return "Rebirth 3" end,            -- optional line under the name
--     showcase = function(target) return Showcase.list(target) end, -- optional (default: CoreServer/Showcase if ready)
--   })
-- Remote CoreProfile (function, userId) -> card payload. Rate-limited per viewer (MIN_GAP and PER_MINUTE).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Core.Net)
local Showcase = require(script.Parent.Showcase)

local Profile = {}

export type Stat = { icon: string?, label: any, value: any, unit: string?, prefix: string? }
export type Options = {
	stats: (target: Player, viewer: Player) -> { Stat },
	title: ((target: Player) -> any)?,
	showcase: ((target: Player) -> { any })?,
}

Profile.SPEC = { CoreProfile = { kind = "function", args = { "number" } } }
Profile.MIN_GAP = 0.5
Profile.PER_MINUTE = 30

local opts: Options? = nil
local server: Net.Server? = nil
local joined: { [Player]: number } = {}
local asks: { [Player]: { number } } = {}

-- Session playtime text ("1h 05m" / "12m") for the stats list. Pass saved seconds to add earlier sessions.
function Profile.playtime(player: Player, savedSeconds: number?): string
	local sec = (savedSeconds or 0) + (os.clock() - (joined[player] or os.clock()))
	local h = math.floor(sec / 3600)
	local m = math.floor(sec % 3600 / 60)
	return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm", m)
end

-- Pure-ish limiter: true when viewer may ask now (records the ask)
function Profile.allow(viewer: Player, now: number): boolean
	local list = asks[viewer] or {}
	asks[viewer] = list
	local lastAt = list[#list]
	if lastAt and now - lastAt < Profile.MIN_GAP then
		return false
	end
	while list[1] and now - list[1] > 60 do
		table.remove(list, 1)
	end
	if #list >= Profile.PER_MINUTE then
		return false
	end
	table.insert(list, now)
	return true
end

local function card(target: Player, viewer: Player)
	local o = opts :: Options
	local ok, stats = pcall(o.stats, target, viewer)
	local out: { [string]: any } = {
		userId = target.UserId,
		name = target.Name,
		displayName = target.DisplayName,
		stats = if ok and type(stats) == "table" then stats else {},
	}
	if o.title then
		local ok2, t = pcall(o.title, target)
		out.title = if ok2 then t else nil
	end
	local showFn = o.showcase
	if not showFn then
		if Showcase.isReady() then
			showFn = Showcase.list
		end
	end
	if showFn then
		local ok3, list = pcall(showFn, target)
		out.showcase = if ok3 then list else nil
	end
	return out
end

function Profile.init(o: Options)
	if server then
		return
	end
	opts = o
	local s = Net.serve(Profile.SPEC :: any)
	server = s
	s.on("CoreProfile", function(viewer: Player, userId: number)
		if not Profile.allow(viewer, os.clock()) then
			return nil
		end
		local target = Players:GetPlayerByUserId(userId)
		if not target then
			return nil
		end
		return card(target, viewer)
	end)
	for _, p in Players:GetPlayers() do
		joined[p] = os.clock()
	end
	Players.PlayerAdded:Connect(function(p)
		joined[p] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(p)
		joined[p] = nil
		asks[p] = nil
	end)
end

return Profile
