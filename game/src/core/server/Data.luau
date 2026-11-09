--!strict
-- 플레이어 데이터 (ProfileStore 세션 잠금, docs/06 §4)
-- 사용: Data.init({ store = "MergeCubeFactory", template = {...}, migrate = fn? })
--       Data.onLoaded:Connect(function(player, data) ... end)
--       Data.get(player) -> data? (로드 전이면 nil — 로드 전에는 보상·구매를 하지 않는다)
-- Studio에서 API 접근이 꺼져 있으면 ProfileStore가 자동으로 Mock 저장소를 쓴다.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Signal = require(game:GetService("ReplicatedStorage").Core.Signal)
local ProfileStore = require(ServerStorage.Vendor.ProfileStore) :: any

export type Options = {
	store: string,
	template: { [string]: any },
	migrate: ((data: { [string]: any }) -> ())?, -- data.v를 올리는 함수. Reconcile 전에 호출
}

local Data = {}
Data.onLoaded = Signal.new()
Data.onReleasing = Signal.new() -- (player, data) 세션 종료 직전, 마지막 기록 기회

local profiles: { [Player]: any } = {}
local store: any = nil
local options: Options

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function load(player: Player)
	local profile = store:StartSessionAsync(key(player), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		-- 다른 서버가 잠금을 오래 쥐고 있거나 DataStore 장애: 진행을 잃는 것보다 재접속을 요청한다
		player:Kick("Could not load your data. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId) -- GDPR 삭제 요청 대응
	if options.migrate then
		options.migrate(profile.Data)
	end
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was loaded on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	Data.onLoaded:Fire(player, profile.Data)
end

function Data.init(opts: Options)
	options = opts
	store = ProfileStore.New(opts.store, opts.template)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			Data.onReleasing:Fire(player, profile.Data)
			profile:EndSession()
		end
	end)
end

function Data.get(player: Player): { [string]: any }?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function Data.isActive(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

-- 결제 직후처럼 즉시 저장이 필요할 때
function Data.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

-- 저장하고 check(저장된 데이터)가 참이 될 때까지 기다린다 (최대 timeout초). 결제 확정 전에 쓴다 (2026-10-20 리뷰)
function Data.saveAndWait(player: Player, check: (saved: { [string]: any }) -> boolean, timeout: number): boolean
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return false
	end
	local done = false
	local conn = profile.OnAfterSave:Connect(function(saved)
		if check(saved) then
			done = true
		end
	end)
	profile:Save()
	local t0 = os.clock()
	while not done and os.clock() - t0 < timeout do
		if profile.LastSavedData and check(profile.LastSavedData) then
			done = true
			break
		end
		task.wait(0.25)
	end
	conn:Disconnect()
	return done
end

return Data
