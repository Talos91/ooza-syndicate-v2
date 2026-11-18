"""Bake designer 12's copper punk set (cp-r7, Daniele 2026-11-19 "Yes, bake it") into the game kit.

Source (never written): Models/2.0/kit-v3-simple/export-cp-r7/*.glb (exported from Daniele's Blender; the GLBs ARE the source).
Output: Game/2.0/assets/kit/cp/<Key>.glb - new files; the old kit pieces stay where they are (Look.kit_key routes the keys).

- 34 bridge pieces: CP_<Key>.glb -> cp/<Key>.glb, byte-identical. Their colour slots keep their names (CP_Goo_A / CP_Goo_B,
  CP_Neon_A / CP_Neon_B): MapBuilder.paint_cp gives each slot the owner of the NEARER node (Daniele's half rule), so the
  game's OS_Light passes (state / Last Stand / trims) never touch them.
- CP_DrillNode_T3_v3.glb is split by its two scales into the two kit keys the game swaps per node:
  cp/Platform_Standard.glb (the x0.68 platform meshes) and cp/Vat_T3.glb (the T3 vat, door, cage, spire). Its colour slots
  are renamed to the game's owner slots so MapBuilder.apply_owner colours them (unowned = the game's neutral):
  CP_Neon_A, H_NeonBig -> OS_Light_A; CP_Goo_A, H_GooSolid (under-tubes) -> OS_Ooze_A (brief: "all goo = CP_Goo_A,
  all neon = CP_Neon_A -> its owner").

Run: python tools/bake_cp_r7.py [--src <export-cp-r7 folder>]
"""
import json
import os
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SRC = "H:/My Drive/PROJECTS/Ooze Syndicate/Models/2.0/kit-v3-simple/export-cp-r7"
OUT = os.path.join(GAME, "assets", "kit", "cp")

BRIDGES = ["Anchor_Stub", "Deck_S", "Deck_Remote", "Deck_Retract",
           "Deck_Overpass_Ramp", "Deck_Overpass_Span", "Deck_Overpass_High_Ramp", "Deck_Overpass_High_Span",
           "Deck_Underpass_Ramp", "Deck_Underpass_Span", "Pier_Connector",
           "Deck_S_Frag_plate_a", "Deck_S_Frag_plate_b", "Deck_S_Frag_plate_c",
           "Deck_S_Frag_girder_l", "Deck_S_Frag_girder_r", "Deck_S_Frag_truss"] + \
          ["Pier_Angled_%02d" % a for a in range(0, 85, 5)]
NODE = "CP_DrillNode_T3_v3"
NODE_RENAME = {"CP_Neon_A": "OS_Light_A", "H_NeonBig.001": "OS_Light_A",
               "CP_Goo_A": "OS_Ooze_A", "H_GooSolid.001": "OS_Ooze_A"}
PLATFORM_SCALE = 0.68          # the platform meshes' node scale (the vat's is 0.7072 / 0.9264)


def read_glb(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF", path
    jlen = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", b[off:off + 4])[0]
    assert b[off + 4:off + 8] == b"BIN\x00"
    return j, b[off + 8:off + 8 + blen]


def write_glb(path, j, bin_):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_ += b"\x00" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(bin_), b"BIN\x00") + bin_)


def subset(j, bin_, keep_nodes, rename):
    """A new glTF holding only the given root nodes (no children in this export), its meshes, accessors, views,
    materials - the buffer repacked - and the colour slots renamed (two source slots may merge into one)."""
    assert not j.get("images") and not j.get("textures") and not j.get("skins") and not j.get("animations")
    nodes = [dict(j["nodes"][i]) for i in keep_nodes]
    for n in nodes:
        assert "children" not in n
    out = {"asset": j["asset"], "scene": 0, "scenes": [{"name": "Scene", "nodes": list(range(len(nodes)))}],
           "nodes": [], "meshes": [], "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
    mat_map, acc_map, mesh_map, mat_by_name = {}, {}, {}, {}
    blob = bytearray()

    def acc(i):
        if i in acc_map:
            return acc_map[i]
        a = dict(j["accessors"][i])
        v = j["bufferViews"][a["bufferView"]]
        data = bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        while len(blob) % 4:
            blob.append(0)
        nv = {"buffer": 0, "byteOffset": len(blob), "byteLength": v["byteLength"]}
        for k in ("byteStride", "target"):
            if k in v:
                nv[k] = v[k]
        blob.extend(data)
        out["bufferViews"].append(nv)
        a["bufferView"] = len(out["bufferViews"]) - 1
        out["accessors"].append(a)
        acc_map[i] = len(out["accessors"]) - 1
        return acc_map[i]

    def mat(i):
        if i in mat_map:
            return mat_map[i]
        m = dict(j["materials"][i])
        name = rename.get(m.get("name", ""), m.get("name", ""))
        if name in mat_by_name:                         # merged slot: the first source material's look stands
            mat_map[i] = mat_by_name[name]
            return mat_map[i]
        m["name"] = name
        out["materials"].append(m)
        mat_by_name[name] = mat_map[i] = len(out["materials"]) - 1
        return mat_map[i]

    for n in nodes:
        if "mesh" in n:
            mi = n["mesh"]
            if mi not in mesh_map:
                m = j["meshes"][mi]
                prims = []
                for p in m["primitives"]:
                    q = dict(p)
                    q["attributes"] = {k: acc(v) for k, v in p["attributes"].items()}
                    if "indices" in p:
                        q["indices"] = acc(p["indices"])
                    if "material" in p:
                        q["material"] = mat(p["material"])
                    prims.append(q)
                out["meshes"].append({"name": m.get("name", ""), "primitives": prims})
                mesh_map[mi] = len(out["meshes"]) - 1
            n["mesh"] = mesh_map[mi]
        out["nodes"].append(n)
    out["buffers"].append({"byteLength": len(blob)})
    return out, bytes(blob)


def tris(j):
    return sum(j["accessors"][p["indices"]]["count"] // 3 for m in j["meshes"] for p in m["primitives"])


def main():
    src = SRC
    if "--src" in sys.argv:
        src = sys.argv[sys.argv.index("--src") + 1]
    os.makedirs(OUT, exist_ok=True)
    for key in BRIDGES:
        s = os.path.join(src, "CP_%s.glb" % key)
        d = os.path.join(OUT, "%s.glb" % key)
        shutil.copyfile(s, d)
        j, _ = read_glb(d)
        print("%-26s %6d tris  %s" % (key, tris(j), sorted({m["name"] for m in j["materials"]})))
    j, bin_ = read_glb(os.path.join(src, NODE + ".glb"))
    plat, vat = [], []
    for i, n in enumerate(j["nodes"]):
        (plat if abs(n.get("scale", [1, 1, 1])[1] - PLATFORM_SCALE) < 1e-3 else vat).append(i)
    for key, keep in (("Platform_Standard", plat), ("Vat_T3", vat)):
        o, b = subset(j, bin_, keep, NODE_RENAME)
        write_glb(os.path.join(OUT, key + ".glb"), o, b)
        print("%-26s %6d tris  %d meshes  %s" % (key, tris(o), len(o["nodes"]), sorted(m["name"] for m in o["materials"])))
    print("node total", tris(j), "tris; out", OUT)


if __name__ == "__main__":
    main()
