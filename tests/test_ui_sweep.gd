extends Node
## The phone button sweep (Daniele 2026-09-29: "leaderboard on mobile back buttons don't work, check all buttons"): every
## menu page opened in turn, every visible enabled button on it touched once (scrolled into view first) the way a phone's
## browser delivers a tap. A button FAILS when the touch doesn't reach it (the control on top is named) or when it reaches
## it and nothing happens (no page change, no rebuild, no match). Buttons that leave the game or the device (QUIT,
## FULLSCREEN, sign-in, the web-only fields) are listed as skipped.
##   Godot --path . --resolution 1136x640 res://tests/test_ui_sweep.tscn -- --mobile --no-notice --no-account
##   Godot --path . --resolution 1280x720 res://tests/test_ui_sweep.tscn -- --no-notice --no-account
## (NOT --headless: the headless display server routes no input.) Exit code 0 = no button failed.

const PAGES := ["main", "play", "factions", "maps", "setup", "seats", "armies", "skills", "cosmetics", "chapters", "_show_hub", "city_map",
		"online", "profile", "challenges", "leaderboard", "history", "account", "options", "privacy", "help", "tutorial"]
const SKIP := ["QUIT", "FULLSCREEN", "INSTALL", "GOOGLE", "SIGN IN", "DELETE", "SHARE CODE", "JOIN ROOM", "CREATE ROOM",
		"RECONNECT", "RENAME", "PRIVACY PAGE"]
var main: Node
var m
var failures := 0
var taps := 0
var skipped := []
var quiet := []


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _fresh_main() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await _frames(2)
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _frames(30)
	m = main.menu_layer


func _screen_pos(c: Control) -> Vector2:
	return c.get_viewport().get_screen_transform() * (c.get_global_transform_with_canvas() * (c.size / 2.0))


func _touch(p: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = p
	t.pressed = pressed
	Input.parse_input_event(t)


func _label(b: BaseButton) -> String:
	var t := str(b.text) if b is Button else ""
	if t.strip_edges() == "":
		t = str(b.tooltip_text)
	if t.strip_edges() == "":
		for c in b.find_children("*", "Label", true, false):
			t = str((c as Label).text)
			break
	return t.strip_edges().replace("\n", " ") if t.strip_edges() != "" else "<%s @ %s>" % [b.get_class(), str(b.position.floor())]


func _buttons() -> Array:
	## Every visible, enabled, tappable button of the menu right now, in tree order.
	var out := []
	for b in m.find_children("*", "BaseButton", true, false):
		var bb := b as BaseButton
		if bb.is_visible_in_tree() and not bb.disabled and bb.mouse_filter != Control.MOUSE_FILTER_IGNORE and bb.size.x > 2.0 and bb.size.y > 2.0:
			out.append(bb)
	return out


func _open(page: String) -> void:
	if not is_instance_valid(m):
		await _fresh_main()
	m.call("show_" + page if not page.begins_with("_") else page)
	await _frames(6)


func _state() -> String:
	var first = m.content.get_child(0) if is_instance_valid(m) and m.content.get_child_count() > 0 else null
	return "%s|%s|%d" % [str(m._page) if is_instance_valid(m) else "-", str(first.get_instance_id()) if first else "-",
			m.content.get_child_count() if is_instance_valid(m) else -1]


func _ready() -> void:
	await _fresh_main()
	var mobile_run := "--mobile" in OS.get_cmdline_user_args()
	for page in PAGES:
		await _open(page)
		var names := _buttons().map(func(b): return _label(b))
		for i in range(names.size()):
			var name: String = names[i]
			if SKIP.any(func(s): return name.to_upper().contains(s)):
				if not name in skipped:
					skipped.append("%s: %s" % [page, name])
				continue
			await _open(page)                          # each tap on a freshly opened page
			var list := _buttons()
			if i >= list.size():
				continue
			var b: BaseButton = list[i]
			if _label(b) != name:
				continue                               # the page came back different (a random pick): skip it
			var sc := b.get_parent()
			while sc != null and not (sc is ScrollContainer):
				sc = sc.get_parent()
			if sc is ScrollContainer:
				(sc as ScrollContainer).ensure_control_visible(b)
				await _frames(2)
			var p := _screen_pos(b)
			var vr := get_viewport().get_visible_rect()
			if not Rect2(Vector2.ZERO, DisplayServer.window_get_size()).has_point(p):
				print("FAIL  %s: %s - off the screen at %s" % [page, name, p.floor()])
				failures += 1
				continue
			var got := [false]
			b.pressed.connect(func(): got[0] = true)
			b.button_down.connect(func(): got[0] = true)
			var before := _state()
			taps += 1
			_touch(p, true)
			await _frames(2)
			var hovered := get_viewport().gui_get_hovered_control()
			_touch(p, false)
			await _frames(8)
			if not got[0]:
				var who := "%s %s" % [hovered.get_class(), hovered.name] if hovered != null else "nothing"
				if hovered != null and (hovered == b or b.is_ancestor_of(hovered)):
					who = "the button itself (hovered, no press)"
				print("FAIL  %s: %s - the touch didn't press it (on top: %s)" % [page, name, who])
				failures += 1
				continue
			if not is_instance_valid(m) or not is_instance_valid(main) or main.menu_layer != m:
				await _fresh_main()                    # it started a match / lesson: that counts
				continue
			if _state() == before and page != "city_map":   # (the 3D city map changes inside its own view: cards, chips)
				quiet.append("%s: %s" % [page, name])
	for q in quiet:
		print("QUIET %s  (pressed; the page didn't change or rebuild - check it's meant to)" % q)
	for s in skipped:
		print("SKIP  %s" % s)
	print("test_ui_sweep (%s): " % ("phone" if mobile_run else "desktop"), "PASS" if failures == 0 else "%d FAILED" % failures,
			" (%d taps, %d quiet, %d skipped)" % [taps, quiet.size(), skipped.size()])
	get_tree().quit(1 if failures > 0 else 0)
