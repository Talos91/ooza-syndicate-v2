class_name Menu
extends CanvasLayer
## Alpha 11's front menu, ported page for page (Daniele: "I want the damn menu as for Alpha 11"):
## the same backdrop art (assets/art/ui-main.png), neon-cut frames (neon_panel.gd), ui-kit buttons
## per faction (ui_skin.gd), stepper strip, wordmark, Russo One headings, and the same coordinates
## - Alpha 11 laid out on a 1672x941 canvas, ours is 1280x720, so everything is scaled by K.
## MAIN -> 01 FACTION (portrait / stats + trait / abilities / faction tabs) -> 02 BATTLEFIELD
## (3D thumbnails + preview) -> 03 SETUP (players, your colour, your faction, rival, difficulty,
## SIEGE/BRAWL, Last Stand) -> DEPLOY. OPTIONS holds the match switches (SIEGE/BRAWL, Last Stand,
## enemy counts, detail). ONLINE -> CREATE ROOM / JOIN ROOM ->
## the room lobby (players, teams, faction, colour, map, PLAYERS, SIEGE/BRAWL, Last Stand) -> DEPLOY by
## the host (Net, peer-to-peer). TUTORIAL is not in 2.0 yet.
## ARMIES (0.18.7, SKILLS 2.0): the army presets - per faction its fixed ultimate plus 1 active and 1 map skill
## picked from the shared pools (ArmyPresets, saved on the device). 01 FACTION shows the preset; 03 SETUP and
## the lobby carry ABILITIES ON / OFF; DEPLOY and the room send your preset as the match loadout.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const K := 1280.0 / 1672.0
const NAMES := {"vex": "VEX\nBIOENGINEERS", "null": "NULL\nCARTEL", "bloom": "VIRIDIAN\nBLOOM", "ember": "EMBER\nMAW", "solar": "SOLAR\nSHELLS"}

var main: Node3D
var content: Control
var faction := "null"
var rival := "random"
var map_path := ""                                # setup() takes main's, or the pool's first map
var ai_level := "Standard"
var mode := "1v1"
var colour := "A"
const MODE_NAMES := {"1v1": "1 V 1", "2v2": "2 V 2", "3v3": "3 V 3", "2v2v2": "2V2V2", "FFA3": "FFA 3", "FFA4": "FFA 4", "FFA5": "FFA 5"}
const COLOUR_NAMES := {"A": "CYAN", "B": "GREEN", "C": "PURPLE", "D": "RED", "E": "GOLD", "F": "ROSE", "faction": "FACTION"}
var maps: Array = []
var _is_main := false
var _backdrop: TextureRect
var _page := ""                                  # "online" / "lobby": rebuilt when the room changes
var _map_scroll := 0
# map filters on 02 BATTLEFIELD (Daniele, 0.18.6: "add in game filters for maps like 1v1 2v2 ffa etc"): players
# (a mode the map offers) and type (the map's group); static, so they survive a trip through the match
static var map_filter_mode := "all"
static var map_filter_type := "all"
const MAP_TYPES := ["all", "brawl", "siege", "core", "alpha 11", "training"]
const MAP_TYPE_NAMES := {"all": "ALL", "brawl": "BRAWL", "siege": "SIEGE", "core": "CORE", "alpha 11": "ALPHA 11", "training": "TRAINING"}
var _chat_btn: Button
var _chat_t := 0.0
var _move_pick := -1                               # host, team modes: the player picked to MOVE to a team
const HUE_NAMES := ["red", "green", "blue", "gold", "purple", "cyan", "rose", "orange"]   # Rules.HUES, lobby order
var _army := ""                                    # ARMIES: the faction whose preset is open
var _army_back := Callable()                       # ARMIES: the page it was opened from


func setup(m: Node3D) -> void:
	main = m
	ArmyPresets.load_all()                            # the saved army presets (none, or no storage: the defaults)
	_backdrop = TextureRect.new()                     # full-screen art behind the scaled page
	var art: Texture2D = load("res://assets/art/ui-main.png")
	var clean := AtlasTexture.new()                   # the art's right part: its left edge has Alpha 11's
	clean.atlas = art                                 # buttons baked in, which peeked out on wide screens
	clean.region = Rect2(Vector2(art.get_size()) * Vector2(0.36, 0.0), Vector2(art.get_size()) * Vector2(0.64, 1.0))
	_backdrop.texture = clean
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.modulate = Color(0.55, 0.6, 0.65)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	get_viewport().size_changed.connect(_fit)
	faction = m.SEAT_FACTIONS[m.HUMAN]
	if Net.in_room() or Net.status != "":             # back from a room: keep the faction you played
		faction = Net.preferred_faction
	ai_level = m.ai_level
	map_path = m.map_path
	mode = m.mode
	colour = m.color_choice
	for mp in MapPool.all():
		maps.append({"path": mp, "data": MapBuilder.load_map(mp)})
	if not maps.any(func(x): return x["path"] == map_path):
		map_path = maps[0]["path"]                     # the pool is maps4/: the old roster is archive
	Net.lobby_changed.connect(_on_net_changed)
	show_main()


static func P(x: float, y: float) -> Vector2:
	return Vector2(x, y) * K


func color() -> Color:
	return Color("18dae8") if _is_main else Rules.FACTIONS[skin()][1]


func skin() -> String:
	## The faction the page is dressed in: yours, or on ARMIES the faction whose preset is open.
	return _army if _page == "armies" and _army != "" else faction


# ------------------------------------------------------------------ Alpha 11's widgets
func clear_page(art: String) -> void:
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	add_child(content)
	_fit()
	_is_main = art == "ui-main"
	_page = ""
	# one background only: the full-screen backdrop (Alpha 14 playtest: "background on top of a
	# background" - the page used to draw its own copy of the art, misaligned on taller screens)
	if _backdrop:
		_backdrop.modulate = Color(0.95, 0.95, 0.95) if _is_main else Color(0.62, 0.68, 0.74)


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
	UiSkin.button(b, skin())
	return b


func nav_button(text: String, pos: Vector2, dims: Vector2, call: Callable, primary := false) -> Button:
	var b := button(text, call, dims.x)
	b.position = pos
	b.custom_minimum_size = dims
	b.size = dims
	b.add_theme_font_size_override("font_size", int(round(25 * K)))
	UiSkin.button(b, "vex" if _is_main else skin(), primary)
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


func skill_icon(id: String, pos: Vector2, dims: Vector2, col: Color, parent: Control = null) -> TextureRect:
	## A skill's line icon (assets/ui/skills, ArmyPresets.icon) in a colour, with the neon glow of neon_icon.
	var tex := ArmyPresets.icon(id)
	if tex == null:
		return null
	var host := parent if parent != null else content
	var out: TextureRect
	for spread in [6.0, 0.0]:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = pos - Vector2.ONE * spread / 2.0
		r.modulate = Color(col, 0.25) if spread > 0.0 else col
		host.add_child(r)
		r.size = dims + Vector2.ONE * spread
		r.set_deferred("size", dims + Vector2.ONE * spread)
		out = r
	return out


func loadout_icons(f: String, lo: Dictionary, pos: Vector2, icon: float, gap: float, has_relays := true) -> void:
	## Three small icons - active, map, ultimate - of a loadout (the map skill a no-relay map swaps in, dimmed
	## gold, when the preset's is a relay skill).
	var eff := ArmyPresets.effective(f, lo, has_relays)
	var fc: Color = Rules.FACTIONS[f][1]
	var ids := [eff["active"], eff["map"], eff["ultimate"]]
	for i in range(3):
		var p := pos + Vector2(i * (icon + gap), 0)
		content.add_child(neon_panel(p - Vector2.ONE * 3.0 * K, Vector2.ONE * (icon + 6.0 * K), fc if i < 2 else Color("ffd15c"), false, Color("020a10d8")))
		skill_icon(ids[i], p + Vector2.ONE * icon * 0.1, Vector2.ONE * icon * 0.8, Color("ffd15c") if (i == 1 and eff["swapped"] != "") else fc)


func header(step: int) -> void:
	picture("res://assets/ui/Ooze-Syndicate-Wordmark.svg", P(35, 10), P(172, 64))
	if step > 0:
		picture("res://assets/ui-kit/Navigation/stepper-%d.png" % step, P(565, 20), P(620, 59))
	label_at("v%s  %s" % [Rules.VERSION, Rules.VERSION_NAME], P(1480, 34), 16, Color("839da9"))


func map_preview(pos: Vector2, dims: Vector2) -> void:
	var code: String = _selected_map().get("code", "")
	var p := picture(MapPool.thumb(code), pos, dims)
	if p != null:
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED     # the whole map, letterboxed, never cropped


# ------------------------------------------------------------------ pages
func show_main() -> void:
	clear_page("ui-main")
	var mask := ColorRect.new()                      # the dark left column, full screen height
	mask.color = Color("030c12")
	mask.position = Vector2(-3000, -3000)
	mask.size = Vector2(3000, 6000) + Vector2(P(585, 0).x, 0)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(mask)
	frame(P(28, 47), P(550, 840))
	picture("res://assets/ui/Ooze-Syndicate-Logo.svg", P(59, 94), P(520, 293))
	var start := nav_button("NEW GAME", P(80, 407), P(440, 98), show_factions, true)
	start.add_theme_font_size_override("font_size", int(round(37 * K)))
	# ARMIES (0.18.7, Daniele: "its own new menu item where you select what skill each of your factions will
	# use"): its own row under NEW GAME; OPTIONS and FULLSCREEN / QUIT share the next one
	nav_button("ARMIES", P(80, 532), P(440, 82), func(): show_armies(faction, show_main)).add_theme_font_size_override("font_size", int(round(32 * K)))
	nav_button("OPTIONS", P(80, 639), P(212, 82), show_options).add_theme_font_size_override("font_size", int(round(28 * K)))
	nav_button("FULLSCREEN" if OS.has_feature("web") else "QUIT", P(307, 639), P(213, 82), func():
		if OS.has_feature("web"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			get_tree().quit()).add_theme_font_size_override("font_size", int(round(28 * K)))
	var tut := nav_button("TUTORIAL", P(80, 745), P(212, 64), func(): pass)
	tut.disabled = true
	tut.tooltip_text = "Not in 2.0 yet"
	nav_button("ONLINE", P(307, 745), P(213, 64), show_online)
	label_at("%s  ·  v%s" % [Rules.VERSION_NAME.to_upper(), Rules.VERSION], P(66, 843), 19, Color("839da9"))


func show_options() -> void:
	clear_page("city")
	header(0)
	label_at("OPTIONS", P(40, 107), 43)
	frame(P(35, 174), P(1000, 600))
	label_at("MATCH RULES", P(60, 195), 30)
	var bc := nav_button("MODE: %s" % ("SIEGE  -  hordes fight wherever they meet, tug-of-war fronts" if Rules.bridge_combat else "BRAWL  -  Alpha 11: units pass each other, fights only at nodes"),
			P(60, 250), P(950, 70), func():
		Rules.bridge_combat = not Rules.bridge_combat
		show_options())
	bc.add_theme_font_size_override("font_size", int(round(22 * K)))
	label_at("Two modes that play differently: SIEGE and BRAWL. Also in the pause menu and the Debug panel.", P(60, 330), 18, Color("b8ced6"))
	var lsb := nav_button("LAST STAND: %s" % (("ON  -  the map collapses from %d:%02d" % [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60])
			if Rules.last_stand else ("OFF  -  no collapse; the %d:%02d safety net still ends a stalled match" % [int(Rules.MATCH_HARD_END) / 60, int(Rules.MATCH_HARD_END) % 60])),
			P(60, 362), P(950, 50), func():
		Rules.last_stand = not Rules.last_stand
		show_options())
	lsb.add_theme_font_size_override("font_size", int(round(20 * K)))
	var hec := nav_button("ENEMY COUNTS: %s" % ("HIDDEN  -  no unit numbers on enemy nodes, in either mode" if Rules.hide_enemy_counts else "SHOWN IN BRAWL  -  as Alpha 11 (SIEGE always hides them)"),
			P(60, 422), P(950, 44), func():
		Rules.hide_enemy_counts = not Rules.hide_enemy_counts
		show_options())
	hec.add_theme_font_size_override("font_size", int(round(19 * K)))
	label_at("PERFORMANCE", P(60, 482), 30)
	var det := nav_button("DETAIL: %s" % ("FULL" if not Rules.low_detail else "LOW  -  fewer river patches and vat residents"),
			P(60, 526), P(950, 60), func():
		Rules.low_detail = not Rules.low_detail
		show_options())
	det.add_theme_font_size_override("font_size", int(round(22 * K)))
	label_at("Low detail trims the river patches and vat residents - use it if the game makes your machine run hot.", P(60, 596), 18, Color("b8ced6"))
	var ter := nav_button("TERRITORY: %s" % ("GOO  -  player-colour goo on owned ground, units in race colour (BRAWL)" if Rules.goo_territory else "NEON  -  owner-colour neon on decks and platform rims"),
			P(60, 632), P(950, 56), func():
		Rules.goo_territory = not Rules.goo_territory
		show_options())
	ter.add_theme_font_size_override("font_size", int(round(19 * K)))
	var dbg := nav_button("DEBUG TOOLS: %s" % ("ON  -  the Debug button and live sliders in matches" if Rules.debug_tools else "OFF"),
			P(60, 698), P(950, 50), func():
		Rules.debug_tools = not Rules.debug_tools
		show_options())
	dbg.add_theme_font_size_override("font_size", int(round(20 * K)))
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
	# SKILLS 2.0: the faction's army preset (ARMIES) - each row opens ARMIES on this faction
	frame(P(1095, 134), P(550, 580))
	label_at("ABILITIES", P(1118, 152), 30)
	var edit := nav_button("EDIT IN ARMIES  ›", P(1392, 144), P(232, 50), func(): show_armies(faction, show_factions))
	edit.add_theme_font_size_override("font_size", int(round(19 * K)))
	var lo := ArmyPresets.loadout_for(faction)
	var ids := [lo["active"], lo["map"], Rules.FACTION_ULTIMATE_ID[faction]]
	var tags := ["ACTIVE SKILL  ·  ARMY PRESET", "MAP SKILL  ·  ARMY PRESET", "ULTIMATE  ·  %s ONLY" % str(Rules.FACTION_NAMES[faction][0])]
	for i in range(3):
		var y := 200 + i * 165
		var id: String = ids[i]
		nav_button("", P(1117, y), P(507, 150), func(): show_armies(faction, show_factions))
		content.add_child(neon_panel(P(1117, y), P(507, 150), col, false, Color("020a10e8")))
		skill_icon(id, P(1136, y + 33), P(84, 84), col)
		label_at(tags[i], P(1238, y + 14), 16, Color(col, 0.9))
		label_at(ArmyPresets.skill_name(id).to_upper(), P(1238, y + 36), 28)
		var desc := label_at(ArmyPresets.line(id), P(1238, y + 80), 19, Color("c5d2da"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wrap first, then fix the width
		desc.custom_minimum_size = Vector2(368 * K, 0)
		desc.size = Vector2(368 * K, 0)
		label_at(ArmyPresets.cd_text(id) + ("" if i == 2 else " CD"), P(1500, y + 16), 15, Color("ffd15c") if i == 2 else Color("9cb2bf"))
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


# ------------------------------------------------------------------ ARMIES (army presets, SKILLS 2.0)
func show_armies(f: String = "", back: Callable = Callable()) -> void:
	## Daniele (0.18.7): "time to add armies presets and skills (its own new menu item where you select what
	## skill each of your factions will use, follow the skill file from faction ultimates and ability pool)".
	## Left: the five factions (their preset's three icons). Right: the faction's ultimate (fixed), then the
	## five active skills and the five map skills - tap a card to equip it. Saved on the device at once.
	if f != "":
		_army = f
	if _army == "":
		_army = faction
	if back.is_valid():
		_army_back = back
	if not _army_back.is_valid():
		_army_back = show_main
	clear_page("city")
	_page = "armies"
	header(0)
	var fc := color()
	var lo := ArmyPresets.loadout_for(_army)
	label_at("ARMIES", P(40, 104), 43)
	label_at("ARMY PRESETS  ·  one active skill and one map skill per faction; the ultimate comes with the faction",
			P(262, 122), 20, Color("abc1cd"))
	# the factions, each with its preset's three icons
	for i in range(FACTIONS.size()):
		var tf: String = FACTIONS[i]
		var pos := P(35, 174 + i * 128)
		var dims := P(362, 118)
		var tc: Color = Rules.FACTIONS[tf][1]
		nav_button("", pos, dims, func(): show_armies(tf))
		content.add_child(neon_panel(pos, dims, tc, tf == _army, Color("020a10e0") if tf != _army else Color("08202ae8")))
		portrait(tf, pos + P(6, 6), P(100, 106))
		label_at("VIRIDIAN" if tf == "bloom" else tf.to_upper(), pos + P(120, 10), 26, tc if tf == _army else Color.WHITE)
		loadout_icons(tf, ArmyPresets.loadout_for(tf), pos + P(124, 56), 46.0 * K, 10.0 * K)
		if tf == faction:
			label_at("YOU", pos + P(306, 16), 15, Color("ffd15c"))
	# the ultimate: fixed by the faction
	var ult: String = Rules.FACTION_ULTIMATE_ID[_army]
	var up := P(415, 174)
	content.add_child(neon_panel(up, P(1222, 140), Color("ffd15c"), true, Color("0a1216ec")))
	skill_icon(ult, up + P(22, 20), P(100, 100), Color("ffd15c"))
	label_at("ULTIMATE  ·  %s ONLY  ·  FIXED" % str(Rules.FACTION_NAMES[_army][0]), up + P(146, 14), 18, Color("ffd15c"))
	label_at(ArmyPresets.skill_name(ult).to_upper(), up + P(146, 36), 34)
	var ud := label_at(str(Rules.SKILLS[ult]["desc"]), up + P(146, 84), 19, Color("c5d2da"))
	ud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ud.custom_minimum_size = Vector2(1050 * K, 0)
	ud.size = Vector2(1050 * K, 0)
	label_at("CHARGES IN ~%d s (AT LEAST %d s); ENEMY KILLS SPEED IT UP" % [int(Rules.ULT_CHARGE_TIME), int(Rules.ULT_MIN_TIME)], up + P(700, 16), 15, Color("9cb2bf"))
	# the two pools
	var rows := [["active", "ACTIVE SKILL  ·  PICK ONE", "combat skills, every map", Rules.ACTIVE_SKILLS, 326],
			["map", "MAP SKILL  ·  PICK ONE", "network skills; relay skills need a map with relays", Rules.MAP_SKILLS, 576]]
	for row in rows:
		var slot: String = row[0]
		var y: int = row[4]
		label_at(row[1], P(415, y), 24)
		label_at(row[2], P(790, y + 6), 17, Color("8fb3c2"))
		var pool: Array = row[3]
		for i in range(pool.size()):
			_skill_card(pool[i], slot, lo[slot] == pool[i], P(415 + i * 247, y + 32), P(234, 206), fc)
	# foot: back, reset, the save state
	nav_button("BACK", P(40, 866), P(230, 58), func(): _leave_armies())
	var rs := nav_button("RESET %s TO DEFAULT" % ("VIRIDIAN" if _army == "bloom" else _army.to_upper()), P(290, 866), P(420, 58), func():
		ArmyPresets.reset(_army)
		_preset_changed()
		show_armies())
	rs.add_theme_font_size_override("font_size", int(round(20 * K)))
	rs.disabled = ArmyPresets.is_default(_army)
	var note := "Saved on this device" if ArmyPresets.saved else "This browser keeps no storage: your picks last until the page closes"
	label_at(note, P(740, 884), 18, Color("7795a4") if ArmyPresets.saved else Color("ffd15c"))


func _skill_card(id: String, slot: String, chosen: bool, pos: Vector2, dims: Vector2, fc: Color) -> void:
	## One pool skill as a tap target: icon, cooldown, name, one line in shown numbers (the full sentence as
	## its tooltip); the equipped one glows with a check.
	var sk: Dictionary = Rules.SKILLS[id]
	var b := nav_button("", pos, dims, func():
		ArmyPresets.set_pick(_army, slot, id)
		_preset_changed()
		show_armies())
	b.tooltip_text = str(sk["desc"])
	content.add_child(neon_panel(pos, dims, fc, chosen, Color("08202aea") if chosen else Color("020a10e4")))
	skill_icon(id, pos + P(16, 16), P(78, 78), fc if chosen else Color("c9dbe3"))
	label_at("%d s CD" % int(sk["cd"]), pos + P(106, 18), 20, Color("9cb2bf"))
	if chosen:
		label_at("EQUIPPED", pos + P(106, 46), 17, fc)
		neon_icon("check", pos + P(dims.x / K - 34, 12), P(20, 20), fc)
	if sk.get("needs_relays", false):
		label_at("NEEDS RELAYS", pos + P(106, 70), 15, Color("ffb12b"))
	label_at(ArmyPresets.skill_name(id).to_upper(), pos + P(16, 104), 24, Color.WHITE if chosen else Color("dbe6ec"))
	var d := label_at(ArmyPresets.line(id), pos + P(16, 138), 18, Color("c5d2da"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(dims.x - 32 * K, 0)
	d.size = Vector2(dims.x - 32 * K, 0)


func _preset_changed() -> void:
	## In a room, your preset for the faction you play is your loadout: resend it.
	if Net.in_room() and _army == faction:
		ArmyPresets.send_to(Net, faction)


func _leave_armies() -> void:
	var back := _army_back
	_army_back = Callable()
	_army = ""
	if Net.in_room():
		ArmyPresets.send_to(Net, faction)
	back.call()


func show_maps() -> void:
	clear_page("city")
	header(2)
	label_at("CHOOSE YOUR BATTLEFIELD", P(40, 107), 43)
	frame(P(35, 174), P(975, 641))
	var shown := _filtered_maps()
	if not shown.is_empty() and not shown.any(func(e): return e["path"] == map_path):
		map_path = shown[0]["path"]                    # back on the page with filters set: pick a shown map
	if map_filter_mode != "all" and not shown.is_empty():
		mode = map_filter_mode                         # filtered by players: set up that mode
	label_at("%d OF %d MAPS" % [shown.size(), maps.size()], P(780, 122), 20, Color("8fb3c2"))
	var modes_all := _pool_modes()
	var chip_w: float = minf(104.0, (560.0 - 8.0 * modes_all.size()) / float(modes_all.size() + 1))
	var x := 52.0
	for md in ["all"] + modes_all:
		var md_now: String = md
		nav_button("ALL" if md == "all" else MODE_NAMES.get(md, md), P(x, 188), P(chip_w, 52), func():
			map_filter_mode = md_now
			_refilter(), md == map_filter_mode)
		x += chip_w + 8.0
	nav_button("TYPE: %s" % MAP_TYPE_NAMES[map_filter_type], P(752, 188), P(240, 52), func():
		map_filter_type = MAP_TYPES[(MAP_TYPES.find(map_filter_type) + 1) % MAP_TYPES.size()]
		_refilter(), map_filter_type != "all")
	if shown.is_empty():
		label_at("No map matches these filters.", P(70, 290), 24, Color("abc1cd"))
	var scroll := TouchScroll.new()                    # finger swipes scroll the grid (phones)
	var keep := _map_scroll                           # picking a map rebuilds the page: stay where you were
	get_tree().process_frame.connect(func(): if is_instance_valid(scroll): scroll.scroll_vertical = keep, CONNECT_ONE_SHOT)
	scroll.position = P(52, 258)
	scroll.size = P(940, 542)
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(16 * K))
	grid.add_theme_constant_override("v_separation", int(16 * K))
	scroll.add_child(grid)
	for entry in shown:
		var m: Dictionary = entry["data"]
		var mp: String = entry["path"]
		var code: String = m.get("code", "")
		var b := button("", func():
			if scroll.was_drag():                     # that was a swipe, not a pick
				return
			_map_scroll = scroll.scroll_vertical
			map_path = mp
			show_maps(), 451 * K)
		b.custom_minimum_size = P(451, 272)
		grid.add_child(b)
		var tex := TextureRect.new()
		var thumb := MapPool.thumb(code)
		tex.texture = load(thumb) if ResourceLoader.exists(thumb) else null
		tex.position = P(8, 8)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # the whole map, never cropped (Daniele, 0.18.7:
		                                                         # "thumbnail of maps often overflow and can't be seen in full")
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
	label_at("%s    /    %d NODES%s" % [" · ".join(_modes_of(sel).map(func(x): return MODE_NAMES.get(x, x))), sel["nodes"].size(), _relay_kinds(sel).to_upper()], P(1053, 683), 23, color())
	var ls_methods: Array = sel.get("lastStand", {}).get("methods", [])
	var ls_line: String = "No Last Stand on this map" if ls_methods.is_empty() else "Last Stand at %d:%02d - methods: %s" % [
			int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60, ", ".join(ls_methods)]
	label_at("%s\n%s" % [_map_blurb(sel), ls_line], P(1053, 736), 22, Color("abc1cd"))
	nav_button("BACK", P(40, 866), P(230, 58), show_factions)
	nav_button("NEXT: MATCH SETUP", P(1280, 866), P(352, 58), show_setup, true)


func _map_type(m: Dictionary) -> String:
	var g := str(m.get("group", "")).to_lower()
	return "training" if g in ["tutorial", "debug"] else g


func _filtered_maps() -> Array:
	return maps.filter(func(e):
		var m: Dictionary = e["data"]
		return (map_filter_mode == "all" or map_filter_mode in _modes_of(m)) 				and (map_filter_type == "all" or _map_type(m) == map_filter_type))


func _pool_modes() -> Array:
	## The modes some map in the pool offers, in MODE_NAMES order (no chip for a mode no map has).
	var have := {}
	for e in maps:
		for md in _modes_of(e["data"]):
			have[md] = true
	return ["1v1", "2v2", "3v3", "2v2v2", "FFA3", "FFA4", "FFA5"].filter(func(md): return have.has(md))


func _refilter() -> void:
	## A filter changed: back to the top of the grid.
	_map_scroll = 0
	show_maps()                                       # which picks a shown map and the filtered mode


func _relay_kinds(m: Dictionary) -> String:
	var kinds := {}
	for n in m["nodes"]:
		if n.get("relay") != null:
			kinds[n["relay"]] = true
	return "    /    " + " + ".join(kinds.keys()) if not kinds.is_empty() else ""


func _modes_of(m: Dictionary) -> Array:
	var out := []
	for k in ["1v1", "2v2", "3v3", "2v2v2", "FFA3", "FFA4", "FFA5"]:
		if m.get("seats", {}).has(k):
			out.append(k)
	return out if not out.is_empty() else ["1v1"]


func _map_blurb(m: Dictionary) -> String:
	## maps 3.0/4.0: group, family, seats, rings and raised decks; legacy roster maps: tier, layout
	## family and overpass count.
	if m.has("layout"):                               # maps 3.0: group, family, seats, raised decks, rings
		var raised: int = (m["layout"]["edges"] as Array).filter(func(e): return float(e["h"]) != 0.0).size()
		return "%s · %s · %s · %d rings%s" % [str(m.get("group", "")).capitalize(), m.get("family", ""), m.get("playersLabel", ""),
				int(m.get("rings", {}).get("count", 1)), ", %d raised decks" % raised if raised > 0 else ""]
	var overs: int = m["edges"].filter(func(e): return e.get("overpass", false)).size()
	return "%s map, %s layout%s" % [str(m.get("tier", "")).capitalize(), m.get("family", ""),
			", %d overpass%s" % [overs, "es" if overs > 1 else ""] if overs > 0 else ""]


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
	map_preview(P(53, 277), P(946, 360))
	var modes := _modes_of(_selected_map())
	if not mode in modes:
		mode = modes[0]
	label_at("PLAYERS", P(58, 652), 20, Color("aac3cd"))
	for i in range(modes.size()):
		var md: String = modes[i]
		var mb := nav_button(MODE_NAMES.get(md, md), P(150 + i * 140, 642), P(132, 48), func():
			mode = md
			show_setup(), md == mode)
		mb.add_theme_font_size_override("font_size", int(round(18 * K)))
	label_at("YOUR COLOUR", P(58, 725), 20, Color("aac3cd"))
	var keys := COLOUR_NAMES.keys()
	for i in range(keys.size()):
		var ck: String = keys[i]
		var cc: Color = Rules.FACTIONS[faction][1] if ck == "faction" else Rules.SEATS[ck]
		var cb := nav_button(COLOUR_NAMES[ck], P(210 + i * 112, 715), P(106, 48), func():
			colour = ck
			show_setup(), ck == colour)
		cb.add_theme_font_size_override("font_size", int(round(15 * K)))
		cb.add_theme_color_override("font_color", cc)
	label_at("Team modes: one hue per team, light and dark. FACTION: every seat in its own faction colour (Alpha 11).", P(58, 778), 14, Color("7795a4"))
	frame(P(1037, 188), P(595, 630))
	label_at("YOUR FACTION  ·  SEAT A", P(1059, 208), 20, Color("aac3cd"))
	summary_card(faction, P(1058, 240), P(552, 130), true)
	label_at("RIVAL  ·  SEAT B", P(1059, 389), 20, Color("aac3cd"))
	if rival != "random":
		summary_card(rival, P(1058, 422), P(552, 121), false)
	else:
		frame(P(1058, 422), P(552, 121), "row")
		label_at("RANDOM RIVAL" if mode == "1v1" else "SEAT B + OTHER AI SEATS", P(1080, 445), 30, Color("adc7d2"))
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
		var b := nav_button(lv.to_upper(), P(1058 + i * 111, 653), P(105, 59), func():   # Alpha 11's five levels
			ai_level = lv
			show_setup(), lv == ai_level)
		b.add_theme_font_size_override("font_size", int(round(14 * K)))
	var mdb := nav_button("MODE / %s" % ("SIEGE" if Rules.bridge_combat else "BRAWL"), P(1058, 746), P(176, 60), func():
		Rules.bridge_combat = not Rules.bridge_combat
		show_setup())
	var lsb := nav_button("LAST STAND / %s" % ("ON" if Rules.last_stand else "OFF"), P(1242, 746), P(184, 60), func():
		Rules.last_stand = not Rules.last_stand
		show_setup())
	# SKILLS 2.0: ABILITIES ON / OFF (Alpha 11's match setting; default ON)
	var abb := nav_button("ABILITIES / %s" % ("ON" if Rules.abilities_on else "OFF"), P(1434, 746), P(176, 60), func():
		Rules.abilities_on = not Rules.abilities_on
		show_setup(), Rules.abilities_on)
	for b in [mdb, lsb, abb]:
		b.add_theme_font_size_override("font_size", int(round(20 * K)))
	label_at("BRAWL = Alpha 11 rules  ·  Last Stand OFF = no collapse  ·  ABILITIES OFF = no skills", P(1062, 812), 14, Color("7795a4"))
	nav_button("BACK", P(40, 866), P(230, 58), show_maps)
	nav_button("DEPLOY", P(1280, 866), P(352, 58), deploy, true)


func summary_card(f: String, pos: Vector2, dims: Vector2, change: bool) -> void:
	frame(pos, dims, "row")
	portrait(f, pos + P(6, 6), Vector2(146 * K, dims.y - 12 * K))
	label_at("VIRIDIAN" if f == "bloom" else f.to_upper(), pos + P(174, 23), 34, Rules.FACTIONS[f][1])
	label_at(NAMES[f].split("\n")[1], pos + P(177, 70), 20, Color("adc7d2"))
	if change:
		nav_button("CHANGE", pos + Vector2(dims.x - 148 * K, dims.y - 50 * K), P(132, 42), show_factions).add_theme_font_size_override("font_size", int(round(19 * K)))
		# your army preset on this map (a relay skill greyed to its fallback where the map has no relays); tap: ARMIES
		var ip := pos + Vector2(dims.x - 162 * K, 12 * K)
		var ab := nav_button("", ip - P(6, 4), P(160, 60), func(): show_armies(f, show_setup))
		ab.tooltip_text = "Your army preset - tap to change it in ARMIES"
		loadout_icons(f, ArmyPresets.loadout_for(f), ip, 42.0 * K, 8.0 * K, ArmyPresets.map_has_relays(_selected_map()))
		var eff := ArmyPresets.effective(f, ArmyPresets.loadout_for(f), ArmyPresets.map_has_relays(_selected_map()))
		if not Rules.abilities_on:
			label_at("ABILITIES OFF", ip + P(0, 54), 13, Color("7795a4"))
		elif eff["swapped"] != "":
			label_at("NO RELAYS: %s" % ArmyPresets.skill_name(eff["map"]).to_upper(), ip + P(-14, 54), 13, Color("ffd15c"))


func deploy() -> void:
	var r := rival
	if r == "random":
		var others := FACTIONS.filter(func(f): return f != faction)
		r = others[randi() % others.size()]
	main.start_match(map_path, faction, r, ai_level, mode, colour, ArmyPresets.loadout_for(faction))   # your ARMIES preset


# ------------------------------------------------------------------ online (Net, peer-to-peer rooms)
func show_online() -> void:
	## ONLINE: pick your faction, then CREATE ROOM (you host) or JOIN ROOM (the host's code).
	clear_page("city")
	_page = "online"
	header(0)
	label_at("PLAY WITH FRIENDS", P(40, 107), 43)
	frame(P(35, 174), P(1600, 640))
	label_at("PRIVATE PEER-TO-PEER ROOMS  ·  HOSTED BY ONE PLAYER'S BROWSER", P(60, 196), 24, color())
	var about := label_at("Create a room and share its four-character code; everyone opens this same link. Keep the host's tab open and in front - the host's game runs the match. Free-for-all for 2 to 5 players, or 2 v 2. Rematch reuses the room; chat stays between rounds.",
			P(60, 245), 20, Color("bbd1db"))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(1540 * K, 0)
	about.size = Vector2(1540 * K, 0)
	label_at("YOUR FACTION", P(60, 372), 20, Color("aac3cd"))
	_faction_row(P(60, 405), P(300, 64))
	var web := OS.has_feature("web")
	var create := nav_button("CREATE ROOM", P(60, 520), P(560, 92), func():
		ArmyPresets.send_to(Net, faction)                     # your ARMIES preset rides in the roster
		Net.host_room(faction)
		show_lobby(), true)
	create.disabled = not web
	var join := nav_button("JOIN ROOM", P(640, 520), P(560, 92), _open_code)
	join.disabled = not web
	if not Net.rejoin.is_empty():                     # dropped out of a room: back into the same seat
		var rc := nav_button("RECONNECT  %s" % str(Net.rejoin["code"]), P(1220, 520), P(380, 92), func():
			ArmyPresets.send_to(Net, str(Net.rejoin.get("faction", faction)))
			Net.reconnect()
			show_lobby(), true)
		rc.disabled = not web
	var msg := Net.status if Net.status != "" else ("Some networks block direct connections (there is no relay server yet); if joining fails, try another network." if web
			else "Online rooms run in the browser build: open https://talos91.github.io/ooza-syndicate-v2/")
	var st := label_at(msg, P(60, 650), 20, Color("ffd15c") if Net.status != "" else Color("adc7d2"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(1540 * K, 0)
	st.size = Vector2(1540 * K, 0)
	nav_button("BACK", P(40, 866), P(230, 58), func():
		Net.status = ""
		show_main())


func _faction_row(pos: Vector2, dims: Vector2) -> void:
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var b := nav_button("VIRIDIAN" if f == "bloom" else f.to_upper(), pos + Vector2(i * (dims.x + 12 * K), 0), dims, func():
			faction = f
			main.SEAT_FACTIONS[main.HUMAN] = f
			ArmyPresets.room_faction(Net, f)                          # the faction and its ARMIES preset
			if _page == "lobby":
				show_lobby()
			else:
				show_online(), f == faction)
		b.add_theme_font_size_override("font_size", int(round(20 * K)))
		if f != faction:
			b.add_theme_color_override("font_color", Rules.FACTIONS[f][1])


func show_lobby() -> void:
	## The room: who is in which seat, the host's match settings, DEPLOY when every seat is filled.
	if not Net.in_room():
		show_online()
		return
	clear_page("city")
	_page = "lobby"
	map_path = Net.map_path                           # the rows' loadout icons read the room's map (relays)
	header(0)
	if Net.roster.has(Net.local_id()):
		faction = str(Net.roster[Net.local_id()]["faction"])
	var host := Net.is_host()
	label_at("ROOM %s" % (Net.room_code if Net.room_code != "" else "...."), P(40, 100), 52)
	var copy := nav_button("SHARE CODE", P(420, 110), P(230, 52), _share_code)
	copy.disabled = Net.room_code == ""
	var chat := nav_button("CHAT (%d)" % Net.chat_unread() if Net.chat_unread() > 0 else "CHAT", P(668, 110), P(180, 52), Net.open_chat)
	chat.disabled = not Net.connected
	_chat_btn = chat
	var army := nav_button("MY ARMY", P(866, 110), P(170, 52), func(): show_armies(faction, show_lobby))   # your preset = your loadout
	army.disabled = Net.active
	var st := label_at(Net.status, P(1054, 122), 18, Color("adc7d2"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(584 * K, 0)
	st.size = Vector2(584 * K, 0)
	# players (0.18.7, Daniele: "there should be so i can switch to my gf team"; every seat's colour is
	# the same on every screen): team modes list the seats team by team, each team with its JOIN TEAM
	# control (tall enough for a phone thumb); the host can pick a player's row and MOVE them
	frame(P(35, 188), P(800, 640))
	label_at("PLAYERS  %d / %d" % [Net.roster.size(), Net.slots()], P(58, 205), 28)
	var by_slot := {}
	for id in Net.roster:
		by_slot[int(Net.roster[id]["slot"])] = int(id)
	if not Net.roster.has(_move_pick) or not host or _move_pick == Net.local_id():
		_move_pick = -1
	var colours := Net.room_colours()
	var team_mode := Net.mode in Net.TEAM_MODES
	var groups := []                                  # [team, [slots]] in seat order; FFA: one group
	if team_mode:
		for t in Net.team_ids():
			groups.append([t, range(Net.slots()).filter(func(sl): return Net.team_of_slot(sl) == t)])
	else:
		groups.append([-1, range(Net.slots())])
	var row_h: float = minf(76.0, floorf((384.0 - 10.0 * (groups.size() - 1)) / float(Net.slots())))
	var row_w := 590.0 if team_mode else 754.0
	var y := 252.0
	for g in groups:
		var top := y
		for i in g[1]:
			_lobby_row(i, by_slot.get(i, -1), colours, P(58, y), P(row_w, row_h - 8.0), host and team_mode)
			y += row_h
		if team_mode:
			_team_button(int(g[0]), colours, P(660, top), P(152, y - top - 8.0))
			y += 10.0
	label_at("FACTION", P(58, 662), 18, Color("aac3cd"))
	_faction_row(P(190, 646), P(114, 52))
	label_at("COLOUR", P(58, 728), 18, Color("aac3cd"))
	_colour_row(P(190, 712), P(74, 52))
	var hint := "Every seat has one colour, the same on every screen. " + (("Teammates share a hue family (%s); a colour from a free family moves your team to it. " % " / ".join(
			Net.families().map(func(f): return Rules.FAMILY_NAMES.get(f[0], "")))) if team_mode else "Seats go in join order. ")
	if team_mode and host:
		hint += "Host: tap a player, then MOVE on a team."
	var hl := label_at(hint, P(58, 772), 14, Color("7795a4"))
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size = Vector2(760 * K, 0)
	hl.size = Vector2(760 * K, 0)
	# match settings (host decides)
	map_path = Net.map_path
	frame(P(855, 188), P(780, 640))
	label_at("MATCH" + ("" if host else "  ·  the host decides"), P(878, 205), 28)
	map_preview(P(876, 250), P(738, 290))
	label_at(str(_selected_map().get("name", "")).replace("*", "").to_upper(), P(878, 552), 26)
	var prev := nav_button("<", P(1440, 548), P(80, 48), func(): _step_map(-1))
	var next := nav_button(">", P(1534, 548), P(80, 48), func(): _step_map(1))
	prev.disabled = not host
	next.disabled = not host
	label_at("PLAYERS", P(878, 622), 20, Color("aac3cd"))
	for i in range(Net.MODES.size()):
		var md: String = Net.MODES[i]
		var mb := nav_button(Net.MODE_LABELS[md], P(962 + i * 96, 612), P(90, 48), func():
			Net.set_mode(md)
			show_lobby(), md == Net.mode)
		mb.add_theme_font_size_override("font_size", int(round(15 * K)))
		mb.disabled = not host or Net.roster.size() > Net.SLOTS[md] or Net.maps_for(md).is_empty()
	var sb := nav_button("MODE / %s" % ("SIEGE" if Net.siege else "BRAWL"), P(878, 680), P(236, 56), func():
		Net.toggle_siege()
		show_lobby())
	sb.disabled = not host
	var lb := nav_button("LAST STAND / %s" % ("ON" if Net.last_stand else "OFF"), P(1126, 680), P(244, 56), func():
		Net.toggle_last_stand()
		show_lobby())
	lb.disabled = not host
	var abl := nav_button("ABILITIES / %s" % ("ON" if Net.abilities else "OFF"), P(1382, 680), P(232, 56), func():   # SKILLS 2.0
		ArmyPresets.room_toggle_abilities(Net)
		show_lobby(), Net.abilities)
	abl.disabled = not host
	for b in [sb, lb, abl]:
		b.add_theme_font_size_override("font_size", int(round(21 * K)))
	var ab := nav_button("EMPTY SEATS / %s" % ("AI " + Net.ai_fill.to_upper() if Net.ai_fill != "" else "PLAYERS ONLY"), P(878, 750), P(736, 50), func():
		Net.set_ai_fill(Net.AI_FILL[(Net.AI_FILL.find(Net.ai_fill) + 1) % Net.AI_FILL.size()])
		show_lobby())
	ab.add_theme_font_size_override("font_size", int(round(17 * K)))
	ab.disabled = not host
	nav_button("LEAVE ROOM", P(40, 866), P(260, 58), func():
		Net.leave()
		show_online())
	if host:
		var go := nav_button("DEPLOY", P(1280, 866), P(352, 58), func(): Net.start_match(), true)
		go.disabled = not Net.can_start()
		if not Net.can_start():
			label_at("DEPLOY opens when every seat is filled (or EMPTY SEATS: AI)", P(820, 884), 17, Color("adc7d2"))
	else:
		label_at("The host deploys when ready", P(1300, 884), 19, Color("adc7d2"))


func _lobby_row(i: int, id: int, colours: Dictionary, pos: Vector2, dims: Vector2, movable: bool) -> void:
	## One seat of the room: its letter in the seat's colour (the room's colour, the same for everyone),
	## the player's faction and colour, HOST / YOU. Host, team modes: a guest's row picks them to MOVE.
	var seat: String = Net.SEATS[i]
	var col: Color = Rules.HUES.get(str(colours.get(seat, "")), Rules.SEATS.get(seat, Color.WHITE))
	if movable and id >= 0 and id != Net.local_id():
		nav_button("", pos, dims, func():
			_move_pick = -1 if _move_pick == id else id
			show_lobby())
	frame(pos, dims, "row")
	if id == _move_pick and id >= 0:
		content.add_child(neon_panel(pos, dims, col, true, Color(0, 0, 0, 0)))
	var mid := pos.y + dims.y / 2.0
	label_at(seat, Vector2(pos.x + 20 * K, mid - 22 * K), 34, col)
	var sw := ColorRect.new()                         # the seat's colour as a swatch, named beside it
	sw.color = col
	sw.position = Vector2(pos.x + 64 * K, mid - 13 * K)
	sw.size = P(10, 26)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(sw)
	if id >= 0:
		var f: String = str(Net.roster[id]["faction"])
		label_at("VIRIDIAN BLOOM" if f == "bloom" else NAMES[f].replace("\n", " "), Vector2(pos.x + 84 * K, mid - 24 * K), 22, Rules.FACTIONS[f][1])
		var tags := ("HOST" if id == 1 else "") + ("  ·  YOU" if id == Net.local_id() else "") + ("  ·  RECONNECTING" if Net.is_away(id) else "")
		label_at(("%s  %s" % [str(colours.get(seat, "")).to_upper(), tags]).strip_edges(), Vector2(pos.x + 84 * K, mid + 2 * K), 16, Color("ffd15c"))
		# SKILLS 2.0: the player's loadout - active, map (the no-relay fallback on such a map), ultimate
		var lo = Net.roster[id].get("loadout", {})
		var ic := minf(44.0 * K, dims.y - 22.0 * K)
		var gap := 7.0 * K
		var lp := Vector2(pos.x + dims.x - 3.0 * ic - 2.0 * gap - 12.0 * K, mid - ic / 2.0)
		loadout_icons(f, lo if lo is Dictionary else {}, lp, ic, gap, ArmyPresets.map_has_relays(_selected_map()))
		if not Net.abilities:
			var off := ColorRect.new()                    # ABILITIES OFF: the icons dimmed
			off.color = Color(0.01, 0.04, 0.06, 0.62)
			off.position = lp - Vector2.ONE * 3.0 * K
			off.size = Vector2(3.0 * ic + 2.0 * gap + 6.0 * K, ic + 6.0 * K)
			off.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(off)
	else:
		label_at(("AI  ·  %s" % Net.ai_fill.to_upper()) if Net.ai_fill != "" else "open seat - waiting for a player", Vector2(pos.x + 84 * K, mid - 12 * K), 18, Color("7795a4"))


func _team_button(t: int, colours: Dictionary, pos: Vector2, dims: Vector2) -> void:
	## JOIN TEAM n (you), or MOVE X HERE (the host, with a player picked); a full team takes nobody.
	var me := Net.local_id()
	var who := _move_pick if _move_pick >= 0 else me
	var here := Net.team_of(who) == t
	var room := Net.free_slot_in(t) >= 0
	var verb := ("YOUR TEAM" if who == me else "%s IS HERE" % Net.seat_of(who)) if here else (("JOIN" if who == me else "MOVE %s HERE" % Net.seat_of(who)) if room else "FULL")
	var b := nav_button("TEAM %d\n%s" % [Net.team_ids().find(t) + 1, verb], pos, dims, func():
		if who == me:
			Net.switch_team(t)
		else:
			Net.move_to_team(who, t)
		_move_pick = -1
		show_lobby(), not here and room)
	b.add_theme_font_size_override("font_size", int(round(19 * K)))
	b.disabled = here or not room or Net.active
	var first := -1
	for sl in range(Net.slots()):
		if Net.team_of_slot(sl) == t:
			first = sl
			break
	if first >= 0:                                    # the team's hue as a bar along the button's foot
		var bar := ColorRect.new()
		bar.color = Rules.HUES.get(str(colours.get(Net.SEATS[first], "")), Color.WHITE)
		bar.position = Vector2(14 * K, dims.y - 16 * K)
		bar.size = Vector2(dims.x - 28 * K, 6 * K)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)


func _colour_row(pos: Vector2, dims: Vector2) -> void:
	## Your colour: one chip per hue; taken hues (and, in team modes, another team's family) are off.
	var me := Net.local_id()
	var mine := Net.colour_of(me)
	for i in range(HUE_NAMES.size()):
		var k: String = HUE_NAMES[i]
		var ok := Net.colour_allowed(me, k) or k == mine
		var b := nav_button(k.to_upper(), pos + Vector2(i * (dims.x + 5 * K), 0), dims, func():
			Net.set_colour(k)
			show_lobby(), k == mine)
		b.add_theme_font_size_override("font_size", int(round(14 * K)))
		if k != mine:                                 # yours: the kit's selected style, white on the fill
			b.add_theme_color_override("font_color", Rules.HUES[k])
		b.disabled = not ok or Net.active
		var bar := ColorRect.new()                    # the hue itself under the name (dimmed when off)
		bar.color = Rules.HUES[k] if ok else Color(Rules.HUES[k], 0.25)
		bar.position = Vector2(8 * K, dims.y - 11 * K)
		bar.size = Vector2(dims.x - 16 * K, 5 * K)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)


func _step_map(d: int) -> void:
	var pool: Array = Net.maps_for(Net.mode)
	if pool.is_empty():
		return
	var i := pool.find(Net.map_path)
	Net.set_map(pool[posmod(i + d, pool.size())])
	show_lobby()


func _on_net_changed() -> void:
	if _page == "lobby" or (_page == "online" and Net.in_room()):
		show_lobby()
	elif _page == "online":
		show_online()


func _open_code() -> void:
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeRoom")
		if ui != null:
			ui.openCode("")


func _share_code() -> void:
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeRoom")
		if ui != null:
			ui.shareCode(Net.room_code)
	else:
		DisplayServer.clipboard_set(Net.room_code)


func _process(dt: float) -> void:
	## The room code comes from the native DOM field (phone keyboards: web/room-ui.js, Alpha 11's).
	if _page == "lobby" and is_instance_valid(_chat_btn):   # unread count on the lobby CHAT button
		_chat_t -= dt
		if _chat_t <= 0.0:
			_chat_t = 0.5
			var n := Net.chat_unread()
			_chat_btn.text = "CHAT (%d)" % n if n > 0 else "CHAT"
			_chat_btn.disabled = not Net.connected
	if not OS.has_feature("web") or _page != "online":
		return
	var ui = JavaScriptBridge.get_interface("OozeRoom")
	if ui == null:
		return
	var code := str(ui.takeCode())
	if code.length() == 4:
		ArmyPresets.send_to(Net, faction)                         # the register carries your ARMIES preset
		Net.join_room(code, faction)
		show_lobby()


func _exit_tree() -> void:
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeRoom")
		if ui != null:
			ui.closeCode()


func _fit() -> void:
	## The page is laid out on a 1280x720 canvas; scale it to fit any screen shape and centre it
	## (Alpha 14 playtest: "screen size varies and half the interface is shrunk to the left").
	if not is_instance_valid(content):
		return
	var vp := get_viewport().get_visible_rect().size
	var s := minf(vp.x / 1280.0, vp.y / 720.0)
	content.size = Vector2(1280, 720)
	content.scale = Vector2(s, s)
	content.position = (vp - Vector2(1280, 720) * s) / 2.0
