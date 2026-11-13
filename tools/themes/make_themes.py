"""themes (2026-11-13): web-size derivatives of the four round-32 settings for the theme system (scripts/look_theme.gd).
Sources (untouched): References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/32-<setting>/
  background/SURROUND-PHONE-WALLS.png / SURROUND-WIDE-WALLS.png  (RGBA, floor + hole keyed, as 26B2: the -WALLS plates)
  floor/TILE-<S>.png                                               (2048 px = 16 m, as 26F-B TILE-LAB)
  hud/round25/*-SHELL.png, hud/round30-pipes/*-SHELL.png, hud/PAINT-*.png  (14 shells, same canvas + alpha as 29-FINAL)
Out: assets/world/themes/<id>/{surround_phone,surround_wide,tile}.png, assets/ui/themes/<id>/<lab29 name>.png, + .import files
(lossy WebP for the plates and the tile, lossless + mipmaps for the HUD shells, as the lab's).
Usage: python make_themes.py <deliveries dir> <repo root> [tile_px] [plate_q] [tile_q]"""
import sys, os, shutil
import numpy as np
from PIL import Image, ImageFilter

DEL, ROOT = sys.argv[1], sys.argv[2]
TILE_PX = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
PLATE_Q = float(sys.argv[4]) if len(sys.argv) > 4 else 0.85
TILE_Q = float(sys.argv[5]) if len(sys.argv) > 5 else 0.85
HUD_Q = float(sys.argv[6]) if len(sys.argv) > 6 else 0.9    # size pass: lossy WebP (alpha stays lossless in WebP) + mipmaps
THEMES = {"corporate_campus": ("32-corporate-campus", "CORPORATE-CAMPUS"), "golden_hour": ("32-golden-hour", "GOLDEN-HOUR"),
          "quota_parade": ("32-quota-parade", "QUOTA-PARADE"), "wellness_retreat": ("32-wellness-retreat", "WELLNESS-RETREAT")}
HUD = [("hud/round25/KEY-SHELL.png", "key-shell"), ("hud/round25/VAT-SHELL.png", "vat-shell"), ("hud/round25/BUTTON-SHELL.png", "button-shell"),
       ("hud/round30-pipes/TUBE-SHELL.png", "r30-tube-shell"), ("hud/round30-pipes/SKILL-FEED-SHELL.png", "r30-skill-feed-shell"),
       ("hud/round30-pipes/VAT-FEED-SHELL.png", "r30-vat-feed-shell")] + \
      [("hud/PAINT-%s.png" % n, "paint-" + n) for n in ["badge", "banner", "card", "close", "slice-40", "slice-50", "tier-tag", "toast"]]
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=%d
compress/high_quality=false
compress/lossy_quality=%s
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=%s
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_import(path, lossy, q, mips):
    rel = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    imp = path + ".import"
    old = open(imp, encoding="utf8").read() if os.path.exists(imp) else ""
    new = IMPORT % (rel, 1 if lossy else 0, q, "true" if mips else "false")
    if "uid=" in old:                       # keep the uid Godot gave it
        uid = [l for l in old.splitlines() if l.startswith("uid=")][0]
        new = new.replace('type="CompressedTexture2D"\n', 'type="CompressedTexture2D"\n%s\n' % uid)
    open(imp, "w", encoding="utf8", newline="\n").write(new)


def _visible_loss(path, q, min_psnr=40.0):
    """True when lossy WebP at q visibly changes the shell (PSNR < 40 dB on its opaque pixels): that shell stays lossless."""
    import io
    a = Image.open(path).convert("RGBA")
    b = io.BytesIO(); a.save(b, "WEBP", quality=int(q * 100)); b.seek(0)
    d = np.array(Image.open(b).convert("RGBA")).astype(float); o = np.array(a).astype(float)
    m = o[..., 3] > 8
    mse = ((d[..., :3] - o[..., :3])[m] ** 2).mean() if m.any() else 0.0
    return 10 * np.log10(255 ** 2 / max(mse, 1e-9)) < min_psnr


def surround(src, out, size):
    """make_surround.py's recipe (lab-wire): ~4 px inward feather, colour bled under the hole, then resized."""
    im = Image.open(src)
    a = np.array(im.convert("RGBA"))
    if im.mode != "RGBA":
        key = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
        a[..., 3] = np.where(key, 0, 255)
    hard = a[..., 3] > 127
    soft = np.array(Image.fromarray((hard * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(2)))
    a[..., 3] = np.minimum(a[..., 3], soft)
    w = a[..., 3:4].astype(np.float32) / 255.0
    solid = (a[..., 3:4] >= 250).astype(np.float32)        # bleed only from fully opaque wall pixels (the hole is magenta)
    def gb(x):
        return np.stack([np.array(Image.fromarray(x[..., i]).filter(ImageFilter.GaussianBlur(8)), np.float32) for i in range(x.shape[-1])], -1)
    num = gb(np.clip(a[..., :3] * solid, 0, 255).astype(np.uint8)) + 0.0
    den = gb((solid * 255).astype(np.uint8))[..., :1] / 255.0
    blur = num / np.maximum(den, 1e-3)
    blur = np.where(den > 0.004, blur, np.array([40, 40, 40], np.float32))
    use = w[..., 0] < 0.99                                   # every partial / hole pixel takes the wall colour (opaque pixels untouched)
    a[..., :3] = np.where(use[..., None], np.clip(blur, 0, 255), a[..., :3]).astype(np.uint8)
    oa = np.array(Image.fromarray(a, "RGBA").resize(size, Image.LANCZOS))
    oa[..., 3] = np.where(oa[..., 3] < 4, 0, oa[..., 3])     # resample dust (alpha 1-3) out: no invisible magenta left
    Image.fromarray(oa, "RGBA").save(out, optimize=True)
    mag = int(((oa[..., 0] > 240) & (oa[..., 1] < 20) & (oa[..., 2] > 240) & (oa[..., 3] > 0)).sum())
    print(f"  {os.path.basename(out)} {size} alpha0 {(oa[..., 3] == 0).mean():.3f} magenta {mag}")


for tid, (folder, S) in THEMES.items():
    src = os.path.join(DEL, folder)
    wd = os.path.join(ROOT, "assets", "world", "themes", tid)
    ud = os.path.join(ROOT, "assets", "ui", "themes", tid)
    os.makedirs(wd, exist_ok=True)
    os.makedirs(ud, exist_ok=True)
    print(tid)
    for plate, out, size in [("SURROUND-PHONE-WALLS.png", "surround_phone.png", (2436, 1125)), ("SURROUND-WIDE-WALLS.png", "surround_wide.png", (2560, 1440))]:
        p = os.path.join(wd, out)
        surround(os.path.join(src, "background", plate), p, size)
        write_import(p, True, PLATE_Q, False)
    t = Image.open(os.path.join(src, "floor", "TILE-%s.png" % S)).convert("RGB")
    if t.size[0] != TILE_PX:
        t = t.resize((TILE_PX, TILE_PX), Image.LANCZOS)   # 16 m either way (Look.FLOOR_M): a wrap-safe whole-tile resample
    p = os.path.join(wd, "tile.png")
    t.save(p, optimize=True)
    write_import(p, True, TILE_Q, False)
    print(f"  tile.png {t.size}")
    for s, n in HUD:
        p = os.path.join(ud, n + ".png")
        shutil.copyfile(os.path.join(src, s), p)
        write_import(p, not _visible_loss(p, HUD_Q), HUD_Q, True)   # looks first (Daniele 11-13): lossless where WebP shows
    print(f"  hud {len(HUD)} shells")
