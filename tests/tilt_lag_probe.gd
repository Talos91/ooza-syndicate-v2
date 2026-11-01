extends Node
## RELAYS 3.0 round 3: the TILT lag probe (a dev tool, not a suite). P-05 in the PHONE profile at 1266x585, AI off, a line
## crossing the tilt platform: frame time + PerfProfile sections at rest (3 s) and while the platform is held tipped (the
## hold), twice. Windowed, off-screen, silent:
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/tilt_lag_probe.tscn -- --no-telemetry [--level=phone]
## Also prints whether the platform's drawn copy (MapBatch) tips with it: the batched slot's transform vs its node's.

const MAIN := "res://main.tscn"
var inst: Node
var level := "phone"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = a.substr(8)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _window(label: String, secs: float) -> void:
	PerfProfile.sections_on = true
	PerfProfile.sections = {}
	var times := []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) / 1e6 < secs:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var n := times.size()
	var sec := []
	for k in PerfProfile.sections:
		var s: Array = PerfProfile.sections[k]
		sec.append([k, float(s[0]) / 1000.0 / maxf(n, 1), float(s[1]) / 1000.0])
	sec.sort_custom(func(x, y): return x[1] > y[1])
	var top := ""
	for x in sec.slice(0, 6):
		top += " %s %.2f/%.2f" % [x[0], x[1], x[2]]
	print("TILTLAG %s frames %d frame_ms p50 %.1f p95 %.1f max %.1f | ms/frame mean/worst:%s" % [label, n, times[n / 2],
			times[int(n * 0.95)], times[n - 1], top])
	PerfProfile.sections_on = false


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1266, 585))
	PerfProfile.force_level(level)
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with("P-05") and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": "1v1", "map": path}
	inst = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	inst.mobile = true
	get_tree().root.add_child(inst)
	await _frames(30)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var tilt := -1
	for n in sim.nodes:
		if n["relay"] == "tilt":
			tilt = n["id"]
	for id in [5, 6, 7]:
		sim.nodes[id]["owner"] = "A"
		MapBuilder.apply_owner(inst.vis[id]["parts"], "A")
	sim.nodes[6]["units"] = 600.0
	sim.nodes[tilt]["owner"] = "A"
	for round in 2:
		sim.send(6, 7, 1.0)
		await _window("rest%d" % round, 3.0)
		sim.nodes[tilt]["relay_cd"] = 0.0
		sim.fire_relay(tilt)
		while sim.nodes[tilt]["relay_phase"] != "moving":
			await get_tree().process_frame
		var plat: Node3D = inst.vis[tilt].get("platform")
		await _window("held%d" % round, 4.0)
		if plat:
			var drawn := "?"
			for mi in [plat] + plat.find_children("*", "MeshInstance3D", true, false):
				if mi is MeshInstance3D:
					drawn = "layers %d (0 = drawn by MapBatch)" % (mi as MeshInstance3D).layers
					break
			print("TILTLAG platform basis tipped %s, its mesh %s" % [not plat.global_transform.basis.is_equal_approx(Basis.IDENTITY), drawn])
		while sim.nodes[tilt]["relay_phase"] != "":
			await get_tree().process_frame
	print("TILTLAG DONE")
	get_tree().quit()
