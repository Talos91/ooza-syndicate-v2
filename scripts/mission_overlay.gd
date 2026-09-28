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
	## MISSION BRIEFING (Alpha 21 UI pass, screen system 10), full screen over the paused match, in the UiKit language
	## and the menu faction's accent: "CAMPAIGN / DOCKSIDE · MISSION 01" and the title, BACK (-> the campaign); the
	## mission's art large on the left; on the right the briefing panel - the story, the speakers' lines, the objective,
	## optional objective and par as marked rows, the faction pairing and district tags (it scrolls on a short phone);
	## the best result and START MISSION at the foot.
	phase = "brief"
	strip.visible = false
	_card = null                                     # nothing to re-centre: the page is laid out to the screen
	var vp := get_viewport().get_visible_rect().size
	var modal := _new_modal(0.97)
	var f := _brief_faction()
	var acc := UiKit.accent(f)
	var env := TextureRect.new()                     # the faction's environment, like the menu pages
	env.texture = UiKit.background(f)
	env.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	env.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	env.modulate = Color(0.42, 0.45, 0.5)
	env.mouse_filter = Control.MOUSE_FILTER_IGNORE
	env.size = vp
	modal.add_child(env)
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = vp
	modal.add_child(page)
	var mx := maxf(u(16), vp.x * 0.024)
	var y := u(12)
	var kick := _b_label("CAMPAIGN / " + _mission_title(), 12.5, acc, true, 3)
	_b_put(page, kick, Vector2(mx, y))
	y += kick.get_minimum_size().y + u(1)
	var head := _b_label(str(m.get("title", "")), 24, UiKit.INK, true)
	_b_put(page, head, Vector2(mx - u(1), y))
	y += head.get_minimum_size().y + u(10)
	var back := Button.new()
	back.text = "←  BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_override("font", UiKit.HEAD)
	back.add_theme_font_size_override("font_size", int(round(u(14))))
	UiKit.style_button(back, "tertiary", f)
	back.add_theme_color_override("font_color", UiKit.INK)
	back.size = Vector2(UiKit.HEAD.get_string_size(back.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(u(14)))).x + u(24), u(44))
	back.pressed.connect(func(): _on_button("campaign"))
	_b_put(page, back, Vector2(vp.x - mx - back.size.x + u(8), u(8)))
	# the foot: the best result, START MISSION
	var fh := u(46)
	var fy := vp.y - fh - u(10)
	var start := Button.new()
	start.text = "START MISSION  →"
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_override("font", UiKit.HEAD)
	start.add_theme_font_size_override("font_size", int(round(u(15))))
	UiKit.style_button(start, "primary", f)
	start.size = Vector2(UiKit.HEAD.get_string_size(start.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(u(15)))).x + u(56), fh)
	start.pressed.connect(func(): _on_button("start"))
	_b_put(page, start, Vector2(vp.x - mx - start.size.x, fy))
	_b_best(page, Vector2(mx, fy), fh)
	# the art and the briefing panel
	var gap := u(14)
	var bh := fy - u(12) - y
	var aw := (vp.x - mx * 2.0 - gap) * (0.46 if mobile else 0.54)
	var art_path := Campaign.backdrop_of(d.key) if d.key != "" else ""
	var tex: Texture2D = UiKit.tex(art_path) if art_path != "" else UiKit.background(f)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size = Vector2(aw - 4.0, bh - 4.0)
	_b_put(page, pic, Vector2(mx + 2.0, y + 2.0))
	var art_frame := Panel.new()
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_theme_stylebox_override("panel", UiKit.sb(Color(0, 0, 0, 0), UiKit.FRAME, 1, 0))
	art_frame.size = Vector2(aw, bh)
	_b_put(page, art_frame, Vector2(mx, y))
	var px := mx + aw + gap
	var pw := vp.x - mx - px
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.PANEL, 0.96), UiKit.FRAME, 1))
	panel.size = Vector2(pw, bh)
	_b_put(page, panel, Vector2(px, y))
	var pad := u(14)
	var scroll := TouchScroll.new()
	scroll.position = Vector2(pad, pad * 0.8)
	scroll.size = Vector2(pw - pad * 1.4, bh - pad * 1.6)
	var grab := UiKit.sb(Color(acc, 0.7), Color(0, 0, 0, 0), 0, 2)
	grab.set_content_margin_all(2)
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scroll.get_v_scroll_bar().add_theme_stylebox_override(s, grab)
	scroll.get_v_scroll_bar().add_theme_stylebox_override("scroll", UiKit.sb(Color(UiKit.FRAME, 0.3), Color(0, 0, 0, 0), 0, 2))
	panel.add_child(scroll)
	var cw := scroll.size.x - u(12)
	var col := _vbox(6)
	col.custom_minimum_size = Vector2(cw, 0)
	scroll.add_child(col)
	col.add_child(_b_label("MISSION BRIEFING", 12.5, acc, true, 3))
	col.add_child(_b_wrap(_b_label(str(m.get("story", "")), 16, UiKit.INK), cw))
	for pair in m.get("brief", []):                  # the speakers' lines
		var sp: Array = _speaker(str(pair[0]))
		var line := _vbox(0)
		var who_c := UiKit.accent(str(Campaign.rival_of(m).get("faction", "ember"))) if str(pair[0]) == "rival" else acc
		line.add_child(_b_label(str(sp[0]), 12.5, who_c, true, 2))     # the rival in its faction's accent
		line.add_child(_b_wrap(_b_label(Campaign.fill(str(pair[1]), m), 14, UiKit.MUTED), cw))
		col.add_child(line)
	col.add_child(_b_rule(acc))
	col.add_child(_b_goal("OBJECTIVE", Campaign.objective_text(m), UiKit.INK, acc, cw))
	if str(d.optional().get("text", "")) != "":
		col.add_child(_b_goal("OPTIONAL", str(d.optional()["text"]), UiKit.INK, acc, cw))
	if d.par() > 0.0:
		col.add_child(_b_goal("PAR", "%s - win inside it for 2 stars, and keep every node you start with for 3" % MissionDirector.clock(d.par()),
				UiKit.MUTED, acc, cw))
	var tags := HFlowContainer.new()                 # the faction pairing, the district
	tags.add_theme_constant_override("h_separation", int(round(u(6))))
	tags.add_theme_constant_override("v_separation", int(round(u(6))))
	tags.custom_minimum_size = Vector2(cw, 0)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mf := str(m.get("faction", "vex"))
	var rf := str(Campaign.rival_of(m).get("faction", "ember"))
	tags.add_child(_b_tag("%s  vs  %s" % [UiKit.NAMES.get(mf, mf.to_upper()), UiKit.NAMES.get(rf, rf.to_upper())], acc))
	var dist := str(Campaign.district_of(d.key).get("name", "")) if d.key != "" else ""
	if dist != "":
		tags.add_child(_b_tag(dist, acc))
	col.add_child(tags)
	page.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(page, "modulate", Color.WHITE, 0.25)


func _brief_faction() -> String:
	## The briefing wears the campaign's own faction - the one you play the mission as (Daniele 2026-09-28: "for campaign
	## keep campaign faction colour", VEX's cyan for the VEX campaign).
	var f := str(m.get("faction", "vex"))
	return f if UiKit.ACCENTS.has(f) else "vex"


func _b_label(text: String, pt: float, color: Color, head := false, spacing := 0) -> Label:
	## A briefing label in the UiKit faces, sized in this overlay's points (u).
	var l := Label.new()
	l.text = text.to_upper() if head else text
	var font: Font = UiKit.HEAD if head else UiKit.BODY
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = spacing
		font = fv
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", int(round(u(pt))))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _b_wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _b_put(parent: Control, c: Control, pos: Vector2) -> void:
	c.position = pos
	parent.add_child(c)


func _b_rule(acc: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(acc, 0.3)
	r.custom_minimum_size = Vector2(0, maxf(1.0, u(1)))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _b_goal(k: String, v: String, color: Color, acc: Color, w: float) -> HBoxContainer:
	## An objective row: the accent diamond, its key over its text.
	var row := _hbox(10)
	var mark := BriefMark.new()
	mark.color = acc
	mark.custom_minimum_size = Vector2(u(12), u(12))
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var holder := MarginContainer.new()               # the diamond level with the key's line
	holder.add_theme_constant_override("margin_top", int(round(u(3))))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(mark)
	row.add_child(holder)
	var txt := _vbox(0)
	txt.add_child(_b_label(k, 12.5, UiKit.DIM, true, 2))
	txt.add_child(_b_wrap(_b_label(v, 14, color), w - u(24)))
	row.add_child(txt)
	return row


func _b_tag(text: String, acc: Color) -> PanelContainer:
	## A dark plate with the accent bar (UiKit.tag's look, in a container).
	var p := PanelContainer.new()
	var s := UiKit.sb(Color(UiKit.BASE, 0.92), Color(0, 0, 0, 0), 0, 3)
	s.content_margin_left = u(10)
	s.content_margin_right = u(10)
	s.content_margin_top = u(3)
	s.content_margin_bottom = u(3)
	s.border_color = acc
	s.border_width_left = maxi(2, int(round(u(2))))
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_b_label(text, 12.5, UiKit.INK, true, 1))
	return p


func _b_best(page: Control, pos: Vector2, h: float) -> void:
	## "BEST RESULT" - the stars (drawn) and best time of this mission, or "Not completed yet".
	var rec := Campaign.record_of(d.key) if d.key != "" else {}
	var row := _hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(_b_label("BEST RESULT", 12.5, UiKit.DIM, true, 2))
	if bool(rec.get("won", false)):
		var n := int(rec.get("stars", 0))
		for i in range(3):
			var g := Glyph.new()
			g.kind = "star"
			g.color = UiKit.STAR if i < n else Color(UiKit.DIM, 0.8)
			g.custom_minimum_size = Vector2(u(16), u(16))
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(g)
		if float(rec.get("best_time", 0.0)) > 0.0:
			row.add_child(_b_label(MissionDirector.clock(float(rec["best_time"])), 14, UiKit.INK))
	else:
		row.add_child(_b_label("Not completed yet", 14, UiKit.MUTED))
	row.size = Vector2(0, h)
	for c in row.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_b_put(page, row, pos)


class BriefMark extends Control:
	## The briefing's objective marker: an outlined diamond, drawn.
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size if size.x > 0.0 else custom_minimum_size
		var c := s / 2.0
		var r := minf(s.x, s.y) / 2.0 - 1.0
		draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
				c + Vector2(0, -r)]), color, maxf(1.5, r * 0.28), true)


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
