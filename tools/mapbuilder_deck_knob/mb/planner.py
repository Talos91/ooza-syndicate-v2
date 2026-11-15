"""The approved clearance planner, run outside Blender.

Loads Models/2.0/build_maps_4_2_review.py unchanged (NO_MAIN, with stand-ins for bpy / bmesh / mathutils;
plan_map and its helpers are pure geometry) and adds what Models/2.0/export_maps_4_2_game.py computes on top of
it for plaza-free maps (every pack since 4.2): relay tower mounts, retract gates, the verify block and the
baked "layout". `bake_layout(m)` returns exactly the exporter's layout for a map without plazas."""
import json
import math
import sys
import types

from . import kit
from .vec import Vector

_G = None
FRONT = Vector((0.0, -1.0))          # Rules.front_dir() (Godot +Z, the camera side) in the planner's frame
FRONT_ARC = 45.0                     # degrees either side of the front door kept free of relay pieces


def _load():
    global _G
    if _G is not None:
        return _G
    shimmed = []
    if "bpy" not in sys.modules:                       # plain Python: the planner needs none of these
        for name in ("bpy", "bmesh"):
            sys.modules[name] = types.ModuleType(name)
            shimmed.append(name)
        mu = types.ModuleType("mathutils")
        mu.Vector = Vector
        sys.modules["mathutils"] = mu
        shimmed.append("mathutils")
    g = {"__name__": "builder", "NO_MAIN": True}
    try:
        exec(compile(open(kit.BUILDER, encoding="utf-8").read(), kit.BUILDER, "exec"), g)
    finally:
        for name in shimmed:
            del sys.modules[name]
    _G = g
    return g


def consts():
    g = _load()
    return {k: g[k] for k in ("R", "PIER", "S", "HW", "D_EDGE", "D_SPREAD", "D_PHYS", "CLEAR_H", "MOUNT_DIST",
                              "LEDGE_CLEAR", "STRUCT_R", "K")}


def to_plan(x, y):
    """Map metres (0..160 x 0..80, y down = toward the camera) -> planner frame (centred, y up)."""
    return Vector(((x - 80.0), -(y - 40.0)))


def gd(v):
    return [round(v.x, 4), round(-v.y, 4)]


def front_of(m):
    """Rules.front_dir() for this map in the planner frame: main.gd turns the camera (view_yaw = PI / 2) on maps
    taller than wide, and the front door turns with it (Godot +X = planner +x); else Godot +Z = planner (0, -1)."""
    xs = [n["x"] for n in m["nodes"]]
    ys = [n["y"] for n in m["nodes"]]
    return Vector((1.0, 0.0)) if (max(ys) - min(ys)) > (max(xs) - min(xs)) else Vector((0.0, -1.0))


def angle_from_front(d, front=FRONT):
    """Unsigned angle in degrees between a planner-frame direction and the front door."""
    d = d.normalized()
    return math.degrees(math.acos(max(-1.0, min(1.0, d.dot(front)))))


def ledge_dir_front(g, p, Dk, prof, front=FRONT, arc=FRONT_ARC):
    """The builder's ledge_dir, but never within `arc` degrees of the front door."""
    near = [d for k, d in enumerate(Dk) if prof[k][0] == 0 and
            min((d["A"] - p).length, (d["B"] - p).length,
                (d["A"] + d["u"] * g["seg_param"](p, d["A"], d["u"], d["L"]) - p).length) < 25]
    best, best_d = -1.0, None
    for a in range(0, 360, 4):
        v = Vector((math.cos(math.radians(a)), math.sin(math.radians(a))))
        if angle_from_front(v, front) < arc:
            continue
        worst = 1e9
        for t in range(11):
            q = p + v * (4.6 + 0.5 * t)
            for d in near:
                s = g["seg_param"](q, d["A"], d["u"], d["L"])
                worst = min(worst, (d["A"] + d["u"] * s - q).length)
        if worst > best:
            best, best_d = worst, v
    return best_d if best >= g["LEDGE_CLEAR"] else None


def plan(m, front_aware=False):
    """Run the approved planner and the exporter's plaza-free post-pass. Returns a dict with the raw plan,
    the relay mounts, retract gates and the verify block."""
    g = _load()
    if m.get("plazas"):
        raise ValueError("%s has plazas: bake it with the Blender exporter" % m.get("code"))
    N = {n["id"]: n for n in m["nodes"]}
    p = g["plan_map"](m)
    pos, Dk, prof = p["pos"], p["D"], p["prof"]
    relays, mount_pt, on_socket = {}, {}, []
    for i, n in N.items():
        relay = n.get("relay") or ""
        if not relay or relay == "retract":
            continue
        d = ledge_dir_front(g, pos[i], Dk, prof, front_of(m)) if front_aware else g["ledge_dir"](pos[i], Dk, prof)
        if d is not None:
            relays[i] = {"mount": gd(d)}
            mount_pt[i] = pos[i] + d * g["MOUNT_DIST"]
            continue
        on_socket.append(i)
        relays[i] = {"mount": None}
        mount_pt[i] = pos[i]
    short, off_length, edges, gates = 0, [], [], []
    for k, e in enumerate(m["edges"]):
        dk = Dk[k]
        A, B, u, L, p0, p1 = dk["A"], dk["B"], dk["u"], dk["L"], dk["p0"], dk["p1"]
        if L - p0 - p1 < 0.0:
            short += 1
        honest = kit.S * (float(e["modules"]) if e.get("modules") is not None else kit.MODS[e["tier"]] * kit.DECK_K)   # DECK KNOB: `modules` (baked) or tier x knob
        if prof[k][0] == 0 and abs((L - p0 - p1) - honest) > 1.5:
            off_length.append("%d-%d %s %.1f m" % (e["from"], e["to"], e["tier"], L - p0 - p1))
        h, r0, r1 = prof[k]
        edges.append({"A": gd(A), "B": gd(B), "L": round(L, 4), "p0": round(p0, 4), "p1": round(p1, 4),
                      "lean0": round(dk["pier0"]["lean"], 3), "lean1": round(dk["pier1"]["lean"], 3),
                      "plaza0": False, "plaza1": False, "h": h, "r0": round(r0, 4), "r1": round(r1, 4),
                      "dock": False})
        if e.get("retracts") or e.get("state") == "ret":
            ctrl = e.get("relay")
            for end, (node, pt, dd) in enumerate(((e["from"], A, u), (e["to"], B, -u))):
                if ctrl is None or ctrl == node:
                    if (N[node].get("relay") or "") == "retract":
                        gates.append({"node": node, "edge": k, "pos": pt, "dir": dd})
    ledge_hits = 0
    for i, tower in mount_pt.items():
        if i in on_socket:
            continue
        d = (tower - pos[i]).normalized()
        for k in range(len(m["edges"])):
            A, u, L = Dk[k]["A"], Dk[k]["u"], Dk[k]["L"]
            for t in range(11):
                q = pos[i] + d * (4.6 + 0.5 * t)
                s = g["seg_param"](q, A, u, L)
                if (A + u * s - q).length < 2.35 + 1.74 + 0.2 and prof[k][0] == 0:
                    ledge_hits += 1
                    break
    verify = {"clashes": len(p["clashes"]), "over_platform": p["over_platform"], "short": short,
              "ledge_hits": ledge_hits, "tower_on_socket": on_socket, "docks": 0, "off_length": off_length}
    layout = {"K": g["K"], "nodes": {str(i): gd(pos[i]) for i in N}, "plazas": {}, "edges": edges,
              "relays": {str(i): v for i, v in relays.items()}, "glb": "", "verify": verify}
    return {"raw": p, "pos": pos, "front": front_of(m), "D": Dk, "prof": prof, "mount_pt": mount_pt, "on_socket": on_socket,
            "gates": gates, "verify": verify, "layout": layout, "clash_pairs": p["clashes"]}


def bake_layout(m, front_aware=False):
    return plan(m, front_aware)["layout"]


if __name__ == "__main__":                              # smoke: python -m mb.planner <map.json>
    m = json.load(open(sys.argv[1], encoding="utf-8"))
    print(json.dumps(plan(m)["verify"]))
