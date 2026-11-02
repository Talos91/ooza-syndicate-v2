class_name BadgeLayer
extends Control
## HUD pass (the stretch, Alpha 21 OPT-RENDER: the node badges were ~70 of the HUD's ~165 draw calls on M-39): every
## node badge drawn by one canvas item per KIND of thing instead of five nodes per badge. Hud still lays each badge
## out on its own Panel / Label / TextureRect / ProgressBar (_badges / _place_badge / _fit_text, unchanged), but
## those sit under a hidden holder and never draw; this layer reads them and draws, in order: every frame (a nine-patch
## per owner, sorted so each owner's frames batch), every build bar, the emblems (one child per seat: its tint
## material), then every count and sub line (the outlines, then the letters) - so the 2D renderer merges each
## pass into a batch or two, where a panel / text / emblem switch at every badge broke it every time.
## Alpha 24 step 2: the frames are the round-3 pack's node badges (HudSkin.frame: B7 with the owner's colour on its rim -
## own, enemy and neutral alike -, B10 where a rival's count is hidden), the build bar its progress track / fill (B19 /
## B20), in the current theme.

const TINT := preload("res://shaders/emblem_tint.gdshader")   # = Hud.EMBLEM_TINT (Hud itself needs the Net autoload)

var hud                                            # Hud
var _frames := {}                                  # owner key -> the baked frame texture
var _bar_track: Texture2D                          # B19 / B20 baked to the build bar's height
var _bar_fill: Texture2D
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
	var bh := maxi(int(round(4.0 * hud.ui_scale)), 3)
	_bar_track = HudSkin.sprite("B19", Vector2i(bh * 6, bh))
	_bar_fill = HudSkin.sprite("B20", Vector2i(bh * 6, bh))
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
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	queue_redraw()
	for g in _groups.values():
		(g as CanvasItem).queue_redraw()
	_text.queue_redraw()
	PerfProfile.lap("badges_refresh", _pt)


func frame_tex(owner: String, hidden: bool) -> Texture2D:
	## The frame of a badge owned by `owner` ("" neutral); HIDDEN (a rival's count not shown) is B10.
	var key := "?" if hidden else owner
	if not _frames.has(key):
		var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
		_frames[key] = HudSkin.frame(col, HudSkin.fill_a(), hud.ui_scale, hidden)
	return _frames[key]


func _draw() -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	var by := {}                                       # frame texture -> its badges (one batch each)
	var order := []
	for id in hud.badges:
		var b: Dictionary = hud.badges[id]
		var p: Control = b["panel"]
		if not p.visible:
			continue
		var t := frame_tex(str(b["owner"]), not (b["label"] as Label).visible and (b["emblem"] as TextureRect).visible)
		if t == null:
			continue
		if not by.has(t):
			by[t] = []
			order.append(t)
		by[t].append(p)
	var m := float(HudSkin.frame_margin(hud.ui_scale))
	for t in order:
		var tx: Texture2D = t
		for p in by[t]:
			RenderingServer.canvas_item_add_nine_patch(get_canvas_item(), Rect2(p.position, p.size), Rect2(Vector2.ZERO, tx.get_size()),
					tx.get_rid(), Vector2(m, m), Vector2(m, m), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true)
	for id in hud.badges:                              # the build bars along the bottom edges: B19 track, B20 fill
		var b: Dictionary = hud.badges[id]
		var bar: ProgressBar = b["build"]
		if not (b["panel"] as Control).visible or not bar.visible:
			continue
		var r := Rect2((b["panel"] as Control).position + bar.position, bar.size)
		_bar(r, _bar_track, Color.WHITE)
		var w := r.size.x * clampf(bar.value / 100.0, 0.0, 1.0)
		if w >= 1.0:
			_bar(Rect2(r.position, Vector2(maxf(w, r.size.y), r.size.y)), _bar_fill, Rules.state_color("build"))
	PerfProfile.lap("badges_draw", _pt)


func _bar(r: Rect2, t: Texture2D, mod: Color) -> void:
	## A pill bar (B19 / B20 baked to its height): only the middle stretches, the round ends keep their shape.
	if t == null:
		draw_rect(r, mod if mod != Color.WHITE else Color(0, 0, 0, 0.55))
		return
	var e := t.get_size().y * 0.5
	RenderingServer.canvas_item_add_nine_patch(get_canvas_item(), r, Rect2(Vector2.ZERO, t.get_size()), t.get_rid(),
			Vector2(e, 0), Vector2(e, 0), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, mod)
