"""STRAIGHT DECKS (map-pool-g 2026-11-15, Daniele: "a couple of maps have very crooked weird shape bridge like strait 2, fix them").

At deck tiers 2 / 4 / 6 m a 2-port curve piece (Curve_30 / 45 / 60 / 90 / W45 / W90) keeps its full arc (4-16 m) while the decks on
either side drop to 0.3-2 m stubs: the bridge reads as a kinked dog-leg between two platforms. `straighten(m)` runs on the SHRUNK
map (after mb.shrink), so no node moves: every curve whose two decks are plain (no relay state, no relay node, no proto piece such as
a conveyor / ferry) and whose two neighbours are platforms is taken out, and its two decks become ONE straight deck from rim to rim
(the chord: its honest length is what it got, written into `modules`, like every shrunk deck; a little shorter than the old walk
through the arc). The footprint, the camera and the other decks stay as they were. A curve next to another junction piece, or on a
relay / proto deck (part of a gameplay piece), stays and is listed in the report. A first try (straighten before the shrink, then
re-solve) gave 15-20 m decks and new rulebook findings (G05 / G13): dropped.

Node ids stay 0..n-1 (the sim indexes by id): every reference is remapped - edges from / to / relay, seats, node.launcher target(s),
node.conveyor / proto link, node.tilt exits, the map's hill."""
import copy

from . import junctions, kit


def _plain(e):
    return not e.get("state") and e.get("relay") is None and not e.get("proto") and not e.get("joint") \
        and e.get("shape") != "sbend" and not e.get("overpass") and not e.get("lift") and not e.get("ferry")


def straighten(m):
    """-> (map, report). report = {"removed": [(curve id as drawn, piece, a, b, metres)], "kept": [(curve id, piece, why)],
    "edges": [index of each new straight deck in the returned map]}."""
    out = copy.deepcopy(m)
    out.pop("layout", None)
    removed, kept = [], []
    while True:
        N = {n["id"]: n for n in out["nodes"]}
        pick = None
        for n in out["nodes"]:
            if not junctions.is_curve(n):
                continue
            es = [q for q, e in enumerate(out["edges"]) if n["id"] in (e["from"], e["to"])]
            if len(es) != 2:
                continue
            e1, e2 = out["edges"][es[0]], out["edges"][es[1]]
            if not (_plain(e1) and _plain(e2)):
                if n.get("_orig", n["id"]) not in [k[0] for k in kept]:
                    kept.append((n.get("_orig", n["id"]), n["junction"], "relay / proto deck"))
                continue
            a = e1["from"] if e1["to"] == n["id"] else e1["to"]
            b = e2["from"] if e2["to"] == n["id"] else e2["to"]
            if junctions.is_junction(N[a]) or junctions.is_junction(N[b]):
                if n.get("_orig", n["id"]) not in [k[0] for k in kept]:
                    kept.append((n.get("_orig", n["id"]), n["junction"], "next to a junction piece"))
                continue
            if a == b or any({a, b} == {e["from"], e["to"]} for e in out["edges"]):
                kept.append((n.get("_orig", n["id"]), n["junction"], "would double a deck"))
                continue
            pick = (n, es, a, b)
            break
        if pick is None:
            break
        n, es, a, b = pick
        e1, e2 = out["edges"][es[0]], out["edges"][es[1]]
        tier, h = junctions.deck_tier(None, N[a], N[b])
        ne = dict(e1, **{"from": a, "to": b, "tier": tier, "modules": round(h / kit.S, 4), "deckMetres": round(h, 3), "_straight": True})
        ne.pop("centreDistance", None)
        removed.append((n.get("_orig", n["id"]), n["junction"], N[a].get("_orig", a), N[b].get("_orig", b), round(h, 2)))
        out["edges"][es[0]] = ne
        del out["edges"][es[1]]
        _drop_node(out, n["id"])
    for n in out["nodes"]:
        n.pop("_orig", None)
    new = [q for q, e in enumerate(out["edges"]) if e.pop("_straight", False)]
    return out, {"removed": removed, "kept": kept, "edges": new}



def _drop_node(m, gone):
    """Remove node `gone` (no deck may still use it) and renumber the ids above it, everywhere they are referenced."""
    for n in m["nodes"]:
        n.setdefault("_orig", n["id"])
    m["nodes"] = [n for n in m["nodes"] if n["id"] != gone]
    f = lambda i: i - 1 if isinstance(i, int) and not isinstance(i, bool) and i > gone else i
    for n in m["nodes"]:
        n["id"] = f(n["id"])
        for key in ("launcher", "conveyor", "proto", "tilt"):
            p = n.get(key)
            if isinstance(p, dict):
                for kk in ("target", "link"):
                    if isinstance(p.get(kk), int) and p[kk] >= 0:
                        assert p[kk] != gone, (key, kk)
                        p[kk] = f(p[kk])
                for kk in ("targets", "exits"):
                    if isinstance(p.get(kk), list):
                        assert gone not in p[kk], (key, kk)
                        p[kk] = [f(x) for x in p[kk]]
    for e in m["edges"]:
        assert gone not in (e["from"], e["to"], e.get("relay"))
        e["from"], e["to"] = f(e["from"]), f(e["to"])
        if e.get("relay") is not None:
            e["relay"] = f(e["relay"])
    for lst in (m.get("seats") or {}).values():
        for s in lst:
            assert s["node"] != gone
            s["node"] = f(s["node"])
    if isinstance(m.get("hill"), int):
        assert m["hill"] != gone
        m["hill"] = f(m["hill"])
