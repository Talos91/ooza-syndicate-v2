"""Free-form map sketches (round 3 of the relay maps, Daniele 2026-09-28: "kept remaking maps that were all super similar ...
always only 1 type of bridge instead of a mix of all of them ... simply be flexible").

A sketch is the LEFT half of a mirrored map plus its axis (x = 80): platforms and junction pieces at rough positions, and
decks between them, each with its own tier (S / M / L) - platform to platform, platform to junction or junction to
junction, freely mixed. solve() then moves the nodes until every deck has its honest length and every deck at a junction
leaves along one of the piece's ports (a position-based relaxation, mirrored every step), keeping nodes apart and decks
clear of foreign nodes. The sketch's shape is the design; the solver only makes it honest.
Lengths and directions are measured from the port points (a curve's origin is its start port, not a centre), so the
curves (Curve_45 / Curve_90) sketch like any junction: s.j("c1", x, y, "Curve_90") with its two decks.

Keys: a left-half key k has the twin k + "'" on the right; a node sketched at x = 80 sits on the axis (its own twin).
A deck named on the left half is mirrored; a deck between k and k' (or two axis nodes) is drawn once.

    s = Sketch("R-01", "Fork Road", "note")
    s.p("h", 22, 40, home="A")          # platform (home / tier / t4 / core)
    s.j("f", 40, 40, "Junction_Fork")   # junction piece
    s.d("h", "f", "M")                  # deck
    s.relay("c", "retract", "forge")    # the axis platform c becomes a relay
    s.d("b", "c", "M", state="ret", by="c")
    m = s.build(Map)                    # solve + the lab map dict (Map = packs/junction_tests.Map)
"""
import itertools
import math
import random

from . import junctions, kit


def ang(a, b):
    """Map degrees (counter-clockwise, y up) from point a to point b."""
    return math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0])) % 360


def adiff(a, b):
    return (a - b + 180.0) % 360.0 - 180.0


def twin(k):
    return k[:-1] if k.endswith("'") else k + "'"


class Sketch:
    def __init__(self, code, name, note, mode="1v1", sym="mirror"):
        """sym: "mirror" (left / right, the axis x = 80) or "point" (180-degree turn about the centre (80, 40): the twin
        of (x, y) is (160 - x, 80 - y); a node sketched AT the centre is its own twin; curves keep their handedness)."""
        self.code, self.name, self.note, self.mode = code, name, note, mode
        self.sym = sym
        self.pts = {}        # key -> dict(kind, x, y, piece, home, tier, t4, core)
        self.decks = {}      # frozenset -> dict(a, b, tier, state, by)
        self.relays = {}     # key -> (kind, structure)
        self.skins = {}
        self.methods = ("inward", "outward")
        self.tags = {}               # size / family / finale (MAP BIBLE v2 §2, §6; rules M05)
        self.level = []              # (a, b) pairs kept at the same y (a rotor's opposite decks stay opposite - N13)
        self.hill = None             # king of the hill: the key of the T4 hill node
        self.keep_soft = True        # the polish keeps spacing, clearance and deck angles (False: lengths and ports only)
        self.rigid = []              # rigid routes (route())

    # ------------------------------------------------------------ authoring
    def p(self, k, x, y, home=None, tier=None, t4=False, core=False, ring=None):
        """ring: an explicit Last Stand ring (0 = the inward survivor; the highest = the outward survivor). When any node
        carries one, core=True means ring 0 and nodes without one sit on the highest ring; else the 2-ring core logic."""
        self.pts[k] = dict(kind="p", x=float(x), y=float(y), piece=None, home=home, tier=tier, t4=t4, core=core, ring=ring)

    def j(self, k, x, y, piece, core=False, ring=None):
        self.pts[k] = dict(kind="j", x=float(x), y=float(y), piece=piece, home=None, tier=None, t4=False, core=core, ring=ring)

    def relay(self, k, kind, structure="laser"):
        self.relays[k] = (kind, structure)

    def d(self, a, b, tier="M", state=None, by=None):
        for x, y, c in ((a, b, by), (self._tw(a), self._tw(b), self._tw(by) if by else None)):
            self.decks[frozenset((x, y))] = dict(a=x, b=y, tier=tier, tiers=tier, state=state, by=c)

    def dd(self, spec):
        """Several decks at once: "a b tiers [state by]" separated by ";" (e.g. "h a1 S; b1 c SM ret c")."""
        for part in spec.split(";"):
            w = part.split()
            if w:
                self.d(w[0], w[1], w[2], *(w[3:5] if len(w) >= 5 else []))

    def route(self, a, heading, steps, b, name=None, first=None):
        """A winding bridge from a to b, written as a path: steps are deck tier sets ("S", "SM", ...) and turns ("L90",
        "R45", ...: a Curve_90 / Curve_45 turning left / right). heading: map degrees (ccw, 0 = east) leaving a. b: a node
        key, or "mirror" (the last curve's deck crosses the axis to its own twin). The curves are laid out along the path
        (a right turn is the piece crossed backwards, so its origin is where the turn ends); the solver makes it exact.
        first: (state, by) for the first deck (a relay deck). Returns the curve keys.
        A route between two platforms (or from a platform across the axis to its twin) is RIGID in the solver: its
        curves and decks form a fixed shape (for the tiers picked in each set), so it acts as one long deck between its
        platforms and the curves are laid exactly along it afterwards."""
        assert not (b == "mirror" and self.sym == "point"), "route(..., 'mirror') needs a mirror sketch"
        name = name or (a + "_" + (b if b != "mirror" else "m"))
        rigid = self.pts[self._base(a)]["kind"] == "p" and (b == "mirror" or self.pts[self._base(b)]["kind"] == "p")
        dirv = lambda t: (math.cos(math.radians(t)), -math.sin(math.radians(t)))
        x, y = self.pts[a]["x"], self.pts[a]["y"]
        t = float(heading)
        prev, keys, lead, tier = a, [], kit.R + kit.PIER, None
        for i, st in enumerate(steps):
            if st[0] in "LR" and st[1:].isdigit():
                phi = float(st[1:])
                piece = "Curve_%d" % int(phi)
                mods = sum(kit.MODS[c] * kit.DECK_K for c in tier) / len(tier)
                ex, ey = x + dirv(t)[0] * (lead + mods * kit.S), y + dirv(t)[1] * (lead + mods * kit.S)
                sg = 1 if st[0] == "L" else -1
                cx, cy = ex + 5.09 * dirv(t + 90 * sg)[0], ey + 5.09 * dirv(t + 90 * sg)[1]
                t2 = t + sg * phi
                ox, oy = cx + 5.09 * dirv(t2 - 90 * sg)[0], cy + 5.09 * dirv(t2 - 90 * sg)[1]
                k = "%s%d" % (name, len(keys))
                self.j(k, *( (ex, ey) if sg > 0 else (ox, oy) ), piece=piece)
                self.pts[k]["virtual"] = rigid
                self.d(prev, k, tier, *(first if (first and prev == a) else ()))
                keys.append(k)
                prev, x, y, t, lead, tier = k, ox, oy, t2, 0.0, None
            else:
                tier = st
        if b == "mirror":
            self.d(prev, twin(prev), tier or "SML")
        else:
            self.d(prev, b, tier or "SML", *(first if (first and prev == a) else ()))
        if rigid and keys:
            self.rigid.append(dict(a=a, b=b, steps=list(steps), keys=keys))
        return keys

    def _base(self, k):
        return k[:-1] if k.endswith("'") else k

    def _axis(self, k):
        v = self.pts[self._base(k)]
        if self.sym == "point":
            return abs(v["x"] - 80.0) < 1e-6 and abs(v["y"] - 40.0) < 1e-6
        return abs(v["x"] - 80.0) < 1e-6

    def _rot(self, x, y):
        """The twin's position: mirror (160 - x, y), point (160 - x, 80 - y)."""
        return (160.0 - x, 80.0 - y) if self.sym == "point" else (160.0 - x, y)

    def _tw(self, k):
        return k if self._axis(k) else twin(k)

    # ------------------------------------------------------------ the full (mirrored) node set
    def _full(self):
        F = {}
        for k, v in self.pts.items():
            F[k] = dict(v)
            if not self._axis(k):
                w = dict(v)
                w["x"], w["y"] = self._rot(v["x"], v["y"])
                w["home"] = {"A": "B", "C": "D"}.get(v["home"]) if v["home"] else None
                F[twin(k)] = w
        return F

    def honest(self, F, e, tier=None):
        """Honest anchor-to-anchor length of deck e: its modules plus rim + pier at each platform end (a junction end is
        its port's edge centre, so it adds nothing)."""
        ends = sum(kit.R + kit.PIER for k in (e["a"], e["b"]) if F[k]["kind"] == "p")
        return ends + kit.deck_m(tier or e["tier"][0])

    # ------------------------------------------------------------ the solver
    def solve_best(self, restarts=24, seed=1, **kw):
        """solve() from the sketch, then from jittered sketches with random tiers inside each set; keep the most honest."""
        rng = random.Random(seed)
        best = None
        for r in range(restarts + 1):
            got = self.solve(rng=rng if r else None, **kw)
            score = max(got[0], got[1] / 3.0)
            if best is None or score < best[0]:
                best = (score, got, {k: list(v) for k, v in self.pos.items()}, dict(self.yaw), dict(self.assign),
                        {f: e["tier"] for f, e in self.decks.items()}, [list(x) for x in self.E])
            if score < 0.3:
                break
        _, got, self.pos, self.yaw, self.assign, tiers, self.E = best
        for f, t in tiers.items():
            self.decks[f]["tier"] = t
        return got

    def _chain_tokens(self, steps):
        tiers, turns = [], []
        for st in steps:
            if st[0] in "LR" and st[1:].isdigit():
                turns.append((1 if st[0] == "L" else -1, float(st[1:])))
            else:
                tiers.append(st)
        assert len(tiers) == len(turns) + 1, "%s: a route needs a deck between every two turns" % self.code
        return tiers, turns

    def _chain(self, ax, ay, theta, tiers, turns, end):
        """Lay a chain from platform centre (ax, ay) leaving at heading theta: [(origin, yaw, piece)], and the end:
        the next platform's centre ("p") or (last exit, heading, mirror-deck metres) ("mirror")."""
        dirv = lambda t: (math.cos(math.radians(t)), -math.sin(math.radians(t)))
        x, y, t, lead, out = ax, ay, theta, kit.R + kit.PIER, []
        for (sg, phi), tr in zip(turns, tiers):
            L = kit.deck_m(tr)
            ex, ey = x + dirv(t)[0] * (lead + L), y + dirv(t)[1] * (lead + L)
            cx, cy = ex + 5.09 * dirv(t + 90 * sg)[0], ey + 5.09 * dirv(t + 90 * sg)[1]
            t2 = t + sg * phi
            ox, oy = cx + 5.09 * dirv(t2 - 90 * sg)[0], cy + 5.09 * dirv(t2 - 90 * sg)[1]
            piece = "Curve_%d" % int(phi)
            if sg > 0:
                out.append(((ex, ey), t % 360, piece))
            else:
                out.append(((ox, oy), (t2 - 180) % 360, piece))
            x, y, t, lead = ox, oy, t2, 0.0
        L = kit.deck_m(tiers[-1])
        if end == "p":
            return out, (x + dirv(t)[0] * (L + kit.R + kit.PIER), y + dirv(t)[1] * (L + kit.R + kit.PIER))
        return out, ((x, y), t % 360, L)

    def _rigid_setup(self):
        """Per rigid route: every tier combination with its shape (pp: length and angle of the platform-to-platform
        offset at heading 0; mirror: the heading that makes the crossing deck square to the axis, and the start's
        distance to the axis)."""
        out = []
        for r in self.rigid:
            tiers, turns = self._chain_tokens(r["steps"])
            combos = []
            for tt in itertools.product(*[list(x) for x in tiers]):
                if r["b"] == "mirror":
                    theta = -sum(sg * phi for sg, phi in turns)
                    _, (X, h, L) = self._chain(0.0, 0.0, theta, tt, turns, "mirror")
                    combos.append(dict(tiers=tt, theta=theta, off=X[0] + L / 2))
                else:
                    _, B = self._chain(0.0, 0.0, 0.0, tt, turns, "p")
                    combos.append(dict(tiers=tt, D=math.hypot(B[0], B[1]), phi0=ang((0.0, 0.0), B)))
            out.append(dict(r, tiers=tiers, turns=turns, combos=combos, pick=0))
        return out

    def solve(self, iters=3000, polish=800, search=8, rng=None):
        F_full = self._full()
        V = {k for k in F_full if self.pts[self._base(k)].get("virtual")}
        F = {k: v for k, v in F_full.items() if k not in V}
        R = self._rigid_setup()
        pos = {k: [n["x"], n["y"]] for k, n in F.items()}
        if rng:                                                 # a restart: jitter the sketch (the mirror restores symmetry)
            for k in pos:
                pos[k][0] += rng.uniform(-4, 4)
                pos[k][1] += rng.uniform(-4, 4)
        D_all = list(self.decks.values())
        D = [e for e in D_all if e["a"] not in V and e["b"] not in V]
        pick = {}
        for e in D:                                             # a tier set ("SM", "ML", "SML"): start from its middle
            e["tier"] = "".join(t for t in "SML" if t in e["tiers"])
            if rng:                                             # (a restart: a random tier, the same on both halves)
                f = frozenset((self._tw(e["a"]), self._tw(e["b"])))
                t = pick.get(f) or rng.choice(e["tiers"])
                pick[frozenset((e["a"], e["b"]))] = t
                e["L"] = self.honest(F, e, t)
            else:
                e["L"] = sum(self.honest(F, e, t) for t in e["tiers"]) / len(e["tiers"])
        E = [[e["a"], e["b"], e["L"]] for e in D]
        for a, b, _ in E:
            assert a in F and b in F, "%s: deck %s-%s names a missing node" % (self.code, a, b)
        for k, n in F.items():
            if n["kind"] == "j":
                nd = sum(1 for a, b, _ in E if k in (a, b))
                assert nd <= len(junctions.all_pieces()[n["piece"]]), "%s: junction %s (%s) has %d decks" % (self.code, k, n["piece"], nd)
                assert not (junctions.is_curve(n["piece"]) and self._axis(k)), "%s: curve %s on the axis" % (self.code, k)
        inc = {k: [] for k in F}
        for i, (a, b, _) in enumerate(E):
            inc[a].append((b, i))
            inc[b].append((a, i))
        pdata = {k: [(p["angle_deg"], p["edge_centre"][0], p["edge_centre"][1]) for p in junctions.all_pieces()[n["piece"]]]
                 for k, n in F.items() if n["kind"] == "j"}
        yaw = {k: 0.0 for k in pdata}
        assign = {}                                             # junction -> port index per incident deck (inc order)
        keys = list(F)

        def anchor(k, i):
            """Where deck i meets node k: a platform's centre, or the junction port's edge centre."""
            if k not in pdata:
                return pos[k]
            p = assign[k][[j for _, j in inc[k]].index(i)]
            a, ex, ey = pdata[k][p]
            c, s = math.cos(math.radians(yaw[k])), math.sin(math.radians(yaw[k]))
            return (pos[k][0] + ex * c - ey * s, pos[k][1] - (ex * s + ey * c))

        def port_dir(k, i):
            p = assign[k][[j for _, j in inc[k]].index(i)]
            return pdata[k][p][0] + yaw[k]

        def far(k, o, i):
            """The other end's anchor of deck i seen from k (its centre while o's ports are not assigned yet)."""
            return anchor(o, i) if (o not in pdata or o in assign) else pos[o]

        def fit(k):
            """Port per incident deck + yaw for junction k: every permutation, yaw refined from the port points."""
            nb = inc[k]
            best = None
            for perm in itertools.permutations(range(len(pdata[k])), len(nb)):
                y0 = None
                for rnd in range(3):
                    diffs = []
                    for (o, i), p in zip(nb, perm):
                        a, ex, ey = pdata[k][p]
                        if y0 is None:
                            src = pos[k]
                        else:
                            c, s = math.cos(math.radians(y0)), math.sin(math.radians(y0))
                            src = (pos[k][0] + ex * c - ey * s, pos[k][1] - (ex * s + ey * c))
                        diffs.append(math.radians(ang(src, far(k, o, i)) - a))
                    y0 = math.degrees(math.atan2(sum(math.sin(d) for d in diffs), sum(math.cos(d) for d in diffs))) % 360
                cost = sum(adiff(math.degrees(d) % 360, y0) ** 2 for d in diffs)
                if best is None or cost < best[0]:
                    best = (cost, y0, list(perm))
            return best[1], best[2]

        mirror_deck = {}
        for i, (a, b, _) in enumerate(E):
            for j, (c, d, _) in enumerate(E):
                if {c, d} == {self._tw(a), self._tw(b)}:
                    mirror_deck[i] = j
        curves = [k for k in pdata if junctions.is_curve(F[k]["piece"]) and not k.endswith("'")]

        def refit():
            for k in pdata:
                if not (k.endswith("'") and k[:-1] in curves):
                    yaw[k], assign[k] = fit(k)
            for k in curves:                                    # a mirrored curve starts at the mirror of the end port
                t = twin(k)
                if self.sym == "point":                          # a turned curve: same port, yaw + 180
                    yaw[t] = (yaw[k] + 180.0) % 360
                    assign[t] = [assign[k][[j for _, j in inc[k]].index(mirror_deck[i])] for _, i in inc[t]]
                else:
                    yaw[t] = (-(pdata[k][1][0] + yaw[k])) % 360
                    assign[t] = [1 - assign[k][[j for _, j in inc[k]].index(mirror_deck[i])] for _, i in inc[t]]

        def dist_of(i):
            a, b, _ = E[i]
            return math.dist(anchor(a, i), anchor(b, i))

        def retier():
            for i, (e, row) in enumerate(zip(D, E)):
                d = dist_of(i)
                t = min(e["tiers"], key=lambda t: abs(self.honest(F, e, t) - d))
                e["tier"], row[2] = t, self.honest(F, e, t)
            for r in R:
                rigid_pick(r)

        def refit_curves():
            for k in curves:
                yaw[k], assign[k] = fit(k)
                t = twin(k)
                if self.sym == "point":                          # a turned curve: same port, yaw + 180
                    yaw[t] = (yaw[k] + 180.0) % 360
                    assign[t] = [assign[k][[j for _, j in inc[k]].index(mirror_deck[i])] for _, i in inc[t]]
                else:
                    yaw[t] = (-(pdata[k][1][0] + yaw[k])) % 360
                    assign[t] = [1 - assign[k][[j for _, j in inc[k]].index(mirror_deck[i])] for _, i in inc[t]]

        joined = {frozenset((a, b)) for a, b, _ in E}
        for r in R:
            joined.add(frozenset((r["a"], r["b"])))
            if r["b"] != "mirror":
                joined.add(frozenset((self._tw(r["a"]), self._tw(r["b"]))))

        def rigid_pick(r, first=False):
            a = r["a"]
            if r["b"] == "mirror":
                want = 80.0 - pos[a][0]
                r["pick"] = min(range(len(r["combos"])), key=lambda i: abs(r["combos"][i]["off"] - want))
            else:
                d = math.dist(pos[a], pos[r["b"]])
                r["pick"] = min(range(len(r["combos"])), key=lambda i: abs(r["combos"][i]["D"] - d))

        def rigid_step():
            for r in R:
                c = r["combos"][r["pick"]]
                if r["b"] == "mirror":
                    for a, sgn in ((r["a"], 1), (self._tw(r["a"]), -1)):
                        target = 80.0 - sgn * c["off"]
                        pos[a][0] += (target - pos[a][0]) * 0.25
                    continue
                for a, b in ((r["a"], r["b"]), (self._tw(r["a"]), self._tw(r["b"]))):
                    pa, pb = pos[a], pos[b]
                    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
                    d = math.hypot(dx, dy) or 1e-6
                    k = (d - c["D"]) / d * 0.25
                    pa[0] += dx * k
                    pa[1] += dy * k
                    pb[0] -= dx * k
                    pb[1] -= dy * k

        for r in R:
            if rng:
                r["pick"] = rng.randrange(len(r["combos"]))
            else:
                rigid_pick(r)

        def relax(n, soft):
            for it in range(n):
                if it % 10 == 0 or not assign:
                    refit()
                elif curves:
                    refit_curves()
                self._step(soft, pos, F, E, inc, pdata, anchor, port_dir, keys, yaw, curves, joined)
                if R:
                    rigid_step()

        def worst():
            refit()
            r = [abs(dist_of(i) - L) for i, (a, b, L) in enumerate(E)]
            for k in pdata:
                for o, i in inc[k]:
                    r[i] = max(r[i], abs(adiff(ang(anchor(k, i), anchor(o, i)), port_dir(k, i))) / 3.0)   # 3 degrees ~ 1 m
            return r

        def snap():
            return ({k: list(v) for k, v in pos.items()}, [row[2] for row in E], [x["tier"] for x in D])

        def restore(st):
            for k, v in st[0].items():
                pos[k][:] = v
            for row, L in zip(E, st[1]):
                row[2] = L
            for x, t0 in zip(D, st[2]):
                x["tier"] = t0

        refit()
        relax(iters // 2, True)
        if not rng:
            retier()
        relax(iters // 2, True)
        retier()
        relax(polish, self.keep_soft)
        r = worst()
        tries = 0
        while max(r) > 0.6 and tries < search:                  # a tier set that can't close: try the worst decks' others
            tries += 1
            best = (max(r), None)
            for i in sorted(range(len(E)), key=lambda i: -r[i])[:4]:
                e = D[i]
                for t in e["tiers"]:
                    if t == e["tier"]:
                        continue
                    keep = snap()
                    tw = self.decks.get(frozenset((self._tw(e["a"]), self._tw(e["b"]))))
                    for x in (e, tw):
                        if x is not None:
                            j = D.index(x)
                            x["tier"], E[j][2] = t, self.honest(F, x, t)
                    relax(polish, self.keep_soft)
                    got = max(worst())
                    if got < best[0] - 0.05:
                        best = (got, snap())
                    restore(keep)
            if best[1] is None:
                break
            restore(best[1])
            r = worst()
        refit()
        if R:                                                   # lay every rigid chain's curves along it
            pos, F, E, inc, pdata, yaw, assign = self._expand(R, pos, yaw, assign, F_full, D_all)
        ys = [p[1] for p in pos.values()]
        dy = 40.0 - (min(ys) + max(ys)) / 2                     # centre the map on the frame
        for p in pos.values():
            p[1] += dy
        self.pos, self.F, self.E = pos, F, E
        self.yaw, self.assign = dict(yaw), {k: list(v) for k, v in assign.items()}
        self._inc, self._pdata = inc, pdata
        return self.residuals()

    def _expand(self, R, pos, yaw, assign, F_full, D_all):
        """After the reduced solve: place each rigid chain's curves (left half, then mirrored), give its decks their
        tiers, and rebuild the full deck / port structures."""
        pos = {k: list(v) for k, v in pos.items()}
        yaw = dict(yaw)
        port_of = {}                                             # (curve, deck) -> port index, from the chain's order
        for r in R:
            c = r["combos"][r["pick"]]
            a = r["a"]
            if r["b"] == "mirror":
                theta = c["theta"]
            else:
                theta = ang(pos[a], pos[r["b"]]) - c["phi0"]
            curves, _ = self._chain(pos[a][0], pos[a][1], theta, c["tiers"], r["turns"], "p" if r["b"] != "mirror" else "mirror")
            chain = [a] + r["keys"] + ([twin(r["keys"][-1])] if r["b"] == "mirror" else [r["b"]])
            for j, (k, (o, y, piece)) in enumerate(zip(r["keys"], curves)):
                pos[k] = [o[0], o[1]]
                yaw[k] = y
                pd = junctions.all_pieces()[piece][1]
                a1 = pd["angle_deg"]
                ex, ey = pd["edge_centre"][0], pd["edge_centre"][1]
                cc, sn = math.cos(math.radians(y)), math.sin(math.radians(y))
                end = (o[0] + ex * cc - ey * sn, o[1] - (ex * sn + ey * cc))
                if self.sym == "point":                          # turned: the twin starts at the turned start port
                    pos[twin(k)] = [160.0 - o[0], 80.0 - o[1]]
                    yaw[twin(k)] = (y + 180.0) % 360
                else:
                    pos[twin(k)] = [160.0 - end[0], end[1]]      # the twin starts at the mirror of the end port
                    yaw[twin(k)] = (-(a1 + y)) % 360
                left = r["turns"][j][0] > 0
                pin, pout = (0, 1) if left else (1, 0)           # a right turn is the piece crossed backwards
                port_of[(k, frozenset((k, chain[j])))] = pin
                port_of[(k, frozenset((k, chain[j + 2])))] = pout
                tk = twin(k)
                flip = 0 if self.sym == "point" else 1
                port_of[(tk, frozenset((tk, self._tw(chain[j]))))] = abs(flip - pin)
                port_of[(tk, frozenset((tk, self._tw(chain[j + 2]) if chain[j + 2] != twin(k) else k)))] = abs(flip - pout)
            for x, y2, t in zip(chain, chain[1:], c["tiers"]):   # the chain's decks take the picked tiers
                for f in (frozenset((x, y2)), frozenset((self._tw(x), self._tw(y2)))):
                    if f in self.decks:
                        self.decks[f]["tier"] = t
        F = F_full
        E = []
        for e in D_all:
            e["L"] = self.honest(F, e, e["tier"])
            E.append([e["a"], e["b"], e["L"]])
        inc = {k: [] for k in F}
        for i, (a, b, _) in enumerate(E):
            inc[a].append((b, i))
            inc[b].append((a, i))
        pdata = {k: [(p["angle_deg"], p["edge_centre"][0], p["edge_centre"][1]) for p in junctions.all_pieces()[n["piece"]]]
                 for k, n in F.items() if n["kind"] == "j"}
        assign = dict(assign)
        for k in pdata:
            if (k, frozenset((k, inc[k][0][0]))) in port_of:
                assign[k] = [port_of[(k, frozenset((k, o)))] for o, _ in inc[k]]
        return pos, F, E, inc, pdata, yaw, assign

    def anchor_of(self, k, i):
        """After solve(): where deck i (index in self.E) meets node k."""
        if k not in self._pdata:
            return tuple(self.pos[k])
        p = self.assign[k][[j for _, j in self._inc[k]].index(i)]
        a, ex, ey = self._pdata[k][p]
        c, s = math.cos(math.radians(self.yaw[k])), math.sin(math.radians(self.yaw[k]))
        return (self.pos[k][0] + ex * c - ey * s, self.pos[k][1] - (ex * s + ey * c))

    def _step(self, soft, pos, F, E, inc, pdata, anchor, port_dir, keys, yaw, curves, joined):
        """One relaxation step: honest lengths, ports, (soft:) deck angles at platforms, spacing, clearance; then the mirror."""
        def spot(k):
            """Where a node counts for spacing / clearance: a curve's arc middle, else its centre."""
            if F[k]["kind"] != "j" or not junctions.is_curve(F[k]["piece"]):
                return pos[k]
            return junctions.node_point({"x": pos[k][0], "y": pos[k][1], "junction": F[k]["piece"], "junctionYaw": yaw[k]})
        for i, (a, b, L) in enumerate(E):                       # honest lengths (anchor to anchor)
            pa, pb = anchor(a, i), anchor(b, i)
            dx, dy = pb[0] - pa[0], pb[1] - pa[1]
            d = math.hypot(dx, dy) or 1e-6
            c = (d - L) / d * 0.25
            pos[a][0] += dx * c
            pos[a][1] += dy * c
            pos[b][0] -= dx * c
            pos[b][1] -= dy * c
        for k in pdata:                                         # decks along the ports
            for o, i in inc[k]:
                L = E[i][2]
                pk = anchor(k, i)
                t = math.radians(port_dir(k, i))
                tx, ty = pk[0] + L * math.cos(t), pk[1] - L * math.sin(t)
                po = anchor(o, i)
                dx, dy = tx - po[0], ty - po[1]
                pos[o][0] += dx * 0.25
                pos[o][1] += dy * 0.25
                pos[k][0] -= dx * 0.25
                pos[k][1] -= dy * 0.25
        for a, b in self.level:                                 # level pairs (rigid rotors)
            if a in pos and b in pos:
                mid = (pos[a][1] + pos[b][1]) / 2
                pos[a][1], pos[b][1] = mid, mid
        if soft:
            for k in keys:                                      # decks leave a platform at least 40 degrees apart
                if F[k]["kind"] != "p" or len(inc[k]) < 2:
                    continue
                nb = sorted(inc[k], key=lambda oi: ang(pos[k], anchor(oi[0], oi[1])))
                for j in range(len(nb)):
                    (o1, i1), (o2, i2) = nb[j], nb[(j + 1) % len(nb)]
                    gap = (ang(pos[k], anchor(o2, i2)) - ang(pos[k], anchor(o1, i1))) % 360
                    if gap < 40.0:
                        push = math.radians((40.0 - gap) / 4)
                        for o, sg in ((o1, -1), (o2, 1)):
                            vx, vy = pos[o][0] - pos[k][0], -(pos[o][1] - pos[k][1])     # y up
                            c, sn = math.cos(sg * push), math.sin(sg * push)
                            rx, ry = vx * c - vy * sn, vx * sn + vy * c
                            pos[o][0], pos[o][1] = pos[k][0] + rx, pos[k][1] - ry
            for j, a in enumerate(keys):                        # spacing
                for b in keys[j + 1:]:
                    if frozenset((a, b)) in joined and "j" in (F[a]["kind"], F[b]["kind"]):
                        continue                                # the deck's honest length sets that gap
                    want = 17.0 if F[a]["kind"] == F[b]["kind"] == "p" else 9.5
                    qa, qb = spot(a), spot(b)
                    dx, dy = qb[0] - qa[0], qb[1] - qa[1]
                    d = math.hypot(dx, dy) or 1e-6
                    if d < want:
                        c = (want - d) / d * 0.25
                        pos[a][0] -= dx * c
                        pos[a][1] -= dy * c
                        pos[b][0] += dx * c
                        pos[b][1] += dy * c
            for i, (a, b, _) in enumerate(E):                   # decks clear of foreign nodes
                pa, pb = anchor(a, i), anchor(b, i)
                for k in keys:
                    if k in (a, b):
                        continue
                    want = 9.6 if F[k]["kind"] == "p" else 5.2
                    sk = spot(k)
                    q, t = _closest(sk, pa, pb)
                    dx, dy = sk[0] - q[0], sk[1] - q[1]
                    d = math.hypot(dx, dy) or 1e-6
                    if d < want and 0.02 < t < 0.98:
                        c = (want - d) / d * 0.06
                        pos[k][0] += dx * c
                        pos[k][1] += dy * c
                        for e in (a, b):
                            pos[e][0] -= dx * c / 2
                            pos[e][1] -= dy * c / 2
            ys = [pos[k][1] for k in keys]                      # inside the 202 x 83 m maximum (platform rims included)
            yc = (min(ys) + max(ys)) / 2
            for k in keys:
                lim = (41.5 - kit.R - 0.8) if F[k]["kind"] == "p" else 38.0
                off = pos[k][1] - yc
                if abs(off) > lim:
                    pos[k][1] -= (abs(off) - lim) * 0.5 * (1 if off > 0 else -1)
                if abs(pos[k][0] - 80.0) > 101.0 - kit.R - 0.8:
                    pos[k][0] -= (abs(pos[k][0] - 80.0) - (101.0 - kit.R - 0.8)) * 0.5 * (1 if pos[k][0] > 80 else -1)
        if self.sym == "group":                                 # mb/group_sketch.py: n-fold rotation (+ mirrors)
            self._symmetrize(pos)
            return

        def end_port(k):
            a, ex, ey = pdata[k][1]
            c, sn = math.cos(math.radians(yaw[k])), math.sin(math.radians(yaw[k]))
            return (pos[k][0] + ex * c - ey * sn, pos[k][1] - (ex * sn + ey * c))

        if self.sym == "point":                                 # turn 180 degrees about (80, 40)
            for k in keys:
                if self._axis(k):
                    pos[k][0], pos[k][1] = 80.0, 40.0
                elif not k.endswith("'"):
                    t = twin(k)
                    x = (pos[k][0] + 160.0 - pos[t][0]) / 2
                    y = (pos[k][1] + 80.0 - pos[t][1]) / 2
                    pos[k][0], pos[k][1] = x, y
                    pos[t][0], pos[t][1] = 160.0 - x, 80.0 - y
            return
        for k in curves:                                        # mirror a curve: start port <-> mirrored end port
            t = twin(k)
            back = end_port(t)                                  # where the twin says k's origin should be
            pos[k][0] = (pos[k][0] + 160.0 - back[0]) / 2
            pos[k][1] = (pos[k][1] + back[1]) / 2
            e = end_port(k)
            pos[t][0], pos[t][1] = 160.0 - e[0], e[1]
        for k in keys:                                          # mirror
            if k in curves or (k.endswith("'") and k[:-1] in curves):
                continue
            if self._axis(k):
                pos[k][0] = 80.0
            elif not k.endswith("'"):
                t = twin(k)
                x = (pos[k][0] + 160.0 - pos[t][0]) / 2
                y = (pos[k][1] + pos[t][1]) / 2
                pos[k][0], pos[k][1] = x, y
                pos[t][0], pos[t][1] = 160.0 - x, y

    def residuals(self):
        worst_len = max(abs(math.dist(self.anchor_of(a, i), self.anchor_of(b, i)) - L) for i, (a, b, L) in enumerate(self.E))
        worst_port = 0.0
        for k in self._pdata:
            for o, i in self._inc[k]:
                p = self.assign[k][[j for _, j in self._inc[k]].index(i)]
                worst_port = max(worst_port, abs(adiff(ang(self.anchor_of(k, i), self.anchor_of(o, i)),
                                                       self._pdata[k][p][0] + self.yaw[k])))
        return worst_len, worst_port

    # ------------------------------------------------------------ extra geometry checks (beyond the rulebook)
    def extra_findings(self):
        out = []
        E = self.E
        seg = [(self.anchor_of(a, i), self.anchor_of(b, i)) for i, (a, b, _) in enumerate(E)]
        for i, (a, b, _) in enumerate(E):
            for j in range(i + 1, len(E)):
                c, d, _ = E[j]
                if len({a, b, c, d}) == 4 and _cross(seg[i][0], seg[i][1], seg[j][0], seg[j][1]):
                    out.append("decks %s-%s and %s-%s cross" % (a, b, c, d))
        for k, n in self.F.items():
            if n["kind"] != "p":
                continue
            angs = sorted(ang(self.pos[k], seg[i][1] if a == k else seg[i][0]) for i, (a, b, _) in enumerate(E) if k in (a, b))
            for i in range(len(angs)):
                gap = (angs[(i + 1) % len(angs)] - angs[i]) % 360 if len(angs) > 1 else 360
                if gap < 37.0:
                    out.append("platform %s: two decks leave %.0f degrees apart" % (k, gap))
        return out

    # ------------------------------------------------------------ Last Stand rings
    def _rings(self, F):
        """The inner ring (0) and the methods, the way the game collapses (Sim._plan_waves drops whatever a wave cuts off
        over FIXED decks): the sketched core grows along the shortest fixed-deck paths until it is one piece (twins
        too, so it stays mirrored); outward is kept only while the outer ring also holds together over fixed decks."""
        fixed = {k: set() for k in F}
        per = {}                                             # hubs (rules.hub_decks): 2+ decks in every state
        for e in self.decks.values():
            if e["state"] and e["state"][0] in "rs":
                per.setdefault(e["by"], {}).setdefault(e["state"], 0)
                per[e["by"]][e["state"]] += 1
        hub = {k for k, by in per.items() if len(by) >= 2 and min(by.values()) >= 2}
        for e in self.decks.values():
            if not e["state"] or (e["state"][0] in "rs" and e["by"] in hub):
                fixed[e["a"]].add(e["b"])
                fixed[e["b"]].add(e["a"])
        core = {k for k, n in F.items() if n["core"]}

        def parts(nodes):
            seen, out = set(), []
            for k in nodes:
                if k in seen:
                    continue
                comp, stack = set(), [k]
                seen.add(k)
                while stack:
                    v = stack.pop()
                    comp.add(v)
                    for w in fixed[v]:
                        if w in nodes and w not in seen:
                            seen.add(w)
                            stack.append(w)
                out.append(comp)
            return out

        for _ in range(len(F)):
            comps = parts(core)
            if len(comps) <= 1:
                break
            main = max(comps, key=len)
            prev, front, hit = {k: None for k in main}, list(main), None      # BFS over fixed decks to another part
            while front and hit is None:
                nxt = []
                for v in front:
                    for w in fixed[v]:
                        if w not in prev:
                            prev[w] = v
                            if w in core:
                                hit = w
                                break
                            nxt.append(w)
                    if hit:
                        break
                front = nxt
            if hit is None:
                break
            v = prev[hit]
            while v is not None and v not in main:
                core.add(v)
                core.add(self._tw(v))
                v = prev[v]
        methods = [m for m in self.methods]
        rim = set(F) - core
        if "outward" in methods and (len(parts(rim)) > 1 or not rim):
            methods.remove("outward")
        if "inward" in methods and len(parts(core)) > 1:
            print("WARN %s: the inner ring stays split over fixed decks" % self.code)
        return core, tuple(methods)

    # ------------------------------------------------------------ to the lab map format
    def build(self, Map, iters=3000):
        """Map: the lab map writer (packs/junction_tests.Map)."""
        wl, wp = self.solve_best(iters=iters)
        self.worst = (wl, wp)
        F, P = self.F, self.pos
        relay_at = {}
        for k, v in self.relays.items():
            relay_at[k] = v
            relay_at[self._tw(k)] = v
        for e in self.decks.values():
            if e["state"] == "m1":
                relay_at.setdefault(e["by"], ("remote", "laser"))
        adj = {k: [] for k in F}
        for e in self.decks.values():
            adj[e["a"]].append(e["b"])
            adj[e["b"]].append(e["a"])
        homes = [k for k, n in F.items() if n["home"]]
        hop = {h: 0 for h in homes}                              # platform hops from the nearest home
        front = list(homes)
        while front:
            nxt = []
            for v in front:
                for w in adj[v]:
                    if w not in hop:
                        hop[w] = hop[v] + (0 if F[w]["kind"] == "j" else 1)
                        nxt.append(w)
            front = nxt
        explicit = any(n.get("ring") is not None for n in F.values())
        if explicit:
            top = max(n["ring"] for n in F.values() if n.get("ring") is not None)
            top = max(top, 1)
            ring_of = {k: (n["ring"] if n.get("ring") is not None else 0 if n["core"] else top) for k, n in F.items()}
            methods = tuple(self.methods)
        else:
            core, methods = self._rings(F)
            ring_of = {k: (0 if k in core else 1) for k in F}
        self.methods = methods
        ring_ids = sorted(set(ring_of.values()))
        g = Map(self.code, self.name, self.note)
        for k in sorted(F, key=lambda k: (round(P[k][1], 1), round(P[k][0], 1))):
            n = F[k]
            ring = ring_of[k]
            x, y = P[k]
            if n["kind"] == "j":
                g.node(k, x, y, junction=n["piece"], yaw=round(self.yaw[k], 2), ring=ring)
            elif n["home"]:
                g.node(k, x, y, home=True, ring=ring)
            elif k in relay_at:
                kind, st = relay_at[k]
                g.node(k, x, y, relay=kind, structure=st, tier=2, ring=ring)
            elif n["t4"]:
                g.node(k, x, y, tier=4, strategic=True, ring=ring)
            else:
                h = hop.get(k, 9)
                g.node(k, x, y, tier=n["tier"] or (1 if h <= 1 else 2 if h <= 3 else 3), ring=ring)
        for e in self.decks.values():
            st = e["state"]
            g.deck(e["a"], e["b"], retract_by=e["by"] if st == "ret" else None)
            d = g.m["edges"][-1]
            d["tier"], d["seconds"], d["deckMetres"] = e["tier"], kit.SECONDS[e["tier"]], kit.deck_m(e["tier"])
            d.pop("nominal", None)                               # (centre distances mean little at a curve)
            if st in ("r1", "r2", "s1", "s2", "m1"):
                d["state"], d["relay"] = st, g.at[e["by"]]["id"]
        seats = sorted(({"seat": F[k]["home"], "node": g.at[k]["id"], "team": 0 if F[k]["home"] in "AC" else 1} for k in homes),
                       key=lambda s: s["seat"])
        g.m["modes"], g.m["playersLabel"], g.m["seats"] = [self.mode], self.mode, {self.mode: seats}
        orders = {"inward": ring_ids[::-1], "outward": list(ring_ids), "chaos": list(ring_ids)}
        g.m["rings"] = {"count": len(ring_ids), "boundaries": [], "aspect": 2.0, "shape": "ellipse"}
        g.m["lastStand"] = {"methods": list(self.methods), "orders": {m: orders[m] for m in self.methods}}
        if self.tags:
            g.m["tags"] = dict(self.tags)
        if self.hill:
            g.m["hill"] = g.at[self.hill]["id"]
        if sum(1 for n in g.m["nodes"] if n.get("relay")) > 3:
            g.m["relayHeavy"] = True
        self.id2key = {n["id"]: k for k, n in g.at.items()}
        g.m["family"] = "relay test r3"
        g.m["labVariant"] = {"junctions": True, "skins": self.skins}
        return g.m


def _closest(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy or 1e-9
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return (a[0] + t * dx, a[1] + t * dy), t


def _cross(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    return (ccw(p1, p3, p4) > 0) != (ccw(p2, p3, p4) > 0) and (ccw(p1, p2, p3) > 0) != (ccw(p1, p2, p4) > 0)
