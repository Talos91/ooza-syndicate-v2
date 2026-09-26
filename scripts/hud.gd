class_name Hud
extends CanvasLayer
## The match interface (2.0): Alpha 11's chrome and layout brought over in full - top bar (emblem,
## your total, timer, rivals, strength bar), pause menu, side send panel with the fractions and the
## selected vat's count, node badges floating beside their nodes (count - the owner's emblem in the
## owner's colour instead on enemy nodes in SIEGE or when enemy counts are hidden -, emblem, tier,
## relay state, build bar), the
## ring inspector with costed actions, a hidden ability dock (slots waiting on the 2.0 skill pools),
## toasts, the Last Stand banner, status line and drop order, the results panel with match stats,
## and the debug panel.

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
var stats_label: Label
var strength_bar: HBoxContainer
var score_sections := {}
var pause_button: Button
var side_panel: PanelContainer
var side_box: VBoxContainer
var count_label: Label
var badges := {}                     # node id -> {panel, label, sub, emblem, build, owner, count_w, sub_w, look}
var _badge_px := Vector2.ZERO        # the one badge size on this screen (BADGE_SIZE x ui_scale)
var inspector: Control
var inspector_id := -1
var inspector_label: Label
var inspector_emblem: TextureRect       # the header: owner's emblem + faction name in the owner's colour
var inspector_who: Label
var inspector_first: Label
var inspector_progress: ProgressBar
var inspector_actions: Array = []
var notices: VBoxContainer
var banner: Label
var _banner_time := 0.0
var status_label: Label                # Last Stand status under the top bar
var hint: Label
var map_title: Label
var dock: HBoxContainer
var end_panel: PanelContainer
var pause_panel: PanelContainer
var rotate_hint: Label
var debug_button: Button
var chat_button: Button
var _chat_poll := 0.0
var debug_panel: PanelContainer
var _bridge_text := Callable()          # Debug panel text refreshers (see _refresh_mode_texts)
var _hide_text := Callable()
var margins := Vector4(16, 12, 16, 12)
var _last_fps_print := 0.0
var version_label: Label
var ui_scale := 1.0


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


static func tint_emblem(rect: TextureRect, color: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = EMBLEM_TINT
	m.set_shader_parameter("tint", color)
	rect.material = m
	rect.modulate = Color.WHITE


static var _emblem_cache := {}


static func emblem_texture(faction: String) -> Texture2D:
	## A faction emblem for the HUD's small spots (badges, inspector, toasts). The SVGs are 200 px and
	## imported without mipmaps, so drawn at ~20 px their thin strokes broke up: a mipmapped copy is
	## made once per faction (the imported texture itself if its image can't be read back).
	if _emblem_cache.has(faction):
		return _emblem_cache[faction]
	var path := "res://assets/ui/%s.svg" % faction
	var tex: Texture2D = load(path if ResourceLoader.exists(path) else "res://assets/ui/null.svg")
	var out: Texture2D = tex
	var img: Image = tex.get_image() if tex else null
	if img and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.fix_alpha_edges()                          # no dark fringe in the smaller mip levels
		img.generate_mipmaps()
		# the thin-stroke emblems (NULL, VEX) averaged down to a faint haze at badge size: the coverage
		# of the small levels (50 px and below) is lifted so their strokes keep reading as lines
		var lut := PackedByteArray()
		lut.resize(256)
		for a in range(256):
			lut[a] = int(round(255.0 * pow(a / 255.0, 0.5)))
		var data := img.get_data()
		var from := img.get_mipmap_offset(mini(2, img.get_mipmap_count()))
		for i in range(from + 3, data.size(), 4):
			data[i] = lut[data[i]]
		img = Image.create_from_data(img.get_width(), img.get_height(), true, Image.FORMAT_RGBA8, data)
		out = ImageTexture.create_from_image(img)
	_emblem_cache[faction] = out
	return out


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
	_badge_px = (BADGE_SIZE * ui_scale).round()
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
		root.add_child(badge)
		badges[n["id"]] = {"panel": badge, "label": l, "sub": sub, "emblem": emblem, "build": build_bar, "owner": "?",
				"count_w": 0.0, "sub_w": 0.0, "sub_small": false, "wide": false, "shape": "", "look": -1}
	# top bar: emblem, your total, timer, rivals, strength bar (Alpha 11's score header)
	top_panel = PanelContainer.new()
	style_panel(top_panel, accent)
	root.add_child(top_panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	top_panel.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	stack.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/%s.svg" % main.SEAT_FACTIONS[human])
	tint_emblem(icon, Rules.seat_color(human))           # your emblem in your colour
	icon.custom_minimum_size = Vector2(34, 34) * ui_scale
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	stats_label = text_label("", 22)
	row.add_child(stats_label)
	strength_bar = HBoxContainer.new()
	strength_bar.add_theme_constant_override("separation", 2)
	strength_bar.custom_minimum_size.y = 8 * ui_scale
	stack.add_child(strength_bar)
	for seat in sim.factions.keys():
		var segment := ColorRect.new()
		segment.color = Rules.seat_color(seat)
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strength_bar.add_child(segment)
		score_sections[seat] = segment
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
		var b := button("%d%%" % int(f * 100), Callable(), 100, 66 if not mobile else 64, 26)
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
	hint.visible = not mobile
	root.add_child(hint)
	dock = HBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	root.add_child(dock)
	dock.visible = false                              # no abilities in 2.0 yet: an empty dock only covered the map
	for slot in ["ACTIVE", "MAP", "ULTIMATE"]:
		var b := button("%s\nCOMING SOON" % slot, Callable(), 150 if not mobile else 130, 60 if not mobile else 48, 15 if not mobile else 12)
		b.disabled = true
		b.tooltip_text = "Ooze Factory slot - waiting on the 2.0 skill pools (SKILLS-2.0-DRAFT.md)"
		dock.add_child(b)
	version_label = text_label("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], 14, Color(1, 1, 1, 0.5))
	root.add_child(version_label)
	notices = VBoxContainer.new()                     # Alpha 16: styled notification stack
	notices.add_theme_constant_override("separation", int(6 * ui_scale))
	notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notices)
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
	end_panel = PanelContainer.new()
	end_panel.visible = false
	style_panel(end_panel, accent)
	root.add_child(end_panel)
	pause_panel = PanelContainer.new()
	pause_panel.visible = false
	style_panel(pause_panel, accent)
	root.add_child(pause_panel)


func _hint_text() -> String:
	return "Drag to send  ·  Tap a node to inspect  ·  Double-tap your node to upgrade" + ("  ·  Tap your line to RECALL it" if Rules.bridge_combat else "")


func _refresh_mode_texts() -> void:
	## The texts that depend on SIEGE/BRAWL, rebuilt when the mode is switched mid-match (pause menu
	## or Debug): the hint line (RECALL is SIEGE-only) and the Debug mode and enemy-count buttons.
	hint.text = _hint_text()
	if _bridge_text.is_valid():
		_bridge_text.call()
	if _hide_text.is_valid():
		_hide_text.call()


func layout(vp: Vector2, m: Vector4) -> void:
	margins = m
	top_panel.size = top_panel.get_combined_minimum_size()
	top_panel.position = Vector2(m.x, m.y)
	status_label.size = Vector2(top_panel.size.x, 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.position = Vector2(m.x + 4, m.y + top_panel.size.y + 2)
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
	version_label.size = version_label.get_combined_minimum_size()
	version_label.position = Vector2(vp.x - m.z - version_label.size.x, vp.y - m.w - version_label.size.y)
	notices.size = Vector2(vp.x * 0.56, 0)
	notices.position = Vector2(vp.x * 0.22, m.y + top_panel.size.y + 14 * ui_scale)
	banner.size = banner.get_combined_minimum_size()
	banner.position = Vector2((vp.x - banner.size.x) / 2.0, vp.y * 0.26)
	if debug_button:
		debug_button.position = Vector2(vp.x - m.z - debug_button.size.x, pause_button.position.y + pause_button.size.y + 8.0)   # under PAUSE, off the map
		debug_panel.size = debug_panel.get_combined_minimum_size()
		debug_panel.position = Vector2(vp.x - m.z - debug_panel.size.x, debug_button.position.y + debug_button.size.y + 8.0)
	if chat_button:
		chat_button.position = Vector2(vp.x - m.z - chat_button.size.x, pause_button.position.y + pause_button.size.y + 8.0)   # Debug's slot (hidden online)
	rotate_hint.size = vp
	rotate_hint.visible = vp.y > vp.x
	for p in [end_panel, pause_panel]:
		p.size = p.get_combined_minimum_size()
		p.position = (vp - p.size) / 2.0


func side_panel_width() -> float:
	return side_panel.size.x if side_panel else 0.0


func top_used() -> float:
	return margins.y + (top_panel.size.y if top_panel else 0.0) + 34.0


func bottom_used() -> float:
	return margins.w + 30.0 * ui_scale                   # the map title and hint line (badges are fitted by the camera)


func pointer_over_ui(p: Vector2) -> bool:
	for c in [top_panel, pause_button, side_panel, dock, debug_button, chat_button]:
		if c and c.visible and c.get_global_rect().has_point(p):
			return true
	if debug_panel and debug_panel.visible and debug_panel.get_global_rect().has_point(p):
		return true
	if is_instance_valid(inspector):
		for a in inspector_actions:
			if (a["button"] as Button).get_global_rect().has_point(p):
				return true
		if inspector.has_meta("close") and (inspector.get_meta("close") as Button).get_global_rect().has_point(p):
			return true
	return end_panel.visible or pause_panel.visible


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
	var strength := {}                                # one walk per seat per frame
	for seat in sim.factions.keys():
		strength[seat] = sim.seat_strength(seat)
	var total: float = strength[human] if strength.has(human) else sim.seat_strength(human)
	var rivals := 0.0
	for seat in sim.factions.keys():
		if not sim.allied(seat, human):
			rivals += strength[seat]
	stats_label.text = "%s  %03d    %02d:%02d    RIVALS  %03d" % [str(main.SEAT_FACTIONS[human]).to_upper(), Rules.shown(total),
			int(sim.time) / 60, int(sim.time) % 60, Rules.shown(rivals)]
	for seat in score_sections:
		var count: float = strength[seat]
		score_sections[seat].visible = count > 0.0
		score_sections[seat].size_flags_stretch_ratio = maxf(1.0, count)
	if sim.last_stand_active:
		var next := ""
		var pending: int = sim.last_stand_waves.size() if sim.v3 else sim.last_stand_order.size()
		if sim.v3 and not sim.last_stand_warn.is_empty():
			next = "RING %d FALLING · next platform in %d s (%d left)" % [sim.last_stand_next, int(ceil(sim.last_stand_warn_t)), sim.last_stand_queue.size()]
		elif sim.last_stand_warn_node >= 0:
			next = "NODE %d FALLS IN %d s" % [sim.last_stand_warn_node, int(ceil(sim.last_stand_warn_t))]
		elif sim.last_stand_next < pending:
			next = "next drop in %d s" % int(ceil(maxf(sim._next_wave_at - sim.time, 0.0)))
		else:
			next = ("the last ring stands" if sim.v3 else "the final node stands") + " - conquest decides"
		status_label.text = "LAST STAND · %s · %s" % [sim.last_stand_method.to_upper(), next]
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
	_refresh_inspector(cam)
	_sync_notices(dt)
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
		panel.visible = true
		var owner: String = n["owner"]
		var key := owner + ("*" if sim.is_warned(n["id"]) else "")
		if b["owner"] != key:
			b["owner"] = key
			var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			if sim.is_warned(n["id"]):
				col = Rules.state_color("warn")
			panel.add_theme_stylebox_override("panel", badge_style(col))
			(b["label"] as Label).add_theme_color_override("font_color", col if owner != "" else Color("d8e0e8"))
		var label: Label = b["label"]
		var sub: Label = b["sub"]
		var classic := not Rules.bridge_combat
		var masked := not (owner == "" or sim.allied(owner, human) or (classic and not Rules.hide_enemy_counts))   # Brawl = Alpha 11: every count, unless hidden
		label.visible = not masked
		var inner := _badge_px.x - 2.0 * BADGE_PAD * ui_scale
		if not masked:
			b["count_w"] = _fit_text(label, str(Rules.shown(n["units"])), BADGE_COUNT_FONT, inner, b["count_w"])
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
			what = Rules.RELAY_GLYPH[n["relay"]] + ("OUT" if st == "out" else "IN" if st == "retract" else st.to_upper())
		elif n["attachment"] == "cannon":
			what = "CN%d" % n["cannon_tier"]
		elif n["attachment"] == "forge":
			what = "FRG"
		else:
			what = "T%d" % n["tier"]
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
	if vp != _layout_vp or xf != _layout_xf:
		_layout_vp = vp
		_layout_xf = xf
		_layout_badges(cam)
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


func _inspector_actions(n: Dictionary) -> void:
	var id: int = n["id"]
	var is_final: bool = n["relay"] == "" and ("cannon" in n["buildable"] or "forge" in n["buildable"])
	if n["relay"] != "":
		_add_action("SWITCH\n%s" % Rules.RELAY_GLYPH[n["relay"]], 0, "switch", id)
	if Sim.has_vat(n):
		if n["tier"] < 4:
			_add_action("UPGRADE T%d" % (n["tier"] + 1), Sim.vat_cost(n), "upgrade", id)
	elif n["attachment"] == "cannon" and n["cannon_tier"] < 3:
		_add_action("CANNON T%d" % (n["cannon_tier"] + 1), Rules.CANNON_COST[n["cannon_tier"] + 1], "upgrade", id)
	for kind in ["cannon", "forge"]:
		if kind in n["buildable"] and n["attachment"] != kind:
			_add_action(kind.to_upper(), Rules.CANNON_COST[1] if kind == "cannon" else Rules.FORGE_COST, "build_" + kind, id)
	if is_final and n["attachment"] != "":
		_add_action("RESTORE VAT", 0, "restore", id)


func _add_action(title: String, cost: int, method: String, id: int) -> void:
	# prices shown at Alpha 11 scale like every other number (Alpha 14 playtest: "upgrade info still
	# says 150") - the button used to print the raw internal cost
	var text := title + ("\n%d UNITS" % Rules.shown(cost) if cost > 0 else ("\nFREE" if method == "restore" else "\n%d s CD" % int(Rules.RELAY_COOLDOWN)))
	var b := button(text, func():
		if main.node_action(method, id):
			close_inspector()
		else:
			_refresh_inspector(main.cam), 150, 82 if not mobile else 100, 16)
	var slots := [Vector2(-75, -175), Vector2(80, -60), Vector2(-230, -60), Vector2(80, 30)]
	b.position = slots[mini(inspector_actions.size(), slots.size() - 1)] * ui_scale
	var style := panel_style(Rules.seat_color(human))
	style.set_corner_radius_all(int(40 * ui_scale))
	b.add_theme_stylebox_override("normal", style)
	inspector.add_child(b)
	inspector_actions.append({"button": b, "cost": cost, "method": method})


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
		var units := "%d / %d units" % [Rules.shown(n["units"]), Rules.shown(Rules.CAPS[n["tier"]])] if Sim.has_vat(n) else "%d units" % Rules.shown(n["units"])
		lines.append("%s · %s" % [what, units])
		if owner != "":
			# Alpha 11's status line: production, and what a double-tap upgrade costs
			var status := "%.1f / s production" % Rules.shown_f(sim.production(n)) if Sim.has_vat(n) else "no vat - garrison must be fed"
			var up := sim.upgrade_cost(n)
			if owner == human and up > 0:
				status += " | Double-tap: %d units" % Rules.shown(up)
			elif owner == human and Sim.has_vat(n) and n["tier"] >= 4:
				status += " | MAX TIER"
			lines.append(status)
			lines.append("garrison %s | attack %d%% | speed %d%%" % [
					"%d%%" % roundi(sim.stat(owner, "garrison") * 100.0), roundi(sim.attack_of(owner) * 100.0),
					roundi(sim.stat(owner, "speed") * 100.0)])
	if n["relay"] != "":
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
	if n["attachment"] == "cannon" and owner == human:
		lines.append("cannon %s" % ("FIRING" if n["cannon_burst"] > 0.0 else ("READY" if n["cannon_cd"] <= 0.0 else "RECHARGING %.1f s" % n["cannon_cd"])))
	if n["build_kind"] != "":
		lines.append("BUILDING %s · %.1f s" % [str(n["build_target"].get("kind", n["build_kind"])).to_upper(), n["build_timer"]])
	if n["swap_cd"] > 0.0 and owner == human:
		lines.append("attachment swap in %.0f s" % ceil(n["swap_cd"]))
	if sim.last_stand_active:
		var k := sim.drop_order_of(n["id"])
		lines.append("LAST STAND: %s" % ((("falls in wave %d" if sim.v3 else "drop #%d") % k) if k > 0 else ("THE %s - never falls" % ("LAST RING" if sim.v3 else "FINAL") if sim.is_final(n["id"]) else "")))
	inspector_first.text = "· " + str(lines.pop_front())
	inspector_label.text = "\n".join(lines)
	inspector_label.visible = not lines.is_empty()
	inspector_progress.visible = n["build_kind"] != ""
	inspector_progress.value = Sim.build_progress(n) * 100.0
	for a in inspector_actions:
		var b: Button = a["button"]
		var disabled: bool = n["build_kind"] != "" or owner != human or n["units"] < a["cost"]
		if a["method"] == "switch":
			disabled = n["relay_cd"] > 0.0 or n["relay_phase"] != ""
		elif a["method"] in ["build_cannon", "build_forge", "restore"] and n["swap_cd"] > 0.0 and (n["attachment"] != "" or (n["relay"] == "" and n["tier"] > 0) or a["method"] == "restore"):   # sim.build_attachment's swap test
			disabled = true
		b.disabled = disabled


func _structure_line(n: Dictionary) -> String:
	if n["relay"] != "":
		return "%s RELAY" % n["relay"].to_upper() + (" + %s" % n["attachment"].to_upper() if n["attachment"] != "" else " (empty socket)")
	if n["attachment"] == "cannon":
		return "CANNON T%d" % n["cannon_tier"]
	if n["attachment"] == "forge":
		return "FORGE"
	return "VAT T%d" % n["tier"]


func close_inspector() -> void:
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = null
	inspector_id = -1
	inspector_actions.clear()


# ------------------------------------------------------------------ messages
const NOTICE_HOLD := 3.0
const NOTICE_MAX := 3
const WARN_WORDS := ["lost", "falls", "get out", "can't", "Can't", "No ", "needs", "refused", "rejected", "on cooldown",
		"swap ready", "Not your", "Too many", "already", "max tier", "no further", "Nothing", "missing", "Waiting"]
static var _SEAT_WORD := RegEx.create_from_string("(?i)\\bseat ([A-F])\\b(?: \\([^)]*\\))?")   # "seat B", "seat A (NULL)"
const GOOD_WORDS := ["captured", "Sending", "Recalled", "reconnected", "Upgrade started", "construction started", "Restoring", "Relay fired"]


func toast(msg: String, kind := "") -> void:
	## Alpha 16: notifications in the UI's own panel style (Daniele: "better notifications, the same
	## style as the rest of the UI"): a framed line with a colour bar - info cyan, good news in your
	## colour, builds gold, warnings red - sliding in under the top bar, three at most, fading out.
	if kind == "":
		kind = "info"
		for w in WARN_WORDS:
			if w in msg:
				kind = "warn"
		if kind == "info":
			for w in GOOD_WORDS:
				if w in msg:
					kind = "build" if ("started" in w or "Restoring" in w) else "good"
	var col: Color = {"warn": Rules.state_color("warn"), "good": Rules.seat_color(human), "build": Rules.state_color("build")}.get(kind, Color("7fe9f5"))
	for c in notices.get_children():                 # the same line again: refresh it, don't stack
		if c.get_meta("text", "") == msg and not c.is_queued_for_deletion():
			c.set_meta("t", 0.0)
			return
	var p := PanelContainer.new()
	var st := panel_style(col)
	st.set_content_margin_all(0)
	st.content_margin_right = 14 * ui_scale
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * ui_scale))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(5, 30) * ui_scale
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	# a line naming a player ("lost to seat B", "Seat C reconnected", "you are seat A (NULL)") names
	# them by emblem and faction in their colour instead (Daniele: "don't use A B and C")
	var named := _SEAT_WORD.search(msg)
	var seat := named.get_string(1).to_upper() if named else ""
	if seat != "" and sim.factions.has(seat):
		row.add_child(seat_emblem(seat, Vector2(24, 24)))
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.scroll_active = false
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rt.add_theme_font_override("normal_font", UI_FONT)
		rt.add_theme_font_size_override("normal_font_size", int(18 * ui_scale))
		rt.add_theme_color_override("default_color", Color("e6f4f8"))
		rt.text = "%s[color=#%s]%s[/color]%s" % [msg.substr(0, named.get_start()).replace("[", "[lb]"),
				Rules.seat_color(seat).to_html(false), str(sim.factions[seat]).to_upper(), msg.substr(named.get_end()).replace("[", "[lb]")]
		row.add_child(rt)
	else:
		var l := text_label(msg, 18, Color("e6f4f8"))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
	p.set_meta("text", msg)
	p.set_meta("t", 0.0)
	p.modulate.a = 0.0
	notices.add_child(p)
	while notices.get_child_count() > NOTICE_MAX:
		var old := notices.get_child(0)
		notices.remove_child(old)
		old.queue_free()


func _sync_notices(dt: float) -> void:
	for c in notices.get_children():
		var t: float = float(c.get_meta("t", 0.0)) + dt
		c.set_meta("t", t)
		var a := minf(t / 0.18, 1.0) * clampf((NOTICE_HOLD + 0.45 - t) / 0.45, 0.0, 1.0)
		(c as Control).modulate.a = a
		(c as Control).pivot_offset = (c as Control).size / 2.0
		(c as Control).scale = Vector2.ONE * lerpf(0.92, 1.0, minf(t / 0.18, 1.0))   # pops in
		if t > NOTICE_HOLD + 0.45:
			notices.remove_child(c)
			c.queue_free()


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
func pause_menu() -> void:
	if end_panel.visible:
		return
	if main.online:                                   # a room never pauses (Alpha 11): the menu only
		_fill_overlay(pause_panel, "ROOM %s" % Net.room_code, "%s · %02d:%02d · the match keeps running" % [
				str(main.map.get("name", "")), int(sim.time) / 60, int(sim.time) % 60],
				[["RESUME", func(): pause_panel.visible = false], ["LEAVE ROOM", main.to_menu]])
		pause_panel.visible = true
		layout(root.get_viewport_rect().size, margins)
		return
	main.paused = true
	_fill_overlay(pause_panel, "PAUSED", "%s · %02d:%02d" % [str(main.map.get("name", "")), int(sim.time) / 60, int(sim.time) % 60],
			[["RESUME", func(): main.paused = false; pause_panel.visible = false],
			["MODE: %s" % ("SIEGE" if Rules.bridge_combat else "BRAWL"), func():
				Rules.bridge_combat = not Rules.bridge_combat
				_refresh_mode_texts()
				pause_menu()],
			["LAST STAND: %s" % ("ON" if Rules.last_stand else "OFF"), func():
				Rules.last_stand = not Rules.last_stand
				pause_menu()],
			["RESTART", main.restart], ["MAIN MENU", main.to_menu]])
	pause_panel.visible = true
	layout(root.get_viewport_rect().size, margins)


var _end_winner := ""


func _on_rematch_changed() -> void:
	if end_panel.visible:
		show_end(_end_winner)


func show_end(winner: String) -> void:
	_end_winner = winner
	main.paused = true
	var title := "VICTORY" if sim.allied(winner, human) else ("DEFEAT" if winner != "" else "DRAW")   # team modes: allies win together
	var a_lost: float = sim.combat_losses.get(human, 0.0)
	var a_fell: float = sim.fall_losses.get(human, 0.0)
	var captures := sim.events.filter(func(e): return e["type"] == "capture" and e["seat"] == human).size()
	var body := "%s · %02d:%02d\ncaptures %d   ·   lost in combat %d   ·   lost to falls %d\n%s" % [
			str(main.map.get("name", "")), int(sim.time) / 60, int(sim.time) % 60, captures, Rules.shown(a_lost), Rules.shown(a_fell),
			("Last Stand: %s" % sim.last_stand_method.to_upper()) if sim.last_stand_active else "decided before the Last Stand"]
	if main.online:
		var votes: int = Net.rematch_votes.size()
		var mine: bool = Net.rematch_votes.has(Net.local_id())
		body += "
REMATCH: %d / %d ready%s" % [votes, Net.present_ids().size(), " - waiting for the others" if mine else ""]
		_fill_overlay(end_panel, title, body, [["REMATCH" if not mine else "REMATCH - READY", func(): Net.request_rematch()],
				["LEAVE ROOM", main.to_menu]])
		if not Net.rematch_changed.is_connected(_on_rematch_changed):
			Net.rematch_changed.connect(_on_rematch_changed)
	else:
		_fill_overlay(end_panel, title, body, [["REMATCH", main.restart], ["MAIN MENU", main.to_menu]])
	end_panel.visible = true
	pause_panel.visible = false
	layout(root.get_viewport_rect().size, margins)


func _fill_overlay(panel: PanelContainer, title: String, body: String, actions: Array) -> void:
	for c in panel.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(460, 0) * ui_scale
	panel.add_child(col)
	var t := text_label(title, 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var b := text_label(body, 18, Color("c8e6ee"))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(b)
	for a in actions:
		var btn := button(a[0], a[1], 0, 56 if not mobile else 80, 22)
		col.add_child(btn)


# ------------------------------------------------------------------ debug panel
func _build_debug() -> void:
	## Debug controls for playtests (Daniele, 2026-09-25): live sliders, thumb-sized, top-right under PAUSE,
	## wide ranges on purpose. Also prints FPS to the console every 5 s while open.
	debug_button = button("Debug", Callable(), 110, 50 if not mobile else 70, 20)
	debug_button.toggle_mode = true
	debug_button.size = debug_button.custom_minimum_size
	root.add_child(debug_button)
	debug_button.visible = not main.online           # online: the rules are the host's, not live-tunable
	chat_button = button("Chat", func(): Net.open_chat(), 110, 50 if not mobile else 70, 20)   # online: the room chat
	chat_button.size = chat_button.custom_minimum_size
	chat_button.visible = main.online
	root.add_child(chat_button)
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	style_panel(debug_panel, Color("2ee6ff"))
	root.add_child(debug_panel)
	debug_button.toggled.connect(func(on: bool): debug_panel.visible = on)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	debug_panel.add_child(box)
	box.add_child(text_label("Debug - live, resets on reload", 20))
	var deck := _debug_slider(box, "Deck speed", 0.2, 30.0, 0.1, Rules.deck_speed, "%.1f m/s",
			func(v: float): Rules.deck_speed = v)
	var node := _debug_slider(box, "Platform speed", 0.1, 30.0, 0.05, Rules.node_speed_mult, "x%.2f deck",
			func(v: float): Rules.node_speed_mult = v)
	var door := _debug_slider(box, "Door rate", 1.0, 500.0, 1.0, Rules.door_rate, "%.0f units/s",
			func(v: float): Rules.door_rate = v)
	var nfight := _debug_slider(box, "Platform fight", 0.05, 20.0, 0.05, Rules.node_fight_mult, "x%.2f rate",
			func(v: float): Rules.node_fight_mult = v)
	var forge := _debug_slider(box, "Forge bonus", 0.0, 200.0, 5.0, Rules.forge_bonus * 100.0, "+%.0f%% attack",
			func(v: float): Rules.forge_bonus = v / 100.0)
	var bridge := button("", Callable(), 0, 44, 18)
	var bridge_text := func(): bridge.text = "Mode: %s" % ("SIEGE (fights on bridges)" if Rules.bridge_combat else "BRAWL (Alpha 11 - pass through, fight at nodes)")
	bridge_text.call()
	_bridge_text = bridge_text
	bridge.pressed.connect(func():
		Rules.bridge_combat = not Rules.bridge_combat
		_refresh_mode_texts()
		toast("Mode: %s" % ("SIEGE" if Rules.bridge_combat else "BRAWL")))
	box.add_child(bridge)
	var hide := button("", Callable(), 0, 44, 18)
	var hide_text := func(): hide.text = "Enemy counts: %s" % ("HIDDEN" if Rules.hide_enemy_counts or Rules.bridge_combat else "SHOWN") + (" (Siege always hides)" if Rules.bridge_combat and not Rules.hide_enemy_counts else "")
	hide_text.call()
	_hide_text = hide_text
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
	var reset := button("Reset to rules", func():
		deck.value = Rules.DECK_SPEED_DEFAULT
		node.value = Rules.NODE_SPEED_MULT_DEFAULT
		door.value = Rules.DOOR_RATE_DEFAULT
		nfight.value = Rules.NODE_FIGHT_MULT_DEFAULT
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
		placed.append([best, rb])


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
