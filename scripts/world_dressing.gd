class_name WorldDressing
extends Node3D
## WORLD COMPLETE LAB (world dressing, 2026-11-07; cosmetic, VIEW ONLY): everything that makes the lab biome's floor a
## place, on top of world pass 2 (lab5 floor, decals, side backdrop, containment rings, Locals, tube entrances):
##  - the DISTRICT ENDS a little beyond the board (shaders/world_floor_lab.gdshader): the floor fades out in a rounded box
##    round the board's footprint and the side backdrop (LAB-SIDE B machinery, --lab-side=a calm) shows through, framing
##    the board at left / right / top; the backdrop gets its own light shader (shaders/lab_backdrop.gdshader);
##  - LAB PROP KIT props (Models/2.0/world-1.0/build_lab_props.py -> assets/world/lab_props_v1.glb): specimen tanks and
##    pods, robot arms, lab benches, goo conveyors with gray Locals riding them, valve manifolds, pipe runs from the
##    craters toward the tube feet, queue rails beside the Local lanes, light posts, floor grates, steam vents with two
##    flat steam cards each, one hovering maintenance drone - all merged into ONE mesh (one draw; the shader animates the
##    riders, the arm, the drone), their glass in one more, the steam in one more;
##  - decals placed with intent (WorldDecals' MultiMesh, no extra draw): hazard patches at the arm's reach, the conveyor's
##    ends and the manifolds, goo stains under the tanks / belts / tube feet, guide arcs round the craters;
##  - light pools as decals (one draw): warm under the posts, cold in front of the tanks, benches and panels, the drone's
##    soft cone that follows it. No real-time light anywhere.
## Placement: only floor the default camera sees (the floor plan's mask, refs/09-floor-plan-<map>), never under the HUD
## (HUD: the demo4 layout, vat gauge left, powers right, top capsule and buttons, hint line, of the 812 x 375 frame at
## the default camera), clear of the tube feet, the craters and their rings / guide arcs, the Local lanes, the
## bridges' fall bands (where bodies splat) and each other.
## WORLD LAB 2 (Daniele 2026-11-07): props at 1.5x (PROP_S), the tallest capped at PROP_MAX_H (the decks are 16 m up);
## the district ends ~10 m past the board on every side (MARGIN, FADE); the floor is the flush-slab pavement.
## Hooked from WorldLayer.setup (lab5 floor only; --no-dressing turns it off, --lab-side=a the calm backdrop,
## --district=<x>,<top>,<bottom> the district's margins past the board in metres).

const PROPS_GLB := "res://assets/world/lab_props_v1.glb"
const SHADER_FLOOR := preload("res://shaders/world_floor_lab.gdshader")
const SHADER_SKY := preload("res://shaders/lab_backdrop.gdshader")
const SHADER_PROP := preload("res://shaders/world_prop.gdshader")
const SHADER_FX := preload("res://shaders/world_prop_fx.gdshader")
const MARGIN := Vector3(10.0, 10.0, 10.0)    # the district past the board's footprint: x sides, far top (-z), near bottom (+z)
const FADE := 5.0                            # metres from full floor to none (it ends at MARGIN)
const EDGE_NOISE := 2.0                      # metres the edge wanders
const CORNER := 8.0                          # rounded corners (m)
const PROP_S := 1.5                          # every lab prop 1.5x (Daniele 2026-11-07)
const PROP_MAX_H := 4.5                      # m: the tallest prop's cap (the floor is 16 m under the platforms)
const FALL_BAND := 3.0                       # m beside a bridge's floor line kept clear (bodies fall off and splat there)
const HUD := [Rect2(0.0, 0.2, 0.1, 0.62), Rect2(0.9, 0.25, 0.1, 0.55), Rect2(0.38, 0.0, 0.24, 0.12),
		Rect2(0.86, 0.0, 0.14, 0.12), Rect2(0.0, 0.92, 1.0, 0.08)]   # the HUD since demo4: vat gauge left, powers right,
		# the top capsule, the top-right buttons, the hint line
const WARM := Color(1.0, 0.66, 0.3, 0.42)
const COLD := Color(0.55, 0.8, 1.0, 0.32)
const DRONE_Y := 3.7                  # m over the floor (the saucer's centre; its top + bob stays under PROP_MAX_H)
const DRONE_R := 7.6
const DRONE_W := 0.11

var wl: WorldLayer
var built := false
var district := Vector4.ZERO           # xmin, xmax, zmin, zmax
var tris := 0
var draws := 0
var log_lines: Array = []
var where: Array = []                  # debug: what stands where
var counts := {}
var _lib := {}                         # prop name -> [verts, normals, colours, indices]
var _h := {}                           # prop name -> its top (m, model scale)
var _arcs: Array = []                  # the guide arcs round the craters: [centre, radius, yaw]
var _stain_i := 0
var _occ: Array = []                   # [Vector2, r]
var _cam: Camera3D
var _vp := Vector2(812, 375)
var _y := 0.0
# merged opaque props / glass
var _pv := PackedVector3Array()
var _pn := PackedVector3Array()
var _pc := PackedColorArray()
var _pu := PackedVector2Array()
var _pu2 := PackedVector2Array()
var _pk := PackedFloat32Array()
var _pi := PackedInt32Array()
var _gv := PackedVector3Array()
var _gn := PackedVector3Array()
var _gi := PackedInt32Array()
# quads: steam cards / light pools
var _sv := PackedVector3Array()
var _sc_steam := PackedColorArray()
var _su2 := PackedVector2Array()
var _si := PackedInt32Array()
var _lv := PackedVector3Array()
var _lc := PackedColorArray()
var _lu := PackedVector2Array()
var _lu2 := PackedVector2Array()
var _li := PackedInt32Array()
var _drone_c := Vector3.ZERO
var _mats: Array = []


func _ready() -> void:
	name = "Dressing"
	wl = get_parent() as WorldLayer
	_y = wl.floor_y
	_district()
	_floor()
	_backdrop()


# ------------------------------------------------------------------ the district's end + the side backdrop
func _district() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in wl.sim.nodes:
		var p: Vector3 = n["pos"]
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var m := MARGIN
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--district="):
			var v := a.substr(11).split(",")
			if v.size() == 3:
				m = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var r := Rules.R
	district = Vector4(lo.x - r - m.x, hi.x + r + m.x, lo.y - r - m.y, hi.y + r + m.z)


func _floor() -> void:
	var old := wl._floor.material_override as ShaderMaterial
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_FLOOR
	for k in ["abyss", "centre", "r0", "r1", "haze", "t_lab5", "lab5_m", "lab5_gain"]:
		mat.set_shader_parameter(k, old.get_shader_parameter(k))
	mat.set_shader_parameter("district", district)
	mat.set_shader_parameter("fade", FADE)
	mat.set_shader_parameter("edge_noise", EDGE_NOISE)
	mat.set_shader_parameter("corner", CORNER)
	mat.set_shader_parameter("lip_col", WorldLayer.LAB_FAR)
	mat.render_priority = old.render_priority
	wl._floor.material_override = mat


func district_alpha(p: Vector2) -> float:
	## the floor's opacity at p without the edge noise (placement keeps props well inside)
	var c := Vector2(district.x + district.y, district.z + district.w) * 0.5
	var h := Vector2(district.y - district.x, district.w - district.z) * 0.5
	var q := (p - c).abs() - h + Vector2.ONE * CORNER
	var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - CORNER
	return 1.0 - smoothstep(-FADE, 0.0, d + EDGE_NOISE)


func _backdrop() -> void:
	var sc = wl.get_parent().get("scenery")
	var layer: CanvasLayer = sc.backdrop if sc != null else null
	if layer == null or layer.get_child_count() == 0 or not (layer.get_child(0) is TextureRect):
		return
	var sky := layer.get_child(0) as TextureRect
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SKY
	mat.set_shader_parameter("abyss", WorldLayer.LAB_FAR)
	sky.material = mat


# ------------------------------------------------------------------ build (once the craters and lanes are placed)
func _process(_dt: float) -> void:
	if built or wl.locals == null or not wl.locals.placed:
		return
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	built = true
	set_process(false)
	var t0 := Time.get_ticks_usec()
	_vp = get_viewport().get_visible_rect().size
	_load_lib()
	_place_all()
	_finish()
	log_lines.append("dressing built in %.1f ms: %d tris, %d draws, %s" % [(Time.get_ticks_usec() - t0) / 1000.0, tris, draws,
			str(counts)])
	log_lines.append("placed: " + " ".join(where))
	var hs := {}
	for k in _h:
		hs[k] = snappedf(float(_h[k]) * _sc(k), 0.01)
	log_lines.append("tallest prop top %.2f m (cap %.1f) | tops at scale: %s" % [max_top(), PROP_MAX_H, str(hs)])


func _load_lib() -> void:
	var ps := load(PROPS_GLB) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	var stack: Array = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			var mi := nd as MeshInstance3D
			var a := mi.mesh.surface_get_arrays(0)
			var xf := mi.transform                     # (the importer may leave a node transform: bake it)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in range(v.size()):
				v[i] = xf * v[i]
				n[i] = (xf.basis * n[i]).normalized()
			var c = a[Mesh.ARRAY_COLOR]
			var idx = a[Mesh.ARRAY_INDEX]
			if idx == null:
				idx = PackedInt32Array(range(v.size()))
			_lib[String(mi.name)] = [v, n, c if c != null else PackedColorArray(), idx]
			var top := 0.0
			for p in v:
				top = maxf(top, p.y)
			_h[String(mi.name)] = top
		stack.append_array(nd.get_children())
	root.free()


func _put(prop: String, xf: Transform3D, kind := 0, phase := 0.0, anchor := Vector3.ZERO, v2 := Vector2.ZERO) -> void:
	if not _lib.has(prop):
		return
	var L: Array = _lib[prop]
	var v: PackedVector3Array = L[0]
	var n: PackedVector3Array = L[1]
	var c: PackedColorArray = L[2]
	var idx: PackedInt32Array = L[3]
	if prop.ends_with("_glass"):
		var b0 := _gv.size()
		for i in range(v.size()):
			_gv.append(xf * v[i])
			_gn.append((xf.basis * n[i]).normalized())
		for i in idx:
			_gi.append(b0 + i)
	else:
		var b := _pv.size()
		var drone := kind == 3
		var ds := _sc("drone")
		for i in range(v.size()):
			_pv.append(v[i] * ds if drone else xf * v[i])
			_pn.append(n[i] if drone else (xf.basis * n[i]).normalized())
			_pc.append(c[i] if i < c.size() else Color(0.2, 0.22, 0.26))
			_pu.append(Vector2(kind, phase))
			_pu2.append(v2)
			_pk.append_array(PackedFloat32Array([anchor.x, anchor.y, anchor.z, 0.0]))
		for i in idx:
			_pi.append(b + i)
	tris += idx.size() / 3
	counts[prop] = int(counts.get(prop, 0)) + 1
	if not prop in ["pipe", "flange", "rail", "local"] and not prop.ends_with("_glass"):
		where.append("%s(%d,%d)" % [prop, roundi(xf.origin.x), roundi(xf.origin.z)])


func _xf(p: Vector2, yaw: float, prop := "", y := 0.0) -> Transform3D:
	## a prop's placement at p, yaw, scaled by _sc(prop) (no prop: 1x)
	var s := _sc(prop) if prop != "" else 1.0
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, _y + y, p.y))


func _sc(prop: String) -> float:
	## PROP_S, or less where the prop (with its glass / its other arm part) would top PROP_MAX_H
	var g := prop.trim_suffix("_glass")
	var top := float(_h.get(g, 0.0))
	if g.begins_with("arm"):
		top = maxf(float(_h.get("arm_base", 0.0)), float(_h.get("arm_upper", 0.0)))
	elif g == "drone":
		return minf(PROP_S, (PROP_MAX_H - DRONE_Y - 0.2) / maxf(float(_h.get("drone", 0.0)), 0.01))
	top = maxf(top, float(_h.get(g + "_glass", 0.0)))
	return minf(PROP_S, PROP_MAX_H / top) if top > 0.0 else PROP_S


func max_top() -> float:
	## the tallest placed prop's top (m over the floor), for the report
	var m := 0.0
	for k in counts:
		if _h.has(k):
			m = maxf(m, float(_h[k]) * _sc(k) if k != "drone" else DRONE_Y + float(_h[k]) * _sc(k) + 0.18)
	return m


# ------------------------------------------------------------------ where things may stand
func on_hud(p: Vector3) -> bool:
	if _cam.is_position_behind(p):
		return true
	var s := _cam.unproject_position(p) / _vp
	if s.x < 0.0 or s.y < 0.0 or s.x > 1.0 or s.y > 1.0:
		return true
	for r in HUD:
		if (r as Rect2).grow(0.015).has_point(s):
			return true
	return false


func _lane_d(q: Vector2, skip := -1) -> float:
	var best := INF
	for i in wl.locals.feeds:
		if i == skip:
			continue
		var path: Array = wl.locals.feeds[i]["path"]
		for k in range(1, path.size()):
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, path[k - 1], path[k]).distance_to(q))
	return best


func ok(q: Vector2, r: float, h: float, lanes := true) -> bool:
	## a prop of radius r, height h may stand at q
	if district_alpha(q) < 0.999 or district_alpha(q + (q - Vector2(district.x + district.y, district.z + district.w) * 0.5).normalized() * (r + 1.5)) < 0.98:
		return false
	for a in _arcs:                                    # the guide arcs (quarter circles) round the craters
		var l := (q - (a[0] as Vector2)).rotated(float(a[2]))
		if l.x < r and l.y < r and absf(l.length() - float(a[1])) < r + 0.6:
			return false
	if _fall_d(q) < FALL_BAND + r:
		return false
	for tb in wl._tubes:
		if q.distance_to(Vector2(tb["x"], tb["z"])) < float(tb["r"]) + 3.2 + r:
			return false
	for c in wl.locals.craters:
		if q.distance_to(Vector2((c as Vector3).x, (c as Vector3).z)) < 8.6 + r:   # the 16 m spawn surround + a lip
			return false
	for o in _occ:
		if q.distance_to(o[0]) < r + float(o[1]) + 0.7:
			return false
	if wl.pipes != null and wl.pipes.near(q, r + 0.4):   # PITS / TUBES: props keep off the transport tubes
		return false
	if lanes and _lane_d(q) < 1.5 + r:
		return false
	for k in range(9):
		var e := q if k == 8 else q + Vector2.from_angle(TAU * k / 8.0) * r
		if wl.locals.mask_at(e.x, e.y) >= 0 and wl.locals.mask_at(e.x, e.y) <= 200:
			return false
		if on_hud(Vector3(e.x, _y, e.y)) or on_hud(Vector3(e.x, _y + h, e.y)):
			return false
	return true


func _fall_d(q: Vector2) -> float:
	## distance to the nearest bridge's line on the floor (bodies fall off its sides and splat close to it)
	var best := INF
	for e in wl.sim.edges:
		var pa: Vector3 = wl.sim.nodes[int(e["a"])]["pos"]
		var pb: Vector3 = wl.sim.nodes[int(e["b"])]["pos"]
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)).distance_to(q))
	return best


func find(target: Vector2, r: float, h: float, search := 9.0, lanes := true) -> Variant:
	## the nearest spot to target (spiral, 0.75 m steps) where a prop of radius r may stand; null if none within search
	if ok(target, r, h, lanes):
		return target
	var step := 0.75
	var ring := 1
	while ring * step <= search:
		var best: Variant = null
		var bd := INF
		for ix in range(-ring, ring + 1):
			for iz in range(-ring, ring + 1):
				if maxi(absi(ix), absi(iz)) != ring:
					continue
				var q := target + Vector2(ix, iz) * step
				if q.distance_to(target) < bd and ok(q, r, h, lanes):
					bd = q.distance_to(target)
					best = q
		if best != null:
			return best
		ring += 1
	return null


func _claim(q: Vector2, r: float) -> void:
	_occ.append([q, r])


# ------------------------------------------------------------------ the layout
func _place_all() -> void:
	var lc := wl.locals
	var bb := lc.board_bounds()
	var mid := bb.get_center()
	_plan_arcs()                                       # the guide arcs first: the props keep off their lines
	# 1 the pipe runs and queue rails first (they follow the lanes), so the bigger props keep clear of them
	var fi := 0
	for i in lc.feeds:
		_pipe_run(i, lc.feeds[i], 1.0 if fi % 2 == 0 else -1.0)
		_rails(lc.feeds[i])
		fi += 1
	# 2 per crater (left / right side of the board): a specimen bay, a goo line, a workstation, service fixtures
	for k in range(lc.craters.size()):
		var cp: Vector3 = lc.craters[k]
		var c := Vector2(cp.x, cp.z)
		var s := signf(c.x - mid.x) if absf(c.x - mid.x) > 1.0 else (1.0 if k % 2 == 0 else -1.0)
		_goo_line(c, s, k, bb)
		_specimen_bay(c, s, k)
		_workstation(c, s, k, bb)
	# 3 the bands just past the board (top and sides): manifolds, tanks, vents
	for s in [-1.0, 1.0]:
		_far_band(s, bb)
	# 4 fixtures in what floor is left: grates + vents + posts
	_fixtures(bb)
	# 5 the drone over the first crater; the guide arcs round the craters
	if not lc.craters.is_empty():
		var c0: Vector3 = lc.craters[0]
		_drone_c = Vector3(c0.x, _y + DRONE_Y, c0.z)
		_put("drone", Transform3D.IDENTITY, 3, 0.0)
		_light(Vector2(c0.x, c0.z), 3.6 * PROP_S, Color(1.0, 0.85, 0.6, 0.34), true)
	_crater_decals()


func _plan_arcs() -> void:
	## the guide arcs round each crater: 12.5 m and 16.5 m quarters facing out / far, an 8.5 m quarter on the near inner
	## side (an arc cell's circle centre is its bottom-right corner (+x, +z); the yaw turns the quarter)
	var lc := wl.locals
	var mid := lc.board_bounds().get_center()
	for k in range(lc.craters.size()):
		var cp: Vector3 = lc.craters[k]
		var c := Vector2(cp.x, cp.z)
		var s := signf(c.x - mid.x)
		for spec in [[1, PI if s < 0 else PI / 2], [2, -PI / 2 if s < 0 else 0.0], [0, 0.0 if s < 0 else -PI / 2]]:
			var cell: Rect2 = WorldDecals.ARCS[spec[0]]
			_arcs.append([c, WorldDecals._m(cell).x, float(spec[1]), cell])


func _specimen_bay(c: Vector2, s: float, k: int) -> void:
	## a specimen tank and a pod bench on the crater's outer / far side, a cold pool in front, a goo stain, a light post
	var S := PROP_S
	var tries := [c + Vector2(s * 11.0, -4.0), c + Vector2(s * 3.0, -11.5), c + Vector2(s * 11.0, 5.0), c + Vector2(0, -12.0),
			c + Vector2(-s * 10.0, -8.0), c + Vector2(s * 8.0, 10.0), c + Vector2(-s * 6.0, 12.0), c + Vector2(s * 15.0, 15.0)]
	for t in tries:
		var q = find(t, 1.6 * _sc("tank"), 2.9 * _sc("tank"), 6.0)
		if q == null:
			continue
		_put("tank", _xf(q, -s * 0.6 + 0.3 * k, "tank"))
		_put("tank_glass", _xf(q, -s * 0.6 + 0.3 * k, "tank"))
		_claim(q, 1.6 * _sc("tank"))
		_light(q + Vector2(0, 1.6 * S), 2.6 * S, COLD)
		_decal_stain(q + Vector2(-s * 1.6, 1.2) * S, 1.4 * S)
		var q2 = find(q + Vector2(s * 3.6, 0.6) * S, 1.8 * _sc("pods"), 2.2 * _sc("pods"), 8.0)
		if q2 != null:
			var yaw := atan2(-(q2.y - c.y), q2.x - c.x) + PI / 2
			_put("pods", _xf(q2, yaw, "pods"))
			_put("pods_glass", _xf(q2, yaw, "pods"))
			_claim(q2, 1.8 * _sc("pods"))
			_light(q2 + Vector2(0, 1.4 * S), 2.4 * S, COLD)
		var q3 = find(q + Vector2(-s * 2.4, -1.8) * S, 0.35 * _sc("post"), 2.6 * _sc("post"), 3.0)
		if q3 != null:
			_post(q3)
		return


func _goo_line(c: Vector2, s: float, k: int, bb: Rect2) -> void:
	## a goo conveyor carrying gray Locals, its ends on hazard patches, a valve manifold at its drive end
	var S := _sc("conveyor")
	var tries := [Vector2(c.x + s * 2.0, bb.position.y - 3.0), Vector2(c.x + s * 12.0, c.y + 10.0),
			Vector2(c.x - s * 4.0, bb.position.y - 4.0), Vector2(c.x, c.y + 13.0), Vector2(c.x + s * 13.0, c.y - 6.0)]
	for t0 in tries:
		var found := false
		var t: Vector2 = t0
		var yaw := 0.0
		var dir := Vector2.RIGHT
		for ring in range(0, 9):                        # a spiral of 0.8 m steps round the target
			for ix in range(-ring, ring + 1):
				for iz in range(-ring, ring + 1):
					if found or maxi(absi(ix), absi(iz)) != ring:
						continue
					for yw in [0.0, 0.3 * s, -0.3 * s, PI / 2]:
						if found:
							break
						var tq: Vector2 = t0 + Vector2(ix, iz) * 0.8
						var dq := Vector2(cos(yw), -sin(yw))
						var all_ok := true
						for f in [-3.2, -1.6, 0.0, 1.6, 3.2]:
							if not ok(tq + dq * f * S, 1.0 * S, 1.3 * S):
								all_ok = false
								break
						if all_ok:
							found = true
							t = tq
							yaw = yw
							dir = dq
			if found:
				break
		if not found:
			continue
		var yy: float = yaw if s < 0 else yaw + PI
		var xf := _xf(t, yy, "conveyor")                # its drive box toward the board's outside
		_put("conveyor", xf)
		for f in [-3.2, -1.6, 0.0, 1.6, 3.2]:
			_claim(t + dir * f * S, 1.0 * S)
		var a := xf * Vector3(2.9, 0.86, 0)
		var tr := xf.basis * Vector3(-5.8, 0, 0)
		for r in range(4):
			var rx := Transform3D(xf.basis.scaled(Vector3.ONE * 0.62), a)
			_put("local", rx, 1, r * 0.25 + k * 0.13, a, Vector2(tr.x, tr.z))
		var e0 := xf * Vector3(3.8, 0, 0)
		var e1 := xf * Vector3(-4.3, 0, 0)
		wl.decals._add(Vector2(e0.x, e0.z), Vector2(3.0, 3.0) * S, yy, WorldDecals.HAZARD[2], WorldDecals.T_HAZARD, false, 0.02)
		wl.decals._add(Vector2(e1.x, e1.z), Vector2(4.0, 2.0) * S, yy + PI / 2, WorldDecals.HAZARD[0], WorldDecals.T_HAZARD, false, 0.02)
		_decal_stain(Vector2(e0.x, e0.z) + Vector2(0.6, 1.4) * S, 1.0 * S)
		_light(t + Vector2(0, 1.0 * S), 3.0 * S, WARM)
		var mpos = find(Vector2(e1.x, e1.z) + Vector2(0, -2.6 * S), 1.3 * _sc("manifold"), 1.7 * _sc("manifold"), 4.0)
		if mpos != null:
			_put("manifold", _xf(mpos, yaw + PI / 2, "manifold"))
			_claim(mpos, 1.3 * _sc("manifold"))
		return


func _workstation(c: Vector2, s: float, k: int, bb: Rect2) -> void:
	## a lab bench with a robot arm beside it (its reach on a hazard patch), a light post and its warm pool
	var S := PROP_S
	var tries := [Vector2(c.x + s * 7.0, bb.end.y + 3.0), Vector2(c.x + s * 12.0, c.y + 9.0),
			Vector2(c.x - s * 6.0, bb.position.y - 3.0), Vector2(c.x + s * 13.0, c.y - 8.0), Vector2(c.x - s * 9.0, c.y + 10.0)]
	for t in tries:
		var q = find(t, 1.7 * _sc("bench"), 1.8 * _sc("bench"), 6.0)
		if q == null:
			continue
		var yaw := 0.0 if absf(q.y - c.y) > 6.0 else PI / 2
		_put("bench", _xf(q, yaw, "bench"))
		_put("bench_glass", _xf(q, yaw, "bench"))
		_claim(q, 1.7 * _sc("bench"))
		_light(q + Vector2(0, 1.1 * S), 2.8 * S, COLD)
		var qa = find(q + Vector2(-s * 3.2, 0.4) * S, 1.2 * _sc("arm"), 3.0 * _sc("arm"), 7.0)
		if qa == null:
			qa = find(q + Vector2(s * 3.2, 0.4) * S, 1.2 * _sc("arm"), 3.0 * _sc("arm"), 7.0)
		if qa != null:
			var ay := (atan2(-(q.y - qa.y), q.x - qa.x))
			var xa := _xf(qa, ay, "arm")
			_put("arm_base", xa)
			_put("arm_upper", xa, 2, k * 1.7, xa.origin)
			_claim(qa, 1.9 * _sc("arm"))
			wl.decals._add(qa, Vector2(6.0, 3.0) * _sc("arm"), ay, WorldDecals.HAZARD[1], WorldDecals.T_HAZARD, false, 0.022)
		var qp = find(q + Vector2(s * 2.4, -1.4) * S, 0.35 * _sc("post"), 2.6 * _sc("post"), 3.0)
		if qp != null:
			_post(qp)
		return


func _far_band(s: float, bb: Rect2) -> void:
	## the floor just past the board (the top band, then the side's): a manifold, a second tank, a steam vent, a grate -
	## spread out, clear of the top HUD capsule; what does not fit is dropped
	var cx := bb.get_center().x
	var y0 := bb.position.y - 3.5
	var sx := bb.end.x + 3.5 if s > 0 else bb.position.x - 3.5
	var spots := [Vector2(cx + s * 30.0, y0), Vector2(sx, bb.get_center().y - 6.0), Vector2(cx + s * 18.0, y0 - 1.0),
			Vector2(sx, bb.get_center().y + 8.0)]
	var made := 0
	for t in spots:
		var q = find(t, 1.6 * PROP_S, 2.9 * _sc("tank"), 5.0)
		if q == null:
			made += 1
			continue
		match made:
			0:
				_put("manifold", _xf(q, s * 0.4, "manifold"))
				_claim(q, 1.4 * PROP_S)
				_decal_hazard(q + Vector2(0, 1.8 * PROP_S), 1, s * 0.4)
				_light(q + Vector2(0, 1.3 * PROP_S), 2.6 * PROP_S, WARM)
			1:
				_put("tank", _xf(q, s * 0.5, "tank"))
				_put("tank_glass", _xf(q, s * 0.5, "tank"))
				_claim(q, 1.6 * _sc("tank"))
				_light(q + Vector2(0, 1.6 * PROP_S), 2.6 * PROP_S, COLD)
				_decal_stain(q + Vector2(1.3, 1.1) * PROP_S, 1.2 * PROP_S)
			2:
				_vent(q)
			_:
				_put("grate", _xf(q, 0.0, "grate"))
				_claim(q, 1.2 * PROP_S)
		made += 1


func _fixtures(bb: Rect2) -> void:
	## grates, vents and posts on the remaining seen floor round the board (a coarse sweep, spaced out)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var want := {"grate": 3, "vent": 2, "post": 3}
	var tries := 0
	while tries < 800 and (want["grate"] + want["vent"] + want["post"]) > 0:
		tries += 1
		var q := Vector2(rng.randf_range(district.x, district.y), rng.randf_range(district.z, district.w))
		var kind: String = ["grate", "vent", "post"][rng.randi() % 3]
		if want[kind] <= 0:
			continue
		var r := (1.3 if kind == "grate" else (0.7 if kind == "vent" else 0.35)) * PROP_S
		var near := false
		for o in _occ:
			if q.distance_to(o[0]) < 4.0 + r:
				near = true
				break
		if near or not ok(q, r, (2.6 if kind == "post" else 2.4) * PROP_S):
			continue
		match kind:
			"grate":
				_put("grate", _xf(q, rng.randf() * 0.4, "grate"))
				_claim(q, r)
				_light(q, 2.0 * PROP_S, Color(0.55, 0.8, 1.0, 0.12))
			"vent":
				_vent(q)
			"post":
				_post(q)
		want[kind] -= 1


func _post(q: Vector2) -> void:
	_put("post", _xf(q, 0.0, "post"))
	_claim(q, 0.4 * PROP_S)
	_light(q, 3.4 * PROP_S, WARM)


func _vent(q: Vector2) -> void:
	var S := _sc("vent")
	_put("vent", _xf(q, 0.0, "vent"))
	_claim(q, 0.7 * S)
	var steam_h := minf(2.4 * S, PROP_MAX_H - 0.45 * S)
	for k in range(2):                                   # two crossed steam cards, 1.95 x 3.6 m at 1.5x
		var a := PI / 4 + k * PI / 2
		var d := Vector3(cos(a), 0, sin(a)) * 0.65 * S
		var o := Vector3(q.x, _y + 0.45 * S, q.y)
		var b := _sv.size()
		for corner in [[-1.0, 0.0], [1.0, 0.0], [1.0, 1.0], [-1.0, 1.0]]:
			_sv.append(o + d * corner[0] + Vector3(0, steam_h * corner[1], 0))
			_sc_steam.append(Color(fmod(q.x * 0.13 + k * 0.37, 1.0), 0, 0, 1))
			_su2.append(Vector2((corner[0] + 1.0) / 2.0, 1.0 - corner[1]))
		_si.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
		tris += 2
	_decal_stain(q + Vector2(0.9, 0.5) * S, 0.8 * S)
	counts["steam_card"] = int(counts.get("steam_card", 0)) + 2


func _light(q: Vector2, r: float, col: Color, drone := false) -> void:
	var b := _lv.size()
	var y := _y + 0.05
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector2 = q + corner * r
		_lv.append(Vector3(p.x, y, p.y))
		_lc.append(col)
		_lu.append(Vector2(3.0 if drone else 0.0, 0.0))
		_lu2.append((corner + Vector2.ONE) / 2.0)
	_li.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	tris += 2
	counts["light_pool"] = int(counts.get("light_pool", 0)) + 1


# ------------------------------------------------------------------ pipes + rails along the lanes
func _pipe_run(fi: int, f: Dictionary, side: float) -> void:
	## a floor pipe from the crater's rim toward the tube foot, 2.6 m beside the lane; only the stretches the camera sees
	if not (WorldLayer.FLOOR_TUBES or "--floor-tubes" in OS.get_cmdline_user_args()):
		return                                         # FLOOR TUBES OFF (Daniele 2026-11-09): no floor pipe runs for now
	var S := _sc("pipe")
	var path: Array = f["path"]
	var pts: Array = []
	for k in range(path.size()):
		var a: Vector2 = path[maxi(k - 1, 0)]
		var b: Vector2 = path[mini(k + 1, path.size() - 1)]
		var d := (b - a).normalized()
		pts.append((path[k] as Vector2) + Vector2(-d.y, d.x) * 2.6 * side)
	var pieces: Array = []                              # the path cut into <= 2 m pieces: the seen ones survive
	for k in range(1, pts.size() - 1):                  # stops a waypoint short of the door (the queue's stretch)
		var n := maxi(1, ceili((pts[k - 1] as Vector2).distance_to(pts[k]) / 2.0))
		for j in range(n):
			pieces.append([(pts[k - 1] as Vector2).lerp(pts[k], float(j) / n), (pts[k - 1] as Vector2).lerp(pts[k], float(j + 1) / n)])
	var run := 0
	for pc in pieces:
		var a2: Vector2 = pc[0]
		var b2: Vector2 = pc[1]
		var L := a2.distance_to(b2)
		if L < 0.4:
			continue
		var good := true
		for t in [0.0, 0.5, 1.0]:
			var q := a2.lerp(b2, t)
			var mv := wl.locals.mask_at(q.x, q.y)
			if (mv >= 0 and mv <= 200) or on_hud(Vector3(q.x, _y, q.y)) or _lane_d(q, fi) < 1.9 or district_alpha(q) < 0.99:
				good = false
			for tb in wl._tubes:
				if q.distance_to(Vector2(tb["x"], tb["z"])) < float(tb["r"]) + 2.4:
					good = false
			for c in wl.locals.craters:
				if q.distance_to(Vector2((c as Vector3).x, (c as Vector3).z)) < 8.2:
					good = false
			if wl.pipes != null and wl.pipes.near(q, 0.6):   # PITS / TUBES: no lane pipe through a transport tube
				good = false
		if not good:
			continue
		var d2 := (b2 - a2) / L
		var yaw := atan2(-d2.y, d2.x)
		var mid := (a2 + b2) / 2.0
		_put("pipe", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(L + 0.1, S, S)), Vector3(mid.x, _y, mid.y)))
		_put("flange", _xf(a2, yaw, "flange"))
		_put("flange", _xf(b2, yaw, "flange"))
		run += 1
	if run > 0:
		counts["pipe_runs"] = int(counts.get("pipe_runs", 0)) + 1


func _rails(f: Dictionary) -> void:
	## queue rails on both sides of the lane's last 8 m before the door (where the line waits), seen stretches only;
	## 1.5x, set 1.4 m off the lane (the Locals keep their walk)
	var path: Array = f["path"]
	var total := 0.0
	for k in range(1, path.size()):
		total += (path[k - 1] as Vector2).distance_to(path[k])
	var step := 2.0 * _sc("rail")
	var dd := maxf(total - 9.0, 0.5)
	while dd < total - 1.5:
		var at: Array = WorldLocals._along(path, dd)
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var nrm := Vector2(-dir.y, dir.x)
		var yaw := atan2(-dir.y, dir.x)
		for sd in [-1.0, 1.0]:
			var q: Vector2 = p + nrm * 1.4 * sd
			var e: Vector2 = q + dir * step
			var mv := wl.locals.mask_at(q.x, q.y)
			var mv2 := wl.locals.mask_at(e.x, e.y)
			if (mv >= 0 and mv <= 200) or (mv2 >= 0 and mv2 <= 200) or on_hud(Vector3(q.x, _y + 1.5, q.y)):
				continue
			var near_tube := false
			for tb in wl._tubes:
				if q.distance_to(Vector2(tb["x"], tb["z"])) < float(tb["r"]) + 1.0 or e.distance_to(Vector2(tb["x"], tb["z"])) < float(tb["r"]) + 1.0:
					near_tube = true
			if wl.pipes != null and (wl.pipes.near(q, 0.5) or wl.pipes.near(e, 0.5)):
				near_tube = true                         # PITS / TUBES: no rail through a transport tube
			if near_tube:
				continue
			_put("rail", _xf(q, yaw, "rail"))
		dd += step


# ------------------------------------------------------------------ decals placed with intent
func _decal_stain(q: Vector2, s: float) -> void:
	## the stain cells in turn (all eight get used), size s x the cell
	if wl.decals == null:
		return
	var cell: Rect2 = WorldDecals.STAINS[_stain_i % WorldDecals.STAINS.size()]
	_stain_i += 1
	wl.decals._add(q, WorldDecals._m(cell) * s, fmod(q.x * 1.7, TAU), cell, WorldDecals.T_STAIN, false, 0.018)


func _decal_hazard(q: Vector2, i: int, yaw: float) -> void:
	if wl.decals == null:
		return
	var cell: Rect2 = WorldDecals.HAZARD[i]
	wl.decals._add(q, WorldDecals._m(cell) * PROP_S, yaw, cell, WorldDecals.T_HAZARD, false, 0.02)


func _crater_decals() -> void:
	## the guide arcs planned round each crater (_plan_arcs), stains where the Locals leave the rim, goo stains at a few
	## seen tube feet
	if wl.decals == null:
		return
	var lc := wl.locals
	for a in _arcs:
		var cell: Rect2 = a[3]
		var sz := WorldDecals._m(cell)
		var yaw: float = a[2]
		var off := Vector3(-sz.x / 2.0, 0, -sz.y / 2.0).rotated(Vector3.UP, yaw)
		wl.decals._add((a[0] as Vector2) + Vector2(off.x, off.z), sz, yaw, cell, WorldDecals.T_ARC, false, 0.012)
	for k in range(lc.craters.size()):
		var cp: Vector3 = lc.craters[k]
		var c := Vector2(cp.x, cp.z)
		for j in range(3):
			var a2 := TAU * (j / 3.0) + k
			_decal_stain(c + Vector2.from_angle(a2) * 6.4, 0.7)
	var n := 0
	for tb in wl._tubes:
		var q := Vector2(tb["x"], tb["z"]) + Vector2(2.3, 1.8)
		var mv := lc.mask_at(q.x, q.y)
		if mv > 200 and n < 5:
			_decal_stain(q, 0.8)
			n += 1


# ------------------------------------------------------------------ meshes
func _finish() -> void:
	var abyss := wl.haze_abyss()
	if _pv.size() > 0:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = _pv
		a[Mesh.ARRAY_NORMAL] = _pn
		a[Mesh.ARRAY_COLOR] = _pc
		a[Mesh.ARRAY_TEX_UV] = _pu
		a[Mesh.ARRAY_TEX_UV2] = _pu2
		a[Mesh.ARRAY_CUSTOM0] = _pk
		a[Mesh.ARRAY_INDEX] = _pi
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {},
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER_PROP
		mat.set_shader_parameter("abyss", abyss)
		mat.set_shader_parameter("haze", maxf(wl.floor_haze, 0.0))
		_drone_uniforms(mat)
		_add_mi(m, mat)
	if _gv.size() > 0:
		var g := []
		g.resize(Mesh.ARRAY_MAX)
		g[Mesh.ARRAY_VERTEX] = _gv
		g[Mesh.ARRAY_NORMAL] = _gn
		g[Mesh.ARRAY_INDEX] = _gi
		var gm := ArrayMesh.new()
		gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g)
		_add_mi(gm, _fx_mat(0, abyss, -7))
	if _sv.size() > 0:
		var st := []
		st.resize(Mesh.ARRAY_MAX)
		st[Mesh.ARRAY_VERTEX] = _sv
		st[Mesh.ARRAY_NORMAL] = PackedVector3Array(Array(range(_sv.size())).map(func(_i): return Vector3.UP))
		st[Mesh.ARRAY_COLOR] = _sc_steam
		st[Mesh.ARRAY_TEX_UV] = PackedVector2Array(Array(range(_sv.size())).map(func(_i): return Vector2.ZERO))
		st[Mesh.ARRAY_TEX_UV2] = _su2
		st[Mesh.ARRAY_INDEX] = _si
		var sm := ArrayMesh.new()
		sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st)
		_add_mi(sm, _fx_mat(1, abyss, -6))
	if _lv.size() > 0:
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = _lv
		la[Mesh.ARRAY_NORMAL] = PackedVector3Array(Array(range(_lv.size())).map(func(_i): return Vector3.UP))
		la[Mesh.ARRAY_COLOR] = _lc
		la[Mesh.ARRAY_TEX_UV] = _lu
		la[Mesh.ARRAY_TEX_UV2] = _lu2
		la[Mesh.ARRAY_INDEX] = _li
		var lm := ArrayMesh.new()
		lm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, la)
		_add_mi(lm, _fx_mat(2, abyss, -8))


func _fx_mat(mode: int, abyss: Color, prio: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_FX
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("abyss", abyss)
	m.set_shader_parameter("haze", maxf(wl.floor_haze, 0.0))
	_drone_uniforms(m)
	m.render_priority = prio
	return m


func _drone_uniforms(m: ShaderMaterial) -> void:
	m.set_shader_parameter("drone_c", _drone_c)
	m.set_shader_parameter("drone_r", DRONE_R)
	m.set_shader_parameter("drone_w", DRONE_W)


func _add_mi(m: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(district.x - 20, _y - 5, district.z - 20), Vector3(district.y - district.x + 40, 30,
			district.w - district.z + 40))
	add_child(mi)
	_mats.append(mat)
	draws += 1
