extends Node
## KEEP-LIST baseline probe (a dev tool, not a suite; maps-keep 2026-11-10): the start view of each kept old map as the game draws it on
## a landscape phone (desktop emulation, mobile profile), plus <code>.json = the screen position and kind of every relay and the
## map's own numbers, for the sheet maker (Tools in References/.../baseline). Run WINDOWED, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/keep_shots.tscn -- --no-notice out=<dir> [maps=E-01,N-02]
const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	var out := "user://keep_shots"
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("maps="):
			only = a.substr(5).split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	for path in MapPool.all():
		var code: String = path.get_file().substr(0, 4)
		if not code in MapPool.KEEP_OLD or (not only.is_empty() and not code in only):
			continue
		var m := MapBuilder.load_map(path)
		load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": m["modes"][0], "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.demo = false
		inst.mobile = true
		get_tree().root.add_child(inst)
		await _frames(90)
		await RenderingServer.frame_post_draw
		var img: Image = inst.get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, code])
		var sim: Sim = inst.sim
		var relays := []
		for n in sim.nodes:
			if str(n["relay"]) != "":
				var vpz: Vector2 = inst.cam.get_viewport().get_visible_rect().size
				var sp: Vector2 = inst.cam.unproject_position(n["pos"]) * Vector2(img.get_width() / vpz.x, img.get_height() / vpz.y)
				relays.append({"id": n["id"], "kind": str(n["relay"]), "structure": str(n.get("structure", "")), "x": sp.x, "y": sp.y})
		var info := {"code": code, "name": m.get("name", ""), "mode": m["modes"][0], "modes": m["modes"], "frame": m.get("frame", {}),
				"nodes": sim.nodes.size(), "relays": relays, "pitch": inst.cam_pitch, "viewport": [img.get_width(), img.get_height()]}
		var f := FileAccess.open("%s/%s.json" % [out, code], FileAccess.WRITE)
		f.store_string(JSON.stringify(info))
		f.close()
		print("shot ", code, " relays ", relays.size())
		inst.queue_free()
		await _frames(3)
	print("KEEP SHOTS DONE")
	get_tree().quit()
