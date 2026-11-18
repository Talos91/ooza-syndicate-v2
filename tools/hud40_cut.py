"""hud-40b6 (2026-11-15): the match HUD pack = 40B4 base + 40B5 pipes + 40B6 rack / connectors, skill keys from 40B5 (= 40B4).
Copies the 4x cuts at 2x (half size, LANCZOS) into assets/ui/hud40/; MUTE / PAUSE keys are cut from the B6 MATCH proof through
KEY-CHAT's alpha (same canvas). Originals untouched. Run: python tools/hud40_cut.py <DIRECTOR-PACKAGE/deliveries>"""
import sys, os, json
from PIL import Image
D = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "hud40")
os.makedirs(OUT, exist_ok=True)
B4, B5, B6, A = [os.path.join(D, "40-ui-hybrid-chamfer-" + s, "cut") for s in ("B4", "B5", "B6", "")]
A = os.path.join(D, "40-ui-hybrid-chamfer-A")
PICK = {
    B4: ["PAINT-VAT-FRAME", "MASK-VAT-GOO", "MASK-VAT-NEON-B4", "PAINT-VAT-GLASS", "PAINT-VAT-TICK-25", "PAINT-VAT-TICK-50",
         "PAINT-VAT-TICK-75", "PAINT-SCORE-FRAME", "PAINT-SCORE-4P-FRAME", "MASK-SCORE-TUBE", "PAINT-SCORE-TUBE-GLASS",
         "PAINT-SCORE-TIMER", "PAINT-SCORE-CAP", "PAINT-SCORE-CAP-4P", "MASK-SCORE-CAP-SEAT", "MASK-SCORE-CAP-SEAT-4P",
         "PAINT-TOPKEY-BRACKET", "KEY-CHAT", "KEY-DEBUG", "GEO-SKILL-KEY", "GEO-SKILL-KEY-2", "GEO-SKILL-KEY-3"],
    B5: ["PAINT-VAT-PIPE", "PAINT-SCORE-MOUNT-LEFT", "PAINT-SCORE-MOUNT-RIGHT", "PAINT-BRACKET-PIPE"],
    B6: ["PAINT-RACK-MAIN-SHAFT", "PAINT-RACK-TOP-ELBOW", "PAINT-RACK-TOP-EXTENSION", "PAINT-CONNECTOR-SAGE-T", "PAINT-SKILL-FEED",
         "PAINT-CONNECTOR-SKILL-T", "PAINT-CONNECTOR-SCORE"],
    A: ["MASK-SKILL-KEY%s-%s" % (k, m) for k in ("", "-2", "-3") for m in ("SEAT-RIM", "DIM", "ICON-WELL")],
}
def half(im):
    return im.resize((max(1, round(im.width / 2)), max(1, round(im.height / 2))), Image.LANCZOS)
info = {}
for src, names in PICK.items():
    for n in names:
        im = Image.open(os.path.join(src, n + ".png")).convert("RGBA")
        h = half(im)
        h.save(os.path.join(OUT, n + ".png"), optimize=True)
        bb = h.getchannel("A").point(lambda a: 255 if a > 127 else 0).getbbox()
        info[n] = {"px2": list(h.size), "alpha_bbox_px2": list(bb) if bb else None}
proof = Image.open(os.path.join(D, "40-ui-hybrid-chamfer-B6", "MATCH.png")).convert("RGBA")
alpha = Image.open(os.path.join(B4, "KEY-CHAT.png")).convert("RGBA").getchannel("A")
for n, (x, y) in {"KEY-MUTE": (715.5, 11), "KEY-PAUSE": (749.5, 9)}.items():
    c = proof.crop((int(x * 4), int(y * 4), int(x * 4) + alpha.width, int(y * 4) + alpha.height))
    c.putalpha(alpha)
    half(c).save(os.path.join(OUT, n + ".png"), optimize=True)
json.dump(info, open(os.path.join(OUT, "hud40.json"), "w"), indent=1)
print(json.dumps({k: v for k, v in info.items() if k.startswith("MASK")}, indent=0))
