class_name UnitView
extends Node3D
## BRAWL mode look (Daniele, Alpha 14: "for the non-bridge-fight mode remove the ooze goo and go
## back to actually sending models of units like we did in Alpha 11 - two distinct modes that look
## and feel different"). Every send is a column of the approved faction creature models
## (assets/units/<faction>.glb, Alpha 11's own meshes, unmodified), three across like Alpha 11's
## default formation, one model per unit as the player counts them (Rules.shown). The model's body
## takes its OWNER's colour (the creature shader's hue shift, as the goo hordes do) so three players
## on the same faction never look alike (Alpha 14 playtest), and stands on a disc in that colour.
## Garrisons don't loiter round the vat: the platform neon shows the owner. Drawn with one
## MultiMesh per faction x seat plus one for the discs, rebuilt every frame.

const UNIT_SIZE := 1.3               # metres across a creature (readable at full-map zoom)
const ACROSS := 3                    # Alpha 11's default formation
const LANE := 0.95                   # metres between the columns
const MAX_PER_HORDE := 200           # Alpha 11 drew every body
const MODEL_YAW := PI / 2.0          # the models face +Z; the path heading is kit +X
# ALPHA 11'S TROOP ANIMATION (game.gd draw loop + unit.gdshader, Daniele Alpha 16: "animations matching
# Alpha 11"): every body hops on an 8 rad/s wave with its own phase (j * 0.618 + order * 0.137), only
# upward, rolls +-0.07 rad on the same wave, squashes and stretches 11 % (40 % of that for Ember and
# Solar), and faces the camera three-quarters (0.65 rad) toward the side it is travelling - it never
# turns its back along the path.
const WAVE := 8.0
const HOP := 0.087 * UNIT_SIZE       # Alpha 11: 0.052 on a 0.6-unit body
const ROLL := 0.07
const SQUASH := 0.11
const TURN := 0.65
const SOFTNESS := {"ember": 0.4, "solar": 0.4}
# Through the door (Daniele, Alpha 17: "units entering the building just clip"): over the last DOOR m
# of the route a body shrinks and dips into the doorway, and a body leaving grows out of it the same
# way, so a column pours in and out instead of popping.
const DOOR := 1.6
const BEND := 1.0                    # metres either side a body reads its heading over (corners)

var _mesh := {}                      # faction -> Mesh
var _tex := {}                       # faction -> albedo Texture2D
var _scale := {}                     # faction -> uniform scale to UNIT_SIZE
var _mm := {}                        # "faction|seat" -> MultiMeshInstance3D
var _xf := {}                        # "faction|seat" -> [Transform3D] this frame
var _disc: MultiMeshInstance3D
var _discs: Array = []               # [[Transform3D, Color]] this frame
var _pour := {}                      # horde id -> {"L", "head", "t", "count"} while its column walks in
var _seen := {}                      # horde ids drawn this frame (the rest are dropped from _pour)


func _ready() -> void:
	for f in Rules.FACTIONS.keys():
		var root: Node = load("res://assets/units/%s.glb" % f).instantiate()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			_mesh[f] = (mi as MeshInstance3D).mesh
			break
		root.free()
		if not _mesh.has(f):
			continue
		var aabb: AABB = (_mesh[f] as Mesh).get_aabb()
		_scale[f] = UNIT_SIZE / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
		var src := (_mesh[f] as Mesh).surface_get_material(0) as BaseMaterial3D
		_tex[f] = src.albedo_texture if src else null
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.5
	disc_mesh.bottom_radius = 0.5
	disc_mesh.height = 0.05
	disc_mesh.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	disc_mesh.material = mat
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.use_colors = true
	dm.mesh = disc_mesh
	dm.instance_count = 4096
	dm.visible_instance_count = 0
	_disc = MultiMeshInstance3D.new()
	_disc.multimesh = dm
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _instance(faction: String, seat: String) -> MultiMeshInstance3D:
	var key := "%s|%s" % [faction, seat]
	if not _mm.has(key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh[faction]
		mm.instance_count = 1024
		mm.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _tex[faction]:
			var m: ShaderMaterial = (Mats.creature(faction, seat, _tex[faction]) as ShaderMaterial).duplicate()
			m.set_shader_parameter("self_glow", 0.45)
			inst.material_override = m
		add_child(inst)
		_mm[key] = inst
		_xf[key] = []
	return _mm[key]


func begin(now := -1.0) -> void:
	for k in _xf:
		(_xf[k] as Array).clear()
	for k in _blob_xf:
		(_blob_xf[k] as Array).clear()
	_discs.clear()
	_seen.clear()
	if now >= 0.0:
		_now = now


func add_unit(faction: String, seat: String, pos: Vector3, heading: float, bob := 0.0, roll := 0.0, squeeze := 0.0, size := 1.0) -> void:
	if not _mesh.has(faction):
		return
	if ForgePulse.live:                              # a forge coming online: the body glows, hops and swells in its wave
		var b := ForgePulse.boost(seat, pos)
		bob += ForgePulse.HOP * b
		size *= 1.0 + ForgePulse.SWELL * b
	var key := "%s|%s" % [faction, seat]
	if not _mm.has(key):
		_instance(faction, seat)
	var s: float = _scale[faction] * size
	var basis := Basis(Vector3.UP, heading + MODEL_YAW) * Basis(Vector3(0, 0, 1), roll) \
			* Basis.from_scale(Vector3(1.0 + squeeze * 0.6, 1.0 - squeeze, 1.0 + squeeze * 0.45) * s)
	(_xf[key] as Array).append(Transform3D(basis, pos + Vector3(0, 0.08 + bob, 0)))
	_discs.append([Transform3D(Basis().scaled(Vector3.ONE * size), pos + Vector3(0, 0.05, 0)), Rules.seat_color(seat)])   # the disc goes in with its body


func add_horde(h: Dictionary, shown_units: float, time: float, drop := {}) -> void:
	## Alpha 11's column (simulation.gd formation_sample): one body every 12 px (0.93 m); body j's lane is
	## j % 3; lanes open from single file over the first and last 85 px (6.6 m) of the route, so a
	## send files out of the door, spreads three across on the bridge and files back in at the target;
	## each body faces its own way along the route. Arriving bodies keep walking in at their spacing.
	## Every body keeps ONE identity for the whole trip (Daniele, Alpha 18: "on brawl units entering
	## the building still feels a bit strange as if the units were violently shaking toward the door
	## instead of orderly entering"): body i is the i-th out of the door and walks at head - i * gap
	## with its own lane and hop phase from start to finish. While the column pours in, the head walks
	## on past the door at the marching pace instead of being recounted from the units left - that
	## recount re-numbered every body each time one went in, so the whole column swapped lanes and hop
	## phase and lurched a gap forward about ten times a second.
	## 0.18.7: the column is anchored where its head would be without what was cut off its front
	## (h["fcut"]: cannon hits at the head, the line walking off a lip), so the bodies that go are the
	## front ones and nobody else moves: a cannon's kills pop under the beam, a line walking off a
	## missing deck keeps marching and each body tumbles off the lip in turn (_spawn). `drop` (HordeView,
	## a line leaving a vat): its next bodies are dropped out of the vat's tanks and run to the door.
	var n := clampi(int(ceil(shown_units)), 1, MAX_PER_HORDE)
	var gap := Rules.BRAWL_SPACING
	var L: float = h["L"]
	var id: int = h["id"]
	var fcut: float = h.get("fcut", 0.0)
	_seen[id] = true
	_now = time
	var tr: Dictionary = _front.get(id, {})
	if tr.is_empty() or tr["L"] != L or fcut < float(tr["fc"]) - 1.0:   # a new path (re-route, recall)
		tr = {"P": 0, "mask": 0, "L": L, "fc": fcut}
		_front[id] = tr
	tr["fc"] = fcut
	var absorb: bool = h["state"] == "absorb"
	var head: float = h["s"] + fcut
	var front := int(fcut / gap + 0.5)            # bodies cut off the front
	var count := front + n                         # bodies out of the door so far (the front ones may be gone)
	if absorb:                                     # the front has reached the door: the column walks on in
		var w: Dictionary = _pour.get(id, {})
		if w.is_empty() or w["L"] != L or time < w["t"] - 1.0:
			w = {"L": L, "head": L + fcut, "t": time, "count": count, "fc": fcut, "fd": fcut / gap}
			_pour[id] = w
		w["head"] += Rules.move_speed() * maxf(time - w["t"], 0.0)   # a guest's clock may step back to a snapshot:
		w["t"] = maxf(w["t"], time)                                   # hold still until it catches up
		head = w["head"]
		var inside := maxi(int(ceil((head - L) / gap)), 0)
		w["fd"] = maxf(w["fd"], float(inside)) + maxf(fcut - w["fc"], 0.0) / gap   # the door's cannon kills
		w["fc"] = fcut
		front = maxi(inside, int(w["fd"] + 0.5))
		if h["streaming"]:                         # the door still emits: new bodies file out behind
			w["count"] = maxi(w["count"], mini(int(head / gap) + 1, front + n))
		w["count"] = mini(w["count"], front + n + 1)   # losses on the way in thin the tail, not the front
		count = w["count"]
	else:
		_pour.erase(id)
	var pour: bool = h.get("pour", false) and not absorb
	var lip: float = h.get("pour_lip", -1.0)
	var fall_from: float = float(h.get("pour_k", 0.0)) - 0.5 * gap
	var lost := int(fcut / gap + 0.001)            # whole bodies the sim has taken off the front (never ahead of it)
	var soft: float = SOFTNESS.get(h["faction"], 1.0)
	var to_cam := Rules.front_dir()
	var screen_right := Vector3(1, 0, 0).rotated(Vector3.UP, Rules.view_yaw)
	var dropping := not drop.is_empty()
	if dropping:
		tr["dropped"] = true                       # its bodies came out of the tanks: none shrinks into the door
	var from_tanks: bool = tr.get("dropped", false)
	var P: int = tr["P"]
	var mask: int = tr["mask"]
	var drawn := 0
	for j in range(P, count):
		var k := j - P
		if k < 31 and (mask >> k) & 1:
			continue                                  # already gone
		var dist := head - j * gap
		if dist < 0.0:
			break                                     # still in the vat
		var lanes := ACROSS
		var col := j % lanes
		var expansion := clampf(minf(dist, L - dist) / Rules.BRAWL_EXPAND, 0.0, 1.0)
		var travel := dist + col * gap * expansion
		# gone at the front? 0 = quietly (through the door, or fell with its deck - Fx drew it), 1 = a
		# cannon kill (pop), 2 = walked off the lip (it falls)
		var gone := -1
		if absorb:
			gone = 0 if travel > L else (1 if j < front else -1)
		elif pour and j < lost:                    # the sim has lost it off the lip: it goes over
			gone = 2 if j * gap >= fall_from and travel > lip else 0
		elif j < front and not pour:
			gone = 1
		if gone >= 0:
			if k < 31:
				mask |= 1 << k
				if gone > 0:
					_spawn(h, gone, j, travel if gone == 1 else lip, dist - lip, time, tr)
			continue
		if pour and travel > lip:
			travel = lip                              # a side lane a stride ahead of its row waits its turn at the edge
		if travel > L or drawn >= MAX_PER_HORDE:
			continue
		drawn += 1
		var door_d := (L - travel) if from_tanks else minf(travel, L - travel)   # dropped bodies are already out
		var door := smoothstep(0.0, 1.0, clampf(door_d / DOOR, 0.0, 1.0))
		var smp := Sim.sample(h, travel)
		# the heading over the metre either side, not the polyline segment's: where the bridge meets the
		# platform ring (and round the ring's segments) the side lanes swing round the corner instead of
		# stepping sideways, and a body turns from one three-quarter view to the other over a stride
		var fwd: Vector3 = (Sim.sample(h, travel + BEND)[0] as Vector3) - (Sim.sample(h, travel - BEND)[0] as Vector3)
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.001 else (smp[1] as Vector3)
		var side := fwd.cross(Vector3.UP).normalized()
		var row_size := mini(lanes, count - int(j / lanes) * lanes)
		var lateral := (col - (row_size - 1) * 0.5) * LANE * expansion
		var facing := clampf(fwd.dot(screen_right) * 2.0, -1.0, 1.0)
		var yaw := Rules.heading(to_cam.rotated(Vector3.UP, TURN * facing))
		var phase := fmod(j * 0.618 + float(id) * 0.137, 1.0)
		var wave := sin(time * WAVE + phase * TAU)
		add_unit(h["faction"], h["owner"], (smp[0] as Vector3) + side * lateral * door + Vector3.DOWN * 0.35 * (1.0 - door), yaw,
				maxf(0.0, wave) * HOP * door, wave * ROLL, wave * SQUASH * soft, lerpf(0.12, 1.0, door))
	while mask & 1:                                # the gone prefix is done with
		mask >>= 1
		P += 1
	tr["P"] = P
	tr["mask"] = mask
	if dropping and h["streaming"]:
		_drop_bodies(h, drop, head, count, time)


# ------------------------------------------------------------------ out of the vat's tanks
# Daniele, 0.18.7: "while is fine for armies to start at the door, i want the animation to make it look
# like they drop down from the vats and then join the horde... you know like goo monsters being dropped
# from the vats". The sim is unchanged (a line starts at the door); only the view: each body still to
# come out of the door is shown DROP_T s ahead - a goo blob squeezes out of one of the vat's tanks (the
# tanks take turns), falls with a stretch, splats on the platform, forms into the creature and runs to
# the door, reaching it exactly when the line's own stream puts it there. Stateless: a body's phase is
# how far it still is from the door (BRAWL) or how many units are still to be emitted before it (SIEGE).
const DROP_T := 1.0                  # seconds from the tank to the door
const BLOB_R := 0.46                 # a dropped blob's radius (m)
const DROP_UP := 1.4                 # m/s up as it squeezes out over the tank's rim
const DROP_OUT := 0.6                # m further out than the rim it fell off (HordeView.vat_drop)


static func drop_phase(u: float, spout: Vector3, rim: Vector3, land: Vector3, door_pt: Vector3) -> Array:
	## [position, blob scale (Vector3, zero = none), body size (0..1, 0 = none), heading dir] of a dropped
	## unit at phase u (0 at the tank, 1 at the door): out of the spout (over the rim of a tank's cap
	## when the spout is its top), down in an arc, a splat, and the run to the door.
	if u < 0.16:                                   # squeezes out of the tank, swelling and stretching
		var a := u / 0.16
		var p0 := spout.lerp(rim, smoothstep(0.0, 1.0, a)) + Vector3.UP * 0.18 * sin(a * PI)
		return [p0, Vector3(0.4 + 0.35 * a, 0.55 + 0.7 * a, 0.4 + 0.35 * a), 0.0, land - spout]
	if u < 0.5:                                    # falls in an arc, stretched along the drop
		var b := (u - 0.16) / 0.34
		var tf := 0.34 * DROP_T
		var t := tf * b
		var g := 2.0 * (rim.y - land.y + DROP_UP * tf) / (tf * tf)
		var p := rim.lerp(land, b)
		p.y = rim.y + DROP_UP * t - 0.5 * g * t * t
		var st := 1.0 + 0.45 * b
		return [p, Vector3(0.78, st, 0.78), 0.0, land - spout]
	if u < 0.64:                                   # splat, then it forms into the creature
		var c := (u - 0.5) / 0.14
		var blob := 1.0 - smoothstep(0.35, 1.0, c)
		return [land, Vector3(lerpf(1.75, 1.0, c), lerpf(0.3, 0.8, c), lerpf(1.75, 1.0, c)) * blob,
				smoothstep(0.25, 1.0, c), door_pt - land]
	var d := (u - 0.64) / 0.36                     # runs to its place in the line at the door
	return [land.lerp(door_pt, d), Vector3.ZERO, 1.0, door_pt - land]


func _drop_bodies(h: Dictionary, drop: Dictionary, head: float, count: int, time: float) -> void:
	## BRAWL: bodies count.. (not out yet) whose turn at the door comes within DROP_T s.
	var spouts: PackedVector3Array = drop["spouts"]
	if spouts.is_empty():
		return
	var gap := Rules.BRAWL_SPACING
	var reach: float = Rules.move_speed() * DROP_T
	var door_pt: Vector3 = Sim.sample(h, 0.0)[0]
	var to_cam := Rules.front_dir()
	var screen_right := Vector3(1, 0, 0).rotated(Vector3.UP, Rules.view_yaw)
	var soft: float = SOFTNESS.get(h["faction"], 1.0)
	var last := count + int(drop.get("pending", 0))
	for j in range(count, mini(last, count + 40)):
		var dist := head - j * gap
		if dist < -reach:
			break
		var u := clampf(1.0 + dist / reach, 0.0, 1.0)
		var spout: Vector3 = spouts[j % spouts.size()]
		var rim: Vector3 = (drop["rims"] as PackedVector3Array)[j % spouts.size()]
		var ph := drop_phase(u, spout, rim, (drop["lands"] as PackedVector3Array)[j % spouts.size()], door_pt)
		var blob: Vector3 = ph[1]
		if blob.x > 0.01:
			add_blob(h["owner"], ph[0], blob * BLOB_R)
		var size: float = ph[2]
		if size > 0.01:
			var dir: Vector3 = ph[3]
			dir.y = 0.0
			var facing := clampf(dir.normalized().dot(screen_right) * 2.0, -1.0, 1.0) if dir.length() > 0.01 else 0.0
			var wave := sin(time * WAVE + fmod(j * 0.618 + float(h["id"]) * 0.137, 1.0) * TAU)
			add_unit(h["faction"], h["owner"], ph[0], Rules.heading(to_cam.rotated(Vector3.UP, TURN * facing)),
					maxf(0.0, wave) * HOP * size, wave * ROLL, wave * SQUASH * soft + (1.0 - size) * 0.3, lerpf(0.25, 1.0, size))


func add_goo_drops(seat: String, drop: Dictionary, door_pt: Vector3, emitted: float, total: float) -> void:
	## SIEGE: one goo blob per shown unit still to leave the door within DROP_T s (never fewer - the
	## phone profile keeps them all): it drops out of a tank, splats and slides into the line's stream
	## at the door. `emitted` / `total`: shown units of the order out / ordered.
	var spouts: PackedVector3Array = drop["spouts"]
	if spouts.is_empty():
		return
	var rate: float = Rules.shown_f(Rules.exit_rate())
	var i := int(floor(emitted)) + 1
	var top := int(ceil(total))
	var k := 0
	while i <= top and k < 40:
		var lead := (float(i) - emitted) / maxf(rate, 0.01)   # seconds until it reaches the door
		if lead > DROP_T:
			break
		var u := clampf(1.0 - lead / DROP_T, 0.0, 1.0)
		var spout: Vector3 = spouts[i % spouts.size()]
		var rim: Vector3 = (drop["rims"] as PackedVector3Array)[i % spouts.size()]
		var ph := drop_phase(u, spout, rim, (drop["lands"] as PackedVector3Array)[i % spouts.size()], door_pt)
		var blob: Vector3 = ph[1]
		if blob.x <= 0.01 or u >= 0.64:              # no creature in SIEGE: the blob itself slides in
			var d := clampf((u - 0.64) / 0.36, 0.0, 1.0)
			blob = Vector3(1.15, 0.62, 1.15) * lerpf(1.0, 0.55, d * d) if u >= 0.64 else Vector3(1.0, 0.8, 1.0)
		add_blob(seat, ph[0], blob * BLOB_R * 1.25)
		i += 1
		k += 1


# ------------------------------------------------------------------ falls and pops (pooled)
# THE WATERFALL IS ONE MOTION (Daniele, 0.18.7: "when units reach a collapsing bridge now they stop near
# it before jumping in the void while the animation should be seamless and exaggerates so it looks cooler
# (exaggeration still should be kept in the ratio of the actual units lets say a +20%)"): a body walks off
# the lip at marching pace and keeps its momentum - a little leap, gravity, a tumble, a spread - from
# the very frame it passes the lip; POUR_EXTRA of a spray body per real one, never more than +20 %.
# A cannon kill at the head pops its body under the beam.
const FALL_MAX := 512                # pooled falling / popping bodies (ring buffer)
const FALL_T := 1.7                  # seconds a falling body is drawn (it is ~25 m down by then)
const POUR_G := 19.0                 # m/s2: a heavier, snappier fall than real gravity
const POUR_HOP := 2.4                # m/s up as it leaps off the lip
const POUR_SPREAD := 1.3             # m/s sideways scatter
const POUR_TUMBLE := 6.5             # rad/s at most
const POUR_EXTRA := 0.2              # extra spray bodies per real one (Daniele's +20 % cap)
const POP_T := 0.24                  # a popped body: swells, then is gone
const POP_DROPS := 5                 # goo droplets a popped body bursts into

var _now := 0.0
var _front := {}                     # horde id -> {"P", "mask", "L", "fc"}: which front bodies are gone
var _fl_key := PackedStringArray()   # "faction|seat" per slot
var _fl_p := PackedVector3Array()    # start position
var _fl_v := PackedVector3Array()    # start velocity
var _fl_spin := PackedVector3Array() # tumble rates (x pitch, y yaw, z roll)
var _fl_t := PackedFloat32Array()    # start time
var _fl_yaw := PackedFloat32Array()
var _fl_mode := PackedByteArray()    # 0 free, 1 pop, 2 fall
var _fl_scale := PackedFloat32Array() # the body's model scale
var _fl_seat := PackedStringArray()   # its owner (a pop's goo splash)
var _fl_next := 0
var falls_drawn := 0                 # bodies sent off a lip so far, spray included (probes read these)
var falls_real := 0
var pops := 0


func _spawn(h: Dictionary, mode: int, j: int, at: float, over: float, time: float, tr: Dictionary) -> void:
	## Body j of this line is gone: mode 1 pops where it stands (at = its travel), mode 2 walks off the lip
	## (at = the lip; `over` = how far past it the column already is).
	var faction: String = h["faction"]
	if not _mesh.has(faction):
		return
	var key := "%s|%s" % [faction, h["owner"]]
	if not _mm.has(key):
		_instance(faction, h["owner"])
	var smp := Sim.sample(h, at)
	var fwd: Vector3 = smp[1]
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(1, 0, 0)
	var side := fwd.cross(Vector3.UP)
	var col := j % ACROSS
	var p: Vector3 = (smp[0] as Vector3) + side * (col - 1) * LANE + Vector3(0, 0.08, 0)
	var screen_right := Vector3(1, 0, 0).rotated(Vector3.UP, Rules.view_yaw)
	var yaw := Rules.heading(Rules.front_dir().rotated(Vector3.UP, TURN * clampf(fwd.dot(screen_right) * 2.0, -1.0, 1.0)))
	if mode == 1:
		pops += 1
		_put_faller(key, p, Vector3.ZERO, Vector3.ZERO, time, yaw, 1)
		return
	var v := Rules.move_speed()
	var r1 := _rnd(h["id"], j)
	var r2 := _rnd(j, h["id"] + 7)
	var vel := fwd * v * lerpf(0.95, 1.2, r1) + side * POUR_SPREAD * (r2 - 0.5) * 2.0
	var spin := Vector3((r1 - 0.3) * POUR_TUMBLE, (r2 - 0.5) * POUR_TUMBLE * 0.5, (r2 - 0.5) * POUR_TUMBLE)
	var t0 := time - clampf(over, 0.0, 2.0) / v      # it passed the lip this long ago
	_put_faller(key, p, vel + Vector3.UP * POUR_HOP, spin, t0, yaw, 2)
	falls_real += 1
	falls_drawn += 1
	tr["fr"] = int(tr.get("fr", 0)) + 1
	if float(tr.get("fs", 0) + 1) <= POUR_EXTRA * float(tr["fr"]) + 0.0001:   # the +20 % spray: one per five real
		tr["fs"] = int(tr.get("fs", 0)) + 1                                    # bodies of this line, never more
		falls_drawn += 1
		var r3 := _rnd(h["id"] + 3, j + 11)
		_put_faller(key, p + side * (r3 - 0.5) * LANE * 2.0, vel * 0.85 + side * POUR_SPREAD * (r3 - 0.5) * 3.0 + Vector3.UP * POUR_HOP * 1.3,
				-spin * 1.2, t0 - 0.06, yaw + PI * r3, 2)


func _put_faller(key: String, p: Vector3, v: Vector3, spin: Vector3, t0: float, yaw: float, mode: int) -> void:
	if _fl_key.is_empty():                            # the pool, made once
		_fl_key.resize(FALL_MAX)
		_fl_p.resize(FALL_MAX)
		_fl_v.resize(FALL_MAX)
		_fl_spin.resize(FALL_MAX)
		_fl_t.resize(FALL_MAX)
		_fl_yaw.resize(FALL_MAX)
		_fl_mode.resize(FALL_MAX)
		_fl_scale.resize(FALL_MAX)
		_fl_seat.resize(FALL_MAX)
	var i := _fl_next
	_fl_next = (_fl_next + 1) % FALL_MAX
	_fl_key[i] = key
	_fl_p[i] = p
	_fl_v[i] = v
	_fl_spin[i] = spin
	_fl_t[i] = t0
	_fl_yaw[i] = yaw
	_fl_mode[i] = mode
	_fl_scale[i] = _scale[key.get_slice("|", 0)]
	_fl_seat[i] = key.get_slice("|", 1)


func _draw_fallers() -> void:
	for i in range(_fl_mode.size()):
		var mode := _fl_mode[i]
		if mode == 0:
			continue
		var age := _now - _fl_t[i]
		var key: String = _fl_key[i]
		if age > (POP_T if mode == 1 else FALL_T) or not _xf.has(key):
			_fl_mode[i] = 0
			continue
		if age < 0.0:
			continue
		var s: float = _fl_scale[i]
		var basis: Basis
		var pos: Vector3
		if mode == 1:                                 # pop: swells and squashes, then shrinks to nothing
			var k := age / POP_T
			var sw := (1.0 + 0.55 * sin(minf(k * 2.2, 1.0) * PI * 0.5)) * (1.0 - smoothstep(0.45, 1.0, k))
			basis = Basis(Vector3.UP, _fl_yaw[i] + MODEL_YAW) * Basis.from_scale(Vector3(1.2, 0.75, 1.2) * s * maxf(sw, 0.01))
			pos = _fl_p[i] + Vector3.UP * 0.35 * k
			for d in range(POP_DROPS):                # and it bursts: goo droplets fly off it
				var a := _fl_yaw[i] + TAU * d / POP_DROPS
				var t := age * 1.6
				var dp: Vector3 = _fl_p[i] + Vector3(cos(a) * 3.2 * t, 0.5 + 3.0 * t - 7.0 * t * t, sin(a) * 3.2 * t)
				add_blob(_fl_seat[i], dp, Vector3.ONE * 0.16 * (1.0 - 0.6 * k))
		else:
			var sp: Vector3 = _fl_spin[i]
			var v: Vector3 = _fl_v[i]
			var shrink := 1.0 - 0.35 * smoothstep(FALL_T * 0.6, FALL_T, age)
			var stretch := 1.0 + 0.18 * clampf(age / 0.5, 0.0, 1.0)            # stretched by the fall
			var sq := 1.0 / sqrt(stretch)
			basis = Basis(Vector3.UP, _fl_yaw[i] + MODEL_YAW + sp.y * age) * Basis(Vector3(1, 0, 0), sp.x * age) \
					* Basis(Vector3(0, 0, 1), sp.z * age) * Basis.from_scale(Vector3(sq, stretch, sq) * s * shrink)
			pos = _fl_p[i] + Vector3(v.x, 0.0, v.z) * age + Vector3.UP * (v.y * age - 0.5 * POUR_G * age * age)
		(_xf[key] as Array).append(Transform3D(basis, pos))


static func _rnd(a: int, b: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453, 1.0)


# ------------------------------------------------------------------ goo blobs (vat drops)
var _blob := {}                      # seat -> MultiMeshInstance3D of goo spheres
var _blob_xf := {}                   # seat -> [Transform3D] this frame
var _blob_mesh: SphereMesh


func add_blob(seat: String, pos: Vector3, scale3: Vector3) -> void:
	if not _blob.has(seat):
		if _blob_mesh == null:
			_blob_mesh = SphereMesh.new()
			_blob_mesh.radius = 1.0
			_blob_mesh.height = 2.0
			_blob_mesh.radial_segments = 12
			_blob_mesh.rings = 6
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _blob_mesh
		mm.instance_count = 64
		mm.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.material_override = Mats.goo(seat)
		add_child(inst)
		_blob[seat] = inst
		_blob_xf[seat] = []
	(_blob_xf[seat] as Array).append(Transform3D(Basis.from_scale(scale3), pos))


func flush() -> void:
	for id in _pour.keys():
		if not _seen.has(id):
			_pour.erase(id)
	for id in _front.keys():
		if not _seen.has(id):
			_front.erase(id)
	_draw_fallers()
	for seat in _blob:
		var arr: Array = _blob_xf[seat]
		var bm: MultiMesh = (_blob[seat] as MultiMeshInstance3D).multimesh
		if arr.size() > bm.instance_count:
			bm.instance_count = nearest_po2(arr.size())
		for i in range(arr.size()):
			bm.set_instance_transform(i, arr[i])
		bm.visible_instance_count = arr.size()
	for k in _mm:
		var arr: Array = _xf[k]
		var mm: MultiMesh = (_mm[k] as MultiMeshInstance3D).multimesh
		if arr.size() > mm.instance_count:            # grow rather than drop bodies (every transform is rewritten below)
			mm.instance_count = nearest_po2(arr.size())
		var count := mini(arr.size(), mm.instance_count)
		for i in range(count):
			mm.set_instance_transform(i, arr[i])
		mm.visible_instance_count = count
	var dm := _disc.multimesh
	if _discs.size() > dm.instance_count:
		dm.instance_count = nearest_po2(_discs.size())
	var dc := mini(_discs.size(), dm.instance_count)
	for i in range(dc):
		dm.set_instance_transform(i, _discs[i][0])
		dm.set_instance_color(i, _discs[i][1])
	dm.visible_instance_count = dc
