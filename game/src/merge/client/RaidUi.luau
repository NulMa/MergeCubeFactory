--!strict
-- 보스 레이드 화면 (docs/25_RAID.md, 서버 server/Raid): 참여 묻기 → (JOIN 즉시 하늘 전장, 대기) → 보스 체력·타수·패턴 안내 → 결과.
-- 승리 보너스(x2, 참여자만) 칩은 BuffChips 줄에 붙인다. 보스 코인 강화는 광장 BOSS SHOP 발판 (client/Stations).
-- 전장에 있는 동안 gui 속성 InRaid = true → 토스트·배너·출석·평가 창이 뜨지 않는다 (2026-10-20 사용자).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Core.Net)
local RaidRules = require(ReplicatedStorage.Game.Raid)
local EventsConfig = require(ReplicatedStorage.Game.EventsConfig)
local Ui = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Ui"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Loc = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Loc"))

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button
local player = Players.LocalPlayer

local BOSS = Color3.fromRGB(170, 90, 255)
local HP = Color3.fromRGB(255, 80, 140)

local RaidUi = {}

function RaidUi.init(gui: ScreenGui, _toast: (string) -> ())
	local rm = Net.client(RaidRules.REMOTES :: any)

	------------------------------------------------------------------
	-- 참여 묻기
	------------------------------------------------------------------
	local invite = make("Frame", {
		Name = "RaidInvite",
		Size = UDim2.fromOffset(380, 170),
		Position = UDim2.new(0.5, 0, 0, 126),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(16) }) :: Frame
	local inviteStroke = make("UIStroke", { Color = BOSS, Thickness = 3, Parent = invite }) :: UIStroke
	local inviteTitle = label({
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 8),
		Text = "BOSS RAID!",
		TextColor3 = BOSS,
		ZIndex = 21,
		Parent = invite,
	})
	local REWARD_TEXT =
		`Win: BOSS COINS + x{RaidRules.BUFF_MULT} income for {RaidRules.BUFF_SECONDS // 60} min. Get hit {RaidRules.LIVES} times = out!`
	local inviteBlurb = label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 44),
		Text = `Hit the boss with your bat together. {REWARD_TEXT}`,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.ink,
		ZIndex = 21,
		Parent = invite,
	})
	local inviteInfo = label({
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 86),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.dim,
		ZIndex = 21,
		Parent = invite,
	})
	local joinedMe = false
	local inviteLeft, inviteJoined, inviteAt = 0, 0, os.clock()
	local seenInvite: any = nil -- 이미 띄운 초대 번호 (늦게 들어와도 이번 초대 창을 한 번 띄운다)

	-- 전장에서는 공장 버튼을 숨긴다 (2026-10-21 리뷰). 지갑·버프 칩·배트/DROP·레이드 화면은 남김
	local KEEP = {
		RaidInvite = true,
		RaidHud = true,
		RaidCallout = true,
		RaidCrit = true,
		RaidResult = true,
		BuffChips = true,
		PanelBackdrop = true,
	}
	local hidden: { GuiObject } = {}
	local function hideHud(on: boolean)
		if on then
			for _, c in gui:GetChildren() do
				if
					c:IsA("GuiObject")
					and c.Visible
					and not KEEP[c.Name]
					and not c:GetAttribute("RaidKeep")
					and (c:IsA("GuiButton") or c.Name == "FeverBar")
				then
					local o = c :: GuiObject
					o.Visible = false
					table.insert(hidden, o)
				end
			end
		else
			for _, c in hidden do
				c.Visible = true
			end
			table.clear(hidden)
		end
	end

	local function setRaid(on: boolean)
		if on ~= joinedMe then
			hideHud(on)
		end
		joinedMe = on
		gui:SetAttribute("InRaid", if on then true else nil)
	end
	local onJoined: () -> () -- 아래 HUD를 만든 뒤 채운다
	local joinButton = button({
		Size = UDim2.new(0.5, -15, 0, 50),
		Position = UDim2.new(0, 10, 1, -60),
		Text = "JOIN",
		BackgroundColor3 = THEME.good,
		TextColor3 = THEME.accentInk,
		ZIndex = 21,
		Parent = invite,
	}, function()
		if joinedMe then
			return
		end
		-- 누르면 창을 닫고 바로 전장으로 (서버가 옮긴다)
		invite.Visible = false
		setRaid(true)
		local ok = (rm.RaidJoin :: RemoteFunction):InvokeServer(true)
		if ok then
			Fx.sound("LevelUp", nil, 0.5, 1.1)
			onJoined()
		else
			setRaid(false)
		end
	end)
	button({
		Size = UDim2.new(0.5, -15, 0, 50),
		Position = UDim2.new(0.5, 5, 1, -60),
		Text = "NO THANKS",
		ZIndex = 21,
		Parent = invite,
	}, function()
		invite.Visible = false
		task.spawn(function()
			(rm.RaidJoin :: RemoteFunction):InvokeServer(false) -- 모두 답하면 기다리지 않고 시작하게
		end)
	end)
	Ui.touchFit(gui, invite, 1.4)

	------------------------------------------------------------------
	-- 전투 HUD (참여자): 위 가운데, 목표 바 자리 아래
	------------------------------------------------------------------
	local hud = make("Frame", {
		Name = "RaidHud",
		Size = UDim2.fromOffset(440, 74),
		Position = UDim2.new(0.5, 0, 0, 74),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 15,
		Parent = gui,
	}, { corner(14) }) :: Frame
	local hudStroke = make("UIStroke", { Color = BOSS, Thickness = 2, Parent = hud }) :: UIStroke
	local hpBack = make("Frame", {
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 8),
		BackgroundColor3 = Color3.fromRGB(30, 20, 40),
		ZIndex = 16,
		Parent = hud,
	}, { corner(8) }) :: Frame
	local hpFill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = HP,
		ZIndex = 17,
		Parent = hpBack,
	}, { corner(8) }) :: Frame
	local hpText = label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 18,
		Parent = hpBack,
	})
	Ui.touchFit(gui, hud, 1.3)
	local hudInfo = label({
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 40),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.ink,
		ZIndex = 16,
		Parent = hud,
	})
	local callout = label({
		Name = "RaidCallout",
		Size = UDim2.fromOffset(420, 70),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 90),
		Visible = false,
		ZIndex = 25,
		Parent = gui,
	})
	local calloutScale = make("UIScale", { Parent = callout }) :: UIScale
	local function shout(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		callout.Visible = true
		calloutScale.Scale = 1.5
		TweenService:Create(calloutScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local token = os.clock()
		callout:SetAttribute("At", token)
		task.delay(seconds, function()
			if callout:GetAttribute("At") == token then
				callout.Visible = false
			end
		end)
	end

	-- 크리티컬 표시 (화면 가운데 조금 아래, 짧게)
	local critLabel = label({
		Name = "RaidCrit",
		Size = UDim2.fromOffset(260, 56),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "CRIT! x2",
		TextColor3 = Color3.fromRGB(255, 90, 60),
		Visible = false,
		ZIndex = 26,
		Parent = gui,
	})
	local critScale = make("UIScale", { Parent = critLabel }) :: UIScale
	local function showCrit()
		critLabel.Visible = true
		critLabel.Rotation = math.random(-8, 8)
		critScale.Scale = 1.8
		TweenService:Create(critScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local token = os.clock()
		critLabel:SetAttribute("At", token)
		task.delay(0.6, function()
			if critLabel:GetAttribute("At") == token then
				critLabel.Visible = false
			end
		end)
	end

	-- 전장으로 옮겨진 뒤 카메라를 보스 쪽으로 돌린다
	local function faceBoss()
		task.delay(0.5, function()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local boss = workspace:FindFirstChild("RaidBoss") :: BasePart?
			local cam = workspace.CurrentCamera
			if root and boss and cam then
				local flat = (boss.Position - root.Position) * Vector3.new(1, 0, 1)
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
				cam.CFrame = CFrame.lookAt(root.Position - dir * 14 + Vector3.new(0, 7, 0), boss.Position)
			end
		end)
	end

	-- 배트를 손에 쥐어 준다 (보스는 배트로만 때림)
	local function equipBat()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		local bat = backpack and backpack:FindFirstChild("Bat")
		if hum and bat and bat:IsA("Tool") and not (char :: Model):FindFirstChild("Bat") then
			hum:EquipTool(bat)
		end
	end

	------------------------------------------------------------------
	-- 결과
	------------------------------------------------------------------
	local result = make("Frame", {
		Name = "RaidResult",
		Size = UDim2.fromOffset(400, 180),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	}, { corner(16) }) :: Frame
	make("UIStroke", { Color = BOSS, Thickness = 3, Parent = result })
	local resultTitle = label({
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.fromOffset(10, 10),
		Text = "",
		ZIndex = 31,
		Parent = result,
	})
	local resultSub = label({
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.fromOffset(10, 60),
		Text = "",
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.ink,
		ZIndex = 31,
		Parent = result,
	})
	Ui.touchFit(gui, result, 1.4)
	local resultScale = result:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = result })

	------------------------------------------------------------------
	-- 서버 보너스 칩 (BuffChips 줄)
	------------------------------------------------------------------
	local buffLeft, buffAt = 0, os.clock()
	local chip: TextLabel? = nil
	task.spawn(function()
		local chips = gui:WaitForChild("BuffChips", 10)
		if not chips then
			return
		end
		local c = label({
			Name = "RaidChip",
			Size = UDim2.fromOffset(147, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = BOSS,
			TextColor3 = THEME.accentInk,
			Text = "",
			Visible = false,
			LayoutOrder = 3,
			Parent = chips,
		})
		corner(10).Parent = c
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = c })
		chip = c
	end)

	------------------------------------------------------------------
	-- 서버 이벤트
	------------------------------------------------------------------
	local bossName = "BOSS CUBE"
	local fighting = false
	local waiting = false -- JOIN 뒤 전투 시작 전 (전장에서 대기)
	local fight: { [string]: any }? = nil
	local fightAt = os.clock()

	onJoined = function()
		waiting = true
		hud.Visible = true
		hpFill.Size = UDim2.fromScale(1, 1)
		Loc.plain(hpText, bossName)
		equipBat()
		faceBoss()
	end

	local function render()
		if waiting and not fighting then
			local left = math.max(0, inviteLeft - (os.clock() - inviteAt))
			Loc.set(hudInfo, "raid.getReady", { s = math.ceil(left), n = inviteJoined })
			return
		end
		local f = fight
		if not f then
			return
		end
		local hp, maxHp = f.hp or 0, math.max(1, f.maxHp or 1)
		hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		Loc.set(hpText, "raid.hp", { boss = bossName, hp = hp, max = maxHp })
		local left = math.max(0, (f.left or 0) - (os.clock() - fightAt))
		Loc.set(hudInfo, "raid.hits", { time = EventsConfig.clock(left), n = f.hits or 0 })
	end

	(rm.Raid :: RemoteEvent).OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any)
		if kind == "invite" then
			inviteLeft, inviteJoined, inviteAt = a, b, os.clock()
			-- 이번 보스 (로테이션): 이름·색·한 줄 설명
			local def = RaidRules.boss(c)
			bossName = def.name
			local col = Color3.fromRGB(def.glow[1], def.glow[2], def.glow[3])
			inviteTitle.Text = `BOSS RAID: {def.name}!`
			inviteTitle.TextColor3 = col
			inviteStroke.Color = col
			hudStroke.Color = col
			inviteBlurb.Text = `{def.blurb}. {REWARD_TEXT}`
			-- 초대 번호마다 한 번만 연다 (이미 답해 닫은 창은 인원 갱신으로 다시 열지 않는다).
			-- 초대 중에 들어온 사람도 남은 시간이 있으면 받는다 (2026-10-21 리뷰: 예전엔 첫 1초에만 열림)
			local id = d
			if id ~= seenInvite and inviteLeft > 2 and not joinedMe then
				seenInvite = id
				Fx.sound("Fanfare", nil, 0.4, 1.2)
				invite.Visible = true
			end
		elseif kind == "wait" then
			inviteLeft, inviteAt = tonumber(a) or inviteLeft, os.clock()
			if not waiting then
				setRaid(true)
				onJoined()
			end
		elseif kind == "start" then
			invite.Visible = false
			fight = a
			fightAt = os.clock()
			fighting = true
			waiting = false
			setRaid(true)
			hud.Visible = true
			equipBat()
			shout("BEAT THE BOSS!", BOSS, 2)
			Fx.sound("Boom", nil, 0.6, 0.9)
			render()
		elseif kind == "hit" then
			if a == true then
				showCrit()
				Fx.sound("Boom", nil, 0.35, 1.6)
			end
		elseif kind == "tick" then
			fight = a
			fightAt = os.clock()
			render()
		elseif kind == "pattern" then
			local warn = Color3.fromRGB(255, 120, 120)
			if a == "slam" then
				shout(Ui.hint("JUMP! (SPACE)", "JUMP!", "JUMP! (A)"), warn, 1.6)
			elseif a == "laser" then
				shout(Ui.hint("JUMP THE LASER! (SPACE)", "JUMP THE LASER!", "JUMP THE LASER! (A)"), warn, 2)
			elseif a == "pounce" then
				shout("IT'S LEAPING AT YOU! MOVE!", warn, 1.8)
			elseif a == "storm" then
				shout("GET IN A GREEN CIRCLE!", Color3.fromRGB(120, 255, 140), 2.4)
			elseif a == "spokes" then
				shout("DODGE THE ROLLING ROCKS!", warn, 1.8)
			elseif a == "enrage" then
				shout(`{bossName} IS ENRAGED!`, Color3.fromRGB(255, 70, 70), 2)
				Fx.sound("Boom", nil, 0.5, 0.7)
			else
				shout("MOVE OUT OF THE RED!", warn, 1.6)
			end
		elseif kind == "hurt" then
			local stun = tonumber(a) or RaidRules.STUN
			gui:SetAttribute("StunUntil", os.clock() + stun) -- Bat: SWING 회색·누르고 있기 멈춤
			local lives = tonumber(b)
			if lives and lives > 0 then
				shout(`STUNNED!  {string.rep("♥", lives)} LEFT`, Color3.fromRGB(255, 120, 120), math.min(stun, 1.4))
			end
			render()
		elseif kind == "out" then
			-- 목숨을 다 잃음: 이번 보스전 실패 → 서버가 곧 집으로 보낸다. 보스가 잡히면 기여 보상
			hud.Visible = false
			fight = nil
			fighting = false
			waiting = false
			shout("YOU'RE OUT!", Color3.fromRGB(255, 80, 80), 2.5)
			Fx.sound("Boom", nil, 0.5, 0.6)
			task.delay(2, function()
				if not fighting and not waiting then
					setRaid(false)
				end
			end)
		elseif kind == "end" then
			local win, coins, buff, hits, out = a == true, tonumber(b) or 0, tonumber(c) or 0, d, e == true
			hud.Visible = false
			callout.Visible = false
			critLabel.Visible = false
			fight = nil
			waiting = false
			if buff > 0 then
				buffLeft, buffAt = buff, os.clock()
			end
			-- 결과 창이 닫히고 집에 간 뒤 알림을 다시 받는다
			task.delay(RaidRules.RESULT + 0.5, function()
				if not fighting and not waiting then
					setRaid(false)
				end
			end)
			if hits ~= nil then
				result.Visible = true
				resultTitle.Text = if win then "BOSS DEFEATED!" else "THE BOSS GOT AWAY..."
				resultTitle.TextColor3 = if win then Color3.fromRGB(255, 220, 90) else THEME.dim
				local coinText = if coins > 0 and out
					then Loc.format("raid.coinsOut", { n = coins })
					elseif coins > 0 then Loc.format("raid.coins", { n = coins })
					elseif not win then Loc.format("raid.noReward")
					else Loc.format("raid.minHits", { n = RaidRules.MIN_HITS })
				Loc.raw(
					resultSub,
					Loc.format("raid.result", { n = hits, coins = coinText })
						.. (if buff > 0
							then "\n" .. Loc.format(
								"raid.buff",
								{ mult = RaidRules.BUFF_MULT, mins = RaidRules.BUFF_SECONDS // 60 }
							)
							else "")
						.. (if coins > 0 then "\n" .. Loc.format("raid.spend") else "")
				)
				local base = (result:GetAttribute("FitScale") :: number?) or 1
				resultScale.Scale = base * 0.6
				TweenService:Create(resultScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = base }):Play()
				if win then
					Fx.sound("Fanfare", nil, 0.7)
					Fx.screenFlash(Color3.fromRGB(255, 230, 140), 0.4, 0.6)
				end
				task.delay(RaidRules.RESULT, function()
					result.Visible = false
				end)
			end
			fighting = false
		elseif kind == "idle" then
			invite.Visible = false
			hud.Visible = false
			waiting = false
			fighting = false
			setRaid(false)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if invite.Visible then
			local left = math.max(0, inviteLeft - (os.clock() - inviteAt))
			Loc.set(inviteInfo, "raid.startsIn", { s = math.ceil(left), n = inviteJoined })
			if left <= 0 then
				invite.Visible = false
			end
		end
		if fighting or waiting then
			render()
		end
		-- 숨긴 공장 버튼을 다른 화면 코드가 다시 켜면 다시 숨긴다
		for _, h in hidden do
			if h.Visible then
				h.Visible = false
			end
		end
		local c = chip
		if c then
			local left = buffLeft - (os.clock() - buffAt)
			c.Visible = left > 0
			if left > 0 then
				Loc.set(c, "raid.chip", { mult = RaidRules.BUFF_MULT, time = EventsConfig.clock(left) })
			end
		end
	end)

	-- 접속했을 때 이미 서버 보너스가 돌고 있으면 상태에서 받는다
	local self = {}
	function self.render(s: { [string]: any })
		local r = s.raid
		if r and r.buff and r.buff > 0 and buffLeft - (os.clock() - buffAt) <= 0 then
			buffLeft, buffAt = r.buff, os.clock()
		end
	end
	return self
end

return RaidUi
