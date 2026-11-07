extends Node
## VAT COLUMN shots + cost (a dev tool, not a suite): R-01 STRAIT as the game draws it on a landscape phone (lab floor,
## craters 2). Seat A's home vat goes T1 -> T2, then T2 -> T3; for each, frames over the fill (the module out of the pit,
## the blueprint filling, the dock) at the default camera and zoomed onto the column, and prints frame times idle vs
## during the upgrade (the blueprint cost), plus the sim's production while paused.
## Run WINDOWED, off-screen and silent (add --mobile for the phone path's low detail):
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/vat_column_shots.tscn -- \
##       out=<dir> --craters=2 --floor=lab5 [--mobile]

const MAIN := "res://main.tscn"
const MARKS := [0.0, 0.08, 0.2, 0.4, 0.6, 0.8, 0.95]


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


func _perf(label: String, n: int) -> float:
	var ts := []
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := 0.0
	var cpu := 0.0
	var last := Time.get_ticks_usec()
	for i in range(n):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	print("PERF %s: render GPU %.3f ms, render CPU %.3f ms per frame" % [label, gpu / n, cpu / n])
	ts.sort()
	var avg := 0.0
	for t in ts:
		avg += t
	avg /= ts.size()
	print("PERF %s: frame avg %.2f ms p95 %.2f max %.2f (%d frames)" % [label, avg, ts[int(ts.size() * 0.95)], ts[-1], n])
	return avg


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


func _foot_shot(inst: Node, wl: WorldLayer, id: int, file: String) -> void:
	## a dev camera low over the floor, looking at the tube's foot and its crater (the game camera sees it only
	## between platforms): the doors, the module out of the pit, the dock
	var tb: Dictionary = {}
	for t in wl._tubes:
		if t["id"] == id:
			tb = t
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	var pit: Vector3 = wl.pipes.pit_of(tb)
	var mid := foot.lerp(pit, 0.4)
	var side := (pit - foot).normalized().cross(Vector3.UP)
	var cam := Camera3D.new()
	cam.fov = 50.0
	inst.add_child(cam)
	cam.global_position = mid + side * 13.0 + Vector3(0, 6.5, 0)
	cam.look_at(mid + Vector3(0, 1.0, 0), Vector3.UP)
	var was := inst.get_viewport().get_camera_3d()
	cam.make_current()
	await _frames(2)
	await _shot(inst, file)
	if was:
		was.make_current()
	cam.queue_free()


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://vat_column"))
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file("R-01")}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(20)
	inst.ais.clear()                                  # nobody else acts: the column alone
	var sim: Sim = inst.sim
	var wl: WorldLayer = inst.world_layer
	var col: VatColumn = wl.column
	# seat A's vat with an entrance (a common tube)
	var id := -1
	for tb in wl._tubes:
		var n: Dictionary = sim.nodes[tb["id"]]
		if tb.get("ent", false) and n["owner"] == "A" and n["structure"] == "vat":
			id = tb["id"]
			break
	if id < 0:
		print("VAT_COLUMN no seat-A vat with an entrance on this map")
		get_tree().quit(1)
		return
	var n: Dictionary = sim.nodes[id]
	n["tier"] = 1
	await _frames(10)
	_home(inst)
	await _frames(30)
	await _foot_shot(inst, wl, id, "%s/T1-foot-before.png" % out)
	var idle := await _perf("idle (no upgrade)", 240)
	var at: Vector3 = n["pos"]
	for step in [[1, 2], [2, 3]]:
		var tag := "T%d-T%d" % step
		n["units"] = 140.0
		var ok := sim.upgrade(id, "A")
		print("VAT_COLUMN %s upgrade started %s | paused %s | production %.3f/s | units %.1f" % [tag, ok, Sim.vat_paused(n),
				sim.production(n), n["units"]])
		var u0: float = n["units"]
		var shot_i := 0
		var perf_done := false
		var up_card := false
		while n["build_kind"] != "":
			var p := Sim.build_progress(n)
			if shot_i < MARKS.size() and p >= MARKS[shot_i]:
				await _frames(2)
				_home(inst)
				await _frames(2)
				await _shot(inst, "%s/%s-game-%02d.png" % [out, tag, int(MARKS[shot_i] * 100)])
				_zoom_onto(inst, at, 0.22)
				await _frames(2)
				await _shot(inst, "%s/%s-zoom-%02d.png" % [out, tag, int(MARKS[shot_i] * 100)])
				await _foot_shot(inst, wl, id, "%s/%s-foot-%02d.png" % [out, tag, int(MARKS[shot_i] * 100)])
				_home(inst)
				shot_i += 1
			if p > 0.6 and not up_card:                  # the compact inspector card while paused
				up_card = true
				_home(inst)
				inst.hud.inspect(id, inst.get_viewport().get_camera_3d())
				await _frames(3)
				await _shot(inst, "%s/%s-card-paused.png" % [out, tag])
				print("VAT_COLUMN %s card: %s | badge clock %s" % [tag, inst.hud.inspector_label.text, str(Sim.build_progress(n))])
				inst.hud.close_inspector()
			if not perf_done and p > 0.25 and step[0] == 1:
				perf_done = true
				var busy := await _perf("upgrade (blueprint + module shown)", 120)
				print("VAT_COLUMN blueprint cost %+.2f ms/frame (avg, desktop GPU)" % (busy - idle))
			await get_tree().process_frame
		print("VAT_COLUMN %s fill end: tier %d | units %.1f (were %.1f: no production while paused) | production %.3f/s" % [tag,
				n["tier"], n["units"], u0, sim.production(n)])
		for k in range(4):
			await _frames(6)
			_zoom_onto(inst, at, 0.22)
			await _frames(1)
			await _shot(inst, "%s/%s-zoom-dock-%d.png" % [out, tag, k])
			await _foot_shot(inst, wl, id, "%s/%s-foot-dock-%d.png" % [out, tag, k])
		await _frames(30)
		_home(inst)
		await _frames(2)
		await _shot(inst, "%s/%s-game-after.png" % [out, tag])
		_zoom_onto(inst, at, 0.22)
		await _frames(2)
		await _shot(inst, "%s/%s-zoom-after.png" % [out, tag])
		await _foot_shot(inst, wl, id, "%s/%s-foot-after.png" % [out, tag])
	print("VAT_COLUMN started %d docked %d cancelled %d" % [col.started, col.docked, col.cancelled])
	get_tree().quit(0)
