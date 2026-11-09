--!strict
-- 번역 키 (docs/31 §2): 숫자·이름이 바뀌는 문장은 키 + 매개변수로 그린다.
-- 자동 캡처(ATC)는 값마다 다른 문자열로 모아 할당량을 낭비하므로, 키로 그리는 라벨은 AutoLocalize를 끈다.
-- 번역은 클라우드 현지화 표(같은 키)에서 Translator:FormatByKey로. 키가 표에 없거나 번역기가 없으면 Strings의 영어 원문.
-- 고정 문장은 그대로 두면 ATC가 잡는다. 같은 라벨에 키 문장과 고정 문장을 번갈아 쓰면 고정 쪽은 Loc.plain으로.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local Loc = {}

export type Args = { [string]: any }
export type Msg = { key: string, args: Args? }
export type Text = string | Msg
-- The game's key table (e.g. Merge shared/Strings or core/shared/StringTable.new): English fallback + name args
export type Source = {
	format: (key: string, args: Args?) -> string,
	NAME_ARGS: { [string]: boolean }?,
}

-- Injected by the game with Loc.init(strings) once at boot. Until then keys render as the key itself.
local Strings: Source = {
	format = function(key: string, _args: Args?): string
		return key
	end,
}

function Loc.init(strings: Source)
	Strings = strings
end

local translator: Translator? = nil
-- 키로 그린 라벨: 번역기가 늦게 오면 다시 그린다
local bound: { [GuiObject]: Msg } = setmetatable({}, { __mode = "k" }) :: any

function Loc.format(key: string, args: Args?): string
	local t = translator
	if t then
		-- 매개변수는 모두 글자로: 숫자를 그대로 넘기면 FormatByKey가 "3.00"처럼 소수점을 붙인다 (Studio 확인).
		-- 매개변수 안의 Msg(서버 보상 글자 등)는 먼저 번역해 글자로
		local flat: Args = {}
		for k, v in (args or {}) :: Args do
			flat[k] = if Loc.isMsg(v)
				then Loc.format(v.key, v.args)
				elseif Strings.NAME_ARGS and Strings.NAME_ARGS[k] then Loc.source(tostring(v))
				else tostring(v)
		end
		local ok, text = pcall(function()
			return t:FormatByKey(key, flat)
		end)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	return Strings.format(key, args)
end

-- 고정 영어 문장을 현지화 표(원문 기준)로 번역. 매개변수로 넣을 이름·설명용 (없으면 그대로)
function Loc.source(text: string): string
	local t = translator
	if t and text ~= "" then
		local ok, out = pcall(function()
			return t:Translate(game, text)
		end)
		if ok and type(out) == "string" and out ~= "" then
			return out
		end
	end
	return text
end

function Loc.msg(key: string, args: Args?): Msg
	return { key = key, args = args }
end

function Loc.isMsg(v: any): boolean
	return type(v) == "table" and type(v.key) == "string"
end

-- 키 문장으로 그리기
function Loc.set(label: GuiObject, key: string, args: Args?)
	local l = label :: any
	l.AutoLocalize = false
	local text = Loc.format(key, args)
	if l.Text ~= text then
		l.Text = text
	end
	bound[label] = { key = key, args = args }
end

-- 번역하지 않을 글자 (숫자·기호뿐: "$1.2K", "T12", "R$ 49")
function Loc.raw(label: GuiObject, text: string)
	local l = label :: any
	bound[label] = nil
	l.AutoLocalize = false
	l.Text = text
end

-- 고정 영어 문장 (ATC가 캡처·번역)
function Loc.plain(label: GuiObject, text: string)
	local l = label :: any
	bound[label] = nil
	l.AutoLocalize = true
	l.Text = text
end

-- 자동 캡처해도 되는 영어 문장인가: 숫자가 든 글자("$1.2K", "Lv3/10")는 값마다 새 문자열이라 캡처하지 않는다
function Loc.capturable(text: string): boolean
	return string.find(text, "%d") == nil and string.find(text, "%a%a") ~= nil
end

-- 글자 또는 Msg (알림·배너·팝업처럼 둘 다 받는 곳)
function Loc.apply(label: GuiObject, v: Text)
	if Loc.isMsg(v) then
		local m = v :: Msg
		Loc.set(label, m.key, m.args)
	else
		local text = v :: string
		if Loc.capturable(text) then
			Loc.plain(label, text)
		else
			Loc.raw(label, text)
		end
	end
end

-- 글자 또는 Msg → 그릴 글자 (팝업처럼 라벨이 없는 곳)
function Loc.text(v: Text): string
	if Loc.isMsg(v) then
		local m = v :: Msg
		return Loc.format(m.key, m.args)
	end
	return v :: string
end

-- 번역기 받기 (네트워크라 비동기). 시작할 때 init.client가 짧게 기다린다
local readyEvent = Instance.new("BindableEvent")
local done = false
task.spawn(function()
	local ok, t = pcall(function()
		return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
	end)
	if not ok then
		-- 게시 안 된 Studio 파일 등: 클라우드 표 없이 게임 안 LocalizationTable만 쓰는 동기 번역기
		ok, t = pcall(function()
			return LocalizationService:GetTranslatorForPlayer(Players.LocalPlayer)
		end)
	end
	if ok then
		translator = t
		for label, m in bound do
			if label.Parent then
				(label :: any).Text = Loc.format(m.key, m.args)
			end
		end
	end
	done = true
	readyEvent:Fire()
end)

function Loc.wait(timeout: number)
	if done then
		return
	end
	task.delay(timeout, function()
		if not done then
			readyEvent:Fire()
		end
	end)
	readyEvent.Event:Wait()
end

return Loc
