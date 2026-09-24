class_name Hud
extends CanvasLayer
## The match interface (Alpha 12): Alpha 11's chrome and layout brought over in full - top bar
## (emblem, your total, timer, rivals, strength bar), pause menu, side command panel with the send
## fractions and the selected vat's count, node badges (count, tier, relay state, build and shield
## bars; never a number on an enemy node), the ring inspector with costed actions, ability dock
## (slots present, disabled until the 2.0 skill pools are approved), toasts, the Last Stand banner
## and drop-order numbers, the results panel with match stats, and the debug panel.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")

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
var fraction_buttons: Array = []
var badges := {}                     # node id -> {panel, label, sub, shield, build, owner}
var inspector: Control
var inspector_id := -1
var inspector_label: Label
var inspector_progress: ProgressBar
var inspector_actions: Array = []
var toast_label: Label
var _toast_time := 0.0
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
var debug_panel: PanelContainer
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
	var s := panel_style(color)
	s.bg_color = Color("101419")
	s.set_corner_radius_all(32)
	s.set_content_margin_all(4)
	return s


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
	# badges first (under everything else)
	for n in sim.nodes:
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.custom_minimum_size = Vector2(70, 44) * ui_scale
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(column)
		var l := text_label("", 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(l)
		var sub := text_label("", 12, Color("c8e6ee"))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(sub)
		var shield_bar := ProgressBar.new()
		shield_bar.show_percentage = false
		shield_bar.custom_minimum_size = Vector2(0, 4 * ui_scale)
		shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb_fill := StyleBoxFlat.new()
		sb_fill.bg_color = Rules.seat_color(human)
		shield_bar.add_theme_stylebox_override("fill", sb_fill)
		var sb_bg := StyleBoxFlat.new()
		sb_bg.bg_color = Color(0, 0, 0, 0.5)
		shield_bar.add_theme_stylebox_override("background", sb_bg)
		column.add_child(shield_bar)
		var build_bar := ProgressBar.new()
		build_bar.show_percentage = false
		build_bar.custom_minimum_size = Vector2(0, 4 * ui_scale)
		build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bb_fill := StyleBoxFlat.new()
		bb_fill.bg_color = Rules.state_color("build")
		build_bar.add_theme_stylebox_override("fill", bb_fill)
		build_bar.add_theme_stylebox_override("background", sb_bg)
		column.add_child(build_bar)
		root.add_child(badge)
		badges[n["id"]] = {"panel": badge, "label": l, "sub": sub, "shield": shield_bar, "build": build_bar, "owner": "?"}
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
		b.pressed.connect(func(): main.fraction = f)
		b.gui_input.connect(func(event):                  # slide a finger over the buttons to pick
			if (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT) or event is InputEventScreenDrag:
				b.button_pressed = true
				main.fraction = f)
		side_box.add_child(b)
		fraction_buttons.append(b)
	count_label = text_label("DRAG A VAT", 14, accent)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_box.add_child(count_label)
	# bottom: map title, hint, ability dock, version
	map_title = text_label(str(main.map.get("name", "")).to_upper(), 20)
	root.add_child(map_title)
	hint = text_label("Drag to send  ·  Tap to inspect  ·  Double-tap your node to upgrade  ·  Relay: tap + SWITCH", 14, Color("d0dceb"))
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.visible = not mobile
	root.add_child(hint)
	dock = HBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	root.add_child(dock)
	for slot in ["ACTIVE", "MAP", "ULTIMATE"]:
		var b := button("%s\nCOMING SOON" % slot, Callable(), 150 if not mobile else 130, 60 if not mobile else 48, 15 if not mobile else 12)
		b.disabled = true
		b.tooltip_text = "Ooze Factory slot - waiting on the 2.0 skill pools (SKILLS-2.0-DRAFT.md)"
		dock.add_child(b)
	version_label = text_label("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], 14, Color(1, 1, 1, 0.5))
	root.add_child(version_label)
	toast_label = text_label("", 22, Color("a9e9f8"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	toast_label.visible = false
	root.add_child(toast_label)
	banner = text_label("", 44, Color("ffd6d6"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.visible = false
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
	var pause_bottom := pause_button.position.y + pause_button.size.y + 8.0
	side_y = maxf(side_y, pause_bottom)                 # never under the pause button (phones)
	side_panel.position = Vector2(vp.x - m.z - side_panel.size.x, side_y)
	map_title.position = Vector2(m.x + 8, vp.y - m.w - 30 * ui_scale)
	hint.size = Vector2(vp.x * 0.5, 20)
	hint.position = Vector2(vp.x * 0.5 - hint.size.x / 2.0, vp.y - m.w - 18)
	dock.size = dock.get_combined_minimum_size()
	dock.position = Vector2(vp.x * 0.5 - dock.size.x / 2.0, vp.y - m.w - dock.size.y - (26 if not mobile else 8))
	version_label.size = version_label.get_combined_minimum_size()
	version_label.position = Vector2(vp.x - m.z - version_label.size.x, vp.y - m.w - version_label.size.y)
	toast_label.size = Vector2(vp.x * 0.6, 34)
	toast_label.position = Vector2(vp.x * 0.2, m.y + top_panel.size.y + 36)
	banner.size = Vector2(vp.x, 120)
	banner.position = Vector2(0, vp.y * 0.28)
	if debug_button:
		debug_button.position = Vector2(m.x, vp.y - m.w - 30 * ui_scale - 8 - debug_button.size.y)
		debug_panel.size = debug_panel.get_combined_minimum_size()
		debug_panel.position = Vector2(m.x, debug_button.position.y - 8.0 - debug_panel.size.y)
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
	return margins.w + (dock.size.y if dock else 0.0) * (1.0 if not mobile else 0.5) + (30.0 if not mobile else 0.0)


func pointer_over_ui(p: Vector2) -> bool:
	for c in [top_panel, pause_button, side_panel, dock, debug_button]:
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
	## Alpha 11: badges are explicit, unobstructed selection targets.
	for id in badges:
		var panel: Control = badges[id]["panel"]
		if panel.visible and panel.get_global_rect().grow(20 if mobile else 4).has_point(p):
			return id
	return -1


# ------------------------------------------------------------------ per frame
func sync(dt: float, cam: Camera3D) -> void:
	var total := sim.seat_strength(human)
	var rivals := 0.0
	for seat in sim.factions.keys():
		if seat != human:
			rivals += sim.seat_strength(seat)
	stats_label.text = "%s  %03d    %02d:%02d    RIVALS  %03d" % [str(main.SEAT_FACTIONS[human]).to_upper(), int(total),
			int(sim.time) / 60, int(sim.time) % 60, int(rivals)]
	for seat in score_sections:
		var count := sim.seat_strength(seat)
		score_sections[seat].visible = count > 0.0
		score_sections[seat].size_flags_stretch_ratio = maxf(1.0, count)
	if sim.last_stand_active:
		var next := ""
		if sim.last_stand_warn_node >= 0:
			next = "NODE %d FALLS IN %d s" % [sim.last_stand_warn_node, int(ceil(sim.last_stand_warn_t))]
		elif sim.last_stand_next < sim.last_stand_order.size():
			next = "next drop in %d s" % int(ceil(maxf(sim._next_wave_at - sim.time, 0.0)))
		else:
			next = "the final node stands - conquest decides"
		status_label.text = "LAST STAND · %s · %s" % [sim.last_stand_method.to_upper(), next]
	elif sim.time > Rules.LAST_STAND_TIME - 15.0:
		status_label.text = "LAST STAND in %d s" % int(ceil(Rules.LAST_STAND_TIME - sim.time))
	else:
		status_label.text = ""
	var source: int = main.drag_from if main.drag_from >= 0 else main.selected
	if source >= 0 and sim.nodes[source]["owner"] == human:
		count_label.text = "%d / %d" % [int(floorf(sim.nodes[source]["units"] * main.fraction)), int(sim.nodes[source]["units"])]
	else:
		count_label.text = "DRAG A VAT"
	_badges(cam)
	_refresh_inspector(cam)
	if _toast_time > 0.0:
		_toast_time -= dt
		if _toast_time <= 0.0:
			toast_label.visible = false
	if _banner_time > 0.0:
		_banner_time -= dt
		banner.modulate.a = clampf(_banner_time / 1.5, 0.0, 1.0)
		if _banner_time <= 0.0:
			banner.visible = false
	_last_fps_print += dt
	if debug_panel.visible and _last_fps_print > 5.0:
		_last_fps_print = 0.0
		print("FPS %d  hordes %d  t=%.0f" % [Engine.get_frames_per_second(), sim.hordes.size(), sim.time])


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
		var key := owner + ("*" if n["id"] == sim.last_stand_warn_node else "")
		if b["owner"] != key:
			b["owner"] = key
			var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			if n["id"] == sim.last_stand_warn_node:
				col = Rules.state_color("warn")
			panel.add_theme_stylebox_override("panel", badge_style(col))
			(b["label"] as Label).add_theme_color_override("font_color", col if owner != "" else Color("d8e0e8"))
		var label: Label = b["label"]
		var sub: Label = b["sub"]
		if owner == "" or owner == human:
			label.text = str(int(n["units"]))
		else:
			label.text = owner                            # no numbers on enemy nodes: seat letter only
		var parts := []
		if n["relay"] != "":
			var st := sim.relay_state_key(n, n["relay_index"])
			parts.append("%s %s" % [Rules.RELAY_GLYPH[n["relay"]], st.to_upper()])
			if n["relay_phase"] == "warning":
				parts.append("!%d" % int(ceil(n["relay_t"])))
			elif n["relay_cd"] > 0.0 and owner == human:
				parts.append("%ds" % int(ceil(n["relay_cd"])))
		elif n["attachment"] == "cannon":
			parts.append("CANNON T%d" % n["cannon_tier"])
		elif n["attachment"] == "forge":
			parts.append("FORGE")
		else:
			parts.append("T%d" % n["tier"])
		if n["build_kind"] != "":
			parts.append("BUILD %ds" % int(ceil(n["build_timer"])))
		if order_shown:
			var k := sim.drop_order_of(n["id"])
			if k > 0:
				parts.append("#%d" % k)
			elif n["id"] == sim.last_stand_final:
				parts.append("FINAL")
		if n["id"] == sim.last_stand_warn_node:
			parts.append("FALLS %d" % int(ceil(sim.last_stand_warn_t)))
		sub.text = " ".join(parts)
		var shield_bar: ProgressBar = b["shield"]
		shield_bar.visible = owner != ""
		if owner != "":
			var cap: float = maxf(Rules.SHIELD_FRACTION * n["units"], 0.001)
			shield_bar.value = 100.0 * clampf(n["shield"] / cap, 0.0, 1.0)
			(shield_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Rules.seat_color(owner) if n["shield_up"] else Rules.state_color("warn")
		var build_bar: ProgressBar = b["build"]
		build_bar.visible = n["build_kind"] != ""
		build_bar.value = 100.0 * Sim.build_progress(n)
		var top: Vector3 = n["pos"] + Vector3(0, 8.5, 0)
		if cam.is_position_behind(top):
			panel.visible = false
			continue
		var p := cam.unproject_position(top)
		panel.size = panel.get_combined_minimum_size()
		panel.position = p - Vector2(panel.size.x / 2.0, 0)


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
	style.bg_color = Color(0.09, 0.13, 0.17, 0.35)
	ring.add_theme_stylebox_override("panel", style)
	inspector.add_child(ring)
	var close := button("X", close_inspector, 64, 52 if not mobile else 80)
	close.position = Vector2(100, 70) * ui_scale
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
	inspector_label = text_label("", 16, Color("c8e6ee"))
	inspector_label.custom_minimum_size = Vector2(364, 0) * ui_scale
	inspector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_bg.add_child(inspector_label)
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
	var text := title + ("\n%d UNITS" % cost if cost > 0 else ("\nFREE" if method == "restore" else "\n15 s CD"))
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
	var who := "NEUTRAL" if owner == "" else ("SEAT %s · %s" % [owner, str(sim.factions.get(owner, "")).to_upper()])
	var lines := []
	if owner != "" and owner != human:
		lines.append("%s · population hidden" % who)
		lines.append(_structure_line(n))
	else:
		var what := _structure_line(n)
		var units := "%d / %d units" % [int(n["units"]), Rules.CAPS[n["tier"]]] if Sim.has_vat(n) else "%d units" % int(n["units"])
		lines.append("%s · %s · %s" % [who, what, units])
		if owner != "":
			var status := "%.1f / s production" % sim.production(n) if Sim.has_vat(n) else "no vat - garrison must be fed"
			var cap: float = maxf(Rules.SHIELD_FRACTION * n["units"], 0.001)
			status += " | shield %d/%d %s" % [int(n["shield"]), int(cap), "UP" if n["shield_up"] else "DOWN"]
			lines.append(status)
	if n["relay"] != "":
		var states := sim.relay_states(n)
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
		lines.append("LAST STAND: %s" % ("drop #%d" % k if k > 0 else ("THE FINAL - never falls" if n["id"] == sim.last_stand_final else "")))
	inspector_label.text = "\n".join(lines)
	inspector_progress.visible = n["build_kind"] != ""
	inspector_progress.value = Sim.build_progress(n) * 100.0
	for a in inspector_actions:
		var b: Button = a["button"]
		var disabled: bool = n["build_kind"] != "" or owner != human or n["units"] < a["cost"]
		if a["method"] == "switch":
			disabled = n["relay_cd"] > 0.0 or n["relay_phase"] != ""
		elif a["method"] in ["build_cannon", "build_forge", "restore"] and n["swap_cd"] > 0.0 and (n["attachment"] != "" or a["method"] == "restore"):
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
func toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.visible = true
	_toast_time = 2.8


func show_banner(msg: String, seconds := 4.0) -> void:
	banner.text = msg
	banner.visible = true
	banner.modulate.a = 1.0
	_banner_time = seconds


# ------------------------------------------------------------------ overlays
func pause_menu() -> void:
	if end_panel.visible:
		return
	main.paused = true
	_fill_overlay(pause_panel, "PAUSED", "%s · %02d:%02d" % [str(main.map.get("name", "")), int(sim.time) / 60, int(sim.time) % 60],
			[["RESUME", func(): main.paused = false; pause_panel.visible = false],
			["RESTART", main.restart], ["MAIN MENU", main.to_menu]])
	pause_panel.visible = true
	layout(root.get_viewport_rect().size, margins)


func show_end(winner: String) -> void:
	main.paused = true
	var title := "VICTORY" if winner == human else ("DEFEAT" if winner != "" else "DRAW")
	var a_lost: float = sim.combat_losses.get(human, 0.0)
	var a_fell: float = sim.fall_losses.get(human, 0.0)
	var captures := sim.events.filter(func(e): return e["type"] == "capture" and e["seat"] == human).size()
	var body := "%s · %02d:%02d\ncaptures %d   ·   lost in combat %d   ·   lost to falls %d\n%s" % [
			str(main.map.get("name", "")), int(sim.time) / 60, int(sim.time) % 60, captures, int(a_lost), int(a_fell),
			("Last Stand: %s" % sim.last_stand_method.to_upper()) if sim.last_stand_active else "decided before the Last Stand"]
	_fill_overlay(end_panel, title, body, [["PLAY AGAIN", main.restart], ["MAIN MENU", main.to_menu]])
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
	## Debug controls for playtests (Daniele, 2026-09-25): live sliders, thumb-sized, bottom-left,
	## wide ranges on purpose. Also prints FPS to the console every 5 s while open.
	debug_button = button("Debug", Callable(), 110, 50 if not mobile else 70, 20)
	debug_button.toggle_mode = true
	debug_button.size = debug_button.custom_minimum_size
	root.add_child(debug_button)
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
	var forge := _debug_slider(box, "Forge bonus", 0.0, 2.0, 0.05, Rules.forge_bonus, "+%.0f%% attack",
			func(v: float): Rules.forge_bonus = v)
	var reset := button("Reset to rules", func():
		deck.value = Rules.DECK_SPEED_DEFAULT
		node.value = Rules.NODE_SPEED_MULT_DEFAULT
		door.value = Rules.DOOR_RATE_DEFAULT
		nfight.value = 1.0
		forge.value = 0.5, 0, 44, 18)
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
