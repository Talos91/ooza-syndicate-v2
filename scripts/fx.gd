class_name Fx
extends Node3D
## In-world animation and effects: construction (the new structure grows out of the socket under a
## turning build ring), capture pulses, cannon beams, relay warnings (blinking state lights + a ghost
## of the next deck), relay motion (rotation pivots the turntable and its decks, retract slides the
## deck into its gate, switch/remote dissolve and assemble), the Last Stand warning ring and the falls
## (platform, deck fragments, waterfall of goo, hordes tumbling into the void, lines flung off a
## turning rotation deck), the selection ring,
## owner-coloured deck lights (SIEGE) and Alpha 11's half-bridge neon trims (BRAWL).

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
var _beams := {}            # node id -> {"beam", "flash"}
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
	var classic := not Rules.bridge_combat
	if classic != _lights_classic:                    # SIEGE/BRAWL switched (pause menu, Debug panel)
		_lights_classic = classic
		_edge_light.clear()                           # SIEGE: _decks re-applies owner/state lights
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
		_cannon(n, entry)
	_decks()
	_half_trims()
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


func _cannon(n: Dictionary, _entry: Dictionary) -> void:
	var id: int = n["id"]
	var firing: bool = n["attachment"] == "cannon" and n["cannon_burst"] > 0.0 and n["owner"] != ""
	if not _beams.has(id):
		if not firing:
			return
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.16
		cyl.height = 1.0
		cyl.radial_segments = 8
		beam.mesh = cyl
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		var flash := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		sph.radial_segments = 12
		sph.rings = 6
		flash.mesh = sph
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flash)
		_beams[id] = {"beam": beam, "flash": flash}
	var b: Dictionary = _beams[id]
	(b["beam"] as MeshInstance3D).visible = firing
	(b["flash"] as MeshInstance3D).visible = firing
	if not firing:
		return
	var col := Rules.seat_color(n["owner"])
	var from: Vector3 = n["pos"] + Vector3(0, 4.3 + 0.35 * n["cannon_tier"], 0)
	var to: Vector3 = n["cannon_target"] + Vector3(0, 0.6, 0)
	var beam: MeshInstance3D = b["beam"]
	beam.material_override = Mats.glow(col.lerp(Color.WHITE, 0.5), 0.9)
	var v := to - from
	beam.position = (from + to) / 2.0
	beam.scale = Vector3(1.0 + 0.4 * sin(sim.time * 40.0), v.length(), 1.0 + 0.4 * sin(sim.time * 40.0))
	if v.length() > 0.01:
		beam.look_at(to, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.FORWARD)
		beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var flash: MeshInstance3D = b["flash"]
	flash.material_override = Mats.glow(col.lerp(Color.WHITE, 0.6), 0.55)
	flash.position = to
	flash.scale = Vector3.ONE * (1.2 + 0.6 * absf(sin(sim.time * 25.0)))


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


# ------------------------------------------------------------------ BRAWL: Alpha 11 half-bridge neon
var _trims := {}             # edge -> [MeshInstance3D x4]: two edges x two halves
var _trim_key := {}          # edge -> "show|owner_a|owner_b" last applied
var _trim_mesh: BoxMesh
const NEUTRAL_TRIM := Color("ffad51")   # Alpha 11's neutral bridge trim
const TRIM_OFF := Color(0.12, 0.14, 0.16)   # the kit's deck lights, dimmed under the trims


func _half_trims() -> void:
	## BRAWL (Daniele: "bridges need to follow Alpha 11's idea of neon lighting up half the
	## bridge connected to a node"): every deck carries two neon strips along its edges; the half
	## nearest each node glows in that node's owner colour (neutral amber), like Alpha 11's
	## bridge_trims. The kit's own deck lights are dimmed while this is on.
	var on := not Rules.bridge_combat
	if _trim_mesh == null:
		_trim_mesh = BoxMesh.new()
		_trim_mesh.size = Vector3(1.0, 0.07, 0.14)
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var show: bool = on and not _collapsed.has(i) and sim.is_edge_open(i)
		if not _trims.has(i):
			if not show:
				continue
			var arr := []
			for k in range(4):
				var mi := MeshInstance3D.new()
				mi.mesh = _trim_mesh
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				arr.append(mi)
			_trims[i] = arr
			for d in vis["edge_decks"][i]:
				MapBuilder.set_lights(d, Mats.light_color(TRIM_OFF, "trim_off"))
		var key := "%s|%s|%s" % [show, sim.nodes[e["a"]]["owner"], sim.nodes[e["b"]]["owner"]]
		if _trim_key.get(i, "") == key:
			continue                                      # geometry is static: only show/owners change it
		_trim_key[i] = key
		var parts: Array = _trims[i]
		for mi in parts:
			(mi as MeshInstance3D).visible = show
		if not show:
			continue
		var line: Array = sim.deck_line(i)
		if line.is_empty():
			continue
		if not sim.v3:                                    # legacy: trims run centre to centre
			line = [sim.nodes[e["a"]]["pos"]] + sim.deck_points(i, e["a"]) + [sim.nodes[e["b"]]["pos"]]
		var pa: Vector3 = line[1] if line.size() > 2 else line[0]
		var pb: Vector3 = line[-2] if line.size() > 2 else line[-1]
		var mid := (pa + pb) / 2.0
		var halves := [[pa, mid, sim.nodes[e["a"]]["owner"]], [mid, pb, sim.nodes[e["b"]]["owner"]]]
		for h in range(2):
			var p0: Vector3 = halves[h][0]
			var p1: Vector3 = halves[h][1]
			var owner: String = halves[h][2]
			var col: Color = Rules.seat_color(owner) if owner != "" else NEUTRAL_TRIM
			var dir := (p1 - p0)
			var x := dir.normalized()
			var side := x.cross(Vector3.UP).normalized()
			for s in range(2):
				var mi: MeshInstance3D = parts[h * 2 + s]
				mi.material_override = Mats.light_color(col)
				mi.position = (p0 + p1) / 2.0 + side * (Rules.W * 0.42) * (1 if s == 0 else -1) + Vector3(0, 0.1, 0)
				mi.basis = Basis(x * maxf(dir.length() - 0.3, 0.1), Vector3.UP, side)
