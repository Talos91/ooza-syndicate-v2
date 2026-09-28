class_name TopBar
extends Control
## The app shell's top bar (Alpha 21 UI pass): the wordmark, a breadcrumb ("OOZE / CAMPAIGN"), both balances, the
## level ring + "LEVEL n · x / y campaign stars" (tap: PROFILE), a gear (OPTIONS) and "?" (HELP). Full screen width
## on every shell page. `slim` (a phone's subflow - faction, battlefield, setup, lobby...; SCREEN-SYSTEM.md "Mobile
## layout"): only BACK and the breadcrumb, so the page keeps its height. Canvas units (UiKit); >= 44 pt on phones.

signal help_pressed
signal options_pressed
signal profile_pressed
signal back_pressed

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var slim := false
var _ring_c := Vector2.ZERO
var _ring_r := 0.0
var _ring_col := UiKit.CYAN
var _level := 1


static func make(m, crumb: String, f := "vex", p_slim := false) -> TopBar:
	var t := TopBar.new()
	t.menu = m
	t.slim = p_slim
	t._build(crumb, f)
	return t


func bar_height() -> float:
	return size.y


func _build(crumb: String, f: String) -> void:
	var w: float = menu.content.size.x
	var q := UiKit.tap_h(menu, 46.0)                  # the square buttons, a little over 44 pt on phones (the sweep: 43)
	var h := maxf(58.0, q + 10.0)
	position = Vector2.ZERO
	size = Vector2(w, h)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_ring_col = UiKit.accent(f)
	var x := 18.0
	if slim:
		var back := UiKit.make_btn(menu, "←  BACK", Vector2(120, q), func(): back_pressed.emit(), "secondary", f, 15)
		back.position = Vector2(x, (h - back.size.y) / 2.0)
		add_child(back)
		x += back.size.x + 18.0
	else:
		var mark := TextureRect.new()                # the wordmark, left
		mark.texture = load("res://assets/ui/Ooze-Syndicate-Wordmark.svg")
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mark)
		mark.position = Vector2(x, h * 0.2)
		mark.size = Vector2(112, h * 0.6)
		x += 112.0 + 26.0
	var c := UiKit.label(menu, crumb.to_upper(), 12, UiKit.MUTED, true, 3)
	c.position = Vector2(x, (h - c.get_minimum_size().y) / 2.0)
	add_child(c)
	if slim:
		queue_redraw()
		return
	# right to left: "?", the gear, the level block, the balances
	var help := _square("?", Vector2(w - 14.0 - q, (h - q) / 2.0), q, f)
	help.tooltip_text = "HELP"
	help.pressed.connect(func(): help_pressed.emit.call_deferred())
	var gear := _square("", help.position - Vector2(q + 8.0, 0), q, f)
	gear.tooltip_text = "OPTIONS"
	gear.pressed.connect(func(): options_pressed.emit.call_deferred())
	var glyph := Control.new()                       # a drawn gear (no icon for it in the kit yet)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.position = gear.position
	glyph.size = gear.size
	glyph.draw.connect(func(): _draw_gear(glyph, q))
	add_child(glyph)
	var lf := Progression.level_for(Progression.xp)
	_level = int(lf["level"])
	var cf := f if Campaign.has_content(f) else "vex"
	var top := UiKit.label(menu, "LEVEL %d" % _level, 15, UiKit.INK, true)
	var sub := UiKit.label(menu, "%d / %d campaign stars" % [Campaign.stars_total(cf), Campaign.stars_max(cf)], 12, UiKit.MUTED)
	var text_w := maxf(UiKit.text_w(menu, top.text, 15, true), UiKit.text_w(menu, sub.text, 12))
	_ring_r = minf(17.0, h * 0.28)
	var block_w := _ring_r * 2.0 + 12.0 + text_w
	var bx := gear.position.x - 22.0 - block_w
	_ring_c = Vector2(bx + _ring_r, h / 2.0)
	var th := top.get_minimum_size().y + sub.get_minimum_size().y
	top.position = Vector2(bx + _ring_r * 2.0 + 12.0, (h - th) / 2.0)
	sub.position = top.position + Vector2(0, top.get_minimum_size().y)
	add_child(top)
	add_child(sub)
	var prof := UiKit.flat_button(menu, "", 12)       # the whole level block is PROFILE's tap target
	prof.tooltip_text = "PROFILE"
	prof.position = Vector2(bx - 6.0, 0)
	prof.size = Vector2(block_w + 12.0, h)
	prof.pressed.connect(func(): profile_pressed.emit.call_deferred())
	add_child(prof)
	var bxr := bx - 18.0                              # PROGRESSION: SCRAP and CHIPS, as on the old profile card
	var p := UiKit.pt(menu)                           # the ticker sizes in pt: exact on phones, the old card's size on desktop
	for cur in ["premium", "soft"]:
		var t := RewardTicker.make(Progression.balance(cur), cur, func(n: float) -> float: return n / p if p > 0.0 else n * 0.62 * 1.6 * UiKit.K)
		t.sign = false
		t.named = false
		t.tooltip_text = Rules.CURRENCY_NAMES.get(cur, "")
		t.fit()
		add_child(t)
		t.play(true)
		bxr -= t.size.x
		t.position = Vector2(bxr, (h - t.size.y) / 2.0)
		bxr -= 16.0
	queue_redraw()


func _square(text: String, pos: Vector2, q: float, f: String) -> Button:
	var b := UiKit.make_btn(menu, text, Vector2(q, q), Callable(), "selected", f, 20)
	b.position = pos
	b.clip_text = false
	add_child(b)
	return b


func _draw_gear(c: Control, q: float) -> void:
	var o := Vector2(q, q) / 2.0
	var r := q * 0.19
	var col := UiKit.INK
	for i in range(8):                                 # eight teeth
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(o + d * r * 0.9, o + d * r * 1.45, col, q * 0.085)
	c.draw_arc(o, r, 0.0, TAU, 32, col, q * 0.07, true)
	c.draw_arc(o, r * 0.42, 0.0, TAU, 20, col, q * 0.05, true)


func _draw() -> void:
	var sf: Vector4 = menu.safe                       # the back reaches over the notch bands and the status bar
	draw_rect(Rect2(-sf.x, -sf.y, size.x + sf.x + sf.z, size.y + sf.y), UiKit.BAR)   # (drawn here: children would cover the ring)
	draw_rect(Rect2(-sf.x, size.y - 1.0, size.x + sf.x + sf.z, 1.0), Color(_ring_col, 0.3))
	if slim:
		return
	draw_circle(_ring_c, _ring_r, UiKit.BASE)
	draw_arc(_ring_c, _ring_r, 0.0, TAU, 40, Color(_ring_col, 0.9), 1.5, true)
	var font := UiKit.BODY
	var fs := UiKit.px(menu, 15)
	var s := str(_level)
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, _ring_c + Vector2(-tw / 2.0, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
