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


const RELAY_HOUSING := {"rotation": "Relay_Rotation_Tower", "retract": "Relay_Retract",
		"switch": "Relay_Switch_Hub", "remote": "Relay_Remote"}


static func build(parent: Node3D, sim: Sim) -> Dictionary:
	## Returns node id -> {"parts": [Node3D], "label": Label3D, "vat_node", "vat_tier",
	## "attachment_node", "attachment"}, "stretched": [edge index] and "edge_decks": edge index ->
	## [Node3D] (the relay-controlled ones - see RelayView/relay cycling visibility).
	var vis := {"stretched": [], "edge_decks": {}}
	var centre := Vector3.ZERO
	for n in sim.nodes:
		if n["center"]:
			centre = n["pos"]
	for n in sim.nodes:
		var parts: Array = []
		var relay: String = n["relay"]
		parts.append(put(parent, "Platform_Rotation" if relay == "rotation" else "Platform_Standard", n["pos"]))
		var vat_node: Node3D
		if relay != "":
			# a relay node has NO vat (GAME-RULES sec6: centreHasNoVat): its housing is a FIXED
			# structure (never swaps, unlike a vat) - Daniele: the Blender kit's rim-ledge mount
			# didn't come across straight, so this centres it instead (guaranteed not to float or
			# clip). The attachment SOCKET is the separate swappable centre slot a cannon/forge
			# later replaces, same as on a final node.
			var out: Vector3 = (n["pos"] - centre)
			out = out.normalized() if out.length() > 0.5 else Vector3.FORWARD
			parts.append(put(parent, RELAY_HOUSING.get(relay, "Relay_Mount"), n["pos"], Rules.heading(out)))
			vat_node = put(parent, "Socket_Attachment", n["pos"])
		else:
			vat_node = put(parent, "Vat_T%d" % n["tier"], n["pos"])
		parts.append(vat_node)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.02
		label.font_size = 96
		label.outline_size = 24
		label.no_depth_test = true
		label.position = n["pos"] + Vector3(0, 10.5, 0)
		parent.add_child(label)
		vis[n["id"]] = {"parts": parts, "label": label, "vat_node": vat_node,
				"vat_tier": -1 if relay != "" else n["tier"],   # -1: never swap a relay's socket for a vat
				"attachment_node": null, "attachment": "", "cannon_tier": 0}
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
		var piece := "Deck_Retract" if e["retracts"] else ("Deck_Remote" if e["state"].begins_with("m") else "Deck_S")
		var deck_nodes: Array = []
		for k in range(e["modules"]):
			deck_nodes.append(put(parent, piece, pa + d * (Rules.R + Rules.PIER + k * Rules.S * f),
					Rules.heading(d), f))
		vis["edge_decks"][i] = deck_nodes                  # main.gd toggles these against
                                                            # Sim.is_edge_open (relay cycling AND a
                                                            # shield-broken bond, on ANY edge)
	return vis


static func set_vat_tier(parent: Node3D, entry: Dictionary, tier: int, seat: String) -> void:
	## Swap a node's vat model for its new tier (upgrade_vat, Rules.BUILD_SECONDS after the tap).
	if entry["vat_tier"] == tier:
		return
	(entry["parts"] as Array).erase(entry["vat_node"])
	(entry["vat_node"] as Node).queue_free()
	var vat_node := put(parent, "Vat_T%d" % tier, (entry["label"] as Label3D).position - Vector3(0, 10.5, 0))
	entry["parts"].append(vat_node)
	entry["vat_node"] = vat_node
	entry["vat_tier"] = tier
	apply_owner(entry["parts"], seat)


static func set_attachment(parent: Node3D, entry: Dictionary, kind: String, tier: int, pos: Vector3, seat: String) -> void:
	## A built cannon or forge REPLACES whatever sits in the centre slot (the vat, or a relay's
	## empty socket) at the exact same spot - GAME-RULES sec6: a node's attachment is one slot, not
	## an extra piece bolted on the side (that offset placement was the misalignment Daniele found).
	## kind "" restores an empty Socket_Attachment. `tier` only matters for a cannon (T1-T3).
	if entry["attachment"] == kind and (kind != "cannon" or entry.get("cannon_tier", 1) == tier):
		return
	if entry["vat_node"]:
		(entry["parts"] as Array).erase(entry["vat_node"])
		(entry["vat_node"] as Node).queue_free()
	var piece := "Socket_Attachment" if kind == "" else ("Cannon_T%d" % tier if kind == "cannon" else "Forge")
	var node := put(parent, piece, pos)
	entry["parts"].append(node)
	entry["vat_node"] = node
	entry["attachment_node"] = node
	entry["attachment"] = kind
	entry["cannon_tier"] = tier
	apply_owner(entry["parts"], seat)


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
