class_name UiKit
extends RefCounted
## Alpha 21 UI pass - ONE visual language for every menu page (Daniele's screen system, 2026-09-28: "Alpha 20 UI
## Expansion", used as direction, in our neon cyber style; SCREEN-SYSTEM.md's tokens below). Sizes are 1280x720
## CANVAS units - what the shell pages lay out in - not Alpha 11's raw units (menu.gd's P() / K); the phone minimums
## (44 pt taps, 12.5 pt text) come from Menu's live viewport fit, so every piece keeps the same rules on phones.
##
## The building blocks (each adds itself to the menu's page, `m.content`, and returns the node):
##   btn(m, text, pos, dims, call, kind, f)    kind "primary" (solid accent, dark text - one per area) | "secondary"
##                                             (dark, quiet frame) | "selected" (tinted fill, accent frame) | "tertiary"
##   panel(m, pos, dims, f, selected)          an opaque clipped-corner surface under text
##   title(m, x, y, kicker, headline, f)       the page's kicker ("03 / SETUP") + headline ("READY TO DEPLOY.")
##   back_link(m, right_x, y, call)            "<- BACK", top right of a page (phones' subflows put it in the bar)
##   row(m, pos, dims, num, title, sub, call, f, selected)   a numbered row with a chevron ("01  SCORCH / Active skill")
##   chip(m, text, pos, call, f, selected)     a filter / tab chip, auto width
##   stat(m, pos, value, caption)              "100%" over "Speed · Baseline"
##   tag(m, text, pos, f)                      "EMBER / MAW" with the accent bar
##   stars(m, n, of, pos, size)                filled gold / unfilled, plus the count
##   bar(m, pos, dims, frac, f)                a progress bar
##   hero(m, f, pos, dims)                     the faction's original character (transparent cutout)
## Faction accents are UI colours (SCREEN-SYSTEM.md), separate from the match's ownership colours (Rules).

const HEAD := preload("res://assets/fonts/RussoOne-Regular.ttf")
const BODY := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const SYMBOLS := preload("res://assets/fonts/DejaVuSansMono.woff2")   # arrows, stars, ticks (Hud.SYMBOL_FONT)
# Rajdhani and Russo One have no arrows (← →), stars (★ ☆) or ticks (✓), and the web build has no system fonts to
# fall back on (they showed as boxes): both faces take DejaVu Sans Mono as their fallback, once, when UiKit loads -
# the shared font resources, so every label in the game gets it.
static var _symbols_ready := _add_symbol_fallback()


static func _add_symbol_fallback() -> bool:
	for f: Font in [HEAD, BODY]:
		if not f.fallbacks.has(SYMBOLS):
			var fb := f.fallbacks.duplicate()
			fb.append(SYMBOLS)
			f.fallbacks = fb
	return true
const BASE := Color("041016")                      # base surface
const PANEL := Color("071820")                     # panel surface, opaque beneath text
const INK := Color("e8f6fa")                       # primary text
const MUTED := Color("a6bfca")                     # secondary text
const DIM := Color("5f7a86")                       # captions, unavailable
const FRAME := Color("255363")                     # quiet frame
const CYAN := Color("14d3e4")                      # VEX / neutral action
const STAR := Color("ffce68")                      # earned stars
const WEAKER := Color("ff4f64")                    # a stat below baseline - a rose red no faction accent is near (Daniele:
                                                  # the old amber read like EMBER / SOLAR)
const BAR := Color("041016f2")                     # top / bottom bars
const CARD := Color("071820f0")                    # card fill
const ACCENTS := {"vex": Color("14d3e4"), "null": Color("f327c3"), "bloom": Color("a1eb39"),
		"ember": Color("ff7c19"), "solar": Color("ffce58")}
const ORDER := ["vex", "null", "bloom", "ember", "solar"]
const NAMES := {"vex": "VEX", "null": "NULL", "bloom": "VIRIDIAN", "ember": "EMBER", "solar": "SOLAR"}
const SUBS := {"vex": "BIOENGINEERS", "null": "CARTEL", "bloom": "BLOOM", "ember": "MAW", "solar": "SHELLS"}
const TAGS := {"vex": "VEX / BIOENGINEERS", "null": "NULL / CARTEL", "bloom": "VIRIDIAN / BLOOM",
		"ember": "EMBER / MAW", "solar": "SOLAR / SHELLS"}
const CUT := 10                                    # the standard corner cut
const CFG := "user://ui.cfg"
const K := 1280.0 / 1672.0                       # = Menu.K, Menu.MIN_TAP_PT, Menu.MIN_FONT_PT - copied so the pieces
const MIN_TAP_PT := 44.0                          #   (and their tests) load without menu.gd and its autoloads
const MIN_FONT_PT := 12.5


static func accent(f: String) -> Color:
	return ACCENTS.get(f, CYAN)


static func pt(m) -> float:
	## One canvas unit in pt at the live fit (landscape-phone reference); 0.0 on desktop (no minimum).
	var f: float = m._pt_factor()
	return f / K if f > 0.0 else 0.0


static func tap_h(m, h: float) -> float:
	## A tappable height in canvas units: `h`, or taller where a phone needs it for 44 pt.
	var p := pt(m)
	return maxf(h, MIN_TAP_PT / p) if p > 0.0 else h


static func px(m, size: float) -> int:
	## A font size in canvas units, grown on phones to >= 12.5 pt.
	var p := pt(m)
	return int(round(maxf(size, MIN_FONT_PT / p) if p > 0.0 else size))


static func label(m, text: String, size: float, col := INK, head := false, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	var font: Font = HEAD if head else BODY
	if spacing != 0:                                 # the spaced-out kickers / breadcrumbs
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = spacing
		font = fv
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px(m, size))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func text_w(m, text: String, size: float, head := false) -> float:
	## A one-line text's width at its (phone-grown) size - Label.get_minimum_size() is unreliable before the tree.
	return (HEAD if head else BODY).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px(m, size)).x


static func text_h(m, text: String, size: float, width: float, head := false) -> float:
	## A word-wrapped text's height inside `width` (for laying out before the label is in the tree).
	var f: Font = HEAD if head else BODY
	return f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, px(m, size), -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y


static func line_h(m, size: float, head := false) -> float:
	## One line's height at a (phone-grown) size.
	return (HEAD if head else BODY).get_height(px(m, size))


static func rect(pos: Vector2, dims: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = dims
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func add(m, node: Control, pos: Vector2) -> Control:
	node.position = pos
	m.content.add_child(node)
	return node


# ------------------------------------------------------------------ surfaces and buttons
static func sb(fill: Color, border := Color(0, 0, 0, 0), bw := 0, cut := CUT, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	## A clipped-corner box: StyleBoxFlat's corner_detail 1 turns each radius into a straight 45-degree cut.
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(cut)
	s.corner_detail = 1
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if glow.a > 0.0:
		s.shadow_color = glow
		s.shadow_size = 8
	s.set_content_margin_all(10)
	return s


static func style_button(b: Button, kind: String, f := "vex") -> void:
	var a := accent(f)
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	var fc := INK
	match kind:
		"primary":                                    # solid accent, dark text, a soft glow of its own colour
			normal = sb(a, a.lightened(0.25), 1, CUT, Color(a, 0.28))
			hover = sb(a.lightened(0.12), a.lightened(0.4), 1, CUT, Color(a, 0.4))
			pressed = sb(a.darkened(0.18), a, 1, CUT)
			fc = BASE
		"selected":                                   # tinted fill, accent frame (tabs, chips, picked tiles)
			normal = sb(Color(a.darkened(0.72), 0.94), a, 2)
			hover = sb(Color(a.darkened(0.62), 0.96), a.lightened(0.2), 2)
			pressed = sb(Color(a.darkened(0.55), 0.96), a, 2)
		"tertiary":                                   # text-led
			normal = sb(Color(0, 0, 0, 0))
			hover = sb(Color(a, 0.08))
			pressed = sb(Color(a, 0.16))
		_:                                            # secondary: dark surface, quiet frame, the accent on hover
			normal = sb(Color(PANEL, 0.94), FRAME, 1)
			hover = sb(Color(PANEL.lightened(0.05), 0.96), a, 1)
			pressed = sb(Color(a.darkened(0.7), 0.96), a, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", sb(Color(PANEL, 0.7), Color(FRAME, 0.5), 1))
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc if kind == "primary" else (a if kind == "tertiary" else INK))
	b.add_theme_color_override("font_pressed_color", fc if kind == "primary" else INK)
	b.add_theme_color_override("font_hover_pressed_color", fc if kind == "primary" else INK)
	b.add_theme_color_override("font_focus_color", fc)
	b.add_theme_color_override("font_disabled_color", DIM)


static func make_btn(m, text: String, dims: Vector2, call: Callable, kind := "secondary", f := "vex", size := 16.0) -> Button:
	## A button, not yet placed: text in the display face, at least 44 pt tall on phones.
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HEAD)
	b.add_theme_font_size_override("font_size", px(m, size))
	b.clip_text = true
	style_button(b, kind, f)
	dims.y = tap_h(m, dims.y)
	b.custom_minimum_size = dims
	b.size = dims
	if call.is_valid():
		var ui := "confirm" if kind == "primary" else "tap"   # SOUND: the primary action confirms, the rest tap (sfx.gd)
		b.pressed.connect(func():
			Sfx.play_ui(ui)
			call.call_deferred())
	return b


static func btn(m, text: String, pos: Vector2, dims: Vector2, call: Callable, kind := "secondary", f := "vex", size := 16.0) -> Button:
	return add(m, make_btn(m, text, dims, call, kind, f, size), pos) as Button


static func flat_button(m, text: String, size: float, col := INK) -> Button:
	## A text-only button ("CONTINUE CAMPAIGN", "NEW HERE? START TRAINING ->"): no frame, still a full tap target.
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", HEAD)
	b.add_theme_font_size_override("font_size", px(m, size))
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", CYAN)
	b.add_theme_color_override("font_pressed_color", CYAN)
	var none := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(s, none)
	return b


static func panel(m, pos: Vector2, dims: Vector2, f := "", selected := false, fill := CARD) -> Panel:
	## An opaque surface: the quiet frame, or the accent (with a tinted fill) when `selected`.
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := accent(f)
	p.add_theme_stylebox_override("panel", sb(Color(a.darkened(0.8), 0.95) if selected else fill, a if selected else FRAME, 2 if selected else 1))
	p.size = dims
	return add(m, p, pos) as Panel


# ------------------------------------------------------------------ text blocks
static func title(m, x: float, y: float, kicker: String, headline: String, f := "vex", size := 34.0) -> float:
	## A page's kicker + headline; returns the y under them.
	var k := label(m, kicker.to_upper(), 12, accent(f), true, 3)
	add(m, k, Vector2(x, y))
	y += k.get_minimum_size().y + 2.0
	var h := label(m, headline.to_upper(), size, INK, true)
	add(m, h, Vector2(x - 2.0, y))
	return y + h.get_minimum_size().y


static func back_link(m, right_x: float, y: float, call: Callable) -> Button:
	var b := flat_button(m, "←  BACK", 15)
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var w := text_w(m, b.text, 15, true) + 20.0
	b.size = Vector2(w, tap_h(m, 36.0))
	b.pressed.connect(func():
		Sfx.play_ui("back")                                 # SOUND
		call.call_deferred())
	return add(m, b, Vector2(right_x - w, y)) as Button


static func row(m, pos: Vector2, dims: Vector2, num: String, title_text: String, sub: String, call: Callable,
		f := "vex", selected := false, chevron := true) -> Button:
	## A numbered row: "01" in the accent, the title over a caption, a chevron; the whole row is the target.
	dims.y = tap_h(m, dims.y)
	var b := make_btn(m, "", dims, call, "selected" if selected else "secondary", f)
	add(m, b, pos)
	var x := 16.0
	if num != "":
		var n := label(m, num, 22, accent(f), true)
		n.position = Vector2(x, (dims.y - n.get_minimum_size().y) / 2.0)
		b.add_child(n)
		x += text_w(m, num, 22, true) + 14.0
	var t := label(m, title_text.to_upper(), 16, INK, true)
	var s := label(m, sub, 13, MUTED)
	var th := t.get_minimum_size().y + (s.get_minimum_size().y if sub != "" else 0.0)
	t.position = Vector2(x, (dims.y - th) / 2.0)
	t.clip_text = true
	t.size = Vector2(dims.x - x - 36.0, t.get_minimum_size().y)
	b.add_child(t)
	if sub != "":
		s.position = t.position + Vector2(0, t.get_minimum_size().y)
		s.clip_text = true
		s.size = Vector2(dims.x - x - 36.0, s.get_minimum_size().y)
		b.add_child(s)
	if chevron:
		var c := label(m, "›", 22, MUTED)
		c.position = Vector2(dims.x - 26.0, (dims.y - c.get_minimum_size().y) / 2.0)
		b.add_child(c)
	return b


static func chip(m, text: String, pos: Vector2, call: Callable, f := "vex", selected := false, size := 14.0) -> Button:
	var w := text_w(m, text.to_upper(), size, true) + 32.0
	return btn(m, text.to_upper(), pos, Vector2(maxf(w, 56.0), 40.0), call, "selected" if selected else "secondary", f, size)


static func stat(m, pos: Vector2, value: String, caption: String, col := INK) -> float:
	## A value over its caption; returns the block's width.
	var v := label(m, value, 22, col, true)
	add(m, v, pos)
	var c := label(m, caption, 12, MUTED)
	add(m, c, pos + Vector2(0, v.get_minimum_size().y))
	return maxf(text_w(m, value, 22, true), text_w(m, caption, 12))


static func tag(m, text: String, pos: Vector2, f := "vex", mark := true) -> Vector2:
	## "EMBER / MAW": a dark plate with the accent bar on its left and the faction's emblem (`mark`); returns its size.
	var l := label(m, text.to_upper(), 14, INK, true, 2)
	var lh := l.get_minimum_size().y
	var es := lh + 6.0 if mark else 0.0
	var dims := Vector2(text_w(m, text.to_upper(), 14, true) + text.length() * 2.0 + 30.0 + (es + 6.0 if mark else 0.0), lh + 14.0)
	m.content.add_child(rect(pos, dims, Color(BASE, 0.88)))
	m.content.add_child(rect(pos, Vector2(3.0, dims.y), accent(f)))
	if mark:
		emblem_rect(m, f, pos + Vector2(12.0, (dims.y - es) / 2.0), es)
	add(m, l, pos + Vector2(16.0 + (es + 6.0 if mark else 0.0), 7.0))
	return dims


const STAR_OFF := Color(1.0, 0.808, 0.408, 0.3)   # an unearned star: the same filled star, faint (the sweep: the thin
                                                  # outline glyph read as ~5 pt)


static func star_row(m, n: int, of: int, size: float) -> HBoxContainer:
	## Earned stars bright gold, the rest the same filled star faint - one row, not yet placed.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	if n > 0:
		row.add_child(label(m, "★".repeat(n), size, STAR))
	if of - n > 0:
		row.add_child(label(m, "★".repeat(of - n), size, STAR_OFF))
	return row


static func stars(m, n: int, of: int, pos: Vector2, size := 20.0, count := true) -> Control:
	## The star row and the number beside it, so it never rests on colour alone.
	var row := star_row(m, maxi(0, n), maxi(0, of), size)
	if count:
		row.add_child(label(m, "   %d / %d" % [n, of], size * 0.85, STAR if n > 0 else MUTED))
	return add(m, row, pos)


static func bar(m, pos: Vector2, dims: Vector2, frac: float, f := "vex") -> void:
	m.content.add_child(rect(pos, dims, Color(FRAME, 0.6)))
	m.content.add_child(rect(pos, Vector2(dims.x * clampf(frac, 0.0, 1.0), dims.y), accent(f)))


# ------------------------------------------------------------------ real points on the web
static var _ppp := 0.0                             # pt_per_px's last answer, and the frame / viewport it was for
static var _ppp_frame := -1
static var _ppp_vp := Vector2.ZERO


static func pt_per_px(vp: Vector2) -> float:
	## Points per viewport pixel on a phone. The web page knows its real size in CSS px (= iOS points, Android dp) via
	## web/viewport-fix.js's OozeViewport.size(); elsewhere the landscape-phone reference (390 pt tall) stands in, as it
	## always did. The iPhone sweep (0.21.5): the 390 guess left taps at 42-43 pt and text near 10.5 pt on the shorter
	## iPhones. Cached per frame - every px() / tap_h() asks.
	var frame := Engine.get_process_frames()
	if frame == _ppp_frame and vp == _ppp_vp:
		return _ppp
	_ppp_frame = frame
	_ppp_vp = vp
	_ppp = MIN_PHONE_REF / maxf(vp.y, 1.0)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js = JavaScriptBridge.eval("window.OozeViewport ? OozeViewport.size().join(',') : ''", true)
		var f := str(js).split(",")
		if f.size() == 2 and float(f[0]) > 0.0 and vp.x > 0.0:
			_ppp = float(f[0]) / vp.x
	return _ppp


const MIN_PHONE_REF := 390.0                       # = Menu.PHONE_PT_H: the landscape phone the sizes assume off the web


# ------------------------------------------------------------------ the safe area (notch, Dynamic Island, home indicator)
static var test_insets := _arg_insets()            # screenshots / tests: fake insets in viewport px (x < 0: the device's)


static func _arg_insets() -> Vector4:
	## --safe-insets=left,top,right,bottom (viewport px): a notched phone's bands on a desktop window, for screenshots.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--safe-insets="):
			var v := a.substr(14).split(",")
			if v.size() == 4:
				return Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return Vector4(-1, -1, -1, -1)


static func safe_insets(vp: Vector2) -> Vector4:
	## The device's unsafe bands in viewport px - left, top, right, bottom - from the same sources as main._apply_safe_area
	## (the web page's env() insets via web/viewport-fix.js, a native phone's display safe area), without the HUD's own
	## padding. Zero on desktop. The menu shell, VersusScreen and MatchScreens keep their controls inside them (the
	## Architect's iPhone sweep, 0.21.5: only the battle HUD did).
	if test_insets.x >= 0.0:
		return test_insets
	var ins := Vector4.ZERO
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js = JavaScriptBridge.eval("window.OozeViewport ? OozeViewport.safe().concat(OozeViewport.size()).join(',') : ''", true)
		var f := str(js).split(",")
		if f.size() == 6 and float(f[4]) > 0.0:
			var kw := vp.x / float(f[4])                 # CSS px -> viewport units
			ins = Vector4(float(f[0]), float(f[1]), float(f[2]), float(f[3])) * kw
	if OS.has_feature("mobile"):
		var screen := Vector2(DisplayServer.screen_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.screen_get_position())
		var k := vp.x / maxf(screen.x, 1.0)
		ins = Vector4(maxf(ins.x, safe.position.x * k), maxf(ins.y, safe.position.y * k),
				maxf(ins.z, (screen.x - safe.end.x) * k), maxf(ins.w, (screen.y - safe.end.y) * k))
	return ins


# ------------------------------------------------------------------ art
static func hero_path(f: String) -> String:
	return "res://assets/art/ui/hero_%s.png" % (f if ACCENTS.has(f) else "vex")


static func hero(m, f: String, pos: Vector2, dims: Vector2, glow := true) -> TextureRect:
	## The faction's original character, standing in `dims` (tools/ui_art.py cut them from Alpha 12's references);
	## a soft accent glow behind it.
	if glow:
		var g := TextureRect.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(accent(f), 0.28))
		grad.set_color(1, Color(accent(f), 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.55)
		gt.fill_to = Vector2(0.5, 0.0)
		g.texture = gt
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size = dims * 1.3
		add(m, g, pos - dims * 0.15)
	var r := TextureRect.new()
	r.texture = load(hero_path(f))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = dims
	return add(m, r, pos) as TextureRect


# ------------------------------------------------------------------ the race emblems (THE faction mark, everywhere)
## Daniele's race emblems v2 (Art/Interface/Final set 2026-09-28/emblems; SOLAR = v2), cut out by tools/ui_art.py:
## emblem_<f>.png (192 px) and emblem_<f>_32.png (32 px, downsampled offline so small spots stay crisp). Every faction
## mark reads from here: the menus (emblem / emblem_rect), the HUD's badges, chips and inspector (Hud.emblem_texture ->
## emblem_mip, tinted in the seat colour there), the lobby's hex chips (their white silhouette).
static var _emblem_mips := {}


static func emblem_path(f: String, small := false) -> String:
	return "res://assets/art/ui/emblem_%s%s.png" % [f if ACCENTS.has(f) else "vex", "_32" if small else ""]


static func emblem(f: String, px := 64.0) -> Texture2D:
	## The faction's emblem for a spot `px` canvas units across (<= 40: the 32 px cut).
	var p := emblem_path(f, px <= 40.0)
	return load(p) if ResourceLoader.exists(p) else null


static func emblem_mip(f: String) -> Texture2D:
	## The 192 px emblem with mipmaps (made once per faction), for spots drawn at many sizes (the HUD's badges scale
	## with ui_scale; TEXTURE_FILTER_LINEAR_WITH_MIPMAPS there); the small levels' coverage lifted so the thin ring
	## keeps reading as a line at ~18 px.
	if _emblem_mips.has(f):
		return _emblem_mips[f]
	var tex := emblem(f, 192.0)
	var out: Texture2D = tex
	var img: Image = tex.get_image() if tex else null
	if img and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.fix_alpha_edges()                          # no dark fringe in the smaller mip levels
		img.generate_mipmaps()
		var lut := PackedByteArray()
		lut.resize(256)
		for a in range(256):
			lut[a] = int(round(255.0 * pow(a / 255.0, 0.6)))
		var data := img.get_data()
		var from := img.get_mipmap_offset(mini(2, img.get_mipmap_count()))
		for i in range(from + 3, data.size(), 4):
			data[i] = lut[data[i]]
		img = Image.create_from_data(img.get_width(), img.get_height(), true, Image.FORMAT_RGBA8, data)
		out = ImageTexture.create_from_image(img)
	_emblem_mips[f] = out
	return out


static func emblem_rect(m, f: String, pos: Vector2, side: float) -> TextureRect:
	## The faction's emblem, `side` canvas units square, added to the page at `pos` (its own colours: a faction mark;
	## ownership stays the seat colour beside it).
	var r := TextureRect.new()
	r.texture = emblem(f, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(side, side)
	return add(m, r, pos) as TextureRect


static func map_thumb(path: String) -> Texture2D:
	## A map's menu thumbnail (MapPool.thumb, 960x540) without its baked caption strip (the bottom 11 %: name and modes in
	## ~4 pt type on a phone - the iPhone sweep - which every page already writes out beside it). The map itself is whole.
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Rect2(Vector2.ZERO, Vector2(t.get_width(), roundf(t.get_height() * 0.885)))
	return a


static func background(f: String) -> Texture2D:
	## The faction's FINAL wallpaper (Daniele 2026-09-28; the pages' backdrop and HOME's scene).
	var p := "res://assets/art/ui/bg_%s.jpg" % (f if ACCENTS.has(f) else "vex")
	return load(p) if ResourceLoader.exists(p) else null


static func stage(f: String) -> Texture2D:
	## The faction's empty VERSUS stage (Daniele's FINAL set; a creature cutout stands on its platform).
	var p := "res://assets/art/ui/stage_%s.jpg" % (f if ACCENTS.has(f) else "vex")
	return load(p) if ResourceLoader.exists(p) else null


# ------------------------------------------------------------------ the last played faction (HOME's hero)
static var path := CFG                             # tests point it elsewhere; UI preferences only, never progression


static func last_faction() -> String:
	## Daniele 2026-09-28: HOME always shows the faction you played last - VEX until you have played one.
	var c := ConfigFile.new()
	if c.load(path) != OK:                           # none yet, or no storage at all (private browsing)
		return "vex"
	var f := str(c.get_value("home", "faction", "vex"))
	return f if Rules.FACTIONS.has(f) else "vex"


static func save_last_faction(f: String) -> bool:
	if not Rules.FACTIONS.has(f):
		return false
	var c := ConfigFile.new()
	c.load(path)                                      # keep anything else saved there (none: a fresh file)
	c.set_value("home", "faction", f)
	return c.save(path) == OK


static func campaign_view() -> String:
	## CAMPAIGN opens on the view you used last: "map" (the 3D city - Daniele 2026-09-28: "i like the current campaign
	## map view", the default) or "cards" (the mission cards).
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return "map"
	return "cards" if str(c.get_value("campaign", "view", "map")) == "cards" else "map"


static func save_campaign_view(v: String) -> bool:
	var c := ConfigFile.new()
	c.load(path)
	c.set_value("campaign", "view", "cards" if v == "cards" else "map")
	return c.save(path) == OK


static func hero_art(f: String) -> Texture2D:
	## The faction's full scene (assets/art/<faction>.png; VEX's is the old MAIN art minus its baked-in buttons) -
	## FrameCard's default art.
	if f == "vex":
		var art: Texture2D = load("res://assets/art/ui-main.png")
		var clean := AtlasTexture.new()
		clean.atlas = art
		clean.region = Rect2(Vector2(art.get_size()) * Vector2(0.36, 0.0), Vector2(art.get_size()) * Vector2(0.64, 1.0))
		return clean
	return load("res://assets/art/%s.png" % f)
