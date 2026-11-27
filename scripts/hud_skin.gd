class_name HudSkin
extends RefCounted
## Alpha 24 step 2 (the in-match HUD, Daniele 2026-11-02: "the switch covers matches too"; Hub Roadmap m05: "send on the left
## thumb, skills stacked on the right, compact sizes"): the HUD's look from the round-3 pack's B (HUD), E (skill icons) and F
## (board icons) sheets, in the current UiTheme mode (DARK / LIGHT, the menus' switch).
##   outline()                         the text outline colour that reads on the mode's panel fill
##   sprite(id, px, tint)              any B sprite baked to `px` (rim recoloured when tint has a hue) - overlay atlases
##   b_box(id, scale, mod)             a B sprite as a SkinBox at its own slicing (B19 / B20 bars, B6 square)
##   skill_icon(id)                    the E icon of a skill id (ArmyPresets' SVG when the pack has none)
## Everything baked is cached per mode, colour and size; a mode switch mid-match is not supported (the HUD is built once).

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
