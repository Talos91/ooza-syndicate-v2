"""AI REACTIONS (ai-reactions, 2026-11-18): the AI screen as LAYERS, so ai_screens.gd can animate the face (squash, squint, glitch)
instead of swapping two flat pictures. Same placement as tools/units/build_heroes_1117.py screens() (Daniele's 2026-11-17 frame,
each AI's own body box centred in the glass, one shared scale), so the screen at rest looks like ai_screen_<f>.png.
Sources (read only): ai-clean/<AI>-GLOW / -BODY / -EYES / -EYES-CLOSED, GLITCH-OVERLAY; the frame's clean-alpha derivative.
Out: assets/art/ui/ai_layers/ glass.png (the glass, also the clip mask), frame.png (the frame, glass punched out), glitch.png
(grey: the game tints it the AI colour), <f>_glow / _body / _eyes / _shut.png, each cropped to its box; layers.json = boxes in
the 384 px screen canvas ("glitch@<f>" = the glitch layer's box for that AI). No new art: crops, scales, the frame's own pixels.
usage (repo root): python tools/prep_ai_layers.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageFilter

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "units"))
import build_heroes_1117 as H  # noqa: E402

OUT = "assets/art/ui/ai_layers/"
S = H.SCREEN_PX


def main():
    from scipy import ndimage
    os.makedirs(OUT, exist_ok=True)
    frame = Image.open(H.FRAME_CLEAN).convert("RGBA")
    m = H.screen_mask(frame)
    ys, xs = np.nonzero(m)
    mb = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    mm = Image.fromarray((ndimage.binary_erosion(m, iterations=2) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    fb = frame.getchannel("A").getbbox()
    side = max(fb[2] - fb[0], fb[3] - fb[1])
    cx, cy = (fb[0] + fb[2]) // 2, (fb[1] + fb[3]) // 2
    crop = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    s = S / side
    boxes = {}

    def save(im, name, off=(0.0, 0.0)):
        bb = im.getchannel("A").point(lambda v: 255 if v > 2 else 0).getbbox()
        im.crop(bb).save(OUT + name + ".png", optimize=True)
        return [round(off[0] + bb[0], 2), round(off[1] + bb[1], 2), bb[2] - bb[0], bb[3] - bb[1]]

    glass = Image.new("RGBA", frame.size, (22, 4, 28, 0))
    glass.putalpha(mm)
    holed = frame.copy()
    holed.putalpha(ImageChops.multiply(frame.getchannel("A"), ImageChops.invert(mm)))
    boxes["glass"] = save(glass.crop(crop).resize((S, S), Image.LANCZOS), "glass")
    boxes["frame"] = save(holed.crop(crop).resize((S, S), Image.LANCZOS), "frame")
    ai_box = {}
    for f, n in H.AI.items():
        u = H.over(H.load(f"ai-clean/{n}-GLOW.png"), H.load(f"ai-clean/{n}-BODY.png"))
        ai_box[f] = u.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    gw, gh = mb[2] - mb[0], mb[3] - mb[1]
    k = min(min(gw * H.FILL / (x[2] - x[0]), gh * H.FILL / (x[3] - x[1])) for x in ai_box.values())
    px = round(2048 * k * s)

    def layer(path):
        return H.load(path).resize((px, px), Image.LANCZOS)

    g = layer("ai-clean/GLITCH-OVERLAY.png")
    a = np.asarray(g, np.float32)
    lum = a[..., :3].mean(-1, keepdims=True)
    g = Image.fromarray(np.concatenate([np.repeat(lum, 3, -1), a[..., 3:]], -1).astype(np.uint8))
    gbox = save(g, "glitch")
    for f, n in H.AI.items():
        x0, y0, x1, y1 = ai_box[f]
        ox = (mb[0] + mb[2]) / 2 - (x0 + x1) / 2 * k
        oy = (mb[1] + mb[3]) / 2 - (y0 + y1) / 2 * k
        off = ((ox - crop[0]) * s, (oy - crop[1]) * s)
        boxes["glitch@" + f] = [round(off[0] + gbox[0], 2), round(off[1] + gbox[1], 2), gbox[2], gbox[3]]
        for tag, src in (("glow", "GLOW"), ("body", "BODY"), ("eyes", "EYES"), ("shut", "EYES-CLOSED")):
            boxes[f + "_" + tag] = save(layer(f"ai-clean/{n}-{src}.png"), f + "_" + tag, off)
    with open(OUT + "layers.json", "w") as fh:
        json.dump({"size": S, "boxes": boxes}, fh, indent=1)
    print(json.dumps(boxes))


if __name__ == "__main__":
    main()
