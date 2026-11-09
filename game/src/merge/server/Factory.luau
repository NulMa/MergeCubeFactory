--!strict
-- 플레이어별 공장: 드로퍼 투하, 서버 물리 합치기, 수입, 코어 부화, 업그레이드, 리버스, 오프라인 수익.
-- 모든 재화 변경은 Ledger 경유 (docs/06 §1). 공식은 shared/Economy (docs/13 시뮬레이션과 동일).

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local AssetIds = require(Shared.AssetIds)
local Shop = require(Shared.Shop)
local Strings = require(Shared.Strings) -- 화면 글자는 번역 키로 보낸다 (client/Loc)
local CoreServer = game:GetService("ServerScriptService").CoreServer
local Ledger = require(CoreServer.Ledger)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Plots = require(script.Parent.Plots)
local Events = require(script.Parent.Events) -- 황금 큐브·피버·알림 (docs/17)
local Collection = require(script.Parent.Collection)
local Steal = require(script.Parent.Steal) -- 큐브 훔치기·배트 넉백 (docs/22)
local Daily = require(script.Parent.Daily) -- 접속 선물·일일 퀘스트 (docs/23)
local PetsServer = require(script.Parent.Pets) -- 펫 뽑기·장착·합성 (docs/24)
local Raid = require(script.Parent.Raid) -- 보스 레이드·보스 코인 강화 (docs/25)
local Friends = require(CoreServer.Friends)
local CubeWorld = require(script.Parent.CubeWorld) -- 플롯별 큐브 저장소 (docs/27)
local SimBackend = require(script.Parent.SimBackend) -- 데이터 큐브 (Config.DATA_CUBES, docs/27 단계 4)
local CubeCodec = require(Shared.CubeCodec) -- 제거 사유 (클라이언트 연출 구분)
local TraySim = require(Shared.TraySim) -- 데이터 큐브 자석 깡충 높이 (hopVelocity)
local Online = require(game:GetService("ReplicatedStorage").Core.Online) -- 접속 중 가속: 연속 보너스·콤보 현금·부화 2배

type Cube = number -- 큐브 id (server/CubeWorld 엔티티)
type State = {
	player: Player,
	data: { [string]: any },
	plot: Plots.Plot,
	cubes: CubeWorld.World, -- 이 플롯의 큐브들 (id + 컴포넌트 열, docs/27)
	dropTimers: { number },
	lastManual: number,
	combo: number,
	comboAt: number,
	comboRecordShown: boolean, -- 이번 연쇄에서 "최고 콤보" 기록 알림을 이미 띄웠나
	income: number,
	pendingTray: { any }, -- 아직 다시 떨어뜨리지 않은 저장 큐브 (복원 중 저장해도 잃지 않게)
	baseIncome: number, -- 일시 버프(프렌지·피버·러시·팀) 뺀 수입: 오프라인·현금 상품·보상·랭킹용
	luck: number, -- 변이 확률 배율 (Studio 디버그 전용, 기본 1)
	lastSwing: number,
	ceilingHintAt: number,
	joinedAt: number, -- 이번 접속 시작 (os.clock, 온라인 연속 보너스)
	comboCash: number, -- 이번 연쇄에서 쌓인 콤보 현금 (연쇄가 끝나면 지급)
}

local Factory = {}
local giveBat: (Player) -> ()

local states: { [Player]: State } = {}
local net: any = nil -- core Net 서버 객체 (init에서 받음)

local FTUE = { "loaded", "first_merge", "first_purchase", "first_core", "first_hatch", "first_rebirth" }

local function ftue(st: State, step: number)
	local data = st.data
	if (data.ftue or 0) >= step then
		return
	end
	data.ftue = step
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(st.player, step, FTUE[step])
	end)
end

local function upg(st: State, id: string): number
	return st.data.upgrades[id] or 0
end

-- 영구 배수: 리버스·코어 보너스·패스·광택·펫 (오프라인 수입·현금 상품·코어·선물·랭킹은 이것만 쓴다)
local function baseMult(st: State): number
	local studio = if RunService:IsStudio() then Config.STUDIO_CASH_MULT else 1
	-- 2x Cash 패스 (data.passes는 server/Shop이 접속·구매 때 채움)
	local pass = if st.data.passes.cash2x then 2 else 1
	return Economy.multiplier(st.data.rebirths, st.data.coreBonus, pass)
		* Economy.polishMult(upg(st, "polish"))
		* (1 + PetsServer.bonus(st.data)) -- 장착 펫 % (docs/24)
		* Raid.incomeMult(st.data) -- 보스 코인 수입 강화 (docs/25)
		* studio
end

-- 친구 보너스 (2026-10-20): 같은 공장에 함께 있는 친구 수 (주인·방문자 모두)
local function friendsHere(st: State): number
	return Plots.friendsTogether(st.player, Friends.are)
end

local function onlineSeconds(st: State): number
	return os.clock() - st.joinedAt
end

-- 지금 버는 배수 = 영구 배수 × 일시 버프(리버스 러시·친구·온라인 연속·프렌지·피버·레이드 승리)
-- (2026-10-20 리뷰: 버프가 낀 수입이 오프라인·Cash 상품·코어·랭킹에 복사돼 Flash Frenzy 뒤 Cash Vault가 5배가 되던 문제)
local function mult(st: State): number
	local team = Config.TEAM_BONUS[math.min(friendsHere(st), 3)] or 0
	return baseMult(st)
		* Economy.rushMult(st.data.rebirths, st.data.runBest or st.data.stats.best) -- 리버스 러시
		* (1 + team)
		* (1 + Online.streakBonus(onlineSeconds(st)))
		* Events.mult(st)
		* Raid.buffMult(st.data) -- 레이드 승리 x2 (참여자만)
end

-- st.income(지금 버는 것)과 st.baseIncome(버프 뺀 것)을 함께 갱신
local function refreshIncome(st: State)
	local sum = 0
	for _, id in st.cubes:ids() do
		sum += Economy.cubeValue(st.cubes:tier(id), st.cubes:variant(id))
	end
	st.income = sum * mult(st)
	st.baseIncome = sum * baseMult(st)
end

local function spawnCube(st: State, tier: number, position: Vector3, variant: number?): Cube
	local id = st.cubes:spawn(tier, position, variant)
	st.data.stats.drops += 1
	return id
end

-- 개인 기록 (docs/18 §3): 깨질 때만 크게 알린다. 기준이 계속 올라가서 무뎌지지 않음
local function record(st: State, text: string | Strings.Msg, delay: number?)
	task.delay(delay or 0, function()
		if states[st.player] == st then
			net.fire("Fx", st.player, "record", text)
		end
	end)
end

-- 지금까지 본 가장 드문 변이 갱신 (변이 연출이 끝난 뒤 이어서)
local function recordVariant(st: State, variant: number, how: string)
	local rec = st.data.records
	if how == "keep" or variant <= rec.variant then
		return
	end
	local first = rec.variant <= Economy.NORMAL + 1 -- 첫 메탈릭은 이미 큰 일이 아님
	rec.variant = variant
	if not first then
		record(st, Strings.msg("record.rarest", { variant = string.upper(Economy.VARIANTS[variant].id) }), 1.4)
	end
end

-- 변이가 생김: 도감 기록(첫 발견 젬) + 연출. how = "drop" | "roll" | "fusion" | "keep" | "steal"
-- "steal"(훔쳐서 집에 가져옴, docs/22): 도감·젬은 인정, 최고 단계는 합체로만 오르므로 여기서 건드리지 않는다.
-- "keep"(이어받으며 한 단계 약해진 것)은 새 발견일 때만 알린다. 맨 위 두 변이(Cosmic·Divine)는 서버 전체에 토스트.
local function announceVariant(st: State, tier: number, variant: number, at: Vector3, how: string)
	if variant == Economy.NORMAL then
		return
	end
	local data = st.data
	local isNew, gems, milestoneNow = Collection.discover(st.player, data, tier, variant)
	if how == "keep" and not isNew then
		return
	end
	local id = Economy.VARIANTS[variant].id
	net.fire("Fx", st.player, "variant", at, tier, id, how, isNew, gems)
	if milestoneNow then
		local m = Economy.CODEX_MILESTONES[data.codexMilestone + 1]
		net.fire("Fx", st.player, "codex", Strings.msg("codex.milestoneFx", { gems = m.gems }), 0)
	end
	recordVariant(st, variant, how)
	if how ~= "keep" then
		Daily.progress(data, "variant")
	end
	if how ~= "keep" and how ~= "steal" and variant >= Economy.TOAST_VARIANT then
		net.fireAll(
			"Toast",
			Strings.msg("toast.foundVariant", { name = st.player.DisplayName, variant = string.upper(id), tier = tier })
		)
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(st.player, "VariantFound", variant, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = id,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = how,
		})
	end)
end

-- 큐브 id로 부르는 쪽 (훔치기·투하): 지금 등급·변이·위치로 알린다
local function onVariant(st: State, cube: Cube, how: string)
	local cubes = st.cubes
	announceVariant(st, cubes:tier(cube), cubes:variant(cube), cubes:position(cube), how)
end

-- 드문 변이(Rainbow 이상)는 바로 보여 주지 않는다: 큐브를 잠깐 일반 모습으로 두고 '두근' 연출 뒤 공개 (docs/18 §5).
-- 결과는 이미 정해져 있고 보여 주는 순간만 늦춘다(수입·도감은 즉시 반영). 공개 중엔 합쳐지지 않음.
local REVEAL_SECONDS = 1.2 -- client Fx.reveal 길이와 맞춤
local OMEN_SECONDS = 0.9 -- 투하 전 드로퍼 예고 (client Fx.omen)
local function revealFrom(): number
	return Economy.variantIndex("Rainbow")
end
-- 예고·두근 연출은 도감에 아직 없는 변이만 (이미 찾은 것은 바로 보여 줌, 2026-10-19 사용자 요청)
local function suspense(st: State, tier: number, v: number): boolean
	return v >= revealFrom() and not st.data.variants[Economy.codexKey(tier, v)]
end
local function revealVariant(st: State, cube: Cube, how: string)
	local cubes = st.cubes
	local v = cubes:variant(cube)
	local tier = cubes:tier(cube)
	local at = cubes:position(cube) -- 연출 중에 사라져도(팔림·리버스) 마지막 자리에서 알린다
	cubes:setRevealUntil(cube, os.clock() + REVEAL_SECONDS)
	cubes:look(cube, Economy.NORMAL)
	-- 큐브 id를 보낸다: 클라이언트가 내 Cubes 폴더에서 CubeId 속성으로 파트를 찾아 빛기둥을 따라 붙인다
	net.fire("Fx", st.player, "reveal", at, tier, Economy.VARIANTS[v].id, cube)
	task.delay(REVEAL_SECONDS, function()
		if cubes:has(cube) then
			cubes:setRevealUntil(cube, nil)
			if cubes:alive(cube) and cubes:variant(cube) == v then
				cubes:look(cube, v)
			end
			announceVariant(st, cubes:tier(cube), cubes:variant(cube), cubes:position(cube), how)
		else
			announceVariant(st, tier, v, at, how)
		end
	end)
end

-- 변이 행운: Studio 배율 × 낮은 등급 보정(드로퍼 최저 등급보다 낮은 큐브, Economy.lowTierLuck)
local function luckFor(st: State, tier: number): number
	local low = math.huge
	for _, d in st.data.droppers do
		low = math.min(low, d.tier)
	end
	return st.luck * Economy.lowTierLuck(tier, if low == math.huge then 1 else low)
end

-- 드로퍼·DROP 투하: 낮은 확률로 변이 (Economy.VARIANTS dropChance)
local function dropCube(st: State, tier: number, position: Vector3)
	local v = Economy.rollVariant(math.random(), true, luckFor(st, tier))
	if suspense(st, tier, v) then
		-- 드문 변이: 드로퍼가 먼저 떨리며 빛나고(예고) 조금 뒤 떨어진 다음 공개
		net.fire("Fx", st.player, "omen", position, Economy.VARIANTS[v].id)
		task.delay(OMEN_SECONDS, function()
			if states[st.player] == st then
				revealVariant(st, spawnCube(st, tier, position, v), "drop")
			end
		end)
		return
	end
	local cube = spawnCube(st, tier, position, v)
	if v ~= Economy.NORMAL then
		onVariant(st, cube, "drop")
	end
end

-- reason = CubeCodec.REASON_* (합치기·팔기·기타)
-- 데이터 큐브: 자석 깡충 횟수. 회전 없는 간이 물리라 사이에 낀 큐브에 계속 막히는 짝이 생긴다(Studio 2026-10-22).
-- 둘 다 HOP_GIVE_UP번 넘게 뛰고도 못 만나면 거리와 상관없이 결과로 합친다 (데이터 지향: 결과만 서버가 정함, docs/27)
local HOP_GIVE_UP = 3
local hopTries: { [any]: { [Cube]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function hopsOf(cubes: CubeWorld.World): { [Cube]: number }
	local t = hopTries[cubes]
	if not t then
		t = {}
		hopTries[cubes] = t
	end
	return t
end

local function removeCube(st: State, cube: Cube, reason: number)
	hopsOf(st.cubes)[cube] = nil
	st.cubes:remove(cube, reason)
end

local function trayPoint(st: State, x: number, z: number): Vector3
	local half = Config.TRAY_SIZE.X / 2 * 0.8
	return st.plot.center + Vector3.new(x * half, Config.DROP_HEIGHT, z * half)
end

local function refreshDroppers(st: State)
	for i, p in st.plot.dropperParts do
		local d = st.data.droppers[i]
		p.Transparency = if d then 0 else 0.8
		p.Color = if d then Config.TIER_COLORS[d.tier] else Color3.fromRGB(90, 90, 110)
	end
end

local function startCores(st: State)
	local data = st.data
	while #data.hatching < data.incubators and #data.coreQueue > 0 do
		local tier = table.remove(data.coreQueue, 1) :: number
		local scale = Economy.hatchScale(upg(st, "hatch"))
		local seconds = math.ceil(Economy.CORES[tier].seconds * scale)
		table.insert(data.hatching, {
			tier = tier,
			endsAt = os.time() + seconds,
			duration = seconds, -- 진행 막대용 (예전 저장분엔 없음 → CORES 기본 시간)
			payout = Economy.corePayout(st.baseIncome, tier, scale), -- 시뮬과 같음 (상한 CORE_PAYOUT_CAP초치)
		})
		-- 부화 중인 게 없을 때 산 Instant Hatch는 다음 코어에 쓴다 (Factory.finishHatch)
		if (data.hatchCredit or 0) > 0 then
			data.hatchCredit -= 1
			data.hatching[#data.hatching].endsAt = os.time()
		end
		ftue(st, 4)
	end
end

local function addCore(st: State, tier: number, at: Vector3)
	if #st.data.coreQueue >= Economy.CORE_QUEUE_CAP then
		Ledger.credit(st.player, "cash", st.baseIncome * Economy.CORE_SELL_SECONDS, "Gameplay", "core_overflow", false)
		return
	end
	table.insert(st.data.coreQueue, tier)
	startCores(st)
	net.fire("Fx", st.player, "core", at, Economy.CORES[tier].name)
end

-- 병합 연출 이벤트는 주인과 근처(MERGE_FX_RANGE) 사람에게만 보낸다 (2026-10-19 다인 최적화).
-- 8인 서버에서 모든 병합을 모두에게 보내면 클라이언트마다 이벤트·연출이 8배가 된다
local MERGE_FX_RANGE = 170
local function fireMergedNear(owner: any, at: Vector3, ...: any)
	for _, pl in game:GetService("Players"):GetPlayers() do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pl == owner or (root and (root.Position - at).Magnitude < MERGE_FX_RANGE) then
			net.fire("Merged", pl, at, ...)
		end
	end
end
local function fireMerged(st: State, at: Vector3, ...: any)
	fireMergedNear(st.player, at, ...)
end

local function resting(cubes: CubeWorld.World, cube: Cube): boolean
	return cubes:velocity(cube).Magnitude < Config.magnetRest(cubes:tier(cube))
end

-- 데이터 큐브(TraySim)용 자석 깡충: 회전이 없어 사이에 낀 큐브를 넘지 못하므로(Studio 2026-10-21 "같은 등급이 안 합쳐짐")
-- 지나는 길의 가장 높은 큐브 윗면을 넘게 뛴다. 움직이는 큐브는 뛰는 큐브 높이에 내려앉는다고 보고 잰다. 계산은 TraySim.hopVelocity
local function hopOver(cubes: CubeWorld.World, from: Cube, to: Cube): Vector3
	local a, b = cubes:position(from), cubes:position(to)
	local fh = cubes:size(from) / 2
	local others: { number } = {}
	local mid = (a + b) / 2
	for _, id in cubes:query(mid, (b - a).Magnitude / 2 + Config.CUBE_SIZE_MAX * 2) do
		if id ~= from and id ~= to then
			local p = cubes:position(id)
			local ch = cubes:size(id) / 2
			local top = if cubes:velocity(id).Magnitude < 2 then p.Y + ch else a.Y - fh + ch * 2
			table.insert(others, p.X)
			table.insert(others, p.Z)
			table.insert(others, ch)
			table.insert(others, top)
		end
	end
	local vx, vy, vz = TraySim.hopVelocity(a.X, a.Y, a.Z, fh, b.X, b.Z, others, Config.MAGNET_HOP, workspace.Gravity)
	return Vector3.new(vx, vy, vz)
end

-- 자석: 드로퍼 자리가 고정이라 같은 등급끼리 살짝 떨어져 멈추면 영영 못 합쳐진다(플레이테스트 2026-10-17).
-- 멈춰 있는 같은 등급 두 개를 서로를 향해 깡충 뛰게 한다. 둘 다 움직여 가운데서 부딪힘.
local function magnet(cubes: CubeWorld.World, list: { Cube }, used: { [Cube]: boolean }, now: number)
	local free: { Cube } = {}
	for _, c in list do
		if
			not used[c]
			and cubes:alive(c)
			and resting(cubes, c)
			and now - cubes:nudged(c) >= Config.magnetInterval(cubes:tier(c))
		then
			table.insert(free, c)
		end
	end
	local taken: { [Cube]: boolean } = {}
	for _, a in free do
		if taken[a] then
			continue
		end
		local best: Cube? = nil
		local bestDist = math.huge
		for _, b in free do
			if b ~= a and not taken[b] then
				local dist = (cubes:position(a) - cubes:position(b)).Magnitude
				if dist < bestDist then
					best, bestDist = b, dist
				end
			end
		end
		if best then
			taken[a], taken[best] = true, true
			for _, pair in { { a, best }, { best, a } } do
				local from, to = pair[1], pair[2]
				local delta = cubes:position(to) - cubes:position(from)
				local flat = Vector3.new(delta.X, 0, delta.Z)
				if flat.Magnitude > 0.01 and Config.DATA_CUBES then
					cubes:setVelocity(from, hopOver(cubes, from, to))
				elseif flat.Magnitude > 0.01 then
					-- 반씩 다가가도록 수평 속도 + 짧은 점프 (공중 시간 ≈ 2 × 상승속도 / 중력)
					local air = 2 * Config.MAGNET_HOP / workspace.Gravity
					cubes:setVelocity(from, flat / 2 / air + Vector3.new(0, Config.MAGNET_HOP, 0))
				end
				cubes:setNudged(from, now)
				if Config.DATA_CUBES then
					local hops = hopsOf(cubes)
					hops[from] = (hops[from] or 0) + 1
				end
			end
		end
	end
end

local function scanMerges(st: State)
	local now = os.clock()
	local cubes = st.cubes
	local byTier: { [number]: { Cube } } = {}
	for _, cube in cubes:ids() do
		local reveal = cubes:revealUntil(cube)
		if now - cubes:born(cube) >= Config.MERGE_MIN_AGE and not (reveal and now < reveal) then
			local tier = cubes:tier(cube)
			local list = byTier[tier]
			if not list then
				list = {}
				byTier[tier] = list
			end
			table.insert(list, cube)
		end
	end
	local ceiling = Economy.tierCeiling(st.data.rebirths)
	-- 상한 등급이 둘 이상 모였는데 안 합쳐지면 이유를 알려 준다 (10분에 한 번)
	local capped = byTier[ceiling]
	if capped and #capped >= 2 and ceiling < Economy.MAX_TIER and now - st.ceilingHintAt > 600 then
		st.ceilingHintAt = now
		net.fire("Fx", st.player, "ceiling", ceiling, Economy.tierCeiling(st.data.rebirths + 1))
	end
	for tier, list in byTier do
		if #list < 2 or not Economy.canMerge(tier, tier, ceiling) then
			continue
		end
		local used: { [Cube]: boolean } = {}
		local reach = Config.cubeSize(tier) * Config.MERGE_DISTANCE
		local hops = hopsOf(cubes)
		for i = 1, #list do
			local a = list[i]
			if used[a] then
				continue
			end
			for j = i + 1, #list do
				local b = list[j]
				local gaveUp = Config.DATA_CUBES
					and (hops[a] or 0) >= HOP_GIVE_UP
					and (hops[b] or 0) >= HOP_GIVE_UP
					and resting(cubes, a)
					and resting(cubes, b)
				if used[b] or ((cubes:position(a) - cubes:position(b)).Magnitude > reach and not gaveUp) then
					continue
				end
				hops[a], hops[b] = nil, nil
				used[a], used[b] = true, true
				local lower, upper = a, b
				if cubes:position(b).Y < cubes:position(a).Y then
					lower, upper = b, a
				end
				local lowerVariant, upperVariant = cubes:variant(lower), cubes:variant(upper)
				removeCube(st, upper, CubeCodec.REASON_MERGE)
				local inherited = Economy.inheritVariant(lowerVariant, upperVariant)
				local fused = lowerVariant == upperVariant and lowerVariant ~= Economy.NORMAL
				local lucky = tier + 2 <= ceiling and math.random() < Economy.luckyChance(upg(st, "lucky"))
				local newTier = tier + (if lucky then 2 else 1)
				cubes:setBorn(lower, now)
				-- 변이: 새로 굴린 것과 이어받은 것 중 좋은 쪽 (docs/16 §2)
				local rolled = Economy.rollVariant(math.random(), false, luckFor(st, newTier))
				local newVariant = math.max(rolled, inherited)
				cubes:retier(lower, newTier, newVariant) -- 크기·색·변이 장식·MAX 표시를 다시 입힘
				-- 콤보 (1초 창)
				st.combo = if now - st.comboAt <= 1 then st.combo + 1 else 1
				st.comboAt = now
				-- 콤보 현금 (2026-10-20 "콤보 보상은 인게임 재화"): 3연쇄부터 쌓고 연쇄가 끝나면 secondTick에서 지급
				st.comboCash += (st.baseIncome or 0) * Online.comboSeconds(st.combo)
				local data = st.data
				-- 최고 콤보 기록: 연쇄 하나에 한 번만 알림 (5 이상부터)
				if st.combo == 1 then
					st.comboRecordShown = false
				end
				if st.combo > data.records.combo then
					data.records.combo = st.combo
					if st.combo >= 5 and not st.comboRecordShown then
						st.comboRecordShown = true
						record(st, "NEW BEST COMBO!")
					end
				end
				data.stats.merges += 1
				Daily.progress(data, "merge")
				PetsServer.onMerge(st.player, newTier)
				if newTier > (data.runBest or data.stats.best) then
					local wasRush = Economy.rushMult(data.rebirths, data.runBest or data.stats.best) > 1
					data.runBest = newTier
					if wasRush and Economy.rushMult(data.rebirths, newTier) == 1 then
						net.fire("Toast", st.player, "REBIRTH RUSH complete! Back to normal speed")
					end
				end
				local isBest = newTier > data.stats.best
				if isBest then
					data.stats.best = newTier
					data.codex[tostring(newTier)] = true
					pcall(function()
						AnalyticsService:LogProgressionCompleteEvent(st.player, "CubeTier", newTier, `Tier {newTier}`)
					end)
				end
				ftue(st, 2)
				if Economy.CORES[newTier] and math.random() < Economy.CORE_CHANCE then
					addCore(st, newTier, cubes:position(lower))
				end
				fireMerged(st, cubes:position(lower), newTier, st.combo, st.player, isBest)
				Events.onMerge(st, newTier, isBest, st.combo)
				if lucky then
					net.fire("Fx", st.player, "lucky", cubes:position(lower), newTier)
				end
				if newVariant ~= Economy.NORMAL then
					local how = if rolled > inherited
						then "roll"
						elseif fused and inherited == newVariant then "fusion"
						else "keep"
					if how ~= "keep" and suspense(st, newTier, newVariant) then
						revealVariant(st, lower, how)
					else
						onVariant(st, lower, how)
					end
				end
				break
			end
		end
		magnet(cubes, list, used, now)
	end
end

-- AI 플레이어 트레이 (server/Bots): 사람 트레이와 같은 접촉 합치기 + 자석 깡충 (2026-10-25 사용자 "봇 트레이 안의 큐브는 안움직이는거같은데":
-- 예전엔 멈춘 같은 등급 둘을 그 자리에서 지우고 새로 만들어 큐브가 움직이지 않았다). 보상·기록·변이·코어 없음, 근처 사람에게 연출만.
-- 돌려줌: 합친 수, 새로 만든 가장 높은 등급
function Factory.botMerge(cubes: CubeWorld.World, cap: number, owner: Model): (number, number)
	local now = os.clock()
	local byTier: { [number]: { Cube } } = {}
	for _, cube in cubes:ids() do
		local reveal = cubes:revealUntil(cube)
		if now - cubes:born(cube) >= Config.MERGE_MIN_AGE and not (reveal and now < reveal) then
			local tier = cubes:tier(cube)
			local list = byTier[tier]
			if not list then
				list = {}
				byTier[tier] = list
			end
			table.insert(list, cube)
		end
	end
	local merges, top = 0, 0
	local hops = hopsOf(cubes)
	for tier, list in byTier do
		if #list < 2 or tier >= cap then
			continue
		end
		local used: { [Cube]: boolean } = {}
		local reach = Config.cubeSize(tier) * Config.MERGE_DISTANCE
		for i = 1, #list do
			local a = list[i]
			if used[a] then
				continue
			end
			for j = i + 1, #list do
				local b = list[j]
				local gaveUp = Config.DATA_CUBES
					and (hops[a] or 0) >= HOP_GIVE_UP
					and (hops[b] or 0) >= HOP_GIVE_UP
					and resting(cubes, a)
					and resting(cubes, b)
				if used[b] or ((cubes:position(a) - cubes:position(b)).Magnitude > reach and not gaveUp) then
					continue
				end
				hops[a], hops[b] = nil, nil
				used[a], used[b] = true, true
				local lower, upper = a, b
				if cubes:position(b).Y < cubes:position(a).Y then
					lower, upper = b, a
				end
				cubes:remove(upper, CubeCodec.REASON_MERGE)
				cubes:setBorn(lower, now)
				cubes:retier(lower, tier + 1, cubes:variant(lower))
				fireMergedNear(nil, cubes:position(lower), tier + 1, 1, owner, false)
				merges += 1
				top = math.max(top, tier + 1)
				break
			end
		end
		magnet(cubes, list, used, now)
	end
	return merges, top
end

-- 한 등급 위 투하(예전 2배 투하) = 이미 한 번 합쳐진 큐브. 큐브·연출만 줄이고 합치기 보상은 그대로 굴린다
-- (2026-10-21: 합치기를 건너뛰면 코어·행운·피버·일일 퀘스트가 줄어 regular 엔드게임 26 → 31일이었다)
local function bigDropTier(st: State, tier: number, at: Vector3): number
	local ceiling = Economy.tierCeiling(st.data.rebirths)
	local lucky = tier + 2 <= ceiling and math.random() < Economy.luckyChance(upg(st, "lucky"))
	local out = tier + (if lucky then 2 else 1)
	local data = st.data
	data.stats.merges += 1
	Daily.progress(data, "merge")
	PetsServer.onMerge(st.player, out)
	Events.onMerge(st, out, false, 1)
	if Economy.CORES[out] and math.random() < Economy.CORE_CHANCE then
		addCore(st, out, at)
	end
	return out
end

local function enforceTray(st: State)
	local m = mult(st)
	-- 트레이 밖으로 나간 큐브(배트·폭발로 날아감, 물리 끼임)는 잃지 않고 트레이 위로 되돌린다.
	-- 보이지 않는 가드 벽·천장(Plots)이 1차로 막고, 이건 그래도 빠져나간 경우의 안전망
	local c = st.plot.center
	local limit = st.plot.width / 2 + Config.WALL_THICKNESS + 1
	local cubes = st.cubes
	local ids = cubes:ids()
	for i = #ids, 1, -1 do
		local cube = ids[i]
		if not cubes:alive(cube) then
			removeCube(st, cube, CubeCodec.REASON_OTHER)
			continue
		end
		local off = cubes:position(cube) - c
		if math.abs(off.X) > limit or math.abs(off.Z) > limit or off.Y < -10 or off.Y > 80 then
			cubes:setVelocity(cube, Vector3.zero)
			cubes:setAngular(cube, Vector3.zero)
			cubes:teleport(cube, trayPoint(st, math.random() * 1.2 - 0.6, math.random() * 1.2 - 0.6))
		end
	end
	while cubes:count() > Economy.trayCap(upg(st, "tray")) + Economy.TRAY_OVERFLOW do
		-- 가장 값싼 큐브(변이 배수 포함)를 판다: 낮은 등급 Rainbow가 먼저 팔리지 않게
		local lowest = ids[1]
		for _, cube in ids do
			if
				Economy.cubeValue(cubes:tier(cube), cubes:variant(cube))
				< Economy.cubeValue(cubes:tier(lowest), cubes:variant(lowest))
			then
				lowest = cube
			end
		end
		local value = Economy.sellValue(cubes:tier(lowest), m) * Economy.variantMult(cubes:variant(lowest))
		Ledger.credit(st.player, "cash", value, "Gameplay", "auto_sell", false)
		removeCube(st, lowest, CubeCodec.REASON_SELL)
	end
end

local function batLv(data: { [string]: any }, stat: string): number
	local b = data.bat
	return if b then b[stat] or 0 else 0
end

local function batSnapshot(data: { [string]: any }): { [string]: any }
	local cap = Economy.batCap(Collection.found(data))
	local out = { cap = cap, found = Collection.found(data) }
	for _, stat in Economy.BAT_STATS do
		local lv = batLv(data, stat)
		out[stat] = { lv = lv, cost = Economy.batCost(lv), locked = lv >= cap and lv < Economy.BAT_MAX }
	end
	return out
end

-- 스타터 팩 제안 (2026-10-19, "너무 자주 뜸"): 접속마다 → 24시간에 한 번, 계정당 최대 3번
local STARTER_OFFER_GAP = 24 * 3600
local STARTER_OFFER_MAX = 3
local function starterOfferReady(data: { [string]: any }): boolean
	return not data.starterBought
		and (data.starterOfferCount or 0) < STARTER_OFFER_MAX
		and os.time() - (data.starterOfferAt or 0) >= STARTER_OFFER_GAP
end

-- 반짝 특가 프렌지: 오늘 남은 횟수, 다음 구매 분, 초기화까지 초 (Shop.FLASH)
local function flashSnapshot(data: { [string]: any }): { [string]: number }
	local now = os.time()
	local day = now // 86400
	local count = if data.flashDay == day then data.flashCount or 0 else 0
	return {
		left = math.max(0, Shop.FLASH.perDay - count),
		nextMin = Shop.flashMinutes(count + 1),
		resetIn = (day + 1) * 86400 - now,
	}
end

local function trayTop(st: State): number
	local top = 0
	for _, c in st.cubes:ids() do
		top = math.max(top, st.cubes:tier(c))
	end
	return top
end

-- 트레이 등급별 개수 { {tier, count}, ... } 높은 등급부터 (큐브 인벤토리 위젯, client/CubeInventory)
local function trayTiers(st: State): { { number } }
	local n: { [number]: number } = {}
	for _, c in st.cubes:ids() do
		local tier = st.cubes:tier(c)
		n[tier] = (n[tier] or 0) + 1
	end
	local list = {}
	for tier, count in n do
		table.insert(list, { tier, count })
	end
	table.sort(list, function(a, b)
		return a[1] > b[1]
	end)
	return list
end

local function snapshot(st: State): { [string]: any }
	local data = st.data
	local droppers = {}
	for i, d in data.droppers do
		droppers[i] = {
			tier = d.tier,
			lv = d.lv,
			interval = Economy.dropInterval(d.lv),
			double = Economy.doubleDropChance(d.lv),
			nextMilestone = Economy.nextMilestone(Economy.SPEED_MILESTONES, d.lv),
			tierCap = Economy.tierCap(data.rebirths),
			speedCost = if d.lv < Economy.MAX_SPEED_LV then Economy.speedCost(i, d.lv, data.rebirths) else nil,
			tierCost = if d.tier < Economy.tierCap(data.rebirths) then Economy.tierCost(d.tier, data.rebirths) else nil,
		}
	end
	local hatching = {}
	local now = os.time()
	for i = 1, data.incubators do
		local h = data.hatching[i]
		hatching[i] = if h
			then {
				tier = h.tier,
				name = Economy.CORES[h.tier].name,
				remaining = math.max(0, h.endsAt - now),
				total = h.duration or Economy.CORES[h.tier].seconds,
				payout = h.payout,
			}
			else false
	end
	local upgrades = {}
	for id, def in Economy.UPGRADES do
		local lv = upg(st, id)
		upgrades[id] = {
			lv = lv,
			max = def.max,
			cost = Economy.upgradeCost(id, lv, data.rebirths),
			nextMilestone = Economy.nextMilestone(def.milestones, lv),
		}
	end
	return {
		cash = data.cash,
		gems = data.gems,
		collection = Collection.snapshot(data),
		pets = PetsServer.snapshot(data),
		rush = if Economy.rushMult(data.rebirths, data.runBest or data.stats.best) > 1
			then { mult = Economy.RUSH_MULT, untilTier = Economy.rushUntil(data.rebirths) }
			else nil,
		shop = {
			starter = data.starterBought == true,
			passes = data.passes,
			offerReady = starterOfferReady(data),
			flash = flashSnapshot(data),
		},
		rateAsked = data.rateAsked == true,
		upgrades = upgrades,
		bat = batSnapshot(data),
		steal = Steal.snapshot(data, (Shop.item("steal") :: Shop.Item).id),
		carrying = Steal.isCarrying(st.player),
		income = st.income,
		mult = mult(st),
		visitors = friendsHere(st), -- 함께 있는 친구 수 (친구 보너스)
		friendsOnline = Friends.any(st.player),
		online = (function()
			local secs = onlineSeconds(st)
			local nextIn, nextBonus = Online.streakNext(secs)
			return { bonus = Online.streakBonus(secs), nextIn = nextIn, nextBonus = nextBonus }
		end)(),
		hatchSpeed = Online.HATCH_SPEED,
		raid = Raid.snapshot(data),
		rebirths = data.rebirths,
		rebirthCost = if data.rebirths < Economy.MAX_REBIRTH then Economy.rebirthCost(data.rebirths) else nil,
		runBest = data.runBest or data.stats.best,
		droppers = droppers,
		slotCost = if #data.droppers < Economy.MAX_DROPPERS
			then Economy.slotCost(#data.droppers, data.rebirths)
			else nil,
		incubatorCost = if data.incubators < Economy.MAX_INCUBATORS
			then Economy.incubatorCost(data.incubators)
			else nil,
		hatching = hatching,
		incubatorCount = data.incubators,
		queued = #data.coreQueue,
		offline = data.offlinePending,
		best = data.stats.best,
		trayCount = st.cubes:count(),
		trayTop = trayTop(st),
		trayTiers = trayTiers(st), -- 트레이에 있는 가장 높은 등급 (목표 바: 다음 등급 / 천장 → 환생)
		trayCap = Economy.trayCap(upg(st, "tray")),
		plotCenter = st.plot.center,
		traySize = Vector3.new(st.plot.width, Config.TRAY_SIZE.Y, st.plot.width),
		events = Events.snapshot(st),
		daily = Daily.snapshot(data, st.baseIncome),
		login = Daily.loginSnapshot(data),
	}
end

local function push(st: State)
	net.fire("State", st.player, snapshot(st))
end

-- 저장할 트레이: 지금 있는 큐브 + 아직 복원 중인 큐브
-- (2026-10-20 리뷰: 접속 후 ~3초 복원 중에 나가거나 저장되면 아직 안 떨어진 큐브가 사라졌다)
local function packTray(st: State): { any }
	local tray = {}
	for _, cube in st.cubes:ids() do
		table.insert(tray, Economy.packCube(st.cubes:tier(cube), st.cubes:variant(cube)))
	end
	for _, entry in st.pendingTray do
		table.insert(tray, entry)
	end
	return tray
end

-- 1초마다: 수입, 기록, 상태 전송
local function secondTick(st: State)
	local data = st.data
	refreshIncome(st)
	if st.income > 0 then
		Ledger.credit(st.player, "cash", st.income, "Gameplay", "tray_income", false)
	end
	data.lastIncome = st.baseIncome
	data.lastSeen = os.time()
	Daily.tick(data)
	-- 연쇄가 끝났으면 콤보 현금 지급
	if st.comboCash > 0 and os.clock() - st.comboAt > 1.2 then
		local amount = math.floor(st.comboCash)
		st.comboCash = 0
		if amount > 0 then
			Ledger.credit(st.player, "cash", amount, "Gameplay", "combo_cash", false)
			net.fire("Fx", st.player, "comboCash", amount, st.combo)
		end
	end
	-- 접속 중엔 부화 시계 2배 (오프라인은 그대로): 끝나는 시각을 1초씩 더 당긴다
	local t = os.time()
	for _, h in data.hatching do
		if h.endsAt > t then
			h.endsAt = math.max(t, h.endsAt - (Online.HATCH_SPEED - 1))
		end
	end
	-- 수입 자릿수 기록: $1K/s, $10K/s ... 처음 넘을 때만
	local exp = if st.income >= 1 then math.floor(math.log10(st.income)) else 0
	if exp > data.records.incomeExp then
		local announce = data.records.incomeExp >= 2 -- 접속 첫 틱의 몰아 쌓기·초반 $100/s 이하는 조용히
		data.records.incomeExp = exp
		if announce then
			record(st, Strings.msg("record.income", { cash = Format.short(10 ^ exp) }))
		end
	end
	data.tray = packTray(st)
	push(st)
end

function Factory.start(player: Player, data: { [string]: any }): boolean
	local plot = Plots.claim(player)
	if not plot then
		player:Kick("This server is full. Please join another server.")
		return false
	end
	local st: State = {
		player = player,
		data = data,
		plot = plot,
		cubes = CubeWorld.new(plot, function()
			return Economy.tierCeiling(data.rebirths)
		end, if Config.DATA_CUBES then SimBackend.new(plot) else nil),
		dropTimers = {},
		lastManual = 0,
		combo = 0,
		comboAt = 0,
		comboRecordShown = false,
		income = data.lastIncome or 0,
		baseIncome = data.lastIncome or 0,
		pendingTray = {},
		luck = 1,
		lastSwing = 0,
		ceilingHintAt = -1e9,
		joinedAt = os.clock(),
		comboCash = 0,
	}
	states[player] = st
	PetsServer.ensure(data)
	PetsServer.apply(player, data)
	giveBat(player)
	Plots.setWidth(plot, Economy.trayWidth(upg(st, "tray")))

	-- 오프라인 수익: 마지막 기록 시점의 초당 수입 기준 (docs/05 §4.6, 상한 Economy.OFFLINE_CAP)
	if data.lastSeen > 0 then
		local away = os.time() - data.lastSeen
		data.offlinePending += Economy.offlineEarnings(data.lastIncome, away)
	end

	-- 저장된 트레이 복원: 위에서 차례로 떨어뜨림
	-- 저장분은 st.pendingTray에 두고 하나씩 꺼내 떨어뜨린다 (그동안 저장하면 packTray가 남은 것도 넣는다)
	st.pendingTray = table.clone(data.tray)
	task.spawn(function()
		-- 항목: 예전 저장은 등급 숫자, 변이 큐브는 { t, v } (Economy.unpackCube)
		local i = 0
		while #st.pendingTray > 0 do
			if states[player] ~= st then
				return
			end
			local entry = table.remove(st.pendingTray, 1)
			i += 1
			local tier, v = Economy.unpackCube(entry)
			if not tier then
				continue
			end
			local col = (i - 1) % 6
			local row = ((i - 1) // 6) % 6
			local ok, err = pcall(spawnCube, st, tier, trayPoint(st, -0.8 + col * 0.32, -0.8 + row * 0.32), v)
			if not ok then
				warn("tray restore failed", tier, v, err)
			end
			if i % 6 == 0 then
				task.wait(0.15)
			end
		end
	end)

	refreshDroppers(st)
	Collection.apply(player, data, plot.model)
	startCores(st)
	ftue(st, 1)
	push(st)
	return true
end

function Factory.stop(player: Player)
	local st = states[player]
	if not st then
		return
	end
	st.data.tray = packTray(st)
	st.data.lastSeen = os.time()
	states[player] = nil
	st.cubes:close() -- 데이터 큐브면 모두에게 빈 목록 (클라이언트 로컬 파트는 Plots.release가 못 지운다)
	Plots.release(st.plot)
	Collection.applyPlot(st.plot.model, nil) -- 다음 주인을 위해 기본 꾸미기로
end

function Factory.spawnCFrame(player: Player): CFrame?
	local st = states[player]
	return st and Plots.spawnCFrame(st.plot)
end

-- 원격 핸들러 ------------------------------------------------------------------

local function onDrop(player: Player, x: number)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	if now - st.lastManual < Config.MANUAL_DROP_COOLDOWN then
		return
	end
	st.lastManual = now
	local tier = Economy.tapTier(0) -- TAP POWER 삭제 (2026-10-20), 예전 레벨은 무시
	dropCube(st, tier, trayPoint(st, math.clamp(x, -1, 1), (math.random() - 0.5) * 0.6))
	Daily.progress(st.data, "tap")
end

-- 하나 사기 (push는 부르는 쪽에서)
local function buyOne(st: State, kind: string, index: number): boolean
	local player = st.player
	local data = st.data
	local cost: number?
	local apply: (() -> ())?
	if kind == "speed" or kind == "tier" then
		local d = data.droppers[index]
		if not d then
			return false
		end
		if kind == "speed" and d.lv < Economy.MAX_SPEED_LV then
			cost = Economy.speedCost(index, d.lv, data.rebirths)
			apply = function()
				d.lv += 1
				if table.find(Economy.SPEED_MILESTONES, d.lv) then
					local pct = math.round(Economy.doubleDropChance(d.lv) * 100)
					net.fire("Fx", player, "milestone", `BIG DROP {pct}%!`, index)
				end
			end
		elseif kind == "tier" and d.tier < Economy.tierCap(data.rebirths) then
			cost = Economy.tierCost(d.tier, data.rebirths)
			apply = function()
				d.tier += 1
			end
		end
	elseif kind == "slot" and #data.droppers < Economy.MAX_DROPPERS then
		cost = Economy.slotCost(#data.droppers, data.rebirths)
		apply = function()
			table.insert(data.droppers, { tier = 1, lv = 0 })
		end
	elseif kind == "incubator" and data.incubators < Economy.MAX_INCUBATORS then
		cost = Economy.incubatorCost(data.incubators)
		apply = function()
			data.incubators += 1
			startCores(st)
		end
	end
	if not cost or not apply or not Ledger.debit(player, "cash", cost, "Shop", kind) then
		return false
	end
	apply()
	Daily.progress(data, "upgrade")
	return true
end

-- 일괄 강화 (2026-10-25 사용자 "환생하면 기존 강화 누르기 매우 귀찮아짐, 유지하거나 일괄 강화"):
-- 드로퍼 SPEED·TIER·새 드로퍼 중 가장 싼 것을 돈이 떨어질 때까지 산다
local function buyAll(st: State): number
	local data = st.data
	local n = 0
	for _ = 1, 400 do
		local bestKind, bestIndex, bestCost = nil, 0, math.huge
		for i, d in data.droppers do
			if d.lv < Economy.MAX_SPEED_LV then
				local c = Economy.speedCost(i, d.lv, data.rebirths)
				if c < bestCost then
					bestKind, bestIndex, bestCost = "speed", i, c
				end
			end
			if d.tier < Economy.tierCap(data.rebirths) then
				local c = Economy.tierCost(d.tier, data.rebirths)
				if c < bestCost then
					bestKind, bestIndex, bestCost = "tier", i, c
				end
			end
		end
		if #data.droppers < Economy.MAX_DROPPERS then
			local c = Economy.slotCost(#data.droppers, data.rebirths)
			if c < bestCost then
				bestKind, bestIndex, bestCost = "slot", 0, c
			end
		end
		if not bestKind or bestCost > data.cash or not buyOne(st, bestKind, bestIndex) then
			break
		end
		n += 1
	end
	return n
end

local function onBuy(player: Player, kind: string, index: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local ok = if kind == "all" then buyAll(st) > 0 else buyOne(st, kind, index)
	if not ok then
		return false
	end
	refreshDroppers(st)
	ftue(st, 3)
	push(st)
	return true
end

-- 섞기 사용: 무료 먼저, 없으면 유료
------------------------------------------------------------------------
-- 배트 (2026-10-18): 휘두르면 앞쪽의 내 큐브를 밀친다. 남의 트레이 큐브는 건드리지 않는다(방해 방지).
-- 강화(범위·힘·속도)는 젬, 최대 Lv은 도감 발견 수 (Economy.batCap)
------------------------------------------------------------------------

local function makeBat(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.CanBeDropped = false
	tool.ToolTip = "Swing to knock your cubes around!"
	tool.Grip = CFrame.new(0, -1.6, 0)
	tool.TextureId = (AssetIds :: any).Icons.Bat or ""
	-- 알루미늄 배트 (2026-10-19, 나무 배트에서 교체): 검은 그립 테이프 + 노브, 은색 금속 테이퍼·배럴, 빨간 띠, 끝 캡.
	-- Handle·Barrel은 보이지 않는 기준 블록(손잡이 방향·궤적 기준점), 모양은 원기둥 조각들 (원기둥 축 = X → Z축 90° 회전)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 2.2, 0.45)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.8, 2.8, 0.8)
	barrel.Transparency = 1
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.CFrame = handle.CFrame * CFrame.new(0, 2.5, 0)
	barrel.Parent = tool
	local GRIP = Color3.fromRGB(30, 30, 34)
	local SILVER = Color3.fromRGB(232, 236, 244)
	local function piece(name: string, y0: number, y1: number, d: number, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = handle.CFrame * CFrame.new(0, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		p.Color = color
		p.Material = material
		p.Reflectance = if material == Enum.Material.Metal then 0.25 else 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	-- y = 손잡이 중심 기준 (예전 나무 배트와 같은 길이: -1.25 ~ 3.95)
	piece("Knob", -1.25, -1.05, 0.62, GRIP, Enum.Material.SmoothPlastic)
	piece("GripTape", -1.05, 1.0, 0.4, GRIP, Enum.Material.Fabric)
	piece("Taper1", 1.0, 1.45, 0.46, SILVER, Enum.Material.Metal)
	piece("Taper2", 1.45, 1.8, 0.58, SILVER, Enum.Material.Metal)
	piece("Taper3", 1.8, 2.1, 0.7, SILVER, Enum.Material.Metal)
	piece("BarrelBody", 2.1, 3.85, 0.82, SILVER, Enum.Material.Metal)
	piece("Band", 2.35, 2.75, 0.84, Color3.fromRGB(230, 60, 60), Enum.Material.SmoothPlastic)
	piece("EndCap", 3.85, 3.95, 0.7, GRIP, Enum.Material.SmoothPlastic)
	-- 휘두를 때 궤적 (모두에게 보이게 서버가 켠다: onSwing. 내 화면은 클라가 먼저 켜서 지연 없이)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = Vector3.new(0, -0.6, 0)
	a0.Parent = barrel
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = Vector3.new(0, 1.5, 0)
	a1.Parent = barrel
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 210, 140))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.3)
	trail.Enabled = false
	trail.Parent = barrel
	return tool
end

Factory.makeBat = makeBat -- AI 플레이어(server/Bots)도 같은 배트를 든다

-- 서버 Swing은 임팩트 순간에 온다 → 따라가기 구간 동안 궤적을 켠다
function Factory.flashTrail(char: Model)
	local bat = char:FindFirstChild("Bat")
	local trail = bat and bat:FindFirstChild("SwingTrail", true) :: Trail?
	if not trail then
		return
	end
	trail.Enabled = true
	local token = ((trail:GetAttribute("Flash") :: number?) or 0) + 1
	trail:SetAttribute("Flash", token)
	task.delay(0.18, function()
		if trail.Parent and trail:GetAttribute("Flash") == token then
			trail.Enabled = false
		end
	end)
end

-- 지금 가방과 다시 태어날 때 모두 배트가 있게 (StarterGear는 리스폰마다 복사됨)
function giveBat(player: Player)
	local gear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)
	if gear and not gear:FindFirstChild("Bat") then
		makeBat().Parent = gear
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	if backpack and not backpack:FindFirstChild("Bat") and not (char and char:FindFirstChild("Bat")) then
		makeBat().Parent = backpack
	end
	local st = states[player]
	if st then
		Collection.applyBat(player, st.data) -- 배트 스킨 (docs/16 §3)
	end
end

local MAX_HITS = 14

local function onSwing(player: Player): number
	local st = states[player]
	if not st then
		return 0
	end
	local data = st.data
	local now = os.clock()
	-- 지연을 감안해 쿨다운의 85%까지 허용
	if now - st.lastSwing < Economy.batCooldown(batLv(data, "speed")) * 0.85 then
		return 0
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not (char :: Model):FindFirstChild("Bat") then
		return 0
	end
	st.lastSwing = now
	Factory.flashTrail(char :: Model)
	local range = Economy.batRange(batLv(data, "range"))
	local power = Economy.batPower(batLv(data, "power"))
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	local hits = 0
	local cubes = st.cubes
	for _, cube in cubes:ids() do
		if hits >= MAX_HITS then
			break
		end
		local off = cubes:position(cube) - root.Position
		local reach = range + cubes:size(cube) / 2
		if off.Magnitude > reach then
			continue
		end
		local flat = off * Vector3.new(1, 0, 1)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else look
		-- 앞쪽 반원 (아주 가까우면 방향 무관)
		if dir:Dot(look) < 0.1 and off.Magnitude > 4 then
			continue
		end
		local push = (dir + look).Unit * power + Vector3.new(0, power * 0.45, 0)
		cubes:setVelocity(cube, push)
		cubes:setAngular(cube, Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12)
		hits += 1
	end
	if hits > 0 then
		Daily.progress(data, "bat", hits)
	end
	-- 다른 플레이어도 날린다 (들고 있던 큐브는 주인에게)
	return hits + Steal.batHit(player, root :: BasePart, range, power, look) + Raid.onSwing(player, root :: BasePart)
end

local function onBatUpgrade(player: Player, stat: string): boolean
	local st = states[player]
	if not st or not table.find(Economy.BAT_STATS, stat) then
		return false
	end
	local data = st.data
	data.bat = data.bat or {}
	local lv = batLv(data, stat)
	local cost = Economy.batCost(lv)
	if not cost or lv >= Economy.batCap(Collection.found(data)) then
		return false
	end
	if not Ledger.debit(player, "gems", cost, "Shop", "bat_" .. stat) then
		return false
	end
	data.bat[stat] = lv + 1
	if stat == "move" then
		Steal.applySpeed(player)
	end
	push(st)
	return true
end

-- 상품 지급 등 외부에서 상태가 바뀌었을 때 즉시 전송
function Factory.refresh(player: Player)
	local st = states[player]
	if st then
		push(st)
	end
end

-- 상품 "Cube Rain": 내 드로퍼 최고 등급 일반 큐브 n개를 트레이 위에서 차례로 떨어뜨림.
-- 변이 굴림을 하지 않는다(유료 결과는 확정). 넘치면 enforceTray가 가장 싼 큐브를 판다
function Factory.cubeRain(player: Player, n: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local tier = 1
	for _, d in st.data.droppers do
		tier = math.max(tier, d.tier)
	end
	net.fire("Fx", player, "shop", `CUBE RAIN x{n}!`)
	task.spawn(function()
		for i = 1, n do
			if states[player] ~= st then
				return
			end
			local a = i * 2.4
			spawnCube(st, tier, trayPoint(st, math.cos(a) * 0.7, math.sin(a) * 0.7), Economy.NORMAL)
			task.wait(0.08)
		end
	end)
	return true
end

-- 상품 "Instant Hatch": 부화 중인 코어를 모두 지금 끝냄 (받기는 평소처럼 CLAIM)
function Factory.finishHatch(player: Player): boolean
	local st = states[player]
	if not st then
		return false
	end
	local t = os.time()
	local any = false
	for _, h in st.data.hatching do
		if h.endsAt > t then
			any = true
		end
		h.endsAt = math.min(h.endsAt, t)
	end
	if not any then
		-- 부화 중인 코어가 없으면 돈만 내고 받는 게 없었다 (2026-10-20 리뷰) → 다음에 시작하는 코어를 바로 끝내는 권리로 보관
		st.data.hatchCredit = (st.data.hatchCredit or 0) + 1
		net.fire("Toast", player, "Saved! Your next core will hatch instantly")
		push(st)
		return true
	end
	net.fire("Fx", player, "shop", "CORES READY!")
	push(st)
	return true
end

-- 상점 구매 연출 (server/Shop)
function Factory.shopFx(player: Player, text: string)
	if net then
		net.fire("Fx", player, "shop", text)
	end
end

-- 공장·코어 업그레이드 (docs/14 §3.2)
local function onUpgrade(player: Player, id: string): boolean
	local st = states[player]
	if not st or not Economy.UPGRADES[id] then
		return false
	end
	local data = st.data
	local before = upg(st, id)
	local cost = Economy.upgradeCost(id, before, data.rebirths)
	if not cost or not Ledger.debit(player, "cash", cost, "Shop", id) then
		return false
	end
	local lv = before + 1
	data.upgrades[id] = lv
	if id == "hatch" then
		-- 진행 중인 부화도 남은 시간을 새 배율로 줄인다
		local ratio = Economy.hatchScale(lv) / Economy.hatchScale(before)
		local now = os.time()
		for _, h in data.hatching do
			h.endsAt = now + math.ceil(math.max(0, h.endsAt - now) * ratio)
		end
	end
	local ms = Economy.UPGRADES[id].milestones
	if ms and table.find(ms, lv) then
		net.fire("Fx", player, "milestone", "INCOME x2!", id)
	end
	if id == "tray" then
		Plots.setWidth(st.plot, Economy.trayWidth(lv))
		net.fire("Fx", player, "shop", `TRAY +{Economy.TRAY_STEP}!`)
	end
	refreshIncome(st)
	Daily.progress(data, "upgrade")
	ftue(st, 3)
	push(st)
	return true
end

local function onRebirth(player: Player): boolean
	local st = states[player]
	if not st then
		return false
	end
	local data = st.data
	-- 이번 판에 상한 등급 큐브를 만들어야 (2026-10-21 사용자)
	if not Economy.canRebirth(data.rebirths, data.runBest or data.stats.best) then
		return false
	end
	if not Ledger.debit(player, "cash", Economy.rebirthCost(data.rebirths), "Gameplay", "rebirth") then
		return false
	end
	local rest = data.cash
	if rest > 0 then
		Ledger.debit(player, "cash", rest, "Gameplay", "rebirth_reset")
	end
	data.rebirths += 1
	-- 리버스 러시: 드로퍼는 startTier부터, 지난 판 상한 근처까지 수입 x3 (Economy.rushMult)
	local startTier = Economy.startTier(data.rebirths)
	data.droppers = { { tier = startTier, lv = 0 }, { tier = startTier, lv = 0 } }
	data.runBest = startTier
	for id, def in Economy.UPGRADES do
		if not def.keep then
			data.upgrades[id] = 0
		end
	end
	local ids = st.cubes:ids()
	for i = #ids, 1, -1 do
		removeCube(st, ids[i], CubeCodec.REASON_OTHER)
	end
	refreshDroppers(st)
	ftue(st, 6)
	pcall(function()
		AnalyticsService:LogProgressionCompleteEvent(player, "Rebirth", data.rebirths, `Rebirth {data.rebirths}`)
	end)
	net.fire(
		"Toast",
		player,
		Strings.msg("toast.rebirth", {
			n = data.rebirths,
			mult = string.format("%.4g", Economy.REBIRTH_MULT ^ data.rebirths),
			tier = Economy.tierCeiling(data.rebirths),
		})
	)
	task.delay(2.5, function()
		if states[player] == st then
			net.fire(
				"Toast",
				player,
				Strings.msg(
					"toast.rush",
					{ mult = Economy.RUSH_MULT, tier = Economy.rushUntil(data.rebirths), start = startTier }
				)
			)
		end
	end)
	net.fire("Fx", player, "rebirth", st.plot.center)
	push(st)
	return true
end

local function onClaimCore(player: Player, index: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local data = st.data
	local h = data.hatching[index]
	if not h or h.endsAt > os.time() then
		return false
	end
	table.remove(data.hatching, index)
	data.coreBonus += Economy.CORES[h.tier].bonus
	Ledger.credit(player, "cash", h.payout, "Gameplay", "core_hatch")
	net.fire("Fx", player, "hatch", st.plot.center + Vector3.new(0, 6, 0), Economy.CORES[h.tier].name, h.payout)
	Daily.progress(data, "hatch")
	ftue(st, 5)
	startCores(st)
	push(st)
	return true
end

-- 꾸미기 장착·젬 구매 (docs/16 §3)
local function onEquip(player: Player, id: string): boolean
	local st = states[player]
	if not st or not Collection.equip(player, st.data, st.plot.model, id) then
		return false
	end
	push(st)
	return true
end

local function onClaimCodex(player: Player, what: string): number
	local st = states[player]
	if not st then
		return 0
	end
	local gems = Collection.claim(player, st.data, what)
	if gems > 0 then
		push(st)
	end
	return gems
end

local function onBuyCosmetic(player: Player, id: string): boolean
	local st = states[player]
	if not st or not Collection.buy(player, st.data, st.plot.model, id) then
		return false
	end
	push(st)
	return true
end

-- 캐릭터가 새로 생기면 꼬리 꾸미기를 다시 단다
function Factory.onCharacter(player: Player, character: Model)
	local function group(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	for _, d in character:GetDescendants() do
		group(d)
	end
	character.DescendantAdded:Connect(group)
	local st = states[player]
	if st then
		Collection.applyTrail(character, st.data)
		PetsServer.apply(player, st.data)
		Steal.applySpeed(player) -- MOVE SPEED 강화
	end
end

-- Studio 전용 디버그 (init.server StudioDebug 훅에서만 호출): 변이 확률 배율
-- Studio 디버그: 코어를 대기열에 넣음 (부화 UI 확인용)
function Factory.debugCore(player: Player, tier: number): boolean
	local st = states[player]
	if not st or not Economy.CORES[tier] then
		return false
	end
	addCore(st, tier, st.plot.center + Vector3.new(0, 6, 0))
	push(st)
	return true
end

-- Studio 전용 (StudioDebug "fill"): 트레이를 비우고 등급 tier 근처 큐브 n개로 채움 (고등급 렉 측정)
function Factory.debugFill(player: Player, tier: number, n: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local ids = st.cubes:ids()
	for i = #ids, 1, -1 do
		removeCube(st, ids[i], CubeCodec.REASON_OTHER)
	end
	for k = 1, n do
		local t = math.max(1, tier - (k % 6))
		spawnCube(
			st,
			t,
			trayPoint(st, math.random() * 1.6 - 0.8, math.random() * 1.6 - 0.8) + Vector3.new(0, k * 0.3, 0)
		)
	end
	return true
end

function Factory.debugLuck(player: Player, factor: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	st.luck = math.max(0, factor)
	return true
end

local function onClaimOffline(player: Player): boolean
	local st = states[player]
	if not st or st.data.offlinePending <= 0 then
		return false
	end
	local amount = st.data.offlinePending
	st.data.offlinePending = 0
	Ledger.credit(player, "cash", amount, "Gameplay", "offline")
	push(st)
	return true
end

local function onStarterOffered(player: Player): boolean
	local st = states[player]
	if not st or not starterOfferReady(st.data) then
		return false
	end
	st.data.starterOfferAt = os.time()
	st.data.starterOfferCount = (st.data.starterOfferCount or 0) + 1
	return true
end

-- 접속 선물·일일 퀘스트 받기 (docs/23)
local function onClaimGift(player: Player, which: string): (string?, (string | Strings.Msg)?)
	local st = states[player]
	if not st then
		return nil, nil
	end
	local reward, text = Daily.claimGift(player, st.data, st.baseIncome, which)
	if reward then
		push(st)
	end
	return reward, text
end

local function onClaimQuest(player: Player, index: number): Strings.Msg?
	local st = states[player]
	if not st then
		return nil
	end
	local text = Daily.claimQuest(player, st.data, st.baseIncome, index)
	if text then
		push(st)
	end
	return text
end

local function onClaimLogin(player: Player): Strings.Msg?
	local st = states[player]
	if not st then
		return nil
	end
	local text = Daily.claimLogin(player, st.data, st.baseIncome)
	if text then
		push(st)
	end
	return text
end

local function onPetHatch(player: Player, eggId: string, count: number): ({ any }?, string?)
	local st = states[player]
	if not st then
		return nil, nil
	end
	local out, why = PetsServer.hatch(player, st.data, eggId, count)
	if out then
		Daily.progress(st.data, "pet", #out)
		refreshIncome(st)
		push(st)
	end
	return out, why
end

-- action: "equip" | "fuse" | "release" | "best" (uid는 best일 때 0)
local function onPetAction(player: Player, action: string, uid: number): any
	local st = states[player]
	if not st then
		return nil
	end
	local data = st.data
	local result: any = nil
	if action == "equip" then
		result = PetsServer.equip(player, data, uid)
	elseif action == "best" then
		result = PetsServer.equipBest(player, data)
	elseif action == "fuse" then
		local p = PetsServer.fuse(player, data, uid)
		result = if p then { u = p.u, id = p.id, star = p.star } else nil
	elseif action == "release" then
		result = PetsServer.release(player, data, uid)
	end
	refreshIncome(st)
	push(st)
	return result
end

-- Studio 전용 (StudioDebug "pet"): 펫 지급
function Factory.debugPet(player: Player, id: string, star: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	PetsServer.debugGive(player, st.data, id, star)
	push(st)
	return true
end

local function onRateAsked(player: Player): boolean
	local st = states[player]
	if not st then
		return false
	end
	st.data.rateAsked = true
	return true
end

function Factory.init(netServer: any)
	net = netServer
	-- 충돌 그룹(Cubes·Players·TrayGuard)은 Plots.init에서 등록
	if Config.DATA_CUBES then
		SimBackend.start(net) -- 플롯 시뮬 Heartbeat + CubeNet 복제
	end
	net.on("Drop", onDrop)
	net.on("Buy", onBuy)
	net.on("Upgrade", onUpgrade)
	net.on("Swing", onSwing)
	net.on("BatUpgrade", onBatUpgrade)
	net.on("Rebirth", onRebirth)
	net.on("ClaimCore", onClaimCore)
	net.on("ClaimOffline", onClaimOffline)
	net.on("RateAsked", onRateAsked)
	net.on("StarterOffered", onStarterOffered)
	Events.init({
		states = states,
		spawnCube = spawnCube,
		trayPoint = trayPoint,
		onGolden = function(st)
			Daily.progress(st.data, "golden")
		end,
	})
	Daily.init({ giftGolden = Events.gift })
	net.on("ClaimGift", onClaimGift)
	net.on("ClaimQuest", onClaimQuest)
	net.on("ClaimLogin", onClaimLogin)
	net.on("PetHatch", onPetHatch)
	net.on("PetAction", onPetAction)
	Steal.init({
		states = states,
		spawnCube = spawnCube,
		onVariant = onVariant,
		trayPoint = trayPoint,
		push = push,
		net = net,
	})
	-- 보스 레이드 (docs/25): 레이드 중엔 참여자끼리 배트 넉백·훔치기 없음
	Friends.init()
	Steal.setRaidCheck(Raid.inRaid)
	Raid.init({
		states = states,
		center = Vector3.new(0, 1, 0), -- 광장 바닥 (server/World TOP)
		fx = function(player: Player, ...)
			net.fire("Fx", player, ...)
		end,
		home = function(player: Player): CFrame?
			local st = states[player]
			return if st then Plots.spawnCFrame(st.plot) else nil
		end,
		beforeTeleport = Steal.onLeave,
		resist = Steal.resist,
		applySpeed = Steal.applySpeed,
		refresh = Factory.refresh,
		hitGap = function(player: Player): number
			local st = states[player]
			return Economy.batCooldown(if st then batLv(st.data, "speed") else 0)
		end,
	})
	-- 광장 선물 상자 (server/Boxes)
	-- 광장 발판: BOSS SHOP·PET EGGS (server/Stations, 클라가 올라섰는지 보고 패널을 연다)
	require(script.Parent.Stations).init(Vector3.new(0, 1, 0))
	require(script.Parent.Boxes).init({
		states = states,
		center = Vector3.new(0, 1, 0),
		radius = 44,
		fx = function(player: Player, ...)
			net.fire("Fx", player, ...)
		end,
		refresh = Factory.refresh,
		busy = Raid.inRaid,
	})
	net.on("Equip", onEquip)
	net.on("BuyCosmetic", onBuyCosmetic)
	net.on("ClaimCodex", onClaimCodex)

	-- 한 사람 데이터 오류가 같은 서버 다른 사람의 수입·저장까지 멈추지 않게 사람마다 pcall (2026-10-20 리뷰)
	local warnedAt: { [Player]: number } = {}
	local function guarded(st: State, what: string, f: (State) -> ())
		local ok, err = pcall(function()
			f(st)
		end)
		if not ok and os.clock() - (warnedAt[st.player] or -1e9) > 30 then
			warnedAt[st.player] = os.clock()
			warn(`Factory {what} failed for {st.player.Name}: {err}`)
		end
	end
	local function dropperStep(st: State, dt: number)
		-- 가득 차면 드로퍼는 쉰다 (타이머는 한 번 쏠 만큼만 쌓아 두어 빈칸이 나면 바로 떨군다). 복원 중인 큐브도 자리를 차지
		local full = st.cubes:count() + #st.pendingTray >= Economy.trayCap(upg(st, "tray"))
		for i, d in st.data.droppers do
			local interval = Economy.dropInterval(d.lv) * Events.dropScale(st)
			st.dropTimers[i] = math.min((st.dropTimers[i] or 0) + dt, interval)
			if not full and st.dropTimers[i] >= interval then
				st.dropTimers[i] -= interval
				local p = st.plot.dropperParts[i]
				if p then
					local at = p.Position - Vector3.new(0, 3, 0)
					-- 2배 투하 = 한 등급 위 큐브 1개 (같은 가치, 2026-10-21 사용자: 후반 큐브 수·물리 줄이기).
					-- 합치기 상한을 넘으면 예전처럼 2개
					if math.random() < Economy.doubleDropChance(d.lv) then
						if d.tier + 1 <= Economy.tierCeiling(st.data.rebirths) then
							dropCube(st, bigDropTier(st, d.tier, at), at)
						else
							dropCube(st, d.tier, at)
							local side = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
							dropCube(st, d.tier, at + side * Config.cubeSize(d.tier))
						end
					else
						dropCube(st, d.tier, at)
					end
				end
			end
		end
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		warnedAt[player] = nil
	end)

	local scanAcc, secAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		scanAcc += dt
		secAcc += dt
		for _, st in states do
			guarded(st, "drop", function(s: State)
				dropperStep(s, dt)
			end)
		end
		if scanAcc >= Config.MERGE_SCAN_INTERVAL then
			scanAcc = 0
			for _, st in states do
				guarded(st, "merge", function(s: State)
					scanMerges(s)
					enforceTray(s)
				end)
			end
		end
		if secAcc >= 1 then
			secAcc -= 1
			for _, st in states do
				guarded(st, "tick", secondTick)
			end
		end
	end)
end

return Factory
