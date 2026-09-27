extends Node
## Headless campaign page check, run as a scene (the Net autoload that hud.gd needs exists only then):
##   Godot --headless --path . res://tests/test_campaign_page.tscn
## Exit code 0 = all passed. CAMPAIGN-DESIGN.md §3: the CampaignPage at a landscape phone (844 x 390 pt, the project's
## canvas_items / expand stretch) and at desktop 1280 x 720: every district opens, every visible Button is >= 44 pt on
## both sides (phone) and every Label >= 12.5 pt, nothing sits off the 1280 x 720 canvas; a mission card for a playable
## mission has an enabled PLAY that emits play_pressed, an IN DEVELOPMENT one a disabled button naming what it needs;
## the side relay swings; Campaign.last_run is consumed (stars pop, the bridge extends); a done district collapses
## once (mark_seen), pans on and stays a memorial; tap to skip.

var failures := 0
var page: CampaignPage
var played := ""


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _frames(n := 3) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _new_page(phone: bool) -> void:
	if is_instance_valid(page):
		page.queue_free()
		await _frames(2)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(844, 390) if phone else Vector2i(1280, 720)
	page = CampaignPage.new()
	page.set_mobile(phone)
	page.set_faction("vex")
	page.play_pressed.connect(func(k): played = k)
	get_tree().root.add_child(page)
	await _frames(4)


func _controls(n: Node, out: Array, scrolled := false) -> void:
	## Visible controls as [control, inside a scroll list] (a scrolled row may sit below the list's fold).
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			out.append([c, scrolled])
		if c is Node and not (c is SubViewportContainer):
			_controls(c, out, scrolled or c is ScrollContainer)


func _sizes_ok(tag: String, phone: bool) -> void:
	## Every visible Button >= 44 pt both ways (phone), every Label >= 12.5 pt, all inside the canvas.
	var vp := page.get_viewport().get_visible_rect().size
	var pt := 390.0 / vp.y                       # viewport unit -> pt on the 844 x 390 phone
	var canvas := Rect2(page.content.position, CampaignPage.CANVAS * page.content.scale.x).grow(1.0)
	var small := []
	var tiny := []
	var off := []
	var ctrls := []
	_controls(page.content, ctrls)
	var buttons := 0
	for pair in ctrls:
		var c: Control = pair[0]
		var r := (c as Control).get_global_rect()
		if c is Button:
			buttons += 1
			if phone and minf(r.size.x, r.size.y) * pt < 43.5:
				small.append("%s %s" % [(c as Button).text.replace("\n", " "), r.size * pt])
		if c is Label and phone:
			var fs := (c as Label).get_theme_font_size("font_size") * (c as Control).get_global_transform().get_scale().x * pt
			if fs < 12.4:
				tiny.append("%s %.1f" % [(c as Label).text, fs])
		if (c is Button or c is Label or c is ScrollContainer) and not pair[1] and not canvas.encloses(r):
			off.append("%s %s" % [(c.text if "text" in c else c.name), r])
	check(buttons > 0, "%s: buttons on the page (%d)" % [tag, buttons])
	if phone:
		check(small.is_empty(), "%s: every button >= 44 pt %s" % [tag, str(small)])
		check(tiny.is_empty(), "%s: every label >= 12.5 pt %s" % [tag, str(tiny)])
	check(off.is_empty(), "%s: nothing off the canvas %s" % [tag, str(off)])


func _run() -> void:
	Campaign.path = "user://test_campaign_page.cfg"
	Campaign.use_progression(null)
	Campaign.all_open = false
	Campaign.reset_progress()
	for phone in [true, false]:
		var tag := "phone" if phone else "desktop"
		await _new_page(phone)
		var n := Campaign.districts("vex").size()
		check(page.current_district() == 0, "%s: a fresh campaign opens on District 1" % tag)
		for i in range(n):
			await page.show_district(i, false)
			await _frames(3)
			_sizes_ok("%s district %d" % [tag, i + 1], phone)
		# a playable mission's card
		page.open_card("vex:01")
		await _frames(3)
		var pb: Button = page._card.get_meta("play")
		check(pb != null and not pb.disabled and pb.text == "PLAY", "%s: 01's card has an enabled PLAY" % tag)
		_sizes_ok("%s card 01" % tag, phone)
		played = ""
		pb.pressed.emit()
		await _frames(2)
		check(played == "vex:01", "%s: PLAY emits play_pressed(vex:01)" % tag)
		# a locked one, and an IN DEVELOPMENT one (with every mission open)
		page.open_card("vex:02")
		await _frames(2)
		check((page._card.get_meta("play") as Button).disabled, "%s: a locked mission's PLAY is disabled" % tag)
	Campaign.all_open = true
	await _new_page(true)
	page.open_card("vex:04")
	await _frames(3)
	var dev: Button = page._card.get_meta("play")
	check(dev.disabled and dev.text.begins_with("IN DEVELOPMENT") and dev.text.contains("flooding tides"),
			"IN DEVELOPMENT card: disabled, names what it needs (%s)" % dev.text.replace("\n", " / "))
	_sizes_ok("phone card 04 (in development)", true)
	page.close_card()
	# the side relay swings its deck over, then opens the card
	await page.show_district(0, false)
	var rr: Dictionary = page._districts[0]["relays"]["vex:s1"]
	var rot0 := (rr["pivot"] as Node3D).rotation.y
	page._relay_tapped("vex:s1")
	await _wait(CampaignPage.SWING_TIME + 0.4)
	check(absf((rr["pivot"] as Node3D).rotation.y - Rules.heading(rr["d"])) < 0.01 and absf(rot0 - Rules.heading(rr["d"])) > 0.5,
			"relay tap: the deck swings from parked onto the side mission's line")
	check(page.card_key() == "vex:s1", "relay tap: the side mission's card opens")
	Campaign.all_open = false
	# after a mission: last_run is consumed, the stars pop, the bridge to 02 extends
	var sm := Campaign.record("vex:01", {"won": true, "time": 200.0, "stars": 3, "objective": true})
	check(str(sm["reward"]["state"]) == "earned", "record: 3 stars + objective, no wallet yet -> earned")
	Campaign.last_run = {"key": "vex:01", "summary": sm}
	await _new_page(true)
	check(Campaign.last_run.is_empty(), "last_run consumed by the page")
	var br: Dictionary = page._districts[0]["bridges"]["vex:02"]
	check(float(br["p"]) < 1.0, "after the first win the bridge to 02 starts retracted (p %.2f)" % float(br["p"]))
	await _wait(3.2)
	check(float(br["p"]) >= 0.999, "... and extends (p %.2f)" % float(br["p"]))
	var plate = page._districts[0]["nodes"]["vex:01"]["plate"]
	check(plate != null and int(plate.stars) == 3, "01's plate shows 3 stars")
	# a done district collapses once, pans on, stays a memorial
	Campaign.record("vex:02", {"won": true, "time": 100.0, "stars": 2, "objective": false})
	var s3 := Campaign.record("vex:03", {"won": true, "time": 100.0, "stars": 1, "objective": false})
	check(bool(s3["district_done"]), "record: 03 finishes Dockside")
	await _new_page(true)
	check(page.busy() and page.current_district() == 0, "Dockside done, never seen: the collapse plays on open")
	await _wait(1.0)
	var g01: Node3D = page._districts[0]["groups"]["vex:01"]
	page.skip()
	await _wait(0.6)
	check(Campaign.was_seen("collapse:dockside"), "collapse: mark_seen(collapse:dockside)")
	check(page.current_district() == 1 and not page.busy(), "collapse (skipped): panned on to THE EXCHANGE")
	check(g01.position.y < -1.0 and g01.position.y > -10.0, "Dockside stays as a sunk memorial (y %.1f)" % g01.position.y)
	await _new_page(true)
	check(not page.busy() and bool(page._districts[0]["memorial"]), "seen once: no second collapse, memorial look")
	await page.show_district(0, false)
	await _frames(3)
	_sizes_ok("phone memorial", true)
	page.open_card("vex:01")
	await _frames(2)
	check(not (page._card.get_meta("play") as Button).disabled, "memorial missions stay replayable")
	page.queue_free()
	Campaign.reset_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.path))
	print("\n%s (%d failures)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)
