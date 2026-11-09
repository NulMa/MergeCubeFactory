--!strict
-- 머지 팩토리 프로토타입 서버 부트스트랩

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Core.Net)
local Config = require(ReplicatedStorage.Game.Config)
local Remotes = require(ReplicatedStorage.Game.Remotes)
local Economy = require(ReplicatedStorage.Game.Economy)
local CoreServer = ServerScriptService.CoreServer
local Data = require(CoreServer.Data)
local Receipts = require(CoreServer.Receipts)
local Ledger = require(CoreServer.Ledger)
local Plots = require(script.Plots)
local Factory = require(script.Factory)
local World = require(script.World)
local Leaderboard = require(script.Leaderboard)
local Shop = require(script.Shop)
local Bots = require(script.Bots)

local TEMPLATE = {
	v = 1,
	cash = 0,
	gems = 0,
	rebirths = 0,
	coreBonus = 0,
	droppers = { { tier = 1, lv = 0 }, { tier = 1, lv = 0 } },
	incubators = Economy.START_INCUBATORS,
	upgrades = { polish = 0, lucky = 0, tap = 0, hatch = 0, tray = 0 },
	bat = { range = 0, power = 0, speed = 0, move = 0 }, -- 배트 강화 Lv (젬). move = 이동 속도
	hatching = {}, -- { tier, endsAt, payout }
	coreQueue = {}, -- 등급 목록
	tray = {}, -- 저장 시점 트레이: 등급 숫자 또는 변이 큐브 { t = 등급, v = 변이 id } (Economy.packCube)
	lastSeen = 0,
	lastIncome = 0,
	offlinePending = 0,
	ftue = 0,
	codex = {},
	variants = {}, -- 도감: ["7:Rainbow"] = true (docs/16)
	codexMilestone = 0, -- 받은 도감 마일스톤 수
	codexUnclaimed = {}, -- 발견했지만 아직 안 받은 도감 젬 { [칸 키] = 젬 } (눌러서 받기)
	cosmetics = { owned = {}, equipped = {} }, -- 젬으로 산 꾸미기, 칸별 장착 id (비면 기본값)
	stats = { merges = 0, drops = 0, best = 1, peakIncome = 0 },
	records = { combo = 0, variant = 1, incomeExp = 0 }, -- 개인 기록 (docs/18 §3)
	receipts = {},
	passes = {}, -- 게임 패스 소유 캐시 { cash2x, collector } (server/Shop이 접속 때 다시 확인)
	starterBought = false,
	stealFree = Economy.STEAL_START, -- 큐브 훔치기 무료 횟수 (2분마다 +1, 최대 3)
	stealAt = 0, -- 무료 충전 기준 시각 (0 = 첫 접속 때 지금으로)
	stealPaid = 0, -- 상품으로 산 횟수
	shufflePaid = 0, -- 판매 종료된 Shuffle x3 (늦게 온 영수증 지급용, 2026-10-20)
	hatchCredit = 0, -- 부화 중인 코어 없이 산 Instant Hatch: 다음에 시작하는 코어를 바로 끝낸다
	rateAsked = false, -- 좋아요·즐겨찾기 부탁 창을 봤는지 (client/RatePrompt, 보상 없음)
	starterOfferAt = 0, -- 스타터 팩 제안 창을 마지막으로 띄운 시각 (os.time)
	flashDay = 0, -- 반짝 특가 프렌지 산 날 (Daily.dayOf, Shop.FLASH)
	flashCount = 0, -- 그날 산 횟수
	starterOfferCount = 0, -- 띄운 횟수 (최대 STARTER_OFFER_MAX)
	daily = {}, -- 접속 선물·일일 퀘스트 (server/Daily, 날짜가 바뀌면 새로 만듦)
	shards = 0, -- 펫 조각: 큐브 합치기로만 얻음, Robux로 안 팖 (docs/24)
	pets = { list = {}, equipped = {}, nextUid = 1, seen = {}, hatched = 0 }, -- 펫 인벤토리 (server/Pets)
	bossCoins = 0, -- 보스 레이드 보상 (docs/25), Robux로 안 팖
	boss = { income = 0, speed = 0, resist = 0 }, -- 보스 코인 강화 Lv (리버스로 안 사라짐)
	login = { day = 0, index = 0, claimed = true }, -- 7일 출석 (server/Daily)
}

Plots.init()
local net = Net.serve(Remotes :: any)
Factory.init(net)
Bots.init() -- 사람이 적으면 AI 플레이어 (server/Bots, Config.BOTS)
Leaderboard.init(net)
World.init() -- 광장·랭킹 게시판·다리·꾸밈 (server/World)
Receipts.init()

Shop.init() -- 개발자 상품·게임 패스 (shared/Shop, docs/03 §2)

local function placeCharacter(player: Player, character: Model)
	local cf = Factory.spawnCFrame(player)
	if cf then
		character:PivotTo(cf)
	end
	Factory.onCharacter(player, character)
end

Data.onLoaded:Connect(function(player: Player, data)
	if not Factory.start(player, data) then
		return
	end
	if player.Character then
		placeCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.defer(placeCharacter, player, character)
	end)
end)

Data.onReleasing:Connect(function(player: Player)
	Factory.stop(player)
end)

Data.init({
	store = Config.DATA_STORE .. Config.STUDIO_STORE_SUFFIX,
	template = TEMPLATE,
})

-- Studio 전용 테스트 훅: execute_luau 등 별도 VM에서 require하면 모듈 상태가 따로라 Ledger를 직접 못 부른다.
-- 게시 서버에는 만들지 않는다. 사용: ServerScriptService.StudioDebug:Invoke("cash"|"gems"|"luck"|"grant"|"play", player, amount)
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "StudioDebug"
	hook.OnInvoke = function(cmd: string, player: Player, amount: number)
		if cmd == "cash" or cmd == "gems" then
			return Ledger.credit(player, cmd, amount, "Gameplay", "studio_debug", false)
		elseif cmd == "luck" then
			-- 변이 확률 배율 (예: 200이면 합치기 Metallic 4% → 사실상 매번 변이). 1로 되돌림
			return Factory.debugLuck(player, amount)
		elseif cmd == "stealSelf" or cmd == "knock" then
			-- 혼자 훔치기 확인: 내 트레이에서 훔치고 광장이 집 / 배트 넉백 연출
			require(script.Steal).debug(player, if cmd == "knock" then "knock" else "self")
			return true
		elseif cmd == "fill" then
			-- 트레이 채우기: amount = "등급:개수" (예: "25:50")
			local t, n = string.match(tostring(amount), "^(%d+):(%d+)$")
			return Factory.debugFill(player, tonumber(t) or 5, tonumber(n) or 50)
		elseif cmd == "stats" then
			-- 측정용: 합치기·투하 누적 수 (docs/27 A/B)
			local data = Data.get(player)
			return data and { merges = data.stats.merges, drops = data.stats.drops }
		elseif cmd == "droppers" then
			-- 후반 드로퍼 재현: amount = "등급:레벨" → 드로퍼 8개 모두 (렉 측정용)
			local data = Data.get(player)
			local t, lv = string.match(tostring(amount), "^(%d+):(%d+)$")
			-- 되돌리기: amount = "get"이 돌려준 JSON 그대로
			if data and string.sub(tostring(amount), 1, 1) == "{" then
				local saved = game:GetService("HttpService"):JSONDecode(tostring(amount))
				data.droppers = saved.droppers
				data.rebirths = saved.rebirths
				Factory.refresh(player)
				return true
			end
			if data and tostring(amount) == "get" then
				return game:GetService("HttpService"):JSONEncode({ droppers = data.droppers, rebirths = data.rebirths })
			end
			if data and t then
				table.clear(data.droppers)
				for _ = 1, 8 do
					table.insert(data.droppers, { tier = tonumber(t), lv = tonumber(lv) })
				end
				Factory.refresh(player)
				return true
			end
		elseif cmd == "rebirths" then
			-- 리버스 횟수 강제 (합치기 상한 확인용). 저장은 Studio 전용 스토어
			local data = Data.get(player)
			if data then
				data.rebirths = amount
				return true
			end
		elseif cmd == "core" then
			-- 코어 지급 (amount = 등급, 5 이상)
			return Factory.debugCore(player, amount)
		elseif cmd == "grant" then
			-- 결제 없이 상품·패스 지급 로직 실행. amount 자리에 Shop 항목 key (예: "starter", "cash2x")
			return Shop.grant(player, amount :: any)
		elseif cmd == "cosmetic" then
			-- 꾸미기 강제 해금 + 장착 (amount 자리에 꾸미기 id)
			local data = Data.get(player)
			local plot = nil
			for _, m in workspace.Plots:GetChildren() do
				if m:GetAttribute("OwnerUserId") == player.UserId then
					plot = m
				end
			end
			if data and plot then
				data.cosmetics.owned[amount] = true
				return require(script.Collection).equip(player, data, plot, amount :: any)
			end
		elseif cmd == "pet" then
			-- 펫 지급: amount = "id:별" (예: "tiger:3")
			local id, star = string.match(tostring(amount), "^([%w_]+):?(%d?)$")
			return Factory.debugPet(player, id or "", tonumber(star) or 1)
		elseif cmd == "raid" then
			-- 보스 레이드: amount = "start"(지금 초대) | "fight"(초대 끝내고 바로 전투) | "low"(보스 체력 1)
			require(script.Raid).debug(tostring(amount))
			return true
		elseif cmd == "boss" then
			return Ledger.credit(player, "bossCoins", amount, "Gameplay", "studio_debug", false)
		elseif cmd == "shards" then
			return Ledger.credit(player, "shards", amount, "Gameplay", "studio_debug", false)
		elseif cmd == "bots" then
			-- AI 플레이어: amount = 숫자(봇 수 고정, -1 자동) | "steal"(봇 하나가 지금 이 사람을 턴다, 촬영용)
			if tostring(amount) == "steal" then
				return Bots.debug("steal", player)
			end
			return Bots.debug("count", player, tonumber(amount))
		elseif cmd == "play" then
			-- 오늘 플레이 시간 더하기 (접속 선물 확인용, 초)
			local data = Data.get(player)
			if data then
				require(script.Daily).debugPlay(data, amount)
				return true
			end
		end
		return false
	end
	hook.Parent = ServerScriptService
end

Players.PlayerRemoving:Connect(function(player)
	-- 데이터 로드 전에 나간 경우에도 플롯이 남지 않게
	Factory.stop(player)
end)
