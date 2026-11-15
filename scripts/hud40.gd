class_name Hud40
extends RefCounted
## hud-40b6 (2026-11-15, Daniele: "ship now use 40B6 but keep the skill buttons looking like in 40B5"): the match HUD from the
## round-40 hybrid-chamfer pack (DIRECTOR-PACKAGE/deliveries/40-ui-hybrid-chamfer-B4 base + B5 pipes + B6 rack / connectors;
## skill keys = B5 = B4). Cut at 2x into assets/ui/hud40 by tools/hud40_cut.py. Every piece sits at its registered pt place in the
## pack's 812 x 375 frame: the vat group from the safe left, the score top centre, the top keys + rack + skill keys from the safe
## right. Goo = faction colour (pipes recoloured from the painted NULL goo by shaders/hud_pipe_tint.gdshader, the vat / score
## through hud_goo); neon = seat colour (key rims, score caps). The controls, readouts and taps stay the lab HUD's (HudLab, SendTank,
## SkillDock, Hud); only their faces and places change. Off: --hud-lab29 (the round-29/30 lab HUD) or no hud40 art.

const DIR := "res://assets/ui/hud40/"
const PX := 2.0                                  # art px per pt (the 2x cuts)
const PIPE := preload("res://shaders/hud_pipe_tint.gdshader")
const W := 812.0                                 # the pack's frame (pt)
const H := 375.0
const VAT_AT := Vector2(10.5, 66.5)              # vat canvas origin (66 x 244 pt)
const VAT_PT := Vector2(66, 244)
const VAT_GOO := Rect2(6, 30, 53, 199)           # MASK-VAT-GOO's alpha box in the vat canvas (pt): 0 % at its bottom
const VAT_PIPES := [Vector2(-9, 91.5), Vector2(-9, 286.5)]   # B5 feeds (screen pt), 26.5 x 15, joint on the right
const TICKS := {0.75: 71.75, 0.5: 122.0, 0.25: 172.25}       # PAINT-VAT-TICK-* origins (vat-canvas pt y; x 27)
const SCORE_AT := Vector2(270, 0)                # score canvas (274 x 40 pt)
const SCORE_PT := Vector2(274, 40)
const SCORE_GOO_U := Vector2(97.0 / 548.0, 451.0 / 548.0)
const TIMER_AT := Vector2(104, 8)                # PAINT-SCORE-TIMER (66 x 27), digits Russo One 14 pt #14262B
const TIMER_INK := Color("14262b")
const CAPS_2 := [Vector2(34, 21.5), Vector2(240, 21.5)]
const CAPS_4 := [Vector2(31.5, 21.5), Vector2(73.5, 21.5), Vector2(200.5, 21.5), Vector2(242.5, 21.5)]
const KEYS := [Rect2(734, 90.5, 77, 68.5), Rect2(737, 161, 72, 66), Rect2(736.5, 231, 73, 65.5)]
const KEY_ART := ["GEO-SKILL-KEY", "GEO-SKILL-KEY-2", "GEO-SKILL-KEY-3"]
const KEY_ICON := [Vector2(14.5, 6.5), Vector2(12.0, 6.5), Vector2(12.5, 6.5)]   # icon sockets 48 x 40 pt
const KEY_LABEL := [Rect2(4, 51.0, 69, 12.5), Rect2(4, 48.5, 64, 12.5), Rect2(4, 48.0, 65, 12.5)]
const SLOT_PT := Vector2(77, 68.5)               # every slot control: the union of the three keys
const SLOT_GAP := 1.75                           # slot pitch 70.25 pt (keys at 90.5 / 161 / 231)
const TOPKEY_HIT := 33.0
const TOPKEYS := {"CHAT": Vector2(646.25, 9.5), "DEBUG": Vector2(680.25, 9.5), "MUTE": Vector2(714.25, 9.5), "PAUSE": Vector2(748.25, 7.5)}
const TOPKEY_ART := {"CHAT": Vector2(647.5, 11), "DEBUG": Vector2(681.5, 11), "MUTE": Vector2(715.5, 11), "PAUSE": Vector2(749.5, 9)}
const BRACKET_AT := Vector2(639, 5)              # PAINT-TOPKEY-BRACKET 149.5 x 42 (fixed corners, the middle stretches)

static var _tex := {}


static func on() -> bool:
	if not HudLab.on() or "--hud-lab29" in OS.get_cmdline_user_args():
		return false
	return tex("PAINT-VAT-FRAME") != null


static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DIR + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]


static func art(ci: CanvasItem, n: String, pos: Vector2, u: float, col := Color.WHITE) -> void:
	## Draw a 2x cut at pos (px), u = screen px per pt.
	var t := tex(n)
	if t != null:
		ci.draw_texture_rect(t, Rect2(pos, t.get_size() * u / PX), false, col)


static func run3(ci: CanvasItem, n: String, dest: Rect2, l_pt: float, r_pt: float, u: float) -> void:
	## A 3-slice horizontal pipe: l_pt / r_pt fixed ends (pt), the middle stretched over dest.
	var t := tex(n)
	if t == null or dest.size.x <= 0.0:
		return
	var sz := t.get_size()
	var l := l_pt * PX
	var r := r_pt * PX
	var mid_w := maxf(dest.size.x - (l_pt + r_pt) * u, 0.0)
	ci.draw_texture_rect_region(t, Rect2(dest.position, Vector2(l_pt * u, dest.size.y)), Rect2(0, 0, l, sz.y))
	ci.draw_texture_rect_region(t, Rect2(dest.position + Vector2(l_pt * u, 0), Vector2(mid_w, dest.size.y)), Rect2(l, 0, sz.x - l - r, sz.y))
	ci.draw_texture_rect_region(t, Rect2(dest.position + Vector2(l_pt * u + mid_w, 0), Vector2(r_pt * u, dest.size.y)), Rect2(sz.x - r, 0, r, sz.y))


static func goo_of(seat: String, human: String) -> Color:
	## Goo = the seat's FACTION colour (Daniele's colour rule); yours = your vat's goo.
	if seat == human:
		return GooTone.mine(HudNoir.accent)
	return GooTone.liquid(seat, Rules.seat_color(seat))


class PipeLayer:
	## Draws through hud_pipe_tint: the painted NULL goo of the B5 / B6 pipes becomes `goo`; housings, collars, glass stay.
	extends Control
	var painter: Callable

	func _init(p: Callable) -> void:
		painter = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var m := ShaderMaterial.new()
		m.shader = Hud40.PIPE
		material = m

	func set_goo(c: Color) -> void:
		## c = a goo tint as hud_goo takes it; the pipe core shows it lit like the vat's goo (x 1.24)
		(material as ShaderMaterial).set_shader_parameter("goo", Color(minf(c.r * 1.24, 1.0), minf(c.g * 1.24, 1.0), minf(c.b * 1.24, 1.0)))

	func _draw() -> void:
		painter.call(self)


# ------------------------------------------------------------------------------------------- the right group (top keys + rack)

class Rack:
	## Full-screen layer behind the keys: the rack pipe (B6 shaft, elbow, top run to the right edge, sage T, three skill feeds
	## with their fittings), the B5 bracket branch, and the top-key bracket sized to the keys that show.
	extends Control
	var hud
	var u := 1.0
	var right := 0.0                             # px x of the pack's x = 812 (the safe right)
	var top := 0.0
	var keys := 4
	var show_rack := true
	var pipes: Hud40.PipeLayer

	func setup(h) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		pipes = Hud40.PipeLayer.new(_draw_pipes)
		pipes.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(pipes)

	func at(p: Vector2) -> Vector2:
		return Vector2(right - (Hud40.W - p.x) * u, top + p.y * u)

	func _draw_pipes(ci: Control) -> void:
		var vp := ci.get_viewport_rect().size
		if show_rack:
			Hud40.art(ci, "PAINT-RACK-MAIN-SHAFT", at(Vector2(706.2, 87.5)), u)
			var ex := at(Vector2(725.7, 68.2))           # the top run: the B6 straight section on to the physical right edge
			var t := Hud40.tex("PAINT-RACK-TOP-EXTENSION")
			if t != null:
				ci.draw_texture_rect_region(t, Rect2(ex, Vector2(maxf(vp.x - ex.x + 2.0, 16.0 * u), 15.0 * u)),
						Rect2(4, 0, t.get_size().x - 8, t.get_size().y))
			Hud40.art(ci, "PAINT-RACK-TOP-ELBOW", at(Vector2(705.7, 67.7)), u)
			var bt := Hud40.tex("PAINT-BRACKET-PIPE")     # B5 branch up to the bracket, visible y 47..69
			if bt != null:
				var y0 := 47.0 - 28.5
				ci.draw_texture_rect_region(bt, Rect2(at(Vector2(765.5, 47)), Vector2(15.0, 22.0) * u),
						Rect2(0, y0 * Hud40.PX, bt.get_size().x, 22.0 * Hud40.PX))
			Hud40.art(ci, "PAINT-CONNECTOR-SAGE-T", at(Vector2(766.375, 65.325)), u)
			var br := [[117.25, 23.3], [186.5, 26.3], [256.25, 25.8]]
			for i in range(3):
				Hud40.run3(ci, "PAINT-SKILL-FEED", Rect2(at(Vector2(713.7, br[i][0])), Vector2(br[i][1], 15.0) * u), 2.0, 10.0, u)
			for y in [118.125, 187.375, 257.125]:
				Hud40.art(ci, "PAINT-CONNECTOR-SKILL-T", at(Vector2(707.075, y)), u)
		# the bracket: fixed 12 pt ends, the middle sized to the keys that show (right-aligned, 34 pt per key)
		var w := 149.5 - 34.0 * float(4 - keys)
		var x0 := Hud40.BRACKET_AT.x + 149.5 - w
		Hud40.run3(ci, "PAINT-TOPKEY-BRACKET", Rect2(at(Vector2(x0, Hud40.BRACKET_AT.y)), Vector2(w, 42.0) * u), 12.0, 12.0, u)

	func refresh(goo: Color) -> void:
		pipes.set_goo(goo)
		pipes.queue_redraw()


static func topkey_face(b: Button, name: String, u: float, off := false) -> void:
	## A top key: its 40B4 face (30.5 x 30 pt) in its 33 pt tap; MUTE off = faded + struck, a pressed key dims a little.
	var art_at: Vector2 = TOPKEY_ART[name] - TOPKEYS[name]
	var pressed := b.button_pressed or b.is_hovered()
	art(b, "KEY-" + name, art_at * u, u, Color(0.9, 0.9, 0.9) if pressed else Color(1, 1, 1, 0.55 if off else 1.0))
	if off:
		var c := (art_at + Vector2(15.25, 15)) * u
		b.draw_line(c - Vector2(8, 8) * u, c + Vector2(8, 8) * u, HudLab.INK, 2.0 * u, true)


# ------------------------------------------------------------------------------------------------ the skill keys

static func draw_key(sl) -> void:
	## One skill key on the B5 (= B4) art: GEO-SKILL-KEY[-2|-3], the skill icon in its well, the name in the label box;
	## READY = the seat rim breathing in your seat colour, ARMED = solid in the slot colour, COOLING = the sweep + seconds,
	## LOCKED = dimmed (MASK DIM) with a padlock; a refused tap flashes the rim red.
	var dock = sl.dock
	var u: float = dock.lab_u
	var i: int = clampi(sl.index, 0, 2)
	var off: Vector2 = (KEYS[i].position - KEYS[0].position - Vector2(0, (SLOT_PT.y + SLOT_GAP) * i)) * u
	var t: float = dock._t
	var disabled: bool = sl.id == "" or not dock.sim.abilities_on or dock.sim.over
	var armed: bool = dock.armed == sl.index
	var full: bool = sl.is_ready or sl.fires > 0 or armed
	var cooling: bool = not disabled and not full and sl.cd > 0.0
	var col: Color = SkillDock.SLOT_ACCENT[sl.index]
	var n: String = KEY_ART[i]
	art(sl, n, off, u)
	var wc: Vector2 = off + (KEY_ICON[i] + Vector2(24, 20)) * u
	var tx := HudSkin.skill_icon(sl.id)
	if tx:
		SkillDock.draw_icon_fit(sl, tx, wc, 26.0 * u, Color(1, 1, 1, 0.45) if disabled or cooling else Color.WHITE)
	if cooling:
		var left: float = sl.frac if sl.index != 2 else 1.0 - float(sl.frac)
		_sweep(sl, wc, 19.0 * u, clampf(left, 0.0, 1.0))
		HudLab.text_c(sl, "%d" % int(ceil(sl.cd)), wc, int(round(16.0 * u)), HudLab.LIGHT, HudLab.bold(), maxi(2, int(3.0 * u)), Color(0, 0, 0, 0.75))
	if disabled:
		art(sl, n.replace("GEO-", "MASK-") + "-DIM", off, u, Color(0, 0, 0, 0.35))
		HudLab._padlock(sl, wc, 9.0 * u)
	var seat: Color = Rules.seat_color(str(dock.human))   # neon = SEAT colour (colour rule)
	var edge := 1.0                                   # the fine seat neon is always on (the B5 key's line, designer 10); READY glows over it
	var ecol := seat
	if armed:
		edge = 1.0
		ecol = col
	elif disabled:
		edge = 0.5
	if sl.pulse > 0.0:
		edge = maxf(edge, sl.pulse)
		ecol = ecol.lerp(Color.WHITE, sl.pulse * 0.6)
	if sl.warn > 0.0:
		edge = maxf(edge, sl.warn)
		ecol = HudNoir.ENEMY
	var rim := n.replace("GEO-", "MASK-") + "-SEAT-RIM"
	art(sl, rim, off, u, Color(ecol, edge))
	art(sl, rim, off, u, Color(ecol, edge * 0.8))       # twice: the thin line reads at phone size
	if armed:
		art(sl, rim, off, u, Color(ecol, 0.7))
	elif full and not disabled:                        # READY: a breathing glow on top of the line
		art(sl, rim, off - Vector2(0.5, 0.5) * u, u * 1.0, Color(ecol.lightened(0.3), 0.25 + 0.3 * sin(t * 4.0)))
	var lb: Rect2 = KEY_LABEL[i]
	var room := lb.size.x * u
	var lines: Array = dock.name_lines(sl.id, room) if sl.id != "" else ["—"]
	var nm := SkillDock.plate_name(str(lines[0]) if lines.size() == 1 else " ".join(lines))
	var fs := HudLab.fit_px(nm, 13.0 * u, room, HudLab.bold(), 10.5 * u)
	HudLab.text_c(sl, nm, off + lb.get_center() * u, fs, Color(HudLab.INK, 0.55 if disabled else 1.0), HudLab.bold())
	if sl.fires > 0:
		HudLab.text_c(sl, "x%d" % sl.fires, wc + Vector2(0, 12.0 * u), int(round(12.5 * u)), HudLab.LIGHT, HudLab.bold(), maxi(2, int(3.0 * u)))


static func _sweep(ci: CanvasItem, c: Vector2, r: float, left: float) -> void:
	## The part of the well still to charge, clockwise from 12: a dark translucent pie.
	if left <= 0.001:
		return
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(ceil(left * 48.0)))
	var a0 := -PI / 2.0 + TAU * (1.0 - left)
	for i in range(steps + 1):
		var a := a0 + TAU * left * float(i) / float(steps)
		pts.append(c + Vector2(cos(a) * 1.2, sin(a)) * r)
	ci.draw_colored_polygon(pts, Color(0.02, 0.06, 0.08, 0.55))
