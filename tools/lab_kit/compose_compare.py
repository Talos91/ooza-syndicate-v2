"""Compare sheet: the 8 vat tiles of the base kit next to a variant. Rows T1-T4; columns base full | variant full | base 25 % | variant 25 %.
python compose_compare.py <base tiles dir> <variant tiles dir> <base label> <variant label> <out png>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
A, B, LA, LB, OUTP = sys.argv[1:6]
base = [l.split("\t") for l in open(os.path.join(A, "..", "tiles.txt"), encoding="utf-8").read().splitlines()]
var = [l.split("\t") for l in open(os.path.join(B, "..", "tiles.txt"), encoding="utf-8").read().splitlines()]
bv = {lab: fn for fn, lab in base if lab.startswith("Vat_")}
vv = {lab: fn for fn, lab in var}
TW, TH, PAD, HEAD, LH = 640, 480, 12, 120, 30
def font(sz):
    for f in ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()
W, H = 4 * (TW + PAD) + PAD, HEAD + 4 * (TH + LH + PAD) + PAD
sheet = Image.new("RGB", (W, H), "#F2F3EE"); d = ImageDraw.Draw(sheet)
d.text((PAD, 12), "Lab kit vats - caps compare", fill="#1E3A3C", font=font(34))
cols = [(A, bv, "full", LA), (B, vv, "full", LB), (A, bv, "25 % fill", LA), (B, vv, "25 % fill", LB)]
for c, (_, _, fill, lab) in enumerate(cols):
    d.text((PAD + c * (TW + PAD), 64), "%s - %s" % (lab, fill), fill="#1E3A3C", font=font(24))
for r in range(4):
    for c, (dirp, m, fill, lab) in enumerate(cols):
        key = "Vat_T%d - %s" % (r + 1, fill)
        x, y = PAD + c * (TW + PAD), HEAD + r * (TH + LH + PAD)
        bg = Image.new("RGBA", (TW, TH), "#2F4D4E"); bg.alpha_composite(Image.open(os.path.join(dirp, m[key])).convert("RGBA"))
        sheet.paste(bg.convert("RGB"), (x, y)); d.text((x + 4, y + TH + 2), key, fill="#1E3A3C", font=font(20))
sheet.save(OUTP); print(OUTP, sheet.size)
