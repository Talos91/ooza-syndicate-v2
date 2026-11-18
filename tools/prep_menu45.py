"""45-menu-parts-paint-B -> assets/ui/menu45: the remake's menu kit (geometry 45A2, PASS + locked; paint 45B).

    python tools/board_geo_diff.py --parts "<deliveries>/45-menu-parts-geometry-A2" "<deliveries>/45-menu-parts-paint-B"   (0 failures first)
    python tools/prep_menu45.py assets/ui/menu45

Copies the delivered 2x lossless parts (import-2x/parts, 1 px = 0.5 pt) as they are, writes parts.json trimmed to what the
game reads (family -> variant -> size_pt, slots_pt, slice_pt, states -> file + masks; points, top-left of the part's canvas)
and the header / nav art slots of 43B-pack-ARMIES at 2x (crest, currency glyphs, utility icons, nav inks). Geometry is never
edited here; Kit45 (scripts/kit45.gd) draws every part at its native size in points (stretch families 9-sliced)."""
import json, os, shutil, sys
from PIL import Image

DEL = r"H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/"
PAINT = DEL + "45-menu-parts-paint-B/"
OVER = DEL + "45-menu-parts-paint-B2/import-2x/parts/"   # 45B2: the SELECTED fix, same names, replaces 45B files (designer 11 PASS)
ARMIES = DEL + "43B-pack-ARMIES/parts/"
ART = ["FLUTED-TRIM", "BOLT", "OVERLORD-CREST", "CUR-1", "CUR-2", "ICON-SOUND", "ICON-SETTINGS", "ICON-HELP",
       "NAV-HOME-INK", "NAV-ARMIES-INK", "NAV-PROFILE-INK", "NAV-GUIDE-INK", "SEAT-LAMP"]
out = sys.argv[1]
os.makedirs(out + "/parts", exist_ok=True)
os.makedirs(out + "/art", exist_ok=True)
pj = json.load(open(PAINT + "parts.json", encoding="utf-8"))
sc = float(pj["scale"])                                  # 4 px per pt in the masters
fams = {}
used = set()
for name, p in pj["parts"].items():
    vs = {}
    for vn, v in p["variants"].items():
        st = {}
        for sn, s in v["states"].items():
            masks = {k: os.path.basename(f) for k, f in s.get("mask_files", {}).items()}
            st[sn] = {"file": os.path.basename(s["file"]), "masks": masks}
            used.add(os.path.basename(s["file"]))
            used.update(masks.values())
        slots = {k: [round(c / sc, 2) for c in r] for k, r in v.get("slots_px", {}).items()}
        e = {"size": v["size_pt"], "slots": slots, "states": st}
        sl = v.get("slice_px") or p.get("slice_px")
        if sl:
            e["slice"] = [c / sc for c in sl]            # left, top, right, bottom in pt
        vs[vn] = e
    fams[name] = {"mode": p["mode"], "variants": vs}
tot = 0
for f in sorted(used):
    src = OVER + f if os.path.exists(OVER + f) else PAINT + "import-2x/parts/" + f
    shutil.copyfile(src, out + "/parts/" + f)
    tot += os.path.getsize(out + "/parts/" + f)
for a in ART:
    im = Image.open(ARMIES + a + ".png").convert("RGBA")
    im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    im.save(out + "/art/" + a + ".png", optimize=True)
    tot += os.path.getsize(out + "/art/" + a + ".png")
json.dump({"revision": pj["revision"], "parts": fams}, open(out + "/parts.json", "w", encoding="utf-8"), indent=1)
print(f"{len(used)} parts + {len(ART)} art -> {out} ({tot / 1e6:.2f} MB)")
