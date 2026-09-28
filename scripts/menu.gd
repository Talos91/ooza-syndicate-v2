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


func show_options() -> void:
	_last_show = show_options                  # a resize that changes the phone sizing rebuilds it (_fit)
	clear_page("city")
	header(0)
	label_at("OPTIONS", P(40, 107), 43)
	frame(P(35, 174), P(1000, 600))
	# a scrollable stack (stack_open()): on mobile every toggle row grows to the 44 pt tap minimum, which
	# would no longer fit this frame stacked at the desktop gaps - scrolling keeps every row full size
	# instead of shrinking them back down or hiding rows.
	var st := stack_open(P(45, 190), P(980, 566))
	var y := 5.0
	stack_add(st, label_at("MATCH RULES", P(15, y), 30))
	y += 41.0
	# one game: BRAWL (Daniele, 0.18.7: "for now completely deactivate [SIEGE] ... brawl is our game (can
	# also remove mode selector)") - no MODE switch here, in SETUP, the lobby, the pause menu or Debug
	var h1 := rh(66)
	var lsb := stack_add(st, nav_button("LAST STAND: %s" % (("ON  -  the map collapses from %d:%02d" % [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60])
			if Rules.last_stand else ("OFF  -  no collapse; the %d:%02d safety net still ends a stalled match" % [int(Rules.MATCH_HARD_END) / 60, int(Rules.MATCH_HARD_END) % 60])),
			P(15, y), P(915, h1), func():
		Rules.last_stand = not Rules.last_stand
		show_options())) as Button
	lsb.add_theme_font_size_override("font_size", int(round(fsz(21) * K)))
	y += h1 + 12.0
	var h2 := rh(60)
	var hec := stack_add(st, nav_button("ENEMY COUNTS: %s" % ("HIDDEN  -  no unit numbers on enemy nodes" if Rules.hide_enemy_counts else "SHOWN  -  every node's count, as in Alpha 11"),
			P(15, y), P(915, h2), func():
		Rules.hide_enemy_counts = not Rules.hide_enemy_counts
		show_options())) as Button
	hec.add_theme_font_size_override("font_size", int(round(fsz(21) * K)))
	y += h2 + 12.0
	if not mobile:                                    # the button text already carries the state; the phone skips the recap to save room
		stack_add(st, label_at("Last Stand: the map collapses ring by ring late in the match. Hidden counts make you scout.", P(15, y), 18, Color("b8ced6")))
		y += 34.0
	y += 20.0
	stack_add(st, label_at("PERFORMANCE", P(15, y), 30))
	y += 41.0
	var h3 := rh(60)
	var det := stack_add(st, nav_button("DETAIL: %s" % ("FULL" if not Rules.low_detail else "LOW  -  fewer river patches and vat residents"),
			P(15, y), P(915, h3), func():
		Rules.low_detail = not Rules.low_detail
		show_options())) as Button
	det.add_theme_font_size_override("font_size", int(round(fsz(22) * K)))
	y += h3 + 12.0
	if not mobile:
		stack_add(st, label_at("Low detail trims the river patches and vat residents - use it if the game makes your machine run hot.", P(15, y), 18, Color("b8ced6")))
		y += 34.0
	# --- Alpha 21 OPT-RENDER: GRAPHICS AUTO / LOW RES / FULL and FPS AUTO / 30 / 60 (perf_profile.gd, user://settings.cfg) ---
	var h4 := rh(60)
	var gfx := stack_add(st, nav_button(PerfProfile.label(), P(15, y), P(600, h4), func():
		PerfProfile.set_mode(PerfProfile.next_mode())
		show_options())) as Button
	gfx.add_theme_font_size_override("font_size", int(round(fsz(22) * K)))
	var fpb := stack_add(st, nav_button(PerfProfile.fps_label(), P(627, y), P(303, h4), func():
		PerfProfile.set_fps(PerfProfile.next_fps())
		show_options())) as Button
	fpb.add_theme_font_size_override("font_size", int(round(fsz(22) * K)))
	fpb.disabled = PerfProfile.level() == "low"      # LOW RES stays at 30
	y += h4 + 12.0
	if not mobile:
		stack_add(st, label_at("LOW RES: 30 fps, no glow or shadows, fewer effects and lighter models - only for weak phones. From the next match.", P(15, y), 18, Color("b8ced6")))
		y += 34.0
	# --- end OPT-RENDER ---
	# TERRITORY moved to ARMIES > COSMETICS > CORE (0.19.2, Daniele: "goo/neon should be in the choice of
	# cosmetic, as general core one maybe") - one place only, so it isn't duplicated here any more.
	var h5 := rh(50)
	var dbg := stack_add(st, nav_button("DEBUG TOOLS: %s" % ("ON  -  the Debug button and live sliders in matches" if Rules.debug_tools else "OFF"),
			P(15, y), P(915, h5), func():
		Rules.debug_tools = not Rules.debug_tools
		show_options())) as Button
	dbg.add_theme_font_size_override("font_size", int(round(fsz(20) * K)))
	y += h5 + 10.0
	var h6 := rh(50)                                   # PROGRESSION: see the game as players will once the locks go live
	var lk := stack_add(st, nav_button("TEST SWITCH  ·  LOCKS: %s" % ("OFF  -  everything unlocked (the testing default)" if Progression.unlock_all
			else "ON  -  preview: skills and looks earned or bought (until the page closes)"), P(15, y), P(915, h6), func():
		Progression.unlock_all = not Progression.unlock_all
		show_options())) as Button
	lk.add_theme_font_size_override("font_size", int(round(fsz(20) * K)))
	y += h6 + 10.0
	stack_close(st, y)
	nav_button("BACK", P(40, foot_y()), P(230, 58), show_main)


func show_factions() -> void:
	## 01 FACTION (screen system 03): the roster - five tiles, the picked one lit (a tap picks it: `faction`, and the
	## page's accent) - the picked faction large (its character, name, tagline, persistent trait, stats) and its army
	## preset (01 active / 02 map / 03 ultimate: each row opens ARMIES on it, as does EDIT IN ARMIES); NEXT: BATTLEFIELD.
	_last_show = show_factions                  # a resize that changes the phone sizing rebuilds it (_fit)
	var area := shell_open("OOZE / FACTION", "play", show_play, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "01 / FACTION", "PICK YOUR SYNDICATE.")
	var gap := 10.0
	var th := UiKit.tap_h(self, 58.0)
	var tw := (w - gap * 4.0) / 5.0
	for i in range(FACTIONS.size()):
		_roster_tile(FACTIONS[i], Vector2(x + i * (tw + gap), y), Vector2(tw, th))
	y += th + 14.0
	# the foot: the note (where it fits), EDIT IN ARMIES, NEXT
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var nt := "NEXT: BATTLEFIELD  →"
	var nw := UiKit.text_w(self, nt, 17, true) + 48.0
	UiKit.btn(self, nt, Vector2(content.size.x - x - nw, fy), Vector2(nw, 48), show_maps, "primary", faction, 17)
	var et := "EDIT IN ARMIES  ›"
	var ew := UiKit.text_w(self, et, 15, true) + 40.0
	var ex := content.size.x - x - nw - 12.0 - ew
	UiKit.btn(self, et, Vector2(ex, fy), Vector2(ew, 48), func(): show_armies(faction, show_factions), "secondary", faction, 15)
	var note := "Faction identity is separate from your team colour."
	if UiKit.text_w(self, note, 15) < ex - x - 16.0:
		_shell_add(UiKit.label(self, note, 15, UiKit.MUTED), Vector2(x, fy + (bh - UiKit.line_h(self, 15)) / 2.0))
	var ch := fy - 14.0 - y
	var lw := floorf(w * 0.52)
	_faction_card(Vector2(x, y), Vector2(lw, ch))
	_preset_rows(Vector2(x + lw + 14.0, y), Vector2(w - lw - 14.0, ch))


func _cutout(f: String, pos: Vector2, dims: Vector2) -> TextureRect:
	## The faction's character cutout, not yet placed (a tile's or a chip's child; UiKit.hero adds it to the page).
	var r := TextureRect.new()
	r.texture = load(UiKit.hero_path(f))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = dims
	return r


func _roster_tile(f: String, pos: Vector2, dims: Vector2) -> void:
	## FACTION's roster tile: the character and the name; the picked one in its accent. A tap picks the faction.
	var picked := f == faction
	var b := UiKit.btn(self, "", pos, dims, func():
		faction = f
		main.SEAT_FACTIONS[main.HUMAN] = f
		show_factions(), "selected" if picked else "secondary", f)
	var hs := b.size.y - 10.0
	b.add_child(_cutout(f, Vector2(6, 5), Vector2(hs, hs)))
	var tx := hs + 16.0
	var nm := UiKit.label(self, UiKit.NAMES[f], 15, UiKit.accent(f) if picked else UiKit.INK, true)
	var sl := UiKit.label(self, UiKit.SUBS[f], 12, UiKit.MUTED)
	var nh := UiKit.line_h(self, 15, true)
	var two := nh + UiKit.line_h(self, 12) <= b.size.y - 6.0
	var ty := (b.size.y - (nh + (UiKit.line_h(self, 12) if two else 0.0))) / 2.0
	for l in ([nm, sl] if two else [nm]):
		l.clip_text = true
		l.position = Vector2(tx, ty)
		l.size = Vector2(maxf(10.0, b.size.x - tx - 8.0), l.get_minimum_size().y)
		b.add_child(l)
		ty += nh


func _faction_card(pos: Vector2, dims: Vector2) -> void:
	## FACTION's big card: the character over its glow, the name block with the persistent trait, the five stats
	## (Rules.stat, as 01 FACTION always showed them) under a rule.
	var acc := UiKit.accent(faction)
	UiKit.panel(self, pos, dims, faction)
	var pad := 18.0
	var stat_h := UiKit.line_h(self, 22, true) + UiKit.line_h(self, 12)
	var sy := pos.y + dims.y - pad - stat_h
	var body_h := sy - 14.0 - (pos.y + pad)
	var hs := minf(body_h, dims.x * 0.42)
	UiKit.hero(self, faction, Vector2(pos.x + pad, pos.y + pad + (body_h - hs) / 2.0), Vector2(hs, hs))
	var tx := pos.x + pad + hs + 18.0
	var tw := pos.x + dims.x - pad - tx
	var ft: Array = Rules.FACTION_TRAITS[faction]
	# [text, size, colour, head, spacing, optional] - the tagline goes first when a phone runs out of room
	var lines := [[UiKit.SUBS[faction], 12, acc, true, 3, false], [UiKit.NAMES[faction], 38, acc, true, 0, false],
			[Rules.FACTION_TAGLINES[faction], 15, UiKit.MUTED, false, 0, true], ["", 10, UiKit.INK, false, 0, false],
			["PERSISTENT TRAIT  ·  COMING SOON", 12, acc, true, 2, false], [str(ft[0]).to_upper(), 16, UiKit.INK, true, 0, false],
			[str(ft[1]), 14, UiKit.MUTED, false, 0, false]]
	var total := 0.0
	var hts := []
	for ln in lines:
		if int(ln[4]) > 0 and UiKit.text_w(self, ln[0], ln[1], ln[3]) + str(ln[0]).length() * float(ln[4]) > tw:
			ln[0] = str(ln[0]).replace("  ·  ", "
")          # a spaced kicker too wide: one part per line
		var h: float = float(ln[1]) if ln[0] == "" else (UiKit.line_h(self, ln[1], ln[3]) * (str(ln[0]).count("
") + 1) + 2.0
				if int(ln[4]) > 0 else UiKit.text_h(self, ln[0], ln[1], tw, ln[3]) + 2.0)
		hts.append(h)
		total += h
	if total > body_h:                                       # no room for the tagline (phones)
		total -= hts[2]
		hts[2] = -1.0
	var ly := pos.y + pad + maxf(0.0, (body_h - total) / 2.0)
	for i in range(lines.size()):
		var ln: Array = lines[i]
		if hts[i] < 0.0:
			continue
		if ln[0] != "":
			var l := UiKit.label(self, ln[0], ln[1], ln[2], ln[3], ln[4])
			if int(ln[4]) == 0:
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(tw, 0)
			_shell_add(l, Vector2(tx, ly))
		ly += hts[i]
	# the stats
	content.add_child(UiKit.rect(Vector2(pos.x + pad, sy - 12.0), Vector2(dims.x - pad * 2.0, 1.0), UiKit.FRAME))
	var rows := [["speed", "Speed", "Faster", "Slower"], ["health", "Health", "Tougher", "Fragile"],
			["attack", "Attack", "Stronger", "Weaker"], ["production", "Production", "Faster", "Slower"],
			["garrison", "Garrison", "Stronger", "Weaker"]]
	var sw := (dims.x - pad * 2.0) / float(rows.size())
	for i in range(rows.size()):
		var r: Array = rows[i]
		var v := Rules.stat(faction, r[0])
		var rating: String = r[2] if v > 1.001 else (r[3] if v < 0.999 else "Baseline")
		var cap := "%s · %s" % [r[1], rating]
		if UiKit.text_w(self, cap, 12) > sw - 10.0:            # phones: the name only; the value's colour carries the rest
			cap = r[1]
		UiKit.stat(self, Vector2(pos.x + pad + i * sw, sy), "%d%%" % roundi(v * 100.0), cap,
				acc if v > 1.001 else (Color("ffb12b") if v < 0.999 else UiKit.INK))


func _preset_rows(pos: Vector2, dims: Vector2) -> void:
	## FACTION's army preset (SKILLS 2.0): 01 the active skill, 02 the map skill, 03 the faction's ultimate.
	var lo := ArmyPresets.loadout_for(faction)
	var ids := [lo["active"], lo["map"], Rules.FACTION_ULTIMATE_ID[faction]]
	var kicks := ["ACTIVE SKILL  ·  ARMY PRESET", "MAP SKILL  ·  ARMY PRESET", "ULTIMATE  ·  %s ONLY" % UiKit.NAMES[faction]]
	var gap := 10.0
	var h := (dims.y - gap * 2.0) / 3.0
	for i in range(3):
		_skill_row(pos + Vector2(0, i * (h + gap)), Vector2(dims.x, h), "%02d" % (i + 1), ids[i], kicks[i], i == 2)


func _skill_row(pos: Vector2, dims: Vector2, num: String, id: String, kicker: String, ultimate: bool) -> void:
	## One preset row: the slot number, the skill's icon, kicker + cooldown, name, its line; the row opens ARMIES.
	var acc := UiKit.accent(faction)
	var b := UiKit.btn(self, "", pos, dims, func(): show_armies(faction, show_factions), "secondary", faction)
	var h := b.size.y
	var pad := 14.0
	var n := UiKit.label(self, num, 24, acc, true)
	n.position = Vector2(pad, (h - UiKit.line_h(self, 24, true)) / 2.0)
	b.add_child(n)
	var ix := pad + UiKit.text_w(self, num, 24, true) + 12.0
	var isz := minf(h - pad * 2.0, 64.0)
	skill_icon(id, Vector2(ix, (h - isz) / 2.0), Vector2(isz, isz), acc, b)
	var tx := ix + isz + 14.0
	var tw := dims.x - tx - 34.0
	var kh := UiKit.line_h(self, 11, true)
	var thh := UiKit.line_h(self, 18, true)
	var dl := UiKit.line_h(self, 14)
	var dn := clampi(int((h - pad - kh - thh) / dl), 0, 2)
	var desc := ArmyPresets.line(id)
	var need := mini(dn, int(ceil(UiKit.text_h(self, desc, 14, tw) / dl - 0.1)))
	var ty := (h - (kh + thh + need * dl)) / 2.0
	var cd := ArmyPresets.cd_text(id) + ("" if ultimate else " CD")
	var cdw := UiKit.text_w(self, cd, 12)
	var cl := UiKit.label(self, cd, 12, UiKit.STAR if ultimate else UiKit.MUTED)
	cl.position = Vector2(dims.x - 34.0 - cdw, ty)
	b.add_child(cl)
	var kw := maxf(10.0, tw - cdw - 12.0)
	if UiKit.text_w(self, kicker, 11, true) + kicker.length() * 2.0 > kw:   # phones: "ACTIVE SKILL" without the preset note
		kicker = kicker.get_slice("  ·  ", 0)
	var k := UiKit.label(self, kicker, 11, acc, true, 2)
	k.clip_text = true
	k.position = Vector2(tx, ty)
	k.size = Vector2(kw, kh)
	b.add_child(k)
	var t := UiKit.label(self, ArmyPresets.skill_name(id).to_upper(), 18, UiKit.INK, true)
	t.clip_text = true
	t.position = Vector2(tx, ty + kh)
	t.size = Vector2(tw, thh)
	b.add_child(t)
	if need > 0:
		var d := UiKit.label(self, desc, 14, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.max_lines_visible = need
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.clip_text = true
		d.position = Vector2(tx, ty + kh + thh)
		d.size = Vector2(tw, need * dl)
		b.add_child(d)
	var c := UiKit.label(self, "›", 22, UiKit.MUTED)
	c.position = Vector2(dims.x - 24.0, (h - UiKit.line_h(self, 22)) / 2.0)
	b.add_child(c)


# ------------------------------------------------------------------ TUTORIAL (TUTORIAL-DESIGN.md §7)
func show_tutorial() -> void:
	## TRAINING (screen system 11, a PLAY subflow): the shell with "TRAINING / n OF 10", and in its free area the
	## TutorialPage (host_in) - the ten lesson rows (any order, a tick when done), CONTINUE = the first lesson not
	## done. BACK (the shell's) goes through the page's back_pressed. A lesson starts with the faction and colour
	## picked here last (NEW GAME's picks).
	_last_show = show_tutorial                  # a resize that changes the phone sizing rebuilds it (_fit)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tutorial-cfg=") and TutorialDirector.path != arg.substr(15):   # UI: screenshots
			TutorialDirector.path = arg.substr(15)
			TutorialDirector.reload_progress()
	var page := TutorialPage.new()
	var area := shell_open("OOZE / TRAINING", "play", func(): page.back_pressed.emit())
	var top := page_title(area, "%s / %d OF %d" % [TutorialDirector.line("page_title"), TutorialDirector.done_count(),
			TutorialDirector.TOTAL_LESSONS], "LEARN THE CITY.")
	_tut_page = page
	_tut_page.standalone_backdrop = false             # the menu's own backdrop shows through
	_tut_page.set_faction(shell_f)
	_tut_page.set_mobile(mobile)
	_tut_page.set_lessons(TutorialDirector.lesson_rows())
	_tut_page.set_progress_note("" if TutorialDirector.saved else TutorialDirector.line("no_storage"))
	_tut_page.host_in(self, Rect2(0, top, content.size.x, area.end.y - top))
	_tut_page.continue_pressed.connect(func(): _start_lesson(TutorialDirector.first_unfinished()))
	_tut_page.lesson_pressed.connect(_start_lesson)
	_tut_page.back_pressed.connect(show_main)
	content.add_child(_tut_page)
	shell_raise()


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
	## PROFILE: level and XP, both balances and where they come from, per faction plays / wins and the faction
	## vat's progress (25 wins online or vs Veteran / Expert AI), and whether it is saved on this device.
	clear_page("city")
	_page = "profile"
	header(0)
	label_at("PROFILE", P(40, 104), 43)
	label_at("LEVEL, SCRAP, CHIPS AND YOUR FACTIONS  ·  earned by playing", P(300, 122), 20, Color("abc1cd"))
	var lf := Progression.level_for(Progression.xp)
	var lp := P(35, 174)
	frame(lp, P(560, 600))
	label_at("LEVEL %d" % int(lf["level"]), lp + P(28, 20), 56)
	_bar(lp + P(28, 108), P(500, 16), float(lf["into"]) / maxf(1.0, float(lf["need"])), Color("5fd7ff"))
	label_at("%d / %d XP TO LEVEL %d" % [int(lf["into"]), int(lf["need"]), int(lf["level"]) + 1], lp + P(28, 132), 18, Color("9cb2bf"))
	var PR := Rules.PROGRESSION
	# the explanations wrap inside the frame at their designed size (a dense box - see label_at())
	_wrapped("EVERY LEVEL +%d SCRAP  ·  EVERY %dTH ALSO +%d CHIPS" % [int(PR["level_soft"]), int(PR["level_premium_every"]),
			int(PR["level_premium"])], lp + P(28, 162), 16, Color("7795a4"), 500)
	_balance(Progression.balance("soft"), "soft", lp + P(24, 216), K * 1.6)
	_wrapped("Matches (from Veteran AI up), challenges, the tutorial and the campaign. A skill costs %s." % Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false),
			lp + P(28, 284), 17, Color("c5d2da"), 500)
	_balance(Progression.balance("premium"), "premium", lp + P(24, 364), K * 1.6)
	_wrapped("Weekly challenges and every %dth level; the store later. For looks only - never skills." % int(PR["level_premium_every"]),
			lp + P(28, 432), 17, Color("c5d2da"), 500)
	if Progression.unlock_all:
		label_at("UNLOCKS OPEN WHILE TESTING (OPTIONS > TEST SWITCH)", lp + P(28, 530), 16, Color("ffd15c"), false)
	# factions
	var fp := P(620, 174)
	frame(fp, P(1017, 600))
	label_at("FACTIONS", fp + P(24, 16), 28)
	label_at("%d WINS WITH A FACTION UNLOCK ITS VAT  ·  ONLINE, OR VS VETERAN / EXPERT AI" % int(PR["faction_vat_wins"]),
			fp + P(210, 26), 16, Color("8fb3c2"), false)
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var rp := fp + P(24, 70 + i * 104)
		var fc: Color = Rules.FACTIONS[f][1]
		var st := Progression.faction_stats(f)
		portrait(f, rp, P(86, 92))
		label_at("VIRIDIAN" if f == "bloom" else f.to_upper(), rp + P(104, 6), 26, fc, false)
		label_at("PLAYED %d  ·  WON %d" % [int(st["plays"]), int(st["wins"])], rp + P(104, 44), 19, Color("dbe6ec"), false)
		var need: int = PR["faction_vat_wins"]
		var owned := Progression.owns("vat:faction:" + f)
		_bar(rp + P(470, 30), P(360, 14), 1.0 if owned else float(st["vat_wins"]) / float(need), fc)
		label_at("VAT UNLOCKED" if owned else "VAT  %d / %d WINS" % [int(st["vat_wins"]), need], rp + P(470, 54), 17,
				fc if owned else Color("9cb2bf"), false)
	nav_button("BACK", P(40, foot_y()), P(210, 58), show_main)
	nav_button("CHALLENGES", P(265, foot_y()), P(270, 58), show_challenges)
	nav_button("LEADERBOARD", P(550, foot_y()), P(290, 58), show_leaderboard)    # 0.20.5
	nav_button("HISTORY", P(855, foot_y()), P(230, 58), show_history)
	nav_button("ACCOUNT", P(1100, foot_y()), P(230, 58), show_account, _account().state == "guest")
	var acct := _account()
	var note := "Progress saved on this device" if Progression.saved else "This browser keeps no storage: progress lasts until the page closes"
	if acct.state == "linked":
		note = "Progress saved on this device and in your account"
	elif acct.state == "guest":
		note = "Guest account: add Google (ACCOUNT) to keep your progress on any device"
	_wrapped(note, lp + P(28, 560), 15, Color("7795a4") if Progression.saved else Color("ffd15c"), 500)


func show_challenges(just_claimed := "") -> void:
	_last_show = func(): show_challenges()                  # a resize that changes the phone sizing rebuilds it (_fit)
	## CHALLENGES: three daily and three weekly (the same for everyone, reset 00:00 UTC / Monday), progress from any
	## finished match (tutorial lessons excluded), CLAIM pays (the card counts it up), one daily REROLL a day.
	clear_page("city")
	_page = "challenges"
	header(0)
	label_at("CHALLENGES", P(40, 104), 43)
	label_at("PLAY ANY MATCH TO PROGRESS  ·  CLAIM TO COLLECT", P(380, 122), 20, Color("abc1cd"))
	for kind in ["daily", "weekly"]:
		var x := 35.0 if kind == "daily" else 845.0
		var cp := P(x, 174)
		frame(cp, P(792, 600))
		label_at(kind.to_upper(), cp + P(24, 16), 30)
		label_at("RESETS IN " + Progression.duration_text(Progression.seconds_to_reset(kind)).to_upper(), cp + P(210, 28), 17,
				Color("8fb3c2"), false)
		var list := Progression.current_challenges(kind)
		var rerolled: bool = Progression.challenges.get("daily", {}).get("rerolled", false)
		for i in range(list.size()):
			var c: Dictionary = list[i]
			var rp := cp + P(24, 76 + i * 172)
			content.add_child(neon_panel(rp, P(744, 158), color(), c["done"] and not c["claimed"], Color("08131ae8")))
			label_at(str(c["text"]), rp + P(18, 12), 24, Color.WHITE if not c["claimed"] else Color("7795a4"), false)
			_bar(rp + P(18, 60), P(440, 14), float(c["progress"]) / maxf(1.0, float(c["target"])), color())
			label_at("%d / %d" % [int(c["progress"]), int(c["target"])], rp + P(470, 52), 19, Color("dbe6ec"), false)
			var reward := "%s  ·  +%d XP" % [Progression.amount_text(int(c["soft"])), int(c["xp"])]
			if int(c["premium"]) > 0:
				reward += "  ·  " + Progression.amount_text(int(c["premium"]), "premium")
			label_at(reward, rp + P(18, 94), 18, Color("e08a3a"), false)
			var id: String = c["id"]
			var k: String = kind
			if c["claimed"]:
				if id == just_claimed:               # the paid SCRAP counts up on the card it came from
					var t := RewardTicker.make(int(c["soft"]), "soft", func(n: float) -> float: return n * K * 1.4)
					t.position = rp + P(540, 96)
					t.fit()
					content.add_child(t)
					t.play()
				else:
					label_at("CLAIMED", rp + P(600, 104), 19, Color("7795a4"), false)
			elif c["done"]:
				_card_button("CLAIM", rp, P(744, 158), func():
					if not Progression.claim(k, id).is_empty():
						show_challenges(id), true)
			elif kind == "daily" and not rerolled:
				var rb := _card_button("REROLL", rp, P(744, 158), func():
					Progression.reroll(id)
					show_challenges())
				rb.add_theme_font_size_override("font_size", int(round(fsz(19) * K)))
	nav_button("BACK", P(40, foot_y()), P(230, 58), show_main)
	nav_button("PROFILE", P(290, foot_y()), P(230, 58), show_profile)
	label_at("One reroll a day, for a daily you would rather swap.", P(985, foot_y() + 18.0), 18, Color("7795a4"), false)


func _card_button(text: String, card_pos: Vector2, card_dims: Vector2, call: Callable, primary := false) -> Button:
	## A card's action button in its bottom-right corner, inside the card at any phone size (0.20.5: REROLL grew
	## past the card's edge on phones - tap() makes it taller there, so place it from its grown height).
	var dims := tap(P(166, 58))
	var pos := card_pos + card_dims - dims - P(14, 8)
	return nav_button(text, pos, dims, call, primary, false)


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
	## A text field in the menu's style (email, name); the phone's own keyboard opens on tap.
	dims = tap(dims)
	var e := LineEdit.new()
	e.position = pos
	e.size = dims
	e.custom_minimum_size = dims
	e.placeholder_text = placeholder
	e.text = text
	e.add_theme_font_override("font", UI_FONT)
	e.add_theme_font_size_override("font_size", int(round(fsz(21) * K)))
	e.add_theme_stylebox_override("normal", Hud.panel_style())
	e.add_theme_stylebox_override("focus", Hud.panel_style(color()))
	e.virtual_keyboard_enabled = true
	content.add_child(e)
	return e


func show_account() -> void:
	_last_show = show_account                  # a resize that changes the phone sizing rebuilds it (_fit)
	## ACCOUNT (Daniele: an automatic guest, then Google to keep progress on any device - no email: "its a game why
	## would they want to do that"; a sign-in onto an account that already has progress keeps the account's). Guests are
	## never asked to verify anything; the game plays offline without it.
	var a := _account()
	clear_page("city")
	_page = "account"
	header(0)
	label_at("ACCOUNT", P(40, 104), 43)
	label_at("OPTIONAL  ·  the game plays offline without it", P(300, 122), 20, Color("abc1cd"))
	var lp := P(35, 174)
	frame(lp, P(760, 600))
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
	_wrapped(status, lp + P(28, 22), 22, col, 700)
	# rows advance by each control's grown height (rh / tap): on a phone the 44 pt fields are taller than designed
	var hh := rh(58)
	var y := 86.0
	label_at("NAME", lp + P(28, y), 18, Color("8fb3c2"), false)
	y += 28.0
	if OS.has_feature("web"):
		# the web build: Godot's LineEdit doesn't raise a phone keyboard, and a field focused from Godot's own input
		# handling doesn't either on Android (outside the tap's gesture - Daniele, 0.20.10: "keyboard still doesn't
		# appear"). So the NAME box IS a native HTML <input> laid over it (_place_name_field): the tap lands on the DOM
		# element itself and the phone raises its keyboard. RENAME (or Enter) saves what it holds.
		var box := _line_edit(lp + P(28, y), P(440, 58), "", "")   # the frame the HTML field sits on (never typed into)
		box.editable = false
		box.focus_mode = Control.FOCUS_NONE
		_name_box = box
		_name_enabled = a.signed_in()
		_name_value = a.player_name
		_place_name_field.call_deferred()
		var rw := nav_button("RENAME", lp + P(490, y), P(240, 58), func(): _rename_from_field())
		rw.disabled = not a.signed_in()
	else:
		var nm := _line_edit(lp + P(28, y), P(440, 58), "3-16 letters or digits", a.player_name)
		var rn := nav_button("RENAME", lp + P(490, y), P(240, 58), func():
			if await a.rename(nm.text):
				_account_note = "Name saved: " + a.player_name
			else:
				_account_note = a.last_error
			show_account())
		rn.disabled = not a.signed_in()
		nm.editable = a.signed_in()
	y += hh + 22.0
	if OS.has_feature("web") and not a.google_ready and a.state != "offline":
		a.check_google()                           # redraws through Account.changed when the answer differs
	var google_ok := OS.has_feature("web") and a.google_ready
	if a.state == "guest":
		label_at("KEEP YOUR PROGRESS ON ANY DEVICE", lp + P(28, y), 20, Color.WHITE, false)
		y += 32.0
		var g := nav_button("ADD GOOGLE", lp + P(28, y), P(440, 58), func():
			if not await a.google(true):
				_account_note = a.last_error
				show_account(), google_ok)
		g.disabled = not google_ok
		y += hh + 10.0
		_wrapped("Your progress is already kept in this guest account; Google keeps it on your other devices too.",
				lp + P(28, y), 16, Color("7795a4"), 700)
	# sign in with an account linked elsewhere: its progress replaces this device's
	var rp := P(815, 174)
	frame(rp, P(822, 600))
	label_at("ALREADY HAVE AN ACCOUNT?", rp + P(28, 22), 22, Color.WHITE, false)
	_wrapped("Sign in with the Google account you linked on another device. Its progress replaces this device's.",
			rp + P(28, 60), 18, Color("c5d2da"), 760)
	var ry := 130.0
	var gs := nav_button("SIGN IN WITH GOOGLE", rp + P(28, ry), P(480, 58), func():
		if not await a.google(false):
			_account_note = a.last_error
			show_account())
	gs.disabled = not google_ok
	ry += hh + 10.0
	if not OS.has_feature("web"):
		_wrapped("Google sign-in works in the browser build.", rp + P(28, ry), 16, Color("7795a4"), 760)
		ry += 30.0
	elif not a.google_ready and a.state != "offline":
		_wrapped("Google sign-in isn't available right now.", rp + P(28, ry), 16, Color("7795a4"), 760)
		ry += 30.0
	if _account_note != "":
		_wrapped(_account_note, rp + P(28, ry + 10.0), 19, Color("ffd15c"), 760)
	nav_button("BACK", P(40, foot_y()), P(230, 58), func():
		_account_note = ""
		show_profile())


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
	## LEADERBOARD: WINS THIS SEASON (the UTC month) - online wins in server rooms with two or more players,
	## written by the server only. Reads it when opened; offline says so.
	clear_page("city")
	_page = "leaderboard"
	header(0)
	label_at("LEADERBOARD", P(40, 104), 43)
	var now := Time.get_datetime_dict_from_system(true)
	label_at("WINS THIS SEASON  ·  %s %d  ·  online, server rooms with 2+ players" % [MONTHS[int(now["month"]) - 1], int(now["year"])],
			P(400, 122), 20, Color("abc1cd"))
	var fp := P(35, 174)
	frame(fp, P(1602, 600))
	if _board_state == "idle":
		_board_state = "loading"
		_load_board()
	if _board_state == "loading":
		label_at("LOADING ...", fp + P(30, 30), 24, Color("9cb2bf"), false)
	elif _board_state == "offline":
		label_at("The leaderboard needs a connection.", fp + P(30, 30), 24, Color("ffd15c"), false)
	elif _board_rows.is_empty():
		_wrapped("No wins yet this season - win an online match against another player to open the board.", fp + P(30, 30),
				24, Color("9cb2bf"), 1500)
	else:
		var st := stack_open(fp + P(16, 16), P(1570, 568))
		var ry := 0.0
		for row in _board_rows:
			var me := bool(row.get("is_me", false))
			var h := rh(56)
			stack_add(st, _placed(neon_panel(P(0, ry), P(1560, h), color(), me, Color("08202ae8") if me else Color("020a10d8"))))
			stack_add(st, label_at("#%d" % int(row.get("rank", 0)), P(20, ry + h * 0.2), 24, Color("ffd15c"), false))
			stack_add(st, label_at(str(row.get("name", "")) + ("  (YOU)" if me else ""), P(160, ry + h * 0.2), 24,
					Color.WHITE, false))
			stack_add(st, label_at("%d WINS" % int(row.get("wins", 0)), P(1320, ry + h * 0.2), 24, Color("6fff2a"), false))
			ry += h + 8.0
		if not _board_me.is_empty():                  # 0.20.13: YOU, when you're not on the list - a row like the rest
			var h := rh(56)
			var wins := int(_board_me.get("wins", 0))
			stack_add(st, _placed(neon_panel(P(0, ry + 8.0), P(1560, h), Color("ffd15c"), true, Color("08202ae8"))))
			stack_add(st, label_at("#%d" % int(_board_me.get("rank", 0)) if wins > 0 else "-", P(20, ry + 8.0 + h * 0.2), 24, Color("ffd15c"), false))
			stack_add(st, label_at(str(_board_me.get("name", "")) + "  (YOU)" + ("" if wins > 0 else "  ·  win an online round vs a player"),
					P(160, ry + 8.0 + h * 0.2), 24, Color.WHITE, false))
			stack_add(st, label_at("%d WINS" % wins, P(1320, ry + 8.0 + h * 0.2), 24, Color("ffd15c"), false))
			ry += h + 16.0
		stack_close(st, ry * K)
	nav_button("BACK", P(40, foot_y()), P(230, 58), func():
		_board_state = "idle"
		show_profile())
	nav_button("REFRESH", P(290, foot_y()), P(230, 58), func():
		_board_state = "idle"
		show_leaderboard())



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
	## here) plus the server's record of your online rounds from other devices; newest first, ONLINE / OFFLINE tags.
	var a := _account()
	clear_page("city")
	_page = "history"
	header(0)
	label_at("MATCH HISTORY", P(40, 104), 43)
	label_at("YOUR RECENT MATCHES  ·  this device" + (" + your account's online rounds" if a.signed_in() else ""),
			P(420, 122), 20, Color("abc1cd"))
	if _history_state == "idle" and a.signed_in():
		_history_state = "loading"
		_load_history(false)
	var list := Progression.merge_history(Progression.history, _history_online)
	var fp := P(35, 174)
	frame(fp, P(1602, 600))
	if list.is_empty():
		_wrapped("No matches yet - finish one and it shows here.", fp + P(30, 30), 24, Color("9cb2bf"), 1500)
	else:
		var names := _map_names()
		var st := stack_open(fp + P(16, 16), P(1570, 568))
		var ry := 0.0
		for h in list:
			var rowh := rh(92)
			var won := bool(h.get("won", false))
			var draw := bool(h.get("draw", false))
			var res := "DRAW" if draw else ("WIN" if won else "LOSS")
			var rc := Color("9cb2bf") if draw else (Color("6fff2a") if won else Color("ff5a4a"))
			stack_add(st, _placed(neon_panel(P(0, ry), P(1560, rowh), rc.darkened(0.3), false, Color("020a10d8"))))
			var online := bool(h.get("online", false))
			stack_add(st, label_at("ONLINE" if online else "OFFLINE", P(16, ry + 8), 15, Color("5fd7ff") if online else Color("839da9"), false))
			stack_add(st, label_at(_date_text(int(h.get("t", 0))), P(16, ry + 34), 17, Color("c5d2da"), false))
			var code := str(h.get("map", ""))
			stack_add(st, label_at(code + "  " + str(names.get(code, "")), P(220, ry + 8), 20, Color.WHITE, false))
			var dur := int(h.get("duration_s", 0))
			stack_add(st, label_at("%s  ·  %d:%02d" % [str(Menu.MODE_NAMES.get(str(h.get("mode", "")), str(h.get("mode", "")))), dur / 60, dur % 60],
					P(220, ry + 40), 17, Color("9cb2bf"), false))
			var px := 760.0
			for p in h.get("players", []):
				if not p is Dictionary:
					continue
				var f := str(p.get("faction", "null"))
				var tex := Hud.emblem_texture(f) if Rules.FACTIONS.has(f) else null
				if tex != null:
					var ic := TextureRect.new()
					ic.texture = tex
					ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					ic.position = P(px, ry + 10)
					ic.size = P(34, 34)
					ic.modulate = Rules.FACTIONS[f][1]
					ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
					content.add_child(ic)
					stack_add(st, ic)
				var who := "YOU" if bool(p.get("is_me", false)) and str(p.get("name", "")) == "" else str(p.get("name", ""))
				if str(p.get("ai_level", "")) != "":
					who = "AI" if str(p["ai_level"]) == "AI" else "AI " + str(p["ai_level"]).to_upper()
				elif who == "":
					who = "PLAYER"
				stack_add(st, label_at(who, P(px - 10, ry + 50), 14, Color.WHITE if bool(p.get("is_me", false)) else Color("9cb2bf"), false))
				px += 120.0
			stack_add(st, label_at(res, P(1420, ry + 22), 28, rc, false))
			ry += rowh + 8.0
		stack_close(st, ry * K)
	nav_button("BACK", P(40, foot_y()), P(230, 58), func():
		_history_state = "idle"
		_history_online = []
		show_profile())
	if a.signed_in() and _history_more and not _history_online.is_empty():
		nav_button("MORE", P(290, foot_y()), P(230, 58), func(): _load_history(true))
	if _history_state == "loading":
		label_at("LOADING ONLINE ROUNDS ...", P(985, foot_y() + 18.0), 18, Color("9cb2bf"), false)


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
# CAMPAIGN (Alpha 21 UI pass, screen system 09 / 28): the hub - one district's missions as image cards (Campaign.hub),
# district paging, CHAPTERS (the faction picker) and CITY MAP (the 3D district diorama, CampaignPage, its own canvas
# over the backdrop). The hub is the CAMPAIGN tab and the page a mission returns to (menu_open = "campaign").
# Screenshot / test args: --campaign-all (every playable mission open), --campaign-cfg=<path> (read progress from
# another file), --campaign-district=<id> (the district shown), --campaign-card=<key> (opens the CITY MAP on that
# card); the last two are used once per menu.
var _camp_page: CampaignPage
var _hub_f := ""                                   # UI: the campaign the hub shows ("" = yours, else the first with content)
var _hub_i := -1                                   # UI: its district (-1 = the district of the next mission)
var _camp_args_used := false


func _campaign_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--campaign-all":
			Campaign.all_open = true
		elif arg.begins_with("--campaign-cfg=") and Campaign.path != arg.substr(15):
			Campaign.path = arg.substr(15)
			Campaign.reload_all()                      # the top bar may have read the default file already


func _hub_faction() -> String:
	## The campaign on show: the one picked in CHAPTERS, else yours, else the first with content.
	for f in [_hub_f, faction] + Campaign.FACTION_ORDER:
		if f != "" and Campaign.has_content(f):
			return f
	return ""


func show_campaign() -> void:
	## CAMPAIGN HUB (screen system 09), on the district of the next mission.
	_campaign_args()
	_hub_i = -1
	if not _camp_args_used:
		_camp_args_used = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--campaign-card="):
				show_city_map()
				return
			if arg.begins_with("--campaign-district="):
				var ds := Campaign.districts(_hub_faction())
				for i in range(ds.size()):
					if str(ds[i]["id"]) == arg.substr(20):
						_hub_i = i
	_show_hub()


func _show_hub() -> void:
	## "CAMPAIGN / VEX BIOENGINEERS", the district's name and blurb; its missions as FrameCards in a row that swipes
	## sideways (number, the mission's art, title, stars; CONTINUE / PLAY / REPLAY, LOCKED with the reason, IN
	## DEVELOPMENT with what it needs); district paging and the stars at the foot; CITY MAP and CHAPTERS top right.
	_last_show = _show_hub
	var cf := _hub_faction()
	var h := Campaign.hub(cf, _hub_i) if cf != "" else {}
	var area := shell_open("OOZE / CAMPAIGN", "campaign")
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var bh := 42.0
	var bw := maxf(UiKit.text_w(self, "CHAPTERS", 15, true), UiKit.text_w(self, "CITY MAP", 15, true)) + 40.0
	var by := area.position.y + 18.0
	UiKit.btn(self, "CHAPTERS", Vector2(content.size.x - x - bw, by), Vector2(bw, bh), show_chapters, "secondary", shell_f, 15)
	if h.is_empty():                                   # no campaign has content (never in this build)
		page_title(area, "CAMPAIGN", "COMING LATER.")
		return
	_hub_i = int(h["district_index"])
	UiKit.btn(self, "CITY MAP", Vector2(content.size.x - x - bw * 2.0 - 12.0, by), Vector2(bw, bh), show_city_map,
			"secondary", shell_f, 15)
	var top := page_title(area, "CAMPAIGN / " + str(h["faction_title"]), str(h["district_name"]))
	var blurb := str(h["district_blurb"])              # "District 1 - where ..." : the foot already says which district
	if blurb.begins_with("District ") and blurb.find(" - ") > 0:
		blurb = blurb.substr(blurb.find(" - ") + 3)
		blurb = blurb.left(1).to_upper() + blurb.substr(1)
	var bl := UiKit.label(self, blurb, 15, UiKit.MUTED)
	bl.clip_text = true
	bl.size = Vector2(w - bw * 2.0 - 24.0, UiKit.line_h(self, 15))
	_shell_add(bl, Vector2(x, top - 10.0))
	top += UiKit.line_h(self, 15) - 2.0
	# the foot: district paging, the district's stars, the campaign's total
	var th := UiKit.tap_h(self, 42.0)
	var fy := area.end.y - th - 12.0
	var n := int(h["district_count"])
	var i := _hub_i
	var prev := UiKit.btn(self, "‹", Vector2(x, fy), Vector2(th, th), func(): _hub_page(i - 1), "secondary", shell_f, 22)
	prev.disabled = i <= 0
	var dl := UiKit.label(self, "DISTRICT %d OF %d" % [i + 1, n], 15, UiKit.INK, true, 2)
	var dw := UiKit.text_w(self, dl.text, 15, true) + dl.text.length() * 2.0
	_shell_add(dl, Vector2(x + th + 14.0, fy + (th - dl.get_minimum_size().y) / 2.0))
	var nxt := UiKit.btn(self, "›", Vector2(x + th + 28.0 + dw, fy), Vector2(th, th), func(): _hub_page(i + 1), "secondary", shell_f, 22)
	nxt.disabled = i >= n - 1
	var ds := UiKit.label(self, "★  %d / %d" % [int(h["stars"]), int(h["stars_max"])], 16, UiKit.STAR if int(h["stars"]) > 0 else UiKit.MUTED)
	_shell_add(ds, Vector2(x + th * 2.0 + 48.0 + dw, fy + (th - ds.get_minimum_size().y) / 2.0))
	var tt := "CAMPAIGN STARS   ★  %d / %d" % [Campaign.stars_total(cf), Campaign.stars_max(cf)]
	var tl := UiKit.label(self, tt, 16, UiKit.STAR if Campaign.stars_total(cf) > 0 else UiKit.MUTED, true)
	_shell_add(tl, Vector2(content.size.x - x - UiKit.text_w(self, tt, 16, true), fy + (th - tl.get_minimum_size().y) / 2.0))
	# the mission cards
	var cards: Array = h["missions"]
	var gap := 16.0
	var ch := fy - 14.0 - top
	var cw := (w - gap * (cards.size() - 1)) / cards.size() if cards.size() <= 3 else (w + gap) / 3.35 - gap
	var row := _card_row(Vector2(x, top), Vector2(w, ch), cards.size(), cw, gap)
	var scroll: TouchScroll = row[0]
	var focus := 0
	for k in range(cards.size()):
		var c: Dictionary = cards[k]
		var st := str(c["state"])
		var key := str(c["key"])
		var card := FrameCard.make(self, Vector2(cw, ch), shell_f, scroll)
		card.set_number(str(c["number"]))
		card.set_art(str(c["backdrop"]))
		card.set_title(str(c["title"]))
		card.set_kicker("NEXT MISSION" if st == "next" else {"side": "SIDE MISSION", "duel": "RIVAL DUEL", "finale": "FINALE"}.get(str(c["kind"]), ""))
		card.set_state(st)
		match st:
			"dev":
				card.set_note("IN DEVELOPMENT · needs %s" % str(c["needs"]))
			"locked":
				card.set_note(str(c["unlock_hint"]))
			_:
				card.set_stars(int(c["stars"]), int(c["stars_max"]))
				if not mobile:                         # a phone's card keeps its art: the stars say enough
					card.set_note(str(Campaign.mission(key).get("story", "")))
		if st == "next":
			focus = k
		card.pressed.connect(func(): _hub_play(key))
		card.position = Vector2(k * (cw + gap), 0)
		(row[1] as Control).add_child(card)
	if (focus + 1) * (cw + gap) > w:                   # the next mission is past the fold: start the row there
		var sx := int(focus * (cw + gap))
		(func(): scroll.scroll_horizontal = sx).call_deferred()
	shell_raise()


func _card_row(pos: Vector2, dims: Vector2, n: int, cw: float, gap: float) -> Array:
	## [TouchScroll, inner]: a row of `n` cards `cw` wide that swipes sideways when it is wider than `dims`
	## (a thin scrollbar under it for the mouse).
	var scroll := TouchScroll.new()
	scroll.horizontal = true
	scroll.size = dims + Vector2(0, 14.0)
	var grab := UiKit.sb(Color(UiKit.accent(shell_f), 0.7), Color(0, 0, 0, 0), 0, 2)
	grab.set_content_margin_all(3)
	var track := UiKit.sb(Color(UiKit.FRAME, 0.35), Color(0, 0, 0, 0), 0, 2)
	track.set_content_margin_all(3)
	var hb := scroll.get_h_scroll_bar()
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		hb.add_theme_stylebox_override(s, grab)
	hb.add_theme_stylebox_override("scroll", track)
	_shell_add(scroll, pos)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.custom_minimum_size = Vector2(n * (cw + gap) - gap, dims.y)
	scroll.add_child(inner)
	return [scroll, inner]


func _hub_page(i: int) -> void:
	_hub_i = i
	_show_hub()


func _hub_play(key: String) -> void:
	## CONTINUE / PLAY / REPLAY on a card (a locked or IN DEVELOPMENT one does nothing): the mission's briefing.
	var m := Campaign.mission(key)
	if not (Campaign.playable(m) and Campaign.is_open(key)):
		return
	UiKit.save_last_faction(Campaign.faction_of(key))   # UI: HOME's hero is the faction played last
	main.SEAT_FACTIONS[main.HUMAN] = faction           # your pick: the briefing's accent, the menu's after the mission
	if main.has_method("start_mission"):
		main.call("start_mission", key, colour)


func show_chapters() -> void:
	## CAMPAIGN CHAPTERS (screen system 28): one card per faction (Campaign.episodes) - its character, OPEN CAMPAIGN /
	## LOCKED / COMING LATER, its stars; the open one opens its hub. The overall progress at the foot.
	_last_show = show_chapters
	var area := shell_open("OOZE / CHAPTERS", "campaign", _show_hub)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var top := page_title(area, "CAMPAIGN", "CHOOSE YOUR SYNDICATE.")
	var th := UiKit.tap_h(self, 36.0)
	var fy := area.end.y - th - 10.0
	var pt := Campaign.progress_total()
	var pl := UiKit.label(self, "CAMPAIGN PROGRESS   ★  %d / %d" % [pt.x, pt.y], 16, UiKit.STAR if pt.x > 0 else UiKit.MUTED, true)
	_shell_add(pl, Vector2(x, fy + (th - pl.get_minimum_size().y) / 2.0))
	var eps := Campaign.episodes()
	var gap := 14.0
	var ch := fy - 12.0 - top
	var cw := (w - gap * (eps.size() - 1)) / eps.size()
	var min_w := 290.0 if UiKit.pt(self) > 0.0 else 210.0
	if cw < min_w:
		cw = (w + gap) / 3.4 - gap
	var row := _card_row(Vector2(x, top), Vector2(w, ch), eps.size(), cw, gap)
	for k in range(eps.size()):
		var ep: Dictionary = eps[k]
		var f := str(ep["faction"])
		var st := str(ep["state"])
		var card := FrameCard.make(self, Vector2(cw, ch), f, row[0])
		card.art_frac = 0.5
		card.set_hero(f)
		card.set_title(UiKit.NAMES.get(f, f.to_upper()), UiKit.SUBS.get(f, ""))
		card.set_kicker({"open": "OPEN CAMPAIGN", "locked": "LOCKED"}.get(st, "COMING LATER"))
		match st:
			"open":
				card.set_state("next")
				card.set_action("OPEN  →")
				card.set_note("%s  ·  ★ %d / %d" % [str(ep["title"]), int(ep["stars"]), int(ep["stars_max"])])
			"locked":
				card.set_state("locked")
				card.set_note("%s  ·  not unlocked yet" % str(ep["title"]))
			_:
				card.set_state("coming")
				card.set_note("Campaign not yet available")
		if st == "open":
			card.pressed.connect(func():
				_hub_f = f
				_hub_i = -1
				_show_hub())
		card.position = Vector2(k * (cw + gap), 0)
		(row[1] as Control).add_child(card)
	shell_raise()


func show_city_map() -> void:
	## CITY MAP: the 3D district diorama (CampaignPage - the campaign as the sinking city; its own canvas, animations
	## and cards); BACK returns to the hub.
	_last_show = Callable()                            # CampaignPage fits itself; a rebuild would reset its camera
	clear_page("city")
	_page = "campaign"
	_campaign_args()
	_camp_page = CampaignPage.new()
	_camp_page.standalone_backdrop = false
	_camp_page.set_faction(_hub_faction() if _hub_faction() != "" else faction)
	_camp_page.set_mobile(mobile)
	_camp_page.back_pressed.connect(_show_hub)
	_camp_page.play_pressed.connect(func(key: String):
		UiKit.save_last_faction(_camp_page.faction)     # UI: HOME's hero is the faction played last
		main.SEAT_FACTIONS[main.HUMAN] = faction       # your pick: the briefing's accent, the menu's after the mission
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


# ------------------------------------------------------------------ ARMIES (army presets, SKILLS 2.0; UI: screens 06-08)
const LOCK_COL := Color("ffb12b")                  # ARMIES: a locked skill or look, its price, its way in
const STAT_ROWS := [["speed", "SPEED"], ["health", "HEALTH"], ["attack", "ATTACK"], ["production", "PRODUCTION"],
		["garrison", "GARRISON"]]


func show_armies(f: String = "", back: Callable = Callable()) -> void:
	_last_show = func(): show_armies(f, back)                  # a resize that changes the phone sizing rebuilds it (_fit)
	## Daniele (0.18.7): "time to add armies presets and skills (its own new menu item where you select what
	## skill each of your factions will use, follow the skill file from faction ultimates and ability pool)".
	## UI (Alpha 21, screen 06): the five-faction roster (tap: that faction's preset, and the page takes its accent),
	## the open faction's character, trait and stats, its three slots - 01 active and 02 map (tap: SKILLS, the
	## pools), the fixed ultimate - COSMETICS and RESET. A top-level tab (HOME, the tab bar); a subflow with BACK
	## when FACTION, SETUP or the lobby opened it. Saved on the device at once.
	if f != "":
		_army = f
	if _army == "":
		_army = faction
	if back.is_valid():
		_army_back = back
	if not _army_back.is_valid():
		_army_back = show_main
	var sub := _army_back != show_main
	var area := shell_open("OOZE / ARMIES", "armies", (func(): _leave_armies()) if sub else Callable(), _army)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var top := page_title(area, "ARMIES", "YOUR SYNDICATE. YOUR RULES.")
	# COSMETICS and RESET, top right (left of the desktop BACK link)
	var right := _title_right()
	var bh := 44.0
	var rt := "RESET TO DEFAULT"
	var rw := UiKit.text_w(self, rt, 14, true) + 30.0
	var cw := UiKit.text_w(self, "COSMETICS", 15, true) + 44.0
	var by := area.position.y + (10.0 if shell_slim else 16.0)
	var rs := UiKit.btn(self, rt, Vector2(right - cw - 10.0 - rw, by), Vector2(rw, bh), func():
		ArmyPresets.reset(_army)
		_preset_changed()
		show_armies(), "tertiary", _army, 14)
	rs.disabled = ArmyPresets.is_default(_army)
	UiKit.btn(self, "COSMETICS", Vector2(right - cw, by), Vector2(cw, bh), func(): show_cosmetics(_army), "secondary", _army, 15)
	# the roster
	var th := UiKit.tap_h(self, 58.0)
	var gap := 10.0
	var tw := (w - gap * 4.0) / 5.0
	for i in range(FACTIONS.size()):
		_army_tile(FACTIONS[i], Vector2(x + i * (tw + gap), top), Vector2(tw, th))
	var y := top + th + 14.0
	var ph := area.end.y - 16.0 - y
	var lw := floorf((w - 14.0) * 0.5)
	_army_identity(Vector2(x, y), Vector2(lw, ph))
	_army_loadout(Vector2(x + lw + 14.0, y), Vector2(w - lw - 14.0, ph))


func _title_right() -> float:
	## The right edge a page's title-row controls end at: the margin, or left of page_title's BACK link.
	var r := content.size.x - shell_x()
	if shell_back.is_valid() and not shell_slim:
		r -= UiKit.text_w(self, "←  BACK", 15, true) + 20.0 + 18.0
	return r


func _army_tile(tf: String, pos: Vector2, dims: Vector2) -> void:
	## A roster tile: the faction's character cutout and name (YOU under yours); the open one lit in its accent.
	var picked := tf == _army
	var b := UiKit.btn(self, "", pos, dims, func(): show_armies(tf), "selected" if picked else "secondary", tf)
	var hs := dims.y - 8.0
	var art := TextureRect.new()
	art.texture = load(UiKit.hero_path(tf))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(8.0, 4.0)
	art.size = Vector2(hs, hs)
	b.add_child(art)
	var n := UiKit.label(self, UiKit.NAMES[tf], 15, UiKit.accent(tf) if picked else UiKit.INK, true)
	var lh := n.get_minimum_size().y + (UiKit.line_h(self, 11, true) if tf == faction else 0.0)
	var tx := 8.0 + hs + 8.0
	n.position = Vector2(tx, (dims.y - lh) / 2.0)
	n.clip_text = true
	n.size = Vector2(dims.x - tx - 6.0, n.get_minimum_size().y)
	b.add_child(n)
	if tf == faction:                                   # the faction you play
		var you := UiKit.label(self, "YOU", 11, UiKit.STAR, true, 2)
		you.position = n.position + Vector2(0, n.get_minimum_size().y)
		b.add_child(you)
	b.tooltip_text = UiKit.TAGS[tf]


func _army_identity(pos: Vector2, dims: Vector2) -> void:
	## The open faction: its character large, name / sub / tagline, the persistent trait, its five stats (dropped
	## first, then the smaller lines, when a phone's panel is too short).
	var acc := UiKit.accent(_army)
	UiKit.panel(self, pos, dims, _army)
	var ftrait: Array = Rules.FACTION_TRAITS[_army]
	var stats_h := UiKit.line_h(self, 20, true) + UiKit.line_h(self, 12) + 30.0
	var hs0 := minf(dims.y - 32.0, dims.x * 0.44)
	var tw := dims.x - 20.0 - hs0 - 16.0 - 18.0
	# [text, size, colour, head, spacing, gap before, wraps, drop order (0 = always)]
	var items := [
		[UiKit.SUBS[_army], 12, acc, true, 3, 0.0, false, 0],
		[UiKit.NAMES[_army], 34, acc, true, 0, 0.0, false, 0],
		[str(Rules.FACTION_TAGLINES[_army]), 14, UiKit.MUTED, false, 0, 2.0, true, 2],
		["PERSISTENT TRAIT", 12, acc, true, 3, 16.0, false, 0],
		[str(ftrait[0]).to_upper(), 16, UiKit.INK, true, 0, 2.0, false, 0],
		[str(ftrait[1]), 14, UiKit.MUTED, false, 0, 0.0, true, 0],
		["COMING SOON", 11, UiKit.DIM, true, 2, 6.0, false, 1],
	]
	var heights := []
	for it in items:
		heights.append((UiKit.text_h(self, it[0], it[1], tw, it[3]) if it[6] else UiKit.line_h(self, it[1], it[3])) + it[5])
	var drop := 0
	var with_stats := true
	while _kept_h(items, heights, drop) > dims.y - 32.0 - (stats_h if with_stats else 0.0):
		if with_stats:
			with_stats = false
		elif drop < 2:
			drop += 1
		else:
			break
	var ah := dims.y - (stats_h if with_stats else 0.0)       # the character + text area
	var hs := minf(ah - 24.0, hs0)
	UiKit.hero(self, _army, pos + Vector2(20.0, (ah - hs) / 2.0), Vector2(hs, hs))
	var tx := pos.x + 20.0 + hs0 + 16.0
	var ty := pos.y + (ah - _kept_h(items, heights, drop)) / 2.0
	for i in range(items.size()):
		var it: Array = items[i]
		if it[7] != 0 and it[7] <= drop:
			continue
		ty += it[5]
		var l := UiKit.label(self, it[0], it[1], it[2], it[3], it[4])
		if it[6]:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(tw, 0)
		_shell_add(l, Vector2(tx - (2.0 if it[1] >= 30 else 0.0), ty))
		ty += heights[i] - it[5]
	if not with_stats:
		return
	var sy := pos.y + dims.y - stats_h
	content.add_child(UiKit.rect(Vector2(pos.x + 18.0, sy), Vector2(dims.x - 36.0, 1.0), Color(UiKit.FRAME, 0.9)))
	var cw := (dims.x - 36.0) / STAT_ROWS.size()
	for i in range(STAT_ROWS.size()):
		var v := Rules.stat(_army, STAT_ROWS[i][0])
		var col := acc if v > 1.001 else (LOCK_COL if v < 0.999 else UiKit.INK)
		UiKit.stat(self, Vector2(pos.x + 18.0 + i * cw, sy + 12.0), "%d%%" % roundi(v * 100.0), STAT_ROWS[i][1], col)


func _kept_h(items: Array, heights: Array, drop: int) -> float:
	## _army_identity's text block height with the optional lines up to `drop` left out.
	var s := 0.0
	for i in range(items.size()):
		if items[i][7] == 0 or items[i][7] > drop:
			s += heights[i]
	return s


func _army_loadout(pos: Vector2, dims: Vector2) -> void:
	## The three equipped slots: 01 active and 02 map (tap: SKILLS on that pool), the ultimate (fixed); the save note.
	var lo := ArmyPresets.loadout_for(_army)
	var ult: String = Rules.FACTION_ULTIMATE_ID[_army]
	var row_h := func(lines: int) -> float:
		return 28.0 + UiKit.line_h(self, 17, true) + UiKit.line_h(self, 13) * lines
	var ult_h := func(lines: int) -> float:
		return 28.0 + UiKit.line_h(self, 11, true) + UiKit.line_h(self, 17, true) + UiKit.line_h(self, 13) * lines
	var note := "Saved on this device" if ArmyPresets.saved else "This browser keeps no storage: your picks last until the page closes"
	var note_h := UiKit.text_h(self, note, 13, dims.x) + 8.0
	var gap := 10.0
	var full: bool = 2 * maxf(row_h.call(2), UiKit.tap_h(self, 64.0)) + ult_h.call(2) + gap * 2.0 + note_h <= dims.y
	var rh: float = maxf(row_h.call(2 if full else 1), UiKit.tap_h(self, 64.0))
	var uh: float = ult_h.call(2 if full else 1)
	var show_note: bool = not ArmyPresets.saved or 2.0 * rh + uh + gap * 2.0 + note_h <= dims.y
	var y := pos.y
	var extra := dims.y - (2.0 * rh + uh + gap * 2.0 + (note_h if show_note else 0.0))
	var head_h := UiKit.line_h(self, 12, true) + UiKit.line_h(self, 13) + 12.0
	if extra >= head_h + 10.0:                          # room: the loadout's rule over the slots, taller rows
		_shell_add(UiKit.label(self, "EQUIPPED LOADOUT", 12, UiKit.accent(_army), true, 3), Vector2(pos.x + 2.0, y))
		var cap := UiKit.label(self, "One active skill and one map skill per faction; the ultimate comes with the faction.", 13, UiKit.MUTED)
		cap.clip_text = true
		cap.size = Vector2(dims.x, UiKit.line_h(self, 13))
		_shell_add(cap, Vector2(pos.x + 2.0, y + UiKit.line_h(self, 12, true)))
		y += head_h
		extra -= head_h
		var grow := minf(extra / 3.0, 22.0)
		rh += grow
		uh += grow
	_army_slot(Vector2(pos.x, y), Vector2(dims.x, rh), "01", lo["active"], "ACTIVE SKILL", full, func(): show_skills("active"))
	y += rh + gap
	_army_slot(Vector2(pos.x, y), Vector2(dims.x, rh), "02", lo["map"], "MAP SKILL", full, func(): show_skills("map"))
	y += rh + gap
	# the ultimate: fixed by the faction
	UiKit.panel(self, Vector2(pos.x, y), Vector2(dims.x, uh))
	content.add_child(UiKit.rect(Vector2(pos.x, y + 10.0), Vector2(3.0, uh - 20.0), UiKit.STAR))
	var ic := 44.0
	_icon_box(ult, Vector2(pos.x + 18.0, y + (uh - ic) / 2.0), ic, UiKit.STAR)
	var tx := pos.x + 18.0 + ic + 16.0
	var ty := y + 14.0
	var k := UiKit.label(self, "ULTIMATE  ·  %s ONLY  ·  FIXED" % UiKit.NAMES[_army], 11, UiKit.STAR, true, 2)
	_shell_add(k, Vector2(tx, ty))
	ty += UiKit.line_h(self, 11, true)
	_shell_add(UiKit.label(self, ArmyPresets.skill_name(ult).to_upper(), 17, UiKit.INK, true), Vector2(tx, ty))
	ty += UiKit.line_h(self, 17, true)
	var lines := [ArmyPresets.line(ult)]
	if full:
		lines.append("Charges in ~%d s (at least %d s); enemy kills speed it up" % [int(Rules.ULT_CHARGE_TIME), int(Rules.ULT_MIN_TIME)])
	for t in lines:
		var l := UiKit.label(self, t, 13, UiKit.MUTED)
		l.clip_text = true
		l.size = Vector2(pos.x + dims.x - 14.0 - tx, l.get_minimum_size().y)
		_shell_add(l, Vector2(tx, ty))
		ty += UiKit.line_h(self, 13)
	y += uh + gap
	if show_note:
		var n := UiKit.label(self, note, 13, UiKit.DIM if ArmyPresets.saved else LOCK_COL)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(dims.x, 0)
		_shell_add(n, Vector2(pos.x + 4.0, minf(y, pos.y + dims.y - note_h + 4.0)))


func _army_slot(pos: Vector2, dims: Vector2, num: String, id: String, kind: String, full: bool, call: Callable) -> void:
	## An equipped slot as a numbered row: the number, the skill's icon, its name, "ACTIVE SKILL · 32 s CD" (and the
	## one-line effect when there is room), a chevron - the whole row opens SKILLS.
	var acc := UiKit.accent(_army)
	var b := UiKit.btn(self, "", pos, dims, call, "secondary", _army)
	var n := UiKit.label(self, num, 24, acc, true)
	n.position = Vector2(16.0, (dims.y - n.get_minimum_size().y) / 2.0)
	b.add_child(n)
	var cx := 16.0 + UiKit.text_w(self, num, 24, true) + 14.0
	var ic := 44.0
	_icon_box(id, Vector2(cx, (dims.y - ic) / 2.0), ic, acc, b)
	cx += ic + 14.0
	var sub := "%s  ·  %s CD" % [kind, ArmyPresets.cd_text(id)]
	if Rules.SKILLS[id].get("needs_relays", false):
		sub += "  ·  NEEDS RELAYS"
	var texts := [[ArmyPresets.skill_name(id).to_upper(), 17, UiKit.INK, true], [sub, 13, UiKit.MUTED, false]]
	if full:
		texts.append([ArmyPresets.line(id), 13, Color(UiKit.MUTED, 0.8), false])
	var hh := 0.0
	for t in texts:
		hh += UiKit.line_h(self, t[1], t[3])
	var ty := (dims.y - hh) / 2.0
	for t in texts:
		var l := UiKit.label(self, t[0], t[1], t[2], t[3])
		l.position = Vector2(cx, ty)
		l.clip_text = true
		l.size = Vector2(dims.x - cx - 36.0, UiKit.line_h(self, t[1], t[3]))
		b.add_child(l)
		ty += UiKit.line_h(self, t[1], t[3])
	var c := UiKit.label(self, "›", 26, UiKit.MUTED)
	c.position = Vector2(dims.x - 28.0, (dims.y - c.get_minimum_size().y) / 2.0)
	b.add_child(c)
	b.tooltip_text = str(Rules.SKILLS[id]["desc"])


func _icon_box(id: String, pos: Vector2, s: float, col: Color, parent: Control = null) -> void:
	## A skill's line icon (ArmyPresets.icon) in a small dark clipped square framed in `col`.
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.9), Color(col, 0.55), 1, 6))
	box.position = pos
	box.size = Vector2(s, s)
	if parent != null:
		parent.add_child(box)
	else:
		content.add_child(box)
	skill_icon(id, pos + Vector2.ONE * s * 0.14, Vector2.ONE * s * 0.72, col, parent)


var _skills_args := false                          # SKILLS: the screenshot arg below was read


func show_skills(slot: String = "active") -> void:
	if not _skills_args:                              # screenshot arg: --skills-slot=map (open on the map pool)
		_skills_args = true
		if "--skills-slot=map" in OS.get_cmdline_user_args():
			slot = "map"
	_last_show = func(): show_skills(slot)
	## UI (Alpha 21, screen 07): ARMIES > SKILLS - the SKILLS 2.0 pools as they were (Daniele 2026-09-28: "skills i
	## think are better how we have them now") in the new language: the faction's fixed ultimate, then the five active
	## skills and the five map skills; tap a card to equip it at once, a locked one to unlock it (PROGRESSION).
	## `slot` ("active" / "map", the row that opened it) lights its pool and scrolls to it where the page scrolls.
	if _army == "":
		_army = faction
	if not _army_back.is_valid():
		_army_back = show_main
	var area := shell_open("OOZE / ARMIES / SKILLS", "armies", func(): show_armies(_army), _army)
	var acc := UiKit.accent(_army)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var top := page_title(area, "ARMIES / SKILLS  ·  " + UiKit.TAGS[_army], "PICK YOUR SKILLS.")
	var lo := ArmyPresets.loadout_for(_army)
	var st := stack_open(Vector2(x, top), Vector2(w, area.end.y - 12.0 - top))
	var scroll: TouchScroll = st["scroll"]
	_quiet_bar(scroll)
	var before := content.get_child_count()
	var iw := w - 14.0                                  # room for the scroll bar
	# the ultimate: fixed by the faction (one strip)
	var ult: String = Rules.FACTION_ULTIMATE_ID[_army]
	var ic := 44.0
	var tx := 16.0 + ic + 16.0
	var dw := iw - tx - 14.0
	var kick := "ULTIMATE  ·  %s ONLY  ·  FIXED" % UiKit.NAMES[_army]
	var charge := "  ·  ~%d s CHARGE, ENEMY KILLS SPEED IT UP" % int(Rules.ULT_CHARGE_TIME)
	if UiKit.text_w(self, kick + charge, 11, true) + (kick + charge).length() * 2.0 <= dw:
		kick += charge                                  # a phone keeps the kicker short
	var udesc := str(Rules.SKILLS[ult]["desc"])
	var uh := maxf(UiKit.tap_h(self, 0.0), 20.0 + UiKit.line_h(self, 11, true) + UiKit.line_h(self, 16, true) + UiKit.text_h(self, udesc, 13, dw))
	UiKit.panel(self, Vector2.ZERO, Vector2(iw, uh))
	content.add_child(UiKit.rect(Vector2(0, 10.0), Vector2(3.0, uh - 20.0), UiKit.STAR))
	_icon_box(ult, Vector2(16.0, (uh - ic) / 2.0), ic, UiKit.STAR)
	var ty := 10.0
	_shell_add(UiKit.label(self, kick, 11, UiKit.STAR, true, 2), Vector2(tx, ty))
	ty += UiKit.line_h(self, 11, true)
	_shell_add(UiKit.label(self, ArmyPresets.skill_name(ult).to_upper(), 16, UiKit.INK, true), Vector2(tx, ty))
	ty += UiKit.line_h(self, 16, true)
	var ud := UiKit.label(self, udesc, 13, UiKit.MUTED)
	ud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ud.custom_minimum_size = Vector2(dw, 0)
	_shell_add(ud, Vector2(tx, ty))
	var y := uh + 18.0
	var map_y := 0.0
	var pools := [["active", "01", "ACTIVE SKILL", "combat skills, every map", Rules.ACTIVE_SKILLS],
			["map", "02", "MAP SKILL", "network skills; relay skills need a map with relays", Rules.MAP_SKILLS]]
	var gap := 12.0
	for pool in pools:
		var ps: String = pool[0]
		if ps == "map":
			map_y = y
		var lit := ps == slot
		var n := UiKit.label(self, pool[1], 18, acc if lit else UiKit.MUTED, true)
		_shell_add(n, Vector2(0, y))
		var hx := UiKit.text_w(self, pool[1], 18, true) + 12.0
		var ht := UiKit.label(self, pool[2] + "  ·  PICK ONE", 16, UiKit.INK, true)
		_shell_add(ht, Vector2(hx, y + (UiKit.line_h(self, 18, true) - UiKit.line_h(self, 16, true)) / 2.0))
		hx += UiKit.text_w(self, pool[2] + "  ·  PICK ONE", 16, true) + 16.0
		_shell_add(UiKit.label(self, pool[3], 13, UiKit.MUTED), Vector2(hx, y + (UiKit.line_h(self, 18, true) - UiKit.line_h(self, 13)) / 2.0))
		y += UiKit.line_h(self, 18, true) + 8.0
		var ids: Array = pool[4]
		var cw := (iw - gap * (ids.size() - 1)) / ids.size()
		var ch := 0.0
		for id in ids:
			ch = maxf(ch, _skill_card_h(id, cw))
		for i in range(ids.size()):
			_skill_card(ids[i], ps, lo[ps] == ids[i], Vector2(i * (cw + gap), y), Vector2(cw, ch), scroll)
		y += ch + 20.0
	stack_capture(st, before)
	stack_close(st, y - 8.0)
	if slot == "map":
		_scroll_later(scroll, map_y - 4.0)


func _skill_card_h(id: String, cw: float) -> float:
	## A pool card's height at width `cw`: the icon row, the effect line wrapped, the state line.
	return 12.0 + maxf(40.0, _skill_head_h(id, cw)) + 8.0 + UiKit.text_h(self, ArmyPresets.line(id), 13, cw - 24.0) 			+ 8.0 + UiKit.line_h(self, 12, true) + 12.0


func _relays_inline(id: String, cw: float) -> bool:
	## NEEDS RELAYS fits on the cooldown's line (else it takes its own line under it).
	return 64.0 + UiKit.text_w(self, "%s CD" % ArmyPresets.cd_text(id), 13, true) + 10.0 			+ UiKit.text_w(self, "NEEDS RELAYS", 11, true) + 12.0 + 12.0 <= cw


func _skill_stacked(cw: float) -> bool:
	## A narrow card (phones): the name goes under the icon row instead of beside the icon.
	for id in Rules.ACTIVE_SKILLS + Rules.MAP_SKILLS:
		if UiKit.text_w(self, ArmyPresets.skill_name(id).to_upper(), 16, true) > cw - 64.0 - 10.0:
			return true
	return false


func _skill_head_h(id: String, cw: float) -> float:
	## The block beside the icon: name + cooldown (+ NEEDS RELAYS); stacked, the icon row and the name under it.
	if _skill_stacked(cw):
		return 46.0 + UiKit.line_h(self, 16, true) + (UiKit.line_h(self, 11, true) if Rules.SKILLS[id].get("needs_relays", false) else 0.0)
	var h := UiKit.line_h(self, 16, true) + UiKit.line_h(self, 13, true)
	if Rules.SKILLS[id].get("needs_relays", false) and not _relays_inline(id, cw):
		h += UiKit.line_h(self, 11, true)
	return h


func _skill_card(id: String, slot: String, chosen: bool, pos: Vector2, dims: Vector2, scroll: TouchScroll) -> void:
	## One pool skill as a tap target: icon, name, cooldown (and NEEDS RELAYS), one line in shown numbers (the full
	## sentence as its tooltip), then its state - EQUIPPED (lit in the accent), LOCKED with its price, or TAP TO EQUIP.
	var sk: Dictionary = Rules.SKILLS[id]
	var acc := UiKit.accent(_army)
	var locked := not Progression.is_unlocked("skill:" + id)   # PROGRESSION: tap a locked skill to unlock it
	var b := UiKit.btn(self, "", pos, dims, func():
		if scroll.was_drag():
			return
		if locked:
			_buy_prompt("skill:" + id, ArmyPresets.skill_name(id).to_upper(),
					"Unlocks %s for every faction's loadout. Skills are earned with SCRAP only." % ArmyPresets.skill_name(id),
					func(): show_skills(slot))
			return
		ArmyPresets.set_pick(_army, slot, id)
		_preset_changed()
		show_skills(slot), "selected" if chosen else "secondary", _army)
	b.tooltip_text = str(sk["desc"])
	var ic_col := acc if chosen else (Color("6f8792") if locked else Color("c9dbe3"))
	var hh := _skill_head_h(id, dims.x)
	var relays: bool = sk.get("needs_relays", false)
	var tx := 64.0
	var nm := UiKit.label(self, ArmyPresets.skill_name(id).to_upper(), 16, UiKit.INK if not locked else UiKit.MUTED, true)
	nm.clip_text = true
	var cd := UiKit.label(self, "%s CD" % ArmyPresets.cd_text(id), 13, acc if chosen else UiKit.MUTED, true)
	var nr: Label = UiKit.label(self, "NEEDS RELAYS", 11, UiKit.STAR, true, 1) if relays else null
	if _skill_stacked(dims.x):                         # icon | cooldown - then the name (and NEEDS RELAYS), full width
		_icon_box(id, Vector2(12.0, 12.0), 40.0, ic_col, b)
		cd.position = Vector2(tx, 12.0 + (40.0 - UiKit.line_h(self, 13, true)) / 2.0)
		nm.position = Vector2(12.0, 12.0 + 46.0)
		nm.size = Vector2(dims.x - 22.0, UiKit.line_h(self, 16, true))
		if relays:
			nr.position = nm.position + Vector2(0, UiKit.line_h(self, 16, true))
	else:
		_icon_box(id, Vector2(12.0, 12.0 + (maxf(40.0, hh) - 40.0) / 2.0), 40.0, ic_col, b)
		var y0 := 12.0 + (maxf(40.0, hh) - hh) / 2.0
		nm.position = Vector2(tx, y0)
		nm.size = Vector2(dims.x - tx - 10.0, UiKit.line_h(self, 16, true))
		cd.position = Vector2(tx, y0 + UiKit.line_h(self, 16, true))
		if relays:
			if _relays_inline(id, dims.x):
				nr.position = cd.position + Vector2(UiKit.text_w(self, cd.text, 13, true) + 10.0,
						(UiKit.line_h(self, 13, true) - UiKit.line_h(self, 11, true)) / 2.0)
			else:
				nr.position = cd.position + Vector2(0, UiKit.line_h(self, 13, true))
	b.add_child(nm)
	b.add_child(cd)
	if relays:
		b.add_child(nr)
	var y := 12.0 + maxf(40.0, hh) + 8.0
	var d := UiKit.label(self, ArmyPresets.line(id), 13, UiKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.position = Vector2(12.0, y)
	d.custom_minimum_size = Vector2(dims.x - 24.0, 0)
	d.size = Vector2(dims.x - 24.0, 0)
	b.add_child(d)
	var sy := dims.y - 12.0 - UiKit.line_h(self, 12, true)
	var sx := 12.0
	var state := "TAP TO EQUIP"
	var scol := UiKit.DIM
	if chosen:
		state = "EQUIPPED"
		scol = acc
		var cs := UiKit.line_h(self, 12, true) * 0.75
		_check(b, Vector2(sx, sy + (UiKit.line_h(self, 12, true) - cs) / 2.0), cs, acc)
		sx += cs + 6.0
	elif locked:
		state = "LOCKED  ·  " + Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false)
		scol = LOCK_COL
	var s := UiKit.label(self, state, 12, scol, true, 1)
	s.position = Vector2(sx, sy)
	s.clip_text = true
	s.size = Vector2(dims.x - sx - 12.0, UiKit.line_h(self, 12, true))
	b.add_child(s)


func _check(parent: Control, pos: Vector2, s: float, col: Color) -> void:
	## The check mark (assets/icons/check.png) in a colour.
	var r := TextureRect.new()
	r.texture = load("res://assets/icons/check.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = col
	r.position = pos
	r.size = Vector2(s, s)
	parent.add_child(r)


func _quiet_bar(scroll: ScrollContainer) -> void:
	## A thin, quiet scroll bar for the ARMIES pages' lists (the theme's default is a wide grey one); vertical only.
	if scroll is TouchScroll:
		(scroll as TouchScroll).horizontal = false      # the setter turns sideways scrolling off
	for bar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
		bar.add_theme_stylebox_override("scroll", UiKit.sb(Color(UiKit.FRAME, 0.25), Color(0, 0, 0, 0), 0, 2))
		bar.add_theme_stylebox_override("grabber", UiKit.sb(Color(UiKit.FRAME, 0.9), Color(0, 0, 0, 0), 0, 2))
		bar.add_theme_stylebox_override("grabber_highlight", UiKit.sb(Color(UiKit.MUTED, 0.8), Color(0, 0, 0, 0), 0, 2))
		bar.add_theme_stylebox_override("grabber_pressed", UiKit.sb(Color(UiKit.MUTED, 0.9), Color(0, 0, 0, 0), 0, 2))
		for s in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
			(bar.get_theme_stylebox(s) as StyleBoxFlat).set_content_margin_all(0)
		bar.custom_minimum_size = Vector2(6, 6)


func _scroll_later(scroll: ScrollContainer, v: float) -> void:
	## Scrolls once the list has its size (two frames after the page is built).
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll):
		if scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			scroll.scroll_vertical = int(maxf(v, 0.0))
		else:
			scroll.scroll_horizontal = int(maxf(v, 0.0))


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


# ------------------------------------------------------------------ ARMIES > COSMETICS (0.19.0, spec E/I; UI: screen 08)
const COSMETIC_FAMILIES := ["vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const COSMETIC_FAMILY_LABEL := {"territory": "TERRITORY", "vat": "VAT", "machinegoon": "MACHINEGOON", "laser": "LASER",
		"forge": "FORGE", "monster_hub": "MONSTER HUB", "monster": "MONSTER"}
const WARDROBE_CATS := ["territory", "vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const TERRITORY_LOOKS := {"neon": ["NEON", "Your colour in neon on the decks, piers and platform rims you hold."],
		"goo": ["GOO", "A slab of goo in your player colour over everything you hold; it spreads as you capture."]}
var _ward_cat := "vat"                             # COSMETICS: the open category ("territory" or a Cosmetics family)
var _ward_sel := {}                                # COSMETICS: category -> the look on preview (not equipped yet)
var _ward_tier := 2                                # COSMETICS: the tier the vat / Machinegoon preview shows
var _ward_args := false                            # COSMETICS: the screenshot args below were read


func show_cosmetics(f: String = "") -> void:
	_last_show = func(): show_cosmetics(f)                  # a resize that changes the phone sizing rebuilds it (_fit)
	## A look per structure family, per faction (GAME-BIBLE sec17; Daniele, 2026-09-27): DEFAULT / the
	## faction set / GRADUATE / the skin lines for vats, DEFAULT / SPITTER / PEPPERBOX for the
	## Machinegoon, and so on - saved in user://armies.cfg (ArmyPresets), applied at match start
	## (main.gd's Cosmetics.set_loadout) and sent along with the skill loadout online (ArmyPresets.send_to).
	## UI (Alpha 21, screen 08, the wardrobe; Daniele: "needs lots of improvement"): the faction at the top right, the
	## categories on the left (TERRITORY - CORE, every faction - then the six families), ONE large turning preview of
	## the look on selection (its tier switchable for vats and Machinegoons), the category's looks as tiles
	## (EQUIPPED / on preview / LOCKED with its way in), and EQUIP - or UNLOCK (_buy_prompt) for a locked look.
	if not _ward_args:                                # screenshot args: --wardrobe-cat=<category> --wardrobe-look=<id>
		_ward_args = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--wardrobe-cat="):
				_ward_cat = arg.substr(15)
			elif arg.begins_with("--wardrobe-look="):
				_ward_sel[_ward_cat] = arg.substr(16)
	if f != "" and f != _army:
		_ward_sel = {}                                  # another faction: its own saved picks
	if f != "":
		_army = f
	if _army == "":
		_army = faction
	if not _army_back.is_valid():                     # 0.19.2 spec H11: BACK did nothing reached directly
		_army_back = show_main                         # (show_armies() sets this; a direct entry never did)
	var area := shell_open("OOZE / ARMIES / COSMETICS", "armies", func(): show_armies(_army), _army)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var top := page_title(area, "ARMIES / COSMETICS", "BUILT TO LOOK DIFFERENT.")
	var fy := area.position.y + (10.0 if shell_slim else 16.0)
	_ward_factions(fy)
	top = maxf(top, fy + UiKit.tap_h(self, 50.0) + 10.0)
	var cat := _ward_cat if _ward_cat in WARDROBE_CATS else "vat"
	var looks: Array = TERRITORY_LOOKS.keys() if cat == "territory" else Cosmetics.OPTIONS[cat]
	var played := ArmyPresets.cosmetic_loadout_for(_army)          # what plays (a locked pick plays as the default)
	var saved := ArmyPresets.cosmetic_loadout_for(_army, true)     # the picks as saved
	var equipped: String = ArmyPresets.core_territory if cat == "territory" else str(played[cat])
	var sel := str(_ward_sel.get(cat, ArmyPresets.core_territory if cat == "territory" else str(saved[cat])))
	if not sel in looks:
		sel = equipped
	var h := area.end.y - 14.0 - top
	var rail_w := 180.0
	for c in WARDROBE_CATS:
		rail_w = maxf(rail_w, UiKit.text_w(self, COSMETIC_FAMILY_LABEL[c], 15, true) + 44.0)
	var looks_w := clampf(w * 0.25, 270.0, 340.0)
	var pv_w := w - rail_w - looks_w - 28.0
	_ward_rail(Vector2(x, top), Vector2(rail_w, h), cat, played)
	_ward_stage(Vector2(x + rail_w + 14.0, top), Vector2(pv_w, h), cat, sel, equipped)
	_ward_looks(Vector2(x + rail_w + 14.0 + pv_w + 14.0, top), Vector2(looks_w, h), cat, looks, sel, equipped)


func _ward_factions(y: float) -> void:
	## The faction the looks are for: five character tiles right of the title (the open one lit in its accent).
	var s := UiKit.tap_h(self, 50.0)
	var gap := 8.0
	var x := _title_right() - FACTIONS.size() * (s + gap) + gap
	for i in range(FACTIONS.size()):
		var tf: String = FACTIONS[i]
		var b := UiKit.btn(self, "", Vector2(x + i * (s + gap), y), Vector2(s, s), func(): show_cosmetics(tf),
				"selected" if tf == _army else "secondary", tf)
		b.tooltip_text = UiKit.TAGS[tf]
		var art := TextureRect.new()
		art.texture = load(UiKit.hero_path(tf))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2.ONE * 5.0
		art.size = Vector2.ONE * (s - 10.0)
		b.add_child(art)


func _ward_look_name(cat: String, id: String) -> String:
	if cat == "territory":
		return TERRITORY_LOOKS[id][0]
	return Cosmetics.label(cat, id, _army)


func _ward_rail(pos: Vector2, dims: Vector2, cat: String, played: Dictionary) -> void:
	## The categories, each with what it wears now; the open one lit. Scrolls where a phone runs out of height.
	var st := stack_open(pos, dims)
	var scroll: TouchScroll = st["scroll"]
	_quiet_bar(scroll)
	var before := content.get_child_count()
	var rh := maxf(UiKit.tap_h(self, 58.0), 16.0 + UiKit.line_h(self, 15, true) + UiKit.line_h(self, 12))
	var y := 0.0
	var sel_y := 0.0
	for c in WARDROBE_CATS:
		var cc: String = c
		var now := ArmyPresets.core_territory if c == "territory" else str(played[c])
		var b := UiKit.btn(self, "", Vector2(0, y), Vector2(dims.x - 10.0, rh), func():
			if scroll.was_drag():
				return
			_ward_cat = cc
			show_cosmetics(), "selected" if c == cat else "secondary", _army)
		var hh := UiKit.line_h(self, 15, true) + UiKit.line_h(self, 12)
		var t := UiKit.label(self, COSMETIC_FAMILY_LABEL[c], 15, UiKit.INK, true)
		t.position = Vector2(16.0, (rh - hh) / 2.0)
		b.add_child(t)
		var cap := _ward_look_name(c, now)
		if c == "territory" and UiKit.text_w(self, cap + "  ·  ALL FACTIONS", 12) <= dims.x - 42.0:
			cap += "  ·  ALL FACTIONS"
		var s := UiKit.label(self, cap, 12, UiKit.accent(_army) if c == cat else UiKit.MUTED)
		s.position = t.position + Vector2(0, UiKit.line_h(self, 15, true))
		s.clip_text = true
		s.size = Vector2(dims.x - 42.0, UiKit.line_h(self, 12))
		b.add_child(s)
		if c == cat:
			sel_y = y
		y += rh + 8.0
	stack_capture(st, before)
	stack_close(st, y - 8.0)
	if y - 8.0 > dims.y:
		_scroll_later(scroll, sel_y + rh - dims.y + 8.0)


func _ward_state(cat: String, id: String, equipped: String) -> Dictionary:
	## A look's state for its tile and the stage: {"locked", "equipped", "line" (the tile's short state), "col"}.
	if cat == "territory":
		return {"locked": false, "equipped": id == equipped, "line": "EQUIPPED" if id == equipped else "ALL FACTIONS",
				"col": UiKit.accent(_army) if id == equipped else UiKit.DIM}
	var item := Progression.cosmetic_item(cat, id, _army)
	if not ArmyPresets.is_unlocked(id, cat, _army):
		var price := Progression.price(item)
		var line := "LOCKED"
		if item == "vat:graduate":
			line += "  ·  " + TutorialDirector.line("locked_cosmetic").to_upper()
		elif price.has("soft"):
			line += "  ·  " + Progression.amount_text(int(price["soft"]), "soft", false)
		return {"locked": true, "equipped": false, "line": line, "col": LOCK_COL}
	if id == equipped:
		return {"locked": false, "equipped": true, "line": "EQUIPPED", "col": UiKit.accent(_army)}
	return {"locked": false, "equipped": false, "line": "OWNED" if Progression.owns(item) else "OPEN",
			"col": UiKit.DIM}


func _ward_stage(pos: Vector2, dims: Vector2, cat: String, sel: String, equipped: String) -> void:
	## The look on preview: "EMBER / VAT", its name and state, the large turning model (TERRITORY: what it does),
	## what the look is or how to unlock it, the tier chips (vat T1-T4, Machinegoon T1-T3) and EQUIP / UNLOCK.
	var acc := UiKit.accent(_army)
	UiKit.panel(self, pos, dims, _army)
	var st := _ward_state(cat, sel, equipped)
	var ix := pos.x + 18.0
	var iw := dims.x - 36.0
	var y := pos.y + 14.0
	var k := UiKit.label(self, ("ALL FACTIONS" if cat == "territory" else UiKit.NAMES[_army]) + " / " + COSMETIC_FAMILY_LABEL[cat], 12, acc, true, 3)
	_shell_add(k, Vector2(ix, y))
	y += UiKit.line_h(self, 12, true)
	_shell_add(UiKit.label(self, _ward_look_name(cat, sel), 26, UiKit.INK, true), Vector2(ix - 1.0, y))
	# the state badge, top right
	var badge := "LOCKED" if st["locked"] else ("EQUIPPED" if st["equipped"] else "ON PREVIEW")
	var bcol: Color = LOCK_COL if st["locked"] else (acc if st["equipped"] else UiKit.MUTED)
	var bw := UiKit.text_w(self, badge, 12, true) + badge.length() * 2.0 + 26.0
	var bl := UiKit.label(self, badge, 12, bcol, true, 2)
	var bhh := bl.get_minimum_size().y + 10.0
	var bp := Panel.new()
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.92), Color(bcol, 0.8), 1, 5))
	bp.size = Vector2(bw, bhh)
	_shell_add(bp, Vector2(pos.x + dims.x - 18.0 - bw, pos.y + 16.0))
	bl.position = Vector2(12.0, 5.0)
	bp.add_child(bl)
	y += UiKit.line_h(self, 26, true) + 8.0
	# the foot: the look's line, then the tier chips and the action
	var detail := _ward_detail(cat, sel, st)
	var dh := UiKit.text_h(self, detail, 14, iw)
	var ah := UiKit.tap_h(self, 50.0)
	var ay := pos.y + dims.y - 16.0 - ah
	var dy := ay - 10.0 - dh
	var vh := dy - 10.0 - y
	# the stage: a dark well with the accent's glow, the model turning in it
	content.add_child(UiKit.rect(Vector2(ix, y), Vector2(iw, vh), Color(UiKit.BASE, 0.75)))
	var g := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(acc, 0.2))
	grad.set_color(1, Color(acc, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.62)
	gt.fill_to = Vector2(0.5, 0.0)
	g.texture = gt
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size = Vector2(iw, vh)
	_shell_add(g, Vector2(ix, y))
	var pv: WardrobePreview = null
	var tiers := {"vat": 4, "machinegoon": 3}.get(cat, 0) as int
	if cat == "territory":
		var big := UiKit.label(self, TERRITORY_LOOKS[sel][0], 64, acc, true, 6)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.size = Vector2(iw, big.get_minimum_size().y)
		var tl := UiKit.label(self, "HOW THE GROUND YOU HOLD IS DRAWN", 13, UiKit.MUTED, true, 2)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(iw - 24.0, 0)
		tl.size = Vector2(iw - 24.0, UiKit.text_h(self, tl.text, 13, iw - 24.0 - tl.text.length() * 2.0, true))
		var bh2 := big.size.y + tl.size.y + 6.0
		_shell_add(big, Vector2(ix, y + (vh - bh2) / 2.0))
		_shell_add(tl, Vector2(ix + 12.0, y + (vh - bh2) / 2.0 + big.size.y + 6.0))
	else:
		var tier := clampi(_ward_tier, 1, tiers) if tiers > 0 else 0
		pv = WardrobePreview.make(cat, sel, _army, tier, Vector2(iw, vh))
		_shell_add(pv, Vector2(ix, y))
	var dl := UiKit.label(self, detail, 14, LOCK_COL if st["locked"] else UiKit.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(iw, 0)
	_shell_add(dl, Vector2(ix, dy))
	# tier chips (in place: the preview switches its model, the page is not rebuilt)
	if tiers > 0:
		var chips := []
		var cx := ix
		var tl := UiKit.label(self, "TIER", 12, UiKit.MUTED, true, 2)
		_shell_add(tl, Vector2(cx, ay + (ah - tl.get_minimum_size().y) / 2.0))
		cx += UiKit.text_w(self, "TIER", 12, true) + 16.0
		for t in range(1, tiers + 1):
			var tt: int = t
			var ch := UiKit.chip(self, "T%d" % t, Vector2(cx, ay), Callable(), _army, t == clampi(_ward_tier, 1, tiers))
			ch.size.y = ah
			chips.append(ch)
			ch.pressed.connect(func():
				_ward_tier = tt
				pv.set_tier(tt)
				for i in range(chips.size()):
					UiKit.style_button(chips[i], "selected" if i + 1 == tt else "secondary", _army))
			cx += ch.size.x + 8.0
	# the action
	var item := "" if cat == "territory" else Progression.cosmetic_item(cat, sel, _army)
	var aw := minf(240.0, iw * 0.42)
	var ap := Vector2(ix + iw - aw, ay)
	if st["equipped"]:
		var eb := UiKit.btn(self, "EQUIPPED", ap, Vector2(aw, ah), Callable(), "selected", _army, 16)
		eb.disabled = true
		eb.add_theme_stylebox_override("disabled", eb.get_theme_stylebox("normal"))
		eb.add_theme_color_override("font_disabled_color", acc)
	elif st["locked"] and not Progression.price(item).is_empty():   # PROGRESSION: UNLOCK where it can be bought
		UiKit.btn(self, "UNLOCK", ap, Vector2(aw, ah), func():
			_buy_prompt(item, _ward_look_name(cat, sel).to_upper(), "A look only: tier read, footprint and colour stay the same.",
					func(): show_cosmetics()), "primary", _army, 16)
	elif st["locked"]:
		var lb := UiKit.btn(self, "LOCKED", ap, Vector2(aw, ah), Callable(), "secondary", _army, 16)
		lb.disabled = true
	else:
		UiKit.btn(self, "EQUIP", ap, Vector2(aw, ah), func():
			if cat == "territory":
				ArmyPresets.set_core_territory(sel)
			else:
				ArmyPresets.set_cosmetic_pick(_army, cat, sel)
				_preset_changed()
			_ward_sel.erase(cat)
			show_cosmetics(), "primary", _army, 16)


func _ward_detail(cat: String, sel: String, st: Dictionary) -> String:
	## The stage's line: what the look does (TERRITORY), how to unlock it, or what it is - and the no-storage warning.
	var out := ""
	if cat == "territory":
		out = TERRITORY_LOOKS[sel][1] + " One pick for every faction."
	elif st["locked"]:
		var item := Progression.cosmetic_item(cat, sel, _army)
		out = "TO UNLOCK: " + _cosmetic_path(cat, sel)
		var price := Progression.price(item)
		var costs := []
		for cur in ["soft", "premium"]:
			if price.has(cur):
				costs.append(Progression.amount_text(int(price[cur]), cur, false))
		if not costs.is_empty():
			out += "  ·  " + " OR ".join(costs)
	else:
		out = "A look only: tier read, footprint and colour stay the same."
		if not Progression.owns(Progression.cosmetic_item(cat, sel, _army)):
			out = "Open while testing; earned or unlocked later. " + out
		if cat in ["monster_hub", "monster"] or sel == "faction":
			out += " Made for %s." % UiKit.NAMES[_army]
	if not ArmyPresets.saved:
		out += "\nThis browser keeps no storage: your picks last until the page closes."
	return out


func _ward_looks(pos: Vector2, dims: Vector2, cat: String, looks: Array, sel: String, equipped: String) -> void:
	## The category's looks as tiles: the one on preview framed in the accent, the equipped one with a check and an
	## accent bar, a locked one with its price or way in. Tap: preview it (EQUIP is on the stage).
	var acc := UiKit.accent(_army)
	var kt := "%d LOOKS" % looks.size()
	if Progression.unlock_all and cat != "territory":
		var more := kt + "  ·  ALL OPEN WHILE TESTING"
		if UiKit.text_w(self, more, 12, true) + more.length() * 2.0 <= dims.x:
			kt = more
	var k := UiKit.label(self, kt, 12, UiKit.MUTED, true, 2)
	k.clip_text = true
	k.size = Vector2(dims.x, UiKit.line_h(self, 12, true))
	_shell_add(k, pos + Vector2(2.0, 0))
	var ty := UiKit.line_h(self, 12, true) + 6.0
	var st := stack_open(pos + Vector2(0, ty), Vector2(dims.x, dims.y - ty))
	var scroll: TouchScroll = st["scroll"]
	_quiet_bar(scroll)
	var before := content.get_child_count()
	var th := maxf(UiKit.tap_h(self, 56.0), 18.0 + UiKit.line_h(self, 15, true) + UiKit.line_h(self, 12, true))
	var tw := dims.x - 10.0
	var y := 0.0
	var sel_y := 0.0
	for id in looks:
		var lid: String = id
		var s := _ward_state(cat, lid, equipped)
		var b := UiKit.btn(self, "", Vector2(0, y), Vector2(tw, th), func():
			if scroll.was_drag():
				return
			_ward_sel[cat] = lid
			show_cosmetics(), "selected" if lid == sel else "secondary", _army)
		if s["equipped"]:
			b.add_child(UiKit.rect(Vector2(0, 8.0), Vector2(3.0, th - 16.0), acc))
		var hh := UiKit.line_h(self, 15, true) + UiKit.line_h(self, 12, true)
		var tx := 16.0
		var n := UiKit.label(self, _ward_look_name(cat, lid), 15, UiKit.MUTED if s["locked"] else UiKit.INK, true)
		n.position = Vector2(tx, (th - hh) / 2.0)
		n.clip_text = true
		n.size = Vector2(tw - tx - 12.0, UiKit.line_h(self, 15, true))
		b.add_child(n)
		var lx := tx
		if s["equipped"]:
			var cs := UiKit.line_h(self, 12, true) * 0.75
			_check(b, Vector2(lx, n.position.y + UiKit.line_h(self, 15, true) + (UiKit.line_h(self, 12, true) - cs) / 2.0), cs, acc)
			lx += cs + 6.0
		var line: String = s["line"]
		if UiKit.text_w(self, line, 12, true) > tw - lx - 12.0 and s["locked"]:
			line = "LOCKED"                             # a phone's narrow tile: the stage spells the way in out
		var sl := UiKit.label(self, line, 12, s["col"], true, 1)
		sl.position = Vector2(lx, n.position.y + UiKit.line_h(self, 15, true))
		sl.clip_text = true
		sl.size = Vector2(tw - lx - 12.0, UiKit.line_h(self, 12, true))
		b.add_child(sl)
		if lid == sel:
			sel_y = y
		y += th + 8.0
	stack_capture(st, before)
	stack_close(st, y - 8.0)
	if y - 8.0 > dims.y - ty:
		_scroll_later(scroll, sel_y + th - (dims.y - ty) + 8.0)


func show_maps() -> void:
	## 02 BATTLEFIELD (screen system 04): the players filter (ALL + every mode some map offers; picking one also sets
	## up that mode) and the TYPE filter (cycles MAP_TYPES), a scrolling grid of the real thumbnails (MapPool.thumb:
	## the whole map, never cropped; the picked one lit), the picked map's name / modes / nodes / relays / Last Stand,
	## NEXT: MATCH SETUP. (The mockup's search box is left out: phones have no text field for it.)
	_last_show = show_maps                  # a resize that changes the phone sizing rebuilds it (_fit)
	var shown := _filtered_maps()
	if not shown.is_empty() and not shown.any(func(e): return e["path"] == map_path):
		map_path = shown[0]["path"]                    # back on the page with filters set: pick a shown map
	if map_filter_mode != "all" and not shown.is_empty():
		mode = map_filter_mode                         # filtered by players: set up that mode
	var area := shell_open("OOZE / BATTLEFIELD", "play", show_factions, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "02 / BATTLEFIELD", "CHOOSE YOUR CROSSING.")
	# the filters: players at the left (wrapping if a phone needs it), TYPE at the right, the count between them
	var tt := "TYPE: %s" % MAP_TYPE_NAMES[map_filter_type]
	var tw := maxf(UiKit.text_w(self, tt, 14, true) + 32.0, 56.0)
	var tb := UiKit.chip(self, tt, Vector2(content.size.x - x - tw, y), func():
		map_filter_type = MAP_TYPES[(MAP_TYPES.find(map_filter_type) + 1) % MAP_TYPES.size()]
		_refilter(), faction, map_filter_type != "all")
	var chip_h := tb.size.y
	var cx := x
	var cy := y
	for md in ["all"] + _pool_modes():
		var md_now: String = md
		var text: String = "ALL" if md == "all" else MODE_NAMES.get(md, md)
		var cw := maxf(UiKit.text_w(self, text, 14, true) + 32.0, 56.0)
		if cx + cw > (tb.position.x - 12.0 if cy == y else x + w):
			cx = x
			cy += chip_h + 8.0
		UiKit.chip(self, text, Vector2(cx, cy), func():
			map_filter_mode = md_now
			_refilter(), faction, md == map_filter_mode)
		cx += cw + 8.0
	var count := "%d OF %d MAPS" % [shown.size(), maps.size()]
	var count_w := UiKit.text_w(self, count, 13)
	var count_in_row := cy == y and cx + count_w + 8.0 < tb.position.x - 12.0
	if count_in_row:
		_shell_add(UiKit.label(self, count, 13, UiKit.MUTED), Vector2(tb.position.x - 14.0 - count_w, y + (chip_h - UiKit.line_h(self, 13)) / 2.0))
	y = cy + chip_h + 12.0
	# the foot: the picked map, NEXT
	var sel := _selected_map()
	var bh := UiKit.tap_h(self, 48.0)
	var nt := "NEXT: MATCH SETUP  →"
	var nw := UiKit.text_w(self, nt, 17, true) + 48.0
	var detail := "%s   /   %d NODES%s" % [" · ".join(_modes_of(sel).map(func(v): return MODE_NAMES.get(v, v))), sel["nodes"].size(),
			_relay_kinds(sel).replace("    /    ", "   /   ")]
	if not count_in_row:
		detail += "   ·   " + count
	var ls_methods: Array = sel.get("lastStand", {}).get("methods", [])
	var ls_line: String = "No Last Stand on this map" if ls_methods.is_empty() else "Last Stand at %d:%02d - methods: %s" % [
			int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60, ", ".join(ls_methods)]
	var info := [[str(sel.get("name", "")).replace("*", "").to_upper(), 18, UiKit.INK, true], [detail, 13, UiKit.accent(faction), false]]
	if not mobile:                                     # the phone keeps the grid's height instead of the recap
		info.append(["%s  ·  %s" % [_map_blurb(sel), ls_line], 12, UiKit.MUTED, false])
	var info_h := 0.0
	for ln in info:
		info_h += UiKit.line_h(self, ln[1], ln[3])
	var foot_h := maxf(bh, info_h)
	var fy := area.end.y - foot_h - 12.0
	UiKit.btn(self, nt, Vector2(content.size.x - x - nw, fy + (foot_h - bh) / 2.0), Vector2(nw, 48), show_setup, "primary", faction, 17)
	var iy := fy + (foot_h - info_h) / 2.0
	for ln in info:
		var l := UiKit.label(self, ln[0], ln[1], ln[2], ln[3])
		l.clip_text = true
		l.size = Vector2(w - nw - 24.0, UiKit.line_h(self, ln[1], ln[3]))
		_shell_add(l, Vector2(x, iy))
		iy += l.size.y
	# the grid: every shown map, a swipe scrolls (phones), a tap picks
	var gy := y
	var scroll := TouchScroll.new()
	var keep := _map_scroll                           # picking a map rebuilds the page: stay where you were
	get_tree().process_frame.connect(func(): if is_instance_valid(scroll): scroll.scroll_vertical = keep, CONNECT_ONE_SHOT)
	scroll.position = Vector2(x, gy)
	scroll.size = Vector2(w, fy - 12.0 - gy)
	content.add_child(scroll)
	if shown.is_empty():
		_shell_add(UiKit.label(self, "No map matches these filters.", 18, UiKit.MUTED), Vector2(x + 4.0, gy + 20.0))
	var gap := 12.0
	var cols := clampi(int((w + gap) / (270.0 + gap)), 3, 6)
	var cw := floorf((w - 16.0 - gap * (cols - 1)) / cols)    # 16: the scroll bar's lane
	var cap_h := UiKit.line_h(self, 13, true) + 12.0
	var thumb := Vector2(cw - 12.0, floorf((cw - 12.0) * 9.0 / 16.0))
	var card := Vector2(cw, 6.0 + thumb.y + cap_h)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	scroll.add_child(grid)
	for entry in shown:
		var m: Dictionary = entry["data"]
		var mp: String = entry["path"]
		var code: String = m.get("code", "")
		var picked := mp == map_path
		var b := UiKit.make_btn(self, "", card, func():
			if scroll.was_drag():                     # that was a swipe, not a pick
				return
			_map_scroll = scroll.scroll_vertical
			map_path = mp
			show_maps(), "selected" if picked else "secondary", faction)
		grid.add_child(b)
		var back := UiKit.rect(Vector2(6, 6), thumb, Color(UiKit.BASE, 0.9))
		b.add_child(back)
		var tex := TextureRect.new()
		var tp := MapPool.thumb(code)
		tex.texture = load(tp) if ResourceLoader.exists(tp) else null
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # the whole map, never cropped (Daniele, 0.18.7:
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE                # "thumbnail of maps often overflow and can't be seen in full")
		tex.position = Vector2(6, 6)
		tex.size = thumb
		b.add_child(tex)
		var cap_text := "%s  %s" % [code, str(m.get("name", "")).replace("*", "").to_upper()]
		if UiKit.text_w(self, cap_text, 13, true) > cw - 20.0:    # phones: the name alone (the thumbnail carries the code)
			cap_text = str(m.get("name", "")).replace("*", "").to_upper()
		var cap := UiKit.label(self, cap_text, 13, UiKit.accent(faction) if picked else UiKit.INK, true)
		cap.clip_text = true
		cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cap.position = Vector2(10, 6.0 + thumb.y + (cap_h - UiKit.line_h(self, 13, true)) / 2.0)
		cap.size = Vector2(cw - 20.0, UiKit.line_h(self, 13, true))
		b.add_child(cap)
	shell_raise()


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
	## 03 SETUP (screen system 05): the map (its preview, CHANGE -> BATTLEFIELD) and YOUR TEAM COLOUR on the left; your
	## faction (CHANGE -> FACTION, its army preset -> ARMIES), the rival (1 V 1: seat B's faction; other modes: every AI
	## seat's pick, set in SEATS & TEAMS), DIFFICULTY on the right; LAST STAND, ABILITIES and DEPLOY at the foot. SEATS &
	## TEAMS (show_seats) holds the PLAYERS mode and every seat's pick. Each choice is the variable deploy() reads.
	_last_show = show_setup                  # a resize that changes the phone sizing rebuilds it (_fit)
	var modes := _modes_of(_selected_map())
	if not mode in modes:
		mode = modes[0]
	var area := shell_open("OOZE / SETUP", "play", show_maps, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "03 / SETUP", "READY TO DEPLOY.")
	# SEATS & TEAMS (and the mode), top right - left of BACK where the page has it
	var stt := "SEATS & TEAMS  ·  %s" % MODE_NAMES.get(mode, mode)
	var stw := UiKit.text_w(self, stt, 14, true) + 36.0
	var right := content.size.x - x
	if shell_back.is_valid() and not shell_slim:
		right -= UiKit.text_w(self, "←  BACK", 15, true) + 20.0 + 14.0
	var stb := UiKit.btn(self, stt, Vector2(right - stw, area.position.y + (10.0 if shell_slim else 14.0)), Vector2(stw, 42),
			show_seats, "secondary", faction, 14)
	y = maxf(y, stb.position.y + stb.size.y + 10.0)
	var lw := floorf(w * 0.52)
	var rx := x + lw + 18.0
	var rw := w - lw - 18.0
	# the foot of the right column: LAST STAND, ABILITIES, DEPLOY
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var dt := "DEPLOY  →"
	var dw := maxf(UiKit.text_w(self, dt, 18, true) + 56.0, 170.0)
	UiKit.btn(self, dt, Vector2(content.size.x - x - dw, fy), Vector2(dw, 48), deploy, "primary", faction, 18)
	var tgw := (rw - dw - 20.0) / 2.0
	_toggle("LAST STAND", Rules.last_stand, Vector2(rx, fy), Vector2(tgw, 48), func():
		Rules.last_stand = not Rules.last_stand
		show_setup())
	_toggle("ABILITIES", Rules.abilities_on, Vector2(rx + tgw + 10.0, fy), Vector2(tgw, 48), func():   # SKILLS 2.0: Alpha 11's match setting
		Rules.abilities_on = not Rules.abilities_on
		show_setup())
	if not mobile:                                    # the phone skips the recap to save room
		var tip := UiKit.label(self, "Last Stand ON = the map collapses ring by ring late in the match.  ABILITIES OFF = no skills.", 12, UiKit.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(rw, 0)
		_shell_add(tip, Vector2(rx, fy - 8.0 - UiKit.text_h(self, tip.text, 12, rw)))
	# the left column: the map, YOUR TEAM COLOUR under it
	var hs := UiKit.tap_h(self, 44.0)
	var col_h := UiKit.line_h(self, 12, true) + 8.0 + hs + (UiKit.line_h(self, 13) + 6.0 if colour == "faction" else 0.0) \
			+ (UiKit.line_h(self, 12) + 6.0 if not mobile else 0.0)
	var col_y := area.end.y - 18.0 - col_h           # (the picked chip grows 12 %)
	_setup_map(Vector2(x, y), Vector2(lw, col_y - 16.0 - y))
	_setup_colours(Vector2(x, col_y), lw)
	# the right column: your faction, the rival(s), DIFFICULTY
	var ry := y
	if not mobile:
		_shell_add(UiKit.label(self, "YOUR FACTION  ·  SEAT A", 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
		ry += UiKit.line_h(self, 12, true) + 6.0
	var card_h := maxf(76.0, UiKit.tap_h(self, 40.0) + 12.0)
	_setup_faction(Vector2(rx, ry), Vector2(rw, card_h))
	ry += card_h + 14.0
	var seats := _enemy_seats()
	if mode == "1v1" and seats.size() == 1:
		var pick := str(rival_picks.get(seats[0], "random"))
		var kt := "RIVAL  ·  SEAT %s  ·  %s" % [seats[0], "ANY (picked when you deploy)" if pick == "random" else UiKit.NAMES[pick]]
		if UiKit.text_w(self, kt, 12, true) + kt.length() * 3.0 > rw:
			kt = kt.replace(" (picked when you deploy)", "")
		var kl := UiKit.label(self, kt, 12, UiKit.MUTED, true, 3)
		kl.clip_text = true
		kl.size = Vector2(rw, UiKit.line_h(self, 12, true))
		_shell_add(kl, Vector2(rx, ry))
		ry += UiKit.line_h(self, 12, true) + 6.0
		ry += _faction_picks(seats[0], Vector2(rx, ry), rw, show_setup) + 14.0
	else:
		_shell_add(UiKit.label(self, "AI SEATS  ·  %s" % MODE_NAMES.get(mode, mode), 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
		ry += UiKit.line_h(self, 12, true) + 6.0
		var parts := seats.map(func(s):
			var p := str(rival_picks.get(s, "random"))
			return "%s %s" % [s, "ANY" if p == "random" else UiKit.NAMES[p]])
		var r := UiKit.row(self, Vector2(rx, ry), Vector2(rw, 52), "", "  ·  ".join(parts), "Set each seat's faction, see the teams",
				show_seats, faction)
		ry += r.size.y + 14.0
	_shell_add(UiKit.label(self, "DIFFICULTY", 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
	ry += UiKit.line_h(self, 12, true) + 6.0
	_difficulty(Vector2(rx, ry), rw)


func _setup_map(pos: Vector2, dims: Vector2) -> void:
	## SETUP's map panel: the name and CHANGE (-> BATTLEFIELD), the whole-map preview, its mode / nodes / relays.
	var sel := _selected_map()
	UiKit.panel(self, pos, dims, faction)
	var pad := 16.0
	var ct := "CHANGE"
	var cw := UiKit.text_w(self, ct, 14, true) + 34.0
	var cb := UiKit.btn(self, ct, Vector2(pos.x + dims.x - pad / 2.0 - cw, pos.y + 6.0), Vector2(cw, 38), show_maps, "tertiary", faction, 14)
	var nm := UiKit.label(self, str(sel.get("name", "")).replace("*", "").to_upper(), 18, UiKit.INK, true)
	nm.clip_text = true
	nm.size = Vector2(dims.x - pad * 2.0 - cw, UiKit.line_h(self, 18, true))
	_shell_add(nm, Vector2(pos.x + pad, cb.position.y + (cb.size.y - nm.size.y) / 2.0))
	var th := UiKit.line_h(self, 12, true) + 10.0
	var py := cb.position.y + cb.size.y + 6.0
	var pd := Vector2(dims.x - pad * 2.0, pos.y + dims.y - pad - th - 10.0 - py)
	content.add_child(UiKit.rect(Vector2(pos.x + pad, py), pd, Color(UiKit.BASE, 0.9)))
	var tex := TextureRect.new()
	var tp := MapPool.thumb(str(sel.get("code", "")))
	tex.texture = load(tp) if ResourceLoader.exists(tp) else null
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED     # the whole map, letterboxed, never cropped
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.size = pd
	_shell_add(tex, Vector2(pos.x + pad, py))
	var tx := pos.x + pad
	var tags := [MODE_NAMES.get(mode, mode), "%d NODES" % sel["nodes"].size()]
	for k in _relay_kinds(sel).replace("    /    ", "").split(" + ", false):
		tags.append(k.to_upper())
	for t in tags:
		var tw := UiKit.text_w(self, t, 12, true) + 20.0
		if tx + tw > pos.x + dims.x - pad:
			break
		content.add_child(UiKit.rect(Vector2(tx, pos.y + dims.y - pad - th), Vector2(tw, th), Color(UiKit.FRAME, 0.55)))
		_shell_add(UiKit.label(self, t, 12, UiKit.INK, true), Vector2(tx + 10.0, pos.y + dims.y - pad - th + 5.0))
		tx += tw + 6.0


func _setup_colours(pos: Vector2, width: float) -> void:
	## YOUR TEAM COLOUR: the hex chips (0.19.0), FACTION's split hexagon with your emblem (0.19.2 spec H2).
	_shell_add(UiKit.label(self, "YOUR TEAM COLOUR", 12, UiKit.MUTED, true, 3), pos)
	var hy := pos.y + UiKit.line_h(self, 12, true) + 8.0
	var keys := COLOUR_NAMES.keys()
	var hs := UiKit.tap_h(self, 44.0)
	var gap := clampf((width - hs * keys.size()) / float(keys.size() - 1), 4.0, 14.0)
	for i in range(keys.size()):
		var ck: String = keys[i]
		var wedges := FACTIONS.map(func(f): return Rules.FACTIONS[f][1]) if ck == "faction" else []
		var cc: Color = Color.WHITE if ck == "faction" else Rules.SEATS[ck]
		var chip := hex_chip(Vector2(pos.x + i * (hs + gap), hy), Vector2(hs, hs), cc, wedges, ck == colour, COLOUR_NAMES[ck], func():
			colour = ck
			show_setup())
		if ck == "faction":
			chip.emblem_faction = faction              # a recognisable face, not just wedges
	var y := hy + hs + 6.0
	if colour == "faction":                            # a one-line caption while FACTION is picked
		_shell_add(UiKit.label(self, "Every player in their faction's colour", 13, Color("ffd15c")), Vector2(pos.x, y))
		y += UiKit.line_h(self, 13) + 6.0
	if not mobile:
		var n := UiKit.label(self, "Team modes: one hue per team, light and dark. FACTION: every seat in its own faction colour (Alpha 11).", 12, UiKit.DIM)
		n.clip_text = true
		n.size = Vector2(width, UiKit.line_h(self, 12))
		_shell_add(n, Vector2(pos.x, y))


func _setup_faction(pos: Vector2, dims: Vector2) -> void:
	## SETUP's faction card: your character, name, your army preset on this map (a relay skill greyed to its
	## fallback where the map has no relays; tap: ARMIES), CHANGE (-> FACTION).
	var acc := UiKit.accent(faction)
	UiKit.panel(self, pos, dims, faction)
	var pad := 8.0
	var hs := dims.y - pad * 2.0
	_shell_add(_cutout(faction, Vector2.ZERO, Vector2(hs, hs)), pos + Vector2(pad, pad))
	var ct := "CHANGE"
	var cw := UiKit.text_w(self, ct, 14, true) + 34.0
	var cb := UiKit.btn(self, ct, Vector2(pos.x + dims.x - pad - cw, pos.y), Vector2(cw, 40), show_factions, "tertiary", faction, 14)
	cb.position.y = pos.y + (dims.y - cb.size.y) / 2.0
	var relays := ArmyPresets.map_has_relays(_selected_map())
	var eff := ArmyPresets.effective(faction, ArmyPresets.loadout_for(faction), relays)
	var isz := minf(34.0, cb.size.y - 16.0)
	var aw := isz * 3.0 + 12.0 + 20.0
	var ab := UiKit.btn(self, "", Vector2(cb.position.x - 8.0 - aw, cb.position.y), Vector2(aw, cb.size.y), func(): show_armies(faction, show_setup),
			"secondary", faction)
	ab.tooltip_text = "Your army preset - tap to change it in ARMIES"
	var ids := [eff["active"], eff["map"], eff["ultimate"]]
	for i in range(3):
		var ic: Color = UiKit.STAR if (i == 2 or (i == 1 and eff["swapped"] != "")) else acc
		skill_icon(ids[i], Vector2(10.0 + i * (isz + 6.0), (ab.size.y - isz) / 2.0), Vector2(isz, isz), ic, ab)
	var tx := pos.x + pad + hs + 12.0
	var tw := ab.position.x - 8.0 - tx
	var lines := [[UiKit.NAMES[faction], 17, acc, true], ["%s  ·  SEAT A" % UiKit.SUBS[faction], 13, UiKit.MUTED, false]]
	if not Rules.abilities_on:
		lines.append(["ABILITIES OFF", 12, UiKit.DIM, false])
	elif eff["swapped"] != "":
		lines.append(["NO RELAYS: %s" % ArmyPresets.skill_name(eff["map"]).to_upper(), 12, Color("ffd15c"), false])
	var total := 0.0
	for ln in lines:
		total += UiKit.line_h(self, ln[1], ln[3])
	var ly := pos.y + (dims.y - total) / 2.0
	for ln in lines:
		var l := UiKit.label(self, ln[0], ln[1], ln[2], ln[3])
		l.clip_text = true
		l.size = Vector2(maxf(10.0, tw), UiKit.line_h(self, ln[1], ln[3]))
		_shell_add(l, Vector2(tx, ly))
		ly += l.size.y


func _faction_picks(seat: String, pos: Vector2, width: float, back: Callable) -> float:
	## An AI seat's faction pick (0.19.2 spec H3: one per enemy seat): ANY (drawn when you deploy) or one of the five -
	## the characters, the picked one lit. Returns the row's height.
	var pick := str(rival_picks.get(seat, "random"))
	var s := UiKit.tap_h(self, 50.0)
	var aw := UiKit.text_w(self, "ANY", 14, true) + 36.0
	var gap := clampf((width - aw - s * 5.0) / 5.0, 4.0, 10.0)
	UiKit.btn(self, "ANY", pos, Vector2(aw, 50), func():
		rival_picks[seat] = "random"
		back.call(), "selected" if pick == "random" else "secondary", faction, 14).tooltip_text = "ANY FACTION"
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var b := UiKit.btn(self, "", pos + Vector2(aw + gap + i * (s + gap), 0), Vector2(s, 50), func():
			rival_picks[seat] = f
			back.call(), "selected" if pick == f else "secondary", f)
		b.tooltip_text = UiKit.NAMES[f]
		b.add_child(_cutout(f, Vector2(5, 5), b.size - Vector2(10, 10)))
	return s


func _difficulty(pos: Vector2, width: float) -> void:
	## DIFFICULTY: Alpha 11's five levels side by side - or, where they don't fit (phones), a < LEVEL > stepper.
	var levels: Array = Rules.AI_LEVELS.keys()
	var gap := 6.0
	var lw := (width - gap * (levels.size() - 1)) / float(levels.size())
	var fs := UiKit.px(self, 15)
	var fits := levels.all(func(l): return UiKit.BODY.get_string_size(str(l).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0 <= lw)
	if fits:
		for i in range(levels.size()):
			var lv: String = levels[i]
			var b := UiKit.btn(self, lv.to_upper(), pos + Vector2(i * (lw + gap), 0), Vector2(lw, 44), func():
				ai_level = lv
				show_setup(), "selected" if lv == ai_level else "secondary", faction, 15)
			b.add_theme_font_override("font", UiKit.BODY)
		return
	var i0 := maxi(0, levels.find(ai_level))
	var sw := UiKit.tap_h(self, 44.0)
	UiKit.btn(self, "‹", pos, Vector2(sw, 44), func():
		ai_level = levels[(i0 + levels.size() - 1) % levels.size()]
		show_setup(), "secondary", faction, 20)
	UiKit.btn(self, "›", pos + Vector2(width - sw, 0), Vector2(sw, 44), func():
		ai_level = levels[(i0 + 1) % levels.size()]
		show_setup(), "secondary", faction, 20)
	var mid := UiKit.panel(self, pos + Vector2(sw + 8.0, 0), Vector2(width - sw * 2.0 - 16.0, sw), faction, true)
	var l := UiKit.label(self, "%s   %d / %d" % [str(levels[i0]).to_upper(), i0 + 1, levels.size()], 15, UiKit.INK, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(mid.size.x, UiKit.line_h(self, 15, true))
	_shell_add(l, mid.position + Vector2(0, (sw - l.size.y) / 2.0))


func _toggle(text: String, on: bool, pos: Vector2, dims: Vector2, call: Callable) -> Button:
	## An ON / OFF switch: a check box (ticked when ON) and its name; the frame lit while ON.
	var b := UiKit.btn(self, text, pos, dims, call, "selected" if on else "secondary", faction, 15)
	b.add_theme_font_override("font", UiKit.BODY)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var bs := minf(22.0, b.size.y - 16.0)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		(b.get_theme_stylebox(st) as StyleBoxFlat).content_margin_left = 12.0 + bs + 10.0
	b.tooltip_text = "%s: %s" % [text, "ON" if on else "OFF"]
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(12.0, (b.size.y - bs) / 2.0)
	box.size = Vector2(bs, bs)
	var acc := UiKit.accent(faction)
	box.draw.connect(func():
		box.draw_style_box(UiKit.sb(acc if on else Color(UiKit.BASE, 0.9), acc if on else UiKit.MUTED, 2, 3), Rect2(Vector2.ZERO, box.size))
		if on:
			box.draw_polyline(PackedVector2Array([Vector2(bs * 0.24, bs * 0.52), Vector2(bs * 0.43, bs * 0.72), Vector2(bs * 0.78, bs * 0.3)]),
					UiKit.BASE, maxf(2.0, bs * 0.13), true))
	b.add_child(box)
	return b


func show_seats() -> void:
	## SEATS & TEAMS (screen system 29), from SETUP: PLAYERS (the map's modes), then every seat - you in seat A (your
	## faction, CHANGE -> FACTION), each AI seat as ally or rival (its team in team modes) with its faction pick; DONE.
	_last_show = show_seats                  # a resize that changes the phone sizing rebuilds it (_fit)
	var sel := _selected_map()
	var modes := _modes_of(sel)
	if not mode in modes:
		mode = modes[0]
	var area := shell_open("OOZE / SEATS & TEAMS", "play", show_setup, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "MATCH SETUP", "SEATS & TEAMS.")
	var gap := 10.0
	var mw := (w - gap * (modes.size() - 1)) / float(modes.size())
	var mb: Button
	for i in range(modes.size()):
		var md: String = modes[i]
		mb = UiKit.btn(self, MODE_NAMES.get(md, md), Vector2(x + i * (mw + gap), y), Vector2(mw, 44), func():
			mode = md
			show_seats(), "selected" if md == mode else "secondary", faction, 15)
	y += mb.size.y + 14.0
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var dw := maxf(UiKit.text_w(self, "DONE  →", 18, true) + 56.0, 170.0)
	UiKit.btn(self, "DONE  →", Vector2(content.size.x - x - dw, fy), Vector2(dw, 48), show_setup, "primary", faction, 18)
	_shell_add(UiKit.label(self, "Team colour identifies ownership. Faction is your army.", 15, UiKit.MUTED),
			Vector2(x, fy + (bh - UiKit.line_h(self, 15)) / 2.0))
	# the seats, two per row, in a scroll (five seats outgrow a phone)
	var team := {}
	for s in sel.get("seats", {}).get(mode, []):
		if mode in ["2v2", "3v3", "2v2v2"] and s.get("team") != null:
			team[str(s.get("seat", ""))] = int(s["team"])
	var seats := ["A"] + _enemy_seats()
	var cw := (w - 16.0 - gap) / 2.0
	var ph := UiKit.tap_h(self, 50.0)
	var card_h := 14.0 + UiKit.line_h(self, 12, true) + UiKit.line_h(self, 17, true) + 10.0 + ph + 14.0
	var st := stack_open(Vector2(x, y), Vector2(w, fy - 12.0 - y))
	var before := content.get_child_count()
	for i in range(seats.size()):
		var s: String = seats[i]
		var p := Vector2((i % 2) * (cw + gap), (i / 2) * (card_h + gap))
		UiKit.panel(self, p, Vector2(cw, card_h), faction, s == "A")
		var ally: bool = s == "A" or (team.has(s) and team.get(s) == team.get("A", -1))
		var kick := "SEAT %s%s" % [s, ("  ·  TEAM %d" % (int(team[s]) + 1)) if team.has(s) else ""]
		_shell_add(UiKit.label(self, kick, 12, UiKit.accent(faction), true, 3), p + Vector2(16, 14))
		var role := "YOU" if s == "A" else ("AI ALLY" if ally else "AI RIVAL")
		var ry := 14.0 + UiKit.line_h(self, 12, true)
		_shell_add(UiKit.label(self, role, 17, UiKit.INK, true), p + Vector2(16, ry))
		UiKit.tag(self, "PLAYER" if s == "A" else "AI", p + Vector2(cw - 16.0 - UiKit.text_w(self, "PLAYER" if s == "A" else "AI", 14, true) - 46.0, 12.0), faction)
		var py := ry + UiKit.line_h(self, 17, true) + 10.0
		if s == "A":
			_shell_add(_cutout(faction, Vector2.ZERO, Vector2(ph, ph)), p + Vector2(16, py))
			_shell_add(UiKit.label(self, "%s  ·  %s" % [UiKit.NAMES[faction], UiKit.SUBS[faction]], 15, UiKit.INK, true),
					p + Vector2(16.0 + ph + 12.0, py + (ph - UiKit.line_h(self, 15, true)) / 2.0))
			var ct := "CHANGE"
			var chw := UiKit.text_w(self, ct, 14, true) + 34.0
			UiKit.btn(self, ct, p + Vector2(cw - 16.0 - chw, py), Vector2(chw, 50), show_factions, "tertiary", faction, 14)
		else:
			_faction_picks(s, p + Vector2(16, py), cw - 32.0, show_seats)
	stack_capture(st, before)
	stack_close(st, ceilf(seats.size() / 2.0) * (card_h + gap))
	shell_raise()


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


func show_confirm_demo() -> void:
	## UI: SCREENSHOT HELPER only (--menu-page=confirm_demo) - ConfirmSheet (screen system 26) over a page, with the
	## words a LEAVE MATCH would use. No button in the game opens it; both actions just go back to HOME.
	_last_show = show_confirm_demo
	shell_open("OOZE / CONFIRM", "home", Callable(), faction)
	ConfirmSheet.make(self, "CONFIRM ACTION", "LEAVE THIS MATCH?",
			"Your current match will end. Campaign progress from this attempt will not be saved.",
			"KEEP PLAYING", "LEAVE MATCH", show_main, show_main, faction)


# ------------------------------------------------------------------ online (Net, rooms through the room server)
func show_online() -> void:
	_last_show = show_online                  # a resize that changes the phone sizing rebuilds it (_fit)
	## ONLINE: pick your faction, then CREATE ROOM (you host) or JOIN ROOM (the host's code).
	clear_page("city")
	_page = "online"
	header(0)
	label_at("PLAY WITH FRIENDS", P(40, 107), 43)
	frame(P(35, 174), P(1600, 640))
	label_at("PRIVATE ROOMS  ·  HOSTED ON THE OOZE ROOM SERVER", P(60, 196), 24, color())
	var about := label_at("Create a room and share its four-character code; everyone opens this same link. The room server runs the match, so a phone that locks or switches apps only drops its own seat - RECONNECT takes it back. The room's creator picks the map and settings. Free-for-all for 2 to 5 players, or teams. Rematch reuses the room; chat stays between rounds.",
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
	var msg := Net.status if Net.status != "" else ("Rooms run on the Ooze room server, so any network that reaches the internet can join. If the server is busy, the room's creator hosts it in their browser instead (keep that tab in front)." if web
			else "Online rooms run in the browser build: open https://talos91.github.io/ooza-syndicate-v2/")
	var st := label_at(msg, P(60, 650), 20, Color("ffd15c") if Net.status != "" else Color("adc7d2"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(1540 * K, 0)
	st.size = Vector2(1540 * K, 0)
	nav_button("BACK", P(40, foot_y()), P(230, 58), func():
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
	_last_show = show_lobby                  # a resize that changes the phone sizing rebuilds it (_fit)
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
	var host := Net.can_control()                     # the browser host, or a server room's owner (Alpha 20)
	label_at("ROOM %s" % (Net.room_code if Net.room_code != "" else "...."), P(40, 100), 52)
	var th := rh(52)
	var copy := nav_button("SHARE CODE", P(420, 110), P(230, th), _share_code)
	copy.disabled = Net.room_code == ""
	var chat := nav_button("CHAT (%d)" % Net.chat_unread() if Net.chat_unread() > 0 else "CHAT", P(668, 110), P(180, th), Net.open_chat)
	chat.disabled = not Net.connected
	_chat_btn = chat
	var army := nav_button("MY ARMY", P(866, 110), P(170, th), func(): show_armies(faction, show_lobby))   # your preset = your loadout
	army.disabled = Net.active
	var st := label_at(Net.status, P(1054, 110.0 + th / 2.0 - 11.0), 18, Color("adc7d2"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(584 * K, 0)
	st.size = Vector2(584 * K, 0)
	# both frames start below the (possibly taller) top row and stop short of the (possibly taller) foot
	# row - a scrollable stack (stack_open()) inside each, since on mobile several rows below grow to the
	# 44 pt tap minimum, more than fits stacked at the desktop gaps
	var fy := 110.0 + th + 16.0
	var frame_h := foot_y() - 20.0 - fy
	# players (0.18.7, Daniele: "there should be so i can switch to my gf team"; every seat's colour is
	# the same on every screen): team modes list the seats team by team, each team with its JOIN TEAM
	# control (tall enough for a phone thumb); the host can pick a player's row and MOVE them
	frame(P(35, fy), P(800, frame_h))
	label_at("PLAYERS  %d / %d" % [Net.roster.size(), Net.slots()], P(58, fy + 17.0), 28)
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
	var left_st := stack_open(P(50, fy + 56.0), P(770, maxf(160.0, frame_h - 56.0 - 14.0)))
	var y := 0.0
	for g in groups:
		var top := y
		var before := content.get_child_count()
		for i in g[1]:
			_lobby_row(i, by_slot.get(i, -1), colours, P(8, y), P(row_w, row_h - 8.0), host and team_mode)
			y += row_h
		if team_mode:
			_team_button(int(g[0]), colours, P(610, top), P(152, y - top - 8.0))
			y += 10.0
		stack_capture(left_st, before)
	y += 8.0
	var frow_h := rh(52)
	var before_fc := content.get_child_count()
	label_at("FACTION", P(8, y + frow_h / 2.0 - 9.0), 18, Color("aac3cd"))
	_faction_row(P(140, y), P(114, frow_h))
	stack_capture(left_st, before_fc)
	y += frow_h + 10.0
	var crow_h := rh(52)
	var before_cc := content.get_child_count()
	label_at("COLOUR", P(8, y + crow_h / 2.0 - 9.0), 18, Color("aac3cd"))
	_colour_row(P(140, y), P(74, crow_h))
	stack_capture(left_st, before_cc)
	y += crow_h + 8.0
	if not mobile:                                    # the phone skips the recap to save room (the chip colours already show it)
		var hint := "Every seat has one colour, the same on every screen. " + (("Teammates share a hue family (%s); a colour from a free family moves your team to it. " % " / ".join(
				Net.families().map(func(f): return Rules.FAMILY_NAMES.get(f[0], "")))) if team_mode else "Seats go in join order. ")
		if team_mode and host:
			hint += "Host: tap a player, then MOVE on a team."
		if Net.abilities and not ArmyPresets.map_has_relays(_selected_map()):
			hint += " No relays on this map: a gold map skill is the faction's fallback for a relay skill."
		var before_h := content.get_child_count()
		var hl := label_at(hint, P(8, y), 14, Color("7795a4"))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size = Vector2(700 * K, 0)
		hl.size = Vector2(700 * K, 0)
		stack_capture(left_st, before_h)
		y += 40.0
	stack_close(left_st, y)
	# match settings (host decides)
	map_path = Net.map_path
	frame(P(855, fy), P(780, frame_h))
	label_at("MATCH" + ("" if host else "  ·  the host decides"), P(878, fy + 17.0), 28)
	map_preview(P(876, fy + 62.0), P(738, 290))
	var right_st := stack_open(P(870, fy + 62.0 + 290.0 + 14.0), P(750, maxf(160.0, frame_h - (62.0 + 290.0 + 14.0) - 14.0)))
	var y2 := 0.0
	var step_h := rh(48)
	var before_step := content.get_child_count()
	label_at(str(_selected_map().get("name", "")).replace("*", "").to_upper(), P(8, y2 + step_h / 2.0 - 13.0), 26)
	var prev := nav_button("<", P(570, y2), P(80, step_h), func(): _step_map(-1))
	var next := nav_button(">", P(664, y2), P(80, step_h), func(): _step_map(1))
	prev.disabled = not host
	next.disabled = not host
	stack_capture(right_st, before_step)
	y2 += step_h + 20.0
	var mode_h2 := rh(48)
	var before_mode := content.get_child_count()
	label_at("PLAYERS", P(8, y2 + mode_h2 / 2.0 - 10.0), 20, Color("aac3cd"))
	for i in range(Net.MODES.size()):
		var md: String = Net.MODES[i]
		var mb := nav_button(Net.MODE_LABELS[md], P(92 + i * 96, y2), P(90, mode_h2), func():
			Net.set_mode(md)
			show_lobby(), md == Net.mode)
		mb.add_theme_font_size_override("font_size", int(round(15 * K)))
		mb.disabled = not host or Net.roster.size() > Net.SLOTS[md] or Net.maps_for(md).is_empty()
	stack_capture(right_st, before_mode)
	y2 += mode_h2 + 20.0
	var ls_h2 := rh(56)
	var before_ls := content.get_child_count()
	var lb := nav_button("LAST STAND / %s" % ("ON" if Net.last_stand else "OFF"), P(8, y2), P(360, ls_h2), func():
		Net.toggle_last_stand()
		show_lobby())
	lb.disabled = not host
	var abl := nav_button("ABILITIES / %s" % ("ON" if Net.abilities else "OFF"), P(384, y2), P(360, ls_h2), func():   # SKILLS 2.0
		ArmyPresets.room_toggle_abilities(Net)
		show_lobby())
	abl.disabled = not host
	stack_capture(right_st, before_ls)
	y2 += ls_h2 + 14.0
	var empty_h := rh(50)
	var before_empty := content.get_child_count()
	var ab := nav_button("EMPTY SEATS / %s" % ("AI " + Net.ai_fill.to_upper() if Net.ai_fill != "" else "PLAYERS ONLY"), P(8, y2), P(736, empty_h), func():
		Net.set_ai_fill(Net.AI_FILL[(Net.AI_FILL.find(Net.ai_fill) + 1) % Net.AI_FILL.size()])
		show_lobby())
	ab.add_theme_font_size_override("font_size", int(round(fsz(17) * K)))
	ab.disabled = not host
	stack_capture(right_st, before_empty)
	y2 += empty_h + 10.0
	stack_close(right_st, y2)
	nav_button("LEAVE ROOM", P(40, foot_y()), P(260, 58), func():
		Net.leave()
		show_online())
	if host:
		var go := nav_button("DEPLOY", P(1280, foot_y()), P(352, 58), func(): Net.start_match(), true)
		go.disabled = not Net.can_start()
		if not Net.can_start():
			label_at("DEPLOY opens when every seat is filled (or EMPTY SEATS: AI)", P(820, foot_y() + 18.0), 17, Color("adc7d2"), false)   # shares the foot row with DEPLOY - see label_at()
	else:
		label_at("The host deploys when ready", P(1300, foot_y() + 18.0), 19, Color("adc7d2"), false)


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
	# this row's own size is deliberately left at its Alpha-11 dims (its tap targets - the row-select
	# button above, the MOVE / colour chips it feeds - already grow to the phone minimum): every label
	# inside it keeps its designed size too (grow=false), or the fixed-width faction-name/tag/icon layout
	# below would start overlapping itself, seat by seat, at a size no card redesign fixes.
	label_at(seat, Vector2(pos.x + 20 * K, mid - 22 * K), 34, col, false)
	var sw := ColorRect.new()                         # the seat's colour as a swatch, named beside it
	sw.color = col
	sw.position = Vector2(pos.x + 64 * K, mid - 13 * K)
	sw.size = P(10, 26)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(sw)
	if id >= 0:
		var f: String = str(Net.roster[id]["faction"])
		label_at("VIRIDIAN BLOOM" if f == "bloom" else NAMES[f].replace("\n", " "), Vector2(pos.x + 84 * K, mid - 24 * K), 22, Rules.FACTIONS[f][1], false)
		var tags := ("HOST" if id == Net.room_owner else "") + ("  ·  YOU" if id == Net.local_id() else "") + ("  ·  RECONNECTING" if Net.is_away(id) else "")
		label_at(("%s  %s" % [str(colours.get(seat, "")).to_upper(), tags]).strip_edges(), Vector2(pos.x + 84 * K, mid + 2 * K), 16, Color("ffd15c"), false)
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
		label_at(("AI  ·  %s" % Net.ai_fill.to_upper()) if Net.ai_fill != "" else "open seat - waiting for a player", Vector2(pos.x + 84 * K, mid - 12 * K), 18, Color("7795a4"), false)


func _team_button(t: int, colours: Dictionary, pos: Vector2, dims: Vector2) -> void:
	## JOIN TEAM n (you), or MOVE X HERE (the host, with a player picked); a full team takes nobody.
	dims = tap(dims)                                  # grow once so the bottom hue bar (below) lands correctly
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
	## Your colour: one hexagon chip per hue, filled solid in its colour, border the same colour, no
	## words (Daniele, 0.19.0); taken hues (and, in team modes, another team's family) are dimmed and
	## disabled. The picked chip gets HexChip's white ring + scale-up.
	var me := Net.local_id()
	var mine := Net.colour_of(me)
	for i in range(HUE_NAMES.size()):
		var k: String = HUE_NAMES[i]
		var ok := Net.colour_allowed(me, k) or k == mine
		var b := hex_chip(pos + Vector2(i * (dims.x + 5 * K), 0), dims, Rules.HUES[k], [], k == mine, k.to_upper(), func():
			Net.set_colour(k)
			show_lobby())
		b.disabled = not ok or Net.active


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
	if OS.has_feature("web"):                                  # PROGRESSION: the HTML name field (ACCOUNT)
		_poll_name(dt)
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
