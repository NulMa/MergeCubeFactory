--!strict
-- lune run tests/core/Ranking.spec.luau (game 디렉터리에서)
-- 랭킹 점수 인코딩: OrderedDataStore는 정수만 받으므로 큰 수입은 log10 × 1e6으로 저장한다.

local process = require("@lune/process")
local Ranking = require("../../src/core/shared/Ranking")

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

ok("encode 0", Ranking.encode(0, true) == 0)
ok("encode NaN", Ranking.encode(0 / 0, true) == 0)
ok("encode negative", Ranking.encode(-5, false) == 0)
ok("log keeps order", Ranking.encode(1.5e30, true) > Ranking.encode(1.4e30, true))
ok("log is integer", Ranking.encode(1.23e45, true) % 1 == 0)
local back = Ranking.decode(Ranking.encode(1.23e45, true), true)
ok("log roundtrip", math.abs(back / 1.23e45 - 1) < 1e-5)
ok("plain floor", Ranking.encode(42.9, false) == 42)
ok("plain decode", Ranking.decode(42, false) == 42)
ok("decode 0", Ranking.decode(0, true) == 0)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
