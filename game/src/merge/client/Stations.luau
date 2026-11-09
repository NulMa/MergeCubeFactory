--!strict
-- 광장 발판 (server/Stations): 올라서면 해당 패널을 열고, 내려오면 닫는다.
--   boss → Upgrades BOSS SHOP, eggs → PetsUi EGGS. 레이드 중(InRaid)엔 열지 않는다.
--   발판 위에서 창을 닫았거나 부화 뒤 닫혔으면 아래 가운데 "OPEN ..." 버튼으로 다시 연다
--   (2026-10-21 리뷰: 발판은 올라설 때만 반응해서 내려섰다 다시 올라서야 했음)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Fx = require(script.Parent:WaitForChild("Fx"))
local Ui = require(game:GetService("ReplicatedStorage"):WaitForChild("CoreClient"):WaitForChild("Ui"))

local player = Players.LocalPlayer

local Stations = {}

export type Handlers = { [string]: (on: boolean) -> () }

local OPEN_TEXT = { boss = "OPEN BOSS SHOP", eggs = "OPEN PET EGGS" } :: { [string]: string }

-- panels: 발판 종류 → 그 패널 (열려 있는지 보고 다시 열기 버튼을 띄운다)
function Stations.init(gui: ScreenGui, handlers: Handlers, panels: { [string]: GuiObject })
	local inside: string? = nil
	local acc = 0
	local reopen = Ui.button({
		Name = "StationReopen",
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, 0, 1, -110), -- 아래 버튼 줄 위
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		BackgroundColor3 = Ui.THEME.good,
		TextColor3 = Ui.THEME.accentInk,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, function()
		local kind = inside
		if kind and handlers[kind] then
			Fx.sound("Pop", nil, 0.4, 1.2)
			handlers[kind](true)
		end
	end)
	Ui.touchFit(gui, reopen, 1.3)
	RunService.RenderStepped:Connect(function()
		local kind = inside
		local panel = kind and panels[kind]
		reopen.Visible = panel ~= nil and not panel.Visible and not gui:GetAttribute("InRaid")
		if kind then
			reopen.Text = OPEN_TEXT[kind] or "OPEN"
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.15 then
			return
		end
		acc = 0
		local folder = workspace:FindFirstChild("Stations")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local now: string? = nil
		if folder and root and not gui:GetAttribute("InRaid") then
			for _, m in folder:GetChildren() do
				local center = m:GetAttribute("Center")
				local radius = m:GetAttribute("Radius")
				if typeof(center) == "Vector3" and typeof(radius) == "number" then
					local off = root.Position - center
					if (off * Vector3.new(1, 0, 1)).Magnitude <= radius and off.Y > -2 and off.Y < 8 then
						now = m:GetAttribute("Kind") :: string?
						break
					end
				end
			end
		end
		if now == inside then
			return
		end
		local was = inside
		inside = now
		if was and handlers[was] then
			handlers[was](false)
		end
		if now and handlers[now] then
			Fx.sound("Pop", nil, 0.4, 1.2)
			handlers[now](true)
		end
	end)
end

return Stations
