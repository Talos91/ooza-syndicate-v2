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
    """Goocannon = the launcher turret (Relay_Cannon_v4 / _T2 / _T3), REMADE as clean kit geometry (Daniele 2026-11-12: "the
    cannon needs to be remade in blender as the original rodin model ... very hard to paint and would look different then
    other models in game"). Proportions measured on the deployed GLBs (disc, ramp, pedestal, pivot, drum, barrel, rear tank),
    built from clean primitives in the vat language, zoned by OS_* slots (so it now takes the owner's neon at runtime):
    dark disc drum + cream top plate + ramp wedge (+X, the throw direction), thin neon halo on the plate, detail collar,
    cream pedestal with side fins + a front recess, detail yoke arms; Head (origin on the yoke pivot, the game pitches it
    and kicks it back along -X): cream drum on a Y axle, detail trunnion bosses (5 mm clear of the arms), detail neck,
    cream muzzle with detail rings, recess bore + thin neon ring on the muzzle face, a hatch with a thin neon ring;
    T2 / T3: the rear ammo tank has a glass window band with goo inside (the goo gauge)."""
    T = {"Relay_Cannon_v4": dict(R=4.62, Hd=0.75, piv=3.21, top=2.25, col=2.6, p0=2.3, p1=1.9, xd=-0.9, dz=0.69, Rb=1.35,
                                 Wb=1.1, neck=(0.3, 1.45, 0.75), muz=(1.45, 2.38, 0.95), rear=None),
         "Relay_Cannon_v4_T2": dict(R=4.32, Hd=0.6, piv=3.72, top=2.9, col=2.47, p0=2.25, p1=2.0, xd=-0.4, dz=1.0, Rb=1.55,
                                    Wb=1.25, neck=(0.6, 2.0, 0.55), muz=(2.0, 3.91, 1.12), rear=(-3.41, -1.0, 1.27)),
         "Relay_Cannon_v4_T3": dict(R=4.85, Hd=0.7, piv=4.26, top=3.4, col=2.73, p0=2.55, p1=2.15, xd=-0.6, dz=1.2, Rb=1.72,
                                    Wb=1.35, neck=(0.9, 1.6, 0.5), muz=(1.6, 3.55, 1.5), rear=(-4.3, -1.6, 1.55))}[piece]
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

    def box(bm, c, s, mi):
        r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Diagonal((*s, 1)))
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = mi
            f.smooth = False

    def wedge(bm, x0, x1, hw, z0, z1, mi):
        """Ramp: x0..x1 at half width hw, top from z0 (at x0) down to z1 (at x1), bottom on z 0."""
        P = [(x0, -hw, 0), (x1, -hw, 0), (x1, hw, 0), (x0, hw, 0), (x0, -hw, z0), (x1, -hw, z1), (x1, hw, z1), (x0, hw, z0)]
        v = [bm.verts.new(p) for p in P]
        for q in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            f = bm.faces.new([v[i] for i in q])
            f.material_index = mi
        bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.verts[0] in v])

    R, Hd, piv = T["R"], T["Hd"], T["piv"]
    # ---------------------------------------------------------------- base (static)
    b = bmesh.new()
    _prim(b, "cyl", (0, 0, 0.3 * Hd), R, 0, 0.6 * Hd, DK)                         # dark disc drum
    _prim(b, "cyl", (0, 0, 0.8 * Hd), R - 0.08, 0, 0.4 * Hd, SH)                   # cream top plate
    _prim(b, "tube", (0, 0, Hd + 0.008), T["col"] + 0.18, T["col"] + 0.3, 0.012, LI)   # thin neon halo on the plate
    wedge(b, 2.9, R + 0.35, 1.35, Hd + 0.24, 0.45 * Hd, SH)                       # the throw ramp (+X), past the rim
    wedge(b, 2.9, R + 0.36, 0.25, Hd + 0.255, 0.45 * Hd + 0.015, DE)              # its centre strip
    c0, c1 = Hd, Hd + 0.3
    _prim(b, "cyl", (0, 0, (c0 + c1) / 2), T["col"], 0, c1 - c0, DE)              # detail collar
    _prim(b, "cone", (0, 0, (c1 + T["top"]) / 2), T["p0"], T["p1"], T["top"] - c1, SH)   # cream pedestal
    hp = T["top"] - c1
    for sy in (-1, 1):                                                           # side fins
        box(b, (0, sy * (T["p0"] - 0.05), c1 + hp * 0.4), (0.5, 0.36, hp * 0.8), DE)
    box(b, ((T["p0"] + T["p1"]) / 2 - 0.12, 0, c1 + hp * 0.45), (0.3, 1.0, hp * 0.7), DK)   # front recess (door)
    a0, a1 = T["Wb"] + 0.405, T["Wb"] + 0.75                                     # yoke arms, 5 mm clear of the bosses
    for sy in (-1, 1):
        box(b, (0, sy * (a0 + a1) / 2, (T["top"] - 0.05 + piv) / 2), (0.9, a1 - a0, piv - T["top"] + 0.05), DE)
        ax(b, "cyl", (0, sy * (a0 + a1) / 2, piv), 0.45, 0, a1 - a0, DE, "Y", segs=48)
    # ---------------------------------------------------------------- head (pivot at the origin)
    h = bmesh.new()
    xd, dz, Rb, Wb = T["xd"], T["dz"], T["Rb"], T["Wb"]
    ax(h, "cyl", (xd, 0, dz), Rb, 0, 2 * Wb - 0.24, SH, "Y")                       # cream drum
    for sy in (-1, 1):
        f = ax(h, "cone", (xd, sy * (Wb - 0.06), dz), Rb, Rb - 0.12, 0.12, SH, "Y")   # chamfered ends
        if sy < 0:
            bmesh.ops.reverse_faces(h, faces=f)
            bmesh.ops.rotate(h, verts=list({v for q in f for v in q.verts}), cent=(xd, -(Wb - 0.06), dz),
                             matrix=Matrix.Rotation(math.pi, 3, "Z"))
        ax(h, "cyl", (xd, sy * (Wb - 0.2), dz), Rb + 0.03, 0, 0.12, DE, "Y")      # drum rims
        ax(h, "cyl", (xd, sy * (Wb + 0.01), dz), 0.62 * Rb, 0, 0.02, DE, "Y", segs=48)   # hub plates
        ax(h, "cyl", (0, sy * (Wb + 0.2), 0), 0.5, 0, 0.40, DE, "Y", segs=48)      # trunnion bosses (to Wb + 0.40)
        ax(h, "cyl", (0, sy * (Wb + 0.39), 0), 0.22, 0, 0.02, DK, "Y", segs=32)    # boss caps
    nx0, nx1, nr = T["neck"]
    ax(h, "cyl", ((nx0 + nx1) / 2, 0, dz), nr, 0, nx1 - nx0, DE, "X")             # neck
    mx0, mx1, mr = T["muz"]
    ax(h, "cyl", ((mx0 + mx1) / 2, 0, dz), mr, 0, mx1 - mx0, SH, "X")             # muzzle
    for x in (mx0 + 0.1, mx1 - 0.1):
        ax(h, "cyl", (x, 0, dz), mr + 0.05, 0, 0.16, DE, "X")                     # muzzle rings
    ax(h, "cyl", (mx1 + 0.01, 0, dz), 0.55 * mr, 0, 0.02, DK, "X", segs=48)       # bore
    ax(h, "tube", (mx1 + 0.002 + 0.006, 0, dz), 0.66 * mr, 0.78 * mr, 0.012, LI, "X")   # thin neon ring on the muzzle face
    if T["rear"]:
        rx0, rx1, rr = T["rear"]
        g0, g1 = rx0 + 0.3 + 0.3 * (rx1 - rx0 - 0.3), rx1 - 0.25 * (rx1 - rx0)
        ax(h, "cone", (rx0 + 0.15, 0, dz), 0.6 * rr, rr, 0.3, SH, "X")             # rear dome
        ax(h, "cyl", ((rx0 + 0.3 + g0) / 2, 0, dz), rr, 0, g0 - (rx0 + 0.3), SH, "X")
        ax(h, "cyl", ((g1 + rx1) / 2, 0, dz), rr, 0, rx1 - g1, SH, "X")
        ax(h, "cyl", ((g0 + g1) / 2, 0, dz), rr - 0.05, 0, g1 - g0, GL, "X")       # glass window band (inset 5 cm)
        ax(h, "cyl", ((g0 + g1) / 2, 0, dz), rr - 0.17, 0, g1 - g0 - 0.04, GO, "X")   # goo inside (the gauge)
        hx, hz = (rx0 + 0.3 + g0) / 2, dz + rr                                     # hatch on the tank's back end
    else:
        hx, hz = xd, dz + Rb                                                       # T1: hatch on the drum
    _prim(h, "cyl", (hx, 0, hz + 0.02), 0.34, 0, 0.24, DE, segs=48)               # hatch (sunk 0.1 into the shell)
    _prim(h, "tube", (hx, 0, hz + 0.14 + 0.008), 0.18, 0.28, 0.012, LI, segs=48)  # thin neon ring on the hatch
    obs = []
    for nm, bm in (("Relay_Cannon_v4", b), ("Head", h)):
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
    return "remade clean: base %d faces, head %d faces%s" % (len(obs[0].data.polygons), len(obs[1].data.polygons),
                                                            ", rear tank + goo gauge" if T["rear"] else "")


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
    if fam == "Cannon":
        return struct_neon(root, piece) + " | " + tower_head(root, piece, int(piece[-1])) + " | " + col
    if fam == "Laser":
        collar = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent is root)
        return (struct_neon(root, piece) + " | " + tower_head(root, piece, 3) + " | " + col + " | collar "
                + struct_neon(collar, piece, keep=lambda c: c.z > 7.2))       # the top hoop stays neon
    if fam == "Forge":                     # top block + chimneys (z > 4.72) and the ooze tube's lid -> cream
        col = cream(root, piece, lambda c: c.z > 4.72 or (math.hypot(c.x, c.y + 0.95) <= 1.01 and 4.2 <= c.z <= 4.55))
        return struct_neon(root, piece, keep=lambda c: c.z > 5.9 and abs(c.y - 0.5) < 0.5) + " | " + col   # 3 chimney rings
    if fam == "Machinegoon":
        return gatling(piece)
    raise ValueError(piece)


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
