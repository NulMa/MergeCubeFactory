--!strict
-- 큐브 복제 메시지 직렬화 (Roblox API 없음 → Lune 테스트 가능)
-- 위치·속도는 Vector3가 아니라 x,y,z 숫자 필드로 받는다.
--
-- [신뢰 이벤트] CubeEvt (RemoteEvent, buffer). 여러 op를 한 패킷에 묶는다. 모든 정수는 little-endian.
--   u16 opCount
--   op마다 u8 opcode 로 시작: 1 spawn, 2 remove, 3 retier, 4 reset
--   spawn   (29B): u8 1 | u16 id | u8 tier | u8 variant | f32 x,y,z | f32 vx,vy,vz
--   remove   (4B): u8 2 | u16 id | u8 reason (1 merge, 2 sell, 3 steal, 4 other)
--   retier   (6B): u8 3 | u16 id | u8 tier | u8 variant | u8 atMax (0/1)
--   reset (3B+17B×n): u8 4 | u16 n | n × { u16 id | u8 tier | u8 variant | f32 x,y,z | u8 atMax }
--   신뢰 이벤트는 빈도가 낮으므로 위치·속도를 양자화하지 않고 f32 그대로 보낸다.
--
-- [비신뢰 스냅샷] CubeSnap (UnreliableRemoteEvent, buffer). 보정이 필요한 큐브만 보낸다 (데드 레코닝, shared/CubePredict).
--   헤더 7B: u16 seq (65536이면 0으로 감김) | u16 tick (상태의 시뮬 틱 mod 65536) | u8 hz (이 등급 스냅샷 빈도)
--            | u8 nMove | u8 nRest (각각 최대 255)
--   움직임 항목 12B × nMove: u16 id | 40비트 위치 | 40비트 속도   (각 40비트 = u32 아래 + u8 위, little-endian)
--     위치 40비트 = x + y·4096 + z·4096²        (12비트씩, 값 + 2048. 위 4비트 0)
--     속도 40비트 = vx + vy·4096 + vz·4096² + air·2^36
--   정지 항목 7B × nRest: u16 id | 40비트 위치 (속도 0, air 아님 = 잠든 자리)
--     위치: 플롯 중심 기준 스터드 × 32 반올림 (범위 ±64스터드, 해상도 1/32, 최대 오차 1/64). 트레이 반폭 ≤ 28, 천장 48
--     속도: 스터드/초 × 8 반올림 (범위 ±256스터드/초, 해상도 1/8, 최대 오차 1/16 → 1초 예측 오차 ≤ 0.06스터드)
--     air: 공중이라 중력 예측 (shared/CubePredict)
--   인코더는 air가 아니고 양자화한 속도가 모두 0인 항목을 정지 항목으로 보낸다 (디코드 결과는 같다). 순서는 움직임 → 정지.
--   범위를 넘는 값은 오류 없이 끝값으로 클램프하고, NaN은 0으로 본다.
--   서버가 예측에 쓸 값은 snapPos/snapVel (디코드 결과와 똑같은 값).
--   (2026-10-22 전: 헤더 4B + 항목 11B = id + i16 위치(1/64) + i8 속도(2스터드/초, 오차 1스터드/초라 예측이 0.25초 만에 0.25스터드 어긋남))

local CubeCodec = {}

export type Spawn = {
	kind: "spawn",
	id: number,
	tier: number,
	variant: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
}
export type Remove = { kind: "remove", id: number, reason: number }
export type Retier = { kind: "retier", id: number, tier: number, variant: number, atMax: boolean }
export type ResetEntry = {
	id: number,
	tier: number,
	variant: number,
	x: number,
	y: number,
	z: number,
	atMax: boolean,
}
export type Reset = { kind: "reset", entries: { ResetEntry } }
export type Op = Spawn | Remove | Retier | Reset
export type SnapEntry = {
	id: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	air: boolean, -- 공중(중력 예측). 아니면 직선 (받쳐져 미끄러짐·정지)
}
export type SnapHeader = { seq: number, tick: number, hz: number }

-- 제거 사유 (remove op의 reason)
CubeCodec.REASON_MERGE = 1
CubeCodec.REASON_SELL = 2
CubeCodec.REASON_STEAL = 3
CubeCodec.REASON_OTHER = 4

-- 스냅샷 양자화 배율: 위치는 1스터드 = 32단위, 속도는 1스터드/초 = 8단위 (12비트 부호 있는 값)
CubeCodec.POS_SCALE = 32
CubeCodec.VEL_SCALE = 8
CubeCodec.SNAP_HEADER_SIZE = 7
CubeCodec.SNAP_ENTRY_SIZE = 12 -- 움직임 항목
CubeCodec.SNAP_REST_SIZE = 7 -- 정지 항목
CubeCodec.SNAP_MAX = 255 -- 한 패킷 종류별 최대 항목

local OP_SPAWN, OP_REMOVE, OP_RETIER, OP_RESET = 1, 2, 3, 4
local SIZE_SPAWN, SIZE_REMOVE, SIZE_RETIER = 29, 4, 6
local RESET_HEAD_SIZE, RESET_ENTRY_SIZE = 3, 17
local MAX_U16 = 0xFFFF

-- 숫자를 정수 범위로 맞춘다. NaN은 0
local function clampInt(v: number, lo: number, hi: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(math.round(v), lo, hi)
end

local function clampU8(v: number): number
	return clampInt(v, 0, 255)
end

local function clampU16(v: number): number
	return clampInt(v, 0, MAX_U16)
end

local function boolByte(v: boolean): number
	return if v then 1 else 0
end

-- seq는 감싸기(mod 65536). 클램프하면 65535에 붙어 버린다
local function wrapU16(v: number): number
	if v ~= v then
		return 0
	end
	return math.round(v) % 65536
end

local function opSize(op: Op): number
	if op.kind == "spawn" then
		return SIZE_SPAWN
	elseif op.kind == "remove" then
		return SIZE_REMOVE
	elseif op.kind == "retier" then
		return SIZE_RETIER
	else
		return RESET_HEAD_SIZE + math.min(#op.entries, MAX_U16) * RESET_ENTRY_SIZE
	end
end

-- ===== 신뢰 이벤트 =====

function CubeCodec.encodeEvents(ops: { Op }): buffer
	local n = math.min(#ops, MAX_U16)
	local size = 2
	for i = 1, n do
		size += opSize(ops[i])
	end

	local b = buffer.create(size)
	buffer.writeu16(b, 0, n)
	local p = 2
	for i = 1, n do
		local op = ops[i]
		if op.kind == "spawn" then
			buffer.writeu8(b, p, OP_SPAWN)
			buffer.writeu16(b, p + 1, clampU16(op.id))
			buffer.writeu8(b, p + 3, clampU8(op.tier))
			buffer.writeu8(b, p + 4, clampU8(op.variant))
			buffer.writef32(b, p + 5, op.x)
			buffer.writef32(b, p + 9, op.y)
			buffer.writef32(b, p + 13, op.z)
			buffer.writef32(b, p + 17, op.vx)
			buffer.writef32(b, p + 21, op.vy)
			buffer.writef32(b, p + 25, op.vz)
			p += SIZE_SPAWN
		elseif op.kind == "remove" then
			buffer.writeu8(b, p, OP_REMOVE)
			buffer.writeu16(b, p + 1, clampU16(op.id))
			buffer.writeu8(b, p + 3, clampU8(op.reason))
			p += SIZE_REMOVE
		elseif op.kind == "retier" then
			buffer.writeu8(b, p, OP_RETIER)
			buffer.writeu16(b, p + 1, clampU16(op.id))
			buffer.writeu8(b, p + 3, clampU8(op.tier))
			buffer.writeu8(b, p + 4, clampU8(op.variant))
			buffer.writeu8(b, p + 5, boolByte(op.atMax))
			p += SIZE_RETIER
		else
			local entries = op.entries
			local m = math.min(#entries, MAX_U16)
			buffer.writeu8(b, p, OP_RESET)
			buffer.writeu16(b, p + 1, m)
			for j = 1, m do
				local e = entries[j]
				local q = p + RESET_HEAD_SIZE + (j - 1) * RESET_ENTRY_SIZE
				buffer.writeu16(b, q, clampU16(e.id))
				buffer.writeu8(b, q + 2, clampU8(e.tier))
				buffer.writeu8(b, q + 3, clampU8(e.variant))
				buffer.writef32(b, q + 4, e.x)
				buffer.writef32(b, q + 8, e.y)
				buffer.writef32(b, q + 12, e.z)
				buffer.writeu8(b, q + 16, boolByte(e.atMax))
			end
			p += RESET_HEAD_SIZE + m * RESET_ENTRY_SIZE
		end
	end
	return b
end

local function decodeEventsUnsafe(b: buffer): { Op }
	local ops: { Op } = {}
	local count = buffer.readu16(b, 0)
	local p = 2
	for _ = 1, count do
		local code = buffer.readu8(b, p)
		if code == OP_SPAWN then
			ops[#ops + 1] = {
				kind = "spawn",
				id = buffer.readu16(b, p + 1),
				tier = buffer.readu8(b, p + 3),
				variant = buffer.readu8(b, p + 4),
				x = buffer.readf32(b, p + 5),
				y = buffer.readf32(b, p + 9),
				z = buffer.readf32(b, p + 13),
				vx = buffer.readf32(b, p + 17),
				vy = buffer.readf32(b, p + 21),
				vz = buffer.readf32(b, p + 25),
			} :: Spawn
			p += SIZE_SPAWN
		elseif code == OP_REMOVE then
			ops[#ops + 1] = {
				kind = "remove",
				id = buffer.readu16(b, p + 1),
				reason = buffer.readu8(b, p + 3),
			} :: Remove
			p += SIZE_REMOVE
		elseif code == OP_RETIER then
			ops[#ops + 1] = {
				kind = "retier",
				id = buffer.readu16(b, p + 1),
				tier = buffer.readu8(b, p + 3),
				variant = buffer.readu8(b, p + 4),
				atMax = buffer.readu8(b, p + 5) == 1,
			} :: Retier
			p += SIZE_RETIER
		elseif code == OP_RESET then
			local n = buffer.readu16(b, p + 1)
			local entries: { ResetEntry } = {}
			for j = 0, n - 1 do
				local q = p + RESET_HEAD_SIZE + j * RESET_ENTRY_SIZE
				entries[#entries + 1] = {
					id = buffer.readu16(b, q),
					tier = buffer.readu8(b, q + 2),
					variant = buffer.readu8(b, q + 3),
					x = buffer.readf32(b, q + 4),
					y = buffer.readf32(b, q + 8),
					z = buffer.readf32(b, q + 12),
					atMax = buffer.readu8(b, q + 16) == 1,
				}
			end
			ops[#ops + 1] = { kind = "reset", entries = entries } :: Reset
			p += RESET_HEAD_SIZE + n * RESET_ENTRY_SIZE
		else
			error("unknown cube op " .. code)
		end
	end
	if p ~= buffer.len(b) then
		error("trailing bytes in cube events")
	end
	return ops
end

-- 잘못된 버퍼(잘림, 알 수 없는 opcode, 남은 바이트)면 nil
function CubeCodec.decodeEvents(b: buffer): { Op }?
	local ok, result = pcall(decodeEventsUnsafe, b)
	if ok then
		return result
	end
	return nil
end

-- ===== 비신뢰 스냅샷 =====

local F12_MIN, F12_MAX = -2048, 2047 -- 12비트 부호 있는 값 (저장은 + 2048)
local B12, B24, B36 = 4096, 16777216, 68719476736 -- 4096^1, 4096^2, 2^36
local B32 = 4294967296

local function quantPos(v: number): number
	return clampInt(v * CubeCodec.POS_SCALE, F12_MIN, F12_MAX)
end

local function quantVel(v: number): number
	return clampInt(v * CubeCodec.VEL_SCALE, F12_MIN, F12_MAX)
end

-- 디코드하면 나올 값 (서버가 "클라가 아는 상태"를 기억할 때 쓴다 → 서버 예측 = 클라 예측)
function CubeCodec.snapPos(v: number): number
	return quantPos(v) / CubeCodec.POS_SCALE
end

function CubeCodec.snapVel(v: number): number
	return quantVel(v) / CubeCodec.VEL_SCALE
end

-- 40비트 정수 (double로 정확) 쓰기·읽기: u32 아래 + u8 위
local function write40(b: buffer, p: number, n: number)
	buffer.writeu32(b, p, n % B32)
	buffer.writeu8(b, p + 4, n // B32)
end

local function read40(b: buffer, p: number): number
	return buffer.readu32(b, p) + buffer.readu8(b, p + 4) * B32
end

local function pack3(a: number, c: number, d: number): number
	return (a + 2048) + (c + 2048) * B12 + (d + 2048) * B24
end

local function field(n: number, k: number): number
	return (n // k) % B12 - 2048
end

local function isRest(e: SnapEntry): boolean
	return not e.air and quantVel(e.vx) == 0 and quantVel(e.vy) == 0 and quantVel(e.vz) == 0
end

-- 움직임 항목 먼저, 정지 항목 뒤 (각각 최대 SNAP_MAX, 넘는 것은 버림 → 부르는 쪽이 나눠 보낸다)
function CubeCodec.encodeSnapshot(seq: number, tick: number, hz: number, entries: { SnapEntry }): buffer
	local moving: { SnapEntry } = {}
	local rest: { SnapEntry } = {}
	for _, e in entries do
		if isRest(e) then
			if #rest < CubeCodec.SNAP_MAX then
				table.insert(rest, e)
			end
		elseif #moving < CubeCodec.SNAP_MAX then
			table.insert(moving, e)
		end
	end
	local nm, nr = #moving, #rest
	local b = buffer.create(CubeCodec.SNAP_HEADER_SIZE + nm * CubeCodec.SNAP_ENTRY_SIZE + nr * CubeCodec.SNAP_REST_SIZE)
	buffer.writeu16(b, 0, wrapU16(seq))
	buffer.writeu16(b, 2, wrapU16(tick))
	buffer.writeu8(b, 4, clampU8(hz))
	buffer.writeu8(b, 5, nm)
	buffer.writeu8(b, 6, nr)
	local p = CubeCodec.SNAP_HEADER_SIZE
	for _, e in moving do
		buffer.writeu16(b, p, clampU16(e.id))
		write40(b, p + 2, pack3(quantPos(e.x), quantPos(e.y), quantPos(e.z)))
		write40(b, p + 7, pack3(quantVel(e.vx), quantVel(e.vy), quantVel(e.vz)) + (if e.air then B36 else 0))
		p += CubeCodec.SNAP_ENTRY_SIZE
	end
	for _, e in rest do
		buffer.writeu16(b, p, clampU16(e.id))
		write40(b, p + 2, pack3(quantPos(e.x), quantPos(e.y), quantPos(e.z)))
		p += CubeCodec.SNAP_REST_SIZE
	end
	return b
end

-- 길이가 헤더의 개수와 맞지 않으면 nil, nil
function CubeCodec.decodeSnapshot(b: buffer): (SnapHeader?, { SnapEntry }?)
	local size = buffer.len(b)
	if size < CubeCodec.SNAP_HEADER_SIZE then
		return nil, nil
	end
	local nm, nr = buffer.readu8(b, 5), buffer.readu8(b, 6)
	if size ~= CubeCodec.SNAP_HEADER_SIZE + nm * CubeCodec.SNAP_ENTRY_SIZE + nr * CubeCodec.SNAP_REST_SIZE then
		return nil, nil
	end

	local ps, vs = CubeCodec.POS_SCALE, CubeCodec.VEL_SCALE
	local entries: { SnapEntry } = {}
	local p = CubeCodec.SNAP_HEADER_SIZE
	for _ = 1, nm do
		local pos = read40(b, p + 2)
		local vel = read40(b, p + 7)
		local air = vel >= B36
		if air then
			vel -= B36
		end
		table.insert(entries, {
			id = buffer.readu16(b, p),
			x = field(pos, 1) / ps,
			y = field(pos, B12) / ps,
			z = field(pos, B24) / ps,
			vx = field(vel, 1) / vs,
			vy = field(vel, B12) / vs,
			vz = field(vel, B24) / vs,
			air = air,
		})
		p += CubeCodec.SNAP_ENTRY_SIZE
	end
	for _ = 1, nr do
		local pos = read40(b, p + 2)
		table.insert(entries, {
			id = buffer.readu16(b, p),
			x = field(pos, 1) / ps,
			y = field(pos, B12) / ps,
			z = field(pos, B24) / ps,
			vx = 0,
			vy = 0,
			vz = 0,
			air = false,
		})
		p += CubeCodec.SNAP_REST_SIZE
	end
	return { seq = buffer.readu16(b, 0), tick = buffer.readu16(b, 2), hz = buffer.readu8(b, 4) }, entries
end

return CubeCodec
