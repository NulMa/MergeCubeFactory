--!strict
-- 따라다니는 펫 (docs/24 §3): 서버는 플레이어 속성 "Pets"("id:별,id:별")만 바꾸고,
-- 모양·움직임은 클라이언트가 전부 만든다(복제 부담 없음). 모든 플레이어의 펫을 이 클라이언트에서 그린다.
-- 움직임: 스프링으로 늦게 따라오고(살짝 지나쳤다 돌아옴), 걸을 때 깡충 + 좌우 뒤뚱, 서 있을 때 둥실 + 살랑.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetLook = require(script.Parent.PetLook)
local Pets = require(ReplicatedStorage.Game.Pets)

local PetFollow = {}

-- 캐릭터 기준 자리(오른쪽 X, 위 Y, 뒤 +Z): 양옆 뒤 + 가운데 더 뒤
local SLOTS = {
	Vector3.new(3.2, 0, 2.2),
	Vector3.new(-3.2, 0, 2.2),
	Vector3.new(0, 0, 4.4),
}
local FLY: { [string]: boolean } = { ufo = true, jelly = true, ghostcat = true }
local STIFF = 26 -- 스프링 세기 (작을수록 늦게 따라옴)
local DAMP = 6.5 -- 감쇠 (작을수록 출렁임)
local FAR = 160 -- 이보다 멀면 안 움직임(숨김)
local LOD = 70 -- 남의 펫이 이보다 멀면 3프레임에 한 번만 그린다 (다인 서버 최적화)
local frame = 0

type PetState = {
	model: Model,
	root: BasePart,
	move: (CFrame) -> (),
	hidden: boolean,
	id: string,
	slot: number,
	pos: Vector3,
	vel: Vector3,
	yaw: number,
	phase: number,
	len: number, -- 높이
	fly: boolean,
}
type Owner = { key: string, pets: { PetState } }

local folder = Instance.new("Folder")
folder.Name = "LocalPets"
folder.Parent = workspace

local owners: { [Player]: Owner } = {}

local function clear(o: Owner)
	for _, p in o.pets do
		p.model:Destroy()
	end
	table.clear(o.pets)
end

local function parse(s: string): { { id: string, star: number } }
	local out = {}
	for id, star in string.gmatch(s, "([%w_]+):(%d)") do
		if Pets.get(id) and #out < #SLOTS then
			table.insert(out, { id = id, star = tonumber(star) or 1 })
		end
	end
	return out
end

local function rebuild(player: Player)
	local key = (player:GetAttribute("Pets") :: string?) or ""
	local o = owners[player]
	if not o then
		o = { key = "", pets = {} }
		owners[player] = o
	end
	if o.key == key then
		return
	end
	o.key = key
	clear(o)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if hrp then hrp.Position else Vector3.zero
	for i, e in parse(key) do
		local m = PetLook.build(e.id, e.star)
		if m and m.PrimaryPart then
			local root = m.PrimaryPart
			local len = (m:GetAttribute("Height") :: number?) or 2.4
			local at = start + Vector3.new(SLOTS[i].X, 0, SLOTS[i].Z)
			local move = PetLook.mover(m)
			move(CFrame.new(at))
			m.Parent = folder
			table.insert(o.pets, {
				model = m,
				root = root,
				move = move,
				hidden = false,
				id = e.id,
				slot = i,
				pos = at,
				vel = Vector3.zero,
				yaw = 0,
				phase = i * 1.7 + math.random() * 2,
				len = len,
				fly = FLY[e.id] == true,
			})
		end
	end
end

local function watch(player: Player)
	rebuild(player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		rebuild(player)
	end)
	player.CharacterAdded:Connect(function()
		-- 새 캐릭터 위치로 순간이동
		local o = owners[player]
		if o then
			o.key = ""
		end
		task.defer(rebuild, player)
	end)
end

local function step(dt: number)
	dt = math.min(dt, 0.1)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	frame += 1
	for player, o in owners do
		if #o.pets == 0 then
			continue
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then
			continue
		end
		local dist = (hrp.Position - camPos).Magnitude
		local far = dist > FAR
		local skipDraw = player ~= Players.LocalPlayer and dist > LOD and frame % 3 ~= 0
		local floorY = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
		local look = hrp.CFrame.LookVector
		local flatCf = CFrame.lookAt(hrp.Position, hrp.Position + Vector3.new(look.X, 0, look.Z))
		local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
		local moving = speed > 1.5
		for _, p in o.pets do
			if far then
				if not p.hidden then
					p.hidden = true
					p.move(CFrame.new(0, -500, 0))
				end
				continue
			end
			p.hidden = false
			local slot = SLOTS[p.slot]
			local target = flatCf:PointToWorldSpace(slot)
			local hover = if p.fly then 2.2 + math.sin(now * 2 + p.phase) * 0.4 else 0
			target = Vector3.new(target.X, floorY + p.len / 2 + hover, target.Z)
			-- 너무 멀어지면(순간이동·리스폰) 바로 옆으로
			if (p.pos - target).Magnitude > 60 then
				p.pos = target
				p.vel = Vector3.zero
			end
			-- 스프링: 늦게 출발 → 살짝 지나침 → 제자리
			local accel = (target - p.pos) * STIFF
			p.vel = (p.vel + accel * dt) * math.exp(-DAMP * dt)
			p.pos += p.vel * dt
			local flatVel = Vector3.new(p.vel.X, 0, p.vel.Z)
			local petMoving = flatVel.Magnitude > 1.2
			-- 방향: 움직이면 가는 쪽, 멈추면 주인이 보는 쪽 (부드럽게)
			local wantYaw = if petMoving then math.atan2(-flatVel.X, -flatVel.Z) else math.atan2(-look.X, -look.Z)
			local diff = (wantYaw - p.yaw + math.pi) % (2 * math.pi) - math.pi
			p.yaw += diff * (1 - math.exp(-8 * dt))
			-- 깡충·뒤뚱(걸을 때) / 둥실·살랑(서 있을 때)
			local t = now * (if moving then 11 else 2.4) + p.phase
			local hop = if p.fly
				then 0
				elseif moving then math.abs(math.sin(t)) * 0.55 * p.len / 2.4
				else (math.sin(t) * 0.5 + 0.5) * 0.12
			local roll = math.rad(if moving then 14 else 6) * math.sin(if moving then t else t * 0.8)
			local pitch = if moving then math.rad(-8) else math.rad(3) * math.sin(t * 0.5)
			if not skipDraw then
				p.move(
					CFrame.new(p.pos + Vector3.new(0, hop, 0))
						* CFrame.Angles(0, p.yaw, 0)
						* CFrame.Angles(pitch, 0, roll)
				)
				PetLook.animate(p.model, now)
			end
		end
	end
end

function PetFollow.start()
	for _, pl in Players:GetPlayers() do
		watch(pl)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(pl)
		local o = owners[pl]
		if o then
			clear(o)
			owners[pl] = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetFollow
