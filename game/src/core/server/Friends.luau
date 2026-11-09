--!strict
-- 친구 확인 캐시 (2026-10-20 "친구 보너스": 협동 보너스를 친구끼리만, 양쪽 모두에게).
-- IsFriendsWith는 웹 호출이라 들어올 때 한 번씩 비동기로 묻고 결과를 둔다 (모르면 친구 아님).

local Players = game:GetService("Players")

local Friends = {}

local known: { [Player]: { [Player]: boolean } } = {}

local function ask(a: Player, b: Player)
	task.spawn(function()
		local ok, yes = pcall(function()
			return a:IsFriendsWithAsync(b.UserId)
		end)
		local v = ok and yes == true
		if a.Parent and b.Parent then
			known[a] = known[a] or {}
			known[b] = known[b] or {}
			known[a][b] = v
			known[b][a] = v
		end
	end)
end

function Friends.are(a: Player, b: Player): boolean
	local k = known[a]
	return k ~= nil and k[b] == true
end

-- 이 서버에 친구가 있나 (초대 안내용)
function Friends.any(player: Player): boolean
	local k = known[player]
	if not k then
		return false
	end
	for other, yes in k do
		if yes and other.Parent then
			return true
		end
	end
	return false
end

function Friends.init()
	local function added(p: Player)
		known[p] = known[p] or {}
		for _, other in Players:GetPlayers() do
			if other ~= p then
				ask(p, other)
			end
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		known[p] = nil
		for _, k in known do
			k[p] = nil
		end
	end)
end

return Friends
