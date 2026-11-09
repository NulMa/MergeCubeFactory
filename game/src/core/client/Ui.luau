--!strict
-- 코드로 만드는 UI 헬퍼 (그레이박스 단계). init.client와 Upgrades가 같이 쓴다.
-- Core client module (docs/33): games call Ui.configure({ icons = ..., clickSound = ... }) once at boot,
-- before building UI. Theme colors can be overridden by assigning Ui.THEME fields before building UI.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Loc = require(script.Parent.Loc)
local Theme = require(script.Parent.Parent.Core.Theme)
local Format = require(script.Parent.Parent.Core.Format)

local Ui = {}

export type Options = {
	icons: { [string]: string }?, -- icon name -> rbxassetid (Ui.icon / addIcon / shine)
	clickSound: string?, -- button click SoundId
	clickVolume: number?,
}

-- Injected by the game (Ui.configure). Empty until then: icons resolve to nil, clicks are silent.
local icons: { [string]: string }? = nil

-- Active theme tokens (docs/33 §Theme). Defaults = the pre-theme look; Ui.theme(tokens) replaces them.
local T: Theme.Tokens = Theme.defaults()
local sfx: { [string]: Sound } = {} -- click / open / close / purchase / notify

-- Live palette: panel, card, button, accent, accentInk, ink, dim, good, bad, lucky, outline (legacy names)
-- plus every palette token (panelAlt, text, textDim, stroke, accent2, buy, medals, ...). Ui.theme fills it in place.
Ui.THEME = {} :: { [string]: any }
Theme.fillLegacy(Ui.THEME, T.palette)

-- Prop keys Ui.make consumes instead of setting on the instance
local META = {
	Parent = true,
	NoDress = true,
	Loc = true,
	Role = true,
	Style = true,
	PanelStyle = true,
	Icon = true,
	IconSize = true,
}

-- 화면 크기 맞춤 (2026-10-19): UI가 화면에서 차지하는 비율을 해상도와 상관없이 일정하게.
-- 기준 1280×720(가로·세로 중 빡빡한 쪽) × 1.02, 터치 화면 × 0.91 (PC 1.2는 너무 크다는 피드백으로 -15%, 2026-10-19;
-- 터치 1.3은 휴대폰에서 너무 크다는 피드백으로 -30%, 2026-10-19). 세로 560 단위는 항상 화면에 들어가게
-- (패널 448 + 아래 버튼 줄 90). 예전 식(720/높이, 0.85~1.4)은 큰 모니터에서 UI가 작아지고 휴대폰에선 넘쳤다.
local REF_W, REF_H, FIT_H = 1280, 720, 560

-- 휴대폰·태블릿 (키보드 없는 터치 화면): 화면 배치를 휴대폰용으로 바꿀 때 쓴다
function Ui.isTouch(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- 조작 안내 문구를 기기별로 고른다 (2026-10-20 "모바일버전엔 키보드안내 제거"): 휴대폰엔 키 이름을 보이지 않는다
function Ui.hint(pc: string, touch: string, pad: string?): string
	local UserInputService = game:GetService("UserInputService")
	if Ui.isTouch() then
		return touch
	elseif pad and UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return pad
	end
	return pc
end

-- 휴대폰: 패널·팝업을 화면에 맞춰 키운다 (UIScale, 1 ~ maxScale배). 전체 UI를 30% 줄인 만큼 읽을 창은 크게 (2026-10-20).
-- reserveTop: 위쪽에 남길 높이(패널 위 지갑 자리). 배수는 속성 FitScale에도 남긴다 (등장 연출이 0 → FitScale로 키우게). 프레임에 UIScale이 이미 있으면 그걸 쓴다
function Ui.touchFit(gui: ScreenGui, frame: GuiObject, maxScale: number?, reserveTop: number?)
	if not Ui.isTouch() then
		return
	end
	local sc = frame:FindFirstChildOfClass("UIScale")
	if not sc then
		local made = Instance.new("UIScale")
		made.Name = "TouchScale"
		made.Parent = frame
		sc = made
	end
	local function fit()
		local root = gui:FindFirstChildOfClass("UIScale")
		local s = if root and root.Scale > 0 then root.Scale else 1
		local w, h = gui.AbsoluteSize.X / s, gui.AbsoluteSize.Y / s
		local size = frame.Size
		local k =
			math.min((h - 24 - (reserveTop or 0)) / math.max(1, size.Y.Offset), (w - 24) / math.max(1, size.X.Offset))
		k = math.clamp(k, 1, maxScale or 1.5)
		frame:SetAttribute("FitScale", k);
		(sc :: UIScale).Scale = k
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local root = gui:FindFirstChildOfClass("UIScale")
	if root then
		root:GetPropertyChangedSignal("Scale"):Connect(fit)
	end
end

function Ui.fitScale(gui: ScreenGui): UIScale
	local s = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = gui
	local UserInputService = game:GetService("UserInputService")
	local function update()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(REF_W, REF_H)
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local fit = math.min(vp.X / REF_W, vp.Y / REF_H) * (if touch then 0.91 else 1.02)
		s.Scale = math.clamp(math.min(fit, vp.Y / FIT_H), 0.35, 4)
	end
	update()
	local function watch()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	watch()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	return s
end

-- 그라데이션 회전(무지개 테두리), 이미지 회전(햇살 배경). 프레임당 대입 한 번이라 비용 작음
local spinning: { [UIGradient]: number } = {}
local spinners: { [GuiObject]: number } = {}
function Ui.spinGradient(g: UIGradient, degPerSec: number)
	spinning[g] = degPerSec
	g.Destroying:Connect(function()
		spinning[g] = nil
	end)
end
function Ui.spin(gui: GuiObject, degPerSec: number)
	spinners[gui] = degPerSec
	gui.Destroying:Connect(function()
		spinners[gui] = nil
	end)
end
RunService.RenderStepped:Connect(function(dt)
	for g, speed in spinning do
		g.Rotation = (g.Rotation + speed * dt) % 360
	end
	for gui, speed in spinners do
		gui.Rotation = (gui.Rotation + speed * dt) % 360
	end
end)

-- 화려한 기본 꾸미기 (사용자 지시 2026-10-18: "조금 과하다 싶을 만큼 화려하게, 순위권 게임들이 그렇다").
-- make()가 패널·카드 색 Frame과 버튼에 그라데이션·굵은 외곽선을 자동으로 붙인다 → 모든 화면이 한 번에 바뀐다.
-- 2026-10-29: 모양은 테마 토큰(shape.*)에서 읽는다. 기본값(classic/gradient) = 예전 모양 그대로.

local function gradient(spec: any, parent: Instance): UIGradient?
	if not spec then
		return nil
	end
	local g = Instance.new("UIGradient")
	g.Color = Theme.colorSequence(spec.colors)
	g.Rotation = spec.rotation or 0
	if spec.transparency then
		g.Transparency = spec.transparency
	end
	g.Parent = parent
	return g
end

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local edge = Instance.new("UIStroke")
	edge.Thickness = thickness
	edge.Color = color
	if transparency then
		edge.Transparency = transparency
	end
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = parent
	return edge
end

-- 9-slice image behind a frame/button (shape.images.*: { image, slice = Rect, scale?, tint? }).
-- The frame's own background turns transparent; tint = true (default) follows BackgroundColor3.
local function skin(inst: GuiObject, img: { [string]: any })
	local s = Instance.new("ImageLabel")
	s.Name = "Skin"
	s.BackgroundTransparency = 1
	s.Image = Theme.soundId(img.image) or ""
	s.ScaleType = Enum.ScaleType.Slice
	if img.slice then
		s.SliceCenter = img.slice
	end
	s.SliceScale = img.scale or 1
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = 0 -- under the frame's other children
	local pad = inst:FindFirstChildOfClass("UIPadding")
	if pad then -- ignore the button's inner padding
		s.Size = UDim2.new(
			1 + pad.PaddingLeft.Scale + pad.PaddingRight.Scale,
			pad.PaddingLeft.Offset + pad.PaddingRight.Offset,
			1 + pad.PaddingTop.Scale + pad.PaddingBottom.Scale,
			pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		)
		s.Position =
			UDim2.new(-pad.PaddingLeft.Scale, -pad.PaddingLeft.Offset, -pad.PaddingTop.Scale, -pad.PaddingTop.Offset)
	end
	if img.tint ~= false then
		s.ImageColor3 = inst.BackgroundColor3
		inst:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			s.ImageColor3 = inst.BackgroundColor3
		end)
	end
	s.Parent = inst
	inst.BackgroundTransparency = 1
end

-- Image buttons: a TextButton's children draw over its own text, so the text moves to a child label above the skin
local MIRROR = {
	"Text",
	"TextColor3",
	"FontFace",
	"TextScaled",
	"TextSize",
	"TextWrapped",
	"RichText",
	"TextStrokeColor3",
	"TextStrokeTransparency",
	"TextXAlignment",
	"TextYAlignment",
	"AutoLocalize",
}
local function mirrorText(b: TextButton)
	local m = Instance.new("TextLabel")
	m.Name = "Label"
	m.BackgroundTransparency = 1
	m.Size = UDim2.fromScale(1, 1)
	m.ZIndex = 1
	for _, k in MIRROR do
		(m :: any)[k] = (b :: any)[k]
	end
	b.Changed:Connect(function(prop: string)
		if table.find(MIRROR, prop) then
			(m :: any)[prop] = (b :: any)[prop]
		end
	end)
	b.TextTransparency = 1
	m.Parent = b
end

local function dressFrame(inst: GuiObject, kind: string, style: string)
	local sh = T.shape
	if style == "image" then
		local img = sh.images[kind]
		if img then
			skin(inst, img)
			return
		end
		style = "card" -- no image given: flat card
	end
	if style == "classic" then
		if kind == "panel" then
			gradient(sh.gradients.panel, inst)
			local edge = stroke(inst, sh.stroke.panel, Color3.new(1, 1, 1))
			local g = gradient(sh.gradients.edge, edge)
			if g and sh.gradients.edge.spin then
				Ui.spinGradient(g, sh.gradients.edge.spin)
			end
		else
			gradient(sh.gradients.card, inst)
			stroke(inst, sh.stroke.card, Ui.THEME.outline)
		end
	elseif style == "card" then
		stroke(inst, sh.stroke.card, Ui.THEME.outline)
	elseif style == "glass" then
		if inst.BackgroundTransparency == 0 then
			inst.BackgroundTransparency = 0.3
		end
		gradient({ colors = Color3.new(1, 1, 1), rotation = 90, transparency = NumberSequence.new(0, 0.35) }, inst)
		stroke(inst, math.max(1, sh.stroke.card * 0.75), Color3.new(1, 1, 1), 0.55)
	elseif style == "neon" then
		local edge = stroke(inst, math.max(2, sh.stroke[kind] or 2), Ui.THEME.accent)
		TweenService:Create(
			edge,
			TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.45 }
		):Play()
	end
end

local function dressButton(b: TextButton, style: string)
	local sh = T.shape
	if style == "image" then
		local img = sh.images.button
		if img then
			skin(b, img)
			mirrorText(b)
			return
		end
		style = "gradient"
	end
	if style == "gradient" or style == "pill" then
		gradient(sh.gradients.button, b)
		stroke(b, sh.stroke.button, Ui.THEME.outline)
	elseif style == "solid" then
		stroke(b, sh.stroke.button, Ui.THEME.outline)
	elseif style == "outlined" then
		b.BackgroundTransparency = 0.82
		local edge = stroke(b, sh.stroke.button, b.BackgroundColor3)
		b:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			edge.Color = b.BackgroundColor3
		end)
	end
end

-- Hard drop shadow (shape.shadow): a sibling frame that follows the panel. Skipped inside list/grid layouts.
local function addShadow(inst: GuiObject)
	local spec = T.shape.shadow
	local parent = inst.Parent
	if not spec or not parent or parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return
	end
	local s = if type(spec) == "table" then spec else {}
	local off = s.offset or 5
	local sh = Instance.new("Frame")
	sh.Name = inst.Name .. "Shadow"
	sh.BorderSizePixel = 0
	sh.BackgroundColor3 = s.color or Color3.new(0, 0, 0)
	sh.BackgroundTransparency = s.transparency or 0.55
	local c = inst:FindFirstChildOfClass("UICorner")
	if c then
		c:Clone().Parent = sh
	end
	local scale = Instance.new("UIScale")
	scale.Parent = sh
	local function sync()
		sh.Size = inst.Size
		sh.AnchorPoint = inst.AnchorPoint
		sh.Position = inst.Position + UDim2.fromOffset(0, off)
		sh.Visible = inst.Visible
		sh.Rotation = inst.Rotation
		sh.ZIndex = inst.ZIndex - 1
		local is = inst:FindFirstChildOfClass("UIScale")
		scale.Scale = if is then is.Scale else 1
	end
	sync()
	inst.Changed:Connect(sync)
	inst.ChildAdded:Connect(function(ch)
		if ch:IsA("UIScale") then
			ch:GetPropertyChangedSignal("Scale"):Connect(sync)
		end
	end)
	local is = inst:FindFirstChildOfClass("UIScale")
	if is then
		is:GetPropertyChangedSignal("Scale"):Connect(sync)
	end
	inst.AncestryChanged:Connect(function()
		sh.Parent = inst.Parent
	end)
	inst.Destroying:Connect(function()
		sh:Destroy()
	end)
	sh.Parent = parent
end

-- 반환·자식 타입은 any: Luau 테이블 타입은 불변이라 { UICorner }를 { Instance }에 못 넘긴다
-- NoDress = true면 자동 꾸미기를 건너뛴다. Loc = Loc.msg(키, 매개변수)면 번역 키로 글자를 그린다 (client/Loc)
-- Frame 꾸미기: 색이 THEME.panel이면 shape.panelStyle, THEME.card면 shape.cardStyle. PanelStyle = "glass" 등으로 직접 고를 수도 있다
function Ui.make(className: string, props: { [string]: any }, children: { any }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if not META[k] then
			(inst :: any)[k] = v
		end
	end
	if props.Loc then
		Loc.apply(inst :: GuiObject, props.Loc)
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	local dressed = false
	if className == "Frame" and props.BackgroundTransparency ~= 1 and props.NoDress ~= true then
		local kind = if props.BackgroundColor3 == Ui.THEME.panel
			then "panel"
			elseif props.BackgroundColor3 == Ui.THEME.card then "card"
			else nil
		local style = props.PanelStyle
			or (if kind == "panel" then T.shape.panelStyle elseif kind == "card" then T.shape.cardStyle else nil)
		if style then
			dressFrame(inst :: any, kind or "panel", style)
			dressed = true
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
		if dressed and T.shape.shadow then
			addShadow(inst :: any)
		end
	end
	return inst
end

-- 모서리: shape.corner(기본 반지름) × shape.cornerScale
function Ui.corner(radius: number?): UICorner
	return Ui.make(
			"UICorner",
			{ CornerRadius = UDim.new(0, (radius or T.shape.corner) * T.shape.cornerScale) }
		) :: UICorner
end

-- Font role -> instance props (Enum.Font token sets .Font exactly like before themes; others set .FontFace)
local function fontProps(props: { [string]: any }, role: string)
	local e, f = Theme.font(T.fonts[role] or T.fonts.body)
	if e then
		props.Font = e
	else
		props.FontFace = f
	end
end

-- Ui.font(label, "number"): give an existing text object the theme font of a role
function Ui.font(inst: Instance, role: string)
	local e, f = Theme.font(T.fonts[role] or T.fonts.body)
	if e then
		(inst :: any).Font = e
	else
		(inst :: any).FontFace = f
	end
end

local function strokeProps(props: { [string]: any }, transparency: number?)
	if transparency then
		props.TextStrokeColor3 = T.text.strokeColor or Ui.THEME.outline
		props.TextStrokeTransparency = transparency
	end
end

-- text.case[role] ("upper"/"lower"): applied now and whenever Text changes (Loc). Rich text is left alone.
local function applyCase(t: any, role: string)
	local case = T.text.case[role]
	if not case or t.RichText then
		return
	end
	local function fix()
		local want = Theme.applyCase(t.Text, case)
		if t.Text ~= want then
			t.Text = want
		end
	end
	fix()
	t:GetPropertyChangedSignal("Text"):Connect(fix)
end

-- Role = "title" (기본) | "body" | "caption" | "number" | "button": 테마 글꼴·외곽선·대소문자. Font/FontFace를 주면 그대로 쓴다
function Ui.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	local explicit = props.Font ~= nil or props.FontFace ~= nil
	local role = props.Role or "title"
	if not explicit then
		fontProps(props, role)
	end
	props.TextColor3 = props.TextColor3 or Ui.THEME.ink
	props.TextScaled = true
	-- 굵은 글자는 만화풍 외곽선 (기본: title·number 역할 = FredokaOne). 글꼴을 직접 준 라벨은 예전 규칙 (FredokaOne만)
	if props.TextStrokeTransparency == nil then
		if explicit and props.Role == nil then
			strokeProps(props, if props.Font == Enum.Font.FredokaOne then T.text.stroke.title else nil)
		else
			strokeProps(props, T.text.stroke[role])
		end
	end
	local l = Ui.make("TextLabel", props) :: TextLabel
	applyCase(l, role)
	return l
end

-- 패널 제목 (shape.titleStyle): plain = 강조색 글자 (예전 모양) | ribbon = 강조색 띠 안의 글자 | tab = 패널 위 가장자리에 걸친 탭.
-- props는 Ui.label과 같다 (Size/Position/AnchorPoint/Parent는 띠에 적용). 글자 라벨을 돌려준다 (Loc.set 가능)
-- Icon = "Shop"이면 제목 왼쪽 끝에 아이콘을 달고 글자를 아이콘 폭 + 간격만큼 민다 (IconSize 기본 = 제목 높이 × 1.4)
function Ui.title(props: { [string]: any }): TextLabel
	local style = props.Style or T.shape.titleStyle
	props.Role = props.Role or "title"
	local size = props.Size or UDim2.new(1, 0, 0, 40)
	local iconName = props.Icon
	local iconSize = props.IconSize or math.floor((if size.Y.Offset > 0 then size.Y.Offset else 40) * 1.4 + 0.5)
	if style == "plain" then
		props.TextColor3 = props.TextColor3 or Ui.THEME.accent
		local l = Ui.label(props)
		if iconName then
			Ui.leadIcon(l, iconName, iconSize, { poke = math.floor(iconSize * 0.1 + 0.5), rotation = -10, gap = 6 })
		end
		return l
	end
	local barSize, barPos, barAnchor = size, props.Position, props.AnchorPoint
	if style == "tab" then
		barSize = UDim2.new(size.X.Scale * 0.7, size.X.Offset * 0.7, size.Y.Scale, size.Y.Offset)
		barPos = UDim2.fromScale(0.5, 0)
		barAnchor = Vector2.new(0.5, 0.5)
	end
	local bar = Ui.make("Frame", {
		Name = "TitleBar",
		Size = barSize,
		Position = barPos,
		AnchorPoint = barAnchor,
		BackgroundColor3 = Ui.THEME.accent,
		ZIndex = props.ZIndex,
		NoDress = true,
		Parent = props.Parent,
	}, {
		Ui.corner(if style == "tab" then 999 else nil),
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(0.04, 0),
			PaddingRight = UDim.new(0.04, 0),
			PaddingTop = UDim.new(0.12, 0),
			PaddingBottom = UDim.new(0.12, 0),
		}),
	})
	gradient(T.shape.gradients.button, bar)
	stroke(bar, T.shape.stroke.button, Ui.THEME.outline)
	props.Size = UDim2.fromScale(1, 1)
	props.Position = nil
	props.AnchorPoint = nil
	props.Parent = bar
	props.TextColor3 = Ui.THEME.accentInk
	props.TextStrokeTransparency = props.TextStrokeTransparency or 1
	local l = Ui.label(props)
	if iconName then
		-- 띠(bar)의 UIPadding 왼쪽을 아이콘 폭 + 간격으로 바꾼다 (글자 라벨은 띠 안쪽 전체)
		Ui.leadIcon(bar, iconName, iconSize, { poke = math.floor(iconSize * 0.15 + 0.5), rotation = -10, gap = 6 })
	end
	return l
end

function Ui.hasIcon(name: string): boolean
	return icons ~= nil and icons[name] ~= nil
end

-- 아이콘 (게임이 configure로 넘긴 표, 예: Merge AssetIds.Icons). 아직 없는 이름이면 nil
function Ui.icon(name: string, props: { [string]: any }): ImageLabel?
	local id = icons and icons[name]
	if not id then
		return nil
	end
	props.Image = id
	props.BackgroundTransparency = 1
	props.ScaleType = props.ScaleType or Enum.ScaleType.Fit
	return Ui.make("ImageLabel", props) :: ImageLabel
end

-- 글자 앞 아이콘 (제목·섹션 머리·버튼 공통): 아이콘을 t의 왼쪽 끝에 (poke px만큼 밖으로 튀어나오게) 두고,
-- 글자 왼쪽 여백(UIPadding.PaddingLeft) = 아이콘이 차지하는 폭(회전 포함) + gap. 그래서 아이콘이 첫 글자를 덮지 않는다.
-- t에 UIPadding이 없으면 만든다 (글자 객체일 때만; 다른 Frame은 자식 배치가 바뀌므로 여백 없이 아이콘만 놓는다).
export type LeadIconOpts = { poke: number?, rotation: number?, gap: number? }
function Ui.leadIcon(t: GuiObject, name: string, size: number, opts: LeadIconOpts?): ImageLabel?
	if not Ui.hasIcon(name) then
		return nil
	end
	local poke = (opts and opts.poke) or 0
	local gap = (opts and opts.gap) or 6
	-- 기울인(rotation) 아이콘의 귀퉁이는 그림 여백(투명)이라 회전으로 늘어난 폭은 gap이 흡수한다
	local reach = size - poke
	local inset = math.ceil(reach + gap)
	local pad = t:FindFirstChildOfClass("UIPadding")
	if not pad and (t:IsA("TextLabel") or t:IsA("TextButton") or t:IsA("TextBox")) then
		pad = Ui.make("UIPadding", { Parent = t })
	end
	if pad then
		pad.PaddingLeft = UDim.new(0, inset)
	else
		inset = 0
	end
	-- 자식은 UIPadding 안쪽 기준으로 놓이므로, 여백만큼 왼쪽으로 빼서 t의 왼쪽 끝(-poke)에 붙인다
	return Ui.icon(name, {
		Name = "LeadIcon",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0, -inset - poke, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Rotation = (opts and opts.rotation) or 0,
		ZIndex = t.ZIndex + 2,
		Parent = t,
	})
end

-- 버튼 왼쪽에 큰 아이콘을 튀어나오게 달고 글자를 아이콘 오른쪽으로 민다 (시뮬레이터 게임 버튼 모양).
-- 크기 = 버튼 높이 × scale. 높이를 아직 모르면 (Scale 크기, 그리드 칸) 크기가 정해질 때 다시 맞춘다
function Ui.addIcon(b: GuiObject, name: string, scale: number?): ImageLabel?
	if not Ui.hasIcon(name) then
		return nil
	end
	local k = scale or 1.25
	-- 높이 (UIScale 배수 제외): 고정 Offset 크기 > 부모 그리드 칸 > 실제 화면 크기 ÷ 조상 UIScale
	local function fixedHeight(): number?
		if
			b.Size.Y.Scale == 0
			and b.Size.Y.Offset > 0
			and not (b.Parent and b.Parent:FindFirstChildOfClass("UIGridLayout"))
		then
			return b.Size.Y.Offset
		end
		local grid = b.Parent and b.Parent:FindFirstChildOfClass("UIGridLayout")
		if grid and grid.CellSize.Y.Scale == 0 and grid.CellSize.Y.Offset > 0 then
			return grid.CellSize.Y.Offset
		end
		return nil
	end
	local function measured(): number
		local m = 1
		local p: Instance? = b
		while p do
			local sc = p:FindFirstChildOfClass("UIScale")
			if sc and sc.Scale > 0 then
				m *= sc.Scale
			end
			p = p.Parent
		end
		return b.AbsoluteSize.Y / m
	end
	local function layout(h: number): ImageLabel?
		local size = math.floor(h * k + 0.5)
		return Ui.leadIcon(b, name, size, {
			poke = math.floor(size * 0.2 + 0.5),
			rotation = -8,
			gap = math.max(3, math.floor(h * 0.08 + 0.5)),
		})
	end
	local fixed = fixedHeight()
	local h = fixed or measured()
	local img = layout(if h > 0 then h else 40)
	if not fixed then
		-- Scale 크기 버튼: 실제 높이가 정해지거나 바뀌면 다시 맞춘다 (누름 UIScale은 measured에서 빠짐)
		local last = h
		b:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local nh = measured()
			if nh > 0 and math.abs(nh - last) >= 2 and img and img.Parent == b then
				last = nh
				img:Destroy()
				img = layout(nh)
			end
		end)
	end
	return img
end

-- 광택이 주기적으로 훑고 지나감 (구매 버튼·추천 상품).
-- 튀어나온 아이콘이 잘리지 않게 부모 대신 안쪽 틀(CanvasGroup: 둥근 모서리까지 잘림)에서만 자른다
function Ui.shine(gui: GuiObject, every: number?)
	local id = icons and icons.Shine
	local corner = gui:FindFirstChildOfClass("UICorner")
	local clip = Ui.make("CanvasGroup", {
		Name = "ShineClip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = gui.ZIndex + 1,
		Parent = gui,
	}, { Ui.make("UICorner", { CornerRadius = if corner then corner.CornerRadius else UDim.new(0, 10) }) })
	-- 버튼 안쪽 여백(UIPadding)을 무시하도록 여백만큼 밖으로 넓힌다
	local pad = gui:FindFirstChildOfClass("UIPadding")
	if pad then
		clip.Size = UDim2.new(
			1 + pad.PaddingLeft.Scale + pad.PaddingRight.Scale,
			pad.PaddingLeft.Offset + pad.PaddingRight.Offset,
			1 + pad.PaddingTop.Scale + pad.PaddingBottom.Scale,
			pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		)
		clip.Position =
			UDim2.new(-pad.PaddingLeft.Scale, -pad.PaddingLeft.Offset, -pad.PaddingTop.Scale, -pad.PaddingTop.Offset)
	end
	local streak = Ui.make(if id then "ImageLabel" else "Frame", {
		Size = UDim2.fromScale(0.35, 1.8),
		Position = UDim2.fromScale(-0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 20,
		BackgroundTransparency = if id then 1 else 0.7,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = gui.ZIndex + 3,
		NoDress = true,
		Parent = clip,
	}) :: GuiObject
	if id then
		local img = streak :: ImageLabel
		img.Image = id
		img.ImageTransparency = 0.15
	end
	task.spawn(function()
		while streak.Parent do
			streak.Position = UDim2.fromScale(-0.5, 0.5)
			TweenService:Create(streak, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
				Position = UDim2.fromScale(1.5, 0.5),
			}):Play()
			task.wait((every or 2.5) + math.random() * 0.8)
		end
	end)
end

-- 좌우로 살랑 흔들림 (SHOP 버튼·추천 상품 아이콘). 누름 효과 UIScale과 겹치지 않게 회전만 쓴다
function Ui.wiggle(gui: GuiObject, degrees: number?)
	local d = degrees or 4
	TweenService
		:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = d })
		:Play()
	gui.Rotation = -d
end

-- UI 소리 (테마 sounds.*: click / open / close / purchase / notify). 없는 이름은 조용히 건너뛴다
function Ui.sound(name: string)
	local s = sfx[name]
	if s then
		s:Play()
	end
end

function Ui.click()
	Ui.sound("click")
end

local function setSound(name: string, id: any, volume: number)
	local sid = Theme.soundId(id)
	if not sid then
		return
	end
	if sfx[name] then
		sfx[name]:Destroy()
	end
	sfx[name] = Ui.make("Sound", {
		SoundId = sid,
		Volume = volume,
		Parent = SoundService,
	}) :: Sound
end

-- Game setup, once at boot (before any UI is built)
function Ui.configure(opts: Options)
	if opts.icons then
		icons = opts.icons
		-- 접속하자마자 아이콘을 미리 받아 둔다: 상점을 처음 열 때 빈 칸으로 보이던 문제 (Studio 확인 2026-10-18)
		local list = {}
		for _, id in opts.icons do
			table.insert(list, id)
		end
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(list)
			end)
		end)
	end
	if opts.clickSound then
		setSound("click", opts.clickSound, opts.clickVolume or 0.4)
	end
end

-- 게임 테마 (docs/33 §Theme). 부팅 때 UI를 만들기 전에 한 번. 부분 토큰만 주면 나머지는 기본값(= Merge 모양).
-- Ui.theme(nil) 또는 부르지 않음 = 기본 테마. 알 수 없는 그룹·스타일 이름은 오류.
function Ui.theme(tokens: Theme.Tokens?)
	T = Theme.merge(tokens)
	Theme.fillLegacy(Ui.THEME, T.palette)
	local list = {}
	for _, name in { "click", "open", "close", "purchase", "notify" } do
		if T.sounds[name] ~= nil then -- nil keeps a click sound from Ui.configure
			setSound(name, T.sounds[name], T.sounds.volume[name] or 0.5)
			if sfx[name] then
				table.insert(list, sfx[name])
			end
		end
	end
	if #list > 0 then
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(list)
			end)
		end)
	end
end

-- Active tokens (read-only use: Ui.tokens().motion.open.duration, Ui.tokens().palette.rarity)
function Ui.tokens(): Theme.Tokens
	return T
end

-- Style = "gradient" (기본) | "solid" | "outlined" | "pill" | "image" (shape.buttonStyle을 이 버튼만 바꿈). Role 기본 "button"
function Ui.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local style = props.Style or T.shape.buttonStyle
	local role = props.Role or "button"
	if props.Font == nil and props.FontFace == nil then
		fontProps(props, role)
	end
	props.TextColor3 = props.TextColor3 or Ui.THEME.ink
	props.BackgroundColor3 = props.BackgroundColor3 or Ui.THEME.button
	props.TextScaled = true
	props.AutoButtonColor = true
	if props.TextStrokeTransparency == nil then
		strokeProps(props, T.text.stroke[role])
	end
	local pad = T.shape.padding
	local b = Ui.make("TextButton", props, {
		if style == "pill" then Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) else Ui.corner(),
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(pad.x, 0),
			PaddingRight = UDim.new(pad.x, 0),
			PaddingTop = UDim.new(pad.y, 0),
			PaddingBottom = UDim.new(pad.y, 0),
		}),
	}) :: TextButton
	if props.BackgroundTransparency ~= 1 then
		dressButton(b, style)
	end
	applyCase(b, role)
	-- 누르면 쏙 들어갔다 튀어나옴 (motion.press / motion.hover)
	local m = T.motion
	local press = Ui.make("UIScale", { Parent = b }) :: UIScale
	b.MouseButton1Down:Connect(function()
		TweenService:Create(press, TweenInfo.new(m.press.down), { Scale = m.press.scale }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(press, TweenInfo.new(m.press.up, m.press.style), { Scale = 1 }):Play()
	end)
	if m.hover.scale ~= 1 then
		b.MouseEnter:Connect(function()
			TweenService:Create(press, TweenInfo.new(m.hover.time), { Scale = m.hover.scale }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(press, TweenInfo.new(m.hover.time), { Scale = 1 }):Play()
		end)
	else
		b.MouseLeave:Connect(function()
			press.Scale = 1
		end)
	end
	if onClick then
		b.Activated:Connect(function()
			Ui.click()
			onClick()
		end)
	end
	return b
end

-- 패널 열기·닫기 연출 (motion.open / motion.close, sounds.open / sounds.close). 기본값 = 즉시 (예전과 같음).
-- Ui.bindPanel(frame): Visible이 true가 될 때마다 (누가 열든) 열기 소리 + 커지며 등장. 만든 직후 한 번 부른다.
-- Ui.closePanel(frame): 닫기 소리 + 작아지며 사라진 뒤 Visible = false. 닫기 버튼에서 panel.Visible = false 대신 쓴다.
-- 휴대폰 Ui.touchFit 배수(FitScale 속성)를 기준 크기로 쓴다.
local closing: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function scaleOf(frame: GuiObject): (UIScale, number)
	local sc = frame:FindFirstChildOfClass("UIScale")
	if not sc then
		local made = Instance.new("UIScale")
		made.Name = "ThemeScale"
		made.Parent = frame
		sc = made
	end
	return sc :: UIScale, (frame:GetAttribute("FitScale") :: number?) or 1
end

function Ui.bindPanel(frame: GuiObject)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			return
		end
		closing[frame] = (closing[frame] or 0) + 1 -- cancels a running close
		Ui.sound("open")
		local o = T.motion.open
		if o.duration > 0 then
			local sc, base = scaleOf(frame)
			sc.Scale = o.from * base
			TweenService:Create(sc, TweenInfo.new(o.duration, o.style, Enum.EasingDirection.Out), { Scale = base })
				:Play()
		end
	end)
end

function Ui.closePanel(frame: GuiObject)
	if not frame.Visible then
		return
	end
	Ui.sound("close")
	local c = T.motion.close
	if c.duration <= 0 then
		frame.Visible = false
		return
	end
	local id = (closing[frame] or 0) + 1
	closing[frame] = id
	local sc, base = scaleOf(frame)
	local tw =
		TweenService:Create(sc, TweenInfo.new(c.duration, c.style, Enum.EasingDirection.In), { Scale = c.to * base })
	tw.Completed:Once(function()
		if closing[frame] == id then
			frame.Visible = false
			sc.Scale = base
		end
	end)
	tw:Play()
end

-- 팝업 등장 (motion.pop): 작게 → 기준 크기로 튀어나옴 (RatePrompt). frame에 UIScale이 없으면 만든다
function Ui.pop(frame: GuiObject)
	local p = T.motion.pop
	local sc, base = scaleOf(frame)
	sc.Scale = p.from * base
	TweenService:Create(sc, TweenInfo.new(p.duration, p.style, Enum.EasingDirection.Out), { Scale = base }):Play()
end

-- 길게 누르면 연속 구매: 누르는 즉시 1회, 0.35초 뒤부터 점점 빨리 (docs/14 §3.3-4).
-- step()이 false를 돌려주면(돈 부족·MAX) 멈춘다. 게임패드는 Activated 1회.
-- 누르고 있으면 연속 구매 (2026-10-20 리뷰로 바꿈): 한 번 구매는 손을 뗄 때(Activated). 예전엔 누르는 순간(InputBegan) 사서
-- 휴대폰에서 목록을 스크롤하려고 손가락만 대도 사졌고, REBIRTH도 바로 됐다.
-- 0.35초 넘게 제자리(10px 안)로 누르고 있으면 그때부터 연속. 손가락이 움직이거나 목록이 스크롤되면 멈춘다
local HOLD_START = 0.35
local HOLD_SLOP = 10
function Ui.holdRepeat(b: GuiButton, step: () -> boolean)
	local holding = 0 -- 누를 때마다 새 번호: 이전 루프는 번호가 달라 스스로 끝난다
	local repeated = false -- 이번 누름에서 연속 구매가 돌았으면 손 뗄 때 한 번 더 사지 않는다
	local function stop()
		holding += 1
	end
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		holding += 1
		repeated = false
		local id = holding
		local start = input.Position
		task.delay(HOLD_START, function()
			local gap = 0.18
			while holding == id do
				if (input.Position - start).Magnitude > HOLD_SLOP then
					return
				end
				repeated = true
				if not step() then
					return
				end
				task.wait(gap)
				gap = math.max(0.05, gap * 0.85)
			end
		end)
	end)
	b.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			stop()
		end
	end)
	b.MouseLeave:Connect(stop)
	-- 목록이 스크롤되면 연속 구매를 멈춘다 (스크롤이 손가락을 가져가면 InputEnded가 안 올 수 있음)
	task.defer(function()
		local scroller = b:FindFirstAncestorWhichIsA("ScrollingFrame")
		if scroller then
			scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(stop)
		end
	end)
	b.Activated:Connect(function()
		if repeated then
			repeated = false
			return
		end
		step()
	end)
end

------------------------------------------------------------------------
-- 읽기 쉬운 수치 (docs/33 §11-1): 숫자마다 아이콘 + 짧은 이름 + 단위. 테마 ux.stat 색·모양
------------------------------------------------------------------------

export type StatSpec = {
	icon: string?, -- Ui.configure 아이콘 이름, 없으면 글자 그대로 (이모지 "⏱" 등)
	label: Loc.Text?, -- 짧은 이름 ("grow", "per harvest")
	value: any, -- 숫자는 Format.short
	unit: string?, -- "s", "/harvest", "x" ... 값 뒤에 작고 흐리게
	prefix: string?, -- 값 앞 ("x" -> "x2.0")
	color: Color3?, -- 값 색 (기본 ux.stat.value = palette.text)
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Name: string?,
}

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5)
end

local function statText(frame: Instance, value: any, unit: string?, prefix: string?): string
	local v = if type(value) == "number" then Format.short(value) else tostring(value)
	local s = (prefix or "") .. v
	if unit and unit ~= "" then
		local dim = T.ux.stat.label or Ui.THEME.dim
		s ..= string.format('<font color="%s">%s</font>', hex(dim), unit)
	end
	frame:SetAttribute("StatUnit", unit)
	frame:SetAttribute("StatPrefix", prefix)
	return s
end

-- 아이콘 칸: 게임 아이콘이 있으면 이미지, 아니면 글자(이모지)
local function statIcon(parent: Instance, icon: string?, props: { [string]: any }): GuiObject?
	if not icon or icon == "" then
		return nil
	end
	props.Name = "Icon"
	props.Parent = parent
	local img = Ui.icon(icon, props)
	if img then
		return img
	end
	props.Text = icon
	props.Role = "body"
	props.TextStrokeTransparency = 1
	return Ui.label(props)
end

-- 한 줄 수치: [아이콘] 이름(작게·흐림) ........ 값(크게) 단위(작게·흐림).
-- Ui.statRow(list, { icon = "Clock", label = "grow", value = 45, unit = "s" }) -> Frame (기본 가로 100% × 28px)
-- 값 바꾸기: Ui.setStat(row, 50) (단위·접두는 그대로, 바꾸려면 setStat(row, v, unit, prefix))
function Ui.statRow(parent: Instance?, spec: StatSpec): Frame
	local row = Ui.make("Frame", {
		Name = spec.Name or "Stat",
		BackgroundTransparency = 1,
		Size = spec.Size or UDim2.new(1, 0, 0, 28),
		Position = spec.Position or UDim2.new(),
		AnchorPoint = spec.AnchorPoint or Vector2.zero,
		LayoutOrder = spec.LayoutOrder or 0,
	}) :: Frame
	local hasIcon = statIcon(row, spec.icon, {
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}) ~= nil
	local labelX = if hasIcon then 1.25 else 0 -- 아이콘 폭(=높이) 뒤 여백, 높이 배수
	local lab = Ui.label({
		Name = "Label",
		Role = "caption",
		Text = "",
		TextColor3 = T.ux.stat.label or Ui.THEME.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		Size = UDim2.fromScale(0.5, 0.72),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = row,
	})
	if spec.label then
		Loc.apply(lab, spec.label)
	end
	-- 아이콘 폭만큼 글자를 민다 (높이 = 아이콘 폭)
	local function place()
		local h = row.AbsoluteSize.Y
		lab.Position = UDim2.new(0, h * labelX, 0.5, 0)
		lab.Size = UDim2.new(0.58, -h * labelX, 0.72, 0)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	Ui.label({
		Name = "Value",
		Role = "number",
		RichText = true,
		Text = statText(row, spec.value, spec.unit, spec.prefix),
		TextColor3 = spec.color or T.ux.stat.value or Ui.THEME.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.42, 1),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = row,
	})
	if parent then
		row.Parent = parent
	end
	return row
end

-- 알약 수치 칩: [아이콘] 값 단위 (이름 없이 짧게, 카드 위 묶음용). 기본 크기 96×28.
-- Ui.statChip(card, { icon = "⏱", value = 45, unit = "s" }); 갱신은 Ui.setStat(chip, v)
function Ui.statChip(parent: Instance?, spec: StatSpec): Frame
	local chip = Ui.make("Frame", {
		Name = spec.Name or "Chip",
		BackgroundColor3 = T.ux.stat.chip or Ui.THEME.card,
		BackgroundTransparency = 0.15,
		Size = spec.Size or UDim2.fromOffset(96, 28),
		Position = spec.Position or UDim2.new(),
		AnchorPoint = spec.AnchorPoint or Vector2.zero,
		LayoutOrder = spec.LayoutOrder or 0,
		NoDress = true,
	}, {
		if T.ux.stat.chipStyle == "pill"
			then Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) })
			else Ui.corner(6),
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0.12, 0),
			PaddingBottom = UDim.new(0.12, 0),
		}),
	}) :: Frame
	stroke(chip, 1.5, Ui.THEME.outline, 0.4)
	local hasIcon = statIcon(chip, spec.icon, {
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}) ~= nil
	local val = Ui.label({
		Name = "Value",
		Role = "number",
		RichText = true,
		Text = statText(chip, spec.value, spec.unit, spec.prefix),
		TextColor3 = spec.color or T.ux.stat.value or Ui.THEME.ink,
		TextXAlignment = if hasIcon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = chip,
	})
	if hasIcon then
		local function place()
			local h = chip.AbsoluteSize.Y * 0.76
			val.Position = UDim2.fromOffset(h + 4, 0)
			val.Size = UDim2.new(1, -(h + 4), 1, 0)
		end
		chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		place()
	end
	if parent then
		chip.Parent = parent
	end
	return chip
end

-- statRow / statChip 값 갱신. unit·prefix를 안 주면 처음 값 유지
function Ui.setStat(stat: Instance, value: any, unit: string?, prefix: string?)
	local val = stat:FindFirstChild("Value") :: TextLabel?
	if not val then
		return
	end
	local u = if unit ~= nil then unit else stat:GetAttribute("StatUnit") :: string?
	local p = if prefix ~= nil then prefix else stat:GetAttribute("StatPrefix") :: string?
	val.Text = statText(stat, value, u, p)
end

return Ui
