class_name MapBuilder
extends RefCounted
## Lays a roster map out at honest lengths and builds it from the kit GLBs (assets/kit).
## Layout: breadth-first from the centre node, keeping each edge's schematic direction and
## giving it its honest length (Rules.span). Exact for trees such as Two Piers; for maps with
## cycles an edge that closes a loop keeps whatever length results and its modules are stretched
## (flagged in `stretched`) - the roster rewrite fixes those maps (OPEN-QUESTIONS.md).

const KIT := "res://assets/kit/%s.glb"
static var _scenes := {}


static func load_map(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func layout(map: Dictionary) -> Dictionary:
	var schem := {}
	for n in map["nodes"]:
		schem[int(n["id"])] = Vector3(n["x"], 0.0, n["y"])
	var root := 0
	for n in map["nodes"]:
		if n["center"]:
			root = int(n["id"])
	var pos := {root: Vector3.ZERO}
	var queue := [root]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for e in map["edges"]:
			var a := int(e["from"])
			var b := int(e["to"])
			var other := b if a == cur else (a if b == cur else -1)
			if other < 0 or pos.has(other):
				continue
			var mods: int = {"S": 1, "M": 2, "L": 3}[e["tier"]]
			var d: Vector3 = (schem[other] - schem[cur]).normalized()
			pos[other] = pos[cur] + d * Rules.span(mods)
			queue.append(other)
	return pos


static func piece(name: String) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load(KIT % name)
	return (_scenes[name] as PackedScene).instantiate()


static func put(parent: Node3D, name: String, pos: Vector3, heading := 0.0, stretch := 1.0) -> Node3D:
	var n := piece(name)
	parent.add_child(n)
	n.position = pos
	n.rotation.y = heading
	if stretch != 1.0:
		n.scale = Vector3(stretch, 1.0, 1.0)
	return n


static func build(parent: Node3D, sim: Sim) -> Dictionary:
	## Returns node id -> {"parts": [Node3D], "label": Label3D} and "stretched": [edge index].
	var vis := {"stretched": []}
	for n in sim.nodes:
		var parts: Array = []
		parts.append(put(parent, "Platform_Standard", n["pos"]))
		parts.append(put(parent, "Vat_T%d" % n["tier"], n["pos"]))
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.02
		label.font_size = 96
		label.outline_size = 24
		label.no_depth_test = true
		label.position = n["pos"] + Vector3(0, 10.5, 0)
		parent.add_child(label)
		vis[n["id"]] = {"parts": parts, "label": label}
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var pa: Vector3 = sim.nodes[e["a"]]["pos"]
		var pb: Vector3 = sim.nodes[e["b"]]["pos"]
		var d := (pb - pa).normalized()
		var gap := pa.distance_to(pb) - 2.0 * (Rules.R + Rules.PIER)
		var f: float = gap / (e["modules"] * Rules.S)
		if absf(f - 1.0) > 0.02:
			vis["stretched"].append(i)
		var pier_a := put(parent, "Pier_Connector", pa, Rules.heading(d))
		var pier_b := put(parent, "Pier_Connector", pb, Rules.heading(-d))
		vis[e["a"]]["parts"].append(pier_a)
		vis[e["b"]]["parts"].append(pier_b)
		for k in range(e["modules"]):
			put(parent, "Deck_S", pa + d * (Rules.R + Rules.PIER + k * Rules.S * f), Rules.heading(d), f)
	return vis


static func apply_owner(parts: Array, seat: String) -> void:
	## Structure = model, ownership = material: swap the lights and the vat ooze per surface.
	for p in parts:
		for mi in (p as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for s in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(s)
				var name := m.resource_name if m else ""
				if name.begins_with("OS_Light"):
					mi.set_surface_override_material(s, Mats.light(seat) if seat != "" else null)
				elif name.begins_with("OS_Ooze"):
					mi.set_surface_override_material(s, Mats.ooze(seat) if seat != "" else null)
