"""Tables for the balance study: python -I tests/balance_report.py <dir with *.jsonl> [prefix]  (see tests/balance_study.gd)."""
import glob, json, sys, statistics as st
from collections import defaultdict

d = sys.argv[1]
prefix = sys.argv[2] if len(sys.argv) > 2 else ""
rows = []
for p in glob.glob(f"{d}/{prefix}*.jsonl"):
    for line in open(p):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
FACS = ["vex", "null", "bloom", "ember", "solar"]


def side(r, seat):
    return r["teams"].get(seat, seat) if r["teams"] else seat


def score(r, seat):
    """1 win, 0.5 draw, 0 loss for `seat` (team modes: its side)."""
    w = r["winner"]
    if w == "":
        return 0.5
    return 1.0 if side(r, w) == side(r, seat) else 0.0


def wr(xs):
    return (sum(xs) / len(xs) * 100.0) if xs else float("nan")


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def wilson(w, n):
    if n == 0:
        return (0, 0)
    z = 1.96
    p = w / n
    c = (p + z * z / (2 * n)) / (1 + z * z / n)
    h = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / (1 + z * z / n)
    return (round((c - h) * 100), round((c + h) * 100))


def seats_of(r):
    return sorted(r["spec"].keys())


modes = sorted(set(r["mode"] for r in rows))
for mode in modes:
    for level in sorted(set(r["level"] for r in rows if r["mode"] == mode)):
        R = [r for r in rows if r["mode"] == mode and r["level"] == level]
        print(f"\n=================== {mode} {level}: {len(R)} matches, {len(set(r['map'] for r in R))} maps ===================")
        # ---- 1 faction matrix
        if mode == "1v1":
            print("\n## Faction matrix (row's win % vs column; both seats pooled; mirror excluded)  [n per cell]")
            print("      " + " ".join(f"{f:>12}" for f in FACS) + "   overall(non-mirror) n")
            tot = {}
            for a in FACS:
                cells = []
                allx = []
                for b in FACS:
                    xs = []
                    for r in R:
                        if r["spec"]["A"] == a and r["spec"]["B"] == b:
                            xs.append(score(r, "A"))
                        elif r["spec"]["B"] == a and r["spec"]["A"] == b:
                            xs.append(score(r, "B"))
                    if a == b:
                        cells.append(f"{'--':>12}")
                    else:
                        allx += xs
                        cells.append(f"{wr(xs):6.1f} [{len(xs):3d}]")
                tot[a] = allx
                print(f"{a:>6}" + " ".join(cells) + f"   {wr(allx):5.1f}  {len(allx)}  CI{wilson(sum(allx), len(allx))}")
        else:
            print("\n## Faction win % (a seat of that faction; side result) in 2v2")
            for f in FACS:
                xs = [score(r, s) for r in R for s in seats_of(r) if r["spec"][s] == f]
                print(f"  {f:>6}: {wr(xs):5.1f} n={len(xs)} CI{wilson(sum(xs), len(xs))}")
        # ---- faction expected score for later residuals
        fac_wr = {}
        for f in FACS:
            xs = [score(r, s) for r in R for s in seats_of(r) if r["spec"][s] == f]
            fac_wr[f] = sum(xs) / len(xs) if xs else 0.5
        # ---- 2 powers
        print("\n## Powers: seat has it in its loadout. WR (raw), faction-adjusted delta (pp vs its faction's expectation), casts/seat/match, n seats")
        pw = defaultdict(list)
        for r in R:
            for s in seats_of(r):
                lo = r["loadouts"][s]
                for slot in ("active", "map", "ultimate"):
                    pw[(slot, lo[slot])].append((score(r, s), fac_wr[r["spec"][s]], sum(1 for c in r["casts"] if c[1] == s and c[2] == lo[slot]), r["spec"][s]))
        for (slot, pid), v in sorted(pw.items()):
            raw = wr([x[0] for x in v])
            exp = wr([x[1] for x in v])
            casts = sum(x[2] for x in v) / len(v)
            print(f"  {slot:>8} {pid:>14}: WR {raw:5.1f} (exp {exp:5.1f}, delta {raw - exp:+5.1f}) casts {casts:4.1f} n={len(v)} factions={sorted(set(x[3] for x in v))}")
        # win rate when a power was cast at all vs not
        print("\n## Powers: WR when the seat cast that power >=1 / >=3 times vs 0 (same power in loadout)")
        for (slot, pid), v in sorted(pw.items()):
            z = [x for x in v if x[2] == 0]
            a = [x for x in v if x[2] >= 1]
            b = [x for x in v if x[2] >= 3]
            print(f"  {pid:>14}: cast0 WR {wr([x[0] for x in z]):5.1f} (n={len(z)})  cast>=1 {wr([x[0] for x in a]):5.1f} (n={len(a)})  cast>=3 {wr([x[0] for x in b]):5.1f} (n={len(b)})")
        # ---- structures
        print("\n## Structures built by a seat (build_start): WR built>=1 vs 0, avg count when built, share of seats")
        for kind in ("laser", "machinegoon", "forge", "monster_hub"):
            a, z, cnt = [], [], []
            for r in R:
                for s in seats_of(r):
                    n = sum(1 for b in r["builds"] if b[1] == s and b[2] == kind)
                    (a if n else z).append(score(r, s))
                    if n:
                        cnt.append(n)
            tot = len(a) + len(z)
            print(f"  {kind:>12}: built by {len(a) / tot * 100:4.1f}% of seats (n={len(a)}), WR {wr(a):5.1f}  vs not built WR {wr(z):5.1f} (n={len(z)}), avg count {sum(cnt) / max(1, len(cnt)):.1f}")
        for kind in ("laser", "machinegoon", "forge", "monster_hub"):
            line = f"  by faction, {kind}: "
            for f in FACS:
                xs = [(sum(1 for b in r["builds"] if b[1] == s and b[2] == kind) > 0, score(r, s)) for r in R for s in seats_of(r) if r["spec"][s] == f]
                line += f"{f} {sum(1 for x in xs if x[0]) / len(xs) * 100:.0f}% (WR {wr([x[1] for x in xs if x[0]]):.0f}/{wr([x[1] for x in xs if not x[0]]):.0f}) "
            print(line)
        ups = []
        for r in R:
            for s in seats_of(r):
                ups.append((sum(1 for b in r["builds"] if b[1] == s and b[2] == "vat"), score(r, s)))
        for lo_, hi_ in ((0, 1), (2, 3), (4, 5), (6, 99)):
            xs = [x[1] for x in ups if lo_ <= x[0] <= hi_]
            print(f"  vat builds/upgrades {lo_}-{hi_}: WR {wr(xs):5.1f} n={len(xs)}")
        mon = []
        for r in R:
            for s in seats_of(r):
                mon.append((r["monsters"].get(s, 0), score(r, s)))
        for lo_, hi_ in ((0, 0), (1, 2), (3, 99)):
            xs = [x[1] for x in mon if lo_ <= x[0] <= hi_]
            print(f"  monster takes {lo_}-{hi_}: WR {wr(xs):5.1f} n={len(xs)}")
        bu = []
        for r in R:
            for s in seats_of(r):
                bu.append((r["bursts"].get(s, 0), score(r, s)))
        for lo_, hi_ in ((0, 0), (1, 5), (6, 99)):
            xs = [x[1] for x in bu if lo_ <= x[0] <= hi_]
            print(f"  laser bursts {lo_}-{hi_}: WR {wr(xs):5.1f} n={len(xs)}")
        # ---- 3 length
        ts = [r["t"] for r in R]
        print("\n## Match length (s): median %.0f p10 %.0f p90 %.0f mean %.0f min %.0f max %.0f" % (st.median(ts), pct(ts, .1), pct(ts, .9), st.mean(ts), min(ts), max(ts)))
        ls = [r for r in R if r["ls_t"] > 0]
        early = [r for r in R if r["ls_t"] < 0]
        forced = [r for r in R if r["forced"]]
        draws = [r for r in R if r["winner"] == ""]
        print(f"  ended before Last Stand: {len(early) / len(R) * 100:.1f}% | reached Last Stand: {len(ls) / len(R) * 100:.1f}% | hit the 7:00 hard end: {len(forced) / len(R) * 100:.1f}% | draws {len(draws) / len(R) * 100:.1f}%")
        buckets = [(0, 120), (120, 180), (180, 240), (240, 300), (300, 360), (360, 421)]
        print("  length buckets: " + " ".join(f"{a}-{b}s {sum(1 for t in ts if a <= t < b) / len(ts) * 100:.0f}%" for a, b in buckets))
        if ls:
            lts = [r["t"] - r["ls_t"] for r in ls]
            print(f"  after LS start: median {st.median(lts):.0f}s p10 {pct(lts, .1):.0f} p90 {pct(lts, .9):.0f}")
            # LS outcome: leader (nodes) at 240 snap wins?
            lead = []
            for r in ls:
                s = r["snaps"].get("240")
                if not s:
                    continue
                sds = defaultdict(lambda: [0, 0.0])
                for seat, v in s.items():
                    sd = side(r, seat)
                    sds[sd][0] += v[0]
                    sds[sd][1] += v[2]
                if len(sds) < 2:
                    continue
                (k1, v1), (k2, v2) = list(sds.items())[:2]
                if v1[0] == v2[0]:
                    continue
                lead_side = k1 if v1[0] > v2[0] else k2
                w = r["winner"]
                lead.append((1.0 if w != "" and side(r, w) == lead_side else 0.0, r["forced"]))
            print(f"  Last Stand games with a node lead at 4:00: leader wins {wr([x[0] for x in lead]):.1f}% (n={len(lead)}); of those decided by the hard end: {sum(1 for x in lead if x[1])}")
            print(f"  LS games decided by the 7:00 forced end: {sum(1 for r in ls if r['forced'])} of {len(ls)} ({sum(1 for r in ls if r['forced']) / len(ls) * 100:.0f}%)")
        # ---- 4 snowball
        print("\n## Snowball: P(leader wins) among games still running at t (ties dropped); lead measured by nodes / strength / production")
        for t in ("60", "120", "180", "240"):
            line = f"  t={t:>3}s "
            for mi, name in ((0, "nodes"), (2, "strength"), (1, "prod")):
                xs = []
                for r in R:
                    s = r["snaps"].get(t)
                    if not s:
                        continue
                    sds = defaultdict(float)
                    for seat, v in s.items():
                        sds[side(r, seat)] += v[mi]
                    if len(sds) < 2:
                        continue
                    (k1, v1), (k2, v2) = list(sds.items())[:2]
                    if abs(v1 - v2) < 1e-9:
                        continue
                    if mi == 2 and abs(v1 - v2) < 0.1 * max(v1, v2):
                        continue
                    lead_side = k1 if v1 > v2 else k2
                    w = r["winner"]
                    xs.append(1.0 if w != "" and side(r, w) == lead_side else (0.5 if w == "" else 0.0))
                line += f"| {name}: {wr(xs):5.1f}% (n={len(xs)}) "
            print(line)
        print("  comeback at 120s (trailing side wins): by node deficit")
        for thr in (1, 2, 3, 4):
            xs = []
            for r in R:
                s = r["snaps"].get("120")
                if not s:
                    continue
                sds = defaultdict(float)
                for seat, v in s.items():
                    sds[side(r, seat)] += v[0]
                if len(sds) < 2:
                    continue
                (k1, v1), (k2, v2) = list(sds.items())[:2]
                if abs(v1 - v2) < thr:
                    continue
                trail = k1 if v1 < v2 else k2
                w = r["winner"]
                xs.append(1.0 if w != "" and side(r, w) == trail else 0.0)
            print(f"    deficit >= {thr} nodes: comeback {wr(xs):5.1f}% (n={len(xs)})")
        print("  comeback by strength deficit at 120s (trailing side has <= X of leader's strength)")
        for ratio in (0.8, 0.6, 0.4):
            xs = []
            for r in R:
                s = r["snaps"].get("120")
                if not s:
                    continue
                sds = defaultdict(float)
                for seat, v in s.items():
                    sds[side(r, seat)] += v[2]
                if len(sds) < 2:
                    continue
                (k1, v1), (k2, v2) = list(sds.items())[:2]
                lo_, hi_ = (v1, v2) if v1 < v2 else (v2, v1)
                if hi_ <= 0 or lo_ / hi_ > ratio:
                    continue
                trail = k1 if v1 < v2 else k2
                w = r["winner"]
                xs.append(1.0 if w != "" and side(r, w) == trail else 0.0)
            print(f"    trailing <= {int(ratio * 100)}% of leader: comeback {wr(xs):5.1f}% (n={len(xs)})")
        # first-capture / first blood proxy: who took more neutrals by 60s
        xs = []
        for r in R:
            c = defaultdict(int)
            for cp in r["caps"]:
                if cp[0] <= 60 and cp[2] == "":
                    c[side(r, cp[1])] += 1
            if len(c) < 2 and not c:
                continue
            sides = set(side(r, s) for s in seats_of(r))
            if len(sides) < 2:
                continue
            a, b = list(sides)[:2]
            if c[a] == c[b]:
                continue
            lead_side = a if c[a] > c[b] else b
            w = r["winner"]
            xs.append(1.0 if w != "" and side(r, w) == lead_side else 0.0)
        print(f"  more neutrals taken by 1:00 -> wins {wr(xs):.1f}% (n={len(xs)})")
        # ---- 5 map table
        print("\n## Per map: n, first-seat%s win %%, median length, p10/p90, forced-end %%, LS %%, early(<2:30)%%" % (" (A)" if mode == "1v1" else " (team 0 / seat A's side)"))
        bymap = defaultdict(list)
        for r in R:
            bymap[r["map"]].append(r)
        out = []
        for m, rs in sorted(bymap.items()):
            xs = [score(r, "A") for r in rs]
            ts = [r["t"] for r in rs]
            out.append((m, len(rs), wr(xs), st.median(ts), pct(ts, .1), pct(ts, .9), sum(1 for r in rs if r["forced"]) / len(rs) * 100, sum(1 for r in rs if r["ls_t"] > 0) / len(rs) * 100, sum(1 for t in ts if t < 150) / len(ts) * 100, rs[0]["file"]))
        for o in out:
            flag = "  <-- bias" if abs(o[2] - 50) >= 12 else ""
            print(f"  {o[9][:-5]:<28} n={o[1]:3d}  A {o[2]:5.1f}%  len {o[3]:4.0f} [{o[4]:3.0f}-{o[5]:3.0f}]  forced {o[6]:4.0f}%  LS {o[7]:4.0f}%  early {o[8]:3.0f}%{flag}")
        allA = [score(r, "A") for r in R]
        print(f"  ALL maps: seat A win {wr(allA):.1f}% n={len(allA)} CI{wilson(sum(allA), len(allA))}")
        # ---- 6 degenerate
        print("\n## Degenerate checks")
        print(f"  matches not over by sim cap (600 s): {sum(1 for r in R if not r['over'])}")
        # winners' casts
        cs = defaultdict(list)
        for r in R:
            for s in seats_of(r):
                cs[score(r, s)].append(sum(1 for c in r["casts"] if c[1] == s))
        for k in sorted(cs):
            print(f"  casts per seat when result={k}: mean {st.mean(cs[k]):.1f}")
        # whether most-cast power is ultimates
        ult = defaultdict(int)
        for r in R:
            for c in r["casts"]:
                ult[c[3]] += 1
        print(f"  casts by slot: {dict(ult)}  per match {sum(ult.values()) / len(R):.1f}")
        print("  total captures per match (neutral / hostile): %.1f / %.1f" % (sum(1 for r in R for c in r["caps"] if c[2] == "") / len(R), sum(1 for r in R for c in r["caps"] if c[2] != "") / len(R)))
        # ping-pong captures: same node flipped? count captures within 1s windows
        pp = 0
        for r in R:
            caps = [c for c in r["caps"] if c[2] != ""]
            pp += sum(1 for a, b in zip(caps, caps[1:]) if abs(a[0] - b[0]) < 0.3)
        print(f"  hostile captures within 0.3 s of the previous one (chain flips): {pp / len(R):.1f} per match")
