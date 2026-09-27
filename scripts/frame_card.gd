class_name FrameCard
extends Control
## A framed card (Alpha 21 UI pass): art under a dark fade, a neon-cut frame in the faction accent, an optional
## big number ("01"), a kicker ("NEXT MISSION"), the title (+ subtitle), stars, a one-line note and an action
## button whose look follows the state. The campaign hub's mission cards and the Campaign session's episode
## picker are both this. The whole card is one tap target (`pressed`); on a locked card the UNLOCK button
## emits `unlock_pressed` instead (Progression's buy sheet, later). Inside a TouchScroll, a drag emits nothing.
##   var c := FrameCard.make(menu, Vector2(300, 250), "vex", scroll)
##   c.set_art(path); c.set_number("01"); c.set_title("HOSTILE TAKEOVER"); c.set_stars(0, 3); c.set_state("next")
## States: "next" (lit, CONTINUE), "open" / "won" (PLAY / REPLAY), "locked" (dim, LOCKED - or UNLOCK when
## `buyable`), "coming" (dim, COMING LATER), "dev" (dim, IN DEVELOPMENT, no button).

signal pressed
signal unlock_pressed

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var faction := "vex"
var scroll: TouchScroll
var art := ""
var number := ""
var kicker := ""
var title := ""
var subtitle := ""
var note := ""
var state := "open"
var stars := -1                                    # < 0: no stars row
var stars_max := 3
var action := ""                                   # "" = the state's own button text
var buyable := false                               # a locked card that can be bought: UNLOCK
var _dirty := false


static func make(m, dims: Vector2, f := "vex", p_scroll: TouchScroll = null) -> FrameCard:
	var c := FrameCard.new()
	c.menu = m
	c.faction = f
	c.scroll = p_scroll
	c.size = dims
	c.custom_minimum_size = dims
	c.clip_contents = true
	c._queue()
	return c


func set_art(path: String) -> void: art = path; _queue()
func set_number(text: String) -> void: number = text; _queue()
func set_kicker(text: String) -> void: kicker = text; _queue()
func set_title(text: String, sub := "") -> void: title = text; subtitle = sub; _queue()
func set_note(text: String) -> void: note = text; _queue()
func set_state(s: String) -> void: state = s; _queue()
func set_stars(n: int, of := 3) -> void: stars = n; stars_max = of; _queue()
func set_action(text: String) -> void: action = text; _queue()


func dimmed() -> bool:
	return state in ["locked", "coming", "dev"]


func _queue() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func _drag() -> bool:
	return scroll != null and scroll.was_drag()


func _rebuild() -> void:
	_dirty = false
	for c in get_children():
		c.queue_free()
	var w := size.x
	var h := size.y
	var acc := UiKit.accent(faction)
	var dim := dimmed()
	var body := UiKit.flat_button(menu, "", 12)        # the whole card: one tap target, under everything else
	body.position = Vector2.ZERO
	body.size = size
	body.pressed.connect(func():
		if not _drag():
			pressed.emit())
	add_child(body)
	var tex: Texture2D = load(art) if art != "" and ResourceLoader.exists(art) else UiKit.hero_art(faction)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate = Color(0.45, 0.5, 0.55) if dim else Color(0.85, 0.88, 0.9)
	add_child(pic)
	pic.position = Vector2.ZERO
	pic.size = Vector2(w, h * 0.55)
	var fade := TextureRect.new()                     # art -> card fill, so the text below always reads
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.CARD, 0.0))
	g.set_color(1, UiKit.CARD)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(fade)
	fade.position = Vector2(0, h * 0.15)
	fade.size = Vector2(w, h * 0.4 + 1.0)
	add_child(UiKit.rect(Vector2(0, h * 0.55), Vector2(w, h * 0.45), UiKit.CARD))
	var frame := NeonPanel.new()
	frame.accent = acc if not dim else Color(UiKit.DIM, 0.8)
	frame.fill = Color(0, 0, 0, 0)
	frame.glowing = state == "next"
	frame.cut = 12.0
	add_child(frame)
	frame.position = Vector2.ZERO
	frame.size = size
	var pad := 16.0
	if number != "":
		var n := UiKit.label(menu, number, 44, Color(UiKit.INK, 0.35 if dim else 0.55), true)
		n.position = Vector2(pad, 4)
		add_child(n)
	# the text column, bottom up: the button, the note, stars, the title, the kicker
	var y := h - pad
	var bt := _button_text()
	if bt != "":
		var bh := UiKit.tap_h(menu, 40.0)
		var b := Button.new()
		b.text = bt
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiKit.HEAD)
		b.add_theme_font_size_override("font_size", UiKit.px(menu, 15))
		UiSkin.button(b, faction, state == "next")
		b.disabled = dim and not (state == "locked" and buyable)
		b.position = Vector2(pad, y - bh)
		b.size = Vector2(w - pad * 2.0, bh)
		b.pressed.connect(func():
			if _drag():
				return
			if state == "locked" and buyable:
				unlock_pressed.emit()
			else:
				pressed.emit())
		add_child(b)
		y -= bh + 10.0
	if note != "":
		var l := UiKit.label(menu, note, 13, UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(w - pad * 2.0, 0)
		var lh := UiKit.text_h(menu, note, 13, w - pad * 2.0)
		l.position = Vector2(pad, y - lh)
		add_child(l)
		y -= lh + 4.0
	if stars >= 0:
		var s := UiKit.label(menu, "★".repeat(stars) + "☆".repeat(maxi(0, stars_max - stars)), 15,
				Color("ffd15c") if stars > 0 else UiKit.MUTED)
		s.position = Vector2(pad, y - s.get_minimum_size().y)
		add_child(s)
		y -= s.get_minimum_size().y + 2.0
	if subtitle != "":
		var st := UiKit.label(menu, subtitle.to_upper(), 12, UiKit.MUTED, false, 2)
		st.position = Vector2(pad, y - st.get_minimum_size().y)
		add_child(st)
		y -= st.get_minimum_size().y
	if title != "":
		var t := UiKit.label(menu, title, 22, UiKit.INK if not dim else UiKit.MUTED, true)
		t.clip_text = true
		t.size = Vector2(w - pad * 2.0, t.get_minimum_size().y)
		t.position = Vector2(pad, y - t.size.y)
		add_child(t)
		y -= t.size.y + 4.0
	var k := kicker if kicker != "" else ("NEXT MISSION" if state == "next" else "")
	if k != "":
		var kl := UiKit.label(menu, k, 12, acc, false, 3)
		kl.position = Vector2(pad, y - kl.get_minimum_size().y)
		add_child(kl)


func _button_text() -> String:
	if action != "":
		return action
	match state:
		"next":
			return "CONTINUE  →"
		"open":
			return "PLAY"
		"won":
			return "REPLAY"
		"locked":
			return "UNLOCK" if buyable else "LOCKED"
		"coming":
			return "COMING LATER"
	return ""                                        # "dev": IN DEVELOPMENT shows as the note, no button
