extends Node
## PROTO: TWO DOORS render probe (a dev tool, not a suite): N-24, a line from node 2 to node 8 (its deck meets 8's ring on
## the far side) walks to the TOP door and pours in there; plus the board with both doors drawn. Run WINDOWED, off-screen,
## silent:  Godot --path . --resolution 1688x780 --audio-driver Dummy --position -6000,-6000 res://tests/door_shots.tscn
##          -- --no-telemetry out=<dir> [doors=0]

const MAIN := "res://main.tscn"
const MAP := "res://maps4/N-24-k-crossing.json"


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
	var tag := "two"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a == "doors=0":
			Rules.PROTO_TWO_DOORS = false
			tag = "one"
	var main_script = load("res://scripts/main.gd")
	main_script.relaunch = {"faction": "null", "mode": "1v1", "map": MAP}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	inst.focus_node = 8
	inst.scenario_zoom = 34.0
	get_tree().root.add_child(inst)
	await _frames(12)
	inst.ais.clear()
	var sim: Sim = inst.sim
	sim.nodes[2]["owner"] = "A"
	sim.nodes[2]["units"] = 300.0
	MapBuilder.apply_owner(inst.vis[2]["parts"], "A")
	await _shot(inst, "%s/doors_%s_0_board.png" % [out, tag])
	var h := sim.send(2, 8, 1.0)
	print("route ", h.get("route"), " L ", h.get("L"))
	await _step(inst, 3.3)
	await _shot(inst, "%s/doors_%s_1_ring_walk.png" % [out, tag])
	await _step(inst, 1.3)
	await _shot(inst, "%s/doors_%s_2_pouring_in.png" % [out, tag])
	await _step(inst, 1.5)
	await _shot(inst, "%s/doors_%s_3_taken.png" % [out, tag])
	get_tree().quit(0)
