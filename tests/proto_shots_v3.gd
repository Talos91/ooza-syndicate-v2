extends Node
## RELAYS 3.0 ROUND 3 render probe (a dev tool, not a suite): the five kinds on their 🗺️ test maps P-01..P-05 as round 3
## plays them - the lift's two levels (UP / DOWN on the decks, dock ghosts, the moving edge), the moving bridge in line and
## HELD by its owner, the belts' x2.25 / x0.3 tags, the launcher's aim, lock, quicker throw, landing and MISFIRE, the tilt
## held tipped (now drawn tipped: _unbatch). Run WINDOWED
## as a scene (the Net autoload), off-screen and silent:
##   Godot --path . --resolution 1688x780 --audio-driver Dummy --position -6000,-6000 res://tests/proto_shots_v3.tscn -- --no-telemetry out=<dir>
##   only=lift,ferry     a subset

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


func _step(inst: Node, seconds: float) -> void:
	var t0: float = inst.sim.time
	var guard := 0
	while inst.sim.time - t0 < seconds and guard < 6000:
		await get_tree().process_frame
		guard += 1


func _until(inst: Node, cond: Callable, limit: float) -> void:
	var t0: float = inst.sim.time
	var guard := 0
	while not cond.call() and inst.sim.time - t0 < limit and guard < 9000:
		await get_tree().process_frame
		guard += 1


func _own(inst: Node, id: int, seat: String, units := -1.0) -> void:
	inst.sim.nodes[id]["owner"] = seat
	if units >= 0.0:
		inst.sim.nodes[id]["units"] = units
	MapBuilder.apply_owner(inst.vis[id]["parts"], seat)


func _shot(inst: Node, file: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _open(code: String, focus := -1, zoom := 30.0) -> Node:
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	var m := MapBuilder.load_map(path)
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	inst.focus_node = focus
	inst.scenario_zoom = zoom
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()                                  # a still board: only what we stage moves
	return inst


func _close(inst: Node) -> void:
	inst.queue_free()
	await _frames(3)


func _through(sim: Sim, pad: int) -> Array:
	## [a, b]: two neighbours of `pad` whose route runs across it (a line from a to b crosses the launcher).
	for la in sim.adj[pad]:
		for lb in sim.adj[pad]:
			var a: int = int(la[0])
			var b: int = int(lb[0])
			if a != b and pad in sim.find_route(a, b):
				return [a, b]
	return []


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://proto_shots_v3"))
	DirAccess.make_dir_recursive_absolute(out)
	var only: PackedStringArray = str(args.get("only", "")).split(",", false)
	var want := func(k: String) -> bool: return only.is_empty() or k in only
	if want.call("lift"):
		for view in [["wide", -1, 30.0], ["close", 6, 48.0]]:
			var inst: Node = await _open("P-04", view[1], view[2])
			var sim: Sim = inst.sim
			_own(inst, 6, "A", 30.0)
			await _step(inst, 1.0)
			await _shot(inst, "%s/lift-%s-1-DOWN.png" % [out, view[0]])
			sim.fire_relay(6)
			await _until(inst, func(): return sim.nodes[6]["relay_phase"] == "moving" and float(sim.nodes[6]["relay_anim"].get("progress", 0.0)) > 0.45, 4.0)
			await _shot(inst, "%s/lift-%s-2-moving.png" % [out, view[0]])
			await _until(inst, func(): return sim.nodes[6]["relay_phase"] == "", 4.0)
			await _step(inst, 0.5)
			await _shot(inst, "%s/lift-%s-3-UP.png" % [out, view[0]])
			await _close(inst)
	if want.call("ferry"):
		var inst: Node = await _open("P-01", 3, 62.0)
		var sim: Sim = inst.sim
		_own(inst, 3, "A", 250.0)
		await _until(inst, func():
			var fp := sim.ferry_phase(3)
			return fp["part"] == "open" and float(fp["left"]) <= 6.4, 30.0)
		sim.send(3, 4, 1.0)
		await _until(inst, func(): return float(sim.ferry_phase(3)["left"]) <= 0.8, 8.0)
		await _shot(inst, "%s/ferry-1-in-line.png" % out)
		sim.fire_relay(3)                             # round 3: the owner HOLDS it in line
		await _step(inst, 1.5)
		await _shot(inst, "%s/ferry-2-HELD.png" % out)
		await _until(inst, func(): return sim.ferry_phase(3)["part"] == "away", 12.0)
		await _step(inst, 0.3)
		await _shot(inst, "%s/ferry-3-out-after-hold.png" % out)
		await _until(inst, func(): return sim._ferry_tally.is_empty(), 14.0)
		await _step(inst, 0.2)
		await _shot(inst, "%s/ferry-4-tally.png" % out)
		await _close(inst)
	if want.call("conveyor"):
		var inst: Node = await _open("P-02")
		var sim: Sim = inst.sim
		_own(inst, 0, "A", 250.0)
		_own(inst, 1, "A", 10.0)
		_own(inst, 13, "B", 250.0)
		_own(inst, 14, "B", 10.0)
		sim.send(0, 1, 1.0)                           # with the flow (0 -> 3 -> 1)
		sim.send(13, 14, 1.0)                         # against it (13 -> 11 -> 14)
		await _step(inst, 2.6)
		await _shot(inst, "%s/conveyor-1-with-and-against.png" % out)
		await _close(inst)
	if want.call("launcher"):
		var inst: Node = await _open("P-03")
		var sim: Sim = inst.sim
		var ab := _through(sim, 6)
		print("launcher line ", ab)
		_own(inst, 6, "A", 20.0)
		_own(inst, ab[0], "A", 250.0)
		await _step(inst, 1.0)
		await _shot(inst, "%s/launcher-1-aim.png" % out)
		await _until(inst, func(): return sim.launcher_aim(6) == 7, 13.0)
		sim.fire_relay(6)
		await _step(inst, 0.5)
		await _shot(inst, "%s/launcher-2-LOCK.png" % out)
		sim.send(ab[0], ab[1], 1.0)
		await _until(inst, func(): return not sim.flights.is_empty(), 8.0)
		await _step(inst, 0.7)
		await _shot(inst, "%s/launcher-3-throw.png" % out)
		await _until(inst, func(): return sim.flights.any(func(f): return sim.time - float(f["land"]) > 0.1), 4.0)
		await _shot(inst, "%s/launcher-4-landing.png" % out)
		await _close(inst)
		var inst2: Node = await _open("P-03")             # MISFIRE: B jams A's pad, A's line walks onto it
		var sim2: Sim = inst2.sim
		var ab2 := _through(sim2, 6)
		_own(inst2, 6, "A", 20.0)
		_own(inst2, ab2[0], "A", 250.0)
		await _step(inst2, 0.5)
		sim2.send(ab2[0], ab2[1], 1.0)
		await _step(inst2, 1.2)
		sim2.launcher_misfire(6, "B")
		await _until(inst2, func(): return sim2.flights.size() >= 3, 6.0)
		await _step(inst2, 0.5)
		await _shot(inst2, "%s/launcher-5-MISFIRE.png" % out)
		await _close(inst2)
	if want.call("tilt"):
		var inst: Node = await _open("P-05", 5, 52.0)
		var sim: Sim = inst.sim
		_own(inst, 5, "A", 30.0)
		_own(inst, 6, "A", 250.0)
		_own(inst, 7, "A", 10.0)
		sim.send(6, 7, 1.0)                           # a line crossing the platform 6 -> 5 -> 7 (the tilt's own laser
		await _step(inst, 0.3)                        # would hold back a rival's line: tests cover that case)
		sim.fire_relay(5)
		await _step(inst, 1.0 + 2.0)
		await _shot(inst, "%s/tilt-1-held-sliding.png" % out)
		await _step(inst, 1.6)
		await _shot(inst, "%s/tilt-2-held-later.png" % out)
		await _close(inst)
	print("PROTOSHOTS V3 DONE")
	get_tree().quit()
