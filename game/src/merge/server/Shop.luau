--!strict
-- 상점: 개발자 상품 지급 + 게임 패스 확인 (docs/03 §2). 목록·수치는 shared/Shop.
-- 엔진(영수증 등록·패스 확인·패스 구매)은 core/server/Shop, 여기는 Merge 지급 표(GRANTS)와 패스 효과.
-- 패스 소유는 data.passes[key]에 적어 두고 Factory·Collection이 읽는다. 접속할 때마다 다시 확인한다(환불 반영).
-- 모든 보상은 정해진 양(유료 랜덤 금지). 재화 변경은 Ledger 경유.

local Shared = game:GetService("ReplicatedStorage").Game
local ShopDef = require(Shared.Shop)
local Economy = require(Shared.Economy)
local CoreServer = game:GetService("ServerScriptService").CoreServer
local Ledger = require(CoreServer.Ledger)
local CoreShop = require(CoreServer.Shop)
local Factory = require(script.Parent.Factory)

local Shop = {}

local function addFrenzy(data: { [string]: any }, seconds: number)
	-- 시계는 서버 시각 기준이라 나가 있어도 흐른다 (Events.luau와 같은 방식)
	data.frenzyUntil = math.max(data.frenzyUntil or 0, workspace:GetServerTimeNow()) + seconds
end

-- 상품별 지급. true를 돌려야 영수증이 처리된다
local GRANTS: { [string]: (Player, { [string]: any }) -> boolean } = {
	starter = function(player, data)
		local s = ShopDef.STARTER
		data.starterBought = true
		addFrenzy(data, s.frenzy)
		data.cosmetics.owned[s.cosmetic] = true
		Factory.shopFx(player, "STARTER PACK!")
		return Ledger.credit(player, "gems", s.gems, "IAP", "starter")
	end,
	shuffle = function(player, data)
		data.shufflePaid += Economy.SHUFFLE_PACK
		Factory.shopFx(player, `+{Economy.SHUFFLE_PACK} SHUFFLES`)
		return true
	end,
	steal = function(player, data)
		data.stealPaid += Economy.STEAL_PACK
		Factory.shopFx(player, `+{Economy.STEAL_PACK} STEALS`)
		return true
	end,
	rain = function(player, _data)
		return Factory.cubeRain(player, ShopDef.RAIN_CUBES)
	end,
	hatch = function(player, _data)
		return Factory.finishHatch(player)
	end,
}
-- 반짝 특가: 오늘 산 횟수에 따라 10 → 20 → 30분. 한도는 버튼에서 막지만, 넘겨 결제됐어도 지급은 한다(마지막 단계 분)
local Daily = require(Shared.Daily)
GRANTS.frenzy_xs = function(player, data)
	local day = Daily.dayOf(os.time())
	if data.flashDay ~= day then
		data.flashDay, data.flashCount = day, 0
	end
	data.flashCount += 1
	local minutes = ShopDef.flashMinutes(data.flashCount)
	addFrenzy(data, minutes * 60)
	Factory.shopFx(player, `FLASH FRENZY x5 +{minutes} MIN`)
	return true
end
for key, seconds in ShopDef.FRENZY_SECONDS do
	GRANTS[key] = function(player, data)
		addFrenzy(data, seconds)
		Factory.shopFx(player, `FRENZY x5 +{seconds // 60} MIN`)
		return true
	end
end
for key in ShopDef.CASH_MINUTES do
	GRANTS[key] = function(player, data)
		local amount = ShopDef.cashAmount(key, data.lastIncome or 0, data.rebirths)
		Factory.shopFx(player, "CASH!")
		return Ledger.credit(player, "cash", amount, "IAP", key)
	end
end
for key, amount in ShopDef.GEMS do
	GRANTS[key] = function(player, _data)
		Factory.shopFx(player, `+{amount} GEMS`)
		return Ledger.credit(player, "gems", amount, "IAP", key)
	end
end

-- 패스 효과 중 데이터에 남는 것 (Collector: 전용 오라)
local function applyPass(data: { [string]: any }, key: string)
	if key == "collector" then
		data.cosmetics.owned[ShopDef.COLLECTOR_COSMETIC] = true
	end
end

-- 서버 전용: Studio 디버그·테스트에서 결제 없이 지급 로직을 돌린다
function Shop.grant(player: Player, key: string): boolean
	return CoreShop.grant(player, key)
end

function Shop.init()
	CoreShop.init({
		items = ShopDef.ITEMS :: any,
		grants = GRANTS,
		onPass = function(player, data, key, owned, bought)
			if owned then
				applyPass(data, key)
			end
			if bought then
				local item = ShopDef.item(key)
				Factory.shopFx(player, `{string.upper(if item then item.name else key)} UNLOCKED!`)
			end
		end,
		refresh = Factory.refresh,
	})
end

return Shop
