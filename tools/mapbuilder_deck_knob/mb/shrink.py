"""DECK KNOB re-bake (map-shrink 2026-11-15, Daniele: maps too big on a phone; tiers 4 / 8 / 12 m -> 2 / 4 / 6 m).

`shrink(m, k)` takes a pack map drawn at the default tiers and returns the same map with every deck's honest length x k:
same nodes, same edges, same tiers, same junction yaws, same deck directions; only the deck part of each hop gets shorter.
Platforms (R + pier) and junction pieces keep their size, so the map shrinks less than its bridges.

How: per deck, the exits (mb.junctions.exits: a platform's rim toward the other end, or a junction's port edge) give the deck
direction u. The new centre-to-centre vector is the old one minus (1 - k) x honest x u, so the deck keeps its heading (junction
ports J02 stay aligned) and loses exactly (1 - k) of its honest length. Node positions are the linear least-squares solution of
"every centre vector = its target" (lane twins of a Crossing kept on one point, centroid kept). A tree solves exactly; a loop
whose shortenings do not close leaves a residual, reported per map (`report()`), and the rulebook / planner / test_maps4 judge
the result like any bake. k = 1 returns the map unchanged (parity).

The result is re-centred on the 160 x 80 frame and every edge carries `modules` (honest / S, so the game's test_maps4 and the
planner read the new honest length from the map itself), `deckMetres` and `centreDistance`."""
import copy
import os
import math

import numpy as np
from scipy.optimize import least_squares

from . import junctions, kit

GAP, GAP_J, CLEAR, CLEAR_J = 15.0, 8.0, 8.6, 4.4      # mb.rules G02 / G04 (platform, junction)
MARGIN = 0.3                                           # aim this far inside each rule
RELAY_HEAD = float(os.environ.get("OOZE_SHRINK_RELAY_HEAD", "3.0"))   # heading pull on relay / rotor decks (R-09: 0.4)
PAD_RIM, PAD_SEP, PAD_R, PAD_CLEAR, PAD_CLEAR_T = 8.45, 25.97, 2.0, 4.04, 3.7   # Rules.RELAY_* / rulebook G11 (pad clear of decks)
MIN_DECK = 1.0                                         # no deck under 1 m (a quarter deck): room for its piers (test_maps4)
TOL_GAP, TOL_PORT = 0.7, 2.5                           # a deck may sit this far off its honest length / a junction port
                                                       # (rulebook: G03 / J01 1.0 m, J02 3 degrees; test_maps4 2.5 m)


def _honest(e):
    """The deck's honest length as DRAWN (default tiers; ignores the DECK_K knob, which is for new drawings)."""
    if e.get("joint"):
        return 0.0
    if e.get("shape") == "sbend":
        return float(e.get("deckMetres") or float(e.get("modules", 2)) * kit.S)
    if e.get("modules") is not None:
        return float(e["modules"]) * kit.S
    return kit.MODS.get(e.get("tier"), 2) * kit.S


def shrink(m, k=None, anchor=1e-4):
    k = kit.DECK_K if k is None else float(k)
    out = copy.deepcopy(m)
    out.pop("layout", None)
    if abs(k - 1.0) < 1e-9:
        return out, {"k": 1.0, "max_res": 0.0, "rms_res": 0.0}
    N = [n["id"] for n in out["nodes"]]
    idx = {i: j for j, i in enumerate(N)}
    P0 = np.array([[float(n["x"]), float(n["y"])] for n in out["nodes"]])
    X = junctions.exits(out)
    rows, rhs = [], []
    targets = []
    for kk, e in enumerate(out["edges"]):
        A, B = X[kk][0], X[kk][1]
        d = np.array([B[0] - A[0], B[1] - A[1]])
        ln = float(np.linalg.norm(d)) or 1e-6
        u = d / ln
        h = _honest(e)
        a, b = idx[e["from"]], idx[e["to"]]
        t = (P0[b] - P0[a]) - (1.0 - k) * h * u
        targets.append((a, b, t))
        r = np.zeros(len(N))
        r[b], r[a] = 1.0, -1.0
        rows.append(r)
        rhs.append(t)
    for i, j in junctions.lane_twins(out).items():           # a Crossing's two lanes stay on one point
        if i < j:
            r = np.zeros(len(N))
            r[idx[j]], r[idx[i]] = 10.0, -10.0
            rows.append(r)
            rhs.append(np.zeros(2))
    r = np.full(len(N), 1.0 / len(N))                         # centroid kept (re-centred below anyway)
    rows.append(r * 10.0)
    rhs.append(P0.mean(axis=0) * 10.0)
    for j in range(len(N)):                                   # tiny pull to the k-scaled drawing: pins free directions only
        r = np.zeros(len(N))
        r[j] = anchor
        rows.append(r)
        rhs.append((P0.mean(axis=0) + (P0[j] - P0.mean(axis=0)) * k) * anchor)
    Amat = np.array(rows)
    Bmat = np.array(rhs)
    P, *_ = np.linalg.lstsq(Amat, Bmat, rcond=None)
    P, yaw, res = _refine(out, P, k, [_target(e, k) / k for e in out["edges"]])
    xs, ys = P[:, 0], P[:, 1]
    P[:, 0] += kit.FRAME_W / 2 - (xs.min() + xs.max()) / 2
    P[:, 1] += kit.FRAME_H / 2 - (ys.min() + ys.max()) / 2
    for n in out["nodes"]:
        n["x"], n["y"] = round(float(P[idx[n["id"]]][0]), 3), round(float(P[idx[n["id"]]][1]), 3)
        if n["id"] in yaw:
            n["junctionYaw"] = round(yaw[n["id"]], 2)
    X = junctions.exits(out)
    dev = 0.0
    for q, e in enumerate(out["edges"]):
        if e.get("joint"):
            continue
        h = _target(e, k)
        if e.get("shape") != "sbend":                     # HONEST AS DRAWN: where fixed pieces (curves) or the 15 m rule keep a
            A, B, p0, p1 = X[q][:4]                       # deck off k x its length, it keeps the length it got and says so
            got = math.dist(A, B) - p0 - p1
            dev = max(dev, abs(got - h))
            if abs(got - h) > 0.05:
                h = got
        if e.get("shape") == "sbend":
            e["deckMetres"] = round(h, 3)
        e["modules"] = round(h / kit.S, 4)
        e["deckMetres"] = round(h, 3)
        a, b = out["nodes"][idx[e["from"]]], out["nodes"][idx[e["to"]]]
        if "centreDistance" in e:
            e["centreDistance"] = round(math.hypot(a["x"] - b["x"], a["y"] - b["y"]), 2)
    out["deckK"] = k
    return out, {"k": k, "max_dev": dev, "max_res": max(res) if res else 0.0, "rms_res": float(np.sqrt(np.mean(np.square(res)))) if res else 0.0}


def _target(e, k):
    """The deck length to aim for: honest x k, but a connector never goes under MIN_DECK (EXP half / quarter decks between junction
    pieces) keeps its length - it is not a bridge, and shorter it would leave no room for its piers (test_maps4)."""
    h = _honest(e)
    return max(h * k, min(h, MIN_DECK))


def _pad(c, heads):
    """RelayView.place: the button pad's direction (map frame) in the middle of the widest gap between deck headings, and
    its distance (RIM_DIST, pushed out when the gap is under 2 x RELAY_MIN_SEP)."""
    if not heads:
        return (c[0], c[1] - PAD_RIM)
    hs = sorted(heads)
    best, mid = -1.0, 0.0
    for i in range(len(hs)):
        a0, a1 = hs[i], hs[(i + 1) % len(hs)] + (2 * math.pi if i == len(hs) - 1 else 0.0)
        if a1 - a0 > best:
            best, mid = a1 - a0, (a0 + a1) / 2
    dist = PAD_RIM
    if best < 2 * math.radians(PAD_SEP):
        dist = max(dist, PAD_CLEAR_T / max(math.sin(best / 2), 0.05))
    return (c[0] + math.cos(mid) * dist, c[1] + math.sin(mid) * dist)


def _seg_dist(p, a, b):
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    L2 = dx * dx + dy * dy or 1e-9
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - ax - t * dx, p[1] - ay - t * dy)


def symmetries(m, tol=0.6):
    """The drawing's symmetries: [(kind, {node: twin})] for kind in rot180 / mirror_x (left-right) / mirror_y (top-bottom),
    found on node points (a curve at its arc middle) about the centre of the node extent."""
    Q = {n["id"]: junctions.node_point(n) for n in m["nodes"]}
    xs, ys = [q[0] for q in Q.values()], [q[1] for q in Q.values()]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    out = []
    for kind, T in (("rot180", lambda p: (2 * cx - p[0], 2 * cy - p[1])), ("mirror_x", lambda p: (2 * cx - p[0], p[1])),
                    ("mirror_y", lambda p: (p[0], 2 * cy - p[1]))):
        tw = {}
        for i, q in Q.items():
            t = T(q)
            j = min(Q, key=lambda j: math.dist(Q[j], t))
            if math.dist(Q[j], t) > tol:
                break
            tw[i] = j
        else:
            out.append((kind, tw))
    return out


def _refine(m, P_lin, k, honest):
    """Non-linear pass from the linear solution: every deck's gap = honest x k exactly (G03 / J01), decks leave junction
    ports straight (J02, junction yaws free), unjoined nodes keep 15 m (8 m at a junction; G02), decks keep 8.6 m from
    foreign nodes (4.4 m at a junction; G04), and a light pull keeps the drawing's deck headings and the linear layout
    (symmetry, shape). Returns (positions, {junction id: yaw}, per-deck gap error in metres)."""
    N = m["nodes"]
    ids = [n["id"] for n in N]
    idx = {i: j for j, i in enumerate(ids)}
    J = [n["id"] for n in N if junctions.is_junction(n)]
    yaw0 = {i: float(N[idx[i]].get("junctionYaw", 0.0)) for i in J}
    assign = junctions.assign_ports(m)
    E = m["edges"]
    joined = {frozenset((e["from"], e["to"])) for e in E}
    twins = junctions.lane_twins(m)
    for a, b in twins.items():
        joined.add(frozenset((a, b)))
    X0 = junctions.exits(m, assign)
    head0 = [math.atan2(B[1] - A[1], B[0] - A[0]) for (A, B, *_r) in X0]
    pairs = [(i, j) for a, i in enumerate(ids) for j in ids[a + 1:] if frozenset((i, j)) not in joined]
    RELAYS = [n["id"] for n in N if n.get("relay") and n.get("plaza") is None]
    SYM = [] if os.environ.get("OOZE_SHRINK_NOSYM") else symmetries(m)
    nn = len(ids)

    def unpack(x):
        P = x[:2 * nn].reshape(nn, 2)
        y = {i: x[2 * nn + q] for q, i in enumerate(J)}
        tmp = {"nodes": [dict(n, x=float(P[idx[n["id"]]][0]), y=float(P[idx[n["id"]]][1]),
                              **({"junctionYaw": float(y[n["id"]])} if n["id"] in y else {})) for n in N], "edges": E}
        return P, y, tmp

    def resid(x, full=False, pads=False):
        P, y, tmp = unpack(x)
        X = junctions.exits(tmp, assign)
        r, gaps = [], []
        Nt = {n["id"]: n for n in tmp["nodes"]}
        for q, e in enumerate(E):
            A, B, p0, p1, pa, pb = X[q]
            if e.get("joint"):
                gap_err = math.dist(A, B)
            else:
                gap_err = math.dist(A, B) - p0 - p1 - honest[q] * k
            gaps.append(gap_err)
            r.append(0.5 * gap_err)                                   # exact if it can be,
            if not e.get("joint"):                                    # never squeezed under its piers
                r.append(100.0 * max(0.0, 0.5 - (gap_err + honest[q] * k)))
            r.append(30.0 * max(0.0, abs(gap_err) - TOL_GAP))   # inside the tolerance if it must (MIN_DECK - TOL_GAP >= 0.3 m: piers fit)
            h = math.atan2(B[1] - A[1], B[0] - A[0])
            wh = RELAY_HEAD if (e.get("state") or e.get("relay") is not None) else 0.4     # relay / rotor decks keep their heading (N13)
            r.append(wh * math.degrees(math.atan2(math.sin(h - head0[q]), math.cos(h - head0[q]))) / 10.0)
            for me, here, there, pi in ((e["from"], A, B, pa), (e["to"], B, A, pb)):
                if pi is not None:
                    pw = junctions.ports_world(Nt[me]["junction"], Nt[me]["x"], Nt[me]["y"], Nt[me]["junctionYaw"])
                    off = (junctions._ang(here, there) - pw[pi][2] + 180.0) % 360.0 - 180.0
                    r.append(0.2 * off + 30.0 * max(0.0, abs(off) - TOL_PORT) * (1 if off > 0 else -1))
            for i in ids:
                if i in (e["from"], e["to"]) or i in (twins.get(e["from"]), twins.get(e["to"])):
                    continue
                c = _seg_dist(junctions.node_point(Nt[i]), A, B)
                lim = (CLEAR_J if i in J else CLEAR) + MARGIN
                r.append(30.0 * max(0.0, lim - c))
        Q = {i: junctions.node_point(Nt[i]) for i in ids}
        for i in (RELAYS if pads else []):                    # RELAY V2 button pad: clear of platforms and decks
            c = (Nt[i]["x"], Nt[i]["y"])
            heads = []
            for q, e in enumerate(E):
                if i in (e["from"], e["to"]):
                    far = X[q][1] if e["from"] == i else X[q][0]
                    heads.append(math.atan2(far[1] - c[1], far[0] - c[0]))
            p = _pad(c, heads)
            for o in ids:
                if o != i and not junctions.is_junction(Nt[o]):
                    r.append(30.0 * max(0.0, kit.R + PAD_R + 0.3 + MARGIN - math.dist(p, (Nt[o]["x"], Nt[o]["y"]))))
            for q, e in enumerate(E):
                r.append(30.0 * max(0.0, PAD_CLEAR + MARGIN - _seg_dist(p, X[q][0], X[q][1])))
        for i, j in pairs:
            lim = (GAP_J if (i in J or j in J) else GAP) + MARGIN
            r.append(30.0 * max(0.0, lim - math.dist(Q[i], Q[j])))
        for a, b in twins.items():
            if a < b:
                r.extend(10.0 * (P[idx[a]] - P[idx[b]]))
        if SYM:                                               # keep the drawing's symmetry exactly (fair seats)
            qx = [q[0] for q in Q.values()]
            qy = [q[1] for q in Q.values()]
            cx, cy = (min(qx) + max(qx)) / 2, (min(qy) + max(qy)) / 2
            for kind, tw in SYM:
                for i, j in tw.items():
                    if i <= j:
                        a, b = Q[i], Q[j]
                        if kind == "rot180":
                            r.extend([10.0 * (a[0] + b[0] - 2 * cx), 10.0 * (a[1] + b[1] - 2 * cy)])
                        elif kind == "mirror_x":
                            r.extend([10.0 * (a[0] + b[0] - 2 * cx), 10.0 * (a[1] - b[1])])
                        else:
                            r.extend([10.0 * (a[0] - b[0]), 10.0 * (a[1] + b[1] - 2 * cy)])
        r.extend(0.02 * (P - P_lin).ravel())
        for i in J:
            r.append(0.01 * (y[i] - yaw0[i]))
        return (np.array(r), gaps) if full else np.array(r)

    x0 = np.concatenate([P_lin.ravel(), np.array([yaw0[i] for i in J])])
    meth, nfev = os.environ.get("OOZE_SHRINK_METHOD", "lm"), int(os.environ.get("OOZE_SHRINK_NFEV", "6000"))
    sol = least_squares(resid, x0, method=meth, max_nfev=nfev)          # 1. lengths, ports, spacing, symmetry
    if RELAYS and os.environ.get("OOZE_SHRINK_PADS"):                   # 2. + the relay button pads (off: it made tall maps taller)
        sol2 = least_squares(lambda x: resid(x, pads=True), sol.x, method=meth, max_nfev=nfev)
        if os.environ.get("OOZE_SHRINK_DEBUG"):
            print("SOLVER pads", sol2.status, sol2.nfev, float(sol2.cost))
        sol = sol2
    if os.environ.get("OOZE_SHRINK_DEBUG"):
        print("SOLVER", sol.status, sol.nfev, sol.message, float(sol.cost))
    P, y, _ = unpack(sol.x)
    _, gaps = resid(sol.x, full=True, pads=True)
    return P.copy(), {i: float(v) % 360.0 for i, v in y.items()}, [abs(g) for g in gaps]


def footprint(m, pad=None):
    """Platform extent in metres (centres +- R; junctions count by their centre)."""
    pad = kit.R if pad is None else pad
    xs = [float(n["x"]) for n in m["nodes"]]
    ys = [float(n["y"]) for n in m["nodes"]]
    return (max(xs) - min(xs) + 2 * pad, max(ys) - min(ys) + 2 * pad)
