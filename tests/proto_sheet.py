"""RELAYS 3.0 PROTOTYPES: lay tests/proto_shots.gd's shots out as one contact sheet (rows = kinds, columns = before /
warning / after).  python tests/proto_sheet.py <shots dir> [out.png]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

KINDS = ["ferry", "conveyor", "launcher", "lift", "tilt", "switch"]
COLS = ["1-before", "2-warning", "3-after"]
d = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "relays-proto-contact.png")
W, PAD, LBL = 640, 8, 34
rows = [k for k in KINDS if os.path.exists(os.path.join(d, f"{k}-1-before.png"))]
first = Image.open(os.path.join(d, f"{rows[0]}-1-before.png"))
H = int(first.height * W / first.width)
sheet = Image.new("RGB", (PAD + 3 * (W + PAD), LBL + len(rows) * (H + LBL + PAD)), (14, 14, 20))
dr = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("arial.ttf", 22)
except OSError:
    font = ImageFont.load_default()
for c, col in enumerate(COLS):
    dr.text((PAD + c * (W + PAD) + 6, 6), col.split("-", 1)[1].upper(), fill=(230, 230, 240), font=font)
for r, k in enumerate(rows):
    y = LBL + r * (H + LBL + PAD)
    dr.text((PAD + 6, y + 4), k.upper(), fill=(255, 210, 63), font=font)
    for c, col in enumerate(COLS):
        p = os.path.join(d, f"{k}-{col}.png")
        if os.path.exists(p):
            sheet.paste(Image.open(p).convert("RGB").resize((W, H)), (PAD + c * (W + PAD), y + LBL))
sheet.save(out)
print(out)
