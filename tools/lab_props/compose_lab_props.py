"""SHEET-lab-props-31A.png: the director's LINEUP.png | Blender render at the locked metres | the same props x2.05.
Run: python compose_lab_props.py <LINEUP.png> <render-x1.png> <render-x2.05.png> <props.txt> <out.png>"""
import sys
from PIL import Image, ImageDraw, ImageFont

LINE, R1, R2, TXT, OUT = sys.argv[1:6]


def font(n):
    for f in ("arialbd.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, n)
        except OSError:
            pass
    return ImageFont.load_default()


def crop(p):
    im = Image.open(p).convert("RGB")
    g = im.convert("L").point(lambda v: 255 if v > 150 else 0)   # ivory parts; the floor cue and background stay below
    x0, y0, x1, y1 = g.getbbox()
    m = 70
    return im.crop((max(0, x0 - m), max(0, y0 - m), min(im.width, x1 + m), min(im.height, y1 + m)))


H = 1100
panels = [("Director LINEUP.png (locked STEP A; 0.6 m unit, 6 m node)", Image.open(LINE).convert("RGB")),
          ("Blender GLBs at the locked metres, game camera 54 deg / 25 deg; real kit node 12.3 m, VEX unit 1.3 m", crop(R1)),
          ("Same GLBs x2.05 (the director's 6 m node ratio on the real 12.3 m node): placement scale only", crop(R2))]
panels = [(t, im.resize((round(im.width * H / im.height), H), Image.LANCZOS)) for t, im in panels]
rows = [l.split("\t") for l in open(TXT).read().strip().splitlines()[1:]]
PAD, TOP = 30, 120
W = max(sum(im.width for _, im in panels[1:]) + PAD * 3, panels[0][1].width + 900)
sheet = Image.new("RGB", (W, TOP + H * 2 + PAD * 4 + 60), "#F3EEE4")
d = ImageDraw.Draw(sheet)
d.text((PAD, 24), "Round 31 lab props - Blender GLBs from the locked STEP A (15 meshes, %d tris total, max %d, 1 shared 512 px atlas + 256 px foliage)" % (
    sum(int(r[1]) for r in rows), max(int(r[1]) for r in rows)), fill="#3D5758", font=font(34))
d.text((PAD, 72), "No lights (lamp lens emissive only). BVH overlaps 0, non-manifold 0 on the exported GLBs. Colours = lab kit (#E2CFAE / #718A83 / #3D5758, glass #AECAC7, white goo mask).",
       fill="#3D5758", font=font(22))
x, y = PAD, TOP
t, im = panels[0]
sheet.paste(im, (x, y + 40))
d.text((x, y), t, fill="#3D5758", font=font(26))
tx = x + im.width + PAD * 2
d.text((tx, y), "tris per mesh (guide)", fill="#3D5758", font=font(26))
for i, r in enumerate(rows):
    d.text((tx, y + 50 + i * 40), "%-18s %4s  (%s)  %s KB" % (r[0], r[1], r[2], round(int(r[3]) / 1024)), fill="#3D5758", font=font(24))
y += H + PAD * 2 + 40
for t, im in panels[1:]:
    d.text((x, y), t, fill="#3D5758", font=font(24))
    sheet.paste(im, (x, y + 40))
    x += im.width + PAD
sheet.save(OUT)
print(OUT, sheet.size)
