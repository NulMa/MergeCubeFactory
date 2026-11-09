--!strict
-- 숫자 표기 (Roblox API 없음 → Lune 테스트 가능)
-- 1234 -> "1.23K", 5e9 -> "5.00B". 방치형 게임은 값이 10^30 이상으로 커지므로 접미사 표를 넉넉히 둔다.

local Format = {}

-- 10^3 단위. Dc(10^33) 다음은 Ud(10^36)·Dd(10^39)·Td(10^42)…·Nod(10^60), Vg(10^63). 40등급 사다리(docs/13 §8)에서 값은 약 10^30
local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
}

function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local exp = math.floor(math.log10(n) / 3)
	if exp >= #SUFFIXES then
		return sign .. string.format("%.2e", n)
	end
	local scaled = n / 1000 ^ exp
	-- 반올림으로 1000.00K 같은 표기가 나오지 않게 한 단계 올린다
	if scaled >= 999.995 then
		exp += 1
		scaled /= 1000
		if exp >= #SUFFIXES then
			return sign .. string.format("%.2e", n)
		end
	end
	local digits = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	return sign .. string.format("%." .. digits .. "f", scaled) .. SUFFIXES[exp + 1]
end

-- 초 → "1h 05m", "4m 09s", "12s"
function Format.duration(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	local s = sec % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

return Format
