"""Pacing / economy simulation for the top-3 concepts (docs/13_SIMULATION.md).

Each concept is a deterministic-seed incremental economy driven by the same simple player:
online -> act every second (collect, buy the cheapest affordable upgrade, rebirth when possible);
offline -> time skips, timers keep running, offline income is capped.

Fairness: every concept gets one global cost scale k, calibrated so the "regular" archetype reaches
the concept's endgame on day CAL_DAY. Metrics are then compared at equal content runway.

Usage: python -I tools/pacing_sim.py [--quick] [--only MergeGarden] [--k 7.8e4] [--offline RATE HOURS]
"""

import functools
import math
import random
import sys

DAY = 86400
CAL_DAY = 35  # target endgame day for the regular archetype
HORIZON_DAYS = 60

# (session start hour, minutes) per day
ARCHETYPES = {
    "casual": [(19, 15)],
    "regular": [(8, 20), (19, 20)],
    "engaged": [(8, 25), (13, 25), (20, 25)],
    "hardcore": [(8, 30), (12, 30), (17, 30), (21, 30)],
}

# Offline income for A and D: rate x income/s, for at most CAP seconds.
# docs/05 draft was 0.5 / 8 h; the sim shows that makes 80-95% of income passive (docs/13 §4),
# so the default is 0.1 / 4 h. Override: --offline RATE HOURS
OFFLINE_RATE = 0.1
OFFLINE_CAP = 4 * 3600


class Metrics:
    def __init__(self):
        self.first = {}  # milestone -> online seconds since first join
        self.endgame_day = None
        self.positive_triggers = 0  # things that finished while away (reasons to come back)
        self.loss_events = 0  # things taken from the player while away
        self.purchases_per_session = []
        self.online_income = 0.0
        self.offline_income = 0.0
        self.day_progress = {}  # day -> log10(income rate)

    def mark(self, name, online_t):
        if name not in self.first:
            self.first[name] = online_t


# ---------------------------------------------------------------- A: merge factory
class MergeFactory:
    name = "A merge factory"
    MAX_TIER = 12
    TRAY_CAP = 40
    MAX_REBIRTH = 5
    HATCH = {8: (300, 0.02), 9: (300, 0.02), 10: (1800, 0.05), 11: (7200, 0.10), 12: (28800, 0.25)}

    def __init__(self, k, cash_mult=1.0, seed=1):
        self.k, self.cash_mult = k, cash_mult
        self.rng = random.Random(seed)
        self.hatch_bonus = 0.0
        self.rebirths = 0
        self.incubators = []  # finish times
        self.core_queue = []  # pending cores (finish duration, bonus)
        self.reset_run()

    def reset_run(self):
        self.cash = 0.0
        self.tray = [0] * (self.MAX_TIER + 1)
        self.droppers = [{"tier": 1, "lv": 0, "t": 0.0} for _ in range(2)]
        self.reached = 1

    def tier_cap(self):
        return min(6 + self.rebirths, self.MAX_TIER - 1)

    def mult(self):
        return 1.5**self.rebirths * (1 + self.hatch_bonus) * self.cash_mult

    def income_rate(self):
        return sum(n * 2.4 ** (t - 1) for t, n in enumerate(self.tray) if n) * self.mult()

    def upgrades(self):
        k = self.k
        out = []
        for i, d in enumerate(self.droppers):
            if d["lv"] < 15:
                out.append((10 * 1.55 ** d["lv"] * k * 1.3**i, ("speed", i)))
            if d["tier"] < self.tier_cap():
                out.append((40 * 7 ** (d["tier"] - 1) * k, ("tier", i)))
        if len(self.droppers) < 8:
            out.append((300 * 9 ** (len(self.droppers) - 2) * k, ("slot", None)))
        return out

    def buy(self, kind, i):
        if kind == "speed":
            self.droppers[i]["lv"] += 1
        elif kind == "tier":
            self.droppers[i]["tier"] += 1
        else:
            self.droppers.append({"tier": 1, "lv": 0, "t": 0.0})

    def rebirth_cost(self):
        return 2e5 * 12**self.rebirths * self.k

    def is_endgame(self):
        return self.rebirths >= self.MAX_REBIRTH and self.reached >= self.MAX_TIER

    def tick_online(self, now, online_t, m):
        for d in self.droppers:
            d["t"] += 1
            interval = max(0.4, 2.0 * 0.88 ** d["lv"])
            while d["t"] >= interval:
                d["t"] -= interval
                self.tray[d["tier"]] += 1
        # resolve merges (physics would take ~1s; one pass per tick is close enough)
        for t in range(1, self.MAX_TIER):
            while self.tray[t] >= 2:
                self.tray[t] -= 2
                self.tray[t + 1] += 1
                if t + 1 > self.reached:
                    self.reached = t + 1
                    m.mark(f"tier{t + 1}", online_t)
                m.mark("first_reward", online_t)
                if t + 1 in self.HATCH and self.rng.random() < 0.25:
                    self.core_queue.append(self.HATCH[t + 1])
        while sum(self.tray) > self.TRAY_CAP:  # auto-sell lowest
            low = next(t for t in range(1, self.MAX_TIER + 1) if self.tray[t])
            self.tray[low] -= 1
            self.cash += 10 * 2.4 ** (low - 1) * self.mult()
        self.fill_incubators(now, m, online_t)
        gained = self.income_rate()
        self.cash += gained
        m.online_income += gained

    def fill_incubators(self, now, m, online_t):
        done = [f for f in self.incubators if f[0] <= now]
        for f in done:
            self.incubators.remove(f)
            self.hatch_bonus += f[1]
            m.mark("first_hatch", online_t)
        while len(self.incubators) < 2 and self.core_queue:
            dur, bonus = self.core_queue.pop(0)
            self.incubators.append((now + dur, bonus))
            m.mark("first_timer", online_t)

    def go_offline(self, start, end, m):
        dur = end - start
        gained = OFFLINE_RATE * self.income_rate() * min(dur, OFFLINE_CAP)
        self.cash += gained
        m.offline_income += gained
        m.positive_triggers += sum(1 for f in self.incubators if start < f[0] <= end)
        if dur >= OFFLINE_CAP:
            m.positive_triggers += 1  # "offline storage full"

    def try_rebirth(self, online_t, m):
        if self.rebirths < self.MAX_REBIRTH and self.cash >= self.rebirth_cost():
            self.rebirths += 1
            m.mark(f"rebirth{self.rebirths}", online_t)
            self.reset_run()
            return True
        return False


# ---------------------------------------------------------------- variants (docs/16)
# Same table and recurrence as Economy.VARIANTS / Economy.variantMeanByTier: (mult, merge chance, drop chance).
VARIANTS = [
    (1, 0, 0),
    (1.5, 0.025, 0.005),  # Metallic
    (3, 0.008, 0.0016),  # Neon
    (8, 0.0018, 0.00036),  # Rainbow
    (25, 0.00025, 0.00005),  # Galaxy
    (70, 0.0001, 0.00002),  # Cosmic
    (200, 0.00002, 0.000004),  # Divine
]
# events (docs/17): golden cube ~+19% (70% caught) + merge fever ~+6% while online, as an average factor.
# Applied to every income in the model (online and offline); offline is slightly overstated as a result.
EVENT_MULT = 1.25  # --no-events sets 1.0
USE_VARIANTS = True  # --no-variants turns the expected multiplier off (pre-docs/16 baseline)


@functools.lru_cache(maxsize=None)
def variant_mean_by_tier(tiers):
    """Random same-tier pairing: result = max(fresh roll, inherited), inherited = better parent one step
    weaker, or one step stronger when both parents share a non-normal variant (fusion)."""
    n = len(VARIANTS)

    def dist(drop):
        p = [v[2] if drop else v[1] for v in VARIANTS]
        p[0] = 1 - sum(p[1:])
        return p

    def inherit(a, b):
        if a == b and a > 0:
            return min(a + 1, n - 1)
        return max(max(a, b) - 1, 0)

    merge, d, out = dist(False), dist(True), []
    for _ in range(tiers):
        out.append(sum(d[i] * VARIANTS[i][0] for i in range(n)))
        nd = [0.0] * n
        for a in range(n):
            for b in range(n):
                inh = inherit(a, b)
                for k in range(n):
                    nd[max(inh, k)] += d[a] * d[b] * merge[k]
        d = nd
    return out


# ---------------------------------------------------------------- A+: merge factory with a core farm
class MergeGarden(MergeFactory):
    """A + E hybrid (docs/13 §5): merges from tier 5 drop cores; cores grow in a buyable bank of
    incubators (2 -> 12) on real-time timers and pay out cash (60% of income/s x timer) plus a small
    permanent bonus. Early costs are not scaled by k (k ramps in over the first levels), so the first
    session stays fast while the late game is stretched."""

    name = "A+ merge + core farm"
    # tier ladder v3 (docs/13 §8): 40 tiers, merges stop at a ceiling that each rebirth raises by 2
    # (12 -> 40 over 14 rebirths), regular endgame on day 75. Same numbers as
    # game/src/merge/shared/Economy.luau (MAX_TIER, MAX_REBIRTH, tierCap, tierCeiling, tierCost, rebirthCost, CORES).
    CAL_DAY = 26  # 2026-10-20: 75 -> 30 (docs/13 §9.7); 2026-10-21: core payout cap -> 26 (docs/13 §9.8)
    HORIZON_DAYS = 60
    MAX_TIER = 40
    MAX_REBIRTH = 14
    CEILING_BASE = 12
    CEILING_STEP = 2  # 3 -> 2 (2026-10-21): 상한 큐브를 만들어야 리버스, 14번째에 T40 (docs/13 §9.9)
    DROPPER_GAP = 10  # 드로퍼 최대 등급 = 상한 - 10 (Economy.tierCap)
    TIER_GROWTH = 7
    REBIRTH_GROWTH = 12
    RUN_GROWTH = 3  # run upgrades (speed, tier, slot, polish, lucky) cost x RUN_GROWTH^rebirths
    HATCH = {
        5: (120, 0.002),
        6: (300, 0.003),
        7: (600, 0.005),
        8: (1200, 0.008),
        9: (2700, 0.012),
        10: (5400, 0.02),
        11: (10800, 0.03),
        12: (28800, 0.06),
    }
    # tiers 13..MAX: 8 h + 30 min per tier up to 12 h, bonus +0.01 per tier
    for _t in range(13, MAX_TIER + 1):
        HATCH[_t] = (min(43200, 28800 + 1800 * (_t - 12)), round(0.06 + 0.01 * (_t - 12), 6))
    del _t
    MAX_INCUBATORS = 12
    QUEUE_CAP = 6
    PAYOUT = 0.6
    CORE_CAP = 90  # Economy.CORE_PAYOUT_CAP (2026-10-21: tray income should lead, docs/13 §9.8)

    # upgrades v2 (docs/14 §3.2) — same numbers as game/src/merge/shared/Economy.luau UPGRADES
    UPG = {
        "polish": (20, 500, 4, 4),
        "lucky": (10, 2000, 6, 3),
        "hatch": (10, 1000, 5, 3),
        "tray": (8, 5000, 9, 3),  # bigger tray: cap 50 + 8/Lv (Economy.trayCap, 2026-10-19)
    }  # max, base, growth, rampAt  (tap power is manual-only, not modeled)
    KEEP = ("polish", "lucky", "hatch", "tray")  # kept on rebirth, so no run_scale (2026-10-20: factory upgrades kept)
    TRAY_CAP = 50  # Economy.TRAY_CAP (2026-10-19)
    TRAY_STEP = 8

    def __init__(self, k, cash_mult=1.0, seed=1):
        self.incubator_slots = 2
        self.upg = {"polish": 0, "lucky": 0, "hatch": 0, "tray": 0}
        super().__init__(k, cash_mult, seed)

    def reset_run(self):
        super().reset_run()
        if not hasattr(self, "away"):
            self.away = []

    def mult(self):
        lv = self.upg["polish"] if hasattr(self, "upg") else 0
        # variants: the tray is modelled as counts per tier, so apply the expected multiplier of
        # high-tier cubes (they dominate income) instead of tracking a variant per cube (docs/16 §4)
        var = variant_mean_by_tier(self.MAX_TIER)[-1] if USE_VARIANTS else 1.0
        return super().mult() * (1 + 0.1 * lv) * 2 ** (lv // 10) * var * EVENT_MULT

    def ramp(self, idx, full_at):
        return self.k ** min(1.0, idx / full_at)

    def tier_cap(self):
        return min(max(6 + self.rebirths, self.ceiling() - self.DROPPER_GAP), self.MAX_TIER - 1)

    def ceiling(self):
        return min(self.CEILING_BASE + self.CEILING_STEP * self.rebirths, self.MAX_TIER)

    def run_scale(self):
        return self.RUN_GROWTH**self.rebirths

    def tier_cost(self, tier):
        return 40 * self.TIER_GROWTH ** (tier - 1) * self.ramp(tier - 1, 3) * self.run_scale()

    def rebirth_cost(self):
        # first five rebirths get k^(1/6)..k^(5/6) (Economy.rebirthCost REBIRTH_RAMP, docs/13 §9.6)
        return 2e4 * self.REBIRTH_GROWTH**self.rebirths * self.k ** min(1.0, (self.rebirths + 1) / 6)

    # 2026-10-21 사용자 "환생 요구량은 해당 티어 큐브를 1~2개 만들 때쯤": 이번 판에 상한 등급 큐브를 만들어야 리버스
    # (Economy.canRebirth). cash<n> / ceil<n> 표시로 돈과 상한 큐브 중 무엇이 먼저 오는지 잰다
    REBIRTH_GATE = True

    def try_rebirth(self, online_t, m):
        if self.rebirths >= self.MAX_REBIRTH:
            return False
        n = self.rebirths + 1
        cash_ok = self.cash >= self.rebirth_cost()
        gate_ok = self.reached >= self.ceiling()
        if cash_ok:
            m.mark(f"cash{n}", online_t)
        if gate_ok:
            m.mark(f"ceil{n}", online_t)
        if cash_ok and (gate_ok or not self.REBIRTH_GATE):
            self.rebirths += 1
            m.mark(f"rebirth{self.rebirths}", online_t)
            self.reset_run()
            return True
        return False

    def upgrades(self):
        out = []
        for i, d in enumerate(self.droppers):
            if d["lv"] < 15:
                out.append((10 * 1.55 ** d["lv"] * 1.3**i * self.ramp(d["lv"], 6) * self.run_scale(), ("speed", i)))
            if d["tier"] < self.tier_cap():
                out.append((self.tier_cost(d["tier"]), ("tier", i)))
        if len(self.droppers) < 8:
            n = len(self.droppers) - 2
            out.append((300 * 9**n * self.ramp(n, 2) * self.run_scale(), ("slot", None)))
        if self.incubator_slots < self.MAX_INCUBATORS:
            n = self.incubator_slots - 2
            out.append((150 * 3.2**n * self.ramp(n, 2), ("incubator", None)))
        for uid, (mx, base, growth, ramp_at) in self.UPG.items():
            lv = self.upg[uid]
            if lv < mx:
                scale = 1 if uid in self.KEEP else self.run_scale()
                out.append((base * growth**lv * self.ramp(lv, ramp_at) * scale, ("upg", uid)))
        return out

    def buy(self, kind, i):
        if kind == "incubator":
            self.incubator_slots += 1
        elif kind == "upg":
            self.upg[i] += 1
        else:
            super().buy(kind, i)

    def tick_online(self, now, online_t, m):
        for d in self.droppers:
            d["t"] += 1
            interval = max(0.4, 2.0 * 0.88 ** d["lv"])
            double = 0.15 * (d["lv"] // 5)
            while d["t"] >= interval:
                d["t"] -= interval
                # 2배 투하 = 한 등급 위 1개 (2026-10-21), 합치기 상한이면 2개
                if self.rng.random() < double:
                    if d["tier"] + 1 <= self.ceiling():
                        # 이미 한 번 합쳐진 큐브: 행운·코어는 합치기처럼 굴린다
                        t = d["tier"]
                        up = 2 if (t + 2 <= self.ceiling() and self.rng.random() < 0.02 * self.upg["lucky"]) else 1
                        self.tray[t + up] += 1
                        self.reached = max(self.reached, t + up)
                        if t + up in self.HATCH and self.rng.random() < 0.25:
                            if len(self.core_queue) < self.QUEUE_CAP:
                                self.core_queue.append(self.HATCH[t + up])
                            else:
                                self.cash += self.income_rate() * 5
                    else:
                        self.tray[d["tier"]] += 2
                else:
                    self.tray[d["tier"]] += 1
        lucky = 0.02 * self.upg["lucky"]
        top = self.ceiling()
        for t in range(1, top):
            while self.tray[t] >= 2:
                self.tray[t] -= 2
                up = 2 if (t + 2 <= top and self.rng.random() < lucky) else 1
                self.tray[t + up] += 1
                if t + up > self.reached:
                    self.reached = t + up
                    m.mark(f"tier{t + up}", online_t)
                m.mark("first_reward", online_t)
                if t + up in self.HATCH and self.rng.random() < 0.25:
                    if len(self.core_queue) < self.QUEUE_CAP:
                        self.core_queue.append(self.HATCH[t + up])
                    else:  # full queue: core sells for a little cash
                        self.cash += self.income_rate() * 5
        while sum(self.tray) > self.TRAY_CAP + self.TRAY_STEP * self.upg["tray"]:
            low = next(t for t in range(1, self.MAX_TIER + 1) if self.tray[t])
            self.tray[low] -= 1
            self.cash += 10 * 2.4 ** (low - 1) * self.mult()
        self.fill_incubators(now, m, online_t)
        gained = self.income_rate()
        self.cash += gained
        m.online_income += gained

    def fill_incubators(self, now, m, online_t):
        for f in [f for f in self.incubators if f[0] <= now]:
            self.incubators.remove(f)
            finish, bonus, payout, started = f
            self.hatch_bonus += bonus
            self.cash += payout
            away = sum(max(0, min(finish, e) - max(started, s)) for s, e in self.away[-4:])
            frac = away / max(1e-9, finish - started)
            m.offline_income += payout * frac
            m.online_income += payout * (1 - frac)
            m.mark("first_hatch", online_t)
        while len(self.incubators) < self.incubator_slots and self.core_queue:
            dur, bonus = self.core_queue.pop(0)
            dur *= 1 - 0.05 * self.upg["hatch"]
            payout = self.income_rate() * min(dur * self.PAYOUT, self.CORE_CAP)
            self.incubators.append((now + dur, bonus, payout, now))
            m.mark("first_timer", online_t)

    def go_offline(self, start, end, m):
        self.away.append((start, end))
        dur = end - start
        gained = OFFLINE_RATE * self.income_rate() * min(dur, OFFLINE_CAP)
        self.cash += gained
        m.offline_income += gained
        m.positive_triggers += len({round(f[0] / 600) for f in self.incubators if start < f[0] <= end})
        if dur >= OFFLINE_CAP:
            m.positive_triggers += 1



# ---------------------------------------------------------------- E: crystal garden
class CrystalGarden:
    name = "E crystal garden"
    GROW = [30, 120, 300, 900, 2700, 7200, 14400, 28800, 57600, 86400]
    MAX_PLOTS = 40
    MAX_SPRINKLER = 10

    def __init__(self, k, cash_mult=1.0, seed=1):
        self.k, self.cash_mult = k, cash_mult
        self.rng = random.Random(seed)
        self.cash = 5.0
        self.plots = [None] * 6  # (ready_time, seed index) or None
        self.unlocked = 1
        self.sprinkler = 0
        self.stock = {}
        self.next_restock = 0
        self.away = []

    def rate(self, s):  # profit per growth second per plot
        return 0.25 * 2.1**s

    def value(self, s):
        return self.rate(s) * self.GROW[s] * 1.5

    def seed_cost(self, s):
        # Seed 0 is free and always stocked: without this guard a player who spends all cash on plots
        # can never plant again (softlock found by this sim, see docs/13 §4).
        return 0.0 if s == 0 else self.value(s) / 3

    def unlock_cost(self, s):
        return 60 * 6.5 ** (s - 1) * self.k

    def income_rate(self):
        return sum(self.rate(p[1]) for p in self.plots if p) * self.cash_mult

    def restock(self, now):
        while now >= self.next_restock:
            self.next_restock += 300
            self.stock = {0: 10**9}
            for s in range(1, self.unlocked):
                if self.rng.random() < max(0.2, 1 - 0.09 * s):
                    self.stock[s] = self.rng.randint(1, 6)

    def upgrades(self):
        out = []
        if self.unlocked < len(self.GROW):
            out.append((self.unlock_cost(self.unlocked), ("unlock", None)))
        if len(self.plots) < self.MAX_PLOTS:
            out.append((40 * 1.35 ** (len(self.plots) - 6) * self.k, ("plot", None)))
        if self.sprinkler < self.MAX_SPRINKLER:
            out.append((800 * 4.2**self.sprinkler * self.k, ("sprinkler", None)))
        return out

    def buy(self, kind, _):
        if kind == "unlock":
            self.unlocked += 1
        elif kind == "plot":
            self.plots.append(None)
        else:
            self.sprinkler += 1

    def is_endgame(self):
        return (
            self.unlocked == len(self.GROW)
            and len(self.plots) == self.MAX_PLOTS
            and self.sprinkler == self.MAX_SPRINKLER
        )

    def tick_online(self, now, online_t, m):
        self.restock(now)
        for i, p in enumerate(self.plots):
            if p and p[0] <= now:
                mut = 3 if self.rng.random() < 0.1 else 1
                gained = self.value(p[1]) * mut * self.cash_mult
                self.cash += gained
                # attribute value by how much of the growth happened while the player was away
                ready, _, planted = p
                away = sum(max(0, min(ready, e) - max(planted, s)) for s, e in self.away[-4:])
                frac = away / max(1e-9, ready - planted)
                m.offline_income += gained * frac
                m.online_income += gained * (1 - frac)
                m.mark("first_reward", online_t)
                self.plots[i] = None
            if self.plots[i] is None:
                for s in sorted(self.stock, reverse=True):
                    if self.stock[s] > 0 and self.cash >= self.seed_cost(s):
                        self.cash -= self.seed_cost(s)
                        self.stock[s] -= 1
                        grow = self.GROW[s] / (1 + 0.15 * self.sprinkler)
                        self.plots[i] = (now + grow, s, now)
                        m.mark("first_timer", online_t)
                        m.mark(f"seed{s + 1}", online_t)
                        break

    def go_offline(self, start, end, m):
        # plants keep growing; harvest happens on return
        self.away.append((start, end))
        m.positive_triggers += len({round(p[0] / 600) for p in self.plots if p and start < p[0] <= end})

    def try_rebirth(self, online_t, m):
        return False


# ---------------------------------------------------------------- D: cube heist
class CubeHeist:
    name = "D cube heist"
    MAX_RARITY = 10
    MAX_REBIRTH = 5

    def __init__(self, k, cash_mult=1.0, seed=1, shield=False):
        self.k, self.cash_mult, self.shield = k, cash_mult, shield
        self.rng = random.Random(seed)
        self.rebirths = 0
        self.best_ever = 1
        self.reset_run()

    def reset_run(self):
        self.cash = 30.0
        self.units = []
        self.slots = 8
        self.belt_t = 0

    def mult(self):
        return 1.5**self.rebirths * self.cash_mult

    def income(self, r):
        return 3 ** (r - 1)

    def price(self, r):
        return 20 * 4 ** (r - 1) * self.k

    def income_rate(self):
        return sum(self.income(r) for r in self.units) * self.mult()

    def upgrades(self):
        if self.slots < 30:
            return [(1000 * 1.6 ** (self.slots - 8) * self.k, ("slot", None))]
        return []

    def buy(self, kind, _):
        self.slots += 1

    def rebirth_cost(self):
        return 5e5 * 15**self.rebirths * self.k

    def is_endgame(self):
        return self.rebirths >= self.MAX_REBIRTH and self.best_ever >= self.MAX_RARITY

    def add_unit(self, r, online_t, m):
        if len(self.units) < self.slots:
            self.units.append(r)
        elif self.units and r > min(self.units):
            self.units.remove(min(self.units))
            self.units.append(r)
        else:
            return
        if r > self.best_ever:
            self.best_ever = r
            m.mark(f"rarity{r}", online_t)

    def tick_online(self, now, online_t, m):
        self.belt_t += 1
        if self.belt_t >= 8:  # a unit rolls past every 8 s
            self.belt_t = 0
            cap = min(self.MAX_RARITY, 4 + self.rebirths + 1)
            weights = [0.55**r for r in range(cap)]
            r = self.rng.choices(range(1, cap + 1), weights)[0]
            if self.cash >= self.price(r) and (len(self.units) < self.slots or r > min(self.units)):
                self.cash -= self.price(r)
                self.add_unit(r, online_t, m)
                m.mark("first_reward", online_t)
        if self.units and self.rng.random() < 0.15 / 60:  # successful steal ~ every 7 online minutes
            self.add_unit(max(1, max(self.units) - self.rng.randint(0, 2)), online_t, m)
            m.mark("first_steal", online_t)
        gained = self.income_rate()
        self.cash += gained
        m.online_income += gained

    def go_offline(self, start, end, m):
        dur = end - start
        gained = OFFLINE_RATE * self.income_rate() * min(dur, OFFLINE_CAP)
        self.cash += gained
        m.offline_income += gained
        if dur >= OFFLINE_CAP:
            m.positive_triggers += 1
        if not self.shield:
            lost = sum(1 for _ in range(int(dur // 3600)) if self.units and self.rng.random() < 0.08)
            for _ in range(lost):
                if self.units:
                    self.units.remove(max(self.units))
                    m.loss_events += 1

    def try_rebirth(self, online_t, m):
        if self.rebirths < self.MAX_REBIRTH and self.cash >= self.rebirth_cost():
            self.rebirths += 1
            m.mark(f"rebirth{self.rebirths}", online_t)
            self.reset_run()
            return True
        return False


CONCEPTS = [MergeFactory, MergeGarden, CrystalGarden, CubeHeist]


# ---------------------------------------------------------------- driver
def horizon(cls):
    return getattr(cls, "HORIZON_DAYS", HORIZON_DAYS)


def cal_day(cls):
    return getattr(cls, "CAL_DAY", CAL_DAY)


def simulate(cls, k, archetype, days=None, seed=1, **kw):
    days = days or horizon(cls)
    g = cls(k, seed=seed, **kw)
    m = Metrics()
    online_t = 0
    last_logout = None
    for day in range(days):
        for hour, minutes in ARCHETYPES[archetype]:
            start = day * DAY + hour * 3600
            if last_logout is not None:
                g.go_offline(last_logout, start, m)
            bought = 0
            for s in range(minutes * 60):
                now = start + s
                g.tick_online(now, online_t, m)
                g.try_rebirth(online_t, m)
                while True:  # cheapest-first purchasing
                    ups = g.upgrades()
                    if not ups:
                        break
                    cost, (kind, i) = min(ups, key=lambda u: u[0])
                    if g.cash < cost:
                        break
                    g.cash -= cost
                    g.buy(kind, i)
                    bought += 1
                    m.mark("first_purchase", online_t)
                online_t += 1
                if m.endgame_day is None and g.is_endgame():
                    m.endgame_day = day + 1
            if m.endgame_day is None:  # only sessions that still had something to buy
                m.purchases_per_session.append(bought)
            last_logout = start + minutes * 60
        m.day_progress[day + 1] = math.log10(max(g.income_rate(), 1e-9))
    return m


def calibrate(cls):
    lo, hi = -3.0, 9.0  # log10(k)
    for _ in range(22):
        mid = (lo + hi) / 2
        d = simulate(cls, 10**mid, "regular", days=cal_day(cls) + 15).endgame_day
        if d is None or d > cal_day(cls):
            hi = mid
        else:
            lo = mid
    return 10**lo


def fmt_t(sec):
    if sec is None:
        return "-"
    return f"{sec:.0f}s" if sec < 120 else f"{sec / 60:.1f}m"


def main():
    global OFFLINE_RATE, OFFLINE_CAP, USE_VARIANTS
    quick = "--quick" in sys.argv
    USE_VARIANTS = "--no-variants" not in sys.argv
    global EVENT_MULT
    if "--no-events" in sys.argv:
        EVENT_MULT = 1.0
    if "--offline" in sys.argv:
        i = sys.argv.index("--offline")
        OFFLINE_RATE, OFFLINE_CAP = float(sys.argv[i + 1]), float(sys.argv[i + 2]) * 3600
    print(f"# pacing_sim results (default CAL_DAY={CAL_DAY} / horizon {HORIZON_DAYS} days unless a concept overrides, offline {OFFLINE_RATE} x {OFFLINE_CAP / 3600:g} h)\n")
    rows = {}
    concepts = CONCEPTS
    if "--only" in sys.argv:
        want = sys.argv[sys.argv.index("--only") + 1]
        concepts = [c for c in CONCEPTS if c.__name__ == want]
    for cls in concepts:
        if "--k" in sys.argv:  # reuse a calibrated value (e.g. Economy.COST_SCALE) instead of searching
            k = float(sys.argv[sys.argv.index("--k") + 1])
        else:
            k = calibrate(cls) if not quick else 1.0
        rows[cls.name] = {"k": k, "cal": cal_day(cls), "h": horizon(cls)}
        for a in ARCHETYPES:
            rows[cls.name][a] = simulate(cls, k, a)
        rows[cls.name]["regular_2x"] = simulate(cls, k, "regular", cash_mult=2.0)
        if cls is CubeHeist:
            rows[cls.name]["regular_shield"] = simulate(cls, k, "regular", shield=True)

    print("## Calibration and runway (endgame day)\n")
    print("| concept | target day | k | casual | regular | engaged | hardcore | regular + 2x cash |")
    print("|---|---|---|---|---|---|---|---|")
    for name, r in rows.items():
        cells = [str(r[a].endgame_day or f">{r['h']}") for a in ARCHETYPES]
        print(f"| {name} | {r['cal']} | {r['k']:.3g} | " + " | ".join(cells) + f" | {r['regular_2x'].endgame_day or '>' + str(r['h'])} |")

    print("\n## First session (regular archetype, online time since first join)\n")
    keys = ["first_reward", "first_purchase", "first_timer", "first_hatch", "first_steal"]
    print("| concept | " + " | ".join(keys) + " |")
    print("|---|" + "---|" * len(keys))
    for name, r in rows.items():
        m = r["regular"]
        print(f"| {name} | " + " | ".join(fmt_t(m.first.get(x)) for x in keys) + " |")

    print("\n## Return structure (per-day average over each concept's horizon)\n")
    print("| concept | archetype | reasons to return / day | losses while away / day | value created while away | sessions with 0 purchases (D2 to endgame) | longest no-purchase streak (sessions) |")
    print("|---|---|---|---|---|---|---|")
    for name, r in rows.items():
        for a in ARCHETYPES:
            m = r[a]
            spd = len(ARCHETYPES[a])
            sessions = m.purchases_per_session[spd:]
            zero = sum(1 for b in sessions if b == 0) / max(1, len(sessions))
            streak = best = 0
            for b in sessions:
                streak = streak + 1 if b == 0 else 0
                best = max(best, streak)
            total = m.online_income + m.offline_income
            off = m.offline_income / total if total else 0
            print(
                f"| {name} | {a} | {m.positive_triggers / r['h']:.2f} | {m.loss_events / r['h']:.2f} | {off:.0%} | {zero:.0%} | {best} |"
            )

    print("\n## Progress curve (log10 income/s at end of day, regular)\n")
    days = [1, 3, 7, 14, 21, 28, 35, 50, 75]
    print("| concept | " + " | ".join(f"D{d}" for d in days) + " |")
    print("|---|" + "---|" * len(days))
    for name, r in rows.items():
        m = r["regular"]
        print(f"| {name} | " + " | ".join(f"{m.day_progress.get(d, float('nan')):.1f}" for d in days) + " |")

    if "D cube heist" in rows:
        s = rows["D cube heist"]["regular_shield"]
        print(f"\nD with offline shield (regular): endgame day {s.endgame_day}, losses {s.loss_events}")


if __name__ == "__main__":
    main()
