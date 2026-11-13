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
            "OS_Light": top, "OS_Ooze_Neutral": "GOO", "OS_Detail": "DETAIL",
            "OS_Gunmetal": "DETAIL", "OS_Light_A": top, "OS_Ooze_A": "GOO"}.get(mat)   # Googatling (Machinegoon v2) slots


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


PLINTH_R = {"Vat_T1": 1.7, "Vat_T2": 1.8, "Vat_T3": 1.9, "Vat_T4": 2.05}   # build_kit_2_0.VAT_SIZES
PLINTH_TOP = 0.40                                                          # SOCKET_Z + PLINTH_H


def vat_neon(ob, piece):
    """Designer 4 (2026-11-12, on a1c5075): neon is a thin rim only. On a vat the player neon stays on the base ring (the
    plinth's lit halo ring) and the spire's glowing tip; cap rings, dashed bands, the vertical slot, fin strips, door
    edges, nozzle mouths and clamp lights move to OS_Detail (#718A83)."""
    me = ob.data
    li = slot_index(ob, "OS_Light", piece)
    di = slot_index(ob, "OS_Detail", piece)
    pr = PLINTH_R[piece]
    ztop = max(v.co.z for v in me.vertices)
    kept_ring = kept_tip = moved = 0
    for p in me.polygons:
        if p.material_index != li:
            continue
        c = p.center
        r = math.hypot(c.x, c.y)
        if pr - 0.40 <= r <= pr - 0.21 and PLINTH_TOP - 0.03 <= c.z <= PLINTH_TOP + 0.07:
            kept_ring += 1
        elif r < 0.25 and c.z > ztop - 0.6:
            kept_tip += 1
        else:
            p.material_index = di
            moved += 1
    return "neon kept: base ring %d faces, tip %d; moved to detail %d" % (kept_ring, kept_tip, moved)


def vat_caps(ob, piece):
    """Daniele via Designer 4 (2026-11-12): "the top of the vats either full white or add a neon circle; right now just seem a
    badly painted skin" -> every tank cap and the main spire cap are SOLID shell cream (OS_Shell, #E2CFAE): the slate band,
    its (former neon) dashes and the cap ring become shell; no neon on the caps (the spire tip keeps its neon)."""
    me = ob.data
    names = [base_name(m.name) if m else "" for m in me.materials]
    shell = slot_index(ob, "OS_Shell", piece)
    paint = {i for i, n in enumerate(names) if n in ("OS_Dark", "OS_Detail", "OS_Recess")}
    bm = bmesh.new()
    bm.from_mesh(me)
    glass = [f for f in bm.faces if names[f.material_index].startswith("OS_Glass")]
    tanks = [_tank(c) for c in _clusters(_islands(bm, glass))]
    ztop = max(v.co.z for v in bm.verts)
    col_z1 = ztop - 1.83                                    # build_kit_2_0.vat_spire: tip top = col_z1 + 1.83
    caps = head = 0
    for f in bm.faces:
        if f.material_index not in paint:
            continue
        c = f.calc_center_median()
        for cx, cy, z0, z1, rmin, isl in tanks:
            if math.hypot(c.x - cx, c.y - cy) <= rmin * 1.2 + 0.05 and z1 - 0.05 <= c.z <= z1 + 0.45:
                f.material_index = shell
                caps += 1
                break
        else:
            if math.hypot(c.x, c.y) < 1.25 and col_z1 - 0.3 <= c.z <= ztop - 0.6:
                f.material_index = shell
                head += 1
    bm.to_mesh(me)
    bm.free()
    return "caps to shell: tank caps %d faces, spire cap %d" % (caps, head)


CAPNEON = "--capneon" in sys.argv


TANK_R = {"Vat_T1": 0.86, "Vat_T2": 0.92, "Vat_T3": 0.95, "Vat_T4": 1.0}       # build_kit_2_0.VAT_SIZES tank radius


def _prim(bm, kind, c, r0, r1, h, mi, segs=64):
    """Clean primitive into bm: 'cyl' (r0), 'cone' (r0 bottom, r1 top) or 'tube' (r0 inner, r1 outer), centred at c,
    height h; flat caps, smooth sides."""
    x, y, z = c
    if kind == "tube":
        rows = []
        for r, zz in ((r1, z - h / 2), (r1, z + h / 2), (r0, z + h / 2), (r0, z - h / 2)):
            rows.append([bm.verts.new((x + r * math.cos(2 * math.pi * i / segs), y + r * math.sin(2 * math.pi * i / segs), zz))
                         for i in range(segs)])
        fs = []
        for k in range(4):
            A, B = rows[k], rows[(k + 1) % 4]
            for i in range(segs):
                j = (i + 1) % segs
                fs.append(bm.faces.new((A[i], A[j], B[j], B[i])))
    else:
        res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0,
                                    radius2=r1 if kind == "cone" else r0, depth=h, matrix=Matrix.Translation((x, y, z)))
        fs = list({f for v in res["verts"] for f in v.link_faces})
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    for f in fs:
        f.material_index = mi
        f.smooth = abs(f.normal.z) < 0.5
    return fs


def vat_strip_goo(ob, piece):
    """Daniele 2026-11-12 (on the spire's front strip): "add goo color to this strip it should fill as much as the vats". The
    front strip (build_kit_2_0.vat_spire: 0.06 x 0.12 m bar at 0.86 m in front, base + 2.4 up to col_z1 - 0.4 / - 0.9 with
    dots) moves from OS_Detail to OS_Ooze_Neutral: it takes the AI goo tint and, as its own goo island, the same runtime fill
    cut as the tanks (scenery.gd). T4 has no strip (its glass core is the gauge)."""
    if piece == "Vat_T4":
        return "strip: none (T4)"
    me = ob.data
    names = [base_name(m.name) if m else "" for m in me.materials]
    det = [i for i, n in enumerate(names) if n == "OS_Detail"]
    goo = slot_index(ob, "OS_Ooze_Neutral", piece)
    cz = max(v.co.z for v in me.vertices) - 1.83
    z1 = cz - (0.9 if piece == "Vat_T3" else 0.4) + 0.05
    n = 0
    for p in me.polygons:
        c = p.center
        if p.material_index in det and abs(c.x) < 0.1 and -0.95 < c.y < -0.8 and 2.3 < c.z < z1:
            p.material_index = goo
            n += 1
    return "strip goo %d faces" % n


def vat_clean_caps(ob, piece):
    """Daniele 2026-11-12 (in Blender, on the capneon variant): "the cream caps seem the top of them is made of too many
    polygons and looks jagged fix the model of all of them". The deployed vats are decimated, so the cap faces are deleted
    and the caps rebuilt clean (64 segments, flat tops, smooth sides) from build_kit_2_0's own dimensions, all solid OS_Shell
    cream except the spire tip (OS_Light): tank cap = band r 1.08 x 0.26 + top plate r 1.0 x 0.06 + boss r 0.38 x 0.14;
    spire = head r 0.95 x 0.5 + crown lip r 0.975 + cone r 0.9 -> 0.42 + steel boss r 0.26 + tip r 0.16 (T4: also its core
    collar). A tank with another tank stacked on it keeps its hidden centre (under the upper bowl): only its outer band /
    plate ring (>= 0.72 r) is rebuilt."""
    me = ob.data
    shell = slot_index(ob, "OS_Shell", piece)
    light = slot_index(ob, "OS_Light", piece)
    names = [base_name(m.name) if m else "" for m in me.materials]
    keep = {i for i, n in enumerate(names) if n.startswith("OS_Glass") or n.startswith("OS_Ooze")}
    bm = bmesh.new()
    bm.from_mesh(me)
    tanks = [_tank(c) for c in _clusters(_islands(bm, [f for f in bm.faces if names[f.material_index].startswith("OS_Glass")]))]
    ztop = max(v.co.z for v in bm.verts)
    cz = ztop - 1.83                                             # build_kit_2_0.vat_spire col_z1
    r = TANK_R[piece]
    t4 = piece == "Vat_T4"
    side = [t for t in tanks if t[3] - t[2] < 3.0]
    caps = []                                                    # (cx, cy, zt, stacked)
    for cx, cy, z0, z1, rmin, isl in side:
        stacked = any(abs(o[0] - cx) < 0.3 and abs(o[1] - cy) < 0.3 and o[2] > z1 for o in side)
        caps.append((cx, cy, z1, stacked))
    dead = set()
    for f in bm.faces:
        if f.material_index in keep:
            continue
        c = f.calc_center_median()
        for cx, cy, zt, stacked in caps:
            d = math.hypot(c.x - cx, c.y - cy)
            if stacked:
                if 0.72 * r <= d <= 1.14 * r and zt - 0.005 <= c.z <= zt + 0.33:
                    dead.add(f)
            elif d <= 1.14 * r and zt - 0.005 <= c.z <= zt + 0.47:
                dead.add(f)
        rr = math.hypot(c.x, c.y)
        if t4:
            rail = abs(c.y) < 0.25 and abs(c.x) > 0.9 and c.z < cz + 0.12
            if rr <= 1.21 and c.z >= cz - 0.26 and not rail:
                dead.add(f)
        elif rr <= 1.0 and c.z >= cz - 0.002:
            dead.add(f)
    bmesh.ops.delete(bm, geom=list(dead), context="FACES")
    for cx, cy, zt, stacked in caps:
        if stacked:
            _prim(bm, "tube", (cx, cy, zt + 0.13), 0.72 * r, 1.08 * r, 0.26, shell)
            _prim(bm, "tube", (cx, cy, zt + 0.28), 0.72 * r, 1.0 * r, 0.06, shell)
        else:
            _prim(bm, "cyl", (cx, cy, zt + 0.13), 1.08 * r, 0, 0.26, shell)
            _prim(bm, "cyl", (cx, cy, zt + 0.28), 1.0 * r, 0, 0.06, shell)
            _prim(bm, "cyl", (cx, cy, zt + 0.37), 0.38 * r, 0, 0.14, shell, segs=48)
    if t4:
        _prim(bm, "cyl", (0, 0, cz - 0.12), 1.16, 0, 0.26, shell)
        _prim(bm, "cyl", (0, 0, cz + 0.04), 1.18, 0, 0.05, shell)
        _prim(bm, "cone", (0, 0, cz + 0.2), 1.12, 0.95, 0.3, shell)
    _prim(bm, "cyl", (0, 0, cz + 0.25), 0.95, 0, 0.5, shell)
    _prim(bm, "cyl", (0, 0, cz + 0.22), 0.975, 0, 0.09, shell)
    _prim(bm, "cone", (0, 0, cz + 0.8), 0.9, 0.42, 0.6, shell)
    _prim(bm, "cyl", (0, 0, cz + 1.2), 0.26, 0, 0.3, shell, segs=32)
    _prim(bm, "cyl", (0, 0, cz + 1.58), 0.16, 0, 0.5, light, segs=32)
    bm.to_mesh(me)
    bm.free()
    return "clean caps: %d tank caps (%d stacked) + spire cap, %d faces replaced" % (len(caps), sum(c[3] for c in caps), len(dead))


def vat_capneon(ob, piece):
    """VARIANT (Daniele's sketch via Designer 4, 2026-11-12; "love it" 2026-11-12): a THIN player-neon ring (OS_Light, the base
    ring's runtime slot) in the step between each exposed tank cap and its boss, and round the spire's steel boss. Child mesh
    "CapNeon": flat annuli 0.012 m thick seated 2 mm over the clean cap plates (vat_clean_caps). Tanks with a tank stacked on
    them get none (hidden under the upper bowl)."""
    me = ob.data
    li = slot_index(ob, "OS_Light", piece)
    names = [base_name(m.name) if m else "" for m in me.materials]
    bm = bmesh.new()
    bm.from_mesh(me)
    side = [t for t in (_tank(c) for c in _clusters(_islands(bm, [f for f in bm.faces if names[f.material_index].startswith("OS_Glass")])))
            if t[3] - t[2] < 3.0]
    ztop = max(v.co.z for v in bm.verts)
    bm.free()
    r = TANK_R[piece]
    rings = [(cx, cy, 0.6 * r, 0.8 * r, z1 + 0.312) for cx, cy, z0, z1, rm, isl in side
             if not any(abs(o[0] - cx) < 0.3 and abs(o[1] - cy) < 0.3 and o[2] > z1 for o in side)]
    rings.append((0.0, 0.0, 0.29, 0.41, ztop - 1.83 + 1.102))
    out = bmesh.new()
    for cx, cy, ri, ro, z in rings:
        _prim(out, "tube", (cx, cy, z + 0.006), ri, ro, 0.012, 0)
    rm = bpy.data.meshes.new("CapNeon")
    out.to_mesh(rm)
    out.free()
    rm.materials.append(me.materials[li])
    ring_ob = bpy.data.objects.new("CapNeon", rm)
    for c in ob.users_collection:
        c.objects.link(ring_ob)
    ring_ob.parent = ob
    return "capneon rings %d" % len(rings)


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


# ------------------------------------------------------------------ lab-kit 2: structures (Daniele 2026-11-12: "make all the
# other structure in the new style (laser/forge/googatling/goocannon)"). Same language as the final (capneon) vats: cream shell,
# slate recess bands, detail #718A83, glass, goo where liquid shows; player neon only as thin rings: the plinth's halo ring (kept
# in place, as on the vats) and one clean ring per cap. Silhouettes unchanged; runtime slot names kept.
PLINTH = {"Cannon": (1.75, 0.40), "Laser": (1.75, 0.40), "Forge": (2.3, 0.62)}   # build_kit_2_0.structure_plinth r, top


def _family(piece):
    return piece.split("_")[0]


def struct_neon(ob, piece, keep=None):
    """Every OS_Light* face -> OS_Detail except the plinth's halo ring (r - 0.36 .. r - 0.25 on the plinth top) and the
    faces `keep(centre)` accepts. Returns kept / moved counts."""
    me = ob.data
    names = [base_name(m.name) if m else "" for m in me.materials]
    lights = {i for i, n in enumerate(names) if n.startswith("OS_Light")}
    if not lights:
        return "neon: none"
    di = slot_index(ob, "OS_Detail", piece)
    pr, top = PLINTH.get(_family(piece), (None, None))
    mw = ob.matrix_world
    ring = kept = moved = 0
    for p in me.polygons:
        if p.material_index not in lights:
            continue
        c = mw @ p.center
        r = math.hypot(c.x, c.y)
        if pr and pr - 0.38 <= r <= pr - 0.23 and top - 0.01 <= c.z <= top + 0.05 and p.normal.z > 0.5:
            ring += 1
        elif keep and keep(c):
            kept += 1
        else:
            p.material_index = di
            moved += 1
    return "neon kept: halo %d, caps %d; moved to detail %d" % (ring, kept, moved)


def tower_head(ob, piece, tier):
    """build_kit_2_0.cannon head: the decimated cone / emitter lens / emitter tube are deleted and rebuilt clean (64 seg);
    the lens is detail, the tube recess, and a THIN neon ring (0.09 x 0.012 m, OS_Light) sits on the tube top (capneon)."""
    me = ob.data
    z = 0.06 + 2.4 + 1.18 * tier
    plate = slot_index(ob, "OS_Plate", piece)
    det = slot_index(ob, "OS_Detail", piece)
    dark = slot_index(ob, "OS_Dark", piece)
    light = slot_index(ob, "OS_Light", piece)
    bm = bmesh.new()
    bm.from_mesh(me)
    dead = [f for f in bm.faces if not me.materials[f.material_index].name.startswith("OS_Glass")
            and math.hypot(*f.calc_center_median().xy) <= 1.01 and f.calc_center_median().z >= z + 0.505]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    _prim(bm, "cone", (0, 0, z + 0.68), 1.0, 0.62, 0.36, plate)
    _prim(bm, "cyl", (0, 0, z + 0.88), 0.5, 0, 0.06, det, segs=48)
    _prim(bm, "tube", (0, 0, z + 0.89), 0.5, 0.62, 0.10, dark)
    _prim(bm, "tube", (0, 0, z + 0.94 + 0.008), 0.515, 0.605, 0.012, light)
    bm.to_mesh(me)
    bm.free()
    return "head rebuilt clean at z %.2f (%d faces replaced), emitter ring" % (z, len(dead))


def _world_tree():
    from mathutils.bvhtree import BVHTree
    vs, fs = [], []
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        k = len(vs)
        vs += [o.matrix_world @ v.co for v in o.data.vertices]
        fs += [[k + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(vs, fs)


SEAT_LOG = []


def _seat(tree, cx, cy, r0, r1, n=16, z_from=30.0):
    """Top surface height under an annulus (rays straight down from z_from); None unless flat within 4 mm."""
    zs = []
    for r in (r0, (r0 + r1) / 2, r1):
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            h = tree.ray_cast(Vector((cx + r * math.cos(a), cy + r * math.sin(a), z_from)), Vector((0, 0, -1)))
            if h[0] is None:
                return None
            zs.append(h[0].z)
    zs.sort()
    SEAT_LOG.append("seat (%.2f,%.2f) r %.2f-%.2f: z %.3f..%.3f median %.3f" % (cx, cy, r0, r1, zs[0], zs[-1], zs[len(zs) // 2]))
    return max(zs) if max(zs) - min(zs) <= 0.004 else None


def _ring_object(root, rings, mat, name):
    """Child mesh of thin flat annuli (world coords) on `mat` (the piece's own OS_Light slot)."""
    out = bmesh.new()
    for cx, cy, ri, ro, z in rings:
        _prim(out, "tube", (cx, cy, z + 0.002 + 0.006), ri, ro, 0.012, 0)
    me = bpy.data.meshes.new(name)
    out.to_mesh(me)
    out.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    for c in root.users_collection:
        c.objects.link(ob)
    ob.parent = root
    ob.matrix_parent_inverse = root.matrix_world.inverted()
    return ob


def gatling(piece):
    """Googatling (Machinegoon_T1..T3 = Base + Turret): every OS_Light_A face -> detail; NEW thin neon rings on OS_Light_A:
    a base ring on the flat gunmetal ledge (r 1.47 .. 1.55, z 0.94) and one ring on each tank's cap (0.50 .. 0.64 of its
    glass half-width), seated by ray casts and only where the surface is flat."""
    base = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is None)
    tur = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is base)
    notes = [struct_neon(base, piece), struct_neon(tur, piece)]
    notes.append(drum_doors(base, piece))   # doors set into the drum, inside the base's footprint (v3)
    light = next(m for m in tur.data.materials if m and base_name(m.name) == "OS_Light_A")
    tree = _world_tree()
    rings = []
    del SEAT_LOG[:]
    z = None
    for r0, r1 in ((1.51, 1.575), (1.515, 1.575), (1.52, 1.575), (1.51, 1.565)):   # the flat gunmetal ledge (a steel slope reaches r 1.50)
        z = _seat(tree, 0, 0, r0, r1, n=36, z_from=1.0)    # under the turret (T3 lowest part 1.03 m; ring top 0.956)
        if z is not None:
            rings.append((0, 0, r0, r1, z))
            break
    names = [base_name(m.name) if m else "" for m in tur.data.materials]
    bm = bmesh.new()
    bm.from_mesh(tur.data)
    bm.transform(tur.matrix_world)
    caps = 0
    tanks = []                                                    # glass panels -> one box per tank (grouped in plan)
    for isl in _islands(bm, [f for f in bm.faces if names[f.material_index].startswith("OS_Glass")]):
        b = _bbox(isl)
        cx, cy = (b[0] + b[3]) / 2, (b[1] + b[4]) / 2
        t = next((t for t in tanks if math.hypot(t[0] - cx, t[1] - cy) < 0.15), None)
        if t is None:
            tanks.append([cx, cy, b])
        else:
            t[2] = [min(t[2][k], b[k]) for k in range(3)] + [max(t[2][k], b[k]) for k in range(3, 6)]
    for _, _, (x0, y0, z0, x1, y1, z1) in tanks:
        cx, cy, hw = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2
        zc = _seat(tree, cx, cy, 0.50 * hw, 0.64 * hw, z_from=z1 + 1.0)
        if zc is not None and zc > z1 - 0.05:
            rings.append((cx, cy, 0.50 * hw, 0.64 * hw, zc))
            caps += 1
            notes.append(cream(tur, piece, lambda c, cx=cx, cy=cy, hw=hw, z1=z1:       # the tank's cap -> cream
                               math.hypot(c.x - cx, c.y - cy) <= 1.25 * hw and c.z >= z1 - 0.02))
    bm.free()
    _ring_object(base, rings, light, "CapNeon")
    print("\n".join(SEAT_LOG))
    return " | ".join(notes) + " | rings: base %s, tank caps %d" % ("yes" if z is not None else "NO", caps)


def goocannon(piece):
    """Goocannon = the launcher turret (Relay_Cannon_v4 / _T2 / _T3), REMADE as clean kit geometry. Daniele 2026-11-12: "the
    cannon needs to be remade in blender as the original rodin model ... very hard to paint and would look different then
    other models in game", then (on the first remake) "too lowquality make it more complicated and closer to the original
    expecially T2vs T3 barely any difference". Proportions measured on the deployed GLBs; each tier keeps the original's
    own anatomy:
      T1 = ball head with a belt band, side ring bosses, short ribbed neck, double-ring muzzle; low pedestal.
      T2 = rounded rear ammo capsule (glass goo window + top port), chamfered block body, hex-nut bosses, long ribbed neck,
           banded muzzle with a flared lip; mid pedestal with 4 buttresses.
      T3 = long finned rear tank (goo window, top port, 2 feed pipes), armoured body with a V-ridge roof and angled shoulder
           plates, big ring bosses, heavy cooled muzzle drum with a slotted brake; tall pedestal, buttresses, bolted collar.
    Every tier: dark disc drum, cream plate with a step ring and a bolt ring, +X throw ramp with a centre strip, detail
    collar, cream pedestal with a framed front hatch, detail yoke arms. OS_* slots (owner neon only as thin rings: plinth
    halo, muzzle face, port; goo = AI tint). Head = child on the yoke pivot (the game pitches it and kicks it along -X);
    every head part stays >= 5 mm clear of the base (BVH)."""
    T = {"Relay_Cannon_v4": dict(R=4.62, Hd=0.75, piv=3.21, top=2.25, col=2.6, p0=2.3, p1=1.9, fins=0, bolts=12),
         "Relay_Cannon_v4_T2": dict(R=4.32, Hd=0.6, piv=3.72, top=2.9, col=2.47, p0=2.25, p1=1.85, fins=4, bolts=12),
         "Relay_Cannon_v4_T3": dict(R=4.85, Hd=0.7, piv=4.26, top=3.4, col=2.73, p0=2.55, p1=2.05, fins=4, bolts=16)}[piece]
    tier = 1 if piece == "Relay_Cannon_v4" else int(piece[-1])
    names = ["OS_Shell", "OS_Detail", "OS_Dark", "OS_Light", "OS_Glass", "OS_Ooze_Neutral"]
    mats = [make_mat(n, zone_of("Goocannon", n)) for n in names]
    SH, DE, DK, LI, GL, GO = range(6)

    def ax(bm, kind, c, r0, r1, h, mi, axis, segs=64):
        """_prim along X or Y (built on Z at the origin, turned, moved to c)."""
        fs = _prim(bm, kind, (0, 0, 0), r0, r1, h, mi, segs)
        vs = list({v for f in fs for v in f.verts})
        if axis == "X":
            bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
        elif axis == "Y":
            bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "X"))
        bmesh.ops.translate(bm, verts=vs, vec=c)
        a = Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis])
        for f in fs:
            f.normal_update()
            f.smooth = abs(f.normal.dot(a)) < 0.5
        return fs

    def box(bm, c, s, mi, bev=0.0, rz=0.0, ry=0.0, rx=0.0):
        M = (Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
             @ Matrix.Diagonal((*s, 1)))
        r = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
        vs = r["verts"]
        for f in {f for v in vs for f in v.link_faces}:
            f.material_index = mi
            f.smooth = False
        if bev:
            bmesh.ops.bevel(bm, geom=vs + list({e for v in vs for e in v.link_edges}), offset=bev, offset_type="OFFSET",
                            segments=3, profile=0.5, affect="EDGES", clamp_overlap=True)

    def ball(bm, c, r, mi, sx=1.0):
        res = bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r,
                                        matrix=Matrix.Translation(c) @ Matrix.Diagonal((sx, 1, 1, 1)))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = mi
            f.smooth = True

    def wedge(bm, x0, x1, hw, z0, z1, mi):
        """Ramp: x0..x1 at half width hw, top from z0 (at x0) down to z1 (at x1), bottom on z 0."""
        P = [(x0, -hw, 0), (x1, -hw, 0), (x1, hw, 0), (x0, hw, 0), (x0, -hw, z0), (x1, -hw, z1), (x1, hw, z1), (x0, hw, z0)]
        v = [bm.verts.new(p) for p in P]
        fs = []
        for q in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            f = bm.faces.new([v[i] for i in q])
            f.material_index = mi
            fs.append(f)
        bmesh.ops.recalc_face_normals(bm, faces=fs)

    R, Hd, piv = T["R"], T["Hd"], T["piv"]
    # ---------------------------------------------------------------- base (static)
    b = bmesh.new()
    _prim(b, "cyl", (0, 0, 0.3 * Hd), R, 0, 0.6 * Hd, DK)                         # dark disc drum
    _prim(b, "cyl", (0, 0, 0.8 * Hd), R - 0.08, 0, 0.4 * Hd, SH)                   # cream top plate
    _prim(b, "tube", (0, 0, Hd + 0.03), 0.8 * R, 0.85 * R, 0.06, DE)               # step ring
    _prim(b, "tube", (0, 0, Hd + 0.008), T["col"] + 0.18, T["col"] + 0.3, 0.012, LI)   # thin neon halo on the plate
    n = T["bolts"]
    for i in range(n):                                                           # bolt ring (not under the ramp)
        a = 2 * math.pi * (i + 0.5) / n
        if abs(math.atan2(math.sin(a), math.cos(a))) > 0.42:
            _prim(b, "cyl", ((0.92 * R) * math.cos(a), (0.92 * R) * math.sin(a), Hd + 0.02), 0.1, 0, 0.08, DE, segs=12)
    wedge(b, 2.9, R + 0.35, 1.35, Hd + 0.24, 0.45 * Hd, SH)                       # the throw ramp (+X), past the rim
    wedge(b, 2.9, R + 0.36, 0.25, Hd + 0.255, 0.45 * Hd + 0.015, DE)              # its centre strip
    c0, c1 = Hd, Hd + 0.3
    _prim(b, "cyl", (0, 0, (c0 + c1) / 2), T["col"], 0, c1 - c0, DE)              # detail collar
    if tier == 3:
        for i in range(12):                                                      # bolted collar
            a = 2 * math.pi * (i + 0.5) / 12
            r = (T["col"] + T["p0"]) / 2
            _prim(b, "cyl", (r * math.cos(a), r * math.sin(a), c1 + 0.03), 0.06, 0, 0.08, DK, segs=10)
    hp = T["top"] - c1
    _prim(b, "cone", (0, 0, (c1 + T["top"]) / 2), T["p0"], T["p1"], hp, SH)       # cream pedestal
    _prim(b, "cyl", (0, 0, T["top"] - 0.06), T["p1"] + 0.05, 0, 0.12, DE)         # pedestal cap rim
    tilt = math.atan2(T["p0"] - T["p1"], hp)
    if T["fins"]:                                                                # buttresses on the diagonals
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            rm = (T["p0"] + T["p1"]) / 2 + 0.12
            box(b, (rm * math.cos(a), rm * math.sin(a), c1 + hp * 0.42), (0.55, 0.32, hp * 0.82), DE, bev=0.04, rz=a, ry=tilt)
    else:
        for sy in (-1, 1):                                                       # T1: side fins
            box(b, (0, sy * (T["p0"] - 0.05), c1 + hp * 0.4), (0.5, 0.36, hp * 0.8), DE, bev=0.04)
    # ENTRANCES front (+X, the throw side) + back (Daniele 2026-11-12: the tilted hatches sat "inside its base"): a cream housing
    # standing on the plate (Hd) out of the pedestal, slate foot strip, detail roof slab, framed dark door (0.8 x 0.85 m)
    ri, ro = T["p1"] - 0.1, min(T["p0"] + 0.35, 2.75)                            # ro < 2.9: clear of the throw ramp
    zt = c1 + 1.0
    for sg in (1, -1):
        box(b, (sg * (ri + ro) / 2, 0, (Hd + zt) / 2), (ro - ri, 1.3, zt - Hd), SH)
        box(b, (sg * ((ri + ro) / 2 + 0.01), 0, Hd + 0.04), (ro - ri, 1.33, 0.08), DK)
        box(b, (sg * ((ri + ro) / 2 + 0.04), 0, zt + 0.035), (ro - ri + 0.08, 1.4, 0.07), DE)
        box(b, (sg * (ro + 0.01), 0, Hd + 0.43), (0.04, 0.8, 0.85), DK)               # the door (z Hd + 0.005 .. Hd + 0.855)
        for sy in (-1, 1):
            box(b, (sg * (ro + 0.03), sy * 0.47, Hd + 0.47), (0.06, 0.14, 0.94), DE)    # jambs
        box(b, (sg * (ro + 0.03), 0, Hd + 0.94), (0.06, 1.08, 0.12), DE)               # lintel
    # head numbers (local to the pivot): drum / body, bosses (|y| out to bo), arms (|y| a0..a1)
    H = {1: dict(bo=1.75, br=0.55, dz=0.69),
         2: dict(bo=1.9, br=0.6, dz=1.0),
         3: dict(bo=2.25, br=0.75, dz=1.45)}[tier]
    a0, a1 = H["bo"] + 0.005, H["bo"] + 0.4
    aw = 0.9 if tier < 3 else 1.2
    for sy in (-1, 1):                                                           # yoke arms
        box(b, (0, sy * (a0 + a1) / 2, (T["top"] - 0.05 + piv) / 2), (aw, a1 - a0, piv - T["top"] + 0.05), DE, bev=0.04)
        ax(b, "cyl", (0, sy * (a0 + a1) / 2, piv), aw / 2, 0, a1 - a0, DE, "Y", segs=48)
        ax(b, "cyl", (0, sy * (a1 + 0.01), piv), 0.22, 0, 0.02, DK, "Y", segs=32)   # axle cap
    # ---------------------------------------------------------------- head (pivot at the origin)
    h = bmesh.new()
    dz = H["dz"]

    def boss(y0, y1, r, hexnut):
        for sy in (-1, 1):
            ax(h, "cyl", (0, sy * (y0 + y1) / 2, 0), r, 0, y1 - y0, DE, "Y", segs=48)
            ax(h, "tube", (0, sy * (y1 - 0.06), 0), r - 0.02, r + 0.06, 0.08, SH, "Y", segs=48)   # boss ring
            if hexnut:
                ax(h, "cyl", (0, sy * (y1 - 0.03), 0), 0.32 * r / 0.6, 0, 0.06, DK, "Y", segs=6)
            else:
                ax(h, "cyl", (0, sy * (y1 - 0.01), 0), 0.25, 0, 0.02, DK, "Y", segs=32)

    def muzzle(x0, x1, r, bands, flare, brake=False):
        ax(h, "cyl", ((x0 + x1) / 2, 0, dz), r, 0, x1 - x0, SH, "X")
        for k in range(bands):
            x = x0 + 0.12 + k * (x1 - x0 - 0.24) / max(1, bands - 1)
            ax(h, "cyl", (x, 0, dz), r + 0.05, 0, 0.12, DE, "X")
        if flare:
            ax(h, "cone", (x1 + 0.12, 0, dz), r, r + 0.1, 0.24, SH, "X")
            x1 += 0.24
        if brake:                                                                # slotted brake: dark slots round the lip
            for k in range(6):
                a = 2 * math.pi * k / 6
                box(h, (x1 - 0.35, (r + 0.005) * math.cos(a), dz + (r + 0.005) * math.sin(a)), (0.4, 0.06, 0.24), DK, rx=a)
        ax(h, "cyl", (x1 + 0.01, 0, dz), 0.55 * r, 0, 0.02, DK, "X", segs=48)      # bore
        ax(h, "tube", (x1 + 0.002 + 0.006, 0, dz), 0.64 * r, 0.76 * r, 0.012, LI, "X")   # thin neon ring on the face

    def neck(x0, x1, r, ribs):
        ax(h, "cyl", ((x0 + x1) / 2, 0, dz), r, 0, x1 - x0, DE, "X")
        for k in range(ribs):
            ax(h, "cyl", (x0 + (k + 1) * (x1 - x0) / (ribs + 1), 0, dz), r + 0.07, 0, 0.08, SH, "X")

    def port(x, z):                                                              # hatch / port with a neon ring
        _prim(h, "cyl", (x, 0, z + 0.02), 0.34, 0, 0.24, DE, segs=48)
        _prim(h, "tube", (x, 0, z + 0.14 + 0.008), 0.18, 0.28, 0.012, LI, segs=48)

    def rear_tank(x0, x1, rr, fins, body_x):
        """Rounded ammo capsule along X: a flattened back dome at x0, then (behind the body, which starts at body_x)
        cooling fins and a glass goo window band (the gauge)."""
        de = x0 + 0.55 * rr                                                        # dome end
        ball(h, (de, 0, dz), rr, SH, sx=0.55)
        f0 = de + 0.12
        for k in range(fins):
            ax(h, "cyl", (f0 + k * 0.2, 0, dz), rr + 0.07, 0, 0.07, DE, "X")      # cooling fins
        g0 = f0 + fins * 0.2 + 0.12
        g1 = body_x - 0.2
        ax(h, "cyl", ((de + g0) / 2, 0, dz), rr, 0, g0 - de, SH, "X")             # tank shell, split round the window
        ax(h, "cyl", ((g1 + x1) / 2, 0, dz), rr, 0, x1 - g1, SH, "X")
        ax(h, "cyl", ((g0 + g1) / 2, 0, dz), rr + 0.02, 0, g1 - g0, GL, "X")      # glass window band
        ax(h, "cyl", ((g0 + g1) / 2, 0, dz), rr - 0.08, 0, g1 - g0 - 0.04, GO, "X")   # goo inside (the gauge)
        for x in (g0 - 0.05, g1 + 0.05):
            ax(h, "cyl", (x, 0, dz), rr + 0.06, 0, 0.1, DE, "X")                  # window rims
        return (de + f0) / 2

    if tier == 1:
        Rb, xb = 1.4, -0.95
        ball(h, (xb, 0, dz), Rb, SH)                                              # ball head
        ax(h, "tube", (xb, 0, dz), Rb - 0.03, Rb + 0.04, 0.22, DE, "Y")           # belt band over the top
        ax(h, "cyl", (xb + 1.15, 0, dz), 0.85, 0, 0.3, DE, "X")                   # neck collar
        boss(0.7, H["bo"], H["br"], False)
        neck(0.4, 1.45, 0.7, 2)
        muzzle(1.45, 2.3, 0.95, 2, False)
        port(xb, dz + Rb)
    elif tier == 2:
        box(h, (-0.4, 0, 0.8), (2.0, 2.5, 3.05), SH, bev=0.32)                   # chamfered block body
        box(h, (-0.4, 0, 2.33), (1.4, 1.6, 0.12), DE, bev=0.04)                   # roof plate
        ax(h, "cyl", (0.62, 0, dz), 0.8, 0, 0.24, DE, "X")                        # barrel collar
        boss(1.2, H["bo"], H["br"], True)
        px = rear_tank(-3.41, -1.0, 1.25, 0, -1.4)
        port(px - 0.25, dz + 1.25)
        neck(0.74, 2.0, 0.55, 3)
        muzzle(2.0, 3.67, 1.12, 3, True)
    else:
        box(h, (-0.7, 0, 0.95), (2.6, 3.0, 3.4), SH, bev=0.3)                    # armoured body
        P = [(-1.9, -1.35, 2.62), (0.5, -1.35, 2.62), (0.5, 1.35, 2.62), (-1.9, 1.35, 2.62), (-1.9, 0, 3.05), (0.5, 0, 3.05)]
        v = [h.verts.new(q) for q in P]                                          # V-ridge roof (a prism along X)
        fs = [h.faces.new([v[i] for i in q]) for q in ((0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5))]
        bmesh.ops.recalc_face_normals(h, faces=fs)
        for f in fs:
            f.material_index = DE
        for sy in (-1, 1):
            for zz in (0.2, 1.6):                                                # side armour ribs
                box(h, (-0.7, sy * 1.5, zz), (2.2, 0.08, 0.18), DE, bev=0.03)
        ax(h, "cyl", (0.66, 0, dz), 1.1, 0, 0.3, DE, "X")                         # barrel collar
        boss(1.45, H["bo"], H["br"], False)
        px = rear_tank(-4.3, -1.7, 1.5, 3, -2.0)
        port(px - 0.3, dz + 1.5)
        for sy in (-1, 1):                                                       # feed pipes, tank -> body
            ax(h, "cyl", (-2.2, sy * 0.95, dz - 1.2), 0.16, 0, 1.0, DE, "X", segs=24)
        neck(0.8, 1.6, 0.62, 1)
        muzzle(1.6, 3.4, 1.5, 4, False, brake=True)
    obs = []
    for nm, bm in (("Relay_Cannon_v4", b), ("Head", h)):                          # the game's names in every tier
        me = bpy.data.meshes.new(nm)
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(nm, me)
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    obs[1].parent = obs[0]
    obs[1].location = (0, 0, piv)
    return "remade clean T%d: base %d faces, head %d faces" % (tier, len(obs[0].data.polygons), len(obs[1].data.polygons))


def _rbox(bm, c, s, mi, rz):
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Diagonal((*s, 1)))
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.material_index = mi
        f.smooth = False


def doors(ob, piece, dist, base, angs, w=1.1, hgt=1.5):
    """ENTRANCES (Daniele 2026-11-12: "for every structure including vats we need entrance in the front and the back"): the
    kit's framed door (build_kit_2_0.front_door, scaled to w x hgt) at radius `dist` facing each angle in `angs` (plan
    angle of the door's outward normal: -pi/2 = front -Y, +pi/2 = back +Y). Recess OS_Dark, jambs + lintel OS_Steel (shell
    cream on structures), its former lit outline OS_Detail - the same zones as the existing front doors after rezone."""
    me = ob.data
    dk, st, de = (slot_index(ob, n, piece) for n in ("OS_Dark", "OS_Steel", "OS_Detail"))
    kx, kz = w / 1.1, hgt / 1.5
    bm = bmesh.new()
    bm.from_mesh(me)
    for a in angs:
        def put(dx, dy, z, size, mi):
            x, y = dist + dx, dy * kx
            _rbox(bm, (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a), base + z * kz),
                  (size[0], size[1] * kx, size[2] * kz), mi, a)
        put(0, 0, 0.75, (0.2, 1.1, 1.5), dk)
        for sy in (-1, 1):
            put(0.04, sy * 0.62, 0.8, (0.24, 0.16, 1.6), st)
            put(0.17, sy * 0.54, 0.75, (0.04, 0.05, 1.3), de)
        put(0.04, 0, 1.66, (0.24, 1.4, 0.2), st)
        put(0.17, 0, 1.46, (0.04, 1.1, 0.05), de)
    bm.to_mesh(me)
    bm.free()
    return "doors %d at r %.2f" % (len(angs), dist)


FRONT, BACK = -math.pi / 2, math.pi / 2


FORGE_BLOCK = (-1.65, 1.65, -0.55, 1.65, 0.58, 4.74)       # the deployed Forge block: x0, x1, y0, y1, z0, z1
FORGE_TANK_R, FORGE_TANK_Y = 0.55, 0.55                      # side tanks: glass r, centre y (block centre); half set into the block


def forge_rework(ob, piece):
    """FORGE 2 (Daniele, 2026-11-12: "modify the forge model put the goo vat on left and right side and keep door infront with
    some decoation so it still look good"). Removes the front goo tube + lid, the front radiator fins and the two side add-ons
    (islands centred in front of the block's front face or outside its sides, above the plinth), then adds: a goo tank on each
    side (cream foot collar + cap, glass with two detail bands, goo at 85 %, a feed pipe into the block), a framed front door
    (doors(), the same frame as the back) under a cream canopy on two detail posts, a radiator fin bank either side of the door,
    a slate band and a round vent emblem above. No new neon (halo + chimney rings stay as before)."""
    x0, x1, y0, y1, z0, z1 = FORGE_BLOCK
    me = ob.data
    sh, de, dk, gl, go = (slot_index(ob, n, piece) for n in ("OS_Shell", "OS_Detail", "OS_Dark", "OS_Glass", "OS_Ooze_Neutral"))
    bm = bmesh.new()
    bm.from_mesh(me)
    gone = []
    for isl in _islands(bm, bm.faces[:]):
        bx0, by0, bz0, bx1, by1, bz1 = _bbox(isl)
        cx, cy, cz = (bx0 + bx1) / 2, (by0 + by1) / 2, (bz0 + bz1) / 2
        if bz0 < 0.635 or bz1 > z1 - 0.02 or bx1 - bx0 > 3.5:      # plinth rings, the block itself, the top block / chimneys
            continue
        if cy < y0 - 0.05 or abs(cx) > x1 + 0.02:
            gone.extend(isl)
    n_gone = len(gone)
    bmesh.ops.delete(bm, geom=list(set(gone)), context="FACES")
    # side tanks
    for sx in (-1, 1):
        cx = sx * x1
        _pr(bm, "tube", FORGE_TANK_R - 0.03, FORGE_TANK_R + 0.08, 0.30, sh, (cx, FORGE_TANK_Y, 0.62 + 0.15))      # foot collar
        _pr(bm, "tube", FORGE_TANK_R + 0.08, FORGE_TANK_R + 0.11, 0.06, de, (cx, FORGE_TANK_Y, 0.62 + 0.24))      # its slate band
        _pr(bm, "tube", FORGE_TANK_R - 0.03, FORGE_TANK_R, 3.0, gl, (cx, FORGE_TANK_Y, 0.92 + 1.5))               # glass 0.92..3.92
        _pr(bm, "cyl", FORGE_TANK_R - 0.08, 0, 2.55, go, (cx, FORGE_TANK_Y, 0.94 + 1.275))                         # goo 0.94..3.49
        for zb in (1.9, 2.9):
            _pr(bm, "tube", FORGE_TANK_R + 0.002, FORGE_TANK_R + 0.05, 0.07, de, (cx, FORGE_TANK_Y, zb))          # detail bands
        _pr(bm, "cyl", FORGE_TANK_R + 0.08, 0, 0.26, sh, (cx, FORGE_TANK_Y, 3.92 + 0.13))                          # cap
        _pr(bm, "cyl", FORGE_TANK_R - 0.12, 0, 0.08, de, (cx, FORGE_TANK_Y, 4.18 + 0.04))                          # cap boss
        _pr(bm, "cyl", 0.18, 0, 0.06, dk, (cx, FORGE_TANK_Y, 4.26 + 0.03))                                         # filler port
    # front: canopy on two posts, fin banks, slate band, vent emblem
    yf = y0
    _rbox(bm, (0, yf - 0.32, 2.52), (2.1, 0.66, 0.12), sh, 0)                     # canopy
    _rbox(bm, (0, yf - 0.64, 2.52), (2.12, 0.04, 0.14), de, 0)                    # its detail edge
    for sx in (-1, 1):
        _rbox(bm, (sx * 0.92, yf - 0.52, 0.62 + 0.92), (0.14, 0.14, 1.84), de, 0)   # posts 0.62..2.46
        _rbox(bm, (sx * 0.92, yf - 0.52, 0.66), (0.26, 0.26, 0.08), sh, 0)          # post feet
        for k in range(5):                                                         # radiator fins either side of the door
            _rbox(bm, (sx * (1.08 + 0.11 * k), yf - 0.16, 1.45), (0.04, 0.32, 1.3), de, 0)
        _rbox(bm, (sx * 1.30, yf - 0.06, 0.78), (0.56, 0.12, 0.06), sh, 0)          # fin base rail
        _rbox(bm, (sx * 1.30, yf - 0.06, 2.12), (0.56, 0.12, 0.06), sh, 0)          # fin top rail
    _rbox(bm, (0, yf - 0.02, 3.05), (3.3, 0.04, 0.10), dk, 0)                      # slate band across the front
    M = Matrix.Translation((0, yf, 3.75)) @ Matrix.Rotation(math.pi / 2, 4, "X")   # round vent emblem (axis -> -Y)
    prim_at(bm, "tube", 0.34, 0.46, 0.08, sh, M, zc=0.04)
    prim_at(bm, "cyl", 0.34, 0, 0.03, dk, M, zc=0.015)
    for k in range(3):
        _rbox(bm, (0, yf - 0.035, 3.75 - 0.18 + 0.18 * k), (0.56, 0.03, 0.05), de, 0)
    bm.to_mesh(me)
    bm.free()
    return "forge 2: removed %d faces (front tube, fins, side bits); 2 side tanks, canopy, fins, emblem" % n_gone


def clear_entries(ob, rmin, rmax, zmax, tol=math.radians(40), maxdim=1.6):
    """Remove the small islands (old door boxes, the fins beside them) whose centre lies within `tol` of the front (-Y) or back
    (+Y) axis, at plan radius rmin..rmax, centre height 0.3..zmax. The big shells (cone, bands, plinth) are kept (maxdim)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    gone = []
    for isl in _islands(bm, bm.faces[:]):
        x0, y0, z0, x1, y1, z1 = _bbox(isl)
        cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
        r = math.hypot(cx, cy)
        if max(x1 - x0, y1 - y0) > maxdim or not (rmin <= r <= rmax) or not (0.3 <= cz <= zmax):
            continue
        a = math.atan2(cy, cx)
        if min(abs(a - FRONT), abs(a - BACK)) <= tol:
            gone.extend(isl)
    bmesh.ops.delete(bm, geom=list(set(gone)), context="FACES")
    bm.to_mesh(me)
    bm.free()
    return len(gone)


def entrance(ob, piece, r0, r1, z0, z1, hw, door_w, door_h, roof_r0=None):
    """ENTRANCE HOUSING front + back (Daniele 2026-11-12: "fix the doors for googatling and cannons, in first case are too small
    in second is clipped in their base"): a cream housing from plan radius r0 to r1, z0..z1, half width hw, a slate strip at its
    foot, a detail roof slab (from roof_r0) and the kit's framed door (doors()) on its outer face, standing on z0."""
    sh, de, dk = (slot_index(ob, n, piece) for n in ("OS_Shell", "OS_Detail", "OS_Dark"))
    rr0 = r0 if roof_r0 is None else roof_r0
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for a in (FRONT, BACK):
        d = Vector((math.cos(a), math.sin(a), 0))
        _rbox(bm, d * ((r0 + r1) / 2) + Vector((0, 0, (z0 + z1) / 2)), ((r1 - r0), 2 * hw, z1 - z0), sh, a)
        _rbox(bm, d * ((r0 + r1) / 2 + 0.01) + Vector((0, 0, z0 + 0.04)), ((r1 - r0), 2 * hw + 0.03, 0.08), dk, a)
        _rbox(bm, d * ((rr0 + r1 + 0.08) / 2) + Vector((0, 0, z1 + 0.035)), ((r1 + 0.08 - rr0), 2 * hw + 0.1, 0.07), de, a)
    bm.to_mesh(ob.data)
    bm.free()
    return "entrance r %.2f..%.2f z %.2f..%.2f + " % (r0, r1, z0, z1) + doors(ob, piece, r1, z0, [FRONT, BACK], w=door_w, hgt=door_h)


def drum_doors(ob, piece, r0=1.40, r1=1.68, hw=0.6, z1=0.90):
    """Googatling doors v3 (Daniele 2026-11-12: the porch "extendo too much and won t fit on a node"): a shallow cream door block
    set into the drum (r0..r1, inside the 1.75 skirt line but for its corners ~1.81) front + back, a 0.9 x 0.72 m dark door with a
    flush detail frame, a slate foot strip and a detail top strip under the ledge ring (z 0.94)."""
    sh, de, dk = (slot_index(ob, n, piece) for n in ("OS_Shell", "OS_Detail", "OS_Dark"))
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for a in (FRONT, BACK):
        d = Vector((math.cos(a), math.sin(a), 0))
        P = lambda r, z: d * r + Vector((0, 0, z))
        _rbox(bm, P((r0 + r1) / 2, z1 / 2 + 0.01), (r1 - r0, 2 * hw, z1 - 0.02), sh, a)        # door block 0.02..0.90
        _rbox(bm, P((r0 + r1) / 2 + 0.005, 0.05), (r1 - r0, 2 * hw + 0.02, 0.06), dk, a)       # slate foot strip
        _rbox(bm, P((r0 + r1) / 2 + 0.005, z1 - 0.03), (r1 - r0, 2 * hw + 0.02, 0.05), de, a)  # detail top strip
        _rbox(bm, P(r1 + 0.008, 0.45), (0.02, 0.9, 0.70), dk, a)                               # the door 0.9 x 0.70 (z 0.10..0.80)
        for sy in (-1, 1):                                                                     # flush frame: jambs + lintel
            M = Vector((-d.y, d.x, 0)) * sy * 0.485
            _rbox(bm, P(r1 + 0.012, 0.46) + M, (0.03, 0.07, 0.76), de, a)
        _rbox(bm, P(r1 + 0.012, 0.83), (0.03, 1.04, 0.07), de, a)
    bm.to_mesh(ob.data)
    bm.free()
    return "drum doors front + back r %.2f..%.2f, door 0.9 x 0.70" % (r0, r1)


def cream(ob, piece, test):
    """OS_Dark primitives that read as caps / collars -> OS_Shell cream (whole primitives, so no ragged edges)."""
    me = ob.data
    dark = {i for i, m in enumerate(me.materials) if m and base_name(m.name) == "OS_Dark"}
    shell = slot_index(ob, "OS_Shell", piece)
    mw = ob.matrix_world
    n = 0
    for p in me.polygons:
        if p.material_index in dark and test(mw @ p.center):
            p.material_index = shell
            n += 1
    return "cream %d faces" % n


def structure(piece):
    fam = _family(piece)
    root = next(o for o in bpy.data.objects if o.parent is None and o.type == "MESH")
    if fam in ("Cannon", "Laser"):                                    # ring collars (r 1.02 x 0.24) above the column foot
        t = 3 if fam == "Laser" else int(piece[-1])
        col = cream(root, piece, lambda c: 0.95 <= math.hypot(c.x, c.y) <= 1.04 and 2.45 <= c.z <= 2.46 + 1.18 * t)
    if fam in ("Cannon", "Laser"):
        col += " | cleared %d faces (old doors + fins beside them)" % clear_entries(root, 0.55, 1.65, 1.88)
        col += " | " + entrance(root, piece, 0.9, 1.5, 0.40, 1.78, 0.55, 0.8, 1.1)   # on the plinth top (0.40), front + back
    if fam == "Cannon":
        return struct_neon(root, piece) + " | " + tower_head(root, piece, int(piece[-1])) + " | " + col
    if fam == "Laser":
        collar = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is root)
        return (struct_neon(root, piece) + " | " + tower_head(root, piece, 3) + " | " + col + " | collar "
                + struct_neon(collar, piece, keep=lambda c: c.z > 7.2))       # the top hoop stays neon
    if fam == "Forge":                     # top block + chimneys (z > 4.72) and the ooze tube's lid -> cream
        col = cream(root, piece, lambda c: c.z > 4.72 or (math.hypot(c.x, c.y + 0.95) <= 1.01 and 4.2 <= c.z <= 4.55))
        col += " | " + forge_rework(root, piece)                                     # Forge 2: tanks to the sides, door in front
        col += " | front + back " + doors(root, piece, 0.55, 0.06 + 0.56, [FRONT])        # block front face (was behind the goo tube)
        col += " / " + doors(root, piece, 1.65, 0.06 + 0.56, [BACK])               # on the plinth top, block back face
        return struct_neon(root, piece, keep=lambda c: c.z > 5.9 and abs(c.y - 0.5) < 0.5) + " | " + col   # 3 chimney rings
    if fam == "Machinegoon":
        return gatling(piece)
    raise ValueError(piece)


# ------------------------------------------------------------------ lab-kit 3: the BOTTOM PART (Daniele 2026-11-12: "don t forget
# the kit for the bottom part so the node tube, tube entrance and node connectors, walkways  pit to node tubes and the pit").
# Sizes = the runtime meshes (world_tubes.gd column_base_mesh / _build_connectors / _build_mesh, world_layer.gd _build_tube,
# world_locals.gd _build_walkways, containment_ring_v1): see the role note's inventory. Clean primitives (64 seg), lab zones,
# player neon only as thin rings (OS_Light). Blender -Y = the runtime's +Z front (export_yup).
B_ZONE = {"OS_Shell": "DECK", "OS_Plate": "WALK", "OS_Steel": "DETAIL", "OS_Detail": "DETAIL", "OS_Dark": "RECESS",
          "OS_Glass": "GLASS", "OS_Ooze_Neutral": "GOO", "OS_Light": "DECK"}
B_SLOTS = ["OS_Shell", "OS_Detail", "OS_Dark", "OS_Light", "OS_Plate", "OS_Steel"]
SH, DE, DK, LT, PL, ST = range(6)
# runtime numbers (world_tubes.gd / world_layer.gd / world_locals.gd)
APO, WALL_H, ROOF_A, ROOF_H, DOOR_HW, DOOR_RECT, FRAME_W, FRAME_D = 1.6, 1.05, 1.08, 1.38, 0.42, 0.42, 0.09, 0.08
LASER_Y, SOCK_Y, SOCK_Y_LOW, SOCK_ANG, SOCK_R, SOCK_RI, SOCK_D = (0.26, 0.5), 0.62, 0.35, math.radians(40), 0.36, 0.30, 0.32
LIFT_R, LIFT_R_PILLAR, LIFT_H = 0.95, 2.6, 12.5          # TUBE_R / TUBE_R_PILLAR; floor -16 -> TUBE_TOP -3.5
CONN_H, ORTHO_GAP, CONN_HALF = 1.5, 1.1, 1.2              # _conn_rect: half = gap / 2 + 0.25 + CONN_PAD / 2
DECK_HW, DECK_T, RAIL_H, RAMP_LEN, WALK_LEVELS = 0.8, 0.16, 0.45, 3.2, (1.75, 2.45, 3.15)
ABOUT_R = 0.95 + 0.3 + DECK_HW                            # roundabout centre radius round a column (ABOUT_GAP 0.3)
FLOOR2_Y = LOW_Y + 0.62                                   # FLOOR2_STEP


def _pr(bm, kind, r0, r1, h, mi, c, segs=64):
    return _prim(bm, kind, c, r0, r1, h, mi, segs)


def bmats(names=B_SLOTS):
    return [bpy.data.materials.get(n) or make_mat(n, B_ZONE[n]) for n in names]


def bobj(name, bm, mats, parent=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def xfm(c, x, y, z):
    """4x4 with columns x, y, z (unit axes) and translation c."""
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = c
    return m


def prim_at(bm, kind, r0, r1, h, mi, M, segs=64, zc=0.0):
    """_prim built round the local Z axis (centre zc), then moved by M."""
    fs = _prim(bm, kind, (0, 0, zc), r0, r1, h, mi, segs)
    bmesh.ops.transform(bm, matrix=M, verts=list({v for f in fs for v in f.verts}))
    return fs


def box_at(bm, M, s, mi, smooth=False):
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=M @ Matrix.Diagonal((*s, 1)))
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.material_index = mi
        f.smooth = smooth


def box_zoned(bm, c, s, top, side, bottom=None):
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Diagonal((*s, 1)))
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.normal_update()
        f.material_index = top if f.normal.z > 0.9 else (bottom if bottom is not None and f.normal.z < -0.9 else side)


def lathe(bm, prof, mis, segs=64, closed=True, poly=None):
    """Closed solid of revolution from (r, z) profile points (mis[i] = material of segment i -> i + 1). poly = 8 makes
    an octagon (faces on the cardinals, r = apothem)."""
    n = poly or segs
    k = 1 / math.cos(math.pi / n) if poly else 1.0
    off = math.pi / n if poly else 0.0
    rings = [[bm.verts.new((r * k * math.cos(2 * math.pi * i / n + off), r * k * math.sin(2 * math.pi * i / n + off), z))
              for i in range(n)] for r, z in prof]
    cnt = len(prof) if closed else len(prof) - 1
    for s in range(cnt):
        A, Bb = rings[s], rings[(s + 1) % len(prof)]
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((A[i], A[j], Bb[j], Bb[i]))
            f.material_index = mis[s]
            f.smooth = not poly
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def sweep(bm, pts, r, mi, segs=64, caps=True):
    """Tube of radius r along the polyline pts (parallel-transport frames), capped."""
    pts = [Vector(p) for p in pts]
    tg = []
    for i in range(len(pts)):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        tg.append((b - a).normalized())
    ref = Vector((0, 0, 1)) if abs(tg[0].z) < 0.9 else Vector((1, 0, 0))
    u = tg[0].cross(ref).normalized()
    rings = []
    for i, p in enumerate(pts):
        if i:
            u = (u - tg[i] * u.dot(tg[i])).normalized()
        v = tg[i].cross(u)
        rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r)
                      for k in range(segs)])
    fs = []
    for i in range(len(rings) - 1):
        for k in range(segs):
            j = (k + 1) % segs
            fs.append(bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k])))
    for f in fs:
        f.smooth = True
    if caps:
        fs.append(bm.faces.new(list(reversed(rings[0]))))
        fs.append(bm.faces.new(rings[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    for f in fs:
        f.material_index = mi
    return fs


def sleeve(bm, p, t, mi, r_out=SLEEVE_R, r_in=TUBE_R + 0.002, l=SLEEVE_L):
    t = Vector(t).normalized()
    ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    x = t.cross(ref).normalized()
    prim_at(bm, "tube", r_in, r_out, l, mi, xfm(Vector(p), x, t.cross(x), t))


def fillet_path(way, R, step=0.06):
    """Polyline with every inner corner replaced by an arc of radius R (sampled ~step m); straights resampled 0.25 m."""
    way = [Vector(p) for p in way]
    out = [way[0]]
    for i in range(1, len(way) - 1):
        a, b, c = way[i - 1], way[i], way[i + 1]
        d0, d1 = (b - a).normalized(), (c - b).normalized()
        th = d0.angle(d1)
        if th < 1e-3:
            out.append(b)
            continue
        p0 = b - d0 * (R * math.tan(th / 2))
        ax = d0.cross(d1).normalized()
        cen = p0 + ax.cross(d0).normalized() * R
        n = max(int(th * R / step), 4)
        for k in range(n + 1):
            out.append(cen + Matrix.Rotation(th * k / n, 3, ax) @ (p0 - cen))
    out.append(way[-1])
    res = [out[0]]
    for q in out[1:]:
        L = (q - res[-1]).length
        a = res[-1]
        n = int(L / 0.25)
        for k in range(1, n):
            res.append(a.lerp(q, k / n))
        if L > 1e-4:
            res.append(q)
    return res


def tube_piece(name, path, sleeves, extra=None):
    """A transport-tube piece: Glass (root, r 0.27), Goo child (r 0.22, ends 2 cm in), Sleeves child (cream, 2 mm clear)."""
    ms = {n: bpy.data.materials.get(n) or make_mat(n, B_ZONE[n]) for n in ("OS_Glass", "OS_Ooze_Neutral", "OS_Shell", "OS_Detail")}
    g, o, s = bmesh.new(), bmesh.new(), bmesh.new()
    sweep(g, path, TUBE_R, 0)
    L = [0.0]
    for i in range(1, len(path)):
        L.append(L[-1] + (Vector(path[i]) - Vector(path[i - 1])).length)
    inner = [p for p, d in zip(path, L) if 0.02 <= d <= L[-1] - 0.02]
    sweep(o, inner, GOO_R, 0)
    for sv in sleeves:                       # END sleeves are HALF length (Daniele 2026-11-12: two joined pieces = ONE connector,
        sleeve(s, sv[0], sv[1], 0, l=sv[2] if len(sv) > 2 else SLEEVE_L / 2)   # not a double); a 3rd value = a full-length sleeve
    if extra:
        extra(s)
    root = bobj(name, g, [ms["OS_Glass"]])
    bobj(name + "_Goo", o, [ms["OS_Ooze_Neutral"]], root)
    if len(s.verts):
        bobj(name + "_Sleeves", s, [ms["OS_Shell"], ms["OS_Detail"]], root)
    else:
        s.free()
    return root


def line(a, b, n):
    a, b = Vector(a), Vector(b)
    return [a.lerp(b, k / n) for k in range(n + 1)]


# ---------------------------------------------------------------- the pieces
def _face(f):
    """Runtime face f of the octagon (0 = +Z front ... f even = door): Blender out / side vectors."""
    a = math.pi / 4 * f
    out = Vector((math.sin(a), -math.cos(a), 0))
    return out, Vector((-out.y, out.x, 0))


def _arch(w, n=16):
    pts = [(-w, 0.0), (-w, DOOR_RECT)]
    for k in range(1, n):
        a = math.pi - math.pi * k / n
        pts.append((math.cos(a) * w, DOOR_RECT + math.sin(a) * w))
    return pts + [(w, DOOR_RECT), (w, 0.0)]


def arch_door(bm, f):
    """The runtime arch door on face f: dark mouth, frame (detail) FRAME_W wide FRAME_D proud, two owner-light strands."""
    out, side = _face(f)
    c = out * APO
    P = lambda q, d: c + side * q[0] + Vector((0, 0, q[1])) + out * d
    inner, outer = _arch(DOOR_HW), _arch(DOOR_HW + FRAME_W)
    mouth = [bm.verts.new(P(q, 0.012)) for q in inner]
    back = [bm.verts.new(P(q, -0.001)) for q in inner]
    fs = [bm.faces.new(mouth), bm.faces.new(list(reversed(back)))]
    for k in range(len(inner) - 1):
        fs.append(bm.faces.new((mouth[k], mouth[k + 1], back[k + 1], back[k])))
    fs.append(bm.faces.new((mouth[-1], mouth[0], back[0], back[-1])))
    for fc in fs:
        fc.material_index = DK
    fr = []
    I0 = [bm.verts.new(P(q, 0.0)) for q in inner]
    I1 = [bm.verts.new(P(q, FRAME_D)) for q in inner]
    O0 = [bm.verts.new(P(q, 0.0)) for q in outer]
    O1 = [bm.verts.new(P(q, FRAME_D)) for q in outer]
    for k in range(len(inner) - 1):
        for quad in ((I1[k], I1[k + 1], O1[k + 1], O1[k]), (I0[k], I0[k + 1], I1[k + 1], I1[k]),
                     (O0[k], O0[k + 1], O1[k + 1], O1[k]), (I0[k], I0[k + 1], O0[k + 1], O0[k])):
            fr.append(bm.faces.new(quad))
    for e in (0, len(inner) - 1):
        fr.append(bm.faces.new((I0[e], O0[e], O1[e], I1[e])))
    bmesh.ops.recalc_face_normals(bm, faces=fr)
    for fc in fr:
        fc.material_index = DE
    for ly in LASER_Y:                                            # the door laser: owner light (thin strands)
        box_at(bm, xfm(c + Vector((0, 0, ly)) + out * 0.05, side, out, Vector((0, 0, 1))), (2 * DOOR_HW, 0.044, 0.044), DE)   # (designer 4, 11-12: detail, not neon)


def socket(bm, f, y, ang):
    out, side = _face(f)
    ax = out * math.cos(ang) + Vector((0, 0, 1)) * math.sin(ang)
    up = Vector((0, 0, 1)) * math.cos(ang) - out * math.sin(ang)
    back = -SOCK_R * math.sin(ang) - 0.04
    c = out * APO + Vector((0, 0, y))
    M = xfm(c, side, up, ax)
    prim_at(bm, "tube", SOCK_RI, SOCK_R, SOCK_D - back, DE, M, zc=(SOCK_D + back) / 2)          # the coupling sleeve
    prim_at(bm, "tube", SOCK_R - 0.005, SOCK_R + 0.025, 0.035, DE, M, zc=SOCK_D - 0.06)         # detail ring (designer 4, 11-12: neon on the top ring only)
    prim_at(bm, "tube", SOCK_RI - 0.03, SOCK_RI, 0.04, SH, M, zc=SOCK_D - 0.02)                 # cream lip
    prim_at(bm, "cyl", SOCK_RI - 0.005, 0, 0.03, DK, M, zc=0.03)                                # dark bore


def node_base(name, flat=True):
    """TUBE ENTRANCE / column base: octagon (apothem 1.6, wall 1.05, sloped roof to 1.08 at 1.38), 4 cardinal walk-in doors
    (front AND back + both sides), 4 sockets on the diagonal faces (flat=True: faces 1 / 5 flat at 0.35 = base45 default,
    3 / 7 tilted 40 deg at 0.62), a thin owner ring round the foot and a cream collar with a thin owner ring round the lift."""
    bm = bmesh.new()
    prof = [(0.97, 0.0), (APO, 0.0), (APO, 0.09), (APO, 0.13), (APO, 0.92), (APO, WALL_H), (ROOF_A, ROOF_H), (0.97, ROOF_H)]
    lathe(bm, prof, [DK, DE, DE, SH, DK, SH, SH, DK], poly=8)   # foot band detail: neon on the top ring only
    prim_at(bm, "tube", 0.97, 1.20, 0.10, SH, Matrix.Translation((0, 0, ROOF_H + 0.05)))      # collar round the lift
    prim_at(bm, "tube", 1.00, 1.06, 0.02, LT, Matrix.Translation((0, 0, ROOF_H + 0.11)))      # thin owner ring on it
    prim_at(bm, "tube", 1.12, 1.20, 0.03, DE, Matrix.Translation((0, 0, ROOF_H + 0.115)))
    for f in (0, 2, 4, 6):
        arch_door(bm, f)
    for f in (1, 3, 5, 7):
        socket(bm, f, SOCK_Y_LOW if flat and f in (1, 5) else SOCK_Y, 0.0 if flat and f in (1, 5) else SOCK_ANG)
    bobj(name, bm, bmats())
    return "octagon apothem %.2f, 4 doors, 4 sockets (%s)" % (APO, "2 flat + 2 tilted" if flat else "4 tilted")


def node_tube(name, r, h, bands=True, collar=True):
    """The NODE TUBE (the lift): glass r (open-ended in game, closed here), goo core, detail bands every 2.5 m, cream collar
    under the platform. Origin at the floor; h = floor to platform underside."""
    ms = {n: bpy.data.materials.get(n) or make_mat(n, B_ZONE[n]) for n in ("OS_Glass", "OS_Ooze_Neutral", "OS_Shell", "OS_Detail", "OS_Light")}
    g = bmesh.new()
    _pr(g, "tube", r - 0.03, r, h, 0, (0, 0, h / 2))
    o = bmesh.new()
    _pr(o, "cyl", r - 0.09, 0, h - 0.04, 0, (0, 0, h / 2))
    root = bobj(name, g, [ms["OS_Glass"]])
    bobj(name + "_Goo", o, [ms["OS_Ooze_Neutral"]], root)
    if bands or collar:
        s = bmesh.new()
        if bands:
            z = 2.5
            while z < h - 1.0:
                _pr(s, "tube", r + 0.002, r + 0.05, 0.08, 1, (0, 0, z))
                z += 2.5
        if collar:
            _pr(s, "tube", r + 0.002, r + 0.28, 0.34, 0, (0, 0, h - 0.17))                     # cream collar
            _pr(s, "tube", r + 0.28, r + 0.31, 0.06, 1, (0, 0, h - 0.17))                      # slate band
            _pr(s, "tube", r + 0.002, r + 0.10, 0.12, 0, (0, 0, h - 0.40))                     # step
            _pr(s, "tube", r + 0.10, r + 0.13, 0.025, 2, (0, 0, h - 0.40))                     # thin owner ring
        bobj(name + "_Bands", s, [ms["OS_Shell"], ms["OS_Detail"], ms["OS_Light"]], root)
    return "r %.2f h %.2f" % (r, h)


def connector(name, a, b):
    """NODE / TUBE CONNECTOR block (world_tubes _build_connectors): a x-lanes enter the +-X faces, b z-lanes the +-Y faces,
    lanes 1.1 m apart, block = 2.4 + (n - 1) x 1.1 per side, 1.5 m tall; one coupling per lane per face at the floor tube
    level 0.35. Cream block, slate base + recess band, detail top panel, detail couplings with a cream lip."""
    sx, sy = 2 * CONN_HALF + (b - 1) * ORTHO_GAP, 2 * CONN_HALF + (a - 1) * ORTHO_GAP
    bm = bmesh.new()
    box_zoned(bm, (0, 0, 0.06), (sx, sy, 0.12), DE, DE)                                        # slate foot
    box_zoned(bm, (0, 0, 0.12 + (CONN_H - 0.22) / 2), (sx - 0.06, sy - 0.06, CONN_H - 0.22), SH, SH)
    box_zoned(bm, (0, 0, 1.02), (sx - 0.02, sy - 0.02, 0.08), DK, DK)                          # recess band
    box_zoned(bm, (0, 0, CONN_H - 0.05), (sx - 0.18, sy - 0.18, 0.10), SH, SH)                 # chamfer step
    box_zoned(bm, (0, 0, CONN_H + 0.004), (sx - 0.5, sy - 0.5, 0.008), DE, DE)                 # top panel (8 mm proud: no z-fight)
    lanes = lambda n: [(k - (n - 1) / 2) * ORTHO_GAP for k in range(n)]
    for sg in (-1, 1):
        for ly in lanes(a):
            for M in (xfm(Vector((sg * (sx / 2 - 0.03), ly, LOW_Y)), Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((sg, 0, 0))),):
                prim_at(bm, "tube", SOCK_RI, SOCK_R, 0.30, DE, M, zc=0.07)
                prim_at(bm, "tube", SOCK_R, SOCK_R + 0.04, 0.04, SH, M, zc=0.20)
                prim_at(bm, "cyl", SOCK_RI, 0, 0.02, DK, M, zc=0.02)
        for lx in lanes(b):
            M = xfm(Vector((lx, sg * (sy / 2 - 0.03), LOW_Y)), Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, sg, 0)))
            prim_at(bm, "tube", SOCK_RI, SOCK_R, 0.30, DE, M, zc=0.07)
            prim_at(bm, "tube", SOCK_R, SOCK_R + 0.04, 0.04, SH, M, zc=0.20)
            prim_at(bm, "cyl", SOCK_RI, 0, 0.02, DK, M, zc=0.02)
    bobj(name, bm, bmats())
    return "%.2f x %.2f x %.1f, %d x-lanes, %d z-lanes" % (sx, sy, CONN_H, a, b)


def _rails(bm, p0, p1, nrm, posts=True):
    """Hand rail, mid rail, kick plate (world_locals _beam sizes) from p0 to p1 (deck-top points on the rail line)."""
    d = (p1 - p0)
    L = d.length
    t = d.normalized()
    up = nrm.cross(t).normalized()
    if up.z < 0:
        up = -up
    zv = Vector((0, 0, 1))
    for top, w, h in ((RAIL_H, 0.07, 0.06), (RAIL_H * 0.5, 0.04, 0.04), (0.09, 0.05, 0.09)):
        c = (p0 + p1) / 2 + zv * (top - h / 2)
        box_at(bm, xfm(c, t, nrm, t.cross(nrm)), (L, w, h), ST)
    if posts:
        n = max(math.ceil(L / 2.2), 1)
        for k in range(n + 1):
            q = p0.lerp(p1, k / n)
            box_at(bm, Matrix.Translation(q + zv * (RAIL_H / 2)), (0.07, 0.07, RAIL_H), ST)


def walk_straight(name, L=4.0):
    """WALKWAY deck (world_locals _build_walkways): 1.6 m wide, 0.16 thick, rails 0.45 both sides; origin = deck top centre;
    two slate inlay lines where the old neon dashes were (no neon on walkways, Daniele 2026-11-11)."""
    bm = bmesh.new()
    box_zoned(bm, (0, 0, -DECK_T / 2), (L, 2 * DECK_HW, DECK_T), PL, DE)
    for sy in (-1, 1):
        box_zoned(bm, (0, sy * 0.42, 0.002), (L, 0.04, 0.004), DE, DE)
        y = sy * (DECK_HW - 0.035)
        _rails(bm, Vector((-L / 2, y, 0)), Vector((L / 2, y, 0)), Vector((0, sy, 0)))
    bobj(name, bm, bmats())
    return "%.1f m x %.1f m" % (L, 2 * DECK_HW)


def walk_ramp(name, rise=WALK_LEVELS[0], L=RAMP_LEN):
    """WALKWAY RAMP floor -> level (3.2 m run); origin at the floor end."""
    bm = bmesh.new()
    ang = math.atan2(rise, L)
    t = Vector((math.cos(ang), 0, math.sin(ang)))
    nrm = Vector((-math.sin(ang), 0, math.cos(ang)))
    S = math.hypot(L, rise)
    c = Vector((L / 2, 0, rise / 2)) - nrm * (DECK_T / 2)
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=xfm(c, t, Vector((0, 1, 0)), nrm) @ Matrix.Diagonal((S, 2 * DECK_HW, DECK_T, 1)))
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.normal_update()
        f.material_index = PL if f.normal.dot(nrm) > 0.9 else DE
    for sy in (-1, 1):
        y = sy * (DECK_HW - 0.035)
        p0, p1 = Vector((0, y, 0)), Vector((L, y, rise))
        d = p1 - p0
        tt = d.normalized()
        side = Vector((0, sy, 0))
        for top, w, h in ((RAIL_H, 0.07, 0.06), (RAIL_H * 0.5, 0.04, 0.04), (0.09, 0.05, 0.09)):
            cc = (p0 + p1) / 2 + Vector((0, 0, top - h / 2))
            box_at(bm, xfm(cc, tt, side, tt.cross(side) if tt.cross(side).z > 0 else -tt.cross(side)), (d.length, w, h), ST)
        for k in range(3):
            q = p0.lerp(p1, k / 2)
            box_at(bm, Matrix.Translation(q + Vector((0, 0, RAIL_H / 2))), (0.07, 0.07, RAIL_H), ST)
    zt = rise - DECK_T / math.cos(ang) - 0.01                       # one stand under the top end
    box_zoned(bm, (L - 0.3, 0, zt / 2), (0.14, 0.14, zt), ST, ST)
    box_zoned(bm, (L - 0.3, 0, 0.02), (0.3, 0.3, 0.04), DE, DE)
    bobj(name, bm, bmats())
    return "run %.1f m, rise %.2f m" % (L, rise)


def walk_stand(name):
    bm = bmesh.new()
    box_zoned(bm, (0, 0, 0.52), (0.14, 0.14, 0.96), ST, ST)
    box_zoned(bm, (0, 0, 0.02), (0.30, 0.30, 0.04), DE, DE)
    bobj(name, bm, bmats())
    return "1 m (scale z), 0.14 sq + 0.30 foot"


def walk_about(name, R=ABOUT_R):
    """WALKWAY ROUNDABOUT round a column (R = lift 0.95 + 0.3 + 0.8); origin = deck top centre."""
    bm = bmesh.new()
    lathe(bm, [(R - DECK_HW, -DECK_T), (R + DECK_HW, -DECK_T), (R + DECK_HW, 0), (R - DECK_HW, 0)], [DE, DE, PL, DE])
    for rr in (R - DECK_HW + 0.035, R + DECK_HW - 0.035):
        for top, w, h in ((RAIL_H, 0.07, 0.06), (RAIL_H * 0.5, 0.04, 0.04), (0.09, 0.05, 0.09)):
            _pr(bm, "tube", rr - w / 2, rr + w / 2, h, ST, (0, 0, top - h / 2))
        n = max(math.ceil(2 * math.pi * rr / 2.2), 4)
        for k in range(n):
            a = 2 * math.pi * (k + 0.5) / n
            box_at(bm, Matrix.Translation((rr * math.cos(a), rr * math.sin(a), RAIL_H / 2)) @ Matrix.Rotation(a, 4, "Z"),
                   (0.07, 0.07, RAIL_H), ST)
    _pr(bm, "tube", R - 0.44, R - 0.40, 0.004, DE, (0, 0, 0.002))
    _pr(bm, "tube", R + 0.40, R + 0.44, 0.004, DE, (0, 0, 0.002))
    bobj(name, bm, bmats())
    return "R %.2f (deck %.2f..%.2f)" % (R, R - DECK_HW, R + DECK_HW)


def pit(name):
    """THE PIT (containment ring v1 measures: outer r 5.0, pool r 3.5 at 0.55, rim top 0.80), rebuilt as clean 64-seg
    primitives: cream rim with a slate inner wall, recess groove, detail plinth, a bolt ring and 4 recess vent slots; the goo
    pool (OS_Ooze_Neutral, R7 tint at runtime). Not entered (the Locals hop the rim): no doors."""
    ms = bmats(["OS_Shell", "OS_Detail", "OS_Dark", "OS_Ooze_Neutral"])
    bm = bmesh.new()
    prof = [(3.5, 0.0), (5.0, 0.0), (5.0, 0.14), (4.82, 0.22), (4.76, 0.70), (4.62, 0.80), (4.12, 0.80), (4.12, 0.75),
            (4.0, 0.75), (4.0, 0.80), (3.62, 0.80), (3.5, 0.72)]
    lathe(bm, prof, [1, 1, 1, 0, 0, 0, 2, 2, 2, 0, 1, 1])
    for k in range(28):                                             # bolt ring on the outer top band
        a = 2 * math.pi * (k + 0.5) / 28
        _pr(bm, "cyl", 0.045, 0, 0.03, 1, (4.37 * math.cos(a), 4.37 * math.sin(a), 0.815), segs=16)
    for k in range(4):                                              # vent slots on the outer wall (the old grilles)
        a = math.pi / 2 * k
        out = Vector((math.cos(a), math.sin(a), 0))
        for j in range(4):
            box_at(bm, xfm(out * 4.80 + Vector((0, 0, 0.30 + 0.09 * j)), Vector((-out.y, out.x, 0)), Vector((0, 0, 1)), out),
                   (0.9, 0.04, 0.04), 2)
    root = bobj(name, bm, ms[:3])
    g = bmesh.new()
    _pr(g, "cyl", 3.49, 0, 0.53, 0, (0, 0, 0.285))
    bobj(name + "_Goo", g, [ms[3]], root)
    return "r 5.0, pool r 3.5 at 0.55, rim 0.80"


def b_tube(name):
    up = Vector((0, 0, 1))
    if name == "Pit_Tube_Run_2m":
        return tube_piece(name, line((-1, 0, LOW_Y), (1, 0, LOW_Y), 8),
                          [((-1 + SLEEVE_L / 4, 0, LOW_Y), (1, 0, 0)), ((1 - SLEEVE_L / 4, 0, LOW_Y), (1, 0, 0))])
    if name == "Pit_Tube_Elbow_R080":                               # ORTHO_BEND 0.8: quarter bend + 0.3 m leads (sleeves)
        pts = [Vector((-0.3, 0, LOW_Y))] + [Vector((0.8 * math.sin(a), 0.8 - 0.8 * math.cos(a), LOW_Y))
                                            for a in (math.pi / 2 * s / 24 for s in range(25))] + [Vector((0.8, 1.1, LOW_Y))]
        return tube_piece(name, pts, [((-0.3 + SLEEVE_L / 4, 0, LOW_Y), (1, 0, 0)), ((0.8, 1.1 - SLEEVE_L / 4, LOW_Y), (0, 1, 0))])
    if name == "Pit_Tube_Step":                                     # floor level 0.35 -> second level 0.97 (FLOOR2_STEP 0.62)
        pts = [Vector((x, 0, LOW_Y + (FLOOR2_Y - LOW_Y) * (0.5 - 0.5 * math.cos(math.pi * min(max((x + 0.3) / 1.6, 0), 1)))))
               for x in [-0.6 + 0.05 * k for k in range(45)]]
        return tube_piece(name, pts, [((pts[0].x + SLEEVE_L / 4, 0, LOW_Y), (1, 0, 0)), ((pts[-1].x - SLEEVE_L / 4, 0, FLOOR2_Y), (1, 0, 0))])
    if name == "Pit_Tube_Socket_Climb":                             # out of a tilted socket (40 deg at 0.62) to level 0.97
        way = [Vector((0, 0, SOCK_Y)), Vector(((FLOOR2_Y - SOCK_Y) / math.tan(SOCK_ANG), 0, FLOOR2_Y)),
               Vector((1.8, 0, FLOOR2_Y))]
        pts = fillet_path(way, 0.8)
        return tube_piece(name, pts, [((1.8 - SLEEVE_L / 4, 0, FLOOR2_Y), (1, 0, 0))])
    if name == "Pit_Tube_Rim_Dip":                                  # origin = pit centre: floor run in, over the rim, into the goo
        way = [Vector((7.2, 0, LOW_Y)), Vector((6.0, 0, LOW_Y)), Vector((5.0, 0, 1.22)), Vector((3.3, 0, 1.22)), Vector((2.7, 0, 0.25))]
        pts = fillet_path(way, 0.6)

        def clamp(bm):                                              # a clamp on the rim top
            box_at(bm, Matrix.Translation((4.3, 0, 0.865)), (0.30, 0.42, 0.13), 1)
        return tube_piece(name, pts, [((7.2 - SLEEVE_L / 4, 0, LOW_Y), (-1, 0, 0)), ((4.3, 0, 1.22), (-1, 0, 0), SLEEVE_L)], clamp)   # rim clamp: full sleeve (a support, not a joint)
    raise ValueError(name)


def bottom(name):
    if name == "Node_Base":
        return node_base(name, True)
    if name == "Node_Base_Tilted":
        return node_base(name, False)
    if name == "Node_Tube":
        return node_tube(name, LIFT_R, LIFT_H)
    if name == "Node_Tube_Unit_1m":
        return node_tube(name, LIFT_R, 1.0, bands=False, collar=False)
    if name == "Node_Tube_Pillar_Unit_1m":
        return node_tube(name, LIFT_R_PILLAR, 1.0, bands=False, collar=False)
    if name.startswith("Tube_Connector_"):
        a, b = (int(v) for v in name.rsplit("_", 1)[1].split("x"))
        return connector(name, a, b)
    if name == "Walkway_Straight_4m":
        return walk_straight(name)
    if name == "Walkway_Ramp":
        return walk_ramp(name)
    if name == "Walkway_Stand_1m":
        return walk_stand(name)
    if name == "Walkway_Roundabout":
        return walk_about(name)
    if name == "Pit":
        return pit(name)
    if name.startswith("Pit_Tube_"):
        b_tube(name)
        return "transport tube r %.2f, goo %.2f" % (TUBE_R, GOO_R)
    raise ValueError(name)


BOTTOM = ["Node_Base", "Node_Base_Tilted", "Node_Tube", "Node_Tube_Unit_1m", "Node_Tube_Pillar_Unit_1m",
          "Tube_Connector_1x1", "Tube_Connector_1x2", "Tube_Connector_2x2", "Tube_Connector_3x3",
          "Walkway_Straight_4m", "Walkway_Ramp", "Walkway_Stand_1m", "Walkway_Roundabout",
          "Pit", "Pit_Tube_Run_2m", "Pit_Tube_Elbow_R080", "Pit_Tube_Step", "Pit_Tube_Socket_Climb", "Pit_Tube_Rim_Dip"]


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
STRUCTURES = ["Laser", "Cannon_T1", "Cannon_T2", "Cannon_T3", "Forge", "Machinegoon_T1", "Machinegoon_T2", "Machinegoon_T3"]
PIECES += [("kit/" + n, n, "structure") for n in STRUCTURES]
PIECES += [(None, n, "goocannon") for n in ("Relay_Cannon_v4", "Relay_Cannon_v4_T2", "Relay_Cannon_v4_T3")]   # the launcher turret
PIECES += [(None, n, "bottom") for n in BOTTOM]   # lab-kit 3: the bottom part (node base / tube, connectors, walkways, pit, pit tubes)


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
        elif kind == "goocannon":
            note = goocannon(name)
        elif kind == "bottom":
            note = bottom(name)
        else:
            bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, src + ".glb"))
            mats = rezone(name if kind != "pit" else "Pit")
            root = next(o for o in bpy.data.objects if o.parent is None and o.type == "MESH")
            if kind == "pit":
                root.name = root.data.name = name
                note = pit_zones(root, "Pit")
            elif kind == "platform":
                note = rim_band(root, name)
            elif kind == "structure":
                note = structure(name)
            elif kind == "vat":
                note = vat_goo(root, name) + " | " + vat_neon(root, name) + " | " + vat_caps(root, name) + " | " + vat_clean_caps(root, name) + " | " + vat_strip_goo(root, name)
                note += " | back " + doors(root, name, 1.28, 0.06, [BACK])
                if CAPNEON:
                    note += " | " + vat_capneon(root, name)
            else:
                note = "zones " + ",".join(mats)
        for m in list(bpy.data.materials):
            if m.users == 0:
                bpy.data.materials.remove(m)
        path = os.path.join(OUT, name + ("_capneon" if CAPNEON and kind == "vat" else "") + ".glb")
        if CAPNEON and kind != "vat":
            continue
        export(path)
        print("LABKIT %-28s %8d  %s" % (name, os.path.getsize(path), note))


main()
