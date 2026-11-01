class_name DoorView
extends Node3D
## TWO DOORS (Rules.TWO_DOORS) - the readout of the two doors on every BRAWL platform: ONE FLOOR ARROW per door, a flat
## chevron on the ring the lines walk, in the owner's colour (neutral: pale). Daniele 2026-11-02: "keep only the floor
## arrow, drop the door marker" - no arch, no posts, nothing standing up, so the interface stays clear.
## Idle the arrows are faint and point IN (where an arriving line goes in). A door in use lights up: while a line pours
## in through it the arrow flares pointing in; while a line streams out of it (Rules.DOOR_EXITS) it flares pointing OUT.
## The flare is the arrow itself (no separate effect). Created by main.gd while the switch is on; synced every frame.

const CHEV_R := Rules.BRAWL_RING     # the chevron sits on the ring the lines walk
const NEUTRAL := Color(0.75, 0.85, 0.9)
const IDLE_ENERGY := 0.55            # faint when no line uses the door
const IDLE_ALPHA := 0.45

var sim: Sim
var _doors := {}                     # node id -> [front, back]: {root, chev: Node3D, mat: StandardMaterial3D}
var _t := 0.0
static var _chev_mesh: ArrayMesh


static func wanted(s: Sim) -> bool:
	return Rules.TWO_DOORS and not Rules.bridge_combat and s.v3


func setup(s: Sim) -> void:
	sim = s
	name = "DoorView"
	var front := Rules.front_dir()
	for n in sim.nodes:
		if n["node_kind"] == "junction":
			continue
		_doors[n["id"]] = [_door(n, front, "Door_Front"), _door(n, -front, "Door_Back")]


static func _mesh() -> ArrayMesh:
	## A flat chevron in the XZ plane centred on (0, 0, 0), pointing -Z (in toward the platform when placed at +Z).
	if _chev_mesh:
		return _chev_mesh
	var w := 0.95
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-w, 0, 0.55), Vector3(0, 0, -0.55), Vector3(0, 0, -0.05),
		Vector3(-w, 0, 0.55), Vector3(0, 0, -0.05), Vector3(-w, 0, 1.05),
		Vector3(w, 0, 0.55), Vector3(0, 0, -0.05), Vector3(0, 0, -0.55),
		Vector3(w, 0, 0.55), Vector3(w, 0, 1.05), Vector3(0, 0, -0.05)])
	_chev_mesh = ArrayMesh.new()
	_chev_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _chev_mesh


func _door(n: Dictionary, d: Vector3, label: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "%s_%d" % [label, n["id"]]
	add_child(root)
	root.position = (n["pos"] as Vector3) + Vector3(0, 0.06, 0)
	root.rotation.y = atan2(d.x, d.z)                  # local +Z points out of the door
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var chev := MeshInstance3D.new()                  # the floor arrow on the ring
	chev.mesh = _mesh()
	chev.material_override = mat
	chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chev.position = Vector3(0, 0, CHEV_R)
	root.add_child(chev)
	return {"root": root, "chev": chev, "mat": mat}


func door_state(id: int, k: int) -> int:
	## 0 idle, 1 a line pours in by door k (0 front, 1 back) of node id, 2 a line streams out of it. Tests / shots read it.
	return int(_busy.get("%d:%d" % [id, k], 0))


var _busy := {}


func sync(dt: float) -> void:
	_t += dt
	var front := Rules.front_dir()
	_busy.clear()
	for n in sim.nodes:                                # a line streaming out: the door its path starts at
		if n["streaming"].is_empty():
			continue
		var hs := sim._horde(n["streaming"]["hid"])
		if hs.is_empty():
			continue
		var p0: Vector3 = (hs["pts"] as PackedVector3Array)[0] - (n["pos"] as Vector3)
		_busy["%d:%d" % [n["id"], 0 if p0.dot(front) > 0.0 else 1]] = 2
	for h in sim.hordes:                               # a line pouring in wins the arrow (it points in)
		if h["state"] != "absorb" or h["units"] <= 0.0:
			continue
		_busy["%d:%d" % [h["target"], 0 if sim.entry_door_dir(h).dot(front) > 0.0 else 1]] = 1
	for id in _doors:
		var n: Dictionary = sim.nodes[id]
		var gone: bool = sim.collapsed.get(id, false)
		var c: Color = Rules.seat_color(n["owner"]) if n["owner"] != "" else NEUTRAL
		for k in 2:
			var dr: Dictionary = _doors[id][k]
			(dr["root"] as Node3D).visible = not gone
			if gone:
				continue
			var st := door_state(id, k)
			var chev: Node3D = dr["chev"]
			chev.rotation.y = PI if st == 2 else 0.0     # out: the arrow turns to point away from the platform
			var mat: StandardMaterial3D = dr["mat"]
			var col := c.lightened(0.25) if st else c
			col.a = 1.0 if st else IDLE_ALPHA
			mat.albedo_color = col
			mat.emission = c
			mat.emission_energy_multiplier = (2.6 + 0.6 * sin(_t * 12.0)) if st else IDLE_ENERGY
