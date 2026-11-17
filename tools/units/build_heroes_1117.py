"""Unit pictures + AI screens from Daniele's 2026-11-17 2D sets (originals only read):
  ooze-heroes/<AI>-SHADOW / -HERO-NONEON / -NEON-WHITE   -> assets/art/ui/hero_<f>.png (shadow + body, the old 768 px slot, lossy import)
                                                           assets/art/ui/hero_neon_<f>.png (white neon line; the game tints it the SEAT colour)
  ai-clean/SCREEN-BACK, GLITCH-OVERLAY (tinted the AI colour), <AI>-GLOW, -BODY, -EYES / -EYES-CLOSED, SCREEN-BEZEL
                                                        -> assets/art/ui/ai_screen_<f>.png, ai_screen_<f>_blink.png (prematch AI screen)
One shared crop for all five heroes, so the lineup's relative sizes hold in every picture (feet on one row).
usage (repo root): python tools/units/build_heroes_1117.py"""
import numpy as np
from PIL import Image, ImageChops, ImageFilter

REF = "H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/MODEL-DIRECTION-2026-11-16/"
OUT = "assets/art/ui/"
AI = {"vex": "VEX", "ember": "EMBER", "solar": "AEGIS", "bloom": "BLOOM", "null": "NULL"}
GLITCH = {"vex": (25, 229, 255), "ember": (255, 120, 30), "solar": (255, 190, 25), "bloom": (111, 255, 42), "null": (255, 25, 171)}
HERO_PX = 768
SCREEN_PX = 384


def load(p):
    return Image.open(REF + p).convert("RGBA")


def over(dst, src):
    return Image.alpha_composite(dst, src)


def tint(im, rgb):
    a = np.asarray(im, np.float32)
    lum = a[..., :3].mean(-1, keepdims=True) / 255.0
    out = np.concatenate([np.clip(lum * np.array(rgb, np.float32), 0, 255), a[..., 3:]], -1)
    return Image.fromarray(out.astype(np.uint8))


def heroes():
    body, neon = {}, {}
    box = None
    for f, n in AI.items():
        b = over(load(f"ooze-heroes/{n}-SHADOW.png"), load(f"ooze-heroes/{n}-HERO-NONEON.png"))
        body[f] = b
        neon[f] = load(f"ooze-heroes/{n}-NEON-WHITE.png")
        bb = b.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()   # faint shadow / AA alpha ignored
        box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    side = max(box[2] - box[0], box[3] - box[1]) + 24
    cx = (box[0] + box[2]) // 2
    crop = (cx - side // 2, box[3] + 12 - side, cx - side // 2 + side, box[3] + 12)   # feet near the bottom edge
    print("hero union bbox", box, "crop", crop)
    for f in AI:
        body[f].crop(crop).resize((HERO_PX, HERO_PX), Image.LANCZOS).save(f"{OUT}hero_{f}.png", optimize=True)
        m = neon[f].crop(crop).resize((HERO_PX, HERO_PX), Image.LANCZOS)
        a = np.asarray(m)[..., 3]
        w = np.zeros((HERO_PX, HERO_PX, 4), np.uint8)
        w[..., :3] = 255
        w[..., 3] = a
        Image.fromarray(w).save(f"{OUT}hero_neon_{f}.png", optimize=True)


FILL = 0.80          # the tallest / widest AI fills this share of the glass
FRAME_DIR = REF + "ai-screen-frame-2026-11-17/"
FRAME_SRC = FRAME_DIR + "ai-screen-frame-daniele-2026-11-17.webp"
FRAME_CLEAN = FRAME_DIR + "ai-screen-frame-daniele-2026-11-17_clean-alpha.png"   # derivative next to the immutable source


def clean_frame():
    """Daniele's frame (2026-11-17) with a clean alpha: the webp's alpha is ~252 across the metal and soft at the rim, with dark / white
    contamination in the rim's colour. Fully opaque where >= 200, transparent where < 24, and every soft rim texel takes the colour of its
    nearest solid texel (no halo on any background)."""
    from scipy import ndimage
    a = np.asarray(Image.open(FRAME_SRC).convert("RGBA")).copy()
    al = a[..., 3]
    solid = al >= 200
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = a[..., :3][idx[0], idx[1]]
    out = np.zeros_like(a)
    out[..., :3] = rgb
    out[..., 3] = np.where(solid, 255, np.where(al < 24, 0, ((al.astype(np.float32) - 24) / 176 * 255).clip(0, 255))).astype(np.uint8)
    out[out[..., 3] == 0, :3] = 0
    im = Image.fromarray(out)
    im.save(FRAME_CLEAN, optimize=True)
    return im, a


def screen_mask(im):
    """The dark purple glass: the flood-filled dark region from the centre (frame metal is brighter)."""
    from scipy import ndimage
    a = np.asarray(im).astype(np.float32)
    dark = (a[..., :3].max(-1) < 62) & (a[..., 3] > 200)
    lab, _ = ndimage.label(dark)
    m = lab == lab[a.shape[0] // 2, a.shape[1] // 2]
    return ndimage.binary_fill_holes(m)


def screens():
    from scipy import ndimage
    frame, _ = clean_frame()
    m = screen_mask(frame)
    ys, xs = np.nonzero(m)
    mb = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    mm = Image.fromarray((ndimage.binary_erosion(m, iterations=2) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    back, glitch = load("ai-clean/SCREEN-BACK.png"), load("ai-clean/GLITCH-OVERLAY.png")
    bb = back.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    print("frame glass bbox", mb, "portrait screen bbox", bb)
    fb = frame.getchannel("A").getbbox()
    side = max(fb[2] - fb[0], fb[3] - fb[1])
    cx, cy = (fb[0] + fb[2]) // 2, (fb[1] + fb[3]) // 2
    crop = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    # Daniele 2026-11-17 (round 2): "the AIs look too high in the screen and cut" -> centre each AI's OWN body box in the glass and size
    # every AI by the widest / tallest one (so they keep their relative sizes), with a margin; the glitch layer moves with it.
    boxes = {}
    for f, n in AI.items():
        u = over(load(f"ai-clean/{n}-GLOW.png"), load(f"ai-clean/{n}-BODY.png"))
        boxes[f] = u.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    gw, gh = mb[2] - mb[0], mb[3] - mb[1]
    k = min(min(gw * FILL / (x[2] - x[0]), gh * FILL / (x[3] - x[1])) for x in boxes.values())
    print("fill k", round(k, 3), {f: x for f, x in boxes.items()})
    glass = Image.new("RGBA", frame.size, (22, 4, 28, 0))
    glass.putalpha(mm)
    holed = frame.copy()
    holed.putalpha(ImageChops.multiply(frame.getchannel("A"), ImageChops.invert(mm)))
    for f, n in AI.items():
        for tag, eyes in (("", "EYES"), ("_blink", "EYES-CLOSED")):
            im = Image.new("RGBA", back.size, (0, 0, 0, 0))
            im = over(im, tint(glitch, GLITCH[f]))
            for layer in ("GLOW", "BODY", eyes):
                im = over(im, load(f"ai-clean/{n}-{layer}.png"))
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            x0, y0, x1, y1 = boxes[f]
            ox = (mb[0] + mb[2]) / 2 - (x0 + x1) / 2 * k
            oy = (mb[1] + mb[3]) / 2 - (y0 + y1) / 2 * k
            cv = Image.new("RGBA", frame.size, (0, 0, 0, 0))
            cv.paste(im, (round(ox), round(oy)))
            r, g, b, a = cv.split()
            cv = Image.merge("RGBA", (r, g, b, ImageChops.multiply(a, mm)))        # clipped to the glass's rounded corners
            full = over(glass, cv)
            full = over(full, holed)       # the frame over the portrait, its glass punched out
            full.crop(crop).resize((SCREEN_PX, SCREEN_PX), Image.LANCZOS).save(f"{OUT}ai_screen_{f}{tag}.png", optimize=True)


if __name__ == "__main__":
    if "--screens-only" not in __import__("sys").argv:
        heroes()
    screens()
