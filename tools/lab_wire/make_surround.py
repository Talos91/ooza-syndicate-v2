"""lab-wire (2026-11-12): web-size derivatives of the 26B2 lab surround for the lab look.
Sources (untouched): References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/26B2-lab-surround/
SURROUND-PHONE-WALLS.png (3248x1500) / SURROUND-WIDE-WALLS.png (3840x2160): RGBA, floor + #FF00FF hole already keyed out
(UI designer 4 team note: use the -WALLS files). If a source has no alpha, the pure #FF00FF hole is keyed here.
Edge: alpha feathered ~4 px (source px) by a box blur of the key, so the 3D TILE-LAB floor blends into the wall base.
Usage: python make_surround.py <src dir> <out dir>"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
JOBS = [("SURROUND-PHONE-WALLS.png", "SURROUND-PHONE.png", "lab_surround_phone.png", (2436, 1125)),
        ("SURROUND-WIDE-WALLS.png", "SURROUND-WIDE.png", "lab_surround_wide.png", (2560, 1440))]
for walls, plain, out, size in JOBS:
    p = os.path.join(SRC, walls if os.path.exists(os.path.join(SRC, walls)) else plain)
    im = Image.open(p)
    a = np.array(im.convert("RGBA"))
    if im.mode != "RGBA":
        key = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
        a[..., 3] = np.where(key, 0, 255)
    al = Image.fromarray(a[..., 3])
    hard = np.array(al) > 127
    soft = np.array(Image.fromarray((hard * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(2)))   # 5 px box = ~4 px feather
    a[..., 3] = np.minimum(np.array(al), soft)          # feather only inward, never re-open keyed pixels
    rgb = a[..., :3].astype(np.float32)
    w = a[..., 3:4].astype(np.float32) / 255.0          # bleed colour under transparent pixels (no magenta fringe on resample)
    blur = np.array(Image.fromarray(a[..., :3]).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
    a[..., :3] = np.where(w > 0.01, rgb, blur).astype(np.uint8)
    mag = (a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240) & (a[..., 3] > 0)
    o = Image.fromarray(a, "RGBA").resize(size, Image.LANCZOS)
    o.save(os.path.join(OUT, out), optimize=True)
    oa = np.array(o)[..., 3]
    print(f"{os.path.basename(p)} {im.size} {im.mode} -> {out} {size}: alpha0 {(oa == 0).mean():.3f} partial {((oa > 0) & (oa < 255)).mean():.4f} "
          f"visible magenta px {int(mag.sum())} bytes {os.path.getsize(os.path.join(OUT, out))}")
