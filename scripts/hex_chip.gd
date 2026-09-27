class_name HexChip
extends Button
## A colour-picker chip (0.19.0, Daniele: "the actual hexagon should be in full color of the actual
## color, no words, border same color"): a hexagon filled solid in its colour, border the same colour,
## no text. FACTION has no single colour: its hexagon splits into wedges, one per faction. Because the
## border matches the fill, the picked chip needs another cue: a white outer ring plus a slight scale-up
## (Daniele: "a white (or light) outer ring or glow plus a slight scale-up on the picked chip"). Every
## chip keeps its colour name as `tooltip_text` (also read out via Control's accessible name) so a
## colour-blind player can still tell them apart.

var fill := Color.WHITE                # a solid hue chip
var wedges: Array = []                 # non-empty: a FACTION-style split hexagon instead (one Color per wedge)
var emblem_faction := ""               # 0.19.2 spec H2: FACTION gets a recognisable face - the player's
                                        # faction emblem in white, centred over the wedges
static var _white_emblem_cache := {}
var picked := false:
	set(v):
		picked = v
		scale = Vector2.ONE * (1.12 if v else 1.0)
		queue_redraw()


func _ready() -> void:
	flat = true
	text = ""
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	resized.connect(func(): pivot_offset = size / 2.0)


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) / 2.0 - 3.0
	var pts := PackedVector2Array()
	for k in range(6):
		var a := TAU * k / 6.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var dim := disabled
	if wedges.is_empty():
		draw_colored_polygon(pts, fill if not dim else Color(fill, 0.28))
	else:
		for k in range(wedges.size()):
			var a0 := TAU * k / wedges.size() - PI / 2.0
			var a1 := TAU * (k + 1) / wedges.size() - PI / 2.0
			var tri := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r])
			draw_colored_polygon(tri, wedges[k] if not dim else Color(wedges[k], 0.28))
	var edge := pts.duplicate()
	edge.append(pts[0])
	var border: Color = fill if wedges.is_empty() else Color.WHITE
	draw_polyline(edge, border if not dim else Color(0.4, 0.44, 0.47), 3.0, true)
	if emblem_faction != "":
		var tex := _white_emblem(emblem_faction)
		if tex:
			var isz := Vector2.ONE * r * 0.9
			draw_texture_rect(tex, Rect2(c - isz / 2.0, isz), false, Color(1, 1, 1, 1.0 if not dim else 0.35))
	if picked:
		var ring := PackedVector2Array()
		for k in range(6):
			var a := TAU * k / 6.0 - PI / 2.0
			ring.append(c + Vector2(cos(a), sin(a)) * (r + 6.0))
		ring.append(ring[0])
		draw_polyline(ring, Color(1, 1, 1, 0.95), 3.5, true)


static func _white_emblem(fac: String) -> Texture2D:
	## A once-baked white silhouette of the faction emblem (same luminance-keeps-alpha/hue-replaced
	## recipe as shaders/emblem_tint.gdshader, done on the CPU so a plain _draw() can use it).
	if _white_emblem_cache.has(fac):
		return _white_emblem_cache[fac]
	var src: Texture2D = Hud.emblem_texture(fac)
	var out: Texture2D = null
	var img: Image = src.get_image() if src else null
	if img and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			var v: int = maxi(data[i], maxi(data[i + 1], data[i + 2]))
			data[i] = 255
			data[i + 1] = 255
			data[i + 2] = 255
			data[i + 3] = int(float(data[i + 3]) * float(v) / 255.0)
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
		out = ImageTexture.create_from_image(img)
	_white_emblem_cache[fac] = out
	return out
