# sheet.py: rows = baseline / A / B / C, columns = R-01 0:05, 1:40, 4:05 + E-01 1:40 (all with the top-band fix)
import sys, glob
from PIL import Image, ImageDraw, ImageFont
OUT = sys.argv[1]
SRC = "C:/Users/itisf/ooze-wt/calm-pass-out/shots"
rows = [("base", "BASELINE 0.24.1"), ("a", "A  world only"), ("b", "B  A + label diet"), ("c", "C  B + colour discipline")]
cols = [("R-01_t5", "R-01 STRAIT 0:05"), ("R-01_t100", "R-01 STRAIT 1:40"), ("R-01_t245", "R-01 STRAIT 4:05 (Last Stand)"), ("E-01_t100", "E-01 SPIRAL 1:40")]
W, H, LW, TH = 812, 375, 190, 34
try:
    f = ImageFont.truetype("arialbd.ttf", 22); fs = ImageFont.truetype("arial.ttf", 15)
except Exception:
    f = fs = ImageFont.load_default()
sheet = Image.new("RGB", (LW + W * len(cols) + 6 * len(cols), TH + (H + 6) * len(rows) + 30), (18, 18, 22))
d = ImageDraw.Draw(sheet)
for j, (c, ct) in enumerate(cols):
    d.text((LW + j * (W + 6) + 8, 6), ct, fill=(230, 230, 235), font=f)
for i, (r, rt) in enumerate(rows):
    y = TH + i * (H + 6)
    d.text((10, y + H // 2 - 30), rt.split("  ")[0], fill=(255, 255, 255), font=ImageFont.truetype("arialbd.ttf", 40) if r != "base" else f)
    if "  " in rt:
        d.text((10, y + H // 2 + 20), rt.split("  ")[1], fill=(200, 200, 205), font=fs)
    for j, (c, ct) in enumerate(cols):
        p = glob.glob(f"{SRC}/{r}/{c}/*.png")
        if p:
            sheet.paste(Image.open(p[0]).convert("RGB").resize((W, H)), (LW + j * (W + 6), y))
d.text((10, sheet.height - 24), "calm-pass 2026-11-12 - 812x375 --mobile desktop emulation (not a phone), AI vs AI seed 7, same moment per column; every row has the top-band fix. Dev flag --calm=a|b|c", fill=(160, 160, 165), font=fs)
sheet.save(OUT)
print(sheet.size)
