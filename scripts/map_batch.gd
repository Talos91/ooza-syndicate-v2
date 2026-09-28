class_name MapBatch
extends Node3D
## Alpha 21 OPT-RENDER: the map's kit pieces drawn as MultiMeshes instead of one draw call per surface per
## piece (Daniele: phones overheat, co-op shows LOW FPS). A 202 m map had ~1,500 draw calls, most of them
## the same few deck / pier / platform / vat surfaces repeated.
##
## Nothing changes for the game code: every piece keeps its node, transform, visibility, overrides and
## place in `vis`; only its MeshInstance3D draws on no layer (layers = 0) while a MultiMesh slot draws it.
## - The fixed surfaces (plate, dark, steel, recess, shell) of a piece share one slot in the batch of its
##   mesh + materials + map cell (CHUNK: culling and the kit's automatic LODs work per cell).
## - Every other surface (lights, ooze, state symbols, glass, a vat's living liquid) has a slot in the batch
##   of its mesh, surface and CURRENT material (a unique material simply makes a batch of one).
## - Static pieces (platforms, piers, relay ledges, fixed decks) change only by recolouring (MapBuilder.
##   set_lights / apply_owner call refresh()), hiding (Node3D.visibility_changed: a demolished deck) and
##   falling (Fx._collapse calls release(): the piece draws itself again and the tween moves it).
## - Structures in the centre slot (vats, Machinegoons, lasers, forges, hubs, sockets and their skins) grow,
##   pump, aim and swap: they are polled each frame (transform, visibility, mesh, materials - a few dozen
##   pieces) and a freed one leaves its batches. MapBuilder.set_centre_model tracks the new one (track()).
## - Relay pieces (housings, gates, controlled decks, turntable platforms) move only while a relay works:
##   polled like the structures.
## Never batched: anything with a material_override (ghosts), skinned meshes or blend shapes.

const STATIC_KIT := ["Platform_", "Pier_", "Relay_Mount", "Deck_"]   # kit scenes batched as static pieces
# low-poly pieces in many variants (17 pier leans, switch and mirrored copies, one or two of each on a map):
# merged into one mesh per material instead (a MultiMesh per variant would still cost a draw per variant)
const MERGED_KIT := ["Pier_", "Relay_Mount"]
const FIXED := ["OS_Plate", "OS_Dark", "OS_Steel", "OS_Recess", "OS_Shell"]   # materials no game code swaps
const STATIC_GROUP := -1
const CHUNK := 128.0                    # batches split into cells of at most this size over the map's bounds
                                        # (per-cell frustum culling and LOD; most maps are one or two cells)

static var current: MapBatch = null     # the live match's batcher (null: nothing is batched)
static var disabled := false            # --no-batch (A/B measurements)

var _batches := {}                      # key -> Batch
var _pieces := {}                       # MeshInstance3D instance id -> Piece
var _by_root := {}                      # static root Node3D instance id -> [Piece]
var _polled: Array = []                 # structure Pieces checked every frame
var _dirty := {}                        # Merged batches to rebuild this frame
var _lo := Vector2.ZERO                 # the map's plan bounds and cell size (chunk_of)
var _cell := Vector2(CHUNK, CHUNK)


class Batch:
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D
	var items: Array = []               # slot -> [Piece, group]

	func add(p: Piece, group: int) -> void:
		var i := items.size()
		items.append([p, group])
		p.slots[group] = [self, i]
		if i >= mm.instance_count:      # grow (a new instance_count clears the buffer: write every slot again)
			mm.instance_count = maxi(8, mm.instance_count * 2)
			for k in range(items.size()):
				mm.set_instance_transform(k, (items[k][0] as Piece).xform)
		else:
			mm.set_instance_transform(i, p.xform)
		mm.visible_instance_count = items.size()
		mmi.visible = true

	func remove(p: Piece, group: int) -> void:
		var i: int = p.slots[group][1]
		var last := items.size() - 1
		if i != last:                   # the last slot fills the hole
			var moved: Array = items[last]
			items[i] = moved
			(moved[0] as Piece).slots[moved[1]] = [self, i]
			mm.set_instance_transform(i, (moved[0] as Piece).xform)
		items.pop_back()
		p.slots.erase(group)
		mm.visible_instance_count = items.size()
		mmi.visible = not items.is_empty()

	func move(p: Piece, group: int) -> void:
		mm.set_instance_transform(p.slots[group][1], p.xform)


class Merged:
	## One material's surfaces of the MERGED_KIT pieces, baked into a single mesh (rebuilt when a piece
	## joins or leaves: a capture recolours a pier's lights, a fall releases it).
	var host: MapBatch
	var mi: MeshInstance3D
	var items: Array = []               # slot -> [Piece, surface]

	func add(p: Piece, group: int) -> void:
		items.append([p, group])
		p.slots[group] = [self, items.size() - 1]
		host._dirty[self] = true

	func remove(p: Piece, group: int) -> void:
		var i: int = p.slots[group][1]
		var last := items.size() - 1
		if i != last:
			var moved: Array = items[last]
			items[i] = moved
			(moved[0] as Piece).slots[moved[1]] = [self, i]
		items.pop_back()
		p.slots.erase(group)
		host._dirty[self] = true

	func move(_p: Piece, _group: int) -> void:
		host._dirty[self] = true

	func rebuild() -> void:
		mi.visible = not items.is_empty()
		if items.is_empty():
			return
		var st := SurfaceTool.new()
		for it in items:
			st.append_from((it[0] as Piece).mesh, it[1], (it[0] as Piece).xform)
		mi.mesh = st.commit()


class Piece:
	var mi: MeshInstance3D
	var id := 0                         # mi's instance id (kept: mi may be freed)
	var mesh: Mesh
	var root: Node3D
	var xform: Transform3D
	var chunk := ""
	var static_key := ""
	var merge := false                  # a MERGED_KIT piece: every surface goes to its material's Merged
	var dyn := {}                       # surface index -> material in its batch
	var slots := {}                     # group (STATIC_GROUP or a surface index) -> [Batch, slot]
	var attached := false


# ------------------------------------------------------------------ building
static func build(main: Node3D) -> MapBatch:
	## Batch main's map (main.vis / main.sim). Called once the match is set up (Fx has made its ghost decks:
	## copies made later go through show_copy()).
	if disabled:
		return null
	var b := MapBatch.new()
	b.name = "MapBatch"
	main.add_child(b)
	current = b
	var vis: Dictionary = main.get("vis")
	var sim = main.get("sim")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in sim.nodes:
		var q := Vector2((n["pos"] as Vector3).x, (n["pos"] as Vector3).z)
		lo = lo.min(q)
		hi = hi.max(q)
	var ext := (hi - lo).max(Vector2.ONE)
	b._lo = lo
	b._cell = Vector2(ext.x / ceilf(ext.x / CHUNK), ext.y / ceilf(ext.y / CHUNK))
	for n in sim.nodes:
		var entry: Dictionary = vis[n["id"]]
		var moving := [entry.get("vat_node"), entry.get("housing"), entry.get("attachment_node")]
		moving.append_array(entry.get("state_hosts", []))
		if n["relay"] == "rotation":                     # the turntable turns with its relay
			moving.append(entry.get("platform"))
		for p in entry["parts"]:
			if p != null and not p in moving:
				b._track_static(p)
		for p in moving:
			b._track_polled(p)
	for i in range(sim.edges.size()):
		for d in vis["edge_decks"].get(i, []):
			if sim.edge_controller.has(i):               # relay decks slide / swing / retract
				b._track_polled(d)
			else:
				b._track_static(d)
	return b


func _exit_tree() -> void:
	if current == self:
		current = null
	for k in _batches:                                   # Batch <-> Piece refer to each other: break the cycles
		_batches[k].items.clear()
		if _batches[k] is Merged:
			(_batches[k] as Merged).host = null
	_dirty.clear()
	for k in _pieces:
		(_pieces[k] as Piece).slots.clear()
	_batches.clear()
	_pieces.clear()
	_by_root.clear()
	_polled.clear()


func _new_pieces(root: Node3D) -> Array:
	var list := []
	for mi in [root] + root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or m.material_override != null or m.skin != null or m.layers == 0:
			continue
		if _pieces.has(m.get_instance_id()) or (m.mesh is ArrayMesh and (m.mesh as ArrayMesh).get_blend_shape_count() > 0):
			continue
		var p := Piece.new()
		p.mi = m
		p.id = m.get_instance_id()
		p.mesh = m.mesh
		p.root = root
		p.xform = m.global_transform
		p.chunk = _chunk_of(p.xform.origin)
		p.static_key = _static_key(m, p.chunk)
		var file := root.scene_file_path.get_file()
		p.merge = MERGED_KIT.any(func(pre): return file.begins_with(pre))
		_pieces[p.id] = p
		list.append(p)
	return list


func _track_static(root) -> void:
	if not is_instance_valid(root) or not root is Node3D or _by_root.has(root.get_instance_id()):
		return
	var file: String = (root as Node).scene_file_path.get_file()
	if not STATIC_KIT.any(func(pre): return file.begins_with(pre)):
		return
	var list := _new_pieces(root)
	if list.is_empty():
		return
	_by_root[root.get_instance_id()] = list
	(root as Node3D).visibility_changed.connect(_on_visibility.bind(root))
	for p in list:
		if p.mi.is_visible_in_tree():
			_attach(p)


func _track_polled(root) -> void:
	if not is_instance_valid(root) or not root is Node3D:
		return
	for p in _new_pieces(root):
		_polled.append(p)
		if p.mi.is_visible_in_tree():
			_attach(p)


func _chunk_of(at: Vector3) -> String:
	return "@%d,%d" % [clampi(floori((at.x - _lo.x) / _cell.x), 0, 64), clampi(floori((at.z - _lo.y) / _cell.y), 0, 64)]


static func _fixed(mat: Material) -> bool:
	return mat != null and mat.resource_name in FIXED


static func _surface_mat(mi: MeshInstance3D, s: int) -> Material:
	var o := mi.get_surface_override_material(s)
	return o if o != null else mi.mesh.surface_get_material(s)


static func _static_key(mi: MeshInstance3D, chunk: String) -> String:
	var k := str(mi.mesh.get_instance_id())
	var any := false
	for s in range(mi.mesh.get_surface_count()):
		if not _fixed(mi.mesh.surface_get_material(s)):
			continue
		var m := _surface_mat(mi, s)
		k += ":%d" % (m.get_instance_id() if m else 0)
		any = true
	return k + chunk if any else ""


func _batch(key: String, mi: MeshInstance3D, surfaces: Array, mats: Array) -> Batch:
	if _batches.has(key):
		return _batches[key]
	var mesh := ArrayMesh.new()
	var src = mi.mesh.get("_surfaces") if mi.mesh is ArrayMesh else null
	if src is Array and (src as Array).size() == mi.mesh.get_surface_count():
		# the raw surfaces, LODs included (a batch keeps the kit's automatic LODs: a far chunk draws light)
		var out := []
		for k in range(surfaces.size()):
			var d: Dictionary = (src[surfaces[k]] as Dictionary).duplicate()
			d["material"] = mats[k]
			out.append(d)
		mesh.set("_surfaces", out)
	else:
		for k in range(surfaces.size()):
			var s: int = surfaces[k]
			mesh.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(s), mi.mesh.surface_get_arrays(s))
			mesh.surface_set_material(k, mats[k])
	var bt := Batch.new()
	bt.mm = MultiMesh.new()
	bt.mm.transform_format = MultiMesh.TRANSFORM_3D
	bt.mm.mesh = mesh
	bt.mm.instance_count = 8
	bt.mm.visible_instance_count = 0
	bt.mmi = MultiMeshInstance3D.new()
	bt.mmi.multimesh = bt.mm
	bt.mmi.cast_shadow = mi.cast_shadow
	add_child(bt.mmi)
	_batches[key] = bt
	return bt


# ------------------------------------------------------------------ slots
func _attach(p: Piece) -> void:
	if p.attached:
		return
	p.attached = true
	p.mi.layers = 0                                   # the node stays; the batch draws it
	p.mi.set_meta("map_batch", true)
	if p.merge:
		for s in range(p.mesh.get_surface_count()):
			_attach_surface(p, s)
		return
	if p.static_key != "":
		var surfaces := []
		var mats := []
		for s in range(p.mesh.get_surface_count()):
			if _fixed(p.mesh.surface_get_material(s)):
				surfaces.append(s)
				mats.append(_surface_mat(p.mi, s))
		_batch(p.static_key, p.mi, surfaces, mats).add(p, STATIC_GROUP)
	for s in range(p.mesh.get_surface_count()):
		if not _fixed(p.mesh.surface_get_material(s)):
			_attach_surface(p, s)


func _attach_surface(p: Piece, s: int) -> void:
	var m := _surface_mat(p.mi, s)
	p.dyn[s] = m
	if p.merge:
		var mk := "M%d" % (m.get_instance_id() if m else 0)
		if not _batches.has(mk):
			var mg := Merged.new()
			mg.host = self
			mg.mi = MeshInstance3D.new()
			mg.mi.material_override = m
			mg.mi.cast_shadow = p.mi.cast_shadow
			add_child(mg.mi)
			_batches[mk] = mg
		_batches[mk].add(p, s)
		return
	var key := "%d/%d/%d%s" % [p.mesh.get_instance_id(), s, m.get_instance_id() if m else 0, p.chunk]
	_batch(key, p.mi, [s], [m]).add(p, s)


func _detach(p: Piece) -> void:
	if not p.attached:
		return
	p.attached = false
	for g in p.slots.keys():
		p.slots[g][0].remove(p, g)
	p.dyn.clear()


func _untrack(p: Piece) -> void:
	## The piece draws itself again (it falls, takes a material_override) or is gone.
	_detach(p)
	_pieces.erase(p.id)
	if is_instance_valid(p.mi):
		p.mi.layers = 1
		p.mi.remove_meta("map_batch")


func _recolour(p: Piece) -> void:
	for s in p.dyn.keys():
		var m := _surface_mat(p.mi, s)
		if m != p.dyn[s]:
			p.slots[s][0].remove(p, s)
			_attach_surface(p, s)


func _on_visibility(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	for p in _by_root.get(root.get_instance_id(), []):
		if p.mi.is_visible_in_tree():
			_attach(p)
		else:
			_detach(p)


func _process(_dt: float) -> void:
	## The structures: gone, hidden, re-meshed (a split turret), overridden, moved (growing, pumping,
	## aiming, tier-down) or recoloured since last frame.
	var k := 0
	while k < _polled.size():
		var p: Piece = _polled[k]
		if not is_instance_valid(p.mi) or not p.mi.is_inside_tree() or not is_instance_valid(p.root) 				or p.root.is_queued_for_deletion():
			_untrack(p)
			_polled.remove_at(k)
			continue
		if p.mi.material_override != null or p.mi.mesh != p.mesh:
			_untrack(p)
			_polled.remove_at(k)
			if p.mi.material_override == null:            # a new mesh (split spinner): track it afresh
				_track_polled(p.mi)
			continue
		k += 1
		var shown := p.mi.is_visible_in_tree()
		if shown != p.attached:
			if shown:
				p.xform = p.mi.global_transform
				_attach(p)
			else:
				_detach(p)
		if not p.attached:
			continue
		var xf := p.mi.global_transform
		if xf != p.xform:
			p.xform = xf
			for g in p.slots:
				p.slots[g][0].move(p, g)
		_recolour(p)
	for mg in _dirty:
		(mg as Merged).rebuild()
	_dirty.clear()


func _refresh(node: Node) -> void:
	for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		var p: Piece = _pieces.get(mi.get_instance_id())
		if p != null and p.attached:
			_recolour(p)


func _refresh_meshes(meshes: Array) -> void:
	for mi in meshes:
		if not is_instance_valid(mi):
			continue
		var p: Piece = _pieces.get((mi as Node).get_instance_id())
		if p != null and p.attached:
			_recolour(p)


func _release(node: Node) -> void:
	var list: Array = _by_root.get(node.get_instance_id(), [])
	_by_root.erase(node.get_instance_id())             # (its visibility_changed hook finds nothing now)
	for p in list:
		_untrack(p)


# ------------------------------------------------------------------ hooks (static: no-ops when nothing is batched)
static func refresh(node: Node) -> void:
	## A piece's recoloured surfaces changed (MapBuilder.set_lights / apply_owner): move their slots.
	if current != null and is_instance_valid(node):
		current._refresh(node)


static func refresh_meshes(meshes: Array) -> void:
	## refresh() for known MeshInstance3Ds (MapBuilder.set_lights' cached light surfaces): no tree search.
	if current != null:
		current._refresh_meshes(meshes)


static func track(node: Node) -> void:
	## A new centre-slot structure (MapBuilder.set_centre_model): batched and polled from now on.
	if current != null and is_instance_valid(node):
		current._track_polled(node)


static func release(nodes: Array) -> void:
	## These pieces are about to move (Fx._collapse: they fall): they draw themselves again.
	if current == null:
		return
	for n in nodes:
		if is_instance_valid(n) and n is Node:
			current._release(n)


static func show_copy(copy: Node) -> void:
	## A duplicate of a batched piece (SkillFx's Demolish fragments) draws itself.
	for mi in [copy] + copy.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("map_batch"):
			(mi as MeshInstance3D).layers = 1
			mi.remove_meta("map_batch")


static func stats() -> Dictionary:
	if current == null:
		return {}
	var inst := 0
	for k in current._batches:
		inst += current._batches[k].items.size()
	return {"batches": current._batches.size(), "instances": inst, "pieces": current._pieces.size(),
			"polled": current._polled.size()}


static func verify() -> Array:
	## tests/perf_check: every tracked piece drawn exactly as its node says - attached while visible, each
	## slot pointing back at it, its MultiMesh transform its node's, its batch material its surface's.
	## Returns the mismatches (empty: consistent).
	var bad := []
	if current == null:
		return bad
	for id in current._pieces:
		var p: Piece = current._pieces[id]
		if not is_instance_valid(p.mi) or not is_instance_valid(p.root) or p.root.is_queued_for_deletion():
			continue                                     # gone this frame: the next poll drops it
		var name := "%s/%s" % [p.root.name, p.mi.name]
		if p.attached != p.mi.is_visible_in_tree():
			bad.append("%s attached=%s visible=%s" % [name, p.attached, p.mi.is_visible_in_tree()])
			continue
		if not p.attached:
			continue
		if p.mi.layers != 0:
			bad.append("%s draws itself too" % name)
		for g in p.slots:
			var b = p.slots[g][0]
			var i: int = p.slots[g][1]
			if b.items[i][0] != p:
				bad.append("%s slot %d/%d points elsewhere" % [name, g, i])
			elif b is Batch and not (b as Batch).mm.get_instance_transform(i).is_equal_approx(p.mi.global_transform):
				bad.append("%s slot %d at the wrong place" % [name, g])
			if g >= 0 and _surface_mat(p.mi, g) != p.dyn.get(g):
				bad.append("%s surface %d in the wrong colour" % [name, g])
	return bad


# ------------------------------------------------------------------ merged unique meshes (Fx's neon)
class Merge:
	## Unique static meshes that only change colour and visibility (Fx's deck-half trims, pier stripes and
	## platform rims: ~190 draw calls on a big map) drawn as one merged mesh per material. The source
	## MeshInstance3Ds stay the game's handles (visible / material_override keep their meaning) but draw on
	## no layer; whoever changes them sets `dirty`, and sync() rebuilds the merged mesh of each material
	## whose members changed. A released one (it falls) draws itself again.
	var host: Node3D
	var all := {}                       # instance id -> MeshInstance3D
	var merged := {}                    # material -> MeshInstance3D
	var members := {}                   # material -> member signature last built
	var dirty := false

	func add(mi: MeshInstance3D) -> void:
		if MapBatch.disabled:
			return
		all[mi.get_instance_id()] = mi
		mi.layers = 0
		dirty = true

	func release(nodes: Array) -> void:
		for n in nodes:
			if is_instance_valid(n) and n is MeshInstance3D and all.has(n.get_instance_id()):
				all.erase(n.get_instance_id())
				(n as MeshInstance3D).layers = 1
				dirty = true

	func sync() -> void:
		if not dirty or host == null:
			return
		dirty = false
		var groups := {}
		for id in all:
			var mi: MeshInstance3D = all[id]
			if not is_instance_valid(mi) or not mi.visible or mi.material_override == null or mi.mesh == null:
				continue
			var m := mi.material_override
			if not groups.has(m):
				groups[m] = []
			(groups[m] as Array).append(mi)
		for m in merged.keys():
			if not groups.has(m):
				(merged[m] as MeshInstance3D).visible = false
				members[m] = ""
		for m in groups:
			var list: Array = groups[m]
			var sig := ",".join(list.map(func(x): return str(x.get_instance_id())))
			if members.get(m, "") == sig:
				continue
			members[m] = sig
			var st := SurfaceTool.new()
			for mi in list:
				for s in range((mi as MeshInstance3D).mesh.get_surface_count()):
					st.append_from((mi as MeshInstance3D).mesh, s, (mi as MeshInstance3D).transform)
			if not merged.has(m):
				var out := MeshInstance3D.new()
				out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				out.material_override = m
				host.add_child(out)
				merged[m] = out
			(merged[m] as MeshInstance3D).mesh = st.commit()
			(merged[m] as MeshInstance3D).visible = true
