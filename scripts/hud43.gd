class_name Hud43
extends RefCounted
## hud-43 (2026-11-18, Daniele's SCREEN LAYOUT + the 43-interface-direction-HUD-recreated / score-hud-2p-4p(-goo) packs, designer 10:
## rail 104 -> 84 pt, comms dropped, score fitted to its 270 x 37 pt zone, the goo pack's material). The HUD in his zones round THE
## PIT (main.pit_rect, same unit): SEND = left column, SKILLS = right column (84 pt), SCORE = top centre, the two AI SCREENS in the top
## corners (tilted -12 / +12 deg; AI moods live there), SOUND / PAUSE / CHAT top right, MAP NAME bottom left, VERSION bottom right.
## Controls, readouts and taps stay Hud40's / the lab HUD's (SendTank, SkillDock, Hud): only faces and places change.
## Goo = faction colour (rail / cable / score goo), neon = seat colour (key rims, sockets). Off: no hud43 art (then Hud40). Dev --hud-40b6 deleted 2026-11-23, back from tag archive-2026-11-23.

const DIR := "res://assets/ui/hud43/"
const SCORE_SHADER := preload("res://assets/ui/hud43/score_share.gdshader")
# zones in Fold-front pt (SCREEN-LAYOUT-SPEC section 1; safe area 806 x 360)
const COL_H := 239.0
const SEND_W := 85.0
const SKILL_W := 84.0
const SCORE_PT := Vector2(270, 37)
const AI_PT := Vector2(133, 79)
const AI_X := 92.0                               # left AI zone starts 92 pt from the safe left (11.4 %), the right one mirrored
const AI_Y := 3.0
const UTIL_PT := Vector2(82, 27)
const UTIL_Y := 11.0
const FOOT_H := 13.5
const FOOT_IN := 8.0                             # map name / version: 8 pt in from the safe edge (designer 10, 11-18)
const FOOT_Y := 9.5                              # map name / version: their bottom 9.5 pt over the screen bottom
# the vat (43 vat_sender_housing, 187 x 572 ref) fitted to the column height
const VAT_PT := Vector2(78, 239)
const VAT_GOO := Rect2(0.123 * 78.0, 0.171 * 239.0, 0.754 * 78.0, 0.677 * 239.0)
const VAT_TICKS := {0.75: 0.330, 0.5: 0.493, 0.25: 0.656}   # tick centres (fraction of the vat height)
# the skill keys (43 skill_key, 182 x 158 ref) in the 84 pt rail: 66 x 58 pt, pitch 72
const SLOT_PT := Vector2(66, 58)
const SLOT_GAP := 14.0
const KEY_X := 15.0                              # key left edge in the rail (the goo pipe runs left of it)
const KEY_TOP := 21.0
const KEY_WELL := Vector2(0.5, 0.443)            # cooldown / icon centre (fraction of the key)
const KEY_LABEL := Vector2(0.5, 0.835)
const INK := Color("30202a")

static var _tex := {}


static func on() -> bool:
	if not Hud40.on():
		return false
	return tex("skill_rail") != null


static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DIR + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]


static func unit(vp: Vector2) -> float:
	## Screen px per zone pt: THE PIT's unit (main.pit_rect), so the zones and the pit always meet.
	return UiKit.hud_k(vp) / UiKit.hud_k_for(360.0) / maxf(UiKit.pt_per_px(vp), 0.01)


static func zones(vp: Vector2) -> Dictionary:
	## Every zone in screen px.
	var z := unit(vp)
	var ins := UiKit.safe_insets(vp)
	var l := ins.x
	var r := vp.x - ins.z
	var cy := vp.y / 2.0
	var d := {}
	d["send"] = Rect2(l, cy - COL_H * z / 2.0, SEND_W * z, COL_H * z)
	d["skill"] = Rect2(r - SKILL_W * z, cy - COL_H * z / 2.0, SKILL_W * z, COL_H * z)
	# the TOP BAR is centred on the physical SCREEN (Daniele 2026-11-27 "Centre on screen"): with per-side insets the safe area
	# between the columns is off-centre, the score and the two AI screens are not - they mirror round vp.x / 2, each AI screen
	# AI_X in from the wider of the two side insets (clear of the cut-out in both rotations)
	var cx := vp.x / 2.0
	var e := maxf(l, vp.x - r)
	d["score"] = Rect2(cx - SCORE_PT.x * z / 2.0, 0.0, SCORE_PT.x * z, SCORE_PT.y * z)
	# the AI screens end at THE PIT's top edge (+2 pt): his frame dips them 5 % into the pit's round corners, but the G maps put
	# platforms there (zone sweep 11-18: G-01 / G-06 / G-10 / G-18), so they stay on the crust
	var ah := minf(AI_PT.y, 66.0 + 2.0 - AI_Y)                 # (pit top = 66 pt in this unit, main.pit_rect)
	d["ai_l"] = Rect2(e + AI_X * z, AI_Y * z, AI_PT.x * z, ah * z)
	d["ai_r"] = Rect2(vp.x - e - (AI_X + AI_PT.x) * z, AI_Y * z, AI_PT.x * z, ah * z)
	d["util"] = Rect2(r - UTIL_PT.x * z, UTIL_Y * z, UTIL_PT.x * z, UTIL_PT.y * z)
	d["name"] = Rect2(l + 1.0 * z, vp.y - (FOOT_Y + FOOT_H) * z, 111.0 * z, FOOT_H * z)
	d["ver"] = Rect2(r - 112.0 * z, vp.y - (FOOT_Y + FOOT_H) * z, 112.0 * z, FOOT_H * z)
	return d


static func score_goo(f: String) -> Color:
	## The score strip's goo: the faction's own saturated goo colour (designer 10: the dulled Hud40.goo_of read muddy),
	## the pack's material multiplies it (score_share.gdshader goo_n are source_color = sRGB).
	return UiKit.accent(f)


static func goo_tint(c: Color) -> Color:
	## A faction colour as the white goo layers' modulate (a touch brighter so the white highlights stay).
	return c.lightened(0.08)


# ------------------------------------------------------------------------------------------------ the skill rail + keys

static func draw_rail(ci: CanvasItem, r: Rect2, goo: Color) -> void:
	var b := tex("skill_rail")
	var g := tex("skill_rail_goo")
	if b:
		ci.draw_texture_rect(b, r, false)
	if g:
		ci.draw_texture_rect(g, r, false, goo_tint(goo))


static func draw_key(sl) -> void:
	## One skill key on the 43 key: plate, the icon in its well, the name on the cream label; READY = the seat rim breathing,
	## ARMED = solid in the slot colour, COOLING = the sweep + seconds, LOCKED = dimmed + padlock; a refused tap flashes red.
	var dock = sl.dock
	var u: float = dock.lab_u
	var t: float = dock._t
	var kr := Rect2(Vector2.ZERO, SLOT_PT * u)
	var disabled: bool = sl.id == "" or not dock.sim.abilities_on or dock.sim.over
	var armed: bool = dock.armed == sl.index
	var full: bool = sl.is_ready or sl.fires > 0 or armed
	var cooling: bool = not disabled and not full and sl.cd > 0.0
	var col: Color = SkillDock.SLOT_ACCENT[sl.index]
	var base := tex("skill_key_cyan")
	if base:
		sl.draw_texture_rect(base, kr, false, Color(0.62, 0.6, 0.62) if disabled else Color.WHITE)
	var wc := kr.size * KEY_WELL
	var tx := HudSkin.skill_icon(sl.id)
	if tx:
		SkillDock.draw_icon_fit(sl, tx, wc, 21.0 * u, Color(1, 1, 1, 0.45) if disabled or cooling else Color.WHITE)
	if cooling:
		var left: float = sl.frac if sl.index != 2 else 1.0 - float(sl.frac)
		Hud40._sweep(sl, wc, 16.0 * u, clampf(left, 0.0, 1.0))
		HudLab.text_c(sl, "%d" % int(ceil(sl.cd)), wc, int(round(15.0 * u)), HudLab.LIGHT, HudLab.bold(), maxi(2, int(3.0 * u)), Color(0, 0, 0, 0.75))
	if disabled:
		HudLab._padlock(sl, wc, 8.0 * u)
	var seat: Color = Rules.seat_color(str(dock.human))   # neon = SEAT colour
	var edge := 0.85
	var ecol := seat
	if armed:
		edge = 1.0
		ecol = col
	elif disabled:
		edge = 0.4
	if sl.pulse > 0.0:
		edge = maxf(edge, sl.pulse)
		ecol = ecol.lerp(Color.WHITE, sl.pulse * 0.6)
	if sl.warn > 0.0:
		edge = maxf(edge, sl.warn)
		ecol = HudNoir.ENEMY
	var rim := tex("skill_key_rim_mask")
	if rim:
		sl.draw_texture_rect(rim, kr, false, Color(ecol, edge))
		if armed:
			sl.draw_texture_rect(rim, kr.grow(1.0 * u), false, Color(ecol, 0.7))
		elif full and not disabled:
			sl.draw_texture_rect(rim, kr.grow(0.8 * u), false, Color(ecol.lightened(0.3), 0.25 + 0.3 * sin(t * 4.0)))
	var room := kr.size.x * 0.78
	var lines: Array = dock.name_lines(sl.id, room) if sl.id != "" else ["—"]
	var nm := SkillDock.plate_name(str(lines[0]) if lines.size() == 1 else " ".join(lines))
	var fs := HudLab.fit_px(nm, 11.5 * u, room, HudLab.bold(), 9.0 * u)
	HudLab.text_c(sl, nm, kr.size * KEY_LABEL, fs, Color(INK, 0.55 if disabled else 1.0), HudLab.bold())
	if sl.fires > 0:
		HudLab.text_c(sl, "x%d" % sl.fires, wc + Vector2(0, 11.0 * u), int(round(12.0 * u)), HudLab.LIGHT, HudLab.bold(), maxi(2, int(3.0 * u)))


static func topkey_face(b: Button, name: String, u: float, off := false) -> void:
	## A utility key: the cream 43 key (27 pt) centred in its tap, its glyph (sound / muted / pause) or a short word.
	var s := UTIL_PT.y * u
	var r := Rect2((b.size - Vector2(s, s)) / 2.0, Vector2(s, s))
	var pressed := b.button_pressed or b.is_hovered()
	var k := tex("utility_key")
	if k:
		b.draw_texture_rect(k, r, false, Color(0.88, 0.86, 0.86) if pressed else Color.WHITE)
	var g: Texture2D = null
	match name:
		"PAUSE": g = tex("pause_icon")
		"MUTE": g = tex("audio_muted_icon") if off else tex("audio_on_icon")
	if g:
		var gs := Vector2(g.get_size().x / g.get_size().y, 1.0) * s * 0.5
		b.draw_texture_rect(g, Rect2(r.get_center() - gs / 2.0, gs), false, INK)
	else:
		HudLab.text_c(b, "CHAT" if name == "CHAT" else "DBG", r.get_center(), int(round(8.0 * u)), INK, HudLab.bold())


# ------------------------------------------------------------------------------------------------ the score (2p / 4p)

class Score extends Control:
	## The 43 score housing (2p or 4p) in its 270 x 37 pt zone (fitted evenly: 246 x 37), ONE goo strip through score_share
	## (each seat's FACTION colour over its share of the units on the map, Sim.seat_strength), the timer on the cream plate, and
	## each seat's AI in its socket (Daniele 11-16 note 15: "the AIs don't appear") with a seat-colour neon ring; out = dimmed.
	var hud
	var players: Array = []
	var goo: Control
	var u := 1.0
	var _acc := 0.0
	const REF := Vector2(639, 96)                  # the score box (ref px)
	const LANE := Rect2(102, 40, 435, 42)
	const PLATE := Rect2(242, 7, 155, 30)
	const TIMER := Vector2(319.5, 22)
	const SOCK := {2: [[51, 48, 33], [588, 48, 33]], 4: [[28, 48, 19], [75, 48, 19], [564, 48, 19], [611, 48, 19]]}

	func setup(h) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		for g in hud._seat_groups():
			for s in g:
				players.append(str(s))
		if "--h40-4p" in OS.get_cmdline_user_args() and players.size() == 2:
			players = [players[0], "C", "D", players[1]]
		goo = Control.new()
		goo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = Hud43.SCORE_SHADER
		m.set_shader_parameter("chamber_sheen", Hud43.tex("score_goo_sheen"))
		goo.material = m
		goo.draw.connect(func():
			var t := Hud43.tex("score_goo_material")
			if t:
				goo.draw_texture_rect(t, Rect2(Vector2.ZERO, goo.size), false))
		add_child(goo)
		var over := Control.new()
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		over.set_anchors_preset(Control.PRESET_FULL_RECT)
		over.draw.connect(_draw_over.bind(over))
		add_child(over)
		set_meta("over", over)

	func four() -> bool:
		return players.size() > 2

	func k() -> float:
		return size.x / REF.x

	func lay(zone: Rect2) -> void:
		var s := minf(zone.size.x / REF.x, zone.size.y / REF.y)
		size = REF * s
		position = Vector2(zone.get_center().x - size.x / 2.0, zone.position.y)
		goo.position = LANE.position * s
		goo.size = LANE.size * s
		queue_redraw()

	func _process(dt: float) -> void:
		_acc += dt
		if _acc < 0.1:
			return
		_acc = 0.0
		sync()

	func sync() -> void:
		var vals: Array = []
		var tot := 0.0
		for s in players:
			var v := 0.0
			if hud.sim.factions.has(s) and not hud._seat_out(s):
				v = maxf(float(hud.sim.seat_strength(s)), 0.0)
			vals.append(v)
			tot += v
		var ends := [1.0, 1.0, 1.0, 1.0]
		var acc := 0.0
		var n := mini(players.size(), 4)
		for i in range(n):
			acc += (float(vals[i]) / tot) if tot > 0.0 else 1.0 / float(n)
			ends[i] = acc if i < n - 1 else 1.0
		var m := goo.material as ShaderMaterial
		m.set_shader_parameter("ends", Vector4(ends[0], ends[1], ends[2], ends[3]))
		for i in range(4):
			var seat: String = players[mini(i, n - 1)]
			m.set_shader_parameter("goo_%d" % (i + 1), Hud43.score_goo(str(hud.sim.factions.get(seat, "vex"))))
		(get_meta("over") as Control).queue_redraw()

	func _draw() -> void:
		var h := Hud43.tex("score_housing_4p" if four() else "score_housing_2p")
		if h:
			draw_texture_rect(h, Rect2(Vector2.ZERO, size), false)

	func _draw_over(ci: Control) -> void:
		var s := k()
		var pl := Hud43.tex("score_timer_plate")
		if pl:
			ci.draw_texture_rect(pl, Rect2(PLATE.position * s, PLATE.size * s), false)
		var t: float = hud.sim.time
		HudLab.text_c(ci, "%02d:%02d" % [int(t) / 60, int(t) % 60], TIMER * s, int(round(26.0 * s)), Hud43.INK, HudLab.bold())
		var socks: Array = SOCK[4 if four() else 2]
		for i in range(mini(players.size(), socks.size())):
			var seat: String = players[i]
			var c := Vector2(socks[i][0], socks[i][1]) * s
			var rad: float = float(socks[i][2]) * s * 0.92
			var out: bool = hud.sim.factions.has(seat) and hud._seat_out(seat)
			var f: String = str(hud.sim.factions.get(seat, "vex"))
			Hud43.draw_ai_disc(ci, f, c, rad, Color(1, 1, 1, 0.45) if out else Color.WHITE)
			# the seat ring, thin (Daniele 11-18: "less thick ... same size of other neon stripes we use"): 1.0 pt, as the 45B
			# SELECTED rims (639 ref px = 270 pt)
			ci.draw_arc(c, rad, 0.0, TAU, 40, Color(Rules.seat_color(seat), 0.35 if out else 1.0), maxf(1.0, 639.0 / 270.0 * s), true)


static func draw_ai_disc(ci: CanvasItem, f: String, c: Vector2, r: float, mod := Color.WHITE, blink := false) -> void:
	## The faction AI's HD screen (UiKit.ai_screen_path) cropped to a disc: its inner face, no bezel.
	var t := UiKit.tex(UiKit.ai_screen_path(f, blink))
	if t == null:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.53) + d * 0.33)
	ci.draw_colored_polygon(pts, mod, uvs, t)
