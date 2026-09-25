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


func begin() -> void:
	for k in _xf:
		(_xf[k] as Array).clear()
	_discs.clear()
	_seen.clear()


func add_unit(faction: String, seat: String, pos: Vector3, heading: float, bob := 0.0, roll := 0.0, squeeze := 0.0, size := 1.0) -> void:
	if not _mesh.has(faction):
		return
	var key := "%s|%s" % [faction, seat]
	if not _mm.has(key):
		_instance(faction, seat)
	var s: float = _scale[faction] * size
	var basis := Basis(Vector3.UP, heading + MODEL_YAW) * Basis(Vector3(0, 0, 1), roll) \
			* Basis.from_scale(Vector3(1.0 + squeeze * 0.6, 1.0 - squeeze, 1.0 + squeeze * 0.45) * s)
	(_xf[key] as Array).append(Transform3D(basis, pos + Vector3(0, 0.08 + bob, 0)))
	_discs.append([Transform3D(Basis().scaled(Vector3.ONE * size), pos + Vector3(0, 0.05, 0)), Rules.seat_color(seat)])   # the disc goes in with its body


func add_horde(h: Dictionary, shown_units: float, time: float) -> void:
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
	var n := clampi(int(ceil(shown_units)), 1, MAX_PER_HORDE)
	var gap := Rules.BRAWL_SPACING
	var L: float = h["L"]
	var head: float = h["s"]
	var count := n                                 # bodies out of the door so far (the front ones may be in)
	var id: int = h["id"]
	_seen[id] = true
	if h["state"] == "absorb":                     # the front has reached the door: the column walks on in
		var w: Dictionary = _pour.get(id, {})
		if w.is_empty() or w["L"] != L or time < w["t"] - 1.0:
			w = {"L": L, "head": L, "t": time, "count": n}
			_pour[id] = w
		w["head"] += Rules.move_speed() * maxf(time - w["t"], 0.0)   # a guest's clock may step back to a snapshot:
		w["t"] = maxf(w["t"], time)                                   # hold still until it catches up
		head = w["head"]
		var inside := maxi(int(ceil((head - L) / gap)), 0)
		if h["streaming"]:                         # the door still emits: new bodies file out behind
			w["count"] = maxi(w["count"], mini(int(head / gap) + 1, inside + n))
		w["count"] = mini(w["count"], inside + n + 1)   # losses on the way in thin the tail, not the front
		count = w["count"]
	else:
		_pour.erase(id)
	var soft: float = SOFTNESS.get(h["faction"], 1.0)
	var to_cam := Rules.front_dir()
	var screen_right := Vector3(1, 0, 0).rotated(Vector3.UP, Rules.view_yaw)
	var first := clampi(int(ceil((head - L) / gap)), 0, count)   # the ones before it are through the door
	for j in range(first, mini(count, first + MAX_PER_HORDE)):
		var dist := head - j * gap
		if dist < 0.0:
			break
		var lanes := ACROSS
		var col := j % lanes
		var expansion := clampf(minf(dist, L - dist) / Rules.BRAWL_EXPAND, 0.0, 1.0)
		var travel := dist + col * gap * expansion
		if travel > L:
			continue                                  # through the door
		var door := smoothstep(0.0, 1.0, clampf(minf(travel, L - travel) / DOOR, 0.0, 1.0))
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


func flush() -> void:
	for id in _pour.keys():
		if not _seen.has(id):
			_pour.erase(id)
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
