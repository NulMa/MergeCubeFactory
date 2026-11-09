--!strict
-- Shop server engine (docs/03 §2, docs/33): developer products through core Receipts with a per-game grant table,
-- game pass ownership checked on every join (refunds are reflected), pass purchase in session.
-- No paid random: every grant must give a fixed result (CLAUDE.md).
--   Shop.init({
--     items = Catalog.ITEMS,                     -- { key, kind = "product" | "pass", id, name } (id 0 = not created yet)
--     grants = { coins_s = function(player, data) return Ledger.credit(...) end, ... },  -- products; true = granted
--     onPass = function(player, data, key, owned, bought) end,   -- optional: apply pass side effects
--     refresh = function(player) end,                            -- optional: push new state to the client
--   })
-- Pass ownership is stored in data.passes[key] = true (data.passes must exist in the data template).
-- Shop.owns(player, key) for gameplay checks; Shop.grant(player, key) runs a grant without payment (Studio debug).

local MarketplaceService = game:GetService("MarketplaceService")

local CoreServer = script.Parent
local Data = require(CoreServer.Data)
local Receipts = require(CoreServer.Receipts)

local Shop = {}

export type Item = { key: string, kind: string, id: number, name: string, [any]: any }
export type Grant = (player: Player, data: { [string]: any }) -> boolean
export type Options = {
	items: { Item },
	grants: { [string]: Grant },
	onPass: ((player: Player, data: { [string]: any }, key: string, owned: boolean, bought: boolean) -> ())?,
	refresh: ((player: Player) -> ())?,
}

local opts: Options? = nil

local function refresh(player: Player)
	local o = opts
	if o and o.refresh then
		o.refresh(player)
	end
end

local function itemByKey(key: string): Item?
	local o = opts
	if not o then
		return nil
	end
	for _, item in o.items do
		if item.key == key then
			return item
		end
	end
	return nil
end

local function setPass(player: Player, data: { [string]: any }, key: string, owned: boolean, bought: boolean)
	data.passes[key] = owned or nil
	local o = opts
	if o and o.onPass then
		o.onPass(player, data, key, owned, bought)
	end
end

local function checkPasses(player: Player, data: { [string]: any })
	local o = opts :: Options
	for _, item in o.items do
		if item.kind ~= "pass" or item.id == 0 then
			continue
		end
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.id)
		if ok then
			setPass(player, data, item.key, owns == true, false)
		end
	end
	refresh(player)
end

function Shop.owns(player: Player, key: string): boolean
	local data = Data.get(player)
	return data ~= nil and data.passes ~= nil and data.passes[key] == true
end

-- Server only: run a grant without payment (Studio debug / tests)
function Shop.grant(player: Player, key: string): boolean
	local o = opts
	local data = Data.get(player)
	local item = itemByKey(key)
	if not o or not data or not item then
		return false
	end
	if item.kind == "pass" then
		setPass(player, data, key, true, false)
		refresh(player)
		return true
	end
	local fn = o.grants[key]
	local ok = fn ~= nil and fn(player, data)
	refresh(player)
	return ok
end

function Shop.init(o: Options)
	assert(opts == nil, "Shop.init called twice")
	opts = o
	for _, item in o.items do
		local fn = o.grants[item.key]
		if item.kind == "product" and item.id ~= 0 and fn then
			Receipts.register(item.id, function(player, data)
				local ok = fn(player, data)
				refresh(player)
				return ok
			end)
		end
	end
	Data.onLoaded:Connect(function(player: Player, data)
		task.spawn(checkPasses, player, data)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought then
			return
		end
		local data = Data.get(player)
		if not data then
			return
		end
		for _, item in o.items do
			if item.kind == "pass" and item.id == passId then
				setPass(player, data, item.key, true, true)
				refresh(player)
			end
		end
	end)
end

return Shop
