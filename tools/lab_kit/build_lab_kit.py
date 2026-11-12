"""Ooze Syndicate 2.0 - PRODUCTION LAB KIT (2026-11-12, from the locked 26S structure sheets).

Builds NEW GLBs into assets/kit/labkit/ (a .gdignore keeps them out of the Godot import and the Web pck until the
wiring step). Today's shapes are kept: every piece is imported from the deployed kit GLB (assets/kit/<key>.glb,
assets/world/containment_ring_v1.glb) and only its material zones change, plus two fixes over --look=lab2:

  1. OWNER RIM ~0.5 m: the platform's flat rim top (r 5.5..6.0, z 0, was OS_Dark = recess) becomes OS_Light, so an
     owned platform shows a 0.5 m band in the owner neon (lab2 drew a 0.28 m band at runtime: 3-4 px at 812 px).
     Neutral OS_Light is the deck cream, no emission (as lab2). No geometry is added.
  2. VAT GOO AT LOW FILL: each tank's glass is cut at 40 % of its height; the lower part gets OS_Glass_Low (much
     clearer, alpha 0.05), the upper part stays OS_Glass (#AECAC7, alpha 0.18); the goo volume is widened to 95 % of
     the glass radius and made dense (opaque, glossy, faint self-light), so a low level still reads.

Zones and values = MATERIALS.md (26S) with the passed lab2 values: decks #E2CFAE, walkways #EAD9BC, satin 0.8, no
metal; detail #718A83; recess #3D5758; glass #AECAC7. Runtime slots keep their names (OS_Light* = player neon,
OS_Ooze* = goo, OS_State* = relay state, OS_Conveyor / OS_Hazard = function cues) so the game's per-name swaps work.

New pieces (no GLB today): Pit_Ring (containment_ring_v1 shape, zoned SHELL / DETAIL inner lip / GOO pool) and the
floor tube samples from SHEET-Floor-Tubes (Floor_Tube_Run_6m 4 lanes on 1.10 m, Floor_Tube_Elbow_R080:
glass r 0.27, goo core r 0.22, 0.28 m shell end sleeves; low axis +0.35 m, crossing +0.97 m).

Run:  blender -b --factory-startup --python build_lab_kit.py -- <repo root>
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "C:/Users/itisf/ooze-wt/lab-kit"
SRC = os.path.join(ROOT, "assets")
OUT = os.path.join(ROOT, "assets", "kit", "labkit")


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# zone: hex, metallic, roughness, alpha, emission strength (of the base colour)
ZONES = {
    "DECK": ("#E2CFAE", 0.0, 0.80, 1.0, 0.0),
    "WALK": ("#EAD9BC", 0.0, 0.80, 1.0, 0.0),
    "DETAIL": ("#718A83", 0.0, 0.62, 1.0, 0.0),
    "RECESS": ("#3D5758", 0.0, 0.80, 1.0, 0.0),
    "GLASS": ("#AECAC7", 0.0, 0.12, 0.18, 0.0),
    "GLASS_LOW": ("#D8ECE8", 0.0, 0.05, 0.05, 0.0),   # fix 2: the bottom 40 % of a tank, almost clear
    "GOO": ("#5E8A86", 0.0, 0.20, 1.0, 0.25),         # neutral goo, dense; the AI tint replaces it at runtime
}
WALKWAYS = ("Deck_", "Pier_", "Relay_Ferry_Rail")


def zone_of(piece, mat):
    walk = piece.startswith(WALKWAYS)
    top = "WALK" if walk else "DECK"
    return {"OS_Plate": top, "OS_Shell": "DECK", "OS_Steel": "DETAIL" if walk else "DECK",
            "OS_Dark": "RECESS", "OS_Recess": "RECESS", "OS_Glass": "GLASS", "OS_Glass_Low": "GLASS_LOW",
            "OS_Light": top, "OS_Ooze_Neutral": "GOO", "OS_Detail": "DETAIL"}.get(mat)


def make_mat(name, zone):
    hx, met, rough, alpha, emit = ZONES[zone]
    col = lin(hx)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    bsdf.inputs["Metallic"].default_value = met
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*col, 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
        m.use_backface_culling = False
    m.diffuse_color = (*col, alpha)
    return m


def base_name(n):
    return n.split(".")[0]


def rezone(piece):
    """Swap every zoned material slot for a fresh lab material; runtime-only slots keep their source material
    (renamed to the bare base name)."""
    made = {}
    src = {m: base_name(m.name) for m in bpy.data.materials}       # original base names, before any rename
    for m in src:
        m.name = "_src_" + m.name
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for slot in ob.material_slots:
            if slot.material is None:
                continue
            b = src.get(slot.material) or base_name(slot.material.name)
            if b not in made:
                z = zone_of(piece, b)
                if z is None:                                       # runtime slot: keep the source material
                    slot.material.name = b
                    made[b] = slot.material
                else:
                    made[b] = make_mat(b, z)
            slot.material = made[b]
    return sorted(made)


def slot_index(ob, name, zone_piece):
    for i, m in enumerate(ob.data.materials):
        if m and base_name(m.name) == name:
            return i
    ob.data.materials.append(make_mat(name, zone_of(zone_piece, name)))
    return len(ob.data.materials) - 1


# ------------------------------------------------------------------ fix 1: owner rim on platforms
def rim_band(ob, piece):
    me = ob.data
    light = slot_index(ob, "OS_Light", piece)
    n = 0
    for p in me.polygons:
        c = p.center
        r = math.hypot(c.x, c.y)
        if 5.5 <= r <= 6.02 and abs(c.z) < 0.01 and p.normal.z > 0.9 \
                and base_name(me.materials[p.material_index].name) == "OS_Dark":
            p.material_index = light
            n += 1
    area = sum(p.area for p in me.polygons if p.material_index == light and p.normal.z > 0.9 and abs(p.center.z) < 0.01)
    return "rim faces %d, top area %.1f m2 (0.5 m annulus = %.1f)" % (n, area, math.pi * (6.0 ** 2 - 5.5 ** 2))


# ------------------------------------------------------------------ fix 2: vat goo readable when low
def _islands(bm, faces):
    faces, out = set(faces), []
    while faces:
        f = faces.pop()
        isl, stack = {f}, [f]
        while stack:
            g = stack.pop()
            for e in g.edges:
                for h in e.link_faces:
                    if h in faces:
                        faces.remove(h)
                        isl.add(h)
                        stack.append(h)
        out.append(isl)
    return out


def _bbox(isl):
    vs = {v for f in isl for v in f.verts}
    return [min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs),
            max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)]


def _clusters(islands, pad=0.06):
    """Decimation splits one tank into many islands: merge islands whose boxes touch (union-find)."""
    boxes = [_bbox(i) for i in islands]
    parent = list(range(len(islands)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i in range(len(islands)):
        for j in range(i + 1, len(islands)):
            a, b = boxes[i], boxes[j]
            if all(a[k] - pad <= b[k + 3] and b[k] - pad <= a[k + 3] for k in range(3)):
                parent[find(i)] = find(j)
    out = {}
    for i, isl in enumerate(islands):
        out.setdefault(find(i), set()).update(isl)
    return list(out.values())


def _tank(isl):
    x0, y0, z0, x1, y1, z1 = _bbox(isl)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    vs = {v for f in isl for v in f.verts}
    mid = [v for v in vs if z0 + 0.1 * (z1 - z0) < v.co.z < z1 - 0.1 * (z1 - z0)] or list(vs)
    rmin = min(math.hypot(v.co.x - cx, v.co.y - cy) for v in mid)
    return (cx, cy, z0, z1, rmin, isl)


def vat_goo(ob, piece):
    me = ob.data
    gi = slot_index(ob, "OS_Glass", piece)
    oi = slot_index(ob, "OS_Ooze_Neutral", piece)
    low = slot_index(ob, "OS_Glass_Low", piece)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    tanks = [_tank(c) for c in _clusters(_islands(bm, [f for f in bm.faces if f.material_index == gi]))]
    log = []
    for cx, cy, z0, z1, rmin, isl in tanks:                      # cut each glass tank at 40 % height
        zc = z0 + 0.4 * (z1 - z0)
        geom = list(isl) + list({e for f in isl for e in f.edges}) + list({v for f in isl for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, zc), plane_no=(0, 0, 1))
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        if f.material_index != gi:
            continue
        c = f.calc_center_median()
        for cx, cy, z0, z1, rmin, isl in tanks:
            if z0 - 0.01 <= c.z <= z1 + 0.01 and math.hypot(c.x - cx, c.y - cy) <= rmin * 1.4 + 0.1:
                if c.z < z0 + 0.4 * (z1 - z0):
                    f.material_index = low
                break
    for isl in _clusters(_islands(bm, [f for f in bm.faces if f.material_index == oi])):   # widen the goo
        vs = list({v for f in isl for v in f.verts})                                         # to 95 % of its glass
        gx = (min(v.co.x for v in vs) + max(v.co.x for v in vs)) / 2
        gy = (min(v.co.y for v in vs) + max(v.co.y for v in vs)) / 2
        gr = max(math.hypot(v.co.x - gx, v.co.y - gy) for v in vs)
        tank = min(tanks, key=lambda t: math.hypot(t[0] - gx, t[1] - gy))
        k = min(1.12, 0.95 * tank[4] / gr) if gr > 0 else 1.0
        k = max(k, 1.0)
        for v in vs:
            v.co.x = gx + (v.co.x - gx) * k
            v.co.y = gy + (v.co.y - gy) * k
        log.append("goo r %.2f->%.2f in glass r %.2f" % (gr, gr * k, tank[4]))
    bm.to_mesh(me)
    bm.free()
    return "%d tanks cut at 40 %%; %s" % (len(tanks), "; ".join(log))


# ------------------------------------------------------------------ pit
def pit_zones(ob, piece):
    me = ob.data
    for m in list(me.materials):
        pass
    me.materials.clear()
    names = ["OS_Shell", "OS_Detail", "OS_Ooze_Neutral"]
    for n in names:
        me.materials.append(bpy.data.materials.get(n) or make_mat(n, zone_of(piece, n)))
    cnt = [0, 0, 0]
    for p in me.polygons:
        c = p.center
        r = math.hypot(c.x, c.y)
        if r < 3.45 and c.z < 0.7 and p.normal.z > 0.7:
            k = 2                                                # the pool surface
        elif r < 4.05 and c.z < 0.85:
            k = 1                                                # the darker inner lip (sheet: DETAIL band)
        elif c.z < 0.12 and abs(p.normal.z) < 0.7:
            k = 1                                                # the base strip at the floor
        else:
            k = 0
        p.material_index = k
        cnt[k] += 1
    return "faces shell %d / detail %d / goo %d" % tuple(cnt)


# ------------------------------------------------------------------ floor tubes (new, from SHEET-Floor-Tubes)
TUBE_R, GOO_R, SLEEVE_L, SLEEVE_R = 0.27, 0.22, 0.28, 0.30
LOW_Y, CROSS_Y, LANE = 0.35, 0.97, 1.10


def _mesh_obj(name, bm, mat):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _cyl_x(bm, x0, x1, y, z, r, segs=20, ring=None):
    """Cylinder along X; ring=(r_in) makes a hollow sleeve (tube between r_in and r)."""
    m = Matrix.Translation(((x0 + x1) / 2, y, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    if ring is None:
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=x1 - x0, matrix=m)
        return
    rings = []
    for rr, xx in ((r, x0), (r, x1), (ring, x1), (ring, x0)):
        rings.append([bm.verts.new((xx, y + rr * math.cos(2 * math.pi * i / segs), z + rr * math.sin(2 * math.pi * i / segs)))
                      for i in range(segs)])
    for k in range(4):
        a, b = rings[k], rings[(k + 1) % 4]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))


def _elbow(bm, R, r, z, lead=0.0, end=math.pi / 2, segs=20, steps=12):
    """One closed tube: a straight lead along +X from (-lead, 0) to (0, 0), then a quarter bend of centreline radius R
    round (0, R) to (R, R) heading +Y; capped at both ends only."""
    frames = [(-lead, 0.0, 0.0)] if lead else []
    frames += [(R * math.sin(a), R - R * math.cos(a), a) for a in (end * s / steps for s in range(steps + 1))]
    rings = []
    for cx, cy, a in frames:
        px, py = -math.sin(a), math.cos(a)                       # plan normal of the centreline
        rings.append([bm.verts.new((cx + px * r * math.cos(t), cy + py * r * math.cos(t), z + r * math.sin(t)))
                      for t in (2 * math.pi * i / segs for i in range(segs))])
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def floor_tubes(kind):
    mats = {n: make_mat(n, zone_of("Floor", n)) for n in ("OS_Glass", "OS_Ooze_Neutral", "OS_Shell")}
    root = bpy.data.objects.new(kind, None)
    bpy.context.scene.collection.objects.link(root)
    g, o, s = bmesh.new(), bmesh.new(), bmesh.new()
    if kind == "Floor_Tube_Run_6m":
        for k in range(4):
            y = (k - 1.5) * LANE
            _cyl_x(g, -3.0, 3.0, y, LOW_Y, TUBE_R)
            _cyl_x(o, -2.98, 2.98, y, LOW_Y, GOO_R)
            for x0 in (-3.0, 3.0 - SLEEVE_L):                    # ring sleeves over the glass ends (2 mm clear)
                _cyl_x(s, x0, x0 + SLEEVE_L, y, LOW_Y, SLEEVE_R, ring=TUBE_R + 0.002)
    elif kind == "Floor_Tube_Elbow_R080":
        _elbow(g, 0.80, TUBE_R, LOW_Y, lead=1.2)
        _elbow(o, 0.80, GOO_R, LOW_Y, lead=1.18, end=math.pi / 2 - 0.02 / 0.80)
        _cyl_x(s, -1.2, -1.2 + SLEEVE_L, 0, LOW_Y, SLEEVE_R, ring=TUBE_R + 0.002)
    for nm, b, mk in (("Glass", g, "OS_Glass"), ("Goo", o, "OS_Ooze_Neutral"), ("Sleeves", s, "OS_Shell")):
        ob = _mesh_obj(nm, b, mats[mk])
        ob.parent = root
    return "built"


# ------------------------------------------------------------------ pieces
PIECES = [("kit/Platform_Standard", "Platform_Standard", "platform"),
          ("kit/Platform_Pillar", "Platform_Pillar", "platform"),
          ("kit/Platform_Relay_v3", "Platform_Relay_v3", "platform"),
          ("kit/Deck_S", "Deck_S", ""),
          ("kit/Pier_Connector", "Pier_Connector", "")]
PIECES += [("kit/Pier_Angled_%02d" % a, "Pier_Angled_%02d" % a, "") for a in range(0, 85, 5)]
PIECES += [("kit/Deck_Conveyor_Belt_v4_%d" % n, "Deck_Conveyor_Belt_v4_%d" % n, "") for n in (2, 4, 6, 8, 10, 12, 14, 16, 20)]
PIECES += [("kit/Vat_T%d" % t, "Vat_T%d" % t, "vat") for t in (1, 2, 3, 4)]
PIECES += [("kit/Relay_Mount", "Relay_Mount", "")]
# Relay_Button_*: not on the 26S sheets (lab2 recolours cover them); their deployed Glyph / Strut fail the BVH check.
PIECES += [("world/containment_ring_v1", "Pit_Ring", "pit")]
PIECES += [(None, n, "tube") for n in ("Floor_Tube_Run_6m", "Floor_Tube_Elbow_R080")]   # crossings: procedural, on the connector blocks


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_extras=True,
                              export_apply=False, export_cameras=False, export_lights=False,
                              export_tangents=False, export_animations=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    for src, name, kind in PIECES:
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        note = ""
        if kind == "tube":
            note = floor_tubes(name)
        else:
            bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, src + ".glb"))
            mats = rezone(name if kind != "pit" else "Pit")
            root = next(o for o in bpy.data.objects if o.parent is None and o.type == "MESH")
            if kind == "pit":
                root.name = root.data.name = name
                note = pit_zones(root, "Pit")
            elif kind == "platform":
                note = rim_band(root, name)
            elif kind == "vat":
                note = vat_goo(root, name)
            else:
                note = "zones " + ",".join(mats)
        for m in list(bpy.data.materials):
            if m.users == 0:
                bpy.data.materials.remove(m)
        path = os.path.join(OUT, name + ".glb")
        export(path)
        print("LABKIT %-28s %8d  %s" % (name, os.path.getsize(path), note))


main()
