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
const LINE_MAX := 90              # Locals in one tube's line at most (Daniele 2026-11-11: the line fills the whole walkway and moves at the vat's pace; was 30)
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
const PATH_PTS := 32              # waypoints per feed in the paths texture (texel 32 = mouth, points, length; texel .w = height over the floor)
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
const WALK_LEVELS := [1.75, 2.45, 3.15]   # walkway layer (Daniele 2026-11-11): 3 concentric rings, each closer to the centre one level higher
const DECK_HW := 0.8              # deck half width
const DECK_T := 0.16
const RAIL_H := 0.45              # the hand rails either side of a walkway
const NEON_DASH := false          # Daniele 2026-11-11: no dashed neon line on the walkways, the rails are enough (true brings it back)
const DASH := 0.9                 # the neon centre line: dash / gap (m)
const DASH_GAP := 0.7
const ABOUT_GAP := 0.3            # m between a column and the roundabout a walkway makes round it (Daniele 2026-11-11: a walkway that
                                  # reaches a column never runs through it, it goes round - on any map)
const RAMP_LEN := 3.2              # m: the ramp between the floor and a walkway (the rest of a bridge is level)
const LOW_DECK := 1.6             # m: a ramp / bridge lower than this is no place for a tube to pass under (the tubes keep off it)
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
var walkways := false
var _deck_mi: MeshInstance3D
var _tq: Array = []               # the shared queues: one per stretch of walkway that several feeds walk (see _build_queues)
var _abouts: Array = []           # the roundabouts the feeds' paths take: [centre, radius, height, joint angle, joint angle]
var about_at: Array = []          # probes: [centre, height] of each roundabout
var about_count := 0              # probes: roundabouts built
var deck_tris := 0                # probes: the walkway mesh's triangles
var _rings: Array = []            # per ring (0 = outer): half extents (x, z) round _wctr
var _wctr := Vector2.ZERO


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
	sync_walkways()
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
static func door_dirs() -> Array:
	## the base's walk-in doors: +Z (v1's door), +X, -Z, -X; with --base45 the diagonals
	if WorldTubes.base45():
		var r := 0.70710678
		return [Vector2(r, r), Vector2(r, -r), Vector2(-r, -r), Vector2(-r, r)]
	return [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]


func _route_all() -> void:
	## one feed per tube with a door: its nearest crater, the door facing it, a path from the crater's rim to the door's
	## first slot (the last APPROACH metres straight on the door's axis) - the line forms back along that path
	feeds.clear()
	_abouts.clear()
	walkways = walkways_wanted()
	if walkways:
		_walk_rings()
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
		var dir: Vector2 = door_dirs()[0]
		var dd := INF
		for d2 in door_dirs():
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
		var hs: Array = []
		var wp := _walk_path(t2, c2, Vector2.ZERO) if walkways else {}
		if not wp.is_empty():                         # walkway layer: pit -> ramp -> rings -> diagonal bridge -> door
			dir = wp["dir"]
			path = wp["pts"]
			hs = wp["hs"]
		while path.size() > PATH_PTS:                 # (never seen: a path bends round at most a few feet)
			path.remove_at(path.size() / 2)
			if not hs.is_empty():
				hs.remove_at(hs.size() / 2)
		var plen := _plen(path)
		feeds[i] = {"tube": i, "crater": ci, "dir": dir, "path": path, "len": plen, "row": rows, "line": [],
				"hs": hs, "cap": clampi(int((plen - 0.6) / GAP) + 1, 1, LINE_MAX), "next_spawn": randf() * SPAWN_GAP,
				"next_admit": 0.0, "rate": 0.0, "mouth": t2 + dir * DOOR_MOUTH}
		rows += 1
	if wl.sim.time <= MARCH_WINDOW or "--march" in OS.get_cmdline_user_args():
		rows = _route_marches(rows)
	_build_queues()
	_build_paths_tex(rows)


func _lcp(pa: Array, pb: Array) -> float:
	## how far two paths run together from the pit (m)
	if (pa[0] as Vector2).distance_to(pb[0]) > 0.05:
		return 0.0
	var ia := 1
	var ib := 1
	var pos: Vector2 = pa[0]
	var d := 0.0
	while ia < pa.size() and ib < pb.size():
		var da: Vector2 = (pa[ia] as Vector2) - pos
		var db: Vector2 = (pb[ib] as Vector2) - pos
		if da.length() < 0.02:
			ia += 1
			continue
		if db.length() < 0.02:
			ib += 1
			continue
		if da.normalized().dot(db.normalized()) < 0.999:
			break
		var stp := minf(da.length(), db.length())
		pos += da.normalized() * stp
		d += stp
	return d


func _build_queues() -> void:
	## Daniele 2026-11-11: Locals never overlap. Where several feeds walk the same stretch of walkway, that stretch is ONE queue
	## (a trunk); a Local standing in it belongs to no door yet. When a door's own line has room, the trunk's first Local walks
	## on into it and the trunk moves up, drawing the next one from the trunk before it (or from the pit). A tree per pit exit.
	_tq.clear()
	var groups := {}
	for fk in feeds:
		var f: Dictionary = feeds[fk]
		f["parent"] = -1
		f["q0"] = 0.0
		var e: Vector2 = (f["path"] as Array)[0]
		var gk := Vector3(float(f["crater"]), roundf(e.x * 10.0), roundf(e.y * 10.0))
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append(fk)
	for gk in groups:
		_queue_tree(groups[gk], 0.0, -1)
	for fk in feeds:
		var f: Dictionary = feeds[fk]
		var room := int((float(f["len"]) - float(f["q0"]) - 0.7 * GAP) / GAP) + 1
		f["cap"] = clampi(mini(room, int(f["cap"])), 1, LINE_MAX)


func _queue_tree(keys: Array, start: float, parent: int) -> void:
	if keys.size() == 1:
		feeds[keys[0]]["parent"] = parent
		feeds[keys[0]]["q0"] = start
		return
	var m := INF                                          # how far ALL of them run together
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			m = minf(m, _lcp(feeds[keys[i]]["path"], feeds[keys[j]]["path"]))
	var node := parent
	var from := start
	if m > start + GAP * 1.5:
		var lo := maxf(start, 1.0)
		_tq.append({"s0": start, "s1": m, "row": int(feeds[keys[0]]["row"]), "rep": keys[0], "line": [], "parent": parent,
				"cap": maxi(int((m - lo) / GAP), 1), "next_spawn": 0.0, "want": {}, "last": -1})
		node = _tq.size() - 1
		from = m
	var clusters: Array = []
	for k in keys:
		var placed_in := -1
		for ci in range(clusters.size()):
			if _lcp(feeds[k]["path"], feeds[clusters[ci][0]]["path"]) > m + 0.05:
				placed_in = ci
				break
		if placed_in >= 0:
			clusters[placed_in].append(k)
		else:
			clusters.append([k])
	if clusters.size() == 1:                              # (identical paths: each keeps its own line)
		for k in keys:
			feeds[k]["parent"] = node
			feeds[k]["q0"] = from
		return
	for cl in clusters:
		_queue_tree(cl, from, node)


func _take(ti: int, into: Array, row: int, d1: float, who: int) -> bool:
	## the first Local of trunk ti walks on to slot d1 of `into` (a door's line or the next trunk); the trunk moves up
	var tl: Array = _tq[ti]["line"]
	var want: Dictionary = _tq[ti]["want"]
	want[who] = _syncs
	if tl.is_empty():
		return false
	if int(_tq[ti]["last"]) == who:                    # turns: whoever took the last one waits while another line is asking
		for w in want:
			if w != who and int(want[w]) >= _syncs - 1:
				return false
	_tq[ti]["last"] = who
	var s: int = tl.pop_front()
	_d0[s] = _dnow(s)
	_tw[s] = maxf(_t, _tw[s])
	_d1[s] = d1
	_row[s] = row
	_write(s)
	into.append(s)
	for k in range(tl.size()):
		var s2: int = tl[k]
		_d0[s2] = _dnow(s2)
		_tw[s2] = maxf(_t, _tw[s2])
		_d1[s2] = float(_tq[ti]["s1"]) - (k + 1) * GAP
		_write(s2)
	return true


func _trunk_step() -> void:
	## every trunk keeps itself full: from the trunk before it, or from the pit (never closer than one Local's gap)
	for ti in range(_tq.size()):
		var T: Dictionary = _tq[ti]
		var tl: Array = T["line"]
		if tl.size() >= int(T["cap"]):
			continue
		var d1: float = float(T["s1"]) - (tl.size() + 1) * GAP
		if int(T["parent"]) >= 0:
			_take(int(T["parent"]), tl, int(T["row"]), d1, 1000 + ti)
		elif _t >= float(T["next_spawn"]) and _alive < LOCALS_MAX and feeds.has(T["rep"]):
			T["next_spawn"] = _t + GAP / WALK_V * randf_range(1.0, 1.25)
			_spawn(feeds[T["rep"]], tl, d1)


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
		var dir: Vector2 = door_dirs()[0]
		var dd := INF
		for d2 in door_dirs():
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
		var hs: Array = []
		var wp := _walk_path(t2, c2, taken) if walkways else {}
		if not wp.is_empty():
			dir = wp["dir"]
			path = wp["pts"]
			hs = wp["hs"]
		while path.size() > PATH_PTS:
			path.remove_at(path.size() / 2)
			if not hs.is_empty():
				hs.remove_at(hs.size() / 2)
		var plen := _plen(path)
		feeds[MARCH_KEY + k] = {"tube": best, "crater": k, "dir": dir, "path": path, "len": plen, "row": rows, "line": [],
				"hs": hs, "cap": clampi(int((plen - 0.6) / GAP) + 1, 1, MARCH_N), "next_spawn": 0.0, "next_admit": 0.0, "rate": 0.0,
				"mouth": t2 + dir * DOOR_MOUTH, "march": MARCH_N, "only_march": true}
		rows += 1
	return rows


func walkways_wanted() -> bool:
	## the walkway layer follows the tube mode (floor-level tubes in --tubes=connectors); --walkways=1|0 forces it
	var on: bool = wl.pipes != null and wl.pipes.floor_mode()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--walkways="):
			on = a.substr(11) == "1"
	return on


func reroute() -> void:
	## the tube mode changed (WorldTubes.rebuild): the feeds' paths follow the walkways (or not)
	_route_all()


func sync_walkways() -> void:
	## (re)builds the deck mesh once the tubes are laid (the stands keep clear of them)
	if _deck_mi != null:
		_deck_mi.queue_free()
		_deck_mi = null
	if walkways and not feeds.is_empty():
		_build_walkways()


func _walk_rings() -> void:
	## 3 concentric rectangles round the board's centre, each between two rows / columns of vats; the outer one just past the outermost
	var bb := board_bounds()
	_wctr = bb.get_center()
	var xs: Array = []
	var zs: Array = []
	for tb in wl._tubes:
		if not tb.get("ent", false):
			continue
		var ax := snappedf(absf(float(tb["x"]) - _wctr.x), 0.5)
		var az := snappedf(absf(float(tb["z"]) - _wctr.y), 0.5)
		if not xs.has(ax):
			xs.append(ax)
		if not zs.has(az):
			zs.append(az)
	xs.sort()
	zs.sort()
	_rings.clear()
	if xs.size() >= 3 and zs.size() >= 3:
		var nx := xs.size()
		var nz := zs.size()
		_rings.append(Vector2(float(xs[nx - 1]) + (float(xs[nx - 1]) - float(xs[nx - 2])) * 0.5, float(zs[nz - 1]) + (float(zs[nz - 1]) - float(zs[nz - 2])) * 0.5))
		_rings.append(Vector2((float(xs[nx - 1]) + float(xs[nx - 2])) * 0.5, (float(zs[nz - 1]) + float(zs[nz - 2])) * 0.5))
		_rings.append(Vector2((float(xs[nx - 2]) + float(xs[nx - 3])) * 0.5, (float(zs[nz - 2]) + float(zs[nz - 3])) * 0.5))
	else:                                                 # few rows: fractions of the board
		for f in [0.97, 0.68, 0.4]:
			_rings.append(bb.size * 0.5 * f)


func _ring_pt(k: int, t: float) -> Vector2:
	var X: float = _rings[k].x
	var Z: float = _rings[k].y
	var per := 4.0 * (X + Z)
	t = fposmod(t, per)
	if t < 2.0 * X:
		return _wctr + Vector2(-X + t, -Z)
	t -= 2.0 * X
	if t < 2.0 * Z:
		return _wctr + Vector2(X, -Z + t)
	t -= 2.0 * Z
	if t < 2.0 * X:
		return _wctr + Vector2(X - t, Z)
	t -= 2.0 * X
	return _wctr + Vector2(-X, Z - t)


func _ring_t(k: int, p: Vector2) -> float:
	var X: float = _rings[k].x
	var Z: float = _rings[k].y
	var q := p - _wctr
	if absf(q.y + Z) < 0.05:
		return q.x + X
	if absf(q.x - X) < 0.05:
		return 2.0 * X + q.y + Z
	if absf(q.y - Z) < 0.05:
		return 2.0 * X + 2.0 * Z + (X - q.x)
	return 4.0 * X + 2.0 * Z + (Z - q.y)


func _ray_ring(s: Vector2, d: Vector2) -> Array:
	## the first ring edge a ray from s along d crosses (at least 1 m out, at most 22 m): [ring, point] or []
	var best := 22.0
	var res: Array = []
	var q := s - _wctr
	for k in range(_rings.size()):
		var X: float = _rings[k].x
		var Z: float = _rings[k].y
		for sx in [1.0, -1.0]:
			if absf(d.x) > 0.01:
				var u: float = (sx * X - q.x) / d.x
				if u > 1.0 and u < best:
					var y := q.y + u * d.y
					if absf(y) <= Z + 0.01:
						best = u
						res = [k, _wctr + Vector2(sx * X, y)]
		for sz in [1.0, -1.0]:
			if absf(d.y) > 0.01:
				var u2: float = (sz * Z - q.y) / d.y
				if u2 > 1.0 and u2 < best:
					var x := q.x + u2 * d.x
					if absf(x) <= X + 0.01:
						best = u2
						res = [k, _wctr + Vector2(x, sz * Z)]
	return res


func _ray_ring0(s: Vector2, d: Vector2) -> Vector2:
	## where a ray from s along d first meets the OUTER ring (2 .. 45 m out), or Vector2.INF
	var X: float = _rings[0].x
	var Z: float = _rings[0].y
	var q := s - _wctr
	var best := 45.0
	var res := Vector2.INF
	for sg in [1.0, -1.0]:
		if absf(d.x) > 0.01:
			var u: float = (sg * X - q.x) / d.x
			if u > 2.0 and u < best and absf(q.y + u * d.y) <= Z:
				best = u
				res = _wctr + Vector2(sg * X, q.y + u * d.y)
		if absf(d.y) > 0.01:
			var u2: float = (sg * Z - q.y) / d.y
			if u2 > 2.0 and u2 < best and absf(q.x + u2 * d.x) <= X:
				best = u2
				res = _wctr + Vector2(q.x + u2 * d.x, sg * Z)
	return res


func low_decks() -> Array:
	## the stretches of ramp / bridge too low for a tube to pass under (x z segments): the tube router keeps off them, so a
	## Locals' way out of a pit or into a door never has a tube through it
	var out: Array = []
	if not walkways:
		return out
	var seen := {}
	for fk in feeds:
		var hs: Array = feeds[fk]["hs"]
		var path: Array = feeds[fk]["path"]
		if hs.is_empty():
			continue
		for k in range(1, path.size()):
			var h0: float = hs[k - 1]
			var h1: float = hs[k]
			if minf(h0, h1) >= LOW_DECK:
				continue
			var a: Vector2 = path[k - 1]
			var b: Vector2 = path[k]
			var key := Vector4(roundf(a.x), roundf(a.y), roundf(b.x), roundf(b.y))
			if seen.has(key):
				continue
			seen[key] = true
			if h0 < h1 and h1 > LOW_DECK:
				out.append([a, a.lerp(b, (LOW_DECK - h0) / (h1 - h0))])
			elif h1 < h0 and h0 > LOW_DECK:
				out.append([a.lerp(b, (h0 - LOW_DECK) / (h0 - h1)), b])
			else:
				out.append([a, b])
	return out


func _bridge_clear(a: Vector2, b: Vector2, skip: Vector2) -> bool:
	for tb in wl._tubes:
		var c := Vector2(tb["x"], tb["z"])
		if c.distance_to(skip) < 0.1:
			continue
		if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < (2.0 if tb.get("ent", false) else float(tb["r"]) + 1.0) + 1.6:
			return false
	return true


func _ring_walk(a_pt: Vector2, b_pt: Vector2, kb: int) -> Array:
	## shortest walk on the rings from a_pt (on ring 0) to b_pt (on ring kb): the loops' corners and side midpoints, a ramp
	## between neighbouring rings at each midpoint. [[point, height], ...]
	var npos: Array = []
	var nring: Array = []
	var nt: Array = []
	var by_key := {}
	var add := func(k: int, t: float, p: Vector2) -> int:
		var key := Vector2i(k, roundi(t * 10.0))
		if by_key.has(key):
			return by_key[key]
		npos.append(p)
		nring.append(k)
		nt.append(t)
		by_key[key] = npos.size() - 1
		return npos.size() - 1
	var gate: Array = []
	for k in range(_rings.size()):
		var X: float = _rings[k].x
		var Z: float = _rings[k].y
		var cuts := [0.0, X, 2.0 * X, 2.0 * X + Z, 2.0 * X + 2.0 * Z, 3.0 * X + 2.0 * Z, 4.0 * X + 2.0 * Z, 4.0 * X + 3.0 * Z]
		var gk: Array = []
		for t in cuts:
			gk.append(add.call(k, t, _ring_pt(k, t)))
		gate.append(gk)
	var ia: int = add.call(0, _ring_t(0, a_pt), a_pt)
	var ib: int = add.call(kb, _ring_t(kb, b_pt), b_pt)
	var n := npos.size()
	var adj: Array = []
	for i in range(n):
		adj.append([])
	for k in range(_rings.size()):
		var ids: Array = []
		for i in range(n):
			if nring[i] == k:
				ids.append(i)
		ids.sort_custom(func(p, q): return nt[p] < nt[q])
		var per := 4.0 * (float(_rings[k].x) + float(_rings[k].y))
		for j in range(ids.size()):
			var u: int = ids[j]
			var v: int = ids[(j + 1) % ids.size()]
			var cost: float = fposmod(float(nt[v]) - float(nt[u]), per)
			adj[u].append([v, cost])
			adj[v].append([u, cost])
	for k in range(_rings.size() - 1):                    # ramps at the four side midpoints (cuts 1, 3, 5, 7)
		for gi in [1, 3, 5, 7]:
			var u: int = gate[k][gi]
			var v: int = gate[k + 1][gi]
			var cost := (npos[u] as Vector2).distance_to(npos[v]) + 3.0
			adj[u].append([v, cost])
			adj[v].append([u, cost])
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in range(n):
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[ia] = 0.0
	for _it in range(n):
		var u := -1
		for i in range(n):
			if not done[i] and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or dist[u] == INF:
			break
		done[u] = true
		for e in adj[u]:
			var v: int = e[0]
			if dist[u] + float(e[1]) < dist[v]:
				dist[v] = dist[u] + float(e[1])
				prev[v] = u
	if dist[ib] == INF:
		return []
	var ids2: Array = []
	var cur := ib
	while cur != -1:
		ids2.push_front(cur)
		cur = prev[cur]
	var out: Array = []
	for i in ids2:
		out.append([npos[i], float(WALK_LEVELS[nring[i]])])
	# drop the points that lie on a straight, level run
	var keep: Array = [out[0]]
	for j in range(1, out.size() - 1):
		var a: Vector2 = keep[keep.size() - 1][0]
		var b: Vector2 = out[j][0]
		var c: Vector2 = out[j + 1][0]
		var straight: bool = absf((b - a).cross(c - b)) < 0.05 and (b - a).dot(c - b) > 0.0 and is_equal_approx(float(keep[keep.size() - 1][1]), float(out[j][1])) and is_equal_approx(float(out[j][1]), float(out[j + 1][1]))
		if not straight:
			keep.append(out[j])
	keep.append(out[out.size() - 1])
	return keep


func _walk_path(t2: Vector2, c2: Vector2, taken: Vector2) -> Dictionary:
	## the walkway route of one feed: pit exit -> diagonal ramp to the nearest corner of the outer ring -> the rings -> a diagonal
	## bridge to a door (the one with the shortest total walk; not `taken`). {dir, pts, hs} or {}
	if _rings.is_empty():
		return {}
	var X0: float = _rings[0].x
	var Z0: float = _rings[0].y
	var r := 0.70710678
	var to_c := (_wctr - c2).normalized()
	var diag: Array = [Vector2(r, r), Vector2(r, -r), Vector2(-r, -r), Vector2(-r, r)]
	diag.sort_custom(func(p1, p2): return (p1 as Vector2).dot(to_c) > (p2 as Vector2).dot(to_c))
	var exits: Array = []                                 # [where the Locals leave the pit, where that ramp lands on the outer ring]
	for k in range(2):                                    # Daniele 2026-11-11: out of the pit on BOTH diagonals that face the board
		var dg: Vector2 = diag[k]
		var ex: Vector2 = c2 + dg * (RING_R + 0.4)
		var land := _ray_ring0(ex, dg)
		if land == Vector2.INF:                               # it just misses the ring: it lands on the corner it passes (within 4 m)
			for sx in [1.0, -1.0]:
				for sz in [1.0, -1.0]:
					var cc := _wctr + Vector2(sx * X0, sz * Z0)
					var along := (cc - ex).dot(dg)
					if along > 2.0 and absf((cc - ex).cross(dg)) < 4.0:
						land = cc
		if land != Vector2.INF:
			exits.append([ex, land])
	if exits.is_empty():                                  # (a pit no diagonal links to the ring: straight to its nearest corner)
		var best_c := Vector2.ZERO
		var bd := INF
		for sx in [1.0, -1.0]:
			for sz in [1.0, -1.0]:
				var cc := _wctr + Vector2(sx * X0, sz * Z0)
				if cc.distance_to(c2) < bd:
					bd = cc.distance_to(c2)
					best_c = cc
		exits.append([c2 + (best_c - c2).normalized() * (RING_R + 0.4), best_c])
	var best := {}
	var bl := INF
	for e in exits:
		var exit: Vector2 = e[0]
		var land: Vector2 = e[1]
		for d2 in door_dirs():
			if d2 == taken:
				continue
			var slot0: Vector2 = t2 + d2 * DOOR_OUT
			var hit: Array = _ray_ring(slot0, d2)
			if hit.is_empty():
				continue
			var bp: Vector2 = hit[1]
			if not _bridge_clear(slot0, bp, t2):
				continue
			var walk: Array = _ring_walk(land, bp, int(hit[0]))
			if walk.is_empty():
				continue
			var tot: float = exit.distance_to(land) + slot0.distance_to(bp)
			for j in range(1, walk.size()):
				tot += (walk[j][0] as Vector2).distance_to(walk[j - 1][0])
			if tot < bl:
				bl = tot
				var pts: Array = [exit]
				var hs: Array = [0.0]
				if exit.distance_to(land) > RAMP_LEN + 0.6:      # a short ramp up out of the pit, then a LEVEL bridge to the ring:
					pts.append(exit + (land - exit).normalized() * RAMP_LEN)   # the tubes pass under the bridge, only the ramp is in their way
					hs.append(float(walk[0][1]))
				for w in walk:
					pts.append(w[0])
					hs.append(w[1])
				if bp.distance_to(slot0) > RAMP_LEN + 0.6:        # and the same down to the door
					pts.append(slot0 + (bp - slot0).normalized() * RAMP_LEN)
					hs.append(float(walk[walk.size() - 1][1]))
				pts.append(slot0)
				hs.append(0.0)
				best = {"dir": d2, "pts": pts, "hs": hs}
	if not best.is_empty():
		_add_abouts(best, t2)
	return best


func _on_ring_edge(a: Vector2, b: Vector2, ha: float, hb: float) -> bool:
	for k in range(_rings.size()):
		if absf(ha - float(WALK_LEVELS[k])) > 0.01 or absf(hb - float(WALK_LEVELS[k])) > 0.01:
			continue
		var X: float = _rings[k].x
		var Z: float = _rings[k].y
		var qa := a - _wctr
		var qb := b - _wctr
		if absf(absf(qa.x) - X) < 0.06 and absf(qa.x - qb.x) < 0.06 and absf(qa.y) <= Z + 0.06 and absf(qb.y) <= Z + 0.06:
			return true
		if absf(absf(qa.y) - Z) < 0.06 and absf(qa.y - qb.y) < 0.06 and absf(qa.x) <= X + 0.06 and absf(qb.x) <= X + 0.06:
			return true
	return false


func _about_hits(a: Vector2, b: Vector2, skip: Vector2) -> Array:
	## the columns a walkway from a to b would run into, in order: [centre, roundabout radius, where it joins, where it leaves, t]
	var out: Array = []
	var dv := b - a
	var ln := dv.length()
	if ln < 0.5:
		return out
	dv /= ln
	for tb in wl._tubes:
		var c := Vector2(tb["x"], tb["z"])
		if skip != Vector2.INF and c.distance_to(skip) < 0.1:
			continue
		var R: float = (0.95 if tb.get("ent", false) else float(tb["r"])) + ABOUT_GAP + DECK_HW
		var t := (c - a).dot(dv)
		var d := absf((c - a).cross(dv))
		if d >= R - 0.05:
			continue                                      # the deck passes clear of it
		var half := sqrt(R * R - d * d)
		if t - half < 0.3 or t + half > ln - 0.3:
			continue                                      # (an end of the stretch is inside the circle: left as it is)
		var foot := a + dv * t
		out.append([c, R, foot - dv * half, foot + dv * half, t])
	out.sort_custom(func(p1, p2): return float(p1[4]) < float(p2[4]))
	return out


func _add_abouts(wp: Dictionary, own: Vector2) -> void:
	## the path goes ROUND every column it would run through (the short way), level with the deck there
	var pts: Array = wp["pts"]
	var hs: Array = wp["hs"]
	var np: Array = [pts[0]]
	var nh: Array = [hs[0]]
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		for hit in _about_hits(a, b, own if k == pts.size() - 1 else Vector2.INF):
			var c: Vector2 = hit[0]
			var R: float = hit[1]
			var e: Vector2 = hit[2]
			var x: Vector2 = hit[3]
			var hm := lerpf(float(hs[k - 1]), float(hs[k]), float(hit[4]) / a.distance_to(b))
			if hm < 1.5:
				continue                                  # too low to clear the base's roof: not a deck up there
			var a0 := atan2(e.y - c.y, e.x - c.x)
			var dl := angle_difference(a0, atan2(x.y - c.y, x.x - c.x))
			var n := maxi(ceili(absf(dl) / 0.8), 1)
			for j in range(n + 1):
				var ang := a0 + dl * float(j) / n
				np.append(c + Vector2(cos(ang), sin(ang)) * R)
				nh.append(hm)
			_abouts.append([c, R, hm, a0, a0 + dl])
		np.append(b)
		nh.append(hs[k])
	wp["pts"] = np
	wp["hs"] = nh


func _build_walkways() -> void:
	var fy := wl.floor_y
	var st := SurfaceTool.new()
	var sg := SurfaceTool.new()
	var sr := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	sg.begin(Mesh.PRIMITIVE_TRIANGLES)
	sr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: Array = []                                  # the tubes' xz segments (a stand never lands on one)
	if wl.pipes != null:
		for rn in wl.pipes.run_pts:
			var pts: PackedVector3Array = rn[3]
			for k in range(1, pts.size()):
				segs.append([Vector2(pts[k - 1].x, pts[k - 1].z), Vector2(pts[k].x, pts[k].z)])
	var ribbons: Array = []                               # [a, b, ha, hb, rail trim at a, rail trim at b]
	var abouts: Array = _abouts.duplicate()               # + the ones on the ring edges below
	for k in range(_rings.size()):                        # the rings
		var h: float = WALK_LEVELS[k]
		for j in range(4):
			var t0: float = 0.0
			var cs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			var a: Vector2 = _wctr + Vector2(cs[j].x * float(_rings[k].x), cs[j].y * float(_rings[k].y))
			var b: Vector2 = _wctr + Vector2(cs[(j + 1) % 4].x * float(_rings[k].x), cs[(j + 1) % 4].y * float(_rings[k].y))
			var dv0 := (b - a).normalized()
			var cur := a - dv0 * DECK_HW
			var cur_trim := 1.7
			for hit in _about_hits(a, b, Vector2.INF):        # a column on the ring: the ring goes round it
				var hc: Vector2 = hit[0]
				var he: Vector2 = hit[2]
				var hx: Vector2 = hit[3]
				ribbons.append([cur, he, h, h, cur_trim, 0.15])
				abouts.append([hc, hit[1], h, atan2(he.y - hc.y, he.x - hc.x), atan2(hx.y - hc.y, hx.x - hc.x)])
				cur = hx
				cur_trim = 0.15
			ribbons.append([cur, b + dv0 * DECK_HW, h, h, cur_trim, 1.7])
	var seen := {}                                        # the ramps and bridges the feeds use (each once)
	for fk in feeds:
		var f: Dictionary = feeds[fk]
		var hs: Array = f["hs"]
		var path: Array = f["path"]
		if hs.is_empty():
			continue
		for k in range(1, path.size()):
			if _on_ring_edge(path[k - 1], path[k], float(hs[k - 1]), float(hs[k])):
				continue                                  # a ring edge: drawn above
			var key := Vector4(roundf((path[k - 1] as Vector2).x), roundf((path[k - 1] as Vector2).y), roundf((path[k] as Vector2).x), roundf((path[k] as Vector2).y))
			if seen.has(key):
				continue
			seen[key] = true
			var on_about := false                         # a step of a roundabout: the round deck is drawn below
			for ab in _abouts:
				if absf((path[k - 1] as Vector2).distance_to(ab[0]) - float(ab[1])) < 0.06 and absf((path[k] as Vector2).distance_to(ab[0]) - float(ab[1])) < 0.06:
					on_about = true
			if on_about:
				continue
			ribbons.append([path[k - 1], path[k], float(hs[k - 1]), float(hs[k]), 1.1, 1.1])
	var discs: Array = []                                 # the roundabouts, each once: [centre, radius, height]
	var dseen := {}
	for ab in abouts:
		var dkey := Vector3(roundf((ab[0] as Vector2).x * 10.0), roundf((ab[0] as Vector2).y * 10.0), roundf(float(ab[2]) * 10.0))
		if not dseen.has(dkey):
			dseen[dkey] = true
			discs.append([ab[0], ab[1], ab[2]])
	var cores: Array = []                                 # per ribbon: its deck as [a, b, ha, hb, direction, length] (ring corners' overhang left out)
	for rb in ribbons:
		var ca: Vector2 = rb[0]
		var cb: Vector2 = rb[1]
		var cd := (cb - ca).normalized()
		var cl := ca.distance_to(cb)
		var sa := DECK_HW if float(rb[4]) > 1.5 else 0.0
		var sb := DECK_HW if float(rb[5]) > 1.5 else 0.0
		var ha0 := lerpf(float(rb[2]), float(rb[3]), sa / maxf(cl, 0.01))
		var hb0 := lerpf(float(rb[2]), float(rb[3]), 1.0 - sb / maxf(cl, 0.01))
		cores.append([ca + cd * sa, cb - cd * sb, ha0, hb0, cd, maxf(cl - sa - sb, 0.01)])
	for ri in range(ribbons.size()):
		var rb: Array = ribbons[ri]
		var a: Vector2 = rb[0]
		var b: Vector2 = rb[1]
		var ha: float = rb[2]
		var hb: float = rb[3]
		var dv := (b - a).normalized()
		var a2 := a
		var b2 := b
		if a.distance_to(b) < 0.2:
			continue
		var nv := Vector2(-dv.y, dv.x)
		var hw := DECK_HW
		var ya := fy + ha
		var yb := fy + hb
		var tl0 := Vector3(a2.x + nv.x * hw, ya, a2.y + nv.y * hw)
		var tr0 := Vector3(a2.x - nv.x * hw, ya, a2.y - nv.y * hw)
		var tl1 := Vector3(b2.x + nv.x * hw, yb, b2.y + nv.y * hw)
		var tr1 := Vector3(b2.x - nv.x * hw, yb, b2.y - nv.y * hw)
		var dn := Vector3(0, -DECK_T, 0)
		_quad3(st, tl0, tl1, tr1, tr0, Vector3.UP)
		_quad3(st, tl0 + dn, tl1 + dn, tr1 + dn, tr0 + dn, Vector3.DOWN)
		_quad3(st, tl0, tl1, tl1 + dn, tl0 + dn, Vector3(nv.x, 0, nv.y))
		_quad3(st, tr0, tr1, tr1 + dn, tr0 + dn, Vector3(-nv.x, 0, -nv.y))
		var ln := a2.distance_to(b2)
		var up := Vector3(0, 0.012, 0)
		var ra := 0.05 if float(rb[4]) > 1.5 else 0.0      # a rail runs the whole deck (to the corner's own rail line at a ring corner)
		var rbb := 0.05 if float(rb[5]) > 1.5 else 0.0
		for sd in [1.0, -1.0]:
			var off: Vector2 = nv * sd * (hw - 0.05)
			var q0: Vector2 = a2 + dv * ra + off
			var q1: Vector2 = b2 - dv * rbb + off
			var y0 := lerpf(ha, hb, ra / ln)
			var y1 := lerpf(ha, hb, 1.0 - rbb / ln)
			var rl := q0.distance_to(q1)
			for run in _rail_runs(q0, q1, y0, y1, ri, cores, discs):   # ...minus what lies on another deck: the rails plug into each other
				var r0: float = run[0]
				var r1: float = run[1]
				if (r1 - r0) * rl < 0.12:
					continue
				var p0: Vector2 = q0.lerp(q1, r0)
				var p1: Vector2 = q0.lerp(q1, r1)
				var h0r := fy + lerpf(y0, y1, r0)
				var h1r := fy + lerpf(y0, y1, r1)
				_beam(sr, Vector3(p0.x, h0r + RAIL_H, p0.y), Vector3(p1.x, h1r + RAIL_H, p1.y), 0.07, 0.06)      # hand rail
				_beam(sr, Vector3(p0.x, h0r + RAIL_H * 0.5, p0.y), Vector3(p1.x, h1r + RAIL_H * 0.5, p1.y), 0.04, 0.04)   # mid rail
				_beam(sr, Vector3(p0.x, h0r + 0.09, p0.y), Vector3(p1.x, h1r + 0.09, p1.y), 0.05, 0.09)          # kick plate
				var np := maxi(ceili((r1 - r0) * rl / 2.2), 1)
				for j in range(np + 1):
					var uu := lerpf(r0, r1, float(j) / np)
					var qp: Vector2 = q0.lerp(q1, uu)
					_box(sr, Vector3(qp.x, fy + lerpf(y0, y1, uu) + RAIL_H * 0.5, qp.y), Vector3(0.07, RAIL_H, 0.07))
		var dd := 0.6                                       # the neon centre line, dashed
		while NEON_DASH and dd + DASH < ln - 0.6:
			var c0: Vector2 = a2.lerp(b2, dd / ln)
			var c1: Vector2 = a2.lerp(b2, (dd + DASH) / ln)
			var h0 := lerpf(ya, yb, dd / ln)
			var h1 := lerpf(ya, yb, (dd + DASH) / ln)
			var w2 := nv * 0.06
			for sd2 in [1.0, -1.0]:                             # one dashed strip along each side (Daniele 2026-11-11), inside the rails
				var o2: Vector2 = nv * sd2 * (hw - 0.24)
				_quad3(sg, Vector3(c0.x + o2.x + w2.x, h0, c0.y + o2.y + w2.y) + up, Vector3(c1.x + o2.x + w2.x, h1, c1.y + o2.y + w2.y) + up,
						Vector3(c1.x + o2.x - w2.x, h1, c1.y + o2.y - w2.y) + up, Vector3(c0.x + o2.x - w2.x, h0, c0.y + o2.y - w2.y) + up, Vector3.UP)
			dd += DASH + DASH_GAP
		var d2 := 1.0
		while d2 < ln - 0.5:
			var u := d2 / ln
			var yy := lerpf(ha, hb, u)
			if yy > 0.6:
				var c: Vector2 = a2.lerp(b2, u)
				for sd in [1.0, -1.0]:
					var q: Vector2 = c + nv * sd * (hw - 0.1)
					var ok := true
					for sg2 in segs:
						if Geometry2D.get_closest_point_to_segment(q, sg2[0], sg2[1]).distance_to(q) < 1.3:
							ok = false
							break
					if ok:
						_box(st, Vector3(q.x, fy + (yy - DECK_T) * 0.5, q.y), Vector3(0.14, yy - DECK_T, 0.14))
			d2 += 4.0
	var merged := {}                                      # the roundabouts, each once: [centre, radius, height, joint angles]
	for ab in abouts:
		var key := Vector3(roundf((ab[0] as Vector2).x * 10.0), roundf((ab[0] as Vector2).y * 10.0), roundf(float(ab[2]) * 10.0))
		if not merged.has(key):
			merged[key] = [ab[0], ab[1], ab[2], []]
		merged[key][3].append(float(ab[3]))
		merged[key][3].append(float(ab[4]))
	for key in merged:
		var c: Vector2 = merged[key][0]
		var R: float = merged[key][1]
		var y: float = fy + float(merged[key][2])
		var joints: Array = merged[key][3]
		var N := 48
		var dn2 := Vector3(0, -DECK_T, 0)
		var up2 := Vector3(0, 0.012, 0)
		for j in range(N):
			var t0 := TAU * j / N
			var t1 := TAU * (j + 1) / N
			var e0 := Vector2(cos(t0), sin(t0))
			var e1 := Vector2(cos(t1), sin(t1))
			var i0 := Vector3(c.x + e0.x * (R - DECK_HW), y, c.y + e0.y * (R - DECK_HW))
			var i1 := Vector3(c.x + e1.x * (R - DECK_HW), y, c.y + e1.y * (R - DECK_HW))
			var o0 := Vector3(c.x + e0.x * (R + DECK_HW), y, c.y + e0.y * (R + DECK_HW))
			var o1 := Vector3(c.x + e1.x * (R + DECK_HW), y, c.y + e1.y * (R + DECK_HW))
			var out3 := Vector3(e0.x, 0, e0.y)
			_quad3(st, o0, o1, i1, i0, Vector3.UP)
			_quad3(st, o0 + dn2, o1 + dn2, i1 + dn2, i0 + dn2, Vector3.DOWN)
			_quad3(st, o0, o1, o1 + dn2, o0 + dn2, out3)
			_quad3(st, i0, i1, i1 + dn2, i0 + dn2, -out3)
			var rise := Vector3(0, RAIL_H, 0)
			var in0 := i0 + out3 * 0.05
			var in1 := i1 + Vector3(e1.x, 0, e1.y) * 0.05
			_beam(sr, in0 + rise, in1 + rise, 0.07, 0.06)                     # the inner rail, all the way round the column
			_beam(sr, in0 + Vector3(0, 0.09, 0), in1 + Vector3(0, 0.09, 0), 0.05, 0.09)
			if j % 6 == 0:
				_box(sr, in0 + rise * 0.5, Vector3(0.07, RAIL_H, 0.07))
			var tm := (t0 + t1) * 0.5                          # the outer rail opens where a walkway joins
			var joint := _rail_blocked(c + Vector2(cos(tm), sin(tm)) * (R + DECK_HW - 0.05), float(merged[key][2]), -1, cores, [], 1.2)
			if not joint:
				var on0 := o0 - out3 * 0.05
				var on1 := o1 - Vector3(e1.x, 0, e1.y) * 0.05
				_beam(sr, on0 + rise, on1 + rise, 0.07, 0.06)
				_beam(sr, on0 + rise * 0.5, on1 + rise * 0.5, 0.04, 0.04)
				_beam(sr, on0 + Vector3(0, 0.09, 0), on1 + Vector3(0, 0.09, 0), 0.05, 0.09)
				if j % 6 == 0:
					_box(sr, on0 + rise * 0.5, Vector3(0.07, RAIL_H, 0.07))
			if NEON_DASH and j % 4 < 2:                                      # the dashed neon line goes round too
				for rr in [R + DECK_HW - 0.24, R - DECK_HW + 0.24]:
					_quad3(sg, Vector3(c.x + e0.x * (rr + 0.06), y, c.y + e0.y * (rr + 0.06)) + up2, Vector3(c.x + e1.x * (rr + 0.06), y, c.y + e1.y * (rr + 0.06)) + up2,
							Vector3(c.x + e1.x * (rr - 0.06), y, c.y + e1.y * (rr - 0.06)) + up2, Vector3(c.x + e0.x * (rr - 0.06), y, c.y + e0.y * (rr - 0.06)) + up2, Vector3.UP)
	about_count = merged.size()
	about_at = []
	for key in merged:
		about_at.append([merged[key][0], merged[key][2]])
	var mesh := st.commit()
	if NEON_DASH:
		sg.commit(mesh)
	sr.commit(mesh)
	var m3 := StandardMaterial3D.new()
	m3.albedo_color = Color(0.72, 0.76, 0.84)
	m3.metallic = 0.6
	m3.roughness = 0.35
	mesh.surface_set_material(mesh.get_surface_count() - 1, m3)
	deck_tris = 0
	for si in range(mesh.get_surface_count()):
		deck_tris += mesh.surface_get_array_len(si) / 3
	var m1 := StandardMaterial3D.new()
	m1.albedo_color = Color(0.20, 0.22, 0.28)
	m1.metallic = 0.45
	m1.roughness = 0.6
	m1.cull_mode = BaseMaterial3D.CULL_DISABLED
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.albedo_color = Color(0.75, 0.92, 1.0)
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m1)
	if NEON_DASH:
		mesh.surface_set_material(1, m2)
	_deck_mi = MeshInstance3D.new()
	_deck_mi.mesh = mesh
	_deck_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_deck_mi)


static func _quad3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	## a quad that FACES hint: its normal and its winding agree (a quad wound the other way is lit as its back, darker)
	var n := (b - a).cross(c - a)
	if n.length() < 0.00001:
		n = (c - a).cross(d - a)
	n = n.normalized()
	var vs := [a, b, c, a, c, d]
	if n.dot(hint) > 0.0:
		vs = [a, c, b, a, d, c]                         # (front faces are clockwise)
	else:
		n = -n
	for v in vs:
		st.set_normal(n)
		st.add_vertex(v)


func _rail_blocked(q: Vector2, y: float, skip: int, cores: Array, discs: Array, ext := 0.005) -> bool:
	## is this point of a rail ON another deck (same level)? Then there is no rail there: the walkways open into each other
	for i in range(cores.size()):
		if i == skip:
			continue
		var cr: Array = cores[i]
		var rel: Vector2 = q - (cr[0] as Vector2)
		var t := rel.dot(cr[4])
		if t < -ext or t > float(cr[5]) + ext:
			continue
		if absf(rel.cross(cr[4])) > DECK_HW - 0.055:
			continue
		if absf(lerpf(float(cr[2]), float(cr[3]), clampf(t / float(cr[5]), 0.0, 1.0)) - y) > 0.6:
			continue
		return true
	for d in discs:
		if q.distance_to(d[0]) < float(d[1]) + DECK_HW - 0.055 and absf(float(d[2]) - y) < 0.6:
			return true
	return false


func _rail_runs(q0: Vector2, q1: Vector2, y0: float, y1: float, skip: int, cores: Array, discs: Array) -> Array:
	## the stretches [u0, u1] of a rail that stand free (0.25 m samples, the ends found to the centimetre)
	var ln := q0.distance_to(q1)
	var n := maxi(ceili(ln / 0.25), 1)
	var runs: Array = []
	var open := -1.0
	var prev_free := false
	var prev_u := 0.0
	for j in range(n + 1):
		var u := float(j) / n
		var free := not _rail_blocked(q0.lerp(q1, u), lerpf(y0, y1, u), skip, cores, discs)
		if j == 0:
			if free:
				open = 0.0
		elif free != prev_free:
			var lo := prev_u
			var hi := u
			for _i in range(7):
				var m := (lo + hi) * 0.5
				if (not _rail_blocked(q0.lerp(q1, m), lerpf(y0, y1, m), skip, cores, discs)) == prev_free:
					lo = m
				else:
					hi = m
			var edge := (lo + hi) * 0.5
			if free:
				open = edge
			else:
				runs.append([open, edge])
				open = -1.0
		prev_free = free
		prev_u = u
	if open >= 0.0:
		runs.append([open, 1.0])
	return runs


static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float) -> void:
	## a straight bar from a to b (its top centre line), w wide and h tall; it follows the slope
	var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var n := Vector3(-d.z, 0, d.x) * (w * 0.5)
	var dn := Vector3(0, -h, 0)
	_quad3(st, a + n, b + n, b - n, a - n, Vector3.UP)
	_quad3(st, a + n, b + n, b + n + dn, a + n + dn, n)
	_quad3(st, a - n, b - n, b - n + dn, a - n + dn, -n)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)], [1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)]]
	for fc in faces:
		_quad3(st, c + p[fc[0]], c + p[fc[1]], c + p[fc[2]], c + p[fc[3]], fc[4])


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
			img.set_pixel(k, int(f["row"]), Color((path[k] as Vector2).x, (path[k] as Vector2).y, cum, float((f["hs"] as Array)[k]) if not (f["hs"] as Array).is_empty() else 0.0))
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
	_trunk_step()
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
	if not tb.get("shown", false) or not tb["alive"]:
		if not line.is_empty():                       # the tube is gone: its line melts where it stands
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
	if line.size() >= int(f["cap"]):
		return
	if int(f.get("parent", -1)) >= 0:                 # its line fills from the shared walkway queue, never straight from the pit
		if _take(int(f["parent"]), line, int(f["row"]), plen - line.size() * GAP, int(f["row"])) and int(f.get("march", 0)) > 0:
			f["march"] = int(f["march"]) - 1
		return
	if _t >= float(f["next_spawn"]) and _alive < LOCALS_MAX:
		var gap := clampf(0.8 / maxf(rate, 0.8), GAP / WALK_V, 1.2) * randf_range(1.0, 1.3)   # never closer than one Local's gap at walking pace
		if int(f.get("march", 0)) > 0:                # R6: the match-start column leaves the pit in step
			gap = maxf(MARCH_GAP, GAP / WALK_V)
			f["march"] = int(f["march"]) - 1
		f["next_spawn"] = _t + gap
		_spawn(f, line)


func _spawn(f: Dictionary, line: Array, d1 := -1.0) -> void:
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
	_d1[s] = d1 if d1 >= 0.0 else float(f["len"]) - line.size() * GAP
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
