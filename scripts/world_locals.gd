class_name WorldLocals
extends Node3D
## LOCALS MARCH (cosmetic, VIEW ONLY, no rules): the lab's CONTAINMENT RING craters on the world floor, where the gray
## native goo (the Locals, WORLD-LORE-2026-11) wells up. Locals rise out of a crater's pool, hop over the rim, walk the
## floor to the NEAREST door of each tube's four-door entrance (each tube is fed by its nearest crater), queue in a short
## line, squeeze in (squash + shrink at the door) and ride up the tube as gray goo (WorldLayer riders).
## Art: Models/2.0/world-1.0/build_containment_ring.py (ring v1) + build_tube_entrance_v2.py (four doors).
## Layouts (--craters=1|2|4): 1 = the map centre; 2 = the board's left and right side; 4 = near each corner of the
## board's bounding box - each nudged to the nearest floor the default camera sees (platforms and bridges block it).
## Budget: two draws (one MultiMesh of rings, one of Locals), fixed pools, Locals gray only, no skeletons: bob and
## squash in the shader (shaders/world_local.gdshader), the pool swirl in shaders/world_ring.gdshader.

const RING_GLB := "res://assets/world/containment_ring_v1.glb"
const SHADER_RING := preload("res://shaders/world_ring.gdshader")
const SHADER_LOCAL := preload("res://shaders/world_local.gdshader")

const SPAWN_EVERY := 2.0          # s: one Local per fed tube (on average; small bursts make the queues)
const WALK_V := 1.2               # m/s on the floor
const LOCALS_MAX := 150           # the pool; a spawn waits while it is full
const ADMIT_EVERY := 1.8          # s: a door takes one Local
const SQUEEZE_T := 0.55           # s: squash + shrink through the door
const EMERGE_T := 0.8             # s: rising out of the pool
const HOP_T := 1.1                # s: the hop over the rim
const QUEUE_GAP := 0.72           # m between queued Locals
const QUEUE_LEN := 5              # the walk ends at the back of a line this long (the line may grow past it)
const DOOR_OUT := 1.78            # m from the tube axis: the first queue slot (the hood's front is at 1.52)
const DOOR_MOUTH := 1.30          # m: where a Local vanishes into the door
const LOCAL_SIZE := 0.62          # m wide (QUEUE KIT blob)
const RING_R := 5.0               # containment ring v1: outer radius
const POOL_R := 3.5
const POOL_H := 0.55
const RIM_H := 0.80
const TUBE_AVOID := 2.0           # m: a path keeps this far from another tube's axis (collar r 1.45 + a blob)
const RING_AVOID := 5.6
const PLAT_R := Rules.R           # a platform's radius (the board's footprint)
const BRIDGE_HALF := 1.4
const SEARCH_R := 16.0            # m: how far a crater may move from its layout target to reach visible floor
const DEFAULT_LAYOUT := 2
# The parallel worker's floor plan (dev only; an exported build falls back to the ray test below): a visibility mask of
# the floor at the default camera (255 seen, 128 seen only when panned / zoomed, 0 never; 16 px/m, world x,z -80..80,
# pixel (0,0) = (-80,-80), +z down) and open spots. Layout 2 = the board's two side courtyards, layout 4 = the open
# spots nearest the board's four corners, layout 1 = the map centre (Daniele) whatever shows of it.
const PLAN_DIR := "H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/refs/09-floor-plan-%s/"

var wl: WorldLayer
var layout := DEFAULT_LAYOUT
var craters: Array = []           # Vector3 on the floor
var targets: Array = []           # the layout's targets before the visibility nudge (debug view)
var crater_vis: Array = []        # share of the ring the default camera sees
var feeds: Dictionary = {}        # tube index -> {crater, dir, path, queue, next_spawn, next_admit}
var placed := false
var spawned := 0
var admitted := 0
var _locals: Array = []           # {st, t0, tube, p, path, d, ph, s, from, to, dir}
var _t := 0.0
var _ring_mm: MultiMesh
var _loc_mm: MultiMesh
var _syncs := 0
var _debug: MeshInstance3D
var plan: Dictionary = {}         # the floor plan JSON (empty: none for this map)
var _mask: Image
var _mask_px := 16.0
var _mask_x0 := -80.0
var _mask_z0 := -80.0
var step_us := 0                  # the last step's CPU cost (perf probe)


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
	rm.set_shader_parameter("abyss", Scenery.ABYSS)
	if "--floor-clear" in OS.get_cmdline_user_args():
		rm.set_shader_parameter("haze", 0.0)
	elif wl.floor_pic:
		rm.set_shader_parameter("haze", WorldLayer.LAB_PIC_HAZE)
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
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 5
	var lm := ShaderMaterial.new()
	lm.shader = SHADER_LOCAL
	lm.set_shader_parameter("abyss", Scenery.ABYSS)
	if "--floor-clear" in OS.get_cmdline_user_args():
		lm.set_shader_parameter("haze", 0.0)
	elif wl.floor_pic:
		lm.set_shader_parameter("haze", WorldLayer.LAB_PIC_HAZE)
	_loc_mm = MultiMesh.new()
	_loc_mm.transform_format = MultiMesh.TRANSFORM_3D
	_loc_mm.use_colors = true
	_loc_mm.use_custom_data = true
	_loc_mm.mesh = sphere
	_loc_mm.instance_count = LOCALS_MAX
	_loc_mm.visible_instance_count = 0
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = _loc_mm
	lmi.material_override = lm
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)


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
	var dir := PLAN_DIR % code
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
	var img := Image.load_from_file(dir + code + "-floor-visible-mask.png")
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
	for i in range(craters.size()):
		var p: Vector3 = craters[i]
		_ring_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.37 * i), p))
		_ring_mm.set_instance_custom_data(i, Color(float(i) * 1.7, 0, 0, 0))
		_ring_mm.set_instance_color(i, Color.WHITE)
	_ring_mm.visible_instance_count = craters.size()
	placed = true
	_route_all()


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
	feeds.clear()
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb.get("ent", false):
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
		var back := t2 + dir * (DOOR_OUT + (QUEUE_LEN - 1) * QUEUE_GAP)
		var exit := c2 + (back - c2).normalized() * (RING_R + 0.4)
		var path := _steer(exit, back, i, 0)
		path.push_front(exit)
		path.append(back)
		feeds[i] = {"crater": ci, "dir": dir, "path": path, "len": _plen(path), "queue": [],
				"next_spawn": randf() * SPAWN_EVERY, "next_admit": 0.0}


func _obstacles(skip_tube: int) -> Array:
	var obs := []
	for j in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[j]
		var r := TUBE_AVOID if is_equal_approx(float(tb["r"]), WorldLayer.TUBE_R) else float(tb["r"]) + 0.8
		if j == skip_tube:
			r = 1.65                                  # its own housing: walk round it to the door side
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


# ------------------------------------------------------------------ per frame
func prewarm(seconds: float) -> void:
	## dev / shots: run the march so the frame shows the steady state (the game itself starts empty at the match start)
	var n := int(seconds / 0.1)
	for i in range(n):
		step(0.1, false)


func step(dt: float, draw := true) -> void:
	_syncs += 1
	if not placed:
		var cam := get_viewport().get_camera_3d()
		if _syncs < 3 or cam == null:
			return
		place(cam)
	var t0 := Time.get_ticks_usec()
	_t += dt
	_spawn()
	_move(dt)
	if draw:
		_draw()
	step_us = Time.get_ticks_usec() - t0


func _spawn() -> void:
	for i in feeds:
		var f: Dictionary = feeds[i]
		var tb: Dictionary = wl._tubes[i]
		if _t < float(f["next_spawn"]):
			continue
		if not tb.get("shown", false) or not tb["alive"]:
			f["next_spawn"] = _t + SPAWN_EVERY
			continue
		if _locals.size() >= LOCALS_MAX:
			continue
		# bursts of 1-3 Locals 0.4-0.7 s apart, then a gap that keeps the mean at SPAWN_EVERY: short lines at the door
		var left := int(f.get("burst", 0))
		if left <= 0:
			var nb: int = [1, 1, 2, 3][randi() % 4]
			left = nb
			f["gap"] = nb * SPAWN_EVERY
		left -= 1
		f["burst"] = left
		if left > 0:
			var g := randf_range(0.4, 0.7)
			f["gap"] = float(f["gap"]) - g
			f["next_spawn"] = _t + g
		else:
			f["next_spawn"] = _t + maxf(float(f["gap"]), 0.4)
		var cp: Vector3 = craters[int(f["crater"])]
		var path: Array = f["path"]
		var exit: Vector2 = path[0]
		var dir2 := (exit - Vector2(cp.x, cp.z)).normalized()
		var a := randf() * TAU
		var rr := sqrt(randf()) * (POOL_R - 0.9)
		var from := Vector2(cp.x + cos(a) * rr, cp.z + sin(a) * rr)
		from = from.lerp(Vector2(cp.x, cp.z) + dir2 * (POOL_R - 1.0), 0.35)   # well up toward the exit side
		_locals.append({"st": 0, "t0": _t, "tube": i, "from": from, "p": from, "d": 0.0, "ph": randf() * TAU,
				"s": randf_range(0.85, 1.12), "dir": dir2})
		spawned += 1


func _move(dt: float) -> void:
	var keep := []
	for L in _locals:
		var f: Dictionary = feeds.get(int(L["tube"]), {})
		var tb: Dictionary = wl._tubes[int(L["tube"])]
		var age := _t - float(L["t0"])
		var st: int = L["st"]
		if f.is_empty():
			continue
		if st >= 2 and st <= 3 and (not tb.get("shown", false) or not tb["alive"]):
			L["st"] = 5                               # the tube is gone: the Local melts where it stands
			L["t0"] = _t
			st = 5
			age = 0.0
		match st:
			0:
				if age >= EMERGE_T:
					L["st"] = 1
					L["t0"] = _t
			1:
				if age >= HOP_T:
					L["st"] = 2
					L["t0"] = _t
					L["d"] = 0.0
			2:
				L["d"] = float(L["d"]) + WALK_V * dt
				var at: Array = _along(f["path"], float(L["d"]))
				L["p"] = at[0]
				L["dir"] = at[1]
				if float(L["d"]) >= float(f["len"]):
					L["st"] = 3
					(f["queue"] as Array).append(L)
			3:
				var q: Array = f["queue"]
				var slot := q.find(L)
				var t2 := Vector2(tb["x"], tb["z"])
				var dir: Vector2 = f["dir"]
				var want := t2 + dir * (DOOR_OUT + slot * QUEUE_GAP)
				var p: Vector2 = L["p"]
				var to := want - p
				if to.length() > 0.02:
					var stp := minf(to.length(), WALK_V * dt)
					L["p"] = p + to.normalized() * stp
					L["dir"] = to.normalized()
				else:
					L["dir"] = -dir
				if slot == 0 and to.length() <= 0.05 and _t >= float(f["next_admit"]):
					q.pop_front()
					L["st"] = 4
					L["t0"] = _t
					L["from"] = L["p"]
					f["next_admit"] = _t + ADMIT_EVERY
			4:
				if age >= SQUEEZE_T:
					admitted += 1
					if tb["alive"]:
						(tb["riders"] as Array).append([wl.floor_y + 0.4, WorldLayer.NATIVE_GRAY])
					continue
				var t2b := Vector2(tb["x"], tb["z"])
				L["p"] = (L["from"] as Vector2).lerp(t2b + (f["dir"] as Vector2) * DOOR_MOUTH, age / SQUEEZE_T)
				L["dir"] = -(f["dir"] as Vector2)
			5:
				if age >= 0.6:
					var q2: Array = f["queue"]
					q2.erase(L)
					continue
		keep.append(L)
	_locals = keep


func _draw() -> void:
	var n := 0
	for L in _locals:
		var st: int = L["st"]
		var age := _t - float(L["t0"])
		var s := LOCAL_SIZE * float(L["s"])
		var p2: Vector2 = L["p"]
		var y := wl.floor_y
		var squeeze := 0.0
		var walk := 0.0
		var cp: Vector3 = craters[int((feeds[int(L["tube"])] as Dictionary)["crater"])] if st <= 1 else Vector3.ZERO
		match st:
			0:                                        # rise out of the pool
				var k := clampf(age / EMERGE_T, 0.0, 1.0)
				y = wl.floor_y + POOL_H - 0.35 * s * (1.0 - k)
				s *= 0.35 + 0.65 * k
				squeeze = -0.4 * (1.0 - k)            # stretched up as it rises
			1:                                        # hop over the rim and down to the floor
				var k := clampf(age / HOP_T, 0.0, 1.0)
				var path: Array = (feeds[int(L["tube"])] as Dictionary)["path"]
				p2 = (L["from"] as Vector2).lerp(path[0], k)
				var base := lerpf(wl.floor_y + POOL_H, wl.floor_y, k)
				y = base + sin(k * PI) * (RIM_H + 0.9)
				L["p"] = p2
				walk = 0.0
			2, 3:
				walk = 1.0
			4:
				squeeze = clampf(age / SQUEEZE_T, 0.0, 1.0)
				s *= 1.0 - 0.75 * squeeze
			5:
				s *= 1.0 - clampf(age / 0.6, 0.0, 1.0)
		if st == 3 and (L["dir"] as Vector2).dot(-(feeds[int(L["tube"])] as Dictionary)["dir"]) > 0.99:
			walk = 0.25                               # waiting: a slow breathing bob
		var d2: Vector2 = L["dir"]
		var fwd := Vector3(d2.x, 0.0, d2.y)
		if fwd.length() < 0.01:
			fwd = Vector3(0, 0, 1)
		var basis := Basis.looking_at(fwd.normalized(), Vector3.UP).scaled(Vector3(s, s * 0.78, s))
		var h := s * 0.78 * 0.5
		_loc_mm.set_instance_transform(n, Transform3D(basis, Vector3(p2.x, y + h, p2.y)))
		_loc_mm.set_instance_custom_data(n, Color(float(L["ph"]), walk, squeeze, 0.0))
		_loc_mm.set_instance_color(n, Color.WHITE)
		n += 1
		if n >= LOCALS_MAX:
			break
	_loc_mm.visible_instance_count = n


func count() -> int:
	return _locals.size()


func queued() -> int:
	var q := 0
	for i in feeds:
		q += ((feeds[i] as Dictionary)["queue"] as Array).size()
	return q


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
		var tb: Dictionary = wl._tubes[i]
		var t2 := Vector2(tb["x"], tb["z"])
		var dir: Vector2 = f["dir"]
		_seg(im, t2 + dir * 1.2, t2 + dir * (DOOR_OUT + (QUEUE_LEN - 1) * QUEUE_GAP), 0.5, y + 0.05, Color(1, 1, 1))
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
