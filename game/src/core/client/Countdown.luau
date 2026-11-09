--!strict
-- Countdown widget for live events and restocks (docs/32 §3-4, docs/33). Core client module.
-- Uses the shared server clock (workspace:GetServerTimeNow), so every player sees the same numbers.
--   local cd = Countdown.new(parent, { position = UDim2.new(...) })
--   cd:bindSchedule(def, { comet = "COMET SHOWER", eclipse = "ECLIPSE" })  -- running: "ENDS IN", next: "STARTS IN"
--   cd:bindCycle(300, "SEED RESTOCK")                                       -- shared restock (Schedule.cycle)
--   cd:set(endsAt, "BOSS ARRIVES", "IN")                                    -- any fixed end time
-- Names are fixed English (auto-translated); numbers are raw text (not sent to translation capture, docs/28 §7).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schedule = require(ReplicatedStorage.Core.Schedule)
local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)

local Countdown = {}
Countdown.__index = Countdown

export type Options = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?, -- accent while an event is running
	icon: string?, -- Ui icon name
}

export type Widget = typeof(setmetatable(
	{} :: {
		frame: Frame,
		nameLabel: TextLabel,
		stateLabel: TextLabel,
		timeLabel: TextLabel,
		mode: string,
		endsAt: number,
		def: Schedule.Def?,
		names: { [string]: string },
		period: number,
		alive: boolean,
		color: Color3,
		onChange: ((running: boolean, id: string?) -> ())?,
		lastKey: string,
	},
	Countdown
))

local function now(): number
	return workspace:GetServerTimeNow()
end

function Countdown.new(parent: Instance, opts: Options?): Widget
	local o: Options = opts or {}
	local frame = Ui.make("Frame", {
		Size = o.size or UDim2.fromOffset(220, 64),
		Position = o.position or UDim2.fromOffset(12, 90),
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundColor3 = Ui.THEME.panel,
		BackgroundTransparency = 0.1,
		Parent = parent,
	}, { Ui.corner(12) }) :: Frame
	local left = 8
	if
		o.icon
		and Ui.icon(o.icon, {
			Size = UDim2.fromOffset(48, 48),
			Position = UDim2.fromOffset(6, 8),
			Parent = frame,
		})
	then
		left = 58
	end
	local nameLabel = Ui.label({
		Size = UDim2.new(1, -left - 8, 0.42, 0),
		Position = UDim2.fromOffset(left, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = frame,
	})
	local stateLabel = Ui.label({
		Size = UDim2.new(0.45, -left / 2, 0.4, 0),
		Position = UDim2.new(0, left, 0.52, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Ui.THEME.dim,
		Role = "caption",
		Text = "",
		Parent = frame,
	})
	local timeLabel = Ui.label({
		Size = UDim2.new(0.55, -left / 2 - 8, 0.44, 0),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Ui.THEME.accent,
		Role = "number",
		Text = "",
		Parent = frame,
	})
	local self = setmetatable({
		frame = frame,
		nameLabel = nameLabel,
		stateLabel = stateLabel,
		timeLabel = timeLabel,
		mode = "none",
		endsAt = 0,
		def = nil :: Schedule.Def?,
		names = {} :: { [string]: string },
		period = 0,
		alive = true,
		color = o.color or Ui.THEME.good,
		onChange = nil :: ((boolean, string?) -> ())?,
		lastKey = "",
	}, Countdown)
	task.spawn(function()
		while self.alive and frame.Parent do
			self:_tick()
			task.wait(0.25)
		end
	end)
	return self
end

function Countdown._tick(self: Widget)
	local t = now()
	local name, state, seconds, running, id = "", "", 0, false, nil :: string?
	if self.mode == "schedule" and self.def then
		local st = Schedule.status(self.def, t)
		if st then
			id = st.id
			running = st.running
			name = self.names[st.id] or string.upper(st.id)
			state = if st.running then "ENDS IN" else "STARTS IN"
			seconds = st.seconds
		end
	elseif self.mode == "cycle" and self.period > 0 then
		local _, endsAt = Schedule.cycle(self.period, t)
		seconds = endsAt - t
		name = self.names._cycle or ""
		state = "RESTOCK IN"
	elseif self.mode == "fixed" then
		seconds = self.endsAt - t
		name = self.names._fixed or ""
		state = self.names._state or "IN"
	end
	local key = `{name}|{state}|{running}`
	if key ~= self.lastKey then
		self.lastKey = key
		Loc.plain(self.nameLabel, name)
		Loc.plain(self.stateLabel, state)
		self.frame.BackgroundColor3 = if running then self.color:Lerp(Ui.THEME.panel, 0.55) else Ui.THEME.panel
		if self.onChange then
			self.onChange(running, id)
		end
	end
	Loc.raw(self.timeLabel, Schedule.clock(seconds))
end

-- Show the running / next event of a fixed schedule. names: event id -> display name (fixed English)
function Countdown.bindSchedule(self: Widget, def: Schedule.Def, names: { [string]: string }?)
	self.mode = "schedule"
	self.def = def
	self.names = names or {}
	self.lastKey = ""
end

-- Shared restock countdown (Schedule.cycle(period))
function Countdown.bindCycle(self: Widget, period: number, name: string)
	self.mode = "cycle"
	self.period = period
	self.names = { _cycle = name }
	self.lastKey = ""
end

function Countdown.set(self: Widget, endsAt: number, name: string, state: string?)
	self.mode = "fixed"
	self.endsAt = endsAt
	self.names = { _fixed = name, _state = state or "IN" }
	self.lastKey = ""
end

-- Called when the shown event starts/stops (e.g. turn weather on): fn(running, id)
function Countdown.changed(self: Widget, fn: (running: boolean, id: string?) -> ())
	self.onChange = fn
end

function Countdown.destroy(self: Widget)
	self.alive = false
	self.frame:Destroy()
end

return Countdown
