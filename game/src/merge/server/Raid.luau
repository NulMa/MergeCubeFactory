--!strict
-- 보스 레이드 서버 (규칙·수치는 shared/Raid, docs/25_RAID.md).
-- 흐름: idle → invite(참여 받기, JOIN 누르면 바로 하늘 전장으로) → fight(보스전) → result(보상·집으로) → idle
-- 전장은 광장 위 하늘에 떠 있는 별도 섬 (참여자만 옮김, 2026-10-20 사용자). 모두 답하면 초대 시간을 기다리지 않고 시작.
-- 보스 타격은 Factory.onSwing이 Raid.onSwing으로 넘긴다 (한 대 1, 크리티컬 2. 간격은 각자 배트 SPEED).
-- 보스 4종 로테이션(shared/Raid.BOSSES): 레이드마다 다음 보스. 보스마다 패턴 두 가지를 번갈아 쓴다.
-- 패턴은 서버가 부품으로 그리고 판정한다: 충격파·레이저(점프), 낙하·덮치기·굴러오는 바위(비켜섬), 폭풍(안전 원으로).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Core.Net)
local Shared = ReplicatedStorage.Game
local Config = require(Shared.Config)
local RaidRules = require(Shared.Raid)
local Ledger = require(game:GetService("ServerScriptService").CoreServer.Ledger)

type Ctx = {
	states: { [Player]: any },
	center: Vector3, -- 광장 바닥 가운데
	fx: (player: Player, ...any) -> (), -- 메인 Fx 이벤트 (넉백 등)
	home: (player: Player) -> CFrame?,
	beforeTeleport: (player: Player) -> (), -- 들고 있던 훔친 큐브 돌려보내기
	resist: (data: { [string]: any }) -> number,
	applySpeed: (player: Player) -> (),
	refresh: (player: Player) -> (),
	hitGap: (player: Player) -> number, -- 각자 배트 쿨다운 (초)
}
type Joined = { hits: number, lastHit: number, stunUntil: number, hurt: number }

local Raid = {}

local ctx: Ctx? = nil
local net: any = nil
local rng = Random.new()

local phase = "idle"
local phaseEnds = 0
local nextInvite = 0
local joined: { [Player]: Joined } = {}
local knockedOut: { [Player]: Joined } = {} -- 목숨을 다 잃고 집에 간 사람 (보스가 잡히면 기여 보상)
local boss: Part? = nil
local bossFlash: Highlight? = nil
local bossBase: CFrame? = nil
local bossBusy = false -- 패턴 연출 중 (둥실 애니메이션 멈춤)
local hp, maxHp = 0, 0
local bossDef: RaidRules.Boss = RaidRules.BOSSES[1] -- 이번 레이드 보스
local bossSize = bossDef.size
local rotation = 0 -- 다음 레이드 보스 번호 (init에서 서버마다 무작위로 시작)
local answered: { [Player]: boolean } = {} -- 이번 초대에 답한 사람 (모두 답하면 바로 시작)
local inviteId = 0 -- 초대 번호 (늦게 들어온 사람도 이번 초대 창을 띄우게)
local arena = Vector3.zero -- 전장 바닥 가운데 (init에서 광장 위로)
local fx: { Instance } = {} -- 패턴 부품 (끝나면 지움)
local lastAir: { [Player]: number } = {} -- 마지막으로 떠 있던 때 (점프 판정 유예, RaidRules.JUMP_GRACE)

local function now(): number
	return os.clock()
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function log(player: Player, name: string)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, 1)
	end)
end

local function rootOf(p: Player): (BasePart?, Humanoid?)
	local char = p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?,
		char and char:FindFirstChildOfClass("Humanoid")
end

------------------------------------------------------------------------
-- 외부에서 쓰는 것
------------------------------------------------------------------------

-- 레이드 중인 참여자 (훔치기·배트 넉백·광장 상자 막기). JOIN을 누른 순간부터 전장에 있다
function Raid.inRaid(player: Player): boolean
	return phase ~= "idle" and joined[player] ~= nil
end

-- 승리 보상: 보스를 잡은 참여자만 잠시 x2 (data.raidBuff = 끝나는 os.time, 다시 들어와도 이어짐)
function Raid.buffLeft(data: { [string]: any }): number
	return math.max(0, (data.raidBuff or 0) - os.time())
end

function Raid.buffMult(data: { [string]: any }): number
	return if Raid.buffLeft(data) > 0 then RaidRules.BUFF_MULT else 1
end

-- 보스 코인 수입 강화 (영구 배수)
function Raid.incomeMult(data: { [string]: any }): number
	return 1 + RaidRules.incomeBonus(data.boss)
end

function Raid.snapshot(data: { [string]: any }): { [string]: any }
	return {
		coins = data.bossCoins or 0,
		levels = data.boss or {},
		buff = if Raid.buffLeft(data) > 0 then Raid.buffLeft(data) else nil,
		phase = phase,
	}
end

------------------------------------------------------------------------
-- 보스
------------------------------------------------------------------------

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function makeBoss(at: CFrame): Part
	local size = bossSize
	local def = bossDef
	local p = Instance.new("Part")
	p.Name = "RaidBoss"
	p.Size = Vector3.one * size
	p.CFrame = at
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.Color = rgb(def.color)
	p.Material = Enum.Material.SmoothPlastic
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local d = Instance.new("Decal")
		d.Name = "Face"
		d.Texture = Config.faceFor(def.face)
		d.Face = face
		d.Parent = p
	end
	-- 왕관: 금색 뿔 4개
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local spike = Instance.new("Part")
		spike.Name = "Crown"
		spike.Size = Vector3.new(2, 3.2, 2)
		spike.Color = rgb(def.crown)
		spike.Material = Enum.Material.Metal
		spike.Anchored = false
		spike.CanCollide = false
		spike.CanQuery = false
		spike.Massless = true
		spike.CFrame = at * CFrame.new(math.cos(a) * size * 0.32, size / 2 + 1.4, math.sin(a) * size * 0.32)
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = spike
		w.Parent = spike
		spike.Parent = p
	end
	local light = Instance.new("PointLight")
	light.Color = rgb(def.glow)
	light.Range = 30
	light.Brightness = 2
	light.Parent = p
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 1
	hl.OutlineColor = rgb(def.glow)
	hl.Parent = p
	bossFlash = hl
	-- 체력 막대 (모두에게)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Hp"
	bb.Size = UDim2.fromOffset(260, 46)
	bb.StudsOffset = Vector3.new(0, size / 2 + 5, 0)
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	bb.Parent = p
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 255)
	title.TextStrokeTransparency = 0
	title.Text = def.name
	title.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 0.4)
	back.Position = UDim2.fromScale(0, 0.55)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 40)
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 80, 140)
	fill.BorderSizePixel = 0
	fill.Parent = back
	p.Parent = workspace
	return p
end

local function setHpBar()
	local b = boss
	local fill = b and b:FindFirstChild("Fill", true) :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, maxHp), 0, 1), 1)
	end
end

------------------------------------------------------------------------
-- 판정 도우미
------------------------------------------------------------------------

-- 바닥은 전장 폴더만 본다 (buildArena에서 한 번 설정, 매번 제외 목록을 만들지 않음)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- 발밑 바닥 높이
local function floorY(pos: Vector3): number?
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), rayParams)
	return hit and hit.Position.Y
end

-- 땅을 딛고 서 있나 (충격파는 떠 있으면 피함)
local function grounded(root: BasePart, hum: Humanoid): boolean
	local y = floorY(root.Position)
	if not y then
		return false
	end
	local stand = hum.HipHeight + root.Size.Y / 2
	return root.Position.Y - y < stand + RaidRules.SLAM_JUMP
end

-- 점프로 피했나: 지금 떠 있거나 JUMP_GRACE 안에 떠 있었으면 (모바일 지연 여유). 매 프레임 모두 갱신한다
local function updateAir()
	local t = os.clock()
	for p in joined do
		local root, hum = rootOf(p)
		if root and hum and not grounded(root, hum) then
			lastAir[p] = t
		end
	end
end

local function jumped(p: Player): boolean
	return os.clock() - (lastAir[p] or -math.huge) < RaidRules.JUMP_GRACE
end

-- 머리 위 목숨 표시 (2026-10-21 사용자 "체력은 자기 머리 위에 뜨게"). 모두에게 보인다
local function setLives(player: Player, j: Joined?)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = head:FindFirstChild("RaidLives") :: BillboardGui?
	if not j then
		if bb then
			bb:Destroy()
		end
		return
	end
	local text: TextLabel
	if bb then
		text = bb:FindFirstChildOfClass("TextLabel") :: TextLabel
	else
		local g = Instance.new("BillboardGui")
		g.Name = "RaidLives"
		g.Size = UDim2.fromOffset(130, 30)
		g.StudsOffset = Vector3.new(0, 2.6, 0)
		g.AlwaysOnTop = true
		g.MaxDistance = 120
		g.LightInfluence = 0
		text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.RichText = true
		text.TextStrokeTransparency = 0.2
		text.Parent = g
		g.Parent = head
	end
	local left = math.max(0, RaidRules.LIVES - j.hurt)
	text.Text = `<font color="#ff4d6d">{string.rep("♥", left)}</font><font color="#5a5566">{string.rep(
		"♥",
		RaidRules.LIVES - left
	)}</font>`
end

local function teleportHome(player: Player)
	local c = ctx
	local cf = c and c.home(player)
	if c and cf and player.Character then
		c.beforeTeleport(player)
		local char = player.Character
		if char then
			char:PivotTo(cf)
		end
	end
end

-- 목숨을 다 잃음: 이번 보스전 실패 → 집으로. 보스가 잡히면 기여 보상만 (RaidRules.coins out)
local function knockOut(player: Player, j: Joined)
	joined[player] = nil
	knockedOut[player] = j
	setLives(player, nil)
	net.fire("Raid", player, "out")
	log(player, "RaidOut")
	task.delay(1.5, function()
		if player.Parent and phase ~= "idle" then
			teleportHome(player)
		end
	end)
end

local function knock(player: Player, from: Vector3)
	local c = ctx
	local j = joined[player]
	local root = rootOf(player)
	if not c or not j or not root then
		return
	end
	-- 표시 한가운데(발밑 낙하)면 보스 반대쪽으로 민다
	local flat = (root.Position - from) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1 then
		flat = (root.Position - arena) * Vector3.new(1, 0, 1)
	end
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
	local st = c.states[player]
	local resist = if st then c.resist(st.data) else 0
	c.fx(player, "knock", (dir * RaidRules.KNOCK_SPEED + Vector3.new(0, RaidRules.KNOCK_UP, 0)) * (1 - resist), player)
	local stun = RaidRules.stunFor(resist) -- RAIDER GUARD가 경직도 줄인다
	j.stunUntil = now() + stun
	j.hurt += 1
	net.fire("Raid", player, "hurt", stun, math.max(0, RaidRules.LIVES - j.hurt))
	if j.hurt >= RaidRules.LIVES then
		knockOut(player, j)
	else
		setLives(player, j)
	end
end

local function newFxPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = workspace
	table.insert(fx, p)
	return p
end

local function clearFx()
	for _, p in fx do
		p:Destroy()
	end
	table.clear(fx)
end

------------------------------------------------------------------------
-- 패턴
------------------------------------------------------------------------

local function tellJoined(...: any)
	for p in joined do
		net.fire("Raid", p, ...)
	end
end

-- 충격파: 보스가 뛰어올랐다 내려찍고, 바닥 고리가 퍼진다. 고리가 지나갈 때 땅에 있으면 맞음
local function slam()
	local c = ctx
	local b = boss
	local base = bossBase
	if not c or not b or not base then
		return
	end
	tellJoined("pattern", "slam")
	bossBusy = true
	TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = base + Vector3.new(0, 7, 0),
	}):Play()
	task.wait(0.55)
	if phase ~= "fight" then
		bossBusy = false
		return
	end
	TweenService:Create(b, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = base })
		:Play()
	task.wait(0.2)
	bossBusy = false
	local ground = arena.Y + 0.4
	local SEG = 36
	local segs: { Part } = {}
	for i = 1, SEG do
		segs[i] = newFxPart({
			Name = "RaidWave",
			Size = Vector3.new(3.4, 1.2, RaidRules.SLAM_BAND * 2),
			Color = Color3.fromRGB(255, 90, 90),
			Transparency = 0.15,
		})
	end
	local hitThis: { [Player]: boolean } = {}
	local t0 = now()
	local r0 = bossSize / 2 + 1
	while phase == "fight" do
		local a = (now() - t0) / RaidRules.SLAM_TIME
		if a > 1 then
			break
		end
		local r = r0 + (RaidRules.ARENA_R - r0) * a
		for i, s in segs do
			local ang = i / SEG * math.pi * 2
			local pos = arena + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			s.CFrame =
				CFrame.lookAt(Vector3.new(pos.X, ground + 0.6, pos.Z), Vector3.new(arena.X, ground + 0.6, arena.Z))
			-- lookAt이라 Z = 가운데 방향 → 둘레 길이는 X, 고리 두께는 Z (예전엔 반대로 넣어 빈틈 많은 점선이었음)
			s.Size = Vector3.new(math.max(2, r * 2 * math.pi / SEG * 1.1), 1.2, RaidRules.SLAM_BAND * 2)
		end
		updateAir()
		for p in joined do
			if hitThis[p] then
				continue
			end
			local root = rootOf(p)
			if root then
				local d = ((root.Position - arena) * Vector3.new(1, 0, 1)).Magnitude
				if math.abs(d - r) < RaidRules.SLAM_BAND and not jumped(p) then
					hitThis[p] = true
					knock(p, arena)
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	for _, s in segs do
		s:Destroy()
		local i = table.find(fx, s)
		if i then
			table.remove(fx, i)
		end
	end
end

-- 낙하: 참여자 발밑과 빈 곳에 붉은 원 → 잠시 뒤 큐브가 떨어져 원 안에 있으면 맞음
local function meteors()
	local c = ctx
	if not c then
		return
	end
	tellJoined("pattern", "meteor")
	local spots: { Vector3 } = {}
	for p in joined do
		local root = rootOf(p)
		if root then
			table.insert(spots, root.Position * Vector3.new(1, 0, 1) + Vector3.new(0, arena.Y, 0))
		end
	end
	local want = RaidRules.meteorCount(count(joined))
	while #spots < want do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(bossSize, RaidRules.ARENA_R)
		table.insert(spots, arena + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	local marks: { Part } = {}
	for i, at in spots do
		local y = floorY(at + Vector3.new(0, 20, 0)) or arena.Y
		spots[i] = Vector3.new(at.X, y, at.Z)
		marks[i] = newFxPart({
			Name = "RaidMark",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, RaidRules.METEOR_R * 2, RaidRules.METEOR_R * 2),
			CFrame = CFrame.new(spots[i] + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 60, 60),
			Transparency = 0.45,
		})
	end
	task.wait(RaidRules.METEOR_WARN)
	if phase ~= "fight" then
		return
	end
	local rocks: { Part } = {}
	for i, at in spots do
		local rock = newFxPart({
			Name = "RaidRock",
			Size = Vector3.one * 4,
			CFrame = CFrame.new(at + Vector3.new(0, 30, 0)),
			Color = rgb(bossDef.color),
			Material = Enum.Material.SmoothPlastic,
		})
		rocks[i] = rock
		TweenService:Create(rock, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(at + Vector3.new(0, 2, 0)),
		}):Play()
	end
	task.wait(0.27)
	if phase ~= "fight" then
		return
	end
	for p in joined do
		local root = rootOf(p)
		if not root then
			continue
		end
		for _, at in spots do
			local off = root.Position - at
			if (off * Vector3.new(1, 0, 1)).Magnitude < RaidRules.METEOR_R and off.Y < 8 then
				knock(p, at)
				break
			end
		end
	end
	task.wait(0.4)
	for _, list in { marks, rocks } do
		for _, p in list do
			p:Destroy()
			local i = table.find(fx, p)
			if i then
				table.remove(fx, i)
			end
		end
	end
end

local function dropFx(list: { any })
	for _, p in list do
		p:Destroy()
		local i = table.find(fx, p)
		if i then
			table.remove(fx, i)
		end
	end
end

local function flatDist(a: Vector3, b: Vector3): number
	return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

-- 레이저 (LASER CUBE): 바닥 높이로 전장 지름을 가르는 빛줄기가 반 바퀴 돈다. 지나갈 때 땅에 있으면 맞음 → 점프
local function laser()
	tellJoined("pattern", "laser")
	local len = RaidRules.ARENA_EDGE * 2
	local beam = newFxPart({
		Name = "RaidLaser",
		Size = Vector3.new(len, 1.4, 1.4),
		Color = Color3.fromRGB(255, 60, 60),
		Transparency = 0.4,
	})
	local a0 = rng:NextNumber(0, math.pi * 2)
	local dir = if rng:NextInteger(0, 1) == 0 then -1 else 1
	local function place(a: number)
		beam.CFrame = CFrame.new(arena + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, a, 0)
	end
	place(a0)
	-- 도는 방향 표시: 양 끝에서 앞으로 점 3개 (가까울수록 진하게)
	local dots: { Instance } = {}
	for side = -1, 1, 2 do
		for i = 1, 3 do
			local a = a0 + dir * 0.09 * i
			local r = RaidRules.ARENA_R * 0.8 * side
			table.insert(
				dots,
				newFxPart({
					Name = "RaidLaserDir",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * (2.2 - 0.4 * i),
					CFrame = CFrame.new(arena + Vector3.new(math.cos(a) * r, 1.3, -math.sin(a) * r)),
					Color = Color3.fromRGB(255, 200, 80),
					Transparency = 0.1 + 0.2 * i,
				})
			)
		end
	end
	task.wait(RaidRules.LASER_WARN)
	dropFx(dots)
	if phase ~= "fight" then
		dropFx({ beam })
		return
	end
	beam.Transparency = 0
	beam.Size = Vector3.new(len, 1.4, 1.4)
	local hitThis: { [Player]: boolean } = {}
	local t0 = now()
	while phase == "fight" do
		local k = (now() - t0) / RaidRules.LASER_TIME
		if k > 1 then
			break
		end
		local a = a0 + dir * math.pi * k
		place(a)
		-- CFrame.Angles(0, a, 0)의 X축 = (cos a, 0, -sin a)
		local d = Vector3.new(math.cos(a), 0, -math.sin(a))
		updateAir()
		for p in joined do
			if hitThis[p] then
				continue
			end
			local root = rootOf(p)
			if root then
				local o = (root.Position - arena) * Vector3.new(1, 0, 1)
				local perp = math.abs(o.X * d.Z - o.Z * d.X)
				if perp < RaidRules.LASER_BAND and o.Magnitude > bossSize / 2 and not jumped(p) then
					hitThis[p] = true
					knock(p, arena)
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	dropFx({ beam })
end

-- 덮치기 (JUMBO CUBE): 참여자 발밑에 붉은 원 → 보스가 높이 뛰어 그 자리에 떨어진다 → 비켜섬. 몇 번 하고 가운데로
local function pounce()
	local b = boss
	local base = bossBase
	if not b or not base then
		return
	end
	tellJoined("pattern", "pounce")
	local targets: { Player } = {}
	for p in joined do
		table.insert(targets, p)
	end
	if #targets == 0 then
		return
	end
	-- 섞어서 차례로 (같은 사람만 계속 노리지 않게)
	for i = #targets, 2, -1 do
		local j = rng:NextInteger(1, i)
		targets[i], targets[j] = targets[j], targets[i]
	end
	bossBusy = true
	for k = 1, RaidRules.pounceCount(#targets) do
		if phase ~= "fight" then
			break
		end
		local target = targets[(k - 1) % #targets + 1]
		local root = rootOf(target)
		local at = if root then Vector3.new(root.Position.X, arena.Y, root.Position.Z) else arena
		local flat = (at - arena) * Vector3.new(1, 0, 1)
		if flat.Magnitude > RaidRules.ARENA_R then
			at = arena + flat.Unit * RaidRules.ARENA_R
		end
		local mark = newFxPart({
			Name = "RaidMark",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, RaidRules.POUNCE_R * 2, RaidRules.POUNCE_R * 2),
			CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 60, 60),
			Transparency = 0.45,
		})
		TweenService:Create(b, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(at + Vector3.new(0, bossSize / 2 + 24, 0)),
		}):Play()
		task.wait(RaidRules.POUNCE_WARN)
		if phase ~= "fight" then
			dropFx({ mark })
			break
		end
		TweenService:Create(b, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(at + Vector3.new(0, bossSize / 2, 0)),
		}):Play()
		task.wait(0.22)
		if phase ~= "fight" then
			dropFx({ mark })
			break
		end
		for p in joined do
			local pr = rootOf(p)
			if pr and flatDist(pr.Position, at) < RaidRules.POUNCE_R and pr.Position.Y - at.Y < bossSize then
				knock(p, at)
			end
		end
		dropFx({ mark })
		task.wait(if k == 1 then 0.5 else 0.35)
	end
	if phase == "fight" then
		TweenService:Create(b, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = base })
			:Play()
		task.wait(0.6)
	end
	bossBusy = false
end

-- 폭풍 (STORM CUBE): 전장이 붉게 물들고 초록 안전 원 몇 개만 남는다 → 시간 안에 원 안으로 (점프해도 맞음)
local function storm()
	tellJoined("pattern", "storm")
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local red = newFxPart({
		Name = "RaidStorm",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, RaidRules.ARENA_EDGE * 2, RaidRules.ARENA_EDGE * 2),
		CFrame = CFrame.new(arena + Vector3.new(0, 0.15, 0)) * flat,
		Color = Color3.fromRGB(255, 50, 50),
		Transparency = 0.7,
	})
	local zones: { Vector3 } = {}
	local parts: { Instance } = { red }
	local n = RaidRules.stormZones(count(joined))
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, n do
		local a = a0 + i / n * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = rng:NextNumber(bossSize / 2 + RaidRules.STORM_SAFE_R + 1, RaidRules.ARENA_R - 4)
		local at = arena + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		table.insert(zones, at)
		table.insert(
			parts,
			newFxPart({
				Name = "RaidSafe",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, RaidRules.STORM_SAFE_R * 2, RaidRules.STORM_SAFE_R * 2),
				CFrame = CFrame.new(at + Vector3.new(0, 0.25, 0)) * flat,
				Color = Color3.fromRGB(80, 255, 120),
				Transparency = 0.25,
			})
		)
	end
	-- 경고 동안 붉은 판이 점점 짙어진다
	TweenService:Create(red, TweenInfo.new(RaidRules.STORM_WARN), { Transparency = 0.35 }):Play()
	task.wait(RaidRules.STORM_WARN)
	if phase ~= "fight" then
		dropFx(parts)
		return
	end
	red.Color = Color3.fromRGB(255, 255, 200)
	red.Transparency = 0.1
	for p in joined do
		local root = rootOf(p)
		if not root then
			continue
		end
		local safe = false
		for _, at in zones do
			if flatDist(root.Position, at) < RaidRules.STORM_SAFE_R then
				safe = true
				break
			end
		end
		if not safe then
			knock(p, root.Position + Vector3.new(0, 0, 0.1))
		end
	end
	task.wait(0.35)
	dropFx(parts)
end

-- 굴러오는 바위 (STORM CUBE): 보스에서 바깥으로 여러 줄 예고 → 큐브 바위가 줄을 따라 굴러감 → 줄 사이로 비켜섬
local function spokes()
	tellJoined("pattern", "spokes")
	local n = RaidRules.SPOKES
	local a0 = rng:NextNumber(0, math.pi * 2)
	local r0, r1 = bossSize / 2 + 1, RaidRules.ARENA_EDGE
	local lines: { Instance } = {}
	local dirs: { Vector3 } = {}
	for i = 1, n do
		local a = a0 + i / n * math.pi * 2
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		dirs[i] = d
		local mid = arena + d * (r0 + r1) / 2 + Vector3.new(0, 0.2, 0)
		table.insert(
			lines,
			newFxPart({
				Name = "RaidMark",
				Size = Vector3.new(RaidRules.SPOKE_STRIPE, 0.3, r1 - r0),
				CFrame = CFrame.lookAt(mid, mid + d),
				Color = Color3.fromRGB(255, 60, 60),
				Transparency = 0.5,
			})
		)
	end
	task.wait(RaidRules.SPOKE_WARN)
	if phase ~= "fight" then
		dropFx(lines)
		return
	end
	local rocks: { Part } = {}
	for i = 1, n do
		rocks[i] = newFxPart({
			Name = "RaidRock",
			Size = Vector3.one * 4,
			Color = rgb(bossDef.color),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	local hitThis: { [Player]: boolean } = {}
	local t0 = now()
	while phase == "fight" do
		local k = (now() - t0) / RaidRules.SPOKE_TIME
		if k > 1 then
			break
		end
		local r = r0 + (r1 - r0) * k
		for i, rock in rocks do
			local at = arena + dirs[i] * r + Vector3.new(0, 2, 0)
			rock.CFrame = CFrame.new(at) * CFrame.Angles(k * 12, 0, 0)
			for p in joined do
				if hitThis[p] then
					continue
				end
				local root = rootOf(p)
				if root and flatDist(root.Position, at) < RaidRules.SPOKE_HIT and root.Position.Y - at.Y < 5 then
					hitThis[p] = true
					knock(p, at - dirs[i] * 2)
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	dropFx(lines)
	dropFx(rocks)
end

local PATTERNS: { [string]: () -> () } = {
	slam = slam,
	meteor = meteors,
	laser = laser,
	pounce = pounce,
	storm = storm,
	spokes = spokes,
}

------------------------------------------------------------------------
-- 흐름
------------------------------------------------------------------------

local function inviteInfo(): (number, number)
	return math.max(0, phaseEnds - now()), count(joined)
end

local function startInvite()
	phase = "invite"
	phaseEnds = now() + RaidRules.INVITE
	table.clear(joined)
	table.clear(knockedOut)
	table.clear(answered)
	table.clear(lastAir)
	inviteId += 1
	-- 로테이션: 레이드마다 다음 보스
	bossDef = RaidRules.bossAt(rotation)
	bossSize = bossDef.size
	rotation += 1
	local left, n = inviteInfo()
	net.fireAll("Raid", "invite", left, n, bossDef.id, inviteId)
end

local function teleport(player: Player, cf: CFrame)
	local c = ctx
	if not c or not player.Character then
		return
	end
	c.beforeTeleport(player)
	-- 스트리밍이 켜져 있으면 도착지를 먼저 받아 둔다 (하늘 전장이 아직 안 보였을 수 있음)
	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 3)
		end)
	end
	local char = player.Character
	if char then
		char:PivotTo(cf)
	end
end

-- 전장 둘레 원의 i번째 자리 (보스를 보게). 몇 명이 오든 겹치지 않게 2.4라디안씩 돌려 흩어 놓는다
local function spawnCFrame(i: number): CFrame
	local a = (i - 0.5) * 2.4 + math.pi / 2
	local pos = arena + Vector3.new(math.cos(a), 0, math.sin(a)) * RaidRules.SPAWN_R + Vector3.new(0, 4, 0)
	return CFrame.lookAt(pos, Vector3.new(arena.X, pos.Y, arena.Z))
end

------------------------------------------------------------------------
-- 전장 (광장 위 하늘 섬, 한 번만 만든다)
------------------------------------------------------------------------

local function buildArena()
	local folder = Instance.new("Folder")
	folder.Name = "RaidArena"
	local function piece(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in props do
			(p :: any)[k] = v
		end
		p.Parent = folder
		return p
	end
	local edge = RaidRules.ARENA_EDGE
	local flat = CFrame.Angles(0, 0, math.rad(90))
	-- 바닥 (윗면 = arena.Y) + 빛나는 테두리 + 패턴 범위 표시
	piece({
		Name = "ArenaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, edge * 2, edge * 2),
		CFrame = CFrame.new(arena - Vector3.new(0, 2, 0)) * flat,
		Color = Color3.fromRGB(45, 35, 70),
		Material = Enum.Material.Slate,
	})
	piece({
		Name = "ArenaRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, edge * 2 + 3, edge * 2 + 3),
		CFrame = CFrame.new(arena - Vector3.new(0, 2.6, 0)) * flat,
		Color = Color3.fromRGB(170, 90, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	piece({
		Name = "ArenaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, RaidRules.ARENA_R * 2, RaidRules.ARENA_R * 2),
		CFrame = CFrame.new(arena + Vector3.new(0, 0.05, 0)) * flat,
		Color = Color3.fromRGB(80, 60, 120),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	-- 아래로 늘어진 바위 (떠 있는 섬처럼)
	for i, r in { edge * 0.85, edge * 0.6, edge * 0.35 } do
		piece({
			Name = "ArenaRock",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, r * 2, r * 2),
			CFrame = CFrame.new(arena - Vector3.new(0, 4 + i * 5, 0)) * flat,
			Color = Color3.fromRGB(70, 55, 95),
			Material = Enum.Material.Rock,
			CanCollide = false,
			CanQuery = false,
		})
	end
	-- 둘레 기둥 8개 (불 켜진 머리) + 보이지 않는 울타리 (밀려나도 떨어지지 않게)
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local at = arena + Vector3.new(math.cos(a), 0, math.sin(a)) * (edge - 2)
		piece({
			Name = "ArenaPillar",
			Size = Vector3.new(2.4, 10, 2.4),
			CFrame = CFrame.new(at + Vector3.new(0, 5, 0)),
			Color = Color3.fromRGB(60, 50, 90),
			Material = Enum.Material.Marble,
		})
		local top = piece({
			Name = "ArenaFlame",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.6,
			CFrame = CFrame.new(at + Vector3.new(0, 11, 0)),
			Color = Color3.fromRGB(200, 120, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Color = top.Color
		light.Range = 18
		light.Parent = top
	end
	local SEG = 32
	for i = 1, SEG do
		local a = i / SEG * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = arena + dir * (edge + 0.5) + Vector3.new(0, 8, 0)
		piece({
			Name = "ArenaFence",
			Size = Vector3.new(edge * 2 * math.pi / SEG + 1, 16, 1),
			CFrame = CFrame.lookAt(at, at + dir),
			Transparency = 1,
			CanQuery = false,
		})
	end
	folder.Parent = workspace
	rayParams.FilterDescendantsInstances = { folder }
end

local function fightInfo(p: Player): { [string]: any }
	local j = joined[p]
	return {
		hp = hp,
		maxHp = maxHp,
		left = math.max(0, phaseEnds - now()),
		players = count(joined),
		boss = bossDef.id,
		hits = if j then j.hits else nil,
	}
end

-- 보스는 첫 참여자가 전장에 오면 미리 띄워 둔다 (기다리는 동안 볼 수 있게, 때리기는 전투부터)
local function ensureBoss()
	if boss then
		return
	end
	bossBase = CFrame.new(arena + Vector3.new(0, RaidRules.BOSS_HOVER, 0))
	boss = makeBoss(bossBase :: CFrame)
	maxHp = RaidRules.hp(math.max(1, count(joined)))
	hp = maxHp
	setHpBar()
end

-- 보스 치우기 (참여자가 모두 나가 초대가 끝났을 때. 남겨 두면 다음 보스가 예전 모양을 다시 씀)
local function removeBoss()
	if boss then
		boss:Destroy()
	end
	boss = nil
	bossBase = nil
	bossFlash = nil
	bossBusy = false
end

local function startFight()
	phase = "fight"
	phaseEnds = now() + RaidRules.FIGHT
	bossBusy = false
	ensureBoss()
	maxHp = RaidRules.hp(count(joined))
	hp = maxHp
	setHpBar()
	for p in joined do
		log(p, "RaidJoin")
		net.fire("Raid", p, "start", fightInfo(p))
	end
	-- 패턴: 이번 보스의 패턴들을 번갈아. 체력이 절반 아래면 분노(간격 짧게)
	task.spawn(function()
		local kinds = bossDef.patterns
		local i = rng:NextInteger(1, #kinds)
		local enraged = false
		task.wait(RaidRules.FIRST_PATTERN)
		while phase == "fight" do
			local f = PATTERNS[kinds[i]]
			if f then
				-- 패턴 하나가 실패해도 이번 전투의 다음 패턴·다음 레이드는 이어지게
				local ok, err = pcall(function()
					f()
				end)
				if not ok then
					warn("Raid pattern " .. kinds[i] .. " failed: " .. tostring(err))
				end
				bossBusy = false
			end
			i = i % #kinds + 1
			if not enraged and phase == "fight" and hp < maxHp * RaidRules.ENRAGE_AT then
				enraged = true
				tellJoined("pattern", "enrage")
			end
			task.wait(if enraged then RaidRules.ENRAGE_GAP else RaidRules.PATTERN_GAP)
		end
	end)
end

local function finish(win: boolean)
	local c = ctx
	if not c then
		return
	end
	phase = "result"
	phaseEnds = now() + RaidRules.RESULT
	clearFx()
	local b = boss
	if b then
		if win then
			-- 터지듯 커지며 사라짐
			b.CanCollide = false
			TweenService:Create(b, TweenInfo.new(0.6), { Size = b.Size * 1.6, Transparency = 1 }):Play()
			task.delay(0.7, function()
				b:Destroy()
			end)
		else
			b:Destroy()
		end
	end
	boss = nil
	bossBase = nil
	bossBusy = false
	-- 보상·x2는 참여자만 (2026-10-20 사용자). 참여하지 않은 사람에게는 아무것도 보내지 않는다.
	-- 탈락자는 보스가 잡혔을 때만 기여 보상(10%), x2 없음. 아무도 못 잡으면 보상 없음 (2026-10-21 사용자).
	-- 한 사람에게서 오류가 나도 나머지는 받게 사람마다 pcall
	local everyone: { [Player]: boolean } = {}
	for p in joined do
		everyone[p] = false
		setLives(p, nil)
	end
	for p in knockedOut do
		everyone[p] = true
	end
	for p, out in everyone do
		local j = if out then knockedOut[p] else joined[p]
		local ok, err = pcall(function()
			local coins = RaidRules.coins(win, j.hits, out)
			if coins > 0 then
				Ledger.credit(p, "bossCoins", coins, "Gameplay", if win then "raid_win" else "raid_try")
			end
			local buff = 0
			local st = c.states[p]
			if win and coins > 0 and st and not out then
				st.data.raidBuff = os.time() + RaidRules.BUFF_SECONDS
				buff = RaidRules.BUFF_SECONDS
				log(p, "RaidWin")
			end
			net.fire("Raid", p, "end", win, coins, buff, j.hits, out)
			c.refresh(p)
		end)
		if not ok then
			warn("Raid reward failed for " .. p.Name .. ": " .. tostring(err))
		end
	end
end

local function backHome()
	local c = ctx
	if not c then
		return
	end
	-- 먼저 idle로 (teleport가 스트리밍을 기다리는 동안 step이 다시 들어와 여러 번 보내지 않게)
	local list: { Player } = {}
	for p in joined do
		table.insert(list, p)
	end
	table.clear(joined)
	table.clear(knockedOut)
	phase = "idle"
	nextInvite = now() + RaidRules.EVERY
	net.fireAll("Raid", "idle", RaidRules.EVERY)
	for _, p in list do
		local cf = c.home(p)
		if cf then
			task.spawn(teleport, p, cf)
		end
	end
end

-- 공장이 로드된 사람이 모두 답했나 (그러면 초대 시간을 다 기다리지 않는다)
local function allAnswered(): boolean
	local c = ctx
	if not c then
		return false
	end
	for _, p in Players:GetPlayers() do
		if c.states[p] and not answered[p] then
			return false
		end
	end
	return true
end

local function step()
	local t = now()
	if phase == "idle" then
		if t >= nextInvite and #Players:GetPlayers() > 0 then
			startInvite()
		end
	elseif phase == "invite" then
		-- 모두 답하면 onJoin이 phaseEnds를 "마지막 답 + 3초"로 당긴다
		if t >= phaseEnds then
			if next(joined) then
				startFight()
			else
				removeBoss()
				phase = "idle"
				nextInvite = t + RaidRules.EVERY
				net.fireAll("Raid", "idle", RaidRules.EVERY)
			end
		end
	elseif phase == "fight" then
		if hp <= 0 then
			finish(true)
		elseif t >= phaseEnds or not next(joined) then
			finish(false)
		else
			for p in joined do
				net.fire("Raid", p, "tick", fightInfo(p))
			end
		end
	elseif phase == "result" then
		if t >= phaseEnds then
			backHome()
		end
	end
	-- 전장 밖(떨어짐·리스폰으로 집에 감)이면 전장 가장자리로 되돌린다
	if phase == "invite" or phase == "fight" then
		for p, j in joined do
			-- 리스폰하면 머리 위 목숨 표시를 다시 단다
			local head = p.Character and p.Character:FindFirstChild("Head")
			if head and not head:FindFirstChild("RaidLives") then
				setLives(p, j)
			end
			local root = rootOf(p)
			if root then
				local off = root.Position - arena
				local flat = off * Vector3.new(1, 0, 1)
				-- 아래로 떨어졌거나, 밖으로 나갔거나, 비정상적으로 높이 떠 있으면 (날기 핵: 패턴을 피하며 때리기)
				if off.Y < -4 or off.Y > RaidRules.MAX_ABOVE or flat.Magnitude > RaidRules.ARENA_EDGE + 4 then
					local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
					local pos = arena + dir * RaidRules.SPAWN_R + Vector3.new(0, 4, 0)
					task.spawn(teleport, p, CFrame.lookAt(pos, Vector3.new(arena.X, pos.Y, arena.Z)))
				end
			end
		end
	end
end

-- 보스 둥실 + 천천히 회전 (패턴 연출 중엔 멈춤)
local function animate()
	local b = boss
	local base = bossBase
	if not b or not base or bossBusy or phase ~= "fight" then
		return
	end
	local t = now()
	b.CFrame = base * CFrame.new(0, math.sin(t * 1.5) * 0.8, 0) * CFrame.Angles(0, t * 0.6, 0)
end

------------------------------------------------------------------------
-- 입력
------------------------------------------------------------------------

local function onJoin(player: Player, yes: boolean): boolean
	local c = ctx
	if phase ~= "invite" or not c or not c.states[player] then
		return false
	end
	-- 한 번만 답한다 (연타해도 서버 전체에 다시 보내지 않게)
	if answered[player] then
		return joined[player] ~= nil
	end
	answered[player] = true
	if yes then
		-- 누르는 즉시 전장으로 (2026-10-20 사용자 "수락시 바로 맵 이동 + 알림창은 꺼줘")
		local j = { hits = 0, lastHit = 0, stunUntil = 0, hurt = 0 }
		joined[player] = j
		ensureBoss()
		task.spawn(function()
			teleport(player, spawnCFrame(count(joined)))
			setLives(player, j)
		end)
	end
	-- 모두 답했으면 마지막 답 3초 뒤 시작 (도착·둘러보기)
	if next(joined) and allAnswered() then
		phaseEnds = math.min(phaseEnds, now() + RaidRules.EARLY_START)
		tellJoined("wait", math.max(0, phaseEnds - now()))
	elseif yes then
		net.fire("Raid", player, "wait", math.max(0, phaseEnds - now()))
	end
	local left, n = inviteInfo()
	net.fireAll("Raid", "invite", left, n, bossDef.id, inviteId)
	return true
end

-- Factory.onSwing에서: 보스를 맞혔으면 1 (크리티컬이면 보스 체력 2). 간격은 각자 배트 SPEED 쿨다운
-- (예전엔 0.9초 고정이라 SPEED를 올린 배트로 빨리 휘두르면 헛스윙이 났다, 2026-10-20 사용자)
function Raid.onSwing(player: Player, root: BasePart): number
	local j = joined[player]
	local b = boss
	local c = ctx
	if phase ~= "fight" or not j or not b or not c then
		return 0
	end
	local t = now()
	-- Factory가 이미 같은 쿨다운(85%)으로 걸렀다. 여기서는 지연 때문에 두 번 오는 것만 막는다
	if t < j.stunUntil or t - j.lastHit < c.hitGap(player) * 0.6 then
		return 0
	end
	local flat = ((b.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
	local dy = math.abs(b.Position.Y - root.Position.Y)
	if flat > RaidRules.REACH + bossSize / 2 + 1 or dy > bossSize / 2 + RaidRules.REACH_UP then
		return 0
	end
	local st = c.states[player]
	local eq = st and st.data.cosmetics and st.data.cosmetics.equipped
	local crit = rng:NextNumber() < RaidRules.critChance(eq and eq.bat)
	local dmg = if crit then RaidRules.CRIT_DAMAGE else 1
	j.hits += dmg
	j.lastHit = t
	hp = math.max(0, hp - dmg)
	net.fire("Raid", player, "hit", crit, dmg)
	setHpBar()
	local hl = bossFlash
	if hl then
		hl.FillTransparency = 0.4
		task.delay(0.08, function()
			hl.FillTransparency = 1
		end)
	end
	return 1
end

local function onUpgrade(player: Player, id: string): boolean
	local c = ctx
	local st = c and c.states[player]
	local u = RaidRules.upgrade(id)
	if not c or not st or not u then
		return false
	end
	local data = st.data
	data.boss = data.boss or {}
	local lv = data.boss[id] or 0
	if lv >= u.max or not RaidRules.unlocked(data.boss, id) then
		return false
	end
	if not Ledger.debit(player, "bossCoins", RaidRules.cost(lv, id), "Shop", "boss_" .. id) then
		return false
	end
	data.boss[id] = lv + 1
	if id == "speed" then
		c.applySpeed(player)
	end
	c.refresh(player)
	return true
end

-- Studio 디버그: 다음 보스 고르기 / 지금 초대 시작 / 바로 전투 / 보스 체력 1로
function Raid.debug(cmd: string)
	local id = string.match(cmd, "^boss:(%w+)$")
	if id then
		-- 다음 레이드 보스 고르기 (예: "boss:laser")
		for i, b in RaidRules.BOSSES do
			if b.id == id then
				rotation = i - 1
			end
		end
	elseif cmd == "start" and phase == "idle" then
		nextInvite = 0
	elseif cmd == "fight" and phase == "invite" then
		phaseEnds = 0
	elseif cmd == "low" and phase == "fight" then
		hp = 1
		setHpBar()
	end
end

function Raid.init(c: Ctx)
	ctx = c
	arena = c.center + Vector3.new(0, RaidRules.ARENA_HEIGHT, 0)
	buildArena()
	net = Net.serve(RaidRules.REMOTES :: any)
	net.on("RaidJoin", onJoin)
	net.on("RaidUpgrade", onUpgrade)
	nextInvite = now() + RaidRules.FIRST
	rotation = rng:NextInteger(0, #RaidRules.BOSSES - 1) -- 서버마다 시작 보스는 무작위
	Players.PlayerRemoving:Connect(function(p)
		joined[p] = nil
		knockedOut[p] = nil
		answered[p] = nil
		lastAir[p] = nil
	end)
	-- 늦게 들어온 사람에게 지금 상태
	Players.PlayerAdded:Connect(function(p)
		task.delay(5, function()
			if not p.Parent then
				return
			end
			if phase == "invite" then
				local left, n = inviteInfo()
				net.fire("Raid", p, "invite", left, n, bossDef.id, inviteId)
			elseif phase == "idle" then
				net.fire("Raid", p, "idle", math.max(0, nextInvite - now()))
			end
		end)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		animate()
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			step()
		end)
		if not ok then
			warn("Raid step failed: " .. tostring(err))
		end
	end)
end

return Raid
