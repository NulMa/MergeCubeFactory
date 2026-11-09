--!strict
-- lune run tests/core/ObjectiveRules.spec.luau (game 디렉터리에서)
local T = require("../T")
local R = require("../Require")("src/core/shared/ObjectiveRules")

local STEPS = {
	{ id = "plant", text = "Plant a seed", reward = { text = "+50" } },
	{ id = "harvest", text = "Harvest 3 plants", count = 3 },
	{ id = "shop", text = "Open the shop", client = true, reward = "+1 seed" },
}

local s = R.new()
T.eq("starts at step 1", s.i, 1)
T.ok("wrong id ignored", R.advance(STEPS, s, "harvest") == nil and s.i == 1)
local done = R.advance(STEPS, s, "plant")
T.eq("finishes plant", done and done.id, "plant")
T.eq("moves to harvest", s.i, 2)
T.ok("partial count", R.advance(STEPS, s, "harvest", 2) == nil and s.n == 2)
local _, _, frac = R.progress(STEPS, s)
T.near("progress fraction", frac, (1 + 2 / 3) / 3, 1e-6)
T.eq("count finishes", (R.advance(STEPS, s, "harvest", 5) or {}).id, "harvest")
T.eq("no spill into next step", s.n, 0)
T.ok("zero amount ignored", R.advance(STEPS, s, "shop", 0) == nil)
local v = R.view(STEPS, s)
T.eq("view id", v.id, "shop")
T.eq("view reward string", v.reward, "+1 seed")
T.eq("view index/total", v.index .. "/" .. v.total, "3/3")
R.advance(STEPS, s, "shop")
T.ok("all done", R.isDone(STEPS, s))
local dv = R.view(STEPS, s)
T.ok("done view", dv.done and dv.id == nil and dv.index == 3)
local d, total, f = R.progress(STEPS, s)
T.ok("done progress", d == 3 and total == 3 and f == 1)
T.ok("advance after done is nil", R.advance(STEPS, s, "shop") == nil)

-- sanitize
T.eq("sanitize nil", R.sanitize(STEPS, nil).i, 1)
T.eq("sanitize clamps high", R.sanitize(STEPS, { i = 99, n = 4 }).i, 4)
local bad = R.sanitize(STEPS, { i = 2, n = 10 })
T.eq("sanitize clamps n", bad.n, 2)
T.eq("sanitize junk", R.sanitize(STEPS, { i = "x", n = 0 / 0 }).i, 1)

-- skipTo
local k = R.new()
T.ok("skip forward", R.skipTo(STEPS, k, "shop") and k.i == 3)
T.ok("no skip backward", not R.skipTo(STEPS, k, "plant") and k.i == 3)
T.eq("need default", R.need(STEPS[1]), 1)
T.done()
