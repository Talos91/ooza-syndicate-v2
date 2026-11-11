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
# FOG MIX (Daniele 2026-11-11): the backdrop / centre FOG layer's colour = the share of nodes nobody owns in GRAY plus each
# seat's share in its colour (linear mix), so it starts gray and drifts toward whoever holds the nodes. The clouds never change.
const FOG_GRAY := Color(0.22, 0.23, 0.26)
const FOG_SEAT_DIM := 0.6        # the seat colours are dimmed so a full-colour haze stays a haze
var _fog_mats: Array = []
var fog_force: Dictionary = {}   # playground / probes: {seat: share 0..1} replaces the real node counts (the rest is gray)
const FOG_PATCH_SAT := 0.5       # how much of a faction's own colour its fog patches carry (1 = full colour, 0 = neutral fog)
var _fog_goal := Color.BLACK     # linear
var _fog_goal_b := Color.BLACK   # the second faction's fog colour (Daniele 2026-11-11: 50 / 50 = half cyan fog, half red fog, never gray)
var _fog_cur_b := Color.BLACK
var _fog_split_goal := 1.0
var _fog_split := 1.0
var _fog_split_applied := -1.0
var _fog_cur := Color.BLACK
var _fog_applied := Color(-1, -1, -1)
var _fog_started := false
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
			_fog_mats.append((layer.get_child(0) as TextureRect).material)   # the FOG layer follows the node mix (_fog_step); the clouds stay
		for c in (sc as Node).get_children():
			if c is MeshInstance3D:
				_add_mist((c as MeshInstance3D).material_override)
	var wl: WorldLayer = main.get("world_layer")
	if wl != null:
		if wl.center_fog_mat != null:
			_fog_mats.append(wl.center_fog_mat)
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


func _measure_fog() -> void:
	var total := 0
	var counts := {}
	if not fog_force.is_empty():
		total = 1000
		for seat in fog_force:
			counts[seat] = int(float(fog_force[seat]) * 1000.0)
	else:
		for n in sim.nodes:
			if str(n.get("junction", "")) != "":
				continue
			total += 1
			var o: String = n["owner"]
			if o != "":
				counts[o] = int(counts.get(o, 0)) + 1
	if total == 0:
		return
	var owned := 0
	var seats: Array = counts.keys()
	seats.sort()
	for seat in seats:
		owned += int(counts[seat])
	var wg := float(total - owned) / float(total)      # gray is only the NEUTRAL share: no neutral nodes, no gray
	var g := FOG_GRAY.srgb_to_linear()
	var mix := g
	if owned > 0:
		# a COLOUR mix (Daniele 2026-11-11): the factions' hues are blended round the colour wheel, not averaged in RGB (cyan + red
		# averaged is gray). Hues far apart meet through GREEN, so 50 / 50 cyan and red reads as a green; near hues take the short way.
		var h := 0.0
		var sat := 0.0
		var val := 0.0
		var wsum := 0.0
		for seat in seats:
			var c := Rules.seat_color(seat)
			var w := float(counts[seat]) / float(owned)
			if wsum == 0.0:
				h = c.h
			else:
				var t := w / (wsum + w)
				var d := c.h - h                            # along the wheel, 0 .. 1
				if absf(d) > 0.25:                          # far apart: the way that passes green (hue 1/3)
					var lo := minf(h, c.h)
					var hi := maxf(h, c.h)
					if not (lo <= 1.0 / 3.0 and 1.0 / 3.0 <= hi):
						d = d - signf(d)                    # green is on the other arc: go round through 0
				h = fposmod(h + d * t, 1.0)
			sat += c.s * w
			val += c.v * w
			wsum += w
		mix = Color.from_hsv(h, sat, val).srgb_to_linear() * FOG_SEAT_DIM
	_fog_goal = Color(lerpf(mix.r, g.r, wg), lerpf(mix.g, g.g, wg), lerpf(mix.b, g.b, wg), 1.0)
	_fog_goal_b = _fog_goal
	_fog_split_goal = 1.0


func _fog_step(delta: float, snap: bool) -> void:
	if _fog_mats.is_empty():
		return
	if snap:
		_fog_cur = _fog_goal
		_fog_cur_b = _fog_goal_b
		_fog_split = _fog_split_goal
	else:
		var kf := 1.0 - exp(-delta / TAU)
		_fog_cur = _fog_cur.lerp(_fog_goal, kf)
		_fog_cur_b = _fog_cur_b.lerp(_fog_goal_b, kf)
		_fog_split = lerpf(_fog_split, _fog_split_goal, kf)
	if _fog_cur.is_equal_approx(_fog_applied) and is_equal_approx(_fog_split, _fog_split_applied):
		return
	_fog_applied = _fog_cur
	_fog_split_applied = _fog_split
	var c := _fog_cur.linear_to_srgb()
	var cb := _fog_cur_b.linear_to_srgb()
	for m in _fog_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter(&"fog_col", c)
			(m as ShaderMaterial).set_shader_parameter(&"fog_col_b", cb)
			(m as ShaderMaterial).set_shader_parameter(&"fog_split", _fog_split)


func _measure() -> void:
	_measure_fog()
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
	var first_fog := not _fog_started
	_measure_t -= delta
	if _measure_t <= 0.0:
		_measure_t = MEASURE_EVERY
		_fog_started = true
		var first := _applied < 0.0
		_measure()
		if first or _force_lead >= 0.0:            # start (and forced shots) at the value, no ease-in
			_amt = _goal_amt
			_col = _goal_col
	_fog_step(delta, first_fog)
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
