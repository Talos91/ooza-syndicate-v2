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
var music_button: Button              # MUSIC (0.22.x): left of PAUSE, a drawn note glyph (Music.toggle_on())
var _music_glyph: Control
var side_panel: PanelContainer
var side_box: VBoxContainer
var count_label: Label
var send_tank: SendTank                 # ui-node: the SEND tank (one container, 4 levels)
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
var inspector_tier: Control             # ui-node: the card's tier chip, units bar and armour shields (custom-drawn, NodeNoir)
var inspector_units: Control
var inspector_shields: Control
var inspector_col := Color.WHITE        # ui-node: this node's UI colour (your accent on yours, the owner's seat colour else)
var inspector_actions: Array = []
var notices: Control                   # HUD pass: no stack any more - only where the old one began (a mission's
                                       # strip still pushes it down: note_line's lines start under it)
var banner: Label
var _banner_time := 0.0
var status_label: Label                # Last Stand status under the top bar
var catchup_tag: PanelContainer        # CATCH-UP (Rules.CATCHUP_*): "CATCH-UP +15 %" under your chips while your side trails
var hint: Label
var map_title: Label
var dock: SkillDock
var skill_targets: Control             # the dock's target highlights: over the badges, under the panels
var overlay: HudOverlay                # 0.19.0: monster reach, halo rings, relay-outcome preview, danger symbols
var action_buttons: Dictionary = {}    # stable action name -> the inspector's Button (tutorial spotlight, spec I)
var switch_ring: Control                # 0.19.0: the SWITCH button's READY / cooldown ring (SwitchRing)
var _inspector_guides: Control          # 0.23.x radial redesign: the glowing arc the card fan stands on
var _inspector_opened_ms := 0           # when the ring opened: the cards deal out from the vat over ~0.25 s
var _fan := {}                          # this frame's fan geometry for _draw_inspector_guides
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
var _chat_dot: Control                    # Alpha 24: the unread count on the chat button (the pack's notification dot)
var _chat_poll := 0.0
var debug_panel: PanelContainer
var debug_tag: Label                    # PROTO DEBUG: "DEBUG x4 · PROD x10" on screen while anything is not x1
var _debug_proto: VBoxContainer         # PROTO DEBUG: the controls (hidden where the debug is off: online, lessons, missions)
var _debug_off_note: Label
var _debug_last_node := -1              # PROTO DEBUG: the node last opened (tapped) - the +100 target
var _debug_add_button: Button
var _debug_vp := Vector2(-1, -1)        # the viewport size of the last layout()
var _debug_box: VBoxContainer          # the Debug panel's content (its height: the ScrollContainer reports none)
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
const BADGE_EMBLEM_OWNER := Vector2(24, 24)    # in place of a hidden count: about the count's own height
# Alpha 19: every node badge is one fixed box (x ui_scale) sized for its largest normal content - a
# 3-digit count over an emblem and a short sub line; longer text steps its font down, then clips.
# 0.23.6 (Daniele: "make numbers of units in structure bigger"): count 16 -> 22 px, the box 44 x 33 -> 54 x 40;
# 0.23.7 ("another 10 %"): count 24 px, the box 59 x 44.
const BADGE_SIZE := Vector2(59, 44)
const BADGE_COUNT_FONT := 24
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
	# Alpha 24 Neon Noir: the score pill - glass with the seat's colour on its rim (seat colours stay: every screen shows the
	# room's colours), yours the brightest; a seat that is out dims (_sync_top_chips swaps the box)
	chip.add_theme_stylebox_override("panel", _score_box(seat, "score_pill_mine" if mine else "score_pill"))
	chip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
		var nm := text_label(str(who["name"]), 15, HudSkin.INK if mine else HudSkin.MUTED)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(minf(TOP_NAME_W, UI_FONT.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * ui_scale)).x / ui_scale + 2.0) * ui_scale, 0)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		chip.custom_minimum_size.x += nm.custom_minimum_size.x + 4.0 * ui_scale
	var lbl := text_label("000", 15, HudSkin.INK)
	lbl.add_theme_font_override("font", SYMBOL_FONT)      # monospace: the digits never shift the chip
	lbl.custom_minimum_size = Vector2(28 * ui_scale, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(lbl)
	into.add_child(chip)
	top_chips[seat] = {"panel": chip, "emblem": emb, "label": lbl, "box": "score_pill_mine" if mine else "score_pill"}


func _score_box(seat: String, id: String) -> StyleBox:
	var m := Vector4(6.0, 3.0, 6.0, 3.0) * ui_scale
	return HudNoir.box(id, Rules.seat_color(seat), m)


func _exit_tree() -> void:
	UiTheme.match_dark(false)                         # Neon Noir: the menus follow the player's theme again


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
	# Alpha 24 Neon Noir (Daniele 2026-11-02): the match is dark only, its chrome in your faction's colour
	UiTheme.match_dark(true)
	HudNoir.setup(str(sim.factions.get(human, "vex")), ui_scale)
	var accent := HudNoir.accent
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
		l.add_theme_color_override("font_outline_color", HudSkin.outline())
		badge.add_child(l)
		var sub := text_label("", BADGE_SUB_FONT, HudSkin.sub_ink())
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub.clip_text = true
		sub.add_theme_constant_override("outline_size", 2)  # crisp on the see-through box
		sub.add_theme_color_override("font_outline_color", HudSkin.outline())
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
		build_bar.position = Vector2(inset, _badge_px.y - 6.5 * ui_scale)   # Alpha 24: the pack's pill bar (BadgeLayer: B19 / B20)
		build_bar.size = Vector2(_badge_px.x - 2.0 * inset, 4.0 * ui_scale)
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
	# GMN-1 layout (the director's QA/layout-*.json): on a phone the score words are 14 pt, the clock 16, the status line 13 -
	# the top bar (capsule, pills, emblems, clock, status line) is built at that scale, everything else at ui_scale.
	var keep_s := ui_scale
	if mobile and HudNoir.has("top_capsule"):
		ui_scale = maxf(ui_scale, pt(14.0) / 15.0)
	top_panel = PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", HudNoir.box("top_capsule", Color(0, 0, 0, 0), Vector4(6, 6, 6, 6) * ui_scale))
	top_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(top_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(10 * ui_scale))
	top_panel.add_child(bar)
	top_left = HBoxContainer.new()
	top_left.add_theme_constant_override("separation", int(TOP_CHIP_GAP * ui_scale))
	bar.add_child(top_left)
	stats_label = text_label("00:00", 22, HudSkin.INK)
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
	status_glow.add_theme_stylebox_override("panel", HudNoir.box("status_pill", Color(0, 0, 0, 0), Vector4.ZERO))
	status_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_glow.visible = false
	root.add_child(status_glow)
	status_label = text_label("", 18, Color("ffb0b0"))
	ui_scale = keep_s
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Alpha 24 Neon Noir: the line sits on the red status pill, as wide as its words (_fit_status); empty, nothing shows. The
	# seconds ("9 s") sit in an amber capsule (_draw_status_secs, like the board's NEXT DROP 6s)
	status_label.add_theme_stylebox_override("normal", HudNoir.box("status_pill", Color(0, 0, 0, 0), Vector4(16.0, 1.0, 16.0, 1.0) * ui_scale))
	_status_secs = Control.new()
	_status_secs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_secs.draw.connect(_draw_status_secs)
	status_label.add_child(_status_secs)
	status_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(status_label)
	catchup_tag = PanelContainer.new()                 # CATCH-UP: your side only (the HUD shows no rival modifiers)
	catchup_tag.add_theme_stylebox_override("panel", HudNoir.box("catchup_tag", Color(0, 0, 0, 0), Vector4(10, 4, 10, 4) * ui_scale))
	catchup_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catchup_tag.add_child(text_label("CATCH-UP +%d %%" % int(round((Rules.CATCHUP_PRODUCTION - 1.0) * 100.0)), 18, HudNoir.GOOD))
	catchup_tag.modulate.a = 0.0
	catchup_tag.visible = false
	root.add_child(catchup_tag)
	# Alpha 24: PAUSE and MUSIC are the pack's square icon buttons (B6 with the D pause / music icons), the same height as
	# before (phones: 78 x ui_scale, >= 44 pt)
	var pb_h: float = (52.0 if not mobile else 78.0) * ui_scale
	pause_button = button("", pause_menu, pb_h / ui_scale, pb_h / ui_scale)
	pause_button.tooltip_text = "PAUSE"
	_icon_button(pause_button, "pause")
	root.add_child(pause_button)
	# MUSIC (Daniele 2026-09-29/30): left of PAUSE, same height - the top-right button's twin (its note: the D music icon)
	music_button = button("", Callable(), pb_h, -1, 19)
	music_button.custom_minimum_size = Vector2(pb_h, pb_h)
	music_button.size = music_button.custom_minimum_size
	_icon_button(music_button, "")
	music_button.tooltip_text = "MUSIC"
	music_button.pressed.connect(func():
		Music.toggle_on()                            # OFF at once, everywhere
		_music_glyph.queue_redraw())
	root.add_child(music_button)
	_music_glyph = Control.new()
	_music_glyph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_music_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_glyph.size = music_button.size
	_music_glyph.draw.connect(func(): _draw_music_note(_music_glyph))
	music_button.add_child(_music_glyph)
	# side command panel (Alpha 11: 100/75/50/25 + the selected vat's count)
	side_panel = PanelContainer.new()
	# Alpha 24 Neon Noir: the SEND housing - a container, so it holds living ooze and drips (its buttons never do)
	# ui-node (Daniele 2026-11-04): ONE tank instead of four share buttons and no SEND / DRAG A VAT words - SendTank draws its own
	# frame, the goo at the picked share, the gauge ticks and the share / units on the surface; the panel is just its holder.
	side_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	side_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(side_panel)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 0)
	side_panel.add_child(side_box)
	send_tank = SendTank.new()
	send_tank.custom_minimum_size = Vector2(112.0, 4.0 * (78.0 if mobile else 66.0) + 74.0) * ui_scale
	var tank_s := ui_scale
	if mobile and HudNoir.has("send_tank"):          # GMN-1 layout: 4 bands of 60 pt, 59 wide, caps + drips round them
		send_tank.custom_minimum_size = Vector2(pt(66.0), pt(4.0 * 60.0 + 64.0)).round()
	elif HudNoir.has("send_tank"):                   # ui-demo-hud-scale: the desktop tank keeps its own proportions, scaled as a whole
		tank_s = ui_scale * pt(4.0 * 60.0 + 64.0) / send_tank.custom_minimum_size.y   # (caps, ticks, words) to the pt layout's height
		send_tank.custom_minimum_size = (send_tank.custom_minimum_size * tank_s / ui_scale).round()
	send_tank.setup(self, main, tank_s, UI_FONT)
	side_box.add_child(send_tank)
	count_label = text_label("", 14, accent)                # (kept, hidden: the tank shows the units on its goo)
	count_label.visible = false
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
	version_label = text_label(Rules.version_label(), 14, Color(1, 1, 1, 0.5))
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


func _icon_button(b: Button, icon_name: String) -> void:
	## Alpha 24 Neon Noir: a square HUD button (part square_button: glass, the accent rim), its white D icon centred.
	_noir_skin(b, "square_button")
	b.add_theme_color_override("font_pressed_color", HudSkin.INK)
	b.size = b.custom_minimum_size
	if icon_name != "":
		var side := minf(b.size.x, b.size.y) * 0.44
		b.add_child(UiTheme.icon_rect(icon_name, side, HudSkin.INK, (b.size - Vector2(side, side * 1.15)) / 2.0))


func _send_skin(b: Button, share := 1.0) -> void:
	## Alpha 24 Neon Noir: a SEND share button is a clean glass pill (no drips: those stay on the housing). With the director's
	## revision-6 parts it is a little vat (HudLiquid) holding its share of lit ooze in your faction's colour - 100 / 75 / 50 /
	## 25 % - dim while idle, lit when picked; the words stay white over it.
	_noir_skin(b, "send_button")
	if not HudNoir.has("send_button_liquid"):
		return
	var c := Vector4(4, 4, 4, 4) * ui_scale
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = c.x
		e.content_margin_top = c.y
		e.content_margin_right = c.z
		e.content_margin_bottom = c.w
		b.add_theme_stylebox_override(st, e)
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, HudNoir.INK)
	b.add_theme_constant_override("outline_size", int(4 * ui_scale))
	var vat := HudLiquid.new()
	vat.setup("send_button", HudNoir.accent, share * 3.1)
	vat.show_behind_parent = true                     # (the button's words draw over it)
	vat.set_anchors_preset(Control.PRESET_FULL_RECT)
	vat.set_level(share, true)
	b.add_child(vat)
	b.draw.connect(_send_vat_state.bind(b, vat))


func _send_vat_state(b: Button, vat: HudLiquid) -> void:
	## A SEND vat follows its button: idle (dim liquid, the normal rim), hover (brighter rim), picked (lit liquid, the picked
	## rim), disabled.
	var mode := b.get_draw_mode()
	var picked := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var id := "send_button_disabled" if mode == BaseButton.DRAW_DISABLED else ("send_button_picked" if picked else
			("send_button_hover" if mode == BaseButton.DRAW_HOVER else "send_button"))
	var fill := "send_button_disabled" if mode == BaseButton.DRAW_DISABLED else ("send_button_hover" if mode == BaseButton.DRAW_HOVER else "send_button")
	if vat.fill_part != fill:
		vat.fill_part = fill
		vat.queue_redraw()
	vat.set_rim(str(HudNoir.part_data(id).get("rim", "")), HudNoir.accent)
	vat.set_liquid(HudNoir.accent, 1.0 if picked else (0.2 if mode == BaseButton.DRAW_DISABLED else (0.5 if mode == BaseButton.DRAW_HOVER else 0.32)))
	vat.ready_glow = picked


func _noir_skin(b: Button, part: String) -> void:
	## A HUD button in its Neon Noir part's states: <part>, _hover, _picked / _pressed, _disabled (HudNoir.box: the cut sprite
	## when imported, else the placeholder).
	var on := part + ("_picked" if HudNoir.PRESETS.has(part + "_picked") else "_pressed")
	var c := Vector4(4, 4, 4, 4) * ui_scale
	b.add_theme_stylebox_override("normal", HudNoir.box(part, Color(0, 0, 0, 0), c))
	b.add_theme_stylebox_override("hover", HudNoir.box(part + "_hover", Color(0, 0, 0, 0), c))
	b.add_theme_stylebox_override("pressed", HudNoir.box(on, Color(0, 0, 0, 0), c))
	b.add_theme_stylebox_override("hover_pressed", HudNoir.box(on, Color(0, 0, 0, 0), c))
	b.add_theme_stylebox_override("disabled", HudNoir.box(part + "_disabled", Color(0, 0, 0, 0), c))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, HudNoir.INK)
	b.add_theme_color_override("font_pressed_color", HudNoir.on_accent())
	b.add_theme_color_override("font_hover_pressed_color", HudNoir.on_accent())
	b.add_theme_color_override("font_disabled_color", HudNoir.MUTED)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))


func _fit_status() -> void:
	## Alpha 24: the status line's pill is as wide as its words, centred under the top bar; an empty line shows nothing (the
	## label itself stays visible: the tutorial's reveal owns that).
	var empty := status_label.text == ""
	status_label.self_modulate.a = 0.0 if empty else 1.0
	if _status_secs.get_meta("text", "") != status_label.text:
		_status_secs.set_meta("text", status_label.text)
		_status_secs.size = status_label.size
		_status_secs.queue_redraw()
	if empty:
		return
	var vp := root.get_viewport_rect().size
	var w := status_label.get_combined_minimum_size().x
	if absf(status_label.size.x - w) > 0.5:
		status_label.size.x = w
		status_label.position.x = (vp.x - w) / 2.0


func _draw_status_secs() -> void:
	## Neon Noir: the status line's seconds ("9 s", "12 s") in amber over the words.
	var t := status_label.text
	var m := _secs_re.search(t)
	if m == null:
		return
	var font := status_label.get_theme_font("font")
	var fs := status_label.get_theme_font_size("font_size")
	var sb := status_label.get_theme_stylebox("normal")
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var inner := status_label.size.x - sb.content_margin_left - sb.content_margin_right
	var x0 := sb.content_margin_left + (inner - tw) / 2.0 + font.get_string_size(t.substr(0, m.get_start()), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := font.get_height(fs)
	var y0 := (status_label.size.y - h) / 2.0
	# 0.23.23 (Daniele: "the orange box for the time in the last stand warning looks weird"): no capsule any more - the
	# seconds are simply amber over the line's own glyphs
	var at := Vector2(x0, y0 + font.get_ascent(fs))
	var os := status_label.get_theme_constant("outline_size")
	if os > 0:
		_status_secs.draw_string_outline(font, at, m.get_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, os, status_label.get_theme_color("font_outline_color"))
	_status_secs.draw_string(font, at, m.get_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudNoir.AMBER.lightened(0.35))


func _draw_music_note(c: Control) -> void:
	## MUSIC (0.22.x): the note - Alpha 24: the D music / music_off icons, dimmed when OFF.
	var on := Music.music_on()
	var ic := UiTheme.icon("music" if on else "music_off")
	if ic != null:
		var side := c.size.y * 0.46
		c.draw_texture_rect(ic, Rect2((c.size - Vector2(side, side)) / 2.0, Vector2(side, side)), false, Color(HudSkin.INK, 1.0 if on else 0.55))
		return
	var q: float = c.size.y
	var col := Color.WHITE if on else Color(1, 1, 1, 0.4)
	var o := Vector2(q * 0.36, q * 0.66)
	var r := q * 0.1
	c.draw_circle(o, r, col)
	var stem_top := o + Vector2(r * 0.92, -q * 0.36)
	c.draw_line(o + Vector2(r * 0.92, 0), stem_top, col, q * 0.06)
	c.draw_line(stem_top, stem_top + Vector2(q * 0.18, q * 0.1), col, q * 0.06)
	if not on:
		c.draw_line(Vector2(q * 0.16, q * 0.86), Vector2(q * 0.84, q * 0.14), col, q * 0.08)


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
	catchup_tag.size = catchup_tag.get_combined_minimum_size()   # under the status line, at your chips' end of the bar
	catchup_tag.position = Vector2(maxf(top_panel.position.x, m.x), status_label.position.y + status_label.size.y + 2)
	pause_button.size = pause_button.custom_minimum_size
	pause_button.position = Vector2(vp.x - m.z - pause_button.size.x, m.y)
	music_button.size = music_button.custom_minimum_size
	music_button.position = Vector2(pause_button.position.x - 8.0 * ui_scale - music_button.size.x, pause_button.position.y)
	for extra in [debug_button, chat_button]:          # Alpha 24: the top-right row, left of MUSIC (never both: offline / online)
		if extra:
			extra.size = extra.custom_minimum_size
			extra.position = Vector2(music_button.position.x - 8.0 * ui_scale - extra.size.x, pause_button.position.y)
	side_panel.size = side_panel.get_combined_minimum_size()
	var side_y := (vp.y - side_panel.size.y) / 2.0
	var top_bottom := top_panel.position.y + top_panel.size.y + 34.0   # below the top bar and status line
	side_y = maxf(side_y, top_bottom)
	side_panel.position = Vector2(m.x, side_y)          # send controls on the LEFT, like Alpha 11 (Daniele)
	map_title.position = Vector2(m.x + 8, vp.y - m.w - 30 * ui_scale)
	hint.size = Vector2(vp.x * 0.5, 20)
	hint.position = Vector2(vp.x * 0.5 - hint.size.x / 2.0, vp.y - m.w - 18)
	# Alpha 24 (Hub Roadmap m05, "send on the left thumb, skills stacked on the right"): the skills stand in a column on the
	# right edge under PAUSE, centred on the screen's height where there is room (the right thumb's reach)
	# Neon Noir: the column sits in its housing (SkillDock._draw, housing_margin: its rim round the slots, its drips below)
	dock.size = dock.get_combined_minimum_size()
	var hm := dock.housing_margin()
	var dock_top := pause_button.position.y + pause_button.size.y + 8.0 * ui_scale + hm.y
	var dock_bottom := vp.y - m.w - hm.w
	var dock_y := clampf((vp.y - dock.size.y) / 2.0 + 10.0 * ui_scale, dock_top, maxf(dock_top, dock_bottom - dock.size.y))
	dock.position = Vector2(vp.x - m.z - hm.z - dock.size.x, dock_y)
	dock._place_hint()
	version_label.size = version_label.get_combined_minimum_size()
	version_label.position = Vector2(vp.x - m.z - version_label.size.x, vp.y - m.w - version_label.size.y)
	if dock.visible:                                   # Alpha 24: beside the skill column's foot, not under its drips
		version_label.position.x = dock.position.x - hm.x - 10.0 * ui_scale - version_label.size.x
	# HUD pass: the old stack's top-left corner stays as a mark only (a mission's strip pushes it down; note_line
	# starts under whichever is lower)
	notices.size = Vector2.ZERO
	notices.position = Vector2(m.x + side_panel_width() + 14.0 * ui_scale, top_panel.position.y + top_panel.size.y + 8.0 * ui_scale)
	banner.size = banner.get_combined_minimum_size()
	banner.position = Vector2((vp.x - banner.size.x) / 2.0, vp.y * 0.26)
	if debug_button:
		_debug_vp = vp                                 # demo-world merge: the button sits in the top-right row (Alpha 24)
		_size_debug_panel()
	_place_debug_tag()
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


func right_used() -> float:
	## The right edge the map keeps clear of (main._fit_nodes): PAUSE's column, and the skill column when it shows.
	var w := pause_button.size.x if pause_button else 0.0
	if dock and dock.visible:
		var hm := dock.housing_margin()
		w = maxf(w, dock.size.x + hm.x + hm.z)
	return margins.z + w + 12.0


func top_used() -> float:
	return margins.y + (top_panel.size.y if top_panel else 0.0) + 34.0


func bottom_used() -> float:
	# the map title and hint line (badges are fitted by the camera); Alpha 24: the skill dock is a column on the right now
	# (right_used), no longer a bar across the bottom
	return margins.w + 30.0 * ui_scale


func pointer_over_ui(p: Vector2) -> bool:
	for c in [top_panel, pause_button, music_button, side_panel, dock, debug_button, chat_button, monster_icon, spectate_button]:
		if c and c.visible and c.get_global_rect().has_point(p):
			return true
	if dock and dock.visible:                         # Neon Noir: the skill column's housing round it
		var hm := dock.housing_margin()
		var dr := dock.get_global_rect()
		if Rect2(dr.position - Vector2(hm.x, hm.y), dr.size + Vector2(hm.x + hm.z, hm.y + hm.w)).has_point(p):
			return true
	if debug_panel and debug_panel.visible and debug_panel.get_global_rect().has_point(p):
		return true
	for r in extra_ui_rects:                          # TUTORIAL: the coach card / completion screen
		if (r as Rect2).has_point(p):
			return true
	if is_instance_valid(inspector):
		for a in inspector_actions:
			if (a["button"] as ActionWedge).hit_global(p):     # 0.23.x: a slice of the hex pie, not its square
				return true
		if inspector.has_meta("close") and (inspector.get_meta("close") as Control).get_global_rect().has_point(p):
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
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	if main.online:
		_chat_poll -= dt
		if _chat_poll <= 0.0:
			_chat_poll = 0.5
			var n := Net.chat_unread()
			_chat_dot.visible = n > 0                      # Alpha 24: the chat icon button's red dot (B12) with the count
			(_chat_dot.get_child(0) as Label).text = str(mini(n, 99))
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
			(c["panel"] as Control).modulate = Color(1, 1, 1, 0.55) if out else Color.WHITE
			if out and str(c["box"]) != "score_pill_out":          # Neon Noir: an out seat's pill sinks (grey rim, no glow)
				c["box"] = "score_pill_out"
				(c["panel"] as Control).add_theme_stylebox_override("panel", _score_box(seat, "score_pill_out"))
	if not shows("status_line"):
		status_label.text = ""
	elif sim.very_last_stand_active:
		# 0.23.23 (Daniele: "last stand message is too long"): the line says what drops when, nothing more
		status_label.text = ("VERY LAST STAND · DROP EVERY %d s" % int(round(sim.very_last_stand_gap))
				if sim.very_last_stand_gap > 0.0 else "VERY LAST STAND · CONQUEST DECIDES")
	elif sim.last_stand_active:
		var next := ""
		var pending: int = sim.last_stand_waves.size() if sim.v3 else sim.last_stand_order.size()
		if sim.v3 and not sim.last_stand_warn.is_empty():
			next = "NEXT DROP %d s · %d LEFT" % [int(ceil(sim.last_stand_warn_t)), sim.last_stand_queue.size()]
		elif sim.last_stand_warn_node >= 0:
			next = "NEXT DROP %d s" % int(ceil(sim.last_stand_warn_t))
		elif sim.last_stand_next < pending:
			next = "NEXT DROP %d s" % int(ceil(maxf(sim._next_wave_at - sim.time, 0.0)))
		else:
			next = "CONQUEST DECIDES"
		# the method and how it falls only while the announcement pulses (HUD_LS_PULSE s); then just the next drop
		status_label.text = ("LAST STAND · %s · %s" % [sim.last_stand_method.to_upper(), _ls_how]) if _ls_pulse > 0.0 and _ls_how != "" 				else "LAST STAND · %s" % next
	elif Rules.last_stand and not sim.over and sim.time > Rules.LAST_STAND_TIME - 15.0 and sim.time < Rules.LAST_STAND_TIME and not (sim.v3 and (sim._map_last_stand.get("methods", []) as Array).is_empty()):
		# mirrors sim._step_last_stand: no countdown when the Last Stand is off, over, or the map has none
		status_label.text = "LAST STAND in %d s" % int(ceil(Rules.LAST_STAND_TIME - sim.time))
	else:
		status_label.text = ""
	_fit_status()
	_sync_catchup(dt)
	var source: int = main.drag_from if main.drag_from >= 0 else main.selected
	if source >= 0 and sim.nodes[source]["owner"] == human:
		count_label.text = "%d / %d" % [Rules.shown(floorf(sim.nodes[source]["units"] * main.fraction)), Rules.shown(sim.nodes[source]["units"])]
	else:
		count_label.text = "DRAG A VAT"
	if _badges(cam):
		badge_layer.refresh()                             # perf pass (audit B4): only when a badge changed
	overlay.sync(dt)
	_sync_monster_icon(cam, 0.0 if main.paused else dt)
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
	PerfProfile.lap("hud", _pt)


func _font_color(l: Control, c: Color) -> void:
	## add_theme_color_override("font_color", c) only when it changes (perf pass, audit B3: every override is a
	## THEME_CHANGED - the label re-shaped - and these ran for every badge on every frame).
	if (l.get_meta("font_color") if l.has_meta("font_color") else null) != c:   # (4.6: a null default still errors)
		l.set_meta("font_color", c)
		l.add_theme_color_override("font_color", c)


func _badges(cam: Camera3D) -> bool:
	## Lays out and places every node badge; true when anything BadgeLayer draws changed (it redraws only then).
	var order_shown := sim.last_stand_active
	for n in sim.nodes:
		var b: Dictionary = badges[n["id"]]
		var panel: Control = b["panel"]
		if sim.collapsed.get(n["id"], false) or n.get("node_kind", "") == "junction":   # JUNCTION: no badge
			panel.visible = false
			continue
		# ui-neon (Daniele 2026-11-02, "unit count HUD disappearing"): a warned node keeps its badge - the count stays readable
		# all through the Last Stand; the neon alarm sign (HudOverlay._draw_danger_symbols) sits beside it, clear of it.
		# (0.19.0 hid the badge here, when the sign replaced a round badge; with a whole ring warned at once that hid 6 counts.)
		panel.visible = true
		var owner: String = n["owner"]
		if b["owner"] != owner:
			b["owner"] = owner
			var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			panel.add_theme_stylebox_override("panel", badge_style(col))
			_font_color(b["label"] as Label, HudSkin.ink(col) if owner != "" else HudSkin.neutral_ink())
		var label: Label = b["label"]
		var sub: Label = b["sub"]
		var classic := not Rules.bridge_combat
		var masked := not (owner == "" or sim.allied(owner, human) or (classic and not Rules.hide_enemy_counts and shows("rival_counts")))   # Brawl = Alpha 11: every count, unless hidden (TUTORIAL: from L3)
		# POWERS (0.22.2): a rival's Fog of War over this node - "?" for its count, no owner emblem, no tags or build bar
		# (your own side's nodes stay readable to you; Sim.node_hidden is true only outside the caster's side)
		var fogged: bool = sim.node_hidden(n["id"], human) and (owner == "" or not sim.allied(owner, human))
		if fogged:
			masked = false
		label.visible = not masked
		var inner := _badge_px.x - 2.0 * BADGE_PAD * ui_scale
		var has_allies := sim.allied_units(n) > 0.0001   # GAME-RULES sec11: team members see total + own
		if fogged:
			b["count_w"] = _fit_text(label, "?", BADGE_COUNT_FONT, inner, b["count_w"])
		elif not masked:
			# POWERS: a rival's count as a rival should see it - a Ghost Line's source drops as a real send would
			var shown_units: float = sim.garrison_total(n) if has_allies else sim.visible_units(n, human)
			b["count_w"] = _fit_text(label, str(Rules.shown(shown_units)), BADGE_COUNT_FONT, inner, b["count_w"])
		# no numbers on enemy nodes: the owner's emblem in the owner's colour stands in the count's place
		# (Daniele: "don't use A B and C but use emblems in the color of the owner")
		var emb: TextureRect = b["emblem"]
		var show_emb := owner != "" and (classic or masked) and not fogged
		if show_emb and emb.get_meta("f", "") != sim.factions.get(owner, ""):
			emb.set_meta("f", sim.factions.get(owner, ""))
			emb.texture = emblem_texture(str(sim.factions.get(owner, "null")))
		if show_emb and emb.get_meta("seat", "") != owner:
			emb.set_meta("seat", owner)
			tint_emblem(emb, Rules.seat_color(owner))
		sub.visible = (not classic or n["build_kind"] != "" or sim.last_stand_active) and not fogged   # (POWERS: fog)
		# Alpha 19 (Daniele: "some text is too long, like the word FINAL isn't necessary"): two compact
		# tags at most - what the node is (relay glyph + state, CN3 cannon, FRG forge, T2 tier) and the
		# one clock that matters most: the falling countdown (a down triangle), the relay's !n switch
		# warning, the build's seconds (over its bar), your relay's ns cooldown, else the Last Stand
		# drop ring (R2 / #2). The node that never falls shows nothing extra: the banner says it.
		var what := ""
		if n["relay"] != "":
			var st := sim.relay_state_key(n, n["relay_index"])
			if Rules.is_proto(n["relay"]):                # RELAYS 3.0: OPEN 3 / A>B / UP / EXIT 2 / AIM 7 / ARMED 5
				st = sim.proto_tag(n["id"])
			what = Rules.RELAY_GLYPH[n["relay"]] + (("OUT" if st == "out" else "IN" if st == "retract" else st.to_upper()) if shows("relay") else "")
			if n["relay"] == "launcher":                  # LAUNCHER TURRET: its tier first (➶T2 LOAD 40/100)
				what = Rules.RELAY_GLYPH["launcher"] + "T%d " % int(n["tier"]) + (st.to_upper() if shows("relay") else "")
		elif n["structure"] == "machinegoon":
			what = "GAT%d" % n["tier"]                   # GOOGATLING (was MGN, the Machinegoon)
		elif Sim.vat_paused(n):                             # VAT COLUMN: the blueprint fills, the vat makes nothing
			what = "PAUSED"
		else:
			what = "T%d" % n["tier"]
		# 0.20.13 (Daniele's 2v2 co-op playtest: "i sent troops to her node and except the count going up
		# i couldn't see any other indicator"): your own share on an ally's node stands out in your own
		# colour, not the sub-label's default light blue - reset every frame, or a stale override would
		# bleed into a later node that has none.
		var sub_col := HudSkin.sub_ink()
		if has_allies and not masked:                       # GAME-RULES sec11: the total is shown above -
			if owner == human:                               # this names the ally share / your own share of it
				what += "+A%d" % Rules.shown(sim.allied_units(n))
			else:
				var mine := sim.allied_units(n, human)
				if mine > 0.0001:
					what += " +%d" % Rules.shown(mine)
					sub_col = HudSkin.ink(Rules.seat_color(human))
		_font_color(sub, sub_col)
		var clock := ""
		var worst := ""                                     # the clock's widest form (see below)
		if sim.is_warned(n["id"]) and not shows("danger"):   # ui-neon: the alarm sign shows the seconds (no second copy here) -
			clock = "▼%d" % int(ceil(sim.drop_in(n["id"]) if sim.v3 else sim.last_stand_warn_t))   # so a warned relay keeps its !n
			worst = "▼88"
		elif n["relay"] != "" and n["relay_phase"] == "warning":
			clock = "!%d" % int(ceil(n["relay_t"]))
			worst = "!8"
		elif Sim.vat_paused(n):                             # VAT COLUMN: "PAUSED 62%" over the build bar
			clock = "%d%%" % int(floor(100.0 * Sim.build_progress(n)))
			worst = "88%"
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
		build_bar.visible = n["build_kind"] != "" and not fogged
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
	var changed := false
	for n in sim.nodes:
		var b: Dictionary = badges[n["id"]]
		var panel: Control = b["panel"]
		if panel.visible and _badge_screen.has(n["id"]):
			panel.position = ((_badge_screen[n["id"]] as Vector2) - _badge_px / 2.0).round()
		# what BadgeLayer reads of this badge (its box, texts, colours, emblem, bar): redraw only if it changed
		var sig := [panel.visible]
		if panel.visible:
			var bar: ProgressBar = b["build"]
			var emb: TextureRect = b["emblem"]
			var label: Label = b["label"]
			var sub: Label = b["sub"]
			sig.append_array([panel.position, panel.size, b["owner"], b["look"], label.visible, label.text, label.position,
					label.size, label.get_theme_font_size("font_size"), label.get_meta("font_color") if label.has_meta("font_color") else null, sub.visible, sub.text,
					sub.position, sub.size, sub.get_theme_font_size("font_size"), sub.get_meta("font_color") if sub.has_meta("font_color") else null, emb.visible,
					emb.texture, emb.position, emb.size, emb.get_meta("seat", ""), bar.visible, bar.position, bar.size,
					bar.value if bar.visible else 0.0,
					# ui-node: the tier chip and the armour shields BadgeLayer draws round the badge (shields step 0.01 = 1 s)
					n["tier"], n["structure"], n["relay"], int(round(float(n["armour"]) * 100.0)), float(n["armour_cap"])])
		if sig != b.get("drawn", []):
			b["drawn"] = sig
			changed = true
	return changed


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
	var top_y := (16.5 if row2 else 22.0) * s                # centre of the count row
	var low_y := 33.0 * s                                    # centre of the sub line
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
## 0.23.x radial redesign (Daniele: "the radial menu is messy ... doesn't account for screen position ...
## more beautiful, more useful, easier to understand"; then his reference - a pie of wedges round a centre
## × - "only on the right side and in the style of our game", "make the radial hexagonal"): a half-hexagon
## pie on the node's right, one slice per action (ActionWedge: glyph, name, price), a hex × hub on the node
## itself (InspectorHub), the info card on the other side. The ring always sits on the node; every frame
## _layout_inspector_wheel (from _refresh_inspector) turns the pie away from any edge or panel it would cross
## (flipping it to the left only when the right has no room) and keeps the card inside _inspector_bounds.
const INSPECTOR_RING_R := 76.0                    # the node's own hex ring (apothem), and the pie's inner edge
const INSPECTOR_PIE_W := 112.0                    # the pie's depth, ring to outer edge (x ui_scale; phones +16)
const INSPECTOR_CARD_W := 196.0                   # ui-node: the compact card (Daniele 2026-11-04) - was 280 with 4-8 lines


func inspect(id: int, cam: Camera3D) -> void:
	close_inspector()
	if id < 0 or sim.collapsed.get(id, false):
		return
	inspector_id = id
	_debug_last_node = id                             # PROTO DEBUG: the +100 target
	if _debug_proto and debug_panel.visible:
		_debug_proto_refresh()
	var n: Dictionary = sim.nodes[id]
	var col := NodeNoir.mine_or_seat(str(n["owner"]), human)   # ui-node: your accent on yours, the owner's seat colour else
	inspector_col = col
	inspector = Control.new()
	inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inspector)
	_inspector_opened_ms = Time.get_ticks_msec()
	_inspector_guides = Control.new()                 # drawn first: the node's hex ring and the pie's dark backing
	_inspector_guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector_guides.draw.connect(func(): _draw_inspector_guides(col))
	inspector.add_child(_inspector_guides)
	var hub := InspectorHub.new()                     # the pie's centre: × on the node (was a loose X chip)
	hub.accent = col
	hub.ui_scale = ui_scale
	hub.custom_minimum_size = Vector2.ONE * (60.0 if not mobile else 78.0) * ui_scale
	hub.size = hub.custom_minimum_size
	hub.position = -hub.size / 2.0
	hub.pressed.connect(func(): close_inspector.call_deferred())
	inspector.add_child(hub)
	inspector.set_meta("close", hub)
	# ui-node (Daniele 2026-11-04, "compact card"): the node's card in the HUD's glass - [emblem] FACTION · STRUCTURE [T2], the
	# units bar (units / cap in lit goo), the armour shields (vats: one per 0.1 of the tier's armour, filling as it regains),
	# one status line, the build bar while building. The army stats line (garrison / attack / speed %) left the card.
	var info_bg := PanelContainer.new()
	info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	info_bg.add_theme_stylebox_override("panel", HudNoir.box("node_card", col, Vector4(12, 8, 12, 9) * ui_scale))
	inspector.add_child(info_bg)
	inspector.set_meta("card", info_bg)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", int(5 * ui_scale))
	info_box.custom_minimum_size = Vector2(INSPECTOR_CARD_W, 0) * ui_scale
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_bg.add_child(info_box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", int(5 * ui_scale))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(head)
	inspector_emblem = seat_emblem("", Vector2(20, 20))
	head.add_child(inspector_emblem)
	inspector_who = text_label("", 16, Color("c8e6ee"))
	head.add_child(inspector_who)
	inspector_first = text_label("", 16, HudNoir.INK)
	inspector_first.add_theme_font_size_override("font_size", card_px(16))
	inspector_who.add_theme_font_size_override("font_size", card_px(16))
	head.add_child(inspector_first)
	inspector_tier = Control.new()
	inspector_tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector_tier.custom_minimum_size = Vector2(30, 20) * ui_scale
	inspector_tier.draw.connect(func():
		if inspector_id < 0:
			return
		var tn: Dictionary = sim.nodes[inspector_id]
		NodeNoir.tier_chip(inspector_tier, inspector_tier.size / 2.0, maxf(18.0 * ui_scale, card_px(12) / 0.72), int(tn["tier"]), inspector_col, UI_FONT, ui_scale,
				"M%d" % tn["tier"] if tn["structure"] == "machinegoon" else ""))
	head.add_child(inspector_tier)
	inspector_units = Control.new()
	inspector_units.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector_units.custom_minimum_size = Vector2(0, maxf(20.0 * ui_scale, card_px(14) + 6.0))
	inspector_units.draw.connect(_draw_card_units)
	info_box.add_child(inspector_units)
	inspector_shields = Control.new()
	inspector_shields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector_shields.custom_minimum_size = Vector2(0, maxf(22.0 * ui_scale, card_px(13) + 6.0))
	inspector_shields.draw.connect(_draw_card_shields)
	info_box.add_child(inspector_shields)
	inspector_label = text_label("", 15, Color("c8e6ee"))
	inspector_label.add_theme_font_size_override("font_size", card_px(15))
	inspector_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(inspector_label)
	inspector_progress = ProgressBar.new()
	inspector_progress.custom_minimum_size = Vector2(0, 8) * ui_scale
	inspector_progress.show_percentage = false
	inspector_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(NodeNoir.GLASS_LOW, 0.9)
	track.set_corner_radius_all(int(4 * ui_scale))
	var goo := StyleBoxFlat.new()
	goo.bg_color = Color(col, 0.9)
	goo.set_corner_radius_all(int(4 * ui_scale))
	inspector_progress.add_theme_stylebox_override("background", track)
	inspector_progress.add_theme_stylebox_override("fill", goo)
	info_box.add_child(inspector_progress)
	if n["owner"] == human:
		_inspector_actions(n)
	_refresh_inspector(cam)


const STRUCT_LABEL := {"vat": "VAT", "machinegoon": "GOOGATLING", "laser": "LASER TOWER", "forge": "FORGE", "monster_hub": "MONSTER HUB"}
const BUILD_LABEL := {"machinegoon": "GOOGAT", "vat": "VAT", "laser": "LASER", "forge": "FORGE", "monster_hub": "MONSTER HUB"}
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


class ActionWedge:
	## 0.23.x (Daniele's reference: a pie of wedges round a centre ×, "only on the right side and in the style
	## of our game"): one action as a slice of the half-ring beside the node - dark glass, the accent on its
	## outer rim, a line glyph, its name and price. The control is the pie's whole bounding square (its centre
	## is the node); _has_point keeps taps to this slice alone, so the slices overlap as controls and each still
	## takes only its own. Hud._layout_inspector_wheel sets a0 / a1 / radii / grow every frame.
	extends Button
	var title := ""
	var cost := ""
	var kind := ""              # UPGRADE / MACHINEGOON / VAT / SWITCH / LASER / FORGE / MONSTER HUB / LAUNCH / EJECT
	var glyph := ""             # SWITCH: the relay's own symbol (Rules.RELAY_GLYPH), in the symbol font
	var accent := Color.WHITE
	var ui_scale := 1.0
	var font: Font
	var symbol_font: Font
	var a0 := 0.0               # the slice, radians (screen space: 0 = right, + = clockwise / down)
	var a1 := 0.0
	var r_in := 80.0            # apothems of the inner and outer hexagon (Daniele: "make the radial hexagonal")
	var r_out := 200.0
	var floor_px := 0           # GMN-1: a phone's 13 pt in px (the director's slice words); 0 on a desktop
	const ROUND := true         # GMN-1: round ring (hex_r returns the radius); false = the 0.23.x hexagon pie
	var hex_base := 0.0         # the direction of the flat edge the pie opens toward (its middle edge)
	var grow := 1.0             # deal-out from the ring, 0..1
	var type_scale := 1.0       # phones: 1.15 (the slice's name / price / glyph)
	var lift := 0.0             # hover / held: the slice slides out along its own middle, 0..1
	var afford := 1.0           # ui-node: your units / its price, 0..1 - 1 = the slice is lit (no goo fill since mockup 3)
	var why := ""               # ui-node: a greyed slice's short reason (COOLDOWN, UNDER ATTACK ...), shown instead of the price
	var _held := false
	var _ci: CanvasItem = self   # where _text / _icon draw (the words child)
	var _words: Control

	func _init() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, empty)
		_words = Control.new()
		_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_words.set_anchors_preset(Control.PRESET_FULL_RECT)
		_words.z_index = 1
		_words.draw.connect(_draw_words)
		add_child(_words)
		button_down.connect(func(): _held = true)
		button_up.connect(func(): _held = false)

	func centre() -> Vector2:
		return size / 2.0

	func mid() -> float:
		return (a0 + a1) / 2.0

	func outer() -> float:
		return r_in + (r_out - r_in) * grow

	func _shift() -> Vector2:
		return Vector2(cos(mid()), sin(mid())) * lift * 8.0 * ui_scale

	static func hex_r(t: float, apothem: float, base: float) -> float:
		## The distance from the centre to a hexagon (flat edge facing `base`) along direction t.
		if ROUND:                                       # GMN-1 (Daniele: no hexagons): the pie is a slice of a ROUND ring
			return apothem
		var rel := t - base
		return apothem / cos(rel - round(rel / (PI / 3.0)) * (PI / 3.0))

	func _angles() -> PackedFloat32Array:
		## Samples across the slice, with its hexagon corners exactly on them (no clipped corners).
		var out := PackedFloat32Array()
		var steps := maxi(4, int(ceil((a1 - a0) / deg_to_rad(6.0))))
		for i in range(steps + 1):
			out.append(lerpf(a0, a1, float(i) / steps))
		var k := ceilf((a0 - hex_base - PI / 6.0) / (PI / 3.0))
		var v := hex_base + PI / 6.0 + k * PI / 3.0
		while v < a1:
			if v > a0:
				out.append(v)
			v += PI / 3.0
		out.sort()
		return out

	func content_point() -> Vector2:
		## Local: the middle of the slice, where its glyph / name / price sit.
		var m := mid()
		var rr := (hex_r(m, r_in, hex_base) + hex_r(m, outer(), hex_base)) / 2.0
		return centre() + _shift() + Vector2(cos(m), sin(m)) * rr

	func _has_point(pt: Vector2) -> bool:
		var d := pt - centre() - _shift()
		var t := d.angle()
		if wrapf(t - a0, 0.0, TAU) > a1 - a0:
			return false
		var r := d.length()
		return r >= hex_r(t, r_in, hex_base) and r <= hex_r(t, outer(), hex_base)

	func hit_global(p: Vector2) -> bool:
		return visible and _has_point(get_global_transform().affine_inverse() * p)

	func sector_rect() -> Rect2:
		## Global: a square round the slice's middle - the tutorial's spotlight and the coach's fingertip
		## (action_rect -> its centre) land inside the slice, not on the pie's shared centre (the close hub).
		var g: Vector2 = get_global_transform() * content_point()
		var e := (r_out - r_in) * 0.72
		return Rect2(g - Vector2(e, e) / 2.0, Vector2(e, e))

	func bbox_global() -> Rect2:
		var gt := get_global_transform()
		var r := Rect2(gt * (centre() + Vector2(cos(a0), sin(a0)) * hex_r(a0, r_in, hex_base)), Vector2.ZERO)
		for a in _angles():
			for ap in [r_in, r_out]:
				r = r.expand(gt * (centre() + Vector2(cos(a), sin(a)) * hex_r(a, ap, hex_base)))
		return r

	func _process(dt: float) -> void:
		var want := 1.0 if (is_hovered() or _held) and not disabled else 0.0
		lift = move_toward(lift, want, dt * 8.0)
		queue_redraw()

	func _edge(c: Vector2, ap: float) -> PackedVector2Array:
		## The slice's hexagon edge at apothem `ap`, a0 -> a1.
		var pts := PackedVector2Array()
		for a in _angles():
			pts.append(c + Vector2(cos(a), sin(a)) * hex_r(a, ap, hex_base))
		return pts

	func _slice(c: Vector2, ri: float, ro: float) -> PackedVector2Array:
		var pts := _edge(c, ro)
		var inner := _edge(c, ri)
		inner.reverse()
		pts.append_array(inner)
		return pts

	func _draw() -> void:
		## ui-node: a slice of smoked glass, LIT in the accent when you can do it, GREYED when not (no goo), the neon tube on its
		## outer edge, the glyph, the name, the price (in red when you can't afford it) or the reason.
		if grow <= 0.001 or a1 <= a0:
			return
		var s := ui_scale
		var c := centre() + _shift()
		var ro := outer()
		var off := disabled
		var a := accent.darkened(0.35) if off else accent
		var poly := _slice(c, r_in, ro)
		if lift > 0.01 and not HudNoir.has("node_wedge"):
			draw_polyline(_edge(c, ro + 4.0 * s), Color(a, 0.25 * lift), 8.0 * s, true)
		# Daniele 2026-11-04 (mockup 3): NO goo in the slices - a slice is LIT (affordable / free) or GREYED (not yet):
		# "easy to just have grayed or not; the filling would also cost resources especially when open and close fast".
		var lit := not off and afford >= 1.0
		var sec := sector_id()
		if sec != "":                                     # GMN-2: the director's FINISHED slice (fixed 50 / 40 deg sector, own bolts and rim):
			_sector(sec, c, lit, a)                       # OFF metal always, the LIT neon signal over it in the accent
		elif HudNoir.has("node_wedge"):                   # DROP-IN: the director's slice (lit / _fill_off), unrolled onto this one
			_mapped("node_wedge_fill_off" if not lit and HudNoir.has("node_wedge_fill_off") else "node_wedge", c, r_in, ro,
					Color.WHITE if lit or HudNoir.has("node_wedge_fill_off") else Color(0.55, 0.55, 0.6))
			_mapped_rim("node_wedge", c, r_in, ro, a if lit else Color(a, 0.35))
		else:
			NodeNoir.glass(self, poly, 0.9, Color(a, 0.25 * lift))
			if lit:                                       # lit glass: the accent glows through it, brightest at the rim
				var gp := NodeNoir.clean(poly)
				var gc := PackedColorArray()
				for q in gp:
					var u := clampf(((q - c).length() - r_in) / maxf(ro - r_in, 1.0), 0.0, 1.0)
					gc.append(Color(a.darkened(0.5).lerp(a, u), 0.16 + 0.22 * u))
				draw_polygon(gp, gc)
		if sec == "" and not HudNoir.has("node_wedge"):  # (the director's slice brings its own rim: one edge, not two - Daniele)
			var edge := poly.duplicate()
			edge.append(poly[0])
			draw_polyline(edge, Color(a, 0.3), 1.0 * s, true)
			NodeNoir.neon(self, _edge(c, ro - 1.5 * s), a, (2.0 + 1.0 * lift) * s, 0.9 if lit else 0.2)
		_words.queue_redraw()

	func _draw_words() -> void:
		## The glyph, name and price / reason, drawn on a child ABOVE every slice (z 1): the next slice's steel rail no longer
		## covers the words of a turned fan (GMN-2 sectors: "?0 UNITS").
		_ci = _words
		if grow <= 0.001 or a1 <= a0:
			return
		var s := ui_scale
		var ro := outer()
		var off := disabled
		var a := accent.darkened(0.35) if off else accent
		var lit := not off and afford >= 1.0
		var k := clampf((grow - 0.5) * 2.0, 0.0, 1.0)
		if k <= 0.0:
			return
		## Daniele 2026-11-05: radial words - the glyph upright in the slice's INNER end, the name + price to its right, turned
		## along the slice's middle ray (flipped 180 deg left of the centre so they never read upside down), centred in the rest.
		var ink := Color(HudNoir.INK, k) if lit else Color(HudNoir.MUTED, k)
		var lh := maxf(14.0 * s * type_scale, float(floor_px) * 1.1)   # GMN-1: lines spaced for the phone's 13 pt words
		var ir := maxf(12.0 * s * type_scale, float(floor_px) * 0.8)
		var m := mid()
		var u := Vector2(cos(m), sin(m))
		var c := centre() + _shift()
		var ri := hex_r(m, r_in, hex_base)
		var span := hex_r(m, ro, hex_base) - ri
		var izone := ir * 2.5
		_icon(c + u * (ri + ir * 1.3), ir, Color(a.lightened(0.2) if lit else HudNoir.MUTED, k))
		var tr := ri + izone + (span - izone) * 0.5                      # the text block's centre on the ray
		var maxw := (span - izone) * 0.94
		var room := (a1 - a0) * tr * 0.92                                  # the slice's width across the ray there
		var fs := maxi(int(round(13.0 * ui_scale * type_scale)), floor_px)
		var min_fs := maxi(7, int(round(float(floor_px) * 10.0 / 13.0)))   # radial words may shrink to 10 pt (as the plate names)
		var lines: Array = []
		var low := why if why != "" else cost
		for ln in [[str(SLICE_NAMES.get(title, title)), 13.0, ink], [low, 12.0, Color(HudNoir.ENEMY.lightened(0.25) if not lit else a.lightened(0.35), k)]]:
			lines.append_array(_wrap(str(ln[0]), maxi(min_fs, int(round(fs * 0.85))), maxw).map(func(t): return [t, ln[1], ln[2]]))   # MONSTER / HUB, FREE / 5 s
		var gap := minf(lh, room / float(lines.size()))
		var ang := m + (PI if u.x < -0.01 else 0.0)
		_ci.draw_set_transform(c + u * tr, ang)
		for i in lines.size():
			var ln: Array = lines[i]
			_text(str(ln[0]), Vector2(0, (float(i) - (lines.size() - 1) / 2.0) * gap), float(ln[1]), ln[2], maxw, min_fs)
		_ci.draw_set_transform(Vector2.ZERO)

	const SLICE_NAMES := {"MACHINEGOON": "GOON", "MONSTER HUB": "HUB"}   # Daniele 2026-11-05: short names on the slice only (the card keeps the full)

	static func sector_for(span: float) -> String:
		## GMN-2: "50" / "40" when the director's finished sector of that angle is in the game and fits a slice of `span`
		## (the phone layout: 50 deg up to 3 slices, 40 for 4-5), else "" (the unrolled node_wedge / code-drawn slice).
		for deg in [50, 40]:
			if absf(rad_to_deg(span) - deg) < 4.0 and HudNoir.has("node_slice_off_%d" % deg):   # (a slice's span is its slot less 2 x 1.4 deg seams)
				return str(deg)
		return ""

	func sector_id() -> String:
		return sector_for(a1 - a0)

	func _sector(deg: String, c: Vector2, lit: bool, a: Color) -> void:
		## The sector sprites face +x with the ring centre outside their canvas (part socket = centre in body px, inner / outer
		## radius 147 / 357 px): turned to the slice's middle, scaled so 357 px = this slice's outer edge, faded in with the deal-out.
		var off: Dictionary = HudNoir.part_data("node_slice_off_" + deg)
		var t := HudNoir.texture(str(off.get("file", "")))
		if t == null:
			return
		var body: Array = off["body"]
		var sock: Array = off["socket"] if off.get("socket") != null else [-133.0, 151.0]
		var origin := -Vector2(float(body[0]) + float(sock[0]), float(body[1]) + float(sock[1]))   # canvas (0,0) from the centre
		var k := outer() / 357.0
		draw_set_transform(c, mid(), Vector2(k, k))
		draw_texture(t, origin, Color(1, 1, 1, clampf(grow * 1.5, 0.0, 1.0)))
		if lit:
			var lt := HudNoir.texture(str(HudNoir.part_data("node_slice_lit_" + deg).get("file", "")))
			if lt != null:
				draw_texture(lt, origin, Color(a.lightened(0.15 * lift), clampf(grow * 1.5, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO)

	func _uv_poly(c: Vector2, ri: float, ro2: float, full_ro: float) -> Array:
		## The slice ri..ro2 with polar UVs into an unrolled-slice texture: u across a0 -> a1, v 0 at full_ro (its top = the
		## outer rim) to 1 at r_in.
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var ang := _angles()
		for t in ang:
			pts.append(c + Vector2(cos(t), sin(t)) * hex_r(t, ro2, hex_base))
			uvs.append(Vector2((t - a0) / (a1 - a0), 1.0 - (ro2 - r_in) / maxf(full_ro - r_in, 1.0)))
		for i in range(ang.size() - 1, -1, -1):
			var t: float = ang[i]
			pts.append(c + Vector2(cos(t), sin(t)) * hex_r(t, ri, hex_base))
			uvs.append(Vector2((t - a0) / (a1 - a0), 1.0 - (ri - r_in) / maxf(full_ro - r_in, 1.0)))
		return [pts, uvs]

	func _mapped(id: String, c: Vector2, ri: float, ro2: float, mod: Color) -> void:
		var t := HudNoir.texture(str(HudNoir.part_data(id).get("file", "")))
		if t == null:
			return
		var pu: Array = _uv_poly(c, ri, ro2, outer())
		var cols := PackedColorArray()
		cols.resize((pu[0] as PackedVector2Array).size())
		cols.fill(mod)
		draw_polygon(pu[0], cols, pu[1], t)

	func _mapped_rim(id: String, c: Vector2, ri: float, ro2: float, mod: Color) -> void:
		var t := HudNoir.texture(str(HudNoir.part_data(id).get("rim", "")))
		if t == null:
			return
		var pu: Array = _uv_poly(c, ri, ro2, ro2)
		var cols := PackedColorArray()
		cols.resize((pu[0] as PackedVector2Array).size())
		cols.fill(mod)
		draw_polygon(pu[0], cols, pu[1], t)

	func _wrap(t: String, fs: int, maxw: float) -> Array:
		## A slice line too long for maxw at fs splits once: at " · " first, else at the space nearest the middle.
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= maxw:
			return [t]
		if " · " in t:
			var i := t.find(" · ")
			return [t.substr(0, i), t.substr(i + 3)]
		var best := -1
		for i in t.length():
			if t[i] == " " and (best < 0 or absi(i - t.length() / 2) < absi(best - t.length() / 2)):
				best = i
		return [t] if best < 0 else [t.substr(0, best), t.substr(best + 1)]

	func _text(t: String, at: Vector2, px: float, col: Color, maxw: float, min_fs := -1) -> void:
		var fs := maxi(int(round(px * ui_scale * type_scale)), floor_px)
		while fs > (min_fs if min_fs > 0 else maxi(7, floor_px - 1)) and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
			fs -= 1
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_ci.draw_string(font, Vector2(at.x - w / 2.0, at.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _icon(p: Vector2, r: float, col: Color) -> void:
		## Line glyphs in the kit's manner: one stroke weight, the accent, no fills except where a shape needs mass.
		var w := 2.2 * ui_scale
		match kind:
			"UPGRADE":
				for dy in [-0.45, 0.2]:
					_ci.draw_polyline(PackedVector2Array([p + Vector2(-0.75, dy + 0.4) * r, p + Vector2(0, dy - 0.3) * r,
							p + Vector2(0.75, dy + 0.4) * r]), col, w, true)
			"MACHINEGOON":
				_ci.draw_arc(p, r * 0.62, 0.0, TAU, 24, col, w, true)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					_ci.draw_line(p + d * r * 0.3, p + d * r * 1.0, col, w, true)
				_ci.draw_circle(p, r * 0.12, col)
			"VAT":
				var body := PackedVector2Array([p + Vector2(-0.6, -0.5) * r, p + Vector2(0.6, -0.5) * r, p + Vector2(0.6, 0.9) * r,
						p + Vector2(-0.6, 0.9) * r, p + Vector2(-0.6, -0.5) * r])
				_ci.draw_polyline(body, col, w, true)
				_ci.draw_line(p + Vector2(-0.3, -0.85) * r, p + Vector2(0.3, -0.85) * r, col, w, true)
				_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.5, 0.25) * r, p + Vector2(0.5, 0.1) * r,
						p + Vector2(0.5, 0.8) * r, p + Vector2(-0.5, 0.8) * r]), Color(col, col.a * 0.55))
			"SWITCH":
				if glyph != "" and symbol_font:
					var fs := int(round(r * 1.7))
					var gw := symbol_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					_ci.draw_string(symbol_font, p + Vector2(-gw / 2.0, (symbol_font.get_ascent(fs) - symbol_font.get_descent(fs)) / 2.0),
							glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				else:
					_ci.draw_arc(p, r * 0.7, -PI * 0.9, PI * 0.4, 20, col, w, true)
			"LASER":
				_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0.2, -1.0) * r, p + Vector2(-0.5, 0.12) * r,
						p + Vector2(-0.02, 0.12) * r, p + Vector2(-0.2, 1.0) * r, p + Vector2(0.5, -0.15) * r,
						p + Vector2(0.02, -0.15) * r]), col)
			"FORGE":
				_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.8, -0.75) * r, p + Vector2(0.35, -0.75) * r,
						p + Vector2(0.35, -0.25) * r, p + Vector2(-0.8, -0.25) * r]), col)
				_ci.draw_line(p + Vector2(-0.15, -0.25) * r, p + Vector2(0.55, 0.95) * r, col, w * 1.3, true)
			"MONSTER HUB":
				for dx in [-0.5, 0.0, 0.5]:
					_ci.draw_line(p + Vector2(dx - 0.25, -0.85) * r, p + Vector2(dx + 0.2, 0.85) * r, col, w * 1.2, true)
			"LAUNCH":
				_ci.draw_line(p + Vector2(0, 0.9) * r, p + Vector2(0, -0.75) * r, col, w, true)
				_ci.draw_polyline(PackedVector2Array([p + Vector2(-0.55, -0.2) * r, p + Vector2(0, -0.85) * r,
						p + Vector2(0.55, -0.2) * r]), col, w, true)
			"EJECT":
				_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.75, 0.15) * r, p + Vector2(0.75, 0.15) * r,
						p + Vector2(0, -0.8) * r]), col)
				_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.75, 0.42) * r, p + Vector2(0.75, 0.42) * r,
						p + Vector2(0.75, 0.72) * r, p + Vector2(-0.75, 0.72) * r]), col)
			_:
				_ci.draw_circle(p, r * 0.4, col)


class InspectorHub:
	## The pie's centre: a round × on the node itself (Daniele's reference) - tap to close. Round hit area.
	extends Button
	var accent := Color.WHITE
	var ui_scale := 1.0
	var grow := 1.0
	var hex_base := 0.0         # same orientation as the pie's hexagon

	func _init() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, empty)

	func _has_point(pt: Vector2) -> bool:
		var d := pt - size / 2.0
		var rel := d.angle() - hex_base
		return d.length() <= size.x / 2.0 * 0.866 / cos(rel - round(rel / (PI / 3.0)) * (PI / 3.0))

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var s := ui_scale
		var c := size / 2.0
		var r := size.x / 2.0 * (0.55 + 0.45 * grow)       # the hexagon's corner radius
		var hot := is_hovered() or button_pressed
		var hex := PackedVector2Array()
		for i in range(7):
			var a := hex_base + PI / 6.0 + i * PI / 3.0
			hex.append(c + Vector2(cos(a), sin(a)) * r)
		if not NodeNoir.sprite(self, "node_hub", c, Vector2(r, r) * (2.0 if ActionWedge.ROUND else 1.732), accent, hex_base):
			NodeNoir.glass(self, hex.slice(0, 6), 0.92)        # ui-node: smoked glass, a neon rim breathing in the node's colour
			NodeNoir.neon(self, hex, accent, (2.0 + (1.0 if hot else 0.0)) * s, 0.55 + 0.25 * sin(Time.get_ticks_msec() / 260.0) + (0.3 if hot else 0.0))
		var k := r * 0.3
		var ink := Color(0.92, 0.97, 0.98)
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), ink, 2.4 * s, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), ink, 2.4 * s, true)


func _inspector_actions(n: Dictionary) -> void:
	## Structures 2.1 (spec B): common - UPGRADE / MACHINEGOON (or VAT to go back); relay - LASER / FORGE /
	## MONSTER HUB (single tier) + SWITCH; special - T4 vat only, no swap; hub - LAUNCH; EJECT wherever
	## allied troops are stored. Costs and disabled reasons come straight from the Sim (can_build /
	## can_upgrade) in _refresh_inspector, so a greyed button always explains itself.
	var id: int = n["id"]
	# (TUTORIAL: each action shows once its lesson is reached - shows(); outside the tutorial, always)
	if n["relay"] != "":
		if shows("relay") and not sim.relay_fixed(id):  # RELAYS 3.0: a ferry without the hold / a fixed belt runs on its own
			var verb: String = {"launcher": "LOAD", "ferry": "HOLD"}.get(n["relay"], "SWITCH")   # round 3: the ferry HOLDS; the
			_add_action("SWITCH", "%s\n%s" % [verb, Rules.RELAY_GLYPH[n["relay"]]], 0, "switch", id)   # turret LOADS, then fires
		if n["relay"] == "launcher" and int(n["tier"]) < Rules.LAUNCHER_MAX_TIER and shows("upgrade"):   # LAUNCHER TURRET: T2 / T3
			_add_action("UPGRADE", "UPGRADE T%d" % (int(n["tier"]) + 1), sim.upgrade_cost(n), "upgrade", id)
		for kind in ["laser", "forge", "monster_hub"]:
			if kind in n["buildable"] and n["structure"] != kind and shows("relay_build"):
				_add_action(BUILD_LABEL[kind], BUILD_LABEL[kind], sim.build_cost(n, kind), "build", id, {"kind": kind})
		if n["structure"] == "monster_hub" and shows("monster"):
			_add_action("LAUNCH", "LAUNCH", Rules.MONSTER_COST, "launch_monster", id)
	elif n["structure"] == "vat":
		if n["tier"] < 4 and shows("upgrade"):
			_add_action("UPGRADE", "UPGRADE T%d" % (n["tier"] + 1), sim.upgrade_cost(n), "upgrade", id)
		if "machinegoon" in n["buildable"] and shows("machinegoon"):
			_add_action("MACHINEGOON", BUILD_LABEL["machinegoon"], sim.build_cost(n, "machinegoon"), "build", id, {"kind": "machinegoon"})
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
	var price := "FREE"
	if cost > 0:
		price = "%d UNITS" % Rules.shown(cost)
	elif method == "switch":
		price = "FREE · %d s" % int(Rules.relay_cooldown(str(sim.nodes[id]["relay"])))   # free, then its cooldown (GMN-1: "5 s COOLDOWN" overflowed the 40 deg slice)
	var b := ActionWedge.new()                            # 0.23.x: a slice of the hex pie (see ActionWedge)
	b.title = title.get_slice("\n", 0)
	b.cost = price
	b.kind = name
	if method == "switch":
		b.glyph = str(Rules.RELAY_GLYPH.get(sim.nodes[id]["relay"], ""))
	b.accent = RELAY_ACCENT if method == "switch" else HudNoir.accent   # ui-node: your faction accent (Daniele 2026-11-04)
	b.ui_scale = ui_scale
	b.font = UI_FONT
	b.symbol_font = SYMBOL_FONT
	b.type_scale = 1.15 if mobile else 1.0
	b.floor_px = int(ceil(pt(13.0))) if mobile else 0
	var act := func():
		if method == "launch_monster":                    # arm: drag from the hub, or tap a highlighted node
			main.monster_from = id
			close_inspector()
			return
		if main.node_action(method, id, args):
			close_inspector()
		else:
			_refresh_inspector(main.cam)
	b.pressed.connect(func(): act.call_deferred())
	if method == "switch":                                # relay-outcome preview while SWITCH is hovered / held
		b.mouse_entered.connect(func(): overlay.hover_relay = id)
		b.mouse_exited.connect(func():
			if overlay.hover_relay == id:
				overlay.hover_relay = -1)
		b.button_down.connect(func(): overlay.hover_relay = id)
	# The slice's angles / radii are set every frame in _layout_inspector_wheel. SWITCH stands out (Daniele,
	# 0.19.0: "add some visibility to the buttons / models of the relays"): the relay's own accent plus a
	# READY / cooldown ring round its glyph (SwitchRing, updated in _refresh_inspector, placed by the layout).
	inspector.add_child(b)
	if method == "switch":
		switch_ring = SwitchRing.new()
		switch_ring.ui_scale = ui_scale
		switch_ring.accent = RELAY_ACCENT
		b.add_child(switch_ring)
	inspector_actions.append({"button": b, "cost": cost, "method": method, "name": name, "args": args})
	action_buttons[name] = b


func action_rect(name: String) -> Rect2:
	## Stable rect getter for the tutorial's spotlight (TUTORIAL-DESIGN.md sec11): valid only while that
	## action's button is on screen (the inspector open on the right node kind). Empty otherwise.
	## 0.23.x: a slice of the hex pie - a square round the slice's own middle (ActionWedge.sector_rect), so
	## the coach's fingertip (its centre) lands on that slice, never on the pie's shared centre (the × hub).
	name = name.replace("MACHINGOON", "MACHINEGOON")   # 0.19.2 spelling fix; old name accepted for one release
	if action_buttons.has(name) and is_instance_valid(action_buttons[name]):
		return (action_buttons[name] as ActionWedge).sector_rect()
	return Rect2()


func send_button_rect(fraction: float) -> Rect2:
	## The SEND tank's band for `fraction` (1.0 / 0.75 / 0.5 / 0.25), for the tutorial's spotlight (ui-node: was a button).
	if send_tank == null or not side_panel.visible:
		return Rect2()
	return send_tank.level_rect(snappedf(fraction, 0.25))


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
		if c is Control and (c as Control).visible and (c as Control).size != Vector2.ZERO:
			# 0.23.x: a pie slice's control is the pie's whole square - its own slice is what it covers
			var g: Rect2 = (c as ActionWedge).bbox_global() if c is ActionWedge else (c as Control).get_global_rect()
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


func _sync_monster_icon(cam: Camera3D, dt: float) -> void:
	var hub := _human_hub_id()
	var ready := hub >= 0 and _monster_ready(sim.nodes[hub]) == "" and shows("monster_icon")
	monster_icon.visible = ready
	if not ready:
		return
	var n: Dictionary = sim.nodes[hub]
	var p := cam.unproject_position((n["pos"] as Vector3) + Vector3(0, 5.5, 0))
	monster_icon.position = p - monster_icon.size / 2.0
	monster_icon.accent = Rules.seat_color(human)
	monster_icon.t += dt                              # (audit A3: was 0.016 a frame - half speed at 30 fps, on while paused)
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


func _inspector_bounds() -> Rect2:
	## The open play area the radial menu may use: below the top bar, right of the SEND panel (when it
	## shows), above the dock / hint / map title, inside the safe-area margins - the pie turns to stay in it.
	var vp := root.get_viewport_rect().size
	var l := margins.x + (side_panel.size.x + 16.0 * ui_scale if side_panel.visible else 0.0)
	var t := top_used() + 8.0 * ui_scale
	var r := vp.x - margins.z - 8.0 * ui_scale
	if dock and dock.visible:                           # Alpha 24: the skill column on the right
		r = minf(r, dock.position.x - 8.0 * ui_scale)
	var bo := vp.y - bottom_used() - 8.0 * ui_scale
	return Rect2(l, t, maxf(r - l, 20.0), maxf(bo - t, 20.0))


func _settle(p: Vector2, centre_offset: Vector2, size: Vector2, bounds: Rect2) -> Vector2:
	## Where a wheel part (an action button, the close chip, the info card) actually lands: `centre_offset`
	## from the node p is the ask, clamped fully inside `bounds`; returns a position local to `inspector`
	## (which sits at p), ready to assign straight to that Control's .position.
	var top_left := p + centre_offset - size / 2.0
	top_left = Vector2(clampf(top_left.x, bounds.position.x, bounds.position.x + bounds.size.x - size.x),
			clampf(top_left.y, bounds.position.y, bounds.position.y + bounds.size.y - size.y))
	return top_left - p


static func _hex_edge(c: Vector2, base: float, a0: float, a1: float, ap: float) -> PackedVector2Array:
	## Points along a hexagon (flat edge facing `base`, apothem `ap`) from direction a0 to a1, corners included.
	var angs: Array[float] = []
	var steps := maxi(2, int(ceil((a1 - a0) / deg_to_rad(6.0))))
	for i in range(steps + 1):
		angs.append(lerpf(a0, a1, float(i) / steps))
	var v := base + PI / 6.0 + ceilf((a0 - base - PI / 6.0) / (PI / 3.0)) * PI / 3.0
	while v < a1:
		if v > a0:
			angs.append(v)
		v += PI / 3.0
	angs.sort()
	var pts := PackedVector2Array()
	for a in angs:
		pts.append(c + Vector2(cos(a), sin(a)) * ActionWedge.hex_r(a, ap, base))
	return pts


func _pie_overflow(p: Vector2, base: float, total: float, r_out: float, bounds: Rect2, rot := 0.0) -> float:
	## How far (px, summed) a half-hex pie facing `base` would cross the play area's edges.
	var over := 0.0
	for q in _hex_edge(p, base + rot, base - total / 2.0, base + total / 2.0, r_out):
		over += maxf(0.0, bounds.position.x - q.x) + maxf(0.0, q.x - bounds.end.x)
		over += maxf(0.0, bounds.position.y - q.y) + maxf(0.0, q.y - bounds.end.y)
	return over


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a / 2.0


func _layout_inspector_wheel(p: Vector2, _vp: Vector2) -> void:
	## The hex pie, the hub and the info card, placed fresh every frame (see the block comment above inspect()).
	var bounds := _inspector_bounds()
	var s := ui_scale
	var n := inspector_actions.size()
	var ring := INSPECTOR_RING_R * s
	# 4-5 actions (a relay) share half an edge each: a bigger pie there, or names and prices got cut (Daniele,
	# 2026-10-01: "for relay vat make them a bit larger as some text gets cut")
	var big := n >= 4
	var r_in := ring + (5.0 + (18.0 if big else 0.0)) * s
	var r_out := r_in + (INSPECTOR_PIE_W + (16.0 if mobile else 0.0) + (34.0 if big else 0.0)) * s
	if mobile and ActionWedge.ROUND:                  # GMN-1 layout: ring 49 -> 119 pt, 50 deg a slice (40 for 4-5)
		r_in = pt(49.0)
		r_out = pt(119.0)
	# one hexagon edge (60 deg) per action up to 3 - the half-hex; 4-5 take half an edge each (30 deg), so every
	# seam still lands on a corner or an edge's midpoint and each slice stays a clean trapezoid (45 / 36 deg
	# slices cut across the edges and came out as kites)
	var span := PI / 3.0 if n <= 3 else PI / 6.0
	if mobile and ActionWedge.ROUND:
		span = deg_to_rad(50.0 if n <= 3 else 40.0)
	var total := span * n
	# the hexagon turned so the seams land on those points: flat edge to the front for 1, 3 or 4 slices, a
	# corner for 2, 15 deg off for 5
	var rot := {2: PI / 6.0, 5: PI / 12.0}.get(n, 0.0) as float
	# Facing: the right (0) - Daniele: "only on the right side" - turned by the smallest step that keeps the
	# whole pie inside the play area; the mirror (the left, PI) only when no turn of the right one fits.
	var base := 0.0
	if n > 0:
		var best := INF
		for side in [0.0, PI]:
			for k in range(19):
				for sg in ([1.0] if k == 0 else [1.0, -1.0]):
					var b: float = side + sg * deg_to_rad(k * 5.0)
					var score: float = _pie_overflow(p, b, total, r_out, bounds, rot) * 1000.0 + k * 5.0 + (150.0 if side != 0.0 else 0.0)
					if score < best:
						best = score
						base = b
	var now := Time.get_ticks_msec() - _inspector_opened_ms
	var box := Vector2.ONE * 2.0 * (r_out * 1.16 + 14.0 * s)
	var hex_base := base + rot
	var mirrored := cos(base) < 0.0                   # the left side: keep the first action on top there too
	for i in range(n):
		var w: ActionWedge = inspector_actions[i]["button"]
		var j := (n - 1 - i) if mirrored else i
		var a0 := base - total / 2.0 + span * j
		w.a0 = a0 + deg_to_rad(1.4)                   # the dark seams between slices
		w.a1 = a0 + span - deg_to_rad(1.4)
		w.r_in = r_in
		w.r_out = r_out
		w.hex_base = hex_base
		var t := clampf((now - i * 45.0) / 230.0, 0.0, 1.0)
		w.grow = 1.0 - pow(1.0 - t, 3.0)              # dealt out from the ring, one after the other
		w.custom_minimum_size = box
		w.size = box
		w.position = -box / 2.0
		if is_instance_valid(switch_ring) and switch_ring.get_parent() == w:   # (not child 0: the words layer is)
			var u := Vector2(cos(w.mid()), sin(w.mid()))
			var ir := maxf(12.0 * s * w.type_scale, float(w.floor_px) * 0.8)
			var gp := w.centre() + w._shift() + u * (ActionWedge.hex_r(w.mid(), w.r_in, w.hex_base) + ir * 1.3)   # = _draw_words' glyph
			switch_ring.size = Vector2.ONE * ir * 2.6
			switch_ring.position = gp - switch_ring.size / 2.0
	var hub: Control = inspector.get_meta("close")
	if hub is InspectorHub:
		(hub as InspectorHub).hex_base = hex_base
		(hub as InspectorHub).grow = 1.0 - pow(1.0 - clampf(now / 160.0, 0.0, 1.0), 3.0)
	# the info card: the far side of the node from the pie, else above / below it leaning that way - whichever
	# spot overlaps the pie and the node's ring least (their real shapes, not boxes)
	var card: Control = inspector.get_meta("card")
	var isz: Vector2 = card.get_combined_minimum_size()
	var sx := -signf(cos(base)) if absf(cos(base)) > 0.05 else -1.0
	var shapes: Array = [_hex_edge(p, hex_base, hex_base - PI, hex_base + PI - 0.001, ring * 1.05)]
	if n > 0:
		var pie_poly := _hex_edge(p, hex_base, base - total / 2.0, base + total / 2.0, r_out + 4.0 * s)
		pie_poly.append(p)
		shapes.append(pie_poly)
	var rr := ring * 1.16 + 12.0 * s
	var lean := isz.x / 2.0 - ring * 0.4
	var tries := [Vector2(sx * (rr + isz.x / 2.0), 0),
			Vector2(sx * lean, -(rr + isz.y / 2.0)), Vector2(sx * lean, rr + isz.y / 2.0),
			Vector2(0, -(rr + isz.y / 2.0)), Vector2(0, rr + isz.y / 2.0),
			Vector2(-sx * (r_out * 1.16 + 12.0 * s + isz.x / 2.0), 0)]
	var best_pos := Vector2.ZERO
	var best_hit := INF
	for cc in tries:
		var lp := _settle(p, cc, isz, bounds)
		var q := p + lp
		var rect_poly := PackedVector2Array([q, q + Vector2(isz.x, 0), q + isz, q + Vector2(0, isz.y)])
		var hit := 0.0
		for sh in shapes:
			for part in Geometry2D.intersect_polygons(rect_poly, sh):
				hit += absf(_poly_area(part))
		if hit < best_hit - 1.0:
			best_hit = hit
			best_pos = lp
	card.position = best_pos
	_fan = {"base": base, "hex": hex_base, "total": total, "r_in": r_in, "r_out": r_out, "n": n,
			"e": 1.0 - pow(1.0 - clampf(now / 200.0, 0.0, 1.0), 3.0)}
	if is_instance_valid(_inspector_guides):
		_inspector_guides.queue_redraw()


func _draw_inspector_guides(col: Color) -> void:
	## The node's own hex ring (the pie's hub sits inside it) and a dark backing under the pie, so the seams
	## between slices read as clean dark lines over any background.
	if _fan.is_empty():
		return
	var s := ui_scale
	var base: float = _fan["base"]
	var hx: float = _fan["hex"]
	var e: float = _fan["e"]
	var g := _inspector_guides
	var hexp := _hex_edge(Vector2.ZERO, hx, hx - PI, hx + PI, INSPECTOR_RING_R * s)
	# ui-node: the selection hex as a neon tube (halo, tube, core) breathing in the node's colour, a faint wash inside
	g.draw_colored_polygon(hexp.slice(0, hexp.size() - 1), Color(col, 0.06 * e))
	if not NodeNoir.sprite(g, "node_select", Vector2.ZERO, Vector2.ONE * INSPECTOR_RING_R * s * 2.0, Color(col, e), hx, NodeNoir.floor_k(g)):
		NodeNoir.neon(g, hexp, col, 2.4 * s, (0.65 + 0.2 * sin(Time.get_ticks_msec() / 300.0)) * e, e)
	if int(_fan["n"]) > 0 and ActionWedge.sector_for(float(_fan["total"]) / int(_fan["n"])) == "":   # GMN-2 sectors: no container
		var total: float = _fan["total"]
		var outer := _hex_edge(Vector2.ZERO, hx, base - total / 2.0, base + total / 2.0, float(_fan["r_out"]) + 3.0 * s)
		var inner := _hex_edge(Vector2.ZERO, hx, base - total / 2.0, base + total / 2.0, float(_fan["r_in"]) - 2.0 * s)
		inner.reverse()
		outer.append_array(inner)
		g.draw_colored_polygon(outer, Color(0.0, 0.0, 0.0, 0.5 * e))



func _refresh_inspector(cam: Camera3D) -> void:
	if not is_instance_valid(inspector) or inspector_id < 0:
		return
	var n: Dictionary = sim.nodes[inspector_id]
	if sim.collapsed.get(inspector_id, false):
		close_inspector()
		return
	var vp := root.get_viewport_rect().size
	var p := cam.unproject_position(n["pos"] + Vector3(0, 2.0, 0))
	var off_margin := 90.0 * ui_scale                 # 0.23.6+: a wheel/pinch zoom can carry the inspected node
	if p.x < -off_margin or p.x > vp.x + off_margin or p.y < -off_margin or p.y > vp.y + off_margin:
		close_inspector()                             # well off the fitted view - close rather than leave the info
		return                                        # card floating disconnected with no ring, no fan, to point at
	inspector.position = p                            # 0.23.x: the ring always sits truthfully on the node itself -
	                                                   # everything around it moves instead (_layout_inspector_wheel,
	                                                   # called at the end of this function - after the info card's
	                                                   # text below, so its size is this frame's, not last frame's)
	var owner: String = n["owner"]
	# the header names the owner by emblem and faction in the owner's colour (Daniele: "don't use A B
	# and C but use emblems in the color of the owner")
	inspector_emblem.visible = owner != ""
	if owner != "" and inspector_emblem.get_meta("seat", "") != owner:
		inspector_emblem.set_meta("seat", owner)
		inspector_emblem.texture = emblem_texture(str(sim.factions.get(owner, "null")))
		tint_emblem(inspector_emblem, Rules.seat_color(owner))
	inspector_who.text = "NEUTRAL" if owner == "" else str(sim.factions.get(owner, "")).to_upper()
	_font_color(inspector_who, Color("c8e6ee") if owner == "" else inspector_col)
	# ui-node compact card: STRUCTURE [tier chip] / units bar (yours, allies', neutral) / shields (vats) / ONE status line
	inspector_first.text = "· " + _structure_word(n)
	var hidden_pop := owner != "" and not sim.allied(owner, human)
	inspector_tier.visible = (n["relay"] == "" and str(n["structure"]) in ["vat", "machinegoon", ""]) or n["relay"] == "launcher"   # the launcher has tiers (proto merge)
	inspector_units.visible = not hidden_pop
	inspector_shields.visible = owner != "" and Sim.has_vat(n) and NodeNoir.shield_count(float(n["armour_cap"])) > 0
	inspector_label.text = _status_line(n, hidden_pop)
	inspector_label.visible = inspector_label.text != ""
	inspector_tier.queue_redraw()
	inspector_units.queue_redraw()
	inspector_shields.queue_redraw()
	inspector_progress.visible = n["build_kind"] != ""
	inspector_progress.value = Sim.build_progress(n) * 100.0
	_layout_inspector_wheel(p, vp)
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
		if b is ActionWedge:                              # ui-node: the slice fills with goo as your units near its price;
			var cost_now := int(a["cost"])                # a greyed slice names its reason on a phone (no tooltips there)
			(b as ActionWedge).afford = 1.0 if cost_now <= 0 else clampf(float(n["units"]) / float(cost_now), 0.0, 1.0)
			(b as ActionWedge).why = _short_why(why)


func pt(v: float) -> float:
	## GMN-1 (the director's layout, QA/layout-*.json, measured at 812 x 375 pt): v points in viewport px - on a phone its real
	## points x hud_k (FOLDABLES), on a desktop the canvas as a HUD_DESKTOP_PT_H pt screen (ui-demo-hud-scale, UiKit.hud_px_per_pt).
	return v * UiKit.hud_px_per_pt(root.get_viewport_rect().size, mobile)


func card_px(fs: int) -> int:
	## A node-card word's font size: fs x ui_scale, never under the phone's 12.5 pt floor (PROJECT.md UI rules).
	var floor_px := 12.5 / maxf(UiKit.pt_per_px(root.get_viewport_rect().size), 0.01) if mobile else 0.0
	return maxi(int(fs * ui_scale), int(ceil(floor_px)))


func _structure_word(n: Dictionary) -> String:
	## The card's title (ui-node): what stands here; the tier sits in its own chip.
	if n["relay"] == "launcher":
		return "LAUNCHER"
	if n["relay"] != "":
		return "%s RELAY" % str(n["relay"]).to_upper() + (" + %s" % STRUCT_LABEL.get(n["structure"], str(n["structure"]).to_upper()) if n["structure"] != "" else "")
	if n["structure"] == "machinegoon":
		return "GOOGATLING"
	return STRUCT_LABEL.get(n["structure"], "VAT")


func _status_line(n: Dictionary, hidden_pop: bool) -> String:
	## The card's one status line (ui-node): the clock that matters most, else what the node does for you.
	var owner: String = n["owner"]
	if Sim.vat_paused(n):                                   # VAT COLUMN (Daniele, 2026-11-07): the blueprint fills, no production
		return "UPGRADING T%d %d%% · PAUSED · %d s" % [int(n["build_target"].get("tier", n["tier"] + 1)),
				int(floor(100.0 * Sim.build_progress(n))), int(ceil(n["build_timer"]))]
	if n["build_kind"] != "":
		return "BUILDING %s · %d s" % [str(n["build_target"].get("kind", n["build_kind"])).to_upper().replace("_", " "), int(ceil(n["build_timer"]))]
	if sim.very_last_stand_active:
		if sim.very_last_stand_gap <= 0.0:
			return "THE LAST NODE"
		return "FALLS IN %d s" % int(ceil(sim.drop_in(n["id"]))) if sim.is_warned(n["id"]) else "COULD FALL NEXT"
	if sim.last_stand_active and sim.is_warned(n["id"]):
		return "FALLS IN %d s" % int(ceil(sim.drop_in(n["id"]) if sim.v3 else sim.last_stand_warn_t))
	if n["relay"] == "launcher" and owner != "" and not hidden_pop:   # LAUNCHER TURRET (proto merge): loads / LOADING / cooldown
		var ls := launcher_line(n).to_upper()
		var lup := sim.upgrade_cost(n)
		if owner == human and lup > 0 and shows("upgrade"):
			ls += " · UPGRADE T%d: %d" % [int(n["tier"]) + 1, Rules.shown(lup)]
		return ls
	if n["relay"] != "" and shows("relay"):
		var cur := sim.relay_state_key(n, n["relay_index"]).to_upper()
		var nxt := sim.relay_state_key(n, sim.relay_next_index(n)).to_upper()
		if n["relay_phase"] == "warning":
			return "%s → %s IN %.1f s" % [cur, nxt, n["relay_t"]]
		if n["relay_phase"] == "moving":
			return "%s → %s · MOVING" % [cur, nxt]
		if n["relay_cd"] > 0.0:
			return "%s · NEXT %s · %d s" % [cur, nxt, int(ceil(n["relay_cd"]))]
		return "%s · NEXT %s · READY" % [cur, nxt]
	if hidden_pop:
		return "POPULATION HIDDEN"
	if owner == "":
		return "NEUTRAL"
	if n["structure"] == "laser" and owner == human:
		return "LASER %s" % ("FIRING" if n["cannon_burst"] > 0.0 else ("READY" if n["cannon_cd"] <= 0.0 else "RECHARGING %d s" % int(ceil(n["cannon_cd"]))))
	if n["structure"] == "monster_hub" and shows("monster"):
		var mr := _monster_ready(n)
		return "MONSTER %s" % ("READY" if mr == "" else mr.to_upper())
	if n["structure"] == "forge" and shows("forge_readout"):
		return "+%d%% ATTACK · -%d%% DAMAGE" % [roundi(Rules.forge_bonus * 100.0), roundi((1.0 - 1.0 / Rules.FORGE_DEFENCE) * 100.0)]
	if n["structure"] == "machinegoon":                      # GOOGATLING (proto merge): its ammo is its garrison
		return gat_line(n).to_upper()
	if Sim.has_vat(n):
		var up := sim.upgrade_cost(n)
		var prod := "+%.1f / s" % Rules.shown_f(sim.production(n))
		if owner == human and shows("upgrade"):
			return prod + (" · MAX TIER" if up <= 0 else " · DOUBLE-TAP: UPGRADE")
		return prod
	return ""


func _short_why(why: String) -> String:
	## A greyed slice's reason in a few words (the Sim's sentences are tooltips; phones have none).
	if why == "":
		return ""
	var w := why.to_upper()
	if "UNIT" in w or "AFFORD" in w or "ENOUGH" in w:
		return ""                                     # the price in red on the greyed slice says it
	if "COOLDOWN" in w:
		return "COOLDOWN"
	if "SWITCHING" in w or "MOVING" in w:
		return "SWITCHING"
	if "ATTACK" in w:
		return "UNDER ATTACK"
	if "BUILD" in w:
		return "BUILDING"
	if "MAX" in w:
		return "MAX TIER"
	return w.left(16)


func _draw_card_units() -> void:
	## The card's units bar: a glass track, lit goo up to units / cap in the node's colour, "29 / 60" over it.
	if inspector_id < 0 or not is_instance_valid(inspector_units):
		return
	var n: Dictionary = sim.nodes[inspector_id]
	var c := inspector_units
	var s := ui_scale
	var r := Rect2(Vector2(0, 2.0 * s), Vector2(c.size.x, c.size.y - 4.0 * s))
	var cap := maxf(float(sim.node_cap(n)), 1.0)
	var units: float = sim.garrison_total(n) if sim.allied_units(n) > 0.0001 else float(n["units"])
	var f := clampf(units / cap, 0.0, 1.0)
	var pts := NoirBox.rounded(r, r.size.y / 2.0)
	NodeNoir.glass(c, pts, 0.9)
	if f > 0.0:
		var fr := Rect2(r.position, Vector2(maxf(r.size.x * f, r.size.y), r.size.y))
		var gp := NodeNoir.clean(NoirBox.rounded(fr, r.size.y / 2.0))
		var cols := PackedColorArray()
		for q in gp:
			cols.append(Color(inspector_col.darkened(0.45).lerp(inspector_col.darkened(0.15), (q.y - r.position.y) / r.size.y), 0.9))
		c.draw_polygon(gp, cols)
	var loop := pts.duplicate()
	loop.append(pts[0])
	c.draw_polyline(loop, Color(inspector_col, 0.6), maxf(1.0, 1.2 * s), true)
	var txt := "%d / %d" % [Rules.shown(units), Rules.shown(cap)]
	var fs := card_px(14)
	var tw := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(r.get_center().x - tw / 2.0, r.get_center().y + (UI_FONT.get_ascent(fs) - UI_FONT.get_descent(fs)) / 2.0)
	c.draw_string_outline(UI_FONT, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), Color(0, 0, 0, 0.85))
	c.draw_string(UI_FONT, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudNoir.INK)


func _draw_card_shields() -> void:
	## The card's armour: the shields (one per 0.1 of the tier's armour) and, while they fill, the seconds to full.
	if inspector_id < 0 or not is_instance_valid(inspector_shields):
		return
	var n: Dictionary = sim.nodes[inspector_id]
	var c := inspector_shields
	var s := ui_scale
	var cap := float(n["armour_cap"])
	var arm := float(n["armour"])
	var h := c.size.y - 4.0 * s
	var txt := "ARMOUR x%.1f" % arm if arm >= cap - 0.0001 else "FULL IN %d s" % int(ceil(sim.armour_full_in(n)))
	var fs := card_px(13)
	var tw := UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rw := NodeNoir.shield_count(cap) * (h * 0.84 + 2.0 * s)
	var x0 := (c.size.x - rw - 6.0 * s - tw) / 2.0
	NodeNoir.shields_row(c, Vector2(x0 + rw / 2.0, c.size.y / 2.0), h, arm, cap, inspector_col, s, Time.get_ticks_msec() / 1000.0)
	c.draw_string(UI_FONT, Vector2(x0 + rw + 6.0 * s, c.size.y / 2.0 + (UI_FONT.get_ascent(fs) - UI_FONT.get_descent(fs)) / 2.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudNoir.MUTED)


func gat_line(n: Dictionary) -> String:
	## GOOGAT readout (Desk dec-googatling): its ammo IS its garrison - "ammo 24/30 · +0.5/s · fires 1.6/s" at Alpha 11
	## scale (cap = the node's own cap, + = half the same-tier vat rate); EMPTY while it trickles.
	var ammo := float(n["units"])
	var line := "ammo %d/%d · +%.1f/s · fires %.1f/s" % [Rules.shown(ammo), Rules.shown(Sim.gat_cap(n)),
			Rules.shown_f(sim.gat_rate(n)), Rules.shown_f(Sim.gat_fire_rate(n))]
	return line + (" · EMPTY" if ammo < 0.5 * Rules.SCALE else "")


func launcher_line(n: Dictionary) -> String:
	## LAUNCHER TURRET readout: "loads 50 in 2 s" idle; "LOADING 32/50 · 1.4 s" while it loads; the cooldown after a salvo.
	var cap := Rules.shown(Sim.launcher_load(n))
	if n["relay_phase"] == "moving" and n.get("misfire", "") == "":
		return "LOADING %d/%d · %.1f s" % [Rules.shown(Sim.launcher_loaded(n)), cap, maxf(0.0, float(n["relay_t"]))]
	var line := "loads %d in %d s" % [cap, int(Sim.launcher_load_s(n))]
	if float(n["relay_cd"]) > 0.0:
		line += " · ready in %d s" % int(ceil(float(n["relay_cd"])))
	return line


func _structure_line(n: Dictionary) -> String:
	if n["relay"] == "launcher":
		return "LAUNCHER T%d" % int(n["tier"])
	if n["relay"] != "":
		return "%s RELAY" % n["relay"].to_upper() + (" + %s" % STRUCT_LABEL.get(n["structure"], str(n["structure"]).to_upper()) if n["structure"] != "" else " (empty socket)")
	if n["structure"] == "machinegoon":
		return "GOOGATLING T%d" % n["tier"]
	return "VAT T%d" % n["tier"]


func close_inspector() -> void:
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = null
	inspector_id = -1
	inspector_actions.clear()
	action_buttons.clear()
	switch_ring = null
	_fan = {}
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
var _status_secs: Control               # Neon Noir: the amber capsule round the status line's seconds
var _secs_re := RegEx.create_from_string("\\d+ s\\b")
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
			{"anchor": func(): return Vector2(b.get_global_rect().position.x - 6.0 * ui_scale, b.get_global_rect().get_center().y),
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


func _sync_catchup(dt: float) -> void:
	## CATCH-UP: the tag fades in while your side's vats make +15 % (Sim.catchup_active), out when the gap closes - over
	## Rules.HUD_CALLOUT_FADE, the callouts' fade. Recounted every frame (an online guest's Sim never steps).
	var on: bool = shows("status_line") and not sim.over and not _seat_out(human) and sim.catchup_active(human)
	var a := move_toward(catchup_tag.modulate.a, 1.0 if on else 0.0, dt / Rules.HUD_CALLOUT_FADE)
	catchup_tag.modulate.a = a
	catchup_tag.visible = a > 0.0
	if catchup_tag.visible:
		_place_catchup()


func _place_catchup() -> void:
	## 0.23.23 (Daniele: "catch up seems randomly positioned"): it hung under the status line's slot, empty or not, at the bar's
	## left end. Now it sits right under YOUR score pill, left-aligned with it; when the status line is up and would meet it,
	## it drops under that line instead.
	var gap := 4.0 * ui_scale
	catchup_tag.size = catchup_tag.get_combined_minimum_size()
	var x := maxf(top_panel.position.x, margins.x)
	var y := top_panel.position.y + top_panel.size.y + gap
	var c = top_chips.get(human)
	if c != null and is_instance_valid(c["panel"]):
		x = maxf((c["panel"] as Control).global_position.x - root.global_position.x, margins.x)
	var r := Rect2(Vector2(x, y), catchup_tag.size)
	if status_label.text != "" and r.intersects(Rect2(status_label.position, status_label.size).grow(gap)):
		y = status_label.position.y + status_label.size.y + gap
	catchup_tag.position = Vector2(x, y)


func pulse_last_stand(how: String) -> void:
	## The Last Stand's announcement: its own status line pulses for HUD_LS_PULSE s and says how the method falls.
	_ls_pulse = Rules.HUD_LS_PULSE
	_ls_how = how


func _under_top() -> float:
	## The first free y under the top bar, the status line and a mission's strip.
	var y := top_panel.position.y + top_panel.size.y if top_panel.visible else margins.y
	if status_label.text != "":
		y = status_label.position.y + status_label.size.y
	if catchup_tag.visible:
		y = maxf(y, catchup_tag.position.y + catchup_tag.size.y)
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
	for c in [catchup_tag, pause_button, music_button, side_panel, dock, dock.hint_panel if dock else null, debug_button, chat_button, spectate_button, monster_icon, map_title]:
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
	if not main.online:                                # UX pass (board 07): PLAY AGAIN = the same setup, one tap
		primary = ["PLAY AGAIN  →", main.restart]
		quiet = [["HOME", main.to_menu], ["RANDOM MAP", main.rematch_random], ["CHANGE SETUP", func(): main.to_menu("setup")]]
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
			# 0.22.4 playtest (Daniele's cousins): 6 rows (4 actions + 2 toggle rows) at the default row_gap
			# overflowed a 1266x585 phone viewport by ~8 px. Tighter row_gap/pad here only - MatchScreens.card()
			# defaults are unchanged for every other card (PAUSE, YOU'RE OUT, VICTORY/DEFEAT, ...).
			"row_gap": 6.0, "pad": 24.0,
			"pairs": [["SOUND: " + ("ON" if Sfx.sound_on() else "OFF"), func(): Sfx.set_on(not Sfx.sound_on()); _pause_settings()],   # SOUND
				["VOLUME: " + Sfx.volume_label(), func(): Sfx.set_volume(Sfx.next_volume()); _pause_settings()],
				["TEST SOUND", func(): AudioDiag.run_test()]],   # AUDIO DIAG (audio_diag.gd): in the SOUND row, the card no taller
			"pairs2": [["MUSIC: " + ("ON" if Music.music_on() else "OFF"), func(): Music.set_on(not Music.music_on()); _pause_settings()],   # MUSIC
				["MATCH MUSIC: " + Music.volume_label(-1, "match"), func(): Music.set_volume(Music.next_volume("match"), "match"); _pause_settings()]]
				+ ([["FULLSCREEN", FullscreenGate.request]] if FullscreenGate.available() else []),   # 0.22.3: the emergency way back
																									# to fullscreen (web phones), same action as the menu's;
																									# in the MUSIC row so the card grows no taller
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
	# Alpha 24: Debug and Chat are square icon buttons in the top-right row, left of MUSIC (the skills took their column)
	var sq: float = 52.0 if not mobile else 78.0
	debug_button = button("DBG", Callable(), sq, sq, 15)   # 78: matches the phone-tuned default height (>= 44 pt)
	debug_button.toggle_mode = true
	_icon_button(debug_button, "")
	debug_button.add_theme_font_override("font", UiKit.HEAD)
	root.add_child(debug_button)
	debug_button.visible = not main.online and (Rules.debug_tools or Rules.proto_debug)   # online: the rules are the host's,
	                                                               # not live-tunable; offline only when DEBUG TOOLS is on in
	                                                               # OPTIONS (0.18.7) or in a proto build (PROTO DEBUG)
	chat_button = button("", func(): Net.open_chat(), sq, sq, 20)   # online: the room chat (78: >= 44 pt)
	chat_button.tooltip_text = "CHAT"
	_icon_button(chat_button, "chat")
	_chat_dot = Panel.new()
	var dot := StyleBoxTexture.new()
	dot.texture = UiTheme.atlas("B")
	var dr: Array = UiTheme.DATA.SPRITES["B12"]["rect"]
	dot.region_rect = Rect2(dr[0], dr[1], dr[2], dr[3])
	_chat_dot.add_theme_stylebox_override("panel", dot)
	_chat_dot.size = Vector2(20, 20) * ui_scale
	_chat_dot.position = Vector2(chat_button.size.x - _chat_dot.size.x * 0.75, -_chat_dot.size.y * 0.25)
	_chat_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_dot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var dl := text_label("", 13, Color.WHITE)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.size = _chat_dot.size
	_chat_dot.add_child(dl)
	_chat_dot.visible = false
	chat_button.add_child(_chat_dot)
	chat_button.visible = main.online
	root.add_child(chat_button)
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	style_panel(debug_panel, Color("2ee6ff"))
	root.add_child(debug_panel)
	debug_button.toggled.connect(func(on: bool):
		debug_panel.visible = on
		if on:
			_debug_proto_refresh()
			_size_debug_panel())
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
	_debug_box = box
	box.add_child(text_label("Debug - live, resets on reload", 20))
	if Rules.proto_debug:
		_build_proto_debug(box)
		if not Rules.debug_tools:
			return
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


func _build_proto_debug(box: VBoxContainer) -> void:
	## PROTO DEBUG (Daniele, 2026-11-02: "speed up player production and speed up time so I can test fast"): GAME SPEED
	## x1/2/4/8 (the whole sim), MY PRODUCTION x1/2/5/10 (the human seat), REFILL, +100 on the last tapped own node,
	## LAST STAND NOW. Each row reads its value; debug_tag keeps "DEBUG ..." on screen while anything is not x1.
	var h := 50.0 if not mobile else 78.0             # >= 44 pt on phones, as the Debug button
	box.add_child(text_label("PROTO TEST TOOLS", 20, Color("ffd23f")))
	_debug_off_note = text_label("", 18, Color("ffb238"))
	_debug_off_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_off_note.custom_minimum_size = Vector2(480 * ui_scale, 0)
	box.add_child(_debug_off_note)
	_debug_proto = VBoxContainer.new()
	_debug_proto.add_theme_constant_override("separation", 6)
	box.add_child(_debug_proto)
	_debug_choice(_debug_proto, "GAME SPEED", Rules.DEBUG_SPEEDS, h,
			func(): return float(Rules.debug_speed),
			func(v: float): Rules.debug_speed = int(v))
	_debug_choice(_debug_proto, "MY PRODUCTION", Rules.DEBUG_PRODS, h,
			func(): return Rules.debug_prod,
			func(v: float):
				Rules.debug_prod = v
				sim.debug_prod[human] = v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_debug_proto.add_child(row)
	row.add_child(button("REFILL SKILLS", _debug_refill, 150, h, 17))
	_debug_add_button = button("+%d" % Rules.DEBUG_ADD_UNITS, _debug_add, 190, h, 17)
	row.add_child(_debug_add_button)
	row.add_child(button("LAST STAND NOW", _debug_last_stand, 170, h, 17))
	if Rules.debug_prod != 1.0:                       # the multiplier carries over from the last match (resets on reload)
		sim.debug_prod[human] = Rules.debug_prod
	debug_tag = text_label("", 18, Color("ffd23f"))
	var ts := panel_style(Color("ffd23f"))
	ts.bg_color = Color(0.08, 0.06, 0.0, 0.85)
	ts.set_content_margin_all(6 * ui_scale)
	debug_tag.add_theme_stylebox_override("normal", ts)
	root.add_child(debug_tag)
	_debug_proto_refresh()


func _debug_refill() -> void:
	var n := sim.debug_refill(human)
	toast("DEBUG: skills ready%s" % ((", %d relay%s off cooldown" % [n, "" if n == 1 else "s"]) if n > 0 else ""))


func _debug_add() -> void:
	if sim.debug_add_units(_debug_last_node, human):
		toast("DEBUG: +%d on node %d" % [Rules.DEBUG_ADD_UNITS, _debug_last_node])
	else:
		toast("DEBUG: tap one of your nodes first, then +%d" % Rules.DEBUG_ADD_UNITS, "warn")


func _debug_last_stand() -> void:
	if sim.last_stand_active:
		toast("DEBUG: the Last Stand is already on")
	else:
		sim.start_last_stand_now()


func _debug_proto_refresh() -> void:
	## Where the debug may run (offline, outside lessons / missions) and the on-screen tag.
	if _debug_proto == null:
		return
	var ok: bool = main.debug_allowed()
	_debug_proto.visible = ok
	_debug_off_note.visible = not ok
	_debug_off_note.text = "Off in online rooms (every player's sim must stay in sync)" if main.online \
			else "Off in lessons and campaign missions (they run on their own clocks)"
	if _debug_add_button:
		var mine: bool = _debug_last_node >= 0 and _debug_last_node < sim.nodes.size() and sim.nodes[_debug_last_node]["owner"] == human
		_debug_add_button.text = ("+%d ON NODE %d" % [Rules.DEBUG_ADD_UNITS, _debug_last_node]) if mine \
				else ("+%d: TAP YOUR NODE" % Rules.DEBUG_ADD_UNITS)
	var bits := []
	if ok and Rules.debug_speed != 1:
		bits.append("x%d" % Rules.debug_speed)
	if ok and Rules.debug_prod != 1.0:
		bits.append("PROD x%d" % int(Rules.debug_prod))
	debug_tag.text = "DEBUG " + " · ".join(bits)
	debug_tag.visible = not bits.is_empty()
	_place_debug_tag()


func _size_debug_panel() -> void:
	## Under the Debug button, as tall as its content (a ScrollContainer reports no height of its own) but clamped to what
	## is left on screen (phones: the panel used to run off the bottom) - the ScrollContainer then scrolls the rest.
	if debug_panel == null or debug_button == null:
		return
	var vp := _debug_vp if _debug_vp.x > 0.0 else root.get_viewport_rect().size
	var dp_y := debug_button.position.y + debug_button.size.y + 8.0
	var frame := debug_panel.get_theme_stylebox("panel").get_minimum_size()
	var natural := debug_panel.get_combined_minimum_size()
	if _debug_box:
		natural.y = _debug_box.get_combined_minimum_size().y + frame.y
		natural.x = maxf(natural.x, _debug_box.get_combined_minimum_size().x + frame.x)
	debug_panel.size = Vector2(natural.x, minf(natural.y, vp.y - dp_y - 10.0))
	debug_panel.position = Vector2(vp.x - margins.z - debug_panel.size.x, dp_y)


func _place_debug_tag() -> void:
	## PROTO DEBUG: the tag sits left of the Debug button (top right, under PAUSE), off the map's middle.
	if debug_tag == null or debug_button == null:
		return
	debug_tag.size = debug_tag.get_combined_minimum_size()
	debug_tag.position = Vector2(debug_button.position.x - debug_tag.size.x - 8.0,
			debug_button.position.y + (debug_button.size.y - debug_tag.size.y) * 0.5)


func _debug_choice(box: Control, text: String, values: Array, h: float, current: Callable, apply: Callable) -> void:
	## One row: "<TEXT>  xN" (the readout) and a toggle per value; the pressed one is the value in force.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var label := text_label("", 18)
	label.custom_minimum_size = Vector2(190 * ui_scale, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var buttons := []
	var show := func():
		var cur: float = current.call()
		label.text = "%s  x%d" % [text, int(cur)]
		for b in buttons:
			(b as Button).set_pressed_no_signal(is_equal_approx(float((b as Button).get_meta("v")), cur))
	for v in values:
		var b := button("x%d" % int(v), Callable(), 74, h, 18)
		b.toggle_mode = true
		b.set_meta("v", float(v))
		b.pressed.connect(func():
			apply.call(float(v))
			show.call()
			_debug_proto_refresh())
		buttons.append(b)
		row.add_child(b)
	show.call()


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
	for c in [side_panel, pause_button, music_button, debug_button, chat_button, dock]:   # Alpha 18: never under the HUD
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
