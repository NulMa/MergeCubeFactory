--!strict
-- 접속 중에만 붙는 성장 가속 (2026-10-20 사용자 "접속시에만 할 수 있고 성장을 가속시킬 컨텐츠"). 순수 규칙, Lune 테스트 대상.
--   온라인 연속 보너스: 이번 접속을 이어 간 시간에 따라 수입 +%. 나가면 처음부터
--   콤보 현금: 연쇄 합치기 3번째부터 합치기마다 기본 수입 몇 초치, 연쇄가 끝나면 한 번에 지급
--   온라인 부화 가속: 접속 중엔 코어 부화 시계가 2배로 간다 (오프라인은 그대로)
--   광장 선물 상자: 광장에 상자가 나타나고, 먼저 닿은 사람이 기본 수입 몇 초치를 받는다

local Online = {}

-- { 이어 간 초, 수입 +비율 }
Online.STREAK = {
	{ at = 5 * 60, bonus = 0.1 },
	{ at = 10 * 60, bonus = 0.2 },
	{ at = 20 * 60, bonus = 0.35 },
	{ at = 30 * 60, bonus = 0.5 },
}

function Online.streakBonus(seconds: number): number
	local b = 0
	for _, s in Online.STREAK do
		if seconds >= s.at then
			b = s.bonus
		end
	end
	return b
end

-- 다음 단계: (남은 초, 그때 보너스) 또는 nil (최대)
function Online.streakNext(seconds: number): (number?, number?)
	for _, s in Online.STREAK do
		if seconds < s.at then
			return s.at - seconds, s.bonus
		end
	end
	return nil, nil
end

-- 콤보 n번째 합치기의 현금 (기본 수입 × 초). 1·2번째는 0, 3번째 0.5초부터 0.5씩, 최대 8초
Online.COMBO_FROM = 3
Online.COMBO_STEP = 0.5
Online.COMBO_CAP = 8
function Online.comboSeconds(combo: number): number
	if combo < Online.COMBO_FROM then
		return 0
	end
	return math.min(Online.COMBO_CAP, (combo - Online.COMBO_FROM + 1) * Online.COMBO_STEP)
end

Online.HATCH_SPEED = 2 -- 접속 중 부화 시계 배속

-- 광장 선물 상자
Online.BOX_MAX = 2 -- 동시에 떠 있는 수
Online.BOX_EVERY = 75 -- 새 상자 간격 (초)
Online.BOX_LIFE = 150 -- 아무도 안 열면 사라짐
Online.BOX_CASH_SECONDS = 90 -- 기본 수입 × 초
Online.BOX_CASH_MIN = 300
Online.BOX_SHARD_MERGES = 20 -- 펫 조각도 같이: 최고 등급 합치기 20번치 (조각은 Robux 판매 없음)

function Online.boxCash(baseIncome: number): number
	return math.max(Online.BOX_CASH_MIN, math.floor(baseIncome * Online.BOX_CASH_SECONDS))
end

return Online
