"""Ooze models 2026-11-17 (Daniele's five models from the locked lineup) -> game units.
Originals (read only): References/Art direction 2026-11 - syndicate uniforms/MODEL-DIRECTION-2026-11-16/models-2026-11-17/<ai>_2026-11-17.glb
Same recipe as build_rodin_units.py (Daniele 2026-11-15, option A): the ORIGINAL geometry buffers untouched, textures resized to
1024, no normal map (creature.gdshader never samples it). New: the neon mask follows the 2026-11-16 direction - "one cyan neon line
per accessory = the tint mask". The neon is the cyan line inset in the gunmetal plates; VEX's goo is the same cyan (hue 0.54), so a
colour test alone would tint the whole VEX body: a texel is neon only when it is cyan AND has gunmetal on both opposite sides within
TWO_SIDED px (the line runs inside the plate; goo beside a plate has steel on one side only). Other AIs also keep cyan texels touching
the plate (their goo is never cyan). Tint G = EMBER's glowing visor slit (README: "EMBER's glowing slit stays").
usage (repo root): python tools/units/build_units_1117.py [review_dir]
  -> assets/units/<f>.glb, <f>_texture_diffuse.png, <f>_texture_metallic-texture_roughness.png, <f>_tint.png"""
import struct, json, io, sys, numpy as np
from PIL import Image
from scipy import ndimage

SRC = "H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/MODEL-DIRECTION-2026-11-16/models-2026-11-17/"
OUT = "assets/units/"
UNITS = {"vex": "vex", "null": "null", "bloom": "bloom", "ember": "ember", "solar": "aegis"}   # game key -> AI file
TWO_SIDED = 40      # px at 2048: max distance to the plate on each side of a neon texel
CYAN_ONLY = {"null", "bloom", "ember", "solar"}   # goo never cyan: cyan touching the plate is neon too
MIN_COMP = {"vex": 1200}
CLOSE_GAPS = {"vex": 14}                           # px at 2048: VEX drops cyan specks between plate bits on its goo
GLOW = {"ember": ((0.10, 0.19), 0.55, 0.80)}       # tint G: (hue range, min sat, min value) = EMBER visor slit


def disc(r):
    yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
    return xx * xx + yy * yy <= r * r


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 1e-4, d / np.maximum(mx, 1e-4), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) / 6.0
    return np.where(d > 1e-6, h, 0), s, mx


def _shift(a, dy, dx):
    o = np.zeros_like(a)
    H, W = a.shape
    o[max(dy, 0):H + min(dy, 0), max(dx, 0):W + min(dx, 0)] = a[max(-dy, 0):H + min(-dy, 0), max(-dx, 0):W + min(-dx, 0)]
    return o


def two_sided(steel, r):
    out = np.zeros_like(steel)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = np.zeros_like(steel)
        b = np.zeros_like(steel)
        for k in range(1, r + 1):
            a |= _shift(steel, dy * k, dx * k)
            b |= _shift(steel, -dy * k, -dx * k)
        out |= a & b
    return out


def masks(diff, game):
    rgb = np.asarray(diff, np.float32) / 255.0
    h, s, v = hsv(rgb)
    cyan = (h > 0.46) & (h < 0.60) & (s > 0.30) & (v > 0.40)
    steel = ndimage.binary_opening((s < 0.25) & (v > 0.10) & (v < 0.62), structure=disc(1))
    m = cyan & two_sided(steel, TWO_SIDED)
    if game in CYAN_ONLY:
        m |= cyan & ndimage.binary_dilation(steel, structure=disc(12))
    lab, n = ndimage.label(m)
    if n:
        sz = ndimage.sum(m, lab, range(1, n + 1))
        m = np.isin(lab, 1 + np.nonzero(sz >= MIN_COMP.get(game, 60))[0])
    if game in CLOSE_GAPS:                                         # bridge short breaks along the line (VEX band beside the glyph)
        m |= ndimage.binary_closing(m, structure=disc(CLOSE_GAPS[game])) & cyan
    fringe = (h > 0.44) & (h < 0.62) & (s > 0.18) & ~steel        # the anti-aliased edge of the line, never the plate itself
    m |= ndimage.binary_dilation(m, structure=disc(2)) & fringe
    g = np.zeros_like(m)
    if game in GLOW:
        (h0, h1), smin, vmin = GLOW[game]
        g = (h > h0) & (h < h1) & (s > smin) & (v > vmin)
        g = ndimage.binary_opening(g, structure=disc(2))
    return m, g


def build(game, ai, review=None):
    b = open(SRC + f"{ai}_2026-11-17.glb", "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl + 8
    imgs = {}
    for im in j["images"]:
        bv = j["bufferViews"][im["bufferView"]]
        o = off + bv.get("byteOffset", 0)
        imgs[im["name"]] = Image.open(io.BytesIO(b[o:o + bv["byteLength"]])).convert("RGB")
    diff, mr = imgs["texture_diffuse"], imgs["texture_metallic-texture_roughness"]
    pr = j["meshes"][0]["primitives"][0]
    geo_views = sorted({j["accessors"][i]["bufferView"] for i in list(pr["attributes"].values()) + [pr["indices"]]})
    assert geo_views == [0, 1, 2, 3], geo_views
    geom_len = j["bufferViews"][3]["byteOffset"] + j["bufferViews"][3]["byteLength"]
    body = bytearray(b[off:off + geom_len])
    pngs = []
    for name, im in (("texture_diffuse", diff), ("texture_metallic-texture_roughness", mr)):
        r = im.resize((1024, 1024), Image.LANCZOS)
        r.save(f"{OUT}{game}_{name}.png", optimize=True)
        o = io.BytesIO(); r.save(o, "PNG", optimize=True); pngs.append((name, o.getvalue()))
    m, g = masks(diff, game)
    def down(a):
        return np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((1024, 1024), Image.BOX), np.float32) / 255.0
    tint = np.zeros((1024, 1024, 3), np.uint8)
    tint[..., 0] = (down(m) > 0.4) * 255
    tint[..., 1] = (down(g) > 0.4) * 255
    Image.fromarray(tint).save(f"{OUT}{game}_tint.png", optimize=True)
    if review:
        ov = np.asarray(diff.resize((1024, 1024), Image.LANCZOS)).copy()
        ov[tint[..., 0] > 0] = (255, 0, 160)
        ov[tint[..., 1] > 0] = (0, 255, 0)
        Image.fromarray(ov).save(f"{review}/{game}_mask_overlay.png")
    bvs = [dict(x) for x in j["bufferViews"][:4]]
    for name, data in pngs:
        while len(body) % 4: body.append(0)
        bvs.append({"buffer": 0, "byteOffset": len(body), "byteLength": len(data)})
        body += data
    while len(body) % 4: body.append(0)
    j2 = {k: j[k] for k in ("asset", "scene", "scenes", "nodes", "meshes", "accessors", "samplers") if k in j}
    j2["bufferViews"] = bvs
    j2["buffers"] = [{"byteLength": len(body)}]
    j2["images"] = [{"bufferView": 4, "mimeType": "image/png", "name": "texture_diffuse"},
                    {"bufferView": 5, "mimeType": "image/png", "name": "texture_metallic-texture_roughness"}]
    j2["textures"] = [{"sampler": 0, "source": 0}, {"sampler": 0, "source": 1}]
    j2["materials"] = [{"name": "model", "doubleSided": True,
                        "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}}}]
    js = json.dumps(j2, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(body))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(body), 0x004E4942) + bytes(body)
    open(f"{OUT}{game}.glb", "wb").write(out)
    a0 = j["accessors"][pr["attributes"]["POSITION"]]
    print(game, ai, "glb", len(out), "neon texels@1024", int((tint[..., 0] > 0).sum()), "glow", int((tint[..., 1] > 0).sum()),
          "tris", j["accessors"][pr["indices"]]["count"] // 3, "size", [round(a0["max"][k] - a0["min"][k], 3) for k in range(3)])


if __name__ == "__main__":
    rv = sys.argv[1] if len(sys.argv) > 1 else None
    for g, a in UNITS.items():
        build(g, a, rv)
