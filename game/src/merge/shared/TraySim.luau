--!strict
-- TraySim: 트레이 안 큐브 간이 물리 (순수 Luau, Roblox API 없음 → Lune 테스트). docs/27_DATA_CUBES.md §1.2
--
-- 모델
--   - 축 정렬 정육면체(회전 없음, 반 변 half)가 위가 열린 상자(바닥 + 벽 4 + 선택 천장) 안에 있다.
--   - 좌표는 시뮬 로컬: 트레이 중심 x = z = 0, 바닥 윗면 y = floorY. 벽은 x = ±halfX, z = ±halfZ (안쪽 면).
--   - 위치 기반 동역학(PBD), 고정 스텝 DT = 1/30초. SoA 배열(슬롯 1..n, 지우면 마지막 슬롯과 바꿈).
--   - 넓은 단계: xz 평면 균일 격자(셀 = CELL 스터드), 스텝마다 한 번 짝 목록을 만들고 반복마다 재사용.
--   - 제약: 바닥·벽·천장은 위치 고정(절대 못 나감). 큐브끼리는 AABB 겹침을 "들어온 축"으로 민다:
--     세로면 위 큐브만 올리고(쌓임 떨림 없음), 가로면 부피 역수 비율로 나눈다. 회전 대신 모서리 미끄럼(TIP_SPEED).
--   - 잠: 느리고 받쳐진 채 SLEEP_FRAMES 스텝이 지나면 잠든다(적분 건너뜀, 둘 다 잠든 짝은 검사 안 함).
--     WAKE_DIST보다 많이 밀리거나, 아래 큐브가 깨거나, setVelocity/teleport/remove(이웃)/resize면 깬다.
--   - 터널링 방지: 속도 상한 + 한 부분 스텝 이동 ≤ 최소 반 변 × 0.8 이 되도록 부분 스텝(최대 SUB_MAX).
--   - 적분: 자유 낙하는 정확한 포물선(y += vy·t − g·t²/2). 반암시 오일러는 약한 배트 위 속도의 꼭짓점을 30% 깎았다.
--   - 무너짐(slumpY, 기본 없음): 밑면이 slumpY × SCATTER_FROM보다 높은 곳에서 큐브 위에 세게 떨어지면 옆으로 튕기고(SCATTER),
--     받침 하나에만 얹혀 밑면이 slumpY보다, 받침이 여럿이면 slumpY × SLUMP_HIGH(벽 위)보다 높으면 미끄러져 내려간다.
--     큐브마다 SLIDE_TIME(벽 위면 SLIDE_TIME_HIGH)초 한도(막혀도 흐름), 바닥에 닿거나 던지면 다시 채움. 옆 큐브에 기대면 멈추되
--     벽 위 큐브는 한도 안에서 이웃을 밀고 지나간다. 벽에 붙은 큐브는 위치로 보아 벽 반대쪽으로. 고정된 드로퍼 자리 탑 방지(단계 4).
--   - 타고 넘기: 던진(setVelocity) 큐브가 올라가는 중 옆 큐브에 막히면 가로 속도를 지키고 보정은 자기가 다 진다 (자석 깡충).
--     TraySim.hopVelocity는 사이에 낀 큐브를 넘을 만큼 높이 뛰는 깡충 속도를 준다.
--
-- API
--   TraySim.new({ halfX, halfZ, floorY = 0, ceilY = nil, slumpY = nil, gravity = 196.2, friction = 0.4,
--                 restitution = 0.1, iterations = 4, cell = 6 }) -> sim
--   sim:add(id, x, y, z, half, vx?, vy?, vz?)   깨어 있는 채로 추가 (id 중복이면 에러)
--   sim:remove(id)                              없으면 무시. 닿아 있던 이웃을 깨운다
--   sim:setVelocity(id, vx, vy, vz)             깨움 (자석 깡충·배트)
--   sim:teleport(id, x, y, z)                   속도 0, 깨움, 옛 자리 이웃도 깨움 (enforceTray)
--   sim:wake(id)
--   sim:step(dt) -> 실행한 고정 스텝 수         누적해서 0..MAX_STEPS 스텝, 밀린 시간은 버림
--   sim:position(id) -> x, y, z    sim:velocity(id) -> vx, vy, vz    sim:half(id)    sim:awake(id)
--   sim:has(id)    sim:count()    sim:awakeCount()
--   sim:eachAwake(fn(id, x, y, z, vx, vy, vz, air))  복제용 (깨어 있는 것만, air = 지난 스텝에 받침 없음)
--   sim:query(x, y, z, r) -> { id }             중심 거리 ≤ r
--   sim:resize(halfX, halfZ)                    트레이 강화로 폭 변경. 전부 깨워 새 벽에 맞춘다

local TraySim = {}
TraySim.__index = TraySim

TraySim.DT = 1 / 30
TraySim.MAX_STEPS = 3 -- step() 한 번에 최대 고정 스텝 (서버 Heartbeat 끊김 대비)
TraySim.SUB_MAX = 8 -- 빠를 때 부분 스텝 상한
TraySim.SLEEP_SPEED = 0.3 -- 이보다 느리고 받쳐져 있으면 잠 카운트
TraySim.SLEEP_FRAMES = 10 -- 0.33초
TraySim.WAKE_SPEED = 2 -- 끼임 판정에서 이보다 빠르게 움직이는 짝은 빼고 본다 (충돌 중 겹침은 다음 스텝이 푼다)
TraySim.SHOVE_SPEED = 6 -- 이보다 느리게 미는 큐브는 잠든 큐브를 깨우지 못한다 (미끄럼 4보다 큼)
TraySim.WAKE_DIST = 0.01 -- 잠든 큐브가 이보다 많이 밀려야 깨운다 (적으면 깨어 있는 상대가 다 진다)
TraySim.BOUNCE_MIN = 8 -- 이보다 느린 충돌은 튀지 않음 (중력 한 스텝 = 6.5 → 바닥 떨림 방지)
TraySim.TIP_SPEED = 4 -- 받침 모서리 밖에 무게중심이 걸친 큐브를 미끄러뜨리는 속도
TraySim.SLUMP_HIGH = 1.5 -- 밑면이 slumpY × 이 값보다 높으면 받침이 여럿이어도 무너짐 (벽 위로 솟은 더미)
TraySim.SLIDE_TIME = 1.0 -- 큐브 하나가 무너짐 미끄럼을 쓸 수 있는 시간 (막혀도 흐름, 바닥에 닿거나 던지면 다시 채움)
TraySim.SLIDE_TIME_HIGH = 1.5 -- 밑면이 slumpHigh(벽 위)보다 높을 때의 한도 (꼭대기 큐브는 더 멀리 가야 벽 높이로 내려온다)
TraySim.CLIMB_SPEED = 5 -- 이보다 빠르게 올라가는 중에 옆 큐브에 막히면 가로 속도를 지킨다 (타고 넘기)
TraySim.JAM_GIVEUP = 30 -- 끼임 풀기를 이 스텝(1초)까지만 (못 풀면 조금 겹친 채 잠듦)
TraySim.JAM_OVERLAP = 0.03 -- 느린 짝이 스텝 끝에 작은 쪽 반 변의 이 비율보다 겹쳐 있으면 끼임 (둘 다 깨워 둠)
TraySim.PUSH_SPEED = 15 -- 아래에서 밀려 올라갈 때 더해지는 속도 상한 (깊은 겹침 해소가 발사가 되지 않게)
TraySim.SCATTER = 0.8 -- 큐브 위 착지: 받침보다 빨리 내려오던 속도(SCATTER_MIN 넘는 만큼)의 이 비율로 옆으로 튕김 (회전으로 굴러 떨어지는 것 대신)
TraySim.SCATTER_MIN = 8 -- 이보다 약한 착지는 튕기지 않음 (중력 한 스텝보다 조금 큼)
TraySim.SCATTER_FROM = 0.5 -- 착지 튕김은 밑면이 slumpY × 이 값보다 높을 때만 (바닥 근처 쌓기는 그대로)

-- hit 비트 (부분 스텝마다 초기화)
local HIT_FLOOR = 1
local HIT_WALL_X = 2
local HIT_WALL_Z = 4
local HIT_CEIL = 8
local HIT_SUPPORT = 16 -- 아래에서 받침 (바닥 또는 다른 큐브 위)
local HIT_SIDE = 32 -- 옆 큐브와 맞닿음 (기대어 있으면 모서리 미끄럼 없음)
local HIT_CLIMB = 64 -- 뛰어오르다 옆 큐브에 막혀 혼자 비켜남 (가로 속도 지킴)

export type Options = {
	halfX: number,
	halfZ: number,
	floorY: number?,
	ceilY: number?,
	slumpY: number?, -- 밑면이 이보다 높은 외줄 큐브는 무너뜨린다 (기본 없음)
	gravity: number?,
	friction: number?,
	restitution: number?,
	iterations: number?,
	cell: number?,
}

type SimData = {
	halfX: number,
	halfZ: number,
	floorY: number,
	ceilY: number,
	slumpY: number,
	gravity: number,
	friction: number,
	restitution: number,
	iterations: number,
	cell: number,
	acc: number,
	spin: number, -- 한가운데 착지 튕김 방향 (황금각씩 돈다)
	n: number,
	nAwake: number,
	slotOf: { [number]: number },
	ids: { number },
	px: { number },
	py: { number },
	pz: { number },
	ox: { number }, -- 부분 스텝 시작 위치
	oy: { number },
	oz: { number },
	vx: { number },
	vy: { number },
	vz: { number },
	h: { number }, -- 반 변
	w: { number }, -- 역질량 (1 / 부피)
	m: { number }, -- 넓은 단계 여유 (이번 스텝 이동 예상)
	sleep: { number }, -- 연속 정지 스텝 수
	asleep: { boolean },
	hit: { number },
	sup: { boolean }, -- 이번 스텝에 받쳐진 적 있음
	on: { number }, -- 이번 부분 스텝의 받침: 0 없음, -1 바닥·여럿, >0 그 큐브 하나
	act: { number }, -- 마지막 부분 스텝의 실제 이동 속도² (잠 판정)
	pv: { number }, -- 이번 부분 스텝 제약 전 세로 속도 (잠들었으면 0)
	imp: { number }, -- 이번 부분 스텝에 받침 큐브에 부딪힌 상대 속도 (큐브 위 착지 튕김)
	launched: { boolean }, -- setVelocity로 던져짐(자석 깡충·배트), 잠들 때까지 착지 튕김 없음
	jam: { number }, -- 끼임 풀기에 걸린 스텝 수 (JAM_GIVEUP까지, 던지기·순간이동이면 0)
	slid: { number }, -- 모서리·무너짐 미끄럼을 쓴 시간(초). SLIDE_TIME까지만 (바닥 닿기·던지기·순간이동이면 0)
	-- 격자
	nx: number,
	nz: number,
	cells: { { number } },
	cellN: { number },
	touched: { number },
	-- 짝 목록
	pa: { number },
	pb: { number },
	np: number,
}

export type Sim = typeof(setmetatable({} :: SimData, TraySim))

local function makeGrid(self: Sim)
	self.nx = math.max(1, math.ceil(self.halfX * 2 / self.cell))
	self.nz = math.max(1, math.ceil(self.halfZ * 2 / self.cell))
	local cells, cellN = {}, {}
	for i = 1, self.nx * self.nz do
		cells[i] = {}
		cellN[i] = 0
	end
	self.cells, self.cellN, self.touched = cells, cellN, {}
end

function TraySim.new(opts: Options): Sim
	local self = setmetatable(
		{
			halfX = opts.halfX,
			halfZ = opts.halfZ,
			floorY = opts.floorY or 0,
			ceilY = opts.ceilY or math.huge,
			slumpY = opts.slumpY or math.huge,
			gravity = opts.gravity or 196.2,
			friction = opts.friction or 0.4,
			restitution = opts.restitution or 0.1,
			iterations = opts.iterations or 4,
			cell = opts.cell or 6,
			acc = 0,
			spin = 0,
			n = 0,
			nAwake = 0,
			slotOf = {},
			ids = {},
			px = {},
			py = {},
			pz = {},
			ox = {},
			oy = {},
			oz = {},
			vx = {},
			vy = {},
			vz = {},
			h = {},
			w = {},
			m = {},
			sleep = {},
			asleep = {},
			hit = {},
			sup = {},
			on = {},
			act = {},
			pv = {},
			imp = {},
			launched = {},
			slid = {},
			jam = {},
			nx = 1,
			nz = 1,
			cells = {},
			cellN = {},
			touched = {},
			pa = {},
			pb = {},
			np = 0,
		} :: SimData,
		TraySim
	)
	makeGrid(self)
	return self
end

-- 슬롯 i를 깨운다 (이미 깨어 있으면 카운트만 초기화). 새로 깨면 그 위에 얹힌 잠든 큐브도 차례로 깨운다
local function wakeSlot(self: Sim, i: number)
	self.sleep[i] = 0
	if not self.asleep[i] then
		return
	end
	self.asleep[i] = false
	self.nAwake += 1
	local px, py, pz, h, asleep = self.px, self.py, self.pz, self.h, self.asleep
	local x, y, z, hi = px[i], py[i], pz[i], h[i]
	self.ox[i], self.oy[i], self.oz[i] = x, y, z
	self.on[i] = 0
	self.act[i] = 0
	for j = 1, self.n do
		if asleep[j] then
			local r = hi + h[j]
			local dy = py[j] - y
			if dy > 0 and math.abs(dy - r) < 0.05 and math.abs(px[j] - x) < r and math.abs(pz[j] - z) < r then
				wakeSlot(self, j)
			end
		end
	end
end

-- (x, y, z, half) 상자에 닿거나 가까운(0.2) 큐브를 모두 깨운다
local function wakeAround(self: Sim, x: number, y: number, z: number, half: number)
	local px, py, pz, h = self.px, self.py, self.pz, self.h
	for i = 1, self.n do
		local r = half + h[i] + 0.2
		if math.abs(px[i] - x) < r and math.abs(py[i] - y) < r and math.abs(pz[i] - z) < r then
			wakeSlot(self, i)
		end
	end
end

function TraySim.add(
	self: Sim,
	id: number,
	x: number,
	y: number,
	z: number,
	half: number,
	vx: number?,
	vy: number?,
	vz: number?
)
	assert(self.slotOf[id] == nil, "TraySim.add: duplicate id")
	local i = self.n + 1
	self.n = i
	self.nAwake += 1
	self.slotOf[id] = i
	self.ids[i] = id
	self.px[i], self.py[i], self.pz[i] = x, y, z
	self.ox[i], self.oy[i], self.oz[i] = x, y, z
	self.vx[i], self.vy[i], self.vz[i] = vx or 0, vy or 0, vz or 0
	self.h[i] = half
	self.w[i] = 1 / (half * half * half)
	self.m[i] = 0
	self.sleep[i] = 0
	self.asleep[i] = false
	self.hit[i] = 0
	self.sup[i] = false
	self.launched[i] = false
	self.slid[i] = 0
	self.jam[i] = 0
	self.on[i] = 0
	self.act[i] = self.vx[i] ^ 2 + self.vy[i] ^ 2 + self.vz[i] ^ 2
	self.pv[i] = 0
	self.imp[i] = 0
end

function TraySim.remove(self: Sim, id: number)
	local i = self.slotOf[id]
	if not i then
		return
	end
	local x, y, z, half = self.px[i], self.py[i], self.pz[i], self.h[i]
	if not self.asleep[i] then
		self.nAwake -= 1
	end
	-- 마지막 슬롯을 i로 옮긴다
	local last = self.n
	if i ~= last then
		local lastId = self.ids[last]
		self.ids[i] = lastId
		self.slotOf[lastId] = i
		for _, arr in
			{
				self.px,
				self.py,
				self.pz,
				self.ox,
				self.oy,
				self.oz,
				self.vx,
				self.vy,
				self.vz,
				self.h,
				self.w,
				self.m,
				self.sleep,
				self.hit,
				self.on,
				self.act,
				self.slid,
				self.jam,
				self.pv,
				self.imp,
			} :: { { number } }
		do
			arr[i] = arr[last]
		end
		self.asleep[i] = self.asleep[last]
		self.sup[i] = self.sup[last]
		self.launched[i] = self.launched[last]
	end
	self.ids[last] = nil :: any
	self.slotOf[id] = nil
	self.n = last - 1
	-- 위에 얹혀 있던 큐브가 떨어지도록
	wakeAround(self, x, y, z, half)
end

function TraySim.has(self: Sim, id: number): boolean
	return self.slotOf[id] ~= nil
end

function TraySim.count(self: Sim): number
	return self.n
end

function TraySim.awakeCount(self: Sim): number
	return self.nAwake
end

function TraySim.wake(self: Sim, id: number)
	local i = self.slotOf[id]
	if i then
		wakeSlot(self, i)
	end
end

function TraySim.setVelocity(self: Sim, id: number, vx: number, vy: number, vz: number)
	local i = self.slotOf[id]
	if i then
		wakeSlot(self, i)
		self.vx[i], self.vy[i], self.vz[i] = vx, vy, vz
		self.act[i] = vx * vx + vy * vy + vz * vz
		self.launched[i] = true
		self.slid[i] = 0
		self.jam[i] = 0
	end
end

function TraySim.teleport(self: Sim, id: number, x: number, y: number, z: number)
	local i = self.slotOf[id]
	if not i then
		return
	end
	wakeAround(self, self.px[i], self.py[i], self.pz[i], self.h[i])
	wakeSlot(self, i)
	self.px[i], self.py[i], self.pz[i] = x, y, z
	self.ox[i], self.oy[i], self.oz[i] = x, y, z
	self.vx[i], self.vy[i], self.vz[i] = 0, 0, 0
	self.launched[i] = false
	self.slid[i] = 0
	self.jam[i] = 0
end

function TraySim.position(self: Sim, id: number): (number, number, number)
	local i = self.slotOf[id]
	assert(i, "TraySim.position: unknown id")
	return self.px[i], self.py[i], self.pz[i]
end

function TraySim.velocity(self: Sim, id: number): (number, number, number)
	local i = self.slotOf[id]
	assert(i, "TraySim.velocity: unknown id")
	return self.vx[i], self.vy[i], self.vz[i]
end

function TraySim.half(self: Sim, id: number): number
	local i = self.slotOf[id]
	assert(i, "TraySim.half: unknown id")
	return self.h[i]
end

function TraySim.awake(self: Sim, id: number): boolean
	local i = self.slotOf[id]
	return i ~= nil and not self.asleep[i]
end

-- air: 지난 스텝에 받침(바닥·큐브)이 없었음 = 자유 비행 (복제 예측이 중력을 넣을지, shared/CubePredict)
function TraySim.eachAwake(self: Sim, fn: (number, number, number, number, number, number, number, boolean) -> ())
	local asleep, sup = self.asleep, self.sup
	for i = 1, self.n do
		if not asleep[i] then
			fn(self.ids[i], self.px[i], self.py[i], self.pz[i], self.vx[i], self.vy[i], self.vz[i], not sup[i])
		end
	end
end

function TraySim.query(self: Sim, x: number, y: number, z: number, r: number): { number }
	local out = {}
	local px, py, pz = self.px, self.py, self.pz
	local r2 = r * r
	for i = 1, self.n do
		local dx, dy, dz = px[i] - x, py[i] - y, pz[i] - z
		if dx * dx + dy * dy + dz * dz <= r2 then
			table.insert(out, self.ids[i])
		end
	end
	return out
end

function TraySim.resize(self: Sim, halfX: number, halfZ: number)
	self.halfX, self.halfZ = halfX, halfZ
	makeGrid(self)
	for i = 1, self.n do
		wakeSlot(self, i)
	end
end

-- 넓은 단계: 여유(m)를 더한 AABB가 겹칠 수 있는 짝을 pa/pb에 모은다.
-- 큐브는 xz로 덮는 모든 셀에 들어가고, 짝은 두 AABB 교집합의 최소 모서리가 있는 셀에서만 센다(중복 없음).
local function broadphase(self: Sim)
	local n = self.n
	local px, py, pz, h, m, asleep = self.px, self.py, self.pz, self.h, self.m, self.asleep
	local cell, nx, nz = self.cell, self.nx, self.nz
	local minX, minZ = -self.halfX, -self.halfZ
	local cells, cellN, touched = self.cells, self.cellN, self.touched
	local nt = 0
	local floor, maxN, maxZ = math.floor, nx - 1, nz - 1
	for i = 1, n do
		local r = h[i] + m[i]
		local x0 = floor((px[i] - r - minX) / cell)
		local x1 = floor((px[i] + r - minX) / cell)
		local z0 = floor((pz[i] - r - minZ) / cell)
		local z1 = floor((pz[i] + r - minZ) / cell)
		x0 = if x0 < 0 then 0 elseif x0 > maxN then maxN else x0
		x1 = if x1 < 0 then 0 elseif x1 > maxN then maxN else x1
		z0 = if z0 < 0 then 0 elseif z0 > maxZ then maxZ else z0
		z1 = if z1 < 0 then 0 elseif z1 > maxZ then maxZ else z1
		for cx = x0, x1 do
			for cz = z0, z1 do
				local idx = cx * nz + cz + 1
				local c = cellN[idx] + 1
				if c == 1 then
					nt += 1
					touched[nt] = idx
				end
				cellN[idx] = c
				cells[idx][c] = i
			end
		end
	end
	local pa, pb = self.pa, self.pb
	local np = 0
	for t = 1, nt do
		local idx = touched[t]
		local list, c = cells[idx], cellN[idx]
		cellN[idx] = 0
		for j1 = 1, c - 1 do
			local a = list[j1]
			local ra = h[a] + m[a]
			local ax, ay, az, sa = px[a], py[a], pz[a], asleep[a]
			for j2 = j1 + 1, c do
				local b = list[j2]
				if sa and asleep[b] then
					continue
				end
				local rb = h[b] + m[b]
				local rr = ra + rb
				local bx, bz = px[b], pz[b]
				if math.abs(bx - ax) >= rr or math.abs(bz - az) >= rr or math.abs(py[b] - ay) >= rr then
					continue
				end
				-- 교집합 최소 모서리의 셀이 이 셀일 때만
				local ix = math.max(ax - ra, bx - rb)
				local iz = math.max(az - ra, bz - rb)
				local cx = floor((ix - minX) / cell)
				local cz = floor((iz - minZ) / cell)
				cx = if cx < 0 then 0 elseif cx > maxN then maxN else cx
				cz = if cz < 0 then 0 elseif cz > maxZ then maxZ else cz
				if cx * nz + cz + 1 == idx then
					np += 1
					pa[np], pb[np] = a, b
				end
			end
		end
	end
	self.np = np
end

-- 자석 깡충 속도 (데이터 큐브용, 순수 함수 — Factory.magnet와 테스트가 같이 쓴다).
-- (fx,fy,fz, 반 변 fh)에서 (tx,tz)의 짝을 향해 가운데까지 뛴다. 회전이 없어서 사이에 큐브가 있으면 넘지 못하므로
-- 지나는 길(xz 띠)에 걸치는 큐브 윗면보다 HOP_CLEAR 높이 뛰게 상승 속도를 올린다(최소 hop, 높이 상한 = 큐브 두 개 + 1).
-- others = 짝 둘을 뺀 큐브의 평평한 배열 { x, z, 반 변, 윗면 y, x, z, ... }. 공중 시간 = 2 × 상승 속도 / g
TraySim.HOP_CLEAR = 0.6
function TraySim.hopVelocity(
	fx: number,
	fy: number,
	fz: number,
	fh: number,
	tx: number,
	tz: number,
	others: { number },
	hop: number,
	g: number
): (number, number, number)
	local sx, sz = tx - fx, tz - fz
	local len2 = sx * sx + sz * sz
	local bottom = fy - fh
	local top = bottom
	for k = 1, #others, 4 do
		local cx, cz, ch, ctop = others[k], others[k + 1], others[k + 2], others[k + 3]
		local u = if len2 > 0 then math.clamp(((cx - fx) * sx + (cz - fz) * sz) / len2, 0, 1) else 0
		local qx, qz = fx + sx * u - cx, fz + sz * u - cz
		local r = fh + ch
		if qx * qx + qz * qz < r * r and ctop > top then
			top = ctop
		end
	end
	local vy = hop
	if top > bottom then
		local rise = math.min(top - bottom + TraySim.HOP_CLEAR, 4 * fh + 1)
		vy = math.max(hop, math.sqrt(2 * g * rise))
	end
	local air = 2 * vy / g
	return sx / 2 / air, vy, sz / 2 / air
end

-- 상자 안쪽으로 (깨어 있는 것만; 잠든 것은 이미 안에 있다)
local function bounds(self: Sim)
	local px, py, pz, h, asleep, hit, on = self.px, self.py, self.pz, self.h, self.asleep, self.hit, self.on
	local loX, loZ, hiX, hiZ = -self.halfX, -self.halfZ, self.halfX, self.halfZ
	local floorY, ceilY = self.floorY, self.ceilY
	local bor = bit32.bor
	for i = 1, self.n do
		if asleep[i] then
			continue
		end
		local hi = h[i]
		local f = hit[i]
		local x = px[i]
		if x < loX + hi then
			px[i] = loX + hi
			f = bor(f, HIT_WALL_X)
		elseif x > hiX - hi then
			px[i] = hiX - hi
			f = bor(f, HIT_WALL_X)
		end
		local z = pz[i]
		if z < loZ + hi then
			pz[i] = loZ + hi
			f = bor(f, HIT_WALL_Z)
		elseif z > hiZ - hi then
			pz[i] = hiZ - hi
			f = bor(f, HIT_WALL_Z)
		end
		local y = py[i]
		if y < floorY + hi then
			py[i] = floorY + hi
			f = bor(f, HIT_FLOOR, HIT_SUPPORT)
			on[i] = -1
		elseif y > ceilY - hi then
			py[i] = ceilY - hi
			f = bor(f, HIT_CEIL)
		end
		hit[i] = f
	end
end

-- 큐브 i가 lo 말고 다른 큐브 위에도 닿아 얹혀 있나 (짝 목록에서 찾음, 미끄럼 후보에만 쓴다)
local function restsOnOther(self: Sim, i: number, lo: number): boolean
	local pa, pb, px, py, pz, h = self.pa, self.pb, self.px, self.py, self.pz, self.h
	for k = 1, self.np do
		local j = if pa[k] == i then pb[k] elseif pb[k] == i then pa[k] else 0
		if j ~= 0 and j ~= lo then
			local r = h[i] + h[j]
			local dy = py[i] - py[j]
			if dy > 0 and math.abs(dy - r) < 0.3 and math.abs(px[i] - px[j]) < r and math.abs(pz[i] - pz[j]) < r then
				return true
			end
		end
	end
	return false
end

-- 부분 스텝 하나 (길이 sh)
local function substep(self: Sim, sh: number)
	local n = self.n
	local px, py, pz, ox, oy, oz = self.px, self.py, self.pz, self.ox, self.oy, self.oz
	local vx, vy, vz, h, w = self.vx, self.vy, self.vz, self.h, self.w
	local asleep, hit, sup, on, act = self.asleep, self.hit, self.sup, self.on, self.act
	local pv, imp, launched = self.pv, self.imp, self.launched
	local pa, pb, np = self.pa, self.pb, self.np
	local g = self.gravity
	local gs = g * sh
	local wakeDist = TraySim.WAKE_DIST
	local climb = TraySim.CLIMB_SPEED
	local shove2 = TraySim.SHOVE_SPEED * TraySim.SHOVE_SPEED
	local abs = math.abs

	-- 1. 적분 (예측 위치). 세로는 등가속도 정확해(평균 속도): 반암시 오일러면 1/30초 스텝에서 꼭대기가 vy·dt/2만큼 낮아
	-- 배트·자석 깡충이 덜 뜬다 (배트 Lv0 상승 1.05 → 0.72, Studio 2026-10-21)
	local halfDrop = gs * sh * 0.5
	for i = 1, n do
		if not asleep[i] then
			ox[i], oy[i], oz[i] = px[i], py[i], pz[i]
			px[i] += vx[i] * sh
			py[i] += vy[i] * sh - halfDrop
			vy[i] -= gs
			pz[i] += vz[i] * sh
			hit[i] = 0
			on[i] = 0
			pv[i] = vy[i]
			imp[i] = 0
		else
			pv[i] = 0
		end
	end

	-- 2. 제약 반복: 벽·바닥 → 큐브끼리. 마지막에 벽을 한 번 더 (벽 밖으로는 절대 안 나감)
	for _ = 1, self.iterations do
		bounds(self)
		for k = 1, np do
			local a, b = pa[k], pb[k]
			local sa, sb = asleep[a], asleep[b]
			if sa and sb then
				continue
			end
			local ha, hb = h[a], h[b]
			local dx = px[b] - px[a]
			local ovx = ha + hb - abs(dx)
			if ovx <= 0 then
				continue
			end
			local dy = py[b] - py[a]
			local ovy = ha + hb - abs(dy)
			if ovy <= 0 then
				continue
			end
			local dz = pz[b] - pz[a]
			local ovz = ha + hb - abs(dz)
			if ovz <= 0 then
				continue
			end
			-- 밀어낼 축: 부분 스텝 시작 때 떨어져 있던 축(들어온 방향) 중 가장 얕은 축.
			-- 가장 얕은 축만 보면 좁은 틈에 떨어지는 큐브가 옆으로 밀려 끼인다. 처음부터 겹쳐 있었으면 가장 얕은 축
			local r = ha + hb - 1e-6
			local qa, qb = not sa, not sb
			local sepX = abs((if qb then ox[b] else px[b]) - (if qa then ox[a] else px[a])) >= r
			local sepY = abs((if qb then oy[b] else py[b]) - (if qa then oy[a] else py[a])) >= r
			local sepZ = abs((if qb then oz[b] else pz[b]) - (if qa then oz[a] else pz[a])) >= r
			if not (sepX or sepY or sepZ) then
				sepX, sepY, sepZ = true, true, true
			end
			local axis, best = 0, math.huge
			if sepX then
				axis, best = 1, ovx
			end
			if sepY and ovy < best then
				axis, best = 2, ovy
			end
			if sepZ and ovz < best then
				axis = 3
			end
			if axis == 2 then
				-- 세로: 위 큐브만 올린다(쌓임 떨림 방지). 위가 잠들어 있고 아주 조금이면 아래를 내린다
				local up, lo = b, a
				if dy < 0 then
					up, lo = a, b
				end
				if asleep[up] and (ovy < wakeDist and not asleep[lo]) then
					py[lo] -= ovy
				else
					if asleep[up] then
						wakeSlot(self, up)
						hit[up], on[up] = 0, 0
					end
					py[up] += ovy
					hit[up] = bit32.bor(hit[up], HIT_SUPPORT)
					-- 받침 기록: 큐브 하나면 그 슬롯, 바닥이나 둘 이상이면 -1 (모서리 미끄럼 판정용)
					local o = on[up]
					on[up] = if o == 0 or o == lo then lo else -1
					-- 받침보다 빠르게 내려오던 만큼 = 착지 세기 (같이 떨어지는 쌓임은 0)
					local d = pv[lo] - pv[up]
					if d > imp[up] then
						imp[up] = d
					end
				end
			else
				-- 가로: 역질량(부피) 비율로 나눠 민다. 그 축으로 벽에 닿은 큐브는 못 민다(벽과 큰 큐브 사이 끼임 방지).
				-- 잠든 큐브도 밀린다(고정 벽으로 두면 좁은 틈에 끼인 채 풀리지 않는다). 몫이 아주 작으면 깨우지 않고 상대가 다 진다
				local isX = axis == 1
				local wall = if isX then HIT_WALL_X else HIT_WALL_Z
				local ov = if isX then ovx else ovz
				-- 타고 넘기: 한쪽만 뛰어오르는 중이면 그쪽이 혼자 비켜난다(막는 큐브는 그대로, 가로 속도는 아래 3에서 지킴)
				local ca = not sa and launched[a] and vy[a] + gs > climb and not bit32.btest(hit[a], wall)
				local cb = not sb and launched[b] and vy[b] + gs > climb and not bit32.btest(hit[b], wall)
				if ca ~= cb then
					local c = if ca then a else b
					local d = if isX then dx else dz
					local s = if (d >= 0) == ca then -ov else ov -- a는 d 반대쪽으로, b는 d 쪽으로
					if isX then
						px[c] += s
					else
						pz[c] += s
					end
					hit[c] = bit32.bor(hit[c], HIT_CLIMB)
					continue
				end
				local wa = if bit32.btest(hit[a], wall) then 0 else w[a]
				local wb = if bit32.btest(hit[b], wall) then 0 else w[b]
				local ws = wa + wb
				if ws <= 0 then
					continue
				end
				local ma, mb = ov * wa / ws, ov * wb / ws
				hit[a] = bit32.bor(hit[a], HIT_SIDE)
				hit[b] = bit32.bor(hit[b], HIT_SIDE)
				-- 잠든 큐브는 미는 쪽이 느리면(실제 속도 SHOVE_SPEED 미만: 미끄럼·기대기) 깨우지 않고 상대가 다 진다.
				-- 느린 미끄럼이 잠든 이웃을 깨우고, 깬 이웃이 또 미끄러지는 연쇄로 더미가 잠들지 못하던 것 (단계 4 slumpY).
				-- 빠른 충돌·끼임(끼임 풀기가 act를 올려 둠)이면 깨워서 질량 비율로 민다
				if sa then
					if act[b] < shove2 and wb > 0 then
						ma, mb = 0, ov
					else
						wakeSlot(self, a)
						hit[a], on[a] = 0, 0
					end
				elseif sb then
					if act[a] < shove2 and wa > 0 then
						ma, mb = ov, 0
					else
						wakeSlot(self, b)
						hit[b], on[b] = 0, 0
					end
				end
				if (if isX then dx else dz) < 0 then
					ma, mb = -ma, -mb
				end
				if isX then
					px[a] -= ma
					px[b] += mb
				else
					pz[a] -= ma
					pz[b] += mb
				end
			end
		end
	end
	bounds(self)

	-- 3. 속도 = 이동 / 시간, 반발, 마찰, 모서리 미끄럼
	local e = self.restitution
	local bmin = TraySim.BOUNCE_MIN
	local fr = self.friction * gs
	local tipV = TraySim.TIP_SPEED
	local slid, slideTime, slideHigh = self.slid, TraySim.SLIDE_TIME, TraySim.SLIDE_TIME_HIGH
	local scatter, scatterMin = TraySim.SCATTER, TraySim.SCATTER_MIN
	local slumpY = self.slumpY
	local slumpHigh = slumpY * TraySim.SLUMP_HIGH
	local scatterY = slumpY * TraySim.SCATTER_FROM
	for i = 1, n do
		if asleep[i] then
			continue
		end
		local f = hit[i]
		local ux, uy, uz = vx[i], vy[i], vz[i] -- 제약 전 속도
		local nvx = (px[i] - ox[i]) / sh
		local nvy = (py[i] - oy[i]) / sh
		if not bit32.btest(f, HIT_SUPPORT + HIT_CEIL) then
			nvy -= halfDrop / sh -- 평균 속도 적분이라 끝 속도는 반 스텝 중력을 더 뺀다 (자유 낙하면 vy - g·sh 그대로)
		end
		local nvz = (pz[i] - oz[i]) / sh
		if f ~= 0 then
			-- 타고 넘기: 뛰어오르는 중(위로 CLIMB_SPEED 이상)에 옆 큐브에 막히면 가로 속도를 버리지 않는다.
			-- 면을 따라 올라가다 윗면을 넘으면 계속 나아가고, 그동안 막는 큐브는 질량 비율로 옆으로 밀린다
			-- (회전이 없으니 자석 깡충이 사이에 낀 큐브에 막혀 제자리만 뛰던 문제, 단계 4 Studio)
			if bit32.band(f, HIT_CLIMB + HIT_SIDE + HIT_WALL_X + HIT_WALL_Z) == HIT_CLIMB then
				nvx, nvz = ux, uz
			end
			if (bit32.btest(f, HIT_FLOOR) and uy < -bmin) or (bit32.btest(f, HIT_CEIL) and uy > bmin) then
				nvy = -e * uy
			end
			-- 큐브 위에 세게 떨어지면 옆으로 튕겨 낸다 (회전 대신 구르기). 없으면 고정된 드로퍼 자리에 기둥이 선다
			if
				imp[i] > scatterMin
				and py[i] - h[i] > scatterY
				and not bit32.btest(f, HIT_FLOOR)
				and not launched[i]
			then
				local kick = (imp[i] - scatterMin) * scatter
				local lo = on[i]
				local ex, ez = 0, 0
				if lo > 0 then
					ex, ez = px[i] - px[lo], pz[i] - pz[lo]
				end
				local d = math.sqrt(ex * ex + ez * ez)
				if d < 0.1 * h[i] then
					-- 거의 한가운데: 정해진 순서의 각도 (황금각, 결정적이라 테스트 재현)
					self.spin = (self.spin + 2.39996) % (2 * math.pi)
					ex, ez, d = math.cos(self.spin), math.sin(self.spin), 1
				end
				nvx += ex / d * kick
				nvz += ez / d * kick
			end
			if bit32.btest(f, HIT_WALL_X) and abs(ux) > bmin then
				nvx = -e * ux
			end
			if bit32.btest(f, HIT_WALL_Z) and abs(uz) > bmin then
				nvz = -e * uz
			end
			if bit32.btest(f, HIT_SUPPORT) then
				sup[i] = true
				-- 깊은 겹침을 한 부분 스텝에 풀면 위치 차이가 큰 속도가 되어 튀어 오른다. 받침이 올려 준 속도는 상한
				local cap = math.max(uy + gs, 0) + TraySim.PUSH_SPEED
				if nvy > cap then
					nvy = cap
				end
				local s = math.sqrt(nvx * nvx + nvz * nvz)
				if s > 0 then
					local k = math.max(0, s - fr) / s
					nvx *= k
					nvz *= k
				end
			end
		end
		-- 잠 판정은 실제로 움직인 양으로 (모서리 미끄럼이 이웃에 막혀 있으면 잠들 수 있게)
		act[i] = nvx * nvx + nvy * nvy + nvz * nvz
		-- 미끄럼 (회전이 없어서 대신). 옆 큐브에 기대어 있으면 없음 (벽 위 큐브만 예외, 아래).
		--  - 모서리: 큐브 하나에만 얹혔고 무게중심이 그 윗면 밖이면 그쪽으로 (실제로도 넘어짐, 한도 없음). 그쪽이 벽이면 무너짐으로
		--  - 무너짐: 무게중심이 받침 위여도 밑면이 slumpY(외줄) / slumpHigh(받침 여럿, 벽 위로 솟은 더미)보다 높으면 바깥으로.
		--    큐브마다 SLIDE_TIME(벽 위 SLIDE_TIME_HIGH)초까지, 막혀도 시간이 흐른다(바닥에 닿으면 다시 채움).
		--    한도가 없으면 넓은 더미 위·구석에서 끝없이 밀고 있어 잠들지 못한다
		local lo = on[i]
		if bit32.btest(f, HIT_FLOOR) then
			slid[i] = 0
		elseif lo ~= 0 then
			local side = bit32.btest(f, HIT_SIDE)
			local ex, ez, sx, sz = 0, 0, 0, 0
			if lo > 0 then
				local hl = h[lo]
				ex, ez = px[i] - px[lo], pz[i] - pz[lo]
				sx = if ex > hl then 1 elseif ex < -hl then -1 else 0
				sz = if ez > hl then 1 elseif ez < -hl then -1 else 0
				if (sx ~= 0 or sz ~= 0 or py[i] - h[i] > slumpY) and restsOnOther(self, i, lo) then
					-- 두 받침에 걸친 다리: 한 번에 하나만 풀려 on이 번갈아 바뀌므로 닿아 있는 받침을 직접 찾는다
					sx, sz, lo = 0, 0, -1
				end
				-- 벽 쪽으로 넘어가려는데 벽에 붙어 있으면 벽과 받침 사이에 끼인 것: 벽에서 멀어지는 무너짐으로 넘긴다
				-- (안 그러면 벽에 기댄 채 벽 위로 솟아 잠든다)
				if sx ~= 0 and sx * px[i] > 0 and math.abs(px[i]) + h[i] > self.halfX - 0.1 then
					sx = 0
				end
				if sz ~= 0 and sz * pz[i] > 0 and math.abs(pz[i]) + h[i] > self.halfZ - 0.1 then
					sz = 0
				end
			end
			if side then
				-- 옆 큐브에 기대 있으면 보통은 그대로 (넘어가기·무너짐 없음: 잠든 이웃을 깨우는 연쇄 방지).
				-- 다만 밑면이 slumpHigh(벽 위)보다 높으면 받침과 이웃 사이에 낀 꼭대기 큐브: 한도 안에서 이웃을 밀며 계속 간다
				if slid[i] < slideHigh and py[i] - h[i] > slumpHigh then
					act[i] = math.max(act[i], shove2 + 1)
					slid[i] += sh
				else
					vx[i], vy[i], vz[i] = nvx, nvy, nvz
					continue
				end
			end
			if sx ~= 0 or sz ~= 0 then
				if sx ~= 0 and nvx * sx < tipV then
					nvx = sx * tipV
				end
				if sz ~= 0 and nvz * sz < tipV then
					nvz = sz * tipV
				end
			elseif
				slid[i] < (if py[i] - h[i] > slumpHigh then slideHigh else slideTime)
				and py[i] - h[i] > (if lo > 0 then slumpY else slumpHigh)
			then
				-- 한가운데·받침 여럿이면 큐브마다 정해진 방향 (늘 같은 쪽 → 떨림 없음)
				local d = math.sqrt(ex * ex + ez * ez)
				if d < 0.1 * h[i] then
					local ang = self.ids[i] * 2.39996
					ex, ez = math.cos(ang), math.sin(ang)
				end
				-- 벽에 붙은 기둥은 벽에서 멀어지는 쪽으로. 이번 부분 스텝 접촉(hit)이 아니라 위치로 본다:
				-- 접촉으로 보면 벽 쪽 ↔ 반대쪽이 스텝마다 번갈아 구석 큐브가 잠들지 못한다
				if math.abs(px[i]) + h[i] > self.halfX - 0.1 then
					ex = if px[i] > 0 then -math.abs(ex) - 0.5 else math.abs(ex) + 0.5
				end
				if math.abs(pz[i]) + h[i] > self.halfZ - 0.1 then
					ez = if pz[i] > 0 then -math.abs(ez) - 0.5 else math.abs(ez) + 0.5
				end
				d = math.sqrt(ex * ex + ez * ez)
				if nvx * nvx + nvz * nvz < tipV * tipV then
					nvx, nvz = ex / d * tipV, ez / d * tipV
				end
				slid[i] += sh -- 막혀 못 움직여도 시간은 쓴다 (안 쓰면 막힌 큐브가 영영 밀고만 있어 잠들지 못함)
			end
		end
		vx[i], vy[i], vz[i] = nvx, nvy, nvz
	end
end

local function fixedStep(self: Sim)
	local n = self.n
	local dt = TraySim.DT
	local vx, vy, vz, h, m, asleep = self.vx, self.vy, self.vz, self.h, self.m, self.asleep
	local g = self.gravity

	-- 부분 스텝 수: 한 부분 스텝 이동 ≤ 최소 반 변 × 0.8. 속도 상한은 SUB_MAX로 감당되는 만큼
	local minHalf = math.huge
	for i = 1, n do
		if h[i] < minHalf then
			minHalf = h[i]
		end
	end
	local maxMove = minHalf * 0.8
	local vmax = maxMove * TraySim.SUB_MAX / dt - g * dt
	local fastest = 0
	for i = 1, n do
		if asleep[i] then
			m[i] = 0
			continue
		end
		local x, y, z = vx[i], vy[i], vz[i]
		local s = math.sqrt(x * x + y * y + z * z)
		if s > vmax then
			local k = vmax / s
			vx[i], vy[i], vz[i] = x * k, y * k, z * k
			s = vmax
		end
		s += g * dt
		if s > fastest then
			fastest = s
		end
		m[i] = s * dt + 0.05
		self.sup[i] = false
	end
	local subs = math.clamp(math.ceil(fastest * dt / maxMove), 1, TraySim.SUB_MAX)

	broadphase(self)
	local sh = dt / subs
	for _ = 1, subs do
		substep(self, sh)
	end

	-- 끼임 풀기: 틈보다 넓은 큐브가 끼면 한 스텝에 다 못 푼다. 느린 짝이 스텝 끝에도 겹쳐 있으면
	-- 둘 다 깨워 둔다(잠 카운트 0) → 다음 스텝들에 질량 비율로 서로 밀어 틈을 벌린다. 빠른 충돌 중 겹침은 다음 스텝이 푼다
	local sleep, sup, act, jam = self.sleep, self.sup, self.act, self.jam
	local px, py, pz, pa, pb = self.px, self.py, self.pz, self.pa, self.pb
	local slow2 = TraySim.SLEEP_SPEED * TraySim.SLEEP_SPEED
	local wake2 = TraySim.WAKE_SPEED * TraySim.WAKE_SPEED
	for k = 1, self.np do
		local a, b = pa[k], pb[k]
		if (asleep[a] and asleep[b]) or act[a] > wake2 or act[b] > wake2 then
			continue
		end
		local ha, hb = h[a], h[b]
		local r = ha + hb
		local ov = math.min(r - math.abs(px[b] - px[a]), r - math.abs(py[b] - py[a]), r - math.abs(pz[b] - pz[a]))
		if ov > TraySim.JAM_OVERLAP * math.min(ha, hb) and math.max(jam[a], jam[b]) < TraySim.JAM_GIVEUP then
			-- 둘 다 깨워 둔다 (잠든 채 겹쳐 굳지 않게). 다음 스텝엔 느려도 잠든 이웃을 밀 수 있게(SHOVE_SPEED) act를 올려 둔다.
			-- JAM_GIVEUP 스텝 넘게 안 풀리면 회전 없이는 풀 수 없는 끼임(벽까지 꽉 찬 줄, 위에도 큐브)이라 보고 그대로 잠들게 둔다
			wakeSlot(self, a)
			wakeSlot(self, b)
			local push = TraySim.SHOVE_SPEED * TraySim.SHOVE_SPEED + 1
			act[a] = math.max(act[a], push)
			act[b] = math.max(act[b], push)
			jam[a] += 1
			jam[b] += 1
		end
	end

	-- 4. 잠
	for i = 1, n do
		if asleep[i] then
			continue
		end
		if sup[i] and act[i] < slow2 then
			sleep[i] += 1
			if sleep[i] >= TraySim.SLEEP_FRAMES then
				asleep[i] = true
				self.launched[i] = false
				self.nAwake -= 1
				vx[i], vy[i], vz[i] = 0, 0, 0
			end
		else
			sleep[i] = 0
		end
	end
end

-- dt를 누적해 고정 스텝을 0..MAX_STEPS번 돌린다. 돌린 스텝 수를 돌려준다
function TraySim.step(self: Sim, dt: number): number
	self.acc += dt
	local ran = 0
	local due = TraySim.DT - 1e-9 -- 1/60 두 번이 1/30에 못 미치는 반올림 오차
	while self.acc >= due and ran < TraySim.MAX_STEPS do
		self.acc -= TraySim.DT
		ran += 1
		if self.nAwake > 0 then
			fixedStep(self)
		end
	end
	if self.acc >= due then
		self.acc = 0 -- 밀린 시간은 버린다 (느려질지언정 몰아서 돌지 않음)
	end
	return ran
end

return TraySim
