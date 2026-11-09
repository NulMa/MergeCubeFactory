--!strict
-- 큐브 훔치기 (클라, docs/22). 실제 판정은 서버(server/Steal).
--   * STEAL 버튼: 남의 공장 땅에 있거나 큐브를 들고 있을 때 보인다 (키보드 E, 게임패드 R1)
--   * 도둑: 집 표시(내 트레이 위, 항상 보임) + 남은 시간
--   * 주인: 도둑 캐릭터 빨간 외곽선 + "THIEF!" 표시와 거리 (항상 보임)
--   * 배트에 맞으면(knock) 날아간다: 캐릭터는 내 클라이언트가 물리 주인이라 여기서 속도를 준다

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Game.Config)
local Economy = require(game:GetService("ReplicatedStorage").Game.Economy)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Ui = require(game:GetService("ReplicatedStorage").CoreClient.Ui)
local Loc = require(game:GetService("ReplicatedStorage").CoreClient.Loc)

local THEME = Ui.THEME
local RED = Color3.fromRGB(255, 90, 100)
local player = Players.LocalPlayer
local Steal = {}

local remote: RemoteFunction
local getState: () -> { [string]: any }?
local toast: (Loc.Text) -> ()
local fx: any
local button: TextButton
local title: TextLabel
local sub: TextLabel
local carryUntil = 0
local homeMark: BillboardGui? = nil
local thieves: { [any]: { Instance } } = {} -- 도둑(Player 또는 봇 Model) → 표시들

-- 훔칠 큐브 표시 (2026-10-19, 사용자 "훔칠 때 내가 훔칠 큐브가 뭔지 잘 안보임"):
-- 남의 트레이에 있으면 서버와 같은 규칙(최고 등급 제외, 가장 가까운 것)으로 고른 큐브에 외곽선 + 글자.
-- 손이 닿으면 금색 "STEAL T5!", 멀면 흰색 "T5: GET CLOSER". 판정은 여전히 서버
local targetLight: Highlight? = nil
local targetSign: BillboardGui? = nil
local targetText: TextLabel? = nil
local GOLD = Color3.fromRGB(255, 215, 70)
local CYAN = Color3.fromRGB(120, 220, 255)

-- 잠긴(보호 중) 공장: 서버가 플롯 속성 StealLockUntil(서버 시각)을 둔다
local function lockedLeft(plot: Instance): number
	local untilT = plot:GetAttribute("StealLockUntil")
	if typeof(untilT) ~= "number" then
		return 0
	end
	return math.max(0, untilT - workspace:GetServerTimeNow())
end

local function count(s: { [string]: any }): number
	return s.steal.free + s.steal.paid
end

local function plotOf(userId: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, m in plots:GetChildren() do
		if m:GetAttribute("OwnerUserId") == userId then
			return m :: Model
		end
	end
	return nil
end

-- 지금 서 있는 남의 공장 (땅 기준). 봇 공장(BotName)도 포함 — 2026-10-25 봇 공장엔 OwnerUserId가 없어 STEAL이 안 떴다
local function otherPlotHere(): Model?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plots = workspace:FindFirstChild("Plots")
	if not root or not plots then
		return nil
	end
	local half = Config.PLATFORM_SIZE.X / 2
	for _, m in plots:GetChildren() do
		local owner = m:GetAttribute("OwnerUserId")
		local floor = m:FindFirstChild("TrayFloor") :: BasePart?
		if ((owner and owner ~= player.UserId) or m:GetAttribute("BotName")) and floor then
			local off = root.Position - floor.Position
			if math.abs(off.X) <= half and math.abs(off.Z) <= half and off.Y > -6 and off.Y < 60 then
				return m :: Model
			end
		end
	end
	return nil
end

local REASONS = {
	notInside = "Jump into their tray first!",
	far = "Get closer to a cube",
	top = "Their biggest cubes are protected. Grab a smaller one!",
	tooHigh = "Too big for you! You can steal up to your merge limit. Rebirth to raise it",
	newbie = "New players are protected until their first rebirth",
	raid = "No stealing during a BOSS RAID",
	locked = "This factory is SHIELDED (robbed twice in a row). Try another one!",
	carrying = "You're already carrying a cube",
	gone = "That cube is gone. Pick another!",
	dead = "",
}

-- 고르기 창 (2026-10-19 "근처 큐브 10개 정도 띄우고 골라서 가져가기, 큐브별 이동속도 감소량도"):
-- STEAL을 누르면 서버가 준 근처 큐브 목록(등급 높은 순)을 띄우고, 고른 큐브만 훔친다.
-- 줄에 마우스를 올리면 그 큐브에 외곽선. 남의 공장을 벗어나면 닫힘
local listRemote: RemoteFunction
local picker: Frame
local pickRows: ScrollingFrame
local pickerOpen = false
local closePicker: () -> ()
local openPicker: ({ any }) -> ()

local function press()
	local s = getState()
	if not s or not s.steal then
		return
	end
	if s.carrying then
		toast("Bring it to YOUR factory!")
		return
	end
	if count(s) <= 0 then
		if s.steal.product then
			MarketplaceService:PromptProductPurchase(player, s.steal.product)
		else
			toast(Loc.msg("steal.nextIn", { time = Format.duration(s.steal.nextIn or 0) }))
		end
		return
	end
	if pickerOpen then
		closePicker()
		return
	end
	local res = listRemote:InvokeServer()
	if type(res) ~= "table" then
		return
	end
	if not res.ok then
		local text: Loc.Text? = REASONS[res.why]
		if res.why == "empty" then
			text = Loc.msg("steal.nextIn", { time = Format.duration(s.steal.nextIn or 0) })
		end
		if text and text ~= "" then
			toast(text)
		end
		return
	end
	openPicker(res.cubes)
end

-- 플롯 Cubes 폴더에서 큐브 id로 파트 찾기 (서버 파트든 데이터 큐브의 로컬 파트든 CubeId 속성이 있다)
local function cubePart(plot: Model?, id: number): BasePart?
	local folder = plot and plot:FindFirstChild("Cubes")
	if not folder then
		return nil
	end
	for _, c in folder:GetChildren() do
		if c:IsA("BasePart") and c:GetAttribute("CubeId") == id then
			return c
		end
	end
	return nil
end

local function grab(id: number)
	closePicker()
	local ok, why = remote:InvokeServer(id)
	if why == "gone" then
		-- 고르는 사이 합쳐지거나 팔린 큐브: 새 목록을 바로 다시 띄운다
		toast(REASONS.gone)
		press()
		return
	end
	if not ok and why then
		local text = REASONS[why]
		if text and text ~= "" then
			toast(text)
		end
	end
end

local function billboard(adornee: Instance, text: string, color: Color3): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 56)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2000
	bb.Adornee = adornee
	local l = Ui.label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		Parent = bb,
	})
	bb.Parent = player:WaitForChild("PlayerGui")
	return bb, l
end

local function clearThief(thief: any)
	local list = thieves[thief]
	if list then
		for _, inst in list do
			inst:Destroy()
		end
	end
	thieves[thief] = nil
end

local function clearHome()
	if homeMark then
		homeMark:Destroy()
		homeMark = nil
	end
	carryUntil = 0
end

-- 서버 Fx 이벤트 (init.client 디스패처에서 넘김). 처리했으면 true
function Steal.onFx(kind: string, a: any, b: any, c: any, ...: any): boolean
	if kind == "stolen" then
		-- ("stolen", thief, tier, variantId): 내 큐브를 훔쳐 감
		-- thief = 사람(Player) 또는 AI 플레이어 Model (server/Bots, 이름은 BotName 속성)
		local thief = a :: any
		clearThief(thief)
		local isBot = typeof(thief) == "Instance" and thief:IsA("Model")
		local name = if isBot then `{thief:GetAttribute("BotName")} (Bot)` else thief.DisplayName
		fx.banner("CUBE STOLEN!", "Bat", RED, Loc.msg("steal.stolenSub", { name = name, tier = b }))
		fx.shake(0.4)
		local char: Model? = if isBot then thief else thief.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		if char and head then
			local hl = Instance.new("Highlight")
			hl.FillColor = RED
			hl.FillTransparency = 0.5
			hl.OutlineColor = Color3.new(1, 1, 1)
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = char
			hl.Parent = player:WaitForChild("PlayerGui")
			local bb, l = billboard(head, "THIEF!", RED)
			thieves[thief] = { hl, bb }
			task.spawn(function()
				while thieves[thief] and bb.Parent do
					local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local h = head :: BasePart
					if me and h.Parent then
						Loc.set(l, "steal.thiefDist", { m = math.floor((h.Position - me.Position).Magnitude) })
					end
					task.wait(0.2)
				end
			end)
		end
		return true
	elseif kind == "stealEnd" then
		clearThief(a)
		return true
	elseif kind == "caught" then
		-- ("caught", tier, thiefName, pos, mine): 들고 가던 도둑을 배트로 잡음 (2026-10-25 사용자 "도둑 잡았을 때 효과")
		local at = c :: Vector3
		local mine = select(1, ...) == true
		fx.banner(
			"THIEF CAUGHT!",
			"Trophy",
			GOLD,
			Loc.msg(if mine then "steal.caughtMine" else "steal.caughtOther", { name = b, tier = a })
		)
		fx.screenFlash(GOLD, 0.35, 0.5)
		fx.fovPunch(6)
		fx.shake(0.45)
		fx.sound("Fanfare", nil, 0.8, 1)
		fx.sound("Bonk", at, 1, 0.85)
		if typeof(at) == "Vector3" then
			fx.burst("Sparkle", at, 40, 2, GOLD)
			fx.popup(at + Vector3.new(0, 4, 0), "CAUGHT!", GOLD, 1.8, 1.4)
		end
		return true
	elseif kind == "caughtFor" then
		-- ("caughtFor", tier, byName): 다른 사람이 내 도둑을 잡아 줌
		fx.banner("THIEF CAUGHT!", "Trophy", GOLD, Loc.msg("steal.caughtFor", { name = b, tier = a }))
		fx.sound("Chime", nil, 0.8, 1)
		return true
	elseif kind == "shield" then
		-- ("shield", seconds): 연속으로 털려 내 공장이 잠김 (Economy.STEAL_LOCK_*)
		fx.banner("SHIELD ON!", "Trophy", CYAN, Loc.msg("steal.shieldSub", { mins = math.floor(a / 60) }))
		fx.sound("Chime", nil, 0.8, 1.1)
		return true
	elseif kind == "carry" then
		-- ("carry", tier, timeout): 들었다
		clearHome()
		carryUntil = os.clock() + (tonumber(b) or 0)
		fx.banner(
			"GOT IT!",
			"Bat",
			THEME.accent,
			if c then "Higher than your best: extra heavy! Get home!" else "Carry it to YOUR factory. Don't get hit!"
		)
		local mine = plotOf(player.UserId)
		local floor = mine and mine:FindFirstChild("TrayFloor")
		if floor then
			local bb, l = billboard(floor, "HOME", THEME.good)
			bb.StudsOffset = Vector3.new(0, 26, 0)
			homeMark = bb
			task.spawn(function()
				while homeMark == bb do
					local left = math.max(0, math.ceil(carryUntil - os.clock()))
					Loc.set(l, "steal.home", { s = left })
					task.wait(0.25)
				end
			end)
		end
		return true
	elseif kind == "carryEnd" then
		clearHome()
		return true
	elseif kind == "stealDone" then
		clearHome()
		fx.banner("STOLEN!", "Trophy", THEME.accent, Loc.msg("steal.doneSub", { tier = a }))
		return true
	elseif kind == "knock" then
		-- ("knock", velocity, attacker): 배트에 맞음
		-- 넘어지지 않고 선 채로 밀려 날아간다: 공중 상태로 바꾸고 0.35초 동안 수평 속도를 유지
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum then
			local v = a :: Vector3
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
			root.AssemblyLinearVelocity = v
			fx.shake(0.4)
			fx.sound("Bonk", nil, 0.9, 0.9)
			fx.sound("BatPing", nil, 0.5, 0.9)
			local t0 = os.clock()
			local conn: RBXScriptConnection
			conn = RunService.Heartbeat:Connect(function()
				if os.clock() - t0 > 0.35 or not root.Parent then
					conn:Disconnect()
					return
				end
				root.AssemblyLinearVelocity = Vector3.new(v.X, root.AssemblyLinearVelocity.Y, v.Z)
			end)
		end
		return true
	end
	return false
end

local function hideTarget()
	if targetLight then
		targetLight.Adornee = nil
		targetLight.Enabled = false
	end
	if targetSign then
		targetSign.Enabled = false
	end
end

local function showTarget(part: BasePart, tier: number, inRange: boolean)
	if not targetLight then
		local hl = Instance.new("Highlight")
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = player:WaitForChild("PlayerGui")
		targetLight = hl
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(190, 44)
		bb.AlwaysOnTop = true
		bb.Parent = player:WaitForChild("PlayerGui")
		targetSign = bb
		targetText = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "", Parent = bb })
	end
	local hl = targetLight :: Highlight
	local bb = targetSign :: BillboardGui
	local l = targetText :: TextLabel
	hl.Adornee = part
	hl.Enabled = true
	hl.FillColor = if inRange then GOLD else Color3.new(1, 1, 1)
	-- 손이 닿으면 깜빡이며 진하게
	hl.FillTransparency = if inRange then 0.35 + 0.25 * math.sin(os.clock() * 10) else 0.75
	hl.OutlineColor = if inRange then GOLD else Color3.new(1, 1, 1)
	hl.OutlineTransparency = 0
	bb.Adornee = part
	bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2.2, 0)
	bb.Enabled = true
	Loc.set(l, if inRange then "steal.pickHere" else "steal.getCloser", { tier = tier })
	l.TextColor3 = if inRange then GOLD else Color3.new(1, 1, 1)
end

local function updateTarget(here: Model?, s: { [string]: any }?)
	if pickerOpen then
		return -- 고르기 창이 열려 있으면 마우스를 올린 줄의 큐브만 표시
	end
	if here and lockedLeft(here) > 0 then
		hideTarget()
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cubes = here and here:FindFirstChild("Cubes")
	if not root or not cubes or not s or not s.steal or s.carrying or count(s) <= 0 then
		hideTarget()
		return
	end
	local tiers: { number } = {}
	for _, c in cubes:GetChildren() do
		table.insert(tiers, (c:GetAttribute("Tier") :: number?) or 0)
	end
	local top = Economy.stealProtectedFrom(tiers) -- 이 등급 이상은 보호 (상위 2개)
	local best: BasePart?, bestD, bestTier = nil, math.huge, 0
	for _, c in cubes:GetChildren() do
		local tier = (c:GetAttribute("Tier") :: number?) or 0
		if c:IsA("BasePart") and tier > 0 and tier < top then
			local d = (c.Position - root.Position).Magnitude - c.Size.X / 2
			if d < bestD then
				best, bestD, bestTier = c, d, tier
			end
		end
	end
	if best then
		showTarget(best, bestTier, bestD <= Economy.STEAL_PICK_RANGE)
	else
		hideTarget()
	end
end

function Steal.button(): TextButton?
	return button
end

function Steal.render(s: { [string]: any })
	if not s.steal then
		return
	end
	local n = count(s)
	if s.carrying then
		Loc.plain(title, "CARRYING")
		Loc.plain(sub, "Go home!")
	else
		Loc.set(title, "steal.button", { n = n })
		if n == 0 and s.steal.product then
			Loc.set(sub, "steal.getPack", { n = s.steal.pack })
		elseif s.steal.nextIn then
			Loc.set(sub, "steal.plusOneIn", { time = Format.duration(s.steal.nextIn) })
		else
			Loc.plain(sub, "FULL")
		end
	end
	local active = n > 0 and not s.carrying
	button.BackgroundColor3 = if active then RED else THEME.button
	title.TextColor3 = if active then THEME.accentInk else THEME.dim
	sub.TextColor3 = title.TextColor3
end

function Steal.start(
	gui: ScreenGui,
	r: RemoteFunction,
	stateFn: () -> { [string]: any }?,
	toastFn: (Loc.Text) -> (),
	fxModule: any
)
	remote = r
	getState = stateFn
	toast = toastFn
	fx = fxModule
	button = Ui.button({
		Size = UDim2.fromOffset(150, 64),
		Position = UDim2.new(1, -20, 1, -186), -- DROP 바로 위 (섞기 버튼 자리, 섞기 삭제 2026-10-19)
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = RED,
		Text = "",
		Visible = false,
		Parent = gui,
	}, press)
	Ui.addIcon(button, "Bat", 1.15)
	title = Ui.label({
		Size = UDim2.fromScale(1, 0.6),
		Text = "STEAL",
		TextColor3 = THEME.accentInk,
		Parent = button,
	})
	sub = Ui.label({
		Size = UDim2.fromScale(1, 0.4),
		Position = UDim2.fromScale(0, 0.6),
		Text = "",
		TextColor3 = THEME.accentInk,
		Font = Enum.Font.GothamBold,
		Parent = button,
	})
	listRemote =
		game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("StealList") :: RemoteFunction
	picker = Ui.make("Frame", {
		Size = UDim2.fromOffset(380, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 15, -- 열린 패널(10)·황금 큐브 버튼에 가리지 않게
		Parent = gui,
	}, { Ui.corner(16) }) :: Frame
	Ui.touchFit(gui, picker)
	Ui.label({
		Size = UDim2.new(1, -70, 0, 34),
		Position = UDim2.fromOffset(14, 10),
		Text = "PICK A CUBE TO STEAL",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = picker,
	})
	Ui.label({
		Size = UDim2.new(1, -28, 0, 20),
		Position = UDim2.fromOffset(14, 44),
		Text = "Heavier cubes slow you down more",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		Parent = picker,
	})
	Ui.button({
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -10, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Text = "X",
		BackgroundColor3 = RED,
		TextColor3 = THEME.accentInk,
		Parent = picker,
	}, function()
		closePicker()
	end)
	pickRows = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -80),
		Position = UDim2.fromOffset(10, 72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = picker,
	}, { Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	closePicker = function()
		pickerOpen = false
		picker.Visible = false
		hideTarget()
	end
	openPicker = function(cubes: { any })
		for _, c in pickRows:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		-- 목록은 큐브 id로 온다 (docs/27 단계 4). 외곽선은 지금 서 있는 공장의 그 id 파트에
		local here = otherPlotHere()
		for i, e in cubes do
			local id = tonumber(e.id) or 0
			local style = Config.VARIANT_STYLE[e.variant]
			local mult = Economy.VARIANTS[Economy.variantIndex(e.variant)].mult
			local slow = math.floor((e.slow or 0) * 100 + 0.5)
			local heavy = slow > math.floor((1 - Economy.CARRY_FACTOR) * 100 + 0.5)
			local row = Ui.button({
				Size = UDim2.new(1, -8, 0, 40),
				Text = "",
				LayoutOrder = i,
				BackgroundColor3 = THEME.card,
				Parent = pickRows,
			}, function()
				grab(id)
			end)
			Ui.make("Frame", {
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.new(0, 8, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Config.TIER_COLORS[e.tier] or Color3.new(1, 1, 1),
				Parent = row,
			}, { Ui.corner(6) })
			Ui.label({
				Size = UDim2.new(0.55, -42, 1, 0),
				Position = UDim2.fromOffset(42, 0),
				Loc = if style
					then Loc.msg("steal.pickRow", { tier = e.tier, variant = style.label, mult = mult })
					else nil,
				Text = if style then "" else `T{e.tier}`,
				AutoLocalize = false,
				TextColor3 = if style then style.tag else THEME.ink,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			Ui.label({
				Size = UDim2.new(0.45, -12, 1, 0),
				Position = UDim2.fromScale(0.55, 0),
				Loc = Loc.msg("steal.slow", { pct = slow }),
				TextColor3 = if heavy then Color3.fromRGB(255, 140, 90) else THEME.dim,
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Enum.Font.GothamBold,
				Parent = row,
			})
			row.MouseEnter:Connect(function()
				local part = cubePart(here, id)
				if part then
					showTarget(part, e.tier, true)
				end
			end)
		end
		pickerOpen = true
		picker.Visible = true
		local first = cubes[1] and cubePart(here, tonumber(cubes[1].id) or 0)
		if first then
			showTarget(first, cubes[1].tier, true)
		end
	end

	ContextActionService:BindAction("StealCube", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and button.Visible then
			press()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	local hintShown = false
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.05 then
			return
		end
		acc = 0
		local s = getState()
		local here = otherPlotHere()
		updateTarget(here, s)
		if pickerOpen and (here == nil or (s ~= nil and s.carrying == true)) then
			closePicker()
		end
		local show = s ~= nil and s.steal ~= nil and (here ~= nil or s.carrying == true)
		button.Visible = show
		if here and not hintShown then
			hintShown = true
			toast("Jump into their tray and press STEAL to grab a cube!")
		end
	end)
	-- 보호 중인 공장 위 방패 표시 (누구에게나 보임)
	task.spawn(function()
		local shields: { [Instance]: { bb: BillboardGui, l: TextLabel } } = {}
		while true do
			local plots = workspace:FindFirstChild("Plots")
			for _, m in (if plots then plots:GetChildren() else {}) do
				local left = lockedLeft(m)
				local floor = m:FindFirstChild("TrayFloor")
				local sh = shields[m]
				if left > 0 and floor then
					if not sh then
						local bb, l = billboard(floor, "", CYAN)
						bb.Size = UDim2.fromOffset(220, 60)
						bb.StudsOffset = Vector3.new(0, 22, 0)
						bb.MaxDistance = 260
						sh = { bb = bb, l = l }
						shields[m] = sh
					end
					local mine = m:GetAttribute("OwnerUserId") == player.UserId
					local t = math.ceil(left)
					Loc.set(
						sh.l,
						if mine then "steal.shieldMine" else "steal.shield",
						{ time = `{t // 60}:{string.format("%02d", t % 60)}` }
					)
				elseif sh then
					sh.bb:Destroy()
					shields[m] = nil
				end
			end
			task.wait(0.5)
		end
	end)
	Players.PlayerRemoving:Connect(clearThief)
end

return Steal
