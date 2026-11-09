class_name HudSkin
extends RefCounted
## Alpha 24 step 2 (the in-match HUD, Daniele 2026-11-02: "the switch covers matches too"; Hub Roadmap m05: "send on the left
## thumb, skills stacked on the right, compact sizes"): the HUD's look from the round-3 pack's B (HUD), E (skill icons) and F
## (board icons) sheets, in the current UiTheme mode (DARK / LIGHT, the menus' switch).
##   ink(col) / outline() / sub_ink()   text colours that read on the mode's badge / panel fill
##   frame(col, fill_a, px)            B7 (the own-node badge) baked small with its rim recoloured to `col` (seat colours: B7's
##                                     cyan rim, B8's red one are just two of them) and its fill see-through - a nine-patch
##                                     texture for BadgeLayer and the top-bar chips; HIDDEN = B10 as is
##   frame_box(col, ...)               the same as a SkinBox (top-bar chips, CATCH-UP tag)
##   sprite(id, px, tint)              any B sprite baked to `px` (rim recoloured when tint has a hue) - overlay atlases
##   b_box(id, scale, mod)             a B sprite as a SkinBox at its own slicing (B19 / B20 bars, B6 square)
##   skill_icon(id)                    the E icon of a skill id (ArmyPresets' SVG when the pack has none)
## Everything baked is cached per mode, colour and size; a mode switch mid-match is not supported (the HUD is built once).

const FILL_A_DARK := 0.45                          # a badge's fill over the board (the old box was 0.42 of near-black)
const FILL_A_LIGHT := 0.78
# skill id -> the E sheet's icon name, where they differ (Rewire is OVERDRIVE since bal-02321: the E15 icon)
const SKILL_ICON := {"evac": "emergency_evac", "fog": "fog_of_war", "rewire": "overdrive"}
# the board icons (F) a HUD readout uses
const BOARD_ICON := {"vat": "F1", "machinegoon": "F2", "laser": "F3", "forge": "F4", "monster_hub": "F5", "timer": "F17"}

const MODE := "dark"                               # neon pass: the match HUD is dark glass in both themes (it sits on the board)
const INK := Color("e8f6fa")
const MUTED := Color("a6bfca")
static var _img := {}                              # mode -> the B sheet as an Image (no mipmaps)
static var _baked := {}                            # key -> ImageTexture


static func light() -> bool:
	return false                                   # (neon pass: see MODE - the pause / results screens follow the theme)


static func fill_a() -> float:
	return FILL_A_LIGHT if light() else FILL_A_DARK


static func ink(col: Color) -> Color:
	## A seat / state colour as text on the mode's fill: as is on dark, deepened on light (a pale surface).
	if not light():
		return col
	var h := col
	h.v = minf(h.v, 0.62)
	h.s = maxf(h.s, 0.75)
	return h


static func neutral_ink() -> Color:
	return Color("3a4652") if light() else Color("d8e0e8")


static func sub_ink() -> Color:
	return Color("31414e") if light() else Color("c8e6ee")


static func outline() -> Color:
	return Color(1, 1, 1, 0.85) if light() else Color(0, 0, 0, 0.9)


static func text() -> Color:
	return INK


static func muted() -> Color:
	return MUTED


static func sheet() -> Image:
	var m := MODE
	if not _img.has(m):
		var t := UiTheme.atlas("B", m)
		var im: Image = t.get_image() if t != null else null
		if im != null:
			im = im.duplicate()
			if im.is_compressed():
				im.decompress()
			im.clear_mipmaps()
			im.convert(Image.FORMAT_RGBA8)
		_img[m] = im
	return _img[m]


static func _region(id: String) -> Image:
	var im := sheet()
	if im == null:
		return null
	var rc: Array = UiTheme.DATA.SPRITES[id]["rect"]
	return im.get_region(Rect2i(int(rc[0]), int(rc[1]), int(rc[2]), int(rc[3])))


static func recolor(im: Image, tint: Color, fill: float) -> void:
	## In place: the saturated pixels (the sprite's neon rim) take `tint`'s hue at their own brightness; the grey ones (the
	## fill, its shading) keep theirs, their alpha x `fill`. A tint with no hue (white) keeps the rim's own colour.
	var keep := tint.s < 0.05 and tint.v > 0.95
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var p := im.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			var mx := maxf(p.r, maxf(p.g, p.b))
			var mn := minf(p.r, minf(p.g, p.b))
			var m := smoothstep(0.12, 0.42, mx - mn)
			var c := p
			if not keep and m > 0.0:
				var k := clampf(mx / 0.86, 0.0, 1.15)
				c = p.lerp(Color(tint.r * k, tint.g * k, tint.b * k, p.a), m)
			c.a = p.a * lerpf(fill, 1.0, m)
			im.set_pixel(x, y, c)


static func sprite(id: String, px: Vector2i, tint := Color.WHITE, fill := 1.0) -> Texture2D:
	## A B sprite resized to px (whole), its rim recoloured to `tint`, its fill's alpha x fill; null without the sheet.
	var key := "%s|%s|%s|%s|%.2f" % [MODE, id, px, tint.to_html(), fill]
	if _baked.has(key):
		return _baked[key]
	var im := sprite_image(id, px, tint, fill)
	var t: Texture2D = ImageTexture.create_from_image(im) if im != null else null
	_baked[key] = t
	return t


static func sprite_image(id: String, px: Vector2i, tint := Color.WHITE, fill := 1.0) -> Image:
	var im := _region(id)
	if im == null:
		return null
	im.resize(maxi(px.x, 2), maxi(px.y, 2), Image.INTERPOLATE_LANCZOS)
	if not (tint == Color.WHITE and fill >= 1.0):
		recolor(im, tint, fill)
	return im


static func frame_px(ui_scale: float) -> int:
	## The baked badge frame's side (px): its rounded corner then reads ~11 px x ui_scale, the old box's.
	return int(round(64.0 * ui_scale))


static func frame_margin(ui_scale: float) -> int:
	return int(round(frame_px(ui_scale) * 0.3))


static func frame_glow(ui_scale: float) -> int:
	## The neon halo baked round a badge frame (px each side): BadgeLayer draws the frame that much bigger.
	return int(round(5.0 * ui_scale))


static func noir_image(id: String, k: float, rim := Color.WHITE) -> Image:
	## Neon Noir (art director revision 6): part `id`'s layers composed at scale k (source px -> px): its fill, then its white
	## rim tinted `rim`. The whole canvas, glow band included; null when the part is not imported.
	var s := HudNoir.part_data(id)
	var out: Image = null
	# ui-neon-apply: a badge's backlight (the delivery's W <id>_rim_glow halo) behind it, in its rim colour
	var glow_path := "res://assets/ui/hud_noir/%s_rim_glow.png" % id
	for layer in [["glow", rim], ["file", Color.WHITE], ["rim", rim]]:
		var t := HudNoir.texture(glow_path if layer[0] == "glow" and ResourceLoader.exists(glow_path) else str(s.get(layer[0], "")))
		if t == null:
			continue
		var im := t.get_image().duplicate() as Image
		if im.is_compressed():
			im.decompress()
		im.clear_mipmaps()
		im.convert(Image.FORMAT_RGBA8)
		im.resize(maxi(2, int(round(im.get_width() * k))), maxi(2, int(round(im.get_height() * k))), Image.INTERPOLATE_LANCZOS)
		var c: Color = layer[1]
		if c != Color.WHITE:
			for y in range(im.get_height()):
				for x in range(im.get_width()):
					var p := im.get_pixel(x, y)
					im.set_pixel(x, y, Color(p.r * c.r, p.g * c.g, p.b * c.b, p.a))
		if out == null:
			out = im
		else:
			out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
	return out


static func noir_badge_k(ui_scale: float) -> float:
	## The director's badge is drawn at the phone shot's 1/3 (source px -> px).
	return ui_scale / HudNoir.SPRITE_K


static func frame(col: Color, fill: float, ui_scale: float, hidden := false, mine := false) -> Texture2D:
	## A node badge's frame: B7 with its rim in `col` (own / enemy / neutral alike), or B10 (HIDDEN) as drawn - with a soft neon
	## halo in `col` round it (neon pass), frame_glow px each side. Neon Noir revision 6: the director's badge / badge_mine (your
	## own nodes: the full-strength rim) / badge_hidden, rim in `col`, its glow band baked in (BadgeLayer grows the box by it).
	if HudNoir.has("badge"):
		if col.is_equal_approx(HudNoir.NEUTRAL):        # ui-neon-apply: a neutral badge's tube is lit too (light steel neon, not dull grey)
			col = HudNoir.NEUTRAL.lightened(0.5)
		var nk := "noir|%s|%s|%s|%.3f" % [col.to_html(), hidden, mine, ui_scale]
		if not _baked.has(nk):
			var im := noir_image("badge_hidden" if hidden else ("badge_mine" if mine else "badge"), noir_badge_k(ui_scale), col)
			_baked[nk] = ImageTexture.create_from_image(im) if im != null else null
		return _baked[nk]
	var s := frame_px(ui_scale)
	var g := frame_glow(ui_scale)
	var key := "frame|%s|%.2f|%d|%s" % [col.to_html(), fill, s, hidden]
	if _baked.has(key):
		return _baked[key]
	var im := sprite_image("B10" if hidden else "B7", Vector2i(s, s), Color.WHITE if hidden else col, fill)
	if im == null:
		_baked[key] = null
		return null
	var out := Image.create(s + 2 * g, s + 2 * g, false, Image.FORMAT_RGBA8)
	# the halo: the rim's own alpha, blurred (down- then up-sampled), in the rim's colour
	var halo := Image.create(s + 2 * g, s + 2 * g, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var p := im.get_pixel(x, y)
			var mx := maxf(p.r, maxf(p.g, p.b))
			var mn := minf(p.r, minf(p.g, p.b))
			var m := smoothstep(0.12, 0.42, mx - mn) if not hidden else 0.0
			if m > 0.0:
				halo.set_pixel(x + g, y + g, Color(col, p.a * m))
	var small := maxi(int((s + 2 * g) / 5), 4)
	halo.resize(small, small, Image.INTERPOLATE_BILINEAR)
	halo.resize(s + 2 * g, s + 2 * g, Image.INTERPOLATE_CUBIC)
	for y in range(halo.get_height()):
		for x in range(halo.get_width()):
			var h := halo.get_pixel(x, y)
			halo.set_pixel(x, y, Color(col, clampf(h.a * 1.6, 0.0, 0.75)))
	out.blend_rect(halo, Rect2i(0, 0, halo.get_width(), halo.get_height()), Vector2i.ZERO)
	out.blend_rect(im, Rect2i(0, 0, s, s), Vector2i(g, g))
	var t := ImageTexture.create_from_image(out)
	_baked[key] = t
	return t


static func frame_box(col: Color, fill: float, ui_scale: float, content := 4.0) -> StyleBox:
	## The badge frame as a StyleBox (top-bar chips, tags) - a flat box when the pack is missing.
	var t := frame(col, fill, ui_scale)
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.05, 0.07, 0.09, fill)
		f.border_color = col
		f.set_border_width_all(2)
		f.set_corner_radius_all(int(9 * ui_scale))
		f.set_content_margin_all(content)
		return f
	var b := SkinBox.new()
	b.texture = t
	b.region = Rect2(Vector2.ZERO, t.get_size())
	var m := float(frame_margin(ui_scale) + frame_glow(ui_scale))
	b.slice = Vector4(m, m, m, m)
	b.scale = 1.0
	b.set_content_margin_all(content)
	return b


static func b_box(id: String, scale := UiTheme.SCALE, mod := Color.WHITE, content := 0.0) -> StyleBox:
	## A B sprite at its manifest slicing (fixed sprites draw whole, aspect kept).
	return UiTheme.box(id, scale, mod, content, MODE)


static func pill(scale: float, content_x: float, content_y: float, mod := Color.WHITE) -> StyleBox:
	## The B19 track pill (the status line's, the bars' track) with room for words.
	var b := UiTheme.box("B19", scale, mod, 0.0, MODE)
	b.axis = "x"
	b.content_margin_left = content_x
	b.content_margin_right = content_x
	b.content_margin_top = content_y
	b.content_margin_bottom = content_y
	return b


static func skill_icon(id: String) -> Texture2D:
	var t := UiTheme.icon(str(SKILL_ICON.get(id, id)))
	return t if t != null else ArmyPresets.icon(id)


static func board_icon(what: String) -> Texture2D:
	return UiTheme.icon(str(BOARD_ICON.get(what, what)))


static func draw_sprite(ci: CanvasItem, id: String, r: Rect2, mod := Color.WHITE) -> void:
	## One B sprite from the mode's atlas, whole, into r (aspect kept, centred).
	var s: Dictionary = UiTheme.DATA.SPRITES[id]
	var rc: Array = s["rect"]
	var src := Rect2(rc[0], rc[1], rc[2], rc[3])
	var k := minf(r.size.x / src.size.x, r.size.y / src.size.y)
	var d := src.size * k
	ci.draw_texture_rect_region(UiTheme.atlas("B", MODE), Rect2(r.position + (r.size - d) / 2.0, d), src, mod)
