extends Node
## WORLD COMPLETE LAB shots (a dev tool, not a suite): R-01 STRAIT, lab biome, --craters=2, the default camera (54 deg)
## with fog, the world dressing on (scripts/world_dressing.gd). AI match fast-forwarded to 60 s, Locals prewarmed 60 s:
##   <tag>-game.png        the full composition at the default camera
##   <tag>-zoom.png        the closest pinch zoom on the first crater
##   <tag>-pan-left.png / -pan-right.png   the closest zoom panned to the left / right limits (the side backdrop shows)
##   <tag>-gif-NN.png      16 frames 0.25 s apart at a mid zoom on the first crater (drone, riders, arm, steam)
## and prints the dressing's build log, perf with the dressing shown vs hidden (draws, primitives, frame ms), decals.
## only=game: just the game shot (backdrop A / B comparison, before / after).
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/world_complete_shots.tscn -- \
##       out=<dir> tag=R-01-lab --craters=2 --floor=lab5 [--lab-side=a] [only=game]

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
	var r := {"avg": avg, "p95": ts[int(ts.size() * 0.95)], "draws": draws / n, "prims": prims / n}
	print("PERF %s: frame avg %.2f ms p95 %.2f | draws %d prims %d" % [label, r["avg"], r["p95"], r["draws"], r["prims"]])
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


func _pan(inst: Node, sx: float, k: float) -> void:
	var far: float = inst._view_fit[1]
	var home: Vector3 = inst._view_fit[0]
	inst.cam_dist = far * k
	inst.cam_target = Vector3(home.x + sx * inst._map_half.x * (1.0 - k), home.y, home.z)
	inst._place_camera()


func _home(inst: Node) -> void:
	inst.cam_target = inst._view_fit[0]
	inst.cam_dist = inst._view_fit[1]
	inst._place_camera()


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://world_complete"))
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
	var dr: Node = wl.get_node_or_null("Dressing")
	print("%s pitch %.1f cam_dist %.1f | craters %s | viewport %s" % [tag, float(inst.cam_pitch), float(inst.cam_dist),
			str(lc.craters.map(func(p): return Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))), str(get_viewport().get_visible_rect().size)])
	if dr != null:
		print("DRESSING district ", dr.district, " | ", " | ".join(dr.log_lines))
	if lc.decals != null:
		print("DECALS %d quads" % lc.decals._n)
	await _shot(inst, "%s/%s-game.png" % [out, tag])
	if str(args.get("debug", "")) != "":           # placement check: straight down over each half of the board
		var keep := float(inst.cam_pitch)
		inst.cam_pitch = 89.0
		for sx in [-1.0, 1.0]:
			inst.cam_target = Vector3(sx * 34.0, wl.floor_y, -12.0)
			inst.cam_dist = 62.0
			inst._place_camera()
			await _frames(10)
			await _shot(inst, "%s/%s-top-%s.png" % [out, tag, "L" if sx < 0 else "R"])
		inst.cam_pitch = keep
		_home(inst)
		get_tree().quit()
		return
	if str(args.get("only", "")) == "game":
		print("WORLD COMPLETE SHOTS DONE ", tag)
		get_tree().quit()
		return
	var on := await _perf(tag + " all on", 240)
	if dr != null:
		dr.visible = false
		var off := await _perf(tag + " dressing hidden", 240)
		dr.visible = true
		print("%s ADDED by the dressing meshes: %d draws, %d primitives, %.2f ms avg frame" % [tag, on["draws"] - off["draws"],
				on["prims"] - off["prims"], on["avg"] - off["avg"]])
	if lc.decals != null:
		lc.decals.visible = false
		var off2 := await _perf(tag + " decals hidden", 120)
		lc.decals.visible = true
		print("%s decals: %d draws, %d primitives" % [tag, on["draws"] - off2["draws"], on["prims"] - off2["prims"]])
	_zoom_onto(inst, lc.craters[0], Rules.CAM_ZOOM_MIN)
	await _frames(15)
	await _shot(inst, "%s/%s-zoom.png" % [out, tag])
	if lc.craters.size() > 1:
		_zoom_onto(inst, lc.craters[1], Rules.CAM_ZOOM_MIN)
		await _frames(15)
		await _shot(inst, "%s/%s-zoom2.png" % [out, tag])
	_pan(inst, -1.0, Rules.CAM_ZOOM_MIN)
	await _frames(15)
	await _shot(inst, "%s/%s-pan-left.png" % [out, tag])
	_pan(inst, 1.0, Rules.CAM_ZOOM_MIN)
	await _frames(15)
	await _shot(inst, "%s/%s-pan-right.png" % [out, tag])
	_pan(inst, -1.0, 0.6)
	await _frames(15)
	await _shot(inst, "%s/%s-pan-left-60.png" % [out, tag])
	_zoom_onto(inst, lc.craters[0], 0.5)
	await _frames(15)
	for k in range(16):
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 250:
			await get_tree().process_frame
		await _shot(inst, "%s/%s-gif-%02d.png" % [out, tag, k])
	print("WORLD COMPLETE SHOTS DONE ", tag)
	get_tree().quit()


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""
