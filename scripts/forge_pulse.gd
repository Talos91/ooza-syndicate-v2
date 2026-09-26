class_name ForgePulse
extends Node3D
## Forge online (0.18.7). Daniele: "when a forge is created all units and structures of that player
## should get a 2 sec animation". The moment a forge COMPLETES (or its owner gains one by capturing a node
## that has one), the forge ignites - a white-hot flare and a column of sparks - and an energy wave in the
## owner's colour mixed with a hot forge orange radiates from it across the map. Over 2.0 s it reaches
## every structure and unit of that player in turn by distance: a structure (vat, cannon, forge, relay
## node) flashes, pumps its scale and throws a ring and sparks off its platform; a unit (BRAWL creature
## bodies in UnitView, SIEGE goo patches and river rings in HordeView) glows, hops and swells. Pure view:
## the forge is read from the Sim's node state (owner + attachment, which travel in every snapshot), so
## online guests see it with no new net traffic. It never touches input. The views hook in with one
## check, `if ForgePulse.live:`, and multiply in `ForgePulse.boost(seat, pos)`, 0 when nothing plays, so
## nothing looks different outside a pulse. Visuals are made once per node and reused; the unit glows
## are one MultiMesh refilled from preallocated arrays.

signal online(seat: String, node_id: int, first: bool)   # main.gd: the toast

const FLARE_SHADER := preload("res://shaders/flare.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")

const TIME := 2.0                 # s: the whole pulse
const WAVE_TIME := 1.1            # s: the wave crosses to the farthest thing the player owns
const HIT := TIME - WAVE_TIME     # s: each structure's / unit's own flash, pump and hop
const MIN_REACH := 12.0           # m: a wave never crawls (a player with one node)
const FORGE_HOT := Color(1.0, 0.5, 0.12)
const WHITE_HOT := Color(1.0, 0.93, 0.8)
const PUMP := 0.18                # a structure's scale pump at its peak
const HOP := 0.75                 # m a unit hops at the peak
const SWELL := 0.3                # a unit's swell at the peak
const FLASH_Y := 3.4              # m above the platform: the flash over a structure
const MAX_GLOWS := 1024
const MAX_PULSES := 4

static var live := false          # a pulse is playing: the views' one check
static var _me: ForgePulse

var sim: Sim
var vis: Dictionary
var combat: Node3D                 # CombatFx: its spark MultiMesh throws the bursts (untyped: the headless tests load this without the HUD)
var _pulses: Array = []            # {seat, node, origin, t, reach, col}
var _forge_owner := {}             # node id -> the seat holding a finished forge there last frame ("" none)
var _primed := false
var _last_time := -1.0
var _cam: Camera3D
var _nodes := {}                   # node id -> {flash, fmat, ring, rmat, hit}: made on first use, reused
var _waves: Array = []             # per pulse slot: {ring, rmat, core, cmat}
var _glow_mm: MultiMesh
var _gl_pos := PackedVector3Array()
var _gl_col := PackedColorArray()
var _gl_size := PackedFloat32Array()
var _gl_n := 0
var _plane: PlaneMesh
var _quad: QuadMesh
const _BIG := AABB(Vector3(-2000, -400, -2000), Vector3(4000, 800, 4000))


func setup(s: Sim, v: Dictionary, c: Node3D) -> void:
	sim = s
	vis = v
	combat = c
	_me = self
	live = false
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1.0, 1.0)
	_quad = QuadMesh.new()
	_gl_pos.resize(MAX_GLOWS)
	_gl_col.resize(MAX_GLOWS)
	_gl_size.resize(MAX_GLOWS)
	_glow_mm = MultiMesh.new()
	_glow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_glow_mm.use_colors = true
	_glow_mm.use_custom_data = true
	_glow_mm.mesh = _quad
	_glow_mm.instance_count = MAX_GLOWS
	_glow_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _glow_mm
	var sm := ShaderMaterial.new()
	sm.shader = SPARK_SHADER
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = _BIG
	add_child(mmi)
	for i in range(MAX_PULSES):
		var ring := _flat(2)
		var edge := _flat(2)
		var core := _sprite()
		_waves.append({"ring": ring, "rmat": ring.material_override, "edge": edge, "emat": edge.material_override,
				"core": core, "cmat": core.material_override})


func _exit_tree() -> void:
	if _me == self:
		live = false
		_me = null


# ------------------------------------------------------------------ the views' hook
static func boost(seat: String, pos: Vector3, glow := 2.4) -> float:
	## 0..1: how hard the forge's wave is lifting a unit of `seat` standing at `pos` right now (0 outside
	## a pulse). With glow > 0 the unit also gets a glow sprite of that size this frame.
	if not live or _me == null:
		return 0.0
	return _me._boost(seat, pos, glow)


static func powering(seat: String) -> bool:
	## A pulse of this seat is playing (HordeView redraws the seat's river rings while it does).
	if not live or _me == null:
		return false
	for p in _me._pulses:
		if p["seat"] == seat:
			return true
	return false


func _boost(seat: String, pos: Vector3, glow: float) -> float:
	var b := 0.0
	var col := Color.WHITE
	for p in _pulses:
		if p["seat"] != seat:
			continue
		var k := _hit(p, pos)
		if k > b:
			b = k
			col = p["hot"]
	if b > 0.001 and glow > 0.0 and _gl_n < MAX_GLOWS:
		_gl_pos[_gl_n] = pos + Vector3(0, glow * 0.3, 0)
		_gl_col[_gl_n] = Color(col.r, col.g, col.b, minf(1.0, 1.3 * b))
		_gl_size[_gl_n] = glow * (0.6 + 0.6 * b)
		_gl_n += 1
	return b


static func _envelope(u: float) -> float:
	## One hit, u = 0..1 over HIT seconds: a fast rise, a slower settle.
	if u <= 0.0 or u >= 1.0:
		return 0.0
	return smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.3, 1.0, u))


func _arrival(p: Dictionary, pos: Vector3) -> float:
	## When the wave reaches pos (s into the pulse).
	var d := Vector2(pos.x - p["origin"].x, pos.z - p["origin"].z).length()
	return WAVE_TIME * minf(d / float(p["reach"]), 1.0)


func _hit(p: Dictionary, pos: Vector3) -> float:
	return _envelope((float(p["t"]) - _arrival(p, pos)) / HIT)


# ------------------------------------------------------------------ per frame (after CombatFx.sync)
func sync(dt: float, cam: Camera3D) -> void:
	_cam = cam
	_detect()
	var i := 0
	while i < _pulses.size():
		var p: Dictionary = _pulses[i]
		p["t"] += dt
		if p["t"] >= TIME:
			_pulses.remove_at(i)
			continue
		i += 1
	live = not _pulses.is_empty()
	_draw_waves()
	_draw_structures()
	_flush_glows()


func _detect() -> void:
	## A finished forge that has a new holder since last frame: built (attachment became "forge") or
	## captured (the owner changed). The first frame only learns the state (a guest's first snapshot, a
	## staged scenario), and so does a clock jump (a guest reconnecting), so nothing plays for forges that
	## were already there.
	var jumped := _last_time >= 0.0 and absf(sim.time - _last_time) > 1.0
	_last_time = sim.time
	for n in sim.nodes:
		var id: int = n["id"]
		var now: String = n["owner"] if n["attachment"] == "forge" and n["owner"] != "" \
				and not sim.collapsed.get(id, false) else ""
		var was: String = _forge_owner.get(id, "")
		if _primed and not jumped and now != "" and now != was:
			var first := true
			for other in _forge_owner:
				if other != id and _forge_owner[other] == now:
					first = false
			_start(now, n, first)
		_forge_owner[id] = now
	_primed = true


func _start(seat: String, n: Dictionary, first: bool) -> void:
	if _pulses.size() >= MAX_PULSES:
		_pulses.pop_front()
	var origin: Vector3 = n["pos"]
	var reach := MIN_REACH
	for m in sim.nodes:                               # the farthest thing the player owns sets the wave's pace
		if m["owner"] == seat and not sim.collapsed.get(m["id"], false):
			reach = maxf(reach, Vector2(m["pos"].x - origin.x, m["pos"].z - origin.z).length())
	for h in sim.hordes:
		if h["owner"] == seat:
			var hp: Vector3 = Sim.sample(h, h["s"])[0]
			reach = maxf(reach, Vector2(hp.x - origin.x, hp.z - origin.z).length())
	var col := Rules.seat_color(seat)
	_pulses.append({"seat": seat, "node": n["id"], "origin": origin, "t": 0.0, "reach": reach, "col": col,
			"hot": col.lerp(FORGE_HOT, 0.6)})
	live = true
	# the forge ignites: a column of white-hot and forge-orange sparks off its top
	if combat:
		var top := origin + Vector3(0, 5.0, 0)
		for i in range(40 if not Rules.low_detail else 20):
			var a := randf() * TAU
			var v := Vector3(cos(a) * randf_range(0.2, 1.0), randf_range(1.6, 3.2), sin(a) * randf_range(0.2, 1.0)).normalized()
			var roll := randf()
			var c: Color = WHITE_HOT if roll < 0.35 else (FORGE_HOT if roll < 0.75 else Rules.seat_color(seat))
			combat._spark(top + Vector3(randf_range(-0.8, 0.8), randf_range(-1.5, 0.5), randf_range(-0.8, 0.8)),
					v * randf_range(7.0, 15.0), c * 1.4, randf_range(0.16, 0.34), randf_range(0.5, 1.0), 14.0)
	online.emit(seat, n["id"], first)


func _draw_waves() -> void:
	for i in range(MAX_PULSES):
		var w: Dictionary = _waves[i]
		var ring: MeshInstance3D = w["ring"]
		var edge: MeshInstance3D = w["edge"]
		var core: MeshInstance3D = w["core"]
		if i >= _pulses.size():
			ring.visible = false
			edge.visible = false
			core.visible = false
			continue
		var p: Dictionary = _pulses[i]
		var t: float = p["t"]
		var col: Color = p["col"]
		var origin: Vector3 = p["origin"]
		# the shock wave on the ground (the band sits at r 0.82 of the plane's half size): a thin white-hot
		# forge edge at the front, the owner's colour in a wider band just behind it
		var k := clampf(t / WAVE_TIME, 0.0, 1.0)
		var r: float = maxf(float(p["reach"]) * k, 1.0)
		var fade := 1.0 - smoothstep(WAVE_TIME * 0.7, WAVE_TIME + 0.15, t)   # gone before it runs past the map
		var size := r * 2.0 / 0.82
		edge.visible = fade > 0.0
		edge.position = origin + Vector3(0, 0.6, 0)
		edge.scale = Vector3(size, 1.0, size)
		var emat: ShaderMaterial = w["emat"]
		emat.set_shader_parameter("thickness", clampf(0.6 / (size * 0.5), 0.01, 0.2))
		emat.set_shader_parameter("color", FORGE_HOT)
		emat.set_shader_parameter("intensity", 1.2 * fade)
		var rsize := maxf(r - 1.6, 0.5) * 2.0 / 0.82
		ring.visible = fade > 0.0
		ring.position = origin + Vector3(0, 0.55, 0)
		ring.scale = Vector3(rsize, 1.0, rsize)
		var rmat: ShaderMaterial = w["rmat"]
		rmat.set_shader_parameter("thickness", clampf(1.5 / (rsize * 0.5), 0.015, 0.25))
		rmat.set_shader_parameter("color", col)
		rmat.set_shader_parameter("intensity", 0.75 * fade * (1.0 - 0.3 * k))
		# the ignition flare over the forge
		var ig := 1.0 - smoothstep(0.0, 0.7, t)
		core.visible = ig > 0.0
		var up := origin + Vector3(0, 4.5, 0)
		core.position = up + _to_cam(up) * 2.5
		core.scale = Vector3.ONE * (9.0 + 10.0 * (1.0 - ig))
		var cmat: ShaderMaterial = w["cmat"]
		cmat.set_shader_parameter("color", FORGE_HOT.lerp(col, 0.35))
		cmat.set_shader_parameter("intensity", 1.6 * ig)
		cmat.set_shader_parameter("spin", t * 1.5)


func _draw_structures() -> void:
	## Every node of a pulsing seat: flash, ring and sparks as the wave reaches it, the centre model pumps.
	for n in sim.nodes:
		var id: int = n["id"]
		var b := 0.0
		var u := -1.0
		var col := Color.WHITE
		if live and n["owner"] != "" and not sim.collapsed.get(id, false):
			for p in _pulses:
				if p["seat"] != n["owner"]:
					continue
				var pu := (float(p["t"]) - _arrival(p, n["pos"])) / HIT
				var pb := _envelope(pu)
				if pb > b or (u < 0.0 and pu >= 0.0 and pu < 1.0):
					b = pb
					u = pu
					col = p["col"]
		if u < 0.0 or u >= 1.0:
			if _nodes.has(id):
				var v0: Dictionary = _nodes[id]
				(v0["flash"] as Node3D).visible = false
				(v0["ring"] as Node3D).visible = false
				v0["hit"] = false
			continue
		var v := _node_fx(id)
		var entry: Dictionary = vis.get(id, {})
		var centre: Vector3 = entry.get("centre", n["pos"])
		if not v["hit"]:                              # the wave arrives: sparks off the structure's top
			v["hit"] = true
			if combat:
				var top := centre + Vector3(0, FLASH_Y + 0.5, 0)
				for i in range(14 if not Rules.low_detail else 7):
					var a := randf() * TAU
					var dv := Vector3(cos(a), randf_range(0.8, 2.0), sin(a)).normalized()
					combat._spark(top + Vector3(randf_range(-1, 1), randf_range(-1.5, 0.3), randf_range(-1, 1)),
							dv * randf_range(4.0, 9.0), (WHITE_HOT if randf() < 0.3 else (FORGE_HOT if randf() < 0.5 else col)) * 1.3,
							randf_range(0.14, 0.28), randf_range(0.35, 0.7), 14.0)
		# the centre model (vat / cannon / forge / socket) pumps: up fast, a small undershoot, settled by
		# the end. Fx._construction and the tier-down set its scale first each frame; this multiplies in.
		var model: Node3D = entry.get("vat_node")
		if is_instance_valid(model):
			var pump := sin(PI * clampf(u / 0.45, 0.0, 1.0)) - 0.3 * sin(PI * clampf((u - 0.45) / 0.35, 0.0, 1.0))
			model.scale *= 1.0 + PUMP * pump
		var flash: MeshInstance3D = v["flash"]
		flash.visible = b > 0.001
		var fp := centre + Vector3(0, FLASH_Y, 0)
		flash.position = fp + _to_cam(fp) * 3.0           # in front of the model, or the model hides it
		flash.scale = Vector3.ONE * (4.0 + 3.5 * b)
		var fmat: ShaderMaterial = v["fmat"]
		fmat.set_shader_parameter("color", FORGE_HOT.lerp(col, 0.3))
		fmat.set_shader_parameter("intensity", 1.0 * b)
		fmat.set_shader_parameter("spin", u * 2.0 + float(id))
		var ring: MeshInstance3D = v["ring"]          # a ring runs off the platform's rim
		var rk := clampf(u / 0.7, 0.0, 1.0)
		ring.visible = rk < 1.0
		ring.position = (n["pos"] as Vector3) + Vector3(0, 0.6, 0)
		var rs := lerpf(Rules.R * 1.4, Rules.R * 3.0, sqrt(rk))
		ring.scale = Vector3(rs, 1.0, rs)
		var rmat: ShaderMaterial = v["rmat"]
		rmat.set_shader_parameter("color", col)
		rmat.set_shader_parameter("intensity", 1.1 * (1.0 - rk) * smoothstep(0.0, 0.08, u))


func _node_fx(id: int) -> Dictionary:
	if not _nodes.has(id):
		var flash := _sprite()
		var ring := _flat(2)
		(ring.material_override as ShaderMaterial).set_shader_parameter("thickness", 0.06)
		_nodes[id] = {"flash": flash, "fmat": flash.material_override, "ring": ring, "rmat": ring.material_override, "hit": false}
	return _nodes[id]


func _flush_glows() -> void:
	## The unit glows the views asked for this frame (they run before this).
	if _gl_n == 0 and _glow_mm.visible_instance_count == 0:
		return
	for i in range(_gl_n):
		_glow_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _gl_pos[i]))
		_glow_mm.set_instance_color(i, _gl_col[i])
		_glow_mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, _gl_size[i]))
	_glow_mm.visible_instance_count = _gl_n
	_gl_n = 0


# ------------------------------------------------------------------ pieces
func _to_cam(p: Vector3) -> Vector3:
	if _cam == null:
		return Vector3.UP
	return (_cam.global_position - p).normalized()


func _sprite() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := ShaderMaterial.new()
	m.shader = FLARE_SHADER
	m.set_shader_parameter("mode", 0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _flat(mode: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _plane
	var m := ShaderMaterial.new()
	m.shader = FLARE_SHADER
	m.set_shader_parameter("mode", mode)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi
