class_name HordeView
extends Node3D
## Draws every horde as Alpha 11 unit models (UnitView), body by body along its path, out of the vats
## (vat_drop) and with the conveyor speed trail. The drawn count follows the real one with a short lag,
## so the line visibly recedes with its losses. The patch meshes (assets/horde/patches_<faction>.glb)
## are still loaded per faction (load_faction, warmed up by warmup.gd), though nothing draws them now.
## SIEGE's goo-patch lines, contact menisci, rivers, corridors, door puddles and transit skirmishes were
## deleted 2026-11-23 (back from tag archive-2026-11-23).

const KINDS := ["head", "body_a", "body_b", "body_c", "tail",
		"body_a_lod1", "body_b_lod1", "body_c_lod1", "tail_lod1"]

const EASE := 7.0                    # 1/s: how quickly the drawn count catches up with losses

var meshes := {}      # faction -> kind -> Mesh
var textures := {}    # faction -> creature Texture2D
var pools := {}       # horde id -> {"vis": float, "fc": float, "speed": the speed trail}
var _last_time := -1.0
var units: UnitView                  # the Alpha 11 unit models every line is drawn with
var vis: Dictionary = {}             # MapBuilder's node entries (main): the vat models the drops come out of
var _spouts := {}                    # node id -> {"vn", "spouts", "rims", "lands", "centre", "plat_y", "back"} (see vat_drop)
var _fog := PackedVector3Array()     # POWERS: this frame's rival Fog of War circles over this screen: (x, z, radius^2)
var _no_fog := PackedVector3Array()   # (never filled: "no fog" for a line)


func load_faction(faction: String) -> void:
	if meshes.has(faction):
		return
	var root: Node = load("res://assets/horde/patches_%s.glb" % faction).instantiate()
	meshes[faction] = {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		for kind in KINDS:
			var tag := "_%s_%s" % [faction, kind]
			if String(mi.name).ends_with(tag) or String(mi.get_parent().name).ends_with(tag):
				meshes[faction][kind] = (mi as MeshInstance3D).mesh
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m and m.albedo_texture and not textures.has(faction):
				textures[faction] = m.albedo_texture
	root.free()


var _sim: Sim                        # the Sim of the last sync (Surge's door rate, Sim.door_mult)


func sync(sim: Sim, viewer: String) -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	_sim = sim
	speed_trails = 0
	if units == null:
		units = UnitView.new()
		add_child(units)
	units.begin(sim.time)
	var dt := 0.0 if _last_time < 0.0 else maxf(sim.time - _last_time, 0.0)
	_last_time = sim.time
	# POWERS (0.22.2): Fog of War - a rival's line inside a circle cast by someone outside this screen's side is not
	# drawn (body by body: UnitView.fog). Your own side's lines always show.
	_fog.clear()
	for e in sim.effects:
		if e["id"] == "fog" and viewer != "" and not sim.allied(str(e["seat"]), viewer):
			var c: Vector3 = sim.nodes[int(e["target"])]["pos"]
			_fog.append(Vector3(c.x, c.z, float(e["radius"]) * float(e["radius"])))
	var alive := {}
	for h in sim.hordes:
		alive[h["id"]] = true
		units.fog = _no_fog if _fog.is_empty() or viewer == "" or sim.allied(str(h["owner"]), viewer) else _fog
		_draw(h, viewer, sim.time, dt, _drop_for(sim, h))
		_draw_speed(h, sim.time)
	units.fog = _no_fog
	for id in pools.keys():
		if not alive.has(id):
			if pools[id].get("speed") != null:
				(pools[id]["speed"] as Node).queue_free()
			pools.erase(id)
	units.flush()
	PerfProfile.lap("horde", _pt)


# ------------------------------------------------------------------ the line
func _draw(h: Dictionary, viewer: String, time: float, dt: float, drop := {}) -> void:
	var faction: String = h["faction"]
	load_faction(faction)
	if not pools.has(h["id"]):
		# 0.20.6 declutter (Daniele: "remove the number on top of units line"): no Label3D any more -
		# the node badges (hud.gd) still show counts.
		pools[h["id"]] = {"vis": float(h["units"]), "fc": h.get("fcut", 0.0)}
	var pool: Dictionary = pools[h["id"]]
	# the drawn count trails the real one a little, so losses read as the line receding, not popping -
	# except what was cut off its FRONT (0.18.7: a cannon hit at the head, walking off a lip): that is
	# gone at once, or the tail would jump back while the head gave way
	var fcut: float = h.get("fcut", 0.0)
	var vis: float = pool["vis"]
	vis -= maxf(fcut - float(pool["fc"]), 0.0) / Rules.metres_per_unit()
	if h["units"] > vis:
		vis = h["units"]
	else:
		vis += (h["units"] - vis) * minf(1.0, EASE * dt)
	pool["vis"] = vis
	pool["fc"] = fcut
	units.door_rate = _sim.door_mult(h) if _sim and _sim.has_method("door_mult") else 1.0   # 0.19.2 Surge: faster doors
	units.add_horde(h, Rules.shown_f(vis), time, drop, Sim.is_ghost_for(h, viewer))   # your own Ghost Line: see-through
	# 0.20.6 declutter (Daniele: "remove the number on top of units line - is not readable and makes
	# noise"): the line no longer carries a moving-count label; the node badges (hud.gd) still count.


# ------------------------------------------------------------------ CONVEYOR CARRY: the speed trail
# Daniele 2026-11-10: a line a belt pushed keeps the belt's speed until its target, a fall or a belt the other way
# (Sim.conveyor_mult). While it moves at a belt factor (on the belt or carried off it) it wears a trail: fast = long
# green streaks racing back along both flanks from the head; slow = short blue dashes creeping, the line dragging them.
const SPEED_STREAKS := 5             # per flank
const SPEED_SPAN := 8.0              # metres behind the head the streaks run over
const SPEED_SIDE := 1.5              # metres out from the line's centre
const SPEED_UP := 0.8
var _speed_mats := {}                # 1 / -1 -> StandardMaterial3D
var _speed_mesh := {}                # 1 / -1 -> BoxMesh
var speed_trails := 0                # lines wearing a trail this frame (probes read it)


func _speed_kit(push: int) -> void:
	if _speed_mats.has(push):
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color("#2bff3c") if push > 0 else Color("#3d7dff")
	m.albedo_color.a = 0.95
	_speed_mats[push] = m
	var b := BoxMesh.new()
	b.size = Vector3(0.32, 0.22, 2.6) if push > 0 else Vector3(0.42, 0.3, 0.8)
	_speed_mesh[push] = b


func _draw_speed(h: Dictionary, time: float) -> void:
	var pool: Dictionary = pools.get(h["id"], {})
	if pool.is_empty():
		return
	var push := int(h.get("conv", 0))
	if push == 0:
		push = int(h.get("conv_carry", 0))
	var root: Node3D = pool.get("speed")
	var hide: bool = push == 0 or h["state"] != "move" or float(h["s"]) < 1.0 			or (not units.fog.is_empty() and UnitView.fogged(units.fog, Sim.sample(h, h["s"])[0]))
	if hide:
		if root != null:
			root.visible = false
		return
	_speed_kit(push)
	if root == null or int(pool.get("speed_push", 0)) != push:
		if root != null:
			root.queue_free()
		root = Node3D.new()
		add_child(root)
		for k in range(SPEED_STREAKS * 2):
			var mi := MeshInstance3D.new()
			mi.mesh = _speed_mesh[push]
			mi.material_override = _speed_mats[push]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		pool["speed"] = root
		pool["speed_push"] = push
	root.visible = true
	speed_trails += 1
	var span: float = minf(SPEED_SPAN, maxf(float(h["s"]) - 0.5, 1.0))
	var rate: float = 2.4 if push > 0 else 0.35          # streak cycles per second (fast race back, slow ones creep)
	var kids := root.get_children()
	for k in range(kids.size()):
		var mi: MeshInstance3D = kids[k]
		var flank := 1.0 if k < SPEED_STREAKS else -1.0
		var j := k % SPEED_STREAKS
		var u := fposmod(time * rate + (float(j) + (0.5 if flank < 0.0 else 0.0)) / SPEED_STREAKS + h["id"] * 0.13, 1.0)
		var s: float = float(h["s"]) - u * span
		var smp := Sim.sample(h, s)
		var fwd: Vector3 = smp[1]
		mi.position = smp[0] + fwd.cross(Vector3.UP).normalized() * SPEED_SIDE * flank + Vector3.UP * SPEED_UP
		mi.rotation = Vector3(0.0, Rules.heading(fwd), 0.0)
		var fade := sin(PI * u)                          # streaks fade in at the head and out at the span's end
		mi.scale = Vector3.ONE * (0.35 + 0.65 * fade)


# ------------------------------------------------------------------ out of the vats
func _drop_for(sim: Sim, h: Dictionary) -> Dictionary:
	## The vat a streaming line is still leaving, if its model can dispense (see vat_drop): its spouts
	## plus what is still to come out of the door. {} = the line starts at the door as before.
	if not h["streaming"]:
		return NO_DROP
	var src: Dictionary = sim.nodes[h["route"][0]]
	if src["streaming"].get("hid", -1) != h["id"] or float(src["streaming"].get("remaining", 0.0)) <= 0.0:
		return NO_DROP
	var p0: Vector3 = (h["pts"] as PackedVector3Array)[0] - (src["pos"] as Vector3)
	var d := vat_drop(src, Rules.TWO_DOORS and p0.dot(Rules.front_dir()) < 0.0)   # TWO DOORS: it leaves by the back
	if d.is_empty():
		return NO_DROP
	var remaining: float = src["streaming"]["remaining"]
	d["remaining"] = remaining                       # the node's cached record: nothing allocated per frame
	d["pending"] = int(ceil(Rules.shown_f(remaining)))
	return d


const NO_DROP := {}                  # (shared, read-only)
# which models drop their units: Cosmetics.drops_from (vats T1-T3, default or skin, 0.19.0); T4 (its core is
# the vat) and relays: from the door


func vat_drop(n: Dictionary, back := false) -> Dictionary:
	## Where a vat drops its units from: the model's `Spout_0`, `Spout_1`, ... markers when it has them
	## (the vat redesign), else the top of each tank found from its liquid (Scenery.tank_info), the
	## blob overflowing the rim. {} while there is no vat to drop from - a relay, T4, a vat being built,
	## or a model still rising after a tier-down. `back` (TWO DOORS): the line leaves by the back door, so the
	## blobs fall off the far side of the tanks and land there instead of in front.
	var id: int = n["id"]
	if vis.is_empty() or not vis.has(id) or n["build_kind"] != "":
		return {}
	var entry: Dictionary = vis[id]
	var key := str(entry.get("model_key", ""))
	var vn = entry.get("vat_node")
	if not Cosmetics.drops_from(key) or not is_instance_valid(vn):
		return {}
	var node := vn as Node3D
	var base: Vector3 = entry.get("centre", n["pos"])
	if not node.visible or not node.scale.is_equal_approx(Vector3.ONE) or absf(node.position.y - base.y) > 0.02:
		return {}
	var c: Dictionary = _spouts.get(id, {})
	if c.is_empty() or c["vn"] != vn:
		c = {"vn": vn, "centre": node.global_position, "plat_y": (n["pos"] as Vector3).y}
		var sp := PackedVector3Array()
		var rims := PackedVector3Array()
		var lands := PackedVector3Array()
		var rims_b := PackedVector3Array()             # TWO DOORS: the same drops toward the back door
		var lands_b := PackedVector3Array()
		var back_dir := -Rules.front_dir()
		var centre: Vector3 = c["centre"]
		var marks := node.find_children("Spout_*", "Node3D", true, false)
		if not marks.is_empty():
			marks.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
			for m in marks:
				var g: Vector3 = (m as Node3D).global_position
				sp.append(g)
				rims.append(g)                          # an outlet: it squeezes straight out
				lands.append(_land(centre, g, float(c["plat_y"])))
				rims_b.append(g)
				lands_b.append(_land(centre, g, float(c["plat_y"]), back_dir))
		else:
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				var info := Scenery.tank_info((mi as MeshInstance3D).mesh, key)
				if info["surface"] < 0:
					continue
				var xf: Transform3D = (mi as MeshInstance3D).global_transform
				for t in info["tanks"]:
					var tc: Vector3 = t["c"]
					var top: Vector3 = xf * Vector3(tc.x, float(t["y1"]) + TANK_CAP, tc.z)
					var rim: Vector3 = top + _out(centre, top) * (float(t["r"]) * 1.2 + 0.25)   # over the cap's edge
					sp.append(top)
					rims.append(rim)
					lands.append(_land(centre, rim, float(c["plat_y"])))
					var rim_b: Vector3 = top + _out(centre, top, back_dir) * (float(t["r"]) * 1.2 + 0.25)
					rims_b.append(rim_b)
					lands_b.append(_land(centre, rim_b, float(c["plat_y"]), back_dir))
				break
		c["spouts"] = sp
		c["rims"] = rims
		c["lands"] = lands
		c["back"] = {"vn": vn, "centre": centre, "plat_y": c["plat_y"], "spouts": sp, "rims": rims_b, "lands": lands_b}
		_spouts[id] = c
	if (c["spouts"] as PackedVector3Array).is_empty():
		return {}
	return c["back"] if back else c


const TANK_CAP := 0.95               # m from a tank's liquid top to the top of its cap (build_kit_2_0 vat_tank)


static func _out(centre: Vector3, p: Vector3, door := Vector3.ZERO) -> Vector3:
	## The way a blob leaves a tank: outward from the vat and toward the camera side (the door's side),
	## so the drop reads in front of the tanks rather than behind them. `door`: toward that door instead
	## (TWO DOORS: a line leaving by the back door).
	var out := p - centre
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.ZERO
	return (out + (Rules.front_dir() if door == Vector3.ZERO else door) * 1.3).normalized()


static func _land(centre: Vector3, rim: Vector3, plat_y: float, door := Vector3.ZERO) -> Vector3:
	return Vector3(rim.x, plat_y + UnitView.BLOB_R * 0.3, rim.z) + _out(centre, rim, door) * UnitView.DROP_OUT
