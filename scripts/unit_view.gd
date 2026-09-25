class_name UnitView
extends Node3D
## CLASSIC MODE look (Daniele, Alpha 14: "for the non-bridge-fight mode remove the ooze goo and go
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
const ROW := 1.35                    # metres between rows
const LANE := 0.95                   # metres between the columns
const MAX_PER_HORDE := 60
const MODEL_YAW := PI / 2.0          # the models face +Z; the path heading is kit +X

var _mesh := {}                      # faction -> Mesh
var _tex := {}                       # faction -> albedo Texture2D
var _scale := {}                     # faction -> uniform scale to UNIT_SIZE
var _mm := {}                        # "faction|seat" -> MultiMeshInstance3D
var _xf := {}                        # "faction|seat" -> [Transform3D] this frame
var _disc: MultiMeshInstance3D
var _discs: Array = []               # [[Transform3D, Color]] this frame


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


func add_unit(faction: String, seat: String, pos: Vector3, heading: float, bob := 0.0) -> void:
	if not _mesh.has(faction):
		return
	_instance(faction, seat)
	var s: float = _scale[faction]
	var basis := Basis(Vector3.UP, heading + MODEL_YAW).scaled(Vector3.ONE * s)
	(_xf["%s|%s" % [faction, seat]] as Array).append(Transform3D(basis, pos + Vector3(0, 0.08 + bob, 0)))
	_discs.append([Transform3D(Basis(), pos + Vector3(0, 0.05, 0)), Rules.seat_color(seat)])


func add_horde(h: Dictionary, shown_units: float, time: float) -> void:
	## A column of models from the head back along the path, ACROSS abreast.
	var n := clampi(int(ceil(shown_units)), 1, MAX_PER_HORDE)
	var rows := int(ceil(float(n) / ACROSS))
	var fighting: bool = h["state"] == "fight"
	for r in range(rows):
		var s: float = h["s"] - r * ROW
		if s < 0.0:
			break
		var smp := Sim.sample(h, s)
		var fwd: Vector3 = smp[1]
		var side := fwd.cross(Vector3.UP).normalized()
		var in_row := mini(ACROSS, n - r * ACROSS)
		for c in range(in_row):
			var off := (c - (in_row - 1) / 2.0) * LANE
			var hop := absf(sin(time * 9.0 + r * 0.9 + c * 1.7)) * (0.18 if not fighting else 0.3)
			add_unit(h["faction"], h["owner"], (smp[0] as Vector3) + side * off, Rules.heading(fwd), hop)


func flush() -> void:
	for k in _mm:
		var arr: Array = _xf[k]
		var mm: MultiMesh = (_mm[k] as MultiMeshInstance3D).multimesh
		var count := mini(arr.size(), mm.instance_count)
		for i in range(count):
			mm.set_instance_transform(i, arr[i])
		mm.visible_instance_count = count
	var dm := _disc.multimesh
	var dc := mini(_discs.size(), dm.instance_count)
	for i in range(dc):
		dm.set_instance_transform(i, _discs[i][0])
		dm.set_instance_color(i, _discs[i][1])
	dm.visible_instance_count = dc
