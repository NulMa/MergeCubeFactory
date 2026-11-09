--!strict
-- Server-wide announcement banner (docs/32 §3-1 "서버 배너", docs/33). Core server module.
-- The server decides what is worth announcing (never trust a client "I got a 1 in 1M" message):
--   Banner.init()                                  -- once at boot, creates Remotes.CoreBanner
--   Banner.announce({ text, sub?, color?, icon?, level?, who? })   -- everyone in this server
--   Banner.toPlayer(player, payload)               -- one player
-- text/sub: English text (auto-translated) or { key, args } from the game's StringTable (client Loc renders it).
-- level 1..5 picks the banner style (4-5 = big + sting). who = player display name shown in front.
-- Rate limit: at most MAX announcements per WINDOW seconds per server and one per player per PLAYER_GAP seconds,
-- so a lucky streak cannot flood the screen (docs/17 R5). Client side: client/Banner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Core.Net)
local EventRules = require(ReplicatedStorage.Core.EventRules)

local Banner = {}

export type Payload = {
	text: any, -- string | { key: string, args: {}? }
	sub: any?,
	color: Color3?,
	icon: string?,
	level: number?,
	who: string?,
}

Banner.WINDOW = 60
Banner.MAX = 4
Banner.PLAYER_GAP = 15

local server: Net.Server? = nil
local history: { number } = {}
local lastBy: { [Player]: number } = {}

function Banner.init(opts: { window: number?, max: number?, playerGap: number? }?)
	if server then
		return
	end
	if opts then
		Banner.WINDOW = opts.window or Banner.WINDOW
		Banner.MAX = opts.max or Banner.MAX
		Banner.PLAYER_GAP = opts.playerGap or Banner.PLAYER_GAP
	end
	server = Net.serve({ CoreBanner = { kind = "event" } })
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastBy[p] = nil
	end)
end

-- Returns false when rate-limited (nothing sent). from = player the news is about (per-player gap)
-- exceptFrom: the roller already has their own result card, so only the others get the strip
function Banner.announce(payload: Payload, from: Player?, exceptFrom: boolean?): boolean
	local s = server
	assert(s, "Banner.init() first")
	local now = os.clock()
	if from and lastBy[from] and now - lastBy[from] < Banner.PLAYER_GAP then
		return false
	end
	-- top-level reveals (level 5) always go out; others share the window budget
	if (payload.level or 1) < 5 and not EventRules.rateLimit(history, now, Banner.MAX, Banner.WINDOW) then
		return false
	end
	if from then
		lastBy[from] = now
		payload.who = payload.who or from.DisplayName
	end
	if exceptFrom and from then
		for _, p in game:GetService("Players"):GetPlayers() do
			if p ~= from then
				s.fire("CoreBanner", p, payload)
			end
		end
	else
		s.fireAll("CoreBanner", payload)
	end
	return true
end

function Banner.toPlayer(player: Player, payload: Payload)
	local s = server
	assert(s, "Banner.init() first")
	s.fire("CoreBanner", player, payload)
end

return Banner
