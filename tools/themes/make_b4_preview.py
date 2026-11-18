"""B4 setting tile preview (assets/ui/settings/lab.jpg is the live B4 tile): goo tile + pit rim + crust, 384x216."""
import os
from PIL import Image
d = "assets/art/bg44b4/"
W, H = 1624, 750
base = Image.new("RGBA", (W, H))
t = Image.open(d + "goo_tile.png").convert("RGBA")
for x in range(0, W, t.width):
    for y in range(0, H, t.height):
        base.paste(t, (x, y))
if os.path.exists(d + "rim.png"):
    r = Image.open(d + "rim.png").convert("RGBA")
    base.alpha_composite(r, (240, 123))
base.alpha_composite(Image.open(d + "crust.png").convert("RGBA").resize((W, H)))
base.convert("RGB").resize((384, 216), Image.LANCZOS).save("assets/ui/settings/lab.jpg", quality=90)
