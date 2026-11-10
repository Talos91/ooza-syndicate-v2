extends Node
## WORLD VISUALS 3 shots (dev tool): R-01 STRAIT, game camera, a frame sequence from the match start (the Locals' first
## march -> the goo trace on their lane; the home tube filling) plus the play-area luma (backdrop layer hidden).
## Windowed, off-screen, silent:
##   Godot --path . --resolution 740x340 --audio-driver Dummy --position -6000,-6000 res://tests/world_visuals3_shots.tscn -- \
##       out=<dir> name=<prefix> times=0.4,1.2,2.4,4 --rings-dim=dark --test --no-telemetry --mobile

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
	var out := "user://wv3"
	var nm := "shot"
	var times: Array = [0.4, 1.2, 2.4, 4.0]
	var replay := -1.0                               # replay_fill=<s>: every finished tube refills then (the completion animation)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("name="): nm = a.substr(5)
		if a.begins_with("replay_fill="): replay = a.substr(12).to_float()
		if a.begins_with("times="):
			times = []
			for t in a.substr(6).split(","):
				times.append(float(t))
	DirAccess.make_dir_recursive_absolute(out)
	var f := ""
	for g in DirAccess.get_files_at("res://maps4"):
		if g.begins_with("R-01") and g.ends_with(".json"):
			f = g
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + f}
	var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(2)
	inst.ais.clear()
	var t0 := Time.get_ticks_msec() / 1000.0
	var last: Image
	for t in times:
		var wait: float = float(t) - (Time.get_ticks_msec() / 1000.0 - t0)
		if replay >= 0.0 and float(t) >= replay:     # wait to the replay time, refill, then the frames keep their times
			var w0: float = replay - (Time.get_ticks_msec() / 1000.0 - t0)
			if w0 > 0.0:
				await get_tree().create_timer(w0).timeout
			_replay(inst)
			replay = -1.0
			wait = float(t) - (Time.get_ticks_msec() / 1000.0 - t0)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		last = inst.get_viewport().get_texture().get_image()
		last.save_png("%s/%s_t%.1f.png" % [out, nm, float(t)])
	var s := last.get_size()
	var mid := Rect2i(s.x / 4, s.y / 4, s.x / 2, s.y / 2)
	var layer: CanvasLayer = inst.scenery.backdrop
	layer.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img2 := inst.get_viewport().get_texture().get_image()
	img2.save_png(out + "/" + nm + "_playonly.png")
	var wl: WorldLayer = inst.world_layer
	if wl != null and wl.decals != null:
		wl.decals.visible = false                    # the frame without any floor decal: the "rest of the play area" mask
		await _frames(3)
		await RenderingServer.frame_post_draw
		inst.get_viewport().get_texture().get_image().save_png(out + "/" + nm + "_nodecals.png")
	else:
		print("WV3 no WorldLayer found")
	print("WV3LUMA ", nm, " full=", _luma(last, Rect2i(Vector2i.ZERO, s), false), " mid=", _luma(last, mid, false),
		" playonly=", _luma(img2, Rect2i(Vector2i.ZERO, s), true), " size=", s)
	get_tree().quit()


func _replay(inst: Node) -> void:
	var p: WorldTubes = inst.world_layer.pipes
	if p == null:
		print("WV3 no tubes")
		return
	var n := 0
	for i in p.cols:
		var c: Dictionary = p.cols[i]
		for k in range((c["full"] as Array).size()):
			if c["full"][k]:
				c["fill_t"][k] = p.wl._t
				n += 1
	print("WV3 replay fill: ", n, " tubes")
