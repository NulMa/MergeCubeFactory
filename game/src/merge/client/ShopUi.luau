--!strict
-- Merge 상점 (docs/03 §2): 패널·카드·가격 조회는 core/client/ShopUi, 여기는 Merge 카탈로그·규칙·스타터 팩 제안.
-- 아직 만들지 않은 상품(id 0)은 숨긴다. 가격은 MarketplaceService에서 읽는다 (읽기 전엔 shared/Shop의 price).
-- 산 패스는 OWNED, 스타터 팩은 산 뒤 사라진다. 현금 상품은 지금 수입 기준 금액을 보여 준다.
-- 스타터 팩 제안: 플레이 STARTER_OFFER_AFTER초 뒤 가운데 창. 24시간에 한 번, 계정당 최대 3번 (서버 Factory.starterOfferReady).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Core.Format)
local ShopDef = require(ReplicatedStorage.Game.Shop)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Loc = require(ReplicatedStorage.CoreClient.Loc)
local CoreShopUi = require(ReplicatedStorage.CoreClient.ShopUi)

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button
local STARTER_OFFER_AFTER = 300 -- 접속 후 5분 (150초는 첫 인상에 너무 빨랐다)
local SECTION_COLOR = {
	SPECIAL = Color3.fromRGB(255, 120, 170),
	PASSES = Color3.fromRGB(170, 120, 255),
	BOOSTS = Color3.fromRGB(255, 160, 60),
	CASH = Color3.fromRGB(110, 220, 120),
	GEMS = Color3.fromRGB(150, 230, 255),
}

-- 상품 key → 아이콘 (AssetIds.Icons)
local ICON = {
	starter = "Starter",
	cash2x = "Pass2x",
	collector = "Collector",
	frenzy_xs = "Frenzy",
	frenzy_s = "Frenzy",
	frenzy_m = "Frenzy",
	rain = "Rain",
	hatch = "Hatch",
	shuffle = "Shuffle",
	steal = "Bat",
	cash_s = "CashBag",
	cash_m = "CashChest",
	cash_l = "CashVault",
	gems_s = "GemPouch",
	gems_m = "GemPack",
	gems_l = "GemChest",
}
local SECTION_ICON = { SPECIAL = "Star", PASSES = "Pass2x", BOOSTS = "Frenzy", CASH = "Cash", GEMS = "Gem" }
-- 리본: 사실인 문구만 (R$당 양이 가장 많은 묶음 = BEST VALUE, 패스 = FOREVER)
local RIBBON = { cash_l = "BEST VALUE", gems_l = "BEST VALUE", starter = "ONE TIME!" }

local ShopUi = {}

local sunburst = CoreShopUi.sunburst

-- 구매 창 띄우기 (상품/패스 구분). id 0이면 false
function ShopUi.prompt(key: string): boolean
	return CoreShopUi.prompt(ShopDef.item(key) :: any)
end

function ShopUi.new(ctx: { gui: ScreenGui, getState: () -> { [string]: any }?, remotes: { [string]: any }? })
	local last: { [string]: any }? = nil
	local core = CoreShopUi.new({
		gui = ctx.gui,
		catalog = {
			sections = ShopDef.SECTIONS,
			items = ShopDef.ITEMS :: any,
			sectionColor = SECTION_COLOR,
			sectionIcon = SECTION_ICON,
			icons = ICON,
			ribbons = RIBBON,
		},
		owned = function(key: string): boolean
			local s = last or ctx.getState()
			return s ~= nil and s.shop.passes[key] == true
		end,
		hidden = function(item): boolean
			local s = last
			return item.key == "starter" and s ~= nil and s.shop.starter == true
		end,
		beforeBuy = function(item, buy): boolean
			local s = ctx.getState()
			-- 부화 중인 코어가 없으면 Instant Hatch를 팔지 않는다 (서버는 혹시 산 경우 다음 코어에 쓴다)
			if item.key == "hatch" and s then
				local hatching = false
				for _, h in s.hatching do
					if h and h.remaining > 0 then
						hatching = true
					end
				end
				if not hatching then
					buy.Text = "NOTHING HATCHING"
					task.delay(1.5, function()
						buy.Text = CoreShopUi.priceText(item)
					end)
					return false
				end
			end
			return true
		end,
		describe = function(item, desc)
			local s = last
			if s and ShopDef.CASH_MINUTES[item.key] then
				Loc.set(desc, "shop.cashDesc", {
					cash = Format.short(ShopDef.cashAmount(item.key, s.income or 0, s.rebirths)),
					desc = Loc.source(item.desc),
				})
			end
		end,
	})
	local panel = core.panel

	local function render(s: { [string]: any })
		last = s
		core.render()
	end

	-- 스타터 팩 제안 창 (세션당 한 번)
	local offer = make("Frame", {
		Size = UDim2.fromOffset(400, 290),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 20,
		Parent = ctx.gui,
	}, {
		corner(16),
		make("UIStroke", { Color = SECTION_COLOR.SPECIAL, Thickness = 3 }),
	}) :: Frame
	Ui.touchFit(ctx.gui, offer)
	local starter = ShopDef.item("starter") :: ShopDef.Item
	local art = make("Frame", {
		Size = UDim2.fromOffset(150, 150),
		Position = UDim2.new(0.5, 0, 0, -40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = offer,
	})
	sunburst(art, SECTION_COLOR.SPECIAL, 2, 22)
	local gift = Ui.icon("Starter", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 23,
		Parent = art,
	})
	if gift then
		Ui.wiggle(gift, 8)
	end
	label({
		Size = UDim2.new(1, -30, 0, 44),
		Position = UDim2.fromOffset(15, 50),
		Text = "STARTER PACK",
		TextColor3 = SECTION_COLOR.SPECIAL,
		ZIndex = 21,
		Parent = offer,
	})
	label({
		Size = UDim2.new(1, -30, 0, 70),
		Position = UDim2.fromOffset(15, 98),
		Text = starter.desc,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		ZIndex = 21,
		Parent = offer,
	})
	local buyStarter = button({
		Size = UDim2.new(0.55, -20, 0, 56),
		Position = UDim2.new(0, 15, 1, -71),
		Text = `BUY {CoreShopUi.priceText(starter :: any)}`,
		BackgroundColor3 = THEME.accent,
		TextColor3 = THEME.accentInk,
		ZIndex = 21,
		Parent = offer,
	}, function()
		offer.Visible = false
		ShopUi.prompt("starter")
	end)
	CoreShopUi.priceOf(starter :: any, function()
		buyStarter.Text = `BUY {CoreShopUi.priceText(starter :: any)}`
	end)
	button({
		Size = UDim2.new(0.45, -15, 0, 56),
		Position = UDim2.new(0.55, 0, 1, -71),
		Text = "LATER",
		ZIndex = 21,
		Parent = offer,
	}, function()
		offer.Visible = false
	end)
	-- 서버가 허락할 때만 (24시간에 한 번, 계정당 최대 3번 — 매 접속마다 뜨던 것, 2026-10-19)
	task.delay(STARTER_OFFER_AFTER, function()
		local s = ctx.getState()
		if starter.id == 0 or not s or s.shop.starter or not s.shop.offerReady or panel.Visible then
			return
		end
		local remote = ctx.remotes and ctx.remotes.StarterOffered
		local ok, allowed = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and allowed then
			offer.Visible = true
		end
	end)

	return { panel = panel, render = render }
end

return ShopUi
