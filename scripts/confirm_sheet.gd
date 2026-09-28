class_name ConfirmSheet
extends Control
## CONFIRMATION (Alpha 21 UI pass, screen system 26): a sheet over a dimmed page - the kicker, the question, what
## happens if you go on, the SAFE action (primary: KEEP PLAYING / CANCEL) and the DESTRUCTIVE one (secondary, in a
## warning tone, a specific verb - never a bare YES / NO). Either button closes the sheet, then runs its callable;
## a tap on the dim does nothing (the choice stays explicit). Canvas units (UiKit), in the menu's `m.content`.

const WARN := Color("ff5c6c")                       # the destructive action's tone (not a faction accent)

signal chose(safe: bool)

var menu                                             # the page's owner (Menu, or anything with `content` + _pt_factor)
var on_safe := Callable()
var on_destructive := Callable()


static func make(m, kicker: String, question: String, consequence: String, safe_text: String, destructive_text: String,
		safe: Callable, destructive: Callable, f := "vex") -> ConfirmSheet:
	var c := ConfirmSheet.new()
	c.menu = m
	c.on_safe = safe
	c.on_destructive = destructive
	c._build(kicker, question, consequence, safe_text, destructive_text, f)
	m.content.add_child(c)
	return c


func _build(kicker: String, question: String, consequence: String, safe_text: String, destructive_text: String, f: String) -> void:
	var W: float = menu.content.size.x
	var H: float = menu.content.size.y
	position = Vector2.ZERO
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP              # the page under it takes no taps
	add_child(UiKit.rect(Vector2.ZERO, size, Color(UiKit.BASE, 0.72)))
	var pad := 24.0
	var pw := minf(620.0, W - 2.0 * maxf(26.0, W * 0.024))
	var iw := pw - pad * 2.0
	var bh := UiKit.tap_h(menu, 48.0)
	var kh := UiKit.line_h(menu, 12, true)
	var qh := UiKit.text_h(menu, question.to_upper(), 30, iw, true)
	var ch := UiKit.text_h(menu, consequence, 15, iw)
	var ph := pad + kh + 6.0 + qh + 10.0 + ch + 22.0 + bh + pad
	var pos := Vector2((W - pw) / 2.0, maxf(20.0, (H - ph) / 2.0 - H * 0.06))
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.PANEL, 0.98), UiKit.FRAME, 1))
	p.position = pos
	p.size = Vector2(pw, ph)
	add_child(p)
	var y := pos.y + pad
	_text(kicker.to_upper(), 12, UiKit.accent(f), true, 3, Vector2(pos.x + pad, y), iw)
	y += kh + 6.0
	_text(question.to_upper(), 30, UiKit.INK, true, 0, Vector2(pos.x + pad - 1.0, y), iw)
	y += qh + 10.0
	_text(consequence, 15, UiKit.MUTED, false, 0, Vector2(pos.x + pad, y), iw)
	y += ch + 22.0
	var bw := (iw - 12.0) / 2.0
	var sb := UiKit.make_btn(menu, safe_text.to_upper(), Vector2(bw, 48), func(): _choose(true), "primary", f, 16)
	sb.position = Vector2(pos.x + pad, y)
	add_child(sb)
	var db := UiKit.make_btn(menu, destructive_text.to_upper(), Vector2(bw, 48), func(): _choose(false), "secondary", f, 16)
	db.add_theme_stylebox_override("normal", UiKit.sb(Color(UiKit.PANEL, 0.94), WARN, 1))
	db.add_theme_stylebox_override("hover", UiKit.sb(Color(WARN.darkened(0.78), 0.96), WARN.lightened(0.15), 1))
	db.add_theme_stylebox_override("pressed", UiKit.sb(Color(WARN.darkened(0.6), 0.96), WARN, 1))
	db.add_theme_stylebox_override("hover_pressed", db.get_theme_stylebox("pressed"))
	db.add_theme_color_override("font_hover_color", WARN.lightened(0.3))
	db.position = Vector2(pos.x + pad + bw + 12.0, y)
	add_child(db)


func _text(t: String, sz: float, col: Color, head: bool, spacing: int, pos: Vector2, width: float) -> void:
	var l := UiKit.label(menu, t, sz, col, head, spacing)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.position = pos
	add_child(l)


func _choose(safe: bool) -> void:
	chose.emit(safe)
	var call := on_safe if safe else on_destructive
	queue_free()
	if call.is_valid():
		call.call()
