extends SceneTree
## Headless one-tap check (Daniele's phone test, 2026-09-28: "you need to double or triple click any menu item"):
##   Godot --path . --script res://tests/test_ui_tap.gd     (NOT --headless: the headless display server routes no input;
##   a window opens for a second)
## A finger's touch (press, a few px of wobble, release - through Input, as a phone's browser delivers it, with the
## project's emulate_mouse_from_touch) must press a UiKit button once: on the page, and inside a TouchScroll list
## (where a swipe must scroll and never press). The texture cache (UiKit.tex) keeps one copy and honours its budgets.
## Exit code 0 = all passed.

var failures := 0


class M:
	## The bits of Menu that UiKit's builders read.
	var content: Control
	func _pt_factor() -> float:
		return 0.0


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)
	Input.flush_buffered_events()


func _drag(pos: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = pos
	d.relative = rel
	Input.parse_input_event(d)
	Input.flush_buffered_events()


func _tap(pos: Vector2, wobble := Vector2.ZERO) -> void:
	_touch(pos, true)
	await _frames(2)
	if wobble != Vector2.ZERO:
		_drag(pos + wobble, wobble)
		await _frames(1)
	_touch(pos + wobble, false)
	await _frames(4)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false),
			"the project turns touches into mouse presses (buttons listen to those)")
	var m := M.new()
	m.content = Control.new()
	m.content.size = Vector2(1280, 720)
	root.add_child(m.content)
	await _frames(2)
	var hits := {"page": 0, "list": 0}
	var b := UiKit.btn(m, "PLAY", Vector2(40, 40), Vector2(230, 54), func(): hits["page"] += 1, "primary", "vex", 20)
	var sc := TouchScroll.new()
	sc.position = Vector2(400, 40)
	sc.size = Vector2(400, 300)
	m.content.add_child(sc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 900)
	sc.add_child(box)
	var lb := UiKit.make_btn(m, "A MAP", Vector2(380, 60), func():
		if not sc.was_drag():
			hits["list"] += 1, "secondary", "vex", 16)
	box.add_child(lb)
	await _frames(3)
	var bc := b.get_global_rect().get_center()
	await _tap(bc)
	check(hits["page"] == 1, "one still tap presses a page button once (got %d)" % hits["page"])
	await _tap(bc, Vector2(4, 3))
	check(hits["page"] == 2, "a tap that wobbles 5 px still presses it (got %d)" % hits["page"])
	b.pressed.emit()                                   # two taps before the page answers: one action
	b.pressed.emit()
	await _frames(4)
	check(hits["page"] == 3, "a second tap while the first is being answered does nothing (got %d)" % hits["page"])
	var lc := lb.get_global_rect().get_center()
	await _tap(lc, Vector2(3, -2))
	check(hits["list"] == 1, "one tap presses a button inside a scrolling list (got %d)" % hits["list"])
	_touch(lc, true)                                   # a swipe up the list: scrolls, never presses
	await _frames(2)
	for k in range(1, 6):
		_drag(lc - Vector2(0, 12.0 * k), Vector2(0, -12))
		await _frames(1)
	_touch(lc - Vector2(0, 60), false)
	await _frames(3)
	check(hits["list"] == 1 and sc.scroll_vertical > 0, "a swipe scrolls the list and presses nothing (scroll %d, presses %d)"
			% [sc.scroll_vertical, hits["list"]])
	# the texture cache: one copy per path, kept, and the thumbnails' bucket never pushes the pages' art out
	var p := UiKit.hero_path("vex")
	var t1 := UiKit.tex(p)
	check(t1 != null and UiKit.tex(p) == t1 and UiKit.cached(p), "UiKit.tex keeps one copy of a texture")
	check(UiKit.tex("res://no/such.png") == null, "a missing file is null")
	for code in ["A-01", "A-02", "A-03", "A-04"]:
		UiKit.map_thumb(MapPool.thumb(code))
	check(UiKit.cached(p), "map thumbnails don't evict the pages' art")
	root.remove_child(m.content)
	m.content.free()
	print("test_ui_tap: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
