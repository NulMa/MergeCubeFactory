--!strict
-- lune run tests/core/StringTable.spec.luau (game 디렉터리에서)
local T = require("../T")
local StringTable = require("../../src/core/shared/StringTable")

local S = StringTable.new({
	["a.hello"] = "HELLO {name}",
	["a.nested"] = "GOT {what}",
	["a.two"] = "{x}/{y}",
}, { name = true })

T.eq("fill", S.format("a.hello", { name = "Bob" }), "HELLO Bob")
T.eq("missing key returns key", S.format("nope", nil), "nope")
T.eq("missing arg stays", S.format("a.hello", {}), "HELLO {name}")
T.eq("two args", S.format("a.two", { x = 3, y = 10 }), "3/10")
T.eq("nested msg", S.format("a.nested", { what = S.msg("a.hello", { name = "Ann" }) }), "GOT HELLO Ann")
T.ok("name args kept", S.NAME_ARGS.name == true)
local m = S.msg("a.two", { x = 1 })
T.ok("msg shape", m.key == "a.two" and (m.args :: any).x == 1)
T.done()
