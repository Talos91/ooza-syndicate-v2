"""One labelled contact sheet per group (1-terrain, 2-backdrops, 3-mixed) from the full 1280x720 frames."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
G = Path(r"H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/generated/terrain-backdrop-shots-2026-11-10")
TW, TH, COLS, LAB = 640, 360, 4, 34
try:
    FONT = ImageFont.truetype("arialbd.ttf", 22); TFONT = ImageFont.truetype("arialbd.ttf", 30)
except OSError:
    FONT = TFONT = ImageFont.load_default()
TITLES = {"1-terrain": "TERRAIN SETS on R-01 STRAIT, backdrop = current LAB-SIDE B (desktop 1280x720, 6 s in)",
          "2-backdrops": "BACKGROUNDS on R-01 STRAIT, floor = current R16 lab tile (desktop 1280x720, 6 s in)",
          "3-mixed": "MIXED floor + background pairs (M) and deliberate contrasts (C), R-01 STRAIT"}
for grp, title in TITLES.items():
    files = sorted((G / grp).glob("*.png"))
    rows = (len(files) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * TW, 50 + rows * (TH + LAB)), (16, 18, 24))
    d = ImageDraw.Draw(sheet)
    d.text((12, 10), title, fill=(235, 235, 240), font=TFONT)
    for i, f in enumerate(files):
        x, y = (i % COLS) * TW, 50 + (i // COLS) * (TH + LAB)
        sheet.paste(Image.open(f).convert("RGB").resize((TW - 6, TH - 4), Image.LANCZOS), (x + 3, y + 2))
        d.text((x + 8, y + TH + 4), f.stem, fill=(120, 230, 160) if f.stem.startswith("C") and grp == "3-mixed" and "CONTRAST" in f.stem else (235, 235, 240), font=FONT)
    out = G / f"SHEET-{grp}.png"
    sheet.save(out, optimize=True)
    print(out, len(files), sheet.size)
