class_name SkillDock
extends HBoxContainer
## SKILLS 2.0 in-match dock (0.18.7): the three slots ACTIVE / MAP / ULTIMATE at the bottom of the screen,
## shown only when ABILITIES are on. Daniele (0.18.7): "time to add armies presets and skills"; for all UI:
## "make sure it all is consistent, functional, cool, properly sized and that it looks good and modern".
## Each slot: the skill's icon, a cooldown sweep with the seconds left, a ready glow; the ultimate has a
## charge ring and a READY burst; Rewire shows its relay fires left. Casting: tap a slot (or 1 / 2 / 3),
## the valid targets light up in the world (Sim.targets_for: lines, nodes, decks, relays), tap one to
## cast - Ghost Line takes its source node, then its destination. Tap the slot again or empty space to
## cancel (a cancel spends nothing). A tap on a wrong target toasts Sim.cast_check's reason; a cast goes
## through main.node_action("cast", slot index, {"target": t}) (online guests: an order to the host) and
## the slot pulses. While no slot is armed the dock never touches world input (drag-to-send, tap-to-inspect).
## Also: the toast when an enemy's skill hits you (fx "skill" with `affects`), and the note when a map
## without relays swaps a relay map skill for the faction's fallback. Target highlights are drawn here, on a
## screen layer under the HUD panels; the skills' own world effects are fx code, not this file.

const SLOTS := ["active", "map", "ultimate"]
const TAGS := ["ACTIVE", "MAP", "ULTIMATE"]
const SLOT_SIZE := Vector2(196, 78)            # x ui_scale: 225 x 90 px on the phone profile = ~49 pt tall (was 72, 44.9 pt: another nudge, Daniele 0.18.8)
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const TAP_PIXELS := 14.0

var main                                      # main.gd, or a test double: node_action, sim, HUMAN, fraction, paused
var hud                                       # Hud (toasts, inspector) or null in tests
var sim: Sim
var human := "A"
var ui_scale := 1.0
var mobile := false
var accent := Color("18dae8")
var slots: Array = []                         # Slot
var layer: Control                            # target highlights (under the HUD panels)
var hint_panel: PanelContainer                # "SURGE · tap one of your lines" above the dock while armed
var hint_label: Label
var armed := -1                               # the slot being aimed, -1 = none
var src := -1                                 # Ghost Line: the source node picked (then the destination)
var cands: Array = []                         # valid targets right now
var swapped := ""                             # the relay map skill this map replaced ("" = none)
var _cand_t := 0.0
var _press := Vector2.INF
var _t := 0.0
var _prev: Array = []                         # per slot: [cooldown, charge, rewire fires] last frame
var _last_pulse := [-9.0, -9.0, -9.0]


class Slot:
	extends BaseButton
	var dock: SkillDock
	var index := 0
	var id := ""
	var cd := 0.0                              # seconds left (ultimate: seconds of charge left)
	var frac := 0.0                            # active / map: cooldown left 0..1; ultimate: charge 0..1
	var is_ready := false
	var fires := 0                             # Rewire running: relay fires left
	var pulse := 0.0                           # a cast: 1 -> 0
	var burst := 0.0                           # the ultimate turned ready: 1 -> 0
	var warn := 0.0                            # a refused tap: 1 -> 0
	var _key := ""

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

	func _draw() -> void:
		var s := dock.ui_scale
		var w := size.x
		var h := size.y
		var col := dock.accent
		var armed := dock.armed == index
		var ult := index == 2
		var t := dock._t
		var c := minf(12.0 * s, h * 0.2)
		var poly := PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
				Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])
		var fill := Color("040f16f0")
		if armed:
			fill = Color("0b2230f4")
		draw_colored_polygon(poly, fill)
		var edge := poly.duplicate()
		edge.append(poly[0])
		var glow := 0.55 + 0.45 * sin(t * 4.0)
		if is_ready or armed:
			for gw in [18.0, 11.0, 6.0]:
				draw_polyline(edge, Color(col, (0.05 if not armed else 0.08) * (glow if not armed else 1.0)), gw * s, true)
		var rim := Color(col, 0.95) if is_ready else Color("35505e")
		if armed:
			rim = Color.WHITE
		if warn > 0.0:
			rim = rim.lerp(Rules.state_color("warn"), warn)
		draw_polyline(edge, rim, (2.2 if is_ready or armed else 1.2) * s, true)
		# the icon disc
		var r := h * 0.36
		var ic := Vector2(h * 0.5, h * 0.5)
		draw_circle(ic, r, Color(col, 0.14) if is_ready else Color(0.35, 0.45, 0.52, 0.12))
		var tex := ArmyPresets.icon(id)
		var isz := Vector2.ONE * r * 1.36
		if tex:
			var tint := col if is_ready else Color(0.62, 0.7, 0.76, 0.55)
			if armed:
				tint = Color.WHITE
			draw_texture_rect(tex, Rect2(ic - isz / 2.0, isz), false, tint)
		if ult:
			# the charge ring round the disc: dim track, the charge in your colour, full + glowing when ready
			draw_arc(ic, r + 3.0 * s, 0.0, TAU, 48, Color(1, 1, 1, 0.1), 3.0 * s, true)
			if fires > 0 or is_ready:
				draw_arc(ic, r + 3.0 * s, 0.0, TAU, 48, Color(col, 0.95), 3.5 * s, true)
				draw_arc(ic, r + 3.0 * s, 0.0, TAU, 48, Color(col, 0.18 * glow), 9.0 * s, true)
			elif frac > 0.0:
				draw_arc(ic, r + 3.0 * s, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, Color(col, 0.9), 3.5 * s, true)
				var tip := ic + Vector2(cos(-PI / 2.0 + TAU * frac), sin(-PI / 2.0 + TAU * frac)) * (r + 3.0 * s)
				draw_circle(tip, 3.2 * s, Color.WHITE)
			if burst > 0.0:                     # READY: a ring bursting out of the disc
				var k := 1.0 - burst
				draw_arc(ic, r + (4.0 + 26.0 * k) * s, 0.0, TAU, 48, Color(col, burst), (5.0 * burst + 1.0) * s, true)
				draw_arc(ic, r + (2.0 + 14.0 * k) * s, 0.0, TAU, 48, Color(1, 1, 1, burst * 0.8), 2.0 * s, true)
		elif cd > 0.0:
			# the cooldown sweep: the part still cooling stays dark, clockwise from the top
			var pts := PackedVector2Array([ic])
			var n := maxi(3, int(40.0 * frac))
			for k in range(n + 1):
				var a := -PI / 2.0 + TAU * (1.0 - frac) + TAU * frac * float(k) / float(n)
				pts.append(ic + Vector2(cos(a), sin(a)) * r)
			if frac > 0.01:
				draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
			draw_arc(ic, r, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - frac), 40, Color(col, 0.85), 2.5 * s, true)
			_centred(str(int(ceil(cd))), ic, 22, Color.WHITE, true)
		if fires > 0:                            # Rewire: fires left, a badge on the disc
			var bc := ic + Vector2(r * 0.78, -r * 0.78)
			draw_circle(bc, 10.0 * s, col)
			_centred("%d" % fires, bc, 14, Color("06121a"), false)
		# the words: slot tag (+ key on desktop), skill name, status
		var x0 := h + 2.0 * s
		var room := w - x0 - 8.0 * s
		var tag: String = SkillDock.TAGS[index]
		if index == 1 and dock.swapped != "":
			tag = "MAP · NO RELAYS"
		_text(tag, Vector2(x0, 17.0 * s), 12, Color(col, 0.85) if is_ready else Color("7f98a6"), room, UI_FONT)
		if not dock.mobile:
			var kp := Vector2(w - 20.0 * s, 6.0 * s)
			var kr := Rect2(kp, Vector2(14, 15) * s)
			draw_rect(kr, Color(1, 1, 1, 0.08))
			draw_rect(kr, Color(1, 1, 1, 0.3), false, 1.0)
			_centred(str(index + 1), kr.get_center() + Vector2(0, 0.5 * s), 11, Color("b8ced6"), false)
		_text(ArmyPresets.skill_name(id).to_upper(), Vector2(x0, 41.0 * s), 18, Color.WHITE if is_ready or armed else Color("b8c7cf"), room, HEAD_FONT)
		var status := ""
		var sc := Color("8fa6b2")
		if armed:
			status = "TAP A TARGET" if not (dock.src >= 0) else "TAP WHERE IT GOES"
			if fires > 0:
				status = "TAP A RELAY · %d LEFT" % fires
			sc = Color.WHITE
		elif fires > 0:
			status = "FIRE A RELAY · %d LEFT" % fires
			sc = col
		elif is_ready:
			status = "READY"
			sc = col
		elif ult:
			status = "CHARGING · %d s" % int(ceil(cd))
		else:
			status = "COOLDOWN"
		_text(status, Vector2(x0, 61.0 * s), 14, sc, room, UI_FONT)
		if burst > 0.0:                          # the ultimate turned ready: READY rises out of the slot
			var rise := (1.0 - burst) * 16.0 * s
			var rp := Vector2(w / 2.0, -10.0 * s - rise)
			var f := int(22 * s)
			var rsz := HEAD_FONT.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f)
			draw_string_outline(HEAD_FONT, rp - Vector2(rsz.x / 2.0, 0), "READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(6 * s), Color(0, 0, 0, 0.8 * burst))
			draw_string(HEAD_FONT, rp - Vector2(rsz.x / 2.0, 0), "READY", HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color(col.lerp(Color.WHITE, 0.4), minf(1.0, burst * 1.6)))
		if pulse > 0.0:                          # a cast: a white flash through the frame
			draw_colored_polygon(poly, Color(1, 1, 1, 0.28 * pulse))
			draw_polyline(edge, Color(1, 1, 1, pulse), 3.0 * s, true)

	func _centred(txt: String, at: Vector2, fs: int, col: Color, outline: bool) -> void:
		var f := int(fs * dock.ui_scale)
		var sz := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		var p := at + Vector2(-sz.x / 2.0, UI_FONT.get_ascent(f) / 2.0 - 1.0)
		if outline:
			draw_string_outline(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * dock.ui_scale), Color(0, 0, 0, 0.85))
		draw_string(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)

	func _text(txt: String, base: Vector2, fs: int, col: Color, room: float, font: Font) -> void:
		## One line, its font stepped down to fit the room (never below 70 %), baseline at `base`.
		var f := int(fs * dock.ui_scale)
		var least := int(fs * dock.ui_scale * 0.7)
		while f > least and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > room:
			f -= 1
		draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, room, f, col)


class TargetLayer:
	extends Control
	var dock: SkillDock

	func _draw() -> void:
		if dock and dock.armed >= 0:
			dock._draw_targets(self)


# ------------------------------------------------------------------ build
func setup(m, s: Sim, seat: String, scale_ui: float, is_mobile: bool, h = null, targets: Control = null) -> void:
	main = m
	sim = s
	human = seat
	ui_scale = scale_ui
	mobile = is_mobile
	hud = h
	accent = Rules.seat_color(human)
	add_theme_constant_override("separation", int(10 * ui_scale))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(3):
		var b := Slot.new()
		b.dock = self
		b.index = i
		b.custom_minimum_size = (SLOT_SIZE * ui_scale).round()
		b.pressed.connect(press_slot.bind(i))
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
	var st := StyleBoxFlat.new()                  # Hud.panel_style's look (Hud itself needs the Net autoload)
	st.border_color = accent
	st.set_border_width_all(1)
	st.corner_radius_top_left = 8
	st.corner_radius_bottom_right = 8
	st.bg_color = Color(0.02, 0.06, 0.09, 0.92)
	st.set_content_margin_all(8 * ui_scale)
	st.content_margin_left = 14 * ui_scale
	st.content_margin_right = 14 * ui_scale
	hint_panel.add_theme_stylebox_override("panel", st)
	hint_label = Label.new()
	hint_label.add_theme_font_override("font", UI_FONT)
	hint_label.add_theme_font_size_override("font_size", int(17 * ui_scale))
	hint_label.add_theme_color_override("font_color", Color("e6f4f8"))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_label)
	hint_panel.visible = false
	# a relay skill on a map without relays: the faction's fallback plays (Sim._setup_skills); say so once
	var lo = main.LOADOUTS.get(human, {}) if main.get("LOADOUTS") is Dictionary else {}
	var f := str(sim.factions.get(human, "null"))
	var wanted := Rules.skill_slot_id(f, lo if lo is Dictionary else {}, "map")
	if sim.loadouts.has(human) and wanted != sim.skill_id(human, "map"):
		swapped = wanted


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
	for i in range(3):
		var slot: String = SLOTS[i]
		var b: Slot = slots[i]
		var id := sim.skill_id(human, slot)
		var cd := sim.cooldown(human, slot)
		var ch := sim.charge(human) if i == 2 else 0.0
		var fires := sim.rewire_left(human) if i == 2 else 0
		var ready := sim.abilities_on and not sim.over and (cd <= 0.0 or fires > 0) and id != ""
		var frac := 0.0
		if i == 2:
			frac = clampf(ch, 0.0, 1.0) if cd > 0.0 else 1.0
		elif cd > 0.0:
			frac = clampf(cd / maxf(float(Rules.SKILLS.get(id, {}).get("cd", 1.0)), 0.01), 0.0, 1.0)
		var p: Array = _prev[i]
		# a cast happened (ours, or a guest's order the host accepted): the cooldown jumped up, the charge
		# was spent, or a Rewire fire was used
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
		var rewiring := armed == 2 and sim.rewire_left(human) > 0
		if main.paused or sim.over or not sim.abilities_on or (not rewiring and sim.cooldown(human, slot) > 0.0):
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
	if _kind() == "vat_to_node" and src >= 0:
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
	if armed == 2 and id == "rewire" and sim.rewire_left(human) > 0:
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
	var rewiring := i == 2 and id == "rewire" and sim.rewire_left(human) > 0
	if not sim.abilities_on or not (rewiring or sim.cooldown(human, slot) <= 0.0):
		_refuse(i, sim.cast_check(human, slot, null))
		return
	var kind := "relay" if rewiring else str(Rules.SKILLS[id]["target"])
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
	if why != "":
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
	hint_panel.position = Vector2((vp.x - hint_panel.size.x) / 2.0, position.y - hint_panel.size.y - 8.0 * ui_scale)


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
	## The deck under a tap (screen distance to its centre line), lit decks first.
	var reach := (20.0 if not mobile else 30.0) * ui_scale
	for pass_n in range(2):
		var best := -1
		var best_d := reach
		var pool: Array = cands if pass_n == 0 else range(sim.edges.size())
		for ei in pool:
			var pts := _deck_px(int(ei), cam)
			for k in range(pts.size() - 1):
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]))
				if d < best_d:
					best_d = d
					best = int(ei)
		if best >= 0:
			return best
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
	var cam: Camera3D = main.cam
	if cam == null:
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
			if src >= 0 and sim._node_ok(src):
				var ss := _node_screen(src, cam)
				_ring(ci, ss[0], float(ss[1]) + 6.0 * s, Color.WHITE, 1.0, true)
				_label(ci, "FROM", (ss[0] as Vector2) + Vector2(0, -float(ss[1]) - 14.0 * s), Color.WHITE)
			for c in cands:
				var jam: bool = c is Array
				var id: int = c[0] if jam else int(c)
				if id == src:
					continue
				var ns := _node_screen(id, cam)
				var cc := Rules.state_color("build") if jam else col
				_ring(ci, ns[0], float(ns[1]) + 6.0 * s, cc, a, false)
				if jam:
					_label(ci, "JAM", (ns[0] as Vector2) + Vector2(0, -float(ns[1]) - 14.0 * s), cc)


func _ring(ci: CanvasItem, c: Vector2, r: float, col: Color, a: float, solid: bool) -> void:
	var s := ui_scale
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.22 * a), 12.0 * s, true)
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.95 if solid else 0.75 + 0.25 * a), 2.5 * s, true)
	for k in range(4):                          # four ticks turning round the ring: "tap me"
		var ang := _t * 1.6 + TAU * k / 4.0
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(c + d * (r + 5.0 * s), c + d * (r + 13.0 * s), Color(col, 0.95), 3.0 * s, true)


func _label(ci: CanvasItem, txt: String, at: Vector2, col: Color) -> void:
	var f := int(14 * ui_scale)
	var sz := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	var p := at - Vector2(sz.x / 2.0, 0)
	ci.draw_string_outline(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * ui_scale), Color(0, 0, 0, 0.9))
	ci.draw_string(UI_FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


# ------------------------------------------------------------------ enemy casts
func on_event(ev: Dictionary) -> void:
	## An fx "skill" event: a rival's skill that touches you gets a toast (emblem + faction via "seat X", the
	## skill's name, what it does to you). Private events (Ghost Line, echoes) are for their owner only.
	if ev.has("private") and str(ev["private"]) != human:
		return
	var seat := str(ev.get("seat", ""))
	if seat == "" or seat == human or sim.allied(seat, human):
		return
	var hit: Array = ev.get("affects", []) if ev.get("affects", []) is Array else []
	if not human in hit:
		return
	var id := str(ev.get("id", ""))
	var what := ""
	match id:
		"scorch": what = "your lines on a deck are burning"
		"mire": what = "your lines are slowed"
		"demolish": what = "a deck falls in %d s" % int(Rules.SKILLS["demolish"]["warn"])
		"bypass": what = "a relay holds both states"
		"relay_hack": what = "your relay is jammed" if ev.get("target") is Array else "your relay fires"
		"rewire": what = "your relay fires" if ev.has("fire") else "their lines speed up"
		"echo_split": what = "decoy lines on the move"
		"core_meltdown": what = "your garrison melts"
	_toast("seat %s cast %s%s" % [seat, ArmyPresets.skill_name(id).to_upper(), (" - " + what) if what != "" else ""], "warn")
