class_name FogLead
extends Node
## FOG LEAD (Daniele, 2026-11-07: "the more a player is winning the more the fog switches from default to his player
## colour (specifically not race colour), but gradually, as a kind of live indicator"). Visual only: it reads the sim's
## node owners (replicated state online, the local sim solo) and tints every part of the arena's air one colour - the
## WorldEnvironment height fog, the backdrop's haze, the void / floor mist sheets, the floor's (and its decals') far haze.
##   lead = top seat's share of the board's nodes - the second's;  t = smoothstep(LEAD_LO, LEAD_HI, lead)
##   air  = lerp(default, Rules.seat_color(leader), t * MAX_TINT) in linear colour, eased over ~2-3 s
## With no lead the air is exactly today's default. Dev: --fog-lead=<seat>:<lead 0..1> forces a leader and a lead (no
## easing), for screenshots.

const LEAD_LO := 0.10            # below this lead the air stays default
const LEAD_HI := 0.50            # the full tint from this lead on
const MAX_TINT := 0.35           # at most 35 % of the leader's colour
const TAU := 0.8                 # s: ease time constant (~2.4 s to 95 %), frame-rate independent
const MEASURE_EVERY := 0.25      # s between lead measures

var sim: Sim
var main: Node
var _targets: Array = []         # [object, param, base (linear), scale, default as set]: env fog, backdrop, mists, floor, decals
var _collected := false
var _counts: Dictionary = {}     # reused per measure
var _measure_t := 0.0
var _goal_amt := 0.0             # t * MAX_TINT the lead asks for
var _goal_col := Color.BLACK     # the leader's colour (linear)
var _amt := 0.0                  # eased
var _col := Color.BLACK          # eased (linear)
var _applied := -1.0
var _force_seat := ""
var _force_lead := -1.0


func setup(m: Node, s: Sim) -> void:
	main = m
	sim = s
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fog-lead="):
			var kv := a.substr(11).split(":")
			if kv.size() == 2:
				_force_seat = kv[0]
				_force_lead = clampf(float(kv[1]), 0.0, 1.0)


static func tint_for(lead: float) -> float:
	return smoothstep(LEAD_LO, LEAD_HI, lead) * MAX_TINT


func _collect() -> void:
	## after the world is built (the world dressing swaps the floor and backdrop materials at setup)
	_collected = true
	_targets.clear()
	for c in main.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			var env := (c as WorldEnvironment).environment
			_targets.append([env, &"fog_light_color", env.fog_light_color.srgb_to_linear(), 1.0, env.fog_light_color])
	var sc = main.get("scenery")
	if sc != null:
		var layer: CanvasLayer = sc.backdrop
		if layer != null and layer.get_child_count() > 0 and layer.get_child(0) is TextureRect:
			_add_mat((layer.get_child(0) as TextureRect).material, &"fog_col", 1.0)   # the backdrop FOG layer takes the leader colour; the clouds stay (Daniele 2026-11-11)
		for c in (sc as Node).get_children():
			if c is MeshInstance3D:
				_add_mist((c as MeshInstance3D).material_override)
	var wl: WorldLayer = main.get("world_layer")
	if wl != null:
		if wl.center_fog_mat != null:
			_add_mat(wl.center_fog_mat, &"fog_col", 1.0)
		for c in wl.get_children():
			if c is MeshInstance3D:
				_add_mist((c as MeshInstance3D).material_override)
		var far := 1.0 / 0.6 if wl.floor_lab5 else 1.0   # the lab floor's far haze is abyss x 0.6 (= the backdrop's middle)
		if wl._floor != null:
			_add_mat(wl._floor.material_override, &"abyss", far)
		if wl.decals != null and wl.decals._mm != null and wl.decals._mm.mesh is PrimitiveMesh:
			_add_mat((wl.decals._mm.mesh as PrimitiveMesh).material, &"abyss", far)


func _add_mist(m: Material) -> void:
	if m is ShaderMaterial and (m as ShaderMaterial).shader == Scenery.VOID_SHADER:
		_add_mat(m, &"mist_color", 1.0)


func _add_mat(m: Material, param: StringName, scale: float) -> void:
	if not (m is ShaderMaterial):
		return
	var v = (m as ShaderMaterial).get_shader_parameter(param)
	if v is Color:
		_targets.append([m, param, (v as Color).srgb_to_linear(), scale, v])
	elif v is Vector3:
		_targets.append([m, param, Color(v.x, v.y, v.z).srgb_to_linear(), scale, v])


func _measure() -> void:
	if _force_lead >= 0.0:
		_goal_col = Rules.seat_color(_force_seat).srgb_to_linear()
		_goal_amt = tint_for(_force_lead)
		return
	_counts.clear()
	var total := 0
	for n in sim.nodes:
		if str(n.get("junction", "")) != "":
			continue
		total += 1
		var o: String = n["owner"]
		if o != "":
			_counts[o] = int(_counts.get(o, 0)) + 1
	var top := 0
	var second := 0
	var leader := ""
	for seat in _counts:
		var c: int = _counts[seat]
		if c > top:
			second = top
			top = c
			leader = seat
		elif c > second:
			second = c
	if total == 0 or leader == "":
		_goal_amt = 0.0
		return
	var lead := float(top - second) / float(total)
	_goal_amt = tint_for(lead)
	if _goal_amt > 0.0:
		_goal_col = Rules.seat_color(leader).srgb_to_linear()


func _process(delta: float) -> void:
	if sim == null or main == null:
		return
	if not _collected:
		_collect()
	_measure_t -= delta
	if _measure_t <= 0.0:
		_measure_t = MEASURE_EVERY
		var first := _applied < 0.0
		_measure()
		if first or _force_lead >= 0.0:            # start (and forced shots) at the value, no ease-in
			_amt = _goal_amt
			_col = _goal_col
	var k := 1.0 - exp(-delta / TAU)
	if _amt < 0.001 and _goal_amt > 0.0:          # rising from default: take the leader's colour at once
		_col = _goal_col
	_amt += (_goal_amt - _amt) * k
	if _goal_amt > 0.0:
		_col = _col.lerp(_goal_col, k)
	if absf(_amt - _applied) < 0.0005 and _applied >= 0.0 and (_goal_amt <= 0.0 or _col.is_equal_approx(_goal_col)):
		return
	_applied = _amt
	var plain := _amt < 0.0005                     # no lead: exactly the default values, untouched by colour maths
	for tg in _targets:
		var obj: Object = tg[0]
		if plain:
			if obj is ShaderMaterial:
				(obj as ShaderMaterial).set_shader_parameter(tg[1], tg[4])
			else:
				obj.set(tg[1], tg[4])
			continue
		var base: Color = tg[2]
		var s: float = tg[3]
		var c := Color(base.r + (_col.r * s - base.r) * _amt, base.g + (_col.g * s - base.g) * _amt,
				base.b + (_col.b * s - base.b) * _amt, base.a).linear_to_srgb()
		if obj is ShaderMaterial:
			(obj as ShaderMaterial).set_shader_parameter(tg[1], c)
		else:
			obj.set(tg[1], c)
