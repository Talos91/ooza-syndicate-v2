"""A chain builder for EXPERIMENTAL Build page maps (Daniele 2026-09-29: "we touch no rule, nothing goes in staging or
release or test, this is for us"). It mirrors Tools/MapBuilder/editor/build.html's geometry so the page draws every
bridge without a red line:

  platform rim R 6 + pier 1.6 (kit.R, kit.PIER); a deck is modules x 4 m; a platform end sits at centre + dir(ang) x 7.6
  junction / curve / S-bend ports = ports() (piece yaw ccw, y UP inside the piece, map y DOWN); a curve's origin is its
  start port; a piece set on a bridge end turns so the entering port faces back along the bridge (poseOnEnd)

A map is built as a turtle walk: go(platform, ang) / go(piece, port) puts the cursor on a socket, deck(n) lays a bridge
along the cursor, piece()/curve()/sbend() set a piece on its end, plat() ends it on a new platform, to() closes it on an
existing node, flex() lays a flex S-bridge between two sockets. sym("rot") / sym("mirror") copies the half map by a
half turn about the frame centre or a left / right mirror (any piece: the copy is searched port by port). check()
replays build.html's fromMap() (greedy port pick) and deckEnds().ok, plus overlap checks, and returns the problems."""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from mb import junctions, kit  # noqa: E402

R, PIER, S = kit.R, kit.PIER, kit.S
K = kit.DECK_K
RP = R + PIER
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPP = json.load(open(os.path.join(HERE, "editor", "experimental", "pieces.json"), encoding="utf-8"))
PIECES = {k: [(p["angle_deg"], p["edge_centre"][0], p["edge_centre"][1]) for p in v] for k, v in junctions.all_pieces().items()}
PIECES.update({k: [(p["angle_deg"], p["edge_centre"][0], p["edge_centre"][1]) for p in v] for k, v in EXPP["pieces"].items()})
EXP_NAMES = set(EXPP["pieces"])
OUT = os.path.join(kit.REFS, "Ooze Syndicate maps - experimental", "json")


def norm(a):
    return a % 360.0


def adiff(a, b):
    return abs((a - b + 540.0) % 360.0 - 180.0)


def dirv(a):
    return (math.cos(math.radians(a)), -math.sin(math.radians(a)))


def ang_to(p, q):
    return norm(math.degrees(math.atan2(-(q[1] - p[1]), q[0] - p[0])))


def rot(x, y, yaw):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return x * c - y * s, x * s + y * c


def tier_of(n):
    return "S" if n <= 1 else "M" if n == 2 else "L"


class Map:
    def __init__(self, code, name, note, frame=(160, 80)):
        self.code, self.name, self.note, self.frame = code, name, note, frame
        self.nodes = []          # {kind p|j, name, x, y, yaw, piece, role, relay, tier, structure, core}
        self.edges = []          # {a:(i, port|None), b:(i, port|None), mods, joint, shape, state, retracts, relay}
        self.by = {}
        self.cur = None          # (att, x, y, a)
        self.pend = None         # an open deck: {a, mods, ...}
        self.last = None
        self.outward = False
        self.symmetry = "point (half turn)"

    # ------------------------------------------------------------------ nodes
    def _add(self, n):
        n["i"] = len(self.nodes)
        self.nodes.append(n)
        if n.get("name"):
            assert n["name"] not in self.by, n["name"]
            self.by[n["name"]] = n["i"]
        return n["i"]

    def P(self, name, x, y, role="normal", tier=1, structure="vat", relay=None, core=False):
        """a platform; role normal | homeA | homeB | hill | relay (relay = rotation | switch | retract)"""
        return self._add({"kind": "p", "name": name, "x": x, "y": y, "role": role, "tier": tier, "structure": structure,
                          "relay": relay, "core": core})

    def J(self, name, piece, x, y, yaw, core=False):
        assert piece in PIECES, piece
        return self._add({"kind": "j", "name": name, "piece": piece, "x": x, "y": y, "yaw": norm(yaw), "core": core})

    def idx(self, n):
        return self.by[n] if isinstance(n, str) else n

    def node(self, n):
        return self.nodes[self.idx(n)]

    def ports(self, n):
        n = self.node(n)
        out = []
        for a, x, y in PIECES[n["piece"]]:
            rx, ry = rot(x, y, n["yaw"])
            out.append((n["x"] + rx, n["y"] - ry, norm(a + n["yaw"])))
        return out

    def anchor(self, att):
        i, port = att
        n = self.nodes[i]
        if n["kind"] == "p":
            d = dirv(port)                       # for a platform the "port" is the pier angle
            return (n["x"] + d[0] * RP, n["y"] + d[1] * RP, port)
        return self.ports(i)[port]

    # ------------------------------------------------------------------ the turtle
    def go(self, n, ang_or_port):
        i = self.idx(n)
        att = (i, norm(ang_or_port) if self.nodes[i]["kind"] == "p" else ang_or_port)
        x, y, a = self.anchor(att)
        self.cur = (att, x, y, a)
        self.pend = None
        self.last = i
        return self

    def out(self, port):
        return self.go(self.last, port)

    def deck(self, mods, state=None, relay=None, retract=None):
        """a bridge of `mods` 4 m modules along the cursor; state r1/r2 + relay (rotor) or retract=<relay platform>"""
        assert self.pend is None, "deck on a deck: use a Link"
        att, x, y, a = self.cur
        self.pend = {"a": att, "mods": mods, "state": state, "relay": relay, "retract": retract}
        d = dirv(a)
        L = mods * S * K
        self.cur = (None, x + d[0] * L, y + d[1] * L, a)
        return self

    def _close(self, att, joint=False):
        if self.pend is not None:
            e = dict(self.pend)
            e["b"] = att
            self.edges.append(e)
            self.pend = None
        elif joint:
            self.edges.append({"a": self.cur[0], "b": att, "mods": 0, "joint": True})
        else:
            raise AssertionError("nothing to close")

    def piece(self, name, piece, enter, exit=None, core=False):
        """set a piece on the cursor with port `enter` facing back; joint when no deck is open"""
        _, x, y, a = self.cur
        back = norm(a + 180)
        qa, qx, qy = PIECES[piece][enter]
        yaw = norm(back - qa)
        rx, ry = rot(qx, qy, yaw)
        i = self.J(name, piece, x - rx, y + ry, yaw, core)
        self._close((i, enter), joint=self.pend is None)
        self.last = i
        if exit is not None:
            self.out(exit)
        return self

    def curve(self, name, piece, turn, core=False):
        """a curve turning left (turn > 0) or right; leaves the cursor on its far port"""
        return self.piece(name, piece, 0 if turn > 0 else 1, 1 if turn > 0 else 0, core)

    def sbend(self, name, piece, core=False):
        return self.piece(name, piece, 0, 1, core)

    def link(self, name, core=False):
        return self.piece(name, "Link", 0, 1, core)

    def plat(self, name, **kw):
        _, x, y, a = self.cur
        d = dirv(a)
        i = self.P(name, x + d[0] * RP, y + d[1] * RP, **kw)
        self._close((i, norm(a + 180)))
        self.last = i
        return self

    def to(self, n, port=None):
        i = self.idx(n)
        nd = self.nodes[i]
        if nd["kind"] == "p":
            att = (i, ang_to((nd["x"], nd["y"]), self.cur[1:3]))
        else:
            att = (i, port)
        self._close(att, joint=self.pend is None)
        self.last = i
        return self

    def pp(self, name, frm, ang, mods, deck_kw=None, **kw):
        """a new platform `mods` modules from platform / port `frm` (ang = pier angle or port)"""
        return self.go(frm, ang).deck(mods, **(deck_kw or {})).plat(name, **kw)

    def tri(self, name, a, na, b, nb, side=1, **kw):
        """a new platform an honest na-module bridge from platform a and nb from b (side +1 / -1 picks the solution)"""
        A, B = self.node(a), self.node(b)
        ra, rb = 2 * RP + na * S * K, 2 * RP + nb * S * K
        d = math.hypot(B["x"] - A["x"], B["y"] - A["y"])
        assert abs(ra - rb) < d < ra + rb, "tri %s: no solution (d %.1f, %.1f + %.1f)" % (name, d, ra, rb)
        t = (ra * ra - rb * rb + d * d) / (2 * d)
        h = math.sqrt(max(0, ra * ra - t * t))
        ux, uy = (B["x"] - A["x"]) / d, (B["y"] - A["y"]) / d
        x, y = A["x"] + t * ux - side * h * uy, A["y"] + t * uy + side * h * ux
        i = self.P(name, x, y, **kw)
        return i

    def join(self, a, b, mods, **deck_kw):
        """a straight bridge between two platforms (their pier angles aim at each other)"""
        A, B = self.node(a), self.node(b)
        ab = ang_to((A["x"], A["y"]), (B["x"], B["y"]))
        self.go(a, ab).deck(mods, **deck_kw).to(b)
        return self

    def flex(self, a_att, b_att, state=None, relay=None, retract=None):
        """a flex S-bridge between two sockets: (node, ang) for a platform, (node, port) for a piece"""
        a = (self.idx(a_att[0]), a_att[1])
        b = (self.idx(b_att[0]), b_att[1])
        self.edges.append({"a": a, "b": b, "mods": "flex", "shape": "sbend", "state": state, "relay": relay, "retract": retract})
        return self

    def edge(self, a, b, mods, **kw):
        """a straight bridge between two existing sockets (checked like the page)"""
        self.edges.append(dict({"a": (self.idx(a[0]), a[1]), "b": (self.idx(b[0]), b[1]), "mods": mods}, **kw))
        return self

    def shift(self, dx, dy):
        for n in self.nodes:
            n["x"] += dx
            n["y"] += dy
        return self

    def near(self, lim=31):
        """platform pairs not yet bridged whose distance is close to an honest S / M / L / 16 / 20 m bridge"""
        bridged = {frozenset((e["a"][0], e["b"][0])) for e in self.edges}
        ps = [n for n in self.nodes if n["kind"] == "p"]
        for i, a in enumerate(ps):
            for b in ps[i + 1:]:
                d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
                if d > 2 * RP + 5 * S + 1 or frozenset((a["i"], b["i"])) in bridged:
                    continue
                n = round((d - 2 * RP) / S * 2) / 2
                err = d - 2 * RP - n * S
                if abs(err) < 1.0 and n >= 0.5:
                    print("   near %s-%s %.1f m -> %g modules (%+.2f)" % (a["name"], b["name"], d, n, err))

    def where(self, *names):
        for nm in names:
            n = self.node(nm)
            print("   %s at (%.2f, %.2f)%s" % (nm, n["x"], n["y"], " yaw %.1f" % n["yaw"] if n["kind"] == "j" else ""))

    # ------------------------------------------------------------------ symmetry
    def _xf(self, kind):
        cx, cy = self.frame[0] / 2, self.frame[1] / 2
        if kind == "rot":
            return (lambda x, y: (2 * cx - x, 2 * cy - y)), (lambda a: norm(a + 180))
        return (lambda x, y: (2 * cx - x, y)), (lambda a: norm(180 - a))

    def _pose_for(self, piece, want):
        """a pose of `piece` (or its S-bend twin) whose ports land on `want` [(x, y, a)]; returns (piece, x, y, yaw, map)"""
        cands = [piece] + ([EXPP["info"][piece]["twin"]] if EXPP["info"].get(piece, {}).get("twin") else [])
        for pc in cands:
            base = PIECES[pc]
            if len(base) != len(want):
                continue
            for k, (wx, wy, wa) in enumerate(want):
                for qa, qx, qy in base:
                    yaw = norm(wa - qa)
                    rx, ry = rot(qx, qy, yaw)
                    ox, oy = wx - rx, wy + ry
                    got = []
                    for ba, bx, by in base:
                        sx, sy = rot(bx, by, yaw)
                        got.append((ox + sx, oy - sy, norm(ba + yaw)))
                    mp = []
                    for w in want:
                        hit = [j for j, g in enumerate(got) if math.hypot(g[0] - w[0], g[1] - w[1]) < 0.05 and adiff(g[2], w[2]) < 0.5]
                        mp.append(hit[0] if hit else -1)
                    if all(j >= 0 for j in mp) and len(set(mp)) == len(mp):
                        return pc, ox, oy, yaw, mp
        raise AssertionError("no mirrored pose for " + piece)

    def mark(self):
        return (len(self.nodes), len(self.edges))

    def sym(self, kind="rot", since=(0, 0)):
        """copy the nodes / edges made since `since` (a mark()) by the symmetry; earlier nodes keep their first copies"""
        P, A = self._xf(kind)
        self.symmetry = "point (half turn)" if kind == "rot" else "mirror left/right"
        if since == (0, 0):
            self.twin, self.pmap = {}, {}
        twin, pmap = self.twin, self.pmap
        n0 = len(self.nodes)
        for n in list(self.nodes[since[0]:n0]):
            x, y = P(n["x"], n["y"])
            if n["kind"] == "p":
                if math.hypot(x - n["x"], y - n["y"]) < 0.3:
                    twin[n["i"]] = n["i"]
                    continue
                role = {"homeA": "homeB", "homeB": "homeA"}.get(n["role"], n["role"])
                twin[n["i"]] = self.P(n["name"] + "'", x, y, role, n["tier"], n["structure"], n["relay"], n["core"])
                continue
            want = [(*P(px, py), A(pa)) for px, py, pa in self.ports(n["i"])]
            pc, ox, oy, yaw, mp = self._pose_for(n["piece"], want)
            own = self.ports(n["i"])
            hit = [[j for j, g in enumerate(own) if math.hypot(g[0] - w[0], g[1] - w[1]) < 0.05 and adiff(g[2], w[2]) < 0.5] for w in want]
            if all(hit) and pc == n["piece"]:
                twin[n["i"]] = n["i"]            # on the axis / centre: itself, ports swapped
                pmap[n["i"]] = [h[0] for h in hit]
                continue
            twin[n["i"]] = self.J(n["name"] + "'", pc, ox, oy, yaw, n["core"])
            pmap[n["i"]] = mp

        for o, c in list(twin.items()):                # the copies map back (both symmetries are involutions)
            if c != o and c not in twin:
                twin[c] = o
                if o in pmap:
                    inv = [0] * len(pmap[o])
                    for k, j in enumerate(pmap[o]):
                        inv[j] = k
                    pmap[c] = inv

        def matt(att):
            i, p = att
            if self.nodes[i]["kind"] == "p":
                return (twin[i], A(p))
            return (twin[i], pmap[i][p])
        for e in list(self.edges[since[1]:]):
            a, b = matt(e["a"]), matt(e["b"])
            if {a, b} == {e["a"], e["b"]}:
                continue
            c = dict(e, a=a, b=b)
            for k in ("relay", "retract"):
                if c.get(k) is not None:
                    c[k] = twin[self.idx(c[k])]
            self.edges.append(c)
        return self

    # ------------------------------------------------------------------ the page's view of it
    def flex_pts(self, A, B):
        c = math.hypot(B[0] - A[0], B[1] - A[1])
        k = max(1.5, c * 0.42)
        u, v = dirv(A[2]), dirv(B[2])
        Pp = [(A[0], A[1]), (A[0] + u[0] * k, A[1] + u[1] * k), (B[0] + v[0] * k, B[1] + v[1] * k), (B[0], B[1])]
        pts = []
        for i in range(33):
            t = i / 32
            m = 1 - t
            pts.append(tuple(m ** 3 * Pp[0][j] + 3 * m * m * t * Pp[1][j] + 3 * m * t * t * Pp[2][j] + t ** 3 * Pp[3][j] for j in (0, 1)))
        return pts

    def to_json(self):
        # X03 (rulebook, 2026-10-28): a Crossing is written as TWO lane nodes at one point - the ground lane (ports 0 / 2)
        # and the over lane (ports 1 / 3, drawn by nobody: junctionDraw false) - so decks join only within a lane.
        vnodes = list(self.nodes)
        lane_of = {}                                      # (node index, port) -> virtual node index for the over lane
        for n in list(self.nodes):
            if n["kind"] == "j" and n["piece"] == "Crossing":
                v = dict(n, i=len(vnodes), name=n["name"] + "^", lane="over")
                vnodes.append(v)
                lane_of[(n["i"], 1)] = v["i"]
                lane_of[(n["i"], 3)] = v["i"]
        vedges = []
        for e in self.edges:
            c = dict(e)
            for side in ("a", "b"):
                att = c[side]
                if att in lane_of:
                    c[side] = (lane_of[att], att[1])
            vedges.append(c)
        order = sorted(range(len(vnodes)), key=lambda i: (round(vnodes[i]["y"], 2), round(vnodes[i]["x"], 2), i))
        idx = {old: new for new, old in enumerate(order)}
        nodes = []
        core_of = {}
        for e in vedges:
            for me, ot in (("a", "b"), ("b", "a")):
                core_of.setdefault(e[me][0], []).append(e[ot][0])
        for new, old in enumerate(order):
            p = vnodes[old]
            n = {"id": new, "x": round(p["x"], 2), "y": round(p["y"], 2), "plaza": None, "socket": None,
                 "ring": 0 if p["core"] else 1, "category": "normal", "relay": None, "home": False, "neutral": None,
                 "buildable": ["vat"]}
            if p["kind"] == "j":
                n.update(category="junction", buildable=[], junction=p["piece"], junctionYaw=round(p["yaw"], 2))
                n["ring"] = 0 if p["core"] or any(vnodes[o]["kind"] == "p" and vnodes[o]["core"] for o in core_of.get(old, [])) else 1
                if p.get("lane"):                     # the over lane hangs on its ramps (relay decks) only: it falls with
                    n.update(lane=p["lane"], junctionDraw=False, ring=1)   # the outer ring (the game drops islands)
            elif p["role"] in ("homeA", "homeB"):
                n["home"] = True
            elif p["role"] == "hill":
                n.update(category="strategic", neutral={"tier": 4, "structure": "vat"})
            elif p["role"] == "relay":
                n.update(category="relay", relay=p["relay"], neutral={"tier": 2, "structure": p["structure"] if p["structure"] != "vat" else "laser"},
                         buildable=["laser", "forge", "monster_hub"])
            else:
                n["neutral"] = {"tier": p["tier"], "structure": p["structure"]}
            nodes.append(n)
        tags = {}
        for old in sorted(i for i, p in enumerate(self.nodes) if p["kind"] == "p" and p["role"] == "relay"):
            tags[old] = chr(65 + len(tags))
        for old, t in tags.items():
            nodes[idx[old]]["relayTag"] = t
        edges = []
        for e in vedges:
            m = e["mods"]
            o = {"from": idx[e["a"][0]], "to": idx[e["b"][0]], "tier": "M", "seconds": 0, "level": 0, "state": None,
                 "relay": None, "retracts": False, "deckMetres": 0}
            if e.get("joint"):
                o.update(tier="S", joint=True, modules=0, seconds=0, deckMetres=0)
            elif m == "flex":
                A, B = self.anchor(e["a"]), self.anchor(e["b"])
                pts = self.flex_pts(A, B)
                L = sum(math.dist(pts[i], pts[i - 1]) for i in range(1, len(pts)))
                o.update(tier="M", shape="sbend", deckMetres=round(L, 2), modules=round(L / S, 2), seconds=round(L / 2, 1))
            else:
                o.update(tier=tier_of(m), seconds=m * 2, deckMetres=round(m * K * S, 3))
                if m > 3 or m % 1 or K != 1:
                    o["modules"] = round(m * K, 4)
            if e.get("retract") is not None:
                o.update(retracts=True, relay=idx[self.idx(e["retract"])])
            elif e.get("state"):
                o.update(state=e["state"], relay=idx[self.idx(e["relay"])])
            edges.append(o)
        homes = [i for i, p in enumerate(self.nodes) if p.get("role") in ("homeA", "homeB")]
        seats = [{"seat": self.nodes[i]["role"][4], "node": idx[i], "team": 0 if self.nodes[i]["role"] == "homeA" else 1}
                 for i in sorted(homes, key=lambda i: self.nodes[i]["role"])]
        methods = ["inward", "outward"] if self.outward else ["inward"]
        orders = {"inward": [1, 0]}
        if self.outward:
            orders["outward"] = [0, 1]
        out = {"code": self.code, "name": self.name, "group": "experimental", "players": "versus", "playersLabel": "1v1 (2 homes)",
               "combatMode": "both", "family": "build page", "modes": ["1v1"], "symmetry": self.symmetry,
               "frame": {"width": self.frame[0], "height": self.frame[1], "units": "metres", "version": "5.0"},
               "minEnemyHomeHops": 2, "centreSpawn": False, "plazas": [], "nodes": nodes, "edges": edges,
               "rings": {"count": 2, "boundaries": [30], "aspect": 2, "shape": "ellipse"},
               "lastStand": {"methods": methods, "orders": orders}, "seats": {"1v1": seats},
               "note": self.note, "geometricSymmetry": True, "labVariant": {"junctions": True}, "experimental": True}
        if getattr(self, "waivers", None):
            out["ruleWaivers"] = dict(self.waivers)
        try:                                              # tags (M05) from the rulebook's own reading
            from mb import rules as _rules
            out["tags"] = _rules.tags_of(out)
        except Exception:
            pass
        return out

    # ------------------------------------------------------------------ checks
    def check(self):
        """build.html's fromMap() + deckEnds().ok on the written map, plus overlaps and the relay / layout rules"""
        m = self.to_json()
        N = m["nodes"]
        probs = []
        pts = {}

        def nports(n):
            out = []
            for a, x, y in PIECES[n["junction"]]:
                rx, ry = rot(x, y, n["junctionYaw"])
                out.append((n["x"] + rx, n["y"] - ry, norm(a + n["junctionYaw"])))
            return out
        taken = set()

        def att_for(i, o):
            n, on = N[i], N[o]
            if not n.get("junction"):
                return ("p", ang_to((n["x"], n["y"]), (on["x"], on["y"])))
            ps = nports(n)
            want = ang_to((n["x"], n["y"]), (on["x"], on["y"]))
            best, bd = 0, 1e9
            for k, q in enumerate(ps):
                if (i, k) in taken:
                    continue
                dd = math.hypot(q[0] - on["x"], q[1] - on["y"]) if n["junction"].startswith("Curve") else adiff(q[2], want)
                if dd < bd:
                    bd, best = dd, k
            taken.add((i, best))
            return ("j", best)
        decks = []
        for e in m["edges"]:
            decks.append([e, att_for(e["from"], e["to"]), att_for(e["to"], e["from"])])

        def anc(i, att):
            n = N[i]
            if att[0] == "p":
                d = dirv(att[1])
                return (n["x"] + d[0] * RP, n["y"] + d[1] * RP, att[1])
            return nports(n)[att[1]]
        for d in decks:                                   # platform ends face the other end's anchor exactly
            e = d[0]
            for me, ot, mi, oi in ((1, 2, e["from"], e["to"]), (2, 1, e["to"], e["from"])):
                if d[me][0] != "p":
                    continue
                O = anc(oi, d[ot]) if d[ot][0] == "j" else (N[oi]["x"], N[oi]["y"])
                d[me] = ("p", ang_to((N[mi]["x"], N[mi]["y"]), O[:2]))
        segs = []
        # the intended ports (this builder) vs. the page's greedy pick
        mine = {}
        order = sorted(range(len(self.nodes)), key=lambda i: (round(self.nodes[i]["y"], 2), round(self.nodes[i]["x"], 2)))
        idx = {old: new for new, old in enumerate(order)}
        for k, (e0, d) in enumerate(zip(self.edges, decks)):
            for side, s in (("a", 1), ("b", 2)):
                i = e0[side][0]
                if self.nodes[i]["kind"] == "j" and d[s][1] != e0[side][1]:
                    probs.append("edge %d: the page picks port %d on %s, meant %d" % (k, d[s][1], self.nodes[i]["name"], e0[side][1]))
        for k, d in enumerate(decks):
            e = d[0]
            A, B = anc(e["from"], d[1]), anc(e["to"], d[2])
            if e.get("shape") == "sbend":
                c = math.hypot(B[0] - A[0], B[1] - A[1])
                if not 2 < c < 32:
                    probs.append("edge %d: flex chord %.1f" % (k, c))
                segs.append((k, e, self.flex_pts(A, B)))
                continue
            if e.get("joint"):
                if math.hypot(B[0] - A[0], B[1] - A[1]) >= 0.5 or adiff(A[2], norm(B[2] + 180)) >= 3:
                    probs.append("edge %d: joint misses (%.2f m, %.1f deg)" % (k, math.hypot(B[0] - A[0], B[1] - A[1]), adiff(A[2], norm(B[2] + 180))))
                continue
            L = e.get("modules", {"S": 1, "M": 2, "L": 3}[e["tier"]]) * S
            dist = math.hypot(B[0] - A[0], B[1] - A[1])
            da = adiff(ang_to(A[:2], B[:2]), A[2])
            if abs(dist - L) >= 1.0 or da >= 4:
                probs.append("edge %d %s-%s: RED (len %.2f vs %.0f, angle %.1f)" % (k, e["from"], e["to"], dist, L, da))
            if adiff(ang_to(B[:2], A[:2]), B[2]) > 2.5:
                probs.append("edge %d: far end enters at %.1f deg" % (k, adiff(ang_to(B[:2], A[:2]), B[2])))
            segs.append((k, e, [A[:2], B[:2]]))
        # overlaps: platforms apart, bridges clear of other platforms and of each other
        plats = [n for n in N if not n.get("junction")]
        for i, a in enumerate(plats):
            for b in plats[i + 1:]:
                if math.dist((a["x"], a["y"]), (b["x"], b["y"])) < 2 * R + 3:
                    probs.append("platforms %d and %d overlap" % (a["id"], b["id"]))
        for n in N:
            if n["x"] < 7 or n["y"] < 7 or n["x"] > self.frame[0] - 7 or n["y"] > self.frame[1] - 7:
                probs.append("node %d (%.0f, %.0f) is outside the frame" % (n["id"], n["x"], n["y"]))
        for n in N:
            if n.get("junction"):
                for p in plats:
                    rr = max(math.hypot(q[1], q[2]) for q in PIECES[n["junction"]])
                    if math.dist((n["x"], n["y"]), (p["x"], p["y"])) < R + 0.5 and True:
                        probs.append("junction %d sits on platform %d" % (n["id"], p["id"]))

        def segd(p, a, b):
            ax, ay = b[0] - a[0], b[1] - a[1]
            L2 = ax * ax + ay * ay or 1e-9
            t = max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L2))
            return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)

        def cross(p1, p2, q1, q2):
            def o(a, b, c):
                return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            return (o(p1, p2, q1) * o(p1, p2, q2) < 0) and (o(q1, q2, p1) * o(q1, q2, p2) < 0)
        for k, e, pl in segs:
            for p in N:
                if p["id"] in (e["from"], e["to"]):
                    continue
                lim = R + 1.0 if not p.get("junction") else 1.2
                if p.get("junction"):
                    continue
                for a, b in zip(pl, pl[1:]):
                    if segd((p["x"], p["y"]), a, b) < lim:
                        probs.append("edge %d runs over platform %d" % (k, p["id"]))
                        break
        for x in range(len(segs)):
            for y in range(x + 1, len(segs)):
                k1, e1, p1 = segs[x]
                k2, e2, p2 = segs[y]
                if any(c in (e2["from"], e2["to"]) for c in (e1["from"], e1["to"])):
                    continue
                hit = any(cross(a, b, c, d) for a, b in zip(p1, p1[1:]) for c, d in zip(p2, p2[1:]))
                if hit:
                    probs.append("edges %d and %d cross" % (k1, k2))
        # degree, relays
        deg = {}
        for e in m["edges"]:
            for s in ("from", "to"):
                deg[e[s]] = deg.get(e[s], 0) + 1
        for n in N:
            d = deg.get(n["id"], 0)
            if not n.get("junction") and d < 2:
                probs.append("platform %d has %d bridge(s)" % (n["id"], d))
            if n.get("junction"):
                np_ = len(PIECES[n["junction"]])
                if d != np_ and n["junction"] != "Crossing":
                    probs.append("%s %d: %d of %d ports used" % (n["junction"], n["id"], d, np_))
        for n in N:
            if n.get("relay") in ("rotation", "switch"):
                st = [e["state"] for e in m["edges"] if e.get("relay") == n["id"]]
                pre = "r" if n["relay"] == "rotation" else "s"
                if st.count(pre + "1") < 2 or st.count(pre + "2") < 2:
                    probs.append("%s %d: %s1 x%d %s2 x%d" % (n["relay"], n["id"], pre, st.count(pre + "1"), pre, st.count(pre + "2")))
                for e in m["edges"]:
                    if e.get("relay") == n["id"] and n["id"] not in (e["from"], e["to"]):
                        probs.append("rotor %d drives a bridge it doesn't touch" % n["id"])
            if n.get("relay") == "retract":
                if not any(e.get("relay") == n["id"] and e.get("retracts") for e in m["edges"]):
                    probs.append("retract relay %d drives nothing" % n["id"])
        # homes far apart
        homes = [s["node"] for s in m["seats"]["1v1"]]
        adj = {}
        for e in m["edges"]:
            adj.setdefault(e["from"], set()).add(e["to"])
            adj.setdefault(e["to"], set()).add(e["from"])
        if len(homes) == 2:
            dist = {homes[0]: 0}
            q = [homes[0]]
            while q:
                v = q.pop(0)
                for w in adj.get(v, ()):
                    if w not in dist:
                        dist[w] = dist[v] + (0 if N[w].get("junction") else 1)
                        q.append(w)
            if dist.get(homes[1], 0) < 3:
                probs.append("homes only %s platform hops apart" % dist.get(homes[1]))
        return probs, m

    def stats(self, m):
        plats = [n for n in m["nodes"] if not n.get("junction")]
        pieces = sorted({n["junction"] for n in m["nodes"] if n.get("junction")})
        xs, ys = [n["x"] for n in m["nodes"]], [n["y"] for n in m["nodes"]]
        return "%d platforms, %d pieces (%s), %d bridges, span %.0f x %.0f m" % (
            len(plats), len(m["nodes"]) - len(plats), ", ".join(pieces), len(m["edges"]),
            max(xs) - min(xs) + 2 * R, max(ys) - min(ys) + 2 * R)

    def write(self, slug):
        probs, m = self.check()
        os.makedirs(OUT, exist_ok=True)
        p = os.path.join(OUT, "%s-%s.json" % (self.code, slug))
        json.dump(m, open(p, "w", encoding="utf-8"), indent=1)
        return p, probs, m


def preview(maps, path, cols=2, cw=800, ch=430):
    """a quick schematic sheet (PIL): platforms, piece ports, bridges by state - for iterating before the page check"""
    from PIL import Image, ImageDraw
    rows = (len(maps) + cols - 1) // cols
    im = Image.new("RGB", (cols * cw, rows * ch), "#0b0f14")
    dr = ImageDraw.Draw(im)
    COL = {"r1": "#ffd23f", "r2": "#ff8c2a", "ret": "#ff5a5a"}
    for k, (mp, m, probs) in enumerate(maps):
        ox, oy = (k % cols) * cw, (k // cols) * ch
        W, H = m["frame"]["width"], m["frame"]["height"]
        s = min((cw - 20) / W, (ch - 40) / H)
        T = lambda x, y: (ox + 10 + x * s, oy + 30 + y * s)
        dr.rectangle([T(0, 0), T(W, H)], outline="#1d2a35")
        dr.text((ox + 10, oy + 8), "%s %s  %s" % (m["code"], m["name"], ("PROBLEMS %d" % len(probs)) if probs else "ok"),
                fill="#ff5a5a" if probs else "#9fb4c2")
        N = m["nodes"]
        for n in N:
            if n.get("junction"):
                ps = []
                for a, x, y in PIECES[n["junction"]]:
                    rx, ry = rot(x, y, n["junctionYaw"])
                    ps.append((n["x"] + rx, n["y"] - ry))
                if n["junction"].startswith(("Curve", "Sbend")):
                    dr.line([T(*ps[0]), T(*ps[1])], fill="#566d80", width=max(2, int(3.4 * s)))
                    continue
                cx_, cy_ = sum(q[0] for q in ps) / len(ps), sum(q[1] for q in ps) / len(ps)
                if n["junction"] in ("Link", "Junction_T45", "Junction_WideFork", "Crossing") or n["junction"].startswith(("Bend", "Junction_Kletter")):
                    cx_, cy_ = n["x"], n["y"]
                for q in ps:
                    dr.line([T(cx_, cy_), T(*q)], fill="#566d80", width=max(2, int(3.4 * s)))
        for e in m["edges"]:
            a, b = N[e["from"]], N[e["to"]]
            col = COL.get("ret" if e.get("retracts") else e.get("state") or "", "#8aa3b6")
            if e.get("joint"):
                continue
            dr.line([T(a["x"], a["y"]), T(b["x"], b["y"])], fill=col, width=max(2, int(2.2 * s)) if e.get("shape") != "sbend" else 2)
        for n in N:
            if not n.get("junction"):
                c = "#2ee6ff" if n.get("home") and any(st["node"] == n["id"] and st["seat"] == "A" for st in m["seats"]["1v1"]) else \
                    "#7dff5a" if n.get("home") else "#ff8c2a" if n.get("relay") else "#ffd23f" if n["category"] == "strategic" else "#3f5566"
                x, y = T(n["x"], n["y"])
                dr.ellipse([x - R * s, y - R * s, x + R * s, y + R * s], fill="#1b2833", outline=c, width=2)
                lab = ("R" if n.get("relay") == "rotation" else "X") if n.get("relay") else ("T%d" % n["neutral"]["tier"] if n.get("neutral") else "")
                dr.text((x - 6, y - 5), lab, fill=c)
                if n["ring"] == 0:
                    dr.ellipse([x - (R + 1.6) * s, y - (R + 1.6) * s, x + (R + 1.6) * s, y + (R + 1.6) * s], outline="#ffd23f")
    im.save(path)
