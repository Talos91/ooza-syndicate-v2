class_name HudLab
extends RefCounted
## hud-lab (2026-11-13): the round-29 / round-30 lab HUD pack (UI designer 4, DIRECTOR-PACKAGE/deliveries/29-hud-pieces-FINAL) as the
## default in-match HUD. Every piece is the pack's 3x PNG (derivatives in assets/ui/lab29, originals untouched) drawn evenly scaled at
## the README's LOCKED phone sizes (Daniele 2026-11-13): skill keys x1.2 (~76 x 68 pt), sending vat x1.2 (~88 x 253 pt with its feed),
## node badges 28 x 21 pt, the score tube with the timer only. Goo = shaders/hud_goo.gdshader (tint per player, level from the match,
## slosh, bubbles, glass highlight; clipped by the goo master's alpha). Key and slice states are built at run time from the masks;
## numbers, names and timers are drawn live. Placement: 25-hud-pieces-B/PIECES.json and round30-pipes/GEO.json (812 x 375 pt frame).
## Off: dev --hud-old (the pre-lab HUD, as staging 0.24.1) or Rules.HUD_LAB = false.

const DIR := "res://assets/ui/lab29/"
const GOO := preload("res://shaders/hud_goo.gdshader")
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSansMono.woff2")
const INK := Color("1e3a3f")                    # the pack's label ink (A3 / A4 / A5)
const LIGHT := Color("eef7f4")                  # light digits on dark windows (badge count, timer, key seconds)
const WARN_INK := Color("a3242f")               # a slice's price you cannot pay yet
const SWITCH_AMBER := Color("ffb238")
const PX := 3.0                                 # art px per pt (the 3x exports)
const KEY_K := 1.2                              # LOCKED 2026-11-13: skill keys +20 %
const VAT_K := 1.2                              # LOCKED 2026-11-13: sending vat +20 %
const KEY_PT := Vector2(62, 57)                 # KEY-SHELL body (pt at 1x)
const KEY_PITCH := 60.0                         # PIECES.json key pitch (pt at 1x): the skill feed's branches match it
const KEY_WINDOW_C := Vector2(31.5, 20.5)       # the icon window's centre (GEO-A key icon_window 12.5, 5, 38 x 31)
const KEY_NAME_C := Vector2(31.5, 46.5)         # the name strip's centre (GEO-A key name anchor)
const SKILL_FEED_OFF := Vector2(-16, -21)       # round-30 skill feed canvas (719, 67) from key 0 (735, 88), pt at 1x
const SKILL_FEED_PT := Vector2(93, 192)
const BADGE_PT := Vector2(28, 21)               # LOCKED (revised 2026-11-13 from 34 x 25)
const BADGE_ART := Vector2(59, 44)
const VAT_CANVAS := Vector2(87, 211)            # every VAT-* layer's canvas (pt at 1x), at (0, 74) in the frame
const VAT_BODY_X := 16.0                        # the vat body's left in that canvas (left of it: the feed stub to the screen edge)
const VAT_GOO_PX := Rect2(78, 96, 141, 410)     # VAT-GOO-WHITE's box (3x px): 0 % at its bottom, 100 % at its top (README)
const VAT_FEED_AT := Vector2(0, 177)            # round-30 VAT-FEED (0, 251) in the vat canvas (pt at 1x)
const VAT_FEED_PT := Vector2(28, 20)
const TUBE_PT := Vector2(288, 42)               # round-30 TUBE canvas, top edge = the screen top
const TUBE_R25_AT := Vector2(1, 4)              # round-25 tube layers (glass, timer window) in the round-30 canvas (body offset)
const TUBE_STRIP_AT := Vector2(38, 7)           # round-25 goo strips (300, 6) + the body offset, in the round-30 canvas
const TUBE_STRIP_PT := Vector2(213, 30)
const TUBE_TIMER_C := Vector2(145, 21.7)        # the timer window's centre in the round-30 canvas
const BUTTON_PT := 32.0                         # music / pause shells; their taps 40 pt (PIECES.json hit boxes)
const BUTTON_HIT := 40.0
const SLICE_R := [49.0, 119.0]
const CARD_PT := Vector2(196, 66)
const CLOSE_PT := 44.0
const TOAST_PT := Vector2(280, 30)
const BANNER_PT := Vector2(328, 54)

static var _tex := {}


static func on() -> bool:
	if not Rules.HUD_LAB or "--hud-old" in OS.get_cmdline_user_args():
		return false
	return tex("vat-shell") != null


static func tex(n: String) -> Texture2D:
	var k := LookTheme.current + "/" + n              # THEMES: the setting's painted shell (the 14 shells), else the lab's
	if not _tex.has(k):
		var tp := LookTheme.hud_path(n)
		var p := DIR + n + ".png"
		_tex[k] = load(tp) if tp != "" else (load(p) if ResourceLoader.exists(p) else null)
	return _tex[k]


static func u_for(vp: Vector2, mobile: bool) -> float:
	## Screen px per layout pt: the HUD's pt (phones: real pt x hud_k), desktop x 1.2 (as the tank and HudR19).
	return UiKit.hud_px_per_pt(vp, mobile) * (1.0 if mobile else 1.2)


static func u_of(hud) -> float:
	return u_for(hud.root.get_viewport_rect().size, hud.mobile)


static func art(ci: CanvasItem, n: String, pos: Vector2, k: float, col := Color.WHITE) -> void:
	## Draw a 3x layer at pos (px), k = screen px per pt.
	var t := tex(n)
	if t != null:
		ci.draw_texture_rect(t, Rect2(pos, t.get_size() * k / PX), false, col)


static func art_part(ci: CanvasItem, n: String, pos: Vector2, k: float, src: Rect2, col := Color.WHITE) -> void:
	## Draw the src (3x px) part of a layer, placed where it sits in the full layer.
	var t := tex(n)
	if t != null and src.size.x > 0.0 and src.size.y > 0.0:
		ci.draw_texture_rect_region(t, Rect2(pos + src.position * k / PX, src.size * k / PX), src, col)


static func fit_px(txt: String, px: float, maxw: float, font: Font = UI_FONT, floor_px := 0.0) -> int:
	var fs := int(round(px))
	while fs > maxi(6, int(floor_px)) and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
		fs -= 1
	return fs


static func text_c(ci: CanvasItem, txt: String, c: Vector2, fs: int, col: Color, font: Font = UI_FONT, outline := 0, out_col := Color(0, 0, 0, 0.8)) -> void:
	## A line centred on c.
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(c.x - w / 2.0, c.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0)
	if outline > 0:
		ci.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, out_col)
	ci.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func text_l(ci: CanvasItem, txt: String, left_mid: Vector2, fs: int, col: Color, font: Font = UI_FONT) -> void:
	ci.draw_string(font, Vector2(left_mid.x, left_mid.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func bold() -> Font:
	return UiKit.HEAD if UiKit.HEAD != null else UI_FONT


class Goo:
	## A goo layer: its WHITE master drawn over the control's rect through hud_goo.gdshader (uniforms set by the owner each frame).
	extends Control
	var texture: Texture2D

	func _init(t: Texture2D, mode: int) -> void:
		texture = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var m := ShaderMaterial.new()
		m.shader = HudLab.GOO
		material = m
		p("mode", mode)
		if t != null:
			p("aspect", t.get_size().x / maxf(t.get_size().y, 1.0))

	func p(k: String, v) -> void:
		(material as ShaderMaterial).set_shader_parameter(k, v)

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


class Pic:
	## Static layers drawn over the control's rect, in order: [[name, colour], ...].
	extends Control
	var layers: Array = []

	func _init(l: Array) -> void:
		layers = l
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		for l in layers:
			var t := HudLab.tex(str(l[0]))
			if t != null:
				draw_texture_rect(t, Rect2(Vector2.ZERO, size), false, l[1] if l.size() > 1 else Color.WHITE)


static func pipe_run(ci: CanvasItem, pre: String, src: Rect2, dest: Rect2, goo: Color) -> void:
	## Daniele 2026-11-13 (phone shot): a feed pipe runs off the PHYSICAL screen edge, never ends in mid-air. A straight run =
	## a thin slice (src, 3x px; >= 8 px, 1 px samples empty under mipmaps) of the pipe's own layers stretched over dest: shell, window, the WHITE goo tinted `goo`, glass.
	if dest.size.x <= 0.0 or dest.size.y <= 0.0:
		return
	for l in [["shell", Color.WHITE], ["window", Color.WHITE], ["goo-white", goo], ["glass", Color.WHITE]]:
		var t := tex(pre + str(l[0]))
		if t != null and (l[1] as Color).a > 0.0:
			ci.draw_texture_rect_region(t, dest, src, l[1])


static func place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz


# ------------------------------------------------------------------------------------------------ the score tube (top centre)

class Tube:
	## Round-30 score tube with its elbows turned up off the screen top; the goo = each seat's share of the units on the map
	## (Sim.seat_strength, as the old score pills), NO score numbers (Daniele 2026-11-13); the match clock in the centre window.
	extends Control
	var hud
	var u := 1.0
	var seats: Array = []                        # left to right: your group first (Hud._seat_groups)
	var strip: Goo
	var elbows: Goo
	var show_shares := true
	var _force: Array = []                       # dev shots: --lab-tube=a,b,... fixed shares (the collar close-up)

	func setup(h) -> void:
		hud = h
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--lab-tube="):
				for v in a.substr(11).split(","):
					_force.append(float(v))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var groups: Array = hud._seat_groups()
		for gi in range(groups.size()):
			for s in groups[gi]:
				seats.append(s)
			if gi == 0:
				seats.append("")                     # Daniele 2026-11-13: the neutral share in GREY, after your side
		var win := HudLab.Pic.new([["r30-tube-window"]])
		add_child(win)
		elbows = HudLab.Goo.new(HudLab.tex("r30-tube-goo-white"), 1)
		add_child(elbows)
		strip = HudLab.Goo.new(HudLab.tex("tube-goo-strip-white"), 1)
		add_child(strip)
		var glass := HudLab.Pic.new([["r30-tube-glass"]])
		add_child(glass)
		var over := Control.new()
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		over.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		over.draw.connect(_draw_over.bind(over))
		add_child(over)
		set_meta("parts", [win, glass, over])

	func lay(vp: Vector2, scale_u: float) -> void:
		u = scale_u
		size = HudLab.TUBE_PT * u
		position = Vector2(vp.x / 2.0 - size.x / 2.0, 0.0)
		for c in get_meta("parts"):
			HudLab.place(c, Vector2.ZERO, size)
		HudLab.place(elbows, Vector2.ZERO, size)
		HudLab.place(strip, HudLab.TUBE_STRIP_AT * u, HudLab.TUBE_STRIP_PT * u)

	func sync() -> void:
		var tot := 0.0
		var vals: Array = []
		for s in seats:
			var v := 0.0
			if s == "":
				v = _neutral_strength()
			elif not hud._seat_out(s):
				v = maxf(float(hud.sim.seat_strength(s)), 0.0)
			if vals.size() < _force.size():
				v = _force[vals.size()]
			vals.append(v)
			tot += v
		var ends := PackedFloat32Array()
		var cols := PackedColorArray()
		var acc := 0.0
		var n := mini(seats.size(), 6)
		for i in range(n):
			acc += (float(vals[i]) / tot) if tot > 0.0 else 1.0 / float(n)
			ends.append(acc if i < n - 1 else 1.0)
			cols.append(NEUTRAL_GOO if str(seats[i]) == "" else HudLab.seat_goo(str(seats[i]), hud.human))
		while ends.size() < 6:
			ends.append(1.0)
			cols.append(Color.WHITE)
		for g in [strip, elbows]:
			(g as HudLab.Goo).p("seats", n)
			(g as HudLab.Goo).p("seat_end", ends)
			(g as HudLab.Goo).p("seat_tint", cols)
			(g as HudLab.Goo).p("collar", 0.0)      # (the round-25 TUBE-COLLAR piece marks the splits: _draw_over)
		var e2 := PackedFloat32Array([0.5, 1.0, 1.0, 1.0, 1.0, 1.0])   # the elbows: the first seat left, the last right
		var c2 := PackedColorArray([cols[0], cols[maxi(n - 1, 0)], Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		elbows.p("seats", 2 if n > 1 else 1)
		elbows.p("seat_end", e2)
		elbows.p("seat_tint", c2)
		elbows.p("collar", 0.0)
		strip.visible = show_shares
		set_meta("ends", ends)
		set_meta("n", n)
		get_child(get_child_count() - 1).queue_redraw()

	func _draw() -> void:
		HudLab.art(self, "r30-tube-shell", Vector2.ZERO, u)

	const NEUTRAL_GOO := Color("7a8285")            # neutral = grey goo (Daniele 2026-11-13)

	func _neutral_strength() -> float:
		## The neutral share, the same measure as Sim.seat_strength for a seat: the units held on neutral nodes.
		var t := 0.0
		for n in hud.sim.nodes:
			if str(n["owner"]) == "":
				t += maxf(float(n["units"]), 0.0)
		return t

	const COLLAR_W := 6.0                           # pt (designer 4, 0.24.2 look check: 2 pt read as a hairline)
	const COLLAR_IVORY := Color("f1ead8")           # the tube shell's ivory: a ring round the glass between two goos
	var _win_cols := PackedVector2Array()           # per strip column (3x px): the goo window's top / bottom (3x px)

	func _window_cols() -> PackedVector2Array:
		## The strip's own alpha = the tube window; the collar is clipped to it column by column (never on the shell).
		if _win_cols.is_empty():
			var t := HudLab.tex("tube-goo-strip-white")
			var img: Image = t.get_image() if t != null else null
			if img == null:
				return _win_cols
			if img.is_compressed():
				img.decompress()
			for x in range(img.get_width()):
				var top := -1
				var bot := -1
				for y in range(img.get_height()):
					if img.get_pixel(x, y).a > 0.5:
						if top < 0:
							top = y
						bot = y + 1
				_win_cols.append(Vector2(top, bot))
		return _win_cols

	func _collar(ci: Control, sx: float) -> void:
		## A 6 pt ivory collar with ink edges at strip x = sx (pt), clipped to the window: drawn per 3x column, so the
		## rounded ends and the window's edge stay goo-free outside the window.
		var cols := _window_cols()
		if cols.is_empty():
			return
		var px := HudLab.PX
		var x0 := int(floor((sx - COLLAR_W / 2.0) * px))
		var x1 := int(ceil((sx + COLLAR_W / 2.0) * px))
		var at := HudLab.TUBE_STRIP_AT * u
		var k := u / px
		for x in range(maxi(x0, 0), mini(x1, cols.size())):
			var c := cols[x]
			if c.x < 0.0:
				continue
			var edge := x - x0 < 3 or x1 - x <= 3      # 1 pt ink line each side
			var col := Color(HudLab.INK, 0.85) if edge else COLLAR_IVORY
			ci.draw_rect(Rect2(at + Vector2(x * k, c.x * k), Vector2(k, (c.y - c.x) * k)), col)

	func _draw_over(ci: Control) -> void:
		if show_shares and has_meta("ends"):          # designer 4: the 6 pt TUBE-COLLAR at each split so the sides read apart
			var ends: PackedFloat32Array = get_meta("ends")
			for i in range(int(get_meta("n")) - 1):
				_collar(ci, HudLab.TUBE_STRIP_PT.x * ends[i])
		HudLab.art(ci, "tube-glass", HudLab.TUBE_R25_AT * u, u)
		HudLab.art(ci, "tube-timer-window", HudLab.TUBE_R25_AT * u, u)
		var t: float = hud.sim.time
		var txt := "%02d:%02d" % [int(t) / 60, int(t) % 60]
		var fs := int(round(16.0 * u))
		HudLab.text_c(ci, txt, HudLab.TUBE_TIMER_C * u, fs, HudLab.LIGHT, HudLab.bold())


static func seat_goo(seat: String, human: String) -> Color:
	## A seat's goo in the HUD: yours = your faction's goo tone (as the vat), the others their seat colour (room colours rule).
	var c := Rules.seat_color(seat)
	if seat == human:
		c = GooTone.mine(HudNoir.accent)
	return c


# ------------------------------------------------------------------------------------------------ the skill feed (beside the keys)

class SkillFeed:
	## Round-30 glass pipe from the top-right edge down the outside of the three keys, a branch into each. Its goo fills toward
	## the keys as the skills charge (the README's conservative meaning): level = the mean readiness of the three slots.
	extends Control
	var dock
	var goo: Goo
	var flow: Pic
	var _t := 0.0

	func setup(d) -> void:
		dock = d
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shell := HudLab.Pic.new([["r30-skill-feed-shell"], ["r30-skill-feed-window"]])
		add_child(shell)
		goo = HudLab.Goo.new(HudLab.tex("r30-skill-feed-goo-white"), 3)
		goo.p("axis", 1.0)
		goo.p("v_top", 0.0)
		goo.p("v_bot", 1.0)
		goo.p("pulse_rate", 0.35)
		add_child(goo)
		flow = HudLab.Pic.new([["r30-skill-feed-flow", Color(1, 1, 1, 0.0)]])
		add_child(flow)
		add_child(HudLab.Pic.new([["r30-skill-feed-glass"]]))

	func lay(key0: Vector2, u: float) -> void:
		var k := HudLab.KEY_K * u
		position = key0 + HudLab.SKILL_FEED_OFF * k
		size = HudLab.SKILL_FEED_PT * k
		for c in get_children():
			HudLab.place(c, Vector2.ZERO, size)

	func _process(dt: float) -> void:
		_t += dt
		if dock == null or not is_instance_valid(dock):
			return
		visible = dock.visible
		var tot := 0.0
		for s in dock.slots:
			var full: bool = s.is_ready or s.fires > 0
			tot += 1.0 if full else (float(s.frac) if s.index == 2 else 1.0 - float(s.frac))
		var lv := tot / maxf(float(dock.slots.size()), 1.0)
		goo.p("level", clampf(lv, 0.0, 1.0))
		goo.p("tint", GooTone.mine(HudNoir.accent))
		flow.layers[0][1] = Color(1, 1, 1, 0.18 + 0.18 * sin(_t * 2.4))
		flow.queue_redraw()


# ------------------------------------------------------------------------------------------------ the skill keys (SkillDock.Slot)

static func draw_key(sl) -> void:
	## One skill key: shell + icon window + the skill's icon, its name in the strip; states made at run time:
	## READY = KEY-NEON-EDGE in your accent (breathing), COOLING = KEY-SWEEP-COOLING clipped to the time left + the seconds,
	## LOCKED = dimmed with a padlock; ARMED = the edge solid in the slot colour; a refused tap flashes it red.
	var dock = sl.dock
	var u: float = dock.lab_u
	var k := KEY_K * u
	var t: float = dock._t
	var disabled: bool = sl.id == "" or not dock.sim.abilities_on or dock.sim.over
	var armed: bool = dock.armed == sl.index
	var full: bool = sl.is_ready or sl.fires > 0 or armed
	var cooling: bool = not disabled and not full and sl.cd > 0.0
	var col: Color = SkillDock.SLOT_ACCENT[sl.index]
	var dim := Color(0.62, 0.62, 0.64, 0.9) if disabled else Color.WHITE
	art(sl, "key-shell", Vector2.ZERO, k, dim)
	art(sl, "key-icon-window", Vector2.ZERO, k, dim)
	var wc := KEY_WINDOW_C * k
	var tx := HudSkin.skill_icon(sl.id)
	if tx:
		SkillDock.draw_icon_fit(sl, tx, wc, 22.0 * k, Color(1, 1, 1, 0.45) if disabled or cooling else Color.WHITE)
	if cooling:                                         # the sweep over the part still to charge, clockwise from 12
		var left: float = sl.frac if sl.index != 2 else 1.0 - float(sl.frac)
		_sweep(sl, wc, 19.0 * k, clampf(left, 0.0, 1.0), k)
		var secs := "%d" % int(ceil(sl.cd))
		text_c(sl, secs, wc, int(round(14.0 * u)), LIGHT, bold(), maxi(2, int(3.0 * u)), Color(0, 0, 0, 0.75))
	if disabled:
		_padlock(sl, wc, 8.0 * k)
	var edge := 0.0
	var ecol := HudNoir.accent
	if armed:
		edge = 1.0
		ecol = col
	elif full and not disabled:
		edge = 0.6 + 0.4 * sin(t * 4.0)
	if sl.pulse > 0.0:
		edge = maxf(edge, sl.pulse)
		ecol = ecol.lerp(Color.WHITE, sl.pulse * 0.6)
	if sl.warn > 0.0:
		edge = maxf(edge, sl.warn)
		ecol = HudNoir.ENEMY
	if edge > 0.0:
		art(sl, "key-neon-edge", Vector2.ZERO, k, Color(ecol, edge))
		if armed:
			art(sl, "key-neon-edge", Vector2.ZERO, k, Color(ecol, 0.6))
	var room := 57.0 * k * 0.94
	var lines: Array = dock.name_lines(sl.id, room) if sl.id != "" else ["—"]
	var nm := SkillDock.plate_name(str(lines[0]) if lines.size() == 1 else " ".join(lines))
	var fs := fit_px(nm, 13.0 * u, room, bold(), 10.5 * u)
	text_c(sl, nm, KEY_NAME_C * k, fs, Color(INK, 0.55 if disabled else 1.0), bold())
	if sl.fires > 0:                                    # Overdrive running: relay fires left, on the window
		text_c(sl, "x%d" % sl.fires, wc + Vector2(0, 11.0 * k), int(round(12.5 * u)), LIGHT, bold(), maxi(2, int(3.0 * u)))


static func _sweep(ci: CanvasItem, c: Vector2, r: float, left: float, k: float) -> void:
	## KEY-SWEEP-COOLING shown on the slice of the window still to charge (clockwise from 12 o'clock): the layer drawn through a
	## pie polygon with UVs, so its own paint is kept (no shader).
	var t := tex("key-sweep-cooling")
	if t == null or left <= 0.001:
		return
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(ceil(left * 48.0)))
	var a0 := -PI / 2.0 + TAU * (1.0 - left)
	for i in range(steps + 1):
		var a := a0 + TAU * left * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r * 1.6)
	var uvs := PackedVector2Array()
	var ts := t.get_size() * k / PX                   # the layer's size on screen (it sits at the key's origin)
	for p in pts:
		uvs.append(Vector2(p.x / ts.x, p.y / ts.y))
	ci.draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, t)


static func _padlock(ci: CanvasItem, c: Vector2, r: float) -> void:
	var body := Rect2(c + Vector2(-r * 0.75, -r * 0.1), Vector2(r * 1.5, r * 1.1))
	ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.5, PI, TAU, 16, LIGHT, maxf(1.5, r * 0.22), true)
	ci.draw_rect(body, LIGHT)
	ci.draw_circle(body.get_center(), maxf(1.0, r * 0.14), INK)


# ------------------------------------------------------------------------------------------------ node badges (BadgeLayer)

static func draw_badges(layer, hud) -> void:
	## Every node's badge: PAINT-badge scaled to 28 x 21 pt, the owner's colour on its outline (MASK OWNER-EDGE), no emblem, the
	## count 13 pt bold centred in the dark window (29.5 / 59, 22 / 44), the build timer on the TIMER-STRIP, a tier tag on owned
	## vats / Googatlings. A rival's hidden count (emblem only before) would be an empty box: hidden (README item 4, conservative).
	var paint := tex("paint-badge")
	if paint == null:
		return
	var edge := tex("mask-badge-owner-edge")
	var strip := tex("mask-badge-timer-strip")
	var fnt := bold()
	for id in hud.badges:
		var b: Dictionary = hud.badges[id]
		var p: Control = b["panel"]
		if not p.visible:
			continue
		var lbl: Label = b["label"]
		if not lbl.visible:
			continue
		var r := Rect2(p.position, p.size)
		var owner := str(b["owner"])
		var oc := Rules.seat_color(owner) if owner != "" and owner != "?" else Rules.NEUTRAL
		layer.draw_texture_rect(paint, r, false)
		if owner != "" and owner != "?":                  # vat-neon hotfix 0.24.4: the owner reads at a glance - a soft glow + a bolder outline
			var gl := StyleBoxFlat.new()
			gl.bg_color = Color(oc.r, oc.g, oc.b, 0.0)
			gl.set_corner_radius_all(int(r.size.y * 0.22))
			gl.shadow_color = Color(oc.r, oc.g, oc.b, 0.75)
			gl.shadow_size = maxi(int(r.size.y * 0.30), 3)
			layer.draw_style_box(gl, r)
			var ol := StyleBoxFlat.new()
			ol.bg_color = Color(0, 0, 0, 0)
			ol.border_color = oc
			ol.set_border_width_all(maxi(int(r.size.y * 0.11), 2))
			ol.set_corner_radius_all(int(r.size.y * 0.22))
			layer.draw_style_box(ol, r)
		layer.draw_texture_rect(edge, r, false, oc)
		var bar: ProgressBar = b["build"]
		if bar.visible and strip != null:
			var f := clampf(bar.value / 100.0, 0.0, 1.0)
			var src := Rect2(24, 121, 129 * f, 7)        # TIMER-STRIP box (3x px), filled left to right
			if src.size.x >= 1.0:
				var kk := r.size.x / paint.get_size().x
				layer.draw_texture_rect_region(strip, Rect2(r.position + src.position * kk, src.size * kk), src, Rules.state_color("build"))
		var wc := r.position + Vector2(r.size.x * 29.5 / 59.0, r.size.y * 22.0 / 44.0)
		var fs := fit_px(lbl.text, r.size.y * 13.0 / 21.0, r.size.x * 46.0 / 59.0, fnt)
		text_c(layer, lbl.text, wc, fs, LIGHT, fnt)
	var tag := tex("paint-tier-tag")
	if tag == null:
		return
	for id in hud.badges:                                # tier tags over the top-right corner of owned vats / Googatlings
		var b: Dictionary = hud.badges[id]
		var p: Control = b["panel"]
		if not p.visible or not (b["label"] as Label).visible:
			continue
		var n: Dictionary = hud.sim.nodes[id]
		if str(n["owner"]) == "" or n["relay"] != "" or not (str(n["structure"]) in ["vat", "machinegoon"]):
			continue
		var side := p.size.y * 16.0 / 21.0
		var c := Vector2(p.position.x + p.size.x - side * 0.15, p.position.y - side * 0.2)
		var rr := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
		layer.draw_texture_rect(tag, rr, false)
		text_c(layer, str(int(n["tier"])), c, fit_px("4", side * 0.78, side * 0.7, fnt), LIGHT, fnt)


# ------------------------------------------------------------------------------------------------ the radial (Hud.ActionWedge)

static func draw_slice(w, lit: bool) -> void:
	## A round-29 A5 slice (50 deg for 1-3 actions, 40 for 4-5) on the live ring r 49-119 pt, rotated to the slice's middle,
	## its ACCENT-RIM in the player's colour (SWITCH amber), DIM over it when you cannot do it now; slides 6 pt out on hover / hold.
	var small: bool = (w.a1 - w.a0) < deg_to_rad(45.0)
	var nm := "slice-40" if small else "slice-50"
	var piv := Vector2(2, 45) if small else Vector2(2, 54)
	var u: float = w.r_out / SLICE_R[1]
	var g: float = w.grow
	var sc := u / PX * (0.72 + 0.28 * g)
	var m: float = w.mid()
	var c: Vector2 = w.centre() + Vector2(cos(m), sin(m)) * w.lift * 6.0 * u
	w.draw_set_transform(c, m, Vector2(sc, sc))
	var o := -piv * PX
	w.draw_texture(tex("paint-" + nm), o, Color(1, 1, 1, g))
	w.draw_texture(tex("mask-" + nm + "-accent-rim"), o, Color(w.accent, g * (1.0 if lit else 0.55)))
	if not lit:
		w.draw_texture(tex("mask-" + nm + "-dim"), o, Color(1, 1, 1, g * 0.85))
	w.draw_set_transform(Vector2.ZERO)


static func slice_glyph_at(w) -> Vector2:
	var u: float = w.r_out / SLICE_R[1]
	var m: float = w.mid()
	return w.centre() + Vector2(cos(m), sin(m)) * (84.0 * u + w.lift * 6.0 * u) + Vector2(0, -16.0 * u)


static func draw_slice_words(w, lit: bool, k: float) -> void:
	## Upright in the slice's middle (r 84 pt): the glyph (~22 pt) on the ivory, the name, the price / reason - dark ink #1E3A3F,
	## 13 pt on phones; a price you cannot pay yet in red.
	var u: float = w.r_out / SLICE_R[1]
	var m: float = w.mid()
	var c: Vector2 = w.centre() + Vector2(cos(m), sin(m)) * (84.0 * u + w.lift * 6.0 * u)
	var a := k
	w._ci = w._words
	var gc := c + Vector2(0, -16.0 * u)
	if w.kind != "SWITCH":
		w._icon(gc, 9.0 * u, Color(INK, a * (1.0 if lit else 0.6)))
	else:
		text_c(w._words, w.glyph, gc, int(round(18.0 * u)), Color(INK, a), w.symbol_font)
	var room: float = (w.a1 - w.a0) * 84.0 * u * 0.9
	var name := str(w.title)
	var fnt := bold()
	var floor_px := float(w.floor_px)
	var fs := fit_px(name, maxf(13.0 * u, floor_px), room, fnt, minf(floor_px, 11.0 * u))
	text_c(w._words, name, c + Vector2(0, 2.0 * u), fs, Color(INK, a), fnt)
	var low := str(w.why) if str(w.why) != "" else str(w.cost)
	var pc := INK if lit else WARN_INK
	var fs2 := fit_px(low, maxf(12.5 * u, floor_px), room, UI_FONT, minf(floor_px, 10.5 * u))
	text_c(w._words, low, c + Vector2(0, 16.0 * u), fs2, Color(pc, a * 0.92), UI_FONT)


static func draw_close(hub, accent: Color, u: float) -> void:
	## The radial's centre: PAINT-close (44 pt), its RIM in the node owner's colour, the X drawn by the game.
	var c: Vector2 = hub.size / 2.0
	var s: float = CLOSE_PT * u * (0.6 + 0.4 * hub.grow)
	var r := Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))
	hub.draw_texture_rect(tex("paint-close"), r, false)
	hub.draw_texture_rect(tex("mask-close-rim"), r, false, accent)
	var x := 5.0 * u
	var hot: bool = hub.is_hovered() or hub.button_pressed
	var col := INK if not hot else INK.lightened(0.25)
	hub.draw_line(c + Vector2(-x, -x), c + Vector2(x, x), col, 2.4 * u, true)
	hub.draw_line(c + Vector2(-x, x), c + Vector2(x, -x), col, 2.4 * u, true)


# ------------------------------------------------------------------------------------------------ node card (inspector)

static func draw_card(hud, ci: Control) -> void:
	## PAINT-card (196 x 66 pt, no emblem socket): the owner's colour on its edge, the first line "WHO · STRUCTURE", the units, the
	## status line (the card's existing words), the units bar on BAR-TRACK / BAR-FILL.
	if hud.inspector_id < 0:
		return
	var n: Dictionary = hud.sim.nodes[hud.inspector_id]
	var u: float = ci.size.x / CARD_PT.x
	var r := Rect2(Vector2.ZERO, ci.size)
	ci.draw_texture_rect(tex("paint-card"), r, false)
	ci.draw_texture_rect(tex("mask-card-owner-edge"), r, false, hud.inspector_col)
	var cap := maxf(float(hud.sim.node_cap(n)), 1.0)
	var units: float = hud.sim.garrison_total(n) if hud.sim.allied_units(n) > 0.0001 else float(n["units"])
	var f := clampf(units / cap, 0.0, 1.0)
	var k := u
	art(ci, "mask-card-bar-track", Vector2.ZERO, k)
	if f > 0.0:
		art_part(ci, "mask-card-bar-fill", Vector2.ZERO, k, Rect2(24, 159, 540.0 * f, 24), hud.inspector_col)
	var who := str(hud.inspector_who.text).strip_edges()
	var first := str(hud.inspector_first.text).strip_edges()
	var head := who.trim_suffix("·").strip_edges() + (" · " if who != "" and first != "" else "") + first.trim_prefix("·").strip_edges()
	if int(n["tier"]) > 0 and n["relay"] == "" and not ("T%d" % int(n["tier"])) in head:
		head += " T%d" % int(n["tier"])
	var fnt := bold()
	var fl: float = float(hud.card_px(13))
	text_l(ci, head, Vector2(8.0, 14.0) * u, fit_px(head, maxf(16.0 * u, fl), 180.0 * u, fnt, fl), INK, fnt)
	var l2 := "%d / %d units" % [Rules.shown(units), Rules.shown(cap)]
	text_l(ci, l2, Vector2(8.0, 30.0) * u, fit_px(l2, maxf(13.0 * u, fl), 180.0 * u, UI_FONT, fl), INK, UI_FONT)
	var l3 := str(hud.inspector_label.text).replace("\n", " · ")
	if l3 != "":
		text_l(ci, l3, Vector2(8.0, 44.0) * u, fit_px(l3, maxf(13.0 * u, fl), 180.0 * u, UI_FONT, fl), Color(INK, 0.85), UI_FONT)


# ------------------------------------------------------------------------------------------------ toast / banner

static func hslice(ci: CanvasItem, t: Texture2D, r: Rect2, cap_px: float, col := Color.WHITE) -> void:
	## A piece stretched to r's width with its rounded ends kept (3-slice across; the height scales evenly).
	if t == null:
		return
	var ts := t.get_size()
	var cap := minf(cap_px * r.size.y / ts.y, r.size.x / 2.0)
	ci.draw_texture_rect_region(t, Rect2(r.position, Vector2(cap, r.size.y)), Rect2(0, 0, cap_px, ts.y), col)
	ci.draw_texture_rect_region(t, Rect2(r.position + Vector2(cap, 0), Vector2(r.size.x - 2.0 * cap, r.size.y)),
			Rect2(cap_px, 0, ts.x - 2.0 * cap_px, ts.y), col)
	ci.draw_texture_rect_region(t, Rect2(r.end.x - cap, r.position.y, cap, r.size.y), Rect2(ts.x - cap_px, 0, cap_px, ts.y), col)


static func draw_toast(ci: CanvasItem, box: Rect2, kind_col: Color, a: float, u: float) -> Rect2:
	## PAINT-toast behind a line, as wide as its words (ends kept), the KIND-BAR in the line's kind colour; the text then draws in
	## dark ink. Returns the toast's rect.
	var h := TOAST_PT.y * u
	var w := maxf(box.size.x + 30.0 * u, 120.0 * u)
	var r := Rect2(Vector2(box.get_center().x - w / 2.0 - 5.0 * u, box.get_center().y - h / 2.0), Vector2(w, h))
	hslice(ci, tex("paint-toast"), r, 12.0 * PX, Color(1, 1, 1, a))
	var bar := tex("mask-toast-kind-bar")
	if bar != null:
		ci.draw_texture_rect_region(bar, Rect2(r.position + Vector2(4, 2) * u, Vector2(4, 26) * u), Rect2(12, 6, 12, 78), Color(kind_col, a))
	return r


static func draw_banner(ci: Control, kind_col: Color) -> void:
	## PAINT-banner behind the banner's words (ends kept, 54 pt tall), its KIND-EDGE in the banner's kind colour.
	var r := Rect2(Vector2.ZERO, ci.size)
	hslice(ci, tex("paint-banner"), r, 14.0 * PX)
	hslice(ci, tex("mask-banner-kind-edge"), r, 14.0 * PX, kind_col)


# ------------------------------------------------------------------------------------------------ music / pause

static func button_face(b: Button, glyph: String, u: float, off := false) -> void:
	## BUTTON-SHELL (32 pt) centred in its 40 pt tap, the glyph in dark ink; music off = the glyph faded and struck through.
	var c := b.size / 2.0
	var s := BUTTON_PT * u
	var r := Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))
	var pressed := b.button_pressed or b.is_hovered()
	b.draw_texture_rect(tex("button-shell"), r, false, Color(0.92, 0.92, 0.92) if pressed else Color.WHITE)
	b.draw_texture_rect(tex(glyph), r, false, Color(INK, 0.4 if off else 1.0))
	if off:
		b.draw_line(r.position + r.size * 0.28, r.position + r.size * 0.72, INK, 2.0 * u, true)

# ---- round 37B2 (hud-37): the HUD leftovers pack, 4x exports in assets/ui/lab37 (DIRECTOR-PACKAGE/deliveries/37-hud-leftovers-B2).
# Neon masks take the SEAT colour, goo the faction colour (Daniele's colour rule, 2026-11-15).
const DIR37 := "res://assets/ui/lab37/"
const PX37 := 4.0                               # art px per pt in that pack
const CUE_PT := Vector2(26, 22)                 # P1 / P1R canvas (pt)
static var _tex37 := {}


static func tex37(n: String) -> Texture2D:
	if not _tex37.has(n):
		var p := DIR37 + n + ".png"
		_tex37[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex37[n]


static func cue_ready() -> bool:
	return tex37("PAINT-P1") != null and tex37("PAINT-P1R") != null


static func draw_cue(ci: CanvasItem, relay: bool, centre: Vector2, pt: float, seat: Color, glow: float, alpha := 1.0) -> void:
	## P1 (upgrade ready: chevron tag) / P1R (relay ready to fire: lozenge): an indicator, never a touch target.
	## Paint, the owner edge in the seat colour, the READY layer pulsing with `glow` 0..1.
	var id := "P1R" if relay else "P1"
	var r := Rect2(centre - CUE_PT * pt * 0.5, CUE_PT * pt)
	var base := tex37("PAINT-" + id)
	if base == null:
		return
	ci.draw_texture_rect(base, r, false, Color(1, 1, 1, alpha))
	var edge := tex37("MASK-%s-OWNER-EDGE" % id)
	if edge != null:
		ci.draw_texture_rect(edge, r, false, Color(seat.r, seat.g, seat.b, alpha))
	var rd := tex37("MASK-%s-READY" % id)
	if rd != null and glow > 0.0:
		ci.draw_texture_rect(rd, r, false, Color(seat.r, seat.g, seat.b, glow * alpha))
