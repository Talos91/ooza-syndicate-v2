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
	await get_tree().create_timer(4.0).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := inst.get_viewport().get_texture().get_image()
	img.save_png(out + "/" + nm + ".png")
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
