--!strict
-- AI 플레이어 (2026-10-24 사용자: "플레이어 수가 미달이라면 ai 플레이어도 조금 넣어볼까,
-- 공장 성장보다는(안하는건 아님) 훔치기나 지키기를 간헐적으로 시도하거나 맵을 돌아다니는 방향으로")
--   * 사람 + 봇이 Config.BOTS.FILL_TO 명이 될 때까지 빈 플롯에 봇을 세운다 (사람 0명이면 없음, 최대 MAX)
--   * 사람이 들어왔는데 빈 플롯이 없으면 봇 하나가 바로 비켜 준다 (Plots.claim → evict)
--   * 이름 [BOT] ·표지판 (Bot): 사람인 척하지 않는다. Players에 없으니 접속자 수·랭킹·추천 지표에도 안 들어간다
--   * 하는 일: 광장·남의 공장 구경, 자기 트레이에서 배트질, 가끔 훔치기(사람과 같은 규칙: server/Steal),
--     자기 트레이를 털리면 도둑을 쫓아가 배트로 친다
--   * 공장은 간이: 드로퍼 2개 + 멈춘 같은 등급 2개를 합침. 사람이 털어 갈 수 있다 (털 거리 제공)
-- 저장 없음. 봇 공장 상태 st는 Factory State와 같은 이름의 필드(player·data·plot·cubes)만 가진다 → Steal이 그대로 쓴다

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local AssetIds = require(Shared.AssetIds)
local CubeCodec = require(Shared.CubeCodec)
local Plots = require(script.Parent.Plots)
local CubeWorld = require(script.Parent.CubeWorld)
local SimBackend = require(script.Parent.SimBackend)
local Steal = require(script.Parent.Steal)
local Factory = require(script.Parent.Factory)

local B = Config.BOTS

local Bots = {}

type BotState = {
	player: Model, -- Steal이 "주인"으로 쓰는 키
	data: { [string]: any },
	plot: Plots.Plot,
	cubes: CubeWorld.World,
	baseTier: number, -- 드롭 등급
	topTier: number, -- 합치기 상한 (사람 평균 아래)
	dropAt: number,
}

type Bot = {
	name: string,
	model: Model,
	hum: Humanoid,
	root: BasePart,
	st: BotState,
	alive: boolean,
	chase: Player?, -- 쫓는 도둑
	stunUntil: number,
	nextSteal: number,
	lastSwing: number,
	swingTrack: AnimationTrack?,
	forceVictim: any?, -- Studio 디버그: 다음 행동으로 이 사람을 턴다
	lowSince: number?, -- 물에 빠진 것 같은 높이에 처음 있던 시각
}

local NAMES = { "Bolt", "Pixel", "Nova", "Mochi", "Rusty", "Bloop", "Ziggy", "Tofu", "Sprocket", "Pebble" }
-- Roblox 기본 R15 애니메이션 (서버가 NPC Animator로 재생)
local ANIM: { [string]: string } = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	fall = "rbxassetid://507767968",
}
local SKIN = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 110, 80),
	Color3.fromRGB(110, 75, 55),
}
local SHIRT = {
	Color3.fromRGB(230, 80, 80),
	Color3.fromRGB(80, 150, 240),
	Color3.fromRGB(90, 200, 120),
	Color3.fromRGB(250, 190, 60),
	Color3.fromRGB(170, 100, 230),
	Color3.fromRGB(60, 200, 200),
}

local bots: { Bot } = {}
local forced: number? = nil -- Studio 디버그: 봇 수 고정
local lastVictim: { [Player]: number } = {}
local rng = Random.new()

local function flat(v: Vector3): Vector3
	return v * Vector3.new(1, 0, 1)
end

local function botOfModel(model: Model): Bot?
	for _, b in bots do
		if b.model == model then
			return b
		end
	end
	return nil
end

local function realPlayers(): { Player }
	return Players:GetPlayers()
end

-- 사람들의 평균 진행도 → 봇 수준 (Config.BOTS TOP_*/DROP_BELOW)
-- 2026-10-25: 중간값 -7 드롭 + 리버스 상한까지 합치기라 봇 큐브가 사람보다 높아졌다 (봇만 털면 그만, 봇은 털 등급이 안 나옴)
-- 반환: 최고 등급(합치기 상한), 드롭 등급, 리버스
local function reference(): (number, number, number)
	local n, sumBest, sumDrop, sumReb = 0, 0, 0, 0
	for _, st in Steal.playerStates() do
		n += 1
		sumBest += st.data.stats.best
		local hi = 1
		for _, d in st.data.droppers or {} do
			hi = math.max(hi, d.tier)
		end
		sumDrop += hi
		sumReb += st.data.rebirths
	end
	if n == 0 then
		return 8, 1, 1
	end
	local reb = math.max(1, math.floor(sumReb / n + 0.5))
	local top = math.clamp(math.floor(sumBest / n) - B.TOP_BELOW, 3, math.min(B.TOP_MAX, Economy.tierCeiling(reb)))
	local drop = math.clamp(math.floor(sumDrop / n) - B.DROP_BELOW, 1, math.max(1, top - 3))
	return top, drop, reb
end

------------------------------------------------------------------------
-- 몸
------------------------------------------------------------------------

local function makeRig(name: string): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = SHIRT[rng:NextInteger(1, #SHIRT)]
	local pants = Color3.fromHSV(rng:NextNumber(), 0.35, rng:NextNumber(0.25, 0.55))
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = "Bot_" .. name
	model:SetAttribute("BotName", name)
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- LocalScript라 NPC에선 안 돈다. 서버가 직접 재생
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = "[BOT] " .. name
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	-- 머리 위 이름표: 봇이라는 걸 늘 보이게 (기본 이름표는 이 게임에서 잘 안 보인다)
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "BotTag"
		bb.Size = UDim2.fromOffset(140, 30)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.MaxDistance = 90
		bb.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(190, 230, 255)
		label.TextStrokeTransparency = 0.3
		label.Text = `[BOT] {name}`
		label.Parent = bb
		bb.Parent = head
	end
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = 16
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players" -- 큐브와 안 부딪힘 (사람 캐릭터와 같게)
		end
	end
	return model
end

local function startAnims(b: Bot)
	local animator = b.hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = b.hum
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in ANIM do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, t = pcall(function()
			return (animator :: Animator):LoadAnimation(a)
		end)
		if ok and t then
			t.Looped = true
			tracks[key] = t
		end
	end
	local swing = Instance.new("Animation")
	swing.AnimationId = (AssetIds :: any).Anims.BatSwing
	local ok, t = pcall(function()
		return (animator :: Animator):LoadAnimation(swing)
	end)
	if ok and t then
		t.Priority = Enum.AnimationPriority.Action
		b.swingTrack = t
	end
	local current = ""
	task.spawn(function()
		while b.alive and b.model.Parent do
			local state = b.hum:GetState()
			local speed = flat(b.root.AssemblyLinearVelocity).Magnitude
			local want = if state == Enum.HumanoidStateType.Freefall
					or state == Enum.HumanoidStateType.Jumping
				then "fall"
				elseif speed > 1.5 then "walk"
				else "idle"
			if want ~= current then
				local old = tracks[current]
				if old then
					old:Stop(0.2)
				end
				local new = tracks[want]
				if new then
					new:Play(0.2)
				end
				current = want
			end
			local walk = tracks.walk
			if walk and current == "walk" then
				walk:AdjustSpeed(math.clamp(speed / 14, 0.5, 1.5))
			end
			task.wait(0.1)
		end
	end)
end

------------------------------------------------------------------------
-- 움직임
------------------------------------------------------------------------

local function interrupted(b: Bot, allowChase: boolean): boolean
	return not b.alive or (b.chase ~= nil and not allowChase) or b.forceVictim ~= nil
end

-- 지금 하는 일 (Studio에서 속성으로 확인)
local function doing(b: Bot, what: string)
	b.model:SetAttribute("Doing", what)
end

-- 쉬기: 털리거나(chase) 디버그 지시가 오면 바로 끝낸다
local function pause(b: Bot, seconds: number)
	local t0 = os.clock()
	while b.alive and os.clock() - t0 < seconds and not b.chase and not b.forceVictim do
		task.wait(0.2)
	end
end

-- 기절(배트에 맞음) 중이면 끝날 때까지
local function waitStun(b: Bot)
	while b.alive and os.clock() < b.stunUntil do
		task.wait(0.1)
	end
end

-- 앞이 막혔으면 점프 (2026-10-25 사용자 "언덕은 알아서 점프"): 무릎 높이 앞쪽에 가파른 면이 있거나,
-- 걷는 중인데 0.4초 넘게 거의 못 나아가면. 길찾기 Jump 지점만으로는 언덕 턱·바위에 걸려 멈췄다
local jumpParams = RaycastParams.new()
jumpParams.FilterType = Enum.RaycastFilterType.Exclude
local function autoJump(b: Bot, slowSince: number?)
	local hum = b.hum
	if hum.FloorMaterial == Enum.Material.Air then
		return
	end
	local dir = flat(hum.MoveDirection)
	if dir.Magnitude < 0.1 then
		return
	end
	jumpParams.FilterDescendantsInstances = { b.model }
	local knee = b.root.Position - Vector3.new(0, hum.HipHeight * 0.6, 0)
	local hit = workspace:Raycast(knee, dir.Unit * 3.2, jumpParams)
	local wall = hit ~= nil and hit.Normal.Y < 0.75 and (hit.Instance :: BasePart).CanCollide
	if wall or (slowSince and os.clock() - slowSince > 0.4) then
		hum.Jump = true
	end
end

-- 목적지까지 걷기 (길찾기). 도착하면 true
-- 2026-10-25 "다음 움직임도 너무 끊기지 않게": 지점에 닿기 전에(4.5) 다음 지점으로 넘어가 멈칫하지 않게, 0.1초마다 갱신
local function walkTo(b: Bot, goal: Vector3, timeout: number, allowChase: boolean?): boolean
	local deadline = os.clock() + timeout
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		-- 플롯 사이 모래섬을 징검다리로 건너지 않게 (광장·다리로 돌아간다)
		Costs = { Sand = 40, Water = math.huge },
	})
	local ok = pcall(function()
		path:ComputeAsync(b.root.Position, goal)
	end)
	local points: { PathWaypoint } = {}
	if ok and path.Status == Enum.PathStatus.Success then
		points = path:GetWaypoints()
	end
	local route: { Vector3 } = {}
	local jumps: { boolean } = {}
	for _, wp in points do
		table.insert(route, wp.Position)
		table.insert(jumps, wp.Action == Enum.PathWaypointAction.Jump)
	end
	if #route == 0 then
		-- 길이 없으면 직선으로 가지 않는다 (다리 밖 바다로 걸어 들어감, Studio 2026-10-24). 광장 가운데로 물러난다
		if flat(b.root.Position).Magnitude > 20 and flat(goal).Magnitude > 1 then
			b.hum:MoveTo(Vector3.new(0, 2, 0))
			task.wait(1)
		end
		return false
	end
	local slowSince: number? = nil
	for i, p in route do
		local legEnd = math.min(deadline, os.clock() + 4)
		local reach = if i == #route then 2.5 else 4.5
		while true do
			if interrupted(b, allowChase == true) then
				return false
			end
			waitStun(b)
			b.hum:MoveTo(p)
			if jumps[i] then
				b.hum.Jump = true
			end
			local speed = flat(b.root.AssemblyLinearVelocity).Magnitude
			if speed < b.hum.WalkSpeed * 0.3 then
				slowSince = slowSince or os.clock()
			else
				slowSince = nil
			end
			autoJump(b, slowSince)
			if flat(b.root.Position - p).Magnitude < reach then
				break
			end
			if os.clock() > legEnd then
				break -- 막혔으면 다음 점으로
			end
			task.wait(0.1)
		end
		if os.clock() > deadline then
			break
		end
	end
	return flat(b.root.Position - goal).Magnitude < 5
end

-- 점프 패드처럼 포물선 비행 (client/JumpPads.plan과 같은 식, NPC는 서버가 물리 주인)
local function fly(b: Bot, to: Vector3, wallTop: number)
	local g = workspace.Gravity
	local p0 = b.root.Position
	local apexY = wallTop + 10
	local up = math.max(1, apexY - p0.Y)
	local down = math.max(1, apexY - to.Y)
	local vy = math.sqrt(2 * g * up)
	local total = vy / g + math.sqrt(2 * down / g)
	local h = math.clamp(wallTop + 4.5 - p0.Y, 0, up - 0.5)
	local tClear = (vy - math.sqrt(math.max(0, vy * vy - 2 * g * h))) / g
	local horiz = flat(to - p0) / math.max(0.2, total - tClear)
	b.hum:ChangeState(Enum.HumanoidStateType.Freefall)
	local t0 = os.clock()
	while b.alive and os.clock() - t0 < total - 0.05 do
		local t = os.clock() - t0
		local v = if t >= tClear then horiz else Vector3.zero
		b.root.AssemblyLinearVelocity = Vector3.new(v.X, vy - g * t, v.Z)
		RunService.Heartbeat:Wait()
	end
	task.wait(0.3)
end

local function padIn(plot: Plots.Plot): BasePart?
	return plot.model:FindFirstChild("JumpPadIn") :: BasePart?
end

local function wallTop(plot: Plots.Plot): number
	return plot.floor.Position.Y + Config.TRAY_SIZE.Y
end

-- 트레이 밖에서 패드로 트레이 안에 들어가기
local function enterTray(b: Bot, plot: Plots.Plot): boolean
	local pad = padIn(plot)
	if not pad then
		return false
	end
	if not walkTo(b, pad.Position, 45) then
		doing(b, "enterTray: no path")
		return false
	end
	b.hum:MoveTo(pad.Position)
	task.wait(0.3)
	local w = plot.floor.Size.X
	fly(b, plot.floor.Position + Vector3.new(-w * 0.2, 3.5, w * 0.2), wallTop(plot))
	return b.alive
end

-- 트레이 안 구석 패드로 나가기 (시점 비컨 쪽으로 떨어짐)
local function leaveTray(b: Bot, plot: Plots.Plot)
	local pad = plot.padOut
	local deadline = os.clock() + 8
	while b.alive and os.clock() < deadline and flat(b.root.Position - pad.Position).Magnitude > 2 do
		waitStun(b)
		b.hum:MoveTo(pad.Position)
		task.wait(0.15)
	end
	local view = plot.model:FindFirstChild("ViewPad") :: BasePart?
	local to = if view then view.Position + Vector3.new(0, 3, 0) else plot.center + Vector3.new(0, 4, 40)
	fly(b, to, wallTop(plot))
end

local function inTray(plot: Plots.Plot, pos: Vector3): boolean
	local off = pos - plot.center
	local half = plot.width / 2 + 1
	return math.abs(off.X) <= half and math.abs(off.Z) <= half and off.Y > -6 and off.Y < 20
end

------------------------------------------------------------------------
-- 배트
------------------------------------------------------------------------

local function look(b: Bot): Vector3
	local l = flat(b.root.CFrame.LookVector)
	return if l.Magnitude > 0.01 then l.Unit else Vector3.zAxis
end

local function face(b: Bot, at: Vector3, seconds: number?)
	local d = flat(at - b.root.Position)
	if d.Magnitude <= 0.5 then
		return
	end
	local dur = seconds or 0
	if dur <= 0 then
		b.root.CFrame = CFrame.lookAt(b.root.Position, b.root.Position + d)
		return
	end
	-- 천천히 돌아보기 (뚝 돌면 어색하다)
	local from = look(b)
	local t0 = os.clock()
	while b.alive and os.clock() - t0 < dur do
		local k = (os.clock() - t0) / dur
		local dir = from:Lerp(d.Unit, k * k * (3 - 2 * k))
		if dir.Magnitude > 0.01 then
			b.root.CFrame = CFrame.lookAt(b.root.Position, b.root.Position + dir)
		end
		task.wait(0.03)
	end
end

-- 휘두르기: only = 칠 사람 (지키기), 없으면 자기 트레이 큐브만 민다
local function swing(b: Bot, only: Player?)
	local now = os.clock()
	if now - b.lastSwing < 0.9 then
		return
	end
	b.lastSwing = now
	if b.swingTrack then
		b.swingTrack:Play(0.05)
	end
	task.wait(0.22) -- 임팩트 순간
	if not b.alive then
		return
	end
	Factory.flashTrail(b.model)
	local range, power = Economy.batRange(2), Economy.batPower(1)
	local dir = look(b)
	if only then
		Steal.batHit(b.model, b.root, range, power, dir, only)
		return
	end
	local cubes = b.st.cubes
	for _, cube in cubes:ids() do
		local off = cubes:position(cube) - b.root.Position
		if off.Magnitude > range + cubes:size(cube) / 2 then
			continue
		end
		local f = flat(off)
		local d = if f.Magnitude > 0.1 then f.Unit else dir
		if d:Dot(dir) < 0.1 and off.Magnitude > 4 then
			continue
		end
		cubes:setVelocity(cube, (d + dir).Unit * power + Vector3.new(0, power * 0.45, 0))
	end
end

------------------------------------------------------------------------
-- 공장 (간이)
------------------------------------------------------------------------

local function ceilingOf(st: BotState): number
	return Economy.tierCeiling(st.data.rebirths)
end

local function spawnCube(st: BotState, tier: number, at: Vector3, variant: number?): number
	st.data.stats.drops += 1
	return st.cubes:spawn(tier, at, variant)
end

local function factoryStep(st: BotState, now: number)
	local cubes = st.cubes
	local cap = math.min(ceilingOf(st), st.topTier)
	-- 드로퍼
	if now >= st.dropAt and cubes:count() < B.TRAY_MAX then
		st.dropAt = now + B.DROP_EVERY
		local d = st.plot.dropperParts[rng:NextInteger(1, 2)]
		if d then
			spawnCube(st, st.baseTier, d.Position - Vector3.new(0, 3, 0))
		end
	end
	-- 합치기: 사람 트레이와 같은 접촉 합치기 + 자석 깡충 (Factory.botMerge)
	local _, top = Factory.botMerge(cubes, cap, st.player)
	st.data.stats.best = math.max(st.data.stats.best, top)
	-- 상한이 내려갔으면(사람 평균이 낮은 사람이 들어옴) 넘는 큐브는 판다
	for _, id in cubes:ids() do
		if cubes:tier(id) > cap and not cubes:revealUntil(id) then
			cubes:remove(id, CubeCodec.REASON_SELL)
			break
		end
	end
	-- 넘치면 가장 낮은 것부터 뺀다
	if cubes:count() > B.TRAY_MAX then
		local low, lowT = nil, math.huge
		for _, id in cubes:ids() do
			local t = cubes:tier(id)
			if t < lowT then
				low, lowT = id, t
			end
		end
		if low then
			cubes:remove(low, CubeCodec.REASON_SELL)
		end
	end
end

------------------------------------------------------------------------
-- 행동
------------------------------------------------------------------------

local function homeFront(b: Bot): Vector3
	return Plots.spawnCFrame(b.st.plot).Position
end

local function pickVictim(b: Bot): any?
	local now = os.clock()
	local cap = ceilingOf(b.st)
	local list = {}
	for player, st in Steal.playerStates() do
		if Steal.inRaid(player) or Steal.isLocked(player) or now - (lastVictim[player] or -1e9) < B.VICTIM_COOLDOWN then
			continue
		end
		if not B.STEAL_NEWBIES and st.data.rebirths == 0 then
			continue
		end
		local char = player.Character
		if not (char and char:FindFirstChild("HumanoidRootPart")) then
			continue
		end
		-- 털 만한 큐브가 있나 (상위 2등급 보호·내 상한 아래)
		local tiers = {}
		for _, id in st.cubes:ids() do
			table.insert(tiers, st.cubes:tier(id))
		end
		local top = Economy.stealProtectedFrom(tiers)
		for _, t in tiers do
			if t < top and t <= cap then
				table.insert(list, st)
				break
			end
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function anyCarrying(): boolean
	for _, o in bots do
		if Steal.isCarrying(o.model) then
			return true
		end
	end
	return false
end

-- 훔치기: 남의 트레이에 패드로 들어가 → 큐브 하나 → 나가서 집으로 (Steal이 집에 들어서면 확정)
local function doSteal(b: Bot, victim: any): boolean
	local player = victim.player :: Player
	lastVictim[player] = os.clock()
	if not enterTray(b, victim.plot) or interrupted(b, false) then
		return false
	end
	local list = Steal.botCandidates(b.model)
	doing(b, `steal: {#list} candidates`)
	if #list == 0 then
		leaveTray(b, victim.plot)
		return false
	end
	-- 가장 높은 것 말고 무작위 (사람이 잃는 양을 줄이고 덜 뻔하게)
	local pick = list[rng:NextInteger(1, #list)]
	local cubes = victim.cubes
	if cubes:alive(pick.cube) then
		local deadline = os.clock() + 4
		while b.alive and os.clock() < deadline and cubes:alive(pick.cube) do
			local p = cubes:position(pick.cube)
			if (p - b.root.Position).Magnitude < 8 then
				break
			end
			b.hum:MoveTo(p)
			task.wait(0.15)
		end
	end
	-- 걸어가는 사이 합쳐져 없어졌을 수 있다 → 지금 목록에서 다시 (가까운 순)
	local ok = cubes:alive(pick.cube) and Steal.botSteal(b.model, pick.cube)
	if not ok then
		for _, e in Steal.botCandidates(b.model) do
			if Steal.botSteal(b.model, e.cube) then
				ok = true
				break
			end
		end
	end
	if not ok then
		doing(b, "steal: missed")
		leaveTray(b, victim.plot)
		return false
	end
	Steal.applySpeed(b.model)
	leaveTray(b, victim.plot)
	-- 집까지. 맞아서 떨어뜨리면(isCarrying false) 그만
	local deadline = os.clock() + Economy.CARRY_TIMEOUT
	while b.alive and Steal.isCarrying(b.model) and os.clock() < deadline do
		walkTo(b, b.st.plot.center + Vector3.new(0, 3, Config.PLATFORM_SIZE.Z * 0.3), 20)
		if inTray(b.st.plot, b.root.Position) then
			break
		end
		task.wait(0.5)
	end
	Steal.applySpeed(b.model)
	return true
end

-- 지키기: 내 트레이를 턴 사람을 쫓아가 친다 (그 사람만)
local function doChase(b: Bot)
	local thief = b.chase
	b.chase = nil
	if not thief then
		return
	end
	task.wait(B.DEFEND_DELAY)
	local plot = b.st.plot
	local deadline = os.clock() + 45
	while b.alive and os.clock() < deadline and thief.Parent and Steal.isCarrying(thief) do
		local char = thief.Character
		local troot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not troot then
			break
		end
		waitStun(b)
		local d = (troot.Position - b.root.Position).Magnitude
		local thiefIn = inTray(plot, troot.Position)
		local meIn = inTray(plot, b.root.Position)
		if d < Economy.batRange(2) then
			face(b, troot.Position)
			swing(b, thief)
		elseif thiefIn and not meIn then
			enterTray(b, plot) -- 도둑이 아직 내 트레이 안
		elseif meIn and not thiefIn then
			leaveTray(b, plot)
		elseif d < 30 then
			b.hum:MoveTo(troot.Position)
		else
			walkTo(b, troot.Position, 2.5, true)
		end
		task.wait(0.15)
	end
end

-- 걷는 속도: 산책은 조금씩 다르게, 일(훔치기·지키기)은 기본 16 (Steal.applySpeed가 운반 중 속도를 따로 정한다)
local function stroll(b: Bot)
	if not Steal.isCarrying(b.model) then
		b.hum.WalkSpeed = rng:NextNumber(11, 15)
	end
end
local function hurry(b: Bot)
	if not Steal.isCarrying(b.model) then
		b.hum.WalkSpeed = 16
	end
end

-- 가만히 서 있지 않고 서성이기 (2026-10-25 사용자 "움직임이 너무 단조로움"):
-- 둘러보기·몇 걸음 옮기기·가끔 점프. 배트는 휘두르지 않는다(광장에서 사람을 칠 수 있음). 털리면 바로 끝
local function loiter(b: Bot, seconds: number)
	local t0 = os.clock()
	while b.alive and os.clock() - t0 < seconds and not b.chase and not b.forceVictim do
		local r = rng:NextNumber()
		if r < 0.4 then
			local a = rng:NextNumber(0, math.pi * 2)
			face(b, b.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 5, rng:NextNumber(0.3, 0.6))
			pause(b, rng:NextNumber(0.4, 1.2))
		elseif r < 0.75 then
			local a = rng:NextNumber(0, math.pi * 2)
			local to = b.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(3, 7)
			b.hum.WalkSpeed = rng:NextNumber(7, 10)
			b.hum:MoveTo(to)
			local s0 = os.clock()
			while b.alive and os.clock() - s0 < 1.5 and flat(to - b.root.Position).Magnitude > 1.5 do
				autoJump(b, nil)
				task.wait(0.1)
			end
			stroll(b)
		elseif r < 0.88 then
			b.hum.Jump = true
			pause(b, rng:NextNumber(0.6, 1))
		else
			pause(b, rng:NextNumber(0.8, 1.6))
		end
	end
end

local function idlePlaza(b: Bot)
	stroll(b)
	-- 광장 안 두세 곳을 이어서 돈다 (한 곳 가서 오래 서 있던 것)
	for _ = 1, rng:NextInteger(1, 3) do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(14, 38)
		if not walkTo(b, Vector3.new(math.cos(a) * r, 2, math.sin(a) * r), 30) and interrupted(b, false) then
			return
		end
		loiter(b, rng:NextNumber(0.5, 2))
	end
	loiter(b, rng:NextNumber(1.5, 4))
end

local function idleVisit(b: Bot)
	local others = {}
	for _, plot in Plots.all() do
		if plot ~= b.st.plot and (plot.owner or plot.bot) then
			table.insert(others, plot)
		end
	end
	if #others == 0 then
		idlePlaza(b)
		return
	end
	local plot = others[rng:NextInteger(1, #others)]
	stroll(b)
	walkTo(b, Plots.spawnCFrame(plot).Position + Vector3.new(rng:NextNumber(-8, 8), 0, 0), 40)
	face(b, plot.center, 0.5)
	loiter(b, rng:NextNumber(2, 5))
end

local function idleHome(b: Bot)
	local plot = b.st.plot
	if not enterTray(b, plot) then
		return
	end
	for _ = 1, rng:NextInteger(3, 6) do
		if interrupted(b, false) then
			return
		end
		local ids = b.st.cubes:ids()
		if #ids > 0 then
			local target = b.st.cubes:position(ids[rng:NextInteger(1, #ids)])
			local t0 = os.clock()
			while b.alive and os.clock() - t0 < 2.5 and flat(target - b.root.Position).Magnitude > 6 do
				b.hum:MoveTo(target)
				task.wait(0.15)
			end
			face(b, target)
			swing(b, nil)
		end
		pause(b, rng:NextNumber(0.6, 1.4))
	end
	if not b.chase then
		leaveTray(b, plot)
	end
end

-- 지금 서 있는 트레이 (트레이 안에선 길찾기가 안 된다: 벽)
local function trayAt(pos: Vector3): Plots.Plot?
	for _, plot in Plots.all() do
		if inTray(plot, pos) then
			return plot
		end
	end
	return nil
end

local function brain(b: Bot)
	while b.alive do
		local stuckIn = trayAt(b.root.Position)
		if stuckIn and not b.chase then
			doing(b, "leave tray")
			leaveTray(b, stuckIn)
		end
		if b.forceVictim then
			local v = b.forceVictim
			b.forceVictim = nil
			doing(b, "steal")
			hurry(b)
			doSteal(b, v)
		elseif b.chase then
			doing(b, "chase")
			hurry(b)
			doChase(b)
		elseif os.clock() >= b.nextSteal and not anyCarrying() then
			b.nextSteal = os.clock() + rng:NextNumber(B.STEAL_EVERY[1], B.STEAL_EVERY[2])
			local victim = pickVictim(b)
			if victim then
				doing(b, "steal")
				hurry(b)
				doSteal(b, victim)
			end
		else
			local r = rng:NextNumber()
			if r < 0.35 then
				doing(b, "plaza")
				idlePlaza(b)
			elseif r < 0.65 then
				doing(b, "visit")
				idleVisit(b)
			elseif r < 0.85 then
				doing(b, "home")
				idleHome(b)
			else
				doing(b, "front")
				stroll(b)
				walkTo(b, homeFront(b), 30)
				loiter(b, rng:NextNumber(1.5, 4))
			end
		end
		task.wait(0.05)
	end
end

------------------------------------------------------------------------
-- 생성·제거
------------------------------------------------------------------------

local function freeName(): string
	local used: { [string]: boolean } = {}
	for _, b in bots do
		used[b.name] = true
	end
	local pool = {}
	for _, n in NAMES do
		if not used[n] then
			table.insert(pool, n)
		end
	end
	return if #pool > 0 then pool[rng:NextInteger(1, #pool)] else "Bot" .. rng:NextInteger(10, 99)
end

local function despawn(b: Bot)
	if not b.alive then
		return
	end
	b.alive = false
	local i = table.find(bots, b)
	if i then
		table.remove(bots, i)
	end
	Steal.onLeave(b.model) -- 들고 있던 큐브는 주인에게
	b.st.cubes:close()
	Plots.release(b.st.plot)
	b.model:Destroy()
end

local function spawnBot(): Bot?
	local name = freeName()
	local top, base, refReb = reference() -- 플롯을 잡기 전에 (여기서 오류가 나면 빈 플롯이 봇 이름으로 남았다)
	local plot = Plots.claimBot(name)
	if not plot then
		return nil
	end
	local data = { rebirths = refReb, stats = { drops = 0, merges = 0, best = 1 } }
	local st: BotState = {
		player = nil :: any,
		data = data,
		plot = plot,
		cubes = nil :: any,
		baseTier = base,
		topTier = top,
		dropAt = 0,
	}
	st.cubes = CubeWorld.new(plot, function()
		return ceilingOf(st)
	end, if Config.DATA_CUBES then SimBackend.new(plot) else nil)
	local ok, model = pcall(makeRig, name)
	if not ok then
		warn("bot rig failed", model)
		st.cubes:close()
		Plots.release(plot)
		return nil
	end
	st.player = model
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local b: Bot = {
		name = name,
		model = model,
		hum = hum,
		root = root,
		st = st,
		alive = true,
		chase = nil,
		stunUntil = 0,
		nextSteal = os.clock() + rng:NextNumber(30, B.STEAL_EVERY[1]),
		lastSwing = 0,
		swingTrack = nil,
		forceVictim = nil,
		lowSince = nil,
	}
	model:PivotTo(Plots.spawnCFrame(plot))
	model.Parent = workspace
	pcall(function()
		root:SetNetworkOwner(nil) -- 서버가 움직인다 (패드 비행·넉백 속도)
	end)
	local bat = Factory.makeBat()
	bat.Parent = model
	hum:EquipTool(bat)
	-- 드로퍼 2개 켜기 + 처음 트레이 (높은 것 몇 개 + 바닥 등급들)
	for i = 1, 2 do
		local d = plot.dropperParts[i]
		if d then
			d.Transparency = 0
			d.Color = Config.TIER_COLORS[base] or d.Color
		end
	end
	local n = 0
	for t = top, base, -1 do
		for _ = 1, (if t >= top - 1 then 1 else 2) do
			n += 1
			local col, row = (n - 1) % 5, ((n - 1) // 5) % 5
			local at = plot.center + Vector3.new(-12 + col * 6, Config.DROP_HEIGHT, -12 + row * 6)
			spawnCube(st, t, at)
		end
	end
	data.stats.best = top
	table.insert(bots, b)
	startAnims(b)
	task.spawn(function()
		while b.alive do
			local ok2, err = pcall(function()
				brain(b)
			end)
			if not ok2 and b.alive then
				warn(`bot {name} brain error: {tostring(err)}`)
				task.wait(2)
			end
		end
	end)
	return b
end

local function wanted(): number
	if forced then
		return forced
	end
	if not B.ENABLED then
		return 0
	end
	local real = #realPlayers()
	if real == 0 then
		return 0
	end
	return math.clamp(B.FILL_TO - real, 0, B.MAX)
end

------------------------------------------------------------------------
-- Steal 연결
------------------------------------------------------------------------

local api = {
	states = function(): { any }
		local out = {}
		for _, b in bots do
			table.insert(out, b.st)
		end
		return out
	end,
	stateOf = function(model: Model): any?
		local b = botOfModel(model)
		return b and b.st
	end,
	onStolen = function(st: any, thief: Player)
		for _, b in bots do
			if b.st == st and b.chase == nil and rng:NextNumber() < B.DEFEND_CHANCE then
				b.chase = thief
			end
		end
	end,
	roots = function(): { BasePart }
		local out = {}
		for _, b in bots do
			if b.alive and b.root.Parent then
				table.insert(out, b.root)
			end
		end
		return out
	end,
	knock = function(model: Model, v: Vector3)
		local b = botOfModel(model)
		if not b then
			return
		end
		b.stunUntil = os.clock() + 1.2
		b.hum:ChangeState(Enum.HumanoidStateType.Freefall)
		b.root.AssemblyLinearVelocity = v
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			if os.clock() - t0 > 0.35 or not b.root.Parent then
				conn:Disconnect()
				return
			end
			b.root.AssemblyLinearVelocity = Vector3.new(v.X, b.root.AssemblyLinearVelocity.Y, v.Z)
		end)
	end,
}

------------------------------------------------------------------------

-- Studio 디버그: "count" n(봇 수 고정, -1이면 자동) / "steal" player(아무 봇이 지금 그 사람을 턴다, 촬영용)
function Bots.debug(cmd: string, player: Player?, n: number?): boolean
	if cmd == "count" then
		forced = if n and n >= 0 then n else nil
		return true
	elseif cmd == "steal" and player then
		local st = Steal.playerStates()[player]
		if not st then
			return false
		end
		-- 그 사람 공장에서 가장 가까운 봇
		local b: Bot? = nil
		local best = math.huge
		for _, o in bots do
			local d = (o.root.Position - st.plot.center).Magnitude
			if d < best and not Steal.isCarrying(o.model) then
				b, best = o, d
			end
		end
		if not b then
			return false
		end
		lastVictim[player] = nil
		b.chase = nil
		b.forceVictim = st -- 지금 하던 행동이 끝나면 (brain)
		return true
	end
	return false
end

function Bots.init()
	Steal.setBots(api :: any)
	Plots.setEvict(function(plot)
		for _, b in bots do
			if b.st.plot == plot then
				despawn(b)
				return
			end
		end
		Plots.release(plot) -- 봇을 못 찾으면 자리만 비운다
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastVictim[player] = nil
	end)
	-- 봇 수 맞추기 (3초마다 하나씩) + 떨어지면 집으로
	task.spawn(function()
		while true do
			task.wait(3)
			-- 사람이 드나들면 봇 수준도 다시 맞춘다
			if #bots > 0 then
				local top, base, reb = reference()
				for _, b in bots do
					b.st.topTier, b.st.baseTier, b.st.data.rebirths = top, base, reb
				end
			end
			local want = wanted()
			if #bots < want and Plots.freeCount() > 0 then
				local ok, err = pcall(spawnBot)
				if not ok then
					warn(`bot spawn failed: {tostring(err)}`)
				end
			elseif #bots > want then
				-- 들고 있지 않은 봇부터
				local pick = bots[#bots]
				for _, b in bots do
					if not Steal.isCarrying(b.model) then
						pick = b
					end
				end
				despawn(pick)
			end
			for _, b in bots do
				-- 땅(광장·다리·플롯) 위면 몸통 높이 ≈ 4. 한참 낮으면 물에 빠진 것
				local low = b.root.Position.Y < 2.5
				b.lowSince = if low then (b.lowSince or os.clock()) else nil
				local stuck = b.lowSince ~= nil and os.clock() - (b.lowSince :: number) > 4
				if stuck or b.root.Position.Y < -30 or b.hum.Health <= 0 then
					b.lowSince = nil
					Steal.onLeave(b.model)
					b.hum.Health = b.hum.MaxHealth
					b.model:PivotTo(Plots.spawnCFrame(b.st.plot))
				end
			end
		end
	end)
	-- 봇 공장 (0.2초마다: 접촉 합치기가 늦지 않게. 사람 트레이는 Config.MERGE_SCAN_INTERVAL 0.1)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, b in bots do
			local ok, err = pcall(function()
				factoryStep(b.st, now)
			end)
			if not ok then
				warn(`bot {b.name} factory error: {tostring(err)}`)
			end
		end
	end)
end

return Bots
