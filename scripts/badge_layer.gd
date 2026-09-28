class_name BadgeLayer
extends Control
## HUD pass (the stretch, Alpha 21 OPT-RENDER: the node badges were ~70 of the HUD's ~165 draw calls on M-39): every
## node badge drawn by one canvas item per KIND of thing instead of five nodes per badge. Hud still lays each badge
## out on its own Panel / Label / TextureRect / ProgressBar (_badges / _place_badge / _fit_text, unchanged), but
## those sit under a hidden holder and never draw; this layer reads them and draws, in order: every box (one
## nine-patch texture: the fills, then the rims), every build bar, the emblems (one child per seat: its tint
## material), then every count and sub line (the outlines, then the letters) - so the 2D renderer merges each
## pass into a batch or two, where a panel / text / emblem switch at every badge broke it every time.

const FILL := Color(0.063, 0.078, 0.098, 0.42)     # = Hud.badge_style's box
const RADIUS := 9                                  # its corner (px, not scaled - as the StyleBox had it)
const TINT := preload("res://shaders/emblem_tint.gdshader")   # = Hud.EMBLEM_TINT (Hud itself needs the Net autoload)

var hud                                            # Hud
var _fill_tex: Texture2D                           # a white rounded box, and its 1 px rim, for the nine-patches
var _rim_tex: Texture2D
var _groups := {}                                  # seat -> EmblemGroup
var _text: TextPass


class EmblemGroup:
	extends Control
	## One seat's emblems, under that seat's tint material (Hud.tint_emblem's shader): one batch a seat.
	var layer: BadgeLayer
	var seat := ""

	func _draw() -> void:
		for id in layer.hud.badges:
			var b: Dictionary = layer.hud.badges[id]
			var e: TextureRect = b["emblem"]
			if not (b["panel"] as Control).visible or not e.visible or e.texture == null or str(e.get_meta("seat", "")) != seat:
				continue
			var r := Rect2((b["panel"] as Control).position + e.position, e.size)
			var ts := e.texture.get_size()
			var k := minf(r.size.x / maxf(ts.x, 1.0), r.size.y / maxf(ts.y, 1.0))   # STRETCH_KEEP_ASPECT_CENTERED
			var d := ts * k
			draw_texture_rect(e.texture, Rect2(r.position + (r.size - d) * 0.5, d), false)


class TextPass:
	extends Control
	## Every count and sub line: all outlines first, then all letters (each pass one font texture per size).
	var layer: BadgeLayer

	func _draw() -> void:
		var labels := []
		for id in layer.hud.badges:
			var b: Dictionary = layer.hud.badges[id]
			var p: Control = b["panel"]
			if not p.visible:
				continue
			for k in ["label", "sub"]:
				var l: Label = b[k]
				if l.visible and l.text != "":
					labels.append([l, p.position + l.position])
		for outline in [true, false]:
			for e in labels:
				var l: Label = e[0]
				var font: Font = l.get_theme_font("font")
				var px := l.get_theme_font_size("font_size")
				var text := l.text
				var room := l.size.x
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
				while l.clip_text and w > room and text.length() > 1:   # the Label's clip: never past its box
					text = text.substr(0, text.length() - 1)
					w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
				var at: Vector2 = e[1]
				var pos := Vector2(at.x + (room - w) * 0.5, at.y + (l.size.y - font.get_height(px)) * 0.5 + font.get_ascent(px)).round()
				if outline:
					var os := l.get_theme_constant("outline_size")
					if os > 0:
						draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, os, l.get_theme_color("font_outline_color"))
				else:
					draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, l.get_theme_color("font_color"))


func setup(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_tex = _box_texture(false)
	_rim_tex = _box_texture(true)
	for seat in hud.sim.factions.keys():              # every seat that can own a node, in a fixed order
		var g := EmblemGroup.new()
		g.layer = self
		g.seat = str(seat)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # as the emblem TextureRects had it
		var m := ShaderMaterial.new()
		m.shader = TINT
		m.set_shader_parameter("tint", Rules.seat_color(str(seat)))
		g.material = m
		add_child(g)
		_groups[seat] = g
	_text = TextPass.new()                             # last: the words over the emblems and boxes
	_text.layer = self
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)


func refresh() -> void:
	## Hud.sync, after _badges moved and re-dressed the badges: draw them again.
	queue_redraw()
	for g in _groups.values():
		(g as CanvasItem).queue_redraw()
	_text.queue_redraw()


func _draw() -> void:
	var boxes := []
	for id in hud.badges:
		var b: Dictionary = hud.badges[id]
		var p: Control = b["panel"]
		if p.visible:
			boxes.append(b)
	var m := float(RADIUS + 1)
	for rim in [false, true]:                          # the see-through fills, then the owner-coloured rims
		for b in boxes:
			var p: Control = b["panel"]
			var col := FILL
			if rim:
				var owner := str(b["owner"])
				col = Color(Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL, 0.8)
			RenderingServer.canvas_item_add_nine_patch(get_canvas_item(), Rect2(p.position, p.size), Rect2(Vector2.ZERO, _fill_tex.get_size()),
					(_rim_tex if rim else _fill_tex).get_rid(), Vector2(m, m), Vector2(m, m),
					RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, col)
	for b in boxes:                                    # the build bars along the bottom edges
		var bar: ProgressBar = b["build"]
		if not bar.visible:
			continue
		var r := Rect2((b["panel"] as Control).position + bar.position, bar.size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(bar.value / 100.0, 0.0, 1.0), r.size.y)), Rules.state_color("build"))


static func _box_texture(rim: bool) -> Texture2D:
	## A white rounded box (RADIUS corner) - filled, or only its 1 px rim - anti-aliased, for a nine-patch.
	var n := RADIUS * 2 + 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n / 2.0
	for y in range(n):
		for x in range(n):
			# signed distance from the pixel centre to the rounded box's edge (negative inside)
			var q := Vector2(absf(x + 0.5 - half), absf(y + 0.5 - half)) - Vector2(half - RADIUS, half - RADIUS)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - RADIUS
			var a := clampf(0.5 - d, 0.0, 1.0)                           # inside the box
			if rim:
				a = minf(a, clampf(d + 1.4, 0.0, 1.0))                     # ... and within ~1 px of its edge (the StyleBox's AA rim)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
