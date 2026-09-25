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

var meshes := {}      # faction -> kind -> Mesh
var textures := {}    # faction -> creature Texture2D
var pools := {}       # horde id -> {"patches": [MeshInstance3D], "label": Label3D, "vis": float, "phase": float}
var contacts := {}    # contact key -> {"root", "lobes", "seam", "splash", "seats"}
var rivers := {}      # node id -> {"patches": [MeshInstance3D], "vis": float}
var corridors := {}   # edge index -> MeshInstance3D: goo covering a deck between two owned nodes
var _corridor_mesh: BoxMesh
var _last_time := -1.0
var _lobe_mesh: SphereMesh
var _drop_meshes := {}   # seat -> SphereMesh with the seat's goo
var units: UnitView                  # classic mode (bridge combat OFF): Alpha 11 unit models
var classic := false                # true this frame when drawing the classic unit look


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
	units.begin()
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
		_draw(h, viewer, roles.get(h["id"], {}), sim.time, dt)
	for id in pools.keys():
		if not alive.has(id):
			for p in pools[id]["patches"]:
				p.queue_free()
			pools[id]["label"].queue_free()
			pools.erase(id)
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
func _draw(h: Dictionary, viewer: String, role: Dictionary, time: float, dt: float) -> void:
	var faction: String = h["faction"]
	load_faction(faction)
	if not pools.has(h["id"]):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.016
		label.font_size = 80
		label.outline_size = 20
		label.no_depth_test = true
		label.modulate = Rules.seat_color(h["owner"])
		add_child(label)
		pools[h["id"]] = {"patches": [], "label": label, "vis": float(h["units"]), "phase": fposmod(h["id"] * 0.37, 1.0)}
	var pool: Dictionary = pools[h["id"]]
	# the drawn count trails the real one a little, so losses read as the line receding, not popping
	var vis: float = pool["vis"]
	if h["units"] > vis:
		vis = h["units"]
	else:
		vis += (h["units"] - vis) * minf(1.0, EASE * dt)
	pool["vis"] = vis
	var full := Sim.full_length(vis)
	var length := minf(full, maxf(h["s"], 1.0))
	var n := clampi(int(length / Rules.PATCH_SPACING) + 1, 1, Rules.MAX_PATCHES)
	var rest := length - (n - 1) * Rules.PATCH_SPACING       # fraction of the last patch
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
	while arr.size() < n:
		var mi := MeshInstance3D.new()
		add_child(mi)
		arr.append(mi)
	if classic:
		units.add_horde(h, Rules.shown_f(vis), time)
	for i in range(arr.size()):
		var mi: MeshInstance3D = arr[i]
		var s: float = h["s"] - i * Rules.PATCH_SPACING
		if i >= n or s < 0.0 or classic:
			mi.visible = false
			continue
		var kind: String = "head" if i == 0 else ("tail" if i == n - 1 else KINDS[1 + (i % 3)])
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
			sc = [0.55, 0.75, 0.9][from_tail]
		if i == n - 1 and n > 1:
			sc *= clampf(0.3 + rest / Rules.PATCH_SPACING, 0.3, 1.0)   # grows/shrinks smoothly
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
	## the corridor DRAINS - the goo sinks and pulls back toward the end still held over ~1 s -
	## so breaking a link is a clear goal with a visible payoff. New corridors pour in the same way.
	var dt := get_process_delta_time()
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var a: Dictionary = sim.nodes[e["a"]]
		var b: Dictionary = sim.nodes[e["b"]]
		var held: bool = sim.bonded(i) and not classic
		if not corridors.has(i):
			if not held:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _corridor_mesh
			add_child(mi)
			corridors[i] = mi
			mi.set_meta("fill", 0.0)
			mi.set_meta("anchor", 0.5)
		var mi: MeshInstance3D = corridors[i]
		var fill: float = mi.get_meta("fill", 0.0)
		if held:
			mi.set_meta("owner", a["owner"])
			mi.set_meta("anchor", 0.5)
		elif fill > 0.0 and mi.get_meta("anchor", 0.5) == 0.5:
			# drain toward whichever end is still held by the corridor's owner (or the middle)
			var o: String = mi.get_meta("owner", "")
			mi.set_meta("anchor", 0.0 if a["owner"] == o else (1.0 if b["owner"] == o else 0.49))
		fill = move_toward(fill, 1.0 if held else 0.0, dt * (1.5 if held else 1.0))
		mi.set_meta("fill", fill)
		mi.visible = fill > 0.01
		if not mi.visible:
			continue
		mi.material_override = Mats.goo(mi.get_meta("owner", a["owner"]))
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		var dir := (pb - pa).normalized()
		var full_len: float = maxf(pa.distance_to(pb) - 2.0 * Rules.R, 1.0)   # rim to rim
		var anchor: float = mi.get_meta("anchor", 0.5)
		var len := full_len * fill
		var start := pa + dir * Rules.R
		var centre: Vector3 = start + dir * (anchor * full_len + (0.5 - anchor) * len)
		mi.position = centre + Vector3(0, 0.06 - 0.12 * (1.0 - fill) * (0.0 if held else 1.0), 0)
		mi.rotation = Vector3(0, Rules.heading(dir), 0)
		mi.scale = Vector3(len, 1.0, Rules.W * 0.92 * lerpf(0.6, 1.0, fill))


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
	for n in sim.nodes:
		var id: int = n["id"]
		if not rivers.has(id):
			var arr := []
			for i in range(Rules.RIVER_SLOTS):
				var mi := MeshInstance3D.new()
				add_child(mi)
				arr.append(mi)
			rivers[id] = {"patches": arr, "seat": [], "vis": 0.0}
		var r: Dictionary = rivers[id]
		if sim.collapsed.get(id, false):                 # a fallen platform takes its river with it
			for mi in r["patches"]:
				mi.visible = false
			continue
		var total: float = n["units"]
		for k in n["siege"]:
			total += n["siege"][k]
		var vis: float = r["vis"]
		vis += (total - vis) * minf(1.0, EASE * 0.6 * dt)
		r["vis"] = vis
		var arr: Array = r["patches"]
		if vis < 1.0:
			for mi in arr:
				mi.visible = false
			continue
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
		var fill := clampf(total / float(Rules.CAPS[n["tier"]]), 0.0, 1.0)
		var sc := lerpf(0.4, 1.0, sqrt(fill))
		var contested: bool = not n["siege"].is_empty()
		for i in range(Rules.RIVER_SLOTS):
			var mi: MeshInstance3D = arr[i]
			if Rules.low_detail and i % 2 == 1:
				mi.visible = false
				continue
			var seat: String = slots[i]
			var faction: String = sim.factions.get(seat, "null")
			if classic:                                # a ring of creatures, no goo
				mi.visible = false
				if seat == "" or float(i) / Rules.RIVER_SLOTS > fill + 0.08:
					continue
				var ua := TAU * i / Rules.RIVER_SLOTS
				var ur := Vector3(cos(ua), 0.0, sin(ua))
				var bob := absf(sin(sim.time * (8.0 if contested else 2.0) + i)) * (0.25 if contested else 0.05)
				units.add_unit(faction, seat, n["pos"] + ur * Rules.RIVER_R, Rules.heading(-ur if faces_in[i] else ur), bob)
				continue
			load_faction(faction)
			var kind: String = ["body_a_lod1", "body_b_lod1", "body_c_lod1"][i % 3]
			var mesh: Mesh = meshes[faction][kind]
			if mi.mesh != mesh or mi.get_meta("seat", "?") != seat:
				mi.mesh = mesh
				mi.set_meta("seat", seat)
				for sidx in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(sidx) as BaseMaterial3D
					var is_creature := m != null and m.albedo_texture != null
					mi.set_surface_override_material(sidx, Mats.creature(faction, seat, textures[faction])
							if is_creature else Mats.goo(seat))
			mi.visible = true
			var a := TAU * i / Rules.RIVER_SLOTS
			var radial := Vector3(cos(a), 0.0, sin(a))
			var pos: Vector3 = n["pos"] + radial * Rules.RIVER_R
			var fwd := -radial if faces_in[i] else Vector3(-sin(a), 0.0, cos(a))
			var s := sc
			if contested:                              # the whole platform seethes
				pos += radial * 0.18 * sin(sim.time * 6.0 + i * 1.3)
				s *= 1.0 + 0.08 * sin(sim.time * 7.0 + i * 2.1)
			mi.position = pos
			mi.rotation = Vector3(0.0, Rules.heading(fwd), 0.0)
			mi.scale = Vector3(s * 0.85, s * 0.9, s)
			# seam with the next slot: meniscus + splash between the two owners
			var nxt: String = slots[(i + 1) % Rules.RIVER_SLOTS]
			if nxt != seat:
				var key := "n%d_%d" % [id, i]
				var a2 := TAU * (i + 0.5) / Rules.RIVER_SLOTS
				var spos: Vector3 = n["pos"] + Vector3(cos(a2), 0.0, sin(a2)) * Rules.RIVER_R
				var sfwd := Vector3(-sin(a2), 0.0, cos(a2))
				_place_contact(key, spos, sfwd, [seat, nxt],
						[n["node_loss"].get(seat, 0.0), n["node_loss"].get(nxt, 0.0)], sim.time)
				(contacts[key]["root"] as Node3D).scale = Vector3.ONE * (0.6 + 0.4 * sc)
				seen[key] = true


func _place_contact(key: String, pos: Vector3, fwd: Vector3, seats: Array, losses: Array, time: float) -> void:
	var fight: bool = seats[0] != seats[1]
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
