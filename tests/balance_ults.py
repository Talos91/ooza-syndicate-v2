"""Ultimates tables (2026-10-27 rework): python -I tests/balance_ults.py <dir> [noult-prefix] [matrix-prefix]
noult: tests/balance_study.gd --study=habit --habits=noult (a stock seat vs the same faction that never casts its ultimate).
Lift = stock win rate - 50. Also: the stock seat's ultimate casts per match, and the win rate when it cast >= 2 times.
matrix: --study=base 1v1 (every ordered faction pair): each faction's overall win rate (mirrors left out)."""
import glob, json, sys
from collections import defaultdict

d = sys.argv[1]
pn = sys.argv[2] if len(sys.argv) > 2 else "noult"
pm = sys.argv[3] if len(sys.argv) > 3 else "mat"
ULT = {"vex": "rewire", "null": "echo_split", "bloom": "superbloom", "ember": "core_meltdown", "solar": "relay_aegis"}
FACS = ["vex", "null", "bloom", "ember", "solar"]


def load(prefix):
    return [json.loads(l) for p in glob.glob(f"{d}/{prefix}_*.jsonl") for l in open(p) if l.strip()]


def ci(x):
    n = len(x)
    if n == 0:
        return float("nan")
    p = sum(x) / n
    return 1.96 * (p * (1 - p) / n) ** 0.5 * 100


def ult_casts(r, seat, uid=None):
    """Activations only: Rewire's free relay fires are logged as ultimate casts too, so casts within 20 s count once."""
    n, last = 0, -99.0
    for x in r["casts"]:
        if x[1] == seat and x[3] == "ultimate" and (uid is None or x[2] == uid):
            if x[0] - last >= 20.0:
                n += 1
            last = x[0] if x[0] - last >= 20.0 else last
    return n


def s(r, seat):
    w = r["winner"]
    return 0.5 if w == "" else (1.0 if w == seat else 0.0)


rows = load(pn)
if rows:
    print(f"## Cast vs no-cast (mirror, Expert, {len(rows)} matches)")
    print("| faction | ultimate | stock WR | lift | +- | n | casts/match (mean) | cast >= 2 | WR when cast >= 2 | n |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for f in FACS:
        g, g2, nc = [], [], []
        for r in rows:
            if r["spec"][r["vseat"]] != f:
                continue
            stock = "B" if r["vseat"] == "A" else "A"         # vseat plays the habit (noult)
            sc = s(r, stock)
            g.append(sc)
            c = ult_casts(r, stock, ULT[f])
            nc.append(c)
            if c >= 2:
                g2.append(sc)
        if not g:
            continue
        wr = sum(g) / len(g) * 100
        w2 = sum(g2) / len(g2) * 100 if g2 else float("nan")
        print(f"| {f} | {ULT[f]} | {wr:.1f} | {wr - 50:+.1f} | {ci(g):.1f} | {len(g)} | {sum(nc) / len(nc):.2f} | "
              f"{len(g2) / len(g) * 100:.0f} % | {w2:.1f} | {len(g2)} |")

rows = load(pm)
if rows:
    print(f"\n## Faction matrix (Expert 1v1, {len(rows)} matches, both seats, mirrors left out)")
    tot = defaultdict(list)
    cell = defaultdict(list)
    casts = defaultdict(list)
    for r in rows:
        a, b = r["spec"]["A"], r["spec"]["B"]
        for seat, f, o in (("A", a, b), ("B", b, a)):
            casts[f].append(ult_casts(r, seat))
            if f == o:
                continue
            tot[f].append(s(r, seat))
            cell[(f, o)].append(s(r, seat))
    print("| faction | WR | +- | n | ult casts/match |")
    print("|---|---|---|---|---|")
    for f in sorted(FACS, key=lambda f: -sum(tot[f]) / max(1, len(tot[f]))):
        print(f"| {f} | {sum(tot[f]) / len(tot[f]) * 100:.1f} | {ci(tot[f]):.1f} | {len(tot[f])} | {sum(casts[f]) / len(casts[f]):.2f} |")
    print("\n| row vs col | " + " | ".join(FACS) + " |")
    print("|---" * (len(FACS) + 1) + "|")
    for f in FACS:
        print(f"| {f} | " + " | ".join("-" if f == o else f"{sum(cell[(f, o)]) / len(cell[(f, o)]) * 100:.0f}" for o in FACS) + " |")
