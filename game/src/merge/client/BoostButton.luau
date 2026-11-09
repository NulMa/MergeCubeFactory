--!strict
-- 오른쪽 위 떠 있는 초저가 단기 버프 버튼 (2026-10-19 사용자 "매우 싼 단기 버프 상품, 우상단 강조 버튼으로 플로팅").
-- 상품: Shop "frenzy_xs" 반짝 특가 (Shop.FLASH: 하루 3번, 10 → 20 → 30분). 상품 id가 0이면 버튼을 만들지 않는다.
-- 남은 횟수를 보여 주고(소유욕), 다 사면 SOLD OUT + 초기화까지 남은 시간. 프렌지 중이면 남은 시간도 같이.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopDef = require(ReplicatedStorage.Game.Shop)
local EventsConfig = require(ReplicatedStorage.Game.EventsConfig)
local Format = require(ReplicatedStorage.Core.Format)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Loc = require(ReplicatedStorage.CoreClient.Loc)
local ShopUi = require(script.Parent.ShopUi)

local BoostButton = {}

local KEY = "frenzy_xs"
local FLASH = ShopDef.FLASH

-- 반환: 세로 위치를 바꾸는 함수 (휴대폰에서 init.client가 오른쪽 위 버튼들 아래로 내린다). 상품이 없으면 nil
function BoostButton.start(gui: ScreenGui, getState: () -> { [string]: any }?): ((y: number) -> ())?
	local item = ShopDef.item(KEY)
	if not item or item.id == 0 then
		return nil
	end
	local b = Ui.button({
		Visible = false,
		Size = UDim2.fromOffset(204, 68),
		Position = UDim2.new(1, -16, 0, 66), -- Roblox 상단 바 아래
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 120, 60),
		Text = "",
		Parent = gui,
	}, function()
		local s = getState()
		local f = s and s.shop and s.shop.flash
		if f and f.left <= 0 then
			return -- 오늘 다 샀음
		end
		ShopUi.prompt(KEY)
	end)
	Ui.addIcon(b, "Frenzy", 1.2)
	local title = Ui.label({
		Size = UDim2.fromScale(1, 0.58),
		Loc = Loc.msg("boost.offer", { mult = EventsConfig.FRENZY_MULT, mins = 10 }),
		TextColor3 = Ui.THEME.accentInk,
		Parent = b,
	})
	local sub = Ui.label({
		Size = UDim2.fromScale(1, 0.42),
		Position = UDim2.fromScale(0, 0.58),
		Loc = Loc.msg("boost.priceLeft", { price = item.price, left = 3, max = 3 }),
		TextColor3 = Ui.THEME.accentInk,
		Font = Enum.Font.GothamBold,
		Parent = b,
	})
	do
		-- 무지개처럼 도는 테두리 + 주기적 반짝임 + 살짝 둥실 (눈에 띄게)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Parent = b
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 120)),
		})
		g.Parent = stroke
		Ui.spinGradient(g, 120)
		Ui.shine(b, 2.5)
	end
	-- 살짝 둥실: 위치 트윈이 계속 Position을 덮어쓰므로 자리를 옮길 땐 트윈을 새로 만든다
	local float: Tween? = nil
	local function place(y: number)
		if float then
			float:Cancel()
		end
		local base = UDim2.new(1, -16, 0, y)
		b.Position = base
		local t = TweenService:Create(
			b,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = base + UDim2.fromOffset(0, 5) }
		)
		t:Play()
		float = t
	end
	place(66)
	-- 프렌지 남은 시간 (state.events.frenzy = 받은 시점의 남은 초)
	local lastEvents: any = nil
	local lastShop: any = nil
	local recvAt = os.clock()
	task.spawn(function()
		while b.Parent do
			local s = getState()
			local e = s and s.events
			if e ~= lastEvents or (s and s.shop) ~= lastShop then
				lastEvents = e
				lastShop = s and s.shop
				recvAt = os.clock()
			end
			local left = if e and e.frenzy then math.max(0, e.frenzy - (os.clock() - recvAt)) else 0
			-- 첫 리버스 전에는 숨긴다 (2026-10-20 리뷰: 첫 화면에서 R$ 버튼이 제일 반짝여 할 일을 가린다). 프렌지 중이면 남은 시간은 보인다
			b.Visible = left > 0 or (s ~= nil and (s.rebirths or 0) >= 1)
			local f = s and s.shop and s.shop.flash
			local stock = if f then f.left else FLASH.perDay
			if stock <= 0 then
				-- 오늘 다 팔림: 회색 + 초기화까지 남은 시간 (resetIn은 받은 시점 기준)
				b.BackgroundColor3 = Color3.fromRGB(110, 110, 125)
				if left > 0 then
					Loc.set(title, "boost.frenzyLeft", { time = EventsConfig.clock(left) })
				else
					Loc.plain(title, "SOLD OUT")
				end
				Loc.set(
					sub,
					"boost.newDeals",
					{ time = Format.duration(math.max(0, f.resetIn - (os.clock() - recvAt))) }
				)
			else
				b.BackgroundColor3 = Color3.fromRGB(255, 120, 60)
				local mins = if f then f.nextMin else FLASH.minutes[1]
				if left > 0 then
					Loc.set(title, "boost.frenzyLeft", { time = EventsConfig.clock(left) })
					Loc.set(sub, "boost.moreLeft", { mins = mins, left = stock, max = FLASH.perDay })
				else
					Loc.set(title, "boost.offer", { mult = EventsConfig.FRENZY_MULT, mins = mins })
					Loc.set(sub, "boost.priceLeft", { price = item.price, left = stock, max = FLASH.perDay })
				end
			end
			task.wait(0.25)
		end
	end)
	return place
end

return BoostButton
