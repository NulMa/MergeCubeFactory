--!strict
-- 랭킹 패널: 보드 탭(최고 수입 / 누적 합치기 / 리버스) + 상위 50 목록. 내 줄은 강조, 1~3위는 메달 색.
-- 2026-10-20: 아래에 '내 줄'을 고정 (상위 50 밖이어도 내 값이 보인다), 빈 보드 안내가 쌓이던 문제 수정.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Core.Format)
local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)

local THEME = Ui.THEME
local make, label, corner = Ui.make, Ui.label, Ui.corner
-- medal colors: THEME.medals (theme palette.medals), read at render time

local LeaderboardUi = {}

-- One tab per board. id matches the server's board id (res.boards[i].id). icon: Ui icon name (optional).
-- format: value -> text (default Format.short)
export type Tab = { id: string, label: string, icon: string?, format: ((value: number) -> string)? }

-- remote returns { boards = { { id, entries = { { userId, name, value } }, mine } }, live: boolean, top: number }
function LeaderboardUi.new(gui: ScreenGui, remote: RemoteFunction, tabSpecs: { Tab })
	local me = Players.LocalPlayer.UserId
	local panel = make("Frame", {
		Size = UDim2.fromOffset(420, 400),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = gui,
	}, { corner(14) }) :: Frame
	Ui.bindPanel(panel) -- theme open motion + sound (default: none)
	local tabBar = make("Frame", {
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
		}),
	})
	local note = label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 52),
		Text = "",
		TextColor3 = THEME.dim,
		Role = "body",
		Parent = panel,
	})
	local list = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -126),
		Position = UDim2.fromOffset(8, 74),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame

	-- 내 줄: 목록 아래 고정
	local mineRow = make("Frame", {
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.new(0, 8, 1, -44),
		BackgroundColor3 = THEME.mine,
		Parent = panel,
	}, { corner(8) }) :: Frame
	make("UIStroke", { Color = THEME.accent, Thickness = 2, Parent = mineRow })
	local mineRank = label({
		Role = "number",
		Size = UDim2.new(0, 70, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Text = "",
		TextColor3 = THEME.accent,
		Parent = mineRow,
	})
	label({
		Size = UDim2.new(1, -200, 1, -8),
		Position = UDim2.fromOffset(80, 4),
		Text = "YOU",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.accent,
		Parent = mineRow,
	})
	local mineValue = label({
		Role = "number",
		Size = UDim2.new(0, 120, 1, -8),
		Position = UDim2.new(1, -126, 0, 4),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = THEME.good,
		Parent = mineRow,
	})

	local formats: { [string]: (number) -> string } = {}
	for _, t in tabSpecs do
		if t.format then
			formats[t.id] = t.format
		end
	end
	local function fmt(id: string, v: number): string
		local f = formats[id]
		return if f then f(v) else Format.short(v)
	end

	local result: { [string]: any }? = nil
	local current = if tabSpecs[1] then tabSpecs[1].id else ""
	local tabs: { [string]: TextButton } = {}

	local function render()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local res = result
		if not res then
			note.Text = "Loading..."
			mineRow.Visible = false
			return
		end
		note.Text = if res.live
			then "All servers · updates every minute"
			else "This server only (global board offline)"
		for _, b in res.boards do
			local tab = tabs[b.id]
			if tab then
				tab.BackgroundColor3 = if b.id == current then THEME.accent else THEME.button
				tab.TextColor3 = if b.id == current then THEME.accentInk else THEME.ink
			end
			if b.id ~= current then
				continue
			end
			for rank, e in b.entries do
				local mine = e.userId == me
				local row = make("Frame", {
					Size = UDim2.new(1, -8, 0, 34),
					BackgroundColor3 = if mine then THEME.mine else THEME.card,
					LayoutOrder = rank,
					Parent = list,
				}, { corner(8) })
				label({
					Size = UDim2.new(0, 44, 1, -8),
					Position = UDim2.fromOffset(6, 4),
					Text = "#" .. rank,
					Role = "number",
					AutoLocalize = false,
					TextColor3 = THEME.medals[rank] or THEME.dim,
					Parent = row,
				})
				-- 1~3위: 메달 색 트로피 + 줄 색
				if rank <= 3 then
					row.BackgroundColor3 = THEME.medals[rank]:Lerp(THEME.card, 0.7)
					Ui.icon("Trophy", {
						Size = UDim2.fromOffset(30, 30),
						Position = UDim2.new(1, -150, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						ImageColor3 = THEME.medals[rank]:Lerp(Color3.new(1, 1, 1), 0.4),
						Parent = row,
					})
				end
				label({
					-- 1~3위는 트로피(오른쪽 -150~-120) 앞에서 이름이 끝나게 줄인다 (긴 이름이 트로피에 깔리지 않게)
					Size = UDim2.new(1, if rank <= 3 then -210 else -170, 1, -8),
					Position = UDim2.fromOffset(54, 4),
					Text = e.name,
					AutoLocalize = false, -- 플레이어 이름은 번역 캡처하지 않는다
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = if mine then THEME.accent else THEME.ink,
					Parent = row,
				})
				label({
					Size = UDim2.new(0, 110, 1, -8),
					Position = UDim2.new(1, -116, 0, 4),
					Text = fmt(b.id, e.value),
					Role = "number",
					AutoLocalize = false,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = THEME.good,
					Parent = row,
				})
			end
			if #b.entries == 0 then
				label({ Size = UDim2.new(1, -8, 0, 30), Text = "No records yet", TextColor3 = THEME.dim, Parent = list })
			end
			-- 내 줄: 목록에 있으면 그 순위, 없으면 '50+'. 값은 서버가 지금 계산한 내 값
			local myRank: number? = nil
			for rank, e in b.entries do
				if e.userId == me then
					myRank = rank
					break
				end
			end
			mineRow.Visible = true
			Loc.raw(mineRank, if myRank then "#" .. myRank else `{res.top or 50}+`)
			Loc.raw(mineValue, fmt(b.id, b.mine or 0))
		end
	end

	local n = math.max(1, #tabSpecs)
	for _, spec in tabSpecs do
		tabs[spec.id] = Ui.button({ Size = UDim2.new(1 / n, -4, 1, 0), Text = spec.label, Parent = tabBar }, function()
			current = spec.id
			render()
		end)
		if spec.icon then
			Ui.addIcon(tabs[spec.id], spec.icon, 1.2)
		end
	end

	local function refresh()
		local ok, res = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and res then
			result = res
		end
		render()
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible then
			render()
			task.spawn(refresh)
		end
	end)

	return { panel = panel }
end

return LeaderboardUi
