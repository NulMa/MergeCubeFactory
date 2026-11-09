--!strict
-- lune run tests/merge/CubeCodec.spec.luau (game 디렉터리에서)

local process = require("@lune/process")
local CubeCodec = require("../../src/merge/shared/CubeCodec")

local passed, failed = 0, 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print(`FAIL  {name}{if detail then ": " .. detail else ""}`)
	end
end

local function eq(name: string, got: any, want: any)
	check(name, got == want, `got {tostring(got)}, want {tostring(want)}`)
end

-- 값이 허용 오차 안이면 통과 (양자화 검사용)
local function near(name: string, got: number, want: number, tol: number)
	local diff = math.abs(got - want)
	check(name, diff <= tol + 1e-9, `got {got}, want {want}, diff {diff}`)
end

-- 테이블을 재귀적으로 비교 (이벤트 round-trip 검사용)
local function deepEq(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEq(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- ===== 신뢰 이벤트 round-trip =====
-- f32로 정확히 표현되는 값만 쓴다 (신뢰 이벤트는 양자화하지 않음)
local ops: { CubeCodec.Op } = {
	{ kind = "spawn", id = 7, tier = 3, variant = 2, x = 1.5, y = -20.25, z = 300.125, vx = -3.5, vy = 0, vz = 12.75 },
	{ kind = "remove", id = 7, reason = CubeCodec.REASON_MERGE },
	{ kind = "remove", id = 8, reason = CubeCodec.REASON_SELL },
	{ kind = "remove", id = 9, reason = CubeCodec.REASON_STEAL },
	{ kind = "remove", id = 10, reason = CubeCodec.REASON_OTHER },
	{ kind = "retier", id = 11, tier = 5, variant = 1, atMax = true },
	{ kind = "retier", id = 12, tier = 6, variant = 0, atMax = false },
	{
		kind = "reset",
		entries = {
			{ id = 1, tier = 1, variant = 0, x = 0, y = 2, z = -4, atMax = false },
			{ id = 2, tier = 40, variant = 3, x = -100.5, y = 0.25, z = 50, atMax = true },
		},
	},
}

local decodedOps = CubeCodec.decodeEvents(CubeCodec.encodeEvents(ops))
check("events round-trip every op type", decodedOps ~= nil and deepEq(ops, decodedOps))
eq("events round-trip op count", decodedOps and #decodedOps, #ops)

-- spawn 하나 = 2(헤더) + 29 바이트
eq("spawn op size", buffer.len(CubeCodec.encodeEvents({ ops[1] })), 2 + 29)
eq("remove op size", buffer.len(CubeCodec.encodeEvents({ ops[2] })), 2 + 4)
eq("retier op size", buffer.len(CubeCodec.encodeEvents({ ops[6] })), 2 + 6)
eq("reset op size 2 entries", buffer.len(CubeCodec.encodeEvents({ ops[8] })), 2 + 3 + 2 * 17)

-- 빈 목록
local emptyEvents = CubeCodec.encodeEvents({})
eq("empty events size", buffer.len(emptyEvents), 2)
local decodedEmpty = CubeCodec.decodeEvents(emptyEvents)
check("empty events decode", decodedEmpty ~= nil and #decodedEmpty == 0)

-- 빈 reset 목록
local decodedEmptyReset = CubeCodec.decodeEvents(CubeCodec.encodeEvents({ { kind = "reset", entries = {} } }))
check(
	"empty reset round-trip",
	decodedEmptyReset ~= nil and deepEq(decodedEmptyReset[1], { kind = "reset", entries = {} })
)

-- id 감싸기 경계값 0 / 65535
local edgeOps: { CubeCodec.Op } = {
	{ kind = "spawn", id = 0, tier = 0, variant = 0, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0 },
	{ kind = "spawn", id = 65535, tier = 255, variant = 255, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0 },
	{ kind = "remove", id = 65535, reason = 4 },
	{ kind = "retier", id = 0, tier = 1, variant = 1, atMax = false },
}
local decodedEdge = CubeCodec.decodeEvents(CubeCodec.encodeEvents(edgeOps))
check("events id 0 and 65535 round-trip", decodedEdge ~= nil and deepEq(edgeOps, decodedEdge))

-- 잘못된 버퍼는 nil
local good = CubeCodec.encodeEvents(ops)
local truncated = buffer.create(buffer.len(good) - 1)
buffer.copy(truncated, 0, good, 0, buffer.len(good) - 1)
eq("truncated events decode nil", CubeCodec.decodeEvents(truncated), nil)

local padded = buffer.create(buffer.len(good) + 1)
buffer.copy(padded, 0, good, 0, buffer.len(good))
eq("events with trailing bytes decode nil", CubeCodec.decodeEvents(padded), nil)

local badOp = buffer.create(3)
buffer.writeu16(badOp, 0, 1)
buffer.writeu8(badOp, 2, 99)
eq("unknown opcode decode nil", CubeCodec.decodeEvents(badOp), nil)

-- ===== 비신뢰 스냅샷 =====

-- 움직임 항목 110개: 7 + 110*12 바이트
local entries110: { CubeCodec.SnapEntry } = {}
for i = 1, 110 do
	entries110[i] = {
		id = i - 1,
		x = (i - 55) * 0.5,
		y = 1.25 + i * 0.3,
		z = -(i - 55) * 0.4,
		vx = 1,
		vy = -2,
		vz = 0.5,
		air = i % 2 == 0,
	}
end
local snap110 = CubeCodec.encodeSnapshot(42, 1234, 15, entries110)
eq("110 moving entries size", buffer.len(snap110), 7 + 110 * 12)
eq("moving entry size constant", CubeCodec.SNAP_ENTRY_SIZE, 12)
eq("rest entry size constant", CubeCodec.SNAP_REST_SIZE, 7)
eq("header size constant", CubeCodec.SNAP_HEADER_SIZE, 7)

local head110, decoded110 = CubeCodec.decodeSnapshot(snap110)
eq("snapshot seq round-trip", head110 and head110.seq, 42)
eq("snapshot tick round-trip", head110 and head110.tick, 1234)
eq("snapshot hz round-trip", head110 and head110.hz, 15)
eq("snapshot count round-trip", decoded110 and #decoded110, 110)
if decoded110 then
	local idsOk, posOk, airOk, velOk = true, true, true, true
	for i, e in decoded110 do
		local src = entries110[i]
		if e.id ~= src.id then
			idsOk = false
		end
		if
			math.abs(e.x - src.x) > 1 / 64 + 1e-9
			or math.abs(e.y - src.y) > 1 / 64 + 1e-9
			or math.abs(e.z - src.z) > 1 / 64 + 1e-9
		then
			posOk = false
		end
		if e.air ~= src.air then
			airOk = false
		end
		if e.vx ~= 1 or e.vy ~= -2 or e.vz ~= 0.5 then
			velOk = false
		end
	end
	check("110-entry ids round-trip", idsOk)
	check("110-entry positions within 1/64", posOk)
	check("110-entry air flag round-trip", airOk)
	check("110-entry exact velocities round-trip", velOk)
end

-- 정지 항목 (air 아님, 양자화 속도 0): 7B, 움직임 항목 뒤로
local mixed = CubeCodec.encodeSnapshot(1, 2, 15, {
	{ id = 10, x = 1, y = 2, z = 3, vx = 0, vy = 0, vz = 0, air = false },
	{ id = 11, x = 4, y = 5, z = 6, vx = 0.01, vy = 0, vz = 0, air = false }, -- 1/16 미만 → 정지
	{ id = 12, x = 7, y = 8, z = 9, vx = 0, vy = 0, vz = 0, air = true }, -- 공중이면 움직임
	{ id = 13, x = -1, y = 0.5, z = -2, vx = 3, vy = 0, vz = 0, air = false },
})
eq("mixed snapshot size (2 moving + 2 rest)", buffer.len(mixed), 7 + 2 * 12 + 2 * 7)
local _, decodedMixed = CubeCodec.decodeSnapshot(mixed)
if decodedMixed then
	local ids = {}
	for _, e in decodedMixed do
		table.insert(ids, tostring(e.id))
	end
	eq("moving entries first, rest after", table.concat(ids, ","), "12,13,10,11")
	local r = decodedMixed[4]
	check("rest entry decodes as v=0, not air", r.vx == 0 and r.vy == 0 and r.vz == 0 and not r.air and r.x == 4)
	check("air entry with v=0 keeps air", decodedMixed[1].air and decodedMixed[1].vx == 0)
else
	check("mixed snapshot decodes", false)
end

-- 빈 스냅샷
local snapEmpty = CubeCodec.encodeSnapshot(5, 0, 5, {})
eq("empty snapshot size", buffer.len(snapEmpty), 7)
local headE, entriesE = CubeCodec.decodeSnapshot(snapEmpty)
eq("empty snapshot seq", headE and headE.seq, 5)
eq("empty snapshot count", entriesE and #entriesE, 0)

-- 항목 1개 = 7 + 12
eq("one-entry snapshot size", buffer.len(CubeCodec.encodeSnapshot(0, 0, 15, { entries110[1] })), 19)

-- 양자화 오차: 범위(±64) 안의 위치는 1/64 스터드 이내
local maxErr = 0
local entriesQ: { CubeCodec.SnapEntry } = {}
for i = 0, 199 do
	local v = -63.9 + i * (127.8 / 199)
	entriesQ[#entriesQ + 1] = { id = 1, x = v, y = -v, z = v * 0.5, vx = 0, vy = 0, vz = 0, air = false }
end
local _, decodedQ = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(1, 0, 15, entriesQ))
if decodedQ then
	for i, e in decodedQ do
		local src = entriesQ[i]
		maxErr = math.max(maxErr, math.abs(e.x - src.x), math.abs(e.y - src.y), math.abs(e.z - src.z))
	end
end
check(`position quantization max error {maxErr} <= 1/64`, decodedQ ~= nil and maxErr <= 1 / 64 + 1e-9)

-- 속도 양자화: 1/8스터드/초 단위라 오차 1/16 이내. 부호·air 조합 모두, 서버가 기억하는 값(snapVel) = 디코드 결과
local maxVelErr = 0
local velOk = true
local velIn = { -255.9, -137.3, -17.3, -1, -1 / 16, 1 / 32, 0.9, 3, 100.4, 205, 255.8 }
local velEntries: { CubeCodec.SnapEntry } = {}
for i, v in velIn do
	velEntries[i] = { id = i, x = 0, y = 0, z = 0, vx = v, vy = -v, vz = v * 0.5, air = i % 3 ~= 0 }
end
local _, decodedVel = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(0, 0, 15, velEntries))
if decodedVel then
	local byId: { [number]: CubeCodec.SnapEntry } = {}
	for _, e in decodedVel do
		byId[e.id] = e
	end
	for i, want in velIn do
		local e = byId[i]
		local src = velEntries[i]
		if not e then
			velOk = false
			continue
		end
		if e.vx == 0 and e.vy == 0 and e.vz == 0 and not e.air then
			-- 정지로 접힌 항목: air가 아니고 속도가 모두 0으로 양자화된 것만
			if src.air or CubeCodec.snapVel(want) ~= 0 then
				velOk = false
			end
			continue
		end
		maxVelErr = math.max(maxVelErr, math.abs(e.vx - want), math.abs(e.vy + want), math.abs(e.vz - want * 0.5))
		if e.air ~= src.air then
			velOk = false
		end
		if
			e.vx ~= CubeCodec.snapVel(want)
			or e.vy ~= CubeCodec.snapVel(-want)
			or e.vz ~= CubeCodec.snapVel(want * 0.5)
		then
			velOk = false
		end
	end
end
check(`velocity quantization max error {maxVelErr} <= 1/16`, maxVelErr <= 1 / 16 + 1e-9)
check("air bit + snapVel match decode for every sign", decodedVel ~= nil and velOk)
eq("snapPos matches decode", CubeCodec.snapPos(1.2345), math.round(1.2345 * 32) / 32)

-- 범위 밖 값은 클램프 (오류 없음). 위치 ±64, 속도 ±256 (12비트)
local _, decodedClamp = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(0, 0, 15, {
	{ id = 3, x = 1000, y = -1000, z = 0, vx = 5000, vy = -5000, vz = 0, air = true },
}))
if decodedClamp then
	local c = decodedClamp[1]
	near("position clamp max", c.x, 2047 / 32, 0)
	near("position clamp min", c.y, -64, 0)
	near("velocity clamp max", c.vx, 2047 / 8, 0)
	near("velocity clamp min", c.vy, -256, 0)
	check("clamped entry keeps air", c.air)
	eq("clamped z stays 0", c.z, 0)
else
	check("clamp snapshot decodes", false)
end

-- NaN은 0
local _, decodedNan = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(0, 0, 15, {
	{ id = 4, x = 0 / 0, y = 0, z = 0, vx = 0 / 0, vy = 1, vz = 0, air = true },
}))
eq("NaN position becomes 0", decodedNan and decodedNan[1].x, 0)
eq("NaN velocity becomes 0", decodedNan and decodedNan[1].vx, 0)

-- seq·tick 감싸기와 id 경계값 0 / 65535
local headW, entriesW = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(65536, 65536 + 7, 300, {
	{ id = 0, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, air = false },
	{ id = 65535, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, air = false },
}))
eq("seq 65536 wraps to 0", headW and headW.seq, 0)
eq("tick wraps mod 65536", headW and headW.tick, 7)
eq("hz clamps to u8", headW and headW.hz, 255)
eq("id 0 round-trip", entriesW and entriesW[1].id, 0)
eq("id 65535 round-trip", entriesW and entriesW[2].id, 65535)
local headMax = CubeCodec.decodeSnapshot(CubeCodec.encodeSnapshot(65535, 65535, 5, {}))
eq("seq 65535 round-trip", headMax and headMax.seq, 65535)
eq("tick 65535 round-trip", headMax and headMax.tick, 65535)

-- 종류별 최대 SNAP_MAX개 (넘는 것은 버림: CubeNet이 60개씩 나눠 보낸다)
local many: { CubeCodec.SnapEntry } = {}
for i = 1, 300 do
	many[i] = { id = i, x = 0, y = 0, z = 0, vx = 1, vy = 0, vz = 0, air = false }
end
eq("moving entries capped at SNAP_MAX", buffer.len(CubeCodec.encodeSnapshot(0, 0, 15, many)), 7 + 255 * 12)

-- 잘못된 길이는 nil, nil
local headBad, entriesBad = CubeCodec.decodeSnapshot(buffer.create(6))
eq("short snapshot header nil", headBad, nil)
eq("short snapshot entries nil", entriesBad, nil)
local bogus = buffer.create(7 + 12)
buffer.writeu16(bogus, 0, 1)
buffer.writeu8(bogus, 5, 1)
buffer.writeu8(bogus, 6, 1)
local headB2 = CubeCodec.decodeSnapshot(bogus)
eq("count mismatch header nil", headB2, nil)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
