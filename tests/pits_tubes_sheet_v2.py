"""PITS / TUBES v2 capture sheet (Daniele's 3 corrections, 2026-11-09): symmetric pits, ordered fan-in, build hologram.
    python tests/pits_tubes_sheet_v2.py <shots dir (tests/pits_tubes_shots.tscn out=)> <out png> [<plan png>]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PANELS = [
    ("z-top-down.png", "1  PITS - whole map straight down: 4 pits mirror L/R + T/B"),
    ("f-fan-pit.png", "2  FAN-IN - every column of a pit at T3: ribbons -> header -> riser"),
    ("c-t3-game.png", "after T3 - game camera"),
    ("e-build-1.png", "3  BUILD 16% - hologram ghost, tube revealed from the column"),
    ("e-build-2.png", "3  BUILD 41%"),
    ("e-build-3.png", "3  BUILD 71%"),
    ("e-build-4.png", "3  BUILD 96% - then the goo fills pit -> column"),
    ("b-t2-foot.png", "after T2 - 2 tubes on stands, sockets + doors"),
    ("d-mixed-pit.png", "MIXED PIT - A + B tubes into one header"),
]
W, H = 812, 375
PAD = 10
LABEL = 26


def main() -> None:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    plan = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    cells = [(src / f, t) for f, t in PANELS if (src / f).exists()]
    if plan and plan.exists():
        cells.append((plan, "PLAN - pit 0, every potential tube; clip probe 0 on 14 maps"))
    cols = 3
    rows = (len(cells) + cols - 1) // cols
    head = 44
    sheet = Image.new("RGB", (cols * (W + PAD) + PAD, head + rows * (H + LABEL + PAD) + PAD), (18, 20, 24))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arialbd.ttf", 18)
        big = ImageFont.truetype("arialbd.ttf", 24)
    except OSError:
        font = big = ImageFont.load_default()
    d.text((PAD, 10), "PITS / TUBES v2 - R-01 STRAIT, 812x375 (landscape phone size, desktop window, off-screen)",
           fill=(230, 235, 240), font=big)
    for n, (path, title) in enumerate(cells):
        cx = PAD + (n % cols) * (W + PAD)
        cy = head + (n // cols) * (H + LABEL + PAD)
        img = Image.open(path).convert("RGB")
        if img.size != (W, H):
            img.thumbnail((W, H))
            canvas = Image.new("RGB", (W, H), (255, 255, 255))
            canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
            img = canvas
        d.text((cx, cy + 3), title, fill=(120, 230, 255), font=font)
        sheet.paste(img, (cx, cy + LABEL))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print("sheet", out, sheet.size)


if __name__ == "__main__":
    main()
