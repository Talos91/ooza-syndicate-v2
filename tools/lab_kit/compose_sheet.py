"""Compose the lab kit contact sheet from sheet_lab_kit.py tiles: 5 columns, slate-teal floor cue behind each tile.
python compose_sheet.py <sheet dir> <out png>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
S, OUTP = sys.argv[1], sys.argv[2]
rows = [l.split("\t") for l in open(os.path.join(S, "tiles.txt"), encoding="utf-8").read().splitlines()]
TW, TH, LH, COLS, PAD = 640, 480, 34, 5, 12
n = len(rows); R = (n + COLS - 1) // COLS
HEAD = 90
W, H = COLS * (TW + PAD) + PAD, HEAD + R * (TH + LH + PAD) + PAD + 40
sheet = Image.new("RGB", (W, H), "#F2F3EE")
d = ImageDraw.Draw(sheet)
def font(sz):
    for f in ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()
d.text((PAD, 14), "Ooze Syndicate 2.0 - production LAB KIT (branch lab-kit, assets/kit/labkit/)", fill="#1E3A3C", font=font(34))
d.text((PAD, 56), "26S zones + lab2 values (decks #E2CFAE, walkways #EAD9BC, satin 0.8, no metal). Fixes: owner rim 0.5 m band; vat goo dense + clear lower glass. Silhouettes = today's kit. Eevee render, 54 deg pitch, 25 deg turn; floor cue #2F4D4E.", fill="#3D5758", font=font(17))
for i, (fn, label) in enumerate(rows):
    r, c = divmod(i, COLS)
    x, y = PAD + c * (TW + PAD), HEAD + r * (TH + LH + PAD)
    bg = Image.new("RGBA", (TW, TH), "#2F4D4E")
    t = Image.open(os.path.join(S, "tiles", fn)).convert("RGBA")
    bg.alpha_composite(t)
    sheet.paste(bg.convert("RGB"), (x, y))
    d.text((x + 4, y + TH + 4), label, fill="#1E3A3C", font=font(22))
d.text((PAD, H - 34), "Neon samples cyan #00E5FF / red-magenta #FF2B6A; goo VEX #2E86AE EMBER #E76A1E SOLAR #E4B14E BLOOM #8ABF35 NULL #C02263 (MATERIALS.md). Low-fill tiles cut each tank's goo at 25 %.", fill="#3D5758", font=font(17))
sheet.save(OUTP)
print(OUTP, sheet.size)
