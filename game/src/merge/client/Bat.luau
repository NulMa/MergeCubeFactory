--!strict
-- 배트 휘두르기 (클라). 도구(서버 Factory.makeBat)를 들고 클릭/탭 → 스윙 애니메이션 + 임팩트 순간 서버 Swing.
-- 실제로 밀치는 건 서버(범위·쿨다운·내 큐브만). 여기서는 반응만: 바람 소리 → 맞으면 히트스톱 + 쿵 + 흔들림 + 글자.
--
-- 애니메이션: 자작 KeyframeSequence(game/tools/anim/bat_swing.luau → AssetIds.Anims.BatSwing).
-- 내 캐릭터 Animator에서 튼 애니메이션은 Roblox가 다른 플레이어에게도 복제한다 (2026-10-19)
-- 젖힘 0.10 → 임팩트 0.16 → 따라가기 0.26 → 복귀 0.55 (초, 속도 1 기준)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage").Game
local AssetIds = require(Shared.AssetIds)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Ui = require(game:GetService("ReplicatedStorage").CoreClient.Ui)

local player = Players.LocalPlayer
local Bat = {}

local REST = CFrame.new(0, -1.6, 0)
local IMPACT = 0.16
local LENGTH = 0.55
local HITSTOP = 0.07

local swingAnim = Instance.new("Animation")
swingAnim.AnimationId = (AssetIds :: any).Anims.BatSwing

local tracks: { [Model]: AnimationTrack } = {}
local swingHeld: (() -> ())? = nil -- 손에 든 배트로 휘두르기 (휴대폰 SWING 버튼)
-- 누르고 있으면 계속 휘두른다 (2026-10-21 리뷰: 레이드 한 판에 40~240번 탭. 사용자 "계속 눌러도 1번만" → 어디서나).
-- 간격은 swing()의 쿨다운이라 탭과 같은 속도
local touchHold = false
local mouseHold = false

-- 레이드 중인가 (RaidUi가 FactoryHud에 InRaid 속성을 켬)
local function inRaid(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("FactoryHud")
	return hud ~= nil and hud:GetAttribute("InRaid") == true
end

-- 패턴에 맞아 경직 중인가 (RaidUi가 StunUntil = os.clock 기준 끝나는 때)
local function stunned(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("FactoryHud")
	local t = hud and hud:GetAttribute("StunUntil")
	return typeof(t) == "number" and os.clock() < t
end

local function trackFor(char: Model): AnimationTrack?
	local cached = tracks[char]
	if cached then
		return cached
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(swingAnim)
	end)
	if not ok then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	tracks[char] = track
	char.Destroying:Connect(function()
		tracks[char] = nil
	end)
	return track
end

-- 내 화면에선 서버 왕복을 기다리지 않고 궤적을 바로 켠다 (서버도 임팩트 때 켜서 남들에게 보임)
local function flashTrail(tool: Tool, seconds: number)
	local trail = tool:FindFirstChild("SwingTrail", true) :: Trail?
	if not trail then
		return
	end
	trail.Enabled = true
	task.delay(seconds, function()
		if trail.Parent then
			trail.Enabled = false
		end
	end)
end

function Bat.start(remote: RemoteFunction, getState: () -> { [string]: any }?, fx: any)
	local busyUntil = 0

	local function lv(stat: string): number
		local s = getState()
		local b = s and s.bat and s.bat[stat]
		return if b then b.lv else 0
	end

	local function swing(tool: Tool)
		local now = os.clock()
		if now < busyUntil then
			return
		end
		local cooldown = Economy.batCooldown(lv("speed"))
		busyUntil = now + cooldown
		tool.Grip = REST
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not char or not root then
			return
		end
		-- 쿨다운이 동작보다 짧으면(속도 강화) 그만큼 빨리 휘두른다
		local speed = math.max(1, LENGTH / cooldown)
		local track = trackFor(char)
		if track then
			track:Play(0.04, 1, speed)
		end
		fx.sound("Whoosh", nil, 0.5, 1.25 + math.random() * 0.2)
		flashTrail(tool, (IMPACT + 0.12) / speed)
		-- 서버 판정은 배트가 정면에 왔을 때 (동작과 결과가 맞게)
		task.delay(IMPACT / speed, function()
			local ok, hits = pcall(function()
				return remote:InvokeServer()
			end)
			if not (ok and typeof(hits) == "number" and hits > 0) then
				return
			end
			-- 히트스톱: 동작을 잠깐 멈춰 "걸리는" 느낌 + 화면 펀치
			if track and track.IsPlaying then
				track:AdjustSpeed(0)
				task.delay(HITSTOP, function()
					if track.IsPlaying then
						track:AdjustSpeed(speed)
					end
				end)
			end
			fx.fovPunch(3 + math.min(hits, 8) * 0.5)
			fx.shake(0.12)
			local r = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local st = getState()
				local skin = st and st.collection and Config.cosmetic(st.collection.equipped.bat or "")
				fx.batHit(
					r.Position + r.CFrame.LookVector * 4,
					hits,
					Economy.batRange(lv("range")),
					skin and skin.hitSound
				)
			end
		end)
	end

	swingHeld = function()
		local char = player.Character
		local tool = char and char:FindFirstChild("Bat")
		if tool and tool:IsA("Tool") then
			swing(tool)
		end
	end

	local function hook(tool: Instance)
		if not tool:IsA("Tool") or tool.Name ~= "Bat" or tool:GetAttribute("Hooked") then
			return
		end
		tool:SetAttribute("Hooked", true)
		-- 마우스·게임패드로 누르면 Activated, 떼면 Deactivated (UI 위 판정에 흔들리지 않게 도구 신호로)
		tool.Activated:Connect(function()
			mouseHold = true
			swing(tool)
		end)
		tool.Deactivated:Connect(function()
			mouseHold = false
		end)
		tool.Unequipped:Connect(function()
			mouseHold = false
		end)
	end

	local function watch(container: Instance)
		for _, c in container:GetChildren() do
			hook(c)
		end
		container.ChildAdded:Connect(hook)
	end

	-- 누르고 있으면 계속 (마우스·게임패드: 배트를 든 채 누른 채로, 터치: SWING 버튼을 누른 채로).
	-- 마우스를 놓친 Deactivated에 대비해 떼어져 있으면 끈다
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHold = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		local f = swingHeld
		if f and (touchHold or mouseHold) and not (inRaid() and stunned()) then
			f()
		end
	end)

	local backpack = player:WaitForChild("Backpack")
	watch(backpack)
	player.CharacterAdded:Connect(function(char)
		watch(char)
		local bp = player:WaitForChild("Backpack")
		if bp ~= backpack then
			backpack = bp
			watch(bp)
		end
	end)
	if player.Character then
		watch(player.Character)
	end
end

-- 휴대폰 SWING 버튼 (2026-10-19, 사용자 보고 "모바일에서 버튼 겹쳐서 배트를 못휘두름"):
-- 터치 화면에선 빈 화면을 탭해야 휘둘러지는데, 왼쪽은 이동 스틱·오른쪽은 버튼들이라 탭할 자리가 거의 없다.
-- 배트를 든 동안 DROP 자리에 큰 SWING 버튼을 띄우고 DROP은 잠깐 숨긴다 (트레이 탭 투하는 그대로).
function Bat.touchSwing(gui: ScreenGui, dropButton: GuiObject)
	local b = Ui.button({
		Size = dropButton.Size,
		Position = dropButton.Position,
		AnchorPoint = dropButton.AnchorPoint,
		BackgroundColor3 = Color3.fromRGB(240, 150, 70),
		TextColor3 = Ui.THEME.accentInk,
		Text = "SWING",
		Visible = false,
		Parent = gui,
	}, function()
		if swingHeld then
			swingHeld()
		end
	end)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
	Ui.addIcon(b, "Bat", 1.4)
	b:SetAttribute("RaidKeep", true) -- 레이드 중에도 보이는 버튼 (RaidUi)
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			touchHold = true
		end
	end)
	b.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			touchHold = false
		end
	end)
	-- 경직 중엔 회색 (왜 안 때려지는지 보이게)
	local SWING_COLOR = b.BackgroundColor3
	RunService.RenderStepped:Connect(function()
		if b.Visible then
			b.BackgroundColor3 = if stunned() then Color3.fromRGB(110, 110, 120) else SWING_COLOR
		end
	end)
	dropButton:GetPropertyChangedSignal("Position"):Connect(function()
		b.Position = dropButton.Position
	end)
	local function refresh()
		local char = player.Character
		local held = char ~= nil and char:FindFirstChild("Bat") ~= nil
		b.Visible = held
		dropButton.Visible = not held
	end
	local function watchChar(char: Model)
		char.ChildAdded:Connect(refresh)
		char.ChildRemoved:Connect(refresh)
		refresh()
	end
	player.CharacterAdded:Connect(watchChar)
	if player.Character then
		watchChar(player.Character)
	end
end

-- 배트 꺼내기/넣기 버튼 (2026-10-19): Roblox 기본 도구 칸(가운데 아래)이 휴대폰에서 왼쪽 아래 버튼 줄과 겹쳐
-- 기본 칸을 끄고 UPGRADES 버튼 위에 우리 버튼을 둔다. 키보드 1·Q, 게임패드 D-pad 위
-- 휴대폰에선 init.client가 DROP 왼쪽으로 옮긴다 (왼쪽 아래는 이동 스틱 자리)
function Bat.button(gui: ScreenGui): TextButton
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	local function find(): (Tool?, Humanoid?)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local held = char and char:FindFirstChild("Bat")
		if held and held:IsA("Tool") then
			return held, hum
		end
		local bp = player:FindFirstChildOfClass("Backpack")
		local stored = bp and bp:FindFirstChild("Bat")
		return if stored and stored:IsA("Tool") then stored else nil, hum
	end
	local b: TextButton
	local function refresh()
		local tool = find()
		local held = tool ~= nil and tool.Parent == player.Character
		b.Text = if held then "PUT AWAY" else "BAT"
		b.BackgroundColor3 = if held then Color3.fromRGB(240, 150, 70) else Ui.THEME.button
	end
	local function toggle()
		local tool, hum = find()
		if not tool or not hum then
			return
		end
		if tool.Parent == player.Character then
			hum:UnequipTools()
		else
			hum:EquipTool(tool)
		end
	end
	b = Ui.button({
		Size = UDim2.fromOffset(150, 56),
		Position = UDim2.new(0, 20, 1, -86), -- UPGRADES(아래 줄) 바로 위
		AnchorPoint = Vector2.new(0, 1),
		Text = "BAT",
		Parent = gui,
	}, toggle)
	Ui.addIcon(b, "Bat")
	b:SetAttribute("RaidKeep", true)
	ContextActionService:BindAction("BatToggle", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.One, Enum.KeyCode.Q, Enum.KeyCode.DPadUp)
	local function watchChar(char: Model)
		char.ChildAdded:Connect(refresh)
		char.ChildRemoved:Connect(refresh)
		refresh()
	end
	player.CharacterAdded:Connect(watchChar)
	if player.Character then
		watchChar(player.Character)
	end
	refresh()
	return b
end

return Bat
