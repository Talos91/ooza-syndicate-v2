"""Assemble one 4 x 4 (64 m) floor block per terrain set for the terrain-backdrop-shots debug flag (--floor-tex=).
Derivative only: reads the delivery tiles, writes 2048 px (32 px/m) RGB PNGs. Layout = main ground ~60 % + a lane / path
column ending at a cross trench / path row + a few detail tiles; every connector matches (also across the wrap)."""
import json, sys
from pathlib import Path
from PIL import Image

D = Path(r"H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries")
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else r"C:/Users/itisf/ooze-wt/terrain-shots-tools/floors")
OUT.mkdir(parents=True, exist_ok=True)
T = 512   # px per 16 m tile in the output (2048 / 4)

# (piece, clockwise rotation); rows north -> south
KIT7 = [[("P01", 0), ("P10", 0), ("P02", 0), ("P05", 0)],
        [("P03", 0), ("P12", 0), ("P01", 90), ("P04", 0)],
        [("P06", 90), ("P06", 90), ("P06", 90), ("P06", 90)],
        [("P02", 90), ("P12", 180), ("P03", 0), ("P01", 180)]]
KIT8 = [[("P01", 0), ("P10", 0), ("P02", 0), ("P21", 0)],
        [("P20", 0), ("P12", 0), ("P01", 90), ("P22", 0)],
        [("P06", 90), ("P06", 90), ("P06", 90), ("P06", 90)],
        [("P23", 0), ("P12", 180), ("P03", 0), ("P01", 180)]]
FLAT9 = [[("F01", 0), ("F05", 0), ("F01", 90), ("F10", 180)],
         [("F03", 0), ("F05", 0), ("F02", 0), ("F10", 0)],
         [("F05", 90), ("F13", 0), ("F05", 90), ("F05", 90)],
         [("F12", 0), ("F07", 180), ("F04", 0), ("F01", 180)]]

def piece(folder, code):
    return next(folder.glob(code + "-*.png"))

def build(folder, grid, name):
    im = Image.new("RGB", (4 * T, 4 * T))
    used = []
    for r, row in enumerate(grid):
        for c, (code, cw) in enumerate(row):
            f = piece(folder, code)
            t = Image.open(f).convert("RGBA")
            bg = Image.new("RGBA", t.size, (0, 0, 0, 255))
            t = Image.alpha_composite(bg, t).convert("RGB").resize((T, T), Image.LANCZOS)
            if cw:
                t = t.rotate(-cw, expand=False)       # PIL rotates counter-clockwise
            im.paste(t, (c * T, r * T))
            used.append(f"{code}@{cw}")
    p = OUT / (name + ".png")
    im.save(p, optimize=True)
    print(name, p, " ".join(used))
    return p

def check_conn():
    c = json.load(open(D / "round-7-terrain-textures-v2/connectors.json"))
    for k in ("P10", "P12", "P06"):
        key = next(x for x in c if x.startswith(k))
        print(k, [(e["rotation_cw"], [s["side"] for s in e["connectors"]]) for e in c[key]])

if __name__ == "__main__":
    check_conn()
    for w in ("lab", "sewer", "factory"):
        build(D / "round-7-terrain-textures-v2" / w, KIT7, f"r7v2-{w}")
    for w in ("lab", "sewer", "factory", "forest", "cyber_city", "cartoon_factory"):
        build(D / "round-8-expanded-terrain" / w, KIT8, f"r8-{w}")
    for w in ("lab", "sewer", "factory", "forest", "cyber_city"):
        build(D / "round-9-flat-ground" / w, FLAT9, f"r9-{w}")
