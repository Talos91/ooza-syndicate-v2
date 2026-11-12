"""Contact-sheet tiles of the exported lab kit (assets/kit/labkit/*.glb): one Eevee render per tile at the game's 54 deg
pitch, turned 25 deg (as the 26S sheets), transparent film; tiles/<n>.png + tiles.txt for compose_sheet.py.
Owned tiles light OS_Light in a player neon (cyan #00E5FF / red-magenta #FF2B6A) and tint OS_Ooze in an AI goo;
'low' tiles cut each tank's goo at 25 % to show the low-fill fix.
Run: blender -b --factory-startup --python sheet_lab_kit.py -- <labkit dir> <out dir>"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
LK, SHEET = A[0], A[1]
os.makedirs(os.path.join(SHEET, "tiles"), exist_ok=True)
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_lab_kit.py"), encoding="utf-8").read()
exec(src[:src.index("def main():")])      # lin, _islands, _clusters, _bbox (no build)

NEON = {"cyan": "#00E5FF", "magenta": "#FF2B6A"}
GOO = {"VEX": "#2E86AE", "EMBER": "#E76A1E", "SOLAR": "#E4B14E", "BLOOM": "#8ABF35", "NULL": "#C02263"}
TILES = [  # piece, label, neon, goo, low fill
    ("Platform_Standard", "Platform_Standard - neutral", None, None, False),
    ("Platform_Standard", "Platform_Standard - owned (0.5 m rim)", "cyan", None, False),
    ("Platform_Pillar", "Platform_Pillar - owned", "magenta", None, False),
    ("Platform_Relay_v3", "Platform_Relay_v3 (relay deck)", "cyan", None, False),
    ("Relay_Mount", "Relay_Mount", None, None, False),
    ("Deck_S", "Deck_S", None, None, False),
    ("Pier_Connector", "Pier_Connector", None, None, False),
    ("Pier_Angled_30", "Pier_Angled_30 (00-80)", None, None, False),
    ("Deck_Conveyor_Belt_v4_8", "Conveyor v4 (2-20)", None, None, False),
    ("Pit_Ring", "Pit_Ring - VEX goo", None, "VEX", False),
    ("Vat_T1", "Vat_T1 - full", "cyan", "VEX", False),
    ("Vat_T2", "Vat_T2 - full", "cyan", "EMBER", False),
    ("Vat_T3", "Vat_T3 - full", "magenta", "BLOOM", False),
    ("Vat_T4", "Vat_T4 - full", "magenta", "NULL", False),
    ("Floor_Tube_Run_6m", "Floor_Tube_Run_6m - SOLAR", None, "SOLAR", False),
    ("Vat_T1", "Vat_T1 - 25 % fill", "cyan", "VEX", True),
    ("Vat_T2", "Vat_T2 - 25 % fill", "cyan", "EMBER", True),
    ("Vat_T3", "Vat_T3 - 25 % fill", "magenta", "BLOOM", True),
    ("Vat_T4", "Vat_T4 - 25 % fill", "magenta", "NULL", True),
    ("Floor_Tube_Elbow_R080", "Floor_Tube_Elbow_R080 - VEX", None, "VEX", False),
]


def setup():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.62, 0.66, 0.64, 1)
    bg.inputs[1].default_value = 0.9
    sc.world = w
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.6
    sun.rotation_euler = (math.radians(40), 0, math.radians(-35))
    sc.collection.objects.link(sun)


def recolour(neon, goo):
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b is None:
            continue
        nm = m.name.split(".")[0]
        if nm.startswith("OS_Light") and neon:
            c = lin(NEON[neon])
            b.inputs["Base Color"].default_value = (*c, 1)
            b.inputs["Emission Color"].default_value = (*c, 1)
            b.inputs["Emission Strength"].default_value = 3.0
        elif nm.startswith("OS_Ooze") and goo:
            c = lin(GOO[goo])
            b.inputs["Base Color"].default_value = (*c, 1)
            b.inputs["Emission Color"].default_value = (*c, 1)
            b.inputs["Emission Strength"].default_value = 0.35


def low_fill(ob, frac=0.25):
    me = ob.data
    oi = [i for i, m in enumerate(me.materials) if m and m.name.startswith("OS_Ooze")]
    if not oi:
        return
    bm = bmesh.new()
    bm.from_mesh(me)
    for isl in _clusters(_islands(bm, [f for f in bm.faces if f.material_index == oi[0]])):
        x0, y0, z0, x1, y1, z1 = _bbox(isl)
        geom = list(isl) + list({e for f in isl for e in f.edges}) + list({v for f in isl for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z0 + frac * (z1 - z0)), plane_no=(0, 0, 1),
                               clear_outer=True)
    bm.to_mesh(me)
    bm.free()


def frame(objs, zmin=-1e9):
    pts = [o.matrix_world @ v.co for o in objs if o.type == "MESH" for v in o.data.vertices]
    pts = [p for p in pts if p.z > zmin]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    centre = (lo + hi) / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    pitch, yaw = math.radians(54), math.radians(25)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = centre + d * 80
    cam.rotation_euler = (math.radians(90) - pitch, 0, yaw)
    cam.data.clip_end = 300
    cam.data.ortho_scale = max((hi - lo).length * 1.0, 2.0)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def main():
    lines = []
    for i, (piece, label, neon, goo, low) in enumerate(TILES):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        setup()
        bpy.ops.import_scene.gltf(filepath=os.path.join(LK, piece + ".glb"))
        objs = [o for o in bpy.data.objects if o.type in ("MESH", "EMPTY") and o.name not in ("Sun", "Cam")]
        recolour(neon, goo)
        if low:
            for o in objs:
                if o.type == "MESH":
                    low_fill(o)
        frame([o for o in objs if o.type == "MESH"], -12.0 if piece == "Platform_Pillar" else -1e9)   # pillar: top 12 m
        p = os.path.join(SHEET, "tiles", "%02d.png" % i)
        bpy.context.scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        lines.append("%02d.png\t%s" % (i, label))
    open(os.path.join(SHEET, "tiles.txt"), "w", encoding="utf-8").write("\n".join(lines))


main()
