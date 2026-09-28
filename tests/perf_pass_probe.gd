extends Node
## Perf pass probe (2026-09-28): the frame cost of a busy BRAWL board and of the Last Stand, per view. A windowed scene:
##   timeout 240 Godot --fixed-fps 45 --path . tests/perf_pass_probe.tscn -- --phase=busy|ls [--secs=10] [--shot=<png>]
##       [--probe-map=M-57-relay-quarry] [--level=phone|full|low] [--probe-window=1600x900] [--shadow-mode=0|1|2|off]
## Rules.PERF_CHECK_MAP, every seat the Standard AI, seed 7, PHONE profile at 1266x585 (as tests/perf_check.tscn);
## busy: fast-forwarded to Rules.PERF_CHECK_FF; ls: to just after the first Last Stand wave (its camera zoom included).
## "scripts" is the time from the first _process of a frame to the last (every view, the Sim and the AI; not the
## renderer). --fixed-fps makes every frame the same step, so two builds draw the same board frame by frame (a screenshot pair at
## --shot, taken on frame SHOT_FRAME, compares the looks); the frame cap and vsync are lifted so the frame time is the
## cost. Prints the frame time and the scripts' time (median / p95 / max), the draw calls / primitives /
## objects (max), and each view's share (PerfProfile.lap: mean and worst ms per frame). Headless: SKIP.

const SHOT_FRAME := 240
const SKIP_FRAMES := 30

var main: Node3D
var phase := "busy"
var secs := 10.0
var shot := ""
var map := ""                  # --map=<code>: another map (default Rules.PERF_CHECK_MAP)
var level := "phone"           # --level=phone|full|low: the graphics profile
var size := Vector2i(1266, 585)
var shadow_mode := -1          # --shadow-mode=0|1|2 (experiment: the sun's DirectionalLight3D.directional_shadow_mode)
var frames := 0
var t := 0.0
var rows: Array = []           # [frame ms, scripts ms, draw calls, primitives, objects]
var per_frame := {}            # section -> [sum of per-frame us, worst frame us]
var _last_us := 0
var _tail_us := 0               # set by _Tail, the last _process of the frame
var _head_us := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.substr(8)
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--probe-map="):
			map = a.substr(12)
		elif a.begins_with("--level="):
			level = a.substr(8)
		elif a.begins_with("--probe-window="):
			size = Vector2i(int(a.substr(15).get_slice("x", 0)), int(a.substr(15).get_slice("x", 1)))
		elif a.begins_with("--shadow-mode="):
			shadow_mode = -2 if a.substr(14) == "off" else int(a.substr(14))
	if DisplayServer.get_name() == "headless":
		print("SKIP perf_pass_probe: needs a window")
		get_tree().quit(0)
		return
	process_priority = -1000                         # first: every script's _process runs between this and _Tail
	var tail := _Tail.new()
	tail.probe = self
	tail.process_priority = 1000
	add_child(tail)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	PerfProfile.force_level(level)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", Rules.PERF_CHECK_MAP if map == "" else "res://maps4/%s.json" % map)
	main.set("demo", true)
	main.set("ai_level", "Standard")
	main.set("ff_to", Rules.PERF_CHECK_FF if phase == "busy" else Rules.LAST_STAND_TIME + 2.0)
	main.set("seed_value", 7)
	main.set("mobile", level != "full")
	add_child(main)


func _process(_dt: float) -> void:
	if main == null or not bool(main.get("started")):
		return
	if shadow_mode >= 0 and main.get("sun") != null:
		(main.get("sun") as DirectionalLight3D).directional_shadow_mode = shadow_mode
	elif shadow_mode == -2 and main.get("sun") != null:   # --shadow-mode=off: no sun shadows at all
		(main.get("sun") as DirectionalLight3D).shadow_enabled = false
	var scripts := (_tail_us - _head_us) / 1000.0 if _tail_us > _head_us else 0.0
	var now := Time.get_ticks_usec()
	_head_us = now
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	frames += 1
	if frames == SKIP_FRAMES:
		PerfProfile.sections_on = true
		PerfProfile.sections = {}
	if frames > SKIP_FRAMES + 1 and (shot == "" or frames < SHOT_FRAME + 1 or frames > SHOT_FRAME + 2):   # (not the shot's read-back)
		rows.append([ms, scripts,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		for k in PerfProfile.sections:                 # last frame's sections (this probe runs after them all)
			var s: Array = PerfProfile.sections[k]
			var acc: Array = per_frame.get(k, [0, 0, 0])
			acc[0] += s[0]
			acc[1] = maxi(acc[1], s[0])
			acc[2] += s[2]
			per_frame[k] = acc
	PerfProfile.sections = {}
	if frames == SHOT_FRAME and shot != "":
		_shot()
	if frames < SKIP_FRAMES + 3 + int(secs * 45.0):
		return
	set_process(false)
	var n := rows.size()
	var sim: Sim = main.get("sim")
	print("perf_pass_probe %s: %d frames, sim t %.1f -> %.1f, hordes %d" % [phase, n, sim.time - n / 45.0, sim.time, sim.hordes.size()])
	for c in [[0, "frame"], [1, "scripts"]]:
		var v: Array = rows.map(func(r): return r[c[0]])
		v.sort()
		print("  %-8s median %6.2f  p95 %6.2f  max %6.2f ms" % [c[1], v[n / 2], v[int(n * 0.95)], v[-1]])
	var idx := range(n)
	idx.sort_custom(func(x, y): return rows[x][0] > rows[y][0])
	print("  longest frames (frame: ms, scripts ms): ", ", ".join(idx.slice(0, 5).map(func(i): return "#%d: %.0f, %.1f" % [i, rows[i][0], rows[i][1]])))
	var top := [0.0, 0.0, 0.0]
	for r in rows:
		for k in range(3):
			top[k] = maxf(top[k], r[2 + k])
	print("  draw calls max %d, primitives max %d, objects max %d" % top)
	var names := per_frame.keys()
	names.sort_custom(func(a, b): return per_frame[a][0] > per_frame[b][0])
	for k in names:
		print("  %-16s mean %6.3f  worst %6.2f ms/frame  (%d calls)" % [k, per_frame[k][0] / 1000.0 / n, per_frame[k][1] / 1000.0, per_frame[k][2]])
	get_tree().quit(0)


func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	print("perf_pass_probe shot ", shot)


class _Tail extends Node:
	var probe: Node

	func _process(_dt: float) -> void:
		Engine.max_fps = 0                            # (PerfProfile caps it every frame, before this)
		probe.set("_tail_us", Time.get_ticks_usec())
