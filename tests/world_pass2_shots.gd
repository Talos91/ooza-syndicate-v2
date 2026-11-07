extends Node
## WORLD PASS 2 shots (a dev tool, not a suite): R-01 STRAIT as the game draws it on a landscape phone, lab biome
## (--floor=lab5), --craters=2. An AI match fast-forwarded to 60 s, the Locals' lines prewarmed 60 s, then:
##   <tag>-game.png             the default camera
##   <tag>-zoom.png             the player's closest pinch zoom panned onto the first crater and its lines
##   <tag>-gif-NN.png           16 frames 0.25 s apart at that zoom (the queue moving)
##   <tag>-fall-NN.png          a forced 40-body fall off the longest bridge, frames 0.0 .. 2.4 s (F1 / F2)
## and prints: Locals / lines / CPU ms (the Locals' step, the world sync), draw calls and primitives with the Locals and
## decals shown vs hidden, a 1500-Local stress, the F1 landing check (every body inside its splat's blot) and which share
## of the Locals sits under the new HUD (left 0-13 %, right 86-100 %).
## only=game: just the game shot (backdrop A / B comparison).
## Run WINDOWED, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/world_pass2_shots.tscn -- \
##       out=<dir> tag=R-01-lab5 --craters=2 --floor=lab5 [--lab-side=a] [only=game]

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


func _perf(label: String, n: int, lc: WorldLocals = null, wl: WorldLayer = null) -> Dictionary:
	var ts := []
	var last := Time.get_ticks_usec()
	var draws := 0
	var prims := 0
	var lus := 0
	var wus := 0
	for i in range(n):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append((now - last) / 1000.0)
		last = now
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		if lc != null:
			lus += lc.step_us
		if wl != null:
			wus += wl.sync_us
	ts.sort()
	var avg := 0.0
	for t in ts:
		avg += t
	avg /= ts.size()
	var r := {"avg": avg, "p95": ts[int(ts.size() * 0.95)], "draws": draws / n, "prims": prims / n,
			"locals_ms": lus / 1000.0 / n, "world_ms": wus / 1000.0 / n}
	print("PERF %s: frame avg %.2f ms p95 %.2f | draws %d prims %d | locals step %.3f ms, world sync %.3f ms" % [label,
			r["avg"], r["p95"], r["draws"], r["prims"], r["locals_ms"], r["world_ms"]])
	return r


func _zoom_onto(inst: Node, at: Vector3, k: float) -> void:
	var far: float = inst._view_fit[1]
	var home: Vector3 = inst._view_fit[0]
	var pitch := deg_to_rad(float(inst.cam_pitch))
	var node_y := home.y
	var foot := Vector3(at.x, node_y, at.z + (node_y - at.y) / tan(pitch))
	inst.cam_dist = far * k
	var room := 1.0 - k
	inst.cam_target = Vector3(clampf(foot.x, home.x - inst._map_half.x * room, home.x + inst._map_half.x * room), home.y,
			clampf(foot.z, home.z - inst._map_half.z * room, home.z + inst._map_half.z * room))
	inst._place_camera()


func _home(inst: Node) -> void:
	inst.cam_target = inst._view_fit[0]
	inst.cam_dist = inst._view_fit[1]
	inst._place_camera()


func _hud_share(inst: Node, lc: WorldLocals) -> String:
	## where the Locals and the craters land on screen against the new HUD's side bands
	var cam: Camera3D = inst.get_viewport().get_camera_3d()
	var vp := inst.get_viewport().get_visible_rect().size
	var n := 0
	var left := 0
	var right := 0
	for i in lc.feeds:
		var f: Dictionary = lc.feeds[i]
		for s in f["line"]:
			var at: Array = WorldLocals._along(f["path"], lc._dnow(s))
			var p := Vector3((at[0] as Vector2).x, lc.wl.floor_y, (at[0] as Vector2).y)
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y:
				continue
			n += 1
			if sp.x < vp.x * 0.13:
				left += 1
			elif sp.x > vp.x * 0.86:
				right += 1
	var cs := []
	for c in lc.craters:
		var sp2 := cam.unproject_position(c)
		cs.append("(%d%%, %d%%)" % [int(100 * sp2.x / vp.x), int(100 * sp2.y / vp.y)])
	return "on screen %d Locals: %d under the left HUD band, %d under the right; craters at %s" % [n, left, right, ", ".join(cs)]


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://world_pass2"))
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
	lc.prewarm(60.0)
	await _frames(20)
	print("%s layout %d floor %s lab5 %s pitch %.1f cam_dist %.1f | craters %s | fed tubes %d of %d" % [tag, lc.layout, wl.floor_kind,
			str(wl.floor_lab5), float(inst.cam_pitch), float(inst.cam_dist),
			str(lc.craters.map(func(p): return Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))), lc.feeds.size(), wl._tubes.size()])
	await _shot(inst, "%s/%s-game.png" % [out, tag])
	print("HUD: ", _hud_share(inst, lc))
	if str(args.get("only", "")) == "game":
		print("WORLD PASS 2 SHOTS DONE ", tag)
		get_tree().quit()
		return
	# perf: steady state, then the Locals hidden, then the decals hidden
	var on := await _perf(tag + " all on", 240, lc, wl)
	print("%s steady: locals %d (queued %d), spawned %d, admitted %d, instance writes %d, decals %d quads | lines [node, n, cap, rate/s] %s" % [
			tag, lc.count(), lc.queued(), lc.spawned, lc.admitted, lc.writes, lc.decals._n if lc.decals else 0, str(lc.lines())])
	var lmi: MultiMeshInstance3D = null
	for c in lc.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh.instance_count == WorldLocals.LOCALS_MAX:
			lmi = c
	lmi.visible = false
	var off := await _perf(tag + " locals hidden", 120)
	lmi.visible = true
	print("%s ADDED by the Locals: %d draws, %d primitives (tris), %.2f ms avg frame" % [tag, on["draws"] - off["draws"],
			on["prims"] - off["prims"], on["avg"] - off["avg"]])
	if lc.decals != null:
		lc.decals.visible = false
		var off2 := await _perf(tag + " decals hidden", 120)
		lc.decals.visible = true
		print("%s ADDED by the decals: %d draws, %d primitives, %.2f ms avg frame" % [tag, on["draws"] - off2["draws"],
				on["prims"] - off2["prims"], on["avg"] - off2["avg"]])
	# closest zoom onto the first crater, then the queue GIF there
	_zoom_onto(inst, lc.craters[0], Rules.CAM_ZOOM_MIN)
	await _frames(20)
	await _shot(inst, "%s/%s-zoom.png" % [out, tag])
	print("HUD (zoom): ", _hud_share(inst, lc))
	# a debug close-up (camera 16 m from the first crater, same pitch): the Locals' shape, rise, hop, walk, line
	inst.cam_target = Vector3((lc.craters[0] as Vector3).x + 3.0, wl.floor_y + 0.5, (lc.craters[0] as Vector3).z - 2.0)
	inst.cam_dist = 16.0
	inst._place_camera()
	await _frames(20)
	await _shot(inst, "%s/%s-closeup.png" % [out, tag])
	_zoom_onto(inst, lc.craters[0], Rules.CAM_ZOOM_MIN)
	await _frames(10)
	for k in range(16):
		var t0 := lc._t
		while lc._t - t0 < 0.25:
			await get_tree().process_frame
		await _shot(inst, "%s/%s-gif-%02d.png" % [out, tag, k])
	# F1 / F2: a forced 40-body fall off the longest bridge, at a mid zoom on it
	var best := -1
	var bl := 0.0
	for i in range(sim.edges.size()):
		if not sim.edges[i]["plaza"] and float(sim.edges[i]["geo"]["L"]) > bl:
			bl = float(sim.edges[i]["geo"]["L"])
			best = i
	var g: Dictionary = sim.edges[best]["geo"]
	var a := Vector3(g["A"][0], (sim.nodes[sim.edges[best]["a"]]["pos"] as Vector3).y, g["A"][1])
	var b := Vector3(g["B"][0], (sim.nodes[sim.edges[best]["b"]]["pos"] as Vector3).y, g["B"][1])
	var mid := a.lerp(b, 0.5)
	_zoom_onto(inst, Vector3(mid.x, wl.floor_y * 0.5, mid.z), 0.55)
	await _frames(15)
	var pts := []
	for k in range(12):
		pts.append(a.lerp(b, 0.3 + 0.4 * (k + 0.5) / 12.0) + Vector3(0, 0.3, 0))
	wl.log_landings = true
	var ev := {"type": "fall", "seat": "B", "faction": "ember", "pts": pts, "units": 40.0 * Rules.SCALE, "pour": false}
	inst.fx.handle(ev)
	wl.handle(ev)
	var cam: Camera3D = inst.get_viewport().get_camera_3d()
	var t_fall: float = sim.time
	var sizes := []
	var probe: MeshInstance3D = null
	for c in inst.fx.get_children():
		if c is MeshInstance3D and c.has_meta("seat"):
			probe = c
	for k in range(9):
		while sim.time - t_fall < 0.3 * k:
			await get_tree().process_frame
		# F2 probe: one falling body's on-screen size (a 1 m segment across the screen at it: perspective only, its
		# scale stays)
		if is_instance_valid(probe):
			var p: Vector3 = probe.global_position
			var px := cam.unproject_position(p).distance_to(cam.unproject_position(p + cam.global_basis.x * 1.0))
			sizes.append("t %.1f s: y %.1f, scale %.2f, %.1f px/m" % [sim.time - t_fall, p.y, probe.scale.x, px])
		await _shot(inst, "%s/%s-fall-%02d.png" % [out, tag, k])
	print("F2 body size: ", " | ".join(sizes))
	var worst := 0.0
	for L in wl.landing_log:
		var at: Vector3 = L[0]
		var c3: Vector3 = L[1]
		var edge := 0.62 * float(L[2])
		worst = maxf(worst, Vector2(at.x - c3.x, at.z - c3.z).length() - edge)
	print("F1: %d bodies landed, %d splats made; worst landing vs its splat's blot edge %.2f m (<= 0: inside)" % [
			wl.landing_log.size(), wl.splats_made, worst])
	_home(inst)
	await _frames(5)
	# stress: every line uncapped until the pool (1500) is full - CPU / GPU with the Locals cap reached
	for i in lc.feeds:
		(lc.feeds[i] as Dictionary)["cap"] = 400
		(lc.feeds[i] as Dictionary)["next_spawn"] = 0.0
	var guard := 0
	while lc.count() < WorldLocals.LOCALS_MAX - 5 and guard < 4000:
		lc.step(0.05, false)
		for i in lc.feeds:
			(lc.feeds[i] as Dictionary)["next_spawn"] = 0.0
		guard += 1
	await _frames(10)
	await _perf(tag + " STRESS %d Locals" % lc.count(), 180, lc, wl)
	print("WORLD PASS 2 SHOTS DONE ", tag)
	get_tree().quit()


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""
