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


def neon_mask(diff2k, vmin=0.78):
    """The white lit band edges of the Rodin diffuse: low saturation, high value; small specks dropped, holes closed, edges crisp."""
    rgb = np.asarray(diff2k, np.float32) / 255.0
    s, v = hsv(rgb)
    m = (s < 0.16) & (v > vmin)
    m = ndimage.binary_opening(m, iterations=1)
    m = ndimage.binary_closing(m, iterations=2)
    lab, n = ndimage.label(m)
    if n:
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        keep = np.isin(lab, 1 + np.nonzero(sizes >= 600)[0])
        m = keep
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
    m = neon_mask(diff, VMIN.get(game, 0.78)).astype(np.float32)
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
