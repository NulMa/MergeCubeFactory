--!strict
-- Player showcase (docs/33 §11-4): 3-5 pedestals in each player's space showing rare things they chose.
-- Saved per player, visible to everyone. Opt-in core server module; client side = CoreClient/ShowcaseUi.
--   Showcase.init({
--     slots = 4,
--     getData = function(player) return Data.get(player) end,       -- saved in data[key] (default "showcase")
--     eligible = function(player) return { "dragon", "phoenix" } end, -- ids the player may show (owned, rare+)
--     info = function(id) return { name = "Dragon", rarity = "Mythic", color = Color3.fromRGB(255, 80, 60), icon = "rbxassetid://..." } end,
--     build = function(id) return ReplicatedStorage.Models[id]:Clone() end,   -- display model (Model or BasePart)
--     theme = require(ReplicatedStorage.Game.UiTheme),               -- optional: ux.pedestal + palette.accent
--     pedestal = ServerStorage.ShowcasePedestal,                      -- optional custom pedestal Model (cloned)
--   })
--   Showcase.place(player, { cf1, cf2, cf3, cf4 }, plotFolder)   -- build pedestals at plot slots (CFrame or BasePart)
--   Showcase.set(player, 2, "dragon")  /  Showcase.set(player, 2, nil)
--   Showcase.list(player) -> { { slot, id, name, rarity, color, icon } } (Profile card uses this)
-- Each pedestal has a ProximityPrompt; the owner's client opens the picker (others' prompts are hidden locally).
-- Pedestal model attributes: CoreShowcaseOwner (UserId), CoreShowcaseSlot. Items are tagged CoreShowcaseItem
-- (clients spin them locally). Pedestal look: theme ux.pedestal (color, trim, material, glow, plate, spin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Core.Net)
local Theme = require(ReplicatedStorage.Core.Theme)

local Showcase = {}

export type Info = { name: string, rarity: string?, color: Color3?, icon: string? }
export type Options = {
	slots: number?,
	getData: (Player) -> { [string]: any }?,
	key: string?,
	eligible: (Player) -> { string },
	info: (string) -> Info?,
	build: (string) -> Instance?,
	theme: { [string]: any }?,
	pedestal: Model?,
	itemSize: number?, -- largest side of a shown item in studs (default 3.4)
	onChanged: ((Player) -> ())?,
}

Showcase.SPEC = {
	CoreShowcase = { kind = "event" }, -- server -> client: state changed
	CoreShowcaseGet = { kind = "function", args = {} },
	CoreShowcaseSet = { kind = "function", args = { "number", "string" } },
}

local opts: Options? = nil
local server: Net.Server? = nil
local look: { [string]: any } = {}
local placed: { [Player]: { Model } } = {}
local lastSet: { [Player]: number } = {}

function Showcase.slots(): number
	return math.clamp((opts and opts.slots) or 4, 1, 8)
end

local function saved(player: Player): { string }?
	local o = opts
	local data = o and o.getData(player)
	if not o or not data then
		return nil
	end
	local key = o.key or "showcase"
	local s = data[key]
	if type(s) ~= "table" then
		s = {}
		data[key] = s
	end
	for i = 1, Showcase.slots() do
		if type(s[i]) ~= "string" then
			s[i] = ""
		end
	end
	for i = #s, Showcase.slots() + 1, -1 do
		s[i] = nil
	end
	return s
end

local function eligibleSet(player: Player): { [string]: boolean }
	local set = {}
	local o = opts
	if o then
		local ok, list = pcall(o.eligible, player)
		if ok and type(list) == "table" then
			for _, id in list do
				if type(id) == "string" then
					set[id] = true
				end
			end
		end
	end
	return set
end

local function infoOf(id: string): Info
	local o = opts
	local ok, inf = pcall(function()
		return o and o.info(id)
	end)
	if ok and inf then
		return inf
	end
	return { name = id }
end

------------------------------------------------------------------------
-- Pedestal building
------------------------------------------------------------------------

local function cyl(
	name: string,
	h: number,
	d: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, d, d)
	p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Default pedestal: trimmed plinth + column + top plate + rarity ring. Returns the model and the top center CFrame.
local function defaultPedestal(at: CFrame): (Model, CFrame)
	local m = Instance.new("Model")
	m.Name = "Pedestal"
	local col: Color3 = look.color
	local trim: Color3 = look.trim
	local mat: Enum.Material = look.material
	cyl("Base", 0.6, 4.6, at * CFrame.new(0, 0.3, 0), trim, mat, m)
	local column = cyl("Column", 2.2, 3.2, at * CFrame.new(0, 1.7, 0), col, mat, m)
	cyl("Top", 0.45, 4.1, at * CFrame.new(0, 3.0, 0), trim, mat, m)
	local ring = cyl("Ring", 0.12, 4.3, at * CFrame.new(0, 3.24, 0), col, Enum.Material.Neon, m)
	ring.Transparency = 0.25
	m.PrimaryPart = column
	return m, at * CFrame.new(0, 3.3, 0)
end

local function customPedestal(template: Model, at: CFrame): (Model, CFrame)
	local m = template:Clone()
	local cf, size = m:GetBoundingBox()
	-- stand it on `at` (bottom of the box on the anchor)
	m:PivotTo(at * CFrame.new(0, size.Y / 2, 0) * cf:ToObjectSpace(m:GetPivot()))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return m, at * CFrame.new(0, size.Y + 0.05, 0)
end

local function fitItem(item: Instance, top: CFrame): Instance
	local maxSide = (opts and opts.itemSize) or 3.4
	if item:IsA("Model") then
		local _, size = item:GetBoundingBox()
		local big = math.max(size.X, size.Y, size.Z)
		if big > 0 and math.abs(big - maxSide) > 0.05 then
			item:ScaleTo(item:GetScale() * maxSide / big)
		end
		local cf, s2 = item:GetBoundingBox()
		item:PivotTo(top * CFrame.new(0, s2.Y / 2 + 0.25, 0) * cf:ToObjectSpace(item:GetPivot()))
	elseif item:IsA("BasePart") then
		local big = math.max(item.Size.X, item.Size.Y, item.Size.Z)
		if big > maxSide then
			item.Size *= maxSide / big
		end
		item.CFrame = top * CFrame.new(0, item.Size.Y / 2 + 0.25, 0)
	end
	local list = item:GetDescendants()
	table.insert(list, item)
	for _, d in list do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- display only
		end
	end
	CollectionService:AddTag(item, "CoreShowcaseItem")
	return item
end

local function dress(ped: Model, top: CFrame, id: string, player: Player, slot: number)
	local old = ped:FindFirstChild("Item")
	if old then
		old:Destroy()
	end
	local plate = ped:FindFirstChild("Plate")
	if plate then
		plate:Destroy()
	end
	local ring = ped:FindFirstChild("Ring") :: BasePart?
	local light = ped:FindFirstChild("Glow", true)
	if light then
		light:Destroy()
	end
	local inf = if id ~= "" then infoOf(id) else nil
	local rc = (inf and inf.color) or look.color
	if ring then
		ring.Color = rc
	end
	local topPart = ped:FindFirstChild("Top") :: BasePart? or ped.PrimaryPart
	if inf and look.glow and topPart then
		local l = Instance.new("PointLight")
		l.Name = "Glow"
		l.Color = rc
		l.Range = 12
		l.Brightness = 1.6
		l.Parent = topPart
	end
	-- prompt (owner opens the picker on the client)
	local prompt = ped:FindFirstChild("ShowcasePrompt", true) :: ProximityPrompt?
	if not prompt and topPart then
		local p = Instance.new("ProximityPrompt")
		p.Name = "ShowcasePrompt"
		p.ActionText = if id == "" then "Display" else "Change"
		p.ObjectText = "Showcase " .. slot
		p.HoldDuration = 0
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p.Parent = topPart
		prompt = p
	elseif prompt then
		prompt.ActionText = if id == "" then "Display" else "Change"
	end
	if not inf then
		return
	end
	local o = opts :: Options
	local ok, built = pcall(o.build, id)
	if ok and built then
		local item = fitItem(built, top)
		item.Name = "Item"
		item.Parent = ped
	end
	if look.plate and topPart then
		local bb = Instance.new("BillboardGui")
		bb.Name = "Plate"
		bb.Adornee = topPart
		bb.Size = UDim2.fromOffset(200, 50)
		bb.StudsOffsetWorldSpace = Vector3.new(0, ((o.itemSize or 3.4) + 1.6), 0)
		bb.MaxDistance = 70
		bb.LightInfluence = 0
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromScale(1, 0.6)
		name.TextScaled = true
		name.Text = inf.name
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.2
		name.TextStrokeColor3 = Color3.fromRGB(20, 16, 30)
		local e, f = Theme.font(look.font)
		if e then
			name.Font = e
		elseif f then
			name.FontFace = f
		end
		name.Parent = bb
		if inf.rarity then
			local r = name:Clone()
			r.Text = string.upper(inf.rarity)
			r.TextColor3 = rc
			r.Size = UDim2.fromScale(1, 0.4)
			r.Position = UDim2.fromScale(0, 0.6)
			r.Parent = bb
		end
		bb.Parent = ped
	end
	ped:SetAttribute("CoreShowcaseItemId", id)
	ped:SetAttribute("CoreShowcaseOwner", player.UserId)
	ped:SetAttribute("CoreShowcaseSlot", slot)
end

local tops: { [Model]: CFrame } = {}

local function refreshPedestals(player: Player)
	local peds = placed[player]
	local s = saved(player)
	if not peds or not s then
		return
	end
	for i, ped in peds do
		dress(ped, tops[ped], s[i] or "", player, i)
	end
end

-- Build pedestals at anchors (CFrame or BasePart, one per slot; extra anchors ignored). Replaces earlier ones.
function Showcase.place(player: Player, anchors: { any }, parent: Instance?)
	Showcase.remove(player)
	local peds = {}
	local folder = Instance.new("Folder")
	folder.Name = "Showcase_" .. player.UserId
	for i = 1, math.min(#anchors, Showcase.slots()) do
		local a = anchors[i]
		local at: CFrame = if typeof(a) == "CFrame" then a else (a :: BasePart).CFrame
		local ped, top
		if opts and opts.pedestal then
			ped, top = customPedestal(opts.pedestal, at)
		else
			ped, top = defaultPedestal(at)
		end
		ped.Name = "Pedestal" .. i
		ped:SetAttribute("CoreShowcaseOwner", player.UserId)
		ped:SetAttribute("CoreShowcaseSlot", i)
		tops[ped] = top
		ped.Parent = folder
		peds[i] = ped
	end
	folder.Parent = parent or workspace
	placed[player] = peds
	refreshPedestals(player)
end

function Showcase.remove(player: Player)
	local peds = placed[player]
	if peds then
		local folder = peds[1] and peds[1].Parent
		for _, p in peds do
			tops[p] = nil
		end
		if folder then
			folder:Destroy()
		end
	end
	placed[player] = nil
end

export type Entry = { slot: number, id: string, name: string, rarity: string?, color: Color3?, icon: string? }

function Showcase.list(player: Player): { Entry }
	local out = {}
	local s = saved(player)
	if not s then
		return out
	end
	for i, id in s do
		if id ~= "" then
			local inf = infoOf(id)
			table.insert(
				out,
				{ slot = i, id = id, name = inf.name, rarity = inf.rarity, color = inf.color, icon = inf.icon }
			)
		end
	end
	return out
end

-- Put id (nil/"" = empty) on slot. Only eligible ids; an id shown on another slot moves here.
function Showcase.set(player: Player, slot: number, id: string?): boolean
	local s = saved(player)
	if not s or slot ~= math.floor(slot) or slot < 1 or slot > Showcase.slots() then
		return false
	end
	local want = id or ""
	if want ~= "" and not eligibleSet(player)[want] then
		return false
	end
	if want ~= "" then
		for i, v in s do
			if v == want then
				s[i] = ""
			end
		end
	end
	s[slot] = want
	refreshPedestals(player)
	if server then
		server.fire("CoreShowcase", player, s)
	end
	if opts and opts.onChanged then
		task.spawn(opts.onChanged, player)
	end
	return true
end

-- State for the picker: current slots + eligible items with info
local function stateFor(player: Player)
	local s = saved(player)
	local list = {}
	for id in eligibleSet(player) do
		local inf = infoOf(id)
		table.insert(list, { id = id, name = inf.name, rarity = inf.rarity, color = inf.color, icon = inf.icon })
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	local slotInfo = {}
	local slots: { string } = s or {}
	for i, id in slots do
		slotInfo[i] = if id ~= "" then infoOf(id) else false
	end
	return { slots = s or {}, slotInfo = slotInfo, eligible = list, count = Showcase.slots() }
end

function Showcase.init(o: Options)
	if server then
		return
	end
	opts = o
	local merged = Theme.merge(o.theme)
	look = table.clone(merged.ux.pedestal)
	look.trim = look.trim or merged.palette.accent
	look.font = merged.fonts.title
	local s = Net.serve(Showcase.SPEC :: any)
	server = s
	s.on("CoreShowcaseGet", function(player: Player)
		return stateFor(player)
	end)
	s.on("CoreShowcaseSet", function(player: Player, slot: number, id: string)
		local now = os.clock()
		if lastSet[player] and now - lastSet[player] < 0.25 then
			return false
		end
		lastSet[player] = now
		return Showcase.set(player, slot, id)
	end)
	Players.PlayerRemoving:Connect(function(p)
		Showcase.remove(p)
		lastSet[p] = nil
	end)
end

function Showcase.isReady(): boolean
	return server ~= nil
end

return Showcase
