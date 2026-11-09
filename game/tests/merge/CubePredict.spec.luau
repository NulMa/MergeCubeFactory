--!strict
-- lune run tests/merge/CubePredict.spec.luau (game 디렉터리에서)
-- 데드 레코닝 (shared/CubePredict + server/CubeNet 선택 규칙 + CubeCodec 양자화). docs/27 "최적화 (2026-10-22)"
--   1. 예측식 = TraySim 자유 낙하 (공중이면 정확히 같은 포물선)
--   2. collect 규칙: 처음·어긋남·keepalive·잠듦(연속 2번 + 1초 뒤 1번)·없어짐
--   3. 후반 재현(큐브 ~55개, 드로퍼 8개 투하 + 자석 깡충 + 합치기)을 TraySim으로 돌려 예전 방식과 바이트 비교, 클라 화면 오차
--   4. 패킷 손실 10%: 어긋남이 keepalive 안에 낫는다

local process = require("@lune/process")
local TraySim = require("../../src/merge/shared/TraySim")
local CubeCodec = require("../../src/merge/shared/CubeCodec")
local CubePredict = require("../../src/merge/shared/CubePredict")

local passed, failed = 0, 0

local function ok(name: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print(`FAIL  {name}{if detail then ": " .. detail else ""}`)
	end
end

local GRAVITY = 196.2
local DT = TraySim.DT
-- server/CubeNet 값 (주인 등급)
local POS_TOL, VEL_TOL, REST_TOL, KEEP_TICKS, FINAL_REPEAT, REST_KEEP_TICKS = 0.25, 6, 0.05, 30, 1, 240
local SNAP_EVERY = 2 -- 30Hz 시뮬에서 2틱마다 = 주인 15Hz
local QUANT: CubePredict.Quant = { pos = CubeCodec.snapPos, vel = CubeCodec.snapVel }
local RULES: CubePredict.Rules = {
	gravity = GRAVITY,
	posTol = POS_TOL,
	velTol = VEL_TOL,
	restTol = REST_TOL,
	keepTicks = KEEP_TICKS,
	finalRepeat = FINAL_REPEAT,
	restKeepTicks = REST_KEEP_TICKS,
}

local CUBE_SIZE_MIN, CUBE_SIZE_STEP, CUBE_SIZE_MAX = 2.2, 0.35, 4.65 -- shared/Config
local function cubeSize(tier: number): number
	return math.min(CUBE_SIZE_MIN + CUBE_SIZE_STEP * ((math.max(1, tier) - 1) // 5), CUBE_SIZE_MAX)
end

local seed = 777
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function world(sim: TraySim.Sim): CubePredict.World
	return {
		eachAwake = function(fn)
			sim:eachAwake(fn)
		end,
		has = function(id)
			return sim:has(id)
		end,
		position = function(id)
			return sim:position(id)
		end,
	}
end

-- 1. 예측식 ------------------------------------------------------------------------
ok("DT matches TraySim", CubePredict.DT == TraySim.DT)
do
	-- 공중에서 던진 큐브: 바닥에 닿기 전까지 매 틱 예측 = 시뮬 (부분 스텝·정확 적분)
	local sim = TraySim.new({ halfX = 40, halfZ = 40, gravity = GRAVITY })
	sim:add(1, 0, 30, 0, 1.5)
	sim:setVelocity(1, 12, 25, -7)
	local maxErr = 0
	local airAll = true
	for k = 1, 40 do
		sim:step(DT)
		local x, y, z = sim:position(1)
		local px, py, pz = CubePredict.at(0, 30, 0, 12, 25, -7, true, GRAVITY, k * DT)
		if py <= 1.5 then
			break -- 이 틱 안에 바닥에 닿음 (접촉은 예측하지 않는다)
		end
		maxErr = math.max(maxErr, math.abs(px - x), math.abs(py - y), math.abs(pz - z))
		sim:eachAwake(function(_, _, _, _, _, _, _, air)
			airAll = airAll and air
		end)
	end
	ok("free flight prediction == TraySim", maxErr < 1e-6, `max err {maxErr}`)
	ok("eachAwake reports air in free flight", airAll)
	-- 바닥에 놓인 큐브는 air가 아님
	local floorSim = TraySim.new({ halfX = 10, halfZ = 10, gravity = GRAVITY })
	floorSim:add(1, 0, 1.5, 0, 1.5, 3, 0, 0)
	floorSim:step(DT)
	local air = true
	floorSim:eachAwake(function(_, _, _, _, _, _, _, a)
		air = a
	end)
	ok("eachAwake: sliding on floor is not air", not air)
	local x, y, _, vx, vy = CubePredict.at(0, 1.5, 0, 4, 0, 0, false, GRAVITY, 0.5)
	ok("ground slide at SLIDE_SPEED is linear (no gravity)", x == 2 and y == 1.5 and vx == 4 and vy == 0)
	ok("SLIDE_SPEED == TraySim.TIP_SPEED", CubePredict.SLIDE_SPEED == TraySim.TIP_SPEED)
	local hx, _, _, hvx = CubePredict.at(0, 0, 0, 4, 0, 0, false, GRAVITY, 10)
	ok("prediction stops at HORIZON", hx == 4 * CubePredict.HORIZON and hvx == 0)
	-- 바닥 마찰 감속 = TraySim (받쳐진 채 미끄러지다 멈춤)
	local slide = TraySim.new({ halfX = 40, halfZ = 40, gravity = GRAVITY })
	slide:add(1, 0, 1.5, 0, 1.5)
	for _ = 1, 15 do
		slide:step(DT) -- 내려앉게
	end
	slide:setVelocity(1, 30, 0, -12)
	local sx0, sy0, sz0 = slide:position(1)
	local fErr = 0
	for k = 1, 30 do
		slide:step(DT)
		local ax, _, az = slide:position(1)
		local px, _, pz = CubePredict.at(sx0, sy0, sz0, 30, 0, -12, false, GRAVITY, k * DT)
		fErr = math.max(fErr, math.abs(px - ax), math.abs(pz - az))
	end
	ok("ground friction prediction ~= TraySim slide", fErr < 0.15, `max err {fErr}`)
end

-- 2. collect 규칙 ------------------------------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20, gravity = GRAVITY })
	sim:add(1, 0, 20, 0, 1.5)
	local w = world(sim)
	local known: { [number]: CubePredict.Known } = {}
	local tick = 0
	local list = CubePredict.collect(known, tick, RULES, w, QUANT)
	ok("collect: unknown cube is sent", #list == 1 and list[1].air)
	ok("collect: known holds quantized values", known[1] and known[1].y == CubeCodec.snapPos(20))
	-- 떨어지는 동안(바닥 전)은 예측이 맞아 안 보냄
	local sentInFlight = 0
	for _ = 1, 6 do
		sim:step(DT)
		tick += 1
		sentInFlight += #CubePredict.collect(known, tick, RULES, w, QUANT)
	end
	ok("collect: free fall needs no corrections", sentInFlight == 0, `sent {sentInFlight}`)
	-- 바닥에 닿고 잠들 때까지: 접촉 보정 + 정지 자리 연속 2번
	local sends: { number } = {}
	for _ = 1, 120 do
		sim:step(DT)
		tick += 1
		if #CubePredict.collect(known, tick, RULES, w, QUANT) > 0 then
			table.insert(sends, tick)
		end
	end
	ok("collect: cube fell asleep", not sim:awake(1))
	local k = known[1]
	ok("collect: known ends at rest", k ~= nil and CubePredict.resting(k) and k.final == 0)
	local _, ry = sim:position(1)
	ok("collect: rest pose exact", k ~= nil and math.abs(k.y - ry) <= 1 / 128)
	local n = #sends
	ok(
		"collect: rest pose sent twice in a row",
		n >= 2 and sends[n] - sends[n - 1] == 1,
		`sends at {table.concat(sends, ",")}`
	)
	-- 조용하면 정지 keepalive(REST_KEEP_TICKS)까지 아무것도 안 보냄
	local quiet = 0
	local quietTicks = REST_KEEP_TICKS - (tick - sends[n]) - 1
	for _ = 1, quietTicks do
		sim:step(DT)
		tick += 1
		quiet += #CubePredict.collect(known, tick, RULES, w, QUANT)
	end
	ok("collect: nothing sent while asleep", quiet == 0, `sent {quiet}`)
	sim:step(DT)
	tick += 1
	ok("collect: rest keepalive after REST_KEEP_TICKS", #CubePredict.collect(known, tick, RULES, w, QUANT) == 1)
	-- 깨어 있지만 예측이 맞는 큐브(일정한 속도로 미끄러짐을 흉내: 아는 상태를 실제와 같게)도 keepalive마다
	local fake: CubePredict.World = {
		eachAwake = function(fn)
			local t = tick * DT
			fn(2, 4 * t, 1.5, 0, 4, 0, 0, false) -- 미끄럼 속력(SLIDE_SPEED)이라 직선 예측
		end,
		has = function()
			return true
		end,
		position = function()
			return 0, 0, 0
		end,
	}
	local fk: { [number]: CubePredict.Known } = {}
	local count = 0
	for _ = 1, 90 do
		tick += 1
		count += #CubePredict.collect(fk, tick, RULES, fake, QUANT)
	end
	ok("collect: keepalive every second for well-predicted awake cube", count == 3, `count {count}`)
	-- 없어진 큐브는 잊는다
	sim:remove(1)
	CubePredict.collect(known, tick, RULES, w, QUANT)
	ok("collect: removed cube forgotten", known[1] == nil)
	-- 살짝 밀려 잠든 큐브 (아는 자리와 restTol 넘게 다름) → 다시 보냄
	local s2 = TraySim.new({ halfX = 20, halfZ = 20, gravity = GRAVITY })
	s2:add(5, 0, 1.5, 0, 1.5)
	for _ = 1, 30 do
		s2:step(DT)
	end
	local kn: { [number]: CubePredict.Known } =
		{ [5] = { x = 0.2, y = 1.5, z = 0, vx = 0, vy = 0, vz = 0, air = false, tick = tick, final = 0 } }
	ok("collect: drifted rest pose re-sent", #CubePredict.collect(kn, tick + 1, RULES, world(s2), QUANT) == 1)
end

-- 3·4. 후반 재현 ------------------------------------------------------------------------
-- 폭 40 트레이, T19~T23 큐브 55개 쌓인 채 시작. 10초 동안 드로퍼 8자리 초당 14개 투하,
-- 자석 깡충 초당 14번(쉬는 큐브 하나를 다른 큐브 쪽으로 hopVelocity, 0.35초 뒤 합쳐져 사라짐)
type Stats = {
	oldBytes: number,
	newBytes: number,
	newEntries: number,
	oldEntries: number,
	errTicks: number,
	bigErrTicks: number,
	maxErr: number,
	sendErr: number,
	longestBad: number,
	endErr: number,
}

local function scenario(loss: number): Stats
	seed = 4321
	local half = 20
	local sim = TraySim.new({ halfX = half, halfZ = half, ceilY = 48, slumpY = 8, gravity = GRAVITY })
	local nextId = 0
	local tierOf: { [number]: number } = {}
	local function add(x: number, y: number, z: number)
		nextId += 1
		local tier = 19 + math.floor(rand() * 5)
		tierOf[nextId] = tier
		sim:add(nextId, x, y, z, cubeSize(tier) / 2)
		return nextId
	end
	for _ = 1, 55 do
		add((rand() - 0.5) * 30, 5 + rand() * 30, (rand() - 0.5) * 30)
	end
	for _ = 1, 240 do
		sim:step(DT)
	end

	local w = world(sim)
	local known: { [number]: CubePredict.Known } = {}
	-- 클라: 받은 상태 (id → 틱 실린 상태). spawn은 지연 없이 같은 틱에 (v 0, 공중)
	local client: { [number]: CubePredict.Known } = {}
	local wasAwake: { [number]: number } = {} -- 예전 방식: 잠든 뒤 더 보낼 횟수
	local badSince: { [number]: number } = {}
	local pendingMerge: { { id: number, at: number } } = {}
	local st: Stats = {
		oldBytes = 0,
		newBytes = 0,
		newEntries = 0,
		oldEntries = 0,
		errTicks = 0,
		bigErrTicks = 0,
		maxErr = 0,
		sendErr = 0,
		longestBad = 0,
		endErr = 0,
	}
	local DROPPERS = {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		table.insert(DROPPERS, { math.cos(a) * 12, math.sin(a) * 12 })
	end

	local function clientError(id: number, tick: number): number
		local c = client[id]
		if not c then
			return 0
		end
		local x, y, z = sim:position(id)
		local px, py, pz = CubePredict.at(c.x, c.y, c.z, c.vx, c.vy, c.vz, c.air, GRAVITY, (tick - c.tick) * DT)
		return math.sqrt((px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2)
	end

	local TICKS = 300
	local QUIET = 300 -- 끝에 10초 조용히 (전부 잠들고, 정지 keepalive 8초도 지나 마지막 자리 확인)
	for tick = 1, TICKS + QUIET do
		local busy = tick <= TICKS
		-- 투하
		if busy and rand() < 14 / 30 then
			local d = DROPPERS[1 + math.floor(rand() * 8)]
			local id = add(d[1], 26, d[2])
			client[id] = { x = d[1], y = 26, z = d[2], vx = 0, vy = 0, vz = 0, air = true, tick = tick, final = 0 }
		end
		-- 자석 깡충 → 0.35초 뒤 합치기 (위쪽 하나 사라짐)
		if busy and rand() < 14 / 30 then
			local ids = {}
			for id in tierOf do
				if sim:has(id) and not sim:awake(id) then
					table.insert(ids, id)
				end
			end
			if #ids >= 2 then
				local a = ids[1 + math.floor(rand() * #ids)]
				local b = ids[1 + math.floor(rand() * #ids)]
				if a ~= b then
					local fx, fy, fz = sim:position(a)
					local tx, _, tz = sim:position(b)
					local vx, vy, vz = TraySim.hopVelocity(fx, fy, fz, sim:half(a), tx, tz, {}, 30, GRAVITY)
					sim:setVelocity(a, vx, vy, vz)
					table.insert(pendingMerge, { id = a, at = tick + 10 })
				end
			end
		end
		for i = #pendingMerge, 1, -1 do
			local m = pendingMerge[i]
			if tick >= m.at then
				if sim:has(m.id) then
					sim:remove(m.id)
					tierOf[m.id] = nil
					client[m.id] = nil
					known[m.id] = nil
				end
				table.remove(pendingMerge, i)
			end
		end
		sim:step(DT)

		if tick % SNAP_EVERY == 0 then
			-- 예전: 깨어 있는 것 전부 + 잠든 직후 2번, 60개씩
			local oldN = 0
			local recent: { [number]: number } = {}
			sim:eachAwake(function(id)
				recent[id] = FINAL_REPEAT
				oldN += 1
			end)
			for id, left in wasAwake do
				if not recent[id] and sim:has(id) then
					oldN += 1
					if left > 1 then
						recent[id] = left - 1
					end
				end
			end
			wasAwake = recent
			if oldN > 0 then
				st.oldEntries += oldN
				st.oldBytes += math.ceil(oldN / 60) * 4 + oldN * 11
			end
			-- 새: 보정만. 실제 인코딩·디코딩을 거쳐 클라에 넣는다 (손실이면 클라만 못 받음)
			local entries = CubePredict.collect(known, tick, RULES, w, QUANT)
			if #entries > 0 then
				st.newEntries += #entries
				local buf = CubeCodec.encodeSnapshot(tick, tick, 15, entries :: any) -- 60개 넘으면 CubeNet이 나눔(헤더만 더)
				st.newBytes += buffer.len(buf) + (math.ceil(#entries / 60) - 1) * CubeCodec.SNAP_HEADER_SIZE
				local head, decoded = CubeCodec.decodeSnapshot(buf)
				if head and decoded and rand() >= loss then
					for _, e in decoded do
						client[e.id] = {
							x = e.x,
							y = e.y,
							z = e.z,
							vx = e.vx,
							vy = e.vy,
							vz = e.vz,
							air = e.air,
							tick = head.tick,
							final = 0,
						}
					end
				end
			end
			if loss == 0 then
				-- 보낸 직후: 서버가 아는 상태 = 클라 상태 → 모든 큐브 오차 ≤ 한도 + 양자화
				for id in tierOf do
					if sim:has(id) then
						st.sendErr = math.max(st.sendErr, clientError(id, tick))
					end
				end
			end
		end
		-- 매 틱 클라 화면 오차 (보정 사이 포함)
		for id in tierOf do
			if sim:has(id) then
				local e = clientError(id, tick)
				st.errTicks += 1
				st.maxErr = math.max(st.maxErr, e)
				if e > 1 then
					st.bigErrTicks += 1
				end
				if e > POS_TOL * 2 and sim:awake(id) then
					badSince[id] = badSince[id] or tick
					st.longestBad = math.max(st.longestBad, (tick - badSince[id]) * DT)
				else
					badSince[id] = nil
				end
				if tick == TICKS + QUIET then
					st.endErr = math.max(st.endErr, e)
				end
			end
		end
	end
	return st
end

local s0 = scenario(0)
local ratio = s0.newBytes / s0.oldBytes
print(
	string.format(
		"  late-game 10s: old %d B (%d entries) -> new %d B (%d entries) = %.0f%%; per second old %.0f B/s, new %.0f B/s",
		s0.oldBytes,
		s0.oldEntries,
		s0.newBytes,
		s0.newEntries,
		ratio * 100,
		s0.oldBytes / 15,
		s0.newBytes / 15
	)
)
print(
	string.format(
		"  client error: max %.2f, ticks > 1 stud %.2f%%, right after send max %.3f",
		s0.maxErr,
		s0.bigErrTicks / s0.errTicks * 100,
		s0.sendErr
	)
)
ok("late-game snapshot bytes <= 50% of old", ratio <= 0.5, string.format("%.0f%%", ratio * 100))
ok("after each send client == server within POS_TOL", s0.sendErr <= POS_TOL + 0.02, `{s0.sendErr}`)
ok("client error > 1 stud on < 3% of cube-ticks", s0.bigErrTicks / s0.errTicks < 0.03)
ok("all asleep at end: client rest pose within REST_TOL", s0.endErr <= REST_TOL + 0.02, `{s0.endErr}`)

local s1 = scenario(0.1)
print(
	string.format(
		"  10%% loss: longest awake error > %.2f lasted %.2fs, ticks > 1 stud %.2f%%, end err %.3f",
		POS_TOL * 2,
		s1.longestBad,
		s1.bigErrTicks / s1.errTicks * 100,
		s1.endErr
	)
)
ok("10% loss: awake errors heal within ~2 keepalives", s1.longestBad <= 2.2, `{s1.longestBad}s`)
ok("10% loss: rest poses heal (repeat + rest keepalive)", s1.endErr <= REST_TOL + 0.02, `{s1.endErr}`)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
