--!strict
-- 업그레이드 v2 UI (docs/14 §3): 드로퍼 위 월드 카드 + 탭 패널(DROPPERS/FACTORY/CORES/REBIRTH) + 배지.
-- 위젯은 한 번 만들고 상태가 올 때마다 글자·색만 바꾼다(다시 만들면 길게 누르기가 끊김).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Core.Format)
local Config = require(ReplicatedStorage.Game.Config)
local Economy = require(ReplicatedStorage.Game.Economy)
local RaidRules = require(ReplicatedStorage.Game.Raid)
local Net = require(ReplicatedStorage.Core.Net)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Fx = require(script.Parent.Fx)
local Loc = require(ReplicatedStorage.CoreClient.Loc)

local THEME = Ui.THEME
local make, label, corner = Ui.make, Ui.label, Ui.corner

export type Ctx = {
	gui: ScreenGui,
	remotes: { [string]: any },
	getState: () -> { [string]: any }?,
	toast: (Loc.Text) -> (),
	cashLabel: GuiObject,
}

-- 패널 업그레이드 정의: 아이콘 글자·색·이름·효과 문구(lv → 문자열)
type Info = { icon: string, color: Color3, title: string, effect: (number) -> string, tab: string }
local INFO: { [string]: Info } = {
	polish = {
		icon = "$",
		color = Color3.fromRGB(255, 209, 61),
		title = "POLISH",
		tab = "FACTORY",
		effect = function(lv)
			return Loc.format("upg.fxPolish", { m = string.format("%.2f", Economy.polishMult(lv)) })
		end,
	},
	lucky = {
		icon = "♣",
		color = Color3.fromRGB(130, 255, 150),
		title = "LUCKY MERGE",
		tab = "FACTORY",
		effect = function(lv)
			return Loc.format("upg.fxLucky", { pct = math.round(Economy.luckyChance(lv) * 100) })
		end,
	},
	hatch = {
		icon = "⏱",
		color = Color3.fromRGB(150, 225, 255),
		title = "HATCH SPEED",
		tab = "CORES",
		effect = function(lv)
			return Loc.format("upg.fxHatch", { m = string.format("%.2f", Economy.hatchScale(lv)) })
		end,
	},
	tray = {
		icon = "▣",
		color = Color3.fromRGB(255, 160, 110),
		title = "BIGGER TRAY",
		tab = "FACTORY",
		effect = function(lv)
			return Loc.format("upg.fxTray", { n = Economy.trayCap(lv) })
		end,
	},
}
local MILESTONE_TEXT = { polish = "INCOME x2" }
local TABS = { "DROPPERS", "FACTORY", "BAT", "CORES", "REBIRTH", "BOSS" }
local TAB_ICON =
	{ DROPPERS = "Drop", FACTORY = "Upgrades", BAT = "Bat", CORES = "Cores", REBIRTH = "Star", BOSS = "Trophy" }
-- 업그레이드 행 아이콘 (AssetIds.Icons). 없으면 글자 기호(INFO.icon)로
local ROW_ICON = { polish = "Cash", lucky = "Sparkle4", hatch = "Hatch", tray = "Rain" }

local Upgrades = {}

function Upgrades.new(ctx: Ctx)
	local r = ctx.remotes
	local player = Players.LocalPlayer
	local plot: Model? = nil

	-- gems: true = 젬, "coins" = 보스 코인 (docs/25), nil = 현금
	local function affordable(cost: number?, gems: (boolean | string)?): boolean
		local s = ctx.getState()
		if cost == nil or s == nil then
			return false
		end
		if gems == "coins" then
			return (if s.raid then s.raid.coins else 0) >= cost
		end
		return if gems then (s.gems or 0) >= cost else s.cash >= cost
	end

	local function dropperPart(i: number): BasePart?
		return plot and plot:FindFirstChild("Dropper" .. i) :: BasePart?
	end

	-- 구매 공통: 성공 시 버튼 튕김 + 연속 음높이, 대상 반응은 react()
	local function purchase(b: GuiObject, invoke: () -> boolean, react: () -> ()): boolean
		local ok = invoke()
		if ok then
			Fx.purchase(b)
			Fx.bump(ctx.cashLabel, 0.12)
			react()
		end
		return ok
	end

	local function styleBuy(b: TextButton, cost: number?, maxText: Loc.Text?, gems: (boolean | string)?)
		if cost then
			local can = affordable(cost, gems)
			Loc.raw(b, (if gems == "coins" then "BC " elseif gems then "◆" else "$") .. Format.short(cost))
			b.BackgroundColor3 = if can then THEME.good else THEME.button
			b.TextColor3 = if can then THEME.accentInk else THEME.dim
			b.AutoButtonColor = true
		else
			Loc.apply(b, maxText or "MAX")
			b.BackgroundColor3 = THEME.card
			b.TextColor3 = THEME.dim
			b.AutoButtonColor = false
		end
	end

	local function bar(parent: Instance, props: { [string]: any }): (Frame, TextLabel)
		props.BackgroundColor3 = Color3.fromRGB(25, 23, 40)
		props.Parent = parent
		local back = make("Frame", props, { corner(4) }) :: Frame
		local fill = make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = THEME.accent,
			Parent = back,
		}, { corner(4) }) :: Frame
		local text = label({
			Size = UDim2.fromScale(1, 1),
			Text = "",
			TextColor3 = THEME.ink,
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
			Parent = back,
		})
		return fill, text
	end

	------------------------------------------------------------------
	-- 월드 카드: 드로퍼 머리 위 (docs/14 §3.1)
	------------------------------------------------------------------
	-- 평소에는 작은 알약(등급·간격 + 살 수 있으면 ▲), 누르면 상세 카드가 펼쳐짐.
	-- 8개가 모두 펼쳐져 있으면 트레이와 HUD를 가린다(플레이테스트 2026-10-18).
	type Card = {
		gui: BillboardGui,
		pill: TextButton,
		frame: Frame,
		head: TextLabel,
		speed: TextButton,
		tier: TextButton,
		newSlot: TextButton,
		stroke: UIStroke,
		fill: Frame,
		barText: TextLabel,
		barBack: Frame,
	}
	local cards: { [number]: Card } = {}
	local expanded: number? = nil
	local touchedAt = 0
	local PILL_SIZE = UDim2.fromOffset(92, 30)
	local CARD_SIZE = UDim2.fromOffset(196, 104)

	local function applyExpanded()
		for i, c in cards do
			local open = expanded == i
			c.frame.Visible = open
			c.pill.Visible = not open
			c.gui.Size = if open then CARD_SIZE else PILL_SIZE
			c.gui.AlwaysOnTop = open
		end
	end

	local function setExpanded(i: number?)
		expanded = i
		touchedAt = os.clock()
		applyExpanded()
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if expanded and os.clock() - touchedAt > 8 then
				setExpanded(nil)
			end
		end
	end)

	local function buyDropper(kind: string, i: number, b: GuiObject): boolean
		touchedAt = os.clock()
		local s = ctx.getState()
		local before = s and s.droppers[i]
		return purchase(b, function()
			return (r.Buy :: RemoteFunction):InvokeServer(kind, i)
		end, function()
			local part = dropperPart(i)
			if not part or not before then
				return
			end
			if kind == "speed" then
				local after = Economy.dropInterval(before.lv + 1)
				Fx.dropperUpgrade(
					part,
					Loc.msg("fx.faster", { s = string.format("%.2f", after) }),
					Config.TIER_COLORS[before.tier]
				)
			else
				local t = before.tier + 1
				Fx.dropperUpgrade(part, Loc.msg("fx.tierUp", { tier = t }), Config.TIER_COLORS[t] or THEME.accent)
			end
		end)
	end

	local function makeCard(i: number): Card
		local gui = make("BillboardGui", {
			Name = "DropperCard" .. i,
			Size = PILL_SIZE, -- 화면 픽셀 고정: 멀어도 글자가 읽힘
			StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
			LightInfluence = 0,
			MaxDistance = 110, -- 공장 전체 시점(~85)에선 보이고 광장(~140)에선 안 보이게
			Active = true,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = player:WaitForChild("PlayerGui"),
		}) :: BillboardGui
		local pill = Ui.button({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = THEME.panel,
			Text = "",
			RichText = true,
			Parent = gui,
		}, function()
			setExpanded(if expanded == i then nil else i)
		end)
		local frame = make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = THEME.panel,
			BackgroundTransparency = 0.08,
			Visible = false,
			Parent = gui,
		}, { corner(12) }) :: Frame
		-- 카드 머리를 누르면 접힘
		Ui.make("TextButton", {
			Size = UDim2.fromScale(1, 0.3),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			Parent = frame,
		}).Activated
			:Connect(function()
				setExpanded(nil)
			end)
		local stroke =
			make("UIStroke", { Thickness = 3, Color = THEME.good, Transparency = 1, Parent = frame }) :: UIStroke
		local head = label({
			Size = UDim2.fromScale(0.92, 0.26),
			Position = UDim2.fromScale(0.04, 0.03),
			Text = "",
			Parent = frame,
		})
		local function half(x: number, title: string): TextButton
			local b = Ui.button({
				Size = UDim2.fromScale(0.45, 0.44),
				Position = UDim2.fromScale(x, 0.3),
				Text = title,
				RichText = true,
				Parent = frame,
			})
			return b
		end
		local speed = half(0.035, "SPEED")
		local tier = half(0.515, "TIER")
		local fill, barText = bar(frame, {
			Name = "Bar",
			Size = UDim2.fromScale(0.92, 0.18),
			Position = UDim2.fromScale(0.04, 0.78),
		})
		local newSlot = Ui.button({
			Size = UDim2.fromScale(0.92, 0.62),
			Position = UDim2.fromScale(0.04, 0.32),
			Text = "",
			RichText = true,
			Visible = false,
			Parent = frame,
		})
		Ui.holdRepeat(speed, function()
			return buyDropper("speed", i, speed)
		end)
		Ui.holdRepeat(tier, function()
			return buyDropper("tier", i, tier)
		end)
		Ui.holdRepeat(newSlot, function()
			touchedAt = os.clock()
			return purchase(newSlot, function()
				return (r.Buy :: RemoteFunction):InvokeServer("slot", 0)
			end, function()
				local part = dropperPart(i)
				if part then
					Fx.dropperUnlock(part)
				end
			end)
		end)
		return {
			gui = gui,
			pill = pill,
			frame = frame,
			head = head,
			speed = speed,
			tier = tier,
			newSlot = newSlot,
			stroke = stroke,
			fill = fill,
			barText = barText,
			barBack = fill.Parent :: Frame,
		}
	end

	-- 카드 버튼: 위 작은 줄(무엇이 어떻게) + 아래 큰 가격. RichText 크기 태그는 TextScaled와 섞이면 크기가 뒤집혀 라벨 둘로 나눔
	local function priced(b: TextButton, title: Loc.Text, cost: number?)
		styleBuy(b, cost)
		local sub = b:FindFirstChild("Sub") :: TextLabel?
		local price = b:FindFirstChild("Price") :: TextLabel?
		if not sub then
			sub = label({ Name = "Sub", Size = UDim2.fromScale(1, 0.42), Text = "", Parent = b })
		end
		if not price then
			price = label({
				Name = "Price",
				Size = UDim2.fromScale(1, 0.58),
				Position = UDim2.fromScale(0, 0.42),
				Text = "",
				Parent = b,
			})
		end
		assert(sub and price, "card labels")
		Loc.apply(sub, title)
		sub.TextColor3 = b.TextColor3
		Loc.apply(price, b.Text)
		price.TextColor3 = b.TextColor3
		b.Text = ""
	end

	local function renderCards(s: { [string]: any })
		for i = 1, Economy.MAX_DROPPERS do
			local part = dropperPart(i)
			if not part then
				continue
			end
			local card = cards[i]
			if not card then
				card = makeCard(i)
				cards[i] = card
				applyExpanded()
			end
			card.gui.Adornee = part
			local d = s.droppers[i]
			local isNext = i == #s.droppers + 1 and s.slotCost ~= nil
			card.gui.Enabled = d ~= nil or isNext
			card.speed.Visible = d ~= nil
			card.tier.Visible = d ~= nil
			card.barBack.Visible = d ~= nil
			card.newSlot.Visible = d == nil
			if d then
				local double = if d.double > 0 then `  T+1 {math.round(d.double * 100)}%` else ""
				Loc.raw(card.head, `T{d.tier} · {string.format("%.2f", d.interval)}s{double}`)
				card.head.TextColor3 = Config.TIER_COLORS[d.tier]
				local nextIv = if d.speedCost then string.format("→%.2fs", Economy.dropInterval(d.lv + 1)) else ""
				priced(card.speed, Loc.msg("upg.cardSpeed", { next = nextIv }), d.speedCost)
				local nextT = if d.tierCost then `→T{d.tier + 1}` else Loc.format("upg.maxTier", { tier = d.tierCap })
				priced(card.tier, Loc.msg("upg.cardTier", { next = nextT }), d.tierCost)
				-- 더블 드롭 마일스톤까지 막대
				local ms = d.nextMilestone
				if ms then
					local prev = 0
					for _, m in Economy.SPEED_MILESTONES do
						if m < ms then
							prev = m
						end
					end
					card.fill.Size = UDim2.fromScale((d.lv - prev) / (ms - prev), 1)
					Loc.set(card.barText, "upg.cardBigDrop", { lv = d.lv, ms = ms })
				else
					card.fill.Size = UDim2.fromScale(1, 1)
					Loc.plain(card.barText, "SPEED MAX")
				end
				local can = affordable(d.speedCost) or affordable(d.tierCost)
				card.stroke.Transparency = if can then 0 else 1
				local hex = Config.TIER_COLORS[d.tier]:ToHex()
				Loc.raw(
					card.pill,
					`<font color="#{hex}">T{d.tier}</font>·{string.format("%.1f", d.interval)}s`
						.. (if can then ` <font color="#78DC8C">▲</font>` else "")
				)
				card.pill.BackgroundColor3 = if can then Color3.fromRGB(46, 70, 58) else THEME.panel
			else
				priced(card.newSlot, "NEW DROPPER", s.slotCost)
				Loc.plain(card.head, "LOCKED")
				card.head.TextColor3 = THEME.dim
				local can = affordable(s.slotCost)
				card.stroke.Transparency = if can then 0 else 1
				Loc.raw(
					card.pill,
					"+$" .. Format.short(s.slotCost or 0) .. (if can then ` <font color="#78DC8C">▲</font>` else "")
				)
				card.pill.BackgroundColor3 = if can then Color3.fromRGB(46, 70, 58) else THEME.panel
			end
		end
	end

	------------------------------------------------------------------
	-- 패널: 탭 + 카드 (docs/14 §3.1)
	------------------------------------------------------------------
	local panel = make("Frame", {
		Size = UDim2.fromOffset(420, 400),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = ctx.gui,
	}, { corner(14) }) :: Frame
	local tabBar = make("Frame", {
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local tabDots: { [string]: TextLabel } = {}
	local current = "DROPPERS"

	local function selectTab(name: string)
		current = name
		for n, page in pages do
			page.Visible = n == name
			tabButtons[n].BackgroundColor3 = if n == name then THEME.accent else THEME.button
			tabButtons[n].TextColor3 = if n == name then THEME.accentInk else THEME.ink
		end
	end

	-- BOSS 탭은 광장 BOSS SHOP 발판 위에서만 보인다 (2026-10-20 사용자 "탭이 안 보임, 발판 위에서만 탭 보이게")
	for order, name in TABS do
		local b = Ui.button({
			Size = if name == "BOSS" then UDim2.new(1, -5, 1, 0) else UDim2.new(1 / (#TABS - 1), -5, 1, 0),
			Text = if name == "BOSS" then "BOSS SHOP" else name,
			Visible = name ~= "BOSS",
			LayoutOrder = order,
			Parent = tabBar,
		}, function()
			selectTab(name)
		end)
		tabButtons[name] = b
		-- 탭 왼쪽 위에 작은 아이콘을 비스듬히 (탭이 좁아 글자는 그대로 둔다)
		Ui.icon(TAB_ICON[name], {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(-14, -14),
			Rotation = -12,
			ZIndex = 4,
			Parent = b,
		})
		tabDots[name] = label({
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, 2, 0, -8),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = THEME.bad,
			Text = "",
			Visible = false,
			ZIndex = 4,
			Parent = b,
		})
		make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = tabDots[name] })
		pages[name] = make("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -64),
			Position = UDim2.fromOffset(8, 56),
			BackgroundTransparency = 1,
			ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
			Parent = panel,
		}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	end
	selectTab(current)

	-- 카드 하나: 아이콘 | 이름·Lv / 지금 → 다음 / 마일스톤 막대 | 가격 버튼
	type Row = {
		frame: Frame,
		title: TextLabel,
		effect: TextLabel,
		fill: Frame,
		barText: TextLabel,
		barBack: Frame,
		buy: TextButton,
		stroke: UIStroke,
	}
	local function makeRow(
		page: string,
		order: number,
		icon: string,
		color: Color3,
		image: string?,
		step: (TextButton) -> boolean
	): Row
		local f = make("Frame", {
			Size = UDim2.new(1, -8, 0, 92),
			BackgroundColor3 = THEME.card,
			LayoutOrder = order,
			Parent = pages[page],
		}, { corner(12) }) :: Frame
		local stroke = make("UIStroke", { Thickness = 2, Color = THEME.good, Transparency = 1, Parent = f }) :: UIStroke
		local iconBox = make("Frame", {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = color,
			Parent = f,
		}, {
			corner(12),
			make(
				"UIGradient",
				{ Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170)), Rotation = 90 }
			),
			make("UIStroke", { Thickness = 3, Color = THEME.outline, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		-- 큰 아이콘을 상자 밖으로 살짝 튀어나오게, 기호(드로퍼 번호 등)는 오른쪽 아래 배지로
		local art = if image
			then Ui.icon(image, {
				Size = UDim2.fromScale(1.25, 1.25),
				Position = UDim2.fromScale(0.5, 0.45),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ImageColor3 = if image == "Sparkle4" then Color3.fromRGB(140, 255, 150) else Color3.new(1, 1, 1),
				ZIndex = 2,
				Parent = iconBox,
			})
			else nil
		if art then
			if icon ~= "" and tonumber(icon) then
				label({
					Size = UDim2.fromOffset(26, 26),
					Position = UDim2.new(1, 6, 1, 6),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundTransparency = 0,
					BackgroundColor3 = THEME.accent,
					Text = icon,
					TextColor3 = THEME.accentInk,
					TextStrokeTransparency = 1,
					ZIndex = 3,
					Parent = iconBox,
				})
				corner(13).Parent = iconBox:FindFirstChildOfClass("TextLabel")
			end
		else
			label({
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.1, 0.1),
				Text = icon,
				TextColor3 = THEME.accentInk,
				Font = Enum.Font.GothamBlack,
				Parent = iconBox,
			})
		end
		local title = label({
			Size = UDim2.new(1, -200, 0, 26),
			Position = UDim2.fromOffset(80, 8),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = f,
		})
		local effect = label({
			Size = UDim2.new(1, -200, 0, 24),
			Position = UDim2.fromOffset(80, 36),
			Text = "",
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			TextColor3 = THEME.dim,
			Parent = f,
		})
		local fill, barText = bar(f, {
			Size = UDim2.new(1, -200, 0, 16),
			Position = UDim2.fromOffset(80, 66),
		})
		local buy = Ui.button({
			Size = UDim2.fromOffset(104, 60),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Text = "",
			Parent = f,
		})
		Ui.holdRepeat(buy, function()
			return step(buy)
		end)
		return {
			frame = f,
			title = title,
			effect = effect,
			fill = fill,
			barText = barText,
			barBack = fill.Parent :: Frame,
			buy = buy,
			stroke = stroke,
		}
	end

	local function nowNext(now: string, nextText: string?): string
		if not nextText then
			return `<font color="#ECEBF6">{now}</font>`
		end
		return `<font color="#ECEBF6">{now}</font>  →  <font color="#78DC8C">{nextText}</font>`
	end

	-- "POLISH  Lv3/10" 같은 제목: 이름은 원문 번역, 숫자는 매개변수 (client/Loc)
	local function lvTitle(title: string, lv: number, max: number?): Loc.Msg
		return Loc.msg(if max then "upg.lvMax" else "upg.lv", { title = Loc.source(title), lv = lv, max = max })
	end

	local function setRow(
		row: Row,
		title: Loc.Text,
		now: string,
		nextText: string?,
		cost: number?,
		progress: number?,
		barText: Loc.Text?,
		gems: (boolean | string)?,
		maxText: Loc.Text?
	)
		Loc.apply(row.title, title)
		-- now·next는 이미 번역된 글자 (효과 함수가 Loc.format) → 다시 캡처하지 않는다
		Loc.raw(row.effect, nowNext(now, nextText))
		styleBuy(row.buy, cost, maxText, gems)
		row.stroke.Transparency = if affordable(cost, gems) then 0 else 1
		row.barBack.Visible = progress ~= nil
		if progress then
			row.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			Loc.apply(row.barText, barText or "")
		end
	end

	local function trayCenter(): Vector3?
		local s = ctx.getState()
		return s and s.plotCenter + Vector3.new(0, 1, 0)
	end

	-- 공장·코어 업그레이드 행
	local upgradeRows: { [string]: Row } = {}
	for order, id in Economy.UPGRADE_ORDER do
		local info = INFO[id]
		upgradeRows[id] = makeRow(info.tab, order + 10, info.icon, info.color, ROW_ICON[id], function(b)
			local s = ctx.getState()
			local lv = if s then s.upgrades[id].lv else 0
			return purchase(b, function()
				return (r.Upgrade :: RemoteFunction):InvokeServer(id)
			end, function()
				local c = trayCenter()
				if c and (id == "polish" or id == "lucky" or id == "tray") then
					Fx.factoryWave(c, 24, info.effect(lv + 1), info.color)
				elseif c then
					Fx.factoryWave(c + Vector3.new(0, 6, 0), 10, info.effect(lv + 1), info.color)
				end
			end)
		end)
	end

	-- 배트 강화 행 (젬). 최대 Lv은 도감 발견 수로 열린다
	local BAT_INFO = {
		range = {
			title = "BAT RANGE",
			color = Color3.fromRGB(255, 170, 90),
			icon = "↔",
			effect = function(lv: number): string
				return Loc.format("upg.fxRange", { n = string.format("%.1f", Economy.batRange(lv)) })
			end,
		},
		power = {
			title = "BAT POWER",
			color = Color3.fromRGB(255, 110, 110),
			icon = "!",
			effect = function(lv: number): string
				return Loc.format("upg.fxPower", { n = Economy.batPower(lv) })
			end,
		},
		speed = {
			title = "SWING SPEED",
			color = Color3.fromRGB(120, 210, 255),
			icon = "»",
			effect = function(lv: number): string
				return Loc.format("upg.fxSwing", { s = string.format("%.2f", Economy.batCooldown(lv)) })
			end,
		},
		move = {
			title = "MOVE SPEED",
			color = Color3.fromRGB(130, 240, 150),
			icon = "›",
			effect = function(lv: number): string
				return Loc.format("upg.fxWalk", { n = string.format("%.4g", Economy.moveSpeed(lv)) })
			end,
		},
	}
	local batRows: { [string]: Row } = {}
	for order, stat in Economy.BAT_STATS do
		local info = BAT_INFO[stat]
		batRows[stat] = makeRow("BAT", order, info.icon, info.color, "Bat", function(b)
			return purchase(b, function()
				return (r.BatUpgrade :: RemoteFunction):InvokeServer(stat)
			end, function()
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					Fx.factoryWave(
						root.Position,
						8,
						Loc.msg("fx.statUp", { title = string.upper(info.title) }),
						info.color
					)
				end
			end)
		end)
	end
	local batHint = label({
		Size = UDim2.new(1, -8, 0, 44),
		Text = Ui.hint(
			"Equip the BAT (key 1) and click to whack your cubes into merges!",
			"Tap BAT, then SWING to whack your cubes into merges!"
		),
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 100,
		Parent = pages.BAT,
	})
	local function renderBat(s: { [string]: any })
		local bat = s.bat
		if not bat then
			return
		end
		for stat, row in batRows do
			local b = bat[stat]
			local info = BAT_INFO[stat]
			local lockText = if b.locked then Loc.msg("upg.finds", { n = Economy.batFindsFor(b.lv) }) else nil
			setRow(
				row,
				lvTitle(info.title, b.lv, bat.cap),
				info.effect(b.lv),
				if b.cost and not b.locked then info.effect(b.lv + 1) else nil,
				if b.locked then nil else b.cost,
				b.lv / Economy.BAT_MAX,
				if b.locked
					then Loc.msg("upg.batLocked", { n = bat.found, need = Economy.batFindsFor(b.lv), lv = b.lv + 1 })
					else `Lv{b.lv}/{Economy.BAT_MAX}`,
				true,
				lockText
			)
		end
		batHint.Visible = true
	end

	-- 보스 코인 강화 행 (docs/25): 수입 %·이동 속도 %·넉백 저항 %. 코인은 보스 레이드에서만
	local raidRemotes = Net.client(RaidRules.REMOTES :: any)
	local BOSS_ROW = {
		income = { color = Color3.fromRGB(255, 205, 70), icon = "$", image = "Cash", what = "income" },
		-- 글자 기호는 다른 행의 그림 아이콘과 톤이 안 맞아 그림으로 (2026-10-21 사용자)
		speed = { color = Color3.fromRGB(130, 240, 150), icon = "›", image = "Speed", what = "move speed" },
		resist = {
			color = Color3.fromRGB(150, 180, 255),
			icon = "◈",
			image = "Shield",
			what = "knockback & stun resist",
		},
		income2 = { color = Color3.fromRGB(255, 160, 60), icon = "$", image = "CashBag", what = "income" },
	}
	local bossNote = label({
		Size = UDim2.new(1, -8, 0, 44),
		Text = "",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 0,
		Parent = pages.BOSS,
	})
	local bossRows: { [string]: Row } = {}
	for order, u in RaidRules.UPGRADES do
		local info = BOSS_ROW[u.id]
		bossRows[u.id] = makeRow("BOSS", order, info.icon, info.color, info.image, function(b)
			return purchase(b, function()
				return (raidRemotes.RaidUpgrade :: RemoteFunction):InvokeServer(u.id)
			end, function()
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					Fx.factoryWave(root.Position, 8, Loc.msg("fx.statUp", { title = u.title }), info.color)
				end
			end)
		end)
	end
	local function pct(x: number): string
		return `+{math.floor(x * 100 + 0.5)}%`
	end
	local function renderBoss(s: { [string]: any })
		local raid = s.raid or {}
		local levels = raid.levels or {}
		Loc.set(bossNote, "upg.bossNote", { n = raid.coins or 0 })
		for _, u in RaidRules.UPGRADES do
			local lv = levels[u.id] or 0
			local info = BOSS_ROW[u.id]
			-- RAIDER INCOME+ (상한 없음)는 RAIDER INCOME을 다 산 뒤에만 보인다
			local row = bossRows[u.id]
			row.frame.Visible = RaidRules.unlocked(levels, u.id)
			if u.after then
				setRow(
					row,
					lvTitle(u.title, lv),
					Loc.format("upg.fxBoss", { pct = pct(lv * u.per), what = info.what }),
					`{pct((lv + 1) * u.per)}`,
					RaidRules.cost(lv, u.id),
					1,
					`Lv{lv}`,
					"coins"
				)
				continue
			end
			setRow(
				row,
				lvTitle(u.title, lv, u.max),
				Loc.format("upg.fxBoss", { pct = pct(lv * u.per), what = info.what }),
				if lv < u.max then `{pct((lv + 1) * u.per)}` else nil,
				if lv < u.max then RaidRules.cost(lv, u.id) else nil,
				lv / u.max,
				`Lv{lv}/{u.max}`,
				"coins"
			)
		end
	end

	-- 드로퍼 행 (게임패드·멀리서 보는 사람용, 월드 카드와 같은 동작)
	type DropperRows = { speed: Row, tier: Row }
	local dropperRows: { [number]: DropperRows } = {}
	local slotRow = makeRow("DROPPERS", 99, "+", THEME.accent, "Drop", function(b)
		local s = ctx.getState()
		local i = if s then #s.droppers + 1 else 0
		return purchase(b, function()
			return (r.Buy :: RemoteFunction):InvokeServer("slot", 0)
		end, function()
			local part = dropperPart(i)
			if part then
				Fx.dropperUnlock(part)
			end
		end)
	end)
	-- 일괄 강화 (2026-10-25): 드로퍼 강화 중 가장 싼 것부터 돈이 떨어질 때까지 (server/Factory buyAll)
	local allRow = makeRow("DROPPERS", 0, "", THEME.good, "Upgrades", function(b)
		return purchase(b, function()
			return (r.Buy :: RemoteFunction):InvokeServer("all", 0)
		end, function()
			local c = trayCenter()
			if c then
				Fx.factoryWave(c + Vector3.new(0, 6, 0), 8, "UPGRADED!", THEME.good)
			end
		end)
	end)
	local incubatorRow = makeRow("CORES", 1, "◎", Color3.fromRGB(150, 225, 255), "Cores", function(b)
		return purchase(b, function()
			return (r.Buy :: RemoteFunction):InvokeServer("incubator", 0)
		end, function()
			local c = trayCenter()
			if c then
				Fx.factoryWave(c + Vector3.new(0, 6, 0), 10, "NEW INCUBATOR!", Color3.fromRGB(150, 225, 255))
			end
		end)
	end)
	-- 리버스는 두 번 눌러 확정 (2026-10-20 리뷰: 한 번 닿기만 해도 돈·드로퍼가 초기화됐다). 첫 탭 뒤 3초 안에 다시
	local rebirthConfirmUntil = 0
	local rebirthRow: Row
	rebirthRow = makeRow("REBIRTH", 1, "★", Color3.fromRGB(255, 120, 200), "Star", function(b)
		local s = ctx.getState()
		if s and s.rebirthCost and not Economy.canRebirth(s.rebirths, s.runBest or 0) then
			ctx.toast(Loc.msg("upg.needTier", { tier = Economy.tierCeiling(s.rebirths) }))
			return false
		end
		if not (s and s.rebirthCost and s.cash >= s.rebirthCost) then
			ctx.toast("Not enough cash to rebirth")
			return false
		end
		local now = os.clock()
		if now > rebirthConfirmUntil then
			rebirthConfirmUntil = now + 3
			b.Text = "SURE?"
			b.BackgroundColor3 = THEME.bad
			ctx.toast("Tap REBIRTH again to reset cash & droppers")
			return false
		end
		rebirthConfirmUntil = 0
		local ok = (r.Rebirth :: RemoteFunction):InvokeServer()
		if not ok then
			ctx.toast("Not enough cash to rebirth")
		end
		return false -- 리버스는 연속 구매하지 않음
	end)
	label({
		Size = UDim2.new(1, -8, 0, 60),
		LayoutOrder = 2,
		Text = "Resets droppers and cash.\nKeeps factory upgrades, incubators and core bonus.",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamMedium,
		Parent = pages.REBIRTH,
	})

	local function renderPanel(s: { [string]: any })
		for i, d in s.droppers do
			local rows = dropperRows[i]
			if not rows then
				rows = {
					speed = makeRow("DROPPERS", i * 2, tostring(i), Config.TIER_COLORS[d.tier], "Frenzy", function(b)
						return buyDropper("speed", i, b)
					end),
					tier = makeRow(
						"DROPPERS",
						i * 2 + 1,
						tostring(i),
						Config.TIER_COLORS[d.tier],
						"Upgrades",
						function(b)
							return buyDropper("tier", i, b)
						end
					),
				}
				dropperRows[i] = rows
			end
			rows.speed.frame.Visible = true
			rows.tier.frame.Visible = true
			local ms = d.nextMilestone
			setRow(
				rows.speed,
				Loc.msg("upg.dropperSpeed", { i = i, lv = d.lv, max = Economy.MAX_SPEED_LV }),
				string.format("%.2fs", d.interval),
				if d.speedCost then string.format("%.2fs", Economy.dropInterval(d.lv + 1)) else nil,
				d.speedCost,
				if ms then d.lv / ms else 1,
				if ms then Loc.msg("upg.bigDropAt", { lv = ms }) else "MAX"
			)
			setRow(
				rows.tier,
				Loc.msg("upg.dropperTier", { i = i }),
				`T{d.tier}`,
				if d.tierCost then `T{d.tier + 1}` else nil,
				d.tierCost,
				d.tier / d.tierCap,
				Loc.msg("upg.tierCap", { tier = d.tierCap })
			)
		end
		for i, rows in dropperRows do
			if not s.droppers[i] then
				rows.speed.frame.Visible = false
				rows.tier.frame.Visible = false
			end
		end
		local cheapest: number? = s.slotCost
		for _, d in s.droppers do
			for _, c in { d.speedCost, d.tierCost } do
				if c and (cheapest == nil or c < cheapest) then
					cheapest = c
				end
			end
		end
		setRow(allRow, "BUY ALL UPGRADES", Loc.source("Cheapest first"), nil, cheapest, nil, nil, nil, "ALL MAX")
		Loc.plain(allRow.buy, if cheapest then "BUY ALL" else "ALL MAX")
		setRow(
			slotRow,
			Loc.msg("upg.newDropper", { n = #s.droppers, max = Economy.MAX_DROPPERS }),
			`{#s.droppers}`,
			if s.slotCost then `{#s.droppers + 1}` else nil,
			s.slotCost
		)

		for id, row in upgradeRows do
			local u = s.upgrades[id]
			local info = INFO[id]
			local ms = u.nextMilestone
			local msLabel = MILESTONE_TEXT[id]
			setRow(
				row,
				lvTitle(info.title, u.lv, u.max),
				info.effect(u.lv),
				if u.cost then info.effect(u.lv + 1) else nil,
				u.cost,
				if ms then u.lv / ms else u.lv / u.max,
				if ms and msLabel
					then Loc.msg("upg.milestone", { lv = ms, label = Loc.source(msLabel) })
					else `Lv{u.lv}/{u.max}`
			)
		end
		renderBat(s)
		renderBoss(s)
		setRow(
			incubatorRow,
			Loc.msg("upg.incubators", { n = s.incubatorCount, max = Economy.MAX_INCUBATORS }),
			Loc.format("upg.fxSlots", { n = s.incubatorCount }),
			if s.incubatorCost then Loc.format("upg.fxSlots", { n = s.incubatorCount + 1 }) else nil,
			s.incubatorCost
		)
		local nextMult = Economy.REBIRTH_MULT ^ (s.rebirths + 1)
		setRow(
			rebirthRow,
			Loc.msg("upg.rebirth", { n = s.rebirths, max = Economy.MAX_REBIRTH }),
			`x{string.format("%.4g", Economy.REBIRTH_MULT ^ s.rebirths)}`,
			if s.rebirthCost
				then (if Economy.tierCeiling(s.rebirths + 1) > Economy.tierCeiling(s.rebirths)
					then Loc.format(
						"upg.fxMergeTo",
						{ mult = `x{string.format("%.4g", nextMult)}`, tier = Economy.tierCeiling(s.rebirths + 1) }
					)
					else `x{string.format("%.4g", nextMult)}`)
				else nil,
			s.rebirthCost
		)
		if os.clock() <= rebirthConfirmUntil then
			rebirthRow.buy.Text = "SURE?"
			rebirthRow.buy.BackgroundColor3 = THEME.bad
		end
	end

	-- 지금 살 수 있는 것 개수 (탭별)
	local function counts(s: { [string]: any }): { [string]: number }
		local c = { DROPPERS = 0, FACTORY = 0, BAT = 0, CORES = 0, REBIRTH = 0 }
		if s.bat then
			for _, stat in Economy.BAT_STATS do
				local b = s.bat[stat]
				if b and not b.locked and affordable(b.cost, true) then
					c.BAT += 1
				end
			end
		end
		for _, d in s.droppers do
			c.DROPPERS += (if affordable(d.speedCost) then 1 else 0) + (if affordable(d.tierCost) then 1 else 0)
		end
		c.DROPPERS += if affordable(s.slotCost) then 1 else 0
		for id, u in s.upgrades do
			if affordable(u.cost) then
				c[INFO[id].tab] += 1
			end
		end
		c.CORES += if affordable(s.incubatorCost) then 1 else 0
		c.REBIRTH += if affordable(s.rebirthCost) and Economy.canRebirth(s.rebirths, s.runBest or 0) then 1 else 0
		return c
	end

	local self = { panel = panel }

	-- 패널을 특정 탭으로 연다 (목표 바에서 REBIRTH·BAT 등으로 바로 가기)
	local stationMode = false
	local function setStation(on: boolean)
		stationMode = on
		for n, b in tabButtons do
			b.Visible = if n == "BOSS" then on else not on
		end
	end
	function self.open(tab: string)
		if stationMode then
			setStation(false)
		end
		selectTab(tab)
		panel.Visible = true
	end

	-- 광장 BOSS SHOP 발판 (client/Stations): 올라서면 BOSS 탭만 보이는 패널, 내려오면 닫힘
	function self.station(on: boolean)
		if on then
			setStation(true)
			selectTab("BOSS")
			panel.Visible = true
		elseif stationMode then
			panel.Visible = false
		end
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible and stationMode then
			setStation(false)
			selectTab("DROPPERS")
		end
	end)

	function self.setPlot(model: Model)
		plot = model
	end

	-- 반환: 살 수 있는 총 개수 (UPGRADES 버튼 배지)
	function self.render(s: { [string]: any }): number
		renderCards(s)
		if panel.Visible then
			renderPanel(s)
		end
		local total = 0
		for name, n in counts(s) do
			total += n
			tabDots[name].Visible = n > 0
			tabDots[name].Text = tostring(n)
		end
		return total
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		local s = ctx.getState()
		if panel.Visible and s then
			renderPanel(s)
		end
	end)

	-- 서버 알림: 마일스톤 / 행운 합치기
	function self.onFx(kind: string, a: any, b: any)
		if kind == "milestone" then
			local at: Vector3? = nil
			if typeof(b) == "number" then
				local part = dropperPart(b)
				at = part and part.Position
			end
			at = at or trayCenter()
			if at then
				Fx.milestone(at, a)
			end
		elseif kind == "lucky" then
			Fx.lucky(a, b)
		end
	end

	return self
end

return Upgrades
