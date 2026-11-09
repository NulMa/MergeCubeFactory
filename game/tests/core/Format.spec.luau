--!strict
-- lune run tests/core/Format.spec.luau (game 디렉터리에서)

local process = require("@lune/process")
local Format = require("../../src/core/shared/Format")

local passed, failed = 0, 0

local function eq(name: string, got: any, want: any)
	if got == want then
		passed += 1
		print("PASS  " .. name)
	else
		failed += 1
		print(`FAIL  {name}: got {got}, want {want}`)
	end
end

eq("short 0", Format.short(0), "0")
eq("short 999", Format.short(999), "999")
eq("short 1000", Format.short(1000), "1.00K")
eq("short 12345", Format.short(12345), "12.3K")
eq("short 999999 rounds up", Format.short(999999), "1.00M")
eq("short 5e9", Format.short(5e9), "5.00B")
eq("short negative", Format.short(-2500), "-2.50K")
eq("short NaN", Format.short(0 / 0), "0")
eq("short 1e33 Dc", Format.short(1e33), "1.00Dc")
eq("short 2.5e36 Ud", Format.short(2.5e36), "2.50Ud")
eq("short 4.2e40 Dd", Format.short(4.2e40), "42.0Dd")
eq("short 1e63 Vg", Format.short(1e63), "1.00Vg")
eq("short Vg rounds up past table", Format.short(999.999e63), "1.00e+66")
eq("short beyond table", Format.short(1e70), "1.00e+70")
eq("duration 12s", Format.duration(12), "12s")
eq("duration 4m09s", Format.duration(249), "4m 09s")
eq("duration 1h05m", Format.duration(3900), "1h 05m")
eq("duration negative", Format.duration(-5), "0s")

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
