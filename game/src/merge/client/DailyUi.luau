--!strict
-- 접속 선물·일일 퀘스트 화면 (docs/23_DAILY.md). 서버 server/Daily가 뽑고 지급, 여기서는 보여 주고 눌러 받기만.
--   HUD 버튼(도감 버튼 아래): 받을 게 있으면 금색 + 배지, 없으면 다음 선물까지 남은 시간
--   패널: 작은 선물(3분마다) / 큰 선물 4칸(15·30·45·60분) / 퀘스트 3개 + 완주 보너스

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Core.Format)
local AssetIds = require(ReplicatedStorage.Game.AssetIds)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Fx = require(script.Parent.Fx)
local Loc = require(ReplicatedStorage.CoreClient.Loc)

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

local DailyUi = {}

local READY = Color3.fromRGB(255, 205, 70)
local GIFT = Color3.fromRGB(255, 140, 90)
-- 선물 열기 연출용: 보상마다 아이콘·색·이름 (사용자 "퀵 기프트 눌렀을 때 뭘 얻은 건지 안 보임", 2026-10-19)
local REWARD_LOOK: { [string]: { icon: string, color: Color3, name: string } } = {
	cash = { icon = "CashBag", color = Color3.fromRGB(120, 220, 140), name = "CASH" },
	steal = { icon = "Bat", color = Color3.fromRGB(255, 110, 110), name = "FREE STEAL" },
	golden = { icon = "Star", color = Color3.fromRGB(255, 205, 70), name = "GOLDEN CUBE INCOMING!" },
	gems_s = { icon = "GemPouch", color = Color3.fromRGB(120, 190, 255), name = "GEMS" },
	gems_l = { icon = "GemChest", color = Color3.fromRGB(160, 140, 255), name = "BIG GEMS!" },
}

export type Opts = {
	gui: ScreenGui,
	remotes: { [string]: Instance },
	toast: (text: Loc.Text) -> (),
}

-- 받을 게 있는 칸: 금색 테두리가 숨 쉬듯 (도감 보상과 같은 표시)
local function pulse(stroke: UIStroke)
	task.spawn(function()
		while stroke.Parent do
			local on = stroke:GetAttribute("Ready") == true
			local t = os.clock() * 4
			stroke.Color = if on then READY:Lerp(Color3.new(1, 1, 1), (math.sin(t) + 1) / 2) else THEME.outline
			stroke.Thickness = if on then 3 + (math.sin(t) + 1) else 2
			task.wait(0.05)
		end
	end)
end

function DailyUi.new(opts: Opts)
	local gui = opts.gui
	local claimGift = opts.remotes.ClaimGift :: RemoteFunction
	local claimQuest = opts.remotes.ClaimQuest :: RemoteFunction
	local panel: Frame

	-- HUD 버튼 -----------------------------------------------------------------
	local hud = button({
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.fromOffset(12, 164), -- 도감 버튼(12,118) 아래
		BackgroundColor3 = THEME.button,
		Text = "DAILY GIFTS",
		ZIndex = 3,
		Parent = gui,
	}, function()
		panel.Visible = not panel.Visible
	end)
	Ui.addIcon(hud, "GemChest", 1.35)
	local hudStroke = make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = 2,
		Color = THEME.outline,
		Parent = hud,
	}) :: UIStroke
	pulse(hudStroke)
	local badge = label({
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, 8, 0, -10),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = READY,
		TextColor3 = THEME.accentInk,
		Text = "",
		Visible = false,
		ZIndex = 5,
		Parent = hud,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = badge })

	-- 패널 -----------------------------------------------------------------------
	panel = make("Frame", {
		Name = "DailyPanel",
		Size = UDim2.fromOffset(440, 470),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = gui,
	}, { corner(14) }) :: Frame
	make("UIStroke", { Color = THEME.outline, Thickness = 3, Parent = panel })
	local title = label({
		Size = UDim2.new(1, -70, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		Text = "DAILY GIFTS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local resetLabel = label({
		Size = UDim2.new(1, -70, 0, 16),
		Position = UDim2.fromOffset(14, 38),
		Text = "",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
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

	local function card(y: number, h: number): (Frame, UIStroke)
		local f = make("Frame", {
			Size = UDim2.new(1, -20, 0, h),
			Position = UDim2.fromOffset(10, y),
			BackgroundColor3 = THEME.card,
			Parent = panel,
		}, { corner(10) }) :: Frame
		local s = make("UIStroke", { Color = THEME.outline, Thickness = 2, Parent = f }) :: UIStroke
		pulse(s)
		return f, s
	end

	local state: { [string]: any }? = nil

	-- 선물 열기 카드: 패널 가운데에 상자가 흔들리다 터지고 → 받은 것 아이콘 + 큰 글자
	local reveal = make("TextButton", {
		Size = UDim2.fromOffset(300, 230),
		Position = UDim2.fromScale(0.5, 0.6), -- 위쪽 OPEN 버튼은 가리지 않게 (연속으로 열 수 있게)
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
		Parent = panel,
	}, { corner(16) }) :: TextButton
	local revealStroke = make("UIStroke", { Thickness = 4, Color = GIFT, Parent = reveal }) :: UIStroke
	local revealScale = make("UIScale", { Parent = reveal }) :: UIScale
	local burst = Ui.icon("Sunburst", {
		Size = UDim2.fromOffset(190, 190),
		Position = UDim2.new(0.5, 0, 0, 72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.3,
		ZIndex = 21,
		Parent = reveal,
	})
	if burst then
		Ui.spin(burst, 40)
	end
	local revealIcon = make("ImageLabel", {
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(0.5, 0, 0, 72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 22,
		Parent = reveal,
	}) :: ImageLabel
	local revealText = label({
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 132),
		Text = "",
		ZIndex = 22,
		Parent = reveal,
	})
	local revealSub = label({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 186),
		Text = "",
		Font = Enum.Font.GothamBold,
		ZIndex = 22,
		Parent = reveal,
	})
	local revealSerial = 0
	reveal.Activated:Connect(function()
		reveal.Visible = false
	end)

	local function iconImage(name: string): string
		local icons = (AssetIds :: any).Icons
		return icons and icons[name] or ""
	end

	local function showReveal(reward: string, text: Loc.Text)
		revealSerial += 1
		local serial = revealSerial
		local look = REWARD_LOOK[reward] or REWARD_LOOK.cash
		reveal.Visible = true
		revealStroke.Color = GIFT
		revealText.Text = ""
		revealSub.Text = "opening..."
		revealSub.TextColor3 = THEME.dim
		revealIcon.Image = iconImage("GemChest")
		revealIcon.Rotation = 0
		if burst then
			burst.Visible = false
		end
		revealScale.Scale = 0.6
		TweenService:Create(revealScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		-- 상자 흔들기
		task.spawn(function()
			for i = 1, 6 do
				if serial ~= revealSerial then
					return
				end
				revealIcon.Rotation = if i % 2 == 0 then -14 else 14
				task.wait(0.05)
			end
			if serial ~= revealSerial then
				return
			end
			-- 펑: 받은 것
			revealIcon.Rotation = 0
			revealIcon.Image = iconImage(look.icon)
			Loc.apply(revealText, text)
			revealText.TextColor3 = look.color
			revealSub.Text = look.name
			revealSub.TextColor3 = look.color
			revealStroke.Color = look.color
			if burst then
				burst.Visible = true
				burst.ImageColor3 = look.color
			end
			revealScale.Scale = 1.18
			TweenService:Create(revealScale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
			Fx.sound(if reward == "cash" then "Coin" else "Chime", nil, 0.6, if reward == "cash" then 1 else 1.25)
			Fx.sound("Sparkle", nil, 0.4, 1.2)
			task.wait(if reward == "cash" then 1.4 else 2.2)
			if serial == revealSerial then
				reveal.Visible = false
			end
		end)
	end

	local function onGift(which: string, from: GuiObject)
		local ok, reward, text = pcall(function()
			return claimGift:InvokeServer(which)
		end)
		if not ok or not reward then
			return
		end
		Fx.purchase(from)
		showReveal(reward :: string, text :: Loc.Text)
	end

	-- 작은 선물 (3분마다)
	local smallCard, smallStroke = card(62, 74)
	smallCard.Name = "QuickGift"
	Ui.icon("CashChest", { Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(8, 10), Parent = smallCard })
	label({
		Size = UDim2.new(1, -210, 0, 26),
		Position = UDim2.fromOffset(70, 8),
		Text = "QUICK GIFT",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = smallCard,
	})
	local smallSub = label({
		Size = UDim2.new(1, -210, 0, 32),
		Position = UDim2.fromOffset(70, 36),
		Text = "every 3 min of play: cash, rarely STEAL or GOLDEN CUBE",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = smallCard,
	})
	local smallButton: TextButton
	smallButton = button({
		Name = "QuickGiftButton",
		Size = UDim2.fromOffset(120, 50),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "",
		Parent = smallCard,
	}, function()
		if state and state.small > 0 then
			onGift("small", smallButton)
		end
	end)

	-- 큰 선물 (15·30·45·60분)
	local bigCard, bigStroke = card(144, 104)
	label({
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 4),
		Text = "PLAY GIFTS: STEAL / GOLDEN CUBE / GEMS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bigCard,
	})
	local bigBoxes: { TextButton } = {}
	for i = 1, 4 do
		local b: TextButton
		b = button({
			Size = UDim2.new(0.25, -8, 0, 70),
			Position = UDim2.new((i - 1) * 0.25, 4 + 2, 0, 28),
			Text = "",
			Parent = bigCard,
		}, function()
			if state and state.big > 0 and i == state.bigClaimed + 1 then
				onGift("big", b)
			end
		end)
		bigBoxes[i] = b
	end

	-- 퀘스트
	label({
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(14, 254),
		Text = "DAILY QUESTS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	type Row = { stroke: UIStroke, text: TextLabel, fill: Frame, count: TextLabel, claim: TextButton }
	local rows: { Row } = {}
	for i = 1, 3 do
		local f, s = card(280 + (i - 1) * 45, 40)
		local text = label({
			Size = UDim2.new(1, -150, 0, 20),
			Position = UDim2.fromOffset(10, 2),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = f,
		})
		local back = make("Frame", {
			Size = UDim2.new(1, -150, 0, 12),
			Position = UDim2.fromOffset(10, 24),
			BackgroundColor3 = Color3.fromRGB(25, 23, 40),
			Parent = f,
		}, { corner(5) }) :: Frame
		local fill = make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = THEME.good,
			Parent = back,
		}, { corner(5) }) :: Frame
		local count = label({
			Size = UDim2.fromScale(1, 1),
			Text = "",
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
			Parent = back,
		})
		local claim: TextButton
		claim = button({
			Size = UDim2.fromOffset(126, 34),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = "",
			Parent = f,
		}, function()
			local q = state and state.quests[i]
			if not q or q.done or q.n < q.target then
				return
			end
			local ok, text = pcall(function()
				return claimQuest:InvokeServer(i)
			end)
			if ok and text then
				Fx.purchase(claim)
				opts.toast(Loc.msg("daily.questDone", { text = text }))
			end
		end)
		rows[i] = { stroke = s, text = text, fill = fill, count = count, claim = claim }
	end
	local bonusButton: TextButton
	bonusButton = button({
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0, 10, 1, -10),
		AnchorPoint = Vector2.new(0, 1),
		Text = "",
		Parent = panel,
	}, function()
		if not (state and state.bonusReady) then
			return
		end
		local ok, text = pcall(function()
			return claimQuest:InvokeServer(0)
		end)
		if ok and text then
			Fx.purchase(bonusButton)
			Fx.banner(text :: Loc.Text, "Trophy", READY, "DAILY QUESTS COMPLETE")
		end
	end)
	local bonusStroke = make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = 2,
		Color = THEME.outline,
		Parent = bonusButton,
	}) :: UIStroke
	pulse(bonusStroke)

	local function setReady(b: TextButton, ready: boolean, stroke: UIStroke?)
		b.BackgroundColor3 = if ready then READY else THEME.button
		b.TextColor3 = if ready then THEME.accentInk else THEME.dim
		if stroke then
			stroke:SetAttribute("Ready", ready)
		end
	end

	local function renderPanel(d: { [string]: any })
		Loc.set(resetLabel, "daily.resetIn", { time = Format.duration(math.max(0, d.resetIn)) })
		Loc.set(title, "daily.title", { time = Format.duration(d.play) })
		-- 작은 선물
		if d.small > 0 then
			Loc.set(smallButton, "daily.openSmall", { n = d.small })
		elseif d.smallNext then
			Loc.raw(smallButton, Format.duration(d.smallNext))
		else
			Loc.plain(smallButton, "DONE TODAY")
		end
		setReady(smallButton, d.small > 0, smallStroke)
		smallSub.Text = "every 3 min of play: cash, rarely STEAL or GOLDEN CUBE"
		-- 큰 선물
		local nextBox = d.bigClaimed + 1
		for i, b in bigBoxes do
			local at = d.bigAt[i] :: number
			if i <= d.bigClaimed then
				Loc.plain(b, "OPENED")
				setReady(b, false)
			elseif i == nextBox and d.big > 0 then
				Loc.set(b, "daily.bigReady", { mins = at // 60 })
				setReady(b, true)
			else
				Loc.set(b, "daily.bigWait", { mins = at // 60, time = Format.duration(math.max(0, at - d.play)) })
				setReady(b, false)
			end
		end
		bigStroke:SetAttribute("Ready", d.big > 0)
		-- 퀘스트
		for i, row in rows do
			local q = d.quests[i]
			if not q then
				continue
			end
			local finished = q.n >= q.target
			row.text.Text = `{q.text}`
			row.fill.Size = UDim2.fromScale(math.clamp(q.n / q.target, 0, 1), 1)
			Loc.raw(row.count, `{q.n} / {q.target}`)
			if q.done then
				Loc.plain(row.claim, "DONE")
				setReady(row.claim, false, row.stroke)
			elseif finished then
				Loc.set(row.claim, "daily.claimQuest", { gems = d.questGems })
				setReady(row.claim, true, row.stroke)
			else
				Loc.raw(row.claim, `+{d.questGems}◆ +${Format.short(d.questCash)}`)
				setReady(row.claim, false, row.stroke)
			end
		end
		if d.bonusDone then
			bonusButton.Text = "ALL QUESTS DONE: COME BACK TOMORROW"
		elseif d.bonusReady then
			bonusButton.Text = `CLAIM BONUS +{d.bonusGems}◆`
		else
			bonusButton.Text = `FINISH ALL 3: +{d.bonusGems}◆ BONUS`
		end
		setReady(bonusButton, d.bonusReady == true, bonusStroke)
	end

	-- 받을 수 있는 것 수 (HUD 배지·목표 바 힌트)
	local function readyCount(d: { [string]: any }): number
		local n = d.small + d.big + (if d.bonusReady then 1 else 0)
		for _, q in d.quests do
			if not q.done and q.n >= q.target then
				n += 1
			end
		end
		return n
	end

	local function render(s: { [string]: any })
		local d = s.daily
		if not d then
			return
		end
		state = d
		local n = readyCount(d)
		if n > 0 and not badge.Visible then
			Fx.bump(hud, 0.25)
		end
		badge.Visible = n > 0
		badge.Text = tostring(n)
		hudStroke:SetAttribute("Ready", n > 0)
		hud.BackgroundColor3 = if n > 0 then Color3.fromRGB(120, 80, 30) else THEME.button
		if n > 0 then
			Loc.plain(hud, if d.big > 0 then "PLAY GIFT READY!" else "GIFT READY! OPEN")
		elseif d.smallNext or d.bigNext then
			local nextIn = math.min(d.smallNext or math.huge, d.bigNext or math.huge)
			Loc.set(hud, "daily.hudNext", { time = Format.duration(nextIn) })
		else
			local done = 0
			for _, q in d.quests do
				done += if q.done then 1 else 0
			end
			Loc.set(hud, "daily.hudQuests", { n = done, total = #d.quests })
		end
		if panel.Visible then
			renderPanel(d)
		end
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible and state then
			renderPanel(state)
		end
	end)

	return { button = hud, panel = panel, render = render, readyCount = readyCount }
end

return DailyUi
