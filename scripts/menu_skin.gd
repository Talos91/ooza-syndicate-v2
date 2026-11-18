class_name MenuSkin
extends RefCounted
## Round 43B copper punk menu chrome (ui-build-43b, Daniele's theme lock 2026-11-17): the painted pieces of
## `References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/43B-menu-paint/cut` at 2x
## (1 px = 0.5 pt; the menu canvas is about 2 units per pt) in assets/ui/menu43 (tools: ooze-wt/ui-build-43b-tools/prep43b.py).
## Same canvases / 9-slice margins as the 40B2 masters (board_geo_diff 0 failures). Cream keys, burgundy cabinet, smoked plum
## glass, bronze trim. Every key family has its four painted states (NORMAL / PRESSED / DISABLED / SELECTED); SELECTED carries
## a seat lamp (LAMP-WHITE mask) composited in the SEAT colour at run time. COLOUR RULE: neon = SEAT colour; goo never here.
const DIR := "res://assets/ui/menu43/"
const INK_DARK := Color("2a1620")                   # lettering on cream (burgundy-black)
const BRONZE := Color("c08a55")                     # the trim metal (selected rings)
const INK_OFF := Color("d9c6b4")                    # lettering on a DISABLED key
static var _cache := {}


static func seat() -> Color:
	return Rules.seat_color("A")                    # the local player in the menus: seat A (cyan by default)


static func img(n: String) -> Image:
	var t := load(DIR + n + ".png") as Texture2D
	return t.get_image() if t != null else null


static func tex(n: String) -> Texture2D:
	return load(DIR + n + ".png") as Texture2D


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
					bd[i + 3] = maxi(bd[i + 3], a)
			t = ImageTexture.create_from_image(Image.create_from_data(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8, bd))
	_cache[key] = t
	return t


static func selected_tex(piece: String) -> Texture2D:
	## A family's SELECTED paint with its lamp lit in the seat colour.
	return tinted(piece + "-SELECTED", piece + "-SELECTED-LAMP-WHITE", seat())


static func box(t: Texture2D, ltrb: Vector4, mod := Color.WHITE, margin := Vector2(14, 6)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = t
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


class LampBox extends StyleBox:
	## A plate with the SELECTED marks the keys carry (notes 1 / 10: one selected look everywhere): a bronze ring inside the
	## chamfer and the seat lamp, a 3 pt bar along the bottom (70 % wide). Picked cards, rows, tiles and panels.
	var inner: StyleBox
	var lamp := Color.CYAN
	var ring := Color("c08a55")
	var unit := 2.0                                   # canvas units per pt

	func _draw(ci: RID, r: Rect2) -> void:
		inner.draw(ci, r)
		var w := maxf(2.0, 1.2 * unit)
		var c := 10.0 * unit
		var pts := PackedVector2Array([r.position + Vector2(c, w), r.position + Vector2(r.size.x - w, w),
			r.position + Vector2(r.size.x - w, r.size.y - c), r.position + Vector2(r.size.x - c, r.size.y - w),
			r.position + Vector2(w, r.size.y - w), r.position + Vector2(w, c), r.position + Vector2(c, w)])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([ring]), w, true)
		var lw := r.size.x * 0.7
		var lh := 3.0 * unit
		var lr := Rect2(r.position.x + (r.size.x - lw) * 0.5, r.end.y - lh - 2.5 * unit, lw, lh)
		RenderingServer.canvas_item_add_rect(ci, lr.grow(unit * 1.5), Color(lamp, 0.25))
		RenderingServer.canvas_item_add_rect(ci, lr, lamp)
		RenderingServer.canvas_item_add_rect(ci, Rect2(lr.position.x, lr.position.y + lh * 0.35, lw, lh * 0.3), Color(1, 1, 1, 0.55))


static func lamp_plate(margin := Vector2(14, 12)) -> StyleBox:
	var s := LampBox.new()
	s.inner = box(tex("SHELL-M-E"), Vector4(28, 28, 28, 30), Color(1.22, 1.14, 1.12), margin)
	s.lamp = seat()
	s.ring = BRONZE
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s


const FONT_KEYS := ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]


static func ivory(kind: String) -> Array:
	## [piece family, ltrb margins, lit] of the cream keys. primary = P7 lit (the page's main action carries the seat lamp, as on
	## the 43B proofs); secondary / small plain; tab = small lit; quit = the dark QUIT control.
	match kind:
		"primary":
			return ["GEO-P7", Vector4(20, 0, 20, 0), true]
		"small":
			return ["GEO-P7-small", Vector4(20, 0, 20, 0), false]
		"quit":
			return ["GEO-P7-small-QUIT", Vector4(20, 0, 20, 0), false]
		"tab":
			return ["GEO-P7-small", Vector4(20, 0, 20, 0), true]
		_:
			return ["GEO-P7-secondary", Vector4(20, 0, 20, 0), false]


static func _states(b: Button, fam: String, m: Vector4, lit: bool) -> void:
	## The four painted states of one family (note 10: every key changes the same way; the shape never changes).
	var n: Texture2D = selected_tex(fam) if lit else tex(fam)
	var pr: Texture2D = tex(fam + "-PRESSED")
	b.add_theme_stylebox_override("normal", box(n, m))
	b.add_theme_stylebox_override("hover", box(n, m, Color(1.05, 1.04, 1.02)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", box(pr, m))
	b.add_theme_stylebox_override("hover_pressed", box(pr, m))
	b.add_theme_stylebox_override("disabled", box(tex(fam + "-DISABLED"), m))


static func style_ivory(b: Button, kind: String) -> void:
	if kind == "primary" or kind == "secondary":   # 45B (part 3): the remake's keys; primary = SELECTED copper + seat rim
		key45(b, kind == "primary")
		return
	b.set_meta("mskin", "tab" if kind == "tab" else ("quit" if kind == "quit" else "key"))
	_settle.call_deferred(b)
	var spec := ivory(kind)
	_states(b, spec[0], spec[1], spec[2])
	var ink := UiKit.INK if kind == "quit" else INK_DARK
	for k in FONT_KEYS:
		b.add_theme_color_override(k, ink)
	b.add_theme_color_override("font_disabled_color", INK_OFF)


static func key45(b: Button, lit: bool) -> void:
	## The 45B key (Kit45.KeyBox) on a Button: four states, lettering measured on each face (cream on copper, dark on cream).
	b.set_meta("mskin", "key45")
	_settle.call_deferred(b)
	var n := "SELECTED" if lit else "NORMAL"
	var mk := func(st: String, mod := Color.WHITE) -> StyleBox:
		var s := Kit45.KeyBox.new()
		s.st = st
		s.mod = mod
		s.content_margin_left = 14.0
		s.content_margin_right = 14.0
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
		return s
	b.add_theme_stylebox_override("normal", mk.call(n))
	b.add_theme_stylebox_override("hover", mk.call(n, Color(1.06, 1.05, 1.03)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", mk.call("PRESSED"))
	b.add_theme_stylebox_override("hover_pressed", mk.call("PRESSED"))
	b.add_theme_stylebox_override("disabled", mk.call("DISABLED"))
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, Kit45.key_ink(n))
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Kit45.key_ink("PRESSED"))
	b.add_theme_color_override("font_disabled_color", Kit45.key_ink("DISABLED"))


static func style_tab(b: Button, active: bool) -> void:
	## A tab / chip key (M-D, cream): `active` = the SELECTED paint with the seat lamp (picked tiles, chips, the top-right keys).
	b.set_meta("mskin", "tab")
	b.set_meta("mrim", active)
	_settle.call_deferred(b)
	_states(b, "GEO-M-D", Vector4(28, 0, 28, 0), active)
	for k in FONT_KEYS:
		b.add_theme_color_override(k, INK_DARK)
	b.add_theme_color_override("font_disabled_color", INK_OFF)


static func plate(fill_alpha := 1.0, strong := false) -> StyleBoxTexture:
	## The content panel (M-E smoked plum glass in its burgundy cabinet, 9-slice 14 pt = 28 px); `fill_alpha` < 1 lets the
	## painting through.
	return box(tex("SHELL-M-E"), Vector4(28, 28, 28, 30), Color(1, 1, 1, fill_alpha), Vector2(14, 12))


static func strip(fill_alpha := 1.0) -> StyleBoxTexture:
	## A bar (M-C burgundy cabinet strip, stretched across): top bar, nav bar, title bands.
	return box(tex("SHELL-M-C"), Vector4(28, 14, 28, 14), Color(1, 1, 1, fill_alpha), Vector2(14, 0))


static func icon(role: String) -> Texture2D:
	## 43B glyph (flat white mask, 128 px): NAV-HOME / NAV-ARMIES / NAV-PROFILE / NAV-GUIDE, CUR-1 / CUR-2, SKILL-<NAME>.
	return tex("ICON-" + role)


static func skill_icon(id: String) -> Texture2D:
	## The 43B skill glyph for a skill id (null when the pack has none: the caller keeps its own).
	var n := id.to_upper().replace("_", "-")
	var alias := {"OVERDRIVE": "SURGE", "SPORE": "SPORE-BURST", "GHOST": "GHOST-LINE", "FOG": "FOG-OF-WAR", "HACK": "RELAY-HACK",
		"RELAY-HIJACK": "RELAY-HACK", "EMERGENCY-EVAC": "EVAC"}
	n = alias.get(n, n)
	return tex("ICON-SKILL-" + n) if ResourceLoader.exists(DIR + "ICON-SKILL-" + n + ".png") else null


static func _put(m, parent: Control, c: Control, pos: Vector2) -> void:
	if parent != null:
		c.position = pos
		parent.add_child(c)
	else:
		UiKit.add(m, c, pos)


static func mark_tex(f: String, frame := 0) -> Texture2D:
	## 36B2 TECH LOOK mark: frame `frame` of the IDLE strip (12 x 512 px; frame 0 = the HUD pose).
	var t := AtlasTexture.new()
	t.atlas = load(DIR + "MARKS-" + ("AEGIS" if f == "solar" else f.to_upper()) + "-IDLE.png") as Texture2D
	t.region = Rect2(frame * 512, 0, 512, 512)
	return t


class MarkAnim extends TextureRect:
	## The IDLE loop (12 frames, 105 ms) for the big heroes.
	var _f := ""
	var _t := 0.0
	var _n := 0

	func start(f: String) -> void:
		_f = f
		set_process(true)

	func _process(dt: float) -> void:
		_t += dt
		var n := int(_t / 0.105) % 12
		if n != _n:
			_n = n
			texture = MenuSkin.mark_tex(_f, n)


static func ai_hero(m, f: String, pos: Vector2, s: float, mood := "", parent: Control = null, rim := Color(0, 0, 0, 0)) -> void:
	## The faction's AI mark (36A, its own colour) in a GEO-SOCKET (200 / 120) whose rim is the SEAT colour. mood "win": a soft
	## seat-colour burst behind it; "loss": a dim ring, no burst.
	var piece := "GEO-SOCKET-200" if s > 160.0 else "GEO-SOCKET-120"
	var col := seat() if rim.a == 0.0 else rim
	if mood == "win":
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.58, 0.8, 1.0])
		grad.colors = PackedColorArray([Color(col, 0.9), Color(col, 0.85), Color(col, 0.3), Color(col, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var g := TextureRect.new()
		g.texture = gt
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size = Vector2(s, s) * 1.7
		_put(m, parent, g, pos - Vector2(s, s) * 0.35)
	var rim_col := col.darkened(0.7) if mood == "loss" else col
	var t := TextureRect.new()
	t.texture = tinted(piece, "MASK-" + piece.substr(4) + "-SEAT-RIM", rim_col)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size = Vector2(s, s)
	if mood == "loss":
		t.modulate = Color(0.78, 0.86, 1.0)
	_put(m, parent, t, pos)
	if f == "":
		return
	# note 11 (Daniele 11-16: "AIs should use the high-definition version, not the flat icon"): the AI's HD screen face
	# (UiKit.ai_screen_path, the VERSUS art) as a disc in the socket, blinking now and then; the flat 36B2 mark is gone.
	var mk := AiFace.new()
	mk.f = f
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.size = Vector2(s, s) * 0.8
	if mood == "loss":
		mk.modulate = Color(0.82, 0.84, 0.9)
	_put(m, parent, mk, pos + Vector2(s, s) * 0.1)


class AiFace extends Control:
	## The faction AI's HD face in a disc (Hud43.draw_ai_disc), blinking every few seconds.
	var f := "vex"
	var _t := randf() * 3.0
	var _blink := false

	func _process(dt: float) -> void:
		_t += dt
		var b := fmod(_t, 4.0) < 0.14
		if b != _blink:
			_blink = b
			queue_redraw()

	func _draw() -> void:
		Hud43.draw_ai_disc(self, f, size * 0.5, minf(size.x, size.y) * 0.5, Color.WHITE, _blink)


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


static func _settle(b: Button) -> void:
	## Cream is for compact keys that carry only their own lettering. A key that is big (rows, tiles, cards), or has children laid
	## over it (emblems, captions, numbers in light ink), takes the plum glass card instead; picked = the same card with the
	## SELECTED marks (bronze ring + seat lamp) the keys carry, never the old flat rim (note 1).
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var big := b.size.y > 190.0 or b.get_child_count() > 0
	var tab: bool = str(b.get_meta("mskin", "")) == "tab"
	if big:
		var picked: bool = tab and b.get_meta("mrim", false)
		var norm: StyleBox = lamp_plate() if picked else plate()
		b.add_theme_stylebox_override("normal", norm)
		b.add_theme_stylebox_override("hover", norm if picked else box(tex("SHELL-M-E"), Vector4(28, 28, 28, 30), Color(1.18, 1.12, 1.1), Vector2(14, 12)))
		b.add_theme_stylebox_override("pressed", norm if picked else box(tex("SHELL-M-E"), Vector4(28, 28, 28, 30), Color(0.78, 0.74, 0.74), Vector2(14, 12)))
		b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
		b.add_theme_stylebox_override("disabled", plate(0.6))
		for k in FONT_KEYS:
			if b.has_theme_color_override(k) and _lum(b.get_theme_color(k)) < 0.4:
				b.add_theme_color_override(k, UiKit.INK)
	elif str(b.get_meta("mskin", "")) != "key45":      # a 45B key measured its own lettering per face
		for k in FONT_KEYS:
			if b.has_theme_color_override(k) and _lum(b.get_theme_color(k)) > 0.6:
				b.add_theme_color_override(k, UiKit.INK if str(b.get_meta("mskin", "")) == "quit" else INK_DARK)
