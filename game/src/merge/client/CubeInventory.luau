--!strict
-- 큐브 인벤토리 (2026-10-20 사용자 "작은 버튼 누르면 위젯 온, 위젯 한번 더 누르면 탭 켜기"):
--   오른쪽 가장자리 작은 CUBES 버튼 → 위젯(트레이의 높은 등급 8개와 개수, 짝이 있으면 초록)
--   → 위젯을 누르면 전체 창(모든 등급 칸, 없는 등급은 흐리게). 서버 상태 s.trayTiers = { {tier, count}, ... }
-- 눈 아이콘 (2026-10-21 사용자 "합쳐질 수 있는데 다른 큐브가 너무 많아 못 합칠 때 빠르게 찾게"):
--   색 네모(눈)를 누르면 내 트레이에서 그 등급만 테두리로 강조하고 나머지는 반투명. 다시 누르면 끔.
--   내 화면에서만 (LocalTransparencyModifier·SelectionBox), 위젯과 창을 모두 닫으면 꺼진다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Game.Config)
local Economy = require(ReplicatedStorage.Game.Economy)
local Ui = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Ui"))
local Loc = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Loc"))

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

local PAIR = Color3.fromRGB(120, 235, 140)
local WIDGET_ROWS = 8
local DIM = 0.85 -- 강조 중 다른 큐브의 투명도

local player = Players.LocalPlayer

local CubeInventory = {}

-- 색 네모 안의 눈 (흰 타원 + 검은 눈동자)
local function eye(parent: GuiObject, z: number)
	local white = make("Frame", {
		Size = UDim2.fromScale(0.78, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	make("Frame", {
		Size = UDim2.fromScale(0.42, 0.84),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(25, 25, 35),
		BorderSizePixel = 0,
		ZIndex = z + 1,
		Parent = white,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIAspectRatioConstraint", { AspectRatio = 1 }) })
end

-- 내 트레이의 큐브 폴더
local function myCubes(): Instance?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, m in plots:GetChildren() do
		if m:GetAttribute("OwnerUserId") == player.UserId then
			return m:FindFirstChild("Cubes")
		end
	end
	return nil
end

-- 흐린 큐브는 등급 숫자·이름표·빛·입자·테두리도 끈다 (사용자 "숫자나 머지 이펙트도 줄이지 않으면 잘 안 보임").
-- 끈 것에 FocusOff를 달아 원래 꺼져 있던 것(CubeLod가 끈 것 등)은 다시 켜지 않는다
local function setDim(inst: Instance, v: number)
	local off = v > 0
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		(inst :: any).LocalTransparencyModifier = v
	elseif
		inst:IsA("SurfaceGui")
		or inst:IsA("BillboardGui")
		or inst:IsA("PointLight")
		or inst:IsA("ParticleEmitter")
	then
		local obj = inst :: any
		if off and obj.Enabled then
			obj.Enabled = false
			inst:SetAttribute("FocusOff", true)
		elseif not off and inst:GetAttribute("FocusOff") then
			obj.Enabled = true
			inst:SetAttribute("FocusOff", nil)
		end
	elseif inst:IsA("SelectionBox") then
		if off and inst.Visible then
			inst.Visible = false
			inst:SetAttribute("FocusOff", true)
		elseif not off and inst:GetAttribute("FocusOff") then
			inst.Visible = true
			inst:SetAttribute("FocusOff", nil)
		end
	end
end

local function dimCube(cube: Instance, v: number)
	setDim(cube, v)
	for _, d in cube:GetDescendants() do
		setDim(d, v)
	end
end

function CubeInventory.new(gui: ScreenGui)
	------------------------------------------------------------------
	-- 토글 버튼 (오른쪽 가장자리 가운데 조금 위)
	------------------------------------------------------------------
	local widget: TextButton
	local toggle = button({
		Name = "CubesButton",
		Size = UDim2.fromOffset(64, 44),
		Position = UDim2.new(1, -12, 0.5, -70),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "CUBES",
		TextSize = 16,
		BackgroundColor3 = THEME.button,
		ZIndex = 3,
		Parent = gui,
	}, function()
		widget.Visible = not widget.Visible
	end)

	------------------------------------------------------------------
	-- 위젯: 높은 등급부터 몇 줄. 누르면 전체 창
	------------------------------------------------------------------
	local panel: Frame
	widget = make("TextButton", {
		Name = "CubesWidget",
		Size = UDim2.fromOffset(150, 40 + WIDGET_ROWS * 24),
		-- 휴대폰: 오른쪽 버튼 줄(깜짝 특가·DROP·STEAL, 폭 약 210) 왼쪽으로 띄운다 (2026-10-21 리뷰: 특가 버튼을 가렸음)
		Position = if Ui.isTouch() then UDim2.new(1, -240, 0.5, -70) else UDim2.new(1, -84, 0.5, -70),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	}, { corner(12) }) :: TextButton
	widget.Activated:Connect(function()
		panel.Visible = true
	end)
	local widgetTitle = label({
		Size = UDim2.new(1, -12, 0, 24),
		Position = UDim2.fromOffset(6, 4),
		Text = "MY CUBES",
		TextSize = 16,
		ZIndex = 4,
		Parent = widget,
	})
	------------------------------------------------------------------
	-- 강조 (눈): 고른 등급만 테두리, 나머지는 반투명
	------------------------------------------------------------------
	local focusTier: number? = nil
	local boxes: { [Instance]: SelectionBox } = {}
	local dimmed: { [Instance]: boolean } = {}
	local onFocusChanged: () -> () = function() end

	-- Glass 재질 뒤의 반투명 물체는 그려지지 않는다 → 강조 중엔 내 공장 유리 벽을 (내 화면에서만) 일반 재질로
	local glass: { [BasePart]: boolean } = {}
	local function setGlass(folder: Instance?, on: boolean)
		if on and folder and folder.Parent then
			for _, w in folder.Parent:GetChildren() do
				if w:IsA("BasePart") and w.Material == Enum.Material.Glass then
					w.Material = Enum.Material.SmoothPlastic
					glass[w] = true
				end
			end
		elseif not on then
			for w in glass do
				w.Material = Enum.Material.Glass
			end
			table.clear(glass)
		end
	end

	local function clearFocus()
		focusTier = nil
		setGlass(nil, false)
		player:SetAttribute("CubeFocus", nil) -- Fx가 다른 등급의 합치기·착지 연출을 줄인다
		for c in dimmed do
			if c.Parent then
				dimCube(c, 0)
			end
		end
		table.clear(dimmed)
		for _, b in boxes do
			b:Destroy()
		end
		table.clear(boxes)
		onFocusChanged()
	end

	local function applyFocus()
		local tier = focusTier
		local folder = myCubes()
		if not tier or not folder then
			return
		end
		setGlass(folder, true)
		local seen: { [Instance]: boolean } = {}
		for _, c in folder:GetChildren() do
			if c:IsA("BasePart") then
				local match = c:GetAttribute("Tier") == tier
				dimCube(c, if match then 0 else DIM)
				dimmed[c] = true
				if match then
					seen[c] = true
					if not boxes[c] then
						local box = Instance.new("SelectionBox")
						box.Adornee = c
						box.Color3 = PAIR
						box.LineThickness = 0.15
						box.SurfaceColor3 = PAIR
						box.SurfaceTransparency = 0.75
						box.Parent = c
						boxes[c] = box
					end
				end
			end
		end
		for c, box in boxes do
			if not seen[c] then
				box:Destroy()
				boxes[c] = nil
			end
		end
		for c in dimmed do
			if not c.Parent then
				dimmed[c] = nil
			end
		end
	end

	local function focus(tier: number)
		if focusTier == tier then
			clearFocus()
			return
		end
		clearFocus()
		focusTier = tier
		player:SetAttribute("CubeFocus", tier)
		applyFocus()
		onFocusChanged()
	end

	type Line = { swatch: TextButton, text: TextLabel, stroke: UIStroke, tier: number? }
	local lines: { Line } = {}
	for i = 1, WIDGET_ROWS do
		local y = 30 + (i - 1) * 24
		local line: Line
		local swatch = button({
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(7, y + 1),
			Text = "",
			ZIndex = 4,
			Visible = false,
			Parent = widget,
		}, function()
			if line.tier then
				focus(line.tier)
			end
		end)
		corner(5).Parent = swatch
		eye(swatch, 5)
		local stroke = make("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = 2,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = swatch,
		}) :: UIStroke
		local text = label({
			Size = UDim2.new(1, -40, 0, 24),
			Position = UDim2.fromOffset(34, y),
			Text = "",
			TextSize = 16,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
			Parent = widget,
		})
		line = { swatch = swatch, text = text, stroke = stroke, tier = nil }
		lines[i] = line
	end
	local more = label({
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.new(0, 6, 1, -16),
		Text = "EYE = FIND IN TRAY · TAP FOR ALL",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.dim,
		ZIndex = 4,
		Parent = widget,
	})

	------------------------------------------------------------------
	-- 전체 창: 모든 등급
	------------------------------------------------------------------
	panel = make("Frame", {
		Name = "CubesPanel",
		Size = UDim2.fromOffset(500, 440),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = gui,
	}, { corner(14) }) :: Frame
	local panelTitle = label({
		Size = UDim2.new(1, -70, 0, 40),
		Position = UDim2.fromOffset(12, 8),
		Text = "CUBE INVENTORY",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	button({
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Text = "X",
		BackgroundColor3 = THEME.bad,
		Parent = panel,
	}, function()
		panel.Visible = false
	end)
	label({
		Size = UDim2.new(1, -24, 0, 18),
		Position = UDim2.fromOffset(12, 48),
		Text = "Green = a pair ready to merge · tap a tier to find it in your tray",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local grid = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -80),
		Position = UDim2.fromOffset(8, 72),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(88, 58),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame
	type Cell = { frame: GuiObject, count: TextLabel, stroke: UIStroke }
	local cells: { [number]: Cell } = {}
	for tier = 1, Economy.MAX_TIER do
		local color = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
		-- 칸을 누르면 창을 닫고 트레이에서 그 등급을 강조
		local f = make("TextButton", {
			BackgroundColor3 = THEME.card,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = tier,
			Parent = grid,
		}, { corner(10) }) :: TextButton
		f.Activated:Connect(function()
			panel.Visible = false
			if focusTier ~= tier then
				focus(tier)
			end
		end)
		local stroke = make("UIStroke", {
			Color = PAIR,
			Thickness = 2,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = f,
		}) :: UIStroke
		local sw = make("Frame", {
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(5, 5),
			BackgroundColor3 = color,
			Parent = f,
		}, { corner(5) }) :: Frame
		eye(sw, 2)
		label({
			Size = UDim2.new(1, -30, 0, 22),
			Position = UDim2.fromOffset(31, 4),
			Text = `T{tier}`,
			AutoLocalize = false,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = f,
		})
		local count = label({
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.fromOffset(4, 30),
			Text = "-",
			AutoLocalize = false,
			TextSize = 18,
			Font = Enum.Font.GothamBold,
			Parent = f,
		})
		cells[tier] = { frame = f, count = count, stroke = stroke }
	end
	Ui.touchFit(gui, widget, 1.3)

	local self = { panel = panel, button = toggle }
	local last: { [string]: any }? = nil
	function self.render(s: { [string]: any })
		last = s
		local list: { { number } } = s.trayTiers or {}
		local total, cap = s.trayCount or 0, s.trayCap or 0
		Loc.set(widgetTitle, "inv.widget", { n = total, cap = cap })
		Loc.set(panelTitle, "inv.panel", { n = total, cap = cap })
		for i, line in lines do
			local row = list[i]
			line.swatch.Visible = row ~= nil
			line.tier = if row then row[1] else nil
			line.stroke.Transparency = if row and row[1] == focusTier then 0 else 1
			if row then
				local tier, n = row[1], row[2]
				line.swatch.BackgroundColor3 = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
				Loc.raw(line.text, `T{tier}  x{n}`)
				line.text.TextColor3 = if n >= 2 then PAIR else THEME.ink
			else
				line.text.Text = ""
			end
		end
		if #list > WIDGET_ROWS then
			Loc.set(more, "inv.more", { n = #list - WIDGET_ROWS })
		else
			Loc.plain(more, "EYE = FIND IN TRAY · TAP FOR ALL")
		end
		-- 강조한 등급이 트레이에서 사라졌으면 (합쳐짐) 끈다
		if focusTier then
			local still = false
			for _, row in list do
				still = still or row[1] == focusTier
			end
			if not still then
				clearFocus()
			end
		end
		if panel.Visible then
			local have: { [number]: number } = {}
			for _, row in list do
				have[row[1]] = row[2]
			end
			for tier, c in cells do
				local n = have[tier] or 0
				c.count.Text = if n > 0 then `x{n}` else "-"
				c.count.TextColor3 = if n >= 2 then PAIR elseif n == 1 then THEME.ink else THEME.dim
				c.frame.BackgroundTransparency = if n > 0 then 0 else 0.5
				c.stroke.Transparency = if n >= 2 then 0 else 1
			end
		end
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible and last then
			self.render(last)
		end
	end)
	onFocusChanged = function()
		if last then
			self.render(last)
		end
	end
	-- 강조 중엔 0.25초마다 다시 칠한다 (새로 떨어진 큐브·합쳐진 큐브). 위젯과 창을 다 닫으면 끔
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not focusTier then
			return
		end
		if not widget.Visible and not panel.Visible then
			clearFocus()
			return
		end
		acc += dt
		if acc >= 0.25 then
			acc = 0
			applyFocus()
		end
	end)
	return self
end

return CubeInventory
