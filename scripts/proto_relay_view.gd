class_name ProtoRelayView
extends Node3D
## RELAYS 3.0 PROTOTYPES - the look of the five test kinds (01 Rules/RELAYS-3.0-PROTOTYPES.md; Sim's RELAYS 3.0 section).
## PLACEHOLDER GEOMETRY until 🎨's models: every moving piece is a plain coloured mesh named after the GLB node it stands in
## for (Proto_Ferry_Hull, Proto_Conveyor_Chevron, Proto_Launcher_Pad, Proto_Launcher_Arc, Proto_Lift_Platform,
## Proto_Tilt_ExitStrip, Proto_Relay_Pointer) - swap the mesh, keep the node and its transform logic. Fx keeps the common
## relay readouts (the glyph beacon, its state colour, the warning blink, the ready / cooldown arc); this adds per kind:
##   ferry     the hull on the deck (the deck's own modules hidden: it is a gap), its light, the hull's ghost at the far
##             pier during the warning, the hull travelling with its riders
##   conveyor  chevrons running along the deck in the flow's colour, reversing through the flip; the line speed tags
##             (↑ with the flow, ↓ against) over every line head on a conveyor
##   launcher  the pad, the dotted arc to the target (ghost in the warning, bright and pulsing while armed), the throws in
##             flight as a stream of blobs in the seat's colour
##   lift      the platform rides up / down (RELAYS_PROTO.lift.rise view metres); the closed level's decks sunk with a gap
##   tilt      the platform tips toward the exit during the motion; the next exit's deck lit (bright in the warning)
##   all       a pointer over the node: the docked pier, the flow, the target, up / down, the next exit (ghosted toward the
##             next state during the warning)
## Created by main.gd only when the map has a prototype relay; synced after Fx (Fx shows / hides decks first).

const POINTER_UP := 6.2              # m over the node centre
const CHEVRON_GAP := 2.6             # m between two chevrons
const CHEVRON_SPEED := 2.4           # m/s the chevrons run at
const ARC_DOTS := 26
const FLIGHT_BLOBS := 96
const LIFT_GAP := 1.3                # m a closed lift deck stands back from the platform (plus sunk 0.9 m)

var sim: Sim
var vis: Dictionary
var _r := {}                         # relay node id -> its pieces
var _tags := {}                      # horde id -> Label3D (conveyor speed tag)
var _flights: MultiMeshInstance3D
var _t := 0.0


static func wanted(s: Sim) -> bool:
	for n in s.nodes:
		if Rules.is_proto(str(n["relay"])):
			return true
	return false


func setup(s: Sim, v: Dictionary) -> void:
	sim = s
	vis = v
	name = "ProtoRelayView"
	for n in sim.nodes:
		var k: String = n["relay"]
		if not Rules.is_proto(k):
			continue
		var id: int = n["id"]
		var r := {"kind": k, "pointer": _pointer(), "ghost_pointer": _pointer(true)}
		match k:
			"ferry":
				r["hull"] = _hull(id, false)
				r["hull_ghost"] = _hull(id, true)
			"conveyor":
				r["chev"] = _chevrons(id)
				r["phase"] = 0.0
			"launcher":
				r["pad"] = _pad(n)
				r["arc"] = _arc_dots(n)
			"lift", "tilt":
				var base := {}
				for p in vis[id]["parts"]:
					if p != null:
						base[p] = (p as Node3D).transform
				r["base"] = base
				if k == "tilt":
					r["strips"] = _exit_strips(n)
		_r[id] = r
	_flights = MultiMeshInstance3D.new()
	_flights.name = "Proto_Launcher_Flight"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 8
	blob.rings = 4
	mm.mesh = blob
	mm.instance_count = FLIGHT_BLOBS
	mm.visible_instance_count = 0
	_flights.multimesh = mm
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flights.material_override = fm
	add_child(_flights)


# ------------------------------------------------------------------ pieces
func _mat(c: Color, a := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, a)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _pointer(ghost := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Proto_Relay_Pointer" + ("_Ghost" if ghost else "")
	var pm := PrismMesh.new()                         # apex at +Y, turned to point along +X
	pm.size = Vector3(1.6, 2.6, 0.45)
	mi.mesh = pm
	mi.material_override = _mat(Color.WHITE, 0.4 if ghost else 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _aim(mi: MeshInstance3D, at: Vector3, dir: Vector3) -> void:
	## Points the pointer at `at` along `dir` (horizontal), or straight up / down when dir is vertical.
	mi.position = at
	if absf(dir.y) > 0.9:
		mi.basis = Basis(Vector3.RIGHT, 0.0 if dir.y > 0.0 else PI)
	else:
		var d := Vector3(dir.x, 0.0, dir.z).normalized()
		mi.basis = Basis(Vector3.UP, Rules.heading(d)) * Basis(Vector3.BACK, -PI / 2.0)


func _deck_ends(ei: int) -> Array:
	## [the deck's A-end, its B-end] (pier ends, world).
	var pts: Array = sim.deck_points(ei, sim.edges[ei]["a"])
	return [pts[0], pts[-1]]


func _hull(id: int, ghost: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Proto_Ferry_Hull" + ("_Ghost" if ghost else "")
	var bm := BoxMesh.new()
	var len := 4.0
	for ei in sim.controlled_edges(id):
		var ends := _deck_ends(ei)
		len = (ends[1] as Vector3).distance_to(ends[0]) * float(Rules.RELAYS_PROTO["ferry"]["hull"])
	bm.size = Vector3(len, 0.7, Rules.W + 0.4)
	mi.mesh = bm
	mi.material_override = _mat(Color("#4fd8ff"), 0.35 if ghost else 1.0)
	if not ghost:                                     # the hull's light (its state colour)
		var light := MeshInstance3D.new()
		light.name = "Light"
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		light.mesh = sm
		light.position = Vector3(0, 0.9, 0)
		light.material_override = _mat(Color.WHITE)
		mi.add_child(light)
	mi.visible = false
	add_child(mi)
	return mi


func _chevrons(id: int) -> Array:
	var out := []
	for ei in sim.controlled_edges(id):
		var ends := _deck_ends(ei)
		var L: float = (ends[1] as Vector3).distance_to(ends[0])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var pm := PrismMesh.new()
		pm.size = Vector3(1.6, 1.1, 0.12)
		mm.mesh = pm
		mm.instance_count = maxi(1, int(L / CHEVRON_GAP))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Proto_Conveyor_Chevron"
		mmi.multimesh = mm
		mmi.material_override = _mat(Color.WHITE)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		out.append({"edge": ei, "mmi": mmi, "a": ends[0], "b": ends[1], "L": L})
	return out


func _pad(n: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Proto_Launcher_Pad"
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4
	cm.bottom_radius = 2.8
	cm.height = 0.5
	mi.mesh = cm
	mi.position = (n["pos"] as Vector3) + Vector3(0, 0.3, 0)
	mi.material_override = _mat(Rules.RELAY_GHOST_COLORS["launcher"])
	add_child(mi)
	return mi


func arc_point(from: Vector3, to: Vector3, k: float) -> Vector3:
	var d := from.distance_to(to)
	var apex := maxf(8.0, 0.35 * d)
	return from.lerp(to, k) + Vector3(0, 4.0 * apex * k * (1.0 - k) + 1.0, 0)


func _arc_dots(n: Dictionary) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = ARC_DOTS
	var tgt: int = int(n["proto"].get("target", -1))
	if tgt >= 0:
		for k in range(ARC_DOTS):
			var p := arc_point(n["pos"], sim.nodes[tgt]["pos"], float(k + 1) / float(ARC_DOTS + 1))
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Proto_Launcher_Arc"
	mmi.multimesh = mm
	mmi.material_override = _mat(Rules.RELAY_GHOST_COLORS["launcher"], 0.5)
	mmi.visible = false
	add_child(mmi)
	return mmi


func _exit_strips(n: Dictionary) -> Dictionary:
	var out := {}
	for x in n["proto"].get("exits", []):
		var ei := sim._edge_index(n["id"], int(x))
		if ei < 0:
			continue
		var line: Array = sim.deck_line(ei)
		var a: Vector3 = line[0]
		var b: Vector3 = line[-1]
		var mi := MeshInstance3D.new()
		mi.name = "Proto_Tilt_ExitStrip"
		var bm := BoxMesh.new()
		bm.size = Vector3(a.distance_to(b), 0.12, Rules.W * 0.55)
		mi.mesh = bm
		mi.position = (a + b) * 0.5 + Vector3(0, 0.42, 0)
		mi.rotation.y = Rules.heading((b - a).normalized())
		mi.material_override = _mat(Rules.RELAY_GHOST_COLORS["tilt"], 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		out[int(x)] = mi
	return out


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	_t += dt
	for id in _r:
		var n: Dictionary = sim.nodes[id]
		var r: Dictionary = _r[id]
		var gone: bool = sim.collapsed.get(id, false)
		var phase: String = n["relay_phase"]
		var blink := int(sim.time * 5.0) % 2 == 0
		var col := Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
		var next_col := Rules.state_color(sim.relay_state_key(n, n["relay_pending"]))
		var top: Vector3 = (n["pos"] as Vector3) + Vector3(0, POINTER_UP, 0)
		var p: MeshInstance3D = r["pointer"]
		var gp: MeshInstance3D = r["ghost_pointer"]
		p.visible = not gone
		gp.visible = not gone and phase == "warning"
		(p.material_override as StandardMaterial3D).albedo_color = col
		(p.material_override as StandardMaterial3D).emission = col
		(gp.material_override as StandardMaterial3D).albedo_color = Color(next_col.r, next_col.g, next_col.b, 0.75 if blink else 0.3)
		(gp.material_override as StandardMaterial3D).emission = next_col
		match r["kind"]:
			"ferry":
				_ferry(n, r, top, phase, blink, gone)
			"conveyor":
				_conveyor(n, r, top, phase, blink, dt, gone)
			"launcher":
				_launcher(n, r, top, phase, blink, gone)
			"lift":
				_lift(n, r, top, phase)
			"tilt":
				_tilt(n, r, top, phase, blink, gone)
	_flight_stream()
	_speed_tags()


func _ferry(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, gone: bool) -> void:
	for ei in sim.controlled_edges(n["id"]):
		for d in vis["edge_decks"][ei]:              # the deck is a gap: the hull is the only floor
			(d as Node3D).visible = false
		var ends := _deck_ends(ei)
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var u := (b - a).normalized()
		var L := a.distance_to(b)
		var H := L * float(Rules.RELAYS_PROTO["ferry"]["hull"])
		var at := func(f: float) -> Vector3: return a + u * (H * 0.5 + f * (L - H)) + Vector3(0, -0.1, 0)
		var hull: MeshInstance3D = r["hull"]
		hull.visible = not gone and not sim.demolished.has(ei)
		hull.position = at.call(sim.ferry_pos(n["id"]))
		hull.rotation.y = Rules.heading(u)
		hull.position.y += 0.08 * sin(sim.time * 1.7)  # it floats
		var lc := Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
		var light: MeshInstance3D = hull.get_node("Light")
		(light.material_override as StandardMaterial3D).emission = lc
		(light.material_override as StandardMaterial3D).albedo_color = lc
		(light.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if phase != "" else 1.6
		var ghost: MeshInstance3D = r["hull_ghost"]
		ghost.visible = not gone and phase == "warning"
		ghost.position = at.call(float(n["relay_pending"]))
		ghost.rotation.y = hull.rotation.y
		(ghost.material_override as StandardMaterial3D).albedo_color.a = 0.55 if blink else 0.25
		var dock: Vector3 = a if int(n["relay_index"]) == 0 else b
		_aim(r["pointer"], top, dock - (n["pos"] as Vector3))
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), (b if int(n["relay_pending"]) == 1 else a) - (n["pos"] as Vector3))


func _conveyor(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, dt: float, gone: bool) -> void:
	var sign := 1.0 if int(n["relay_index"]) == 0 else -1.0          # +1: flowing A -> B
	var speed := sign
	if phase == "moving":                              # the arrows reverse through the flip
		var p := float(n["relay_anim"].get("progress", 0.0))
		speed = lerpf(-sign, sign, p)                  # (relay_index is already the new direction)
	r["phase"] = float(r["phase"]) + dt * CHEVRON_SPEED * speed
	var col := Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
	if phase == "warning":
		col = Rules.state_color(sim.relay_state_key(n, n["relay_pending"])) if blink else Rules.state_color("warn")
	for c in r["chev"]:
		var mmi: MultiMeshInstance3D = c["mmi"]
		mmi.visible = not gone and sim.is_edge_open(int(c["edge"]))
		(mmi.material_override as StandardMaterial3D).albedo_color = col
		(mmi.material_override as StandardMaterial3D).emission = col
		var a: Vector3 = c["a"]
		var b: Vector3 = c["b"]
		var u := (b - a).normalized()
		var L: float = c["L"]
		var face := u * (1.0 if speed >= 0.0 else -1.0)
		var basis := Basis(Vector3.UP, Rules.heading(face)) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, -PI / 2.0)   # flat, apex along the flow
		var mm: MultiMesh = mmi.multimesh
		for k in range(mm.instance_count):
			var s := fposmod(float(k) * CHEVRON_GAP + float(r["phase"]), L)
			mm.set_instance_transform(k, Transform3D(basis, a + u * s + Vector3(0, 0.36, 0)))
	var first: Array = sim.controlled_edges(n["id"])
	if not first.is_empty():
		var c0: Dictionary = r["chev"][0]
		var flow: Vector3 = ((c0["b"] as Vector3) - (c0["a"] as Vector3)) * sign
		_aim(r["pointer"], top, flow)
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), -flow)


func _launcher(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, gone: bool) -> void:
	var tgt: int = int(n["proto"].get("target", -1))
	var arc: MultiMeshInstance3D = r["arc"]
	var pad: MeshInstance3D = r["pad"]
	pad.visible = not gone
	var armed := phase == "moving"
	arc.visible = not gone and tgt >= 0 and (phase == "warning" or armed)
	var ac: Color = Rules.RELAY_GHOST_COLORS["launcher"]
	var m := arc.material_override as StandardMaterial3D
	m.albedo_color = Color(ac.r, ac.g, ac.b, (0.9 if blink else 0.35) if phase == "warning" else 0.85)
	m.emission_energy_multiplier = 3.0 if armed else 1.4
	var pm := pad.material_override as StandardMaterial3D
	var k := 0.5 + 0.5 * sin(sim.time * 6.0)        # the armed pad pulses (its ready ring)
	pm.emission_energy_multiplier = (1.5 + 3.0 * k) if armed else (1.0 if n["relay_cd"] > 0.0 else 1.8)
	pad.scale = Vector3.ONE * ((1.0 + 0.08 * k) if armed else 1.0)
	if tgt >= 0:
		_aim(r["pointer"], top, (sim.nodes[tgt]["pos"] as Vector3) - (n["pos"] as Vector3))
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), (sim.nodes[tgt]["pos"] as Vector3) - (n["pos"] as Vector3))


func _flight_stream() -> void:
	var mm: MultiMesh = _flights.multimesh
	var flight: float = float(Rules.RELAYS_PROTO["launcher"]["flight"])
	var k := 0
	for f in sim.flights:
		var from: Vector3 = sim.nodes[int(f["from"])]["pos"]
		var to: Vector3 = sim.nodes[int(f["to"])]["pos"]
		var blobs := clampi(int(ceilf(Rules.shown(float(f["left"])))), 1, 6)
		var col := Rules.seat_color(str(f["seat"]))
		for b in range(blobs):
			if k >= FLIGHT_BLOBS:
				break
			var age := sim.time - float(f["t0"]) - b * 0.12
			var q := clampf(age / flight, 0.0, 1.0)
			if age < 0.0:
				continue
			var pos := arc_point(from, to, q) if q < 1.0 else to + Vector3(0, 1.0 + 3.0 * maxf(0.0, 1.0 - (age - flight) / 0.4), 0)
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.1), pos))
			mm.set_instance_color(k, col)
			k += 1
	mm.visible_instance_count = k


func _lift(n: Dictionary, r: Dictionary, top: Vector3, phase: String) -> void:
	var id: int = n["id"]
	var level := float(int(n["relay_index"]))
	if phase == "moving":                             # relay_index is already the new level
		var p := smoothstep(0.0, 1.0, float(n["relay_anim"].get("progress", 0.0)))
		level = lerpf(1.0 - level, level, p)
	var rise: float = float(Rules.RELAYS_PROTO["lift"]["rise"]) * level
	if not sim.collapsed.get(id, false):
		var base: Dictionary = r["base"]
		for part in base:
			if is_instance_valid(part):
				(part as Node3D).transform = (base[part] as Transform3D).translated(Vector3(0, rise, 0))
	for ei in sim.controlled_edges(id):              # a closed level's deck: sunk, standing back from the platform
		if sim.collapsed.get(sim.edges[ei]["a"], false) or sim.collapsed.get(sim.edges[ei]["b"], false):
			continue
		var open: bool = sim._edge_open_at(ei, int(n["relay_index"]))
		var away: Vector3 = ((sim.nodes[sim._other_end(ei, id)]["pos"] as Vector3) - (n["pos"] as Vector3)).normalized()
		var off := 0.0
		if phase == "moving":
			var p2 := smoothstep(0.0, 1.0, float(n["relay_anim"].get("progress", 0.0)))
			off = p2 if not open else 1.0 - p2
		elif not open:
			off = 1.0
		var decks: Array = vis["edge_decks"][ei]
		for k in range(decks.size()):
			var d: Node3D = decks[k]
			d.visible = true
			d.transform = (vis["edge_base"][ei][k] as Transform3D).translated(away * LIFT_GAP * off - Vector3(0, 0.9 * off, 0))
	_aim(r["pointer"], top + Vector3(0, rise, 0), Vector3.UP if int(n["relay_index"]) == 1 else Vector3.DOWN)
	_aim(r["ghost_pointer"], top + Vector3(0, rise + 0.8, 0), Vector3.UP if int(n["relay_pending"]) == 1 else Vector3.DOWN)


func _tilt(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, gone: bool) -> void:
	var id: int = n["id"]
	var next := sim.tilt_next_exit(id)
	var tipping: int = int(n.get("tilt_exit", next)) if phase == "moving" else next
	var c: Vector3 = n["pos"]
	var angle := 0.0
	var axis := Vector3.RIGHT
	if phase == "moving" and tipping >= 0:
		var dir := ((sim.nodes[tipping]["pos"] as Vector3) - c).normalized()
		axis = Vector3.UP.cross(dir).normalized()
		angle = -0.22 * sin(PI * clampf(float(n["relay_anim"].get("progress", 0.0)), 0.0, 1.0))
	if not gone:
		var base: Dictionary = r["base"]
		for part in base:
			if is_instance_valid(part):
				var t: Transform3D = base[part]
				var rot := Basis(axis, angle)
				(part as Node3D).transform = Transform3D(rot * t.basis, c + rot * (t.origin - c))
	for x in r["strips"]:
		var mi: MeshInstance3D = r["strips"][x]
		var lit := int(x) == tipping
		mi.visible = not gone and lit
		var m := mi.material_override as StandardMaterial3D
		var bright := phase != "" and (blink or phase == "moving")
		m.albedo_color.a = 0.85 if bright else 0.35
		m.emission_energy_multiplier = 3.0 if bright else 1.0
	if next >= 0:
		_aim(r["pointer"], top, (sim.nodes[next]["pos"] as Vector3) - c)
		var after: int = int(n["proto"]["exits"][int(n["relay_pending"]) % (n["proto"]["exits"] as Array).size()])
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), (sim.nodes[after]["pos"] as Vector3) - c)


func _speed_tags() -> void:
	## Conveyor: a small ↑ (with the flow) / ↓ (against) over every line head on a conveyor deck.
	var seen := {}
	for h in sim.hordes:
		var sense: Array = sim.conveyor_sense(h)
		if int(sense[0]) == 0:
			continue
		var hid: int = h["id"]
		seen[hid] = true
		var l: Label3D = _tags.get(hid)
		if l == null:
			l = Label3D.new()
			l.font = Fx.SYMBOL_FONT
			l.font_size = 64
			l.pixel_size = 0.03
			l.outline_size = 14
			l.outline_modulate = Color(0.02, 0.02, 0.05, 0.9)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.render_priority = 3
			add_child(l)
			_tags[hid] = l
		var with := int(sense[0]) > 0
		l.text = "↑" if with else "↓"
		l.modulate = Rules.state_color("cAB") if with else Rules.state_color("warn")
		l.position = (Sim.sample(h, h["s"])[0] as Vector3) + Vector3(0, 2.6, 0)
	for hid in _tags.keys():
		if not seen.has(hid):
			(_tags[hid] as Label3D).queue_free()
			_tags.erase(hid)
