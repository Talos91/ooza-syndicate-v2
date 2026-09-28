extends Node
## Every tab of the bottom bar, touched once from every page that shows the bar, lands on its page; BACK (the top bar's
## on phones, the title row's link on desktop) lands on the page the meta pages were opened from (Daniele's 0.22.0 test:
## "tapping HOME in the bottom tab bar doesn't go back to home, it just highlights the button"; "the BACK in LEADERBOARD
## just reloads the leaderboard"). Touches go through Input as a phone's browser delivers them (emulate_mouse_from_touch).
##   Godot --path . --resolution 1280x720 res://tests/test_ui_nav.tscn -- --no-notice --no-account
##   Godot --path . --resolution 1136x640 res://tests/test_ui_nav.tscn -- --mobile --no-notice --no-account
## (NOT --headless: the headless display server routes no input.) Exit code 0 = all passed.

const TAB_PAGE := {"home": "home", "play": "play", "armies": "armies", "campaign": "campaign"}
const FROM := ["main", "play", "armies", "chapters", "factions", "maps", "setup", "seats", "profile", "challenges",
		"leaderboard", "history", "account", "options", "help", "online"]
var m
var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _tap(c: Control) -> void:
	# window pixels: the page's own scale, then the viewport's stretch (touches arrive in window coordinates)
	var p: Vector2 = c.get_viewport().get_screen_transform() * (c.get_global_transform_with_canvas() * (c.size / 2.0))
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = p
		t.pressed = pressed
		Input.parse_input_event(t)
		await _frames(2)
	await _frames(6)                                    # the flash frame, then the page


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _frames(40)
	m = main.menu_layer
	var tabs_seen := 0
	for from in FROM:
		for tab in TAB_PAGE:
			m.call("show_" + from)
			await _frames(3)
			if not is_instance_valid(m.nav_bar) or not m.nav_bar.buttons.has(tab):
				continue                                # a phone's slim sub-page: no tab bar (BACK only)
			tabs_seen += 1
			await _tap(m.nav_bar.buttons[tab])
			check(m._page == TAB_PAGE[tab], "from %s, one tap on %s lands on %s (got %s)" % [from, tab.to_upper(), TAB_PAGE[tab], m._page])
	check(tabs_seen >= 16, "the tab bar was there to tap (%d taps)" % tabs_seen)
	# BACK, touched: a meta page opened from HOME, and one from PROFILE, go back where they came from
	for path in [["main", "profile"], ["main", "options"], ["main", "profile", "leaderboard"], ["play", "challenges"]]:
		for p in path:
			m.call("show_" + p)
			await _frames(3)
		var back: Control = null
		if is_instance_valid(m.top_bar):
			for c in m.top_bar.get_children():
				if c is Button and str(c.text).contains("BACK"):
					back = c
		if back == null:                               # desktop: the title row's BACK link
			for c in m.content.get_children():
				if c is Button and str(c.text).contains("BACK"):
					back = c
		if back == null:
			check(false, "a BACK to tap after %s" % " > ".join(path))
			continue
		await _tap(back)
		var want: String = TAB_PAGE.get(path[path.size() - 2], path[path.size() - 2])
		if path[path.size() - 2] == "main":
			want = "home"
		check(m._page == want, "%s: one tap on BACK lands on %s (got %s)" % [" > ".join(path), want, m._page])
	print("test_ui_nav: ", "PASS" if failures == 0 else "%d FAILED" % failures, " (%d tab taps)" % tabs_seen)
	get_tree().quit(1 if failures > 0 else 0)
