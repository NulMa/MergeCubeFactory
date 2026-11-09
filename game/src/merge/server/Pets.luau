--!strict
-- 펫 뽑기·장착·합성 (docs/24). 확률·보너스 공식은 shared/Pets.
-- 저장: data.shards (조각), data.pets = { list = {{u, id, star}}, equipped = {u...}, nextUid, seen = {[id] = 최고 별}, hatched }
-- 보이는 펫: 플레이어 속성 "Pets" = "id:별,id:별" → client/PetFollow가 그린다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Pets = require(ReplicatedStorage.Game.Pets)
local Ledger = require(ServerScriptService.CoreServer.Ledger)

local PetsServer = {}

export type Owned = { u: number, id: string, star: number }

local rng = Random.new()

-- 예전 꾸미기 펫(젬·도감으로 얻은 것) → 펫 인벤토리 ★1 (한 번만)
local OLD_COSMETIC: { [string]: string } = {
	pet_cube = "cube",
	pet_duck = "duck",
	pet_chick = "chick",
	pet_frog = "frog",
	pet_jelly = "jelly",
	pet_ghostcat = "ghostcat",
	pet_ufo = "ufo",
}

local function find(data: { [string]: any }, uid: number): (Owned?, number?)
	for i, p in data.pets.list do
		if p.u == uid then
			return p, i
		end
	end
	return nil, nil
end

local function isEquipped(data: { [string]: any }, uid: number): boolean
	return table.find(data.pets.equipped, uid) ~= nil
end

local function add(data: { [string]: any }, id: string, star: number): Owned
	local pets = data.pets
	local p = { u = pets.nextUid, id = id, star = star }
	pets.nextUid += 1
	table.insert(pets.list, p)
	pets.seen[id] = math.max(pets.seen[id] or 0, star)
	return p
end

function PetsServer.ensure(data: { [string]: any })
	data.pets = data.pets or {}
	local pets = data.pets
	pets.list = pets.list or {}
	pets.equipped = pets.equipped or {}
	pets.nextUid = pets.nextUid or 1
	pets.seen = pets.seen or {}
	pets.hatched = pets.hatched or 0
	data.shards = data.shards or 0
	if not pets.migrated then
		pets.migrated = true
		local cos = data.cosmetics
		if cos then
			local equippedOld = cos.equipped and cos.equipped.pet
			for cid, pid in OLD_COSMETIC do
				local owned = cos.owned and cos.owned[cid]
				-- 도감 해금분은 owned에 없을 수 있어 장착 중이던 것도 옮긴다
				if owned or equippedOld == cid then
					local p = add(data, pid, 1)
					if equippedOld == cid and #pets.equipped < Pets.EQUIP_SLOTS then
						table.insert(pets.equipped, p.u)
					end
				end
			end
		end
	end
	-- 사라진 펫 정리
	for i = #pets.equipped, 1, -1 do
		if not find(data, pets.equipped[i]) then
			table.remove(pets.equipped, i)
		end
	end
end

function PetsServer.equippedList(data: { [string]: any }): { Owned }
	local out = {}
	for _, uid in data.pets.equipped do
		local p = find(data, uid)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- 장착한 펫 수입 보너스 합 (0.3 = +30%)
function PetsServer.bonus(data: { [string]: any }): number
	return Pets.totalBonus(PetsServer.equippedList(data) :: any)
end

function PetsServer.apply(player: Player, data: { [string]: any })
	local parts = {}
	for _, p in PetsServer.equippedList(data) do
		table.insert(parts, `{p.id}:{p.star}`)
	end
	player:SetAttribute("Pets", table.concat(parts, ","))
end

-- 큐브 합치기 → 조각
function PetsServer.onMerge(player: Player, tier: number)
	Ledger.credit(player, "shards", Pets.shardsForMerge(tier), "Gameplay", "merge_shards", false)
end

-- 알 까기: 결과 목록 또는 (nil, 이유)
function PetsServer.hatch(
	player: Player,
	data: { [string]: any },
	eggId: string,
	count: number
): ({ { u: number, id: string, star: number, new: boolean } }?, string?)
	local egg = Pets.egg(eggId)
	count = math.clamp(math.floor(count), 1, 3)
	if not egg then
		return nil, "?"
	end
	if #data.pets.list + count > Pets.INVENTORY_CAP then
		return nil, "Pet bag full! Fuse or release pets"
	end
	if not Ledger.debit(player, "shards", egg.cost * count, "Gameplay", "egg_" .. eggId) then
		return nil, "Not enough shards"
	end
	local out = {}
	for _ = 1, count do
		local id = Pets.roll(eggId, rng:NextNumber()) :: string
		local new = data.pets.seen[id] == nil
		local p = add(data, id, 1)
		-- 칸이 비어 있으면 바로 장착
		if #data.pets.equipped < Pets.EQUIP_SLOTS then
			table.insert(data.pets.equipped, p.u)
		end
		table.insert(out, { u = p.u, id = id, star = 1, new = new })
	end
	data.pets.hatched += count
	PetsServer.apply(player, data)
	return out, nil
end

-- 장착/해제 토글
function PetsServer.equip(player: Player, data: { [string]: any }, uid: number): boolean
	if not find(data, uid) then
		return false
	end
	local eq = data.pets.equipped
	local at = table.find(eq, uid)
	if at then
		table.remove(eq, at)
	elseif #eq < Pets.EQUIP_SLOTS then
		table.insert(eq, uid)
	else
		-- 칸이 다 찼으면 가장 약한 펫과 바꾼다
		local weakest, wi = nil :: Owned?, 0
		for i, u in eq do
			local p = find(data, u)
			if p and (not weakest or Pets.better(weakest :: any, p :: any)) then
				weakest, wi = p, i
			end
		end
		if wi == 0 then
			return false
		end
		eq[wi] = uid
	end
	PetsServer.apply(player, data)
	return true
end

function PetsServer.equipBest(player: Player, data: { [string]: any }): boolean
	local sorted = table.clone(data.pets.list)
	table.sort(sorted, function(a, b)
		return Pets.better(a :: any, b :: any)
	end)
	local eq = {}
	for i = 1, math.min(Pets.EQUIP_SLOTS, #sorted) do
		eq[i] = sorted[i].u
	end
	data.pets.equipped = eq
	PetsServer.apply(player, data)
	return true
end

-- 합성: 같은 펫·같은 별 3마리 → 다음 별 1마리. 고른 펫 + 나머지는 장착 안 한 것부터
function PetsServer.fuse(player: Player, data: { [string]: any }, uid: number): Owned?
	local pick = find(data, uid)
	if not pick or pick.star >= Pets.MAX_STAR then
		return nil
	end
	local group = { pick }
	local others = {}
	for _, p in data.pets.list do
		if p ~= pick and p.id == pick.id and p.star == pick.star then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		local ea, eb = isEquipped(data, a.u), isEquipped(data, b.u)
		if ea ~= eb then
			return not ea
		end
		return a.u < b.u
	end)
	for _, p in others do
		if #group >= Pets.FUSE_COUNT then
			break
		end
		table.insert(group, p)
	end
	if #group < Pets.FUSE_COUNT then
		return nil
	end
	local wasEquipped = false
	for _, p in group do
		if isEquipped(data, p.u) then
			wasEquipped = true
			table.remove(data.pets.equipped, table.find(data.pets.equipped, p.u) :: number)
		end
		local _, i = find(data, p.u)
		table.remove(data.pets.list, i :: number)
	end
	local fused = add(data, pick.id, pick.star + 1)
	if wasEquipped or #data.pets.equipped < Pets.EQUIP_SLOTS then
		table.insert(data.pets.equipped, fused.u)
	end
	PetsServer.apply(player, data)
	return fused
end

-- 놓아주기 → 조각 일부 환급
function PetsServer.release(player: Player, data: { [string]: any }, uid: number): number?
	local p, i = find(data, uid)
	if not p or not i then
		return nil
	end
	local at = table.find(data.pets.equipped, uid)
	if at then
		table.remove(data.pets.equipped, at)
	end
	table.remove(data.pets.list, i)
	local refund = Pets.releaseValue(p.id) * (3 ^ (p.star - 1))
	Ledger.credit(player, "shards", refund, "Gameplay", "pet_release", false)
	PetsServer.apply(player, data)
	return refund
end

function PetsServer.snapshot(data: { [string]: any }): { [string]: any }
	return {
		shards = data.shards or 0,
		list = data.pets.list,
		equipped = data.pets.equipped,
		seen = data.pets.seen,
		bonus = PetsServer.bonus(data),
	}
end

-- Studio 확인용: 펫 바로 지급
function PetsServer.debugGive(player: Player, data: { [string]: any }, id: string, star: number)
	if Pets.get(id) then
		local p = add(data, id, math.clamp(star, 1, Pets.MAX_STAR))
		if #data.pets.equipped < Pets.EQUIP_SLOTS then
			table.insert(data.pets.equipped, p.u)
		end
		PetsServer.apply(player, data)
	end
end

return PetsServer
