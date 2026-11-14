"""Rodin units, option A (Daniele 2026-11-15): the ORIGINAL Rodin geometry (untouched buffers), upright, textures resized to 1024,
no normal map (creature.gdshader never samples it), and a crisp neon mask cut from the Rodin diffuse at 2048 and shipped at 1024.
Originals (Models/2.0/factions-v4/generated/<f>/<f>_rodin_v1.glb) are only read.
usage: python tools/units/build_rodin_units.py   -> assets/units/<f>.glb, <f>_texture_diffuse.png, <f>_texture_metallic-texture_roughness.png, <f>_tint.png"""
import struct, json, io, os, numpy as np
from PIL import Image
from scipy import ndimage

SRC = "H:/My Drive/PROJECTS/Ooze Syndicate/Models/2.0/factions-v4/generated/"
OUT = "assets/units/"
FACTIONS = {"vex": "vex", "null": "null", "bloom": "bloom", "ember": "ember", "solar": "aegis"}   # game key -> Rodin folder


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    return np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0), mx


VMIN = {"ember": 0.56}   # EMBER: its brim neon is a thinner, greyer line than the others


def thin(img):
    """Zhang-Suen thinning (numpy): the one-pixel centre line of every stroke."""
    im = img.copy().astype(np.uint8)
    while True:
        changed = False
        for step in (0, 1):
            P = np.pad(im, 1)
            p2, p3, p4, p5, p6, p7, p8, p9 = (P[:-2, 1:-1], P[:-2, 2:], P[1:-1, 2:], P[2:, 2:], P[2:, 1:-1], P[2:, :-2], P[1:-1, :-2], P[:-2, :-2])
            nb = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            tr = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                c = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                c = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            rm = (im == 1) & (nb >= 2) & (nb <= 6) & (tr == 1) & c
            if rm.any():
                im[rm] = 0
                changed = True
        if not changed:
            return im.astype(bool)


def disc(r):
    yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
    return (xx * xx + yy * yy) <= r * r


# Plates whose logo is a lighter-grey relief (not white): (x0, y0, x1, y1) at 2048, raised-stroke threshold over the plate's median value
PLATES = {"solar": [(1545, 325, 1765, 605)]}
LINE_R = 5          # half-width of the regularised thin lines at 2048 (about 5 px wide at 1024)


def neon_mask(diff2k, vmin=0.78, game=""):
    """Clean, even neon: smoothed colour candidate; thick parts kept as they are, thin strokes replaced by their centre line grown to an even width;
    short patchy bits dropped; relief logos cut inside their plate."""
    rgb = np.asarray(diff2k, np.float32) / 255.0
    s, v = hsv(rgb)
    cand = (s < 0.16) & (v > vmin)
    cand = ndimage.gaussian_filter(cand.astype(np.float32), 2.0) > 0.5
    thick = ndimage.binary_opening(cand, structure=disc(8))
    thick = ndimage.binary_dilation(thick, structure=disc(1))
    thin_part = cand & ~ndimage.binary_dilation(thick, structure=disc(5))
    sk = thin(thin_part)
    lab, n = ndimage.label(sk, structure=np.ones((3, 3)))
    if n:
        sizes = ndimage.sum(sk, lab, range(1, n + 1))
        sk = np.isin(lab, 1 + np.nonzero(sizes >= 100)[0])
    line = ndimage.binary_dilation(sk, structure=disc(LINE_R))
    lab, n = ndimage.label(thick)
    if n:
        sizes = ndimage.sum(thick, lab, range(1, n + 1))
        thick = np.isin(lab, 1 + np.nonzero(sizes >= 1500)[0])
    m = thick | line
    for (x0, y0, x1, y1) in PLATES.get(game, []):
        g = (v[y0:y1, x0:x1]).copy()
        g = ndimage.gaussian_filter(g, 1.2)
        relief = g > (np.median(g) + 0.10)
        relief = ndimage.binary_opening(relief, structure=disc(2))
        relief = ndimage.binary_dilation(relief, structure=disc(2))
        m[y0:y1, x0:x1] |= relief
    return m


def build(game, folder):
    b = open(SRC + f"{folder}/{folder}_rodin_v1.glb", "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl + 8
    imgs = {}
    for im in j["images"]:
        bv = j["bufferViews"][im["bufferView"]]
        imgs[im["name"]] = Image.open(io.BytesIO(b[off + bv.get("byteOffset", 0):off + bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
    diff, mr = imgs["texture_diffuse"], imgs["texture_metallic-texture_roughness"]
    geom_len = j["bufferViews"][3]["byteOffset"] + j["bufferViews"][3]["byteLength"]
    geom = b[off:off + geom_len]
    pngs = []
    for name, im in (("texture_diffuse", diff), ("texture_metallic-texture_roughness", mr)):
        r = im.resize((1024, 1024), Image.LANCZOS)
        r.save(f"{OUT}{game}_{name}.png")
        o = io.BytesIO(); r.save(o, "PNG", optimize=True); pngs.append((name, o.getvalue()))
    # mask: cut at 2048, area-downsample, threshold -> crisp 1024
    m = neon_mask(diff, VMIN.get(game, 0.78), game).astype(np.float32)
    m1 = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((1024, 1024), Image.BOX), np.float32) / 255.0
    tint = np.zeros((1024, 1024, 3), np.uint8)
    tint[..., 0] = (m1 > 0.5) * 255
    Image.fromarray(tint).save(f"{OUT}{game}_tint.png")
    # review overlay
    ov = np.asarray(diff.resize((1024, 1024), Image.LANCZOS)).copy()
    ov[tint[..., 0] > 0] = (255, 0, 160)
    Image.fromarray(ov).save(f"../units-wire-rodin/{game}_mask_overlay.png")
    # glb
    body = bytearray(geom)
    bvs = list(j["bufferViews"][:4])
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
    print(game, "glb", len(out), "neon texels@1024", int((tint[..., 0] > 0).sum()), "tris", j["accessors"][3]["count"] // 3)


if __name__ == "__main__":
    for g, f in FACTIONS.items():
        build(g, f)
