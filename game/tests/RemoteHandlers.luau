--!strict
-- Shared test helper: every client->server remote in src/<game>/shared/Remotes has a server handler.
-- A RemoteFunction without OnServerInvoke makes the client's InvokeServer hang forever (lantern build button,
-- 2026-10-27), and a RemoteEvent without OnServerEvent silently drops the request.
--
--   require("../RemoteHandlers")("lantern")                 -- from tests/<game>/Remotes.spec.luau
--   require("../RemoteHandlers")("merge", { minRemotes = 10 })
--
-- Client->server = the spec has `args` (Net.serve validates them) or is a RemoteFunction (kind "function").
-- Server->client-only remotes omit args (core Net convention, docs/33).
-- A handler = `<net>.on("Name"` anywhere under src/<game>/server (recursive), where <net> ends in `net`/`Net`
-- (net, ctx.net, Hub.net, Ctx.net) or is `n` (starfall Session), or is listed in opts.receivers (aura: "Link.get()").
local fs = require("@lune/fs")
local T = require("./T")
local Require = require("./Require")

export type Opts = { minRemotes: number?, receivers: { string }? }

local function readTree(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			readTree(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, fs.readFile(path))
		end
	end
end

local function handled(gameName: string, extra: { string }): { [string]: boolean }
	local sources = {}
	readTree("src/" .. gameName .. "/server", sources)
	local found: { [string]: boolean } = {}
	for _, src in sources do
		for receiver, name in string.gmatch(src, '([%w_%.%(%)]+)%.on%(%s*"([%w_]+)"') do
			local last = string.match(receiver, "([%w_]+)$") or ""
			if string.lower(last) == "net" or last == "n" or table.find(extra, receiver) then
				found[name] = true
			end
		end
	end
	return found
end

return function(gameName: string, opts: Opts?)
	local remotes = Require(`src/{gameName}/shared/Remotes`) :: { [string]: any }
	local found = handled(gameName, if opts and opts.receivers then opts.receivers else {})
	local names = {}
	for name, spec in remotes do
		if type(spec) == "table" and (spec.args ~= nil or spec.kind == "function") then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		T.ok(`{gameName} handler for {name}`, found[name] == true)
	end
	local min = if opts and opts.minRemotes then opts.minRemotes else 1
	T.ok(`{gameName} client->server remotes found ({#names} >= {min})`, #names >= min)
	return names
end
