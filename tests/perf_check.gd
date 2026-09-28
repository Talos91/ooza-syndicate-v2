extends Node
## Alpha 21 OPT-RENDER render budget check (a scene: tests/perf_check.tscn):
##   Godot --path . tests/perf_check.tscn          (windowed: the render monitors count nothing headless)
## Loads Rules.PERF_CHECK_MAP with every seat played by the AI, fast-forwards to Rules.PERF_CHECK_FF, plays
## Rules.PERF_CHECK_SECONDS in real time in the PHONE profile at 1266x585, and checks the frame's draw calls /
## primitives / objects (max over the last 3 s) against Rules.PERF_BUDGET_*, and that every batched map piece
## is drawn where and as its node says (MapBatch.verify). Prints the numbers; exit code 0 = within budget.
## Headless it prints SKIP and exits 0. Run it with a timeout (a windowed capture can stall on a busy GPU):
##   timeout 90 Godot --path . tests/perf_check.tscn

var main: Node3D
var t := 0.0
var samples := []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP perf_check: needs a window (the render monitors count nothing headless)")
		get_tree().quit(0)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1266, 585))
	PerfProfile.force_level("phone")
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", Rules.PERF_CHECK_MAP)
	main.set("demo", true)
	main.set("ai_level", "Standard")
	main.set("ff_to", Rules.PERF_CHECK_FF)
	main.set("seed_value", 7)
	main.set("mobile", true)
	add_child(main)


func _process(dt: float) -> void:
	if main == null or not bool(main.get("started")):
		return
	t += dt
	if t > Rules.PERF_CHECK_SECONDS - 3.0:
		samples.append([Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if t < Rules.PERF_CHECK_SECONDS:
		return
	set_process(false)
	var top := [0.0, 0.0, 0.0]
	for s in samples:
		for k in range(3):
			top[k] = maxf(top[k], s[k])
	var budget := [Rules.PERF_BUDGET_DRAW_CALLS, Rules.PERF_BUDGET_PRIMITIVES, Rules.PERF_BUDGET_OBJECTS]
	var names := ["draw calls", "primitives", "objects"]
	var fails := 0
	for k in range(3):
		var ok: bool = top[k] <= budget[k]
		fails += 0 if ok else 1
		print("%s %s %d (budget %d)" % ["PASS" if ok else "FAIL", names[k], top[k], budget[k]])
	var bad := MapBatch.verify()
	fails += 0 if bad.is_empty() else 1
	print("%s batched pieces consistent (%d mismatches) %s" % ["PASS" if bad.is_empty() else "FAIL", bad.size(), bad.slice(0, 5)])
	var ms := PerfProfile.match_stats()                # Alpha 21: the per-match stats Progression's telemetry reads
	var ms_ok := not ms.is_empty() and float(ms.get("fps_avg", 0)) > 0.0 and int(ms.get("frames", 0)) > 0 			and float(ms["frame_ms_p50"]) <= float(ms["frame_ms_p95"]) and float(ms["frame_ms_p95"]) <= float(ms["frame_ms_max"])
	fails += 0 if ms_ok else 1
	print("%s match_stats %s" % ["PASS" if ms_ok else "FAIL", ms])
	print("perf_check %s: %s at t=%.0f, batch %s" % ["OK" if fails == 0 else "FAILED", Rules.PERF_CHECK_MAP.get_file(),
			float(main.get("sim").get("time")), MapBatch.stats()])
	get_tree().quit(0 if fails == 0 else 1)
