extends Node
## menu-bg (0.24.4): HOME's cost with the 35C2 painting - the first show_main() (ms: loads the painting, glass and loop atlas),
## and the frame time of the idle menu with the TV loop vs the still frame. Windowed only (off-screen, silent):
##   Godot --path . --resolution 1624x750 --audio-driver Dummy --position -6000,-6000 res://tests/menu_bg_perf.tscn -- --mobile --pt-height=375 --no-notice --no-account --no-telemetry
var m


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _measure(frames: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var worst := 0
	var last := t0
	for i in range(frames):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	var total := Time.get_ticks_usec() - t0
	return {"avg_ms": total / 1000.0 / frames, "fps": frames * 1e6 / total, "worst_ms": worst / 1000.0,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0}


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	var t0 := Time.get_ticks_usec()
	get_tree().root.add_child.call_deferred(main)
	await _frames(40)
	m = main.menu_layer
	var den: MenuDen = m._den
	print("menu up after ~40 frames, wall %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	m.show_armies()
	await _frames(5)
	var t1 := Time.get_ticks_usec()
	m.show_main()                       # the painting's first load happens here (webp -> texture, 3 images)
	var first := (Time.get_ticks_usec() - t1) / 1000.0
	await _frames(30)
	var t2 := Time.get_ticks_usec()
	m.show_main()
	var again := (Time.get_ticks_usec() - t2) / 1000.0
	print("show_main first %.1f ms, again %.1f ms" % [first, again])
	await _frames(60)
	den.enabled_loop = true
	den.set_process(true)
	var a := await _measure(600)
	print("LOOP  : ", a)
	den.enabled_loop = false
	den._apply_frame()
	den.set_process(false)
	await _frames(30)
	var b := await _measure(600)
	print("STILL : ", b)
	get_tree().quit()
