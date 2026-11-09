--!strict
-- 다음 목표 바 (2026-10-19, docs/13 §9.4): 화면 위 가운데에 "지금 뭘 향해 가는지"를 항상 보여 준다.
--   트레이 최고 등급 < 이번 환생 천장 → "MAKE T{n}" (등급 막대)
--   천장 도달                       → "REBIRTH" (현금/환생 비용 막대, 누르면 REBIRTH 탭)
--   환생 끝                         → 도감 채우기
-- 아래 한 줄: 지금 할 수 있는 일 힌트(도감 보상·강화·코어·훔치기)를 돌아가며 보여 주고, 누르면 그 패널을 연다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Game.Economy)
local Format = require(ReplicatedStorage.Core.Format)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Loc = require(ReplicatedStorage.CoreClient.Loc)
local Fx = require(script.Parent.Fx)

local THEME = Ui.THEME
local make, label, corner = Ui.make, Ui.label, Ui.corner

local GoalBar = {}

export type Actions = {
	upgrades: (tab: string) -> (),
	collection: () -> (),
	cores: () -> (),
	daily: () -> (),
}

type Hint = { text: Loc.Text, color: Color3, go: () -> () }

local HINT_SECONDS = 4
local READY = Color3.fromRGB(255, 205, 70)

function GoalBar.new(gui: ScreenGui, actions: Actions)
	local root = make("TextButton", {
		Size = UDim2.fromOffset(330, 58), -- 왼쪽 현금 패널(12~312)과 안 겹치게: 화면 폭 970 단위 이상이면 여유
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	}, { corner(12) }) :: TextButton
	make("UIStroke", { Color = THEME.outline, Thickness = 2, Parent = root })
	local title = label({
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 3),
		Text = "",
		TextScaled = true,
		TextStrokeTransparency = 0.3,
		Parent = root,
	})
	local barBack = make("Frame", {
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 24),
		BackgroundColor3 = Color3.fromRGB(25, 23, 40),
		Parent = root,
	}, { corner(6) }) :: Frame
	local barFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.accent,
		Parent = barBack,
	}, { corner(6) }) :: Frame
	local barText = label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextScaled = true,
		TextStrokeTransparency = 0.2,
		ZIndex = 3,
		Parent = barBack,
	})
	local hintButton = make("TextButton", {
		Size = UDim2.new(1, -16, 0, 15),
		Position = UDim2.fromOffset(8, 41),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = THEME.dim,
		Text = "",
		Parent = root,
	}) :: TextButton

	local goalAction: (() -> ())? = nil
	local hints: { Hint } = {}
	local hintIndex = 0
	local hintAt = 0
	local lastKind = ""

	root.Activated:Connect(function()
		if goalAction then
			Ui.click()
			goalAction()
		end
	end)
	hintButton.Activated:Connect(function()
		local h = hints[hintIndex]
		if h then
			Ui.click()
			h.go()
		end
	end)

	local function showHint()
		local h = hints[hintIndex]
		if h then
			Loc.apply(
				hintButton,
				if Loc.isMsg(h.text) then Loc.msg("hint.arrow", { text = h.text }) else `▶ {h.text}`
			)
		else
			Loc.raw(hintButton, "")
		end
		hintButton.TextColor3 = if h then h.color else THEME.dim
	end

	-- upgradesAvailable: Upgrades.render가 돌려준 "살 수 있는 개수"
	local function render(s: { [string]: any }, upgradesAvailable: number)
		local ceiling = Economy.tierCeiling(s.rebirths)
		-- 리버스 조건은 이번 판 최고 등급(runBest): 상한 큐브를 한 번 만들었으면 리버스 단계로
		local top = math.max(s.trayTop or 0, s.runBest or 0)
		local kind
		if top < ceiling then
			kind = "tier"
			Loc.set(title, "goal.makeTier", { tier = top + 1 })
			title.TextColor3 = THEME.ink
			barFill.Size = UDim2.fromScale(math.clamp(top / ceiling, 0, 1), 1)
			barFill.BackgroundColor3 = Color3.fromRGB(150, 230, 255)
			Loc.set(barText, "goal.tierBar", { tier = top, max = ceiling })
			goalAction = nil
		elseif s.rebirthCost then
			local p = math.clamp(s.cash / s.rebirthCost, 0, 1)
			local nextCeil = Economy.tierCeiling(s.rebirths + 1)
			local perk = Loc.format("goal.perk", { mult = Economy.REBIRTH_MULT })
				.. (if nextCeil > ceiling then ` · T{nextCeil}` else "")
			kind = if p >= 1 then "rebirthReady" else "rebirth"
			Loc.set(title, if p >= 1 then "goal.rebirthReady" else "goal.rebirthNext", { perk = perk })
			title.TextColor3 = if p >= 1 then READY else THEME.ink
			barFill.Size = UDim2.fromScale(p, 1)
			barFill.BackgroundColor3 = if p >= 1 then READY else THEME.accent
			Loc.raw(barText, `${Format.short(s.cash)} / ${Format.short(s.rebirthCost)}  ({math.floor(p * 100)}%)`)
			goalAction = function()
				actions.upgrades("REBIRTH")
			end
		else
			local col = s.collection
			kind = "codex"
			Loc.plain(title, "MAX REBIRTH! COMPLETE THE COLLECTION")
			title.TextColor3 = READY
			barFill.Size = UDim2.fromScale(math.clamp(col.count / col.total, 0, 1), 1)
			barFill.BackgroundColor3 = Color3.fromRGB(150, 230, 255)
			Loc.set(barText, "goal.found", { n = col.count, total = col.total })
			goalAction = actions.collection
		end
		if kind ~= lastKind then
			if lastKind ~= "" then
				Fx.bump(root, 0.2)
			end
			lastKind = kind
		end

		-- 할 수 있는 일 힌트
		table.clear(hints)
		local col = s.collection
		local rewards = if col and col.milestoneReady then 1 else 0
		for _ in (col and col.unclaimed) or {} do
			rewards += 1
		end
		if rewards > 0 then
			table.insert(hints, {
				text = if rewards > 1 then Loc.msg("hint.rewards", { n = rewards }) else Loc.msg("hint.reward"),
				color = READY,
				go = actions.collection,
			})
		end
		local d = s.daily
		if d and d.big > 0 then
			table.insert(hints, { text = "PLAY GIFT READY! TAP TO OPEN", color = READY, go = actions.daily })
		elseif d and d.small > 0 then
			table.insert(
				hints,
				{ text = Loc.msg("hint.quickGift", { n = d.small }), color = READY, go = actions.daily }
			)
		end
		if d then
			for _, q in d.quests do
				if not q.done and q.n >= q.target then
					table.insert(hints, { text = "QUEST DONE! CLAIM GEMS", color = READY, go = actions.daily })
					break
				end
			end
		end
		local ready = 0
		for _, h in s.hatching or {} do
			if h and h.remaining <= 0 then
				ready += 1
			end
		end
		if ready > 0 then
			table.insert(hints, {
				text = if ready > 1 then Loc.msg("hint.cores", { n = ready }) else Loc.msg("hint.core"),
				color = THEME.good,
				go = actions.cores,
			})
		end
		if upgradesAvailable > 0 then
			table.insert(hints, {
				text = if upgradesAvailable > 1
					then Loc.msg("hint.upgrades", { n = upgradesAvailable })
					else Loc.msg("hint.upgrade"),
				color = THEME.good,
				go = function()
					actions.upgrades("DROPPERS")
				end,
			})
		end
		if kind ~= "tier" then
			-- 천장에서 기다리는 동안 할 일: 변이 사냥·훔치기
			local steals = if s.steal then s.steal.free + s.steal.paid else 0
			if steals > 0 then
				table.insert(hints, {
					text = Loc.msg("hint.steal", { n = steals, key = Ui.hint(" (E)", "", " (R1)") }),
					color = Color3.fromRGB(255, 140, 120),
					go = function() end,
				})
			end
			table.insert(hints, {
				text = "HUNT RARE VARIANTS: each new one = gems",
				color = Color3.fromRGB(170, 200, 255),
				go = actions.collection,
			})
		end
		local now = os.clock()
		if hintIndex > #hints or now - hintAt >= HINT_SECONDS then
			hintIndex = if #hints > 0 then hintIndex % #hints + 1 else 0
			hintAt = now
		end
		showHint()
	end

	return { frame = root, render = render }
end

return GoalBar
