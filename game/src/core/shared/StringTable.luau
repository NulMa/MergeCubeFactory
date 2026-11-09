--!strict
-- Translation key table factory (docs/31 §2, docs/33). Pure, Lune-tested.
-- A game builds its table once: local Strings = StringTable.new(KEYS, NAME_ARGS)
--   Strings.format(key, args) -> English fallback with {name} filled
--   Strings.msg(key, args)    -> { key, args } to send from server to client (client/Loc renders it)
-- Pass the result to client Loc.init(Strings). Merge keeps its own shared/Strings with the same shape.

local StringTable = {}

export type Args = { [string]: any }
export type Msg = { key: string, args: Args? }
export type Table = {
	KEYS: { [string]: string },
	NAME_ARGS: { [string]: boolean },
	format: (key: string, args: Args?) -> string,
	msg: (key: string, args: Args?) -> Msg,
}

function StringTable.new(keys: { [string]: string }, nameArgs: { [string]: boolean }?): Table
	local t = {} :: Table
	t.KEYS = keys
	t.NAME_ARGS = nameArgs or {}

	local function fill(template: string, args: Args?): string
		return (
			string.gsub(template, "{(%w+)}", function(name: string): string
				local v = args and args[name]
				if v == nil then
					return `\{{name}\}` -- leave unknown placeholders as they are
				end
				if type(v) == "table" and type(v.key) == "string" then
					return t.format(v.key, v.args)
				end
				return tostring(v)
			end)
		)
	end

	function t.format(key: string, args: Args?): string
		local template = keys[key]
		if not template then
			return key
		end
		return fill(template, args)
	end

	function t.msg(key: string, args: Args?): Msg
		return { key = key, args = args }
	end

	return t
end

return StringTable
