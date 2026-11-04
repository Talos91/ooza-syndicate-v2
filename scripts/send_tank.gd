class_name SendTank
extends Control
## ui-node (Daniele 2026-11-04): "instead of having a container with the 4 send sizes, remove the internal containers and have the
## left side bar be a single container which fills based on % selected, and the levels are signed by an indicator like in a tank
## that tells how full it is, and the goo moves on it" - and no SEND / DRAG A VAT words ("do we need send and drag vat? i feel we
## don't"). One tall tank of lit goo in your faction accent, filled to the picked share; gauge ticks at 25 / 50 / 75 / 100 % on
## its side (the picked one lit); the share and, with one of your vats selected or dragged, the units it sends ride on the goo's
## surface. Tap the tank at a level or slide a thumb up and down it: it snaps to the nearest of the four shares (Rules: 25 / 50 /
## 75 / 100 %); each level's band is a quarter of the tank (~ 60 pt on a phone). The goo eases to the new level and sloshes.
## DROP-IN: the frame is HudNoir.box("send_tank") (placeholder: the SEND housing look, drips under it); the liquid is code-drawn.

const LEVELS := [0.25, 0.5, 0.75, 1.0]
const EASE := 6.0

var hud                                         # Hud
var main                                        # main.gd
var ui_scale := 1.0
var shown := 0.5                                # the goo's drawn level (eases to the pick)
var _slosh := 0.0
var _t := 0.0
var _frame: StyleBox
var _font: Font


func setup(h, m, s: float, font: Font) -> void:
	hud = h
	main = m
	ui_scale = s
	_font = font
	shown = float(main.fraction)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame = HudNoir.box("send_tank" if HudNoir.has("send_tank") else "send_housing", Color(0, 0, 0, 0), Vector4.ZERO)


func body_rect() -> Rect2:
	## The tank's inside (the goo's room): the frame's rect minus its rim and the drips under it.
	var drip := HudNoir.drip_px("send_tank" if HudNoir.has("send_tank") else "send_housing")
	var inset := 7.0 * ui_scale
	return Rect2(Vector2(inset, inset), Vector2(size.x - 2.0 * inset, size.y - drip - 2.0 * inset))


func level_y(level: float) -> float:
	var b := body_rect()
	return b.end.y - b.size.y * level


func level_rect(level: float) -> Rect2:
	## The tap band of one share (global): a quarter of the tank round its tick - the tutorial's spotlight (Hud.send_button_rect).
	var b := body_rect()
	var i := LEVELS.find(level)
	if i < 0:
		return Rect2()
	var q := b.size.y / 4.0
	return Rect2(global_position + Vector2(b.position.x, b.end.y - q * float(i + 1)), Vector2(b.size.x, q))


func _pick_at(y: float) -> void:
	var b := body_rect()
	var v := clampf((b.end.y - y) / b.size.y, 0.0, 1.0)
	var best: float = LEVELS[0]
	for l in LEVELS:                              # the band a quarter tall under each tick: 0-25 % -> 25, 25-50 -> 50 ...
		if v <= float(l) + 0.0001:
			best = l
			break
		best = l
	if not is_equal_approx(best, float(main.fraction)):
		main.fraction = best
		_slosh = 1.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick_at((event as InputEventMouseButton).position.y)
		accept_event()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_pick_at((event as InputEventMouseMotion).position.y)
		accept_event()
	elif event is InputEventScreenDrag:
		_pick_at((event as InputEventScreenDrag).position.y)
		accept_event()


func _process(dt: float) -> void:
	_t += dt
	var want := float(main.fraction)
	if absf(want - shown) > 0.03 and _slosh <= 0.0:
		_slosh = 1.0
	shown = lerpf(shown, want, 1.0 - exp(-EASE * dt))
	_slosh = maxf(0.0, _slosh - dt / 1.1)
	queue_redraw()


func _draw() -> void:
	var s := ui_scale
	var acc: Color = HudNoir.accent
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var b := body_rect()
	var rad := 10.0 * s
	var inner := NodeNoir.clean(NoirBox.rounded(b, rad))
	# the goo: everything under a wavy surface, clipped to the tank's inside
	var lv := clampf(shown, 0.0, 1.0)
	var amp := (1.5 + 6.0 * _slosh) * s
	var surf := PackedVector2Array()
	var n := 24
	for k in range(n + 1):
		var x := lerpf(b.position.x - 2.0, b.end.x + 2.0, float(k) / n)
		var u := float(k) / n
		var y := level_y(lv) + amp * (0.6 * sin(u * 9.0 + _t * 2.3) + 0.4 * sin(u * 17.0 - _t * 3.4)) \
				+ _slosh * 5.0 * s * sin(_t * 9.0) * (u - 0.5)
		surf.append(Vector2(x, y))
	var goo := surf.duplicate()
	goo.append(Vector2(b.end.x + 2.0, b.end.y + 2.0))
	goo.append(Vector2(b.position.x - 2.0, b.end.y + 2.0))
	for part in Geometry2D.intersect_polygons(goo, inner):
		var cp := NodeNoir.clean(part)
		if cp.size() < 3:
			continue
		var cols := PackedColorArray()
		for p in cp:
			var d := clampf((p.y - level_y(lv)) / maxf(b.size.y * lv, 1.0), 0.0, 1.0)
			cols.append(Color(acc.lerp(acc.darkened(0.55), d * 0.8), 0.92))
		draw_polygon(cp, cols)
	# rising bubbles inside the goo
	for i in range(6):
		var fi := float(i)
		var tt := fposmod(_t * (0.07 + 0.03 * fposmod(fi * 0.37, 1.0)) + fi * 0.19, 1.0)
		var bx := b.position.x + b.size.x * (0.2 + 0.6 * fposmod(fi * 0.61, 1.0)) + 2.0 * s * sin(_t * 2.0 + fi)
		var by := b.end.y - (b.end.y - level_y(lv)) * tt
		if by > level_y(lv) + 4.0 * s:
			draw_arc(Vector2(bx, by), (1.6 + 1.2 * fposmod(fi * 0.53, 1.0)) * s, 0.0, TAU, 10, Color(1, 1, 1, 0.35), 1.0 * s, true)
	# the meniscus: a bright line riding the surface (inside the tank only)
	var line := PackedVector2Array()
	for p in surf:
		if p.x > b.position.x + rad * 0.4 and p.x < b.end.x - rad * 0.4:
			line.append(p)
	if line.size() > 1:
		draw_polyline(line, Color(acc.lerp(Color.WHITE, 0.55), 0.95), 2.0 * s, true)
	# the wet streak down the glass, top-left
	draw_line(b.position + Vector2(5.0 * s, rad), b.position + Vector2(5.0 * s, b.size.y * 0.45), Color(1, 1, 1, 0.16), 2.0 * s, true)
	# the gauge: a tick per share on the right inner wall, its number beside it; the picked one lit
	var fs := maxi(int(13 * s), _floor_px())
	for l in LEVELS:
		var y := level_y(float(l)) + (2.0 * s if is_equal_approx(float(l), 1.0) else 0.0)
		var on := is_equal_approx(float(l), float(main.fraction))
		var x1 := b.end.x - 2.0 * s
		var x0 := x1 - (14.0 if on else 9.0) * s
		var col := Color(1, 1, 1, 0.95) if on else Color(HudNoir.INK, 0.55)
		if on:
			draw_line(Vector2(x0, y), Vector2(x1, y), Color(acc, 0.35), 6.0 * s, true)
		draw_line(Vector2(x0, y), Vector2(x1, y), col, (2.4 if on else 1.6) * s, true)
		if not is_equal_approx(float(l), float(main.fraction)) and absf(level_y(lv) - y) > fs * 1.6:
			var t := "%d" % int(round(float(l) * 100.0))
			var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(x0 - 4.0 * s - w, y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0)
			if is_equal_approx(float(l), 1.0):          # the top tick's number sits under it, inside the glass
				p.y = y + _font.get_ascent(fs) + 3.0 * s
			draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3 * s), Color(0, 0, 0, 0.7))
			draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(HudNoir.INK, 0.6))
	# on the surface: the share, big; under it the units it would send (one of your vats selected or being dragged)
	var big := maxi(int(22 * s), _floor_px() + 4)
	var txt := "%d%%" % int(round(float(main.fraction) * 100.0))
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var sy := clampf(level_y(lv) + _font.get_ascent(big) + 4.0 * s, b.position.y + _font.get_ascent(big) + 2.0 * s, b.end.y - 4.0 * s)
	var cx := b.position.x + (b.size.x - 18.0 * s) / 2.0
	draw_string_outline(_font, Vector2(cx - tw / 2.0, sy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big, int(5 * s), Color(0, 0, 0, 0.75))
	draw_string(_font, Vector2(cx - tw / 2.0, sy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big, HudNoir.INK)
	var units := _units_line()
	if units != "":
		var us := maxi(int(14 * s), _floor_px())
		var uw := _font.get_string_size(units, HORIZONTAL_ALIGNMENT_LEFT, -1, us).x
		var uy := minf(sy + _font.get_height(us), b.end.y - 4.0 * s)
		draw_string_outline(_font, Vector2(cx - uw / 2.0, uy), units, HORIZONTAL_ALIGNMENT_LEFT, -1, us, int(4 * s), Color(0, 0, 0, 0.75))
		draw_string(_font, Vector2(cx - uw / 2.0, uy), units, HORIZONTAL_ALIGNMENT_LEFT, -1, us, HudNoir.INK)


func _units_line() -> String:
	var source: int = main.drag_from if main.drag_from >= 0 else main.selected
	var sim = hud.sim
	if source >= 0 and source < sim.nodes.size() and sim.nodes[source]["owner"] == hud.human:
		return "%d / %d" % [Rules.shown(floorf(sim.nodes[source]["units"] * main.fraction)), Rules.shown(sim.nodes[source]["units"])]
	return ""


func _floor_px() -> int:
	## The phone's 12.5 pt floor in px (0 on desktop).
	if not bool(hud.mobile):
		return 0
	return int(ceil(12.5 / maxf(UiKit.pt_per_px(get_viewport_rect().size), 0.01)))
