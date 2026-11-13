"""SETTING PICK previews (2026-11-13): one small picture per setting for the match setup's SETTING button / sheet.

Source: the themes worker's in-game shots of R-01 at 1:40 (AI vs AI seed 7, 1280x720), originals untouched:
  References/Art direction 2026-11 - syndicate uniforms/generated/themes-2026-11-13/R-01-<short>-1m40-1280x720.png
Out: Game/2.0 assets/ui/settings/<id>.jpg (384x216, JPEG q85; a few KB each).
Usage: python tools/themes/make_setting_previews.py "<project root>"
"""
import os
import sys

from PIL import Image

IDS = {"lab": "lab", "corporate_campus": "corporate", "golden_hour": "golden", "quota_parade": "quota", "wellness_retreat": "wellness"}
SIZE = (384, 216)


def main(root: str) -> None:
    src = os.path.join(root, "References", "Art direction 2026-11 - syndicate uniforms", "generated", "themes-2026-11-13")
    out = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui", "settings")
    os.makedirs(out, exist_ok=True)
    for tid, short in IDS.items():
        im = Image.open(os.path.join(src, "R-01-%s-1m40-1280x720.png" % short)).convert("RGB")
        im = im.resize(SIZE, Image.LANCZOS)        # the whole frame: the walls are what tells the settings apart
        p = os.path.join(out, tid + ".jpg")
        im.save(p, quality=85, optimize=True)
        print(p, os.path.getsize(p))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "H:/My Drive/PROJECTS/Ooze Syndicate")
