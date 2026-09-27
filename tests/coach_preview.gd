extends Node
## Render probe for the tutorial (coach_overlay.gd, tutorial_page.gd, the lessons through main.gd) - screenshots
## for review, not part of the test suites. Run WINDOWED (not --headless: GPU rendering needs a real, even if
## off-screen, window - the same rule phone_fit.gd and skills_probe.gd follow), as a scene (the Net autoload
## must exist, project.godot's [autoload]):
##
##   phone:   Godot --path <wt> --resolution 1266x585 res://tests/coach_preview.tscn -- --mobile tag=phone out=<dir>
##   desktop: Godot --path <wt> --resolution 1920x1080 res://tests/coach_preview.tscn -- tag=desktop out=<dir>
##   combine: Godot --path <wt> --resolution 480x300 res://tests/coach_preview.tscn -- combine=1 out=<dir>
##            (after the others; loads their PNGs back into one labelled contact sheet, rendered in a SubViewport
##            sized to its content so the window's canvas_items/expand stretch never rescales it)
##   lessons=1,4,9   only those lessons (default: all nine)
##
## Every lesson starts the real game (main.tscn) through main's relaunch key, exactly as the TUTORIAL page does,
## and is shot once its first step's card, spotlight and hand are up. Progress goes to a scratch file
## (user://coach_preview_tutorial.cfg, 3 of 9 done, offered) so the first-launch jump never fires and the real
## progress file is never touched.
##
## Shots (saved to <out>/<tag>-<name>.png):
##   L0 .. L9     each lesson at its first step (the tour's hello, L1's drag hand, ...)
##   (every step of every lesson: tests/tutorial_walk.tscn)
##   hand         a 2x close-up of the pointing hand from L1
##   first        L1 on the first launch: SKIP TUTORIAL on the card
##   complete     LESSON COMPLETE (L3's)
##   final        TRAINING COMPLETE with the Graduate vat unlocked (the turntable)
##   page         the TUTORIAL page (3 / 9 done)

const MAIN := "res://main.tscn"
const SHOT_ORDER := ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "hand", "first", "complete", "final", "page"]
const TAGS := ["phone", "desktop"]
const PROGRESS := "user://coach_preview_tutorial.cfg"


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


func _run() -> void:
	var args := _args()
	var out_dir := str(args.get("out", "user://coach_shots"))
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	if args.has("combine"):
		await _combine_all(out_dir)
		get_tree().quit()
		return
	var tag := str(args.get("tag", "shot"))
	TutorialDirector.path = PROGRESS
	TutorialDirector.completed_ids = [1, 2, 3]
	TutorialDirector.offered = true
	TutorialDirector._loaded = true
	TutorialDirector.save_progress()
	var only := []
	for v in str(args.get("lessons", "0,1,2,3,4,5,6,7,8,9")).split(","):
		only.append(int(v))
	for i in only:
		await _lesson_shot(out_dir, tag, i, false)
	if 1 in only:
		await _lesson_shot(out_dir, tag, 1, true)
	await _complete_shots(out_dir, tag)
	await _page_shot(out_dir, tag)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	print("COACH_PREVIEW done tag=%s out=%s" % [tag, out_dir])
	get_tree().quit()


func _shot(dir: String, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("screenshot ", path)
	return img


func _save_crop(img: Image, dir: String, name: String, center: Vector2, half: float) -> void:
	var sz := img.get_size()
	var rect := Rect2i(Vector2i(int(center.x - half), int(center.y - half)), Vector2i(int(half * 2.0), int(half * 2.0)))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, sz))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var region := img.get_region(rect)
	region.resize(region.get_width() * 2, region.get_height() * 2, Image.INTERPOLATE_NEAREST)
	region.save_png("%s/%s.png" % [dir, name])


func _start(extra: Dictionary) -> Node:
	var main_script: GDScript = load("res://scripts/main.gd")
	main_script.relaunch = extra
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(inst)
	return inst


func _lesson_shot(out_dir: String, tag: String, id: int, first: bool) -> void:
	var inst := _start({"tutorial": id, "first": first, "faction": "null", "colour": "A"})
	await _frames(70)                                 # camera fit, badges, the first card eases in
	var name := "first" if first else "L%d" % id
	var img := await _shot(out_dir, "%s-%s" % [tag, name])
	if id == 1 and not first and inst.coach:
		var d: TutorialDirector = inst.director
		var h: int = d.names["H"]
		inst.coach.gesture("tap", inst.cam.unproject_position(inst.sim.nodes[h]["pos"]))
		await _frames(4)
		img = await _shot(out_dir, "%s-_tmp" % tag)
		_save_crop(img, out_dir, "%s-hand" % tag, inst.coach.world_to_overlay(inst.cam.unproject_position(inst.sim.nodes[h]["pos"])), 120.0)
		DirAccess.remove_absolute("%s/%s-_tmp.png" % [out_dir, tag])
	inst.queue_free()
	await _frames(6)


func _complete_shots(out_dir: String, tag: String) -> void:
	var inst := _start({"tutorial": 3, "faction": "null", "colour": "A"})
	await _frames(40)
	inst._on_lesson_completed({"id": 3, "title": TutorialDirector.title_of(3), "time": 94.0, "final": false, "next": 4,
			"lines": [TutorialDirector.line("L3.done1"), TutorialDirector.line("L3.done2")]})
	await _frames(12)
	await _shot(out_dir, "%s-complete" % tag)
	inst.queue_free()
	await _frames(6)
	var fin := _start({"tutorial": 9, "faction": "null", "colour": "A"})
	await _frames(40)
	fin._on_lesson_completed({"id": 9, "final": true, "relay_kill": true, "kill_units": 43, "graduate": true, "time": 170.0})
	await _frames(90)                                 # the Graduate skin loads on a thread, then turns
	await _shot(out_dir, "%s-final" % tag)
	fin.queue_free()
	await _frames(6)


func _page_shot(out_dir: String, tag: String) -> void:
	var inst := _start({"faction": "null", "colour": "A", "menu": "tutorial"})
	await _frames(30)
	await _shot(out_dir, "%s-page" % tag)
	inst.queue_free()
	await _frames(6)


# ------------------------------------------------------------------ contact sheet
func _combine_all(out_dir: String) -> void:
	var entries := []
	for tag in TAGS:
		for k in SHOT_ORDER:
			var path := "%s/%s-%s.png" % [out_dir, tag, k]
			if FileAccess.file_exists(path):
				entries.append([tag, k, path])
	if entries.is_empty():
		print("CONTACT SHEET: no shots found in ", out_dir)
		return
	const COLS := 4
	const THUMB_W := 420.0
	const PAD := 14.0
	const LABEL_H := 26.0
	var rows := ceili(float(entries.size()) / float(COLS))
	var thumb_h := []
	var textures := []
	var row_h := []
	row_h.resize(rows)
	row_h.fill(0.0)
	for i in range(entries.size()):
		var img := Image.load_from_file(entries[i][2])
		textures.append(ImageTexture.create_from_image(img))
		var h := THUMB_W * float(img.get_height()) / float(img.get_width())
		thumb_h.append(h)
		var row := i / COLS
		row_h[row] = maxf(row_h[row], h)
	var row_y := []
	row_y.resize(rows)
	var y_cursor := PAD
	for r in range(rows):
		row_y[r] = y_cursor
		y_cursor += row_h[r] + LABEL_H + PAD
	var sub := SubViewport.new()
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(sub)
	var root_ui := Control.new()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.045)
	root_ui.add_child(bg)
	sub.add_child(root_ui)
	var font := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
	for i in range(entries.size()):
		var col := i % COLS
		var row := i / COLS
		var x := PAD + col * (THUMB_W + PAD)
		var y: float = row_y[row]
		var lbl := Label.new()
		lbl.text = "%s · %s" % [str(entries[i][0]).to_upper(), str(entries[i][1]).to_upper()]
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color("d8eef5"))
		lbl.position = Vector2(x, y)
		lbl.size = Vector2(THUMB_W, LABEL_H)
		root_ui.add_child(lbl)
		var tr := TextureRect.new()
		tr.texture = textures[i]
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.position = Vector2(x, y + LABEL_H)
		tr.size = Vector2(THUMB_W, thumb_h[i])
		root_ui.add_child(tr)
	var total_w := COLS * (THUMB_W + PAD) + PAD
	root_ui.size = Vector2(total_w, y_cursor)
	bg.size = root_ui.size
	sub.size = Vector2i(int(ceil(total_w)), int(ceil(y_cursor)))
	await _frames(8)
	var out_path := "%s/contact-sheet.png" % out_dir
	sub.get_texture().get_image().save_png(out_path)
	sub.queue_free()
	print("CONTACT SHEET ", out_path)
