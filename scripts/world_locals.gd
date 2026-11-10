class_name WorldLocals
extends Node3D
## LOCALS (cosmetic, VIEW ONLY, no rules): the lab's CONTAINMENT RING craters on the world floor, where the gray native
## goo (the Locals, WORLD-LORE-2026-11) wells up to load the vats. WORLD PASS 2 (Daniele: "a NON-STOP queue at every
## tube"): each tube with a door is fed by its nearest crater; its Locals rise out of the pool, hop the rim and walk the
## feed's path to the back of ONE line that runs from the tube's door back toward the crater (at most LINE_MAX, and no
## more than the path holds; a full line = the crater stops sending to that tube). The line is read from the Sim
## (read only): Locals enter the door at the node's production pace (shown units / s: one Local per shown unit, as fast
## as the shuffle allows, WALK_V / GAP); a node at its cap (or with no vat) admits none, so its line stands still until
## room returns, then moves up.
## GPU-DRIVEN (L1): one MultiMesh; the CPU writes a Local's path data once per event (spawn, queue advance, door entry,
## melt) into its instance transform and the vertex shader (shaders/world_local.gdshader) moves it from a per-frame
## `now`: rise, droplets, hop, plop, walk, bob, breathing, door squash. Paths live in a small float texture (row per feed).
## Art: Models/2.0/world-1.0/build_containment_ring.py (ring v1) + build_tube_entrance_v2.py (four doors).
## Layouts (--craters=1|2|4): 1 = the map centre; 2 = the board's left and right side; 4 = near each corner of the
## board's bounding box - each nudged to the nearest floor the default camera sees (platforms and bridges block it).
## PITS / TUBES (Daniele 2026-11-07, 05 Handoff/PITS-TUBES-2026-11.md): 4 pits at the map corners is the default (rule 1;
## 1 / 2 stay as flags); the Locals enter the column base by its door nearest their pit (WorldTubes' base: 4 doors);
## at the match start each pit sends a column of MARCH_N Locals to its nearest node (R6, ties: lower node id) - the
## node's own feed when that pit feeds it, else a one-off march feed (key MARCH_KEY + pit) to the door facing the pit.
## Every feed names its tube ("tube"); the pits' pool colour comes from WorldTubes (R7, tint_pit).
## Lab biome: the floor decals (world_decals.gd: spawn surrounds, march lanes, tube-foot pools, stains, arcs).

const RING_GLB := "res://assets/world/containment_ring_v1.glb"
const SHADER_RING := preload("res://shaders/world_ring.gdshader")
const SHADER_LOCAL := preload("res://shaders/world_local.gdshader")

const LOCALS_MAX := 1500          # the pool (STRAIT steady state ~600)
const LINE_MAX := 30              # Locals in one tube's line at most
const LOCAL_SIZE := 1.0           # m long (L3; was 0.62)
const WALK_V := 1.6               # m/s on the floor (the line shuffles at this too: WALK_V / GAP Locals / s at most)
const GAP := 1.15                 # m between Locals in a line
const SPAWN_GAP := 0.6            # s at most between two Locals sent to the same tube (faster for a faster vat)
const EMERGE_T := 1.0             # s: rising out of the pool
const HOP_T := 0.9                # s: the hop over the rim
const SQUEEZE_T := 0.6            # s: squash + shrink through the door
const MELT_T := 0.6
const DOOR_OUT := 2.3             # m from the tube axis: the first slot of the line (the base's door frame is at 1.68)
const DOOR_MOUTH := 1.45          # m: where a Local vanishes into the door (inside the base's wall at 1.6)
const APPROACH := 3.0             # m: the last stretch runs straight along the door's axis
const PATH_PTS := 16              # waypoints per feed in the paths texture (texel 16 = mouth, points, length)
const RING_R := 5.0               # containment ring v1: outer radius
const POOL_R := 3.5
const POOL_H := 0.55
const RIM_H := 0.80
const TUBE_AVOID := 2.4           # m: a path keeps this far from another tube's axis (base corner r 1.73, sockets 1.92)
const RING_AVOID := 5.6
const PLAT_R := Rules.R           # a platform's radius (the board's footprint)
const BRIDGE_HALF := 1.4
const SEARCH_R := 16.0            # m: how far a crater may move from its layout target to reach visible floor
const DEFAULT_LAYOUT := 4         # PITS / TUBES rule 1 (was 2)
const MARCH_N := 12               # R6: Locals in a pit's match-start column
const MARCH_GAP := 0.32           # s between them leaving the pit
const MARCH_KEY := 10000          # feeds key of pit k's march feed: MARCH_KEY + k
const MARCH_WINDOW := 10.0        # s of sim time: pits placed later than this (a joined / fast-forwarded match) send none
# The parallel worker's floor plan (maps without one fall back to the ray test below): a visibility mask of
# the floor at the default camera (255 seen, 128 seen only when panned / zoomed, 0 never; 16 px/m, world x,z -80..80,
# pixel (0,0) = (-80,-80), +z down) and open spots. Layout 2 = the board's two side courtyards, layout 4 = the open
# spots nearest the board's four corners, layout 1 = the map centre (Daniele) whatever shows of it.
# The plan ships baked in res:// (PLAN_RES_DIR: the json plus the mask PNG imported as "keep", so the web export carries it);
# the Drive folder (PLAN_DIR) is read only in an editor / tool run when no res:// copy exists (OOZE_NO_DRIVE_PLAN=1 skips it).
const PLAN_RES_DIR := "res://assets/world/floor_plan/"
const PLAN_DIR := "H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/refs/09-floor-plan-%s/"

var wl: WorldLayer
var layout := DEFAULT_LAYOUT
var craters: Array = []           # Vector3 on the floor
var targets: Array = []           # the layout's targets before the visibility nudge (debug view)
var crater_vis: Array = []        # share of the ring the default camera sees
var feeds: Dictionary = {}        # tube index -> {crater, dir, path, len, row, cap, line, next_spawn, next_admit, rate}
var placed := false
var spawned := 0
var admitted := 0
var writes := 0                   # instance writes so far (the CPU touches a Local only on its events)
var _t := 0.0
var _ring_mm: MultiMesh
var _loc_mm: MultiMesh
var _loc_mat: ShaderMaterial
var _syncs := 0
var _debug: MeshInstance3D
var plan: Dictionary = {}         # the floor plan JSON (empty: none for this map)
var _mask: Image
var _mask_px := 16.0
var _mask_x0 := -80.0
var _mask_z0 := -80.0
var step_us := 0                  # the last step's CPU cost (perf probe)
var decals: WorldDecals
# per Local (slot) - the CPU's copy of what its instance holds
var _ts := PackedFloat64Array()   # spawn time
var _tw := PackedFloat64Array()   # walk clock start
var _d0 := PackedFloat64Array()   # distance along the path at _tw
var _d1 := PackedFloat64Array()   # its slot's distance (the walk stops there)
var _td := PackedFloat64Array()   # door time (> 0), melt time (< 0), 0 none
var _row := PackedInt32Array()    # the feed's path row
var _px := PackedFloat32Array()   # where it wells up
var _pz := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _size := PackedFloat32Array()
var _free: Array[int] = []
var _hwm := 0
var _dying: Array = []            # [slot, free at]
var _alive := 0
var _paths_tex: ImageTexture


static func layout_arg() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--craters="):
			var n := int(a.substr(10))
			if n in [1, 2, 4]:
				return n
	return DEFAULT_LAYOUT


func setup(w: WorldLayer) -> void:
	wl = w
	layout = layout_arg()
	_load_plan()
	var ring_mesh := _glb_mesh(RING_GLB)
	var rm := ShaderMaterial.new()
	rm.shader = SHADER_RING
	rm.set_shader_parameter("abyss", wl.haze_abyss())
	if wl.floor_haze >= 0.0:
		rm.set_shader_parameter("haze", wl.floor_haze)
	_ring_mm = MultiMesh.new()
	_ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ring_mm.use_colors = true                       # the Compatibility renderer multiplies COLOR by it (black without)
	_ring_mm.use_custom_data = true
	_ring_mm.mesh = ring_mesh
	_ring_mm.instance_count = 4
	_ring_mm.visible_instance_count = 0
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = _ring_mm
	rmi.material_override = rm
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rmi)
	_loc_mat = ShaderMaterial.new()
	_loc_mat.shader = SHADER_LOCAL
	_loc_mat.set_shader_parameter("abyss", wl.haze_abyss())
	if wl.floor_haze >= 0.0:
		_loc_mat.set_shader_parameter("haze", wl.floor_haze)
	_loc_mat.set_shader_parameter("floor_y", wl.floor_y)
	_loc_mat.set_shader_parameter("pool_y", wl.floor_y + POOL_H)
	_loc_mat.set_shader_parameter("walk_v", WALK_V)
	_loc_mat.set_shader_parameter("emerge_t", EMERGE_T)
	_loc_mat.set_shader_parameter("hop_t", HOP_T)
	_loc_mat.set_shader_parameter("squeeze_t", SQUEEZE_T)
	_loc_mat.set_shader_parameter("rim_h", RIM_H)
	_loc_mm = MultiMesh.new()
	_loc_mm.transform_format = MultiMesh.TRANSFORM_3D
	_loc_mm.use_colors = true                        # (white, set once per slot: see the Compatibility note above)
	_loc_mm.mesh = local_mesh()
	_loc_mm.instance_count = LOCALS_MAX
	_loc_mm.visible_instance_count = 0
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = _loc_mm
	lmi.material_override = _loc_mat
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lmi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))   # the transforms hold data, not poses
	add_child(lmi)
	_ts.resize(LOCALS_MAX)                           # (packed arrays are values: each resized by name)
	_tw.resize(LOCALS_MAX)
	_d0.resize(LOCALS_MAX)
	_d1.resize(LOCALS_MAX)
	_td.resize(LOCALS_MAX)
	_px.resize(LOCALS_MAX)
	_pz.resize(LOCALS_MAX)
	_seed.resize(LOCALS_MAX)
	_size.resize(LOCALS_MAX)
	_row.resize(LOCALS_MAX)


static func local_mesh() -> ArrayMesh:
	## L3: a Local - a glossy goo drop, LOCAL_SIZE long (+Z forward), 0.78 wide, 0.64 tall: 10 sides (the silhouette the
	## 54 deg camera sees is the shoulder ring), a foot ring, the shoulder and a leaning crown (30 tris), plus two droplet
	## quads (4 tris, UV.x = 1 / 2: the shader flings them while it wells up, round in the fragment). 34 tris.
	var n := 10
	var prof := [[0.0, 0.42, 0.0], [0.24, 0.50, 0.0]]   # [y, radius, z shift (a forward lean)]
	var apex := Vector3(0, 0.64, 0.1)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := []
	var sx := 0.78 * LOCAL_SIZE
	var sz := 1.0 * LOCAL_SIZE
	for r in prof:
		for k in range(n):
			var a := TAU * k / n
			var p := Vector3(sin(a) * float(r[1]) * sx, float(r[0]) * LOCAL_SIZE, cos(a) * float(r[1]) * sz + float(r[2]))
			vs.append(p)
			ns.append(Vector3(p.x / sx, (p.y - 0.24) * 1.4, (p.z - float(r[2])) / sz).normalized())
			uvs.append(Vector2.ZERO)
	vs.append(apex * Vector3(1, LOCAL_SIZE, 1))
	ns.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	var top := vs.size() - 1
	for ring in range(prof.size() - 1):
		for k in range(n):
			var a0 := ring * n + k
			var a1 := ring * n + (k + 1) % n
			var b0 := a0 + n
			var b1 := a1 + n
			var out := (vs[a0] + vs[a1] + vs[b0] + vs[b1]) * Vector3(1, 0, 1)
			_tri(vs, idx, a0, a1, b1, out)
			_tri(vs, idx, a0, b1, b0, out)
	var last := (prof.size() - 1) * n
	for k in range(n):
		var a0 := last + k
		var a1 := last + (k + 1) % n
		_tri(vs, idx, a0, a1, top, Vector3.UP + (vs[a0] + vs[a1]) * Vector3(1, 0, 1))
	for j in range(2):                                   # droplets: corners in the camera plane (shader billboards them)
		var b := vs.size()
		for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			vs.append(Vector3(c.x, c.y, 0.0))
			ns.append(Vector3(0, 0, 1))
			uvs.append(Vector2(1.0 + j, 0.0))
		_tri(vs, idx, b, b + 1, b + 2, Vector3(0, 0, 1))
		_tri(vs, idx, b, b + 2, b + 3, Vector3(0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(idx)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _tri(vs: PackedVector3Array, idx: Array, a: int, b: int, c: int, out: Vector3) -> void:
	## Godot's front face: (c - a) x (b - a) points out (SurfaceTool.generate_normals' convention)
	if (vs[c] - vs[a]).cross(vs[b] - vs[a]).dot(out) < 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _glb_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var found: Mesh = null
	var stack: Array = [root]
	while not stack.is_empty() and found == null:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			found = (nd as MeshInstance3D).mesh
		stack.append_array(nd.get_children())
	root.free()
	return found


# ------------------------------------------------------------------ placement
func _load_plan() -> void:
	var mp = wl.get_parent().get("map_path") if wl.get_parent() != null else null
	var code := str(mp).get_file().substr(0, 4) if mp != null else ""
	if code == "":
		return
	var dir := PLAN_RES_DIR
	if not FileAccess.file_exists(dir + code + "-floor-plan.json"):
		if OS.has_feature("template") or OS.get_environment("OOZE_NO_DRIVE_PLAN") == "1":
			return
		dir = PLAN_DIR % code
	var jf := FileAccess.open(dir + code + "-floor-plan.json", FileAccess.READ)
	if jf == null:
		return
	var j = JSON.parse_string(jf.get_as_text())
	if not (j is Dictionary):
		return
	plan = j
	_mask_px = float(plan.get("px_per_m", 16.0))
	var wr: Dictionary = plan.get("world_rect_m", {})
	_mask_x0 = float(wr.get("x0", -80.0))
	_mask_z0 = float(wr.get("z0", -80.0))
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(dir + code + "-floor-visible-mask.png")) != OK:
		img = null
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_L8)
		_mask = img


func mask_at(x: float, z: float) -> int:
	## the plan's mask value at a floor point (-1: no plan / outside it)
	if _mask == null:
		return -1
	var i := int((x - _mask_x0) * _mask_px)
	var k := int((z - _mask_z0) * _mask_px)
	if i < 0 or k < 0 or i >= _mask.get_width() or k >= _mask.get_height():
		return 0
	return int(round(_mask.get_pixel(i, k).r * 255.0))


func _plan_targets(b: Rect2) -> Array:
	var inside: Array = plan.get("open_spots_inside_map_radius", [])
	var outer: Array = plan.get("open_spots_default_view", [])
	if layout == 1:
		return [Vector2.ZERO]
	if layout == 2:                                   # the two side courtyards: the inside spots nearest (+-x, centre z)
		var c := b.get_center()
		return [_nearest_spot(inside, Vector2(b.position.x, c.y), []), _nearest_spot(inside, Vector2(b.end.x, c.y), [])]
	var used := []
	var out := []
	for corner in [b.position, Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), b.end]:
		var q := _nearest_spot(outer, corner, used)
		used.append(q)
		out.append(q)
	return out


static func _nearest_spot(spots: Array, to: Vector2, used: Array) -> Vector2:
	var best := to
	var bd := INF
	for sp in spots:
		var q := Vector2(float(sp["x"]), float(sp["z"]))
		if q in used:
			continue
		if q.distance_to(to) < bd:
			bd = q.distance_to(to)
			best = q
	return best


func board_bounds() -> Rect2:
	## the board's footprint on the floor plan: every platform disc (x, z), padded by the platform radius
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in wl.sim.nodes:
		var p: Vector3 = n["pos"]
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	if lo.x == INF:
		return Rect2()
	return Rect2(lo - Vector2.ONE * PLAT_R, hi - lo + Vector2.ONE * PLAT_R * 2.0)


func place(cam: Camera3D) -> void:
	## the layout's targets, each moved to the nearest floor the camera sees (ring sampled at 9 points), clear of the
	## tube feet and of the other craters
	var b := board_bounds()
	var c := b.get_center()
	var out := RING_R + 1.0                           # "just outside" the footprint
	targets.clear()
	match layout:
		1:
			targets = [c]
		2:
			targets = [Vector2(b.position.x - out, c.y), Vector2(b.end.x + out, c.y)]
		_:
			targets = [Vector2(b.position.x - out, b.position.y - out), Vector2(b.end.x + out, b.position.y - out),
					Vector2(b.position.x - out, b.end.y + out), Vector2(b.end.x + out, b.end.y + out)]
	craters.clear()
	crater_vis.clear()
	if layout == 4:                                   # v2 (Daniele 2026-11-09): the 4 corners MIRROR on both axes
		_place_symmetric(cam, b)
		_after_place(cam)
		return
	if not plan.is_empty():
		targets = _plan_targets(b)
	for tg in targets:
		if not plan.is_empty():                       # the plan's spots are already on visible floor: no nudge
			craters.append(Vector3(tg.x, wl.floor_y, tg.y))
			crater_vis.append(_ring_visible(cam, tg))
			continue
		var best := Vector2(tg)
		var best_s := -INF
		var best_v := 0.0
		var step := 1.5
		var n := int(SEARCH_R / step)
		for ix in range(-n, n + 1):
			for iz in range(-n, n + 1):
				var q: Vector2 = tg + Vector2(ix, iz) * step
				var dq := q.distance_to(tg)
				if dq > SEARCH_R or not _clear(q):
					continue
				var v := _ring_visible(cam, q)
				var s := v * 10.0 - dq * 0.25
				if s > best_s:
					best_s = s
					best = q
					best_v = v
		craters.append(Vector3(best.x, wl.floor_y, best.y))
		crater_vis.append(best_v)
	_after_place(cam)


func _place_symmetric(cam: Camera3D, b: Rect2) -> void:
	## PITS v2 (Daniele 2026-11-09: "not symmetric, 2 on left and 2 on right"): ONE offset (dx, dz) from the board's centre,
	## the pits at centre + (-dx, -dz), (+dx, -dz), (-dx, +dz), (+dx, +dz) - mirror-symmetric left/right and top/bottom.
	## The offset starts just outside the footprint's corners and moves (both axes, all 4 pits together) to the one whose
	## LEAST visible pit the default camera sees best, clear of every tube foot; nearest the corner target on a tie.
	targets.clear()
	var c := b.get_center()
	var out := RING_R + 1.0
	var ideal := b.size * 0.5 + Vector2.ONE * out
	var min_d := Vector2(RING_R + 2.0, RING_R + 2.0)  # the two pits of a side never touch (2 RING_R + 4 apart)
	var step := 1.0
	var n := int(SEARCH_R * 1.5 / step)
	var best := ideal
	var best_s := -INF
	var best_v := []
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var o: Vector2 = ideal + Vector2(ix, iz) * step
			if o.x < min_d.x or o.y < min_d.y:
				continue
			var d := o.distance_to(ideal)
			if d > SEARCH_R * 1.5:
				continue
			var ok := true
			var vmin := INF
			var vs := []
			for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var q: Vector2 = c + o * sg
				if not _clear_feet(q):
					ok = false
					break
				var v := _ring_visible(cam, q)
				vs.append(v)
				vmin = minf(vmin, v)
			if not ok:
				continue
			var s := vmin * 10.0 - d * 0.25
			if s > best_s:
				best_s = s
				best = o
				best_v = vs
	for k in range(4):
		var sg: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)][k]
		var q: Vector2 = c + best * sg
		targets.append(c + ideal * sg)
		craters.append(Vector3(q.x, wl.floor_y, q.y))
		crater_vis.append(float(best_v[k]) if k < best_v.size() else 0.0)


func _clear_feet(q: Vector2) -> bool:
	for tb in wl._tubes:
		if q.distance_to(Vector2(tb["x"], tb["z"])) < RING_R + float(tb["r"]) + 1.6:
			return false
	return true


func _after_place(cam: Camera3D) -> void:
	for i in range(craters.size()):
		var p: Vector3 = craters[i]
		_ring_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.37 * i), p))
		var g := WorldLayer.NATIVE_GRAY
		_ring_mm.set_instance_custom_data(i, Color(float(i) * 1.7, g.r, g.g, g.b))
		_ring_mm.set_instance_color(i, Color.WHITE)
	_ring_mm.visible_instance_count = craters.size()
	placed = true
	_route_all()
	if wl.pipes != null:
		wl.pipes.build()                              # the transport tubes keep clear of the lanes' exits
	if wl.floor_lab5 and not "--no-decals" in OS.get_cmdline_user_args():   # the lab floor decals (world pass 2)
		decals = WorldDecals.new()
		add_child(decals)
		decals.setup(wl._floor.material_override as ShaderMaterial, wl.floor_y)
		decals.build(self, cam)
		wl.decals = decals


func _clear(q: Vector2) -> bool:
	for tb in wl._tubes:
		if q.distance_to(Vector2(tb["x"], tb["z"])) < RING_R + float(tb["r"]) + 1.6:
			return false
	for p in craters:
		if q.distance_to(Vector2((p as Vector3).x, (p as Vector3).z)) < RING_R * 2.0 + 4.0:
			return false
	return true


func _ring_visible(cam: Camera3D, q: Vector2) -> float:
	var pts := [Vector3(q.x, wl.floor_y + POOL_H, q.y)]
	for k in range(8):
		var a := TAU * k / 8.0
		pts.append(Vector3(q.x + cos(a) * RING_R, wl.floor_y + 0.3, q.y + sin(a) * RING_R))
	var seen := 0
	for p in pts:
		if floor_visible(cam, p):
			seen += 1
	return float(seen) / pts.size()


func floor_visible(cam: Camera3D, p: Vector3) -> bool:
	## the plan's mask when there is one (rendered ID pass: exact), else on screen (outside the HUD margins of the
	## 812 x 375 phone frame) and not behind a platform disc or a bridge (a ray test: misses the decks' machinery)
	var mv := mask_at(p.x, p.z)
	if mv >= 0:
		return mv > 200
	if cam == null or cam.is_position_behind(p):
		return false
	var vp := cam.get_viewport().get_visible_rect().size
	var s := cam.unproject_position(p)
	var k := vp.y / 375.0
	if s.x < 100.0 * k or s.x > vp.x - 16.0 * k or s.y < 48.0 * k or s.y > vp.y - 78.0 * k:
		return false
	var o := cam.global_position
	for n in wl.sim.nodes:
		var np: Vector3 = n["pos"]
		if absf(o.y - p.y) < 0.01:
			continue
		var t := (np.y - o.y) / (p.y - o.y)
		if t <= 0.0 or t >= 1.0:
			continue
		var hit := o.lerp(p, t)
		if Vector2(hit.x - np.x, hit.z - np.z).length() < PLAT_R:
			return false
	for e in wl.sim.edges:
		var g: Dictionary = e["geo"]
		if not g.has("A"):
			continue
		var ya: float = (wl.sim.nodes[e["a"]]["pos"] as Vector3).y
		var yb: float = (wl.sim.nodes[e["b"]]["pos"] as Vector3).y
		var y := (ya + yb) / 2.0
		var t := (y - o.y) / (p.y - o.y)
		if t <= 0.0 or t >= 1.0:
			continue
		var hit := o.lerp(p, t)
		var a2 := Vector2(g["A"][0], g["A"][1])
		var b2 := Vector2(g["B"][0], g["B"][1])
		if Geometry2D.get_closest_point_to_segment(Vector2(hit.x, hit.z), a2, b2).distance_to(Vector2(hit.x, hit.z)) < BRIDGE_HALF:
			return false
	return true


# ------------------------------------------------------------------ routes
const DOOR_DIRS := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]   # +Z (v1's door), +X, -Z, -X


func _route_all() -> void:
	## one feed per tube with a door: its nearest crater, the door facing it, a path from the crater's rim to the door's
	## first slot (the last APPROACH metres straight on the door's axis) - the line forms back along that path
	feeds.clear()
	var rows := 0
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb.get("ent", false) or craters.is_empty():
			continue                                  # pillar sleeves have no doors
		var t2 := Vector2(tb["x"], tb["z"])
		var ci := 0
		var cd := INF
		for k in range(craters.size()):
			var d: float = t2.distance_to(Vector2(craters[k].x, craters[k].z))
			if d < cd:
				cd = d
				ci = k
		var c2 := Vector2(craters[ci].x, craters[ci].z)
		var dir: Vector2 = DOOR_DIRS[0]
		var dd := INF
		for d2 in DOOR_DIRS:
			var dist: float = (t2 + d2 * DOOR_OUT).distance_to(c2)
			if dist < dd:
				dd = dist
				dir = d2
		var slot0 := t2 + dir * DOOR_OUT
		var appr := t2 + dir * (DOOR_OUT + APPROACH)
		var exit := c2 + (appr - c2).normalized() * (RING_R + 0.4)
		var path := _steer(exit, appr, i, 0)
		path.push_front(exit)
		path.append(appr)
		path.append(slot0)
		while path.size() > PATH_PTS:                 # (never seen: a path bends round at most a few feet)
			path.remove_at(path.size() / 2)
		var plen := _plen(path)
		feeds[i] = {"tube": i, "crater": ci, "dir": dir, "path": path, "len": plen, "row": rows, "line": [],
				"cap": clampi(int((plen - 0.6) / GAP) + 1, 1, LINE_MAX), "next_spawn": randf() * SPAWN_GAP,
				"next_admit": 0.0, "rate": 0.0, "mouth": t2 + dir * DOOR_MOUTH}
		rows += 1
	if wl.sim.time <= MARCH_WINDOW or "--march" in OS.get_cmdline_user_args():
		rows = _route_marches(rows)
	_build_paths_tex(rows)


func _route_marches(rows: int) -> int:
	## R6: each pit's match-start column to its nearest node with a door (ties: the lower node id)
	for k in range(craters.size()):
		var c2 := Vector2(craters[k].x, craters[k].z)
		var best := -1
		var bd := INF
		for i in range(wl._tubes.size()):
			var tb: Dictionary = wl._tubes[i]
			if not tb.get("ent", false):
				continue
			var d := c2.distance_to(Vector2(tb["x"], tb["z"]))
			if d < bd - 0.001 or (best >= 0 and absf(d - bd) <= 0.001 and int(tb["id"]) < int(wl._tubes[best]["id"])):
				bd = d
				best = i
		if best < 0:
			continue
		if feeds.has(best) and int(feeds[best]["crater"]) == k:
			feeds[best]["march"] = MARCH_N            # its own feed is the column: it leaves the pit at the march pace
			continue
		var tb2: Dictionary = wl._tubes[best]
		var t2 := Vector2(tb2["x"], tb2["z"])
		var taken: Vector2 = feeds[best]["dir"] if feeds.has(best) else Vector2.ZERO
		var dir: Vector2 = DOOR_DIRS[0]
		var dd := INF
		for d2 in DOOR_DIRS:
			if d2 == taken:
				continue                              # another door than the node's own line
			var dist: float = (t2 + d2 * DOOR_OUT).distance_to(c2)
			if dist < dd:
				dd = dist
				dir = d2
		var slot0 := t2 + dir * DOOR_OUT
		var appr := t2 + dir * (DOOR_OUT + APPROACH)
		var exit := c2 + (appr - c2).normalized() * (RING_R + 0.4)
		var path := _steer(exit, appr, best, 0)
		path.push_front(exit)
		path.append(appr)
		path.append(slot0)
		while path.size() > PATH_PTS:
			path.remove_at(path.size() / 2)
		var plen := _plen(path)
		feeds[MARCH_KEY + k] = {"tube": best, "crater": k, "dir": dir, "path": path, "len": plen, "row": rows, "line": [],
				"cap": clampi(int((plen - 0.6) / GAP) + 1, 1, MARCH_N), "next_spawn": 0.0, "next_admit": 0.0, "rate": 0.0,
				"mouth": t2 + dir * DOOR_MOUTH, "march": MARCH_N, "only_march": true}
		rows += 1
	return rows


func tint_pit(k: int, c: Color) -> void:
	## R7 (WorldTubes): the pit's pool colour (INSTANCE_CUSTOM gba; r stays its swirl phase)
	if k < _ring_mm.visible_instance_count:
		_ring_mm.set_instance_custom_data(k, Color(float(k) * 1.7, c.r, c.g, c.b))


func _build_paths_tex(rows: int) -> void:
	## the feeds' paths for the vertex shader: RGBA32F, row = feed, texel k = (x, z, distance along), texel 16 = (mouth x,
	## mouth z, points, length)
	var img := Image.create(PATH_PTS + 1, maxi(rows, 1), false, Image.FORMAT_RGBAF)
	for i in feeds:
		var f: Dictionary = feeds[i]
		var path: Array = f["path"]
		var cum := 0.0
		for k in range(path.size()):
			if k > 0:
				cum += (path[k] as Vector2).distance_to(path[k - 1])
			img.set_pixel(k, int(f["row"]), Color((path[k] as Vector2).x, (path[k] as Vector2).y, cum, 0.0))
		var m: Vector2 = f["mouth"]
		img.set_pixel(PATH_PTS, int(f["row"]), Color(m.x, m.y, float(path.size()), cum))
	_paths_tex = ImageTexture.create_from_image(img)
	_loc_mat.set_shader_parameter("paths", _paths_tex)


func _obstacles(skip_tube: int) -> Array:
	var obs := []
	for j in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[j]
		var r := TUBE_AVOID if is_equal_approx(float(tb["r"]), WorldLayer.TUBE_R) else float(tb["r"]) + 0.8
		if j == skip_tube:
			r = 2.1                                   # its own base: walk round it to the door side
		obs.append([Vector2(tb["x"], tb["z"]), r])
	for p in craters:
		obs.append([Vector2((p as Vector3).x, (p as Vector3).z), RING_AVOID])
	return obs


func _steer(a: Vector2, b: Vector2, tube: int, depth: int) -> Array:
	## straight a -> b, unless a tube foot / another crater is in the way: one detour point beside it, then recurse
	if depth > 5:
		return []
	var worst = null
	var worst_t := INF
	for ob in _obstacles(tube):
		var c: Vector2 = ob[0]
		var r: float = ob[1]
		if c.distance_to(a) < r - 0.05 or c.distance_to(b) < r - 0.05:
			continue                                  # the endpoint sits in it (the crater of origin): ignore
		var q := Geometry2D.get_closest_point_to_segment(c, a, b)
		if q.distance_to(c) < r:
			var t := a.distance_to(q)
			if t < worst_t:
				worst_t = t
				worst = ob
	if worst == null:
		return []
	var c2: Vector2 = worst[0]
	var r2: float = worst[1]
	var q2 := Geometry2D.get_closest_point_to_segment(c2, a, b)
	var n := q2 - c2
	if n.length() < 0.01:
		n = (b - a).orthogonal()
	var w := c2 + n.normalized() * (r2 + 0.35)
	var left := _steer(a, w, tube, depth + 1)
	var right := _steer(w, b, tube, depth + 1)
	return left + [w] + right


static func _plen(path: Array) -> float:
	var s := 0.0
	for k in range(1, path.size()):
		s += (path[k] as Vector2).distance_to(path[k - 1])
	return s


static func _along(path: Array, d: float) -> Array:
	## [point, direction] at distance d along the polyline
	for k in range(1, path.size()):
		var a: Vector2 = path[k - 1]
		var b: Vector2 = path[k]
		var l := a.distance_to(b)
		if d <= l or k == path.size() - 1:
			var dir := (b - a) / maxf(l, 0.001)
			return [a + dir * clampf(d, 0.0, l), dir]
		d -= l
	return [path[-1], Vector2(0, 1)]


# ------------------------------------------------------------------ per frame (events only: the shader moves them)
func prewarm(seconds: float) -> void:
	## dev / shots: run the lines so the frame shows the steady state (the game itself starts empty at the match start)
	var n := int(seconds / 0.1)
	for i in range(n):
		step(0.1, false)


func step(dt: float, _draw := true) -> void:
	_syncs += 1
	if not placed:
		var cam := get_viewport().get_camera_3d()
		if _syncs < 3 or cam == null:
			return
		place(cam)
	var t0 := Time.get_ticks_usec()
	_t += dt
	_loc_mat.set_shader_parameter("now", _t)
	while not _dying.is_empty() and _t >= float(_dying[0][1]):
		_free.append(int(_dying.pop_front()[0]))      # its instance already draws nothing (the shader ended it)
		_alive -= 1
	for i in feeds:
		_feed_step(int(feeds[i]["tube"]), feeds[i])
	step_us = Time.get_ticks_usec() - t0


func vat_rate(n: Dictionary) -> float:
	## L2 (read only, no rule): the node's production now in shown units / s - an owned vat under its cap (allied troops
	## count, as Sim.step), a neutral vat regrowing to its garrison; 0 at the cap or with no vat
	var sim := wl.sim
	if not Sim.has_vat(n) or sim.collapsed.get(n["id"], false):
		return 0.0
	if n["owner"] != "":
		if sim.garrison_total(n) >= float(Rules.CAPS[n["tier"]]) - 0.001:
			return 0.0
		return Rules.shown_f(sim._base_production(n) * float(sim._prod_info(n)[0]))
	if Rules.NEUTRAL_REGEN and float(n["units"]) < float(n.get("regen_cap", Rules.NEUTRAL_UNITS.get(n["tier"], 0))):
		return Rules.shown_f(Rules.PROD[n["tier"]])
	return 0.0


func _feed_step(i: int, f: Dictionary) -> void:
	var tb: Dictionary = wl._tubes[i]
	var line: Array = f["line"]
	# Daniele 2026-11-11: "locals don't march to them until a player captured it" - a neutral node gets no Local (its own
	# line and a pit's match-start march wait, march count kept, and start once a player owns it); a line whose node
	# falls back to neutral melts like a dead tube's.
	var unowned := str(wl.sim.nodes[tb["id"]]["owner"]) == ""
	if not tb.get("shown", false) or not tb["alive"] or unowned:
		if not line.is_empty():                       # the tube is gone (or the node neutral): its line melts where it stands
			for s in line:
				var dn := _dnow(s)
				_d0[s] = dn
				_d1[s] = dn
				_tw[s] = _t
				_td[s] = -_t
				_write(s)
				_dying.append([s, _t + MELT_T + 0.05])
			line.clear()
		f["rate"] = 0.0
		return
	var rate := vat_rate(wl.sim.nodes[tb["id"]])
	var only_march := bool(f.get("only_march", false))
	if only_march:
		rate = WALK_V / GAP                           # R6: the march column files in as fast as it walks
	f["rate"] = rate
	var plen: float = f["len"]
	# the door: the front Local goes in at the vat's pace, once it stands at the first slot
	if rate > 0.0 and not line.is_empty() and _t >= float(f["next_admit"]):
		var s0: int = line[0]
		if _dnow(s0) >= plen - 0.02:
			_td[s0] = _t
			_write(s0)
			_dying.append([s0, _t + SQUEEZE_T + 0.05])
			line.pop_front()
			admitted += 1
			f["next_admit"] = _t + 1.0 / rate
			for k in range(line.size()):              # the line moves up one slot
				var s: int = line[k]
				_d0[s] = _dnow(s)
				_tw[s] = maxf(_t, _tw[s])
				_d1[s] = plen - k * GAP
				_write(s)
	# the crater: one more Local toward the back of the line, unless the line is full (then it stops sending here)
	if only_march and int(f.get("march", 0)) <= 0:
		return                                        # the march is out: this feed sends no more
	if line.size() < int(f["cap"]) and _t >= float(f["next_spawn"]) and _alive < LOCALS_MAX:
		var gap := clampf(0.8 / maxf(rate, 0.8), 0.3, SPAWN_GAP) * randf_range(0.75, 1.3)
		if int(f.get("march", 0)) > 0:                # R6: the match-start column leaves the pit in step
			gap = MARCH_GAP
			f["march"] = int(f["march"]) - 1
		f["next_spawn"] = _t + gap
		_spawn(f, line)


func _spawn(f: Dictionary, line: Array) -> void:
	var s: int
	if not _free.is_empty():
		s = _free.pop_back()
	else:
		s = _hwm
		_hwm += 1
		_loc_mm.set_instance_color(s, Color.WHITE)
		_loc_mm.visible_instance_count = _hwm
	var cp: Vector3 = craters[int(f["crater"])]
	var exit: Vector2 = (f["path"] as Array)[0]
	var dir2 := (exit - Vector2(cp.x, cp.z)).normalized()
	var a := randf() * TAU
	var rr := sqrt(randf()) * (POOL_R - 1.0)
	var from := Vector2(cp.x + cos(a) * rr, cp.z + sin(a) * rr)
	from = from.lerp(Vector2(cp.x, cp.z) + dir2 * (POOL_R - 1.1), 0.4)   # well up toward the exit side
	_ts[s] = _t
	_tw[s] = _t + EMERGE_T + HOP_T
	_d0[s] = 0.0
	_d1[s] = float(f["len"]) - line.size() * GAP
	_td[s] = 0.0
	_row[s] = int(f["row"])
	_px[s] = from.x
	_pz[s] = from.y
	_seed[s] = randf()
	_size[s] = randf_range(0.9, 1.1)
	_write(s)
	line.append(s)
	spawned += 1
	_alive += 1


func _dnow(s: int) -> float:
	return minf(_d0[s] + WALK_V * maxf(_t - _tw[s], 0.0), _d1[s])


func _write(s: int) -> void:
	## the one place a Local's instance changes: its path data (see shaders/world_local.gdshader)
	_loc_mm.set_instance_transform(s, Transform3D(Basis(Vector3(_ts[s], _tw[s], _d0[s]), Vector3(_d1[s], _td[s], float(_row[s])),
			Vector3(_px[s], _pz[s], _seed[s])), Vector3(_size[s], 0.0, 0.0)))
	writes += 1


func count() -> int:
	return _alive


func queued() -> int:
	## Locals standing in a line (arrived at their slot)
	var q := 0
	for i in feeds:
		for s in (feeds[i] as Dictionary)["line"]:
			if _dnow(s) >= _d1[s] - 0.02 and _t >= _tw[s]:
				q += 1
	return q


func lines() -> Array:
	## per fed tube: [node id, line length, cap, rate (shown / s)] (probes)
	var out := []
	for i in feeds:
		var f: Dictionary = feeds[i]
		out.append([int(wl._tubes[int(f["tube"])]["id"]), (f["line"] as Array).size(), int(f["cap"]), snappedf(float(f["rate"]), 0.01)])
	return out


# ------------------------------------------------------------------ debug overlay (shots)
func debug_overlay(on: bool, cam: Camera3D = null) -> void:
	## top-down debug: the board's footprint (platform discs, bridges), the floor the default camera sees (green dots) /
	## sees only when panned or zoomed (amber, plan mask) / never (red), crater targets (yellow cross) and craters (white ring), every feed path (cyan) and door (white)
	if _debug != null:
		_debug.queue_free()
		_debug = null
	if not on:
		return
	var im := ImmediateMesh.new()
	var y := wl.floor_y + 0.9
	var b := board_bounds()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if cam != null:
		var stp := 2.0
		var x := b.position.x - 22.0
		while x <= b.end.x + 22.0:
			var z := b.position.y - 22.0
			while z <= b.end.y + 22.0:
				var v := floor_visible(cam, Vector3(x, wl.floor_y, z))
				var dc := Color(0.2, 0.9, 0.3) if v else Color(0.75, 0.15, 0.15)
				if not v and mask_at(x, z) == 128:
					dc = Color(0.85, 0.6, 0.1)            # seen only when the player pans / zooms
				_quad(im, Vector2(x, z), 0.32, y - 0.2, dc)
				z += stp
			x += stp
	for i in feeds:
		var f: Dictionary = feeds[i]
		var path: Array = f["path"]
		for k in range(1, path.size()):
			_seg(im, path[k - 1], path[k], 0.22, y, Color(0.2, 0.95, 1.0))
		var tb: Dictionary = wl._tubes[int(f["tube"])]
		var t2 := Vector2(tb["x"], tb["z"])
		var dir: Vector2 = f["dir"]
		_seg(im, t2 + dir * 1.2, t2 + dir * DOOR_OUT, 0.5, y + 0.05, Color(1, 1, 1))
	for tg in targets:
		_seg(im, tg + Vector2(-1.5, -1.5), tg + Vector2(1.5, 1.5), 0.3, y + 0.1, Color(1, 0.85, 0.1))
		_seg(im, tg + Vector2(-1.5, 1.5), tg + Vector2(1.5, -1.5), 0.3, y + 0.1, Color(1, 0.85, 0.1))
	for p in craters:
		var c2 := Vector2((p as Vector3).x, (p as Vector3).z)
		for k in range(24):
			var a0 := TAU * k / 24.0
			var a1 := TAU * (k + 1) / 24.0
			_seg(im, c2 + Vector2(cos(a0), sin(a0)) * (RING_R + 0.4), c2 + Vector2(cos(a1), sin(a1)) * (RING_R + 0.4), 0.35,
					y + 0.1, Color(1, 1, 1))
	im.surface_end()
	# outlines of the platforms and bridges (the board above, which hides the floor at the real camera)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for nd in wl.sim.nodes:
		var np: Vector3 = nd["pos"]
		for k in range(32):
			var a0 := TAU * k / 32.0
			var a1 := TAU * (k + 1) / 32.0
			_seg(im, Vector2(np.x, np.z) + Vector2(cos(a0), sin(a0)) * PLAT_R, Vector2(np.x, np.z) + Vector2(cos(a1), sin(a1)) * PLAT_R,
					0.18, y + 0.15, Color(0.85, 0.5, 1.0))
	for e in wl.sim.edges:
		var g: Dictionary = e["geo"]
		if g.has("A"):
			_seg(im, Vector2(g["A"][0], g["A"][1]), Vector2(g["B"][0], g["B"][1]), 0.18, y + 0.15, Color(0.85, 0.5, 1.0))
	im.surface_end()
	_debug = MeshInstance3D.new()
	_debug.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	_debug.material_override = m
	add_child(_debug)


static func _quad(im: ImmediateMesh, c: Vector2, r: float, y: float, col: Color) -> void:
	_seg(im, c - Vector2(r, 0), c + Vector2(r, 0), r * 2.0, y, col)


static func _seg(im: ImmediateMesh, a: Vector2, b: Vector2, w: float, y: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var n := d.orthogonal().normalized() * w * 0.5
	var v := [a + n, b + n, b - n, a - n]
	for i in [0, 1, 2, 0, 2, 3]:
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(v[i].x, y, v[i].y))
