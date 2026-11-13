"""Round 31 lab props (STEP A locked by Daniele 2026-11-13) -> low-poly GLBs, built by script from PROPS.json.

Run: blender -b --factory-startup --python build_lab_props.py -- <PROPS.json> <out dir>
Out: <out>/<prop>[_<variant>].glb, <out>/lab-surfaces.png, <out>/lab-foliage.png, <out>/LabProps-31A.blend, <out>/props.txt

Per prop ONE mesh (one MultiMesh per type in game), surfaces:
  LP_Surfaces  ivory / mint / rubber, UVs packed into three zones of the shared lab-surfaces atlas (512 px, <= 1024 rule)
  LP_Foliage   planter leaves, shared lab-foliage atlas (256 px)
  OS_Glass     shared glass (runtime Mats rule matches the name OS_Glass)
  LP_GooMask   shared white goo mask (the game tints it), opaque
  LP_Lens      lamp lens, emissive only (no lights anywhere: crash budget)
Opaque parts are unioned (exact boolean) into one closed shell, so no part cuts another (BVH 0) and nothing is non-manifold.
Glass chambers are trimmed to sit 2 mm clear between their collars; goo masks are cut flat 2-4 mm above what they rest on.
Designer answers (CHECK-2026-11-13.md): floor grate = only the part above the floor (sleeve dropped; a 12 mm ivory frame from
its footprint keeps the ivory border of the locked top view); lamp lens emissive only, no light.
Colours = lab-kit values (lab-kit report 2026-11-12): shell #E2CFAE, detail/mint #718A83, recess/rubber #3D5758, glass #AECAC7.
"""
import json, math, os, sys
import bpy, bmesh
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:]
PROPS, OUT = ARGS[0], os.path.abspath(ARGS[1])
os.makedirs(OUT, exist_ok=True)

HEX = {"ivory": "E2CFAE", "mint": "718A83", "rubber": "3D5758", "glass": "AECAC7", "plant": "7E9F78", "plant2": "678A66",
       "goo": "FFFFFF", "lens": "FFF3D6"}
ATLAS = 512
ZONES = {"ivory": (0.0, 0.5, 1.0, 1.0), "mint": (0.0, 0.0, 0.5, 0.5), "rubber": (0.5, 0.0, 1.0, 0.5)}   # u0, v0, u1, v1
PAD = 8.0 / ATLAS
GAP = 0.002


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


# ---------- textures + materials ----------
def make_atlases():
    img = bpy.data.images.new("lab-surfaces", ATLAS, ATLAS, alpha=False)
    px = [0.0] * (ATLAS * ATLAS * 4)
    for key, (u0, v0, u1, v1) in ZONES.items():
        c = lin(HEX[key])   # image pixels are stored linear for a generated float-less image? set colorspace sRGB below
        c = [int(HEX[key][i:i + 2], 16) / 255 for i in (0, 2, 4)]
        for y in range(int(v0 * ATLAS), int(v1 * ATLAS)):
            for x in range(int(u0 * ATLAS), int(u1 * ATLAS)):
                k = (y * ATLAS + x) * 4
                px[k:k + 4] = [c[0], c[1], c[2], 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(OUT, "lab-surfaces.png")
    img.file_format = "PNG"
    img.save()
    n = 256
    fol = bpy.data.images.new("lab-foliage", n, n, alpha=False)
    a = [int(HEX["plant"][i:i + 2], 16) / 255 for i in (0, 2, 4)]
    b = [int(HEX["plant2"][i:i + 2], 16) / 255 for i in (0, 2, 4)]
    px = []
    for y in range(n):                       # soft vertical two-tone: darker leaf base, lighter top (STEP B repaints)
        t = y / (n - 1)
        c = [b[i] * (1 - t) + a[i] * t for i in range(3)]
        px += (c + [1.0]) * n
    fol.pixels = px
    fol.filepath_raw = os.path.join(OUT, "lab-foliage.png")
    fol.file_format = "PNG"
    fol.save()
    return img, fol


def principled(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    return m, b


def tex_mat(name, img, rough):
    m, b = principled(name)
    t = m.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = img
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    return m


def make_materials():
    img, fol = make_atlases()
    M = {"surf": tex_mat("LP_Surfaces", img, 0.45), "foliage": tex_mat("LP_Foliage", fol, 0.8)}
    m, b = principled("OS_Glass")
    b.inputs["Base Color"].default_value = (*lin(HEX["glass"]), 1)
    b.inputs["Alpha"].default_value = 0.18
    b.inputs["Roughness"].default_value = 0.08
    m.surface_render_method = "BLENDED" if hasattr(m, "surface_render_method") else m.blend_method
    M["glass"] = m
    m, b = principled("LP_GooMask")
    b.inputs["Base Color"].default_value = (1, 1, 1, 1)
    b.inputs["Roughness"].default_value = 0.2
    M["goo"] = m
    m, b = principled("LP_Lens")
    c = lin(HEX["lens"])
    b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Emission Color"].default_value = (*c, 1)
    b.inputs["Emission Strength"].default_value = 2.0
    M["lens"] = m
    return M


# ---------- primitives (bmesh, world placement baked in) ----------
def _axis_matrix(axis):
    """local Z -> axis"""
    if axis == "X":
        return Matrix.Rotation(math.radians(90), 4, "Y")
    if axis == "Y":
        return Matrix.Rotation(math.radians(-90), 4, "X")
    return Matrix.Identity(4)


def ring_profile_solid(bm, rings, sides, M):
    """rings: [(radius, z)] bottom->top, closed with caps. Returns nothing (adds to bm)."""
    vs = []
    for r, z in rings:
        row = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            row.append(bm.verts.new(M @ Vector((r * math.cos(a), r * math.sin(a), z))))
        vs.append(row)
    for j in range(len(vs) - 1):
        for i in range(sides):
            bm.faces.new((vs[j][i], vs[j][(i + 1) % sides], vs[j + 1][(i + 1) % sides], vs[j + 1][i]))
    bm.faces.new(list(reversed(vs[0])))
    bm.faces.new(vs[-1])


def prim_cylinder(bm, p):
    c, r, L = Vector(p["center_xyz_m"]), p["diameter_m"] / 2, p["length_m"]
    M = Matrix.Translation(c) @ _axis_matrix(p.get("axis", "Z"))
    ring_profile_solid(bm, [(r, -L / 2), (r, L / 2)], p["sides"], M)


def prim_collar(bm, p):
    c, r, h, bv = Vector(p["center_xyz_m"]), p["diameter_m"] / 2, p["height_m"], p["bevel_m"]
    M = Matrix.Translation(c)
    ring_profile_solid(bm, [(r - bv, -h / 2), (r, -h / 2 + bv), (r, h / 2 - bv), (r - bv, h / 2)], p["sides"], M)


def prim_ellipsoid(bm, p, cut_z=None):
    c, s = Vector(p["center_xyz_m"]), Vector(p["size_xyz_m"]) / 2
    nr, nv = p["radial_segments"], p["vertical_segments"]
    rings = []
    for j in range(1, nv):
        t = math.pi * j / nv
        rings.append((math.sin(t), -math.cos(t)))
    tmp = bmesh.new()
    vs = []
    bot = tmp.verts.new((0, 0, -1))
    top = tmp.verts.new((0, 0, 1))
    for rr, z in rings:
        vs.append([tmp.verts.new((rr * math.cos(2 * math.pi * i / nr), rr * math.sin(2 * math.pi * i / nr), z)) for i in range(nr)])
    for j in range(len(vs) - 1):
        for i in range(nr):
            tmp.faces.new((vs[j][i], vs[j][(i + 1) % nr], vs[j + 1][(i + 1) % nr], vs[j + 1][i]))
    for i in range(nr):
        tmp.faces.new((bot, vs[0][(i + 1) % nr], vs[0][i]))
        tmp.faces.new((top, vs[-1][i], vs[-1][(i + 1) % nr]))
    for v in tmp.verts:
        v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z)) + c
    if cut_z is not None:
        geom = tmp.verts[:] + tmp.edges[:] + tmp.faces[:]
        res = bmesh.ops.bisect_plane(tmp, geom=geom, plane_co=(0, 0, cut_z), plane_no=(0, 0, 1), clear_inner=True)
        cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        bmesh.ops.holes_fill(tmp, edges=cut, sides=0)
        for f in tmp.faces:
            if len(f.verts) > 4 and abs(f.calc_center_median().z - cut_z) < 1e-4:
                bmesh.ops.triangulate(tmp, faces=[f])
                break
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def rrect(w, d, r, segs):
    r = min(r, w / 2 - 1e-4, d / 2 - 1e-4)
    pts = []
    for cx, cy, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for k in range(segs + 1):
            a = math.radians(a0 + 90 * k / segs)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def prim_rprism(bm, p):
    c = Vector(p["center_xyz_m"])
    W, D, H = p["profile_width_depth_height_m"]
    ax, r = p["extrusion_axis"], p["profile_radius_m"]
    segs = 1 if r < 0.06 else 2
    if ax == "Z":
        pw, pd, L, M = W, D, H, Matrix.Translation(c)
    elif ax == "Y":   # profile = first two numbers (X wide, Z tall), extruded along Y by the third (PROPS bounds agree)
        pw, pd, L = W, D, H
        M = Matrix.Translation(c) @ Matrix.Rotation(math.radians(-90), 4, "X")
    else:             # X: profile (Y, Z), extruded along X by the third
        pw, pd, L = W, D, H
        M = Matrix.Translation(c) @ Matrix.Rotation(math.radians(90), 4, "Y") @ Matrix.Rotation(math.radians(90), 4, "Z")
    pts = rrect(pw, pd, r, segs)
    lo = [bm.verts.new(M @ Vector((x, y, -L / 2))) for x, y in pts]
    hi = [bm.verts.new(M @ Vector((x, y, L / 2))) for x, y in pts]
    n = len(pts)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)


def prim_tube(bm, p):
    pts = [Vector(q) for q in p["centerline_xyz_m"]]
    r, n = p["diameter_m"] / 2, p["sides"]
    rows = []
    for k, q in enumerate(pts):
        tin = (q - pts[k - 1]).normalized() if k > 0 else None
        tout = (pts[k + 1] - q).normalized() if k < len(pts) - 1 else None
        t = (tin + tout).normalized() if tin and tout else (tin or tout)
        scale = 1.0
        if tin and tout:
            scale = 1.0 / max(0.3, tin.dot(t))          # miter
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        u = t.cross(ref).normalized()
        v = t.cross(u).normalized()
        row = []
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            off = u * math.cos(a) + v * math.sin(a)
            if tin and tout:                            # stretch only across the bend plane
                bend = (tout - tin)
                if bend.length > 1e-6:
                    bn = bend.normalized()
                    off = off + bn * off.dot(bn) * (scale - 1)
            row.append(bm.verts.new(q + off * r))
        rows.append(row)
    for j in range(len(rows) - 1):
        for i in range(n):
            bm.faces.new((rows[j][i], rows[j][(i + 1) % n], rows[j + 1][(i + 1) % n], rows[j + 1][i]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])


BUILD = {"cylinder": prim_cylinder, "bevelled_collar": prim_collar, "ellipsoid": prim_ellipsoid,
         "rounded_prism": prim_rprism, "swept_tube": prim_tube}


def part_object(name, part, cut_z=None, override=None):
    bm = bmesh.new()
    p = dict(part["parameters_m"])
    if override:
        p.update(override)
    if part["primitive"] == "ellipsoid":
        prim_ellipsoid(bm, p, cut_z)
    else:
        BUILD[part["primitive"]](bm, p)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def zrange(part):
    p = part["parameters_m"]
    c = p["center_xyz_m"][2]
    if part["primitive"] == "cylinder" and p.get("axis", "Z") == "Z":
        return c - p["length_m"] / 2, c + p["length_m"] / 2
    if part["primitive"] == "bevelled_collar":
        return c - p["height_m"] / 2, c + p["height_m"] / 2
    if part["primitive"] == "rounded_prism":
        return c - p["profile_width_depth_height_m"][2] / 2, c + p["profile_width_depth_height_m"][2] / 2
    raise ValueError(part["name"])


def xy(part):
    if "center_xyz_m" not in part["parameters_m"]:
        return None
    if part["primitive"] in ("cylinder",) and part["parameters_m"].get("axis", "Z") != "Z":
        return None
    return tuple(round(v, 3) for v in part["parameters_m"]["center_xyz_m"][:2])


# ---------- one prop ----------
def build_prop(key, variant, v):
    parts = v["parts"]
    opaque, glass, goo = [], [], []
    for i, part in enumerate(parts):
        mat = part["material"]
        if key == "floor-grate" and part["name"] == "Recess sleeve":
            part = json.loads(json.dumps(part))
            part["parameters_m"]["center_xyz_m"][2] = 0.006
            part["parameters_m"]["profile_width_depth_height_m"][2] = 0.012
        if key == "floor-grate" and part["name"] == "Opening":            # keep only its part above the floor
            part = json.loads(json.dumps(part))
            part["parameters_m"]["center_xyz_m"][2] = 0.03
            part["parameters_m"]["profile_width_depth_height_m"][2] = 0.06
        if key == "specimen-pods" and part["primitive"] == "cylinder":   # tri budget (<= 800): 12 -> 10 sides
            part = json.loads(json.dumps(part))
            part["parameters_m"]["sides"] = 10
        if mat == "glass" and key != "lamp-post":
            glass.append(part)
        elif mat == "goo":
            goo.append(part)
        else:
            opaque.append(part)
    # glass chambers: trim to 2 mm clear of the collars directly below / above at the same xy
    gobs = []
    glass_box = {}
    for part in glass:
        z0, z1 = zrange(part)
        below = [zrange(q)[1] for q in opaque if xy(q) == xy(part) and zrange(q)[1] <= (z0 + z1) / 2]
        above = [zrange(q)[0] for q in opaque if xy(q) == xy(part) and zrange(q)[0] >= (z0 + z1) / 2]
        nz0 = max(below) + GAP if below else z0
        nz1 = min(above) - GAP if above else z1
        c = list(part["parameters_m"]["center_xyz_m"])
        c[2] = (nz0 + nz1) / 2
        ob = part_object(part["name"], part, override={"center_xyz_m": c, "length_m": nz1 - nz0})
        ob["lp_mat"] = "glass"
        gobs.append(ob)
        glass_box[xy(part)] = (nz0, nz1, part["parameters_m"]["diameter_m"] / 2)
    # tubes that start inside a glass chamber (tank service pipe) start 2 mm outside it instead
    for k, part in enumerate(opaque):
        if part["primitive"] != "swept_tube":
            continue
        for (gx, gy), (z0, z1, gr) in glass_box.items():
            pts = [list(q) for q in part["parameters_m"]["centerline_xyz_m"]]
            q = pts[0]
            d = math.hypot(q[0] - gx, q[1] - gy)
            if d < gr and z0 < q[2] < z1:
                dx, dy = pts[1][0] - q[0], pts[1][1] - q[1]
                L = math.hypot(dx, dy)
                # move the start along its first segment until the tube's near edge clears the glass
                t = (gr + GAP - d) / L if L else 0
                q[0], q[1] = q[0] + dx * t, q[1] + dy * t
                part = json.loads(json.dumps(part))
                part["parameters_m"]["centerline_xyz_m"] = pts
                opaque[k] = part
    # goo: cut flat just above what it rests on (inside its glass, or on the belt)
    oobs = []
    for part in goo:
        p = part["parameters_m"]
        bottom = p["center_xyz_m"][2] - p["size_xyz_m"][2] / 2
        if xy(part) in glass_box:
            cut = glass_box[xy(part)][0] + 2 * GAP
        else:
            under = [zrange(q)[1] for q in opaque if q["primitive"] == "rounded_prism"
                     and zrange(q)[1] <= p["center_xyz_m"][2] and zrange(q)[1] > bottom - 0.2]
            cut = max(under) + GAP
        ob = part_object(part["name"], part, cut_z=max(cut, bottom + 1e-3))
        ob["lp_mat"] = "goo"
        oobs.append(ob)
    # opaque: union
    obs = []
    for part in opaque:
        ob = part_object(part["name"], part)
        ob["lp_mat"] = {"ivory": "ivory", "mint": "mint", "rubber": "rubber", "plant": "plant", "glass": "lens"}[part["material"]]
        obs.append(ob)
    return obs, gobs, oobs


def assign(ob, M, slots):
    me = ob.data
    for s in slots:
        me.materials.append(M[s])
    idx = slots.index({"ivory": "surf", "mint": "surf", "rubber": "surf", "plant": "foliage", "lens": "lens",
                       "glass": "glass", "goo": "goo"}[ob["lp_mat"]])
    for p in me.polygons:
        p.material_index = idx
    # zone tag for UV packing: remember the material zone per face through a face attribute
    at = me.attributes.new("lp_zone", "INT", "FACE")
    z = {"ivory": 0, "mint": 1, "rubber": 2, "plant": 3, "lens": 4, "glass": 5, "goo": 6}[ob["lp_mat"]]
    for i in range(len(me.polygons)):
        at.data[i].value = z


def union(obs):
    base = obs[0]
    for o in obs[1:]:
        md = base.modifiers.new("U", "BOOLEAN")
        md.operation = "UNION"
        md.solver = "EXACT"
        md.object = o
        md.material_mode = "TRANSFER"
        bpy.context.view_layer.objects.active = base
        bpy.ops.object.modifier_apply(modifier=md.name)
        bpy.data.objects.remove(o)
    return base


def clip_floor(ob):
    """designer answer 2026-11-13: build only the part above the floor (z >= 0); the cut is filled flat."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 0, 1),
                                 clear_inner=True)
    cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    res = bmesh.ops.holes_fill(bm, edges=cut, sides=0)
    zl = bm.faces.layers.int.get("lp_zone")
    for f in res["faces"]:
        f.material_index = 0
        if zl:
            f[zl] = 2        # rubber underside
    bm.to_mesh(ob.data)
    bm.free()


def uv_pack(ob):
    me = ob.data
    zone = me.attributes["lp_zone"]
    zones = [zone.data[i].value for i in range(len(me.polygons))]
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    for zi, zname in ((0, "ivory"), (1, "mint"), (2, "rubber"), (3, "plant")):
        faces = [i for i, z in enumerate(zones) if z == zi]
        if not faces:
            continue
        for p in me.polygons:
            p.select = zones[p.index] == zi
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.02, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        zones = [me.attributes["lp_zone"].data[i].value for i in range(len(me.polygons))]
        uv = me.uv_layers.active.data
        loops = [li for i in faces for li in me.polygons[i].loop_indices]
        us = [uv[li].uv.x for li in loops]
        vs = [uv[li].uv.y for li in loops]
        u0, v0, u1, v1 = ZONES[zname] if zname in ZONES else (0, 0, 1, 1)
        u0, v0, u1, v1 = u0 + PAD, v0 + PAD, u1 - PAD, v1 - PAD
        s = min((u1 - u0) / max(1e-6, max(us) - min(us)), (v1 - v0) / max(1e-6, max(vs) - min(vs)))
        mu, mv = min(us), min(vs)
        for li in loops:
            uv[li].uv = (u0 + (uv[li].uv.x - mu) * s, v0 + (uv[li].uv.y - mv) * s)
    for p in me.polygons:
        p.select = False
    # glass / goo / lens faces: put their UVs on a clean ivory texel (no atlas sampling on those materials anyway)
    uv = me.uv_layers.active.data
    for p in me.polygons:
        if zones[p.index] >= 4:
            for li in p.loop_indices:
                uv[li].uv = (0.5, 0.75)


def finish(ob, name):
    me = ob.data
    ob.name = name
    me.name = name
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(40))
    except AttributeError:
        pass
    if "lp_zone" in me.attributes:
        me.attributes.remove(me.attributes["lp_zone"])


def main():
    data = json.load(open(PROPS, encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = make_materials()
    top = bpy.data.collections.new("LabProps_31A")
    bpy.context.scene.collection.children.link(top)
    lines = []
    x = 0.0
    for key, prop in data["props"].items():
        for variant, v in prop["variants"].items():
            name = key if variant == "standard" else "%s-%s" % (key, variant)
            obs, gobs, oobs = build_prop(key, variant, v)
            slots = []
            for s in ("surf", "foliage", "lens", "glass", "goo"):
                need = {"surf": ("ivory", "mint", "rubber"), "foliage": ("plant",), "lens": ("lens",), "glass": ("glass",), "goo": ("goo",)}[s]
                if any(o["lp_mat"] in need for o in obs + gobs + oobs):
                    slots.append(s)
            for o in obs + gobs + oobs:
                assign(o, M, slots)
            shell = union(obs)
            uv_pack(shell)
            for o in gobs + oobs:
                o.data.uv_layers.new(name="UVMap")
            bpy.ops.object.select_all(action="DESELECT")
            for o in [shell] + gobs + oobs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = shell
            if gobs or oobs:
                bpy.ops.object.join()
            finish(shell, name)
            for c in shell.users_collection:
                c.objects.unlink(shell)
            col = bpy.data.collections.new(name)
            top.children.link(col)
            col.objects.link(shell)
            tris = len(shell.data.polygons)
            # export
            bpy.ops.object.select_all(action="DESELECT")
            shell.select_set(True)
            path = os.path.join(OUT, name + ".glb")
            if os.path.exists(path):
                raise SystemExit("refusing to overwrite " + path)
            bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=True,
                                      export_yup=True, export_lights=False, export_cameras=False)
            lo = [min((shell.matrix_world @ vv.co)[i] for vv in shell.data.vertices) for i in range(3)]
            hi = [max((shell.matrix_world @ vv.co)[i] for vv in shell.data.vertices) for i in range(3)]
            lines.append("%s\t%d\t%d\t%s\t%s\t%s" % (name, tris, v.get("guide_triangle_count", 0), os.path.getsize(path),
                                                       " ".join("%.3f" % (hi[i] - lo[i]) for i in range(3)),
                                                       ",".join(s for s in slots)))
            shell.location.x = x - lo[0]
            x += (hi[0] - lo[0]) + 1.0
            print("built", lines[-1])
    open(os.path.join(OUT, "props.txt"), "w").write("name\ttris\tguide\tbytes\tsize_xyz\tsurfaces\n" + "\n".join(lines) + "\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "LabProps-31A.blend"))


main()
