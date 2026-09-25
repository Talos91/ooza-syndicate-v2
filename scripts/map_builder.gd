class_name MapBuilder
extends RefCounted
## Lays a roster map out at honest lengths and builds it from the kit GLBs (assets/kit).
## Layout: breadth-first from the centre node, keeping each edge's schematic direction and
## giving it its honest length (Rules.span). Exact for trees such as Two Piers; for maps with
## cycles an edge that closes a loop keeps whatever length results and its modules are stretched
## (flagged in `stretched`) - the roster rewrite fixes those maps (OPEN-QUESTIONS.md).
##
## Relay nodes (BUILDING-PIECES.md B, Daniele 2026-09-24): the attachment socket sits in the
## middle like a vat; the relay's own tower stands on Relay_Mount, a ledge bolted outside the rim
## in the widest free gap between piers; the retract housing is the gate the deck slides into,
## straddling the rim where that deck enters. State colours: a relay-controlled deck's edge lights
## carry its state's colour, the tower's symbol (OS_State) glows in the current state's colour.

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
	mark_crossings(map, pos)
	return pos


static func mark_crossings(map: Dictionary, pos: Dictionary) -> void:
	## Decks that cross must be overpasses (GAME-RULES sec7: "overpasses cross at different heights
	## without joining; only a modelled junction allows a turn"). The roster leaves some crossings
	## unmarked (24 maps, e.g. Trident Exchange 6-7 x 1-4 - Daniele: "no overpass"), so on load each
	## crossing pair gets one deck raised: the longer one that isn't relay-controlled. The roster
	## files are not edited (OPEN-QUESTIONS). A deck already marked covers every crossing it has.
	var es: Array = map["edges"]
	for i in range(es.size()):
		for j in range(i + 1, es.size()):
			var e: Dictionary = es[i]
			var g: Dictionary = es[j]
			var ids := [int(e["from"]), int(e["to"]), int(g["from"]), int(g["to"])]
			if ids[0] in [ids[2], ids[3]] or ids[1] in [ids[2], ids[3]]:
				continue
			if not (pos.has(ids[0]) and pos.has(ids[1]) and pos.has(ids[2]) and pos.has(ids[3])):
				continue
			if e.get("overpass", false) or g.get("overpass", false):
				continue
			var a := Vector2(pos[ids[0]].x, pos[ids[0]].z)
			var b := Vector2(pos[ids[1]].x, pos[ids[1]].z)
			var c := Vector2(pos[ids[2]].x, pos[ids[2]].z)
			var d := Vector2(pos[ids[3]].x, pos[ids[3]].z)
			var r := b - a
			var s := d - c
			var den := r.cross(s)
			if absf(den) < 1e-6:
				continue
			var t := (c - a).cross(s) / den
			var u := (c - a).cross(r) / den
			if t <= 0.02 or t >= 0.98 or u <= 0.02 or u >= 0.98:
				continue
			var can_e := _can_raise(e)
			var can_g := _can_raise(g)
			var pick: Dictionary = {}
			if can_e and can_g:
				var fe: bool = e.get("state") == null and not e.get("retracts", false)
				var fg: bool = g.get("state") == null and not g.get("retracts", false)
				if fe != fg:
					pick = e if fe else g
				else:
					pick = e if _mods(e) >= _mods(g) else g
			elif can_e:
				pick = e
			elif can_g:
				pick = g
			if not pick.is_empty():
				pick["overpass"] = true
				pick["overpass_auto"] = true


static func _mods(e: Dictionary) -> int:
	return {"S": 1, "M": 2, "L": 3}[e["tier"]]


static func _can_raise(e: Dictionary) -> bool:
	## An overpass needs a ramp up and a ramp down (2+ modules). Relay decks may be raised too (their
	## ramps carry the state lights), but a fixed deck is preferred when both could go up.
	return _mods(e) >= 2


static func piece(name: String) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load(KIT % name)
	var node: Node3D = (_scenes[name] as PackedScene).instantiate()
	Mats.apply_detail(node)                         # Alpha 16: surface detail on the flat kit colours
	return node


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
const MOUNT_DIST := 7.15             # the tower's centre on the Relay_Mount ledge (kit: 4.6..9.63 m)


static func widest_gap_dir(pos: Vector3, neighbours: Array) -> Vector3:
	## Unit vector into the widest angular gap between this node's piers (where the ledge goes).
	if neighbours.is_empty():
		return Vector3.FORWARD
	var angles := []
	for p in neighbours:
		angles.append(atan2((p as Vector3).z - pos.z, (p as Vector3).x - pos.x))
	angles.sort()
	var best := 0.0
	var best_gap := -1.0
	for i in range(angles.size()):
		var a0: float = angles[i]
		var a1: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		if a1 - a0 > best_gap:
			best_gap = a1 - a0
			best = (a0 + a1) / 2.0
	return Vector3(cos(best), 0.0, sin(best))


static func build(parent: Node3D, sim: Sim) -> Dictionary:
	## Returns node id -> {"parts": [Node3D], "platform", "vat_node", "vat_tier", "attachment",
	## "cannon_tier", "housing", "state_parts": [MeshInstance3D], "mount_dir"}, plus "stretched":
	## [edge index], "edge_decks": edge -> [Node3D], "edge_base": edge -> [Transform3D],
	## "edge_piers": edge -> [Node3D, Node3D], "conduits": edge -> MeshInstance3D.
	var vis := {"stretched": [], "edge_decks": {}, "edge_base": {}, "edge_piers": {}, "conduits": {}}
	for n in sim.nodes:
		var parts: Array = []
		var relay: String = n["relay"]
		var platform := put(parent, "Platform_Rotation" if relay == "rotation" else "Platform_Standard", n["pos"])
		parts.append(platform)
		var vat_node: Node3D
		var housing: Node3D = null
		var mount_dir := Vector3.FORWARD
		var state_parts := []
		if relay != "":
			var neighbours := []
			for link in sim.adj[n["id"]]:
				neighbours.append(sim.nodes[link[0]]["pos"])
			if relay == "retract":
				# the gate straddles the rim where the retracting deck enters
				var far := -1
				for i in sim.controlled_edges(n["id"]):
					far = sim._other_end(i, n["id"])
				var d: Vector3 = (sim.nodes[far]["pos"] - n["pos"]).normalized() if far >= 0 else Vector3.FORWARD
				housing = put(parent, "Relay_Retract", n["pos"], Rules.heading(d))
				mount_dir = d
			else:
				mount_dir = widest_gap_dir(n["pos"], neighbours)
				parts.append(put(parent, "Relay_Mount", n["pos"], Rules.heading(mount_dir)))
				housing = put(parent, RELAY_HOUSING[relay], n["pos"] + mount_dir * MOUNT_DIST, Rules.heading(-mount_dir))
			parts.append(housing)
			for mi in housing.find_children("*", "MeshInstance3D", true, false):
				var mesh := (mi as MeshInstance3D).mesh
				for s in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(s)
					if m and m.resource_name.begins_with("OS_State"):
						state_parts.append([mi, s])
			vat_node = put(parent, "Socket_Attachment", n["pos"], Rules.view_yaw)
		else:
			vat_node = put(parent, "Vat_T%d" % n["tier"], n["pos"], Rules.view_yaw)   # every structure faces the viewer
		parts.append(vat_node)
		vis[n["id"]] = {"parts": parts, "platform": platform, "vat_node": vat_node,
				"vat_tier": -1 if relay != "" else n["tier"], "model_key": "",
				"attachment_node": null, "attachment": "", "cannon_tier": 0, "housing": housing,
				"state_parts": state_parts, "mount_dir": mount_dir}
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var pa: Vector3 = sim.nodes[e["a"]]["pos"]
		var pb: Vector3 = sim.nodes[e["b"]]["pos"]
		var d := (pb - pa).normalized()
		var gap := pa.distance_to(pb) - 2.0 * (Rules.R + Rules.PIER)
		var f: float = gap / (e["modules"] * Rules.S)
		if absf(f - 1.0) > 0.02:
			vis["stretched"].append(i)
		var ctrl: int = sim.edge_controller.get(i, -1)
		var switched: bool = e["state"].begins_with("s")
		var pier_a := put(parent, "Pier_Switch" if switched and ctrl == e["a"] else "Pier_Connector", pa, Rules.heading(d))
		var pier_b := put(parent, "Pier_Switch" if switched and ctrl == e["b"] else "Pier_Connector", pb, Rules.heading(-d))
		vis[e["a"]]["parts"].append(pier_a)
		vis[e["b"]]["parts"].append(pier_b)
		vis["edge_piers"][i] = [pier_a, pier_b]
		var piece_name := "Deck_Retract" if e["retracts"] else ("Deck_Remote" if e["state"].begins_with("m") else "Deck_S")
		var deck_nodes: Array = []
		var base: Array = []
		var state_key: String = "retract" if e["retracts"] else e["state"]
		var over: bool = e["overpass"] and e["modules"] >= 2
		for k in range(e["modules"]):
			var deck: Node3D
			if over and k == e["modules"] - 1:           # overpass: ramp down, laid from the far end
				deck = put(parent, "Deck_Overpass_Ramp", pb - d * (Rules.R + Rules.PIER), Rules.heading(-d), f)
			elif over:                                   # ramp up, then the raised span on pylons
				deck = put(parent, "Deck_Overpass_Ramp" if k == 0 else "Deck_Overpass_Span",
						pa + d * (Rules.R + Rules.PIER + k * Rules.S * f), Rules.heading(d), f)
			else:
				deck = put(parent, piece_name, pa + d * (Rules.R + Rules.PIER + k * Rules.S * f), Rules.heading(d), f)
			if state_key != "":
				set_lights(deck, Mats.light_color(Rules.state_color(state_key)))
			deck_nodes.append(deck)
			base.append(deck.transform)
		vis["edge_decks"][i] = deck_nodes
		vis["edge_base"][i] = base
		if e["state"].begins_with("m") and ctrl >= 0:  # remote: a lit conduit from the console to its deck
			var c: Vector3 = sim.nodes[ctrl]["pos"] + vis[ctrl]["mount_dir"] * MOUNT_DIST
			var mid := (pa + pb) / 2.0
			var conduit := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 0.12, 0.22)
			conduit.mesh = box
			conduit.material_override = Mats.light_color(Rules.state_color(e["state"]))
			parent.add_child(conduit)
			var v := mid - c
			conduit.position = (c + mid) / 2.0 + Vector3(0, 0.55, 0)
			conduit.rotation = Vector3(0, Rules.heading(v.normalized()), 0)
			conduit.scale = Vector3(v.length(), 1.0, 1.0)
			vis["conduits"][i] = conduit
	return vis


static func set_lights(node: Node3D, mat: Material) -> void:
	## Override every OS_Light surface of a piece (deck edge lights in a state colour, or null).
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s)
			if m and m.resource_name.begins_with("OS_Light"):
				mi.set_surface_override_material(s, mat)


static func set_state_color(entry: Dictionary, c: Color) -> void:
	for pair in entry["state_parts"]:
		(pair[0] as MeshInstance3D).set_surface_override_material(pair[1], Mats.light_color(c))


static func model_for(n: Dictionary) -> String:
	## Which centre-slot model a node shows right now - the build TARGET while a build runs (Alpha
	## 11 shows the new structure growing out of the socket), otherwise what stands there.
	if n["build_kind"] != "" and not n["build_target"].is_empty():
		var t: Dictionary = n["build_target"]
		if t["kind"] == "vat":
			return "Vat_T%d" % t["tier"]
		return "Cannon_T%d" % t["tier"] if t["kind"] == "cannon" else "Forge"
	if n["attachment"] == "cannon":
		return "Cannon_T%d" % maxi(n["cannon_tier"], 1)
	if n["attachment"] == "forge":
		return "Forge"
	if n["relay"] != "":
		return "Socket_Attachment"
	return "Vat_T%d" % n["tier"]


static func set_centre_model(parent: Node3D, entry: Dictionary, model: String, pos: Vector3, seat: String) -> Node3D:
	## Swap the node's centre slot (vat / socket / cannon / forge) for `model` at the exact same
	## spot - GAME-RULES sec6: one slot, never an extra piece bolted on the side. Returns the node.
	if entry["model_key"] == model:
		return entry["vat_node"]
	if entry["vat_node"]:
		(entry["parts"] as Array).erase(entry["vat_node"])
		(entry["vat_node"] as Node).queue_free()
	var node := put(parent, model, pos, Rules.view_yaw)
	entry["parts"].append(node)
	entry["vat_node"] = node
	entry["model_key"] = model
	apply_owner(entry["parts"], seat)
	return node


static func apply_owner(parts: Array, seat: String) -> void:
	## Structure = model, ownership = material: swap the lights and the vat ooze per surface.
	for p in parts:
		if not is_instance_valid(p):
			continue
		for mi in (p as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for s in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(s)
				var name := m.resource_name if m else ""
				if name.begins_with("OS_Light"):
					mi.set_surface_override_material(s, Mats.light(seat) if seat != "" else null)
				elif name.begins_with("OS_Ooze"):
					if mi.has_meta("vat_liquid"):             # a living liquid (Scenery) colours itself
						continue
					mi.set_surface_override_material(s, Mats.ooze(seat) if seat != "" else null)
