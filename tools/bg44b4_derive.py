"""Round 44 B4 match background -> game derivatives (2x of the 812x375 pt reference, the originals stay untouched).

Source (approved, immutable): References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/44-background-B4/
Output: assets/art/bg44b4/  (crust / rim / goo tile / near + mounts) + layout.json (pt placement, read by scripts/pit_backdrop.gd)
  - 4x -> 2x (1624x750 px canvas), LANCZOS.
  - PIT-FLOOR is not shipped: the screen draws the goo tile repeated (period 395 x 258 pt, layout.json pit.floor_tile_period).
  - PIT-RIM is cropped to its alpha box (90 % of it is empty).
  - TILE SEAM: PIT-FLOOR-TILE.png repeats its first column as its last column (and its first row as its last row), so a
    tiled copy shows that column twice = a 1 px line. The derivative drops the last column and the last row (1023 x 1023 =
    the true period), then resamples with wrap (3 x 3 copies, resize, crop the centre) so the edges stay continuous.
Run: python -I tools/bg44b4_derive.py "<delivery folder>"
"""
import json, os, sys
from PIL import Image
import numpy as np

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "bg44b4")
os.makedirs(OUT, exist_ok=True)
L = json.load(open(os.path.join(SRC, "layout.json")))
SC = L["canvas"]["scale"]           # 4 px per pt
K = 2                               # shipped px per pt
r = SC // K

def half(im):
    return im.resize((max(1, round(im.width / r)), max(1, round(im.height / r))), Image.LANCZOS)

def save(im, name):
    p = os.path.join(OUT, name)
    im.save(p, optimize=True)
    return p

out = {"schema": "ooze-bg44b4-game-1", "source": "44-background-B4", "ref_pt": [L["canvas"]["phone_w"], L["canvas"]["phone_h"]],
       "px_per_pt": K, "elements": {}}
# crust: full canvas
crust = half(Image.open(os.path.join(SRC, "CRUST.png")).convert("RGBA"))
save(crust, "crust.png")
out["elements"]["crust"] = {"file": "crust.png", "pt": [0, 0, L["canvas"]["phone_w"], L["canvas"]["phone_h"]]}
# rim: crop to the alpha box (4x px, rounded out to whole 4x px multiples of r)
rim = Image.open(os.path.join(SRC, "PIT-RIM.png")).convert("RGBA")
a = np.array(rim)[..., 3]
ys, xs = np.nonzero(a > 0)
x0, y0 = (xs.min() // r) * r, (ys.min() // r) * r
x1, y1 = -(-(xs.max() + 1) // r) * r, -(-(ys.max() + 1) // r) * r
save(half(rim.crop((x0, y0, x1, y1))), "rim.png")
out["elements"]["rim"] = {"file": "rim.png", "pt": [x0 / SC, y0 / SC, (x1 - x0) / SC, (y1 - y0) / SC]}
# goo tile: seam fix + wrap resample to the 2x period
t = Image.open(os.path.join(SRC, "PIT-FLOOR-TILE.png")).convert("RGB")
ta = np.array(t)
assert (ta[:, 0] == ta[:, -1]).all() and (ta[0] == ta[-1]).all(), "seam: expected col 0 == last col and row 0 == last row"
core = Image.fromarray(ta[:-1, :-1])
per = L["pit"]["floor_tile_period_at_reference_pt"]
tw, th = round(per[0] * K), round(per[1] * K)
big = Image.fromarray(np.tile(np.array(core), (3, 3, 1)))
big = big.resize((tw * 3, th * 3), Image.LANCZOS).crop((tw, th, tw * 2, th * 2))
save(big, "goo_tile.png")
b = np.array(big).astype(int)
out["tile_seam"] = {"source_col0_eq_last": True, "source_row0_eq_last": True, "fix": "dropped last col + last row (1023x1023 period), wrap resample",
                    "derivative_wrap_step_col": round(float(np.abs(b[:, 0] - b[:, -1]).mean()), 3), "derivative_mean_step_col": round(float(np.abs(b[:, 1:] - b[:, :-1]).mean()), 3),
                    "derivative_wrap_step_row": round(float(np.abs(b[0] - b[-1]).mean()), 3), "derivative_mean_step_row": round(float(np.abs(b[1:] - b[:-1]).mean()), 3)}
out["elements"]["goo_tile"] = {"file": "goo_tile.png", "period_pt": per, "anchor_pt": L["widths"]["reference_812"]["pit_stadium"]["center_pt"]}
# fixtures (the HUD backings)
for e in L["elements"] + L.get("conditional_elements", []):
    if (e["id"].startswith("NEAR-") or e["id"].startswith("MOUNT-")):
        name = e["id"].lower().replace("-", "_") + ".png"
        save(half(Image.open(os.path.join(SRC, e["file"])).convert("RGBA")), name)
        out["elements"][e["id"]] = {"file": name, "pt": [e["x"] / SC, e["y"] / SC, e["w"] / SC, e["h"] / SC], "anchor": e["anchor"]}
out["pit_stadium_pt"] = L["widths"]["reference_812"]["pit_stadium"]
json.dump(out, open(os.path.join(OUT, "layout.json"), "w"), indent=1)
tot = 0
for f in sorted(os.listdir(OUT)):
    s = os.path.getsize(os.path.join(OUT, f)); tot += s
    print(f, s)
print("total", tot)
print(json.dumps(out["tile_seam"]))
