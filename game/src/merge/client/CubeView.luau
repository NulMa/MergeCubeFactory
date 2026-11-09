--!strict
-- 데이터 큐브 보기 (docs/27 단계 4, Config.DATA_CUBES). 서버는 큐브를 데이터(TraySim)로만 들고 CubeNet으로 보낸다.
-- 여기서 플롯마다 큐브 엔티티를 들고, 그 플롯의 Cubes 폴더(복제된 폴더) 안에 로컬 파트를 만든다(이 클라이언트에만 있음).
--   * 겉모습은 서버 PartBackend와 같은 shared/CubeStyle (크기·색·재질·변이 장식·Tier/AtMax/Variant 속성)
--     + CubeId 속성 → CubeLook(얼굴·숫자)·CubeLod·CubeInventory·Steal·Fx가 예전처럼 폴더·속성만 보고 동작한다.
--   * 파트: Anchored, CanCollide 끔, CanQuery 켬(마우스·레이), CanTouch 끔, 충돌 그룹 Cubes.
--   * 파트 풀 (2026-10-22): 지운 큐브 파트는 부모를 떼어(nil) 풀에 넣고(최대 POOL_MAX), 새 큐브는 풀에서 꺼내 CubeStyle.reuse로 다시 입힌다.
--     폴더에 다시 넣으므로 ChildAdded(투하 연출·CubeLook)는 그대로 불린다. CubeLook 얼굴·숫자는 파트에 남아 Tier 속성 변화로 갈아 끼운다.
--     넣을 때 변이 장식·VariantCube 태그·MAX 표시와 클라 연출 상태(CubeLod LodOff·CubeInventory FocusOff·흐리기)를 되돌린다.
--   * 움직임 (데드 레코닝, 2026-10-22): 서버는 예측과 어긋날 때만 보정을 보낸다 (server/CubeNet, shared/CubePredict).
--     샘플 = (시각, 위치, 속도, air). 렌더 시각(지금 − 지연)에서 지나간 마지막 샘플로 예측(air면 중력 포물선, 아니면 직선),
--     다음 샘플이 이미 와 있으면 그 직전 한 간격(스냅샷 주기) 동안 다음 샘플로 섞는다(에르미트, 속도가 확 바뀌면 직선).
--     늦게 와서 지금 그림을 바꾸는 보정은 그 차이를 err로 들고 ~100ms에 걸쳐 0으로 줄인다 (튀지 않게).
--     마지막 샘플 뒤로 CubePredict.HORIZON(1.25초) 넘게 아무것도 안 오면(보정을 잃음) 그 자리에 멈춘다(서버도 같은 한도로 예측). 서버 keepalive는 1초.
--   * 시간: 스냅샷 헤더의 시뮬 틱을 받은 시각에 맞춘다. offset = min(받은 시각 − 틱×DT)(가장 빨리 온 패킷 기준, 천천히 올라감)
--     → 샘플 시각 = 틱×DT + offset. 서버 예측(틱 차이)과 클라 예측(시각 차이)이 같은 t를 쓰고, 네트워크·Heartbeat 흔들림이 위치에 안 섞인다.
--     지연 = 스냅샷 주기 × 1.5 (0.1~0.35초: 주인 100ms, 근처 300ms). spawn·reset(신뢰, 틱 없음)은 받은 시각에 놓고, 서버가 다음 스냅샷에서 맞춘다.
--   * 회전(연출만, 서버는 AABB): 생길 때 무작위 방향, 공중에서 수평 속도에 비례해 굴림, 내려앉으면 가장 가까운 90°로.
--   * 착지: 렌더 시각이 샘플을 지날 때, 앞 샘플로 예측한 들어오는 세로 속도가 빠르게(< −14) 떨어지다 그 샘플이 > −3이면 onLand.
-- 순서: 신뢰(CubeEvt)와 비신뢰(CubeSnap)는 서로 순서가 없다 → 모르는 id의 스냅샷 항목은 잠깐 들고 있다가(pending) spawn이 오면 그것부터 쓴다.
-- gen: 플롯 주인이 바뀔 때마다 새 번호. 다른 gen의 스냅샷은 버린다 (새 주인은 id를 1부터 다시 쓴다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Game.Config)
local CubeCodec = require(ReplicatedStorage.Game.CubeCodec)
local CubePredict = require(ReplicatedStorage.Game.CubePredict)
local CubeStyle = require(ReplicatedStorage.Game.CubeStyle)

type Sample = { t: number, p: Vector3, v: Vector3, air: boolean }

type Entity = {
	id: number,
	tier: number,
	variant: number,
	atMax: boolean,
	part: Part,
	samples: { Sample }, -- 시각 순 (플롯 중심 기준이 아니라 월드 좌표)
	err: Vector3, -- 보정 섞기: 보이는 자리 = 예측 + err, err은 BLEND_TAU로 0이 됨
	rot: CFrame, -- 보이는 회전 (연출)
	settled: boolean, -- 회전이 90° 단위로 맞춰짐
	holdUntil: number, -- 막 생긴 큐브는 이때까지 무작위 방향 그대로 (떨어지기 시작 전에 맞추지 않게)
	plot: PlotView,
}

export type PlotView = {
	index: number,
	model: Model,
	folder: Instance,
	center: Vector3, -- 트레이 바닥 윗면 가운데 (서버 plot.center)
	gen: number,
	seq: number,
	period: number, -- 스냅샷 주기 (헤더 hz: 주인 1/15, 근처 1/5)
	tick: number?, -- 마지막 시뮬 틱 (감김 풀어 둔 값)
	offset: number?, -- 클라 시각 − 시뮬 시각 (가장 빨리 온 패킷 기준)
	entities: { [number]: Entity },
	pending: { [number]: Sample }, -- spawn보다 먼저 온 스냅샷 항목
}

local CubeView = {}

local MAX_SAMPLES = 6
local SNAP_DIST = 20 -- 보정이 이보다 멀면 섞지 않고 바로 옮김 (순간이동)
local BLEND_TAU = 0.035 -- 보정 차이 줄이는 시간 상수 (100ms면 ~6%만 남음)
local LINEAR_DV = 30 -- 섞는 두 끝 속도 차가 이보다 크면(부딪힘) 에르미트 대신 직선
local OFFSET_RISE = 0.05 -- 시각 offset이 올라갈 때(지연이 늘어남) 패킷마다 따라가는 비율
local PENDING_AGE = 1 -- spawn보다 먼저 온 항목을 이 초까지 들고 있음
local POOL_MAX = 150 -- 풀에 남겨 둘 파트 수 (넘으면 지움)
local LAND_FROM = -14 -- init.client 착지 판정과 같음: 이보다 빠르게 떨어지다가
local LAND_TO = -3 -- 이보다 느려지면 착지
local AIR_VY = 3 -- 세로 속도가 이보다 크면 공중
local TUMBLE = 0.6 -- 굴림 각속도 = 수평 속도 / 반 변 × 이 값
local SETTLE_RATE = 14 -- 90° 맞추기 속도 (초당)

local plots: { [number]: PlotView } = {}
local active: { [Entity]: boolean } = {}
local landHandlers: { (Model, BasePart, number, number) -> () } = {}
local pool: { Part } = {}
local gravity = workspace.Gravity -- 서버 SimBackend도 workspace.Gravity (렌더마다 다시 읽음)

local AXES = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
local LOCAL_FLAGS = { "LodOff", "FocusOff" } -- client/CubeLod·CubeInventory가 끈 것 표시

-- 가장 가까운 축 정렬 회전 (90° 단위)
local function nearestAxis(v: Vector3, used: Vector3?): Vector3
	local best, bestDot = Vector3.xAxis, -math.huge
	for _, a in AXES do
		if used == nil or math.abs(a:Dot(used)) < 0.5 then
			local d = v:Dot(a)
			if d > bestDot then
				best, bestDot = a, d
			end
		end
	end
	return best
end

local function snap90(cf: CFrame): CFrame
	local x = nearestAxis(cf.XVector, nil)
	local y = nearestAxis(cf.YVector, x)
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local function delayOf(pv: PlotView): number
	return math.clamp(pv.period * 1.5, 0.1, 0.35)
end

-- ===== 파트 풀 =====

-- 다른 클라 모듈이 이 파트에 남긴 화면 상태를 되돌린다 (다음 큐브가 흐리거나 숫자가 꺼진 채 나오지 않게)
local function clearLocal(part: Part)
	part.LocalTransparencyModifier = 0
	for _, d in part:GetDescendants() do
		if d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = 0
		end
		for _, key in LOCAL_FLAGS do
			if d:GetAttribute(key) then
				if d:IsA("SelectionBox") then
					d.Visible = true
				else
					(d :: any).Enabled = true
				end
				d:SetAttribute(key, nil)
			end
		end
	end
end

local function park(part: Part)
	part.Parent = nil
	if #pool >= POOL_MAX then
		part:Destroy()
		return
	end
	part:SetAttribute("CubeId", nil)
	CubeStyle.park(part) -- 변이 장식·태그·MAX 지우기
	clearLocal(part)
	table.insert(pool, part)
end

local function takePart(tier: number, variant: number, atMax: boolean, cf: CFrame): Part
	local part = table.remove(pool)
	if part then
		CubeStyle.reuse(part, tier, variant, atMax, cf)
		return part
	end
	local p = CubeStyle.part(tier, variant, atMax, cf)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	return p
end

-- ===== 예측·보간 =====

local function resting(s: Sample): boolean
	return not s.air and s.v == Vector3.zero
end

-- 샘플에서 dt초 뒤 (shared/CubePredict, 서버와 같은 식). HORIZON 넘으면 그 자리
local function predict(s: Sample, dt: number): (Vector3, Vector3)
	if dt <= 0 or resting(s) then
		return s.p, s.v
	end
	local x, y, z, vx, vy, vz = CubePredict.at(s.p.X, s.p.Y, s.p.Z, s.v.X, s.v.Y, s.v.Z, s.air, gravity, dt)
	return Vector3.new(x, y, z), Vector3.new(vx, vy, vz)
end

local function hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, h: number, u: number): Vector3
	local u2, u3 = u * u, u * u * u
	return p0 * (2 * u3 - 3 * u2 + 1) + v0 * (h * (u3 - 2 * u2 + u)) + p1 * (-2 * u3 + 3 * u2) + v1 * (h * (u3 - u2))
end

-- 렌더 시각 rt의 위치·속도 (샘플을 바꾸지 않음). 아직 움직이는 중이면 true
local function evaluate(e: Entity, rt: number): (Vector3, Vector3, boolean)
	local samples = e.samples
	local i = 1
	if rt <= samples[1].t then
		return samples[1].p, samples[1].v, true -- 아직 첫 샘플 전 (막 생김)
	end
	while samples[i + 1] and samples[i + 1].t <= rt do
		i += 1
	end
	local a, b = samples[i], samples[i + 1]
	local p, v = predict(a, rt - a.t)
	if b then
		-- 다음 보정이 와 있으면 그 직전 한 주기 동안 섞는다 (자유 비행은 에르미트가 포물선을 그대로 그림)
		local w = math.min(b.t - a.t, e.plot.period)
		local s = b.t - w
		if w > 0 and rt > s then
			local p0, v0 = predict(a, s - a.t)
			local u = (rt - s) / w
			if (b.v - v0).Magnitude > LINEAR_DV then
				return p0:Lerp(b.p, u), v0:Lerp(b.v, u), true
			end
			return hermite(p0, v0, b.p, b.v, w, u), v0:Lerp(b.v, u), true
		end
		return p, v, true
	end
	if resting(a) or rt - a.t >= CubePredict.HORIZON then
		return p, Vector3.zero, false
	end
	return p, v, true
end

-- 렌더 시각이 지나간 샘플 버리기 + 착지 판정 (샘플마다 한 번)
local function advance(e: Entity, rt: number)
	local samples = e.samples
	while #samples >= 2 and samples[2].t <= rt do
		local a, b = samples[1], samples[2]
		local _, vIn = predict(a, b.t - a.t) -- 앞 샘플로 예측한, 이 샘플로 들어오는 속도
		local vyIn = vIn.Y
		if vyIn < LAND_FROM and b.v.Y > LAND_TO then
			for _, fn in landHandlers do
				task.spawn(fn, e.plot.model, e.part, e.tier, -vyIn)
			end
		end
		table.remove(samples, 1)
	end
end

local function pushSample(e: Entity, t: number, p: Vector3, v: Vector3, air: boolean)
	local samples = e.samples
	local last = samples[#samples]
	if last and t <= last.t then
		t = last.t + 1e-3 -- 같은 시각(받은 시각에 놓은 spawn·reset 뒤 스냅샷 등): 새 정보가 뒤로
	end
	local rt = os.clock() - delayOf(e.plot)
	local before: Vector3? = nil
	if last then
		local pp = predict(last, t - last.t)
		if (p - pp).Magnitude > SNAP_DIST then
			table.clear(samples) -- 순간이동: 날아가는 것처럼 보이지 않게
			e.err = Vector3.zero
		else
			before = (evaluate(e, rt))
		end
	end
	table.insert(samples, { t = t, p = p, v = v, air = air })
	while #samples > MAX_SAMPLES do
		table.remove(samples, 1)
	end
	if before then
		-- 이 보정이 지금 보이는 자리를 바꾸면 그 차이를 err로 옮겨 천천히 줄인다
		local d = e.err + (before - (evaluate(e, rt)))
		e.err = if d.Magnitude < SNAP_DIST then d else Vector3.zero
	end
	active[e] = true
end

-- ===== 엔티티 =====

local function destroyEntity(e: Entity)
	active[e] = nil
	e.plot.entities[e.id] = nil
	park(e.part)
end

local function clearPlot(pv: PlotView)
	for _, e in pv.entities do
		destroyEntity(e)
	end
	table.clear(pv.pending)
end

local function createEntity(
	pv: PlotView,
	id: number,
	tier: number,
	variant: number,
	atMax: boolean,
	p: Vector3,
	v: Vector3,
	air: boolean
)
	local old = pv.entities[id]
	if old then
		destroyEntity(old)
	end
	local now = os.clock()
	local first: Sample = { t = now, p = p, v = v, air = air }
	local pend = pv.pending[id]
	if pend then
		pv.pending[id] = nil
		if now - pend.t < PENDING_AGE then
			first = pend -- spawn보다 먼저 온 스냅샷: 틱이 실린 더 정확한 상태
		end
	end
	local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
	-- CFrame·속성을 먼저 정하고 폴더에 넣는다 (ChildAdded 쪽이 위치·Tier·CubeId를 바로 읽음)
	local part = takePart(tier, variant, atMax, CFrame.new(first.p) * rot)
	part:SetAttribute("CubeId", id)
	local e: Entity = {
		id = id,
		tier = tier,
		variant = variant,
		atMax = atMax,
		part = part,
		samples = { first },
		err = Vector3.zero,
		rot = rot,
		settled = false,
		holdUntil = now + 0.35,
		plot = pv,
	}
	pv.entities[id] = e
	active[e] = true
	part.Parent = pv.folder
end

local function restyle(e: Entity, tier: number, variant: number, atMax: boolean)
	if e.tier ~= tier or e.variant ~= variant then
		e.tier, e.variant = tier, variant
		CubeStyle.apply(e.part, tier, variant)
	end
	if e.atMax ~= atMax then
		e.atMax = atMax
		CubeStyle.markCeiling(e.part, atMax)
	end
end

local function onEvents(pv: PlotView, gen: number, ops: { CubeCodec.Op })
	if gen ~= pv.gen then
		-- 새 주인(또는 빈 플롯): 옛 엔티티는 모두 버린다. 서버는 새 gen의 첫 메시지로 reset을 보낸다
		clearPlot(pv)
		pv.gen = gen
		pv.seq = -1
		pv.tick = nil
		pv.offset = nil
	end
	local now = os.clock()
	local c = pv.center
	for _, op in ops do
		if op.kind == "spawn" then
			-- 새 큐브는 떨어지는 중으로 본다 (드로퍼·되돌리기). 서버가 다음 스냅샷에서 틱 실린 상태로 맞춘다
			createEntity(
				pv,
				op.id,
				op.tier,
				op.variant,
				false,
				c + Vector3.new(op.x, op.y, op.z),
				Vector3.new(op.vx, op.vy, op.vz),
				true
			)
		elseif op.kind == "remove" then
			-- 합치기 연출은 Merged 이벤트(Fx.merge)가 한다. 여기선 지우기만
			local e = pv.entities[op.id]
			if e then
				destroyEntity(e)
			end
			pv.pending[op.id] = nil
		elseif op.kind == "retier" then
			local e = pv.entities[op.id]
			if e then
				restyle(e, op.tier, op.variant, op.atMax)
			end
		elseif op.kind == "reset" then
			-- 전체 목록으로 맞춘다: 없는 것은 지우고, 있는 것은 겉모습·위치만 고치고(파트 유지), 새것은 만든다.
			-- 위치만 오므로 정지로 둔다. 깨어 있는 큐브는 서버가 다음 스냅샷에 모두 다시 보낸다 (CubeNet이 아는 상태를 비움)
			table.clear(pv.pending)
			local keep: { [number]: boolean } = {}
			for _, en in op.entries do
				keep[en.id] = true
				local p = c + Vector3.new(en.x, en.y, en.z)
				local e = pv.entities[en.id]
				if e then
					restyle(e, en.tier, en.variant, en.atMax)
					pushSample(e, now, p, Vector3.zero, false)
				else
					createEntity(pv, en.id, en.tier, en.variant, en.atMax, p, Vector3.zero, false)
				end
			end
			for id, e in pv.entities do
				if not keep[id] then
					destroyEntity(e)
				end
			end
		end
	end
end

-- 헤더 틱(16비트 감김) → 이 클라 시각
local function sampleTime(pv: PlotView, tick16: number, now: number): number
	local last = pv.tick
	local tick = tick16
	if last then
		local d = (tick16 - last) % 65536
		if d >= 32768 then
			d -= 65536
		end
		tick = last + d
		if d > 0 then
			pv.tick = tick
		end
	else
		pv.tick = tick
	end
	local simT = tick * CubePredict.DT
	local off = now - simT
	local offset = pv.offset
	if offset == nil or off < offset then
		pv.offset = off -- 더 빨리 온 패킷 = 지연이 더 짧음
	else
		pv.offset = offset + (off - offset) * OFFSET_RISE
	end
	return simT + (pv.offset :: number)
end

local function onSnapshot(pv: PlotView, gen: number, head: CubeCodec.SnapHeader, entries: { CubeCodec.SnapEntry })
	if gen ~= pv.gen then
		return
	end
	-- 늦게 온 옛 스냅샷은 버림 (같은 seq = 나뉜 조각, 받음)
	local seq = head.seq
	if pv.seq >= 0 and (seq - pv.seq) % 65536 >= 32768 then
		return
	end
	pv.seq = seq
	pv.period = 1 / math.max(head.hz, 1)
	local now = os.clock()
	local t = sampleTime(pv, head.tick, now)
	local c = pv.center
	for _, en in entries do
		local p = c + Vector3.new(en.x, en.y, en.z)
		local v = Vector3.new(en.vx, en.vy, en.vz)
		local e = pv.entities[en.id]
		if e then
			pushSample(e, t, p, v, en.air)
		else
			pv.pending[en.id] = { t = t, p = p, v = v, air = en.air } -- spawn보다 먼저 옴
		end
	end
end

local function render(dt: number)
	gravity = workspace.Gravity
	local now = os.clock()
	local decay = math.exp(-dt / BLEND_TAU)
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	for e in active do
		local rt = now - delayOf(e.plot)
		advance(e, rt)
		local p, v, busy = evaluate(e, rt)
		local err = e.err
		if err ~= Vector3.zero then
			p += err
			err *= decay
			e.err = if err.Magnitude < 1e-3 then Vector3.zero else err
		end
		-- 회전 연출: 공중이면 수평 속도 방향으로 굴리고, 내려앉으면 가장 가까운 90°로
		local hv = Vector3.new(v.X, 0, v.Z)
		local hs = hv.Magnitude
		if math.abs(v.Y) > AIR_VY and hs > 1 then
			local axis = Vector3.new(hv.Z / hs, 0, -hv.X / hs) -- 위 × 진행 방향: 윗면이 앞으로 구른다
			e.rot = CFrame.fromAxisAngle(axis, hs / (e.part.Size.X / 2) * TUMBLE * dt) * e.rot
			e.settled = false
		elseif not e.settled and math.abs(v.Y) <= AIR_VY and now >= e.holdUntil then
			local target = snap90(e.rot)
			e.rot = e.rot:Lerp(target, math.min(1, dt * SETTLE_RATE))
			if e.rot.XVector:Dot(target.XVector) > 0.9999 and e.rot.YVector:Dot(target.YVector) > 0.9999 then
				e.rot = target
				e.settled = true
			end
		end
		table.insert(parts, e.part)
		table.insert(cfs, CFrame.new(p) * e.rot)
		if not busy and e.settled and e.err == Vector3.zero then
			active[e] = nil -- 멈춤: 새 샘플이 오면 다시 움직인다
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- 착지 콜백 (plot 모델, 파트, 등급, 떨어지던 속도). init.client가 내 플롯 착지 연출에 쓴다
function CubeView.onLand(fn: (Model, BasePart, number, number) -> ())
	table.insert(landHandlers, fn)
end

-- 플롯 번호·큐브 id → 로컬 파트 (없으면 nil). 파트는 풀에서 다시 쓰이므로 오래 들고 있을 땐 CubeId 속성을 다시 확인할 것
function CubeView.part(plotIndex: number, id: number): BasePart?
	local pv = plots[plotIndex]
	local e = pv and pv.entities[id]
	return e and e.part
end

function CubeView.start(evt: RemoteEvent, snap: UnreliableRemoteEvent)
	task.spawn(function()
		-- 플롯 모델(서버 Plots.init이 만든다)이 다 복제될 때까지. 그동안 온 이벤트는 Roblox가 쌓아 둔다
		local folder = workspace:WaitForChild("Plots")
		for i = 1, Config.PLOT_COUNT do
			local model = folder:WaitForChild("Plot" .. i) :: Model
			local floor = model:WaitForChild("TrayFloor") :: BasePart
			plots[i] = {
				index = i,
				model = model,
				folder = model:WaitForChild("Cubes"),
				center = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0),
				gen = 0,
				seq = -1,
				period = 1 / 15,
				tick = nil,
				offset = nil,
				entities = {},
				pending = {},
			}
		end
		evt.OnClientEvent:Connect(function(index: any, gen: any, buf: any)
			local pv = plots[index]
			if not pv or typeof(gen) ~= "number" or typeof(buf) ~= "buffer" then
				return
			end
			local ops = CubeCodec.decodeEvents(buf)
			if ops then
				onEvents(pv, gen, ops)
			end
		end)
		snap.OnClientEvent:Connect(function(index: any, gen: any, buf: any)
			local pv = plots[index]
			if not pv or typeof(gen) ~= "number" or typeof(buf) ~= "buffer" then
				return
			end
			local head, entries = CubeCodec.decodeSnapshot(buf)
			if head and entries then
				onSnapshot(pv, gen, head, entries)
			end
		end)
		RunService.RenderStepped:Connect(render)
	end)
end

return CubeView
