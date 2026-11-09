--!strict
-- 시점 (2026-10-18 사용자 요청, 같은 날 수정)
--   * 3인칭 고정 (1인칭 없음: project.json CameraMinZoomDistance)
--   * 공장 앞 시점 비컨(Plot.ViewPad) 안쪽에 잠깐(DWELL) 서 있으면 그 공장 전체가 보이는 고정 시점으로 부드럽게 이동
--   * 비컨에서 확실히 벗어나면(EXIT_R) 캐릭터 뒤 3인칭 자리까지 부드럽게 돌아온 뒤 기본 카메라에 넘긴다
--     → 가장자리를 스치기만 해도 시점이 끌려가던 문제 (사용자 피드백) 해결: 들어갈 때·나올 때 반지름이 다르고(히스테리시스) 머무는 시간이 필요
--   * 기본 시점은 MMORPG식: 캐릭터 등 뒤 DEFAULT_ZOOM 거리, PITCH 각도로 살짝 내려다봄. 스폰 때마다 이 자리로 맞추고,
--     이동하면 카메라가 등 뒤로 따라 돈다(project.json DevComputer/TouchCameraMovementMode = Follow)
-- 기본 카메라의 가려짐 처리는 Invisicam(project.json). 흔들림·FOV(Fx)는 Camera+1에서 이 위에 얹힌다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Game.Config)

local player = Players.LocalPlayer
local CameraView = {}

local ENTER_R = Config.VIEW_PAD_RADIUS - 1.2 -- 이만큼 안쪽에 들어와야
local EXIT_R = Config.VIEW_PAD_RADIUS + 1.5 -- 이만큼 벗어나야 풀림
local DWELL = 0.3 -- 안쪽에 머무는 시간
local RETURN_TIME = 0.45 -- 돌아오는 시간
local DEFAULT_ZOOM = 12 -- 기본 카메라 거리 (project.json 줌 범위 6~40)
local PITCH = math.rad(20) -- 내려다보는 각도
local ZOOM_MIN, ZOOM_MAX = 6, 40

type Mode = "free" | "overview" | "returning"
local mode: Mode = "free"
local plotView: Model? = nil
local smooth: CFrame? = nil
local insideSince: number? = nil
local returnUntil = 0
local zoom = DEFAULT_ZOOM -- 돌아올 카메라 거리 (진입 때 기억)
local onChanged: ((string) -> ())? = nil

local function overviewCFrame(plot: Model): CFrame?
	local floor = plot:FindFirstChild("TrayFloor") :: BasePart?
	if not floor then
		return nil
	end
	local c = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
	local w = floor.Size.X
	local eye = c + Vector3.new(0, w * 1.05 + 8, w * 1.05 + 10)
	return CFrame.lookAt(eye, c + Vector3.new(0, 2, 2))
end

-- 내 캐릭터가 서 있는 비컨과 수평 거리
local function nearestPad(): (Model?, number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plots = workspace:FindFirstChild("Plots")
	if not root or not plots then
		return nil, math.huge
	end
	local best, bestD = nil, math.huge
	for _, plot in plots:GetChildren() do
		local pad = plot:FindFirstChild("ViewPad") :: BasePart?
		if pad then
			local d = root.Position - pad.Position
			local flat = Vector2.new(d.X, d.Z).Magnitude
			if d.Y > -1 and d.Y < 8 and flat < bestD then
				best, bestD = plot :: Model, flat
			end
		end
	end
	return best, bestD
end

-- 캐릭터 뒤 3인칭 자리: 지금 보는 방향 그대로, 기억한 거리만큼 뒤
local function followCFrame(look: Vector3): CFrame?
	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not head then
		return nil
	end
	local focus = head.Position
	return CFrame.lookAt(focus - look.Unit * zoom, focus)
end

-- 기본 카메라 거리를 d로 맞춘다: 최소=최대로 잠깐 묶었다가 다음 프레임에 풀기 (Roblox 카메라에 거리 설정 API가 없음)
local function setZoom(d: number)
	player.CameraMinZoomDistance = d
	player.CameraMaxZoomDistance = d
	task.defer(function()
		RunService.RenderStepped:Wait()
		player.CameraMinZoomDistance = ZOOM_MIN
		player.CameraMaxZoomDistance = ZOOM_MAX
	end)
end

-- 스폰 직후: 캐릭터 등 뒤, 기본 거리·각도
local function snapBehind()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not root or not cam or mode ~= "free" then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local dir = look * math.cos(PITCH) - Vector3.new(0, math.sin(PITCH), 0)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	cam.CameraType = Enum.CameraType.Custom
	cam.CFrame = CFrame.lookAt(focus - dir * DEFAULT_ZOOM, focus)
	setZoom(DEFAULT_ZOOM)
end

local function setMode(m: Mode)
	mode = m
	if onChanged then
		onChanged(m)
	end
end

function CameraView.isOverview(): boolean
	return mode == "overview"
end

function CameraView.start(changed: ((string) -> ())?)
	onChanged = changed
	player.CameraMode = Enum.CameraMode.Classic
	RunService:BindToRenderStep("FactoryCameraView", Enum.RenderPriority.Camera.Value, function(dt: number)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local now = os.clock()
		local plot, dist = nearestPad()

		if mode == "free" then
			if plot and dist <= ENTER_R then
				insideSince = insideSince or now
				if now - (insideSince :: number) >= DWELL then
					zoom = math.clamp((cam.CFrame.Position - cam.Focus.Position).Magnitude, ZOOM_MIN, ZOOM_MAX)
					plotView = plot
					smooth = cam.CFrame
					cam.CameraType = Enum.CameraType.Scriptable
					setMode("overview")
				end
			else
				insideSince = nil
			end
		elseif mode == "overview" then
			if not plot or plot ~= plotView or dist > EXIT_R then
				returnUntil = now + RETURN_TIME
				setMode("returning")
			end
		end

		if mode == "overview" and smooth and plotView then
			local target = overviewCFrame(plotView)
			if target then
				-- 처음엔 천천히, 가까워질수록 부드럽게 멈춤
				smooth = (smooth :: CFrame):Lerp(target, 1 - math.exp(-dt * 3.5))
				cam.CFrame = smooth :: CFrame
			end
		elseif mode == "returning" and smooth then
			local look = (smooth :: CFrame).LookVector
			-- 내려다보던 각도를 3인칭 기본 각도(약 25도)로 누그러뜨림
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			local target = followCFrame(flat * math.cos(PITCH) - Vector3.new(0, math.sin(PITCH), 0))
			if target then
				smooth = (smooth :: CFrame):Lerp(target, 1 - math.exp(-dt * 9))
				cam.CFrame = smooth :: CFrame
			end
			if now >= returnUntil then
				-- 기본 카메라는 지금 CFrame의 방향을 이어받는다
				cam.CameraType = Enum.CameraType.Custom
				smooth = nil
				plotView = nil
				insideSince = nil
				setMode("free")
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		mode = "free"
		plotView = nil
		smooth = nil
		insideSince = nil
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
		end
		-- 서버가 캐릭터를 플롯 앞으로 옮긴 뒤(task.defer + 복제 지연) 등 뒤로 맞춘다
		task.delay(0.6, snapBehind)
	end)
	if player.Character then
		task.delay(0.6, snapBehind)
	end
end

return CameraView
