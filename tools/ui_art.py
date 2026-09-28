"""Alpha 21 UI pass: game-sized derivatives of Daniele's approved UI art (the originals stay untouched).

    python tools/ui_art.py            (from Game/2.0; needs Pillow)

Sources (Daniele's Art Direction folder, "Alpha 20 UI Expansion" / ASSET-SOURCES.json):
  - the five faction characters, Alpha 12/references/<faction>.png  -> assets/art/ui/hero_<faction>.png
    (transparent cutouts, 768 px; SOLAR's dark backdrop is keyed out)
  - the menu environments, Alpha 20 UX/assets/...                   -> assets/art/ui/bg_<faction>.jpg (1600 px)
  - the VEX campaign mission art, campaign-isometric-v2/*.png       -> assets/art/campaign/vex-<id>.jpg (1280 px)
JPEG for the opaque plates keeps the source small; their .import files are LOSSY (quality 0.8) with a size limit
(backdrops 1600, mission art 1024, cutouts 640), or Godot stores them lossless and the web index.pck grows ~20 MB.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

ART = os.path.expanduser(r"~/OneDrive/Documenti/ChatGPT/Ooze Syndicate/Art Direction")
REFS = os.path.join(ART, "Alpha 12", "references")
UX = os.path.join(ART, "Alpha 20 UX", "assets")
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_UI = os.path.join(HERE, "assets", "art", "ui")
OUT_CAMP = os.path.join(HERE, "assets", "art", "campaign")

BACKGROUNDS = {
    "vex": os.path.join(UX, "dockside-menu-v2.png"),
    "null": os.path.join(UX, "backgrounds-set-02", "null-blackglass-exchange-v1.png"),
    "bloom": os.path.join(UX, "backgrounds-set-02", "viridian-culture-gardens-v1.png"),
    "ember": os.path.join(UX, "backgrounds-set-02", "ember-cinderworks-v1.png"),
    "solar": os.path.join(UX, "backgrounds-set-02", "solar-helios-bastion-v1.png"),
}


def key_out_dark(im: Image.Image, tol: int = 22) -> Image.Image:
    """A flat dark backdrop -> transparent: flood from the border over near-backdrop pixels, feathered."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    mask = Image.new("L", (w, h), 0)
    px = rgb.load()
    mp = mask.load()
    bg = px[0, 0]
    stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    while stack:
        x, y = stack.pop()
        if mp[x, y]:
            continue
        r, g, b = px[x, y]
        if abs(r - bg[0]) > tol or abs(g - bg[1]) > tol or abs(b - bg[2]) > tol:
            continue
        mp[x, y] = 255
        if x > 0: stack.append((x - 1, y))
        if x < w - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < h - 1: stack.append((x, y + 1))
    alpha = Image.eval(mask.filter(ImageFilter.GaussianBlur(1.5)), lambda v: 255 - v)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def fade_dark_fringe(im: Image.Image, lo: int = 34, hi: int = 58) -> Image.Image:
    """The originals carry a near-black halo + drop shadow from their old backdrop: invisible on the dark menus, a dark
    band over bright art (mission results). Fade the near-black pixels CONNECTED TO THE OUTSIDE (a flood from the border
    through transparent / near-black pixels), ramping back to full by `hi` - so the creatures' own dark parts (pupils,
    EMBER's rocks, NULL's body), enclosed by their bright outline, are never touched."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    while stack:
        x, y = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        r, g, b, a = px[x, y]
        m = max(r, g, b)
        if a > 8 and m >= hi:
            continue                                  # the creature's lit edge: the flood stops here
        seen[i] = 1
        if a > 0:
            k = 0.0 if m <= lo else (m - lo) / float(hi - lo)
            px[x, y] = (r, g, b, int(a * k))
        if x > 0: stack.append((x - 1, y))
        if x < w - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < h - 1: stack.append((x, y + 1))
    return im


def fit(im: Image.Image, width: int) -> Image.Image:
    if im.width <= width:
        return im
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def main() -> int:
    os.makedirs(OUT_UI, exist_ok=True)
    os.makedirs(OUT_CAMP, exist_ok=True)
    for f in ["vex", "null", "bloom", "ember", "solar"]:
        im = Image.open(os.path.join(REFS, f + ".png"))
        im = im.convert("RGBA") if im.mode == "RGBA" else key_out_dark(im)
        if f != "null":                              # NULL's own dark body reaches its lower edge: the flood would eat it
            im = fade_dark_fringe(im)
        im = im.crop(im.getbbox())                   # trim the empty margin: the pages place the art themselves
        side = max(im.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, side - im.height))   # standing on the square's floor
        fit(sq, 768).save(os.path.join(OUT_UI, "hero_%s.png" % f), optimize=True)
        fit(Image.open(BACKGROUNDS[f]).convert("RGB"), 1600).save(os.path.join(OUT_UI, "bg_%s.jpg" % f), quality=84)
    camp = os.path.join(UX, "campaign-isometric-v2")
    for name in sorted(os.listdir(camp)):
        if not name.endswith("-v2.png"):
            continue
        mission = name.split("-")[0]                  # "01" .. "10", "s1" ..
        fit(Image.open(os.path.join(camp, name)).convert("RGB"), 1280).save(
            os.path.join(OUT_CAMP, "vex-%s.jpg" % mission), quality=82)
    for d in (OUT_UI, OUT_CAMP):
        total = sum(os.path.getsize(os.path.join(d, n)) for n in os.listdir(d))
        print(d, len(os.listdir(d)), "files", total // 1024, "KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
