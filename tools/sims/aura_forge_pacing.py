"""Aura Forge pacing simulation (docs/35_AURA_FORGE.md).

Mean-field model: a player's progression (roll points, upgrades, rebirths) follows the EXPECTED
path of the greedy human policy; rare hits are handled with survival curves (hazard integration):
    S_T(t) = exp(-sum(rolls * P(aura with N >= T)))      -> P(no aura of tier >= T yet)
Reported: median (S=0.5), P90 (S=0.1) and mean time to the FIRST aura of each tier.
Approximation: RP windfalls from rare hits and the rebirth "must have rolled a goal aura" gate are
taken at expectation (gate = cumulative hazard of the goal tier since last rebirth >= 1.0).

Rules mirrored from the GDD (keep in sync with docs/35 and the Luau Odds/Pacing modules):
  - rolls are free; cooldown CD0 * CD_STEP^q (floor), multi-roll m per press, all earned in game
  - luck multiplies ONLY auras with N >= LUCK_MIN_N; the rest is renormalised to sum to 1
  - event auras exist only while their celestial event is live; event luck multiplies like luck
  - new account: first 150 rolls have luck x3 (free, shown in UI); tutorial-scripted rolls are not modelled
  - mercy: Radiant+ by 1,000 rolls, Prism+ by 15,000, Astral+ by 60,000 (first-hit survival forced to 0)
  - rolls happen only while online (no offline rolling, auto-roll only removes tap loss)
  - rebirth: needs RP cost AND a hit of the goal tier in the current run; resets RP + upgrades,
    keeps luck_rebirth / rp_mult / cooldown mult

Usage: python -I tools/sims/aura_forge_pacing.py [--days 90] [--auto] [--no-events]
                                                 [--archetype regular] [--table] [--odds]
                                                 [--selfcheck] [--first-session]
"""

import argparse
import math
import random
import sys

# ----------------------------------------------------------------------------- aura table
# (id, name, N, tier, event)  event=None for always-available auras. The commonest aura (D01)
# has N=None: its probability is the remainder so that all probabilities sum to exactly 1.
TIERS = ["Dust", "Glint", "Radiant", "Prism", "Astral", "Genesis"]
TIER_MIN_N = {"Dust": 1, "Glint": 100, "Radiant": 1_000, "Prism": 10_000, "Astral": 100_000, "Genesis": 1_000_000}
REVEAL_LEVEL = {"Dust": 1, "Glint": 2, "Radiant": 3, "Prism": 3, "Astral": 4, "Genesis": 5}

AURAS = [
    ("D01", "Cinder Wisp", None, "Dust", None),
    ("D02", "Faded Glow", 5, "Dust", None),
    ("D03", "Pebble Spark", 7, "Dust", None),
    ("D04", "Dew Shimmer", 10, "Dust", None),
    ("D05", "Soot Halo", 14, "Dust", None),
    ("D06", "Moth Dust", 20, "Dust", None),
    ("D07", "Tin Flicker", 28, "Dust", None),
    ("D08", "Ash Ribbon", 40, "Dust", None),
    ("D09", "Copper Pulse", 60, "Dust", None),
    ("D10", "Clover Mist", 90, "Dust", None),
    ("G01", "Lantern Drift", 120, "Glint", None),
    ("G02", "Frost Thread", 160, "Glint", None),
    ("G03", "Ember Crown", 220, "Glint", None),
    ("G04", "Violet Ripple", 300, "Glint", None),
    ("G05", "Tide Echo", 420, "Glint", None),
    ("G06", "Sun Splinter", 550, "Glint", None),
    ("G07", "Thorn Bloom", 700, "Glint", None),
    ("G08", "Quartz Chime", 900, "Glint", None),
    ("R01", "Stormglass", 1_200, "Radiant", None),
    ("R02", "Gilded Veil", 1_800, "Radiant", None),
    ("R03", "Nebula Wake", 2_500, "Radiant", None),
    ("R04", "Obsidian Halo", 3_500, "Radiant", None),
    ("R05", "Petal Cyclone", 5_000, "Radiant", None),
    ("R06", "Mirror Orbit", 6_500, "Radiant", None),
    ("R07", "Voltage Bloom", 8_500, "Radiant", None),
    ("P01", "Prism Cascade", 12_000, "Prism", None),
    ("P02", "Wraith Lantern", 20_000, "Prism", None),
    ("P03", "Aurora Mantle", 35_000, "Prism", None),
    ("P04", "Clockwork Saint", 55_000, "Prism", None),
    ("P05", "Hollow Comet", 80_000, "Prism", None),
    ("A01", "Skybreaker", 150_000, "Astral", None),
    ("A02", "Void Garden", 300_000, "Astral", None),
    ("A03", "Starforge Regent", 500_000, "Astral", None),
    ("A04", "Lunar Maw", 750_000, "Astral", None),
    ("S01", "Genesis Lantern", 1_000_000, "Genesis", None),
    ("S02", "Worldseed", 2_500_000, "Genesis", None),
    ("S03", "Forge Heartbeat", 10_000_000, "Genesis", None),
    # event auras: N is the odds while the event is live, at luck x1
    ("C01", "Comet Tail", 400, "Glint", "comet"),
    ("C02", "Ion Streak", 6_000, "Radiant", "comet"),
    ("C03", "Cometborn Crown", 200_000, "Astral", "comet"),
    ("E01", "Penumbra Veil", 300, "Glint", "eclipse"),
    ("E02", "Black Sun Ring", 8_000, "Radiant", "eclipse"),
    ("E03", "Totality", 400_000, "Astral", "eclipse"),
    ("V01", "Ribbon Chorus", 500, "Glint", "aurora"),
    ("V02", "Polar Lattice", 9_000, "Radiant", "aurora"),
    ("V03", "Skyloom", 300_000, "Astral", "aurora"),
    ("M01", "Falling Ember", 350, "Glint", "meteor"),
    ("M02", "Impact Bloom", 7_000, "Radiant", "meteor"),
    ("M03", "Starfall Crown", 250_000, "Astral", "meteor"),
    ("X01", "Conjunction Halo", 20_000, "Prism", "alignment"),
    ("X02", "Zenith Engine", 1_500_000, "Genesis", "alignment"),
]

# ----------------------------------------------------------------------------- balance knobs
LUCK_MIN_N = 100            # luck only multiplies auras at least this rare
LUCK_CAP = 40.0             # total multiplier cap (anti-overflow; Odds also clamps the sum)
CD0, CD_STEP, CD_FLOOR = 3.0, 0.94, 1.0
QH_MAX, QH_COST0, QH_COST_G = 15, 18, 1.62          # Quick Hands (cooldown)
LL_MAX, LL_PER, LL_COST0, LL_COST_G = 20, 0.05, 30, 1.50   # Luck Lens (+5 % per level, additive, max x2.0)
MR_COSTS = [500, 15000]                              # Multi-roll 2/3 per press (max 3)
RP_EXP = 0.55                                        # RP per roll = max(1, N ** RP_EXP)
REB_MAX = 20
REB_LUCK_PER, REB_RP_PER, REB_CD = 0.15, 0.10, 0.985
# rebirth r (1-based): RP cost, goal tier N (must roll an aura >= this in the run)
REB_COST0, REB_COST_G = 1_000, 2.35
REB_GOAL = [200, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 200_000,
            300_000, 500_000, 750_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000,
            1_000_000, 1_000_000, 1_000_000]
GATE_H = 1.0                # cumulative goal-tier hazard needed (63 % to have it)

# events (UTC): 00:00 and 13:00 daily, 30 min, cycling 4 types (epochDay*2+slot)%4, plus
# Saturday 19:00 UTC 60 min alignment. The sim uses a player-relative day index (weekend = day%7==5).
EVENT_LEN_MIN = 30
EVENT_LUCK = 2.0
WEEKEND_LEN_MIN = 60
WEEKEND_LUCK = 3.0
EVENT_CYCLE = ["comet", "eclipse", "aurora", "meteor"]

# Mercy (free, in-game): a tier-or-better aura is guaranteed after this many rolls without one.
# Counters persist across rebirth; a hit of tier T also resets every lower tier. No mercy for Genesis.
MERCY = {1_000: 1_000, 10_000: 15_000, 100_000: 60_000}  # min N -> max rolls without a hit
NEWBIE_ROLLS, NEWBIE_LUCK = 150, 3.0   # free "Beginner's Luck": first 150 rolls of a new account

STEP = 15  # seconds per sim step while online

# archetype: online minutes per day, share of the live events they attend (0..1)
ARCHETYPES = {
    "casual":   {"minutes": 15, "attend": 0.25},
    "regular":  {"minutes": 30, "attend": 0.50},
    "engaged":  {"minutes": 60, "attend": 0.80},
    "hardcore": {"minutes": 120, "attend": 0.95},
}
TAP_EFF = 0.85  # manual rolling: fraction of cooldowns actually used (auto-roll: 1.0)

REPORT_TIERS = [("N>=10", 10), ("Glint 100", 100), ("Radiant 1k", 1_000), ("Prism 10k", 10_000),
                ("Astral 100k", 100_000), ("Genesis 1M", 1_000_000), ("Forge 10M", 10_000_000)]


# ----------------------------------------------------------------------------- pure rules
def base_probs(event=None):
    """Probabilities at luck x1 for the given live event (None / event id). Sum == 1."""
    p = {}
    for aid, _name, n, _tier, ev in AURAS:
        if aid == "D01":
            continue
        if ev is None or ev == event:
            p[aid] = 1.0 / n
    p["D01"] = 1.0 - sum(p.values())
    assert p["D01"] > 0.2, "remainder aura too rare"
    return p


_N = {a[0]: a[2] for a in AURAS}


def odds(event=None, luck=1.0):
    """Probability table with luck: auras N>=LUCK_MIN_N x luck, the Dust pool renormalised."""
    p = base_probs(event)
    luck = min(luck, LUCK_CAP)
    high = {k: v for k, v in p.items() if _N.get(k) and _N[k] >= LUCK_MIN_N}
    low = {k: v for k, v in p.items() if k not in high}
    hs = sum(high.values()) * luck
    if hs > 0.9:  # clamp: keep at least 10 % for the Dust pool
        luck = 0.9 / sum(high.values())
        hs = 0.9
    ls = sum(low.values())
    out = {k: v * luck for k, v in high.items()}
    out.update({k: v * (1.0 - hs) / ls for k, v in low.items()})
    return out


def tier_prob(table, min_n):
    return sum(v for k, v in table.items() if (_N.get(k) or 0) >= min_n)


def rp_of(aid, n_remainder):
    n = _N.get(aid) or n_remainder
    return max(1.0, n ** RP_EXP)


def qh_cost(q):  # cost of level q (1-based)
    return QH_COST0 * QH_COST_G ** (q - 1)


def ll_cost(l):
    return LL_COST0 * LL_COST_G ** (l - 1)


def reb_cost(r):
    return REB_COST0 * REB_COST_G ** (r - 1)


def day_events(day):
    """Deterministic fixed-UTC schedule for a day index: list of (event_id, minutes, luck)."""
    ev = []
    for slot in (0, 1):
        ev.append((EVENT_CYCLE[(day * 2 + slot) % 4], EVENT_LEN_MIN, EVENT_LUCK))
    if day % 7 == 5:  # Saturday
        ev.append(("alignment", WEEKEND_LEN_MIN, WEEKEND_LUCK))
    return ev


# ----------------------------------------------------------------------------- simulation
class Player:
    def __init__(self, auto=False):
        self.rp = 0.0
        self.q = 0   # Quick Hands level
        self.l = 0   # Luck Lens level
        self.m = 1   # rolls per press
        self.reb = 0
        self.hgate = 0.0
        self.auto = auto
        self.rolls = 0.0

    def cd(self):
        c = CD0 * CD_STEP ** self.q * REB_CD ** self.reb
        return max(CD_FLOOR, c)

    def luck(self):
        return (1 + LL_PER * self.l) * (1 + REB_LUCK_PER * self.reb)

    def rp_mult(self):
        return 1 + REB_RP_PER * self.reb

    def rolls_per_s(self):
        return self.m / self.cd() * (1.0 if self.auto else TAP_EFF)


def simulate(arch, days, auto=False, events=True, log_rebirth=False):
    a = ARCHETYPES[arch]
    pl = Player(auto)
    # survival (log) per report tier + time marks
    surv = {name: 0.0 for name, _ in REPORT_TIERS}  # cumulative hazard
    first = {name: {} for name, _ in REPORT_TIERS}  # {0.5: (min, day), 0.1: .., mean: ..}
    mean_int = {name: 0.0 for name, _ in REPORT_TIERS}  # integral of S dt (minutes)
    online_min = 0.0
    reb_log = []
    nrem_cache = {}
    for day in range(days):
        segs = []
        evs = day_events(day) if events else []
        used = 0.0
        for ev_id, length, eluck in evs:
            m = length * a["attend"]
            m = min(m, a["minutes"] - used)
            if m > 0:
                segs.append((ev_id, eluck, m))
                used += m
        segs.append((None, 1.0, max(0.0, a["minutes"] - used)))
        for ev_id, eluck, mins in segs:
            steps = int(round(mins * 60 / STEP))
            for _ in range(steps):
                luck = pl.luck() * eluck * (NEWBIE_LUCK if pl.rolls < NEWBIE_ROLLS else 1.0)
                table = odds(ev_id, luck)
                if ev_id not in nrem_cache:
                    nrem_cache[ev_id] = 1.0 / base_probs(ev_id)["D01"]
                nrem = nrem_cache[ev_id]
                rolls = pl.rolls_per_s() * STEP
                pl.rolls += rolls
                exp_rp = sum(v * rp_of(k, nrem) for k, v in table.items()) * pl.rp_mult()
                pl.rp += rolls * exp_rp
                for name, tn in REPORT_TIERS:
                    h = rolls * tier_prob(table, tn)
                    s_before = math.exp(-surv[name])
                    surv[name] += h
                    cap = MERCY.get(tn)
                    if cap and pl.rolls >= cap:  # mercy: first hit is certain by now
                        surv[name] = max(surv[name], 50.0)
                    s_after = math.exp(-surv[name])
                    mean_int[name] += (s_before + s_after) / 2 * (STEP / 60.0)
                    for q in (0.5, 0.1):
                        if q not in first[name] and s_after <= q:
                            first[name][q] = (online_min + STEP / 60.0, day + 1)
                online_min += STEP / 60.0
                if pl.reb < REB_MAX:
                    pl.hgate += rolls * tier_prob(table, REB_GOAL[pl.reb])
                # greedy upgrade purchases: cheapest affordable next level
                while True:
                    opts = []
                    if pl.q < QH_MAX:
                        opts.append((qh_cost(pl.q + 1), "q"))
                    if pl.l < LL_MAX:
                        opts.append((ll_cost(pl.l + 1), "l"))
                    if pl.m - 1 < len(MR_COSTS):
                        opts.append((MR_COSTS[pl.m - 1], "m"))
                    if not opts:
                        break
                    cost, kind = min(opts)
                    if pl.rp < cost:
                        break
                    pl.rp -= cost
                    if kind == "q":
                        pl.q += 1
                    elif kind == "l":
                        pl.l += 1
                    else:
                        pl.m += 1
                if pl.reb < REB_MAX and pl.rp >= reb_cost(pl.reb + 1) and pl.hgate >= GATE_H:
                    pl.reb += 1
                    reb_log.append((pl.reb, online_min, day + 1))
                    pl.rp, pl.q, pl.l, pl.m, pl.hgate = 0.0, 0, 0, 1, 0.0
    # mean: integral of S until horizon; if S stays high the mean is a lower bound
    res = {}
    for name, _ in REPORT_TIERS:
        res[name] = {
            "p50": first[name].get(0.5), "p90": first[name].get(0.1),
            "mean_min": mean_int[name], "s_end": math.exp(-surv[name]),
        }
    return res, reb_log, pl


# ----------------------------------------------------------------------------- reporting
def fmt_t(x):
    if x is None:
        return "-"
    minutes, day = x
    if minutes < 90:
        return f"{minutes:.0f}m (D{day})"
    return f"{minutes / 60:.1f}h (D{day})"


def print_odds():
    p = base_probs()
    print("| id | name | tier | base 1-in-N | reveal |")
    print("|---|---|---|---|---|")
    for aid, name, n, tier, ev in AURAS:
        if ev is None:
            n_show = (1.0 / p[aid]) if n is None else n
            ns = f"{n_show:.1f}" if n is None else f"{n_show:,}"
            print(f"| {aid} | {name} | {tier} | 1 in {ns} | Lv{REVEAL_LEVEL[tier]} |")
    for aid, name, n, tier, ev in AURAS:
        if ev is not None:
            print(f"| {aid} | {name} | {tier} | 1 in {n:,} ({ev}) | Lv{REVEAL_LEVEL[tier]} |")


def selfcheck():
    rnd = random.Random(7)
    for ev in (None, "comet", "alignment"):
        for luck in (1.0, 3.0, 12.0, 80.0):
            t = odds(ev, luck)
            assert abs(sum(t.values()) - 1.0) < 1e-9, (ev, luck, sum(t.values()))
            assert all(v >= 0 for v in t.values())
    # luck x1 gives exactly 1/N
    t = odds(None, 1.0)
    for aid, _n, n, _t, ev in AURAS:
        if ev is None and n:
            assert abs(t[aid] - 1.0 / n) < 1e-12
    # event auras absent outside their event
    assert "C01" not in odds(None, 1.0) and "C01" in odds("comet", 1.0)
    # Monte Carlo sanity: mean rolls to the first N>=1000 aura at luck 1
    t = odds(None, 1.0)
    pr = tier_prob(t, 1000)
    trials = [0] * 2000
    for i in range(len(trials)):
        n = 0
        while True:
            n += 1
            if rnd.random() < pr:
                break
        trials[i] = n
    mean = sum(trials) / len(trials)
    exp = 1.0 / pr
    assert abs(mean - exp) / exp < 0.08, (mean, exp)
    # monotonic: more luck -> rarer more likely, commons less likely
    a, b = odds(None, 2.0), odds(None, 5.0)
    assert tier_prob(b, 1000) > tier_prob(a, 1000) and b["D01"] < a["D01"]
    print(f"selfcheck ok (MC mean {mean:.0f} vs expected {exp:.0f} rolls to N>=1000)")


def first_session():
    """Expected rolls/time for the first minutes (no upgrades), tutorial guarantees excluded."""
    t = odds(None, 1.0)
    rps = 1.0 / CD0 * TAP_EFF
    t = odds(None, NEWBIE_LUCK)
    print(f"first session (manual, no upgrades, cooldown 3.0 s, Beginner's Luck x{NEWBIE_LUCK:g} for {NEWBIE_ROLLS} rolls):")
    for name, tn in REPORT_TIERS[:4]:
        p = tier_prob(t, tn)
        print(f"  {name}: P(per roll) = 1 in {1 / p:,.0f}; median {math.log(2) / p:,.0f} rolls "
              f"= {math.log(2) / p / rps / 60:.1f} min")
    for mins in (1, 5, 30):
        rolls = mins * 60 * rps
        base = odds(None, 1.0)
        row = ", ".join(
            f"{n}: {100 * (1 - math.exp(-(min(rolls, NEWBIE_ROLLS) * tier_prob(t, tn) + max(0.0, rolls - NEWBIE_ROLLS) * tier_prob(base, tn)))):.0f}%"
            for n, tn in REPORT_TIERS[:4])
        print(f"  by {mins:>2} min ({rolls:.0f} rolls) P(at least one): {row}")


def server_load():
    """Expected high-tier reveals per hour for a mid-game player mix (drives banner/skysplit caps)."""
    states = [("early (luck x1.5, 0.28 rolls/s)", 1.5, 0.28), ("mid (luck x4, 1.1 rolls/s)", 4.0, 1.1),
              ("late (luck x6, 1.9 rolls/s)", 6.0, 1.9)]
    print("expected reveals per player-hour / per 12-player server-hour / per 1000 CCU-hour:")
    for label, luck, rps in states:
        t = odds(None, luck)
        rolls = rps * 3600
        row = []
        for name, tn in (("Radiant+ (Lv3)", 1_000), ("Prism+ (chat line)", 10_000),
                         ("Astral+ (sky split)", 100_000), ("Genesis (cinematic)", 1_000_000)):
            per = rolls * tier_prob(t, tn)
            row.append(f"{name} {per:.3f} / {per * 12:.2f} / {per * 1000:.0f}")
        print(f"- {label}: " + "; ".join(row))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=90)
    ap.add_argument("--auto", action="store_true", help="auto-roll (same speed, no tap loss)")
    ap.add_argument("--no-events", action="store_true")
    ap.add_argument("--archetype", choices=list(ARCHETYPES))
    ap.add_argument("--table", action="store_true", help="print aura table with odds")
    ap.add_argument("--odds", action="store_true", help="print luck-scaled tier odds")
    ap.add_argument("--selfcheck", action="store_true")
    ap.add_argument("--first-session", action="store_true")
    ap.add_argument("--server", action="store_true", help="expected high-tier reveals per hour")
    args = ap.parse_args()
    if args.table:
        print_odds()
        return
    if args.selfcheck:
        selfcheck()
        return
    if args.first_session:
        first_session()
        return
    if args.server:
        server_load()
        return
    if args.odds:
        for luck in (1, 2, 5, 10, 20, 40):
            t = odds(None, luck)
            print(f"luck x{luck}: " + ", ".join(
                f"{n} 1 in {1 / tier_prob(t, tn):,.0f}" for n, tn in REPORT_TIERS[1:]))
        return
    archs = [args.archetype] if args.archetype else list(ARCHETYPES)
    mode = ("auto-roll" if args.auto else "manual") + ("" if not args.no_events else ", no events")
    print(f"## Aura Forge pacing ({mode}, {args.days} days, median / P90 online time to first aura of tier)\n")
    print("| archetype (min/day) | " + " | ".join(n for n, _ in REPORT_TIERS) + " |")
    print("|---|" + "---|" * len(REPORT_TIERS))
    reb_rows = []
    for arch in archs:
        res, reb_log, pl = simulate(arch, args.days, auto=args.auto, events=not args.no_events)
        cells = []
        for name, _ in REPORT_TIERS:
            r = res[name]
            if r["p50"] is None:
                cells.append(f">{args.days}d (S={r['s_end']:.2f})")
            else:
                cells.append(f"{fmt_t(r['p50'])} / {fmt_t(r['p90'])}")
        print(f"| {arch} ({ARCHETYPES[arch]['minutes']}) | " + " | ".join(cells) + " |")
        reb_rows.append((arch, reb_log, pl))
    print("\nrebirth timeline (rebirth# at online time / calendar day):")
    for arch, reb_log, pl in reb_rows:
        pts = [f"R{r}:{m / 60:.1f}h/D{d}" for r, m, d in reb_log]
        shown = pts[:6] + (["..."] + pts[-2:] if len(pts) > 8 else pts[6:])
        print(f"- {arch}: " + (", ".join(shown) if shown else "none") +
              f" | end state reb={pl.reb} luck=x{pl.luck():.2f} cd={pl.cd():.2f}s m={pl.m} rolls={pl.rolls:,.0f}")


if __name__ == "__main__":
    sys.exit(main())
