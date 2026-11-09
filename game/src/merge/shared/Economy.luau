--!strict
-- 머지 팩토리(A+ 혼합형) 경제 공식 (순수 — Roblox API 없음, Lune 테스트 대상)
-- 출처: tools/pacing_sim.py MergeGarden 클래스와 같은 공식. 바꾸면 시뮬레이션도 같이 바꾸고
-- docs/13_SIMULATION.md의 보정값(COST_SCALE)을 다시 구한다.

local Economy = {}

-- 등급 사다리 v3 (docs/13 §8): 40등급. 합치기 상한(tierCeiling)이 리버스마다 3씩 올라 12 → 40 (10번째 리버스)
Economy.MAX_TIER = 40
-- 기본 칸과 Lv당 증가 (2026-10-19 "트레이가 더 공격적으로 커지게, 처음은 줄여도 됨"): 50 → Lv8 114칸, 폭 40 → 56
Economy.TRAY_CAP = 50 -- 기본 칸. 트레이 확장 Lv마다 +TRAY_STEP (Economy.trayCap)
Economy.TRAY_STEP = 8
-- 가득 차면 드로퍼가 멈추고(자동 판매로 사라지지 않게), 손으로 떨군 큐브·선물·훔친 큐브는 이만큼 더 들어간다.
-- 그 위로 넘치면 가장 싼 큐브부터 판다 (2026-10-19 "자동 소환해도 계속 사라지니 체감이 어렵다")
Economy.TRAY_OVERFLOW = 10
Economy.MAX_REBIRTH = 14
Economy.CEILING_BASE = 12 -- 리버스 0회일 때 합칠 수 있는 최고 등급
-- 리버스 1회마다 상한 +2 → 14번째(마지막) 리버스에 T40. 2026-10-21 사용자 "환생은 그 티어 큐브를 1~2개 만들 때쯤":
-- 상한 큐브를 만들어야 리버스(canRebirth)로 바꾸면서 +3 → +2 (+3이면 10번째에 T40이 되어 남은 4번이 매번 T40 요구, docs/13 §9.9)
Economy.CEILING_STEP = 2
-- 드로퍼 최대 등급은 상한보다 DROPPER_GAP 아래까지 따라 올라간다 (예전 6 + 리버스: 차이가 판마다 2씩 벌어져 후반 상한 큐브는 사실상 못 만듦)
Economy.DROPPER_GAP = 10
Economy.TIER_GROWTH = 7 -- 드로퍼 등급 업 비용 배수
Economy.REBIRTH_GROWTH = 12 -- 리버스 비용 배수
-- 판마다(리버스 후) 다시 사는 업그레이드(드로퍼 속도·등급·슬롯) 비용 배수 = RUN_GROWTH^리버스. 팩토리 강화는 유지(keep)라 해당 없음.
-- 없으면 후반 판에서 업그레이드를 몇 분 만에 다 사고 리버스만 며칠 기다린다 (docs/13 §8)
Economy.RUN_GROWTH = 3
Economy.MAX_DROPPERS = 8
Economy.START_DROPPERS = 2
Economy.MAX_SPEED_LV = 15
Economy.START_INCUBATORS = 2
Economy.MAX_INCUBATORS = 12
Economy.CORE_QUEUE_CAP = 6
Economy.INCOME_GROWTH = 2.4
Economy.SELL_SECONDS = 10 -- 트레이가 넘쳐 자동 판매될 때 = 그 큐브 수입 10초치
Economy.REBIRTH_MULT = 1.5
Economy.OFFLINE_RATE = 0.1 -- docs/13 §4: 0.5 × 8h면 수입의 80~95%가 방치 수입
Economy.OFFLINE_CAP = 4 * 3600
Economy.CORE_CHANCE = 0.25
Economy.CORE_PAYOUT = 0.6 -- 부화 보상 = 시작 시점 초당 수입 × 타이머 × 이 값 (CORE_PAYOUT_CAP초치까지)
-- 2026-10-21 사용자 "트레이 보상이 주류가 되어야": 코어가 6일째부터 수입의 96~98%였다 (8~12시간 코어 × 0.6).
-- 상한 90초치 → 일반 플레이어 수입 비중 트레이 35~45% · 오프라인 ~40% · 코어 15~25% (pacing_sim, docs/13 §9.8).
-- 코어의 주된 보상은 영구 보너스(bonus)
Economy.CORE_PAYOUT_CAP = 90
Economy.CORE_SELL_SECONDS = 5 -- 대기열이 가득 찰 때 새 코어는 초당 수입 5초치로 판매
-- 보정값 (docs/13). 초반 단계에는 점진 적용(ramp)
-- 2026-10-20 "T40 기준 엔드게임 30일 정도" → 1.1e4. 2026-10-21 코어 보상 상한(CORE_PAYOUT_CAP)으로 현금이 줄어 → 1.5e3
-- (pacing_sim: regular 26일 · engaged 14 · hardcore 12, docs/13 §9.8. 사용자 "종료일이 줄어든 건 괜찮음")
Economy.COST_SCALE = 1.12e3

-- 등급 이름 (NEW TIER 연출·코어 이름). 5개씩 묶음(띠)으로 Config.TIER_BANDS와 같은 순서
Economy.TIER_NAMES = {
	-- BASIC 1~5
	"Snow",
	"Mint",
	"Sky",
	"Lemon",
	"Tangerine",
	-- CANDY 6~10
	"Cherry",
	"Grape",
	"Lagoon",
	"Bubblegum",
	"Lime",
	-- GEM 11~15
	"Topaz",
	"Sapphire",
	"Emerald",
	"Ruby",
	"Amethyst",
	-- METAL 16~20
	"Bronze",
	"Copper",
	"Silver",
	"Gold",
	"Platinum",
	-- NEON 21~25
	"Volt",
	"Laser",
	"Plasma",
	"Pulse",
	"Flare",
	-- SHINE 26~30
	"Glitter",
	"Shimmer",
	"Dazzle",
	"Sparkle",
	"Radiant",
	-- COSMIC 31~35
	"Comet",
	"Nebula",
	"Pulsar",
	"Quasar",
	"Galaxy",
	-- MYTHIC 36~40
	"Phoenix",
	"Dragon",
	"Titan",
	"Eternal",
	"Infinity",
}

export type CoreDef = { seconds: number, bonus: number, name: string }

-- 등급 → 코어 (타이머 초, 영구 수입 보너스). 5등급부터 합치기마다 CORE_CHANCE
Economy.CORES = {
	[5] = { seconds = 120, bonus = 0.002, name = "Pebble" },
	[6] = { seconds = 300, bonus = 0.003, name = "Shard" },
	[7] = { seconds = 600, bonus = 0.005, name = "Crystal" },
	[8] = { seconds = 1200, bonus = 0.008, name = "Gem" },
	[9] = { seconds = 2700, bonus = 0.012, name = "Prism" },
	[10] = { seconds = 5400, bonus = 0.02, name = "Nova" },
	[11] = { seconds = 10800, bonus = 0.03, name = "Star" },
	[12] = { seconds = 28800, bonus = 0.06, name = "Cosmic" },
} :: { [number]: CoreDef }
-- 13등급부터: 8시간 + 등급당 30분(최대 12시간), 보너스 0.06 + 등급당 0.01. 이름은 등급 이름
for tier = 13, Economy.MAX_TIER do
	Economy.CORES[tier] = {
		seconds = math.min(43200, 28800 + 1800 * (tier - 12)),
		bonus = 0.06 + 0.01 * (tier - 12),
		name = Economy.TIER_NAMES[tier],
	}
end

function Economy.cubeIncome(tier: number): number
	return Economy.INCOME_GROWTH ^ (tier - 1)
end

function Economy.sellValue(tier: number, mult: number): number
	return Economy.cubeIncome(tier) * Economy.SELL_SECONDS * mult
end

function Economy.dropInterval(speedLv: number): number
	return math.max(0.4, 2.0 * 0.88 ^ speedLv)
end

-- 리버스 횟수에 따른 드로퍼 최대 등급
function Economy.tierCap(rebirths: number): number
	return math.min(math.max(6 + rebirths, Economy.tierCeiling(rebirths) - Economy.DROPPER_GAP), Economy.MAX_TIER - 1)
end

-- 리버스 횟수에 따른 합치기 상한: 이 등급끼리는 더 합쳐지지 않는다. 리버스마다 새 등급 2개가 열린다
function Economy.tierCeiling(rebirths: number): number
	return math.min(Economy.CEILING_BASE + Economy.CEILING_STEP * rebirths, Economy.MAX_TIER)
end

function Economy.multiplier(rebirths: number, coreBonus: number, passMult: number): number
	return Economy.REBIRTH_MULT ^ rebirths * (1 + coreBonus) * passMult
end

-- 리버스 러시 (2026-10-19, 사용자 요청 "환생 뒤 초반부는 빠르게"): 리버스 직후에는 수입 xRUSH_MULT,
-- 이번 판 최고 등급이 지난 판 상한 - RUSH_GAP에 닿으면 끝. 드로퍼도 1등급이 아니라 startTier에서 시작
Economy.RUSH_MULT = 3
Economy.RUSH_GAP = 2
Economy.START_TIER_MAX = 8

function Economy.rushUntil(rebirths: number): number
	if rebirths <= 0 then
		return 0
	end
	return Economy.tierCeiling(rebirths - 1) - Economy.RUSH_GAP
end

-- runBest = 이번 판 최고 등급
function Economy.rushMult(rebirths: number, runBest: number): number
	return if runBest < Economy.rushUntil(rebirths) then Economy.RUSH_MULT else 1
end

-- 낮은 등급 보정 (2026-10-19 사용자 지적): 드로퍼가 높은 등급을 떨어뜨리면 낮은 등급 큐브는 손 DROP으로만 나와
-- 그 등급의 변이 도감 칸을 채우기 더 어려워진다 → 드로퍼 최저 등급보다 낮은 큐브는 변이 확률을 등급 차 × 50% 더(최대 x4)
Economy.LOW_TIER_LUCK_STEP = 0.5
Economy.LOW_TIER_LUCK_MAX = 4
function Economy.lowTierLuck(tier: number, dropperMin: number): number
	return math.min(Economy.LOW_TIER_LUCK_MAX, 1 + Economy.LOW_TIER_LUCK_STEP * math.max(0, dropperMin - tier))
end

function Economy.startTier(rebirths: number): number
	return math.clamp(1 + rebirths, 1, math.min(Economy.START_TIER_MAX, Economy.tierCap(rebirths)))
end

-- 리버스 횟수에 따른 판 업그레이드 비용 배수 (rebirths 생략 = 0)
function Economy.runScale(rebirths: number?): number
	return Economy.RUN_GROWTH ^ (rebirths or 0)
end

-- 보정값을 처음 몇 단계에 걸쳐 서서히 적용: 첫 세션은 빠르게, 후반은 길게 (docs/13 §5)
local function ramp(index: number, fullAt: number): number
	return Economy.COST_SCALE ^ math.min(1, index / fullAt)
end

-- slotIndex는 1부터 (뒤 슬롯일수록 속도 업 비용 1.3배씩)
function Economy.speedCost(slotIndex: number, speedLv: number, rebirths: number?): number
	return 10 * 1.55 ^ speedLv * 1.3 ^ (slotIndex - 1) * ramp(speedLv, 6) * Economy.runScale(rebirths)
end

function Economy.tierCost(currentTier: number, rebirths: number?): number
	return 40 * Economy.TIER_GROWTH ^ (currentTier - 1) * ramp(currentTier - 1, 3) * Economy.runScale(rebirths)
end

function Economy.slotCost(currentCount: number, rebirths: number?): number
	local n = currentCount - Economy.START_DROPPERS
	return 300 * 9 ^ n * ramp(n, 2) * Economy.runScale(rebirths)
end

function Economy.incubatorCost(currentCount: number): number
	local n = currentCount - Economy.START_INCUBATORS
	return 150 * 3.2 ^ n * ramp(n, 2)
end

-- 업그레이드 v2 (docs/14 §3.2): 공장·코어 업그레이드. keep = 리버스 후에도 유지
export type UpgradeDef = {
	max: number,
	base: number,
	growth: number,
	rampAt: number,
	keep: boolean,
	milestones: { number }?,
}
Economy.UPGRADES = {
	-- 2026-10-20 사용자 "팩토리 강화 항목은 환생해도 유지": polish·lucky도 keep (판 비용 배수 없음)
	-- TAP POWER는 삭제 (2026-10-20 사용자: 트레이 한도 때문에 의미 없음). DROP 버튼은 1등급 고정
	polish = { max = 20, base = 500, growth = 4, rampAt = 4, keep = true, milestones = { 10, 20 } },
	lucky = { max = 10, base = 2000, growth = 6, rampAt = 3, keep = true },
	hatch = { max = 10, base = 1000, growth = 5, rampAt = 3, keep = true },
	-- 트레이 확장 (2026-10-18 사용자 요청): 칸 +5, 벽도 넓어짐. 수입이 칸 수에 비례해서 비싸게
	tray = { max = 8, base = 5000, growth = 9, rampAt = 3, keep = true },
} :: { [string]: UpgradeDef }
Economy.UPGRADE_ORDER = { "polish", "lucky", "hatch", "tray" }
Economy.SPEED_MILESTONES = { 5, 10, 15 }

-- keep = false 업그레이드는 리버스마다 초기화되므로 판 비용 배수(runScale)를 받는다
function Economy.upgradeCost(id: string, lv: number, rebirths: number?): number?
	local u = Economy.UPGRADES[id]
	if not u or lv >= u.max then
		return nil
	end
	local scale = if u.keep then 1 else Economy.runScale(rebirths)
	return u.base * u.growth ^ lv * ramp(lv, u.rampAt) * scale
end

-- 트레이 칸 수와 내부 폭 (Lv 0 = 50칸 40 studs, Lv 8 = 114칸 56 studs: 앞쪽 시점 비컨 자리를 남긴다)
function Economy.trayCap(lv: number?): number
	return Economy.TRAY_CAP + Economy.TRAY_STEP * (lv or 0)
end
function Economy.trayWidth(lv: number?): number
	return 40 + 2 * (lv or 0)
end

-- 배트 (2026-10-18 사용자 요청): 휘둘러 내 트레이 큐브를 밀친다. 강화는 젬, 최대 Lv은 도감 진행도로 열림
Economy.BAT_STATS = { "range", "power", "speed", "move" } -- move = 이동 속도 (배트 탭, docs/22)
Economy.BAT_MAX = 10
function Economy.batRange(lv: number): number
	return 9 + 1.5 * lv -- 캐릭터 중심에서 studs
end
function Economy.batPower(lv: number): number
	return 45 + 12 * lv -- 밀어내는 속도 (studs/s)
end
function Economy.batCooldown(lv: number): number
	return 0.9 * 0.92 ^ lv -- 초
end
function Economy.moveSpeed(lv: number): number
	return 16 + 1.2 * lv -- 걷기 속도 (기본 16, 최대 28)
end
-- 훔친 큐브를 들고 걷는 속도: 평소의 80% (2026-10-19 사용자 "속도 올려도 될듯, 비슷한 레벨 기준 80%", 예전 32%). 내 최고 등급보다 높은 큐브면 1등급마다 12%씩 더 느려짐 (최소 35%)
Economy.CARRY_FACTOR = 0.8
function Economy.carrySpeed(walk: number, tier: number, best: number): number
	local over = math.max(0, tier - best)
	return walk * Economy.CARRY_FACTOR * math.max(0.35, 1 - 0.12 * over)
end
-- 들면 느려지는 비율 (0.2 = 20% 느려짐). 훔치기 목록에 큐브마다 보여 준다
function Economy.carrySlow(tier: number, best: number): number
	return 1 - Economy.carrySpeed(1, tier, best)
end
-- 다음 Lv 가격 (젬). 최대면 nil
function Economy.batCost(lv: number): number?
	if lv >= Economy.BAT_MAX then
		return nil
	end
	return math.floor(10 * 1.45 ^ lv + 0.5)
end
-- 도감 발견 수로 열리는 최대 Lv: 처음 3, 발견 8개마다 +1
function Economy.batCap(found: number): number
	return math.min(Economy.BAT_MAX, 3 + found // 8)
end
-- 다음 Lv을 열려면 필요한 발견 수
function Economy.batFindsFor(lv: number): number
	return (lv + 1 - 3) * 8
end

-- 광택: +10%/Lv, 10Lv마다 ×2
function Economy.polishMult(lv: number): number
	return (1 + 0.1 * lv) * 2 ^ (lv // 10)
end

-- 행운: 합치기가 2단계 뛸 확률
function Economy.luckyChance(lv: number): number
	return 0.02 * lv
end

-- 탭 파워: DROP 버튼 큐브 등급
function Economy.tapTier(lv: number): number
	return 1 + lv
end

-- 부화 속도: 타이머 배율
function Economy.hatchScale(lv: number): number
	return 1 - 0.05 * lv
end

-- 더블 드롭: 속도 5·10·15Lv마다 +15%
function Economy.doubleDropChance(speedLv: number): number
	return 0.15 * (speedLv // 5)
end

-- 다음 마일스톤 (없으면 nil)
function Economy.nextMilestone(milestones: { number }?, lv: number): number?
	if milestones then
		for _, m in milestones do
			if lv < m then
				return m
			end
		end
	end
	return nil
end

-- 섞기 (docs/14 §5): 트레이를 등급순으로 다시 놓아 큰 큐브가 막은 합치기를 푼다.
-- 무료 충전은 30분마다 1회, 최대 3회까지 쌓임(접속 안 해도). 유료 충전은 상한 없음.
Economy.SHUFFLE_INTERVAL = 30 * 60
Economy.SHUFFLE_FREE_CAP = 3
Economy.SHUFFLE_START = 1
Economy.SHUFFLE_PACK = 3 -- 개발자 상품 1회 구매당

-- 큐브 훔치기 (docs/22): 2분마다 1회 충전, 최대 3회 모임. 상품 1개 = 3회 (충전 상한과 별개로 쌓임)
Economy.STEAL_INTERVAL = 2 * 60
Economy.STEAL_FREE_CAP = 3
Economy.STEAL_START = 1
Economy.STEAL_PACK = 3
Economy.STEAL_RANGE = 9 -- 큐브까지 손이 닿는 거리 (큐브 반지름 더함, 클라 자동 표시용)
-- 훔치기 목록 (2026-10-19 "근처 큐브 10개 정도 띄우고 골라서 가져가기, 큐브별 이동속도 감소량도")
Economy.STEAL_LIST = 10
Economy.STEAL_PICK_RANGE = 20 -- 목록에 들어가는 거리 (큐브 반지름 더함)
-- 훔치기 보호: 피해자의 가장 높은 등급 N개(서로 다른 등급)는 못 훔친다 (2026-10-21 사용자 "상위 2개까지만", 예전 1개)
Economy.STEAL_PROTECT_TOP = 2
-- 연속 털림 보호 (2026-10-25 사용자 "3분 이내 연속으로 2번 털리면 5분간 잠금으로 보호"): 끝까지 털린 것만 센다(되찾은 건 아님)
Economy.STEAL_LOCK_WINDOW = 180
Economy.STEAL_LOCK_COUNT = 2
Economy.STEAL_LOCK_SECONDS = 300
-- tiers: 피해자 큐브 등급들 → 이 등급 이상은 보호
function Economy.stealProtectedFrom(tiers: { number }): number
	local distinct: { [number]: boolean } = {}
	local list: { number } = {}
	for _, t in tiers do
		if not distinct[t] then
			distinct[t] = true
			table.insert(list, t)
		end
	end
	if #list == 0 then
		return math.huge
	end
	table.sort(list, function(a, b)
		return a > b
	end)
	return list[math.min(Economy.STEAL_PROTECT_TOP, #list)]
end
Economy.CARRY_JUMP = 1.5 -- 들고 있을 때 점프 높이 (기본 7.2)
Economy.CARRY_TIMEOUT = 150 -- 이 안에 내 공장에 못 가져가면 주인에게 돌아감
-- 오라 단계별 배트 넉백 저항 (2026-10-19): 단계마다 5%, 12단계(Divine) 60%
Economy.AURA_RESIST_STEP = 0.05
function Economy.auraResist(tier: number): number
	return math.clamp(tier, 0, 12) * Economy.AURA_RESIST_STEP
end
Economy.KNOCK_IMMUNE = 1.5 -- 배트에 맞은 뒤 다시 맞지 않는 시간

-- (무료 횟수, 마지막 충전 기준 시각) → 지금 시각 기준으로 갱신. 상한이면 기준 시각을 지금으로 붙잡아,
-- 쓰는 순간부터 다음 30분이 시작되게 한다.
-- interval·cap을 넘기면 그 규칙으로 (기본 SHUFFLE_INTERVAL·SHUFFLE_FREE_CAP)
function Economy.shuffleRegen(
	free: number,
	lastAt: number,
	now: number,
	interval: number?,
	cap: number?
): (number, number)
	local every = interval or Economy.SHUFFLE_INTERVAL
	local most = cap or Economy.SHUFFLE_FREE_CAP
	if free >= most then
		return free, now
	end
	local gained = (now - lastAt) // every
	if gained <= 0 then
		return free, lastAt
	end
	local f = math.min(most, free + gained)
	if f >= most then
		return f, now
	end
	return f, lastAt + gained * every
end

-- 비용 배율(COST_SCALE)을 처음 다섯 번은 1/6 ~ 5/6만 적용하고 여섯 번째부터 전부.
-- 2026-10-18: 1/3·2/3 (첫 리버스 $24B까지 한 시간 막힘). 2026-10-20 사용자 "성장 체감이 느림, 빠른 도파민":
-- 램프 3 → 6. 리버스 1~3번째 (온라인 분) 6 / 24 / 50 → 4 / 9 / 21, regular 엔드게임 73 → 75일 (docs/13 §9.6)
Economy.REBIRTH_RAMP = 6
-- 2026-10-21: 2e5 → 2e4. 상한 큐브 조건이 생겨 돈은 그 즈음 모이면 된다 (시뮬: 돈 때문에 기다림 최대 ~2분)
function Economy.rebirthCost(rebirths: number): number
	return 2e4
		* Economy.REBIRTH_GROWTH ^ rebirths
		* Economy.COST_SCALE ^ math.min(1, (rebirths + 1) / Economy.REBIRTH_RAMP)
end

-- 리버스 조건: 이번 판에 합치기 상한 등급 큐브를 만들었을 것 (+ 비용은 서버가 따로 확인)
function Economy.canRebirth(rebirths: number, runBest: number): boolean
	return rebirths < Economy.MAX_REBIRTH and runBest >= Economy.tierCeiling(rebirths)
end

-- 트레이 수입/초 (counts[t] = 등급 t 큐브 수, 일반 변이 기준. 변이 포함은 trayIncomeOf)
function Economy.trayIncome(counts: { [number]: number }, mult: number): number
	local sum = 0
	for tier, n in counts do
		sum += n * Economy.cubeIncome(tier)
	end
	return sum * mult
end

------------------------------------------------------------------------
-- 변이 (docs/16): 큐브가 생길 때 낮은 확률로 특별한 재질 → 수입 배수.
-- 순서 = 등급(rank). 1번은 일반. 저장·Attribute에는 rank가 아니라 id 문자열을 쓴다(순서를 바꿔도 안전).
------------------------------------------------------------------------
export type Variant = {
	id: string,
	mult: number, -- 큐브 수입 배수
	chance: number, -- 합치기로 생길 때 확률
	dropChance: number, -- 드로퍼·DROP으로 떨어질 때 확률
	gems: number, -- (등급, 변이) 첫 발견 보상 젬
}
Economy.VARIANTS = {
	{ id = "Normal", mult = 1, chance = 0, dropChance = 0, gems = 0 },
	-- 확률·배수: docs/15 조사 권장값(흔한 변이는 작게, 드문 변이는 크게). 투하 확률은 합치기의 1/5
	-- 사다리 확장(2026-10-18): 아래 4단은 조금 더 드물게, 위에 Cosmic·Divine을 얹어 "더 드문 것"이 항상 남게 (docs/16 §1)
	{ id = "Metallic", mult = 1.5, chance = 0.025, dropChance = 0.005, gems = 2 }, -- 1/40
	{ id = "Neon", mult = 3, chance = 0.008, dropChance = 0.0016, gems = 5 }, -- 1/125
	{ id = "Rainbow", mult = 8, chance = 0.0018, dropChance = 0.00036, gems = 10 }, -- 1/550
	{ id = "Galaxy", mult = 25, chance = 0.00025, dropChance = 0.00005, gems = 25 }, -- 1/4,000
	{ id = "Cosmic", mult = 70, chance = 0.0001, dropChance = 0.00002, gems = 60 }, -- 1/10,000
	{ id = "Divine", mult = 200, chance = 0.00002, dropChance = 0.000004, gems = 150 }, -- 1/50,000
} :: { Variant }
Economy.NORMAL = 1
Economy.TOAST_VARIANT = #Economy.VARIANTS - 1 -- 이 등급(Cosmic) 이상은 서버 전체 토스트

function Economy.variantIndex(id: string?): number
	for i, v in Economy.VARIANTS do
		if v.id == id then
			return i
		end
	end
	return Economy.NORMAL
end

function Economy.variantMult(v: number): number
	local def = Economy.VARIANTS[v]
	return if def then def.mult else 1
end

-- r = [0,1) 균등 난수. 가장 드문 변이부터 누적 확률로 판정. luck은 Studio 디버그용 확률 배율(기본 1)
function Economy.rollVariant(r: number, onDrop: boolean, luck: number?): number
	local acc = 0
	for i = #Economy.VARIANTS, 2, -1 do
		local def = Economy.VARIANTS[i]
		acc += (if onDrop then def.dropChance else def.chance) * (luck or 1)
		if r < acc then
			return i
		end
	end
	return Economy.NORMAL
end

-- 합치기 결과 변이 = max(새로 굴린 변이, 이어받는 변이).
--   이어받기: 둘 중 좋은 변이가 한 단계 약해져서 남는다(Divine → Cosmic → Galaxy → … → Metallic → 일반).
--   융합: 같은 변이(일반 제외) 둘이 합쳐지면 한 단계 올라간다(맨 위 Divine끼리는 Divine).
-- "더 좋은 변이를 그대로 유지"하면 12등급 큐브 하나가 2천 번 넘는 합치기를 거치면서 거의 전부 최상위 변이가 되어
-- 희귀함과 경제가 같이 무너진다(docs/16 §2).
function Economy.inheritVariant(a: number, b: number): number
	if a == b and a > Economy.NORMAL then
		return math.min(a + 1, #Economy.VARIANTS)
	end
	return math.max(math.max(a, b) - 1, Economy.NORMAL)
end

function Economy.mergeVariant(a: number, b: number, rolled: number): number
	return math.max(rolled, Economy.inheritVariant(a, b))
end

-- 큐브 하나의 초당 수입 (변이 포함, 공통 배수 제외)
function Economy.cubeValue(tier: number, v: number): number
	return Economy.cubeIncome(tier) * Economy.variantMult(v)
end

-- 트레이 수입/초: cubes = { {tier, variant} } (변이 배수를 큐브마다 곱함)
function Economy.trayIncomeOf(cubes: { { tier: number, variant: number } }, mult: number): number
	local sum = 0
	for _, c in cubes do
		sum += Economy.cubeValue(c.tier, c.variant)
	end
	return sum * mult
end

-- 같은 등급 큐브를 무작위로 짝지어 합친다고 보고 등급별 변이 분포를 차례로 구한다(첫 등급 = 투하 분포).
-- 반환: 등급별 평균 변이 배수 목록. 맨 끝 값이 시뮬레이션(tools/pacing_sim.py VARIANT_MEAN)과 같은 기대 배수.
function Economy.variantMeanByTier(tiers: number): { number }
	local n = #Economy.VARIANTS
	local function rollDist(onDrop: boolean): { number }
		local p = table.create(n, 0)
		local rest = 1
		for i = 2, n do
			local def = Economy.VARIANTS[i]
			p[i] = if onDrop then def.dropChance else def.chance
			rest -= p[i]
		end
		p[1] = rest
		return p
	end
	local merge = rollDist(false)
	local d = rollDist(true)
	local out = {}
	for t = 1, tiers do
		local mean = 0
		for i = 1, n do
			mean += d[i] * Economy.variantMult(i)
		end
		out[t] = mean
		local nextD = table.create(n, 0)
		for a = 1, n do
			for b = 1, n do
				local inh = Economy.inheritVariant(a, b)
				for k = 1, n do
					local v = math.max(inh, k)
					nextD[v] += d[a] * d[b] * merge[k]
				end
			end
		end
		d = nextD
	end
	return out
end

-- 저장 트레이 항목: 일반 큐브는 예전처럼 숫자(등급), 변이 큐브는 { t = 등급, v = 변이 id }
function Economy.packCube(tier: number, v: number): any
	if v == Economy.NORMAL then
		return tier
	end
	return { t = tier, v = Economy.VARIANTS[v].id }
end

function Economy.unpackCube(entry: any): (number?, number)
	if type(entry) == "number" then
		return entry, Economy.NORMAL
	elseif type(entry) == "table" and type(entry.t) == "number" then
		return entry.t, Economy.variantIndex(entry.v)
	end
	return nil, Economy.NORMAL
end

------------------------------------------------------------------------
-- 도감 (docs/16 §3): (등급 × 일반 아닌 변이) 칸. data.variants["7:Rainbow"] = true
------------------------------------------------------------------------
function Economy.codexKey(tier: number, v: number): string
	return `{tier}:{Economy.VARIANTS[v].id}`
end

function Economy.codexTotal(): number
	return Economy.MAX_TIER * (#Economy.VARIANTS - 1)
end

-- 발견 칸 수 마일스톤 → 젬. count가 전체 칸보다 크면 "전부 모으기"로 줄여 쓴다(MAX_TIER가 바뀌어도 동작)
Economy.CODEX_MILESTONES = {
	{ count = 1, gems = 10 },
	{ count = 3, gems = 10 },
	{ count = 5, gems = 15 },
	{ count = 10, gems = 25 },
	{ count = 15, gems = 30 },
	{ count = 20, gems = 40 },
	{ count = 30, gems = 60 },
	{ count = 40, gems = 80 },
	{ count = 60, gems = 100 },
	{ count = 80, gems = 120 },
	{ count = 120, gems = 150 },
	{ count = 160, gems = 200 },
	{ count = 200, gems = 250 },
	{ count = math.huge, gems = 400 }, -- 전부 (40등급 × 6변이 = 240칸, 마지막 칸들은 Divine)
}

function Economy.milestoneCount(i: number): number
	return math.min(Economy.CODEX_MILESTONES[i].count, Economy.codexTotal())
end

-- (이미 받은 마일스톤 수, 발견 수) → (새로 받은 뒤 마일스톤 수, 지급할 젬)
function Economy.codexReward(claimed: number, found: number): (number, number)
	local gems = 0
	local i = claimed
	while i < #Economy.CODEX_MILESTONES and found >= Economy.milestoneCount(i + 1) do
		i += 1
		gems += Economy.CODEX_MILESTONES[i].gems
	end
	return i, gems
end

-- 꾸미기 해금: codex 칸 수 조건(전체 칸 수로 상한) 또는 젬 구매로 소유
-- exclusive: 상점 전용(스타터 팩·Collector 패스) → 받은 경우에만
function Economy.cosmeticUnlocked(
	codexReq: number?,
	gemsPrice: number?,
	found: number,
	owned: boolean,
	exclusive: boolean?
): boolean
	if owned then
		return true
	end
	if exclusive then
		return false
	end
	if codexReq then
		return found >= math.min(codexReq, Economy.codexTotal())
	end
	return gemsPrice == nil -- 조건 없음 = 기본 꾸미기
end

-- scale: 부화 시간 배율 (HATCH 강화, Economy.hatchScale). 짧아진 만큼 보상도 줄고, CORE_PAYOUT_CAP초치까지
function Economy.corePayout(incomePerSec: number, tier: number, scale: number?): number
	local core = Economy.CORES[tier]
	if not core then
		return 0
	end
	local seconds = math.min(core.seconds * (scale or 1) * Economy.CORE_PAYOUT, Economy.CORE_PAYOUT_CAP)
	return incomePerSec * seconds
end

function Economy.offlineEarnings(incomePerSec: number, awaySeconds: number, capSeconds: number?): number
	local cap = capSeconds or Economy.OFFLINE_CAP
	return incomePerSec * Economy.OFFLINE_RATE * math.clamp(awaySeconds, 0, cap)
end

-- 같은 등급 두 개가 합쳐질 수 있는가 (상한 등급끼리는 합쳐지지 않음 — Cubika 규칙).
-- ceiling 생략 시 MAX_TIER, 게임에서는 Economy.tierCeiling(rebirths)
function Economy.canMerge(tierA: number, tierB: number, ceiling: number?): boolean
	return tierA == tierB and tierA < (ceiling or Economy.MAX_TIER)
end

-- 1초 안 연속 합치기 콤보 배수 (Cubika COMBO 규칙: 1 + 0.5 × (콤보-1), 최대 ×3)
function Economy.comboMultiplier(combo: number): number
	return math.min(1 + 0.5 * math.max(0, combo - 1), 3)
end

return Economy
