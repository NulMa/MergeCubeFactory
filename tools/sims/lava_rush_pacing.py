"""Lava Rush pacing simulation (docs/36_LAVA_RUSH.md §9).

Model: one wave cycle (WAVE_CYCLE seconds) is one simulation step while the player is online.
Per cycle the player climbs to the highest unlocked zone, collects personal treasure spawns,
and either runs home (low zones) or hides in shelters (high zones). Each trip can be lost to the
wave with a zone/skill dependent chance. Displayed treasures pay income per second; offline the
display pays OFFLINE_RATE for at most OFFLINE_CAP seconds. Purchases are greedy (cheapest first)
except that the next heat unlock is saved for when it is close.

All numbers here are the tuning values written in docs/36 §5~§8. Change both together.

Usage: python -I tools/sims/lava_rush_pacing.py [--seeds 20] [--days 45] [--quick]
Stdlib only, deterministic per seed.
"""

import math
import random
import statistics
import sys

DAY = 86400
WAVE_CYCLE = 60  # calm 30 + warning 8 + flow ~15 + linger/cool 7 (docs/36 §6)

# ---------------------------------------------------------------- content (docs/36 §5, §7)
# name, d0, d1 (studs along the slope), value factor, odds "1 in N" for U,R,E,L,M,S, base trip loss
ZONES = [
    ("Ash Foothills", 0, 80, 1, (4, 15, 80, 600, None, None), 0.010),
    ("Cinder Path", 80, 180, 5, (4, 13, 70, 500, None, None), 0.020),
    ("Obsidian Ridge", 180, 300, 25, (3.5, 12, 60, 400, None, None), 0.035),
    ("Magma Terraces", 300, 440, 120, (3.5, 11, 50, 300, None, None), 0.045),
    ("Sulfur Cliffs", 440, 600, 600, (3, 10, 45, 250, 3000, None), 0.055),
    ("Ember Crown", 600, 760, 3000, (3, 9, 40, 200, 2000, None), 0.065),
    ("Crater Rim", 760, 900, 15000, (3, 8, 35, 150, 1200, 25000), 0.075),
]
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
RARITY_MULT = [1, 3, 10, 40, 200, 2000, 25000]
VARIANTS = [("Molten", 2.0, 12), ("Inferno", 5.0, 150)]  # name, mult, 1 in N (free, shown in UI)

PERSONAL_SPAWNS_TOP = 4  # personal spawns per wave in the player's chosen zone
PERSONAL_SPAWNS_BELOW = 2  # picked up on the way, one zone lower
PICK_SECONDS = 3.0  # walk between spawns + pickup per item
BASE_SPEED = 18
SPEED_PER_LV = 1.0
SPEED_MAX_LV = 24
CARRY_SLOW = 0.04  # -4% speed per carried item after the first (min 0.8)

# ---------------------------------------------------------------- economy (docs/36 §8)
SPEED_COST = lambda lv: 25 * 1.55**lv  # noqa: E731
CARRY_COST = [60, 900, 1.5e4, 3e5, 6e6, 1.2e8, 3e9]  # 1 -> 8 slots
PED_BASE = 8
PED_MAX = 30
PED_PER_ZONE = 3
PED_COST = lambda n: 60 * 2.1**n  # noqa: E731  n = pedestals bought this run
# Heat Suit: levels 0..HEAT_MAX_LV. Zone z opens at HEAT_ZONE_LV[z-1]; each level also cuts trip loss by 1%
# (server: +0.02 s lava grace per level, docs/36 §8.1). Per-level cost is a geometric fill between the
# cumulative cost targets below (cost to reach each zone threshold from level 0).
HEAT_MAX_LV = 30
HEAT_ZONE_LV = [0, 3, 6, 10, 14, 19, 24]
HEAT_ZONE_TOTAL = [0, 150, 3e4, 1.5e6, 3e7, 6e8, 1.5e10]
HEAT_TAIL_GROWTH = 1.9  # per-level growth after the last threshold


def _heat_level_costs():
    costs = []
    for z in range(1, len(HEAT_ZONE_LV)):
        lv0, lv1 = HEAT_ZONE_LV[z - 1], HEAT_ZONE_LV[z]
        spend = HEAT_ZONE_TOTAL[z] - HEAT_ZONE_TOTAL[z - 1]
        n = lv1 - lv0
        g = 1.8 if z > 1 else 1.5
        first = spend * (g - 1) / (g**n - 1)
        costs += [first * g**i for i in range(n)]
    while len(costs) < HEAT_MAX_LV:
        costs.append(costs[-1] * HEAT_TAIL_GROWTH)
    return costs  # costs[lv] = price of going from lv to lv+1


HEAT_LV_COST = _heat_level_costs()
ZONE_CAP = [3, 4, 5, 5, 6, 6, 7, 7, 7, 7, 7]  # highest zone (1-based) reachable at rebirth r
REBIRTH_COST = [1e7, 1.2e8, 1.2e9, 6e9, 6e10, 2.5e11, 9e11, 1.8e12, 3e12, 5e12]
MAX_REBIRTH = 10
REBIRTH_MULT = 0.6  # income x (1 + 0.6 r)
TROPHY_MAX = 5  # one trophy pedestal per rebirth kept through rebirths

OFFLINE_RATE = 0.10
OFFLINE_CAP = 2 * 3600

ARCHETYPES = {
    "casual": ([(19, 15)], 1.5),
    "regular": ([(8, 20), (19, 20)], 1.0),
    "engaged": ([(8, 25), (13, 25), (20, 25)], 0.8),
    "hardcore": ([(8, 30), (12, 30), (17, 30), (21, 30)], 0.6),
}


class Player:
    def __init__(self, rng, skill):
        self.rng = rng
        self.skill = skill
        self.rebirths = 0
        self.trophies = []
        self.cash = 0.0
        self.online = 0.0
        self.events = {}
        self.trips = 0
        self.lost_trips = 0
        self.purchase_times = []
        self.online_income = 0.0
        self.offline_income = 0.0
        self.best_rarity = 0
        self.reset_run()

    def reset_run(self):
        self.cash = 0.0
        self.speed_lv = 0
        self.carry = 1
        self.heat_lv = 0
        self.heat = 1  # zones unlocked (1-based), derived from heat_lv
        self.peds_bought = 0
        self.display = []

    def mark(self, key):
        if key not in self.events:
            self.events[key] = self.online

    def ped_limit(self):
        # pedestal slots open with the zone unlocked (base expands as you climb) + 1 per rebirth
        return min(PED_MAX, PED_BASE + PED_PER_ZONE * (self.heat - 1) + self.rebirths)

    def pedestals(self):
        return min(self.ped_limit(), PED_BASE + self.peds_bought + self.rebirths)

    def mult(self):
        return 1 + REBIRTH_MULT * self.rebirths

    def income(self):
        return (sum(self.display) + sum(self.trophies)) * self.mult()

    def speed(self):
        return BASE_SPEED + SPEED_PER_LV * self.speed_lv + self.rebirths

    def roll(self, z):
        _, _, _, vf, odds, _ = ZONES[z]
        r = 0
        x = self.rng.random()
        acc = 0.0
        # rarest first
        for idx in range(6, 0, -1):
            n = odds[idx - 1]
            if n is None:
                continue
            acc += 1 / n
            if x < acc:
                r = idx
                break
        v = 1.0
        for _, mult, n in VARIANTS:
            if self.rng.random() < 1 / n:
                v = mult
        if r > self.best_rarity:
            self.best_rarity = r
        if r >= 4:
            self.mark(f"first {RARITIES[r]}")
        return vf * RARITY_MULT[r] * self.rng.uniform(0.85, 1.15) * v

    def place(self, value):
        cap = self.pedestals()
        if len(self.display) < cap:
            self.display.append(value)
            return
        lo = min(self.display)
        if value > lo:
            self.display.remove(lo)
            self.display.append(value)
            self.cash += lo * 30 * self.mult()  # auto-sell = 30 s of its income
        else:
            self.cash += value * 30 * self.mult()

    def cycle(self):
        z = self.heat - 1
        _, d0, d1, _, _, risk = ZONES[z]
        mid = (d0 + d1) / 2
        slow = max(0.8, 1 - CARRY_SLOW * (self.carry - 1))
        trip_time = 2 * mid / (self.speed() * slow) + self.carry * PICK_SECONDS
        overhead = 4 if z <= 1 else 9
        cap = PERSONAL_SPAWNS_TOP + (PERSONAL_SPAWNS_BELOW if z > 0 else 0)
        trips_f = (WAVE_CYCLE - overhead) / trip_time
        items_f = min(trips_f * self.carry, cap)
        items = int(items_f) + (1 if self.rng.random() < items_f - int(items_f) else 0)
        while items > 0:
            take = min(self.carry, items)
            items -= take
            self.trips += 1
            p = risk * self.skill * (1 + 0.05 * (take - 1)) * (1 - 0.01 * self.heat_lv)
            if self.rng.random() < p:
                self.lost_trips += 1
                continue
            for i in range(take):
                zz = z if (i < PERSONAL_SPAWNS_TOP or z == 0) else z - 1
                self.place(self.roll(zz))
                self.mark("first treasure")

    def heat_lv_cap(self):
        cap = ZONE_CAP[self.rebirths]
        return HEAT_MAX_LV if cap >= len(HEAT_ZONE_LV) else HEAT_ZONE_LV[cap] - 1

    def buy_heat(self):
        self.cash -= HEAT_LV_COST[self.heat_lv]
        self.heat_lv += 1
        while self.heat < len(HEAT_ZONE_LV) and self.heat_lv >= HEAT_ZONE_LV[self.heat]:
            self.heat += 1
            self.mark(f"zone {self.heat}")
        self.purchase_times.append(self.online)

    def options(self):
        out = []
        if self.heat_lv < self.heat_lv_cap():
            out.append((HEAT_LV_COST[self.heat_lv], "heat"))
        if self.speed_lv < SPEED_MAX_LV:
            out.append((SPEED_COST(self.speed_lv), "speed"))
        if self.carry < 8:
            out.append((CARRY_COST[self.carry - 1], "carry"))
        if self.pedestals() < self.ped_limit():
            out.append((PED_COST(self.peds_bought), "ped"))
        return out

    def shop(self):
        while True:
            cap = ZONE_CAP[self.rebirths]
            if self.heat < cap:
                # save for the heat level that opens the next zone
                need = HEAT_ZONE_LV[self.heat]
                hc = sum(HEAT_LV_COST[self.heat_lv : need])
                if self.cash >= HEAT_LV_COST[self.heat_lv]:
                    self.buy_heat()
                    continue
                inc = self.income()
                if inc > 0 and (hc - self.cash) / inc < 240:
                    return
            elif self.rebirths < MAX_REBIRTH:
                rc = REBIRTH_COST[self.rebirths]
                if self.cash >= rc:
                    self.do_rebirth()
                    continue
                inc = self.income()
                if inc > 0 and (rc - self.cash) / inc < 300:
                    return
            opts = [o for o in self.options() if o[0] <= self.cash]
            if not opts:
                return
            cost, kind = min(opts)
            self.cash -= cost
            if kind == "heat":
                self.cash += cost
                self.buy_heat()
                continue
            if kind == "speed":
                self.speed_lv += 1
            elif kind == "carry":
                self.carry += 1
                self.mark(f"carry {self.carry}")
            else:
                self.peds_bought += 1
            self.purchase_times.append(self.online)

    def do_rebirth(self):
        best = sorted(self.display, reverse=True)
        self.rebirths += 1
        self.trophies = sorted(self.trophies + best[:1], reverse=True)[:TROPHY_MAX]
        self.mark(f"rebirth {self.rebirths}")
        self.purchase_times.append(self.online)
        self.reset_run()

    def endgame(self):
        return self.rebirths >= MAX_REBIRTH and self.heat >= 7


def simulate(archetype, seed, days):
    sessions, skill = ARCHETYPES[archetype]
    p = Player(random.Random(seed), skill)
    day_reached = {}
    last_end = None
    max_gap = 0.0
    for day in range(days):
        for hour, minutes in sessions:
            start = day * DAY + hour * 3600
            if last_end is not None:
                away = start - last_end
                gain = p.income() * OFFLINE_RATE * min(away, OFFLINE_CAP)
                p.cash += gain
                p.offline_income += gain
                p.shop()
            n_cycles = minutes * 60 // WAVE_CYCLE
            for _ in range(n_cycles):
                before = p.cash
                p.cash += p.income() * WAVE_CYCLE
                p.online_income += p.cash - before
                p.cycle()
                p.online += WAVE_CYCLE
                p.shop()
            last_end = start + minutes * 60
        for key in list(p.events):
            if key not in day_reached:
                day_reached[key] = day + 1
    # longest wait between meaningful purchases while online (minutes)
    pt = sorted(p.purchase_times)
    end_t = p.events.get("rebirth 10", p.online)
    pt = [t for t in pt if t <= end_t]
    for a, b in zip(pt, pt[1:]):
        max_gap = max(max_gap, b - a)
    return p, day_reached, max_gap


def fmt_min(sec):
    if sec is None:
        return "-"
    return f"{sec / 60:.0f}m" if sec < 5400 else f"{sec / 3600:.1f}h"


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def main():
    seeds = 20
    days = 45
    args = sys.argv[1:]
    if "--quick" in args:
        seeds = 5
    if "--seeds" in args:
        seeds = int(args[args.index("--seeds") + 1])
    if "--days" in args:
        days = int(args[args.index("--days") + 1])

    keys = (
        ["first treasure", "zone 2", "zone 3", "rebirth 1", "zone 4", "rebirth 2", "zone 5"]
        + ["rebirth 4", "zone 6", "rebirth 6", "zone 7", "rebirth 10", "first Legendary", "first Mythic"]
    )
    print(f"# Lava Rush pacing (seeds={seeds}, days={days}, cycle={WAVE_CYCLE}s)\n")
    print("Online play time to milestone (median over seeds), and calendar day reached.\n")
    header = "| milestone | " + " | ".join(ARCHETYPES) + " |"
    print(header)
    print("|" + "---|" * (len(ARCHETYPES) + 1))
    results = {a: [simulate(a, s, days) for s in range(1, seeds + 1)] for a in ARCHETYPES}
    for k in keys:
        row = [k]
        for a in ARCHETYPES:
            on = median([r[0].events.get(k) for r in results[a]])
            dy = median([r[1].get(k) for r in results[a]])
            reached = sum(1 for r in results[a] if k in r[0].events)
            if on is None:
                row.append("not reached")
            else:
                tag = "" if reached == seeds else f" ({reached}/{seeds})"
                row.append(f"{fmt_min(on)} / D{dy:.0f}{tag}")
        print("| " + " | ".join(row) + " |")

    print("\n| metric | " + " | ".join(ARCHETYPES) + " |")
    print("|" + "---|" * (len(ARCHETYPES) + 1))
    rows = {
        "trip loss rate": lambda r: r[0].lost_trips / max(1, r[0].trips) * 100,
        "offline share of income %": lambda r: r[0].offline_income
        / max(1, r[0].offline_income + r[0].online_income)
        * 100,
        "longest purchase gap (min)": lambda r: r[2] / 60,
        "rebirths at end": lambda r: r[0].rebirths,
        "zone at end": lambda r: r[0].heat,
        "log10 income/s at end": lambda r: math.log10(max(1, r[0].income())),
        "purchases per online hour": lambda r: len(r[0].purchase_times) / max(1, r[0].online / 3600),
    }
    for name, fn in rows.items():
        vals = [median([fn(r) for r in results[a]]) for a in ARCHETYPES]
        print(f"| {name} | " + " | ".join(f"{v:.1f}" for v in vals) + " |")

    # first-session minute-by-minute for the regular archetype, seed 1
    print("\nFirst 20 minutes, regular, seed 1 (cash, income/s, zone, carry, speed lv):\n")
    p = Player(random.Random(1), 1.0)
    print("| min | cash | income/s | zone | carry | speed lv | pedestals used |")
    print("|---|---|---|---|---|---|---|")
    for minute in range(1, 21):
        p.cash += p.income() * WAVE_CYCLE
        p.cycle()
        p.online += WAVE_CYCLE
        p.shop()
        if minute in (1, 2, 3, 5, 8, 10, 15, 20):
            print(
                f"| {minute} | {p.cash:,.0f} | {p.income():,.1f} | {p.heat} | {p.carry} | {p.speed_lv} | "
                f"{len(p.display)}/{p.pedestals()} |"
            )


if __name__ == "__main__":
    main()
