--!strict
-- Onboarding objectives, client side (docs/33 §11-3). Opt-in core client module (Merge does not use it).
-- Pairs with CoreServer/Objective (saved steps). Pieces can also be used alone:
--   Objective.start({ pitch = "Grow glowing plants, sell them, become the richest gardener!" })
--   Objective.guide("plant", { target = workspace.Plot.Soil, button = seedButton })  -- beam + pulse per step
--   Objective.report("shop")              -- a step marked client = true (UI-only action)
--   local stop = Objective.beam(part)     -- guide beam from the player to an Attachment/BasePart/Model/Vector3
--   local unpulse = Objective.pulse(btn)  -- pulsing ring + pointing hand on a GuiObject
--   Objective.goal("Reach 1M to rebirth") -- the one-line goal banner (nil hides it)
-- Tracker: "STEP 2/5" + progress bar + step text "(1/3)" + reward chip. After the last step it shows the server's
-- nextGoal ("NEXT GOAL") with its beam target. Theme: panel/accent palette, ux.objective colors, title/body fonts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)
local Fx = require(script.Parent.Fx)
local Signal = require(script.Parent.Parent.Core.Signal)

local player = Players.LocalPlayer
local Objective = {}

Objective.changed = Signal.new() -- (view) every server update

export type Options = {
	pitch: Loc.Text?, -- one-line "what is this game" shown while the steps are not done
	position: UDim2?, -- tracker position (default left middle)
	anchor: Vector2?,
	goalPosition: UDim2?, -- goal banner position (default top center under the top bar)
	parent: ScreenGui?, -- default: own ScreenGui with Ui.fitScale
	sound: string?, -- Fx sound key on step done (default "Chime", silent if missing)
	stepLabel: string?, -- "STEP" (Loc text ok)
	nextLabel: string?, -- "NEXT GOAL"
}
export type Guide = { target: any?, button: (GuiObject | () -> GuiObject?)? }

local guides: { [string]: Guide } = {}
local last: { [string]: any }? = nil
local options: Options = {}
local remote: RemoteEvent? = nil
local root: ScreenGui? = nil
local tracker: Frame? = nil
local goalBar: Frame? = nil
local stopBeam: (() -> ())? = nil
local stopPulse: (() -> ())? = nil

local function tw(
	inst: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

local function colors()
	local ux = Ui.tokens().ux.objective
	return ux.beam or Ui.THEME.accent, ux.pulse or Ui.THEME.accent, ux.done or Ui.THEME.good
end

------------------------------------------------------------------------
-- World guide beam
------------------------------------------------------------------------

local function targetAttachment(target: any): (Attachment?, Instance?)
	if typeof(target) == "Instance" then
		if target:IsA("Attachment") then
			return target, nil
		end
		local part: BasePart? = nil
		if target:IsA("BasePart") then
			part = target
		elseif target:IsA("Model") then
			part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		end
		if part then
			local a = Instance.new("Attachment")
			a.Name = "CoreObjectiveTarget"
			a.Position = Vector3.new(0, part.Size.Y / 2, 0) -- top of the part (beams at ground level hide in grass)
			a.Parent = part
			return a, a
		end
		return nil, nil
	elseif typeof(target) == "Vector3" then
		local p = Instance.new("Part")
		p.Name = "CoreObjectiveTarget"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Position = target
		p.Parent = Fx.folder
		local a = Instance.new("Attachment")
		a.Parent = p
		return a, p
	end
	return nil, nil
end

-- Beam from the local character to target + a bouncing marker over the target with the distance. Returns stop().
function Objective.beam(target: any): () -> ()
	local beamColor = colors()
	local a1, temp = targetAttachment(target)
	if not a1 then
		return function() end
	end
	local alive = true
	local made: { Instance } = {}
	if temp then
		table.insert(made, temp)
	end
	-- marker
	local holder = a1.Parent :: Instance
	local bb = Instance.new("BillboardGui")
	bb.Name = "CoreObjectiveMarker"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(110, 120)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	if holder:IsA("BasePart") then
		bb.Adornee = holder
	else
		bb.Adornee = holder:FindFirstAncestorWhichIsA("BasePart") :: any
	end
	bb.Parent = player:WaitForChild("PlayerGui")
	table.insert(made, bb)
	local arrow = Ui.label({
		Text = "▼",
		Role = "title",
		TextColor3 = beamColor,
		Size = UDim2.fromScale(1, 0.7),
		Parent = bb,
	})
	local dist = Ui.label({
		Name = "Dist",
		Text = "",
		Role = "number",
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.7),
		Parent = bb,
	})
	-- beam (re-made when the character respawns)
	local beam: Beam? = nil
	local a0: Attachment? = nil
	local function attach()
		if beam then
			beam:Destroy()
		end
		if a0 then
			a0:Destroy()
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local att = Instance.new("Attachment")
		att.Name = "CoreObjectiveFrom"
		att.Position = Vector3.new(0, -0.8, 0)
		att.Parent = hrp
		local b = Instance.new("Beam")
		b.Attachment0 = att
		b.Attachment1 = a1
		b.Color = ColorSequence.new(beamColor)
		b.LightEmission = 0.6
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Width0, b.Width1 = 0.8, 0.8
		b.Segments = 20
		b.CurveSize0, b.CurveSize1 = 0, 0
		b.Texture = Fx.image("Arrow")
		b.TextureMode = Enum.TextureMode.Static
		b.TextureLength = 2
		b.TextureSpeed = 1.5
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, 0.25),
			NumberSequenceKeypoint.new(0.9, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		b.Parent = att
		beam, a0 = b, att
	end
	attach()
	local conns = {
		player.CharacterAdded:Connect(function(c)
			c:WaitForChild("HumanoidRootPart", 5)
			if alive then
				attach()
			end
		end),
	}
	local t0 = os.clock()
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			bb.StudsOffsetWorldSpace = Vector3.new(0, 4 + math.abs(math.sin(t * 3)) * 1.2, 0)
			local b = beam
			if b then
				-- breathing width so the eye catches it
				local w = 0.75 + 0.2 * math.sin(t * 4)
				b.Width0, b.Width1 = w, w
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local d = (hrp.Position - a1.WorldPosition).Magnitude
				dist.Text = string.format("%dm", math.floor(d / 3.5 + 0.5)) -- ~3.5 studs per meter (avatar scale)
				arrow.Visible = true
			end
		end)
	)
	return function()
		if not alive then
			return
		end
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		if beam then
			beam:Destroy()
		end
		if a0 then
			a0:Destroy()
		end
		for _, m in made do
			m:Destroy()
		end
	end
end

------------------------------------------------------------------------
-- Pulse highlight on a button
------------------------------------------------------------------------

-- Pulsing ring around gui + a bobbing pointing hand under it. Returns stop().
function Objective.pulse(gui: GuiObject): () -> ()
	local _, pulseColor = colors()
	local ring = Ui.make("Frame", {
		Name = "CorePulse",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = gui.ZIndex + 5,
		NoDress = true,
		Parent = gui,
	}, { Ui.corner() }) :: Frame
	local st = Instance.new("UIStroke")
	st.Color = pulseColor
	st.Thickness = 4
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = ring
	local hand = Ui.label({
		Name = "CorePulseHand",
		Text = "👆",
		Role = "body",
		TextStrokeTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = gui.ZIndex + 6,
		Parent = gui,
	})
	local alive = true
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) % 1.1 / 1.1
		ring.Size = UDim2.new(1, 0 + t * 22, 1, 0 + t * 22)
		st.Transparency = t
		st.Thickness = 5 - t * 3
		hand.Position = UDim2.new(0.5, 0, 1, 4 + math.abs(math.sin((os.clock() - t0) * 5)) * 8)
	end)
	return function()
		if alive then
			alive = false
			conn:Disconnect()
			ring:Destroy()
			hand:Destroy()
		end
	end
end

------------------------------------------------------------------------
-- Tracker + goal banner
------------------------------------------------------------------------

local function ensureRoot(): ScreenGui
	if root then
		return root
	end
	local g = options.parent
	if not g then
		local sg = Instance.new("ScreenGui")
		sg.Name = "CoreObjective"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 8
		sg.Parent = player:WaitForChild("PlayerGui")
		Ui.fitScale(sg)
		g = sg
	end
	root = g
	return g :: ScreenGui
end

-- One-line goal banner (pitch / custom). nil hides it.
function Objective.goal(text: Loc.Text?)
	local g = ensureRoot()
	if text == nil or text == "" then
		if goalBar then
			goalBar.Visible = false
		end
		return
	end
	if not goalBar then
		local bar = Ui.make("Frame", {
			Name = "Goal",
			BackgroundColor3 = Ui.THEME.panel,
			BackgroundTransparency = 0.2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = options.goalPosition or UDim2.new(0.5, 0, 0, 62),
			Size = UDim2.fromOffset(560, 34),
			NoDress = true,
			Parent = g,
		}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }) :: Frame
		local s = Instance.new("UIStroke")
		s.Color = Ui.THEME.accent
		s.Thickness = 2
		s.Transparency = 0.3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = bar
		Ui.label({
			Name = "Text",
			Role = "caption",
			Text = "",
			Size = UDim2.new(1, -28, 0.7, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = bar,
		})
		goalBar = bar
	end
	local bar = goalBar :: Frame
	Loc.apply(bar:FindFirstChild("Text") :: TextLabel, text)
	if not bar.Visible or bar:GetAttribute("Shown") == nil then
		bar:SetAttribute("Shown", true)
		bar.Visible = true
		local s = bar:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = bar
		s.Scale = 0.6
		tw(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function buildTracker(): Frame
	if tracker then
		return tracker
	end
	local g = ensureRoot()
	local card = Ui.make("Frame", {
		Name = "Tracker",
		BackgroundColor3 = Ui.THEME.panel,
		BackgroundTransparency = 0.1,
		AnchorPoint = options.anchor or Vector2.new(0, 0.5),
		Position = options.position or UDim2.new(0, 14, 0.42, 0),
		Size = UDim2.fromOffset(250, 96),
		Visible = false,
		Parent = g,
	}, { Ui.corner() }) :: Frame
	Ui.label({
		Name = "Head",
		Role = "caption",
		Text = "",
		TextColor3 = Ui.THEME.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 8),
		ZIndex = 3,
		Parent = card,
	})
	local barBg = Ui.make("Frame", {
		Name = "Bar",
		BackgroundColor3 = Ui.THEME.outline,
		BackgroundTransparency = 0.3,
		Size = UDim2.new(1, -20, 0, 6),
		Position = UDim2.fromOffset(10, 28),
		ZIndex = 3,
		NoDress = true,
		Parent = card,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Ui.make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Ui.THEME.accent,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
		NoDress = true,
		Parent = barBg,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Ui.label({
		Name = "Text",
		Role = "body",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 40),
		ZIndex = 3,
		Parent = card,
	})
	local chip = Ui.statChip(card, {
		Name = "Reward",
		icon = if Ui.hasIcon("Gift") then "Gift" else "🎁",
		value = "",
		Size = UDim2.fromOffset(110, 22),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, 8),
	})
	chip.ZIndex = 5
	for _, d in chip:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
	tracker = card
	return card
end

local guideGen = 0
local function guideFor(view: { [string]: any })
	guideGen += 1
	if stopBeam then
		stopBeam()
		stopBeam = nil
	end
	if stopPulse then
		stopPulse()
		stopPulse = nil
	end
	local g = view.id and guides[view.id]
	local target = view.target or (g and g.target)
	if type(target) == "function" then
		local fn = target
		local ok, t = pcall(fn)
		target = if ok then t else nil
		if not target then
			-- the world may not have the target yet (e.g. treasures still streaming in): retry until it appears
			guideGen += 1
			local gen = guideGen
			task.spawn(function()
				while guideGen == gen and not stopBeam do
					task.wait(1)
					local ok2, t2 = pcall(fn)
					if guideGen == gen and ok2 and t2 and not stopBeam then
						stopBeam = Objective.beam(t2)
					end
				end
			end)
		end
	end
	if target then
		stopBeam = Objective.beam(target)
	end
	local btn = g and g.button
	if type(btn) == "function" then
		local ok, b = pcall(btn)
		btn = if ok then b else nil
	end
	if typeof(btn) == "Instance" and (btn :: Instance):IsA("GuiObject") then
		stopPulse = Objective.pulse(btn :: GuiObject)
	end
end

local function render(view: { [string]: any })
	local prev = last
	last = view
	local card = buildTracker()
	local head = card:FindFirstChild("Head") :: TextLabel
	local text = card:FindFirstChild("Text") :: TextLabel
	local fill = (card:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill") :: Frame
	local chip = card:FindFirstChild("Reward") :: Frame
	local _, _, doneColor = colors()
	local finishedStep = prev ~= nil and not prev.done and (prev.id ~= view.id or view.done)
	if finishedStep then
		Fx.sound(options.sound or "Chime", nil, 0.6)
		Ui.sound("notify")
		Fx.bump(card, 0.08)
		local old = fill.BackgroundColor3
		fill.BackgroundColor3 = doneColor
		task.delay(0.4, function()
			fill.BackgroundColor3 = old
		end)
	end
	if view.done then
		if view.goal == nil then
			card.Visible = false
			Objective.goal(nil)
			guideFor(view)
			return
		end
		head.Text = options.nextLabel or "NEXT GOAL"
		Loc.apply(text, view.goal)
		local p = tonumber(view.goalProgress)
		fill.Size = UDim2.fromScale(math.clamp(p or 0, 0, 1), 1)
		chip.Visible = false
		Objective.goal(nil)
	else
		head.Text = string.format("%s %d/%d", options.stepLabel or "STEP", view.index, view.total)
		Loc.apply(text, view.text)
		if (view.need or 1) > 1 then
			text.Text ..= string.format("  (%d/%d)", view.n, view.need)
		end
		local frac = ((view.index - 1) + (view.n / math.max(1, view.need))) / math.max(1, view.total)
		tw(fill, 0.3, { Size = UDim2.fromScale(frac, 1) })
		chip.Visible = view.reward ~= nil
		if view.reward then
			Ui.setStat(chip, view.reward)
		end
		if options.pitch then
			Objective.goal(options.pitch)
		end
	end
	card.Visible = true
	if not prev or prev.id ~= view.id or prev.done ~= view.done or prev.target ~= view.target then
		guideFor(view)
	end
	Objective.changed:Fire(view)
end

-- Connect to CoreServer/Objective. Call once after Ui.theme/Fx.configure.
function Objective.start(opts: Options?)
	options = opts or {}
	ensureRoot()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		local ev = folder:WaitForChild("CoreObjective") :: RemoteEvent
		remote = folder:WaitForChild("CoreObjectiveDo") :: RemoteEvent
		ev.OnClientEvent:Connect(render);
		(remote :: RemoteEvent):FireServer("?")
	end)
end

-- Show a view without the server (demos, single-player tests): same shape as ObjectiveRules.view
function Objective.show(view: { [string]: any })
	render(view)
end

-- Per-step guide: beam target (Instance/Vector3/function) and the button to pulse (GuiObject/function)
function Objective.guide(stepId: string, g: Guide)
	guides[stepId] = g
	if last and last.id == stepId then
		guideFor(last)
	end
end

-- Report a client step (the server accepts only steps marked client = true)
function Objective.report(stepId: string)
	if remote and last and last.id == stepId then
		remote:FireServer(stepId)
	end
end

function Objective.view(): { [string]: any }?
	return last
end

return Objective
