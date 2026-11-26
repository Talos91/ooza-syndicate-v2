extends CanvasLayer
## LAB BUILD (Rules.lab) debug overlay: a small readout, BOTTOM CENTRE of a match when that spot is clear (else the nearest clear
## spot: clear of the left vat sender, the right skill keys, the top band, the map / version labels and every node badge; drawn
## UNDER the HUD and hidden while a match screen such as PAUSE is up - lab4 job 6), starts folded to one line, tap it to unfold and fold. Build + card, camera distance and zoom relative to the whole-map fit,
## pitch, platform diameter in pt (tests/map_size_probe.gd _plat_pt), node / bridge count, shortest / longest deck (m),
## viewport in pt and px. Refreshed 4x a second (so zoom, resize and rotation show). Text >= 12.5 pt (UiKit.pt_per_px).

const LabMenu := preload("res://scripts/lab_menu.gd")
const LabCards := preload("res://scripts/lab_cards.gd")
const TEXT_PT := 12.5

var main: Node
var open := false                                # starts folded to its one line (tap unfolds, tap folds)
var _panel: PanelContainer
var _label: Label
var _t := 0.0
var _decks := Vector2(-1.0, -1.0)               # shortest, longest deck (m), measured once from the map
var _joints := 0                                 # LAB JOINT (WP3): joint links (counted apart from the bridges)
var _hops := Vector2(-1.0, -1.0)                # vat-to-vat walk across a joint (s): shortest, longest
var _placed := false                             # a spot was chosen (kept while it stays clear)


func setup(m: Node) -> void:
	main = m
	layer = 0                                     # lab4 job 6: UNDER the HUD (1): never over a badge, the pause menu or a screen
	_panel = PanelContainer.new()
	var box := UiKit.sb(Color(UiKit.BASE, 0.78), Color(UiKit.CYAN, 0.6), 1, 4)
	box.set_content_margin_all(6.0)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_input)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_override("font", UiKit.BODY)
	_label.add_theme_color_override("font_color", UiKit.INK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_decks = deck_range(m.map)
	_joints = joint_count(m.map)
	_hops = m.sim.joint_hops() if _joints > 0 else Vector2(-1.0, -1.0)
	_refresh()


static func joint_count(map: Dictionary) -> int:
	return (map.get("edges", []) as Array).filter(func(e): return e.get("joint", false) == true).size()


static func deck_range(map: Dictionary) -> Vector2:
	## [shortest, longest] deck in metres: each edge's walked deck (deckMetres, else its baked span minus the piers).
	## Joints (no deck) are left out.
	var lo := INF
	var hi := -INF
	var lay: Array = (map.get("layout", {}) as Dictionary).get("edges", [])
	var edges: Array = map.get("edges", [])
	for k in range(edges.size()):
		var e: Dictionary = edges[k]
		if e.get("joint", false) == true:
			continue
		var d := -1.0
		if e.get("deckMetres") != null:
			d = float(e["deckMetres"])
		elif k < lay.size():
			var g: Dictionary = lay[k]
			d = float(g.get("L", 0.0)) - float(g.get("p0", 0.0)) - float(g.get("p1", 0.0))
		if d >= 0.0:
			lo = minf(lo, d)
			hi = maxf(hi, d)
	return Vector2(lo, hi) if lo <= hi else Vector2(-1.0, -1.0)


static func num(v: float) -> String:
	## 8 -> "8", 0.9 -> "0.9", 1.5 -> "1.5" (readouts of the lab options).
	return str(int(round(v))) if absf(v - round(v)) < 0.001 else str(snappedf(v, 0.01))


static func rules_line(sim) -> String:
	## LAB WP4 rule options, when they matter on this board: the quota score, "gat: own platform" while a Googatling stands.
	var parts := PackedStringArray()
	if Rules.quota:
		parts.append("quota A %d - B %d, %d left" % [sim.quota_of("A"), sim.quota_of("B"), sim.quota_left()])
	if not is_equal_approx(Rules.unit_speed(), 1.0):       # lab4 job 2: CLUSTER HOP speed card
		parts.append("speed x%s" % num(Rules.unit_speed()))
	if (sim.nodes as Array).any(func(n): return n["structure"] == "machinegoon"):
		var g := PackedStringArray()
		if float(Rules.lab_opt("gat_range")) > 0.0:         # lab4 job 5: the Googatling card's choices
			g.append("reach %s m" % num(Sim.gat_reach()))
		elif bool(Rules.lab_opt("gat_own_platform")):
			g.append("own platform")
		if not is_equal_approx(float(Rules.lab_opt("gat_power")), 1.0):
			g.append("power x%s" % num(float(Rules.lab_opt("gat_power"))))
		if not is_equal_approx(Sim.gat_ammo(), 1.0):
			g.append("ammo free" if Sim.gat_ammo() <= 0.0 else "ammo 1 per %s kills" % num(1.0 / Sim.gat_ammo()))
		if not g.is_empty():
			parts.append("gat: " + ", ".join(g))
	return "  ·  ".join(parts)


func plat_pt() -> float:
	## Platform diameter (screen-horizontal axis) in pt at the view's aim point (tests/map_size_probe.gd _plat_pt).
	var cam: Camera3D = main.cam
	if cam == null or not cam.is_inside_tree() or (main._view_fit as Array).is_empty():   # (before the first fit: no view yet)
		return 0.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var p: Vector3 = main.cam_target
	var a := cam.unproject_position(p - right * Rules.R)
	var b := cam.unproject_position(p + right * Rules.R)
	return (b - a).length() * UiKit.pt_per_px(vp)


func text() -> String:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ppp := UiKit.pt_per_px(vp)
	var win := Vector2(get_window().size)
	var card := LabMenu.card_id if LabMenu.card_id != "" else "-"
	var tag := LabMenu.pick_tag(LabCards.find(LabMenu.card_id)) if LabMenu.card_id != "" else ""
	if tag != "":                                    # CHOICE SHEET picks (lab4): "hop x0.9", "gat 8 m · x1.5 · 1 PER 2"
		card += " " + tag
	var head := "LAB %s  ·  CARD %s  ·  %s" % [Rules.VERSION, card, str(main.map.get("code", "?"))]
	if not open:
		var vf = main.get("vat_count")
		if vf != null:                               # card COUNT SIZE: the measured digit in the folded line too
			head += "  ·  digit %.1f pt" % vf.digit_pt(main.cam)
		return head + "  (tap)"
	var fit: float = float(main._view_fit[1]) if main._view_fit.size() > 1 else float(main.cam_dist)
	var zoom := fit / maxf(float(main.cam_dist), 0.001)
	var lines := PackedStringArray([head])
	lines.append("cam %.1f m  ·  zoom x%.2f of fit (map x%.2f)  ·  pitch %.0f deg" % [float(main.cam_dist), zoom,
			MapCamera.zoom_for(str(main.map.get("code", ""))), float(main.cam_pitch)])
	var bridges: int = (main.map.get("edges", []) as Array).size() - _joints
	lines.append("platform %.1f pt  ·  nodes %d  ·  bridges %d%s" % [plat_pt(), (main.sim.nodes as Array).size(), bridges,
			(" + joints %d" % _joints) if _joints > 0 else ""])
	var vc = main.get("vat_count")
	if vc != null:                                   # lab4 job 3: card COUNT SIZE - the vat-screen digit at the aim
		lines.append("digit %.1f pt (vat screen x%s, %.2f m)" % [vc.digit_pt(main.cam), num(vc.scale_k), vc.digit_height_m()])
	var deck_line := "decks %s" % (("%.1f - %.1f m" % [_decks.x, _decks.y]) if _decks.x >= 0.0 else "-")
	if _hops.x >= 0.0:
		deck_line += "  ·  hop: %s s" % (("%.1f" % _hops.x) if absf(_hops.y - _hops.x) < 0.05 else ("%.1f - %.1f" % [_hops.x, _hops.y]))
	lines.append(deck_line)
	var rl := rules_line(main.sim)
	if rl != "":
		lines.append(rl)
	lines.append("view %d x %d pt  ·  %d x %d px" % [int(round(vp.x * ppp)), int(round(vp.y * ppp)), int(win.x), int(win.y)])
	return "\n".join(lines)


func _avoid_rects() -> Array[Rect2]:
	## The HUD pieces the readout must stay clear of (lab4 job 6: the node badges and the top band too): the left vat sender,
	## the right skill column, the bottom-left map label, the bottom-right version label, the score capsule + status line, the
	## top-right buttons, the quota pill, every node badge shown (hud.gd places them; read live so a layout change moves us).
	var out: Array[Rect2] = []
	var h = main.hud if "hud" in main else null
	if h == null or not is_instance_valid(h):
		return out
	var pad := 4.0 / maxf(UiKit.pt_per_px(get_viewport().get_visible_rect().size), 0.0001)
	for ctl in [h.side_panel, h.dock, h.map_title, h.version_label, h.top_panel, h.pause_button, h.music_button,
			h.get("debug_button"), h.get("chat_button"), h.get("_quota_box"), h.get("lab_tube")]:
		if ctl != null and is_instance_valid(ctl) and (ctl as Control).visible:
			out.append(Rect2((ctl as Control).global_position, (ctl as Control).size).grow(pad))
	if h.status_label and h.status_label.visible and h.status_label.text != "":
		out.append(Rect2(h.status_label.global_position, h.status_label.size).grow(pad))
	for id in h.badges:
		var b: Dictionary = h.badges[id]
		var p: Control = b["panel"]
		if p.visible and (b["label"] as Control).visible:
			out.append(Rect2(p.global_position, p.size).grow(pad))
	return out


static func _hit_area(r: Rect2, avoid: Array[Rect2]) -> float:
	var a := 0.0
	for o in avoid:
		a += r.intersection(o).get_area()
	return a


func _screen_open() -> bool:
	## A match screen (pause, settings, the end card, out, reconnect) is up: the readout hides (lab4 job 6).
	var h = main.hud if "hud" in main else null
	if h == null or not is_instance_valid(h):
		return false
	for k in ["pause_panel", "end_panel", "out_panel", "reconnect_panel"]:
		var c = h.get(k)
		if c != null and is_instance_valid(c) and (c as Control).visible:
			return true
	return false


func _refresh() -> void:
	var off := _screen_open()
	_panel.visible = not off
	if off:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var u := 1.0 / maxf(UiKit.pt_per_px(vp), 0.0001)
	_label.add_theme_font_size_override("font_size", int(ceil(TEXT_PT * u)))
	_label.text = text()
	var ins := UiKit.safe_insets(vp)
	var margin := 12.0 * u                          # the panel's own content margins (6 pt each side)
	var avoid := _avoid_rects()
	# the free span between the left sender and the right skill column (the readout never goes over either)
	var h = main.hud
	var lb := ins.x + 4.0 * u
	var rb := vp.x - ins.z - 4.0 * u
	if h.side_panel and h.side_panel.visible:
		lb = maxf(lb, h.side_panel.global_position.x + h.side_panel.size.x + 4.0 * u)
	if h.dock and h.dock.visible:
		rb = minf(rb, h.dock.global_position.x - 4.0 * u)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2.ZERO
	var nat := _label.get_combined_minimum_size()
	var w := minf(nat.x, maxf(rb - lb - margin, 120.0 * u))
	if w < nat.x - 0.5:                              # narrower than its one-line width: wrapped
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size = Vector2(w, 0.0)
	var sz := Vector2(w + margin, _label.get_combined_minimum_size().y + margin)
	# where: bottom centre first, else slid along the bottom, else under the top band, else stepped up from the bottom - the first spot
	# that touches nothing; the current spot is kept while it stays clear (no hopping); none clear = the least covered one.
	# The layer sits UNDER the HUD (layer 0 < 1), so a badge or a menu is never hidden by the readout even then.
	var top_y := float(h.top_used()) + 4.0 * u if h.has_method("top_used") else ins.y + 70.0 * u
	var q = h.get("_quota_box")
	if q != null and (q as Control).visible:
		top_y = maxf(top_y, (q as Control).global_position.y + (q as Control).size.y + 4.0 * u)
	var bot_y := vp.y - ins.w - 4.0 * u - sz.y
	var xs: Array[float] = [(vp.x - sz.x) * 0.5]
	var step := 24.0 * u
	var k := 1
	while true:
		var l := (vp.x - sz.x) * 0.5 - k * step
		var r := (vp.x - sz.x) * 0.5 + k * step
		if l < lb and r + sz.x > rb:
			break
		if l >= lb:
			xs.append(l)
		if r + sz.x <= rb:
			xs.append(r)
		k += 1
	var spots: Array[Vector2] = []
	var ys: Array[float] = [bot_y, top_y]              # the bottom edge, under the top band, then every 12 pt up from the bottom
	var yy := bot_y - 12.0 * u
	while yy > top_y:
		ys.append(yy)
		yy -= 12.0 * u
	for y0 in ys:
		for xx in xs:
			spots.append(Vector2(xx, y0))
	var cur := Rect2(_panel.position, sz)
	var best := spots[0]
	var best_a := INF
	if _placed and absf(cur.position.x - clampf(cur.position.x, lb, rb - sz.x)) < 0.5 and cur.position.y >= top_y - 0.5 			and cur.end.y <= vp.y - ins.w + 0.5 and _hit_area(cur, avoid) <= 0.0:
		best = cur.position
	else:
		for p in spots:
			var a := _hit_area(Rect2(p, sz), avoid)
			if a < best_a:
				best_a = a
				best = p
				if a <= 0.0:
					break
	_placed = true
	_panel.position = best
	_panel.reset_size()


func _process(delta: float) -> void:
	_t += delta
	if _screen_open() == _panel.visible:            # a screen opened / closed: hide / show at once
		_t = 0.25
	if _t >= 0.25:
		_t = 0.0
		_refresh()


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:   # (a phone's tap arrives as this too)
		open = not open
		_refresh()
		_panel.accept_event()
	elif ev is InputEventScreenTouch or ev is InputEventMouseButton:   # the board never gets a tap meant for the readout
		_panel.accept_event()
