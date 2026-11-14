extends Node
## PROPS probe (props-place 2026-11-14): map-start time, frame time and draw calls of one map, PHONE profile at 812x375.
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/props_probe.tscn -- --probe-map=R-01 --theme=lab [--secs=8] [--shot=<png>]
## start = add_child(main) -> main.started, plus the longest frame in the 6 s after it (the first-draw stall); then --secs of
## frames (median / p95 ms) with the draw calls / primitives / objects (median, max). Emulation, not a phone.
var main: Node3D
var map := "R-01"
var secs := 8.0
var shot := ""
var size := Vector2i(812, 375)
var t_add := 0
var t_start := 0
var rows: Array = []
var stall := 0.0
var _last := 0
var frames := 0
var t0 := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-map="): map = a.substr(12)
		elif a.begins_with("--secs="): secs = float(a.substr(7))
		elif a.begins_with("--shot="): shot = a.substr(7)
		elif a.begins_with("--probe-window="): size = Vector2i(int(a.substr(15).get_slice("x", 0)), int(a.substr(15).get_slice("x", 1)))
	if DisplayServer.get_name() == "headless":
		print("SKIP props_probe: needs a window"); get_tree().quit(0); return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	PerfProfile.force_level("phone")
	main = (load("res://main.tscn") as PackedScene).instantiate()
	var f := ""
	for g in DirAccess.get_files_at("res://maps4"):
		if g.begins_with(map) and g.ends_with(".json"):
			f = g
	main.set("map_path", "res://maps4/" + f)
	main.set("demo", true)
	main.set("ai_level", "Standard")
	main.set("seed_value", 7)
	main.set("mobile", true)
	t_add = Time.get_ticks_usec()
	add_child(main)

func _process(_dt: float) -> void:
	if main == null: return
	var now := Time.get_ticks_usec()
	if t_start == 0:
		if bool(main.get("started")):
			t_start = now
			_last = now
			print("PROBE start_ms %.0f" % ((t_start - t_add) / 1000.0))
		return
	var ft := (now - _last) / 1000.0
	_last = now
	var el := (now - t_start) / 1e6
	if el < 6.0:
		stall = maxf(stall, ft)
		return
	if t0 == 0.0:
		t0 = el
	rows.append([ft, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	if shot != "" and rows.size() == 30:
		get_viewport().get_texture().get_image().save_png(shot)
		print("PROBE shot ", shot)
	if el - t0 >= secs:
		_report()

func _med(i: int) -> float:
	var a: Array = rows.map(func(r): return r[i])
	a.sort()
	return a[a.size() / 2]

func _report() -> void:
	var f: Array = rows.map(func(r): return r[0])
	f.sort()
	var dmax := 0
	for r in rows: dmax = maxi(dmax, int(r[1]))
	print("PROBE map %s theme %s | stall_first6s_max_ms %.0f | frames %d median %.1f ms p95 %.1f ms | draw median %d max %d | prims median %d | objects median %d" % [
		map, str(LookTheme.current), stall, rows.size(), f[f.size() / 2], f[int(f.size() * 0.95)], int(_med(1)), dmax, int(_med(2)), int(_med(3))])
	get_tree().quit(0)
