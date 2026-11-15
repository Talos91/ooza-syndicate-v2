"""Deck junctions (MAP LAB experiment, Daniele 2026-09-27: "maps feel too linear ... the new connecting bridges should allow
for a node to be connected to 4 with just 1 bridge"). Pieces by the Skin Designer: Models/2.0/structures_2_1/glb_junctions,
port data in junctions.json (every port an open deck edge 2.8 m wide; a deck starts on the edge centre and runs outward).

A junction is a map node with "junction": "<piece>" and "junctionYaw": <degrees, counter-clockwise with y up>; category
"junction", no neutral, no structure. In the game (branch map-lab) it can't be owned, targeted or tapped, and units walk
across it (a curve: along its arc). Decks plug into its ports without piers, so honest centre distances are:
  platform - platform 19.2 / 23.2 / 27.2, platform - junction 14 / 18 / 22, junction - junction 8.8 / 12.8 / 16.8 (S / M / L)
(port edge 2.4 m from the centre on X / T / Y / L).

Curves (2026-09-28, Daniele: "more curvy using more of the curved bridge modules"): Curve_45 / Curve_90 are 2-port pieces
whose ORIGIN is their start port (not a centre), so every rule and the bake work from the port points themselves: a deck at
a junction runs from the port's edge centre along the port's direction, and its honest length is exit to exit (4 / 8 / 12 m
of modules; a platform end adds its rim + pier). A right turn is the same curve crossed the other way.

bake_simple(m) writes the game's "layout" for a junction map without the planner: every deck runs straight from exit to exit
(a platform's rim + pier, or a junction's port edge), on the ground. Junction maps are drawn so decks leave along port
directions and never cross; the rulebook checks that."""
import itertools
import json
import math
import os
import re

from . import kit

PORTS_JSON = os.path.join(kit.ROOT, "Models", "2.0", "structures_2_1", "junctions.json")
EXP_JSON = os.path.join(kit.ROOT, "Models", "2.0", "structures_2_1", "connectors_exp.json")   # EXP pieces (2026-10-28)
_CACHE = {}
# EXP (Daniele 2026-10-28: E-01..E-10 go through the rulebook): the experimental connector set is modelled by its ports like
# the first junctions. What the rulebook cannot see is recorded on the map as rules X01-X03 (soft), never silently.
EXP_PIECES = set()


def _raw():
    if "raw" not in _CACHE:
        try:
            raw = dict(json.load(open(PORTS_JSON, encoding="utf-8"))["pieces"])
        except OSError:
            raw = {}
        try:
            ex = json.load(open(EXP_JSON, encoding="utf-8"))
            for k, v in ex.get("pieces", {}).items():
                if k not in raw and isinstance(v, list):
                    raw[k] = v
                    EXP_PIECES.add(k)
            for k, v in ex.get("info", {}).items():
                raw.setdefault(k + "_info", v)
        except OSError:
            pass
        _CACHE["raw"] = raw
    return _CACHE["raw"]


def pieces():
    """The 3-4 port junction pieces -> port list (curves and *_info notes left out; Hub6 is withdrawn but still listed)."""
    return {k: v for k, v in _raw().items() if k.startswith("Junction_") and isinstance(v, list)}


def all_pieces():
    """Every piece a map may use: the junctions, the curves (Curve_45 / Curve_90) and, since 2026-10-28, the EXP set
    (Curve_30 / 60 / W45 / W90, S-bends, bends, T-45, wide fork, K 30 / 45 / 60, Hub5, roundabouts, crossing)."""
    return {k: v for k, v in _raw().items() if isinstance(v, list) and not k.endswith("_info")}


def info(piece):
    return _raw().get(piece + "_info") or {}


def is_exp(n_or_piece):
    p = n_or_piece if isinstance(n_or_piece, str) else (n_or_piece.get("junction") or "")
    _raw()
    return p in EXP_PIECES


def is_curve(n_or_piece):
    p = n_or_piece if isinstance(n_or_piece, str) else (n_or_piece.get("junction") or "")
    return p.startswith("Curve_")


def is_sbend(n_or_piece):
    p = n_or_piece if isinstance(n_or_piece, str) else (n_or_piece.get("junction") or "")
    return p.startswith("Sbend_")


def is_crossing(n_or_piece):
    p = n_or_piece if isinstance(n_or_piece, str) else (n_or_piece.get("junction") or "")
    return p == "Crossing"


def curve_angle(piece):
    """A curve's turn in degrees from its name (Curve_45, Curve_W90 ...)."""
    return float(re.sub(r"[^0-9.]", "", piece.split("_", 1)[1]))


def curve_radius(piece):
    return float(info(piece).get("centreline_radius", 5.09))


def through_m(n):
    """How far a line walks through a piece, the way sim.gd does: a curve along its arc, an S-bend its centreline;
    None for every other piece (straight across the plate: the caller measures exit - centre - exit)."""
    piece = n.get("junction") or ""
    if is_curve(piece):
        return float(info(piece).get("length_m") or curve_radius(piece) * math.radians(curve_angle(piece)))
    if is_sbend(piece):
        return float(info(piece).get("centreline_length_m", 8.3))
    return None


def honest_m(e):
    """A deck's honest length in metres: its tier's modules, or the pack's `modules` (EXP: 0.5 = a 2 m half bridge, 4 / 5
    = 16 / 20 m spans, a flex S-bridge's real length); a joint (two pieces port to port) is 0."""
    if e.get("joint"):
        return 0.0
    if e.get("shape") == "sbend":
        return float(e.get("deckMetres") or float(e.get("modules", 2)) * kit.S)
    if e.get("modules") is not None:
        return float(e["modules"]) * kit.S
    return kit.MODS.get(e.get("tier"), 2) * kit.S * kit.DECK_K


def lane_twins(m):
    """{node id: twin id} for Crossing pieces written as two lane nodes at one point (the ground lane and the over lane:
    the rulebook and the sim join decks only within a node, so the lanes never meet)."""
    out = {}
    cr = [n for n in m.get("nodes", []) if is_crossing(n)]
    for a in cr:
        for b in cr:
            if a["id"] < b["id"] and math.hypot(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"])) < 0.05:
                out[a["id"]] = b["id"]
                out[b["id"]] = a["id"]
    return out


def port_r(piece):
    ports = all_pieces().get(piece) or []
    return max((math.hypot(p["edge_centre"][0], p["edge_centre"][1]) for p in ports), default=2.4)


def port_angles(piece, yaw):
    """Port directions in map degrees (counter-clockwise, y up)."""
    return [(p["angle_deg"] + yaw) % 360 for p in (all_pieces().get(piece) or [])]


def ports_world(piece, x, y, yaw):
    """[(px, py, angle)] per port: the edge centre in map metres (y down) and its direction (map degrees, ccw, y up)."""
    out = []
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    for p in all_pieces().get(piece) or []:
        ex, ey = p["edge_centre"][0], p["edge_centre"][1]
        rx, ry = ex * c - ey * s, ex * s + ey * c                          # y up
        out.append((x + rx, y - ry, (p["angle_deg"] + yaw) % 360))
    return out


def node_point(n):
    """Where a node is, for spacing and clearance: a curve's arc middle (its origin is an end port), else its centre."""
    x, y = float(n["x"]), float(n["y"])
    if is_sbend(n):                                                       # an S-bend: its origin is the start port too
        ex, ey = 4.0, float(info(n["junction"]).get("shift_m", 0.0)) / 2.0
        c, s = math.cos(math.radians(float(n.get("junctionYaw", 0.0)))), math.sin(math.radians(float(n.get("junctionYaw", 0.0))))
        return (x + ex * c - ey * s, y - (ex * s + ey * c))
    if not is_curve(n):
        return (x, y)
    r = curve_radius(n["junction"])
    phi = math.radians(curve_angle(n["junction"]) / 2)
    ex, ey = r * math.sin(phi), r * (1 - math.cos(phi))                   # the arc's middle in the piece (turns left)
    c, s = math.cos(math.radians(float(n.get("junctionYaw", 0.0)))), math.sin(math.radians(float(n.get("junctionYaw", 0.0))))
    return (x + ex * c - ey * s, y - (ex * s + ey * c))


def is_junction(n):
    return bool(n.get("junction"))


def end_r(n):
    """From a node's centre to where its deck starts: a platform's rim, or a (centred) junction's port edge."""
    return port_r(n["junction"]) if is_junction(n) else kit.R


def centre_for(tier, a, b):
    """Honest centre distance for a deck of `tier` between nodes a and b (centred pieces; curves: see exits())."""
    extra = sum(0.0 if is_junction(n) else kit.PIER for n in (a, b))
    return end_r(a) + end_r(b) + extra + kit.deck_m(tier)


def has_junctions(m):
    return any(is_junction(n) for n in m.get("nodes", []))


def _ang(p, q):
    return math.degrees(math.atan2(-(q[1] - p[1]), q[0] - p[0])) % 360


def _off(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def assign_ports(m):
    """{(deck index, node id): port index} for every deck end at a junction: the port assignment (one deck per port) whose
    directions best point at the decks' other ends."""
    N = {n["id"]: n for n in m["nodes"]}
    ends = {}
    for k, e in enumerate(m["edges"]):
        for me, other in ((e["from"], e["to"]), (e["to"], e["from"])):
            if is_junction(N[me]):
                ends.setdefault(me, []).append((k, other))
    out = {}
    for rnd in range(2):                                       # round 2 aims at the other ends' ports, not their centres
        for j, lst in ends.items():
            n = N[j]
            pw = ports_world(n["junction"], float(n["x"]), float(n["y"]), float(n.get("junctionYaw", 0.0)))
            if not pw:
                continue
            best = None
            for perm in itertools.permutations(range(len(pw)), min(len(lst), len(pw))):
                cost = 0.0
                for (k, other), pi in zip(lst, perm):
                    ref = _exit_ref(N, m, out, k, other, rnd)
                    cost += _off(_ang(pw[pi][:2], ref), pw[pi][2]) ** 2
                if best is None or cost < best[0]:
                    best = (cost, perm)
            for (k, other), pi in zip(lst, best[1]):
                out[(k, j)] = pi
    return out


def _exit_ref(N, m, assign, k, other, rnd):
    n = N[other]
    if rnd and is_junction(n) and (k, other) in assign:
        pw = ports_world(n["junction"], float(n["x"]), float(n["y"]), float(n.get("junctionYaw", 0.0)))
        return pw[assign[(k, other)]][:2]
    return (float(n["x"]), float(n["y"]))


def exits(m, assign=None):
    """Per deck: (A, B, pier0, pier1, portA, portB) - the exit points in map metres (a platform's rim toward the other end,
    or a junction's port edge centre) and the port index used at each junction end (None at a platform)."""
    N = {n["id"]: n for n in m["nodes"]}
    assign = assign_ports(m) if assign is None else assign
    out = []
    for k, e in enumerate(m["edges"]):
        pts, prt = [], []
        for me in (e["from"], e["to"]):
            n = N[me]
            if is_junction(n) and (k, me) in assign:
                pw = ports_world(n["junction"], float(n["x"]), float(n["y"]), float(n.get("junctionYaw", 0.0)))
                pts.append(pw[assign[(k, me)]][:2])
                prt.append(assign[(k, me)])
            else:
                pts.append(None)
                prt.append(None)
        for i, me in enumerate((e["from"], e["to"])):
            if pts[i] is None:                                  # a platform: its rim toward the other end's exit
                n = N[me]
                o = pts[1 - i] or (float(N[(e["to"], e["from"])[i]]["x"]), float(N[(e["to"], e["from"])[i]]["y"]))
                c = (float(n["x"]), float(n["y"]))
                d = math.dist(c, o) or 1e-6
                r = end_r(n) if not is_junction(n) else 0.0
                pts[i] = (c[0] + (o[0] - c[0]) / d * r, c[1] + (o[1] - c[1]) / d * r)
        piers = [0.0 if is_junction(N[me]) else kit.PIER for me in (e["from"], e["to"])]
        out.append((pts[0], pts[1], piers[0], piers[1], prt[0], prt[1]))
    return out


def bake_simple(m):
    N = {n["id"]: n for n in m["nodes"]}
    P = {i: (n["x"] - 80.0, n["y"] - 40.0) for i, n in N.items()}          # Godot x, z
    edges = []
    for (A, B, p0, p1, _, _) in exits(m):
        A = [round(A[0] - 80.0, 4), round(A[1] - 40.0, 4)]
        B = [round(B[0] - 80.0, 4), round(B[1] - 40.0, 4)]
        L = math.hypot(B[0] - A[0], B[1] - A[1])
        edges.append({"A": A, "B": B, "L": round(L, 4), "p0": p0, "p1": p1, "lean0": 0.0, "lean1": 0.0, "plaza0": False,
                      "plaza1": False, "h": 0.0, "r0": 0.0, "r1": 0.0, "dock": False})
    return {"K": 1.0, "nodes": {str(i): [round(p[0], 4), round(p[1], 4)] for i, p in P.items()}, "plazas": {},
            "edges": edges, "relays": {}, "glb": "",
            "verify": {"clashes": 0, "over_platform": 0, "short": 0, "ledge_hits": 0, "tower_on_socket": [], "docks": 0,
                       "off_length": [], "junctions": sum(1 for n in N.values() if is_junction(n))}}


def deck_tier(m_nodes, a, b):
    """The tier whose honest length is nearest a deck drawn between nodes a and b (exits from the ports), for writers."""
    tmp = {"nodes": [dict(a, id=0), dict(b, id=1)], "edges": [{"from": 0, "to": 1}]}
    A, B, p0, p1, _, _ = exits(tmp)[0]
    gap = math.dist(A, B) - p0 - p1
    return min(kit.MODS, key=lambda t: abs(kit.deck_m(t) - gap)), gap


def check(F, m):
    """The junction rules (J01-J03) for a map that has junctions; called by rules.check."""
    N = {n["id"]: n for n in m["nodes"]}
    deg = {i: 0 for i in N}
    assign = assign_ports(m)
    X = exits(m, assign)
    used = {}
    for k, e in enumerate(m["edges"]):
        a, b = N[e["from"]], N[e["to"]]
        deg[a["id"]] += 1
        deg[b["id"]] += 1
        if not (is_junction(a) or is_junction(b)):
            continue
        A, B, p0, p1, pa, pb = X[k]
        gap = math.dist(A, B) - p0 - p1
        want = honest_m(e)
        if e.get("shape") == "sbend":
            pass                                              # X02: a flex S-bridge is judged by its own length
        elif abs(gap - want) > 1.0:
            F.add("J01", "deck %d-%d is %s: %.1f m of deck, honest %g m" % (a["id"], b["id"], e["tier"], gap, want), edges=[k])
        for n, here, there, pi in ((a, A, B, pa), (b, B, A, pb)):
            if is_junction(n) and pi is not None:
                used.setdefault(n["id"], []).append(pi)
                pw = ports_world(n["junction"], float(n["x"]), float(n["y"]), float(n.get("junctionYaw", 0.0)))
                off = _off(_ang(here, there), pw[pi][2])
                if off > 3.0:
                    F.add("J02", "deck %d-%d leaves junction %d %.0f degrees off its port" % (a["id"], b["id"], n["id"], off),
                          nodes=[n["id"]], edges=[k])
    for i, n in N.items():
        if is_junction(n):
            ports = len(all_pieces().get(n["junction"]) or [])
            if not 2 <= deg[i] <= (ports or 4):
                F.add("J03", "junction %d (%s) carries %d decks (ports %d)" % (i, n["junction"], deg[i], ports), nodes=[i])
