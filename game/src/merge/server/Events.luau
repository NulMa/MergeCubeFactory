--!strict
-- 이벤트 서버 (docs/17_EVENTS.md): 황금 큐브(R1), 머지 피버(R4), 서버 알림(R5).
-- 모든 버프는 서버가 시각으로 들고 있고 Factory의 mult()·투하 간격·snapshot에 한 줄씩 끼워 넣는다.
-- Factory 쪽 훅 (병합 충돌을 줄이려고 이 모듈 밖 수정은 이것뿐):
--   Events.init({ states, spawnCube, trayPoint })  Factory.init에서 1회
--   Events.mult(st)        mult()의 곱 인자
--   Events.dropScale(st)   드로퍼 투하 간격 배율
--   Events.onMerge(st, tier, isBest, combo)  scanMerges 합치기 직후
--   Events.snapshot(st)    State 스냅샷의 events 필드

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Core.Net)
local Shared = ReplicatedStorage.Game
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local EventsConfig = require(Shared.EventsConfig)
local Strings = require(Shared.Strings)
local CoreServer = ServerScriptService.CoreServer
local Ledger = require(CoreServer.Ledger)
local Format = require(ReplicatedStorage.Core.Format)

type Golden = {
	id: number,
	part: Part,
	born: number,
	expires: number,
	from: Vector3,
	to: Vector3,
	keep: number?, -- 선물로 나온 황금 큐브: 원래 다음 등장 시각 (선물이 자연 등장을 늦추지 않게)
}
type PState = {
	golden: Golden?,
	nextGolden: number,
	gauge: number,
	feverUntil: number,
	stormUntil: number,
	passive: number, -- 드로퍼 투하/초 (0.25초마다 갱신)
	lastAnnounce: number,
	forced: EventsConfig.RewardId?, -- Studio 디버그: 다음 보상 고정
	gifts: number, -- 접속 선물로 받은 황금 큐브 (지금 떠 있는 게 없을 때 하나씩 나옴, docs/23)
}
type Hooks = {
	states: { [Player]: any },
	spawnCube: (st: any, tier: number, position: Vector3) -> any,
	trayPoint: (st: any, x: number, z: number) -> Vector3,
	onGolden: ((st: any) -> ())?, -- 황금 큐브를 잡음 (일일 퀘스트)
}

local Events = {}

local hooks: Hooks? = nil
local net: any = nil
local ps: { [Player]: PState } = {}
local serverAnnounces: { number } = {}
local nextId = 0
local rng = Random.new()

local GOLD = Color3.fromRGB(255, 200, 40)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function get(player: Player): PState
	local p = ps[player]
	if not p then
		p = {
			golden = nil,
			nextGolden = now() + EventsConfig.GOLDEN_FIRST,
			gauge = 0,
			feverUntil = 0,
			stormUntil = 0,
			passive = 0,
			lastAnnounce = -math.huge,
			forced = nil,
			gifts = 0,
		}
		ps[player] = p
	end
	return p
end

local function log(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

local function dropperTop(data: { [string]: any }): number
	local top = 1
	for _, d in data.droppers do
		top = math.max(top, d.tier)
	end
	return top
end

-- 서버 알림 ------------------------------------------------------------------------

-- text는 영어 원문 또는 Strings 키 (args가 있으면 키: 클라이언트가 번역해 그린다, client/Loc)
local function announce(player: Player, text: string, kind: string, args: { [string]: any }?)
	local p = get(player)
	local t = now()
	if t - p.lastAnnounce < EventsConfig.ANNOUNCE_PLAYER_GAP then
		return
	end
	if
		not EventsConfig.rateLimit(serverAnnounces, t, EventsConfig.ANNOUNCE_SERVER_MAX, EventsConfig.ANNOUNCE_WINDOW)
	then
		return
	end
	p.lastAnnounce = t
	net.fireAll("Announce", text, kind, args)
end

-- 버프 -----------------------------------------------------------------------------

local function frenzyLeft(st: any): number
	return math.max(0, (st.data.frenzyUntil or 0) - now())
end

function Events.mult(st: any): number
	local p = ps[st.player]
	local fever = p ~= nil and p.feverUntil > now()
	return EventsConfig.buffMult(frenzyLeft(st) > 0, fever)
end

function Events.dropScale(st: any): number
	local p = ps[st.player]
	if not p then
		return 1
	end
	local t = now()
	local scale = if p.stormUntil > t then EventsConfig.STORM_SCALE else 1
	if p.feverUntil > t then
		scale *= EventsConfig.FEVER_DROP_SCALE
	end
	return scale
end

local function addFrenzy(st: any, seconds: number)
	st.data.frenzyUntil = math.max(st.data.frenzyUntil or 0, now()) + seconds
end

-- 머지 피버 -------------------------------------------------------------------------

local function startFever(st: any, p: PState)
	p.gauge = 0
	p.feverUntil = now() + EventsConfig.FEVER_SECONDS
	net.fire("EventFx", st.player, "fever", st.plot.center + Vector3.new(0, 8, 0))
	log(st.player, "FeverStart")
end

function Events.onMerge(st: any, tier: number, isBest: boolean, combo: number?)
	local p = get(st.player)
	if p.feverUntil <= now() then
		p.gauge += if (combo or 1) >= EventsConfig.FEVER_COMBO_FROM then 2 else 1
		if p.gauge >= EventsConfig.FEVER_GOAL then
			startFever(st, p)
		end
	end
	if isBest and tier >= EventsConfig.announceTier(Economy.MAX_TIER) then
		announce(st.player, "announce.tier", "tier", { name = st.player.DisplayName, tier = tier })
	end
end

-- 황금 큐브 -------------------------------------------------------------------------

local function removeGolden(p: PState)
	local g = p.golden
	if g then
		g.part:Destroy()
		p.golden = nil
	end
	p.nextGolden = if g and g.keep
		then math.max(g.keep, now() + 20)
		else now() + EventsConfig.goldenDelay(rng:NextNumber())
end

-- 접속 선물: 황금 큐브 하나 더 (지금 떠 있는 게 사라진 뒤 바로 나옴)
function Events.gift(player: Player)
	get(player).gifts += 1
end

local function claim(player: Player, id: number): boolean
	local h = hooks
	local st = h and h.states[player]
	local p = ps[player]
	local g = p and p.golden
	if not h or not st or not p or not g or g.id ~= id then
		return false
	end
	if now() > g.expires + EventsConfig.GOLDEN_GRACE then
		return false
	end
	local at = g.part.Position
	removeGolden(p)

	local reward = p.forced or EventsConfig.pickReward(rng:NextNumber())
	p.forced = nil
	local data = st.data
	local text: string | Strings.Msg = ""
	local tier: number? = nil
	if reward == "cash" then
		local amount = EventsConfig.cashBurst(st.baseIncome or st.income)
		Ledger.credit(player, "cash", amount, "Gameplay", "golden_cash")
		text = Strings.msg("reward.cash", { cash = Format.short(amount) })
	elseif reward == "frenzy" then
		addFrenzy(st, EventsConfig.FRENZY_SECONDS)
		text = Strings.msg("golden.frenzy", { mult = EventsConfig.FRENZY_MULT })
	elseif reward == "storm" then
		p.stormUntil = math.max(p.stormUntil, now()) + EventsConfig.STORM_SECONDS
		text = "DROP STORM!"
	elseif reward == "rain" then
		local t = EventsConfig.rainTier(data.stats.best, dropperTop(data), Economy.MAX_TIER)
		tier = t
		text = Strings.msg("golden.rain", { n = EventsConfig.RAIN_COUNT })
		task.spawn(function()
			for _ = 1, EventsConfig.RAIN_COUNT do
				if h.states[player] ~= st then
					return
				end
				h.spawnCube(st, t, h.trayPoint(st, rng:NextNumber(-0.7, 0.7), rng:NextNumber(-0.7, 0.7)))
				task.wait(0.2)
			end
		end)
	else
		local t = EventsConfig.jackpotTier(data.stats.best, Economy.MAX_TIER)
		tier = t
		text = "JACKPOT!"
		h.spawnCube(st, t, h.trayPoint(st, 0, 0) + Vector3.new(0, 6, 0))
		if t > data.stats.best then
			data.stats.best = t
			data.codex[tostring(t)] = true
		end
		announce(player, "announce.jackpot", "jackpot", { name = player.DisplayName, tier = t })
	end
	net.fire("EventFx", player, "golden", at, reward, text, tier)
	log(player, "GoldenCubeCaught")
	if h.onGolden then
		h.onGolden(st)
	end
	return true
end

local function spawnGolden(st: any, p: PState)
	nextId += 1
	local id = nextId
	local center: Vector3 = st.plot.center
	local half = Config.TRAY_SIZE.X / 2 * 0.6
	local x, z = rng:NextNumber(-half, half), rng:NextNumber(-half, half)
	local from = center + Vector3.new(x, Config.DROP_HEIGHT + 10, z)
	local to = center + Vector3.new(x * 0.6, Config.TRAY_SIZE.Y * 0.75, z * 0.6)

	local part = Instance.new("Part")
	part.Name = "GoldenCube"
	part.Size = Vector3.new(3.4, 3.4, 3.4)
	part.Color = GOLD
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true -- 클릭 판정에 필요
	part.CastShadow = false
	part.CFrame = CFrame.new(from)
	part:SetAttribute("OwnerUserId", st.player.UserId)
	part:SetAttribute("GoldenId", id)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 18
	light.Brightness = 3
	light.Parent = part
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = Color3.fromRGB(255, 240, 160)
	sparkle.Parent = part
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(140, 44)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = false -- screen_capture가 AlwaysOnTop을 못 그림 (CLAUDE 메모)
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Parent = part
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.FredokaOne
	tag.TextScaled = true
	tag.Text = "TAP ME!"
	tag.TextColor3 = Color3.fromRGB(255, 236, 140)
	tag.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	tag.TextStrokeTransparency = 0
	tag.Parent = bb
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = EventsConfig.GOLDEN_CLAIM_RANGE
	click.Parent = part
	click.MouseClick:Connect(function(clicker: Player)
		claim(clicker, id)
	end)
	part.Parent = st.plot.model

	local t = now()
	p.golden = { id = id, part = part, born = t, expires = t + EventsConfig.GOLDEN_LIFE, from = from, to = to }
	net.fire("EventFx", st.player, "goldenSpawn", part)
	log(st.player, "GoldenCubeSpawn")
end

-- 천천히 떨어지며 회전. 남은 3초는 깜빡임(사라진다는 신호)
local function animateGolden(g: Golden, t: number)
	local a = math.clamp((t - g.born) / EventsConfig.GOLDEN_LIFE, 0, 1)
	local eased = 1 - (1 - a) ^ 2
	local bob = math.sin(t * 3) * 0.6
	g.part.CFrame = CFrame.new(g.from:Lerp(g.to, eased) + Vector3.new(0, bob, 0)) * CFrame.Angles(t * 0.7, t * 1.6, 0)
	local left = g.expires - t
	g.part.Transparency = if left < 3 and math.floor(t * 6) % 2 == 0 then 0.55 else 0
end

-- 스냅샷 --------------------------------------------------------------------------

function Events.snapshot(st: any): { [string]: any }
	local p = get(st.player)
	local t = now()
	local g = p.golden
	local frenzy = frenzyLeft(st)
	return {
		gauge = p.gauge,
		goal = EventsConfig.FEVER_GOAL,
		fever = if p.feverUntil > t then p.feverUntil - t else nil,
		frenzy = if frenzy > 0 then frenzy else nil,
		storm = if p.stormUntil > t then p.stormUntil - t else nil,
		golden = if g then { id = g.id, left = math.max(0, g.expires - t) } else nil,
		mult = Events.mult(st),
	}
end

-- 루프 -----------------------------------------------------------------------------

local tickWarnAt: { [Player]: number } = {} -- 같은 오류 경고는 30초에 한 번
local function tick(dt: number, slow: boolean)
	local h = hooks
	if not h then
		return
	end
	local t = now()
	-- 사람마다 pcall: 한 사람 오류가 다른 사람 황금 큐브·피버를 멈추지 않게 (2026-10-20 리뷰)
	for player, st in h.states do
		local ok, err = pcall(function()
			local p = get(player)
			if slow then
				local intervals, doubles = {}, {}
				for i, d in st.data.droppers do
					intervals[i] = Economy.dropInterval(d.lv)
					-- 2배 투하는 이제 한 등급 위 큐브 1개라 투하 수는 그대로 (2026-10-21)
					doubles[i] = 0
				end
				p.passive = EventsConfig.dropsPerSecond(intervals, doubles, Events.dropScale(st))
			end
			if p.feverUntil <= t then
				p.gauge = EventsConfig.feverDecay(p.gauge, dt, p.passive)
			end
			local g = p.golden
			if g then
				if t > g.expires + EventsConfig.GOLDEN_GRACE then
					removeGolden(p)
					log(player, "GoldenCubeMissed")
				else
					animateGolden(g, t)
				end
			elseif p.gifts > 0 then
				p.gifts -= 1
				local keep = p.nextGolden
				spawnGolden(st, p)
				if p.golden then
					p.golden.keep = keep
				end
			elseif t >= p.nextGolden then
				spawnGolden(st, p)
			end
		end)
		if not ok and os.clock() - (tickWarnAt[player] or -1e9) > 30 then
			tickWarnAt[player] = os.clock()
			warn(`Events tick failed for {player.Name}: {err}`)
		end
	end
	-- 공장이 끝난 플레이어 정리
	for player, p in ps do
		if not h.states[player] then
			if p.golden then
				p.golden.part:Destroy()
			end
			ps[player] = nil
			tickWarnAt[player] = nil
		end
	end
end

-- Studio 전용 디버그 훅 (게시 서버에는 없음): ServerScriptService.EventsDebug:Invoke(cmd, player, arg)
--   "golden" [rewardId] → 지금 황금 큐브 등장 (보상 고정 가능) / "claim" → 현재 황금 큐브 수령
--   "fever" → 게이지 가득 / "announce" text → 배너 / "state" → 현재 이벤트 스냅샷
local function studioDebug()
	local hook = Instance.new("BindableFunction")
	hook.Name = "EventsDebug"
	hook.OnInvoke = function(cmd: string, player: Player, arg: any): any
		local h = hooks
		local st = h and h.states[player]
		if not st then
			return false
		end
		local p = get(player)
		if cmd == "golden" then
			removeGolden(p)
			p.forced = arg
			spawnGolden(st, p)
			return p.golden and p.golden.id
		elseif cmd == "claim" then
			return p.golden ~= nil and claim(player, p.golden.id)
		elseif cmd == "fever" then
			p.gauge = EventsConfig.FEVER_GOAL - 1
			Events.onMerge(st, 1, false)
			return p.feverUntil > now()
		elseif cmd == "announce" then
			p.lastAnnounce = -math.huge
			announce(player, tostring(arg or "TEST BANNER"), "tier")
			return true
		elseif cmd == "state" then
			return Events.snapshot(st)
		end
		return false
	end
	hook.Parent = ServerScriptService
end

function Events.init(h: Hooks)
	hooks = h
	net = Net.serve(EventsConfig.REMOTES :: any)
	net.on("ClaimGolden", claim)
	Players.PlayerRemoving:Connect(function(player)
		local p = ps[player]
		if p and p.golden then
			p.golden.part:Destroy()
		end
		ps[player] = nil
	end)
	local slowAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		slowAcc += dt
		local slow = slowAcc >= 0.25
		if slow then
			slowAcc = 0
		end
		tick(dt, slow)
	end)
	if RunService:IsStudio() then
		studioDebug()
	end
end

return Events
