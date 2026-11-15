"""POOL G (map-pool-g 2026-11-15): the 19 maps that go forward at deck tiers 2 / 4 / 6 m, re-coded G-01..G-19.

Daniele, 2026-11-15: "the 14 pass and the 5 close fail remain (give them a new letter these identify the ones we move forward with)
... also a couple of maps have very crooked weird shape bridge like strait 2, fix them".

    python packs/pool_g.py --shrunk=<maps4 of map-shrink 536b97c> --game=<clone> [--write] [--json=<report>] [OLD CODES...]

Per map (G number = its place in KEEP, the SHRINK-36 table order): the map-shrink bake (2 / 4 / 6 m), then mb.straighten (a plain
curve between two platforms -> one straight deck; nothing moves), the rulebook before / after (hard findings counted per rule: node
ids shift when a curve leaves), re-coded (code G-xx, group G, `was` = the old code; name and file slug kept) and baked by
mb.bake.write_game into <clone>/maps4/G-xx-<slug>.json (no schematic thumbnail: the game's 3D thumb of the old code moves to the G
code). A map whose straight decks would add a hard rulebook finding keeps its curves (listed as kept). The old-coded json and thumb of a kept map leave the clone (git history keeps them); the REWORK maps are not touched."""
import collections
import glob
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from mb import bake, rules, shrink, straighten  # noqa: E402

KEEP = "R-02 R-06 R-10 R-12 R-14 R-17 P-01 P-03 P-05 E-01 E-02 E-04 E-06 E-07 E-08 E-10 N-02 N-03 N-05".split()
# SHRINK-36 table order: the 14 PASS + the 5 close fails (R-10, R-14, P-01, E-06, E-07)


def hard(m):
    return dict(collections.Counter(i["rule"] for i in rules.check(m) if i["sev"] == "hard"))


def main(argv):
    opts = {a.split("=", 1)[0]: (a.split("=", 1) + [""])[1] for a in argv if a.startswith("--")}
    codes = [a for a in argv if not a.startswith("--")] or KEEP
    shrunk, game = opts["--shrunk"], opts.get("--game")
    rows = []
    for c in codes:
        g = "G-%02d" % (KEEP.index(c) + 1)
        f_old = glob.glob(os.path.join(shrunk, c + "-*.json"))[0]
        slug = os.path.basename(f_old)[len(c) + 1:]
        m0 = json.load(open(f_old, encoding="utf-8"))
        m0.pop("layout", None)
        m1, rep = straighten.straighten(m0)
        h0, h1 = hard(m0), hard(m1)
        worse = sorted(r for r in h1 if h1[r] > h0.get(r, 0))
        if worse:                                     # straight decks that break a rule -> keep the curves (E-10: a relay's tower
                                                      # ledge, G09; R-14: the planner lays them 2.6 m off the chord, G05)
            rep = {"removed": [], "kept": [(r[0], r[1], "straight decks add " + "/".join(worse)) for r in rep["removed"]] + rep["kept"],
                   "edges": []}
            m1, h1 = json.loads(json.dumps(m0)), h0
        m1["code"], m1["group"], m1["was"] = g, "G", c
        verify = None
        if "--write" in opts and game:
            verify = bake.write_game(m1, game, g + "-" + slug, thumb=False)
            old_json = os.path.join(game, "maps4", c + "-" + slug)
            if os.path.exists(old_json):
                os.remove(old_json)
            th = os.path.join(game, "assets", "maps4", "thumbs")
            if os.path.exists(os.path.join(th, c + ".png")):
                shutil.move(os.path.join(th, c + ".png"), os.path.join(th, g + ".png"))
            imp = os.path.join(th, c + ".png.import")             # keep its import settings (lossy, ~18 MB of pck otherwise)
            if os.path.exists(imp):
                txt = open(imp, encoding="utf-8").read().replace(c + ".png", g + ".png")
                txt = "\n".join(l for l in txt.split("\n") if not l.startswith("uid="))
                open(os.path.join(th, g + ".png.import"), "w", encoding="utf-8", newline="\n").write(txt)
                os.remove(imp)
        row = {"g": g, "was": c, "file": g + "-" + slug, "straightened": rep["removed"], "kept_curves": rep["kept"],
               "hard_before": h0, "hard_after": h1, "verify": verify, "footprint": [round(v, 1) for v in shrink.footprint(m1)]}
        rows.append(row)
        print("%s <- %s  straight %d %s  kept %d  hard %s -> %s  %s" % (
            g, c, len(rep["removed"]), [(r[2], r[3], r[4]) for r in rep["removed"]], len(rep["kept"]), h0, h1,
            "" if verify is None else json.dumps(verify)[:200]), flush=True)
    if opts.get("--json"):
        json.dump(rows, open(opts["--json"], "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:])
