class_name TopBar
extends Control
## The app shell's header (UI remake 45B, Daniele 11-18; GAP-LIST §0): the 45B HEADER-CABINET full width, OOZE /
## SYNDICATE in cream type and the Overlord crest at the left, two currency wells (SCRAP, CHIPS, thousands comma), the
## LEVEL well (tap: PROFILE) and three square cream keys (SOUND, SETTINGS, ?) at the right - the remake's HOME header,
## 812 x 34 pt, left group anchored left, right group anchored right. `slim` (a phone's subflow): BACK replaces the
## wordmark and the right group stays off, so the page keeps its height.

signal help_pressed
signal options_pressed
signal profile_pressed
signal back_pressed

const H_PT := 34.0                                 # the remake's header height (HOME / ARMIES / PROFILE remakes)

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var slim := false
var glass := false                                 # (kept for callers: HOME's header is the same cabinet now)
var u := 1.0                                       # canvas units per pt (Kit45.Stage of the content)


static func make(m, crumb: String, f := "vex", p_slim := false) -> TopBar:
	var t := TopBar.new()
	t.menu = m
	t.slim = p_slim
	t._build(crumb, f)
	return t


func bar_height() -> float:
	return size.y


func _L(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(Vector2(x, y) * u, Vector2(w, h) * u)


func _Rt(x: float, y: float, w: float, h: float) -> Rect2:
	## A right-group rect: the remake's x measured from the 812 pt right edge, anchored to this bar's right edge.
	return Rect2(Vector2(size.x - (Kit45.DW - x) * u, y * u), Vector2(w, h) * u)


func _build(crumb: String, _f: String) -> void:
	var w: float = menu.content.size.x
	u = minf(w / Kit45.DW, float(menu.content.size.y) / Kit45.DH)
	position = Vector2.ZERO
	size = Vector2(w, H_PT * u)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var c := UiKit.label(menu, crumb.to_upper(), 12, UiKit.MUTED, true, 3)
	c.visible = false                                # Daniele 2026-11-05: no breadcrumbs (kept, hidden: the string names the page)
	add_child(c)
	if slim:
		var back := _key("KEY-SMALL", _L(14, 6, 64, 22), "←  BACK", Callable(menu, "bar_back"))
		back.size_pt = 12.5
		queue_redraw()
		return
	_text("OOZE", _L(16, 2, 120, 19), 17.0, UiKit.INK, true)
	_text("SYNDICATE", _L(16, 20, 120, 11), 7.5, UiKit.MUTED, false)
	var crest := TextureRect.new()
	crest.texture = Kit45.art("OVERLORD-CREST")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cr := _L(231, 5, 34, 24)
	crest.position = cr.position
	crest.size = cr.size
	add_child(crest)
	# right group: SCRAP, CHIPS, LEVEL, SOUND, SETTINGS, ?
	_well("COUNTER-WELL", _Rt(444, 5, 82, 24), "CUR-1", Progression.balance("soft"), "SCRAP")
	_well("COUNTER-WELL", _Rt(532, 5, 63, 24), "CUR-2", Progression.balance("premium"), "CHIPS")
	var lv := Kit45.Piece.new()
	lv.fam = "LEVEL-WELL"
	lv.key = "80x24pt"
	lv.u = u
	var lr := _Rt(601, 5, 80, 24)
	lv.position = lr.position
	lv.size = lr.size
	add_child(lv)
	var level := int(Progression.level_for(Progression.xp)["level"])
	_text("LEVEL %d" % level, lr, 11.0, UiKit.INK, false, 1)
	var prof := _tap(lr.grow_individual(0, 5 * u, 0, 5 * u), Callable(menu, "show_profile"))
	prof.tooltip_text = "PROFILE"
	var snd := _key("UTILITY-BUTTON", _Rt(691, 5, 31, 24), "", Callable())
	snd.tooltip_text = "SOUND"
	snd.glyph = Kit45.art("ICON-SOUND")
	snd.glyph_rect = Rect2(8, 4, 15, 16)
	snd.selected = false
	var cross := Control.new()                       # SOUND OFF: a cross beside the speaker (note 16: never a broken glyph)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.position = snd.art.position
	cross.size = snd.art.size
	cross.draw.connect(func():
		if Music.music_on():
			return
		var q := cross.size
		var lw := maxf(1.5, 1.6 * u)
		cross.draw_rect(Rect2(q * Vector2(0.18, 0.12), q * Vector2(0.64, 0.76)), Color(Kit45.INK_DARK, 0.0))
		cross.draw_line(q * Vector2(0.58, 0.32), q * Vector2(0.82, 0.68), Color("b3263a"), lw)
		cross.draw_line(q * Vector2(0.82, 0.32), q * Vector2(0.58, 0.68), Color("b3263a"), lw))
	snd.add_child(cross)
	snd.pressed.connect(func():
		Music.toggle_on()                            # OFF at once, everywhere (Music.set_on stops the players itself)
		Sfx.play_ui("tap")
		cross.queue_redraw())
	var gear := _key("UTILITY-BUTTON", _Rt(728, 5, 31, 24), "", Callable(menu, "show_options"))
	gear.tooltip_text = "OPTIONS"
	gear.glyph = Kit45.art("ICON-SETTINGS")
	gear.glyph_rect = Rect2(8, 4, 15, 16)
	var help := _key("UTILITY-BUTTON", _Rt(765, 5, 31, 24), "?", Callable(menu, "show_help"))
	help.tooltip_text = "HELP"
	help.glyph = Kit45.art("ICON-HELP")
	help.glyph_rect = Rect2(8, 4, 15, 16)
	help.label = ""
	queue_redraw()


func _key(fam: String, r: Rect2, label: String, call: Callable) -> Kit45.Btn:
	var b := Kit45.Btn.new()
	b.m = menu
	b.fam = fam
	b.key = Kit45.nearest(fam, r.size.x / u, r.size.y / u)
	b.label = label
	b.u = u
	var hit := maxf(r.size.y, Kit45.MIN_HIT * u)
	b.position = Vector2(r.position.x, maxf(0.0, r.position.y - (hit - r.size.y) / 2.0))
	b.size = Vector2(r.size.x, hit)
	b.art = Rect2(Vector2(0, r.position.y - b.position.y), r.size)
	if call.is_valid():
		b.pressed.connect(func(): UiKit.acknowledge(b, call))
	add_child(b)
	return b


func _tap(r: Rect2, call: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for sn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
	b.position = r.position
	b.size = r.size
	b.pressed.connect(func(): UiKit.acknowledge(b, call))
	add_child(b)
	return b


func _text(t: String, r: Rect2, size_pt: float, col: Color, head := false, align := 0) -> Kit45.Txt:
	var l := Kit45.Txt.new()
	l.m = menu
	l.text = t
	l.size_cu = size_pt * u
	l.col = col
	l.head = head
	l.align = align
	l.position = r.position
	l.size = r.size
	add_child(l)
	return l


func _well(fam: String, r: Rect2, glyph: String, amount: int, tip: String) -> void:
	var p := Kit45.Piece.new()
	p.fam = fam
	p.key = Kit45.nearest(fam, r.size.x / u, r.size.y / u)
	p.u = u
	p.position = r.position
	p.size = r.size
	p.tooltip_text = tip
	add_child(p)
	var g := TextureRect.new()
	g.texture = Kit45.art(glyph)
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.position = r.position + Vector2(9, 5) * u
	g.size = Vector2(14, 14) * u
	add_child(g)
	_text(group(amount), Rect2(r.position + Vector2(27, 0) * u, Vector2(r.size.x - 33.0 * u, r.size.y)), 12.0, UiKit.INK, false, 2)


static func group(n: int) -> String:
	## 6620 -> "6,620" (the remake's thousands comma).
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _draw() -> void:
	var sf: Vector4 = menu.safe                       # the cabinet reaches over the notch bands and the status bar
	Kit45.nine(self, Kit45.tex("HEADER-CABINET-812x37pt-STATIC.png"), Rect2(-sf.x, -sf.y, size.x + sf.x + sf.z, size.y + sf.y),
			Kit45.variant("HEADER-CABINET")["slice"], u)
