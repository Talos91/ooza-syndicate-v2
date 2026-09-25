class_name Fx
extends Node3D
## In-world animation and effects (Alpha 12 - Daniele: "the complete lack of animation, HUD, UX/UI
## makes it unplayable"): construction (the new structure grows out of the socket under a
## turning build ring), capture pulses, the shield dome and its break, cannon beams, relay
## warnings (blinking state lights + a ghost of the next deck), relay motion (rotation pivots
## the turntable and its decks, retract slides the deck into its gate, switch/remote dissolve and
## assemble), the Last Stand warning ring and the falls (platform, deck fragments, waterfall of
## goo, hordes tumbling into the void), plus the selection ring and owner-coloured deck lights.

var sim: Sim
var vis: Dictionary
var hordes: HordeView
var world: Node3D
var selected := -1
var _sel_ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _thin_ring: TorusMesh
var _domes := {}            # node id -> MeshInstance3D
var _build_rings := {}      # node id -> MeshInstance3D
var _warn_rings := {}       # node id -> MeshInstance3D (Last Stand)
var _cool_arcs := {}        # node id -> MeshInstance3D (relay cooldown / warning)
var _beams := {}            # node id -> {"beam", "flash"}
var _ghosts := {}           # edge -> [Node3D]
var _plat_angle := {}       # node id -> accumulated turntable angle
var _edge_light := {}       # edge -> owner key currently applied
var _state_color := {}      # node id -> state key applied
var _collapsed := {}
var _pulses: Array = []     # transient rings: {mesh, t, dur, color}
var _frag_names := ["girder_l", "girder_r", "plate_a", "plate_b", "plate_c", "truss"]


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
		"shield_break":
			var n: Dictionary = sim.nodes[ev["node"]]
			_pulse(n["pos"], Rules.state_color("warn"), Rules.RIVER_R + 1.0, 0.7)
		"shield_up":
			var n: Dictionary = sim.nodes[ev["node"]]
			_pulse(n["pos"], Rules.seat_color(n["owner"]), Rules.RIVER_R, 0.5)
		"relay_done":
			var n: Dictionary = sim.nodes[ev["node"]]
			if n["relay"] == "rotation":
				_plat_angle[n["id"]] = _plat_angle.get(n["id"], 0.0) + n["relay_anim"].get("delta", 0.0)
			_restore_edges(n)
		"fall":
			_fall_horde(ev)
		"collapse":
			_collapse(ev["node"])


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
	for n in sim.nodes:
		var entry: Dictionary = vis[n["id"]]
		_construction(n, entry, dt)
		pass                                          # Alpha 14: no shield pool, no shield ring
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


func _shield(n: Dictionary, _entry: Dictionary) -> void:
	var id: int = n["id"]
	if not _domes.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh                          # a flat ring, not a dome: no fill-rate cost
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_domes[id] = mi
	var dome: MeshInstance3D = _domes[id]
	var owner: String = n["owner"]
	if owner == "" or sim.collapsed.get(id, false) or n["units"] <= 0.0 or Rules.low_detail:
		dome.visible = false
		return
	var cap: float = maxf(Rules.SHIELD_FRACTION * n["units"], 0.001)
	var ratio := clampf(n["shield"] / cap, 0.0, 1.0)
	dome.visible = n["shield_up"] or ratio > 0.05
	dome.material_override = Mats.shield(owner)
	var r := Rules.RIVER_R + 1.3
	dome.position = n["pos"] + Vector3(0, 0.35 + 0.9 * ratio, 0)
	dome.scale = Vector3(r, 0.5 + 2.5 * ratio, r)
	dome.rotation.y += 0.01
	var hit: float = clampf(n["shield_loss"] / 30.0, 0.0, 1.0)
	dome.transparency = (0.55 if n["shield_up"] else 0.85) - 0.4 * hit + 0.05 * sin(sim.time * 3.0)


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
		arc.material_override = Mats.glow(arc_col, 0.9)
		arc.position = n["pos"] + Vector3(0, 0.3, 0)
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
	if n["relay"] == "rotation":
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
		var blink := 0.5 + 0.5 * sin(sim.time * (4.0 + 12.0 * (1.0 - sim.last_stand_warn_t / Rules.LAST_STAND_WARNING)))
		ring.position = n["pos"] + Vector3(0, 0.3, 0)
		ring.scale = Vector3.ONE * (Rules.R + 0.9)
		ring.transparency = 0.2 + 0.5 * blink
		for link in sim.adj[id]:                        # threatened decks flash red
			var edge_i: int = link[1]
			var mat: Material = Mats.light_color(Rules.state_color("warn")) if blink > 0.5 else null
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
			continue                                      # classic: _half_trims owns the lights
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
	## lip thins into strands and drops - here the patches tilt, drop and trail droplets).
	var faction: String = ev["faction"]
	hordes.load_faction(faction)
	var mesh: Mesh = hordes.meshes[faction].get("body_a_lod1", null)
	var seat: String = ev["seat"]
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


func _waterfall(seat: String, radius: float, seconds: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = 0.22
	m.height = 0.44
	m.radial_segments = 6
	m.rings = 3
	m.material = Mats.goo(seat if seat != "" else "A")
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


func _collapse(node_id: int) -> void:
	## Last Stand destruction: the platform and every deck it still has fall away; decks break into
	## the kit's fragment pieces, goo pours over the rim all the way round (waterfall board E).
	var n: Dictionary = sim.nodes[node_id]
	var falling: Array = vis[node_id]["parts"].duplicate()
	for key in ["build_rings", "warn_rings", "domes", "cool_arcs"]:
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
	var wf := _waterfall(n["owner"] if n["owner"] != "" else "", Rules.R, 1.8)
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


# ------------------------------------------------------------------ classic: Alpha 11 half-bridge neon
var _trims := {}             # edge -> [MeshInstance3D x4]: two edges x two halves
var _trim_mesh: BoxMesh
const NEUTRAL_TRIM := Color("ffad51")   # Alpha 11's neutral bridge trim


func _half_trims() -> void:
	## CLASSIC MODE (Daniele: "bridges need to follow Alpha 11's idea of neon lighting up half the
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
				MapBuilder.set_lights(d, Mats.light_color(Color(0.12, 0.14, 0.16), "trim_off"))
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
