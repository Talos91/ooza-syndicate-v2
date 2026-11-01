"""MAP SCORECARD - static half (🗺️ map-score, 2026-11-02; measurement only).
  python tests/map_score_static.py <maps4 dir> <walk.jsonl> <out.json>
Per pooled 1v1 map: counts, footprint, size class, structure (lanes, choke points, relay-only nodes, Last Stand isolation),
the rulebook's own findings (Tools/MapBuilder mb.rules.check) and the sim seat walk from map_score.gd --study=walk.
Size class rule (stated in the report): platforms (junction pieces excluded) <= 13 -> S, 14-17 -> M, >= 18 -> L;
a map wider than 140 m or with a footprint over 10,000 m2 moves up one class (footprint = platform centres' box + 12 m)."""
import json, sys, math, glob, os
from collections import Counter

MB = "H:/My Drive/PROJECTS/Ooze Syndicate/Tools/MapBuilder"
sys.path.insert(0, MB)
from mb import rules, routes  # noqa: E402
sys.path.insert(0, MB)
import risk as riskmod  # noqa: E402


def comps(ids, edges):
    adj = {i: set() for i in ids}
    for a, b in edges:
        if a in adj and b in adj:
            adj[a].add(b); adj[b].add(a)
    seen, out = set(), []
    for i in ids:
        if i in seen:
            continue
        st, c = [i], set()
        while st:
            v = st.pop()
            if v in c:
                continue
            c.add(v); st.extend(adj[v] - c)
        seen |= c; out.append(c)
    return out


def articulation(ids, edges, junctions):
    """Platforms whose loss splits the board (junction pieces cannot be held, so they never count)."""
    base = len(comps(ids, edges))
    out = []
    for x in ids:
        if x in junctions:
            continue
        rest = [i for i in ids if i != x]
        if len(comps(rest, [(a, b) for a, b in edges if x not in (a, b)])) > base:
            out.append(x)
    return out


def main(d, walk_path, out_path):
    walk = {}
    for line in open(walk_path, encoding="utf-8"):
        r = json.loads(line)
        walk[r["map"]] = r
    res = {}
    for code in walk:
        f = glob.glob(os.path.join(d, code + "-*.json"))[0]
        m = json.load(open(f, encoding="utf-8"))
        N, E = m["nodes"], m["edges"]
        junc = {n["id"] for n in N if n.get("junction")}
        plats = [n["id"] for n in N if n["id"] not in junc]
        relays = [n for n in N if n.get("relay")]
        kinds = Counter(str(n["relay"].get("kind") if isinstance(n["relay"], dict) else n["relay"]) for n in relays)
        xs = [n["x"] for n in N if n["id"] in plats]; ys = [n["y"] for n in N if n["id"] in plats]
        fw, fh = max(xs) - min(xs) + 12, max(ys) - min(ys) + 12
        npl = len(plats)
        size = "S" if npl <= 13 else ("M" if npl <= 17 else "L")
        if fw > 140 or fw * fh > 10000:
            size = {"S": "M", "M": "L", "L": "L"}[size]
        homes = {s["seat"]: s["node"] for s in m["seats"]["1v1"]}
        ids = [n["id"] for n in N]
        relay_decks = sum(1 for e in E if routes.is_relay_deck(e))
        fixed = [(e["from"], e["to"]) for e in E if not routes.is_relay_deck(e)]
        allp = [(e["from"], e["to"]) for e in E]
        # nodes reachable only through a relay deck: not in a home's component of the fixed decks
        cc = comps(ids, fixed)
        homecomp = set().union(*[c for c in cc if homes["A"] in c or homes["B"] in c])
        relay_only = [i for i in plats if i not in homecomp]
        lanes, chokes = [], set()
        for cfg in (0, 1):
            op = routes.open_edges(m, cfg)
            ed = [(E[k]["from"], E[k]["to"]) for k in op]
            lanes.append(rules._disjoint_routes(len(N), ed, homes["A"], homes["B"], free=junc))
            chokes |= set(articulation(ids, ed, junc))
        chokes -= {homes["A"], homes["B"]}
        # Last Stand: per method, does the survivor ring stay one piece and keep a relay deck working?
        ls = {}
        ring = {n["id"]: n.get("ring", 0) for n in N}
        for meth in m["lastStand"]["methods"]:
            order = m["lastStand"]["orders"].get(meth)
            if not order:
                continue
            fin = [i for i in ids if ring[i] == order[-1]]
            fe = [(E[k]["from"], E[k]["to"]) for k in routes.open_edges(m, None) if E[k]["from"] in fin and E[k]["to"] in fin]
            fixed_fin = [(a, b) for (a, b) in fixed if a in fin and b in fin]
            relay_fin = sum(1 for e in E if routes.is_relay_deck(e) and e["from"] in fin and e["to"] in fin)
            ls[meth] = {"survivors": len([i for i in fin if i not in junc]), "pieces_fixed": len(comps(fin, fixed_fin)),
                        "pieces_any": len(comps(fin, fe)), "relay_decks": relay_fin}
        # rulebook
        try:
            items = rules.check(m, want_plan=False)
        except Exception as ex:  # noqa: BLE001
            items = [{"sev": "error", "rule": "X", "msg": str(ex)}]
        hard = sorted({f["rule"] for f in items if f["sev"] == "hard"})
        soft = sorted({f["rule"] for f in items if f["sev"] == "soft"})
        try:
            rk = riskmod.risk(m)
        except Exception:  # noqa: BLE001
            rk = None
        # sim walk (two doors): seconds from each home
        w = walk[code]["walk"]
        ta = sorted(v for v in w["A"].values() if v >= 0)
        tb = sorted(v for v in w["B"].values() if v >= 0)
        hA, hB = walk[code]["home"]["A"], walk[code]["home"]["B"]
        hh = (w["A"].get(str(hB), -1), w["B"].get(str(hA), -1))
        sorted_gap = max((abs(a - b) for a, b in zip(ta, tb)), default=0)
        res[code] = {
            "code": code, "name": m["name"], "file": os.path.basename(f), "modes": sorted(m["seats"].keys()),
            "platforms": npl, "junctions": len(junc), "bridges": len(E), "relay_nodes": len(relays), "relay_decks": relay_decks,
            "relay_kinds": dict(kinds), "footprint": [round(fw), round(fh)], "size": size,
            "lanes_min": min(lanes), "lanes": lanes, "chokes": len(chokes), "relay_only": len(relay_only),
            "home_to_home_s": [round(hh[0], 1), round(hh[1], 1)], "home_gap_s": round(abs(hh[0] - hh[1]), 2),
            "walk_sorted_gap_s": round(sorted_gap, 2), "longest_walk_s": round(max(ta + tb), 1),
            "mean_walk_s": round(sum(ta + tb) / max(1, len(ta + tb)), 1),
            "last_stand": ls, "rule_hard": hard, "rule_soft": soft, "relay_risk": None if rk is None else round(rk, 3),
            "symmetry": m.get("symmetry"), "family": m.get("family"), "tags": m.get("tags"),
        }
    json.dump(res, open(out_path, "w", encoding="utf-8"), indent=1)
    for c, r in res.items():
        print(c, r["size"], r["platforms"], r["relay_nodes"], r["relay_kinds"], "lanes", r["lanes"], "chokes", r["chokes"],
              "ronly", r["relay_only"], "gap", r["home_gap_s"], r["walk_sorted_gap_s"], "hard", r["rule_hard"])


if __name__ == "__main__":
    main(*sys.argv[1:4])
