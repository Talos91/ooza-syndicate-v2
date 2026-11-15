"""R-14 Catapult Bay (round R, Daniele 2026-11-06: "we have the launcher map on proto?" ... "Yes, design one").

S, mirrored left / right and top / bottom. A wide empty bay in the middle: no bridge across it but a timed 1-bridge ferry
between the two banks' middle platforms. Each middle platform is a LAUNCHER pad whose aim sweeps the enemy bank (top,
middle, bottom): arm it, walk a line onto the pad and it lands over the bay on whatever the aim holds. The dry ways round
are the arcs over the top and under the bottom, each through a crown with a neutral machinegoon (both crowns: symmetry).
Finale: the bay ring (both banks and the two crowns) round the empty bay."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from r_maps import RMap  # noqa: E402

CURVES = ("Curve_30", "Curve_45", "Curve_W45", "Curve_60", "Sbend_L2", "Sbend_R2", "Sbend_L4", "Sbend_R4")
LAUNCHER = dict(role="relay", relay="launcher")


def build():
    m = RMap("R-14", "Catapult Bay", "S", "choke",
             "S, 14 platforms, mirrored both ways. A wide empty bay splits the map: the only way straight across is a "
             "1-bridge FERRY between the two banks' middle platforms (time it). Each middle platform is a LAUNCHER pad: "
             "arm it and its aim sweeps the enemy bank - top, middle, bottom - in turn; a line that walks onto the armed pad "
             "is thrown over the bay and lands where the aim stood. The dry ways round are the arcs over the top and under "
             "the bottom, each through a crown held by a neutral MACHINEGOON. Each home has three ways out: its front "
             "platform (to the pad and the bank corners) and two curved roads to the bank's top and bottom. Finale: the bay "
             "ring - both banks and the two crowns - round the empty bay.")
    cy = 40.0
    px = 80.0 - (15.2 + 20.0) / 2                      # the pads 35.2 m apart: a 20 m ferry deck across the bay
    m.P("P", px, cy, tier=2, core=True, **LAUNCHER)
    m.P("Bu", px, cy - kit.CENTRE["S"], tier=2, core=True)
    m.P("Bd", px, cy + kit.CENTRE["S"], tier=2, core=True)
    dy = (kit.CENTRE["S"] ** 2 - (80.0 - px) ** 2) ** 0.5
    m.P("N", 80.0, cy - kit.CENTRE["S"] - dy, tier=2, core=True)  # the crowns (neutral machinegoons, r_maps.GOONS)
    m.P("S", 80.0, cy + kit.CENTRE["S"] + dy, tier=2, core=True)
    m.P("M", px - kit.CENTRE["S"], cy, tier=1)                    # the home's front platform
    m.P("HA", px - kit.CENTRE["S"] - kit.CENTRE["M"], cy, role="homeA")
    m.join("Bu", "P", 1).join("P", "Bd", 1)            # the bank
    m.join("Bu", "N", 1).join("Bd", "S", 1)            # up to the crowns
    m.join("M", "P", 1).join("HA", "M", 2)
    m.join("M", "Bu", 3).join("M", "Bd", 3)            # the front platform's corners
    m.fit("HA", "Bu", pieces=CURVES, angles=range(-10, 61, 5), tol=0.8, name="cU")
    m.fit("HA", "Bd", pieces=CURVES, angles=range(10, -61, -5), tol=0.8, name="cD")
    m.sym("mirror")
    m.join("P", "P'", 5)                               # the 20 m ferry across the bay
    m.hz(proto="ferry", ferry={"dock": "A"})
    m.node_extra["P"] = {"launcher": {"target": "P'", "targets": ["Bu'", "P'", "Bd'"]}}
    m.node_extra["P'"] = {"launcher": {"target": "P", "targets": ["Bd", "P", "Bu"]}}   # (the same sweep, turned half round)
    return m


if __name__ == "__main__":
    import r_maps as R
    m = build()
    p, probs, js = m.write("catapult-bay")
    print(m.stats(js))
    print(probs)
    h, w, so = R.rulebook(js)
    print("HARD", [(x["rule"], x["msg"]) for x in h])
    print("WAIVED", [x["rule"] for x in w])
    print("SOFT", [(x["rule"], x["msg"]) for x in so])
    if "--png" in sys.argv:
        from exp_chain import preview
        preview([(m, js, probs)], sys.argv[-1])
