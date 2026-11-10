class_name WorldDecals
extends Node3D
## LAB FLOOR DECALS (WORLD PASS 2, director round 5: LAB-FLOOR-DECALS-4096 + manifest, cropped to its used 2048 px corner
## as assets/world/lab5_decals_2048.png, 32 px/m). Cosmetic, view only. ONE MultiMesh of flat quads (one draw, one atlas,
## shaders/world_decal.gdshader):
##  - A1 / A2 spawn surround under each containment ring (its empty 10 m centre is the ring),
##  - B march lane along every Local path (repeats along its length, chevrons point the walking direction),
##  - C tube-foot pool at each tube foot (white in the atlas: tinted with the owner colour, low alpha),
##  - a few F stains and D guide arcs on floor the default camera sees (the floor plan's mask), clear of the rest.
## WORLD COMPLETE LAB (world_dressing.gd): every cell is used - the E hazard patches too - and the stains, arcs and
## hazards are placed with intent by the dressing (round the craters, under the props); the marks are pushed away from
## the floor's mean (shader contrast) so they read at the default camera, still under the decks' brightness.

const ATLAS := "res://assets/world/lab5_decals_2048.png"
const SHADER := preload("res://shaders/world_decal.gdshader")
const ATLAS_PX := 2048.0
const PX_PER_M := 32.0
# manifest rects (px): x, y, w, h
const A1 := Rect2(32, 32, 512, 512)
const A2 := Rect2(608, 32, 512, 512)
const LANE := Rect2(1184, 32, 64, 512)
const POOL := Rect2(1312, 32, 192, 192)
const ARCS := [Rect2(32, 640, 272, 272), Rect2(368, 640, 400, 400), Rect2(832, 640, 528, 528)]
const STAINS := [Rect2(32, 1472, 160, 160), Rect2(256, 1472, 128, 128), Rect2(448, 1472, 96, 128), Rect2(608, 1472, 64, 96),
		Rect2(736, 1472, 32, 64), Rect2(832, 1472, 160, 64), Rect2(1056, 1472, 96, 160), Rect2(1216, 1472, 128, 64)]
const HAZARD := [Rect2(32, 1248, 128, 64), Rect2(224, 1248, 192, 96), Rect2(480, 1248, 96, 96)]
const LANE_W := 1.6               # m: the lane strip's width under the 1 m Locals
const POOL_A := 0.9               # the tube-foot pool's opacity (its own alpha is low: mean 0.17)
# tints (rgb x, alpha x; COLOR is a half float: > 1 lifts): the atlas paints its marks close to the floor's own mean,
# which vanishes under the arena's mist at the game camera - lanes, rings and arcs are lifted, stains stay dark goo
const T_LANE := Color(1.35, 1.4, 1.55, 2.6)
const T_RING := Color(1.35, 1.38, 1.5, 2.2)
const T_ARC := Color(1.45, 1.5, 1.7, 2.4)
# FLOOR RINGS (Daniele 2026-11-11 on demo15: "the white circular floor decorations around nodes are too light, make them
# darker"): the spawn surrounds (T_RING) and the guide arcs (T_ARC) keep their shape; their rgb lift is scaled by one
# level. 1.0 = the demo15 look. Dev override --rings-dim=<soft|dark|0..1>.
const FLOOR_RINGS_LEVELS := {"soft": 0.62, "dark": 0.42}
const FLOOR_RINGS := 0.42         # DEFAULT = "dark" (recommended)
const T_STAIN := Color(0.75, 0.78, 0.85, 1.8)
const T_HAZARD := Color(1.25, 1.2, 1.1, 1.6)
const CONTRAST := 2.4             # the marks pushed away from the floor's mean (world_decal.gdshader)
const N_STAINS := 9
const N_ARCS := 3
const MAX := 260

var _mm: MultiMesh
var _n := 0
var _pool_slot := {}              # tube index -> instance
var tris := 0
var _lanes := {}                  # feed key -> [[instance, start m, quad m, centre, yaw, shown 0..1]] (TRACE)
static var _ring_k := -1.0


static func ring_level() -> float:
	## the FLOOR_RINGS level in use (the default, or --rings-dim=<soft|dark|0..1>)
	if _ring_k < 0.0:
		_ring_k = FLOOR_RINGS
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--rings-dim="):
				var v := a.substr(12)
				_ring_k = float(FLOOR_RINGS_LEVELS[v]) if FLOOR_RINGS_LEVELS.has(v) else clampf(v.to_float(), 0.0, 1.0)
	return _ring_k


static func ring_tint(t: Color) -> Color:
	## T_RING / T_ARC darkened by the FLOOR_RINGS level (shape and opacity kept)
	var k := ring_level()
	return Color(t.r * k, t.g * k, t.b * k, t.a)


func setup(floor_mat: ShaderMaterial, y: float) -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("atlas", load(PerfProfile.hi_path(ATLAS)))   # FOLDABLES: its hi copy once one is shipped
	for k in ["abyss", "centre", "r0", "r1", "haze"]:
		m.set_shader_parameter(k, floor_mat.get_shader_parameter(k))
	m.set_shader_parameter("contrast", CONTRAST)
	m.render_priority = -9                           # over the floor (-10), under the splats (-8)
	quad.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	position = Vector3(0, y, 0)


func _add(c: Vector2, size: Vector2, yaw: float, cell: Rect2, tint: Color, lane := false, lift := 0.02, reveal := 1.0) -> int:
	if _n >= MAX:
		return -1
	# the Y scale (a flat quad never uses it) carries a lane's reveal 0..1 from its crater end (world_decal.gdshader)
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, maxf(reveal, 0.0001), size.y))
	_mm.set_instance_transform(_n, Transform3D(b, Vector3(c.x, lift, c.y)))
	var dv := cell.size.y / ATLAS_PX
	_mm.set_instance_custom_data(_n, Color(cell.position.x / ATLAS_PX, cell.position.y / ATLAS_PX, cell.size.x / ATLAS_PX,
			-dv if lane else dv))
	_mm.set_instance_color(_n, tint)
	_n += 1
	_mm.visible_instance_count = _n
	tris += 2
	return _n - 1


static func _m(cell: Rect2) -> Vector2:
	return cell.size / PX_PER_M


func build(lc: WorldLocals, cam: Camera3D) -> void:
	var wl := lc.wl
	var _trace_always := "--trace-always" in OS.get_cmdline_user_args()   # dev: the demo15 look (every lane from the start)
	# B: march lanes along every feed path (one quad per segment; a lane's top (chevrons) toward the door).
	# TRACE (Daniele 2026-11-11 on demo15: the goo trace on a line must not appear until the Locals start walking it): every
	# lane starts hidden and is revealed behind the feed's farthest walking Local (reveal_lane, from WorldLocals.step).
	for i in lc.feeds:
		var path: Array = (lc.feeds[i] as Dictionary)["path"]
		var segs: Array = []
		var at := 0.0
		for k in range(1, path.size()):
			var a: Vector2 = path[k - 1]
			var b: Vector2 = path[k]
			var d := b - a
			if d.length() < 0.3:
				at += d.length()
				continue
			# local -Z (the cell's top) along the walk: yaw so that Basis(UP, yaw) * (0, 0, -1) = (d.x, 0, d.y)
			var yaw := atan2(-d.x, -d.y)
			var ql := d.length() + 0.4
			var s := _add((a + b) / 2.0, Vector2(LANE_W, ql), yaw, LANE, T_LANE, true, 0.015, 1.0 if _trace_always else 0.0)
			if s >= 0:
				segs.append([s, at - 0.2, ql, (a + b) / 2.0, yaw, 1.0 if _trace_always else 0.0])
			at += d.length()
		_lanes[i] = segs
	# A1 / A2: the spawn surround under each crater (16 m, its empty 10 m centre = the ring)
	for k in range(lc.craters.size()):
		var p: Vector3 = lc.craters[k]
		_add(Vector2(p.x, p.z), _m(A1), 0.6 * k, A1 if k % 2 == 0 else A2, ring_tint(T_RING), false, 0.025)
	# C: the tube-foot pools (white, owner tint, low alpha) - only where a tube can show
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		var s := _add(Vector2(tb["x"], tb["z"]), _m(POOL), 0.0, POOL, Color(0, 0, 0, 0), false, 0.03)
		_pool_slot[i] = s
		tint_pool(i, tb["base"] if tb.get("shown", false) else Color(0, 0, 0, 0))
	# F stains / D arcs: on floor the default camera sees, clear of tube feet, craters and each other
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var b := lc.board_bounds().grow(20.0)
	var used: Array = []
	var stains := 0
	var arcs := 0
	var tries := 0
	if wl.get_node_or_null("Dressing") != null:      # the dressing places the stains / arcs / hazards with intent
		tries = 600
	while (stains < N_STAINS or arcs < N_ARCS) and tries < 600:
		tries += 1
		var q := Vector2(rng.randf_range(b.position.x, b.end.x), rng.randf_range(b.position.y, b.end.y))
		var want_arc := arcs < N_ARCS and (stains >= N_STAINS or rng.randf() < 0.3)
		var r := 9.0 if want_arc else 3.0
		if not lc.floor_visible(cam, Vector3(q.x, wl.floor_y, q.y)):
			continue
		if not _clear(lc, q, r, used):
			continue
		used.append([q, r])
		if want_arc:
			var cell: Rect2 = ARCS[arcs % ARCS.size()]
			_add(q, _m(cell), rng.randf() * TAU, cell, ring_tint(T_ARC), false, 0.012)
			arcs += 1
		else:
			var cell2: Rect2 = STAINS[rng.randi() % STAINS.size()]
			_add(q, _m(cell2), rng.randf() * TAU, cell2, T_STAIN, false, 0.018)
			stains += 1


static func _clear(lc: WorldLocals, q: Vector2, r: float, used: Array) -> bool:
	for tb in lc.wl._tubes:
		if q.distance_to(Vector2(tb["x"], tb["z"])) < r + 3.5:
			return false
	for p in lc.craters:
		if q.distance_to(Vector2((p as Vector3).x, (p as Vector3).z)) < r + 8.0:
			return false
	for u in used:
		if q.distance_to(u[0]) < r + float(u[1]) + 2.0:
			return false
	return true


func tint_pool(tube: int, c: Color) -> void:
	## the tube-foot pool shows the owner (low alpha); a clear colour hides it (no structure / tube gone)
	if not _pool_slot.has(tube) or int(_pool_slot[tube]) < 0:
		return
	_mm.set_instance_color(int(_pool_slot[tube]), Color(c.r, c.g, c.b, POOL_A * c.a))


func reveal_lane(feed: int, walked: float) -> void:
	## TRACE: show the feed's lane up to `walked` metres from the crater exit (its farthest walking Local); never shrinks
	if not _lanes.has(feed):
		return
	for sg in _lanes[feed]:
		var r := clampf((walked - float(sg[1])) / float(sg[2]), 0.0, 1.0)
		if r <= float(sg[5]) + 0.002:
			continue
		sg[5] = r
		var b := Basis(Vector3.UP, float(sg[4])) * Basis.from_scale(Vector3(LANE_W, maxf(r, 0.0001), float(sg[2])))
		var c: Vector2 = sg[3]
		_mm.set_instance_transform(int(sg[0]), Transform3D(b, Vector3(c.x, 0.015, c.y)))


func lane_shown(feed: int) -> float:
	## probes: metres of the feed's lane revealed so far
	var m := 0.0
	for sg in _lanes.get(feed, []):
		m += float(sg[5]) * float(sg[2])
	return m
