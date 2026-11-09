--!strict
-- Weighted rarity tables (docs/33). Pure, Lune-tested (tests/core/Rarity.spec).
-- Free random only: never sell rolls or luck for Robux (CLAUDE.md, docs/02 §4). Show odds on screen (docs/28 §3).
--   Rarity.pick(list, r)        weighted pick with r in [0, 1) (same rule Merge used for pets/daily/events)
--   Rarity.chance(list, entry)  probability of one entry
--   Rarity.oneIn(p)             "1 in 1,000" display string; Rarity.percent(p) "0.1%"
--   Rarity.rng(seed)            deterministic generator (same seed -> same sequence on every server)
--   Rarity.boost(list, fn)      copy with weights multiplied (weather/luck events, free and in-game only)
--   Rarity.level(p)             reveal level 0..5 for client Reveal (1 in 10 / 1K / 100K / 1M ladder)

local Rarity = {}

-- Entries are any tables with a numeric `weight` field (other fields are kept and returned as-is).
export type Weighted = { weight: number }

function Rarity.total(list: { any }): number
	local sum = 0
	for _, e in list do
		sum += e.weight
	end
	return sum
end

-- r in [0, 1) -> entry. Entries with weight 0 are never picked. Empty list -> nil.
-- x < w is checked as (x - w) < 0 in list order, matching the original Pets.roll / Daily pick exactly.
function Rarity.pick(list: { any }, r: number): any
	local x = r * Rarity.total(list)
	for _, e in list do
		x -= e.weight
		if x < 0 then
			return e
		end
	end
	return list[#list]
end

-- Weighted pick with an rng function (Rarity.rng or a wrapper around math.random / Random)
function Rarity.roll(list: { any }, rng: () -> number): any
	return Rarity.pick(list, rng())
end

function Rarity.chance(list: { any }, entry: any): number
	local total = Rarity.total(list)
	return if total > 0 then entry.weight / total else 0
end

-- Copy of the list with each weight multiplied by fn(entry). Keeps other fields (shallow copy).
function Rarity.boost(list: { any }, fn: (any) -> number): { any }
	local out = {}
	for _, e in list do
		local c = table.clone(e)
		c.weight = e.weight * math.max(0, fn(e))
		table.insert(out, c)
	end
	return out
end

-- 1234567 -> "1,234,567"
function Rarity.commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local neg = string.sub(s, 1, 1) == "-"
	if neg then
		s = string.sub(s, 2)
	end
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if neg then "-" .. out else out
end

-- p -> N in "1 in N" (rounded; N >= 1). p <= 0 -> math.huge
function Rarity.denominator(p: number): number
	if p <= 0 or p ~= p then
		return math.huge
	end
	return math.max(1, math.floor(1 / p + 0.5))
end

-- p -> "1 in 1,000,000"
function Rarity.oneIn(p: number): string
	local n = Rarity.denominator(p)
	if n == math.huge then
		return "1 in ∞"
	end
	return "1 in " .. Rarity.commas(n)
end

-- p -> "45%", "0.5%", "0.0001%" (sig significant digits, default 3; trailing zeros removed)
function Rarity.percent(p: number, sig: number?): string
	local v = p * 100
	if v <= 0 or v ~= v then
		return "0%"
	end
	local digits = sig or 3
	local decimals = math.clamp(digits - 1 - math.floor(math.log10(v)), 0, 10)
	local s = string.format("%." .. decimals .. "f", v)
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s .. "%"
end

export type Row = { entry: any, p: number, percent: string, oneIn: string }

-- Display rows for an odds panel, in list order
function Rarity.rows(list: { any }): { Row }
	local total = Rarity.total(list)
	local out = {}
	for _, e in list do
		local p = if total > 0 then e.weight / total else 0
		table.insert(out, { entry = e, p = p, percent = Rarity.percent(p), oneIn = Rarity.oneIn(p) })
	end
	return out
end

-- Deterministic generator: Park-Miller minimal standard (products stay below 2^53, exact in doubles).
-- Same seed -> same sequence in Lune, on the server and on every client. Returns r in [0, 1).
function Rarity.rng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- Mix several integers into one seed (e.g. day number + slot + game salt). Returns 0 <= seed < 2^31 - 1.
-- Every product stays below 2^53 so doubles stay exact (the old FNV-style mixer multiplied values up to 2^32 by
-- 16777619 and collapsed inputs: seed(42, id, 0, 7) == seed(42, id, 0, 8)). Values outside [0, 2^31 - 1) (UserIds,
-- negatives) are mixed as two parts (v % M, v // M); smaller values mix exactly like lava's old SpawnPlan.mix.
-- Merge Cube Factory (live) never calls this (only Rarity.pick/chance), so the 2026-10-28 change moved no live data.
local M = 2147483647
local function mixInto(h: number, v: number): number
	h = ((h + v % M) % M * 16807) % M
	return (h * 48271) % M
end
function Rarity.seed(...: number): number
	local h = 1234567
	for _, v in { ... } do
		local f = math.floor(v)
		if f >= 0 and f < M then
			h = mixInto(h, f)
		else
			h = mixInto(mixInto(h, f % M), f // M)
		end
	end
	return h
end

-- Reveal level for a probability: number of thresholds "1 in N" reached.
-- Default ladder (docs/32 §3): 1 in 1 -> 1, 1 in 10 -> 2, 1 in 1,000 -> 3, 1 in 100,000 -> 4, 1 in 1,000,000 -> 5
Rarity.LEVELS = { 1, 10, 1000, 100000, 1000000 }
function Rarity.level(p: number, ladder: { number }?): number
	local n = Rarity.denominator(p)
	local level = 0
	local steps: { number } = ladder or Rarity.LEVELS
	for _, at in steps do
		if n >= at then
			level += 1
		end
	end
	return level
end

return Rarity
