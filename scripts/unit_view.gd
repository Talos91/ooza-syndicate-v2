class_name UnitView
extends Node3D
## CLASSIC MODE look (Daniele, Alpha 14: "for the non-bridge-fight mode remove the ooze goo and go
## back to actually sending models of units like we did in Alpha 11 - two distinct modes that look
## and feel different"). Every send is a column of the approved faction creature models
## (assets/units/<faction>.glb, Alpha 11's own meshes, unmodified), three across like Alpha 11's
## default formation, one model per unit as the player counts them (Rules.shown), each standing on
## a small disc in its owner's seat colour so ownership still reads by seat (GAME-RULES sec2).
## Garrisons stand in a ring round the tower instead of a goo river. Drawn with one MultiMesh per
## faction plus one for the discs, rebuilt every frame - cheap at these counts.

const UNIT_SIZE := 1.3               # metres across a creature (readable at full-map zoom)
const ACROSS := 3                    # Alpha 11's default formation
const ROW := 1.35                    # metres between rows
const LANE := 0.95                   # metres between the columns
const MAX_PER_HORDE := 60
const MODEL_YAW := PI / 2.0          # the models face +Z; the path heading is kit +X

var _mm := {}                        # faction -> MultiMeshInstance3D
var _scale := {}                     # faction -> uniform scale to UNIT_SIZE
var _disc: MultiMeshInstance3D
var _xf := {}                        # faction -> [Transform3D] this frame
var _discs: Array = []               # [[Transform3D, Color]] this frame


func _ready() -> void:
	for f in Rules.FACTIONS.keys():
		var root: Node = load("res://assets/units/%s.glb" % f).instantiate()
		var mesh: Mesh = null
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			mesh = (mi as MeshInstance3D).mesh
			break
		root.free()
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		_scale[f] = UNIT_SIZE / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 1024
		mm.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var src := mesh.surface_get_material(0) as BaseMaterial3D
		if src and src.albedo_texture:                # Alpha 11 lit its creatures bright on a dark board
			var um := StandardMaterial3D.new()
			um.albedo_texture = src.albedo_texture
			um.normal_enabled = src.normal_texture != null
			um.normal_texture = src.normal_texture
			um.metallic = 0.0
			um.roughness = 0.45
			um.emission_enabled = true
			um.emission_texture = src.albedo_texture
			um.emission_energy_multiplier = 0.55
			inst.material_override = um
		add_child(inst)
		_mm[f] = inst
		_xf[f] = []
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.42
	disc_mesh.bottom_radius = 0.42
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


func begin() -> void:
	for f in _xf:
		(_xf[f] as Array).clear()
	_discs.clear()


func add_unit(faction: String, seat: String, pos: Vector3, heading: float, bob := 0.0) -> void:
	if not _xf.has(faction):
		return
	var s: float = _scale[faction]
	var basis := Basis(Vector3.UP, heading + MODEL_YAW).scaled(Vector3.ONE * s)
	(_xf[faction] as Array).append(Transform3D(basis, pos + Vector3(0, 0.08 + bob, 0)))
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
	for f in _mm:
		var arr: Array = _xf[f]
		var mm: MultiMesh = (_mm[f] as MultiMeshInstance3D).multimesh
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
