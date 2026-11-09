--!strict
-- Merge 랭킹 보드 목록 (core/shared/Ranking이 인코딩, server/Leaderboard·World가 사용)

local RankBoards = {
	{ id = "income", title = "TOP INCOME", store = "MCF_Rank_Income_Live1", log = true },
	{ id = "merges", title = "TOP MERGES", store = "MCF_Rank_Merges_Live1", log = false },
	-- 2026-10-20: 리버스 보드 (오래 한 사람의 진척). 광장 게시판은 앞뒤 두 개라 패널에만 (plaza = false)
	{ id = "rebirths", title = "TOP REBIRTHS", store = "MCF_Rank_Rebirths_Live1", log = false, plaza = false },
}

return RankBoards
