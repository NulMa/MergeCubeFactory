--!strict
-- 접속 선물·일일 퀘스트 서버 (docs/23_DAILY.md). 규칙은 shared/Daily, 재화는 Ledger 경유.
-- 저장: data.daily = { day, play(오늘 플레이 초), small(받은 작은 선물 수), big(받은 큰 선물 수),
--                      quests = { { id, n, done(받음) } }, bonus(완주 보상 받음) }
-- 황금 큐브 보상은 Events.gift(트레이에 황금 큐브를 하나 더 떨어뜨림, 잡아야 받음)로 넘긴다.

local Shared = game:GetService("ReplicatedStorage").Game
local DailyRules = require(Shared.Daily)
local Strings = require(Shared.Strings) -- 보상 글자는 번역 키로 (client/Loc)
local Pets = require(Shared.Pets)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Ledger = require(game:GetService("ServerScriptService").CoreServer.Ledger)

local Daily = {}

local rng = Random.new()

type Ctx = { giftGolden: (player: Player) -> () }
local ctx: Ctx? = nil

function Daily.init(c: Ctx)
	ctx = c
end

-- 날짜가 바뀌었으면 새 하루 (저장에 없던 플레이어도 여기서 만든다)
function Daily.ensure(data: { [string]: any }): { [string]: any }
	local today = DailyRules.dayOf(os.time())
	local d = data.daily
	if type(d) ~= "table" or d.day ~= today then
		local quests = {}
		for i, id in DailyRules.questsFor(today, data.rebirths or 0) do
			local def = DailyRules.quest(id)
			-- 목표는 하루가 시작될 때 정해 둔다 (중간에 리버스해도 그날 목표는 그대로)
			local target = if def then DailyRules.questTarget(def, data.rebirths or 0) else 1
			quests[i] = { id = id, n = 0, done = false, target = target }
		end
		d = { day = today, play = 0, small = 0, big = 0, quests = quests, bonus = false }
		data.daily = d
	end
	return d
end

-- secondTick에서 1초씩
function Daily.tick(data: { [string]: any })
	local d = Daily.ensure(data)
	d.play += 1
end

function Daily.progress(data: { [string]: any }, kind: string, amount: number?)
	local d = Daily.ensure(data)
	for _, q in d.quests do
		if q.id == kind then
			local def = DailyRules.quest(q.id)
			if def then
				q.n = math.min(q.target or def.target, q.n + (amount or 1))
			end
		end
	end
end

-- 선물 받기: which = "small" | "big". 반환: (보상 id, 화면 글자) 또는 nil
function Daily.claimGift(
	player: Player,
	data: { [string]: any },
	income: number,
	which: string
): (string?, (string | Strings.Msg)?)
	local d = Daily.ensure(data)
	local reward: string
	if which == "small" then
		if DailyRules.smallReady(d.play, d.small) <= 0 then
			return nil, nil
		end
		d.small += 1
		reward = DailyRules.rollSmall(rng:NextNumber())
	elseif which == "big" then
		if DailyRules.bigReady(d.play, d.big) <= 0 then
			return nil, nil
		end
		d.big += 1
		reward = DailyRules.rollBig(rng:NextNumber())
	else
		return nil, nil
	end
	local text: string | Strings.Msg
	if reward == "cash" then
		local amount = DailyRules.smallCash(income)
		Ledger.credit(player, "cash", amount, "Gameplay", "gift_cash")
		text = Strings.msg("reward.cash", { cash = Format.short(amount) })
	elseif reward == "steal" then
		local n = if which == "big" then DailyRules.BIG_STEAL else 1
		data.stealPaid = (data.stealPaid or 0) + n
		text = Strings.msg("reward.steal", { n = n })
	elseif reward == "golden" then
		if ctx then
			ctx.giftGolden(player)
		end
		text = "GOLDEN CUBE! CATCH IT"
	else
		local gems = if reward == "gems_l" then DailyRules.GEMS_L else DailyRules.GEMS_S
		Ledger.credit(player, "gems", gems, "Gameplay", "gift_gems")
		text = Strings.msg("reward.gems", { n = gems })
	end
	return reward, text
end

-- 퀘스트 보상: index = 1..3, 0 = 셋 다 끝낸 보너스. 반환: 화면 글자 또는 nil
function Daily.claimQuest(player: Player, data: { [string]: any }, income: number, index: number): Strings.Msg?
	local d = Daily.ensure(data)
	if index == 0 then
		if d.bonus then
			return nil
		end
		for _, q in d.quests do
			if not q.done then
				return nil
			end
		end
		d.bonus = true
		Ledger.credit(player, "gems", DailyRules.BONUS_GEMS, "Gameplay", "quest_bonus")
		return Strings.msg("daily.allDone", { gems = DailyRules.BONUS_GEMS })
	end
	local q = d.quests[index]
	local def = q and DailyRules.quest(q.id)
	if not q or not def or q.done or q.n < (q.target or def.target) then
		return nil
	end
	q.done = true
	local cash = DailyRules.questCash(income)
	Ledger.credit(player, "gems", DailyRules.QUEST_GEMS, "Gameplay", "quest")
	Ledger.credit(player, "cash", cash, "Gameplay", "quest_cash")
	return Strings.msg("daily.questReward", { gems = DailyRules.QUEST_GEMS, cash = Format.short(cash) })
end

function Daily.snapshot(data: { [string]: any }, income: number): { [string]: any }
	local d = Daily.ensure(data)
	local quests = {}
	local allDone = true
	for i, q in d.quests do
		local def = DailyRules.quest(q.id)
		quests[i] = {
			text = if def then def.text else q.id,
			n = q.n,
			target = q.target or (if def then def.target else 1),
			done = q.done,
		}
		allDone = allDone and q.done
	end
	return {
		small = DailyRules.smallReady(d.play, d.small),
		smallNext = DailyRules.smallNextIn(d.play),
		big = DailyRules.bigReady(d.play, d.big),
		bigNext = DailyRules.bigNextIn(d.play),
		bigClaimed = d.big,
		bigAt = DailyRules.BIG_AT,
		play = d.play,
		quests = quests,
		bonusReady = allDone and not d.bonus,
		bonusDone = d.bonus,
		bonusGems = DailyRules.BONUS_GEMS,
		questGems = DailyRules.QUEST_GEMS,
		questCash = DailyRules.questCash(income),
		resetIn = (d.day + 1) * 86400 - os.time(),
	}
end

-- 7일 출석: 날짜가 바뀌었으면 다음 칸을 열어 둔다
local function ensureLogin(data: { [string]: any }): { [string]: any }
	local today = DailyRules.dayOf(os.time())
	local l = data.login
	if type(l) ~= "table" then
		l = { day = 0, index = 0, claimed = true }
		data.login = l
	end
	if l.day ~= today then
		l.day = today
		l.index = DailyRules.nextLogin(l.index or 0)
		l.claimed = false
	end
	return l
end

-- 출석 보상 받기 → 화면 글자 또는 nil
function Daily.claimLogin(player: Player, data: { [string]: any }, income: number): Strings.Msg?
	local l = ensureLogin(data)
	if l.claimed then
		return nil
	end
	local r = DailyRules.LOGIN[l.index]
	if not r then
		return nil
	end
	l.claimed = true
	if r.kind == "cash" then
		local amount = math.max(DailyRules.LOGIN_CASH_MIN, math.floor(income * r.amount))
		Ledger.credit(player, "cash", amount, "Gameplay", "login_cash")
		return Strings.msg("login.cash", { day = l.index, cash = Format.short(amount) })
	elseif r.kind == "shards" then
		local n = r.amount * Pets.shardsForMerge(data.stats.best or 1)
		Ledger.credit(player, "shards", n, "Gameplay", "login_shards")
		return Strings.msg("login.shards", { day = l.index, n = n })
	elseif r.kind == "gems" then
		Ledger.credit(player, "gems", r.amount, "Gameplay", "login_gems")
		return Strings.msg("login.gems", { day = l.index, n = r.amount })
	elseif r.kind == "steal" then
		data.stealPaid = (data.stealPaid or 0) + r.amount
		return Strings.msg("login.steals", { day = l.index, n = r.amount })
	else
		Ledger.credit(player, "bossCoins", r.amount, "Gameplay", "login_boss")
		Ledger.credit(player, "gems", DailyRules.LOGIN_DAY7_GEMS, "Gameplay", "login_gems")
		return Strings.msg("login.day7", { n = r.amount, gems = DailyRules.LOGIN_DAY7_GEMS })
	end
end

function Daily.loginSnapshot(data: { [string]: any }): { [string]: any }
	local l = ensureLogin(data)
	local days = {}
	for i, r in DailyRules.LOGIN do
		days[i] = r.text
	end
	return { index = l.index, claimed = l.claimed, days = days }
end

-- Studio 디버그: 오늘 플레이 시간 더하기
function Daily.debugPlay(data: { [string]: any }, seconds: number)
	Daily.ensure(data).play += seconds
end

return Daily
