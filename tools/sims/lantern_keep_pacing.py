"""Lantern Keep pacing / survival simulation (docs/37_LANTERN_KEEP.md §15).

Two parts:
  1. Run model (Monte Carlo): one server run = up to 12 nights (boss nights 4/8/12).
     Day: every participant mines crystals and buys towers greedily (best marginal DPS per crystal).
     Night: per-second queue model. Enemy HP spawns over SPAWN_WINDOW s, each chunk must cross the
     lane (EXPOSURE s inside tower coverage); defence DPS hits the front of the queue; HP older than
     EXPOSURE leaks into the Heart. Boss nights add a boss that must die before dawn.
     Output: P(survive night n) for 1 / 4 / 8 humans (bots fill to 4) x player profile x Moon Tier.
  2. Progression model: archetype play minutes per day -> runs -> Ember -> lantern unlocks, keeper
     upgrades, Moon Tier unlocks, first Rekindle.

All numbers are tuning values that must match game/src/lantern/shared/Config (to be written) and the
tables in docs/37. Usage: python -I tools/sims/lantern_keep_pacing.py [--runs 2000] [--seed 7] [--quick]
"""

import random
import sys

# ---------------------------------------------------------------- run constants (docs/37 §4)
NIGHTS = 12
BOSS_NIGHTS = {4: 2600, 8: 7000, 12: 6500}  # boss base HP (x tier HP x human scale)
DAY_SECONDS = 180
NIGHT_SECONDS = 90
BOSS_NIGHT_SECONDS = 150
SPAWN_WINDOW = 60  # normal nights: spawns during the first 60 s
EXPOSURE = 24  # seconds an enemy spends inside tower coverage before reaching the gate
H1 = 6800  # night-1 total shadow HP for scale 1
GROWTH = 1.155  # per-night HP growth
EARLY = {1: 0.55, 2: 0.75, 3: 0.9}  # tutorial-ish first nights (first 60 s must feel safe)
HEART_HP = 1000
HEART_DMG_PER_HP = 0.30  # leaked HP -> heart damage
DAWN_REPAIR = 0.25  # free heart repair each dawn (fraction of max)
BOSS_ESCAPE_DMG = 0.40  # boss alive at dawn -> heart loses 40% of max
BOUNTY_PER_HP = 0.04  # crystals paid per shadow HP killed (split, §11)
MINE_RATE = 3.0  # crystals/s base while mining
START_CRYSTALS = 150
BASE_SLOTS = 3
PADS = 48
BOT_FILL_TO = 4
BOT_MAX = 3
BOT_THREAT_WEIGHT = 0.8  # bots count 0.8 of a human for threat scaling
BOT_ECON = 0.7  # bots earn/spend at 70% of the humans' profile
THREAT_EXP = 0.75
AFK_CHANCE = 0.04  # per human per night: idle/away (no mining, no fighting) until next night
WAVE_SD = 0.10  # night-to-night wave strength noise (composition, lane split, path luck)
STARLIGHT_DPS = 0.15  # Rekindle: +15% lantern damage per Starlight

# Moon Tiers: (name, HP mult, crystal mult, Ember mult)
TIERS = [
    ("Pale", 1.0, 1.0, 1.0),
    ("Silver", 1.45, 1.2, 1.5),
    ("Violet", 2.0, 1.45, 2.2),
    ("Crimson", 2.8, 1.75, 3.2),
    ("Void", 3.9, 2.1, 4.5),
]

LVL_DPS = [1.0, 1.7, 2.8, 4.5, 7.0]  # L1..L5 multiplier
LVL_COST = [1.0, 1.2, 2.2, 4.0, 7.0]  # cost of reaching L1..L5 (x base cost)

# Lantern table (docs/37 §6). eff = (swarm, normal, armor, boss). air/reveal flags. unlock = Ember.
LANTERNS = {
    "ember": dict(cost=100, dps=14, eff=(1.0, 1.0, 0.4, 1.0), air=1, reveal=0, unlock=0),
    "pulse": dict(cost=140, dps=11, eff=(2.6, 1.0, 0.4, 0.6), air=0, reveal=0, unlock=0),
    "frost": dict(cost=160, dps=6, eff=(1.2, 1.0, 0.5, 0.8), air=1, reveal=0, unlock=40),
    "prism": dict(cost=220, dps=20, eff=(1.8, 1.0, 0.4, 0.7), air=1, reveal=0, unlock=80),
    "flare": dict(cost=260, dps=18, eff=(2.2, 1.0, 0.6, 0.8), air=0, reveal=1, unlock=140),
    "bloom": dict(cost=180, dps=3, eff=(1.0, 1.0, 0.5, 0.5), air=0, reveal=0, unlock=220),
    "firefly": dict(cost=280, dps=22, eff=(1.4, 1.0, 0.5, 0.8), air=2, reveal=0, unlock=350),
    "lighthouse": dict(cost=380, dps=26, eff=(1.6, 1.0, 0.6, 0.8), air=1, reveal=1, unlock=520),
    "sunstone": dict(cost=420, dps=34, eff=(0.5, 1.0, 1.0, 1.8), air=0, reveal=0, unlock=760),
    "mirror": dict(cost=300, dps=0, eff=(0, 0, 0, 0), air=0, reveal=0, unlock=1100),
    "aurora": dict(cost=480, dps=30, eff=(2.2, 1.0, 0.5, 0.9), air=1, reveal=0, unlock=1500),
    "halo": dict(cost=400, dps=14, eff=(1.3, 1.0, 0.6, 0.6), air=1, reveal=1, unlock=2000),
    "starfall": dict(cost=650, dps=40, eff=(2.5, 1.0, 0.8, 1.0), air=0, reveal=0, unlock=2600),
    "dawn": dict(cost=1200, dps=0, eff=(0, 0, 0, 0), air=0, reveal=0, unlock=3500),
}
UNLOCK_ORDER = sorted(LANTERNS, key=lambda k: LANTERNS[k]["unlock"])


def composition(n):
    """HP share per class on night n: swarm, normal, armor, air, cloak (docs/37 §8)."""
    swarm = 0.55 - 0.02 * n
    armor = 0.0 if n < 3 else min(0.05 + 0.02 * (n - 3), 0.22)
    air = 0.0 if n < 2 else min(0.06 + 0.01 * n, 0.16)
    cloak = 0.0 if n < 5 else min(0.04 + 0.01 * (n - 5), 0.10)
    normal = 1 - swarm - armor - air - cloak
    return swarm, normal, armor, air, cloak


# Keeper upgrades bought with Ember (docs/37 §10.2): id -> (max lv, base cost, growth)
UPGRADES = {
    "mine": (10, 40, 1.40),  # +10% mining / lv
    "start": (5, 60, 1.50),  # +80 start crystals / lv
    "bat": (10, 40, 1.40),  # +15% bat damage / lv
    "ward": (5, 80, 1.50),  # +10% heart HP / lv
    "slot": (3, 400, 2.50),  # +1 tower slot / lv
    "burst": (5, 60, 1.50),  # +10% burst charge / lv
    "focus": (10, 60, 1.45),  # +6% lantern damage / lv (Light Focus)
}


def upgrade_cost(uid, lv):
    _, base, g = UPGRADES[uid]
    return int(base * g**lv)


class Profile:
    """What a player brings to a run (permanent progression)."""

    def __init__(self, unlocked=("ember", "pulse"), up=None, skill=0.15, starlight=0):
        self.unlocked = set(unlocked)
        self.up = dict.fromkeys(UPGRADES, 0)
        if up:
            self.up.update(up)
        self.skill = skill  # placement noise sd (smaller = better player)
        self.starlight = starlight  # Rekindle count

    def slots(self):
        return BASE_SLOTS + self.up["slot"]


PROFILES = {
    "new (D0)": Profile(),
    "D3": Profile(("ember", "pulse", "frost", "prism", "flare"), {"mine": 3, "start": 1, "bat": 2, "focus": 1}, 0.12),
    "D7": Profile(
        ("ember", "pulse", "frost", "prism", "flare", "bloom", "firefly", "lighthouse"),
        {"mine": 6, "start": 3, "bat": 5, "ward": 2, "slot": 1, "burst": 2, "focus": 4},
        0.10,
    ),
    "D28": Profile(
        tuple(LANTERNS),
        {"mine": 10, "start": 5, "bat": 10, "ward": 5, "slot": 3, "burst": 5, "focus": 10},
        0.08,
        starlight=1,
    ),
}


class Participant:
    def __init__(self, profile, rng, bot=False):
        self.p = profile
        self.bot = bot
        self.rng = rng
        self.crystals = START_CRYSTALS + 80 * profile.up["start"]
        self.towers = []  # [type, level, quality]
        self.afk = False

    def econ(self):
        e = (1 + 0.1 * self.p.up["mine"]) * (1 + 0.1 * self.p.starlight)
        return e * (BOT_ECON if self.bot else 1.0)

    def quality(self):
        """Placement / targeting quality of a new tower (pad choice, lane coverage) x Starlight damage."""
        sd = 0.12 if self.bot else self.p.skill
        q = max(0.5, self.rng.gauss(0.92 if self.bot else 1.0, sd))
        return q * (1 + STARLIGHT_DPS * self.p.starlight) * (1 + 0.06 * self.p.up["focus"])


def tower_eff_dps(t, lv, q, comp, reveal):
    L = LANTERNS[t]
    swarm, normal, armor, air, cloak = comp
    s_e, n_e, a_e, _ = L["eff"]
    mix = swarm * s_e + normal * n_e + armor * a_e + air * (L["air"] * 1.0) + cloak * (1.0 if reveal else 0.0)
    return L["dps"] * LVL_DPS[lv - 1] * q * mix


def team_defence(parts, comp, boss=False):
    towers = [(t, lv, q) for pt in parts for (t, lv, q) in pt.towers]
    reveal = any(LANTERNS[t]["reveal"] for t, _, _ in towers)
    dps = [tower_eff_dps(t, lv, q, comp, reveal) for t, lv, q in towers]
    boss_dps = sum(LANTERNS[t]["dps"] * LVL_DPS[lv - 1] * q * LANTERNS[t]["eff"][3] for t, lv, q in towers)
    total = sum(dps)
    frost = sum(1 for t, _, _ in towers if t == "frost")
    total *= 1 + 0.08 * min(frost, 3)
    boss_dps *= 1 + 0.08 * min(frost, 3)
    mirrors = sum(1 for t, _, _ in towers if t == "mirror")
    if mirrors:
        top = sorted(dps, reverse=True)[: 4 * mirrors]
        total += 0.25 * sum(top)
    halo = any(t == "halo" for t, _, _ in towers)
    dawn = any(t == "dawn" for t, _, _ in towers)
    # players: bat + light burst
    pl = 0.0
    for pt in parts:
        if pt.bot:
            pl += 12
        elif not pt.afk:
            pl += 16 * (1 + 0.15 * pt.p.up["bat"]) * 0.55 + 5 * (1 + 0.1 * pt.p.up["burst"])
    return total + pl, boss_dps + 0.6 * pl, halo, dawn


def buy_phase(pt, comp_next, crystals_mult):
    """Greedy: best marginal effective DPS per crystal (new tower on free slot or upgrade)."""
    unlocked = [t for t in pt.p.unlocked if t not in ("mirror", "dawn")]
    while True:
        best, best_ratio = None, 0.0
        if len(pt.towers) < pt.p.slots():
            for t in unlocked:
                c = LANTERNS[t]["cost"] * crystals_mult
                if c <= pt.crystals:
                    r = tower_eff_dps(t, 1, 1.0, comp_next, True) / c
                    if t == "bloom":
                        r *= 0.0  # bloom is bought by rule below
                    if r > best_ratio:
                        best, best_ratio = ("new", t, c), r
        for i, (t, lv, q) in enumerate(pt.towers):
            if lv < 5:
                c = LANTERNS[t]["cost"] * LVL_COST[lv] * crystals_mult  # price of the next level
                if c <= pt.crystals:
                    gain = tower_eff_dps(t, lv + 1, q, comp_next, True) - tower_eff_dps(t, lv, q, comp_next, True)
                    r = gain / c
                    if r > best_ratio:
                        best, best_ratio = ("up", i, c), r
        if not best:
            return
        if best[0] == "new":
            pt.towers.append([best[1], 1, pt.quality()])
        else:
            pt.towers[best[1]][1] += 1
        pt.crystals -= best[2]


def special_buys(pt, night, crystals_mult, server_has_dawn):
    # Bloom early (economy), mirror / dawn engine when affordable later (one dawn per server)
    if "bloom" in pt.p.unlocked and night <= 2 and len(pt.towers) < pt.p.slots():
        c = LANTERNS["bloom"]["cost"] * crystals_mult
        if pt.crystals >= c and not any(t[0] == "bloom" for t in pt.towers):
            pt.towers.append(["bloom", 1, 1.0])
            pt.crystals -= c
    if "mirror" in pt.p.unlocked and night >= 5 and len(pt.towers) < pt.p.slots():
        c = LANTERNS["mirror"]["cost"] * crystals_mult
        if pt.crystals >= c * 1.5 and not any(t[0] == "mirror" for t in pt.towers):
            pt.towers.append(["mirror", 1, 1.0])
            pt.crystals -= c
    if "dawn" in pt.p.unlocked and not server_has_dawn and night >= 6 and len(pt.towers) < pt.p.slots():
        c = LANTERNS["dawn"]["cost"] * crystals_mult
        if pt.crystals >= c:
            pt.towers.append(["dawn", 1, 1.0])
            pt.crystals -= c
            return True
    return server_has_dawn


def night_fight(total_hp, defence, boss_hp, boss_dps, seconds, dawn_engine, rng):
    """Per-second queue. Returns (leaked HP, boss alive)."""
    queue = []  # [age, hp]
    leaked = 0.0
    spawn_window = SPAWN_WINDOW
    # three bursts: 25% / 35% / 40%
    profile = [0.25 / 20] * 20 + [0.35 / 20] * 20 + [0.40 / 20] * 20
    wobble = max(0.7, rng.gauss(1.0, WAVE_SD))
    total_hp *= wobble
    if dawn_engine:
        total_hp *= 0.80  # one mini-sunrise wipes ~20% of the night's HP
    boss_left = boss_hp
    boss_share = 0.5 if boss_hp > 0 else 0.0
    for s in range(seconds):
        if s < spawn_window:
            queue.append([0, total_hp * profile[s]])
        dmg = defence * (1 - boss_share) if boss_left > 0 else defence
        while dmg > 0 and queue:
            if queue[0][1] <= dmg:
                dmg -= queue[0][1]
                queue.pop(0)
            else:
                queue[0][1] -= dmg
                dmg = 0
        if boss_left > 0 and s >= 10:
            boss_left -= boss_dps * boss_share  # half of the team focuses the boss
        for e in queue:
            e[0] += 1
        while queue and queue[0][0] >= EXPOSURE:
            leaked += queue.pop(0)[1]
    # anything still in the queue at dawn burns in sunlight (no leak)
    return leaked, boss_left > 0


def run_once(humans, profile, tier, rng, bots=True):
    tname, hp_m, cr_m, _ = TIERS[tier]
    n_bots = min(BOT_MAX, max(0, BOT_FILL_TO - humans)) if bots and humans > 0 else 0
    parts = [Participant(profile, rng) for _ in range(humans)]
    parts += [Participant(profile, rng, bot=True) for _ in range(n_bots)]  # bots mirror the humans' profile at 80% econ
    # pads cap: 36 pads shared
    eff_players = humans + BOT_THREAT_WEIGHT * n_bots
    scale = eff_players**THREAT_EXP
    ward = profile.up["ward"]
    heart_max = HEART_HP * (1 + 0.1 * ward)
    heart = heart_max
    has_dawn = False
    for night in range(1, NIGHTS + 1):
        comp = composition(night)
        # day: mining + bloom
        for pt in parts:
            pt.afk = (not pt.bot) and rng.random() < AFK_CHANCE
            uptime = 0.55 if pt.bot else (0.0 if pt.afk else rng.uniform(0.5, 0.85))
            blooms = sum(1 for t in pt.towers if t[0] == "bloom")
            pt.crystals += (MINE_RATE * uptime + 1.6 * blooms) * DAY_SECONDS * pt.econ() * cr_m
        pads_used = 0
        for pt in parts:
            if pt.afk:
                pads_used += len(pt.towers)
                continue
            has_dawn = special_buys(pt, night, 1.0, has_dawn)
            buy_phase(pt, comp, 1.0)
            pads_used += len(pt.towers)
            # leftover crystals (slots / levels capped) go into the Heart brazier: 0.5 crystal per HP
            if heart < heart_max and pt.crystals > 0:
                fix = min(heart_max - heart, pt.crystals / (0.5 * cr_m))
                heart += fix
                pt.crystals -= fix * 0.5 * cr_m
        # enforce pad cap (late towers simply not placed)
        if pads_used > PADS:
            excess = pads_used - PADS
            for pt in reversed(parts):
                while excess > 0 and len(pt.towers) > 1:
                    pt.crystals += LANTERNS[pt.towers[-1][0]]["cost"]
                    pt.towers.pop()
                    excess -= 1
        total_hp = H1 * GROWTH ** (night - 1) * EARLY.get(night, 1.0) * hp_m * scale
        boss_hp = BOSS_NIGHTS.get(night, 0) * hp_m**0.85 * scale
        if boss_hp:
            total_hp *= 0.6
        defence, boss_dps, halo, dawn = team_defence(parts, comp, boss=bool(boss_hp))
        secs = BOSS_NIGHT_SECONDS if boss_hp else NIGHT_SECONDS
        leaked, boss_alive = night_fight(total_hp, defence, boss_hp, boss_dps, secs, dawn, rng)
        heart_dmg = leaked * HEART_DMG_PER_HP / hp_m ** 0.5
        if halo:
            heart_dmg = max(0.0, heart_dmg - 3 * secs)
        if boss_alive:
            heart_dmg += BOSS_ESCAPE_DMG * heart_max
        heart -= heart_dmg
        if heart <= 0:
            return night - 1  # nights survived
        # bounty: killed HP pays crystals (40% pool equal, 60% contribution ~ tower share)
        killed = total_hp - leaked + (boss_hp if not boss_alive else 0)
        bounty = killed * BOUNTY_PER_HP / hp_m * cr_m
        pool = bounty * 0.4 / len(parts)
        tower_share = [sum(LVL_DPS[t[1] - 1] * LANTERNS[t[0]]["dps"] for t in pt.towers) + 1 for pt in parts]
        tot = sum(tower_share)
        for pt, sh in zip(parts, tower_share):
            pt.crystals += pool + bounty * 0.6 * sh / tot
        heart = min(heart_max, heart + DAWN_REPAIR * heart_max)
    return NIGHTS


def ember_for(nights_survived, tier, starlight=0):
    return sum(night_ember(n, tier, starlight) for n in range(1, nights_survived + 1))


def run_minutes(nights_survived):
    # day ~150 s average (READY skip), night 90 s / boss night 150 s, + 30 s results when the run ends
    t = 0
    for n in range(1, min(NIGHTS, nights_survived + 1) + 1):
        t += 150 + (BOSS_NIGHT_SECONDS if n in BOSS_NIGHTS else NIGHT_SECONDS)
    return (t + 30) / 60


TABLE_TIERS = {"new (D0)": (0,), "D3": (0, 1), "D7": (0, 1, 2), "D28": (1, 2, 3, 4)}


def survival_table(runs, seed, groups=(1, 4, 8)):
    rng = random.Random(seed)
    rows = []
    for pname, tiers in TABLE_TIERS.items():
        for tier in tiers:
            for h in groups:
                res = [run_once(h, PROFILES[pname], tier, rng) for _ in range(runs)]
                surv = [sum(1 for r in res if r >= n) / runs for n in range(1, NIGHTS + 1)]
                avg = sum(res) / runs
                rows.append((pname, TIERS[tier][0], h, surv, avg))
    return rows


def print_survival(rows):
    print("| 프로필 | Moon Tier | 인원 | N1 | N3 | N4(보스) | N6 | N8(보스) | N10 | N12(Dawn) | 평균 생존 밤 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for pname, tname, h, s, avg in rows:
        pick = [s[0], s[2], s[3], s[5], s[7], s[9], s[11]]
        cells = " | ".join(f"{v * 100:.0f}%" for v in pick)
        hl = f"{h}" + (" (+봇 3)" if h == 1 else "")
        print(f"| {pname} | {tname} | {hl} | {cells} | {avg:.1f} |")


# ---------------------------------------------------------------- progression
SESSIONS = {"casual": [15], "regular": [20, 20], "engaged": [25, 25, 25], "hardcore": [30, 30, 30, 30]}
ARCHETYPES = {k: sum(v) for k, v in SESSIONS.items()}  # minutes / day
DAILY_EMBER = 30  # 7-day login track average (docs/37 §10.4)
SEAL_MIN_NIGHTS = 2  # Moon Seal = present & survived a boss night, and in that run for >= 2 nights (anti late-join farm)


def night_ember(n, tier, starlight):
    e = 25 + 5 * n + {4: 60, 8: 120, 12: 400}.get(n, 0)  # night 12 = boss 200 + Dawn 200
    return e * TIERS[tier][3] * (1 + 0.2 * starlight)


def night_minutes(n):
    return (150 + (BOSS_NIGHT_SECONDS if n in BOSS_NIGHTS else NIGHT_SECONDS)) / 60


def play_session(minutes, prof, max_tier, rng, group=4):
    """Join a public server mid-run (random night), play until the session ends.
    Returns (ember, tier, seals) where seals = boss nights beaten while present.
    Lost runs restart at night 1 in the same server."""
    ember, seals = 0.0, set()
    tier = max_tier if rng.random() < 0.6 or max_tier == 0 else max_tier - 1  # tier vote result
    start = rng.randint(1, NIGHTS)
    left = minutes
    while left > 0:
        res = run_once(group, prof, tier, rng)  # nights this server run survives
        present = 0
        for n in range(start, NIGHTS + 1):
            if left <= 0:
                break
            left -= night_minutes(n)
            if left < 0:
                break  # left before dawn: no credit for this night
            if n > res:
                break  # keep fell this night
            present += 1
            ember += night_ember(n, tier, prof.starlight)
            if n in BOSS_NIGHTS and present >= SEAL_MIN_NIGHTS:
                seals.add(n)
        start = 1
        left -= 0.5  # results screen
    return ember, tier, seals


def progression(runs_cache_seed, days=30, group=4):
    rng = random.Random(runs_cache_seed)
    out = {}
    for arch, sessions in SESSIONS.items():
        prof = Profile()
        prof.skill = 0.15
        ember = 0.0
        max_tier = 0
        rekindles = 0
        log = {}
        got = {t: set() for t in range(len(TIERS))}  # Moon Seals per tier (boss nights 4/8/12)
        earned = 0.0
        for day in range(1, days + 1):
            ember += DAILY_EMBER
            before = ember
            for minutes in sessions:
                e, tier, seals = play_session(minutes, prof, max_tier, rng, group)
                ember += e
                got[tier] |= seals
                if tier == max_tier and len(got[tier]) == len(BOSS_NIGHTS) and max_tier < len(TIERS) - 1:
                    max_tier += 1
                    log.setdefault(f"tier {TIERS[max_tier][0]} 해금", day)
            earned += ember - before + DAILY_EMBER
            if day in (1, 7, 28):
                log[f"ember/day D{day}"] = round(earned / day)
            # spend: cheap upgrades (<= 35% of the next unlock) first, otherwise save for the next lantern
            spent = True
            while spent:
                spent = False
                nxt = next((t for t in UNLOCK_ORDER if t not in prof.unlocked), None)
                cands = [(upgrade_cost(u, prof.up[u]), u) for u in UPGRADES if prof.up[u] < UPGRADES[u][0]]
                if cands and nxt:
                    c, u = min(cands)
                    if c <= ember and c <= 0.35 * LANTERNS[nxt]["unlock"]:
                        ember -= c
                        prof.up[u] += 1
                        spent = True
                        continue
                if nxt and ember >= LANTERNS[nxt]["unlock"]:
                    ember -= LANTERNS[nxt]["unlock"]
                    prof.unlocked.add(nxt)
                    spent = True
                    n = len(prof.unlocked)
                    if n in (3, 5, 8, 11, 14):
                        log.setdefault(f"랜턴 {n}종", day)
                    continue
                cands = [(upgrade_cost(u, prof.up[u]), u) for u in UPGRADES if prof.up[u] < UPGRADES[u][0]]
                if cands:
                    c, u = min(cands)
                    if ember >= c and (nxt is None or ember - c >= 0.5 * LANTERNS[nxt]["unlock"]):
                        ember -= c
                        prof.up[u] += 1
                        spent = True
            prof.skill = max(0.08, 0.15 - 0.004 * day)
            # Rekindle r+1: Dawn on tier >= Silver+r (next tier unlocked) and >= 10 lanterns -> reset upgrades, +1 Starlight
            if max_tier >= 2 + rekindles and len(prof.unlocked) >= 10 and rekindles < 3:
                rekindles += 1
                prof.starlight = rekindles
                prof.up = dict.fromkeys(UPGRADES, 0)
                log.setdefault(f"Rekindle {rekindles}", day)
        out[arch] = log
    return out


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass
    runs = 2000
    seed = 7
    args = sys.argv[1:]
    if "--runs" in args:
        runs = int(args[args.index("--runs") + 1])
    if "--seed" in args:
        seed = int(args[args.index("--seed") + 1])
    if "--quick" in args:
        runs = 300
    print(f"## 생존 확률 (runs={runs}, seed={seed}, 봇은 4명까지 채움)\n")
    print_survival(survival_table(runs, seed))
    print("\n## 봇 없이 1명 (참고)\n")
    rng = random.Random(seed + 1)
    for pname in ("new (D0)", "D7"):
        res = [run_once(1, PROFILES[pname], 0, rng, bots=False) for _ in range(runs)]
        s = [sum(1 for r in res if r >= n) / runs for n in (1, 4, 8, 12)]
        print(f"- {pname} Pale 1명 봇 없음: N1 {s[0]:.0%} / N4 {s[1]:.0%} / N8 {s[2]:.0%} / N12 {s[3]:.0%}")
    print("\n## 런 길이 / Ember\n")
    for n in (3, 6, 12):
        print(f"- {n}밤 생존: 약 {run_minutes(n):.0f}분, Pale Ember {ember_for(n, 0):.0f} / Silver {ember_for(n, 1):.0f}")
    print("\n## 진행 (4인 서버, 30일)\n")
    prog = progression(seed + 2)
    keys = ["랜턴 3종", "랜턴 5종", "랜턴 8종", "랜턴 11종", "랜턴 14종", "tier Silver 해금", "tier Violet 해금", "tier Crimson 해금", "Rekindle 1"]
    print("| 아키타입 | 분/일 | " + " | ".join(keys) + " |")
    print("|---|---|" + "---|" * len(keys))
    for arch, log in prog.items():
        cells = " | ".join(f"D{log[k]}" if k in log else "-" for k in keys)
        print(f"| {arch} | {ARCHETYPES[arch]} | {cells} |")
    print("\n평균 Ember/일 (누적 평균, 일일 보상 포함):")
    for arch, log in prog.items():
        print(f"- {arch}: D1 {log.get('ember/day D1')} / D7 {log.get('ember/day D7')} / D28 {log.get('ember/day D28')}")


if __name__ == "__main__":
    main()
