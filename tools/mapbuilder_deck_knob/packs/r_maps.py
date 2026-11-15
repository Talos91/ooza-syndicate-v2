"""Round R maps R-01..R-10 (map round 2026-11; plan `05 Handoff/MAP-ROUND-2026-11.md`, agreed with Daniele 2026-11-04).

Ten 1v1 maps that replace the whole pool at once (step 7 of the plan). Every map: one signature idea, mirror symmetry
left / right (x = 80), inward Last Stand only with its own finale ring, EXP pieces as core, 3+ routes, firing a relay
changes length, speed or open lanes (R10 info; the R07 choke test was dropped 2026-11-07), relays AND hazards priced by scan cost within the size budget (R02: XS 9, S 7, M 5).
The round-R rules are R01-R09 in mb/rules.py (they run on any map whose "round" is "R-2026-11").

Built with exp_chain.Map (build.html's geometry: the Build page opens every map with no red bridge), plus the hazards and
prototype relays of the proto line (01 Rules/relays-proto-schema.md "Round 3"):
  belt hazard   plain deck  "proto": "conveyor", "belt": "AB" | "BA"     (flow from -> to = AB; no relay, always runs)
  ferry hazard  plain deck  "proto": "ferry", "ferry": {"dock": "A"}     (variant 1: one bridge swinging out and back)
  3-pos ferry   plain decks "proto": "ferry", "ferry": {"group": "F", "pos": 0 | 1 | 2}   (variant 2: one ferry, 2-3
                bridges, it sits on up / mid / down in turn; proto-r branch)
  speed relay   relay "conveyor" node ("conveyor": {"dir": "AB"}) + its decks "proto": "conveyor", "relay": <node>
  retract       live retract; one relay may pull up to 3 decks (R08)

Run:  python Tools/MapBuilder/packs/r_maps.py [R-05 ...] [--sheet=<png>] [--check] [--draft]   (--draft: DRAFTS too)
      writes References/Ooze Syndicate maps - round R/json/R-*.json
Bake: python Tools/MapBuilder/packs/r_maps.py --bake=<game clone> [--no-thumbs] [R-05 ...]
      maps4/R-*.json (mb/bake.py) + thumbnails rendered by the game; a hard rulebook finding stops the bake."""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from exp_chain import Map, preview  # noqa: E402
from mb import kit  # noqa: E402

OUT = os.environ.get("OOZE_R_OUT") or os.path.join(kit.REFS, "Ooze Syndicate maps - round R", "json")
# DRAFTS: maps designed on paper ahead of their game prerequisite (R-06 Fort waits for plan step 3: Lift live, Switch archived,
# Daniele's Desk check-rmaps-1). They are built only with --draft and written to json-draft/ (never OUT), so a bake and the
# MapPool never see them until the flag is lifted (move the code out of DRAFTS).
DRAFTS = set()                             # R-06 left the drafts 2026-11-05 (Daniele: "make 5 more and we do another round of review")
OUT_DRAFT = os.path.join(kit.REFS, "Ooze Syndicate maps - round R", "json-draft")
ROUND = "R-2026-11"
MAPS = []


def mapdef(slug):
    def deco(f):
        MAPS.append((slug, f))
        return f
    return deco


class RMap(Map):
    """exp_chain.Map + round-R fields: hazards / proto relays on decks (hz), a size tag, family, fort flag."""

    def __init__(self, code, name, size, family, note, frame=(160, 80)):
        super().__init__(code, name, note, frame)
        self.size, self.family, self.fort = size, family, False
        self.node_extra = {}                       # node name -> extra JSON fields (e.g. conveyor dir)

    def hz(self, **kw):
        """set hazard / proto fields on the LAST edge laid: proto=, belt=, ferry=, prelay=<relay platform name>"""
        self.edges[-1].update(kw)
        return self

    def fit(self, a, b, pieces=("Sbend_L2", "Sbend_R2", "Sbend_L4", "Sbend_R4", "Curve_30", "Curve_W45", "Curve_45"),
            name=None, angles=None, tol=0.35, hz=None, only=None):
        """an exact chain platform a -> deck x -> piece -> deck y -> platform b (searched: pier angle, x, y in half modules,
        piece, turn); hz = hazard fields for the FIRST deck (only="first" | "last" | None = both). Returns the fit."""
        import math as _m
        from exp_chain import Map as _Map, ang_to, adiff, RP as _RP
        A, B = self.node(a), self.node(b)
        base = ang_to((A["x"], A["y"]), (B["x"], B["y"]))
        best = None
        for da in (angles if angles is not None else range(-40, 41, 5)):
            for pc in pieces:
                for turn in ((+1, -1) if pc.startswith("Curve") else (0,)):
                    for x in (0.5, 1, 1.5, 2, 2.5, 3, 4, 5):
                        t = _Map("t", "t", "")
                        t.P("A", A["x"], A["y"])
                        t.go("A", base + da).deck(x)
                        if turn:
                            t.curve("c", pc, turn)
                        else:
                            t.sbend("c", pc)
                        _, cx, cy, h = t.cur
                        L = _m.hypot(B["x"] - cx, B["y"] - cy) - _RP
                        err = adiff(ang_to((cx, cy), (B["x"], B["y"])), h)
                        y = round(L / (2.0 * kit.DECK_K)) / 2.0
                        if y < 0.5 or y > 5 or err > 2.0:
                            continue
                        e = abs(L - 4 * kit.DECK_K * y) + err * 0.1
                        if e < tol and (best is None or e < best[0]):
                            best = (e, da, pc, turn, x, y)
        assert best, "fit %s-%s: no chain" % (a, b)
        e, da, pc, turn, x, y = best
        nm = name or "c%d" % len(self.nodes)
        self.go(a, base + da).deck(x)
        if hz and only in (None, "first"):
            self.pend.update(hz)
        if turn:
            self.curve(nm, pc, turn)
        else:
            self.sbend(nm, pc)
        self.deck(y)
        if hz and only in (None, "last"):
            self.pend.update(hz)
        self.to(b)
        return best

    def reverse(self, a, b):
        """swap the ends of the deck a-b (its flow AB then runs b -> a)"""
        ia, ib = self.idx(a), self.idx(b)
        for e in self.edges:
            if {e["a"][0], e["b"][0]} == {ia, ib}:
                e["a"], e["b"] = e["b"], e["a"]
                return self
        raise AssertionError("no deck %s-%s" % (a, b))

    def sym(self, kind="mirror", since=(0, 0)):
        n0 = len(self.edges)
        super().sym(kind, since)
        for e in self.edges[n0:]:                    # copies keep their hazard fields; a proto relay maps to its twin
            if e.get("prelay") is not None:
                e["prelay"] = self.twin[self.idx(e["prelay"])]
            if e.get("belt"):                        # the mirror keeps from / to order, so the flow keeps its sense
                pass
        for i, c in list(self.twin.items()):
            nm = self.nodes[i]["name"]
            if nm in self.node_extra and self.nodes[c]["name"] not in self.node_extra:
                self.node_extra[self.nodes[c]["name"]] = dict(self.node_extra[nm])
        return self

    def _order(self):
        vn = [(n["y"], n["x"]) for n in self.nodes]
        vn += [(n["y"], n["x"]) for n in self.nodes if n["kind"] == "j" and n["piece"] == "Crossing"]
        order = sorted(range(len(vn)), key=lambda i: (round(vn[i][0], 2), round(vn[i][1], 2), i))
        return {old: new for new, old in enumerate(order)}

    def to_json(self):
        out = super().to_json()
        idx = self._order()
        for nm, extra in self.node_extra.items():
            extra = json.loads(json.dumps(extra))
            for v in extra.values():                  # node names -> ids: a linked relay's twin (R-13 drives), a launcher's
                if not isinstance(v, dict):           # target / targets (R-14)
                    continue
                for k in ("link", "target"):
                    if isinstance(v.get(k), str):
                        v[k] = idx[self.by[v[k]]]
                if isinstance(v.get("targets"), list):
                    v["targets"] = [idx[self.by[t]] if isinstance(t, str) else t for t in v["targets"]]
            out["nodes"][idx[self.by[nm]]].update(extra)
        for k, e in enumerate(self.edges):
            o = out["edges"][k]
            if e.get("proto"):
                o["proto"] = e["proto"]
                if e.get("prelay") is not None:
                    o["relay"] = idx[self.idx(e["prelay"])]
            if e.get("belt"):
                o["belt"] = e["belt"]
            if e.get("ferry"):
                o["ferry"] = dict(e["ferry"])
            if e.get("lift"):
                o["lift"] = dict(e["lift"])
        out.update(group="R", round=ROUND, family="round R", experimental=False,
                   tags={"size": self.size, "family": self.family, "finale": "inward"})
        out.pop("labVariant", None)
        out["labVariant"] = {"junctions": True}
        if self.fort:
            out["fort"] = True
        return out

    def _lifts_to_laser_relays(self):
        """LASER RELAY (Daniele 2026-11-09, proto25 review: "lift/switch too costly and confusing -> turn lift nodes into a
        LASER RELAY, a relay that can only hold a laser, no other function"). Conservative bake: each lift is frozen where it
        starts - the node becomes relay "laser" at its starting height (base + level), the decks of its starting level stay
        as plain decks, the other level's decks go (no ramps invented). The lift code stays: LASER_RELAYS = False restores it."""
        for i, n in enumerate(self.nodes):
            if n.get("relay") != "lift":
                continue
            nm = n["name"]
            ex = self.node_extra.setdefault(nm, {})
            lf = ex.pop("lift", {}) or {}
            start, base = int(lf.get("level", 0)), int(lf.get("base", 0))
            start = LASER_AT.get(self.code, {}).get(nm.rstrip("'"), start)
            if base + start:
                ex["level"] = base + start
            if not ex:
                self.node_extra.pop(nm)
            n["relay"] = "laser_relay"
            keep = []
            for e in self.edges:
                if e.get("proto") == "lift" and e.get("prelay") is not None and self.idx(e["prelay"]) == i:
                    if LASER_DECKS == "start" and int((e.get("lift") or {}).get("level", 0)) != start:
                        continue                          # the other level's deck: gone
                    for k in ("proto", "prelay", "lift"):
                        e.pop(k, None)
                keep.append(e)
            self.edges[:] = keep

    def write(self, slug):
        if LASER_RELAYS:
            self._lifts_to_laser_relays()
        for nm in GOONS.get(self.code, ()):               # neutral machinegoons (Daniele 2026-11-06), a symmetric set
            n = self.node(nm)
            n["structure"], n["tier"] = "machinegoon", GOON_TIER
        for rule in ("R04",):                             # Daniele 2026-11-06 (Desk): every R04 waiver ACCEPTED (R04 stays at
            w = getattr(self, "waivers", {}) or {}        # 66 m); R07 and its waivers dropped 2026-11-07 (Desk dec-drop-r07)
            if rule in w and "ACCEPTED" not in w[rule]:
                w[rule] += " - ACCEPTED by Daniele 2026-11-06 (Desk)"
        probs, m = self.check()
        out = OUT_DRAFT if self.code in DRAFTS else OUT
        os.makedirs(out, exist_ok=True)
        p = os.path.join(out, "%s-%s.json" % (self.code, slug))
        json.dump(m, open(p, "w", encoding="utf-8"), indent=1)
        return p, probs, m


# NEUTRAL MACHINEGOONS (Daniele 2026-11-05/06: "suggest placement for neutral machinegoon in strategic neutral nodes near the
# center"; "symmetry is key - if you put one in top passage you put one in bottom passage"; "neutral shoot all"; "if you
# capture the goon it's yours like any other structure"): a platform that starts with a built machinegoon instead of its vat,
# shooting every seat's lines in range until someone takes it. Each set is mirrored left / right AND top / bottom; every gun
# T2 so a pair matches.
GOON_TIER = 2
GOONS = {"R-01": ("Lm", "Lm'"), "R-02": ("Ht", "Hb"), "R-05": ("N", "S"), "R-11": ("N", "S"), "R-06": ("N", "S"),
         "R-10": ("D",), "R-14": ("N", "S"), "R-15": ("N", "S"), "R-16": ("N", "S")}


FERRY_FINALE = ("the finale's decision is the ferry between the banks (a hazard on its own clock: when to send, which lane); "
                "the rulebook's stand-in reads a hazard ferry as a fixed deck, so L05 cannot see it (round R, 2026-11-05)")
ROTOR = dict(role="relay", relay="rotation")
SPEED = dict(role="relay", relay="conveyor")
RETRACT = dict(role="relay", relay="retract")
LIFT = dict(role="relay", relay="lift")
LASER_RELAYS = True     # Daniele 2026-11-09: every lift bakes as a LASER RELAY (RMap._lifts_to_laser_relays); False = the lifts
LASER_DECKS = "both"    # "both": every deck of the old lift stays (the layout is kept; the stone sits at its start height and its
                        # other level's decks run as slopes); "start": only its start level's decks (breaks R05 / N04 on R-01, R-12)
LASER_AT = {}   # a stone frozen at another level than its start ("start" mode needed R-12 B at 0 for L03), e.g. {"R-12": {"B": 0}}; else the
                                # survivor ring's platform 18 is cut off over fixed decks once ring 1 falls (rulebook L03)


# ---------------------------------------------------------------------------------------------------------------- R-01
@mapdef("strait")
def r01():
    # Daniele 2026-11-05 (proto8 review): "Strait 1 and 2 should be merged - the central kill area with the 3-way ferry; top
    # and bottom have a laser LIFT, not a retract, and the lift alternates the connected bridges; and mirror on the other
    # side". So: R-01's 3-position ferry, a stone above AND below the strait (mirrored top / bottom as well as left / right),
    # each a laser lift: DOWN joins the two outer roads, UP joins the two banks' end platforms. R-03 leaves the picker.
    m = RMap("R-01", "Strait", "XS", "choke",
             "XS, 14 platforms, mirrored both ways. A strait runs down the middle; ONE ferry serves its three crossings and "
             "sits on the top, middle, bottom, middle lane in turn (time your send to the lane it is heading for). The dry "
             "ways over are the two stones, top and bottom - each a laser LIFT between the banks (ground) and its outer road: "
             "the top roads stand raised, the bottom roads lowered, so the top stone goes UP to its road and the bottom one "
             "DOWN to its road (the top one starts on its road, the bottom one on the banks). Each home's straight middle road is a belt "
             "toward the strait. Finale: the two banks, split by the ferry.")
    KS = 4.0 * kit.DECK_K                                                     # MAP-SIZE STUDY: one module in metres
    cy, bx, half = 40.0, 80.0 - (3 * KS + 2 * 7.6) / 2, 2 * 7.6 + 0.5 * KS     # half: centre gap over a 2 m half deck
    dy = (half ** 2 - (80.0 - bx) ** 2) ** 0.5                               # the stone sits that far above the top lane
    m.P("Lm", bx, cy, tier=2, core=True)
    # Daniele 2026-11-06 (proto21): "the lift bridge still looks weird as we use a lift without a second level - the top
    # part of the map raised and the bottom lowered". The outer roads stand on their own level (Pu +1, Pd -1, a ramp on
    # the curved road from home); each stone lifts between the bank (ground) and its outer road's level: T 0 / +1, B -1 / 0
    # ("base": -1). Both start where they did: T on the outer road (its level 1), B on the bank (its level 1 = ground).
    # Daniele 2026-11-09 (Desk laser-relay-decks = a): "map needs to be symmetric, currently top and bottom have different
    # bridges (top has S shape somehow)" - the top stone stood raised (level 1) with a 0.5-tier ramp down to its bank (the S).
    # With the laser relays (no lift) the top now mirrors the bottom: outer road lowered (-1), stone on the bank (ground).
    for sgn, st, lane, pier, base, plv in ((-1, "T", "Lu", "Pu", -1, -1), (1, "B", "Ld", "Pd", -1, -1)):
        m.P(lane, bx, cy + sgn * half, tier=1, core=True)
        m.P(st, 80.0, cy + sgn * (half + dy), tier=3, structure="laser", **LIFT)
        m.node_extra[st] = {"lift": {"level": 1, "base": base}}
        m.P(pier, bx - (80.0 - bx), cy + sgn * (half + dy), tier=1)
        m.node_extra[pier] = {"level": plv}
    m.P("HA", bx - (2 * 7.6 + 3 * KS), cy, role="homeA")
    m.join("Lu", "Lm", 0.5).join("Lm", "Ld", 0.5)
    m.join("HA", "Lm", 3)
    m.hz(proto="conveyor", belt="AB")                                       # the home's middle road: a belt to the strait
    for st, lane, pier, road, bank in (("T", "Lu", "Pu", 0, 1), ("B", "Ld", "Pd", 0, 1)):
        lift_deck(m, st, pier, 3, st, road)                                 # the outer road, at its level (T up, B down)
        lift_deck(m, st, lane, 0.5, st, bank)                               # the bank's end platform, on the ground
    m.fit("HA", "Pu", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(5, 61, 5), tol=0.6, name="rU")
    m.fit("HA", "Pd", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(-5, -61, -5), tol=0.6, name="rD")
    m.where("Lu", "Lm", "Ld", "T", "B", "Pu", "Pd", "HA")
    m.sym("mirror")
    for k, nm in enumerate(("Lu", "Lm", "Ld")):
        m.join(nm, nm + "'", 3)
        m.hz(proto="ferry", ferry={"group": "F", "pos": k})
    m.waivers = {"L05": FERRY_FINALE,                         # R07 waiver dropped with the rule (Daniele 2026-11-07, Desk dec-drop-r07)
                 "R04": "Daniele 2026-11-05 merge (stone above AND below the 3-lane strait over 2 m half decks): 67.5 m tall, "
                        "1.5 m over the provisional 66 m line; the phone probe decides (plan rule 7)"}
    return m


# ---------------------------------------------------------------------------------------------------------------- R-17
R17_HOME = 3            # modules of each home's two roads onto the lanes (3 = L 12 m)


@mapdef("strait-2")
def r17():
    # Daniele 2026-11-12: "do a version of strait with 1 less center connection bridge so 2 nodes less and 1 less ferry
    # bridge (so the map shrink in height a bit)". R-01 minus its middle crossing: the middle lane platforms Lm / Lm' and
    # their ferry deck go, the top and bottom lanes close up to one 2 m half deck apart (17.2 m), the ferry serves 2
    # crossings (R08: 2 or 3), and each home's single middle road (to Lm) becomes two belts, one onto each lane.
    # No neutral machinegoons (R-01's stood on Lm): Daniele 2026-11-12, "Leave without goons" - keep R-17 out of GOONS.
    m = RMap("R-17", "Strait 2", "XS", "choke",
             "XS, 12 platforms, mirrored both ways. R-01 with two crossings: a strait runs down the middle and ONE ferry "
             "serves its two crossings, top and bottom lane in turn. The dry ways over are the two stones, top and bottom, "
             "each a laser relay over its bank. Each home's two straight roads are belts toward the strait. Finale: the two "
             "banks, split by the ferry.")
    cy, bx, half = 40.0, 80.0 - kit.CENTRE["L"] / 2, 2 * 7.6 + 2.0
    dy = (half ** 2 - (80.0 - bx) ** 2) ** 0.5
    gap = half / 2                                                           # each lane sits half a half-deck gap off the axis
    for sgn, st, lane, pier, base, plv in ((-1, "T", "Lu", "Pu", -1, -1), (1, "B", "Ld", "Pd", -1, -1)):
        m.P(lane, bx, cy + sgn * gap, tier=1 if sgn < 0 else 2, core=True)
        m.P(st, 80.0, cy + sgn * (gap + dy), tier=3, structure="laser", **LIFT)
        m.node_extra[st] = {"lift": {"level": 1, "base": base}}
        m.P(pier, bx - (80.0 - bx), cy + sgn * (gap + dy), tier=1)
        m.node_extra[pier] = {"level": plv}
    L = R17_HOME * kit.S * kit.DECK_K + 2 * (kit.R + kit.PIER)                                             # home to lane, centre to centre
    m.P("HA", bx - (L ** 2 - gap ** 2) ** 0.5, cy, role="homeA")
    m.join("Lu", "Ld", 0.5)
    for lane in ("Lu", "Ld"):
        m.join("HA", lane, R17_HOME)
        m.hz(proto="conveyor", belt="AB")                                   # the home's roads: belts to the strait
    for st, lane, pier, road, bank in (("T", "Lu", "Pu", 0, 1), ("B", "Ld", "Pd", 0, 1)):
        lift_deck(m, st, pier, 3, st, road)
        lift_deck(m, st, lane, 0.5, st, bank)
    m.fit("HA", "Pu", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(5, 81, 5), tol=0.6, name="rU")
    m.fit("HA", "Pd", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(-5, -81, -5), tol=0.6, name="rD")
    m.where("Lu", "Ld", "T", "B", "Pu", "Pd", "HA")
    m.sym("mirror")
    for k, nm in enumerate(("Lu", "Ld")):
        m.join(nm, nm + "'", 3)
        m.hz(proto="ferry", ferry={"group": "F", "pos": k})
    m.waivers = {"L05": FERRY_FINALE}
    return m


# ---------------------------------------------------------------------------------------------------------------- R-02
@mapdef("gate")
def r02():
    m = RMap("R-02", "Gate", "S", "choke",
             "S, 15 platforms. Two roads round each side and one straight road through a gatehouse (G: a retract relay with "
             "a laser); both outer road corners also link to the gatehouse. G's owner pulls BOTH its doors into the hexagon at "
             "once (2 decks): the short road shuts and armies take the long S-bend roads past the gatehouse laser. The hub is "
             "a speed relay joined six ways: its four side decks mirror left / right (top fast going in, bottom slow going in, "
             "on both sides); firing it reverses all four. Finale: the hexagon and its hub.")
    cx, cy, s = 80.0, 40.0, kit.CENTRE["S"]
    import math as _m
    hx = s * _m.cos(_m.radians(30))
    m.P("X", cx, cy, core=True, **SPEED)
    m.node_extra["X"] = {"conveyor": {"dir": "AB"}}
    m.P("Ht", cx, cy - s, tier=1, core=True)
    m.P("Hb", cx, cy + s, tier=2, core=True)
    m.P("Hul", cx - hx, cy - s / 2, tier=2, core=True)
    m.P("Hll", cx - hx, cy + s / 2, tier=1, core=True)
    m.tri("G", "Hul", 2, "Hll", 2, side=1, structure="laser", **RETRACT)
    m.P("HA", m.node("G")["x"] - s, cy, role="homeA")
    m.tri("Ru", "HA", 2, "G", 2, side=-1, tier=1)
    m.tri("Rl", "HA", 2, "G", 2, side=1, tier=2)
    m.join("X", "Ht", 1).join("X", "Hb", 1)
    m.join("X", "Hul", 1)
    m.hz(proto="conveyor", prelay="X")
    m.reverse("X", "Hul")                                     # left top: flows INTO the hub (fast going in)
    m.join("X", "Hll", 1)                                     # left bottom: flows out of the hub (slow going in)
    m.hz(proto="conveyor", prelay="X")                        # (Daniele 2026-11-05: the hub joined six ways, sides alternated)
    m.join("Ht", "Hul", 1).join("Hul", "Hll", 1).join("Hll", "Hb", 1)
    m.join("G", "Hul", 2, retract="G").join("G", "Hll", 2, retract="G")
    m.join("HA", "G", 1).join("HA", "Ru", 2).join("HA", "Rl", 2).join("Ru", "G", 2)
    m.join("Rl", "G", 2)                                      # (Daniele 2026-11-05: the lower corner links to the gatehouse too)
    m.fit("Ru", "Ht", angles=range(10, 41, 5))
    m.fit("Rl", "Hb", angles=range(-40, -9, 5))
    m.sym("mirror")
    # (Daniele 2026-11-05, proto10 check: "the default position of speed on the right needs to mirror the left" - the mirror
    # copy already has right top flowing INTO the hub (fast going in) and right bottom out of it (slow going in))
    m.waivers = {}                                            # R07 waiver dropped with the rule (Daniele 2026-11-07, Desk dec-drop-r07)
    return m


# ---------------------------------------------------------------------------------------------------------------- R-03
@mapdef("strait-2")
def r03():
    m = RMap("R-03", "Strait 2", "XS", "choke",
             "XS, 13 platforms. R-01's strait upside down and with three ferries of their own: each crossing is a "
             "1-bridge ferry swinging out and back on its own clock, the top and bottom ones in step, the middle one half a "
             "cycle off (one crossing is always about to open). The dry way is the bottom stone, whose owner retracts the "
             "outer roads into it. Curved belt roads from each home to the middle bank. Finale: the banks.")
    s, gap = kit.CENTRE["S"], kit.CENTRE["L"]
    bx = 80.0 - gap / 2
    d = s / 2 ** 0.5
    yb = 72.0
    m.P("T", 80.0, yb, tier=3, **RETRACT)
    m.P("Ld", 80.0 - d, yb - d, tier=1, core=True)
    m.P("Lm", bx, yb - d - s, tier=2, core=True)
    m.P("Lu", bx, yb - d - 2 * s, tier=1, core=True)
    m.P("Pd", 80.0 - kit.CENTRE["L"], yb, tier=1)
    m.P("HA", 25.2, yb - d - s + 8.0, role="homeA")
    m.tri("U2", "HA", 2, "Pd", 2, side=1, tier=1)
    m.tri("U1", "HA", 2, "Lu", 3, side=-1, tier=2)
    m.join("T", "Ld", 1).join("T", "Pd", 3, retract="T")
    m.join("Ld", "Lm", 1).join("Lm", "Lu", 1)
    m.join("HA", "U1", 2).join("U1", "Lu", 3).join("HA", "U2", 2).join("U2", "Pd", 2)
    m.join("Pd", "Ld", 1)
    m.fit("HA", "Lm", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(-60, 61, 5), tol=0.6,
          hz={"proto": "conveyor", "belt": "AB"}, only="first")
    m.sym("mirror")
    for nm, dock in (("Lu", "A"), ("Lm", "B"), ("Ld", "A")):
        m.join(nm, nm + "'", 3)
        m.hz(proto="ferry", ferry={"dock": dock})
    m.waivers = {"L05": FERRY_FINALE}
    return m


# ---------------------------------------------------------------------------------------------------------------- R-04
RU_ANG = 60


@mapdef("gate-2")
def r04():
    m = RMap("R-04", "Gate 2", "S", "choke",
             "S, 13 platforms. An hourglass keep: two triangles (top and bottom) meet at the centre stone X, with a "
             "gatehouse in each side of the waist (G: a retract relay with a laser). G's owner pulls its top door and its "
             "waist door into the gatehouse at once (2 decks): on that side the keep opens only by the bottom door, and "
             "armies take the outer roads round to a corner - the top road is a belt running toward the keep - past the "
             "gatehouse laser. Finale: the hourglass and its two gatehouses.")
    import math as _m
    cx, cy, s = 80.0, 40.0, kit.CENTRE["S"]
    hy = s * _m.sin(_m.radians(60))
    m.P("X", cx, cy, tier=3, core=True)
    m.P("Hu", cx - s / 2, cy - hy, tier=1, core=True)
    m.P("Hd", cx - s / 2, cy + hy, tier=2, core=True)
    m.P("G", cx - s, cy, tier=2, core=True, structure="laser", **RETRACT)
    m.P("HA", cx - s - kit.CENTRE["L"], cy, role="homeA")
    m.join("X", "Hu", 1).join("X", "Hd", 1)
    m.join("G", "Hu", 1, retract="G").join("G", "X", 1, retract="G").join("G", "Hd", 1)
    m.join("HA", "G", 3)
    m.pp("Ru", "HA", RU_ANG, 3, tier=1)
    m.pp("Rl", "HA", -RU_ANG, 3, tier=2)
    m.where("Ru", "Rl")
    m.fit("Ru", "Hu", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(-30, 31, 5), tol=0.6,
          hz={"proto": "conveyor", "belt": "AB"}, only="first")
    m.fit("Rl", "Hd", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=range(-30, 31, 5), tol=0.6)
    m.sym("mirror")
    m.join("Hu", "Hu'", 1).join("Hd", "Hd'", 1)
    return m


# ---------------------------------------------------------------------------------------------------------------- R-05
def set_edge(m, a, b, **kw):
    """set fields on the existing deck a-b (either way round)"""
    ia, ib = m.idx(a), m.idx(b)
    for e in m.edges:
        if {e["a"][0], e["b"][0]} == {ia, ib}:
            e.update(kw)
            return m
    raise AssertionError("no deck %s-%s" % (a, b))


PW_WANG = [x * 0.5 for x in range(-30, 1)]
PW_LOW_WANG = [x * 0.5 for x in range(-32, 1)]                # R-15 / R-16: W - Ul road angles (searched 2026-11-10: an S-bend like R-05's,
                                                               # clear of W - P1 and the N - Ul deck; wider windows pick a clashing Curve_45)
PW_ANG = range(0, 41, 5)                                       # R-05: pier angles of the ferry-pier roads (top; bottom = -)


def belt_from(m, a, b):
    """make the existing deck a-b a plain belt flowing a -> b"""
    ia, ib = m.idx(a), m.idx(b)
    for e in m.edges:
        if {e["a"][0], e["b"][0]} == {ia, ib}:
            e.update(proto="conveyor", belt="AB" if e["a"][0] == ia else "BA")
            return m
    raise AssertionError("no deck %s-%s" % (a, b))


def pinwheel(code, name, side_relay, low=False):
    """R-05 (side_relay "rotor") and its variant R-11 (side_relay "speed"); Daniele 2026-11-05 (proto9 review): "mirror the
    bottom to the top; a conveyor on the top-left and bottom-right bridges, both facing the centre; a ferry top and bottom;
    2 rotors on the two nodes next to the homes with bridges up and down - a line of 3 rotors". Then: "another version: don't
    add the bridge to the relay we turned into a rotor, turn those 2 into speed relays and add speed / slow bridges on the top
    and bottom outer bridges, mirrored on both sides".
    low=True: the 66 m variants R-15 / R-16 (Daniele 2026-11-06, Desk R04: "try to do a version that is shrunk on top and
    bottom to be 66 m"). The tall versions are 77.5 m because each ferry pier hangs off N / S at 45 degrees: a pier deck
    must leave the ferry by ~37 degrees (G13) and the ferry line must pass 8.6 m clear of N (G04), so no ferry over N fits
    66 m while N keeps its 4 m spokes and 4 m pier decks. The first try (2026-11-06) dropped the N - pier decks; Daniele
    2026-11-07 (Desk dec-pinwheel-66): "connect to the nodes same way as 78, build a bridge that size if we don't have one".
    So the low version (2026-11-10) (1) shortens the four centre-rotor spokes to 1 m QUARTER bridges (0.25 module, the new
    bridge; the star stays rigid) and (2) joins N / S to their ferry piers by 2 m HALF bridges at 37.7 deg off the ferry, as
    R-05 does with 4 m ones: platform span 65.5 m."""
    rotor = side_relay == "rotor"
    note = ("S, 17 platforms, mirrored both ways. THREE rotors on the middle line: the centre (C) and the stone next to each "
            "home (M): ACROSS opens the straight middle road, UP / DOWN shuts it and opens the north / south ways (at M: "
            "home - M - the top / bottom corner). " if rotor else
            "S, 17 platforms, mirrored both ways. The centre is a rotor (C: ACROSS opens the middle road, UP / DOWN the "
            "north / south points); the stone next to each home (M) is a SPEED relay driving four roads: on the left the "
            "top pier road is slow going in, the top inner road fast, the bottom inner road slow, the bottom pier road fast "
            "(the curved pier roads are speed lanes end to end); the right side the same turned half round. Firing M "
            "reverses its four. ")
    m = RMap(code, name, "S", "open", note +
             "A 1-bridge ferry joins the top pair and another the bottom pair. " + ("The outer roads to the top-left and "
             "bottom-right ferry piers are belts running toward the centre (the pinwheel's turn). " if rotor else "") +
             "Finale: the star round the centre rotor.")
    cx, cy, s = 80.0, 40.0, kit.CENTRE["S"]
    pier = kit.CENTRE["S"]                                       # ferry pier to its star point: a 4 m deck at 45 deg
    gap = kit.CENTRE["L"]                                   # the 12 m ferries
    k = 2 * 7.6 + 1.0 if low else s                            # centre rotor spoke: 1 m quarter bridges on the low variant
    py = (kit.CENTRE["L"] ** 2 - s ** 2) ** 0.5 if low else s             # P1 / P2: 12 m roads to HA and W (s apart either side)
    m.P("C", cx, cy, core=True, **ROTOR)
    m.P("W", cx - k, cy, tier=2, core=True)
    m.P("N", cx, cy - k, tier=3)
    m.P("S", cx, cy + k, tier=1, core=True)
    m.P("M", cx - k - s, cy, tier=1, **(ROTOR if rotor else SPEED))
    m.P("HA", cx - k - 2 * s, cy, role="homeA")
    m.P("P1", cx - k - s, cy - py, tier=1)
    m.P("P2", cx - k - s, cy + py, tier=2)
    # low: the pier hangs off N by a 2 m half bridge at 37.7 deg off the ferry (G13 needs ~36.7 deg at the pier rim), so the
    # ferry line passes 10.5 m from N; the 1 m spokes keep the platform span at 65.5 m (R04 66 m)
    dy = ((2 * 7.6 + 2.0) ** 2 - (gap / 2) ** 2) ** 0.5 if low else (pier ** 2 - (gap / 2) ** 2) ** 0.5
    m.P("Ul", cx - gap / 2, cy - k - dy, tier=1, core=True)
    m.P("Dl", cx - gap / 2, cy + k + dy, tier=1, core=True)
    sp = 0.25 if low else 1
    m.join("C", "W", sp, state="r1", relay="C")
    m.join("C", "N", sp, state="r2", relay="C")
    m.join("C", "S", sp, state="r2", relay="C")
    if rotor:
        m.join("HA", "M", 1, state="r1", relay="M").join("M", "W", 1, state="r1", relay="M")
        m.join("M", "P1", 1, state="r2", relay="M").join("M", "P2", 1, state="r2", relay="M")
        m.join("HA", "P1", 3).join("P1", "W", 3).join("HA", "P2", 3).join("P2", "W", 3)
    else:
        m.node_extra["M"] = {"conveyor": {"dir": "AB"}}
        m.join("HA", "M", 1).join("M", "W", 1)
        m.join("HA", "P1", 3).join("HA", "P2", 3)
        # Daniele 2026-11-05 (R-11 correction, sketch: blue = speed, red = slow at the start, going in): M drives FOUR roads
        # - top pier road slow, top inner road fast, bottom inner road slow, bottom pier road fast; the right side is the
        # same turned half round (its top pier road fast ...). A curved road is a speed lane end to end (its curve too).
        m.join("P1", "W", 3)
        m.hz(proto="conveyor", prelay="M")                   # top inner road: flows P1 -> W (fast going in)
        m.join("W", "P2", 3)
        m.hz(proto="conveyor", prelay="M")                   # bottom inner road: flows W -> P2 (slow going in)
    # Daniele 2026-11-07 (Desk dec-pinwheel-66): "connect to the nodes same way as 78, build a bridge that size if we don't have
    # one". Low variant: N - Ul is a 2 m half bridge (0.5 module) like R-05's 4 m one; a straight 1 m deck would leave the
    # ferry at 33 deg (G13 clash), so the spokes became 1 m quarter bridges (Q, 0.25 module) to stay under 66 m.
    m.join("Ul", "N", 0.5 if low else 1).join("Dl", "S", 0.5 if low else 1)
    CURVES = ("Curve_30", "Curve_45", "Curve_W45", "Curve_60", "Sbend_L2", "Sbend_R2", "Sbend_L4", "Sbend_R4")
    SB = ("Sbend_L2", "Sbend_R2", "Sbend_L4", "Sbend_R4")
    lane = None if rotor else {"proto": "conveyor", "prelay": "M"}       # R-11: the pier roads are M's speed lanes
    m.fit("P1", "Ul", pieces=CURVES, angles=PW_ANG, tol=0.6, name="cP1", hz=lane)
    m.fit("P2", "Dl", pieces=CURVES, angles=[-a for a in PW_ANG], tol=0.6, name="cP2", hz=lane)
    if not rotor:
        m.reverse("P1", "cP1").reverse("cP1", "Ul")           # top pier road: flows Ul -> P1 (slow going in)
    wp, wa = (CURVES, PW_LOW_WANG) if low else (SB, PW_WANG)   # low: any curve, angles clear of W - P1 and the N - Ul deck
    m.fit("W", "Ul", pieces=wp, angles=wa, tol=0.6, name="cW1")             # an S-bend: it reaches the pier from the
    m.fit("W", "Dl", pieces=wp, angles=[-a for a in wa], tol=0.6, name="cW2")   # lower left, clear of its N deck
    m.sym("mirror")
    m.join("Dl", "Dl'", 3)
    m.hz(proto="ferry", ferry={"dock": "A"})
    m.join("Ul", "Ul'", 3)
    m.hz(proto="ferry", ferry={"dock": "A"})
    if rotor:
        belt_from(m, "P1", "cP1")                             # top-left: the belt runs toward the centre
        belt_from(m, "P2'", "cP2'")                           # bottom-right: the same (a turn, not a mirror)
    else:                                                     # the right side's four roads run the other way round
        for a, b in (("P1'", "cP1'"), ("cP1'", "Ul'"), ("P1'", "W'"), ("W'", "P2'"), ("P2'", "cP2'"), ("cP2'", "Dl'")):
            m.reverse(a, b)
    m.waivers = {} if low else {"R04": "Daniele 2026-11-05: mirrored top / bottom (a ferry pair above and below the star) - taller "
                                       "than the provisional 66 m line; the phone probe decides (plan rule 7); ACCEPTED by Daniele "
                                       "2026-11-06 (Desk R04), the 66 m try is R-15 / R-16"}
    # R-11 / R-16: R07 waiver dropped with the rule (Daniele 2026-11-07, Desk dec-drop-r07)
    return m


@mapdef("pinwheel")
def r05():
    return pinwheel("R-05", "Pinwheel", "rotor")


@mapdef("pinwheel-b")
def r11():
    return pinwheel("R-11", "Pinwheel B", "speed")


@mapdef("pinwheel-66")
def r15():
    return pinwheel("R-15", "Pinwheel 66", "rotor", low=True)          # R-05 shrunk to 66 m (pinwheel low=True)


@mapdef("pinwheel-b-66")
def r16():
    return pinwheel("R-16", "Pinwheel B 66", "speed", low=True)        # R-11 shrunk to 66 m


# ---------------------------------------------------------------------------------------------------------------- R-06
def lift_deck(m, a, b, mods, lift, level):
    """a straight deck a-b that the lift `lift` opens at `level` (0 down / 1 up; proto line `lift` relay)"""
    m.join(a, b, mods)
    m.hz(proto="lift", prelay=lift, lift={"level": level})
    return m


TOP_ANG = range(10, 46, 5)                                     # R-06: the tower roads leave up / down (G13 at N / S)


@mapdef("fort")
def r06():
    m = RMap("R-06", "Fort", "S", "fort",
             "S, 13 platforms. Each home is a keep: two towers (its walls) and a LIFT gate in front. The lift DOWN opens "
             "the keep's door and the front gate (home - lift - the courtyard), the lift UP shuts both and joins the two "
             "towers behind it (a wall walk: move the garrison between the towers without leaving the keep). Out of each "
             "keep: the front gate to the courtyard's side corner, the top tower's curved road to the crown (N), the bottom "
             "tower's curved road to the south corner (S). The centre is open: a rotor swings its spokes between N / S and "
             "the two side corners. Finale: the courtyard diamond round the rotor (plan said triangle: a rotor inside a "
             "triangle fails N13 / G13 - its spokes need the same count per state and 120 degrees; see the role note).")
    m.fort = True
    cx, cy, s = 80.0, 38.0, kit.CENTRE["S"]
    m.P("C", cx, cy, core=True, **ROTOR)
    m.pp("N", "C", 90, 1, deck_kw={"state": "r1", "relay": "C"}, tier=3, core=True)
    m.pp("Wc", "C", 180, 1, deck_kw={"state": "r2", "relay": "C"}, tier=2, core=True)
    m.pp("S", "C", 270, 1, deck_kw={"state": "r1", "relay": "C"}, tier=1, core=True)
    m.join("Wc", "N", 3).join("Wc", "S", 3)                   # the courtyard (diamond, 12 m sides)
    m.pp("LA", "Wc", 180, 1, tier=2, structure="laser", **LIFT)
    m.hz(proto="lift", prelay="LA", lift={"level": 0})       # the front gate (down)
    m.node_extra["LA"] = {"lift": {"level": 0}}
    m.pp("HA", "LA", 180, 1, role="homeA")
    m.hz(proto="lift", prelay="LA", lift={"level": 0})       # the keep's door (down)
    m.tri("Tu", "HA", 1, "LA", 1, side=-1, tier=1)
    m.tri("Td", "HA", 1, "LA", 1, side=1, tier=1)
    m.join("HA", "Tu", 1).join("HA", "Td", 1)                 # the home's own walls
    lift_deck(m, "LA", "Tu", 1, "LA", 1)                      # the wall walk (up)
    lift_deck(m, "LA", "Td", 1, "LA", 1)
    m.where("N", "Wc", "S", "LA", "HA", "Tu", "Td")
    m.fit("Tu", "N", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=TOP_ANG, tol=0.6, name="cT")
    m.fit("Td", "S", pieces=("Curve_30", "Curve_45", "Curve_W45", "Curve_60"), angles=[-a for a in TOP_ANG], tol=0.6, name="cB")
    m.sym("mirror")
    return m


def rulebook(js):
    from mb import rules
    items = rules.check(js)
    w = js.get("ruleWaivers") or {}
    hard = [x for x in items if x["sev"] == "hard" and x["rule"] not in w]
    waived = [x for x in items if x["sev"] in ("hard", "waived") and x["rule"] in w]
    soft = [x for x in items if x["sev"] not in ("hard", "waived")]
    return hard, waived, soft


def bake_game(game, only=(), thumbs=True):
    from mb import bake, bake5
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".json") and (not only or f[:4] in only))
    maps = [(f, json.load(open(os.path.join(OUT, f), encoding="utf-8"))) for f in files]
    bad = [(f, [x["rule"] + " " + x["msg"] for x in rulebook(js)[0]]) for f, js in maps]
    bad = [b for b in bad if b[1]]
    if bad:
        for f, h in bad:
            print("GATE", f, h)
        raise SystemExit("round R: %d map(s) fail the rulebook - nothing baked" % len(bad))
    for f, js in maps:
        b = bake.baked(js)
        json.dump(b, open(os.path.join(game, "maps4", f), "w", encoding="utf-8"), indent=1)
        print("baked", f, b["layout"]["verify"])
        if thumbs:
            d = os.path.join(game, "assets", "maps4", "thumbs")
            os.makedirs(d, exist_ok=True)
            png = os.path.join(d, js["code"] + ".png")
            subprocess.run([bake5.GODOT, "--path", game, "--audio-driver", "Dummy", "--position", "-6000,-6000",
                            "--", "--map=res://maps4/" + f, "--thumb=" + png], capture_output=True, timeout=300)
            imp = png + ".import"
            if not os.path.exists(imp) or "compress/mode=1" not in open(imp, encoding="utf-8").read():
                open(imp, "w", encoding="utf-8").write(bake5.IMPORT % js["code"])
            print("thumb", js["code"], os.path.exists(png) and os.path.getsize(png))
    return 0


# Wave 2 (Daniele 2026-11-05: "make 5 more and we do another round of review ... 1 xs 2 s 2 m"): R-06 above + four makers in
# their own files (each `build()` returns the RMap; they import this module, so they are loaded here, only when run as a script).
WAVE2 = (("r_new_r09", "stack"), ("r_new_r10", "crescent"), ("r_new_r12", "crossfire"), ("r_new_r13", "gearbox"), ("r_new_r14", "catapult-bay"))


def _wave2():
    import importlib
    for mod, slug in WAVE2:
        MAPS.append((slug, importlib.import_module(mod).build))


def main():
    _wave2()
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sheet = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--sheet=")), None)
    game = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--bake=")), None)
    if game:
        return bake_game(game, args, thumbs="--no-thumbs" not in sys.argv)
    out = []
    for slug, f in MAPS:
        m = f()
        if args and m.code not in args:
            continue
        if m.code in DRAFTS and "--draft" not in sys.argv:
            continue
        p, probs, js = m.write(slug)
        print("%s %-10s %s" % (m.code, m.name, m.stats(js)))
        for x in probs:
            print("   !", x)
        if "--check" in sys.argv:
            hard, waived, soft = rulebook(js)
            for x in hard:
                print("   HARD", x["rule"], x["msg"])
            for x in waived:
                print("   waived", x["rule"], x["msg"])
            for x in soft:
                print("   %s %s %s" % (x["sev"], x["rule"], x["msg"]))
        out.append((m, js, probs))
    if sheet:
        preview(out, sheet)


if __name__ == "__main__":
    main()
