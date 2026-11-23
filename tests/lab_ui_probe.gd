extends SceneTree
## LAB UI probe (lab4 job 6: four small UI fixes). A dev tool, not a suite. Headless, through the lab guard:
##   Godot --headless --path . --script res://tests/lab_ui_probe.gd -- --mobile
## Phones (pt, notch): 844 x 390 (47) and 812 x 375 (44), at 2 px per pt. Prints one line per check, "BAD" on a failure, and
## "UI PROBE: <n> BAD" at the end (exit code = BAD count).
##   MENU   every LAB card (every page) and every CHOICE SHEET: each label fits its box (no hidden line, no clipped one-liner),
##          every font >= 12.5 pt, everything on screen.
##   QUOTA  card QUOTA BY TIER: the score readout's digit height (pt), its rect, and what it touches among the HUD pieces.
##   OVER   the lab overlay folded / unfolded: its rect, what it touches (HUD pieces + node badges); hidden under the pause menu.
##   TURN   the match started in portrait (390 x 844) then turned to 844 x 390, and started on a stale pt size (the page's CSS
##          size settling after the canvas): the HUD scale and the key HUD rects at the final size.
##   MTURN  the same for the LAB screen.
const LabCards := preload("res://scripts/lab_cards.gd")
const LabMenu := preload("res://scripts/lab_menu.gd")
const LabOverlay := preload("res://scripts/lab_overlay.gd")
const PHONES := [[844.0, 390.0, 47.0], [812.0, 375.0, 44.0]]
var bad := 0


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _say(ok: bool, line: String) -> void:
	if not ok:
		bad += 1
	print(("ok   " if ok else "BAD  ") + line)


func _phone(pw: float, ph: float, notch: float) -> void:
	UiKit.test_pt_h = ph
	root.size = Vector2i(int(pw * 2.0), int(ph * 2.0))
	await _frames(3)
	var vp := root.get_visible_rect().size
	var ppp := UiKit.pt_per_px(vp)
	UiKit.test_insets = Vector4(notch / ppp, 0.0, notch / ppp, 0.0)


func _ppp() -> float:
	return UiKit.pt_per_px(root.get_visible_rect().size)


func _r(c: Control) -> String:
	var k := _ppp()
	var r := Rect2(c.global_position * k, c.size * k)
	return "(%d,%d %dx%d pt)" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


func _labels(c: Node, out: Array) -> void:
	if c is CanvasItem and not (c as CanvasItem).visible:
		return
	if c is Label:
		out.append(c)
	for k in c.get_children():
		_labels(k, out)


func _check_labels(where: String, top: Control) -> void:
	var vp := root.get_visible_rect().size
	var ppp := _ppp()
	var ls := []
	_labels(top, ls)
	var worst := ""
	var n_bad := 0
	var lo_pt := 99.0
	for l: Label in ls:
		if l.text.strip_edges() == "":
			continue
		var fs := l.get_theme_font_size("font_size")
		lo_pt = minf(lo_pt, fs * ppp)
		var why := ""
		if fs * ppp < 12.49:
			why = "font %.1f pt" % (fs * ppp)
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			if l.get_visible_line_count() < l.get_line_count():
				why = "%d of %d lines" % [l.get_visible_line_count(), l.get_line_count()]
		elif l.clip_text:
			var w := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > l.size.x + 1.0:
				why = "clipped %.0f of %.0f pt" % [l.size.x * ppp, w * ppp]
		var g := Rect2(l.global_position, l.size)
		if not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(g):
			why = "off screen"
		if why != "":
			n_bad += 1
			worst += "  [%s: %s]" % [l.text.substr(0, 28).replace("\n", " "), why]
	_say(n_bad == 0, "%s labels %d, smallest %.1f pt%s" % [where, ls.size(), lo_pt, worst])


func _run() -> void:
	for ph in PHONES:
		await _menu(ph)
	for ph in PHONES:
		await _match(ph)
	for ph in PHONES:
		for cid in ["gat", "count", "hop", "relay-kill", "clus-13"]:
			await _over_only(ph, cid)
	await _turn()
	await _mturn()
	print("UI PROBE: %d BAD" % bad)
	LabMenu.reset_card()
	quit(bad)


func _lab_menu() -> Node:
	for c in current_scene.get_children():
		if c.get_script() == LabMenu:
			return c
	return null


func _menu(phone: Array) -> void:
	await _phone(phone[0], phone[1], phone[2])
	LabMenu.reset_card()
	load("res://scripts/main.gd").relaunch = {}
	change_scene_to_file("res://main.tscn")
	await _frames(20)
	var lm = _lab_menu()
	if lm == null:
		_say(false, "MENU %dx%d: no LAB screen" % [phone[0], phone[1]])
		return
	for p in range(6):
		lm.page = p
		lm._build()
		if lm.page != p:
			break
		await _frames(2)
		_check_labels("MENU %dx%d page %d" % [phone[0], phone[1], p + 1], lm._root)
	for c in LabCards.CARDS:
		if (c.get("choices", []) as Array).is_empty():
			continue
		lm._sheet(c)
		await _frames(2)
		_check_labels("MENU %dx%d sheet %s" % [phone[0], phone[1], c["id"]], lm._root)
	lm._build()


func _start(card_id: String, frames := 60) -> Node:
	var card := LabCards.find(card_id)
	LabMenu.picks = {}
	LabMenu.apply_card(card)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1",
			"map": LabCards.map_path(str(card["map"]))}
	change_scene_to_file("res://main.tscn")
	await _frames(frames)
	return current_scene


func _overlay(m: Node) -> Node:
	for c in m.get_children():
		if c.get_script() == LabOverlay:
			return c
	return null


func _hud_pieces(h) -> Dictionary:
	var out := {}
	for k in ["top_panel", "side_panel", "dock", "pause_button", "music_button", "map_title", "version_label", "status_label"]:
		var c = h.get(k)
		if c != null and is_instance_valid(c) and (c as Control).visible and (c as Control).is_visible_in_tree():
			out[k] = Rect2((c as Control).global_position, (c as Control).size)
	return out


func _badges(h) -> Dictionary:
	var out := {}
	for id in h.badges:
		var p: Control = h.badges[id]["panel"]
		if p.visible and (h.badges[id]["label"] as Control).visible:   # (drawn by the badge layer: the panel itself may sit in a hidden parent)
			out["badge %s" % str(id)] = Rect2(p.global_position, p.size)
	return out


func _touches(r: Rect2, pieces: Dictionary) -> String:
	var hit := PackedStringArray()
	for k in pieces:
		if (pieces[k] as Rect2).intersects(r):
			hit.append(k)
	return ", ".join(hit)


func _match(phone: Array) -> void:
	await _phone(phone[0], phone[1], phone[2])
	var m := await _start("quota")
	var h = m.hud
	var tag := "%dx%d" % [phone[0], phone[1]]
	var ppp := _ppp()
	var vp := root.get_visible_rect().size
	var screen := Rect2(Vector2.ZERO, vp)
	var top_dump := PackedStringArray()                # what the top band holds (y < 80 pt)
	for c in h.root.get_children():
		if c is Control and (c as Control).visible and (c as Control).global_position.y * ppp < 80.0 and (c as Control).size.x * ppp < 600.0:
			top_dump.append("%s %s" % [c.name if not str(c.name).begins_with("@") else c.get_class(), _r(c)])
	print("     TOP %s: %s" % [tag, " | ".join(top_dump)])
	# QUOTA readout
	var q: Control = h.get("_quota_box") if h.get("_quota_box") != null else h.get("_quota_label")
	if q == null or not q.is_visible_in_tree():
		_say(false, "QUOTA %s: no readout shown" % tag)
	else:
		var dl: Label = h.get("_quota_score") if h.get("_quota_score") != null else h.get("_quota_label")
		var fs := dl.get_theme_font_size("font_size")
		var digit_pt := fs * ppp * (0.643 if dl.get_theme_font("font") == UiKit.BODY else 0.70)   # digit height: Rajdhani 0.643 em, Russo One ~0.70 em
		var r := Rect2(q.global_position, q.size)
		var pieces := _hud_pieces(h)
		pieces.merge(_badges(h))
		var hit := _touches(r, pieces)
		_say(digit_pt >= 12.5 and hit == "" and screen.encloses(r), "QUOTA %s digits %.1f pt (font %.1f pt) %s text '%s' touches [%s]" % [
				tag, digit_pt, fs * ppp, _r(q), dl.text, hit])
	# OVERLAY folded / unfolded / paused
	var ov = _overlay(m)
	if ov == null:
		_say(false, "OVER %s: no overlay" % tag)
		return
	var pieces2 := _hud_pieces(h)
	pieces2.merge(_badges(h))
	if q != null and q.is_visible_in_tree():
		pieces2["quota"] = Rect2(q.global_position, q.size)
	for open in [false, true]:
		ov.open = open
		ov._refresh()
		await _frames(2)
		var p: Control = ov._panel
		var r2 := Rect2(p.global_position, p.size)
		var hit2 := _touches(r2, pieces2)
		var hud_hit2 := _touches(r2, _hud_pieces(h))
		var under2: bool = ov.layer < h.layer
		_say(screen.encloses(r2) and p.visible and hud_hit2 == "" and (hit2 == "" or (open and under2)), "OVER %s %s %s touches [%s]%s" % [
				tag, "unfolded" if open else "folded", _r(p), hit2, (" - drawn under them (layer %d < HUD %d)" % [ov.layer, h.layer]) if hit2 != "" and under2 else ""])
	h.pause_menu()
	await _frames(3)
	var pv: bool = ov._panel.is_visible_in_tree()
	_say(not pv, "OVER %s under the pause menu: overlay %s" % [tag, "SHOWN" if pv else "hidden"])
	h.pause_panel.visible = false
	m.paused = false
	await _frames(3)
	_say(ov._panel.is_visible_in_tree(), "OVER %s after RESUME: overlay %s" % [tag, "shown" if ov._panel.is_visible_in_tree() else "HIDDEN"])
	ov.open = false


func _hud_report(tag: String, m: Node) -> void:
	var h = m.hud
	var vp := root.get_visible_rect().size
	var ppp := _ppp()
	var want := UiKit.hud_px_per_pt(vp, true)
	var clock_pt: float = h.stats_label.get_theme_font_size("font_size") * ppp
	var pieces := _hud_pieces(h)
	var off := PackedStringArray()
	for k in pieces:
		if not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(pieces[k]):
			off.append(k)
	var built: float = float(m.get("_hud_built_ppt")) if m.get("_hud_built_ppt") != null else -1.0
	var ratio := built / want if built > 0.0 else -1.0
	_say(off.is_empty() and clock_pt < 30.0 and (ratio < 0.0 or absf(ratio - 1.0) < 0.03),
			"%s view %dx%d pt  clock %.1f pt  hud scale built/now %.2f  top %s  dock %s  side %s  off screen [%s]" % [
			tag, int(vp.x * ppp), int(vp.y * ppp), clock_pt, ratio, _r(h.top_panel), _r(h.dock), _r(h.side_panel), ", ".join(off)])


func _turn() -> void:
	# portrait first, then the phone turns
	await _phone(390.0, 844.0, 0.0)
	var m := await _start("quota", 40)
	await _phone(844.0, 390.0, 47.0)
	await _frames(20)
	await _hud_report("TURN portrait->844x390", current_scene)
	# landscape canvas, but the page's pt size still stale (pt_per_px too small = oversized), settling 20 frames later
	await _phone(844.0, 390.0, 47.0)
	UiKit.test_pt_h = 180.0
	m = await _start("quota", 40)
	UiKit.test_pt_h = 390.0
	await _frames(20)
	await _hud_report("TURN stale-pt->844x390", current_scene)


func _mturn() -> void:
	await _phone(390.0, 844.0, 0.0)
	LabMenu.reset_card()
	load("res://scripts/main.gd").relaunch = {}
	change_scene_to_file("res://main.tscn")
	await _frames(20)
	await _phone(844.0, 390.0, 47.0)
	await _frames(10)
	var lm = _lab_menu()
	if lm:
		_check_labels("MTURN portrait->844x390", lm._root)
	UiKit.test_pt_h = 180.0
	lm._build()
	await _frames(3)
	UiKit.test_pt_h = 390.0
	await _frames(10)
	lm = _lab_menu()
	var fs: int = lm._font_px(12.5)
	var lab_title_pt := 0.0
	for c in lm._root.get_children():
		if c is Label and (c as Label).text == "OOZE LAB":
			lab_title_pt = (c as Label).get_theme_font_size("font_size") * _ppp()
	_say(absf(lab_title_pt - 20.0) < 1.0, "MTURN stale-pt->844x390 title %.1f pt (20 wanted)" % lab_title_pt)
	_check_labels("MTURN stale-pt->844x390", lm._root)


func _over_only(phone: Array, card_id: String) -> void:
	await _phone(phone[0], phone[1], phone[2])
	var m := await _start(card_id)
	var h = m.hud
	var ov = _overlay(m)
	var vp := root.get_visible_rect().size
	var pieces := _hud_pieces(h)
	var bs := _badges(h)
	pieces.merge(bs)
	for open in [false, true]:
		ov.open = open
		ov._refresh()
		await _frames(2)
		var p: Control = ov._panel
		var r := Rect2(p.global_position, p.size)
		var hit := _touches(r, pieces)
		var hud_hit := _touches(r, _hud_pieces(h))
		var under: bool = ov.layer < h.layer           # the readout draws UNDER the HUD: a badge it touches stays on top
		var ok: bool = Rect2(Vector2.ZERO, vp).encloses(r) and hud_hit == "" and (hit == "" or (open and under))
		_say(ok, "OVER %dx%d %s %s %s (badges %d) touches [%s]%s" % [phone[0], phone[1],
				card_id, "unfolded" if open else "folded", _r(p), bs.size(), hit, (" - drawn under them (layer %d < HUD %d)" % [ov.layer, h.layer]) if hit != "" and under else ""])
	ov.open = false
