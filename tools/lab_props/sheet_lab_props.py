"""Render sheet of the lab props from the game camera (orthographic, 54 deg pitch, 25 deg turn, as the lab-kit sheets),
with a node platform (kit Platform_Standard, labkit) and a unit (VEX at the game's UNIT_SIZE 1.3 m across) for scale.
Run: blender -b --factory-startup --python sheet_lab_props.py -- <props dir> <platform glb> <unit glb> <out png> [prop scale]
prop scale (default 1): uniform scale on the props only (2.05 = the director's 6 m platform ratio on the real 12.3 m platform)."""
import math, os, sys
import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
PD, PLAT, UNIT, OUT = A[:4]
PS = float(A[4]) if len(A) > 4 else 1.0
ROWS = [["specimen-tank", "specimen-pods", "lab-bench", "goo-conveyor", "robot-arm", "valve-manifold", "lamp-post"],
        ["pipe-kit-straight", "pipe-kit-elbow", "pipe-kit-tee", "pipe-kit-cross", "queue-rail", "floor-grate", "steam-vent",
         "planter-box"]]
GAP = 0.9


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def imp(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    return new, roots


def box(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def move(objs, roots, d):
    for r in roots:
        r.location += d
    bpy.context.view_layer.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.render.resolution_x, sc.render.resolution_y = 2000, 1300
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("W")
w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.62, 0.66, 0.64, 1)
bg.inputs[1].default_value = 0.9
sc.world = w
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))   # render light only; the GLBs carry none
sun.data.energy = 2.6
sun.rotation_euler = (math.radians(40), 0, math.radians(-35))
sc.collection.objects.link(sun)

# platform + unit at the left
pobs, proots = imp(PLAT)
lo, hi = box(pobs)
move(pobs, proots, Vector((-hi.x, -(lo.y + hi.y) / 2, -lo.z)))
plo, phi = box(pobs)
plat_d = phi.x - plo.x
uobs, uroots = imp(UNIT)
ulo, uhi = box(uobs)
s = 1.3 / max(uhi.x - ulo.x, uhi.y - ulo.y)
for r in uroots:
    r.scale *= s
bpy.context.view_layer.update()
ulo, uhi = box(uobs)
move(uobs, uroots, Vector((-(ulo.x + uhi.x) / 2 + (plo.x + phi.x) / 2, -(ulo.y + uhi.y) / 2, phi.z - ulo.z + 0.0)))
ulo, uhi = box(uobs)
print("platform %.2f m across, top z %.2f; unit %.2f x %.2f x %.2f m" % (plat_d, phi.z, uhi.x - ulo.x, uhi.y - ulo.y, uhi.z - ulo.z))

allobs = pobs + uobs
yaw = math.radians(25)
R = Vector((math.cos(yaw), math.sin(yaw), 0))      # camera right on the floor
F = Vector((-math.sin(yaw), math.cos(yaw), 0))     # camera up on the floor
start = Vector((phi.x, (plo.y + phi.y) / 2, 0)) + R * 1.5 + F * 3.5
for k, row in enumerate(ROWS):
    t = 0.0
    depth = 0
    for name in row:
        obs, roots = imp(os.path.join(PD, name + ".glb"))
        for r in roots:
            r.scale *= PS
        bpy.context.view_layer.update()
        lo, hi = box(obs)
        half = (hi - lo) / 2
        ext = abs(half.x * R.x) + abs(half.y * R.y)            # half width along the row
        p = start + R * (t + ext) - F * (k * 4.2 * PS)
        move(obs, roots, Vector((p.x - (lo.x + hi.x) / 2, p.y - (lo.y + hi.y) / 2, -lo.z)))
        t += 2 * ext + GAP * PS
        allobs += obs
floor = bpy.data.objects.new("Floor", bpy.data.meshes.new("Floor"))
lo, hi = box(allobs)
c = (lo + hi) / 2
sz = (hi - lo) * 0.5 + Vector((3, 3, 0))
floor.data.from_pydata([(c.x - sz.x, c.y - sz.y, 0), (c.x + sz.x, c.y - sz.y, 0), (c.x + sz.x, c.y + sz.y, 0), (c.x - sz.x, c.y + sz.y, 0)], [], [(0, 1, 2, 3)])
fm = bpy.data.materials.new("FloorCue")
fm.use_nodes = True
b = next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
b.inputs["Base Color"].default_value = (*lin("2F4D4E"), 1)
b.inputs["Roughness"].default_value = 0.9
floor.data.materials.append(fm)
sc.collection.objects.link(floor)
floor.location.z = -0.002

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.type = "ORTHO"
pitch, yaw = math.radians(54), math.radians(25)
d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
cam.location = c + d * 80
cam.rotation_euler = (math.radians(90) - pitch, 0, yaw)
cam.data.clip_end = 300
sc.collection.objects.link(cam)
bpy.context.view_layer.update()
mi = cam.matrix_world.inverted()
pts = [mi @ (o.matrix_world @ Vector(cc)) for o in allobs if o.type == "MESH" for cc in o.bound_box]
xs, ys = [q.x for q in pts], [q.y for q in pts]
cam.location = cam.matrix_world @ Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, 0))
asp = sc.render.resolution_x / sc.render.resolution_y
cam.data.ortho_scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * asp) * 1.04
sc.camera = cam
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("wrote", OUT)
