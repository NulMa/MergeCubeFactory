--!strict
-- 랭킹 공통 (순수, Lune 테스트 대상). OrderedDataStore는 정수만 저장하므로 큰 수는 로그로 바꿔 넣는다.

-- Board lists are per game (Merge: shared/RankBoards). Board shape:
--   { id, title, store = OrderedDataStore name, log = true for values that grow over many digits }

local Ranking = {}

export type Board = { id: string, title: string, store: string, log: boolean, plaza: boolean? }

Ranking.TOP_N = 50
Ranking.SUBMIT_INTERVAL = 120 -- 플레이어별 점수 기록 주기(초)
Ranking.FETCH_INTERVAL = 60 -- 서버별 상위 목록 갱신 주기(초)

local SCALE = 1e6

-- 수입처럼 수십 자리까지 커지는 값: log10 × 1e6 정수 (소수 6자리 정밀도)
function Ranking.encode(value: number, log: boolean): number
	if value ~= value or value <= 0 then
		return 0
	end
	if log then
		return math.floor(math.log10(math.max(value, 1)) * SCALE)
	end
	return math.floor(value)
end

function Ranking.decode(score: number, log: boolean): number
	if log then
		return if score <= 0 then 0 else 10 ^ (score / SCALE)
	end
	return score
end

return Ranking
