"""BVH collision check on the EXPORTED lab kit GLBs (assets/kit/labkit/*.glb).
Every pair of mesh nodes in a GLB: 0 triangle overlaps (BVHTree.overlap, world space). Every mesh node that is not the
root must be attached: its nearest distance to another node <= 0.01 m, or its box inside another node's box (a goo
volume inside its glass). Prints one line per GLB and a total; exit code 1 on any failure.
Run: blender -b --factory-startup --python check_lab_kit_bvh.py -- <labkit dir>"""
import glob, os, sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

D = sys.argv[sys.argv.index("--") + 1]
fails = 0
goo_checks = []
EXCLUSIVE = {frozenset(("Treads", "TreadsRev"))}   # conveyor: one shown per flow direction (proto_relay_view.gd)
pairs_total = 0
for p in sorted(glob.glob(os.path.join(D, "*.glb"))):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=p)
    dg = bpy.context.evaluated_depsgraph_get()
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    trees, boxes = {}, {}
    for o in obs:
        trees[o] = BVHTree.FromObject(o, dg, deform=True)
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        boxes[o] = ([min(v[i] for v in bb) for i in range(3)], [max(v[i] for v in bb) for i in range(3)])
    # FromObject gives local coords: rebuild in world space
    trees = {}
    for o in obs:
        me = o.evaluated_get(dg).to_mesh()
        vs = [o.matrix_world @ v.co for v in me.vertices]
        trees[o] = BVHTree.FromPolygons(vs, [list(f.vertices) for f in me.polygons])
        o.evaluated_get(dg).to_mesh_clear()
    over, floating = [], []
    for i, a in enumerate(obs):
        for b in obs[i + 1:]:
            if frozenset((a.name, b.name)) in EXCLUSIVE:
                continue
            pairs_total += 1
            n = len(trees[a].overlap(trees[b]))
            if n:
                over.append("%s x %s: %d" % (a.name, b.name, n))
    for o in obs:
        if o.parent is None and o.name not in ("Glass",):
            continue
        others = [q for q in obs if q is not o]
        if not others:
            continue
        me = o.data
        dmin = min(min((trees[q].find_nearest(o.matrix_world @ v.co)[3] or 9e9) for v in me.vertices) for q in others)
        inside = any(all(boxes[q][0][k] - 1e-3 <= boxes[o][0][k] and boxes[o][1][k] <= boxes[q][1][k] + 1e-3 for k in range(3))
                     for q in others)
        if dmin > 0.01 and not inside:
            floating.append("%s %.3f m" % (o.name, dmin))
    for o in obs:                                   # inside one mesh: the goo volume must not cut its glass
        me = o.data
        names = [m.name.split(".")[0] if m else "" for m in me.materials]
        gl = [p for p in me.polygons if names[p.material_index].startswith("OS_Glass")]
        go = [p for p in me.polygons if names[p.material_index].startswith("OS_Ooze")]
        if gl and go:
            vs = [o.matrix_world @ v.co for v in me.vertices]
            n = len(BVHTree.FromPolygons(vs, [list(p.vertices) for p in gl]).overlap(
                BVHTree.FromPolygons(vs, [list(p.vertices) for p in go])))
            goo_checks.append(n)
            if n:
                over.append("%s goo x glass: %d" % (o.name, n))
    ok = not over and not floating
    fails += 0 if ok else 1
    print("BVH %-28s nodes %d  overlaps %s  floating %s  %s" % (os.path.basename(p), len(obs),
          "; ".join(over) or "0", "; ".join(floating) or "0", "OK" if ok else "FAIL"))
print("BVH TOTAL files %d, node pairs %d, goo-in-glass meshes %d, failing files %d" % (len(glob.glob(os.path.join(D, "*.glb"))), pairs_total, len(goo_checks), fails))
