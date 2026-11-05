extends Node
## ROUND R contact-sheet probe (a dev tool, not a suite): four frames of each round-R map as the game draws it on a landscape
## phone - 1 the start board, 2 its relays fired (every relay owned by A and fired, 1.2 s in: the signature in motion, with
## the hazards on their own clocks), 3 an AI match fast-forwarded to 150 s, 4 the same match 25 s into its Last Stand (or at 420 s / its end). Run
## WINDOWED as a scene (the Net autoload), off-screen and silent, at the phone's point size:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/round_r_shots.tscn -- out=<dir>
##   maps=R-01,R-04     a subset (default: every R map in maps4)

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
	await _frames(6)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _open(path: String) -> Node:
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()                                  # the probe drives both seats itself
	return inst


func _ff(inst: Node, ais: Array, to: float, ls_wait := -1.0) -> void:
	## fast-forward the AI match to `to`; with ls_wait >= 0 stop that long after the Last Stand starts (the finale frame)
	var sim: Sim = inst.sim
	var ls_t := -1.0
	while sim.time < to and not sim.over:
		if ls_wait >= 0.0 and sim.last_stand_active:
			if ls_t < 0.0:
				ls_t = sim.time
			if sim.time - ls_t >= ls_wait:
				break
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	sim.fx_events.clear()


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://round_r_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var only: PackedStringArray = str(args.get("maps", "")).split(",", false)
	var files: Array = []
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with("R-") and f.ends_with(".json") and (only.is_empty() or f.substr(0, 4) in only):
			files.append(f)
	files.sort()
	for f in files:
		var code: String = f.substr(0, 4)
		var inst: Node = await _open("res://maps4/" + f)
		var sim: Sim = inst.sim
		await _frames(20)
		await _shot(inst, "%s/%s-1-start.png" % [out, code])
		for n in sim.nodes:
			if str(n["relay"]) != "":
				n["owner"] = "A"
				MapBuilder.apply_owner(inst.vis[n["id"]]["parts"], "A")
		for n in sim.nodes:
			if str(n["relay"]) != "":
				sim.fire_relay(int(n["id"]))
		var t0: float = sim.time
		while sim.time - t0 < 1.2:
			await get_tree().process_frame
		await _shot(inst, "%s/%s-2-relays-fired.png" % [out, code])
		inst.queue_free()
		await _frames(3)
		inst = await _open("res://maps4/" + f)
		sim = inst.sim
		var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
		await _ff(inst, ais, 150.0)
		await _frames(30)
		await _shot(inst, "%s/%s-3-match-150s.png" % [out, code])
		await _ff(inst, ais, 420.0, 25.0)
		await _frames(30)
		print("%s match at %.0f s, last stand %s, over %s, winner '%s'" % [code, sim.time, sim.last_stand_active, sim.over, sim.winner])
		await _shot(inst, "%s/%s-4-match-%ds%s.png" % [out, code, int(sim.time), "-last-stand" if sim.last_stand_active else ""])
		inst.queue_free()
		await _frames(3)
	print("ROUND R SHOTS DONE")
	get_tree().quit()
