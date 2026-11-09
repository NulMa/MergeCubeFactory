--!strict
-- 첫 플레이 안내 (2026-10-20 리뷰 "온보딩"): 처음 들어온 사람에게만 손가락으로 가리킨다.
--   (DROP 버튼 단계는 버튼과 함께 삭제, 2026-10-25)
--   1번 드로퍼: 첫 SPEED를 살 돈이 모이면 "BUY SPEED!" — 어느 드로퍼든 SPEED를 사면 끝
-- 처음 받은 상태가 리버스 0회 + 드로퍼 SPEED 모두 0일 때만 켠다. 저장할 필요 없음
-- (SPEED는 리버스 전까지 내려가지 않으므로 다시 켜지지 않는다).

local TweenService = game:GetService("TweenService")

local Ui = require(game:GetService("ReplicatedStorage").CoreClient.Ui)

local THEME = Ui.THEME
local make, label = Ui.make, Ui.label

local Tutorial = {}

local POINT = Color3.fromRGB(255, 225, 80)

local function bounce(obj: GuiObject, from: UDim2)
	obj.Position = from
	TweenService:Create(
		obj,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = from - UDim2.fromOffset(0, 12) }
	):Play()
end

-- 아래를 가리키는 화살표 + 글자 묶음 (부모 안 맨 아래가 화살표 끝)
local function pointer(parent: Instance, text: string): (Frame, TextLabel)
	local root = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local bubble = label({
		Size = UDim2.fromScale(1, 0.5),
		BackgroundTransparency = 0,
		BackgroundColor3 = POINT,
		TextColor3 = THEME.accentInk,
		TextStrokeTransparency = 1,
		Text = text,
		ZIndex = 20,
		Parent = root,
	})
	make("UICorner", { CornerRadius = UDim.new(0.4, 0), Parent = bubble })
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = bubble })
	label({
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Text = "▼",
		TextColor3 = POINT,
		ZIndex = 20,
		Parent = root,
	})
	return root, bubble
end

function Tutorial.start(gui: ScreenGui, getState: () -> { [string]: any }?, getPlot: () -> Model?)
	-- 첫 상태를 기다렸다가 새 플레이어인지 본다
	local s = getState()
	while not s do
		task.wait(0.5)
		s = getState()
	end
	local function speedBought(st: { [string]: any }): boolean
		if (st.rebirths or 0) > 0 then
			return true
		end
		for _, d in st.droppers or {} do
			if d.lv > 0 then
				return true
			end
		end
		return false
	end
	if speedBought(s :: any) then
		return
	end

	-- 1번 드로퍼 카드 위 (돈이 모였을 때만)
	local board = make("BillboardGui", {
		Name = "TutorialPointer",
		Size = UDim2.fromOffset(230, 90),
		SizeOffset = Vector2.new(0, 0.85), -- 카드(높이 30) 위로
		StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 140,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = gui.Parent,
	}) :: BillboardGui
	local holder = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = board,
	}) :: Frame
	local _, bubble = pointer(holder, "")
	bounce(holder, UDim2.fromScale(0, 0))

	while true do
		task.wait(0.3)
		local st = getState()
		if not st then
			continue
		end
		if speedBought(st) then
			break
		end
		local d = st.droppers and st.droppers[1]
		local plot = getPlot()
		local part = plot and plot:FindFirstChild("Dropper1") :: BasePart?
		local ready = d ~= nil and d.speedCost ~= nil and st.cash >= d.speedCost and part ~= nil
		board.Adornee = part :: any
		board.Enabled = ready
		if ready then
			bubble.Text = Ui.hint("CLICK → BUY SPEED!", "TAP → BUY SPEED!")
		end
	end
	board:Destroy()
end

return Tutorial
