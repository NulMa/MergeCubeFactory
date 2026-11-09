--!strict
-- Showcase picker + item spin (docs/33 §11-4). Opt-in core client module; server side = CoreServer/Showcase.
--   ShowcaseUi.init({ title = "SHOWCASE" })   -- once after Ui.theme; own pedestal prompts open the picker
--   ShowcaseUi.open(slot?)                     -- open from a HUD button too
-- Picker: slot tabs on top, then every eligible item (rarity color, name, rarity) + "Empty". Tapping one puts
-- it on the selected slot. Other players' pedestal prompts are hidden on this client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Ui = require(script.Parent.Ui)
local Fx = require(script.Parent.Fx)

local player = Players.LocalPlayer
local ShowcaseUi = {}

export type Options = {
	parent: ScreenGui?,
	title: string?,
	emptyText: string?,
	slotText: string?,
	cellArt: ((cell: GuiButton, id: string, size: number) -> ())?,
}

local options: Options = {}
local remotes: { [string]: Instance } = {}
local panel: Frame? = nil
local selected = 1
local state: { [string]: any }? = nil

local function call(name: string, ...): any
	local r = (remotes[name] :: any) :: RemoteFunction?
	if not r then
		return nil
	end
	local ok, res = pcall(r.InvokeServer, r, ...)
	return if ok then res else nil
end

local function build(): Frame
	if panel then
		return panel
	end
	local g = options.parent
	if not g then
		local sg = Instance.new("ScreenGui")
		sg.Name = "CoreShowcase"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 20
		sg.Parent = player:WaitForChild("PlayerGui")
		Ui.fitScale(sg)
		g = sg
	end
	local p = Ui.make("Frame", {
		Name = "ShowcasePanel",
		BackgroundColor3 = Ui.THEME.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 380),
		Visible = false,
		Parent = g,
	}, { Ui.corner() }) :: Frame
	Ui.bindPanel(p)
	Ui.title({
		Text = options.title or "SHOWCASE",
		Size = UDim2.new(0.6, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Parent = p,
	})
	Ui.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Parent = p,
	}, function()
		Ui.closePanel(p)
	end)
	local tabs = Ui.make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.fromOffset(12, 56),
		Parent = p,
	}, {
		Ui.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	tabs.Name = "Tabs"
	Ui.make("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 1, -116),
		Position = UDim2.fromOffset(12, 104),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = p,
	}, {
		Ui.make("UIGridLayout", {
			CellSize = UDim2.fromOffset(136, 64),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	panel = p
	return p
end

local function render()
	local p = panel
	local st = state
	if not p or not st then
		return
	end
	local tabs = p:FindFirstChild("Tabs") :: Frame
	local list = p:FindFirstChild("List") :: ScrollingFrame
	for _, c in tabs:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for _, c in list:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i = 1, st.count do
		local inf = st.slotInfo[i]
		local b = Ui.button({
			Name = "Slot" .. i,
			Text = (options.slotText or "SLOT ") .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(80, 36),
			BackgroundColor3 = if i == selected then Ui.THEME.accent else Ui.THEME.button,
			TextColor3 = if i == selected then Ui.THEME.accentInk else Ui.THEME.ink,
			Parent = tabs,
		}, function()
			selected = i
			render()
		end)
		if inf and inf.color then
			local dot = Ui.make("Frame", {
				BackgroundColor3 = inf.color,
				Size = UDim2.fromOffset(10, 10),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 2, 0, -2),
				NoDress = true,
				Parent = b,
			}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			dot.ZIndex = b.ZIndex + 2
		end
	end
	local current = st.slots[selected]
	local function cell(order: number, id: string, name: string, rarity: string?, color: Color3?)
		local on = current == id
		local b = Ui.button({
			Name = "Item_" .. id,
			Text = "",
			LayoutOrder = order,
			BackgroundColor3 = if on then Ui.THEME.accent else Ui.THEME.card,
			Parent = list,
		}, function()
			local ok = call("CoreShowcaseSet", selected, id)
			if ok then
				Fx.purchase(nil)
				state = call("CoreShowcaseGet") or state
				render()
			end
		end)
		-- optional portrait on the right (games pass cellArt); text keeps clear of it
		local artW = if options.cellArt and id ~= "" then 52 else 0
		Ui.label({
			Text = name,
			Role = "body",
			TextColor3 = if on then Ui.THEME.accentInk else Ui.THEME.ink,
			Size = UDim2.new(1, -10 - artW, 0.55, 0),
			Position = UDim2.fromOffset(5, 4),
			Parent = b,
		})
		if rarity then
			Ui.label({
				Text = string.upper(rarity),
				Role = "caption",
				TextColor3 = color or Ui.THEME.dim,
				Size = UDim2.new(1, -10 - artW, 0.32, 0),
				Position = UDim2.new(0, 5, 0.6, 0),
				Parent = b,
			})
		end
		if artW > 0 and options.cellArt then
			options.cellArt(b, id, 48)
		end
		if color then
			local s = Instance.new("UIStroke")
			s.Color = color
			s.Thickness = 2
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = b
		end
	end
	cell(0, "", options.emptyText or "Empty", nil, nil)
	for i, e in st.eligible do
		cell(i, e.id, e.name, e.rarity, e.color)
	end
end

function ShowcaseUi.open(slot: number?)
	local p = build()
	state = call("CoreShowcaseGet")
	if not state then
		return
	end
	selected = math.clamp(slot or selected, 1, math.max(1, state.count))
	render()
	p.Visible = true
end

function ShowcaseUi.close()
	if panel then
		Ui.closePanel(panel)
	end
end

-- Spin shown items locally (theme ux.pedestal.spin deg/s), only near the camera
local base: { [Instance]: CFrame } = {}
local function startSpin()
	local spin = Ui.tokens().ux.pedestal.spin
	if not spin or spin == 0 then
		return
	end
	local rate = math.rad(spin)
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local ang = (os.clock() * rate) % (2 * math.pi)
		local bob = math.sin(os.clock() * 1.6) * 0.15
		for _, item in CollectionService:GetTagged("CoreShowcaseItem") do
			if item:IsA("PVInstance") then
				local b0 = base[item]
				if not b0 then
					b0 = (item :: any):GetPivot()
					base[item] = b0
					item.Destroying:Once(function()
						base[item] = nil
					end)
				end
				local b1 = b0 :: CFrame
				if (b1.Position - cam.CFrame.Position).Magnitude < 90 then
					(item :: any):PivotTo(
						CFrame.new(b1.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, ang, 0) * b1.Rotation
					)
				end
			end
		end
	end)
end

function ShowcaseUi.init(o: Options?)
	options = o or {}
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes")
		for _, n in { "CoreShowcase", "CoreShowcaseGet", "CoreShowcaseSet" } do
			remotes[n] = folder:WaitForChild(n)
		end
		(remotes.CoreShowcase :: RemoteEvent).OnClientEvent:Connect(function()
			if panel and panel.Visible then
				state = call("CoreShowcaseGet") or state
				render()
			end
		end)
	end)
	-- own pedestals open the picker; hide others' prompts
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name ~= "ShowcasePrompt" then
			return
		end
		local ped = prompt:FindFirstAncestorWhichIsA("Model")
		if ped and ped:GetAttribute("CoreShowcaseOwner") ~= player.UserId then
			prompt.Enabled = false
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "ShowcasePrompt" then
			return
		end
		local ped = prompt:FindFirstAncestorWhichIsA("Model")
		if ped and ped:GetAttribute("CoreShowcaseOwner") == player.UserId then
			ShowcaseUi.open(ped:GetAttribute("CoreShowcaseSlot") :: number?)
		end
	end)
	startSpin()
end

return ShowcaseUi
