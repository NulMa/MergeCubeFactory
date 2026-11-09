--!strict
-- 큐브 움직임 예측 (데드 레코닝, docs/27 "최적화 2026-10-22"). 순수 Luau (Roblox API 없음 → Lune 테스트).
-- 서버 CubeNet과 클라 CubeView가 **같은 함수**로 예측한다: 서버는 "클라가 지금 그리고 있을 자리"를 알고,
-- 그게 실제(TraySim)와 어긋날 때만 스냅샷 항목을 보낸다.
--   * 모델: 마지막으로 보낸 상태(위치·속도·air)에서 t초 뒤. air면 중력 포물선(TraySim 자유 낙하와 같은 정확해),
--     아니면 가로 마찰 감속(TraySim 바닥·받침 마찰과 같은 식, 모서리 미끄럼 속력이면 직선).
--     바닥·벽·큐브와의 접촉은 흉내 내지 않는다: 접촉하면 속도가 확 바뀌어 서버가 곧 보정을 보낸다.
--   * 시간: 시뮬 틱(TraySim.DT 고정 스텝) 단위. 서버는 틱 차이로, 클라는 틱을 자기 시계로 옮겨(CubeView) 같은 t를 쓴다.
--   * 보낸 상태는 양자화된 값(CubeCodec.snap*)으로 기억해야 서버 예측 = 클라 예측이 된다.

local CubePredict = {}

CubePredict.DT = 1 / 30 -- 틱 길이 = TraySim.DT (shared/TraySim과 같아야 함)
-- 이 초 넘게는 예측하지 않고 그 자리에 멈춘다 (보정을 잃었을 때 멀리 날아가지 않게). 서버 keepalive(1초)보다 길어
-- 깨어 있는 큐브는 그 전에 늘 새 상태를 받는다. 서버·클라가 같은 한도를 써야 서버가 "클라가 멈춰 있음"을 안다
CubePredict.HORIZON = 1.25
-- 받쳐진(air 아님) 큐브의 가로 감속 = FRICTION × g (TraySim 기본 마찰 0.4와 같음, 멈추면 0).
-- 단 가로 속력이 SLIDE_SPEED(= TraySim.TIP_SPEED)면 모서리·무너짐 미끄럼이라 같은 속도로 직선
CubePredict.FRICTION = 0.4
CubePredict.SLIDE_SPEED = 4
CubePredict.SLIDE_TOL = 0.2 -- 대각선 미끄럼은 양자화로 속력이 조금 어긋난다

-- 클라가 알고 있는 큐브 상태 (서버는 관찰 등급마다 큐브별로 하나)
export type Known = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	air: boolean,
	tick: number, -- 이 상태의 시뮬 틱
	final: number, -- 정지 상태를 다음 스냅샷들에 더 보낼 횟수 (비신뢰 손실 대비)
}

-- 제한 없는 예측 (t ≥ 0)
local function free(
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	air: boolean,
	g: number,
	t: number
): (number, number, number, number, number, number)
	if air then
		return x + vx * t, y + vy * t - g * t * t * 0.5, z + vz * t, vx, vy - g * t, vz
	end
	local hs = math.sqrt(vx * vx + vz * vz)
	if hs < 1e-9 or math.abs(hs - CubePredict.SLIDE_SPEED) <= CubePredict.SLIDE_TOL then
		return x + vx * t, y + vy * t, z + vz * t, vx, vy, vz
	end
	-- 바닥·받침 마찰: 등감속, 멈추면 그 자리. TraySim은 스텝마다 움직인 뒤 a·DT씩 깎으므로(이산)
	-- 거리 = v·t − a·t·(t − DT)/2, 멈춤 시각 = v/a + DT/2 (연속식보다 a·t·DT/2 더 감)
	local a = CubePredict.FRICTION * g
	local dt = CubePredict.DT
	local tt = math.min(t, hs / a + dt * 0.5)
	local d = (hs * tt - a * tt * (tt - dt) * 0.5) / hs
	local k = math.max(hs - a * t, 0) / hs
	return x + vx * d, y + vy * t, z + vz * d, vx * k, vy, vz * k
end

-- t초 뒤 위치·속도. air면 중력 g 포물선, 아니면 가로 마찰 감속(미끄럼 속력이면 직선).
-- t는 0..HORIZON으로 자르고, HORIZON에 닿으면 그 자리에 멈춘다(속도 0)
function CubePredict.at(
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	air: boolean,
	g: number,
	t: number
): (number, number, number, number, number, number)
	if t >= CubePredict.HORIZON then
		local px, py, pz = free(x, y, z, vx, vy, vz, air, g, CubePredict.HORIZON)
		return px, py, pz, 0, 0, 0
	end
	return free(x, y, z, vx, vy, vz, air, g, math.max(t, 0))
end

-- 정지 상태 (속도 0, 중력 없음): 예측해도 제자리
function CubePredict.resting(k: Known): boolean
	return not k.air and k.vx == 0 and k.vy == 0 and k.vz == 0
end

-- 서버: 이 틱에 실제 상태가 클라 예측과 어긋났나 (위치 오차 > posTol, 또는 속도 차 > velTol = 부딪힘·깡충·배트)
function CubePredict.diverged(
	k: Known,
	tick: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	g: number,
	posTol: number,
	velTol: number
): boolean
	local px, py, pz, pvx, pvy, pvz =
		CubePredict.at(k.x, k.y, k.z, k.vx, k.vy, k.vz, k.air, g, (tick - k.tick) * CubePredict.DT)
	local dx, dy, dz = px - x, py - y, pz - z
	if dx * dx + dy * dy + dz * dz > posTol * posTol then
		return true
	end
	local ex, ey, ez = pvx - vx, pvy - vy, pvz - vz
	return ex * ex + ey * ey + ez * ez > velTol * velTol
end

-- 스냅샷 항목 (CubeCodec.SnapEntry와 같은 모양)
export type Entry = {
	id: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	air: boolean,
}

-- 보낼 때 양자화 (CubeCodec.snapPos/snapVel: 디코드 결과와 같은 값). 이 모듈이 CubeCodec을 require하지 않게 넘겨받는다
export type Quant = {
	pos: (number) -> number,
	vel: (number) -> number,
}

export type Rules = {
	gravity: number,
	posTol: number, -- 깨어 있는 큐브 위치 오차 한도
	velTol: number, -- 속도 차 한도 (접촉·깡충·배트)
	restTol: number, -- 잠든 큐브의 마지막 자리가 아는 자리와 이만큼 다르면 다시 보냄 (쌓임이 딱 맞게)
	keepTicks: number, -- 움직이는 상태 keepalive (틱)
	finalRepeat: number, -- 정지 상태를 보낸 뒤 다음 스냅샷들에 더 보낼 횟수
	restKeepTicks: number, -- 정지 상태 keepalive (틱, 길게): 반복까지 다 잃은 정지 자리도 결국 맞춘다
}

-- 시뮬 쪽 (server/CubeNet Source의 일부)
export type World = {
	eachAwake: (fn: (number, number, number, number, number, number, number, boolean) -> ()) -> (),
	has: (id: number) -> boolean,
	position: (id: number) -> (number, number, number),
}

local function remember(known: { [number]: Known }, e: Entry, tick: number, final: number)
	local k = known[e.id]
	if k then
		k.x, k.y, k.z, k.vx, k.vy, k.vz, k.air, k.tick, k.final = e.x, e.y, e.z, e.vx, e.vy, e.vz, e.air, tick, final
	else
		known[e.id] = {
			x = e.x,
			y = e.y,
			z = e.z,
			vx = e.vx,
			vy = e.vy,
			vz = e.vz,
			air = e.air,
			tick = tick,
			final = final,
		}
	end
end

-- 아는 상태를 다시 보낼 차례인가 (비신뢰 손실 대비).
--   움직이는 상태: keepTicks마다. 정지 상태: final이 남았으면 다음 스냅샷에, 그 뒤엔 restKeepTicks마다 (반복을 다 잃어도 언젠가 맞음)
local function repeatDue(k: Known, tick: number, rules: Rules): boolean
	if CubePredict.resting(k) then
		return k.final > 0 or tick - k.tick >= rules.restKeepTicks
	end
	return tick - k.tick >= rules.keepTicks
end

local function isRest(e: Entry): boolean
	return not e.air and e.vx == 0 and e.vy == 0 and e.vz == 0
end

-- 서버 한 등급의 이번 스냅샷 항목을 고르고 known(그 등급 클라가 아는 상태)을 갱신한다.
--   깨어 있는 큐브: 모름 / 예측과 어긋남 / 다시 보낼 차례(repeatDue) → 지금 상태
--   잠든 큐브: 클라가 아직 움직인다고 알거나 아는 자리와 restTol 넘게 다르면 → 마지막 자리(속도 0, 중력 없음)
--   정지 상태를 보내면 finalRepeat번 더 보낸다 (다음 스냅샷 + keepalive 뒤). 정지로 아는 큐브는 그 뒤 keepalive 없음
--   없어진 큐브: known에서 지움 (remove op가 신뢰로 간다)
function CubePredict.collect(known: { [number]: Known }, tick: number, rules: Rules, world: World, q: Quant): { Entry }
	local list: { Entry } = {}
	local seen: { [number]: boolean } = {}
	world.eachAwake(function(id, x, y, z, vx, vy, vz, air)
		seen[id] = true
		local k = known[id]
		local again = false -- 어긋나지 않았고 반복 차례라서 보냄
		if k then
			if CubePredict.diverged(k, tick, x, y, z, vx, vy, vz, rules.gravity, rules.posTol, rules.velTol) then
				again = false
			elseif repeatDue(k, tick, rules) then
				again = true
			else
				return
			end
		end
		local e: Entry = {
			id = id,
			x = q.pos(x),
			y = q.pos(y),
			z = q.pos(z),
			vx = q.vel(vx),
			vy = q.vel(vy),
			vz = q.vel(vz),
			air = air,
		}
		table.insert(list, e)
		local final = 0
		if isRest(e) then
			final = if again and k and CubePredict.resting(k) then math.max(0, k.final - 1) else rules.finalRepeat
		end
		remember(known, e, tick, final)
	end)
	for id, k in known do
		if seen[id] then
			continue
		end
		if not world.has(id) then
			known[id] = nil
			continue
		end
		local x, y, z = world.position(id)
		local final: number
		local dx, dy, dz = k.x - x, k.y - y, k.z - z
		if not CubePredict.resting(k) or dx * dx + dy * dy + dz * dz > rules.restTol * rules.restTol then
			final = rules.finalRepeat -- 막 잠듦(클라는 아직 움직이는 중) 또는 아는 자리와 다름
		elseif repeatDue(k, tick, rules) then
			final = math.max(0, k.final - 1)
		else
			continue -- 이미 제자리를 안다
		end
		local e: Entry = { id = id, x = q.pos(x), y = q.pos(y), z = q.pos(z), vx = 0, vy = 0, vz = 0, air = false }
		table.insert(list, e)
		remember(known, e, tick, final)
	end
	return list
end

return CubePredict
