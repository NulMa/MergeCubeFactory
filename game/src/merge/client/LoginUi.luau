--!strict
-- 7일 출석 창 + 친구 초대 버튼 (2026-10-20 "재방문 장치랑 친구보너스", 서버 server/Daily·Plots.friendsTogether).
-- 출석: 오늘 칸을 아직 안 받았으면 접속 때 한 번 띄운다. 보상은 고정 (shared/Daily.LOGIN).
-- 초대: 왼쪽 버튼 줄 펫 버튼 아래. 친구와 같은 공장에 있으면 둘 다 수입 보너스 (Config.TEAM_BONUS).

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Game.Config)
local Ui = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Ui"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Loc = require(ReplicatedStorage:WaitForChild("CoreClient"):WaitForChild("Loc"))

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button
local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 205, 70)

local LoginUi = {}

type Opts = { gui: ScreenGui, remotes: { [string]: Instance }, toast: (Loc.Text) -> () }

function LoginUi.new(opts: Opts)
	local gui = opts.gui
	local claim = opts.remotes.ClaimLogin :: RemoteFunction

	------------------------------------------------------------------
	-- 출석 창
	------------------------------------------------------------------
	local panel = make("Frame", {
		Name = "LoginPanel",
		Size = UDim2.fromOffset(470, 250),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 22,
		Parent = gui,
	}, { corner(16) }) :: Frame
	make("UIStroke", { Color = GOLD, Thickness = 3, Parent = panel })
	label({
		Size = UDim2.new(1, -70, 0, 34),
		Position = UDim2.fromOffset(14, 10),
		Text = "7-DAY LOGIN",
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = panel,
	})
	label({
		Size = UDim2.new(1, -70, 0, 18),
		Position = UDim2.fromOffset(14, 44),
		Text = "Come back each day for the next reward",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = panel,
	})
	button({
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -10, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Text = "X",
		BackgroundColor3 = THEME.bad,
		ZIndex = 23,
		Parent = panel,
	}, function()
		panel.Visible = false
	end)
	local row = make("Frame", {
		Size = UDim2.new(1, -20, 0, 96),
		Position = UDim2.fromOffset(10, 70),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = panel,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	type Cell = { frame: Frame, day: TextLabel, text: TextLabel, stroke: UIStroke }
	local cells: { Cell } = {}
	for i = 1, 7 do
		local f = make("Frame", {
			Size = UDim2.new(1 / 7, -6, 1, 0),
			BackgroundColor3 = THEME.card,
			LayoutOrder = i,
			ZIndex = 23,
			Parent = row,
		}, { corner(10) }) :: Frame
		local stroke = make("UIStroke", { Color = GOLD, Thickness = 3, Transparency = 1, Parent = f }) :: UIStroke
		local day = label({
			Size = UDim2.new(1, -6, 0, 22),
			Position = UDim2.fromOffset(3, 4),
			Text = `DAY {i}`,
			ZIndex = 24,
			Parent = f,
		})
		local text = label({
			Size = UDim2.new(1, -6, 1, -32),
			Position = UDim2.fromOffset(3, 28),
			Text = "",
			TextWrapped = true,
			Font = Enum.Font.GothamBold,
			TextColor3 = THEME.ink,
			ZIndex = 24,
			Parent = f,
		})
		cells[i] = { frame = f, day = day, text = text, stroke = stroke }
	end
	local claimButton: TextButton
	claimButton = button({
		Size = UDim2.new(1, -20, 0, 56),
		Position = UDim2.new(0, 10, 1, -66),
		Text = "CLAIM",
		BackgroundColor3 = THEME.good,
		TextColor3 = THEME.accentInk,
		ZIndex = 23,
		Parent = panel,
	}, function()
		local text = claim:InvokeServer()
		if text then
			Fx.purchase(claimButton)
			Fx.sound("Fanfare", nil, 0.5, 1.1)
			opts.toast(text)
			task.delay(0.8, function()
				panel.Visible = false
			end)
		end
	end)
	Ui.shine(claimButton, 2.5)
	Ui.touchFit(gui, panel, 1.4)
	local scale = panel:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = panel })

	local shownOnce = false
	local function open()
		-- 보스 레이드 참여 창이 떠 있으면 그게 닫힌 뒤에 (두 창이 겹쳤다, Studio 2026-10-20)
		-- 레이드 중이면 끝나고 집에 온 뒤에
		local raid = gui:FindFirstChild("RaidInvite") :: GuiObject?
		while (raid and raid.Visible) or gui:GetAttribute("InRaid") do
			task.wait(1)
		end
		local base = (panel:GetAttribute("FitScale") :: number?) or 1
		panel.Visible = true
		scale.Scale = base * 0.6
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = base }):Play()
	end

	-- 레이드 참여 창이 뜨면 출석 창은 잠시 접었다가 그 창이 닫힌 뒤 다시 연다
	task.spawn(function()
		local raid = gui:WaitForChild("RaidInvite", 20) :: GuiObject?
		if not raid then
			return
		end
		local reopen = false
		raid:GetPropertyChangedSignal("Visible"):Connect(function()
			if raid.Visible and panel.Visible then
				panel.Visible = false
				reopen = true
			elseif not raid.Visible and reopen then
				reopen = false
				task.delay(1, open)
			end
		end)
	end)

	-- 일일 선물 창 머리에서도 다시 열 수 있게
	task.spawn(function()
		local daily = gui:WaitForChild("DailyPanel", 10)
		if daily then
			button({
				Size = UDim2.fromOffset(96, 40),
				Position = UDim2.new(1, -56, 0, 8),
				AnchorPoint = Vector2.new(1, 0),
				Text = "7-DAY",
				BackgroundColor3 = GOLD,
				TextColor3 = THEME.accentInk,
				Parent = daily,
			}, open)
		end
	end)

	------------------------------------------------------------------
	-- 친구 초대 버튼
	------------------------------------------------------------------
	local friendPct = math.floor((Config.TEAM_BONUS[1] or 0) * 100 + 0.5)
	local invite = button({
		Name = "InviteButton",
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.fromOffset(12, 256), -- 펫 버튼(210) 아래, 버프 칩 줄은 그 아래로 (init.client)
		BackgroundColor3 = Color3.fromRGB(90, 170, 255),
		Text = `INVITE FRIENDS  +{friendPct}% TOGETHER`,
		ZIndex = 3,
		Parent = gui,
	}, function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		else
			opts.toast("Invites aren't available on this account")
		end
	end)

	local self = { panel = panel, invite = invite }
	function self.render(s: { [string]: any })
		local l = s.login
		if not l then
			return
		end
		for i, c in cells do
			local done = i < l.index or (i == l.index and l.claimed)
			local today = i == l.index and not l.claimed
			c.text.Text = if l.days and l.days[i] then l.days[i] else ""
			c.frame.BackgroundColor3 = if done
				then Color3.fromRGB(60, 90, 70)
				elseif today then Color3.fromRGB(90, 80, 40)
				else THEME.card
			c.stroke.Transparency = if today then 0 else 1
			c.day.Text = if done then `DAY {i} ✓` else `DAY {i}`
		end
		claimButton.Visible = not l.claimed
		if not l.claimed and not shownOnce then
			shownOnce = true
			task.delay(2, open) -- 오프라인 수익 창 등 접속 창이 먼저 뜨게 잠깐 뒤
		end
		-- 친구와 같이 있으면 버튼이 지금 보너스를 보여 준다
		local n = s.visitors or 0
		invite.Text = if n > 0
			then `FRIENDS HERE x{n}  +{math.floor((Config.TEAM_BONUS[math.min(n, 3)] or 0) * 100 + 0.5)}%`
			else `INVITE FRIENDS  +{friendPct}% TOGETHER`
	end
	return self
end

return LoginUi
