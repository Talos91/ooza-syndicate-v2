"""R-13 Gearbox (round R wave 2, 2026-11-05): two hexagon gears that share their meshing point, the gearbox stone C.

Each gear is six platforms round a three-spoke hub (pointy toward its home). The two gears share their inner point C (a
figure-eight), so C is where they mesh: a ROTOR on its two diagonals (r1 top-left / bottom-right, r2 bottom-left /
top-right). The four outer rim decks of each gear are speed lanes driven by ONE speed relay, the drive X (the crown stone on
the axis above the gears; decks need not touch their relay): left gear clockwise, right gear anticlockwise (the mirror
copy keeps each deck's from / to order, so the gears mesh). Firing X reverses both gears. Plain arches over the top (via X)
and under the bottom (via Y) are the long dry ways round. Design notes (why not lifts at the mesh, why X sits on the crown)
in the R-13 report; check loop in BRIEF-COMMON."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from r_maps import *  # noqa: E402,F401,F403
from r_maps import RMap, SPEED, ROTOR, set_edge  # noqa: E402

CURVES = ("Curve_30", "Curve_45", "Curve_W45", "Curve_60")
XY = 26.0                                              # the crowns X / Y: 26 m above / below C (span 64 m)


def build():
    m = RMap("R-13", "Gearbox", "M", "open",
             "M, 17 platforms, mirrored both ways. Two gears mesh in the middle and share one stone, the gearbox (C). "
             "Each gear's rim is a speed lane that turns: the left gear clockwise, the right one anticlockwise (on both, the "
             "top runs toward the middle and the bottom away from it). Two drives turn both gears: the crown "
             "stones over and under the gearbox (X and Y) are linked speed relays - fire EITHER and both gears turn the "
             "other way (hold one drive and you can flip the gears even if the other side holds the other). The gearbox is a ROTOR on its two "
             "diagonals: one joins top-left to bottom-right, the other bottom-left to top-right; with the gears turning "
             "as they start, the first is the left player's fast lane through the middle and the second the right player's "
             "(firing the drive swaps that). The long dry ways round are the arches over the top (by the drive) and under "
             "the bottom. Each home has three ways onto its gear: the straight road to its point and a curved road to its "
             "top and bottom corners. Finale: the figure-eight round the gearbox - both gears' inner corners and hubs.")
    s, th, cy = kit.CENTRE["S"], 130.0, 40.0                      # rim deck 1 module; the gearbox diagonals leave C at 130 degrees
    m.P("C", 80.0, cy, tier=3, core=True, **ROTOR)    # the gearbox: shared by both rims, a rotor on its two diagonals
    ux, uy = math.cos(math.radians(th)), math.sin(math.radians(th))
    gui = (80.0 + s * ux, cy - s * uy)
    m.P("Gui", *gui, tier=2, core=True)               # upper-inner rim point
    m.P("Gli", gui[0], 2 * cy - gui[1], tier=2, core=True)
    m.P("Guo", gui[0] - s, gui[1], tier=1)            # the flat top side
    m.P("Glo", gui[0] - s, 2 * cy - gui[1], tier=1)
    m.P("Go", gui[0] - s + s * ux, cy, tier=1)        # the outer point, facing home
    m.P("Hub", m.node("Go")["x"] + s, cy, tier=2, core=True)   # three spokes: Go, Gui, Gli
    m.P("HA", m.node("Go")["x"] - s, cy, role="homeA")
    m.P("X", 80.0, cy - XY, tier=3, **SPEED)          # the drive (top crown), speed relay of both rims
    m.node_extra["X"] = {"conveyor": {"dir": "AB"}}
    m.P("Y", 80.0, cy + XY, tier=3, **SPEED)          # the bottom crown: a second drive, LINKED to X (Daniele 2026-11-05:
    m.node_extra["Y"] = {"conveyor": {"dir": "AB", "link": "X"}}   # "another speed relay in the bottom part, mirror of the
                                                      # upper, controlling the SAME speed / slow") - firing either turns both
    for a, b in (("Go", "Guo"), ("Guo", "Gui"), ("Gli", "Glo"), ("Glo", "Go")):   # clockwise: flow from -> to
        m.join(a, b, 1)
        m.hz(proto="conveyor", prelay="X")
    m.join("C", "Gui", 1, state="r1", relay="C")      # r1: top-left / bottom-right; r2 (mirror): bottom-left / top-right
    m.join("C", "Gli", 1, state="r2", relay="C")
    for g in ("Go", "Gui", "Gli"):
        m.join("Hub", g, 1)
    m.join("HA", "Go", 1)
    m.fit("HA", "Guo", pieces=CURVES, angles=range(0, 61, 5), tol=0.6, name="cU")
    m.fit("HA", "Glo", pieces=CURVES, angles=range(0, -61, -5), tol=0.6, name="cD")
    m.fit("Guo", "X", pieces=CURVES, angles=range(10, 61, 5), tol=0.6, name="aU")
    m.fit("Glo", "Y", pieces=CURVES, angles=range(-10, -61, -5), tol=0.6, name="aD")
    m.where("C", "X", "Gui", "Guo", "Go", "Hub", "HA", "cU", "aU")
    m.sym("mirror")
    set_edge(m, "C", "Gui'", state="r2")              # the mirror copies swap states: the diagonals, not the V's
    set_edge(m, "C", "Gli'", state="r1")
    m.waivers = {}                                            # R07 waiver dropped with the rule (Daniele 2026-11-07, Desk dec-drop-r07)
    return m


if __name__ == "__main__":
    import r_maps as R
    m = build()
    p, probs, js = m.write("gearbox")
    print(m.stats(js))
    print(probs)
    h, w, so = R.rulebook(js)
    print("HARD", [(x["rule"], x["msg"]) for x in h])
    print("WAIVED", [x["rule"] for x in w])
    print("SOFT", [(x["rule"], x["msg"]) for x in so])
    idx = m._order()
    print(" ".join("%d=%s" % (idx[i], n.get("name")) for i, n in sorted(enumerate(m.nodes), key=lambda t: idx[t[0]])))
    if "--png" in sys.argv:
        from exp_chain import preview
        preview([(m, js, probs)], os.path.join(os.environ.get("R13PNG", "."), "r13.png"))
