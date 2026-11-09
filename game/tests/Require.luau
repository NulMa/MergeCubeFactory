--!nocheck
-- Lune loader for shared modules that use Roblox-style requires (docs/33 §테스트).
-- In Roblox a shared module requires core with `require(script.Parent.Parent.Core.Rarity)` and siblings with
-- `require(script.Parent.Sibling)`. Lune has no `script`, so this loader gives each module a fake `script`
-- whose Parent/child lookups map the Rojo layout back to files:
--   ReplicatedStorage.Core.X  -> src/core/shared/X.luau
--   ReplicatedStorage.Game.X  -> src/<game>/shared/X.luau   (<game> = the game folder of the first module loaded)
-- Usage (from tests/<dir>/X.spec.luau or tools/*.luau):
--   local Require = require("../Require")
--   local Pets = Require("src/merge/shared/Pets")
-- Only pure modules (no game:GetService at load time) can be loaded this way.

local realRequire = require

local cache: { [string]: any } = {}

local function proxy(path: { string }, gameName: string?)
	return setmetatable({ __path = path, __game = gameName }, {
		__index = function(_, key)
			local p = table.clone(path)
			if key == "Parent" then
				table.remove(p)
			else
				table.insert(p, key)
			end
			return proxy(p, gameName)
		end,
	})
end

-- instance path -> file path (relative to game/)
local function toFile(path: { string }, gameName: string?): string
	if path[1] ~= "ReplicatedStorage" or #path < 3 then
		error("Require: unsupported instance path " .. table.concat(path, "."))
	end
	local root
	if path[2] == "Core" then
		root = "src/core/shared"
	elseif path[2] == "Game" then
		if not gameName then
			error("Require: ReplicatedStorage.Game used outside a game module")
		end
		root = "src/" .. gameName .. "/shared"
	else
		error("Require: unknown ReplicatedStorage child " .. path[2])
	end
	local rest = {}
	for i = 3, #path do
		table.insert(rest, path[i])
	end
	return root .. "/" .. table.concat(rest, "/")
end

-- file path (relative to game/) -> instance path + game name
local function toInstance(file: string): ({ string }, string?)
	local core = string.match(file, "^src/core/shared/(.+)$")
	if core then
		local p = { "ReplicatedStorage", "Core" }
		for part in string.gmatch(core, "[^/]+") do
			table.insert(p, part)
		end
		return p, nil
	end
	local gameName, rest = string.match(file, "^src/([%w_]+)/shared/(.+)$")
	if gameName and rest then
		local p = { "ReplicatedStorage", "Game" }
		for part in string.gmatch(rest, "[^/]+") do
			table.insert(p, part)
		end
		return p, gameName
	end
	error("Require: only src/core/shared and src/<game>/shared can be loaded: " .. file)
end

local loadFile

local function shimRequire(target)
	if type(target) == "table" and rawget(target, "__path") then
		return loadFile(toFile(rawget(target, "__path"), rawget(target, "__game")), rawget(target, "__game"))
	end
	return realRequire(target)
end

function loadFile(file: string, gameName: string?)
	if cache[file] ~= nil then
		return cache[file]
	end
	local path, fileGame = toInstance(file)
	local prevScript, prevRequire = script, require
	script = proxy(path, fileGame or gameName)
	require = shimRequire
	local ok, result = pcall(realRequire, "../" .. file)
	script, require = prevScript, prevRequire
	if not ok then
		error(result, 0)
	end
	cache[file] = result
	return result
end

return function(file: string)
	return loadFile(file, nil)
end
