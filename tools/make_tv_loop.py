"""Main menu TV loop (menu-bg, 0.24.4): packs the frames of a real demo match into one atlas, assets/art/menu/tv_loop.webp.
   1. Godot --path . --resolution 960x540 -- --map=res://maps4/R-01-strait.json --demo --mobile --ff=40 --seed=7 --clean-shots
        --shots=40,40.5,...,51.5 --out=<dir>        (24 frames, HUD and board tags hidden)
   2. python tools/make_tv_loop.py <dir>            (6 x 4 grid of 480 x 270; menu_den.gd plays it at 8 fps)"""
import sys, glob
from PIL import Image
src = sorted(glob.glob(sys.argv[1] + "/shot_*.png"))[:24]
W, H, C, R = 480, 270, 6, 4
atlas = Image.new("RGB", (W * C, H * R))
for i, f in enumerate(src):
    atlas.paste(Image.open(f).convert("RGB").resize((W, H), Image.LANCZOS), ((i % C) * W, (i // C) * H))
atlas.save("assets/art/menu/tv_loop.webp", quality=78, method=6)
print(len(src), "frames")
