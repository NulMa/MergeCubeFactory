--!strict
-- 접속 선물·일일 퀘스트의 Merge 수치 (docs/23_DAILY.md). 규칙은 core/shared/Daily (Daily.new로 주입).
-- 서버(server/Daily)와 테스트(tests/merge/Daily.spec)가 쓴다.
-- 하루 = UTC 날짜. 날짜가 바뀌면 오늘 플레이 시간·받은 선물·퀘스트가 새로 시작한다.
-- 선물은 무료 랜덤(유료 랜덤 아님). 젬은 적게 (사용자 요청 2026-10-19 "잼 보상도 줄이는쪽으로").

local CoreDaily = require(script.Parent.Parent.Core.Daily)

local Daily = {}

-- 작은 선물: 오늘 플레이 3분마다 1개, 하루 최대 20개. 대부분 적은 현금, 낮은 확률로 훔치기·황금 큐브
Daily.SMALL_EVERY = 180
Daily.SMALL_MAX = 20
Daily.SMALL_CASH_SECONDS = 20 -- 현금 = 초당 수입 × 20초
Daily.SMALL_CASH_MIN = 50
Daily.SMALL_TABLE = {
	{ id = "steal", weight = 5 },
	{ id = "golden", weight = 5 },
	{ id = "cash", weight = 90 },
}

-- 큰 선물: 오늘 플레이 15·30·45·60분. 훔치기·황금 큐브·젬 중 랜덤
Daily.BIG_AT = { 900, 1800, 2700, 3600 }
Daily.BIG_TABLE = {
	{ id = "steal", weight = 35 },
	{ id = "golden", weight = 30 },
	{ id = "gems_s", weight = 25 },
	{ id = "gems_l", weight = 10 },
}
Daily.BIG_STEAL = 2
Daily.GEMS_S = 3
Daily.GEMS_L = 8

-- 일일 퀘스트: 날짜 시드로 모든 서버가 같은 3개. 하나에 젬 2 + 현금(수입 60초), 셋 다 하면 젬 5
Daily.QUEST_COUNT = 3
Daily.QUEST_GEMS = 2
Daily.QUEST_CASH_SECONDS = 60
Daily.QUEST_CASH_MIN = 200
Daily.BONUS_GEMS = 5

-- scale: 진척(리버스 수)에 따라 목표가 커지는 퀘스트 (2026-10-20 "일일 퀘스트 목표를 진행도에 맞게").
-- 합치기·배트·변이·강화는 리버스할수록 빨라지므로 목표 × (1 + 0.35 × 리버스, 최대 10회분)
-- maxLevel: 이 리버스 수를 넘으면 뽑지 않는다 (2026-10-21 사용자 "높은 레벨이면 안 뜨도록":
-- 강화는 R5쯤 거의 다 사서 후반엔 하루 1~6번뿐이라 "업그레이드 8번"을 못 깸)
export type Quest = CoreDaily.Quest
Daily.QUESTS = {
	{ id = "merge", target = 300, text = "Merge cubes", scale = true },
	{ id = "tap", target = 60, text = "Drop cubes by hand" },
	{ id = "bat", target = 40, text = "Hit cubes with the bat", scale = true },
	{ id = "upgrade", target = 8, text = "Buy upgrades", maxLevel = 5 },
	{ id = "hatch", target = 2, text = "Hatch cores" },
	{ id = "golden", target = 2, text = "Catch golden cubes" },
	{ id = "variant", target = 5, text = "Make variant cubes", scale = true },
	{ id = "pet", target = 3, text = "Hatch pet eggs" },
} :: { Quest }

Daily.QUEST_SCALE_STEP = 0.35
Daily.QUEST_SCALE_MAX_REBIRTHS = 10
-- 7일 출석 (2026-10-20 "재방문 장치"): 접속한 날마다 한 칸씩 (빠진 날이 있어도 초기화하지 않음), 7일째 뒤엔 1일째부터.
-- 보상은 고정 (랜덤 없음). cash = 기본 수입 × 초, shards = 최고 등급 합치기 n번치
export type LoginReward = CoreDaily.LoginReward
Daily.LOGIN = {
	{ kind = "cash", amount = 300, text = "CASH x5 MIN" },
	{ kind = "shards", amount = 40, text = "SHARDS" },
	{ kind = "gems", amount = 3, text = "3 GEMS" },
	{ kind = "steal", amount = 2, text = "2 STEALS" },
	{ kind = "cash", amount = 900, text = "CASH x15 MIN" },
	{ kind = "gems", amount = 5, text = "5 GEMS" },
	{ kind = "boss", amount = 10, text = "10 BOSS COINS + 8 GEMS" },
} :: { LoginReward }
Daily.LOGIN_DAY7_GEMS = 8
Daily.LOGIN_CASH_MIN = 500

local rules = CoreDaily.new({
	smallEvery = Daily.SMALL_EVERY,
	smallMax = Daily.SMALL_MAX,
	smallTable = Daily.SMALL_TABLE,
	bigAt = Daily.BIG_AT,
	bigTable = Daily.BIG_TABLE,
	questCount = Daily.QUEST_COUNT,
	quests = Daily.QUESTS,
	scaleStep = Daily.QUEST_SCALE_STEP,
	scaleMaxLevel = Daily.QUEST_SCALE_MAX_REBIRTHS,
	login = Daily.LOGIN,
})

-- 규칙 (core/shared/Daily). rebirths = 진척 레벨
Daily.questTarget = rules.questTarget
Daily.nextLogin = rules.nextLogin -- 지난 출석 칸(0 = 처음) → 오늘 칸
Daily.quest = rules.quest
Daily.dayOf = rules.dayOf
Daily.rollSmall = rules.rollSmall -- r: 0..1 난수
Daily.rollBig = rules.rollBig
Daily.smallReady = rules.smallReady -- 지금 받을 수 있는 작은 선물 수
Daily.smallNextIn = rules.smallNextIn -- 다음 작은 선물까지 남은 초 (오늘 몫을 다 쌓았으면 nil)
Daily.bigReady = rules.bigReady
Daily.bigNextIn = rules.bigNextIn
Daily.questsFor = rules.questsFor -- 날짜 시드로 퀘스트 3개 (서로 다름). 같은 날이면 어느 서버에서든 같다

function Daily.smallCash(income: number): number
	return CoreDaily.incomeReward(income, Daily.SMALL_CASH_SECONDS, Daily.SMALL_CASH_MIN)
end

function Daily.questCash(income: number): number
	return CoreDaily.incomeReward(income, Daily.QUEST_CASH_SECONDS, Daily.QUEST_CASH_MIN)
end

return Daily
