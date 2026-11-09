--!strict
-- lune run tests/merge/Remotes.spec.luau (from game/) — every client->server remote has a server handler (tests/RemoteHandlers)
local T = require("../T")
require("../RemoteHandlers")("merge", { minRemotes = 21 })
T.done()
