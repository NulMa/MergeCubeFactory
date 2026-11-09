--!strict
-- 보스 레이드 (2026-10-20 사용자 결정: 보스 큐브 + 서버 공동 목표를 하나로). 순수 규칙, Lune 테스트 대상.
--   주기마다 서버 전체에 참여 여부를 묻고(JOIN), 누른 사람은 바로 하늘 위 별도 전장으로 옮겨 보스를 배트로 잡는다.
--   데미지는 "맞힌 횟수(타수)": 한 대 = 1, 크리티컬 = 2. 공격 간격은 각자 배트 SPEED 강화를 따른다
--   (2026-10-20 사용자 "레이드시 공격속도는 각 개인의 업그레이드를 따라가도록", "크리티컬 5% + 높은 등급 배트일수록 ↑, 체력 -2").
--   보스는 간단한 패턴 두 가지(바닥 충격파 = 점프로 피함, 낙하 표시 = 비켜서 피함). 맞으면 밀려나고 잠깐 못 때림.
--   레이드 중 참여자끼리(그리고 참여자에게) 배트 넉백·훔치기는 막는다.
--   잡으면: 참여자(최소 타수 이상)에게만 보스 코인 + 잠시 수입 x2 (2026-10-20 사용자 "보상·수입X2는 참여한 사람에게만").
--   보스 코인으로 영구 강화: 수입 %, 이동 속도 %, 넉백 저항 %. 코인은 Robux로 팔지 않는다.

local Raid = {}

-- 일정 (초)
Raid.FIRST = 4 * 60 -- 서버가 열리고 첫 레이드 초대까지
Raid.EVERY = 12 * 60 -- 레이드가 끝나고 다음 초대까지
Raid.INVITE = 20 -- 참여 받는 시간
Raid.EARLY_START = 3 -- 모두 답하면 마지막 답 이만큼 뒤 시작 (전장 도착·둘러보기)
Raid.FIGHT = 90 -- 제한 시간
Raid.RESULT = 6 -- 결과 화면 뒤 집으로

-- 보스 체력 = 타수. 참여자 수에 따라 조금씩 (2026-10-20 사용자 "인원수가 2배가 된다고 체력이 2배가 되면 안됨")
--   40 × n^0.8 → 1명 40, 2명 70, 4명 121, 8명 211 (2배 인원 = 체력 1.74배)
--   (2026-10-21 리뷰: 0.6이면 8~20명이 5~25초에 잡아 패턴을 거의 못 봄)
Raid.MIN_HP = 40
Raid.HP_EXP = 0.8
function Raid.hp(players: number): number
	return math.floor(Raid.MIN_HP * math.max(1, players) ^ Raid.HP_EXP + 0.5)
end

-- 타격: 간격은 각자 배트 쿨다운(Economy.batCooldown, 0레벨 0.9초). 사거리는 넉넉하게 (헛스윙 줄이기)
Raid.HIT_GAP = 0.9 -- 0레벨 배트 (테스트 기준)
Raid.REACH = 11 -- 캐릭터 중심 ~ 보스 표면 (studs, 수평). 0레벨 배트 사거리 9 + 지연 여유
Raid.REACH_UP = 8 -- 높이 차 (보스 반지름 + 이만큼). 덮치기로 높이 뜬 보스·날기 핵 막기
Raid.MAX_ABOVE = 40 -- 전장 바닥보다 이만큼 높이 떠 있으면 가장자리로 되돌림

-- 크리티컬: 기본 5% + 배트 스킨 등급(도감·젬으로 여는 배트일수록 ↑). 크리티컬 한 대 = 체력 2
Raid.CRIT_BASE = 0.05
Raid.CRIT_DAMAGE = 2
Raid.CRIT_BONUS = {
	bat_aluminum = 0,
	bat_wood = 0.01, -- 도감 3
	bat_fish = 0.02, -- 도감 8
	bat_baguette = 0.03, -- 도감 18
	bat_neon = 0.04, -- 도감 25
	bat_pan = 0.04, -- 90젬
	bat_cane = 0.05, -- 도감 35
	bat_gold = 0.05, -- 120젬
	bat_crystal = 0.06, -- 도감 50
	bat_chicken = 0.07, -- 180젬
	bat_hammer = 0.08, -- 도감 70
	bat_rainbow = 0.1, -- 도감 100
} :: { [string]: number }
function Raid.critChance(batId: string?): number
	return Raid.CRIT_BASE + (if batId then Raid.CRIT_BONUS[batId] or 0 else 0)
end
Raid.STUN = 2.5 -- 패턴에 맞으면 못 때리는 시간 (2026-10-21 리뷰: 1.5초면 맞는 것 ≈ 피하는 것)
Raid.STUN_RESIST = 0.6 -- RAIDER GUARD 저항만큼 경직도 줄인다: 경직 × (1 − 0.6 × 저항)
function Raid.stunFor(resist: number): number
	return Raid.STUN * (1 - Raid.STUN_RESIST * math.clamp(resist, 0, 1))
end
Raid.KNOCK_SPEED = 38 -- 패턴에 맞았을 때 수평 속도 (섬 밖으로 날아가지 않게, Studio 2026-10-20: 70은 광장 밖까지 날아감)
Raid.KNOCK_UP = 26

-- 보스·전장 (광장 위 하늘에 떠 있는 별도 섬, 2026-10-20 사용자 "보스전은 별도 공간에서, 참여한 사람만 이동")
Raid.BOSS_SIZE = 12
Raid.BOSS_HOVER = 8 -- 전장 바닥에서 보스 중심 높이
Raid.ARENA_R = 34 -- 패턴·이동 범위
Raid.ARENA_EDGE = 44 -- 전장 바닥 반지름 (패턴 범위 + 여유)
Raid.ARENA_HEIGHT = 260 -- 광장 바닥 위로
Raid.SPAWN_R = 22 -- 참여자 배치 원

-- 패턴
Raid.PATTERN_GAP = 4.5 -- 패턴 사이 쉬는 시간
Raid.FIRST_PATTERN = 1.5 -- 전투 시작 뒤 첫 패턴까지
Raid.ENRAGE_AT = 0.5 -- 체력이 이 비율 아래면 분노: 패턴 간격 ENRAGE_GAP
Raid.ENRAGE_GAP = 3
Raid.JUMP_GRACE = 0.2 -- 충격파·레이저가 지나갈 때 이 시간 안에 떠 있었으면 피한 것으로 (모바일 지연)
Raid.SLAM_TIME = 2.2 -- 충격파가 ARENA_R까지 퍼지는 시간
Raid.SLAM_BAND = 2.2 -- 충격파 두께 (반쪽)
Raid.SLAM_JUMP = 1.6 -- 바닥에서 이만큼(+서 있는 높이) 떠 있으면 피함
Raid.METEOR_WARN = 1.5 -- 바닥 표시 뒤 떨어지기까지
Raid.METEOR_R = 6
function Raid.meteorCount(players: number): number
	return math.min(14, 4 + 2 * players)
end
-- 레이저 (LASER CUBE): 바닥 높이로 지름 전체를 가르는 빛줄기가 반 바퀴 돈다 → 지나갈 때 점프
Raid.LASER_WARN = 1.2 -- 예고선 (도는 방향 화살표 포함)
Raid.LASER_TIME = 5.5 -- 반 바퀴 도는 시간 (4 → 5.5, 2026-10-21 리뷰: 반지름 34에서 0.12초 만에 지나감)
Raid.LASER_BAND = 1.6 -- 빛줄기에서 이 거리 안이면 맞음 (수평)
-- 덮치기 (JUMBO CUBE): 참여자 발밑에 붉은 원 → 보스가 뛰어올라 그 자리에 떨어짐 → 비켜서 피함
Raid.POUNCE_WARN = 1.1
Raid.POUNCE_R = 8
function Raid.pounceCount(players: number): number
	return math.min(6, 2 + players // 3)
end
-- 폭풍 (STORM CUBE): 전장 전체가 붉어지고 초록 안전 원 몇 개만 남는다 → 원 안으로
Raid.STORM_WARN = 2.6
Raid.STORM_SAFE_R = 7
function Raid.stormZones(players: number): number
	return math.min(5, 3 + players // 3)
end
-- 굴러오는 바위 (STORM CUBE): 보스에서 바깥으로 여러 줄 → 줄 사이로 비켜섬
Raid.SPOKES = 8
Raid.SPOKE_WARN = 1.2
Raid.SPOKE_TIME = 1.4
Raid.SPOKE_HIT = 3.4
Raid.SPOKE_STRIPE = 2 * Raid.SPOKE_HIT + 1 -- 경고 줄 폭 = 맞는 폭 + 여유 (예전 5.44는 맞는 폭보다 좁았음)

-- 보스 4종 로테이션 (2026-10-20 사용자 "보스 3~4개로 늘리고 조금씩 다른 패턴, 로테이션").
-- 레이드마다 다음 보스로 (서버마다 시작 보스는 무작위). 체력·보상은 같고 패턴만 다르다.
-- 색은 {r, g, b} (Lune 테스트에서도 읽게 Color3을 쓰지 않음)
export type Boss = {
	id: string,
	name: string,
	blurb: string, -- 초대 창 한 줄 (영어)
	color: { number },
	glow: { number },
	crown: { number },
	face: number, -- 얼굴 그림 = 이 등급의 표정
	size: number,
	patterns: { string },
}
Raid.BOSSES = {
	{
		id = "king",
		name = "KING CUBE",
		blurb = "Jump the shockwave, dodge falling cubes",
		color = { 120, 60, 200 },
		glow = { 255, 120, 255 },
		crown = { 255, 205, 60 },
		face = 40,
		size = 12,
		patterns = { "slam", "meteor" },
	},
	{
		id = "laser",
		name = "LASER CUBE",
		blurb = "Jump over the spinning laser",
		color = { 190, 35, 55 },
		glow = { 255, 90, 90 },
		crown = { 220, 225, 235 },
		face = 33,
		size = 11,
		patterns = { "laser", "meteor" },
	},
	{
		id = "jumbo",
		name = "JUMBO CUBE",
		blurb = "It leaps at you - keep moving!",
		color = { 60, 165, 75 },
		glow = { 150, 255, 140 },
		crown = { 255, 150, 40 },
		face = 37,
		size = 14,
		patterns = { "pounce", "slam" },
	},
	{
		id = "storm",
		name = "STORM CUBE",
		blurb = "Hide in green circles, dodge rolling rocks",
		color = { 40, 100, 210 },
		glow = { 120, 220, 255 },
		crown = { 255, 245, 120 },
		face = 29,
		size = 12,
		patterns = { "storm", "spokes" },
	},
} :: { Boss }

-- n번째 레이드의 보스 (0부터, 끝나면 처음으로)
function Raid.bossAt(n: number): Boss
	return Raid.BOSSES[n % #Raid.BOSSES + 1]
end

function Raid.boss(id: string?): Boss
	for _, b in Raid.BOSSES do
		if b.id == id then
			return b
		end
	end
	return Raid.BOSSES[1]
end

-- 목숨 (2026-10-21 사용자 "5번 이상 맞으면 그 보스전 실패, 체력은 자기 머리 위에"): 패턴에 LIVES번 맞으면 탈락 → 집으로
Raid.LIVES = 5

-- 보상 (2026-10-21 사용자 "보스 타수 보너스는 없어도 됨 / 누구든 보스를 잡으면 탈락자도 기여 보상 10% / 아무도 못 잡으면 보상 없음")
Raid.MIN_HITS = 5 -- 이만큼은 때려야 보상 (탈락자의 기여 보상도)
Raid.WIN_COINS = 12
Raid.CONTRIB_SHARE = 0.1 -- 탈락했어도 보스가 잡히면 승리 코인의 10%
Raid.BUFF_MULT = 2 -- 잡으면 참여자(코인 받은 사람)만 수입 x2
Raid.BUFF_SECONDS = 5 * 60

-- out: 목숨을 다 잃어 탈락했나
function Raid.coins(win: boolean, hits: number, out: boolean?): number
	if not win or hits < Raid.MIN_HITS then
		return 0
	end
	if out then
		return math.max(1, math.floor(Raid.WIN_COINS * Raid.CONTRIB_SHARE + 0.5))
	end
	return Raid.WIN_COINS
end

-- 보스 코인 강화 (영구, 리버스로 사라지지 않음)
-- 2026-10-20 사용자 "단위를 조금 더 크게, 레벨당 요구량 증가 없이 동일하게": Lv당 효과 2배·최대 Lv 절반, 비용 고정
-- 이름은 RAIDER ~ (2026-10-21 사용자 "BOSS SPEED면 보스를 강화하는 것 같음"). id는 저장 데이터라 그대로
-- 2026-10-21 리뷰: 다 사면 코인 쓸 곳이 없어서 RAIDER INCOME을 다 산 뒤 열리는 상한 없는 RAIDER INCOME+ (Lv당 +2%, 100코인)
export type Upgrade = { id: string, title: string, per: number, max: number, cost: number?, after: string? }
Raid.UPGRADES = {
	{ id = "income", title = "RAIDER INCOME", per = 0.1, max = 10 }, -- 수입 +10%/Lv (최대 +100%)
	{ id = "speed", title = "RAIDER SPEED", per = 0.05, max = 6 }, -- 이동 속도 +5%/Lv (최대 +30%)
	{ id = "resist", title = "RAIDER GUARD", per = 0.1, max = 5 }, -- 넉백·경직 저항 +10%/Lv (최대 50%)
	{ id = "income2", title = "RAIDER INCOME+", per = 0.02, max = 9999, cost = 100, after = "income" }, -- 수입 +2%/Lv
} :: { Upgrade }

function Raid.upgrade(id: string): Upgrade?
	for _, u in Raid.UPGRADES do
		if u.id == id then
			return u
		end
	end
	return nil
end

Raid.COST = 50 -- 모든 Lv 같은 값 (승리 1판 12코인 → 4~5판에 1Lv, 기본 21Lv = 1,050코인)
function Raid.cost(_lv: number, id: string?): number
	local u = if id then Raid.upgrade(id) else nil
	return if u and u.cost then u.cost else Raid.COST
end

-- 이 강화를 살 수 있나 (after: 앞 강화를 다 사야 열림)
function Raid.unlocked(boss: { [string]: number }?, id: string): boolean
	local u = Raid.upgrade(id)
	if not u then
		return false
	end
	if not u.after then
		return true
	end
	local pre = Raid.upgrade(u.after)
	return pre ~= nil and (if boss then boss[u.after] or 0 else 0) >= pre.max
end

-- 수입 배수 (RAIDER INCOME + RAIDER INCOME+)
function Raid.incomeBonus(boss: { [string]: number }?): number
	return Raid.effect(boss, "income") + Raid.effect(boss, "income2")
end

-- 데이터 data.boss = { income, speed, resist } → 효과 (비율)
function Raid.effect(boss: { [string]: number }?, id: string): number
	local u = Raid.upgrade(id)
	if not u then
		return 0
	end
	local lv = math.clamp(if boss then boss[id] or 0 else 0, 0, u.max)
	return lv * u.per
end

-- 넉백 저항 합치기 (오라 저항과 곱으로, 최대 80%)
Raid.RESIST_CAP = 0.8
function Raid.combineResist(a: number, b: number): number
	return math.min(Raid.RESIST_CAP, 1 - (1 - a) * (1 - b))
end

-- Remote 계약 (core Net 형식, Net.serve로 추가)
Raid.REMOTES = {
	RaidJoin = { kind = "function", args = { "boolean" } }, -- 참여/거절 → 받아들여졌나
	RaidUpgrade = { kind = "function", args = { "string" } }, -- 코인 강화
	Raid = { kind = "event" }, -- ("invite", left, joined, bossId, inviteId) | ("wait", left) | ("start", info) | ("tick", info) | ("hit", crit) | ("hurt", stun, livesLeft) | ("out") | ("end", win, coins, buff, hits, out) | ("idle", nextIn)
}

return Raid
