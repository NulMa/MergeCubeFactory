--!strict
-- 점프 패드 (Plot.JumpPadIn / JumpPadOut, 속성 JumpPad = "in"|"out").
-- 내 캐릭터가 패드 위에 올라서면 포물선으로 발사: in → 그 트레이 안쪽, out → 그 플롯의 시점 비컨.
-- 캐릭터는 클라 소유라 속도를 클라에서 넣어야 바로 반영된다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local JumpPads = {}

local RADIUS = 2.8
local COOLDOWN = 1.2

-- p0에서 p1로, 꼭대기 apexY를 지나는 포물선. 벽(clearY) 위로 올라설 때까지는 수직으로만 오르고 그 뒤 수평 이동
-- 반환: 처음 속도(수직만), 수평 속도, 수평 시작 시각, 착지 시각
local function plan(p0: Vector3, p1: Vector3, apexY: number, clearY: number): (Vector3, Vector3, number, number)
	local g = workspace.Gravity
	local up = math.max(1, apexY - p0.Y)
	local down = math.max(1, apexY - p1.Y)
	local vy = math.sqrt(2 * g * up)
	local total = vy / g + math.sqrt(2 * down / g)
	-- y(t) = vy t - g t²/2 = clearY - p0.Y 의 첫 해
	local h = math.clamp(clearY - p0.Y, 0, up - 0.5)
	local tClear = (vy - math.sqrt(math.max(0, vy * vy - 2 * g * h))) / g
	local flat = (p1 - p0) * Vector3.new(1, 0, 1)
	return Vector3.new(0, vy, 0), flat / math.max(0.2, total - tClear), tClear, total
end

local function target(pad: BasePart, kind: string): Vector3?
	local plot = pad.Parent
	if not plot then
		return nil
	end
	if kind == "in" then
		local floor = plot:FindFirstChild("TrayFloor") :: BasePart?
		if not floor then
			return nil
		end
		local w = floor.Size.X
		return floor.Position + Vector3.new(-w * 0.2, 3.5, w * 0.2)
	end
	local view = plot:FindFirstChild("ViewPad") :: BasePart?
	return view and view.Position + Vector3.new(0, 3, 0)
end

function JumpPads.start(fx: any)
	local lastLaunch = 0
	-- 비행 중엔 수평 속도를 고정: 공중 이동 입력(조이스틱·WASD)이 궤도를 꺾지 않게
	local flight: { flat: Vector3, vy: number, t0: number, fromT: number, untilT: number }? = nil
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if flight and root then
			if now < flight.untilT then
				-- 포물선 전체를 스크립트로: 서 있던 Humanoid가 수직 속도를 깎아 벽에 걸리던 문제 (Studio 2026-10-18)
				local vy = flight.vy - workspace.Gravity * (now - flight.t0)
				local flat = if now >= flight.fromT then flight.flat else Vector3.zero
				root.AssemblyLinearVelocity = Vector3.new(flat.X, vy, flat.Z)
			else
				flight = nil
			end
		end
		if now - lastLaunch < COOLDOWN then
			return
		end
		local plots = workspace:FindFirstChild("Plots")
		if not root or not plots then
			return
		end
		for _, plot in plots:GetChildren() do
			for _, pad in plot:GetChildren() do
				local kind = pad:GetAttribute("JumpPad")
				if type(kind) ~= "string" or not pad:IsA("BasePart") then
					continue
				end
				local d = root.Position - pad.Position
				if Vector2.new(d.X, d.Z).Magnitude > RADIUS or d.Y < 0 or d.Y > 5 then
					continue
				end
				local to = target(pad, kind)
				if not to then
					continue
				end
				lastLaunch = now
				local floor = plot:FindFirstChild("TrayFloor") :: BasePart?
				local wallTop = (if floor then floor.Position.Y else root.Position.Y) + 16
				local v, flat, tClear, total = plan(root.Position, to, wallTop + 10, wallTop + 4.5)
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:ChangeState(Enum.HumanoidStateType.Freefall)
				end
				root.AssemblyLinearVelocity = v
				flight = { flat = flat, vy = v.Y, t0 = now, fromT = now + tClear, untilT = now + total - 0.05 }
				fx.sound("Whoosh", root.Position, 0.6, 0.8)
				fx.sound("Pop", root.Position, 0.5, 0.7)
				fx.burst("Puff", pad.Position, 6, 1)
				return
			end
		end
	end)
end

return JumpPads
