--!strict
-- 머지 팩토리 프로토타입 클라이언트: HUD, 투하 입력(버튼·탭·게임패드), 업그레이드, 부화기, 오프라인 팝업, 합치기 연출.
-- 그레이박스 단계라 UI는 코드로 만든다. 전 기기 대응: Scale 기반 배치 + 화면 크기별 UIScale (docs/05 §5).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Core.Net)
local Format = require(ReplicatedStorage.Core.Format)
local Config = require(ReplicatedStorage.Game.Config)
local Economy = require(ReplicatedStorage.Game.Economy)
local ShopDef = require(ReplicatedStorage.Game.Shop)
local Remotes = require(ReplicatedStorage.Game.Remotes)
local CoreClient = ReplicatedStorage:WaitForChild("CoreClient")
-- 공용 클라 모듈 설정 (docs/33): 다른 모듈이 UI를 만들기 전에 번역 키 표·아이콘·클릭 소리를 넣는다
local Loc = require(CoreClient:WaitForChild("Loc"))
Loc.init(require(ReplicatedStorage.Game.Strings))
local Ui = require(CoreClient:WaitForChild("Ui"))
Ui.configure({ icons = (require(ReplicatedStorage.Game.AssetIds) :: any).Icons, clickSound = Config.SOUNDS.UiClick })
-- 번역기를 잠깐 기다린다: UI를 만들기 전에 받으면 처음부터 플레이어 언어로 (늦으면 Loc이 키 라벨을 다시 그림)
Loc.wait(2)
local Fx = require(script:WaitForChild("Fx"))
local CameraView = require(script:WaitForChild("CameraView"))
local RatePrompt = require(CoreClient:WaitForChild("RatePrompt"))
local StealUi = require(script:WaitForChild("Steal"))
local Bat = require(script:WaitForChild("Bat"))
local JumpPads = require(script:WaitForChild("JumpPads"))
local Upgrades = require(script:WaitForChild("Upgrades"))
local LeaderboardUi = require(CoreClient:WaitForChild("LeaderboardUi"))
local CollectionUi = require(script:WaitForChild("Collection"))
local GoalBar = require(script:WaitForChild("GoalBar"))
local ShopUi = require(script:WaitForChild("ShopUi"))
local DailyUi = require(script:WaitForChild("DailyUi"))
local PetsUi = require(script:WaitForChild("PetsUi"))

local player = Players.LocalPlayer
local r = Net.client(Remotes :: any)

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

local state: { [string]: any }? = nil
local myPlot: Model? = nil

-- 화면 ---------------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "FactoryHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
}) :: ScreenGui

-- 해상도와 상관없이 화면 대비 같은 크기 (Ui.fitScale)
Ui.fitScale(gui)

-- 상단: 현금 / 초당 수입 / 배수
local top = make("Frame", {
	-- 왼쪽 위: 가운데에 두면 트레이 뒤쪽 드로퍼 카드를 가린다 (docs/14)
	Size = UDim2.fromOffset(300, 74),
	Position = UDim2.fromOffset(12, 8),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundColor3 = THEME.panel,
	BackgroundTransparency = 0.1,
	Parent = gui,
}, { corner(14) })
-- 동전 아이콘이 있으면 왼쪽에 크게, 글자는 오른쪽으로
local cashIcon = Ui.icon("Cash", {
	Size = UDim2.fromOffset(62, 62),
	Position = UDim2.fromOffset(-10, 6),
	Rotation = -10,
	ZIndex = 3,
	Parent = top,
})
if cashIcon then
	Ui.wiggle(cashIcon, 6)
end
local textLeft = if cashIcon then 56 else 10
local cashLabel = label({
	Size = UDim2.new(1, -textLeft - 10, 0.58, 0),
	Position = UDim2.fromOffset(textLeft, 4),
	Text = "$0",
	AutoLocalize = false,
	TextColor3 = THEME.accent,
	Parent = top,
})
local incomeLabel = label({
	Size = UDim2.new(1, -textLeft - 10, 0.34, 0),
	Position = UDim2.new(0, textLeft, 0.6, 0),
	Text = "+$0/s",
	TextColor3 = THEME.dim,
	Parent = top,
})

-- 젬 + 도감 버튼 (현금 HUD 바로 아래). 아래쪽 버튼 줄에 넣으면 휴대폰 가로 화면에서 DROP과 겹친다
local collectionPanel: Frame
local gemsButton = button({
	Size = UDim2.fromOffset(300, 40),
	Position = UDim2.fromOffset(12, 118), -- 피버 게이지(12,88) 아래
	BackgroundColor3 = Color3.fromRGB(70, 90, 150),
	Text = "◆ 0   COLLECTION",
	ZIndex = 3, -- 배지가 위쪽 피버 게이지에 가려 잘리던 문제 (나중에 만든 형제가 위에 그려짐, 2026-10-19)
	Parent = gui,
}, function()
	collectionPanel.Visible = not collectionPanel.Visible
end)
Ui.addIcon(gemsButton, "Gem", 1.35)
-- 도감에서 받을 보상 수 (칸 보상 + 마일스톤): 금색 배지
local codexBadge = label({
	Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, 8, 0, -10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(255, 205, 70),
	TextColor3 = THEME.accentInk,
	Text = "",
	Visible = false,
	ZIndex = 5,
	Parent = gemsButton,
})
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = codexBadge })
local GEM = if Ui.hasIcon("Gem") then "" else "◆ "

-- 토스트 (2026-10-20 "토스트 위치 개선"): 화면 가운데 위 목표 바(8~66) 바로 아래, 반투명 알약 배경.
-- 열린 패널(ZIndex ~10)보다 위에 그려지고, 긴 문장은 두 줄로 감싼다.
local toast = label({
	Size = UDim2.fromOffset(480, 44),
	Position = UDim2.new(0.5, 0, 0, 74),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 18, 32),
	BackgroundTransparency = 1,
	Text = "",
	TextWrapped = true,
	TextScaled = true,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	ZIndex = 30,
	Visible = false,
	Parent = gui,
})
make("UICorner", { CornerRadius = UDim.new(0, 14), Parent = toast })
make("UIPadding", {
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	Parent = toast,
})
make("UITextSizeConstraint", { MaxTextSize = 24, Parent = toast })
local toastTween: Tween? = nil
local missedToasts: { Loc.Text } = {} -- 레이드 중에 못 띄운 알림 (집에 오면 최근 3개)
-- text: 영어 원문(자동 번역) 또는 Loc.msg(키, 매개변수)
local function showToast(text: Loc.Text)
	-- 보스 레이드 중엔 다른 알림을 띄우지 않는다 (2026-10-20 사용자, RaidUi가 gui InRaid 속성을 켬)
	if gui:GetAttribute("InRaid") then
		table.insert(missedToasts, text)
		if #missedToasts > 3 then
			table.remove(missedToasts, 1)
		end
		return
	end
	if toastTween then
		toastTween:Cancel()
	end
	Loc.apply(toast, text)
	toast.Visible = true
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.4
	toast.BackgroundTransparency = 0.35
	local t =
		TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.2), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			BackgroundTransparency = 1,
		})
	toastTween = t
	t.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			toast.Visible = false
		end
	end)
	t:Play()
end
-- 서버 알림: 영어 원문 또는 Strings.msg(키, 매개변수) 표
(r.Toast :: RemoteEvent).OnClientEvent:Connect(function(text: Loc.Text)
	showToast(text)
end)
-- 집에 오면 레이드 중에 못 본 알림을 차례로 (3초 간격)
gui:GetAttributeChangedSignal("InRaid"):Connect(function()
	if gui:GetAttribute("InRaid") or #missedToasts == 0 then
		return
	end
	local list = table.clone(missedToasts)
	table.clear(missedToasts)
	for i, text in list do
		task.delay(1 + (i - 1) * 3, function()
			showToast(text)
		end)
	end
end)

-- 하단 오른쪽 엄지 자리. DROP 버튼은 삭제 (사용자 2026-10-25 "드롭버튼 삭제") — 투하는 드로퍼 자동 + 트레이 탭·E·R2.
-- 보이지 않는 자리 표시만 남겨 SWING(배트)·STEAL·BAT 버튼 배치 기준으로 쓴다
local function sendDrop(x: number)
	(r.Drop :: RemoteEvent):FireServer(x)
end
local dropButton = make("Frame", {
	Name = "ButtonAnchor",
	Size = UDim2.fromOffset(150, 150),
	Position = UDim2.new(1, -20, 1, -20),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
}) :: Frame
-- 첫 플레이 안내: 첫 SPEED (Tutorial.luau)
task.spawn(require(script:WaitForChild("Tutorial")).start, gui, function()
	return state
end, function()
	return myPlot
end)

-- 시점: 3인칭 고정 + 공장 앞 비컨에 서면 공장 전체 시점 (client/CameraView)
local viewHintShown: boolean? = nil -- nil: 아직 비컨에 선 적 없음
-- 좋아요·즐겨찾기 부탁 (보상 없음, client/RatePrompt)
RatePrompt.start(gui, r.RateAsked :: RemoteFunction, function()
	return state
end, {
	title = "Enjoying the factory?",
	body = "Tap 👍 Like and ⭐ Favorite on the game page!\nIt helps us add new cubes and events.",
})

CameraView.start(function(mode)
	-- 처음 비컨을 벗어날 때 한 번 안내
	if mode == "overview" then
		if viewHintShown == nil then
			viewHintShown = false
		end
	elseif mode == "free" and viewHintShown == false then
		viewHintShown = true
		showToast("Stand on the glowing FACTORY VIEW circle to see your whole factory")
	end
end)

Bat.start(r.Swing :: RemoteFunction, function()
	return state
end, Fx)
local batButton = Bat.button(gui)
JumpPads.start(Fx)
-- 큐브 훔치기 (client/Steal, docs/22): DROP 위 STEAL 버튼, 도둑·집 표시, 배트 넉백
StealUi.start(gui, r.Steal :: RemoteFunction, function()
	return state
end, showToast, Fx)

-- 터치 화면 (2026-10-19): Roblox 점프 버튼이 오른쪽 아래 DROP·STEAL 자리와 겹친다 → 오른쪽 버튼 줄을 점프 버튼 왼쪽으로 민다.
-- 배트를 들면 DROP 자리에 SWING 버튼 (Bat.touchSwing)
-- 휴대폰 (2026-10-19, 사용자 요청 "하단부의 좌우 끝부분은 버튼 없게"): 왼쪽 아래는 이동 스틱 자리라 비운다 →
-- BAT 버튼은 DROP 왼쪽으로, 아래 버튼 줄(UPGRADES·CORES·TOP·SHOP)은 오른쪽 위로 (layoutTopRight)
if UserInputService.TouchEnabled then
	Bat.touchSwing(gui, dropButton)
	local column: { GuiObject } = { dropButton }
	if Ui.isTouch() then
		batButton.AnchorPoint = Vector2.new(1, 1)
		batButton.Position = UDim2.new(1, -20 - 150 - 12, 1, -20)
		table.insert(column, batButton)
	end
	local stealButton = StealUi.button()
	if stealButton then
		table.insert(column, stealButton)
	end
	local base: { [GuiObject]: UDim2 } = {}
	for _, b in column do
		base[b] = b.Position
	end
	local function layout()
		local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true) :: GuiObject?
		local scale = gui:FindFirstChildOfClass("UIScale")
		local shift = 0
		if jump and jump.Visible and scale and scale.Scale > 0 then
			-- 점프 버튼 왼쪽 끝에서 화면 오른쪽 끝까지(픽셀) → UI 단위, 우리 오른쪽 여백(20)만큼은 이미 비어 있다
			local fromRight = gui.AbsoluteSize.X - jump.AbsolutePosition.X
			shift = math.max(0, fromRight / scale.Scale - 20 + 8)
		end
		for b, p in base do
			b.Position = UDim2.new(p.X.Scale, p.X.Offset - shift, p.Y.Scale, p.Y.Offset)
		end
	end
	task.spawn(function()
		local touchGui = player.PlayerGui:WaitForChild("TouchGui", 30)
		local jump = touchGui and touchGui:WaitForChild("TouchControlFrame", 10)
		jump = jump and jump:WaitForChild("JumpButton", 10)
		if jump and jump:IsA("GuiObject") then
			jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout)
			jump:GetPropertyChangedSignal("Visible"):Connect(layout)
		end
		layout()
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
end

local upgradesPanel: Frame
local coresPanel: Frame
local upgrades: any
local function toggle(panel: Frame)
	panel.Visible = not panel.Visible
end
local upgradesButton = button({
	Size = UDim2.fromOffset(150, 56),
	Position = UDim2.new(0, 20, 1, -20),
	AnchorPoint = Vector2.new(0, 1),
	Text = "UPGRADES",
	BackgroundColor3 = Color3.fromRGB(90, 200, 110),
	Parent = gui,
}, function()
	toggle(upgradesPanel)
end)
Ui.addIcon(upgradesButton, "Upgrades")
-- 배지: 지금 살 수 있는 업그레이드 수 (docs/14 §3.1)
local badge = label({
	Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, 8, 0, -10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 0,
	BackgroundColor3 = THEME.bad,
	Text = "",
	Visible = false,
	ZIndex = 5,
	Parent = upgradesButton,
})
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = badge })
local coresButton = button({
	Size = UDim2.fromOffset(150, 56),
	Position = UDim2.new(0, 180, 1, -20),
	AnchorPoint = Vector2.new(0, 1),
	Text = "CORES",
	BackgroundColor3 = Color3.fromRGB(200, 120, 255),
	Parent = gui,
}, function()
	toggle(coresPanel)
end)
Ui.addIcon(coresButton, "Cores")
-- 배지: 다 부화해 받을 수 있는 코어 수. 부화 중이면 남은 시간이 가장 짧은 것 (사용자 질문 2026-10-18: "부화는 언제 쓰는 거임")
local coresBadge = label({
	Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, 8, 0, -10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 0,
	BackgroundColor3 = THEME.bad,
	Text = "",
	Visible = false,
	ZIndex = 5,
	Parent = coresButton,
})
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = coresBadge })
local coresTimer = label({
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.fromOffset(0, -22),
	Text = "",
	TextColor3 = Color3.fromRGB(220, 180, 255),
	Visible = false,
	Parent = coresButton,
})
-- 랭킹 (전 서버 상위 50)
local rankPanel = LeaderboardUi.new(gui, r.GetLeaderboard :: RemoteFunction, {
	{
		id = "income",
		label = "INCOME",
		icon = "Cash",
		format = function(v: number): string
			return "$" .. Format.short(v) .. "/s"
		end,
	},
	{ id = "merges", label = "MERGES", icon = "Trophy" },
	{ id = "rebirths", label = "REBIRTHS", icon = "Star" },
}).panel
local topButton = button({
	Size = UDim2.fromOffset(110, 56),
	Position = UDim2.new(0, 340, 1, -20),
	AnchorPoint = Vector2.new(0, 1),
	Text = "TOP",
	BackgroundColor3 = Color3.fromRGB(90, 160, 255),
	Parent = gui,
}, function()
	toggle(rankPanel)
end)
Ui.addIcon(topButton, "Trophy")
-- 상점 (ShopUi.luau, docs/03 §2)
local shop = ShopUi.new({
	gui = gui,
	remotes = r,
	getState = function()
		return state
	end,
})
local shopPanel = shop.panel
local shopButton = button({
	Size = UDim2.fromOffset(120, 56),
	Position = UDim2.new(0, 460, 1, -20),
	AnchorPoint = Vector2.new(0, 1),
	Text = "SHOP",
	BackgroundColor3 = THEME.accent,
	TextColor3 = THEME.accentInk,
	Parent = gui,
}, function()
	toggle(shopPanel)
end)
-- 상점 버튼은 눈에 띄게: 아이콘 흔들림 + 광택
local shopIcon = Ui.addIcon(shopButton, "Shop")
if shopIcon then
	Ui.wiggle(shopIcon, 10)
end
Ui.shine(shopButton, 2)

-- 휴대폰: 아래 버튼 줄을 오른쪽 위로 (왼쪽 아래 이동 스틱과 겹치지 않게, 2026-10-19 사용자 요청).
-- 화면이 넓으면(가로 1500 단위 이상, 요즘 휴대폰 가로는 약 2000) 한 줄, 좁으면(4:3 태블릿·옛 16:9 폰 약 1400) 위 가운데
-- 목표 막대(330)와 겹치므로 2×2. 부화 남은 시간은 CORES 버튼 아래, 단기 버프 버튼은 그 아래로 (layoutTopRight)
local placeBoost: ((y: number) -> ())? = nil
local function layoutTopRight()
	local scale = gui:FindFirstChildOfClass("UIScale")
	local width = gui.AbsoluteSize.X / (if scale and scale.Scale > 0 then scale.Scale else 1)
	local rows: { { TextButton } } = if width >= 1500
		then { { upgradesButton, coresButton, topButton, shopButton } }
		else { { upgradesButton, shopButton }, { coresButton, topButton } }
	local y = 14
	for _, row in rows do
		local right = -16
		for i = #row, 1, -1 do
			local b = row[i]
			b.AnchorPoint = Vector2.new(1, 0)
			b.Position = UDim2.new(1, right, 0, y)
			right -= b.Size.X.Offset + 10
		end
		y += 66
	end
	coresTimer.Position = UDim2.fromOffset(0, 58)
	if placeBoost then
		placeBoost(y + 20) -- 부화 시간 글자(20) 아래
	end
end

-- 업그레이드: 드로퍼 위 카드 + 탭 패널 (Upgrades.luau, docs/14)
upgrades = Upgrades.new({
	gui = gui,
	remotes = r,
	getState = function()
		return state
	end,
	toast = showToast,
	cashLabel = cashLabel,
})
upgradesPanel = upgrades.panel
require(script:WaitForChild("EventsUi")).init(gui) -- 황금 큐브·피버·알림 HUD (docs/17)
-- 보스 레이드 참여 묻기·전투 HUD·결과 (docs/25). BuffChips가 생긴 뒤
local raidUi = require(script:WaitForChild("RaidUi")).init(gui, showToast)

-- 도감·꾸미기 (Collection.luau, docs/16)
local collection = CollectionUi.new({
	gui = gui,
	remotes = r,
	getState = function()
		return state
	end,
	toast = showToast,
})
collectionPanel = collection.panel

-- 접속 선물·일일 퀘스트 (DailyUi.luau, docs/23): 도감 버튼 아래
local daily = DailyUi.new({ gui = gui, remotes = r, toast = showToast })
-- 7일 출석 창 + 친구 초대 버튼 (LoginUi.luau)
local login = require(script:WaitForChild("LoginUi")).new({ gui = gui, remotes = r, toast = showToast })
local dailyPanel = daily.panel

-- 펫 뽑기·인벤토리 (PetsUi.luau, docs/24): 일일 선물 버튼 아래. 따라다니는 펫은 PetFollow가 모든 플레이어 것을 그린다
local pets = PetsUi.new({
	gui = gui,
	remotes = r,
	getState = function()
		return state
	end,
	toast = showToast,
})
local petsPanel = pets.panel
-- 큐브 인벤토리 (CubeInventory.luau): 오른쪽 CUBES 버튼 → 위젯 → 전체 창
local cubeInv = require(script:WaitForChild("CubeInventory")).new(gui)
-- 광장 발판 (Stations.luau): BOSS SHOP·PET EGGS 위에 서면 그 패널만 (2026-10-20 사용자)
require(script:WaitForChild("Stations")).init(gui, {
	boss = upgrades.station,
	eggs = pets.station,
}, {
	boss = upgrades.panel,
	eggs = petsPanel,
})
require(script:WaitForChild("PetFollow")).start()
-- 다인 최적화: 먼 공장 큐브의 빛·입자·글자 끄기 (CubeLod.luau)
require(script:WaitForChild("CubeLod")).start()
-- 큐브 얼굴·등급 숫자는 클라이언트가 붙인다 (서버 복제 줄이기, CubeLook.luau)
require(script:WaitForChild("CubeLook")).start()
-- 데이터 큐브 (docs/27 단계 4): 서버 데이터 → 플롯 Cubes 폴더 안 로컬 파트 (CubeView.luau)
local CubeView = require(script:WaitForChild("CubeView"))
if Config.DATA_CUBES then
	CubeView.start(r.CubeEvt :: RemoteEvent, r.CubeSnap :: UnreliableRemoteEvent)
end
-- 오른쪽 위 초저가 단기 버프 버튼 (BoostButton.luau)
placeBoost = require(script:WaitForChild("BoostButton")).start(gui, function()
	return state
end)
if Ui.isTouch() then
	layoutTopRight()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTopRight)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if scale then
		scale:GetPropertyChangedSignal("Scale"):Connect(layoutTopRight)
	end
end
-- 메뉴(Esc)를 열면 "나가도 돈을 번다" 알림 (LeaveNote.luau)
require(script:WaitForChild("LeaveNote")).start(function(): number
	local s = state
	return if s then tonumber(s.income) or 0 else 0
end)

-- 부화기 패널
coresPanel = make("Frame", {
	Size = UDim2.fromOffset(380, 330),
	Position = UDim2.new(0.5, 0, 1, -90),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = THEME.panel,
	Visible = false,
	Parent = gui,
}, { corner(14) }) :: Frame
-- 접속 중엔 부화 2배 (2026-10-20, shared/Online.HATCH_SPEED)
label({
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.fromOffset(8, 6),
	Text = "ONLINE BONUS: cores hatch 2x faster while you play",
	TextColor3 = THEME.good,
	Font = Enum.Font.GothamBold,
	Parent = coresPanel,
})
local coreList = make("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -38),
	Position = UDim2.fromOffset(8, 30),
	BackgroundTransparency = 1,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = coresPanel,
}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

-- 상태는 1초마다 오는데 매번 다시 만들면 누르는 도중 버튼이 바뀌어 클릭이 씹힌다:
-- 구성(코어 종류·다 됨 여부·대기 수)이 같으면 진행 막대·남은 시간만 고친다
local coreSig = ""
local coreBars: { { bar: Frame, text: TextLabel, slot: number } } = {}
local function coreSignature(s: { [string]: any }): string
	local parts = { tostring(s.queued) }
	for _, h in s.hatching do
		table.insert(parts, if h then `{h.tier}{if h.remaining <= 0 then "R" else "H"}{h.payout}` else "E")
	end
	return table.concat(parts, ",")
end
local function renderCores(s: { [string]: any }, force: boolean?)
	local sig = coreSignature(s)
	if not force and sig == coreSig then
		for _, e in coreBars do
			local h = s.hatching[e.slot]
			if h then
				e.bar.Size = UDim2.fromScale(math.clamp(1 - h.remaining / math.max(1, h.total or 1), 0.03, 1), 1)
				e.text.Text = Format.duration(h.remaining)
			end
		end
		return
	end
	coreSig = sig
	table.clear(coreBars)
	for _, c in coreList:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	label({
		Size = UDim2.new(1, -8, 0, 30),
		Loc = Loc.msg("cores.queued", { n = s.queued }),
		TextColor3 = THEME.dim,
		LayoutOrder = 0,
		Parent = coreList,
	})
	-- 언제 쓰는 기능인지 늘 보이게 (사용자 질문 2026-10-18)
	label({
		Size = UDim2.new(1, -8, 0, 40),
		Text = "Merge tier 5+ cubes to find cores. Hatch them for cash + permanent income!",
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(220, 180, 255),
		LayoutOrder = 2000,
		Parent = coreList,
	})
	-- 부화 중인 코어가 있으면 즉시 완료 상품 (ShopUi.prompt가 상품이 없으면 아무것도 안 함)
	local waiting = false
	for _, h in s.hatching do
		if h and h.remaining > 0 then
			waiting = true
		end
	end
	local hatchItem = ShopDef.item("hatch")
	if waiting and hatchItem and hatchItem.id ~= 0 then
		local f = make("Frame", {
			Size = UDim2.new(1, -8, 0, 46),
			BackgroundTransparency = 1,
			LayoutOrder = 1000,
			Parent = coreList,
		})
		button({
			Size = UDim2.fromScale(1, 1),
			Text = `FINISH ALL NOW  R$ {hatchItem.price}`,
			BackgroundColor3 = THEME.accent,
			TextColor3 = THEME.accentInk,
			Parent = f,
		}, function()
			ShopUi.prompt("hatch")
		end)
	end
	-- 부화기 카드: 알 아이콘 + 이름 + 진행 막대 + 남은 시간. 다 되면 반짝이는 CLAIM
	-- 다 된 코어는 맨 위로 (2026-10-19 "부화된 코어가 리스트 상단으로, 제자리 클릭으로 부화"):
	-- 받으면 다음 다 된 코어가 같은 자리로 올라와서 한 자리만 계속 눌러 다 받을 수 있다. 카드 어디를 눌러도 받음
	for i, h in s.hatching do
		local ready = h and h.remaining <= 0
		local f = make("Frame", {
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundColor3 = if ready then Color3.fromRGB(90, 200, 110) elseif h then THEME.card else THEME.panel,
			BackgroundTransparency = if h then 0 else 0.4,
			LayoutOrder = if ready then -100 + i elseif h then i else 500 + i,
			NoDress = ready == true or h == false,
			Parent = coreList,
		}, { corner(12) })
		-- 코어 그림: 등급마다 다름 (CoreT5…CoreT40, 2026-10-19 "코어별 이미지 전부 다르게").
		-- 부화 중이면 오른쪽 아래 작은 시계, 다 되면 체크 + 흔들림
		local coreIcon = if h then `CoreT{h.tier}` else "Cores"
		if h and not Ui.hasIcon(coreIcon) then
			coreIcon = `Core{math.clamp((h.tier - 1) // Config.BAND_SIZE + 1, 1, 8)}`
		end
		local egg = Ui.icon(if Ui.hasIcon(coreIcon) then coreIcon else "Cores", {
			Size = UDim2.fromOffset(58, 58),
			Position = UDim2.new(0, 4, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ImageTransparency = if h then 0 else 0.7,
			Parent = f,
		})
		if egg and h then
			Ui.icon(if ready then "Check" else "Clock", {
				Size = UDim2.fromOffset(24, 24),
				Position = UDim2.new(1, 2, 1, 2),
				AnchorPoint = Vector2.new(1, 1),
				Parent = egg,
			})
		end
		if egg and ready then
			Ui.wiggle(egg, 10)
		end
		local left = if egg then 68 else 10
		if h == false then
			label({
				Size = UDim2.new(1, -left - 10, 0.5, 0),
				Position = UDim2.new(0, left, 0.25, 0),
				Loc = Loc.msg("cores.empty", { i = i }),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = THEME.dim,
				Parent = f,
			})
		elseif not ready then
			label({
				Size = UDim2.new(1, -left - 10, 0.4, 0),
				Position = UDim2.new(0, left, 0.08, 0),
				Loc = Loc.msg("cores.hatching", { core = h.name, cash = Format.short(h.payout) }),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = f,
			})
			local back = make("Frame", {
				Size = UDim2.new(1, -left - 10, 0.36, 0),
				Position = UDim2.new(0, left, 0.54, 0),
				BackgroundColor3 = Color3.fromRGB(25, 22, 40),
				NoDress = true,
				Parent = f,
			}, { corner(8) })
			local total = math.max(1, h.total or 1)
			local bar = make("Frame", {
				Size = UDim2.fromScale(math.clamp(1 - h.remaining / total, 0.03, 1), 1),
				BackgroundColor3 = Color3.fromRGB(200, 120, 255),
				NoDress = true,
				Parent = back,
			}, {
				corner(8),
				make("UIGradient", {
					Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), Color3.fromRGB(220, 120, 255)),
				}),
			})
			local timeText = label({
				Size = UDim2.fromScale(1, 1),
				Text = Format.duration(h.remaining),
				AutoLocalize = false,
				Parent = back,
			})
			table.insert(coreBars, { bar = bar :: Frame, text = timeText :: TextLabel, slot = i })
		else
			local claimed = false
			local function claim()
				if claimed then
					return -- 두 번 눌러도 한 번만 (응답 오기 전 같은 카드)
				end
				claimed = true
				f.Visible = false -- 바로 사라져 다음 다 된 코어가 이 자리로 올라옴
				if not (r.ClaimCore :: RemoteFunction):InvokeServer(i) and f.Parent then
					f.Visible, claimed = true, false -- 실패하면 되돌림 (구성이 같으면 다시 안 그리므로)
				end
			end
			local b = button({
				Size = UDim2.new(1, -left - 8, 1, -12),
				Position = UDim2.fromOffset(left, 6),
				Loc = Loc.msg("cores.claim", { core = h.name, cash = Format.short(h.payout) }),
				BackgroundColor3 = THEME.accent,
				TextColor3 = THEME.accentInk,
				Parent = f,
			}, claim)
			Ui.shine(b, 1.5)
			-- 카드 전체(알 아이콘 포함)도 누르면 받기
			local hit = make("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 0,
				NoDress = true,
				Parent = f,
			}) :: TextButton
			hit.Activated:Connect(claim)
		end
	end
end

-- 오프라인 수익 팝업
local offlinePopup = make("Frame", {
	Size = UDim2.fromOffset(420, 200),
	Position = UDim2.fromScale(0.5, 0.45),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = THEME.panel,
	Visible = false,
	Parent = gui,
}, { corner(16) }) :: Frame
label({
	Size = UDim2.new(1, -30, 0, 40),
	Position = UDim2.fromOffset(15, 15),
	Text = "While you were away",
	Parent = offlinePopup,
})
local offlineAmount = label({
	Size = UDim2.new(1, -30, 0, 54),
	Position = UDim2.fromOffset(15, 60),
	Text = "",
	AutoLocalize = false,
	TextColor3 = THEME.accent,
	Parent = offlinePopup,
})
local collectButton = button({
	Size = UDim2.new(1, -30, 0, 56),
	Position = UDim2.new(0, 15, 1, -71),
	Text = "COLLECT",
	BackgroundColor3 = THEME.accent,
	TextColor3 = THEME.accentInk,
	Parent = offlinePopup,
}, function()
	(r.ClaimOffline :: RemoteFunction):InvokeServer()
	offlinePopup.Visible = false
end)
Ui.shine(collectButton, 1.5)
-- 위에 햇살 + 보물상자
local offlineArt = make("Frame", {
	Size = UDim2.fromOffset(120, 120),
	Position = UDim2.new(0.5, 0, 0, -50),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Parent = offlinePopup,
})
local offlineRays = Ui.icon("Sunburst", {
	Size = UDim2.fromScale(2.2, 2.2),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ImageColor3 = THEME.accent,
	ImageTransparency = 0.3,
	Parent = offlineArt,
})
if offlineRays then
	Ui.spin(offlineRays, 30)
end
local offlineChest = Ui.icon("CashChest", { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = offlineArt })
if offlineChest then
	Ui.wiggle(offlineChest, 6)
end

-- 패널 위 지갑: 패널이 열려 있어도 지금 재화가 보이게 (사용자 피드백 2026-10-18)
local wallets: { { cash: TextLabel, gems: TextLabel } } = {}
for _, panel in { upgradesPanel, coresPanel, shopPanel, collectionPanel, rankPanel } do
	local pill = make("Frame", {
		Name = "Wallet",
		Size = UDim2.fromOffset(250, 38),
		Position = UDim2.new(1, -4, 0, -8),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = THEME.panel,
		ZIndex = 11,
		Parent = panel,
	}, { corner(19) })
	Ui.icon("Cash", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(4, 2), ZIndex = 12, Parent = pill })
	local cash = label({
		Size = UDim2.fromOffset(100, 28),
		Position = UDim2.fromOffset(40, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Text = "$0",
		AutoLocalize = false,
		ZIndex = 12,
		Parent = pill,
	})
	Ui.icon("Gem", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(146, 3), ZIndex = 12, Parent = pill })
	local gems = label({
		Size = UDim2.fromOffset(64, 28),
		Position = UDim2.fromOffset(180, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 230, 255),
		Text = "0",
		AutoLocalize = false,
		ZIndex = 12,
		Parent = pill,
	})
	table.insert(wallets, { cash = cash, gems = gems })
end

-- 상태 수신 -------------------------------------------------------------------------

local shownOffline = false
-- 다음 목표 바 (GoalBar.luau): 위 가운데
local goalBar = GoalBar.new(gui, {
	upgrades = function(tab: string)
		upgrades.open(tab)
	end,
	collection = function()
		collectionPanel.Visible = true
	end,
	cores = function()
		coresPanel.Visible = true
	end,
	daily = function()
		dailyPanel.Visible = true
	end,
})

local stateRemote = r.State :: RemoteEvent
stateRemote.OnClientEvent:Connect(function(s)
	local prev = state
	state = s
	cashLabel.Text = "$" .. Format.short(s.cash)
	for _, w in wallets do
		w.cash.Text = "$" .. Format.short(s.cash)
		w.gems.Text = Format.short(s.gems or 0)
	end
	if prev and s.cash > prev.cash * 1.25 + 10 then
		Fx.bump(cashLabel, 0.2)
	end
	-- 친구 보너스·온라인 연속 보너스는 지금 배수 옆에 (2026-10-20)
	local team = if s.visitors > 0 then "  " .. Loc.format("hud.friends", { n = s.visitors }) else ""
	local online = s.online
	local streak = if online and online.bonus > 0
		then "  " .. Loc.format("hud.online", { pct = math.floor(online.bonus * 100 + 0.5) })
		else ""
	if online and prev and prev.online and online.bonus > prev.online.bonus then
		local pct = math.floor(online.bonus * 100 + 0.5)
		showToast(if online.nextBonus
			then Loc.msg("toast.onlineNext", {
				pct = pct,
				mins = math.ceil((online.nextIn or 0) / 60),
				next = math.floor(online.nextBonus * 100 + 0.5),
			})
			else Loc.msg("toast.online", { pct = pct }))
	end
	raidUi.render(s)
	login.render(s)
	Loc.raw(
		incomeLabel,
		`+${Format.short(s.income)}/s   x{string.format("%.2f", s.mult)}{team}{streak}   `
			.. Loc.format(if s.trayCount >= s.trayCap then "hud.trayFull" else "hud.tray", {
				n = s.trayCount,
				cap = s.trayCap,
			})
	)
	StealUi.render(s)
	Loc.set(
		gemsButton,
		"hud.gems",
		{ gem = GEM, gems = Format.short(s.gems or 0), n = s.collection.count, total = s.collection.total }
	)
	if prev and (s.gems or 0) > (prev.gems or 0) then
		Fx.bump(gemsButton, 0.2)
	end
	local rewards = if s.collection.milestoneReady then 1 else 0
	for _ in s.collection.unclaimed or {} do
		rewards += 1
	end
	if rewards > 0 and not codexBadge.Visible then
		Fx.bump(gemsButton, 0.25)
	end
	codexBadge.Visible = rewards > 0
	codexBadge.Text = tostring(rewards)
	if collectionPanel.Visible then
		collection.render(s)
	end
	daily.render(s)
	pets.render(s)
	cubeInv.render(s)
	local n = upgrades.render(s)
	goalBar.render(s, n)
	if n > 0 and not badge.Visible then
		Fx.bump(upgradesButton, 0.2)
	end
	badge.Visible = n > 0
	badge.Text = tostring(n)
	local ready, soonest = 0, math.huge
	for _, h in s.hatching do
		if h then
			if h.remaining <= 0 then
				ready += 1
			else
				soonest = math.min(soonest, h.remaining)
			end
		end
	end
	if ready > 0 and not coresBadge.Visible then
		Fx.bump(coresButton, 0.25)
		showToast("A core finished hatching! Open CORES to claim")
	end
	coresBadge.Visible = ready > 0
	coresBadge.Text = tostring(ready)
	coresTimer.Visible = ready == 0 and soonest < math.huge
	Loc.set(coresTimer, "cores.timer", { time = if soonest < math.huge then Format.duration(soonest) else "" })
	if coresPanel.Visible then
		renderCores(s)
	end
	if shopPanel.Visible then
		shop.render(s)
	end
	if s.offline > 0 and not shownOffline then
		shownOffline = true
		offlineAmount.Text = "+$" .. Format.short(s.offline)
		offlinePopup.Visible = true
	end
end)
-- 패널은 한 번에 하나만. HUD(현금·피버·젬)보다 위에 그린다: ZIndexBehavior.Sibling이라
-- 나중에 만든 HUD(EventsUi 피버 게이지 등)가 패널을 덮던 문제 (사용자 보고 2026-10-18)
local panels =
	{ upgradesPanel, coresPanel, collectionPanel, rankPanel, shopPanel, dailyPanel, petsPanel, cubeInv.panel }
for _, panel in panels do
	panel.ZIndex = 10
end
offlinePopup.ZIndex = 15

-- 패널 바깥을 누르면 닫기 (2026-10-20 사용자 요청): 패널이 열린 동안 투명한 전체 화면 버튼을 HUD 아래(ZIndex 0)에 깐다.
-- HUD 버튼은 그대로 눌리고(다른 패널로 바로 전환), 3D 화면 탭은 닫기만 하고 트레이 투하·배트로 새지 않는다
local backdrop = make("TextButton", {
	Name = "PanelBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 0,
	Parent = gui,
}) :: TextButton
-- 패널(Frame)은 Active여도 아래 버튼으로 클릭이 새므로(Studio 확인 2026-10-20) 누른 자리가 열린 패널 안이면 무시한다
backdrop.Activated:Connect(function(input: InputObject)
	local at = Vector2.new(input.Position.X, input.Position.Y)
	for _, panel in panels do
		local p, size = panel.AbsolutePosition, panel.AbsoluteSize
		if panel.Visible and at.X >= p.X and at.X <= p.X + size.X and at.Y >= p.Y and at.Y <= p.Y + size.Y then
			return
		end
	end
	for _, panel in panels do
		panel.Visible = false
	end
end)
local function syncBackdrop()
	local open = false
	for _, panel in panels do
		open = open or panel.Visible
	end
	backdrop.Visible = open
end
for _, panel in panels do
	panel:GetPropertyChangedSignal("Visible"):Connect(syncBackdrop)
end

-- 휴대폰 (2026-10-20 사용자 요청): 패널은 화면 가운데에 크게 (전체 UI를 30% 줄인 만큼 패널은 화면 높이에 맞춰 키운다, 최대 1.5배),
-- 왼쪽 버튼 줄(도감·일일 선물·펫)은 높이 56·간격 28로 벌려 잘못 누르지 않게
if Ui.isTouch() then
	-- 패널 위 지갑(높이 ~46)이 화면 밖으로 나가지 않게 위쪽 70을 남기고 그만큼 아래로
	for _, panel in panels do
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.new(0.5, 0, 0.5, 35)
		Ui.touchFit(gui, panel, 1.5, 70)
	end
	Ui.touchFit(gui, offlinePopup) -- 접속 때 처음 보는 창

	local y = 124 -- 피버 게이지(88~112) 아래
	for _, b in { gemsButton, daily.button, pets.button, login.invite } do
		b.Size = UDim2.fromOffset(300, 56)
		b.Position = UDim2.fromOffset(12, y)
		y += 56 + 28
	end
	local chips = gui:FindFirstChild("BuffChips") :: GuiObject?
	if chips then
		chips.Position = UDim2.fromOffset(12, y - 8)
	end
end

for _, panel in panels do
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			return
		end
		for _, other in panels do
			if other ~= panel then
				other.Visible = false
			end
		end
		if panel == coresPanel and state then
			renderCores(state, true)
		elseif panel == collectionPanel and state then
			collection.render(state)
			collection.focusReward()
		elseif panel == shopPanel and state then
			shop.render(state)
		end
	end)
end

-- 트레이를 탭/클릭하면 그 위치에 투하 -------------------------------------------------

local function dropAtScreen(pos: Vector2)
	local s = state
	local cam = workspace.CurrentCamera
	if not s or not cam then
		return
	end
	-- 입력 좌표는 상단 바(인셋)를 뺀 화면 좌표 → ScreenPointToRay (ViewportPointToRay는 인셋만큼 위로 어긋났다, 2026-10-20)
	local ray = cam:ScreenPointToRay(pos.X, pos.Y)
	-- 트레이 바닥 평면(y = center.Y)과의 교점
	if math.abs(ray.Direction.Y) < 1e-3 then
		return
	end
	local t = (s.plotCenter.Y - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then
		return
	end
	local hit = ray.Origin + ray.Direction * t
	local half = s.traySize.X / 2
	local local3 = hit - s.plotCenter
	if math.abs(local3.X) <= half and math.abs(local3.Z) <= half then
		sendDrop(local3.X / (half * 0.8))
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- 배트를 든 동안 클릭·탭은 휘두르기 (투하까지 같이 되던 문제)
		local char = player.Character
		if char and char:FindFirstChild("Bat") then
			return
		end
		dropAtScreen(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

-- 게임패드: R2 투하, Y 업그레이드, X 코어
-- E는 남의 트레이에서 STEAL 버튼이 떠 있으면 훔치기(client/Steal의 StealCube로 넘김), 아니면 투하 (2026-10-20 리뷰:
-- 나중에 묶은 이쪽이 E를 항상 먹어서 PC에서 E로 못 훔쳤다). 배트를 든 동안 R2는 배트 휘두르기(도구 Activate)로 넘긴다
ContextActionService:BindAction("FactoryDrop", function(_, inputState, input)
	local steal = StealUi.button()
	if input.KeyCode == Enum.KeyCode.E and steal and steal.Visible then
		return Enum.ContextActionResult.Pass
	end
	local char = player.Character
	if input.KeyCode == Enum.KeyCode.ButtonR2 and char and char:FindFirstChild("Bat") then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		sendDrop((math.random() - 0.5) * 1.6)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonR2, Enum.KeyCode.E)
ContextActionService:BindAction("FactoryUpgrades", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		toggle(upgradesPanel)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonY)
ContextActionService:BindAction("FactoryCores", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		toggle(coresPanel)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonX)
ContextActionService:BindAction("FactoryCollection", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		toggle(collectionPanel)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonL1)
local function nearestDropper(at: Vector3): BasePart?
	local plot = myPlot
	if not plot then
		return nil
	end
	local best, bestD = nil, 6
	for _, d in plot:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Dropper") then
			local dist = (d.Position - at).Magnitude
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	return best
end

-- 연출 연결 (Fx.luau) -------------------------------------------------------------

local mergedRemote = r.Merged :: RemoteEvent
mergedRemote.OnClientEvent:Connect(function(at, tier, combo, owner, isBest)
	local s = state
	Fx.merge(at, tier, combo, owner, isBest, if s then s.best else nil)
end)
local fxRemote = r.Fx :: RemoteEvent
fxRemote.OnClientEvent:Connect(function(kind: string, at: any, name: any, payout: any, ...: any)
	if StealUi.onFx(kind, at, name, payout, ...) then
		return
	end
	if kind == "variant" then
		-- ("variant", pos, tier, variantId, how, isNew, gems)
		local id = tostring(payout)
		local how, isNew, gems = ...
		local rank = Economy.variantIndex(id) - 1
		Fx.variant(at, name, id, rank, tostring(how), isNew == true, tonumber(gems) or 0)
		if isNew then
			Fx.bump(gemsButton, 0.3)
		end
	elseif kind == "reveal" then
		-- ("reveal", pos, tier, variantId, cubeId): 드문 변이 공개 전 두근 연출.
		-- 큐브 파트는 내 Cubes 폴더에서 CubeId로 찾는다 (데이터 큐브면 spawn이 이 이벤트보다 늦게 올 수 있어 매 프레임 다시 찾음)
		local cubeId = ...
		local plot = myPlot
		local found: BasePart? = nil
		Fx.reveal(at, name, tostring(payout), function(): BasePart?
			-- 데이터 큐브 파트는 풀에서 다른 큐브로 다시 쓰이므로 CubeId도 확인 (client/CubeView)
			if found and found.Parent and found:GetAttribute("CubeId") == cubeId then
				return found
			end
			local folder = plot and plot:FindFirstChild("Cubes")
			if folder and typeof(cubeId) == "number" then
				for _, c in folder:GetChildren() do
					if c:IsA("BasePart") and c:GetAttribute("CubeId") == cubeId then
						found = c
						return c
					end
				end
			end
			return nil
		end)
		RatePrompt.happy()
	elseif kind == "omen" then
		-- ("omen", dropPos, variantId): 드로퍼 예고
		Fx.omen(at, tostring(name), nearestDropper(at + Vector3.new(0, 3, 0)))
	elseif kind == "ceiling" then
		-- ("ceiling", 상한 등급, 리버스 후 상한): 상한 등급은 더 안 합쳐짐 → 리버스 안내
		Fx.banner(
			Loc.msg("banner.tierMax", { tier = at }),
			"Star",
			THEME.accent,
			if tonumber(name) and tonumber(name) > tonumber(at)
				then Loc.msg("banner.rebirthUpTo", { tier = name })
				else "REBIRTH for more income"
		)
	elseif kind == "record" then
		Fx.record(at :: Loc.Text)
		RatePrompt.happy()
	elseif kind == "codex" then
		-- ("codex", text, gems): 도감 마일스톤
		local s = state
		local center = if s then s.plotCenter else Vector3.zero
		Fx.codex(center, at :: Loc.Text, tonumber(name) or 0)
		RatePrompt.happy()
	elseif kind == "gift" then
		-- ("gift", 상자 위치, 글): 광장 선물 상자
		local text = name :: Loc.Text
		if typeof(at) == "Vector3" then
			Fx.popup(at + Vector3.new(0, 3, 0), text, Color3.fromRGB(255, 215, 90), 1.4, 2.5)
		end
		Fx.sound("Coin", nil, 0.6, 1.1)
		Fx.bump(cashLabel, 0.35)
		showToast(text)
	elseif kind == "shop" then
		local s = state
		Fx.codex(if s then s.plotCenter else Vector3.zero, at :: Loc.Text, 0)
	elseif kind == "milestone" or kind == "lucky" then
		upgrades.onFx(kind, at, name)
	elseif kind == "core" then
		Fx.coreFound(at, name or "")
		Fx.bump(coresButton, 0.3)
		showToast(Loc.msg("cores.found", { core = name or "" }))
	elseif kind == "hatch" then
		Fx.hatch(at, name or "", "+$" .. Format.short(payout or 0))
		Fx.bump(cashLabel, 0.35)
	elseif kind == "rebirth" then
		Fx.rebirth(at)
	elseif kind == "comboCash" then
		-- ("comboCash", 금액, 콤보): 연쇄가 끝나면 받은 콤보 현금 (트레이 위 글자)
		local s = state
		if s then
			Fx.popup(
				s.plotCenter + Vector3.new(0, 10, 0),
				`COMBO x{name or 0}  +${Format.short(tonumber(at) or 0)}`,
				Color3.fromRGB(255, 225, 90),
				1.2
			)
		end
		Fx.sound("Coin", nil, 0.5, 1.2)
		Fx.bump(cashLabel, 0.15)
	end
end)

-- 내 플롯 큐브 감시: 새 큐브 = 투하 연출, 빠르게 떨어지다 멈춤 = 착지 연출.
-- 데이터 큐브(로컬 Anchored 파트라 속도가 0)는 CubeView가 보이는 시점에 착지를 알려 준다
local watched: { [BasePart]: { vy: number, landed: boolean } } = {}
CubeView.onLand(function(plot: Model, part: BasePart, tier: number, speed: number)
	if plot == myPlot then
		Fx.land(part.Position, tier, speed)
	end
end)

local function watchPlot(plot: Model)
	myPlot = plot
	upgrades.setPlot(plot)
	local cubes = plot:WaitForChild("Cubes")
	cubes.ChildAdded:Connect(function(c)
		if c:IsA("BasePart") then
			if not Config.DATA_CUBES then
				watched[c] = { vy = 0, landed = false }
			end
			Fx.drop(c.Position, nearestDropper(c.Position + Vector3.new(0, 3, 0)))
		end
	end)
	cubes.ChildRemoved:Connect(function(c)
		watched[c :: BasePart] = nil
	end)
end

task.spawn(function()
	local plots = workspace:WaitForChild("Plots")
	while not myPlot do
		for _, m in plots:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
				watchPlot(m)
			end
		end
		task.wait(0.5)
	end
end)

RunService.Heartbeat:Connect(function()
	for part, w in watched do
		local vy = part.AssemblyLinearVelocity.Y
		-- 아래로 빠르게 가다가 거의 멈춤 → 착지 (한 큐브당 첫 착지 + 이후 큰 튕김만)
		if w.vy < -14 and vy > -3 then
			Fx.land(part.Position, (part:GetAttribute("Tier") :: number?) or 1, -w.vy)
			w.landed = true
		end
		w.vy = vy
	end
end)

-- BGM
local bgm = make("Sound", { SoundId = Config.BGM, Looped = true, Volume = 0.25, Parent = SoundService }) :: Sound
bgm:Play()

-- 카메라: 캐릭터 중심 MMORPG식 3인칭 (client/CameraView). 예전의 "공장 근처면 초점을 트레이로 옮기기"와
-- "스폰 때 높이서 내려다보기"는 비컨 전에 시점이 끌려가는 원인이라 지웠다 (2026-10-18 사용자 피드백).
-- 공장 전체는 시점 비컨에서 본다.
