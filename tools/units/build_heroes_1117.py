"""Unit pictures + AI screens from Daniele's 2026-11-17 2D sets (originals only read):
  ooze-heroes/<AI>-SHADOW / -HERO-NONEON / -NEON-WHITE   -> assets/art/ui/hero_<f>.png (shadow + body, the old 768 px slot, lossy import)
                                                           assets/art/ui/hero_neon_<f>.png (white neon line; the game tints it the SEAT colour)
  ai-clean/SCREEN-BACK, GLITCH-OVERLAY (tinted the AI colour), <AI>-GLOW, -BODY, -EYES / -EYES-CLOSED, SCREEN-BEZEL
                                                        -> assets/art/ui/ai_screen_<f>.png, ai_screen_<f>_blink.png (prematch AI screen)
One shared crop for all five heroes, so the lineup's relative sizes hold in every picture (feet on one row).
usage (repo root): python tools/units/build_heroes_1117.py"""
import numpy as np
from PIL import Image

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


def screens():
    back, bezel, glitch = load("ai-clean/SCREEN-BACK.png"), load("ai-clean/SCREEN-BEZEL.png"), load("ai-clean/GLITCH-OVERLAY.png")
    bb = over(back, bezel).getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    side = max(bb[2] - bb[0], bb[3] - bb[1])
    cx, cy = (bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2
    crop = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    print("screen bbox", bb, "crop", crop)
    for f, n in AI.items():
        for tag, eyes in (("", "EYES"), ("_blink", "EYES-CLOSED")):
            im = back
            im = over(im, tint(glitch, GLITCH[f]))
            for layer in ("GLOW", "BODY", eyes):
                im = over(im, load(f"ai-clean/{n}-{layer}.png"))
            im = over(im, bezel)
            im.crop(crop).resize((SCREEN_PX, SCREEN_PX), Image.LANCZOS).save(f"{OUT}ai_screen_{f}{tag}.png", optimize=True)


if __name__ == "__main__":
    heroes()
    screens()
