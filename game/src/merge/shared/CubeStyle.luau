--!strict
-- 큐브 겉모습 (크기·등급 색·재질·변이 장식·Tier/AtMax/Variant 속성). 서버 PartBackend와 클라 CubeView가 같이 쓴다 (docs/27 단계 4).
-- 단계 3까지는 server/CubeWorld 안에 있었다. 얼굴·윗면 숫자는 client/CubeLook이 Tier 속성을 보고 따로 붙인다.

local CollectionService = game:GetService("CollectionService")

local VariantDecor = require(script.Parent.VariantDecor)
local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local AssetIds = require(script.Parent.AssetIds)

local CubeStyle = {}

local VARIANT_TAG = "VariantCube" -- 클라이언트가 무지개 색 돌림·이름표 연출에 씀

-- 변이 장식(이름표·반짝이·빛·껍데기)을 지우고 변이에 맞게 다시 단다 (docs/16 §1)
local function styleVariant(part: Part, tier: number, v: number)
	-- 이름이 Variant로 시작하는 자식 = 변이 장식 (VariantTag·Sparkle·Light·Shell·Outline·Orbit·Core·Halo)
	for _, child in part:GetChildren() do
		if string.sub(child.Name, 1, 7) == "Variant" then
			child:Destroy()
		end
	end
	local def = Economy.VARIANTS[v]
	local style = Config.VARIANT_STYLE[def.id]
	part:SetAttribute("Variant", if v == Economy.NORMAL then nil else def.id)
	if not style then
		CollectionService:RemoveTag(part, VARIANT_TAG)
		return
	end
	CollectionService:AddTag(part, VARIANT_TAG)
	local base = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
	part.Color = if style.color then base:Lerp(style.color, style.blend) else base
	part.Material = style.material
	part.Reflectance = style.reflectance
	local s = part.Size.X
	-- 이름표: AlwaysOnTop 아님(큐브 뒤로 가려지는 게 자연스럽고, Studio 화면 캡처에도 찍힘)
	local tag = Instance.new("BillboardGui")
	tag.Name = "VariantTag"
	tag.Size = UDim2.fromScale(math.max(4, s * 1.6), math.max(1, s * 0.4))
	tag.StudsOffset = Vector3.new(0, s / 2 + 0.9 + (if style.particle == "halo" then 0.4 + s * 0.15 else 0), 0) -- 고리 위로
	tag.LightInfluence = 0
	tag.MaxDistance = 90
	tag.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = `{style.label} x{def.mult}`
	text.TextColor3 = style.tag
	text.TextStrokeColor3 = Color3.fromRGB(30, 24, 40)
	text.TextStrokeTransparency = 0
	text.Parent = tag
	-- 모서리 테두리: 등급 띠(Metal/Neon 재질)와 섞여도 변이를 한눈에 알아보게. 클라이언트가 깜빡임·무지개를 돌린다
	local outline = Instance.new("SelectionBox")
	outline.Name = "VariantOutline"
	outline.Adornee = part
	outline.Color3 = style.outline
	outline.LineThickness = 0.08 + s * 0.015
	outline.SurfaceTransparency = 1
	outline.Parent = part
	if style.sparkle then
		-- 변이마다 다른 입자. 큐브 표면에서 나오도록 파트에 바로 단다
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "VariantSparkle"
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.SpreadAngle = Vector2.new(180, 180)
		local big = 0.35 + s * 0.08
		local function size(peak: number)
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, peak),
				NumberSequenceKeypoint.new(1, 0),
			})
		end
		if style.particle == "glint" then
			-- 금속 번쩍임: 드물고 크고 짧게, 제자리에서
			pe.Texture = AssetIds.Images.Sparkle
			pe.Rate = 1.2 + v * 0.4
			pe.Lifetime = NumberRange.new(0.25, 0.4)
			pe.Speed = NumberRange.new(0)
			pe.Rotation = NumberRange.new(0, 90)
			pe.LockedToPart = true
			pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
			size(big * 2.2)
		elseif style.particle == "orb" then
			-- 네온: 떠오르는 빛방울
			pe.Texture = AssetIds.Images.Glow
			pe.Rate = 5 + v
			pe.Lifetime = NumberRange.new(0.9, 1.5)
			pe.Speed = NumberRange.new(0.3, 1)
			pe.Acceleration = Vector3.new(0, 5, 0)
			pe.Color = ColorSequence.new(style.outline)
			size(big * 0.9)
		elseif style.particle == "prism" then
			-- 무지개: 여러 색 반짝이가 흩어짐
			pe.Texture = AssetIds.Images.Sparkle
			pe.Rate = 6 + v
			pe.Lifetime = NumberRange.new(0.6, 1)
			pe.Speed = NumberRange.new(1.5, 3.5)
			pe.RotSpeed = NumberRange.new(-180, 180)
			pe.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 140)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
			})
			size(big)
		elseif style.particle == "vortex" then
			-- 우주: 표면에서 새어 나오는 잔별 + 둘레를 도는 별무리 두 줄기(클라이언트가 VariantOrbit을 돌림) + 강착 고리
			pe.Texture = AssetIds.Images.Sparkle
			pe.Rate = 14
			pe.Lifetime = NumberRange.new(0.8, 1.4)
			pe.Speed = NumberRange.new(0.3, 0.9)
			pe.Drag = 2
			pe.RotSpeed = NumberRange.new(-90, 90)
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), style.pulse or style.outline)
			size(big * 0.5)
			-- 몸통 여섯 면에 별 무늬(클라이언트가 천천히 흘림) → 큐브 속이 밤하늘처럼 보임
			for _, face in Enum.NormalId:GetEnumItems() do
				local stars = Instance.new("Texture")
				stars.Name = "VariantStars"
				stars.Face = face
				stars.Texture = AssetIds.Images.Sparkle
				stars.StudsPerTileU = s * 0.45
				stars.StudsPerTileV = s * 0.45
				stars.Color3 = Color3.fromRGB(190, 230, 255)
				stars.Transparency = 0.15
				stars.ZIndex = 0
				stars.Parent = part
			end
			for k = 1, 2 do
				local orbit = Instance.new("Attachment")
				orbit.Name = "VariantOrbit"
				orbit:SetAttribute("Phase", k * math.pi)
				orbit.Parent = part
				local trail = Instance.new("ParticleEmitter")
				trail.Texture = AssetIds.Images.Sparkle
				trail.LightEmission = 1
				trail.LightInfluence = 0
				trail.Rate = 40
				trail.Lifetime = NumberRange.new(0.6, 1.1)
				trail.Speed = NumberRange.new(0)
				trail.RotSpeed = NumberRange.new(-120, 120)
				trail.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(0.4, style.pulse or style.tag),
					ColorSequenceKeypoint.new(1, style.outline),
				})
				trail.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, big * 0.7),
					NumberSequenceKeypoint.new(1, 0),
				})
				trail.Parent = orbit
			end
			-- 강착 고리: 납작한(수평) 고리가 큐브 둘레로 퍼지며 사라짐
			local core = Instance.new("Attachment")
			core.Name = "VariantCore"
			core.Parent = part
			local ring = Instance.new("ParticleEmitter")
			ring.Texture = AssetIds.Images.Ring
			ring.LightEmission = 1
			ring.LightInfluence = 0
			ring.EmissionDirection = Enum.NormalId.Top
			ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
			ring.Speed = NumberRange.new(0.01)
			ring.SpreadAngle = Vector2.new(0, 0)
			ring.Rate = 1.6
			ring.Lifetime = NumberRange.new(1.6)
			ring.Size = NumberSequence.new(s * 0.7, s * 2.4)
			ring.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			ring.Color = ColorSequence.new(style.outline, style.pulse or style.tag)
			ring.Parent = core
		elseif style.particle == "halo" then
			-- 신성: 위로 솟는 가늘고 긴 빛줄기 + 큐브 뒤에서 도는 햇살 + 머리 위 금빛 고리(클라이언트가 둥실거림)
			pe.Texture = AssetIds.Images.Glow
			pe.Rate = 12
			pe.Lifetime = NumberRange.new(0.7, 1.2)
			pe.EmissionDirection = Enum.NormalId.Top
			pe.SpreadAngle = Vector2.new(8, 8)
			pe.Speed = NumberRange.new(3, 6)
			pe.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
			pe.Squash = NumberSequence.new(2.6)
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 240), style.outline)
			pe.Transparency = NumberSequence.new(0.1, 1)
			size(big * 0.9)
			local core = Instance.new("Attachment")
			core.Name = "VariantCore"
			core.Parent = part
			local burst = Instance.new("ParticleEmitter")
			burst.Texture = AssetIds.Icons.Sunburst
			burst.LightEmission = 1
			burst.LightInfluence = 0
			burst.ZOffset = -s
			burst.Speed = NumberRange.new(0)
			burst.Rate = 2
			burst.Lifetime = NumberRange.new(1.5)
			burst.Rotation = NumberRange.new(0, 360)
			burst.RotSpeed = NumberRange.new(25, 35)
			burst.LockedToPart = true
			burst.Size = NumberSequence.new(s * 1.6)
			burst.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			burst.Color = ColorSequence.new(style.tag)
			burst.Parent = core
			-- 머리 위 헤일로는 VariantDecor(크리스탈 헤일로 메시)가 붙인다
		else
			-- 은하: 천천히 맴도는 별
			pe.Texture = AssetIds.Images.Sparkle
			pe.Rate = 8 + v
			pe.Lifetime = NumberRange.new(1.2, 2)
			pe.Speed = NumberRange.new(0.2, 0.8)
			pe.RotSpeed = NumberRange.new(-60, 60)
			pe.Drag = 1
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), style.outline)
			size(big * 0.8)
		end
		pe.Parent = part
	end
	if style.light then
		local light = Instance.new("PointLight")
		light.Name = "VariantLight"
		light.Color = style.tag
		light.Range = 6 + s * 1.5 * (style.glow or 1.2) / 1.2
		light.Brightness = style.glow or 1.2
		light.Parent = part
	end
	if style.shell then
		-- 일렁이는 ForceField 껍데기(Cosmic은 짙은 유리 "사건의 지평선"). 질량·충돌 없음, 큐브에 붙어 같이 움직임
		local shell = Instance.new("Part")
		shell.Name = "VariantShell"
		shell.Size = part.Size * (style.shellScale or 1.08)
		shell.CFrame = part.CFrame
		shell.Material = style.shellMaterial or Enum.Material.ForceField
		shell.Transparency = style.shellTransparency or 0
		shell.Color = style.tag
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.Massless = true
		shell.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = shell
		weld.Parent = shell
		shell.Parent = part
	end
	-- 꾸미기 (선글라스·무지개 꼬리·성운·헤일로, shared/VariantDecor)
	VariantDecor.attach(part, def.id)
end

local function styleCube(part: Part, tier: number, v: number)
	local s = Config.cubeSize(tier)
	part.Size = Vector3.new(s, s, s)
	part.Color = Config.TIER_COLORS[tier] or Color3.new(1, 1, 1)
	Config.applyTierLook(part, tier)
	-- 등급별 표정·윗면 숫자는 클라이언트(client/CubeLook)가 Tier 속성을 보고 붙인다 (복제 줄이기, 2026-10-21)
	part:SetAttribute("Tier", tier)
	styleVariant(part, tier, v)
end

-- 합치기 상한(리버스 전 T12, 리버스마다 +2) 등급이면 윗면 숫자 아래 "MAX" (멈춘 게 버그처럼 보이지 않게)
local function markCeiling(part: Part, atMax: boolean)
	part:SetAttribute("AtMax", if atMax then true else nil)
end

-- 등급·변이를 (다시) 입힌다. 변이 장식은 지우고 새로 단다
function CubeStyle.apply(part: Part, tier: number, variant: number)
	styleCube(part, tier, variant)
end

CubeStyle.markCeiling = markCeiling

-- 새 큐브 파트 (물리 설정·부모는 부르는 쪽 몫). cf를 먼저 정해야 변이 껍데기 용접이 제자리에 붙는다
function CubeStyle.part(tier: number, variant: number, atMax: boolean, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "Cube"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CollisionGroup = "Cubes"
	part.CFrame = cf
	styleCube(part, tier, variant)
	markCeiling(part, atMax)
	return part
end

-- ===== 파트 풀 (client/CubeView, 2026-10-22) =====
-- 풀에 넣을 때(부모를 뗀 뒤): 변이 장식(껍데기·용접·테두리·입자·이름표)을 모두 지우고 일반 겉모습으로 되돌린다.
-- 그래서 풀 안 파트는 늘 "일반 변이 + 어떤 등급" → 꺼낼 때 변이를 처음부터 새로 다는 것과 같다 (용접이 새 CFrame에 붙음).
-- 얼굴·숫자(client/CubeLook의 Face·Num)와 등급 빛(Glow·Sparkle)은 남겨 다시 쓴다.
function CubeStyle.park(part: Part)
	local tier = part:GetAttribute("Tier")
	if part:GetAttribute("Variant") ~= nil or CollectionService:HasTag(part, VARIANT_TAG) then
		styleCube(part, if typeof(tier) == "number" then tier else 1, Economy.NORMAL)
	end
	CollectionService:RemoveTag(part, VARIANT_TAG)
	markCeiling(part, false)
end

-- 풀에서 꺼낸 파트에 겉모습을 입힌다. 등급이 같고 일반이면 속성·자식을 건드리지 않는다 (인스턴스 생성 0)
function CubeStyle.reuse(part: Part, tier: number, variant: number, atMax: boolean, cf: CFrame)
	part.CFrame = cf
	if part:GetAttribute("Tier") ~= tier or variant ~= Economy.NORMAL then
		styleCube(part, tier, variant)
	end
	markCeiling(part, atMax)
end

return CubeStyle
