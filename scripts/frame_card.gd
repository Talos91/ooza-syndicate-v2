class_name FrameCard
extends Control
## An image-led card (Alpha 21 UI pass): art on top (optionally a faction character standing in it), then on an
## opaque panel the kicker ("NEXT MISSION"), the title (+ subtitle), stars, a one-line note and an action button whose
## look follows the state. PLAY's three choices, the campaign hub's missions and the chapter picker are all this.
## The whole card is one tap target (`pressed`); a locked, buyable card's UNLOCK emits `unlock_pressed` instead.
## Inside a TouchScroll, a drag emits nothing.
##   var c := FrameCard.make(menu, Vector2(300, 250), "vex", scroll)
##   c.set_art(path); c.set_number("01"); c.set_title("HOSTILE TAKEOVER"); c.set_stars(0, 3); c.set_state("next")
## States: "next" (accent frame, primary CONTINUE), "open" / "won" (PLAY / REPLAY), "locked" (dim, LOCKED - or UNLOCK
## when `buyable`), "coming" (dim, COMING LATER), "dev" (dim, IN DEVELOPMENT, no button). `selected` lights the frame.

signal pressed
signal unlock_pressed

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var faction := "vex"
var scroll: TouchScroll
var art := ""
var hero := ""                                     # a faction whose character stands in the art ("" = none)
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
var selected := false
var art_frac := 0.46                               # the art's share of the card's height
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
func set_hero(f: String) -> void: hero = f; _queue()
func set_number(text: String) -> void: number = text; _queue()
func set_kicker(text: String) -> void: kicker = text; _queue()
func set_title(text: String, sub := "") -> void: title = text; subtitle = sub; _queue()
func set_note(text: String) -> void: note = text; _queue()
func set_state(s: String) -> void: state = s; _queue()
func set_stars(n: int, of := 3) -> void: stars = n; stars_max = of; _queue()
func set_action(text: String) -> void: action = text; _queue()
func set_selected(on: bool) -> void: selected = on; _queue()


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
	var lit := (state == "next" or selected) and not dim
	var body := UiKit.flat_button(menu, "", 12)       # the whole card: one tap target, under everything else
	body.position = Vector2.ZERO
	body.size = size
	body.pressed.connect(func():
		if not _drag():
			UiKit.acknowledge(self, func(): pressed.emit()))   # the card flashes at once (a phone builds the next page)
	# UI (0.22.x button sweep): a card that can't be opened (COMING LATER, IN DEVELOPMENT, LOCKED and not buyable) doesn't
	# react - it flashed and then nothing happened, which on a phone reads as a dead button; its note / button says why
	body.disabled = dim and not buyable
	add_child(body)
	var surface := Panel.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", UiKit.sb(UiKit.CARD))
	surface.size = size
	add_child(surface)
	var ah := maxf(h * art_frac, h - _text_block_h() - 10.0)   # the art fills down to the text
	var tex: Texture2D = UiKit.tex(art) if art != "" and ResourceLoader.exists(art) else UiKit.background(faction)
	if tex == null:
		tex = UiKit.hero_art(faction)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate = Color(0.42, 0.46, 0.5) if dim else Color(0.9, 0.92, 0.95)
	pic.position = Vector2(3, 3)
	pic.size = Vector2(w - 6.0, ah)
	add_child(pic)
	if hero != "":                                     # the character, standing at the art's right
		var hr := TextureRect.new()
		hr.texture = UiKit.tex(UiKit.hero_path(hero))
		hr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hr.modulate = Color(0.5, 0.5, 0.5) if dim else Color.WHITE
		hr.size = Vector2(ah * 0.95, ah * 0.95)
		hr.position = Vector2(w - hr.size.x - 10.0, ah - hr.size.y + 6.0)
		add_child(hr)
		var es := clampf(ah * 0.24, 28.0, 48.0)       # the race emblem, the art's top-left corner
		var em := UiKit.emblem_node(hero, es, Vector2(10, 10))
		em.modulate = Color(0.5, 0.5, 0.5) if dim else Color.WHITE
		add_child(em)
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
	fade.position = Vector2(0, ah * 0.6)
	fade.size = Vector2(w, ah * 0.4 + 4.0)
	add_child(fade)
	var frame := Panel.new()                          # the frame last, over the art's edges
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiKit.sb(Color(0, 0, 0, 0), acc if lit else (Color(UiKit.FRAME, 0.6) if dim else UiKit.FRAME),
			2 if lit else 1, UiKit.CUT, Color(acc, 0.22) if lit else Color(0, 0, 0, 0)))
	frame.size = size
	add_child(frame)
	var pad := 14.0
	if number != "":                                   # the badge, top left of the art
		var n := UiKit.label(menu, number, 15, UiKit.INK, true)
		var nb := Panel.new()
		nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nb.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.9), acc if lit else UiKit.FRAME, 1, 5))
		var nw := UiKit.text_w(menu, number, 15, true) + 18.0
		nb.size = Vector2(nw, n.get_minimum_size().y + 6.0)
		nb.position = Vector2(10, 10)
		add_child(nb)
		n.position = nb.position + Vector2(9, 3)
		add_child(n)
	# the text column, bottom up: the button, the note, stars, the title, the kicker
	var y := h - pad
	var bt := _button_text()
	if bt != "":
		var kind := "primary" if (state == "next" or selected) and not dim else "secondary"
		var b := UiKit.make_btn(menu, bt, Vector2(w - pad * 2.0, 38.0), Callable(), kind, faction, 15)
		b.disabled = dim and not (state == "locked" and buyable)
		b.position = Vector2(pad, y - b.size.y)
		b.pressed.connect(func():
			if _drag():
				return
			if state == "locked" and buyable:
				unlock_pressed.emit()
			else:
				pressed.emit())
		add_child(b)
		y -= b.size.y + 10.0
	if note != "":
		var l := UiKit.label(menu, note, 13, UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(w - pad * 2.0, 0)
		var lh := UiKit.text_h(menu, note, 13, w - pad * 2.0)
		l.position = Vector2(pad, y - lh)
		add_child(l)
		y -= lh + 4.0
	if stars >= 0:
		var s := UiKit.star_row(menu, stars, stars_max, 18)
		s.position = Vector2(pad, y - UiKit.line_h(menu, 18))
		add_child(s)
		y -= UiKit.line_h(menu, 18) + 2.0
	if subtitle != "":
		var st := UiKit.label(menu, subtitle.to_upper(), 12, UiKit.MUTED, false, 2)
		st.position = Vector2(pad, y - st.get_minimum_size().y)
		add_child(st)
		y -= st.get_minimum_size().y
	if title != "":
		var t := UiKit.label(menu, title.to_upper(), 20, UiKit.INK if not dim else UiKit.MUTED, true)
		t.clip_text = true
		t.size = Vector2(w - pad * 2.0, t.get_minimum_size().y)
		t.position = Vector2(pad, y - t.size.y)
		add_child(t)
		y -= t.size.y + 2.0
	var k := kicker if kicker != "" else ("NEXT MISSION" if state == "next" else "")
	if k != "":
		var kl := UiKit.label(menu, k.to_upper(), 11, acc if not dim else UiKit.DIM, true, 3)
		kl.position = Vector2(pad, y - kl.get_minimum_size().y)
		add_child(kl)


func _text_block_h() -> float:
	## The text column's height (kicker .. button), measured the way _rebuild() lays it out.
	var w := size.x - 28.0
	var t := 14.0
	if _button_text() != "":
		t += UiKit.tap_h(menu, 38.0) + 10.0
	if note != "":
		t += UiKit.text_h(menu, note, 13, w) + 4.0
	if stars >= 0:
		t += UiKit.line_h(menu, 18) + 2.0
	if subtitle != "":
		t += UiKit.line_h(menu, 12)
	if title != "":
		t += UiKit.line_h(menu, 20, true) + 2.0
	if kicker != "" or state == "next":
		t += UiKit.line_h(menu, 11, true)
	return t + 6.0


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
