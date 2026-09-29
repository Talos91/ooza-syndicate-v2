class_name Warmup
extends Node3D
## First-use hitches (match-feel pass, Daniele's phone test 2026-09-28: "when in game first interaction with tower lags
## only on first time you send and first time you enter a tower"). The GL Compatibility renderer compiles a shader the
## first frame something with it is drawn: a line's first bodies (the creature shader, instanced), the fight ring, the
## flares and sparks at the door, the floaters' outlined font, a Last Stand ring, a skill's shaders... each one a stall
## of 50-150 ms on a desktop GPU and more on a phone, just when the player acts. Warmup draws one of each, tiny (a
## millimetre, 12 m in front of the camera: well under a pixel), for Rules.WARMUP_FRAMES frames at match start -
## behind the VERSUS card, which holds the match paused - then frees itself. The creature bodies and their discs go
## through the real UnitView (every seat's faction and colour, the exact materials a line will use); the rest are the
## effects' own materials (Mats, CombatFx / SkillFx / Fx shaders) on stand-in meshes of the same kind (instanced or
## not), and Label3Ds with the floaters' / route label's font settings and the characters they print.
## main._start_map adds it once the world is built (one marked line); the room server and headless runs never do.

const AHEAD := 12.0                        # m in front of the camera
const TINY := 0.001                        # scale: far below a pixel at that distance
const CHARS := "+-0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ·▼!→%"   # what the in-world labels print (captures, routes, tier-downs)

var main: Node3D
var _left := 0
var _pieces: Array[Node3D] = []
var staged := false                        # STAGED LOAD (0.23.4, an online round under the VERSUS card): the pieces go in a few per frame
var _queue: Array[Node3D] = []             # STAGED LOAD: pieces made, not yet drawn
var _batch := 1                            # STAGED LOAD: pieces added per frame (adapts to Rules.STAGED_LOAD_FRAME_MS)
var _last_us := 0


static func run(m: Node3D, stage := false) -> void:
	## main._start_map, after the world and the HUD are built. stage: an online round's staged load - the pieces are drawn
	## a few per frame (each frame compiles only its own new shaders), then held Rules.WARMUP_FRAMES frames as usual.
	if DisplayServer.get_name() == "headless" or m.get("hordes") == null:
		return
	var w := Warmup.new()
	w.name = "Warmup"
	w.main = m
	w.staged = stage
	w._batch = Rules.STAGED_LOAD_FIRST_GROUPS
	m.add_child(w)


var _jobs: Array[Callable] = []           # STAGED LOAD: the making still to do (a model load, the effects' pieces), a job a frame


func _ready() -> void:
	_left = Rules.WARMUP_FRAMES
	var sim: Sim = main.get("sim")
	_jobs = _loads(sim)
	_jobs.append(_effects.bind(sim))
	if staged:
		return
	for j in _jobs:
		j.call()
	_jobs.clear()


func _effects(sim: Sim) -> void:
	## The effects' materials and shaders on stand-in meshes, the instanced ones, the in-world labels' fonts.
	var quad := QuadMesh.new()
	var mats: Array[Material] = [Mats.glow(Color.WHITE, 0.9), Mats.glow(Color.WHITE, 1.0), Mats.construction(), Mats.seam()]
	for seat in sim.factions.keys():
		mats.append(Mats.goo(seat))
		mats.append(Mats.light(seat))
	for sh in [CombatFx.RING_SHADER, CombatFx.ALARM_SHADER, CombatFx.FLARE_SHADER, CombatFx.BEAM_SHADER,
			SkillFx.FX_SHADER, SkillFx.SLUDGE_SHADER]:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if sh == CombatFx.BEAM_SHADER:                    # the beam is placed in its shader (p0 / p1): drawn at nothing
			sm.set_shader_parameter("power", 0.0)
			sm.set_shader_parameter("width", 0.0)
		mats.append(sm)
	for m in mats:                                        # plain meshes (rings, pulses, flares, beams, skill parts)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(mi)
	var faded := MeshInstance3D.new()                    # a pulse fading out (GeometryInstance transparency: the alpha pass)
	faded.mesh = quad
	faded.material_override = Mats.glow(Color.WHITE, 0.9)
	faded.transparency = 0.5
	_add(faded)
	for m in [Mats.goo(str(sim.factions.keys()[0])) as Material, _spark_material(), _ghost_material()]:   # instanced ones
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(0, 0, 0, TINY))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		_add(mmi)
	for spec in [[72, 16], [72, 18], [48, 10], [64, 14]]:   # Fx.floater, the route label, tier-down / skill labels
		var l := Label3D.new()
		l.font = Hud.UI_FONT
		l.font_size = spec[0]
		l.outline_size = spec[1]
		l.text = CHARS
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 3
		l.outline_render_priority = 2
		l.pixel_size = 0.00002
		_add(l)


func _loads(sim: Sim) -> Array[Callable]:
	## What the views load the first time it is needed, measured as the first send's stall (76 ms of script on a
	## desktop, 2026-09-28 probe: HordeView.load_faction reading assets/horde/patches_<faction>.glb on a line's first
	## frame): every seat's faction patches, and the centre models a capture's tier-down, an upgrade or a build swaps in
	## (MapBuilder's scene cache) with their vat-tank measurements (Scenery.tank_info, cached per model), one tiny copy
	## of each drawn with the rest.
	## Returned as jobs (a model each), run at once or - staged - one per frame.
	var jobs: Array[Callable] = []
	var hv: HordeView = main.get("hordes")
	var seats: Array = [""]
	for seat in sim.factions.keys():
		seats.append(seat)
		if hv != null:
			jobs.append(hv.load_faction.bind(str(sim.factions[seat])))
	var keys := {}
	for seat in seats:
		for spec in [["vat", 1], ["vat", 2], ["vat", 3], ["machinegoon", 1], ["laser", 1], ["forge", 1], ["monster_hub", 1]]:
			var key := Cosmetics.key_for(str(spec[0]), str(seat), int(spec[1]))
			if key != "" and not key.begins_with("skins/"):   # (a skin is Cosmetics' own threaded load)
				keys[key] = str(seat)
	for frag in ["girder_l", "girder_r", "plate_a", "plate_b", "plate_c", "truss"]:   # Fx._collapse's fall pieces
		keys["Deck_S_Frag_" + frag] = ""
	for key in keys:
		jobs.append(_piece.bind(str(key), str(keys[key])))
	return jobs


func _piece(key: String, seat: String) -> void:
	var node := MapBuilder.piece(key)
	MapBuilder.apply_owner([node], seat)
	for mi in node.find_children("*", "MeshInstance3D", true, false):   # as Scenery._bind measures a new vat
		var info := Scenery.tank_info((mi as MeshInstance3D).mesh, key)
		if info["surface"] >= 0 and not (info["tanks"] as Array).is_empty():
			var mat := ShaderMaterial.new()
			mat.shader = Scenery.LIQUID_SHADER
			(mi as MeshInstance3D).set_surface_override_material(info["surface"], mat)
			break
	_add(node)


func _add(n: Node3D) -> void:
	n.scale = Vector3.ONE * TINY
	if staged:
		_queue.append(n)
		return
	add_child(n)
	_pieces.append(n)


func _exit_tree() -> void:
	for n in _queue:                                      # (freed before every piece went in: the rest go too)
		if is_instance_valid(n):
			n.free()
	_queue.clear()


func _spark_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = CombatFx.SPARK_SHADER
	return sm


func _ghost_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SkillFx.ghost_shader()
	return sm


func _process(_dt: float) -> void:
	## After main._process (a child runs after its parent): the camera is placed and the lines drawn for this frame.
	var cam: Camera3D = main.get("cam")
	if cam == null:
		return
	var spot: Vector3 = cam.global_position - cam.global_transform.basis.z * AHEAD
	position = spot
	_units(spot)
	if not _jobs.is_empty() or not _queue.is_empty():     # STAGED LOAD: the next job, the next few pieces, paced by the last frame
		var now := Time.get_ticks_usec()
		if _last_us > 0:
			var ms := (now - _last_us) / 1000.0
			if ms > Rules.STAGED_LOAD_FRAME_MS:
				_batch = maxi(1, _batch / 2)
			elif ms < Rules.STAGED_LOAD_FRAME_MS / 3.0:
				_batch *= 2
		_last_us = now
		var t0 := Time.get_ticks_usec()                   # jobs: as many as fit a third of the frame budget (at least one)
		while not _jobs.is_empty():
			_jobs.pop_front().call()
			if (Time.get_ticks_usec() - t0) / 1000.0 > Rules.STAGED_LOAD_FRAME_MS / 3.0:
				break
		for i in range(mini(_batch, _queue.size())):
			var n: Node3D = _queue.pop_front()
			add_child(n)
			_pieces.append(n)
		if main.get("load_progress") != null and float(main.get("load_progress")) >= 0.0:
			main.set("load_progress", lerpf(float(main.get("load_progress")), 0.99, 0.25))
		return
	_left -= 1
	if _left < 0:
		if main.has_method("_lm"):
			main.call("_lm", "warmup_done")
		queue_free()


func _units(spot: Vector3) -> void:
	## Every seat's creature column and disc through the real UnitView: one body each, tiny, on top of whatever this
	## frame's lines drew (the next frame's HordeView.sync rewrites them all).
	var hv: HordeView = main.get("hordes")
	var uv: UnitView = hv.units if hv != null else null
	if uv == null:
		return
	var sim: Sim = main.get("sim")
	for seat in sim.factions.keys():
		var f := str(sim.factions[seat])
		if not uv._mesh.has(f):
			continue
		var mmi: MultiMeshInstance3D = uv._instance(f, seat)
		var mm := mmi.multimesh
		if mm.visible_instance_count == 0:
			mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * TINY), spot))
			mm.visible_instance_count = 1
	var dm: MultiMesh = uv._disc.multimesh
	if dm.visible_instance_count == 0:
		dm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * TINY), spot))
		dm.set_instance_color(0, Color.WHITE)
		dm.visible_instance_count = 1
