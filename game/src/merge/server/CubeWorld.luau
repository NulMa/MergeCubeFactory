--!strict
-- 플롯별 큐브 저장소 (ECS: 엔티티 id + 컴포넌트 열, docs/27 §1.1).
-- 시스템(합치기·자석·배트·트레이 정리·훔치기)은 큐브의 Part를 직접 만지지 않고 이 API(id)만 쓴다.
-- 몸(body)은 백엔드가 맡는다: PartBackend = Roblox Part + 서버 물리 (Config.DATA_CUBES = false, 롤백용),
-- SimBackend(server/SimBackend) = TraySim 데이터 + CubeNet 복제, 파트는 클라이언트(client/CubeView)가 만든다.
-- 겉모습(크기·색·변이 장식·속성)은 shared/CubeStyle (두 백엔드 공용).

local Shared = game:GetService("ReplicatedStorage").Game
local Economy = require(Shared.Economy)
local CubeCodec = require(Shared.CubeCodec)
local CubeStyle = require(Shared.CubeStyle)
local Plots = require(script.Parent.Plots)

-- 백엔드 인터페이스: body는 백엔드가 정하는 핸들(PartBackend = Part, SimBackend = id). 위치·속도는 월드 좌표.
export type Backend = {
	create: (plot: Plots.Plot, id: number, tier: number, variant: number, position: Vector3, atMax: boolean) -> any,
	destroy: (body: any, reason: number) -> (), -- reason = CubeCodec.REASON_* (클라이언트 연출용)
	alive: (body: any) -> boolean, -- 바깥에서 지워졌거나(플롯 비움) 아직 살아 있나
	position: (body: any) -> Vector3,
	velocity: (body: any) -> Vector3,
	setVelocity: (body: any, v: Vector3) -> (), -- 깨움
	setAngular: (body: any, v: Vector3) -> (), -- SimBackend는 무시 (회전은 클라 연출)
	teleport: (body: any, cf: CFrame) -> (),
	size: (body: any) -> number, -- 한 변 길이
	restyle: (body: any, tier: number, variant: number) -> (), -- 등급 크기·색·변이 장식을 다시 입힘
	markCeiling: (body: any, atMax: boolean) -> (),
	partOf: (body: any) -> Part?, -- 백엔드 전용 우회 (SimBackend는 nil)
	release: (body: any) -> Part?, -- 몸을 월드에서 떼어 호출자에게 넘김(파괴 안 함). SimBackend는 지우고 nil
	close: () -> (), -- 플롯을 비울 때 (주인 나감)
}

local CubeWorld = {}
CubeWorld.__index = CubeWorld

export type World = typeof(setmetatable(
	{} :: {
		plot: Plots.Plot,
		backend: Backend,
		ceilingOf: () -> number,
		nextId: number,
		order: { number }, -- 살아 있는 id (만든 순서)
		bodies: { [number]: any },
		tiers: { [number]: number },
		variants: { [number]: number },
		borns: { [number]: number },
		nudges: { [number]: number },
		reveals: { [number]: number? }, -- 공개 연출 중엔 합쳐지지 않음
	},
	CubeWorld
))

-- PartBackend: 큐브 = Roblox Part (서버 물리, 네트워크 소유자 없음)
local PartBackend: Backend = {
	create = function(plot, id, tier, variant, position, atMax)
		-- 얼굴(정면·뒷면)·윗면 등급 숫자는 client/CubeLook이 붙인다
		local part = CubeStyle.part(
			tier,
			variant,
			atMax,
			CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
		)
		part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.4, 0.1)
		part:SetAttribute("CubeId", id) -- 클라이언트가 id로 찾는다 (훔치기 목록·변이 공개)
		part.Parent = plot.cubes
		part:SetNetworkOwner(nil)
		return part
	end,
	destroy = function(body, _reason)
		(body :: Part):Destroy()
	end,
	alive = function(body)
		return (body :: Part).Parent ~= nil
	end,
	position = function(body)
		return (body :: Part).Position
	end,
	velocity = function(body)
		return (body :: Part).AssemblyLinearVelocity
	end,
	setVelocity = function(body, v)
		(body :: Part).AssemblyLinearVelocity = v
	end,
	setAngular = function(body, v)
		(body :: Part).AssemblyAngularVelocity = v
	end,
	teleport = function(body, cf)
		(body :: Part).CFrame = cf
	end,
	size = function(body)
		return (body :: Part).Size.X
	end,
	restyle = function(body, tier, variant)
		CubeStyle.apply(body :: Part, tier, variant)
	end,
	markCeiling = function(body, atMax)
		CubeStyle.markCeiling(body :: Part, atMax)
	end,
	partOf = function(body)
		return body :: Part
	end,
	release = function(body)
		local part = body :: Part
		part:SetAttribute("CubeId", nil)
		return part
	end,
	close = function()
		-- 파트는 Plots.release가 Cubes 폴더째 비운다
	end,
}

-- ceilingOf: 지금 합치기 상한 등급 (Economy.tierCeiling(리버스 수)) — 상한 등급 큐브에 MAX 표시
function CubeWorld.new(plot: Plots.Plot, ceilingOf: () -> number, backend: Backend?): World
	return setmetatable({
		plot = plot,
		backend = backend or PartBackend,
		ceilingOf = ceilingOf,
		nextId = 0,
		order = {},
		bodies = {},
		tiers = {},
		variants = {},
		borns = {},
		nudges = {},
		reveals = {},
	}, CubeWorld)
end

-- 큐브 하나 만들기. variant가 없으면 일반. 투하 통계(stats.drops)는 부르는 쪽 몫
function CubeWorld.spawn(self: World, tier: number, position: Vector3, variant: number?): number
	local v = variant or Economy.NORMAL
	local atMax = tier >= self.ceilingOf()
	-- id는 16비트로 돌려 쓴다(docs/27 §1.1). 아직 쓰는 번호는 건너뜀. 계속 올라가므로 지운 번호를 곧바로 다시 쓰지 않는다
	local id = self.nextId
	repeat
		id = id % 65535 + 1
	until self.bodies[id] == nil
	self.nextId = id
	self.bodies[id] = self.backend.create(self.plot, id, tier, v, position, atMax)
	self.tiers[id] = tier
	self.variants[id] = v
	self.borns[id] = os.clock()
	self.nudges[id] = 0
	table.insert(self.order, id)
	return id
end

local function forget(self: World, id: number)
	local i = table.find(self.order, id)
	if i then
		table.remove(self.order, i)
	end
	self.bodies[id] = nil
	self.tiers[id] = nil
	self.variants[id] = nil
	self.borns[id] = nil
	self.nudges[id] = nil
	self.reveals[id] = nil
end

-- reason = CubeCodec.REASON_* (합치기·팔기·기타). 클라이언트 연출 구분용, 기본은 기타
function CubeWorld.remove(self: World, id: number, reason: number?)
	local body = self.bodies[id]
	if body == nil then
		return
	end
	forget(self, id)
	self.backend.destroy(body, reason or CubeCodec.REASON_OTHER)
end

-- 월드에서 빼되 몸은 파괴하지 않고 넘겨줌 (훔치기: PartBackend면 그 파트를 머리 위에 붙임).
-- SimBackend는 데이터만 지우고(클라이언트에 steal 사유로 알림) nil → 부르는 쪽이 들기용 파트를 새로 만든다
function CubeWorld.release(self: World, id: number): Part?
	local body = self.bodies[id]
	if body == nil then
		return nil
	end
	forget(self, id)
	return self.backend.release(body)
end

-- 플롯을 비울 때 (주인 나감). 데이터만 비우고 백엔드에 알린다(SimBackend: 모두에게 빈 목록)
function CubeWorld.close(self: World)
	for i = #self.order, 1, -1 do
		forget(self, self.order[i])
	end
	self.backend.close()
end

-- 살아 있는 id 목록(만든 순서). 읽기 전용: 도는 중에 지우려면 뒤에서부터(#ids → 1) 돌 것
function CubeWorld.ids(self: World): { number }
	return self.order
end

function CubeWorld.count(self: World): number
	return #self.order
end

-- 엔티티가 있고 몸도 살아 있나 (플롯이 비워지면 몸만 먼저 사라질 수 있다)
function CubeWorld.alive(self: World, id: number): boolean
	local body = self.bodies[id]
	return body ~= nil and self.backend.alive(body)
end

function CubeWorld.has(self: World, id: number): boolean
	return self.bodies[id] ~= nil
end

-- 컴포넌트 ---------------------------------------------------------------------

function CubeWorld.tier(self: World, id: number): number
	return self.tiers[id]
end

function CubeWorld.variant(self: World, id: number): number
	return self.variants[id]
end

-- 등급·변이를 함께 바꾸고 한 번만 다시 입힌다 (합치기). 상한 표시도 갱신
function CubeWorld.retier(self: World, id: number, tier: number, variant: number)
	self.tiers[id] = tier
	self.variants[id] = variant
	local body = self.bodies[id]
	self.backend.restyle(body, tier, variant)
	self.backend.markCeiling(body, tier >= self.ceilingOf())
end

function CubeWorld.setTier(self: World, id: number, tier: number)
	CubeWorld.retier(self, id, tier, self.variants[id])
end

function CubeWorld.setVariant(self: World, id: number, variant: number)
	CubeWorld.retier(self, id, self.tiers[id], variant)
end

-- 열(column)은 바꾸지 않고 겉모습만 변이 variant로 (공개 연출: 잠깐 일반 모습 → 공개 때 원래 변이)
function CubeWorld.look(self: World, id: number, variant: number)
	self.backend.restyle(self.bodies[id], self.tiers[id], variant)
end

function CubeWorld.born(self: World, id: number): number
	return self.borns[id]
end

function CubeWorld.setBorn(self: World, id: number, t: number)
	self.borns[id] = t
end

function CubeWorld.nudged(self: World, id: number): number
	return self.nudges[id]
end

function CubeWorld.setNudged(self: World, id: number, t: number)
	self.nudges[id] = t
end

function CubeWorld.revealUntil(self: World, id: number): number?
	return self.reveals[id]
end

function CubeWorld.setRevealUntil(self: World, id: number, t: number?)
	self.reveals[id] = t
end

-- 몸 ---------------------------------------------------------------------------

function CubeWorld.position(self: World, id: number): Vector3
	return self.backend.position(self.bodies[id])
end

function CubeWorld.velocity(self: World, id: number): Vector3
	return self.backend.velocity(self.bodies[id])
end

function CubeWorld.setVelocity(self: World, id: number, v: Vector3)
	self.backend.setVelocity(self.bodies[id], v)
end

function CubeWorld.setAngular(self: World, id: number, v: Vector3)
	self.backend.setAngular(self.bodies[id], v)
end

function CubeWorld.teleport(self: World, id: number, to: CFrame | Vector3)
	self.backend.teleport(self.bodies[id], if typeof(to) == "Vector3" then CFrame.new(to) else to)
end

-- 한 변 길이
function CubeWorld.size(self: World, id: number): number
	return self.backend.size(self.bodies[id])
end

-- center에서 radius 안(중심 기준)에 있는 id 목록
function CubeWorld.query(self: World, center: Vector3, radius: number): { number }
	local out = {}
	for _, id in self.order do
		if (self.backend.position(self.bodies[id]) - center).Magnitude <= radius then
			table.insert(out, id)
		end
	end
	return out
end

-- 백엔드 전용 우회 (PartBackend만 Part, SimBackend에선 nil). 단계 4부터 게임 코드는 쓰지 않는다
function CubeWorld.partOf(self: World, id: number): Part?
	local body = self.bodies[id]
	return if body == nil then nil else self.backend.partOf(body)
end

return CubeWorld
