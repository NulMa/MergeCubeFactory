--!strict
-- lune run tests/core/Notify.spec.luau (game 디렉터리에서)
local T = require("../T")
local N = require("../Require")("src/core/shared/NotifyRules")

local DAY = 86400
local s = {}
T.ok("not before min play", not N.allowed(s, 0, 100))
T.ok("allowed after min play", N.allowed(s, 0, 700))
N.record(s, 0)
T.ok("cooldown blocks", not N.allowed(s, DAY, 700))
T.ok("after cooldown", N.allowed(s, 3 * DAY, 700))
N.record(s, 3 * DAY)
N.record(s, 6 * DAY)
T.ok("max asks reached", not N.allowed(s, 30 * DAY, 9999))
T.ok("opted in never asks", not N.allowed({ optedIn = true }, 0, 9999))
T.ok("custom options", N.allowed({}, 0, 61, { minPlay = 60 }))
T.eq("asked counter", s.asked, 3)
T.done()
