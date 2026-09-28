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
var _last_show := Callable():                    # the page on screen (rebuilt when a resize changes the phone sizing)
	set(v):
		_prev_show = _last_show                      # UI: the page before it - a meta page's BACK (_meta_open)
		_last_show = v
var _prev_show := Callable()
var _built_pt := 0.0                             # _pt_factor() the page was built with (0 while building)
var _backdrop: TextureRect
var _backdrop_art: Texture2D                     # the backdrop's own art (HOME swaps in the hero faction's scene)
var _backdrop_ay := 0.5                           # UI: the backdrop's vertical anchor when it crops (0.5 centred; HOME
                                                  # lower, so the wallpaper's creature stands above the tab bar)
# UI: the Alpha 21 app shell (Daniele's navigation mockups, 2026-09-28): a shell page lays out full screen width in
# canvas units (UiKit) between a TopBar and a NavBar - HOME / PLAY / ARMIES / CAMPAIGN.
var _shell := false
var _built_w := 0.0                              # the shell page's canvas width when built (a rotation rebuilds it)
var top_bar: TopBar
var nav_bar: NavBar
var shell_f := "vex"                             # the faction a shell page is dressed in (its accent, its backdrop)
var shell_back := Callable()                     # the page's BACK (a subflow), or none (a top-level tab)
var shell_slim := false                          # a phone subflow: BACK in the bar, no tab bar
var safe := Vector4.ZERO                         # the device's unsafe bands around a shell page, in page units
var _page := ""                                  # "online" / "lobby": rebuilt when the room changes
var _tele_page := ""                               # PROGRESSION (Alpha 21): the open page for telemetry (the breadcrumb's last part)


func telemetry_page_name() -> String:
	## The page the menu shows, for the menu perf sample ("home", "faction", "settings"; an old-style page's _page).
	return _tele_page if _tele_page != "" else _page
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
var _lobby_note := ""                              # READY: the host's last notice in the lobby ("Settings changed - ...")
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
	return K * s * UiKit.pt_per_px(vp)                # real points on the web (the page's CSS size)


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
	if not m.relaunched:                              # UI: a fresh start opens on the faction played last (HOME's hero);
		faction = UiKit.last_faction()                # AUDIT FIX: main cleared relaunch already - its own flag says it
	if Net.in_room() or Net.status != "":             # back from a room: keep the faction you played
		faction = Net.preferred_faction
	ai_level = m.ai_level
	map_path = m.map_path
	mode = m.mode
	colour = m.color_choice
	for mp in MapPool.battlefield():
		maps.append({"path": mp, "data": m.pool_map(mp)})   # AUDIT FIX (B1): parsed once per session, read-only
	if not maps.any(func(x): return x["path"] == map_path):
		map_path = maps[0]["path"]                     # the pool is maps4/: the old roster is archive
	Net.lobby_changed.connect(_on_net_changed)
	Net.order_feedback.connect(_on_lobby_note)         # READY: the host's notices show in the lobby's foot
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
	_tele_page = ""                                   # PROGRESSION: the page name for the menu perf sample
	# one background only: the full-screen backdrop (Alpha 14 playtest: "background on top of a
	# background" - the page used to draw its own copy of the art, misaligned on taller screens)
	if _backdrop:
		_backdrop.texture = _backdrop_art
		_backdrop.modulate = Color(0.95, 0.95, 0.95) if _is_main else Color(0.62, 0.68, 0.74)
		_backdrop_ay = 0.5
		_place_backdrop()


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


# --- UI (speed, Daniele's phone test 2026-09-28): the map grid's thumbnails fill in a few per frame, and idle frames warm
# the texture cache (UiKit.tex / warm) - never while a finger or button is down, so a tap is never held up by a load
var _thumb_queue: Array = []                       # [TextureRect, thumbnail path]
var _warm_armed := false


func _speed_step() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var n := 0
	while not _thumb_queue.is_empty() and n < 3:
		var job: Array = _thumb_queue.pop_front()
		if is_instance_valid(job[0]):
			(job[0] as TextureRect).texture = UiKit.map_thumb(str(job[1]))
			n += 1
	if n > 0:
		return
	if not _warm_armed:                                # once: the pages' common art, then every map thumbnail
		_warm_armed = true
		UiKit.warm_menu(faction)
		var thumbs := []
		for entry in maps.slice(0, 18):                # the grid's first screens (the rest fill in as it opens)
			thumbs.append(MapPool.thumb(str((entry["data"] as Dictionary).get("code", ""))))
		UiKit.warm(thumbs)
	UiKit.warm_step()
# --- end UI (speed) ---


func picture(path: String, pos: Vector2, dims: Vector2) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var p := TextureRect.new()
	p.texture = UiKit.tex(path)
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
		p.texture = UiKit.map_thumb(MapPool.thumb(code))   # UI: the map alone, without the baked caption strip
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
	_tele_page = crumb.get_slice("/", crumb.get_slice_count("/") - 1).strip_edges().to_lower()   # PROGRESSION: "OOZE / FACTION" -> "faction"
	shell_f = f if f != "" else faction
	shell_back = back
	shell_slim = mobile and back.is_valid()
	if _backdrop:
		var bg := UiKit.background(shell_f)
		if bg != null:
			_backdrop.texture = bg
		_backdrop.modulate = Color(0.55, 0.58, 0.62)
		_backdrop_ay = 0.5
		_place_backdrop()
	top_bar = TopBar.make(self, crumb, shell_f, shell_slim)
	# (the bar's BACK / ? / gear / level block call bar_back / show_help / show_options / show_profile themselves - 0.22.1)
	content.add_child(top_bar)
	var y0 := top_bar.bar_height()
	var y1 := content.size.y
	if not shell_slim:
		nav_bar = NavBar.make(self, tab, shell_f)
		pass                                           # (its tabs call _on_tab themselves - 0.22.1)
		content.add_child(nav_bar)
		y1 = nav_bar.position.y
	return Rect2(0, y0, content.size.x, y1 - y0)


func bar_back() -> void:
	## The slim top bar's BACK: the page's own way back (shell_open's `back`).
	if shell_back.is_valid():
		shell_back.call()


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
		"campaign":                                    # UI (Daniele, 0.22.0): the tab opens every campaign first; the
			show_chapters()                            # city map opens once you pick one (show_campaign)


func _shell_add(c: Control, pos: Vector2) -> Control:
	return UiKit.add(self, c, pos)


func _place_backdrop() -> void:
	## UI: the backdrop covers the screen (like STRETCH_KEEP_ASPECT_COVERED), cropped at `_backdrop_ay` (0 = keep the
	## top, 1 = keep the bottom) - HOME keeps its wallpaper's floor, where the creature stands, on wide phones.
	if not _backdrop or _backdrop.texture == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var ts := Vector2(_backdrop.texture.get_size())
	if ts.x <= 0.0 or ts.y <= 0.0 or vp.x <= 0.0:
		return
	var sz := ts * maxf(vp.x / ts.x, vp.y / ts.y)
	_backdrop.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.size = sz
	_backdrop.position = Vector2((vp.x - sz.x) / 2.0, (vp.y - sz.y) * _backdrop_ay)


func _backdrop_point(frac: Vector2) -> Vector2:
	## UI: a point of the backdrop art (fractions of the image) in page units - where HOME's wallpaper creature stands.
	var gp := _backdrop.position + _backdrop.size * frac
	return (gp - content.position) / content.scale.x


func _fade_left(area: Rect2, reach: float) -> void:
	## A dark wash from the left edge, so HOME's white headline reads over the bright wallpaper (VEX / NULL / SOLAR have
	## white sky and fog there): nearly opaque behind the text, gone before the creature.
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BASE, 0.9))
	g.add_point(0.55, Color(UiKit.BASE, 0.72))
	g.set_color(g.get_point_count() - 1, Color(UiKit.BASE, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.25, 0)
	gt.fill_to = Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(r)
	r.position = area.position
	r.size = Vector2(reach, area.size.y)


const HOME_CREATURE := {                         # where each FINAL wallpaper's creature stands: [centre x, feet y]
	"vex": Vector2(0.73, 0.86), "null": Vector2(0.76, 0.83), "bloom": Vector2(0.71, 0.84),
	"ember": Vector2(0.77, 0.88), "solar": Vector2(0.71, 0.86),
}


func show_main() -> void:
	## HOME (Daniele's screen system 01): the faction played last - its FINAL wallpaper behind, the creature in it on
	## the right (Daniele 2026-09-28; its tag under it) - the headline, PLAY (-> NEW GAME's faction step), CONTINUE CAMPAIGN, the training link while
	## lessons remain; CHALLENGES top right; QUIT / FULLSCREEN and the version at the foot; the install guide.
	_last_show = show_main                  # a resize that changes the phone sizing rebuilds it (_fit)
	var hero := UiKit.last_faction()
	var area := shell_open("OOZE / HOME", "home", Callable(), hero)
	_is_main = true
	if _backdrop:
		var wall := UiKit.wallpaper(hero)
		if wall != null:
			_backdrop.texture = wall
		_backdrop.modulate = Color(0.9, 0.9, 0.92)       # the wallpaper bright (the pages behind panels stay darker)
		_backdrop_ay = 0.7
		_place_backdrop()
	var acc := UiKit.accent(hero)
	_fade_left(area, content.size.x * 0.62)
	var x := shell_x() + 8.0
	# the wallpaper's creature, its tag under it (on the floor; kept above the tab bar)
	var feet := _backdrop_point(HOME_CREATURE.get(hero, Vector2(0.73, 0.86)) as Vector2)
	var tag_t := str(UiKit.TAGS[hero])
	var tag_w: float = UiKit.text_w(self, tag_t, 14, true) + tag_t.length() * 2.0 + 30.0
	var tag_h: float = UiKit.line_h(self, 14, true) + 14.0
	UiKit.tag(self, tag_t, Vector2(clampf(feet.x - tag_w / 2.0, content.size.x * 0.5, content.size.x - tag_w - shell_x()),
			minf(feet.y + 4.0, area.end.y - tag_h - 12.0)), hero)
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
	UiKit.btn(self, "PLAY", Vector2(x, y), Vector2(230, 54), show_play, "primary", hero, 20)   # UI (Daniele, 0.22.0): PLAY opens PLAY
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
	## PLAY (screen system 02): three image-led choices - VS AI (primary; NEW GAME's faction -> battlefield -> setup ->
	## rivals), ONLINE ROOMS, TRAINING. In your faction's accent like every page (Daniele 2026-09-28: not always cyan).
	_last_show = show_play
	var area := shell_open("OOZE / PLAY", "play")
	var x := shell_x()
	var top := page_title(area, "PLAY", "PICK YOUR FIGHT.")
	var ct := "CAMPAIGN  →"                            # UI (0.22.1, the Architect's suggestion): the campaigns are their own tab
	var ctw := UiKit.text_w(self, ct, 15, true) + 40.0
	UiKit.btn(self, ct, Vector2(content.size.x - x - ctw, area.position.y + (12.0 if shell_slim else 20.0)), Vector2(ctw, 42), show_chapters,
			"secondary", faction, 15)
	var gap := 16.0
	var cw := (content.size.x - x * 2.0 - gap * 2.0) / 3.0
	var ch := area.end.y - top - 18.0
	var done := TutorialDirector.done_count()
	var cards := [
		# Daniele's FINAL PLAY art (2026-09-28): the creatures are in the pictures, so no cutout over them
		["CUSTOM MATCH", "VS AI", "Pick a faction, a battlefield and your rivals.", "res://assets/art/ui/play_vs_ai.jpg", show_factions,
				"PLAY  →"],
		["WITH FRIENDS", "ONLINE ROOMS", "Create a room or join a friend's code.", "res://assets/art/ui/play_online.jpg", show_online,
				"PLAY ONLINE  →"],
		["LEARN THE CITY", "TRAINING", "%d / %d lessons done. Replay any lesson." % [done, TutorialDirector.TOTAL_LESSONS],
				"res://assets/art/ui/play_training.jpg", show_tutorial, "START  →" if done < TutorialDirector.TOTAL_LESSONS else "REPLAY  →"],
	]
	for i in range(cards.size()):
		var c := FrameCard.make(self, Vector2(cw, ch), faction)
		c.art_frac = 0.52
		c.set_kicker(cards[i][0])
		c.set_title(cards[i][1])
		c.set_note(cards[i][2])
		c.set_art(cards[i][3])
		c.set_action(cards[i][5])                      # UI (Daniele, 0.22.0): three equal cards, each with its own verb
		c.set_selected(false)
		var go: Callable = cards[i][4]
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


static var _opt_tab := "display"                   # SETTINGS: the open tab (kept while the game runs)
static var _opt_arg_read := false
const OPT_TABS := [["display", "DISPLAY"], ["privacy", "PRIVACY"], ["debug", "TESTING"]]   # Daniele 2026-09-28: match options
# (Last Stand, enemy counts) live in SETUP, not here; the test tools sit apart in TESTING (id "debug"); PROGRESSION:
# PRIVACY (Alpha 21) between them


func show_options() -> void:
	## SETTINGS (screen system 23; the top bar's gear): tabs of rows, each row its name, what it does and its choices
	## (the current one lit, the words carrying the state). DISPLAY: GRAPHICS AUTO / LOW RES / FULL and FRAME RATE AUTO /
	## 30 / 60 (Alpha 21 OPT-RENDER, perf_profile.gd, user://settings.cfg), DETAIL. TESTING (id "debug"): DEBUG TOOLS (the
	## Debug button and live sliders in matches), the progression TEST SWITCH. Match options (LAST STAND, ENEMY COUNTS) are
	## SETUP's (Daniele 2026-09-28: they make no sense here), TERRITORY the wardrobe's. The rows scroll
	## (phones grow them to 44 pt). DISPLAY ends with an AUDIO group: SOUND ON / OFF and VOLUME (sfx.gd), MUSIC ON / OFF and
## MUSIC VOLUME (music.gd), all live, then a small CREDITS line (the soundtrack's). TERRITORY lives
	## in ARMIES > COSMETICS > CORE (0.19.2). DONE / BACK return to the page the gear was pressed on.
	_last_show = show_options                  # a resize that changes the phone sizing rebuilds it (_fit)
	if not _opt_arg_read:                              # UI: screenshots open a tab (--options-tab=display)
		_opt_arg_read = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--options-tab="):
				_opt_tab = arg.substr(14)
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
		"debug":
			y += _opt_row(y, w, "DEBUG TOOLS", "The Debug button and live sliders in matches.",
					[["ON", Rules.debug_tools, func(): Rules.debug_tools = true], ["OFF", not Rules.debug_tools, func(): Rules.debug_tools = false]])
			y += _opt_row(y, w, "TEST SWITCH  ·  LOCKS", "OFF: everything unlocked (the testing default). ON: a preview of the game as players will see it once the locks go live - skills and looks earned or bought (until the page closes).",   # PROGRESSION
					[["OFF", Progression.unlock_all, func(): Progression.unlock_all = true], ["ON", not Progression.unlock_all, func(): Progression.unlock_all = false]])
		"privacy":
			y = _privacy_rows_options(y, w)            # PROGRESSION (Alpha 21): SHARE PLAY & CRASH DATA + the PRIVACY page
		_:                                            # DISPLAY
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
			y += _opt_row(y, w, "COLOUR-BLIND", "Player colours anyone can tell apart, with red-green or blue-yellow colour blindness. It picks every seat's colour in the match (your screen only). From the next match.",
					[["OFF", not Rules.colour_blind(), func(): Rules.set_colour_blind(false)], ["ON", Rules.colour_blind(), func(): Rules.set_colour_blind(true)]])
			# SOUND: the AUDIO group (sfx.gd, user://settings.cfg [audio]) - both heard at once, the tap itself included
			y += _say("AUDIO", Vector2(0, y + 18.0), 12, UiKit.accent(shell_f), 0.0, true) + 18.0
			y += _opt_row(y, w, "SOUND", "The match and the menus. OFF: silent (the VOLUME is kept for ON).",
					[["ON", Sfx.sound_on(), func(): Sfx.set_on(true)], ["OFF", not Sfx.sound_on(), func(): Sfx.set_on(false)]])
			var vols := []
			for v in Rules.SOUND_VOLUME_STEPS:
				var pct: int = v
				vols.append([Sfx.volume_label(pct), Sfx.volume() == pct, func(): Sfx.set_volume(pct)])
			y += _opt_row(y, w, "VOLUME", "How loud the sounds are - heard at once.", vols, not Sfx.sound_on())
			y += _opt_row(y, w, "MUSIC", "The soundtrack, in the menus and the match. OFF: no music (the MUSIC VOLUME is kept for ON).",
					[["ON", Music.music_on(), func(): Music.set_on(true)], ["OFF", not Music.music_on(), func(): Music.set_on(false)]])
			var mvols := []
			for v in Rules.MUSIC_VOLUME_STEPS:
				var pct: int = v
				mvols.append([Music.volume_label(pct), Music.volume() == pct, func(): Music.set_volume(pct)])
			y += _opt_row(y, w, "MUSIC VOLUME", "How loud the music is, apart from the sounds - heard at once.", mvols, not Music.music_on())
			# MUSIC: the soundtrack's credit (the game has no credits page: a small CREDITS line under AUDIO)
			y += _say("CREDITS", Vector2(0, y + 18.0), 12, UiKit.accent(shell_f), 0.0, true) + 18.0
			y += _say(Rules.MUSIC_CREDIT, Vector2(0, y + 8.0), 13, UiKit.MUTED, w) + 16.0
	_column_end(col, n0, y, true)


func _opt_row(y: float, w: float, title_text: String, desc: String, opts: Array, off := false) -> float:
	## A SETTINGS row: its name over what it does (left), its choices [text, current, apply] as chips at the right, the
	## current one lit; `off` greys them out. A pick applies and redraws the page. Returns the row's height.
	var ch := UiKit.tap_h(self, 40.0)
	var widths := []
	var cw := 0.0
	for o in opts:
		var bw := maxf(maxf(64.0, UiKit.tap_h(self, 46.0)), UiKit.text_w(self, str(o[0]), 14, true) + 32.0)   # >= 44 pt wide too
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
	r.texture = UiKit.tex(UiKit.hero_path(f))
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
	var nh := UiKit.line_h(self, 15, true)
	var two := nh + UiKit.line_h(self, 12) <= b.size.y - 6.0
	var ty := (b.size.y - (nh + (UiKit.line_h(self, 12) if two else 0.0))) / 2.0
	b.add_child(UiKit.emblem_node(f, nh, Vector2(hs + 14.0, ty)))   # the race emblem before the name
	var tx := hs + 14.0 + nh + 6.0
	var nm := UiKit.label(self, UiKit.NAMES[f], 15, UiKit.accent(f) if picked else UiKit.INK, true)
	var sl := UiKit.label(self, UiKit.SUBS[f], 12, UiKit.MUTED)
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
	var es := clampf(dims.y * 0.14, 40.0, 64.0)          # the race emblem, the card's top-right corner
	UiKit.emblem_rect(self, faction, Vector2(pos.x + dims.x - pad - es, pos.y + pad), es)
	var tx := pos.x + pad + hs + 18.0
	var tw := pos.x + dims.x - pad - tx - es * 0.6
	var ft: Array = Rules.FACTION_TRAITS[faction]
	# [text, size, colour, head, spacing] - measured as they draw (Daniele 2026-09-28: on his screen PERSISTENT TRAIT ·
	# COMING SOON wrapped where the old width estimate said one line, and COMING SOON sat on the trait's name). Where the
	# card is short (phones) it makes room in steps: the tagline goes, then the spacer, then the kicker shortens.
	var nb := "PERSISTENT\u00a0TRAIT"                          # (a no-break space: the words wrap as one)
	var attempts := [[true, true, nb], [false, true, nb], [false, false, nb], [false, false, "TRAIT"]]
	var labels := []
	var hts := []
	var total := 0.0
	for at in attempts:
		for l in labels:
			if l != null:
				(l as Label).queue_free()
		labels = []
		hts = []
		total = 0.0
		var lines := [[UiKit.SUBS[faction], 12, acc, true, 3], [UiKit.NAMES[faction], 38, acc, true, 0]]
		if at[0]:
			lines.append([Rules.FACTION_TAGLINES[faction], 15, UiKit.MUTED, false, 0])
		if at[1]:
			lines.append(["", 10, UiKit.INK, false, 0])
		var kick := "%s  ·  COMING SOON" % at[2]
		if UiKit.text_w(self, kick, 12, true) + kick.length() * 2.0 > tw:
			kick = kick.replace("  ·  ", "\n")                     # too wide: one part per line
		lines.append([kick, 12, acc, true, 2])
		lines.append([str(ft[0]).to_upper(), 16, UiKit.INK, true, 0])
		lines.append([str(ft[1]), 14, UiKit.MUTED, false, 0])
		for ln in lines:
			var h := float(ln[1])
			var l: Label = null
			if ln[0] != "":
				l = UiKit.label(self, ln[0], ln[1], ln[2], ln[3], ln[4])
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # a line that still runs long wraps, and is measured so
				l.custom_minimum_size = Vector2(tw, 0)
				l.size = Vector2(tw, 0)
				_shell_add(l, Vector2(tx, pos.y + pad))
				h = l.get_combined_minimum_size().y + 2.0
			labels.append(l)
			hts.append(h)
			total += h
		if total <= body_h:
			break
	var ly := pos.y + pad + maxf(0.0, (body_h - total) / 2.0)
	for i in range(labels.size()):
		if labels[i] != null:
			(labels[i] as Label).position = Vector2(tx, ly)
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
				acc if v > 1.001 else (UiKit.WEAKER if v < 0.999 else UiKit.INK))


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
	var area := shell_open("OOZE / TRAINING", "home", func(): page.back_pressed.emit())   # BACK: HOME (Daniele), so HOME's tab
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
		UiKit.emblem_rect(self, f, Vector2(tx, ty), l1)
		_say(UiKit.NAMES[f], Vector2(tx + l1 + 6.0, ty), 16, fa, 0.0, true)
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
	var bw := maxf(150.0, UiKit.text_w(self, "IN PROGRESS", 13, true) + 8.0)   # the right column fits its widest word
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
		# UI (Daniele 2026-09-28: "the BACK in LEADERBOARD just reloads the leaderboard"): every meta page sets _last_show
		# to itself before it gets here, so the page it came from is the one before that (_prev_show)
		_meta_from[page] = [_prev_show if _prev_show.is_valid() and _page != "" else fallback, tab]
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
	var pnl := UiKit.panel(self, pos, dims, shell_f, selected)
	var col := stack_open(pos + Vector2(18.0, 12.0), dims - Vector2(26.0, 24.0))
	col["panel"] = pnl
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


func _column_end(col: Dictionary, before: int, h: float, fit := false) -> void:
	## `fit`: the panel shrinks to its rows when they need less than it was given.
	stack_capture(col, before)
	var inner: Control = col["inner"]
	inner.custom_minimum_size = Vector2(float(col["w"]), h + 6.0)
	inner.size = inner.custom_minimum_size
	var sc: Control = col["scroll"]
	if fit and h + 12.0 < sc.size.y:
		sc.size.y = h + 12.0                            # a little over the rows: no scroll bar
		(col["panel"] as Control).size.y = h + 36.0


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
	var lp := UiKit.panel(self, Vector2(x, top), Vector2(cw, ch), shell_f)
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
		"deleted":                                  # PROGRESSION (Alpha 21): DELETE ACCOUNT done
			status = "ACCOUNT DELETED  -  this device keeps its progress; a new guest account starts next time"
			col = Color("ffd15c")
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
			y += _say(gn, Vector2(px, y), 13, UiKit.MUTED, w)
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
	ry = _privacy_rows_account(ry, rcw)                # PROGRESSION (Alpha 21): the switch, PRIVACY, DELETE ACCOUNT
	_column_end(right, n0, ry, true)
	var both := minf(ch, maxf(y + 16.0 - top, (right["panel"] as Control).size.y))   # one height for the pair
	lp.size.y = both
	(right["panel"] as Control).size.y = both
	(right["scroll"] as Control).size.y = both - 24.0


# ------------------------------------------------------------------ PROGRESSION: PRIVACY (Alpha 21)
func _privacy_rows_options(y: float, w: float) -> float:
	## SETTINGS > PRIVACY (TELEMETRY-PRIVACY-DESIGN §6): the switch as a settings row, then the PRIVACY page. UiKit canvas
	## units, rows at (0, y) in the tab's column; returns the next row's y.
	y += _opt_row(y, w, "SHARE PLAY & CRASH DATA",
			"Gameplay and performance numbers and crash reports, tied only to your game account id. OFF: nothing leaves this device.",
			[["ON", Telemetry.sharing(), func(): _set_share(true)], ["OFF", not Telemetry.sharing(), func(): _set_share(false)]])
	var pw := UiKit.text_w(self, "PRIVACY  →", 15, true) + 44.0
	var b := UiKit.btn(self, "PRIVACY  →", Vector2(0, y + 12.0), Vector2(pw, 44), func(): show_privacy(show_options),
			"secondary", shell_f, 15)
	return y + 12.0 + b.size.y + 12.0


func _privacy_rows_account(ry: float, rcw: float) -> float:
	## ACCOUNT's right column, under the Google sign-in (§6-§7): the switch, the PRIVACY page, DELETE ACCOUNT. UiKit canvas
	## units, rows at (0, ry), width rcw (the column scrolls); returns the next row's y.
	var a := _account()
	ry += 10.0
	ry += _say("PRIVACY", Vector2(0, ry), 15, UiKit.INK, rcw, true) + 8.0   # no line under it: the rows stay on a 640 px phone
	var sw := minf(rcw, UiKit.text_w(self, _share_label(), 15, true) + 44.0)
	var sb := UiKit.btn(self, _share_label(), Vector2(0, ry), Vector2(sw, 48), func():
		_toggle_share()
		show_account(), "secondary", shell_f, 15)
	ry += sb.size.y + 10.0
	var pw := UiKit.text_w(self, "PRIVACY", 15, true) + 44.0
	var dw := UiKit.text_w(self, "DELETE ACCOUNT", 15, true) + 44.0
	var pb := UiKit.btn(self, "PRIVACY", Vector2(0, ry), Vector2(pw, 48), func(): show_privacy(show_account),
			"secondary", shell_f, 15)
	var dx := pw + 12.0
	if dx + dw > rcw:                                  # a narrow phone column: DELETE ACCOUNT on its own row
		ry += pb.size.y + 10.0
		dx = 0.0
	var del := UiKit.btn(self, "DELETE ACCOUNT", Vector2(dx, ry), Vector2(dw, 48), _delete_prompt, "secondary", shell_f, 15)
	del.disabled = not a.signed_in()
	ry += del.size.y + 10.0
	return ry


func _share_label() -> String:
	return "SHARE PLAY & CRASH DATA: " + ("ON" if Telemetry.sharing() else "OFF")


func _toggle_share() -> void:
	_set_share(not Telemetry.sharing())


func _set_share(on: bool) -> void:
	Telemetry.choose(on)
	if on:
		Telemetry.flush_soon()


func show_privacy(back: Callable = Callable()) -> void:
	## PRIVACY (from SETTINGS and ACCOUNT): the full notice - the same text as privacy.html beside the game - in a
	## scrolling column, the switch, DONE back to where it was opened.
	var ret: Callable = back if back.is_valid() else show_options
	_last_show = func(): show_privacy(ret)
	var tab := _meta_open("privacy", ret)
	var done := func(): ret.call()
	var area := shell_open("OOZE / PRIVACY", tab, done, faction)
	_page = "privacy"
	var x := shell_x()
	var top := page_title(area, "PRIVACY  ·  SHARE PLAY & CRASH DATA: " + ("ON" if Telemetry.sharing() else "OFF"),
			"WHAT THE GAME KEEPS.")
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var sw := UiKit.text_w(self, _share_label(), 15, true) + 44.0
	UiKit.btn(self, _share_label(), Vector2(x, fy), Vector2(sw, 48), func():
		_toggle_share()
		show_privacy(ret), "secondary", shell_f, 15)
	UiKit.btn(self, "DONE  →", Vector2(content.size.x - x - 200.0, fy), Vector2(200, 48), done, "primary", shell_f, 16)
	var col := _column(Vector2(x, top), Vector2(content.size.x - x * 2.0, fy - 12.0 - top))
	var w: float = col["w"]
	var n0 := content.get_child_count()
	var y := 4.0
	for para in Telemetry.privacy_text().split("\n\n"):
		var heading := para == para.to_upper()
		y += _say(para, Vector2(0, y), 15 if heading else 14, UiKit.accent(shell_f) if heading else UiKit.MUTED, w, heading)
		y += 6.0 if heading else 16.0
	_column_end(col, n0, y)


func _delete_prompt() -> void:
	## DELETE ACCOUNT's confirm sheet over ACCOUNT: what goes, what stays, DELETE / CANCEL.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.position = Vector2(-3000, -3000)
	dim.size = Vector2(9000, 9000)
	content.add_child(dim)
	var pp := P(386, 230)
	var pd := P(900, 480)
	content.add_child(neon_panel(pp, pd, Color("ff5a4e"), true, Color("0a1216f4")))
	label_at("DELETE ACCOUNT?", pp + P(32, 24), 34, Color.WHITE, false)
	_wrapped("This deletes your account, cloud save, match history, leaderboard entries and shared play data. "
			+ "It can't be undone. The progress saved on this device stays.", pp + P(32, 90), 21, Color("c5d2da"), 836)
	var a := _account()
	var busy := [false]
	nav_button("DELETE", pp + P(32, 330), P(360, 66), func():
		if busy[0]:
			return
		busy[0] = true
		if await a.delete_account():
			_account_note = "Account deleted."
		else:
			_account_note = "Not deleted: " + a.last_error
		show_account())
	nav_button("CANCEL", pp + P(420, 330), P(300, 66), show_account, true)


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
			var me: bool = row.get("is_me", false) == true   # the server may send null
			y += _board_row("#%d" % int(row.get("rank", 0)), str(row.get("name", "")) + ("  (YOU)" if me else ""),
					"%d WINS" % int(row.get("wins", 0)), Vector2(0, y), w, me) + 6.0
		if not _board_me.is_empty():                  # 0.20.13: YOU, when you're not on the list - a row like the rest
			var wins := int(_board_me.get("wins", 0))
			y += 8.0
			y += _board_row("#%d" % int(_board_me.get("rank", 0)) if wins > 0 else "-", str(_board_me.get("name", "")) + "  (YOU)"
					+ ("" if wins > 0 else "  ·  win an online round vs a player"), "%d WINS" % wins, Vector2(0, y), w, true, UiKit.STAR) + 6.0
	_column_end(col, n0, y, true)


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
	if not rows.any(func(r): return r.get("is_me", false) == true):   # not on the list: say where you stand (0.20.13)
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
	_column_end(col, n0, y, true)


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
		if Rules.FACTIONS.has(f):                        # the race emblem, in its own colours
			UiKit.emblem_rect(self, f, Vector2(px, py), ic)
		var me: bool = p.get("is_me", false) == true   # (a null from the server)
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
	## The CAMPAIGN tab: the view used last - the CITY MAP (the 3D district diorama, the default: Daniele 2026-09-28)
	## or the mission CARDS (the hub, screen system 09, on the district of the next mission); each has a switch to the
	## other. A mission's return (main's menu_open "campaign") lands here too, so the city's star / bridge animations play.
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
	if UiKit.campaign_view() == "cards":
		_show_hub()
	else:
		show_city_map()


func _show_hub() -> void:
	## "CAMPAIGN / VEX BIOENGINEERS", the district's name and blurb; its missions as FrameCards in a row that swipes
	## sideways (number, the mission's art, title, stars; CONTINUE / PLAY / REPLAY, LOCKED with the reason, IN
	## DEVELOPMENT with what it needs); district paging and the stars at the foot; CITY MAP and CHAPTERS top right.
	_last_show = _show_hub
	var cf := _hub_faction()
	var h := Campaign.hub(cf, _hub_i) if cf != "" else {}
	var area := shell_open("OOZE / CAMPAIGN / %s" % str(UiKit.NAMES.get(cf, "")), "campaign", Callable(),
			cf if cf != "" else faction)                # the campaign's colour; ALL CAMPAIGNS (top right) goes back (0.22.0)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var bh := 42.0
	var bw := maxf(UiKit.text_w(self, "ALL CAMPAIGNS", 15, true), UiKit.text_w(self, "CITY MAP", 15, true)) + 40.0
	var by := area.position.y + 18.0
	UiKit.btn(self, "ALL CAMPAIGNS", Vector2(content.size.x - x - bw, by), Vector2(bw, bh), show_chapters, "secondary", shell_f, 15)
	if h.is_empty():                                   # no campaign has content (never in this build)
		page_title(area, "CAMPAIGN", "COMING LATER.")
		return
	_hub_i = int(h["district_index"])
	UiKit.btn(self, "CITY MAP", Vector2(content.size.x - x - bw * 2.0 - 12.0, by), Vector2(bw, bh), func():
		UiKit.save_campaign_view("map")                # the view switch: CAMPAIGN reopens on the city map
		show_city_map(), "secondary", shell_f, 15)
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
	var area := shell_open("OOZE / CAMPAIGN", "campaign", Callable(), _hub_faction() if _hub_faction() != "" else faction)   # the tab's page
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
		card.set_kicker({"open": "CAMPAIGN", "locked": "LOCKED"}.get(st, "COMING LATER"))
		match st:
			"open":
				card.set_state("next")
				card.set_action("PLAY  →")
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
				show_campaign())                       # its city map (or the cards, the view used last)
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
	_camp_page.view_switch = "CARDS"
	_camp_page.back_pressed.connect(show_chapters)       # UI (0.22.0): BACK to every campaign, the tab's page
	_camp_page.view_pressed.connect(func():
		UiKit.save_campaign_view("cards")
		_show_hub())
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
	art.texture = UiKit.tex(UiKit.hero_path(tf))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(8.0, 4.0)
	art.size = Vector2(hs, hs)
	b.add_child(art)
	var n := UiKit.label(self, UiKit.NAMES[tf], 15, UiKit.accent(tf) if picked else UiKit.INK, true)
	var lh := n.get_minimum_size().y + (UiKit.line_h(self, 11, true) if tf == faction else 0.0)
	var es := n.get_minimum_size().y
	b.add_child(UiKit.emblem_node(tf, es, Vector2(8.0 + hs + 6.0, (dims.y - lh) / 2.0)))   # the race emblem before the name
	var tx := 8.0 + hs + 6.0 + es + 6.0
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
	var es := clampf(dims.y * 0.13, 36.0, 56.0)          # the race emblem, the panel's top-right corner
	UiKit.emblem_rect(self, _army, pos + Vector2(dims.x - 16.0 - es, 16.0), es)
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
		var col := acc if v > 1.001 else (UiKit.WEAKER if v < 0.999 else UiKit.INK)
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
		art.texture = UiKit.tex(UiKit.hero_path(tf))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2.ONE * 5.0
		art.size = Vector2.ONE * (s - 10.0)
		b.add_child(art)
		UiKit.emblem_badge(b, tf, s * 0.36)


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
		return {"locked": true, "equipped": false, "line": "LOCKED  ·  " + _ward_price(item), "col": LOCK_COL}
	if id == equipped:
		return {"locked": false, "equipped": true, "line": "EQUIPPED", "col": UiKit.accent(_army)}
	# Daniele 2026-09-28: a look you own shows nothing; one open only while testing shows how it will be unlocked
	var owned := Progression.owns(item) or Progression.price(item).is_empty() and item != "vat:graduate"
	return {"locked": false, "equipped": false, "line": "" if owned else _ward_price(item), "col": LOCK_COL}


func _ward_price(item: String) -> String:
	## A look's way in, short (a tile's line): its SCRAP price, or the Graduate vat's condition.
	if item == "vat:graduate":
		return TutorialDirector.line("locked_cosmetic").to_upper()
	var price := Progression.price(item)
	return Progression.amount_text(int(price["soft"]), "soft", false) if price.has("soft") else "UNLOCK"


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
	elif st["locked"] or not Progression.owns(Progression.cosmetic_item(cat, sel, _army)) and str(st["line"]) != "":
		var item := Progression.cosmetic_item(cat, sel, _army)
		out = "TO UNLOCK: " + _cosmetic_path(cat, sel)
		var price := Progression.price(item)
		var costs := []
		for cur in ["soft", "premium"]:
			if price.has(cur):
				costs.append(Progression.amount_text(int(price[cur]), cur, false))
		if not costs.is_empty():
			out += "  ·  " + " OR ".join(costs)
		if not st["locked"]:
			out += "
Open while testing: you can equip it now."
	else:
		out = "A look only: tier read, footprint and colour stay the same."
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
	# UI: BACKGROUND (Daniele 2026-09-28): the match background - AUTO / ROTATE / one of the five - picked in a sheet
	var bgt := "BACKGROUND: " + _backdrop_short(UiKit.backdrop_choice())
	var bgw := UiKit.text_w(self, bgt, 14, true) + 36.0
	UiKit.btn(self, bgt, Vector2(content.size.x - x - nw - 12.0 - bgw, fy + (foot_h - bh) / 2.0), Vector2(bgw, 48), func():
		_bg_sheet = true
		show_maps(), "secondary", faction, 14)
	var iy := fy + (foot_h - info_h) / 2.0
	for ln in info:
		var l := UiKit.label(self, ln[0], ln[1], ln[2], ln[3])
		l.clip_text = true
		l.size = Vector2(w - nw - bgw - 36.0, UiKit.line_h(self, ln[1], ln[3]))
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
		var tp := MapPool.thumb(code)                  # the map alone (its caption strip is written below); a thumbnail
		if UiKit.cached(tp):                           # not loaded yet fills in a few frames later (_thumb_queue)
			tex.texture = UiKit.map_thumb(tp)
		else:
			_thumb_queue.append([tex, tp])
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
	if _bg_sheet:                                      # UI: the BACKGROUND sheet, over the page and its bars
		_backdrop_sheet(sel)


func _map_type(m: Dictionary) -> String:
	var g := str(m.get("group", "")).to_lower()
	return "training" if g in ["tutorial", "debug"] else g


# --- UI: BATTLEFIELD > BACKGROUND (Daniele 2026-09-28): the match background, your screen only (UiKit.backdrop_choice) ---
var _bg_sheet := "--backdrop-sheet" in OS.get_cmdline_user_args()   # the BACKGROUND sheet is open (screenshots: open)


func _backdrop_short(v: String) -> String:
	if v == "auto":
		return "AUTO"
	if v == "rotate":
		return "ROTATE"
	if not v.is_valid_int() or int(v) >= Scenery.BATTLE_BACKDROPS.size():
		return "AUTO"
	return UiKit.backdrop_name(int(v), Scenery.BATTLE_BACKDROPS[int(v)]).get_slice(" ", 0).trim_suffix(":")


func _backdrop_sheet(sel: Dictionary) -> void:
	## Over BATTLEFIELD: AUTO (the map's own background - what everyone in a room sees), ROTATE (a new one every match)
	## and the five, each by its picture; the current pick lit. A pick saves and closes; so does a tap outside.
	var dim := UiKit.rect(Vector2(-safe.x, -safe.y), content.size + Vector2(safe.x + safe.z, safe.y + safe.w), Color(0, 0, 0, 0.62))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_bg_sheet = false
			show_maps.call_deferred())
	content.add_child(dim)
	var pw := minf(content.size.x - 60.0, 1080.0)
	var cols := 4
	var gap := 12.0
	var tw := floorf((pw - 48.0 - gap * (cols - 1)) / cols)
	var th := floorf(tw * 9.0 / 16.0)
	var cap := UiKit.line_h(self, 13, true) + UiKit.line_h(self, 12) + 12.0
	var tile := Vector2(tw, th + cap + 12.0)
	var note := "For your matches here. In an online room its owner picks the background for everyone (the lobby's BACKGROUND). Campaign missions and training keep their own."
	var head := UiKit.line_h(self, 12, true) + UiKit.line_h(self, 26, true) + UiKit.text_h(self, note, 13, pw - 48.0) + 28.0
	var ph := minf(content.size.y - 24.0, head + 2.0 * tile.y + gap + 24.0)
	var pos := ((content.size - Vector2(pw, ph)) / 2.0).floor()
	var panel := UiKit.panel(self, pos, Vector2(pw, ph), faction)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ty := UiKit.title(self, pos.x + 24.0, pos.y + 18.0, "BATTLEFIELD / BACKGROUND", "PICK THE SKY.", faction, 26.0)
	_say(note, Vector2(pos.x + 24.0, ty + 2.0), 13, UiKit.MUTED, pw - 48.0)
	var mine := UiKit.backdrop_choice()
	var auto_i := absi(hash(str(sel.get("code", "")))) % Scenery.BATTLE_BACKDROPS.size()
	var opts := [["auto", auto_i, "AUTO", "This map's own"], ["rotate", -1, "ROTATE", "A new one every match"]]
	for i in range(Scenery.BATTLE_BACKDROPS.size()):
		opts.append([str(i), i, UiKit.backdrop_name(i, Scenery.BATTLE_BACKDROPS[i]), "%d / %d" % [i + 1, Scenery.BATTLE_BACKDROPS.size()]])
	var gy := pos.y + head
	for k in range(opts.size()):
		var o: Array = opts[k]
		var v: String = o[0]
		var tp := Vector2(pos.x + 24.0 + (k % cols) * (tw + gap), gy + (k / cols) * (tile.y + gap))
		var b := UiKit.btn(self, "", tp, tile, func():
			UiKit.save_backdrop_choice(v)
			_bg_sheet = false
			show_maps(), "selected" if v == mine else "secondary", faction)
		var idx: int = o[1]
		if idx >= 0:                                   # the picture (ROTATE: the five in a strip)
			var pic := TextureRect.new()
			pic.texture = UiKit.tex(Scenery.BATTLE_BACKDROPS[idx])
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pic.position = Vector2(6, 6)
			pic.size = Vector2(tw - 12.0, th)
			b.add_child(pic)
		else:
			var n := Scenery.BATTLE_BACKDROPS.size()
			var sw := (tw - 12.0) / n
			for j in range(n):
				var strip := TextureRect.new()
				strip.texture = UiKit.tex(Scenery.BATTLE_BACKDROPS[j])
				strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				strip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				strip.position = Vector2(6.0 + j * sw, 6)
				strip.size = Vector2(sw - 2.0, th)
				b.add_child(strip)
		var nm := UiKit.label(self, str(o[2]), 13, UiKit.accent(faction) if v == mine else UiKit.INK, true)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.position = Vector2(10, th + 12.0)
		nm.size = Vector2(tw - 20.0, UiKit.line_h(self, 13, true))
		b.add_child(nm)
		var sub := UiKit.label(self, str(o[3]), 12, UiKit.MUTED)
		sub.position = Vector2(10, th + 12.0 + nm.size.y)
		b.add_child(sub)
# --- end UI: BACKGROUND ---


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
	## 03 SETUP (screen system 05; Daniele 2026-09-28: the match here, the rivals in step 04): the map (its preview,
	## CHANGE -> BATTLEFIELD) and YOUR TEAM COLOUR on the left; your faction (CHANGE -> FACTION, its army preset ->
	## ARMIES), DIFFICULTY and the MATCH OPTIONS - LAST STAND, ABILITIES, HIDDEN COUNTS (moved here from SETTINGS) - on
	## the right; NEXT: RIVALS (04, show_seats: the PLAYERS mode, every seat's army, DEPLOY). Each choice is the variable
	## deploy() reads.
	_last_show = show_setup                  # a resize that changes the phone sizing rebuilds it (_fit)
	var modes := _modes_of(_selected_map())
	if not mode in modes:
		mode = modes[0]
	var area := shell_open("OOZE / SETUP", "play", show_maps, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "03 / SETUP", "SET THE MATCH.")
	var lw := floorf(w * 0.52)
	var rx := x + lw + 18.0
	var rw := w - lw - 18.0
	# the foot of the right column: NEXT: RIVALS
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var nt := "NEXT: RIVALS  →"
	var nw := maxf(UiKit.text_w(self, nt, 18, true) + 56.0, 200.0)
	UiKit.btn(self, nt, Vector2(content.size.x - x - nw, fy), Vector2(nw, 48), show_seats, "primary", faction, 18)
	var who := _enemy_seats().map(func(s):
		var p := str(rival_picks.get(s, "random"))
		return "ANY" if p == "random" else UiKit.NAMES[p])
	var nl := UiKit.label(self, "%s  ·  vs %s" % [MODE_NAMES.get(mode, mode), ", ".join(who)], 14, UiKit.MUTED)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size = Vector2(maxf(rw - nw - 14.0, 10.0), UiKit.line_h(self, 14))
	_shell_add(nl, Vector2(rx, fy + (bh - UiKit.line_h(self, 14)) / 2.0))
	# the left column: the map, YOUR TEAM COLOUR under it
	var hs := UiKit.tap_h(self, 44.0)
	var col_h := UiKit.line_h(self, 12, true) + 8.0 + hs + (UiKit.line_h(self, 13) + 6.0 if colour == "faction" else 0.0) \
			+ (UiKit.line_h(self, 13) + 10.0 if not mobile else 0.0)
	var col_y := area.end.y - 18.0 - col_h           # (the picked chip grows 12 %)
	_setup_map(Vector2(x, y), Vector2(lw, col_y - 16.0 - y))
	_setup_colours(Vector2(x, col_y), lw)
	# the right column: your faction, DIFFICULTY, MATCH OPTIONS
	var ry := y
	if not mobile:
		_shell_add(UiKit.label(self, "YOUR FACTION  ·  SEAT A", 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
		ry += UiKit.line_h(self, 12, true) + 6.0
	var card_h := maxf(76.0, UiKit.tap_h(self, 40.0) + 12.0)
	_setup_faction(Vector2(rx, ry), Vector2(rw, card_h))
	ry += card_h + 14.0
	_shell_add(UiKit.label(self, "DIFFICULTY", 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
	ry += UiKit.line_h(self, 12, true) + 6.0
	_difficulty(Vector2(rx, ry), rw)
	ry += UiKit.tap_h(self, 44.0) + 16.0
	_shell_add(UiKit.label(self, "MATCH OPTIONS", 12, UiKit.MUTED, true, 3), Vector2(rx, ry))
	ry += UiKit.line_h(self, 12, true) + 6.0
	# three switches in a row, or - where the longest name doesn't fit a third (phones) - two, and HIDDEN COUNTS under them
	var tgw := (rw - 20.0) / 3.0
	var one_row := UiKit.text_w(self, "HIDDEN COUNTS", 15) + UiKit.tap_h(self, 46.0) * 0.5 + 44.0 <= tgw
	if not one_row:
		tgw = (rw - 10.0) / 2.0
	_toggle("LAST STAND", Rules.last_stand, Vector2(rx, ry), Vector2(tgw, 46), func():
		Rules.last_stand = not Rules.last_stand
		main.keep_own_settings()                      # AUDIT FIX: yours, put back after a room's round
		show_setup())
	_toggle("ABILITIES", Rules.abilities_on, Vector2(rx + tgw + 10.0, ry), Vector2(tgw, 46), func():   # SKILLS 2.0: Alpha 11's match setting
		Rules.abilities_on = not Rules.abilities_on
		main.keep_own_settings()
		show_setup())
	var hp := Vector2(rx + (tgw + 10.0) * 2.0, ry) if one_row else Vector2(rx, ry + UiKit.tap_h(self, 46.0) + 8.0)
	_toggle("HIDDEN COUNTS", Rules.hide_enemy_counts, hp, Vector2(tgw, 46), func():
		Rules.hide_enemy_counts = not Rules.hide_enemy_counts   # (was SETTINGS > GAME > ENEMY COUNTS)
		main.keep_own_settings()
		show_setup())
	ry = hp.y + UiKit.tap_h(self, 46.0) + 8.0
	nl.visible = ry <= fy - 4.0 or ry <= nl.position.y        # the foot's "mode · vs ..." line only where it has room
	if not mobile:                                    # the phone skips the recap to save room
		var tip := UiKit.label(self, "LAST STAND: the map collapses ring by ring late in the match.  ABILITIES off: no skills.  "
				+ "HIDDEN COUNTS: no unit numbers on enemy nodes, so you scout.", 13, UiKit.MUTED)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(rw, 0)
		if ry + UiKit.text_h(self, tip.text, 13, rw) < fy - 8.0:
			_shell_add(tip, Vector2(rx, ry))


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
	tex.texture = UiKit.map_thumb(MapPool.thumb(str(sel.get("code", ""))))   # the map alone, name + tags beside it
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
	var y := hy + hs + (10.0 if not mobile else 6.0)
	if Rules.colour_blind():                           # UI: COLOUR-BLIND MODE decides the match's colours
		_shell_add(UiKit.label(self, "COLOUR-BLIND MODE: the match picks colour-blind-safe colours", 13, Color("ffd15c")), Vector2(pos.x, y))
		y += UiKit.line_h(self, 13) + 6.0
	elif colour == "faction":                          # a one-line caption while FACTION is picked
		_shell_add(UiKit.label(self, "Every player in their faction's colour", 13, Color("ffd15c")), Vector2(pos.x, y))
		y += UiKit.line_h(self, 13) + 6.0
	if not mobile:
		var n := UiKit.label(self, "Team modes: one hue per team, light and dark. FACTION: every seat in its own faction colour (Alpha 11).", 13, UiKit.MUTED)
		n.clip_text = true
		n.size = Vector2(width, UiKit.line_h(self, 13))
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
	var sub := "%s  ·  SEAT A" % UiKit.SUBS[faction]
	if UiKit.text_w(self, sub, 13) > tw:                 # a narrow phone column (the iPhone SE): the name alone
		sub = UiKit.SUBS[faction]
	var lines := [[UiKit.NAMES[faction], 17, acc, true], [sub, 13, UiKit.MUTED, false]]
	if not Rules.abilities_on:
		lines.append(["ABILITIES OFF", 12, UiKit.DIM, false])
	elif eff["swapped"] != "":
		lines.append(["NO RELAYS: %s" % ArmyPresets.skill_name(eff["map"]).to_upper(), 12, Color("ffd15c"), false])
	var total := 0.0
	for ln in lines:
		total += UiKit.line_h(self, ln[1], ln[3])
	var ly := pos.y + (dims.y - total) / 2.0
	for i in range(lines.size()):
		var ln: Array = lines[i]
		var l := UiKit.label(self, ln[0], ln[1], ln[2], ln[3])
		l.clip_text = true
		l.size = Vector2(maxf(10.0, tw), UiKit.line_h(self, ln[1], ln[3]))
		var ex := 0.0
		if i == 0:                                    # the race emblem before the name
			ex = l.size.y + 6.0
			UiKit.emblem_rect(self, faction, Vector2(tx, ly), l.size.y)
			l.size.x = maxf(10.0, tw - ex)
		_shell_add(l, Vector2(tx + ex, ly))
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
		UiKit.emblem_badge(b, f, s * 0.36)
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
	## 04 RIVALS (screen system 29; Daniele 2026-09-28: the step after SETUP): PLAYERS (the map's modes), then every seat -
	## you in seat A (your faction, CHANGE -> FACTION), each AI seat as ally or rival (its team in team modes) with its
	## army pick; DEPLOY.
	_last_show = show_seats                  # a resize that changes the phone sizing rebuilds it (_fit)
	var sel := _selected_map()
	var modes := _modes_of(sel)
	if not mode in modes:
		mode = modes[0]
	var area := shell_open("OOZE / RIVALS", "play", show_setup, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "04 / RIVALS", "PICK YOUR RIVALS.")
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
	var dw := maxf(UiKit.text_w(self, "DEPLOY  →", 18, true) + 56.0, 170.0)
	UiKit.btn(self, "DEPLOY  →", Vector2(content.size.x - x - dw, fy), Vector2(dw, 48), deploy, "primary", faction, 18)
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
		UiKit.tag(self, "PLAYER" if s == "A" else "AI", p + Vector2(cw - 16.0 - UiKit.text_w(self, "PLAYER" if s == "A" else "AI", 14, true) - 46.0, 12.0), faction, false)
		var py := ry + UiKit.line_h(self, 17, true) + 10.0
		if s == "A":
			_shell_add(_cutout(faction, Vector2.ZERO, Vector2(ph, ph)), p + Vector2(16, py))
			var nl := UiKit.line_h(self, 15, true)
			UiKit.emblem_rect(self, faction, p + Vector2(16.0 + ph + 12.0, py + (ph - nl) / 2.0), nl)
			_shell_add(UiKit.label(self, "%s  ·  %s" % [UiKit.NAMES[faction], UiKit.SUBS[faction]], 15, UiKit.INK, true),
					p + Vector2(16.0 + ph + 12.0 + nl + 6.0, py + (ph - nl) / 2.0))
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
			else "Online rooms run in the browser build: open https://oozesyndicate.com", Vector2(0, y), 13,
			UiKit.DIM if web else UiKit.STAR, w)
	_column_end(host, n0, y, true)
	# JOIN A FRIEND: a plain panel, never scrolled, so the web's native code field stays exactly on its frame
	var jx := x + cw + gap
	var jp := UiKit.panel(self, Vector2(jx, top), Vector2(cw, ch), shell_f)
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
	var both := minf(ch, maxf((host["panel"] as Control).size.y, join.position.y + join.size.y + 18.0 - top))   # one height for the pair
	jp.size.y = both
	(host["panel"] as Control).size.y = both
	(host["scroll"] as Control).size.y = both - 24.0
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
		art.texture = UiKit.tex(UiKit.hero_path(f))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2.ONE * tile * 0.1
		art.size = Vector2.ONE * tile * 0.8
		art.modulate = Color.WHITE if picked else Color(1, 1, 1, 0.72)
		b.add_child(art)
		UiKit.emblem_badge(b, f, tile * 0.34)
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
	UiKit.back_link(self, content.size.x - x, ty, _leave_room, "LEAVE ROOM")   # UI (0.22.1): a real button (Daniele)
	# the foot: who is in and the room's status at the left, DEPLOY (the host) at the right
	var bh := UiKit.tap_h(self, 50.0)
	var fy := area.end.y - bh - 12.0
	var rx := content.size.x - x
	if host:
		var go := UiKit.btn(self, "DEPLOY  →", Vector2(rx - 240.0, fy), Vector2(240, 50), func(): Net.start_match(), "primary", shell_f, 18)
		go.disabled = not Net.can_start()
		rx = go.position.x - 16.0
		# READY: the owner's DEPLOY waits for every player's READY
		var waiting := Net.present_ids().filter(func(id): return not Net.is_ready(int(id))).size()
		if waiting > 0:
			var ww := "WAITING FOR %d PLAYER%s" % [waiting, "" if waiting == 1 else "S"]
			var wwid := UiKit.text_w(self, ww, 14, true)
			_say(ww, Vector2(rx - wwid, fy + (bh - UiKit.line_h(self, 14, true)) / 2.0), 14, UiKit.STAR, 0.0, true)
			rx -= wwid + 16.0
		# --- end READY ---
	else:
		# READY (Alpha 21, ooze20-net-6): a guest's READY / UN-READY where "the host deploys when ready" was; ready locks
		# your faction, colour, team and army until you un-ready. 🧩 UI may restyle it (handoffs/🧩 UI.md).
		var me_ready := Net.is_ready(Net.local_id())
		var rt := "UN-READY" if me_ready else "READY  ✓"
		var rw := maxf(UiKit.text_w(self, rt, 18, true) + 56.0, 200.0)
		var rb := UiKit.btn(self, rt, Vector2(rx - rw, fy), Vector2(rw, 50), func():
			_lobby_note = ""
			Net.set_ready(not Net.is_ready(Net.local_id())), "secondary" if me_ready else "primary", shell_f, 18)
		rb.disabled = Net.active or not Net.connected
		rx = rb.position.x - 16.0
		var hw := "THE HOST DEPLOYS WHEN EVERYONE IS READY" if me_ready else "PRESS READY WHEN YOUR PICKS ARE SET"
		var hwid := minf(UiKit.text_w(self, hw, 13, true), rx - x - 120.0)
		_clip(hw, Vector2(rx - hwid, fy + (bh - UiKit.line_h(self, 13, true)) / 2.0), 13, UiKit.MUTED, hwid, true)
		rx -= hwid + 16.0
		# --- end READY ---
	var line := "%d / %d PLAYERS" % [Net.roster.size(), Net.slots()] + (("  ·  " + Net.status) if Net.status != "" else "")
	if _lobby_note != "":                              # READY: the host's last notice (e.g. "Settings changed - press READY again")
		line = _lobby_note.to_upper() + "  ·  " + line
	_say(line, Vector2(x, fy + maxf(0.0, (bh - UiKit.text_h(self, line, 13, rx - x)) / 2.0)), 13, UiKit.STAR if _lobby_note != "" else UiKit.INK, rx - x)
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
	army.disabled = Net.active or Net.ready_locked()   # READY: a ready player's army is locked
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
			var tb0 := content.get_child_count()
			y += _team_button(int(g[0]), colours, Vector2(0, y), w) + 6.0
			if Net.ready_locked():                     # READY: no JOIN while ready
				_ready_lock(tb0)
		for i in g[1]:
			y += _lobby_row(i, by_slot.get(i, -1), colours, Vector2(0, y), w, host and team_mode) + 6.0
		if team_mode:
			y += 8.0
	y += 10.0
	y += _say("YOUR FACTION", Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	var pk0 := content.get_child_count()               # READY: the picks below are locked while you're ready
	y += _faction_row(Vector2(0, y), 50.0) + 14.0
	var mine := Net.colour_of(Net.local_id())
	y += _say("YOUR COLOUR" + (("  ·  " + mine.to_upper()) if mine != "" else ""), Vector2(0, y), 12, UiKit.MUTED, 0.0, true, 2) + 8.0
	y += _colour_row(Vector2(0, y), w) + 12.0
	if Rules.colour_blind():                           # UI: your screen recolours the match (the room keeps its hues)
		y += _say("COLOUR-BLIND MODE is on: in the match your screen shows colour-blind-safe colours.", Vector2(0, y), 13, UiKit.STAR, w) + 8.0
	if Net.ready_locked():
		_ready_lock(pk0)
		y += _say("You're READY: your picks are locked. UN-READY to change them.", Vector2(0, y), 13, UiKit.STAR, w) + 8.0
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
	# UI (Daniele 2026-09-28): the room owner's BACKGROUND for everyone - AUTO / ROTATE / each of the five, in turn
	var bgs := ["auto", "rotate"]
	for i in range(Scenery.BATTLE_BACKDROPS.size()):
		bgs.append(str(i))
	var bgn := _backdrop_short(Net.room_backdrop) if not Net.room_backdrop.is_valid_int() \
			else UiKit.backdrop_name(int(Net.room_backdrop), Scenery.BATTLE_BACKDROPS[int(Net.room_backdrop)])
	var bgb := UiKit.btn(self, "BACKGROUND  ·  %s" % bgn, Vector2(0, y), Vector2(w, 44), func():
		Net.set_room_backdrop(bgs[(bgs.find(Net.room_backdrop) + 1) % bgs.size()])
		show_lobby(), "secondary", shell_f, 14)
	bgb.disabled = not host
	y += bgb.size.y + 10.0
	if host and not Net.can_start():
		y += _say("DEPLOY opens when every seat is filled (or EMPTY SEATS: AI) and every player is READY.", Vector2(0, y), 13, UiKit.MUTED, w)
	_column_end(right, n0, y)


func _leave_room() -> void:
	Net.leave()
	main.restore_own_settings()                        # AUDIT FIX: a round's settings don't outlive the room
	show_online()


# --- READY (Alpha 21, ooze20-net-6): the lobby's ready lock and the host's notices ---
func _ready_lock(from: int) -> void:
	## Grey every button built since child `from` (a ready player's picks; the host refuses them anyway).
	for i in range(from, content.get_child_count()):
		var c := content.get_child(i)
		for b in [c] + c.find_children("*", "BaseButton", true, false):
			if b is BaseButton:
				(b as BaseButton).disabled = true


func _on_lobby_note(msg: String) -> void:
	if _page == "lobby" and not Net.active:
		_lobby_note = msg
		show_lobby()
# --- end READY ---


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
		art.texture = UiKit.tex(UiKit.hero_path(f))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2(tx, 7)
		art.size = Vector2(ts, ts)
		r.add_child(art)
		title_text = ("YOU / " if id == Net.local_id() else "") + Net.name_of(id).to_upper() + "  ·  " + str(UiKit.NAMES[f])   # NAMES (net-7): the player's name, then the faction
		var words := ["HOST  ·  DEPLOYS" if id == Net.room_owner or (id == 1 and not Net.server_hosted()) else "JOINED"]   # READY: DEPLOY is the owner's ready
		if Net.is_away(id):
			words.append("RECONNECTING")
			sub_col = UiKit.STAR
		if picked:
			words.append("PICKED: MOVE ON A TEAM")
			sub_col = UiKit.accent(shell_f)
		if id != Net.room_owner and not Net.is_away(id):   # READY: who the room waits for, in words and the seat's colour
			if Net.is_ready(id):                           # a READY chip in the seat's colour, a drawn tick in it
				var tagw := UiKit.text_w(self, "READY", 13, true) + 5.0 * 2.0 + 44.0
				var th := UiKit.line_h(self, 13, true) + 12.0
				var chip := Panel.new()
				chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chip.add_theme_stylebox_override("panel", UiKit.sb(Color(col, 0.2), col, 2, 4))
				chip.position = Vector2(right - tagw, (h - th) / 2.0)
				chip.size = Vector2(tagw, th)
				r.add_child(chip)
				var tick := MatchScreens.Mark.new()
				tick.kind = "check"
				tick.color = col
				tick.position = Vector2(10.0, (th - 16.0) / 2.0)
				tick.size = Vector2(16, 16)
				chip.add_child(tick)
				var tag := UiKit.label(self, "READY", 13, UiKit.INK, true, 2)
				tag.position = Vector2(32.0, (th - UiKit.line_h(self, 13, true)) / 2.0)
				chip.add_child(tag)
				right -= tagw + 12.0
			else:
				words.append("NOT READY")
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
	var ex := 0.0
	if id >= 0:                                        # the race emblem before the player's name
		ex = l1 + 6.0
		r.add_child(UiKit.emblem_node(str(Net.roster[id]["faction"]), l1, Vector2(lx, ty)))
	for part in [[title_text, 16, UiKit.INK, true, ty, ex], [sub, 13, sub_col, false, ty + l1, 0.0]]:
		var l := UiKit.label(self, part[0], part[1], part[2], part[3])
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.position = Vector2(lx + part[5], part[4])
		l.size = Vector2(maxf(10.0, right - lx - part[5]), UiKit.line_h(self, part[1], part[3]))
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
	_speed_step()
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
	_place_backdrop()
	var s := minf(vp.x / 1280.0, vp.y / 720.0)
	content.size = Vector2(1280, 720)
	content.scale = Vector2(s, s)
	content.position = (vp - Vector2(1280, 720) * s) / 2.0
	if _shell:                                        # UI: a shell page spans the whole screen (bars edge to edge),
		var ins := UiKit.safe_insets(vp)              # its controls inside the notch / home-indicator bands
		safe = ins / s                                # (in page units: the bars paint their backs out into them)
		content.size = (vp - Vector2(ins.x + ins.z, ins.y + ins.w)) / s
		content.position = Vector2(ins.x, ins.y)
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
