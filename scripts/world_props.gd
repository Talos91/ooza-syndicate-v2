class_name WorldProps
extends Node3D
## SETTING PROPS (props-place 2026-11-14; cosmetic, VIEW ONLY): the lab props (assets/props/lab, placed at x2.05) and the four
## round-33 theme sets (assets/props/<setting>, real metres) standing on the floor under the decks, chosen by the match's setting
## (LookTheme.current). Only maps with a baked placement file get any (R-01 and R-17 for now).
##  - PLACEMENT IS BAKED: assets/props/placement/<map code>_<setting>.json = [{p: prop file, x, z, yaw}] written by
##    tests/props_bake.tscn (this class's bake() with the floor's own rules). Nothing is planned at run time, no map file is touched.
##  - DRAWS: every prop of the match is merged into ONE static mesh with one surface per material (LP_Surfaces, LP_Foliage,
##    OS_Glass, LP_Lens, LP_GooMask = at most 5 draws whatever the prop count), shared materials per setting, no lights, no shadows.
##    (A MultiMesh per prop type costs 1-3 draws per type = 15-25: more than this build can spend, perf-measure-report.)
##  - PAINT STEP B: the atlases are plain textures, assets/props/<setting>/<setting>-surfaces.png / -foliage.png (lab: lab-surfaces /
##    lab-foliage). Repaint those files (same UVs) and every prop of the setting changes; nothing else points at the GLBs' own copies.
## Bake rules: off the visible-floor mask's blind spots and the HUD, clear of pits (RING_R + PIT_CLEAR), tube feet, transport tubes,
## walkway decks and their feed lanes, bridge fall bands and the platforms' own footprints on screen (tap targets), >= 1 prop apart,
## <= MAX_MESHES unique meshes per map.

const DIR := "res://assets/props/"
const PLACEMENT := "res://assets/props/placement/%s_%s.json"
const FOLDER := {"lab": "lab", "corporate_campus": "corporate-campus", "golden_hour": "golden-hour", "quota_parade": "quota-parade",
		"wellness_retreat": "wellness-retreat"}
const SCALE := {"lab": 3.69, "corporate_campus": 1.8, "golden_hour": 1.8, "quota_parade": 1.8, "wellness_retreat": 1.8}            # lab = x2.05 (UI designer 5) x 1.8, themes real metres x 1.8 (UI designer 6: at 1.0 they read as debris, hero ~ half a node)
const MAX_MESHES := 13
const COUNT := 2                        # instances per unique mesh (the bake's default)
# What each setting stands: [file, instances], biggest first. The lab drops the pipe kit's cross + elbow (13 meshes).
const SPEC := {
	"lab": [["specimen-pods", 2], ["goo-conveyor", 2], ["lab-bench", 2], ["specimen-tank", 2], ["valve-manifold", 2], ["queue-rail", 2],
			["robot-arm", 2], ["planter-box", 2], ["steam-vent", 2], ["lamp-post", 2], ["floor-grate", 2], ["pipe-kit-straight", 2],
			["pipe-kit-tee", 2]],
	"corporate_campus": [["striped-snack-kiosk", 2], ["cafe-table-parasol", 3], ["park-bench", 3], ["hedge-block", 3], ["flower-bed-planter", 3],
			["campus-banner", 2], ["campus-lamp", 3], ["potted-topiary-ball", 3]],
	"golden_hour": [["small-tide-pool-rim", 2], ["violet-rock-cluster", 3], ["pink-palm", 3], ["copper-boiler", 2], ["hover-robot", 2],
			["crystal-coral-cluster", 3], ["fern-cluster", 3], ["sunset-lantern", 3]],
	"quota_parade": [["striped-fair-booth", 2], ["marquee-bulb-arch", 2], ["red-rail-section", 3], ["bunting-posts", 3], ["hydrangea-box", 3],
			["tethered-mini-balloon", 3], ["glove-finial", 3], ["harbor-lantern", 3]],
	"wellness_retreat": [["small-fountain-basin", 2], ["lounge-chair-parasol", 3], ["zen-gravel-tray", 3], ["stepping-stone-pad", 3],
			["lavender-bed", 3], ["towel-cart", 2], ["yoga-mat-roll-stack", 3], ["spa-lantern", 3]],
}
const HUD := [Rect2(0.0, 0.1, 0.16, 0.8), Rect2(0.88, 0.2, 0.12, 0.65), Rect2(0.38, 0.0, 0.24, 0.12),
		Rect2(0.86, 0.0, 0.14, 0.12), Rect2(0.0, 0.92, 1.0, 0.08), Rect2(0.09, 0.0, 0.14, 0.26)]   # + the top-left sign       # as WorldDressing: vat gauge, powers, capsule, buttons, hint line
const FALL_BAND := 3.0
const GAP := 0.4                        # m between two props' footprints

static var _mesh_cache := {}            # "<setting>/<file>" -> {mesh, mats (name per surface), aabb}

var wl: WorldLayer
var code := ""
var setting := "lab"
var count := 0
var surfaces := 0
var _y := 0.0
var _cam: Camera3D
var _vp := Vector2(812, 375)
var _occ: Array = []


static func code_of(map_path: String) -> String:
	var f := map_path.get_file()
	var i := f.find("-", 2)                # "R-01-strait.json" -> "R-01"
	return f.substr(0, i) if i > 0 else f.get_basename()


static func has_placement(map_code: String, set_id: String) -> bool:
	return map_code != "" and FileAccess.file_exists(PLACEMENT % [map_code, set_id])


static func _entry(set_id: String, file: String) -> Dictionary:
	## the prop's mesh + material names + bounds (loaded once; the imported GLB's single MeshInstance3D)
	var key := "%s/%s" % [set_id, file]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out := {}
	var ps := load("%s%s/%s.glb" % [DIR, FOLDER[set_id], file]) as PackedScene
	if ps != null:
		var root := ps.instantiate()
		var stack: Array = [root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if out.is_empty() and nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
				var m := (nd as MeshInstance3D).mesh
				var names: Array = []
				var mats: Array = []
				for i in range(m.get_surface_count()):
					var mt := m.surface_get_material(i)
					mats.append(mt)
					names.append(mt.resource_name if mt != null else "")
				out = {"mesh": m, "mats": mats, "names": names, "aabb": m.get_aabb(), "xf": (nd as MeshInstance3D).transform}
			stack.append_array(nd.get_children())
		root.free()
	_mesh_cache[key] = out
	return out


static func _scale(set_id: String) -> float:
	return float(SCALE.get(set_id, 1.0))


# ------------------------------------------------------------------ run time: read the baked file, build the merged mesh
func _ready() -> void:
	name = "Props"
	wl = get_parent() as WorldLayer
	if wl == null or bake_mode:
		return
	_y = wl.floor_y
	if not has_placement(code, setting):
		return
	var f := FileAccess.open(PLACEMENT % [code, setting], FileAccess.READ)
	var rows = JSON.parse_string(f.get_as_text())
	if not rows is Array:
		return
	build(rows)


var bake_mode := false


func build(rows: Array) -> void:
	var sc := _scale(setting)
	var buckets := {}                                  # material name -> {v, n, uv, i}
	var proto := {}                                    # material name -> first GLB material seen
	for r in rows:
		var e := _entry(setting, str(r["p"]))
		if e.is_empty():
			continue
		var m: Mesh = e["mesh"]
		var xf: Transform3D = e["xf"]
		var ab: AABB = e["aabb"]
		var basis := Basis(Vector3.UP, float(r["yaw"])).scaled(Vector3.ONE * sc)
		var t := Transform3D(basis, Vector3(float(r["x"]), _y - ab.position.y * sc, float(r["z"])))
		for si in range(m.get_surface_count()):
			var nm: String = e["names"][si]
			var a := m.surface_get_arrays(si)
			if not buckets.has(nm):
				buckets[nm] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
				proto[nm] = e["mats"][si]
			var b: Dictionary = buckets[nm]
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uv = a[Mesh.ARRAY_TEX_UV]
			var idx = a[Mesh.ARRAY_INDEX]
			if idx == null:
				idx = PackedInt32Array(range(v.size()))
			var bv: PackedVector3Array = b["v"]
			var bn: PackedVector3Array = b["n"]
			var buv: PackedVector2Array = b["uv"]
			var bi: PackedInt32Array = b["i"]
			var base := bv.size()
			for k in range(v.size()):
				bv.append(t * (xf * v[k]))
				bn.append((t.basis * xf.basis * n[k]).normalized())
				buv.append(uv[k] if uv != null else Vector2.ZERO)
			for k in idx:
				bi.append(base + k)
			b["v"] = bv
			b["n"] = bn
			b["uv"] = buv
			b["i"] = bi
		count += 1
	if buckets.is_empty():
		return
	var mesh := ArrayMesh.new()
	for nm in buckets:
		var b: Dictionary = buckets[nm]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b["v"]
		arr[Mesh.ARRAY_NORMAL] = b["n"]
		arr[Mesh.ARRAY_TEX_UV] = b["uv"]
		arr[Mesh.ARRAY_INDEX] = b["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(setting, nm, proto[nm]))
		surfaces += 1
	var mi := MeshInstance3D.new()
	mi.name = "PropsMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static var _mats := {}


static func _material(set_id: String, nm: String, proto: Material) -> Material:
	## one shared material per setting and name; the atlases come from the plain png (swappable), the rest from the GLB's material
	var key := "%s/%s" % [set_id, nm]
	if _mats.has(key):
		return _mats[key]
	var m: Material = proto.duplicate() if proto != null else StandardMaterial3D.new()
	var tex := ""
	if nm == "LP_Surfaces":
		tex = "%s%s/%s-surfaces.png" % [DIR, FOLDER[set_id], FOLDER[set_id]]
	elif nm == "LP_Foliage":
		tex = "%s%s/%s-foliage.png" % [DIR, FOLDER[set_id], FOLDER[set_id]]
	if tex != "" and m is BaseMaterial3D and ResourceLoader.exists(tex):
		(m as BaseMaterial3D).albedo_texture = load(tex)
	_mats[key] = m
	return m


# ------------------------------------------------------------------ bake time (tests/props_bake.gd): where things may stand
func _on_hud(p: Vector3) -> bool:
	if _cam.is_position_behind(p):
		return true
	var s := _cam.unproject_position(p) / _vp
	if s.x < 0.0 or s.y < 0.0 or s.x > 1.0 or s.y > 1.0:
		return true
	for r in HUD:
		if (r as Rect2).grow(0.03).has_point(s):
			return true
	return false


func _lane_d(q: Vector2) -> float:
	var best := INF
	for i in wl.locals.feeds:
		var path: Array = wl.locals.feeds[i]["path"]
		for k in range(1, path.size()):
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, path[k - 1], path[k]).distance_to(q))
	return best


func _deck_d(q: Vector2) -> float:
	## distance from q to the nearest drawn walkway deck's edge (ribbons + roundabouts)
	var best := INF
	for rb in wl.locals.deck_ribbons:
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, rb[0], rb[1]).distance_to(q) - WorldLocals.DECK_HW)
	for dc in wl.locals.deck_discs:
		best = minf(best, absf((dc[0] as Vector2).distance_to(q) - float(dc[1])) - WorldLocals.DECK_HW)
	return best


func _fall_d(q: Vector2) -> float:
	var best := INF
	for e in wl.sim.edges:
		var pa: Vector3 = wl.sim.nodes[int(e["a"])]["pos"]
		var pb: Vector3 = wl.sim.nodes[int(e["b"])]["pos"]
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)).distance_to(q))
	return best


func _on_node(p: Vector3) -> bool:
	## the point's screen position lies on a platform's disc (its tap target) as the camera sees it
	var s := _cam.unproject_position(p)
	for n in wl.sim.nodes:
		var np: Vector3 = n["pos"]
		var c := _cam.unproject_position(np)
		var edge := _cam.unproject_position(np + Vector3(Rules.R, 0, 0))
		if s.distance_to(c) < c.distance_to(edge) * 1.1:
			return true
	return false


func ok(q: Vector2, r: float, h: float) -> bool:
	var lc := wl.locals
	if lc.board_bounds().has_point(q):                  # never inside the board outline (designer 6: R-17, the cones under IN 16)
		return false
	for c in lc.craters:
		if q.distance_to(Vector2((c as Vector3).x, (c as Vector3).z)) < WorldLocals.RING_R + WorldLocals.PIT_CLEAR + 1.0 + r:
			return false
	for tb in wl._tubes:
		if q.distance_to(Vector2(tb["x"], tb["z"])) < float(tb["r"]) + 3.2 + r:
			return false
	if wl.pipes != null and wl.pipes.near(q, r + 0.6):
		return false
	if _fall_d(q) < FALL_BAND + r:
		return false
	if _lane_d(q) < 1.5 + r:
		return false
	if _deck_d(q) < 1.0 + r:
		return false
	for o in _occ:
		if q.distance_to(o[0]) < r + float(o[1]) + GAP:
			return false
	for k in range(9):
		var e := q if k == 8 else q + Vector2.from_angle(TAU * k / 8.0) * r
		var ev := Vector3(e.x, _y, e.y)
		if not lc.floor_visible(_cam, ev) or _on_hud(ev) or _on_hud(Vector3(e.x, _y + h, e.y)) or _on_node(Vector3(e.x, _y + h * 0.5, e.y)):
			return false
	return true


func _dims(set_id: String, file: String) -> Array:
	var e := _entry(set_id, file)
	if e.is_empty():
		return []
	var ab: AABB = e["aabb"]
	var sc := _scale(set_id)
	return [0.36 * Vector2(ab.size.x, ab.size.z).length() * sc, ab.size.y * sc]


func _try(rows: Array, file: String, q: Vector2, d: Array, mid: Vector2, rng: RandomNumberGenerator) -> bool:
	## place a prop at q and at its twin (mirror about x = mid.x), both facing the board's centre; both or neither
	var tw := Vector2(2.0 * mid.x - q.x, q.y)
	if q.distance_to(tw) < 2.0 * float(d[0]) + GAP or not ok(q, d[0], d[1]):
		return false
	_occ.append([q, d[0]])
	var good: bool = ok(tw, d[0], d[1])
	if not good:
		_occ.pop_back()
		return false
	for pt in [q, tw]:
		var f: Vector2 = mid - pt
		var yaw := atan2(f.x, f.y) + float(rng.randi_range(-1, 1)) * TAU / 24.0
		rows.append({"p": file, "x": snappedf(pt.x, 0.01), "z": snappedf(pt.y, 0.01), "yaw": snappedf(yaw, 0.001)})
	_occ.append([tw, d[0]])
	return true


func bake(set_id: String, map_code: String, cam: Camera3D) -> Array:
	## COMPOSED placement (Daniele 2026-11-14: "randomly spread around, don't look good"): mirrored left / right about the board's
	## centre (the pits are mirrored too), in clusters - a hero prop with satellites tucked round it - each cluster on free floor
	## near a pit and facing the board's centre, so a corner reads as a little station or garden instead of scattered specks.
	setting = set_id
	code = map_code
	_cam = cam
	_vp = get_viewport().get_visible_rect().size
	_y = wl.floor_y
	_occ.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_code + set_id)
	var bb := wl.locals.board_bounds()
	var mid := bb.get_center()
	var grown := bb.grow(14.0)
	var left: Array = []
	var step := 1.0
	var x := grown.position.x
	while x <= mid.x:
		var z := grown.position.y
		while z <= grown.end.y:
			left.append(Vector2(x, z))
			z += step
		x += step
	var files: Array = []
	for sp in SPEC[set_id]:
		if not _dims(set_id, str(sp[0])).is_empty() and files.size() < MAX_MESHES:
			files.append(str(sp[0]))
	var nh := mini(4, files.size())                        # hero meshes: the biggest four
	var rows: Array = []
	var anchors: Array = []
	var ci := 0
	for k in range(2):                                     # 2 pairs = 4 clusters at most
		var order: Array = [files[k % nh]]
		var rest: Array = files.duplicate()
		rest.sort_custom(func(x, y): return _dims(set_id, x)[0] > _dims(set_id, y)[0])
		# (no fallback to smaller heroes: when no hero pair fits, place nothing - designer 6, R-17)
		var hero := ""
		var hd: Array = []
		var best := Vector2.ZERO
		for cand in order:
			var cd := _dims(set_id, cand)
			var best_s := -INF
			for q in left:
				var near_pit := INF
				for c in wl.locals.craters:
					near_pit = minf(near_pit, q.distance_to(Vector2((c as Vector3).x, (c as Vector3).z)))
				var spread := 30.0
				for aq in anchors:
					spread = minf(spread, q.distance_to(aq))
				var s := spread * 0.4 + absf(q.x - mid.x) * 0.15 + absf(q.y - mid.y) * 0.25 - absf(near_pit - 12.0) * 0.3 + rng.randf() * 1.5
				if s > best_s and ok(q, cd[0], cd[1]) and ok(Vector2(2.0 * mid.x - q.x, q.y), cd[0], cd[1]):
					best_s = s
					best = q
			if best_s > -INF and _try(rows, cand, best, cd, mid, rng):
				hero = cand
				hd = cd
				break
		if hero == "":
			continue
		anchors.append(best)
		for j in range(2):                                 # up to 2 satellites round the hero
			var sat: String = files[(nh + ci + j) % files.size()] if files.size() > nh else files[(j + 1) % files.size()]
			var sd := _dims(set_id, sat)
			var placed := false
			for ang in range(24):
				var a := TAU * float(ang + j * 6) / 24.0
				var q2: Vector2 = best + Vector2.from_angle(a) * (hd[0] + sd[0] + 0.3 + 0.8 * float(ang / 12))
				if _try(rows, sat, q2, sd, mid, rng):
					placed = true
					break
		ci += 2
	var seen := {}
	for r in rows:
		seen[r["p"]] = int(seen.get(r["p"], 0)) + 1
	print("PROPS bake %s %s: %d props, %d meshes %s" % [map_code, set_id, rows.size(), seen.size(), str(seen)])
	return rows
