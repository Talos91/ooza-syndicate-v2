"""PITS / TUBES capture sheet (dev tool): tests/pits_tubes_shots.tscn frames -> one labelled PNG.

    python tools/pits_tubes_sheet.py <shots dir> <out png> [<plan png>]

Panels (812x375 game-size frames, landscape phone): start (game camera), a pit's match-start column, home column foot
T1 (1 tube), T2 being built (new tube empty), after T2 (2 tubes), after T3 (4 tubes, foot + game camera), mixed pit
(seat A T3 + seat B T3 into one pit), plus an optional top-down plan of every potential tube (the clipping probe's dump).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PANELS = [
    ("a-start-game.png", "START - game camera, 4 pits"),
    ("a-start-pit0.png", "R6 - a pit's match-start column of Locals"),
    ("a-home-foot.png", "HOME T1 - 1 tube (pit -> column)"),
    ("b-t2-build-foot.png", "T1 -> T2 building - new tube EMPTY (R4)"),
    ("b-t2-foot.png", "after T2 - 2 tubes, 4 doors + 4 sockets"),
    ("c-t3-foot.png", "after T3 - 4 tubes"),
    ("c-t3-game.png", "after T3 - game camera"),
    ("d-mixed-pit.png", "MIXED PIT - A (T3) + B (T3) into one pit (R7)"),
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
        cells.append((plan, "PLAN - every potential tube (T3 max), R-01; clip probe 0 hits"))
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
    d.text((PAD, 10), "PITS / TUBES / COLUMNS v1 - R-01 STRAIT, 812x375 (landscape phone size, desktop window, off-screen)",
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
