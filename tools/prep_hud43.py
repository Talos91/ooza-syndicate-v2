"""43-HUD-recreated + 43-score-hud-2p-4p(-goo) -> assets/ui/hud43 at ~3 px/pt (1/3 of the 4 px/ref-unit cut; 1 ref unit =
812/1842 pt). Designer 10 (2026-11-18): skill rail 104 -> 84 pt (trimmed: a middle strip is cut, the pipe and the right
edge kept), comms dropped, score housings fitted to the 270x37 pt zone, the goo pack's material + sheen.
Goo (magenta) pixels of the rail / cable / pipes are split into a white 'goo' layer so the game tints them the FACTION
colour (goo = faction colour, neon = seat colour)."""
import sys, os, shutil, colorsys
from PIL import Image
H = r"C:/Users/itisf/ooze-wt/ui-build-43b-tools/hudpacks/"
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
tot = 0


def save(im, name):
    global tot
    p = os.path.join(OUT, name + ".png")
    im.save(p, optimize=True)
    tot += os.path.getsize(p)


def third(im):
    return im.resize((max(1, round(im.width / 3)), max(1, round(im.height / 3))), Image.LANCZOS)


def split_goo(im):
    """(base, goo): goo = saturated magenta / pink pixels as white luminance, alpha kept; base = the rest."""
    base = im.copy()
    goo = Image.new("RGBA", im.size, (0, 0, 0, 0))
    bp, gp, sp = base.load(), goo.load(), im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            hd = h * 360
            if s > 0.35 and (hd > 285 or hd < 12) and l > 0.24 and r > g + 60:
                v = int(min(255, l * 255 * 1.35))
                gp[x, y] = (v, v, v, a)
                bp[x, y] = (0, 0, 0, 0)
    return base, goo


def trim_x(im, keep_w_ratio, cut_from=0.45):
    """Cut a vertical strip out of the middle so the width becomes keep_w_ratio of it (the edges untouched)."""
    w, h = im.size
    nw = round(w * keep_w_ratio)
    cut = w - nw
    x0 = round(w * cut_from)
    out = Image.new("RGBA", (nw, h))
    out.paste(im.crop((0, 0, x0, h)), (0, 0))
    out.paste(im.crop((x0 + cut, 0, w, h)), (x0, 0))
    return out


S = H + "rec/sprites/"
rail = trim_x(Image.open(S + "skill_rail.png").convert("RGBA"), 84 / 104)
rb, rg = split_goo(third(rail))
save(rb, "skill_rail"); save(rg, "skill_rail_goo")
for n in ["skill_key_cyan", "skill_key_rim_mask", "utility_key", "vat_sender_housing", "vat_liquid_neutral"]:
    save(third(Image.open(S + n + ".png").convert("RGBA")), n)
cb, cg = split_goo(third(Image.open(S + "vat_sender_cable.png").convert("RGBA")))
save(cb, "vat_cable"); save(cg, "vat_cable_goo")
pb, pg = split_goo(third(Image.open(S + "score_pipe_magenta.png").convert("RGBA")))
save(pb, "score_pipe"); save(pg, "score_pipe_goo")
for n in ["pause_icon", "audio_on_icon", "audio_muted_icon"]:
    shutil.copy(S + n + ".png", os.path.join(OUT, n + ".png")); tot += os.path.getsize(os.path.join(OUT, n + ".png"))
G = H + "goo/sprites/"
for n in ["score_housing_2p", "score_housing_4p", "score_timer_plate", "score_goo_material", "score_goo_sheen"]:
    save(third(Image.open(G + n + ".png").convert("RGBA")), n)
shutil.copy(H + "goo/score_share.gdshader", os.path.join(OUT, "score_share.gdshader"))
print("TOTAL bytes", tot)
