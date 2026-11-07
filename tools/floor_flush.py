"""Make the lab floor's FLUSH derivative: the slabs of lab5_floor_2048.png meet without the dark grout lines
(Daniele 2026-11-07: "you mustn't see the space between them; it should read as one actual pavement").

The source has a regular grout grid: every 128 px (2 m at 64 px/m), 4 px of grout (#1C1C1C) at k*128-2 .. k*128+1 plus a
2 px bevel each side, wrapping at the tile's edge. For every line, the band k*128-6 .. k*128+5 is rebuilt from each
neighbouring slab's own pixels mirrored across the band edge (so grain, stains and tone stay the slab's), the two halves
meet over a 4 px blend at the joint, and a 1 px hairline marks the joint SEAM_DARK darker. Vertical lines first, then
horizontal ones on the result (so the crossings come from fixed pixels). Indexing wraps, so the tile stays seamless.
The original is never touched.

    python tools/floor_flush.py [src] [dst]
      default src assets/world/lab5_floor_2048.png -> dst assets/world/lab5_floor_2048_flush.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PITCH = 128        # px between grout lines (2 m)
HALF_L = 6         # band = [x0 - HALF_L, x0 + HALF_R]
HALF_R = 5
BLEND = 4          # px over which the two slabs meet
SEAM_DARK = 0.05   # the hairline: this much darker (<= 6 %)
SEAM_COL = -1      # the hairline's offset from k * PITCH (the grout's centre is at -0.5)


def flush_axis(a: np.ndarray) -> np.ndarray:
    """Rebuild every vertical grout band of a (H, W, 3 float); returns a new array."""
    out = a.copy()
    w = a.shape[1]
    lo = -HALF_L
    n = HALF_L + HALF_R + 1
    for x0 in range(0, w, PITCH):
        for j in range(n):
            x = x0 + lo + j
            xl = x0 + lo - 1 - j                     # mirrored across the band's left edge
            xr = x0 + HALF_R + 1 + (n - 1 - j)       # mirrored across the band's right edge
            c = (j + 0.5) - (n / 2.0)                # px from the band's middle
            t = np.clip(c / BLEND + 0.5, 0.0, 1.0)
            t = t * t * (3.0 - 2.0 * t)
            out[:, x % w] = a[:, xl % w] * (1.0 - t) + a[:, xr % w] * t
        out[:, (x0 + SEAM_COL) % w] *= 1.0 - SEAM_DARK
    return out


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "assets/world/lab5_floor_2048.png"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "assets/world/lab5_floor_2048_flush.png"
    if src.resolve() == dst.resolve():
        raise SystemExit("refusing to overwrite the original")
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float64)
    a = flush_axis(a)                                       # vertical lines
    a = flush_axis(a.transpose(1, 0, 2)).transpose(1, 0, 2)  # horizontal lines
    Image.fromarray(np.clip(np.rint(a), 0, 255).astype(np.uint8)).save(dst, optimize=True)
    # report: the darkest line profile left (column / row means vs the median), the wrap seam
    L = a.mean(2)
    for name, prof in (("cols", L.mean(0)), ("rows", L.mean(1))):
        med = float(np.median(prof))
        print("%s: darkest line %.1f %% below the median" % (name, 100.0 * (1.0 - prof.min() / med)))
    print("wrap: |col0-col2047| %.2f, |row0-row2047| %.2f (neighbouring columns differ by %.2f)" % (
        np.abs(L[:, 0] - L[:, -1]).mean(), np.abs(L[0] - L[-1]).mean(), np.abs(L[:, 500] - L[:, 501]).mean()))
    print("wrote", dst)


if __name__ == "__main__":
    main()
