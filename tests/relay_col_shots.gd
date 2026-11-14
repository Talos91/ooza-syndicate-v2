extends Node
## relay-v3-column shots (dev tool): an AI match is fast-forwarded until relays have REAL owners, then per relay node one
## board frame + one close-up of the column. Windowed, off-screen, silent, desktop emulation:
##   Godot --path . --resolution 1624x750 --audio-driver Dummy --position -6000,-6000 res://tests/relay_col_shots.tscn -- out=<dir> map=R-01 theme=lab
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
	await _frames(8)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)

func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://relay_col"))
	DirAccess.make_dir_recursive_absolute(out)
	var code := str(args.get("map", "R-01"))
	var theme := str(args.get("theme", "lab"))
	UiKit.save_setting_choice(theme)
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
	var owned := func() -> Array:
		var r := []
		for n in sim.nodes:
			if str(n["relay"]) != "" and str(n["owner"]) != "":
				r.append(n)
		return r
	while sim.time < 420.0 and not sim.over and (owned.call() as Array).size() < int(args.get("need", "2")):
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	sim.fx_events.clear()
	await _frames(30)
	var rel: Array = owned.call()
	print("%s %s t=%.0f owned relays: %s" % [code, theme, sim.time, str(rel.map(func(n): return "%d:%s:%s" % [n["id"], n["relay"], n["owner"]]))])
	await _shot(inst, "%s/%s-%s-board.png" % [out, code, theme])
	if not rel.is_empty():
		var n: Dictionary = rel[0]
		var p: Vector3 = n["pos"]
		var plat = inst.vis[n["id"]].get("platform")
		var names := []
		if plat is Node:
			for c in (plat as Node).get_children():
				names.append(str(c.name))
		print("node %d y=%.2f platform children %s" % [n["id"], p.y, str(names)])
		inst.set_process(false)                       # freeze the game camera, place ours
		for yaw_deg in [0.0, 55.0]:
			var d := float(args.get("dist", "34"))
			var yaw := deg_to_rad(yaw_deg)
			inst.cam.position = p + Vector3(sin(yaw) * d, 2.0, cos(yaw) * d)
			inst.cam.look_at(p + Vector3(0, -7.0, 0), Vector3.UP)
			await _frames(30)
			await _shot(inst, "%s/%s-%s-col%d-%s-yaw%d.png" % [out, code, theme, n["id"], n["owner"], int(yaw_deg)])
	print("DONE")
	get_tree().quit()
