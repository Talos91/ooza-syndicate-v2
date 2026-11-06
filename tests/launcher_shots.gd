extends Node
## LAUNCHER TURRET + GOOGAT contact-sheet probe (a dev tool, not a suite): R-14 Catapult Bay as the game draws it on a
## landscape phone - 1 A's T1 launcher loading (A and B units in the cannon, the LOADING readout over the target and the
## tag), 2 the salvo in the air, 3 the launcher at T3 (the bigger cannon) with its inspector open (UPGRADE / LOAD), 4 a
## GooGat at half ammo with its inspector (ammo n/cap). Run WINDOWED as a scene, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/launcher_shots.tscn -- out=<dir>

const MAIN := "res://main.tscn"
const MAP := "res://maps4/R-14-catapult-bay.json"


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


func _frame_on(inst: Node, ids: Array, dist: float) -> void:
	var c := Vector3.ZERO
	for id in ids:
		c += inst.sim.nodes[int(id)]["pos"]
	inst.cam_target = c / float(ids.size())
	inst.cam_dist = dist


func _run() -> void:
	var out := str(_args().get("out", "user://launcher_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": MAP}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var lid := -1
	for n in sim.nodes:
		if str(n["relay"]) == "launcher":
			lid = int(n["id"])
			break
	var n: Dictionary = sim.nodes[lid]
	n["owner"] = "A"
	n["units"] = 40.0
	MapBuilder.apply_owner(inst.vis[lid]["parts"], "A")
	print("launcher %d tier %d targets %s" % [lid, int(n["tier"]), str(n["proto"].get("targets", []))])
	while sim.launcher_aim(lid) != int(n["proto"].get("target", -1)):
		sim.step(0.1)
	var tgt := sim.launcher_aim(lid)
	sim.fire_relay(lid)
	sim.step(0.05)
	n["relay_t"] = 60.0                                # hold the loading frame
	n["relay_move"] = 60.0
	n["load"] = {"A": {"units": 120.0, "faction": "vex"}, "B": {"units": 55.0, "faction": "ember"}}
	_frame_on(inst, [lid, tgt], 70.0)
	await _frames(40)
	await _shot(inst, "%s/1-loading.png" % out)
	n["relay_t"] = 0.01                                # the salvo
	var t0: float = sim.time
	while sim.time - t0 < 0.7:
		await get_tree().process_frame
	await _shot(inst, "%s/2-salvo.png" % out)
	while sim.time - t0 < 3.0:
		await get_tree().process_frame
	n["tier"] = 2
	n["units"] = 300.0
	_frame_on(inst, [lid], 34.0)
	await _frames(30)
	inst.hud.inspect(lid, inst.cam)
	await _frames(20)
	await _shot(inst, "%s/3-launcher-T2-inspector.png" % out)
	inst.hud.close_inspector()
	n["tier"] = 3
	await _frames(40)
	await _shot(inst, "%s/4-launcher-T3.png" % out)
	var gid := -1
	for m in sim.nodes:
		if m["structure"] == "machinegoon":
			gid = int(m["id"])
			break
	var g: Dictionary = sim.nodes[gid]
	g["owner"] = "A"
	g["units"] = Sim.gat_cap(g) * 0.5
	MapBuilder.apply_owner(inst.vis[gid]["parts"], "A")
	_frame_on(inst, [gid], 34.0)
	await _frames(30)
	inst.hud.inspect(gid, inst.cam)
	await _frames(20)
	await _shot(inst, "%s/5-googat-half-ammo.png" % out)
	print("LAUNCHER SHOTS DONE")
	get_tree().quit()
