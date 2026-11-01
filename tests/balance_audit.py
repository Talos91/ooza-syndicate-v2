"""bal-audit tables (2026-11-02): python -I tests/balance_audit.py <dir> [--json out.json] [--mat P] [--noult P] [--lift P1,P2] [--mg P]
Reads tests/balance_study.gd lines (1v1, Expert, real settings) and prints:
  factions   --study=base matrix: each faction's win rate (mirrors left out)
  ultimates  --study=habit --habits=noult: lift = the casting seat's win rate - 50 (the vseat never casts)
  skills     --study=lift: lift = the casting seat's win rate - 50 (the vseat casts, the other seat never casts that slot)
  usage      from the matrix: casts per match of every skill a seat carried
  machinegoon --study=habit --habits=nomg,mgfront: what building it is worth, how often, kills vs production forgone
AI-vs-AI evidence only."""
import glob, json, sys
from collections import defaultdict

FACS = ["vex", "null", "bloom", "ember", "solar"]
ULT = {"vex": "rewire", "null": "echo_split", "bloom": "superbloom", "ember": "core_meltdown", "solar": "relay_aegis"}


def opt(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


d = sys.argv[1]
out = {}


def load(prefixes):
    rows = []
    for pre in prefixes.split(","):
        for p in glob.glob(f"{d}/{pre}_*.jsonl"):
            rows += [json.loads(l) for l in open(p) if l.strip()]
    return rows


def sc(r, seat):
    w = r["winner"]
    return 0.5 if w == "" else (1.0 if w == seat else 0.0)


def other(seat):
    return "B" if seat == "A" else "A"


def ci(x):
    n = len(x)
    if not n:
        return float("nan")
    p = sum(x) / n
    return 1.96 * (p * (1 - p) / n) ** 0.5 * 100


def activations(r, seat, slot, uid=None):
    """Casts of a slot; Rewire's free relay fires count once per 20 s window."""
    n, last = 0, -99.0
    for x in r["casts"]:
        if x[1] == seat and x[3] == slot and (uid is None or x[2] == uid):
            if slot != "ultimate" or x[0] - last >= 20.0:
                n += 1
                last = x[0]
    return n


def mean(x):
    return sum(x) / len(x) if x else float("nan")


# ---- factions
mat = load(opt("--mat", "mat"))
if mat:
    wr = defaultdict(list)
    for r in mat:
        a, b = r["spec"]["A"], r["spec"]["B"]
        if a == b:
            continue
        wr[a].append(sc(r, "A"))
        wr[b].append(sc(r, "B"))
    print(f"## Factions ({len(mat)} matches, mirrors out)")
    out["factions"] = {}
    for f in FACS:
        print(f"{f:<6} {mean(wr[f])*100:5.1f} +-{ci(wr[f]):4.1f} n={len(wr[f])}")
        out["factions"][f] = [round(mean(wr[f]) * 100, 1), round(ci(wr[f]), 1)]
    t = [r["t"] for r in mat]
    ls = sum(1 for r in mat if r["ls_t"] >= 0) / len(mat)
    t.sort()
    print(f"median length {t[len(t)//2]:.0f} s, Last Stand reached {ls*100:.0f} %, hard end {sum(1 for r in mat if r['forced'])/len(mat)*100:.0f} %")
    out["match"] = {"median_t": t[len(t) // 2], "ls": round(ls * 100), "n": len(mat)}

# ---- ultimates
nu = load(opt("--noult", "noult"))
if nu:
    print(f"\n## Ultimates: cast vs never-cast ({len(nu)} matches)")
    print("| faction | ultimate | lift | +- | n | casts/match | lines moving at cast | units moving at cast | lift relay maps | lift no-relay maps |")
    out["ults"] = {}
    for f in FACS:
        g, gr, gn, nc, nl, nunits = [], [], [], [], [], []
        for r in nu:
            if r["spec"][r["vseat"]] != f:
                continue
            st = other(r["vseat"])
            s = sc(r, st)
            g.append(s)
            (gr if r.get("relays") else gn).append(s)
            nc.append(activations(r, st, "ultimate", ULT[f]))
            for c in r.get("ult_ctx", []):
                if c[1] == st:
                    nl.append(c[3])
                    nunits.append(c[4])
        if not g:
            continue
        row = [round(mean(g) * 100 - 50, 1), round(ci(g), 1), len(g), round(mean(nc), 2), round(mean(nl), 1), round(mean(nunits), 1),
               round(mean(gr) * 100 - 50, 1) if gr else None, round(mean(gn) * 100 - 50, 1) if gn else None, len(gr), len(gn)]
        out["ults"][ULT[f]] = row
        print(f"| {f} | {ULT[f]} | {row[0]:+.1f} | {row[1]:.1f} | {row[2]} | {row[3]} | {row[4]} | {row[5]} | {row[6]} (n={len(gr)}) | {row[7]} (n={len(gn)}) |")

# ---- active / map skills
lift = load(opt("--lift", "lift1,lift2,lift3"))
if lift:
    print(f"\n## Active / map skills: cast vs never-cast ({len(lift)} matches)")
    g = defaultdict(list)
    nc = defaultdict(list)
    for r in lift:
        slot = r["study"].split(":")[1]
        vs = r["vseat"]
        pid = r["loadouts"][vs][slot]                  # the skill actually carried (relay skills fall back on relay-less maps)
        g[(slot, pid)].append(sc(r, vs))
        nc[(slot, pid)].append(activations(r, vs, slot))
    out["skills"] = {}
    print("| slot | skill | lift | +- | n | casts/match |")
    for k in sorted(g, key=lambda k: -mean(g[k])):
        row = [round(mean(g[k]) * 100 - 50, 1), round(ci(g[k]), 1), len(g[k]), round(mean(nc[k]), 2)]
        out["skills"][k[1]] = [k[0]] + row
        print(f"| {k[0]} | {k[1]} | {row[0]:+.1f} | {row[1]:.1f} | {row[2]} | {row[3]} |")

# ---- natural usage (matrix: AI builds rotate per faction)
if mat:
    carried = defaultdict(int)
    casts = defaultdict(int)
    used = defaultdict(int)
    for r in mat:
        for seat in ["A", "B"]:
            for slot in ["active", "map", "ultimate"]:
                pid = r["loadouts"][seat][slot]
                carried[pid] += 1
                c = activations(r, seat, slot, pid)
                casts[pid] += c
                used[pid] += 1 if c else 0
    print("\n## Usage in normal matches (matrix): seats carrying it, casts per match, share of matches cast at least once")
    out["usage"] = {}
    for pid in sorted(carried, key=lambda p: -casts[p] / carried[p]):
        out["usage"][pid] = [carried[pid], round(casts[pid] / carried[pid], 2), round(used[pid] / carried[pid] * 100)]
        print(f"{pid:<14} seats {carried[pid]:5d}  casts/match {casts[pid]/carried[pid]:5.2f}  used {used[pid]/carried[pid]*100:3.0f} %")

# ---- machinegoon
mgp = opt("--mg", "mg")
mg = load(mgp)


def mg_stats(rows, seats_of):
    built, n_mg, secs, kills, lost, n = 0, [], [], [], [], 0
    for r in rows:
        for seat in seats_of(r):
            n += 1
            b = sum(1 for x in r["builds"] if x[1] == seat and x[2] == "machinegoon")
            n_mg.append(b)
            built += 1 if b else 0
            m = r.get("mg", {}).get(seat)
            if m:
                secs.append(m[0])
                kills.append(m[1])
                lost.append(m[2])
    return {"seats": n, "built_pct": round(built / n * 100, 1) if n else None, "builds_per_seat": round(mean(n_mg), 2),
            "mg_node_s": round(mean(secs), 0) if secs else 0, "kills": round(mean(kills), 1) if kills else 0,
            "prod_forgone": round(mean(lost), 1) if lost else 0}


if mat:
    st = mg_stats(mat, lambda r: ["A", "B"])
    print(f"\n## Machinegoon in normal matches: {st}")
    out["mg_usage"] = st
if mg:
    print(f"\n## Machinegoon habits ({len(mg)} matches)")
    out["mg"] = {}
    for h in ["nomg", "mgfront"]:
        rows = [r for r in mg if r["study"] == "habit:" + h]
        if not rows:
            continue
        x = [sc(r, r["vseat"]) for r in rows]
        stock = mg_stats(rows, lambda r: [other(r["vseat"])])
        hab = mg_stats(rows, lambda r: [r["vseat"]])
        print(f"{h}: habit seat WR {mean(x)*100:.1f} +-{ci(x):.1f} n={len(x)} | stock {stock} | habit {hab}")
        out["mg"][h] = [round(mean(x) * 100, 1), round(ci(x), 1), len(x), stock, hab]

if "--json" in sys.argv:
    json.dump(out, open(opt("--json", "audit.json"), "w"), indent=1)
