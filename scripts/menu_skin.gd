class_name MenuSkin
extends RefCounted
## Round 40B2 menu chrome (0.24.5 import, designer 9's list): the painted pieces of
## `References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/40-ui-hybrid-chamfer-B2/cut` at 2x
## (1 px = 0.5 pt; the menu canvas is about 2 units per pt), in assets/ui/menu40. Ivory P7 keys, dark glass plates, tabs.
## COLOUR RULE: neon = SEAT colour. The seat rims are inherited state masks (white, alpha = coverage; 40A) composited over
## the painted piece in the seat's colour at run time and cached per (piece, colour); goo is never touched here.
const DIR := "res://assets/ui/menu40/"
const INK_DARK := Color("1a1710")                   # lettering on ivory
static var _cache := {}


static func seat() -> Color:
	return Rules.seat_color("A")                    # the local player in the menus: seat A (cyan by default)


static func img(n: String) -> Image:
	var t := load(DIR + n + ".png") as Texture2D
	return t.get_image() if t != null else null


static func tinted(piece: String, mask: String, col: Color) -> Texture2D:
	## `piece` with `mask` painted in `col` (alpha of the mask = how much); no mask = the piece as painted.
	var key := "%s|%s|%s" % [piece, mask, col.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = load(DIR + piece + ".png")
	if mask != "" and t != null:
		var base := img(piece)
		var m := img(mask)
		if base != null and m != null and base.get_size() == m.get_size():
			base.convert(Image.FORMAT_RGBA8)
			m.convert(Image.FORMAT_RGBA8)
			var bd := base.get_data()
			var md := m.get_data()
			var r8 := col.r8
			var g8 := col.g8
			var b8 := col.b8
			for i in range(0, bd.size(), 4):
				var a: int = md[i + 3]
				if a > 0:
					var k := a / 255.0
					bd[i] = int(lerpf(bd[i], r8, k))
					bd[i + 1] = int(lerpf(bd[i + 1], g8, k))
					bd[i + 2] = int(lerpf(bd[i + 2], b8, k))
			t = ImageTexture.create_from_image(Image.create_from_data(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8, bd))
	_cache[key] = t
	return t


static func box(tex: Texture2D, ltrb: Vector4, mod := Color.WHITE, margin := Vector2(14, 6)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = ltrb.x
	s.texture_margin_top = ltrb.y
	s.texture_margin_right = ltrb.z
	s.texture_margin_bottom = ltrb.w
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.modulate_color = mod
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s


static func ivory(kind: String) -> Array:
	## [piece, rim mask, ltrb margins] of the ivory keys: primary = P7 with the seat rim, small = nav / chip key.
	match kind:
		"primary":
			return ["GEO-P7", "MASK-P7-ACCENT-RIM", Vector4(20, 0, 20, 0)]
		"small":
			return ["GEO-P7-small", "", Vector4(20, 0, 20, 0)]
		_:
			return ["GEO-P7-secondary", "", Vector4(20, 0, 20, 0)]


static func style_ivory(b: Button, kind: String) -> void:
	b.set_meta("mskin", "tab" if kind == "tab" else "key")
	_settle.call_deferred(b)
	## An ivory key (P7): normal, a touch lighter on hover, pressed darker; lettering dark; the seat rim on `primary`.
	var spec := ivory(kind)
	var col := seat()
	var tex := tinted(spec[0], spec[1], col)
	b.add_theme_stylebox_override("normal", box(tex, spec[2]))
	b.add_theme_stylebox_override("hover", box(tex, spec[2], Color(1.06, 1.06, 1.04)))
	b.add_theme_stylebox_override("pressed", box(tex, spec[2], Color(0.86, 0.85, 0.8)))
	b.add_theme_stylebox_override("hover_pressed", box(tex, spec[2], Color(0.86, 0.85, 0.8)))
	b.add_theme_stylebox_override("disabled", strip(0.75))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, INK_DARK)
	b.add_theme_color_override("font_disabled_color", UiKit.INK)


static func style_tab(b: Button, active: bool) -> void:
	b.set_meta("mskin", "tab")
	b.set_meta("mrim", active)
	_settle.call_deferred(b)
	## A dark glass tab (M-D); `active` carries the seat-colour rim (picked tiles, chips, the top-right round keys).
	var col := seat()
	var tex := tinted("GEO-M-D", "MASK-M-D-ACTIVE" if active else "", col)
	var m := Vector4(28, 0, 28, 0)
	b.add_theme_stylebox_override("normal", box(tex, m))
	b.add_theme_stylebox_override("hover", box(tex, m, Color(1.18, 1.18, 1.18)))
	b.add_theme_stylebox_override("pressed", box(tex, m, Color(0.8, 0.8, 0.8)))
	b.add_theme_stylebox_override("hover_pressed", box(tex, m, Color(0.8, 0.8, 0.8)))
	b.add_theme_stylebox_override("disabled", strip(0.75))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, INK_DARK)
	b.add_theme_color_override("font_disabled_color", UiKit.INK)


static func plate(fill_alpha := 1.0, strong := false) -> StyleBoxTexture:
	## The content panel (M-E dark glass, 9-slice 14 pt = 28 px); `fill_alpha` < 1 lets the painting through (HOME: 0.6).
	return box(load(DIR + "SHELL-M-E.png"), Vector4(28, 28, 28, 30), Color(1, 1, 1, fill_alpha), Vector2(14, 12))


static func strip(fill_alpha := 1.0) -> StyleBoxTexture:
	## A bar (M-C dark glass plate, stretched across): top bar, nav bar.
	return box(load(DIR + "SHELL-M-C.png"), Vector4(28, 14, 28, 14), Color(1, 1, 1, fill_alpha), Vector2(14, 0))


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


static func _settle(b: Button) -> void:
	## Ivory is for compact keys that carry only their own lettering. A key that is big (rows, tiles, cards), or has children laid
	## over it (emblems, captions, numbers in light ink), takes the dark glass card instead (the seat rim when picked); a compact
	## key whose caller set a light font colour gets dark lettering.
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var col := seat()
	var big := b.size.y > 190.0 or b.get_child_count() > 0
	var tab: bool = str(b.get_meta("mskin", "")) == "tab"
	if big:
		var card := plate()
		var ring := (UiKit.sb(Color(col.darkened(0.8), 0.96), col, 2) if (tab and b.get_meta("mrim", false)) else null)
		var norm: StyleBox = ring if ring != null else card
		b.add_theme_stylebox_override("normal", norm)
		b.add_theme_stylebox_override("hover", ring if ring != null else box(load(DIR + "SHELL-M-E.png"), Vector4(28, 28, 28, 30), Color(1.25, 1.25, 1.25), Vector2(14, 12)))
		b.add_theme_stylebox_override("pressed", ring if ring != null else box(load(DIR + "SHELL-M-E.png"), Vector4(28, 28, 28, 30), Color(0.75, 0.75, 0.75), Vector2(14, 12)))
		b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
		b.add_theme_stylebox_override("disabled", plate(0.6))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			if b.has_theme_color_override(k) and _lum(b.get_theme_color(k)) < 0.4:
				b.add_theme_color_override(k, UiKit.INK)
	else:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			if b.has_theme_color_override(k) and _lum(b.get_theme_color(k)) > 0.6:
				b.add_theme_color_override(k, INK_DARK)
