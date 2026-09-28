extends Node
## Render census (Alpha 21 OPT-RENDER): runs main.tscn with the given user args, waits --probe-at=<s>
## seconds of real play, then prints the frame's draw calls / primitives / objects and a count of the
## render nodes by class, and quits. Stage like the spec:
##   godot --path . tests/perf_probe.tscn -- --map=res://maps4/A-01-orbital-nexus.json --demo --ai=Standard
##       --ff=120 --window=1266x585 --mobile --probe-at=10

var at := 10.0
var t := 0.0
var samples := []
var tri_cache := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-at="):
			at = float(a.substr(11))
	add_child(load("res://main.tscn").instantiate())


func _process(dt: float) -> void:
	t += dt
	if "--probe-nohud" in OS.get_cmdline_user_args() and get_child(0).get("hud") != null:
		(get_child(0).get("hud").get("root") as CanvasItem).visible = false
	if "--probe-no3d" in OS.get_cmdline_user_args() and get_child(0).get("cam") != null:
		(get_child(0).get("cam") as Camera3D).cull_mask = 0
	if t > at - 3.0:
		samples.append([Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if t < at:
		return
	set_process(false)
	var d := 0.0
	var p := 0.0
	var o := 0.0
	for s in samples:
		d = maxf(d, s[0])
		p = maxf(p, s[1])
		o = maxf(o, s[2])
	var census := {}
	var mm_inst := 0
	for n in get_tree().root.find_children("*", "", true, false):
		var k := n.get_class()
		if n is VisualInstance3D or n is Light3D:
			if n is Node3D and not (n as Node3D).is_visible_in_tree():
				k += "(hidden)"
			elif n is VisualInstance3D and (n as VisualInstance3D).layers == 0:
				k += "(batched)"
			census[k] = census.get(k, 0) + 1
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
				mm_inst += (n as MultiMeshInstance3D).multimesh.visible_instance_count if (n as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (n as MultiMeshInstance3D).multimesh.instance_count
	print("PROBE draw=%d prims=%d objects=%d nodes=%d fps=%d (max over the last 3 s)" % [d, p, o,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Engine.get_frames_per_second()])
	var bad := MapBatch.verify()
	print("VERIFY %d mismatches %s" % [bad.size(), bad.slice(0, 5)])
	var keys := census.keys()
	keys.sort()
	print("CENSUS ", ", ".join(keys.map(func(k): return "%s=%d" % [k, census[k]])), "  multimesh instances=", mm_inst, "  batch=", MapBatch.stats())
	if "--probe-detail" in OS.get_cmdline_user_args():
		_detail()
		print(batch_breakdown())
	get_tree().quit()


func _detail() -> void:
	## Visible MeshInstance3D grouped by the kit piece (their topmost Node3D under main) with surface and
	## triangle totals, biggest draw-call share first.
	var groups := {}
	var main := get_child(0)
	for mi in main.find_children("*", "MeshInstance3D", true, false):
		if not (mi as Node3D).is_visible_in_tree() or (mi as MeshInstance3D).mesh == null or (mi as MeshInstance3D).layers == 0:
			continue
		var top: Node = mi
		while top.get_parent() != main and top.get_parent() != null:
			top = top.get_parent()
		var key := String(top.name).rstrip("0123456789@")
		if top.scene_file_path != "":
			key = top.scene_file_path.get_file()
		if top.get_script() != null:
			key = "[%s] %s" % [top.get_script().resource_path.get_file(), (mi as MeshInstance3D).mesh.get_class() + ":" + String(mi.get_parent().name).rstrip("0123456789@")]
		var mesh := (mi as MeshInstance3D).mesh
		if not tri_cache.has(mesh):
			tri_cache[mesh] = mesh.get_faces().size() / 3
		var tris: int = tri_cache[mesh]
		var g: Array = groups.get(key, [0, 0, 0])
		g[0] += 1
		g[1] += mesh.get_surface_count()
		g[2] += tris
		groups[key] = g
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	for k in keys:
		print("  %-48s meshes=%4d surfaces=%4d tris=%7d" % [k, groups[k][0], groups[k][1], groups[k][2]])


static func batch_breakdown() -> String:
	## MapBatch's batches by kit scene: batches / draw calls (surfaces) / instances.
	if MapBatch.current == null:
		return ""
	var by := {}
	for k in MapBatch.current._batches:
		var b = MapBatch.current._batches[k]
		if b.items.is_empty():
			continue
		var root: Node = b.items[0][0].root
		var f := root.scene_file_path.get_file() if is_instance_valid(root) else "?"
		var g: Array = by.get(f, [0, 0, 0])
		g[0] += 1
		g[1] += b.mm.mesh.get_surface_count() if b is MapBatch.Batch else 1
		g[2] += b.items.size()
		by[f] = g
	var keys := by.keys()
	keys.sort_custom(func(a, b): return by[a][1] > by[b][1])
	return "\n".join(keys.map(func(k): return "  batch %-36s batches=%3d draws=%3d instances=%3d" % [k, by[k][0], by[k][1], by[k][2]]))
