class_name SkillDock
extends VBoxContainer
## SKILLS 2.0 in-match dock (0.18.7): the three slots ACTIVE / MAP / ULTIMATE - Alpha 24 (Hub Roadmap m05: "skills stacked
## on the right, compact sizes"): a column of round buttons on the right edge (Hud.layout), in the round-3 pack's look,
## shown only when ABILITIES are on. Daniele (0.18.7): "time to add armies presets and skills"; for all UI:
## "make sure it all is consistent, functional, cool, properly sized and that it looks good and modern".
## Each slot: the skill's icon, a cooldown sweep with the seconds left, a ready glow; the ultimate has a
## charge ring and a READY burst; Overdrive shows its relay fires left. Casting: tap a slot (or 1 / 2 / 3),
## the valid targets light up in the world (Sim.targets_for: lines, nodes, decks, relays), tap one to
## cast - Ghost Line takes its source node, then its destination. Tap the slot again or empty space to
## cancel (a cancel spends nothing). A tap on a wrong target says Sim.cast_check's reason just above the slot
## (Hud.skill_refusal - HUD pass: no notification box; a HUD without it, the tests' double: its toast); a cast goes
## through main.node_action("cast", slot index, {"target": t}) (online guests: an order to the host) and
## the slot pulses. While no slot is armed the dock never touches world input (drag-to-send, tap-to-inspect).
## POWERS (0.22.2): Quake taps a platform, Sinkhole an enemy structure (each lit one says what it becomes: "T3→T2" /
## "SINK"), Fog of War the circle's centre, Backwash / Sever a deck (relay decks too), Evac an enemy node; Portal
## takes two taps like Ghost Line - an entrance, then an exit among Sim.portal_exits (lit, with a faint link from the
## entrance); Core Meltdown lists every attacking line from the start of its trip.
## Also: the callout where an enemy's skill hits you (fx "skill" with `affects`), and the note when a map
## without relays swaps a relay map skill for the faction's fallback. Target highlights are drawn here, on a
## screen layer under the HUD panels; the skills' own world effects are fx code, not this file.

const SLOTS := ["active", "map", "ultimate"]
const TAGS := ["ACTIVE", "MAP", "ULTIMATE"]
# 0.19.2 spec H5: each slot type gets its own ring colour instead of sharing the seat colour - Alpha 24 Neon Noir (Daniele
# 2026-11-02, DECIDED): fixed per slot in every faction - ACTIVE ice-white, MAP violet, ULTIMATE amber (HudNoir.RING)
const SLOT_ACCENT := HudNoir.RING
const SLOT_W := 112.0                          # x ui_scale: a slot's width on desktop (phones: Rules.HUD_DOCK_PHONE_W)
const ROUND_D := 64.0                          # x ui_scale: the round button (phones: ROUND_D_PHONE - 90 px on the phone profile, ~45 pt)
const ROUND_D_PHONE := 78.0
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const TAP_PIXELS := 14.0
const HOUSING_PAD := 7.0                       # x ui_scale: the skill column's housing round its slots (Neon Noir)

var main                                      # main.gd, or a test double: node_action, sim, HUMAN, fraction, paused
var hud                                       # Hud (toasts, inspector) or null in tests
var sim: Sim
var human := "A"
var ui_scale := 1.0
var mobile := false
var keys := true                         # the slot's desktop key (1 / 2 / 3) drawn in its corner - never on touch (Hud)
var accent := Color("18dae8")
var slots: Array = []                         # Slot
var layer: Control                            # target highlights (under the HUD panels)
var hint_panel: PanelContainer                # "SURGE · tap one of your lines" above the dock while armed
var hint_label: Label
var armed := -1                               # the slot being aimed, -1 = none
var src := -1                                 # Ghost Line: the source node picked (then the destination); POWERS: Portal's entrance
var cands: Array = []                         # valid targets right now
var swapped := ""                             # the relay map skill this map replaced ("" = none)
var _cand_t := 0.0
var _press := Vector2.INF
var _t := 0.0
var _prev: Array = []                         # per slot: [cooldown, charge, overdrive fires] last frame
var _last_pulse := [-9.0, -9.0, -9.0]
var _floor_px := 0.0                          # phones: the smallest font the slot words may use (HUD_DOCK_MIN_PT), 0 = none
var vessel := false                           # Neon Noir revision 6: hex vessels filling with lit ooze (HudLiquid) instead of round buttons
var vessel_cy := 0.0                          # ... the vessel's centre below the slot's top (the skill card's socket, px)
var round_d := 64.0                           # the round button's diameter (px), the card's inner pad, the tag pill's height
var pad := 6.0
var gap := 4.0                                # between the round button and the name
var _cards := {}                              # armed? -> the slot card's box (HudNoir skill_card / skill_card_armed)
var _housing: StyleBox                        # Neon Noir: the column's container (HudNoir skill_housing: ooze, drips)
var _names := {}                              # skill id -> its name in 1 or 2 lines (name_lines)
var _bad := Vector2.INF                       # where the last wrong target was tapped (an INVALID mark there, fading)
var _bad_t := 0.0
var _last_tap := Vector2.INF                  # the world tap being judged (tap -> pick -> _refuse)


class Slot:
	extends BaseButton
	var dock: SkillDock
	var index := 0
	var id := ""
	var cd := 0.0                              # seconds left (ultimate: seconds of charge left)
	var frac := 0.0                            # active / map: cooldown left 0..1; ultimate: charge 0..1
	var is_ready := false
	var fires := 0                             # Overdrive running: relay fires left
	var pulse := 0.0                           # a cast: 1 -> 0
	var burst := 0.0                           # the ultimate turned ready: 1 -> 0
	var warn := 0.0                            # a refused tap: 1 -> 0
	var _key := ""
	var vessel: HudLiquid                      # Neon Noir: the hex vessel (the liquid = the charge) and, over it, the face:
	var face: Control                          # icon, seconds, flashes

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func state(new_id: String, new_cd: float, new_frac: float, new_ready: bool, new_fires: int) -> void:
		var key := "%s|%d|%d|%s|%d|%s" % [new_id, int(ceil(new_cd)), int(new_frac * 96.0), new_ready, new_fires, dock.armed == index]
		id = new_id
		cd = new_cd
		frac = new_frac
		is_ready = new_ready
		fires = new_fires
		if key != _key or is_ready or pulse > 0.0 or burst > 0.0 or warn > 0.0 or dock.armed == index:
			_key = key
			queue_redraw()                     # a ready slot glows (animated): the only per-frame redraw
			if face != null:
				face.queue_redraw()

	func _draw() -> void:
		## Alpha 24 Neon Noir (the board's ABILITY CONTROL, Daniele's corrections 2026-11-02): a glass section of the skill
		## column's housing holding the round button - its ring fixed per slot (HudNoir.RING), the white icon -, then the skill's
		## NAME (no slot label: no "ACTIVE", no "MAP ·"; one line, or two when it would be cut - EMERGENCY / EVAC) and its state.
		var s := dock.ui_scale
		var w := size.x
		var col: Color = SkillDock.SLOT_ACCENT[index]
		var armed := dock.armed == index
		var ult := index == 2
		var t := dock._t
		var glow := 0.55 + 0.45 * sin(t * 4.0)
		var disabled := id == "" or not dock.sim.abilities_on or dock.sim.over
		draw_style_box(dock.card_box(armed), Rect2(Vector2.ZERO, size))
		var d := dock.round_d
		var ic := Vector2(w / 2.0, dock.vessel_cy if vessel != null else dock.pad + d / 2.0)
		var state := "disabled" if disabled else ("armed" if armed else ("ready" if is_ready or fires > 0 else "cooling"))
		var done := 1.0 if is_ready or fires > 0 or armed else (frac if ult else 1.0 - frac)
		if vessel != null:
			_vessel_state(state, done, col)
			_draw_tail(w, ic, d, armed, disabled, ult, col)
			return
		if state == "ready":                              # a ready button breathes
			draw_circle(ic, d * 0.5 + 3.0 * s, Color(col, 0.1 * glow))
		HudNoir.draw_skill_button(self, ic, d, index, state, done)
		var ring_r := d * 0.46
		var ring_w := d * 0.075
		if warn > 0.0:                                     # a refused tap: the ring flashes the warning red
			draw_arc(ic, ring_r, 0.0, TAU, 48, Color(HudNoir.ENEMY, warn), ring_w * 1.4, true)
		var tex := HudSkin.skill_icon(id)
		var isz := Vector2.ONE * d * 0.46
		if tex:                                            # skill icons are white (Neon Noir: never tinted)
			var tint := HudNoir.INK if is_ready or armed else Color(HudNoir.MUTED, 0.55)
			draw_texture_rect(tex, Rect2(ic - isz / 2.0, isz), false, tint)
		if not ult and cd > 0.0 and not disabled:
			# the cooldown sweep over the icon: the part still cooling stays shaded, clockwise from the top
			var pts := PackedVector2Array([ic])
			var n := maxi(3, int(40.0 * frac))
			for k in range(n + 1):
				var a := -PI / 2.0 + TAU * (1.0 - frac) + TAU * frac * float(k) / float(n)
				pts.append(ic + Vector2(cos(a), sin(a)) * d * 0.4)
			if frac > 0.01:
				draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
			_centred("%d s" % int(ceil(cd)), ic, 22, HudNoir.INK, true)
		elif ult and not is_ready and fires <= 0 and cd > 0.0 and not disabled:
			_centred("%d s" % int(ceil(cd)), ic, 22, HudNoir.INK, true)
		if ult and burst > 0.0:                            # READY: a ring bursting out of the button
			var k := 1.0 - burst
			draw_arc(ic, d * 0.5 + (4.0 + 26.0 * k) * s, 0.0, TAU, 48, Color(col, burst), (5.0 * burst + 1.0) * s, true)
			draw_arc(ic, d * 0.5 + (2.0 + 14.0 * k) * s, 0.0, TAU, 48, Color(1, 1, 1, burst * 0.8), 2.0 * s, true)
		if fires > 0:                                      # Rewire / Overdrive: fires left, a count dot on the button
			var bc := ic + Vector2(d * 0.36, -d * 0.36)
			var br := maxf(11.0 * s, dock._floor_px * 0.62)
			draw_circle(bc, br + 2.0 * s, Color(HudNoir.ENEMY, 0.3))
			draw_circle(bc, br, HudNoir.ENEMY)
			draw_arc(bc, br, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.2 * s, true)
			_centred("%d" % fires, bc, 14, Color.WHITE, false)
		_draw_tail(w, ic, d, armed, disabled, ult, col)
		if pulse > 0.0:                          # a cast: a white flash through the button
			draw_circle(ic, d * 0.5, Color(1, 1, 1, 0.3 * pulse))
			draw_arc(ic, d * 0.5, 0.0, TAU, 48, Color(1, 1, 1, pulse), 3.0 * s, true)

	func _draw_tail(w: float, ic: Vector2, d: float, armed: bool, disabled: bool, ult: bool, col: Color) -> void:
		## The desktop key, the words, and READY rising out of the slot when the ultimate fills.
		var s := dock.ui_scale
		if dock.keys and not dock.mobile:
			var kr := Rect2(Vector2(5.0, 5.0) * s, Vector2(14, 15) * s)
			draw_rect(kr, Color(HudNoir.INK, 0.08))
			draw_rect(kr, Color(HudNoir.INK, 0.3), false, 1.0)
			_centred(str(index + 1), kr.get_center() + Vector2(0, 0.5 * s), 11, HudNoir.MUTED, false)
		_draw_words(w, ic, d, armed, disabled, ult, col)
		if burst > 0.0:                          # the ultimate turned ready: READY rises out of the slot
			var rise := (1.0 - burst) * 16.0 * s
			var rp := Vector2(w / 2.0, -10.0 * s - rise)
			var f := int(22 * s)
			var rsz := HEAD_FONT.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f)
			draw_string_outline(HEAD_FONT, rp - Vector2(rsz.x / 2.0, 0), "READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(6 * s), Color(0, 0, 0, 0.8 * burst))
			draw_string(HEAD_FONT, rp - Vector2(rsz.x / 2.0, 0), "READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color(col.lerp(Color.WHITE, 0.4), minf(1.0, burst * 1.6)))

	func _draw_words(w: float, ic: Vector2, d: float, armed: bool, disabled: bool, ult: bool, col: Color) -> void:
		## The skill's NAME (one or two lines) and its state word under the button / vessel.
		var room := w - 2.0 * dock.pad
		var nf := dock.font_px(16)
		var lines: Array = dock.name_lines(id, room)
		var y := ic.y + d / 2.0 + dock.gap + UI_FONT.get_ascent(nf)
		for ln in lines:
			_line(str(ln), Vector2(w / 2.0, y), 16, HudNoir.INK if is_ready or armed else HudNoir.MUTED, room, UI_FONT)
			y += UI_FONT.get_height(nf) * 0.88
		var status := ""
		var sc := HudNoir.MUTED
		if armed:
			status = "TAP A TARGET" if not (dock.src >= 0) else ("TAP THE EXIT" if dock._kind() == "node_pair" else "TAP WHERE IT GOES")   # (POWERS: Portal)
			if fires > 0:
				status = "TAP A RELAY · %d LEFT" % fires
			sc = HudNoir.INK
		elif fires > 0:
			status = "FIRE A RELAY · %d LEFT" % fires
			sc = col
		elif disabled:
			status = "OFF"
		elif is_ready:
			status = "READY"
			sc = col
		elif ult:
			status = "CHARGING"
		else:
			status = "COOLDOWN"
		y += UI_FONT.get_height(dock.font_px(13)) * 0.1
		_line(status, Vector2(w / 2.0, y), 13, sc, room, UI_FONT)

	func _vessel_state(state: String, done: float, col: Color) -> void:
		## Neon Noir: the hex vessel shows the charge as its liquid level (the slot's fixed colour); full = ready, breathing.
		var rid := "skill_vessel_rim_disabled" if state == "disabled" else ("skill_vessel_rim_armed" if state == "armed" or state == "ready" else "")
		var path := str(HudNoir.part_data(rid).get("file", "")) if rid != "" else str(HudNoir.part_data("skill_vessel").get("rim", ""))
		vessel.set_rim(path, col)
		vessel.set_liquid(col, 1.0 if state != "disabled" else 0.35)
		vessel.set_level(0.0 if state == "disabled" else done)
		vessel.ready_glow = state == "ready" or state == "armed"

	func _draw_face(ci: Control) -> void:
		## Over the vessel: the white icon (dark on a full vessel), the seconds while it fills, the flashes - a cast, a refused
		## tap (red hex), the ultimate turning ready (a hex bursting out), Rewire's fires left.
		var s := dock.ui_scale
		var c := ci.size / 2.0
		var d := ci.size.x
		var col: Color = SkillDock.SLOT_ACCENT[index]
		var ult := index == 2
		var disabled := id == "" or not dock.sim.abilities_on or dock.sim.over
		var full := is_ready or fires > 0 or dock.armed == index
		var cooling := not disabled and not full and cd > 0.0
		var tex := HudSkin.skill_icon(id)
		if tex:
			var isz := Vector2.ONE * d * (0.44 if not cooling else 0.32)
			var at := c - isz / 2.0 - Vector2(0, d * 0.1 if cooling else 0.0)
			var tint := Color(0.03, 0.05, 0.07, 0.9) if full and not disabled else (Color(1, 1, 1, 0.85) if not disabled else Color(HudNoir.MUTED, 0.5))
			ci.draw_texture_rect(tex, Rect2(at, isz), false, tint)
		if cooling:
			var f := int(20 * s)
			var txt := "%d s" % int(ceil(cd))
			var sz := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
			var p := c + Vector2(-sz.x / 2.0, d * 0.2 + UI_FONT.get_ascent(f) / 2.0 - 1.0)
			ci.draw_string_outline(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * s), HudSkin.outline())
			ci.draw_string(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, HudNoir.INK)
		if warn > 0.0:                                     # a refused tap: the vessel's outline flashes the warning red
			ci.draw_polyline(_hex(c, d * 0.5), Color(HudNoir.ENEMY, warn), 3.0 * s, true)
		if ult and burst > 0.0:                            # READY: a hex bursting out of the vessel
			var k := 1.0 - burst
			ci.draw_polyline(_hex(c, d * 0.5 + (4.0 + 26.0 * k) * s), Color(col, burst), (5.0 * burst + 1.0) * s, true)
			ci.draw_polyline(_hex(c, d * 0.5 + (2.0 + 14.0 * k) * s), Color(1, 1, 1, burst * 0.8), 2.0 * s, true)
		if pulse > 0.0:                                    # a cast: a white flash through the vessel
			ci.draw_colored_polygon(_hex(c, d * 0.48), Color(1, 1, 1, 0.3 * pulse))
			ci.draw_polyline(_hex(c, d * 0.5), Color(1, 1, 1, pulse), 3.0 * s, true)
		if fires > 0:                                      # Rewire / Overdrive: fires left, a count dot on the vessel
			var bc := c + Vector2(d * 0.36, -d * 0.36)
			var br := maxf(11.0 * s, dock._floor_px * 0.62)
			ci.draw_circle(bc, br + 2.0 * s, Color(HudNoir.ENEMY, 0.3))
			ci.draw_circle(bc, br, HudNoir.ENEMY)
			ci.draw_arc(bc, br, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.2 * s, true)
			var f2 := int(14 * s)
			var t2 := "%d" % fires
			var z2 := UI_FONT.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, f2)
			ci.draw_string(UI_FONT, bc + Vector2(-z2.x / 2.0, UI_FONT.get_ascent(f2) / 2.0 - 1.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, f2, Color.WHITE)

	static func _hex(c: Vector2, r: float) -> PackedVector2Array:
		## A flat-topped hexagon (the vessel's outline), closed.
		var pts := PackedVector2Array()
		for k in range(7):
			var a := TAU * float(k % 6) / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		return pts

	func _line(txt: String, centre_base: Vector2, fs: int, col: Color, room: float, font: Font) -> void:
		## One line centred on centre_base.x, its baseline at centre_base.y, stepped down / cut to fit like _text.
		var f := dock.font_px(fs)
		var least := maxi(int(fs * dock.ui_scale * 0.7), int(ceil(dock._floor_px)))
		while f > least and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
			f -= 1
		if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
			while txt.length() > 1 and font.get_string_size(txt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
				txt = txt.substr(0, txt.length() - 1).strip_edges()
			txt += "…"
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		draw_string(font, Vector2(centre_base.x - w / 2.0, centre_base.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)

	func _centred(txt: String, at: Vector2, fs: int, col: Color, outline: bool) -> void:
		var f := int(fs * dock.ui_scale)
		var sz := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		var p := at + Vector2(-sz.x / 2.0, UI_FONT.get_ascent(f) / 2.0 - 1.0)
		if outline:
			draw_string_outline(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * dock.ui_scale), HudSkin.outline())
		draw_string(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)

	func _text(txt: String, base: Vector2, fs: int, col: Color, room: float, font: Font) -> void:
		## One line, its font stepped down to fit the room (never below 70 %, and on a phone never below
		## HUD_DOCK_MIN_PT - the iPhone sweep: the tags read ~7-8 pt), baseline at `base`; what still doesn't fit
		## is cut with an ellipsis rather than drawn past the slot.
		var f := maxi(int(fs * dock.ui_scale), int(ceil(dock._floor_px)))
		var least := maxi(int(fs * dock.ui_scale * 0.7), int(ceil(dock._floor_px)))
		while f > least and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
			f -= 1
		if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
			while txt.length() > 1 and font.get_string_size(txt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
				txt = txt.substr(0, txt.length() - 1).strip_edges()
			txt += "…"
		draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


class TargetLayer:
	extends Control
	var dock: SkillDock

	func _draw() -> void:
		if dock and (dock.armed >= 0 or dock._bad_t > 0.0):
			dock._draw_targets(self)


# ------------------------------------------------------------------ build
func setup(m, s: Sim, seat: String, scale_ui: float, is_mobile: bool, h = null, targets: Control = null) -> void:
	main = m
	sim = s
	human = seat
	ui_scale = scale_ui
	mobile = is_mobile
	hud = h
	accent = HudNoir.accent                       # Neon Noir: the chrome takes your faction's colour
	add_theme_constant_override("separation", int(8 * ui_scale))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the iPhone sweep (HUD pass): on a phone the slot words never drop under HUD_DOCK_MIN_PT real points, and the
	# column is a little wider (HUD_DOCK_PHONE_W) so they still fit; the round button stays >= 44 pt
	var slot_w := SLOT_W
	round_d = ROUND_D * ui_scale
	if mobile:
		var tree := Engine.get_main_loop() as SceneTree   # (not in the tree yet: the window's canvas size)
		var vp := tree.root.get_visible_rect().size if tree != null and tree.root != null else Vector2(1280, 720)
		_floor_px = Rules.HUD_DOCK_MIN_PT / maxf(UiKit.pt_per_px(vp), 0.01)
		slot_w = Rules.HUD_DOCK_PHONE_W
		round_d = ROUND_D_PHONE * ui_scale
	pad = 6.0 * ui_scale
	gap = 4.0 * ui_scale
	add_theme_constant_override("separation", int(6 * ui_scale))
	slot_w -= 2.0 * HOUSING_PAD                   # Neon Noir: the housing's rim sits inside the column's old width (phone fit)
	vessel = HudNoir.has("skill_vessel") and HudNoir.has("skill_card")
	var top := pad
	if vessel:                                    # the vessel is drawn at the card's scale, centred on its socket
		var k := ui_scale / HudNoir.SPRITE_K
		var vb: Array = HudNoir.part_data("skill_vessel").get("body", [0, 0, 270, 270])
		var sock: Array = HudNoir.part_data("skill_card").get("socket", [0, 170])
		round_d = float(vb[2]) * k
		vessel_cy = float(sock[1]) * k
		top = vessel_cy - round_d / 2.0
	for i in range(3):
		# Neon Noir: no slot label; the name takes a second line only where one line would cut it (EMERGENCY / EVAC)
		var lines := name_lines(sim.skill_id(human, SLOTS[i]), slot_w * ui_scale - 2.0 * pad).size()
		var slot_h := top + round_d + gap + UI_FONT.get_height(font_px(16)) * (1.0 + 0.88 * float(lines - 1)) + UI_FONT.get_height(font_px(13)) * 1.1 + pad
		var b := Slot.new()
		b.dock = self
		b.index = i
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.custom_minimum_size = Vector2(slot_w * ui_scale, slot_h).round()
		b.pressed.connect(press_slot.bind(i))
		if vessel:
			b.vessel = HudLiquid.new()
			b.vessel.setup("skill_vessel", SLOT_ACCENT[i], float(i) * 1.7)
			b.vessel.position = Vector2(b.custom_minimum_size.x / 2.0 - round_d / 2.0, top).round()
			b.vessel.size = Vector2(round_d, round_d)
			b.add_child(b.vessel)
			b.face = Control.new()
			b.face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.face.position = b.vessel.position
			b.face.size = b.vessel.size
			b.face.draw.connect(b._draw_face.bind(b.face))
			b.add_child(b.face)
		b.tooltip_text = ""
		add_child(b)
		slots.append(b)
		_prev.append([0.0, 0.0, 0])
	layer = targets
	if layer == null:
		layer = TargetLayer.new()
	if layer is TargetLayer:
		(layer as TargetLayer).dock = self
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel = PanelContainer.new()
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", HudNoir.box("hint_pill", Color(0, 0, 0, 0), Vector4(16, 8, 16, 8) * ui_scale))
	hint_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hint_label = Label.new()
	hint_label.add_theme_font_override("font", UI_FONT)
	hint_label.add_theme_font_size_override("font_size", maxi(int(17 * ui_scale), int(ceil(_floor_px * 1.15))))
	hint_label.add_theme_color_override("font_color", HudSkin.INK)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_label)
	hint_panel.visible = false
	# a relay skill on a map without relays: the faction's fallback plays (Sim._setup_skills); say so once
	var lo = main.LOADOUTS.get(human, {}) if main.get("LOADOUTS") is Dictionary else {}
	var f := str(sim.factions.get(human, "null"))
	var wanted := Rules.skill_slot_id(f, lo if lo is Dictionary else {}, "map")
	if sim.loadouts.has(human) and wanted != sim.skill_id(human, "map"):
		swapped = wanted


func font_px(fs: int) -> int:
	## A slot word's font size: fs x ui_scale, never under the phone's floor (HUD_DOCK_MIN_PT).
	return maxi(int(fs * ui_scale), int(ceil(_floor_px)))


func card_box(armed_now: bool) -> StyleBox:
	## A slot's section of the housing (Neon Noir): faint glass, the accent rim lit while that slot is armed.
	if not _cards.has(armed_now):
		_cards[armed_now] = HudNoir.box("skill_card_armed" if armed_now else "skill_card", Color(0, 0, 0, 0), Vector4.ZERO)
	return _cards[armed_now]


func housing_margin() -> Vector4:
	## The skill column's housing round the slots (l, t, r, b px - b holds its drips): Hud.layout keeps it on screen.
	var m := HOUSING_PAD * ui_scale
	var pool := HudNoir.gel_px("skill_housing") * 0.55       # Neon Noir: the upper half of the pooled ooze shows under the last card
	return Vector4(m, m, m, m + pool + HudNoir.drip_px("skill_housing"))


func _draw() -> void:
	## Neon Noir: the column's container - smoked glass with living ooze in its foot and the drips under it (the one place on
	## the right thumb that drips; the slots themselves are clean glass).
	if _housing == null:
		_housing = HudNoir.box("skill_housing", Color(0, 0, 0, 0), Vector4.ZERO)
	var hm := housing_margin()
	draw_style_box(_housing, Rect2(-hm.x, -hm.y, size.x + hm.x + hm.z, size.y + hm.y + hm.w))


func name_lines(id: String, room: float) -> Array:
	## The skill's name as drawn under its button: one line when it fits (down to 80 % of its size), else split at the space
	## nearest the middle into two lines (EMERGENCY EVAC was cut to "EMERGENCY E..." on the phone).
	if _names.has(id):
		return _names[id]
	var name := ArmyPresets.skill_name(id).to_upper() if id != "" else ""
	var least := maxi(int(16 * ui_scale * 0.8), int(ceil(_floor_px)))
	var out := [name]
	if UI_FONT.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, least).x > room and name.contains(" "):
		var best := -1
		for k in range(name.length()):
			if name[k] == " " and (best < 0 or absi(k - name.length() / 2) < absi(best - name.length() / 2)):
				best = k
		out = [name.substr(0, best), name.substr(best + 1)]
	_names[id] = out
	return out


static func new_layer() -> Control:
	var l := TargetLayer.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func start_note() -> String:
	## The line for the match's first toasts: which relay skill this map replaced, or "".
	if swapped == "":
		return ""
	return "No relays on this map: %s plays instead of %s" % [ArmyPresets.skill_name(sim.skill_id(human, "map")), ArmyPresets.skill_name(swapped)]


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	_t += dt
	if _bad_t > 0.0:
		_bad_t = maxf(_bad_t - dt / 0.7, 0.0)
		layer.queue_redraw()
	for i in range(3):
		var slot: String = SLOTS[i]
		var b: Slot = slots[i]
		var id := sim.skill_id(human, slot)
		var cd := sim.cooldown(human, slot)
		var ch := sim.charge(human) if i == 2 else 0.0
		var fires := sim.overdrive_left(human) if i == 2 else 0
		var ready := sim.abilities_on and not sim.over and (cd <= 0.0 or fires > 0) and id != ""
		var frac := 0.0
		if i == 2:
			frac = clampf(ch, 0.0, 1.0) if cd > 0.0 else 1.0
		elif cd > 0.0:
			frac = clampf(cd / maxf(float(Rules.SKILLS.get(id, {}).get("cd", 1.0)), 0.01), 0.0, 1.0)
		var p: Array = _prev[i]
		# a cast happened (ours, or a guest's order the host accepted): the cooldown jumped up, the charge
		# was spent, or a Overdrive fire was used
		var cast := (i < 2 and float(p[0]) <= 0.05 and cd > 1.0) or (i == 2 and float(p[1]) >= 1.0 and ch < 0.5) or (i == 2 and fires < int(p[2]) and fires >= 0 and int(p[2]) > 0)
		if cast and _t - float(_last_pulse[i]) > 0.6:
			b.pulse = 1.0
			_last_pulse[i] = _t
		if i == 2 and float(p[1]) < 1.0 and ch >= 1.0 and _t > 0.5:
			b.burst = 1.0
		_prev[i] = [cd, ch, fires]
		b.pulse = maxf(b.pulse - dt / 0.35, 0.0)
		b.burst = maxf(b.burst - dt / 1.1, 0.0)
		b.warn = maxf(b.warn - dt / 0.45, 0.0)
		b.pivot_offset = b.size / 2.0
		b.scale = Vector2.ONE * (1.0 + 0.07 * b.pulse + 0.05 * b.burst)
		b.state(id, cd, frac, ready, fires)
	if armed >= 0:
		var slot: String = SLOTS[armed]
		var overdriving := armed == 2 and sim.overdrive_left(human) > 0
		if main.paused or sim.over or not sim.abilities_on or (not overdriving and sim.cooldown(human, slot) > 0.0):
			cancel()
		else:
			_cand_t -= dt
			if _cand_t <= 0.0:
				_refresh_cands()
			layer.queue_redraw()


func _refresh_cands() -> void:
	_cand_t = 0.3
	if armed < 0:
		return
	var slot: String = SLOTS[armed]
	if _kind() == "node_pair" and src >= 0:          # POWERS (Portal): the exits of the entrance picked
		if not sim._node_ok(src) or sim.portal_of(src) >= 0:
			src = -1                                  # (its node dropped, or someone opened a portal there first)
			cands = sim.targets_for(human, slot)
			_hint()
		else:
			cands = sim.portal_exits(src).filter(func(x): return sim.cast_check(human, slot, [src, x]) == "")
	elif _kind() == "vat_to_node" and src >= 0:
		cands = []
		for n in sim.nodes:
			if sim.cast_check(human, slot, [src, n["id"]]) == "":
				cands.append(n["id"])
		if not sim._node_ok(src) or sim.nodes[src]["owner"] != human:
			src = -1
			cands = sim.targets_for(human, slot)
			_hint()
	else:
		cands = sim.targets_for(human, slot)


# ------------------------------------------------------------------ slots
func _kind() -> String:
	if armed < 0:
		return ""
	var id := sim.skill_id(human, SLOTS[armed])
	if armed == 2 and id == "overdrive" and sim.overdrive_left(human) > 0:
		return "relay"
	return str(Rules.SKILLS.get(id, {}).get("target", "none"))


func press_slot(i: int) -> void:
	## A slot tapped (or its key): arm it, cast it (no target), cancel it (armed again), or say why not.
	if i < 0 or i > 2 or main.paused or sim.over:
		return
	if armed == i:
		cancel()
		return
	cancel()
	var slot: String = SLOTS[i]
	var id := sim.skill_id(human, slot)
	if id == "":
		return
	var overdriving := i == 2 and id == "overdrive" and sim.overdrive_left(human) > 0
	if not sim.abilities_on or not (overdriving or sim.cooldown(human, slot) <= 0.0):
		_refuse(i, sim.cast_check(human, slot, null))
		return
	var kind := "relay" if overdriving else str(Rules.SKILLS[id]["target"])
	if kind == "none":
		var why := sim.cast_check(human, slot, null)
		if why != "":
			_refuse(i, why)
			return
		_cast(i, null)
		return
	var t := sim.targets_for(human, slot)
	if t.is_empty():
		var why := sim.cast_check(human, slot, null)
		if kind == "own_line" and why.begins_with("Pick"):
			why = "%s: none of your lines to pick right now" % ArmyPresets.skill_name(id)
		elif why == "" or why.begins_with("Pick"):
			why = "%s: nothing to target right now" % ArmyPresets.skill_name(id)
		_refuse(i, why)
		return
	armed = i
	src = -1
	cands = t
	_cand_t = 0.3
	if hud:
		hud.close_inspector()
	_hint()
	layer.visible = true
	layer.queue_redraw()


func cancel() -> void:
	## Disarm (nothing is spent).
	if armed < 0:
		return
	var was := armed
	armed = -1
	src = -1
	cands = []
	_press = Vector2.INF
	hint_panel.visible = false
	layer.queue_redraw()
	(slots[was] as Slot).queue_redraw()


func _refuse(i: int, why: String) -> void:
	(slots[i] as Slot).warn = 1.0
	if armed >= 0 and _last_tap != Vector2.INF:       # a wrong target tapped while aiming: the pack's INVALID mark there
		_bad = _last_tap
		_bad_t = 1.0
		_last_tap = Vector2.INF
	if why == "":
		return
	if hud and hud.has_method("skill_refusal"):     # HUD pass: a small line just above the slot that was tapped
		hud.skill_refusal(i, why)
	else:
		_toast(why, "warn")


func _hint() -> void:
	if armed < 0:
		hint_panel.visible = false
		return
	var id := sim.skill_id(human, SLOTS[armed])
	var what := ArmyPresets.target_hint(id, 1 if src >= 0 else 0)
	if _kind() == "relay" and armed == 2:
		what = "tap any relay to fire it"
	hint_label.text = "%s  ·  %s  ·  tap the slot again to cancel" % [ArmyPresets.skill_name(id).to_upper(), what]
	hint_panel.visible = true
	hint_panel.size = Vector2.ZERO
	hint_panel.size = hint_panel.get_combined_minimum_size()
	_place_hint()


func _place_hint() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var floor_y := vp.y - 40.0 * ui_scale                 # Alpha 24: bottom centre, over the map title's line (the dock is a column)
	hint_panel.position = Vector2(clampf((vp.x - hint_panel.size.x) / 2.0, 0.0, maxf(position.x - hint_panel.size.x - 8.0 * ui_scale, 0.0)),
			floor_y - hint_panel.size.y)


func _cast(i: int, target) -> bool:
	var ok: bool = main.node_action("cast", i, {"target": target})
	if ok:
		cancel()
		if not main.get("online"):             # offline it has happened; online the host's answer pulses it
			(slots[i] as Slot).pulse = 1.0
			_last_pulse[i] = _t
	else:
		_refresh_cands()
	return ok


func _toast(msg: String, kind := "") -> void:
	if hud:
		hud.toast(msg, kind)


# ------------------------------------------------------------------ world taps while armed
func take_input(mb: InputEventMouseButton) -> bool:
	## main._unhandled_input: while a slot is armed every world tap is the dock's. False = not armed.
	if armed < 0:
		return false
	if mb.pressed:
		_press = mb.position
		return true
	if _press == Vector2.INF:
		return true
	var moved := (mb.position - _press).length() >= TAP_PIXELS * (1.6 if mobile else 1.0)
	_press = Vector2.INF
	if moved:                                  # a drag is not a pick: stand down, nothing spent
		cancel()
		return true
	tap(mb.position)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	## Desktop: 1 / 2 / 3 arm (or cast) the slots, Esc cancels.
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k: Key = (event as InputEventKey).keycode
	var i := [KEY_1, KEY_2, KEY_3].find(k)
	if i < 0:
		i = [KEY_KP_1, KEY_KP_2, KEY_KP_3].find(k)
	if i >= 0:
		press_slot(i)
		get_viewport().set_input_as_handled()
	elif k == KEY_ESCAPE and armed >= 0:
		cancel()
		get_viewport().set_input_as_handled()


func tap(p: Vector2) -> void:
	## A world tap while armed: what is under it, for this slot's kind of target (nothing: cancel).
	var cam: Camera3D = main.cam
	var raw = -1
	_last_tap = p
	match _kind():
		"own_line":
			raw = _line_at(p, cam)
		"deck", "fixed_deck":
			raw = _deck_at(p, cam)
		_:
			raw = main._node_at(main._ground(p), p)
			var near := _cand_node_at(p, cam)           # a lit ring wins over a neighbour's badge
			if near >= 0:
				raw = near
	if raw is int and raw < 0:
		cancel()
		return
	pick(raw)


func pick(raw) -> void:
	## The thing tapped (node id, edge index or line id) as this slot's target: cast it, step Ghost Line on,
	## or toast why not. Tests call this directly.
	if armed < 0:
		return
	var slot: String = SLOTS[armed]
	var kind := _kind()
	var target = raw
	match kind:
		"enemy_relay":                         # fire where it can, else the jam (Sim.targets_for's choice)
			if sim.cast_check(human, slot, raw) != "" and sim.cast_check(human, slot, [raw, "jam"]) == "":
				target = [raw, "jam"]
		"vat_to_node":
			if src < 0:
				if raw in cands:
					src = raw
					_refresh_cands()
					_cand_t = 0.3
					_hint()
					(slots[armed] as Slot).queue_redraw()
				else:
					var n: Dictionary = sim.nodes[raw]
					_refuse(armed, "Start from one of your nodes" if n["owner"] != human else "No units to copy there")
				return
			if raw == src:                     # the source again: pick another
				src = -1
				cands = sim.targets_for(human, slot)
				_hint()
				return
			target = [src, raw, clampf(float(main.fraction), 0.01, 1.0)]
		"node_pair":                           # POWERS (Portal): the entrance, then the exit
			if src < 0:
				if raw in cands:
					src = raw
					_refresh_cands()
					_cand_t = 0.3
					_hint()
					(slots[armed] as Slot).queue_redraw()
				else:
					var why0 := sim.cast_check(human, slot, [raw, -1])
					_refuse(armed, why0 if why0 != "" and why0 != "Pick an exit" else "No exit within reach of that node")
				return
			if raw == src:                     # the entrance again: pick another
				src = -1
				cands = sim.targets_for(human, slot)
				_hint()
				return
			target = [src, raw]
	var why := sim.cast_check(human, slot, target)
	if why != "":
		_refuse(armed, why)
		return
	_cast(armed, target)


func _node_screen(id: int, cam: Camera3D) -> Array:
	## [centre, radius] of a node's platform on screen.
	var pos: Vector3 = sim.nodes[id]["pos"]
	var c := cam.unproject_position(pos)
	var r := cam.unproject_position(pos + cam.global_transform.basis.x * Rules.R).distance_to(c)
	return [c, r]


func _cand_node_at(p: Vector2, cam: Camera3D) -> int:
	var best := -1
	var best_d := INF
	for c in cands:
		var id: int = c[0] if c is Array else int(c)
		var ns := _node_screen(id, cam)
		var d := p.distance_to(ns[0])
		if d <= float(ns[1]) + 10.0 * ui_scale and d < best_d:
			best_d = d
			best = id
	return best


func _deck_px(ei: int, cam: Camera3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in sim.deck_line(ei):
		out.append(cam.unproject_position(q + Vector3(0, 0.3, 0)))
	return out


func _deck_at(p: Vector2, cam: Camera3D) -> int:
	## The deck under a tap (screen distance to its centre line), lit decks first. 2026-11-01 (Daniele: "bridges are
	## sometimes hard to click"): on a phone the band is at least Rules.DECK_HIT_PT across in real points (deck_reach)
	## - invisible, the deck looks the same. The extra reach beyond the old band never takes a tap that sits on a
	## node's platform (nodes keep priority where a tap is near both); inside the old band nothing changed.
	var core := (20.0 if not mobile else 30.0) * ui_scale
	var reach := deck_reach(core)
	var on_node := reach > core and _platform_at(p, cam) >= 0
	for pass_n in range(2):
		var best := -1
		var best_d := reach
		var pool: Array = cands if pass_n == 0 else range(sim.edges.size())
		for ei in pool:
			var pts := _deck_px(int(ei), cam)
			for k in range(pts.size() - 1):
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]))
				if d < best_d and (d <= core or not on_node):
					best_d = d
					best = int(ei)
		if best >= 0:
			return best
	return -1


func deck_reach(core: float) -> float:
	## Half the deck tap band in viewport pixels: the old band, or - on a phone - half Rules.DECK_HIT_PT in real points
	## (UiKit.pt_per_px: the web page's CSS size, else the landscape-phone reference), whichever is wider.
	if not mobile:
		return core
	var ppt := UiKit.pt_per_px(get_viewport().get_visible_rect().size)
	return maxf(core, Rules.DECK_HIT_PT * 0.5 / maxf(ppt, 0.001))


func _platform_at(p: Vector2, cam: Camera3D) -> int:
	## The node whose platform (Rules.R on the ground) holds this screen point, or -1 (collapsed and junctions skipped).
	var g: Vector3 = main._ground(p)
	if g == Vector3.INF:
		return -1
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false) or n.get("node_kind", "") == "junction":
			continue
		if (n["pos"] as Vector3).distance_to(g) <= Rules.R:
			return n["id"]
	return -1


func _line_px(h: Dictionary, cam: Camera3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var length := Sim.chain_length(h)
	var k := 0.0
	while k <= length + 0.01 and out.size() < 48:
		out.append(cam.unproject_position(Sim.sample(h, float(h["s"]) - k)[0] + Vector3(0, 0.6, 0)))
		k += maxf(1.2, length / 40.0)
	return out


func _line_at(p: Vector2, cam: Camera3D) -> int:
	## The line under a tap, lit lines first (any line: a rival's gets cast_check's "Pick one of your lines").
	var reach := (24.0 if not mobile else 34.0) * ui_scale
	for pass_n in range(2):
		var best := -1
		var best_d := reach
		for h in sim.hordes:
			if pass_n == 0 and not h["id"] in cands:
				continue
			var pts := _line_px(h, cam)
			for k in range(pts.size()):
				var d := p.distance_to(pts[k])
				if k < pts.size() - 1:
					d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
				if d < best_d:
					best_d = d
					best = int(h["id"])
		if best >= 0:
			return best
	return -1


# ------------------------------------------------------------------ highlights (TargetLayer._draw)
func _draw_targets(ci: CanvasItem) -> void:
	if _bad_t > 0.0 and _bad != Vector2.INF:          # INVALID TARGET (B22) where a wrong pick was tapped
		var br := (26.0 + 8.0 * (1.0 - _bad_t)) * ui_scale
		HudSkin.draw_sprite(ci, "B22", Rect2(_bad - Vector2(br, br), Vector2(br, br) * 2.0), Color(1, 1, 1, _bad_t))
	var cam: Camera3D = main.cam
	if cam == null or armed < 0:
		return
	var s := ui_scale
	var a := 0.6 + 0.4 * sin(_t * 5.0)
	var col := accent
	match _kind():
		"own_line":
			for hid in cands:
				var h := sim._horde(int(hid))
				if h.is_empty():
					continue
				var pts := _line_px(h, cam)
				if pts.size() >= 2:
					ci.draw_polyline(pts, Color(col, 0.22 * a), 16.0 * s, true)
					ci.draw_polyline(pts, Color(col, 0.95), 3.0 * s, true)
				if pts.size() >= 1:
					_ring(ci, pts[0], 12.0 * s, col, a, false)
		"deck", "fixed_deck":
			for ei in cands:
				var pts := _deck_px(int(ei), cam)
				if pts.size() < 2:
					continue
				ci.draw_polyline(pts, Color(col, 0.2 * a), 18.0 * s, true)
				ci.draw_polyline(pts, Color(col, 0.9), 3.0 * s, true)
				var mid := pts[pts.size() / 2] if pts.size() % 2 == 1 else (pts[pts.size() / 2 - 1] + pts[pts.size() / 2]) / 2.0
				ci.draw_circle(mid, 5.0 * s, Color(col, 0.6 + 0.4 * a))
		_:
			var kind := _kind()
			var ss := []
			if src >= 0 and sim._node_ok(src):
				ss = _node_screen(src, cam)
			for c in cands:
				var jam: bool = c is Array
				var id: int = c[0] if jam else int(c)
				if id == src:
					continue
				var ns := _node_screen(id, cam)
				var cc := Rules.state_color("build") if jam else col
				if kind == "node_pair" and not ss.is_empty():   # POWERS (Portal): a faint link from the entrance to each exit
					_dashes(ci, ss[0], ns[0], Color(col, 0.35 + 0.25 * a), 2.0 * s)
				_ring(ci, ns[0], float(ns[1]) + 6.0 * s, cc, a, false)
				if jam:
					_label(ci, "JAM", (ns[0] as Vector2) + Vector2(0, -float(ns[1]) - 14.0 * s), cc)
				elif kind == "enemy_structure":        # POWERS (Sinkhole): what the structure becomes
					var n: Dictionary = sim.nodes[id]
					var sink := "SINK" if not (n["structure"] in ["vat", "machinegoon"] and int(n["tier"]) > 1) else "T%d→T%d" % [int(n["tier"]), int(n["tier"]) - 1]
					_label(ci, sink, (ns[0] as Vector2) + Vector2(0, -float(ns[1]) - 14.0 * s), cc)
			if not ss.is_empty():                      # the source / entrance on top of its neighbours' rings
				_ring(ci, ss[0], float(ss[1]) + 6.0 * s, Color.WHITE, 1.0, true)
				_label(ci, "IN" if kind == "node_pair" else "FROM", (ss[0] as Vector2) + Vector2(0, -float(ss[1]) - 14.0 * s), Color.WHITE)


func _ring(ci: CanvasItem, c: Vector2, r: float, col: Color, a: float, solid: bool) -> void:
	var s := ui_scale
	# Alpha 24: the pack's VALID TARGET reticle (B21) round the target, in the cast's colour, gently breathing
	var rr := r * (1.12 + 0.04 * a)
	HudSkin.draw_sprite(ci, "B21", Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), Color(col.lightened(0.2), 0.85 if solid else 0.55 + 0.3 * a))
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.22 * a), 12.0 * s, true)
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.95 if solid else 0.75 + 0.25 * a), 2.5 * s, true)
	for k in range(4):                          # four ticks turning round the ring: "tap me"
		var ang := _t * 1.6 + TAU * k / 4.0
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(c + d * (r + 5.0 * s), c + d * (r + 13.0 * s), Color(col, 0.95), 3.0 * s, true)


func _dashes(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	## POWERS: a dashed line from a to b, the dashes marching toward b.
	var d := b - a
	var length := d.length()
	if length < 1.0:
		return
	var step := 14.0 * ui_scale
	var dir := d / length
	var k := fposmod(_t * 30.0 * ui_scale, step)
	while k < length:
		ci.draw_line(a + dir * k, a + dir * minf(k + step * 0.55, length), col, w, true)
		k += step


func _label(ci: CanvasItem, txt: String, at: Vector2, col: Color) -> void:
	var f := maxi(int(14 * ui_scale), int(ceil(_floor_px * 1.15)))   # (POWERS: never under the phone's floor - IN / SINK / JAM)
	var sz := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	var p := at - Vector2(sz.x / 2.0, 0)
	ci.draw_string_outline(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * ui_scale), Color(0, 0, 0, 0.9))
	ci.draw_string(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


# ------------------------------------------------------------------ enemy casts
func on_event(ev: Dictionary) -> void:
	## An fx "skill" event: a rival's skill that touches you gets a toast (emblem + faction via "seat X", the
	## skill's name, what it does to you). Private events (Ghost Line, echoes) are for their owner only.
	if not SkillFx.touches(ev, sim, human):
		return
	var seat := str(ev.get("seat", ""))
	var id := str(ev.get("id", ""))
	var what := ""
	match id:
		"scorch": what = "your lines on a deck are burning"
		"mire": what = "your lines are slowed"
		"demolish": what = "a deck falls in %d s" % int(Rules.SKILLS["demolish"]["warn"])
		"bypass": what = "a relay holds both states"
		"relay_hack": what = "your relay is jammed" if ev.get("target") is Array else "your relay fires"
		"overdrive": what = "your relay fires" if ev.has("fire") else "their lines speed up"
		"echo_split": what = "decoy lines on the move"
		"core_meltdown": what = "an armed line is coming"   # POWERS (0.22.2): armed from the start of its trip
		# POWERS (0.22.2): the new powers
		"quake": what = "decks around a platform drop"
		"sever": what = "a deck is cut"
		"backwash": what = "your lines are shoved back"
		"sinkhole": what = "your structure sinks"
		"fog": what = "a fog hides their moves"
		"portal": what = "a portal opens"
		"evac": what = "your garrison is forced out"   # (offensive since 2026-10-07)
	# HUD pass: at the place the skill landed (the event's pos), the caster's emblem as the icon
	if hud and hud.has_method("callout_at") and ev.get("pos") is Vector3:
		hud.callout_at(ev["pos"], "skill:%s" % seat, "%s%s" % [ArmyPresets.skill_name(id).to_upper(), (" - " + what) if what != "" else ""], "warn", seat)
		return
	_toast("seat %s cast %s%s" % [seat, ArmyPresets.skill_name(id).to_upper(), (" - " + what) if what != "" else ""], "warn")
