--!strict
-- Player profile card, client side (docs/33 §11-4). Opt-in core client module; server = CoreServer/Profile.
--   Profile.init({ canOpen = function() return not building end })   -- tap/click another player's character
--   Profile.open(somePlayer)                                          -- open directly (leaderboard row, etc.)
--   Profile.button(hudFrame, { Size = ..., Position = ... })         -- "ME" button for your own card
-- Detection: a short tap/click (under 0.35 s, moved under 10 px) that the game did not process; one raycast from
-- the camera. It never sinks input, so game clicks still happen; canOpen lets the game opt out (combat, build mode).
-- Card: avatar headshot, display name, title line, stat rows (Ui.statRow), showcase chips (rarity colors).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Loc = require(script.Parent.Loc)

local player = Players.LocalPlayer
local Profile = {}

export type Options = {
	parent: ScreenGui?,
	canOpen: (() -> boolean)?,
	statsTitle: string?, -- section labels
	showcaseTitle: string?,
}

local options: Options = {}
local remote: RemoteFunction? = nil
local card: Frame? = nil
local openId = 0

local function build(): Frame
	if card then
		return card
	end
	local g = options.parent
	if not g then
		local sg = Instance.new("ScreenGui")
		sg.Name = "CoreProfile"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 22
		sg.Parent = player:WaitForChild("PlayerGui")
		Ui.fitScale(sg)
		g = sg
	end
	local c = Ui.make("Frame", {
		Name = "ProfileCard",
		BackgroundColor3 = Ui.THEME.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 400),
		Visible = false,
		Parent = g,
	}, { Ui.corner() }) :: Frame
	Ui.bindPanel(c)
	local avatar = Ui.make("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = Ui.THEME.card,
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(14, 14),
		Image = "",
		Parent = c,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local st = Instance.new("UIStroke")
	st.Color = Ui.THEME.accent
	st.Thickness = 3
	st.Parent = avatar
	Ui.label({
		Name = "Display",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 32),
		Position = UDim2.fromOffset(98, 16),
		Parent = c,
	})
	Ui.label({
		Name = "User",
		Role = "caption",
		Text = "",
		TextColor3 = Ui.THEME.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		Size = UDim2.new(1, -150, 0, 16),
		Position = UDim2.fromOffset(98, 50),
		Parent = c,
	})
	Ui.label({
		Name = "Title",
		Role = "caption",
		Text = "",
		TextColor3 = Ui.THEME.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		Size = UDim2.new(1, -150, 0, 16),
		Position = UDim2.fromOffset(98, 68),
		Parent = c,
	})
	Ui.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
	}, function()
		Ui.closePanel(c)
	end).Parent =
		c
	Ui.make("Frame", {
		Name = "Stats",
		BackgroundColor3 = Ui.THEME.card,
		Size = UDim2.new(1, -28, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(14, 100),
		Parent = c,
	}, {
		Ui.corner(8),
		Ui.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}),
	})
	Ui.label({
		Name = "ShowHead",
		Role = "caption",
		Text = options.showcaseTitle or "SHOWCASE",
		TextColor3 = Ui.THEME.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 300),
		Parent = c,
	})
	Ui.make("Frame", {
		Name = "Show",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 60),
		Position = UDim2.fromOffset(14, 320),
		Parent = c,
	}, {
		Ui.make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 26),
			CellPadding = UDim2.fromOffset(8, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	card = c
	return c
end

local function fill(data: { [string]: any })
	local c = build()
	local stats = c:FindFirstChild("Stats") :: Frame
	local show = c:FindFirstChild("Show") :: Frame
	for _, ch in stats:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	for _, ch in show:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	(c:FindFirstChild("Display") :: TextLabel).Text = data.displayName or data.name or "?"
	(c:FindFirstChild("User") :: TextLabel).Text = "@" .. tostring(data.name or "")
	local title = c:FindFirstChild("Title") :: TextLabel
	if data.title then
		Loc.apply(title, data.title)
	else
		title.Text = ""
	end
	for i, s in data.stats or {} do
		Ui.statRow(stats, {
			icon = s.icon,
			label = s.label,
			value = s.value,
			unit = s.unit,
			prefix = s.prefix,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = i,
		})
	end
	local list = data.showcase or {}
	for i, e in list do
		local chip = Ui.statChip(show, {
			icon = if e.icon and Ui.hasIcon(e.icon) then e.icon else "★",
			value = e.name or e.id or "?",
			color = e.color,
			LayoutOrder = i,
		})
		local s = chip:FindFirstChildOfClass("UIStroke")
		if s and e.color then
			s.Color = e.color
			s.Transparency = 0
		end
	end
	local nRows = #(data.stats or {})
	local statsH = nRows * 30 + 16
	local head = c:FindFirstChild("ShowHead") :: TextLabel
	head.Visible = #list > 0
	head.Position = UDim2.fromOffset(14, 100 + statsH + 10)
	show.Position = UDim2.fromOffset(14, 100 + statsH + 30)
	local showRows = math.ceil(#list / 2)
	c.Size = UDim2.fromOffset(340, 100 + statsH + (if #list > 0 then 36 + showRows * 32 else 0) + 14)
	-- headshot (yields)
	local avatar = c:FindFirstChild("Avatar") :: ImageLabel
	avatar.Image = ""
	local my = openId
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(
				data.userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and my == openId then
			avatar.Image = img
		end
	end)
end

function Profile.open(target: Player)
	local r = remote
	if not r then
		return
	end
	openId += 1
	local my = openId
	task.spawn(function()
		local ok, data = pcall(r.InvokeServer, r, target.UserId)
		if not ok or type(data) ~= "table" or my ~= openId then
			return
		end
		fill(data)
		build().Visible = true
	end)
end

function Profile.close()
	if card then
		Ui.closePanel(card)
	end
end

-- "ME" button: opens your own card
function Profile.button(parent: Instance, props: { [string]: any }?): TextButton
	local p: { [string]: any } = props or {}
	p.Name = p.Name or "ProfileButton"
	p.Text = p.Text or "ME"
	p.Size = p.Size or UDim2.fromOffset(64, 40)
	p.Parent = parent
	return Ui.button(p, function()
		Profile.open(player)
	end)
end

-- Which other player is at this screen point (nil = none)
function Profile.playerAt(screen: Vector2): Player?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local ray = cam:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	if not hit then
		return nil
	end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then
			return if p ~= player then p else nil
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

function Profile.init(o: Options?)
	options = o or {}
	task.spawn(function()
		remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CoreProfile") :: RemoteFunction
	end)
	local downAt, downPos = 0, Vector2.zero
	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if processed or (t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch) then
			return
		end
		downAt = os.clock()
		downPos = Vector2.new(input.Position.X, input.Position.Y)
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		local t = input.UserInputType
		if processed or (t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch) then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if os.clock() - downAt > 0.35 or (pos - downPos).Magnitude > 10 then
			return
		end
		if options.canOpen and not options.canOpen() then
			return
		end
		local p = Profile.playerAt(pos)
		if p then
			Profile.open(p)
		end
	end)
end

return Profile
