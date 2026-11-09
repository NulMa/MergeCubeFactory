--!strict
-- 메뉴(Esc)를 열면 "나가도 공장은 돈을 번다" 알림 (2026-10-19 사용자 요청).
-- Roblox 메뉴는 게임 UI보다 위라 가릴 수 없어서, 메뉴 위에 뜨는 시스템 알림(SendNotification)을 쓴다.
-- 금액은 지금 수입 × 방치 비율 × 상한 시간 (server Factory: Economy.offlineEarnings와 같은 식)

local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Game.Economy)
local Format = require(ReplicatedStorage.Core.Format)
local AssetIds = require(ReplicatedStorage.Game.AssetIds)
local Loc = require(ReplicatedStorage.CoreClient.Loc)

local LeaveNote = {}

local COOLDOWN = 180 -- 메뉴를 자주 여닫아도 3분에 한 번

function LeaveNote.start(getIncome: () -> number)
	local last = -math.huge
	GuiService.MenuOpened:Connect(function()
		local now = os.clock()
		if now - last < COOLDOWN then
			return
		end
		last = now
		local income = getIncome()
		local hours = Economy.OFFLINE_CAP // 3600
		-- 시스템 알림은 자동 번역 대상이 아니라 직접 번역해 넣는다
		local text = if income > 0
			then Loc.format(
				"leave.cash",
				{ cash = Format.short(Economy.offlineEarnings(income, Economy.OFFLINE_CAP)), hours = hours }
			)
			else Loc.format("leave.noCash", { hours = hours })
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = Loc.source("Your factory keeps working!"),
				Text = text,
				Icon = AssetIds.Icons.Cash,
				Duration = 8,
			})
		end)
	end)
end

return LeaveNote
