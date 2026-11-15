"""DECK KNOB re-bake of the game pool (map-shrink 2026-11-15).

    python packs/shrink_pool.py --src=<maps4 at default tiers> --game=<clone> [--deck-k=0.5] [--write] [CODES...]

Reads each map from --src (the baked maps at tiers 4 / 8 / 12 m = main's maps4), runs mb.shrink at --deck-k (default: the
kit knob OOZE_DECK_K), checks the rulebook before / after (only hard findings NEW after the shrink are reported as failures),
and with --write bakes it through mb.bake.write_game into <clone>/maps4 (+ thumbnail). Prints one row per map:
code, platforms, footprint before -> after, deck residual (max m), new hard findings, planner verify."""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from mb import bake, kit, rules, shrink  # noqa: E402

POOL = ("R-01 R-02 R-05 R-06 R-09 R-10 R-11 R-12 R-13 R-14 R-15 R-16 R-17 P-01 P-02 P-03 P-04 P-05 "
        "E-01 E-02 E-03 E-04 E-05 E-06 E-07 E-08 E-09 E-10 N-02 N-03 N-05 N-06 N-16 N-17 N-20 N-22 M-15").split()


PER_MAP = {"R-09": {"RELAY_HEAD": 0.4}}   # solver knobs that converge (R-09: the default 3.0 heading pull on relay decks breaks
                                          # its mirror; 0.4 bakes it clean). Bake 2026-11-15: lm, 6000 evaluations.


def hard(items):
    return sorted({(i["rule"], i["msg"]) for i in items if i["sev"] == "hard"})


def main(argv):
    opts = {a.split("=", 1)[0]: (a.split("=", 1) + [""])[1] for a in argv if a.startswith("--")}
    codes = [a for a in argv if not a.startswith("--")] or POOL
    k = float(opts.get("--deck-k") or kit.DECK_K)
    src, game = opts["--src"], opts.get("--game")
    out = []
    for c in codes:
        f = glob.glob(os.path.join(src, c + "-*.json"))[0]
        m0 = json.load(open(f, encoding="utf-8"))
        m0.pop("layout", None)
        shrink.RELAY_HEAD = PER_MAP.get(c, {}).get("RELAY_HEAD", float(os.environ.get("OOZE_SHRINK_RELAY_HEAD", "3.0")))
        m1, info = shrink.shrink(m0, k)
        h0, h1 = hard(rules.check(m0)), hard(rules.check(m1))
        new = [x for x in h1 if x not in h0]
        fp0, fp1 = shrink.footprint(m0), shrink.footprint(m1)
        plats = sum(1 for n in m0["nodes"] if not n.get("junction"))
        verify = None
        if "--write" in opts and game:
            verify = bake.write_game(m1, game, os.path.basename(f))
        row = {"code": c, "platforms": plats, "nodes": len(m0["nodes"]), "fp0": [round(v, 1) for v in fp0],
               "fp1": [round(v, 1) for v in fp1], "max_res": round(info["max_res"], 2), "max_dev": round(info.get("max_dev", 0), 2), "new_hard": new,
               "verify": verify}
        out.append(row)
        print("%s plats %2d  %5.1f x %4.1f -> %5.1f x %4.1f m  res %.2f  new hard %d %s %s" % (
            c, plats, fp0[0], fp0[1], fp1[0], fp1[1], info["max_res"], len(new),
            "; ".join("%s %s" % x for x in new)[:300], "" if verify is None else json.dumps(verify)[:200]), flush=True)
    if opts.get("--json"):
        json.dump(out, open(opts["--json"], "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:])
