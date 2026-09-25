class_name Menu
extends CanvasLayer
## Alpha 11's front menu, ported (Daniele: "why didn't we introduce the rest of the UX/UI, main menu,
## race selection?"): MAIN -> 01 FACTION (illustrated portrait left, stats + persistent trait in
## the middle, abilities right, illustrated faction tabs below - the supplied composition) ->
## 02 BATTLEFIELD (the starter seven with previews) -> 03 SETUP (your faction, rival faction,
## difficulty) -> DEPLOY. Built from Alpha 11's actual portrait art and icon kit (assets/art,
## assets/icons) and the shared panel/button recipe.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const W := 1280.0
const H := 720.0

var main: Node3D
var page: Control
var faction := "null"
var rival := "random"
var map_path := "res://maps/004-two-piers.json"
var ai_level := "Standard"
var maps: Array = []                 # [{path, data}]


func setup(m: Node3D) -> void:
	main = m
	faction = m.SEAT_FACTIONS[m.HUMAN]
	ai_level = m.ai_level
	map_path = m.map_path
	for mp in m.STARTER_MAPS:
		maps.append({"path": mp, "data": MapBuilder.load_map(mp)})
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.01, 0.014)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	show_main()


# ------------------------------------------------------------------ widgets
func clear() -> void:
	for c in page.get_children():
		c.queue_free()


func label_at(text: String, pos: Vector2, size: int = 20, color: Color = Color.WHITE, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		l.custom_minimum_size.x = width
		l.size.x = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(l)
	return l


func frame(pos: Vector2, dims: Vector2, color: Color = Color("276578")) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = dims
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Hud.panel_style(color))
	page.add_child(p)
	return p


func nav(text: String, pos: Vector2, dims: Vector2, call: Callable, primary := false, font := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = dims
	b.size = dims
	b.add_theme_font_override("font", UI_FONT)
	b.add_theme_font_size_override("font_size", font)
	var accent := Rules.FACTIONS[faction][1] as Color
	b.add_theme_stylebox_override("normal", Hud.panel_style(accent if primary else Color("276578")))
	b.add_theme_stylebox_override("hover", Hud.panel_style(accent))
	var pressed := Hud.panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", Hud.panel_style(Color("3a4650")))
	b.pressed.connect(func(): call.call_deferred())
	page.add_child(b)
	return b


func picture(tex: Texture2D, pos: Vector2, dims: Vector2, region := Rect2()) -> TextureRect:
	var p := TextureRect.new()
	if region.size != Vector2.ZERO:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(region.position * Vector2(tex.get_size()), region.size * Vector2(tex.get_size()))
		atlas.filter_clip = true
		p.texture = atlas
	else:
		p.texture = tex
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.position = pos
	p.size = dims
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(p)
	return p


func portrait(f: String, pos: Vector2, dims: Vector2) -> TextureRect:
	## Alpha 11's cinematic illustrated portraits (assets/art), same atlas regions as its menu.
	if f == "vex":
		return picture(load("res://assets/art/ui-faction.png"), pos, dims, Rect2(0.02, 0.092, 0.333, 0.54))
	return picture(load("res://assets/art/%s.png" % f), pos, dims, Rect2(0.43, 0.035, 0.54, 0.86))


func icon(name: String, pos: Vector2, dims: Vector2, color: Color) -> void:
	var tex: Texture2D = load("res://assets/icons/%s.png" % name)
	var glow := picture(tex, pos - Vector2(4, 4), dims + Vector2(8, 8))
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.modulate = Color(color, 0.25)
	var i := picture(tex, pos, dims)
	i.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	i.modulate = color


func header(step: int) -> void:
	var logo := picture(load("res://assets/ui/Ooze-Syndicate-Logo.svg"), Vector2(24, 10), Vector2(150, 44))
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var steps := ["01  FACTION", "02  BATTLEFIELD", "03  SETUP"]
	var accent := Rules.FACTIONS[faction][1] as Color
	for i in range(3):
		var on := i + 1 == step
		var p := frame(Vector2(430 + i * 150, 14), Vector2(144, 36), accent if on else Color("276578"))
		if on:
			(p.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(accent, 0.25)
		label_at(steps[i], Vector2(444 + i * 150, 20), 17, Color.WHITE if on else Color("839da9"))
	label_at("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], Vector2(1120, 22), 15, Color("839da9"))


# ------------------------------------------------------------------ pages
func show_main() -> void:
	clear()
	frame(Vector2(340, 70), Vector2(600, 580))
	var logo := picture(load("res://assets/ui/Ooze-Syndicate-Logo.svg"), Vector2(380, 95), Vector2(520, 200))
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	label_at("OOZE SYNDICATE 2.0  ·  %s" % Rules.VERSION_NAME.to_upper(), Vector2(380, 300), 26, Color("b8ced6"), 520).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav("NEW GAME", Vector2(420, 350), Vector2(440, 74), show_factions, true, 32)
	nav("QUICK MATCH", Vector2(420, 438), Vector2(440, 56), func():
		rival = "random"
		deploy(), false, 24)
	nav("FULLSCREEN" if OS.has_feature("web") else "QUIT", Vector2(420, 508), Vector2(440, 56), func():
		if OS.has_feature("web"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			get_tree().quit(), false, 24)
	label_at("v%s  ·  reload twice after a new publish (PWA cache)" % Rules.VERSION, Vector2(380, 600), 15, Color("839da9"), 520).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_factions() -> void:
	clear()
	header(1)
	var color := Rules.FACTIONS[faction][1] as Color
	var names: Array = Rules.FACTION_NAMES[faction]
	# portrait, left
	frame(Vector2(20, 62), Vector2(392, 480))
	portrait(faction, Vector2(24, 66), Vector2(384, 340))
	label_at(names[0], Vector2(24, 410), 46, Color.WHITE, 384).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_at(names[1], Vector2(24, 462), 22, color, 384).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_at(Rules.FACTION_TAGLINES[faction], Vector2(24, 494), 15, Color("b8ced6"), 384).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# stats + trait, middle
	frame(Vector2(428, 62), Vector2(400, 300))
	label_at("FACTION STATS", Vector2(446, 72), 24)
	var rows := [["speed", "SPEED", "FASTER", "SLOWER"], ["health", "HEALTH", "TOUGHER", "FRAGILE"],
			["attack", "ATTACK", "STRONGER", "WEAKER"], ["production", "PRODUCTION SPEED", "FASTER", "SLOWER"],
			["garrison", "GARRISON STRENGTH", "STRONGER", "WEAKER"]]
	for i in range(rows.size()):
		var row: Array = rows[i]
		var y := 108 + i * 48
		frame(Vector2(444, y), Vector2(368, 42), Color("1e3d4a"))
		icon(row[0], Vector2(454, y + 8), Vector2(26, 26), color)
		label_at(row[1], Vector2(492, y + 10), 17)
		var v := Rules.stat(faction, row[0])
		var rating: String = row[2] if v > 1.001 else (row[3] if v < 0.999 else "BASELINE")
		var rc := color if v > 1.001 else (Color("ffb12b") if v < 0.999 else Color("9cb2bf"))
		label_at("%d%%" % roundi(v * 100.0), Vector2(680, y + 10), 16, Color("9cb2bf"))
		label_at(rating, Vector2(730, y + 10), 16, rc)
	frame(Vector2(428, 372), Vector2(400, 170))
	label_at("PERSISTENT TRAIT", Vector2(446, 382), 20)
	icon("efficient_routing", Vector2(450, 424), Vector2(54, 54), color)
	label_at(str(Rules.FACTION_TRAITS[faction][0]).to_upper(), Vector2(518, 420), 22)
	label_at(Rules.FACTION_TRAITS[faction][1], Vector2(518, 452), 16, Color("bed0da"), 290)
	label_at("COMING SOON", Vector2(700, 514), 13, Color("7795a4"))
	# abilities, right (the Ooze Factory's three slots - GAME-RULES sec9; pools pending approval)
	frame(Vector2(844, 62), Vector2(416, 480))
	label_at("ABILITIES", Vector2(862, 72), 24)
	label_at("OOZE FACTORY: 3 SLOTS", Vector2(1080, 80), 14, color)
	var slots := [["ACTIVE SKILL", "One regular skill from the %s pool." % names[0]],
			["MAP SKILL", "A network ability: temporary deck, destroy a section, hack a relay..."],
			["ULTIMATE - %s" % str(Rules.FACTION_ULTIMATE[faction][0]).to_upper(), "Charges over ~120 s; %s." % Rules.FACTION_ULTIMATE[faction][1]]]
	for i in range(3):
		var y := 112 + i * 132
		frame(Vector2(860, y), Vector2(384, 118), Color("1e3d4a"))
		icon(["attack", "efficient_routing", "speed"][i], Vector2(874, y + 30), Vector2(54, 54), color)
		label_at(slots[i][0], Vector2(944, y + 14), 21)
		label_at(slots[i][1], Vector2(944, y + 46), 15, Color("c5d2da"), 290)
		label_at("ULTIMATE / 120 s" if i == 2 else "COMING SOON", Vector2(1120, y + 96), 12, Color("ffd15c") if i == 2 else Color("7795a4"))
	# illustrated faction tabs
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var pos := Vector2(20 + i * 250, 556)
		var chosen := f == faction
		var fc := Rules.FACTIONS[f][1] as Color
		var b := nav("", pos, Vector2(240, 82), func():
			faction = f
			main.SEAT_FACTIONS[main.HUMAN] = f
			show_factions(), chosen)
		portrait(f, pos + Vector2(5, 5), Vector2(80, 72))
		label_at(Rules.FACTION_NAMES[f][0], pos + Vector2(96, 14), 22, fc if chosen else Color.WHITE)
		label_at(Rules.FACTION_NAMES[f][1], pos + Vector2(96, 44), 14, fc)
		if chosen:
			icon("check", pos + Vector2(210, 8), Vector2(20, 20), fc)
	nav("BACK", Vector2(20, 654), Vector2(180, 48), show_main)
	nav("NEXT: BATTLEFIELD", Vector2(940, 654), Vector2(320, 48), show_maps, true)


func show_maps() -> void:
	clear()
	header(2)
	var color := Rules.FACTIONS[faction][1] as Color
	label_at("CHOOSE YOUR BATTLEFIELD", Vector2(24, 62), 30)
	frame(Vector2(20, 104), Vector2(760, 540))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 114)
	scroll.size = Vector2(740, 520)
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for entry in maps:
		var m: Dictionary = entry["data"]
		var mp: String = entry["path"]
		var chosen: bool = mp == map_path
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 118)
		b.add_theme_stylebox_override("normal", Hud.panel_style(color if chosen else Color("276578")))
		b.add_theme_stylebox_override("hover", Hud.panel_style(color))
		b.add_theme_stylebox_override("pressed", Hud.panel_style(color))
		b.pressed.connect(func():
			map_path = mp
			show_maps())
		grid.add_child(b)
		var tex := TextureRect.new()
		tex.texture = load(mp.replace("maps/", "assets/maps/").replace(".json", ".svg"))
		tex.position = Vector2(8, 8)
		tex.custom_minimum_size = Vector2(100, 100)
		tex.size = Vector2(100, 100)
		b.clip_contents = true
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tex)
		var cap := Label.new()
		cap.add_theme_font_override("font", UI_FONT)
		cap.add_theme_font_size_override("font_size", 20)
		cap.text = "%s  %s" % [m.get("code", "?"), str(m.get("name", "")).replace("*", "")]
		cap.position = Vector2(126, 14)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		var sub := Label.new()
		sub.add_theme_font_override("font", UI_FONT)
		sub.add_theme_font_size_override("font_size", 14)
		sub.add_theme_color_override("font_color", Color("abc1cd"))
		sub.text = "%d nodes%s\n%s" % [m["nodes"].size(), _relay_kinds(m), main.PROVES.get(m.get("code", ""), "")]
		sub.position = Vector2(126, 46)
		sub.custom_minimum_size.x = 224
		sub.size.x = 224
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sub)
	# preview, right
	var sel := _selected_map()
	frame(Vector2(796, 104), Vector2(464, 540))
	var prev := picture(load(map_path.replace("maps/", "assets/maps/").replace(".json", ".svg")), Vector2(836, 118), Vector2(384, 300))
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	label_at(str(sel.get("name", "")).replace("*", "").to_upper(), Vector2(812, 430), 28)
	label_at("1v1  ·  %d NODES%s" % [sel["nodes"].size(), _relay_kinds(sel).to_upper()], Vector2(812, 470), 18, color)
	label_at(main.PROVES.get(sel.get("code", ""), ""), Vector2(812, 500), 16, Color("abc1cd"), 430)
	var ls: Dictionary = sel.get("lastStand", {})
	label_at("LAST STAND at %d:%02d  ·  methods: %s" % [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60, ", ".join(ls.get("methods", []))],
			Vector2(812, 560), 15, Color("ffb0b0"), 430)
	nav("BACK", Vector2(20, 654), Vector2(180, 48), show_factions)
	nav("NEXT: MATCH SETUP", Vector2(940, 654), Vector2(320, 48), show_setup, true)


func _relay_kinds(m: Dictionary) -> String:
	var kinds := {}
	for n in m["nodes"]:
		if n.get("relay") != null:
			kinds[n["relay"]] = true
	return "  ·  " + "/".join(kinds.keys()) if not kinds.is_empty() else ""


func _selected_map() -> Dictionary:
	for entry in maps:
		if entry["path"] == map_path:
			return entry["data"]
	return maps[0]["data"]


func show_setup() -> void:
	clear()
	header(3)
	var color := Rules.FACTIONS[faction][1] as Color
	label_at("READY TO DEPLOY", Vector2(24, 62), 30)
	var sel := _selected_map()
	frame(Vector2(20, 104), Vector2(600, 540))
	label_at(str(sel.get("name", "")).replace("*", "").to_upper(), Vector2(40, 118), 24)
	nav("CHANGE MAP", Vector2(450, 114), Vector2(150, 40), show_maps, false, 16)
	var prev := picture(load(map_path.replace("maps/", "assets/maps/").replace(".json", ".svg")), Vector2(60, 160), Vector2(520, 460))
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame(Vector2(636, 104), Vector2(624, 540))
	label_at("YOUR FACTION  ·  SEAT A  (cyan)", Vector2(656, 116), 16, Color("aac3cd"))
	_summary_card(faction, Vector2(656, 140), Vector2(584, 96), true)
	label_at("RIVAL  ·  SEAT B  (green)", Vector2(656, 250), 16, Color("aac3cd"))
	var choices := ["random"] + FACTIONS
	for i in range(choices.size()):
		var f: String = choices[i]
		var on := f == rival
		var fc: Color = Rules.FACTIONS[f][1] if f != "random" else Color("00ddf2")
		var b := nav(f.to_upper(), Vector2(656 + i * 98, 278), Vector2(92, 44), func():
			rival = f
			show_setup(), on, 15)
		if on:
			b.add_theme_stylebox_override("normal", Hud.panel_style(fc))
	var rf := rival if rival != "random" else "?"
	if rf != "?":
		_summary_card(rf, Vector2(656, 332), Vector2(584, 84), false)
	else:
		frame(Vector2(656, 332), Vector2(584, 84), Color("1e3d4a"))
		label_at("RANDOM RIVAL - picked when you deploy", Vector2(676, 360), 20, Color("adc7d2"))
	label_at("DIFFICULTY", Vector2(656, 430), 16, Color("aac3cd"))
	var levels: Array = Rules.AI_LEVELS.keys()
	for i in range(levels.size()):
		var lv: String = levels[i]
		var b := nav(lv.to_upper(), Vector2(656 + i * 150, 458), Vector2(140, 48), func():
			ai_level = lv
			show_setup(), lv == ai_level, 17)
	label_at("Same costs, same slots, no cheats - only how often it thinks, its attack margin and whether it uses relays as weapons.", Vector2(656, 514), 13, Color("aac3cd"), 584)
	nav("BRIDGE COMBAT: %s" % ("ON  (Alpha 12 - hordes fight wherever they meet)" if Rules.bridge_combat else "OFF  (Alpha 11 - they pass, fight only at nodes)"),
			Vector2(656, 556), Vector2(584, 44), func():
		Rules.bridge_combat = not Rules.bridge_combat
		show_setup(), false, 15)
	label_at("Ownership colour = seat (A cyan, B green); faction = shape, stats and accent (GAME-RULES sec2).", Vector2(656, 610), 12, Color("7795a4"), 584)
	nav("BACK", Vector2(20, 654), Vector2(180, 48), show_maps)
	nav("DEPLOY", Vector2(940, 654), Vector2(320, 48), deploy, true, 24)


func _summary_card(f: String, pos: Vector2, dims: Vector2, change: bool) -> void:
	frame(pos, dims, Color("1e3d4a"))
	portrait(f, pos + Vector2(6, 6), Vector2(120, dims.y - 12))
	label_at(Rules.FACTION_NAMES[f][0], pos + Vector2(140, 14), 28, Rules.FACTIONS[f][1])
	label_at(Rules.FACTION_NAMES[f][1], pos + Vector2(142, 50), 16, Color("adc7d2"))
	if change:
		nav("CHANGE", pos + Vector2(dims.x - 120, dims.y - 46), Vector2(108, 36), show_factions, false, 15)


func deploy() -> void:
	var r := rival
	if r == "random":
		var others := FACTIONS.filter(func(f): return f != faction)
		r = others[randi() % others.size()]
	main.start_match(map_path, faction, r, ai_level)
