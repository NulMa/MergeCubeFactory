--!strict
-- 큐브 훔치기 + 배트로 사람 날리기 (2026-10-18 사용자 요청, docs/22)
--   * 남의 트레이 안에서 STEAL → 가장 가까운 큐브를 머리 위에 들고, 아주 느려진다
--   * 주인에게 알림 + 도둑 위치 표시. 도둑이 배트에 맞거나, 죽거나, 나가거나, 시간이 다 되면 큐브는 주인에게 돌아간다
--   * 내 공장 땅(플롯)에 들어서면 내 트레이로 들어가 내 것이 된다
--   * 횟수: 2분마다 1회 충전, 최대 3회 + 상품(Steal x3)
--   * 공정성 (2026-10-20, 리뷰): 내 합치기 상한(tierCeiling)보다 높은 큐브는 못 훔친다(새 유저가 고참 T29를 가져가 바로 리버스하던 문제),
--     리버스 1회 이상인 사람은 리버스 0회인 사람 것을 못 훔친다(첫 판 보호),
--     들고 가는 동안 서버가 이동 거리·최소 운반 시간을 확인한다(순간이동으로 바로 집에 가던 문제)
-- 큐브 상태(states, spawnCube ...)는 Factory가 init에서 넘겨준다 (Events와 같은 방식).
-- AI 플레이어(server/Bots, 2026-10-24): 도둑·주인·때리는 쪽이 봇 Model일 수 있다. 봇 공장 상태는 Steal.setBots로 받는다.
--   알림(net.fire)·통계·횟수는 사람에게만, 규칙(상위 2등급 보호·상한·리버스 0회 보호·운반 시간)은 똑같이

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local RaidRules = require(Shared.Raid)
local Strings = require(Shared.Strings)
local CubeStyle = require(Shared.CubeStyle) -- 들고 가는 큐브 겉모습 (데이터 큐브면 서버 파트가 없어 새로 만든다)
local Collection = require(script.Parent.Collection) -- 오라 단계 → 넉백 저항

local Steal = {}

-- 보스 레이드 중인 사람 (server/Raid가 setRaidCheck로 넣는다): 레이드 중엔 그 사람을 때리거나 그 공장을 털 수 없다
local inRaid: (Player) -> boolean = function(_player: Player)
	return false
end
function Steal.setRaidCheck(f: (Player) -> boolean)
	inRaid = f
end

-- server/Bots가 넣는다. who = 사람(Player) 또는 봇(Model)
type BotApi = {
	states: () -> { any }, -- 봇 공장 상태 (st.player = 봇 Model)
	stateOf: (bot: Model) -> any?,
	onStolen: (st: any, thief: Player) -> (), -- 봇 트레이를 털림 → 쫓아가기
	roots: () -> { BasePart }, -- 배트에 맞을 수 있는 봇 몸통
	knock: (bot: Model, v: Vector3) -> (),
}
local bots: BotApi? = nil
function Steal.setBots(api: BotApi)
	bots = api
end

type Ctx = {
	states: { [Player]: any },
	spawnCube: (st: any, tier: number, position: Vector3, variant: number?) -> number, -- 큐브 id
	onVariant: (st: any, cube: number, how: string) -> (),
	trayPoint: (st: any, x: number, z: number) -> Vector3,
	push: (st: any) -> (),
	net: any,
}
type Carry = {
	thief: any, -- Player | 봇 Model
	owner: any,
	ownerSt: any,
	tier: number,
	variant: number,
	part: Part,
	root: BasePart, -- 리스폰하면 바뀜 → 떨어뜨린 것으로
	since: number,
	jump: number,
	lastPos: Vector3, -- 0.2초마다 이동 거리 확인 (순간이동)
	padUntil: number, -- 점프 패드 근처에 선 뒤 이 시각까지는 빠른 비행 허용
	minHome: number, -- 이 시각 전엔 집에 들어와도 아직 확정하지 않는다 (최소 운반 시간)
}

local ctx: Ctx
local carrying: { [any]: Carry } = {}
local knockedAt: { [any]: number } = {}
local debugSelf = false -- Studio 전용: 내 트레이에서 훔치고 광장(가운데)을 "집"으로 (혼자 확인용)
local PAD_NEAR = 7 -- 점프 패드에서 이만큼 안이면 발사 직전으로 본다
local PAD_WINDOW = 2.5 -- 발사 뒤 비행 허용 시간
local PAD_SPEED = 70 -- 비행 중 허용 수평 속도 (스터드/초)
local MIN_CARRY_SHARE = 0.5 -- 집까지 직선거리를 들고 걷는 속도로 간 시간의 이 비율은 지나야 확정 (패드로 줄어드는 몫 감안)

local function isPlayer(who: any): boolean
	return typeof(who) == "Instance" and who:IsA("Player")
end

local function rootOf(who: any): (BasePart?, Humanoid?)
	local char: Model? = if isPlayer(who) then who.Character else who
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return nil, nil
	end
	return root, hum
end

-- 사람이면 Factory 상태, 봇이면 Bots 상태
local function stateOf(who: any): any?
	if isPlayer(who) then
		return ctx.states[who]
	end
	return bots and bots.stateOf(who)
end

-- 알림은 사람에게만
local function notify(kind: string, who: any, ...: any)
	if isPlayer(who) and who.Parent then
		ctx.net.fire(kind, who, ...)
	end
end

local function busy(who: any): boolean
	return isPlayer(who) and inRaid(who)
end

-- 플롯 안(수평)에 있는가: 트레이 안쪽(halfW = 트레이 폭/2) 또는 플롯 땅 전체(halfW = 땅 폭/2)
local function inside(st: any, pos: Vector3, halfW: number): boolean
	local off = pos - st.plot.center
	return math.abs(off.X) <= halfW and math.abs(off.Z) <= halfW and off.Y > -6 and off.Y < 60
end

function Steal.regen(data: { [string]: any })
	if data.stealAt == 0 then
		data.stealAt = os.time()
	end
	data.stealFree, data.stealAt =
		Economy.shuffleRegen(data.stealFree, data.stealAt, os.time(), Economy.STEAL_INTERVAL, Economy.STEAL_FREE_CAP)
end

function Steal.snapshot(data: { [string]: any }, product: number?): { [string]: any }
	Steal.regen(data)
	return {
		free = data.stealFree,
		paid = data.stealPaid,
		cap = Economy.STEAL_FREE_CAP,
		nextIn = if data.stealFree < Economy.STEAL_FREE_CAP
			then math.max(0, data.stealAt + Economy.STEAL_INTERVAL - os.time())
			else nil,
		product = product,
		pack = Economy.STEAL_PACK,
	}
end

function Steal.isCarrying(who: any): boolean
	return carrying[who] ~= nil
end

-- 걷기 속도: 배트 탭 MOVE SPEED 강화, 들고 있으면 Economy.carrySpeed
function Steal.applySpeed(player: any)
	local st = stateOf(player)
	local _, hum = rootOf(player)
	if not st or not hum then
		return
	end
	if not isPlayer(player) then
		-- 봇: 기본 걷기 16, 들면 사람과 같은 공식으로 느려짐
		local c = carrying[player]
		hum.WalkSpeed = if c then Economy.carrySpeed(16, c.tier, st.data.stats.best) else 16
		return
	end
	local lv = if st.data.bat then st.data.bat.move or 0 else 0
	local walk = Economy.moveSpeed(lv) * (1 + RaidRules.effect(st.data.boss, "speed")) -- 보스 코인 강화
	local c = carrying[player]
	hum.WalkSpeed = if c then Economy.carrySpeed(walk, c.tier, st.data.stats.best) else walk
end

local function restoreSpeed(c: Carry)
	local _, hum = rootOf(c.thief)
	if hum then
		hum.JumpHeight = c.jump
	end
	Steal.applySpeed(c.thief)
end

-- 끝: 주인에게 돌려주거나(back = true) 도둑 것으로 확정
-- 연속 털림 보호 (Economy.STEAL_LOCK_*): 사람 주인만. 잠기면 플롯 속성 StealLockUntil(서버 시각)로 모두에게 보인다
local robbedAt: { [Player]: { number } } = {}
local lockUntil: { [Player]: number } = {}
function Steal.isLocked(owner: any): boolean
	return isPlayer(owner) and os.clock() < (lockUntil[owner] or 0)
end
local function onRobbed(owner: Player, ownerSt: any)
	local now = os.clock()
	local list = robbedAt[owner] or {}
	robbedAt[owner] = list
	table.insert(list, now)
	while list[1] and now - list[1] > Economy.STEAL_LOCK_WINDOW do
		table.remove(list, 1)
	end
	if #list >= Economy.STEAL_LOCK_COUNT then
		table.clear(list)
		lockUntil[owner] = now + Economy.STEAL_LOCK_SECONDS
		ownerSt.plot.model:SetAttribute("StealLockUntil", workspace:GetServerTimeNow() + Economy.STEAL_LOCK_SECONDS)
		ctx.net.fire("Fx", owner, "shield", Economy.STEAL_LOCK_SECONDS)
	end
end
Players.PlayerRemoving:Connect(function(p)
	robbedAt[p] = nil
	lockUntil[p] = nil
end)

local function finish(c: Carry, back: boolean, why: string, by: any?)
	if carrying[c.thief] ~= c then
		return
	end
	carrying[c.thief] = nil
	local partPos = c.part.Position
	c.part:Destroy()
	restoreSpeed(c)
	local thiefSt = stateOf(c.thief)
	local ownerHere = stateOf(c.owner) == c.ownerSt
	if back then
		if ownerHere then
			local cube = ctx.spawnCube(c.ownerSt, c.tier, ctx.trayPoint(c.ownerSt, 0, 0), c.variant)
			c.ownerSt.data.stats.drops -= 1 -- 투하 통계에서 빼기
			c.ownerSt.cubes:setVelocity(cube, Vector3.zero)
			if why ~= "knock" then
				notify("Toast", c.owner, Strings.msg("steal.back", { tier = c.tier }))
			end
		end
		-- 도둑 잡음 (2026-10-25 사용자 "도둑 잡았을 때 효과"): 때린 사람과 주인에게 큰 연출
		if why == "knock" then
			local thiefName = if isPlayer(c.thief)
				then c.thief.DisplayName
				else `{c.thief:GetAttribute("BotName")} (Bot)`
			local at = partPos
			if by ~= nil and isPlayer(by) then
				ctx.net.fire("Fx", by, "caught", c.tier, thiefName, at, by == c.owner)
			end
			if ownerHere and by ~= c.owner then
				local byName = if by ~= nil and isPlayer(by)
					then by.DisplayName
					elseif by ~= nil then `{by:GetAttribute("BotName")} (Bot)`
					else "Someone"
				notify("Fx", c.owner, "caughtFor", c.tier, byName)
			end
		end
		notify(
			"Toast",
			c.thief,
			if why == "knock" then "You got hit and dropped the cube!" else "The cube went back home"
		)
	else
		if thiefSt then
			local cube = ctx.spawnCube(thiefSt, c.tier, ctx.trayPoint(thiefSt, 0, 0), c.variant)
			thiefSt.data.stats.drops -= 1
			if isPlayer(c.thief) then
				-- 훔친 큐브도 도감(변이 발견·젬)에 올린다. 최고 단계(stats.best)는 합체로만 (2026-10-19)
				ctx.onVariant(thiefSt, cube, "steal")
				ctx.net.fire("Fx", c.thief, "stealDone", c.tier)
				pcall(function()
					AnalyticsService:LogCustomEvent(c.thief, "StealDelivered", c.tier)
				end)
			end
		end
		local name = if isPlayer(c.thief) then c.thief.DisplayName else c.thief:GetAttribute("BotName")
		notify("Toast", c.owner, Strings.msg("steal.gotAway", { name = name, tier = c.tier }))
		if isPlayer(c.owner) and ownerHere then
			onRobbed(c.owner, c.ownerSt)
		end
	end
	notify("Fx", c.owner, "stealEnd", c.thief)
	notify("Fx", c.thief, "carryEnd")
	if thiefSt and isPlayer(c.thief) then
		ctx.push(thiefSt)
	end
end

local function nearPad(pos: Vector3): boolean
	for _, ost in ctx.states do
		for _, name in { "JumpPadIn", "JumpPadOut" } do
			local pad = ost.plot.model:FindFirstChild(name) :: BasePart?
			if pad and ((pad.Position - pos) * Vector3.new(1, 0, 1)).Magnitude <= PAD_NEAR then
				return true
			end
		end
	end
	return false
end

-- 훔칠 수 있는 근처 큐브 (가까운 순, 최대 STEAL_LIST개). 최고 등급·공개 연출 중인 큐브·내 상한보다 높은 큐브 제외
-- 털 수 있는 공장: 사람 + 봇
local function victimsOf(): { any }
	local list = {}
	for _, ost in ctx.states do
		table.insert(list, ost)
	end
	if bots then
		for _, bst in bots.states() do
			table.insert(list, bst)
		end
	end
	return list
end

local function candidates(player: any): (any, { any }, string?)
	local st = stateOf(player)
	local root, hum = rootOf(player)
	if not st or not root or not hum then
		return nil, {}, "dead"
	end
	if carrying[player] then
		return nil, {}, "carrying"
	end
	-- 남의 트레이 안에 있어야 한다
	local victim: any = nil
	for _, ost in victimsOf() do
		-- 봇은 봇 공장을 털지 않는다
		local skip = (ost.player == player and not debugSelf) or (not isPlayer(player) and not isPlayer(ost.player))
		if not skip and inside(ost, root.Position, ost.plot.width / 2 + 1) then
			victim = ost
			break
		end
	end
	if not victim then
		return nil, {}, "notInside"
	end
	if busy(victim.player) or busy(player) then
		return victim, {}, "raid"
	end
	if Steal.isLocked(victim.player) and not debugSelf then
		return victim, {}, "locked"
	end
	if not debugSelf and victim.data.rebirths == 0 and st.data.rebirths > 0 then
		return victim, {}, "newbie"
	end
	if isPlayer(player) then
		Steal.regen(st.data)
		if st.data.stealFree <= 0 and st.data.stealPaid <= 0 then
			return nil, {}, "empty"
		end
	end
	local tiers: { number } = {}
	local cubes = victim.cubes
	for _, cube in cubes:ids() do
		table.insert(tiers, cubes:tier(cube))
	end
	local top = Economy.stealProtectedFrom(tiers) -- 상위 2개 등급은 보호
	local cap = Economy.tierCeiling(st.data.rebirths)
	local list = {}
	local topNear, highNear = false, false
	local now = os.clock()
	for _, cube in cubes:ids() do
		local reveal = cubes:revealUntil(cube)
		if reveal and now < reveal then
			continue
		end
		local d = (cubes:position(cube) - root.Position).Magnitude - cubes:size(cube) / 2
		if d > Economy.STEAL_PICK_RANGE then
			continue
		end
		local tier = cubes:tier(cube)
		if tier >= top then
			topNear = true
			continue
		end
		if tier > cap then
			highNear = true
			continue
		end
		table.insert(list, { cube = cube, d = d, victim = victim })
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	while #list > Economy.STEAL_LIST do
		table.remove(list)
	end
	if #list == 0 then
		return victim, list, if highNear then "tooHigh" elseif topNear then "top" else "far"
	end
	return victim, list, nil
end

-- 목록: { ok, why?, cubes = { { id, pos, tier, variant, slow } } } (등급 높은 순)
-- id = 큐브 id (클라이언트는 그 플롯 Cubes 폴더에서 CubeId 속성으로 파트를 찾아 외곽선), pos = 월드 위치
local function onList(player: Player): { [string]: any }
	local _, list, why = candidates(player)
	if why then
		return { ok = false, why = why }
	end
	local st = ctx.states[player]
	local out = {}
	for _, e in list do
		local cubes = e.victim.cubes
		local tier = cubes:tier(e.cube)
		table.insert(out, {
			id = e.cube,
			pos = cubes:position(e.cube),
			tier = tier,
			variant = Economy.VARIANTS[cubes:variant(e.cube)].id,
			slow = Economy.carrySlow(tier, st.data.stats.best),
		})
	end
	table.sort(out, function(a, b)
		return a.tier > b.tier
	end)
	return { ok = true, cubes = out }
end

local function onSteal(player: any, target: number): (boolean, string?)
	local victim, list, why = candidates(player)
	if why then
		return false, why
	end
	local best: number? = nil
	for _, e in list do
		if e.cube == target then -- 지금도 훔칠 수 있는 목록 안의 id만 (Net이 숫자인지는 확인함)
			best = e.cube
			break
		end
	end
	if not best then
		return false, "gone"
	end
	local st = stateOf(player)
	local data = st.data
	local root, hum = rootOf(player)
	if not root or not hum then
		return false, "dead"
	end
	local now = os.clock()
	-- 봇은 횟수 없음 (빈도는 server/Bots가 조절)
	if isPlayer(player) then
		if data.stealFree > 0 then
			data.stealFree -= 1
		else
			data.stealPaid -= 1
		end
	end
	-- 주인 트레이에서 빼서 머리 위에 붙인다. 가까운 3인칭 카메라를 가리지 않게 최대 2.6칸 크기로.
	-- PartBackend면 그 파트를 떼어 받고, 데이터 큐브(SimBackend)면 같은 겉모습의 서버 파트를 새로 만든다 (사람당 최대 1개)
	local bestTier = victim.cubes:tier(best)
	local bestVariant = victim.cubes:variant(best)
	local part = victim.cubes:release(best)
		or CubeStyle.part(bestTier, bestVariant, false, root.CFrame * CFrame.new(0, 4, 0))
	part.Parent = workspace
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	local s = math.min(part.Size.X, 2.6)
	part.Size = Vector3.new(s, s, s)
	part.CFrame = root.CFrame * CFrame.new(0, 2.6 + s / 2, 0.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	-- 트레이 밖 파트라 client/CubeLook이 이 태그로 얼굴·등급 숫자를 붙인다 (Tier 속성은 CubeStyle이 달았다)
	game:GetService("CollectionService"):AddTag(part, "CarriedCube")
	-- 최소 운반 시간: 내 플롯 가장자리까지 직선거리 ÷ 들고 걷는 속도 × MIN_CARRY_SHARE
	local walk = Economy.moveSpeed(if data.bat then data.bat.move or 0 else 0)
	local speed = Economy.carrySpeed(walk, bestTier, data.stats.best)
	local toHome = ((st.plot.center - root.Position) * Vector3.new(1, 0, 1)).Magnitude - Config.PLATFORM_SIZE.X / 2
	local c: Carry = {
		thief = player,
		owner = victim.player,
		ownerSt = victim,
		tier = bestTier,
		variant = bestVariant,
		part = part,
		root = root,
		since = now,
		jump = hum.JumpHeight,
		lastPos = root.Position,
		padUntil = 0,
		minHome = now + math.max(0, toHome) / math.max(1, speed) * MIN_CARRY_SHARE,
	}
	carrying[player] = c
	Steal.applySpeed(player)
	hum.JumpHeight = Economy.CARRY_JUMP
	notify("Fx", victim.player, "stolen", player, bestTier, Economy.VARIANTS[bestVariant].id)
	if isPlayer(player) then
		ctx.net.fire("Fx", player, "carry", bestTier, Economy.CARRY_TIMEOUT, bestTier > data.stats.best)
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "StealStarted", bestTier)
		end)
		ctx.push(st)
		if bots and not isPlayer(victim.player) then
			bots.onStolen(victim, player)
		end
	end
	return true, nil
end

-- 넉백 저항: 오라 단계 + 보스 코인 강화 (곱으로 합침, 최대 80%)
function Steal.resist(data: { [string]: any }): number
	return RaidRules.combineResist(Economy.auraResist(Collection.auraTier(data)), RaidRules.effect(data.boss, "resist"))
end

-- 배트에 맞은 다른 플레이어를 날린다 (Factory.onSwing에서 부름). 들고 있던 큐브는 주인에게 돌아감
-- attacker = 사람 또는 봇. only가 있으면 그 대상만 (봇은 쫓던 도둑만 친다)
function Steal.batHit(attacker: any, root: BasePart, range: number, power: number, look: Vector3, only: any?): number
	local hits = 0
	local now = os.clock()
	local targets: { any } = Players:GetPlayers()
	if bots and isPlayer(attacker) then
		for _, broot in bots.roots() do
			table.insert(targets, broot.Parent)
		end
	end
	for _, other in targets do
		if other == attacker or busy(other) or busy(attacker) or (only ~= nil and other ~= only) then
			continue
		end
		local oroot = rootOf(other)
		if not oroot then
			continue
		end
		local off = oroot.Position - root.Position
		if off.Magnitude > range + 2 then
			continue
		end
		local flat = off * Vector3.new(1, 0, 1)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else look
		if dir:Dot(look) < 0.1 and off.Magnitude > 4 then
			continue
		end
		if now - (knockedAt[other] or 0) < Economy.KNOCK_IMMUNE then
			continue
		end
		knockedAt[other] = now
		hits += 1
		-- 캐릭터는 그 플레이어 클라이언트가 물리 주인이라 그쪽에서 속도를 준다
		local v = (dir + look).Unit * (power * 1.1) + Vector3.new(0, 32, 0)
		-- 높은 단계 오라를 낀 사람은 덜 날아간다 (2026-10-19, 단계마다 5%, 최대 60%)
		if isPlayer(other) then
			local ost = ctx.states[other]
			if ost then
				v *= 1 - Steal.resist(ost.data)
			end
			ctx.net.fire("Fx", other, "knock", v, attacker)
		elseif bots then
			bots.knock(other, v)
		end
		local c = carrying[other]
		if c then
			finish(c, true, "knock", attacker)
		end
	end
	return hits
end

-- 봇용 (server/Bots): 지금 서 있는 트레이에서 훔칠 수 있는 큐브 { cube, tier }
function Steal.botCandidates(bot: Model): { { cube: number, tier: number } }
	local victim, list, why = candidates(bot)
	if why or not victim then
		return {}
	end
	local out = {}
	for _, e in list do
		table.insert(out, { cube = e.cube, tier = victim.cubes:tier(e.cube) })
	end
	return out
end

function Steal.botSteal(bot: Model, cube: number): boolean
	local ok = onSteal(bot, cube)
	return ok
end

-- 사람 공장 상태 (봇이 털 대상을 고른다)
function Steal.playerStates(): { [Player]: any }
	return ctx.states
end

function Steal.inRaid(who: any): boolean
	return busy(who)
end

-- Studio 디버그 (init.server StudioDebug에서만)
function Steal.debug(player: Player, cmd: string)
	if cmd == "self" then
		debugSelf = true
	elseif cmd == "knock" then
		ctx.net.fire("Fx", player, "knock", Vector3.new(50, 32, 0), player)
	end
end

function Steal.onLeave(player: any)
	local c = carrying[player]
	if c then
		finish(c, true, "leave")
	end
	knockedAt[player] = nil
end

function Steal.init(context: Ctx)
	ctx = context
	ctx.net.on("Steal", onSteal)
	ctx.net.on("StealList", onList)
	Players.PlayerRemoving:Connect(Steal.onLeave)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()
		for thief, c in carrying do
			local root, hum = rootOf(thief)
			if not root or root ~= c.root or not c.part.Parent then
				finish(c, true, "dead")
			elseif now - c.since > Economy.CARRY_TIMEOUT then
				finish(c, true, "timeout")
			else
				-- 이동 거리 확인: 걷기 속도의 1.6배 + 여유. 점프 패드를 밟은 직후엔 비행 속도까지 허용
				local pos = root.Position
				local moved = ((pos - c.lastPos) * Vector3.new(1, 0, 1)).Magnitude
				if nearPad(c.lastPos) or nearPad(pos) then
					c.padUntil = now + PAD_WINDOW
				end
				local walk = if hum then hum.WalkSpeed else 16
				local limit = (if now < c.padUntil then math.max(PAD_SPEED, walk) else walk * 1.6) * step + 4
				c.lastPos = pos
				if moved > limit and not debugSelf and isPlayer(thief) then
					finish(c, true, "teleport")
					continue
				end
				local mine = stateOf(thief)
				local home = if debugSelf
					then (pos * Vector3.new(1, 0, 1)).Magnitude < 30
					else mine and inside(mine, pos, Config.PLATFORM_SIZE.X / 2)
				if home and now >= c.minHome then
					finish(c, false, "home")
				end
			end
		end
	end)
end

return Steal
