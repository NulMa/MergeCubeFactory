--!strict
-- 펫 모양 만들기 (docs/24): Pets 정의 → Model. 따라다니는 펫·뽑기 연출·인벤토리 미리보기가 같이 쓴다.
-- 모델 = 보이지 않는 Root + 조각들, 전부 Anchored. Root 기준 상대 위치로 PetLook.mover가 한 번에 옮긴다(BulkMoveTo).
-- 별(★2·★3)은 같은 모델에 오라(반짝이·빛)를 붙이고 조금 키운다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Game.AssetIds)
local Pets = require(ReplicatedStorage.Game.Pets)
local PetModels = require(ReplicatedStorage.Game.PetModels)

local PetLook = {}

local DEFAULT_LEN = 2.4
local STAR_SCALE = { 1, 1.12, 1.25 }
local SHAPES: { [string]: Enum.PartType } = {
	B = Enum.PartType.Block,
	S = Enum.PartType.Ball,
	C = Enum.PartType.Cylinder,
}
local GOLD = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 180, 40))
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 255, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 110, 255)),
})

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function basePart(kind: string): BasePart
	local p: BasePart
	if kind == "W" then
		p = Instance.new("WedgePart")
	elseif kind == "K" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = SHAPES[kind] or Enum.PartType.Block
		p = part
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function fromData(m: Model, parts: { { [string]: any } })
	for _, e in parts do
		local p = basePart(e.k)
		p.Size = v3(e.s)
		local rot = e.r
		p.CFrame = CFrame.new(v3(e.p))
			* (
				if rot
					then CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					else CFrame.identity
			)
		p.Color = Color3.fromHex(string.format("%06X", e.c))
		if e.m then
			local ok, mat = pcall(function()
				return (Enum.Material :: any)[e.m]
			end)
			if ok and mat then
				p.Material = mat
			end
		end
		p.Transparency = e.t or 0
		p.Reflectance = e.f or 0
		local mesh = e.mesh
		if mesh then
			local sm = Instance.new("SpecialMesh")
			if mesh.id and not mesh.mt or mesh.mt == "FileMesh" then
				sm.MeshType = Enum.MeshType.FileMesh
				sm.MeshId = `rbxassetid://{mesh.id}`
				sm.TextureId = if mesh.tex then `rbxassetid://{mesh.tex}` else ""
			else
				local ok, mt = pcall(function()
					return (Enum.MeshType :: any)[mesh.mt]
				end)
				sm.MeshType = if ok and mt then mt else Enum.MeshType.Brick
			end
			sm.Scale = v3(mesh.sc)
			if mesh.o then
				sm.Offset = v3(mesh.o)
			end
			sm.Parent = p
		end
		if e.d then
			for _, d in e.d do
				local decal = Instance.new("Decal")
				decal.Face = (Enum.NormalId :: any)[d[1]]
				decal.Texture = `rbxassetid://{d[2]}`
				decal.Parent = p
			end
		end
		p.Parent = m
	end
end

local function fromMesh(m: Model, mesh: { id: number, tex: number?, size: Vector3 })
	local p = basePart("B")
	p.Size = mesh.size
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.FileMesh
	sm.MeshId = `rbxassetid://{mesh.id}`
	sm.TextureId = if mesh.tex then `rbxassetid://{mesh.tex}` else ""
	sm.Parent = p
	p.Parent = m
end

local function fromCube(m: Model, cube: { color: Color3, material: string?, rainbow: boolean? })
	local p = basePart("B")
	p.Size = Vector3.new(2, 2, 2)
	p.Color = cube.color
	p.Material = if cube.material then (Enum.Material :: any)[cube.material] else Enum.Material.SmoothPlastic
	if cube.rainbow then
		p:SetAttribute("Rainbow", true)
	end
	local face = Instance.new("Decal")
	face.Face = Enum.NormalId.Front -- 진행 방향(-Z)
	face.Texture = (AssetIds.Images :: any).FaceHappy or ""
	face.Parent = p
	p.Parent = m
end

-- 크기·중심 맞추기: 가장 긴 변 = len, 바운딩 박스 중심이 원점. 메시는 SpecialMesh.Scale도 같이
local function normalize(m: Model, len: number, yaw: number)
	local cf, size = m:GetBoundingBox()
	-- 부피 기준(세 변의 기하평균 = len × 0.8): 길쭉한 동물(사자·기린)이 너무 작아지지 않게. 가장 긴 변은 len × 1.7까지
	local mean = math.max(size.X * size.Y * size.Z, 1e-4) ^ (1 / 3)
	local s = math.min(len * 0.8 / mean, len * 1.7 / math.max(size.X, size.Y, size.Z, 0.01))
	local turn = CFrame.Angles(0, math.rad(yaw), 0)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			local rel = cf:ToObjectSpace(p.CFrame)
			p.CFrame = turn * CFrame.new(rel.Position * s) * rel.Rotation
			p.Size *= s
			local sm = p:FindFirstChildOfClass("SpecialMesh")
			if sm then
				if sm.MeshType == Enum.MeshType.FileMesh then
					sm.Scale *= s
				end
				sm.Offset *= s
			end
		end
	end
end

-- 별 오라: ★2 금빛 반짝이 + 빛, ★3 무지개 반짝이 + 고리 + 더 밝은 빛
local function addAura(root: BasePart, star: number, len: number)
	if star < 2 then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "StarAura"
	att.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = (AssetIds.Images :: any).Sparkle or ""
	pe.Color = if star >= 3 then RAINBOW else GOLD
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35 * len / 2.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Rate = if star >= 3 then 16 else 8
	pe.Speed = NumberRange.new(0.4, 1.2)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-120, 120)
	pe.Parent = att
	if star >= 3 then
		local ring = Instance.new("ParticleEmitter")
		ring.Texture = (AssetIds.Images :: any).Ring or (AssetIds.Images :: any).Sparkle or ""
		ring.Color = RAINBOW
		ring.LightEmission = 1
		ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		ring.Size = NumberSequence.new(len * 0.3, len * 0.9)
		ring.Transparency = NumberSequence.new(0.3, 1)
		ring.Lifetime = NumberRange.new(1)
		ring.Rate = 1.5
		ring.Speed = NumberRange.new(0.01)
		ring.EmissionDirection = Enum.NormalId.Top
		ring.Parent = att
	end
	local light = Instance.new("PointLight")
	light.Color = if star >= 3 then Color3.fromRGB(220, 160, 255) else Color3.fromRGB(255, 210, 90)
	light.Brightness = if star >= 3 then 2.5 else 1.5
	light.Range = if star >= 3 then 10 else 7
	light.Parent = root
end

-- 펫 모델. withAura = false면 반짝이·빛 없이 (뷰포트용)
function PetLook.build(id: string, star: number?, withAura: boolean?): Model?
	local def = Pets.get(id)
	if not def then
		return nil
	end
	local s = math.clamp(star or 1, 1, Pets.MAX_STAR)
	local m = Instance.new("Model")
	m.Name = "Pet_" .. id
	if def.model and PetModels[def.model] then
		fromData(m, PetModels[def.model])
	elseif def.mesh then
		fromMesh(m, def.mesh)
	elseif def.cube then
		fromCube(m, def.cube)
	else
		return nil
	end
	local len = (def.len or DEFAULT_LEN) * STAR_SCALE[s]
	normalize(m, len, def.yaw or 0)
	local _, ext = m:GetBoundingBox()
	local root = basePart("B")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CFrame = CFrame.identity
	root.Parent = m
	m.PrimaryPart = root
	if withAura ~= false then
		addAura(root, s, len)
	end
	m:SetAttribute("Len", math.max(ext.X, ext.Y, ext.Z)) -- 가장 긴 변 (뷰포트 카메라 거리)
	m:SetAttribute("Height", ext.Y) -- 바닥에서 띄울 높이
	return m
end

-- 뷰포트용: 반짝이·빛 없이
function PetLook.still(id: string, star: number?): Model?
	local m = PetLook.build(id, star, false)
	if not m then
		return nil
	end
	return m
end

-- 따라다니기용: move(cf) 한 번에 모든 조각을 Root 기준 자리로 (용접은 클라이언트 고정 Root에서 안 따라옴, 2026-10-19 확인)
function PetLook.mover(m: Model): (CFrame) -> ()
	local root = m.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(offsets, root.CFrame:ToObjectSpace(p.CFrame))
		end
	end
	local cfs = table.create(#parts) :: { CFrame }
	return function(cf: CFrame)
		for i, o in offsets do
			cfs[i] = cf * o
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- 무지개 큐브 등 색이 도는 조각 (매 프레임 호출)
function PetLook.animate(m: Model, now: number)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("Rainbow") then
			p.Color = Color3.fromHSV((now * 0.3) % 1, 0.7, 1)
		end
	end
end

return PetLook
