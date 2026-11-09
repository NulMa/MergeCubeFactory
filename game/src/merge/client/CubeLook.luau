--!strict
-- 큐브 얼굴(정면·뒷면 Decal)과 윗면 등급 숫자(SurfaceGui)를 클라이언트가 직접 붙인다 (2026-10-21 고등급 렉).
-- 예전엔 서버가 큐브마다 Decal 2 + SurfaceGui + TextLabel을 만들어 모두에게 복제했다: 후반(초당 큐브 ~24개)엔
-- 큐브 하나에 인스턴스 5개 → 초당 120개를 복제·생성. 이제 서버는 Part와 속성(Tier, AtMax)만 보낸다.
-- 등급이 바뀌면(합치기) Tier 속성 변화로 얼굴·숫자를 갈아 끼운다.
-- 데이터 큐브 파트는 풀에서 다시 쓰인다(client/CubeView, 2026-10-22): 폴더에 다시 들어와도 Num이 있으면 새로 만들지 않고,
-- 처음 단 Tier·AtMax 감시가 그대로 남아 꺼낼 때 바뀐 등급으로 고친다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Game.Config)

local CubeLook = {}

local MAX_COLOR = Color3.fromRGB(255, 220, 90)

local function refresh(part: BasePart, faces: { Decal }, text: TextLabel)
	local tier = part:GetAttribute("Tier")
	if typeof(tier) ~= "number" then
		return
	end
	local faceId = Config.faceFor(tier)
	for _, f in faces do
		f.Texture = faceId
	end
	-- 합치기 상한 등급이면 숫자 아래 "MAX" (멈춘 게 버그처럼 보이지 않게)
	if part:GetAttribute("AtMax") then
		text.Text = `{tier}\nMAX`
		text.TextColor3 = MAX_COLOR
	else
		text.Text = tostring(tier)
		text.TextColor3 = Color3.new(1, 1, 1)
	end
end

local function decorate(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("Num") then
		return
	end
	local faces: { Decal } = {}
	for _, side in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local face = Instance.new("Decal")
		face.Name = "Face"
		face.Face = side
		face.Parent = part
		table.insert(faces, face)
	end
	local num = Instance.new("SurfaceGui")
	num.Name = "Num"
	num.Face = Enum.NormalId.Top
	num.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	num.CanvasSize = Vector2.new(100, 100)
	num.LightInfluence = 0
	num.MaxDistance = 120
	local text = Instance.new("TextLabel")
	text.AutoLocalize = false -- 등급 숫자뿐 (번역 캡처 안 함, client/Loc)
	text.Name = "Text"
	text.Size = UDim2.fromScale(0.8, 0.8)
	text.Position = UDim2.fromScale(0.1, 0.1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(30, 24, 40)
	text.TextStrokeTransparency = 0
	text.Parent = num
	num.Parent = part
	refresh(part, faces, text)
	part:GetAttributeChangedSignal("Tier"):Connect(function()
		refresh(part, faces, text)
	end)
	part:GetAttributeChangedSignal("AtMax"):Connect(function()
		refresh(part, faces, text)
	end)
end

local function watchPlot(plot: Instance)
	local function onCubes(cubes: Instance)
		for _, c in cubes:GetChildren() do
			decorate(c)
		end
		cubes.ChildAdded:Connect(decorate)
	end
	local cubes = plot:FindFirstChild("Cubes")
	if cubes then
		onCubes(cubes)
	else
		plot.ChildAdded:Connect(function(c)
			if c.Name == "Cubes" then
				onCubes(c)
			end
		end)
	end
end

function CubeLook.start()
	local plots = workspace:WaitForChild("Plots")
	for _, p in plots:GetChildren() do
		watchPlot(p)
	end
	plots.ChildAdded:Connect(watchPlot)
	-- 훔쳐서 머리 위에 든 큐브 (server/Steal, 트레이 밖)
	local CollectionService = game:GetService("CollectionService")
	for _, c in CollectionService:GetTagged("CarriedCube") do
		decorate(c)
	end
	CollectionService:GetInstanceAddedSignal("CarriedCube"):Connect(decorate)
end

return CubeLook
