--!strict
-- Tiny test helper for Lune specs (not a spec itself). Usage:
--   local T = require("../T")
--   T.ok("name", cond)
--   T.eq("name", got, want)
--   T.done() -- prints totals, exits 1 on failure

local process = require("@lune/process")

local T = {}

local passed, failed = 0, 0

function T.ok(name: string, cond: boolean)
	if cond then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print("FAIL  " .. name)
	end
end

function T.eq(name: string, got: any, want: any)
	if got == want then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print(`FAIL  {name}: got {tostring(got)}, want {tostring(want)}`)
	end
end

function T.near(name: string, got: number, want: number, eps: number?)
	T.ok(name .. ` ({got} ~ {want})`, math.abs(got - want) <= (eps or 1e-9))
end

function T.done()
	print(`\n{passed} passed, {failed} failed`)
	if failed > 0 then
		process.exit(1)
	end
end

return T
