--!strict
-- 나무·바위 꾸밈 소품 (2026-10-19 "에셋 찾아서 써라, 기본 도형은 별로" → "섬까지 바꿀 필요는 없었다, 풀만 스타일이 다르다"):
-- 섬 받침(모래·흙)은 그대로 두고 나무·바위만 메시. 스타일을 맞추려고 텍스처 사실적인 풀·이끼 돌은 뺐다.
-- Creator Store 메시를 SpecialMesh로 붙여 만든다 (펫·배트와 같은 방식, 스크립트 없음, 충돌 없음).
-- 각 소품은 Studio에서 넣어 본 모델의 파트 배치를 그대로 옮긴 것: box = 모델 경계 크기,
-- parts = 메시 id·텍스처·원본 메시 크기(native)·모델 안 크기(size)·경계 중심 기준 CFrame·색.
-- 출처 (asset id, 만든 사람):
--   treeAndy   9208781518 "Tree Basic Two" (LowPolyAndy, Blender 제작)
--   treeXenon  10674424255 "Tree by XenonWorkshop" (XGraphics, Blender 제작) — 텍스처 없음 → 잎 색 바꿔 씀
--   palm       15802072942 "Low Poly Cartoon Palm Tree" (Insan3_Script3r)
--   rock       71589923760635 "Rock" stylized (CursedSorcerer58ALT) — 텍스처 없음 → 톤 바꿔 씀

local Decor = {}

type PartDef = {
	mesh: number,
	tex: number?,
	native: Vector3,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	role: string?, -- "leaf"면 색 바꾸기 대상
}
type Def = { box: Vector3, parts: { PartDef } }

local function e(x: number, y: number, z: number): CFrame
	return CFrame.fromEulerAnglesXYZ(x, y, z)
end

local DEFS: { [string]: Def } = {
	treeAndy = {
		box = Vector3.new(8.656, 16.000, 8.300),
		parts = {
			{
				mesh = 9208781302,
				tex = 9208781390,
				native = Vector3.new(27.049, 50.000, 25.940),
				size = Vector3.new(8.656, 16.000, 8.301),
				cf = CFrame.new(),
				color = Color3.fromHex("a3a2a5"),
			},
		},
	},
	treeXenon = {
		box = Vector3.new(12.885, 16.000, 8.420),
		parts = {
			{
				mesh = 8593833175,
				native = Vector3.new(13.274, 7.563, 5.538),
				size = Vector3.new(11.930, 6.797, 4.977),
				cf = CFrame.new(0, 4.602, 0) * e(0, -0.314, 0),
				color = Color3.fromHex("7f8e64"),
				role = "leaf",
			},
			{
				mesh = 8593837883,
				native = Vector3.new(9.956, 12.291, 2.276),
				size = Vector3.new(8.948, 11.046, 2.045),
				cf = CFrame.new(0.140, -2.477, 0.176) * e(0, -0.314, 0),
				color = Color3.fromHex("6c584b"),
			},
		},
	},
	palm = {
		box = Vector3.new(12.298, 16.000, 12.434),
		parts = {
			{
				mesh = 15801444514,
				tex = 15801444550,
				native = Vector3.new(29.941, 50.000, 29.851),
				size = Vector3.new(9.489, 15.844, 9.459),
				cf = e(-3.124, -0.359, -3.135),
				color = Color3.fromHex("a3a2a5"),
			},
		},
	},
	rock = {
		box = Vector3.new(4.710, 5.000, 4.777),
		parts = {
			{
				mesh = 98381838008800,
				native = Vector3.new(47.098, 50.000, 47.770),
				size = Vector3.new(4.710, 5.000, 4.777),
				cf = CFrame.new(),
				color = Color3.fromRGB(150, 150, 160),
				role = "leaf", -- 톤 바꾸기
			},
		},
	},
}

-- 소품 하나를 만든다. at = 바닥 가운데(땅에 닿는 점), height = 원하는 높이(studs), yaw = 세로축 회전.
-- color를 주면 role "leaf" 파트(잎·덤불·무채색 바위)를 그 색으로. 돌려주는 Model은 parent에 붙어 있다
function Decor.spawn(kind: string, at: Vector3, height: number, yaw: number, parent: Instance, color: Color3?): Model
	local def = DEFS[kind]
	assert(def, kind)
	local s = height / def.box.Y
	local origin = CFrame.new(at + Vector3.new(0, def.box.Y * s / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = kind
	for _, pd in def.parts do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = pd.size * s
		local rel = pd.cf
		p.CFrame = origin * (rel - rel.Position + rel.Position * s)
		p.Color = if color and pd.role == "leaf" then color else pd.color
		p.Material = Enum.Material.SmoothPlastic
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = `rbxassetid://{pd.mesh}`
		m.TextureId = if pd.tex then `rbxassetid://{pd.tex}` else ""
		-- 원본 메시 크기 × Scale = 화면 크기
		m.Scale = Vector3.new(pd.size.X / pd.native.X, pd.size.Y / pd.native.Y, pd.size.Z / pd.native.Z) * s
		m.Parent = p
		p.Parent = model
	end
	model.Parent = parent
	return model
end

return Decor
