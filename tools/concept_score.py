"""Concept scoring with weight sensitivity (docs/12 §2-3).

Raw scores are on each criterion's base weight (docs/04 §1: 20/25/20/15/20).
Each scenario rescales them: score_c * (scenario_weight_c / base_weight_c).
Also runs a random-weight Monte Carlo (weights ~ Dirichlet around the base) to report how often each concept ranks first.

Usage: python -I tools/concept_score.py [--set 2026-10-27]
"""

import random
import sys

CRITERIA = ["demand", "rfy", "revenue", "originality", "automation"]
BASE = [20, 25, 20, 15, 20]

CONCEPTS = {
    "A merge factory": [17, 22, 17, 12, 17],
    "E crystal garden": [18, 22, 16, 8, 17],
    "D cube heist": [20, 20, 18, 6, 15],
    "H fishing": [17, 21, 15, 9, 14],
    "G co-op TD": [15, 20, 15, 9, 16],
    "F egg hatching": [17, 19, 14, 6, 16],
    "I physics arena": [14, 18, 13, 11, 12],
    "B co-op horror": [15, 21, 14, 8, 8],
    "J anime RPG": [15, 19, 17, 6, 7],
    "C stack party": [9, 13, 9, 12, 15],
}

# 2026-10-27 portfolio round (docs/32). Scores use research/2026-10-27-*.md;
# automation includes reuse of the Merge Cube Factory code.
CONCEPTS_2026_10_27 = {
    "starfall heist (steal+collect)": [20, 21, 18, 7, 17],
    "glow garden (grow timer)": [18, 22, 16, 9, 18],
    "aura forge (free RNG roll)": [16, 20, 13, 8, 19],
    "lava rush (risk carry runner)": [17, 21, 15, 10, 16],
    "lantern keep (day build/night defend)": [15, 21, 15, 12, 13],
    "fishing": [15, 20, 14, 8, 14],
    "swing obby tycoon": [14, 19, 13, 10, 13],
    "co-op TD": [15, 20, 15, 9, 13],
    "co-op horror": [15, 21, 14, 8, 8],
}

SCENARIOS = {
    "base": [20, 25, 20, 15, 20],
    "revenue-heavy": [20, 20, 35, 10, 15],
    "demand-heavy": [35, 20, 20, 10, 15],
    "originality-light": [25, 25, 25, 5, 20],
    "automation-light": [20, 30, 25, 15, 10],
}


def score(raw, weights):
    return sum(r * w / b for r, w, b in zip(raw, weights, BASE))


def ranking(weights):
    return sorted(CONCEPTS, key=lambda name: -score(CONCEPTS[name], weights))


def main():
    global CONCEPTS
    if "--set" in sys.argv and sys.argv[sys.argv.index("--set") + 1] == "2026-10-27":
        CONCEPTS = CONCEPTS_2026_10_27
    print("| rank | concept | base score |")
    print("|---|---|---|")
    for i, c in enumerate(ranking(BASE), 1):
        print(f"| {i} | {c} | {score(CONCEPTS[c], BASE):.1f} |")
    print()
    print("| scenario | weights | 1st | 2nd | 3rd |")
    print("|---|---|---|---|---|")
    for name, w in SCENARIOS.items():
        r = ranking(w)
        cells = [f"{c} ({score(CONCEPTS[c], w):.1f})" for c in r[:3]]
        print(f"| {name} | {'/'.join(map(str, w))} | " + " | ".join(cells) + " |")

    rng = random.Random(20261017)
    trials = 20000
    first = {c: 0 for c in CONCEPTS}
    top3 = {c: 0 for c in CONCEPTS}
    for _ in range(trials):
        # Dirichlet(alpha = base/2) keeps the base as the mean but allows large swings.
        g = [rng.gammavariate(b / 2, 1) for b in BASE]
        s = sum(g)
        w = [x / s * 100 for x in g]
        r = ranking(w)
        first[r[0]] += 1
        for c in r[:3]:
            top3[c] += 1
    print()
    print(f"Monte Carlo ({trials} random weightings, Dirichlet alpha = base/2)")
    print("| concept | rank 1 | top 3 |")
    print("|---|---|---|")
    for c in sorted(CONCEPTS, key=lambda c: -top3[c]):
        if top3[c] == 0:
            continue
        print(f"| {c} | {first[c] / trials:.1%} | {top3[c] / trials:.1%} |")

    # Raw scores are judgment calls: perturb each by a uniform integer in [-2, +2] (base weights).
    first = {c: 0 for c in CONCEPTS}
    for _ in range(trials):
        noisy = {c: [r + rng.randint(-2, 2) for r in raw] for c, raw in CONCEPTS.items()}
        best = max(noisy, key=lambda c: score(noisy[c], BASE))
        first[best] += 1
    print()
    print(f"Raw-score noise ({trials} trials, each raw score +/-2, base weights)")
    print("| concept | rank 1 |")
    print("|---|---|")
    for c in sorted(CONCEPTS, key=lambda c: -first[c]):
        if first[c]:
            print(f"| {c} | {first[c] / trials:.1%} |")


if __name__ == "__main__":
    main()
