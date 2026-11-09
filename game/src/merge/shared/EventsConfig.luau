--!strict
-- 이벤트 (황금 큐브·머지 피버·서버 알림) 수치와 순수 공식. docs/17_EVENTS.md, docs/15 §4 R1·R4·R5.
-- 공식은 core/shared/EventRules (중립 이름), 여기는 Merge 수치. Lune 테스트(tests/merge/Events.spec.luau).
-- 최고 등급은 인자로 받는다 (등급 확장 브랜치가 Economy.MAX_TIER를 바꿔도 여기 숫자는 그대로).

local EventRules = require(script.Parent.Parent.Core.EventRules)

local EventsConfig = {}

-- 황금 큐브 (R1) -------------------------------------------------------------------
EventsConfig.GOLDEN_FIRST = 90 -- 접속 후 첫 등장까지 (초)
EventsConfig.GOLDEN_MIN = 4 * 60 -- 다음 등장까지 균등 랜덤 [MIN, MAX] (사라진 뒤부터 잼)
EventsConfig.GOLDEN_MAX = 10 * 60
EventsConfig.GOLDEN_LIFE = 12 -- 화면에 머무는 시간 (초)
EventsConfig.GOLDEN_GRACE = 0.75 -- 지연 보정: 사라지는 순간 누른 탭도 인정
EventsConfig.GOLDEN_CLAIM_RANGE = 400 -- ClickDetector 거리 (studs). 카메라가 멀리 있어도 누를 수 있게

export type RewardId = "cash" | "frenzy" | "storm" | "rain" | "jackpot"

-- 무료 랜덤 보상표 (합계 100). Robux와 무관해야 한다 (DECISIONS 2026-10-18 유료 랜덤 없음)
EventsConfig.REWARDS = {
	{ id = "cash" :: RewardId, weight = 45 },
	{ id = "frenzy" :: RewardId, weight = 35 },
	{ id = "storm" :: RewardId, weight = 12 },
	{ id = "rain" :: RewardId, weight = 6 },
	{ id = "jackpot" :: RewardId, weight = 2 },
}

-- CASH BURST: 현재 초당 수입 × 이 초. 연구 초안 600초는 총수입 +80% 이상이라 줄였다 (docs/17 §2.3)
EventsConfig.CASH_SECONDS = 150
EventsConfig.CASH_FLOOR = 50 -- 수입이 거의 없는 첫 몇 분에도 보상이 0이 아니게
EventsConfig.FRENZY_MULT = 5
EventsConfig.FRENZY_SECONDS = 30
EventsConfig.STORM_SCALE = 1 / 3 -- 드로퍼 투하 간격 배율 (= 큐브 3배)
EventsConfig.STORM_SECONDS = 20
EventsConfig.RAIN_COUNT = 4
EventsConfig.RAIN_ABOVE_DROPPER = 2 -- TIER RAIN 등급 상한 = 드로퍼 최고 등급 + 이 값
EventsConfig.JACKPOT_ABOVE_BEST = 1

-- 머지 피버 (R4) -------------------------------------------------------------------
EventsConfig.FEVER_GOAL = 30
-- 2026-10-20 "오버드라이브": 피버를 키웠다. 12초 → 20초, 피버 중 드로퍼 2배속, 3연쇄 이상 합치기는 게이지 2칸
EventsConfig.FEVER_SECONDS = 20
EventsConfig.FEVER_MULT = 3
EventsConfig.FEVER_DROP_SCALE = 0.5 -- 피버 중 투하 간격 배율
EventsConfig.FEVER_COMBO_FROM = 3 -- 이 콤보부터 합치기 하나가 게이지 2칸
-- 게이지 감쇠/초 = BASE + 드로퍼가 혼자 만드는 합치기/초 × PASSIVE.
-- 방치 상태의 합치기는 감쇠와 상쇄되어 게이지가 거의 안 찬다 → 직접 투하·SHUFFLE·연쇄로만 피버 (실력·참여).
EventsConfig.FEVER_DECAY_BASE = 1
EventsConfig.FEVER_DECAY_PASSIVE = 1

-- 이벤트 배수 합계 상한 (FRENZY × FEVER 겹침이 너무 커지지 않게)
EventsConfig.MULT_CAP = 10

-- 서버 알림 (R5) -------------------------------------------------------------------
EventsConfig.ANNOUNCE_FRACTION = 0.8 -- 최고 등급의 80% 이상 첫 도달 (MAX 12 → 10)
EventsConfig.ANNOUNCE_MIN_TIER = 6
EventsConfig.ANNOUNCE_WINDOW = 60 -- 서버 전체: WINDOW초에 최대 SERVER_MAX건
EventsConfig.ANNOUNCE_SERVER_MAX = 3
EventsConfig.ANNOUNCE_PLAYER_GAP = 20 -- 같은 플레이어 알림 최소 간격 (초)
EventsConfig.BANNER_SECONDS = 4

-- 상품 (확정 효과만, 0 = 없음 → 숨김). Creator Hub에서 만든 뒤 채운다 (docs/17 §5)

-- Remote 계약 (core Net 형식). Net.serve를 한 번 더 불러 같은 Remotes 폴더에 추가한다 → Remotes.luau 수정 없음
EventsConfig.REMOTES = {
	ClaimGolden = { kind = "function", args = { "number" } }, -- 황금 큐브 id
	EventFx = { kind = "event" }, -- ("golden", pos, rewardId, text, tier?) | ("fever", pos) | ("feverEnd")
	Announce = { kind = "event" }, -- (text: string, kind: string) 서버 전체 배너 + 시스템 채팅
}

-- 공식 (core/shared/EventRules) ---------------------------------------------------

-- r ∈ [0, 1)
function EventsConfig.goldenDelay(r: number): number
	return EventRules.randomDelay(EventsConfig.GOLDEN_MIN, EventsConfig.GOLDEN_MAX, r)
end

function EventsConfig.totalWeight(): number
	local sum = 0
	for _, rw in EventsConfig.REWARDS do
		sum += rw.weight
	end
	return sum
end

-- r ∈ [0, 1) → 보상 id (가중치 누적)
function EventsConfig.pickReward(r: number): RewardId
	return EventRules.pickId(EventsConfig.REWARDS, r) :: RewardId
end

function EventsConfig.cashBurst(incomePerSec: number): number
	return math.max(EventsConfig.CASH_FLOOR, incomePerSec * EventsConfig.CASH_SECONDS)
end

-- TIER RAIN: "최고 기록 - 1" 정도, 단 드로퍼 최고 등급 + 2를 넘지 않게
-- (리버스 직후 최고 기록은 그대로라 기록 기준만 쓰면 리버스 속도가 무너진다)
function EventsConfig.rainTier(best: number, dropperTop: number, maxTier: number): number
	local t = math.min(best - 1, dropperTop + EventsConfig.RAIN_ABOVE_DROPPER)
	return math.clamp(t, 1, maxTier - 1)
end

-- JACKPOT: 최고 기록 + 1 (상한 maxTier) → 대개 새 기록 = 서버 알림
function EventsConfig.jackpotTier(best: number, maxTier: number): number
	return math.clamp(best + EventsConfig.JACKPOT_ABOVE_BEST, 2, maxTier)
end

-- 피버 게이지 감쇠 (dt초). passiveRate = 드로퍼 투하/초 (방치 합치기/초 추정)
function EventsConfig.feverDecay(gauge: number, dt: number, passiveRate: number): number
	return EventRules.gaugeDecay(
		gauge,
		dt,
		EventsConfig.FEVER_DECAY_BASE,
		passiveRate,
		EventsConfig.FEVER_DECAY_PASSIVE
	)
end

-- 드로퍼 목록의 초당 투하 수. intervals[i] = 투하 간격(초), doubles[i] = 더블 드롭 확률
function EventsConfig.dropsPerSecond(intervals: { number }, doubles: { number }, scale: number): number
	local sum = 0
	for i, iv in intervals do
		sum += (1 + (doubles[i] or 0)) / math.max(0.05, iv * scale)
	end
	return sum
end

-- 버프 배수 (FRENZY·FEVER), 상한 MULT_CAP
function EventsConfig.buffMult(frenzy: boolean, fever: boolean): number
	local mults = {}
	if frenzy then
		table.insert(mults, EventsConfig.FRENZY_MULT)
	end
	if fever then
		table.insert(mults, EventsConfig.FEVER_MULT)
	end
	return EventRules.stackMult(mults, EventsConfig.MULT_CAP)
end

-- 서버 알림 기준 등급 (등급 수가 바뀌어도 비율로)
function EventsConfig.announceTier(maxTier: number): number
	return EventRules.announceLevel(maxTier, EventsConfig.ANNOUNCE_FRACTION, EventsConfig.ANNOUNCE_MIN_TIER)
end

-- 이동 창 제한: history(보낸 시각 목록)에서 window 밖은 지우고, 남은 수 < max면 now를 넣고 true
EventsConfig.rateLimit = EventRules.rateLimit

-- 남은 초 → "0:32"
EventsConfig.clock = EventRules.clock

-- 황금 큐브 1개의 기대 가치 (초당 수입 × 초 단위, 수입 배수 효과만. 큐브 보상은 근사값 인자로)
-- cubeSeconds: TIER RAIN 큐브 1개·JACKPOT 큐브가 수입 몇 초치인지 (시뮬 근사)
function EventsConfig.expectedGoldenSeconds(
	stormSeconds: number,
	rainCubeSeconds: number,
	jackpotSeconds: number
): number
	return EventRules.expectedValue(EventsConfig.REWARDS, function(rw): number
		if rw.id == "cash" then
			return EventsConfig.CASH_SECONDS
		elseif rw.id == "frenzy" then
			return (EventsConfig.FRENZY_MULT - 1) * EventsConfig.FRENZY_SECONDS
		elseif rw.id == "storm" then
			return stormSeconds
		elseif rw.id == "rain" then
			return EventsConfig.RAIN_COUNT * rainCubeSeconds
		end
		return jackpotSeconds
	end)
end

-- 황금 큐브의 총수입 증가율 (잡는 비율 catchRate)
function EventsConfig.goldenIncomeBoost(evSeconds: number, catchRate: number): number
	local cycle = (EventsConfig.GOLDEN_MIN + EventsConfig.GOLDEN_MAX) / 2 + EventsConfig.GOLDEN_LIFE / 2
	return EventRules.incomeBoost(evSeconds, catchRate, cycle)
end

return EventsConfig
