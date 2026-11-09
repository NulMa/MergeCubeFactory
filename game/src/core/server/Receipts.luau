--!strict
-- 개발자 상품 결제 처리 (docs/02 §4-6, docs/06 §4)
-- 규칙: 데이터 로드 전이면 NotProcessedYet → Roblox가 다음 접속 때 다시 호출한다.
--       영수증 id를 먼저 기록하고 보상을 준다. 같은 id가 다시 오면 보상 없이 PurchaseGranted.
-- 사용: Receipts.register(productId, function(player, data) ... return true end)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Data = require(script.Parent.Data)

local Receipts = {}

local MAX_REMEMBERED = 100
local SAVE_TIMEOUT = 15
local handlers: { [number]: (player: Player, data: { [string]: any }) -> boolean } = {}

function Receipts.register(productId: number, handler: (Player, { [string]: any }) -> boolean)
	handlers[productId] = handler
end

local function process(info): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local data = player and Data.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.receipts = data.receipts or {}
	local list: { string } = data.receipts
	if table.find(list, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local handler = handlers[info.ProductId]
	if not handler then
		warn(`[Receipts] no handler for product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player, data)
	if not ok or granted ~= true then
		warn(`[Receipts] handler failed for {info.ProductId}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(list, info.PurchaseId)
	while #list > MAX_REMEMBERED do
		table.remove(list, 1)
	end
	-- 저장이 끝나 영수증 id가 DataStore에 들어간 뒤에 확정한다 (2026-10-20 리뷰: 저장 전에 확정하면 그 사이 서버가 꺼질 때
	-- 돈만 나가고 아이템이 사라졌다). 시간 안에 못 하면 NotProcessedYet → Roblox가 다시 부르고, 같은 서버에선 위 중복 확인으로
	-- 다시 주지 않고 확정, 다른 서버에선 저장 안 된 상태라 새로 준다
	local saved = Data.saveAndWait(player, function(snapshot)
		return snapshot.receipts ~= nil and table.find(snapshot.receipts, info.PurchaseId) ~= nil
	end, SAVE_TIMEOUT)
	if not saved then
		warn(`[Receipts] save not confirmed for {info.PurchaseId}, will retry`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Receipts.init()
	MarketplaceService.ProcessReceipt = process
end

return Receipts
