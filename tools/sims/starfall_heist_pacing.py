"""Starfall Heist pacing / economy simulation (docs/38_STARFALL_HEIST.md).

Deterministic (seeded) model of one player on a shared star conveyor. The simulated player plays
greedily like a human would: buy any affordable star that beats the weakest pedestal, expand when
pedestals are full and the expansion is cheap, rebirth as soon as both conditions are met.

Rules mirrored from the GDD (all numbers live in the tables below; the GDD tables are generated
from them with --table so the doc and the sim cannot drift):
  - one star spawns every SPAWN s on the shared conveyor (meteor shower: SPAWN_SHOWER s, Rare+ x2)
  - rarity roll "1 in N", star inside the rarity by geometric weight 0.7^j
  - guarantees: Nova+ pity after PITY_NOVA s without one; Legendary on the UTC clock every
    CLOCK_LEGENDARY s; Celestial every CLOCK_CELESTIAL s; Cosmic once per meteor shower
  - competition: other players/bots may buy a star first (P_GET, P_GET_CLOCK for clock drops)
  - income/s = sum(star income) x (1 + REBIRTH_BONUS x rebirths) x constellation bonus
  - offline: OFFLINE_RATE x income for at most OFFLINE_CAP (the island is not in any server while
    offline, so nothing can be stolen while offline)
  - rebirth: cash cost AND owning a star of rarity >= requirement (docs/28 §3: money alone skips content)
  - steals (optional, on by default): the player tries a steal every STEAL_TRY online seconds after
    the rookie period; is robbed every ROBBED_EVERY online seconds; robbed stars pay 25% "stardust"

Usage: python -I tools/sims/starfall_heist_pacing.py [--days 35] [--seeds 12] [--no-steal]
                                                     [--pass2x] [--table] [--json]
"""

import argparse
import json
import math
import random
import statistics
import sys

DAY = 86400
SPAWN = 2.5
SPAWN_SHOWER = 1.25
RIDE = 36  # seconds a star rides the conveyor before it fades
PITY_NOVA = 150
CLOCK_LEGENDARY = 9 * 60
CLOCK_CELESTIAL = 45 * 60
CLOCK_COSMIC = 4 * 3600  # UTC 00/04/08/12/16/20 "Cosmic Hour"
P_GET_COSMIC = 0.25
P_GET = 0.55
P_GET_CLOCK = 0.35
START_CASH = 30
START_PEDESTALS = 6
MAX_PEDESTALS = 30
REBIRTH_BONUS = 0.6
MAX_REBIRTH = 12
OFFLINE_RATE = 0.05
OFFLINE_CAP = 3 * 3600
CONSTELLATION = 1.10  # average bonus from same-family links (GDD §5.4, measured later)
ROOKIE = 12 * 60
STEAL_TRY = 8 * 60
STEAL_SUCCESS = 0.45
ROBBED_EVERY = 15 * 60
STARDUST = 0.25
GIFT_AT = 45  # first-session personal "First Light" star

# Meteor showers (UTC): (weekday or None, hour, minutes). Daily 01:00 and 19:00 for 30 min,
# Saturday 17:00 "Cosmic Storm" 45 min.
SHOWERS = [(None, 1, 30), (None, 19, 30), (5, 17, 45)]

# key, display, "1 in N" per spawn (None = remainder), payback s, reveal level
RARITIES = [
    ("common", "Common", None, 10, 1),
    ("glow", "Glow", 4, 18, 1),
    ("rare", "Rare", 12, 32, 2),
    ("nova", "Nova", 45, 60, 3),
    ("legendary", "Legendary", 180, 120, 4),
    ("celestial", "Celestial", 1200, 170, 4),
    ("cosmic", "Cosmic", 40000, 240, 5),
]
RIDX = {r[0]: i for i, r in enumerate(RARITIES)}

# id, name, rarity, family, event_only
STARS = [
    (1, "Pip Spark", "common", "Sol", False),
    (2, "Driftling", "common", "Tide", False),
    (3, "Cinder Mote", "common", "Ember", False),
    (4, "Sprout Star", "common", "Bloom", False),
    (5, "Frostlet", "common", "Frost", False),
    (6, "Dusk Mote", "common", "Void", False),
    (7, "Lantern Pup", "glow", "Sol", False),
    (8, "Bubble Comet", "glow", "Tide", False),
    (9, "Ember Kit", "glow", "Ember", False),
    (10, "Petal Wisp", "glow", "Bloom", False),
    (11, "Snowpuff", "glow", "Frost", False),
    (12, "Shade Hopper", "glow", "Void", False),
    (13, "Halo Hare", "rare", "Sol", False),
    (14, "Tidal Ray", "rare", "Tide", False),
    (15, "Blaze Fox", "rare", "Ember", False),
    (16, "Moss Glider", "rare", "Bloom", False),
    (17, "Crystal Owl", "rare", "Frost", False),
    (18, "Gloom Moth", "rare", "Void", False),
    (19, "Sunburst Lion", "nova", "Sol", False),
    (20, "Riptide Whale", "nova", "Tide", False),
    (21, "Magma Drake", "nova", "Ember", False),
    (22, "Aurora Stag", "nova", "Frost", False),
    (23, "Eclipse Cat", "nova", "Void", False),
    (24, "Solar Phoenix", "legendary", "Sol", False),
    (25, "Abyss Leviathan", "legendary", "Tide", False),
    (26, "Verdant Serpent", "legendary", "Bloom", False),
    (27, "Glacier Titan", "legendary", "Frost", False),
    (28, "Nebula Wolf", "legendary", "Void", False),
    (29, "Zenith Griffin", "celestial", "Sol", False),
    (30, "Comet Kraken", "celestial", "Tide", False),
    (31, "Pulsar Dragon", "celestial", "Ember", False),
    (32, "Starbloom Moth", "celestial", "Bloom", False),
    (33, "Quasar Behemoth", "cosmic", "Void", False),
    (34, "Galaxy Koi", "cosmic", "Frost", False),
    (35, "Supernova Seraph", "cosmic", "Ember", True),
    (36, "Event Horizon Owl", "cosmic", "Void", True),
]
INCOME_GROWTH = 1.45


def nice(x):
    """Round to 2 significant digits so prices read cleanly (12, 18, 1,500, 2.4M)."""
    if x < 10:
        return round(x * 2) / 2
    p = 10 ** (int(math.log10(x)) - 1)
    return round(x / p) * p


def star_income(i):
    return nice(INCOME_GROWTH ** (i - 1))


def star_price(i):
    s = STARS[i - 1]
    return nice(star_income(i) * RARITIES[RIDX[s[2]]][3])


# Rebirth r -> r+1: cash cost REBIRTH_BASE x REBIRTH_GROWTH^r AND owning a star of this rarity
REBIRTH_BASE = 5e6
REBIRTH_GROWTH = 2.6
REBIRTH_NEED = ["legendary"] * 4 + ["celestial"] * 6 + ["cosmic"] * 2


def rebirth_cost(r):
    return nice(REBIRTH_BASE * REBIRTH_GROWTH**r)


def rebirth_start_cash(r):
    return START_CASH if r == 0 else nice(1000 * 2**r)


PED_BASE = 250
PED_GROWTH = 2.4
EXPAND_WITHIN = 120  # the simulated player buys a pedestal only if it costs <= this many seconds of income


def pedestal_cost(n):
    """Cost of the n-th pedestal (n = 7..30)."""
    return nice(PED_BASE * PED_GROWTH ** (n - 7))


def within_weights(rarity, shower):
    ids = [s[0] for s in STARS if s[2] == rarity and (shower or not s[4])]
    return ids, [0.7**j for j in range(len(ids))]


def rarity_probs(shower):
    p = {}
    for key, _, n, _, _ in RARITIES[1:]:
        p[key] = (1 / n) * (2 if shower and RIDX[key] >= RIDX["rare"] else 1)
    p["common"] = 1 - sum(p.values())
    return p


def in_shower(t):
    wd = int(t // DAY + 3) % 7  # unix day 0 was a Thursday -> Monday = 0
    sod = t % DAY
    for day, hour, mins in SHOWERS:
        if day is not None and day != wd:
            continue
        start = hour * 3600
        if start <= sod < start + mins * 60:
            return True, sod - start
    return False, 0


class Player:
    def __init__(self, seed, steal=True, pass2x=False):
        self.rng = random.Random(seed)
        self.steal = steal
        self.mult_pass = 2.0 if pass2x else 1.0
        self.rebirths = 0
        self.online = 0.0
        self.first = {}
        self.gift_done = False
        self.online_income = 0.0
        self.offline_income = 0.0
        self.robbed = 0
        self.stolen = 0
        self.last_nova = -1e9
        self.next_try = ROOKIE
        self.next_robbed = ROOKIE + ROBBED_EVERY
        self.cosmic_shower_done = set()
        self.reset()

    def reset(self):
        self.cash = rebirth_start_cash(self.rebirths)
        self.pedestals = START_PEDESTALS + min(self.rebirths, 6)
        self.stars = []  # star ids on pedestals

    def mult(self):
        return (1 + REBIRTH_BONUS * self.rebirths) * CONSTELLATION * self.mult_pass

    def income(self):
        return sum(star_income(i) for i in self.stars) * self.mult()

    def mark(self, name):
        if name not in self.first:
            self.first[name] = self.online

    def best_rarity(self):
        return max((RIDX[STARS[i - 1][2]] for i in self.stars), default=-1)

    def place(self, sid):
        if len(self.stars) < self.pedestals:
            self.stars.append(sid)
        else:
            worst = min(self.stars, key=star_income)
            self.stars.remove(worst)
            self.cash += star_price(worst) * 0.5
            self.stars.append(sid)
        r = STARS[sid - 1][2]
        self.mark("own_" + r)

    def wants(self, sid):
        if len(self.stars) < self.pedestals:
            return True
        return star_income(sid) > min(star_income(i) for i in self.stars)

    def offer(self, sid, clock):
        price = star_price(sid)
        if self.cash < price or not self.wants(sid):
            return
        chance = P_GET_COSMIC if clock == "cosmic" else P_GET_CLOCK if clock else P_GET
        if self.rng.random() > chance:
            return
        self.cash -= price
        self.mark("first_buy")
        self.place(sid)

    def spawn(self, t, shower, since, step):
        rng = self.rng
        sid, clock = None, False
        if t % CLOCK_COSMIC < step:
            rar, clock = "cosmic", "cosmic"
        elif t % CLOCK_CELESTIAL < step:
            rar, clock = "celestial", True
        elif t % CLOCK_LEGENDARY < step:
            rar, clock = "legendary", True
        elif shower and since >= 15 * 60 and (t - since) not in self.cosmic_shower_done:
            self.cosmic_shower_done.add(t - since)
            rar, clock = "cosmic", "cosmic"
        elif t - self.last_nova >= PITY_NOVA:
            rar = "nova"
        else:
            probs = rarity_probs(shower)
            x, acc, rar = rng.random(), 0.0, "common"
            for key, _, _, _, _ in RARITIES:
                acc += probs[key]
                if x < acc:
                    rar = key
                    break
        if RIDX[rar] >= RIDX["nova"]:
            self.last_nova = t
        ids, w = within_weights(rar, shower)
        sid = rng.choices(ids, w)[0]
        self.offer(sid, clock)

    def try_expand(self):
        while self.pedestals < MAX_PEDESTALS and len(self.stars) >= self.pedestals:
            c = pedestal_cost(self.pedestals + 1)
            if c > self.cash or c > EXPAND_WITHIN * max(self.income(), 1):
                return
            self.cash -= c
            self.pedestals += 1

    def try_rebirth(self, day):
        if self.rebirths >= MAX_REBIRTH:
            return
        cost, need = rebirth_cost(self.rebirths), REBIRTH_NEED[self.rebirths]
        if self.cash >= cost and self.best_rarity() >= RIDX[need]:
            self.rebirths += 1
            self.first["rebirth%d" % self.rebirths] = self.online
            self.first.setdefault("rebirth%d_day" % self.rebirths, day)
            self.reset()

    def steals(self):
        if not self.steal or self.online < ROOKIE:
            return
        if self.online >= self.next_try:
            self.next_try += STEAL_TRY
            if self.stars and self.rng.random() < STEAL_SUCCESS:
                best = max(self.stars, key=star_income)
                sid = max(1, min(34, best + self.rng.randint(-3, 1)))
                if self.wants(sid):
                    self.place(sid)
                    self.stolen += 1
                    self.mark("first_steal")
        if self.online >= self.next_robbed:
            self.next_robbed += ROBBED_EVERY
            if len(self.stars) >= 3:
                top = sorted(self.stars, key=star_income)[-3:]
                lost = self.rng.choice(top)
                self.stars.remove(lost)
                self.cash += star_price(lost) * STARDUST
                self.robbed += 1

    def session(self, start, seconds, day):
        t = start
        end = start + seconds
        acc = 0.0
        while t < end:
            shower, since = in_shower(t)
            step = SPAWN_SHOWER if shower else SPAWN
            inc = self.income() * step
            self.cash += inc
            self.online_income += inc
            self.online += step
            if not self.gift_done and self.online >= GIFT_AT:
                self.gift_done = True
                self.place(7)  # First Light gift = Lantern Pup with a level-3 reveal
                self.mark("gift")
            acc += step
            self.spawn(t, shower, since, step)
            self.try_expand()
            self.try_rebirth(day)
            self.steals()
            if self.rebirths >= MAX_REBIRTH and self.best_rarity() >= RIDX["cosmic"]:
                self.mark("endgame")
                self.first.setdefault("endgame_day", day)
            t += step
        return end

    def offline(self, seconds):
        gain = self.income() * OFFLINE_RATE * min(seconds, OFFLINE_CAP)
        self.cash += gain
        self.offline_income += gain


ARCHETYPES = {
    "casual": [(19, 15)],
    "regular": [(8, 20), (19, 20)],
    "engaged": [(8, 25), (13, 25), (20, 25)],
    "hardcore": [(8, 30), (12, 30), (17, 30), (21, 30)],
}
EPOCH = 1_793_059_200  # 2026-10-26 00:00 UTC (Monday) — only the weekday/clock matter


def run(arch, seed, days, steal, pass2x):
    p = Player(seed, steal, pass2x)
    last_end = None
    snap = {}
    for d in range(days):
        for hour, mins in ARCHETYPES[arch]:
            start = EPOCH + d * DAY + hour * 3600
            if last_end is not None:
                p.offline(start - last_end)
            last_end = p.session(start, mins * 60, d + 1)
        if d + 1 in (1, 7, 14, 28):
            snap[d + 1] = (p.rebirths, p.income(), len(p.stars), p.pedestals)
    tot = p.online_income + p.offline_income
    return p, snap, (p.offline_income / tot if tot else 0)


def fmt_t(s):
    if s is None:
        return "-"
    if s < 120:
        return "%ds" % s
    return "%.1fm" % (s / 60)


def fmt_n(x):
    for unit, v in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if x >= v:
            return ("%.1f" % (x / v)).rstrip("0").rstrip(".") + unit
    return ("%.1f" % x).rstrip("0").rstrip(".")


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def star_table():
    probs = rarity_probs(False)
    out = ["| # | 별 | 등급 | 계열 | 가격 $ | 수입 $/s | 등장 (일반, 1 in N) | 공개 Lv |", "|---|---|---|---|---|---|---|---|"]
    for sid, name, rar, fam, ev in STARS:
        ids, w = within_weights(rar, ev)
        share = w[ids.index(sid)] / sum(w)
        if ev:
            arrive = "유성우 전용 (Cosmic Storm 보장)"
        else:
            n = 1 / (probs[rar] * share)
            arrive = "1 in %s" % fmt_n(round(n, 1) if n < 100 else round(n))
        out.append(
            "| %d | %s | %s | %s | %s | %s | %s | %d |"
            % (sid, name, RARITIES[RIDX[rar]][1], fam, fmt_n(star_price(sid)), fmt_n(star_income(sid)), arrive, RARITIES[RIDX[rar]][4])
        )
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=35)
    ap.add_argument("--seeds", type=int, default=12)
    ap.add_argument("--no-steal", action="store_true")
    ap.add_argument("--pass2x", action="store_true")
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if a.table:
        print(star_table())
        print()
        print("| 다음 받침대 | " + " | ".join(str(n) for n in range(7, 31, 3)) + " |")
        print("|---|" + "---|" * len(range(7, 31, 3)))
        print("| 가격 $ | " + " | ".join(fmt_n(pedestal_cost(n)) for n in range(7, 31, 3)) + " |")
        return
    keys = ["first_buy", "gift", "own_rare", "own_nova", "first_steal", "own_legendary", "rebirth1", "rebirth2", "rebirth3", "own_celestial", "rebirth6", "own_cosmic", "rebirth12"]
    result = {}
    print("Starfall Heist pacing - days=%d seeds=%d steal=%s pass2x=%s" % (a.days, a.seeds, not a.no_steal, a.pass2x))
    print("online time to milestone (median over seeds); '-' = not reached in the horizon")
    print("| archetype | " + " | ".join(keys) + " | R@D1 | R@D7 | R@D28 | endgame day | offline share | robbed/stolen |")
    print("|---|" + "---|" * (len(keys) + 6))
    for arch in ARCHETYPES:
        runs = [run(arch, s, a.days, not a.no_steal, a.pass2x) for s in range(1, a.seeds + 1)]
        row = [fmt_t(med([p.first.get(k) for p, _, _ in runs])) for k in keys]
        rd = {d: med([snap.get(d, (None,))[0] for _, snap, _ in runs]) for d in (1, 7, 28)}
        eg = [p.first.get("endgame_day") for p, _, _ in runs]
        egm = med(eg)
        off = statistics.mean(o for _, _, o in runs)
        rob = statistics.mean(p.robbed for p, _, _ in runs)
        sto = statistics.mean(p.stolen for p, _, _ in runs)
        row += [str(rd[1]), str(rd[7]), str(rd[28]), ("%d (%d/%d)" % (egm, sum(e is not None for e in eg), len(eg))) if egm else "-", "%.0f%%" % (off * 100), "%.0f/%.0f" % (rob, sto)]
        print("| %s | %s |" % (arch, " | ".join(row)))
        result[arch] = dict(zip(keys + ["R@D1", "R@D7", "R@D28", "endgame", "offline", "robbed/stolen"], row))
    if a.json:
        print(json.dumps(result, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
