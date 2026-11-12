"""lab-kit 3 (2026-11-12): ONE ASSEMBLED VIEW of the bottom part from the exported GLBs (assets/kit/labkit/): a node base
(tube entrance, turned like the runtime's base45 yaw: flat sockets on world x) + its lift (Node_Tube 12.5 m) under a lab
platform with a vat, a walkway roundabout round the lift on stands + a ramp, a transport tube from the -X socket over the
rim into a pit, a tube from the +X socket into a 1x1 connector block crossed by a second run, a socket climb on +Y.
Saves <blend> (collection LabKit_bottom_assembly, ready to File > Append) and renders <png> (Eevee, low 3/4 view: 22 deg pitch, -30 deg turn,
owner neon cyan, VEX goo in the node's tubes, gray in the pit).
Run: blender -b --factory-startup --python assemble_bottom.py -- <labkit dir> <out.blend> <out.png>"""
import math
import os
import sys

import bpy
from mathutils import Vector

LK, BLEND, PNG = [os.path.abspath(a) for a in sys.argv[sys.argv.index("--") + 1:][:3]]
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sheet_lab_kit.py"), encoding="utf-8").read()
src = src.replace("A = sys.argv[sys.argv.index(\"--\") + 1:]\nLK, SHEET = A[0], A[1]\nos.makedirs(os.path.join(SHEET, \"tiles\"), exist_ok=True)\n", "")
exec(src[:src.rindex("def main():")].replace("LK, SHEET", "_LK, _SH"))     # setup, recolour, lin (rindex: skip the line that execs the builder)

bpy.ops.wm.read_factory_settings(use_empty=True)
setup()
col = bpy.data.collections.new("LabKit_bottom_assembly")
bpy.context.scene.collection.children.link(col)
bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children[col.name]


def put(name, loc=(0, 0, 0), rz=0.0, sz=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(LK, name + ".glb"))
    roots = [o for o in bpy.data.objects if o not in before and o.parent is None]
    for o in roots:
        o.location = Vector(loc)
        o.rotation_mode = "XYZ"
        o.rotation_euler = (0, 0, math.radians(rz))
        o.scale.z = sz
    return roots


put("Node_Base", rz=225)                                   # face 1 (flat socket) -> -X, face 5 -> +X, face 7 (tilted) -> +Y
put("Node_Tube")
put("Platform_Standard", (0, 0, 12.5 + 3.6))               # platform underside (legs / core end at -3.6) on the lift's collar
put("Vat_T2_capneon", (0, 0, 12.5 + 3.6))
put("Walkway_Roundabout", (0, 0, 1.75))
for k in range(4):
    a = math.radians(22.5 + 90 * k)
    put("Walkway_Stand_1m", (2.6 * math.cos(a), 2.6 * math.sin(a), 0), sz=1.75 - 0.16)
a = math.radians(-67.5)
put("Walkway_Ramp", (6.05 * math.cos(a), 6.05 * math.sin(a), 0), rz=-67.5 + 180)
put("Pit", (-9.12, 0, 0))
put("Pit_Tube_Rim_Dip", (-9.12, 0, 0))
for x in (2.92, 4.92):
    put("Pit_Tube_Run_2m", (x, 0, 0))
put("Tube_Connector_1x1", (7.12, 0, 0))
put("Pit_Tube_Run_2m", (9.32, 0, 0))
for y in (2.2, -2.2):
    put("Pit_Tube_Run_2m", (7.12, y, 0), rz=90)
put("Pit_Tube_Socket_Climb", (0, 1.6, 0), rz=90)

recolour("cyan", None)
for m in bpy.data.materials:                                # node tubes VEX, the pit's goo stays native gray
    nm = m.name.split(".")[0]
    if nm.startswith("OS_Ooze") and m.users and m.use_nodes:
        users = [o for o in bpy.data.objects if o.type == "MESH" and m.name in [s.material.name for s in o.material_slots if s.material]]
        if users and not all(o.name.startswith("Pit_Goo") for o in users):
            b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            c = lin(GOO["VEX"])
            b.inputs["Base Color"].default_value = (*c, 1)
            b.inputs["Emission Color"].default_value = (*c, 1)
            b.inputs["Emission Strength"].default_value = 0.35
floor = bpy.data.objects.new("Floor_cue", bpy.data.meshes.new("Floor_cue"))
floor.data.from_pydata([(-16, -9, -0.01), (13, -9, -0.01), (13, 9, -0.01), (-16, 9, -0.01)], [], [(0, 1, 2, 3)])
fm = bpy.data.materials.new("Floor_cue")
fm.use_nodes = True
next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (*lin("#2F4D4E"), 1)
floor.data.materials.append(fm)
col.objects.link(floor)

objs = [o for o in col.all_objects if o.type == "MESH" and o.name != "Floor_cue"]
frame(objs)
sc = bpy.context.scene
sc.render.resolution_x, sc.render.resolution_y = 1600, 1200
cam = sc.camera                                             # low 3/4 view (the 54 deg game pitch shows only the platform's top)
pitch, yaw = math.radians(22), math.radians(-30)
centre = Vector((-2.0, 0.0, 7.5))
d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
cam.location = centre + d * 80
cam.rotation_euler = (math.radians(90) - pitch, 0, yaw)
cam.data.ortho_scale = 31.0
sc.render.filepath = PNG
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND, copy=True)
print("ASSEMBLY", BLEND, PNG, len(objs))
