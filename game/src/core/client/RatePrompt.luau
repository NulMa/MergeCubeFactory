--!strict
-- 좋아요·즐겨찾기 부탁 창 (2026-10-18 사용자 요청, docs/21)
--   * 보상 없음: 좋아요(평가)에 보상을 주는 것은 Roblox 규칙 위반으로 보는 게 개발자 포럼의 공통 의견이고,
--     좋아요·즐겨찾기 여부는 게임 안에서 확인할 수도 없다
--   * 계정당 한 번 (data.rateAsked). 접속 10분이 지난 뒤 처음 오는 기분 좋은 순간(드문 변이 공개, 기록 경신,
--     도감 마일스톤)에 배너가 끝날 때쯤 띄우고, 그런 순간이 없으면 20분에 띄운다

local Ui = require(script.Parent.Ui)

local THEME = Ui.THEME
local MIN_ONLINE = 600 -- 이 시간이 지나야 부탁한다
local FALLBACK = 1200 -- 기분 좋은 순간이 없을 때
local AFTER_MOMENT = 4.5 -- 배너가 끝날 때까지 기다림

local RatePrompt = {}

-- Texts are per game (Merge passes its own). Fixed English sentences: auto-capture translates them.
export type Options = {
	title: string?,
	body: string?,
	ok: string?,
}
local DEFAULT_TITLE = "Enjoying the game?"
local DEFAULT_BODY = "Tap 👍 Like and ⭐ Favorite on the game page!\nIt helps us add new updates."

local startedAt = os.clock()
local shown = false
local pending = false
local popup: Frame? = nil
local markRemote: RemoteFunction? = nil
local getState: (() -> { [string]: any }?)? = nil

local function alreadyAsked(): boolean
	local s = getState and getState()
	return shown or (s ~= nil and s.rateAsked == true)
end

local function show()
	if alreadyAsked() or not popup then
		return
	end
	local screen = (popup :: Frame):FindFirstAncestorOfClass("ScreenGui")
	if screen and screen:GetAttribute("InRaid") then
		return -- 레이드 중엔 묻지 않는다 (다음 기분 좋은 순간에)
	end
	shown = true
	local p = popup :: Frame
	p.Visible = true
	Ui.sound("open") -- theme sound (default: none)
	Ui.pop(p) -- theme motion.pop (default: 0.6 -> FitScale, Back 0.35s)
	-- 봤다는 사실만 저장 (다시 묻지 않기)
	task.spawn(function()
		if markRemote then
			pcall(function()
				(markRemote :: RemoteFunction):InvokeServer()
			end)
		end
	end)
end

RatePrompt.show = show -- Studio 확인용

-- 기분 좋은 순간 (init.client의 reveal·record·codex 이벤트에서 부른다)
function RatePrompt.happy()
	if pending or alreadyAsked() or os.clock() - startedAt < MIN_ONLINE then
		return
	end
	pending = true
	task.delay(AFTER_MOMENT, function()
		pending = false
		show()
	end)
end

-- remote: RemoteFunction the server uses to store data.rateAsked = true. stateFn: returns the latest state ({ rateAsked })
function RatePrompt.start(gui: ScreenGui, remote: RemoteFunction, stateFn: () -> { [string]: any }?, opts: Options?)
	local o: Options = opts or {}
	markRemote = remote
	getState = stateFn
	local p = Ui.make("Frame", {
		Size = UDim2.fromOffset(440, 250),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.panel,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { Ui.corner(16), Ui.make("UIScale", {}) }) :: Frame
	popup = p
	Ui.touchFit(gui, p)
	Ui.icon("Star", {
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.new(0.5, 0, 0, -30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 21,
		Parent = p,
	})
	Ui.title({
		-- tab 제목은 패널 위 가장자리로 올라가 위의 큰 별에 깔리므로 이 창만 ribbon (별 아래 제자리)
		Style = if Ui.tokens().shape.titleStyle == "tab" then "ribbon" else nil,
		Size = UDim2.new(1, -30, 0, 40),
		Position = UDim2.fromOffset(15, 26),
		Text = o.title or DEFAULT_TITLE,
		ZIndex = 21,
		Parent = p,
	})
	Ui.label({
		Size = UDim2.new(1, -40, 0, 84),
		Position = UDim2.fromOffset(20, 70),
		Text = o.body or DEFAULT_BODY,
		TextColor3 = THEME.ink,
		TextWrapped = true,
		ZIndex = 21,
		Parent = p,
	})
	Ui.button({
		Size = UDim2.new(1, -30, 0, 56),
		Position = UDim2.new(0, 15, 1, -71),
		Text = o.ok or "OK!",
		BackgroundColor3 = THEME.accent,
		TextColor3 = THEME.accentInk,
		ZIndex = 21,
		Parent = p,
	}, function()
		Ui.closePanel(p)
	end)
	task.delay(FALLBACK, show)
end

return RatePrompt
