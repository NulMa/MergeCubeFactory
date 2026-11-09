--!strict
-- Remote 계약을 한 곳에서 정의한다 (docs/06 §6).
-- 서버: Net.serve(spec) → ReplicatedStorage.Remotes 아래 인스턴스 생성 + 인자 검증 래퍼.
-- 클라: Net.client(spec) → 같은 이름으로 기다려서 가져온다.
--
-- spec 예:
--   { DropAt = { kind = "event", args = { "number" } },
--     Buy    = { kind = "function", args = { "string" } },
--     State  = { kind = "event" },     -- 서버 → 클라 전용은 args 생략
--     Snap   = { kind = "unreliable" } } -- 서버 → 클라 비신뢰(UnreliableRemoteEvent): 순서·도착 보장 없음, 900바이트 이하
-- 검증 실패한 호출은 조용히 버린다(악성 클라이언트에 오류 메시지를 주지 않음).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteSpec = { kind: "event" | "function" | "unreliable", args: { string }? }
export type Spec = { [string]: RemoteSpec }

local Net = {}

local FOLDER = "Remotes"
-- 플레이어당 초당 호출 상한 (06 §5 "Remote 빈도")
local RATE_PER_SEC = 20

local function validArgs(types: { string }?, ...: any): boolean
	if not types then
		return select("#", ...) == 0
	end
	if select("#", ...) ~= #types then
		return false
	end
	for i, t in types do
		local v = select(i, ...)
		if typeof(v) ~= t then
			return false
		end
		if t == "number" and (v ~= v or v == math.huge or v == -math.huge) then
			return false
		end
		if t == "string" and #v > 200 then
			return false
		end
	end
	return true
end

local buckets: { [Player]: { t: number, n: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b or now - b.t >= 1 then
		buckets[player] = { t = now, n = 1 }
		return true
	end
	b.n += 1
	return b.n <= RATE_PER_SEC
end

export type Server = {
	on: (name: string, handler: (player: Player, ...any) -> ...any) -> (),
	fire: (name: string, player: Player, ...any) -> (),
	fireAll: (name: string, ...any) -> (),
}

function Net.serve(spec: Spec): Server
	assert(RunService:IsServer(), "Net.serve is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER) or Instance.new("Folder")
	folder.Name = FOLDER
	local remotes: { [string]: Instance } = {}
	for name, def in spec do
		local class = if def.kind == "event"
			then "RemoteEvent"
			elseif def.kind == "unreliable" then "UnreliableRemoteEvent"
			else "RemoteFunction"
		local r = Instance.new(class)
		r.Name = name
		r.Parent = folder
		remotes[name] = r
	end
	folder.Parent = ReplicatedStorage
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)

	local server = {}
	function server.on(name: string, handler: (Player, ...any) -> ...any)
		local def = spec[name]
		assert(def and def.args, "unknown or server-only remote: " .. name)
		local r = remotes[name]
		assert(not r:IsA("UnreliableRemoteEvent"), "unreliable remotes are server -> client only: " .. name)
		if r:IsA("RemoteEvent") then
			r.OnServerEvent:Connect(function(player, ...)
				if allow(player) and validArgs(def.args, ...) then
					handler(player, ...)
				end
			end)
		else
			(r :: RemoteFunction).OnServerInvoke = function(player, ...)
				if allow(player) and validArgs(def.args, ...) then
					return handler(player, ...)
				end
				return nil
			end
		end
	end
	function server.fire(name: string, player: Player, ...)
		(remotes[name] :: any):FireClient(player, ...) -- RemoteEvent 또는 UnreliableRemoteEvent
	end
	function server.fireAll(name: string, ...)
		(remotes[name] :: any):FireAllClients(...)
	end
	return server :: Server
end

function Net.client(spec: Spec): { [string]: Instance }
	local folder = ReplicatedStorage:WaitForChild(FOLDER)
	local out = {}
	for name in spec do
		out[name] = folder:WaitForChild(name)
	end
	return out
end

Net._validArgs = validArgs -- 테스트용

return Net
