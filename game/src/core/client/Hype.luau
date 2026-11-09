--!strict
-- 연출 감독 (docs/18 §1): 같은 사건이라도 '이 플레이어에게 얼마나 놀라운가'로 연출 크기(0~4)를 정한다.
--   * 기본값: 희귀도(rank), 처음 본 것(도감 NEW)은 +1, 이어받은 것(keep)은 -1
--   * 익숙해짐: 최근 60초 안에 같은 종류가 또 나오면 한 단계씩 내린다
--   * 가뭄 보너스: 큰 연출(3+)이 2분 넘게 없었으면 +1
--   * 예산: 4단계는 60초에 한 번, 3단계는 15초에 한 번까지 (넘으면 한 단계 낮춤)
-- 연출만 바꾼다. 보상·확률은 그대로. Core client module (docs/33): the game decides what a "kind" and a "rank" are
-- (Merge: variant id + variant rank). Numbers can be changed with Hype.configure; defaults are Merge's.

local Hype = {}

export type Options = {
	habitWindow: number?, -- seconds a repeat counts as "seen recently"
	drought: number?, -- seconds without a big moment before the +1 bonus
	budget: { [number]: number }?, -- level -> minimum seconds between two moments of that level
	comboMarks: { number }?, -- combo counts that get a popup
	discover: ((rank: number, isNew: boolean, revealed: boolean) -> (number, number))?, -- rank -> (base, floor)
}

local HABIT_WINDOW = 60
local DROUGHT = 120
local BUDGET = { [3] = 15, [4] = 60 } :: { [number]: number }
local COMBO_MARKS = { 3, 5, 10, 25, 50, 100 }

-- 2026-10-19 사용자 (Merge): 이미 도감에 있는 것은 연출을 줄이고, 처음 보는 것은 더 크게
local function defaultDiscover(rank: number, isNew: boolean, revealed: boolean): (number, number)
	if isNew then
		return (if rank >= 3 then 4 elseif rank == 2 then 3 else 2), (if rank >= 5 then 4 else 2)
	end
	return (if rank >= 5 then 3 elseif rank >= 3 then 1 else 0), (if rank >= 5 then 2 elseif revealed then 1 else 0)
end
local discoverRule = defaultDiscover

local seen: { [string]: { number } } = {} -- 종류별 최근 시각
local lastAt: { [number]: number } = {} -- 단계별 마지막 시각
local lastBig = os.clock()

function Hype.configure(opts: Options)
	HABIT_WINDOW = opts.habitWindow or HABIT_WINDOW
	DROUGHT = opts.drought or DROUGHT
	BUDGET = opts.budget or BUDGET
	COMBO_MARKS = opts.comboMarks or COMBO_MARKS
	discoverRule = opts.discover or discoverRule
end

local function recent(kind: string, now: number): number
	local list: { number } = seen[kind] or {}
	local kept: { number } = {}
	for _, t in list do
		if now - t <= HABIT_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	seen[kind] = kept
	return #kept - 1
end

-- 최종 단계 결정 (익숙해짐·가뭄·예산 적용). floor = 무슨 일이 있어도 이 아래로는 안 내림
function Hype.settle(kind: string, base: number, floor: number): number
	local now = os.clock()
	local level = base - recent(kind, now)
	if now - lastBig >= DROUGHT and level >= 2 then
		level += 1
	end
	level = math.clamp(level, floor, 4)
	while level >= 3 and lastAt[level] and now - lastAt[level] < BUDGET[level] do
		level -= 1
	end
	level = math.max(level, floor)
	lastAt[level] = now
	if level >= 3 then
		lastBig = now
	end
	return level
end

-- 희귀한 것 등장 (변이·오라·꽃 변이 등). rank = 1부터(높을수록 희귀). keep = 이어받은 것(-1),
-- revealed = 공개 연출(Reveal)을 거친 것 (최소 단계 보장)
function Hype.discover(kind: string, rank: number, isNew: boolean, keep: boolean?, revealed: boolean?): number
	local base, floor = discoverRule(rank, isNew, revealed == true)
	if keep then
		base -= 1
	end
	return Hype.settle(kind, base, floor)
end

-- 콤보 팝업은 마일스톤에서만 (3/5/10/25/50/100). 아니면 nil
function Hype.comboMark(combo: number): number?
	for i, m in COMBO_MARKS do
		if combo == m then
			return math.min(i, 4)
		end
	end
	return nil
end

-- 진행 사건(합치기·수확 등): 내 최고 기록보다 한참 낮으면 조용하게 (0~1), 최고 근처면 1~2
function Hype.progress(value: number, best: number): number
	if value >= best then
		return 2
	elseif value >= best - 2 then
		return 1
	end
	return 0
end

-- 다른 큰 연출(기록·공개)이 나갔음을 알린다: 예산·가뭄 계산에 반영
function Hype.spent(level: number)
	local now = os.clock()
	lastAt[level] = now
	if level >= 3 then
		lastBig = now
	end
end

return Hype
