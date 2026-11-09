--!strict
-- SimBackend: 큐브 몸 = TraySim 슬롯 (Roblox Part·물리 없음, docs/27 단계 4, Config.DATA_CUBES).
-- 플롯마다 TraySim 하나 + CubeNet 채널 하나. body = 큐브 id. 위치는 월드 좌표로 주고받고 안에서 플롯 중심 기준으로 바꾼다.
-- 등급·변이·MAX 표시는 데이터(look)로만 들고 retier op로 복제한다. 파트는 클라이언트(client/CubeView)가 만든다.
-- 모든 플롯 시뮬은 Heartbeat 하나에서 돌리고(SimBackend.start), 이어서 CubeNet.flush.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local TraySim = require(Shared.TraySim)
local CubeCodec = require(Shared.CubeCodec)
local Plots = require(script.Parent.Plots)
local CubeNet = require(script.Parent.CubeNet)
local CubeWorld = require(script.Parent.CubeWorld)

type Look = { tier: number, variant: number, atMax: boolean }
type Entry = {
	plot: Plots.Plot,
	sim: TraySim.Sim,
	width: number,
	ticks: number, -- 돈 고정 스텝 수 = 시뮬 시계 (CubeNet 스냅샷 시간 기준, 데드 레코닝)
}

local SimBackend = {}

-- 밑면이 이보다 높고 옆이 빈 외줄 큐브는 무너뜨린다 (벽 높이의 절반, TraySim slumpY). 고정 드로퍼 밑 탑 방지
SimBackend.SLUMP_Y = Config.TRAY_SIZE.Y * 0.5

local live: { [Entry]: boolean } = {}
local started = false

function SimBackend.new(plot: Plots.Plot): CubeWorld.Backend
	local center = plot.center
	local half = plot.width / 2
	local gravity = workspace.Gravity -- 자석 깡충(Factory.magnet)이 같은 중력으로 공중 시간을 잰다. 클라 예측(CubeView)도 workspace.Gravity
	local sim = TraySim.new({
		halfX = half,
		halfZ = half,
		floorY = 0,
		ceilY = Plots.GUARD_TOP, -- 보이지 않는 천장 가드와 같은 높이 (벽은 천장까지 이어진 것으로 본다)
		slumpY = SimBackend.SLUMP_Y,
		gravity = gravity,
	})
	local entry: Entry = { plot = plot, sim = sim, width = plot.width, ticks = 0 }
	live[entry] = true
	local looks: { [number]: Look } = {}

	local ch = CubeNet.open(plot, {
		entries = function()
			local out: { CubeCodec.ResetEntry } = {}
			for id, l in looks do
				local x, y, z = sim:position(id)
				table.insert(out, { id = id, tier = l.tier, variant = l.variant, x = x, y = y, z = z, atMax = l.atMax })
			end
			return out
		end,
		eachAwake = function(fn)
			sim:eachAwake(fn)
		end,
		has = function(id)
			return sim:has(id)
		end,
		position = function(id)
			return sim:position(id)
		end,
		tick = function()
			return entry.ticks
		end,
		gravity = gravity,
	})

	local function forget(id: number, reason: number)
		if not sim:has(id) then
			return
		end
		sim:remove(id)
		looks[id] = nil
		CubeNet.remove(ch, id, reason)
	end

	local backend: CubeWorld.Backend = {
		create = function(_plot, id, tier, variant, position, atMax)
			local p = position - center
			sim:add(id, p.X, p.Y, p.Z, Config.cubeSize(tier) / 2)
			looks[id] = { tier = tier, variant = variant, atMax = atMax }
			CubeNet.spawn(ch, id, tier, variant, p.X, p.Y, p.Z, 0, 0, 0, atMax)
			return id
		end,
		destroy = function(body, reason)
			forget(body :: number, reason)
		end,
		alive = function(body)
			return sim:has(body :: number)
		end,
		position = function(body)
			local x, y, z = sim:position(body :: number)
			return center + Vector3.new(x, y, z)
		end,
		velocity = function(body)
			return Vector3.new(sim:velocity(body :: number))
		end,
		setVelocity = function(body, v)
			sim:setVelocity(body :: number, v.X, v.Y, v.Z)
		end,
		setAngular = function(_body, _v)
			-- 회전은 클라이언트 연출 (CubeView: 공중 속도에 비례해 굴림)
		end,
		teleport = function(body, cf)
			local id = body :: number
			local l = looks[id]
			if not l then
				return
			end
			local p = cf.Position - center
			sim:teleport(id, p.X, p.Y, p.Z)
			-- 클라이언트가 날아가는 것처럼 보간하지 않게 지웠다가 새로 만든다 (트레이 위로 되돌림 = 다시 떨어짐)
			CubeNet.remove(ch, id, CubeCodec.REASON_OTHER)
			local x, y, z = sim:position(id)
			CubeNet.spawn(ch, id, l.tier, l.variant, x, y, z, 0, 0, 0, l.atMax)
		end,
		size = function(body)
			return sim:half(body :: number) * 2
		end,
		restyle = function(body, tier, variant)
			local id = body :: number
			local l = looks[id]
			if not l then
				return
			end
			local h = Config.cubeSize(tier) / 2
			if math.abs(sim:half(id) - h) > 1e-6 then
				-- 크기가 바뀜(합치기): 위치·속도는 그대로 두고 슬롯을 다시 넣는다. 커진 만큼은 다음 스텝 제약이 밀어낸다
				local x, y, z = sim:position(id)
				local vx, vy, vz = sim:velocity(id)
				sim:remove(id)
				sim:add(id, x, y, z, h, vx, vy, vz)
			end
			l.tier, l.variant = tier, variant
			CubeNet.retier(ch, id, tier, variant, l.atMax)
		end,
		markCeiling = function(body, atMax)
			local id = body :: number
			local l = looks[id]
			if l and l.atMax ~= atMax then
				l.atMax = atMax
				CubeNet.retier(ch, id, l.tier, l.variant, atMax)
			end
		end,
		partOf = function(_body)
			return nil
		end,
		release = function(body)
			-- 훔치기: 데이터에서 빼고(클라이언트는 steal 사유로 지움) 들기용 파트는 부르는 쪽이 새로 만든다
			forget(body :: number, CubeCodec.REASON_STEAL)
			return nil
		end,
		close = function()
			live[entry] = nil
			table.clear(looks)
			CubeNet.close(ch)
		end,
	}
	return backend
end

-- 한 번만: 모든 플롯 시뮬을 같은 Heartbeat에서 dt만큼 돌리고 복제
function SimBackend.start(net: any)
	if started then
		return
	end
	started = true
	CubeNet.init(net)
	RunService.Heartbeat:Connect(function(dt)
		for e in live do
			-- 트레이 확장 강화(Plots.setWidth)로 폭이 바뀌면 벽을 옮긴다
			if e.plot.width ~= e.width then
				e.width = e.plot.width
				e.sim:resize(e.width / 2, e.width / 2)
			end
			e.ticks += e.sim:step(dt)
		end
		CubeNet.flush(dt)
	end)
end

return SimBackend
