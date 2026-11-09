--!strict
-- Server-wide announcement strip at the top of the screen (docs/33). Fed by server/Banner (Remotes.CoreBanner).
--   Banner.init()          -- once at boot (waits for the remote in the background; the server must call Banner.init)
--   Banner.show(payload)   -- local banner without the server (tutorial, own events)
-- payload = { text, sub?, color?, icon?, level? 1..5, who? }. text/sub: string or Loc.msg.
-- Queue: one at a time, 3.2 s each (level 4-5: 4.5 s, bigger, sting "Fanfare"). Low quality skips the shine sweep.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Core.Net)
local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)
local Fx = require(script.Parent.Fx)
local Quality = require(script.Parent.Quality)

local player = Players.LocalPlayer

local Banner = {}

export type Payload = {
	text: Loc.Text,
	sub: Loc.Text?,
	color: Color3?,
	icon: string?,
	level: number?,
	who: string?,
}

local gui: ScreenGui? = nil
local queue: { Payload } = {}
local busy = false

local function ensureGui(): ScreenGui
	local g = gui
	if g then
		return g
	end
	local made = Instance.new("ScreenGui")
	made.Name = "CoreBanner"
	made.ResetOnSpawn = false
	made.IgnoreGuiInset = false
	made.DisplayOrder = 40
	made.Parent = player:WaitForChild("PlayerGui")
	Ui.fitScale(made)
	gui = made
	return made
end

local function showNext()
	local p = table.remove(queue, 1)
	if not p then
		busy = false
		return
	end
	busy = true
	local root = ensureGui()
	local level = math.clamp(p.level or 1, 1, 5)
	local big = level >= 4
	local color = p.color or Ui.THEME.accent
	local h = if big then 92 else 70
	local frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -h - 20),
		Size = UDim2.fromOffset(if big then 560 else 470, h),
		BackgroundColor3 = Ui.THEME.panel,
		BackgroundTransparency = 0.05,
		ZIndex = 30,
		Parent = root,
	}, { Ui.corner(14) }) :: Frame
	local edge = Instance.new("UIStroke")
	edge.Thickness = if big then 4 else 3
	edge.Color = color
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = frame
	local iconSize = h - 16
	local hasIcon = Ui.icon(p.icon or "Star", {
		Size = UDim2.fromOffset(iconSize, iconSize),
		Position = UDim2.fromOffset(8, 8),
		ImageColor3 = Fx.lighten(color, 0.3),
		ZIndex = 31,
		Parent = frame,
	}) ~= nil
	local left = if hasIcon then iconSize + 16 else 14
	local main = Ui.label({
		Size = UDim2.new(1, -left - 12, 0.58, 0),
		Position = UDim2.fromOffset(left, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Fx.lighten(color, 0.25),
		ZIndex = 31,
		Parent = frame,
	})
	local text = Loc.text(p.text)
	if p.who then
		-- player names are not sent to translation capture (docs/28 §7)
		Loc.raw(main, `{p.who}: {text}`)
	else
		Loc.apply(main, p.text)
	end
	if p.sub then
		local subLabel = Ui.label({
			Size = UDim2.new(1, -left - 12, 0.32, 0),
			Position = UDim2.new(0, left, 0.6, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.THEME.sub,
			Role = "caption",
			ZIndex = 31,
			Parent = frame,
		})
		Loc.apply(subLabel, p.sub :: Loc.Text)
	end
	if Quality.tier() >= 2 then
		Ui.shine(frame, 1.2)
	end
	Ui.sound("notify") -- theme sound (default: none)
	if big then
		Fx.sound("Fanfare", nil, 0.5, 1)
	else
		Fx.sound("Chime", nil, 0.4, 1.3)
	end
	Fx.tween(frame, 0.35, { Position = UDim2.new(0.5, 0, 0, 10) }, Enum.EasingStyle.Back)
	task.delay(if big then 4.5 else 3.2, function()
		Fx.tween(
			frame,
			0.3,
			{ Position = UDim2.new(0.5, 0, 0, -h - 20) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		task.delay(0.32, function()
			frame:Destroy()
			showNext()
		end)
	end)
end

function Banner.show(payload: Payload)
	table.insert(queue, payload)
	-- too many waiting: keep the newest few (old news is stale)
	while #queue > 4 do
		table.remove(queue, 1)
	end
	if not busy then
		showNext()
	end
end

local started = false
function Banner.init()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local r = Net.client({ CoreBanner = { kind = "event" } })
		local remote = r.CoreBanner :: RemoteEvent
		remote.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.text ~= nil then
				Banner.show(payload)
			end
		end)
	end)
end

return Banner
