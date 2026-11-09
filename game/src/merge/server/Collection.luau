--!strict
-- 도감(등급 × 변이)·젬·꾸미기 (docs/16). 재화 변경은 Ledger 경유.
-- 저장 키: data.variants["7:Rainbow"] = true, data.codexMilestone(받은 마일스톤 수),
--          data.codexUnclaimed["7:Rainbow"] = 젬 (발견했지만 아직 안 받은 보상, 도감에서 눌러 받음),
--          data.cosmetics = { owned = { [id] = true }, equipped = { tray, dropper, trail } }

local Shared = game:GetService("ReplicatedStorage").Game
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local AssetIds = require(Shared.AssetIds)
local Shop = require(Shared.Shop)
local Ledger = require(game:GetService("ServerScriptService").CoreServer.Ledger)

local Collection = {}

function Collection.found(data: { [string]: any }): number
	local n = 0
	for _ in data.variants do
		n += 1
	end
	return n
end

-- 다음 마일스톤을 받을 수 있나 (발견 수가 도달했는데 아직 안 받음)
function Collection.milestoneReady(data: { [string]: any }): boolean
	local i = data.codexMilestone + 1
	return i <= #Economy.CODEX_MILESTONES and Collection.found(data) >= Economy.milestoneCount(i)
end

-- (등급, 변이) 첫 발견이면 기록. 젬은 바로 주지 않고 도감에서 직접 눌러 받는다 (2026-10-19, 클릭 보상).
-- 반환: (새 발견인가, 받을 수 있게 된 젬, 이번 발견으로 마일스톤이 막 받을 수 있게 됐나)
function Collection.discover(
	_player: Player,
	data: { [string]: any },
	tier: number,
	v: number
): (boolean, number, boolean)
	if v == Economy.NORMAL then
		return false, 0, false
	end
	local key = Economy.codexKey(tier, v)
	if data.variants[key] then
		return false, 0, false
	end
	local wasReady = Collection.milestoneReady(data)
	data.variants[key] = true
	-- Collector 패스: 첫 발견 젬 ×2 (마일스톤 보너스는 그대로)
	local gems = Economy.VARIANTS[v].gems
		* (if data.passes and data.passes.collector then Shop.COLLECTOR_GEM_MULT else 1)
	if gems > 0 then
		data.codexUnclaimed[key] = gems
	end
	return true, gems, not wasReady and Collection.milestoneReady(data)
end

-- 보상 받기: what = 도감 칸 키("7:Rainbow") 또는 "milestone" (다음 마일스톤 하나). 반환: 받은 젬 (0 = 없음)
function Collection.claim(player: Player, data: { [string]: any }, what: string): number
	local gems = 0
	if what == "milestone" then
		if not Collection.milestoneReady(data) then
			return 0
		end
		data.codexMilestone += 1
		gems = Economy.CODEX_MILESTONES[data.codexMilestone].gems
	else
		gems = data.codexUnclaimed[what] or 0
		data.codexUnclaimed[what] = nil
	end
	if gems > 0 then
		Ledger.credit(player, "gems", gems, "Gameplay", "codex")
	end
	return gems
end

local function owns(data: { [string]: any }, c: Config.Cosmetic): boolean
	return Economy.cosmeticUnlocked(
		c.codex,
		c.gems,
		Collection.found(data),
		data.cosmetics.owned[c.id] == true,
		c.shop ~= nil
	)
end

local function equippedDef(data: { [string]: any }, slot: string): Config.Cosmetic
	local c = Config.cosmetic(data.cosmetics.equipped[slot] or "")
	if c and c.slot == slot and owns(data, c) then
		return c
	end
	return Config.defaultCosmetic(slot)
end

-- 예전 저장: 오라가 꼬리 칸(equipped.trail)에 있었다 → 오라 칸으로 옮긴다 (2026-10-19 칸 분리)
-- 오라가 단계식(젬)으로 바뀌기 전(2026-10-19) 도감 수로 열렸던 오라는 소유로 남겨 둔다
local OLD_AURA_CODEX: { [string]: number } = {
	aura_hearts = 12,
	aura_ember = 15,
	aura_bubbles = 28,
	aura_snow = 55,
	aura_blossom = 85,
	aura_flame = 100,
	aura_divine = 120,
}
local function migrate(data: { [string]: any })
	local eq = data.cosmetics.equipped
	local c = eq.trail and Config.cosmetic(eq.trail)
	if c and c.slot == "aura" then
		eq.aura = eq.trail
		eq.trail = nil
	end
	if not data.cosmetics.auraTiers then
		data.cosmetics.auraTiers = true
		local found = Collection.found(data)
		for id, need in OLD_AURA_CODEX do
			if found >= need then
				data.cosmetics.owned[id] = true
			end
		end
	end
end

-- 지금 장착한 오라 단계 (0 = 없음). 배트 넉백 저항에 쓴다 (Economy.auraResist)
function Collection.auraTier(data: { [string]: any }): number
	return equippedDef(data, "aura").tier or 0
end

-- 단계식 오라: 앞 단계를 모두 가져야 이 단계를 살 수 있다. 막는 단계를 돌려줌 (nil = 살 수 있음)
local function missingTier(data: { [string]: any }, c: Config.Cosmetic): Config.Cosmetic?
	if not c.tier then
		return nil
	end
	for _, other in Config.COSMETICS do
		if other.slot == c.slot and other.tier and other.tier < c.tier and not data.cosmetics.owned[other.id] then
			return other
		end
	end
	return nil
end

-- 텍스처 이름 → id (AssetIds.Images 키 또는 rbxasset:// 경로 그대로)
local function textureOf(name: string?): string?
	if not name then
		return nil
	end
	if string.find(name, "://", 1, true) then
		return name
	end
	return (AssetIds.Images :: any)[name]
end

local function colorSeq(c: Config.Cosmetic): ColorSequence
	if c.rainbow then
		local kp = {}
		for i = 0, 6 do
			table.insert(kp, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 * 0.85, 0.7, 1)))
		end
		return ColorSequence.new(kp)
	end
	local colors = c.colors :: { Color3 }
	return ColorSequence.new(colors[1], colors[#colors])
end

-- 캐릭터 꼬리(Trail)와 오라(ParticleEmitter). HumanoidRootPart 아래 "Cosmetic" 속성이 붙은 Attachment로 만든다
-- (Attachment는 파트 바로 아래 있어야 동작하므로 폴더로 묶지 않고 속성으로 찾아 지운다)
function Collection.applyTrail(character: Model?, data: { [string]: any })
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	migrate(data)
	for _, child in root:GetChildren() do
		if child:GetAttribute("Cosmetic") then
			child:Destroy()
		end
	end
	local function attachment(y: number): Attachment
		local a = Instance.new("Attachment")
		a.Name = "CosmeticTrail"
		a.Position = Vector3.new(0, y, 0)
		a:SetAttribute("Cosmetic", true)
		a.Parent = root
		return a
	end
	local aura = equippedDef(data, "aura")
	if aura.aura then
		-- 단계가 높을수록 화려하게 (2026-10-19): 입자 수·크기·빛이 늘고,
		-- 4단계부터 몸이 빛나고(PointLight), 7단계부터 발밑 고리가 퍼지고, 10단계부터 위로 솟는 빛기둥
		local tier = aura.tier or 1
		local grow = 0.8 + tier * 0.06
		local c1 = if aura.colors then aura.colors[1] else Color3.fromHSV(0.8, 0.6, 1)
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = textureOf(aura.texture) or AssetIds.Images.Sparkle
		pe.Color = colorSeq(aura)
		pe.LightEmission = 1
		pe.SpreadAngle = Vector2.new(180, 180)
		if tier >= 4 then
			local glowAt = attachment(0)
			local light = Instance.new("PointLight")
			light.Color = c1
			light.Brightness = 0.4 + tier * 0.12
			light.Range = 6 + tier * 0.5
			light.Shadows = false
			light.Parent = glowAt
		end
		if tier >= 7 then
			local ringAt = attachment(-2.8)
			local ring = Instance.new("ParticleEmitter")
			ring.Texture = AssetIds.Images.Ring
			ring.Color = colorSeq(aura)
			ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
			ring.EmissionDirection = Enum.NormalId.Top
			ring.Speed = NumberRange.new(0.01)
			ring.Rate = 0.6 + (tier - 7) * 0.25
			ring.Lifetime = NumberRange.new(1.2)
			ring.Size = NumberSequence.new(1, 4 + (tier - 7) * 0.4)
			ring.Transparency = NumberSequence.new(0.3, 1)
			ring.LightEmission = 1
			ring.Parent = ringAt
		end
		if tier >= 10 then
			local pillarAt = attachment(-2.6)
			local pillar = Instance.new("ParticleEmitter")
			pillar.Texture = AssetIds.Images.Glow or AssetIds.Images.Sparkle
			pillar.Color = colorSeq(aura)
			pillar.EmissionDirection = Enum.NormalId.Top
			pillar.SpreadAngle = Vector2.new(8, 8)
			pillar.Speed = NumberRange.new(6, 9)
			pillar.Rate = 10 + (tier - 10) * 6
			pillar.Lifetime = NumberRange.new(0.8, 1.1)
			pillar.Size = NumberSequence.new(0.6, 0)
			pillar.Transparency = NumberSequence.new(0.2, 1)
			pillar.LightEmission = 1
			pillar.Shape = Enum.ParticleEmitterShape.Disc
			pillar.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			pillar.Parent = pillarAt
		end
		if aura.texture then
			-- 모양 오라: 몸 둘레에서 생겨 떠오르거나(+) 떨어진다(-), 천천히 돌며 커졌다 사라짐
			local rise = aura.rise or 0
			pe.Rate = 6 + tier * 1.2
			pe.Lifetime = NumberRange.new(1.4, 2.2)
			pe.Speed = NumberRange.new(0.6, 1.6)
			pe.Acceleration = Vector3.new(0, rise, 0)
			pe.Drag = 1
			pe.Rotation = NumberRange.new(-25, 25)
			pe.RotSpeed = NumberRange.new(-40, 40)
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.2, 0.55 * grow),
				NumberSequenceKeypoint.new(0.8, 0.45 * grow),
				NumberSequenceKeypoint.new(1, 0),
			})
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.75, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Shape = Enum.ParticleEmitterShape.Cylinder
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			pe.LightEmission = if string.find(aura.texture, "fire", 1, true) then 1 else 0.3
			local a = attachment(if rise < 0 then 2.5 else -1.5)
			a.Orientation = Vector3.new(0, 0, 0)
			pe.Parent = a
		else
			pe.Rate = 8 + tier * 1.6
			pe.Lifetime = NumberRange.new(0.8, 1.4)
			pe.Speed = NumberRange.new(1, 3)
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2 * grow),
				NumberSequenceKeypoint.new(0.3, 0.7 * grow),
				NumberSequenceKeypoint.new(1, 0),
			})
			pe.Parent = attachment(0)
		end
	end
	local c = equippedDef(data, "trail")
	if not c.colors and not c.rainbow then
		return
	end
	local a0, a1 = attachment(0.9), attachment(-0.9)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = colorSeq(c)
	trail.Lifetime = 0.6
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	local tex = textureOf(c.texture)
	if tex then
		-- 무늬 꼬리: 모양이 줄지어 찍힘 (가로 1.8칸마다 하나)
		trail.Texture = tex
		trail.TextureMode = Enum.TextureMode.Static
		trail.TextureLength = 1.8
		trail.Lifetime = 0.9
		trail.LightEmission = 0.3
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0.6)
	end
	trail.Parent = a0
end

-- 배트 스킨: 몸통(테이퍼·배럴) 색·재질 + 띠 색 + 휘두르기 궤적 색. 가방·손·StarterGear(리스폰 복사본) 모두
local BAT_BODY = { "Taper1", "Taper2", "Taper3", "BarrelBody" }
local BAT_PIECES = { "Knob", "GripTape", "Taper1", "Taper2", "Taper3", "BarrelBody", "Band", "EndCap" }
function Collection.applyBat(player: Player, data: { [string]: any })
	local c = equippedDef(data, "bat")
	local body = c.color or Color3.fromRGB(232, 236, 244)
	local function skin(tool: Instance)
		for i, name in BAT_BODY do
			local p = tool:FindFirstChild(name) :: BasePart?
			if p then
				p.Color = if c.rainbow then Color3.fromHSV((i - 1) / #BAT_BODY * 0.8, 0.65, 1) else body
				p.Material = c.material or Enum.Material.Metal
				p.Reflectance = if p.Material == Enum.Material.Metal then 0.25 else 0
			end
		end
		local band = tool:FindFirstChild("Band") :: BasePart?
		if band then
			band.Color = c.band or Color3.fromRGB(230, 60, 60)
		end
		local trail = tool:FindFirstChild("SwingTrail", true) :: Trail?
		if trail then
			trail.Color = if c.rainbow
				then colorSeq(c)
				else ColorSequence.new(Color3.new(1, 1, 1), body:Lerp(Color3.new(1, 1, 1), 0.2))
		end
	end
	-- 메시 배트: 원기둥 조각을 숨기고 메시 하나를 손잡이에 붙인다 (판정은 그대로 서버 범위)
	local function meshSkin(tool: Instance)
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		local old = tool:FindFirstChild("SkinMesh")
		if old then
			old:Destroy()
		end
		for _, name in BAT_PIECES do
			local p = tool:FindFirstChild(name) :: BasePart?
			if p then
				p.Transparency = if c.mesh then 1 else 0
			end
		end
		local m = c.mesh
		if not m or not handle then
			return
		end
		local longest = math.max(m.size.X, m.size.Y, m.size.Z)
		local scale = (m.len or 5.2) / longest
		-- 가장 긴 축 → 손잡이 방향(Y)
		local axis = if m.size.X == longest
			then CFrame.Angles(0, 0, math.rad(90))
			elseif m.size.Z == longest then CFrame.Angles(math.rad(90), 0, 0)
			else CFrame.new()
		local flip = if m.flip then CFrame.Angles(math.rad(180), 0, 0) else CFrame.new()
		local p = Instance.new("Part")
		p.Name = "SkinMesh"
		p.Size = Vector3.new(1, 1, 1)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = handle.CFrame * CFrame.new(0, 1.35, 0) * flip * axis -- 1.35 = 배트 길이 가운데 (-1.25~3.95)
		local sm = Instance.new("SpecialMesh")
		sm.MeshType = Enum.MeshType.FileMesh
		sm.MeshId = `rbxassetid://{m.id}`
		sm.TextureId = if m.tex then `rbxassetid://{m.tex}` else ""
		sm.Scale = Vector3.new(scale, scale, scale)
		sm.Parent = p
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		p.Parent = tool
	end
	local holders: { Instance } = {}
	for _, h in
		{
			player:FindFirstChildOfClass("Backpack") :: Instance?,
			player.Character,
			player:FindFirstChild("StarterGear"),
		}
	do
		if h then
			table.insert(holders, h)
		end
	end
	for _, holder in holders do
		local bat = holder:FindFirstChild("Bat")
		if bat and bat:IsA("Tool") then
			skin(bat)
			meshSkin(bat)
		end
	end
end

-- 트레이 바닥·드로퍼 재질
function Collection.applyPlot(model: Model, data: { [string]: any }?)
	local tray = if data then equippedDef(data, "tray") else Config.defaultCosmetic("tray")
	local dropper = if data then equippedDef(data, "dropper") else Config.defaultCosmetic("dropper")
	local floor = model:FindFirstChild("TrayFloor") :: BasePart?
	if floor then
		floor.Color = tray.color or floor.Color
		floor.Material = tray.material or Enum.Material.SmoothPlastic
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Dropper") then
			d.Material = dropper.material or Enum.Material.Metal
		end
	end
	-- 섬 바닥 (2026-10-19)
	local island = if data then equippedDef(data, "island") else Config.defaultCosmetic("island")
	local platform = model:FindFirstChild("Platform") :: BasePart?
	if platform then
		platform.Color = island.color or Color3.fromRGB(110, 170, 95)
		platform.Material = island.material or Enum.Material.Grass
	end
end

function Collection.apply(player: Player, data: { [string]: any }, model: Model)
	Collection.applyPlot(model, data)
	Collection.applyTrail(player.Character, data)
	Collection.applyBat(player, data)
end

function Collection.equip(player: Player, data: { [string]: any }, model: Model, id: string): boolean
	local c = Config.cosmetic(id)
	if not c or not owns(data, c) then
		return false
	end
	-- 이미 낀 걸 다시 누르면 벗는다 (그 칸 기본값으로, 2026-10-19 장착/해제)
	local default = Config.defaultCosmetic(c.slot)
	data.cosmetics.equipped[c.slot] = if equippedDef(data, c.slot).id == id and id ~= default.id then default.id else id
	Collection.apply(player, data, model)
	return true
end

-- 젬 구매: 확정 효과(정해진 꾸미기 1개). 산 뒤 바로 장착
function Collection.buy(player: Player, data: { [string]: any }, model: Model, id: string): boolean
	local c = Config.cosmetic(id)
	if not c or not c.gems or data.cosmetics.owned[id] then
		return false
	end
	migrate(data)
	if missingTier(data, c) then
		return false -- 앞 단계부터
	end
	if not Ledger.debit(player, "gems", c.gems, "Shop", id) then
		return false
	end
	data.cosmetics.owned[id] = true
	return Collection.equip(player, data, model, id)
end

-- 상태 요약 (State 이벤트에 실림)
function Collection.snapshot(data: { [string]: any }): { [string]: any }
	local found = Collection.found(data)
	local nextIndex = data.codexMilestone + 1
	local nextMilestone = if nextIndex <= #Economy.CODEX_MILESTONES
		then { count = Economy.milestoneCount(nextIndex), gems = Economy.CODEX_MILESTONES[nextIndex].gems }
		else nil
	local gemItem = Shop.item("gems_m") :: Shop.Item
	migrate(data)
	local cosmetics = {}
	for _, c in Config.COSMETICS do
		cosmetics[c.id] = owns(data, c)
	end
	local equipped = {}
	for _, slot in Config.COSMETIC_SLOTS do
		equipped[slot] = equippedDef(data, slot).id
	end
	-- 단계식 오라: 앞 단계가 없어 아직 못 사는 것 { [id] = 막는 단계 이름 }
	local blocked = {}
	for _, c in Config.COSMETICS do
		local miss = if c.tier and not cosmetics[c.id] then missingTier(data, c) else nil
		if miss then
			blocked[c.id] = miss.name
		end
	end
	return {
		found = data.variants,
		count = found,
		total = Economy.codexTotal(),
		nextMilestone = nextMilestone,
		milestoneReady = Collection.milestoneReady(data),
		unclaimed = data.codexUnclaimed, -- { [칸 키] = 젬 }: 눌러서 받을 보상
		unlocked = cosmetics,
		blocked = blocked, -- 단계식 오라: 앞 단계를 먼저
		equipped = equipped,
		gemProduct = if gemItem.id ~= 0 then gemItem.id else nil,
		gemPack = Shop.GEMS[gemItem.key],
	}
end

return Collection
