extends Node
## Every tab of the bottom bar, touched once from every page that shows the bar, lands on its page; BACK (the top bar's
## on phones, the title row's link on desktop) lands on the page the meta pages were opened from (Daniele's 0.22.0 test:
## "tapping HOME in the bottom tab bar doesn't go back to home, it just highlights the button"; "the BACK in LEADERBOARD
## just reloads the leaderboard"). Touches go through Input as a phone's browser delivers them (emulate_mouse_from_touch).
##   Godot --path . --resolution 1280x720 res://tests/test_ui_nav.tscn -- --no-notice --no-account
##   Godot --path . --resolution 1136x640 res://tests/test_ui_nav.tscn -- --mobile --no-notice --no-account
## (NOT --headless: the headless display server routes no input.) Exit code 0 = all passed.

const TAB_PAGE := {"home": "home", "play": "play", "armies": "armies", "campaign": "campaign", "profile": "profile", "guide": "guide"}
const FROM := ["main", "play", "armies", "chapters", "factions", "maps", "setup", "setup_advanced", "seats", "profile", "challenges",
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


func _settle() -> void:
	## A page that loads (LEADERBOARD, MATCH HISTORY) rebuilds itself when its answer comes back: tap after that, not during.
	await _frames(3)
	for i in range(120):
		if str(m.get("_board_state")) != "loading" and str(m.get("_history_state")) != "loading":
			break
		await _frames(1)
	await _frames(2)


func _find_back(n: Node) -> Control:
	## A visible BACK key anywhere under n (45B: the keys sit on the page's Stage).
	for c in n.get_children():
		if c is Button and (c as Button).is_visible_in_tree() and str(c.text).contains("BACK"):
			return c
		var d := _find_back(c)
		if d != null:
			return d
	return null


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _frames(40)
	m = main.menu_layer
	var tabs_seen := 0
	for from in FROM:
		for tab in TAB_PAGE:
			m.call("show_" + from)
			await _settle()
			if not is_instance_valid(m.nav_bar) or not m.nav_bar.buttons.has(tab):
				continue                                # a phone's slim sub-page: no tab bar (BACK only)
			tabs_seen += 1
			await _tap(m.nav_bar.buttons[tab])
			check(m._page == TAB_PAGE[tab], "from %s, one tap on %s lands on %s (got %s)" % [from, tab.to_upper(), TAB_PAGE[tab], m._page])
	check(tabs_seen >= 16, "the tab bar was there to tap (%d taps)" % tabs_seen)   # 4 tabs (GUIDE) since 2026-11-05
	# BACK: a page opened from another goes back where it came from (Daniele's 0.22.0 test). 45B: the remake keeps a BACK key
	# on MATCH SETUP and JOIN only (sizes.json); LEADERBOARD / ACCOUNT / CHALLENGES / SETTINGS go back through the page's
	# own way back (shell_back: Android back / Esc), and their PROFILE sub-tabs / the nav (checked above).
	for path in [["main", "setup"], ["main", "options"], ["profile", "leaderboard"], ["profile", "account"], ["armies", "challenges"]]:
		for p in path:
			m.call("show_" + p)
			await _settle()
		var back: Control = null
		if is_instance_valid(m.top_bar):
			back = _find_back(m.top_bar)
		if back == null:
			back = _find_back(m.content)
		if back != null:
			await _tap(back)
		elif m.shell_back.is_valid():
			m.bar_back()
			await _frames(6)
		else:
			check(false, "a way back from %s" % " > ".join(path))
			continue
		var want: String = TAB_PAGE.get(path[path.size() - 2], path[path.size() - 2])
		if path[path.size() - 2] == "main":
			want = "home"
		check(m._page == want, "%s: %s lands on %s (got %s)" % [" > ".join(path), "one tap on BACK" if back != null else "back", want, m._page])
	print("test_ui_nav: ", "PASS" if failures == 0 else "%d FAILED" % failures, " (%d tab taps)" % tabs_seen)
	get_tree().quit(1 if failures > 0 else 0)
