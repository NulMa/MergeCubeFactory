--!strict
-- 먼 공장 큐브 꾸밈 끄기 (2026-10-19 다인 최적화): 카메라에서 FAR 넘게 떨어진 플롯의 큐브는
-- 빛(PointLight)·입자·등급 숫자(SurfaceGui)·변이 이름표·테두리를 끈다. 8인 서버면 큐브 최대 ~900개라
-- 빛·입자·글자가 모바일 프레임을 가장 많이 먹는다. 클라이언트 전용, 서버 값은 그대로.
-- 끈 것에는 LodOff 속성을 달아, 원래 꺼져 있던 것(한 번만 터지는 입자 등)은 다시 켜지 않는다.

local CubeLod = {}

local FAR = 150 -- 플롯 받침 중심까지 (studs)
local TICK = 0.5

local function setOn(inst: Instance, on: boolean)
	if inst:IsA("PointLight") or inst:IsA("ParticleEmitter") or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
		local obj = inst :: any
		if not on and obj.Enabled then
			obj.Enabled = false
			inst:SetAttribute("LodOff", true)
		elseif on and inst:GetAttribute("LodOff") then
			obj.Enabled = true
			inst:SetAttribute("LodOff", nil)
		end
	elseif inst:IsA("SelectionBox") then
		if not on and inst.Visible then
			inst.Visible = false
			inst:SetAttribute("LodOff", true)
		elseif on and inst:GetAttribute("LodOff") then
			inst.Visible = true
			inst:SetAttribute("LodOff", nil)
		end
	end
end

local function apply(cubes: Instance, on: boolean)
	for _, d in cubes:GetDescendants() do
		setOn(d, on)
	end
end

function CubeLod.start()
	local plots = workspace:WaitForChild("Plots")
	local wasFar: { [Instance]: boolean } = {}
	task.spawn(function()
		while true do
			local cam = workspace.CurrentCamera
			if cam then
				local camPos = cam.CFrame.Position
				for _, plot in plots:GetChildren() do
					local platform = plot:FindFirstChild("Platform") :: BasePart?
					local cubes = plot:FindFirstChild("Cubes")
					if platform and cubes then
						local far = (platform.Position - camPos).Magnitude > FAR
						-- 먼 플롯은 새로 생긴 큐브도 끄도록 매번, 가까워진 플롯은 한 번만 되돌린다
						if far or wasFar[plot] then
							apply(cubes, not far)
						end
						wasFar[plot] = far
					end
				end
			end
			task.wait(TICK)
		end
	end)
end

return CubeLod
