class_name MapBuilder
extends RefCounted
## Builds the arena from the kit GLBs (assets/kit). The game's maps (maps4/*.json +
## assets/maps4/<code>.glb) carry a baked layout: layout3() reads it and build3() only places pieces
## (see the baked layout section below). The archive roster in maps/ still goes through layout()
## (breadth-first at honest lengths, mark_crossings) for the rules tests, and through build() for
## the desktop --map dev path.
##
## Relay nodes (BUILDING-PIECES.md B, Daniele 2026-09-24): the attachment socket sits in the
## middle like a vat; the relay's own tower stands on Relay_Mount, a ledge bolted outside the rim
## in the widest free gap between piers; the retract housing is the gate the deck slides into,
## straddling the rim where that deck enters. State colours: a relay-controlled deck's edge lights
## carry its state's colour, the tower's symbol (OS_State) glows in the current state's colour.

static var _scenes := {}     # keyed by resolved path (Cosmetics.kit_path), not by kit key: see piece()


static func load_map(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func layout(map: Dictionary) -> Dictionary:
	if map.has("layout"):                             # maps 3.0: the baked, approved layout
		return layout3(map)
	var schem := {}
	for n in map["nodes"]:
		schem[int(n["id"])] = Vector3(n["x"], 0.0, n["y"])
	var root := 0
	for n in map["nodes"]:
		if n.get("center", false):
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


static func _mods(e: Dictionary) -> int:
	return {"S": 1, "M": 2, "L": 3}[e["tier"]]


static func _can_raise(e: Dictionary) -> bool:
	## An overpass needs a ramp up and a ramp down (2+ modules). Relay decks may be raised too (their
	## ramps carry the state lights), but a fixed deck is preferred when both could go up.
	return _mods(e) >= 2


static func piece(name: String) -> Node3D:
	## Loads through Cosmetics.kit_path (light kit vs kit_hd, "Phones only" - Alpha 21): the path itself
	## is the cache key, so a profile/HD-pack change mid-session never hands back the wrong quality.
	var scene: PackedScene
	if name.begins_with("skins/"):                  # 0.19.0 cosmetics: loaded on demand, never kept here
		scene = Cosmetics.cached(name)
		if scene == null:
			scene = load(Cosmetics.kit_path(name)) as PackedScene   # (a tier-down ghost of a skin already dropped)
	else:
		var path := Cosmetics.kit_path(name)
		if not _scenes.has(path):
			_scenes[path] = load(path)
		scene = _scenes[path]
	var node: Node3D = scene.instantiate()
	var fit := Cosmetics.fit(name)                  # 0.19.2: the Machinegoon looks at a vat's size, sunk into the socket
	if not fit.is_empty():
		for c in node.get_children():
			if c is Node3D:
				(c as Node3D).scale *= float(fit["scale"])
				(c as Node3D).position = (c as Node3D).position * float(fit["scale"]) - Vector3(0, float(fit["drop"]), 0)
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


static func platform_piece(n: Dictionary) -> String:
	## Relay nodes and strategic nodes (those that can host every structure: vat, cannon, forge) stand on
	## the kit's pillar (Daniele, 0.18.7: "relay nodes and special nodes (like the king of the hill ones so the
	## nodes that can build all structure) need to have the pillar we created on blender"). A rotation relay
	## keeps its turning platform (its machinery is the relay).
	## Structures 2.1 (0.19.0): the special nodes (strategic / final / map-placed T4) keep their pillar.
	if n["relay"] == "rotation":
		return "Platform_Rotation"
	var b: Array = n.get("buildable", [])
	if n["relay"] != "" or n.get("node_kind", "") == "special" or ("cannon" in b and "forge" in b and "vat" in b):
		return "Platform_Pillar"
	return "Platform_Standard"


static func build(parent: Node3D, sim: Sim) -> Dictionary:
	## Returns node id -> {"parts": [Node3D], "platform", "vat_node", "vat_tier", "attachment",
	## "cannon_tier", "housing", "state_parts": [MeshInstance3D], "mount_dir"}, plus "stretched":
	## [edge index], "edge_decks": edge -> [Node3D], "edge_base": edge -> [Transform3D],
	## "edge_piers": edge -> [Node3D, Node3D], "conduits": edge -> MeshInstance3D.
	var vis := {"stretched": [], "edge_decks": {}, "edge_base": {}, "edge_piers": {}, "conduits": {}}
	for n in sim.nodes:
		var parts: Array = []
		var relay: String = n["relay"]
		var platform := put(parent, platform_piece(n), n["pos"])
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
	MapBatch.refresh(node)                          # Alpha 21: a batched piece's light slots follow


static func set_state_color(entry: Dictionary, c: Color) -> void:
	for pair in entry["state_parts"]:
		(pair[0] as MeshInstance3D).set_surface_override_material(pair[1], Mats.light_color(c))


const VAT_MODEL := ["", "Vat_T1", "Vat_T2", "Vat_T3", "Vat_T4"]            # by tier (1-4)
const CANNON_MODEL := ["", "Laser", "Laser", "Laser"]                      # LEGACY: every cannon tier is the laser now


static func model_for(n: Dictionary) -> String:
	## Which centre-slot model a node shows right now - the build TARGET while a build runs (Alpha
	## 11 shows the new structure growing out of the socket), otherwise what stands there. Structures
	## 2.1 (0.19.0): a vat or a Machinegoon (T1-T3) on a common node, a Laser tower / Forge / Monster hub
	## (or the bare socket) on a relay, the T4 vat on a special node - each in the look its OWNER picked
	## (Cosmetics.key_for: the default until a skin has loaded). Called per node per frame (main), so the
	## names come from tables and caches, not string formatting.
	var kind: String
	var tier: int
	if n.get("node_kind", "") == "junction":            # JUNCTION: nothing in the centre slot
		return "junction"
	if n["build_kind"] != "" and not n["build_target"].is_empty():
		var t: Dictionary = n["build_target"]
		kind = t["kind"]
		tier = int(t.get("tier", n["tier"]))
		if kind == "cannon":
			kind = "laser"
	else:
		kind = n.get("structure", "vat")
		tier = n["tier"]
	match kind:
		"vat", "machinegoon", "laser", "forge", "monster_hub":
			return Cosmetics.key_for(kind, n["owner"], tier)
	if n["relay"] != "":
		return "Socket_Attachment"
	return VAT_MODEL[clampi(tier, 1, 4)]


static func centre_lift(model: String) -> Vector3:
	## The laser looks stand on the relay's attachment socket (ATTACH_Z - SOCKET_Z up, Cosmetics.LIFT).
	return Vector3(0, float(Cosmetics.points(model).get("lift", 0.0)), 0)


static func set_centre_model(parent: Node3D, entry: Dictionary, model: String, pos: Vector3, seat: String) -> Node3D:
	## Swap the node's centre slot (vat / socket / machinegoon / laser / forge / hub) for `model` at the
	## exact same spot - GAME-RULES sec6: one slot, never an extra piece bolted on the side. Returns the node.
	if entry["model_key"] == model:
		return entry["vat_node"]
	pos = entry.get("centre", pos)                    # maps 3.0: beside a relay tower that holds the socket
	if entry["vat_node"]:
		(entry["parts"] as Array).erase(entry["vat_node"])
		(entry["vat_node"] as Node).queue_free()
	var node := put(parent, model, pos + centre_lift(model), Rules.view_yaw)
	entry["parts"].append(node)
	entry["vat_node"] = node
	entry["model_key"] = model
	apply_owner(entry["parts"], seat)
	MapBatch.track(node)                            # Alpha 21: the new structure is batched (map_batch.gd)
	return node


# ---------------------------------------------------------------- spinning barrels (0.19.0)
static var _spin_split := {}         # "model|mesh id" -> [static ArrayMesh, spinner ArrayMesh, axis Vector2] (shared)


static func split_spinner(turret: MeshInstance3D, model: String) -> MeshInstance3D:
	## The Machinegoon T3 and the Pepperbox turrets carry their barrel cluster inside the turret mesh.
	## Split it off once per model (Cosmetics.points(model)["spin"]: every mesh island wholly within r of
	## an axis parallel to +Z through (x, y), in front of z0) into a child MeshInstance3D centred on the
	## axis, so the view can turn it about its local Z. Returns the spinner (null if the model has none).
	var spec: Dictionary = Cosmetics.points(model).get("spin", {})
	if spec.is_empty() or turret == null or turret.mesh == null:
		return null
	var ck := "%s|%d" % [model, turret.mesh.get_instance_id()]
	if not _spin_split.has(ck):
		_spin_split[ck] = _split_mesh(turret.mesh, spec["axis"], float(spec["r"]), float(spec["z0"]))
	var pair: Array = _spin_split[ck]
	if pair[1] == null:
		return null
	turret.mesh = pair[0]
	var sp := MeshInstance3D.new()
	sp.name = "Spinner"
	sp.mesh = pair[1]
	sp.position = Vector3((pair[2] as Vector2).x, (pair[2] as Vector2).y, 0.0)
	turret.add_child(sp)
	return sp


static func _split_mesh(src: Mesh, axis: Vector2, r: float, z0: float) -> Array:
	var keep := ArrayMesh.new()
	var spin := ArrayMesh.new()
	var moved := 0
	for s in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			ix = arr[Mesh.ARRAY_INDEX]
		else:
			for i in range(v.size()):
				ix.append(i)
		# islands: vertices joined by triangles or by sharing a position (split normals / UV seams)
		var parent := []                            # (an Array: packed arrays are values, _union must change it)
		parent.resize(v.size())
		for i in range(v.size()):
			parent[i] = i
		var at := {}
		for i in range(v.size()):
			var q := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
			if at.has(q):
				_union(parent, i, at[q])
			else:
				at[q] = i
		for k in range(0, ix.size() - 2, 3):
			_union(parent, ix[k], ix[k + 1])
			_union(parent, ix[k + 1], ix[k + 2])
		var inside := {}
		for i in range(v.size()):
			var root := _find(parent, i)
			var ok: bool = Vector2(v[i].x, v[i].y).distance_to(axis) <= r and v[i].z >= z0
			inside[root] = ok and inside.get(root, true)
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for k in range(0, ix.size() - 2, 3):
			if inside.get(_find(parent, ix[k]), false):
				b.append_array([ix[k], ix[k + 1], ix[k + 2]])
			else:
				a.append_array([ix[k], ix[k + 1], ix[k + 2]])
		var mat := src.surface_get_material(s)
		if not a.is_empty():
			var aa := arr.duplicate()
			aa[Mesh.ARRAY_INDEX] = a
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, aa)
			keep.surface_set_material(keep.get_surface_count() - 1, mat)
		if not b.is_empty():
			moved += b.size() / 3
			var bb := arr.duplicate()
			var off := PackedVector3Array(v)
			for i in range(off.size()):
				off[i] -= Vector3(axis.x, axis.y, 0.0)
			bb[Mesh.ARRAY_VERTEX] = off
			bb[Mesh.ARRAY_INDEX] = b
			spin.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bb)
			spin.surface_set_material(spin.get_surface_count() - 1, mat)
	return [keep, spin if moved > 0 else null, axis]


static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


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
		MapBatch.refresh(p)                             # Alpha 21: a batched piece's light / ooze slots follow


# ---------------------------------------------------------------- baked layout (maps 3.0 / 4.0 pipeline)
# Maps 4.0 (References/Ooze Syndicate maps 4.0, the landscape phone pack) come with the Blender builder's
# layout baked per map (Models/2.0/export_maps_4_0_game.py -> maps4/*.json + assets/maps4/<code>.glb): 1.7 m
# per map unit, each bridge on its own rim exit, angled piers (Pier_Angled_00..80, mirrored for negative
# leans; plazas get exact cuts in the map's GLB), deck heights 0 / +4 / -4 / +8 from the clearance
# planner, ramps between the pier and the first crossing, relay towers on the clearest rim ledge or on
# the socket; a pocket hop too short for two piers is a dock (one straight connector, or plain contact).
# This only places pieces; it never re-plans.
const OVER_H := 4.0                  # Deck_Overpass_High rise per level (builder OVER_H)
const UNDER_BASE := 2.4              # Deck_Underpass depth as modelled (builder base)


static func layout3(map: Dictionary) -> Dictionary:
	var pos := {}
	var nodes: Dictionary = map["layout"]["nodes"]
	for k in nodes:
		pos[int(k)] = Vector3(nodes[k][0], 0.0, nodes[k][1])
	return pos


static func angled_pier(parent: Node3D, exit: Vector3, dir: Vector3, lean: float, switched: bool) -> Node3D:
	var step := clampi(roundi(absf(lean) / 5.0) * 5, 0, 80)
	var n := put(parent, "Pier_Angled_%02d%s" % [step, "_Switch" if switched else ""], exit, Rules.heading(dir))
	if lean < 0.0:
		mirror_z(n)                                # negative lean: the piece mirrored across its deck axis
	return n


static var _mirrored := {}           # kit Mesh -> its copy mirrored across local z (built once, shared)
const MIRROR_Z := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3.ZERO)


static func mirror_z(node: Node3D) -> void:
	## Mirror a placed kit piece across its local z (deck) axis WITHOUT a negative scale. Daniele
	## (0.18.5): "remains a problem a few dark socket connectors" - those were the negative-lean piers,
	## mirrored with scale z = -1: the kit materials are double-sided, and on a mirrored instance the
	## GL Compatibility renderer takes the top faces for back faces and flips their normals down, so
	## the deck plate went almost black. Instead every mesh below the piece is swapped for a mirrored
	## copy (z negated, normals and tangents mirrored, triangles re-wound) and every child transform is
	## conjugated by the mirror, so the piece keeps a proper transform and lights like its neighbours.
	for c in [node] + node.find_children("*", "Node3D", true, false):
		var n3 := c as Node3D
		if n3 != node:                             # the root keeps its placement
			n3.transform = MIRROR_Z * n3.transform * MIRROR_Z
		if n3 is MeshInstance3D and (n3 as MeshInstance3D).mesh != null:
			var mi := n3 as MeshInstance3D
			var src := mi.mesh
			if not _mirrored.has(src):
				_mirrored[src] = _mirror_mesh(src)
			mi.mesh = _mirrored[src]
			for s in range(mi.get_surface_override_material_count()):
				mi.set_surface_override_material(s, null)
	Mats.apply_detail(node)                        # the detail overrides, on the new surfaces


static func _mirror_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in range(v.size()):
			v[k] = v[k] * Vector3(1, 1, -1)
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in range(nr.size()):
				nr[k] = nr[k] * Vector3(1, 1, -1)
			arr[Mesh.ARRAY_NORMAL] = nr
		if arr[Mesh.ARRAY_TANGENT] != null:            # xyzw: mirror the tangent, flip the binormal sign
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for k in range(0, tg.size(), 4):
				tg[k + 2] = -tg[k + 2]
				tg[k + 3] = -tg[k + 3]
			arr[Mesh.ARRAY_TANGENT] = tg
		if arr[Mesh.ARRAY_INDEX] != null:              # a mirror turns the winding: swap two corners
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in range(0, ix.size() - 2, 3):
				var t := ix[k + 1]
				ix[k + 1] = ix[k + 2]
				ix[k + 2] = t
			arr[Mesh.ARRAY_INDEX] = ix
		else:                                          # unindexed: index it in the swapped order
			var ix := PackedInt32Array()
			for k in range(0, v.size() - 2, 3):
				ix.append_array([k, k + 2, k + 1])
			arr[Mesh.ARRAY_INDEX] = ix
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
		out.surface_set_material(s, src.surface_get_material(s))
		if src is ArrayMesh:
			out.surface_set_name(s, (src as ArrayMesh).surface_get_name(s))
	return out


static func build3(parent: Node3D, sim: Sim, map: Dictionary) -> Dictionary:
	var lay: Dictionary = map["layout"]
	var vis := {"stretched": [], "edge_decks": {}, "edge_base": {}, "edge_piers": {}, "conduits": {}, "plazas": {}}
	var glb_nodes := {}
	if str(lay.get("glb", "")) != "" and ResourceLoader.exists(lay["glb"]):
		var inst: Node3D = (load(lay["glb"]) as PackedScene).instantiate()
		parent.add_child(inst)
		Mats.apply_detail(inst)
		for c in inst.find_children("*", "Node3D", true, false):
			glb_nodes[String(c.name)] = c
	for pid in lay.get("plazas", {}):
		var members := []
		for n in sim.nodes:
			if n["plaza"] == int(pid):
				members.append(n["id"])
		vis["plazas"][int(pid)] = {"node": glb_nodes.get("Plaza_%s" % pid), "members": members}
	var relays: Dictionary = lay.get("relays", {})
	for n in sim.nodes:
		var id: int = n["id"]
		var parts: Array = []
		var relay: String = n["relay"]
		var on_plaza: bool = n["plaza"] >= 0
		var platform: Node3D = null
		if n.get("junction", "") != "":                # JUNCTION: the piece itself (a curve's origin is its start port)
			var ji := map["nodes"][id] as Dictionary
			platform = put(parent, "junctions/" + str(n["junction"]), n["pos"], deg_to_rad(float(ji.get("junctionYaw", 0.0))))
			parts.append(platform)
			var empty := Node3D.new()
			parent.add_child(empty)
			empty.position = n["pos"]
			vis[id] = {"parts": parts, "platform": platform, "vat_node": empty, "vat_tier": -1, "model_key": model_for(n),
					"attachment_node": null, "attachment": "", "cannon_tier": 0, "housing": null, "state_parts": [],
					"mount_dir": Vector3.FORWARD, "centre": n["pos"], "state_hosts": []}
			continue
		if not on_plaza:
			platform = put(parent, platform_piece(n), n["pos"])
			parts.append(platform)
		var housing: Node3D = null
		var mount_dir := Vector3.FORWARD
		var tower_on_socket := false
		var state_parts := []
		if relay != "" and relay != "retract":
			var mount = relays.get(str(id), {}).get("mount")
			if mount is Array:
				mount_dir = Vector3(mount[0], 0.0, mount[1]).normalized()
				parts.append(put(parent, "Relay_Mount", n["pos"], Rules.heading(mount_dir)))
				housing = put(parent, RELAY_HOUSING[relay], n["pos"] + mount_dir * MOUNT_DIST, Rules.heading(-mount_dir))
			else:                                      # no clear ledge (or a plaza): the tower holds the socket
				housing = put(parent, RELAY_HOUSING[relay], n["pos"], Rules.view_yaw)
				tower_on_socket = true
			parts.append(housing)
		var centre := n["pos"] as Vector3
		if tower_on_socket:                            # the centre slot moves in front of the tower
			centre += Rules.front_dir() * 3.4
		var vat_node := put(parent, model_for(n), centre + centre_lift(model_for(n)), Rules.view_yaw)
		parts.append(vat_node)
		vis[id] = {"parts": parts, "platform": platform, "vat_node": vat_node,
				"vat_tier": -1 if relay != "" else n["tier"], "model_key": model_for(n),
				"attachment_node": null, "attachment": "", "cannon_tier": 0, "housing": housing,
				"state_parts": state_parts, "mount_dir": mount_dir, "centre": centre,
				"state_hosts": [housing] if housing != null else []}   # every piece carrying an OS_State symbol
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		if e["plaza"]:
			vis["edge_decks"][i] = []
			vis["edge_base"][i] = []
			vis["edge_piers"][i] = []
			continue
		var g: Dictionary = e["geo"]
		var A := Vector3(g["A"][0], 0.0, g["A"][1])
		var B := Vector3(g["B"][0], 0.0, g["B"][1])
		var d := (B - A).normalized()
		var L: float = g["L"]
		var p0: float = g["p0"]
		var p1: float = g["p1"]
		var ctrl: int = sim.edge_controller.get(i, -1)
		var st: String = e["state"]
		var piers := []
		for end in range(2):
			var nid: int = e["a"] if end == 0 else e["b"]
			var exit := A if end == 0 else B
			var dir := d if end == 0 else -d
			var p_len: float = p0 if end == 0 else p1
			var pier: Node3D
			if bool(g["plaza%d" % end]):
				pier = glb_nodes.get("PlazaPier_%d_%d" % [i, end])
			elif g.get("dock", false):                    # maps 4.0 dock: the connector meets the rim directly
				pier = null
			elif sim.nodes[nid].get("junction", "") != "":  # JUNCTION: decks plug straight into the piece's port
				pier = null
			else:
				pier = angled_pier(parent, exit, dir, float(g["lean%d" % end]), st.begins_with("s") and ctrl == nid)
			if pier:
				vis[nid]["parts"].append(pier)
				piers.append(pier)
			if e["retracts"] and ctrl == nid:           # the gate the deck slides into, at the rim
				var gate := put(parent, "Relay_Retract", exit + dir * (p_len - Rules.PIER) - dir * Rules.R, Rules.heading(dir))
				vis[nid]["housing"] = gate
				vis[nid]["parts"].append(gate)
				(vis[nid]["state_hosts"] as Array).append(gate)   # a relay may gate several decks
		vis["edge_piers"][i] = piers
		var state_key: String = "retract" if e["retracts"] else st
		var s0 := A + d * p0
		var s1 := B - d * p1
		var gap := L - p0 - p1
		var h: float = g["h"]
		var decks: Array = []
		if gap >= 0.5:
			if h == 0.0:
				var nmod := maxi(1, roundi(gap / Rules.S))
				var f := gap / (nmod * Rules.S)
				var piece_name := "Deck_Retract" if e["retracts"] else ("Deck_Remote" if st.begins_with("m") else "Deck_S")
				for k in range(nmod):
					decks.append(put(parent, piece_name, s0 + d * (k * Rules.S * f), Rules.heading(d), f))
			else:
				var r0: float = g["r0"]
				var r1: float = g["r1"]
				var ramp := "Deck_Overpass_High_Ramp" if h > 0.0 else "Deck_Underpass_Ramp"
				var span := "Deck_Overpass_High_Span" if h > 0.0 else "Deck_Underpass_Span"
				var base := OVER_H if h > 0.0 else UNDER_BASE
				var zs := absf(h) / base
				var up := put(parent, ramp, s0, Rules.heading(d), r0 / Rules.S)
				up.scale.y = zs
				var down := put(parent, ramp, s1, Rules.heading(-d), r1 / Rules.S)
				down.scale.y = zs
				decks.append(up)
				var flat := gap - r0 - r1
				if flat > 0.05:
					var nmod := maxi(1, roundi(flat / Rules.S))
					for k in range(nmod):
						var sp := put(parent, span, s0 + d * (r0 + k * flat / nmod), Rules.heading(d), flat / (nmod * Rules.S))
						sp.position.y = h - base if h > 0.0 else h + base
						decks.append(sp)
				decks.append(down)
		if state_key != "":
			for dk in decks:
				set_lights(dk, Mats.light_color(Rules.state_color(state_key)))
		vis["edge_decks"][i] = decks
		vis["edge_base"][i] = decks.map(func(x): return (x as Node3D).transform)
		if st.begins_with("m") and ctrl >= 0:          # remote: a lit conduit from the console to its deck
			var c: Vector3 = sim.nodes[ctrl]["pos"] + vis[ctrl]["mount_dir"] * (MOUNT_DIST if relays.get(str(ctrl), {}).get("mount") is Array else 0.0)
			var mid := (A + B) / 2.0
			var conduit := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 0.12, 0.22)
			conduit.mesh = box
			conduit.material_override = Mats.light_color(Rules.state_color(st))
			parent.add_child(conduit)
			var v := mid - c
			conduit.position = (c + mid) / 2.0 + Vector3(0, 0.55, 0)
			conduit.rotation = Vector3(0, Rules.heading(v.normalized()), 0)
			conduit.scale = Vector3(v.length(), 1.0, 1.0)
			vis["conduits"][i] = conduit
	for n in sim.nodes:                               # relay symbols (OS_State) on the housings and gates
		for hs in vis[n["id"]]["state_hosts"]:
			for mi in (hs as Node3D).find_children("*", "MeshInstance3D", true, false):
				var mesh := (mi as MeshInstance3D).mesh
				for s in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(s)
					if m and m.resource_name.begins_with("OS_State"):
						(vis[n["id"]]["state_parts"] as Array).append([mi, s])
	return vis
