class_name Fx
extends Node3D
## In-world animation and effects: construction (the new structure grows out of the socket under a
## turning build ring), capture pulses, relay warnings (blinking state lights + a ghost
## of the next deck), relay motion (rotation pivots the turntable and its decks, retract slides the
## deck into its gate, switch/remote dissolve and assemble), the Last Stand warning ring and the falls
## (platform, deck fragments, waterfall of goo, hordes tumbling into the void, lines flung off a
## turning rotation deck), the selection ring,
## owner-coloured deck lights (SIEGE) and Alpha 11's half-bridge neon trims (BRAWL), pier stripes and
## platform rims. The cannon laser, fights for a tower and tier-downs are combat_fx.gd.

var sim: Sim
var vis: Dictionary
var hordes: HordeView
var world: Node3D
var selected := -1
var _sel_ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _thin_ring: TorusMesh
var _build_rings := {}      # node id -> MeshInstance3D
var _warn_rings := {}       # node id -> MeshInstance3D (Last Stand)
var _cool_arcs := {}        # node id -> MeshInstance3D (relay cooldown / warning)
var _arc_built := {}        # node id -> [frac, colour] the arc was last built with
var _ghosts := {}           # edge -> [Node3D]
var _plat_angle := {}       # node id -> accumulated turntable angle
var _edge_light := {}       # edge -> owner key currently applied
var _state_color := {}      # node id -> state key applied
var _collapsed := {}
var _lights_classic := false  # the mode the deck lights were last laid out for (true = BRAWL)
var _pulses: Array = []     # transient rings: {mesh, t, dur, color}
var _frag_names := ["girder_l", "girder_r", "plate_a", "plate_b", "plate_c", "truss"]
var _body := {}             # faction -> [Mesh, scale to UnitView.UNIT_SIZE, albedo Texture2D]: BRAWL fling bodies
var _body_mat := {}         # "faction|seat" -> Material (UnitView's creature look)
var _fall_debt := {}        # seat -> shown units lost to BRAWL falls not yet drawn as a body


func setup(w: Node3D, s: Sim, v: Dictionary, hv: HordeView) -> void:
	world = w
	sim = s
	vis = v
	hordes = hv
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.82
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 56                                 # segments along the ring
	_ring_mesh.ring_segments = 6                          # segments around the tube
	_thin_ring = TorusMesh.new()
	_thin_ring.inner_radius = 0.93
	_thin_ring.outer_radius = 1.0
	_thin_ring.rings = 48
	_thin_ring.ring_segments = 4
	_sel_ring = MeshInstance3D.new()
	_sel_ring.mesh = _thin_ring
	_sel_ring.scale = Vector3.ONE * (Rules.R + 0.5)
	_sel_ring.visible = false
	add_child(_sel_ring)
	for i in sim.edge_controller:                        # ghost decks: the NEXT state's preview
		var arr := []
		var e: Dictionary = sim.edges[i]
		var col := Rules.state_color("retract" if e["retracts"] else e["state"])
		for deck in vis["edge_decks"][i]:
			var g: Node3D = (deck as Node3D).duplicate()
			world.add_child(g)
			g.transform = deck.transform
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = Mats.ghost(col)
			g.visible = false
			arr.append(g)
		_ghosts[i] = arr


# ------------------------------------------------------------------ events
func handle(ev: Dictionary) -> void:
	match ev["type"]:
		"capture":
			_pulse(sim.nodes[ev["node"]]["pos"], Rules.seat_color(ev["seat"]), Rules.R + 1.0, 1.0)
		"build_done":
			var n: Dictionary = sim.nodes[ev["node"]]
			_pulse(n["pos"], Rules.state_color("build"), 4.0, 0.6)
		"relay_done":
			var n: Dictionary = sim.nodes[ev["node"]]
			if n["relay"] == "rotation":
				_plat_angle[n["id"]] = _plat_angle.get(n["id"], 0.0) + n["relay_anim"].get("delta", 0.0)
			_restore_edges(n)
		"fall":
			_fall_horde(ev)
		"fling":
			_fling_horde(ev)
		"collapse":
			_collapse(ev["node"], str(ev.get("from", "")))


func _pulse(pos: Vector3, color: Color, radius: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _thin_ring
	mi.material_override = Mats.glow(color, 0.9)
	mi.position = pos + Vector3(0, 0.3, 0)
	mi.scale = Vector3.ONE * radius * 0.4
	add_child(mi)
	_pulses.append({"mesh": mi, "t": 0.0, "dur": dur, "r": radius})


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	if not _neon_built:
		_build_neon()
	var classic := not Rules.bridge_combat
	if classic != _lights_classic:                    # SIEGE/BRAWL switched (pause menu, Debug panel)
		_lights_classic = classic
		_edge_light.clear()                           # SIEGE: _decks re-applies owner/state lights
		_pier_key.clear()                             # _neon re-colours the pier stripes and rims
		_rim_key.clear()
		if classic:
			for i in _trims:
				for d in vis["edge_decks"][i]:
					MapBuilder.set_lights(d, Mats.light_color(TRIM_OFF, "trim_off"))
			for i in vis["edge_piers"]:
				for p in vis["edge_piers"][i]:
					MapBuilder.set_lights(p, null)      # piers as in a pure BRAWL match
	for n in sim.nodes:
		var entry: Dictionary = vis[n["id"]]
		_construction(n, entry, dt)
		_relay(n, entry)
		_last_stand_warning(n)
		# the cannon laser is CombatFx._cannons_step (combat_fx.gd), which replaced the old cylinder beam
	_decks()
	_half_trims()
	_neon()
	_sel_ring.visible = selected >= 0 and not sim.collapsed.get(selected, false)
	if _sel_ring.visible:
		var n: Dictionary = sim.nodes[selected]
		_sel_ring.position = n["pos"] + Vector3(0, 0.25, 0)
		_sel_ring.material_override = Mats.glow(Rules.seat_color(n["owner"]) if n["owner"] != "" else Color.WHITE, 0.8)
		_sel_ring.rotation.y += dt * 0.6
	for p in _pulses.duplicate():
		p["t"] += dt
		var k: float = p["t"] / p["dur"]
		var mi: MeshInstance3D = p["mesh"]
		if k >= 1.0:
			mi.queue_free()
			_pulses.erase(p)
			continue
		mi.scale = Vector3.ONE * lerpf(p["r"] * 0.4, p["r"] * 1.6, sqrt(k))
		mi.transparency = k


func _construction(n: Dictionary, entry: Dictionary, dt: float) -> void:
	var building: bool = n["build_kind"] != "" and n["owner"] != ""
	var model: Node3D = entry["vat_node"]
	if building:
		var p := smoothstep(0.0, 1.0, Sim.build_progress(n))
		if model:
			model.scale = Vector3.ONE * lerpf(0.12, 1.0, p)
		if not _build_rings.has(n["id"]):
			var mi := MeshInstance3D.new()
			mi.mesh = _ring_mesh
			mi.material_override = Mats.construction()
			add_child(mi)
			_build_rings[n["id"]] = mi
		var ring: MeshInstance3D = _build_rings[n["id"]]
		ring.visible = true
		ring.position = n["pos"] + Vector3(0, 0.35 + 3.0 * p, 0)
		ring.scale = Vector3.ONE * (3.2 - 1.2 * p)
		ring.rotation.y += dt * 2.5
		ring.transparency = 0.15 + 0.25 * sin(sim.time * 8.0)
	else:
		if model and model.scale != Vector3.ONE:
			model.scale = Vector3.ONE
		if _build_rings.has(n["id"]):
			(_build_rings[n["id"]] as MeshInstance3D).visible = false


func _relay(n: Dictionary, entry: Dictionary) -> void:
	if n["relay"] == "":
		return
	var id: int = n["id"]
	var state_key := sim.relay_state_key(n, n["relay_index"])
	var col := Rules.state_color(state_key)
	var phase: String = n["relay_phase"]
	if phase == "warning":                                # blink between current and next state colour
		var next_key := sim.relay_state_key(n, n["relay_pending"])
		var blink := int(sim.time * 5.0) % 2 == 0
		col = Rules.state_color(next_key) if blink else Rules.state_color("warn")
		state_key = "warn%d" % int(blink)
	if _state_color.get(id, "") != state_key:
		_state_color[id] = state_key
		MapBuilder.set_state_color(entry, col)
	# cooldown / warning arc on the platform around the tower's ledge
	if not _cool_arcs.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_cool_arcs[id] = mi
	var arc: MeshInstance3D = _cool_arcs[id]
	var frac := 1.0
	var arc_col := Rules.seat_color(n["owner"]) if n["owner"] != "" else Rules.NEUTRAL
	if phase == "warning":
		frac = 1.0 - n["relay_t"] / Rules.RELAY_WARNING
		arc_col = Rules.state_color("warn")
	elif phase == "moving":
		frac = 1.0
		arc_col = Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
	elif n["relay_cd"] > 0.0:
		frac = 1.0 - n["relay_cd"] / Rules.RELAY_COOLDOWN
	arc.visible = n["owner"] != "" and not sim.collapsed.get(id, false)
	if arc.visible:
		arc.position = n["pos"] + Vector3(0, 0.3, 0)
		var built := [frac, arc_col]
		if _arc_built.get(id, []) != built:           # idle relays keep their mesh: no rebuild per frame
			_arc_built[id] = built
			arc.material_override = Mats.glow(arc_col, 0.9)
			_build_arc(arc.mesh as ImmediateMesh, Rules.R - 1.0, Rules.R - 0.45, frac)
	# ghosts of the next state during the warning, motion of the decks during the tick
	for i in sim.controlled_edges(id):
		var ghost_on := false
		if phase == "warning":
			ghost_on = sim._edge_open_at(i, n["relay_pending"]) and not sim._edge_open_at(i, n["relay_index"])
		for g in _ghosts.get(i, []):
			(g as Node3D).visible = ghost_on and not _collapsed.has(i)
	if phase == "moving":
		_relay_motion(n, entry)


func _relay_motion(n: Dictionary, entry: Dictionary) -> void:
	var anim: Dictionary = n["relay_anim"]
	var progress: float = anim.get("progress", 0.0)
	var eased := smoothstep(0.0, 1.0, progress)
	var c: Vector3 = n["pos"]
	match n["relay"]:
		"rotation":
			var delta: float = anim.get("delta", 0.0)
			var angle := delta * eased
			if entry["platform"] != null:                 # a plaza socket has no turntable
				(entry["platform"] as Node3D).rotation.y = -(_plat_angle.get(n["id"], 0.0) + angle)
			for i in anim["closing"]:
				var decks: Array = vis["edge_decks"][i]
				for k in range(decks.size()):
					var base: Transform3D = vis["edge_base"][i][k]
					var d: Node3D = decks[k]
					d.visible = true
					d.position = c + (base.origin - c).rotated(Vector3.UP, -angle)
					d.rotation.y = base.basis.get_euler().y - angle
			for i in anim["opening"]:
				for d in vis["edge_decks"][i]:
					(d as Node3D).visible = false
		"retract":
			for i in anim["closing"] + anim["opening"]:
				var closing: bool = i in anim["closing"]
				var far: int = sim._other_end(i, n["id"])
				var dir: Vector3 = (c - sim.nodes[far]["pos"]).normalized()
				var len: float = sim.edges[i]["modules"] * Rules.S
				var decks: Array = vis["edge_decks"][i]
				for k in range(decks.size()):
					var base: Transform3D = vis["edge_base"][i][k]
					var d: Node3D = decks[k]
					d.visible = true
					var slide := eased if closing else 1.0 - eased
					d.position = base.origin + dir * len * slide - Vector3(0, 0.9 * slide, 0)
		_:                                                # switch / remote: dissolve and assemble
			for i in anim["closing"] + anim["opening"]:
				var closing: bool = i in anim["closing"]
				var k2 := eased if closing else 1.0 - eased
				var decks: Array = vis["edge_decks"][i]
				for k in range(decks.size()):
					var base: Transform3D = vis["edge_base"][i][k]
					var d: Node3D = decks[k]
					d.visible = true
					d.scale = Vector3(base.basis.get_scale().x, maxf(1.0 - k2, 0.02), 1.0 - 0.6 * k2)
					d.position = base.origin - Vector3(0, 6.0 * k2 * k2, 0)


func _restore_edges(n: Dictionary) -> void:
	var anim: Dictionary = n["relay_anim"]
	if n["relay"] == "rotation" and vis[n["id"]]["platform"] != null:
		(vis[n["id"]]["platform"] as Node3D).rotation.y = -_plat_angle.get(n["id"], 0.0)
	for i in anim.get("closing", []) + anim.get("opening", []):
		var decks: Array = vis["edge_decks"][i]
		for k in range(decks.size()):
			(decks[k] as Node3D).transform = vis["edge_base"][i][k]


func _build_arc(mesh: ImmediateMesh, r0: float, r1: float, frac: float) -> void:
	mesh.clear_surfaces()
	if frac <= 0.001:
		return
	var steps := maxi(3, int(48 * frac))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(steps + 1):
		var a := -PI / 2.0 + TAU * frac * k / steps
		mesh.surface_add_vertex(Vector3(cos(a) * r0, 0.0, sin(a) * r0))
		mesh.surface_add_vertex(Vector3(cos(a) * r1, 0.0, sin(a) * r1))
	mesh.surface_end()


func _last_stand_warning(n: Dictionary) -> void:
	var id: int = n["id"]
	var warned: bool = sim.is_warned(id)
	if not _warn_rings.has(id):
		if not warned:
			return
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh
		mi.material_override = Mats.glow(Rules.state_color("warn"), 0.9)
		add_child(mi)
		_warn_rings[id] = mi
	var ring: MeshInstance3D = _warn_rings[id]
	ring.visible = warned
	if warned:
		var left: float = sim.drop_in(id) if sim.v3 else sim.last_stand_warn_t   # 0.18.4: each platform counts to its own drop
		var blink := 0.5 + 0.5 * sin(sim.time * (4.0 + 12.0 * (1.0 - clampf(left / Rules.LAST_STAND_WARNING, 0.0, 1.0))))
		ring.position = n["pos"] + Vector3(0, 0.3, 0)
		ring.scale = Vector3.ONE * (Rules.R + 0.9)
		ring.transparency = 0.2 + 0.5 * blink
		for link in sim.adj[id]:                        # threatened decks flash red
			var edge_i: int = link[1]
			var off: Material = null if Rules.bridge_combat else Mats.light_color(TRIM_OFF, "trim_off")
			var mat: Material = Mats.light_color(Rules.state_color("warn")) if blink > 0.5 else off
			if _edge_light.get(edge_i, "") != "warn%d" % int(blink > 0.5):
				_edge_light[edge_i] = "warn%d" % int(blink > 0.5)
				for d in vis["edge_decks"][edge_i]:
					MapBuilder.set_lights(d, mat)


func _decks() -> void:
	## Deck visibility and edge lights: a deck exists while its state is current (or is in motion),
	## lights carry the nearest owner's colour (both ends held by one seat), state colour otherwise.
	for i in range(sim.edges.size()):
		if _collapsed.has(i):
			continue
		var e: Dictionary = sim.edges[i]
		var ctrl: int = sim.edge_controller.get(i, -1)
		var moving := false
		if ctrl >= 0 and sim.nodes[ctrl]["relay_phase"] == "moving":
			moving = i in sim.nodes[ctrl]["moving_edges"]
		if moving:
			continue                                      # _relay_motion places and shows it
		var open := sim.is_edge_open(i)
		for d in vis["edge_decks"][i]:
			(d as Node3D).visible = open
		if not Rules.bridge_combat:
			continue                                      # BRAWL: _half_trims owns the lights
		if sim.is_warned(e["a"]) or sim.is_warned(e["b"]):
			continue                                      # _last_stand_warning flashes these
		if e["state"] != "" or e["retracts"]:             # relay decks keep their state colour
			if _edge_light.get(i, "?") != "state":
				_edge_light[i] = "state"
				var mat := Mats.light_color(Rules.state_color("retract" if e["retracts"] else e["state"]))
				for d in vis["edge_decks"][i]:
					MapBuilder.set_lights(d, mat)
			continue
		var a: Dictionary = sim.nodes[e["a"]]
		var b: Dictionary = sim.nodes[e["b"]]
		var key: String = a["owner"] if a["owner"] != "" and a["owner"] == b["owner"] else ""
		if _edge_light.get(i, "?") != key:
			_edge_light[i] = key
			for d in vis["edge_decks"][i]:
				MapBuilder.set_lights(d, Mats.light(key) if key != "" else null)
			for p in vis["edge_piers"][i]:
				MapBuilder.set_lights(p, Mats.light(key) if key != "" else null)


# ------------------------------------------------------------------ falls
func _fall_horde(ev: Dictionary) -> void:
	## Units lost to a fall tumble into the void as goo patches (waterfall board: the sheet at the
	## lip thins into strands and drops - here the patches tilt, drop and trail droplets). BRAWL has no
	## goo: its Alpha 11 bodies tumble down instead, one per shown unit (a line pouring off a lip loses
	## fractions of a unit per step: they add up per seat until a whole body drops).
	var faction: String = ev["faction"]
	var seat: String = ev["seat"]
	if not Rules.bridge_combat:
		var debt: float = _fall_debt.get(seat, 0.0) + Rules.shown_f(float(ev.get("units", 0.0)))
		var n := mini(int(debt), FLING_MAX_BODIES)
		_fall_debt[seat] = debt - int(debt)
		for b in _spawn_bodies(faction, seat, ev["pts"], n):
			var mi: MeshInstance3D = b[0]
			var tw := create_tween()
			tw.set_parallel(true)
			var spin := Vector3(randf_range(-2.5, 2.5), randf_range(-1.0, 1.0), randf_range(-2.5, 2.5))
			tw.tween_property(mi, "position", (b[1] as Vector3) + Vector3(randf_range(-1.5, 1.5), -FLING_DROP, randf_range(-1.5, 1.5)), 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(mi, "rotation", mi.rotation + spin, 1.4)
			tw.tween_property(mi, "scale", mi.scale * 0.7, 1.4)
			tw.chain().tween_callback(mi.queue_free)
		return
	hordes.load_faction(faction)
	var mesh: Mesh = hordes.meshes[faction].get("body_a_lod1", null)
	for p in ev["pts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if mesh:
			for s in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(s) as BaseMaterial3D
				var is_creature := m != null and m.albedo_texture != null
				mi.set_surface_override_material(s, Mats.creature(faction, seat, hordes.textures[faction])
						if is_creature else Mats.goo(seat))
		mi.position = p
		mi.rotation.y = randf() * TAU
		add_child(mi)
		var tw := create_tween()
		tw.set_parallel(true)
		var spin := Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
		tw.tween_property(mi, "position", (p as Vector3) + Vector3(randf_range(-1.5, 1.5), -26.0, randf_range(-1.5, 1.5)), 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "rotation", mi.rotation + spin, 1.4)
		tw.tween_property(mi, "scale", Vector3(0.5, 1.6, 0.5), 1.4)
		tw.chain().tween_callback(mi.queue_free)
	var drops := _waterfall(seat, 0.9, 1.2)
	if not ev["pts"].is_empty():
		drops.position = ev["pts"][0]
		drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		drops.emission_sphere_radius = 1.2
	add_child(drops)


# Rotation relays (Daniele, 0.18.3: "when a rotating bridge turns all units that are on it are shaken
# down into the void as if the fall due to centrifugal power"): every body is thrown off the deck -
# outward, away from the pivot along the deck, plus a sideways kick the way the deck turns - arcs up a
# little, tumbles and drops FLING_DROP m into the void over FLING_TIME s.
const FLING_TIME := 1.3
const FLING_DROP := 26.0             # as deep as a fall (_fall_horde)
const FLING_OUT := 8.0               # m/s outward; grows with the distance from the pivot (centrifugal)
const FLING_SIDE := 6.5              # m/s sideways, the way the deck turns
const FLING_UP := 3.5                # m/s up: the shake throws them before they drop
const FLING_MAX_BODIES := 120        # BRAWL: one Alpha 11 body per shown unit, up to this


func _fling_horde(ev: Dictionary) -> void:
	## SIEGE flings the line's goo patches (and a spray of droplets), BRAWL flings Alpha 11 creature
	## bodies - one per shown unit, three across like UnitView's column - never goo.
	var pts: Array = ev.get("pts", [])
	if pts.is_empty():
		return
	var faction: String = ev["faction"]
	var seat: String = ev["seat"]
	var centre: Vector3 = ev["centre"]
	var turn: float = ev.get("turn", 1.0)
	if Rules.bridge_combat:
		hordes.load_faction(faction)
		var mesh: Mesh = hordes.meshes[faction].get("body_a_lod1", null)
		for p in pts:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			if mesh:
				for s in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(s) as BaseMaterial3D
					var is_creature := m != null and m.albedo_texture != null
					mi.set_surface_override_material(s, Mats.creature(faction, seat, hordes.textures[faction])
							if is_creature else Mats.goo(seat))
			mi.rotation.y = randf() * TAU
			add_child(mi)
			_fling_body(mi, p, centre, turn, Vector3(0.6, 1.3, 0.6))
		var spray := _waterfall(seat, 0.9, 1.2)
		spray.position = pts[0]
		spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		spray.emission_sphere_radius = 1.2
		var out: Vector3 = ((pts[0] as Vector3) - centre) * Vector3(1, 0, 1)
		spray.direction = (out.normalized() + Vector3(0, 0.6, 0)) if out.length() > 0.01 else Vector3.UP
		spray.spread = 40.0
		spray.initial_velocity_min = 3.0
		spray.initial_velocity_max = 7.0
		add_child(spray)
		return
	for b in _spawn_bodies(faction, seat, pts, clampi(int(ev.get("units", 1)), 1, FLING_MAX_BODIES)):
		_fling_body(b[0], b[1], centre, turn, (b[0] as MeshInstance3D).scale * 0.7)


func _spawn_bodies(faction: String, seat: String, pts: Array, n: int) -> Array:
	## BRAWL: n Alpha 11 bodies laid along the lost stretch three across, as UnitView draws a column
	## (owner-coloured creature, UnitView's glow). Returns [[MeshInstance3D, start position]].
	var out := []
	var body := _body_for(faction)
	if body.is_empty() or pts.is_empty() or n <= 0:
		return out
	var mat := _body_mat_for(faction, seat, body[2])
	var line := _polyline(pts)
	var rows := int(ceil(n / float(UnitView.ACROSS)))
	for j in range(n):
		var row := int(j / float(UnitView.ACROSS))
		var col := j % UnitView.ACROSS
		var at := _along(line, 0.0 if rows <= 1 else float(row) / float(rows - 1))
		var side: Vector3 = (at[1] as Vector3).cross(Vector3.UP).normalized()
		var row_size := mini(UnitView.ACROSS, n - row * UnitView.ACROSS)
		var p: Vector3 = (at[0] as Vector3) + side * (col - (row_size - 1) * 0.5) * UnitView.LANE + Vector3(0, 0.08, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = body[0]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * float(body[1])
		mi.rotation.y = Rules.heading(Rules.front_dir()) + UnitView.MODEL_YAW + randf_range(-0.5, 0.5)
		mi.position = p
		add_child(mi)
		out.append([mi, p])
	return out


func _fling_body(mi: MeshInstance3D, p: Vector3, centre: Vector3, turn: float, end_scale: Vector3) -> void:
	## One flung body: a ballistic arc (outward + sideways + a little up, then gravity to FLING_DROP m
	## below at FLING_TIME) with a tumble. The deck turns by -angle about UP (_relay_motion), so a
	## point on it moves along -turn * (UP x r).
	var r := (p - centre) * Vector3(1, 0, 1)
	var radius := r.length()
	var out := r / radius if radius > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var kick := Vector3.UP.cross(out) * -turn
	var reach := clampf(radius / 12.0, 0.6, 2.0)        # farther from the pivot = thrown harder
	var vel := out * FLING_OUT * reach * randf_range(0.8, 1.2) + kick * FLING_SIDE * reach * randf_range(0.7, 1.3) \
			+ Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	var up := FLING_UP * randf_range(0.7, 1.3)
	var g := 2.0 * (FLING_DROP + up * FLING_TIME) / (FLING_TIME * FLING_TIME)
	var start_rot := mi.rotation
	var spin := Vector3(randf_range(-7.0, 7.0), randf_range(-4.0, 4.0), randf_range(-7.0, 7.0))
	var start_scale := mi.scale
	mi.position = p
	var tw := create_tween()
	tw.tween_interval(randf_range(0.0, 0.18))           # shaken off, not launched as one block
	tw.tween_method(func(t: float):
		if is_instance_valid(mi):
			mi.position = p + vel * t + Vector3(0, up * t - 0.5 * g * t * t, 0)
			mi.rotation = start_rot + spin * t
			mi.scale = start_scale.lerp(end_scale, t / FLING_TIME), 0.0, FLING_TIME, FLING_TIME)
	tw.tween_callback(mi.queue_free)


func _body_for(faction: String) -> Array:
	## The approved Alpha 11 unit model (assets/units/<faction>.glb, loaded as UnitView loads it).
	if not _body.has(faction):
		_body[faction] = []
		var scene: PackedScene = load("res://assets/units/%s.glb" % faction) if Rules.FACTIONS.has(faction) else null
		if scene:
			var root: Node = scene.instantiate()
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				var aabb := mesh.get_aabb()
				var src := mesh.surface_get_material(0) as BaseMaterial3D
				_body[faction] = [mesh, UnitView.UNIT_SIZE / maxf(maxf(aabb.size.x, aabb.size.z), 0.001),
						src.albedo_texture if src else null]
				break
			root.free()
	return _body[faction]


func _body_mat_for(faction: String, seat: String, tex: Texture2D) -> Material:
	var key := "%s|%s" % [faction, seat]
	if not _body_mat.has(key):
		if tex:
			var m: ShaderMaterial = (Mats.creature(faction, seat, tex) as ShaderMaterial).duplicate()
			m.set_shader_parameter("self_glow", 0.45)      # UnitView's column look
			_body_mat[key] = m
		else:
			_body_mat[key] = Mats.goo(seat)
	return _body_mat[key]


static func _polyline(pts: Array) -> Array:
	## [points, cumulative lengths] of the flung stretch.
	var cum := [0.0]
	for i in range(1, pts.size()):
		cum.append(float(cum[-1]) + (pts[i] as Vector3).distance_to(pts[i - 1]))
	return [pts, cum]


static func _along(line: Array, u: float) -> Array:
	## [position, unit direction] at fraction u of the polyline.
	var pts: Array = line[0]
	var cum: Array = line[1]
	if pts.size() < 2 or float(cum[-1]) <= 0.001:
		return [pts[0], Vector3.RIGHT]
	var d: float = u * float(cum[-1])
	for i in range(1, pts.size()):
		if d <= float(cum[i]) or i == pts.size() - 1:
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var seg: float = maxf(float(cum[i]) - float(cum[i - 1]), 0.001)
			return [a.lerp(b, clampf((d - float(cum[i - 1])) / seg, 0.0, 1.0)), (b - a).normalized()]
	return [pts[-1], Vector3.RIGHT]


func _waterfall(seat: String, radius: float, seconds: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = 0.22
	m.height = 0.44
	m.radial_segments = 6
	m.rings = 3
	m.material = Mats.goo(seat)                       # "" = neutral goo, like a neutral river
	p.mesh = m
	p.amount = 90
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.15
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.85
	p.emission_ring_height = 0.2
	p.direction = Vector3(0, -1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.emitting = true
	var timer := get_tree().create_timer(seconds + 2.0)
	timer.timeout.connect(p.queue_free)
	return p


func _collapse(node_id: int, from := "") -> void:
	## Last Stand destruction: the platform and every deck it still has fall away; decks break into
	## the kit's fragment pieces, goo pours over the rim all the way round (waterfall board E).
	## `from` is the owner before the drop (the sim has already cleared it): the goo's colour.
	var n: Dictionary = sim.nodes[node_id]
	var falling: Array = vis[node_id]["parts"].duplicate()
	if _rims.has(node_id):                             # its neon goes down with the platform and piers
		falling.append(_rims[node_id])
	for i in _pier_neon:
		for end in range(2):
			if _pier_neon[i][end] != null and sim.edges[i]["b" if end == 1 else "a"] == node_id:
				falling.append(_pier_neon[i][end])
	for key in ["build_rings", "warn_rings", "cool_arcs"]:
		var dict: Dictionary = get(("_" + key))
		if dict.has(node_id):
			(dict[node_id] as Node3D).visible = false
	for i in range(sim.edges.size()):
		if sim.edges[i]["a"] == node_id or sim.edges[i]["b"] == node_id:
			if _collapsed.has(i):
				continue
			_collapsed[i] = true
			for g in _ghosts.get(i, []):
				(g as Node3D).visible = false
			if vis["conduits"].has(i):
				(vis["conduits"][i] as Node3D).visible = false
			for d in vis["edge_decks"][i]:
				var deck := d as Node3D
				if not deck.visible:
					continue
				deck.visible = false
				for frag in _frag_names:                  # the module breaks into its fall pieces
					var piece := MapBuilder.put(world, "Deck_S_Frag_" + frag, deck.position, deck.rotation.y, deck.scale.x)
					falling.append(piece)
	for pid in vis.get("plazas", {}):                  # maps 3.0: a plaza goes when its last socket goes
		var pz: Dictionary = vis["plazas"][pid]
		if node_id in pz["members"] and pz["node"] and (pz["members"] as Array).all(func(m): return sim.collapsed.get(m, false)):
			falling.append(pz["node"])
	var wf := _waterfall(from, Rules.R, 1.8)
	wf.amount = 220
	wf.position = n["pos"] + Vector3(0, 0.2, 0)
	add_child(wf)
	var tw := create_tween()
	tw.set_parallel(true)
	for p in falling:
		var node3d := p as Node3D
		if not is_instance_valid(node3d):
			continue
		var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 1.4
		var delay := randf_range(0.0, 0.35)
		tw.tween_property(node3d, "position:y", node3d.position.y - 26.0, 1.5).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(node3d, "rotation", node3d.rotation + spin, 1.5).set_delay(delay).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		for p in falling:
			if is_instance_valid(p):
				(p as Node3D).visible = false)


# ------------------------------------------------------------------ neon: half-bridge trims, pier stripes, rims
# BRAWL (Daniele: "bridges need to follow Alpha 11's idea of neon lighting up half the bridge connected
# to a node"): every deck carries two neon strips along its edges; the half nearest each node glows in
# that node's owner colour (neutral amber), like Alpha 11's bridge_trims, and the kit's own deck lights
# are dimmed. Daniele (0.18.5): "sockets miss the neon stripe on top like normal bridge (please add),
# same neon stripe should be added at the edge of nodes for consistent look" - the strips continue over
# every pier to the platform, where a rim stripe runs round the edge of the platform in the node's
# colour and opens at each pier mouth (and at a relay ledge or gate), so a bridge's strips turn into
# the rim. SIEGE keeps its kit deck lights: the rims show there too (owner colour, the kit light when
# neutral) and the pier stripes follow the deck lights' colour (_decks / _last_stand_warning).
# Geometry is static and built once: one mesh per deck half (both strips, ramps included), per pier
# (both strips) and per platform rim; only materials (shared, per colour) and visibility change.
var _trims := {}             # edge -> [deck half a, deck half b] MeshInstance3D (null: no deck)
var _trim_state := {}        # edge -> [show, owner_a, owner_b] last applied
var _pier_neon := {}         # edge -> [pier a, pier b] MeshInstance3D (null: no pier stripe there)
var _pier_key := {}          # edge * 2 + end -> colour key last applied
var _rims := {}              # node id -> MeshInstance3D
var _rim_key := {}           # node id -> owner last applied
var _neon_built := false
var _kit_light: Material     # the kit's own OS_Light (SIEGE's neutral deck light)
const NEUTRAL_TRIM := Color("ffad51")   # Alpha 11's neutral bridge trim
const TRIM_OFF := Color(0.12, 0.14, 0.16)   # the kit's deck lights, dimmed under the trims
const TRIM_Y := 0.1                  # strip centre above the deck plate
const TRIM_HW := 0.07                # half width (0.14 m strip)
const TRIM_HH := 0.035               # half height (0.07 m)
const TRIM_MID_GAP := 0.15           # each half stops this short of the middle (Alpha 11's split)
const RIM_R := 5.75                  # rim stripe radius: the dark band between the plate ring and the edge
const LEDGE_HW := 2.45               # Relay_Mount / Relay_Retract half width (kit 2.35 / 2.375) + clearance
const SIEGE_PIER_STRIPES := true


func _trim_off() -> float:
	return Rules.W * 0.42            # strip offset from the deck centre line


func _build_neon() -> void:
	_neon_built = true
	var off := _trim_off()
	for n in sim.nodes:
		var pf = vis[n["id"]]["platform"]
		if pf != null and _kit_light == null:
			for mi in (pf as Node3D).find_children("*", "MeshInstance3D", true, false):
				var mesh := (mi as MeshInstance3D).mesh
				for s in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(s)
					if m and m.resource_name.begins_with("OS_Light"):
						_kit_light = m
	var gaps := {}                                    # node id -> [[start angle, arc length]]
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var line: Array = sim.deck_line(i)
		if line.size() < 4:
			continue
		# deck halves: split the deck (pier end to pier end, ramps included) at half its length
		var deck: Array = line.slice(1, line.size() - 1)
		var total := 0.0
		for k in range(1, deck.size()):
			total += (deck[k] as Vector3).distance_to(deck[k - 1])
		var plan: Vector3 = ((line[-1] as Vector3) - (line[0] as Vector3)) * Vector3(1, 0, 1)
		var side := plan.normalized().cross(Vector3.UP).normalized()
		var halves := [null, null]
		if total > 2.0 * TRIM_MID_GAP + 0.1:
			for h in range(2):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var a0 := 0.0 if h == 0 else total / 2.0 + TRIM_MID_GAP
				var a1 := total / 2.0 - TRIM_MID_GAP if h == 0 else total
				var run := 0.0
				for k in range(1, deck.size()):
					var p: Vector3 = deck[k - 1]
					var q: Vector3 = deck[k]
					var seg := p.distance_to(q)
					var lo := maxf(a0, run)
					var hi := minf(a1, run + seg)
					if hi - lo > 0.01:
						var u0 := p.lerp(q, (lo - run) / seg)
						var u1 := p.lerp(q, (hi - run) / seg)
						for sgn in [1.0, -1.0]:
							var o: Vector3 = side * off * sgn + Vector3(0, TRIM_Y, 0)
							_bar(st, u0 + o, u1 + o, side)
					run += seg
				halves[h] = _neon_mesh(st, Vector3.ZERO)
		_trims[i] = halves
		# pier stripes: from the rim stripe along the pier to the deck, at the same offsets
		var piers := [null, null]
		for end in range(2):
			var nid: int = e["a"] if end == 0 else e["b"]
			var n: Dictionary = sim.nodes[nid]
			if n["plaza"] >= 0 or vis[nid]["platform"] == null:
				continue
			var c: Vector3 = n["pos"]
			var x: Vector3 = line[0] if end == 0 else line[-1]
			var d_end: Vector3 = line[1] if end == 0 else line[-2]
			var u := (d_end - x) * Vector3(1, 0, 1)
			var reach := u.length()
			u = u.normalized() if reach > 0.001 else (plan.normalized() * (1.0 if end == 0 else -1.0))
			var sd := u.cross(Vector3.UP).normalized()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var any := false
			var ang := []
			for sgn in [1.0, -1.0]:
				var t0 := _rim_cross(c, x, u, off * sgn)
				var q0: Vector3 = x + sd * off * sgn + u * t0
				ang.append(atan2(q0.z - c.z, q0.x - c.x))
				if reach - (t0 - TRIM_HW) > 0.05:
					var y := Vector3(0, TRIM_Y, 0)
					_bar(st, q0 - u * TRIM_HW + y - c, x + sd * off * sgn + u * reach + y - c, sd)
					any = true
			if not gaps.has(nid):
				gaps[nid] = []
			gaps[nid].append(_gap(ang[0], ang[1]))
			if any:
				piers[end] = _neon_mesh(st, c)
		_pier_neon[i] = piers
	for n in sim.nodes:                               # relay ledges and retract gates straddle the rim too
		var id: int = n["id"]
		if vis[id]["platform"] == null:
			continue
		var c: Vector3 = n["pos"]
		for p in vis[id]["parts"]:
			if not is_instance_valid(p):
				continue
			var path := (p as Node).scene_file_path
			if path.ends_with("/Relay_Mount.glb") or path.ends_with("/Relay_Retract.glb"):
				var ax: Vector3 = ((p as Node3D).transform.basis.x * Vector3(1, 0, 1)).normalized()
				var o: Vector3 = (p as Node3D).position
				var sd := ax.cross(Vector3.UP).normalized()
				var q1 := o + sd * LEDGE_HW + ax * _rim_cross(c, o, ax, LEDGE_HW)
				var q2 := o - sd * LEDGE_HW + ax * _rim_cross(c, o, ax, -LEDGE_HW)
				if not gaps.has(id):
					gaps[id] = []
				gaps[id].append(_gap(atan2(q1.z - c.z, q1.x - c.x), atan2(q2.z - c.z, q2.x - c.x)))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for arc in _arcs(gaps.get(id, [])):
			_rim_arc(st, arc[0], arc[1], arc[2])
		_rims[id] = _neon_mesh(st, c)


func _neon_mesh(st: SurfaceTool, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.visible = false
	add_child(mi)
	return mi


static func _rim_cross(c: Vector3, origin: Vector3, axis: Vector3, off: float) -> float:
	## Along the line origin + side * off + axis * t (plan), the t where it leaves the rim stripe's
	## circle (the far root); 0 when it misses.
	var w := (origin + axis.cross(Vector3.UP).normalized() * off - c) * Vector3(1, 0, 1)
	var b := w.dot(axis)
	var disc := b * b - (w.dot(w) - RIM_R * RIM_R)
	return -b + sqrt(disc) if disc >= 0.0 else 0.0


static func _gap(a: float, b: float) -> Array:
	## The short arc between two angles: [start in 0..TAU, length].
	var d := wrapf(b - a, -PI, PI)
	return [fposmod(a if d >= 0.0 else b, TAU), absf(d)]


static func _arcs(gaps: Array) -> Array:
	## The rim's lit arcs between its gaps: [[start, end, closed]] (closed: one full ring, no ends).
	if gaps.is_empty():
		return [[0.0, TAU, true]]
	gaps.sort_custom(func(x, y): return x[0] < y[0])
	var merged := []
	for g in gaps:
		var s: float = g[0]
		var e: float = g[0] + g[1]
		if not merged.is_empty() and s <= merged[-1][1]:
			merged[-1][1] = maxf(merged[-1][1], e)
		else:
			merged.append([s, e])
	while merged.size() > 1 and merged[-1][1] - TAU >= merged[0][0]:   # the last gap wraps over the first
		merged[0] = [merged[-1][0] - TAU, maxf(merged[0][1], merged[-1][1] - TAU)]
		merged.pop_back()
	var out := []
	for k in range(merged.size()):
		var a0: float = merged[k][1]
		var a1: float = merged[(k + 1) % merged.size()][0] + (TAU if k == merged.size() - 1 else 0.0)
		if a1 - a0 > 0.02:
			out.append([a0, a1, false])
	return out


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	## One face; Godot's front faces wind clockwise seen from outside, whatever order a-d come in.
	st.set_normal(n)
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	st.add_vertex(a)
	st.add_vertex(c if flip else b)
	st.add_vertex(b if flip else c)
	st.add_vertex(a)
	st.add_vertex(d if flip else c)
	st.add_vertex(c if flip else d)


static func _bar(st: SurfaceTool, p0: Vector3, p1: Vector3, side: Vector3) -> void:
	## A neon strip from p0 to p1 (centre line), TRIM_HW wide along `side`, TRIM_HH high; no bottom.
	var x := (p1 - p0).normalized()
	var up := side.cross(x).normalized()
	var s := side * TRIM_HW
	var u := up * TRIM_HH
	_quad(st, p0 - s + u, p0 + s + u, p1 + s + u, p1 - s + u, up)
	_quad(st, p0 + s - u, p1 + s - u, p1 + s + u, p0 + s + u, side)
	_quad(st, p0 - s - u, p0 - s + u, p1 - s + u, p1 - s - u, -side)
	_quad(st, p0 - s - u, p0 + s - u, p0 + s + u, p0 - s + u, -x)
	_quad(st, p1 - s - u, p1 - s + u, p1 + s + u, p1 + s - u, x)


static func _rim_arc(st: SurfaceTool, a0: float, a1: float, closed: bool) -> void:
	## The rim stripe from angle a0 to a1 round the platform centre (local), same profile as a strip.
	var steps := maxi(2, int(ceil((a1 - a0) / (TAU / 96.0))))
	var r0 := RIM_R - TRIM_HW
	var r1 := RIM_R + TRIM_HW
	var lo := Vector3(0, TRIM_Y - TRIM_HH, 0)
	var hi := Vector3(0, TRIM_Y + TRIM_HH, 0)
	for k in range(steps):
		var t0 := a0 + (a1 - a0) * k / steps
		var t1 := a0 + (a1 - a0) * (k + 1) / steps
		var v0 := Vector3(cos(t0), 0.0, sin(t0))
		var v1 := Vector3(cos(t1), 0.0, sin(t1))
		var vm := (v0 + v1).normalized()
		_quad(st, v0 * r0 + hi, v0 * r1 + hi, v1 * r1 + hi, v1 * r0 + hi, Vector3.UP)
		_quad(st, v0 * r1 + lo, v1 * r1 + lo, v1 * r1 + hi, v0 * r1 + hi, vm)
		_quad(st, v0 * r0 + lo, v0 * r0 + hi, v1 * r0 + hi, v1 * r0 + lo, -vm)
	if not closed:
		for t in [a0, a1]:
			var v := Vector3(cos(t), 0.0, sin(t))
			var tg := Vector3(-v.z, 0.0, v.x) * (-1.0 if t == a0 else 1.0)
			_quad(st, v * r0 + lo, v * r1 + lo, v * r1 + hi, v * r0 + hi, tg)


func _brawl_color(owner: String) -> Color:
	return Rules.seat_color(owner) if owner != "" else NEUTRAL_TRIM


func _half_trims() -> void:
	## BRAWL deck halves: shown while the deck is open, each half in its end's owner colour.
	var on := not Rules.bridge_combat
	for i in _trims:
		var e: Dictionary = sim.edges[i]
		var show: bool = on and not _collapsed.has(i) and sim.is_edge_open(i)
		var oa: String = sim.nodes[e["a"]]["owner"]
		var ob: String = sim.nodes[e["b"]]["owner"]
		var last: Array = _trim_state.get(i, [])
		if not last.is_empty() and last[0] == show and last[1] == oa and last[2] == ob:
			continue                                      # geometry is static: only show/owners change it
		_trim_state[i] = [show, oa, ob]
		for h in range(2):
			var mi = _trims[i][h]
			if mi == null:
				continue
			(mi as MeshInstance3D).visible = show
			if show:
				(mi as MeshInstance3D).material_override = Mats.light_color(_brawl_color(oa if h == 0 else ob))


func _neon() -> void:
	## Pier stripes and platform rims (see the section note): BRAWL in the end node's owner colour,
	## SIEGE the pier follows its deck's lights and the rim the owner. A dropped node's stripes fall
	## with it (_collapse): they are left alone from then on.
	var brawl := not Rules.bridge_combat
	for i in _pier_neon:
		var e: Dictionary = sim.edges[i]
		for end in range(2):
			var mi = _pier_neon[i][end]
			var nid: int = e["a"] if end == 0 else e["b"]
			if mi == null or sim.collapsed.get(nid, false):
				continue
			var key: String = sim.nodes[nid]["owner"] if brawl else _edge_light.get(i, "")
			if _pier_key.get(i * 2 + end, "?") == key:
				continue
			_pier_key[i * 2 + end] = key
			(mi as MeshInstance3D).visible = brawl or SIEGE_PIER_STRIPES
			(mi as MeshInstance3D).material_override = Mats.light_color(_brawl_color(key)) if brawl else _siege_light(i, key)
	for id in _rims:
		if sim.collapsed.get(id, false):
			continue
		var owner: String = sim.nodes[id]["owner"]
		if _rim_key.get(id, "?") == owner:
			continue
		_rim_key[id] = owner
		var mi: MeshInstance3D = _rims[id]
		mi.visible = true
		if brawl:
			mi.material_override = Mats.light_color(_brawl_color(owner))
		else:
			mi.material_override = Mats.light(owner) if owner != "" else _kit_light


func _siege_light(i: int, key: String) -> Material:
	## The material SIEGE's deck lights carry for _edge_light key `key` (_decks, _last_stand_warning).
	var e: Dictionary = sim.edges[i]
	if key == "state":
		return Mats.light_color(Rules.state_color("retract" if e["retracts"] else e["state"]))
	if key == "warn1":
		return Mats.light_color(Rules.state_color("warn"))
	if key == "" or key == "warn0":
		return _kit_light
	return Mats.light(key)
