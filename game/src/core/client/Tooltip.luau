--!strict
-- Hover / long-press tooltips (docs/33 §11-2). Core client module, opt-in (Merge does not use it).
--   local off = Tooltip.bind(button, "Rebirth: reset cash for a x2 multiplier")
--   Tooltip.bind(statRow, function() return ("Grows in %ds"):format(seed.time) end)   -- text built when shown
--   Tooltip.bind(gui, Loc.msg("tip.aura"))                                             -- translated key
--   off()                                                                               -- unbind
-- Mouse: shows after ux.tooltip.delay seconds of hover, follows the cursor, hides on leave.
-- Touch: press and hold ux.tooltip.hold seconds (finger still) shows it above the finger; it stays until release + 1.2 s.
-- The tap itself is not consumed: a normal tap still clicks the button. One shared tooltip, clamped to the screen.
-- Theme: palette.bg (or ux.tooltip.bg) background, palette.text, body font, shape corner, palette.stroke outline.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)

local Tooltip = {}

export type Source = Loc.Text | () -> Loc.Text?

local gui: ScreenGui? = nil
local box: Frame? = nil
local label: TextLabel? = nil
local owner: GuiObject? = nil -- gui whose tip is shown
local anchor: Vector2? = nil -- touch: fixed point; mouse: nil = follow cursor
local token = 0
local follow: RBXScriptConnection? = nil

local function build()
	if gui then
		return
	end
	local tk = Ui.tokens()
	local cfg = tk.ux.tooltip
	local g = Instance.new("ScreenGui")
	g.Name = "CoreTooltip"
	g.IgnoreGuiInset = true
	g.DisplayOrder = 200
	g.ResetOnSpawn = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local touch = Ui.isTouch()
	local b = Ui.make("Frame", {
		Name = "Tip",
		BackgroundColor3 = cfg.bg or tk.palette.bg,
		BackgroundTransparency = cfg.transparency,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		NoDress = true,
		Parent = g,
	}, {
		Ui.corner(8),
		Ui.make("UIStroke", {
			Color = tk.palette.accent,
			Thickness = 1.5,
			Transparency = 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 7),
		}),
	}) :: Frame
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.TextWrapped = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextSize = cfg.textSize + (if touch then 2 else 0)
	l.TextColor3 = tk.palette.text
	Ui.font(l, "body")
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(cfg.maxWidth, math.huge)
	limit.Parent = l
	l.Parent = b
	gui, box, label = g, b, l
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

-- Pure placement: prefer below-right of the cursor (above the finger on touch), flip when it would leave the screen.
-- Exposed for tests/demos: Tooltip.place(point, size, screen, touch) -> top-left
function Tooltip.place(p: Vector2, size: Vector2, screen: Vector2, touch: boolean): Vector2
	local margin = 6
	local x, y
	if touch then
		x = p.X - size.X / 2
		y = p.Y - size.Y - 56 -- above the finger
		if y < margin then
			y = p.Y + 40
		end
	else
		x = p.X + 16
		y = p.Y + 22
		if x + size.X > screen.X - margin then
			x = p.X - size.X - 8
		end
		if y + size.Y > screen.Y - margin then
			y = p.Y - size.Y - 8
		end
	end
	x = math.clamp(x, margin, math.max(margin, screen.X - size.X - margin))
	y = math.clamp(y, margin, math.max(margin, screen.Y - size.Y - margin))
	return Vector2.new(x, y)
end

local function reposition()
	local b = box
	if not b or not b.Visible then
		return
	end
	local p = anchor or UserInputService:GetMouseLocation()
	local at = Tooltip.place(p, b.AbsoluteSize, viewport(), anchor ~= nil)
	b.Position = UDim2.fromOffset(at.X, at.Y)
end

local function resolve(src: Source): Loc.Text?
	if type(src) == "function" then
		local ok, v = pcall(src)
		return if ok then v else nil
	end
	return src :: Loc.Text
end

-- Show src now for gui (at = fixed screen point for touch, nil = follow the mouse)
function Tooltip.show(src: Source, from: GuiObject?, at: Vector2?)
	build()
	local text = resolve(src)
	local b, l = box :: Frame, label :: TextLabel
	if text == nil or text == "" then
		Tooltip.hide()
		return
	end
	Loc.apply(l, text)
	owner = from
	anchor = at
	b.Visible = true
	reposition()
	task.defer(reposition) -- AutomaticSize settles next frame
	if not follow then
		follow = RunService.RenderStepped:Connect(reposition)
	end
end

function Tooltip.hide(from: GuiObject?)
	if from and owner ~= from then
		return
	end
	token += 1
	owner = nil
	anchor = nil
	if box then
		box.Visible = false
	end
	if follow then
		follow:Disconnect()
		follow = nil
	end
end

function Tooltip.isShown(): boolean
	return box ~= nil and box.Visible
end

local bound: { [GuiObject]: { RBXScriptConnection } } = {}

-- Bind a tooltip to any GuiObject. Returns an unbind function. Binding again replaces the old text.
function Tooltip.bind(target: GuiObject, src: Source): () -> ()
	Tooltip.unbind(target)
	local cfg = Ui.tokens().ux.tooltip
	local conns: { RBXScriptConnection } = {}
	-- Mouse hover
	table.insert(
		conns,
		target.MouseEnter:Connect(function()
			if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
				return -- touch screens fire MouseEnter on tap: long-press handles them
			end
			token += 1
			local my = token
			task.delay(cfg.delay, function()
				if token == my and target.Visible and target:IsDescendantOf(game) then
					Tooltip.show(src, target, nil)
				end
			end)
		end)
	)
	table.insert(
		conns,
		target.MouseLeave:Connect(function()
			token += 1
			Tooltip.hide(target)
		end)
	)
	-- Touch long-press (finger must stay within 12 px)
	table.insert(
		conns,
		target.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			token += 1
			local my = token
			local start = Vector2.new(input.Position.X, input.Position.Y)
			task.delay(cfg.hold, function()
				if token ~= my or input.UserInputState == Enum.UserInputState.End then
					return
				end
				local now = Vector2.new(input.Position.X, input.Position.Y)
				if (now - start).Magnitude > 12 then
					return
				end
				-- input.Position is inset-relative; the tooltip gui ignores the inset
				local inset = game:GetService("GuiService"):GetGuiInset()
				Tooltip.show(src, target, now + inset)
			end)
		end)
	)
	table.insert(
		conns,
		target.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if owner == target then
				local my = token
				task.delay(1.2, function()
					if token == my then
						Tooltip.hide(target)
					end
				end)
			else
				token += 1 -- released before the hold time: cancel
			end
		end)
	)
	table.insert(
		conns,
		target.AncestryChanged:Connect(function()
			if not target:IsDescendantOf(game) then
				Tooltip.hide(target)
			end
		end)
	)
	table.insert(
		conns,
		target:GetPropertyChangedSignal("Visible"):Connect(function()
			if not target.Visible then
				Tooltip.hide(target)
			end
		end)
	)
	bound[target] = conns
	target.Destroying:Once(function()
		Tooltip.unbind(target)
	end)
	return function()
		Tooltip.unbind(target)
	end
end

function Tooltip.unbind(target: GuiObject)
	local conns = bound[target]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		bound[target] = nil
	end
	Tooltip.hide(target)
end

return Tooltip
