"""PIT FIT (map-pass 2026-11-18): the G maps reworked to fill THE PIT of Daniele's screen frame and stay uncluttered, like the three
reference maps Catapult Bay G-05, Spiral G-10 and Launcher G-08 (05 Handoff/handoffs/screen-layout Daniele 2026-11-18/SCREEN-LAYOUT-SPEC.md
section 4: <= 15 platforms, <= 25 bridges, spacing >= 55 pt, fill >= 61 %, width >= 75.5 %, height >= 70 % of the pit, pitch 48..56).

    python packs/pit_fit.py --game=<clone> [--write] [--json=<report>] [G CODES...]

Per map: the baked G map (pool_g.py's output, the layout dropped) -> RECIPES[code] -> honest lengths re-read -> rulebook before / after ->
mb.bake.write_game into <clone>/maps4/<same file> (no schematic thumbnail: the game's 3D thumb stays). A recipe is a list of steps:
  ("drop", [(a, b), ...])        remove these decks (old node ids; a mirror / half-turn twin is listed too, so the map keeps its symmetry)
  ("merge", [(a, mid, b), ...])  a chain a - mid - b becomes one deck a - b (mid leaves; the longer deck's tier, both decks' fields of a - mid)
  ("node", [ids])                remove these platforms / junctions (and every deck that touches them)
  ("scale", sx, sy[, ids])       spread node positions (all, or these) about the frame centre (platforms keep their size; decks get longer)
  ("move", {id: (dx, dy)})       move these nodes (metres; the twin is listed too)
  ("set", id, {fields})          change a node's fields (a junction piece)
  ("add_node", tmp_id, {fields}) / ("add_edge", {fields})   a new platform / deck (plain fields as the bake writes them)
Then node ids are renumbered 0..N-1 (seats, deck ends, relay owners, launcher targets follow) and every deck's `modules` / `deckMetres`
is its new honest length (rim to rim minus piers, as mb/shrink.py writes it), so test_maps4 and the planner read it from the map.
Platforms keep their size (Daniele 2026-11-18). Per-map camera pitch: scripts/map_camera.gd (tests/screen_fill.tscn picks it).
A map with no recipe is re-baked unchanged (parity: the bake must reproduce the shipped json)."""
import collections
import copy
import glob
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from mb import bake, junctions, kit, rules  # noqa: E402

RECIPES = {
    # Crossfire (Daniele 11-18: "tilted relic bridges + cramped centre"): the X of four conveyor decks and its Crossing (7 / 8) leave; the
    # square of four vats round the empty centre stays with its two lift stones; spread sideways to fill the pit (60 % -> width target).
    # bridges > 25 -> <= 25 (clutter; spec section 4). Each step names the deck and its mirror / half-turn twin; every removal was
    # checked to add no hard rulebook finding (relay decks, conveyors kept unless named).
    "G-01": [("drop", [(2, 3), (2, 4),                       # Gate: the short decks beside the top and bottom stops and the outer corners'
                       (10, 12), (11, 12),                     # decks into the side relays: 30 -> 24. The centre relay's four conveyors
                       (0, 6), (1, 8)])],                      # stay (taking any moves its button onto a platform: test_maps4)
    "G-03": [("merge", [(9, 13, 15), (10, 14, 16), (15, 17, 16)])],   # Crescent: the horn tips' stops merge into the deck round them: 18 -> 15 platforms, 27 -> 24
    "G-15": [("drop", [(0, 9), (9, 18), (7, 8), (10, 11)])],  # Crescents: the axis spokes of the centre + the homes' short side decks: 28 -> 24
    "G-16": [("drop", [(4, 8), (10, 14), (5, 10), (8, 13)]),  # Ladder Ring: the four stub decks from the side relays into the inner diamond: 28 -> 24
             ("scale", 1.15, 1.0)],                                # + spread sideways (width 77 %, spacing 53.8 pt)
    # tall maps short of the pit's width / crowded (spacing < 55 pt): spread sideways
    "G-07": [("scale", 1.15, 1.0),                                 # Ferry: width 78 %, spacing 51 pt; the tight pairs are the columns
             ("move", {2: (0, -2.0), 11: (0, 2.0), 12: (0, 2.0), 1: (0, -2.0)})],   # 2-7-12 / 11-6-1: their ends 2 m further out
    "G-13": [("scale", 1.15, 1.0)],                                 # Overpass: width 72 %
    "G-18": [("drop", [(1, 6), (2, 8), (6, 12), (8, 13), (3, 10), (4, 11)])],   # Hex Switch: the home hubs' triangle decks + the hex's inner verticals: 30 -> 24
    "G-19": [("drop", [(3, 6), (4, 8)])],                     # Switchyard: one deck into each side hub: 28 -> 26 (every further symmetric
                                                               # removal breaks N11 / N04 / N10: listed as a remaining FIX)
    "G-04": [("node", [7, 8]), ("drop", [(0, 3), (2, 4), (13, 11), (15, 12)]),   # + the four short corner links (they pinch, G13)
             ("set", 6, {"junction": "Junction_X"}), ("set", 9, {"junction": "Junction_X"}),   # the square's side junctions get an inner port
             ("add_node", 100, {"x": 80.0, "y": 40.0, "ring": 0, "category": "normal", "relay": None, "home": False,
                                "neutral": {"tier": 2, "structure": "vat"}, "buildable": ["vat"]}),   # a centre vat on the open square
             ("add_edge", {"from": 6, "to": 100, "tier": "S", "seconds": 2}), ("add_edge", {"from": 100, "to": 9, "tier": "S", "seconds": 2}),
             ("scale", 1.45, 1.0, [0, 2, 5, 10, 13, 15])],   # the outer ring spreads sideways; the square keeps its deck angles (G13)
}


def hard(m):
    return dict(collections.Counter(i["rule"] for i in rules.check(m) if i["sev"] == "hard"))


def _drop_edges(m, pairs):
    want = {frozenset(p) for p in pairs}
    got = [e for e in m["edges"] if frozenset((e["from"], e["to"])) in want]
    assert len(got) == len(want), "drop: %s not all found" % pairs
    m["edges"] = [e for e in m["edges"] if frozenset((e["from"], e["to"])) not in want]


def _merge(m, chains):
    for a, mid, b in chains:
        ea = next(e for e in m["edges"] if {e["from"], e["to"]} == {a, mid})
        eb = next(e for e in m["edges"] if {e["from"], e["to"]} == {mid, b})
        ne = copy.deepcopy(ea)
        ne["from"], ne["to"] = a, b
        ne["tier"] = max(ea["tier"], eb["tier"], key=lambda t: kit.MODS[t])
        ne["seconds"] = float(ea.get("seconds") or 0) + float(eb.get("seconds") or 0)
        m["edges"] = [e for e in m["edges"] if e is not ea and e is not eb] + [ne]
        _drop_nodes(m, [mid], renumber=False)


def _drop_nodes(m, ids, renumber=False):
    ids = set(ids)
    m["nodes"] = [n for n in m["nodes"] if n["id"] not in ids]
    m["edges"] = [e for e in m["edges"] if e["from"] not in ids and e["to"] not in ids]


def _renumber(m):
    old = [n["id"] for n in m["nodes"]]
    new = {o: i for i, o in enumerate(old)}
    for n in m["nodes"]:
        n["id"] = new[n["id"]]
        L = n.get("launcher")
        if L:
            if L.get("target") is not None:
                L["target"] = new[L["target"]]
            if L.get("targets"):
                L["targets"] = [new[t] for t in L["targets"] if t in new]
    for e in m["edges"]:
        e["from"], e["to"] = new[e["from"]], new[e["to"]]
        if e.get("relay") is not None:
            e["relay"] = new[e["relay"]]
    for mode, seats in m.get("seats", {}).items():
        for s in seats:
            s["node"] = new[s["node"]]


def _scale(m, sx, sy, ids=None):
    cx, cy = kit.FRAME_W / 2, kit.FRAME_H / 2
    for n in m["nodes"]:
        if ids is not None and n["id"] not in ids:
            continue
        n["x"] = round(cx + (float(n["x"]) - cx) * sx, 3)
        n["y"] = round(cy + (float(n["y"]) - cy) * sy, 3)
        if n.get("junctionYaw") is not None:          # a stretch keeps a junction on its decks' line: its port turns like the line
            n["_yaw0"] = float(n["junctionYaw"])       # (or like the line's normal): _junction_yaws() keeps the reading J02 accepts
            n["_s"] = (sx, sy)


def _junction_yaws(m):
    """After a stretch: each junction's yaw is turned like its decks' line, read as the port direction or as its normal (pieces differ);
    the reading that leaves this junction no J02 finding stays (first found), else the plain one."""
    for n in m["nodes"]:
        if "_yaw0" not in n:
            continue
        a = math.radians(n.pop("_yaw0"))
        sx, sy = n.pop("_s")
        opts = [math.atan2(math.sin(a) * sy, math.cos(a) * sx), math.atan2(math.sin(a) / sy, math.cos(a) / sx)]
        best = None
        for o in opts:
            n["junctionYaw"] = round(math.degrees(o) % 360.0, 2)
            bad = [i for i in rules.check(m) if i["rule"] == "J02" and n["id"] in (i.get("nodes") or []) or
                   i["rule"] == "J02" and ("junction %d " % n["id"]) in i["msg"]]
            if not bad:
                best = n["junctionYaw"]
                break
        n["junctionYaw"] = best if best is not None else round(math.degrees(opts[0]) % 360.0, 2)


def _honest(m):
    """Every deck's honest length = what it now spans rim to rim (exits) minus its piers, written as mb/shrink.py does."""
    X = junctions.exits(m)
    idx = {n["id"]: n for n in m["nodes"]}
    for q, e in enumerate(m["edges"]):
        if e.get("joint"):
            continue
        A, B, p0, p1 = X[q][:4]
        h = max(math.dist(A, B) - p0 - p1, 0.05)
        e["modules"] = round(h / kit.S, 4)
        e["deckMetres"] = round(h, 3)
        if "centreDistance" in e:
            a, b = idx[e["from"]], idx[e["to"]]
            e["centreDistance"] = round(math.hypot(a["x"] - b["x"], a["y"] - b["y"]), 2)


def apply(m0, recipe):
    m = copy.deepcopy(m0)
    m.pop("layout", None)
    for step in recipe:
        op = step[0]
        if op == "drop":
            _drop_edges(m, step[1])
        elif op == "merge":
            _merge(m, step[1])
        elif op == "node":
            _drop_nodes(m, step[1])
        elif op == "scale":
            _scale(m, step[1], step[2], step[3] if len(step) > 3 else None)
        elif op == "move":
            for n in m["nodes"]:
                if n["id"] in step[1]:
                    n["x"] = round(float(n["x"]) + step[1][n["id"]][0], 3)
                    n["y"] = round(float(n["y"]) + step[1][n["id"]][1], 3)
        elif op == "set":
            next(n for n in m["nodes"] if n["id"] == step[1]).update(step[2])
        elif op == "add_node":
            m["nodes"].append(dict({"id": step[1], "plaza": None, "socket": None}, **step[2]))
        elif op == "add_edge":
            m["edges"].append(dict({"level": 0, "state": None, "relay": None, "retracts": False}, **step[1]))
        else:
            raise ValueError(op)
    _renumber(m)
    if recipe:
        _honest(m)
        _junction_yaws(m)
        _honest(m)
    return m


def main(argv):
    opts = {a.split("=", 1)[0]: (a.split("=", 1) + [""])[1] for a in argv if a.startswith("--")}
    game = opts["--game"]
    codes = [a for a in argv if not a.startswith("--")] or sorted(RECIPES)
    rows = []
    for c in codes:
        f = glob.glob(os.path.join(game, "maps4", c + "-*.json"))[0]
        m0 = json.load(open(f, encoding="utf-8"))
        m1 = apply(m0, RECIPES.get(c, []))
        base = copy.deepcopy(m0)
        base.pop("layout", None)
        h0, h1 = hard(base), hard(m1)
        verify = None
        if "--write" in opts:
            verify = bake.write_game(m1, game, os.path.basename(f), thumb=False)
        row = {"code": c, "nodes": [len(m0["nodes"]), len(m1["nodes"])], "edges": [len(m0["edges"]), len(m1["edges"])],
               "hard_before": h0, "hard_after": h1, "verify": verify}
        rows.append(row)
        print("%s nodes %d->%d decks %d->%d hard %s -> %s %s" % (c, len(m0["nodes"]), len(m1["nodes"]), len(m0["edges"]),
              len(m1["edges"]), h0, h1, "" if verify is None else json.dumps(verify)[:300]), flush=True)
    if opts.get("--json"):
        json.dump(rows, open(opts["--json"], "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:])
