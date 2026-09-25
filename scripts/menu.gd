class_name Menu
extends CanvasLayer
## Alpha 11's front menu, ported page for page (Daniele: "I want the damn menu as for Alpha 11"):
## the same backdrop art (assets/art/ui-main.png), neon-cut frames (neon_panel.gd), ui-kit buttons
## per faction (ui_skin.gd), stepper strip, wordmark, Russo One headings, and the same coordinates
## - Alpha 11 laid out on a 1672x941 canvas, ours is 1280x720, so everything is scaled by K.
## MAIN -> 01 FACTION (portrait / stats + trait / abilities / faction tabs) -> 02 BATTLEFIELD
## (3D thumbnails + preview) -> 03 SETUP (your faction, rival, difficulty, bridge combat) -> DEPLOY.
## OPTIONS holds the match switches (bridge combat, detail). TUTORIAL / ONLINE are not in 2.0 yet.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const K := 1280.0 / 1672.0
const NAMES := {"vex": "VEX\nBIOENGINEERS", "null": "NULL\nCARTEL", "bloom": "VIRIDIAN\nBLOOM", "ember": "EMBER\nMAW", "solar": "SOLAR\nSHELLS"}

var main: Node3D
var content: Control
var faction := "null"
var rival := "random"
var map_path := "res://maps/004-two-piers.json"
var ai_level := "Standard"
var maps: Array = []
var _is_main := false


func setup(m: Node3D) -> void:
	main = m
	faction = m.SEAT_FACTIONS[m.HUMAN]
	ai_level = m.ai_level
	map_path = m.map_path
	for mp in m.STARTER_MAPS:
		maps.append({"path": mp, "data": MapBuilder.load_map(mp)})
	show_main()


static func P(x: float, y: float) -> Vector2:
	return Vector2(x, y) * K


func color() -> Color:
	return Color("18dae8") if _is_main else Rules.FACTIONS[faction][1]


# ------------------------------------------------------------------ Alpha 11's widgets
func clear_page(art: String) -> void:
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	_is_main = art == "ui-main"
	if art == "ui-main":
		picture("res://assets/art/ui-main.png", Vector2.ZERO, P(1672, 941))
	else:
		atlas_picture("res://assets/art/ui-main.png", Rect2(0.36, 0, 0.64, 1), Vector2.ZERO, P(1672, 941))
		var shade := ColorRect.new()
		shade.color = Color(0, 0.015, 0.025, 0.25)
		shade.size = P(1672, 941)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(shade)


func text_label(text: String, size_value: int = 20, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HEAD_FONT if size_value >= 24 else UI_FONT)
	l.add_theme_font_size_override("font_size", int(round(size_value * K)))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func label_at(text: String, pos: Vector2, size_value: int = 20, col: Color = Color.WHITE) -> Label:
	var l := text_label(text, size_value, col)
	l.position = pos
	content.add_child(l)
	return l


func button(text: String, call: Callable, width: float = 130.0) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", UI_FONT)
	b.text = text
	b.custom_minimum_size = Vector2(width, 52.0 * K)
	b.add_theme_stylebox_override("normal", Hud.panel_style())
	b.add_theme_stylebox_override("hover", Hud.panel_style(color()))
	var pressed := Hud.panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_disabled_color", Color("a6b2bb"))
	b.add_theme_font_size_override("font_size", int(round(19 * K)))
	b.pressed.connect(func(): call.call_deferred())
	UiSkin.button(b, faction)
	return b


func nav_button(text: String, pos: Vector2, dims: Vector2, call: Callable, primary := false) -> Button:
	var b := button(text, call, dims.x)
	b.position = pos
	b.custom_minimum_size = dims
	b.size = dims
	b.add_theme_font_size_override("font_size", int(round(25 * K)))
	UiSkin.button(b, "vex" if _is_main else faction, primary)
	content.add_child(b)
	return b


func neon_panel(pos: Vector2, dims: Vector2, accent: Color, glow: bool, fill: Color) -> Control:
	var p := NeonPanel.new()
	p.position = pos
	p.size = dims
	p.accent = accent
	p.glowing = glow
	p.fill = fill
	return p


func frame(pos: Vector2, dims: Vector2, skin := "Panels/panel-large") -> Control:
	var p := neon_panel(pos, dims, color(), false, Color("030c12ec") if skin != "row" else Color("020a10e8"))
	content.add_child(p)
	return p


func picture(path: String, pos: Vector2, dims: Vector2) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var p := TextureRect.new()
	p.texture = load(path)
	p.position = pos
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if path.ends_with(".svg") else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(p)
	p.size = dims
	p.set_deferred("size", dims)                      # Alpha 11 gotcha: size set before enter-tree is reset
	return p


func atlas_picture(path: String, region: Rect2, pos: Vector2, dims: Vector2) -> TextureRect:
	var texture: Texture2D = load(path)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(region.position * Vector2(texture.get_size()), region.size * Vector2(texture.get_size()))
	atlas.filter_clip = true
	var p := TextureRect.new()
	p.texture = atlas
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.position = pos
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(p)
	p.size = dims
	p.set_deferred("size", dims)
	return p


func portrait(f: String, pos: Vector2, dims: Vector2) -> TextureRect:
	if f == "vex":
		return atlas_picture("res://assets/art/ui-faction.png", Rect2(0.02, 0.092, 0.333, 0.54), pos, dims)
	return atlas_picture("res://assets/art/%s.png" % f, Rect2(0.43, 0.035, 0.54, 0.86), pos, dims)


func neon_icon(icon_name: String, pos: Vector2, dims: Vector2, col: Color) -> void:
	var path := "res://assets/icons/%s.png" % icon_name
	if not ResourceLoader.exists(path):
		return
	for spread in [8.0, 4.0]:
		var glow := atlas_picture(path, Rect2(0, 0, 1, 1), pos - Vector2.ONE * spread / 2.0, dims + Vector2.ONE * spread)
		glow.modulate = Color(col, 0.23)
	var icon := atlas_picture(path, Rect2(0, 0, 1, 1), pos, dims)
	icon.modulate = col


func header(step: int) -> void:
	picture("res://assets/ui/Ooze-Syndicate-Wordmark.svg", P(35, 10), P(172, 64))
	if step > 0:
		picture("res://assets/ui-kit/Navigation/stepper-%d.png" % step, P(565, 20), P(620, 59))
	label_at("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], P(1480, 34), 16, Color("839da9"))


func map_preview(pos: Vector2, dims: Vector2) -> void:
	var code: String = _selected_map().get("code", "")
	if not picture("res://assets/map-thumbnails/%s.png" % code, pos, dims):
		var svg := picture(map_path.replace("maps/", "assets/maps/").replace(".json", ".svg"), pos, dims)
		if svg:
			svg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


# ------------------------------------------------------------------ pages
func show_main() -> void:
	clear_page("ui-main")
	var mask := ColorRect.new()                      # the supplied scene keeps its baked controls
	mask.color = Color("030c12")                     # under an opaque live panel, as in Alpha 11
	mask.size = P(585, 941)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(mask)
	frame(P(28, 47), P(550, 840))
	picture("res://assets/ui/Ooze-Syndicate-Logo.svg", P(59, 94), P(520, 293))
	var start := nav_button("NEW GAME", P(80, 407), P(440, 98), show_factions, true)
	start.add_theme_font_size_override("font_size", int(round(37 * K)))
	nav_button("OPTIONS", P(80, 532), P(440, 82), show_options).add_theme_font_size_override("font_size", int(round(32 * K)))
	nav_button("FULLSCREEN" if OS.has_feature("web") else "QUIT", P(80, 639), P(440, 82), func():
		if OS.has_feature("web"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			get_tree().quit()).add_theme_font_size_override("font_size", int(round(32 * K)))
	var tut := nav_button("TUTORIAL", P(80, 745), P(212, 64), func(): pass)
	tut.disabled = true
	tut.tooltip_text = "Not in 2.0 yet"
	var online := nav_button("ONLINE", P(307, 745), P(213, 64), func(): pass)
	online.disabled = true
	online.tooltip_text = "Not in 2.0 yet"
	label_at("%s  ·  v%s" % [Rules.VERSION_NAME.to_upper(), Rules.VERSION], P(66, 843), 19, Color("839da9"))


func show_options() -> void:
	clear_page("city")
	header(0)
	label_at("OPTIONS", P(40, 107), 43)
	frame(P(35, 174), P(1000, 500))
	label_at("MATCH RULES", P(60, 195), 30)
	var bc := nav_button("BRIDGE COMBAT: %s" % ("ON  -  Alpha 12: hordes fight wherever they meet" if Rules.bridge_combat else "OFF  -  Alpha 11: hordes pass each other, fights only at nodes"),
			P(60, 250), P(950, 70), func():
		Rules.bridge_combat = not Rules.bridge_combat
		show_options())
	bc.add_theme_font_size_override("font_size", int(round(22 * K)))
	label_at("Not sure combat on bridges is fun? Try both. Also in the pause menu and the Debug panel.", P(60, 330), 18, Color("b8ced6"))
	label_at("PERFORMANCE", P(60, 395), 30)
	var det := nav_button("DETAIL: %s" % ("FULL" if not Rules.low_detail else "LOW  -  fewer patches, no shield rings"),
			P(60, 450), P(950, 70), func():
		Rules.low_detail = not Rules.low_detail
		show_options())
	det.add_theme_font_size_override("font_size", int(round(22 * K)))
	label_at("Low detail halves the horde and river patches - use it if the game makes your machine run hot.", P(60, 530), 18, Color("b8ced6"))
	nav_button("BACK", P(40, 866), P(230, 58), show_main)


func show_factions() -> void:
	clear_page(faction)
	header(1)
	var col := color()
	frame(P(28, 78), P(572, 636))
	portrait(faction, P(31, 81), P(566, 513))
	var name_label := label_at(NAMES[faction].split("\n")[0], P(50, 593), 52)
	name_label.size.x = 528 * K
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub_label := label_at(NAMES[faction].split("\n")[1], P(50, 651), 25, col)
	sub_label.size.x = 528 * K
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tagline := label_at(Rules.FACTION_TAGLINES[faction], P(50, 686), 16, Color("b8ced6"))
	tagline.size.x = 528 * K
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame(P(614, 134), P(469, 390))
	label_at("FACTION STATS", P(636, 150), 30)
	var rows := [["speed", "SPEED", "FASTER", "SLOWER"], ["health", "HEALTH", "TOUGHER", "FRAGILE"],
			["attack", "ATTACK", "STRONGER", "WEAKER"], ["production", "PRODUCTION SPEED", "FASTER", "SLOWER"],
			["garrison", "GARRISON STRENGTH", "STRONGER", "WEAKER"]]
	for i in range(rows.size()):
		var row: Array = rows[i]
		var y := 201 + i * 61
		frame(P(635, y), P(428, 57), "row")
		neon_icon(row[0], P(652, y + 10), P(34, 34), col)
		label_at(row[1], P(703, y + 17), 19)
		var value := Rules.stat(faction, row[0])
		var rating: String = row[2] if value > 1.001 else (row[3] if value < 0.999 else "BASELINE")
		label_at(rating, P(943, y + 17), 18, col if value > 1.001 else (Color("ffb12b") if value < 0.999 else Color("9cb2bf")))
		label_at(str(roundi(value * 100)) + "%", P(876, y + 17), 18, Color("9cb2bf"))
	frame(P(614, 534), P(469, 180))
	label_at("PERSISTENT TRAIT", P(636, 548), 22)
	neon_icon("efficient_routing", P(642, 602), P(62, 62), col)
	label_at(str(Rules.FACTION_TRAITS[faction][0]).to_upper(), P(719, 596), 24)
	label_at(Rules.FACTION_TRAITS[faction][1], P(719, 632), 18, Color("bed0da"))
	label_at("COMING SOON", P(924, 685), 15, Color("7795a4"))
	frame(P(1095, 134), P(550, 580))
	label_at("ABILITIES", P(1118, 152), 30)
	label_at("OOZE FACTORY: 3 SLOTS", P(1400, 161), 16, col)
	var names: Array = Rules.FACTION_NAMES[faction]
	var slots := [["ACTIVE SKILL", "One regular skill from the %s pool." % names[0], "attack"],
			["MAP SKILL", "A network ability: temporary deck, destroy a section, hack a relay.", "efficient_routing"],
			[str(Rules.FACTION_ULTIMATE[faction][0]).to_upper(), "Ultimate, charges over ~120 s: %s." % Rules.FACTION_ULTIMATE[faction][1], "speed"]]
	for i in range(3):
		var y := 200 + i * 165
		frame(P(1117, y), P(507, 150), "row")
		neon_icon(slots[i][2], P(1134, y + 40), P(64, 64), col)
		label_at(slots[i][0], P(1217, y + 18), 24)
		var desc := label_at(slots[i][1], P(1217, y + 60), 20, Color("c5d2da"))
		desc.custom_minimum_size = P(382, 70)
		desc.size = P(382, 70)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == 2:
			label_at("ULTIMATE / 120s", P(1500, y + 126), 13, Color("ffd15c"))
		else:
			label_at("COMING SOON", P(1500, y + 126), 13, Color("7795a4"))
	for i in range(5):
		faction_tab(FACTIONS[i], P(34 + i * 324, 745), P(312, 101))
	nav_button("BACK", P(40, 866), P(230, 58), show_main)
	nav_button("NEXT: BATTLEFIELD", P(1280, 866), P(352, 58), show_maps, true)


func faction_tab(f: String, pos: Vector2, dims: Vector2) -> void:
	nav_button("", pos, dims, func():
		faction = f
		main.SEAT_FACTIONS[main.HUMAN] = f
		show_factions())
	portrait(f, pos + P(6, 6), P(104, 89))
	var chosen := f == faction
	var fc: Color = Rules.FACTIONS[f][1]
	label_at("VIRIDIAN" if f == "bloom" else f.to_upper(), pos + P(122, 20), 24, fc if chosen else Color.WHITE)
	label_at(NAMES[f].split("\n")[1], pos + P(122, 54), 17, fc)
	content.add_child(neon_panel(pos, dims, fc, chosen, Color(0, 0, 0, 0)))
	if chosen:
		neon_icon("check", pos + P(279, 9), P(21, 21), fc)


func show_maps() -> void:
	clear_page("city")
	header(2)
	label_at("CHOOSE YOUR BATTLEFIELD", P(40, 107), 43)
	frame(P(35, 174), P(975, 641))
	var scroll := ScrollContainer.new()
	scroll.position = P(52, 193)
	scroll.size = P(940, 600)
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(16 * K))
	grid.add_theme_constant_override("v_separation", int(16 * K))
	scroll.add_child(grid)
	for entry in maps:
		var m: Dictionary = entry["data"]
		var mp: String = entry["path"]
		var code: String = m.get("code", "")
		var b := button("", func():
			map_path = mp
			show_maps(), 451 * K)
		b.custom_minimum_size = P(451, 272)
		grid.add_child(b)
		var tex := TextureRect.new()
		var thumb := "res://assets/map-thumbnails/%s.png" % code
		tex.texture = load(thumb) if ResourceLoader.exists(thumb) else load(mp.replace("maps/", "assets/maps/").replace(".json", ".svg"))
		tex.position = P(8, 8)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tex)
		tex.size = P(435, 211)
		tex.set_deferred("size", P(435, 211))
		var caption := text_label("%s  %s" % [code, str(m.get("name", "")).replace("*", "").to_upper()], 23)
		caption.position = P(17, 230)
		b.add_child(caption)
		var edge := neon_panel(Vector2.ZERO, P(451, 272), color(), mp == map_path, Color(0, 0, 0, 0))
		b.add_child(edge)
	frame(P(1030, 174), P(603, 641))
	map_preview(P(1046, 193), P(571, 414))
	var sel := _selected_map()
	label_at(str(sel.get("name", "")).replace("*", "").to_upper(), P(1052, 631), 31)
	label_at("CONQUEST    /    1v1    /    %d NODES%s" % [sel["nodes"].size(), _relay_kinds(sel).to_upper()], P(1053, 683), 23, color())
	label_at("%s\nLast Stand at %d:%02d - methods: %s" % [main.PROVES.get(sel.get("code", ""), ""),
			int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60, ", ".join(sel.get("lastStand", {}).get("methods", []))],
			P(1053, 736), 22, Color("abc1cd"))
	nav_button("BACK", P(40, 866), P(230, 58), show_factions)
	nav_button("NEXT: MATCH SETUP", P(1280, 866), P(352, 58), show_setup, true)


func _relay_kinds(m: Dictionary) -> String:
	var kinds := {}
	for n in m["nodes"]:
		if n.get("relay") != null:
			kinds[n["relay"]] = true
	return "    /    " + " + ".join(kinds.keys()) if not kinds.is_empty() else ""


func _selected_map() -> Dictionary:
	for entry in maps:
		if entry["path"] == map_path:
			return entry["data"]
	return maps[0]["data"]


func show_setup() -> void:
	clear_page("city")
	header(3)
	label_at("READY TO DEPLOY", P(40, 108), 51)
	frame(P(35, 188), P(982, 630))
	label_at(str(_selected_map().get("name", "")).replace("*", "").to_upper(), P(58, 207), 28)
	nav_button("CHANGE MAP", P(810, 206), P(184, 48), show_maps)
	map_preview(P(53, 277), P(946, 516))
	frame(P(1037, 188), P(595, 630))
	label_at("YOUR FACTION  ·  SEAT A", P(1059, 208), 20, Color("aac3cd"))
	summary_card(faction, P(1058, 240), P(552, 130), true)
	label_at("RIVAL  ·  SEAT B", P(1059, 389), 20, Color("aac3cd"))
	if rival != "random":
		summary_card(rival, P(1058, 422), P(552, 121), false)
	else:
		frame(P(1058, 422), P(552, 121), "row")
		label_at("RANDOM RIVAL", P(1080, 445), 30, Color("adc7d2"))
		label_at("picked when you deploy", P(1082, 495), 18, Color("adc7d2"))
	var choices := ["random"] + FACTIONS
	for i in range(choices.size()):
		var f: String = choices[i]
		var b := nav_button(("ANY" if f == "random" else ("VIRIDIAN" if f == "bloom" else f.to_upper())), P(1058 + i * 93, 556), P(88, 49), func():
			rival = f
			show_setup(), rival == f)
		b.add_theme_font_size_override("font_size", int(round(16 * K)))
	label_at("DIFFICULTY", P(1059, 620), 20, Color("aac3cd"))
	var levels: Array = Rules.AI_LEVELS.keys()
	for i in range(levels.size()):
		var lv: String = levels[i]
		var b := nav_button(lv.to_upper(), P(1058 + i * 186, 653), P(178, 59), func():
			ai_level = lv
			show_setup(), lv == ai_level)
		b.add_theme_font_size_override("font_size", int(round(18 * K)))
	nav_button("BRIDGE COMBAT / %s" % ("ON" if Rules.bridge_combat else "OFF"), P(1058, 746), P(552, 60), func():
		Rules.bridge_combat = not Rules.bridge_combat
		show_setup())
	label_at("ON = Alpha 12 (fight wherever they meet)   OFF = Alpha 11 (fight only at nodes)", P(1062, 812), 14, Color("7795a4"))
	nav_button("BACK", P(40, 866), P(230, 58), show_maps)
	nav_button("DEPLOY", P(1280, 866), P(352, 58), deploy, true)


func summary_card(f: String, pos: Vector2, dims: Vector2, change: bool) -> void:
	frame(pos, dims, "row")
	portrait(f, pos + P(6, 6), Vector2(146 * K, dims.y - 12 * K))
	label_at("VIRIDIAN" if f == "bloom" else f.to_upper(), pos + P(174, 23), 34, Rules.FACTIONS[f][1])
	label_at(NAMES[f].split("\n")[1], pos + P(177, 70), 20, Color("adc7d2"))
	if change:
		nav_button("CHANGE", pos + Vector2(dims.x - 148 * K, dims.y - 50 * K), P(132, 42), show_factions).add_theme_font_size_override("font_size", int(round(19 * K)))


func deploy() -> void:
	var r := rival
	if r == "random":
		var others := FACTIONS.filter(func(f): return f != faction)
		r = others[randi() % others.size()]
	main.start_match(map_path, faction, r, ai_level)
