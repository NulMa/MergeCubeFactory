--!strict
-- lune run tests/merge/TraySim.spec.luau (game 디렉터리에서)
-- 트레이 간이 물리 (shared/TraySim): 바닥·벽·쌓기·터널링·잠·자석 깡충·크기 변경·벤치. docs/27_DATA_CUBES.md §1.2

local process = require("@lune/process")
local TraySim = require("../../src/merge/shared/TraySim")

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

local function near(name: string, got: number, want: number, tol: number)
	ok(name, math.abs(got - want) <= tol, `got {got}, want {want} ± {tol}`)
end

-- Config는 Roblox 전용(Vector3, script.Parent)이라 Lune에서 못 읽는다. 값을 옮겨 둔다 (shared/Config)
local CUBE_SIZE_MIN, CUBE_SIZE_STEP, CUBE_SIZE_MAX = 2.2, 0.35, 4.65
local function cubeSize(tier: number): number
	return math.min(CUBE_SIZE_MIN + CUBE_SIZE_STEP * ((math.max(1, tier) - 1) // 5), CUBE_SIZE_MAX)
end
local MERGE_DISTANCE = 1.2
local MAGNET_HOP = 30
local DROP_HEIGHT = 20
local GRAVITY = 196.2
local DT = TraySim.DT

-- 결정적 난수 (LCG)
local seed = 12345
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function run(sim: TraySim.Sim, seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		sim:step(DT)
	end
end

-- 모든 짝 중 가장 깊은 겹침 / 작은 쪽 반 변
local function worstOverlap(sim: TraySim.Sim, ids: { number }): number
	local worst = 0
	for a = 1, #ids do
		local ax, ay, az = sim:position(ids[a])
		local ha = sim:half(ids[a])
		for b = a + 1, #ids do
			local bx, by, bz = sim:position(ids[b])
			local hb = sim:half(ids[b])
			local ox = ha + hb - math.abs(bx - ax)
			local oy = ha + hb - math.abs(by - ay)
			local oz = ha + hb - math.abs(bz - az)
			if ox > 0 and oy > 0 and oz > 0 then
				worst = math.max(worst, math.min(ox, oy, oz) / math.min(ha, hb))
			end
		end
	end
	return worst
end

-- 상자 밖으로 나간 양 (0이면 전부 안)
local function worstOutside(sim: TraySim.Sim, ids: { number }, halfX: number, halfZ: number): number
	local worst = 0
	for _, id in ids do
		local x, y, z = sim:position(id)
		local h = sim:half(id)
		worst = math.max(worst, math.abs(x) + h - halfX, math.abs(z) + h - halfZ, h - y)
	end
	return worst
end

local function maxSpeed(sim: TraySim.Sim, ids: { number }): number
	local s = 0
	for _, id in ids do
		local x, y, z = sim:velocity(id)
		s = math.max(s, math.sqrt(x * x + y * y + z * z))
	end
	return s
end

-- 1. 바닥에 내려앉아 잠든다 ---------------------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 0, 10, 0, 1.5)
	run(sim, 2)
	local x, y, z = sim:position(1)
	near("rest: y = half", y, 1.5, 0.01)
	near("rest: x unchanged", x, 0, 1e-6)
	near("rest: z unchanged", z, 0, 1e-6)
	ok("rest: asleep", not sim:awake(1))
	ok("rest: awakeCount 0", sim:awakeCount() == 0)
end

-- 2. 첫 착지에 살짝 튄다 (반발 0.1) --------------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 0, DROP_HEIGHT, 0, 1.5)
	local peak, landed = 0, false
	for _ = 1, 60 do
		sim:step(DT)
		local _, vy = sim:velocity(1)
		if not landed and vy > 0 then
			landed = true
		end
		if landed then
			local _, y = sim:position(1)
			peak = math.max(peak, y - 1.5)
		end
	end
	ok("bounce: small hop after landing", landed and peak > 0.05 and peak < 1.5, `peak {peak}`)
end

-- 3. 마찰로 미끄러지다 멈춘다 ---------------------------------------------------------
do
	local sim = TraySim.new({ halfX = 40, halfZ = 40 })
	sim:add(1, 0, 1.5, 0, 1.5, 20, 0, 0)
	run(sim, 2)
	local x = sim:position(1)
	ok("friction: slides a bit then stops", x > 1 and x < 8 and not sim:awake(1), `x {x}`)
end

-- 4. 2·3단 쌓기가 유지되고 떨리지 않는다 ----------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 0, 1.5, 0, 1.5)
	sim:add(2, 0.3, 4.6, -0.2, 1.2)
	sim:add(3, -0.2, 7.2, 0.3, 1.0)
	run(sim, 2)
	local _, y1 = sim:position(1)
	local x2, y2 = sim:position(2)
	local x3, y3 = sim:position(3)
	near("stack: bottom on floor", y1, 1.5, 0.01)
	near("stack: middle on bottom", y2, 3 + 1.2, 0.02)
	near("stack: top on middle", y3, 3 + 2.4 + 1.0, 0.03)
	near("stack: middle stays put", x2, 0.3, 0.05)
	near("stack: top stays put", x3, -0.2, 0.05)
	ok("stack: all asleep", sim:awakeCount() == 0, `awake {sim:awakeCount()}`)
	-- 맨 아래를 지우면 위가 떨어진다 (이웃 깨움)
	sim:remove(1)
	ok("remove: neighbors woken", sim:awake(2))
	run(sim, 2)
	local _, y2b = sim:position(2)
	local _, y3b = sim:position(3)
	near("remove: middle falls to floor", y2b, 1.2, 0.02)
	near("remove: top follows", y3b, 2.4 + 1.0, 0.03)
	ok("remove: count", sim:count() == 2 and not sim:has(1))
end

-- 5. 모서리에 걸친 큐브는 미끄러져 떨어진다 -------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 0, 1.5, 0, 1.5)
	sim:add(2, 2.2, 6, 0, 1.0) -- 중심이 받침(반 변 1.5) 밖
	run(sim, 3)
	local _, y2 = sim:position(2)
	near("tip: overhanging cube slides off to floor", y2, 1.0, 0.02)
end

-- 6. 배트 최대 세기: 벽·다른 큐브를 뚫지 않는다 ---------------------------------------
do
	local H = 20
	local sim = TraySim.new({ halfX = H, halfZ = H, ceilY = 32 })
	local ids = {}
	-- 가장 작은 큐브(반 변 1.1)를 벽 앞에 세우고 큰 큐브로 친다
	sim:add(1, 0, 2.8, 0, 2.8)
	sim:add(2, 12, 1.1, 0, 1.1)
	ids = { 1, 2 }
	for i = 3, 30 do
		local half = cubeSize(1 + math.floor(rand() * 40)) / 2
		sim:add(i, -H + 3 + rand() * (H * 2 - 6), half, -H + 3 + rand() * 10, half)
		table.insert(ids, i)
	end
	run(sim, 1)
	-- Economy.batPower(10) = 165, 위로 0.45배 → 약 181. 그보다 세게, 바닥을 따라 수평으로 (위로 치면 넘어갈 수 있다)
	sim:setVelocity(1, 300, 0, 0)
	sim:setVelocity(2, 0, 0, 0)
	local outside, overlap, crossed = 0, 0, false
	for _ = 1, 90 do
		sim:step(DT)
		outside = math.max(outside, worstOutside(sim, ids, H, H))
		overlap = math.max(overlap, worstOverlap(sim, { 1, 2 }))
		-- 뚫고 지나감 = 같은 줄(z가 겹침)에서 x 순서가 바뀜. 옆으로 튕겨 비켜 간 것은 아니다 (2026-10-25 크기 변경 뒤 z=17로 튕김)
		local x1, _, z1 = sim:position(1)
		local x2, _, z2 = sim:position(2)
		crossed = crossed or (x1 > x2 and math.abs(z1 - z2) < 2.8 + 1.1)
	end
	ok("bat: everything stays inside walls", outside <= 1e-9, `outside {outside}`)
	ok("bat: hit cube never passes the small one", not crossed)
	ok("bat: no deep overlap during flight", overlap < 0.5, `overlap {overlap}`)
	-- 모든 큐브를 사방으로 세게 쳐도
	for _, id in ids do
		local a = rand() * math.pi * 2
		sim:setVelocity(id, math.cos(a) * 250, 80, math.sin(a) * 250)
	end
	outside = 0
	for _ = 1, 90 do
		sim:step(DT)
		outside = math.max(outside, worstOutside(sim, ids, H, H))
	end
	ok("bat: all cubes hit hard stay inside", outside <= 1e-9, `outside {outside}`)
	local _, y = sim:position(1)
	ok("bat: ceiling holds", y <= 32, `y {y}`)
end

-- 6b. 배트 위로 튀기: 위 속도 vy면 꼭짓점 높이 ≈ vy²/2g (Studio: 15스터드 날아가며 0.6만 뜨던 것).
--     Factory onSwing = (dir+look).Unit × power + 위 × power × 0.45. 바닥에 잠든 큐브·큐브 위 큐브 둘 다
do
	for _, power in { 40, 80 } do
		local vy = power * 0.45
		local want = vy * vy / (2 * GRAVITY)
		local sim = TraySim.new({ halfX = 28, halfZ = 28, ceilY = 48, slumpY = 8 })
		sim:add(1, -10, 2, 0, 2) -- 바닥
		sim:add(2, 10, 1.5, 0, 1.5) -- 받침
		sim:add(3, 10, 4.6, 0, 1.5) -- 그 위
		run(sim, 2)
		local y0 = { (select(2, sim:position(1))), (select(2, sim:position(3))) }
		sim:setVelocity(1, power, vy, 0)
		sim:setVelocity(3, power, vy, 0)
		local top = { y0[1], y0[2] }
		for _ = 1, 30 do
			sim:step(DT)
			top[1] = math.max(top[1], (select(2, sim:position(1))))
			top[2] = math.max(top[2], (select(2, sim:position(3))))
		end
		near(`bat rise: floor cube, power {power}`, top[1] - y0[1], want, want * 0.1)
		near(`bat rise: stacked cube, power {power}`, top[2] - y0[2], want, want * 0.1)
	end
end

-- 7. 110개 섞인 크기 떨어뜨리기: 6초 뒤 잠/정지, 겹침 ≤ 5% ------------------------------
local function dropScene(s: number): (TraySim.Sim, { number })
	seed = s
	local sim = TraySim.new({ halfX = 20, halfZ = 20, ceilY = 48 })
	local ids = {}
	for i = 1, 110 do
		local half = cubeSize(1 + math.floor(rand() * 40)) / 2
		-- 드로퍼처럼 위에서 한 줄로: 층마다 다른 높이에 흩뿌린다
		local layer = (i - 1) // 20
		sim:add(i, -17 + rand() * 34, DROP_HEIGHT + layer * 6, -17 + rand() * 34, half)
		table.insert(ids, i)
	end
	return sim, ids
end
-- 여러 배치로 (한 배치만 운 좋게 통과하지 않게)
for _, s in { 1, 11, 1234, 31337 } do
	local sim, ids = dropScene(s)
	run(sim, 6)
	local speed = maxSpeed(sim, ids)
	local overlap = worstOverlap(sim, ids)
	ok(
		`pile {s}: asleep or still after 6s`,
		sim:awakeCount() == 0 or speed < 0.5,
		`awake {sim:awakeCount()}, speed {speed}`
	)
	ok(`pile {s}: no pair overlaps > 5%`, overlap <= 0.05, `worst {overlap}`)
	ok(`pile {s}: inside tray`, worstOutside(sim, ids, 20, 20) <= 1e-9)
end
do
	local sim, ids = dropScene(777)
	run(sim, 6)
	local speed = maxSpeed(sim, ids)
	local overlap = worstOverlap(sim, ids)
	ok(
		"pile: asleep or still after 6s",
		sim:awakeCount() == 0 or speed < 0.5,
		`awake {sim:awakeCount()}, max speed {speed}`
	)
	ok("pile: no pair overlaps > 5%", overlap <= 0.05, `worst {overlap}`)
	ok("pile: inside tray", worstOutside(sim, ids, 20, 20) <= 1e-9)
	print(
		`      pile: {sim:awakeCount()} awake, max speed {string.format("%.3f", speed)}, worst overlap {string.format(
			"%.4f",
			overlap
		)}`
	)
	-- 잠든 뒤에는 위치가 바뀌지 않는다 (떨림 없음)
	local before = {}
	for _, id in ids do
		local x, y, z = sim:position(id)
		before[id] = { x, y, z }
	end
	run(sim, 2)
	local drift = 0
	for _, id in ids do
		local x, y, z = sim:position(id)
		local p = before[id]
		drift = math.max(drift, math.abs(x - p[1]), math.abs(y - p[2]), math.abs(z - p[3]))
	end
	ok("pile: no jitter over 2 more seconds", drift < 0.01, `drift {drift}`)
	-- 쿼리
	local x, y, z = sim:position(1)
	local found = false
	for _, id in sim:query(x, y, z, 0.01) do
		found = found or id == 1
	end
	ok("query: finds itself", found)
	ok("query: radius covers tray", #sim:query(0, 0, 0, 100) == 110)
end

-- 8. 자석 깡충: 6스터드 떨어진 같은 등급 둘이 만난다 ----------------------------------
do
	for _, size in { cubeSize(1), 3, cubeSize(40) } do
		local sim = TraySim.new({ halfX = 20, halfZ = 20 })
		local h = size / 2
		sim:add(1, -3, h, 0.5, h)
		sim:add(2, 3, h, -0.5, h)
		run(sim, 0.5)
		-- Factory.magnet와 같은 공식
		for _, pair in { { 1, 2 }, { 2, 1 } } do
			local fx, _, fz = sim:position(pair[1])
			local tx, _, tz = sim:position(pair[2])
			local air = 2 * MAGNET_HOP / GRAVITY
			sim:setVelocity(pair[1], (tx - fx) / 2 / air, MAGNET_HOP, (tz - fz) / 2 / air)
		end
		run(sim, 1.5)
		local ax, ay, az = sim:position(1)
		local bx, by, bz = sim:position(2)
		local dist = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
		ok(
			`magnet: size {string.format("%.2f", size)} meets within MERGE_DISTANCE`,
			dist <= size * MERGE_DISTANCE,
			`dist {dist}`
		)
	end
end

-- 8b. 자석 + 사이에 낀 큐브 (Studio 단계 4 버그): 짝 사이 길에 큐브가 있어도 20초 안에 다 합쳐진다 ------
-- Factory.scanMerges(0.1초마다) + magnet(magnetInterval마다, 멈춘 것끼리 가장 가까운 짝)을 그대로 흉내 낸다.
-- 데이터 큐브 깡충 = TraySim.hopVelocity (Factory.hopOver와 같은 계산). 합쳐진 짝은 둘 다 뺀다(다른 등급이 됨)
do
	local function magnetInterval(t: number): number
		return math.max(0.4, 0.8 / (1 + 0.024 * (t - 1)))
	end
	local function magnetRest(t: number): number
		return math.min(3.5, 1.5 * (1 + 0.032 * (t - 1)))
	end
	local CEILING = 28
	-- (등급, x, z) 트레이 중심 기준, 바닥에 놓임
	local layout = {
		{ 23, 5.2, -7.5 },
		{ 23, 5.2, 3.6 },
		{ 24, -5.9, 3.8 },
		{ 24, 11.1, 3.9 },
		{ 25, 0.5, -1.9 },
		{ 25, 0.5, 9.2 },
		{ 26, -0.3, 14.7 },
		{ 26, -0.3, 3.7 },
		{ 26, 11.9, -8.0 },
		{ 28, -12.0, 1.0 },
		{ 28, 7.3, -1.9 },
	}
	-- SimBackend와 같은 설정 (천장 = Plots.GUARD_TOP 48, slumpY = 벽 16 × 0.5)
	local sim = TraySim.new({ halfX = 20, halfZ = 20, ceilY = 48, slumpY = 8, gravity = GRAVITY })
	local tierOf: { [number]: number } = {}
	local nudged: { [number]: number } = {}
	for i, c in layout do
		local h = cubeSize(c[1]) / 2
		sim:add(i, c[2], h, c[3], h)
		tierOf[i], nudged[i] = c[1], -math.huge
	end
	local function dist(a: number, b: number): number
		local ax, ay, az = sim:position(a)
		local bx, by, bz = sim:position(b)
		return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
	end
	local function speed(id: number): number
		local x, y, z = sim:velocity(id)
		return math.sqrt(x * x + y * y + z * z)
	end
	local mergedAt: { [number]: number } = {}
	local now, nextScan = 0, 0
	while now < 20 do
		sim:step(DT)
		now += DT
		if now < nextScan then
			continue
		end
		nextScan = now + 0.1
		local byTier: { [number]: { number } } = {}
		for id, t in tierOf do
			if t < CEILING then
				byTier[t] = byTier[t] or {}
				table.insert(byTier[t], id)
			end
		end
		for t, list in byTier do
			table.sort(list)
			local used: { [number]: boolean } = {}
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					if not used[a] and not used[b] and dist(a, b) <= cubeSize(t) * MERGE_DISTANCE then
						used[a], used[b] = true, true
						sim:remove(b)
						tierOf[b] = nil
						tierOf[a] = 99 -- 합쳐진 쪽: 다른 등급이 되므로 이 테스트의 짝 찾기에선 뺀다 (몸은 남아 길을 막음)
						mergedAt[t] = mergedAt[t] or now
					end
				end
			end
			local free = {}
			for _, c in list do
				if not used[c] and speed(c) < magnetRest(t) and now - nudged[c] >= magnetInterval(t) then
					table.insert(free, c)
				end
			end
			local taken: { [number]: boolean } = {}
			for _, a in free do
				if taken[a] then
					continue
				end
				local best, bestDist = nil, math.huge
				for _, b in free do
					if b ~= a and not taken[b] and dist(a, b) < bestDist then
						best, bestDist = b, dist(a, b)
					end
				end
				if best then
					taken[a], taken[best] = true, true
					for _, pair in { { a, best }, { best, a } } do
						local from, to = pair[1], pair[2]
						local fx, fy, fz = sim:position(from)
						local tx, _, tz = sim:position(to)
						local fh = sim:half(from)
						local others = {}
						for id in tierOf do
							if id ~= from and id ~= to then
								local x, y, z = sim:position(id)
								local ch = sim:half(id)
								table.insert(others, x)
								table.insert(others, z)
								table.insert(others, ch)
								table.insert(others, if speed(id) < 2 then y + ch else fy - fh + ch * 2)
							end
						end
						local vx, vy, vz = TraySim.hopVelocity(fx, fy, fz, fh, tx, tz, others, MAGNET_HOP, GRAVITY)
						sim:setVelocity(from, vx, vy, vz)
						nudged[from] = now
					end
				end
			end
		end
	end
	for _, t in { 23, 24, 25, 26 } do
		ok(`magnet blocked: T{t} pair merges within 20s`, mergedAt[t] ~= nil, "never met")
	end
	local function at(t: number): string
		return if mergedAt[t] then string.format("%.1fs", mergedAt[t]) else "-"
	end
	print(`      magnet blocked: merged T23 {at(23)}, T24 {at(24)}, T25 {at(25)}, T26 {at(26)}`)
	-- 막는 큐브가 없으면 예전 공식 그대로 (상승 30, 공중 시간 2 × 30 / g)
	local vx, vy = TraySim.hopVelocity(0, 1, 0, 1, 6, 0, {}, MAGNET_HOP, GRAVITY)
	near("hopVelocity: clear path = old hop", vy, MAGNET_HOP, 1e-9)
	near("hopVelocity: clear path = old flat speed", vx, 6 / 2 / (2 * MAGNET_HOP / GRAVITY), 1e-9)
	local _, vy2 = TraySim.hopVelocity(0, 2.75, 0, 2.75, 11, 0, { 5.5, 0.2, 2.75, 5.5 }, MAGNET_HOP, GRAVITY)
	ok("hopVelocity: clears a cube in the way", vy2 * vy2 / (2 * GRAVITY) >= 5.5 + TraySim.HOP_CLEAR - 1e-9, `vy {vy2}`)
end

-- 9. 크기 변경 (트레이 강화) ----------------------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 18, 1, 18, 1)
	run(sim, 0.5)
	sim:resize(28, 28)
	sim:add(2, 26, 1, -26, 1)
	run(sim, 0.5)
	local x2, _, z2 = sim:position(2)
	near("resize: grown tray holds x", x2, 26, 1e-6)
	near("resize: grown tray holds z", z2, -26, 1e-6)
	sim:resize(20, 20)
	run(sim, 1)
	local x3, _, z3 = sim:position(2)
	ok("resize: shrink clamps inside", x3 <= 19 + 1e-9 and z3 >= -19 - 1e-9, `{x3}, {z3}`)
	ok("resize: count kept", sim:count() == 2)
end

-- 10. 고정 스텝 누적 ------------------------------------------------------------------
do
	local sim = TraySim.new({ halfX = 20, halfZ = 20 })
	sim:add(1, 0, 10, 0, 1)
	ok("step: 1/60 runs 0 steps", sim:step(1 / 60) == 0)
	ok("step: second 1/60 runs 1 step", sim:step(1 / 60) == 1)
	ok("step: 0.1s runs 3 steps", sim:step(0.1) == 3)
	ok("step: 1s capped at MAX_STEPS", sim:step(1) == TraySim.MAX_STEPS)
	ok("step: backlog dropped", sim:step(0) == 0)
	sim:teleport(1, 5, 10, 5)
	local x, y, z = sim:position(1)
	ok("teleport: moves and wakes", x == 5 and y == 10 and z == 5 and sim:awake(1))
	local n = 0
	sim:eachAwake(function(id)
		n += id
	end)
	ok("eachAwake: lists awake", n == 1)
end

-- 10b. 무너짐 (slumpY): 같은 자리에 차례로 떨어뜨려도 벽 위로 외줄 탑이 서지 않는다 --------
-- 회전이 없으면 고정된 드로퍼 밑에 기둥이 천장까지 선다. slumpY를 주면 착지 튕김 + 외줄 미끄럼으로 무너진다
local function towerTop(slumpY: number?): (number, number)
	seed = 4242
	local sim = TraySim.new({ halfX = 20, halfZ = 20, ceilY = 48, slumpY = slumpY })
	local ids = {}
	for i = 1, 40 do
		local half = cubeSize(1 + math.floor(rand() * 40)) / 2
		sim:add(i, 5, DROP_HEIGHT, -7, half)
		table.insert(ids, i)
		run(sim, 0.2)
	end
	run(sim, 6)
	local top = 0
	for _, id in ids do
		local _, y = sim:position(id)
		top = math.max(top, y + sim:half(id))
	end
	return top, worstOverlap(sim, ids)
end
do
	local plain = towerTop(nil)
	local top, overlap = towerTop(8)
	print(`      slump: same-spot tower top {string.format("%.1f", plain)} -> {string.format("%.1f", top)}`)
	ok("slump: without it a tower rises above the walls", plain > 24, `top {plain}`)
	ok("slump: pile stays near wall height (16)", top < 18, `top {top}`)
	ok("slump: no deep overlap", overlap <= 0.05, `worst {overlap}`)
	-- 바닥 근처(slumpY 아래)의 살짝 얹은 쌓기는 그대로
	local sim = TraySim.new({ halfX = 20, halfZ = 20, slumpY = 8 })
	sim:add(1, 0, 1.5, 0, 1.5)
	sim:add(2, 0.3, 4.6, -0.2, 1.2)
	run(sim, 2)
	local x2, y2 = sim:position(2)
	ok("slump: low stack untouched", math.abs(y2 - 4.2) < 0.02 and math.abs(x2 - 0.3) < 0.05, `{x2}, {y2}`)
end

-- 10c. 무너짐 켠 채(SimBackend 설정) 무작위 투하도 8초 안에 전부 잠든다 (벽·구석 큐브가 미끄럼 방향을 번갈아 떨던 것)
do
	local latest = 0
	for _, s in { 1, 19, 23, 27, 32 } do
		seed = s
		local sim = TraySim.new({ halfX = 20, halfZ = 20, ceilY = 48, slumpY = 8 })
		for i = 1, 110 do
			local half = cubeSize(1 + math.floor(rand() * 40)) / 2
			sim:add(i, -17 + rand() * 34, 20 + ((i - 1) // 20) * 6, -17 + rand() * 34, half)
		end
		local at = math.huge
		for t = 1, 240 do
			sim:step(DT)
			if sim.nAwake == 0 then
				at = t * DT
				break
			end
		end
		latest = math.max(latest, at)
	end
	print(`      slump settle: latest all-asleep {string.format("%.1f", latest)}s`)
	ok("slump settle: 110 random cubes all asleep within 8s", latest <= 8, `latest {latest}`)
end

-- 10d. 드로퍼 8자리(Plots.dropperOffsets, 트레이가 넓어져도 그대로)에 차례로 0.2초마다: 꼭대기 ≈ 벽 높이(16).
--      벽 위로 솟은 큐브가 받침과 이웃 사이에 끼면 한도 안에서 이웃을 밀고 지나간다
do
	local slots = { { -5, -7 }, { 5, 7 }, { 5, -7 }, { -5, 7 }, { -15, -7 }, { 15, 7 }, { 15, -7 }, { -15, 7 } }
	for _, case in { { 60, 20 }, { 124, 28 } } do
		local count, half = case[1], case[2]
		local worst, high = 0, 0
		for s = 1, 10 do
			seed = s * 7
			local sim = TraySim.new({ halfX = half, halfZ = half, ceilY = 48, slumpY = 8 })
			for i = 1, count do
				local sl = slots[(i - 1) % 8 + 1]
				sim:add(i, sl[1], 17, sl[2], cubeSize(1 + math.floor(rand() * 40)) / 2)
				run(sim, 0.2)
			end
			run(sim, 10)
			local top = 0
			for i = 1, count do
				local _, y = sim:position(i)
				top = math.max(top, y + sim:half(i))
			end
			worst = math.max(worst, top)
			if top > 17.5 then
				high += 1
			end
		end
		print(
			`      8-slot tower {count} cubes width {half * 2}: worst top {string.format("%.1f", worst)}, {high}/10 above 17.5`
		)
		-- 넓은 더미 꼭대기(≈16)에 마지막 큐브 하나가 평평히 얹히는 경우는 남는다 (회전 없음): 10번 중 1번까지, 큐브 하나 높이까지
		ok(`8-slot tower {count}: top ≈ wall height in ≥ 9/10 runs`, high <= 1, `{high}/10 above 17.5`)
		ok(`8-slot tower {count}: never more than one cube above the wall`, worst < 16 + 5.6 + 0.5, `worst {worst}`)
	end
end

-- 11. 벤치: 110개 모두 깨어 있을 때 스텝당 ms ----------------------------------------
do
	-- (a) 떨어지는 중 (부분 스텝 여러 번)
	local sim = dropScene(777)
	local t0 = os.clock()
	local steps = 45
	for _ = 1, steps do
		sim:step(DT)
	end
	local fallMs = (os.clock() - t0) * 1000 / steps
	-- (b) 쌓인 더미를 매 스텝 전부 깨움 (짝이 가장 많은 경우)
	run(sim, 6)
	local ids = {}
	for i = 1, 110 do
		ids[i] = i
	end
	local t1 = os.clock()
	steps = 150
	for _ = 1, steps do
		for _, id in ids do
			sim:wake(id)
		end
		sim:step(DT)
	end
	local pileMs = (os.clock() - t1) * 1000 / steps
	-- (c) 최악: 전부 사방으로 세게 (부분 스텝 최대)
	local t2 = os.clock()
	steps = 60
	for k = 1, steps do
		if k % 15 == 1 then
			for _, id in ids do
				local a = rand() * math.pi * 2
				sim:setVelocity(id, math.cos(a) * 200, 60, math.sin(a) * 200)
			end
		end
		sim:step(DT)
	end
	local batMs = (os.clock() - t2) * 1000 / steps
	local f = function(v: number): string
		return string.format("%.3f", v)
	end
	print(`      bench ms/step: falling {f(fallMs)}, awake pile {f(pileMs)}, all hit hard {f(batMs)}`)
	ok("bench: falling < 2ms/step", fallMs < 2, `{fallMs}`)
	ok("bench: awake pile < 2ms/step", pileMs < 2, `{pileMs}`)
	ok("bench: all hit hard < 2ms/step", batMs < 2, `{batMs}`)
end

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
