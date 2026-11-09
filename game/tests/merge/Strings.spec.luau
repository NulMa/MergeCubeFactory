--!strict
-- lune run tests/merge/Strings.spec.luau (game 디렉터리에서)
-- 번역 키 표 (shared/Strings, docs/31): 코드에서 쓰는 키는 표에 있고, 표의 키는 어딘가에서 쓰이며, 원문 채우기가 맞는지

local fs = require("@lune/fs")
local process = require("@lune/process")
local Strings = require("../../src/merge/shared/Strings")

local passed, failed = 0, 0

local function ok(name: string, cond: boolean)
	if cond then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print("FAIL  " .. name)
	end
end

-- 원문 채우기
ok("format fills named args", Strings.format("steal.button", { n = 3 }) == "STEAL x3")
ok(
	"format fills several args",
	Strings.format("upg.dropperSpeed", { i = 2, lv = 5, max = 50 }) == "DROPPER 2 SPEED  Lv5/50"
)
ok("format keeps missing args", Strings.format("steal.button", {}) == "STEAL x{n}")
ok("unknown key returns key", Strings.format("no.such", nil) == "no.such")
ok(
	"nested msg arg",
	Strings.format("daily.questDone", { text = Strings.msg("reward.gems", { n = 5 }) }) == "Quest done! +5◆"
)
ok("dollar sign kept", Strings.format("reward.cash", { cash = "1.2K" }) == "+$1.2K")

-- 코드 전체에서 키 모양 문자열("steal.button")을 모은다
local NAMESPACES: { [string]: boolean } = {}
for key in Strings.KEYS do
	NAMESPACES[string.match(key, "^(%a+)%.") :: string] = true
end

local used: { [string]: boolean } = {}
local missing: { string } = {}
local function scan(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		elseif string.match(name, "%.luau$") and name ~= "Strings.luau" then
			local src = fs.readFile(path)
			for key in string.gmatch(src, '"(%a+%.%w+)"') do
				local ns = string.match(key, "^(%a+)%.") :: string
				if NAMESPACES[ns] then
					used[key] = true
					if Strings.KEYS[key] == nil then
						table.insert(missing, `{path}: {key}`)
					end
				end
			end
		end
	end
end
scan("src/merge")

for _, m in missing do
	print("      missing key " .. m)
end
ok("every key used in code is in Strings.KEYS", #missing == 0)

local unused: { string } = {}
for key in Strings.KEYS do
	if not used[key] then
		table.insert(unused, key)
	end
end
table.sort(unused)
for _, k in unused do
	print("      unused key " .. k)
end
ok("every Strings.KEYS entry is used", #unused == 0)

-- 표 형식: 매개변수 이름은 영문자·숫자만, 빈 원문 없음, 원문 중복 없음 (CSV 원문 열이 겹치면 업로드 때 섞인다)
local badTemplate, dup = 0, 0
local seen: { [string]: string } = {}
for key, template in Strings.KEYS do
	if template == "" or string.find(template, "{[^}]*[^%w}][^}]*}") then
		badTemplate += 1
		print("      bad template " .. key)
	end
	if seen[template] then
		dup += 1
		print(`      same source {key} = {seen[template]}`)
	end
	seen[template] = key
end
ok("templates are well formed", badTemplate == 0)
ok("no duplicate source text", dup == 0)
local dupSource = 0
for _, s in Strings.SOURCES do
	if seen[s] then
		dupSource += 1
	end
	seen[s] = "SOURCES"
end
ok("SOURCES do not repeat", dupSource == 0)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
