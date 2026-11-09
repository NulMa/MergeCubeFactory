--!strict
-- 특수 큐브 꾸미기 (2026-10-20 사용자 "특수큐브가 밋밋함"):
--   NEON = 가로줄 네온 선글라스(셔터 셰이드), RAINBOW = 둘레를 도는 무지개 꼬리,
--   GALAXY = 궤도를 도는 성운, COSMIC = 더 크고 두 겹으로 도는 성운, DIVINE = 크리스탈 헤일로.
-- 입자(ParticleEmitter·Trail)는 도감 ViewportFrame에 안 그려지므로 모두 파트·메시·Decal로 만든다 → 공장·도감 같은 모양.
-- 서버 styleVariant가 attach(용접, 이름 VariantDeco), 클라 Fx가 animate(돌리기·둥실), 도감은 place(고정 사본).
-- 에셋: 크리스탈 헤일로 메시 = Creator Store 1688249565 "The Crystal Halo"(무료, 스크립트 없음, 메시 1688249536).
--   선글라스는 스토어에 쓸 만한 무료 메시가 없어(다른 게임 아이템 재업로드뿐) 파트로 만든다.
--   성운 구름은 Roblox 기본 입자 그림(rbxasset smoke)을 Decal로 쓴다 (스토어 성운 사진은 배경이 꽉 차 구름으로 못 씀).

local VariantDecor = {}

local CLOUD = "rbxasset://textures/particles/smoke_main.dds"
local HALO_MESH = "rbxassetid://1688249536"
local HALO_MESH_SIZE = 175 -- 메시 원래 지름 (MeshSize 173.8 × 50 × 174.8, Studio 측정)

-- 한 조각: 큐브 중심 기준 위치 = 기울기(X축) × 회전(Y축, phase + t·spin) × (radius, y + bob) × rot
export type Piece = {
	part: BasePart,
	tilt: number,
	spin: number,
	phase: number,
	radius: number,
	y: number,
	bob: number,
	rot: CFrame,
}

local function pose(
	tilt: number,
	spin: number,
	phase: number,
	radius: number,
	y: number,
	bob: number,
	rot: CFrame,
	t: number
)
	return CFrame.Angles(tilt, 0, 0)
		* CFrame.Angles(0, phase + t * spin, 0)
		* CFrame.new(radius, y + math.sin(t * 2 + phase) * bob, 0)
		* rot
end

function VariantDecor.pose(p: Piece, t: number): CFrame
	return pose(p.tilt, p.spin, p.phase, p.radius, p.y, p.bob, p.rot, t)
end

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = "VariantDeco"
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function piece(part: BasePart, opts: { [string]: any }): Piece
	return {
		part = part,
		tilt = opts.tilt or 0,
		spin = opts.spin or 0,
		phase = opts.phase or 0,
		radius = opts.radius or 0,
		y = opts.y or 0,
		bob = opts.bob or 0,
		rot = opts.rot or CFrame.identity,
	}
end

-- 부드러운 구름 카드 두 장을 엇갈려 (어느 쪽에서 봐도 보이게)
local function cloud(list: { Piece }, size: number, color: Color3, alpha: number, opts: { [string]: any })
	for k = 0, 1 do
		local card = newPart({
			Size = Vector3.new(size, size, 0.05),
			Transparency = 1,
			Material = Enum.Material.SmoothPlastic,
		})
		-- 면마다 두 겹 (연기 그림이 옅어서 한 겹이면 하늘에 묻힌다, Studio 2026-10-20)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Front, Enum.NormalId.Back } do
			local d = Instance.new("Decal")
			d.Texture = CLOUD
			d.Face = face
			d.Color3 = color
			d.Transparency = alpha
			d.Parent = card
		end
		local o = table.clone(opts)
		o.rot = (opts.rot or CFrame.identity) * CFrame.Angles(0, k * math.pi / 2, 0)
		table.insert(list, piece(card, o))
	end
end

-- 별 (작은 빛 구슬)
local function star(list: { Piece }, size: number, color: Color3, opts: { [string]: any })
	local p = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = color })
	table.insert(list, piece(p, opts))
end

local BUILDERS: { [string]: (s: number) -> { Piece } } = {}

-- NEON: 가로줄 셔터 셰이드. 앞면(-Z) 눈 높이, 두 알 + 다리 + 귀걸이
BUILDERS.Neon = function(s: number): { Piece }
	local list: { Piece } = {}
	local frame = Color3.fromRGB(255, 70, 200)
	local slat = Color3.fromRGB(80, 255, 230)
	local z = -s / 2 - s * 0.03
	local eyeY = s * 0.03 -- 얼굴 그림의 눈 높이
	local lensW, lensH = s * 0.42, s * 0.26
	for _, side in { -1, 1 } do
		local x = side * s * 0.21
		-- 알 뒤판 (어둡게 비침)
		table.insert(
			list,
			piece(
				newPart({
					Size = Vector3.new(lensW, lensH, s * 0.03),
					Color = Color3.fromRGB(20, 10, 30),
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.2,
				}),
				{ rot = CFrame.new(x, eyeY, z) }
			)
		)
		-- 테 (위·아래)
		for _, dy in { -1, 1 } do
			table.insert(
				list,
				piece(
					newPart({ Size = Vector3.new(lensW + s * 0.04, s * 0.035, s * 0.05), Color = frame }),
					{ rot = CFrame.new(x, eyeY + dy * (lensH / 2), z - s * 0.01) }
				)
			)
		end
		-- 가로줄 3개
		for k = 1, 3 do
			local y = eyeY + lensH / 2 - k * lensH / 4
			table.insert(
				list,
				piece(
					newPart({ Size = Vector3.new(lensW, s * 0.03, s * 0.04), Color = slat }),
					{ rot = CFrame.new(x, y, z - s * 0.02) }
				)
			)
		end
		-- 다리 (옆면을 따라 뒤로)
		table.insert(
			list,
			piece(
				newPart({ Size = Vector3.new(s * 0.03, s * 0.035, s * 0.55), Color = frame }),
				{ rot = CFrame.new(side * (s / 2 + s * 0.02), eyeY + lensH / 2 - s * 0.02, -s * 0.22) }
			)
		)
	end
	-- 코걸이
	table.insert(
		list,
		piece(
			newPart({ Size = Vector3.new(s * 0.08, s * 0.035, s * 0.05), Color = frame }),
			{ rot = CFrame.new(0, eyeY + lensH * 0.3, z - s * 0.01) }
		)
	)
	return list
end

-- RAINBOW: 둘레를 도는 무지개 꼬리 (머리는 하얗고 꼬리로 갈수록 가늘고 흐려짐)
BUILDERS.Rainbow = function(s: number): { Piece }
	local list: { Piece } = {}
	local n = 20
	local arc = math.rad(300)
	for i = 0, n - 1 do
		local a = i / (n - 1)
		local w = s * (0.26 - 0.16 * a)
		local color = if i == 0 then Color3.new(1, 1, 1) else Color3.fromHSV((a * 0.85) % 1, 0.85, 1)
		local p = newPart({
			Size = Vector3.new(w, w * 0.6, s * 0.3),
			Color = color,
			Transparency = 0.5 * a,
		})
		table.insert(
			list,
			piece(p, { tilt = math.rad(18), spin = 2.2, phase = -a * arc, radius = s * 0.9, y = s * 0.05 })
		)
	end
	return list
end

-- GALAXY: 기울어진 궤도를 도는 성운 구름 3개 + 별 5개
BUILDERS.Galaxy = function(s: number): { Piece }
	local list: { Piece } = {}
	local colors = { Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 120, 220), Color3.fromRGB(110, 160, 255) }
	for i, c in colors do
		cloud(list, s * 1.25, c, 0, {
			tilt = math.rad(22),
			spin = 0.9,
			phase = i * math.pi * 2 / 3,
			radius = s * 1.0,
			bob = s * 0.04,
		})
	end
	for i = 1, 5 do
		star(list, s * 0.09, Color3.fromRGB(255, 250, 230), {
			tilt = math.rad(22),
			spin = 0.9,
			phase = i * math.pi * 2 / 5 + 0.5,
			radius = s * 1.0,
			y = (i % 2 - 0.5) * s * 0.2,
		})
	end
	return list
end

-- COSMIC: 더 크고 두 겹(서로 반대로 기울고 반대로 도는) 성운 + 큰 별, 갤럭시보다 웅장하게
BUILDERS.Cosmic = function(s: number): { Piece }
	local list: { Piece } = {}
	local outer = { Color3.fromRGB(150, 60, 255), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 80, 200) }
	for i = 1, 5 do
		cloud(list, s * 1.7, outer[(i - 1) % #outer + 1], 0, {
			tilt = math.rad(28),
			spin = 0.6,
			phase = i * math.pi * 2 / 5,
			radius = s * 1.35,
			bob = s * 0.05,
		})
	end
	for i = 1, 3 do
		cloud(list, s * 0.9, if i == 2 then Color3.fromRGB(255, 200, 120) else Color3.fromRGB(120, 90, 255), 0.2, {
			tilt = math.rad(-35),
			spin = -1.1,
			phase = i * math.pi * 2 / 3,
			radius = s * 0.85,
		})
	end
	for i = 1, 6 do
		star(list, s * (if i % 3 == 0 then 0.16 else 0.09), Color3.fromRGB(230, 245, 255), {
			tilt = math.rad(28),
			spin = 0.6,
			phase = i * math.pi / 3 + 0.3,
			radius = s * 1.35,
			y = (i % 2 - 0.5) * s * 0.3,
		})
	end
	return list
end

-- DIVINE: 머리 위 크리스탈 헤일로 (금빛, 둥실거리며 천천히 돎)
BUILDERS.Divine = function(s: number): { Piece }
	local halo = newPart({
		Size = Vector3.new(s * 1.05, s * 0.3, s * 1.05),
		Color = Color3.fromRGB(255, 215, 90),
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = HALO_MESH
	mesh.Scale = Vector3.one * (s * 1.05 / HALO_MESH_SIZE)
	mesh.Parent = halo
	return { piece(halo, { spin = 0.7, y = s / 2 + s * 0.3, bob = s * 0.05 }) }
end

function VariantDecor.has(id: string?): boolean
	return id ~= nil and BUILDERS[id] ~= nil
end

function VariantDecor.build(id: string, s: number): { Piece }
	local b = BUILDERS[id]
	return if b then b(s) else {}
end

-- 서버: 큐브에 용접해 붙인다 (이름 VariantDeco, styleVariant가 Variant* 자식을 지울 때 함께 지워짐)
function VariantDecor.attach(cube: BasePart, id: string)
	for _, p in VariantDecor.build(id, cube.Size.X) do
		local c0 = VariantDecor.pose(p, 0)
		p.part.CFrame = cube.CFrame * c0
		local weld = Instance.new("Weld")
		weld.Part0 = cube
		weld.Part1 = p.part
		weld.C0 = c0
		if p.spin ~= 0 or p.bob ~= 0 then
			weld:SetAttribute("Tilt", p.tilt)
			weld:SetAttribute("Spin", p.spin)
			weld:SetAttribute("Phase", p.phase)
			weld:SetAttribute("Radius", p.radius)
			weld:SetAttribute("Y", p.y)
			weld:SetAttribute("Bob", p.bob)
			weld:SetAttribute("Rot", p.rot)
		end
		weld.Parent = p.part
		p.part.Parent = cube
	end
end

-- 클라: 붙은 조각을 돌린다 (Fx 변이 애니메이션 루프에서)
function VariantDecor.animate(cube: Instance, t: number)
	for _, child in cube:GetChildren() do
		if child.Name ~= "VariantDeco" then
			continue
		end
		local weld = child:FindFirstChildOfClass("Weld")
		local spin = weld and weld:GetAttribute("Spin") :: number?
		if weld and spin then
			local rot = weld:GetAttribute("Rot")
			weld.C0 = pose(
				(weld:GetAttribute("Tilt") :: number?) or 0,
				spin,
				(weld:GetAttribute("Phase") :: number?) or 0,
				(weld:GetAttribute("Radius") :: number?) or 0,
				(weld:GetAttribute("Y") :: number?) or 0,
				(weld:GetAttribute("Bob") :: number?) or 0,
				if typeof(rot) == "CFrame" then rot else CFrame.identity,
				t
			)
		end
	end
end

-- 도감: 고정 사본 (Anchored) 을 container에 놓는다. 돌릴 수 있게 조각 목록을 돌려준다
function VariantDecor.place(container: Instance, at: CFrame, id: string, s: number): { Piece }
	local list = VariantDecor.build(id, s)
	for _, p in list do
		p.part.Anchored = true
		p.part.CFrame = at * VariantDecor.pose(p, 0)
		p.part.Parent = container
	end
	return list
end

return VariantDecor
