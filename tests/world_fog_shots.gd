extends Node
## WORLD FOG shots (dev tool): R-01 STRAIT, game camera. Prints the mean luma of the whole frame, of the central 50 %
## and of the play area alone (backdrop layer hidden, non-black pixels). Windowed, off-screen, silent:
##   Godot --path . --resolution 740x340 --audio-driver Dummy --position -6000,-6000 res://tests/world_fog_shots.tscn -- \
##       out=<dir> name=<file> --backdrop-fog=0.5 --test --mobile

func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _luma(img: Image, r: Rect2i, skip_black: bool) -> float:
	var sum := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if skip_black and l < 0.004:
				continue
			sum += l
			n += 1
	return sum / maxf(n, 1)


func _run() -> void:
	var out := "user://fog"
	var nm := "shot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("name="): nm = a.substr(5)
	DirAccess.make_dir_recursive_absolute(out)
	var f := ""
	for g in DirAccess.get_files_at("res://maps4"):
		if g.begins_with("R-01") and g.ends_with(".json"):
			f = g
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + f}
	var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(5)
	inst.ais.clear()
	# ENDGAME: every column built (T3 vat, left half A / right half B) and every transport tube filled
	var sim: Sim = inst.sim
	var wl: WorldLayer = inst.world_layer
	var tries := 0
	while (wl.pipes == null or not wl.pipes.built) and tries < 600:
		await get_tree().process_frame
		tries += 1
	for i in wl.pipes.cols:
		var n: Dictionary = sim.nodes[wl._tubes[i]["id"]]
		n["owner"] = "A" if float(wl._tubes[i]["x"]) < 0.0 else "B"
		n["structure"] = "vat"
		n["tier"] = 3
		for a in OS.get_cmdline_user_args():
			if a == "tiers=mixed":                    # T1 / T2 / T3 by column, to see 1 / 2 / 4 tubes
				n["tier"] = 1 + (i % 3)
	var t0 := wl._t
	while wl._t - t0 < WorldTubes.FILL_S + 4.0:
		await get_tree().process_frame
	inst.cam_target = inst._view_fit[0]
	inst.cam_dist = inst._view_fit[1]
	inst._place_camera()
	for a in OS.get_cmdline_user_args():
		if a == "top=1":                              # straight down over the board (tube layout view)
			var lc: WorldLocals = wl.locals
			var bb := lc.board_bounds()
			var ctr := Vector3(bb.get_center().x, wl.floor_y, bb.get_center().y)
			var cam := Camera3D.new()
			cam.fov = 40.0
			cam.far = 600.0
			inst.add_child(cam)
			cam.global_position = ctr + Vector3(0, 125.0, 0.01)
			cam.look_at(ctr, Vector3(0, 0, -1))
			cam.make_current()
			inst.get_node("..") if false else null
			await get_tree().process_frame
			await get_tree().process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cam="):                      # cam=px,py,pz,tx,ty,tz (metres from the board centre): a free close-up camera
			var v := a.substr(4).split(",")
			var bb2 := wl.locals.board_bounds()
			var c0 := Vector3(bb2.get_center().x, wl.floor_y, bb2.get_center().y)
			var cam2 := Camera3D.new()
			cam2.fov = 50.0
			cam2.far = 600.0
			inst.add_child(cam2)
			cam2.global_position = c0 + Vector3(float(v[0]), float(v[1]), float(v[2]))
			cam2.look_at(c0 + Vector3(float(v[3]), float(v[4]), float(v[5])))
			cam2.make_current()
		if a.begins_with("frames="):
			await _frames(int(a.substr(7)))
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := inst.get_viewport().get_texture().get_image()
	img.save_png(out + "/" + nm + ".png")
	for a in OS.get_cmdline_user_args():
		if a == "rebuild=1":                          # exercise the runtime switch: v3 -> ortho -> v3 -> ortho
			wl.pipes.rebuild(true)
			wl.pipes.rebuild(false)
			wl.pipes.rebuild(true)
			await _frames(30)
			await RenderingServer.frame_post_draw
			img = inst.get_viewport().get_texture().get_image()
			img.save_png(out + "/" + nm + ".png")
	var sp := []
	for c in wl.locals.craters:
		sp.append(Vector2(snappedf(c.x, 0.01), snappedf(c.z, 0.01)))
	print("SYMPROBE craters ", sp)
	var tp := []
	for i in wl.pipes.cols:
		tp.append(Vector2(snappedf(wl._tubes[i]["x"], 0.01), snappedf(wl._tubes[i]["z"], 0.01)))
	print("SYMPROBE cols ", tp)
	print("ORTHO stats ", wl.pipes.ortho_stats, " connectors ", wl.pipes.conn_count, " grid ", wl.pipes.grid_routed, " ortho=", wl.pipes.ortho)
	var s := img.get_size()
	var mid := Rect2i(s.x / 4, s.y / 4, s.x / 2, s.y / 2)
	var layer: CanvasLayer = inst.scenery.backdrop
	layer.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img2 := inst.get_viewport().get_texture().get_image()
	img2.save_png(out + "/" + nm + "_playonly.png")
	print("FOGLUMA ", nm, " full=", _luma(img, Rect2i(Vector2i.ZERO, s), false), " mid=", _luma(img, mid, false),
		" playonly=", _luma(img2, Rect2i(Vector2i.ZERO, s), true), " size=", s)
	get_tree().quit()
