class_name CombatFx
extends Node3D
## Combat effects (0.18.6). The fight for a tower (Daniele: "we need an animation for when 2 teams are
## fighting for a tower"): a contest ring round the platform in both owners' colours, impact sparks and
## splats where the attackers hit the garrison (BRAWL: Alpha 11's front door, where every arrival is
## resolved one by one; SIEGE: the seams of the siege on the river ring, or where a line passes through),
## a shock flash per resolved clash, all following the fight's rate, gone when the fight ends. The
## conquest tier-down (Daniele: "and an animation for when a tower is conquered and its tier is lowered
## by 1"): a ghost of the old tier sinks into the socket in a burst of debris while the new tier rises,
## "T3 -> T2" and a falling chevron over the node in the new owner's colour. The cannon laser (Daniele:
## "laser needs to be made looking good, right now it's still default mode"): a shader beam with a hot
## white core and the owner's glow, energy scrolling toward the target, a muzzle flash at the cannon's
## top, an impact burst and a flickering scorch where it hits, charge-in and fade-out over the burst.
## Structures 2.1 (0.19.0): the laser tower fires that beam from its crown's focal orb (the look's emitter,
## Cosmetics.points); a Machinegoon's turret yaws to the line it is shooting (n["shot"]), a goo stream arcs
## from its muzzle to the target with a splash for every kill, and the T3 / Pepperbox barrel cluster spins
## up while it fires.
## Everything is read from the Sim's state (lines pouring in, sieges, node losses, owners and tiers,
## laser bursts, machinegoon shots), so online guests, who apply the host's snapshots, see the same thing
## with no extra traffic. One MultiMesh draws every spark; rings, beams and flares are made once per node
## and reused.
## Match feel (Daniele's phone test, 2026-09-28): the contest ring is a progress meter - the attacker's colour sweeps
## round it over the share of the fight they are winning (_progress: attackers at the door and on their way in
## against the garrison left, at the Sim's own exchange rate; eased, no numbers) - and YOUR node under attack (an
## ally's, dimmer) flickers red on its rim at the side the enemy line pours in from, with short sparks there (_alarm).

const BEAM_SHADER := preload("res://shaders/beam.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")
const FLARE_SHADER := preload("res://shaders/flare.gdshader")
const RING_SHADER := preload("res://shaders/contest_ring.gdshader")
const ALARM_SHADER := preload("res://shaders/alarm_rim.gdshader")

const HOT := Color(1.0, 0.9, 0.72)       # white-hot sparks
const HEAT_RATE := 30.0                  # sim units/s resolved at which a fight reads at full heat
const FIGHT_FADE := 0.35                 # s: the ring fades out after the last clash
const RING_Y := 0.32                     # just above the platform deck
const MAX_SPARKS := 320
# the cannon's emitter dome at the top of Cannon_T1..T3 (kit heights 4.58 / 5.76 / 6.94 m)
const MUZZLE_Y := [0.0, 4.4, 5.55, 6.75]
const BEAM_WIDTH := [0.0, 1.3, 1.6, 1.9]   # metres by cannon tier
const CHARGE := 0.16                     # s: the beam shoots out from the muzzle to the target
const FADE_OUT := 0.3                    # s: after the burst the beam drains into the target
const TIER_DOWN_TIME := 2.4              # s: the whole tier-down flash

var world: Node3D
var sim: Sim
var vis: Dictionary
var fx: Fx
var _frame := 0
var top_limit := 0.0        # screen y the top bar and its toasts reach (main._on_resized): tier-down lines stay below it
var _fights := {}           # node id -> {ring, mat, life, heat, rate, best, att, angle, share, prog, target, frame}
var _alarms := {}           # node id -> {ring, mat, life, angle, ally, frame, spark_t} (your / an ally's node under attack)
var _start_angle := 0.0     # the contest ring's sweep starts here: the platforms' far side (top of the screen)
var viewer := "A"           # whose nodes raise the under-attack cue (main.HUMAN; set in setup)
var _cannons := {}          # node id -> {beam, bmat, muzzle, mmat, hit, hmat, scorch, smat, on, t, fade, to, col}
var _guns := {}             # node id -> machinegoon view state (see _machinegoons_step)
var _tier_owner := {}       # node id -> owner last frame (tier-down detection)
var _tier_level := {}       # node id -> vat / cannon tier last frame
var _downs: Array = []      # running tier-downs: {node, t, ghost, ghost_mis, base_y, new, new_y, label, chev, ring, rmat}
var _annulus: ArrayMesh
var _alarm_mesh: ArrayMesh  # the under-attack arc's thinner ring, just outside the platform (Rules.ALARM_R)
var _strip: ArrayMesh
var _quad: QuadMesh
var _plane: PlaneMesh
var _mm: MultiMesh
var _sp_pos := PackedVector3Array()
var _sp_vel := PackedVector3Array()
var _sp_col := PackedColorArray()
var _sp_life := PackedFloat32Array()
var _sp_max := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_grav := PackedFloat32Array()
var _sp_n := 0
const _BIG := AABB(Vector3(-2000, -400, -2000), Vector3(4000, 800, 4000))


func setup(w: Node3D, s: Sim, v: Dictionary, f: Fx) -> void:
	world = w
	sim = s
	vis = v
	fx = f
	viewer = str(w.get("HUMAN")) if w.get("HUMAN") != null else "A"
	_annulus = _annulus_mesh(0.86, 72)
	_alarm_mesh = _annulus_mesh(Rules.ALARM_INNER, 72)
	_strip = _strip_mesh(40)
	_quad = QuadMesh.new()
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1.0, 1.0)
	_sp_pos.resize(MAX_SPARKS)                        # packed arrays are values: each one resized by name
	_sp_vel.resize(MAX_SPARKS)
	_sp_col.resize(MAX_SPARKS)
	_sp_life.resize(MAX_SPARKS)
	_sp_max.resize(MAX_SPARKS)
	_sp_size.resize(MAX_SPARKS)
	_sp_grav.resize(MAX_SPARKS)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _quad
	_mm.instance_count = MAX_SPARKS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var sm := ShaderMaterial.new()
	sm.shader = SPARK_SHADER
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = _BIG                            # the quads are placed in the shader
	add_child(mmi)


# ------------------------------------------------------------------ per frame
func sync(dt: float, cam: Camera3D) -> void:
	## After Fx.sync (main._process): Fx._construction resets a finished structure's scale each frame,
	## the tier-down's rising model is scaled after it.
	_frame += 1
	if cam:                                           # the sweep starts at the top of the screen, whatever the yaw
		var fwd := -cam.global_transform.basis.z
		if Vector2(fwd.x, fwd.z).length() > 0.01:
			_start_angle = atan2(fwd.z, fwd.x)
	_gather_fights(dt)
	_update_fights(dt)
	_update_alarms(dt)
	_cannons_step(dt, cam)
	_machinegoons_step(dt)
	_tier_downs(dt, cam)
	_update_sparks(dt)
	for n in sim.nodes:                               # remembered for the next frame's tier-down check
		_tier_owner[n["id"]] = n["owner"]
		_tier_level[n["id"]] = _level(n)


# ------------------------------------------------------------------ the fight for a tower
func _gather_fights(dt: float) -> void:
	var front := Rules.front_dir()
	if not Rules.bridge_combat:
		# BRAWL (Alpha 11 land()): a line pouring in at an enemy or neutral node is resolved at the front
		# door unit by unit against the garrison while it pours - that is the fight.
		for h in sim.hordes:
			if h["state"] != "absorb" or h["units"] <= 0.0:
				continue
			var n: Dictionary = sim.nodes[h["target"]]
			if sim.collapsed.get(n["id"], false) or sim.allied(n["owner"], h["owner"]):
				continue
			var route: Array = h["route"]
			var came: Vector3 = (sim.nodes[route[-2]]["pos"] - n["pos"]) if route.size() >= 2 else front
			var rate: float = maxf(Rules.move_speed() * h["units"] / maxf(Sim.chain_length(h), 0.5), 4.0)
			var share: float = h["units"] / maxf(h["units"] + n["units"], 0.001)
			var door: Vector3 = n["pos"] + front * (Rules.EXIT_R + 0.35) + Vector3(0, 0.9, 0)
			_contest(n, h["owner"], came, rate, share, door)
			_clash(door, front, Rules.seat_color(h["owner"]), _owner_color(n["owner"]), rate, dt)
			if n["owner"] != "" and sim.allied(n["owner"], viewer):
				_alarm(n, came, n["owner"] != viewer, dt)
		for id in _fights:                            # the ring's sweep: how close the strongest side is to taking it
			var f: Dictionary = _fights[id]
			if f["frame"] == _frame:
				f["target"] = _progress(sim.nodes[id], str(f["att"]))
		return
	# SIEGE: arrivals sit on the platform (siege) and fight the garrison at node rates (Sim._node_fights);
	# lines passing through fight it where they cross (transit).
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false):
			continue
		var loss: Dictionary = n["node_loss"]
		if loss.is_empty():
			continue
		var g_loss: float = loss.get(n["owner"], 0.0) if n["owner"] != "" else 0.0
		var total: float = n["units"]
		for k in n["siege"]:
			total += n["siege"][k]
		for k in n["siege"]:
			var units: float = n["siege"][k]
			var rate: float = loss.get(k, 0.0) + g_loss
			if units <= 0.0 or rate <= 0.0:
				continue
			var share := units / maxf(total, 0.001)
			var d: Vector3 = n["siege_dir"].get(k, front)
			var a := atan2(d.z, d.x)
			var half := share * PI
			var col := Rules.seat_color(k)
			var def := _owner_color(n["owner"])
			var up := Vector3(0, 0.7, 0)
			var e1 := Vector3(cos(a + half), 0.0, sin(a + half))
			var e2 := Vector3(cos(a - half), 0.0, sin(a - half))
			_contest(n, k, d, rate, share, n["pos"] + d * Rules.RIVER_R + up)
			_clash(n["pos"] + e1 * Rules.RIVER_R + up, e1, col, def, rate * 0.5, dt)   # both seams of the siege
			_clash(n["pos"] + e2 * Rules.RIVER_R + up, e2, col, def, rate * 0.5, dt)
		for k in n["transit"]:
			var rate: float = loss.get(k, 0.0)
			var hs: Array = n["transit"][k]["hordes"]
			if rate <= 0.0 or hs.is_empty():
				continue
			var head: Vector3 = Sim.sample(hs[0], hs[0]["s"])[0]
			var d: Vector3 = head - (n["pos"] as Vector3)
			d.y = 0.0
			d = d.normalized() if d.length() > 0.01 else front
			var units: float = n["transit"][k]["units"]
			var spot: Vector3 = n["pos"] + d * Rules.RIVER_R + Vector3(0, 0.7, 0)
			_contest(n, k, d, rate, units / maxf(units + n["units"], 0.001), spot)
			_clash(spot, d, Rules.seat_color(k), _owner_color(n["owner"]), rate, dt)


func _contest(n: Dictionary, seat: String, dir: Vector3, rate: float, share: float, spot: Vector3) -> void:
	## One attacking side at node n this frame; the ring shows the strongest one's arc, the hot glow on
	## the deck sits where it hits.
	var id: int = n["id"]
	if not _fights.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = _annulus
		var mat := ShaderMaterial.new()
		mat.shader = RING_SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		var glow := MeshInstance3D.new()
		glow.mesh = _plane
		var gmat := ShaderMaterial.new()
		gmat.shader = FLARE_SHADER
		gmat.set_shader_parameter("mode", 1)
		gmat.set_shader_parameter("seed", float(id) * 7.3)
		glow.material_override = gmat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.visible = false
		add_child(glow)
		_fights[id] = {"ring": mi, "mat": mat, "glow": glow, "gmat": gmat, "life": 0.0, "heat": 0.0, "rate": 0.0,
				"best": -1.0, "att": seat, "angle": 0.0, "share": 0.3, "spot": spot, "frame": -1, "prog": 0.0, "target": 0.0}
	var f: Dictionary = _fights[id]
	if f["frame"] != _frame:
		f["frame"] = _frame
		f["rate"] = 0.0
		f["best"] = -1.0
	f["rate"] += rate
	if rate > f["best"]:
		f["best"] = rate
		f["att"] = seat
		f["angle"] = atan2(dir.z, dir.x)
		f["share"] = lerpf(f["share"], clampf(share, 0.08, 0.9), 0.15)
		f["target"] = clampf(share, 0.0, 1.0)             # SIEGE's sweep (BRAWL: _progress, after the gather)
		f["spot"] = spot


func _update_fights(dt: float) -> void:
	for id in _fights:
		var f: Dictionary = _fights[id]
		var ring: MeshInstance3D = f["ring"]
		var active: bool = f["frame"] == _frame
		var target_heat: float = clampf(f["rate"] / HEAT_RATE, 0.15, 1.0) if active else 0.0
		f["heat"] = lerpf(f["heat"], target_heat, minf(1.0, dt * 5.0))
		f["life"] = minf(1.0, f["life"] + dt * 5.0) if active else f["life"] - dt / FIGHT_FADE
		if f["life"] <= 0.0 or sim.collapsed.get(id, false):
			f["life"] = 0.0
			f["prog"] = 0.0                               # the next fight here sweeps in from nothing
			ring.visible = false
			(f["glow"] as Node3D).visible = false
			continue
		var n: Dictionary = sim.nodes[id]
		if not active and sim.allied(str(n["owner"]), str(f["att"])):
			f["target"] = 1.0                             # taken: the sweep closes while the ring fades
		var ease_k: float = Rules.CONTEST_EASE * (1.0 if active else 4.0)
		f["prog"] = lerpf(float(f["prog"]), float(f["target"]), minf(1.0, dt * ease_k))
		ring.visible = true
		# SIEGE: the goo covers the platform to its lip, so the ring rides just outside and above it
		var siege := Rules.bridge_combat
		ring.position = n["pos"] + Vector3(0, RING_Y + (0.45 if siege else 0.0), 0)
		ring.scale = Vector3.ONE * (Rules.R + (0.75 if siege else 0.0))
		var mat: ShaderMaterial = f["mat"]
		mat.set_shader_parameter("col_def", _owner_color(n["owner"]))
		mat.set_shader_parameter("col_att", Rules.seat_color(f["att"]))
		mat.set_shader_parameter("start_angle", _start_angle)
		mat.set_shader_parameter("progress", f["prog"])
		mat.set_shader_parameter("track", Rules.CONTEST_TRACK)
		mat.set_shader_parameter("ticks", float(Rules.CONTEST_TICKS))
		mat.set_shader_parameter("heat", f["heat"])
		mat.set_shader_parameter("life", smoothstep(0.0, 1.0, f["life"]))
		var glow: MeshInstance3D = f["glow"]           # the hot spot on the deck where they clash
		glow.visible = true
		var spot: Vector3 = f["spot"]
		glow.position = Vector3(spot.x, (n["pos"] as Vector3).y + RING_Y + (0.9 if siege else 0.03), spot.z)
		glow.scale = Vector3.ONE * (3.2 + 1.8 * f["heat"])
		var gmat: ShaderMaterial = f["gmat"]
		gmat.set_shader_parameter("color", Rules.seat_color(f["att"]).lerp(_owner_color(n["owner"]), 0.5).lerp(HOT, 0.35))
		gmat.set_shader_parameter("intensity", smoothstep(0.0, 1.0, f["life"]) * (0.7 + 0.9 * f["heat"]))


func _progress(n: Dictionary, seat: String) -> float:
	## How close `seat`'s side is to taking node n, 0..1 (the contest ring's sweep). BRAWL resolves every arriving
	## unit at the door against the whole garrison (Sim._land_classic), killing `ratio` defenders each; so the side's
	## strength is its units pouring in plus those on their way in (within Rules.CONTEST_REACH m of the door) times
	## that ratio, against the garrison left: A / (A + G). Both fall by the same amount per exchange, so the sweep
	## heads for 1 when the attack will take it and back to 0 when the defence will hold. Read-only; no rule here.
	var garrison: float = sim.garrison_total(n)
	var att := 0.0
	for h in sim.hordes:
		if int(h["target"]) != int(n["id"]) or float(h["units"]) <= 0.0 or h.get("decoy", false):
			continue
		if not sim.allied(str(h["owner"]), seat) or sim.allied(str(n["owner"]), str(h["owner"])):
			continue
		if h["state"] == "absorb" or (h["state"] == "move" and float(h["L"]) - float(h["s"]) <= Rules.CONTEST_REACH):
			att += float(h["units"]) * _kill_ratio(n, str(h["owner"]))
	if att + garrison <= 0.0001:
		return 0.0
	return clampf(att / (att + garrison), 0.0, 1.0)


func _kill_ratio(n: Dictionary, seat: String) -> float:
	## Defenders one arriving unit of `seat` kills at node n: Sim._land_classic's exchange (attack / (health x garrison
	## x Fortify / Aegis / forge), against the defenders' attack / the attacker's health), mixed by troop share.
	var d_seat: String = n["owner"]
	var total: float = sim.garrison_total(n)
	var tough := 0.0
	var d_att := 0.0
	if total > 0.0001 and not (n["allies"] as Dictionary).is_empty():
		var shares := {d_seat: float(n["units"])}
		for k in n["allies"]:
			shares[k] = float(n["allies"][k])
		for k in shares:
			var w: float = shares[k] / total
			tough += w * sim.stat(k, "health") * sim.stat(k, "garrison")
			d_att += w * (sim.attack_of(k) if k != "" else 1.0)
	else:
		tough = sim.stat(d_seat, "health") * sim.stat(d_seat, "garrison")
		d_att = sim.attack_of(d_seat) if d_seat != "" else 1.0
	var kill_per: float = sim.attack_of(seat) / maxf(tough * sim.garrison_div(n), 0.0001)
	var cost_per: float = d_att / maxf(sim.stat(seat, "health"), 0.0001)
	return kill_per / maxf(cost_per, 0.0001)


func _alarm(n: Dictionary, came: Vector3, ally: bool, dt: float) -> void:
	## YOUR node (ally: a team-mate's) with an enemy line pouring in at its door this frame: the rim facing the attack
	## flickers red (_update_alarms) and, at most every Rules.ALARM_SPARK_GAP s, short sparks jump off the rim there.
	var id: int = n["id"]
	if not _alarms.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = _alarm_mesh
		var mat := ShaderMaterial.new()
		mat.shader = ALARM_SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_alarms[id] = {"ring": mi, "mat": mat, "life": 0.0, "angle": 0.0, "ally": ally, "frame": -1, "spark_t": 0.0}
	var al: Dictionary = _alarms[id]
	var d := Vector3(came.x, 0.0, came.z)
	d = d.normalized() if d.length() > 0.01 else Rules.front_dir()
	if al["frame"] == _frame:
		return                                        # two lines at one door: one cue, one spark clock
	al["frame"] = _frame
	al["angle"] = atan2(d.z, d.x)
	al["ally"] = ally
	al["spark_t"] = float(al["spark_t"]) - dt
	if float(al["spark_t"]) <= 0.0:
		al["spark_t"] = Rules.ALARM_SPARK_GAP
		var k := Rules.ALARM_ALLY if ally else 1.0
		var rim: Vector3 = n["pos"] + d * (Rules.R + 0.15) + Vector3(0, RING_Y + 0.25, 0)
		var side := d.cross(Vector3.UP)
		for i in range(Rules.ALARM_SPARKS):
			var v := (d * randf_range(0.4, 1.0) + side * randf_range(-0.9, 0.9) + Vector3(0, randf_range(0.8, 1.6), 0)).normalized()
			_spark(rim + side * randf_range(-1.2, 1.2), v * randf_range(3.0, 6.5), Rules.ALARM_COLOR.lerp(HOT, randf() * 0.4) * (1.3 * k),
					randf_range(0.16, 0.26), randf_range(0.18, 0.32), 14.0)


func _update_alarms(dt: float) -> void:
	for id in _alarms:
		var al: Dictionary = _alarms[id]
		var ring: MeshInstance3D = al["ring"]
		var active: bool = al["frame"] == _frame
		al["life"] = minf(1.0, float(al["life"]) + dt * 8.0) if active else float(al["life"]) - dt / Rules.ALARM_HOLD
		if float(al["life"]) <= 0.0 or sim.collapsed.get(id, false) or not sim.allied(str(sim.nodes[id]["owner"]), viewer):
			al["life"] = 0.0
			al["spark_t"] = 0.0                           # the next attack here sparks at once
			ring.visible = false
			continue
		var n: Dictionary = sim.nodes[id]
		ring.visible = true
		ring.position = n["pos"] + Vector3(0, RING_Y + 0.06, 0)
		ring.scale = Vector3.ONE * (Rules.R + Rules.ALARM_R)
		# a hard-edged flicker (bright / dim at ALARM_FLICKER Hz), readable at a glance, eased in and out by the life
		var on := 1.0 if fmod(sim.time * Rules.ALARM_FLICKER, 1.0) < 0.55 else Rules.ALARM_DIM
		var mat: ShaderMaterial = al["mat"]
		mat.set_shader_parameter("color", Rules.ALARM_COLOR)
		mat.set_shader_parameter("att_angle", al["angle"])
		mat.set_shader_parameter("arc", Rules.ALARM_ARC)
		mat.set_shader_parameter("power", Rules.ALARM_POWER * on * smoothstep(0.0, 1.0, float(al["life"]))
				* (Rules.ALARM_ALLY if al["ally"] else 1.0))


func _clash(spot: Vector3, out: Vector3, att: Color, def: Color, rate: float, dt: float) -> void:
	## Where the attackers hit the garrison: sparks and goo splats in both colours spraying off the
	## front, and a shock flash for every clash resolved (one per shown unit, Alpha 11's one-for-one).
	var heat := clampf(rate / HEAT_RATE, 0.15, 1.0)
	var detail := 0.5 if Rules.low_detail else 1.0
	var side := out.cross(Vector3.UP).normalized()
	for i in range(_count((20.0 + 70.0 * heat) * detail * dt)):
		var v := (out * randf_range(0.2, 1.0) + side * randf_range(-1.0, 1.0) + Vector3(0, randf_range(0.7, 1.9), 0)).normalized()
		var roll := randf()
		var col := HOT if roll < 0.3 else (att if roll < 0.65 else def)
		_spark(spot + side * randf_range(-0.5, 0.5), v * randf_range(5.0, 12.0), col * 1.3, randf_range(0.15, 0.28), randf_range(0.3, 0.55), 16.0)
	for i in range(_count((4.0 + 14.0 * heat) * detail * dt)):
		var v := (out * randf_range(0.3, 1.0) + side * randf_range(-0.8, 0.8) + Vector3(0, randf_range(0.8, 1.6), 0)).normalized()
		_spark(spot + side * randf_range(-0.6, 0.6), v * randf_range(2.5, 5.0), (att if randf() < 0.5 else def),
				randf_range(0.32, 0.5), randf_range(0.45, 0.75), 20.0)
	for i in range(_count(clampf(Rules.shown_f(rate), 2.5, 12.0) * dt)):   # a small fight still flashes
		var c := (att if randf() < 0.5 else def).lerp(Color.WHITE, 0.45)
		_spark(spot + side * randf_range(-0.7, 0.7) + Vector3(0, randf_range(-0.2, 0.6), 0), Vector3.ZERO, c * 1.6,
				randf_range(1.4, 2.2) * (0.75 + 0.45 * heat), 0.2, 0.0)


# ------------------------------------------------------------------ cannon laser
func _cannons_step(dt: float, cam: Camera3D) -> void:
	for n in sim.nodes:
		var id: int = n["id"]
		var firing: bool = n.get("structure", "laser" if n["attachment"] == "cannon" else "") == "laser" \
				and n["cannon_burst"] > 0.0 and n["owner"] != "" and not sim.collapsed.get(id, false)
		if not _cannons.has(id):
			if not firing:
				continue
			_cannons[id] = _new_cannon()
		var c: Dictionary = _cannons[id]
		var target: Vector3 = (n["cannon_target"] as Vector3) + Vector3(0, 0.7, 0)
		if firing:
			if not c["on"]:                           # a new burst: snap to its first target
				c["on"] = true
				c["t"] = 0.0
				c["fade"] = -1.0
				c["to"] = target
				c["col"] = Rules.seat_color(n["owner"])
				c["seed"] = randf() * 100.0
			c["t"] += dt
			c["to"] = (c["to"] as Vector3).lerp(target, minf(1.0, dt * 14.0))   # guests: snapshots step the target
		elif c["on"]:
			c["on"] = false
			c["fade"] = 0.0
		elif c["fade"] >= 0.0:
			c["fade"] += dt
		if not c["on"] and (c["fade"] < 0.0 or c["fade"] >= FADE_OUT):
			c["fade"] = -1.0
			for k in ["beam", "muzzle", "hit", "scorch"]:
				(c[k] as Node3D).visible = false
			continue
		var tier := 3                                  # Structures 2.1: one laser tier, the old T3 beam
		var muzzle: Vector3 = _emitter(n)
		var to: Vector3 = c["to"]
		var col: Color = c["col"]
		var t: float = c["t"]
		var ext := smoothstep(0.0, CHARGE, t)          # charge-in: the beam shoots out to the target
		var power := 0.5 + 0.5 * smoothstep(0.0, CHARGE * 2.0, t)
		var p0 := muzzle
		var p1 := muzzle.lerp(to, ext)
		if c["on"]:
			power *= 0.92 + 0.08 * sin(t * 71.0)
			power *= lerpf(0.6, 1.0, smoothstep(0.0, 0.25, n["cannon_burst"]))   # eases off in the burst's last beat
		else:                                         # fade-out: the tail drains into the target
			var k: float = c["fade"] / FADE_OUT
			p0 = muzzle.lerp(to, k * k)
			power *= 0.6 * (1.0 - k)
		var bmat: ShaderMaterial = c["bmat"]
		bmat.set_shader_parameter("p0", p0)
		bmat.set_shader_parameter("p1", p1)
		bmat.set_shader_parameter("color", col)
		bmat.set_shader_parameter("width", BEAM_WIDTH[tier])
		bmat.set_shader_parameter("power", power)
		bmat.set_shader_parameter("seed", c["seed"])
		(c["beam"] as Node3D).visible = true
		var muz: MeshInstance3D = c["muzzle"]           # muzzle flash: a spike on the charge, then a flicker
		muz.visible = true
		var to_cam := Vector3.UP
		if cam:
			to_cam = (cam.global_position - muzzle).normalized()
		muz.position = muzzle + to_cam * 1.6             # in front of the dome, or the dome hides the flash
		var spike := 1.0 - smoothstep(0.0, 0.3, t)
		muz.scale = Vector3.ONE * (BEAM_WIDTH[tier] * (2.2 + 2.6 * spike) * (0.9 + 0.15 * sin(t * 53.0)))
		var mmat: ShaderMaterial = c["mmat"]
		mmat.set_shader_parameter("color", col)
		mmat.set_shader_parameter("intensity", power * (1.1 + 1.4 * spike))
		mmat.set_shader_parameter("spin", t * 2.0)
		var hit: MeshInstance3D = c["hit"]              # impact burst where the beam lands
		var landed := smoothstep(0.7, 1.0, ext)
		hit.visible = landed > 0.0
		hit.position = p1 + to_cam * 0.8                # in front of the bodies it hits
		hit.scale = Vector3.ONE * (2.4 + 0.9 * absf(sin(t * 29.0 + 1.3))) * (0.6 + 0.4 * power)
		var hmat: ShaderMaterial = c["hmat"]
		hmat.set_shader_parameter("color", col.lerp(HOT, 0.35))
		hmat.set_shader_parameter("intensity", power * landed * 1.3)
		hmat.set_shader_parameter("spin", -t * 3.0 + c["seed"])
		var sc: MeshInstance3D = c["scorch"]            # scorch flicker on the deck under the hit
		sc.visible = landed > 0.0
		sc.position = to - Vector3(0, 0.45, 0)            # on the deck (the target is 0.7 m up)
		sc.scale = Vector3.ONE * (3.4 + 0.6 * smoothstep(0.0, 1.5, t))
		var smat: ShaderMaterial = c["smat"]
		smat.set_shader_parameter("color", col.lerp(Color(1.0, 0.45, 0.12), 0.55))
		smat.set_shader_parameter("intensity", landed * (1.6 * smoothstep(0.0, 0.5, t)) * (1.0 if c["on"] else 1.0 - c["fade"] / FADE_OUT))
		if c["on"] and landed > 0.5:
			var detail := 0.5 if Rules.low_detail else 1.0
			var back := (p0 - p1).normalized()
			for i in range(_count(55.0 * detail * dt)):
				var v := (back * randf_range(0.0, 0.8) + Vector3(randf_range(-1, 1), randf_range(0.4, 1.5), randf_range(-1, 1))).normalized()
				_spark(p1, v * randf_range(4.0, 11.0), HOT if randf() < 0.5 else col, randf_range(0.1, 0.2), randf_range(0.2, 0.45), 18.0)


func _new_cannon() -> Dictionary:
	var beam := MeshInstance3D.new()
	beam.mesh = _strip
	var bmat := ShaderMaterial.new()
	bmat.shader = BEAM_SHADER
	beam.material_override = bmat
	beam.custom_aabb = _BIG                           # the ribbon is placed in the shader
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var c := {"beam": beam, "bmat": bmat, "on": false, "t": 0.0, "fade": -1.0, "to": Vector3.ZERO,
			"col": Color.WHITE, "seed": 0.0}
	for k in ["muzzle", "hit", "scorch"]:
		var mi := MeshInstance3D.new()
		mi.mesh = _plane if k == "scorch" else _quad
		var m := ShaderMaterial.new()
		m.shader = FLARE_SHADER
		m.set_shader_parameter("mode", 1 if k == "scorch" else 0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		c[k] = mi
		c[k.substr(0, 1) + "mat"] = m                 # mmat / hmat / smat
	return c


func _emitter(n: Dictionary) -> Vector3:
	## Where the laser beam starts: the look's focal orb (Cosmetics.points "emitter", socket lift added).
	var entry: Dictionary = vis.get(n["id"], {})
	var key := str(entry.get("model_key", "Laser"))
	var pt: Dictionary = Cosmetics.points(key)
	var base: Vector3 = entry.get("centre", n["pos"])
	if pt.has("emitter"):
		return base + (pt["emitter"] as Vector3) + Vector3(0, float(pt.get("lift", 0.0)), 0)
	return base + Vector3(0, MUZZLE_Y[3], 0)


# ------------------------------------------------------------------ machinegoon (0.19.0)
# A continuous goo stream at the nearest enemy line in range (Sim._fire_machinegoon writes n["shot"] every
# step it fires: {"t", "target_horde", "kills", "pos"}). The turret yaws to the target (it idles in a slow
# sweep when nothing is in range), the stream is a thin goo ribbon plus arcing blobs from the muzzle (the
# look's muzzles take turns), every whole shown kill splashes at the target, and a spinning barrel cluster
# (Machinegoon T3, the Pepperbox line) spins up while it fires.
const GUN_HOLD := 0.3                    # s after the last shot the stream still reads as firing (guests' snapshots)
const GUN_TURN := 9.0                    # turret yaw rate toward its target (1/s, exponential)
const GUN_SPIN := 26.0                   # rad/s of the barrel cluster at full fire
const STREAM_T := 0.28                   # s a goo blob flies from the muzzle to the target
const STREAM_G := 16.0                   # its gravity (the spark MultiMesh's)
const STREAM_RATE := 38.0                # blobs per second at full fire


func _machinegoons_step(dt: float) -> void:
	var seen := {}
	for n in sim.nodes:
		var id: int = n["id"]
		if n.get("structure", "") != "machinegoon" or n["build_kind"] != "" or sim.collapsed.get(id, false):
			continue
		var entry: Dictionary = vis.get(id, {})
		var vn = entry.get("vat_node")
		if not is_instance_valid(vn):
			continue
		seen[id] = true
		var g: Dictionary = _guns.get(id, {})
		if g.is_empty() or g["vn"] != vn:
			if not g.is_empty():
				(g["beam"] as Node3D).queue_free()
			g = _new_gun(vn as Node3D, str(entry.get("model_key", "")), n["owner"])
			_guns[id] = g
		var shot: Dictionary = n.get("shot", {})
		var firing: bool = not shot.is_empty() and n["owner"] != "" and sim.time - float(shot.get("t", -99.0)) <= GUN_HOLD
		var turret: Node3D = g["turret"]
		var root := vn as Node3D
		var to: Vector3 = (shot.get("pos", Vector3.ZERO) as Vector3) + Vector3(0, 0.7, 0)
		var want: float = g["yaw"]
		if firing:
			var d: Vector3 = root.global_transform.basis.inverse() * (to - root.global_position)
			if Vector2(d.x, d.z).length() > 0.3:
				want = atan2(d.x, d.z)
			g["idle"] = 0.0
		else:
			g["idle"] = float(g["idle"]) + dt
			if float(g["idle"]) > 1.5:                   # nothing in range: a slow watchful sweep
				want = 0.55 * sin(sim.time * 0.45 + float(id))
		g["yaw"] = lerp_angle(float(g["yaw"]), want, minf(1.0, dt * GUN_TURN))
		if turret:
			turret.rotation.y = g["yaw"]
		g["spin_v"] = lerpf(float(g["spin_v"]), GUN_SPIN if firing else 0.0, minf(1.0, dt * (4.0 if firing else 1.2)))
		var sp: Node3D = g["spinner"]
		if sp:
			sp.rotation.z += float(g["spin_v"]) * dt
		var beam: MeshInstance3D = g["beam"]
		g["power"] = lerpf(float(g["power"]), 1.0 if firing else 0.0, minf(1.0, dt * (12.0 if firing else 6.0)))
		if float(g["power"]) < 0.02:
			beam.visible = false
			continue
		var muzzles: Array = g["muzzles"]
		var mi: int = int(sim.time * 9.0) % maxi(muzzles.size(), 1)   # the barrels take turns
		var local: Vector3 = muzzles[mi] if not muzzles.is_empty() else Vector3(0, 2.6, 2.5)
		var from: Vector3 = (turret.global_transform if turret else root.global_transform) * local
		if not firing:
			to = g["to"]
		g["to"] = to
		var col := Rules.seat_color(n["owner"])
		var goo: Color = col.lerp(Color(0.75, 1.0, 0.55), 0.18)
		var bmat: ShaderMaterial = g["bmat"]
		bmat.set_shader_parameter("p0", from)
		bmat.set_shader_parameter("p1", to)
		bmat.set_shader_parameter("color", goo)
		bmat.set_shader_parameter("width", 0.6)
		bmat.set_shader_parameter("power", 0.85 * float(g["power"]))
		bmat.set_shader_parameter("seed", float(id) * 3.1)
		beam.visible = true
		if not firing:
			continue
		var detail := 0.5 if Rules.low_detail else 1.0
		var vel := (to - from) / STREAM_T + Vector3(0, 0.5 * STREAM_G * STREAM_T, 0)
		for i in range(_count(STREAM_RATE * detail * dt)):   # the goo arcs out of the barrel
			var jit := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * 0.9
			_spark(from, vel + jit, goo * 1.4, randf_range(0.34, 0.55), STREAM_T * randf_range(0.9, 1.15), STREAM_G)
		if randf() < dt * 14.0:                          # muzzle spit
			_spark(from, Vector3.ZERO, goo.lerp(Color.WHITE, 0.35) * 1.5, randf_range(0.7, 1.0), 0.08, 0.0)
		# a splash for every whole shown kill (the shot's kills are sim units per step)
		if float(shot.get("t", -1.0)) != float(g["last_t"]):
			g["last_t"] = float(shot.get("t", -1.0))
			g["debt"] = float(g["debt"]) + Rules.shown_f(float(shot.get("kills", 0.0)))
		var victim := _horde_owner(int(shot.get("target_horde", -1)))
		while float(g["debt"]) >= 1.0:
			g["debt"] = float(g["debt"]) - 1.0
			_splash(to, goo, Rules.seat_color(victim) if victim != "" else HOT, detail)
		if randf() < dt * 20.0:                          # the stream hitting: a small constant spatter
			var v := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized() * randf_range(2.0, 4.5)
			_spark(to, v, goo, randf_range(0.18, 0.3), randf_range(0.25, 0.45), 16.0)
	for id in _guns.keys():                               # gone (swapped back to a vat, captured and rebuilt, fell)
		if not seen.has(id):
			(_guns[id]["beam"] as Node3D).queue_free()
			_guns.erase(id)


func _new_gun(vn: Node3D, key: String, owner: String) -> Dictionary:
	var turret: Node3D = null
	for c in vn.find_children("*_Turret", "Node3D", true, false):
		turret = c
		break
	var spinner: Node3D = null
	if turret is MeshInstance3D:
		spinner = MapBuilder.split_spinner(turret as MeshInstance3D, key)
		if spinner:                                      # the split surfaces take the detail and the owner's lights again
			Mats.apply_detail(vn)
			MapBuilder.apply_owner([vn], owner)
	var beam := MeshInstance3D.new()
	beam.mesh = _strip
	var bmat := ShaderMaterial.new()
	bmat.shader = BEAM_SHADER
	beam.material_override = bmat
	beam.custom_aabb = _BIG
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	add_child(beam)
	return {"vn": vn, "turret": turret, "spinner": spinner, "muzzles": Cosmetics.points(key).get("muzzles", []),
			"yaw": 0.0, "idle": 0.0, "spin_v": 0.0, "power": 0.0, "beam": beam, "bmat": bmat, "to": vn.global_position,
			"last_t": -1.0, "debt": 0.0}


func _horde_owner(hid: int) -> String:
	for h in sim.hordes:
		if h["id"] == hid:
			return h["owner"]
	return ""


func _splash(at: Vector3, goo: Color, victim: Color, detail: float) -> void:
	## One kill: a goo splat bursting out of the body it hit, in both colours, with a flash.
	for i in range(int(9 * detail) + 3):
		var a := randf() * TAU
		var v := Vector3(cos(a), randf_range(0.7, 1.8), sin(a)).normalized() * randf_range(3.0, 7.5)
		_spark(at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), v, (goo if randf() < 0.55 else victim) * 1.2,
				randf_range(0.22, 0.4), randf_range(0.35, 0.6), 18.0)
	_spark(at, Vector3.ZERO, goo.lerp(Color.WHITE, 0.4) * 1.5, randf_range(1.4, 1.9), 0.16, 0.0)


# ------------------------------------------------------------------ conquest tier-down
static func _level(n: Dictionary) -> int:
	if n.get("structure", "") == "machinegoon":         # a Machinegoon loses a tier on conquest like a vat
		return n["tier"]
	if n["attachment"] == "cannon":
		return 0 if n.has("structure") else n["cannon_tier"]   # the one-tier laser has no tier-down
	return n["tier"] if Sim.has_vat(n) else 0


func before_swap(n: Dictionary, entry: Dictionary) -> void:
	## main._process, just before MapBuilder.set_centre_model swaps the node's centre model. When the
	## swap is a conquest's tier-down (a new owner, one tier lower - Sim._capture), a copy of the old
	## model stays behind as the ghost that sinks away.
	var id: int = n["id"]
	for d in _downs:                                  # swapped again while one plays (recaptured at once, a new
		if d["node"] == id and not d["superseded"]:   # build): its rising model is about to be freed, and the
			d["superseded"] = true                    # newer swap's own line takes over
			d["new"] = null
	if not _tier_owner.has(id):
		return
	var was: String = _tier_owner[id]
	var lv: int = _tier_level[id]
	var now := _level(n)
	if was == "" or n["owner"] == "" or n["owner"] == was or now <= 0 or now >= lv:
		return
	var old_key: String = entry.get("model_key", "")
	var ghost: Node3D = null
	if old_key != "":
		ghost = MapBuilder.put(world, old_key, (entry.get("centre", n["pos"]) as Vector3) + MapBuilder.centre_lift(old_key), Rules.view_yaw)
		MapBuilder.apply_owner([ghost], was)
	var mis := []
	if ghost:
		for mi in ghost.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mis.append(mi)
	var col := Rules.seat_color(n["owner"])
	var top: Vector3 = (entry.get("centre", n["pos"]) as Vector3) + Vector3(0, 4.0 + 0.9 * lv, 0)
	var label := _tier_label("T%d → T%d" % [lv, now], col, 96)
	var chev := _tier_label("▼", col, 150)
	var ring := MeshInstance3D.new()                   # the dust wave over the platform
	ring.mesh = _plane
	var rmat := ShaderMaterial.new()
	rmat.shader = FLARE_SHADER
	rmat.set_shader_parameter("mode", 2)
	rmat.set_shader_parameter("thickness", 0.07)
	rmat.set_shader_parameter("color", Rules.seat_color(was).lerp(Color(0.85, 0.85, 0.9), 0.4))
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = n["pos"] + Vector3(0, RING_Y + 0.05, 0)
	add_child(ring)
	var old_col := Rules.seat_color(was)
	for i in range(60 if not Rules.low_detail else 30):   # the debris burst off the old top
		var a := randf() * TAU
		var v := Vector3(cos(a), randf_range(0.6, 1.8), sin(a)).normalized() * randf_range(4.0, 10.0)
		var roll := randf()
		var c: Color = HOT if roll < 0.25 else (old_col if roll < 0.65 else Color(0.7, 0.72, 0.8) * 0.8)
		_spark(top + Vector3(randf_range(-1, 1), randf_range(-1.2, 0.4), randf_range(-1, 1)), v, c,
				randf_range(0.14, 0.34), randf_range(0.5, 1.0), 16.0)
	_spark(top, Vector3.ZERO, old_col.lerp(Color.WHITE, 0.5) * 1.6, 3.2, 0.3, 0.0)
	_downs.append({"node": id, "t": 0.0, "ghost": ghost, "mis": mis, "base_y": ghost.position.y if ghost else 0.0,
			"new": null, "new_y": 0.0, "label": label, "chev": chev, "ring": ring, "rmat": rmat,
			"top": top, "col": col, "landed": false, "below": null, "superseded": false})


func after_swap(n: Dictionary, entry: Dictionary) -> void:
	## main._process, just after the swap: the new (lower) tier is the model that rises.
	for d in _downs:
		if d["node"] == n["id"] and d["new"] == null and not d["superseded"]:
			d["new"] = entry["vat_node"]
			d["new_y"] = (entry["vat_node"] as Node3D).position.y if entry["vat_node"] else 0.0


func _tier_label(text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Hud.UI_FONT
	l.font_size = size
	l.outline_size = int(size * 0.22)
	l.outline_modulate = Color(0.02, 0.02, 0.05, 0.95)
	l.modulate = col.lerp(Color.WHITE, 0.15)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.visible = false
	add_child(l)
	return l


func _tier_downs(dt: float, cam: Camera3D) -> void:
	var i := 0
	while i < _downs.size():
		var d: Dictionary = _downs[i]
		d["t"] += dt
		var t: float = d["t"]
		var id: int = d["node"]
		var n: Dictionary = sim.nodes[id]
		var gone: bool = sim.collapsed.get(id, false)
		# the old tier's ghost sinks into the socket, shrinking and fading (0 .. 0.7 s)
		var ghost: Node3D = d["ghost"] if is_instance_valid(d["ghost"]) else null
		if ghost:
			var k := clampf(t / 0.7, 0.0, 1.0)
			if k >= 1.0 or gone:
				ghost.queue_free()
				d["ghost"] = null
			else:
				ghost.position.y = d["base_y"] - 2.6 * k * k
				ghost.scale = Vector3(1.0 - 0.25 * k, 1.0 - 0.5 * k, 1.0 - 0.25 * k)
				for mi in d["mis"]:
					(mi as GeometryInstance3D).transparency = k * k
		# the new tier rises out of the socket with a little overshoot (0.25 .. 0.85 s)
		var nw: Node3D = d["new"] if is_instance_valid(d["new"]) else null
		if nw and not gone:
			var u := clampf((t - 0.25) / 0.6, 0.0, 1.0)
			var e := 1.0 + 2.7 * pow(u - 1.0, 3.0) + 1.7 * pow(u - 1.0, 2.0)   # ease-out-back
			nw.position.y = d["new_y"] - 1.8 * (1.0 - clampf(e, 0.0, 1.1))
			nw.scale = Vector3.ONE * lerpf(0.55, 1.0, e)
			if u >= 1.0 and not d["landed"]:
				d["landed"] = true
				nw.position.y = d["new_y"]
				nw.scale = Vector3.ONE
				_spark(d["top"] - Vector3(0, 0.9, 0), Vector3.ZERO, (d["col"] as Color).lerp(Color.WHITE, 0.4) * 1.5, 2.4, 0.25, 0.0)
		# the dust wave
		var ring: MeshInstance3D = d["ring"]
		var rk := clampf(t / 0.8, 0.0, 1.0)
		ring.visible = rk < 1.0 and not gone
		ring.scale = Vector3.ONE * lerpf(3.0, Rules.R * 2.4, sqrt(rk))
		(d["rmat"] as ShaderMaterial).set_shader_parameter("intensity", 1.4 * (1.0 - rk))
		# "T3 -> T2" and the falling chevron over the node, sized for the screen (about 5 % of its height)
		var label: Label3D = d["label"]
		var chev: Label3D = d["chev"]
		var fade := 1.0 - smoothstep(TIER_DOWN_TIME - 0.5, TIER_DOWN_TIME, t)
		var pop := 1.0 + 0.5 * (1.0 - smoothstep(0.0, 0.25, t))
		var base: Vector3 = n["pos"] + Vector3(0, 9.5, 0)
		var h := 5.0
		if cam:
			h = cam.global_position.distance_to(base) * 0.05
		label.visible = not gone and not d["superseded"]
		chev.visible = not gone and not d["superseded"]
		label.pixel_size = h / float(label.font_size) * pop
		var above := base + Vector3(0, h * 1.1, 0)
		if d["below"] == null:                        # a node under the top bar and its toasts: the line
			d["below"] = cam != null and not cam.is_position_behind(above) 					and cam.unproject_position(above + Vector3(0, h * 0.6, 0)).y < top_limit   # goes under the platform
		if d["below"]:                                 # toward the viewer, past the badge under the platform
			label.position = (n["pos"] as Vector3) + Rules.front_dir() * (Rules.R + 3.3 + h * 1.2) + Vector3(0, 0.4, 0)
		else:
			label.position = above
		label.modulate.a = fade
		label.outline_modulate.a = 0.95 * fade
		var ck := fmod(t, 0.8) / 0.8                  # the chevron keeps falling toward the tower
		chev.pixel_size = h * 0.9 / float(chev.font_size)
		chev.position = base + Vector3(0, -h * 0.9 * ck, 0)
		chev.modulate.a = fade * sin(ck * PI)
		chev.outline_modulate.a = 0.95 * fade * sin(ck * PI)
		if t >= TIER_DOWN_TIME:
			if nw and is_instance_valid(nw):
				nw.position.y = d["new_y"]
				nw.scale = Vector3.ONE
			if ghost and is_instance_valid(ghost):
				ghost.queue_free()
			label.queue_free()
			chev.queue_free()
			ring.queue_free()
			_downs.remove_at(i)
			continue
		i += 1


# ------------------------------------------------------------------ sparks (one MultiMesh)
func _spark(p: Vector3, v: Vector3, c: Color, size: float, life: float, grav: float) -> void:
	if _sp_n >= MAX_SPARKS:
		return
	var i := _sp_n
	_sp_pos[i] = p
	_sp_vel[i] = v
	_sp_col[i] = c
	_sp_size[i] = size
	_sp_life[i] = life
	_sp_max[i] = life
	_sp_grav[i] = grav
	_sp_n += 1


func _update_sparks(dt: float) -> void:
	if _sp_n == 0 and _mm.visible_instance_count == 0:
		return
	var drag := maxf(0.0, 1.0 - 1.4 * dt)
	var i := 0
	while i < _sp_n:
		var life: float = _sp_life[i] - dt
		if life <= 0.0:                               # swap the last one in
			_sp_n -= 1
			_sp_pos[i] = _sp_pos[_sp_n]
			_sp_vel[i] = _sp_vel[_sp_n]
			_sp_col[i] = _sp_col[_sp_n]
			_sp_size[i] = _sp_size[_sp_n]
			_sp_life[i] = _sp_life[_sp_n]
			_sp_max[i] = _sp_max[_sp_n]
			_sp_grav[i] = _sp_grav[_sp_n]
			continue
		_sp_life[i] = life
		var v: Vector3 = _sp_vel[i]
		v.y -= _sp_grav[i] * dt
		v *= drag
		_sp_vel[i] = v
		_sp_pos[i] += v * dt
		var k: float = life / _sp_max[i]
		var c: Color = _sp_col[i]
		c.a = minf(1.0, k * 3.0) * (0.35 + 0.65 * k)
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _sp_pos[i]))
		_mm.set_instance_color(i, c)
		_mm.set_instance_custom_data(i, Color(v.x, v.y, v.z, _sp_size[i] * (0.45 + 0.55 * k)))
		i += 1
	_mm.visible_instance_count = _sp_n


static func _count(x: float) -> int:
	## A whole number of spawns this frame whose average is x (a rate times dt).
	var whole := int(x)
	return whole + (1 if randf() < x - whole else 0)


static func _owner_color(seat: String) -> Color:
	return Rules.seat_color(seat) if seat != "" else Rules.NEUTRAL


# ------------------------------------------------------------------ meshes
static func _annulus_mesh(inner: float, segments: int) -> ArrayMesh:
	## A flat ring, radius inner..1 in XZ; UV.x = angle / TAU (from +X toward +Z), UV.y = 0 inside .. 1 outside.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(segments + 1):
		var a := TAU * k / segments
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d * inner)
		uvs.append(Vector2(float(k) / segments, 0.0))
		verts.append(d)
		uvs.append(Vector2(float(k) / segments, 1.0))
	for k in range(segments):
		var b := k * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _mesh(verts, uvs, idx)


static func _strip_mesh(segments: int) -> ArrayMesh:
	## The beam's unit ribbon: VERTEX.x = -1 / +1 across, UV.y = 0..1 along (the shader places it).
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(segments + 1):
		var t := float(k) / segments
		verts.append(Vector3(-1, 0, 0))
		uvs.append(Vector2(0.0, t))
		verts.append(Vector3(1, 0, 0))
		uvs.append(Vector2(1.0, t))
	for k in range(segments):
		var b := k * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _mesh(verts, uvs, idx)


static func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
