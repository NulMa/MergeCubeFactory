--!strict
-- lune run tests/merge/Shop.spec.luau (game 디렉터리에서)
-- 상점 관련 Economy 규칙: Shuffle Pro 무료 충전(15분·6회), 상점 전용 꾸미기 잠금

local process = require("@lune/process")
local Economy = require("../../src/merge/shared/Economy")

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

-- 기본 규칙은 그대로
local f, at = Economy.shuffleRegen(0, 0, Economy.SHUFFLE_INTERVAL)
ok("default regen +1 per interval", f == 1 and at == Economy.SHUFFLE_INTERVAL)

-- Shuffle Pro: 15분마다, 최대 6
local PRO, CAP = 15 * 60, 6
f, at = Economy.shuffleRegen(0, 0, PRO * 2 + 10, PRO, CAP)
ok("pro regen 2 in 30 min", f == 2 and at == PRO * 2)
f = Economy.shuffleRegen(0, 0, PRO * 100, PRO, CAP)
ok("pro cap 6", f == 6)
f = Economy.shuffleRegen(5, 0, Economy.SHUFFLE_INTERVAL * 100)
ok("default cap 3 keeps paid-over values", f == 5)
local f2, at2 = Economy.shuffleRegen(6, 123, 999, PRO, CAP)
ok("pro at cap: clock resets", f2 == 6 and at2 == 999)

-- 상점 전용 꾸미기: 받기 전엔 잠김, 받으면 열림
ok("exclusive locked", not Economy.cosmeticUnlocked(nil, nil, 999, false, true))
ok("exclusive owned", Economy.cosmeticUnlocked(nil, nil, 0, true, true))
ok("default still free", Economy.cosmeticUnlocked(nil, nil, 0, false))

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
