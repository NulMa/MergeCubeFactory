--!strict
-- 데이터 큐브 복제 (docs/27 §1.3, 단계 4). 플롯마다 채널 하나 (SimBackend가 연다).
--   신뢰 CubeEvt (plotIndex, gen, buffer): spawn / remove / retier / reset. 한 프레임 동안 쌓은 op를 플롯별 한 패킷으로.
--   비신뢰 CubeSnap (plotIndex, gen, buffer): 데드 레코닝 보정만 (2026-10-22). 900바이트 한도라 60개씩 나눔.
--     등급(주인·근처)마다 큐브별로 "클라가 아는 상태"(마지막으로 보낸 양자화 값 + 틱)를 들고 shared/CubePredict로 같은 예측을 한다.
--     깨어 있는 큐브는 ① 처음 ② 예측 위치 오차 > POS_TOL ③ 속도 차 > VEL_TOL(부딪힘·깡충·배트) ④ KEEPALIVE초 지남 일 때만 넣는다.
--     정지 상태(잠듦·막 멈춤: 속도 0, 중력 없음)는 1 + FINAL_REPEAT번 연속, 그 뒤 REST_KEEPALIVE초마다 (잃어도 결국 맞음).
--     잃은 보정은 ②·④가 다시 잡는다 (비신뢰라도 스스로 낫는다).
--     시간 기준 = 시뮬 틱(source.tick): 헤더에 실어 보내고 클라가 받은 시각으로 자기 시계에 맞춘다 (client/CubeView).
--   관심 영역: 주인 15Hz, 플롯 중심 150스터드 안(나갈 땐 170) 5Hz, 그 밖은 스냅샷·op 없음.
--     범위에 들어오면(접속·리스폰·걸어 들어옴) reset(전체 목록)부터 보내고, 먼 플롯은 FAR_REFRESH초마다 reset만 (멈춘 그림이 너무 낡지 않게).
--   gen: 채널(플롯 주인)마다 새 번호. 주인이 바뀐 뒤 늦게 온 옛 스냅샷을 클라이언트가 버린다 (id는 새 주인 때 1부터 다시 쓰므로).
--   좌표는 플롯 중심(트레이 바닥 윗면 가운데) 기준 = TraySim 좌표.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Game
local CubeCodec = require(Shared.CubeCodec)
local CubePredict = require(Shared.CubePredict)
local Plots = require(script.Parent.Plots)

export type Source = {
	entries: () -> { CubeCodec.ResetEntry }, -- 지금 있는 큐브 전부 (reset)
	eachAwake: (fn: (number, number, number, number, number, number, number, boolean) -> ()) -> (),
	has: (id: number) -> boolean,
	position: (id: number) -> (number, number, number),
	tick: () -> number, -- 지금 상태의 시뮬 틱 (TraySim 고정 스텝 누적 수)
	gravity: number, -- 시뮬 중력 (= workspace.Gravity, 클라 예측과 같아야 함)
}

type Viewer = {
	class: number, -- 0 먼 곳(안 보냄), 1 근처, 2 주인
	needReset: boolean,
	resetAt: number,
}

export type Channel = {
	plot: Plots.Plot,
	index: number,
	gen: number,
	source: Source,
	ops: { any }, -- 이번 프레임 신뢰 op (CubeCodec.Op)
	last: { [number]: any }, -- id → 이번 프레임의 마지막 spawn/retier op (같은 프레임 겉모습 변경은 합친다)
	viewers: { [Player]: Viewer },
	seq: number,
	acc: { number }, -- 등급(1 근처, 2 주인)별 스냅샷 시계
	known: { { [number]: CubePredict.Known } }, -- 등급별 id → 그 등급 클라가 아는 상태 (마지막으로 보낸 값)
	open: boolean,
}

local CubeNet = {}

CubeNet.OWNER_HZ = 15
CubeNet.NEAR_HZ = 5
CubeNet.NEAR = 150 -- client/CubeLod FAR와 같음
CubeNet.NEAR_LEAVE = 170 -- 경계에서 들락날락하며 reset을 반복하지 않게
CubeNet.FAR_REFRESH = 15
CubeNet.INTEREST_TICK = 0.25
CubeNet.SNAP_CHUNK = 60 -- UnreliableRemoteEvent 900바이트 한도: 7 + 60 × 12 = 727B (CubeCodec 종류별 최대 255)
CubeNet.FINAL_REPEAT = 1 -- 정지 자리를 보낸 뒤 다음 스냅샷에 이만큼 더 (예전처럼 연속 2번: 하나 잃어도 제자리에 멈추게)
CubeNet.REST_KEEPALIVE = 8 -- 정지로 아는 큐브도 이 초마다 한 번 (연속 2번을 다 잃은 드문 경우도 결국 맞춘다. 55개면 ≈ 7개/초)
-- 데드 레코닝 기준 (등급 1 근처, 2 주인). 주인은 0.25스터드면 큐브 크기(2.2~5.6)에 비해 눈에 안 띄고 보정은 클라가 100ms에 걸쳐 섞는다
CubeNet.POS_TOL = { 0.6, 0.25 }
CubeNet.VEL_TOL = { 12, 6 } -- 예측 속도와 이만큼 다르면 바로 보냄 (접촉·깡충·배트). 중력 한 틱 = 6.5
CubeNet.KEEPALIVE = 1 -- 깨어 있는 큐브는 맞게 예측돼도 이 초마다 한 번 (잃은 보정·스폰 순서 꼬임 회복)
CubeNet.REST_TOL = 0.05 -- 잠든 큐브가 아는 자리와 이만큼 다르면 마지막 자리를 다시 (살짝 밀려 잠든 것도 딱 맞게)

local net: any = nil
local channels: { [number]: Channel } = {}
local genCounter = 0
local interestAcc = 0

local function rootPos(p: Player): Vector3?
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

function CubeNet.init(netServer: any)
	net = netServer
	Players.PlayerRemoving:Connect(function(p)
		for _, ch in channels do
			ch.viewers[p] = nil
		end
	end)
end

-- 플롯 주인이 정해지면(Factory.start → SimBackend.new) 연다. 모든 사람이 다음 관심 틱에 reset을 받는다
function CubeNet.open(plot: Plots.Plot, source: Source): Channel
	local old = channels[plot.index]
	if old then
		CubeNet.close(old)
	end
	genCounter = genCounter % 65535 + 1
	local ch: Channel = {
		plot = plot,
		index = plot.index,
		gen = genCounter,
		source = source,
		ops = {},
		last = {},
		viewers = {},
		seq = 0,
		acc = { 0, 0 },
		known = { {}, {} },
		open = true,
	}
	channels[plot.index] = ch
	return ch
end

-- 주인이 나가 플롯을 비움: 모두에게 빈 목록 (먼 사람도 멈춘 그림을 갖고 있으므로)
function CubeNet.close(ch: Channel)
	if not ch.open then
		return
	end
	ch.open = false
	if channels[ch.index] == ch then
		channels[ch.index] = nil
	end
	if net then
		net.fireAll("CubeEvt", ch.index, ch.gen, CubeCodec.encodeEvents({ { kind = "reset", entries = {} } :: any }))
	end
end

function CubeNet.spawn(
	ch: Channel,
	id: number,
	tier: number,
	variant: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	atMax: boolean
)
	local op =
		{ kind = "spawn", id = id, tier = tier, variant = variant, x = x, y = y, z = z, vx = vx, vy = vy, vz = vz }
	table.insert(ch.ops, op)
	ch.last[id] = op
	-- 다음 스냅샷에 꼭 넣는다: spawn op는 틱이 없어 클라가 받은 시각으로 놓으므로 틱 실린 상태로 바로 맞춘다
	-- (텔레포트 = remove + spawn 같은 id도 여기서 옛 상태를 버린다)
	for _, known in ch.known do
		known[id] = nil
	end
	if atMax then
		CubeNet.retier(ch, id, tier, variant, true)
	end
end

function CubeNet.remove(ch: Channel, id: number, reason: number)
	table.insert(ch.ops, { kind = "remove", id = id, reason = reason })
	ch.last[id] = nil
	for _, known in ch.known do
		known[id] = nil
	end
end

-- 같은 프레임에 이미 보낼 spawn/retier가 있으면 그것을 고친다 (합치기: 크기·색 + MAX 표시 → op 하나)
function CubeNet.retier(ch: Channel, id: number, tier: number, variant: number, atMax: boolean)
	local prev = ch.last[id]
	if prev and prev.kind == "retier" then
		prev.tier, prev.variant, prev.atMax = tier, variant, atMax
		return
	end
	if prev and prev.kind == "spawn" then
		prev.tier, prev.variant = tier, variant
		if not atMax then
			return -- spawn은 MAX 아님으로 시작
		end
	end
	local op = { kind = "retier", id = id, tier = tier, variant = variant, atMax = atMax }
	table.insert(ch.ops, op)
	ch.last[id] = op
end

local function updateInterest(ch: Channel, now: number)
	local center = ch.plot.center
	for _, p in Players:GetPlayers() do
		local v = ch.viewers[p]
		if not v then
			-- 처음 보는 사람(접속·새 채널): 거리와 상관없이 전체 목록 한 번
			v = { class = 0, needReset = true, resetAt = now }
			ch.viewers[p] = v
		end
		local class = 0
		if p == ch.plot.owner then
			class = 2
		else
			local pos = rootPos(p)
			if pos then
				local d = (pos - center).Magnitude
				if d <= CubeNet.NEAR or (v.class == 1 and d <= CubeNet.NEAR_LEAVE) then
					class = 1
				end
			end
		end
		-- 범위에 들어옴: 그동안 놓친 op 대신 전체 목록. 먼 곳이면 가끔 전체 목록만
		if (class > 0 and v.class == 0) or (class == 0 and now - v.resetAt >= CubeNet.FAR_REFRESH) then
			v.needReset = true
		end
		v.class = class
	end
end

local function sendReliable(ch: Channel, now: number)
	local opsBuf = if #ch.ops > 0 then CubeCodec.encodeEvents(ch.ops) else nil
	local resetBuf: buffer? = nil
	for p, v in ch.viewers do
		if v.needReset then
			-- reset은 지금 상태 = 이번 프레임 op가 이미 반영됨 → op는 보내지 않는다
			if not resetBuf then
				resetBuf = CubeCodec.encodeEvents({ { kind = "reset", entries = ch.source.entries() } :: any })
			end
			net.fire("CubeEvt", p, ch.index, ch.gen, resetBuf)
			v.needReset = false
			v.resetAt = now
			if v.class > 0 then
				-- reset은 위치만(속도 0, 정지) → 이 등급이 아는 상태를 비워 깨어 있는 큐브를 다음 스냅샷에 모두 다시 보낸다
				table.clear(ch.known[v.class])
			end
		elseif v.class > 0 and opsBuf then
			net.fire("CubeEvt", p, ch.index, ch.gen, opsBuf)
		end
	end
	table.clear(ch.ops)
	table.clear(ch.last)
end

local QUANT: CubePredict.Quant = { pos = CubeCodec.snapPos, vel = CubeCodec.snapVel }

-- 이 등급 스냅샷 항목: 예측과 어긋난 것·keepalive·막 잠든 것 (shared/CubePredict.collect, Lune 테스트와 같은 코드)
local function build(ch: Channel, class: number, tick: number): { CubePredict.Entry }
	return CubePredict.collect(ch.known[class], tick, {
		gravity = ch.source.gravity,
		posTol = CubeNet.POS_TOL[class],
		velTol = CubeNet.VEL_TOL[class],
		restTol = CubeNet.REST_TOL,
		keepTicks = math.round(CubeNet.KEEPALIVE / CubePredict.DT),
		finalRepeat = CubeNet.FINAL_REPEAT,
		restKeepTicks = math.round(CubeNet.REST_KEEPALIVE / CubePredict.DT),
	}, ch.source, QUANT)
end

local function sendSnapshots(ch: Channel, dt: number)
	for class = 1, 2 do
		local hz = if class == 2 then CubeNet.OWNER_HZ else CubeNet.NEAR_HZ
		local period = 1 / hz
		ch.acc[class] += dt
		if ch.acc[class] < period then
			continue
		end
		ch.acc[class] = math.min(ch.acc[class] - period, period) -- 밀린 만큼 몰아 보내지 않음
		local any = false
		for _, v in ch.viewers do
			if v.class == class then
				any = true
				break
			end
		end
		if not any then
			table.clear(ch.known[class]) -- 새로 들어오는 사람은 reset으로 시작
			continue
		end
		local tick = ch.source.tick()
		local entries = build(ch, class, tick)
		if #entries == 0 then
			continue
		end
		ch.seq = (ch.seq + 1) % 65536
		for i = 1, #entries, CubeNet.SNAP_CHUNK do
			local chunk = table.move(entries, i, math.min(i + CubeNet.SNAP_CHUNK - 1, #entries), 1, {})
			local buf = CubeCodec.encodeSnapshot(ch.seq, tick, hz, chunk)
			for p, v in ch.viewers do
				if v.class == class then
					net.fire("CubeSnap", p, ch.index, ch.gen, buf)
				end
			end
		end
	end
end

-- 매 Heartbeat (SimBackend가 시뮬을 돌린 뒤): 관심 영역 갱신 → 신뢰 op → 스냅샷
function CubeNet.flush(dt: number)
	if not net then
		return
	end
	interestAcc += dt
	local doInterest = interestAcc >= CubeNet.INTEREST_TICK
	if doInterest then
		interestAcc = 0
	end
	local now = os.clock()
	for _, ch in channels do
		if doInterest then
			updateInterest(ch, now)
		end
		sendReliable(ch, now)
		sendSnapshots(ch, dt)
	end
end

return CubeNet
