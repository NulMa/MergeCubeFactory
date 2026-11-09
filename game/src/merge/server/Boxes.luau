--!strict
-- 광장 선물 상자 (2026-10-20 "접속 중에만 되는 성장 가속", 규칙 shared/Online).
-- 광장 곳곳에 상자가 나타나고, 먼저 닿은 사람이 기본 수입 90초치 + 펫 조각을 받는다. 공장 밖을 돌아다닐 이유.
-- 상자는 모두에게 보이고 하나는 한 사람만 연다 (무료 보상, 확정값).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Game
local Online = require(game:GetService("ReplicatedStorage").Core.Online)
local Pets = require(Shared.Pets)
local Strings = require(Shared.Strings)
local Format = require(game:GetService("ReplicatedStorage").Core.Format)
local Ledger = require(game:GetService("ServerScriptService").CoreServer.Ledger)

type Ctx = {
	states: { [Player]: any },
	center: Vector3, -- 광장 바닥 가운데
	radius: number, -- 상자를 놓을 최대 반지름
	fx: (player: Player, ...any) -> (),
	refresh: (player: Player) -> (),
	busy: (player: Player) -> boolean, -- 레이드 중이면 못 엶 (광장이 전장)
}

local Boxes = {}

local rng = Random.new()
local boxes: { [Part]: number } = {} -- 상자 → 사라지는 시각
local folder: Folder? = nil

local RIBBON = Color3.fromRGB(255, 220, 90)
local COLORS = {
	Color3.fromRGB(255, 110, 150),
	Color3.fromRGB(110, 200, 255),
	Color3.fromRGB(150, 235, 120),
	Color3.fromRGB(200, 140, 255),
}

local function remove(box: Part)
	boxes[box] = nil
	box:Destroy()
end

local function open(c: Ctx, box: Part, player: Player)
	local st = c.states[player]
	if not st or not boxes[box] or c.busy(player) then
		return
	end
	boxes[box] = nil
	local cash = Online.boxCash(st.baseIncome or 0)
	local shards = Online.BOX_SHARD_MERGES * Pets.shardsForMerge(st.data.stats.best or 1)
	Ledger.credit(player, "cash", cash, "Gameplay", "plaza_box")
	Ledger.credit(player, "shards", shards, "Gameplay", "plaza_box")
	-- 받은 것을 상자 자리에 띄우고 토스트로도 (예전엔 공장 가운데에 떠서 광장에선 안 보였다, 2026-10-20 사용자)
	c.fx(player, "gift", box.Position, Strings.msg("gift.box", { cash = Format.short(cash), shards = shards }))
	c.refresh(player)
	-- 열리며 위로 튀고 사라짐
	box.CanTouch = false
	TweenService:Create(box, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = Vector3.one * 0.2,
		CFrame = box.CFrame + Vector3.new(0, 4, 0),
	}):Play()
	task.delay(0.45, function()
		box:Destroy()
	end)
end

local function spawnBox(c: Ctx)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(c.radius * 0.35, c.radius)
	local at = c.center + Vector3.new(math.cos(a) * r, 2.2, math.sin(a) * r)
	local color = COLORS[rng:NextInteger(1, #COLORS)]
	local box = Instance.new("Part")
	box.Name = "GiftBox"
	box.Size = Vector3.new(3, 3, 3)
	box.CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	box.Color = color
	box.Material = Enum.Material.SmoothPlastic
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = true
	-- 리본 십자 + 위 매듭
	for _, size in { Vector3.new(3.05, 3.05, 0.6), Vector3.new(0.6, 3.05, 3.05) } do
		local band = Instance.new("Part")
		band.Name = "Ribbon"
		band.Size = size
		band.CFrame = box.CFrame
		band.Color = RIBBON
		band.Material = Enum.Material.SmoothPlastic
		band.Anchored = false
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = box
		w.Part1 = band
		w.Parent = band
		band.Parent = box
	end
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = RIBBON
	sparkle.Parent = box
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = box
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(110, 34)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	bb.Parent = box
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "GIFT!"
	t.TextColor3 = RIBBON
	t.TextStrokeTransparency = 0
	t.Parent = bb
	box.Touched:Connect(function(hit: BasePart)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			open(c, box, player)
		end
	end)
	-- 천천히 돌며 둥실
	TweenService:Create(
		box,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = box.CFrame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.pi / 2, 0) }
	):Play()
	box.Parent = folder
	boxes[box] = os.clock() + Online.BOX_LIFE
end

function Boxes.init(c: Ctx)
	local f = Instance.new("Folder")
	f.Name = "GiftBoxes"
	f.Parent = workspace
	folder = f
	local nextAt = os.clock() + 30
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		local t = os.clock()
		for box, dies in boxes do
			if t >= dies then
				remove(box)
			end
		end
		local n = 0
		for _ in boxes do
			n += 1
		end
		if t >= nextAt and #Players:GetPlayers() > 0 then
			nextAt = t + Online.BOX_EVERY
			if n < Online.BOX_MAX then
				spawnBox(c)
			end
		end
	end)
end

return Boxes
