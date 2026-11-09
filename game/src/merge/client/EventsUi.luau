--!strict
-- 이벤트 HUD·연출 (docs/17_EVENTS.md): 피버 게이지 바, 버프 타이머, 황금 큐브 버튼(게임패드), 서버 배너 + 시스템 채팅.
-- init.client에서 EventsUi.init(gui) 한 줄로 붙는다. State·EventFx·Announce 원격을 여기서 직접 듣는다.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Core.Net)
local Config = require(ReplicatedStorage.Game.Config)
local Remotes = require(ReplicatedStorage.Game.Remotes)
local EventsConfig = require(ReplicatedStorage.Game.EventsConfig)
local Fx = require(script.Parent:WaitForChild("Fx"))
local Ui = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Ui"))
local Loc = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Loc"))

local player = Players.LocalPlayer
local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

local GOLD = Color3.fromRGB(255, 200, 40)
local FEVER = Color3.fromRGB(255, 110, 60)
local FRENZY = Color3.fromRGB(255, 90, 200)
local STORM = Color3.fromRGB(110, 190, 255)

local EventsUi = {}

function EventsUi.init(gui: ScreenGui)
	local main = Net.client(Remotes :: any)
	local ev = Net.client(EventsConfig.REMOTES :: any)

	local events: { [string]: any }? = nil
	local recvAt = os.clock()
	local plotCenter: Vector3? = nil

	-- 피버 게이지: 현금 패널(12,8 · 300x74) 바로 아래 ------------------------------------
	local bar = make("Frame", {
		Name = "FeverBar",
		Size = UDim2.fromOffset(300, 24),
		Position = UDim2.fromOffset(12, 88),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { corner(12) }) :: Frame
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = FEVER,
		BorderSizePixel = 0,
		Parent = bar,
	}, { corner(12) }) :: Frame
	local fillGrad = make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 70), FEVER),
		Parent = fill,
	}) :: UIGradient
	-- 게이지 왼쪽에 불꽃 번개 아이콘
	local feverIcon = Ui.icon("Frenzy", {
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(0, -14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Rotation = -10,
		ZIndex = 3,
		Parent = bar,
	})
	if feverIcon then
		Ui.wiggle(feverIcon, 6)
	end
	local barText = label({
		Size = UDim2.new(1, -16, 1, -4),
		Position = UDim2.fromOffset(8, 2),
		Text = "FEVER 0/30",
		ZIndex = 2,
		TextStrokeTransparency = 0.5,
		Parent = bar,
	})

	-- 버프 타이머 칩 (FRENZY x5 0:32 / DROP STORM 0:12)
	local chips = make("Frame", {
		Name = "BuffChips", -- 휴대폰 배치에서 init.client가 찾아 옮긴다
		Size = UDim2.fromOffset(300, 28),
		-- 왼쪽 버튼 줄(도감 118·일일 선물 164·펫 210·친구 초대 256, 각 높이 40) 아래 (2026-10-20 초대 버튼이 생겨 256 → 302)
		Position = UDim2.fromOffset(12, 302),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	local function chip(color: Color3, order: number): TextLabel
		local c = label({
			Size = UDim2.fromOffset(147, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			TextColor3 = THEME.accentInk,
			Text = "",
			Visible = false,
			LayoutOrder = order,
			Parent = chips,
		})
		corner(10).Parent = c
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = c })
		return c
	end
	local frenzyChip = chip(FRENZY, 1)
	local stormChip = chip(STORM, 2)
	for c, icon in { [frenzyChip] = "Frenzy", [stormChip] = "Rain" } do
		if
			Ui.icon(icon, {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.new(0, -34, 0.5, 0), -- 자식은 여백(24) 안쪽 기준
				AnchorPoint = Vector2.new(0, 0.5),
				ZIndex = 3,
				Parent = c,
			})
		then
			(c:FindFirstChildOfClass("UIPadding") :: UIPadding).PaddingLeft = UDim.new(0, 24)
		end
	end

	-- 피버 화면 가장자리 틴트
	local tintGui = make("ScreenGui", {
		Name = "EventsTint",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = -1,
		Parent = gui.Parent,
	}) :: ScreenGui
	local tint = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = FEVER,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Parent = tintGui,
	}) :: Frame
	make("UIGradient", {
		-- 가운데는 투명, 가장자리만 물듦
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.18, 1),
			NumberSequenceKeypoint.new(0.82, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = tint,
	})

	-- 황금 큐브 버튼: 터치·마우스는 큐브를 직접 눌러도 되고, 게임패드·멀리 있을 때는 이 버튼 (L1 / G)
	local goldenId: number? = nil
	local claimedId: number? = nil
	local function claimGolden()
		local id = goldenId
		if id then
			goldenId = nil -- 중복 호출 방지 (서버가 다시 검증)
			claimedId = id
			task.spawn(function()
				(ev.ClaimGolden :: RemoteFunction):InvokeServer(id)
			end)
		end
	end
	local goldenButton = button({
		Name = "GoldenButton",
		-- 아래 가운데: 위쪽에 두면 트레이와 황금 큐브 자체를 가린다 (플레이테스트 2026-10-18)
		Size = UDim2.fromOffset(280, 64),
		Position = UDim2.new(0.5, 0, 1, -88), -- 좁은 화면에서 CORES 버튼 줄과 겹치지 않게 그 위로
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = GOLD,
		TextColor3 = THEME.accentInk,
		Text = "GOLDEN CUBE!",
		Visible = false,
		Parent = gui,
	}, claimGolden)
	local goldenIcon = Ui.addIcon(goldenButton, "Star", 1.3)
	if goldenIcon then
		Ui.wiggle(goldenIcon, 12)
	end
	Ui.shine(goldenButton, 1.2)
	local goldenScale = make("UIScale", { Parent = goldenButton }) :: UIScale

	local function bindGolden(on: boolean)
		if on then
			ContextActionService:BindAction("ClaimGolden", function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					claimGolden()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonL1, Enum.KeyCode.G)
		else
			ContextActionService:UnbindAction("ClaimGolden")
		end
	end

	-- 서버 배너 -------------------------------------------------------------------
	local banner = make("Frame", {
		Name = "Announce",
		Size = UDim2.fromOffset(560, 56),
		Position = UDim2.new(0.5, 0, 0, -80),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(16) }) :: Frame
	local bannerStroke = make("UIStroke", { Color = GOLD, Thickness = 3, Parent = banner }) :: UIStroke
	local bannerText = label({
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		Text = "",
		TextColor3 = GOLD,
		ZIndex = 21,
		Parent = banner,
	})
	-- 배너 양쪽 별
	for _, side in { -1, 1 } do
		local star = Ui.icon("Star", {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.new(if side < 0 then 0 else 1, side * 6, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 22,
			Parent = banner,
		})
		if star then
			Ui.wiggle(star, 15)
		end
	end
	local bannerSeq = 0

	local function systemChat(text: string, color: Color3)
		pcall(function()
			local channels = TextChatService:FindFirstChild("TextChannels")
			local sys = channels and channels:FindFirstChild("RBXSystem") :: TextChannel?
			if sys then
				sys:DisplaySystemMessage(`<font color="#{color:ToHex()}">[!] {text}</font>`)
			else
				-- 구형 채팅(LegacyChatService, rojo 빌드 기본값) 대체 경로
				game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", { Text = `[!] {text}`, Color = color })
			end
		end)
	end

	local function showBanner(text: string, kind: string, translated: boolean)
		if gui:GetAttribute("InRaid") then
			return -- 레이드 중엔 배너 없음 (채팅에는 남는다)
		end
		bannerSeq += 1
		local seq = bannerSeq
		local color = if kind == "jackpot" then GOLD else Color3.fromRGB(150, 230, 255)
		if translated then
			Loc.raw(bannerText, text)
		else
			Loc.plain(bannerText, text)
		end
		bannerText.TextColor3 = color
		bannerStroke.Color = color
		banner.Visible = true
		banner.Position = UDim2.new(0.5, 0, 0, -80)
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 12) })
			:Play()
		Fx.sound("Chime", nil, 0.5, 1.2)
		Fx.sound("Sparkle", nil, 0.4, 1)
		task.delay(EventsConfig.BANNER_SECONDS, function()
			if bannerSeq ~= seq then
				return
			end
			local t = TweenService:Create(banner, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -80) })
			t:Play()
			t.Completed:Wait()
			if bannerSeq == seq then
				banner.Visible = false
			end
		end)
	end
	-- args가 있으면 text는 Strings 키 (server/Events announce)
	(ev.Announce :: RemoteEvent).OnClientEvent:Connect(function(key: string, kind: string, args: Loc.Args?)
		local text = if args then Loc.format(key, args) else key
		showBanner(text, kind, args ~= nil)
		systemChat(text, if kind == "jackpot" then GOLD else Color3.fromRGB(150, 230, 255))
	end)

	-- 연출 -----------------------------------------------------------------------
	local bgm: Sound? = nil
	local function findBgm(): Sound?
		if bgm and bgm.Parent then
			return bgm
		end
		for _, s in SoundService:GetChildren() do
			if s:IsA("Sound") and s.SoundId == Config.BGM then
				bgm = s
				return s
			end
		end
		return nil
	end

	local function goldenSpawned(part: Instance?)
		Fx.sound("Sparkle", nil, 0.6, 1.4)
		Fx.sound("Chime", nil, 0.5, 1.6)
		Fx.screenFlash(Color3.fromRGB(255, 230, 120), 0.12, 0.35)
		if part and part:IsA("BasePart") then
			-- 벽 뒤에서도 보이게 (로컬 전용)
			make("Highlight", {
				FillColor = GOLD,
				OutlineColor = Color3.fromRGB(255, 255, 220),
				FillTransparency = 0.6,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				Parent = part,
			})
			Fx.burst("Sparkle", part.Position, 20, 1.4, GOLD)
		end
	end

	local REWARD_COLOR: { [string]: Color3 } = {
		cash = GOLD,
		frenzy = FRENZY,
		storm = STORM,
		rain = Color3.fromRGB(150, 255, 150),
		jackpot = Color3.fromRGB(255, 240, 150),
	}

	local function goldenClaimed(at: Vector3, reward: string, text: Loc.Text)
		local color = REWARD_COLOR[reward] or GOLD
		local big = reward == "jackpot"
		Fx.sound("Coin", nil, 0.7, 1)
		Fx.sound("LevelUp", nil, 0.55, if big then 0.8 else 1.1)
		Fx.sound("Sparkle", at, 0.6, 1.2)
		if big then
			Fx.sound("Boom", nil, 0.6, 1)
			Fx.sound("Fanfare", nil, 0.6, 1)
		end
		Fx.screenFlash(color, if big then 0.7 else 0.4, if big then 0.9 else 0.5)
		Fx.burst("Chunk", at, if big then 90 else 50, 1.4, GOLD)
		Fx.burst("Sparkle", at, if big then 80 else 40, 1.6, color)
		Fx.burst("Glow", at, 1, if big then 4 else 2.5, color)
		Fx.popup(at + Vector3.new(0, 4, 0), text, color, if big then 2.6 else 2, if big then 2.6 else 1.8)
		Fx.shake(if big then 0.8 else 0.45)
		Fx.fovPunch(if big then 10 else 6)
		Fx.bump(goldenButton, 0.3)
		if reward == "storm" and plotCenter then
			Fx.factoryWave(plotCenter, 26, Loc.msg("events.waveStorm", { n = 3 }), STORM)
		elseif reward == "frenzy" and plotCenter then
			Fx.factoryWave(plotCenter, 26, Loc.msg("events.waveFrenzy", { mult = EventsConfig.FRENZY_MULT }), FRENZY)
		end
	end

	local function feverStarted(at: Vector3)
		Fx.sound("LevelUp", nil, 0.6, 1.3)
		Fx.sound("Impact", nil, 0.5, 1)
		Fx.screenFlash(FEVER, 0.45, 0.6)
		Fx.factoryWave(
			at - Vector3.new(0, 4, 0),
			28,
			Loc.msg("events.waveFever", { mult = EventsConfig.FEVER_MULT }),
			FEVER
		)
		Fx.burst("Chunk", at, 50, 1.3, FEVER)
		Fx.shake(0.5)
		Fx.fovPunch(6)
		Fx.bump(bar, 0.25)
	end
	(ev.EventFx :: RemoteEvent).OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
		if kind == "goldenSpawn" then
			goldenSpawned(a)
		elseif kind == "golden" then
			goldenClaimed(a, b, c)
		elseif kind == "fever" then
			feverStarted(a)
		end
	end)

	-- 상태 수신 -------------------------------------------------------------------
	local wasFever = false
	(main.State :: RemoteEvent).OnClientEvent:Connect(function(s)
		plotCenter = s.plotCenter
		local e = s.events
		if not e then
			return
		end
		local g = e.golden
		goldenId = if g and g.id ~= claimedId then g.id else nil
		events = e
		recvAt = os.clock()
	end)

	local function left(v: number?): number
		if not v then
			return 0
		end
		return math.max(0, v - (os.clock() - recvAt))
	end

	local feverPulse = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local e = events
		if not e then
			return
		end
		local fever = left(e.fever)
		local inFever = fever > 0
		if inFever then
			fill.Size = UDim2.fromScale(fever / EventsConfig.FEVER_SECONDS, 1)
			Loc.set(barText, "events.feverOn", { mult = EventsConfig.FEVER_MULT, time = EventsConfig.clock(fever) })
			fillGrad.Rotation = (os.clock() * 120) % 360
			feverPulse += dt
			tint.BackgroundTransparency = 0.3 + math.sin(os.clock() * 8) * 0.1
			if feverPulse >= 0.3 and plotCenter then
				feverPulse = 0
				local c = plotCenter :: Vector3
				Fx.burst("Sparkle", c + Vector3.new(math.random(-18, 18), 6, math.random(-18, 18)), 4, 1, FEVER)
			end
		else
			fill.Size = UDim2.fromScale(math.clamp(e.gauge / e.goal, 0, 1), 1)
			Loc.set(barText, "events.feverGauge", { n = math.floor(e.gauge), goal = e.goal })
			fillGrad.Rotation = 0
			tint.BackgroundTransparency = 1
		end
		if inFever ~= wasFever then
			wasFever = inFever
			local m = findBgm()
			if m then
				m.PlaybackSpeed = if inFever then 1.12 else 1
			end
		end

		local frenzy = left(e.frenzy)
		frenzyChip.Visible = frenzy > 0
		Loc.set(frenzyChip, "events.frenzy", { mult = EventsConfig.FRENZY_MULT, time = EventsConfig.clock(frenzy) })
		local storm = left(e.storm)
		stormChip.Visible = storm > 0
		Loc.set(stormChip, "events.storm", { time = EventsConfig.clock(storm) })

		local g = e.golden
		local gl = if g and goldenId == g.id then left(g.left) else 0
		local show = gl > 0
		if show ~= goldenButton.Visible then
			goldenButton.Visible = show
			bindGolden(show)
		end
		if show then
			Loc.set(goldenButton, "events.golden", { hint = Ui.hint("[G]", "TAP", "[L1]"), n = math.ceil(gl) })
			goldenScale.Scale = 1 + math.sin(os.clock() * 7) * 0.05
		end
	end)
end

return EventsUi
