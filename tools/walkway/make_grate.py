"""Walkway grating texture (Daniele 2026-11-13: walkways were the bridges' ivory; designer 4: darker sage-grey grating).
128 px = 1 m (the material's world triplanar scale); a square grate every 25 cm, lines 5 px. Writes assets/world/walkway/walkway_grate.png."""
import sys
from pathlib import Path
from PIL import Image
BASE = (0x8E, 0x9F, 0x98)
LINE = (0x5F, 0x71, 0x6B)
N, STEP, W = 128, 32, 5
img = Image.new("RGB", (N, N), BASE)
px = img.load()
for y in range(N):
    for x in range(N):
        if x % STEP < W or y % STEP < W:
            px[x, y] = LINE
out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/world/walkway/walkway_grate.png")
img.save(out)
print(out, img.size)
