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
	for a in OS.get_cmdline_user_args():          # screenshots: --send-frac=0.25 starts the pick at that share
		if a.begins_with("--send-frac="):
			main.fraction = clampf(float(a.substr(12)), 0.25, 1.0)
		elif a.begins_with("--send-select="):     # screenshots: one of your vats selected (the plate's 7 / 15 readout)
			main.selected = int(a.substr(14))
	shown = float(main.fraction)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame = HudNoir.box("send_tank" if HudNoir.has("send_tank") else "send_housing", HudNoir.accent if HudNoir.has("send_tank") else Color(0, 0, 0, 0), Vector4.ZERO)   # GMN-1: the tank's white neon rim in the accent


# GMN-1: the glass inside the director's tank, measured on send_tank_liquid.png (canvas px): x 60..336, y 180..1060
const GLASS := Rect2(60, 180, 276, 880)
const GLASS_GMN2 := Rect2(72, 177, 252, 810)      # GMN-2 (thin VEX tank, README "GEL REGISTRATION"): the glass / liquid interior


# ui-send-tank (designer spec, Daniele "Yes, send it" 2026-11-09): the NEON-RESTYLE B_send layers drawn as ONE evenly scaled
# picture (no 9-slice). The control shows the canvas from x 48..348, y 48..PIC_BOTTOM (the body 300 x 1080 + the drip) and the
# readout plate under it. Levels come from the art's liquid box: 100 % = canvas y 177, 0 % = y 987.
const PIC_X := 48.0
const PIC_Y := 48.0
const PIC_W := 300.0
const PIC_BOTTOM := 1250.0                        # under the drip's tip (canvas 1237) + the drop's room
const LIQ_TOP := 177.0
const LVL_TOP := 214.0                            # ui-neon-apply (Daniele 2026-11-09): 100 % ~4.5 % under the glass top (half his first ask)
const LIQ_BOT := 987.0
const LIQ_X0 := 72.0
const LIQ_X1 := 324.0
const PLATE_PT := 24.0                            # the readout plate's height (pt, x the tank's pt scale)
const PLATE_GAP_PT := 2.0
var canvas_k := 0.0                               # control px per canvas px (Hud sets it; 0 = the old frame path)
var pt_px := 1.0                                  # control px per HUD point (Hud sets it)


func picture() -> bool:
	return canvas_k > 0.0 and gmn()


func cv(p: Vector2) -> Vector2:
	## A canvas point in control px.
	return Vector2((p.x - PIC_X) * canvas_k, (p.y - PIC_Y) * canvas_k)


func body_mid_y() -> float:
	## The tank body's centre (canvas y 48..1128) in control px: Hud.layout centres it on the screen.
	return cv(Vector2(0, (PIC_Y + 1128.0) / 2.0)).y


func picture_size(k: float, ptk: float) -> Vector2:
	## The control's size for canvas scale k and pt scale ptk: the picture plus the readout plate under it.
	return Vector2(PIC_W * k, (PIC_BOTTOM - PIC_Y) * k)       # (no readout plate: Daniele 2026-11-09 "remove the 50% form")


func glass() -> Rect2:
	## The canvas rect of the tank's glass: GMN-2's thinner tank when its boards are in (send_tank_drip ships with them).
	return GLASS_GMN2 if HudNoir.has("send_tank_drip") else GLASS


func gmn() -> bool:
	return HudNoir.has("send_tank_liquid")


func body_rect() -> Rect2:
	## The tank's inside (the goo's room): the frame's rect minus its rim and the drips under it.
	if picture():                                 # the art's liquid box: x 72..324, y 177 (100 %) .. 987 (0 %)
		var a := cv(Vector2(LIQ_X0, LVL_TOP))
		return Rect2(a, cv(Vector2(LIQ_X1, LIQ_BOT)) - a)
	var drip := HudNoir.drip_px("send_tank" if HudNoir.has("send_tank") else "send_housing")
	if gmn():                                     # the director's glass: caps top and bottom, the walls at the sides
		var p := HudNoir.part_data("send_tank")
		var bd: Array = p.get("body", [48, 48, 300, 1080])
		var k := ui_scale / HudNoir.SPRITE_K
		var h := size.y - drip
		var gl := glass()
		var top := (gl.position.y - float(bd[1])) * k
		var bot := (float(bd[1]) + float(bd[3]) - gl.end.y) * k
		var side := (gl.position.x - float(bd[0])) * k
		return Rect2(Vector2(side, top), Vector2(size.x - 2.0 * side, h - top - bot))
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
	if picture():
		_draw_picture()
		return
	var s := ui_scale
	var acc: Color = GooTone.mine(HudNoir.accent)     # the goo = your faction's body tone (GooTone); ticks / rim stay neon
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var b := body_rect()
	var rad := 10.0 * s
	var inner := NodeNoir.clean(NoirBox.rounded(b, rad))
	# the goo: everything under a wavy surface, clipped to the tank's inside
	var lv := clampf(shown, 0.0, 1.0)
	# GMN-1 (Daniele: "too stable ... not seamless"): a livelier surface - a slow idle sway that never stops, two travelling
	# waves, the slosh on top - sampled finely (48) so the edge never steps; at 100 % it calms under the cap
	var calm := 0.35 if lv >= 0.999 else 1.0
	var amp := (2.6 + 6.0 * _slosh) * s * calm
	var sway := 2.2 * s * calm * sin(_t * 1.3)
	var surf := PackedVector2Array()
	var n := 48
	for k in range(n + 1):
		var x := lerpf(b.position.x - 2.0, b.end.x + 2.0, float(k) / n)
		var u := float(k) / n
		var y := level_y(lv) + amp * (0.55 * sin(u * 7.0 + _t * 2.1) + 0.45 * sin(u * 13.0 - _t * 3.1)) 				+ (sway + _slosh * 5.0 * s * sin(_t * 9.0)) * (u - 0.5) * 2.0
		surf.append(Vector2(x, y))
	var goo := surf.duplicate()
	goo.append(Vector2(b.end.x + 2.0, b.end.y + 2.0))
	goo.append(Vector2(b.position.x - 2.0, b.end.y + 2.0))
	var gl := glass()
	for part in Geometry2D.intersect_polygons(goo, inner):
		var cp := NodeNoir.clean(part)
		if cp.size() < 3:
			continue
		if gmn():                                 # GMN-1: the director's lit ooze (tinted) and its shine (white), in the glass
			var uvs := PackedVector2Array()
			var cs := PackedColorArray()
			for p in cp:
				var u := (p - b.position) / b.size
				uvs.append(Vector2((gl.position.x + u.x * gl.size.x) / 396.0, (gl.position.y + u.y * gl.size.y) / 1284.0))
				cs.append(acc)
			draw_polygon(cp, cs, uvs, HudNoir.texture(str(HudNoir.part_data("send_tank_liquid").get("file", ""))))
			cs.fill(Color.WHITE)
			draw_polygon(cp, cs, uvs, HudNoir.texture(str(HudNoir.part_data("send_tank").get("shine", ""))))
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
	if gmn():
		_draw_gmn_drips(b, acc)
	# the meniscus: a bright line riding the surface (inside the tank only)
	var line := PackedVector2Array()
	for p in surf:
		if p.x > b.position.x + rad * 0.4 and p.x < b.end.x - rad * 0.4:
			line.append(p)
	if line.size() > 1:
		draw_polyline(line, Color(acc.lerp(Color.WHITE, 0.55), 0.95), 2.0 * s, true)
	# the wet streak down the glass, top-left
	if not gmn():
		draw_line(b.position + Vector2(5.0 * s, rad), b.position + Vector2(5.0 * s, b.size.y * 0.45), Color(1, 1, 1, 0.16), 2.0 * s, true)
	var fs := maxi(int(13 * s), _floor_px())
	if gmn():
		_draw_gmn_gauge(b, fs)
		return
	# the gauge: a tick per share on the right inner wall, its number beside it; the picked one lit
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


func _draw_gmn_gauge(b: Rect2, fs: int) -> void:
	## GMN-1 (the director's tank, Daniele: "apply the correct vat"): a bold white line at each quarter with its share
	## centred on it (- 75% -), the picked one lit in the accent; the units on the bottom of the glass. No SEND word (Daniele 2026-11-05: "Drop SEND").
	var s := ui_scale
	var acc: Color = HudNoir.accent
	var ol := Color(0, 0, 0, 0.75)
	for l in LEVELS:
		var y := level_y(float(l))
		var on := is_equal_approx(float(l), float(main.fraction))
		var t := "%d%%" % int(round(float(l) * 100.0))
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := b.get_center().x
		var gapx := w / 2.0 + 3.0 * s
		var col := Color.WHITE if on else Color(1, 1, 1, 0.85)
		var lw := (3.0 if on else 2.0) * s
		for sg: float in [-1.0, 1.0]:
			var x0 := cx + sg * gapx
			var x1 := b.position.x + 2.0 * s if sg < 0.0 else b.end.x - 2.0 * s
			if on:
				draw_line(Vector2(x0, y), Vector2(x1, y), Color(acc, 0.45), lw * 3.0, true)
			draw_line(Vector2(x0, y), Vector2(x1, y), col, lw, true)
		var p := Vector2(cx - w / 2.0, y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0)
		draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), ol)
		draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, acc.lerp(Color.WHITE, 0.5) if on else Color.WHITE)
	var units := _units_line()
	if units != "":
		var uw := _font.get_string_size(units, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var up := Vector2(b.get_center().x - uw / 2.0, b.end.y - 6.0 * s)
		draw_string_outline(_font, up, units, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), ol)
		draw_string(_font, up, units, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_gmn_drips(b: Rect2, acc: Color) -> void:
	## GMN-1 (Daniele: "lacks the drip"): the goo hanging under the bottom cap - the director's liquid layer below the body
	## (canvas y 1110..1246), tinted - and a drop that swells, falls and fades, again and again.
	var k := ui_scale / HudNoir.SPRITE_K
	var cap_y := b.end.y + (1128.0 - glass().end.y) * k           # the body's bottom (canvas 1128): the cap's lower rim
	var drip := HudNoir.texture(str(HudNoir.part_data("send_tank_drip").get("file", "")))
	if drip != null:                                               # GMN-2: the director's send_tank_drip under the nozzle (white,
		var sx := size.x / 300.0                                   # tinted), hanging from the cap and breathing a little, then the drop
		var st := 1.0 + 0.07 * sin(_t * 2.3)
		var src2 := Rect2(150, 1120, 96, 124)
		var dst2 := Rect2(Vector2((src2.position.x - 48.0) * sx, cap_y + (src2.position.y - 1128.0) * k), Vector2(src2.size.x * sx, src2.size.y * k * st))
		draw_texture_rect_region(drip, dst2, src2, Color(acc, 0.95))
		_drop(Vector2((198.0 - 48.0) * sx, cap_y + (1233.0 - 1128.0) * k * st), acc)
		return
	var tex := HudNoir.texture(str(HudNoir.part_data("send_tank_liquid").get("file", "")))
	if tex == null:
		return
	var src := Rect2(48, 1110, 300, 136)
	var dst := Rect2(Vector2(0.0, cap_y - 18.0 * k), Vector2(size.x, 136.0 * k))
	draw_texture_rect_region(tex, dst, src, Color(acc, 0.95))
	_drop(Vector2(dst.position.x + dst.size.x * 0.32, dst.end.y - 8.0 * k), acc)


func _drop(tip: Vector2, acc: Color) -> void:
	## A drop that swells at the drip's tip, falls and fades - one every 1.8 s.
	var cyc := fposmod(_t, 1.8) / 1.8
	var r := (2.2 + 1.6 * minf(cyc * 2.0, 1.0)) * ui_scale
	var fall := maxf(0.0, cyc - 0.55) / 0.45
	var p := tip + Vector2(0, 26.0 * ui_scale * fall * fall)
	draw_circle(p, r * (1.0 - 0.3 * fall), Color(acc, 0.95 * (1.0 - fall)))
	draw_circle(p - Vector2(r, r) * 0.3, r * 0.3, Color(1, 1, 1, 0.6 * (1.0 - fall)))


func _layer(key: String) -> Texture2D:
	## One B_send layer (canvas 396 x 1284) by its file stem: fill / liquid / surface / rim / shine / drip.
	return HudNoir.texture("res://assets/ui/hud_noir/send_tank_%s.png" % key)


func _draw_layer(tex: Texture2D, src: Rect2, col: Color, dy := 0.0) -> void:
	## Draw a canvas region of a layer at its own place (moved dy canvas px), evenly scaled.
	if tex == null or src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	draw_texture_rect_region(tex, Rect2(cv(src.position + Vector2(0, dy)), src.size * canvas_k), src, col)


func _draw_picture() -> void:
	## ui-send-tank: fill (metal + glass) -> the liquid and its shine CLIPPED at the level (never stretched) -> bubbles ->
	## the surface ring and the rim glow riding the level -> the drip + drop -> the level marks -> the readout plate.
	var s := pt_px
	var acc: Color = GooTone.mine(HudNoir.accent)     # the goo = your faction's body tone (GooTone); ticks / rim stay neon
	var lv := clampf(shown, 0.0, 1.0)
	var ly := lerpf(LIQ_BOT, LVL_TOP, lv)                                    # the level in canvas px
	_draw_layer(_layer("fill"), Rect2(PIC_X, PIC_Y, PIC_W, 1128.0 - PIC_Y), Color.WHITE)
	# the goo: a gently moving surface over the art's liquid, clipped to the glass; UVs = the canvas itself (1:1, no stretch)
	var full := lv >= 0.999
	var calm := 0.5 if full else 1.0
	var amp := (5.0 + 14.0 * _slosh) * calm                                  # canvas px
	var sway := 6.0 * calm * sin(_t * 1.3) + _slosh * 12.0 * sin(_t * 9.0)
	var poly := PackedVector2Array()
	var n := 32
	for k in range(n + 1):
		var u := float(k) / n
		var x := lerpf(LIQ_X0, LIQ_X1, u)
		var y := ly + amp * (0.55 * sin(u * 7.0 + _t * 2.1) + 0.45 * sin(u * 13.0 - _t * 3.1)) + sway * (u - 0.5) * 2.0
		y = clampf(y, LIQ_TOP, LIQ_BOT)                                    # (100 % = LVL_TOP: the surface keeps moving under the cap)
		poly.append(Vector2(x, y))
	poly.append(Vector2(LIQ_X1, LIQ_BOT))
	poly.append(Vector2(LIQ_X0, LIQ_BOT))
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for q in poly:
		pts.append(cv(q))
		uvs.append(q / Vector2(396.0, 1284.0))
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(acc)
	var liq := _layer("liquid")
	if liq != null and lv > 0.001:
		draw_polygon(pts, cols, uvs, liq)
		var shine := _layer("shine")
		if shine != null:
			cols.fill(Color.WHITE)
			draw_polygon(pts, cols, uvs, shine)
	# rising bubbles inside the goo
	for i in range(6):
		var fi := float(i)
		var tt := fposmod(_t * (0.07 + 0.03 * fposmod(fi * 0.37, 1.0)) + fi * 0.19, 1.0)
		var bx := lerpf(LIQ_X0 + 30.0, LIQ_X1 - 30.0, fposmod(fi * 0.61, 1.0)) + 5.0 * sin(_t * 2.0 + fi)
		var by := LIQ_BOT - 12.0 - (LIQ_BOT - 12.0 - ly) * tt
		if by > ly + 14.0:
			draw_arc(cv(Vector2(bx, by)), (1.6 + 1.2 * fposmod(fi * 0.53, 1.0)) * s, 0.0, TAU, 10, Color(1, 1, 1, 0.35), 1.0 * s, true)
	# the surface ring (art y 48..88, centre 68) and the rim glow (art centre 582.5 = the 50 % line) ride the level
	if lv > 0.001:
		_draw_layer(_layer("surface"), Rect2(48, 48, 300, 40), Color(acc.lerp(Color.WHITE, 0.35), 0.95), ly - 68.0 + sway * 0.3)
		_draw_layer(_layer("rim"), Rect2(18, 560, 360, 45), Color(acc.lerp(Color.WHITE, 0.4), 0.95), ly - 582.5)
	# the drip under the nozzle (tinted, breathing a little) and the drop
	var st := 1.0 + 0.07 * sin(_t * 2.3)
	var dsrc := Rect2(150, 1120, 96, 124)
	var drip := _layer("drip")
	if drip != null:
		draw_texture_rect_region(drip, Rect2(cv(dsrc.position), Vector2(dsrc.size.x, dsrc.size.y * st) * canvas_k), dsrc, Color(acc, 0.95))
	_drop(cv(Vector2(198.0, 1120.0 + (1233.0 - 1120.0) * st)), acc)
	# the level marks + words at the liquid box's quarters, then the readout plate under the tank
	var fs := maxi(int(ceil(13.0 * s)), _floor_px())
	_draw_marks(fs)


func _draw_marks(fs: int) -> void:
	## 25 / 50 / 75 / 100 at y = lerp(987, LVL_TOP, share): a white line each side of the word (- 75% -), the picked one lit.
	var s := pt_px
	var acc: Color = HudNoir.accent
	var b := body_rect()
	var ol := Color(0, 0, 0, 0.8)
	for l in LEVELS:
		var y := level_y(float(l))
		var on := is_equal_approx(float(l), float(main.fraction))
		var t := "%d%%" % int(round(float(l) * 100.0))
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := b.get_center().x
		var gapx := w / 2.0 + 3.0 * s
		var col := Color.WHITE if on else Color(1, 1, 1, 0.8)
		var lw := (2.4 if on else 1.4) * s
		for sg: float in [-1.0, 1.0]:
			var x0 := cx + sg * gapx
			var x1 := b.position.x + 1.0 * s if sg < 0.0 else b.end.x - 1.0 * s
			if on:
				draw_line(Vector2(x0, y), Vector2(x1, y), Color(acc, 0.45), lw * 3.0, true)
			draw_line(Vector2(x0, y), Vector2(x1, y), Color(0, 0, 0, 0.5), lw + 2.0 * s, true)
			draw_line(Vector2(x0, y), Vector2(x1, y), col, lw, true)
		var p := Vector2(cx - w / 2.0, y + (_font.get_ascent(fs) - _font.get_descent(fs)) / 2.0)
		draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(4 * s)), ol)
		draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_plate(fs: int) -> void:
	## The readout under the tank: the units the pick sends (7 / 15) with one of your vats selected or dragged, else the share.
	var s := pt_px
	var acc: Color = HudNoir.accent
	var top := (PIC_BOTTOM - PIC_Y) * canvas_k + PLATE_GAP_PT * s
	var r := Rect2(Vector2(cv(Vector2(LIQ_X0 - 14.0, 0)).x, top), Vector2((LIQ_X1 - LIQ_X0 + 28.0) * canvas_k, PLATE_PT * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, 0.88)
	sb.border_color = Color(acc, 0.85)
	sb.set_border_width_all(maxi(1, int(round(1.5 * s))))
	sb.set_corner_radius_all(int(6.0 * s))
	draw_style_box(sb, r)
	var units := _units_line()
	var t := units if units != "" else "%d%%" % int(round(float(main.fraction) * 100.0))
	var f := fs
	while f > 8 and _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > r.size.x - 6.0 * s:
		f -= 1
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var p := Vector2(r.get_center().x - w / 2.0, r.get_center().y + (_font.get_ascent(f) - _font.get_descent(f)) / 2.0)
	draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, maxi(3, int(3 * s)), Color(0, 0, 0, 0.8))
	draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color.WHITE)
