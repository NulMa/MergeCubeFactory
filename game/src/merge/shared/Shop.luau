--!strict
-- 상점 목록 (docs/03 §2, 2026-10-18 개편). 전부 결과가 정해진 상품(유료 랜덤 금지, DECISIONS).
-- id = 0이면 아직 만들지 않은 상품 → 상점에서 숨긴다. 상품은 tools/products.mjs, 패스는 tools/passes.mjs로 만든다.
--   kind: "product"(반복 구매 개발자 상품) | "pass"(영구 게임 패스)
--   grant: 서버 Shop.luau가 보상을 고르는 키

local Economy = require(script.Parent.Economy)

local Shop = {}

export type Item = {
	key: string,
	kind: string,
	section: string,
	name: string,
	desc: string,
	price: number,
	id: number,
	color: Color3?,
	retired: boolean?, -- 판매 종료: 상점·버튼에서 숨김. 이미 산 것은 계속 지급·유지 (영수증·패스 확인은 그대로)
}

Shop.SECTIONS = { "SPECIAL", "PASSES", "BOOSTS", "CASH", "GEMS" }

-- 수치 (서버·클라 공용)
-- Cash 상품 = 다음 리버스 비용의 N% (2026-10-21 사용자 승인: 수입 N분치는 후반에 사도 진행이 0일 당겨짐).
-- 리버스를 다 했으면(MAX_REBIRTH) 예전처럼 지금 초당 수입 N분치
-- 2026-10-21 리버스 비용 1/10(상한 큐브 조건 추가) → 비율 ×10 = 지급액은 그대로 (5/20/60% → 50/200/600%)
Shop.CASH_PCT = { cash_s = 0.5, cash_m = 2, cash_l = 6 } :: { [string]: number }
Shop.CASH_MINUTES = { cash_s = 10, cash_m = 60, cash_l = 8 * 60 } :: { [string]: number }
Shop.CASH_MIN = 500 -- 수입이 아주 낮을 때 최소 지급
Shop.GEMS = { gems_s = 40, gems_m = 120, gems_l = 700 } :: { [string]: number }
Shop.FRENZY_SECONDS = { frenzy_s = 2 * 60, frenzy_m = 5 * 60 } :: { [string]: number }
Shop.RAIN_CUBES = 20 -- 큐브 비: 내 드로퍼 최고 등급 일반 큐브 N개 (변이 굴림 없음 → 확정)
-- 반짝 특가 프렌지 (2026-10-19 "x5 10~30분으로 파격적으로, 제한된 횟수만"): 하루(UTC) PER_DAY번,
-- 살 때마다 10 → 20 → 30분. 상점 목록에는 없고 오른쪽 위 버튼(client/BoostButton)에서만 판다
Shop.FLASH = { perDay = 3, minutes = { 10, 20, 30 } }
function Shop.flashMinutes(n: number): number -- n번째 구매(1부터)의 분
	local m = Shop.FLASH.minutes
	return m[math.clamp(n, 1, #m)]
end
Shop.STARTER = { gems = 200, frenzy = 10 * 60, cosmetic = "trail_starter" }
Shop.COLLECTOR_GEM_MULT = 2 -- 도감 첫 발견 젬 ×2
Shop.COLLECTOR_COSMETIC = "aura_galaxy"

Shop.ITEMS = {
	{
		key = "starter",
		kind = "product",
		section = "SPECIAL",
		name = "Starter Pack",
		desc = "200 Gems + 10 min Frenzy x5 + Starter Trail. Once only!",
		price = 29,
		id = 3719427305,
		color = Color3.fromRGB(255, 120, 170),
	},
	{
		key = "cash2x",
		kind = "pass",
		section = "PASSES",
		name = "2x Cash",
		desc = "Double all cash income forever",
		price = 199,
		id = 2036265503,
		color = Color3.fromRGB(110, 220, 120),
	},
	{
		key = "collector",
		kind = "pass",
		section = "PASSES",
		name = "Collector",
		desc = "x2 gems from new codex finds + Galaxy Aura",
		price = 149,
		id = 2036373632,
		color = Color3.fromRGB(170, 120, 255),
	},
	{
		-- 반짝 특가 (Shop.FLASH): 오른쪽 위 떠 있는 버튼(client/BoostButton)에서만 판다. 상점 목록엔 안 나옴
		key = "frenzy_xs",
		kind = "product",
		section = "FLASH",
		name = "Flash Frenzy x5 (10-30 min)",
		desc = "x5 income! Only 3 a day: 10, 20, then 30 minutes",
		price = 5,
		id = 3719646863,
	},
	{
		key = "frenzy_s",
		kind = "product",
		section = "BOOSTS",
		name = "Frenzy x5 (2 min)",
		desc = "x5 income for 2 minutes",
		price = 19,
		id = 3719427323,
		retired = true, -- 2026-10-20 상점 정리: 5 R$ 반짝 특가·Cash 상품보다 손해라 판매 종료 (산 영수증은 계속 지급)
	},
	{
		key = "frenzy_m",
		kind = "product",
		section = "BOOSTS",
		name = "Frenzy x5 (5 min)",
		desc = "x5 income for 5 minutes",
		price = 49,
		id = 3719427327,
		retired = true, -- 2026-10-20 상점 정리: 5 R$ 반짝 특가·Cash 상품보다 손해라 판매 종료 (산 영수증은 계속 지급)
	},
	{
		key = "rain",
		kind = "product",
		section = "BOOSTS",
		name = "Cube Rain",
		desc = "20 cubes of your best dropper tier fall at once",
		price = 25,
		id = 3719427334,
	},
	{
		key = "hatch",
		kind = "product",
		section = "BOOSTS",
		name = "Instant Hatch",
		desc = "Finish every hatching core now",
		price = 19,
		id = 3719427338,
	},
	{
		key = "shuffle",
		kind = "product",
		section = "BOOSTS",
		name = "Shuffle x3",
		desc = "3 shuffle blasts",
		price = 15,
		id = 3719259642,
		retired = true, -- 배트 도입으로 판매 종료 (2026-10-18)
	},
	{
		key = "steal",
		kind = "product",
		section = "BOOSTS",
		name = "Steal x3",
		desc = "3 extra steals",
		price = 25,
		id = 3719558012,
	},
	{
		key = "cash_s",
		kind = "product",
		section = "CASH",
		name = "Cash Bag",
		desc = "Half of your next rebirth",
		price = 15,
		id = 3719427347,
	},
	{
		key = "cash_m",
		kind = "product",
		section = "CASH",
		name = "Cash Chest",
		desc = "2x your next rebirth",
		price = 49,
		id = 3719427355,
	},
	{
		key = "cash_l",
		kind = "product",
		section = "CASH",
		name = "Cash Vault",
		desc = "6x your next rebirth",
		price = 199,
		id = 3719427361,
	},
	{
		key = "gems_s",
		kind = "product",
		section = "GEMS",
		name = "Gem Pouch",
		desc = "40 gems",
		price = 19,
		id = 3719427370,
	},
	{
		key = "gems_m",
		kind = "product",
		section = "GEMS",
		name = "Gem Pack",
		desc = "120 gems",
		price = 49,
		id = 3719427383,
	},
	{
		key = "gems_l",
		kind = "product",
		section = "GEMS",
		name = "Gem Chest",
		desc = "700 gems (best value)",
		price = 249,
		id = 3719427388,
	},
} :: { Item }

function Shop.item(key: string): Item?
	for _, it in Shop.ITEMS do
		if it.key == key then
			return it
		end
	end
	return nil
end

-- 진행도 비례 현금: 다음 리버스 비용 × N% (리버스를 다 했으면 지금 초당 수입 × 분)
function Shop.cashAmount(key: string, incomePerSec: number, rebirths: number?): number
	local r = rebirths or 0
	local amount = if r < Economy.MAX_REBIRTH
		then Economy.rebirthCost(r) * (Shop.CASH_PCT[key] or 0)
		else incomePerSec * (Shop.CASH_MINUTES[key] or 0) * 60
	return math.max(Shop.CASH_MIN, math.floor(amount))
end

return Shop
