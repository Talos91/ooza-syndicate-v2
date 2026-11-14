"""Widen the v4 tint mask's neon (R channel) so the owner colour reads at the game camera.
New files only: assets/units/<faction>_tint_w.png beside the untouched <faction>_tint.png (same UVs, G = eye glow kept).
usage: python tools/units/widen_tint.py [px]   (px = dilation radius at 1024, default 6)"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

px = int(sys.argv[1]) if len(sys.argv) > 1 else 6
yy, xx = np.ogrid[-px:px + 1, -px:px + 1]
disc = (xx * xx + yy * yy) <= px * px
for f in ["vex", "null", "bloom", "ember", "solar"]:
    a = np.array(Image.open(f"assets/units/{f}_tint.png").convert("RGB"))
    r = a[..., 0]
    grown = ndimage.grey_dilation(r, footprint=disc)
    b = a.copy()
    b[..., 0] = np.maximum(r, grown)
    Image.fromarray(b).save(f"assets/units/{f}_tint_w.png")
    print(f, "neon texels", int((r > 128).sum()), "->", int((b[..., 0] > 128).sum()))
