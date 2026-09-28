class_name Hud
extends CanvasLayer
## The match interface (2.0): Alpha 11's chrome and layout brought over in full - top bar (emblem,
## your total, timer, rivals, strength bar), pause menu, side send panel with the fractions and the
## selected vat's count, node badges floating beside their nodes (count - the owner's emblem in the
## owner's colour instead on enemy nodes in SIEGE or when enemy counts are hidden -, emblem, tier,
## relay state, build bar), the
## ring inspector with costed actions, the skill dock (SkillDock: ACTIVE / MAP / ULTIMATE when ABILITIES
## are on; its target highlights sit on a layer over the badges, under the panels),
## placed messages (HudCallouts: at the node / deck / chip / slot they are about - no notification box), the
## Last Stand status line and drop order, the results panel with match stats, and the debug panel. A human seat
## is named by the player's name wherever a seat shows (main.seat_who), an AI seat by faction and AI level.
## TUTORIAL (TUTORIAL-DESIGN.md §6, reveal as you go): reveal(keys) hides every part a lesson has not reached
## yet (TutorialDirector.ALL_KEYS) - by not showing it, never by disabling a control; outside the tutorial
## nothing is gated. Rect getters for the coach's spotlight: action_rect, send_button_rect, badge_rect,
## dock_slot_rect; extra_ui_rects (the coach card) count as UI for pointer_over_ui.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
# Alpha 18: the relay symbols (Rules.RELAY_GLYPH) are not in Rajdhani, and a browser has no system font to
# fall back on (they drew as empty boxes on the web build): DejaVu Sans Mono supplies them.
const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSansMono.woff2")

var main: Node3D
var sim: Sim
var mobile := false
var human := "A"
var root: Control
var top_panel: PanelContainer
var stats_label: Label                 # 0.19.2 spec H6: the clock, centred in the new top bar
var top_left: HBoxContainer            # your side (you first, then teammates)
var top_right: HBoxContainer           # every other team, grouped with a wider gap between groups
var top_chips := {}                    # seat -> {panel, emblem, label}
var pause_button: Button
var side_panel: PanelContainer
var side_box: VBoxContainer
var count_label: Label
var badges := {}                     # node id -> {panel, label, sub, emblem, build, owner, count_w, sub_w, look}
var _badge_px := Vector2.ZERO        # the one badge size on this screen (BADGE_SIZE x ui_scale)
var badge_layer: BadgeLayer          # HUD pass: draws every badge, one pass per kind (see setup)
var _badge_model: Control            # the badges' layout nodes: hidden, never drawn
var inspector: Control
var inspector_id := -1
var inspector_label: Label
var inspector_emblem: TextureRect       # the header: owner's emblem + faction name in the owner's colour
var inspector_who: Label
var inspector_first: Label
var inspector_progress: ProgressBar
var inspector_actions: Array = []
var notices: Control                   # HUD pass: no stack any more - only where the old one began (a mission's
                                       # strip still pushes it down: note_line's lines start under it)
var banner: Label
var _banner_time := 0.0
var status_label: Label                # Last Stand status under the top bar
var hint: Label
var map_title: Label
var dock: SkillDock
var skill_targets: Control             # the dock's target highlights: over the badges, under the panels
var overlay: HudOverlay                # 0.19.0: monster reach, halo rings, relay-outcome preview, danger symbols
var action_buttons: Dictionary = {}    # stable action name -> the inspector's Button (tutorial spotlight, spec I)
var switch_ring: Control                # 0.19.0: the SWITCH button's READY / cooldown ring (SwitchRing)
# UI (Alpha 21): the in-match screens are full-screen layers MatchScreens draws into (SCREEN-SYSTEM 17-20)
var end_panel: Control                 # VICTORY / DEFEAT, and its MATCH DETAILS page
var pause_panel: Control
var out_panel: Control                 # 0.19.2 spec H7: "YOU'RE OUT" - SPECTATE / MAIN MENU (online: LEAVE ROOM)
var reconnect_panel: Control           # UI (Alpha 21): CONNECTION INTERRUPTED - a guest's silent match host
var _screens_vp := Vector2.ZERO        # the canvas size they were built for (a rotation rebuilds them)
var spectate_button: Button             # stays after SPECTATE: a small way back to the menu while watching
var _out_shown := false                 # this match's panel has already been offered once
var monster_icon: MonsterIcon           # 0.19.2 spec H1: floats above your ready hub; tap to arm LAUNCH
var rotate_hint: Label
var debug_button: Button
var chat_button: Button
var _chat_poll := 0.0
var debug_panel: PanelContainer
var margins := Vector4(16, 12, 16, 12)
var _last_fps_print := 0.0
var version_label: Label
var ui_scale := 1.0
# --- TUTORIAL reveal set (TUTORIAL-DESIGN.md §6) ---
var gated := false                     # a lesson is on: only `revealed` keys show
var revealed := {}                     # key -> true
var extra_ui_rects: Array = []         # the coach card / completion screen: taps there never reach the map


static func panel_style(color: Color = Color("276578")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("17222bf5")
	s.border_color = color
	s.set_border_width_all(1)
	s.corner_radius_top_left = 8
	s.corner_radius_bottom_right = 8
	s.set_content_margin_all(16)
	return s


static func badge_style(color: Color) -> StyleBoxFlat:
	## Alpha 19 (Daniele: "make them a bit transparent so they don't overpower the look of what's near
	## them"): a see-through box and a softer rim; the text keeps its black outline, so it stays crisp.
	var s := panel_style(Color(color, 0.8))
	s.bg_color = Color(0.063, 0.078, 0.098, 0.42)
	s.set_corner_radius_all(9)
	s.set_content_margin_all(0)
	s.set_border_width_all(1)
	return s


const EMBLEM_TINT := preload("res://shaders/emblem_tint.gdshader")
const BADGE_EMBLEM := Vector2(12, 10)          # under a BRAWL count (Alpha 11)
const BADGE_EMBLEM_OWNER := Vector2(18, 18)    # in place of a hidden count: about the count's own height
# Alpha 19: every node badge is one fixed box (x ui_scale) sized for its largest normal content - a
# 3-digit count over an emblem and a short sub line; longer text steps its font down, then clips.
const BADGE_SIZE := Vector2(44, 33)
const BADGE_COUNT_FONT := 16
const BADGE_SUB_FONT := 9
const BADGE_PAD := 3.0                         # side margin inside the box
# 0.19.2 spec H6: the top bar's fixed sizes (fits 844 x 390 pt with up to 6 seats: 1 (you) + 5 rivals,
# ~64 px a chip, well under half of 844 either side of the clock)
const TOP_CHIP_W := 58.0
const TOP_CHIP_H := 32.0
const TOP_CHIP_GAP := 6.0
const TOP_CLOCK_W := 78.0
const TOP_EMBLEM := Vector2(16, 16)
const TOP_NAME_W := 64.0               # HUD pass: a human chip's name, at most this wide (then an ellipsis)


static func tint_emblem(rect: TextureRect, color: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = EMBLEM_TINT
	m.set_shader_parameter("tint", color)
	rect.material = m
	rect.modulate = Color.WHITE


static func emblem_texture(faction: String) -> Texture2D:
	## A faction emblem for the HUD's small spots (badges, inspector, toasts): the race emblems v2, from their one
	## source (UiKit.emblem_mip - mipmapped, the small levels lifted), tinted in the seat colour by tint_emblem.
	return UiKit.emblem_mip(faction)


func seat_emblem(seat: String, size_px: Vector2) -> TextureRect:
	## Daniele: "don't use A B and C but use emblems in the color of the owner; the emblem identifies
	## their chosen race" - the owner's faction emblem, tinted in the owner's seat colour.
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.custom_minimum_size = size_px * ui_scale
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if seat != "":
		r.set_meta("seat", seat)
		r.texture = emblem_texture(str(sim.factions.get(seat, "null")))
		tint_emblem(r, Rules.seat_color(seat))
	return r


func text_label(text: String, size_value: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", int(size_value * ui_scale))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func button(text: String, action: Callable, width: float = 130, height: float = -1.0, font := 19) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", UI_FONT)
	b.text = text
	b.custom_minimum_size = Vector2(width * ui_scale, (height if height > 0 else (52.0 if not mobile else 78.0)) * ui_scale)
	b.add_theme_stylebox_override("normal", panel_style())
	b.add_theme_stylebox_override("hover", panel_style(Rules.seat_color(human)))
	var pressed := panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", panel_style(Color("3a4650")))
	var focus := panel_style(Color.WHITE)
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_disabled_color", Color("a6b2bb"))
	b.add_theme_font_size_override("font_size", int(font * ui_scale))
	if action.is_valid():
		b.pressed.connect(func(): action.call_deferred())
	return b


func style_panel(p: Control, accent: Color = Color("276578")) -> void:
	p.add_theme_stylebox_override("panel", panel_style(accent))


func _seat_groups() -> Array:
	## [[you, your teammates...], [a rival team/seat], ...] (0.19.2 spec H6: "team modes group chips by
	## team"; FFA - no sim.teams entries - puts every rival in its own singleton group).
	var has_teams: bool = sim.teams.has(human)
	var mine: int = int(sim.teams.get(human, -999))
	var my_group := [human]
	var others := {}
	var order := []
	for seat in sim.factions.keys():
		if seat == human:
			continue
		if has_teams and int(sim.teams.get(seat, -998)) == mine:
			my_group.append(seat)
		else:
			var key = sim.teams[seat] if sim.teams.has(seat) else seat
			if not others.has(key):
				others[key] = []
				order.append(key)
			others[key].append(seat)
	var groups := [my_group]
	for k in order:
		groups.append(others[k])
	return groups


func _build_top_chip(seat: String, into: HBoxContainer, mine: bool) -> void:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(TOP_CHIP_W, TOP_CHIP_H) * ui_scale
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.09, 0.8 if mine else 0.62)
	st.border_color = Rules.seat_color(seat)
	st.set_border_width_all(int((2 if mine else 1) * ui_scale))
	st.set_corner_radius_all(int(8 * ui_scale))
	st.set_content_margin_all(2 * ui_scale)
	chip.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(4 * ui_scale))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var emb := seat_emblem(seat, TOP_EMBLEM)
	row.add_child(emb)
	# HUD pass (Daniele: "if the user is a human his name needs to be shown ... instead of his faction only"): a
	# human seat's chip carries the player's name between the emblem (the faction) and the strength, cut to
	# TOP_NAME_W; AI seats keep the emblem alone. Yours is the highlighted chip, first on the left.
	var who: Dictionary = main.seat_who(seat) if main.has_method("seat_who") else {}
	if bool(who.get("human", false)) and str(who.get("name", "")) != "":
		var nm := text_label(str(who["name"]), 15, Color("f2fbff") if mine else Color("c8e6ee"))
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(minf(TOP_NAME_W, UI_FONT.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * ui_scale)).x / ui_scale + 2.0) * ui_scale, 0)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		chip.custom_minimum_size.x += nm.custom_minimum_size.x + 4.0 * ui_scale
	var lbl := text_label("000", 15)
	lbl.add_theme_font_override("font", SYMBOL_FONT)      # monospace: the digits never shift the chip
	lbl.custom_minimum_size = Vector2(28 * ui_scale, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(lbl)
	into.add_child(chip)
	top_chips[seat] = {"panel": chip, "emblem": emb, "label": lbl}


# ------------------------------------------------------------------ build
func setup(m: Node3D) -> void:
	var ui_font: FontFile = UI_FONT                        # shared resource: every HUD label gets the fallback
	if ui_font.fallbacks.is_empty():
		ui_font.fallbacks = [SYMBOL_FONT]
	main = m
	sim = m.sim
	mobile = m.mobile
	human = m.HUMAN
	ui_scale = 1.15 if mobile else 1.0
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var accent := Rules.seat_color(human)
	# badges first (under everything else). Alpha 19 (Daniele: "they all look different size - we should
	# make them have fixed size and have their inside content never get out of the box boundaries"):
	# one fixed box per ui_scale, its parts placed by hand (_place_badge) and clipped to it.
	# HUD pass (the stretch, Alpha 21 OPT-RENDER: the badges were ~70 of the HUD's ~165 draw calls): these
	# nodes are the layout only - under a hidden holder, never drawn; BadgeLayer draws every badge from them,
	# one pass per kind (boxes, bars, emblems, words), so the 2D renderer batches each pass.
	_badge_px = (BADGE_SIZE * ui_scale).round()
	badge_layer = BadgeLayer.new()
	root.add_child(badge_layer)                           # where the badges always drew: under everything else
	_badge_model = Control.new()
	_badge_model.visible = false
	_badge_model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_badge_model)
	var sb_bg := StyleBoxFlat.new()                         # shared by every build bar
	sb_bg.bg_color = Color(0, 0, 0, 0.55)
	var bb_fill := StyleBoxFlat.new()
	bb_fill.bg_color = Rules.state_color("build")
	for n in sim.nodes:
		var badge := Panel.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.clip_contents = true
		badge.custom_minimum_size = _badge_px
		badge.size = _badge_px
		var l := text_label("", BADGE_COUNT_FONT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_child(l)
		var sub := text_label("", BADGE_SUB_FONT, Color("c8e6ee"))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub.clip_text = true
		sub.add_theme_constant_override("outline_size", 2)  # crisp on the see-through box
		sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		badge.add_child(sub)
		var emblem := seat_emblem("", BADGE_EMBLEM)     # classic: Alpha 11's faction emblem under the count;
		emblem.visible = false                          # the owner's emblem in the count's place where it is hidden
		badge.add_child(emblem)
		var build_bar := ProgressBar.new()
		build_bar.show_percentage = false
		build_bar.custom_minimum_size = Vector2.ZERO
		build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		build_bar.add_theme_stylebox_override("fill", bb_fill)
		build_bar.add_theme_stylebox_override("background", sb_bg)
		var inset := 7.0 * ui_scale                     # clear of the rounded corners
		build_bar.position = Vector2(inset, _badge_px.y - 4.0 * ui_scale)
		build_bar.size = Vector2(_badge_px.x - 2.0 * inset, 2.0 * ui_scale)
		badge.add_child(build_bar)
		_badge_model.add_child(badge)
		badges[n["id"]] = {"panel": badge, "label": l, "sub": sub, "emblem": emblem, "build": build_bar, "owner": "?",
				"count_w": 0.0, "sub_w": 0.0, "sub_small": false, "wide": false, "shape": "", "look": -1}
	badge_layer.setup(self)
	skill_targets = SkillDock.new_layer()
	root.add_child(skill_targets)
	overlay = HudOverlay.new()
	root.add_child(overlay)
	overlay.setup(main, sim, self, human, ui_scale)
	# top bar (0.19.2 spec H6, Daniele: "not fixed, keeps moving ... should be centred ... for
	# multiplayer you'd want to see what each player is doing, rethink it"): a fixed-width bar centred
	# at the top - the clock in the middle (monospace, so it never shifts), one chip per seat either
	# side (faction emblem in the seat colour + strength, also monospace), your own chip first and
	# highlighted, team modes grouped with a wider gap between groups. TUTORIAL: "topbar" gates the
	# whole bar, "strength" the chips alone (clock-only in the early lessons, as before).
	top_panel = PanelContainer.new()
	style_panel(top_panel, accent)
	root.add_child(top_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(10 * ui_scale))
	top_panel.add_child(bar)
	top_left = HBoxContainer.new()
	top_left.add_theme_constant_override("separation", int(TOP_CHIP_GAP * ui_scale))
	bar.add_child(top_left)
	stats_label = text_label("00:00", 22)
	stats_label.add_theme_font_override("font", SYMBOL_FONT)   # monospace digits: the clock never shifts
	stats_label.custom_minimum_size = Vector2(TOP_CLOCK_W * ui_scale, 0)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(stats_label)
	top_right = HBoxContainer.new()
	top_right.add_theme_constant_override("separation", int(TOP_CHIP_GAP * ui_scale))
	bar.add_child(top_right)
	var groups := _seat_groups()
	for gi in range(groups.size()):
		var g: Array = groups[gi]
		var into := top_left if gi == 0 else top_right
		if gi > 1:
			var spacer := Control.new()                    # a wider gap between rival team groups
			spacer.custom_minimum_size = Vector2(10 * ui_scale, 1)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top_right.add_child(spacer)
		for seat in g:
			_build_top_chip(seat, into, seat == human)
	status_glow = Panel.new()                         # HUD pass: the Last Stand announcement pulses its own line
	var sg := panel_style(Rules.state_color("warn"))
	sg.set_border_width_all(2)
	sg.bg_color = Color(0.25, 0.03, 0.05, 0.72)
	status_glow.add_theme_stylebox_override("panel", sg)
	status_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_glow.visible = false
	root.add_child(status_glow)
	status_label = text_label("", 18, Color("ffb0b0"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)
	pause_button = button("PAUSE", pause_menu, 100)
	UiSkin.button(pause_button, main.SEAT_FACTIONS[human])
	root.add_child(pause_button)
	# side command panel (Alpha 11: 100/75/50/25 + the selected vat's count)
	side_panel = PanelContainer.new()
	style_panel(side_panel)
	root.add_child(side_panel)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	side_panel.add_child(side_box)
	var send_title := text_label("SEND", 15, Color("c8e6ee"))
	send_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_box.add_child(send_title)
	var group := ButtonGroup.new()
	for f in [1.0, 0.75, 0.5, 0.25]:
		var b := button("%d%%" % int(f * 100), Callable(), 100, 66 if not mobile else 78, 26)   # 78: the phone-tuned default height (>= 44 pt), the send row was a touch under it
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = is_equal_approx(f, main.fraction)
		UiSkin.button(b, main.SEAT_FACTIONS[human])         # Alpha 11's kit buttons
		var sel := UiSkin.box("Buttons/%s/primary-default" % UiSkin.faction(main.SEAT_FACTIONS[human]))
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_color_override("font_pressed_color", Color("08141c"))
		b.pressed.connect(func(): main.fraction = f)
		b.gui_input.connect(func(event):                  # slide a finger over the buttons to pick
			if (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT) or event is InputEventScreenDrag:
				b.button_pressed = true
				main.fraction = f)
		side_box.add_child(b)
	count_label = text_label("DRAG A VAT", 14, accent)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_box.add_child(count_label)
	# bottom: map title, hint, ability dock, version
	map_title = text_label(str(main.map.get("name", "")).to_upper(), 20)
	root.add_child(map_title)
	hint = text_label(_hint_text(), 14, Color("d0dceb"))
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.visible = not touch_ui()                      # (desktop words and the 1 2 3 keys: never on a touch screen)
	root.add_child(hint)
	dock = SkillDock.new()                            # SKILLS 2.0: ACTIVE / MAP / ULTIMATE, only when abilities are on
	root.add_child(dock)
	dock.setup(main, sim, human, ui_scale, mobile, self, skill_targets)
	dock.keys = not touch_ui()
	dock.visible = sim.abilities_on
	root.add_child(dock.hint_panel)
	version_label = text_label("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], 14, Color(1, 1, 1, 0.5))
	root.add_child(version_label)
	notices = Control.new()                           # (see its var: a position only, never drawn)
	notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notices)
	callouts = HudCallouts.new()                      # HUD pass: every message, placed where it belongs
	callouts.ui_scale = ui_scale
	root.add_child(callouts)
	banner = text_label("", 44, Color("ffd6d6"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.visible = false
	var bs := panel_style(Rules.state_color("warn"))    # the Last Stand banner in the UI's own frame
	bs.set_border_width_all(2)
	bs.set_content_margin_all(18 * ui_scale)
	banner.add_theme_stylebox_override("normal", bs)
	root.add_child(banner)
	_build_debug()
	rotate_hint = text_label("Rotate your phone\nOoze Syndicate plays in landscape", 44)
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.01, 0.012, 0.018, 0.94)
	rotate_hint.add_theme_stylebox_override("normal", bg)
	rotate_hint.visible = false
	root.add_child(rotate_hint)
	end_panel = _screen_layer()
	pause_panel = _screen_layer()
	out_panel = _screen_layer()
	reconnect_panel = _screen_layer()
	spectate_button = button("LEAVE ROOM" if main.online else "MAIN MENU", main.to_menu, 170, 48, 16)
	UiKit.style_button(spectate_button, "secondary", _my_faction())   # UI: the screens' language while watching
	spectate_button.add_theme_font_override("font", UiKit.HEAD)
	spectate_button.visible = false
	root.add_child(spectate_button)
	monster_icon = MonsterIcon.new()
	monster_icon.custom_minimum_size = Vector2(48, 48) * ui_scale   # 0.20.1: >= the 44 pt tap minimum (was 40)
	monster_icon.size = monster_icon.custom_minimum_size
	monster_icon.ui_scale = ui_scale
	monster_icon.visible = false
	monster_icon.pressed.connect(func():
		var hub := _human_hub_id()
		if main.monster_from == hub:
			main.monster_from = -1
		else:
			main.monster_from = hub
			note_monster_hint())
	root.add_child(monster_icon)


func touch_ui() -> bool:
	## Match feel (Daniele's phone screenshot, 2026-09-28: the dock's "1 / 2 / 3" on a phone): keyboard hints show only
	## where there is a keyboard - not on a phone / tablet build, a --mobile run, nor a touch browser that reports
	## neither (PerfProfile.is_phone: web + a touch screen), where main.mobile stays false.
	return mobile or PerfProfile.is_phone()


func _hint_text() -> String:
	return "Drag to send  ·  Tap a node to inspect  ·  Double-tap to upgrade (a relay: its button)  ·  Tap your ready monster to launch it" + ("  ·  1 2 3: skills" if sim.abilities_on else "")


func layout(vp: Vector2, m: Vector4) -> void:
	margins = m
	_ins_vp = Vector2(-1, -1)                         # the safe area is read again (a rotation, a new window size)
	top_panel.size = top_panel.get_combined_minimum_size()
	top_panel.position = Vector2((vp.x - top_panel.size.x) / 2.0, m.y)   # 0.19.2 spec H6: centred, not left-hung
	status_label.size = Vector2(maxf(top_panel.size.x, 260 * ui_scale), 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2((vp.x - status_label.size.x) / 2.0, m.y + top_panel.size.y + 2)
	pause_button.size = pause_button.custom_minimum_size
	pause_button.position = Vector2(vp.x - m.z - pause_button.size.x, m.y)
	side_panel.size = side_panel.get_combined_minimum_size()
	var side_y := (vp.y - side_panel.size.y) / 2.0
	var top_bottom := top_panel.position.y + top_panel.size.y + 34.0   # below the top bar and status line
	side_y = maxf(side_y, top_bottom)
	side_panel.position = Vector2(m.x, side_y)          # send controls on the LEFT, like Alpha 11 (Daniele)
	map_title.position = Vector2(m.x + 8, vp.y - m.w - 30 * ui_scale)
	hint.size = Vector2(vp.x * 0.5, 20)
	hint.position = Vector2(vp.x * 0.5 - hint.size.x / 2.0, vp.y - m.w - 18)
	dock.size = dock.get_combined_minimum_size()
	dock.position = Vector2(vp.x * 0.5 - dock.size.x / 2.0, vp.y - m.w - dock.size.y - (26 if not mobile else 8))
	dock._place_hint()
	version_label.size = version_label.get_combined_minimum_size()
	version_label.position = Vector2(vp.x - m.z - version_label.size.x, vp.y - m.w - version_label.size.y)
	# HUD pass: the old stack's top-left corner stays as a mark only (a mission's strip pushes it down; note_line
	# starts under whichever is lower)
	notices.size = Vector2.ZERO
	notices.position = Vector2(m.x + side_panel_width() + 14.0 * ui_scale, top_panel.position.y + top_panel.size.y + 8.0 * ui_scale)
	banner.size = banner.get_combined_minimum_size()
	banner.position = Vector2((vp.x - banner.size.x) / 2.0, vp.y * 0.26)
	if debug_button:
		debug_button.position = Vector2(vp.x - m.z - debug_button.size.x, pause_button.position.y + pause_button.size.y + 8.0)   # under PAUSE, off the map
		var dp_y := debug_button.position.y + debug_button.size.y + 8.0
		var dp_natural := debug_panel.get_combined_minimum_size()
		# clamp to what's actually left on screen (phones: the panel used to run off the bottom) - the
		# ScrollContainer in _build_debug() lets the panel be shorter than its buttons and scroll them
		debug_panel.size = Vector2(dp_natural.x, minf(dp_natural.y, vp.y - dp_y - 10.0))
		debug_panel.position = Vector2(vp.x - m.z - debug_panel.size.x, dp_y)
	if chat_button:
		chat_button.position = Vector2(vp.x - m.z - chat_button.size.x, pause_button.position.y + pause_button.size.y + 8.0)   # Debug's slot (hidden online)
	rotate_hint.size = vp
	rotate_hint.visible = vp.y > vp.x
	if vp != _screens_vp and (end_panel.visible or pause_panel.visible or out_panel.visible):
		_screens_vp = vp                                # UI: a rotation / resize lays the open screen out again
		if end_panel.visible:
			_build_end()
		elif pause_panel.visible:
			pause_menu()
		elif out_panel.visible:
			show_out_panel()
	spectate_button.size = spectate_button.custom_minimum_size
	spectate_button.position = Vector2(m.x, vp.y - m.w - spectate_button.size.y - 8.0)


func side_panel_width() -> float:
	return side_panel.size.x if side_panel else 0.0


func top_used() -> float:
	return margins.y + (top_panel.size.y if top_panel else 0.0) + 34.0


func bottom_used() -> float:
	var used := margins.w + 30.0 * ui_scale              # the map title and hint line (badges are fitted by the camera)
	if dock and dock.visible:                             # the skill dock never covers the map: the camera fits above it
		used = maxf(used, root.get_viewport_rect().size.y - dock.position.y + 6.0)
	return used


func pointer_over_ui(p: Vector2) -> bool:
	for c in [top_panel, pause_button, side_panel, dock, debug_button, chat_button, monster_icon, spectate_button]:
		if c and c.visible and c.get_global_rect().has_point(p):
			return true
	if debug_panel and debug_panel.visible and debug_panel.get_global_rect().has_point(p):
		return true
	for r in extra_ui_rects:                          # TUTORIAL: the coach card / completion screen
		if (r as Rect2).has_point(p):
			return true
	if is_instance_valid(inspector):
		for a in inspector_actions:
			if (a["button"] as Button).get_global_rect().has_point(p):
				return true
		if inspector.has_meta("close") and (inspector.get_meta("close") as Button).get_global_rect().has_point(p):
			return true
	return end_panel.visible or pause_panel.visible or out_panel.visible


func badge_at(p: Vector2) -> int:
	## Alpha 11: badges are explicit, unobstructed selection targets. A direct hit wins; otherwise the
	## nearest badge whose grown (thumb-sized on mobile) rect holds the point, so overlapping grown
	## rects of neighbouring badges never pick the wrong node.
	var pad := 20.0 if mobile else 4.0
	var best := -1
	var best_d := INF
	for id in badges:
		var panel: Control = badges[id]["panel"]
		if not panel.visible:
			continue
		var r := panel.get_global_rect()
		if r.has_point(p):
			return id
		if r.grow(pad).has_point(p):
			var d := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)).length()
			if d < best_d:
				best_d = d
				best = id
	return best


# ------------------------------------------------------------------ per frame
func sync(dt: float, cam: Camera3D) -> void:
	if main.online:
		_chat_poll -= dt
		if _chat_poll <= 0.0:
			_chat_poll = 0.5
			var n := Net.chat_unread()
			chat_button.text = "Chat (%d)" % n if n > 0 else "Chat"
		_reconnect_watch()
	# 0.19.2 spec H6: the clock, centred, never shifts; a chip per seat either side, eliminated seats
	# greyed. "topbar" gates the whole bar, "strength" the chips alone (clock-only in early lessons).
	top_panel.visible = shows("topbar")
	stats_label.text = "%02d:%02d" % [int(sim.time) / 60, int(sim.time) % 60]
	var show_chips := shows("strength")
	top_left.visible = show_chips
	top_right.visible = show_chips
	if show_chips:
		for seat in top_chips:
			var c: Dictionary = top_chips[seat]
			var out := _seat_out(seat)
			(c["label"] as Label).text = "%03d" % Rules.shown(sim.seat_strength(seat))
			(c["panel"] as Control).modulate = Color(1, 1, 1, 0.4) if out else Color.WHITE
	if not shows("status_line"):
		status_label.text = ""
	elif sim.very_last_stand_active:
		status_label.text = ("VERY LAST STAND · a node drops every %d s" % int(round(sim.very_last_stand_gap))
				if sim.very_last_stand_gap > 0.0 else "VERY LAST STAND · one node stands - conquest decides")
	elif sim.last_stand_active:
		var next := ""
		var pending: int = sim.last_stand_waves.size() if sim.v3 else sim.last_stand_order.size()
		if sim.v3 and not sim.last_stand_warn.is_empty():
			next = "RING %d DROPPING · next node in %d s (%d left)" % [sim.last_stand_next, int(ceil(sim.last_stand_warn_t)), sim.last_stand_queue.size()]
		elif sim.last_stand_warn_node >= 0:
			next = "NODE %d FALLS IN %d s" % [sim.last_stand_warn_node, int(ceil(sim.last_stand_warn_t))]
		elif sim.last_stand_next < pending:
			next = "next drop in %d s" % int(ceil(maxf(sim._next_wave_at - sim.time, 0.0)))
		else:
			next = ("the last ring stands" if sim.v3 else "the final node stands") + " - conquest decides"
		status_label.text = "LAST STAND · %s · %s" % [sim.last_stand_method.to_upper(), _ls_how if _ls_pulse > 0.0 and _ls_how != "" else next]
	elif Rules.last_stand and not sim.over and sim.time > Rules.LAST_STAND_TIME - 15.0 and sim.time < Rules.LAST_STAND_TIME and not (sim.v3 and (sim._map_last_stand.get("methods", []) as Array).is_empty()):
		# mirrors sim._step_last_stand: no countdown when the Last Stand is off, over, or the map has none
		status_label.text = "LAST STAND in %d s" % int(ceil(Rules.LAST_STAND_TIME - sim.time))
	else:
		status_label.text = ""
	var source: int = main.drag_from if main.drag_from >= 0 else main.selected
	if source >= 0 and sim.nodes[source]["owner"] == human:
		count_label.text = "%d / %d" % [Rules.shown(floorf(sim.nodes[source]["units"] * main.fraction)), Rules.shown(sim.nodes[source]["units"])]
	else:
		count_label.text = "DRAG A VAT"
	_badges(cam)
	badge_layer.refresh()
	overlay.sync(dt)
	_sync_monster_icon(cam)
	_check_out()
	if dock.visible:
		dock.sync(dt)
	_refresh_inspector(cam)
	_sync_status_pulse(dt)
	if not callouts.items.is_empty():
		callouts.sync(dt, cam, callout_area(root.get_viewport_rect().size), callout_blocked())
	if _banner_time > 0.0:
		_banner_time -= dt
		banner.modulate.a = clampf(_banner_time / 1.5, 0.0, 1.0)
		if _banner_time <= 0.0:
			banner.visible = false
	_last_fps_print += dt
	if debug_panel.visible and _last_fps_print > 5.0:
		_last_fps_print = 0.0
		print("FPS %d  draw calls %d  triangles %d  hordes %d  t=%.0f" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), sim.hordes.size(), sim.time])


func _badges(cam: Camera3D) -> void:
	var order_shown := sim.last_stand_active
	for n in sim.nodes:
		var b: Dictionary = badges[n["id"]]
		var panel: Control = b["panel"]
		if sim.collapsed.get(n["id"], false):
			panel.visible = false
			continue
		if sim.is_warned(n["id"]):                    # 0.19.0: the floating danger symbol replaces the badge
			panel.visible = false                     # circle instead (HudOverlay._draw_danger_symbols)
			continue
		panel.visible = true
		var owner: String = n["owner"]
		if b["owner"] != owner:
			b["owner"] = owner
			var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			panel.add_theme_stylebox_override("panel", badge_style(col))
			(b["label"] as Label).add_theme_color_override("font_color", col if owner != "" else Color("d8e0e8"))
		var label: Label = b["label"]
		var sub: Label = b["sub"]
		var classic := not Rules.bridge_combat
		var masked := not (owner == "" or sim.allied(owner, human) or (classic and not Rules.hide_enemy_counts and shows("rival_counts")))   # Brawl = Alpha 11: every count, unless hidden (TUTORIAL: from L3)
		label.visible = not masked
		var inner := _badge_px.x - 2.0 * BADGE_PAD * ui_scale
		var has_allies := sim.allied_units(n) > 0.0001   # GAME-RULES sec11: team members see total + own
		if not masked:
			var shown_units: float = sim.garrison_total(n) if has_allies else n["units"]
			b["count_w"] = _fit_text(label, str(Rules.shown(shown_units)), BADGE_COUNT_FONT, inner, b["count_w"])
		# no numbers on enemy nodes: the owner's emblem in the owner's colour stands in the count's place
		# (Daniele: "don't use A B and C but use emblems in the color of the owner")
		var emb: TextureRect = b["emblem"]
		var show_emb := owner != "" and (classic or masked)
		if show_emb and emb.get_meta("f", "") != sim.factions.get(owner, ""):
			emb.set_meta("f", sim.factions.get(owner, ""))
			emb.texture = emblem_texture(str(sim.factions.get(owner, "null")))
		if show_emb and emb.get_meta("seat", "") != owner:
			emb.set_meta("seat", owner)
			tint_emblem(emb, Rules.seat_color(owner))
		sub.visible = not classic or n["build_kind"] != "" or sim.last_stand_active
		# Alpha 19 (Daniele: "some text is too long, like the word FINAL isn't necessary"): two compact
		# tags at most - what the node is (relay glyph + state, CN3 cannon, FRG forge, T2 tier) and the
		# one clock that matters most: the falling countdown (a down triangle), the relay's !n switch
		# warning, the build's seconds (over its bar), your relay's ns cooldown, else the Last Stand
		# drop ring (R2 / #2). The node that never falls shows nothing extra: the banner says it.
		var what := ""
		if n["relay"] != "":
			var st := sim.relay_state_key(n, n["relay_index"])
			what = Rules.RELAY_GLYPH[n["relay"]] + (("OUT" if st == "out" else "IN" if st == "retract" else st.to_upper()) if shows("relay") else "")
		elif n["structure"] == "machinegoon":
			what = "MGN%d" % n["tier"]
		else:
			what = "T%d" % n["tier"]
		# 0.20.13 (Daniele's 2v2 co-op playtest: "i sent troops to her node and except the count going up
		# i couldn't see any other indicator"): your own share on an ally's node stands out in your own
		# colour, not the sub-label's default light blue - reset every frame, or a stale override would
		# bleed into a later node that has none.
		sub.add_theme_color_override("font_color", Color("c8e6ee"))
		if has_allies and not masked:                       # GAME-RULES sec11: the total is shown above -
			if owner == human:                               # this names the ally share / your own share of it
				what += "+A%d" % Rules.shown(sim.allied_units(n))
			else:
				var mine := sim.allied_units(n, human)
				if mine > 0.0001:
					what += " +%d" % Rules.shown(mine)
					sub.add_theme_color_override("font_color", Rules.seat_color(human))
		var clock := ""
		var worst := ""                                     # the clock's widest form (see below)
		if sim.is_warned(n["id"]):
			clock = "▼%d" % int(ceil(sim.drop_in(n["id"]) if sim.v3 else sim.last_stand_warn_t))
			worst = "▼88"
		elif n["relay"] != "" and n["relay_phase"] == "warning":
			clock = "!%d" % int(ceil(n["relay_t"]))
			worst = "!8"
		elif n["build_kind"] != "":
			clock = "%ds" % int(ceil(n["build_timer"]))
			worst = "88s"
		elif n["relay"] != "" and n["relay_cd"] > 0.0 and owner == human:
			clock = "%ds" % int(ceil(n["relay_cd"]))
			worst = "88s"
		elif order_shown:
			var k := sim.drop_order_of(n["id"])
			if k > 0:
				clock = ("R%d" if sim.v3 else "#%d") % k
				worst = clock
		var small := show_emb and not masked               # Alpha 11's emblem shares the sub line
		if sub.visible:
			# a sub line that would drop under 8 pt beside the emblem takes the whole row instead (the
			# owner still reads from the rim colour). Judged on the clock's widest form, so a countdown
			# does not make the emblem come and go as its digits change.
			var shape := what + (" " + worst if worst != "" else "")
			if shape != b["shape"] or small != b["sub_small"]:
				b["shape"] = shape
				b["sub_small"] = small
				b["wide"] = small and _fit_size(shape, BADGE_SUB_FONT, inner - (BADGE_EMBLEM.x + 2.0) * ui_scale - 2.0).x < int(8 * ui_scale)
				sub.text = ""                                 # re-measure in the new room
			if b["wide"]:
				small = false
			var room := inner - ((BADGE_EMBLEM.x + 2.0) * ui_scale if small else 0.0)
			b["sub_w"] = _fit_text(sub, what + (" " + clock if clock != "" else ""), BADGE_SUB_FONT, room, b["sub_w"])
		emb.visible = show_emb and (masked or small)
		var build_bar: ProgressBar = b["build"]
		build_bar.visible = n["build_kind"] != ""
		if build_bar.visible:
			build_bar.value = 100.0 * Sim.build_progress(n)
		# the box never changes size; its parts move only when what it shows changes
		var look := (1 if masked else 0) | (2 if emb.visible else 0) | (4 if sub.visible else 0) | (int(b["sub_w"]) << 3)
		if look != b["look"]:
			b["look"] = look
			_place_badge(b, masked, small)
	var vp := get_viewport().get_visible_rect().size
	var xf := cam.global_transform
	# Match feel (the Last Stand zoom "still slows the game down"): the full layout is the HUD's heaviest step (~10 ms
	# on M-39 on desktop, several times that on a phone) and it used to run on every frame the camera moved. While the
	# camera moves the badges follow their platforms (_follow_badges); the layout runs once it has held still.
	if vp != _layout_vp or _badge_screen.is_empty():
		_layout_vp = vp
		_layout_xf = xf
		_layout_badges(cam)
	elif xf != _layout_xf:
		_still = _still + 1 if xf == _last_xf else 0
		if _still >= Rules.BADGE_SETTLE_FRAMES:
			_layout_xf = xf
			_layout_badges(cam)
		else:
			_follow_badges(cam)
	_last_xf = xf
	for n in sim.nodes:
		var panel: Control = badges[n["id"]]["panel"]
		if panel.visible and _badge_screen.has(n["id"]):
			panel.position = ((_badge_screen[n["id"]] as Vector2) - _badge_px / 2.0).round()


func _fit_text(l: Label, text: String, base: int, width: float, drawn: float) -> float:
	## Daniele: "have their inside content never get out of the box boundaries": a text too wide for
	## the badge steps its font down (to 60 % at most), and whatever is still wider is clipped by the
	## label. Measured only when the text changes; returns the drawn width.
	if l.text == text:
		return drawn
	l.text = text
	var fit := _fit_size(text, base, width - float(l.get_theme_constant("outline_size")))
	if l.get_theme_font_size("font_size") != int(fit.x):
		l.add_theme_font_size_override("font_size", int(fit.x))
	return minf(fit.y + float(l.get_theme_constant("outline_size")), width)


func _fit_size(text: String, base: int, width: float) -> Vector2:
	## The largest font size (base x ui_scale down to 60 % of it) whose text fits the width: (size, width).
	var size := int(base * ui_scale)
	var least := maxi(int(round(base * ui_scale * 0.6)), 6)
	var w := UI_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	while w > width and size > least:
		size -= 1
		w = UI_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Vector2(size, w)


func _place_badge(b: Dictionary, masked: bool, small: bool) -> void:
	## The fixed badge's layout: the count (or, where it is hidden, the owner's emblem) on top, the
	## sub line under it with Alpha 11's small emblem at its left in BRAWL, the build bar along the
	## bottom edge. With no sub line the top row sits in the middle of the box.
	var s := ui_scale
	var box := _badge_px
	var label: Label = b["label"]
	var sub: Label = b["sub"]
	var emb: TextureRect = b["emblem"]
	var row2 := sub.visible or small
	var top_y := (12.5 if row2 else 16.0) * s                # centre of the count row
	var low_y := 23.5 * s                                    # centre of the sub line
	var pad := BADGE_PAD * s
	# each label is as tall as its full-size font line, so a stepped-down font stays centred in it
	var lh := UI_FONT.get_height(int(BADGE_COUNT_FONT * s)) + 3.0
	label.size = Vector2(box.x - 2.0 * pad, lh)
	label.position = Vector2(pad, top_y - lh / 2.0)
	var esz := (BADGE_EMBLEM_OWNER if masked else BADGE_EMBLEM) * s
	emb.custom_minimum_size = esz
	emb.size = esz
	var sub_w: float = b["sub_w"] if sub.visible else 0.0
	if masked:
		emb.position = Vector2((box.x - esz.x) / 2.0, top_y - esz.y / 2.0).round()
	var gap := 2.0 * s if sub_w > 0.0 else 0.0
	var x0 := (box.x - sub_w - ((esz.x + gap) if small else 0.0)) / 2.0
	if small:
		emb.position = Vector2(x0, low_y - esz.y / 2.0).round()
		x0 += esz.x + gap
	var sh := UI_FONT.get_height(int(BADGE_SUB_FONT * s)) + 2.0
	sub.size = Vector2(sub_w, sh)
	sub.position = Vector2(x0, low_y - sh / 2.0)


# ------------------------------------------------------------------ inspector (Alpha 11 ring)
func inspect(id: int, cam: Camera3D) -> void:
	close_inspector()
	if id < 0 or sim.collapsed.get(id, false):
		return
	inspector_id = id
	var n: Dictionary = sim.nodes[id]
	var col := Rules.seat_color(n["owner"]) if n["owner"] != "" else Rules.NEUTRAL
	inspector = Control.new()
	inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inspector)
	var ring := Panel.new()
	ring.position = Vector2(-76, -76) * ui_scale
	ring.size = Vector2(152, 152) * ui_scale
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := panel_style(col)
	style.set_corner_radius_all(int(76 * ui_scale))
	style.bg_color = Color(0.09, 0.13, 0.17, 0.0)     # a ring only: the vat stays visible
	ring.add_theme_stylebox_override("panel", style)
	inspector.add_child(ring)
	var close_h := 52.0 if not mobile else 80.0
	var close := button("X", close_inspector, 64, close_h)
	close.position = Vector2(84, -68.0 - close_h) * ui_scale     # Alpha 18: top right of the ring, between the
	                                                             # top and right actions (the info panel covered it)
	inspector.add_child(close)
	inspector.set_meta("close", close)
	var info_bg := PanelContainer.new()
	info_bg.position = Vector2(-190, 96) * ui_scale
	info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_style := panel_style(col)
	info_style.bg_color = Color(0.05, 0.08, 0.11, 0.9)
	info_style.set_content_margin_all(8)
	info_bg.add_theme_stylebox_override("panel", info_style)
	inspector.add_child(info_bg)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 0)
	info_box.custom_minimum_size = Vector2(364, 0) * ui_scale
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bg.add_child(info_box)
	var head := HBoxContainer.new()                   # [emblem] FACTION · first line: the owner, no seat letter
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", int(5 * ui_scale))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(head)
	inspector_emblem = seat_emblem("", Vector2(20, 20))
	head.add_child(inspector_emblem)
	inspector_who = text_label("", 16, Color("c8e6ee"))
	head.add_child(inspector_who)
	inspector_first = text_label("", 16, Color("c8e6ee"))
	head.add_child(inspector_first)
	inspector_label = text_label("", 16, Color("c8e6ee"))
	inspector_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(inspector_label)
	inspector_progress = ProgressBar.new()
	inspector_progress.position = Vector2(-130, 82) * ui_scale
	inspector_progress.size = Vector2(260, 12) * ui_scale
	inspector_progress.show_percentage = false
	inspector_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector.add_child(inspector_progress)
	if n["owner"] == human:
		_inspector_actions(n)
	_refresh_inspector(cam)


const STRUCT_LABEL := {"vat": "VAT", "machinegoon": "MACHINEGOON", "laser": "LASER TOWER", "forge": "FORGE", "monster_hub": "MONSTER HUB"}
const BUILD_LABEL := {"machinegoon": "MACHINEGOON", "vat": "VAT", "laser": "LASER", "forge": "FORGE", "monster_hub": "MONSTER HUB"}
const RELAY_ACCENT := Color("ffb238")   # 0.19.0: SWITCH's own accent (Daniele: "add some visibility to the
                                         # buttons / models of the relays") - distinct from the seat colour


class MonsterIcon:
	## Floats above your Monster hub once it's ready (0.19.2 spec H1, Daniele: "sending of monster is not
	## clear"): a pulsing disc with a simple "send" chevron. Tap arms LAUNCH (main.monster_from) exactly
	## like the inspector's LAUNCH button - tap again (or elsewhere) cancels.
	extends Button
	var accent := Color.WHITE
	var ui_scale := 1.0
	var t := 0.0

	func _init() -> void:
		flat = true
		text = ""
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, empty)

	func _draw() -> void:
		var s := ui_scale
		var c: Vector2 = size / 2.0
		var r: float = minf(size.x, size.y) / 2.0 - 3.0 * s
		var pulse := 0.55 + 0.45 * sin(t * 4.0)
		draw_circle(c, r + 6.0 * s, Color(accent, 0.22 * pulse))
		draw_circle(c, r, Color(0.05, 0.07, 0.09, 0.92))
		draw_arc(c, r, 0.0, TAU, 32, Color(accent, 0.95), 2.5 * s, true)
		var h := r * 0.85
		var pts := PackedVector2Array([c + Vector2(0, -h * 0.6), c + Vector2(-h * 0.55, h * 0.35), c + Vector2(h * 0.55, h * 0.35)])
		draw_colored_polygon(pts, Color.WHITE)


class SwitchRing:
	## A READY / cooldown ring drawn over the SWITCH button (a child Control, full rect, clicks pass
	## through): the relay's own accent while ready or counting down, red while its 1 s warning runs.
	extends Control
	var accent := Color("ffb238")
	var frac := 1.0            # 0..1 cooldown progress (1 = ready)
	var warning := false
	var ui_scale := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := ui_scale
		var c: Vector2 = size / 2.0
		var r: float = minf(size.x, size.y) / 2.0 - 4.0 * s
		draw_arc(c, r, 0.0, TAU, 40, Color(accent, 0.16), 5.0 * s, true)
		if warning:
			draw_arc(c, r, 0.0, TAU, 40, Rules.state_color("warn"), 3.5 * s, true)
		elif frac >= 1.0:
			draw_arc(c, r, 0.0, TAU, 40, Color(accent, 0.95), 3.5 * s, true)
		elif frac > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(accent, 0.85), 3.5 * s, true)


func _inspector_actions(n: Dictionary) -> void:
	## Structures 2.1 (spec B): common - UPGRADE / MACHINEGOON (or VAT to go back); relay - LASER / FORGE /
	## MONSTER HUB (single tier) + SWITCH; special - T4 vat only, no swap; hub - LAUNCH; EJECT wherever
	## allied troops are stored. Costs and disabled reasons come straight from the Sim (can_build /
	## can_upgrade) in _refresh_inspector, so a greyed button always explains itself.
	var id: int = n["id"]
	# (TUTORIAL: each action shows once its lesson is reached - shows(); outside the tutorial, always)
	if n["relay"] != "":
		if shows("relay"):
			_add_action("SWITCH", "SWITCH\n%s" % Rules.RELAY_GLYPH[n["relay"]], 0, "switch", id)
		for kind in ["laser", "forge", "monster_hub"]:
			if kind in n["buildable"] and n["structure"] != kind and shows("relay_build"):
				_add_action(BUILD_LABEL[kind], BUILD_LABEL[kind], sim.build_cost(n, kind), "build", id, {"kind": kind})
		if n["structure"] == "monster_hub" and shows("monster"):
			_add_action("LAUNCH", "LAUNCH", Rules.MONSTER_COST, "launch_monster", id)
	elif n["structure"] == "vat":
		if n["tier"] < 4 and shows("upgrade"):
			_add_action("UPGRADE", "UPGRADE T%d" % (n["tier"] + 1), sim.upgrade_cost(n), "upgrade", id)
		if "machinegoon" in n["buildable"] and shows("machinegoon"):
			_add_action("MACHINEGOON", "MACHINEGOON", sim.build_cost(n, "machinegoon"), "build", id, {"kind": "machinegoon"})
	elif n["structure"] == "machinegoon":
		if n["tier"] < 3 and shows("upgrade"):
			_add_action("UPGRADE", "UPGRADE T%d" % (n["tier"] + 1), sim.upgrade_cost(n), "upgrade", id)
		if shows("machinegoon"):
			_add_action("VAT", "VAT", sim.build_cost(n, "vat"), "build", id, {"kind": "vat"})
	if sim.allied_units(n) > 0.0001 and shows("eject"):
		_add_action("EJECT", "EJECT", 0, "eject", id)


func _add_action(name: String, title: String, cost: int, method: String, id: int, args := {}) -> void:
	# prices shown at Alpha 11 scale like every other number (Alpha 14 playtest: "upgrade info still
	# says 150") - the button used to print the raw internal cost. `name` is the stable id the tutorial
	# spotlights (action_rect(name); TUTORIAL-DESIGN.md sec11).
	var suffix := ""
	if method == "launch_monster":
		suffix = "\n%d UNITS · DRAG" % Rules.shown(cost)
	elif cost > 0:
		suffix = "\n%d UNITS" % Rules.shown(cost)
	elif method == "switch":
		suffix = "\n%d s CD" % int(Rules.RELAY_COOLDOWN)
	else:
		suffix = "\nFREE"
	var text := title + suffix
	var b := button(text, func():
		if method == "launch_monster":                    # arm: drag from the hub, or tap a highlighted node
			main.monster_from = id
			close_inspector()
			return
		if main.node_action(method, id, args):
			close_inspector()
		else:
			_refresh_inspector(main.cam), 150, 82 if not mobile else 100, 16)
	if method == "switch":                                # relay-outcome preview while SWITCH is hovered / held
		b.mouse_entered.connect(func(): overlay.hover_relay = id)
		b.mouse_exited.connect(func():
			if overlay.hover_relay == id:
				overlay.hover_relay = -1)
		b.button_down.connect(func(): overlay.hover_relay = id)
	var slots := [Vector2(-75, -175), Vector2(80, -60), Vector2(-230, -60), Vector2(80, 30), Vector2(-230, 30)]
	b.position = slots[mini(inspector_actions.size(), slots.size() - 1)] * ui_scale
	# SWITCH stands out (Daniele, 0.19.0: "add some visibility to the buttons / models of the relays"):
	# its own accent colour plus a READY / cooldown ring (SwitchRing, updated in _refresh_inspector).
	var style := panel_style(RELAY_ACCENT if method == "switch" else Rules.seat_color(human))
	style.set_corner_radius_all(int(40 * ui_scale))
	b.add_theme_stylebox_override("normal", style)
	inspector.add_child(b)
	if method == "switch":
		switch_ring = SwitchRing.new()
		switch_ring.ui_scale = ui_scale
		switch_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		switch_ring.accent = RELAY_ACCENT
		b.add_child(switch_ring)
	inspector_actions.append({"button": b, "cost": cost, "method": method, "name": name, "args": args})
	action_buttons[name] = b


func action_rect(name: String) -> Rect2:
	## Stable rect getter for the tutorial's spotlight (TUTORIAL-DESIGN.md sec11): valid only while that
	## action's button is on screen (the inspector open on the right node kind). Empty otherwise.
	name = name.replace("MACHINGOON", "MACHINEGOON")   # 0.19.2 spelling fix; old name accepted for one release
	if action_buttons.has(name) and is_instance_valid(action_buttons[name]):
		return (action_buttons[name] as Control).get_global_rect()
	return Rect2()


func send_button_rect(fraction: float) -> Rect2:
	## The SEND panel's button for `fraction` (1.0 / 0.75 / 0.5 / 0.25), for the tutorial's spotlight.
	for c in side_box.get_children():
		if c is Button and (c as Button).text == "%d%%" % int(round(fraction * 100.0)):
			return (c as Control).get_global_rect() if side_panel.visible else Rect2()
	return Rect2()


func badge_rect(id: int) -> Rect2:
	if badges.has(id) and (badges[id]["panel"] as Control).visible:
		return (badges[id]["panel"] as Control).get_global_rect()
	return Rect2()


func inspector_rect() -> Rect2:
	## What the open inspector covers on screen (its ring, info panel and actions); empty when closed.
	if not is_instance_valid(inspector):
		return Rect2()
	var r := Rect2()
	for c in inspector.get_children():
		if c is Control and (c as Control).visible:
			var g := (c as Control).get_global_rect()
			r = g if r.size == Vector2.ZERO else r.merge(g)
	return r


func dock_slot_rect(i: int) -> Rect2:
	if dock and dock.visible and i >= 0 and i < dock.slots.size():
		return (dock.slots[i] as Control).get_global_rect()
	return Rect2()


# ------------------------------------------------------------------ TUTORIAL: reveal as you go (§6)
func shows(key: String) -> bool:
	## Is this HUD part on screen? Always, outside a lesson.
	return not gated or revealed.has(key.replace("machingoon", "machinegoon"))


func reveal(keys: Array, glow: Array = []) -> void:
	## A lesson's reveal set (TutorialDirector.reveal_for): everything else hides. `glow`: the keys this lesson
	## or step adds - those parts appear with a short glow-in.
	gated = true
	revealed = {}
	keys = keys.map(func(k): return str(k).replace("machingoon", "machinegoon"))   # 0.19.2 spelling alias
	glow = glow.map(func(k): return str(k).replace("machingoon", "machinegoon"))
	for k in keys:
		revealed[str(k)] = true
	_apply_reveal()
	for k in glow:
		var c: Control = {"send_panel": side_panel, "strength": top_panel, "dock": dock, "status_line": status_label,
				"notices": callouts}.get(str(k), null)
		if c and c.visible:
			c.modulate = Color(2.2, 2.2, 2.2, 0.0)
			create_tween().set_trans(Tween.TRANS_SINE).tween_property(c, "modulate", Color.WHITE, 0.6)
	for id in badges:                                 # badges re-dress (counts, relay state)
		badges[id]["owner"] = "?"
		badges[id]["shape"] = ""


func reveal_all() -> void:
	gated = false
	revealed = {}
	_apply_reveal()


func _apply_reveal() -> void:
	side_panel.visible = shows("send_panel")
	top_panel.visible = shows("topbar")
	top_left.visible = shows("strength")
	top_right.visible = shows("strength")
	dock.visible = sim.abilities_on and shows("dock")
	hint.visible = not touch_ui() and not gated
	callouts.visible = shows("notices")
	if is_instance_valid(inspector) and inspector_id >= 0:
		inspect(inspector_id, main.cam)


func _seat_out(seat: String) -> bool:
	## Sim.is_out(seat) once the SIM agent adds it (spec S5/H7: no nodes and no lines left); the
	## eliminated set is the safe fallback until then.
	if sim.has_method("is_out"):
		return sim.is_out(seat)
	return bool(sim.eliminated.get(seat, false))


func _monster_ready(n: Dictionary) -> String:
	## "" if this hub may launch a monster right now, else the refusal line (mirrors Sim.launch_monster's
	## own checks, read-only, for the LAUNCH button's disabled state and tooltip).
	if int(n["hub_monster"]) >= 0:
		for m in sim.monsters:
			if m["id"] == n["hub_monster"] and m["state"] == "walking":
				return "Its monster is still out"
	if sim.time < float(n["monster_ready_t"]):
		return "Monster ready in %d s" % int(ceil(float(n["monster_ready_t"]) - sim.time))
	if n["units"] < Rules.MONSTER_COST:
		return "A monster needs %d units (%d here)" % [Rules.shown(Rules.MONSTER_COST), Rules.shown(n["units"])]
	return ""


func _human_hub_id() -> int:
	## The node id of your Monster hub (Structures 2.1: one per player), -1 if you have none.
	for n in sim.nodes:
		if n["owner"] == human and n["structure"] == "monster_hub" and not sim.collapsed.get(n["id"], false):
			return n["id"]
	return -1


func is_ready_hub(node_id: int) -> bool:
	## 0.20.1 (Daniele's online playtest: "i couldn't figure how to send the monster ... tap IT, the
	## guided send lights up every target, tap a target, it goes"): true while node_id is YOUR Monster
	## hub and it can launch right now - main.gd's tap handler arms LAUNCH straight from this instead of
	## opening the inspector (which still opens while it's charging).
	return node_id >= 0 and node_id == _human_hub_id() and _monster_ready(sim.nodes[node_id]) == ""


static var _monster_hint_shown := false


func note_monster_hint() -> void:
	## A short first-time nudge (Daniele's ask) the first time LAUNCH is armed this session, from any of
	## the three equivalent triggers (the hub, its monster, the icon).
	if _monster_hint_shown:
		return
	_monster_hint_shown = true
	callout_node(_human_hub_id(), "Tap your monster, then a lit node", "info")


func monster_icon_rect(hub_id: int) -> Rect2:
	## Stable rect getter for the tutorial's spotlight (0.19.2 spec H1): valid only while the icon is
	## actually showing for this hub (it is your ready hub, on screen, "monster_icon" revealed).
	if monster_icon.visible and _human_hub_id() == hub_id:
		return monster_icon.get_global_rect()
	return Rect2()


func _sync_monster_icon(cam: Camera3D) -> void:
	var hub := _human_hub_id()
	var ready := hub >= 0 and _monster_ready(sim.nodes[hub]) == "" and shows("monster_icon")
	monster_icon.visible = ready
	if not ready:
		return
	var n: Dictionary = sim.nodes[hub]
	var p := cam.unproject_position((n["pos"] as Vector3) + Vector3(0, 5.5, 0))
	monster_icon.position = p - monster_icon.size / 2.0
	monster_icon.accent = Rules.seat_color(human)
	monster_icon.t += 0.016
	monster_icon.queue_redraw()


# ------------------------------------------------------------------ 0.19.2 spec H7: YOU'RE OUT
func _check_out() -> void:
	if _out_shown or not main.get("show_out_panel") or sim.over:   # the match ending wins: show_end() takes it
		return
	if _seat_out(human):
		_out_shown = true
		show_out_panel()


func show_out_panel() -> void:
	if not shows("out_panel"):
		return
	# UI (Alpha 21): a card in the pause's language over the dimmed match - SPECTATE first, the way out quieter
	MatchScreens.open(out_panel, mobile, _my_faction()).card({"kicker": "%s  ·  ELIMINATED" % _who_line(human), "headline": "YOU'RE OUT.",
			"body": "Every node and line you had is gone - you can keep watching, or leave.", "glow": false,
			"actions": [["SPECTATE  →", func():
				out_panel.visible = false
				spectate_button.visible = true],
			["LEAVE ROOM" if main.online else ("CAMPAIGN" if main.get("mission") != null else "MAIN MENU"), main.to_menu]]})   # CAMPAIGN
	_show_screen(out_panel)


func _refresh_inspector(cam: Camera3D) -> void:
	if not is_instance_valid(inspector) or inspector_id < 0:
		return
	var n: Dictionary = sim.nodes[inspector_id]
	if sim.collapsed.get(inspector_id, false):
		close_inspector()
		return
	var vp := root.get_viewport_rect().size
	var p := cam.unproject_position(n["pos"] + Vector3(0, 2.0, 0))
	inspector.position = Vector2(clampf(p.x, 250 * ui_scale, vp.x - 250 * ui_scale), clampf(p.y, 200 * ui_scale, vp.y - 200 * ui_scale))
	var owner: String = n["owner"]
	# the header names the owner by emblem and faction in the owner's colour (Daniele: "don't use A B
	# and C but use emblems in the color of the owner")
	inspector_emblem.visible = owner != ""
	if owner != "" and inspector_emblem.get_meta("seat", "") != owner:
		inspector_emblem.set_meta("seat", owner)
		inspector_emblem.texture = emblem_texture(str(sim.factions.get(owner, "null")))
		tint_emblem(inspector_emblem, Rules.seat_color(owner))
	inspector_who.text = "NEUTRAL" if owner == "" else str(sim.factions.get(owner, "")).to_upper()
	inspector_who.add_theme_color_override("font_color", Color("c8e6ee") if owner == "" else Rules.seat_color(owner))
	var lines := []
	if owner != "" and owner != human:
		lines.append("population hidden")
		lines.append(_structure_line(n))
	else:
		var what := _structure_line(n)
		var units := "%d / %d units" % [Rules.shown(n["units"]), Rules.shown(sim.node_cap(n))]
		lines.append("%s · %s" % [what, units])
		if owner != "":
			# Alpha 11's status line: production, and what a double-tap upgrade costs
			var status := "%.1f / s production" % Rules.shown_f(sim.production(n)) if Sim.has_vat(n) \
					else ("no production - garrison must be fed" if n["structure"] == "machinegoon" else "no vat here")
			var up := sim.upgrade_cost(n)
			if owner == human and up > 0 and shows("upgrade"):
				status += " | Double-tap: %d units" % Rules.shown(up)
			elif owner == human and n["structure"] in ["vat", "machinegoon"] and up <= 0 and shows("upgrade"):
				status += " | MAX TIER"
			lines.append(status)
			var forge: String = " (forge +%d%%)" % roundi(Rules.forge_bonus * 100.0) if sim.has_forge(owner) else ""   # attack_of includes it
			lines.append("garrison %s | attack %d%%%s | speed %d%%" % [
					"%d%%" % roundi(sim.stat(owner, "garrison") * 100.0), roundi(sim.attack_of(owner) * 100.0), forge,
					roundi(sim.stat(owner, "speed") * 100.0)])
			if n["structure"] == "forge" and shows("forge_readout"):
				# Forge readout (spec E): the attack half is in the line above (attack_of includes it)
				lines.append("Forge: +%d%% attack, -%d%% damage taken" % [roundi(Rules.forge_bonus * 100.0), roundi((1.0 - 1.0 / Rules.FORGE_DEFENCE) * 100.0)])
			if n["structure"] == "monster_hub" and shows("monster"):
				var mr := _monster_ready(n)
				lines.append("Monster hub: %s" % ("READY" if mr == "" else mr.to_upper()))
	if n["relay"] != "" and shows("relay"):
		var cur := sim.relay_state_key(n, n["relay_index"]).to_upper()
		var nxt := sim.relay_state_key(n, sim.relay_next_index(n)).to_upper()
		var rs := "%s relay %s -> %s" % [n["relay"].to_upper(), cur, nxt]
		if n["relay_phase"] == "warning":
			rs += " | SWITCHING IN %.1f s" % n["relay_t"]
		elif n["relay_phase"] == "moving":
			rs += " | MOVING"
		elif n["relay_cd"] > 0.0:
			rs += " | READY IN %.0f s" % ceil(n["relay_cd"])
		else:
			rs += " | READY"
		lines.append(rs)
	if n["structure"] == "laser" and owner == human:
		lines.append("laser %s" % ("FIRING" if n["cannon_burst"] > 0.0 else ("READY" if n["cannon_cd"] <= 0.0 else "RECHARGING %.1f s" % n["cannon_cd"])))
	if n["build_kind"] != "":
		lines.append("BUILDING %s · %.1f s" % [str(n["build_target"].get("kind", n["build_kind"])).to_upper(), n["build_timer"]])
	if n["swap_cd"] > 0.0 and owner == human:
		lines.append("attachment swap in %.0f s" % ceil(n["swap_cd"]))
	if sim.very_last_stand_active:
		lines.append("VERY LAST STAND: %s" % ("THE LAST NODE - conquest decides" if sim.very_last_stand_gap <= 0.0
				else ("falls in %d s" % int(ceil(sim.drop_in(n["id"]))) if sim.is_warned(n["id"]) else "could fall next")))
	elif sim.last_stand_active:
		var k := sim.drop_order_of(n["id"])
		lines.append("LAST STAND: %s" % ((("falls in wave %d" if sim.v3 else "drop #%d") % k) if k > 0 else ("THE %s - never falls" % ("LAST RING" if sim.v3 else "FINAL") if sim.is_final(n["id"]) else "")))
	inspector_first.text = "· " + str(lines.pop_front())
	inspector_label.text = "\n".join(lines)
	inspector_label.visible = not lines.is_empty()
	inspector_progress.visible = n["build_kind"] != ""
	inspector_progress.value = Sim.build_progress(n) * 100.0
	for a in inspector_actions:
		var b: Button = a["button"]
		var why := ""
		match str(a["method"]):
			"upgrade":
				why = sim.can_upgrade(inspector_id, human)
			"switch":
				why = "" if n["relay_cd"] <= 0.0 and n["relay_phase"] == "" else \
						("Relay on cooldown" if n["relay_cd"] > 0.0 else "Relay is already switching")
				if is_instance_valid(switch_ring):
					var ring := switch_ring as SwitchRing
					ring.warning = n["relay_phase"] == "warning"
					ring.frac = 1.0 if n["relay_cd"] <= 0.0 else clampf(1.0 - float(n["relay_cd"]) / Rules.relay_cooldown(str(n["relay"])), 0.0, 1.0)
					ring.queue_redraw()
			"build":
				why = sim.can_build(inspector_id, human, str((a["args"] as Dictionary).get("kind", "")))
			"eject":
				why = sim.can_build(inspector_id, human, "eject")
			"launch_monster":
				why = _monster_ready(n)
		b.disabled = why != ""
		b.tooltip_text = why


func _structure_line(n: Dictionary) -> String:
	if n["relay"] != "":
		return "%s RELAY" % n["relay"].to_upper() + (" + %s" % STRUCT_LABEL.get(n["structure"], str(n["structure"]).to_upper()) if n["structure"] != "" else " (empty socket)")
	if n["structure"] == "machinegoon":
		return "MACHINEGOON T%d" % n["tier"]
	return "VAT T%d" % n["tier"]


func close_inspector() -> void:
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = null
	inspector_id = -1
	inspector_actions.clear()
	action_buttons.clear()
	switch_ring = null
	if overlay:
		overlay.hover_relay = -1


# ------------------------------------------------------------------ messages
# HUD pass (2026-09-28, Daniele's "option A": "no notification box at all" - the top-left stack "feels weird"):
# every message goes where it belongs, drawn by HudCallouts. A map event is a callout at its node / deck / spot
# (callout_node / callout_at, an edge arrow when that place is off screen); a skill dock refusal a small line just
# above the slot tapped (skill_refusal); a network line about a seat a line under that seat's top-bar chip; the
# Last Stand's announcement a pulse of its own status line (pulse_last_stand); the start lines a short banner
# (start_banner); online loading the waiting text (set_waiting). toast() stays as the thin router for every other
# caller (other sessions' TUTORIAL / CAMPAIGN / PROGRESSION lines, Net's feedback): the seat chip when the line
# starts with a seat, else a centred line under the top bar. TUTORIAL: nothing of it before the "notices" reveal (L3).
const WARN_WORDS := ["lost", "falls", "get out", "can't", "Can't", "No ", "needs", "refused", "rejected", "on cooldown",
		"swap ready", "Not your", "Too many", "already", "max tier", "no further", "Nothing", "missing", "Waiting"]
static var _SEAT_WORD := RegEx.create_from_string("(?i)\\bseat ([A-F])\\b(?: \\([^)]*\\))?")   # "seat B", "seat A (NULL)"
const GOOD_WORDS := ["captured", "Sending", "Recalled", "reconnected", "Upgrade started", "construction started", "Restoring", "Relay fired"]
const INFO_COLOR := Color("7fe9f5")
var callouts: HudCallouts               # every placed message (see above)
var status_glow: Panel                  # behind the status line while the Last Stand announcement pulses it
var _ls_pulse := 0.0                    # s of that pulse left
var _ls_how := ""                       # the method's one-line explanation, shown in the line meanwhile


func toast(msg: String, kind := "") -> void:
	## The router for a line with no place given (see above): a line naming a seat first ("Seat C reconnected")
	## goes under that seat's top-bar chip, named by player / faction instead of the letter (Daniele: "don't use
	## A B and C"); anything else is a short centred line under the top bar.
	if not shows("notices") or msg == "":           # TUTORIAL: before L3 main hands refusals to the coach card
		return
	kind = kind_of(msg, kind)
	var named := _SEAT_WORD.search(msg)
	var seat := named.get_string(1).to_upper() if named else ""
	if seat != "" and named.get_start() == 0 and top_chips.has(seat) and top_panel.visible and top_left.visible:
		callout_chip(seat, ("%s %s" % [seat_label(seat), msg.substr(named.get_end()).strip_edges()]).strip_edges(), kind)
		return
	note_line(named_text(msg), kind, seat if sim.factions.has(seat) else "")


func kind_of(msg: String, kind := "") -> String:
	## "" -> guessed from the words (warn / good / build / info), as the toasts always were.
	if kind != "":
		return kind
	for w in WARN_WORDS:
		if w in msg:
			return "warn"
	for w in GOOD_WORDS:
		if w in msg:
			return "build" if ("started" in w or "Restoring" in w) else "good"
	return "info"


func kind_color(kind: String) -> Color:
	return {"warn": Rules.state_color("warn"), "good": Rules.seat_color(human), "build": Rules.state_color("build")}.get(kind, INFO_COLOR)


func seat_label(seat: String) -> String:
	## A seat in words: a human's name where the game knows it, else the faction (main.seat_who).
	if main and main.has_method("seat_who"):
		var w: Dictionary = main.seat_who(seat)
		return str(w["name"]) if str(w["name"]) != "" else str(w["faction"])
	return str(UiKit.NAMES.get(str(sim.factions.get(seat, "")), seat))


func named_text(msg: String) -> String:
	## "seat B ..." / "seat A (NULL) ..." -> the seat named by player or faction instead of its letter.
	var named := _SEAT_WORD.search(msg)
	if named == null or not sim.factions.has(named.get_string(1).to_upper()):
		return msg
	return msg.substr(0, named.get_start()) + seat_label(named.get_string(1).to_upper()) + msg.substr(named.get_end())


func callout_px(base: float, min_pt: float) -> int:
	## A message's font in canvas units: `base` x ui_scale, never under `min_pt` real points on a phone.
	var px := base * ui_scale
	if mobile:
		px = maxf(px, min_pt / maxf(UiKit.pt_per_px(root.get_viewport_rect().size), 0.01))
	return int(round(px))


func _icon_opts(seat: String, kind: String) -> Dictionary:
	## The callout's icon: the seat's emblem in its colour, else the kind's mark.
	if seat != "" and sim.factions.has(seat):
		return {"seat": seat, "emblem_tex": emblem_texture(str(sim.factions[seat]))}
	return {"glyph": "good" if kind == "good" else ("warn" if kind == "warn" else "info")}


func callout_node(id: int, text: String, kind := "warn", seat := "", place := "") -> void:
	## A map event at a node (its own place: the same node again refreshes it).
	if id < 0 or id >= sim.nodes.size():
		return
	callout_at(sim.nodes[id]["pos"], place if place != "" else "node:%d" % id, text, kind, seat)


func callout_at(pos: Vector3, place: String, text: String, kind := "warn", seat := "") -> void:
	## A map event at a world point (a deck, a monster, a skill's target): one line in Fx.floater's look.
	if not shows("notices") or callouts == null:
		return
	var col := kind_color(kind)
	var opts := _icon_opts(seat, kind)
	opts["world"] = pos + Vector3(0, Rules.HUD_CALLOUT_LIFT, 0)
	callouts.add(place, [[text, callout_px(Rules.HUD_CALLOUT_FONT, Rules.HUD_CALLOUT_MIN_PT), col.lerp(Color.WHITE, 0.15)]], col, opts)


func callout_chip(seat: String, text: String, kind := "info") -> void:
	## A line about a seat (drops, reconnects, the room changing hands) under its top-bar chip.
	if not shows("notices") or callouts == null or not top_chips.has(seat):
		return
	var col := kind_color(kind)
	var opts := _icon_opts(seat, kind)
	var chip: Control = top_chips[seat]["panel"]
	opts["anchor"] = func(): return Vector2(chip.get_global_rect().get_center().x, chip.get_global_rect().end.y + 4.0 * ui_scale)
	opts["side"] = "below"
	opts["arrow"] = false
	callouts.add("chip:%s" % seat, [[text, callout_px(Rules.HUD_CALLOUT_FONT * 0.9, Rules.HUD_CALLOUT_MIN_PT), col.lerp(Color.WHITE, 0.15)]], col, opts)


func skill_refusal(slot: int, msg: String) -> void:
	## A skill dock refusal: a small line just above the slot that was tapped, gone in HUD_REFUSAL_LIFE.
	if not shows("notices") or callouts == null or msg == "":
		return
	if slot < 0 or slot >= dock.slots.size():
		toast(msg, "warn")
		return
	var b: Control = dock.slots[slot]
	var col := kind_color("warn")
	callouts.add("slot:%d" % slot, [[msg, callout_px(Rules.HUD_REFUSAL_FONT, Rules.HUD_REFUSAL_MIN_PT), col.lerp(Color.WHITE, 0.25)]], col,
			{"anchor": func(): return Vector2(b.get_global_rect().get_center().x, b.get_global_rect().position.y - 4.0 * ui_scale),
			"glyph": "warn", "life": Rules.HUD_REFUSAL_LIFE, "arrow": false, "rise": 6.0})


func note_line(text: String, kind := "info", seat := "") -> void:
	## A line with no place of its own: centred under the top bar and the status line (and a mission's strip,
	## which pushes `notices` down under it - mission_overlay.gd).
	if not shows("notices") or callouts == null:
		return
	var col := kind_color(kind)
	var opts := _icon_opts(seat, kind)
	opts["anchor"] = func(): return Vector2(root.get_viewport_rect().size.x * 0.5, _under_top() + 6.0 * ui_scale)
	opts["side"] = "below"
	opts["arrow"] = false
	opts["life"] = Rules.HUD_LINE_LIFE
	callouts.add("line", [[text, callout_px(Rules.HUD_CALLOUT_FONT * 0.9, Rules.HUD_CALLOUT_MIN_PT), col.lerp(Color.WHITE, 0.2)]], col, opts)


func start_banner(title: String, lines: Array) -> void:
	## The match-start banner: the map, then who you are / the dock's note (short lines), HUD_BANNER_LIFE s of
	## play (its clock stands still while the match is held - under the VERSUS card).
	if not shows("notices") or callouts == null or (title == "" and lines.is_empty()):
		return
	var rows := []
	if title != "":
		rows.append([title, callout_px(Rules.HUD_BANNER_FONT, Rules.HUD_CALLOUT_MIN_PT + 6.0), Color("f2fbff"), true])
	for l in lines:
		rows.append([str(l), callout_px(Rules.HUD_CALLOUT_FONT * 0.9, Rules.HUD_CALLOUT_MIN_PT), Color("c8e6ee")])
	callouts.add("banner", rows, Rules.seat_color(human), {"anchor": func(): return root.get_viewport_rect().size * Vector2(0.5, 0.3),
			"side": "center", "arrow": false, "life": Rules.HUD_BANNER_LIFE, "rise": 0.0,
			"hold": func(): return bool(main.paused) and not sim.over})


func set_waiting(lines: Array) -> void:
	## Online: the "waiting for every player to load" text in the middle until the round starts ([] clears it).
	if callouts == null:
		return
	if lines.is_empty():
		callouts.remove("wait")
		return
	var rows := []
	for i in range(lines.size()):
		rows.append([str(lines[i]), callout_px(Rules.HUD_CALLOUT_FONT * (1.25 if i == 0 else 0.9), Rules.HUD_CALLOUT_MIN_PT),
				Color("f2fbff") if i == 0 else Color("c8e6ee"), i == 0])
	callouts.add("wait", rows, INFO_COLOR, {"anchor": func(): return root.get_viewport_rect().size * Vector2(0.5, 0.38),
			"side": "center", "arrow": false, "life": INF, "rise": 0.0})


func pulse_last_stand(how: String) -> void:
	## The Last Stand's announcement: its own status line pulses for HUD_LS_PULSE s and says how the method falls.
	_ls_pulse = Rules.HUD_LS_PULSE
	_ls_how = how


func _under_top() -> float:
	## The first free y under the top bar, the status line and a mission's strip.
	var y := top_panel.position.y + top_panel.size.y if top_panel.visible else margins.y
	if status_label.text != "":
		y = status_label.position.y + status_label.size.y
	return maxf(y, notices.position.y)


var _ins := Vector4.ZERO               # UiKit.safe_insets for _ins_vp (callout_area; reset by layout())
var _ins_vp := Vector2(-1, -1)


func callout_area(vp: Vector2) -> Rect2:
	## Where a message may be drawn: the screen inside the device's safe area and the HUD's own margins. The insets
	## are read once per screen size (view audit: on the web they are a JavaScriptBridge.eval, and this runs every
	## frame a callout is up).
	if vp != _ins_vp:
		_ins_vp = vp
		_ins = UiKit.safe_insets(vp)
	var ins := _ins
	var l := maxf(ins.x, margins.x * 0.5)
	var t := maxf(ins.y, margins.y * 0.5)
	var r := maxf(ins.z, margins.z * 0.5)
	var b := maxf(ins.w, margins.w * 0.5)
	return Rect2(l, t, maxf(vp.x - l - r, 1.0), maxf(vp.y - t - b, 1.0))


func callout_blocked() -> Array:
	## The HUD parts a message never covers: the top bar (and the band it heads), PAUSE, the SEND panel, the dock
	## and its hint, the inspector, the coach card, the corner buttons.
	var out := []
	var vp := root.get_viewport_rect().size
	if top_panel.visible:
		out.append(Rect2(0, 0, vp.x, top_panel.position.y + top_panel.size.y + 3.0 * ui_scale))
	if status_label.text != "":
		var sw := status_label.get_theme_font("font").get_string_size(status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				status_label.get_theme_font_size("font_size")).x + 24.0 * ui_scale
		out.append(Rect2(vp.x * 0.5 - sw * 0.5, status_label.position.y - 3.0 * ui_scale, sw, status_label.size.y + 8.0 * ui_scale))   # (+ its pulse frame)
	for c in [pause_button, side_panel, dock, dock.hint_panel if dock else null, debug_button, chat_button, spectate_button, monster_icon, map_title]:
		if c and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	if debug_panel and debug_panel.visible:
		out.append(debug_panel.get_global_rect())
	if is_instance_valid(inspector) and inspector_id >= 0:
		out.append(inspector_rect())
	out.append_array(extra_ui_rects)
	return out


func _sync_status_pulse(dt: float) -> void:
	## The Last Stand announcement (pulse_last_stand): the status line pops, a red frame breathes behind it
	## about once a second, then fades - the line itself keeps saying LAST STAND for the rest of the match.
	if _ls_pulse <= 0.0 or status_label.text == "":
		_ls_pulse = maxf(_ls_pulse - dt, 0.0)
		status_glow.visible = false
		status_label.scale = Vector2.ONE
		return
	_ls_pulse = maxf(_ls_pulse - dt, 0.0)
	var age := Rules.HUD_LS_PULSE - _ls_pulse
	var wave := 0.5 + 0.5 * cos(age * TAU / 1.1)                     # 1 -> 0 -> 1, about once a second
	var fade := clampf(_ls_pulse / 0.6, 0.0, 1.0)
	var font := status_label.get_theme_font("font")
	var sw := font.get_string_size(status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, status_label.get_theme_font_size("font_size")).x
	var gw := sw + 36.0 * ui_scale
	status_glow.visible = true
	status_glow.size = Vector2(gw, status_label.size.y + 4.0 * ui_scale)
	status_glow.position = Vector2(status_label.position.x + (status_label.size.x - gw) * 0.5, status_label.position.y - 2.0 * ui_scale)
	status_glow.modulate = Color(1, 1, 1, (0.45 + 0.55 * wave) * fade)
	status_label.pivot_offset = status_label.size * 0.5
	status_label.scale = Vector2.ONE * (1.0 + 0.1 * wave * fade * clampf(1.0 - age / 2.5, 0.35, 1.0))


func skill_event(ev: Dictionary) -> void:
	## main's fx loop: a skill was cast (SkillDock.on_event toasts a rival's cast that touches you).
	if dock:
		dock.on_event(ev)


func show_banner(msg: String, seconds := 4.0) -> void:
	banner.text = msg
	banner.visible = true
	banner.size = Vector2.ZERO                        # re-fit the frame to the new text, centred
	banner.size = banner.get_combined_minimum_size()
	var vp := root.get_viewport_rect().size
	banner.position = Vector2((vp.x - banner.size.x) / 2.0, vp.y * 0.26)
	banner.modulate.a = 1.0
	_banner_time = seconds


# ------------------------------------------------------------------ overlays
# UI (Alpha 21 UI pass): PAUSE, VICTORY / DEFEAT, MATCH DETAILS and YOU'RE OUT are MatchScreens pages (UiKit's
# language, the player's faction accent) on full-screen layers over the match; the actions are the same as before.
# PAUSE carries no LAST STAND / TERRITORY switches (Daniele 2026-09-28): Last Stand is a match option (SETUP), territory
# a look (the wardrobe).
func pause_menu() -> void:
	if end_panel.visible:
		return
	var s := MatchScreens.open(pause_panel, mobile, _my_faction())
	var where := "%s · %s" % [str(main.map.get("name", "")).to_upper(), MatchScreens.clock(sim.time)]
	if main.online:                                   # a room never pauses (Alpha 11): the menu only
		s.card({"kicker": "ROOM %s" % Net.room_code, "headline": "MATCH MENU.",
				"body": "%s · the match keeps running\n%s" % [where, Net.net_stats_line()],
				"actions": [["RESUME  →", func(): pause_panel.visible = false], ["SETTINGS", _pause_settings],
				["LEAVE ROOM", main.to_menu, "secondary"]]})   # UI (0.22.1): a framed button, like the others (Daniele)
		_show_screen(pause_panel)
		return
	main.paused = true
	var resume := ["RESUME  →", func(): main.paused = false; pause_panel.visible = false]
	if main.get("director") != null:                  # TUTORIAL: PAUSE keeps working and gains LESSONS (§6)
		s.card({"kicker": where, "headline": "PAUSED.",
				"actions": [resume, [TutorialDirector.line("paused_lessons"), main.to_lessons], ["RESTART MATCH", main.restart],
				["SETTINGS", _pause_settings], ["MAIN MENU", main.to_menu, "secondary"]]})   # UI (0.22.1): framed
		_show_screen(pause_panel)
		return
	s.card({"kicker": where, "headline": "PAUSED.",
			"actions": [resume, ["RESTART MATCH", main.restart], ["SETTINGS", _pause_settings],
			["CAMPAIGN" if main.get("mission") != null else "EXIT MATCH", main.to_menu, "secondary"]]})   # CAMPAIGN: a mission leaves to its page (UI 0.22.1: framed)
	_show_screen(pause_panel)


var _end_winner := ""
var _end_rematch: Label                           # online results: the rematch line, updated in place
var _end_rematch_btn: Button
var _end_page := "result"                         # UI: the results screen's page - "result" or "details"


func _on_rematch_changed() -> void:
	## A vote arrived: refresh the rematch line and button only - rebuilding the panel replayed the rewards strip and
	## read as the screen reloading (Daniele, 0.20.10 playtest). On MATCH DETAILS nothing moves: BACK rebuilds the
	## results with the latest votes.
	if not end_panel.visible or _end_page != "result":
		return
	if is_instance_valid(_end_rematch) and is_instance_valid(_end_rematch_btn):
		_rematch_texts()
	else:
		show_end(_end_winner)


func _rematch_texts() -> void:
	var st: Dictionary = Net.rematch_status()
	var lines := []
	for who in st["ready"]:
		lines.append("%s  -  READY" % who)
	for who in st["waiting"]:
		lines.append("%s  -  not yet" % who)
	var hint := ""
	if st["mine"] and not (st["waiting"] as Array).is_empty():
		hint = "YOU'RE READY - waiting for %s" % ", ".join(st["waiting"])
	elif not st["mine"] and not (st["ready"] as Array).is_empty():
		hint = "%s %s a rematch - tap REMATCH" % [", ".join(st["ready"]), "wants" if (st["ready"] as Array).size() == 1 else "want"]
	elif not st["mine"]:
		hint = "Tap REMATCH to play again - it starts when everyone here is ready"
	_end_rematch.text = "REMATCH\n" + "\n".join(lines) + ("\n" + hint if hint != "" else "")
	var picks := Net.is_host() or Net.can_control()   # the room owner picks the random map; the others just vote
	_end_rematch_btn.text = "READY - WAITING" if st["mine"] else ("REMATCH ON A RANDOM MAP" if picks else "REMATCH")
	_end_rematch_btn.disabled = st["mine"]


func show_end(winner: String) -> void:
	_end_winner = winner
	main.paused = true
	out_panel.visible = false                          # the match ending wins over YOU'RE OUT lingering on top
	pause_panel.visible = false
	_end_page = "result"
	_build_end()
	if main.online and not Net.rematch_changed.is_connected(_on_rematch_changed):
		Net.rematch_changed.connect(_on_rematch_changed)


func show_end_details() -> void:
	## MATCH DETAILS (SCREEN-SYSTEM 20): every seat's numbers; BACK returns to the results.
	_end_page = "details"
	_build_end()


func _build_end() -> void:
	## VICTORY / DEFEAT (SCREEN-SYSTEM 18 / 19): the outcome readable before any numbers - the kicker, VICTORY. /
	## DEFEAT. / DRAW., the map, your faction's character, three real numbers - then PROGRESSION's strip exactly as it
	## was (main.rewards, granted once at the match end: a rebuild only draws it again), then the ways on.
	var winner := _end_winner
	var won := sim.allied(winner, human)               # team modes: allies win together
	var draw := winner == ""
	var s := MatchScreens.open(end_panel, mobile, _my_faction())
	var seats: Array = sim.factions.keys()
	var team := sim.teams.has(human)
	var ffa := not team and seats.size() > 2
	var outcome := "VICTORY" if won else ("DRAW" if draw else "DEFEAT")
	var where := "%s · %s" % [main.mode, MatchScreens.clock(sim.time)]
	if main.online:
		where = "ROOM %s · %s" % [Net.room_code, where]
	var primary := []
	var quiet := []
	if not main.online:                                # CONTINUE opens PLAY; RETRY replays this map as it was
		primary = ["CONTINUE  →", func(): main.to_menu("play")] if won else ["RETRY  →", main.restart]
		quiet = [["REMATCH · RANDOM MAP", main.rematch_random], ["CHANGE LOADOUT", func(): main.to_menu("armies")],
				["HOME", main.to_menu]]
	if _end_page == "details":
		s.details({"name": str(main.map.get("name", "")), "sub": where, "outcome": outcome, "primary": primary,
				"back": func():
					_end_page = "result"
					_build_end()}, MatchScreens.seat_table(sim, human, _seat_heads()))
		_show_screen(end_panel)
		return
	var placed := Progression.placements(sim)
	var line := MatchScreens.verdict(won, draw, int(main.seed_value))   # the syndicate's joke for it (Daniele)
	var kicker: String = line[0]
	if ffa and not won and not draw:                   # an FFA loss says where you finished instead
		kicker = "FINISHED %s OF %d" % [MatchScreens.ordinal(int(placed.get(human, seats.size()))).to_upper(), seats.size()]
	var sub := where + "  ·  " + (("Last Stand: %s" % sim.last_stand_method.to_upper()) if sim.last_stand_active else "decided before the Last Stand")
	if not won and not draw and seats.size() > 2:     # who took it, when it wasn't a plain duel
		sub = "Won by %s  ·  %s" % [_who_line(winner), sub]
	sub = _versus_line(seats) + "\n" + sub           # HUD pass: who played - a human by name, an AI by faction and level
	if draw and sim.draw_line != "":                   # 7:00, a neutral last platform: the funny call-out (0.19.0)
		sub = str(sim.draw_line) + "\n" + sub
	var st := Progression.seat_stats(sim, human)
	var third := [str(st["captures"]), "Captures"]
	if ffa:
		third = ["%s / %d" % [MatchScreens.ordinal(int(placed.get(human, seats.size()))), seats.size()], "Placement"]
	var extras := []
	var strip := _reward_strip(s.reward_scale(ui_scale))   # PROGRESSION: kept whole
	if strip != null:
		extras.append(strip)
	if main.online:                                   # the rematch vote: who is ready, what happens next (updated in place)
		var rs: Dictionary = Net.rematch_status()
		_end_rematch = UiKit.label(s, "", 14, UiKit.STAR)
		_end_rematch.custom_minimum_size.y = UiKit.line_h(s, 14) * ((rs["ready"] as Array).size() + (rs["waiting"] as Array).size() + 2)
		extras.append(_end_rematch)
		primary = ["REMATCH", func(): main.rematch_random()]
		quiet = [["LEAVE ROOM", main.to_menu]]
	var out := s.result({"won": won, "draw": draw, "kicker": kicker, "headline": str(line[1]),
			"name": str(main.map.get("name", "")), "sub": sub,
			"metrics": [[MatchScreens.clock(sim.time), "Match time"],
					["%d / %d" % [MatchScreens.nodes_held(sim, human), sim.nodes.size()], "Nodes held"], third],
			"primary": primary, "details": show_end_details, "quiet": quiet, "extras": extras})
	if main.online:
		_end_rematch_btn = out.get("primary") as Button
		_rematch_texts()
	_show_screen(end_panel)


func _reward_strip(scale := 1.0) -> Control:
	## PROGRESSION (0.20.1): what the match paid (main.rewards, set once at the match end), or nothing.
	var r = main.get("rewards")
	return RewardStrip.make(r, scale) if r is Dictionary and not (r as Dictionary).get("lines", []).is_empty() else null


func _who_line(seat: String) -> String:
	## One seat in a line: "DANIELE · NULL" for a human (your own: "(YOU)" after the name), "EMBER · VETERAN AI"
	## for an AI (main.seat_who).
	if not main.has_method("seat_who"):
		return str(UiKit.NAMES.get(str(sim.factions.get(seat, "")), seat))
	var w: Dictionary = main.seat_who(seat)
	if bool(w["human"]):
		var nm := str(w["name"]) if str(w["name"]) != "" else "PLAYER"
		return "%s%s  ·  %s" % [nm, " (YOU)" if bool(w["you"]) and nm != "YOU" else "", str(w["faction"])]   # the "YOU" fallback needs no tag
	return "%s  ·  %s" % [str(w["faction"]), str(w["tag"])]


func _versus_line(seats: Array) -> String:
	## The results' "who played" line: you, then everyone you faced (a free-for-all past three: "+N more").
	var you := _who_line(human)
	var rivals := []
	for s in seats:
		if str(s) != human and not sim.allied(str(s), human):
			rivals.append(_who_line(str(s)))
	if rivals.is_empty():
		return you
	if rivals.size() > 2:
		return "%s  vs  %s, %s +%d more" % [you, rivals[0], rivals[1], rivals.size() - 2]
	return "%s  vs  %s" % [you, "  /  ".join(rivals)]


func _seat_heads() -> Dictionary:
	## MATCH DETAILS column heads: seat -> [head, second line] - a human's name (yours marked YOU) over the faction,
	## an AI's faction over its level (main.seat_who).
	var out := {}
	if not main.has_method("seat_who"):
		return out
	for s in sim.factions.keys():
		var w: Dictionary = main.seat_who(str(s))
		if bool(w["human"]):
			var nm := str(w["name"]) if str(w["name"]) != "" else "PLAYER"
			out[s] = ["%s (YOU)" % nm if bool(w["you"]) and nm != "YOU" else nm, str(w["faction"])]
		else:
			out[s] = [str(w["faction"]), str(w["tag"])]
	return out


func _my_faction() -> String:
	return str(sim.factions.get(human, main.SEAT_FACTIONS.get(human, "vex")))


# UI (Alpha 21, screen 25; Daniele: "reconnecting good"): when a guest's match host goes silent the match freezes; this
# says why and how long the game waits (Net.HOST_GRACE - then Net.fail returns to ONLINE, where RECONNECT takes the seat
# back), with LEAVE MATCH meanwhile. It closes by itself when the snapshots return. Net's state is only read here.
const RECONNECT_AFTER := 2.5                      # s of host silence before it shows (a hiccup never flashes it)
var _reconnect_left := -1


func _reconnect_watch() -> void:
	var silent: float = Net._since_snapshot if Net.active and not Net.hosting and not sim.over else 0.0
	if silent >= RECONNECT_AFTER and not end_panel.visible:
		var left := maxi(0, int(ceil(Net.HOST_GRACE - silent)))
		if reconnect_panel.visible and left == _reconnect_left:
			return
		show_reconnect(left)                           # redrawn once a second, for the countdown
	elif reconnect_panel.visible:
		reconnect_panel.visible = false
		_reconnect_left = -1


func _pause_settings() -> void:
	## PAUSE > SETTINGS (Daniele 2026-09-28: yes): the DISPLAY settings that make sense mid-match - GRAPHICS (its 3D side
	## from the next match), FRAME RATE and DETAIL - one tap cycles each (PerfProfile / Rules, saved as in SETTINGS); SOUND /
	## VOLUME and MUSIC / MUSIC VOL (Music) are two rows of toggles under BACK.
	var s := MatchScreens.open(pause_panel, mobile, _my_faction())
	var fps_now := "AUTO (%d)" % int(PerfProfile.PROFILES[PerfProfile.level()]["fps"]) if PerfProfile.fps_mode() == "auto" 			else PerfProfile.fps_mode()
	var gfx_now := "AUTO (%s)" % ("PHONE" if PerfProfile.is_phone() else "FULL") if PerfProfile.mode() == "auto" 			else str(PerfProfile.MODE_NAMES[PerfProfile.mode()])
	s.card({"kicker": "PAUSED", "headline": "SETTINGS.",
			"body": "Tap a setting to change it. GRAPHICS changes the 3D from the next match; the rest right away.",
			"pairs": [["SOUND: " + ("ON" if Sfx.sound_on() else "OFF"), func(): Sfx.set_on(not Sfx.sound_on()); _pause_settings()],   # SOUND
				["VOLUME: " + Sfx.volume_label(), func(): Sfx.set_volume(Sfx.next_volume()); _pause_settings()]],
			"pairs2": [["MUSIC: " + ("ON" if Music.music_on() else "OFF"), func(): Music.set_on(not Music.music_on()); _pause_settings()],   # MUSIC
				["MUSIC VOL: " + Music.volume_label(), func(): Music.set_volume(Music.next_volume()); _pause_settings()]],
			"actions": [["BACK  →", pause_menu],
				["GRAPHICS: " + gfx_now, func(): PerfProfile.set_mode(PerfProfile.next_mode()); _pause_settings()],
				["FRAME RATE: " + fps_now, func(): PerfProfile.set_fps(PerfProfile.next_fps()); _pause_settings()],
				["DETAIL: " + ("LOW" if Rules.low_detail else "FULL"), func(): Rules.low_detail = not Rules.low_detail; _pause_settings()]]})
	_show_screen(pause_panel)


func show_reconnect(left: int) -> void:
	_reconnect_left = left
	var s := MatchScreens.open(reconnect_panel, mobile, _my_faction())
	s.card({"kicker": "ONLINE MATCH", "headline": "CONNECTION INTERRUPTED.",
			"body": "The match host stopped answering, so the match is frozen.
RECONNECTING...  %d s
If it doesn't come back you return to ONLINE, where RECONNECT takes your seat back." % left,
			"actions": [["LEAVE MATCH", main.to_menu, "secondary"]]})
	if not reconnect_panel.visible:
		_show_screen(reconnect_panel)


func _screen_layer() -> Control:
	## One in-match screen's layer: the whole canvas, hidden until MatchScreens fills it.
	var c := Control.new()
	c.visible = false
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(c)
	return c


func _show_screen(layer: Control) -> void:
	_screens_vp = root.get_viewport_rect().size
	layer.visible = true
	root.move_child(layer, -1)                         # over the monster icon / SPECTATE button added after it
	root.move_child(rotate_hint, -1)                   # (the portrait hint stays on top of everything)


# ------------------------------------------------------------------ debug panel
func _build_debug() -> void:
	## Debug controls for playtests (Daniele, 2026-09-25): live sliders, thumb-sized, top-right under PAUSE,
	## wide ranges on purpose. Also prints FPS to the console every 5 s while open.
	debug_button = button("Debug", Callable(), 110, 50 if not mobile else 78, 20)   # 78: matches the phone-tuned default height (>= 44 pt)
	debug_button.toggle_mode = true
	debug_button.size = debug_button.custom_minimum_size
	root.add_child(debug_button)
	debug_button.visible = not main.online and Rules.debug_tools   # online: the rules are the host's, not live-tunable;
	                                                               # offline only when DEBUG TOOLS is on in OPTIONS (0.18.7)
	chat_button = button("Chat", func(): Net.open_chat(), 110, 50 if not mobile else 78, 20)   # online: the room chat (78: >= 44 pt)
	chat_button.size = chat_button.custom_minimum_size
	chat_button.visible = main.online
	root.add_child(chat_button)
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	style_panel(debug_panel, Color("2ee6ff"))
	root.add_child(debug_panel)
	debug_button.toggled.connect(func(on: bool): debug_panel.visible = on)
	# the panel's own size is clamped to the screen in layout() (Daniele, 0.18.8: "the Debug panel's last
	# button runs off the phone screen") - a ScrollContainer (Godot doesn't count its content against its
	# own minimum size, unlike a bare VBoxContainer) lets that clamp actually take effect instead of the
	# panel re-growing to fit every slider and button
	var debug_scroll := ScrollContainer.new()
	debug_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	debug_panel.add_child(debug_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_scroll.add_child(box)
	box.add_child(text_label("Debug - live, resets on reload", 20))
	# (0.18.7: SIEGE is deactivated - its deck / platform / door / platform-fight tunables left the panel)
	var forge := _debug_slider(box, "Forge bonus", 0.0, 200.0, 5.0, Rules.forge_bonus * 100.0, "+%.0f%% attack",
			func(v: float): Rules.forge_bonus = v / 100.0)
	var hide := button("", Callable(), 0, 44, 18)
	var hide_text := func(): hide.text = "Enemy counts: %s" % ("HIDDEN" if Rules.hide_enemy_counts else "SHOWN")
	hide_text.call()
	hide.pressed.connect(func():
		Rules.hide_enemy_counts = not Rules.hide_enemy_counts
		hide_text.call()
		for bid in badges:
			badges[bid]["owner"] = "?")
	hide.disabled = main.online                      # online: the host's room setting
	box.add_child(hide)
	var low := button("", Callable(), 0, 44, 18)
	var low_text := func(): low.text = "Detail: %s" % ("LOW (fewer river patches and vat residents)" if Rules.low_detail else "FULL")
	low_text.call()
	low.pressed.connect(func():
		Rules.low_detail = not Rules.low_detail
		low_text.call())
	box.add_child(low)
	# BALANCE PRESET: the default numbers (Daniele's 0.18.9 pick) or the pre-0.18.9 "legacy" numbers (Rules.BALANCE_PRESETS), live;
	# online it is the host's room setting (it travels with the room's rules)
	var bal := button("", Callable(), 0, 44, 18)
	var bal_text := func(): bal.text = "Balance: %s" % ("DEFAULT" if Rules.BALANCE_PRESET == "" else Rules.BALANCE_PRESET.to_upper() + " (pre-0.18.9 numbers)")
	bal_text.call()
	bal.pressed.connect(func():
		var names: Array = [""] + Rules.BALANCE_PRESETS.keys()
		Rules.apply_balance(names[(names.find(Rules.BALANCE_PRESET) + 1) % names.size()])
		forge.value = Rules.forge_bonus * 100.0
		bal_text.call()
		toast("Balance: %s" % ("default numbers" if Rules.BALANCE_PRESET == "" else Rules.BALANCE_PRESET + " - the pre-0.18.9 numbers, for comparison") + "; neutral garrisons change from the next match"))
	bal.disabled = main.online
	box.add_child(bal)
	var reset := button("Reset to rules", func():
		forge.value = Rules.FORGE_BONUS_DEFAULT * 100.0, 0, 44, 18)
	box.add_child(reset)


func _debug_slider(box: Control, text: String, lo: float, hi: float, step: float, value: float,
		fmt: String, apply: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label := text_label(text, 18)
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var out := text_label(fmt % value, 18)
	out.custom_minimum_size = Vector2(110, 0)
	row.add_child(out)
	slider.value_changed.connect(func(v: float):
		apply.call(v)
		out.text = fmt % v)
	return slider


var _badge_dirs := {}
var _badge_screen := {}                 # node id -> badge centre on screen (fixed camera: laid out once)
var _layout_vp := Vector2(-1, -1)       # viewport size and camera of the last layout (-1: none yet)
var _layout_xf := Transform3D()
var _last_xf := Transform3D()           # the camera last frame (still or moving)
var _still := 0                         # frames the camera has held still since it moved
var _anchors := {}                      # node id -> [badge offset from the platform's screen centre, platform scale] at the last layout


func _layout_badges(cam: Camera3D) -> void:
	## Every badge floats in the void beside its own node (Daniele, Alpha 16: "UI should always float
	## in the void next to a node"): candidate spots all round the platform's drawn rim are scored
	## against every platform, every deck and the badges already placed, on screen, at the badge's
	## real size; the one that covers nothing wins, the near side and the shortest reach break ties.
	## Alpha 18 (Daniele: "make sure ... nothing overflows" on phones): the top and bottom bands, the
	## send panel and the right-hand buttons count as off-screen, and a badge that still touches one is
	## slid clear of it (_clear_of).
	var vp := get_viewport().get_visible_rect().size
	var plat := {}                                        # id -> [centre, radius] on screen
	for n in sim.nodes:
		var c := cam.unproject_position(n["pos"])
		var r := 0.0
		for k in range(8):
			var a := TAU * k / 8.0
			r = maxf(r, cam.unproject_position((n["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * Rules.R).distance_to(c))
		plat[n["id"]] = [c, r]
	for n in sim.nodes:                                   # RELAY V2: a relay's button pad is covered like a platform
		var bs := RelayView.button_screen(cam, main.vis, n["id"])
		if not bs.is_empty():
			plat[-1 - int(n["id"])] = bs
	var decks := []                                       # [a, b, half width] on screen
	for e in sim.edges:
		var pa: Vector3 = sim.nodes[e["a"]]["pos"]
		var pb: Vector3 = sim.nodes[e["b"]]["pos"]
		var mid := (pa + pb) / 2.0
		var side := ((pb - pa) as Vector3).cross(Vector3.UP).normalized()
		var hw := cam.unproject_position(mid + side * Rules.W * 0.5).distance_to(cam.unproject_position(mid))
		decks.append([cam.unproject_position(pa), cam.unproject_position(pb), hw])
	_badge_screen = {}
	var placed := []                                      # [centre, radius]
	var down := Vector2(0, 1)
	var blocked := [Rect2(0, 0, vp.x, top_used()), Rect2(0, vp.y - bottom_used(), vp.x, bottom_used())]
	for c in [side_panel, pause_button, debug_button, chat_button, dock]:   # Alpha 18: never under the HUD
		if c and c.visible:
			blocked.append((c as Control).get_global_rect().grow(4.0))
	for n in sim.nodes:
		var id: int = n["id"]
		var panel: Control = badges[id]["panel"]
		var sz: Vector2 = panel.get_combined_minimum_size()
		var rb: float = maxf(maxf(sz.x, sz.y) * 0.5, 15.0 * ui_scale) + 2.0
		var c: Vector2 = plat[id][0]
		var best: Vector2 = c + down * (float(plat[id][1]) + rb)
		var best_score := INF
		for k in range(24):
			var a := TAU * k / 24.0
			var rim: Vector2 = cam.unproject_position((n["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * Rules.R)
			var dir: Vector2 = (rim - c).normalized() if rim.distance_to(c) > 0.5 else down
			for reach in [3.0, 10.0, 22.0]:
				var p: Vector2 = rim + dir * (rb + reach)
				var cover := 0.0
				for pid in plat:
					cover += maxf(0.0, rb + plat[pid][1] - p.distance_to(plat[pid][0]))
				for d in decks:
					var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, d[0], d[1])
					cover += maxf(0.0, rb + d[2] - p.distance_to(q))
				for o in placed:
					cover += 2.0 * maxf(0.0, rb + o[1] + 2.0 - p.distance_to(o[0]))
				var off := maxf(0.0, rb - p.x) + maxf(0.0, p.x + rb - vp.x) + maxf(0.0, rb - p.y) + maxf(0.0, p.y + rb - vp.y)
				var box := Rect2(p - sz * 0.5, sz)
				for b in blocked:
					if box.intersects(b):
						var over := box.intersection(b)
						off += minf(over.size.x, over.size.y) + 8.0
				var score: float = cover * 10.0 + off * 20.0 + reach * 0.4 - dir.dot(down) * 3.0
				if score < best_score:
					best_score = score
					best = p
		if Rect2(Vector2.ZERO, vp).has_point(c):          # a node off screen (close-up) keeps its spot
			best = _clear_of(best, sz, blocked, vp)
		_badge_screen[id] = best
		_anchors[id] = [best - c, _screen_scale(cam, n["pos"], c)]
		placed.append([best, rb])


func _screen_scale(cam: Camera3D, pos: Vector3, c: Vector2) -> float:
	## A platform's radius on screen along the camera's right axis (the badge offset's scale while the camera moves).
	return maxf(cam.unproject_position(pos + cam.global_transform.basis.x * Rules.R).distance_to(c), 0.5)


func _follow_badges(cam: Camera3D) -> void:
	## Camera in motion (the Last Stand zoom): each badge keeps its last layout's spot relative to its platform, scaled
	## with the platform's size on screen - two projections per node instead of the full scoring.
	var vp := get_viewport().get_visible_rect().size
	for n in sim.nodes:
		var a: Array = _anchors.get(n["id"], [])
		if a.is_empty():
			continue
		var c := cam.unproject_position(n["pos"])
		var p: Vector2 = c + (a[0] as Vector2) * (_screen_scale(cam, n["pos"], c) / float(a[1]))
		_badge_screen[n["id"]] = Vector2(clampf(p.x, 2.0, vp.x - 2.0), clampf(p.y, 2.0, vp.y - 2.0))


func _clear_of(p: Vector2, sz: Vector2, blocked: Array, vp: Vector2) -> Vector2:
	## Last resort when every spot round the rim touches the HUD or the screen edge: slide the badge
	## the shortest way out of each HUD panel it still overlaps, then back inside the screen.
	for b in blocked:
		var box := Rect2(p - sz * 0.5, sz)
		if not box.intersects(b):
			continue
		var r: Rect2 = b
		var dx := (r.end.x - box.position.x) if p.x > r.get_center().x else (r.position.x - box.end.x)
		var dy := (r.end.y - box.position.y) if p.y > r.get_center().y else (r.position.y - box.end.y)
		if absf(dx) < absf(dy):
			p.x += dx
		else:
			p.y += dy
	return Vector2(clampf(p.x, sz.x * 0.5 + 2.0, vp.x - sz.x * 0.5 - 2.0), clampf(p.y, sz.y * 0.5 + 2.0, vp.y - sz.y * 0.5 - 2.0))


func badge_anchor(n: Dictionary) -> Vector3:
	## A 3D estimate of the badge's spot, used only so main._fit_camera leaves room for it; the badge
	## itself is placed on screen by _layout_badges. Just outside the platform, in the gap furthest
	## from any of its bridges, leaning toward the viewer (Daniele: "HUD should always be placed in
	## areas beyond the platform, not overlapping a corridor or a platform"). Computed once per node.
	var id: int = n["id"]
	if not _badge_dirs.has(id):
		var toward_viewer := Vector3(0, 0, 1).rotated(Vector3.UP, Rules.view_yaw)
		var decks := []
		for link in sim.adj[id]:
			decks.append(((sim.nodes[link[0]]["pos"] - n["pos"]) as Vector3).normalized())
		var best := toward_viewer
		var best_score := -INF
		for k in range(16):
			var d := toward_viewer.rotated(Vector3.UP, TAU * k / 16.0)
			var gap := PI
			for dd in decks:
				gap = minf(gap, d.angle_to(dd))
			var score := gap + 0.35 * d.dot(toward_viewer)      # clear of bridges first, then near side
			if score > best_score:
				best_score = score
				best = d
		_badge_dirs[id] = best
	return n["pos"] + (_badge_dirs[id] as Vector3) * (Rules.R + 2.3) + Vector3(0, 0.3, 0)
