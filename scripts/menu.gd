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
## the host (Net, through the room server). TUTORIAL (TUTORIAL-DESIGN.md §7): the nine lesson rows
## (TutorialPage, TutorialDirector's table and progress), CONTINUE = the first lesson not done.
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
var rival_picks: Dictionary = {}                  # seat letter -> "random" | faction id (0.19.2, one per enemy seat)
var rival: String:                                # kept for the RIVAL summary card: seat B's pick
	get: return str(rival_picks.get("B", "random"))
	set(v): rival_picks["B"] = v
var map_path := ""                                # setup() takes main's, or the pool's first map
var ai_level := "Standard"
var mode := "1v1"
var colour := "A"
const MODE_NAMES := {"1v1": "1 V 1", "2v2": "2 V 2", "3v3": "3 V 3", "2v2v2": "2V2V2", "FFA3": "FFA 3", "FFA4": "FFA 4", "FFA5": "FFA 5"}
const COLOUR_NAMES := {"A": "CYAN", "B": "GREEN", "C": "PURPLE", "D": "RED", "E": "GOLD", "F": "ROSE", "faction": "FACTION"}
var maps: Array = []
var _is_main := false
var _last_show := Callable()                     # the page on screen (rebuilt when a resize changes the phone sizing)
var _built_pt := 0.0                             # _pt_factor() the page was built with (0 while building)
var _backdrop: TextureRect
var _backdrop_art: Texture2D                     # the backdrop's own art (HOME swaps in the hero faction's scene)
# UI: the Alpha 21 app shell (Daniele's navigation mockups, 2026-09-28): a shell page lays out full screen width in
# canvas units (UiKit) between a TopBar and a NavBar - HOME / PLAY / ARMIES / CAMPAIGN.
var _shell := false
var _built_w := 0.0                              # the shell page's canvas width when built (a rotation rebuilds it)
var top_bar: TopBar
var nav_bar: NavBar
var shell_f := "vex"                             # the faction a shell page is dressed in (its accent, its backdrop)
var shell_back := Callable()                     # the page's BACK (a subflow), or none (a top-level tab)
var shell_slim := false                          # a phone subflow: BACK in the bar, no tab bar
var _page := ""                                  # "online" / "lobby": rebuilt when the room changes
var _map_scroll := 0
# map filters on 02 BATTLEFIELD (Daniele, 0.18.6: "add in game filters for maps like 1v1 2v2 ffa etc"): players
# (a mode the map offers) and type (the map's group); static, so they survive a trip through the match
static var map_filter_mode := "all"
static var map_filter_type := "all"
const MAP_TYPES := ["all", "brawl", "siege", "core", "alpha 11", "training"]
const MAP_TYPE_NAMES := {"all": "ALL", "brawl": "FAST", "siege": "FORTRESS", "core": "STANDARD", "alpha 11": "ALPHA 11", "training": "TRAINING"}
# (0.19.0, Daniele: labels only - the pack groups (BRAWL / SIEGE / CORE) stay the same underneath)
var _chat_btn: Button
var _chat_t := 0.0
var _move_pick := -1                               # host, team modes: the player picked to MOVE to a team
const HUE_NAMES := ["red", "green", "blue", "gold", "purple", "cyan", "rose", "orange"]   # Rules.HUES, lobby order
var _army := ""                                    # ARMIES: the faction whose preset is open
var _army_back := Callable()                       # ARMIES: the page it was opened from
var _tut_page: TutorialPage                        # TUTORIAL: the lesson page (its own canvas, over the backdrop)

# Phone sizing (Daniele, 0.18.8: "quite small on mobile in certain parts"): every tappable control
# reaches Apple's 44 pt guideline and every label a readable size on a landscape phone (844 x 390 pt -
# the same reference map_camera.gd and the phone-fit probe use), not just hud.gd's ui_scale bump.
# content is scaled twice - by K (this canvas's 1672->1280 conversion, baked into every P() call and
# every text_label size_value) and by _fit()'s s (1280 canvas -> the real viewport) - so a raw unit
# alone can't say what lands as N pt; _pt_factor() works out raw-unit -> pt at the live viewport fit.
const MIN_TAP_PT := 44.0                           # Apple's guideline (map_camera.gd, phone_fit.gd)
const MIN_FONT_PT := 12.5                          # readable body/caption text (Daniele: >= 12 / 10 pt asked)
const PHONE_PT_H := 390.0                          # landscape phone reference height
var mobile := false                                # main.mobile


func _pt_factor() -> float:
	## Raw (pre-K, Alpha-11-style) unit -> pt at the current viewport fit; 0.0 on desktop (no minimum
	## applies) or before the first _fit().
	if not mobile:
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0
	var s := minf(vp.x / 1280.0, vp.y / 720.0)
	if s <= 0.0:
		return 0.0
	return K * s * (PHONE_PT_H / vp.y)


func _tap_min_raw() -> float:
	## The shortest a tappable control's raw (pre-K) height may be to land at >= 44 pt. 0.0 on desktop.
	var f := _pt_factor()
	return (MIN_TAP_PT / f) if f > 0.0 else 0.0


func _tap_min() -> float:
	## _tap_min_raw(), already K-scaled - what dims: Vector2 (every P() result) already are.
	return _tap_min_raw() * K


func tap(dims: Vector2) -> Vector2:
	## Grows a control's HEIGHT (never its width - rows keep their column count) to the phone minimum;
	## a no-op on desktop or where dims is already tall enough.
	return Vector2(dims.x, maxf(dims.y, _tap_min()))


func rh(base: float) -> float:
	## A raw (pre-K) row height: `base` on desktop, the phone tap minimum on mobile if that is taller.
	return maxf(base, _tap_min_raw())


func foot_y(h: float = 58.0) -> float:
	## The foot nav row (BACK / NEXT / DEPLOY / LEAVE ROOM...) sits at a raw y of 866 by design, `h` (58)
	## raw units tall; grown by tap() on mobile (rh(), the same growth nav_button applies), that would run
	## past the bottom of the 720/K raw canvas - foot_y() nudges the row up just enough to keep it fully
	## on screen (a no-op at the desktop height, where rh() doesn't grow it).
	return minf(866.0, 720.0 / K - rh(h) - 4.0)


func fsz(size_value: int) -> int:
	## A raw (pre-K) text size_value: itself on desktop, grown on mobile so it renders at >= 12.5 pt
	## (Daniele: text was unreadably small alongside the undersized buttons).
	var f := _pt_factor()
	return maxi(size_value, int(ceil(MIN_FONT_PT / f))) if f > 0.0 else size_value


func setup(m: Node3D) -> void:
	main = m
	mobile = m.mobile
	ArmyPresets.load_all()                            # the saved army presets (none, or no storage: the defaults)
	_backdrop = TextureRect.new()                     # full-screen art behind the scaled page
	var art: Texture2D = load("res://assets/art/ui-main.png")
	var clean := AtlasTexture.new()                   # the art's right part: its left edge has Alpha 11's
	clean.atlas = art                                 # buttons baked in, which peeked out on wide screens
	clean.region = Rect2(Vector2(art.get_size()) * Vector2(0.36, 0.0), Vector2(art.get_size()) * Vector2(0.64, 1.0))
	_backdrop.texture = clean
	_backdrop_art = clean
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.modulate = Color(0.55, 0.6, 0.65)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	get_viewport().size_changed.connect(_fit)
	faction = m.SEAT_FACTIONS[m.HUMAN]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-cfg="):              # UI: tests / screenshots use their own ui.cfg
			UiKit.path = arg.substr(9)
	if not m.relaunch.has("faction"):                 # UI: a fresh start opens on the faction played last (HOME's hero)
		faction = UiKit.last_faction()
	if Net.in_room() or Net.status != "":             # back from a room: keep the faction you played
		faction = Net.preferred_faction
	ai_level = m.ai_level
	map_path = m.map_path
	mode = m.mode
	colour = m.color_choice
	for mp in MapPool.battlefield():
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
	if is_instance_valid(_tut_page):
		_tut_page.queue_free()
		_tut_page = null
	_built_pt = 0.0                                   # no rebuild check while this page is being built
	_shell = art == "shell"                           # UI: before _fit(), which sizes a shell page full width
	top_bar = null
	nav_bar = null
	content = Control.new()
	add_child(content)
	_fit()
	_built_pt = _pt_factor()
	_built_w = content.size.x
	_is_main = art == "ui-main"
	_page = ""
	# one background only: the full-screen backdrop (Alpha 14 playtest: "background on top of a
	# background" - the page used to draw its own copy of the art, misaligned on taller screens)
	if _backdrop:
		_backdrop.texture = _backdrop_art
		_backdrop.modulate = Color(0.95, 0.95, 0.95) if _is_main else Color(0.62, 0.68, 0.74)


func text_label(text: String, size_value: int = 20, col: Color = Color.WHITE, grow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HEAD_FONT if size_value >= 24 else UI_FONT)   # the font family follows the
	l.add_theme_font_size_override("font_size", int(round((fsz(size_value) if grow else size_value) * K)))   # DESIGNED size, not the phone bump
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func label_at(text: String, pos: Vector2, size_value: int = 20, col: Color = Color.WHITE, grow := true) -> Label:
	## `grow=false`: a label whose neighbour sits close enough (an inline number/tag pair, a badge in a
	## corner) that growing it to the phone minimum would run the two together - keeps its designed size
	## on mobile too rather than overlapping (an open issue: still small there, not a size-rule fix).
	var l := text_label(text, size_value, col, grow)
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
	b.add_theme_font_size_override("font_size", int(round(fsz(19) * K)))
	b.pressed.connect(func(): call.call_deferred())
	UiSkin.button(b, skin())
	return b


func nav_button(text: String, pos: Vector2, dims: Vector2, call: Callable, primary := false, grow := true) -> Button:
	if grow:
		dims = tap(dims)                              # phone: grow to >= 44 pt (a no-op on desktop)
	var b := button(text, call, dims.x)
	b.position = pos
	b.custom_minimum_size = dims
	b.size = dims
	b.add_theme_font_size_override("font_size", int(round(fsz(25) * K)))
	UiSkin.button(b, "vex" if _is_main else skin(), primary)
	content.add_child(b)
	return b


func hex_chip(pos: Vector2, dims: Vector2, fill: Color, wedges: Array, picked: bool, tip: String, call: Callable) -> HexChip:
	## A colour-picker chip (0.19.0, Daniele: "the actual hexagon should be in full color... no words,
	## border same color"): a solid hexagon (or, `wedges` non-empty, a FACTION-style split hexagon),
	## border the same colour, no text; the picked chip gets a white ring + a slight scale-up (HexChip).
	## `tip` is the chip's colour name, read out as its tooltip / accessible name for colour-blind players.
	dims = Vector2(maxf(dims.x, _tap_min()), maxf(dims.y, _tap_min()))   # a square tap target, both axes
	var b := HexChip.new()
	b.custom_minimum_size = dims
	b.size = dims
	b.position = pos
	b.fill = fill
	b.wedges = wedges
	b.tooltip_text = tip
	b.pressed.connect(func(): call.call_deferred())
	content.add_child(b)
	b.picked = picked                                 # after add_child: picked's setter needs `size` set
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


func stack_open(pos: Vector2, dims: Vector2) -> Dictionary:
	## A scrollable, phone-safe row stack (TouchScroll, Alpha 18's map-grid pattern): a page whose rows
	## grow to the phone tap/text minimums (rh() / fsz()) can outgrow its fixed frame on mobile before
	## any single row does - safer than hand-tuning every gap to a possibly-wrong hand calculation. Rows
	## are still built with the usual label_at() / nav_button() (position relative to `pos`, i.e. starting
	## near (0, 0)) and moved in with stack_add(); call stack_close() once every row is placed.
	var scroll := TouchScroll.new()
	scroll.position = pos
	scroll.size = dims
	content.add_child(scroll)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(inner)
	return {"scroll": scroll, "inner": inner}


func stack_add(stack: Dictionary, node: Control) -> Control:
	content.remove_child(node)
	(stack["inner"] as Control).add_child(node)
	return node


func stack_close(stack: Dictionary, content_h: float) -> void:
	var inner: Control = stack["inner"]
	var w: float = (stack["scroll"] as Control).size.x
	inner.custom_minimum_size = Vector2(w, content_h)
	inner.size = inner.custom_minimum_size


func stack_capture(stack: Dictionary, before: int) -> void:
	## Reparents into the stack every `content` child added since `before` (a content.get_child_count()
	## sampled right before the call(s) that built them) - lets a whole helper (_lobby_row(), a summary
	## card, ...) feed a stack without every one of them taking a parent argument.
	var inner: Control = stack["inner"]
	while content.get_child_count() > before:
		var c := content.get_child(before)
		content.remove_child(c)
		inner.add_child(c)


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
# ------------------------------------------------------------------ UI: the app shell (Alpha 21 UI pass)
func shell_open(crumb: String, tab: String, back := Callable(), f := "") -> Rect2:
	## Clears to a shell page (Alpha 21 UI pass): the faction's environment behind it, TopBar (breadcrumb,
	## balances, level -> PROFILE, gear -> OPTIONS, "?" -> HELP) and NavBar (HOME / PLAY / ARMIES / CAMPAIGN,
	## `tab` lit). A subflow (`back` given: faction, battlefield, setup, lobby...) on a phone is SLIM - BACK and the
	## breadcrumb only, no tab bar (SCREEN-SYSTEM.md "Mobile layout"); on desktop it keeps the full shell and its
	## title row carries the BACK link (page_title). Returns the free area in canvas units (full screen width).
	clear_page("shell")
	_page = tab
	shell_f = f if f != "" else faction
	shell_back = back
	shell_slim = mobile and back.is_valid()
	if _backdrop:
		var bg := UiKit.background(shell_f)
		if bg != null:
			_backdrop.texture = bg
		_backdrop.modulate = Color(0.55, 0.58, 0.62)
	top_bar = TopBar.make(self, crumb, shell_f, shell_slim)
	top_bar.help_pressed.connect(show_help)
	top_bar.options_pressed.connect(show_options)
	top_bar.profile_pressed.connect(show_profile)
	top_bar.back_pressed.connect(func(): back.call_deferred())
	content.add_child(top_bar)
	var y0 := top_bar.bar_height()
	var y1 := content.size.y
	if not shell_slim:
		nav_bar = NavBar.make(self, tab, shell_f)
		nav_bar.tab_pressed.connect(_on_tab)
		content.add_child(nav_bar)
		y1 = nav_bar.position.y
	return Rect2(0, y0, content.size.x, y1 - y0)


func shell_x() -> float:
	## The shell pages' side margin.
	return maxf(26.0, content.size.x * 0.024)


func page_title(area: Rect2, kicker: String, headline: String, size := 34.0) -> float:
	## The page's kicker + headline at the top of `area`, and BACK at the right when the page has one and the bar
	## doesn't; returns the y under the title (canvas units).
	var x := shell_x()
	var y := UiKit.title(self, x, area.position.y + (10.0 if shell_slim else 18.0), kicker, headline, shell_f,
			size * (0.8 if shell_slim else 1.0))
	if shell_back.is_valid() and not shell_slim:
		UiKit.back_link(self, content.size.x - x, area.position.y + 20.0, shell_back)
	return y + 14.0


func shell_raise() -> void:
	## Keeps the bars over anything a page drew after shell_open().
	if is_instance_valid(top_bar):
		content.move_child(top_bar, -1)
	if is_instance_valid(nav_bar):
		content.move_child(nav_bar, -1)


func _on_tab(id: String) -> void:
	match id:
		"home":
			show_main()
		"play":
			show_play()
		"armies":
			show_armies(faction, show_main)
		"campaign":
			show_campaign()


func _shell_add(c: Control, pos: Vector2) -> Control:
	return UiKit.add(self, c, pos)


func _fade_left(area: Rect2, reach: float) -> void:
	## A dark wash from the left edge, so HOME's text reads over the environment.
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BASE, 0.92))
	g.set_color(1, Color(UiKit.BASE, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.3, 0)
	gt.fill_to = Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(r)
	r.position = area.position
	r.size = Vector2(reach, area.size.y)


func show_main() -> void:
	## HOME (Daniele's screen system 01): the faction played last - its environment behind, its original character
	## on the right - the headline, PLAY (-> NEW GAME's faction step), CONTINUE CAMPAIGN, the training link while
	## lessons remain; CHALLENGES top right; QUIT / FULLSCREEN and the version at the foot; the install guide.
	_last_show = show_main                  # a resize that changes the phone sizing rebuilds it (_fit)
	var hero := UiKit.last_faction()
	var area := shell_open("OOZE / HOME", "home", Callable(), hero)
	_is_main = true
	if _backdrop:
		_backdrop.modulate = Color(0.7, 0.72, 0.76)
	var acc := UiKit.accent(hero)
	_fade_left(area, content.size.x * 0.6)
	var x := shell_x() + 8.0
	# the character, right of centre, over its glow; its tag under it
	var hs := minf(area.size.y * 0.78, content.size.x * 0.3)
	var hpos := Vector2(content.size.x * 0.66 - hs / 2.0, area.position.y + (area.size.y - hs) / 2.0 - 10.0)
	UiKit.hero(self, hero, hpos, Vector2(hs, hs))
	var tag_w := UiKit.text_w(self, UiKit.TAGS[hero], 14, true) + 60.0
	UiKit.tag(self, UiKit.TAGS[hero], Vector2(content.size.x * 0.66 - tag_w / 2.0 + 30.0, area.end.y - UiKit.tap_h(self, 36.0) - 20.0), hero)
	var kick := UiKit.label(self, "BETTER SLUDGE. FEWER QUESTIONS.", 13, acc, true, 3)
	var head := UiKit.label(self, "THE CITY IS\nYOURS TO TAKE.", 56, UiKit.INK, true)
	var sub := UiKit.label(self, "Pick your syndicate. Control the crossings.", 18, UiKit.MUTED)
	var bh := UiKit.tap_h(self, 54.0)
	var th := UiKit.tap_h(self, 36.0)
	var tut_done := TutorialDirector.done_count() >= TutorialDirector.TOTAL_LESSONS
	var stack_h := kick.get_minimum_size().y + 8.0 + head.get_minimum_size().y + 10.0 + sub.get_minimum_size().y \
			+ 26.0 + bh + (8.0 + th if not tut_done else 0.0)
	var free_h := area.size.y - th - 14.0              # the foot row (QUIT / version) keeps its own strip
	var y := area.position.y + maxf(10.0, (free_h - stack_h) / 2.0)
	_shell_add(kick, Vector2(x, y))
	y += kick.get_minimum_size().y + 8.0
	_shell_add(head, Vector2(x - 3.0, y))
	y += head.get_minimum_size().y + 10.0
	_shell_add(sub, Vector2(x, y))
	y += sub.get_minimum_size().y + 26.0
	UiKit.btn(self, "PLAY", Vector2(x, y), Vector2(230, 54), show_factions, "primary", hero, 20)
	var cont := UiKit.flat_button(self, "CONTINUE CAMPAIGN", 16)
	cont.size = Vector2(UiKit.text_w(self, cont.text, 16, true) + 28.0, bh)
	cont.pressed.connect(func(): show_campaign.call_deferred())
	_shell_add(cont, Vector2(x + 230.0 + 16.0, y))
	y += bh + 8.0
	if not tut_done:                                   # TUTORIAL (§7): "n / 10" until every lesson is done
		var n := TutorialDirector.done_count()
		var tl := UiKit.flat_button(self, "NEW HERE? START TRAINING  →" if n == 0
				else "TRAINING %d / %d  →" % [n, TutorialDirector.TOTAL_LESSONS], 14)
		tl.size = Vector2(UiKit.text_w(self, tl.text, 14, true) + 16.0, th)
		tl.pressed.connect(func(): show_tutorial.call_deferred())
		_shell_add(tl, Vector2(x, y))
	# PROGRESSION: CHALLENGES (what is ready to claim), top right under the bar
	var ready_n := Progression.claimable()
	var ct := "CHALLENGES" + ("  ·  %d TO CLAIM" % ready_n if ready_n > 0 else "")
	var cw := UiKit.text_w(self, ct, 15, true) + 44.0
	UiKit.btn(self, ct, Vector2(content.size.x - cw - shell_x(), area.position.y + 16.0), Vector2(cw, 42),
			show_challenges, "primary" if ready_n > 0 else "secondary", hero, 15)
	# the foot: FULLSCREEN (QUIT on desktop) and the version
	var fy := area.end.y - th - 6.0
	var fb := UiKit.flat_button(self, "FULLSCREEN" if OS.has_feature("web") else "QUIT", 13, UiKit.MUTED)
	fb.size = Vector2(UiKit.text_w(self, fb.text, 13, true) + 20.0, th)
	fb.pressed.connect(func():
		if OS.has_feature("web"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			get_tree().quit())
	_shell_add(fb, Vector2(x - 10.0, fy))
	var ver := UiKit.label(self, "%s  ·  v%s" % [Rules.VERSION_NAME.to_upper(), Rules.VERSION], 12, UiKit.DIM)
	_shell_add(ver, Vector2(x + fb.size.x + 4.0, fy + (th - ver.get_minimum_size().y) / 2.0))
	shell_raise()
	# 0.20.11: INSTALL THE GAME (web + phone browsers only, hidden once installed or dismissed), bottom right
	if _install_available():
		_install_button(Vector2(content.size.x - 300.0 - shell_x(), area.end.y - UiKit.tap_h(self, 44.0) - 70.0))
	if _install_guide_open:
		_install_guide_panel()


func show_play() -> void:
	## PLAY (screen system 02; the hub stays cyan): three image-led choices - VS AI (primary; NEW GAME's faction ->
	## battlefield -> setup), ONLINE ROOMS, TRAINING.
	_last_show = show_play
	var area := shell_open("OOZE / PLAY", "play", Callable(), "vex")
	var x := shell_x()
	var top := page_title(area, "PLAY", "PICK YOUR FIGHT.")
	var gap := 16.0
	var cw := (content.size.x - x * 2.0 - gap * 2.0) / 3.0
	var ch := area.end.y - top - 18.0
	var done := TutorialDirector.done_count()
	var cards := [
		["CUSTOM MATCH", "VS AI", "Pick a faction, a battlefield and your rivals.", "res://assets/art/ui/bg_vex.jpg", "vex", show_factions],
		["WITH FRIENDS", "ONLINE ROOMS", "Create a room or join a friend's code.", "res://assets/art/ui/bg_null.jpg", "null", show_online],
		["LEARN THE CITY", "TRAINING", "%d / %d lessons done. Replay any lesson." % [done, TutorialDirector.TOTAL_LESSONS],
				"res://assets/art/campaign/vex-01.jpg", "", show_tutorial],
	]
	for i in range(cards.size()):
		var c := FrameCard.make(self, Vector2(cw, ch), "vex")
		c.art_frac = 0.52
		c.set_kicker(cards[i][0])
		c.set_title(cards[i][1])
		c.set_note(cards[i][2])
		c.set_art(cards[i][3])
		c.set_hero(cards[i][4])
		c.set_action("PLAY  →" if i == 0 else "OPEN")
		c.set_selected(i == 0)
		var go: Callable = cards[i][5]
		c.pressed.connect(func(): go.call_deferred())
		_shell_add(c, Vector2(x + i * (cw + gap), top))


func show_help() -> void:
	## HELP (screen system 24): the four things to know, and TRAINING.
	_last_show = show_help
	var area := shell_open("OOZE / HELP", _page if _page in ["home", "play", "armies", "campaign"] else "home", show_main)
	var x := shell_x()
	var y := page_title(area, "HELP", "OWN THE CROSSINGS.")
	var gap := 14.0
	var cw := (content.size.x - x * 2.0 - gap) / 2.0
	var tips := [
		["SEND UNITS", "Drag from your vat to a connected target. Pick 25 %, 50 %, 75 % or 100 % before sending."],
		["INSPECT & UPGRADE", "Tap a node to inspect it. Use UPGRADE in its panel, or double-tap a node you own."],
		["RELAYS", "Relays change the bridges. Check the next state before you fire one."],
		["ABILITIES", "A ready ability has a bright frame. Tap it, then choose a valid target."],
	]
	var chh := minf(110.0, (area.end.y - y - UiKit.tap_h(self, 48.0) - 40.0) / 2.0 - gap)
	for i in range(tips.size()):
		var p := Vector2(x + (i % 2) * (cw + gap), y + (i / 2) * (chh + gap))
		UiKit.panel(self, p, Vector2(cw, chh), shell_f)
		_shell_add(UiKit.label(self, tips[i][0], 17, UiKit.accent(shell_f), true), p + Vector2(16, 14))
		var l := UiKit.label(self, tips[i][1], 14, UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(cw - 32.0, 0)
		_shell_add(l, p + Vector2(16, 44))
	var by := y + 2.0 * (chh + gap) + 8.0
	_shell_add(UiKit.label(self, "Learn by doing.", 15, UiKit.MUTED), Vector2(x, by + 12.0))
	UiKit.btn(self, "TRAINING  →", Vector2(content.size.x - x - 220.0, by), Vector2(220, 48), show_tutorial, "primary", shell_f, 16)


static var _opt_tab := "game"                      # SETTINGS: the open tab (kept while the game runs)
const OPT_TABS := [["game", "GAME"], ["display", "DISPLAY"], ["debug", "DEBUG"]]
# PRIVACY: (the telemetry branch's rows go here) - its PRIVACY block comes before DEBUG: a ["privacy", "PRIVACY"] tab
# between DISPLAY and DEBUG above, and its 2-3 rows in show_options' "privacy" branch (_opt_row, like the others).


func show_options() -> void:
	## SETTINGS (screen system 23; the top bar's gear): tabs of rows, each row its name, what it does and its choices
	## (the current one lit, the words carrying the state). GAME: LAST STAND, ENEMY COUNTS. DISPLAY: GRAPHICS AUTO /
	## LOW RES / FULL and FRAME RATE AUTO / 30 / 60 (Alpha 21 OPT-RENDER, perf_profile.gd, user://settings.cfg), DETAIL.
	## DEBUG: DEBUG TOOLS (the Debug button and live sliders in matches), the progression TEST SWITCH. The rows scroll
	## (phones grow them to 44 pt). No audio settings exist yet, so no AUDIO tab and no restore-defaults. TERRITORY lives
	## in ARMIES > COSMETICS > CORE (0.19.2). DONE / BACK return to the page the gear was pressed on.
	_last_show = show_options                  # a resize that changes the phone sizing rebuilds it (_fit)
	var tab := _meta_open("options", show_main)
	var back := func(): _meta_back("options", show_main)
	var area := shell_open("OOZE / SETTINGS", tab, back, faction)
	_page = "options"
	var x := shell_x()
	var top := page_title(area, "SETTINGS", "TUNE YOUR EXPERIENCE.")
	var cx := x
	var chip_h := 0.0
	for t in OPT_TABS:
		var id: String = t[0]
		var c := UiKit.chip(self, t[1], Vector2(cx, top), func():
			_opt_tab = id
			show_options(), shell_f, _opt_tab == id)
		cx += c.size.x + 8.0
		chip_h = c.size.y
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	UiKit.btn(self, "DONE  →", Vector2(content.size.x - x - 200.0, fy), Vector2(200, 48), back, "primary", shell_f, 16)
	var y0 := top + chip_h + 12.0
	var col := _column(Vector2(x, y0), Vector2(content.size.x - x * 2.0, fy - 12.0 - y0))
	var w: float = col["w"]
	var n0 := content.get_child_count()
	var y := 0.0
	match _opt_tab:
		"display":
			var modes := []
			for m in PerfProfile.MODES:
				var md: String = m
				modes.append([("AUTO (%s)" % ("PHONE" if PerfProfile.is_phone() else "FULL")) if md == "auto" else str(PerfProfile.MODE_NAMES[md]),
						PerfProfile.mode() == md, func(): PerfProfile.set_mode(md)])
			y += _opt_row(y, w, "GRAPHICS", "AUTO: PHONE on phones and tablets, FULL on computers. LOW RES: 30 fps, no glow or shadows, fewer effects and lighter models - only for weak phones. From the next match.", modes)
			var low := PerfProfile.level() == "low"
			var fps := []
			for fm in PerfProfile.FPS_MODES:
				var fv: String = fm
				fps.append([("AUTO (%d)" % int(PerfProfile.PROFILES[PerfProfile.level()]["fps"])) if fv == "auto" else fv,
						PerfProfile.fps_mode() == fv, func(): PerfProfile.set_fps(fv)])
			y += _opt_row(y, w, "FRAME RATE", PerfProfile.fps_label() + ("  -  LOW RES stays at 30." if low else "  -  the cap while a match runs."), fps, low)
			y += _opt_row(y, w, "DETAIL", "LOW trims the river patches and vat residents - use it if the game makes your machine run hot.",
					[["FULL", not Rules.low_detail, func(): Rules.low_detail = false], ["LOW", Rules.low_detail, func(): Rules.low_detail = true]])
		"debug":
			# PRIVACY: (the telemetry branch's rows go here) - or in a "privacy" tab of their own, before this one
			y += _opt_row(y, w, "DEBUG TOOLS", "The Debug button and live sliders in matches.",
					[["ON", Rules.debug_tools, func(): Rules.debug_tools = true], ["OFF", not Rules.debug_tools, func(): Rules.debug_tools = false]])
			y += _opt_row(y, w, "TEST SWITCH  ·  LOCKS", "OFF: everything unlocked (the testing default). ON: a preview of the game as players will see it once the locks go live - skills and looks earned or bought (until the page closes).",   # PROGRESSION
					[["OFF", Progression.unlock_all, func(): Progression.unlock_all = true], ["ON", not Progression.unlock_all, func(): Progression.unlock_all = false]])
		_:
			# one game: BRAWL (Daniele, 0.18.7: "for now completely deactivate [SIEGE] ... brawl is our game (can
			# also remove mode selector)") - no MODE switch here, in SETUP, the lobby, the pause menu or Debug
			var ls := ("The map collapses ring by ring from %d:%02d." % [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60]) if Rules.last_stand \
					else ("No collapse; the %d:%02d safety net still ends a stalled match." % [int(Rules.MATCH_HARD_END) / 60, int(Rules.MATCH_HARD_END) % 60])
			y += _opt_row(y, w, "LAST STAND", ls, [["ON", Rules.last_stand, func(): Rules.last_stand = true],
					["OFF", not Rules.last_stand, func(): Rules.last_stand = false]])
			y += _opt_row(y, w, "ENEMY COUNTS", "SHOWN: every node's count, as in Alpha 11. HIDDEN: no unit numbers on enemy nodes, so you scout.",
					[["SHOWN", not Rules.hide_enemy_counts, func(): Rules.hide_enemy_counts = false],
					["HIDDEN", Rules.hide_enemy_counts, func(): Rules.hide_enemy_counts = true]])
	_column_end(col, n0, y)


func _opt_row(y: float, w: float, title_text: String, desc: String, opts: Array, off := false) -> float:
	## A SETTINGS row: its name over what it does (left), its choices [text, current, apply] as chips at the right, the
	## current one lit; `off` greys them out. A pick applies and redraws the page. Returns the row's height.
	var ch := UiKit.tap_h(self, 40.0)
	var widths := []
	var cw := 0.0
	for o in opts:
		var bw := maxf(64.0, UiKit.text_w(self, str(o[0]), 14, true) + 32.0)
		widths.append(bw)
		cw += bw + 8.0
	var tw := maxf(160.0, w - cw - 16.0)
	var l1 := UiKit.line_h(self, 16, true)
	var h := maxf(ch, l1 + 4.0 + UiKit.text_h(self, desc, 13, tw)) + 24.0
	_say(title_text, Vector2(0, y + 12.0), 16, UiKit.INK, 0.0, true)
	_say(desc, Vector2(0, y + 16.0 + l1), 13, UiKit.MUTED, tw)
	var bx := w - cw + 8.0
	for i in range(opts.size()):
		var apply: Callable = opts[i][2]
		var b := UiKit.btn(self, str(opts[i][0]), Vector2(bx, y + (h - ch) / 2.0), Vector2(widths[i], 40), func():
			apply.call()
			show_options(), "selected" if opts[i][1] else "secondary", shell_f, 14)
		b.disabled = off
		bx += float(widths[i]) + 8.0
	content.add_child(UiKit.rect(Vector2(0, y + h - 1.0), Vector2(w, 1.0), Color(UiKit.FRAME, 0.7)))
	return h


func show_factions() -> void:
	_last_show = show_factions                  # a resize that changes the phone sizing rebuilds it (_fit)
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
		label_at(rating, P(943, y + 17), 18, col if value > 1.001 else (Color("ffb12b") if value < 0.999 else Color("9cb2bf")), false)
		label_at(str(roundi(value * 100)) + "%", P(876, y + 17), 18, Color("9cb2bf"), false)   # tight inline pair - see label_at()
	frame(P(614, 534), P(469, 180))
	label_at("PERSISTENT TRAIT", P(636, 548), 22)
	neon_icon("efficient_routing", P(642, 602), P(62, 62), col)
	label_at(str(Rules.FACTION_TRAITS[faction][0]).to_upper(), P(719, 596), 24)
	label_at(Rules.FACTION_TRAITS[faction][1], P(719, 632), 18, Color("bed0da"), false)   # fixed one-liner, no autowrap - see label_at()
	label_at("COMING SOON", P(924, 685), 15, Color("7795a4"))
	# SKILLS 2.0: the faction's army preset (ARMIES) - each row opens ARMIES on this faction
	frame(P(1095, 134), P(550, 580))
	label_at("ABILITIES", P(1118, 152), 30)
	var eh := rh(50)
	var edit := nav_button("EDIT IN ARMIES  ›", P(1392, 144), P(232, eh), func(): show_armies(faction, show_factions))
	edit.add_theme_font_size_override("font_size", int(round(fsz(19) * K)))
	var lo := ArmyPresets.loadout_for(faction)
	var ids := [lo["active"], lo["map"], Rules.FACTION_ULTIMATE_ID[faction]]
	var tags := ["ACTIVE SKILL  ·  ARMY PRESET", "MAP SKILL  ·  ARMY PRESET", "ULTIMATE  ·  %s ONLY" % str(Rules.FACTION_NAMES[faction][0])]
	var card_y0 := 144.0 + eh + 14.0                  # below EDIT IN ARMIES, whatever it grew to
	var card_step := 160.0
	for i in range(3):
		var y := card_y0 + i * card_step
		var id: String = ids[i]
		nav_button("", P(1117, y), P(507, 150), func(): show_armies(faction, show_factions))
		content.add_child(neon_panel(P(1117, y), P(507, 150), col, false, Color("020a10e8")))
		skill_icon(id, P(1136, y + 33), P(84, 84), col)
		label_at(tags[i], P(1238, y + 14), 16, Color(col, 0.9), false)   # shares its line with the CD badge - see label_at()
		label_at(ArmyPresets.skill_name(id).to_upper(), P(1238, y + 36), 28)
		var desc := label_at(ArmyPresets.line(id), P(1238, y + 80), 19, Color("c5d2da"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wrap first, then fix the width
		desc.custom_minimum_size = Vector2(368 * K, 0)
		desc.size = Vector2(368 * K, 0)
		label_at(ArmyPresets.cd_text(id) + ("" if i == 2 else " CD"), P(1500, y + 16), 15, Color("ffd15c") if i == 2 else Color("9cb2bf"), false)
	for i in range(5):
		faction_tab(FACTIONS[i], P(34 + i * 324, 745), P(312, 101))
	nav_button("BACK", P(40, foot_y()), P(230, 58), show_main)
	nav_button("NEXT: BATTLEFIELD", P(1280, foot_y()), P(352, 58), show_maps, true)


func faction_tab(f: String, pos: Vector2, dims: Vector2) -> void:
	dims = tap(dims)                                  # grow once so the hit area and the visible edge agree
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


# ------------------------------------------------------------------ TUTORIAL (TUTORIAL-DESIGN.md §7)
func show_tutorial() -> void:
	_last_show = show_tutorial                  # a resize that changes the phone sizing rebuilds it (_fit)
	## The TRAINING page: nine lesson rows (any order, a tick when done), CONTINUE = the first lesson not done,
	## BACK. A lesson starts with the faction and colour picked here last (NEW GAME's picks).
	clear_page("city")
	_page = "tutorial"
	_tut_page = TutorialPage.new()
	_tut_page.standalone_backdrop = false             # the menu's own backdrop shows through
	_tut_page.set_faction(faction)
	_tut_page.set_mobile(mobile)
	_tut_page.set_lessons(TutorialDirector.lesson_rows())
	_tut_page.set_progress_note("" if TutorialDirector.saved else TutorialDirector.line("no_storage"))
	_tut_page.continue_pressed.connect(func(): _start_lesson(TutorialDirector.first_unfinished()))
	_tut_page.lesson_pressed.connect(_start_lesson)
	_tut_page.back_pressed.connect(show_main)
	add_child(_tut_page)


func _start_lesson(id: int) -> void:
	UiKit.save_last_faction(faction)                   # UI: HOME's hero is the faction played last
	main.SEAT_FACTIONS[main.HUMAN] = faction
	main.start_tutorial(id, false, faction, colour)


# ------------------------------------------------------------------ PROGRESSION (0.20.1, PROGRESSION-DESIGN §8)
func _balance(amount: int, currency: String, pos: Vector2, pt_k: float, named := true) -> RewardTicker:
	## A currency balance with its mark ("1 260 SCRAP"; named false: "1 260" + the mark), shown at once.
	var t := RewardTicker.make(amount, currency, func(n: float) -> float: return n * pt_k)
	t.sign = false
	t.named = named
	t.tooltip_text = Rules.CURRENCY_NAMES.get(currency, "")
	t.position = pos
	t.fit()
	content.add_child(t)
	t.play(true)
	return t


func _wrapped(text: String, pos: Vector2, size_value: int, col: Color, width: float) -> Label:
	## A label that wraps inside `width` (canvas units) at its designed size (a dense box - see label_at()).
	var l := label_at(text, pos, size_value, col, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width * K, 0)
	l.size = l.custom_minimum_size
	return l


func _bar(pos: Vector2, dims: Vector2, f: float, col: Color) -> void:
	## A plain progress bar (XP, challenge progress, faction vat wins).
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.07, 0.92)
	bg.position = pos
	bg.size = dims
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = pos
	fill.size = Vector2(dims.x * clampf(f, 0.0, 1.0), dims.y)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(fill)


func _profile_card(pos: Vector2) -> void:
	## MAIN, top right: level, XP to the next, both balances - tap for PROFILE; CHALLENGES under it with what is
	## ready to claim.
	var dims := P(360, 132)
	var lf := Progression.level_for(Progression.xp)
	nav_button("", pos, dims, show_profile, false, false)
	content.add_child(neon_panel(pos, dims, Color("18dae8"), false, Color("030c12ec")))
	label_at("LEVEL %d" % int(lf["level"]), pos + P(18, 8), 30, Color.WHITE, false)
	label_at("PROFILE", pos + P(260, 18), 16, Color("839da9"), false)
	_bar(pos + P(18, 56), P(324, 10), float(lf["into"]) / maxf(1.0, float(lf["need"])), Color("5fd7ff"))
	_balance(Progression.balance("soft"), "soft", pos + P(14, 80), 0.62 * K * 1.6, false)      # the marks name them
	_balance(Progression.balance("premium"), "premium", pos + P(196, 80), 0.62 * K * 1.6, false)
	var ready_n := Progression.claimable()
	var cb := nav_button("CHALLENGES" + ("  ·  %d TO CLAIM" % ready_n if ready_n > 0 else ""), pos + P(0, 146), P(360, 64),
			show_challenges, ready_n > 0)
	cb.add_theme_font_size_override("font_size", int(round(fsz(21) * K)))


func show_profile() -> void:
	_last_show = show_profile                  # a resize that changes the phone sizing rebuilds it (_fit)
	## PROFILE (screen system 21; the top bar's level block): level and XP, both balances and where they come from, per
	## faction plays / wins and the faction vat's progress (25 wins online or vs Veteran / Expert AI), and whether it is
	## saved on this device; CHALLENGES, LEADERBOARD, MATCH HISTORY and ACCOUNT at the foot (a guest's ACCOUNT lit: add
	## Google there). BACK returns to the page it was opened from.
	var tab := _meta_open("profile", show_main)
	var area := shell_open("OOZE / PROFILE", tab, func(): _meta_back("profile", show_main), faction)
	_page = "profile"
	var x := shell_x()
	var acc := UiKit.accent(shell_f)
	var top := page_title(area, "PROFILE", "YOUR SYNDICATE RECORD.")
	var a := _account()
	var bh := UiKit.tap_h(self, 46.0)
	var fy := area.end.y - bh - 12.0
	var bx := x
	for l in [["CHALLENGES", show_challenges], ["LEADERBOARD", show_leaderboard], ["MATCH HISTORY", show_history],
			["ACCOUNT", show_account]]:                  # 0.20.5: LEADERBOARD, HISTORY, ACCOUNT
		var bw := UiKit.text_w(self, l[0], 15, true) + 44.0
		var lit: bool = l[0] == "ACCOUNT" and a.state == "guest"
		UiKit.btn(self, l[0], Vector2(bx, fy), Vector2(bw, 46), l[1], "primary" if lit else "secondary", shell_f, 15)
		bx += bw + 10.0
	var gap := 18.0
	var all_w := content.size.x - x * 2.0
	var lw := floorf((all_w - gap) * 0.42)
	var ch := fy - 12.0 - top
	# left: level, XP, SCRAP and CHIPS and where they come from, where it is saved
	var left := _column(Vector2(x, top), Vector2(lw, ch))
	var w: float = left["w"]
	var n0 := content.get_child_count()
	var lf := Progression.level_for(Progression.xp)
	var hs := 88.0
	UiKit.hero(self, shell_f, Vector2(0, 0), Vector2(hs, hs), false)
	var ly := 10.0
	ly += _say("YOUR LEVEL", Vector2(hs + 14.0, ly), 12, acc, 0.0, true, 3) + 2.0
	ly += _say("LEVEL %d" % int(lf["level"]), Vector2(hs + 12.0, ly), 34, UiKit.INK, 0.0, true)
	var y := maxf(hs, ly) + 10.0
	UiKit.bar(self, Vector2(0, y), Vector2(w, 8), float(lf["into"]) / maxf(1.0, float(lf["need"])), shell_f)
	y += 16.0
	y += _say("%d / %d XP TO LEVEL %d" % [int(lf["into"]), int(lf["need"]), int(lf["level"]) + 1], Vector2(0, y), 14, UiKit.INK, 0.0, true) + 2.0
	var PR := Rules.PROGRESSION
	y += _say("EVERY LEVEL +%d SCRAP  ·  EVERY %dTH ALSO +%d CHIPS" % [int(PR["level_soft"]), int(PR["level_premium_every"]),
			int(PR["level_premium"])], Vector2(0, y), 12, UiKit.MUTED, w, true) + 14.0
	for cur in ["soft", "premium"]:
		content.add_child(UiKit.rect(Vector2(0, y), Vector2(w, 1.0), Color(UiKit.FRAME, 0.7)))
		y += 12.0
		var t := _ticker(Progression.balance(cur), cur, Vector2(-4.0, y))
		y += t.size.y + 4.0
		var why := ("Matches (from Veteran AI up), challenges, the tutorial and the campaign. A skill costs %s." % Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false)) if cur == "soft" \
				else ("Weekly challenges and every %dth level; the store later. For looks only - never skills." % int(PR["level_premium_every"]))
		y += _say(why, Vector2(0, y), 13, UiKit.MUTED, w) + 14.0
	if Progression.unlock_all:
		y += _say("UNLOCKS OPEN WHILE TESTING (SETTINGS > DEBUG > TEST SWITCH)", Vector2(0, y), 12, UiKit.STAR, w, true) + 10.0
	var note := "Progress saved on this device" if Progression.saved else "This browser keeps no storage: progress lasts until the page closes"
	if a.state == "linked":
		note = "Progress saved on this device and in your account"
	elif a.state == "guest":
		note = "Guest account: add Google (ACCOUNT) to keep your progress on any device"
	y += _say(note, Vector2(0, y), 13, UiKit.DIM if Progression.saved else UiKit.STAR, w)
	_column_end(left, n0, y)
	# right: the five factions - plays, wins, the faction vat
	var right := _column(Vector2(x + lw + gap, top), Vector2(all_w - lw - gap, ch))
	w = right["w"]
	n0 = content.get_child_count()
	y = 0.0
	y += _say("FACTIONS", Vector2(0, y), 18, UiKit.INK, 0.0, true) + 2.0
	var need: int = PR["faction_vat_wins"]
	y += _say("%d WINS WITH A FACTION UNLOCK ITS VAT  ·  ONLINE, OR VS VETERAN / EXPERT AI" % need, Vector2(0, y), 12,
			UiKit.MUTED, w, true) + 12.0
	var l1 := UiKit.line_h(self, 16, true)
	var l2 := UiKit.line_h(self, 13)
	var rh := maxf(62.0, l1 + l2 + 16.0)
	for f in FACTIONS:
		var fa := UiKit.accent(f)
		var st := Progression.faction_stats(f)
		var owned := Progression.owns("vat:faction:" + f)
		UiKit.panel(self, Vector2(0, y), Vector2(w, rh), f, false, Color(UiKit.BASE, 0.6))
		UiKit.hero(self, f, Vector2(8, y + 5.0), Vector2(rh - 10.0, rh - 10.0), false)
		var tx := rh + 8.0
		var mid := floorf(w * 0.5)
		var ty := y + (rh - l1 - l2) / 2.0
		_say(UiKit.NAMES[f], Vector2(tx, ty), 16, fa, 0.0, true)
		_say("PLAYED %d  ·  WON %d" % [int(st["plays"]), int(st["wins"])], Vector2(tx, ty + l1), 13, UiKit.INK)
		UiKit.bar(self, Vector2(mid, y + rh / 2.0 - 9.0), Vector2(w - mid - 14.0, 6), 1.0 if owned else float(st["vat_wins"]) / float(need), f)
		_say("VAT UNLOCKED" if owned else "VAT  %d / %d WINS" % [int(st["vat_wins"]), need], Vector2(mid, y + rh / 2.0 + 1.0), 12,
				fa if owned else UiKit.MUTED, 0.0, true)
		y += rh + 8.0
	_column_end(right, n0, y)


func show_challenges(just_claimed := "") -> void:
	_last_show = func(): show_challenges()                  # a resize that changes the phone sizing rebuilds it (_fit)
	## CHALLENGES (screen system 22): three daily and three weekly (the same for everyone, reset 00:00 UTC / Monday),
	## progress from any finished match (tutorial lessons excluded), CLAIM pays (the card counts it up), one daily REROLL
	## a day; PROFILE and PLAY at the foot. BACK returns to the page it was opened from (HOME's CHALLENGES, PROFILE...).
	var tab := _meta_open("challenges", show_main)
	var area := shell_open("OOZE / CHALLENGES", tab, func(): _meta_back("challenges", show_main), faction)
	_page = "challenges"
	var x := shell_x()
	var top := page_title(area, "CHALLENGES", "A LITTLE EXTRA PRESSURE.")
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var play := UiKit.btn(self, "PLAY  →", Vector2(content.size.x - x - 200.0, fy), Vector2(200, 48), show_play, "primary", shell_f, 16)
	var prof := UiKit.btn(self, "PROFILE", Vector2(play.position.x - 170.0, fy), Vector2(160, 48), show_profile, "secondary", shell_f, 15)
	var note := "Play any match to progress, then claim. One reroll a day, for a daily you would rather swap."
	var nw := prof.position.x - x - 16.0
	_say(note, Vector2(x, fy + maxf(0.0, (bh - UiKit.text_h(self, note, 13, nw)) / 2.0)), 13, UiKit.MUTED, nw)
	var gap := 18.0
	var cw := (content.size.x - x * 2.0 - gap) / 2.0
	var rerolled: bool = Progression.challenges.get("daily", {}).get("rerolled", false)
	for k in range(2):
		var kind: String = ["daily", "weekly"][k]
		var col := _column(Vector2(x + k * (cw + gap), top), Vector2(cw, fy - 12.0 - top))
		var w: float = col["w"]
		var n0 := content.get_child_count()
		_say(kind.to_upper(), Vector2(0, 0), 18, UiKit.INK, 0.0, true)
		var rs := "RESETS IN " + Progression.duration_text(Progression.seconds_to_reset(kind)).to_upper()
		_say(rs, Vector2(w - UiKit.text_w(self, rs, 12, true) - 4.0, (UiKit.line_h(self, 18, true) - UiKit.line_h(self, 12, true)) / 2.0),
				12, UiKit.MUTED, 0.0, true)
		var y := UiKit.line_h(self, 18, true) + 10.0
		for c in Progression.current_challenges(kind):
			y += _challenge_card(c, kind, Vector2(0, y), w, just_claimed, rerolled) + 10.0
		_column_end(col, n0, y)


func _challenge_card(c: Dictionary, kind: String, pos: Vector2, w: float, just_claimed: String, rerolled: bool) -> float:
	## One challenge on its card: the task, its progress bar and count, the reward; at the right CLAIM (done), REROLL (a
	## daily, once a day), the paid SCRAP counting up (just claimed), CLAIMED, or IN PROGRESS. Returns the card's height.
	var claimed: bool = c["claimed"]
	var done: bool = c["done"]
	var id: String = c["id"]
	var bw := 150.0
	var bh := UiKit.tap_h(self, 42.0)
	var text := str(c["text"])
	var th := UiKit.text_h(self, text, 15, w - 28.0, true)
	var lh := UiKit.line_h(self, 13)
	var reward := "%s  ·  +%d XP" % [Progression.amount_text(int(c["soft"])), int(c["xp"])]
	if int(c["premium"]) > 0:
		reward += "  ·  " + Progression.amount_text(int(c["premium"]), "premium")
	var rw := w - 28.0 - bw - 16.0
	var rwh := UiKit.text_h(self, reward, 13, rw)
	var body := maxf(bh, lh + 6.0 + rwh)
	var h := 14.0 + th + 8.0 + body + 14.0
	UiKit.panel(self, pos, Vector2(w, h), shell_f, done and not claimed, Color(UiKit.BASE, 0.6))
	_say(text, pos + Vector2(14, 14), 15, UiKit.DIM if claimed else UiKit.INK, w - 28.0, true)
	var by := pos.y + 14.0 + th + 8.0
	var cnt := "%d / %d" % [int(c["progress"]), int(c["target"])]
	var cnt_w := UiKit.text_w(self, cnt, 13, true)
	var bar_w := rw - cnt_w - 10.0
	UiKit.bar(self, Vector2(pos.x + 14.0, by + (lh - 6.0) / 2.0), Vector2(bar_w, 6), float(c["progress"]) / maxf(1.0, float(c["target"])), shell_f)
	_say(cnt, Vector2(pos.x + 14.0 + bar_w + 10.0, by), 13, UiKit.INK, 0.0, true)
	_say(reward, Vector2(pos.x + 14.0, by + lh + 6.0), 13, RewardTicker.COLOURS["soft"], rw)
	var bp := Vector2(pos.x + w - 14.0 - bw, by + (body - bh) / 2.0)
	var tag := ""
	if claimed:
		if id == just_claimed:                          # the paid SCRAP counts up on the card it came from
			var t := _ticker(int(c["soft"]), "soft", bp, false)
			t.position.x = pos.x + w - 14.0 - t.size.x
			t.position.y = by + (body - t.size.y) / 2.0
		else:
			tag = "CLAIMED"
	elif done:
		UiKit.btn(self, "CLAIM", bp, Vector2(bw, 42), func():
			if not Progression.claim(kind, id).is_empty():
				show_challenges(id), "primary", shell_f, 15)
	elif kind == "daily" and not rerolled:
		UiKit.btn(self, "REROLL", bp, Vector2(bw, 42), func():
			Progression.reroll(id)
			show_challenges(), "secondary", shell_f, 15)
	else:
		tag = "IN PROGRESS"
	if tag != "":
		_say(tag, Vector2(pos.x + w - 14.0 - UiKit.text_w(self, tag, 13, true), by + (body - UiKit.line_h(self, 13, true)) / 2.0), 13,
				UiKit.DIM, 0.0, true)
	return h


# ------------------------------------------------------------------ UI: parts of the online / progression / settings pages (Alpha 21)
var _meta_from := {}                               # page -> [the page it was opened from (its BACK), the tab kept lit]
var _meta_returning := false                       # a BACK is under way: the page it lands on keeps its own record
const META_TABS := ["home", "play", "armies", "campaign"]


func _meta_open(page: String, fallback: Callable) -> String:
	## PROFILE, CHALLENGES, LEADERBOARD, MATCH HISTORY, ACCOUNT and SETTINGS open from the shell (the level block, the
	## gear, HOME's CHALLENGES) and from each other: remembers the page each came from - its BACK - and returns the tab
	## to keep lit (that page's). A rebuild of the same page, or a BACK landing on it, keeps what it had.
	if not _meta_from.has(page) or (_page != page and not _meta_returning):
		var tab := "home"
		if is_instance_valid(nav_bar) and nav_bar.active in META_TABS:
			tab = nav_bar.active
		elif _meta_from.has(_page):
			tab = str(_meta_from[_page][1])
		_meta_from[page] = [_last_show if _last_show.is_valid() and _page != "" else fallback, tab]
	return str(_meta_from[page][1])


func _meta_back(page: String, fallback: Callable) -> void:
	var to: Callable = _meta_from[page][0] if _meta_from.has(page) else fallback
	_meta_returning = true
	to.call()
	_meta_returning = false


func _say(text: String, pos: Vector2, size: float, col := UiKit.INK, width := 0.0, head := false, spacing := 0) -> float:
	## A label at `pos` (wrapping inside `width` when one is given); returns its height.
	var l := UiKit.label(self, text, size, col, head, spacing)
	var h := UiKit.line_h(self, size, head)
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h = UiKit.text_h(self, text, size, width, head)
		l.custom_minimum_size = Vector2(width, 0)
		l.size = Vector2(width, h)
	UiKit.add(self, l, pos)
	return h


func _clip(text: String, pos: Vector2, size: float, col: Color, width: float, head := false) -> Label:
	## A one-line label cut to `width` with an ellipsis (names, map names in a row).
	var l := UiKit.label(self, text, size, col, head)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size = Vector2(maxf(width, 10.0), UiKit.line_h(self, size, head))
	return UiKit.add(self, l, pos) as Label


func _column(pos: Vector2, dims: Vector2, selected := false) -> Dictionary:
	## An opaque panel whose inside scrolls (phones grow rows to 44 pt and text to 12.5 pt, more than fits): build its
	## rows at (0, y) in `content`, then _column_end(col, before, height) moves them in. col["w"] = the width to fill.
	UiKit.panel(self, pos, dims, shell_f, selected)
	var col := stack_open(pos + Vector2(18.0, 12.0), dims - Vector2(26.0, 24.0))
	var sc: TouchScroll = col["scroll"]
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := sc.get_v_scroll_bar()                  # a slim accent grabber, not the default grey bar
	var track := UiKit.sb(Color(UiKit.FRAME, 0.35), Color(0, 0, 0, 0), 0, 2)
	var grab := UiKit.sb(Color(UiKit.accent(shell_f), 0.75), Color(0, 0, 0, 0), 0, 2)
	for s in [track, grab]:
		s.set_content_margin_all(2)
	bar.add_theme_stylebox_override("scroll", track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(k, grab)
	col["w"] = dims.x - 44.0
	return col


func _column_end(col: Dictionary, before: int, h: float) -> void:
	stack_capture(col, before)
	var inner: Control = col["inner"]
	inner.custom_minimum_size = Vector2(float(col["w"]), h + 6.0)
	inner.size = inner.custom_minimum_size


func _flow(nodes: Array, pos: Vector2, width: float, gap := 8.0) -> float:
	## Places the (already added) controls left to right from `pos`, wrapping at `width`; returns the height used.
	var cx := 0.0
	var cy := 0.0
	var row := 0.0
	for c in nodes:
		var s: Vector2 = (c as Control).size
		if cx > 0.0 and cx + s.x > width:
			cx = 0.0
			cy += row + gap
			row = 0.0
		(c as Control).position = pos + Vector2(cx, cy)
		cx += s.x + gap
		row = maxf(row, s.y)
	return cy + row


func _ticker(amount: int, cur: String, pos: Vector2, balance := true) -> RewardTicker:
	## SCRAP / CHIPS with its mark, sized in pt on phones: a balance ("1 260 SCRAP") shows at once, a claim ("+140
	## SCRAP") counts up.
	var p := UiKit.pt(self)
	var t := RewardTicker.make(amount, cur, func(n: float) -> float: return n * 0.8 / p if p > 0.0 else n * 1.1)
	t.sign = not balance
	t.tooltip_text = Rules.CURRENCY_NAMES.get(cur, "")
	t.fit()
	UiKit.add(self, t, pos)
	t.play(balance)
	return t


# ------------------------------------------------------------------ PROGRESSION: ACCOUNT, LEADERBOARD, MATCH HISTORY (0.20.5)
var _board_rows: Array = []                        # LEADERBOARD: the last answer
var _board_state := "idle"                         # idle | loading | done | offline
var _board_me := {}                                # LEADERBOARD: your own {rank, name, wins} when you're not in the list
var _history_online: Array = []                    # MATCH HISTORY: server rounds loaded so far
var _history_state := "idle"                       # idle | loading | done | offline
var _history_more := true                          # the server may have older rounds
var _account_note := ""                            # ACCOUNT: what the last action did ("Check your inbox ...")
var _account_hooked := false
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


func _account() -> Account:
	var a := Account.get_instance()
	if not _account_hooked:
		_account_hooked = true
		a.changed.connect(func():
			if _page in ["account", "profile"] and _last_show.is_valid():
				_last_show.call())
	return a


func _line_edit(pos: Vector2, dims: Vector2, placeholder: String, text := "") -> LineEdit:
	## A text field in the shell's style (ACCOUNT's name, ONLINE ROOMS' code frame), >= 44 pt tall on phones; the
	## phone's own keyboard opens on tap (the web build lays a native HTML field over it instead).
	dims.y = UiKit.tap_h(self, dims.y)
	var e := LineEdit.new()
	e.size = dims
	e.custom_minimum_size = dims
	e.placeholder_text = placeholder
	e.text = text
	e.add_theme_font_override("font", UiKit.HEAD)
	e.add_theme_font_size_override("font_size", UiKit.px(self, 17))
	e.add_theme_color_override("font_color", UiKit.INK)
	e.add_theme_color_override("font_placeholder_color", UiKit.DIM)
	e.add_theme_color_override("font_uneditable_color", UiKit.MUTED)
	var box := UiKit.sb(Color(UiKit.BASE, 0.96), UiKit.FRAME, 1, 6)
	box.set_content_margin_all(12)
	var lit := UiKit.sb(Color(UiKit.BASE, 0.96), UiKit.accent(shell_f), 2, 6)
	lit.set_content_margin_all(12)
	e.add_theme_stylebox_override("normal", box)
	e.add_theme_stylebox_override("read_only", box)
	e.add_theme_stylebox_override("focus", lit)
	e.virtual_keyboard_enabled = true
	UiKit.add(self, e, pos)
	return e


func show_account() -> void:
	_last_show = show_account                  # a resize that changes the phone sizing rebuilds it (_fit)
	## ACCOUNT (Daniele: an automatic guest, then Google to keep progress on any device - no email: "its a game why
	## would they want to do that"; a sign-in onto an account that already has progress keeps the account's). Guests are
	## never asked to verify anything; the game plays offline without it. Left: the account's state and your NAME (a
	## plain panel, never scrolled, so the web build's native name field stays exactly on its frame); right: sign in with
	## an account linked elsewhere. BACK returns to PROFILE (or wherever it was opened from).
	var a := _account()
	var tab := _meta_open("account", show_profile)
	var back := func():
		_account_note = ""
		_meta_back("account", show_profile)
	var area := shell_open("OOZE / ACCOUNT", tab, back, faction)
	_page = "account"
	var x := shell_x()
	var top := page_title(area, "ACCOUNT  ·  OPTIONAL, THE GAME PLAYS OFFLINE WITHOUT IT", "KEEP YOUR PROGRESS.")
	var web := OS.has_feature("web")
	var gap := 18.0
	var cw := (content.size.x - x * 2.0 - gap) / 2.0
	var ch := area.end.y - 14.0 - top
	UiKit.panel(self, Vector2(x, top), Vector2(cw, ch), shell_f)
	var px := x + 20.0
	var w := cw - 40.0
	var status := "OFFLINE  -  no connection; you play as a guest on this device"
	var col := Color("ffd15c")
	match a.state:
		"guest":
			status = "GUEST ACCOUNT  -  progress on this device, with a cloud copy"
			col = Color("9cb2bf")
		"linked":
			status = "SIGNED IN WITH GOOGLE" + (("  -  " + a.email) if a.email != "" else "")
			col = Color("6fff2a")
		"signing_in":
			status = "SIGNING IN ..."
	var y := top + 16.0
	y += _say(status, Vector2(px, y), 15, col, w, true) + 16.0
	y += _say("NAME", Vector2(px, y), 12, UiKit.MUTED, 0.0, true, 3) + 6.0
	var rw := UiKit.text_w(self, "RENAME", 15, true) + 44.0
	var fw := minf(w - rw - 12.0, 360.0)
	if web:
		# the web build: Godot's LineEdit doesn't raise a phone keyboard, and a field focused from Godot's own input
		# handling doesn't either on Android (outside the tap's gesture - Daniele, 0.20.10: "keyboard still doesn't
		# appear"). So the NAME box IS a native HTML <input> laid over it (_place_name_field): the tap lands on the DOM
		# element itself and the phone raises its keyboard. RENAME (or Enter) saves what it holds.
		var box := _line_edit(Vector2(px, y), Vector2(fw, 46), "", "")   # the frame the HTML field sits on (never typed into)
		box.editable = false
		box.focus_mode = Control.FOCUS_NONE
		_name_box = box
		_name_enabled = a.signed_in()
		_name_value = a.player_name
		_place_name_field.call_deferred()
		var rn := UiKit.btn(self, "RENAME", Vector2(px + fw + 12.0, y), Vector2(rw, 46), func(): _rename_from_field(), "secondary", shell_f, 15)
		rn.disabled = not a.signed_in()
		y += box.size.y
	else:
		var nm := _line_edit(Vector2(px, y), Vector2(fw, 46), "3-16 letters or digits", a.player_name)
		var rn := UiKit.btn(self, "RENAME", Vector2(px + fw + 12.0, y), Vector2(rw, 46), func():
			if await a.rename(nm.text):
				_account_note = "Name saved: " + a.player_name
			else:
				_account_note = a.last_error
			show_account(), "secondary", shell_f, 15)
		rn.disabled = not a.signed_in()
		nm.editable = a.signed_in()
		y += nm.size.y
	y += 22.0
	if web and not a.google_ready and a.state != "offline":
		a.check_google()                           # redraws through Account.changed when the answer differs
	var google_ok := web and a.google_ready
	if a.state == "guest":
		y += _say("KEEP YOUR PROGRESS ON ANY DEVICE", Vector2(px, y), 15, UiKit.INK, w, true) + 8.0
		var gw := UiKit.text_w(self, "ADD GOOGLE", 16, true) + 60.0
		var g := UiKit.btn(self, "ADD GOOGLE", Vector2(px, y), Vector2(gw, 48), func():
			if not await a.google(true):
				_account_note = a.last_error
				show_account(), "primary" if google_ok else "secondary", shell_f, 16)
		g.disabled = not google_ok
		y += g.size.y + 10.0
		var gn := "Your progress is already kept in this guest account; Google keeps it on your other devices too."
		if y + UiKit.text_h(self, gn, 13, w) < top + ch - 10.0:      # a short phone keeps the panel's edge clear
			_say(gn, Vector2(px, y), 13, UiKit.MUTED, w)
	# right: sign in with an account linked elsewhere - its progress replaces this device's
	var right := _column(Vector2(x + cw + gap, top), Vector2(cw, ch))
	var rcw: float = right["w"]
	var n0 := content.get_child_count()
	var ry := 4.0
	ry += _say("ALREADY HAVE AN ACCOUNT?", Vector2(0, ry), 15, UiKit.INK, rcw, true) + 6.0
	ry += _say("Sign in with the Google account you linked on another device. Its progress replaces this device's.",
			Vector2(0, ry), 14, UiKit.MUTED, rcw) + 14.0
	var sw := UiKit.text_w(self, "SIGN IN WITH GOOGLE", 15, true) + 50.0
	var gs := UiKit.btn(self, "SIGN IN WITH GOOGLE", Vector2(0, ry), Vector2(sw, 48), func():
		if not await a.google(false):
			_account_note = a.last_error
			show_account(), "secondary", shell_f, 15)
	gs.disabled = not google_ok
	ry += gs.size.y + 10.0
	if not web:
		ry += _say("Google sign-in works in the browser build.", Vector2(0, ry), 13, UiKit.DIM, rcw) + 8.0
	elif not a.google_ready and a.state != "offline":
		ry += _say("Google sign-in isn't available right now.", Vector2(0, ry), 13, UiKit.DIM, rcw) + 8.0
	if _account_note != "":
		ry += _say(_account_note, Vector2(0, ry + 6.0), 15, UiKit.STAR, rcw) + 14.0
	# PRIVACY: (the telemetry branch's rows go here) - SHARE PLAY & CRASH DATA, PRIVACY, DELETE ACCOUNT, below the Google
	# sign-in: `ry += ...` rows at (0, ry), width rcw; this column scrolls, so 2-3 rows fit on phones too.
	_column_end(right, n0, ry)


# The web build's name field: a native DOM <input> laid over ACCOUNT's NAME box (like web/room-ui.js's room code, the
# player taps the DOM element itself, so Android / iOS raise the keyboard). Defined at runtime, so the export's script
# list stays as it is. place() makes it or only moves it (a rebuild never steals focus from a field being typed in).
const NAME_UI_JS := """(()=>{if(window.OozeName)return;let result='';
const st=document.createElement('style');st.textContent=`#ooze-name-input{position:fixed;z-index:1100;box-sizing:border-box;margin:0;padding:0 10px;background:#020c12;color:#fff;border:2px solid #4e98ad;font-family:system-ui;font-weight:700;letter-spacing:1px;text-align:center;touch-action:manipulation;user-select:text;-webkit-user-select:text;outline:none}#ooze-name-input:focus{border-color:#19dce8}#ooze-name-input:disabled{opacity:.55}`;document.head.appendChild(st);
function place(fx,fy,fw,fh,v,on){const c=document.getElementById('canvas');if(!c)return;const b=c.getBoundingClientRect();let el=document.getElementById('ooze-name-input');
if(!el){el=document.createElement('input');el.id='ooze-name-input';el.type='text';el.inputMode='text';el.enterKeyHint='done';el.autocomplete='off';el.autocapitalize='characters';el.spellcheck=false;el.maxLength=16;el.setAttribute('aria-label','Your name');el.value=v||'';
el.addEventListener('input',()=>{const p=el.selectionStart;el.value=el.value.toUpperCase().replace(/[^A-Z0-9 _-]/g,'').slice(0,16);try{el.setSelectionRange(p,p)}catch(e){}});
el.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();const n=el.value.trim();if(/^[A-Z0-9 _-]{3,16}$/.test(n)){result=n;el.blur()}}});
el.addEventListener('pointerdown',e=>e.stopPropagation());document.body.appendChild(el)}
el.disabled=!on;el.style.left=(b.left+fx*b.width)+'px';el.style.top=(b.top+fy*b.height)+'px';el.style.width=(fw*b.width)+'px';el.style.height=(fh*b.height)+'px';el.style.fontSize=Math.max(14,Math.round(fh*b.height*0.42))+'px'}
window.OozeName={place:place,value:()=>(document.getElementById('ooze-name-input')?.value||'').trim(),take:()=>{const n=result;result='';return n},set:v=>{const el=document.getElementById('ooze-name-input');if(el)el.value=v},remove:()=>document.getElementById('ooze-name-input')?.remove()};})()"""

var _name_box: Control = null                      # ACCOUNT's NAME frame the HTML field sits on (web)
var _name_inline := false                          # the HTML field is on the page
var _name_enabled := false
var _name_value := ""
var _name_t := 0.0


func _place_name_field() -> void:
	## Web: lay the HTML name field over the NAME frame (canvas fractions -> CSS px in the page), or move it there.
	if not OS.has_feature("web") or _page != "account" or not is_instance_valid(_name_box):
		return
	JavaScriptBridge.eval(NAME_UI_JS, true)
	var t := _name_box.get_global_transform_with_canvas()
	var r := Rect2(t.origin, _name_box.size * t.get_scale())
	var vp := get_viewport().get_visible_rect().size
	JavaScriptBridge.eval("window.OozeName&&OozeName.place(%f,%f,%f,%f,%s,%s)" % [r.position.x / vp.x, r.position.y / vp.y,
			r.size.x / vp.x, r.size.y / vp.y, JSON.stringify(_name_value), "true" if _name_enabled else "false"], true)
	_name_inline = true


func _rename_from_field() -> void:
	var n := str(JavaScriptBridge.eval("window.OozeName?OozeName.value():''", true)).strip_edges().to_upper()
	await _rename_to(n)


func _rename_to(n: String) -> void:
	var a := _account()
	if await a.rename(n):
		_account_note = "Name saved: " + a.player_name
		JavaScriptBridge.eval("window.OozeName&&OozeName.set(%s)" % JSON.stringify(a.player_name), true)
		_name_value = a.player_name
	else:
		_account_note = a.last_error
	if _page == "account":
		show_account()


func _poll_name(dt: float) -> void:
	## Web, while the HTML name field is up: remove it off ACCOUNT, keep it on its frame, save on Enter.
	if not _name_inline:
		return
	if _page != "account":
		JavaScriptBridge.eval("window.OozeName&&OozeName.remove()", true)
		_name_inline = false
		return
	_name_t -= dt
	if _name_t <= 0.0:
		_name_t = 0.4
		_place_name_field()
	var n := str(JavaScriptBridge.eval("window.OozeName?OozeName.take():''", true))
	if n != "":
		_rename_to(n)


# 0.20.11: "on the main screen a guide on how to [add to home screen] so new users can figure it" (Daniele -
# chat and keyboards work properly only in the installed home-screen app). Web build only; the small JS
# interface below detects display-mode: standalone / navigator.standalone, the platform from the user
# agent, and captures `beforeinstallprompt` so Android Chrome can install directly instead of a menu hunt.
const INSTALL_JS := """(()=>{if(window.OozeInstall)return;
function standalone(){try{return window.matchMedia('(display-mode: standalone)').matches||navigator.standalone===true}catch(e){return false}}
function platform(){const ua=navigator.userAgent||'';if(/iPad|iPhone|iPod/.test(ua)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1))return'ios';if(/Android/.test(ua))return'android';return'desktop'}
let deferred=null;
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferred=e});
let hidden=false;try{hidden=localStorage.getItem('ooze20-hide-install')==='1'}catch(e){}
window.OozeInstall={standalone:()=>standalone(),platform:()=>platform(),canPrompt:()=>deferred!==null,
hidden:()=>hidden,hide:()=>{hidden=true;try{localStorage.setItem('ooze20-hide-install','1')}catch(e){}},
install:()=>{if(!deferred)return false;deferred.prompt();deferred=null;return true}};})()"""


func _install_ui():
	## null off the web build, or wherever JavaScriptBridge itself is missing (native builds).
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return null
	JavaScriptBridge.eval(INSTALL_JS, true)
	return JavaScriptBridge.get_interface("OozeInstall")


var _install_guide_open := false
var _install_platform := ""                          # cached when the guide opens: "ios" | "android"


func _install_available() -> bool:
	## MAIN only: web build, phone browsers only (hidden on desktop), not already installed, not dismissed.
	var ui = _install_ui()
	if ui == null or bool(ui.standalone()) or bool(ui.hidden()):
		return false
	return str(ui.platform()) in ["ios", "android"]


func _install_button(pos: Vector2) -> void:
	var b := nav_button("INSTALL THE GAME", pos, P(380, 56), func():
		var ui = _install_ui()
		_install_platform = str(ui.platform()) if ui != null else "android"
		_install_guide_open = true
		show_main())
	b.add_theme_font_size_override("font_size", int(round(fsz(20) * K)))


func _share_glyph(pos: Vector2, size_value: float) -> Control:
	## A small share-icon glyph for the iOS steps (Safari's Share button): a bordered box with an upward
	## arrow - no new art asset, just the UI font's arrow glyph over a thin outline square.
	var box := PanelContainer.new()
	box.position = pos
	box.custom_minimum_size = Vector2(size_value, size_value)
	box.size = Vector2(size_value, size_value)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_width_left = 2
	st.border_width_right = 2
	st.border_width_top = 2
	st.border_width_bottom = 2
	st.border_color = Color("e6f4f8")
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	box.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = "↑"
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", int(size_value * 0.7))
	l.add_theme_color_override("font_color", Color("e6f4f8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(l)
	content.add_child(box)
	return box


func _install_guide_panel() -> void:
	## MAIN's overlay (drawn last, so it sits on top): the right steps for this platform first, an
	## "INSTALL NOW" direct prompt where Chrome offered one (beforeinstallprompt), and "don't show again"
	## (localStorage, wrapped in try/catch on the JS side).
	var ui = _install_ui()
	if ui == null:                                    # shouldn't happen (the button that opens this needs it)
		_install_guide_open = false
		return
	var pos := P(490, 210)
	var dims := P(700, 420)
	content.add_child(neon_panel(pos, dims, Color("18dae8"), true, Color("030c12f0")))
	label_at("INSTALL THE GAME", pos + P(28, 20), 30, Color.WHITE, false)
	_wrapped("Chat and the keyboard work properly only in the installed app.", pos + P(28, 58), 17, Color("839da9"), dims.x - 56.0)
	var ios := _install_platform == "ios"
	var y := 104.0
	if ios:
		_share_glyph(pos + P(28, y), 40.0)
		_wrapped("1. In Safari's toolbar, tap the Share icon (a square with an arrow).", pos + P(84, y + 6.0), 19, Color("e6f4f8"), dims.x - 112.0)
		y += 66.0
		_wrapped("2. Scroll down and tap \"Add to Home Screen\".", pos + P(28, y), 19, Color("e6f4f8"), dims.x - 56.0)
		y += 46.0
		_wrapped("3. Tap \"Add\" - the game then opens full-screen from your Home Screen.", pos + P(28, y), 19, Color("e6f4f8"), dims.x - 56.0)
	else:
		_wrapped("1. Open Chrome's menu (the ⋮  in the top right).", pos + P(28, y), 19, Color("e6f4f8"), dims.x - 56.0)
		y += 46.0
		_wrapped("2. Tap \"Add to Home screen\" or \"Install app\".", pos + P(28, y), 19, Color("e6f4f8"), dims.x - 56.0)
		y += 46.0
		_wrapped("3. Confirm \"Install\" / \"Add\".", pos + P(28, y), 19, Color("e6f4f8"), dims.x - 56.0)
		y += 54.0
		if bool(ui.canPrompt()):
			nav_button("INSTALL NOW", pos + P(28, y), P(260, 58), func():
				_install_ui().install()
				_install_guide_open = false
				show_main(), true)
	nav_button("DON'T SHOW AGAIN", pos + P(28, dims.y - 78.0), P(300, 52), func():
		_install_ui().hide()
		_install_guide_open = false
		show_main())
	nav_button("CLOSE", pos + P(dims.x - 200.0, dims.y - 78.0), P(172, 52), func():
		_install_guide_open = false
		show_main())


func show_leaderboard() -> void:
	_last_show = show_leaderboard              # a resize that changes the phone sizing rebuilds it (_fit)
	## LEADERBOARD: WINS THIS SEASON (the UTC month) - online wins in server rooms with two or more players, written by
	## the server only. Reads it when opened (LOADING / needs a connection / no wins yet say so); YOU, when you're not on
	## the list, as a row of its own (0.20.13; "-" until you win one). REFRESH reads it again.
	var tab := _meta_open("leaderboard", show_profile)
	var back := func():
		_board_state = "idle"
		_meta_back("leaderboard", show_profile)
	var area := shell_open("OOZE / LEADERBOARD", tab, back, faction)
	_page = "leaderboard"
	var x := shell_x()
	var now := Time.get_datetime_dict_from_system(true)
	var top := page_title(area, "LEADERBOARD  ·  %s %d" % [MONTHS[int(now["month"]) - 1], int(now["year"])], "WINS THIS SEASON.")
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var rb := UiKit.btn(self, "REFRESH", Vector2(content.size.x - x - 180.0, fy), Vector2(180, 48), func():
		_board_state = "idle"
		show_leaderboard(), "secondary", shell_f, 15)
	var nt := "Online wins in server rooms with two or more players, written by the server only."
	var nw := rb.position.x - x - 16.0
	_say(nt, Vector2(x, fy + maxf(0.0, (bh - UiKit.text_h(self, nt, 13, nw)) / 2.0)), 13, UiKit.MUTED, nw)
	var col := _column(Vector2(x, top), Vector2(content.size.x - x * 2.0, fy - 12.0 - top))
	var w: float = col["w"]
	var n0 := content.get_child_count()
	var y := 4.0
	if _board_state == "idle":
		_board_state = "loading"
		_load_board.call_deferred()                    # after this page is built (an offline answer comes back at once)
	if _board_state == "loading":
		y += _say("LOADING ...", Vector2(4, y), 16, UiKit.MUTED, 0.0, true)
	elif _board_state == "offline":
		y += _say("The leaderboard needs a connection.", Vector2(4, y), 16, UiKit.STAR, w)
	elif _board_rows.is_empty():
		y += _say("No wins yet this season - win an online match against another player to open the board.", Vector2(4, y), 16,
				UiKit.MUTED, w)
	else:
		y = 0.0
		for row in _board_rows:
			var me := bool(row.get("is_me", false))
			y += _board_row("#%d" % int(row.get("rank", 0)), str(row.get("name", "")) + ("  (YOU)" if me else ""),
					"%d WINS" % int(row.get("wins", 0)), Vector2(0, y), w, me) + 6.0
		if not _board_me.is_empty():                  # 0.20.13: YOU, when you're not on the list - a row like the rest
			var wins := int(_board_me.get("wins", 0))
			y += 8.0
			y += _board_row("#%d" % int(_board_me.get("rank", 0)) if wins > 0 else "-", str(_board_me.get("name", "")) + "  (YOU)"
					+ ("" if wins > 0 else "  ·  win an online round vs a player"), "%d WINS" % wins, Vector2(0, y), w, true, UiKit.STAR) + 6.0
	_column_end(col, n0, y)


func _board_row(rank: String, who: String, wins: String, pos: Vector2, w: float, me: bool, wins_col := UiKit.INK) -> float:
	## One LEADERBOARD row: the rank, the name, the wins; your own row lit. Returns its height.
	var lh := UiKit.line_h(self, 16, true)
	var h := maxf(48.0, lh + 18.0)
	UiKit.panel(self, pos, Vector2(w, h), shell_f, me, Color(UiKit.BASE, 0.6))
	var ty := pos.y + (h - lh) / 2.0
	_say(rank, Vector2(pos.x + 16.0, ty), 16, UiKit.STAR, 0.0, true)
	var nx := 16.0 + UiKit.text_w(self, "#0000", 16, true) + 24.0
	var ww := UiKit.text_w(self, wins, 16, true)
	_clip(who, Vector2(pos.x + nx, ty), 16, UiKit.INK, w - nx - ww - 40.0, true)
	_say(wins, Vector2(pos.x + w - 16.0 - ww, ty), 16, wins_col if not me or wins_col != UiKit.INK else UiKit.accent(shell_f), 0.0, true)
	return h


func _load_board() -> void:
	var rows := await _account().leaderboard("season_wins", 50)
	_board_rows = rows
	_board_me = {}
	if not rows.any(func(r): return bool(r.get("is_me", false))):   # not on the list: say where you stand (0.20.13)
		_board_me = await _account().my_season_wins()
	_board_state = "done" if _account().state != "offline" or not rows.is_empty() else "offline"
	if _page == "leaderboard":
		show_leaderboard()


func show_history() -> void:
	_last_show = show_history                  # a resize that changes the phone sizing rebuilds it (_fit)
	## MATCH HISTORY (Daniele, 0.20.5): your recent matches - this device's log (offline, AI, and online rounds played
	## here) plus the server's record of your online rounds from other devices; newest first, ONLINE / OFFLINE tags,
	## WIN / LOSS / DRAW in words (and colour). MORE loads older online rounds.
	var a := _account()
	var tab := _meta_open("history", show_profile)
	var back := func():
		_history_state = "idle"
		_history_online = []
		_meta_back("history", show_profile)
	var area := shell_open("OOZE / MATCH HISTORY", tab, back, faction)
	_page = "history"
	var x := shell_x()
	var top := page_title(area, "MATCH HISTORY", "YOUR RECENT MATCHES.")
	if _history_state == "idle" and a.signed_in():
		_history_state = "loading"
		_load_history.call_deferred(false)             # after this page is built
	var list := Progression.merge_history(Progression.history, _history_online)
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var nx := content.size.x - x
	if a.signed_in() and _history_more and not _history_online.is_empty():
		var mb := UiKit.btn(self, "MORE", Vector2(nx - 160.0, fy), Vector2(160, 48), func(): _load_history(true), "secondary", shell_f, 15)
		nx = mb.position.x - 16.0
	var nt := "This device" + (" + your account's online rounds" if a.signed_in() else "") \
			+ ("  ·  LOADING ONLINE ROUNDS ..." if _history_state == "loading" else "")
	_say(nt, Vector2(x, fy + maxf(0.0, (bh - UiKit.text_h(self, nt, 13, nx - x)) / 2.0)), 13, UiKit.MUTED, nx - x)
	var col := _column(Vector2(x, top), Vector2(content.size.x - x * 2.0, fy - 12.0 - top))
	var w: float = col["w"]
	var n0 := content.get_child_count()
	var y := 0.0
	if list.is_empty():
		y += _say("No matches yet - finish one and it shows here.", Vector2(4, 4), 16, UiKit.MUTED, w) + 4.0
	else:
		var names := _map_names()
		for h in list:
			y += _history_row(h, names, Vector2(0, y), w) + 6.0
	_column_end(col, n0, y)


func _history_row(h: Dictionary, names: Dictionary, pos: Vector2, w: float) -> float:
	## One match: ONLINE / OFFLINE and when, the map and mode and how long, everyone's faction mark and name, the result.
	## Returns the row's height.
	var won := bool(h.get("won", false))
	var draw := bool(h.get("draw", false))
	var res := "DRAW" if draw else ("WIN" if won else "LOSS")
	var rc := Color("9cb2bf") if draw else (Color("6fff2a") if won else Color("ff5a4a"))
	var l1 := UiKit.line_h(self, 15, true)
	var l2 := UiKit.line_h(self, 13)
	var rh := maxf(64.0, l1 + l2 + 20.0)
	UiKit.panel(self, pos, Vector2(w, rh), shell_f, false, Color(UiKit.BASE, 0.6))
	content.add_child(UiKit.rect(pos + Vector2(0, 6), Vector2(4, rh - 12.0), rc))   # the result at the row's edge too
	var ty := pos.y + (rh - l1 - l2) / 2.0
	var online := bool(h.get("online", false))
	var c1 := 16.0
	_say("ONLINE" if online else "OFFLINE", Vector2(pos.x + c1, ty + 2.0), 12, Color("5fd7ff") if online else UiKit.MUTED, 0.0, true, 2)
	_say(_date_text(int(h.get("t", 0))), Vector2(pos.x + c1, ty + l1), 13, UiKit.MUTED)
	var c2 := c1 + maxf(UiKit.text_w(self, "OFFLINE", 12, true) + 20.0, UiKit.text_w(self, "30 SEP 23:59", 13)) + 20.0
	var c3 := c2 + floorf(w * 0.28)
	var code := str(h.get("map", ""))
	_clip(code + "  " + str(names.get(code, "")), Vector2(pos.x + c2, ty), 15, UiKit.INK, c3 - c2 - 14.0, true)
	var dur := int(h.get("duration_s", 0))
	_clip("%s  ·  %d:%02d" % [str(Menu.MODE_NAMES.get(str(h.get("mode", "")), str(h.get("mode", "")))), dur / 60, dur % 60],
			Vector2(pos.x + c2, ty + l1), 13, UiKit.MUTED, c3 - c2 - 14.0)
	var res_w := UiKit.text_w(self, "LOSS", 20, true) + 24.0
	var players: Array = h.get("players", []).filter(func(p): return p is Dictionary)
	var pw := minf(130.0, (w - c3 - res_w - 16.0) / float(maxi(1, players.size())))
	var ic := minf(26.0, rh - l2 - 16.0)
	var py := pos.y + (rh - ic - 2.0 - UiKit.line_h(self, 12)) / 2.0
	var px := pos.x + c3
	for p in players:
		var f := str(p.get("faction", "null"))
		var tex := Hud.emblem_texture(f) if Rules.FACTIONS.has(f) else null
		if tex != null:
			var em := TextureRect.new()
			em.texture = tex
			em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			em.size = Vector2(ic, ic)
			em.modulate = UiKit.accent(f)
			em.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UiKit.add(self, em, Vector2(px, py))
		var me := bool(p.get("is_me", false))
		var who := "YOU" if me and str(p.get("name", "")) == "" else str(p.get("name", ""))
		if str(p.get("ai_level", "")) != "":
			who = "AI" if str(p["ai_level"]) == "AI" else "AI " + str(p["ai_level"]).to_upper()
		elif who == "":
			who = "PLAYER"
		_clip(who, Vector2(px, py + ic + 2.0), 12, UiKit.INK if me else UiKit.MUTED, pw - 8.0)
		px += pw
	_say(res, Vector2(pos.x + w - 16.0 - UiKit.text_w(self, res, 20, true), pos.y + (rh - UiKit.line_h(self, 20, true)) / 2.0), 20, rc, 0.0, true)
	return rh


func _load_history(more: bool) -> void:
	var before := ""
	if more and not _history_online.is_empty():
		before = str(_history_online[-1].get("started_at", ""))
	var rows := await _account().match_history(20, before)
	_history_online = (_history_online if more else []) + rows
	_history_more = rows.size() >= 20
	_history_state = "done"
	if _page == "history":
		show_history()


func _placed(c: Control) -> Control:
	## neon_panel() hands back an unparented panel; stack_add() moves nodes out of `content`.
	content.add_child(c)
	return c


func _map_names() -> Dictionary:
	## map code -> its name, from the pool's file names ("C-05-karth-carousel.json" -> "KARTH CAROUSEL").
	var out := {}
	for p in MapPool.all():
		var f: String = p.get_file().get_basename()
		out[f.substr(0, 4)] = f.substr(5).replace("-", " ").to_upper()
	return out


static func _date_text(t: int) -> String:
	## "27 SEP 14:05" in the player's own time zone.
	if t <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(t + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%d %s %02d:%02d" % [int(d["day"]), MONTHS[int(d["month"]) - 1], int(d["hour"]), int(d["minute"])]


func _buy_prompt(item: String, title: String, line: String, back: Callable) -> void:
	## UNLOCK sheet over the page: the price in SCRAP (and in CHIPS when it is sold for them), what you have, CANCEL.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.position = Vector2(-3000, -3000)
	dim.size = Vector2(9000, 9000)
	content.add_child(dim)
	var pp := P(436, 250)
	var pd := P(800, 440)
	content.add_child(neon_panel(pp, pd, Color("ffd15c"), true, Color("0a1216f4")))
	label_at("UNLOCK " + title, pp + P(32, 24), 34, Color.WHITE, false)
	var d := label_at(line, pp + P(32, 84), 19, Color("c5d2da"), false)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(pd.x - 64 * K, 0)
	d.size = d.custom_minimum_size
	var price := Progression.price(item)
	var y := 170.0
	for cur in ["soft", "premium"]:
		if not price.has(cur):
			continue
		var cost: int = price[cur]
		var have := Progression.balance(cur)
		var c: String = cur
		var b := nav_button("BUY  ·  " + Progression.amount_text(cost, cur, false), pp + P(32, y), P(420, 66), func():
			if Progression.spend(item, c):
				back.call(), cur == "soft")
		b.disabled = have < cost
		label_at("YOU HAVE " + Progression.amount_text(have, cur, false) if have >= cost else "YOU HAVE %s - %s SHORT" % [
				Progression.amount_text(have, cur, false), Progression.amount_text(cost - have, cur, false)],
				pp + P(476, y + 22), 17, Color("9cb2bf") if have >= cost else Color("ffb12b"), false)
		y += 86.0
	nav_button("CANCEL", pp + P(32, 350), P(220, 60), back)


func _cosmetic_path(family: String, id: String) -> String:
	## A locked cosmetic's way in, for its row: the faction vat's wins, the tutorial for the Graduate vat.
	var item := Progression.cosmetic_item(family, id, _army)
	if item == "vat:graduate":
		return TutorialDirector.line("locked_cosmetic").to_upper()
	if family == "vat" and id == "faction":
		return "%d / %d WINS AS %s, ITS CAMPAIGN, OR UNLOCK" % [int(Progression.faction_stats(_army)["vat_wins"]),
				int(Rules.PROGRESSION["faction_vat_wins"]), "VIRIDIAN" if _army == "bloom" else _army.to_upper()]
	return "UNLOCK WITH SCRAP OR CHIPS"


# ------------------------------------------------------------------ CAMPAIGN (CAMPAIGN-DESIGN.md §3)
# CAMPAIGN: the campaign map page (CampaignPage, its own canvas and 3D diorama over the backdrop); also opened as
# menu_open = "campaign" after a mission relaunch. Screenshot / test args: --campaign-all (every playable mission
# open), --campaign-cfg=<path> (read progress from another file), --campaign-district=<id>, --campaign-card=<key>.
var _camp_page: CampaignPage


func show_campaign() -> void:
	clear_page("city")
	_page = "campaign"
	for arg in OS.get_cmdline_user_args():
		if arg == "--campaign-all":
			Campaign.all_open = true
		elif arg.begins_with("--campaign-cfg="):
			Campaign.path = arg.substr(15)
	_camp_page = CampaignPage.new()
	_camp_page.standalone_backdrop = false
	_camp_page.set_faction(faction)
	_camp_page.set_mobile(mobile)
	_camp_page.back_pressed.connect(show_main)
	_camp_page.play_pressed.connect(func(key: String):
		UiKit.save_last_faction(_camp_page.faction)     # UI: HOME's hero is the faction played last
		if main.has_method("start_mission"):          # main.gd's mission launcher (the campaign session adds it)
			main.call("start_mission", key, colour))
	add_child(_camp_page)
	content.tree_exiting.connect(_camp_page.queue_free)   # the next page's clear_page takes it away
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaign-district="):
			var id := arg.substr(20)
			for i in range(Campaign.districts(_camp_page.faction).size()):
				if str(Campaign.districts(_camp_page.faction)[i]["id"]) == id:
					_camp_page.show_district(i, false)
		elif arg.begins_with("--campaign-card="):
			_camp_page.open_card(arg.substr(16))


# ------------------------------------------------------------------ ARMIES (army presets, SKILLS 2.0)
func show_armies(f: String = "", back: Callable = Callable()) -> void:
	_last_show = func(): show_armies(f, back)                  # a resize that changes the phone sizing rebuilds it (_fit)
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
	label_at("ULTIMATE  ·  %s ONLY  ·  FIXED" % str(Rules.FACTION_NAMES[_army][0]), up + P(146, 14), 18, Color("ffd15c"), false)   # single-line, fixed-width box - see label_at()
	label_at(ArmyPresets.skill_name(ult).to_upper(), up + P(146, 36), 34)
	var ud := label_at(str(Rules.SKILLS[ult]["desc"]), up + P(146, 84), 19, Color("c5d2da"), false)   # fixed-height box - see label_at()
	ud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ud.custom_minimum_size = Vector2(1050 * K, 0)
	ud.size = Vector2(1050 * K, 0)
	label_at("CHARGES IN ~%d s (AT LEAST %d s); ENEMY KILLS SPEED IT UP" % [int(Rules.ULT_CHARGE_TIME), int(Rules.ULT_MIN_TIME)], up + P(700, 16), 15, Color("9cb2bf"), false)
	# the two pools
	var rows := [["active", "ACTIVE SKILL  ·  PICK ONE", "combat skills, every map", Rules.ACTIVE_SKILLS, 326],
			["map", "MAP SKILL  ·  PICK ONE", "network skills; relay skills need a map with relays", Rules.MAP_SKILLS, 576]]
	for row in rows:
		var slot: String = row[0]
		var y: int = row[4]
		# this whole two-pool grid (10 cards across two fixed rows) is a desktop layout that doesn't
		# reflow for a phone - the row headers keep their designed size (grow=false) rather than the
		# rows above/below each other overlapping; the cards themselves are already well over 44 pt
		label_at(row[1], P(415, y), 24, Color.WHITE, false)
		label_at(row[2], P(790, y + 6), 17, Color("8fb3c2"), false)
		var pool: Array = row[3]
		for i in range(pool.size()):
			_skill_card(pool[i], slot, lo[slot] == pool[i], P(415 + i * 247, y + 32), P(234, 206), fc)
	# foot: back, cosmetics, reset, the save state
	nav_button("BACK", P(40, foot_y()), P(230, 58), func(): _leave_armies())
	nav_button("COSMETICS", P(290, foot_y()), P(230, 58), func(): show_cosmetics(_army))
	var rs := nav_button("RESET %s TO DEFAULT" % ("VIRIDIAN" if _army == "bloom" else _army.to_upper()), P(540, foot_y()), P(420, 58), func():
		ArmyPresets.reset(_army)
		_preset_changed()
		show_armies())
	rs.add_theme_font_size_override("font_size", int(round(fsz(20) * K)))
	rs.disabled = ArmyPresets.is_default(_army)
	var note := "Saved on this device" if ArmyPresets.saved else "This browser keeps no storage: your picks last until the page closes"
	label_at(note, P(985, foot_y() + 18.0), 18, Color("7795a4") if ArmyPresets.saved else Color("ffd15c"), false)


func _skill_card(id: String, slot: String, chosen: bool, pos: Vector2, dims: Vector2, fc: Color) -> void:
	## One pool skill as a tap target: icon, cooldown, name, one line in shown numbers (the full sentence as
	## its tooltip); the equipped one glows with a check.
	var sk: Dictionary = Rules.SKILLS[id]
	var locked := not Progression.is_unlocked("skill:" + id)   # PROGRESSION: tap a locked skill to unlock it
	var b := nav_button("", pos, dims, func():
		if locked:
			_buy_prompt("skill:" + id, ArmyPresets.skill_name(id).to_upper(),
					"Unlocks %s for every faction's loadout. Skills are earned with SCRAP only." % ArmyPresets.skill_name(id),
					func(): show_armies())
			return
		ArmyPresets.set_pick(_army, slot, id)
		_preset_changed()
		show_armies())
	b.tooltip_text = str(sk["desc"])
	content.add_child(neon_panel(pos, dims, fc, chosen, Color("08202aea") if chosen else Color("020a10e4")))
	skill_icon(id, pos + P(16, 16), P(78, 78), fc if chosen else Color("c9dbe3"))
	label_at("%d s CD" % int(sk["cd"]), pos + P(106, 18), 20, Color("9cb2bf"), false)   # shares this corner with the check mark - see label_at()
	if chosen:
		label_at("EQUIPPED", pos + P(106, 46), 17, fc, false)
		neon_icon("check", pos + P(dims.x / K - 34, 12), P(20, 20), fc)
	if locked:
		label_at("LOCKED", pos + P(106, 46), 17, Color("e08a3a"), false)
		label_at(Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false), pos + P(106, 70), 15, Color("e08a3a"), false)
	elif sk.get("needs_relays", false):
		label_at("NEEDS RELAYS", pos + P(106, 70), 15, Color("ffb12b"), false)
	label_at(ArmyPresets.skill_name(id).to_upper(), pos + P(16, 104), 24, Color.WHITE if chosen else Color("dbe6ec"), false)   # fixed card height - see label_at()
	var d := label_at(ArmyPresets.line(id), pos + P(16, 138), 18, Color("c5d2da"), false)
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


# ------------------------------------------------------------------ ARMIES > COSMETICS (0.19.0, spec E/I)
const COSMETIC_FAMILIES := ["vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const COSMETIC_FAMILY_LABEL := {"vat": "VAT LOOK", "machinegoon": "MACHINEGOON", "laser": "LASER",
		"forge": "FORGE", "monster_hub": "MONSTER HUB", "monster": "MONSTER"}


func show_cosmetics(f: String = "") -> void:
	_last_show = func(): show_cosmetics(f)                  # a resize that changes the phone sizing rebuilds it (_fit)
	## A look per structure family, per faction (GAME-BIBLE sec17; Daniele, 2026-09-27): DEFAULT / the
	## faction set / GRADUATE / the skin lines for vats, DEFAULT / SPITTER / PEPPERBOX for the
	## Machinegoon, and so on - saved in user://armies.cfg (ArmyPresets), applied at match start
	## (main.gd's Cosmetics.set_loadout) and sent along with the skill loadout online (ArmyPresets.send_to).
	## Every item is unlocked while testing (ArmyPresets.is_unlocked always true for now).
	if f != "":
		_army = f
	if _army == "":
		_army = faction
	if not _army_back.is_valid():                     # 0.19.2 spec H11: BACK did nothing reached directly
		_army_back = show_main                         # (show_armies() sets this; a direct entry never did)
	clear_page("city")
	_page = "armies"
	header(0)
	var fc := color()
	label_at("ARMIES", P(40, 104), 43)
	label_at("COSMETICS  ·  a look per structure, per faction - " + ("all unlocked while testing, the Graduate vat by finishing the tutorial"
			if Progression.unlock_all else "earn or unlock them; the Graduate vat by finishing the tutorial"),
			P(262, 122), 20, Color("abc1cd"))
	for i in range(FACTIONS.size()):
		var tf: String = FACTIONS[i]
		var pos := P(35, 174 + i * 96)
		var dims := P(362, 88)
		var tc: Color = Rules.FACTIONS[tf][1]
		nav_button("", pos, dims, func(): show_cosmetics(tf))
		content.add_child(neon_panel(pos, dims, tc, tf == _army, Color("020a10e0") if tf != _army else Color("08202ae8")))
		portrait(tf, pos + P(6, 4), P(76, 80))
		label_at("VIRIDIAN" if tf == "bloom" else tf.to_upper(), pos + P(92, 8), 24, tc if tf == _army else Color.WHITE)
		if tf == faction:
			label_at("YOU", pos + P(306, 4), 15, Color("ffd15c"))
	var lo := ArmyPresets.cosmetic_loadout_for(_army, true)   # the picks as saved: a locked one shows as locked
	var y := 174.0
	_core_row(P(415, y))                              # CORE · ALL FACTIONS: TERRITORY NEON / GOO (0.19.2)
	y += 88.0
	for family in COSMETIC_FAMILIES:
		_cosmetic_row(family, str(lo.get(family, "default")), P(415, y), fc)
		y += 92.0
	nav_button("BACK TO SKILLS", P(40, foot_y()), P(280, 58), func(): show_armies(_army))
	nav_button("BACK", P(340, foot_y()), P(200, 58), func(): _leave_armies())
	var note := "Saved on this device" if ArmyPresets.saved else "This browser keeps no storage: your picks last until the page closes"
	label_at(note, P(985, foot_y() + 18.0), 18, Color("7795a4") if ArmyPresets.saved else Color("ffd15c"), false)


func _core_row(pos: Vector2) -> void:
	## CORE · ALL FACTIONS (0.19.2, Daniele: "goo/neon should be in the choice of cosmetic, as general core
	## one maybe"): global, not per faction - TERRITORY: NEON / GOO, driving Rules.goo_territory at once.
	var dims := P(1222, 76)
	var accent := Color("ffb238")
	content.add_child(neon_panel(pos, dims, accent, false, Color("1a1408e8")))
	label_at("CORE  ·  ALL FACTIONS", pos + P(20, 10), 19, accent, false)
	var opts := ["neon", "goo"]
	var cur := ArmyPresets.core_territory
	var idx := maxi(opts.find(cur), 0)
	nav_button("<", pos + P(84, 38), P(42, 32), func():
		ArmyPresets.set_core_territory(opts[(idx - 1 + opts.size()) % opts.size()])
		show_cosmetics())
	label_at("TERRITORY: %s" % cur.to_upper(), pos + P(140, 44), 19, Color("dbe6ec"), false)
	nav_button(">", pos + P(1090, 38), P(42, 32), func():
		ArmyPresets.set_core_territory(opts[(idx + 1) % opts.size()])
		show_cosmetics())


func _cosmetic_row(family: String, current: String, pos: Vector2, fc: Color) -> void:
	var dims := P(1222, 84)
	content.add_child(neon_panel(pos, dims, fc, false, Color("08131aE0")))
	label_at(COSMETIC_FAMILY_LABEL.get(family, family.to_upper()), pos + P(20, 10), 19, Color.WHITE, false)
	var options: Array = Cosmetics.OPTIONS.get(family, ["default"])
	var idx := maxi(options.find(current), 0)
	var pv := Cosmetics.make_preview(family, current, _army, P(90, 60))   # 0.19.2 spec H10: a small turning
	pv.position = pos + P(20, 8)                                          # 3D model instead of a colour swatch
	content.add_child(pv)
	nav_button("<", pos + P(122, 42), P(42, 32), func():
		ArmyPresets.set_cosmetic_pick(_army, family, options[(idx - 1 + options.size()) % options.size()])
		show_cosmetics())
	var locked := not ArmyPresets.is_unlocked(current, family, _army)
	label_at(Cosmetics.label(family, current, _army) + ((" (LOCKED - %s)" % _cosmetic_path(family, current)) if locked else ""), pos + P(178, 48),
			19, Color("ffb12b") if locked else Color("dbe6ec"), false)
	var item := Progression.cosmetic_item(family, current, _army)   # PROGRESSION: UNLOCK where it can be bought
	if locked and not Progression.price(item).is_empty():
		nav_button("UNLOCK", pos + P(850, 38), P(190, 42), func():
			_buy_prompt(item, Cosmetics.label(family, current, _army).to_upper(), "A look only: tier read, footprint and colour stay the same.",
					func(): show_cosmetics()), false, false)   # the row's own height (a dense row - see label_at())
	nav_button(">", pos + P(1090, 42), P(42, 32), func():
		ArmyPresets.set_cosmetic_pick(_army, family, options[(idx + 1) % options.size()])
		show_cosmetics())


func show_maps() -> void:
	_last_show = show_maps                  # a resize that changes the phone sizing rebuilds it (_fit)
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
	var chip_h := rh(52)                              # the filter row grows on mobile - the grid below follows it down
	var x := 52.0
	for md in ["all"] + modes_all:
		var md_now: String = md
		nav_button("ALL" if md == "all" else MODE_NAMES.get(md, md), P(x, 188), P(chip_w, chip_h), func():
			map_filter_mode = md_now
			_refilter(), md == map_filter_mode)
		x += chip_w + 8.0
	nav_button("TYPE: %s" % MAP_TYPE_NAMES[map_filter_type], P(752, 188), P(240, chip_h), func():
		map_filter_type = MAP_TYPES[(MAP_TYPES.find(map_filter_type) + 1) % MAP_TYPES.size()]
		_refilter(), map_filter_type != "all")
	var grid_y := 188.0 + chip_h + 12.0
	if shown.is_empty():
		label_at("No map matches these filters.", P(70, grid_y + 32.0), 24, Color("abc1cd"))
	var scroll := TouchScroll.new()                    # finger swipes scroll the grid (phones)
	var keep := _map_scroll                           # picking a map rebuilds the page: stay where you were
	get_tree().process_frame.connect(func(): if is_instance_valid(scroll): scroll.scroll_vertical = keep, CONNECT_ONE_SHOT)
	scroll.position = P(52, grid_y)
	scroll.size = P(940, 815.0 - grid_y - 15.0)         # the frame's own bottom is 174 + 641 = 815
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
	nav_button("BACK", P(40, foot_y()), P(230, 58), show_factions)
	nav_button("NEXT: MATCH SETUP", P(1280, foot_y()), P(352, 58), show_setup, true)


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


func _enemy_seats() -> Array:
	## Every seat but yours (main.gd: "A" is always the human), in the current map/mode's seat list,
	## letter order - one rival-faction picker per seat (0.19.2, spec H3).
	var out := []
	for s in _selected_map().get("seats", {}).get(mode, []):
		var seat := str(s.get("seat", ""))
		if seat != "" and seat != "A":
			out.append(seat)
	out.sort()
	return out


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
	_last_show = show_setup                  # a resize that changes the phone sizing rebuilds it (_fit)
	clear_page("city")
	header(3)
	label_at("READY TO DEPLOY", P(40, 108), 51)
	frame(P(35, 188), P(982, 630))
	label_at(str(_selected_map().get("name", "")).replace("*", "").to_upper(), P(58, 207), 28)
	var hdr_h := rh(48)
	nav_button("CHANGE MAP", P(810, 206), P(184, hdr_h), show_maps)
	var preview_y := 206.0 + hdr_h + 14.0              # CHANGE MAP grows on mobile - the preview follows it down
	map_preview(P(53, preview_y), P(946, 360))
	var modes := _modes_of(_selected_map())
	if not mode in modes:
		mode = modes[0]
	# PLAYERS / YOUR COLOUR: a scrollable stack (stack_open()) below the preview - on mobile both chip
	# rows grow to the 44 pt tap minimum, more than this frame has spare room for stacked at desktop gaps
	var chip_area_y := preview_y + 360.0 + 24.0
	var st := stack_open(P(50, chip_area_y), P(960, maxf(160.0, 818.0 - chip_area_y - 15.0)))
	var y := 4.0
	var mode_h := rh(48)
	stack_add(st, label_at("PLAYERS", P(23, y + mode_h / 2.0 - 10.0), 20, Color("aac3cd")))
	for i in range(modes.size()):
		var md: String = modes[i]
		var mb := stack_add(st, nav_button(MODE_NAMES.get(md, md), P(115 + i * 140, y), P(132, mode_h), func():
			mode = md
			show_setup(), md == mode)) as Button
		mb.add_theme_font_size_override("font_size", int(round(18 * K)))
	y += mode_h + 20.0
	var col_h := rh(48)
	stack_add(st, label_at("YOUR COLOUR", P(23, y + col_h / 2.0 - 10.0), 20, Color("aac3cd")))
	var keys := COLOUR_NAMES.keys()
	for i in range(keys.size()):
		var ck: String = keys[i]
		var wedges := FACTIONS.map(func(f): return Rules.FACTIONS[f][1]) if ck == "faction" else []
		var cc: Color = Color.WHITE if ck == "faction" else Rules.SEATS[ck]
		var chip := hex_chip(P(175 + i * 112, y), P(col_h, col_h), cc, wedges, ck == colour, COLOUR_NAMES[ck], func():
			colour = ck
			show_setup())
		if ck == "faction":
			chip.emblem_faction = faction              # 0.19.2 spec H2: a recognisable face, not just wedges
		stack_add(st, chip)
	y += col_h + 16.0
	if colour == "faction":                            # 0.19.2 spec H2: a one-line caption while FACTION is picked
		stack_add(st, label_at("Every player in their faction's colour", P(23, y), 16, Color("ffd15c")))
		y += 26.0
	if not mobile:                                    # the phone skips the recap to save room
		stack_add(st, label_at("Team modes: one hue per team, light and dark. FACTION: every seat in its own faction colour (Alpha 11).", P(23, y), 14, Color("7795a4")))
		y += 26.0
	stack_close(st, y)
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
	# RIVAL FACTION / DIFFICULTY / LAST STAND / ABILITIES: another scrollable stack, same reason as the left
	# column's - every row here grows to the 44 pt minimum on mobile
	var st2 := stack_open(P(1058, 556), P(552, maxf(160.0, 818.0 - 556.0 - 14.0)))
	var y2 := 0.0
	# RIVAL FACTIONS: one compact cycling chip per enemy seat (0.19.2, spec H3 - "the single picker
	# allows only all different or all the same"), tap to cycle ANY -> each faction -> ANY. Wraps to a
	# second row past 2 seats, so it stays compact on phones too.
	stack_add(st2, label_at("RIVAL FACTIONS  ·  tap a seat to cycle", P(1, y2), 20, Color("aac3cd")))
	y2 += 34.0
	var enemy_seats := _enemy_seats()
	var rf_choices := ["random"] + FACTIONS
	var rf_gap := 8.0
	var rf_per_row := clampi(enemy_seats.size(), 1, 2)
	var rf_w := (552.0 - rf_gap * (rf_per_row - 1)) / float(rf_per_row)
	var rf_h := rh(46)
	for i in range(enemy_seats.size()):
		var seat: String = enemy_seats[i]
		var pick := str(rival_picks.get(seat, "random"))
		var col := i % rf_per_row
		var row := i / rf_per_row
		var lbl := "%s: %s" % [seat, ("ANY" if pick == "random" else ("VIRIDIAN" if pick == "bloom" else pick.to_upper()))]
		var b := stack_add(st2, nav_button(lbl, P(col * (rf_w + rf_gap), y2 + row * (rf_h + 8.0)), P(rf_w, rf_h), func():
			var idx := rf_choices.find(pick)
			rival_picks[seat] = rf_choices[(idx + 1) % rf_choices.size()]
			show_setup())) as Button
		b.add_theme_font_size_override("font_size", int(round(14 * K)))
	y2 += ceilf(float(enemy_seats.size()) / float(rf_per_row)) * (rf_h + 8.0) + 14.0
	stack_add(st2, label_at("DIFFICULTY", P(1, y2), 20, Color("aac3cd")))
	y2 += 34.0
	# equal gaps, computed to fill the column exactly (0.19.2 spec H4: "aren't evenly spaced")
	var levels: Array = Rules.AI_LEVELS.keys()               # Alpha 11's five levels
	var lv_gap := 8.0
	var lv_w := (552.0 - lv_gap * (levels.size() - 1)) / float(levels.size())
	var lv_h := rh(59)
	for i in range(levels.size()):
		var lv: String = levels[i]
		var b := stack_add(st2, nav_button(lv.to_upper(), P(i * (lv_w + lv_gap), y2), P(lv_w, lv_h), func():
			ai_level = lv
			show_setup(), lv == ai_level)) as Button
		b.add_theme_font_size_override("font_size", int(round(14 * K)))
	y2 += lv_h + 18.0
	var ls_h := rh(56)
	var lsb := stack_add(st2, nav_button("LAST STAND / %s" % ("ON" if Rules.last_stand else "OFF"), P(0, y2), P(272, ls_h), func():
		Rules.last_stand = not Rules.last_stand
		show_setup())) as Button
	# SKILLS 2.0: ABILITIES ON / OFF (Alpha 11's match setting; default ON)
	var abb := stack_add(st2, nav_button("ABILITIES / %s" % ("ON" if Rules.abilities_on else "OFF"), P(280, y2), P(272, ls_h), func():
		Rules.abilities_on = not Rules.abilities_on
		show_setup())) as Button
	for b in [lsb, abb]:
		b.add_theme_font_size_override("font_size", int(round(fsz(22) * K)))
	y2 += ls_h + 14.0
	if not mobile:
		stack_add(st2, label_at("Last Stand ON = the map collapses ring by ring late in the match.  ABILITIES OFF = no skills.", P(4, y2), 14, Color("7795a4")))
		y2 += 26.0
	stack_close(st2, y2)
	nav_button("BACK", P(40, foot_y()), P(230, 58), show_maps)
	nav_button("DEPLOY", P(1280, foot_y()), P(352, 58), deploy, true)


func summary_card(f: String, pos: Vector2, dims: Vector2, change: bool) -> void:
	frame(pos, dims, "row")
	portrait(f, pos + P(6, 6), Vector2(146 * K, dims.y - 12 * K))
	label_at("VIRIDIAN" if f == "bloom" else f.to_upper(), pos + P(174, 23), 34, Rules.FACTIONS[f][1])
	label_at(NAMES[f].split("\n")[1], pos + P(177, 70), 20, Color("adc7d2"))
	if change:
		# CHANGE and the preset preview below sit inside this compact card (dims.y ~ 92-100 post-K) - too
		# little room for the full 44 pt phone minimum without redrawing the card; grow=false keeps them
		# at their designed size rather than spilling out of the card's frame (open issue: still small on
		# mobile - a card redesign, not a size-rule tweak, would be needed to fix it properly).
		nav_button("CHANGE", pos + Vector2(dims.x - 148 * K, dims.y - 50 * K), P(132, 42), show_factions, false, false).add_theme_font_size_override("font_size", int(round(19 * K)))
		# your army preset on this map (a relay skill greyed to its fallback where the map has no relays); tap: ARMIES
		var ip := pos + Vector2(dims.x - 162 * K, 12 * K)
		var ab := nav_button("", ip - P(6, 4), P(160, 60), func(): show_armies(f, show_setup), false, false)
		ab.tooltip_text = "Your army preset - tap to change it in ARMIES"
		loadout_icons(f, ArmyPresets.loadout_for(f), ip, 42.0 * K, 8.0 * K, ArmyPresets.map_has_relays(_selected_map()))
		var eff := ArmyPresets.effective(f, ArmyPresets.loadout_for(f), ArmyPresets.map_has_relays(_selected_map()))
		if not Rules.abilities_on:
			label_at("ABILITIES OFF", ip + P(0, 54), 13, Color("7795a4"))
		elif eff["swapped"] != "":
			label_at("NO RELAYS: %s" % ArmyPresets.skill_name(eff["map"]).to_upper(), ip + P(-14, 54), 13, Color("ffd15c"))


func _seat_faction_picks() -> Dictionary:
	## Every enemy seat's pick for this mode (0.19.2 spec H3): a faction id, or "random" - main.gd
	## resolves "random" through Sim.resolve_factions (the seed, so it matches Sim.setup()'s own way).
	var out := {}
	for seat in _enemy_seats():
		out[seat] = str(rival_picks.get(seat, "random"))
	return out


func deploy() -> void:
	UiKit.save_last_faction(faction)                   # UI: HOME's hero is the faction played last
	main.start_match(map_path, faction, _seat_faction_picks(), ai_level, mode, colour, ArmyPresets.loadout_for(faction))   # your ARMIES preset


# ------------------------------------------------------------------ online (Net, rooms through the room server)
var _code_box: Control = null                      # ONLINE ROOMS' ROOM CODE frame (web: the native field sits on it)
var _code_inline := false                          # web: room-ui.js's inline code field is on the page
var _code_t := 0.0
var _code_error := ""                              # the field's own error (an incomplete code), shown under it
var _code_value := ""                              # the code last tried: the field keeps it after a failed join
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # a room code's characters (no I / O / 0 / 1; web/room-ui.js)


func show_online() -> void:
	_last_show = show_online                  # a resize that changes the phone sizing rebuilds it (_fit)
	## ONLINE ROOMS (screen system 13; a PLAY subflow): HOST A MATCH - your faction and CREATE ROOM (RECONNECT when a room
	## dropped you) - and JOIN A FRIEND - the ROOM CODE field and JOIN ROOM, what went wrong right under the field (an
	## incomplete code, or Net's answer: full, not found, closed...). The web build lays web/room-ui.js's native <input>
	## over the field, so a phone raises its keyboard for it; Enter joins too. The room's lobby sets mode, map and rules.
	var area := shell_open("OOZE / ROOMS", "play", _leave_online, faction)
	_page = "online"
	_code_box = null
	var x := shell_x()
	var acc := UiKit.accent(shell_f)
	var web := OS.has_feature("web")
	var top := page_title(area, "ONLINE", "MEET IN THE CITY.")
	var gap := 18.0
	var cw := (content.size.x - x * 2.0 - gap) / 2.0
	var ch := area.end.y - 14.0 - top
	# HOST A MATCH (its inside scrolls on a short phone)
	var host := _column(Vector2(x, top), Vector2(cw, ch))
	var w: float = host["w"]
	var n0 := content.get_child_count()
	var y := 4.0
	y += _say("HOST A MATCH", Vector2(0, y), 12, acc, 0.0, true, 3) + 6.0
	y += _say("YOUR ROOM. YOUR RULES.", Vector2(0, y), 20, UiKit.INK, w, true) + 4.0
	y += _say("Create a room, set the map and the rules in its lobby, then share its four-character code - everyone opens this same link.",
			Vector2(0, y), 14, UiKit.MUTED, w) + 14.0
	y += _say("YOUR FACTION", Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	y += _faction_row(Vector2(0, y), 58.0) + 16.0
	var create := UiKit.btn(self, "CREATE ROOM  →", Vector2(0, y), Vector2(UiKit.text_w(self, "CREATE ROOM  →", 16, true) + 60.0, 50), func():
		ArmyPresets.send_to(Net, faction)                     # your ARMIES preset rides in the roster
		Net.host_room(faction)
		show_lobby(), "primary", shell_f, 16)
	create.disabled = not web
	if not Net.rejoin.is_empty():                     # dropped out of a room: back into the same seat
		var rt := "RECONNECT  %s" % str(Net.rejoin["code"])
		var rw := UiKit.text_w(self, rt, 16, true) + 44.0
		var rpos := Vector2(create.size.x + 12.0, y) if create.size.x + 12.0 + rw <= w else Vector2(0, y + create.size.y + 10.0)
		var rc := UiKit.btn(self, rt, rpos, Vector2(rw, 50), func():
			ArmyPresets.send_to(Net, str(Net.rejoin.get("faction", faction)))
			Net.reconnect()
			show_lobby(), "selected", shell_f, 16)
		rc.disabled = not web
		y = rpos.y
	y += create.size.y + 18.0
	y += _say("The room server runs the match, so a phone that locks or switches apps only drops its own seat - RECONNECT takes it back. The room's creator picks the map and settings. Free-for-all for 2 to 5 players, or teams. Rematch reuses the room; chat stays between rounds.",
			Vector2(0, y), 13, UiKit.MUTED, w) + 10.0
	y += _say("Rooms run on the Ooze room server, so any network that reaches the internet can join. If the server is busy, the room's creator hosts it in their browser instead (keep that tab in front)." if web
			else "Online rooms run in the browser build: open https://talos91.github.io/ooza-syndicate-v2/", Vector2(0, y), 13,
			UiKit.DIM if web else UiKit.STAR, w)
	_column_end(host, n0, y)
	# JOIN A FRIEND: a plain panel, never scrolled, so the web's native code field stays exactly on its frame
	var jx := x + cw + gap
	UiKit.panel(self, Vector2(jx, top), Vector2(cw, ch), shell_f)
	var px := jx + 20.0
	var jw := cw - 40.0
	var jy := top + 16.0
	jy += _say("JOIN A FRIEND", Vector2(px, jy), 12, acc, 0.0, true, 3) + 6.0
	jy += _say("GOT A CODE?", Vector2(px, jy), 20, UiKit.INK, jw, true) + 4.0
	jy += _say("Type the host's four-character room code.", Vector2(px, jy), 14, UiKit.MUTED, jw) + 14.0
	jy += _say("ROOM CODE", Vector2(px, jy), 12, UiKit.MUTED, 0.0, true, 2) + 6.0
	var box := _line_edit(Vector2(px, jy), Vector2(minf(jw, 340.0), 50), "E.G. K7QX", "")
	box.editable = false                              # web: the native field lies over it; elsewhere rooms need the browser build
	box.focus_mode = Control.FOCUS_NONE
	_code_box = box
	jy += box.size.y + 8.0
	var err := _code_error if _code_error != "" else Net.status
	if err != "":                                     # the field's error, or the room's answer, next to the field
		jy += _say(err, Vector2(px, jy), 13, UiKit.STAR, jw) + 8.0
	var join := UiKit.btn(self, "JOIN ROOM", Vector2(px, jy + 2.0), Vector2(UiKit.text_w(self, "JOIN ROOM", 16, true) + 60.0, 48),
			_join_from_field, "secondary", shell_f, 16)
	join.disabled = not web
	if web:
		_place_code_field.call_deferred()


func _leave_online() -> void:
	Net.status = ""
	_code_error = ""
	show_play()


func _faction_row(pos: Vector2, tile: float) -> float:
	## Your faction: its five characters as tiles (the picked one lit in its accent), each name under it - the room
	## gets the pick and its ARMIES preset. Returns the height used.
	tile = UiKit.tap_h(self, tile)
	var nw := 0.0
	for f in FACTIONS:
		nw = maxf(nw, UiKit.text_w(self, UiKit.NAMES[f], 13))
	var step := maxf(tile + 10.0, nw + 10.0)
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var picked := f == faction
		var b := UiKit.btn(self, "", pos + Vector2(i * step + (step - tile) / 2.0, 0), Vector2(tile, tile), func(): _pick_faction(f),
				"selected" if picked else "secondary", f)
		b.tooltip_text = UiKit.TAGS[f]
		var art := TextureRect.new()
		art.texture = load(UiKit.hero_path(f))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2.ONE * tile * 0.1
		art.size = Vector2.ONE * tile * 0.8
		art.modulate = Color.WHITE if picked else Color(1, 1, 1, 0.72)
		b.add_child(art)
		var nm: String = UiKit.NAMES[f]
		_say(nm, pos + Vector2(i * step + (step - UiKit.text_w(self, nm, 13)) / 2.0, tile + 4.0), 13, UiKit.INK if picked else UiKit.MUTED)
	return tile + 4.0 + UiKit.line_h(self, 13)


func _pick_faction(f: String) -> void:
	faction = f
	main.SEAT_FACTIONS[main.HUMAN] = f
	ArmyPresets.room_faction(Net, f)                          # the faction and its ARMIES preset
	if _page == "lobby":
		show_lobby()
	else:
		show_online()


func show_lobby() -> void:
	_last_show = show_lobby                  # a resize that changes the phone sizing rebuilds it (_fit)
	## LOBBY (screen system 14; a PLAY subflow): the room code (SHARE CODE), CHAT with its unread count, MY ARMY; the seats
	## in words - HOST / JOINED / YOU / RECONNECTING, OPEN SEAT, the AI - team by team with JOIN / MOVE in team modes (the
	## host picks a player's row, then MOVE on a team); your faction and colour; the host's MATCH (map, PLAYERS, LAST
	## STAND, ABILITIES, EMPTY SEATS); DEPLOY for the host once every seat is filled, LEAVE ROOM. The foot carries who is
	## in and Net's status (a browser-hosted room's UNRANKED line). Both columns scroll on phones.
	if not Net.in_room():
		show_online()
		return
	if Net.roster.has(Net.local_id()):
		faction = str(Net.roster[Net.local_id()]["faction"])
	var area := shell_open("OOZE / LOBBY", "play", _leave_room, faction)
	_page = "lobby"
	map_path = Net.map_path                           # the rows' loadout icons read the room's map (relays)
	var host := Net.can_control()                     # the browser host, or a server room's owner (Alpha 20)
	var x := shell_x()
	var acc := UiKit.accent(shell_f)
	var ty := area.position.y + (10.0 if shell_slim else 18.0)
	var top := UiKit.title(self, x, ty, "ONLINE / LOBBY", "WAITING FOR THE CREW.", shell_f, 34.0 * (0.8 if shell_slim else 1.0)) + 14.0
	var lv := UiKit.flat_button(self, "LEAVE ROOM", 15)
	lv.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.size = Vector2(UiKit.text_w(self, lv.text, 15, true) + 20.0, UiKit.tap_h(self, 36.0))
	lv.pressed.connect(func(): _leave_room.call_deferred())
	_shell_add(lv, Vector2(content.size.x - x - lv.size.x, ty))
	# the foot: who is in and the room's status at the left, DEPLOY (the host) at the right
	var bh := UiKit.tap_h(self, 50.0)
	var fy := area.end.y - bh - 12.0
	var rx := content.size.x - x
	if host:
		var go := UiKit.btn(self, "DEPLOY  →", Vector2(rx - 240.0, fy), Vector2(240, 50), func(): Net.start_match(), "primary", shell_f, 18)
		go.disabled = not Net.can_start()
		rx = go.position.x - 16.0
	else:
		var hw := "THE HOST DEPLOYS WHEN READY"
		var hwid := UiKit.text_w(self, hw, 14, true)
		_say(hw, Vector2(rx - hwid, fy + (bh - UiKit.line_h(self, 14, true)) / 2.0), 14, UiKit.MUTED, 0.0, true)
		rx -= hwid + 16.0
	var line := "%d / %d PLAYERS" % [Net.roster.size(), Net.slots()] + (("  ·  " + Net.status) if Net.status != "" else "")
	_say(line, Vector2(x, fy + maxf(0.0, (bh - UiKit.text_h(self, line, 13, rx - x)) / 2.0)), 13, UiKit.INK, rx - x)
	var gap := 18.0
	var cw := (content.size.x - x * 2.0 - gap) / 2.0
	var ch := fy - 12.0 - top
	# left: the code, the seats, you
	var left := _column(Vector2(x, top), Vector2(cw, ch))
	var w: float = left["w"]
	var n0 := content.get_child_count()
	var y := 2.0
	y += _say("ROOM CODE", Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 3) + 2.0
	var code := Net.room_code if Net.room_code != "" else "····"
	var code_h := UiKit.line_h(self, 40, true)
	_say(code, Vector2(0, y), 40, acc, 0.0, true, 10)
	var code_w := UiKit.text_w(self, code, 40, true) + code.length() * 10.0 + 20.0
	var share := UiKit.btn(self, "SHARE CODE", Vector2.ZERO, Vector2(UiKit.text_w(self, "SHARE CODE", 14, true) + 34.0, 42), _share_code, "secondary", shell_f, 14)
	share.disabled = Net.room_code == ""
	var chat := UiKit.btn(self, "CHAT (%d)" % Net.chat_unread() if Net.chat_unread() > 0 else "CHAT", Vector2.ZERO,
			Vector2(UiKit.text_w(self, "CHAT (99)", 14, true) + 34.0, 42), Net.open_chat, "secondary", shell_f, 14)
	chat.disabled = not Net.connected
	_chat_btn = chat
	var army := UiKit.btn(self, "MY ARMY", Vector2.ZERO, Vector2(UiKit.text_w(self, "MY ARMY", 14, true) + 34.0, 42),
			func(): show_armies(faction, show_lobby), "secondary", shell_f, 14)   # your preset = your loadout
	army.disabled = Net.active
	var fh := _flow([share, chat, army], Vector2(code_w, y + maxf(0.0, (code_h - share.size.y) / 2.0)), w - code_w)
	y += maxf(code_h, fh) + 16.0
	# players (0.18.7, Daniele: "there should be so i can switch to my gf team"; every seat's colour is the same on every
	# screen): team modes list the seats team by team, each under its JOIN control; the host can pick a row and MOVE it
	var by_slot := {}
	for id in Net.roster:
		by_slot[int(Net.roster[id]["slot"])] = int(id)
	if not Net.roster.has(_move_pick) or not host or _move_pick == Net.local_id():
		_move_pick = -1
	var colours := Net.room_colours()
	var team_mode := Net.mode in Net.TEAM_MODES
	y += _say("SEATS", Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 3) + 4.0
	if team_mode and host:
		y += _say("Host: tap a player, then MOVE on a team.", Vector2(0, y), 13, UiKit.MUTED, w) + 4.0
	y += 4.0
	var groups := []                                  # [team, [slots]] in seat order; FFA: one group
	if team_mode:
		for t in Net.team_ids():
			groups.append([t, range(Net.slots()).filter(func(sl): return Net.team_of_slot(sl) == t)])
	else:
		groups.append([-1, range(Net.slots())])
	for g in groups:
		if team_mode:
			y += _team_button(int(g[0]), colours, Vector2(0, y), w) + 6.0
		for i in g[1]:
			y += _lobby_row(i, by_slot.get(i, -1), colours, Vector2(0, y), w, host and team_mode) + 6.0
		if team_mode:
			y += 8.0
	y += 10.0
	y += _say("YOUR FACTION", Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	y += _faction_row(Vector2(0, y), 50.0) + 14.0
	var mine := Net.colour_of(Net.local_id())
	y += _say("YOUR COLOUR" + (("  ·  " + mine.to_upper()) if mine != "" else ""), Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	y += _colour_row(Vector2(0, y), w) + 12.0
	var hint := "Every seat has one colour, the same on every screen. " + (("Teammates share a hue family (%s); a colour from a free family moves your team to it." % " / ".join(
			Net.families().map(func(f): return Rules.FAMILY_NAMES.get(f[0], "")))) if team_mode else "Seats go in join order.")
	if Net.abilities and not ArmyPresets.map_has_relays(_selected_map()):
		hint += " No relays on this map: a gold map skill is the faction's fallback for a relay skill."
	y += _say(hint, Vector2(0, y), 13, UiKit.DIM, w)
	_column_end(left, n0, y)
	# right: the match (the host decides)
	var right := _column(Vector2(x + cw + gap, top), Vector2(cw, ch))
	w = right["w"]
	n0 = content.get_child_count()
	y = 2.0
	y += _say("MATCH" + ("" if host else "  ·  THE HOST DECIDES"), Vector2(0, y), 12, acc if host else UiKit.MUTED, 0.0, true, 3) + 6.0
	var sh := UiKit.tap_h(self, 40.0)
	var mname := str(_selected_map().get("name", "")).replace("*", "").to_upper()
	if host:
		_clip(mname, Vector2(0, y + (sh - UiKit.line_h(self, 18, true)) / 2.0), 18, UiKit.INK, w - sh * 2.0 - 20.0, true)
		UiKit.btn(self, "<", Vector2(w - sh * 2.0 - 8.0, y), Vector2(sh, 40), func(): _step_map(-1), "secondary", shell_f, 18)
		UiKit.btn(self, ">", Vector2(w - sh, y), Vector2(sh, 40), func(): _step_map(1), "secondary", shell_f, 18)
		y += sh + 10.0
	else:
		_clip(mname, Vector2(0, y), 18, UiKit.INK, w, true)
		y += UiKit.line_h(self, 18, true) + 10.0
	var ph := minf(w * 0.45, 210.0)
	map_preview(Vector2(0, y), Vector2(w, ph))
	y += ph + 14.0
	y += _say("PLAYERS" + ("" if host else "  ·  " + str(Net.MODE_LABELS[Net.mode])), Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	if host:
		var chips := []
		for md in Net.MODES:
			var m2: String = md
			var mb := UiKit.chip(self, Net.MODE_LABELS[m2], Vector2.ZERO, func():
				Net.set_mode(m2)
				show_lobby(), shell_f, m2 == Net.mode)
			mb.disabled = Net.roster.size() > Net.SLOTS[m2] or Net.maps_for(m2).is_empty()
			chips.append(mb)
		y += _flow(chips, Vector2(0, y), w) + 14.0
	var tw := (w - 10.0) / 2.0
	var lb := UiKit.btn(self, "LAST STAND  ·  %s" % ("ON" if Net.last_stand else "OFF"), Vector2(0, y), Vector2(tw, 44), func():
		Net.toggle_last_stand()
		show_lobby(), "selected" if Net.last_stand else "secondary", shell_f, 14)
	lb.disabled = not host
	var abl := UiKit.btn(self, "ABILITIES  ·  %s" % ("ON" if Net.abilities else "OFF"), Vector2(tw + 10.0, y), Vector2(tw, 44), func():   # SKILLS 2.0
		ArmyPresets.room_toggle_abilities(Net)
		show_lobby(), "selected" if Net.abilities else "secondary", shell_f, 14)
	abl.disabled = not host
	y += lb.size.y + 10.0
	var eb := UiKit.btn(self, "EMPTY SEATS  ·  %s" % ("AI " + Net.ai_fill.to_upper() if Net.ai_fill != "" else "PLAYERS ONLY"), Vector2(0, y), Vector2(w, 44), func():
		Net.set_ai_fill(Net.AI_FILL[(Net.AI_FILL.find(Net.ai_fill) + 1) % Net.AI_FILL.size()])
		show_lobby(), "secondary", shell_f, 14)
	eb.disabled = not host
	y += eb.size.y + 10.0
	if host and not Net.can_start():
		y += _say("DEPLOY opens when every seat is filled (or EMPTY SEATS: AI).", Vector2(0, y), 13, UiKit.MUTED, w)
	_column_end(right, n0, y)


func _leave_room() -> void:
	Net.leave()
	show_online()


func _lobby_row(i: int, id: int, colours: Dictionary, pos: Vector2, w: float, movable: bool) -> float:
	## One seat: its letter and an edge bar in the seat's room colour (the same on every screen), the player's character
	## and faction, who holds it in words - HOST / JOINED / RECONNECTING, YOU, OPEN SEAT, the AI - and their loadout
	## (active, map, ultimate; dimmed with ABILITIES OFF). Host, team modes: a guest's row picks them to MOVE.
	## Returns the row's height.
	var seat: String = Net.SEATS[i]
	var hue := str(colours.get(seat, ""))
	var col: Color = Rules.HUES.get(hue, Rules.SEATS.get(seat, Color.WHITE))
	var l1 := UiKit.line_h(self, 16, true)
	var l2 := UiKit.line_h(self, 13)
	var h := maxf(58.0, l1 + l2 + 16.0)
	var pick := movable and id >= 0 and id != Net.local_id()
	if pick:
		h = UiKit.tap_h(self, h)
	var picked := pick and id == _move_pick
	var r: Control
	if pick:
		r = UiKit.btn(self, "", pos, Vector2(w, h), func():
			_move_pick = -1 if _move_pick == id else id
			show_lobby(), "selected" if picked else "secondary", shell_f)
	else:
		r = UiKit.panel(self, pos, Vector2(w, h), shell_f, false, Color(UiKit.BASE, 0.7))
	r.add_child(UiKit.rect(Vector2(0, 6), Vector2(4, h - 12.0), col))
	var sl := UiKit.label(self, seat, 22, col, true)
	sl.position = Vector2(14, (h - UiKit.line_h(self, 22, true)) / 2.0)
	r.add_child(sl)
	var tx := 14.0 + UiKit.text_w(self, "W", 22, true) + 10.0
	var ts := h - 14.0
	var title_text := ""
	var sub := ""
	var sub_col := UiKit.MUTED
	var right := w - 12.0
	if id >= 0:
		var f: String = str(Net.roster[id]["faction"])
		var art := TextureRect.new()
		art.texture = load(UiKit.hero_path(f))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2(tx, 7)
		art.size = Vector2(ts, ts)
		r.add_child(art)
		title_text = ("YOU / " if id == Net.local_id() else "") + str(UiKit.NAMES[f])
		var words := ["HOST" if id == Net.room_owner else "JOINED"]
		if Net.is_away(id):
			words.append("RECONNECTING")
			sub_col = UiKit.STAR
		if picked:
			words.append("PICKED: MOVE ON A TEAM")
			sub_col = UiKit.accent(shell_f)
		sub = "  ·  ".join(words) + (("  ·  " + hue.to_upper()) if hue != "" else "")
		var lo = Net.roster[id].get("loadout", {})
		right = _loadout_chips(r, f, lo if lo is Dictionary else {}, right, h / 2.0, clampf(h * 0.5, 26.0, 40.0)) - 10.0
	else:
		var box := Panel.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.9), UiKit.FRAME, 1, 6))
		box.position = Vector2(tx, 7)
		box.size = Vector2(ts, ts)
		r.add_child(box)
		var mark := UiKit.label(self, "AI" if Net.ai_fill != "" else "+", 18, UiKit.MUTED, true)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.size = Vector2(ts, ts)
		box.add_child(mark)
		title_text = ("AI / " + Net.ai_fill.to_upper()) if Net.ai_fill != "" else "OPEN SEAT"
		sub = "The AI plays this seat" if Net.ai_fill != "" else "Waiting for a player"
	var lx := tx + ts + 12.0
	var ty := (h - l1 - l2) / 2.0
	for part in [[title_text, 16, UiKit.INK, true, ty], [sub, 13, sub_col, false, ty + l1]]:
		var l := UiKit.label(self, part[0], part[1], part[2], part[3])
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.position = Vector2(lx, part[4])
		l.size = Vector2(maxf(10.0, right - lx), UiKit.line_h(self, part[1], part[3]))
		r.add_child(l)
	return h


func _loadout_chips(parent: Control, f: String, lo: Dictionary, right_x: float, cy: float, ic: float) -> float:
	## A seat's loadout (SKILLS 2.0) as three framed icons ending at `right_x`: active, map (gold: the no-relay fallback
	## on a map without relays), ultimate (gold frame); dimmed while ABILITIES is OFF. Returns their left edge.
	var eff := ArmyPresets.effective(f, lo, ArmyPresets.map_has_relays(_selected_map()))
	var ids := [eff["active"], eff["map"], eff["ultimate"]]
	var fa := UiKit.accent(f)
	var gold := Color("ffd15c")
	var gap := 6.0
	var x0 := right_x - 3.0 * ic - 2.0 * gap
	for k in range(3):
		var p := Vector2(x0 + k * (ic + gap), cy - ic / 2.0)
		var fr := Panel.new()
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.9), gold if k == 2 else Color(fa, 0.7), 1, 5))
		fr.position = p
		fr.size = Vector2(ic, ic)
		parent.add_child(fr)
		skill_icon(ids[k], p + Vector2.ONE * ic * 0.14, Vector2.ONE * ic * 0.72, gold if (k == 1 and eff["swapped"] != "") else fa, parent)
	if not Net.abilities:                             # ABILITIES OFF: the icons dimmed
		parent.add_child(UiKit.rect(Vector2(x0 - 2.0, cy - ic / 2.0 - 2.0), Vector2(3.0 * ic + 2.0 * gap + 4.0, ic + 4.0), Color(0.01, 0.04, 0.06, 0.62)))
	return x0


func _team_button(t: int, colours: Dictionary, pos: Vector2, w: float) -> float:
	## A team's header: TEAM n and its hue, and JOIN (you) or MOVE X HERE (the host, with a player picked) - YOUR TEAM /
	## X IS HERE when already there, FULL when it takes nobody. Returns its height.
	var me := Net.local_id()
	var who := _move_pick if _move_pick >= 0 else me
	var here := Net.team_of(who) == t
	var room := Net.free_slot_in(t) >= 0
	var verb := ("YOUR TEAM" if who == me else "%s IS HERE" % Net.seat_of(who)) if here else (("JOIN" if who == me else "MOVE %s HERE" % Net.seat_of(who)) if room else "FULL")
	var bh := UiKit.tap_h(self, 38.0)
	var tl := "TEAM %d" % (Net.team_ids().find(t) + 1)
	_say(tl, Vector2(pos.x, pos.y + (bh - UiKit.line_h(self, 15, true)) / 2.0), 15, UiKit.INK, 0.0, true)
	var first := -1
	for sl in range(Net.slots()):
		if Net.team_of_slot(sl) == t:
			first = sl
			break
	if first >= 0:                                    # the team's hue beside its name
		content.add_child(UiKit.rect(Vector2(pos.x + UiKit.text_w(self, tl, 15, true) + 12.0, pos.y + bh / 2.0 - 2.0), Vector2(36, 4),
				Rules.HUES.get(str(colours.get(Net.SEATS[first], "")), Color.WHITE)))
	var bw := UiKit.text_w(self, verb, 14, true) + 36.0
	var b := UiKit.btn(self, verb, Vector2(pos.x + w - bw, pos.y), Vector2(bw, 38), func():
		if who == me:
			Net.switch_team(t)
		else:
			Net.move_to_team(who, t)
		_move_pick = -1
		show_lobby(), "primary" if (not here and room) else "secondary", shell_f, 14)
	b.disabled = here or not room or Net.active
	return bh


func _colour_row(pos: Vector2, w: float) -> float:
	## Your colour: one hexagon chip per hue, filled solid in its colour, border the same colour, no words (Daniele,
	## 0.19.0 - the picked one is named in the caption above); taken hues (and, in team modes, another team's family)
	## are dimmed and disabled. The picked chip gets HexChip's white ring + scale-up. Wraps on a narrow column; returns
	## the height used.
	var me := Net.local_id()
	var mine := Net.colour_of(me)
	var d := UiKit.tap_h(self, 44.0)
	var per := maxi(1, int((w + 6.0) / (d + 6.0)))
	for i in range(HUE_NAMES.size()):
		var k: String = HUE_NAMES[i]
		var ok := Net.colour_allowed(me, k) or k == mine
		var b := hex_chip(pos + Vector2((i % per) * (d + 6.0), (i / per) * (d + 6.0)), Vector2(d, d), Rules.HUES[k], [], k == mine, k.to_upper(), func():
			Net.set_colour(k)
			show_lobby())
		b.disabled = not ok or Net.active
	var rows := int(ceil(HUE_NAMES.size() / float(per)))
	return rows * d + (rows - 1) * 6.0


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


static func _valid_code(code: String) -> bool:
	if code.length() != 4:
		return false
	for c in code:
		if CODE_CHARS.find(c) < 0:
			return false
	return true


func _code_field_ready() -> bool:
	## Web: this page's room-ui.js has the inline code field (an older cached one only has the code dialog).
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.OozeRoom&&window.OozeRoom.placeCode)", true))


func _join_from_field() -> void:
	## JOIN ROOM: the code in the field (web/room-ui.js's inline <input>); an incomplete one is said under the field.
	## Without the inline field (an older cached room-ui.js) it opens the code dialog, as before.
	if not OS.has_feature("web"):
		return
	if not _code_field_ready():
		_open_code()
		return
	var code := str(JavaScriptBridge.eval("OozeRoom.codeValue()", true)).strip_edges().to_upper()
	if not _valid_code(code):
		_code_error = "Enter all four characters from the host." if code != "" else "Type the host's four-character code first."
		show_online()
		return
	_code_error = ""
	_code_value = code
	ArmyPresets.send_to(Net, faction)                         # the register carries your ARMIES preset
	Net.join_room(code, faction)
	show_lobby()


func _place_code_field() -> void:
	## Web: lay the native code field over ROOM CODE's frame (canvas fractions -> CSS px in the page), or move it
	## there - the same way ACCOUNT's name field sits on its box (_place_name_field).
	if _page != "online" or not is_instance_valid(_code_box) or not _code_field_ready():
		return
	var t := _code_box.get_global_transform_with_canvas()
	var r := Rect2(t.origin, _code_box.size * t.get_scale())
	var vp := get_viewport().get_visible_rect().size
	JavaScriptBridge.eval("OozeRoom.placeCode(%f,%f,%f,%f,%s,%s)" % [r.position.x / vp.x, r.position.y / vp.y,
			r.size.x / vp.x, r.size.y / vp.y, JSON.stringify(_code_value), JSON.stringify("#" + UiKit.accent(shell_f).to_html(false))], true)
	_code_inline = true


func _poll_code(dt: float) -> void:
	## Web, while the inline code field is up: remove it off ONLINE ROOMS, keep it on its frame.
	if not _code_inline:
		return
	if _page != "online":
		JavaScriptBridge.eval("window.OozeRoom&&OozeRoom.removeCode&&OozeRoom.removeCode()", true)
		_code_inline = false
		return
	_code_t -= dt
	if _code_t <= 0.0:
		_code_t = 0.4
		_place_code_field()


func _process(dt: float) -> void:
	## The room code comes from the native DOM field (phone keyboards: web/room-ui.js, Alpha 11's).
	if _page == "lobby" and is_instance_valid(_chat_btn):   # unread count on the lobby CHAT button
		_chat_t -= dt
		if _chat_t <= 0.0:
			_chat_t = 0.5
			var n := Net.chat_unread()
			_chat_btn.text = "CHAT (%d)" % n if n > 0 else "CHAT"
			_chat_btn.disabled = not Net.connected
	if OS.has_feature("web"):                                  # PROGRESSION: the HTML name field (ACCOUNT)
		_poll_name(dt)
		_poll_code(dt)                                         # UI: ONLINE ROOMS' inline code field
	if not OS.has_feature("web") or _page != "online":
		return
	var ui = JavaScriptBridge.get_interface("OozeRoom")
	if ui == null:
		return
	var code := str(ui.takeCode())                             # the dialog's code, or Enter in the inline field
	if code.length() == 4:
		_code_error = ""
		_code_value = code
		ArmyPresets.send_to(Net, faction)                         # the register carries your ARMIES preset
		Net.join_room(code, faction)
		show_lobby()


func _exit_tree() -> void:
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeRoom")
		if ui != null:
			ui.closeCode()
		if _code_inline:                                 # UI: ONLINE ROOMS' inline code field, if it is up
			JavaScriptBridge.eval("window.OozeRoom&&OozeRoom.removeCode&&OozeRoom.removeCode()", true)
		if _name_inline:                                 # PROGRESSION: the HTML name field, if it is up
			JavaScriptBridge.eval("window.OozeName&&OozeName.remove()", true)


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
	if _shell:                                        # UI: a shell page spans the whole screen (bars edge to edge)
		content.size = vp / s
		content.position = Vector2.ZERO
		if _built_w > 0.0 and _last_show.is_valid() and absf(content.size.x / _built_w - 1.0) > 0.02:
			_built_w = 0.0
			_last_show.call_deferred()
			return
	# A page's tap heights and text sizes (rh / tap / fsz) are computed from the screen when it is built: a page
	# built in portrait, or mid-rotation / fullscreen switch, kept giant buttons after the phone turned (0.20.2,
	# Daniele: "emergency this is what my gf see"). When the phone sizing moves by more than 10 %, rebuild it.
	if _built_pt > 0.0 and _last_show.is_valid():
		var f := _pt_factor()
		if f > 0.0 and absf(f / _built_pt - 1.0) > 0.1:
			_built_pt = 0.0
			_last_show.call_deferred()
