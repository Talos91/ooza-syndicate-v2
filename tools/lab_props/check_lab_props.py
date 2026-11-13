"""Collision / topology check on the EXPORTED lab props GLBs.
Per GLB: every mesh is split into its connected islands (the unioned shell, each glass chamber, each goo mask).
  overlaps   triangle pairs that intersect between two islands (BVHTree.overlap, world space)          -> must be 0
  self       triangle pairs inside one island that intersect without sharing a vertex                  -> must be 0
  nonmani    edges not shared by exactly two faces                                                     -> must be 0
  floating   islands farther than 0.01 m (vertices + triangle centroids, both ways) from every other island and not standing on the floor (z<=0.01) -> must be none
Run: blender -b --factory-startup --python check_lab_props.py -- <dir with *.glb>"""
import glob, os, sys
import bpy, bmesh
from mathutils.bvhtree import BVHTree

D = sys.argv[sys.argv.index("--") + 1]


def islands(bm):
    seen, out = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(isl)
    return out


def scan(p):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=p)
    over = selfx = nonm = 0
    floating, nisl, tris = [], 0, 0
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)   # glTF splits verts at seams / sharp edges
        bm.faces.ensure_lookup_table()
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        bm.faces.index_update()
        tris += len(bm.faces)
        nonm += sum(1 for e in bm.edges if len(e.link_faces) != 2)
        isl = islands(bm)
        nisl += len(isl)
        trees, vsets = [], []
        for faces in isl:
            vs = sorted({v.index for f in faces for v in f.verts})
            remap = {v: i for i, v in enumerate(vs)}
            co = [bm.verts[v].co.copy() for v in vs]
            polys = [[remap[v.index] for v in f.verts] for f in faces]
            trees.append((BVHTree.FromPolygons(co, polys), co, polys))
        for i in range(len(trees)):
            for j in range(i + 1, len(trees)):
                over += len(trees[i][0].overlap(trees[j][0]))
            t, co, polys = trees[i]
            for a, b in t.overlap(t):
                if a < b and not (set(polys[a]) & set(polys[b])):
                    selfx += 1
        for i, (t, co, polys) in enumerate(trees):
            zmin = min(c.z for c in co)
            if zmin <= 0.01 or len(trees) == 1:
                continue
            def samples(k):        # vertices + triangle centroids (a flat cap's middle has no vertex)
                t_, c_, p_ = trees[k]
                return c_ + [sum((c_[v] for v in poly), c_[poly[0]] * 0) / len(poly) for poly in p_]
            dmin = min(min(min((trees[j][0].find_nearest(c)[3] or 9e9) for c in samples(i)),
                           min((t.find_nearest(c)[3] or 9e9) for c in samples(j))) for j in range(len(trees)) if j != i)
            if dmin > 0.01:
                floating.append("island%d %.3f m" % (i, dmin))
        bm.free()
    return tris, nisl, over, selfx, nonm, floating


fails = 0
for p in sorted(glob.glob(os.path.join(D, "*.glb"))):
    tris, nisl, over, selfx, nonm, fl = scan(p)
    bad = over or selfx or nonm or fl
    fails += bool(bad)
    print("%-22s tris %4d islands %d overlaps %d self %d nonmanifold %d floating %s %s" % (
        os.path.basename(p)[:-4], tris, nisl, over, selfx, nonm, fl or "-", "FAIL" if bad else "ok"))
print("TOTAL files %d failing %d" % (len(glob.glob(os.path.join(D, "*.glb"))), fails))
sys.exit(1 if fails else 0)
