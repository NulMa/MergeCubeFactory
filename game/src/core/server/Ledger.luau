--!strict
-- 재화 증감의 단일 진입점 (docs/06 §1, docs/09 §1)
-- 모든 현금·젬 변경은 여기를 거친다: 음수 잔액 금지 + AnalyticsService 경제 이벤트.
-- 초당 수입처럼 잦은 소액 증감은 analytics=false로 넘기고, 세션 종료 시 합계를 한 번에 기록한다.

local AnalyticsService = game:GetService("AnalyticsService")

local Data = require(script.Parent.Data)
local Signal = require(game:GetService("ReplicatedStorage").Core.Signal)

local Ledger = {}
Ledger.changed = Signal.new() -- (player, currency, newBalance, delta)

local pendingPassive: { [Player]: { [string]: number } } = {}

local function log(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	currency: string,
	amount: number,
	balance: number,
	txType: string,
	sku: string?
)
	-- 분석 실패가 게임을 멈추면 안 된다
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, currency, amount, balance, txType, sku)
	end)
end

-- txType: Enum.AnalyticsEconomyTransactionType 이름 (예: "Gameplay", "Shop", "IAP", "Onboarding")
function Ledger.credit(
	player: Player,
	currency: string,
	amount: number,
	txType: string,
	sku: string?,
	analytics: boolean?
): boolean
	local data = Data.get(player)
	if not data or amount <= 0 or amount ~= amount then
		return false
	end
	data[currency] = (data[currency] or 0) + amount
	if analytics == false then
		local p = pendingPassive[player] or {}
		p[currency] = (p[currency] or 0) + amount
		pendingPassive[player] = p
	else
		log(player, Enum.AnalyticsEconomyFlowType.Source, currency, amount, data[currency], txType, sku)
	end
	Ledger.changed:Fire(player, currency, data[currency], amount)
	return true
end

function Ledger.debit(player: Player, currency: string, amount: number, txType: string, sku: string?): boolean
	local data = Data.get(player)
	if not data or amount <= 0 or amount ~= amount then
		return false
	end
	local balance = data[currency] or 0
	if balance < amount then
		return false
	end
	data[currency] = balance - amount
	log(player, Enum.AnalyticsEconomyFlowType.Sink, currency, amount, data[currency], txType, sku)
	Ledger.changed:Fire(player, currency, data[currency], -amount)
	return true
end

function Ledger.balance(player: Player, currency: string): number
	local data = Data.get(player)
	return if data then data[currency] or 0 else 0
end

Data.onReleasing:Connect(function(player, data)
	local p = pendingPassive[player]
	pendingPassive[player] = nil
	if p then
		for currency, amount in p do
			log(
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				currency,
				amount,
				data[currency] or 0,
				"Gameplay",
				"passive"
			)
		end
	end
end)

return Ledger
