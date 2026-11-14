extends Node
## ALPHA 24 UNITS v4 render probe (a dev tool, not a suite): a real 1v1 vs the AI, VEX (seat A) against rival=<faction>,
## columns of v4 VEX walking + clashing, shot at the window size. Run WINDOWED, off-screen, silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/v4_unit_shots.tscn
##          -- --no-telemetry out=<dir> [me=vex] [rival=ember] [zoom=34] [colour=A|gold|purple..] [focus=<node>] [tag=x]

const MAIN := "res://main.tscn"
var MAP := "res://maps4/N-24-k-crossing.json"


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _step(inst: Node, seconds: float) -> void:
	var t0: float = inst.sim.time
	var guard := 0
	while inst.sim.time - t0 < seconds and guard < 4000:
		await get_tree().process_frame
		guard += 1


func _shot(inst: Node, file: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _run() -> void:
	var out := "user://"
	var rival := "ember"
	var zoom := -1.0
	var tag := "match"
	var focus := -1
	var colour := "A"
	var me := "vex"                    # me=<faction>: the seat-A faction (units-v4: the other five)
	var south := false                 # south=1: the column walks toward the camera (the faces), focus = its target
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("rival="):
			rival = a.substr(6)
		if a.begins_with("zoom="):
			zoom = float(a.substr(5))
		if a.begins_with("map="):
			MAP = a.substr(4)
		if a.begins_with("tag="):
			tag = a.substr(4)
		if a.begins_with("colour="):
			colour = a.substr(7)
		if a.begins_with("focus="):
			focus = int(a.substr(6))
		if a.begins_with("me="):
			me = a.substr(3)
		if a == "south=1":
			south = true
	var main_script = load("res://scripts/main.gd")
	main_script.relaunch = {"faction": me, "rival": rival, "mode": "1v1", "map": MAP, "colour": colour}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	if zoom > 0.0:
		inst.scenario_zoom = zoom
	if focus >= 0:
		inst.focus_node = focus
	get_tree().root.add_child(inst)
	await _frames(12)
	var sim: Sim = inst.sim
	print("factions ", sim.factions)
	var mine := []
	var theirs := []
	for n in sim.nodes:
		var o := str(n.get("owner", ""))
		if o == "A":
			mine.append(int(n["id"]))
		elif o != "":
			theirs.append(int(n["id"]))
	print("mine ", mine, " theirs ", theirs)
	await _shot(inst, "%s/v4_%s_0_start.png" % [out, tag])
	if mine.is_empty() or theirs.is_empty():
		get_tree().quit(1)
		return
	var a: int = mine[0]
	var b: int = theirs[0]
	if south:                          # the nearest node that lies toward the camera from a
		var pa: Vector3 = sim.nodes[a]["pos"]
		var best := 1e9
		for n in sim.nodes:
			var off: Vector3 = (n["pos"] as Vector3) - pa
			off.y = 0.0
			if off.length() > 1.0 and off.normalized().dot(Rules.front_dir()) > 0.6 and off.length() < best and off.length() < 40.0:
				best = off.length()
				b = int(n["id"])
		print("south target ", b, " at ", best, " m")
		# pass focus=<that id> to frame it (the camera focus is set when the match starts)
	sim.nodes[a]["units"] = 400.0
	sim.nodes[b]["units"] = 400.0
	sim.send(a, b, 0.6)
	await _step(inst, 2.0)
	sim.send(b, a, 0.6)
	await _step(inst, 1.5)
	await _shot(inst, "%s/v4_%s_1_columns.png" % [out, tag])
	var prims := 0
	var draws := 0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while frames < 90:
		await get_tree().process_frame
		frames += 1
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var bodies := 0
	for h in sim.hordes:
		bodies += int(Rules.shown(float(h.get("units", 0.0))))
	print("PERF prims_max %d draws_max %d ms_per_frame %.2f hordes %d" % [prims, draws, (Time.get_ticks_usec() - t0) / 1000.0 / frames, sim.hordes.size()])
	await _shot(inst, "%s/v4_%s_2_clash.png" % [out, tag])
	await _step(inst, 2.5)
	await _shot(inst, "%s/v4_%s_3_later.png" % [out, tag])
	get_tree().quit(0)
