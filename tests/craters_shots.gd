extends Node
## CRATERS / LOCALS shots (a dev tool, not a suite): R-01 as the game draws it on a landscape phone, one crater layout per
## run (--craters=1|2|4 is read by WorldLocals at setup). An AI match fast-forwarded to 60 s, the march prewarmed 45 s, then:
##   <tag>-game.png        the default camera (fog on)
##   <tag>-zoom.png        the player's closest pinch zoom (Rules.CAM_ZOOM_MIN) panned onto the first crater
##   <tag>-debug-top.png   a top-down debug view from under the decks: craters (white), layout targets (yellow), paths
##                         (cyan), doors + queue lines (white), platform / bridge outlines (violet), floor the default
##                         camera sees (green dots) / does not (red)
##   <tag>-gif-NN.png      16 frames 0.25 s apart at the default camera (tools turn them into a GIF)
## and prints the counters and a perf line (desktop window frame times; draw calls / primitives with the Locals + rings
## shown vs hidden).
## Run WINDOWED, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/craters_shots.tscn -- \
##       out=<dir> tag=R-01-c2 --craters=2 --floor=labpic

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


func _perf(label: String, n: int) -> Dictionary:
	var ts := []
	var last := Time.get_ticks_usec()
	var draws := 0
	var prims := 0
	for i in range(n):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append((now - last) / 1000.0)
		last = now
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	ts.sort()
	var avg := 0.0
	for t in ts:
		avg += t
	avg /= ts.size()
	var r := {"avg": avg, "p95": ts[int(ts.size() * 0.95)], "max": ts[-1], "draws": draws / n, "prims": prims / n}
	print("PERF %s: frame avg %.2f ms p95 %.2f max %.2f | draws %d prims %d" % [label, r["avg"], r["p95"], r["max"], r["draws"], r["prims"]])
	return r


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://craters_shots"))
	var tag := str(args.get("tag", "R-01"))
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file("R-01")}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
	while sim.time < 60.0 and not sim.over:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	sim.fx_events.clear()
	await _frames(20)
	var wl: WorldLayer = inst.world_layer
	var lc: WorldLocals = wl.locals
	lc.prewarm(45.0)
	await _frames(20)
	print("%s layout %d floor %s%s pitch %.1f | craters %s vis %s | fed tubes %d of %d" % [tag, lc.layout, wl.floor_kind,
			" (labpic)" if wl.floor_pic else "", float(inst.cam_pitch), str(lc.craters.map(func(p): return Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))),
			str(lc.crater_vis.map(func(v): return snappedf(v, 0.01))), lc.feeds.size(), wl._tubes.size()])
	await _shot(inst, "%s/%s-game.png" % [out, tag])
	# perf: steady state, then the Locals + rings hidden for the difference
	var on := await _perf(tag + " locals on", 180)
	print("%s steady: locals %d (queued %d), spawned %d, admitted %d, locals step %.3f ms, world sync %.3f ms" % [tag, lc.count(),
			lc.queued(), lc.spawned, lc.admitted, lc.step_us / 1000.0, wl.sync_us / 1000.0])
	for c in lc.get_children():
		if c is MultiMeshInstance3D:
			c.visible = false
	var off := await _perf(tag + " locals+rings hidden", 120)
	for c in lc.get_children():
		if c is MultiMeshInstance3D:
			c.visible = true
	print("%s ADDED by rings + Locals: %d draws, %d primitives (tris), %.2f ms avg frame" % [tag, on["draws"] - off["draws"],
			on["prims"] - off["prims"], on["avg"] - off["avg"]])
	# GIF frames, 0.25 s of world time apart
	for k in range(16):
		var t0 := lc._t
		while lc._t - t0 < 0.25:
			await get_tree().process_frame
		await _shot(inst, "%s/%s-gif-%02d.png" % [out, tag, k])
	# closest zoom onto the first crater
	var far: float = inst._view_fit[1]
	var home: Vector3 = inst._view_fit[0]
	var pitch := deg_to_rad(float(inst.cam_pitch))
	var cp: Vector3 = lc.craters[0]
	var node_y := home.y
	var foot := Vector3(cp.x, node_y, cp.z + (node_y - wl.floor_y) / tan(pitch))
	inst.cam_dist = far * Rules.CAM_ZOOM_MIN
	var room := 1.0 - Rules.CAM_ZOOM_MIN
	inst.cam_target = Vector3(clampf(foot.x, home.x - inst._map_half.x * room, home.x + inst._map_half.x * room), home.y,
			clampf(foot.z, home.z - inst._map_half.z * room, home.z + inst._map_half.z * room))
	inst._place_camera()
	await _frames(20)
	await _shot(inst, "%s/%s-zoom.png" % [out, tag])
	inst.cam_target = home
	inst.cam_dist = far
	inst._place_camera()
	await _frames(5)
	# top-down debug from under the decks (the mist sheet is 7 m above the floor: the camera sits under it)
	var game_cam := inst.get_viewport().get_camera_3d()
	lc.debug_overlay(true, game_cam)
	var b := lc.board_bounds()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(b.size.y + 50.0, (b.size.x + 50.0) * 375.0 / 812.0)
	cam.near = 0.05
	cam.far = 40.0
	inst.add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(b.get_center().x, wl.floor_y + 6.0, b.get_center().y))
	cam.current = true
	var hidden := []
	for c in inst.get_children():
		if c is CanvasLayer and c.visible:
			c.visible = false
			hidden.append(c)
	for i in range(10):                              # the game may re-take the current camera: hold ours
		cam.make_current()
		await get_tree().process_frame
	await _shot(inst, "%s/%s-debug-top.png" % [out, tag])
	print("CRATERS SHOTS DONE ", tag)
	get_tree().quit()


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""
