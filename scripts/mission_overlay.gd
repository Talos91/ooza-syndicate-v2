class_name MissionOverlay
extends CanvasLayer
## The campaign mission's screens (CAMPAIGN-DESIGN.md §4 / §5), over the match HUD, fed from a MissionDirector:
##   show_briefing()        the briefing card - the speakers' lines (Campaign.fill), objective, optional objective,
##                          par; the match stays paused until START (signal start_pressed)
##   the in-match strip     under the HUD's clock (below its Last Stand status line when that shows): the objective
##                          with live progress (glows as it moves), the par clock, the optional objective with a
##                          live tick / cross - drawn marks, not font glyphs (the web build has no symbol fallback)
##   show_end(result, summary, xp)   the mission's win_line / lose_line, then the result screen: the stars pop in
##                          one by one with their rule text (unearned ones grey), the optional objective, the reward
##                          line (Campaign.record's summary.reward.state), the unlock line, an XP line when
##                          Progression returned one; NEXT MISSION / RETRY / CAMPAIGN (signal action(id))
## Sizes are in points of a 390-pt landscape phone on mobile (taps >= 44 pt, text >= 12.5 pt), like coach_overlay.gd.

signal start_pressed
signal action(id: String)                            # "next" / "retry" / "campaign"

const PHONE_PT_H := 390.0
const GOLD := Color("ffd23f")
const GOOD := Color("59e07a")
const BAD := Color("ff6b6b")
const DIM := Color("a6b2bb")
const TEXT := Color("e8f4f8")
const END_LINE_SECONDS := 2.4
const STAR_GAP := 0.4

var main: Node
var hud: Hud
var d: MissionDirector
var m: Dictionary = {}
var mobile := false
var accent := Color("00ddf2")
var rival_color := Color("ff6b6b")
var root: Control
var strip: PanelContainer
var _obj: Label
var _par: Label
var _opt: Label
var _opt_mark: Glyph
var _modal: Control                                  # the briefing / end line / result layer (dims the match)
var phase := ""                                      # brief / match / endline / result
var _end := {}                                       # {result, summary, xp}
var _end_t := 0.0
var _animated := false                               # the result screen's pop-in has played (a resize redraws it still)
var _vp := Vector2.ZERO
var _card: Control = null                            # the open card, re-centred each frame (wrapped text settles late)
var _card_y := 0.5


func setup(main_node: Node, director: MissionDirector, is_mobile: bool) -> void:
	main = main_node
	hud = main.get("hud")
	d = director
	m = director.m
	mobile = is_mobile
	layer = 3                                        # over the HUD (1)
	accent = Rules.seat_color(director.seat)
	rival_color = Rules.seat_color("B")
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_strip()
	get_viewport().size_changed.connect(_rebuild)


func u(n: float) -> float:
	## n points -> canvas units: a 390-pt phone on mobile; on desktop a fixed step close to the HUD's own sizes.
	var h := get_viewport().get_visible_rect().size.y if is_inside_tree() else 720.0
	return n * (h / PHONE_PT_H if mobile else 1.3)


# ---------------------------------------------------------------- building blocks
func _label(text: String, pt: float, color := TEXT, wrap_width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud.UI_FONT)
	l.add_theme_font_size_override("font_size", int(round(u(pt))))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap_width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_width, 0)
	return l


func _button(text: String, id: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Hud.UI_FONT)
	b.add_theme_font_size_override("font_size", int(round(u(15))))
	b.custom_minimum_size = Vector2(u(128), u(44))
	var normal := Hud.panel_style(accent if primary else Color("276578"))
	if primary:
		normal.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", Hud.panel_style(accent))
	var pressed := Hud.panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	var focus := Hud.panel_style(Color.WHITE)
	focus.bg_color = Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(func(): _on_button(id))
	return b


func _make_card(width: float, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := Hud.panel_style(border)
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.96)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(u(12))
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(width, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _vbox(gap: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(round(u(gap))))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hbox(gap: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(round(u(gap))))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _new_modal(dim: float) -> Control:
	if _modal:
		_modal.queue_free()
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0.0, 0.01, 0.02, dim)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing reaches the map or the HUD under it
	root.add_child(_modal)
	return _modal


func _centre(card: Control, y_frac := 0.5) -> void:
	## Centres a card on the screen (again every frame: wrapped labels settle their height a frame late).
	_card = card
	_card_y = y_frac
	var vp := get_viewport().get_visible_rect().size
	card.reset_size()
	var sz := card.get_combined_minimum_size()
	card.size = sz
	card.position = Vector2((vp.x - sz.x) / 2.0, clampf((vp.y - sz.y) * y_frac, u(6), maxf(vp.y - sz.y - u(6), u(6))))


func _speaker(who: String) -> Array:
	## [name, colour] for a brief line's speaker: the handler or the mission's rival.
	if who == "rival":
		return [str(Campaign.rival_of(m).get("name", "THE RIVAL")), rival_color]
	return [Campaign.HANDLER, accent]


func _mission_title() -> String:
	var dist := str(Campaign.district_of(d.key).get("name", "")) if d.key != "" else ""
	var kind := str(m.get("kind", "main"))
	var tag: String = {"side": "SIDE MISSION", "duel": "RIVAL DUEL", "finale": "FINALE"}.get(kind, "MISSION %s" % str(m.get("id", "")))
	return ("%s · %s" % [dist, tag]) if dist != "" else tag


# ---------------------------------------------------------------- briefing
func show_briefing() -> void:
	phase = "brief"
	strip.visible = false
	var vp := get_viewport().get_visible_rect().size
	var modal := _new_modal(0.62)
	var w := minf(vp.x - u(24), u(600))
	var card := _make_card(w, accent)
	modal.add_child(card)
	var col := _vbox(5)
	card.add_child(col)
	col.add_child(_label(_mission_title(), 12.5, DIM))
	col.add_child(_label(str(m.get("title", "")), 22, TEXT))
	col.add_child(_label(str(m.get("story", "")), 13, DIM, w - u(28)))
	var lines := _vbox(4)
	for pair in m.get("brief", []):
		var sp: Array = _speaker(str(pair[0]))
		var row := _hbox(8)
		var who := _label(str(sp[0]), 13, sp[1])
		who.custom_minimum_size = Vector2(u(96), 0)
		row.add_child(who)
		row.add_child(_label(Campaign.fill(str(pair[1]), m), 14, TEXT, w - u(28) - u(104)))
		lines.add_child(row)
	col.add_child(lines)
	col.add_child(_rule_line())
	col.add_child(_kv("OBJECTIVE", Campaign.objective_text(m), TEXT, w))
	if str(d.optional().get("text", "")) != "":
		col.add_child(_kv("OPTIONAL", str(d.optional()["text"]), TEXT, w))
	if d.par() > 0.0:
		col.add_child(_kv("PAR", "%s - win inside it for 2 stars, and keep every node you start with for 3" % MissionDirector.clock(d.par()), DIM, w))
	var buttons := _hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(_button("CAMPAIGN", "campaign"))
	var start := _button("START", "start", true)
	start.custom_minimum_size.x = u(170)
	buttons.add_child(start)
	col.add_child(buttons)
	_centre(card)
	card.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(card, "modulate", Color.WHITE, 0.25)


func _kv(k: String, v: String, color: Color, w: float) -> HBoxContainer:
	var row := _hbox(8)
	var kl := _label(k, 12.5, accent)
	kl.custom_minimum_size = Vector2(u(96), 0)
	row.add_child(kl)
	row.add_child(_label(v, 13.5, color, w - u(28) - u(104)))
	return row


func _rule_line() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(accent.r, accent.g, accent.b, 0.35)
	r.custom_minimum_size = Vector2(0, maxf(1.0, u(1)))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ---------------------------------------------------------------- the in-match strip
func _build_strip() -> void:
	strip = PanelContainer.new()
	var sb := Hud.panel_style(accent)
	sb.bg_color = Color(0.02, 0.05, 0.08, 0.78)
	sb.set_content_margin_all(u(2))
	sb.content_margin_left = u(10)
	sb.content_margin_right = u(10)
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = false
	root.add_child(strip)
	var col := _vbox(0)
	strip.add_child(col)
	_obj = _label("OBJECTIVE", 14, TEXT)
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_obj)
	var row := _hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_par = _label("PAR", 12.5, DIM)
	row.add_child(_par)
	_opt_mark = Glyph.new()
	_opt_mark.custom_minimum_size = Vector2(u(12.5), u(12.5))
	_opt_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_opt_mark)
	_opt = _label("", 12.5, TEXT)
	row.add_child(_opt)


func strip_bottom() -> float:
	## Where the objective strip ends (main fits the map under it, briefing or not).
	var y := u(4)
	if hud and hud.top_panel and hud.top_panel.visible:
		y = hud.top_panel.position.y + hud.top_panel.size.y + u(3)
	return y + strip.get_combined_minimum_size().y


func begin_match() -> void:
	phase = "match"
	if _modal:
		_modal.queue_free()
		_modal = null
	strip.visible = true
	strip.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(strip, "modulate", Color.WHITE, 0.4)


func _process(dt: float) -> void:
	if d == null or root == null:
		return
	if get_viewport().get_visible_rect().size != _vp:
		_vp = get_viewport().get_visible_rect().size
	if is_instance_valid(_card) and _card.is_inside_tree() and phase != "match":
		var sz := _card.get_combined_minimum_size()
		if _card.size != sz:
			_centre(_card, _card_y)
	if phase == "match":
		_sync_strip()
	elif phase == "endline":
		_end_t -= dt
		if _end_t <= 0.0:
			_show_result()


func _sync_strip() -> void:
	_obj.text = d.objective_line()
	var par := d.par_line()
	_par.text = par + ("   " if par != "" and d.optional_line() != "" else "")
	_opt.text = d.optional_line()
	_opt_mark.visible = _opt.text != ""
	var ok := d.optional_ok()
	_opt_mark.kind = "check" if ok else "cross"
	_opt_mark.color = GOOD if ok else BAD
	_opt_mark.queue_redraw()
	_opt.modulate = Color(1, 1, 1, 0.55) if d.optional_locked() else Color.WHITE
	_par.add_theme_color_override("font_color", BAD if d.lost_start or (d.sim and d.sim.time > d.par()) else DIM)
	var k := clampf(d.pulse / MissionDirector.PULSE, 0.0, 1.0)
	_obj.modulate = Color(1.0 + 0.9 * k, 1.0 + 0.9 * k, 1.0 + 0.4 * k)
	_obj.pivot_offset = _obj.size / 2.0
	_obj.scale = Vector2.ONE * (1.0 + 0.08 * k)
	strip.reset_size()
	strip.size = strip.get_combined_minimum_size()
	var vp := get_viewport().get_visible_rect().size
	var y := u(4)
	if hud and hud.top_panel and hud.top_panel.visible:
		y = hud.top_panel.position.y + hud.top_panel.size.y + u(3)
		if hud.status_label and hud.status_label.text != "":   # the Last Stand's status line keeps its place
			y = hud.status_label.position.y + hud.status_label.size.y + u(2)
	strip.position = Vector2((vp.x - strip.size.x) / 2.0, y)
	if hud and hud.notices:                                   # the HUD's toasts stack under the strip, not over it
		hud.notices.position.y = maxf(hud.notices.position.y, strip.position.y + strip.size.y + u(4))


# ---------------------------------------------------------------- the end
# UI (Alpha 21 UI pass, SCREEN-SYSTEM 18 / 19 / 20): the closing line and the result are MatchScreens pages in the
# mission faction's accent - the same VICTORY / DEFEAT / MATCH DETAILS as a normal match, plus the stars, the optional
# objective, the one-off reward, the unlocks and the XP strip (all of Campaign.record's / Progression's lines, as before).
var _page := "result"                                # the result's page: "result" or "details"


func _faction() -> String:
	return str(main.SEAT_FACTIONS.get(d.seat, "vex")) if main else "vex"


func _new_screen() -> MatchScreens:
	## A full-screen layer of its own for a result page (it replaces the open modal; taps stop there).
	if _modal:
		_modal.queue_free()
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_modal)
	_card = null
	return MatchScreens.open(_modal, mobile, _faction())


func show_end(res: Dictionary, summary: Dictionary, xp := {}) -> void:
	## The mission's closing line (the handler), then the result screen (tap skips ahead).
	_end = {"result": res, "summary": summary, "xp": xp}
	_animated = false
	_page = "result"
	strip.visible = false
	phase = "endline"
	_end_t = END_LINE_SECONDS
	var won := bool(res.get("won", false))
	var s := _new_screen()
	s.card({"kicker": "DISTRICT SECURED" if won else "THE CITY PUSHED BACK", "headline": "MISSION COMPLETE." if won else "MISSION FAILED.",
			"body": "%s:  %s" % [Campaign.HANDLER, str(m.get("win_line" if won else "lose_line", ""))], "dim": 0.35})
	_modal.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and phase == "endline":
			_show_result())
	_modal.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(_modal, "modulate", Color.WHITE, 0.25)


func _star_rules() -> Array:
	## The three stars' rules (CAMPAIGN-DESIGN §5: the same on every mission).
	return ["Win the mission", "Win within par (%s)" % MissionDirector.clock(d.par()),
			"Within par, keep every node you started with"]


func _mission_name() -> String:
	var id := str(m.get("id", ""))
	return ("%s / %s" % [id, str(m.get("title", ""))]) if id.is_valid_int() else str(m.get("title", ""))


func _ways_on(won: bool) -> Array:
	## [primary, quiet...] as [text, id]: CONTINUE (the next mission) or RETRY first, then the quieter ways out.
	var nxt := str(_end.get("summary", {}).get("next", ""))
	if won and nxt != "" and nxt != d.key:
		return [["CONTINUE  →", "next"], ["RETRY", "retry"], ["CAMPAIGN", "campaign"]]
	if won:
		return [["CAMPAIGN  →", "campaign"], ["RETRY", "retry"]]
	return [["RETRY  →", "retry"], ["CHANGE LOADOUT", "loadout"], ["CAMPAIGN", "campaign"]]


func _show_result() -> void:
	phase = "result"
	_page = "result"
	var res: Dictionary = _end.get("result", {})
	var summary: Dictionary = _end.get("summary", {})
	var won := bool(res.get("won", false))
	var stars := int(res.get("stars", 0))
	var s := _new_screen()
	var ways := _ways_on(won)
	var quiet := []
	for w in ways.slice(1):
		quiet.append([w[0], _on_button.bind(str(w[1]))])
	var extras := []
	# the optional objective, this run
	var opt_text := str(d.optional().get("text", ""))
	if opt_text != "":
		var met := bool(res.get("objective", false))
		var orow := _hbox(8)
		var mk := MatchScreens.Mark.new()
		mk.kind = "check" if met else "cross"
		mk.color = GOOD if met else BAD
		mk.custom_minimum_size = Vector2.ONE * UiKit.line_h(s, 14) * 0.7
		mk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		orow.add_child(mk)
		orow.add_child(UiKit.label(s, "OPTIONAL: " + opt_text, 14, UiKit.INK if met else UiKit.MUTED))
		extras.append(orow)
	# the reward (Campaign.record's summary): paid / earned / taken / none
	var rw: Dictionary = summary.get("reward", {})
	var amount := int(rw.get("amount", Campaign.reward_for(m)))
	var ticker: RewardTicker = null
	match str(rw.get("state", "none")):
		"paid":                                    # the one-off SCRAP counts up after the stars (Progression's ticker)
			ticker = RewardTicker.make(amount, "soft", func(n: float) -> float: return u(n))
			extras.append(ticker)
		"earned":
			extras.append(UiKit.label(s, "+%d SCRAP earned - paid when your wallet arrives" % amount, 14, GOLD))
		"taken":
			extras.append(UiKit.label(s, "Reward already taken", 14, UiKit.DIM))
		_:
			extras.append(UiKit.label(s, "3 stars + the optional objective in one run: +%d SCRAP" % amount, 14, UiKit.MUTED))
	for item in summary.get("unlocked", []):
		var parts := str(item).split(":")
		var what := ("%s vat unlocked" % parts[-1].to_upper()) if str(item).begins_with("vat:faction:") else ("%s unlocked" % str(item))
		extras.append(UiKit.label(s, what, 15, UiKit.accent(_faction()), true))
	var xp: Dictionary = _end.get("xp", {})
	if not xp.is_empty():
		var strip_ui := RewardStrip.make(xp, s.reward_scale(hud.ui_scale if hud else 1.0)) if not (xp.get("lines", []) as Array).is_empty() else null
		if strip_ui:
			extras.append(strip_ui)
		else:
			var xl := _xp_text(xp)
			if xl != "":
				extras.append(UiKit.label(s, xl, 14, UiKit.INK))
	var rules := _star_rules()
	var out := s.result({"won": won, "kicker": "DISTRICT SECURED" if won else "THE CITY PUSHED BACK",
			"headline": "VICTORY." if won else "DEFEAT.", "name": _mission_name(),
			"sub": "%s:  %s" % [Campaign.HANDLER, str(m.get("win_line" if won else "lose_line", ""))],
			"stars": stars, "star_note": ("NEXT STAR: %s" % rules[stars]) if stars < 3 else "",
			"metrics": [[MissionDirector.clock(float(res.get("time", 0.0))), "Match time"],
					["%d / %d" % [MatchScreens.nodes_held(d.sim, d.seat), d.sim.nodes.size()], "Nodes held"],
					["%d / 3" % stars, "Mission stars"]],
			"primary": [ways[0][0], _on_button.bind(str(ways[0][1]))], "details": show_details, "quiet": quiet,
			"extras": extras})
	var pops: Array = out.get("stars", [])
	if _animated:
		if ticker:
			ticker.play(true)
		return
	_animated = true
	# the pop-in: each earned star grows in with a bounce, one after the other; unearned ones fade in
	var tw := create_tween()
	for i in range(pops.size()):
		var g: Control = pops[i]
		g.pivot_offset = g.size / 2.0
		g.scale = Vector2.ZERO if i < stars else Vector2.ONE
		g.modulate = Color(1, 1, 1, 1.0 if i < stars else 0.0)
	for i in range(pops.size()):
		var g: Control = pops[i]
		if i < stars:
			tw.tween_property(g, "scale", Vector2.ONE * 1.3, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(g, "scale", Vector2.ONE, 0.12)
		else:
			tw.tween_property(g, "modulate", Color.WHITE, 0.2)
		tw.tween_interval(STAR_GAP - 0.3)
	if ticker:
		tw.tween_callback(ticker.play)


func show_details() -> void:
	## MATCH DETAILS (SCREEN-SYSTEM 20): the stars' rules and the optional objective for this run, then every seat's
	## numbers (MatchScreens.seat_table); BACK returns to the result.
	phase = "result"
	_page = "details"
	var res: Dictionary = _end.get("result", {})
	var won := bool(res.get("won", false))
	var stars := int(res.get("stars", 0))
	var notes := []
	var rules := _star_rules()
	for i in range(3):
		notes.append(["star", rules[i], i < stars])
	var opt_text := str(d.optional().get("text", ""))
	if opt_text != "":
		var met := bool(res.get("objective", false))
		notes.append(["check" if met else "cross", "OPTIONAL: " + opt_text, met])
	var ways := _ways_on(won)
	var s := _new_screen()
	s.details({"name": _mission_name(), "sub": "%s · %s" % [_mission_title(), MissionDirector.clock(float(res.get("time", 0.0)))],
			"outcome": "MISSION COMPLETE" if won else "MISSION FAILED", "back": _show_result, "notes": notes,
			"primary": [ways[0][0], _on_button.bind(str(ways[0][1]))]}, MatchScreens.seat_table(d.sim, d.seat))


func _xp_text(xp: Dictionary) -> String:
	var lines = xp.get("lines", [])
	if lines is Array and not (lines as Array).is_empty():
		return " · ".join((lines as Array).map(func(x): return str(x)))
	var gain := int(xp.get("xp_after", 0)) - int(xp.get("xp_before", 0))
	return ("+%d XP" % gain) if gain > 0 else ""


func _rebuild() -> void:
	## A resize (a phone rotating, a window drag): the open card is laid out again at the new size.
	if root == null or not is_inside_tree():
		return
	match phase:
		"brief":
			show_briefing()
		"result":
			if _page == "details":                  # UI: the page that was open
				show_details()
			else:
				_show_result()
		"endline":                                  # UI: laid out again, its timer kept
			var left := _end_t
			show_end(_end.get("result", {}), _end.get("summary", {}), _end.get("xp", {}))
			_end_t = left


func _on_button(id: String) -> void:
	if id == "start":
		begin_match()
		start_pressed.emit()
		return
	action.emit(id)


# ---------------------------------------------------------------- drawn marks
class Glyph extends Control:
	## A star, a tick or a cross, drawn (no font glyph needed).
	var kind := "star"
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size if size.x > 0.0 else custom_minimum_size
		var c := s / 2.0
		var r := minf(s.x, s.y) / 2.0
		match kind:
			"star":
				var pts := PackedVector2Array()
				for i in range(10):
					var a := -PI / 2.0 + i * PI / 5.0
					var rr := r if i % 2 == 0 else r * 0.45
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, color)
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, color.darkened(0.45), maxf(1.0, r * 0.08), true)
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-0.8, 0.0) * r, c + Vector2(-0.25, 0.6) * r,
						c + Vector2(0.85, -0.65) * r]), color, maxf(2.0, r * 0.32), true)
			"cross":
				var w := maxf(2.0, r * 0.3)
				draw_line(c + Vector2(-0.7, -0.7) * r, c + Vector2(0.7, 0.7) * r, color, w, true)
				draw_line(c + Vector2(-0.7, 0.7) * r, c + Vector2(0.7, -0.7) * r, color, w, true)
