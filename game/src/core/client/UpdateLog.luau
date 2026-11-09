--!strict
-- "What's new" panel: the last 3 updates from game data (docs/32 §3-4, docs/33). Core client module.
--   local log = UpdateLog.new(gui, UPDATES, { seenVersion = state.updateSeen, onSeen = function(v) remote:FireServer(v) end })
--   log.open() / log.close();  log.button is a HUD button (place it yourself or pass opts.buttonParent)
-- UPDATES = { { version = "1.2", date = "2026-11-03", title = "Comet Shower!", lines = { "New event ...", ... } }, ... }
-- A returning player whose seenVersion is older than the newest entry gets the panel once, 3 s after join
-- (first-time players are left alone: the first minute is for the first reward, docs/32 §3-2).
-- Texts are fixed English sentences (auto-translated by Roblox).

local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)

local UpdateLog = {}

export type Entry = { version: string, date: string, title: string, lines: { string } }
export type Options = {
	seenVersion: string?, -- newest version this player has seen (nil = first visit)
	onSeen: ((version: string) -> ())?, -- save it (server data)
	buttonParent: Instance?,
	buttonPosition: UDim2?,
	count: number?, -- entries shown, default 3
}

-- Newest first by date (YYYY-MM-DD sorts as text), then version
function UpdateLog.latest(entries: { Entry }, n: number?): { Entry }
	local list = table.clone(entries)
	table.sort(list, function(a, b)
		if a.date ~= b.date then
			return a.date > b.date
		end
		return a.version > b.version
	end)
	local out = {}
	for i = 1, math.min(n or 3, #list) do
		out[i] = list[i]
	end
	return out
end

function UpdateLog.new(gui: ScreenGui, entries: { Entry }, opts: Options?)
	local o: Options = opts or {}
	local shown = UpdateLog.latest(entries, o.count or 3)
	local newest = shown[1]
	local THEME = Ui.THEME

	local panel = Ui.make("Frame", {
		Size = UDim2.fromOffset(440, 420),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { Ui.corner(16) }) :: Frame
	Ui.touchFit(gui, panel)
	Ui.bindPanel(panel) -- theme open motion + sound (default: none)
	Ui.title({
		Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(16, 10),
		Text = "WHAT'S NEW",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = panel,
	})
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 56),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 21,
		Parent = panel,
	}, { Ui.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, e in shown do
		local card = Ui.make("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = THEME.card,
			LayoutOrder = i,
			ZIndex = 22,
			Parent = list,
		}, {
			Ui.corner(10),
			Ui.make("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
			}),
			Ui.make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local head = Ui.label({
			Size = UDim2.new(1, 0, 0, 28),
			Text = e.title,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if i == 1 then THEME.accent else THEME.ink,
			LayoutOrder = 0,
			ZIndex = 23,
			Parent = card,
		})
		Loc.plain(head, e.title)
		local date = Ui.label({
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = THEME.dim,
			Role = "body",
			LayoutOrder = 1,
			ZIndex = 23,
			Parent = card,
		})
		Loc.raw(date, `v{e.version} · {e.date}`)
		for j, line in e.lines do
			local l = Ui.make("TextLabel", {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = THEME.ink,
				LayoutOrder = 1 + j,
				ZIndex = 23,
				Parent = card,
			})
			Ui.font(l, "body")
			Loc.plain(l, "• " .. line)
		end
	end

	local function close()
		Ui.closePanel(panel)
	end
	local function open()
		panel.Visible = true
		if newest and o.onSeen then
			o.onSeen(newest.version)
		end
	end
	Ui.button({
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Text = "X",
		BackgroundColor3 = THEME.bad,
		ZIndex = 22,
		Parent = panel,
	}, close)

	local button = Ui.button({
		Size = UDim2.fromOffset(120, 48),
		Position = o.buttonPosition or UDim2.new(1, -12, 0, 140),
		AnchorPoint = Vector2.new(1, 0),
		Text = "UPDATES",
		Parent = o.buttonParent or gui,
	}, function()
		if panel.Visible then
			close()
		else
			open()
		end
	end)
	Ui.addIcon(button, "Star", 1.1)

	local isNew = newest ~= nil and o.seenVersion ~= nil and o.seenVersion ~= newest.version
	if isNew then
		local badge = Ui.label({
			Size = UDim2.fromOffset(46, 22),
			Position = UDim2.new(1, 6, 0, -10),
			AnchorPoint = Vector2.new(1, 0),
			Text = "NEW",
			BackgroundTransparency = 0,
			BackgroundColor3 = THEME.bad,
			ZIndex = button.ZIndex + 3,
			Parent = button,
		})
		Ui.corner(8).Parent = badge
		Ui.wiggle(badge, 6)
		task.delay(3, function()
			if not panel.Visible then
				open()
			end
			badge:Destroy()
		end)
	elseif newest and o.seenVersion == nil and o.onSeen then
		-- first visit: remember the current version silently so the next update shows as new
		o.onSeen(newest.version)
	end

	return { panel = panel, button = button, open = open, close = close }
end

return UpdateLog
