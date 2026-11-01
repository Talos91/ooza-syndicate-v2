class_name DoorView
extends Node3D
## PROTO: TWO DOORS (Rules.PROTO_TWO_DOORS, proto line only) - the look of the two doors on every BRAWL platform.
## PLACEHOLDER GEOMETRY until a kit piece: an arch (two posts and a lintel) facing out of each door, and a chevron on the
## ring pointing in, in the owner's colour (neutral: pale). Proto_Door_Front faces the camera, Proto_Door_Back the far side.
## Readout: a door flares while a line pours in through it, so the player sees which door a line took.
## Created by main.gd only while the switch is on; synced every frame after CombatFx.

const ARCH_R := 3.15                 # m from the node centre to the arch (between the tank bottoms and the ring)
const CHEV_R := Rules.BRAWL_RING     # the chevron sits on the ring the lines walk
const POST_H := 1.7
const SPAN := 1.9                    # m between the posts
const NEUTRAL := Color(0.75, 0.85, 0.9)

var sim: Sim
var _doors := {}                     # node id -> [front pieces, back pieces]: {root, mats: [StandardMaterial3D]}
var _t := 0.0


static func wanted(s: Sim) -> bool:
	return Rules.PROTO_TWO_DOORS and not Rules.bridge_combat and s.v3


func setup(s: Sim) -> void:
	sim = s
	name = "DoorView"
	var front := Rules.front_dir()
	for n in sim.nodes:
		if n["node_kind"] == "junction":
			continue
		_doors[n["id"]] = [_door(n, front, "Proto_Door_Front"), _door(n, -front, "Proto_Door_Back")]


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
	var post := BoxMesh.new()
	post.size = Vector3(0.22, POST_H, 0.22)
	for sx in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = post
		p.material_override = mat
		p.position = Vector3(sx * SPAN * 0.5, POST_H * 0.5, ARCH_R)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(SPAN + 0.22, 0.22, 0.22)
	lintel.mesh = lm
	lintel.material_override = mat
	lintel.position = Vector3(0, POST_H, ARCH_R)
	lintel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lintel)
	var chev := MeshInstance3D.new()                  # a flat arrow on the ring, pointing in toward the door
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var w := 0.95
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-w, 0, CHEV_R + 0.55), Vector3(0, 0, CHEV_R - 0.55), Vector3(0, 0, CHEV_R - 0.05),
		Vector3(-w, 0, CHEV_R + 0.55), Vector3(0, 0, CHEV_R - 0.05), Vector3(-w, 0, CHEV_R + 1.05),
		Vector3(w, 0, CHEV_R + 0.55), Vector3(0, 0, CHEV_R - 0.05), Vector3(0, 0, CHEV_R - 0.55),
		Vector3(w, 0, CHEV_R + 0.55), Vector3(w, 0, CHEV_R + 1.05), Vector3(0, 0, CHEV_R - 0.05)])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	chev.mesh = am
	chev.material_override = mat
	chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(chev)
	return {"root": root, "mat": mat}


func sync(dt: float) -> void:
	_t += dt
	var front := Rules.front_dir()
	var busy := {}                                     # "id:0" front / "id:1" back -> a line pours in there
	for h in sim.hordes:
		if h["state"] != "absorb" or h["units"] <= 0.0:
			continue
		busy["%d:%d" % [h["target"], 0 if sim.entry_door_dir(h).dot(front) > 0.0 else 1]] = true
	for id in _doors:
		var n: Dictionary = sim.nodes[id]
		var gone: bool = sim.collapsed.get(id, false)
		var c: Color = Rules.seat_color(n["owner"]) if n["owner"] != "" else NEUTRAL
		for k in 2:
			var dr: Dictionary = _doors[id][k]
			(dr["root"] as Node3D).visible = not gone
			var mat: StandardMaterial3D = dr["mat"]
			var flare := busy.has("%d:%d" % [id, k])
			var e := 1.0 + (1.6 + 0.6 * sin(_t * 12.0) if flare else 0.0)
			mat.albedo_color = c.lightened(0.25 if flare else 0.0)
			mat.emission = c
			mat.emission_energy_multiplier = e
