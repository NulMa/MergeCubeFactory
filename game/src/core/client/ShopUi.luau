--!strict
-- 상점 패널 (docs/03 §2, docs/33): 구역별 카드(아이콘·이름·설명·가격·리본). Core client module.
-- 가격은 MarketplaceService:GetProductInfo로 읽는다 (docs/32 §3-6 "가격 하드코딩 금지"; 지역별 가격은 Roblox가
-- 보는 사람 기준으로 돌려준다). 읽는 동안·실패하면 catalog의 price(있으면)를, 없으면 "R$ ..."를 보인다.
-- 아직 만들지 않은 상품(id 0)·판매 종료(retired)는 숨긴다. 산 패스는 OWNED.
--   local shop = ShopUi.new({
--     gui = gui,
--     catalog = { sections = { "PASSES", "COINS" }, items = Catalog.ITEMS,
--                 sectionColor = {...}, sectionIcon = {...}, icons = { key = "IconName" }, ribbons = { key = "BEST VALUE" } },
--     owned = function(key) return state.passes[key] == true end,
--     hidden = function(item) return false end,            -- optional extra hide rule
--     beforeBuy = function(item, buyButton) return true end, -- optional: false cancels (show a reason on the button)
--     describe = function(item, descLabel) end,             -- optional: live description (e.g. amount for this player)
--   })
--   shop.render() after state changes; shop.panel.Visible = true to open; ShopUi.prompt(item) to buy from anywhere.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Ui = require(script.Parent.Ui)

local ShopUi = {}

export type Item = {
	key: string,
	kind: string, -- "product" | "pass"
	section: string,
	name: string,
	desc: string,
	id: number,
	price: number?, -- fallback only (shown until the real price arrives)
	color: Color3?,
	retired: boolean?,
	[any]: any,
}
export type Catalog = {
	sections: { string },
	items: { Item },
	sectionColor: { [string]: Color3 }?,
	sectionIcon: { [string]: string }?,
	icons: { [string]: string }?,
	ribbons: { [string]: string }?,
	special: { [string]: boolean }?, -- sections drawn as big shiny cards (default { SPECIAL = true })
}
export type Ctx = {
	gui: ScreenGui,
	catalog: Catalog,
	owned: (key: string) -> boolean,
	hidden: ((item: Item) -> boolean)?,
	beforeBuy: ((item: Item, buy: TextButton) -> boolean)?,
	describe: ((item: Item, desc: TextLabel) -> ())?,
	title: string?,
}

-- 가격 캐시: id -> R$ (nil = 아직/실패)
local prices: { [number]: number } = {}
local waiting: { [number]: { (number?) -> () } } = {}

-- Real price for this player (async, cached). cb(nil) when the lookup failed.
function ShopUi.priceOf(item: Item, cb: (number?) -> ())
	if item.id == 0 then
		cb(nil)
		return
	end
	local cached = prices[item.id]
	if cached then
		cb(cached)
		return
	end
	local list = waiting[item.id]
	if list then
		table.insert(list, cb)
		return
	end
	waiting[item.id] = { cb }
	task.spawn(function()
		local info = if item.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, res = pcall(function()
			return MarketplaceService:GetProductInfo(item.id, info)
		end)
		local price = if ok
				and type(res) == "table"
				and type(res.PriceInRobux) == "number"
			then res.PriceInRobux
			else nil
		if price then
			prices[item.id] = price
		end
		local cbs: { (number?) -> () } = waiting[item.id] or {}
		waiting[item.id] = nil
		for _, f in cbs do
			f(price)
		end
	end)
end

-- "R$ 99" (real price, else catalog fallback, else "R$ ...")
function ShopUi.priceText(item: Item): string
	local p = prices[item.id] or item.price
	return if p then `R$ {p}` else "R$ ..."
end

-- Show the purchase prompt (product or pass). false if the item does not exist yet (id 0)
function ShopUi.prompt(item: Item?): boolean
	if not item or item.id == 0 then
		return false
	end
	local player = Players.LocalPlayer
	if item.kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, item.id)
	else
		MarketplaceService:PromptProductPurchase(player, item.id)
	end
	return true
end

-- 아이콘 뒤에서 도는 햇살
function ShopUi.sunburst(parent: GuiObject, color: Color3, scale: number, z: number)
	local rays = Ui.icon("Sunburst", {
		Size = UDim2.fromScale(scale, scale),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = color,
		ImageTransparency = 0.25,
		ZIndex = z,
		Parent = parent,
	})
	if rays then
		Ui.spin(rays, 25)
	end
end

function ShopUi.new(ctx: Ctx)
	local THEME = Ui.THEME
	local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button
	local cat = ctx.catalog
	local sectionColor = cat.sectionColor or {}
	local sectionIcon = cat.sectionIcon or {}
	local icons = cat.icons or {}
	local ribbons = cat.ribbons or {}
	local specialSections = cat.special or { SPECIAL = true }
	local title = ctx.title or "SHOP"

	local panel = make("Frame", {
		Size = UDim2.fromOffset(460, 440),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = ctx.gui,
	}, { corner(14) }) :: Frame
	Ui.bindPanel(panel) -- theme open motion + sound (default: none)
	Ui.title({
		Size = UDim2.new(1, -70, 0, 40),
		Position = UDim2.fromOffset(12, 8),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Icon = "Shop", -- 아이콘 폭 + 간격만큼 글자를 민다 (공백 문자로 밀면 글꼴마다 폭이 달라 첫 글자를 덮었다)
		IconSize = 56,
		Parent = panel,
	})
	button({
		Size = UDim2.fromOffset(44, 40),
		Position = UDim2.new(1, -52, 0, 8),
		Text = "X",
		BackgroundColor3 = THEME.bad,
		Parent = panel,
	}, function()
		Ui.closePanel(panel)
	end)
	local list = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -60),
		Position = UDim2.fromOffset(8, 54),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	type Card = { item: Item, frame: Frame, desc: TextLabel, buy: TextButton }
	local cards: { Card } = {}
	local headers: { [string]: TextLabel } = {}
	local order = 0
	for _, section in cat.sections do
		order += 1
		local secColor = sectionColor[section] or THEME.accent
		local header = label({
			Size = UDim2.new(1, -8, 0, 30),
			Text = section,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = secColor,
			LayoutOrder = order,
			Parent = list,
		})
		if sectionIcon[section] then
			Ui.leadIcon(header, sectionIcon[section], 30, { gap = 6 })
		end
		headers[section] = header
		for _, item in cat.items do
			if item.section ~= section then
				continue
			end
			order += 1
			local tint = item.color or secColor
			local special = specialSections[section] == true
			local h = if special then 96 else 70
			-- 카드: 상품 색으로 물든 그라데이션 + 굵은 색 테두리
			local frame = make("Frame", {
				Size = UDim2.new(1, -12, 0, h),
				BackgroundColor3 = tint,
				LayoutOrder = order,
				Parent = list,
			}, {
				corner(12),
				make("UIGradient", {
					Color = ColorSequence.new(tint:Lerp(THEME.card, 0.45), tint:Lerp(THEME.panel, 0.8)),
					Rotation = 90,
				}),
				make("UIStroke", {
					Color = tint,
					Thickness = if special then 4 else 2.5,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}) :: Frame
			local iconName = icons[item.key]
			local textLeft = 12
			if iconName and Ui.hasIcon(iconName) then
				textLeft = h + 4
				if special then
					local holder = make("Frame", {
						Size = UDim2.fromOffset(h, h),
						BackgroundTransparency = 1,
						Parent = frame,
					})
					ShopUi.sunburst(holder, tint, 1.5, 1)
				end
				local icon = Ui.icon(iconName, {
					Size = UDim2.fromOffset(h - 4, h - 4),
					Position = UDim2.fromOffset(2, 2),
					ZIndex = 3,
					Parent = frame,
				}) :: ImageLabel
				if special then
					Ui.wiggle(icon, 6)
				end
			end
			local ribbon = ribbons[item.key] or (if item.kind == "pass" then "FOREVER" else nil)
			if ribbon then
				local tag = make("Frame", {
					Size = UDim2.fromOffset(96, 22),
					Position = UDim2.new(1, -8, 0, -8),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundColor3 = if ribbon == "FOREVER" then THEME.accent2 else THEME.bad,
					Rotation = 4,
					ZIndex = 6,
					Parent = frame,
				}, {
					corner(6),
					make("UIStroke", { Thickness = 2, Color = THEME.outline }),
				})
				label({
					Size = UDim2.new(1, -6, 1, -2),
					Position = UDim2.fromOffset(3, 1),
					Text = ribbon,
					ZIndex = 7,
					Parent = tag,
				})
			end
			if special then
				Ui.shine(frame, 2.2)
			end
			label({
				Size = UDim2.new(1, -textLeft - 124, 0.48, 0),
				Position = UDim2.new(0, textLeft, 0.06, 0),
				Text = item.name,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = tint,
				Parent = frame,
			})
			local desc = label({
				Size = UDim2.new(1, -textLeft - 124, 0.38, 0),
				Position = UDim2.new(0, textLeft, 0.56, 0),
				Text = item.desc,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = THEME.desc,
				Role = "body",
				Parent = frame,
			})
			local buy: TextButton
			buy = button({
				Size = UDim2.fromOffset(106, 48),
				Position = UDim2.new(1, -114, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Text = ShopUi.priceText(item),
				BackgroundColor3 = THEME.buy,
				TextColor3 = THEME.buyText,
				ZIndex = 4,
				Parent = frame,
			}, function()
				if item.kind == "pass" and ctx.owned(item.key) then
					return
				end
				if ctx.beforeBuy and not ctx.beforeBuy(item, buy) then
					return
				end
				ShopUi.prompt(item)
			end)
			Ui.shine(buy, 3)
			table.insert(cards, { item = item, frame = frame, desc = desc, buy = buy })
			ShopUi.priceOf(item, function(_price)
				if not (item.kind == "pass" and ctx.owned(item.key)) then
					buy.Text = ShopUi.priceText(item)
				end
			end)
		end
	end

	local function render()
		local visible: { [string]: boolean } = {}
		for _, c in cards do
			local item = c.item
			local show = item.id ~= 0 and not item.retired and not (ctx.hidden and ctx.hidden(item))
			c.frame.Visible = show
			if not show then
				continue
			end
			visible[item.section] = true
			if item.kind == "pass" and ctx.owned(item.key) then
				c.buy.Text = "OWNED"
				c.buy.BackgroundColor3 = THEME.card
				c.buy.TextColor3 = THEME.good
			end
			if ctx.describe then
				ctx.describe(item, c.desc)
			end
		end
		for section, hdr in headers do
			hdr.Visible = visible[section] == true
		end
	end

	return { panel = panel, render = render }
end

return ShopUi
