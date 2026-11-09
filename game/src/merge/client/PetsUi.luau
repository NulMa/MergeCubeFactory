--!strict
-- 펫 화면 (docs/24): HUD 버튼(일일 선물 아래) + 패널 [EGGS | MY PETS] + 알 깨기 연출.
-- 서버 server/Pets가 뽑고 저장한다. 여기서는 보여 주고 의도만 보낸다(PetHatch, PetAction).
-- 확률표는 알 카드에 그대로 공개한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Core.Format)
local Pets = require(ReplicatedStorage.Game.Pets)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Fx = require(script.Parent.Fx)
local Loc = require(ReplicatedStorage.CoreClient.Loc)
local PetLook = require(script.Parent.PetLook)

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

local PetsUi = {}

local SHARD = "◇"
local SHARD_COLOR = Color3.fromRGB(140, 235, 255)
local STAR_TEXT = { "", "★★", "★★★" }
local STAR_COLOR = { Color3.new(1, 1, 1), Color3.fromRGB(255, 205, 70), Color3.fromRGB(255, 120, 230) }

export type Opts = {
	gui: ScreenGui,
	remotes: { [string]: Instance },
	getState: () -> { [string]: any }?,
	toast: (Loc.Text) -> (),
}

local function pct(x: number): string
	local v = x * 100
	return if v >= 10 or v == math.floor(v) then `{math.floor(v + 0.5)}%` else string.format("%.1f%%", v)
end

local function chanceText(c: number): string
	local v = c * 100
	if v >= 1 then
		return `{math.floor(v * 10 + 0.5) / 10}%`
	end
	return string.format("%.2f%%", v)
end

-- 펫 미리보기 뷰포트 (모델은 고정, 카메라만)
local function petViewport(id: string, star: number, props: { [string]: any }): ViewportFrame
	local vp = make("ViewportFrame", props) :: ViewportFrame
	vp.LightDirection = Vector3.new(-0.5, -1, -0.6)
	vp.Ambient = Color3.fromRGB(180, 180, 195)
	local cam = make("Camera", { FieldOfView = 34, Parent = vp }) :: Camera
	vp.CurrentCamera = cam
	local m = PetLook.still(id, star)
	if m then
		local len = (m:GetAttribute("Len") :: number?) or 2.4
		-- 정면(-Z)에서 살짝 오른쪽 위
		cam.CFrame = CFrame.lookAt(Vector3.new(len * 0.9, len * 0.55, -len * 1.9), Vector3.zero)
		m.Parent = vp
	end
	return vp
end

function PetsUi.new(opts: Opts)
	local gui = opts.gui
	local hatchRemote = opts.remotes.PetHatch :: RemoteFunction
	local actionRemote = opts.remotes.PetAction :: RemoteFunction
	local panel: Frame

	-- HUD 버튼 ------------------------------------------------------------------
	local hud = button({
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.fromOffset(12, 210), -- 일일 선물(12,164) 아래
		BackgroundColor3 = Color3.fromRGB(90, 170, 120),
		Text = "PETS",
		Parent = gui,
	}, function()
		panel.Visible = not panel.Visible
	end)
	Ui.addIcon(hud, if Ui.hasIcon("Egg1") then "Egg1" else "Hatch", 1.3)

	panel = make("Frame", {
		Size = UDim2.fromOffset(500, 470),
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = gui,
	}, { corner(14) }) :: Frame

	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local current = "EGGS"
	local function show(name: string)
		current = name
		for n, page in pages do
			page.Visible = n == name
			tabButtons[n].BackgroundColor3 = if n == name then THEME.accent else THEME.button
			tabButtons[n].TextColor3 = if n == name then THEME.accentInk else THEME.ink
		end
	end
	-- 알 뽑기(EGGS)는 광장 PET EGGS 발판 위에서만 (2026-10-20 사용자 "펫 가챠도 발판 방식으로").
	-- PETS 버튼은 MY PETS(장착·합치기)만 연다
	for i, name in { "EGGS", "MY PETS" } do
		tabButtons[name] = button({
			Size = UDim2.fromOffset(150, 40),
			Position = UDim2.fromOffset(8 + (i - 1) * 158, 8),
			Text = name,
			Visible = name ~= "EGGS",
			Parent = panel,
		}, function()
			show(name)
		end)
		pages[name] = make("Frame", {
			Size = UDim2.new(1, -16, 1, -64),
			Position = UDim2.fromOffset(8, 56),
			BackgroundTransparency = 1,
			Parent = panel,
		}) :: Frame
	end
	local shardLabel = label({
		Size = UDim2.fromOffset(130, 40),
		Position = UDim2.new(1, -56, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Text = `{SHARD} 0`,
		AutoLocalize = false,
		TextColor3 = SHARD_COLOR,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})
	button({
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Text = "X",
		BackgroundColor3 = THEME.bad,
		Parent = panel,
	}, function()
		panel.Visible = false
	end)

	------------------------------------------------------------------
	-- 알 깨기 연출 (전체 화면)
	------------------------------------------------------------------
	local overlay = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 8, 20),
		BackgroundTransparency = 0.25,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	}) :: TextButton
	local revealing = false
	local canClose = false
	local afterReveal: (() -> ())? = nil -- 연출을 닫은 뒤 (상점 다시 열기)
	overlay.Activated:Connect(function()
		if canClose then
			overlay.Visible = false
			revealing = false
			local f = afterReveal
			afterReveal = nil
			if f then
				f()
			end
		end
	end)

	local function reveal(egg: Pets.EggDef, results: { { u: number, id: string, star: number, new: boolean } })
		revealing = true
		canClose = false
		overlay:ClearAllChildren()
		overlay.Visible = true
		local n = #results
		local spacing = 210
		local eggs: { GuiObject } = {}
		for i = 1, n do
			local x = (i - (n + 1) / 2) * spacing
			local holder = make("Frame", {
				Size = UDim2.fromOffset(190, 190),
				Position = UDim2.new(0.5, x, 0.45, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 41,
				Parent = overlay,
			})
			local icon = Ui.icon(egg.icon, {
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 42,
				Parent = holder,
			}) or Ui.icon("Hatch", {
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ImageColor3 = egg.color,
				ZIndex = 42,
				Parent = holder,
			})
			if icon then
				table.insert(eggs, icon)
			end
		end
		-- 흔들림이 점점 세짐
		Fx.sound("Whoosh", nil, 0.4, 0.8)
		local t0 = os.clock()
		while os.clock() - t0 < 1.5 do
			local k = (os.clock() - t0) / 1.5
			for j, e in eggs do
				e.Rotation = math.sin(os.clock() * (14 + k * 30) + j) * (6 + k * 22)
				e.Size = UDim2.fromScale(0.8 + k * 0.12, 0.8 + k * 0.12)
			end
			RunService.RenderStepped:Wait()
		end
		Fx.screenFlash(Color3.new(1, 1, 1), 0.7, 0.35)
		Fx.sound("Pop", nil, 0.9, 0.8)
		local best = 1
		for _, r in results do
			local def = Pets.get(r.id)
			if def then
				best = math.max(best, Pets.rarityIndex(def.rarity))
			end
		end
		overlay:ClearAllChildren()
		for i, r in results do
			local def = Pets.get(r.id)
			if not def then
				continue
			end
			local rar = Pets.rarity(def.rarity)
			local x = (i - (n + 1) / 2) * spacing
			local card = make("Frame", {
				Size = UDim2.fromOffset(190, 250),
				Position = UDim2.new(0.5, x, 0.47, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 41,
				Parent = overlay,
			})
			local burst = Ui.icon("Sunburst", {
				Size = UDim2.fromOffset(260, 260),
				Position = UDim2.fromOffset(95, 95),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ImageColor3 = rar.color,
				ImageTransparency = 0.25,
				ZIndex = 41,
				Parent = card,
			})
			if burst then
				Ui.spin(burst, 40)
			end
			local vp = petViewport(r.id, r.star, {
				Size = UDim2.fromOffset(170, 170),
				Position = UDim2.fromOffset(95, 95),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 42,
				Parent = card,
			})
			-- 펫이 천천히 돈다
			task.spawn(function()
				local cam = vp.CurrentCamera
				local start = os.clock()
				while vp.Parent and cam do
					local a = (os.clock() - start) * 1.2
					local m = vp:FindFirstChildOfClass("Model")
					local len = m and (m:GetAttribute("Len") :: number?) or 2.4
					cam.CFrame = CFrame.lookAt(
						Vector3.new(math.sin(a) * len * 2, len * 0.55, -math.cos(a) * len * 2),
						Vector3.zero
					)
					RunService.RenderStepped:Wait()
				end
			end)
			label({
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.fromOffset(0, 180),
				Text = def.name,
				TextScaled = true,
				ZIndex = 43,
				Parent = card,
			})
			label({
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 210),
				Loc = Loc.msg(
					"pets.rarityBonus",
					{ rarity = string.upper(rar.name), pct = pct(Pets.bonus(r.id, r.star)) }
				),
				TextColor3 = rar.color,
				TextScaled = true,
				ZIndex = 43,
				Parent = card,
			})
			if r.new then
				local newTag = label({
					Size = UDim2.fromOffset(70, 26),
					Position = UDim2.fromOffset(150, 14),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 0,
					BackgroundColor3 = THEME.bad,
					Text = "NEW!",
					ZIndex = 44,
					Parent = card,
				})
				corner(8).Parent = newTag
				Ui.wiggle(newTag, 8)
			end
			card.Size = UDim2.fromOffset(60, 80)
			TweenService:Create(
				card,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(190, 250) }
			):Play()
		end
		if best >= 4 then
			Fx.sound("Fanfare", nil, 0.7)
			Fx.screenFlash(Pets.RARITIES[best].color, 0.5, 0.6)
		else
			Fx.sound("Chime", nil, 0.6)
		end
		label({
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromScale(0, 0.8),
			Text = Ui.hint("Click to continue", "Tap to continue"),
			TextColor3 = THEME.dim,
			ZIndex = 43,
			Parent = overlay,
		})
		task.wait(0.5)
		canClose = true
	end

	------------------------------------------------------------------
	-- EGGS
	------------------------------------------------------------------
	local eggList = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = pages.EGGS,
	}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	label({
		Size = UDim2.new(1, -10, 0, 22),
		Text = `Merge cubes to earn {SHARD} shards (higher tiers = more)`,
		TextColor3 = SHARD_COLOR,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 0,
		Parent = eggList,
	})
	type EggRow = { egg: Pets.EggDef, b1: TextButton, b3: TextButton }
	local eggRows: { EggRow } = {}
	local busy = false
	local reopenEggs: (Vector2) -> () = function() end -- 아래 발판 모드에서 채운다
	-- 지금 PET EGGS 발판 위인가 (client/Stations와 같은 판정)
	local function onEggPad(): boolean
		local folder = workspace:FindFirstChild("Stations")
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not folder or not root then
			return false
		end
		for _, m in folder:GetChildren() do
			local center = m:GetAttribute("Center")
			local radius = m:GetAttribute("Radius")
			if m:GetAttribute("Kind") == "eggs" and typeof(center) == "Vector3" and typeof(radius) == "number" then
				local off = root.Position - center
				return (off * Vector3.new(1, 0, 1)).Magnitude <= radius + 1 and off.Y > -2 and off.Y < 8
			end
		end
		return false
	end
	local function doHatch(egg: Pets.EggDef, count: number)
		if busy or revealing then
			return
		end
		local s = opts.getState()
		local shards = s and s.pets and s.pets.shards or 0
		if shards < egg.cost * count then
			opts.toast(Loc.msg("pets.needShards", { shard = SHARD, n = Format.short(egg.cost * count) }))
			return
		end
		busy = true
		local results, why = hatchRemote:InvokeServer(egg.id, count)
		busy = false
		if results then
			-- 연출을 닫으면 상점(EGGS)을 같은 스크롤 위치로 다시 연다 (2026-10-21 사용자 "매번 다시 눌러야 함").
			-- 발판에서 내려왔으면 열지 않는다
			local scroll = eggList.CanvasPosition
			afterReveal = function()
				if onEggPad() then
					reopenEggs(scroll)
				end
			end
			panel.Visible = false
			task.spawn(reveal, egg, results)
		elseif why then
			opts.toast(why)
		end
	end
	for i, egg in Pets.EGGS do
		local f = make("Frame", {
			Size = UDim2.new(1, -10, 0, 150),
			BackgroundColor3 = THEME.card,
			LayoutOrder = i,
			Parent = eggList,
		}, { corner(10) }) :: Frame
		make("UIStroke", { Color = egg.color, Thickness = 2, Transparency = 0.3, Parent = f })
		local icon = Ui.icon(egg.icon, {
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.fromOffset(6, 6),
			Parent = f,
		}) or Ui.icon("Hatch", {
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.fromOffset(6, 6),
			ImageColor3 = egg.color,
			Parent = f,
		})
		if icon then
			Ui.wiggle(icon, 4)
		end
		label({
			Size = UDim2.fromOffset(200, 28),
			Position = UDim2.fromOffset(96, 6),
			Text = egg.name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = f,
		})
		local b1 = button({
			Size = UDim2.fromOffset(110, 34),
			Position = UDim2.new(1, -8, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Text = `x1  {SHARD}{Format.short(egg.cost)}`,
			AutoLocalize = false,
			Parent = f,
		}, function()
			doHatch(egg, 1)
		end)
		local b3 = button({
			Size = UDim2.fromOffset(110, 34),
			Position = UDim2.new(1, -126, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Text = `x3  {SHARD}{Format.short(egg.cost * 3)}`,
			AutoLocalize = false,
			Parent = f,
		}, function()
			doHatch(egg, 3)
		end)
		-- 확률표: 펫 6칸 (미리보기 + 희귀도 색 + %)
		local strip = make("Frame", {
			Size = UDim2.new(1, -100, 0, 104),
			Position = UDim2.fromOffset(96, 42),
			BackgroundTransparency = 1,
			Parent = f,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for k, def in Pets.eggPets(egg.id) do
			local rar = Pets.rarity(def.rarity)
			local cell = make("Frame", {
				Size = UDim2.fromOffset(60, 100),
				BackgroundColor3 = Color3.fromRGB(30, 28, 48),
				LayoutOrder = k,
				Parent = strip,
			}, { corner(8) })
			make("UIStroke", { Color = rar.color, Thickness = 2, Parent = cell })
			petViewport(def.id, 1, {
				Size = UDim2.fromOffset(56, 56),
				Position = UDim2.fromOffset(2, 2),
				BackgroundTransparency = 1,
				Parent = cell,
			})
			label({
				Size = UDim2.new(1, -4, 0, 16),
				Position = UDim2.fromOffset(2, 58),
				Text = chanceText(Pets.chance(def.id)),
				TextColor3 = rar.color,
				TextScaled = true,
				Parent = cell,
			})
			label({
				Size = UDim2.new(1, -4, 0, 14),
				Position = UDim2.fromOffset(2, 76),
				Text = `+{pct(Pets.bonus(def.id, 1))}`,
				AutoLocalize = false,
				TextColor3 = THEME.dim,
				TextScaled = true,
				Font = Enum.Font.GothamBold,
				Parent = cell,
			})
		end
		table.insert(eggRows, { egg = egg, b1 = b1, b3 = b3 })
	end

	------------------------------------------------------------------
	-- MY PETS
	------------------------------------------------------------------
	local mine = pages["MY PETS"]
	local summary = label({
		Size = UDim2.new(1, -150, 0, 30),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = mine,
	})
	button({
		Size = UDim2.fromOffset(140, 30),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Text = "EQUIP BEST",
		BackgroundColor3 = THEME.good,
		TextColor3 = THEME.accentInk,
		Parent = mine,
	}, function()
		actionRemote:InvokeServer("best", 0)
	end)
	local grid = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -128),
		Position = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = mine,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(74, 92),
			CellPadding = UDim2.fromOffset(5, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame
	local emptyLabel = label({
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 80),
		Text = "No pets yet — hatch an egg at the PET EGGS pad in the plaza!",
		TextColor3 = THEME.dim,
		Visible = false,
		Parent = mine,
	})
	-- 아래: 고른 펫 정보 + 버튼
	local detail = make("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = THEME.card,
		Parent = mine,
	}, { corner(10) }) :: Frame
	local detailName = label({
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 4),
		Text = "Tap a pet",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	local selected: number? = nil
	local equipB = button({
		Size = UDim2.new(1 / 3, -8, 0, 40),
		Position = UDim2.new(0, 6, 1, -6),
		AnchorPoint = Vector2.new(0, 1),
		Text = "EQUIP",
		Parent = detail,
	}, function()
		if selected then
			actionRemote:InvokeServer("equip", selected)
		end
	end)
	local fuseB: TextButton
	fuseB = button({
		Size = UDim2.new(1 / 3, -8, 0, 40),
		Position = UDim2.new(1 / 3, 4, 1, -6),
		AnchorPoint = Vector2.new(0, 1),
		Text = "FUSE",
		Parent = detail,
	}, function()
		if not selected then
			return
		end
		local res = actionRemote:InvokeServer("fuse", selected)
		if res then
			selected = res.u
			Fx.purchase(fuseB)
			Fx.sound("LevelUp", nil, 0.7)
			local def = Pets.get(res.id)
			opts.toast(Loc.msg("pets.fused", {
				pet = def and def.name or res.id,
				stars = STAR_TEXT[res.star],
				pct = pct(Pets.bonus(res.id, res.star)),
			}))
		else
			opts.toast(Loc.msg("pets.fuseNeed", { n = Pets.FUSE_COUNT }))
		end
	end)
	local releaseArmed = 0
	local releaseB = button({
		Size = UDim2.new(1 / 3, -8, 0, 40),
		Position = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(1, 1),
		Text = "RELEASE",
		BackgroundColor3 = Color3.fromRGB(120, 70, 90),
		Parent = detail,
	}, function()
		if not selected then
			return
		end
		-- 두 번 눌러야 놓아준다 (실수 방지)
		if os.clock() - releaseArmed > 2.5 then
			releaseArmed = os.clock()
			opts.toast("Tap RELEASE again to confirm")
			return
		end
		releaseArmed = 0
		local refund = actionRemote:InvokeServer("release", selected)
		if refund then
			opts.toast(Loc.msg("pets.released", { shard = SHARD, n = Format.short(refund) }))
			selected = nil
		end
	end)

	type Cell = { frame: TextButton, stroke: UIStroke, check: TextLabel, key: string }
	local cells: { [number]: Cell } = {}
	local lastSig = ""

	local function renderDetail(s: { [string]: any })
		local list = s.pets.list
		local p = nil
		for _, q in list do
			if q.u == selected then
				p = q
			end
		end
		if not p then
			selected = nil
			Loc.plain(detailName, "Tap a pet to equip, fuse or release")
			equipB.Visible, fuseB.Visible, releaseB.Visible = false, false, false
			return
		end
		local def = Pets.get(p.id)
		local rar = Pets.rarity(def and def.rarity or "common")
		local same = 0
		for _, q in list do
			if q.id == p.id and q.star == p.star then
				same += 1
			end
		end
		local equipped = table.find(s.pets.equipped, p.u) ~= nil
		Loc.set(detailName, "pets.detail", {
			pet = def and def.name or p.id,
			stars = STAR_TEXT[p.star],
			rarity = rar.name,
			pct = pct(Pets.bonus(p.id, p.star)),
		})
		detailName.TextColor3 = rar.color
		equipB.Visible, fuseB.Visible, releaseB.Visible = true, true, true
		equipB.Text = if equipped then "UNEQUIP" else "EQUIP"
		equipB.BackgroundColor3 = if equipped then Color3.fromRGB(240, 150, 70) else THEME.good
		equipB.TextColor3 = THEME.accentInk
		if p.star >= Pets.MAX_STAR then
			fuseB.Text = "MAX ★"
			fuseB.BackgroundColor3 = THEME.button
		else
			fuseB.Text = `FUSE {math.min(same, Pets.FUSE_COUNT)}/{Pets.FUSE_COUNT}`
			fuseB.BackgroundColor3 = if same >= Pets.FUSE_COUNT then THEME.accent else THEME.button
			fuseB.TextColor3 = if same >= Pets.FUSE_COUNT then THEME.accentInk else THEME.dim
		end
		Loc.set(
			releaseB,
			"pets.release",
			{ shard = SHARD, n = Format.short(Pets.releaseValue(p.id) * 3 ^ (p.star - 1)) }
		)
	end

	local function renderGrid(s: { [string]: any })
		local list = table.clone(s.pets.list) :: { any }
		local eq = s.pets.equipped
		-- 장착 먼저, 그다음 강한 순
		table.sort(list, function(a, b)
			local ea, eb = table.find(eq, a.u) ~= nil, table.find(eq, b.u) ~= nil
			if ea ~= eb then
				return ea
			end
			return Pets.better(a, b)
		end)
		local sig = {}
		for _, p in list do
			table.insert(sig, `{p.u}:{p.star}:{if table.find(eq, p.u) then 1 else 0}`)
		end
		local sigText = table.concat(sig, ",")
		if sigText == lastSig then
			return
		end
		lastSig = sigText
		local alive: { [number]: boolean } = {}
		for order, p in list do
			alive[p.u] = true
			local key = `{p.id}:{p.star}`
			local c: Cell? = cells[p.u]
			if c and c.key ~= key then
				c.frame:Destroy()
				c = nil
			end
			if not c then
				local def = Pets.get(p.id)
				local rar = Pets.rarity(def and def.rarity or "common")
				local uid = p.u
				local f = make("TextButton", {
					BackgroundColor3 = Color3.fromRGB(30, 28, 48),
					Text = "",
					AutoButtonColor = true,
					Parent = grid,
				}, { corner(8) }) :: TextButton
				local stroke = make("UIStroke", {
					Color = rar.color,
					Thickness = 2,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Parent = f,
				}) :: UIStroke
				petViewport(p.id, p.star, {
					Size = UDim2.fromOffset(70, 66),
					Position = UDim2.fromOffset(2, 2),
					BackgroundTransparency = 1,
					Parent = f,
				})
				-- 아래: 지금 별 기준 효율(%), 별은 오른쪽 위에 따로 (2026-10-19 "성장한 펫은 별만 뜨고 %가 안 나옴")
				label({
					Size = UDim2.new(1, -4, 0, 18),
					Position = UDim2.new(0, 2, 1, -20),
					Text = `+{pct(Pets.bonus(p.id, p.star))}`,
					AutoLocalize = false,
					TextColor3 = if p.star > 1 then STAR_COLOR[p.star] else rar.color,
					TextScaled = true,
					Parent = f,
				})
				if p.star > 1 then
					label({
						Size = UDim2.new(1, -52, 0, 16),
						Position = UDim2.fromOffset(26, 3), -- 왼쪽 위 장착 체크(22px) 옆, 가운데 정렬
						Text = STAR_TEXT[p.star],
						TextColor3 = STAR_COLOR[p.star],
						TextScaled = true,
						Parent = f,
					})
				end
				local check = label({
					Size = UDim2.fromOffset(22, 22),
					Position = UDim2.fromOffset(2, 2),
					BackgroundTransparency = 0,
					BackgroundColor3 = THEME.good,
					Text = "✓",
					TextColor3 = THEME.accentInk,
					Visible = false,
					Parent = f,
				})
				corner(11).Parent = check
				f.Activated:Connect(function()
					selected = uid
					local st = opts.getState()
					if st and st.pets then
						renderDetail(st)
					end
					for u, cc in cells do
						cc.stroke.Thickness = if u == uid then 4 else 2
					end
				end)
				c = { frame = f, stroke = stroke, check = check, key = key }
				cells[p.u] = c
			end
			local cell = c :: Cell
			cell.frame.LayoutOrder = order
			cell.check.Visible = table.find(eq, p.u) ~= nil
			cell.stroke.Thickness = if p.u == selected then 4 else 2
		end
		for u, c in cells do
			if not alive[u] then
				c.frame:Destroy()
				cells[u] = nil
			end
		end
	end

	-- 더 좋은 알을 살 수 있게 되면 한 번 알린다 (2026-10-21 리뷰: 알은 광장 발판에서만 사서 찾기 어려움)
	local bestAffordable: number? = nil

	-- 상태 갱신 (1초마다 + 행동 직후)
	local function render(s: { [string]: any })
		local ps = s.pets
		if not ps then
			return
		end
		Loc.raw(shardLabel, `{SHARD} {Format.short(ps.shards)}`)
		Loc.set(hud, "pets.hud", { pct = pct(ps.bonus), shard = SHARD, n = Format.short(ps.shards) })
		-- 살 수 있는 알이 있으면 버튼이 눈에 띄게
		local canAny = false
		for _, row in eggRows do
			local ok1 = ps.shards >= row.egg.cost
			local ok3 = ps.shards >= row.egg.cost * 3
			canAny = canAny or ok1
			row.b1.BackgroundColor3 = if ok1 then THEME.accent else THEME.button
			row.b1.TextColor3 = if ok1 then THEME.accentInk else THEME.dim
			row.b3.BackgroundColor3 = if ok3 then THEME.accent else THEME.button
			row.b3.TextColor3 = if ok3 then THEME.accentInk else THEME.dim
		end
		hud.BackgroundColor3 = if canAny then Color3.fromRGB(90, 200, 120) else Color3.fromRGB(70, 120, 95)
		local best = 0
		for i, egg in Pets.EGGS do
			if ps.shards >= egg.cost then
				best = i
			end
		end
		-- 이번 접속에서 처음 닿은 더 좋은 알만 (부화로 조각이 줄었다 다시 모여도 또 알리지 않음)
		local seen = bestAffordable
		if seen == nil then
			bestAffordable = best
		elseif best > seen then
			bestAffordable = best
			opts.toast(Loc.msg("pets.canHatch", { egg = Pets.EGGS[best].name }))
		end
		if not panel.Visible then
			return
		end
		summary.Text =
			`{#ps.list}/{Pets.INVENTORY_CAP} pets · equipped {#ps.equipped}/{Pets.EQUIP_SLOTS} · income +{pct(
				ps.bonus
			)}`
		emptyLabel.Visible = #ps.list == 0
		if current == "MY PETS" then
			renderGrid(s)
			renderDetail(s)
		end
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		local s = opts.getState()
		if panel.Visible and s then
			render(s)
		end
	end)
	tabButtons["MY PETS"].Activated:Connect(function()
		-- 탭 전환(show)이 끝난 뒤 그리기
		task.defer(function()
			local s = opts.getState()
			if s then
				render(s)
			end
		end)
	end)
	-- 발판 모드: 위에 서 있으면 EGGS 탭이 보이고 열린다, 내려오면 닫힌다
	local stationMode = false
	local function setStation(on: boolean)
		stationMode = on
		tabButtons.EGGS.Visible = on
		tabButtons["MY PETS"].Position = UDim2.fromOffset(if on then 166 else 8, 8)
		if not on and current == "EGGS" then
			show("MY PETS")
		end
	end
	local function station(on: boolean)
		if on then
			setStation(true)
			show("EGGS")
			panel.Visible = true
		elseif stationMode then
			panel.Visible = false
		end
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible and stationMode then
			setStation(false)
		end
	end)
	reopenEggs = function(scroll: Vector2)
		station(true)
		task.defer(function()
			eggList.CanvasPosition = scroll
		end)
	end
	setStation(false)
	show("MY PETS")
	renderDetail({ pets = { list = {}, equipped = {} } })

	return { button = hud, panel = panel, render = render, station = station }
end

return PetsUi
