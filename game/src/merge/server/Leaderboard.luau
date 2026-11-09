--!strict
-- 랭킹: 서버 안 leaderstats(플레이어 목록) + 전 서버 OrderedDataStore 보드(최고 수입, 누적 합치기).
-- 점수 기록은 SUBMIT_INTERVAL마다와 퇴장 시. 상위 목록은 서버마다 FETCH_INTERVAL마다 받아 캐시하고,
-- 클라는 GetLeaderboard로 캐시를 받는다. DataStore를 못 쓰면(Studio API 꺼짐 등) 이 서버 플레이어로 대신 보여 준다.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local Ranking = require(game:GetService("ReplicatedStorage").Core.Ranking)
local RankBoards = require(Shared.RankBoards)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Data = require(game:GetService("ServerScriptService").CoreServer.Data)

type Entry = { userId: number, name: string, value: number }

local Leaderboard = {}

local stores: { [string]: OrderedDataStore? } = {}
local cache: { [string]: { Entry } } = {}
local live = false -- 마지막 갱신이 실제 전 서버 데이터였는가
local names: { [number]: string } = {}
local lastSubmit: { [Player]: number } = {}

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local p = Players:GetPlayerByUserId(userId)
	local ok, name = pcall(function()
		return if p then p.DisplayName else Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("#" .. userId)
	names[userId] = result
	return result
end

-- 플레이어 데이터에서 보드별 값
local function valueOf(data: { [string]: any }, id: string): number
	if id == "income" then
		return data.stats.peakIncome or 0
	elseif id == "merges" then
		return data.stats.merges or 0
	elseif id == "rebirths" then
		return data.rebirths or 0
	end
	return 0
end

local function track(player: Player, data: { [string]: any })
	-- 최고 수입: 리버스로 수입이 줄어도 기록은 남는다
	data.stats.peakIncome = math.max(data.stats.peakIncome or 0, data.lastIncome or 0)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Best") :: IntValue).Value = data.stats.best or 1
		(ls:FindFirstChild("Income") :: StringValue).Value = "$" .. Format.short(data.lastIncome or 0) .. "/s"
	end
end

-- 점수는 지금 읽고, DataStore 쓰기는 따로 돈다: 나갈 때 SetAsync가 기다리느라 저장·세션 종료가 늦어지지 않게 (2026-10-20 리뷰)
local function submit(player: Player, given: { [string]: any }?)
	local data = given or Data.get(player)
	if not data then
		return
	end
	track(player, data)
	local scores: { [string]: number } = {}
	for _, b in RankBoards do
		if stores[b.id] then
			scores[b.id] = Ranking.encode(valueOf(data, b.id), b.log)
		end
	end
	lastSubmit[player] = os.clock()
	local userId = tostring(player.UserId)
	task.spawn(function()
		for id, score in scores do
			local store = stores[id]
			if store then
				pcall(function()
					store:SetAsync(userId, score)
				end)
			end
		end
	end)
end

local function localBoard(id: string, log: boolean): { Entry }
	local out = {}
	for _, p in Players:GetPlayers() do
		local data = Data.get(p)
		if data then
			table.insert(out, { userId = p.UserId, name = p.DisplayName, value = valueOf(data, id) })
		end
	end
	table.sort(out, function(a, b)
		return a.value > b.value
	end)
	return out
end

local function fetch()
	local allOk = true
	for _, b in RankBoards do
		local store = stores[b.id]
		local ok, pages = false, nil
		if store then
			ok, pages = pcall(function()
				return store:GetSortedAsync(false, Ranking.TOP_N)
			end)
		end
		if ok and pages then
			local list = {}
			for _, item in (pages :: DataStorePages):GetCurrentPage() do
				local userId = tonumber(item.key) or 0
				table.insert(list, {
					userId = userId,
					name = nameOf(userId),
					value = Ranking.decode(item.value, b.log),
				})
			end
			cache[b.id] = list
		else
			allOk = false
			cache[b.id] = localBoard(b.id, b.log)
		end
	end
	live = allOk
end

-- 광장 게시판(server/World)용: 보드별 상위 목록 캐시와 전 서버 여부
function Leaderboard.top(id: string): ({ Entry }, boolean)
	return cache[id] or {}, live
end

function Leaderboard.init(net: any)
	for _, b in RankBoards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(b.store .. Config.STUDIO_STORE_SUFFIX)
		end)
		stores[b.id] = if ok then store else nil
	end

	Data.onLoaded:Connect(function(player: Player, data)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local best = Instance.new("IntValue")
		best.Name = "Best"
		best.Value = data.stats.best or 1
		best.Parent = ls
		local income = Instance.new("StringValue")
		income.Name = "Income"
		income.Parent = ls
		ls.Parent = player
		lastSubmit[player] = os.clock() -- 첫 기록은 한 주기 뒤 (접속 직후 0 수입 기록 방지)
	end)
	Data.onReleasing:Connect(function(player: Player, data: { [string]: any })
		submit(player, data)
		lastSubmit[player] = nil
	end)

	-- mine: 내 지금 값 (상위 목록 밖이어도 패널 아래 '내 줄'에 보여 준다)
	net.on("GetLeaderboard", function(player: Player)
		local data = Data.get(player)
		if data then
			track(player, data)
		end
		local boards = {}
		for _, b in RankBoards do
			table.insert(boards, {
				id = b.id,
				title = b.title,
				entries = cache[b.id] or {},
				mine = if data then valueOf(data, b.id) else 0,
			})
		end
		return { boards = boards, live = live, top = Ranking.TOP_N }
	end)

	task.spawn(function()
		while true do
			fetch()
			task.wait(Ranking.FETCH_INTERVAL)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, p in Players:GetPlayers() do
				local data = Data.get(p)
				if data then
					track(p, data)
					if now - (lastSubmit[p] or now) >= Ranking.SUBMIT_INTERVAL then
						task.spawn(submit, p)
					end
				end
			end
			if not live then
				-- 전 서버 보드를 못 쓰는 동안은 이 서버 순위를 자주 갱신
				for _, b in RankBoards do
					cache[b.id] = localBoard(b.id, b.log)
				end
			end
		end
	end)
end

return Leaderboard
