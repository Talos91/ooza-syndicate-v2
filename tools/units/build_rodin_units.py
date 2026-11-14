"""Rodin units, option A (Daniele 2026-11-15): the ORIGINAL Rodin geometry (untouched buffers), upright, textures resized to 1024,
no normal map (creature.gdshader never samples it), and a crisp neon mask cut from the Rodin diffuse at 2048 and shipped at 1024.
Originals (Models/2.0/factions-v4/generated/<f>/<f>_rodin_v1.glb) are only read.
usage: python tools/units/build_rodin_units.py   -> assets/units/<f>.glb, <f>_texture_diffuse.png, <f>_texture_metallic-texture_roughness.png, <f>_tint.png"""
import struct, json, io, os, numpy as np
from PIL import Image
from scipy import ndimage
from PIL import ImageDraw

EDGE_TRI = None   # set per unit in build()

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
# EDGE_STRIPES: steel/goo boundary triangles of the mesh whose height lies in [y0, y1] (model units) get a neon stripe LINE_R wide on the steel side,
# for an edge the Rodin texture has no light line on (Daniele 2026-11-15: EMBER hat band top edge). Geometry-driven: triangles rasterised into UV space.
EDGE_STRIPES = {"ember": (1.18, 0.03)}   # (top height of the band, stripe depth) in model units
LINE_R = 5          # half-width of the regularised thin lines at 2048 (about 5 px wide at 1024)


def edge_triangles(b, j, off, game, diff2k):
    """Texels (a bool image at 2048) of the steel triangles within `depth` below the top height `ytop`: the interpolated model height is
    rasterised into UV space, so the stripe follows the real top rim of the part."""
    ytop, depth = EDGE_STRIPES[game]
    pr = j["meshes"][0]["primitives"][0]
    def acc(i, n, dt):
        a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
        return np.frombuffer(b, dtype=dt, count=a["count"] * n, offset=off + bv.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(a["count"], n)
    P = acc(pr["attributes"]["POSITION"], 3, "<f4"); UV = acc(pr["attributes"]["TEXCOORD_0"], 2, "<f4"); I = acc(pr["indices"], 1, "<u2").reshape(-1, 3).astype(int)
    rgb = np.asarray(diff2k, np.float32) / 255.0
    sat, val = hsv(rgb)
    steel = (sat < 0.2) & (val > 0.25)
    out = np.zeros((2048, 2048), bool)
    U = UV * 2047.0
    for t in I:
        if P[t, 1].max() < ytop - depth or P[t, 1].min() > ytop + 0.01:
            continue
        pts = U[t]
        x0, x1 = int(pts[:, 0].min()), int(pts[:, 0].max()) + 1
        y0, y1 = int(pts[:, 1].min()), int(pts[:, 1].max()) + 1
        if x1 - x0 > 400 or y1 - y0 > 400:      # a UV seam triangle
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        d = (pts[1, 1] - pts[2, 1]) * (pts[0, 0] - pts[2, 0]) + (pts[2, 0] - pts[1, 0]) * (pts[0, 1] - pts[2, 1])
        if abs(d) < 1e-9:
            continue
        w0 = ((pts[1, 1] - pts[2, 1]) * (xs - pts[2, 0]) + (pts[2, 0] - pts[1, 0]) * (ys - pts[2, 1])) / d
        w1 = ((pts[2, 1] - pts[0, 1]) * (xs - pts[2, 0]) + (pts[0, 0] - pts[2, 0]) * (ys - pts[2, 1])) / d
        w2 = 1 - w0 - w1
        ins = (w0 >= -0.01) & (w1 >= -0.01) & (w2 >= -0.01)
        yy = w0 * P[t[0], 1] + w1 * P[t[1], 1] + w2 * P[t[2], 1]
        sel = ins & (yy > ytop - depth) & (yy < ytop + 0.01)
        out[ys[sel], xs[sel]] = True
    return out & steel


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
    thick = ndimage.gaussian_filter(thick.astype(np.float32), 4.0) > 0.5          # smooth, even edges on the wide parts (AEGIS cap rim)
    m = thick | line
    if game in EDGE_STRIPES and EDGE_TRI is not None:
        m |= ndimage.gaussian_filter(EDGE_TRI.astype(np.float32), 3.0) > 0.45
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
    global EDGE_TRI
    EDGE_TRI = edge_triangles(b, j, off, game, diff) if game in EDGE_STRIPES else None
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
