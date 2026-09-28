class_name MonsterView
extends Node3D
## Monsters and their hubs in the world (Structures 2.1, 0.19.0 "Alpha 19"; GAME-BIBLE sec17). Pure view,
## driven only by the Sim's state - sim.monsters, each hub node's "structure" / "monster_ready_t" /
## "hub_monster" and the monster fx events - so online guests, who apply the host's snapshots (Net carries
## the monsters, their path is rebuilt from the route), see exactly the same thing.
##   * A hub (MonsterVat_<RACE>, or the owner's Hatchery / Pit look) holds its next monster crouched in the
##     goo pool on the plinth: small while it charges, growing to full size as the cooldown runs out. READY
##     (0.19.2): it stands up tall facing the viewer and flexes on a beat, the pool glows bright in the owner's
##     colour and a ring rises off it (with the HUD's hub icon).
##   * Launch: the hub's gate (the model's `*_Gate` child) slides straight down between the jambs, the
##     monster walks down off its stand and out through the opening onto its route (the first metres play
##     a little faster so it catches up with the Sim's monster before the first deck), and the gate rises
##     again behind it.
##   * On the way: the monster's own look (Monster_<RACE> or the owner's alt) in its owner's colours - the
##     body wears the slimmed minion's texture with the column look (UnitView.style), the evolution the
##     owner's LIGHT / OOZE - hops with a squash-and-stretch at monster scale and faces where it walks.
##     Its route is lit in red for everyone from the launch to the end node (a pulsing ring there), the
##     walked part going dark behind it. Every kick (monster_kick) whacks sparks off it; the bodies it kicks
##     fly sideways off the deck into the void (Fx._fall_horde, the fall event's "monster" key).
##   * It falls (state "falling": the deck under it went, the platform dropped) with a tumble into the void;
##     at its end node (monster_take) it stomps in with a burst in its owner's colour and is gone.

const WAVE := 5.5                    # rad/s: the hop (the minions' is 8: a heavier beast)
const HOP := 0.34                    # m at the top of a hop
const SQUASH := 0.12                 # squash and stretch on the same wave
const ROLL := 0.05
const TURN_RATE := 7.0               # facing eases toward the walking direction (1/s)
const OUT_S := 7.0                   # m of the Sim's path the walk-out is spread over (capped at the first deck)
const JOIN_S := 1.0                  # m: where the walk-out meets the Sim's path (just past the gate)
const GATE_DROP := 2.4               # m the gate slides down (the opening is >= 2.4 m)
const GATE_OPEN := 0.35              # s to slide down
const GATE_CLOSE := 0.6              # s to rise again
const CHARGE_MIN := 0.38             # a freshly launched hub's next monster starts at this size
const FALL_G := 22.0
const FALL_DROP := 30.0
const ROUTE_W := 0.9                 # m: the red route ribbon's width
const ROUTE_Y := 0.32                # m above the deck
const ROUTE_RED := Color(1.0, 0.13, 0.08)
const FLARE_SHADER := preload("res://shaders/flare.gdshader")

var world: Node3D
var sim: Sim
var vis: Dictionary
var combat: Node3D                   # CombatFx: its spark MultiMesh throws the bursts
var _mons := {}                      # monster id -> {node, body, key, yaw, fall_t, fall_pos, done_t, route, ring}
var _hubs := {}                      # node id -> {vn, gate, rest, k, idle, idle_key, launched_t}
var _route_mat: StandardMaterial3D
var _ring_mesh: TorusMesh


func setup(w: Node3D, s: Sim, v: Dictionary, c: Node3D) -> void:
	world = w
	sim = s
	vis = v
	combat = c
	_route_mat = StandardMaterial3D.new()
	_route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_route_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_route_mat.vertex_color_use_as_albedo = true
	_route_mat.albedo_color = Color.WHITE
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 4


# ------------------------------------------------------------------ per frame
func sync(dt: float, _cam: Camera3D) -> void:
	## main (the 0.19.0 views block), before the frame's fx events are drained: reads them too.
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	for ev in sim.fx_events:
		match ev["type"]:
			"monster_kick":
				_kick_burst(ev)
			"monster_take":
				_take_burst(ev)
	_sync_hubs(dt)
	_sync_monsters(dt)
	PerfProfile.lap("monster", _pt)


# ------------------------------------------------------------------ hubs
func _sync_hubs(dt: float) -> void:
	var seen := {}
	for n in sim.nodes:
		var id: int = n["id"]
		if n.get("structure", "") != "monster_hub" or n["build_kind"] != "" or sim.collapsed.get(id, false):
			continue
		var entry: Dictionary = vis.get(id, {})
		var vn = entry.get("vat_node")
		if not is_instance_valid(vn) or not str(entry.get("model_key", "")).contains("Monster"):
			continue
		seen[id] = true
		var h: Dictionary = _hubs.get(id, {})
		if h.is_empty() or h["vn"] != vn:
			if not h.is_empty():
				for k in ["idle", "glow", "ring"]:
					if is_instance_valid(h[k]):
						(h[k] as Node).queue_free()
			h = _new_hub(vn as Node3D, str(entry["model_key"]))
			_hubs[id] = h
		# the gate: down while its monster walks out, up again once it is clear
		var m := _monster(int(n["hub_monster"]))
		var out: bool = not m.is_empty() and m["state"] == "walking" and float(m["s"]) < _out_len(m) * 0.75
		h["k"] = clampf(float(h["k"]) + (dt / GATE_OPEN if out else -dt / GATE_CLOSE), 0.0, 1.0)
		var gate: Node3D = h["gate"]
		if gate:
			gate.position = (h["rest"] as Vector3) + Vector3(0, -GATE_DROP * smoothstep(0.0, 1.0, h["k"]), 0)
		# the next monster idling in the pool: grows while the hub charges, hops when READY
		var idle_key := Cosmetics.key_for("monster", n["owner"], 1)
		if idle_key != h["idle_key"]:
			if is_instance_valid(h["idle"]):
				(h["idle"] as Node).queue_free()
			h["idle"] = _make_monster(idle_key, n["owner"])
			h["idle_key"] = idle_key
		var idle: Node3D = h["idle"]
		var home := int(n["hub_monster"]) < 0 or m.is_empty()
		idle.visible = home and n["owner"] != ""
		var glow: MeshInstance3D = h["glow"]
		var ring: MeshInstance3D = h["ring"]
		glow.visible = false
		ring.visible = false
		if not idle.visible:
			continue
		var left: float = float(n["monster_ready_t"]) - sim.time
		var charge := clampf(1.0 - left / maxf(Rules.MONSTER_COOLDOWN, 0.1), 0.0, 1.0)
		var ready: bool = left <= 0.0
		var size := lerpf(CHARGE_MIN, 1.0, smoothstep(0.0, 1.0, charge))
		var root := vn as Node3D
		var stand: Vector3 = root.global_transform * (h["stand"] as Vector3)
		var t := sim.time + float(id) * 0.37
		var yaw := Rules.heading(Rules.front_dir()) + PI / 2.0
		var col := Rules.seat_color(n["owner"])
		if ready:
			# READY (0.19.2, with the HUD's hub icon): it stands up tall facing you, flexes every beat, and the
			# pool under it glows bright in its owner's colour, a ring rising off it
			var beat := fmod(t, 1.4) / 1.4
			var flex := sin(clampf(beat / 0.25, 0.0, 1.0) * PI)
			var stretch := 0.12 * flex
			idle.global_transform = Transform3D(Basis(Vector3.UP, yaw + 0.25 * sin(t * 0.9))
					* Basis.from_scale(Vector3(1.0 - stretch * 0.4, 1.0 + stretch, 1.0 - stretch * 0.4) * 1.1 * root.scale.y),
					stand + Vector3(0, 0.12 + 0.35 * flex, 0))
			glow.visible = true
			glow.position = stand + Vector3(0, 0.08, 0)
			glow.scale = Vector3.ONE * (4.2 + 0.8 * sin(t * 3.0))
			var gm: ShaderMaterial = glow.material_override
			gm.set_shader_parameter("color", col.lerp(Color.WHITE, 0.25))
			gm.set_shader_parameter("intensity", 1.5 + 0.7 * sin(t * 3.0))
			ring.visible = true
			ring.position = stand + Vector3(0, 0.1 + 2.4 * beat, 0)
			ring.scale = Vector3.ONE * lerpf(1.2, 2.2, beat)
			ring.transparency = beat
			ring.material_override = Mats.glow(col, 0.9)
		else:                                        # charging: crouched in the pool, breathing slowly
			var wave := sin(t * 1.6)
			var sq := wave * SQUASH * 0.5 + 0.12
			idle.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.45) * size * root.scale.y),
					stand + Vector3(0, maxf(0.0, wave) * HOP * 0.15, 0))
	for id in _hubs.keys():
		if not seen.has(id):
			for k in ["idle", "glow", "ring"]:
				if is_instance_valid(_hubs[id][k]):
					(_hubs[id][k] as Node).queue_free()
			_hubs.erase(id)


func _new_hub(vn: Node3D, key: String) -> Dictionary:
	var pt := Cosmetics.points(key)
	var gate: Node3D = null
	for c in vn.find_children("*_Gate", "Node3D", true, false):   # the pivot read from the model itself
		gate = c
		break
	var rest: Vector3 = gate.position if gate else pt.get("gate", Vector3(0, 0.31, 2.3))
	var glow := MeshInstance3D.new()                  # the READY pool glow
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	glow.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = FLARE_SHADER
	gm.set_shader_parameter("mode", 1)
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	add_child(glow)
	var ring := MeshInstance3D.new()                  # and the ring rising off it
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	return {"vn": vn, "gate": gate, "rest": rest, "k": 0.0, "idle": null, "idle_key": "", "glow": glow, "ring": ring,
			"stand": pt.get("stand", Vector3(0, 1.44, 0)), "gate_z": rest.z}


# ------------------------------------------------------------------ monsters
func _monster(id: int) -> Dictionary:
	if id < 0:
		return {}
	for m in sim.monsters:
		if int(m["id"]) == id:
			return m
	return {}


func _sync_monsters(dt: float) -> void:
	var seen := {}
	for m in sim.monsters:
		var id: int = m["id"]
		seen[id] = true
		var v: Dictionary = _mons.get(id, {})
		if v.is_empty():
			v = _new_monster(m)
			_mons[id] = v
		match str(m["state"]):
			"walking":
				_walk(m, v, dt)
			"falling":
				_fall(m, v, dt)
			_:                                         # done: stomps into its end node (or finished its fall)
				_done(m, v, dt)
		_route(m, v)
	for id in _mons.keys():
		if not seen.has(id):
			_free_monster(_mons[id])
			_mons.erase(id)


func _new_monster(m: Dictionary) -> Dictionary:
	var seat: String = m["seat"]
	var key := Cosmetics.key_for("monster", seat, 1)
	var node := _make_monster(key, seat)
	var route := MeshInstance3D.new()
	route.mesh = ImmediateMesh.new()
	route.material_override = _route_mat
	route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(route)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = Mats.glow(ROUTE_RED, 0.9, true, "monster_ring")
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var hub: Dictionary = _hubs.get(int(m["hub"]), {})
	return {"node": node, "key": key, "yaw": Rules.heading(Rules.front_dir()) + PI / 2.0, "route": route, "ring": ring,
			"fall_t": -1.0, "fall_pos": Vector3.ZERO, "fall_spin": Vector3.ZERO, "done_t": -1.0, "last": Vector3.INF,
			"hub": hub.duplicate() if not hub.is_empty() else {}, "t": 0.0}


func _free_monster(v: Dictionary) -> void:
	for k in ["node", "route", "ring"]:
		if is_instance_valid(v[k]):
			(v[k] as Node).queue_free()


func _make_monster(key: String, seat: String) -> Node3D:
	## A monster model in `seat`'s colours: the evolution takes the owner's LIGHT / OOZE (MapBuilder.apply_owner),
	## the body (the minion mesh inside) the slimmed minion's texture with the column look.
	var node := MapBuilder.piece(key)
	add_child(node)
	dress(node, sim.factions.get(seat, "null"), seat)
	return node


static var _tex := {}                # faction -> minion albedo Texture2D (shared with the ARMIES previews)


static func dress(node: Node3D, faction: String, seat: String) -> void:
	## Owner colours on a monster model (also Cosmetics' ARMIES preview): evolution LIGHT / OOZE, body = minion texture.
	MapBuilder.apply_owner([node], seat)
	var tex := _tex_for(faction)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if String(mi.name).ends_with("_Evolution") or tex == null:
			continue
		var m: ShaderMaterial = (Mats.creature(faction, seat, tex) as ShaderMaterial).duplicate()
		UnitView.style(m, faction, seat, Rules.goo_look())
		(mi as MeshInstance3D).material_override = m


static func _tex_for(faction: String) -> Texture2D:
	if not _tex.has(faction):
		_tex[faction] = null
		if Rules.FACTIONS.has(faction):
			var root: Node = (load("res://assets/units/%s.glb" % faction) as PackedScene).instantiate()
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				var src := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
				_tex[faction] = src.albedo_texture if src else null
				break
			root.free()
	return _tex[faction]


func _out_len(m: Dictionary) -> float:
	## Metres of the Sim's path the walk-out is spread over: OUT_S, but never onto the first deck.
	var spans: Array = m.get("spans", [])
	var first: float = float(spans[0]["s0"]) if not spans.is_empty() else OUT_S
	return clampf(minf(OUT_S, first - 0.2), JOIN_S + 0.5, OUT_S)


func _exit_points(m: Dictionary, v: Dictionary) -> Array:
	## The walk-out in world space: the stand in the pool, its front edge, down past the gate, just outside.
	var hub: Dictionary = v["hub"]
	if hub.is_empty() or not is_instance_valid(hub.get("vn")):
		return []
	var root: Node3D = hub["vn"]
	var xf := root.global_transform
	var stand: Vector3 = hub["stand"]
	var gz: float = hub["gate_z"]
	return [xf * stand, xf * Vector3(0, stand.y, gz * 0.55), xf * Vector3(0, 0.06, gz + 0.55)]


func _view_pos(m: Dictionary, v: Dictionary) -> Vector3:
	var s: float = m["s"]
	if not m.has("cum"):
		return m["pos"]
	var out := _out_len(m)
	var ex := _exit_points(m, v)
	if s >= out or ex.is_empty():
		return Sim.sample(m, s)[0]
	var lens := [0.0]
	for i in range(1, ex.size()):
		lens.append(float(lens[-1]) + (ex[i] as Vector3).distance_to(ex[i - 1]))
	var le: float = lens[-1]
	var u := s * (le + out - JOIN_S) / out            # the walk-out plays a little faster, then it is the Sim's
	if u >= le:
		return Sim.sample(m, JOIN_S + u - le)[0]
	for i in range(1, ex.size()):
		if u <= float(lens[i]):
			return (ex[i - 1] as Vector3).lerp(ex[i], (u - float(lens[i - 1])) / maxf(float(lens[i]) - float(lens[i - 1]), 0.001))
	return ex[-1]


func _walk(m: Dictionary, v: Dictionary, dt: float) -> void:
	var node: Node3D = v["node"]
	node.visible = true
	v["t"] = float(v["t"]) + dt
	var p := _view_pos(m, v)
	var last: Vector3 = v["last"]
	var d := (p - last) * Vector3(1, 0, 1) if last != Vector3.INF else (m.get("dir", Vector3.FORWARD) as Vector3)
	if d.length() > 0.002:
		v["yaw"] = lerp_angle(float(v["yaw"]), atan2(d.x, d.z), minf(1.0, dt * TURN_RATE))
	v["last"] = p
	var t: float = v["t"]
	var wave := sin(t * WAVE)
	var hop := maxf(0.0, wave) * HOP
	var sq := wave * SQUASH
	node.global_transform = Transform3D(Basis(Vector3.UP, v["yaw"]) * Basis(Vector3(0, 0, 1), wave * ROLL)
			* Basis.from_scale(Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.45)), p + Vector3(0, hop, 0))


func _fall(m: Dictionary, v: Dictionary, dt: float) -> void:
	## The deck (or platform) went from under it: a tumble into the void.
	var node: Node3D = v["node"]
	if float(v["fall_t"]) < 0.0:
		v["fall_t"] = 0.0
		v["fall_pos"] = node.global_position if node.visible else (m["pos"] as Vector3)
		v["fall_spin"] = Vector3(randf_range(-3.5, 3.5), randf_range(-1.5, 1.5), randf_range(-3.5, 3.5))
		v["fall_rot"] = node.rotation
		if combat:                                   # a heave of goo off the lip
			for i in range(18 if not Rules.low_detail else 9):
				var a := randf() * TAU
				combat._spark(v["fall_pos"] + Vector3(0, 1.0, 0), Vector3(cos(a), randf_range(0.5, 1.5), sin(a)).normalized() * randf_range(3.0, 7.0),
						Rules.seat_color(m["seat"]) * 1.2, randf_range(0.25, 0.45), randf_range(0.5, 0.9), 18.0)
	v["fall_t"] = float(v["fall_t"]) + dt
	var t: float = v["fall_t"]
	var y := minf(0.5 * FALL_G * t * t, FALL_DROP)
	node.visible = y < FALL_DROP
	node.global_position = (v["fall_pos"] as Vector3) + Vector3(0, -y, 0)
	node.rotation = (v["fall_rot"] as Vector3) + (v["fall_spin"] as Vector3) * t
	node.scale = Vector3.ONE * lerpf(1.0, 0.6, clampf(t / 1.4, 0.0, 1.0))


func _done(m: Dictionary, v: Dictionary, dt: float) -> void:
	var node: Node3D = v["node"]
	if float(v["fall_t"]) >= 0.0:                     # it fell: keep tumbling out of sight
		_fall(m, v, dt)
		return
	if float(v["done_t"]) < 0.0:
		v["done_t"] = 0.0
	v["done_t"] = float(v["done_t"]) + dt
	var k := clampf(float(v["done_t"]) / 0.45, 0.0, 1.0)   # a stomp (squash) and it melts into its prize
	var sq := sin(k * PI) * 0.35
	node.scale = Vector3(1.0 + sq, maxf(0.05, (1.0 - sq) * (1.0 - k * k)), 1.0 + sq)
	node.visible = k < 1.0


func _route(m: Dictionary, v: Dictionary) -> void:
	## The red route everyone sees from the launch: the part still to walk, and a pulsing ring on the end node.
	var route: MeshInstance3D = v["route"]
	var ring: MeshInstance3D = v["ring"]
	var walking: bool = m["state"] == "walking" and m.has("pts")
	route.visible = walking
	ring.visible = walking
	if not walking:
		return
	var pts: PackedVector3Array = m["pts"]
	var cum: PackedFloat32Array = m["cum"]
	var s: float = m["s"]
	var im := route.mesh as ImmediateMesh
	im.clear_surfaces()
	var pulse := 0.55 + 0.25 * sin(sim.time * 6.0)
	var strip := []
	strip.append(Sim.sample(m, s)[0])
	for i in range(pts.size()):
		if cum[i] > s + 0.05:
			strip.append(pts[i])
	if strip.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(strip.size()):
			var a: Vector3 = strip[maxi(i - 1, 0)]
			var b: Vector3 = strip[mini(i + 1, strip.size() - 1)]
			var f := (b - a) * Vector3(1, 0, 1)
			var side := f.normalized().cross(Vector3.UP) * (ROUTE_W * 0.5) if f.length() > 0.001 else Vector3(ROUTE_W * 0.5, 0, 0)
			var c := ROUTE_RED
			c.a = pulse * (0.55 if i == 0 else 1.0)
			var p: Vector3 = (strip[i] as Vector3) + Vector3(0, ROUTE_Y, 0)
			im.surface_set_color(c)
			im.surface_add_vertex(p - side)
			im.surface_set_color(c)
			im.surface_add_vertex(p + side)
		im.surface_end()
	var target: Dictionary = sim.nodes[int(m["target"])]
	ring.position = (target["pos"] as Vector3) + Vector3(0, 0.4, 0)
	ring.scale = Vector3.ONE * (Rules.R + 0.8 + 0.5 * sin(sim.time * 5.0))
	ring.transparency = 1.0 - pulse


# ------------------------------------------------------------------ bursts
func _kick_burst(ev: Dictionary) -> void:
	## A whack where the monster meets bodies: sparks and goo in the victims' colour off its front.
	if combat == null:
		return
	var pos: Vector3 = ev.get("pos", Vector3.ZERO)
	var col := Rules.seat_color(str(ev.get("seat_hit", ""))) if str(ev.get("seat_hit", "")) != "" else Rules.NEUTRAL
	var sparks := clampi(int(ev.get("shown", 1)) * 2 + 4, 4, 24)
	if Rules.low_detail:
		sparks /= 2
	for i in range(sparks):
		var a := randf() * TAU
		var v := Vector3(cos(a), randf_range(0.5, 1.4), sin(a)).normalized() * randf_range(4.0, 9.0)
		combat._spark(pos + Vector3(0, 1.1, 0), v, (col if randf() < 0.6 else Color(1.0, 0.9, 0.72)) * 1.3,
				randf_range(0.18, 0.36), randf_range(0.3, 0.6), 16.0)
	combat._spark(pos + Vector3(0, 1.2, 0), Vector3.ZERO, col.lerp(Color.WHITE, 0.5) * 1.5, 2.2, 0.18, 0.0)
	# the end node's garrison (the kick at a platform's centre): its bodies are thrown off the rim all round
	var seat := str(ev.get("seat_hit", ""))
	var fx = world.get("fx") if world else null
	if seat == "" or fx == null or not sim.factions.has(seat):
		return
	for n in sim.nodes:
		if (n["pos"] as Vector3).distance_to(pos) < 0.05:
			var bodies := clampi(int(ev.get("shown", 1)), 1, 40)
			var ring := []
			for i in range(bodies):
				var a := TAU * i / bodies + randf() * 0.3
				ring.append(pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.6, Rules.R - 0.6))
			var i := 0
			for b in fx._spawn_bodies(sim.factions[seat], seat, ring, bodies):
				fx._fling_body(b[0], ring[i % ring.size()], pos, 1.0 if i % 2 == 0 else -1.0, (b[0] as MeshInstance3D).scale * 0.7)
				i += 1
			break


func _take_burst(ev: Dictionary) -> void:
	## The monster reaches its end node: a burst and a shock ring in its owner's colour.
	if combat == null:
		return
	var n: Dictionary = sim.nodes[int(ev["node"])]
	var col := Rules.seat_color(str(ev.get("seat", "")))
	var top: Vector3 = (n["pos"] as Vector3) + Vector3(0, 2.5, 0)
	for i in range(50 if not Rules.low_detail else 25):
		var a := randf() * TAU
		var v := Vector3(cos(a), randf_range(0.4, 1.8), sin(a)).normalized() * randf_range(5.0, 12.0)
		combat._spark(top, v, (col if randf() < 0.7 else Color(1.0, 0.9, 0.72)) * 1.4, randf_range(0.2, 0.42), randf_range(0.5, 1.0), 14.0)
	combat._spark(top, Vector3.ZERO, col.lerp(Color.WHITE, 0.45) * 1.6, 5.0, 0.3, 0.0)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = Mats.glow(col, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = (n["pos"] as Vector3) + Vector3(0, 0.35, 0)
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * Rules.R * 2.2, 0.7).from(Vector3.ONE * 2.0)
	tw.tween_property(ring, "transparency", 1.0, 0.7).from(0.0)
	tw.chain().tween_callback(ring.queue_free)


# ------------------------------------------------------------------ staged looks (debug, contact sheets)
static func stage(main: Node, arg: String) -> void:
	## --stage=<what>[:<node>] (main's 0.19.0 views block, once): set a moment up for a screenshot without a
	## long simulation. Debug only - it writes the Sim directly.
	##   monster:<hub>   seat A builds a ready hub on relay node <hub> (or the first relay) and launches at once
	##                   toward the node in reach with the most enemy / neutral bodies on the way, B sends a
	##                   line into its path
	##   guns[:<k>[:<look>]]  seat A (Machinegoon look <look>) gets Machinegoons T1, T2, T3 (tiers rotated by k) and a laser on its nearest
	##                   nodes, B sends lines at them from a neighbour over an open deck
	##   skins           seat A picks a non-default look for every family: vats, two Machinegoons, laser, forge
	##                   and a ready hub on its nearest relays; the monster launches at 2.6 s
	##   relays          seat A owns every relay, the first fires at 0.6 s (ready / warning / cooling looks)
	##   vats:<look>     every free node becomes seat A's in vat look <look> (Cosmetics id), tiers 1-3 round the
	##                   map, part-filled, and each sends a line out (the bodies drop out of the tanks)
	var sim: Sim = main.get("sim")
	var what := arg.split(":")[0]
	var node := int(arg.split(":")[1]) if arg.contains(":") else -1
	match what:
		"monster":
			var hub := node
			if hub < 0:
				for n in sim.nodes:
					if n["node_kind"] == "relay":
						hub = n["id"]
						break
			if hub < 0:
				return
			var h: Dictionary = sim.nodes[hub]
			h["owner"] = "A"
			h["units"] = 400.0
			h["structure"] = "monster_hub"
			h["build_kind"] = ""
			h["monster_ready_t"] = 0.0
			Sim._sync_legacy(h)
			main.set_meta("stage_monster", hub)
		"guns":
			var home: int = sim.homes.get("A", 0)
			if arg.count(":") >= 2:                       # guns:<k>:<look> - seat A's Machinegoon look
				Cosmetics.set_loadout("A", {"machinegoon": arg.split(":")[2]})
			var picks := []
			for n in sim.nodes:
				if n["id"] != home and n["node_kind"] == "common":
					picks.append(n)
			picks.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(sim.nodes[home]["pos"]) < (b["pos"] as Vector3).distance_to(sim.nodes[home]["pos"]))
			for i in range(mini(3, picks.size())):
				var n: Dictionary = picks[i]
				n["owner"] = "A"
				n["units"] = 60.0
				n["structure"] = "machinegoon"
				n["tier"] = (i + maxi(node, 0)) % 3 + 1          # guns:<k> rotates the tiers round the three nodes
				Sim._sync_legacy(n)
			for n in sim.nodes:
				if n["node_kind"] == "relay":
					n["owner"] = "A"
					n["units"] = 60.0
					n["structure"] = "laser"
					Sim._sync_legacy(n)
					picks.push_front(n)
					break
			var pairs := []                               # B's lines walk at each of them from a neighbour
			var chosen := picks.slice(0, 4).map(func(x): return x["id"])
			for i in range(mini(4, picks.size())):
				var gun: Dictionary = picks[i]
				for link in sim.adj[gun["id"]]:
					var nb: Dictionary = sim.nodes[link[0]]
					var used := pairs.any(func(pr): return pr[0] == nb["id"])   # a door emits one order at a time
					if not nb["id"] in chosen and nb["id"] != home and sim.is_edge_open(link[1]) and not used:
						nb["owner"] = "B"
						nb["units"] = 300.0
						pairs.append([nb["id"], gun["id"]])
						break
			main.set_meta("stage_guns", pairs)
			sim.nodes[home]["tier"] = 2                   # A's home as a T2 vat beside them, for scale
			print("stage: guns at ", picks.slice(0, 4).map(func(x): return x["id"]), " lines ", pairs)
		"skins":                                       # seat A in non-default looks everywhere (0.19.2 proof)
			Cosmetics.set_loadout("A", {"vat": "reactor", "machinegoon": "spitter", "laser": "tesla", "forge": "anvil",
					"monster_hub": "pit", "monster": "alt"})
			var home: int = sim.homes.get("A", 0)
			var hp: Vector3 = sim.nodes[home]["pos"]
			var by_d := sim.nodes.duplicate()
			by_d.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(hp) < (b["pos"] as Vector3).distance_to(hp))
			var relays := ["laser", "forge", "monster_hub"]
			var guns := 2
			var k := 0
			for n in by_d:
				if n["owner"] not in ["", "A"]:
					continue
				if n["node_kind"] == "relay" and not relays.is_empty():
					n["owner"] = "A"
					n["units"] = 150.0
					n["structure"] = relays.pop_front()
					n["monster_ready_t"] = 0.0
					Sim._sync_legacy(n)
					if n["structure"] == "monster_hub":
						main.set_meta("stage_monster", n["id"])
						main.set_meta("stage_monster_at", 2.6)
				elif n["node_kind"] == "common" and n["id"] != home and k < 6:
					n["owner"] = "A"
					n["units"] = 60.0
					n["tier"] = 2 + k % 2
					if guns > 0:
						n["structure"] = "machinegoon"
						guns -= 1
					Sim._sync_legacy(n)
					k += 1
			print("stage: skins ", by_d.filter(func(x): return x["owner"] == "A").map(func(x): return [x["id"], x["structure"], x["tier"]]))
		"relays":                                      # seat A owns every relay; the first one fires at 0.6 s
			var rel := []
			for n in sim.nodes:
				if n["node_kind"] == "relay":
					n["owner"] = "A"
					n["units"] = 60.0
					rel.append(n["id"])
			main.set_meta("stage_relay", rel)
		"vats":
			var look := arg.split(":")[1] if arg.contains(":") else "faction"
			var lo := Cosmetics.loadout("A")
			lo["vat"] = look
			Cosmetics.set_loadout("A", lo)
			var k := 0
			var sends := []                               # each vat sends a line out: the bodies drop out of its tanks
			for n in sim.nodes:
				if n["node_kind"] != "relay" and n["owner"] in ["", "A"]:
					n["owner"] = "A"
					if n["node_kind"] == "common":
						n["tier"] = 1 + k % 3
						n["units"] = float(Rules.CAPS[n["tier"]]) * (0.35 + 0.2 * (k % 3))
						k += 1
						for link in sim.adj[n["id"]]:
							if sim.is_edge_open(link[1]):
								sends.append([n["id"], link[0]])
								break
			main.set_meta("stage_guns", sends)
			print("stage: vats ", look, " sends ", sends)
	for n in sim.nodes:
		MapBuilder.apply_owner(main.get("vis")[n["id"]]["parts"], n["owner"])


static func stage_tick(main: Node) -> void:
	## Per frame while a staged moment waits: launch the monster, send the lines at the guns.
	var sim: Sim = main.get("sim")
	if sim.time < 0.6:
		return
	if main.has_meta("stage_guns"):
		for pr in main.get_meta("stage_guns"):
			sim.send(pr[0], pr[1], 0.5)
		main.remove_meta("stage_guns")
	if main.has_meta("stage_relay"):
		var rel: Array = main.get_meta("stage_relay")
		main.remove_meta("stage_relay")
		if not rel.is_empty():
			print("stage: relays ", rel, " firing ", rel[0], ": ", sim.fire_relay(rel[0]))
	if not main.has_meta("stage_monster") or sim.time < float(main.get_meta("stage_monster_at", 0.6)):
		return
	var hub: int = main.get_meta("stage_monster")
	main.remove_meta("stage_monster")
	var best := -1
	var best_d := -1.0
	for id in sim.monster_reach(hub):
		var r := sim.find_route(hub, id)
		var d := float(r.size())
		if sim.nodes[id]["owner"] != "A" and d > best_d:
			best_d = d
			best = id
	if best >= 0:
		var r := sim.find_route(hub, best)
		if r.size() >= 3:                               # a line of B's walks into its path on the first deck
			var mid: int = r[1]
			sim.nodes[mid]["owner"] = "B"
			sim.nodes[mid]["units"] = 150.0
			sim.send(mid, hub, 1.0)
		print("stage: monster from %d to %d via %s: %s" % [hub, best, sim.find_route(hub, best), sim.launch_monster(hub, "A", best)])
