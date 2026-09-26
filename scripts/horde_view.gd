class_name HordeView
extends Node3D
## Draws every horde as ONE long line of patches (assets/horde/patches_<faction>.glb) along its path:
## the head at the horde's position, patches every Rules.PATCH_SPACING back to the tail. The line's
## length is the horde's size (Sim.chain_length): it streams out of the vat, shrinks as it loses
## units, thickens where it piles up behind a frontline or a queue, and tapers at the tail.
## The two head patches carry full-detail creatures (faces); the body uses the light copies.
## Goo = seat colour; creatures = seat hue + race accent.
##
## Fights (Blender behaviour board case 5 - frontline squash and splash; PLAYTEST-NOTES 1, 3, 6, 7):
##  - the drawn count follows the real one with a short lag, so the line visibly recedes with its
##    losses (from the contact end: the head stays put, the tail comes forward) and thins a little;
##  - every contact gets a goo MENISCUS: two lobes of the two owners' goo joined by a hot seam,
##    so the chains read as one mass where they meet (a friendly queue gets a single-colour bumper);
##  - the patch in contact is squashed (0.7 along, 1.35 up, 1.12 across) and the front of the line
##    rocks back and lunges into the contact in shoves, with a pressure ripple down the whole line
##    and a little sideways jostle; goo splashes off the seam in proportion to each side's losses.
##  A rear attack uses the same pieces on the caught horde's tail.

const KINDS := ["head", "body_a", "body_b", "body_c", "tail",
		"body_a_lod1", "body_b_lod1", "body_c_lod1", "tail_lod1"]
const DETAILED := 2                  # patches from the head that keep full-detail creatures

# fight look (kit local axes: x along travel, y up, z across the deck)
const SQUASH := Vector3(0.7, 1.35, 1.12)        # patch pressed into an enemy
const QUEUE_SQUASH := Vector3(0.86, 1.12, 1.06) # patch pressed into a friend's tail
const SHOVE_HZ := 2.2                # shoves per second at a frontline
const SHOVE_AMP := 0.3               # metres the head rocks back before it lunges
const SHOVE_REACH := 4               # patches from the contact that take part in a shove
const SHOVE_LAG := 0.06              # seconds per patch: the shove travels up from behind
const SURGE_AMP := 0.09              # pressure ripple along a jammed line (metres)
const SURGE_WAVELEN := 3.2           # patches per ripple
const JOSTLE := 0.07                 # sideways jitter near the contact (metres)
const EASE := 7.0                    # 1/s: how quickly the drawn count catches up with losses
const THIN := 0.18                   # a horde down to nothing is drawn this much thinner
const MENISCUS := Vector3(0.75, 0.9, 1.5)       # bumper lobe half-sizes: along, up, across (bulges
const MENISCUS_OFFSET := 0.38        # above the 0.3 m goo film and past the deck edge, so it reads)
const MENISCUS_PULSE := 0.08
const SPLASH_AMOUNT := 40            # droplets per side
const SPLASH_FULL_RATE := 40.0       # units/s lost that saturates a side's splash
const RIVER_SHAPE := Vector3(0.85, 0.9, 1.0)    # a river patch's proportions (along, up, across) at scale 1

var meshes := {}      # faction -> kind -> Mesh
var textures := {}    # faction -> creature Texture2D
var pools := {}       # horde id -> {"patches": [MeshInstance3D], "label": Label3D, "vis": float, "phase": float}
var contacts := {}    # contact key -> {"root", "lobes", "seam", "splash", "seats"}
var rivers := {}      # node id -> {"mm": {"faction|seat|kind": MultiMeshInstance3D}, "vis": float, "sig": String}
var _river_meshes := {}   # "faction|seat|kind" -> Mesh: a copy of the patch with the seat's materials and RIVER_SHAPE baked in
var corridors := {}   # edge index -> [MeshInstance3D] per deck segment: goo covering a deck between two owned nodes
var corridor_state := {}   # edge index -> {fill, anchor, owner}: corridors pour in and drain out
var _lines := {}      # edge index -> [line, cum]: deck centre lines never move during a match
var _corridor_mesh: BoxMesh
var _last_time := -1.0
var _lobe_mesh: SphereMesh
var _drop_meshes := {}   # seat -> SphereMesh with the seat's goo
var units: UnitView                  # classic mode (bridge combat OFF): Alpha 11 unit models
var classic := false                # true this frame when drawing the classic unit look
var vis: Dictionary = {}             # MapBuilder's node entries (main): the vat models the drops come out of
var _spouts := {}                    # node id -> {"vn", "spouts", "rims", "lands", "centre", "plat_y"} (see vat_drop)


func _ready() -> void:
	_lobe_mesh = SphereMesh.new()
	_lobe_mesh.radius = 1.0
	_lobe_mesh.height = 2.0
	_lobe_mesh.radial_segments = 18
	_lobe_mesh.rings = 9
	_corridor_mesh = BoxMesh.new()
	_corridor_mesh.size = Vector3(1.0, 0.08, 1.0)


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


func sync(sim: Sim, viewer: String) -> void:
	classic = not Rules.bridge_combat
	if units == null:
		units = UnitView.new()
		add_child(units)
	units.begin(sim.time)
	var dt := 0.0 if _last_time < 0.0 else maxf(sim.time - _last_time, 0.0)
	_last_time = sim.time
	var by_id := {}
	for h in sim.hordes:
		by_id[h["id"]] = h
	# which end of each horde is in contact, and with what
	var roles := {}
	for key in sim.fight_info:
		var info: Dictionary = sim.fight_info[key]
		var ids: PackedStringArray = key.split(":")
		var a := int(ids[0])
		var b := int(ids[1])
		if not (by_id.has(a) and by_id.has(b)):
			continue
		var other: int = b if info["attacker"] == a else a
		if info["kind"] == "frontline":
			_role(roles, a)["front"] = true
			_role(roles, b)["front"] = true
		else:
			_role(roles, info["attacker"])["front"] = true
			_role(roles, other)["rear"] = true
	for h in sim.hordes:
		if h.has("blocked_by"):
			_role(roles, h["id"])["queue"] = true
	var alive := {}
	for h in sim.hordes:
		alive[h["id"]] = true
		_draw(h, viewer, roles.get(h["id"], {}), sim.time, dt, _drop_for(sim, h))
	for id in pools.keys():
		if not alive.has(id):
			for p in pools[id]["patches"]:
				p.queue_free()
			pools[id]["label"].queue_free()
			if pools[id].get("spray") != null:
				(pools[id]["spray"] as Node).queue_free()
			pools.erase(id)
	_draw_fallers(sim.time)
	var seen := _sync_contacts(sim, by_id)
	_draw_rivers(sim, seen, dt)
	_draw_transit_skirmishes(sim, seen)
	_draw_corridors(sim)
	_draw_puddles(sim)
	units.flush()
	for key in contacts.keys():
		if not seen.has(key):
			contacts[key]["root"].queue_free()
			contacts.erase(key)


func _role(roles: Dictionary, id: int) -> Dictionary:
	if not roles.has(id):
		roles[id] = {}
	return roles[id]


# ------------------------------------------------------------------ the line
func _draw(h: Dictionary, viewer: String, role: Dictionary, time: float, dt: float, drop := {}) -> void:
	var faction: String = h["faction"]
	load_faction(faction)
	if not pools.has(h["id"]):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.014
		label.font_size = 56                           # smaller: the badge is the number to read
		label.outline_size = 16
		label.no_depth_test = true
		label.modulate = Rules.seat_color(h["owner"])
		add_child(label)
		pools[h["id"]] = {"patches": [], "label": label, "vis": float(h["units"]), "phase": fposmod(h["id"] * 0.37, 1.0),
				"fc": h.get("fcut", 0.0), "kp": -1, "L": h["L"], "spray": null}
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
	var full := Sim.full_length(vis)
	var length := minf(full, maxf(h["s"], 1.0))
	# the patches keep their places along the line as its front is cut off: patch k (counted from the
	# line's first) sits at s + fcut - k * spacing; the ones past the head are gone (popped / fallen)
	var sp_len := Rules.PATCH_SPACING
	var k0 := maxi(int(ceil(fcut / sp_len - 0.0001)), 0)
	var off := k0 * sp_len - fcut                             # 0..spacing: the head patch sits this far behind s
	if fcut <= 0.0:
		off = 0.0
	var n := clampi(int(maxf(length - off, 0.0) / sp_len) + 1, 1, Rules.MAX_PATCHES)
	var rest := length - off - (n - 1) * sp_len               # fraction of the last patch
	if pool["L"] != h["L"] or fcut < float(pool["fc"]) - 1.0 or int(pool["kp"]) < 0:
		pool["kp"] = k0                                       # a new path: nothing to drop
		pool["L"] = h["L"]
	pool["fc"] = fcut
	if not classic:
		_front_gone(h, pool, k0, time)
	var pile := clampf(full / maxf(length, 1.0), 1.0, 1.5)    # jammed behind a frontline/queue
	var big := clampf((vis * Rules.METRES_PER_UNIT - Rules.MAX_CHAIN) / Rules.MAX_CHAIN, 0.0, Rules.MAX_THICKEN)
	var thin := 1.0 - THIN * (1.0 - clampf(vis / maxf(h["start_units"], 1.0), 0.0, 1.0))
	var thick := pile * (1.0 + big) * thin
	var front: bool = role.get("front", false)
	var rear: bool = role.get("rear", false)
	var queue: bool = role.get("queue", false)
	var blocked: bool = h.get("blocked", false)
	var agitated: bool = front or rear or queue or blocked
	var phase: float = pool["phase"]
	var t: float = time + phase / SHOVE_HZ
	var arr: Array = pool["patches"]
	var slots := SLOTS if k0 > 0 else n                   # patch k lives in slot k % SLOTS once the front is cut
	while not classic and arr.size() < slots:        # BRAWL draws unit models, never these patches
		var mi := MeshInstance3D.new()
		add_child(mi)
		arr.append(mi)
	if classic:
		units.add_horde(h, Rules.shown_f(vis), time, drop)
	elif not drop.is_empty():
		units.add_goo_drops(h["owner"], drop, Sim.sample(h, 0.0)[0], Rules.shown_f(h["ordered"] - float(drop["remaining"])),
				Rules.shown_f(h["ordered"]))
	for q in range(arr.size()):
		var mi: MeshInstance3D = arr[q]
		var i := posmod(q - k0, SLOTS) if k0 > 0 else q
		var s: float = h["s"] - off - i * sp_len
		if i >= n or s < 0.0 or classic:
			mi.visible = false
			continue
		var kind: String = "head" if i == 0 else ("tail" if i == n - 1 else KINDS[1 + ((k0 + i) % 3)])
		if i >= DETAILED and kind != "head":
			kind += "_lod1"
		var mesh: Mesh = meshes[faction][kind]
		if mi.mesh != mesh:
			mi.mesh = mesh
			for sidx in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(sidx) as BaseMaterial3D
				var is_creature := m != null and m.albedo_texture != null
				mi.set_surface_override_material(sidx, Mats.creature(faction, h["owner"], textures[faction])
						if is_creature else Mats.goo(h["owner"]))
		mi.visible = true
		# motion at a contact: shoves from the contact end, a ripple down the line, sideways jostle
		var along := 0.0
		var side := 0.0
		var slam := 0.0
		if agitated:
			along += SURGE_AMP * sin(TAU * (t * SHOVE_HZ * 0.5 - float(i) / SURGE_WAVELEN))
			var k := -1                                # patches from the contact end
			if front or queue:
				k = i
			elif rear:
				k = n - 1 - i
			if k >= 0 and k < SHOVE_REACH:
				var env := 1.0 - float(k) / SHOVE_REACH
				var shove := _shove(t - k * SHOVE_LAG)
				along += (SHOVE_AMP * (0.5 if queue and not (front or rear) else 1.0)) * env * shove[0]
				slam = env * shove[1]
				side = JOSTLE * env * sin(t * 9.0 + i * 1.7)
				if rear and not front:
					along = -along                     # a tail is shoved backwards, toward its head
		var smp := Sim.sample(h, s + along)
		var fwd: Vector3 = smp[1]
		mi.position = smp[0] + fwd.cross(Vector3.UP) * side
		mi.rotation = Vector3(0.0, Rules.heading(fwd), 0.0)
		var sc := 1.0
		var from_tail := n - 1 - i
		if n >= 4 and from_tail < 3:                   # the line tapers off at the tail
			sc = TAPER[from_tail]
		if i == n - 1 and n > 1:
			sc *= clampf(0.3 + rest / sp_len, 0.3, 1.0)   # grows/shrinks smoothly
		if h["state"] == "absorb" and i == 0:
			sc = 0.45                                  # squeezing in through the door
		elif s < 2.0:
			sc *= 0.5 + 0.25 * s                       # emerging from the tank bottoms
		var tk := thick if i > 0 else lerpf(1.0, thick, 0.5)
		var scale := Vector3(sc, sc * tk, sc * tk)
		if (front and i == 0) or (rear and i == n - 1):
			scale *= Vector3.ONE.lerp(SQUASH, 0.7 + 0.3 * slam)   # pressed into the enemy, harder on the slam
		elif queue and i == 0:
			scale *= QUEUE_SQUASH
		mi.scale = scale
		if ForgePulse.live:                          # a forge coming online: the line glows, hops and swells in its wave
			var fb := ForgePulse.boost(h["owner"], mi.position, 3.2)
			mi.scale = scale * (1.0 + ForgePulse.SWELL * fb)
			mi.position.y += ForgePulse.HOP * fb
	var label: Label3D = pool["label"]
	var head: Vector3 = Sim.sample(h, h["s"])[0]
	label.position = head + Vector3(0, 3.0, 0)
	if h["owner"] != viewer:
		label.text = ""
	elif h.get("retreat", false):
		label.text = "%d  RETREAT" % Rules.shown(h["units"])
	elif h["streaming"]:                              # out + still inside the vat (re-orderable)
		label.text = "%d +%d" % [Rules.shown(h["units"]), Rules.shown(h["ordered"] - h["units"])]
	else:
		label.text = str(Rules.shown(h["units"]))


const SLOTS := Rules.MAX_PATCHES + 1  # patch pool slots of a line whose front has been cut
const TAPER := [0.55, 0.75, 0.9]


# ------------------------------------------------------------------ the front: cannon pops, the pour
# 0.18.7 (Daniele: "towers kills enemies blobs from the bottom instead of from the top"; the waterfall
# "should be seamless and exaggerates so it looks cooler (exaggeration still should be kept in the ratio
# of the actual units lets say a +20%)"): a patch cut off the head pops where it was (a cannon hit) or
# walks off the lip and falls with its momentum (a missing deck), one per patch that really went plus a
# spray patch for every five (+20 % at most); droplets keep spraying off the lip while the line pours.
const FALL_POOL := 64
const FALL_T := 1.7
const POUR_G := 19.0
const POUR_HOP := 2.2
const POP_T := 0.28
var _fallers: Array = []             # [MeshInstance3D] pooled, reused
var _fl_t := PackedFloat32Array()    # start time (-1 = free)
var _fl_p := PackedVector3Array()
var _fl_v := PackedVector3Array()
var _fl_spin := PackedVector3Array()
var _fl_mode := PackedByteArray()    # 1 pop, 2 fall
var _fl_next := 0
var falls_drawn := 0                 # patches sent off a lip, spray included (probes read these)
var falls_real := 0
var pops := 0


func _front_gone(h: Dictionary, pool: Dictionary, k0: int, time: float) -> void:
	## Patches kp..k0-1 have gone off the front since last frame.
	var kp: int = pool["kp"]
	if kp >= k0:
		return
	var pour: bool = h.get("pour", false) and h["state"] != "absorb"
	var lip: float = h.get("pour_lip", -1.0)
	var fall_from: float = float(h.get("pour_k", 0.0)) - 0.5 * Rules.PATCH_SPACING
	var anchor: float = h["s"] + float(h.get("fcut", 0.0))
	var steps := 0
	while kp < k0 and steps < 12:
		var at: float = anchor - kp * Rules.PATCH_SPACING
		if pour:
			if kp * Rules.PATCH_SPACING >= fall_from:
				_spawn_patch(h, 2, lip, maxf(at - lip, 0.0), time, pool)
		else:
			_spawn_patch(h, 1, minf(at, h["L"]), 0.0, time, pool)
		kp += 1
		steps += 1
	pool["kp"] = k0                                    # a big cut (a whole stretch) drops its tail end only
	if pour:
		_spray(h, pool, lip)
	elif pool["spray"] != null:
		(pool["spray"] as CPUParticles3D).emitting = false


func _spawn_patch(h: Dictionary, mode: int, at: float, over: float, time: float, pool: Dictionary) -> void:
	var faction: String = h["faction"]
	load_faction(faction)
	var mesh: Mesh = meshes[faction].get("body_a_lod1", null)
	if mesh == null:
		return
	if _fallers.is_empty():                          # the pool, made once
		_fl_t.resize(FALL_POOL)
		_fl_p.resize(FALL_POOL)
		_fl_v.resize(FALL_POOL)
		_fl_spin.resize(FALL_POOL)
		_fl_mode.resize(FALL_POOL)
		for i in range(FALL_POOL):
			var mi := MeshInstance3D.new()
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_fallers.append(mi)
			_fl_t[i] = -1.0
	var smp := Sim.sample(h, at)
	var fwd: Vector3 = smp[1]
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(1, 0, 0)
	var side := fwd.cross(Vector3.UP)
	var n := 1
	if mode == 2:
		falls_real += 1
		pool["fr"] = int(pool.get("fr", 0)) + 1
		if float(pool.get("fs", 0) + 1) <= UnitView.POUR_EXTRA * float(pool["fr"]) + 0.0001:
			pool["fs"] = int(pool.get("fs", 0)) + 1  # the +20 % spray: one per five real patches of this line
			n = 2
		falls_drawn += n
	else:
		pops += 1
	for c in range(n):
		var i := _fl_next
		_fl_next = (_fl_next + 1) % FALL_POOL
		var mi: MeshInstance3D = _fallers[i]
		if mi.mesh != mesh or mi.get_meta("seat", "") != h["owner"]:
			mi.mesh = mesh
			mi.set_meta("seat", h["owner"])
			for sidx in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(sidx) as BaseMaterial3D
				var is_creature := m != null and m.albedo_texture != null
				mi.set_surface_override_material(sidx, Mats.creature(faction, h["owner"], textures[faction])
						if is_creature else Mats.goo(h["owner"]))
		var r1 := UnitView._rnd(h["id"] + c * 17, int(at * 10.0))
		var r2 := UnitView._rnd(int(at * 10.0) + c, h["id"])
		_fl_p[i] = (smp[0] as Vector3) + side * (r1 - 0.5) * (0.4 + 1.2 * c)
		_fl_mode[i] = mode
		if mode == 1:
			_fl_v[i] = Vector3.ZERO
			_fl_t[i] = time
			_fl_spin[i] = Vector3(0.0, Rules.heading(fwd), 0.0)
		else:
			var v := Rules.move_speed()
			_fl_v[i] = fwd * v * lerpf(0.95, 1.2, r1) * (0.85 if c > 0 else 1.0) + side * (r2 - 0.5) * 2.6 \
					+ Vector3.UP * POUR_HOP * (1.3 if c > 0 else 1.0)
			_fl_t[i] = time - clampf(over, 0.0, 2.0) / v - 0.06 * c
			_fl_spin[i] = Vector3((r1 - 0.3) * 5.0, Rules.heading(fwd), (r2 - 0.5) * 5.0)


func _draw_fallers(time: float) -> void:
	for i in range(_fallers.size()):
		var mi: MeshInstance3D = _fallers[i]
		if _fl_t[i] < -0.5 and not mi.visible:
			continue
		var age := time - _fl_t[i]
		var mode := _fl_mode[i]
		if _fl_t[i] < -0.5 or age > (POP_T if mode == 1 else FALL_T) or classic:
			mi.visible = false
			_fl_t[i] = -1.0
			continue
		if age < 0.0:
			mi.visible = false
			continue
		mi.visible = true
		var sp: Vector3 = _fl_spin[i]
		if mode == 1:                                  # pop: the patch bursts - swells flat, then is gone
			var k := age / POP_T
			var sw := (1.0 + 0.6 * sin(minf(k * 2.2, 1.0) * PI * 0.5)) * (1.0 - smoothstep(0.4, 1.0, k))
			mi.position = _fl_p[i] + Vector3.UP * 0.25 * k
			mi.rotation = Vector3(0.0, sp.y, 0.0)
			mi.scale = Vector3(1.25, 0.7, 1.35) * maxf(sw, 0.01)
		else:
			var v: Vector3 = _fl_v[i]
			mi.position = _fl_p[i] + Vector3(v.x, 0.0, v.z) * age + Vector3.UP * (v.y * age - 0.5 * POUR_G * age * age)
			mi.rotation = Vector3(sp.x * age, sp.y, sp.z * age)
			var st := 1.0 + 0.5 * clampf(age / 0.6, 0.0, 1.0)            # the goo stretches as it drops
			mi.scale = Vector3(1.0 / st, st, 1.0 / st) * (1.0 - 0.4 * smoothstep(FALL_T * 0.6, FALL_T, age))


func _spray(h: Dictionary, pool: Dictionary, lip: float) -> void:
	## Goo droplets off the lip while the line pours (one emitter per pouring line, made once).
	if pool["spray"] == null:
		var p := _splash(h["owner"], 0.0)
		p.local_coords = false
		p.amount = 24
		p.lifetime = 1.1
		p.spread = 28.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0.0, -POUR_G, 0.0)
		add_child(p)
		pool["spray"] = p
	var sp: CPUParticles3D = pool["spray"]
	var smp := Sim.sample(h, lip)
	var fwd: Vector3 = smp[1]
	fwd.y = 0.0
	sp.position = (smp[0] as Vector3) + Vector3(0, 0.25, 0)
	sp.direction = (fwd.normalized() + Vector3(0, 0.35, 0)) if fwd.length() > 0.01 else Vector3.UP
	sp.emitting = true


# ------------------------------------------------------------------ out of the vats
func _drop_for(sim: Sim, h: Dictionary) -> Dictionary:
	## The vat a streaming line is still leaving, if its model can dispense (see vat_drop): its spouts
	## plus what is still to come out of the door. {} = the line starts at the door as before.
	if not h["streaming"]:
		return NO_DROP
	var src: Dictionary = sim.nodes[h["route"][0]]
	if src["streaming"].get("hid", -1) != h["id"] or float(src["streaming"].get("remaining", 0.0)) <= 0.0:
		return NO_DROP
	var d := vat_drop(src)
	if d.is_empty():
		return NO_DROP
	var remaining: float = src["streaming"]["remaining"]
	d["remaining"] = remaining                       # the node's cached record: nothing allocated per frame
	d["pending"] = int(ceil(Rules.shown_f(remaining)))
	return d


const NO_DROP := {}                  # (shared, read-only)
const DROP_MODELS := ["Vat_T1", "Vat_T2", "Vat_T3"]  # T4 (its core is the vat) and relays: from the door


func vat_drop(n: Dictionary) -> Dictionary:
	## Where a vat drops its units from: the model's `Spout_0`, `Spout_1`, ... markers when it has them
	## (the vat redesign), else the top of each tank found from its liquid (Scenery.tank_info), the
	## blob overflowing the rim. {} while there is no vat to drop from - a relay, T4, a vat being built,
	## or a model still rising after a tier-down.
	var id: int = n["id"]
	if vis.is_empty() or not vis.has(id) or n["build_kind"] != "":
		return {}
	var entry: Dictionary = vis[id]
	var key := str(entry.get("model_key", ""))
	var vn = entry.get("vat_node")
	if not key in DROP_MODELS or not is_instance_valid(vn):
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
		var centre: Vector3 = c["centre"]
		var marks := node.find_children("Spout_*", "Node3D", true, false)
		if not marks.is_empty():
			marks.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
			for m in marks:
				var g: Vector3 = (m as Node3D).global_position
				sp.append(g)
				rims.append(g)                          # an outlet: it squeezes straight out
				lands.append(_land(centre, g, float(c["plat_y"])))
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
				break
		c["spouts"] = sp
		c["rims"] = rims
		c["lands"] = lands
		_spouts[id] = c
	if (c["spouts"] as PackedVector3Array).is_empty():
		return {}
	return c


const TANK_CAP := 0.95               # m from a tank's liquid top to the top of its cap (build_kit_2_0 vat_tank)


static func _out(centre: Vector3, p: Vector3) -> Vector3:
	## The way a blob leaves a tank: outward from the vat and toward the camera side (the door's side),
	## so the drop reads in front of the tanks rather than behind them.
	var out := p - centre
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.ZERO
	return (out + Rules.front_dir() * 1.3).normalized()


static func _land(centre: Vector3, rim: Vector3, plat_y: float) -> Vector3:
	return Vector3(rim.x, plat_y + UnitView.BLOB_R * 0.3, rim.z) + _out(centre, rim) * UnitView.DROP_OUT


static func _shove(t: float) -> Array:
	## [offset (-1..+0.15), slam (0..1)] of one shove cycle: rock back for 70 % of the period, then
	## slam forward into the contact.
	var w := fposmod(t * SHOVE_HZ, 1.0)
	if w < 0.7:
		var u := w / 0.7
		return [-smoothstep(0.0, 1.0, u), 0.0]
	var v := (w - 0.7) / 0.3
	var slam := sin(v * PI)
	return [lerpf(-1.0, 0.15, smoothstep(0.0, 1.0, minf(v * 1.6, 1.0))), slam]


# ------------------------------------------------------------------ contacts
func _sync_contacts(sim: Sim, by_id: Dictionary) -> Dictionary:
	## Places a meniscus at every deck contact; returns the contact keys in use this frame.
	var seen := {}
	for key in sim.fight_info:
		var info: Dictionary = sim.fight_info[key]
		var ids: PackedStringArray = key.split(":")
		var a := int(ids[0])
		var b := int(ids[1])
		if not (by_id.has(a) and by_id.has(b)):
			continue
		var att: Dictionary = by_id[info["attacker"]]
		var oth: Dictionary = by_id[b if info["attacker"] == a else a]
		var pa := Sim.sample(att, att["s"])
		var pb := Sim.sample(oth, oth["s"]) if info["kind"] == "frontline" \
				else Sim.sample(oth, oth["s"] - Sim.chain_length(oth))
		_place_contact(key, ((pa[0] as Vector3) + (pb[0] as Vector3)) / 2.0, pa[1], [att["owner"], oth["owner"]],
				[att.get("loss_rate", 0.0), oth.get("loss_rate", 0.0)], sim.time)
		seen[key] = true
	for h in sim.hordes:                                  # friendly queue: one bumper joins the two lines
		if h.has("blocked_by") and by_id.has(h["blocked_by"]):
			var friend: Dictionary = by_id[h["blocked_by"]]
			var key := "q%d" % h["id"]
			var pa := Sim.sample(h, h["s"])
			var pb := Sim.sample(friend, friend["s"] - Sim.chain_length(friend))
			var mid := ((pa[0] as Vector3) + (pb[0] as Vector3)) / 2.0
			if (pa[0] as Vector3).distance_to(pb[0]) > Rules.PATCH_SPACING * 1.5:
				mid = (pa[0] as Vector3) + (pa[1] as Vector3) * 0.9
			_place_contact(key, mid, pa[1], [h["owner"], h["owner"]], [0.0, 0.0], sim.time)
			seen[key] = true
	return seen


func _draw_corridors(sim: Sim) -> void:
	## GOO CORRIDORS (Daniele, Alpha 14): always on between any two adjacent nodes one player owns
	## (Sim.bonded); enemies on them are slower and lose the tug-of-war push. Capture either end and
	## the corridor DRAINS - the goo pulls back toward the end still held over ~1 s - so breaking a
	## link is a clear goal with a visible payoff. New corridors pour in the same way. The goo follows
	## the deck rim to rim, up the ramps and along the raised span of an overpass (maps-overpass).
	var dt := get_process_delta_time()
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var a: Dictionary = sim.nodes[e["a"]]
		var b: Dictionary = sim.nodes[e["b"]]
		var held: bool = sim.bonded(i) and not classic
		var st: Dictionary = corridor_state.get(i, {})
		if st.is_empty():
			if not held:
				continue
			st = {"fill": 0.0, "anchor": 0.5, "owner": a["owner"]}
			corridor_state[i] = st
		if held:
			st["owner"] = a["owner"]
			st["anchor"] = 0.5
		elif st["fill"] > 0.0 and st["anchor"] == 0.5:
			# drain toward whichever end the corridor's owner still holds (or the middle)
			var o: String = st["owner"]
			st["anchor"] = 0.0 if a["owner"] == o else (1.0 if b["owner"] == o else 0.49)
		st["fill"] = move_toward(st["fill"], 1.0 if held else 0.0, dt * (1.5 if held else 1.0))
		if st["fill"] <= 0.01:                            # drained: nothing to lay
			for mi in corridors.get(i, []):
				(mi as MeshInstance3D).visible = false
			continue
		if not _lines.has(i):
			var l: Array = sim.deck_line(i)
			var cm := [0.0]
			for k in range(1, l.size()):
				cm.append(cm[k - 1] + (l[k] as Vector3).distance_to(l[k - 1]))
			_lines[i] = [l, cm]
		var line: Array = _lines[i][0]
		if line.is_empty():
			continue                                      # maps 3.0 plaza link: no deck to coat
		if not corridors.has(i):
			var made := []
			for k in range(line.size() - 1):
				var mi := MeshInstance3D.new()
				mi.mesh = _corridor_mesh
				add_child(mi)
				made.append(mi)
			corridors[i] = made
		var parts: Array = corridors[i]
		var cum: Array = _lines[i][1]
		var total: float = cum[-1]
		var fill: float = st["fill"]
		var cover := total * fill
		var c0: float = st["anchor"] * (total - cover)       # the covered stretch along the deck
		var c1: float = c0 + cover
		var sink := 0.12 * (1.0 - fill) * (0.0 if held else 1.0)
		var mat := Mats.goo(st["owner"])
		for k in range(parts.size()):
			var mi: MeshInstance3D = parts[k]
			var s0: float = maxf(cum[k], c0)
			var s1: float = minf(cum[k + 1], c1)
			if fill <= 0.01 or s1 - s0 <= 0.01:
				mi.visible = false
				continue
			var p0: Vector3 = line[k]
			var p1: Vector3 = line[k + 1]
			var seg_len: float = maxf(cum[k + 1] - cum[k], 0.001)
			var q0: Vector3 = p0.lerp(p1, (s0 - cum[k]) / seg_len)
			var q1: Vector3 = p0.lerp(p1, (s1 - cum[k]) / seg_len)
			var seg := q1 - q0
			mi.visible = true
			if mi.material_override != mat:
				mi.material_override = mat
			mi.position = (q0 + q1) / 2.0 + Vector3(0, 0.06 - sink, 0)
			var x := seg.normalized()
			var z := x.cross(Vector3.UP).normalized()
			mi.basis = Basis(x * maxf(seg.length(), 0.01), z.cross(x), z * Rules.W * 0.92 * lerpf(0.6, 1.0, fill))


var puddles := {}     # node id -> MeshInstance3D: the pool at the tank bottoms while an order drains out
var _puddle_mesh: CylinderMesh


func _draw_puddles(sim: Sim) -> void:
	## EXIT BY DRAINING FROM THE TANK BOTTOMS (behaviour board F): while a vat's door is emitting an
	## order, a pool of the owner's goo swells at the tower's foot on the side the line leaves by.
	if _puddle_mesh == null:
		_puddle_mesh = CylinderMesh.new()
		_puddle_mesh.top_radius = 1.0
		_puddle_mesh.bottom_radius = 1.0
		_puddle_mesh.height = 0.16
		_puddle_mesh.radial_segments = 20
	for n in sim.nodes:
		var id: int = n["id"]
		var streaming: bool = not n["streaming"].is_empty() and not classic
		if not streaming:
			if puddles.has(id):
				(puddles[id] as MeshInstance3D).visible = false
			continue
		if not puddles.has(id):
			var mi := MeshInstance3D.new()
			mi.mesh = _puddle_mesh
			add_child(mi)
			puddles[id] = mi
		var mi: MeshInstance3D = puddles[id]
		var h: Dictionary = sim._horde(n["streaming"]["hid"])
		if h.is_empty():
			mi.visible = false
			continue
		mi.visible = true
		mi.material_override = Mats.goo(n["owner"])
		var start: Vector3 = h["pts"][0]
		var d: Vector3 = ((start - n["pos"]) as Vector3).normalized()
		var remaining: float = n["streaming"]["remaining"]
		var swell := clampf(remaining / 120.0, 0.25, 1.0)
		mi.position = n["pos"] + d * (Rules.EXIT_R - 0.6) + Vector3(0, 0.12, 0)
		var pulse := 1.0 + 0.08 * sin(sim.time * 5.0)
		mi.scale = Vector3(1.4 + 1.2 * swell, 1.0, 1.0 + 0.9 * swell) * pulse


func _draw_transit_skirmishes(sim: Sim, seen: Dictionary) -> void:
	## An order passing through a node fights right there (sim.gd _register_transit) - show it AT
	## the platform (on the river's rim), not wherever the long line's tail happens to be, so it
	## never reads as "fighting in the corridor" (Daniele, 2026-09-25).
	for n in sim.nodes:
		if n["transit"].is_empty():
			continue
		for seat in n["transit"]:
			var info: Dictionary = n["transit"][seat]
			if (info["hordes"] as Array).is_empty():
				continue
			var h: Dictionary = info["hordes"][0]
			var head: Vector3 = Sim.sample(h, h["s"])[0]
			var dir: Vector3 = ((head - (n["pos"] as Vector3)) as Vector3)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			var spot: Vector3 = (n["pos"] as Vector3) + dir * Rules.RIVER_R
			var key := "tr%d_%s" % [n["id"], seat]
			_place_contact(key, spot, dir, [seat, n["owner"]],
					[n["node_loss"].get(seat, 0.0), n["node_loss"].get(n["owner"], 0.0)], sim.time)
			seen[key] = true


# ------------------------------------------------------------------ rivers: the platform is the node
func _draw_rivers(sim: Sim, seen: Dictionary, dt: float) -> void:
	## Each platform carries a ring of goo around its tower: the owner's river, sized by how full
	## the vat is. Units fighting on the platform (siege) take a share of the ring centred on the
	## side they landed from, with a meniscus and splash at each seam (Daniele, 2026-09-25).
	## The ring (inner ring by the tower + outer ring to the rim) is drawn with one MultiMesh per
	## (faction, seat, patch kind) on each platform, not one node per patch: the rings were half of
	## all draw calls. A quiet platform (no siege, same owner, mode and detail, fill within 1/4000 of
	## a patch's size) keeps last frame's instances and skips the slot loop.
	for n in sim.nodes:
		var id: int = n["id"]
		if not rivers.has(id):
			rivers[id] = {"mm": {}, "vis": 0.0}
		var r: Dictionary = rivers[id]
		if sim.collapsed.get(id, false):                 # a fallen platform takes its river with it
			_hide_river(r)
			continue
		var total: float = n["units"]
		for k in n["siege"]:
			total += n["siege"][k]
		var vis: float = r["vis"]
		vis += (total - vis) * minf(1.0, EASE * 0.6 * dt)
		r["vis"] = vis
		if vis < 1.0:
			_hide_river(r)
			continue
		var fill := clampf(total / float(Rules.CAPS[n["tier"]]), 0.0, 1.0)
		# the goo covers the whole platform whatever the count (Daniele, Alpha 16: "was nice when it
		# covered all of the platform"); a low vat only thins it a little - the badge carries the number
		var sc := lerpf(0.85, 1.0, sqrt(fill))
		var contested: bool = not n["siege"].is_empty()
		var forged := ForgePulse.live and ForgePulse.powering(n["owner"])   # the owner's forge wave: the ring swells
		if contested or forged:
			r.erase("sig")                              # a siege redraws every frame (seethe, attacker slots, seams)
		else:
			var sig := "%s|%d|%s|%s" % [n["owner"], roundi(sc * 4000.0), str(classic), str(Rules.low_detail)]
			if r.get("sig", "") == sig:
				continue                                  # quiet platform: nothing on its ring changed
			r["sig"] = sig
		# slot ownership: attackers get their share centred where they landed, the owner the rest
		var slots := []
		slots.resize(Rules.RIVER_SLOTS)
		slots.fill(n["owner"])
		var faces_in := []
		faces_in.resize(Rules.RIVER_SLOTS)
		faces_in.fill(false)
		for k in n["siege"]:
			var share: float = n["siege"][k] / maxf(total, 0.001)
			var count := clampi(int(round(share * Rules.RIVER_SLOTS)), 1, Rules.RIVER_SLOTS)
			var d: Vector3 = n["siege_dir"][k]
			var centre := int(round(fposmod(atan2(d.z, d.x), TAU) / TAU * Rules.RIVER_SLOTS))
			for j in range(count):
				var idx := posmod(centre - count / 2 + j, Rules.RIVER_SLOTS)
				slots[idx] = k
				faces_in[idx] = true
		var xfs := {}                                     # "faction|seat|kind" -> [Transform3D] this frame
		for j in range(Rules.RIVER_SLOTS * 2):
			var outer := j >= Rules.RIVER_SLOTS
			var i := j % Rules.RIVER_SLOTS
			if Rules.low_detail and (i % 2 == 1 or outer):
				continue
			if outer and classic:
				continue
			var seat: String = slots[i]
			var faction: String = sim.factions.get(seat, "null")
			if classic:                                # a ring of creatures, no goo
				if seat == "" or seat == n["owner"] or not faces_in[i]:
					continue                              # no loitering garrison: only attackers on the platform show
				var ua := TAU * i / Rules.RIVER_SLOTS
				var ur := Vector3(cos(ua), 0.0, sin(ua))
				var bob := absf(sin(sim.time * (8.0 if contested else 2.0) + i)) * (0.25 if contested else 0.05)
				units.add_unit(faction, seat, n["pos"] + ur * Rules.RIVER_R, Rules.heading(-ur), bob)
				continue
			load_faction(faction)
			var kind: String = ["body_a_lod1", "body_b_lod1", "body_c_lod1"][i % 3]
			var a := TAU * (i + (0.5 if outer else 0.0)) / Rules.RIVER_SLOTS
			var radial := Vector3(cos(a), 0.0, sin(a))
			var pos: Vector3 = n["pos"] + radial * (Rules.RIVER_OUTER_R if outer else Rules.RIVER_R)
			var fwd := -radial if faces_in[i] else Vector3(-sin(a), 0.0, cos(a))
			var s := sc
			if contested:                              # the whole platform seethes
				pos += radial * 0.18 * sin(sim.time * 6.0 + i * 1.3)
				s *= 1.0 + 0.08 * sin(sim.time * 7.0 + i * 2.1)
			if forged:
				var fb := ForgePulse.boost(seat, pos, 0.0)
				s *= 1.0 + ForgePulse.SWELL * fb
				pos.y += ForgePulse.HOP * 0.6 * fb
			# rotation (0, heading, 0) and scale s * RIVER_SHAPE, the shape part baked into the mesh
			(xfs.get_or_add("%s|%s|%s" % [faction, seat, kind], []) as Array).append(
					Transform3D(Basis(Vector3.UP, Rules.heading(fwd)) * Basis.from_scale(Vector3.ONE * s), pos))
			# seam with the next slot: meniscus + splash between the two owners
			var nxt: String = slots[(i + 1) % Rules.RIVER_SLOTS]
			if nxt != seat and not outer:
				var key := "n%d_%d" % [id, i]
				var a2 := TAU * (i + 0.5) / Rules.RIVER_SLOTS
				var spos: Vector3 = n["pos"] + Vector3(cos(a2), 0.0, sin(a2)) * Rules.RIVER_R
				var sfwd := Vector3(-sin(a2), 0.0, cos(a2))
				_place_contact(key, spos, sfwd, [seat, nxt],
						[n["node_loss"].get(seat, 0.0), n["node_loss"].get(nxt, 0.0)], sim.time)
				(contacts[key]["root"] as Node3D).scale = Vector3.ONE * (0.6 + 0.4 * sc)
				seen[key] = true
		for key in xfs:
			var mm := _river_mmi(r, n["pos"], key).multimesh
			var xf: Array = xfs[key]
			for q in range(xf.size()):
				mm.set_instance_transform(q, xf[q])
			mm.visible_instance_count = xf.size()
		for key in r["mm"]:
			if not xfs.has(key):
				(r["mm"][key] as MultiMeshInstance3D).multimesh.visible_instance_count = 0


func _hide_river(r: Dictionary) -> void:
	for key in r["mm"]:
		(r["mm"][key] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	r.erase("sig")                                        # redraw in full when the ring comes back


func _river_mmi(r: Dictionary, centre: Vector3, key: String) -> MultiMeshInstance3D:
	## The platform's MultiMesh for one "faction|seat|kind", made on first use.
	if not r["mm"].has(key):
		var parts := key.split("|")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _river_mesh(parts[0], parts[1], parts[2])
		mm.instance_count = Rules.RIVER_SLOTS * 2
		for q in range(mm.instance_count):
			mm.set_instance_transform(q, Transform3D(Basis(), centre))   # keeps the bounds on the platform
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		r["mm"][key] = mmi
	return r["mm"][key]


func _river_mesh(faction: String, seat: String, kind: String) -> Mesh:
	## A copy of the patch mesh with the seat's goo and creature materials on its surfaces (a MultiMesh
	## has no per-surface overrides) and the ring patch's RIVER_SHAPE baked in. A MultiMesh transforms
	## normals by the instance matrix itself, so a non-uniform instance scale would shift the goo
	## highlights and the creature rim; baked here with the inverse scale on the normals (what a
	## MeshInstance3D does), the instances only carry a uniform scale and light exactly as before.
	## The source mesh stays untouched: the horde lines and fx use it.
	var key := "%s|%s|%s" % [faction, seat, kind]
	if not _river_meshes.has(key):
		var src: Mesh = meshes[faction][kind]
		var inv := Vector3.ONE / RIVER_SHAPE
		var m := ArrayMesh.new()
		for sidx in range(src.get_surface_count()):
			var arrays := src.surface_get_arrays(sidx)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for q in range(v.size()):
				v[q] = v[q] * RIVER_SHAPE
			arrays[Mesh.ARRAY_VERTEX] = v
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for q in range(nr.size()):
					nr[q] = (nr[q] * inv).normalized()
				arrays[Mesh.ARRAY_NORMAL] = nr
			if arrays[Mesh.ARRAY_TANGENT] != null:          # Godot moves tangents with the normal matrix too
				var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				for q in range(0, tg.size(), 4):
					var t := (Vector3(tg[q], tg[q + 1], tg[q + 2]) * inv).normalized()
					tg[q] = t.x
					tg[q + 1] = t.y
					tg[q + 2] = t.z
				arrays[Mesh.ARRAY_TANGENT] = tg
			var lods := {}                                  # keep the imported LODs
			var sd := RenderingServer.mesh_get_surface(src.get_rid(), sidx)
			var wide: bool = (sd["index_data"] as PackedByteArray).size() > int(sd["index_count"]) * 2   # 32-bit indices
			for l in sd.get("lods", []):
				var bytes: PackedByteArray = l["index_data"]
				var idx := PackedInt32Array()
				if wide:
					idx = bytes.to_int32_array()
				else:
					idx.resize(bytes.size() / 2)
					for q in range(idx.size()):
						idx[q] = bytes.decode_u16(q * 2)
				lods[l["edge_length"]] = idx
			# stored uncompressed: a MultiMesh shades the imported (compressed) creature surface
			# differently from a MeshInstance3D; uncompressed it matches the old patches exactly
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
			var sm := src.surface_get_material(sidx) as BaseMaterial3D
			var is_creature := sm != null and sm.albedo_texture != null
			m.surface_set_material(sidx, Mats.creature(faction, seat, textures[faction]) if is_creature else Mats.goo(seat))
		_river_meshes[key] = m
	return _river_meshes[key]


func _place_contact(key: String, pos: Vector3, fwd: Vector3, seats: Array, losses: Array, time: float) -> void:
	var fight: bool = seats[0] != seats[1]
	if contacts.has(key) and contacts[key]["seats"] != seats:
		var old_root := contacts[key]["root"] as Node3D
		old_root.visible = false                         # the sides changed: rebuild in the new colours
		old_root.queue_free()
		contacts.erase(key)
	if not contacts.has(key):
		var root := Node3D.new()
		add_child(root)
		var c := {"root": root, "lobes": [], "seam": null, "splash": [], "seats": seats}
		for k in range(2):                                # attacker's lobe behind the seam, the other's ahead
			var lobe := MeshInstance3D.new()
			lobe.mesh = _lobe_mesh
			lobe.material_override = Mats.goo(seats[k])
			lobe.position = Vector3((-1.0 if k == 0 else 1.0) * MENISCUS_OFFSET, 0.0, 0.0)
			root.add_child(lobe)
			c["lobes"].append(lobe)
		if fight:
			var seam := MeshInstance3D.new()
			seam.mesh = _lobe_mesh
			seam.material_override = Mats.seam()
			root.add_child(seam)
			c["seam"] = seam
			for k in range(2):
				var p := _splash(seats[k], -1.0 if k == 0 else 1.0)
				root.add_child(p)
				c["splash"].append(p)
		contacts[key] = c
	var c: Dictionary = contacts[key]
	var root: Node3D = c["root"]
	root.position = pos + Vector3(0.0, 0.1, 0.0)      # lobes sit on the deck, bulging above the goo film
	root.rotation = Vector3(0.0, Rules.heading(fwd), 0.0)
	var pulse := 1.0 + MENISCUS_PULSE * sin(TAU * SHOVE_HZ * time)
	var lobes: Array = c["lobes"]
	for lobe in lobes:
		(lobe as Node3D).visible = not classic
	if c["seam"]:
		(c["seam"] as Node3D).visible = not classic
	for k in range(2):
		var pk := 1.0 + MENISCUS_PULSE * sin(TAU * SHOVE_HZ * time + (0.0 if k == 0 else PI))
		(lobes[k] as MeshInstance3D).scale = MENISCUS * Vector3(pk, pk, 1.0) * (1.0 if fight else 0.8)
	if c["seam"]:
		(c["seam"] as MeshInstance3D).scale = Vector3(0.14, MENISCUS.y * 1.08 * pulse, MENISCUS.z * 1.05)
	var splash: Array = c["splash"]
	for k in range(splash.size()):
		var p := splash[k] as CPUParticles3D
		var rate: float = losses[k]
		var ratio := clampf(rate / SPLASH_FULL_RATE, 0.15, 1.0)   # heavier losses: bigger, livelier drops
		p.emitting = rate > 0.5
		p.speed_scale = 0.7 + 0.5 * ratio
		p.scale_amount_max = 0.7 + 0.9 * ratio


func _splash(seat: String, back: float) -> CPUParticles3D:
	## Goo droplets thrown off the seam back over the side that is losing them.
	var p := CPUParticles3D.new()
	if not _drop_meshes.has(seat):
		var m := SphereMesh.new()
		m.radius = 0.17
		m.height = 0.34
		m.radial_segments = 8
		m.rings = 4
		m.material = Mats.goo(seat)
		_drop_meshes[seat] = m
	p.mesh = _drop_meshes[seat]
	p.amount = SPLASH_AMOUNT
	p.lifetime = 0.9
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.position = Vector3(0.0, MENISCUS.y * 0.8, 0.0)
	p.direction = Vector3(back * 0.7, 1.0, 0.0)
	p.spread = 50.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.emitting = false
	return p
