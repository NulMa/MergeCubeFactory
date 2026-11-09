--!strict
-- 도감·꾸미기 패널 (docs/16 §3): CODEX 탭(등급 × 변이 칸) + STYLE 탭(꾸미기 잠김/해금/장착).
-- 위젯은 한 번 만들고 상태가 올 때마다 글자·색만 바꾼다.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Game.AssetIds)
local Config = require(ReplicatedStorage.Game.Config)
local Economy = require(ReplicatedStorage.Game.Economy)
local VariantDecor = require(ReplicatedStorage.Game.VariantDecor)
local ShopDef = require(ReplicatedStorage.Game.Shop)
local Ui = require(ReplicatedStorage.CoreClient.Ui)
local Fx = require(script.Parent.Fx)
local Loc = require(ReplicatedStorage.CoreClient.Loc)
local ShopUi = require(script.Parent.ShopUi)
local PetLook = require(script.Parent.PetLook)
local Pets = require(ReplicatedStorage.Game.Pets)

local THEME = Ui.THEME
local make, label, corner, button = Ui.make, Ui.label, Ui.corner, Ui.button

export type Ctx = {
	gui: ScreenGui,
	remotes: { [string]: any },
	getState: () -> { [string]: any }?,
	toast: (Loc.Text) -> (),
}

local SLOT_TITLE = {
	bat = "BAT SKIN",
	pet = "PET",
	aura = "AURA",
	trail = "TRAIL",
	tray = "FACTORY FLOOR",
	dropper = "CUBE DROPPER",
	island = "ISLAND GROUND",
}

-- 도감 칸: 한 페이지 = 등급 10개(5×2). ViewportFrame도 이 개수만 만든다
local GRID_COLS, GRID_ROWS = 5, 2
local PAGE_SIZE = GRID_COLS * GRID_ROWS
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 255, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 110, 255)),
})
local SPARKLE_POS = {
	UDim2.new(0.2, 0, 0, 22),
	UDim2.new(0.82, 0, 0, 14),
	UDim2.new(0.78, 0, 0, 56),
}
local SILHOUETTE = Color3.fromRGB(14, 12, 24)
-- 도감 칸 카메라 (정면 -Z·윗면·오른쪽 면이 보이는 각도). 변이 꾸미기가 큰 칸은 뒤로 물러난다
local CAM_POS = Vector3.new(2.6, 2.4, -4.4)
local DECOR_ZOOM = { Rainbow = 1.35, Galaxy = 1.5, Cosmic = 1.85, Divine = 1.25 } :: { [string]: number }

local Collection = {}

function Collection.new(ctx: Ctx)
	local r = ctx.remotes
	local player = Players.LocalPlayer

	local panel = make("Frame", {
		Size = UDim2.fromOffset(460, 448), -- 변이 탭 두 줄만큼 높임(도감 칸 크기는 그대로)
		-- 하단 가운데: 왼쪽 위 Roblox 채팅창과 겹치면 채팅이 탭 클릭을 가로챈다
		Position = UDim2.new(0.5, 0, 1, -90),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		Parent = ctx.gui,
	}, { corner(14) }) :: Frame

	-- 탭
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local function show(name: string)
		for n, page in pages do
			page.Visible = n == name
			tabButtons[n].BackgroundColor3 = if n == name then THEME.accent else THEME.button
			tabButtons[n].TextColor3 = if n == name then THEME.accentInk else THEME.ink
		end
	end
	-- 카테고리 탭 (2026-10-19 사용자 "도감 카테고리별 페이지 세분화"): CODEX = 큐브 변이 도감, PETS = 펫 도감,
	-- 나머지는 꾸미기 칸 묶음 (STYLE_TABS)
	local TABS = { "CODEX", "PETS", "BATS", "AURAS", "TRAILS", "FACTORY" }
	local TAB_LABEL = { CODEX = "CUBES" }
	local tabW = (460 - 16 - 48) / #TABS
	for i, name in TABS do
		tabButtons[name] = button({
			Size = UDim2.fromOffset(tabW - 4, 40),
			Position = UDim2.fromOffset(8 + (i - 1) * tabW, 8),
			Text = TAB_LABEL[name] or name,
			TextScaled = true,
			Parent = panel,
		}, function()
			show(name)
		end)
		make("UITextSizeConstraint", { MaxTextSize = 16, Parent = tabButtons[name] })
		pages[name] = make("Frame", {
			Size = UDim2.new(1, -16, 1, -64),
			Position = UDim2.fromOffset(8, 56),
			BackgroundTransparency = 1,
			Parent = panel,
		}) :: Frame
	end

	-- 닫기: 패널이 HUD의 COLLECTION 버튼을 덮으므로 따로 둔다 (플레이테스트 2026-10-18)
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
	-- CODEX: 위 = 발견 수 + 다음 마일스톤 막대, 아래 = 변이별 줄 × 등급 칸
	------------------------------------------------------------------
	local codex = pages.CODEX
	local countLabel = label({ Size = UDim2.new(1, 0, 0, 30), Text = "", Parent = codex })
	local barBack = make("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 34),
		BackgroundColor3 = Color3.fromRGB(25, 23, 40),
		Parent = codex,
	}, { corner(6) }) :: Frame
	local barFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(150, 230, 255),
		Parent = barBack,
	}, { corner(6) }) :: Frame
	local barText = label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextStrokeTransparency = 0.3,
		ZIndex = 3,
		Parent = barBack,
	})
	-- 받을 마일스톤이 있으면 막대 전체가 버튼이 된다 (클릭 보상, 2026-10-19)
	local CLAIM = Color3.fromRGB(255, 205, 70)
	local claimBusy = false
	local function claim(what: string, from: GuiObject)
		if claimBusy then
			return
		end
		claimBusy = true
		local ok, gems = pcall(function()
			return r.ClaimCodex:InvokeServer(what)
		end)
		claimBusy = false
		if ok and typeof(gems) == "number" and gems > 0 then
			Fx.purchase(from) -- 연속으로 받으면 동전 소리가 한 음씩 올라간다
		end
	end
	local milestoneButton = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		ZIndex = 4,
		Parent = barBack,
	}) :: TextButton
	milestoneButton.Activated:Connect(function()
		claim("milestone", barBack)
	end)

	-- 변이 탭(한 번에 한 변이) + 페이지(등급 PAGE_SIZE개씩). 칸 위젯 PAGE_SIZE개를 만들어 두고 내용만 바꿔 쓴다
	local variantTabs: { [number]: TextButton } = {}
	local currentV = 2
	local currentPage = 1
	local pageCount = math.ceil(Economy.MAX_TIER / PAGE_SIZE)
	local refreshCodex: () -> ()
	-- 변이 탭은 두 줄(한 줄에 TAB_COLS개): 6개를 한 줄에 넣으면 글자가 너무 작아진다
	local nTabs = #Economy.VARIANTS - 1
	local TAB_COLS = math.ceil(nTabs / 2)
	local TAB_H = 26
	for v = 2, #Economy.VARIANTS do
		local col = (v - 2) % TAB_COLS
		local row = (v - 2) // TAB_COLS
		variantTabs[v] = button({
			Size = UDim2.new(1 / TAB_COLS, -4, 0, TAB_H),
			Position = UDim2.new(col / TAB_COLS, 2, 0, 62 + row * (TAB_H + 3)),
			Text = "",
			Parent = codex,
		}, function()
			currentV = v
			currentPage = 1
			refreshCodex()
		end)
	end
	local tabsBottom = 62 + math.ceil(nTabs / TAB_COLS) * (TAB_H + 3)
	local effectLabel = label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, tabsBottom + 1),
		Text = "",
		Font = Enum.Font.GothamBold,
		Parent = codex,
	})
	local grid = make("Frame", {
		Size = UDim2.new(1, 0, 1, -(tabsBottom + 57)),
		Position = UDim2.fromOffset(0, tabsBottom + 25),
		BackgroundTransparency = 1,
		Parent = codex,
	}) :: Frame
	local prevButton = button({
		Size = UDim2.fromOffset(56, 26),
		Position = UDim2.new(0, 0, 1, -28),
		Text = "<",
		Parent = codex,
	}, function()
		currentPage = math.max(1, currentPage - 1)
		refreshCodex()
	end)
	local nextButton = button({
		Size = UDim2.fromOffset(56, 26),
		Position = UDim2.new(1, 0, 1, -28),
		AnchorPoint = Vector2.new(1, 0),
		Text = ">",
		Parent = codex,
	}, function()
		currentPage = math.min(pageCount, currentPage + 1)
		refreshCodex()
	end)
	local pageLabel = label({
		Size = UDim2.new(1, -128, 0, 22),
		Position = UDim2.new(0, 64, 1, -26),
		Text = "",
		TextColor3 = THEME.dim,
		Font = Enum.Font.GothamBold,
		Parent = codex,
	})

	type Cell = {
		frame: Frame,
		stroke: UIStroke,
		gradient: UIGradient,
		vp: ViewportFrame,
		cube: Part,
		face: Decal,
		tierText: TextLabel,
		nameText: TextLabel,
		statusText: TextLabel,
		sparkles: { ImageLabel },
		tier: number,
		found: boolean,
		claimButton: TextButton,
		rewardBadge: TextLabel,
		decor: { VariantDecor.Piece }?, -- 변이 꾸미기 조각 (도감에서도 보이게, 2026-10-20 사용자)
	}
	local cells: { Cell } = {}
	-- 정면(-Z)·윗면·오른쪽 면이 보이는 각도
	local camCf = CFrame.lookAt(CAM_POS, Vector3.zero)
	for i = 1, PAGE_SIZE do
		local col = (i - 1) % GRID_COLS
		local row = (i - 1) // GRID_COLS
		local f = make("Frame", {
			Size = UDim2.new(1 / GRID_COLS, -6, 1 / GRID_ROWS, -6),
			Position = UDim2.new(col / GRID_COLS, 3, row / GRID_ROWS, 3),
			BackgroundColor3 = THEME.card,
			Parent = grid,
		}, { corner(8) }) :: Frame
		local stroke = make("UIStroke", {
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = f,
		}) :: UIStroke
		local gradient = make("UIGradient", { Enabled = false, Color = RAINBOW, Parent = stroke }) :: UIGradient
		local vp = make("ViewportFrame", {
			Size = UDim2.new(1, -8, 1, -38),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			LightDirection = Vector3.new(-0.6, -1, 0.4),
			Parent = f,
		}) :: ViewportFrame
		local cam = make("Camera", { FieldOfView = 34, CFrame = camCf, Parent = vp }) :: Camera
		vp.CurrentCamera = cam
		local cube = make("Part", {
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(),
			Anchored = true,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = vp,
		}) :: Part
		local face =
			make("Decal", { Texture = AssetIds.Images.Face, Face = Enum.NormalId.Front, Parent = cube }) :: Decal
		local sparkles: { ImageLabel } = {}
		for k, pos in SPARKLE_POS do
			sparkles[k] = make("ImageLabel", {
				Size = UDim2.fromOffset(18, 18),
				Position = pos,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = AssetIds.Images.Sparkle,
				Visible = false,
				ZIndex = 3,
				Parent = f,
			}) :: ImageLabel
		end
		local tierText = label({
			Size = UDim2.fromOffset(34, 16),
			Position = UDim2.fromOffset(4, 3),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 0.2,
			ZIndex = 4,
			Parent = f,
		})
		local nameText = label({
			Size = UDim2.new(1, -6, 0, 17),
			Position = UDim2.new(0, 3, 1, -34),
			Text = "",
			Parent = f,
		})
		local statusText = label({
			Size = UDim2.new(1, -6, 0, 13),
			Position = UDim2.new(0, 3, 1, -16),
			Text = "",
			Font = Enum.Font.GothamBold,
			Parent = f,
		})
		local claimButton = make("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			Visible = false,
			ZIndex = 5,
			Parent = f,
		}) :: TextButton
		-- 받을 보상 표시: 오른쪽 위 금색 ◆ 배지 (칸 밖으로 살짝 튀어나옴)
		local rewardBadge = label({
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, 6, 0, -6),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(255, 205, 70),
			TextColor3 = THEME.accentInk,
			Text = "◆",
			Visible = false,
			ZIndex = 6,
			Parent = f,
		})
		make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = rewardBadge })
		make("UIStroke", { Color = THEME.outline, Thickness = 2, Parent = rewardBadge })
		cells[i] = {
			frame = f,
			claimButton = claimButton,
			rewardBadge = rewardBadge,
			stroke = stroke,
			gradient = gradient,
			vp = vp,
			cube = cube,
			face = face,
			tierText = tierText,
			nameText = nameText,
			statusText = statusText,
			sparkles = sparkles,
			tier = 0,
			found = false,
		}
	end

	for _, cell in cells do
		cell.claimButton.Activated:Connect(function()
			claim(Economy.codexKey(cell.tier, currentV), cell.frame)
		end)
	end

	-- 칸 채우기: 발견 = 등급 색 + 변이 재질·테두리·반짝이, 미발견 = 검은 실루엣(등급·이름은 그대로 보임)
	local lastCol: { [string]: any }? = nil
	local animated: { Cell } = {}
	-- 맥동시킬 것들 (받을 보상 칸 테두리·변이 탭·페이지 화살표)
	local pulsing: { UIStroke } = {}
	local tabBadges: { [number]: TextLabel } = {}
	local function strokeOf(g: GuiObject): UIStroke
		local st = g:FindFirstChild("ClaimStroke") :: UIStroke?
		if not st then
			st = make("UIStroke", {
				Name = "ClaimStroke",
				Thickness = 3,
				Color = CLAIM,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Enabled = false,
				Parent = g,
			}) :: UIStroke
		end
		return st :: UIStroke
	end
	local function tabBadge(v: number): TextLabel
		local b = tabBadges[v]
		if not b then
			b = label({
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(1, 4, 0, -6),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 0,
				BackgroundColor3 = THEME.bad,
				Text = "",
				Visible = false,
				ZIndex = 6,
				Parent = variantTabs[v],
			})
			make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
			tabBadges[v] = b
		end
		return b
	end
	refreshCodex = function()
		table.clear(pulsing)
		local found = if lastCol then lastCol.found else {}
		local def = Economy.VARIANTS[currentV]
		local vstyle = Config.VARIANT_STYLE[def.id]
		local tag = if vstyle then vstyle.tag else THEME.ink
		local unclaimed = if lastCol and lastCol.unclaimed then lastCol.unclaimed else {}
		for v, b in variantTabs do
			local vd = Economy.VARIANTS[v]
			local st = Config.VARIANT_STYLE[vd.id]
			local n, todo = 0, 0
			for t = 1, Economy.MAX_TIER do
				local key = Economy.codexKey(t, v)
				if found[key] then
					n += 1
				end
				if unclaimed[key] then
					todo += 1
				end
			end
			Loc.set(b, "codex.tab", { variant = if st then st.label else vd.id, n = n, max = Economy.MAX_TIER })
			local badge = tabBadge(v)
			badge.Visible = todo > 0
			badge.Text = tostring(todo)
			local ts = strokeOf(b)
			ts.Enabled = todo > 0
			if todo > 0 then
				table.insert(pulsing, ts)
			end
			b.BackgroundColor3 = if v == currentV then (if st then st.tag else THEME.accent) else THEME.button
			b.TextColor3 = if v == currentV then THEME.accentInk else THEME.ink
		end
		effectLabel.Text = `x{def.mult} income · first find +{def.gems}◆ · same variants fuse up!`
		effectLabel.TextColor3 = tag
		local first = (currentPage - 1) * PAGE_SIZE + 1
		local last = math.min(Economy.MAX_TIER, first + PAGE_SIZE - 1)
		-- 다른 페이지에 받을 보상이 있으면 그쪽 화살표를 금색으로
		local before, here, after = 0, 0, 0
		for t = 1, Economy.MAX_TIER do
			if unclaimed[Economy.codexKey(t, currentV)] then
				if t < first then
					before += 1
				elseif t > last then
					after += 1
				else
					here += 1
				end
			end
		end
		Loc.raw(
			pageLabel,
			Loc.format("codex.page", { first = first, last = last, page = currentPage, pages = pageCount })
				.. (if here > 0 then "   " .. Loc.format("codex.toClaim", { n = here }) else "")
		)
		pageLabel.TextColor3 = if here > 0 then CLAIM else THEME.dim
		local function styleArrow(arrow: TextButton, count: number, enabled: boolean, glyph: string)
			arrow.Text = if count > 0 then (if glyph == "<" then `◆{count} <` else `> ◆{count}`) else glyph
			arrow.BackgroundColor3 = if count > 0 then CLAIM else THEME.button
			arrow.TextColor3 = if count > 0 then THEME.accentInk elseif enabled then THEME.ink else THEME.dim
			local as = strokeOf(arrow)
			as.Enabled = count > 0
			if count > 0 then
				table.insert(pulsing, as)
			end
		end
		styleArrow(prevButton, before, currentPage > 1, "<")
		styleArrow(nextButton, after, currentPage < pageCount, ">")
		table.clear(animated)
		for i, cell in cells do
			local t = first + i - 1
			cell.tier = t
			cell.frame.Visible = t <= Economy.MAX_TIER
			if t > Economy.MAX_TIER then
				continue
			end
			local isFound = found[Economy.codexKey(t, currentV)] == true
			cell.found = isFound
			-- 꾸미기: 지난 그림을 지우고, 찾은 칸에만 다시. 큰 꾸미기(성운·꼬리)는 카메라를 뒤로
			if cell.decor then
				for _, p in cell.decor do
					p.part:Destroy()
				end
				cell.decor = nil
			end
			local zoom = DECOR_ZOOM[def.id] or 1
			local cam = cell.vp.CurrentCamera
			if cam then
				cam.CFrame = CFrame.lookAt(CAM_POS * zoom, Vector3.new(0, if def.id == "Divine" then 0.4 else 0, 0))
			end
			if isFound and VariantDecor.has(def.id) then
				cell.decor = VariantDecor.place(cell.vp, cell.cube.CFrame, def.id, cell.cube.Size.X)
			end
			local base = Config.TIER_COLORS[t] or Color3.new(1, 1, 1)
			local band = Config.tierBand(t)
			local cube, vp = cell.cube, cell.vp
			Loc.raw(cell.tierText, `T{t}`)
			cell.nameText.Text = Config.TIER_NAMES[t] or ""
			if isFound then
				cube.Color = if vstyle and vstyle.color then base:Lerp(vstyle.color, vstyle.blend) else base
				local mat = if vstyle then vstyle.material else band.material
				-- ViewportFrame엔 주변 환경이 없어 반사·Glass가 색을 하얗게 바랜다 → 반사 0, Glass는 매끈한 플라스틱
				cube.Material = if mat == Enum.Material.Glass then Enum.Material.SmoothPlastic else mat
				cube.Reflectance = 0
				cell.face.Texture = Config.faceFor(t)
				cell.face.Transparency = 0
				vp.ImageColor3 = Color3.new(1, 1, 1)
				vp.Ambient = Color3.fromRGB(170, 170, 185)
				vp.LightColor = Color3.new(1, 1, 1)
				cell.frame.BackgroundColor3 = base:Lerp(THEME.card, 0.78)
				cell.stroke.Color = if vstyle then vstyle.outline else tag
				cell.stroke.Transparency = 0
				cell.stroke.Thickness = if vstyle and vstyle.pulse then 3 else 2
				cell.nameText.TextColor3 = THEME.ink
				Loc.plain(cell.statusText, if vstyle then vstyle.label else def.id)
				cell.statusText.TextColor3 = tag
				cell.tierText.TextColor3 = THEME.ink
			else
				cube.Color = SILHOUETTE
				cube.Material = Enum.Material.SmoothPlastic
				cube.Reflectance = 0
				cell.face.Transparency = 1
				vp.ImageColor3 = SILHOUETTE
				vp.Ambient = Color3.new()
				vp.LightColor = Color3.new()
				cell.frame.BackgroundColor3 = THEME.card
				cell.stroke.Color = THEME.dim
				cell.stroke.Transparency = 0.7
				cell.stroke.Thickness = 2
				cell.nameText.TextColor3 = THEME.dim
				Loc.plain(cell.statusText, "NOT FOUND")
				cell.statusText.TextColor3 = THEME.dim
				cell.tierText.TextColor3 = THEME.dim
			end
			-- 안 받은 보상: 금색 테두리 + "CLAIM" (칸을 누르면 받음)
			local reward = unclaimed[Economy.codexKey(t, currentV)]
			cell.claimButton.Visible = reward ~= nil
			cell.rewardBadge.Visible = reward ~= nil
			if reward then
				Loc.set(cell.statusText, "codex.tapClaim", { gems = reward })
				cell.statusText.TextColor3 = CLAIM
				cell.frame.BackgroundColor3 = Color3.fromRGB(110, 85, 30) -- 금빛 바탕
				cell.stroke.Color = CLAIM
				cell.stroke.Thickness = 4
				table.insert(pulsing, cell.stroke)
			end
			local cycle = isFound and vstyle ~= nil and vstyle.cycle
			local sparkle = isFound and vstyle ~= nil and vstyle.sparkle
			cell.gradient.Enabled = cycle and reward == nil
			if cycle and reward == nil then
				cell.stroke.Color = Color3.new(1, 1, 1)
			end
			for _, sp in cell.sparkles do
				sp.Visible = sparkle
				sp.ImageColor3 = tag:Lerp(Color3.new(1, 1, 1), 0.5)
			end
			if cycle or sparkle then
				table.insert(animated, cell)
			end
		end
	end

	-- 애니메이션: 패널·CODEX 탭이 보일 때만 RenderStepped 하나
	local animConn: RBXScriptConnection? = nil
	local function updateAnim()
		local want = panel.Visible and pages.CODEX.Visible
		if want and not animConn then
			animConn = RunService.RenderStepped:Connect(function()
				local now = os.clock()
				local vstyle = Config.VARIANT_STYLE[Economy.VARIANTS[currentV].id]
				-- 받을 보상: 금색 ↔ 흰색 맥동 + 두께 출렁
				local a = 0.5 + 0.5 * math.sin(now * 6)
				for _, st in pulsing do
					st.Color = CLAIM:Lerp(Color3.new(1, 1, 1), a)
					st.Thickness = 3 + a * 2
				end
				for _, cell in cells do
					local decor = cell.decor
					if decor and cell.frame.Visible then
						for _, p in decor do
							p.part.CFrame = cell.cube.CFrame * VariantDecor.pose(p, now)
						end
					end
				end
				for _, cell in animated do
					if vstyle and vstyle.cycle then
						local hue = (now * 0.25 + cell.tier * 0.07) % 1
						local c = Color3.fromHSV(hue, 0.6, 1)
						cell.cube.Color = if vstyle.color then c:Lerp(vstyle.color, vstyle.blend) else c
						cell.gradient.Rotation = (now * 90) % 360
					elseif vstyle and vstyle.pulse and cell.found and not cell.rewardBadge.Visible then
						-- Cosmic·Divine: 테두리가 두 색 사이를 맥동 (어두운 Cosmic도 실루엣과 구분)
						local a = 0.5 + 0.5 * math.sin(now * 3 + cell.tier * 0.5)
						cell.stroke.Color = vstyle.outline:Lerp(vstyle.pulse, a)
					end
					for k, sp in cell.sparkles do
						if sp.Visible then
							local a = math.sin(now * 3 + k * 2.1 + cell.tier)
							sp.ImageTransparency = 0.15 + 0.85 * (1 - a * a)
							sp.Rotation = (now * 60 + k * 40) % 360
						end
					end
				end
			end)
		elseif not want and animConn then
			animConn:Disconnect()
			animConn = nil
		end
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(updateAnim)
	pages.CODEX:GetPropertyChangedSignal("Visible"):Connect(updateAnim)

	------------------------------------------------------------------
	-- STYLE: 꾸미기 목록 (칸 제목 + 줄마다 이름·조건·버튼)
	------------------------------------------------------------------
	local SLOT_TAB: { [string]: string } = {
		bat = "BATS",
		aura = "AURAS",
		trail = "TRAILS",
		tray = "FACTORY",
		dropper = "FACTORY",
		island = "FACTORY",
	}
	local styleLists: { [string]: ScrollingFrame } = {}
	for _, tab in { "BATS", "AURAS", "TRAILS", "FACTORY" } do
		styleLists[tab] = make("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Parent = pages[tab],
		}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	end

	-- 꾸미기 미리보기 (2026-10-19, "치장 탭 직관성"): 배트·바닥·드로퍼 = 작은 3D, 오라 = 반짝이, 꼬리 = 빛줄기
	local function viewport(parent: Frame, build: (Model) -> (), camCf: CFrame): ViewportFrame
		local vp = make("ViewportFrame", {
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(5, 3),
			BackgroundColor3 = Color3.fromRGB(30, 28, 48),
			LightDirection = Vector3.new(-0.6, -1, 0.4),
			Ambient = Color3.fromRGB(170, 170, 185),
			Parent = parent,
		}, { corner(8) }) :: ViewportFrame
		local cam = make("Camera", { FieldOfView = 40, CFrame = camCf, Parent = vp }) :: Camera
		vp.CurrentCamera = cam
		local m = Instance.new("Model")
		build(m)
		m.Parent = vp
		return vp
	end
	local function piece(m: Model, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material)
		make("Part", {
			Shape = shape,
			Size = size,
			CFrame = cf,
			Color = color,
			-- 뷰포트엔 주변 환경이 없어 반사·유리가 하얗게 바랜다 → 반사 0, 유리는 반투명 플라스틱
			Material = if mat == Enum.Material.Glass then Enum.Material.SmoothPlastic else mat,
			Transparency = if mat == Enum.Material.Glass then 0.25 else 0,
			Reflectance = 0,
			Anchored = true,
			Parent = m,
		})
	end
	local function rainbowAt(i: number, n: number): Color3
		return Color3.fromHSV((i - 1) / n * 0.8, 0.65, 1)
	end
	-- 메시(배트·펫) 미리보기: 가장 긴 축을 세로로 세우고 len 크기로
	local function meshPart(m: Model, mesh: Config.MeshDef, len: number, upright: boolean)
		local longest = math.max(mesh.size.X, mesh.size.Y, mesh.size.Z)
		local scale = len / longest
		local axis = if not upright
			then CFrame.new()
			elseif mesh.size.X == longest then CFrame.Angles(0, 0, math.rad(90))
			elseif mesh.size.Z == longest then CFrame.Angles(math.rad(90), 0, 0)
			else CFrame.new()
		local flip = if upright and mesh.flip then CFrame.Angles(math.rad(180), 0, 0) else CFrame.new()
		-- 납작한 메시(생선)는 얇은 면이 화면 옆으로 가면 선으로만 보인다 (사용자 보고 2026-10-19):
		-- 가장 얇은 축이 화면 가로(X)로 가면 세로축으로 90도 돌려 넓은 면이 카메라를 보게
		local s = mesh.size
		local thinAxis = if s.X <= s.Y and s.X <= s.Z
			then Vector3.xAxis
			elseif s.Y <= s.Z then Vector3.yAxis
			else Vector3.zAxis
		local face = if upright and math.abs((axis:VectorToWorldSpace(thinAxis)).X) > 0.9
			then CFrame.Angles(0, math.rad(90), 0)
			else CFrame.new()
		local p = make("Part", {
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.Angles(0, 0, if upright then math.rad(-40) else 0) * flip * face * axis,
			Anchored = true,
			Parent = m,
		})
		make("SpecialMesh", {
			MeshType = Enum.MeshType.FileMesh,
			MeshId = `rbxassetid://{mesh.id}`,
			TextureId = if mesh.tex then `rbxassetid://{mesh.tex}` else "",
			Scale = Vector3.new(scale, scale, scale),
			Parent = p,
		})
	end
	local function textureId(name: string): string
		if string.find(name, "://", 1, true) then
			return name
		end
		return (AssetIds.Images :: any)[name] or ""
	end
	local function preview(def: Config.Cosmetic, parent: Frame)
		local c1 = def.color or (def.colors and def.colors[1]) or Color3.fromRGB(150, 150, 170)
		local c2 = (def.colors and def.colors[#def.colors]) or c1
		if def.mesh then
			local mesh = def.mesh
			viewport(
				parent,
				function(m)
					meshPart(m, mesh, if def.slot == "bat" then 4.6 else 2.6, def.slot == "bat")
				end,
				if def.slot == "bat"
					then CFrame.lookAt(Vector3.new(0, 0, -7), Vector3.zero)
					else CFrame.lookAt(Vector3.new(2.2, 1.4, -3.6), Vector3.zero)
			)
			return
		elseif def.slot == "pet" and def.cube then
			viewport(parent, function(m)
				piece(m, Enum.PartType.Block, Vector3.new(1.6, 1.6, 1.6), CFrame.new(), c1, Enum.Material.SmoothPlastic)
				local face = m:FindFirstChildOfClass("Part")
				if face then
					make(
						"Decal",
						{ Face = Enum.NormalId.Back, Texture = (AssetIds.Images :: any).FaceHappy or "", Parent = face }
					)
				end
			end, CFrame.lookAt(Vector3.new(1.6, 1.2, -3.2), Vector3.zero))
			return
		elseif def.texture then
			-- 모양 오라·무늬 꼬리: 그 모양 그림을 색 입혀 보여 줌
			local holder = make("Frame", {
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(5, 3),
				BackgroundColor3 = Color3.fromRGB(30, 28, 48),
				Parent = parent,
			}, { corner(8) }) :: Frame
			local tex = textureId(def.texture)
			for k, spec in { { 30, 0.42, 0.45 }, { 16, 0.78, 0.25 }, { 13, 0.78, 0.8 } } do
				make("ImageLabel", {
					Size = UDim2.fromOffset(spec[1], spec[1]),
					Position = UDim2.fromScale(spec[2], spec[3]),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = tex,
					ImageColor3 = if k == 1 then c1 else c2,
					Parent = holder,
				})
			end
			return
		elseif def.slot == "island" then
			-- 섬 바닥 판 + 작은 나무
			viewport(parent, function(m)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(4.4, 0.8, 4.4),
					CFrame.new(),
					c1,
					def.material or Enum.Material.Grass
				)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(1.6, 1.2, 1.6),
					CFrame.new(0.6, 1, 0.4),
					Color3.fromRGB(48, 46, 73),
					Enum.Material.SmoothPlastic
				)
			end, CFrame.lookAt(Vector3.new(4.6, 4.4, -6), Vector3.new(0, 0.3, 0)))
			return
		end
		if def.slot == "pet" then
			local holder = make("Frame", {
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(5, 3),
				BackgroundColor3 = Color3.fromRGB(30, 28, 48),
				Parent = parent,
			}, { corner(8) }) :: Frame
			label({ Size = UDim2.fromScale(1, 1), Text = "—", TextColor3 = THEME.dim, Parent = holder })
			return
		end
		if def.slot == "bat" then
			-- 대각선으로 누운 배트: 그립(검정) → 몸통(스킨) + 띠
			viewport(parent, function(m)
				local tilt = CFrame.Angles(0, 0, math.rad(50))
				local function seg(y0: number, y1: number, d: number, color: Color3, mat: Enum.Material)
					piece(
						m,
						Enum.PartType.Cylinder,
						Vector3.new(y1 - y0, d, d),
						tilt * CFrame.new((y0 + y1) / 2 - 1.4, 0, 0),
						color,
						mat
					)
				end
				local grip = Color3.fromRGB(30, 30, 34)
				local mat = def.material or Enum.Material.Metal
				seg(-1.25, -1.05, 0.62, grip, Enum.Material.SmoothPlastic)
				seg(-1.05, 1.0, 0.4, grip, Enum.Material.Fabric)
				seg(1.0, 1.8, 0.55, if def.rainbow then rainbowAt(1, 3) else c1, mat)
				seg(1.8, 2.1, 0.7, if def.rainbow then rainbowAt(2, 3) else c1, mat)
				seg(2.1, 3.85, 0.82, if def.rainbow then rainbowAt(3, 3) else c1, mat)
				seg(2.35, 2.75, 0.84, def.band or Color3.fromRGB(230, 60, 60), Enum.Material.SmoothPlastic)
			end, CFrame.lookAt(Vector3.new(0, 0.6, -6), Vector3.new(0, 0.6, 0)))
		elseif def.slot == "tray" then
			-- 바닥 판 + 큐브 두 개
			viewport(parent, function(m)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(4, 0.4, 4),
					CFrame.new(),
					c1,
					def.material or Enum.Material.SmoothPlastic
				)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(1, 1, 1),
					CFrame.new(-0.7, 0.7, 0.3),
					Color3.fromRGB(150, 230, 255),
					Enum.Material.SmoothPlastic
				)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(1.3, 1.3, 1.3),
					CFrame.new(0.8, 0.85, -0.5),
					Color3.fromRGB(255, 200, 120),
					Enum.Material.SmoothPlastic
				)
			end, CFrame.lookAt(Vector3.new(4.6, 5, -6), Vector3.new(0, 0.2, 0)))
		elseif def.slot == "dropper" then
			-- 드로퍼 상자 + 아래 깔때기
			viewport(parent, function(m)
				local col = Color3.fromRGB(150, 155, 170)
				local mat = def.material or Enum.Material.Metal
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(2.4, 1.6, 2.4),
					CFrame.new(0, 0.6, 0),
					if mat == Enum.Material.Neon then Color3.fromRGB(110, 200, 255) else col,
					mat
				)
				piece(
					m,
					Enum.PartType.Block,
					Vector3.new(1.2, 0.8, 1.2),
					CFrame.new(0, -0.6, 0),
					col:Lerp(Color3.new(0, 0, 0), 0.3),
					Enum.Material.Metal
				)
			end, CFrame.lookAt(Vector3.new(3, 2.6, -3.8), Vector3.new(0, 0.1, 0)))
		else
			local holder = make("Frame", {
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(5, 3),
				BackgroundColor3 = Color3.fromRGB(30, 28, 48),
				Parent = parent,
			}, { corner(8) }) :: Frame
			local seq = if def.rainbow
				then ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 140)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 255)),
				})
				else ColorSequence.new(c1, c2)
			if not def.colors and not def.rainbow then
				label({ Size = UDim2.fromScale(1, 1), Text = "—", TextColor3 = THEME.dim, Parent = holder })
			elseif def.slot == "aura" then
				-- 큰 반짝이 + 작은 반짝이 두 개 (오라 색)
				for k, spec in { { 34, 0.5, 0.5 }, { 16, 0.2, 0.22 }, { 14, 0.8, 0.78 } } do
					local img = Ui.icon("Sparkle4", {
						Size = UDim2.fromOffset(spec[1], spec[1]),
						Position = UDim2.fromScale(spec[2], spec[3]),
						AnchorPoint = Vector2.new(0.5, 0.5),
						ImageColor3 = if k == 1 then Color3.new(1, 1, 1) else c2,
						Parent = holder,
					})
					if img and k == 1 then
						make("UIGradient", { Color = seq, Rotation = 45, Parent = img })
					end
				end
			else
				-- 꼬리: 오른쪽으로 가늘어지며 사라지는 빛줄기 두 가닥
				for k, y in { 0.38, 0.66 } do
					local streak = make("Frame", {
						Size = UDim2.new(0.8, 0, 0, if k == 1 then 9 else 6),
						Position = UDim2.fromScale(0.1, y),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						Parent = holder,
					}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
					make("UIGradient", {
						Color = seq,
						Transparency = NumberSequence.new(0, 0.85),
						Parent = streak,
					})
				end
			end
		end
	end
	local SLOT_ICON: { [string]: { any } } = {
		bat = { "Bat", Color3.new(1, 1, 1) },
		aura = { "Sparkle4", Color3.fromRGB(255, 225, 120) },
		trail = { "Shine", Color3.fromRGB(150, 220, 255) },
		tray = { "Star", Color3.new(1, 1, 1) },
		dropper = { "Drop", Color3.new(1, 1, 1) },
		pet = { "Hatch", Color3.new(1, 1, 1) },
		island = { "Trophy", Color3.fromRGB(150, 230, 140) },
	}

	type Row = { def: Config.Cosmetic, sub: TextLabel, buy: TextButton }
	local rowsUi: { Row } = {}
	local order = 0
	for _, slot in Config.COSMETIC_SLOTS do
		order += 1
		local style = styleLists[SLOT_TAB[slot] or "FACTORY"]
		local header = label({
			Size = UDim2.new(1, -10, 0, 30),
			Text = SLOT_TITLE[slot] or slot,
			TextColor3 = THEME.accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			Parent = style,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 36), Parent = header })
		local hi = SLOT_ICON[slot]
		if hi then
			Ui.icon(hi[1], {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.fromOffset(-34, 0),
				ImageColor3 = hi[2],
				Parent = header,
			})
		end
		for _, def in Config.COSMETICS do
			if def.slot ~= slot then
				continue
			end
			order += 1
			local f = make("Frame", {
				Size = UDim2.new(1, -10, 0, 50),
				BackgroundColor3 = THEME.card,
				LayoutOrder = order,
				Parent = style,
			}, { corner(8) }) :: Frame
			preview(def, f)
			label({
				Size = UDim2.new(0.55, -58, 0, 26),
				Position = UDim2.fromOffset(58, 3),
				Text = def.name,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = f,
			})
			local sub = label({
				Size = UDim2.new(0.55, -58, 0, 18),
				Position = UDim2.fromOffset(58, 29),
				Text = "",
				TextColor3 = THEME.dim,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = f,
			})
			local b: TextButton
			b = button({
				Size = UDim2.new(0.4, -8, 0, 38),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Text = "",
				Parent = f,
			}, function()
				local s = ctx.getState()
				if not s then
					return
				end
				local col = s.collection
				if col.equipped[def.slot] == def.id and Config.defaultCosmetic(def.slot).id == def.id then
					return
				end
				if col.unlocked[def.id] then
					-- 낀 걸 다시 누르면 벗음 (서버 Collection.equip)
					if (r.Equip :: RemoteFunction):InvokeServer(def.id) then
						Fx.purchase(b)
					end
				elseif col.blocked and col.blocked[def.id] then
					ctx.toast(`Unlock {col.blocked[def.id]} first`)
				elseif def.gems then
					if s.gems < def.gems then
						ctx.toast(Loc.msg("codex.needGems", { need = def.gems, have = s.gems }))
					elseif (r.BuyCosmetic :: RemoteFunction):InvokeServer(def.id) then
						Fx.purchase(b)
						ctx.toast(`{def.name} unlocked!`)
					end
				elseif def.shop then
					if not ShopUi.prompt(def.shop) then
						ctx.toast("Coming soon")
					end
				elseif def.codex then
					ctx.toast(Loc.msg("codex.discoverToUnlock", { n = def.codex }))
				end
			end)
			table.insert(rowsUi, { def = def, sub = sub, buy = b })
		end
	end
	order += 1
	local gemButton = button({
		Size = UDim2.new(1, -10, 0, 44),
		Text = "",
		BackgroundColor3 = Color3.fromRGB(150, 230, 255),
		TextColor3 = THEME.accentInk,
		LayoutOrder = order,
		Visible = false,
		Parent = styleLists.AURAS,
	}, function()
		local s = ctx.getState()
		if s and s.collection.gemProduct then
			MarketplaceService:PromptProductPurchase(player, s.collection.gemProduct)
		end
	end)
	Ui.addIcon(gemButton, "GemPack", 1.3)
	Ui.shine(gemButton, 3)

	------------------------------------------------------------------
	-- PETS: 펫 도감 (알별 줄, 못 본 펫은 검은 실루엣 + ???). 별은 가져 본 최고 별
	------------------------------------------------------------------
	local petCount = label({ Size = UDim2.new(1, 0, 0, 28), Text = "", Parent = pages.PETS })
	local petList = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -32),
		Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = pages.PETS,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) }) :: ScrollingFrame
	type PetCell = { vp: ViewportFrame, name: TextLabel, stars: TextLabel, stroke: UIStroke, def: Pets.PetDef }
	local petCells: { PetCell } = {}
	for i, egg in Pets.EGGS do
		label({
			Size = UDim2.new(1, -10, 0, 22),
			Text = egg.name,
			TextColor3 = egg.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i * 2 - 1,
			Parent = petList,
		})
		local row = make("Frame", {
			Size = UDim2.new(1, -10, 0, 92),
			BackgroundTransparency = 1,
			LayoutOrder = i * 2,
			Parent = petList,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for k, def in Pets.eggPets(egg.id) do
			local rar = Pets.rarity(def.rarity)
			local cell = make("Frame", {
				Size = UDim2.fromOffset(68, 90),
				BackgroundColor3 = Color3.fromRGB(30, 28, 48),
				LayoutOrder = k,
				Parent = row,
			}, { corner(8) })
			local stroke = make("UIStroke", { Color = rar.color, Thickness = 2, Parent = cell }) :: UIStroke
			local vp = make("ViewportFrame", {
				Size = UDim2.fromOffset(64, 58),
				Position = UDim2.fromOffset(2, 2),
				BackgroundTransparency = 1,
				LightDirection = Vector3.new(-0.5, -1, -0.6),
				Ambient = Color3.fromRGB(180, 180, 195),
				ImageColor3 = SILHOUETTE,
				Parent = cell,
			}) :: ViewportFrame
			local cam = make("Camera", { FieldOfView = 34, Parent = vp }) :: Camera
			vp.CurrentCamera = cam
			local m = PetLook.still(def.id, 1)
			if m then
				local len = (m:GetAttribute("Len") :: number?) or 2.4
				cam.CFrame = CFrame.lookAt(Vector3.new(len * 0.9, len * 0.55, -len * 1.9), Vector3.zero)
				m.Parent = vp
			end
			local name = label({
				Size = UDim2.new(1, -4, 0, 14),
				Position = UDim2.fromOffset(2, 60),
				Text = "???",
				TextScaled = true,
				Font = Enum.Font.GothamBold,
				TextColor3 = THEME.dim,
				Parent = cell,
			})
			local stars = label({
				Size = UDim2.new(1, -4, 0, 14),
				Position = UDim2.fromOffset(2, 74),
				Text = rar.name,
				TextScaled = true,
				TextColor3 = rar.color,
				Parent = cell,
			})
			table.insert(petCells, { vp = vp, name = name, stars = stars, stroke = stroke, def = def })
		end
	end
	local function renderPets(s: { [string]: any })
		local seen = s.pets and s.pets.seen or {}
		local n = 0
		for _, c in petCells do
			local best = seen[c.def.id]
			if best then
				n += 1
				c.vp.ImageColor3 = Color3.new(1, 1, 1)
				c.name.Text = c.def.name
				c.name.TextColor3 = THEME.ink
				-- 별 + 그 별의 효율 (2026-10-19 "별만 뜨고 %가 안 나옴")
				Loc.raw(
					c.stars,
					`{string.rep("★", best)} +{math.floor(Pets.bonus(c.def.id, best) * 1000 + 0.5) / 10}%`
				)
			else
				c.vp.ImageColor3 = SILHOUETTE
				c.name.Text = "???"
				c.name.TextColor3 = THEME.dim
				Loc.plain(c.stars, Pets.rarity(c.def.rarity).name)
			end
		end
		Loc.set(petCount, "codex.petsFound", { n = n, total = #Pets.LIST })
	end

	show("CODEX")
	refreshCodex()

	------------------------------------------------------------------
	-- 갱신
	------------------------------------------------------------------
	local lastCount: number? = nil
	local function render(s: { [string]: any })
		local col = s.collection
		if not col then
			return
		end
		Loc.set(countLabel, "codex.found", { n = col.count, total = col.total, gems = s.gems })
		local nm = col.nextMilestone
		milestoneButton.Visible = col.milestoneReady == true
		barFill.BackgroundColor3 = if col.milestoneReady then CLAIM else Color3.fromRGB(150, 230, 255)
		if nm and col.milestoneReady then
			barFill.Size = UDim2.fromScale(1, 1)
			Loc.set(barText, "codex.milestoneReady", { gems = nm.gems, n = nm.count })
		elseif nm then
			barFill.Size = UDim2.fromScale(math.clamp(col.count / nm.count, 0, 1), 1)
			Loc.set(barText, "codex.milestoneNext", { gems = nm.gems, n = nm.count })
		else
			barFill.Size = UDim2.fromScale(1, 1)
			Loc.plain(barText, "COLLECTION COMPLETE!")
		end
		lastCol = col
		refreshCodex()
		renderPets(s)
		if lastCount and col.count > lastCount then
			Fx.bump(countLabel, 0.25)
		end
		lastCount = col.count
		for _, row in rowsUi do
			local def = row.def
			local unlocked = col.unlocked[def.id] == true
			local equipped = col.equipped[def.slot] == def.id
			local b = row.buy
			local isDefault = Config.defaultCosmetic(def.slot).id == def.id
			-- 단계식 오라: 단계와 넉백 저항을 늘 보여 준다
			local tierInfo = if def.tier
				then `T{def.tier} · knockback -{math.floor(Economy.auraResist(def.tier) * 100 + 0.5)}%`
				else nil
			if equipped then
				Loc.plain(b, if isDefault then "EQUIPPED" else "UNEQUIP")
				b.BackgroundColor3 = if isDefault then THEME.card else Color3.fromRGB(240, 150, 70)
				b.TextColor3 = if isDefault then THEME.good else THEME.accentInk
				row.sub.Text = tierInfo or "in use"
			elseif unlocked then
				Loc.plain(b, "EQUIP")
				b.BackgroundColor3 = THEME.good
				b.TextColor3 = THEME.accentInk
				row.sub.Text = tierInfo or "unlocked"
			elseif col.blocked and col.blocked[def.id] then
				Loc.plain(b, `◆ {def.gems or 0}`)
				b.BackgroundColor3 = THEME.button
				b.TextColor3 = THEME.dim
				row.sub.Text = `unlock {col.blocked[def.id]} first`
			elseif def.shop then
				local item = ShopDef.item(def.shop)
				Loc.plain(b, if item then `R$ {item.price}` else "SHOP")
				b.BackgroundColor3 = THEME.accent
				b.TextColor3 = THEME.accentInk
				row.sub.Text = if item then item.name else "shop"
			elseif def.gems then
				local can = s.gems >= def.gems
				Loc.plain(b, `◆ {def.gems}`)
				b.BackgroundColor3 = if can then Color3.fromRGB(150, 230, 255) else THEME.button
				b.TextColor3 = if can then THEME.accentInk else THEME.dim
				row.sub.Text = tierInfo or "buy with gems"
			else
				local need = math.min(def.codex or 0, col.total)
				Loc.set(b, "codex.locked", { n = col.count, need = need })
				b.BackgroundColor3 = THEME.button
				b.TextColor3 = THEME.dim
				row.sub.Text = `discover {need} special cubes`
			end
		end
		gemButton.Visible = col.gemProduct ~= nil
		gemButton.Text = `GET {col.gemPack}◆`
	end

	-- 패널을 열 때: 안 받은 보상이 있으면 그 변이 탭·페이지로 바로 이동
	local function focusReward()
		local unclaimed = lastCol and lastCol.unclaimed
		if not unclaimed then
			return
		end
		for v = 2, #Economy.VARIANTS do
			for t = 1, Economy.MAX_TIER do
				if unclaimed[Economy.codexKey(t, v)] then
					currentV = v
					currentPage = (t - 1) // PAGE_SIZE + 1
					show("CODEX")
					refreshCodex()
					return
				end
			end
		end
	end

	return {
		panel = panel,
		render = render,
		focusReward = focusReward,
	}
end

return Collection
