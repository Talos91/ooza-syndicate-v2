"""Throwaway RELAY V2 composability board (tests/relay_multi.json, never in the pool): a 6-bridge switch, a rotation
carrying 3 decks (6 headings, r1 / r2), a node with 2 retract bridges, a remote driving decks on 2 different nodes.
Straight radial piers (lean 0) at honest M lengths (23.2 m centre to centre)."""
import json, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay_multi.json")
R, PIER, M = 6.0, 1.6, 23.2
nodes = {}          # id -> (x, y, relay)
def add(i, x, y, relay=None):
    nodes[i] = (x, y, relay)
def ring(c, first, r=M, a0=0.0):
    for k in range(6):
        a = math.radians(a0 + 60 * k)
        add(first + k, c[0] + r * math.cos(a), c[1] + r * math.sin(a))

add(0, 0.0, 0.0, "switch")                 # SW: six bridges, s1..s6
ring((0.0, 0.0), 1)                        # 1..6 round SW (1 at 0 deg, 4 at 180 deg)
add(7, 2 * M, 0.0, "rotation")             # RO: node 1 is its 180 deg neighbour
ring((2 * M, 0.0), 8)                      # 8..13 round RO (11 at 180 deg = on top of node 1: drop it)
del nodes[11]
add(14, 0.0, -2 * M * math.sin(math.radians(60)), "retract")   # RT below, bridges to 5 (240) and 6 (300)
add(15, 0.0, 2 * M * math.sin(math.radians(60)), "remote")     # RC above, fixed to 2 and 3

edges = []
def edge(a, b, state=None, relay=None, retracts=False):
    edges.append((a, b, state, relay, retracts))
for k in range(6):                          # the 6-way switch
    edge(0, 1 + k, "s%d" % (k + 1), 0)
ro = [8, 9, 10, 1, 12, 13]                  # RO's six headings (0, 60, .. 300 deg); 180 deg is node 1
for k, nb in enumerate(ro):                 # r1 on 0/120/240, r2 on 60/180/300: three decks turn together
    edge(7, nb, "r1" if k % 2 == 0 else "r2", 7)
edge(14, 5, None, 14, True)                 # two retract bridges on RT
edge(14, 6, None, 14, True)
edge(15, 2)                                 # RC's own fixed bridges
edge(15, 3)
edge(8, 9, "m1", 15)                        # RC drives a deck by RO ...
edge(4, 5, "m1", 15)                        # ... and one by SW (different nodes)
edge(2, 3)                                  # a few fixed decks keep the board whole
edge(9, 10)
edge(12, 13)
edge(13, 8)
edge(5, 6)
edge(3, 4)

lay_nodes = {str(i): [round(x, 4), round(y, 4)] for i, (x, y, _) in nodes.items()}
lay_edges, map_edges = [], []
for a, b, st, rl, ret in edges:
    pa, pb = nodes[a], nodes[b]
    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
    dist = math.hypot(dx, dy)
    ux, uy = dx / dist, dy / dist
    A = [round(pa[0] + ux * R, 4), round(pa[1] + uy * R, 4)]
    B = [round(pb[0] - ux * R, 4), round(pb[1] - uy * R, 4)]
    L = dist - 2 * R
    mods = max(1, round((L - 2 * PIER) / 4.0))
    lay_edges.append({"A": A, "B": B, "L": round(L, 4), "p0": PIER, "p1": PIER, "lean0": 0.0, "lean1": 0.0,
                      "plaza0": False, "plaza1": False, "h": 0.0, "r0": 0.0, "r1": 0.0, "dock": False})
    map_edges.append({"from": a, "to": b, "tier": {1: "S", 2: "M", 3: "L"}.get(mods, "L"), "seconds": 4, "level": 0,
                      "state": ("ret" if ret else st), "relay": rl, "retracts": ret, "deckMetres": mods * 4.0,
                      "centreDistance": round(dist, 2), "nominal": round(dist, 2)})
ids = sorted(nodes)
remap = {old: new for new, old in enumerate(ids)}      # Sim wants ids 0..N-1 in array order
map_nodes = []
for old in ids:
    x, y, relay = nodes[old]
    map_nodes.append({"id": remap[old], "x": x, "y": y, "plaza": None, "socket": None, "ring": 1,
                      "category": "relay" if relay else "normal", "relay": relay, "home": old in (4, 10), "neutral": None,
                      "buildable": ["laser", "forge", "monster_hub"] if relay else ["vat", "machingoon"]})
for e in map_edges:
    e["from"], e["to"] = remap[e["from"]], remap[e["to"]]
    if e["relay"] is not None:
        e["relay"] = remap[e["relay"]]
lay_nodes = {str(remap[int(k)]): v for k, v in lay_nodes.items()}
out = {"code": "X-RM", "name": "Relay Multi (test)", "group": "test", "players": "versus", "playersLabel": "1v1",
       "combatMode": "brawl", "family": "test", "modes": ["1v1"], "symmetry": "none", "plazas": [],
       "nodes": map_nodes, "edges": map_edges, "rings": {"count": 1, "boundaries": [], "aspect": 1.0, "shape": "ellipse"},
       "lastStand": {"methods": [], "orders": {}},
       "seats": {"1v1": [{"seat": "A", "node": remap[4], "team": 0}, {"seat": "B", "node": remap[10], "team": 1}]},
       "note": "RELAY V2 composability board (tests/, never pooled): 6-bridge switch SW, rotation RO carrying 3 decks, "
               "retract RT with 2 bridges, remote RC driving decks on 2 different nodes. make_relay_multi.py.",
       "names": {"SW": remap[0], "RO": remap[7], "RT": remap[14], "RC": remap[15]},
       "layout": {"K": 1.0, "nodes": lay_nodes, "plazas": {}, "edges": lay_edges, "relays": {}, "glb": "", "verify": {}}}
json.dump(out, open(OUT, "w", encoding="utf-8"), indent=1)
print("wrote", OUT, len(map_nodes), "nodes", len(map_edges), "edges", out["names"])
