class_name WorldRiver
extends Node3D
## RIVER WORLD (Daniele 2026-11-15, "the new setting", References/Art direction 2026-11 - backgrounds/DECISIONS.md;
## brief WORKER-BRIEF-river-world.md): "center a river of goo, sides crust, top the sky. when you start the goo river is
## lets say 5m from node level, the more the game goes the more the level goes down and underneath shows a canyon ... by
## the end of the match the canyon is fully dried up" + "the tubes simply plugged in the floor via some crack ... our
## platform are foundamentally drill".
## VIEW ONLY: reads sim.time, sim.nodes and the map; never writes to the Sim, nothing in the protocol (a guest draws the
## same river from the host's clock).
##  - CANYON: one heightfield GENERATED from the map footprint (platform discs + bridges), no per-map placement: an uneven
##    bed (noise bars and banks + one deep main channel along the map's long side, so banks surface first and the channel
##    dries last) and crust walls rising past the footprint; the far wall ends where the screen's top band starts (the
##    default camera), so the SKY band shows above it. One draw, procedural crust shader (river_bed.gdshader).
##  - RIVER: one plane at the level, gray native goo (river_goo.gdshader). Level = TOP_DROP under the decks at 0:00, the
##    deepest bed (dry) exactly at Last Stand start (Rules.LAST_STAND_TIME, 4:00). Open, conservative readings (noted in
##    OPEN-QUESTIONS): Last Stand OFF drains to the Very Last Stand (6:00); the tutorial (T- maps, no VLS) keeps a full river.
##  - DRILLS: WorldLayer's per-platform tube runs down to the bed under it, into a crack (river_crack.gdshader, one MultiMesh).
##  - LOCALS: gray goo drops rise out of the river near an owned vat's drill and swim into it at the vat's pace; none at a
##    dry drill foot, so none once the river is dry.
##  - SKY: the background canvas layer's picture becomes the small painted band (river_sky.gdshader, placeholder).
## Off: --no-river (the 0.24.4 lab world).

const BED := preload("res://shaders/river_bed.gdshader")
const GOO := preload("res://shaders/river_goo.gdshader")
const SKY := preload("res://shaders/river_sky.gdshader")
const CRACK := preload("res://shaders/river_crack.gdshader")

const TOP_DROP := 5.0          # m: the river at 0:00 under the lowest deck level (Daniele: "5m from node level")
const BANK_DEPTH := 5.0        # m under the river's start: the bars and banks' mean height (+- BANK_VAR)
const BANK_VAR := 2.6
const CHANNEL_DEPTH := 11.0    # m under the start: the main channel's bottom (dries last)
const CHANNEL_W := 8.0         # m: the channel's half width (to the bank height)
const WALL_IN := 7.0           # m past the footprint where the walls start rising (+- 2.5 noise)
const WALL_RUN := 15.0         # m over which they reach the rim
const RIM_UP := 2.5            # m: the side / far rim over the highest deck (the near rim stays under it: RIM_NEAR)
const RIM_NEAR := -2.0
const MARGIN := 55.0           # m of canyon past the footprint on the sides and near side
const SKY_BAND := 0.13         # share of the screen height at the top left to the sky (default camera)
const DRILL_SINK := 1.4        # m: a drill runs this far into its crack
const CRACK_SIZE := 9.0        # m: the crack quad
const LOCALS_MAX := 160
const LOCAL_V := 1.7           # m/s across the goo
const LOCAL_EMERGE := 0.9
const LOCAL_SQUEEZE := 0.5
const LOCAL_FROM := Vector2(5.0, 10.0)   # m from the drill axis where a Local surfaces
const LOCALS_PER_DRILL := 6

var wl: WorldLayer
var sim: Sim
var main: Node
var built := false
var top_y := -5.0               # the river at 0:00
var dry_y := -16.0              # the deepest bed: the level at the drain's end
var level := -5.0
var drain_t := Rules.LAST_STAND_TIME   # s of match time to dry (INF: never)
var progress := 0.0             # 0..1 of the drain
var deck_hi := 0.0
var _low := false
# the grid, in the camera-aligned frame: world xz = c + u * ax_u + w * ax_w
var c := Vector2.ZERO
var ax_u := Vector2.RIGHT
var ax_w := Vector2(0, -1)      # toward the screen's top (away from the camera)
var u0 := 0.0
var w0 := 0.0
var cell := 2.0
var nu := 0
var nw := 0
var H := PackedFloat32Array()
var cut_w := 0.0
var _bed_mat: ShaderMaterial
var _goo: MeshInstance3D
var _goo_mat: ShaderMaterial
var _crack_mm: MultiMesh
var _loc_mm: MultiMesh
var drills: WorldDrill
var _locals: Array = []         # {tube, p, from, end, t0, dur, size, ph}
var _acc: Dictionary = {}       # tube index -> s accumulated toward the next Local
var locals_made := 0            # probes


static func enabled() -> bool:
	return Rules.world_layer and not "--no-river" in OS.get_cmdline_user_args()


func setup(w: WorldLayer, m: Node, low: bool) -> void:
	wl = w
	sim = w.sim
	main = m
	_low = low
	var lo := INF
	deck_hi = -INF
	for n in sim.nodes:
		lo = minf(lo, (n["pos"] as Vector3).y)
		deck_hi = maxf(deck_hi, (n["pos"] as Vector3).y)
	if sim.nodes.is_empty():
		lo = 0.0
		deck_hi = 0.0
	top_y = minf(lo, 0.0) - TOP_DROP
	level = top_y
	dry_y = top_y - CHANNEL_DEPTH
	var code := str((m.get("map") as Dictionary).get("code", "")) if m.get("map") is Dictionary else ""
	if code.begins_with("T-") or not sim.vls_enabled:
		drain_t = INF                                 # the tutorial: a full river (conservative reading)
	elif not Rules.last_stand:
		drain_t = Rules.VERY_LAST_STAND_TIME          # Last Stand OFF: dry at the Very Last Stand
	_sky(m)
	for e in m.find_children("*", "WorldEnvironment", true, false):
		var env := (e as WorldEnvironment).environment
		if env != null:
			env.fog_light_color = Color(0.36, 0.39, 0.38)
			env.fog_height_density = 0.004


func _sky(m: Node) -> void:
	var sc = m.get("scenery")
	var layer: CanvasLayer = sc.backdrop if sc != null and sc.get("backdrop") != null else null
	if layer == null or layer.get_child_count() == 0 or not layer.get_child(0) is TextureRect:
		return
	var sky := layer.get_child(0) as TextureRect
	var mat := ShaderMaterial.new()
	mat.shader = SKY
	var vp := m.get_viewport().get_visible_rect().size if m.is_inside_tree() else Vector2(812, 375)
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	mat.set_shader_parameter("band", SKY_BAND * 1.6)
	sky.material = mat


# ------------------------------------------------------------------ the canyon
func build(cam: Camera3D) -> void:
	## On the first frame with the fitted camera: the frame axes, the far cut, the heightfield, the meshes.
	built = true
	var fwd := -cam.global_transform.basis.z
	ax_w = Vector2(fwd.x, fwd.z)
	ax_w = ax_w.normalized() if ax_w.length() > 0.01 else Vector2(0, -1)
	ax_u = Vector2(-ax_w.y, ax_w.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var cx := Vector2.ZERO
	for n in sim.nodes:
		var p: Vector3 = n["pos"]
		cx += Vector2(p.x, p.z)
	c = cx / maxf(sim.nodes.size(), 1.0)
	var discs: Array = []
	for n in sim.nodes:
		var p: Vector3 = n["pos"]
		var q := _to_uw(Vector2(p.x, p.z))
		discs.append(q)
		lo = lo.min(q - Vector2.ONE * Rules.R)
		hi = hi.max(q + Vector2.ONE * Rules.R)
	var segs: Array = []
	for e in sim.edges:
		var a: Vector3 = sim.nodes[e["a"]]["pos"]
		var b: Vector3 = sim.nodes[e["b"]]["pos"]
		segs.append([_to_uw(Vector2(a.x, a.z)), _to_uw(Vector2(b.x, b.z))])
	# the far cut: where the ray through the screen's sky band meets the rim's height
	var rim := deck_hi + RIM_UP
	var vs := cam.get_viewport().get_visible_rect().size
	var o := cam.project_ray_origin(Vector2(vs.x * 0.5, vs.y * SKY_BAND))
	var d := cam.project_ray_normal(Vector2(vs.x * 0.5, vs.y * SKY_BAND))
	cut_w = hi.y + 60.0
	if d.y < -0.01:
		var hit := o + d * ((rim - o.y) / d.y)
		cut_w = maxf(_to_uw(Vector2(hit.x, hit.z)).y, hi.y + 4.0)
	cell = 2.5 if _low else 2.0
	u0 = lo.x - MARGIN
	w0 = lo.y - MARGIN
	nu = int(ceil((hi.x + MARGIN - u0) / cell)) + 1
	nw = int(ceil((cut_w - w0) / cell)) + 1
	var noise := FastNoiseLite.new()
	noise.seed = absi(hash(str(main.get("map_path")))) % 100000
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var long_u := (hi.x - lo.x) >= (hi.y - lo.y)
	var mid := (lo + hi) / 2.0
	var half := (hi - lo) / 2.0
	var amp := (half.y if long_u else half.x) * 0.3
	var wave := TAU / maxf((hi.x - lo.x) if long_u else (hi.y - lo.y), 20.0) * 0.9
	var ph := float(noise.seed % 628) / 100.0
	H.resize(nu * nw)
	var lowest := INF
	for j in range(nw):
		for i in range(nu):
			var q := Vector2(u0 + i * cell, w0 + j * cell)
			var dist := INF
			for dq in discs:
				dist = minf(dist, q.distance_to(dq) - Rules.R)
			for s in segs:
				dist = minf(dist, _seg_dist(q, s[0], s[1]) - 1.5)
			var n1 := noise.get_noise_2d(q.x, q.y)
			var n2 := noise.get_noise_2d(q.x * 0.5 + 300.0, q.y * 0.5 - 200.0)
			var bank := top_y - BANK_DEPTH + n1 * BANK_VAR
			var off := (q.y - (mid.y + amp * sin((q.x - mid.x) * wave + ph))) if long_u else (q.x - (mid.x + amp * sin((q.y - mid.y) * wave + ph)))
			var ch := 1.0 - smoothstep(0.0, CHANNEL_W + n2 * 2.0, absf(off))
			var bed := lerpf(bank, dry_y + absf(n2) * 0.6, ch * ch * (3.0 - 2.0 * ch))
			var near_k := smoothstep(lo.y - 10.0, hi.y, q.y)   # 0 near side .. 1 far side
			var rim_here := lerpf(minf(deck_hi + RIM_NEAR, rim), rim, near_k)
			var wf := smoothstep(0.0, WALL_RUN, dist - WALL_IN - n2 * 2.5)
			wf = maxf(wf, smoothstep(cut_w - 14.0, cut_w - 1.0, q.y) * smoothstep(1.0, 5.0, dist))
			var h := lerpf(bed, rim_here, pow(wf, 0.8))
			if wf > 0.05:                             # terraced ledges on the walls
				h = lerpf(h, roundf(h / 1.7) * 1.7, 0.35 * wf)
			H[j * nu + i] = h
			lowest = minf(lowest, h)
	dry_y = lowest
	_build_bed()
	_build_goo()
	_build_cracks()
	drills = WorldDrill.new()                         # DRILL NODE (blueprint 11-16): junction, screw bit, branches by tier
	add_child(drills)
	drills.build(self)
	_build_locals()


func _to_uw(p: Vector2) -> Vector2:
	var r := p - c
	return Vector2(r.dot(ax_u), r.dot(ax_w))


func _to_xz(q: Vector2) -> Vector2:
	return c + ax_u * q.x + ax_w * q.y


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func bed_h(x: float, z: float) -> float:
	## The canyon bed's height at world x, z (bilinear); before the canyon is built: the deepest bed.
	if not built:
		return dry_y
	var q := _to_uw(Vector2(x, z))
	var fi := clampf((q.x - u0) / cell, 0.0, nu - 1.001)
	var fj := clampf((q.y - w0) / cell, 0.0, nw - 1.001)
	var i := int(fi)
	var j := int(fj)
	var a := fi - i
	var b := fj - j
	var h00 := H[j * nu + i]
	var h10 := H[j * nu + i + 1]
	var h01 := H[(j + 1) * nu + i]
	var h11 := H[(j + 1) * nu + i + 1]
	return lerpf(lerpf(h00, h10, a), lerpf(h01, h11, a), b)


func ground(x: float, z: float) -> float:
	## Where a falling body stops: the river's surface, or the bed where it is higher.
	return maxf(level, bed_h(x, z))


func in_river(x: float, z: float) -> bool:
	return level > bed_h(x, z) + 0.05


func _build_bed() -> void:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var idx := PackedInt32Array()
	vs.resize(nu * nw)
	ns.resize(nu * nw)
	for j in range(nw):
		for i in range(nu):
			var xz := _to_xz(Vector2(u0 + i * cell, w0 + j * cell))
			vs[j * nu + i] = Vector3(xz.x, H[j * nu + i], xz.y)
	for j in range(nw):
		for i in range(nu):
			var hl := H[j * nu + maxi(i - 1, 0)]
			var hr := H[j * nu + mini(i + 1, nu - 1)]
			var hd := H[maxi(j - 1, 0) * nu + i]
			var hu := H[mini(j + 1, nw - 1) * nu + i]
			var gu := (hr - hl) / (2.0 * cell)
			var gw := (hu - hd) / (2.0 * cell)
			var g := ax_u * gu + ax_w * gw
			ns[j * nu + i] = Vector3(-g.x, 1.0, -g.y).normalized()
	for j in range(nw - 1):
		for i in range(nu - 1):
			var k := j * nu + i
			idx.append_array([k, k + nu, k + 1, k + 1, k + nu, k + nu + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_bed_mat = ShaderMaterial.new()
	_bed_mat.shader = BED
	_bed_mat.set_shader_parameter("top", top_y)
	_bed_mat.set_shader_parameter("level", level)
	var mi := MeshInstance3D.new()
	mi.name = "RiverCanyon"
	mi.mesh = am
	mi.material_override = _bed_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_goo() -> void:
	## the river: one quad over the canyon up to the far cut (the walls hide its edges)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u1 := u0 + (nu - 1) * cell
	var corners := [Vector2(u0, w0), Vector2(u1, w0), Vector2(u1, cut_w), Vector2(u0, cut_w)]
	var p: Array = []
	for q in corners:
		var xz := _to_xz(q)
		p.append(Vector3(xz.x, 0.0, xz.y))
	st.set_normal(Vector3.UP)
	for k in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(p[k])
	var am := st.commit()
	_goo_mat = ShaderMaterial.new()
	_goo_mat.shader = GOO
	var flow_dir := ax_u if absf(ax_u.x) >= 0.0 else ax_w
	_goo_mat.set_shader_parameter("dir", flow_dir)
	_goo = MeshInstance3D.new()
	_goo.name = "RiverGoo"
	_goo.mesh = am
	_goo.material_override = _goo_mat
	_goo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_goo.position.y = level
	add_child(_goo)


func _build_cracks() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = CRACK
	m.render_priority = -2
	quad.material = m
	_crack_mm = MultiMesh.new()
	_crack_mm.transform_format = MultiMesh.TRANSFORM_3D
	_crack_mm.use_custom_data = true
	_crack_mm.use_colors = true
	_crack_mm.mesh = quad
	_crack_mm.instance_count = maxi(wl._tubes.size(), 1)
	var k := 0
	for tb in wl._tubes:
		var x: float = tb["x"]
		var z: float = tb["z"]
		var h := bed_h(x, z)
		var e := 1.0
		var gx := bed_h(x + e, z) - bed_h(x - e, z)
		var gz := bed_h(x, z + e) - bed_h(x, z - e)
		var up := Vector3(-gx / (2.0 * e), 1.0, -gz / (2.0 * e)).normalized()
		var bx := Vector3.RIGHT.slide(up).normalized()
		var bz := bx.cross(up).normalized() * -1.0
		var s := CRACK_SIZE * (1.0 + float(tb["r"]) / 2.6 * 0.4)
		_crack_mm.set_instance_transform(k, Transform3D(Basis(bx * s, up, bz * s), Vector3(x, h + 0.06, z)))
		_crack_mm.set_instance_custom_data(k, Color(randf(), 0, 0, 0))
		_crack_mm.set_instance_color(k, Color.WHITE)
		tb["bot"] = h + WorldDrill.J_UP + WorldDrill.COLLAR_H * 0.5   # DRILL NODE: the skinny tube ends on the junction collar
		tb["top_y"] = 999.0                           # re-place the tube down to its crack
		k += 1
	_crack_mm.visible_instance_count = k
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _crack_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_locals() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.46, 0.47, 0.51)
	m.roughness = 0.18
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.4
	m.emission_enabled = true
	m.emission = Color(0.55, 0.63, 0.62)
	m.emission_energy_multiplier = 0.25
	_loc_mm = MultiMesh.new()
	_loc_mm.transform_format = MultiMesh.TRANSFORM_3D
	_loc_mm.mesh = WorldLocals.local_mesh()
	_loc_mm.instance_count = LOCALS_MAX
	_loc_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _loc_mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	add_child(mmi)


# ------------------------------------------------------------------ per frame
func step(dt: float) -> void:
	if not built:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null:
			return
		build(cam)
	progress = clampf(sim.time / drain_t, 0.0, 1.0) if drain_t < INF else 0.0
	level = lerpf(top_y, dry_y, progress)
	_goo.position.y = level
	_goo.visible = progress < 1.0
	_bed_mat.set_shader_parameter("level", level)
	_goo_mat.set_shader_parameter("t0", progress)
	if drills != null:
		drills.step(dt)
	_locals_step(dt)


func _vat_rate(n: Dictionary) -> float:
	## (WorldLocals.vat_rate, read only) an owned vat's production now in shown units / s; 0 at the cap / no vat / neutral
	if not Sim.has_vat(n) or sim.collapsed.get(n["id"], false) or n["owner"] == "":
		return 0.0
	if sim.garrison_total(n) >= float(Rules.CAPS[n["tier"]]) - 0.001:
		return 0.0
	return Rules.shown_f(sim._base_production(n) * float(sim._prod_info(n)[0]))


func _locals_step(dt: float) -> void:
	var t := sim.time
	var count := {}
	for L in _locals:
		count[L["tube"]] = int(count.get(L["tube"], 0)) + 1
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb["alive"] or not tb.get("shown", false) or VatColumn.upgrading(sim.nodes[tb["id"]]):
			_acc.erase(i)
			continue
		var x: float = tb["x"]
		var z: float = tb["z"]
		if not in_river(x, z) or level < bed_h(x, z) + 0.6:
			continue                                  # a dry drill foot: no Locals
		var rate := _vat_rate(sim.nodes[tb["id"]])
		if rate <= 0.0:
			continue
		var acc := float(_acc.get(i, 0.0)) + dt * minf(rate, 2.5)
		if acc >= 1.0 and int(count.get(i, 0)) < LOCALS_PER_DRILL and _locals.size() < LOCALS_MAX:
			acc -= 1.0
			_spawn(i, tb)
		_acc[i] = minf(acc, 1.5)
	var shown := 0
	var keep := []
	for L in _locals:
		var age := t - float(L["t0"])
		var tb: Dictionary = wl._tubes[L["tube"]]
		var from: Vector3 = L["from"]
		var end: Vector3 = L["end"]
		var dur: float = L["dur"]
		var p: Vector3
		var s: float = L["size"]
		var sq := 1.0
		var dir := Vector3(end.x - from.x, 0, end.z - from.z).normalized()
		if age < 0.0:
			keep.append(L)
			continue
		if age < LOCAL_EMERGE:
			var k := age / LOCAL_EMERGE
			p = Vector3(from.x, level - 0.7 * (1.0 - k), from.z)
			sq = 0.6 + 0.4 * k
		elif age < LOCAL_EMERGE + dur:
			var k := (age - LOCAL_EMERGE) / dur
			p = from.lerp(end, k)
			p.y = level + 0.04 * sin(age * 6.0 + float(L["ph"]))
			sq = 1.0 + 0.12 * sin(age * 8.0 + float(L["ph"]))
		elif age < LOCAL_EMERGE + dur + LOCAL_SQUEEZE:
			p = end
			p.y = level
			s *= 1.0 - (age - LOCAL_EMERGE - dur) / LOCAL_SQUEEZE
		else:
			continue
		if not in_river(p.x, p.z) or not tb["alive"]:
			continue                                  # the goo under it dried: it melts away
		var basis := Basis.looking_at(dir if dir.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		_loc_mm.set_instance_transform(shown, Transform3D(basis.scaled(Vector3(s / sq, s * sq, s)), p))
		shown += 1
		keep.append(L)
		if shown >= LOCALS_MAX:
			break
	_locals = keep
	_loc_mm.visible_instance_count = shown


func _spawn(i: int, tb: Dictionary) -> void:
	var x: float = tb["x"]
	var z: float = tb["z"]
	for attempt in range(4):
		var a := randf() * TAU
		var r := randf_range(LOCAL_FROM.x, LOCAL_FROM.y)
		var q := Vector3(x + cos(a) * r, level, z + sin(a) * r)
		if not in_river(q.x, q.z) or level < bed_h(q.x, q.z) + 0.4:
			continue
		var end := Vector3(x, level, z) + Vector3(cos(a), 0, sin(a)) * (float(tb["r"]) + 0.15)
		var dur := q.distance_to(end) / LOCAL_V
		_locals.append({"tube": i, "from": q, "end": end, "t0": sim.time + randf() * 0.2, "dur": dur,
				"size": randf_range(0.85, 1.1), "ph": randf() * TAU})
		locals_made += 1
		return
