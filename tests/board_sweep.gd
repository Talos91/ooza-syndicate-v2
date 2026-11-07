extends Node
## Board sweep (hotfix-02319, 0.23.18 live: on two phones N-28 and E-07 showed only the sky online - the camera was refitted
## through the RenderScale SubViewport before it had taken the new window size, after a turn to landscape / fullscreen).
## Windowed only (a scene: the Net autoload exists). For every pooled map (MapPool.battlefield(): N, E and the older maps that
## fill the modes N / E don't offer) it starts the real game on the PHONE profile, lets the scaled path come up, turns the
## window to portrait and back to landscape mid-match (the phones' rotation), and checks that the board is drawn:
##   cam   - the camera's position is finite
##   off   - node centres outside the screen (must be 0)
##   drawn - share of node centres whose 9 x 9 px block changes when the 3D pass is switched off for a frame (sky only):
##           the board is really on screen, not only in the scene (must be >= MIN_DRAWN)
##   fit   - the view the camera holds vs a fit measured now at the window's real size (must be <= MAX_FIT_ERR)
##   path  - the scaled path is up when the scale is under 1 (RenderScale.current)
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/board_sweep.tscn -- --mobile --scale3d=0.75
##       [maps=N-28,E-07] [window=1750x800] [out=<file>]
## Prints one line per map and BOARD SWEEP: PASS / FAIL (exit 1).

const MAIN := "res://main.tscn"
const MIN_DRAWN := 0.8                 # node centres that must change with the 3D off
const PIXEL_DELTA := 0.03              # a mean colour change (max channel) over the patch that counts as "the board is drawn there"
const PATCH := 9                       # px: the block sampled at each node's centre (a lone pixel can match the clouds)
const MAX_FIT_ERR := 0.05              # the held view vs a fresh fit: distance and aim, as a share of the camera distance

var _fails := 0
var _lines: PackedStringArray = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("board_sweep: windowed only")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").begins_with(name + "="):
			return a.trim_prefix("--").substr(name.length() + 1)
	return def


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _size(s: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(s)


func _run() -> void:
	var wh := _arg("window", "1750x800").split("x")
	var land := Vector2i(int(wh[0]), int(wh[1]))
	var only := _arg("maps", "")
	var main_script = load("res://scripts/main.gd")
	var scale := PerfProfile.scale_3d()
	for path in MapPool.battlefield():
		var code: String = path.get_file().substr(0, 4)
		if only != "" and not code in only.split(","):
			continue
		_size(land)
		await _frames(2)
		var m := MapBuilder.load_map(path)
		main_script.relaunch = {"faction": "null", "mode": str(m["modes"][0]), "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.mobile = true
		get_tree().root.add_child(inst)
		var t0 := Time.get_ticks_msec()
		while not bool(inst.get("started")) and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		await _frames(10)
		_size(Vector2i(land.y, land.x))                 # a phone held upright...
		await _frames(6)
		_size(land)                                     # ...turned to landscape mid-match
		await _frames(8)
		await _check(code, inst, scale)
		inst.queue_free()
		await _frames(3)
	var verdict := "PASS" if _fails == 0 else "FAIL (%d map(s))" % _fails
	_lines.append("BOARD SWEEP: %s" % verdict)
	print(_lines[-1])
	var out := _arg("out", "")
	if out != "":
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
	get_tree().quit(0 if _fails == 0 else 1)


func _check(code: String, inst: Node, scale: float) -> void:
	var cam: Camera3D = inst.get("cam")
	var sim = inst.get("sim")
	var vp: Vector2 = inst.get_viewport().get_visible_rect().size
	var pos := cam.global_position
	var finite := is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)
	var path_ok := scale >= 0.999 or RenderScale.current != null
	var off := 0
	var pts: Array[Vector2] = []
	for n in sim.nodes:
		var q := cam.unproject_position(n["pos"])
		if not Rect2(Vector2.ZERO, vp).has_point(q) or cam.is_position_behind(n["pos"]):
			off += 1
		else:
			pts.append(q)
	# the view the camera holds against a fit measured now (main._fit_nodes, the window's real size): a fit made through a
	# stale size (the 0.23.18 bug) holds a camera tens of metres off it
	var fresh: Array = inst.call("_fit_nodes", sim.nodes)
	var held: Array = inst.get("_view_fit")
	var fit_err := 0.0
	if held.size() == 2:
		fit_err = absf(float(held[1]) - float(fresh[1])) / maxf(float(fresh[1]), 1.0) 				+ (held[0] as Vector3).distance_to(fresh[0]) / maxf(float(fresh[1]), 1.0)
	var with3d := await _grab()
	var v3d: Viewport = RenderScale.viewport_3d(inst)
	v3d.disable_3d = true
	var sky := await _grab()
	v3d.disable_3d = false
	var changed := 0
	var img_size := Vector2(with3d.get_size())
	for q in pts:                                    # a PATCH x PATCH block at the node's centre: its mean colour change
		var c := Vector2i((q * img_size / vp).floor())
		var sum := 0.0
		var k := 0
		for dy in range(-PATCH / 2, PATCH / 2 + 1):
			for dx in range(-PATCH / 2, PATCH / 2 + 1):
				var px := (c + Vector2i(dx, dy)).clamp(Vector2i.ZERO, with3d.get_size() - Vector2i.ONE)
				var a := with3d.get_pixelv(px)
				var b := sky.get_pixelv(px)
				sum += maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
				k += 1
		if sum / float(k) > PIXEL_DELTA:
			changed += 1
	var drawn := float(changed) / float(maxi(sim.nodes.size(), 1))
	var ok := finite and path_ok and off == 0 and drawn >= MIN_DRAWN and fit_err <= MAX_FIT_ERR
	if not ok:
		_fails += 1
	var line := "%s %-4s nodes %2d  off %d  drawn %3.0f %%  fit %4.1f %%  cam %s  scale %.2f path %s" % [code, "ok" if ok else "FAIL",
			sim.nodes.size(), off, drawn * 100.0, fit_err * 100.0, "ok" if finite else "NaN", RenderScale.scale_now(), "up" if RenderScale.current != null else "root"]
	_lines.append(line)
	print(line)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
