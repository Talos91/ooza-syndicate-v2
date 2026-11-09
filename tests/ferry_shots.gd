extends Node
## FERRY shot sequence (demo-rules-pass, a dev tool): R-01's 3-lane ferry as the game draws it - a frame every `dt` s from
## just before the hull leaves a lane until it sits on the next one, with a line of A's walking onto the lane. Run WINDOWED:
##   Godot --path . --resolution 1280x592 --audio-driver Dummy --position -6000,-6000 res://tests/ferry_shots.tscn -- --test out=<dir>
## Prints the ferry's screen box (for cropping) and the sim's lane / phase at each frame.

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://ferry_shots"))
	var code := str(args.get("map", "R-01"))
	var step := float(args.get("dt", "0.2"))
	DirAccess.make_dir_recursive_absolute(out)
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(30)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var g: String = sim._ferry_groups.keys()[0]
	var slot := sim.ferry3_slot(g)
	print("ferry group %s slot %s seq %s" % [g, slot, sim._ferry_groups[g]["seq"]])
	var cam := inst.get_viewport().get_camera_3d()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for pos in sim._ferry_groups[g]["decks"]:
		var ei: int = sim._ferry_groups[g]["decks"][pos]
		for nid in [sim.edges[ei]["a"], sim.edges[ei]["b"]]:
			var sp := cam.unproject_position(sim.nodes[nid]["pos"])
			lo = lo.min(sp)
			hi = hi.max(sp)
	var prv: Node = null
	for nd in inst.find_children("*", "", true, false):
		if nd.get_script() != null and str(nd.get_script().resource_path).ends_with("proto_relay_view.gd"):
			prv = nd
	if prv != null:
		for parts in prv._plain_ferry:
			var v3: Node3D = parts.get("v3")
			print("FERRY_PART edge %d v3 %s vis %s in_tree %s pos %s scale %s rails %d" % [parts["edge"], v3.name if v3 else "-",
					v3.is_visible_in_tree() if v3 else false, v3.is_inside_tree() if v3 else false, v3.global_position if v3 else Vector3.ZERO,
					v3.scale if v3 else Vector3.ZERO, (parts["rails"] as Array).size()])
			if v3:
				for mi in v3.find_children("*", "MeshInstance3D", true, false):
					var m3 := mi as MeshInstance3D
					print("   mesh %s vis %s aabb %s global %s layers %d" % [m3.name, m3.is_visible_in_tree(), m3.get_aabb(), m3.global_position, m3.layers])
	else:
		print("FERRY_PART no proto_relay_view")
	print("FERRY_BOX %d %d %d %d" % [int(lo.x), int(lo.y), int(hi.x), int(hi.y)])
	# a line of A's onto lane 1 (deck 8 -> 9): node 8 is A's with 60 shown
	var lane1: int = sim._ferry_groups[g]["decks"].get(1, -1)
	var a_n: int = int(sim.edges[lane1]["a"]) if lane1 >= 0 else -1
	var b_n: int = int(sim.edges[lane1]["b"]) if lane1 >= 0 else -1
	# jump the clock to 1.5 s before the hull leaves lane 1 the first time (seq index of 1)
	var seq: Array = sim._ferry_groups[g]["seq"]
	var k := seq.find(1)
	var t_leave: float = float(slot["slot"]) * float(k) + float(slot["open"])
	sim.time = t_leave - 4.0
	if a_n >= 0:
		sim.nodes[a_n]["owner"] = "A"
		sim.nodes[a_n]["units"] = 60.0 * Rules.SCALE
		MapBuilder.apply_owner(inst.vis[a_n]["parts"], "A")
		sim.send(a_n, b_n, 1.0)
	var i := 0
	var t_end: float = t_leave + float(slot["move"]) + 1.5
	var next_shot: float = t_leave - 1.5
	while sim.time < t_end:
		await get_tree().process_frame
		if sim.time >= next_shot:
			await RenderingServer.frame_post_draw
			var L := sim.ferry3_lane(g)
			var file := "%s/%s-ferry-%02d.png" % [out, code, i]
			inst.get_viewport().get_texture().get_image().save_png(file)
			print("shot %s t-leave %+.2f lane at %d from %d to %d moving %s left %.2f" % [file.get_file(), sim.time - t_leave, L["at"], L["from"], L["to"], L["moving"], L["left"]])
			i += 1
			next_shot += step
	print("FERRY SHOTS DONE")
	get_tree().quit()
