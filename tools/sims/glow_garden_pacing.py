"""Glow Garden pacing / economy simulation (docs/34_GLOW_GARDEN.md).

Deterministic (seeded) model of the garden economy. One simulated player archetype plays the
same greedy way a human would: harvest ripe plants, replant the best seed that fits the time until
the next visit, buy plots/fertilizer, rebirth when allowed.

Rules mirrored from the GDD:
  - timers run on wall clock; ripe plants wait (no spoil, no offline income beyond that)
  - weather mutation rolls only happen while the owner is online (15 s ticks)
  - seed shop restocks every 300 s; per-player stock; Rare+ rarity stays 3 slots (see STOCK_HOLD)
  - mutations stack additively: 1 + sum(mult - 1), max 3 mutations
  - rebirth: coin cost AND highest rarity harvested ever >= requirement

Usage: python -I tools/sims/glow_garden_pacing.py [--days 28] [--seeds 20] [--pass2x] [--auto]
                                                  [--mc] [--json]
"""

import argparse
import math
import random
import statistics
import sys

DAY = 86400
RESTOCK = 300
WEATHER_SLOT = 600
WEATHER_LEN = 240
TICK = 15
STEP = 10  # player reaction granularity while online (s)
MAX_MUT = 3
STOCK_HOLD = 2  # slots a Legendary/Mythic stays in the shop

RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]

# name, rarity, seed cost, grow seconds, base sell
PLANTS = [
    ("Sparkle Sprout", 0, 5, 12, 9),
    ("Lumen Moss", 0, 30, 45, 58),
    ("Dew Daisy", 0, 120, 90, 235),
    ("Pebble Pansy", 0, 400, 180, 800),
    ("Glow Tulip", 1, 1200, 240, 2500),
    ("Candle Fern", 1, 3500, 360, 7300),
    ("Mist Lily", 1, 9000, 480, 19000),
    ("Ember Clover", 1, 22000, 600, 47000),
    ("Moonbell", 2, 55000, 720, 118000),
    ("Frost Orchid", 2, 130000, 900, 280000),
    ("Prism Poppy", 2, 300000, 1080, 650000),
    ("Amber Lotus", 2, 650000, 1200, 1400000),
    ("Aurora Rose", 3, 1500000, 1320, 3500000),
    ("Starfruit Vine", 3, 3500000, 1500, 8200000),
    ("Opal Sunflower", 3, 8000000, 1680, 19000000),
    ("Nebula Bloom", 4, 20000000, 1800, 50000000),
    ("Solar Hibiscus", 4, 45000000, 1800, 115000000),
    ("Celestial Lotus", 5, 120000000, 1800, 330000000),
    ("Heartglass Rose", 5, 300000000, 1800, 850000000),
]

# rarity -> (appear chance per restock, stock min, stock max)
APPEAR = {0: (1.0, 6, 12), 1: (0.70, 4, 8), 2: (0.40, 2, 4), 3: (0.18, 1, 2), 4: (0.06, 1, 1), 5: (0.005, 1, 1)}
MYTHIC_PITY_SLOTS = 288  # one guaranteed Mythic slot per 24 h (hash picks the slot)

# name, mult, odds "1 in N" per 15 s tick, weather
MUTATIONS = {
    "Glowing": (3, 25, None),  # rolled on harvest, any weather
    "Dewy": (1.5, 12, "Drizzle"),
    "Frosted": (4, 30, "Frost"),
    "Starlit": (8, 60, "Meteor"),
    "Aurora": (12, 90, "Aurora"),
    "Prismatic": (30, 200, "Prismatic"),
}
WEATHER_P = [("Clear", 0.50), ("Drizzle", 0.24), ("Frost", 0.12), ("Meteor", 0.07), ("Aurora", 0.05), ("Prismatic", 0.02)]

RARITY_LEVEL = {0: 1, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5}
MUT_LEVEL = {"Glowing": 1, "Dewy": 1, "Frosted": 2, "Starlit": 3, "Aurora": 4, "Prismatic": 5}
SIZE_LEVEL = {"Big": 2, "Giant": 3, "Titan": 5}

# size: (name, mult, odds 1 in N) checked rarest first; else Normal 0.7-1.3
SIZES = [("Titan", 8.0, 3000), ("Giant", 3.0, 120), ("Big", 1.7, 8)]

ARCHETYPES = {  # (start hour UTC, minutes)
    "casual": [(19, 12)],
    "regular": [(8, 15), (19, 15)],
    "engaged": [(8, 20), (13, 20), (20, 20)],
    "hardcore": [(8, 30), (12, 30), (17, 30), (21, 30)],
}

PLOT_START = 6
PLOT_COST0, PLOT_GROWTH = 150, 1.55
FERT_COST0, FERT_GROWTH, FERT_STEP, FERT_MAX = 500, 2.2, 0.04, 10
WATER_FACTOR = 0.92  # active watering shortens grow time of plants tended while online
REBIRTH_COST0, REBIRTH_GROWTH = 1_500_000, 7.0
REBIRTH_MULT = 0.30  # +30% sell per rebirth (additive)
REBIRTH_REQ = [2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5, 5]  # highest rarity index harvested for rebirth r
REBIRTH_MAX = 12
# pity / catch-up (docs/34 dopamine design): deterministic, free, never random
GIFT_ON_REBIRTH = {2: 12, 3: 15, 4: 17}  # reaching rebirth N grants one free seed (plant index): Aurora Rose, Nebula Bloom, Celestial Lotus
DAILY_BONUS = 0.5  # first session of each day: +50% sell for DAILY_BONUS_SEC
DAILY_BONUS_SEC = 600


def plot_cap(r):
    return min(18 + 2 * r, 30)


def plot_start(r):
    return PLOT_START + min(r, 6)


def plot_cost(k):  # cost to go from k plots to k+1
    return PLOT_COST0 * PLOT_GROWTH ** (k - PLOT_START)


def fert_cost(l):
    return FERT_COST0 * FERT_GROWTH ** l


def rebirth_cost(r):
    return REBIRTH_COST0 * REBIRTH_GROWTH ** r


def slot_rng(tag, slot):
    return random.Random(f"{tag}:{slot}")


_weather_cache = {}


def weather_at(t):
    slot = t // WEATHER_SLOT
    if t % WEATHER_SLOT >= WEATHER_LEN:
        return "Clear"
    w = _weather_cache.get(slot)
    if w is None:
        x = slot_rng("w", slot).random()
        acc = 0.0
        w = "Clear"
        for name, p in WEATHER_P:
            acc += p
            if x <= acc:
                w = name
                break
        _weather_cache[slot] = w
    return w


_stock_cache = {}


def stock_at(slot):
    """Deterministic per-slot list of (plant idx, qty). Legendary/Mythic persist STOCK_HOLD slots."""
    s = _stock_cache.get(slot)
    if s is not None:
        return s
    out = {}
    for src in range(slot - STOCK_HOLD + 1, slot + 1):
        rng = slot_rng("s", src)
        pity = (src % MYTHIC_PITY_SLOTS) == (hash_int(src // MYTHIC_PITY_SLOTS) % MYTHIC_PITY_SLOTS)
        for rar in range(6):
            held = rar >= 4
            if not held and src != slot:
                continue
            p, lo, hi = APPEAR[rar]
            ok = rng.random() < p or (rar == 5 and pity)
            idxs = [i for i, pl in enumerate(PLANTS) if pl[1] == rar]
            pick = rng.sample(idxs, k=min(len(idxs), 2 if rar < 3 else 1)) if rar < 3 else [rng.choice(idxs)]
            qty = rng.randint(lo, hi)
            if ok:
                if rar < 3:
                    for i in idxs:
                        out[i] = max(out.get(i, 0), qty if i in pick else max(1, qty // 2))
                else:
                    out[pick[0]] = max(out.get(pick[0], 0), qty)
    _stock_cache[slot] = out
    return out


def hash_int(x):
    return random.Random(f"h:{x}").randrange(10**9)


class Player:
    def __init__(self, arch, rng, opts):
        self.arch, self.rng, self.o = arch, rng, opts
        self.coins = 10.0
        self.r = 0
        self.plots = [None] * PLOT_START
        self.fert = 0
        self.best = -1
        self.bought = {}  # slot -> {idx: qty bought}
        self.online_s = 0
        self.log = {}
        self.sold = 0.0
        self.reveals = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
        self.big_hits = {"mut": 0, "titan": 0, "giant": 0, "prismatic": 0, "aurora": 0, "starlit": 0, "glowing": 0}
        self.rebirth_t = []
        self.income_mult = 1.0 + (1.0 if opts.pass2x else 0.0) + (0.25 if opts.vip else 0.0)  # additive
        self.free_start_done = False
        self.gifts = []
        self.bonus_until = -1

    def mark(self, key, t):
        if key not in self.log:
            self.log[key] = (self.online_s, t / DAY)

    def sell_value(self, pl, mutlist, wmult):
        base = PLANTS[pl][4]
        m = 1.0 + sum(MUTATIONS[x][0] - 1 for x in mutlist)
        return base * wmult * m * (1 + REBIRTH_MULT * self.r) * self.income_mult

    def grow_time(self, pl):
        return PLANTS[pl][3] * (1 - FERT_STEP * self.fert) * WATER_FACTOR

    def harvest(self, i, t):
        pl, ready, muts = self.plots[i]
        self.plots[i] = None
        rng = self.rng
        wm = rng.uniform(0.7, 1.3)
        size_level = 1
        for nm, mult, n in SIZES:
            if rng.randrange(n) == 0:
                wm = mult
                size_level = SIZE_LEVEL[nm]
                if nm == "Titan":
                    self.big_hits["titan"] += 1
                if nm == "Giant":
                    self.big_hits["giant"] += 1
                break
        if "Glowing" not in muts and len(muts) < MAX_MUT and rng.randrange(MUTATIONS["Glowing"][1]) == 0:
            muts = muts + ["Glowing"]
            self.big_hits["glowing"] += 1
        v = self.sell_value(pl, muts, wm)
        if self.o.pity and t < self.bonus_until:
            v *= 1 + DAILY_BONUS
        self.coins += v
        self.sold += v
        rar = PLANTS[pl][1]
        if rar > self.best:
            self.best = rar
            self.mark("first_" + RARITIES[rar], t)
        for nm in muts:
            if nm in ("Prismatic", "Aurora", "Starlit"):
                self.big_hits[nm.lower()] += 1
        lvl = RARITY_LEVEL[rar]
        for nm in muts:
            lvl = max(lvl, MUT_LEVEL[nm])
        lvl = max(lvl, size_level)
        if len(muts) >= 3:
            lvl = max(lvl, 5)
        self.reveals[lvl] += 1

    def mutate_tick(self, w, mult_odds=1.0):
        if w == "Clear":
            return
        for i, p in enumerate(self.plots):
            if p is None:
                continue
            muts = p[2]
            if len(muts) >= MAX_MUT:
                continue
            for nm, (m, n, wt) in MUTATIONS.items():
                if wt == w and nm not in muts and self.rng.random() < mult_odds / n:
                    muts.append(nm)
                    break

    def choose_seed(self, t, session_end, next_start, slot):
        st = stock_at(slot)
        bought = self.bought.setdefault(slot, {})
        best, best_score = None, 0.0
        remaining = session_end - t
        for idx, qty in st.items():
            if qty - bought.get(idx, 0) <= 0:
                continue
            _, rar, cost, g, sell = PLANTS[idx]
            if cost > self.coins:
                continue
            gt = self.grow_time(idx)
            wait = gt if gt <= remaining else (next_start - t)
            net = sell * (1 + REBIRTH_MULT * self.r) * self.income_mult - cost
            score = net / max(wait, STEP)
            if score > best_score:
                best, best_score = idx, score
        return best

    def run(self, days):
        sess = ARCHETYPES[self.arch]
        # pre-ripe starter plant: first harvest within 10 s (tutorial)
        self.plots[0] = (0, 0, [])
        starts = []
        for d in range(days):
            for h, m in sess:
                starts.append((d * DAY + h * 3600, m * 60))
        starts.sort()
        for si, (s, dur) in enumerate(starts):
            nxt = starts[si + 1][0] if si + 1 < len(starts) else s + dur + 8 * 3600
            t, end = s, s + dur
            if self.o.pity and (si == 0 or starts[si - 1][0] // DAY != s // DAY):
                self.bonus_until = s + DAILY_BONUS_SEC
            self.session(t, end, nxt)
            if si == 0 and self.r == 0:
                pass
        self.mark("end", days * DAY)

    def session(self, t, end, nxt):
        next_tick = t
        while t < end:
            slot = t // RESTOCK
            w = weather_at(t)
            if t >= next_tick:
                self.mutate_tick(w)
                next_tick = t + TICK
            # harvest ripe
            for i, p in enumerate(self.plots):
                if p is not None and p[1] <= t:
                    self.harvest(i, t)
            # replant
            for i, p in enumerate(self.plots):
                if p is None and self.gifts:
                    idx = self.gifts.pop(0)
                    self.plots[i] = (idx, t + self.grow_time(idx), [])
                    continue
                if p is None:
                    idx = self.choose_seed(t, end, nxt, slot)
                    if idx is None:
                        continue
                    self.coins -= PLANTS[idx][2]
                    self.bought.setdefault(slot, {})[idx] = self.bought.setdefault(slot, {}).get(idx, 0) + 1
                    self.plots[i] = (idx, t + self.grow_time(idx), [])
            # upgrades only when all plots busy
            if all(p is not None for p in self.plots):
                self.buy_upgrades(t)
            self.try_rebirth(t)
            t += STEP
            self.online_s += STEP

    def buy_upgrades(self, t):
        for _ in range(8):
            opts = []
            n = len(self.plots)
            if n < plot_cap(self.r):
                opts.append((plot_cost(n), "plot"))
            if self.fert < FERT_MAX:
                opts.append((fert_cost(self.fert), "fert"))
            if not opts:
                return
            c, kind = min(opts)
            if self.coins < c:
                return
            self.coins -= c
            if kind == "plot":
                self.plots.append(None)
                self.mark(f"plots_{len(self.plots)}", t)
            else:
                self.fert += 1
                self.mark(f"fert_{self.fert}", t)
            if kind == "plot":
                return  # new empty plot must be planted first

    def try_rebirth(self, t):
        if self.r >= REBIRTH_MAX:
            return
        if self.coins >= rebirth_cost(self.r) and self.best >= REBIRTH_REQ[self.r]:
            self.r += 1
            if self.o.pity and self.r in GIFT_ON_REBIRTH:
                self.gifts.append(GIFT_ON_REBIRTH[self.r])
            self.mark(f"rebirth_{self.r}", t)
            self.coins = 10.0
            self.fert = 0
            self.plots = [None] * plot_start(self.r)
            self.plots[0] = None


def run_one(arch, seed, days, opts):
    p = Player(arch, random.Random(seed), opts)
    p.run(days)
    return p


def fmt_t(v):
    if v is None:
        return "-"
    mins, day = v
    return f"{mins/60:.0f}m (D{day:.1f})" if mins < 36000 else f"{mins/3600:.1f}h (D{day:.1f})"


def median_log(players, key):
    vals = [p.log[key] for p in players if key in p.log]
    if len(vals) < len(players) / 2:
        return None
    return (statistics.median(v[0] for v in vals), statistics.median(v[1] for v in vals))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=28)
    ap.add_argument("--seeds", type=int, default=12)
    ap.add_argument("--pass2x", action="store_true")
    ap.add_argument("--vip", action="store_true")
    ap.add_argument("--pity", action="store_true", help="rebirth gift seeds + daily first-session bonus")
    ap.add_argument("--mc", action="store_true", help="mutation / reveal frequency tables")
    args = ap.parse_args()

    print(f"# Glow Garden pacing  days={args.days} seeds={args.seeds} pass2x={args.pass2x} vip={args.vip}")
    keys = ["plots_8", "plots_12", "plots_18", "first_Uncommon", "first_Rare", "first_Epic",
            "first_Legendary", "first_Mythic", "rebirth_1", "rebirth_2", "rebirth_3", "rebirth_5", "rebirth_8"]
    print("\n## milestones (median; online play time (day reached))")
    print("| milestone | " + " | ".join(ARCHETYPES) + " |")
    print("|---|" + "---|" * len(ARCHETYPES))
    res = {}
    for a in ARCHETYPES:
        res[a] = [run_one(a, 1000 + s, args.days, args) for s in range(args.seeds)]
    for k in keys:
        print(f"| {k} | " + " | ".join(fmt_t(median_log(res[a], k)) for a in ARCHETYPES) + " |")

    print("\n## state at day marks (median rebirth count / coins sold total)")
    print("| archetype | online min/day | rebirths end | plots end | sold total |")
    print("|---|---|---|---|---|")
    for a in ARCHETYPES:
        mins = sum(m for _, m in ARCHETYPES[a])
        rs = [p.r for p in res[a]]
        print(f"| {a} | {mins} | {statistics.median(rs):.0f} (min {min(rs)}, max {max(rs)}) | "
              f"{statistics.median(len(p.plots) for p in res[a]):.0f} | {statistics.median(p.sold for p in res[a]):.2e} |")

    print("\n## jackpot events per 28 days (median per player)")
    print("| archetype | Titan | Giant | Glowing | Starlit | Aurora | Prismatic |")
    print("|---|---|---|---|---|---|---|")
    for a in ARCHETYPES:
        h = lambda k: statistics.median(p.big_hits[k] for p in res[a])
        print(f"| {a} | {h('titan'):.1f} | {h('giant'):.1f} | {h('glowing'):.0f} | {h('starlit'):.0f} | {h('aurora'):.0f} | {h('prismatic'):.0f} |")

    print("\n## reveals per online hour (median over whole 28 days; harvest-level reveal L1..L5)")
    print("| archetype | L1 | L2 | L3 | L4 | L5 |")
    print("|---|---|---|---|---|---|")
    for a in ARCHETYPES:
        hrs = statistics.median(p.online_s for p in res[a]) / 3600
        row = [statistics.median(p.reveals[k] for p in res[a]) / hrs for k in range(1, 6)]
        print(f"| {a} | " + " | ".join(f"{v:.1f}" for v in row) + " |")

    # day-by-day for 'regular' archetype
    print("\n## regular archetype by day (median rebirths at end of day)")
    for d in (1, 2, 3, 7, 14, 28):
        if d > args.days:
            continue
        rs = []
        for s in range(args.seeds):
            p = Player("regular", random.Random(1000 + s), args)
            p.run(d)
            rs.append(p.r)
        print(f"- D{d}: rebirth {statistics.median(rs):.0f}")

    if args.mc:
        mc_tables()


def mc_tables():
    rng = random.Random(7)
    print("\n## plant profit rate (coins per plot-second, base, no mutation)")
    print("| plant | rarity | cost | grow | sell | ROI x | profit/plot-min |")
    print("|---|---|---|---|---|---|---|")
    for n, r, c, g, s in PLANTS:
        print(f"| {n} | {RARITIES[r]} | {c:,} | {g}s | {s:,} | {s/c:.2f} | {(s-c)/g*60:,.0f} |")

    print("\n## per-event mutation chance for one plant present the whole 240 s weather (16 ticks)")
    print("| mutation | mult | odds per tick | P(at least one in a window) | in Glow Hour x2 |")
    print("|---|---|---|---|---|")
    for nm, (m, n, wt) in MUTATIONS.items():
        if wt is None:
            print(f"| {nm} | x{m} | 1 in {n} on harvest | {1/n:.1%} | - |")
            continue
        p = 1 - (1 - 1 / n) ** 16
        p2 = 1 - (1 - 2 / n) ** 16
        print(f"| {nm} | x{m} | 1 in {n} | {p:.1%} | {p2:.1%} |")

    wd = {w: 0.0 for w, _ in WEATHER_P}
    for slot in range(144 * 30):
        wd[weather_at(slot * WEATHER_SLOT)] += 1
    print("\n## weather windows per day (deterministic table over 30 days)")
    for w, c in wd.items():
        print(f"- {w}: {c/30:.1f} per day")

    # stock appearance frequencies
    cnt = {r: 0 for r in range(6)}
    N = 12 * 24 * 30
    for slot in range(N):
        st = stock_at(slot)
        seen = {PLANTS[i][1] for i in st}
        for r in seen:
            cnt[r] += 1
    print("\n## shop: share of restocks showing each rarity (30 days)")
    for r in range(6):
        print(f"- {RARITIES[r]}: {cnt[r]/N:.1%}")
    my = sum(1 for slot in range(N) if any(PLANTS[i][1] == 5 for i in stock_at(slot)))
    print(f"- Mythic visible slots per day: {my/30:.1f} (= {my/30*5:.0f} min/day)")
    gaps, last = [], None
    for slot in range(N):
        if any(PLANTS[i][1] == 5 for i in stock_at(slot)):
            if last is not None and slot - last > 1:
                gaps.append((slot - last) * 5 / 60)
            last = slot
    print(f"- longest gap between Mythic windows: {max(gaps):.1f} h, median {statistics.median(gaps):.1f} h")


if __name__ == "__main__":
    sys.exit(main())
