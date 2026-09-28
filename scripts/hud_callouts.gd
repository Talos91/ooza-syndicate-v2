class_name HudCallouts
extends Control
## HUD pass (2026-09-28, Daniele's "option A": "no notification box at all" - the top-left stack "feels weird"):
## every message is a short callout AT the place it is about, in Fx.floater's look (Rajdhani in the message's
## colour, a thick dark outline, no box) with a small icon - the seat's emblem in its colour, or a warn / good /
## info mark. A place is a node or a deck on the map (a world point), the seat chip in the top bar, the skill slot
## that was tapped, the centre under the top bar (a line with no place of its own, the match-start banner, the
## online waiting text). One callout per place: the same place again refreshes it instead of stacking. A world
## place off screen gets an arrow on the screen edge pointing to it. Never over the SEND panel, the dock, the top
## bar or the inspector (Hud.callout_blocked), always inside the device's safe area (Hud.callout_area). One canvas
## item draws the text, icons and arrows of every callout (the emblems are small tinted TextureRects).

const FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD := preload("res://assets/fonts/RussoOne-Regular.ttf")
const TINT := preload("res://shaders/emblem_tint.gdshader")

var items: Array = []          # see add(): one Dictionary per place, oldest first
var ui_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func add(place: String, lines: Array, col: Color, opts := {}) -> Dictionary:
	## lines: [[text, font px, colour, head font?]...] (the first line is the one the icon sits by). opts: world
	## (Vector3: follows that map point), anchor (Callable -> Vector2: a screen point), side ("above" the point,
	## "below" it or "center" on it), seat (the emblem icon), glyph ("warn" | "good" | "info" | "" none), life (s;
	## INF = until removed), arrow (a world place off screen points there from the edge), hold (Callable -> bool:
	## the clock stands still while it is true - the start banner under the VERSUS card), rise (canvas units).
	## Returns the item (callers may keep a count in it).
	var it := find(place)
	var fresh := it.is_empty()
	if fresh:
		it = {"place": place, "t": 0.0, "emblem": null}
		items.append(it)
	else:
		it["t"] = minf(float(it["t"]), Rules.HUD_CALLOUT_POP)   # a refresh: no second pop, the full life again
	it["lines"] = lines
	it["col"] = col
	it["world"] = opts.get("world", null)
	it["anchor"] = opts.get("anchor", Callable())
	it["side"] = str(opts.get("side", "above"))
	it["glyph"] = str(opts.get("glyph", ""))
	it["life"] = float(opts.get("life", Rules.HUD_CALLOUT_LIFE))
	it["arrow"] = bool(opts.get("arrow", true))
	it["hold"] = opts.get("hold", Callable())
	it["rise"] = float(opts.get("rise", Rules.HUD_CALLOUT_RISE)) * ui_scale
	var seat := str(opts.get("seat", ""))
	var tex: Texture2D = opts.get("emblem_tex", null)
	if it["emblem"] != null and (seat == "" or tex == null):
		(it["emblem"] as Node).queue_free()
		it["emblem"] = null
	if seat != "" and tex != null:
		var r: TextureRect = it["emblem"]
		if r == null:
			r = TextureRect.new()
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(r)
			it["emblem"] = r
		r.texture = tex
		var m := ShaderMaterial.new()                  # Hud.tint_emblem's look (without loading Hud: it needs Net)
		m.shader = TINT
		m.set_shader_parameter("tint", Rules.seat_color(seat))
		r.material = m
	it["seat"] = seat
	queue_redraw()
	return it


func find(place: String) -> Dictionary:
	for it in items:
		if it["place"] == place:
			return it
	return {}


func remove(place: String) -> void:
	var it := find(place)
	if not it.is_empty():
		_drop(it)


func texts() -> Array:
	## Every line on screen now (tests, probes).
	var out := []
	for it in items:
		out.append(" ".join((it["lines"] as Array).map(func(l): return str(l[0]))))
	return out


func rects() -> Array:
	## The screen boxes drawn this frame (the coach card keeps clear of them).
	var out := []
	for it in items:
		if it.has("box"):
			out.append(it["box"])
	return out


func _drop(it: Dictionary) -> void:
	if it["emblem"] != null:
		(it["emblem"] as Node).queue_free()
	items.erase(it)
	queue_redraw()


# ------------------------------------------------------------------ per frame
func sync(dt: float, cam: Camera3D, area: Rect2, blocked: Array) -> void:
	## Ages every callout and places it for this frame: at its world point (or on the screen edge with an arrow),
	## or by its screen anchor - then slid out of every HUD panel and every callout placed before it, inside `area`.
	var placed := []                                  # the callouts already placed this frame
	# the ones pinned to a HUD spot (a slot's refusal, a chip's line, the banner) first: a map callout gives way
	# to them, never the other way round
	var order := items.filter(func(i): return not i["world"] is Vector3) + items.filter(func(i): return i["world"] is Vector3)
	for it in order:
		var hold: Callable = it["hold"]
		if not (hold.is_valid() and bool(hold.call())):
			it["t"] = float(it["t"]) + dt
		var t: float = it["t"]
		var life: float = it["life"]
		if t >= life:
			_drop(it)
			continue
		var sz := _size(it)
		var pop := minf(t / Rules.HUD_CALLOUT_POP, 1.0)
		var rise := float(it["rise"]) * (clampf(t / minf(life, Rules.HUD_CALLOUT_LIFE), 0.0, 1.0) if life < INF else 0.0)
		it["alpha"] = pop * (clampf((life - t) / Rules.HUD_CALLOUT_FADE, 0.0, 1.0) if life < INF else 1.0)
		it["scale"] = lerpf(0.84, 1.0, pop)
		it["off"] = false
		var c := Vector2.ZERO
		if it["world"] is Vector3 and cam != null:
			var w: Vector3 = it["world"]
			var p := cam.unproject_position(w)
			var behind := cam.is_position_behind(w)
			var inner := area.grow(-6.0 * ui_scale)
			if behind or not inner.has_point(p):
				if not bool(it["arrow"]):              # an off-screen place without an arrow: nothing to point at
					it.erase("box")
					continue
				var dir := (p - inner.get_center()).normalized()
				if behind:
					dir = -dir
				if dir == Vector2.ZERO:
					dir = Vector2.UP
				var al := Rules.HUD_CALLOUT_ARROW * ui_scale
				var edge := _edge(inner.get_center(), dir, inner.grow(-al - 4.0 * ui_scale))
				c = edge - dir * 4.0 * ui_scale - Vector2(dir.x * sz.x, dir.y * sz.y) * 0.5
				c = _place(it, c, sz, blocked, placed, area)
				var exit := _box_exit(sz, dir)                    # the arrow leaves the box on the place's side
				var tip := c + dir * (exit + 4.0 * ui_scale + al)
				if _hits(Rect2(tip - Vector2.ONE * al * 0.5, Vector2.ONE * al), blocked):
					# the way out is under a HUD panel (a place beyond the dock): the arrow at the box's end instead
					var sx := 1.0 if dir.x >= 0.0 else -1.0
					tip = c + Vector2(sx * (sz.x * 0.5 + 4.0 * ui_scale + al), 0) + dir * al * 0.4
				tip = Vector2(clampf(tip.x, area.position.x + 2.0, area.end.x - 2.0), clampf(tip.y, area.position.y + 2.0, area.end.y - 2.0))
				it["off"] = true
				it["arrow_dir"] = dir
				it["arrow_tip"] = tip
			else:
				c = _place(it, p - Vector2(0, sz.y * 0.5 + rise), sz, blocked, placed, area)
		else:
			var anchor: Callable = it["anchor"]
			var a := anchor.call() as Vector2 if anchor.is_valid() else area.get_center()
			match str(it["side"]):
				"below":
					c = a + Vector2(0, sz.y * 0.5 - rise * 0.3)
				"center":
					c = a
				_:
					c = a - Vector2(0, sz.y * 0.5 + rise)
			c = _place(it, c, sz, blocked, placed, area)
		var box := Rect2(c - sz * 0.5, sz)
		it["box"] = box
		placed.append(box)
		var l0: Array = it["lines"][0]
		var tw0 := _font(l0).get_string_size(str(l0[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l0[1])).x
		var iw := (_icon_r(it) * 2.0 + 7.0 * ui_scale) if _has_icon(it) else 0.0
		it["x0"] = box.position.x + (box.size.x - tw0 - iw) * 0.5 + iw       # line 0's text, right of its icon
		it["icon_c"] = Vector2(float(it["x0"]) - iw + _icon_r(it), box.position.y + _line_h(l0) * 0.5)
		var em: TextureRect = it["emblem"]
		if em != null:                                    # not under _draw's pop transform: scaled here to match
			var r := _icon_r(it)
			var k: float = it["scale"]
			em.size = Vector2.ONE * r * 2.0 * k
			em.position = c + ((it["icon_c"] as Vector2) - c) * k - Vector2(r, r) * k
			em.modulate = Color(1, 1, 1, float(it["alpha"]))
	queue_redraw()


func _size(it: Dictionary) -> Vector2:
	var w := 0.0
	var h := 0.0
	var lines: Array = it["lines"]
	for i in range(lines.size()):
		var l: Array = lines[i]
		var lw := _font(l).get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[1])).x
		if i == 0 and _has_icon(it):
			lw += _icon_r(it) * 2.0 + 7.0 * ui_scale
		w = maxf(w, lw)
		h += _line_h(l)
	return Vector2(w + 8.0 * ui_scale, h)


func _has_icon(it: Dictionary) -> bool:
	return it["emblem"] != null or str(it["glyph"]) != ""


func _icon_r(it: Dictionary) -> float:
	return float((it["lines"] as Array)[0][1]) * 0.5


func _font(l: Array) -> Font:
	return HEAD if l.size() > 3 and bool(l[3]) else FONT


func _line_h(l: Array) -> float:
	return _font(l).get_height(int(l[1]))


static func _edge(c: Vector2, dir: Vector2, r: Rect2) -> Vector2:
	## Where a ray from `c` along `dir` leaves the rect `r`.
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, ((r.end.x if dir.x > 0.0 else r.position.x) - c.x) / dir.x)
	if absf(dir.y) > 0.0001:
		t = minf(t, ((r.end.y if dir.y > 0.0 else r.position.y) - c.y) / dir.y)
	return c + dir * maxf(t, 0.0)


static func _box_exit(sz: Vector2, dir: Vector2) -> float:
	## The distance from a box's centre to its rim along `dir`.
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, sz.x * 0.5 / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, sz.y * 0.5 / absf(dir.y))
	return t


func _place(it: Dictionary, want: Vector2, sz: Vector2, hud: Array, placed: Array, area: Rect2) -> Vector2:
	## The nearest free spot to `want`: the same nudge as last frame first (no jitter while it rises), then a
	## step up or down (a line's height at a time) or sideways - the first spot on screen that touches no HUD
	## panel and no callout placed before it; none free: _clear's slide.
	var gap := 4.0 * ui_scale
	var tries := [it.get("nudge", Vector2.ZERO), Vector2.ZERO]
	for k in range(1, 5):                             # (never far: a callout stays by its place)
		tries.append(Vector2(0, -k * (sz.y + gap)))
		tries.append(Vector2(0, k * (sz.y + gap)))
		if k <= 2:
			tries.append(Vector2(-k * (sz.x * 0.5 + gap), 0))
			tries.append(Vector2(k * (sz.x * 0.5 + gap), 0))
	var inner := area.grow(0.5)
	for d in tries:
		var box := Rect2(want + (d as Vector2) - sz * 0.5, sz)
		if inner.encloses(box) and not _hits(box, hud) and not _hits(box, placed):
			it["nudge"] = d
			return want + d
	it["nudge"] = Vector2.ZERO
	return _clear(want, sz, hud, placed, area)


static func _hits(box: Rect2, rects: Array) -> bool:
	for r in rects:
		if box.intersects(r):
			return true
	return false


static func _clear(c: Vector2, sz: Vector2, hud: Array, placed: Array, area: Rect2) -> Vector2:
	## Hud._clear_of's rule, kept inside `area`: slide the box the shortest way out of each rect it still overlaps -
	## of the four ways out, the shortest that stays on screen (a box at the top of the screen under the top bar
	## goes down, never up and back) - then clamp it into the area; three times over the HUD panels and the callouts
	## placed before it (a slide can land on the next rect), then once more over the HUD panels alone: where they
	## can't all be cleared, two callouts may touch, a callout and a panel never.
	var inner := area.grow(0.5)
	var both := hud + placed
	for pass_n in range(4):
		for b in (both if pass_n < 3 else hud):
			var box := Rect2(c - sz * 0.5, sz)
			var r: Rect2 = b
			if not box.intersects(r):
				continue
			var best := Vector2.INF
			var any := Vector2.INF
			for m in [Vector2(0, r.position.y - box.end.y), Vector2(0, r.end.y - box.position.y),
					Vector2(r.position.x - box.end.x, 0), Vector2(r.end.x - box.position.x, 0)]:
				if m.length() < any.length():
					any = m
				if inner.encloses(Rect2(box.position + m, sz)) and m.length() < best.length():
					best = m
			c += best if best != Vector2.INF else any
		c = Vector2(clampf(c.x, area.position.x + sz.x * 0.5, maxf(area.position.x + sz.x * 0.5, area.end.x - sz.x * 0.5)),
				clampf(c.y, area.position.y + sz.y * 0.5, maxf(area.position.y + sz.y * 0.5, area.end.y - sz.y * 0.5)))
	return c


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	for it in items:
		if not it.has("box"):
			continue
		var a: float = it.get("alpha", 0.0)
		if a <= 0.0:
			continue
		var box: Rect2 = it["box"]
		var k: float = it.get("scale", 1.0)
		var pivot := box.get_center()
		draw_set_transform(pivot * (1.0 - k), 0.0, Vector2(k, k))   # the pop, round the box's centre
		var col: Color = it["col"]
		var lines: Array = it["lines"]
		var y := box.position.y
		for i in range(lines.size()):
			var l: Array = lines[i]
			var f := _font(l)
			var px := int(l[1])
			var text := str(l[0])
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var x := box.position.x + (box.size.x - tw) * 0.5
			if i == 0:
				x = float(it["x0"])
				if it["emblem"] == null and str(it["glyph"]) != "":
					_glyph(str(it["glyph"]), it["icon_c"], _icon_r(it), col, a)
			var base := y + f.get_ascent(px)
			var lc: Color = l[2]
			draw_string_outline(f, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
					maxi(3, int(px * 0.24)), Color(0.02, 0.02, 0.05, 0.92 * a))
			draw_string(f, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(lc, lc.a * a))
			y += _line_h(l)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if bool(it.get("off", false)):
			_arrow(it["arrow_tip"], it["arrow_dir"], col, a)


func _glyph(kind: String, c: Vector2, r: float, col: Color, a: float) -> void:
	## The small mark beside a line with no seat: a warning triangle, a good-news tick, an info dot.
	var dark := Color(0.02, 0.03, 0.05, 0.92 * a)
	var fill := Color(col, a)
	match kind:
		"warn":
			var tri := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.75), c + Vector2(-r * 0.95, r * 0.75)])
			draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(0, -2), tri[1] + Vector2(2, 1.5), tri[2] + Vector2(-2, 1.5)]), dark)
			draw_colored_polygon(tri, fill)
			draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.2), dark, maxf(2.0, r * 0.2))
			draw_circle(c + Vector2(0, r * 0.47), maxf(1.2, r * 0.11), dark)
		"good":
			draw_circle(c, r + 1.5, dark)
			draw_circle(c, r, fill)
			draw_polyline(PackedVector2Array([c + Vector2(-0.5, 0.0) * r, c + Vector2(-0.12, 0.38) * r, c + Vector2(0.52, -0.35) * r]),
					dark, maxf(2.0, r * 0.22), true)
		"info", "build":
			draw_circle(c, r + 1.5, dark)
			draw_circle(c, r, fill)
			draw_line(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.52), dark, maxf(2.0, r * 0.2))
			draw_circle(c + Vector2(0, -r * 0.45), maxf(1.2, r * 0.12), dark)


func _arrow(tip: Vector2, dir: Vector2, col: Color, a: float) -> void:
	## The off-screen pointer: a chevron at the screen edge aimed at the place.
	var l := Rules.HUD_CALLOUT_ARROW * ui_scale
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, tip - dir * l + side * l * 0.62, tip - dir * l * 0.62, tip - dir * l - side * l * 0.62])
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + (p - (tip - dir * l * 0.55)).normalized() * 2.5 * ui_scale)
	draw_colored_polygon(out, Color(0.02, 0.02, 0.05, 0.85 * a))
	draw_colored_polygon(pts, Color(col.lerp(Color.WHITE, 0.15), a))
