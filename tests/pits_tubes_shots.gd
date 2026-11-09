extends Node
## PITS / TUBES shots (a dev tool, not a suite; spec 05 Handoff/PITS-TUBES-2026-11.md): R-01 STRAIT as the game draws it
## on a landscape phone, 4 pits (the default). Nobody plays (AIs off); the states are forced:
##   a-start-game.png      ~7 s after the match start: each pit's Locals column (R6)
##   b-t2-build-foot.png   seat A's home vat T1 -> T2 half built: the new tube EMPTY (low camera on the column base)
##   b-t2-foot.png         after T2: 2 tubes full, sockets + doors (low camera)   b-t2-game.png (default camera)
##   c-t3-foot.png         after T3: 4 tubes                                     c-t3-game.png
##   d-mixed-pit.png       a neutral column next to the same pit given to seat B at T3: two players' tubes into one pit
## v2 (Daniele 2026-11-09):
##   e-build-1..4.png      the T1 -> T2 tube BUILDING as a hologram at 15 / 40 / 70 / 95 % (camera over the whole new run)
##   f-fan-pit.png         every column of seat A's pit at T3 (the full fan, all slots) close over that pit
##   z-top-down.png        the whole map straight down (pit symmetry)
## and prints the tube counts, the base / tube triangle counts and draws with the tubes shown vs hidden.
## Run WINDOWED, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/pits_tubes_shots.tscn -- \
##       out=<dir> --floor=lab5

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


func _shot(inst: Node, file: String) -> void:
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""


func _home(inst: Node) -> void:
	inst.cam_target = inst._view_fit[0]
	inst.cam_dist = inst._view_fit[1]
	inst._place_camera()


func _low_shot(inst: Node, look: Vector3, toward: Vector3, dist: float, file: String) -> void:
	## a dev camera low over the floor (the game camera sees the floor only between the decks)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 400.0
	inst.add_child(cam)
	var back := Vector3(look.x - toward.x, 0, look.z - toward.z)
	back = back.normalized() if back.length() > 0.01 else Vector3(0, 0, 1)
	var side := back.cross(Vector3.UP)
	cam.global_position = look + (back * 0.8 + side * 0.6).normalized() * dist + Vector3(0, dist * 0.55, 0)
	cam.look_at(look + Vector3(0, 0.6, 0), Vector3.UP)
	var was := inst.get_viewport().get_camera_3d()
	cam.make_current()
	await _frames(2)
	await _shot(inst, file)
	if was:
		was.make_current()
	cam.queue_free()


func _wait_world(wl: WorldLayer, s: float) -> void:
	var t0 := wl._t
	while wl._t - t0 < s:
		await get_tree().process_frame


func _draws(n: int) -> Array:
	var d := 0
	var p := 0
	for i in range(n):
		await get_tree().process_frame
		d += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		p += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return [d / n, p / n]


func _upgrade(inst: Node, sim: Sim, wl: WorldLayer, id: int, file_mid: String, build_out := "") -> void:
	var n: Dictionary = sim.nodes[id]
	n["units"] = 140.0
	var ok := sim.upgrade(id, "A")
	print("PITS upgrade %d -> started %s" % [int(n["tier"]), ok])
	var shot := false
	var frames := [0.15, 0.4, 0.7, 0.95] if build_out != "" else []
	var tb := _tube(wl, id)
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	var pit := wl.pipes.pit_of(tb)
	while n["build_kind"] != "":
		if not shot and Sim.build_progress(n) > 0.5 and file_mid != "":
			shot = true
			await _low_shot(inst, foot, pit, 11.0, file_mid)
		if not frames.is_empty() and Sim.build_progress(n) >= float(frames[0]):
			var k := 5 - frames.size()
			frames.pop_front()
			var mid := foot.lerp(pit, 0.45)
			await _low_shot(inst, mid, pit, 8.0 + 0.55 * foot.distance_to(pit), "%s/e-build-%d.png" % [build_out, k])
			print("PITS build frame %d at %.2f" % [k, Sim.build_progress(n)])
		await get_tree().process_frame
	await _wait_world(wl, WorldTubes.FILL_S + 0.8)


func _tube(wl: WorldLayer, id: int) -> Dictionary:
	for t in wl._tubes:
		if int(t["id"]) == id:
			return t
	return {}


func _count(wl: WorldLayer, id: int) -> int:
	for i in wl.pipes.cols:
		if int(wl._tubes[i]["id"]) == id:
			return int(wl.pipes.cols[i]["n"])
	return -1


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://pits_tubes"))
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file("R-01")}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(5)
	inst.ais.clear()                                  # nobody plays: the states are forced
	var sim: Sim = inst.sim
	var wl: WorldLayer = inst.world_layer
	var lc: WorldLocals = wl.locals
	await _wait_world(wl, 7.0)
	_home(inst)
	await _frames(2)
	print("PITS layout %d pits %s | feeds %d (marches %d) | locals %d" % [lc.layout, str(lc.craters.map(func(p): return Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))),
			lc.feeds.size(), lc.feeds.keys().filter(func(k): return int(k) >= WorldLocals.MARCH_KEY).size(), lc.count()])
	await _shot(inst, "%s/a-start-game.png" % out)
	for k in range(lc.craters.size()):               # each pit's match-start column, low over the floor
		var cp: Vector3 = lc.craters[k]
		for fk in lc.feeds:
			var f: Dictionary = lc.feeds[fk]
			if int(f["crater"]) == k and f.has("march"):
				var t0: Dictionary = wl._tubes[int(f["tube"])]
				var ft := Vector3(t0["x"], wl.floor_y, t0["z"])
				await _low_shot(inst, cp.lerp(ft, 0.5), cp, 14.0 + 0.25 * cp.distance_to(ft), "%s/a-start-pit%d.png" % [out, k])
				break
	var cnt := {}
	for i in wl.pipes.cols:
		cnt[int(wl._tubes[i]["id"])] = int(wl.pipes.cols[i]["n"])
	print("PITS start tubes per node %s | base tris %d | tube mesh tris %d (all %d slots)" % [str(cnt),
			WorldTubes.column_base_mesh().get_faces().size() / 3, wl.pipes.tris, wl.pipes._slots])
	var on := await _draws(30)
	(wl.pipes.get_child(0) as Node3D).visible = false
	var off := await _draws(30)
	(wl.pipes.get_child(0) as Node3D).visible = true
	print("PITS tubes drawn: +%d draws, +%d prims" % [on[0] - off[0], on[1] - off[1]])
	var id: int = sim.homes.get("A", -1)
	var tb := _tube(wl, id)
	if tb.is_empty() or not tb.get("ent", false):
		print("PITS seat A's home has no column base")
		get_tree().quit(1)
		return
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	await _low_shot(inst, foot, wl.pipes.pit_of(tb), 11.0, "%s/a-home-foot.png" % out)
	sim.nodes[id]["tier"] = 1
	await _upgrade(inst, sim, wl, id, "%s/b-t2-build-foot.png" % out, out)
	print("PITS after T2: tier %d tubes %d" % [int(sim.nodes[id]["tier"]), _count(wl, id)])
	await _low_shot(inst, foot, wl.pipes.pit_of(tb), 11.0, "%s/b-t2-foot.png" % out)
	_home(inst)
	await _frames(2)
	await _shot(inst, "%s/b-t2-game.png" % out)
	await _upgrade(inst, sim, wl, id, "")
	print("PITS after T3: tier %d tubes %d" % [int(sim.nodes[id]["tier"]), _count(wl, id)])
	await _low_shot(inst, foot, wl.pipes.pit_of(tb), 12.0, "%s/c-t3-foot.png" % out)
	_home(inst)
	await _frames(2)
	await _shot(inst, "%s/c-t3-game.png" % out)
	# d: another column into the same pit, given to seat B at T3 (its start tier counts: a neutral T1 -> 0 + 1 + 2)
	var pit := wl.pipes.pit_of(tb)
	var other := -1
	var od := INF
	for i in wl.pipes.cols:
		var t2: Dictionary = wl._tubes[i]
		if int(t2["id"]) == id or wl.pipes.pit_of(t2) != pit:
			continue
		var d := Vector2(float(t2["x"]) - pit.x, float(t2["z"]) - pit.z).length()
		if d < od:
			od = d
			other = int(t2["id"])
	if other >= 0:
		var n2: Dictionary = sim.nodes[other]
		n2["owner"] = "B"
		n2["structure"] = "vat"
		n2["tier"] = 3
		await _wait_world(wl, WorldTubes.FILL_S + 3.0)
		print("PITS mixed: node %d -> B tier 3, tubes %d | pit tubes %s | pit colours %s" % [other, _count(wl, other),
				str(wl.pipes.pit_strength(lc.craters.find(pit))), str(wl.pipes.pit_cols)])
		var t3 := _tube(wl, other)
		var mid := pit.lerp(Vector3(t3["x"], wl.floor_y, t3["z"]), 0.25)
		await _low_shot(inst, mid, Vector3(foot.x, wl.floor_y, foot.z), 17.0, "%s/d-mixed-pit.png" % out)
		_home(inst)
		await _frames(2)
		await _shot(inst, "%s/d-mixed-game.png" % out)
	else:
		print("PITS no second column feeds that pit")
	# f: the full fan - every column of that pit at T3 (seat A), all slots full
	for i in wl.pipes.cols:
		var t4: Dictionary = wl._tubes[i]
		if wl.pipes.pit_of(t4) == pit and int(t4["id"]) != other:
			var n4: Dictionary = sim.nodes[t4["id"]]
			n4["owner"] = "A"
			n4["structure"] = "vat"
			n4["tier"] = 3
	await _wait_world(wl, WorldTubes.FILL_S + 3.0)
	var away := Vector3(foot.x, wl.floor_y, foot.z)
	var bc2 := lc.board_bounds().get_center()
	away = Vector3(bc2.x, wl.floor_y, bc2.y)
	await _low_shot(inst, pit.lerp(away, 0.18), away, 22.0, "%s/f-fan-pit.png" % out)
	# z: the whole map straight down
	var top := Camera3D.new()
	top.fov = 50.0
	top.far = 600.0
	inst.add_child(top)
	var bb := lc.board_bounds()
	var ext := 0.0
	for c in lc.craters:
		ext = maxf(ext, maxf(absf((c as Vector3).x - bb.get_center().x) * 375.0 / 812.0, absf((c as Vector3).z - bb.get_center().y)) + WorldLocals.RING_R + 12.0)
	top.global_position = Vector3(bb.get_center().x, wl.floor_y + ext / tan(deg_to_rad(25.0)), bb.get_center().y)
	top.look_at(Vector3(bb.get_center().x, wl.floor_y, bb.get_center().y), Vector3(0, 0, -1))
	top.make_current()
	await _frames(3)
	await _shot(inst, "%s/z-top-down.png" % out)
	get_tree().quit(0)
