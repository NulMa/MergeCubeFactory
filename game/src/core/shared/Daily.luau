--!strict
-- Daily gifts, daily quests and the 7-day login track (docs/23, docs/33). Pure, Lune-tested (tests/core/Daily.spec).
-- A day is a UTC date. The game injects its reward kinds and numbers with Daily.new(def); the server grants each
-- reward kind through its own handler table (core never knows what "gems" or "steal" mean).
--   small gifts: one every smallEvery seconds of play today, at most smallMax (kind rolled from smallTable)
--   big gifts:   at play-time marks bigAt (kind rolled from bigTable)
--   quests:      questCount quests picked by a date seed (same on every server), targets scale with a progress level
--   login:       one slot per day played (missed days do not reset), wraps after the last slot
-- Free random only (never paid), see CLAUDE.md.

local Rarity = require(script.Parent.Rarity)

local Daily = {}

export type Weighted = { id: string, weight: number }
-- scale: target grows with the progress level (e.g. rebirths). maxLevel: not offered above this level
export type Quest = { id: string, target: number, text: string, scale: boolean?, maxLevel: number? }
export type LoginReward = { kind: string, amount: number, text: string }

export type Def = {
	smallEvery: number,
	smallMax: number,
	smallTable: { Weighted },
	bigAt: { number },
	bigTable: { Weighted },
	questCount: number,
	quests: { Quest },
	scaleStep: number?, -- target x (1 + scaleStep x level), default 0
	scaleMaxLevel: number?, -- level cap for scaling, default 10
	login: { LoginReward },
	seedSalt: number?, -- quest seed salt (default 12345; give each game its own)
}

export type Rules = {
	def: Def,
	dayOf: (t: number) -> number,
	rollSmall: (r: number) -> string,
	rollBig: (r: number) -> string,
	smallReady: (play: number, claimed: number) -> number,
	smallNextIn: (play: number) -> number?,
	bigReady: (play: number, claimed: number) -> number,
	bigNextIn: (play: number) -> number?,
	quest: (id: string) -> Quest?,
	questTarget: (q: Quest, level: number) -> number,
	questsFor: (day: number, level: number?) -> { string },
	nextLogin: (index: number) -> number,
}

-- UTC day number
function Daily.dayOf(t: number): number
	return t // 86400
end

-- Seconds until the next UTC midnight
function Daily.secondsToNextDay(t: number): number
	return 86400 - t % 86400
end

-- Reward that scales with income: max(min, floor(income x seconds))
function Daily.incomeReward(income: number, seconds: number, min: number): number
	return math.max(min, math.floor(income * seconds))
end

local function pickId(list: { Weighted }, r: number): string
	local e = Rarity.pick(list, r)
	return if e then e.id else ""
end

function Daily.new(def: Def): Rules
	local rules = {} :: Rules
	rules.def = def
	rules.dayOf = Daily.dayOf

	-- r: random in [0, 1)
	function rules.rollSmall(r: number): string
		return pickId(def.smallTable, r)
	end

	function rules.rollBig(r: number): string
		return pickId(def.bigTable, r)
	end

	-- small gifts ready now
	function rules.smallReady(play: number, claimed: number): number
		return math.max(0, math.min(play // def.smallEvery, def.smallMax) - claimed)
	end

	-- seconds to the next small gift (nil when today's share is all earned)
	function rules.smallNextIn(play: number): number?
		local earned = play // def.smallEvery
		if earned >= def.smallMax then
			return nil
		end
		return (earned + 1) * def.smallEvery - play
	end

	function rules.bigReady(play: number, claimed: number): number
		local n = 0
		for _, at in def.bigAt do
			if play >= at then
				n += 1
			end
		end
		return math.max(0, n - claimed)
	end

	function rules.bigNextIn(play: number): number?
		for _, at in def.bigAt do
			if play < at then
				return at - play
			end
		end
		return nil
	end

	function rules.quest(id: string): Quest?
		for _, q in def.quests do
			if q.id == id then
				return q
			end
		end
		return nil
	end

	function rules.questTarget(q: Quest, level: number): number
		if not q.scale then
			return q.target
		end
		local k = 1 + (def.scaleStep or 0) * math.clamp(level, 0, def.scaleMaxLevel or 10)
		return math.floor(q.target * k + 0.5)
	end

	-- questCount different quests from a date seed: the same day gives the same quests on every server
	function rules.questsFor(day: number, level: number?): { string }
		local pool = {}
		for _, q in def.quests do
			if q.maxLevel == nil or (level or 0) <= q.maxLevel then
				table.insert(pool, q.id)
			end
		end
		-- Park-Miller (products stay below 2^53)
		local seed = (day * 7919 + (def.seedSalt or 12345)) % 2147483647 + 1
		local out = {}
		for _ = 1, math.min(def.questCount, #pool) do
			seed = (seed * 16807) % 2147483647
			local i = seed % #pool + 1
			table.insert(out, table.remove(pool, i) :: string)
		end
		return out
	end

	-- last login slot (0 = never) -> today's slot
	function rules.nextLogin(index: number): number
		return index % #def.login + 1
	end

	return rules
end

return Daily
