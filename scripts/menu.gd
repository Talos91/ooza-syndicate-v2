class_name Menu
extends CanvasLayer
## Alpha 11's front menu, ported page for page (Daniele: "I want the damn menu as for Alpha 11"):
## the same backdrop art (the 43B room plate, ARMIES-PLATE), neon-cut frames (neon_panel.gd), ui-kit buttons
## per faction (ui_skin.gd), stepper strip, wordmark, Russo One headings, and the same coordinates
## - Alpha 11 laid out on a 1672x941 canvas, ours is 1280x720, so everything is scaled by K.
## MAIN -> 01 FACTION (portrait / stats + trait / abilities / faction tabs) -> 02 BATTLEFIELD
## (3D thumbnails + preview) -> 03 SETUP (players, your colour, your faction, rival, difficulty,
## Last Stand) -> DEPLOY. OPTIONS holds the match switches (Last Stand,
## enemy counts, detail). ONLINE -> CREATE ROOM / JOIN ROOM ->
## the room lobby (players, teams, faction, colour, map, PLAYERS, Last Stand) -> DEPLOY by
## the host (Net, through the room server). TUTORIAL (TUTORIAL-DESIGN.md §7): the nine lesson rows
## (TutorialPage, TutorialDirector's table and progress), CONTINUE = the first lesson not done.
## ARMIES (0.18.7, SKILLS 2.0): the army presets - per faction its fixed ultimate plus 1 active and 1 map skill
## picked from the shared pools (ArmyPresets, saved on the device). 01 FACTION shows the preset; 03 SETUP and
## the lobby carry ABILITIES ON / OFF; DEPLOY and the room send your preset as the match loadout.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const K := 1280.0 / 1672.0
const NAMES := {"vex": "VEX\nR&D", "null": "NULL\nFINANCE", "bloom": "BLOOM\nPEOPLE & CULTURE", "ember": "EMBER\nOPERATIONS", "solar": "AEGIS\nCOMPLIANCE"}

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
const MODES_OFFERED := ["1v1"]   # OOZE 3.0 (Daniele 2026-11-27): BRAWL 1v1 only; 2v2 / FFA code stays until WP6, never offered
const MODE_NAMES := {"1v1": "1 V 1", "2v2": "2 V 2", "FFA3": "FFA 3", "FFA4": "FFA 4"}   # max 4 seats: FFA5 / 3v3 / 2v2v2 deleted 2026-11-23 (Daniele 2026-11-18)
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
var _den: MenuDen                                 # HOME's 35C2 overlord painting + TV loop (menu_den.gd)
var _backdrop_ax := 0.5                           # the backdrop's horizontal anchor when it crops
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
var _map_page := -1                                # MAP PICKER: the open page of 10 (-1: the picked map's page)
# map filters on 02 BATTLEFIELD (Daniele, 0.18.6: "add in game filters for maps like 1v1 2v2 ffa etc"): players
# (a mode the map offers) and type (the map's group); static, so they survive a trip through the match
static var map_filter_mode := "all"
static var _guide_tab := "basics"                  # GUIDE: the open tab
static var map_filter_type := "all"
# MAPS 5.0 (📐 Architect, 2026-09-30): the pool is only the N- maps now (MapPool.POOL_GROUPS), all group "new" -
# the old BRAWL / SIEGE / CORE / ALPHA 11 / TRAINING groups never match, so TYPE relabels by each map's own "size"
# (XS / S / M / L, baked by the map builder) instead.
const MAP_TYPES := ["all", "xs", "s", "m", "l"]
const MAP_TYPE_NAMES := {"all": "ALL SIZES", "xs": "TINY", "s": "SMALL", "m": "MEDIUM", "l": "LARGE", "none": "OTHER"}
var _chat_btn: Button
var _chat_t := 0.0
var _move_pick := -1                               # host, team modes: the player picked to MOVE to a team
var _lobby_note := ""                              # READY: the host's last notice in the lobby ("Settings changed - ...")
const HUE_NAMES := ["red", "green", "blue", "gold", "purple", "cyan", "rose", "orange"]   # Rules.HUES, lobby order
var _army := ""                                    # ARMIES: the faction whose preset is open
var _army_back := Callable()                       # ARMIES: the page it was opened from
var _tut_page: TutorialPage                        # TUTORIAL: the lesson page (its own canvas, over the backdrop)
var _join_open := false                            # UX pass: HOME's JOIN WITH CODE sheet is up
var _draft := {}                                   # UX pass: the setup as it was when a picker opened (its BACK puts it back)
var _map_list := ""                                # MAP PICKER: "" (every map), "recent" or "favourites"

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
	_den = MenuDen.new()                              # (behind the backdrop: it draws the TV's picture into the painting's hole)
	add_child(_den)
	_backdrop = TextureRect.new()                     # full-screen art behind the scaled page
	_backdrop.texture = UiKit.tex(Armies43.DIR + "ARMIES-PLATE.jpg")   # 45B: the room plate (the old sky-city art is gone)
	_backdrop_art = _backdrop.texture
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
	if not Net.in_room() and Net.status == "":         # UX pass: HOME's PLAY and MATCH SETUP start from the last DEPLOY
		_load_last_setup()
	if not mode in MODES_OFFERED:                      # 3.0: an old setup's 2v2 / FFA falls back to 1v1
		mode = MODES_OFFERED[0]
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
	_stage = null
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


func portrait(f: String, pos: Vector2, dims: Vector2, neon := Color(0, 0, 0, 0)) -> TextureRect:
	## OOZE HEROES 2026-11-17: the faction's ooze hero (UiKit.hero_path) with its neon line in the seat colour.
	if Rules.FACTIONS.has(f):
		var r := _cutout(f, pos, dims)
		if neon.a > 0.0 and r.get_child_count() > 0:
			(r.get_child(0) as TextureRect).modulate = Color(neon, 1.0)
		content.add_child(r)
		return r
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
	label_at(Rules.version_label(), P(1480, 34), 16, Color("839da9"))


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
		_den.hide_den()
		_backdrop_ax = 0.5
		var bg := UiKit.tex(Armies43.DIR + "ARMIES-PLATE.jpg")   # GAP-LIST §0: one room plate behind every menu (the remake)
		if bg != null:
			_backdrop.texture = bg
		_backdrop.modulate = Color(0.9, 0.9, 0.9)
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
	if UiKit.compact(self):                            # iOS (Safari's 320-340 pt): kicker and headline share one row when
		var hs := size * 0.8                           # they fit beside the title row's own buttons
		var kw := UiKit.text_w(self, kicker.to_upper(), 12, true) + kicker.length() * 3.0
		var hw := UiKit.text_w(self, headline.to_upper(), hs, true)
		if kw + 18.0 + hw <= content.size.x * 0.62 - x:
			var ty := area.position.y + 10.0
			var hl := UiKit.label(self, headline.to_upper(), hs, UiKit.INK, true)
			var kl := UiKit.label(self, kicker.to_upper(), 12, UiKit.COPPER, true, 3)
			var rowh := UiKit.line_h(self, hs, true)      # (font measures: a label off the tree reports its default size)
			UiKit.band(self, Rect2(x - 14.0, ty - 6.0, kw + 18.0 + hw + 32.0, rowh + 12.0))
			_shell_add(kl, Vector2(x, ty + (rowh - UiKit.line_h(self, 12, true)) / 2.0 + 2.0))
			_shell_add(hl, Vector2(x + kw + 18.0, ty))
			if shell_back.is_valid() and not shell_slim:
				UiKit.back_link(self, content.size.x - x, ty, shell_back)
			return ty + rowh + 10.0
	var y := UiKit.title(self, x, area.position.y + (10.0 if shell_slim else 18.0), kicker, headline, shell_f,
			size * (0.8 if shell_slim or UiKit.compact(self) else 1.0))
	if shell_back.is_valid() and not shell_slim:
		UiKit.back_link(self, content.size.x - x, area.position.y + 20.0, shell_back)
	return y + 14.0


func shell_raise() -> void:
	## Keeps the bars over anything a page drew after shell_open().
	if is_instance_valid(top_bar):
		content.move_child(top_bar, -1)
	if is_instance_valid(nav_bar) and nav_bar.get_parent() == content:
		content.move_child(nav_bar, -1)                # (ARMIES SPLIT) the tab bar is never under a page's controls
	if is_instance_valid(nav_bar):
		content.move_child(nav_bar, -1)


func _on_tab(id: String) -> void:
	match id:
		"home":
			show_main()
		"play":                                        # (no PLAY tab since the UX pass; kept for old callers)
			show_setup()
		"armies":
			show_armies(faction, show_main)
		"campaign":                                    # UI (Daniele, 0.22.0): the tab opens every campaign first; the
			show_chapters()                            # city map opens once you pick one (show_campaign)
		"profile":                                     # UI (0.22.x): PROFILE is a tab of its own now, not a meta page
			show_profile()
		"guide":                                       # 2026-11-05: the quick guide (HELP) is a tab
			show_help()


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
	_backdrop.position = Vector2((vp.x - sz.x) * _backdrop_ax, (vp.y - sz.y) * _backdrop_ay)
	if _den != null:
		_den.place(_backdrop)


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


func _redraw() -> void:
	## Rebuild the page on screen (a pick inside a page or a sheet keeps you where you are).
	if _last_show.is_valid():
		_last_show.call()


func _load_last_setup() -> void:
	var d := UiKit.last_setup()
	if d.is_empty():
		return
	var mp := str(d.get("map", ""))
	if maps.any(func(x): return x["path"] == mp):
		map_path = mp
	var md := str(d.get("mode", mode))
	if md in _modes_of(_selected_map()):
		mode = md
	var lv := str(d.get("ai", ai_level))
	if Rules.AI_LEVELS.has(lv):
		ai_level = lv
	var cl := str(d.get("colour", colour))
	if COLOUR_NAMES.has(cl):
		colour = cl
	var rv = d.get("rivals", {})
	if rv is Dictionary:
		rival_picks = (rv as Dictionary).duplicate()


func _save_last_setup() -> void:
	UiKit.save_last_setup({"map": map_path, "mode": mode, "ai": ai_level, "colour": colour, "rivals": rival_picks.duplicate()})
	var recent := UiKit.map_list("recent")
	recent.erase(map_path)
	recent.push_front(map_path)
	UiKit.save_map_list("recent", recent.slice(0, 8))


func _setup_summary() -> Array:
	## PLAY LAST SETUP's two lines: "1 V 1  ·  KNOT" and "VS STANDARD AI  ·  VEX".
	var modes := _modes_of(_selected_map())
	if not mode in modes:                              # the map's own modes (a saved or default mode it lacks)
		mode = str(modes[0])
	var md := mode
	var mname := str(_selected_map().get("name", "")).replace("*", "").to_upper()
	var n := _enemy_seats().size()
	var foes := ("VS %s AI" % ai_level.to_upper()) if n <= 1 else ("%d AI  ·  %s" % [n, ai_level.to_upper()])
	return ["%s  ·  %s" % [MODE_NAMES.get(md, md), mname], "%s  ·  %s" % [foes, UiKit.NAMES[faction]]]


func _pick(page: Callable) -> void:
	## Open a picker from MATCH SETUP: remember the setup, so the picker's BACK cancels and CHOOSE / SAVE keeps.
	_draft = {"faction": faction, "map": map_path, "mode": mode, "ai": ai_level, "colour": colour, "rivals": rival_picks.duplicate(),
			"last_stand": Rules.last_stand, "abilities": Rules.abilities_on, "hidden": Rules.hide_enemy_counts,
			"filter_mode": map_filter_mode, "filter_type": map_filter_type}
	page.call()


func _open_maps() -> void:
	## MATCH SETUP's map -> the MAP PICKER, filtered to the chosen mode (board 04).
	_pick(func():
		map_filter_mode = "all" if Net.in_room() else mode
		_map_list = ""
		_map_scroll = 0
		_map_page = -1
		show_maps())


func _cancel_pick() -> void:
	## A picker's BACK: the setup as it was, then MATCH SETUP (or the room).
	if not _draft.is_empty():
		faction = str(_draft["faction"])
		main.SEAT_FACTIONS[main.HUMAN] = faction
		map_path = str(_draft["map"])
		mode = str(_draft["mode"])
		ai_level = str(_draft["ai"])
		colour = str(_draft["colour"])
		rival_picks = (_draft["rivals"] as Dictionary).duplicate()
		map_filter_mode = str(_draft["filter_mode"])
		map_filter_type = str(_draft["filter_type"])
		if Rules.last_stand != bool(_draft["last_stand"]) or Rules.abilities_on != bool(_draft["abilities"]) \
				or Rules.hide_enemy_counts != bool(_draft["hidden"]):
			Rules.last_stand = bool(_draft["last_stand"])
			Rules.abilities_on = bool(_draft["abilities"])
			Rules.hide_enemy_counts = bool(_draft["hidden"])
			main.keep_own_settings()
	_draft = {}
	_bg_sheet = false
	_back_to_setup()


func _back_to_setup() -> void:
	_draft = {}
	_bg_sheet = false
	_lobby_sheet = ""
	if Net.in_room():
		show_lobby()
	else:
		show_setup()


const HOME_CREATURE := {                         # where each FINAL wallpaper's creature stands: [centre x, feet y]
	"vex": Vector2(0.73, 0.86), "null": Vector2(0.76, 0.83), "bloom": Vector2(0.71, 0.84),
	"ember": Vector2(0.77, 0.88), "solar": Vector2(0.71, 0.86),
}


func show_main() -> void:
	## HOME = the launch pad (Alpha 24 step 3, UX board 02a, Daniele 2026-11-04): the headline and CHALLENGES at the top, a
	## row of tiles at the foot - ONLINE (HOST ROOM straight into a room; JOIN WITH CODE: the code sheet over HOME), CAMPAIGN
	## (the next mission, CONTINUE), TRAINING / HOW TO PLAY, and PLAY LAST SETUP (its summary, CHANGE -> MATCH SETUP, PLAY =
	## DEPLOY with the last setup: one tap to a match). The PLAY hub page is gone.
	if _last_show != show_main:                 # HOME just opened (a rebuild of HOME keeps its words): the next pair
		_home_words = _next_words(_home_words)
	_last_show = show_main                  # a resize that changes the phone sizing rebuilds it (_fit)
	if _join_open:                                     # 45B: JOIN is a page of its own (the code field's page "online")
		_code_box = null
		_join_sheet()
		return
	var hero := faction
	var area := shell_open("OOZE / HOME", "home", Callable(), hero)
	_is_main = true
	if _join_open:
		_page = "online"                               # the code field's page (Net changes rebuild HOME with the sheet)
	_code_box = null
	if _backdrop:                                      # 35C2 (Daniele 2026-11-15): one painting for every setting and faction
		_den.show_den(_backdrop)
		_backdrop_ax = _den.backdrop_anchor_x()
		_backdrop_ay = 0.0                             # (crop from the floor and tail, never the ceiling: the TV stays under the top bar)
		_place_backdrop()
	_home_column(area, hero)
	shell_raise()
	if _install_available():
		_install_button(Vector2(_home_install_x, _home_install_y))
	if _install_guide_open:
		_install_guide_panel()


## HOME's rotating words (Daniele 2026-11-15, designer 9): [tagline, title line 1, title line 2], one pair each time HOME opens.
const HOME_WORDS := [
	["DISAPPOINT THE OVERSEER ONCE.", "HIT QUOTA.", "OR BECOME IT."],
	["THE OVERSEER LOVES A GOOD WAR.", "MORE GOO.", "FEWER COWORKERS."],
	["PRODUCTIVITY IS MANDATORY.", "OUTPRODUCE.", "OUTOOZE."],
	["GROWTH AT ANY COST. MOSTLY THEIRS.", "SEIZE SUPPLY.", "PLEASE THE BOSS."]]
var _home_words := -1


func _next_words(prev: int) -> int:
	var n := randi() % HOME_WORDS.size()
	if n == prev:
		n = (n + 1) % HOME_WORDS.size()
	return n


func _home_column(_area: Rect2, hero: String) -> void:
	## HOME = the remake (Daniele 11-18, 43B-five-screen-remake/HOME; 45B parts, sizes.json HOME): over the Overlord lounge,
	## the cyan tagline + two-line headline without a box, FULLSCREEN (QUIT on desktop) + the version under it, three
	## HERO-CABINET cards at the bottom left (PLAY VS AI: CHANGE / PLAY ->, ONLINE: HOST / JOIN, CAMPAIGN: COMING SOON) and
	## CHALLENGES over TRAINING · COMING SOON in a column at the bottom right, so the Overlord and the TV stay in view.
	var st := Kit45.Stage.new()
	st.setup(self, content.size)
	content.add_child(st)
	_stage = st
	var words: Array = HOME_WORDS[maxi(_home_words, 0)]
	st.txt(str(words[0]), 18, 48, 330, 14, 9.0, Kit45.CYAN_KICK, false)
	st.txt("%s
%s" % [words[1], words[2]], 15, 64, 380, 64, 27.0, UiKit.INK, true, 0, 2)
	var web := OS.has_feature("web")
	var fb := st.key("KEY-SMALL", 17, 134, 96, 24, "FULLSCREEN" if web else "QUIT", func():
		if OS.has_feature("web"):
			FullscreenGate.request()
		else:
			get_tree().quit())
	fb.size_pt = 12.5
	st.txt(Rules.version_label(), 122, 136, 160, 20, 10.0, UiKit.MUTED, false)
	var ip := st.P(17, 166)
	_home_install_x = ip.x
	_home_install_y = ip.y                             # (INSTALL THE GAME: under FULLSCREEN at the left, never on the TV)
	# PLAY VS AI
	var sm := _setup_summary()
	_home_card(st, 15, 174, "PLAY VS AI", str(sm[0]), str(sm[1]))
	st.key("KEY-SMALL", 25, 300, 60, 22, "CHANGE", show_setup)
	st.key("PRIMARY-WIDE", 91, 300, 88, 22, "PLAY  →", deploy, true)
	# ONLINE
	_home_card(st, 197.5, 154, "ONLINE", "PLAY FRIENDS", "Room code, up to 4.")   # designer 11: one line at the floor (no ellipsis)
	if not Net.rejoin.is_empty():                      # dropped out of a room: back into the same seat
		var rb := st.key("KEY-SMALL", 208, 300, 134, 22, "RECONNECT %s" % str(Net.rejoin["code"]), func():
			ArmyPresets.send_to(Net, str(Net.rejoin.get("faction", faction)))
			Net.reconnect()
			show_lobby(), true, not web)
		rb.size_pt = 12.5
	else:
		var hb := st.key("KEY-SMALL", 208, 300, 60, 22, "HOST", func():
			ArmyPresets.send_to(Net, faction)
			Net.host_room(faction)
			show_lobby(), false, not web)
		var jb := st.key("KEY-SMALL", 278, 300, 64, 22, "JOIN", func():
			_join_open = true
			Net.status = ""
			_code_error = ""
			show_main(), false, not web)
		if not web:
			hb.tooltip_text = "Online rooms run in the browser build"
			jb.tooltip_text = hb.tooltip_text
	# CAMPAIGN
	var cf := _hub_faction()
	if Campaign.ENABLED and cf != "":
		var nxt := Campaign.next_open(cf)
		_home_card(st, 360, 154, "CAMPAIGN", str(UiKit.NAMES[cf]), "★ %d / %d" % [Campaign.stars_total(cf), Campaign.stars_max(cf)])
		st.key("KEY-SMALL", 370, 300, 134, 22, "CONTINUE" if nxt != "" else "REPLAY", func():
			_hub_f = cf
			show_campaign())
	else:                                              # off for now (Daniele 2026-11-15): the card stays, COMING SOON
		_home_card(st, 360, 154, "CAMPAIGN", "THE CITY", "")
		st.key("KEY-SMALL", 370, 300, 134, 22, "COMING SOON", Callable(), false, true)
	# CHALLENGES over TRAINING (the right column)
	var ready_n := Progression.claimable()
	var ct := "CHALLENGES" + (" · %d TO CLAIM" % ready_n if ready_n > 0 else "")
	st.key("KEY-SMALL", 650, 266, 147, 27, ct, show_challenges, ready_n > 0)
	var tl := "TRAINING  →" if TutorialDirector.ENABLED else "TRAINING"   # Daniele 11-18: "just make it grayed" (DISABLED)
	st.key("KEY-SMALL", 650, 300, 147, 27, tl, show_tutorial, false, not TutorialDirector.ENABLED)


var _stage: Kit45.Stage                            # the open page's remake canvas (Kit45), null on older pages


func _home_card(st: Kit45.Stage, x: float, w: float, kicker: String, title: String, sub: String) -> void:
	## One HOME card: the 78 pt HERO-CABINET, its kicker (cyan small caps), title (cream) and caption (muted).
	st.piece("HERO-CABINET", x, 251, w, 78)
	st.txt(kicker, x + 10, 254, w - 20, 14, 8.0, Kit45.CYAN_KICK)
	st.txt(title, x + 10, 268, w - 20, 16, 12.0, UiKit.INK)
	if sub != "":
		st.txt(sub, x + 10, 283, w - 20, 14, 8.0, UiKit.MUTED)


func _col_back(r: Rect2) -> void:
	## HOME's column rows sit on an (almost) opaque dark plate: the painting never shows through a button (designer 8).
	## Note 3 (Daniele 11-16: CHALLENGES / TRAINING "not overlaid properly, background wrong"): the plate is the chamfered
	## M-E cabinet, a margin wider than the keys, never a square dark box.
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", MenuSkin.plate(0.92))
	p.position = r.position - Vector2(10, 10)
	p.size = r.size + Vector2(20, 20)
	content.add_child(p)


var _home_install_x := 0.0
var _home_install_y := 0.0                         # HOME: INSTALL THE GAME goes under the top-right buttons


func _home_campaign(r: Rect2, pad: float, bh: float) -> void:
	## CAMPAIGN (Daniele 2026-11-05: a tile of its own, the tab left the bar): the campaign on show, its stars, CONTINUE
	## (its page: the city map or the mission cards, as used last).
	var cf := _hub_faction()
	if cf == "":
		_home_tile(r, pad, "CAMPAIGN", "COMING LATER", "")
		return
	if not Campaign.ENABLED:                           # off for now (Daniele 2026-11-15): the card stays, its button is COMING SOON
		var off_by := _home_tile(r, pad, "CAMPAIGN", "THE CITY", "Not open yet.")
		var ob := UiKit.btn(self, UiKit.fit_text(self, "CAMPAIGN · COMING SOON", "COMING SOON", r.size.x - pad * 2.0, 14.0), Vector2(r.position.x + pad, off_by), Vector2(r.size.x - pad * 2.0, 46), show_chapters, "secondary", faction, UiKit.fit_size(self, "CAMPAIGN · COMING SOON", r.size.x - pad * 2.0, 14.0))
		ob.disabled = true
		return
	var nxt := Campaign.next_open(cf)
	var by := _home_tile(r, pad, "CAMPAIGN", str(UiKit.NAMES[cf]), "★ %d / %d" % [Campaign.stars_total(cf), Campaign.stars_max(cf)])
	UiKit.btn(self, "CONTINUE" if nxt != "" else "REPLAY", Vector2(r.position.x + pad, by), Vector2(r.size.x - pad * 2.0, 46), func():
		_hub_f = cf
		show_campaign(), "secondary", faction, 15)


func _home_tile(r: Rect2, pad: float, kicker: String, title: String, sub: String, lit := false) -> float:
	## One HOME tile: its frame, kicker, title and caption; returns the y where its buttons go.
	var pn := UiKit.panel(self, r.position, r.size, faction, lit)
	if not lit:
		pn.add_theme_stylebox_override("panel", MenuSkin.plate(0.6))            # HOME: container fill 60 % over the painting
	var y := r.position.y + pad
	var iw := r.size.x - pad * 2.0
	_clip(kicker, Vector2(r.position.x + pad, y), 12, UiKit.COPPER, iw, true)
	y += UiKit.line_h(self, 12, true) + 4.0
	_clip(title, Vector2(r.position.x + pad, y), 16, UiKit.INK, iw, true)
	y += UiKit.line_h(self, 16, true)
	_clip(sub, Vector2(r.position.x + pad, y), 13, UiKit.MUTED, iw)
	return r.end.y - pad - UiKit.tap_h(self, 46.0)


func _home_online(r: Rect2, pad: float, bh: float) -> void:
	## ONLINE: HOST ROOM creates the room and opens MATCH SETUP with the room layer; JOIN WITH CODE opens the code sheet.
	var by := _home_tile(r, pad, "ONLINE", "PLAY FRIENDS", "A room, a 4-letter code.")
	var iw := r.size.x - pad * 2.0
	var bw := (iw - 8.0) / 2.0
	var web := OS.has_feature("web")
	var long := UiKit.text_w(self, "JOIN WITH CODE", 14, true) + 20.0 <= bw
	if not Net.rejoin.is_empty():                     # dropped out of a room: back into the same seat
		var rb := UiKit.btn(self, "RECONNECT %s" % str(Net.rejoin["code"]), Vector2(r.position.x + pad, by), Vector2(iw, 46), func():
			ArmyPresets.send_to(Net, str(Net.rejoin.get("faction", faction)))
			Net.reconnect()
			show_lobby(), "selected", faction, 14)
		rb.disabled = not web
		return
	var hb := UiKit.btn(self, "HOST ROOM" if long else "HOST", Vector2(r.position.x + pad, by), Vector2(bw, 46), func():
		ArmyPresets.send_to(Net, faction)
		Net.host_room(faction)
		show_lobby(), "secondary", faction, 14)
	hb.disabled = not web
	var jb := UiKit.btn(self, "JOIN WITH CODE" if long else "JOIN", Vector2(r.position.x + pad + bw + 8.0, by), Vector2(bw, 46), func():
		_join_open = true
		Net.status = ""
		_code_error = ""
		show_main(), "secondary", faction, 14)
	jb.disabled = not web
	if not web:
		hb.tooltip_text = "Online rooms run in the browser build"


func _home_play(r: Rect2, pad: float, bh: float) -> void:
	## PLAY LAST SETUP: the summary, CHANGE (MATCH SETUP), PLAY (DEPLOY now).
	var sm := _setup_summary()
	var by := _home_tile(r, pad, "PLAY VS AI", sm[0], sm[1], true)
	var ct := "CHANGE"
	var cw := UiKit.text_w(self, ct, 14, true) + 36.0
	var iw := r.size.x - pad * 2.0
	UiKit.btn(self, ct, Vector2(r.position.x + pad, by), Vector2(cw, 46), show_setup, "secondary", faction, 14)
	UiKit.btn(self, "PLAY  →", Vector2(r.position.x + pad + cw + 10.0, by), Vector2(iw - cw - 10.0, 46), deploy, "primary", faction, 20)


func _join_sheet() -> void:
	## JOIN = the remake (45B sizes.json JOIN, a page of its own): ONLINE, the cabinet with JOIN A ROOM, the four letter
	## boxes (CHAT-FIELD, the next one FOCUS), the error / status line, BACK and JOIN ROOM. Web: the native code field
	## (OozeRoom.placeCode, phone keyboards) sits on the boxes' row (_code_box); the boxes show what was typed.
	var st := _stage_page("OOZE / JOIN", "home", "ONLINE", "JOIN WITH A CODE", _close_join, faction)
	_page = "online"
	var web := OS.has_feature("web")
	st.piece("HERO-CABINET", 212, 76, 388, 246, "STATIC", "388x246pt")
	st.piece("HERO-TITLE-BAR", 224, 88, 364, 42, "STATIC", "364x42pt")
	st.txt("JOIN A ROOM", 238, 100, 336, 18, 15.0, UiKit.INK, true, 1)
	var err := _code_error if _code_error != "" else Net.status
	st.txt(err if err != "" else "Enter the four-letter room code.", 228, 145, 356, 32, 12.5, UiKit.STAR if err != "" else UiKit.MUTED, false, 1, 2)
	var code := _code_value.to_upper()
	for k in range(4):
		var x := 263.0 + 74.0 * k
		var p := st.piece("CHAT-FIELD", x, 183, 64, 51, "FOCUS" if k == mini(code.length(), 3) else "NORMAL")
		p.tints = {"seat": Kit45.seat()}
		st.txt(code.substr(k, 1) if k < code.length() else "", x + 16, 200, 32, 18, 20.0, UiKit.INK, true, 1)
	var box := LineEdit.new()                          # the frame the HTML field sits on (never typed into)
	box.editable = false
	box.focus_mode = Control.FOCUS_NONE
	for sn in ["normal", "read_only", "focus"]:
		box.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
	var br := st.R(263, 183, 286, 51)
	box.position = br.position
	box.size = br.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(box)
	_code_box = box
	st.key("KEY-SMALL", 230, 268.5, 115, 33, "BACK", _close_join)
	var jb := st.key("PRIMARY-WIDE", 402, 268, 181, 33, "JOIN ROOM  →", _join_from_field, true, not web)
	jb.size_pt = 14.0
	if not web:
		jb.tooltip_text = "Online rooms run in the browser build"
	if web:
		_place_code_field.call_deferred()
	shell_raise()


func _close_join() -> void:
	_join_open = false
	_code_error = ""
	Net.status = ""
	show_main()


func show_play() -> void:
	## UX pass (Alpha 24 step 3): the PLAY hub page is gone - HOME plays; old ways in land on MATCH SETUP.
	show_setup()


func show_help() -> void:
	_last_show = show_help
	## GUIDE = the remake (45B sizes.json GUIDE; a nav tab, Daniele 11-05): BASICS / FACTIONS / SKILLS / MAPS sub-tabs, the
	## picture well at the left, the page's four numbered lines at the right, ‹ p / n ›; TRAINING / ARMIES where they help.
	var st := _stage_page("OOZE / GUIDE", "guide", "GUIDE", "HOW TO PLAY", Callable(), faction)
	_page = "guide"
	var tabs := [["basics", "BASICS"], ["factions", "FACTIONS"], ["skills", "SKILLS"], ["maps", "MAPS"]]
	for i in range(4):
		var id: String = tabs[i][0]
		var b := st.key("SUB-TAB", 15 + 197 * i, 74, 191, 34, str(tabs[i][1]), func():
			_guide_tab = id
			show_help(), id == _guide_tab, false, "191x34pt")
		b.size_pt = 13.0
	var pages: Array = GUIDE.get(_guide_tab, GUIDE["basics"])
	var p := _pager(st, "guide:" + _guide_tab, pages.size(), show_help)
	st.piece("HERO-CABINET", 15, 115, 345, 172, "STATIC", "345x172pt")
	st.piece("HERO-WELL", 26, 126, 323, 150, "STATIC", "323x150pt")
	match _guide_tab:
		"factions", "skills":
			UiKit.hero(self, faction, st.P(110, 128), Vector2(155, 146) * st.u, false)
		_:
			st.pic(UiKit.map_thumb(MapPool.thumb(str(_selected_map().get("code", "")))), 30, 130, 315, 142)
	st.piece("HERO-CABINET", 373, 115, 424, 172, "STATIC", "424x172pt")
	var pg: Array = pages[p]
	st.txt(str(pg[0]), 388, 128, 393, 18, 14.0, Kit45.KICK, true)
	var lines: Array = pg[1]
	for k in range(lines.size()):
		var y := 151.0 + 29.0 * k
		st.txt(str(k + 1), 388, y, 16, 16, 13.0, Kit45.KICK, true)
		st.txt(str(lines[k]), 410, y - 6, 375, 28, 12.5, UiKit.INK, false, 0, 2)
	if _guide_tab == "basics":
		var tb := st.key("KEY-SMALL", 612, 299, 185, 33, "TRAINING  →" if TutorialDirector.ENABLED else "TRAINING · SOON", show_tutorial, false,
				not TutorialDirector.ENABLED)               # Daniele 2026-11-15: the tutorial is being remade
		tb.size_pt = 12.5
	elif _guide_tab in ["factions", "skills"]:
		st.key("KEY-SMALL", 612, 299, 185, 33, "ARMIES  →", func(): show_armies())
	shell_raise()


static var _opt_tab := "display"                   # SETTINGS: the open tab (kept while the game runs)
static var _opt_arg_read := false
const OPT_TABS := [["display", "GAME"], ["audio", "AUDIO"], ["privacy", "PRIVACY"], ["debug", "TESTING"]]   # 45B: tabs, never a scroll
# (Last Stand, enemy counts) live in SETUP, not here; the test tools sit apart in TESTING (id "debug"); PROGRESSION:
# PRIVACY (Alpha 21) between them


func show_options() -> void:
	_last_show = show_options                  # a resize that changes the phone sizing rebuilds it (_fit)
	## SETTINGS = the remake (45B sizes.json SETTINGS): four SUB-TABs (GAME, AUDIO, PRIVACY, TESTING; Daniele 11-04: tabs,
	## no scrolling), two HERO-CABINETs of rows (label + option keys, the picked one SELECTED; volumes = a bar in the seat
	## colour with - / +), DONE. Every switch applies at once (no APPLY step: nothing waits to be saved).
	if not _opt_arg_read:                              # UI: screenshots open a tab (--options-tab=audio)
		_opt_arg_read = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--options-tab="):
				_opt_tab = arg.substr(14)
	_meta_open("options", show_main)
	var back := func(): _meta_back("options", show_main)
	var st := _stage_page("OOZE / SETTINGS", "home", "SETTINGS", "GAME OPTIONS", back, faction)
	_page = "options"
	if not OPT_TABS.any(func(t): return t[0] == _opt_tab):
		_opt_tab = "display"
	for i in range(4):
		var id: String = OPT_TABS[i][0]
		var b := st.key("SUB-TAB", 15 + 197 * i, 74, 191, 34, str(OPT_TABS[i][1]), func():
			_opt_tab = id
			show_options(), id == _opt_tab, false, "191x34pt")
		b.size_pt = 13.0
	st.piece("HERO-CABINET", 15, 114, 385, 180, "STATIC", "385x211pt")
	st.piece("HERO-CABINET", 412, 114, 385, 180, "STATIC", "385x211pt")
	var L := [29.0, 124.0]                            # [x, y] of the left cabinet's first row
	var R := [426.0, 124.0]
	_audio_readout = null
	match _opt_tab:
		"audio":
			_opt45(st, L, "Sound", [["ON", Sfx.sound_on(), func(): Sfx.set_on(true)], ["OFF", not Sfx.sound_on(), func(): Sfx.set_on(false)]])
			_vol45(st, L, "Volume", Rules.SOUND_VOLUME_STEPS, Sfx.volume(), Sfx.volume_label(Sfx.volume()), func(v): Sfx.set_volume(v), not Sfx.sound_on())
			_opt45(st, L, "Test", [["TEST SOUND", false, func(): AudioDiag.run_test(_audio_refresh)]], false, false)
			var ro := AudioDiag.readout()
			if ro != "":
				_audio_readout = Label.new()                 # (AudioDiag refreshes it after a TEST SOUND)
				_audio_readout.text = ro
				_audio_readout.visible = false
				st.add_child(_audio_readout)
				st.txt(ro, L[0], L[1], 355, 30, 12.5, UiKit.MUTED, false, 0, 2)
			_opt45(st, R, "Music", [["ON", Music.music_on(), func(): Music.set_on(true)], ["OFF", not Music.music_on(), func(): Music.set_on(false)]])
			_vol45(st, R, "Menus", Rules.MUSIC_VOLUME_STEPS, Music.volume("menu"), Music.volume_label(Music.volume("menu"), "menu"),
					func(v): Music.set_volume(v, "menu"), not Music.music_on())
			_vol45(st, R, "Match", Rules.MUSIC_VOLUME_STEPS, Music.volume("match"), Music.volume_label(Music.volume("match"), "match"),
					func(v): Music.set_volume(v, "match"), not Music.music_on())
			st.txt(Rules.MUSIC_CREDIT, R[0], R[1], 355, 30, 12.5, UiKit.MUTED, false, 0, 2)
		"privacy":
			st.txt("SHARE PLAY & CRASH DATA", L[0], L[1], 355, 16, 12.5, Kit45.KICK, true)
			st.txt("Gameplay and performance numbers and crash reports, tied only to your game account id. OFF: nothing leaves this device.",
					L[0], L[1] + 18.0, 355, 62, 12.5, UiKit.MUTED, false, 0, 4)
			L[1] += 84.0
			_opt45(st, L, "Sharing", [["ON", Telemetry.sharing(), func(): _set_share(true)], ["OFF", not Telemetry.sharing(), func(): _set_share(false)]])
			st.txt("WHAT THE GAME KEEPS", R[0], R[1], 355, 16, 12.5, Kit45.KICK, true)
			st.key("KEY-SMALL", R[0], R[1] + 24.0, 155, 34, "PRIVACY  →", func(): show_privacy(show_options))
			st.key("KEY-SMALL", R[0], R[1] + 66.0, 155, 34, "ACCOUNT  →", show_account)
		"debug":
			_opt45(st, L, "Debug tools", [["ON", Rules.debug_tools, func(): Rules.debug_tools = true], ["OFF", not Rules.debug_tools, func(): Rules.debug_tools = false]])
			st.txt("The Debug button and live sliders in matches.", L[0], L[1], 355, 30, 12.5, UiKit.MUTED, false, 0, 2)
			_opt45(st, R, "Locks", [["OFF", Progression.unlock_all, func(): Progression.unlock_all = true], ["ON", not Progression.unlock_all, func(): Progression.unlock_all = false]])
			st.txt("OFF: everything unlocked (the testing default). ON: the game as players will see it.", R[0], R[1], 355, 46, 12.5, UiKit.MUTED, false, 0, 3)
		_:                                            # GAME
			var modes := []
			for m in PerfProfile.MODES:
				var md: String = m
				modes.append([str(PerfProfile.MODE_NAMES[md]), PerfProfile.mode() == md, func(): PerfProfile.set_mode(md)])
			_opt45(st, L, "Graphics", modes)
			var low := PerfProfile.level() == "low"
			var fps := []
			for fm in PerfProfile.FPS_MODES:
				var fv: String = fm
				fps.append(["AUTO" if fv == "auto" else fv, PerfProfile.fps_mode() == fv, func(): PerfProfile.set_fps(fv)])
			_opt45(st, L, "Frame rate", fps, low)
			st.txt(("AUTO = %s on this device. " % ("PHONE" if PerfProfile.is_phone() else "FULL")) + PerfProfile.fps_label(), L[0], L[1], 355, 46, 12.5, UiKit.MUTED, false, 0, 3)
			_opt45(st, R, "Detail", [["FULL", not Rules.low_detail, func(): Rules.low_detail = false], ["LOW", Rules.low_detail, func(): Rules.low_detail = true]])
			_opt45(st, R, "Colour-blind", [["OFF", not Rules.colour_blind(), func(): Rules.set_colour_blind(false)], ["ON", Rules.colour_blind(), func(): Rules.set_colour_blind(true)]])
			_step45(st, R, "Count size", Rules.COUNT_SIZES.size(), Rules.count_size(),   # 3.0 WP4: the counts on the node screens
					"%s  x%s" % [Rules.COUNT_SIZE_NAMES[Rules.count_size()], str(Rules.count_scale())], func(i): Rules.set_count_size(i))
			st.txt("LOW detail trims the river patches and vat residents. Colour-blind picks seat colours anyone can tell apart.", R[0], R[1], 355, 46, 12.5, UiKit.MUTED, false, 0, 3)
	st.txt(Rules.version_label() + " · settings apply at once", 15, 307, 560, 16, 12.5, UiKit.MUTED)
	var dn := st.key("PRIMARY-WIDE", 610, 299, 187, 33, "DONE  →", back, true)
	dn.size_pt = 14.0
	shell_raise()


var _audio_readout: Label = null                  # AUDIO DIAG: SETTINGS' audio readout (refreshed after a TEST SOUND)


func _audio_refresh() -> void:
	if is_instance_valid(_audio_readout):
		_audio_readout.text = AudioDiag.readout()


func show_factions() -> void:
	## 01 FACTION (screen system 03): the roster - five tiles, the picked one lit (a tap picks it: `faction`, and the
	## page's accent) - the picked faction large (its character, name, tagline, persistent trait, stats) and its army
	## preset (01 active / 02 map / 03 ultimate: each row opens ARMIES on it, as does EDIT IN ARMIES); NEXT: BATTLEFIELD.
	_last_show = show_factions                  # a resize that changes the phone sizing rebuilds it (_fit)
	var area := shell_open("OOZE / ARMY", "home", _cancel_pick, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := page_title(area, "LOBBY / ARMY", "PICK YOUR ARMY.")
	var gap := 10.0
	var th := UiKit.tap_h(self, 58.0)
	var tw := (w - gap * 4.0) / 5.0
	for i in range(FACTIONS.size()):
		_roster_tile(FACTIONS[i], Vector2(x + i * (tw + gap), y), Vector2(tw, th))
	y += th + 14.0
	# the foot: the note (where it fits), EDIT IN ARMIES, NEXT
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 12.0
	var nt := "CHOOSE  →"
	var nw := maxf(UiKit.text_w(self, nt, 17, true) + 48.0, 180.0)
	UiKit.btn(self, nt, Vector2(content.size.x - x - nw, fy), Vector2(nw, 48), _choose_faction, "primary", faction, 17)
	var et := "EDIT LOADOUT  ›"
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


func _choose_faction() -> void:
	## ROUND 4: the ARMY page's CHOOSE - in a room the pick (and its ARMIES preset) goes to the room, then back to the
	## lobby you came from (Daniele: picking an army online must not send you anywhere else).
	main.SEAT_FACTIONS[main.HUMAN] = faction
	if Net.in_room():
		ArmyPresets.room_faction(Net, faction)
	_back_to_setup()


func _cutout(f: String, pos: Vector2, dims: Vector2) -> TextureRect:
	## The faction's character cutout, not yet placed (a tile's or a chip's child; UiKit.hero adds it to the page).
	var r := TextureRect.new()
	r.texture = UiKit.tex(UiKit.hero_path(f))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = dims
	UiKit.hero_neon(r, f, _viewer_col())
	return r


func _viewer_col() -> Color:
	## The viewer's own seat colour in a room (the lobby's accents); seat A's in the menus.
	var seat := Net.local_seat() if Net.in_room() else "A"
	return Rules.HUES.get(str(Net.room_colours().get(seat, "")), Rules.SEATS.get(seat, MenuSkin.seat()))


func _cutout_mark(f: String, pos: Vector2, dims: Vector2, _rim := Color(0, 0, 0, 0)) -> Control:
	## Small faction chips (room seats, pickers): the faction AI's small screen (UiKit.ai_screen_path: brass bezel, the AI on
	## its glitch back), no ring socket around it (Daniele 11-18: "the circle around the AI is not necessary ... use the
	## small screen instead").
	var t := TextureRect.new()
	t.texture = UiKit.tex(UiKit.ai_screen_path(f))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = pos
	t.size = dims
	return t


func _roster_tile(f: String, pos: Vector2, dims: Vector2) -> void:
	## FACTION's roster tile: the character and the name; the picked one in its accent. A tap picks the faction.
	var picked := f == faction
	var b := UiKit.btn(self, "", pos, dims, func():
		faction = f
		main.SEAT_FACTIONS[main.HUMAN] = f
		show_factions(), "selected" if picked else "secondary", f)
	var hs := b.size.y - 10.0
	var nh := UiKit.line_h(self, 15, true)
	# iOS: the name keeps its letters on a narrow tile ("EMBEI") - the emblem goes first, then the character shrinks
	var name_w := UiKit.text_w(self, UiKit.NAMES[f], 15, true)
	var with_em := hs + 14.0 + nh + 6.0 + name_w + 8.0 <= b.size.x
	hs = clampf(b.size.x - 14.0 - (nh + 6.0 if with_em else 0.0) - name_w - 8.0, hs * 0.55, hs)
	b.add_child(_cutout_mark(f, Vector2(6, (b.size.y - hs) / 2.0), Vector2(hs, hs)))
	var two := nh + UiKit.line_h(self, 12) <= b.size.y - 6.0
	var ty := (b.size.y - (nh + (UiKit.line_h(self, 12) if two else 0.0))) / 2.0
	if with_em:
		b.add_child(UiKit.emblem_node(f, nh, Vector2(hs + 14.0, ty)))   # the race emblem before the name
	var tx := hs + 14.0 + (nh + 6.0 if with_em else 0.0)
	var nm := UiKit.label(self, UiKit.NAMES[f], 15, UiKit.accent(f) if picked else UiKit.INK, true)
	var sl := UiKit.label(self, UiKit.SUBS[f], 12, UiKit.MUTED)
	for l in ([nm, sl] if two else [nm]):
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var es := clampf(dims.y * 0.14, 40.0, 64.0)          # the race emblem, the card's top-right corner
	UiKit.emblem_rect(self, faction, Vector2(pos.x + dims.x - pad - es, pos.y + pad), es)
	var tx := pos.x + pad + hs + 18.0
	var tw := pos.x + dims.x - pad - tx - es * 0.6
	var with_stats := true
	var ft: Array = Rules.faction_trait(faction)
	# [text, size, colour, head, spacing] - measured as they draw (Daniele 2026-09-28: on his screen PERSISTENT TRAIT ·
	# COMING SOON wrapped where the old width estimate said one line, and COMING SOON sat on the trait's name). Where the
	# card is short (phones) it makes room in steps: the tagline goes, then the spacer, then the kicker shortens.
	var nb := "PERSISTENT\u00a0TRAIT"                          # (a no-break space: the words wrap as one)
	var attempts := [[true, true, nb], [false, true, nb], [false, false, nb], [false, false, "TRAIT"], [false, false, "TRAIT", "no stats"]]
	var labels := []
	var hts := []
	var total := 0.0
	for at in attempts:
		if at.size() > 3:                               # iOS (Safari's 320-340 pt): still too tall - the stats row goes
			with_stats = false                         # (as on ARMIES), its height to the text
			body_h = dims.y - pad * 2.0
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
		var kick: String = at[2]                           # (the trait is the live stat leans: no COMING SOON)
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
	UiKit.hero(self, faction, Vector2(pos.x + pad, pos.y + pad + (body_h - hs) / 2.0), Vector2(hs, hs))
	var ly := pos.y + pad + maxf(0.0, (body_h - total) / 2.0)
	for i in range(labels.size()):
		if labels[i] != null:
			(labels[i] as Label).position = Vector2(tx, ly)
		ly += hts[i]
	if not with_stats:
		return
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
	if _tut_page.get("content") is Control:            # UI (0.22.x button sweep): its empty area let the desktop BACK
		(_tut_page.content as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE   # (title row) under it take no tap
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


func show_profile() -> void:
	_last_show = show_profile                  # a resize that changes the phone sizing rebuilds it (_fit)
	## PROFILE = the remake (45B sizes.json PROFILE): the four sub-tabs; LEVEL-CARD (avatar, LEVEL, XP bar in the seat colour,
	## SCRAP and CHIPS rows with where they come from); FACTIONS-PANEL with a FACTION-ROW per faction (played / won, the
	## faction vat's progress in the faction colour).
	var st := _profile_tabs("", "OOZE / PROFILE")
	_page = "profile"
	var a := _account()
	var lf := Progression.level_for(Progression.xp)
	var PR := Rules.PROGRESSION
	st.piece("LEVEL-CARD", 15, 116, 329, 213)
	st.piece("SEAT-AVATAR-WELL", 26, 127, 53, 45, "STATIC", "50x46pt")
	st.add_child(_cutout_mark(faction, st.P(29, 129), Vector2(47, 41) * st.u))
	st.txt(a.player_name.to_upper() if a.player_name != "" else "YOUR LEVEL", 91, 127, 230, 16, 12.5, Kit45.KICK, true)
	st.txt("LEVEL %d" % int(lf["level"]), 91, 147, 230, 24, 22.0, UiKit.INK, true)
	var xb := st.piece("XP-BAR", 26, 182, 307, 8)
	xb.fill = float(lf["into"]) / maxf(1.0, float(lf["need"]))
	xb.tints = {"fill": Kit45.seat()}
	st.txt("%s / %s XP TO LEVEL %d" % [_thou(int(lf["into"])), _thou(int(lf["need"])), int(lf["level"]) + 1], 26, 196, 307, 16, 12.5, UiKit.INK, true)
	var rows := [["soft", "CUR-1", "SCRAP", "Matches, challenges, tutorial. Buys skills."],
			["premium", "CUR-2", "CHIPS", "Challenges, every %dth level. Looks only." % int(PR["level_premium_every"])]]
	for k in range(2):
		var y := 222.0 + 50.0 * k
		st.piece("CURRENCY-ROW", 26, y, 307, 46)
		st.pic(Kit45.art(str(rows[k][1])), 33, y + 6, 23, 23)
		st.txt("%s %s" % [_thou(Progression.balance(str(rows[k][0]))), rows[k][2]], 64, y + 4, 258, 16, 13.0, UiKit.INK, true)
		st.txt(str(rows[k][3]), 33, y + 27, 289, 16, 12.5, UiKit.MUTED)
	# FACTIONS
	st.piece("FACTIONS-PANEL", 354, 116, 443, 213)
	var need: int = PR["faction_vat_wins"]
	st.txt("FACTIONS", 366, 122, 415, 16, 13.0, UiKit.INK, true)
	st.txt("%d wins with a faction unlock its vat (online or vs Veteran AI up)." % need, 366, 139, 415, 16, 12.5, UiKit.MUTED)
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var fs := Progression.faction_stats(f)
		var owned := Progression.owns("vat:faction:" + f)
		var y := 157.0 + 34.0 * i
		var row := st.piece("FACTION-ROW", 363, y, 425, 29, "NORMAL", "425x29pt")
		row.fill = 1.0 if owned else float(fs["vat_wins"]) / float(need)
		row.tints = {"fill": UiKit.accent(f)}
		st.pic(UiKit.tex(UiKit.ai_screen_path(f)), 369, y + 4, 30, 21)
		# designer 11 FIX 6: one line, centred in the row (name · played / won · vat), >= 3 pt clear of the rims
		st.txt(str(UiKit.NAMES[f]), 407, y + 4, 66, 21, 12.5, UiKit.accent(f), true)
		st.txt("PLAYED %d · WON %d" % [int(fs["plays"]), int(fs["wins"])], 476, y + 4, 150, 21, 12.5, UiKit.INK)
		st.txt("VAT UNLOCKED" if owned else "VAT %d / %d WINS" % [int(fs["vat_wins"]), need], 628, y + 4, 152, 21, 12.5,
				UiKit.accent(f) if owned else UiKit.MUTED, true, 2)
	shell_raise()


func show_challenges(just_claimed := "") -> void:
	_last_show = func(): show_challenges()                  # a resize that changes the phone sizing rebuilds it (_fit)
	## CHALLENGES = the PROFILE > CHALLENGES tab (45B CHALLENGE-ROW 762 x 72): the dailies then the weeklies, three rows a
	## page (‹ › at the top right), each with its text, progress bar + count, reward, and CLAIM / REROLL / IN PROGRESS / DONE.
	_meta_open("challenges", show_main)
	var kick := "DAILY RESET %s · WEEKLY %s" % [Progression.duration_text(Progression.seconds_to_reset("daily")).to_upper(),
			Progression.duration_text(Progression.seconds_to_reset("weekly")).to_upper()]
	var st := _profile_tabs("CHALLENGES", "OOZE / CHALLENGES", func(): _meta_back("challenges", show_main), kick, Vector2(200, 638))
	_page = "challenges"
	var rerolled: bool = Progression.challenges.get("daily", {}).get("rerolled", false)
	var list := []
	for kind in ["daily", "weekly"]:
		for c in Progression.current_challenges(kind):
			list.append([kind, c])
	var n_pages := maxi(1, ceili(list.size() / 3.0))
	var p := _pager(st, "challenges", n_pages, func(): show_challenges(), 646, 39)   # FIX 7: inside the 16 pt edge
	for k in range(3):
		var i := p * 3 + k
		if i >= list.size():
			break
		_challenge_row45(st, str(list[i][0]), list[i][1], 25, 113 + 72 * k, just_claimed, rerolled)
	if list.is_empty():
		st.txt("No challenges right now - they come back at the next reset.", 25, 150, 762, 20, 13.0, UiKit.MUTED)
	shell_raise()


# ------------------------------------------------------------------ UI: parts of the online / progression / settings pages (Alpha 21)
var _meta_from := {}                               # page -> [the page it was opened from (its BACK), the tab kept lit]
var _meta_returning := false                       # a BACK is under way: the page it lands on keeps its own record
const META_TABS := ["home", "play", "armies", "campaign", "profile", "guide"]


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
	UiKit.shrink_label(l, width)                      # designer 10 (11-18): shrink to fit first (to 80 % of the floor), then cut
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
	col["w"] = dims.x - 34.0                           # (the pager is a strip under the column, ROUND 2b)
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
	## ACCOUNT = PROFILE > ACCOUNT (45B): left PLAYER PROFILE (avatar, name, level), DISPLAY NAME field + SAVE NAME; right
	## ACCOUNT STATUS (where progress is kept, the last note), SIGN IN WITH GOOGLE / ADD GOOGLE (guest), PRIVACY (the
	## share switch + the policy) and DELETE ACCOUNT. Optional: the game plays offline without it.
	var a := _account()
	_meta_open("account", show_profile)
	var st := _profile_tabs("ACCOUNT", "OOZE / ACCOUNT", func():
		_account_note = ""
		_meta_back("account", show_profile))
	_page = "account"
	var web := OS.has_feature("web")
	st.piece("HERO-CABINET", 15, 115, 385, 215, "STATIC", "385x215pt")
	st.piece("HERO-CABINET", 412, 115, 385, 215, "STATIC", "385x215pt")
	# left: the player
	st.piece("SEAT-AVATAR-WELL", 30, 133, 40, 40, "STATIC", "40x40pt")
	st.add_child(_cutout_mark(faction, st.P(33, 136), Vector2(34, 34) * st.u))
	var lf := Progression.level_for(Progression.xp)
	st.txt("PLAYER PROFILE", 85, 133, 293, 16, 12.5, Kit45.KICK, true)
	st.txt("%s · LEVEL %d" % [(a.player_name if a.player_name != "" else "PLAYER").to_upper(), int(lf["level"])], 85, 151, 293, 18, 14.0, UiKit.INK, true)
	st.txt("DISPLAY NAME", 30, 196, 350, 16, 12.5, Kit45.KICK, true)
	var on := a.signed_in()
	st.piece("CHAT-FIELD", 30, 219, 350, 33, "NORMAL" if on else "DISABLED")
	var fr := st.R(36, 219, 338, 33)
	var e := LineEdit.new()
	e.size = fr.size
	e.placeholder_text = "3-16 letters or digits"
	e.text = a.player_name
	e.add_theme_font_override("font", UiKit.HEAD)
	e.add_theme_font_size_override("font_size", int(maxf(13.0 * st.u, Kit45.floor_px(self))))
	e.add_theme_color_override("font_color", UiKit.INK)
	e.add_theme_color_override("font_placeholder_color", UiKit.DIM)
	e.add_theme_color_override("font_uneditable_color", UiKit.MUTED)
	for sn in ["normal", "read_only", "focus"]:
		e.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
	e.virtual_keyboard_enabled = true
	e.position = fr.position
	st.add_child(e)
	if web:                                            # the HTML field sits on this frame (never typed into)
		e.editable = false
		e.focus_mode = Control.FOCUS_NONE
		e.text = ""
		e.placeholder_text = ""
		_name_box = e
		_name_enabled = on
		_name_value = a.player_name
		_place_name_field.call_deferred()
	else:
		e.editable = on
	st.key("KEY-SMALL", 30, 279, 155, 34, "SAVE NAME", func():
		if web:
			_rename_from_field()
			return
		if await a.rename(e.text):
			_account_note = "Name saved: " + a.player_name
		else:
			_account_note = a.last_error
		show_account(), on, not on)
	# right: the account
	var status := "Offline: you play as a guest on this device."
	var col := Color("ffd15c")
	match a.state:
		"guest":
			status = "Guest account: this device, with a cloud copy."
			col = Color("9cb2bf")
		"linked":
			status = "Signed in with Google" + ((": " + a.email) if a.email != "" else ".")
			col = Color("6fff2a")
		"signing_in":
			status = "Signing in ..."
		"deleted":
			status = "Account deleted: this device keeps its progress."
	st.txt("ACCOUNT STATUS", 427, 133, 353, 16, 12.5, Kit45.KICK, true)
	st.txt(status, 427, 153, 353, 18, 12.5, col, true)
	var line2 := _account_note if _account_note != "" else ("Progress saved on this device." if Progression.saved else "This browser keeps no storage.")
	st.txt(line2, 427, 174, 353, 32, 12.5, UiKit.STAR if _account_note != "" else UiKit.MUTED, false, 0, 2)
	if web and not a.google_ready and a.state != "offline":
		a.check_google()                           # redraws through Account.changed when the answer differs
	var google_ok := web and a.google_ready
	st.key("KEY-SMALL", 427.5, 220, 155, 34, "SIGN IN", func():
		if not await a.google(false):
			_account_note = a.last_error
			show_account(), a.state != "linked" and google_ok, not google_ok or a.state == "linked")
	if a.state == "guest":
		st.key("KEY-SMALL", 597.5, 220, 183, 34, "ADD GOOGLE", func():
			if not await a.google(true):
				_account_note = a.last_error
				show_account(), google_ok, not google_ok)
	st.key("KEY-SMALL", 427.5, 279, 155, 34, "PRIVACY", func(): show_privacy(show_account))
	st.key("KEY-SMALL", 597.5, 279, 183, 34, "DELETE ACCOUNT", _delete_prompt, false, not a.signed_in())
	shell_raise()


# ------------------------------------------------------------------ PROGRESSION: PRIVACY (Alpha 21)

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
	## LEADERBOARD = PROFILE > LEADERBOARD (45B): this season's online wins (server rooms, two or more players), four rows
	## a page; YOU last when you are not on the list. REFRESH at the top right.
	_meta_open("leaderboard", show_profile)
	var now := Time.get_datetime_dict_from_system(true)
	var st := _profile_tabs("LEADERBOARD", "OOZE / LEADERBOARD", func():
		_board_state = "idle"
		_meta_back("leaderboard", show_profile), "SEASON %s %d · ONLINE WINS" % [MONTHS[int(now["month"]) - 1], int(now["year"])], Vector2(200, 672))
	_page = "leaderboard"
	st.key("KEY-SMALL", 681.5, 39, 115, 33, "REFRESH", func():
		_board_state = "idle"
		show_leaderboard())
	if _board_state == "idle":
		_board_state = "loading"
		_load_board.call_deferred()                    # after this page is built (an offline answer comes back at once)
	var cols := [["RANK", 35, 83], ["PLAYER", 132, 410], ["WINS", 561, 200]]
	var rows := []
	var acc := UiKit.accent(shell_f)
	for row in _board_rows:
		var me: bool = row.get("is_me", false) == true   # the server may send null
		rows.append([["#%d" % int(row.get("rank", 0)), str(row.get("name", "")) + ("  (YOU)" if me else ""), "%d" % int(row.get("wins", 0))],
				[UiKit.STAR, acc if me else UiKit.INK, acc if me else UiKit.INK]])
	if not _board_me.is_empty():                      # YOU, when you're not on the list
		var wins := int(_board_me.get("wins", 0))
		rows.append([["#%d" % int(_board_me.get("rank", 0)) if wins > 0 else "-", str(_board_me.get("name", "")) + "  (YOU)", "%d" % wins],
				[UiKit.STAR, acc, acc]])
	var empty := "No wins yet this season - win an online match against another player to open the board."
	if _board_state == "loading":
		empty = "LOADING ..."
	elif _board_state == "offline":
		empty = "The leaderboard needs a connection."
	_table45(st, cols, rows, "leaderboard", show_leaderboard, empty)
	shell_raise()


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
	## MATCH HISTORY = PROFILE > MATCH HISTORY (45B): this device's matches + the account's online rounds, four a page;
	## › on the last page asks the server for older rounds.
	var a := _account()
	_meta_open("history", show_profile)
	var st := _profile_tabs("MATCH HISTORY", "OOZE / MATCH HISTORY", func():
		_history_state = "idle"
		_history_online = []
		_meta_back("history", show_profile), "THIS DEVICE" + (" + ONLINE ROUNDS" if a.signed_in() else "") + (" · LOADING ..." if _history_state == "loading" else ""), Vector2(200, 797))
	_page = "history"
	if _history_state == "idle" and a.signed_in():
		_history_state = "loading"
		_load_history.call_deferred(false)             # after this page is built
	var cols := [["RESULT", 35, 79], ["MODE", 130, 90], ["MAP", 230, 155], ["FACTION", 395, 118], ["DURATION", 524, 128], ["DATE", 662, 118]]
	var names := _map_names()
	var rows := []
	for h in Progression.merge_history(Progression.history, _history_online):
		var won := bool(h.get("won", false))
		var draw := bool(h.get("draw", false))
		var res := "DRAW" if draw else ("WIN" if won else "LOSS")
		var rc := Color("9cb2bf") if draw else (Color("6fff2a") if won else Color("ff5a4a"))
		var mine := ""
		for pl in h.get("players", []):
			if pl is Dictionary and pl.get("is_me", false) == true:
				mine = str(pl.get("faction", ""))
		var code := str(h.get("map", ""))
		var dur := int(h.get("duration_s", 0))
		rows.append([[res, str(Menu.MODE_NAMES.get(str(h.get("mode", "")), str(h.get("mode", "")))),
				str(names.get(code, code)).replace("*", "").to_upper(), str(UiKit.NAMES.get(mine, "-")),
				"%02d:%02d" % [dur / 60, dur % 60], _date_text(int(h.get("t", 0)))],
				[rc, UiKit.INK, UiKit.INK, UiKit.accent(mine) if mine != "" else UiKit.MUTED]])
	var more := Callable()
	if a.signed_in() and _history_more and not _history_online.is_empty():
		more = func(): _load_history(true)
	_table45(st, cols, rows, "history", show_history, "No matches yet - finish one and it shows here.", more)
	shell_raise()


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
		return "%d / %d WINS AS %s OR ITS CAMPAIGN" % [int(Progression.faction_stats(_army)["vat_wins"]),
				int(Rules.PROGRESSION["faction_vat_wins"]), "BLOOM" if _army == "bloom" else _army.to_upper()]
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
	if inner.custom_minimum_size.x > dims.x + 1.0:     # iOS: a row that swipes says so - a fade and a "›" over the
		var hint := Control.new()                      # cut card at the right edge, gone once the row is scrolled to its end
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hw := minf(cw * 0.45, 140.0)
		var g := Gradient.new()
		g.set_color(0, Color(UiKit.BASE, 0.0))
		g.set_color(1, Color(UiKit.BASE, 0.88))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_to = Vector2(1, 0)
		var fade := TextureRect.new()
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.size = Vector2(hw, dims.y)
		hint.add_child(fade)
		var arrow := UiKit.label(self, "›", 54, UiKit.accent(shell_f), true)
		arrow.position = Vector2(hw - arrow.get_minimum_size().x - 6.0, (dims.y - arrow.get_minimum_size().y) / 2.0)
		hint.add_child(arrow)
		hint.size = Vector2(hw, dims.y)
		_shell_add(hint, pos + Vector2(dims.x - hw, 0))
		var bar := scroll.get_h_scroll_bar()
		bar.value_changed.connect(func(v: float):
			if is_instance_valid(hint):
				hint.visible = v < bar.max_value - bar.page - 4.0)
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
	# ARMIES SPLIT (Daniele 2026-11-05: "agree on armies split"): the five factions once, then two tabs - SKILLS (what
	# the faction does: identity + the one-page skill tiles) and CUSTOMIZE (how it looks: the wardrobe). No title row.
	if sub:                                            # ROUND 4 (Daniele: "no way to go back to the room lobby"): one big way back
		var to_lobby := Net.in_room() or _army_back == show_factions or _army_back == show_setup
		var st := "SAVE  ·  BACK TO LOBBY" if to_lobby else "SAVE  ·  BACK"
		var sw := UiKit.text_w(self, st, 15, true) + 48.0
		var bx := content.size.x - shell_x() - sw if shell_slim else (content.size.x - sw) / 2.0
		var sb := UiKit.make_btn(self, st, Vector2(sw, 44), _save_armies, "primary", _army, 15)
		top_bar.add_child(sb)                          # in the bar itself (shell_raise keeps the bar on top)
		sb.position = Vector2(bx, maxf(4.0, (top_bar.bar_height() - sb.size.y) / 2.0))
	# 43B (Daniele 2026-11-18 "Yes, import it"): the page is the 43B-pack-ARMIES layout itself (Armies43), scaled evenly
	# into the free area; CUSTOMIZE keeps its wardrobe body under the pack's faction / section row.
	var top := area.position.y + 6.0
	if _backdrop:                                      # designer 10 (11-18): the pack's own room (ARMIES-PLATE), not the sky city
		var plate := UiKit.tex(Armies43.DIR + "ARMIES-PLATE.jpg")
		if plate != null:
			_backdrop.texture = plate
			_backdrop.modulate = Color(0.9, 0.9, 0.9)
	# 45B (the remake): the pack's body sits on the remake canvas (Kit45.Stage) - faction row at y 40, 780 pt wide from
	# x 16 - so SKILLS and CUSTOMIZE (built on the same stage) line up to the point
	var st := Kit45.Stage.new()
	st.setup(self, content.size)
	content.add_child(st)
	_stage = st
	var a43 := Armies43.new()
	a43.setup(self, Rect2(st.P(16, 40), Vector2(780, 290) * st.u), _army, _army_tab, _armies43_tap)
	content.add_child(a43)
	_a43 = a43
	if _army_tab == "customize":
		_customize_body(st)
		shell_raise()
		return
	if _skill_tip != "":
		var cid := "ULT" if _skill_tip == Rules.FACTION_ULTIMATE_ID[_army] else ""
		for c in a43._skill_of:
			if a43._skill_of[c] == _skill_tip:
				cid = c
		if cid != "":
			_skill_popup(_skill_tip, a43.rect_of(cid), _skills_slot)
	shell_raise()


var _a43: Armies43 = null


func _armies43_tap(cid: String) -> void:
	## A tap on the 43B ARMIES page: faction tab, SKILLS / CUSTOMIZE, RESET, the ultimate cabinet ("ULT"), a skill card.
	if cid.begins_with("FACTION-"):
		var n := cid.substr(8).to_lower()
		_skill_tip = ""
		show_armies("solar" if n == "aegis" else n)
	elif cid == "SKILLS" or cid == "CUSTOMIZE":
		_army_tab = cid.to_lower()
		show_armies()
	elif cid == "RESET":
		ArmyPresets.reset(_army)
		_preset_changed()
		show_armies()
	elif cid == "ULT":
		_toggle_tip(Rules.FACTION_ULTIMATE_ID[_army], _skills_slot)
	elif is_instance_valid(_a43) and _a43.skill_of(cid) != "":
		var id := _a43.skill_of(cid)
		var slot := "active" if id in Rules.ACTIVE_SKILLS else "map"
		if Progression.is_unlocked("skill:" + id):
			ArmyPresets.set_pick(_army, slot, id)
			_preset_changed()
		_skill_tip = id
		show_skills(slot)


var _army_tab := "skills"                          # ARMIES: the open tab ("skills" | "customize")
var _skills_slot := "active"


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
	# iOS: the name keeps its letters on a narrow tile ("VIRIDI") - the emblem goes first, then the character shrinks
	var name_w := UiKit.text_w(self, UiKit.NAMES[tf], 15, true)
	var es0 := UiKit.line_h(self, 15, true)
	var with_em := 8.0 + hs + 6.0 + es0 + 6.0 + name_w + 6.0 <= dims.x
	hs = clampf(dims.x - 8.0 - 6.0 - (es0 + 6.0 if with_em else 0.0) - name_w - 6.0, hs * 0.55, hs)
	var art := TextureRect.new()
	art.texture = UiKit.tex(UiKit.hero_path(tf))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(8.0, (dims.y - hs) / 2.0)
	art.size = Vector2(hs, hs)
	UiKit.hero_neon(art, tf, _viewer_col())
	b.add_child(art)
	var n := UiKit.label(self, UiKit.NAMES[tf], 15, UiKit.accent(tf) if picked else UiKit.INK, true)
	var lh := n.get_minimum_size().y
	var es := n.get_minimum_size().y if with_em else 0.0
	if with_em:
		b.add_child(UiKit.emblem_node(tf, es, Vector2(8.0 + hs + 6.0, (dims.y - lh) / 2.0)))   # the race emblem before the name
	var tx := 8.0 + hs + 6.0 + (es + 6.0 if with_em else 0.0)
	n.position = Vector2(tx, (dims.y - lh) / 2.0)
	n.clip_text = true
	n.size = Vector2(dims.x - tx - 6.0, n.get_minimum_size().y)
	b.add_child(n)
	b.tooltip_text = UiKit.TAGS[tf]


func _army_identity(pos: Vector2, dims: Vector2) -> void:
	## The open faction: its character large, name / sub / tagline, the persistent trait, its five stats (dropped
	## first, then the smaller lines, when a phone's panel is too short).
	var acc := UiKit.accent(_army)
	UiKit.panel(self, pos, dims, _army)
	var ftrait: Array = Rules.faction_trait(_army)
	var stats_h := UiKit.line_h(self, 20, true) + UiKit.line_h(self, 12) + 30.0
	if dims.x <= 520.0:                                  # ARMIES > SKILLS' narrow panel: the character beside the
		_army_identity_narrow(pos, dims, ftrait)         # name, the trait under them at full width
		return
	var hs0 := minf(dims.y - 32.0, dims.x * (0.44 if dims.x > 520.0 else 0.3))   # a narrow panel (ARMIES > SKILLS) gives the words room
	var tw := dims.x - 20.0 - hs0 - 16.0 - 18.0
	# [text, size, colour, head, spacing, gap before, wraps, drop order (0 = always)]
	var items := [
		[UiKit.SUBS[_army], 12, acc, true, 3, 0.0, false, 0],
		[UiKit.NAMES[_army], 34, acc, true, 0, 0.0, false, 0],
		[str(Rules.FACTION_TAGLINES[_army]), 14, UiKit.MUTED, false, 0, 2.0, true, 2],
		["PERSISTENT TRAIT" if dims.x > 520.0 else "TRAIT", 12, acc, true, 3, 16.0, false, 0],
		[str(ftrait[0]).to_upper(), 16, UiKit.INK, true, 0, 2.0, false, 0],
		[str(ftrait[1]), 14, UiKit.MUTED, false, 0, 0.0, true, 0],
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
	if dims.x > 520.0:                                   # (a narrow panel: the words need the corner)
		UiKit.emblem_rect(self, _army, pos + Vector2(dims.x - 16.0 - es, 16.0), es)
	elif UiKit.text_w(self, items[0][0], 12, true) + str(items[0][0]).length() * 3.0 > tw:
		items[0][4] = 0                                  # the kicker loses its spacing before it runs out
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


func _army_identity_narrow(pos: Vector2, dims: Vector2, ftrait: Array) -> void:
	## The narrow identity (round 3, Daniele 2026-11-05: "image of vex not needed as it's already on top, can just have
	## the stats possibly using some icons"): KICKER / NAME, the trait across the panel, then the five stats as
	## [icon  CAPTION  value] rows; the tagline only where the height allows.
	var acc := UiKit.accent(_army)
	var ix := pos.x + 18.0
	var iw := dims.x - 36.0
	var y := pos.y + 14.0
	var sub := str(UiKit.SUBS[_army])
	var sp := 3 if UiKit.text_w(self, sub, 12, true) + sub.length() * 3.0 <= iw else 0
	_shell_add(UiKit.label(self, sub, 12, acc, true, sp), Vector2(ix, y))
	y += UiKit.line_h(self, 12, true)
	_shell_add(UiKit.label(self, UiKit.NAMES[_army], 30, acc, true), Vector2(ix - 2.0, y))
	y += UiKit.line_h(self, 30, true) + 6.0
	# the stats block, bottom up
	var rh := UiKit.line_h(self, 15, true) + 4.0
	var srows := ceili(STAT_ROWS.size() / 2.0)            # two columns of [icon  value] (the icon names the stat)
	var sy := pos.y + dims.y - 12.0 - srows * rh
	var tag := str(Rules.FACTION_TAGLINES[_army])
	var th := UiKit.text_h(self, tag, 14, iw)
	var trait_h := UiKit.line_h(self, 12, true) + UiKit.line_h(self, 16, true) + UiKit.text_h(self, str(ftrait[1]), 14, iw) + 2.0
	if y + th + 10.0 + trait_h <= sy - 12.0:
		var tl := UiKit.label(self, tag, 14, UiKit.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(iw, 0)
		_shell_add(tl, Vector2(ix, y))
		y += th + 10.0
	_shell_add(UiKit.label(self, "TRAIT", 12, acc, true, 3), Vector2(ix, y))
	y += UiKit.line_h(self, 12, true)
	var nm := str(ftrait[0]).to_upper()
	var nfs := 16.0
	while nfs > 10.0 and UiKit.text_w(self, nm, nfs, true) > iw:
		nfs -= 1.0
	_shell_add(UiKit.label(self, nm, nfs, UiKit.INK, true), Vector2(ix, y))
	y += UiKit.line_h(self, 16, true) + 2.0
	var dl := UiKit.label(self, str(ftrait[1]), 14, UiKit.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(iw, 0)
	_shell_add(dl, Vector2(ix, y))
	content.add_child(UiKit.rect(Vector2(ix, sy - 8.0), Vector2(iw, 1.0), Color(UiKit.FRAME, 0.9)))
	var gs := UiKit.line_h(self, 15, true) * 0.8
	var cw := iw / 2.0
	for i in range(STAT_ROWS.size()):
		var v := Rules.stat(_army, STAT_ROWS[i][0])
		var col := acc if v > 1.001 else (UiKit.WEAKER if v < 0.999 else UiKit.INK)
		var ry := sy + (i / 2) * rh
		var cx := ix + (i % 2) * cw
		var g := Control.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size = Vector2(gs, gs)
		var kind: String = STAT_ROWS[i][0]
		g.draw.connect(func(): _stat_glyph(g, kind, gs, col))
		g.tooltip_text = STAT_ROWS[i][1]
		_shell_add(g, Vector2(cx, ry + (rh - 4.0 - gs) / 2.0))
		_shell_add(UiKit.label(self, "%d%%" % roundi(v * 100.0), 15, col, true), Vector2(cx + gs + 8.0, ry))


func _stat_glyph(c: Control, kind: String, s: float, col: Color) -> void:
	## A small line icon per stat (drawn; no art for them yet): SPEED chevrons, HEALTH cross, ATTACK sword,
	## PRODUCTION goo drop, GARRISON shield.
	var w := maxf(1.5, s * 0.12)
	match kind:
		"speed":
			for k in [0.0, 0.38]:
				c.draw_polyline(PackedVector2Array([Vector2(s * (0.12 + k), s * 0.15), Vector2(s * (0.48 + k), s * 0.5),
						Vector2(s * (0.12 + k), s * 0.85)]), col, w, true)
		"health":
			c.draw_rect(Rect2(s * 0.38, s * 0.08, s * 0.24, s * 0.84), col)
			c.draw_rect(Rect2(s * 0.08, s * 0.38, s * 0.84, s * 0.24), col)
		"attack":
			c.draw_line(Vector2(s * 0.15, s * 0.85), Vector2(s * 0.88, s * 0.12), col, w, true)
			c.draw_line(Vector2(s * 0.12, s * 0.55), Vector2(s * 0.45, s * 0.88), col, w, true)
		"production":
			var pts := PackedVector2Array([Vector2(s * 0.5, s * 0.05)])
			for k in range(13):
				var a := PI * (0.0 - 0.15 + 1.3 * k / 12.0) + PI * -0.0
				pts.append(Vector2(s * 0.5, s * 0.62) + Vector2(cos(a - PI * 0.0), sin(a)) * s * 0.32 * Vector2(1, 1))
			pts.append(Vector2(s * 0.5, s * 0.05))
			c.draw_polyline(pts, col, w, true)
		"garrison":
			c.draw_polyline(PackedVector2Array([Vector2(s * 0.5, s * 0.05), Vector2(s * 0.88, s * 0.2), Vector2(s * 0.82, s * 0.6),
					Vector2(s * 0.5, s * 0.95), Vector2(s * 0.18, s * 0.6), Vector2(s * 0.12, s * 0.2), Vector2(s * 0.5, s * 0.05)]), col, w, true)


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
	# iOS (Safari's 320-340 pt): the ultimate ran over the tab bar - it drops its line, then puts ULTIMATE beside its name
	var ult_lines := 2 if full else 1
	var ult_inline := false
	if 2.0 * rh + uh + gap * 2.0 > dims.y:
		gap = 8.0
		ult_lines = 0
		uh = ult_h.call(0)
		if 2.0 * rh + uh + gap * 2.0 > dims.y:
			ult_inline = true
			uh = maxf(20.0 + UiKit.line_h(self, 17, true), dims.y - 2.0 * rh - gap * 2.0)
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
	if ult_inline:                                       # one row: ULTIMATE, then its name
		var kt := UiKit.label(self, "ULTIMATE", 11, UiKit.STAR, true, 2)
		var nt := UiKit.label(self, ArmyPresets.skill_name(ult).to_upper(), 17, UiKit.INK, true)
		var rowh := UiKit.line_h(self, 17, true)
		ty = y + (uh - rowh) / 2.0
		_shell_add(kt, Vector2(tx, ty + (rowh - UiKit.line_h(self, 11, true)) / 2.0))
		_shell_add(nt, Vector2(tx + UiKit.text_w(self, "ULTIMATE", 11, true) + 16.0 + 14.0, ty))
	else:
		ty = y + (uh - (ult_h.call(ult_lines) - 28.0)) / 2.0
		var k := UiKit.label(self, "ULTIMATE  ·  %s ONLY  ·  FIXED" % UiKit.NAMES[_army], 11, UiKit.STAR, true, 2)
		_shell_add(k, Vector2(tx, ty))
		ty += UiKit.line_h(self, 11, true)
		_shell_add(UiKit.label(self, ArmyPresets.skill_name(ult).to_upper(), 17, UiKit.INK, true), Vector2(tx, ty))
		ty += UiKit.line_h(self, 17, true)
	var lines := [ArmyPresets.line(ult)] if ult_lines > 0 else []
	if full:
		lines.append("Charges in ~%d s (at least %d s); enemy kills speed it up" % [int(Rules.ult_charge_time(ult)), int(Rules.ult_min_time(ult))])
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


var _skill_tip := ""                               # SKILLS: the skill whose description popup is open ("" none)
var _tile_fs := 14.0                               # SKILLS: the one tile font (all 14 tiles)
var _tile_ic := 40.0                               # SKILLS: the one tile icon size


func show_skills(slot: String = "active") -> void:
	## ARMIES > SKILLS is a tab of ARMIES since the split (2026-11-05); old callers land on it.
	if not _skills_args:                              # screenshot args: --skills-slot=map, --skills-tip=<id>
		_skills_args = true
		for a in OS.get_cmdline_user_args():
			if a == "--skills-slot=map":
				slot = "map"
			elif a.begins_with("--skills-tip="):
				_skill_tip = a.substr(13)
	_skills_slot = slot
	_army_tab = "skills"
	show_armies()


func _skills_body(r: Rect2, slot: String) -> void:
	## Every skill on one screen (round 2c): the fixed ultimate strip, then the ACTIVE and MAP pools as icon + name tiles;
	## a tap equips (locked: no change) and opens the description popup.
	var acc := UiKit.accent(_army)
	var x := r.position.x
	var w := r.size.x
	var top := r.position.y
	var lo := ArmyPresets.loadout_for(_army)
	var bot := r.end.y
	var gap := 10.0
	var lh := UiKit.line_h(self, 13, true)
	# the ultimate: one strip (tap: its description)
	var ult: String = Rules.FACTION_ULTIMATE_ID[_army]
	var uh := UiKit.tap_h(self, 50.0)
	var rsw := UiKit.text_w(self, "RESET", 14, true) + 34.0      # ARMIES SPLIT: RESET (to the default preset) beside it
	var rs := UiKit.btn(self, "RESET", Vector2(x + w - rsw, top), Vector2(rsw, 50), func():
		ArmyPresets.reset(_army)
		_preset_changed()
		show_armies(), "tertiary", _army, 14)
	rs.disabled = ArmyPresets.is_default(_army)
	var ub := UiKit.btn(self, "", Vector2(x, top), Vector2(w - rsw - 10.0, uh), func(): _toggle_tip(ult, slot), "secondary", _army)
	ub.add_child(UiKit.rect(Vector2(0, 8.0), Vector2(3.0, ub.size.y - 16.0), UiKit.STAR))
	var uic := ub.size.y - 12.0
	_icon_box(ult, Vector2(12.0, 6.0), uic, UiKit.STAR, ub)
	var ut := UiKit.label(self, ArmyPresets.skill_name(ult).to_upper(), 17, UiKit.INK, true)
	ut.position = Vector2(12.0 + uic + 14.0, (ub.size.y - UiKit.line_h(self, 17, true)) / 2.0)
	ub.add_child(ut)
	var uk := UiKit.label(self, "~%d s CHARGE" % int(Rules.ult_charge_time(ult)), 12, UiKit.STAR, true, 2)   # name + charge only (Daniele 2026-11-05)
	uk.position = Vector2(ut.position.x + UiKit.text_w(self, ut.text, 17, true) + 18.0, (ub.size.y - UiKit.line_h(self, 12, true)) / 2.0)
	ub.add_child(uk)
	var tile_rects := {}                               # id -> its tile's rect (the popup sits next to it)
	tile_rects[ult] = Rect2(ub.position, ub.size)
	var y := top + ub.size.y + 12.0
	# the pools: a heading line each, then their tiles; rows share the height left
	var pools := [["active", "ACTIVE SKILL  ·  PICK ONE", "combat skills, every map", Rules.ACTIVE_SKILLS],
			["map", "MAP SKILL  ·  PICK ONE", "network skills; relay skills need a map with relays", Rules.MAP_SKILLS]]
	var min_tw := UiKit.tap_h(self, 44.0) * 1.5        # one row per pool where it fits (names shrink to fit)
	var plan := []                                     # [pool, cols, rows]
	var total_rows := 0
	for pool in pools:
		var ids: Array = pool[3]
		var rows := 1
		while ceili(ids.size() / float(rows)) * (min_tw + gap) - gap > w and rows < ids.size():
			rows += 1
		plan.append([pool, ceili(ids.size() / float(rows)), rows])
		total_rows += rows
	var free_h := bot - y - pools.size() * (lh + 6.0 + 10.0) - gap * (total_rows - pools.size())
	var th := clampf(floorf(free_h / total_rows), UiKit.tap_h(self, 44.0), UiKit.tap_h(self, 44.0) * 2.2)
	# ONE icon size and ONE font for all 14 tiles (Daniele 2026-11-05): the font is the largest at which every name fits
	# its narrowest tile in at most two lines (whole words), and every tile keeps room for two lines under its icon
	var tw_min := INF
	for pl in plan:
		tw_min = minf(tw_min, floorf((w - gap * (pl[1] - 1)) / pl[1]))
	var all_ids: Array = Rules.ACTIVE_SKILLS + Rules.MAP_SKILLS
	_tile_fs = 15.0
	while _tile_fs > 9.0 and not all_ids.all(func(i): return _name_lines(ArmyPresets.skill_name(i).to_upper(), _tile_fs, tw_min - 12.0) <= 2):
		_tile_fs -= 0.5
	_tile_ic = clampf(th - UiKit.line_h(self, _tile_fs, true) * 2.0 - 12.0, 18.0, 64.0)
	for pl in plan:
		var pool: Array = pl[0]
		var ps: String = pool[0]
		var cols: int = pl[1]
		var ids: Array = pool[3]
		var hx := x
		_say(pool[1], Vector2(hx, y), 13, acc if ps == slot else UiKit.INK, 0.0, true, 2)
		hx += UiKit.text_w(self, pool[1], 13, true) + pool[1].length() * 2.0 + 14.0
		_say(pool[2], Vector2(hx, y), 13, UiKit.MUTED)
		y += lh + 6.0
		var tw := floorf((w - gap * (cols - 1)) / cols)
		for i in range(ids.size()):
			var id: String = ids[i]
			var p := Vector2(x + (i % cols) * (tw + gap), y + (i / cols) * (th + gap))
			_skill_tile(id, ps, lo[ps] == id, p, Vector2(tw, th), slot)
			tile_rects[id] = Rect2(p, Vector2(tw, th))
		y += pl[2] * (th + gap) - gap + 10.0
	if _skill_tip != "" and tile_rects.has(_skill_tip):
		_skill_popup(_skill_tip, tile_rects[_skill_tip], slot)


func _toggle_tip(id: String, slot: String) -> void:
	_skill_tip = "" if _skill_tip == id else id
	show_skills(slot)


func _skill_tile(id: String, slot: String, chosen: bool, pos: Vector2, dims: Vector2, page_slot: String) -> void:
	## A pool skill as a tile: its icon over its name; EQUIPPED lit in the accent with a tick, LOCKED dimmed with a lock
	## line. A tap equips it (locked: no change) and opens its description popup.
	var acc := UiKit.accent(_army)
	var locked := not Progression.is_unlocked("skill:" + id)
	var b := UiKit.btn(self, "", pos, dims, func():
		if not locked:
			ArmyPresets.set_pick(_army, slot, id)
			_preset_changed()
		_skill_tip = id
		show_skills(page_slot), "selected" if chosen else "secondary", _army)
	var h := b.size.y
	var nfs := _tile_fs                                # shared by every tile (_skills_body picks it)
	var nm_t := ArmyPresets.skill_name(id).to_upper()
	var wrap := _name_lines(nm_t, nfs, dims.x - 12.0) > 1
	var nl := UiKit.line_h(self, nfs, true) * 2.0     # two lines' room on every tile, so icons line up
	var ic := _tile_ic
	var col := acc if chosen else (Color("6f8792") if locked else Color("c9dbe3"))
	var top := (h - ic - nl - 4.0) / 2.0
	_icon_box(id, Vector2((dims.x - ic) / 2.0, top), ic, col, b)
	var nm := UiKit.label(self, nm_t, nfs, acc if chosen else (UiKit.MUTED if locked else UiKit.INK), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	nm.max_lines_visible = 2
	nm.position = Vector2(4.0, top + ic + 4.0)
	nm.custom_minimum_size = Vector2(dims.x - 8.0, 0)
	nm.size = Vector2(dims.x - 8.0, nl)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(nm)
	var cs := UiKit.line_h(self, 12, true) * 0.8
	if chosen:
		_check(b, Vector2(dims.x - cs - 8.0, 8.0), cs, acc)
	elif locked:
		var lk := UiKit.label(self, "LOCKED", 11, LOCK_COL, true, 1)
		lk.position = Vector2(8.0, 6.0)
		b.add_child(lk)


func _name_lines(t: String, fs: float, room: float) -> int:
	## How many lines a tile name needs at font fs in width room, wrapping on whole words (99 = a word doesn't fit).
	var lines := 1
	var cur := ""
	for word in t.split(" "):
		if UiKit.text_w(self, word, fs, true) > room:
			return 99
		var tryl := word if cur == "" else cur + " " + word
		if UiKit.text_w(self, tryl, fs, true) > room:
			lines += 1
			cur = word
		else:
			cur = tryl
	return lines


func _skill_popup(id: String, at: Rect2, slot: String) -> void:
	## The description popup beside a tile: name, cooldown / charge, NEEDS RELAYS, the full sentence, its state (UNLOCK
	## for a locked skill). A tap outside closes it.
	var catcher := UiKit.rect(Vector2(-safe.x, -safe.y), content.size + Vector2(safe.x + safe.z, safe.y + safe.w), Color(0, 0, 0, 0.25))
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_skill_tip = ""
			show_skills.call_deferred(slot))
	content.add_child(catcher)
	var sk: Dictionary = Rules.SKILLS[id]
	var acc := UiKit.accent(_army)
	var is_ult: bool = id == Rules.FACTION_ULTIMATE_ID[_army]
	var locked: bool = not is_ult and not Progression.is_unlocked("skill:" + id)
	var lo := ArmyPresets.loadout_for(_army)
	var equipped: bool = is_ult or lo.get("active", "") == id or lo.get("map", "") == id
	var pw := minf(content.size.x - 40.0, maxf(at.size.x * 2.2, 520.0))
	var iw := pw - 36.0
	var desc := str(sk["desc"])
	var sub := ("~%d s CHARGE, ENEMY KILLS SPEED IT UP" % int(Rules.ult_charge_time(id))) if is_ult else ("%s CD" % ArmyPresets.cd_text(id))
	if sk.get("needs_relays", false):
		sub += "  ·  NEEDS RELAYS"
	var state := "ULTIMATE  ·  FIXED" if is_ult else ("EQUIPPED" if equipped else ("LOCKED  ·  " + Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false) if locked else ""))
	var bh := UiKit.tap_h(self, 44.0)
	var ph := 16.0 + UiKit.line_h(self, 18, true) + UiKit.line_h(self, 13, true) + 8.0 + UiKit.text_h(self, desc, 14, iw) + 10.0 \
			+ (bh if locked else UiKit.line_h(self, 13, true)) + 16.0
	var px := clampf(at.position.x + at.size.x / 2.0 - pw / 2.0, 20.0, content.size.x - 20.0 - pw)
	var py := at.end.y + 8.0                            # under the tile, or over it when it doesn't fit
	if py + ph > content.size.y - 10.0:
		py = maxf(10.0, at.position.y - 8.0 - ph)
	var panel := UiKit.panel(self, Vector2(px, py), Vector2(pw, ph), _army, true)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var y := py + 16.0
	_say(ArmyPresets.skill_name(id).to_upper(), Vector2(px + 18.0, y), 18, UiKit.INK, 0.0, true)
	y += UiKit.line_h(self, 18, true)
	_say(sub, Vector2(px + 18.0, y), 13, UiKit.STAR if is_ult else acc, 0.0, true)
	y += UiKit.line_h(self, 13, true) + 8.0
	y += _say(desc, Vector2(px + 18.0, y), 14, UiKit.INK, iw) + 10.0
	if locked:
		var ut := "UNLOCK  ·  " + Progression.amount_text(int(Rules.PRICES["skill"]["soft"]), "soft", false)
		var uw := UiKit.text_w(self, ut, 14, true) + 40.0
		UiKit.btn(self, ut, Vector2(px + 18.0, y), Vector2(uw, 44), func():
			_skill_tip = ""
			_buy_prompt("skill:" + id, ArmyPresets.skill_name(id).to_upper(),
					"Unlocks %s for every faction's loadout. Skills are earned with SCRAP only." % ArmyPresets.skill_name(id),
					func(): show_skills(slot)), "primary", _army, 14)
	elif state != "":
		_say(state, Vector2(px + 18.0, y), 13, acc, 0.0, true, 2)


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


func _save_armies() -> void:
	## ROUND 4: ARMIES' SAVE (each tap already saves the loadout): from the ARMY page or a lobby, the faction on show
	## becomes yours and you land back in the lobby (PLAY VS AI or the room); elsewhere, the page that opened it.
	var back := _army_back
	if back == show_factions or back == show_setup or Net.in_room():
		faction = _army if _army != "" else faction
		_army_back = Callable()
		_army = ""
		_choose_faction()
		return
	_leave_armies()


func _leave_armies() -> void:
	var back := _army_back
	_army_back = Callable()
	_army = ""
	if Net.in_room():
		ArmyPresets.send_to(Net, faction)
	back.call()


# ------------------------------------------------------------------ ARMIES > COSMETICS (0.19.0, spec E/I; UI: screen 08)
const COSMETIC_FAMILIES := ["vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const COSMETIC_FAMILY_LABEL := {"territory": "TERRITORY", "vat": "VAT", "machinegoon": "GOOGATLING", "laser": "LASER",
		"forge": "FORGE", "monster_hub": "MONSTER HUB", "monster": "MONSTER"}
const WARDROBE_CATS := ["territory", "vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const TERRITORY_LOOKS := {"neon": ["NEON", "Your colour in neon on the decks, piers and platform rims you hold."],
		"goo": ["GOO", "A slab of goo in your player colour over everything you hold; it spreads as you capture."]}
var _ward_cat := "vat"                             # COSMETICS: the open category ("territory" or a Cosmetics family)
var _ward_sel := {}                                # COSMETICS: category -> the look on preview (not equipped yet)
var _ward_tier := 2                                # COSMETICS: the tier the vat / Machinegoon preview shows
var _ward_args := false                            # COSMETICS: the screenshot args below were read


func show_cosmetics(f: String = "") -> void:
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
			elif arg.begins_with("--wardrobe-wear="):   # <family>:<id> worn, in a throwaway save (screenshots)
				ArmyPresets.path = "user://shot-armies.cfg"
				var fw := arg.substr(16).split(":")
				ArmyPresets.set_cosmetic_pick(f if f != "" else (_army if _army != "" else faction), fw[0], fw[1])
	if f != "" and f != _army:
		_ward_sel = {}                                  # another faction: its own saved picks
	if f != "":
		_army = f
	_army_tab = "customize"
	show_armies()


const WARD_TILE := {"territory": "NEON", "vat": "VAT", "forge": "FORGE", "laser": "LASER", "machinegoon": "GATLING",
		"monster_hub": "HUB", "monster": "MONSTER"}
const WARD_TILE_AT := [[15, 83], [83, 83], [15, 133], [83, 133], [15, 183], [83, 183], [15, 233]]   # 45A2 approved 12.5 pt fit
const WARD_CARD_AT := [[354, 83], [466, 83], [578, 83], [690, 83], [354, 187], [466, 187], [578, 187], [690, 187]]


func _customize_body(st: Kit45.Stage) -> void:
	## CUSTOMIZE = the remake (43B-five-screen-remake/ARMIES-CUSTOMIZE, 45A2 approved 12.5 pt fit, 45B paint): the category
	## tiles (what each family wears now, in its icon well), the preview cabinet "VEX / VAT  DEFAULT" with the LIVE 3D model
	## on the seat-lit pedestal and the T1-T4 tier tabs (Daniele 11-18), eight skin cards (rendered thumbnails, name face,
	## LOCKED tag, EQUIPPED tag), the info strip and EQUIP / UNLOCK. Every look of a family fits at once (no scrolling).
	var cat := _ward_cat if _ward_cat in _ward_cats() else "vat"
	var looks: Array = TERRITORY_LOOKS.keys() if cat == "territory" else Cosmetics.OPTIONS[cat]
	var played := ArmyPresets.cosmetic_loadout_for(_army)          # what plays (a locked pick plays as the default)
	var saved := ArmyPresets.cosmetic_loadout_for(_army, true)     # the picks as saved
	var equipped: String = ArmyPresets.core_territory if cat == "territory" else str(played[cat])
	var sel := str(_ward_sel.get(cat, ArmyPresets.core_territory if cat == "territory" else str(saved[cat])))
	if not sel in looks:
		sel = equipped
	var seat := Kit45.seat()
	# the categories
	var cats := _ward_cats()
	# 16:9 phones (Daniele 11-18 "Keep 12.5 pt minimum"): where a tile's word (MONSTER) does not fit its 64 pt tile at the
	# floor, the tiles grow evenly to 74 x 53 pt (the free band under them takes the height) and the preview cabinet gives
	# them the width (195 -> 177 pt, evenly). Other sizes keep the 45A2 layout.
	var tg := 1.0
	var fl := Kit45.floor_px(self)
	if fl > 0.0:
		for cc in cats:
			if UiKit.BODY.get_string_size(str(WARD_TILE.get(cc, "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fl))).x > 56.0 * st.u:
				tg = 74.0 / 64.0
	var cx := 153.0 if tg == 1.0 else 171.0              # the cabinet's left edge and its scale
	var cf := 1.0 if tg == 1.0 else 177.0 / 195.0
	var C := func(x: float, y: float, w: float, h: float) -> Rect2: return Rect2(cx + x * cf, 83.0 + y * cf, w * cf, h * cf)
	for i in range(mini(cats.size(), WARD_TILE_AT.size())):
		var cc: String = cats[i]
		var at: Array = WARD_TILE_AT[i]
		var tx: float = at[0] if tg == 1.0 else (15.0 if at[0] < 50 else 93.0)
		var ty: float = at[1] if tg == 1.0 else 83.0 + (float(at[1]) - 83.0) / 50.0 * 57.0
		var tb := st.key("CUST-CATEGORY-TILE", tx, ty, 64 * tg, 46 * tg, str(WARD_TILE.get(cc, cc.to_upper())), func():
			_ward_cat = cc
			show_cosmetics(), cc == cat, false, "64x46pt")
		tb.u = st.u * tg                                 # (its slots scale with it)
		tb.tooltip_text = COSMETIC_FAMILY_LABEL[cc]
		tb.size_pt = 12.5
		tb.label_slot = true
		var now := ArmyPresets.core_territory if cc == "territory" else str(played[cc])
		if cc == "territory":
			var wl := Kit45.Txt.new()
			wl.m = self
			wl.text = str(TERRITORY_LOOKS[now][0])
			wl.size_cu = 9.0 * st.u
			wl.col = seat
			wl.align = 1
			wl.position = tb.art.position + Vector2(4, 4) * tb.u
			wl.size = Vector2(56, 20) * tb.u
			tb.add_child(wl)
		else:
			var pic := LookThumbs.rect(cc, now, _army, Vector2(28, 20) * tb.u)
			pic.position = tb.art.position + Vector2(18, 4) * tb.u
			tb.add_child(pic)
	# the preview cabinet: title, live 3D model on the pedestal, tier tabs
	var cr: Rect2 = C.call(0, 0, 195, 195)
	st.piece("CUST-PREVIEW-CABINET", cr.position.x, cr.position.y, cr.size.x, cr.size.y, "STATIC", "195x195pt")
	var kt: String = ("ALL FACTIONS" if cat == "territory" else UiKit.NAMES[_army]) + "  /  " + COSMETIC_FAMILY_LABEL[cat]
	var kr: Rect2 = C.call(18, 9, 157, 14)
	if fl > 0.0 and UiKit.BODY.get_string_size(kt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fl))).x > kr.size.x * st.u:
		kt = COSMETIC_FAMILY_LABEL[cat]                  # 12.5 pt floor: the family alone where the faction does not fit too
	st.txt(kt, kr.position.x, kr.position.y, kr.size.x, kr.size.y, 9.0, Kit45.KICK)
	var nr: Rect2 = C.call(18, 23, 157, 18)
	st.txt(_ward_look_name(cat, sel).to_upper(), nr.position.x, nr.position.y, nr.size.x, nr.size.y, 14.0 * cf, UiKit.INK, true)
	var pr: Rect2 = C.call(29.5, 148, 136, 31)
	var ped := st.piece("PEDESTAL-RING", pr.position.x, pr.position.y, pr.size.x, pr.size.y, "STATIC", "136x31pt")
	ped.tints = {"seat": seat}
	var vp: Rect2 = C.call(10, 49, 175, 160)
	var vr := st.R(vp.position.x, vp.position.y, vp.size.x, vp.size.y)   # the model's feet on the pedestal ring
	var tiers := {"vat": 4, "machinegoon": 3}.get(cat, 0) as int
	var pv: WardrobePreview = null
	if cat == "territory":
		var trr: Rect2 = C.call(10, 67, 175, 60)
		st.txt(str(TERRITORY_LOOKS[sel][0]), trr.position.x, trr.position.y, trr.size.x, trr.size.y, 34.0 * cf, seat, true, 1)
	else:
		var tier := clampi(_ward_tier, 1, tiers) if tiers > 0 else 0
		pv = WardrobePreview.make(cat, sel, _army, tier, vr.size)
		pv.plinth = false                              # the 45B pedestal ring (seat colour) is the plinth
		pv.accent = seat                               # neon = seat colour (COLOUR RULE 11-15)
		pv.position = vr.position
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (it reaches over the tier tabs: taps go through)
		st.add_child(pv)
	if tiers > 0:                                       # in place: the preview switches its model, no rebuild
		var tabs := []
		for t in range(1, tiers + 1):
			var tt: int = t
			var tbx := st.key("TIER-TAB", cx + (2.0 + (t - 1) * 48.0) * cf, 297.5, 45 * cf, 22 * cf, "T%d" % t, Callable(), t == clampi(_ward_tier, 1, tiers), false, "45x22pt")
			tbx.u = st.u * cf
			tbx.tooltip_text = "TIER %d" % t
			tabs.append(tbx)
			tbx.pressed.connect(func():
				_ward_tier = tt
				if pv != null:
					pv.set_tier(tt)
				for i in range(tabs.size()):
					tabs[i].selected = i + 1 == tt
					tabs[i].queue_redraw())
	# the looks
	for i in range(mini(looks.size(), WARD_CARD_AT.size())):
		var lid: String = looks[i]
		var at: Array = WARD_CARD_AT[i]
		var ls := _ward_state(cat, lid, equipped)
		var card := st.key("CUST-SKIN-CARD", at[0], at[1], 107, 100, _ward_look_name(cat, lid).to_upper(), func():
			_ward_sel[cat] = lid
			show_cosmetics(), lid == sel, false, "107x100pt")
		card.label_slot = true
		card.size_pt = 12.5
		if ls["locked"] and lid != sel:
			card.lock_state = "LOCKED"
		elif ls["equipped"]:
			card.lock_state = "EQUIPPED"                  # (its tag says so; the seat rim lights it too)
		var rw := Rect2(card.art.position + Vector2(6, 6) * st.u, Vector2(95, 65) * st.u)
		if ls["locked"] or ls["equipped"]:              # designer 11 FIX 5: the tag keeps the top band, the picture below it
			rw = Rect2(card.art.position + Vector2(6, 30) * st.u, Vector2(95, 41) * st.u)
		if cat == "territory":
			var wl2 := Kit45.Txt.new()
			wl2.m = self
			wl2.text = str(TERRITORY_LOOKS[lid][0])
			wl2.size_cu = 22.0 * st.u
			wl2.col = seat
			wl2.head = true
			wl2.align = 1
			wl2.position = rw.position
			wl2.size = rw.size
			card.add_child(wl2)
		else:
			var pic2 := LookThumbs.rect(cat, lid, _army, rw.size)
			pic2.position = rw.position
			if ls["locked"]:
				pic2.modulate = Color(1, 1, 1, 0.45)     # LOCKED: the render dimmed under its tag
			card.add_child(pic2)
		if ls["locked"]:
			var tag := Kit45.Piece.new()
			tag.fam = "LOCKED-TAG"
			tag.key = "68x19pt"
			tag.u = st.u
			tag.position = card.art.position + Vector2(8.75, 9) * st.u
			tag.size = Vector2(68, 19) * st.u
			card.add_child(tag)
			var tl := Kit45.Txt.new()
			tl.m = self
			tl.text = "LOCKED"
			tl.size_cu = 9.0 * st.u
			tl.col = UiKit.INK
			tl.align = 1
			tl.position = tag.position + Vector2(6, 1.5) * st.u
			tl.size = Vector2(56, 16) * st.u
			card.add_child(tl)
		elif ls["equipped"]:
			var et := Kit45.Txt.new()                  # the EQUIPPED state's tag carries its word
			et.m = self
			et.text = "EQUIPPED"
			et.size_cu = 9.0 * st.u
			et.col = Kit45.INK_CREAM                    # (cream on the copper EQUIPPED tag, 45B2)
			et.align = 1
			et.position = card.art.position + Vector2(12.25, 10.5) * st.u
			et.size = Vector2(65.5, 16) * st.u
			card.add_child(et)
	# the info strip and the action
	var ls2 := _ward_state(cat, sel, equipped)
	var ih := 33.0 if tg == 1.0 else 40.0                # 16:9: the 9-slice strip holds two floor-size lines (the band under it is free)
	st.piece("INFO-STRIP", 354, 296, 291, ih, "STATIC", "291x33pt")
	st.txt(_ward_detail(cat, sel, ls2), 367, 299, 270, ih - 6.0, 9.0, LOCK_COL if ls2["locked"] else UiKit.MUTED, false, 0, 2)
	var ky := 296.0 + (ih - 33.0) / 2.0
	var item := "" if cat == "territory" else Progression.cosmetic_item(cat, sel, _army)
	if ls2["equipped"]:
		st.key("PRIMARY-WIDE", 664, ky, 133, 33, "EQUIPPED", Callable(), false, true, "133x33pt")
	elif ls2["locked"] and not Progression.price(item).is_empty():   # PROGRESSION: UNLOCK where it can be bought
		st.key("PRIMARY-WIDE", 664, ky, 133, 33, "UNLOCK", func():
			_buy_prompt(item, _ward_look_name(cat, sel).to_upper(), "A look only: play is unchanged.",
					func(): show_cosmetics()), true, false, "133x33pt")
	elif ls2["locked"]:
		st.key("PRIMARY-WIDE", 664, ky, 133, 33, "LOCKED", Callable(), false, true, "133x33pt")
	else:
		st.key("PRIMARY-WIDE", 664, ky, 133, 33, "EQUIP", func():
			if cat == "territory":
				ArmyPresets.set_core_territory(sel)
			else:
				ArmyPresets.set_cosmetic_pick(_army, cat, sel)
				_preset_changed()
			_ward_sel.erase(cat)
			show_cosmetics(), true, false, "133x33pt")


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
		UiKit.hero_neon(art, tf, _viewer_col())
		b.add_child(art)
		UiKit.emblem_badge(b, tf, s * 0.36)


func _ward_look_name(cat: String, id: String) -> String:
	if cat == "territory":
		return TERRITORY_LOOKS[id][0]
	return Cosmetics.label(cat, id, _army)


func _ward_cats() -> Array:
	## CUSTOMIZE's categories: WARDROBE_CATS minus the families archived out of the game (Rules.ARCHIVED_FAMILIES).
	## The monster hub goes with an archived monster (Daniele 2026-11-05: "Hide both").
	var gone: Array = Rules.ARCHIVED_FAMILIES.duplicate()
	if "monster" in gone:
		gone.append("monster_hub")
	return WARDROBE_CATS.filter(func(c): return not c in gone)


func _ward_rail(pos: Vector2, h: float, cat: String, played: Dictionary) -> float:
	## The categories as model icons (Daniele 2026-11-05): each tile shows what that family wears now - its default
	## model, or the equipped look's - so the rail reads as your whole army at a glance; TERRITORY shows its word
	## (NEON / GOO). All seven fit in a grid of square tiles (2 or 3 columns); the open one lit. Returns the width used.
	var gap := 6.0
	var cats := _ward_cats()
	var n := cats.size()
	var rows := 3                                       # three rows: the tile size never changes, the columns follow
	var cols := ceili(n / float(rows))                  # the categories (an archived family takes its column's room)
	var cell := floorf(minf((h - gap * (rows - 1)) / rows, UiKit.tap_h(self, 44.0) * 2.2))
	for i in range(n):
		var cc: String = cats[i]
		var now := ArmyPresets.core_territory if cc == "territory" else str(played[cc])
		var b := UiKit.btn(self, "", pos + Vector2((i % cols) * (cell + gap), (i / cols) * (cell + gap)), Vector2(cell, cell), func():
			_ward_cat = cc
			show_cosmetics(), "selected" if cc == cat else "secondary", _army)
		b.tooltip_text = COSMETIC_FAMILY_LABEL[cc]
		if cc == "territory":
			var word: String = TERRITORY_LOOKS[now][0]
			var fs := 16.0
			while fs > 10.0 and UiKit.text_w(self, word, fs, true) > cell - 12.0:
				fs -= 1.0
			var t := UiKit.label(self, word, fs, UiKit.accent(_army), true, 1)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			t.position = Vector2.ZERO
			t.size = Vector2(cell, cell)
			b.add_child(t)
		else:
			b.add_child(_model_well(Vector2(4.0, 4.0), Vector2(cell - 8.0, cell - 8.0)))
			var pic := LookThumbs.rect(cc, now, _army, Vector2(cell - 8.0, cell - 8.0))
			pic.position = Vector2(4.0, 4.0)
			b.add_child(pic)
	return cols * (cell + gap) - gap


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
	## The look on preview (round 3d, a narrow column): "VEX / VAT" and the look's name, the turning model (TERRITORY:
	## its word) and the tier chips (vat T1-T4, Machinegoon T1-T3) under it. The look's line and EQUIP / UNLOCK sit
	## under the looks (_ward_looks_grid).
	var acc := UiKit.accent(_army)
	UiKit.panel(self, pos, dims, _army)
	var ix := pos.x + 14.0
	var iw := dims.x - 28.0
	var y := pos.y + 10.0
	var kt: String = ("ALL FACTIONS" if cat == "territory" else UiKit.NAMES[_army]) + " / " + COSMETIC_FAMILY_LABEL[cat]
	var ksp := 2 if UiKit.text_w(self, kt, 12, true) + kt.length() * 2.0 <= iw else 0
	var k := UiKit.label(self, kt, 12, acc, true, ksp)
	k.clip_text = true
	k.size = Vector2(iw, UiKit.line_h(self, 12, true))
	_shell_add(k, Vector2(ix, y))
	y += UiKit.line_h(self, 12, true)
	var nm := _ward_look_name(cat, sel)
	var nfs := 22.0
	while nfs > 13.0 and UiKit.text_w(self, nm, nfs, true) > iw:
		nfs -= 1.0
	_shell_add(UiKit.label(self, nm, nfs, UiKit.INK, true), Vector2(ix - 1.0, y))
	y += UiKit.line_h(self, 22, true) + 4.0
	var tiers := {"vat": 4, "machinegoon": 3}.get(cat, 0) as int
	var ch_h := UiKit.tap_h(self, 44.0)
	var foot := (ch_h + 10.0) if tiers > 0 else 0.0
	var vh := pos.y + dims.y - 10.0 - foot - y
	if cat != "territory":                              # a model stands on the grey well (dark and white skins both read)
		_shell_add(_model_well(Vector2.ZERO, Vector2(iw, vh)), Vector2(ix, y))
	else:
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
	if cat == "territory":
		var big := UiKit.label(self, TERRITORY_LOOKS[sel][0], 44, acc, true, 4)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.size = Vector2(iw, big.get_minimum_size().y)
		_shell_add(big, Vector2(ix, y + (vh - big.size.y) / 2.0))
	else:
		var tier := clampi(_ward_tier, 1, tiers) if tiers > 0 else 0
		pv = WardrobePreview.make(cat, sel, _army, tier, Vector2(iw, vh))
		_shell_add(pv, Vector2(ix, y))
	if tiers > 0:                                       # in place: the preview switches its model, no rebuild
		var chips := []
		var cgap := 6.0
		var cw := floorf((iw - cgap * (tiers - 1)) / tiers)
		var cy := pos.y + dims.y - 10.0 - ch_h
		for t in range(1, tiers + 1):
			var tt: int = t
			var ch := UiKit.btn(self, "T%d" % t, Vector2(ix + (t - 1) * (cw + cgap), cy), Vector2(cw, 44), Callable(),
					"selected" if t == clampi(_ward_tier, 1, tiers) else "secondary", _army, 14)
			ch.tooltip_text = "TIER %d" % t
			chips.append(ch)
			ch.pressed.connect(func():
				_ward_tier = tt
				pv.set_tier(tt)
				for i in range(chips.size()):
					UiKit.style_button(chips[i], "selected" if i + 1 == tt else "secondary", _army))


func _model_well(pos: Vector2, dims: Vector2) -> TextureRect:
	## The mid-grey backdrop every model picture sits on (Daniele 2026-11-05: "give them a gray background so they are
	## easier to see, especially if they are dark ... works well also for grayish/white skins"): a slate grey, lighter
	## in the middle - dark kits read against it, and white / bone skins stay brighter than its lightest point.
	var grad := Gradient.new()
	grad.set_color(0, Color("6b7782"))
	grad.set_color(1, Color("444e57"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 1.05)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = dims
	return r


func _ward_action(pos: Vector2, dims: Vector2, cat: String, sel: String, equipped: String) -> void:
	## EQUIP / EQUIPPED / UNLOCK / LOCKED for the look on preview.
	var acc := UiKit.accent(_army)
	var st := _ward_state(cat, sel, equipped)
	var item := "" if cat == "territory" else Progression.cosmetic_item(cat, sel, _army)
	if st["equipped"]:
		var eb := UiKit.btn(self, "EQUIPPED", pos, dims, Callable(), "selected", _army, 16)
		eb.disabled = true
		eb.add_theme_stylebox_override("disabled", eb.get_theme_stylebox("normal"))
		eb.add_theme_color_override("font_disabled_color", acc)
	elif st["locked"] and not Progression.price(item).is_empty():   # PROGRESSION: UNLOCK where it can be bought
		UiKit.btn(self, "UNLOCK", pos, dims, func():
			_buy_prompt(item, _ward_look_name(cat, sel).to_upper(), "A look only: play is unchanged.",
					func(): show_cosmetics()), "primary", _army, 16)
	elif st["locked"]:
		var lb := UiKit.btn(self, "LOCKED", pos, dims, Callable(), "secondary", _army, 16)
		lb.disabled = true
	else:
		UiKit.btn(self, "EQUIP", pos, dims, func():
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
		out = TERRITORY_LOOKS[sel][1]                  # (the stage says ALL FACTIONS)
	elif st["locked"] or not Progression.owns(Progression.cosmetic_item(cat, sel, _army)) and str(st["line"]) != "":
		var item := Progression.cosmetic_item(cat, sel, _army)
		out = "UNLOCK: " + _cosmetic_path(cat, sel)
		var price := Progression.price(item)
		var costs := []
		for cur in ["soft", "premium"]:
			if price.has(cur):
				costs.append(Progression.amount_text(int(price[cur]), cur, false))
		if not costs.is_empty():
			out += "  ·  " + " OR ".join(costs)
		if not st["locked"] and not st["equipped"]:     # (worn already: nothing to add)
			out += "  ·  OPEN WHILE TESTING"
	else:
		out = "A look only: play is unchanged."
		if cat in ["monster_hub", "monster"] or sel == "faction":
			out += " Made for %s." % UiKit.NAMES[_army]
	if not ArmyPresets.saved:
		out += "\nThis browser keeps no storage: your picks last until the page closes."
	return out


func _ward_looks_grid(pos: Vector2, dims: Vector2, cat: String, looks: Array, sel: String, equipped: String) -> void:
	## Every look of the category at once (no pages): each its model picture over its name (TERRITORY: its word); the
	## one on preview lit, the equipped one with a check, a locked one dimmed with LOCKED. Tap: preview it. Under the
	## grid: the look's line (what it is / how to unlock it) and EQUIP / UNLOCK.
	var acc := UiKit.accent(_army)
	var gap := 8.0
	var ah := UiKit.tap_h(self, 44.0)
	var gh := dims.y - ah - 10.0
	var rows := 1 if looks.size() <= 4 else 2
	var cols := ceili(looks.size() / float(rows))
	var tw := floorf((dims.x - gap * (cols - 1)) / cols)
	var th := floorf((gh - gap * (rows - 1)) / rows)
	var nl := UiKit.line_h(self, 13, true)
	for i in range(looks.size()):
		var lid: String = looks[i]
		var s := _ward_state(cat, lid, equipped)
		var b := UiKit.btn(self, "", pos + Vector2((i % cols) * (tw + gap), (i / cols) * (th + gap)), Vector2(tw, th), func():
			_ward_sel[cat] = lid
			show_cosmetics(), "selected" if lid == sel else "secondary", _army)
		var nm := _ward_look_name(cat, lid)
		var fs := 13.0
		while fs > 9.0 and UiKit.text_w(self, nm, fs, true) > tw - 10.0:
			fs -= 0.5
		var ps := minf(th - nl - 14.0, tw - 10.0)
		if cat == "territory":
			var wl := UiKit.label(self, TERRITORY_LOOKS[lid][0], 24, acc if lid == equipped else UiKit.INK, true, 2)
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			wl.size = Vector2(tw, th)
			wl.position = Vector2.ZERO
			b.add_child(wl)
			if s["equipped"]:
				_check(b, Vector2(tw - UiKit.line_h(self, 12, true) * 0.75 - 6.0, 6.0), UiKit.line_h(self, 12, true) * 0.75, acc)
			continue
		else:
			var well := _model_well(Vector2(6.0, 6.0), Vector2(tw - 12.0, ps))   # the tile's width: the picture sits in it
			if s["locked"]:
				well.modulate = Color(1, 1, 1, 0.6)
			b.add_child(well)
			var pic := LookThumbs.rect(cat, lid, _army, Vector2(ps, ps))
			pic.position = Vector2((tw - ps) / 2.0, 6.0)
			if s["locked"]:
				pic.modulate = Color(1, 1, 1, 0.45)
			b.add_child(pic)
		var n := UiKit.label(self, nm, fs, UiKit.MUTED if s["locked"] else (acc if lid == sel else UiKit.INK), true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.position = Vector2(4.0, th - nl - 6.0)
		n.size = Vector2(tw - 8.0, nl)
		n.clip_text = true
		b.add_child(n)
		var cs := UiKit.line_h(self, 12, true) * 0.75
		if s["equipped"]:
			_check(b, Vector2(tw - cs - 6.0, 6.0), cs, acc)
		elif s["locked"]:
			var lk := UiKit.label(self, "LOCKED", 10, LOCK_COL, true, 1)
			lk.position = Vector2(6.0, 4.0)
			b.add_child(lk)
	# the foot: the look's line, then its action
	var st := _ward_state(cat, sel, equipped)
	var aw := floorf(dims.x * 0.34)
	var ay := pos.y + dims.y - ah
	var dw := dims.x - aw - 12.0
	var plate := Panel.new()                           # a dark plate: the line reads over the backdrop
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UiKit.sb(Color(UiKit.BASE, 0.88), Color(UiKit.FRAME, 0.9), 1, 6))
	plate.size = Vector2(dw, ah)
	_shell_add(plate, Vector2(pos.x, ay))
	dw -= 20.0
	var dl := UiKit.label(self, _ward_detail(cat, sel, st), 12, LOCK_COL if st["locked"] else UiKit.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(dw, 0)
	dl.size = Vector2(dw, ah)
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.max_lines_visible = 2
	_shell_add(dl, Vector2(pos.x + 10.0, ay))
	_ward_action(Vector2(pos.x + dims.x - aw, ay), Vector2(aw, ah), cat, sel, equipped)


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
			b.add_child(UiKit.rect(Vector2(9, 12.0), Vector2(3.0, th - 24.0), acc))
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
	_last_show = show_maps                  # a resize that changes the phone sizing rebuilds it (_fit)
	## MAP PICKER = the remake (45B sizes.json MAP-PICKER): CHOOSE A MAP, the mode keys + RECENT / ★ / RANDOM at the top
	## right, ten MAP-THUMB-CARDs (2 x 5 a page, the picked one SELECTED), CANCEL, ☆ (favourite) + the picked map's name
	## and detail, ‹ p / n › by CHOOSE (Daniele 11-04: 2 x 5 with ‹ › by CHOOSE, no scrolling).
	var room_host := Net.in_room() and Net.can_control()
	if Net.in_room():
		map_filter_mode = Net.mode                     # a room plays its own mode (the lobby's MODE sheet changes it)
	elif map_filter_mode == "all" or not map_filter_mode in _pool_modes():
		map_filter_mode = mode if mode in _pool_modes() else str(_pool_modes()[0])
	var st := _stage_page("OOZE / MATCH SETUP / MAP", "home", "CHOOSE A MAP", "", _cancel_pick, faction)
	var by_mode := func(md: String) -> Array:
		return maps.filter(func(e): return md in _modes_of(e["data"]) and (not Net.in_room() or e["path"] in Net.maps_for(Net.mode)))
	map_filter_type = "all"                            # ROUND 2b: no size tabs - 2 x 5 pages instead (Daniele)
	var shown := _filtered_maps()
	if not shown.is_empty() and not shown.any(func(e): return e["path"] == map_path):
		map_path = shown[0]["path"]                    # a tab without the picked map: pick its first
	if _map_list == "" and not shown.is_empty():
		mode = map_filter_mode                         # a mode tab sets up that mode
	# the top row: modes, RECENT, ★, RANDOM (KEY-SMALL 60 x 30, right-aligned)
	var keys := []
	for md in _pool_modes():
		keys.append(["mode", md])
	keys += [["list", "recent"], ["list", "favourites"], ["random", ""]]
	var kw := func(kk: Array) -> float: return 76.0 if kk[0] == "random" or kk[1] == "recent" else 60.0   # FIX 2: the next size for the long words
	var kx := 801.0
	for kk in keys:
		kx -= kw.call(kk) + 4.0
	for kk in keys:
		var kind: String = kk[0]
		var val: String = kk[1]
		var label := ""
		var lit := false
		var off := false
		var call := Callable()
		match kind:
			"mode":
				label = str(MODE_NAMES.get(val, val))
				lit = val == map_filter_mode and _map_list == ""
				off = (by_mode.call(val) as Array).is_empty() or (Net.in_room() and val != Net.mode)
				call = func():
					map_filter_mode = val
					map_filter_type = "all"
					_map_list = ""
					_map_page = 0
					show_maps()
			"list":
				label = "RECENT" if val == "recent" else "★ %d" % UiKit.map_list("favourites").size()
				lit = _map_list == val
				call = func():
					_map_list = "" if _map_list == val else val
					_map_page = 0
					show_maps()
			"random":
				label = "RANDOM"
				call = func():
					var pool := _filtered_maps()
					if not pool.is_empty():
						map_path = pool[randi() % pool.size()]["path"]
					_map_page = -1
					show_maps()
		var wide: bool = kw.call(kk) > 60.0
		var b := st.key("KEY-SMALL", kx, 38 if wide else 40, kw.call(kk), 34 if wide else 30, label, call, lit, off, "76x34pt" if wide else "60x30pt")
		b.size_pt = 12.5
		kx += kw.call(kk) + 4.0
	# the cards: 2 x 5 a page
	var per := 10
	var pages := maxi(1, ceili(shown.size() / float(per)))
	var sel_i := shown.map(func(e): return e["path"]).find(map_path)
	if _map_page < 0:                                  # opening: the page with the picked map
		_map_page = maxi(0, sel_i) / per
	_map_page = clampi(_map_page, 0, pages - 1)
	shown = shown.slice(_map_page * per, _map_page * per + per)
	if shown.is_empty():
		st.txt("No favourite maps yet: tap ☆ on a map to keep it here." if _map_list == "favourites"
				else ("No recent maps yet." if _map_list == "recent" else "No map matches."), 15, 90, 600, 20, 14.0, UiKit.MUTED)
	for k in range(shown.size()):
		var entry: Dictionary = shown[k]
		var m: Dictionary = entry["data"]
		var mp: String = entry["path"]
		var code: String = m.get("code", "")
		var picked := mp == map_path
		var x := 15.0 + 158.0 * (k % 5)
		var y := 75.0 + 107.0 * (k / 5)
		var b := st.key("MAP-THUMB-CARD", x, y, 150, 100, str(m.get("name", "")).replace("*", "").to_upper(), func():
			map_path = mp
			show_maps(), picked)
		b.label_slot = true
		b.size_pt = 12.5
		var tex := st.pic(null, x + 6, y + 6, 138, 63)
		var tp := MapPool.thumb(code)                  # the map alone; a thumbnail not loaded yet fills in later (_thumb_queue)
		if UiKit.cached(tp):
			tex.texture = UiKit.map_thumb(tp)
		else:
			_thumb_queue.append([tex, tp])
	# the foot: CANCEL, ☆ + the picked map, ‹ p / n ›, CHOOSE
	st.key("KEY-SMALL", 15, 298, 115, 33, "CANCEL", _cancel_pick)
	var is_fav := map_path in UiKit.map_list("favourites")
	var fv := st.key("KEY-SMALL", 138, 298, 36, 33, "★" if is_fav else "☆", func():
		var fl := UiKit.map_list("favourites")
		if map_path in fl:
			fl.erase(map_path)
		else:
			fl.append(map_path)
		UiKit.save_map_list("favourites", fl)
		show_maps(), is_fav)
	fv.size_pt = 16.0
	fv.tooltip_text = "FAVOURITE"
	var sel := _selected_map()
	var detail := "%s · %d NODES%s" % [" · ".join(_modes_of(sel).map(func(v): return MODE_NAMES.get(v, v))), sel["nodes"].size(),
			_relay_kinds(sel).replace("    /    ", " · ")]
	if room_host:
		detail += " · THE ROOM SEES IT AFTER CHOOSE"
	st.txt(str(sel.get("name", "")).replace("*", "").to_upper(), 182, 296, 328, 18, 14.0, UiKit.INK, true)
	st.txt(detail, 182, 313, 328, 18, 12.5, Kit45.KICK)
	var lb := st.key("KEY-SMALL", 518, 298, 36, 33, "‹", func():
		_map_page -= 1
		show_maps(), false, _map_page <= 0)
	lb.size_pt = 18.0
	st.txt("%d / %d" % [_map_page + 1, pages], 556, 306, 38, 16, 12.5, UiKit.INK, true, 1)
	var rb := st.key("KEY-SMALL", 594, 298, 36, 33, "›", func():
		_map_page += 1
		show_maps(), false, _map_page >= pages - 1)
	rb.size_pt = 18.0
	var cb := st.key("PRIMARY-WIDE", 638, 298, 159, 33, "CHOOSE  →", _choose_map, true)
	cb.size_pt = 14.0
	shell_raise()


func _size_key(m: Dictionary) -> String:
	## A map's size tab: xs / s / m / l, or "none" (no size tag).
	var t := _map_type(m)
	return t if t != "" else "none"


func _map_type(m: Dictionary) -> String:
	## MAPS 5.0: TYPE filters by size (XS / S / M / L, under "tags", not a top-level field); a map without
	## one (none baked before 5.0) never matches a size chip, only ALL SIZES.
	return str(m.get("tags", {}).get("size", "")).to_lower()


# --- SETTING PICK (2026-11-13, Daniele: "when you pick AI there should also be a pick of the setting"; it "completely
# supersedes the old backgrounds"): the match's setting (LookTheme: world + HUD shells). PLAY VS AI: yours (UiKit.setting_choice,
# remembered); the online room: the owner's for everyone (Net.room_backdrop, LookTheme.room_value). ---
var _bg_sheet := "--setting-sheet" in OS.get_cmdline_user_args()   # the SETTING sheet is open (screenshots: open)
var _setting_room := ""                            # the room the owner's remembered SETTING was last brought into


func _setting_tiles(r: Rect2, mine: String, on_pick: Callable, f: String, enabled := true) -> float:
	## The five settings in one row inside r, each by its picture (R-01 in that setting), its name and its line; the current
	## lit. Returns the height used. No scrolling: the row shrinks to fit (Daniele 2026-11-04).
	var n := LookTheme.IDS.size()
	var gap := 10.0
	var tw := floorf((r.size.x - gap * (n - 1)) / n)
	var two := false                                  # a narrow tile: the lines wrap to two rows (never cut)
	for id in LookTheme.IDS:
		two = two or UiKit.text_w(self, str(LookTheme.TAGLINES[id]), 12) > tw - 16.0
	var sub_h := UiKit.line_h(self, 12)
	if two:                                           # the wrapped height as the font draws it (2 x line_h clipped the 2nd row)
		for id in LookTheme.IDS:
			sub_h = maxf(sub_h, UiKit.text_h(self, str(LookTheme.TAGLINES[id]), 12, tw - 16.0) + 2.0)
	var cap := UiKit.line_h(self, 13, true) + sub_h + 10.0
	var th := floorf(minf(tw * 9.0 / 16.0, maxf(40.0, r.size.y - cap - 12.0)))
	var tile := Vector2(tw, th + cap + 10.0)
	for k in range(n):
		var id: String = LookTheme.IDS[k]
		var b := UiKit.btn(self, "", r.position + Vector2(k * (tw + gap), 0), tile, func(): on_pick.call(id),
				"selected" if id == mine else "secondary", f)
		b.disabled = not enabled
		var tex := LookTheme.preview(id)
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pic.position = Vector2(5, 5)
			pic.size = Vector2(tw - 10.0, th)
			b.add_child(pic)
		var title := str(LookTheme.NAMES[id])
		if UiKit.text_w(self, title, 13, true) > tw - 16.0:
			title = str(LookTheme.SHORT_NAMES[id])       # CORPORATE CAMPUS -> CAMPUS on a phone
		var nm := UiKit.label(self, title, 13, UiKit.accent(f) if id == mine else UiKit.INK, true)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.position = Vector2(8, th + 10.0)
		nm.size = Vector2(tw - 16.0, UiKit.line_h(self, 13, true))
		b.add_child(nm)
		var sub := UiKit.label(self, str(LookTheme.TAGLINES[id]), 12, UiKit.MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if two else TextServer.AUTOWRAP_OFF
		sub.clip_text = not two
		sub.position = Vector2(8, th + 10.0 + nm.size.y)
		sub.size = Vector2(tw - 16.0, sub_h)
		b.add_child(sub)
	return tile.y


func _setting_sheet(_sel: Dictionary) -> void:
	## Over PLAY VS AI: the five settings; a pick saves and closes; so does a tap outside.
	var dim := UiKit.rect(Vector2(-safe.x, -safe.y), content.size + Vector2(safe.x + safe.z, safe.y + safe.w), Color(0, 0, 0, 0.62))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_bg_sheet = false
			_redraw.call_deferred())
	content.add_child(dim)
	var pw := minf(content.size.x - 40.0, 1180.0)
	var note := "Where your matches here are played: the walls, the floor, the kit and the HUD. Online, the room's host picks it for everyone. Campaign missions and training keep their own."
	var head := UiKit.line_h(self, 12, true) + UiKit.line_h(self, 26, true) + UiKit.text_h(self, note, 13, pw - 48.0) + 28.0
	var ph := minf(content.size.y - 24.0, head + floorf((pw - 48.0 - 40.0) / 5.0) * 9.0 / 16.0 + 104.0)
	var pos := ((content.size - Vector2(pw, ph)) / 2.0).floor()
	var panel := UiKit.panel(self, pos, Vector2(pw, ph), faction)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ty := UiKit.title(self, pos.x + 24.0, pos.y + 18.0, "MATCH SETUP / SETTING", "PICK THE PLACE.", faction, 26.0)
	_say(note, Vector2(pos.x + 24.0, ty + 2.0), 13, UiKit.MUTED, pw - 48.0)
	_setting_tiles(Rect2(pos.x + 24.0, pos.y + head, pw - 48.0, ph - head - 18.0), UiKit.setting_choice(), func(id):
		UiKit.save_setting_choice(id)
		_bg_sheet = false
		_redraw(), faction)


func _setting_owner_remembered(host: bool) -> void:
	## The room owner's remembered SETTING comes along into a new room (once per room; a later pick there is theirs).
	if not host or Net.room_code == "" or Net.room_code == _setting_room:
		return
	_setting_room = Net.room_code
	if Net.room_backdrop == "auto":
		Net.set_room_backdrop.call_deferred(LookTheme.room_value(UiKit.setting_choice()))


# --- end SETTING PICK ---


func _filtered_maps() -> Array:
	var out := maps.filter(func(e):
		return (map_filter_mode == "all" or _map_list != "" or map_filter_mode in _modes_of(e["data"])) 				and (map_filter_type == "all" or _size_key(e["data"]) == map_filter_type))
	if Net.in_room():                                  # a room's host: the maps the room's mode can play
		out = out.filter(func(e): return e["path"] in Net.maps_for(Net.mode))
	if _map_list != "":
		var lst := UiKit.map_list(_map_list)
		out = out.filter(func(e): return e["path"] in lst)
		if _map_list == "recent":
			out.sort_custom(func(a, b): return lst.find(a["path"]) < lst.find(b["path"]))
	return out


func _choose_map() -> void:
	## MAP PICKER's CHOOSE: back to MATCH SETUP with this map; an online host sets the room's map.
	if Net.in_room() and Net.can_control() and map_path != Net.map_path:
		Net.set_map(map_path)
	_map_list = ""
	_back_to_setup()


func _pool_modes() -> Array:
	## The modes some map in the pool offers, in MODE_NAMES order (no chip for a mode no map has).
	var have := {}
	for e in maps:
		for md in _modes_of(e["data"]):
			have[md] = true
	return MODES_OFFERED.filter(func(md): return have.has(md))


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
	for k in MODES_OFFERED:
		if m.get("seats", {}).has(k) and MapPool.mode_offered(str(m.get("code", "")), k):   # 0.23.0: a kept older map fills gaps only
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
	## MATCH SETUP = the remake (45B sizes.json MATCH-SETUP, HOME > CHANGE): MATCH RULES (MODE, MAP, SETTING, RULES) and
	## PLAYER & OPPONENT (AI LEVEL, ARMY, COLOUR, RIVAL + a key per extra AI seat), SELECTOR-CARDs 357 x 35 that open their
	## sheet / page; BACK, the line-up, CONFIRM SETUP (back to HOME, where PLAY deploys).
	_draft = {}
	var sel := _selected_map()
	var modes := _modes_of(sel)
	if not mode in modes:
		mode = modes[0]
	var st := _stage_page("OOZE / PLAY VS AI", "home", "MATCH SETUP", "PLAY VS AI", show_main, faction)
	st.piece("HERO-CABINET", 15, 76, 385, 211, "STATIC", "385x211pt")
	st.piece("HERO-CABINET", 412, 76, 385, 211, "STATIC", "385x211pt")
	st.txt("MATCH RULES", 29, 89, 343, 16, 12.5, Kit45.KICK, true)
	st.txt("PLAYER & OPPONENT", 426, 89, 344, 16, 12.5, Kit45.KICK, true)
	var ys := [110.0, 149.0, 188.0, 227.0]
	_sel45(st, 29, ys[0], 357, 35, "MODE", str(MODE_NAMES.get(mode, mode)), func(): _open_lobby_sheet("mode"))
	var mb := _sel45(st, 29, ys[1], 357, 35, "MAP", str(sel.get("name", "")).replace("*", "").to_upper(), _open_maps)
	mb.acc_tex = UiKit.map_thumb(MapPool.thumb(str(sel.get("code", ""))))
	var sb := _sel45(st, 29, ys[2], 357, 35, "SETTING", str(LookTheme.SHORT_NAMES[UiKit.setting_choice()]), func():
		_bg_sheet = true
		show_setup())
	sb.acc_tex = LookTheme.preview(UiKit.setting_choice())
	var dflt := Rules.last_stand and Rules.abilities_on and not Rules.hide_enemy_counts
	_sel45(st, 29, ys[3], 357, 35, "RULES", "STANDARD" if dflt else "LAST STAND %s · SKILLS %s" % ["ON" if Rules.last_stand else "OFF",
			"ON" if Rules.abilities_on else "OFF"], func(): _pick(show_setup_advanced))
	var enemies := _enemy_seats()
	var first: String = enemies[0] if not enemies.is_empty() else "B"
	_sel45(st, 426, ys[0], 357, 35, "AI LEVEL", ai_level.to_upper(), func(): _open_lobby_sheet("seat:" + first))
	_sel45(st, 426, ys[1], 357, 35, "ARMY", str(UiKit.NAMES[faction]), func(): _pick(show_factions))
	var cb := _sel45(st, 426, ys[2], 357, 35, "COLOUR", str(COLOUR_NAMES[colour]), func(): _pick(show_colours))
	cb.acc_col = Rules.FACTIONS[faction][1] if colour == "faction" else Rules.SEATS[colour]
	var team := _setup_team_of()
	var rw := 357.0 - 40.0 * maxi(0, enemies.size() - 1)
	var rf := str(rival_picks.get(first, "random"))
	var ally: bool = team.has(first) and team.get(first) == team.get("A", -1)
	_sel45(st, 426, ys[3], rw, 35, ("ALLY " if ally else "RIVAL ") + first, str(UiKit.NAMES.get(rf, "RANDOM")), func(): _open_lobby_sheet("seat:" + first))
	for k in range(1, enemies.size()):                 # FFA / 2v2: a key per further AI seat (its sheet: army + level)
		var s: String = enemies[k]
		var kb := st.key("KEY-SMALL", 426 + rw + 4.0 + 40.0 * (k - 1), ys[3] + 1.0, 36, 33, s, func(): _open_lobby_sheet("seat:" + s))
		kb.size_pt = 14.0
		kb.tooltip_text = "AI seat %s: %s" % [s, str(UiKit.NAMES.get(str(rival_picks.get(s, "random")), "RANDOM"))]
	st.key("KEY-SMALL", 15, 299, 115, 33, "BACK", show_main)
	st.txt("%s · YOU + %d AI" % [MODE_NAMES.get(mode, mode), enemies.size()], 140, 307, 455, 16, 12.5, UiKit.MUTED, true, 1)
	var go := st.key("PRIMARY-WIDE", 607, 299, 190, 33, "CONFIRM SETUP", func():
		_save_last_setup()
		show_main(), true)
	go.size_pt = 14.0
	shell_raise()
	if _lobby_sheet != "":
		_setup_sheet_draw()
	elif _bg_sheet:
		_setting_sheet(sel)


# --- ROUND 4: the shared lobby grid (PLAY VS AI and the online room) ---


const TEXT_IN := 22.0                              # note 2: text inset inside a 43B plate (its 14 pt chamfer + bolt)


func _setup_team_of() -> Dictionary:
	var team := {}
	for s in _selected_map().get("seats", {}).get(mode, []):
		if s.get("team") != null and mode == "2v2":
			team[str(s.get("seat", ""))] = int(s["team"])
	return team


func _seat_rows(r: Rect2, cur_f: String, cur_lv: String, on_f: Callable, on_lv: Callable, enabled := true, y0 := -1.0) -> float:
	## ROUND 4: an AI seat's sheet rows, the same in PLAY VS AI and the room - FACTION (ANY + the five) and AI LEVEL
	## (the five, every AI seat). Returns the y under them.
	var y := r.position.y if y0 < 0.0 else y0
	var acc := UiKit.accent(shell_f)
	var kl := UiKit.line_h(self, 12, true)
	var n0 := content.get_child_count()
	_say("FACTION", Vector2(r.position.x, y), 12, acc, 0.0, true, 3)
	y += kl + 4.0
	var s := UiKit.tap_h(self, 54.0)
	var gap := 8.0
	var aw := floorf((r.size.x - gap * 5.0) / 6.0)
	var opts := ["random"] + FACTIONS
	for i in range(opts.size()):
		var f: String = opts[i]
		var b := UiKit.btn(self, "ANY" if f == "random" else "", Vector2(r.position.x + i * (aw + gap), y), Vector2(aw, s), func(): on_f.call(f),
				"selected" if f == cur_f else "secondary", shell_f if f == "random" else f, 15)
		if f != "random":
			var ts := s - 8.0
			var named := aw - ts - 14.0 >= UiKit.text_w(self, "BLOOM", 13, true)
			b.add_child(_cutout_mark(f, Vector2(6 if named else (aw - ts) / 2.0, 4), Vector2(ts, ts)))
			if not named:                              # a narrow phone: the character alone (+ its emblem)
				UiKit.emblem_badge(b, f, s * 0.36)
				continue
			var nl := UiKit.label(self, UiKit.NAMES[f], 13, UiKit.accent(f) if f == cur_f else UiKit.INK, true)
			nl.clip_text = true
			nl.position = Vector2(ts + 10.0, (s - UiKit.line_h(self, 13, true)) / 2.0)
			nl.size = Vector2(maxf(10.0, aw - ts - 14.0), UiKit.line_h(self, 13, true))
			b.add_child(nl)
	y += s + 12.0
	_say("AI LEVEL  ·  EVERY AI SEAT", Vector2(r.position.x, y), 12, acc, 0.0, true, 3)
	y += kl + 4.0
	var levels: Array = Rules.AI_LEVELS.keys()
	var lw := floorf((r.size.x - gap * (levels.size() - 1)) / levels.size())
	var lh := UiKit.tap_h(self, 44.0)
	for i in range(levels.size()):
		var lv: String = levels[i]
		var b := UiKit.btn(self, lv.to_upper(), Vector2(r.position.x + i * (lw + gap), y), Vector2(lw, 44), func(): on_lv.call(lv),
				"selected" if lv.to_lower() == cur_lv.to_lower() else "secondary", shell_f, 14)
		b.add_theme_font_override("font", UiKit.BODY)
	y += lh
	if not enabled:
		_ready_lock(n0)
	return y


func _setup_sheet_draw() -> void:
	## PLAY VS AI's sheets over the lobby (the room's _sheet_frame): MODE, or a seat (an AI: faction + AI level).
	var which := _lobby_sheet
	if which == "mode":
		var r := _sheet_frame("PLAY VS AI / MODE", "HOW MANY PLAY.", Vector2(900, 330))
		var modes := _modes_of(_selected_map())
		var mcols := mini(4, modes.size())
		var mw := floorf((r.size.x - 10.0 * (mcols - 1)) / mcols)
		var mh := UiKit.tap_h(self, 64.0)
		for i in range(modes.size()):
			var md: String = modes[i]
			UiKit.btn(self, MODE_NAMES.get(md, md), r.position + Vector2((i % mcols) * (mw + 10.0), (i / mcols) * (mh + 10.0)), Vector2(mw, 64), func():
				mode = md
				_close_lobby_sheet(), "selected" if md == mode else "secondary", faction, 18)
		_say("The modes this map seats. Other modes: MAP picks a map that seats them.",
				r.position + Vector2(0, ceilf(modes.size() / float(mcols)) * (mh + 10.0)), 13, UiKit.MUTED, r.size.x)
	elif which.begins_with("seat:"):
		var seat := which.substr(5)
		if seat == "A":
			_lobby_sheet = ""
			_pick(show_factions)
			return
		var team := _setup_team_of()
		var ally: bool = team.has(seat) and team.get(seat) == team.get("A", -1)
		var r := _sheet_frame("PLAY VS AI / SEAT %s" % seat, ("AI ALLY" if ally else "AI RIVAL") + ".", Vector2(900, 360))
		_seat_rows(r, str(rival_picks.get(seat, "random")), ai_level, func(f):
			rival_picks[seat] = f
			_close_lobby_sheet(), func(lv):
			ai_level = lv
			show_setup())
	_sheet_fit()


func show_setup_advanced() -> void:
	## 03 SETUP > ADVANCED (Daniele 2026-11-01: "move to a separate advanced tab, not deleted"): the two switches that
	## change the match's rules - LAST STAND and ABILITIES - out of SETUP's main flow. Defaults both ON; each row is the
	## switch and what it does; RESET TO DEFAULTS shows only while something is off. The values are the same
	## Rules.last_stand / Rules.abilities_on as before (main.keep_own_settings: yours, put back after a room's round).
	## BACK -> SETUP.
	_last_show = show_setup_advanced
	var area := shell_open("OOZE / MATCH SETUP / RULES", "home", _cancel_pick, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := area.position.y + 10.0 if shell_slim else page_title(area, "MATCH SETUP / RULES", "THE MATCH RULES.")
	var th := UiKit.tap_h(self, 46.0)
	var pad := 16.0
	var card := UiKit.panel(self, Vector2(x, y), Vector2(w, 10.0), faction)   # sized once the rows are laid out
	x += pad
	w -= pad * 2.0
	y += pad
	var tw := clampf(w * 0.4, 200.0, 340.0)
	var rows := [
		["LAST STAND", Rules.last_stand,
			"From %d:%02d the map collapses ring by ring toward the centre; the danger signs show the next node to fall. Off: every platform stands to the end."
			% [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60],
			func():
				Rules.last_stand = not Rules.last_stand
				main.keep_own_settings()
				show_setup_advanced()],
		["ABILITIES", Rules.abilities_on,
			"Every army fights with its loadout - an active skill, a map skill and the faction's ultimate (ARMIES). Off: no skills for anyone, vats and relays only.",
			func():
				Rules.abilities_on = not Rules.abilities_on
				main.keep_own_settings()
				show_setup_advanced()],
		["HIDDEN COUNTS", Rules.hide_enemy_counts,
			"No unit numbers on enemy nodes, so you scout. Off: every count is shown.",
			func():
				Rules.hide_enemy_counts = not Rules.hide_enemy_counts
				main.keep_own_settings()
				show_setup_advanced()],
	]
	var side := w - tw - 18.0 >= 220.0                 # the text beside the switch, or under it on a narrow phone
	for row in rows:
		_toggle(row[0], row[1], Vector2(x, y), Vector2(tw, 46), row[3])
		var d := UiKit.label(self, str(row[2]), 13, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if side:
			var dw := w - tw - 18.0
			d.custom_minimum_size = Vector2(dw, 0)
			d.size = Vector2(dw, UiKit.text_h(self, d.text, 13, dw))
			_shell_add(d, Vector2(x + tw + 18.0, y + maxf((th - d.size.y) / 2.0, 0.0)))
			y += maxf(th, d.size.y) + 8.0
		else:
			d.custom_minimum_size = Vector2(w, 0)
			d.size = Vector2(w, UiKit.text_h(self, d.text, 13, w))
			_shell_add(d, Vector2(x, y + th + 4.0))
			y += th + 4.0 + d.size.y + 14.0
	var bh := UiKit.tap_h(self, 44.0)
	var fy := y - 2.0                                  # the card's foot row: the default note, RESET while anything is off
	var note := UiKit.label(self, "DEFAULT: LAST STAND + ABILITIES ON, HIDDEN COUNTS OFF", 12, UiKit.DIM, true, 2)
	_shell_add(note, Vector2(x, fy + (bh - UiKit.line_h(self, 12, true)) / 2.0))
	var sv := "SAVE  →"
	var svw := maxf(UiKit.text_w(self, sv, 17, true) + 48.0, 170.0)
	UiKit.btn(self, sv, Vector2(content.size.x - shell_x() - svw, area.end.y - UiKit.tap_h(self, 48.0) - 10.0), Vector2(svw, 48),
			_back_to_setup, "primary", faction, 17)
	if not (Rules.last_stand and Rules.abilities_on and not Rules.hide_enemy_counts):
		var rt := "RESET TO DEFAULTS"
		var rw := UiKit.text_w(self, rt, 15, true) + 44.0
		UiKit.btn(self, rt, Vector2(x + w - rw, fy), Vector2(rw, 44), func():
			Rules.last_stand = true
			Rules.abilities_on = true
			Rules.hide_enemy_counts = false
			main.keep_own_settings()
			show_setup_advanced(), "tertiary", faction, 15)
	card.size.y = minf(fy + bh + pad - card.position.y, area.end.y - UiKit.tap_h(self, 48.0) - 20.0 - card.position.y)


func show_colours() -> void:
	## MATCH SETUP > TEAM COLOUR (UX pass): the hex chips in a sheet; a pick shows at once, SAVE returns, BACK cancels.
	_last_show = show_colours
	var area := shell_open("OOZE / MATCH SETUP / COLOUR", "home", _cancel_pick, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := area.position.y + 14.0 if shell_slim else page_title(area, "MATCH SETUP / COLOUR", "YOUR TEAM COLOUR.")
	_setup_colours(Vector2(x, y), minf(w, 760.0))
	var sv := "SAVE  →"
	var svw := maxf(UiKit.text_w(self, sv, 17, true) + 48.0, 170.0)
	UiKit.btn(self, sv, Vector2(content.size.x - x - svw, area.end.y - UiKit.tap_h(self, 48.0) - 10.0), Vector2(svw, 48),
			_back_to_setup, "primary", faction, 17)


func _setup_map(pos: Vector2, dims: Vector2) -> void:
	## SETUP's map panel: the name and CHANGE (-> BATTLEFIELD), the whole-map preview, its mode / nodes / relays.
	var sel := _selected_map()
	UiKit.panel(self, pos, dims, faction)
	var pad := 16.0
	var ct := "CHANGE MAP"
	var cw := UiKit.text_w(self, ct, 14, true) + 34.0
	var cb := UiKit.btn(self, ct, Vector2(pos.x + dims.x - pad / 2.0 - cw, pos.y + 6.0), Vector2(cw, 38), _open_maps, "tertiary", faction, 14)
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
	var hit := Button.new()                            # UX pass: the map itself opens the MAP PICKER too
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.size = pd
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.pressed.connect(_open_maps)
	_shell_add(hit, Vector2(pos.x + pad, py))
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
	var rows := _colour_rows(width)                    # iOS (the iPhone SE): two rows where seven 44 pt chips don't fit one
	var per := ceili(keys.size() / float(rows))
	var gap := clampf((width - hs * per) / float(maxi(per - 1, 1)), 4.0, 14.0)
	for i in range(keys.size()):
		var ck: String = keys[i]
		var wedges := FACTIONS.map(func(f): return Rules.FACTIONS[f][1]) if ck == "faction" else []
		var cc: Color = Color.WHITE if ck == "faction" else Rules.SEATS[ck]
		var cp := Vector2(pos.x + (i % per) * (hs + gap), hy + (i / per) * (hs + 8.0))
		var chip := hex_chip(cp, Vector2(hs, hs), cc, wedges, ck == colour, COLOUR_NAMES[ck], func():
			colour = ck
			_redraw())
		if ck == "faction":
			chip.emblem_faction = faction              # a recognisable face, not just wedges
	var y := hy + hs * rows + 8.0 * (rows - 1) + (10.0 if not mobile else 6.0)
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


func _colour_rows(width: float) -> int:
	## YOUR TEAM COLOUR's rows: one, or two where the chips (>= 44 pt) don't fit the column on one.
	var n := COLOUR_NAMES.size()
	return 1 if UiKit.tap_h(self, 44.0) * n + 4.0 * (n - 1) <= width else 2


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
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size = Vector2(maxf(10.0, tw), UiKit.line_h(self, ln[1], ln[3]))
		var ex := 0.0
		if i == 0:                                    # the race emblem before the name
			ex = l.size.y + 6.0
			UiKit.emblem_rect(self, faction, Vector2(tx, ly), l.size.y)
			l.size.x = maxf(10.0, tw - ex)
		_shell_add(l, Vector2(tx + ex, ly))
		ly += l.size.y


func _faction_picks(seat: String, pos: Vector2, width: float, back: Callable, size := 0.0) -> float:
	## An AI seat's faction pick (0.19.2 spec H3: one per enemy seat): ANY (drawn when you deploy) or one of the five -
	## the characters, the picked one lit. Returns the row's height.
	var pick := str(rival_picks.get(seat, "random"))
	var s := maxf(UiKit.tap_h(self, 50.0), size)
	var aw := UiKit.text_w(self, "ANY", 14, true) + 36.0
	var gap := clampf((width - aw - s * 5.0) / 5.0, 4.0, 10.0)
	UiKit.btn(self, "ANY", pos, Vector2(aw, s), func():
		rival_picks[seat] = "random"
		back.call(), "selected" if pick == "random" else "secondary", faction, 14).tooltip_text = "ANY FACTION"
	for i in range(FACTIONS.size()):
		var f: String = FACTIONS[i]
		var b := UiKit.btn(self, "", pos + Vector2(aw + gap + i * (s + gap), 0), Vector2(s, s), func():
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
				_redraw(), "selected" if lv == ai_level else "secondary", faction, 15)
			b.add_theme_font_override("font", UiKit.BODY)
		return
	var i0 := maxi(0, levels.find(ai_level))
	var sw := UiKit.tap_h(self, 44.0)
	UiKit.btn(self, "‹", pos, Vector2(sw, 44), func():
		ai_level = levels[(i0 + levels.size() - 1) % levels.size()]
		_redraw(), "secondary", faction, 20)
	UiKit.btn(self, "›", pos + Vector2(width - sw, 0), Vector2(sw, 44), func():
		ai_level = levels[(i0 + 1) % levels.size()]
		_redraw(), "secondary", faction, 20)
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
	## RIVALS (a MATCH SETUP sheet; round 2, Daniele 2026-11-04: one screen, no scroll, no pager): compact cells two per
	## row - YOU (your faction, CHANGE -> FACTION), AI LEVEL, then every AI seat (ally or rival, its team in team modes)
	## with its pick (ANY or one of the five). FFA 5 = 6 cells = 3 rows. SAVE returns to MATCH SETUP.
	_last_show = show_seats                  # a resize that changes the phone sizing rebuilds it (_fit)
	var sel := _selected_map()
	var modes := _modes_of(sel)
	if not mode in modes:
		mode = modes[0]
	var area := shell_open("OOZE / MATCH SETUP / RIVALS", "home", _cancel_pick, faction)
	var x := shell_x()
	var w := content.size.x - x * 2.0
	var y := area.position.y + 10.0 if shell_slim else page_title(area, "MATCH SETUP / RIVALS", "PICK YOUR RIVALS.")
	var gap := 10.0
	var bh := UiKit.tap_h(self, 48.0)
	var fy := area.end.y - bh - 10.0
	var dw := maxf(UiKit.text_w(self, "SAVE  →", 18, true) + 56.0, 170.0)
	UiKit.btn(self, "SAVE  →", Vector2(content.size.x - x - dw, fy), Vector2(dw, 48), _back_to_setup, "primary", faction, 18)
	_shell_add(UiKit.label(self, "%s  ·  you + %d AI" % [MODE_NAMES.get(mode, mode), _enemy_seats().size()], 15, UiKit.MUTED),
			Vector2(x, fy + (bh - UiKit.line_h(self, 15)) / 2.0))
	var team := {}
	for s in sel.get("seats", {}).get(mode, []):
		if mode == "2v2" and s.get("team") != null:
			team[str(s.get("seat", ""))] = int(s["team"])
	var cells := ["A", "level"] + _enemy_seats()
	var cw := floorf((w - gap) / 2.0)
	var ph := UiKit.tap_h(self, 50.0)
	var kl := UiKit.line_h(self, 12, true)
	var rows := ceili(cells.size() / 2.0)
	var avail := fy - 10.0 - y
	var card_h := floorf((avail - gap * (rows - 1)) / rows)                 # ROUND 2b: the cards fill the page
	var aw0 := UiKit.text_w(self, "ANY", 14, true) + 36.0
	ph = clampf(minf(card_h - kl - 6.0 - 20.0, (cw - 28.0 - aw0 - 50.0) / 5.0), ph, ph * 1.8)   # bigger faction picks
	var pad_y := maxf(4.0, (card_h - kl - 6.0 - ph) / 2.0)
	for i in range(cells.size()):
		var s: String = cells[i]
		var p := Vector2(x + (i % 2) * (cw + gap), y + (i / 2) * (card_h + gap))
		UiKit.panel(self, p, Vector2(cw, card_h), faction, s == "A")
		var ry := p.y + pad_y + kl + 6.0
		if s == "level":
			_shell_add(UiKit.label(self, "AI LEVEL", 12, UiKit.COPPER, true, 3), Vector2(p.x + 14.0, p.y + pad_y))
			_difficulty(Vector2(p.x + 14.0, ry), cw - 28.0)
			continue
		var ally: bool = s == "A" or (team.has(s) and team.get(s) == team.get("A", -1))
		var role := "YOU" if s == "A" else ("AI ALLY" if ally else "AI RIVAL")
		var kick := "SEAT %s  ·  %s%s" % [s, role, ("  ·  TEAM %d" % (int(team[s]) + 1)) if team.has(s) else ""]
		_shell_add(UiKit.label(self, kick, 12, UiKit.COPPER, true, 3), Vector2(p.x + 14.0, p.y + pad_y))
		if s == "A":
			_shell_add(_cutout(faction, Vector2.ZERO, Vector2(ph, ph)), Vector2(p.x + 14.0, ry))
			var nl := UiKit.line_h(self, 15, true)
			UiKit.emblem_rect(self, faction, Vector2(p.x + 14.0 + ph + 10.0, ry + (ph - nl) / 2.0), nl)
			var ct := "CHANGE"
			var chw := UiKit.text_w(self, ct, 14, true) + 34.0
			var nx := 14.0 + ph + 10.0 + nl + 6.0
			_clip(str(UiKit.TAGS[faction]), Vector2(p.x + nx, ry + (ph - nl) / 2.0), 15, UiKit.INK, cw - nx - chw - 24.0, true)
			UiKit.btn(self, ct, Vector2(p.x + cw - 14.0 - chw, ry), Vector2(chw, ph), func():
				_draft = {}
				_pick(show_factions), "tertiary", faction, 14)
		else:
			_faction_picks(s, Vector2(p.x + 14.0, ry), cw - 28.0, show_seats, ph)
	shell_raise()


func _seat_faction_picks() -> Dictionary:
	## Every enemy seat's pick for this mode (0.19.2 spec H3): a faction id, or "random" - main.gd
	## resolves "random" through Sim.resolve_factions (the seed, so it matches Sim.setup()'s own way).
	var out := {}
	for seat in _enemy_seats():
		out[seat] = str(rival_picks.get(seat, "random"))
	return out


func deploy() -> void:
	var modes := _modes_of(_selected_map())
	if not mode in modes:                              # HOME's PLAY with a saved mode this map lost
		mode = modes[0]
	UiKit.save_last_faction(faction)                   # UI: HOME's hero is the faction played last
	_save_last_setup()                                 # UX pass: HOME's PLAY LAST SETUP
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
	## UX pass (Alpha 24 step 3): no ONLINE page - HOME's ONLINE tile hosts (straight into the room) or opens the JOIN WITH
	## CODE sheet; a failed join (Net.status) or a room you left lands back on HOME with the sheet.
	_join_open = Net.status != "" or _code_error != "" or _join_open
	show_main()


func _leave_online() -> void:
	Net.status = ""
	_code_error = ""
	_join_open = false
	show_main()


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
		UiKit.hero_neon(art, f, _viewer_col())
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
		_close_lobby_sheet()
	else:
		show_main()


var _versus_warmed := false


func show_lobby() -> void:
	_last_show = show_lobby                  # a resize that changes the phone sizing rebuilds it (_fit)
	if not _versus_warmed:                   # 0.23.3: the VERSUS art decoded while the lobby sits, not on DEPLOY
		_versus_warmed = true
		var fs := [faction]
		for id in Net.roster:
			fs.append(str(Net.roster[id]["faction"]))
		(func(): VersusScreen.warm_art(fs)).call_deferred()
	## ONLINE ROOM = the remake (45B, sizes.json ONLINE-ROOM-4P): LEAVE ROOM at the top right; the MAP-CARD (name, nodes,
	## the map; host: tap = MAP PICKER); up to four SEAT-CARDs (letter + edge in the seat's room colour, the army in the
	## avatar well, name, HOST / READY / AWAY / OPEN / SIT HERE, the three chosen skills; tap = the seat's sheet, an open
	## seat on another team = SIT HERE); the ROOM-CODE-PANEL (code, SHARE, the latest chat lines, the message field);
	## six SELECTOR-CARDs (MODE, MAP, SETTING, ARMY, COLOUR, RULES: each opens its sheet over the room); the STATUS-STRIP
	## (seats, Net's status, the host's notice) and DEPLOY (host, once every seat is ready) / READY (guest).
	if not Net.in_room():
		show_online()
		return
	if Net.roster.has(Net.local_id()):
		faction = str(Net.roster[Net.local_id()]["faction"])
	var st := _stage_page("OOZE / ROOM", "home", "ONLINE ROOM", "", _lobby_back, faction)
	_page = "lobby"
	map_path = Net.map_path                           # the seats' loadout icons read the room's map (relays)
	var host := Net.can_control()                     # the browser host, or a server room's owner (Alpha 20)
	var locked := Net.ready_locked() or Net.active
	st.key("KEY-SMALL", 681.5, 45, 115, 33, "LEAVE ROOM", _leave_room)
	# the map
	var sel := _selected_map()
	st.piece("MAP-CARD", 15, 81, 220, 169)
	st.txt(str(sel.get("name", "")).replace("*", "").to_upper(), 27.8, 97.5, 100, 15, 12.5, UiKit.INK, true)
	st.txt("%d NODES" % sel.get("nodes", []).size(), 128.0, 97.5, 94, 15, 12.5, Kit45.KICK, true, 2)   # FIX 2: room at the floor
	st.pic(UiKit.map_thumb(MapPool.thumb(str(sel.get("code", "")))), 23.5, 126, 203, 114)
	if host and not locked:
		st.tap(15, 81, 220, 169, _open_maps)
	# the seats
	var by_slot := {}
	for id in Net.roster:
		by_slot[int(Net.roster[id]["slot"])] = int(id)
	var colours := Net.room_colours()
	var n: int = mini(Net.slots(), 4)
	var at := [[242, 82], [418, 82], [242, 171], [418, 171]]
	if n == 2:
		at = [[242, 126], [418, 126]]
	for k in range(n):
		_seat45(st, k, by_slot.get(k, -1), colours, float(at[k][0]), float(at[k][1]))
	# the room code + chat
	_room_chat45(st)
	# MODE | MAP | SETTING | ARMY | COLOUR | RULES
	var xs := [15.0, 145.5, 275.75, 406.25, 536.5, 667.0]
	_sel45(st, xs[0], 261, 126, 34, "MODE", str(Net.MODE_LABELS[Net.mode]), func(): _open_lobby_sheet("mode"))
	_sel45(st, xs[1], 261, 126, 34, "MAP", "CHANGE" if host else "HOST PICKS", _open_maps, not host or locked)
	_setting_owner_remembered(host)
	var room_set := LookTheme.of_room_value(Net.room_backdrop)
	var sb := _sel45(st, xs[2], 261, 126, 34, "SETTING", str(LookTheme.SHORT_NAMES[room_set]), func(): _open_lobby_sheet("setting"))
	sb.acc_tex = LookTheme.preview(room_set)
	_sel45(st, xs[3], 261, 126, 34, "ARMY", str(UiKit.NAMES[faction]), func():
		_lobby_sheet = ""
		_pick(show_factions), locked)
	var mine_c := Net.colour_of(Net.local_id())
	var cb := _sel45(st, xs[4], 261, 126, 34, "COLOUR", mine_c.to_upper() if mine_c != "" else "AUTO", func(): _open_lobby_sheet("colour"), locked)
	if mine_c != "":
		cb.acc_col = Rules.HUES.get(mine_c, Color.WHITE)
	var rdef := Net.last_stand and Net.abilities
	_sel45(st, xs[5], 261, 126, 34, "RULES", "DEFAULT" if rdef else "CUSTOM", func(): _open_lobby_sheet("rules"))
	# the status strip + DEPLOY / READY
	st.piece("STATUS-STRIP", 15, 299, 544, 33)
	st.txt("%d / %d SEATS" % [Net.roster.size(), Net.slots()], 28, 307, 112, 16, 12.5, Kit45.KICK, true)
	var hint := ""
	var waiting := Net.present_ids().filter(func(id): return not Net.is_ready(int(id))).size()
	if _lobby_note != "":                              # READY: the host's last notice (e.g. "Settings changed - press READY again")
		hint = _lobby_note
	elif Net.status != "":
		hint = Net.status
	elif host:
		hint = ("Waiting for %d player%s to press READY." % [waiting, "" if waiting == 1 else "s"]) if waiting > 0 else "Share the room code and keep this tab open."
	else:
		hint = "The host deploys when everyone is ready." if Net.is_ready(Net.local_id()) else "Press READY when your picks are set."
	st.txt(hint, 144, 307, 405, 16, 12.5, UiKit.STAR if _lobby_note != "" else UiKit.INK, false)
	if host:
		var go := st.key("PRIMARY-WIDE", 568, 299, 229, 33, "DEPLOY  →", func(): Net.start_match(), true, not Net.can_start())
		go.size_pt = 14.0
	else:
		var me_ready := Net.is_ready(Net.local_id())
		var rb := st.key("PRIMARY-WIDE", 568, 299, 229, 33, "UN-READY" if me_ready else "READY  ✓", func():
			_lobby_note = ""
			Net.set_ready(not Net.is_ready(Net.local_id())), not me_ready, Net.active or not Net.connected)
		rb.size_pt = 14.0
	if _lobby_sheet != "":
		_lobby_sheet_draw(host)
	shell_raise()


var _chat_seen := -1                               # ROUND 4: the last chat line the room's chat panel shows


func _leave_room() -> void:
	_lobby_sheet = ""
	Net.leave()
	main.restore_own_settings()                        # AUDIT FIX: a round's settings don't outlive the room
	_join_open = false
	Net.status = ""
	show_main()


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


func _colour_row(pos: Vector2, w: float, d := 0.0) -> float:
	## Your colour: one hexagon chip per hue, filled solid in its colour, border the same colour, no words (Daniele,
	## 0.19.0 - the picked one is named in the caption above); taken hues (and, in team modes, another team's family)
	## are dimmed and disabled. The picked chip gets HexChip's white ring + scale-up. Wraps on a narrow column; returns
	## the height used.
	var me := Net.local_id()
	var mine := Net.colour_of(me)
	if d <= 0.0:
		d = UiKit.tap_h(self, 44.0)
	var per := maxi(1, int((w + 6.0) / (d + 6.0)))
	for i in range(HUE_NAMES.size()):
		var k: String = HUE_NAMES[i]
		var ok := Net.colour_allowed(me, k) or k == mine
		var b := hex_chip(pos + Vector2((i % per) * (d + 6.0), (i / per) * (d + 6.0)), Vector2(d, d), Rules.HUES[k], [], k == mine, k.to_upper(), func():
			Net.set_colour(k)
			_close_lobby_sheet())
		b.disabled = not ok or Net.active
	var rows := int(ceil(HUE_NAMES.size() / float(per)))
	return rows * d + (rows - 1) * 6.0


# --- ROUND 2 (Daniele 2026-11-04): the lobby on one screen - summaries and seat chips open sheets over the room ---
var _lobby_sheet := ""                             # the open sheet: "mode" | "rules" | "faction" | "colour" | "seat:<slot>"
var _sheet_box: Panel = null                       # the open sheet's panel (_sheet_fit grows it to what was drawn in it)


func _open_lobby_sheet(which: String) -> void:
	_lobby_sheet = which
	if Net.in_room():
		show_lobby()
	else:
		show_setup()


func _close_lobby_sheet() -> void:
	_lobby_sheet = ""
	if Net.in_room():
		show_lobby()
	else:
		show_setup()


func _lobby_back() -> void:
	## The room's BACK: closes an open sheet first, else leaves the room.
	if _lobby_sheet != "":
		_close_lobby_sheet()
	else:
		_leave_room()


func _sheet_frame(kicker: String, headline: String, dims: Vector2) -> Rect2:
	## A sheet over the page: the dim (a tap on it closes), a panel centred, its title and CLOSE. Returns the free area
	## inside the panel under the title.
	var dim := UiKit.rect(Vector2(-safe.x, -safe.y), content.size + Vector2(safe.x + safe.z, safe.y + safe.w), Color(0, 0, 0, 0.62))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_lobby_sheet.call_deferred())
	content.add_child(dim)
	dims = Vector2(content.size.x - 2.0 * maxf(60.0, shell_x() * 2.5), minf(dims.y, content.size.y - 20.0))   # ROUND 2b: wide sheets, big controls
	var pos := Vector2(floorf((content.size.x - dims.x) / 2.0), floorf(content.size.y * 0.14))
	var panel := UiKit.panel(self, pos, dims, shell_f)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_box = panel
	var cw := UiKit.text_w(self, "CLOSE", 14, true) + 34.0
	UiKit.btn(self, "CLOSE", Vector2(pos.x + dims.x - 16.0 - cw, pos.y + 12.0), Vector2(cw, 44), _close_lobby_sheet, "secondary", shell_f, 14)
	var ty := UiKit.title(self, pos.x + 20.0, pos.y + 12.0, kicker, headline, shell_f, 22.0)
	ty = maxf(ty, pos.y + 12.0 + UiKit.tap_h(self, 44.0)) + 10.0
	return Rect2(pos.x + 20.0, ty, dims.x - 40.0, pos.y + dims.y - 16.0 - ty)


func _sheet_fit() -> void:
	## The sheet's panel ends 18 units under the lowest thing drawn after it.
	if not is_instance_valid(_sheet_box):
		return
	var bottom := 0.0
	for i in range(_sheet_box.get_index() + 1, content.get_child_count()):
		var c := content.get_child(i) as Control
		if c != null and c.visible:
			bottom = maxf(bottom, c.position.y + maxf(c.size.y, c.get_combined_minimum_size().y))
	_sheet_box.size.y = bottom - _sheet_box.position.y + 18.0


func _lobby_sheet_draw(host: bool) -> void:
	_lobby_sheet_body(host)
	_sheet_fit()


func _lobby_sheet_body(host: bool) -> void:
	var which := _lobby_sheet
	var rowh := UiKit.tap_h(self, 44.0)
	var locked := Net.ready_locked() or Net.active
	if which == "mode":
		var r := _sheet_frame("ROOM / MODE", "HOW MANY PLAY." if host else "THE HOST PICKS THE MODE.", Vector2(900, 330))
		var room_modes: Array = Net.MODES.filter(func(x): return x in MODES_OFFERED)   # 3.0: 1v1 only
		var mcols := 4
		var mw := floorf((r.size.x - 10.0 * (mcols - 1)) / mcols)
		var mh := UiKit.tap_h(self, 60.0)
		for i in range(room_modes.size()):
			var m2: String = room_modes[i]
			var mb := UiKit.btn(self, Net.MODE_LABELS[m2], r.position + Vector2((i % mcols) * (mw + 10.0), (i / mcols) * (mh + 10.0)), Vector2(mw, 60), func():
				Net.set_mode(m2)
				_close_lobby_sheet(), "selected" if m2 == Net.mode else "secondary", shell_f, 18)
			mb.disabled = not host or Net.roster.size() > Net.SLOTS[m2] or Net.maps_for(m2).is_empty()
		var hh := ceilf(room_modes.size() / float(mcols)) * (mh + 10.0) - 10.0
		_say("A mode needs a map that seats it; greyed modes have none, or fewer seats than players in the room.",
				r.position + Vector2(0, hh + 10.0), 13, UiKit.MUTED, r.size.x)
	elif which == "rules":
		var r := _sheet_frame("ROOM / RULES", "MATCH RULES." if host else "THE HOST SETS THE RULES.", Vector2(900, 330))
		var tw := floorf((r.size.x - 10.0) / 2.0)
		var big := UiKit.tap_h(self, 64.0)
		var y := r.position.y
		var items := [
			["LAST STAND  ·  %s" % ("ON" if Net.last_stand else "OFF"), Net.last_stand, func(): Net.toggle_last_stand()],
			["ABILITIES  ·  %s" % ("ON" if Net.abilities else "OFF"), Net.abilities, func(): ArmyPresets.room_toggle_abilities(Net)],
			["EMPTY SEATS  ·  %s" % ("AI " + Net.ai_fill.to_upper() if Net.ai_fill != "" else "PLAYERS"), Net.ai_fill != "",
				func(): Net.set_ai_fill(Net.AI_FILL[(Net.AI_FILL.find(Net.ai_fill) + 1) % Net.AI_FILL.size()])]]
		for k in range(items.size()):
			var it: Array = items[k]
			var act: Callable = it[2]
			var b := UiKit.btn(self, it[0], r.position + Vector2((k % 2) * (tw + 10.0), (k / 2) * (big + 10.0)), Vector2(tw, 64), func():
				act.call()
				show_lobby(), "selected" if it[1] else "secondary", shell_f, 18)
			b.disabled = not host
		y += 2.0 * (big + 10.0)
		var note := "Tap a rule to change it; everyone sees the change and READY resets." if host else "Only the host changes these."
		if host and not Net.can_start():
			note += " DEPLOY opens when every seat is filled (or EMPTY SEATS: AI) and every player is READY."
		_say(note, Vector2(r.position.x, y), 13, UiKit.MUTED, r.size.x)
	elif which == "setting":                          # SETTING PICK: the owner's, for everyone (was BACKGROUND)
		var r := _sheet_frame("ROOM / SETTING", "WHERE THE BATTLE IS FOUGHT." if host else "THE HOST PICKS THE SETTING.", Vector2(1100, 380))
		var used := _setting_tiles(r, LookTheme.of_room_value(Net.room_backdrop), func(id):
			UiKit.save_setting_choice(id)
			Net.set_room_backdrop(LookTheme.room_value(id))
			_close_lobby_sheet(), shell_f, host)
		_say("Everyone in the room plays in it: the walls, the floor, the kit and the HUD." if host else "Only the host changes it.",
				r.position + Vector2(0, used + 8.0), 13, UiKit.MUTED, r.size.x)
	elif which == "faction":
		var r := _sheet_frame("ROOM / YOUR FACTION", str(UiKit.TAGS[faction]) + ".", Vector2(900, 330))
		var fr0 := content.get_child_count()
		var fh := _faction_row(r.position, minf(190.0, r.size.x / 5.0 - 14.0))
		if locked:
			_ready_lock(fr0)
		_say("Your ARMIES preset for it comes along (its skills). " + ("You're READY: UN-READY to change." if Net.ready_locked() else ""),
				r.position + Vector2(0, fh + 10.0), 13, UiKit.MUTED, r.size.x)
	elif which == "colour":
		var mine := Net.colour_of(Net.local_id())
		var r := _sheet_frame("ROOM / YOUR COLOUR", (mine.to_upper() if mine != "" else "PICK A COLOUR") + ".", Vector2(900, 330))
		var cr0 := content.get_child_count()
		var ch := _colour_row(r.position, r.size.x, maxf(UiKit.tap_h(self, 70.0), floorf(r.size.x / 8.0) - 8.0))
		if locked:
			_ready_lock(cr0)
		var hint := "Every seat has one colour, the same on every screen. " + (("Teammates share a hue family (%s); a colour from a free family moves your team to it." % " / ".join(
				Net.families().map(func(f): return Rules.FAMILY_NAMES.get(f[0], "")))) if Net.mode in Net.TEAM_MODES else "Taken colours are greyed.")
		if Rules.colour_blind():
			hint += " COLOUR-BLIND MODE is on: in the match your screen shows colour-blind-safe colours."
		_say(hint, r.position + Vector2(0, ch + 10.0), 13, UiKit.MUTED, r.size.x)
	elif which.begins_with("seat:"):
		var slot := int(which.substr(5))
		var id := -1
		for pid in Net.roster:
			if int(Net.roster[pid]["slot"]) == slot:
				id = int(pid)
		var seat: String = Net.SEATS[slot]
		var me := id == Net.local_id()
		var head := ("YOU" if me else Net.name_of(id).to_upper()) if id >= 0 else ("AI " + Net.ai_fill.to_upper() if Net.ai_fill != "" else "OPEN SEAT")
		var r := _sheet_frame("ROOM / SEAT %s" % seat, head + ".", Vector2(900, 330))
		var y := r.position.y
		if id >= 0:
			var f: String = str(Net.roster[id]["faction"])
			var ps := 150.0
			portrait(f, Vector2(r.position.x, y), Vector2(ps, ps), Rules.seat_color(seat))
			var tx := r.position.x + ps + 16.0
			var tw := r.size.x - ps - 16.0
			var words := ["HOST · DEPLOYS" if id == Net.room_owner or (id == 1 and not Net.server_hosted()) else "JOINED"]
			if Net.is_away(id):
				words.append("RECONNECTING")
			elif id != Net.room_owner:
				words.append("READY" if Net.is_ready(id) else "NOT READY")
			var hue := Net.colour_of(id)
			if hue != "":
				words.append(hue.to_upper())
			var ty := y + _say(str(UiKit.TAGS[f]), Vector2(tx, y), 17, UiKit.accent(f), tw, true)
			ty += _say("  ·  ".join(words), Vector2(tx, ty + 2.0), 13, UiKit.MUTED, tw) + 10.0
			var lo = Net.roster[id].get("loadout", {})
			var holder := Control.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.position = Vector2(tx, ty)
			holder.size = Vector2(tw, 40)
			content.add_child(holder)
			_loadout_chips(holder, f, lo if lo is Dictionary else {}, 3.0 * 36.0 + 12.0, 20.0, 36.0)
			y += ps + 14.0
		else:                                         # ROUND 4: the vs-AI seat sheet + PLAYER (Daniele)
			var ai_on := Net.ai_fill != ""
			var kl := UiKit.line_h(self, 12, true)
			_say("WHO PLAYS" + ("" if host else "  ·  THE HOST PICKS"), Vector2(r.position.x, y), 12, UiKit.accent(shell_f), 0.0, true, 3)
			y += kl + 4.0
			var wh := UiKit.tap_h(self, 44.0)
			var ww := floorf((r.size.x - 8.0) / 2.0)
			var w0 := content.get_child_count()
			UiKit.btn(self, "PLAYER  ·  SHARE THE CODE", Vector2(r.position.x, y), Vector2(ww, 44), func():
				Net.set_ai_fill("")
				show_lobby(), "selected" if not ai_on else "secondary", shell_f, 14)
			UiKit.btn(self, "AI  ·  UNTIL A PLAYER JOINS", Vector2(r.position.x + ww + 8.0, y), Vector2(r.size.x - ww - 8.0, 44), func():
				Net.set_ai_fill("Standard" if Net.ai_fill == "" else Net.ai_fill)
				show_lobby(), "selected" if ai_on else "secondary", shell_f, 14)
			if not host or Net.active:
				_ready_lock(w0)
			y += wh + 12.0
			_seat_rows(r, str(Net.ai_picks.get(seat, "random")), Net.ai_fill, func(f):
				Net.set_ai_pick(seat, f)
				show_lobby(), func(lv):
				Net.set_ai_fill(lv)
				show_lobby(), host and ai_on and not Net.active, y)
			_sheet_fit()
			return
		# actions: team moves (you: switch; the host: move a player), else your own picks
		var acts := []
		if Net.mode in Net.TEAM_MODES and id >= 0 and (me or host):
			for t in Net.team_ids():
				var tt: int = t
				if Net.team_of(id) == tt or Net.free_slot_in(tt) < 0:
					continue
				var mb := UiKit.chip(self, "MOVE TO TEAM %d" % (Net.team_ids().find(tt) + 1), Vector2.ZERO, func():
					if me:
						Net.switch_team(tt)
					else:
						Net.move_to_team(id, tt)
					_close_lobby_sheet(), shell_f, false)
				mb.disabled = locked if me else Net.active
				acts.append(mb)
			if acts.is_empty():
				y += _say("Every other team is full: free a seat there to move.", Vector2(r.position.x, y), 13, UiKit.MUTED, r.size.x) + 8.0
		if me:
			for a in [["COLOUR", "colour"]]:
				var key: String = a[1]
				var b := UiKit.chip(self, a[0], Vector2.ZERO, func(): _open_lobby_sheet(key), shell_f, false)
				b.disabled = locked
				acts.append(b)
			var arm := UiKit.chip(self, "ARMY", Vector2.ZERO, func():
				_lobby_sheet = ""
				_pick(show_factions), shell_f, false)
			arm.disabled = locked
			acts.append(arm)
		elif id < 0:
			var sh := UiKit.chip(self, "SHARE CODE", Vector2.ZERO, _share_code, shell_f, false)
			sh.disabled = Net.room_code == ""
			acts.append(sh)
		if not acts.is_empty():
			_flow(acts, Vector2(r.position.x, minf(y, r.end.y - rowh)), r.size.x)
# --- end ROUND 2 lobby ---


func _step_map(d: int) -> void:
	var pool: Array = Net.maps_for(Net.mode)
	if pool.is_empty():
		return
	var i := pool.find(Net.map_path)
	Net.set_map(pool[posmod(i + d, pool.size())])
	show_lobby()


func _on_net_changed() -> void:
	if _page == "lobby" or (_page == "online" and Net.in_room()):
		_join_open = false
		show_lobby()
	elif _page == "online":
		show_main()


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
		show_main()
		return
	_code_error = ""
	_code_value = code
	ArmyPresets.send_to(Net, faction)                         # the register carries your ARMIES preset
	Net.join_room(code, faction)
	if Net.in_room():
		_join_open = false
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
	if _page == "lobby" and _lobby_sheet == "":              # ROUND 4: the room chat panel shows a new line
		var hist: Array = Net.chat_history
		var last := int(hist[-1].get("id", hist.size())) if not hist.is_empty() else -1
		if last != _chat_seen:
			_chat_seen = last
			show_lobby()
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



func _stage_page(crumb: String, tab: String, title: String, sub := "", back := Callable(), f := "", sub_box := Vector2(380, 797)) -> Kit45.Stage:
	## A remake page (45B): the full header (37 pt) and nav (42 pt) on every screen (IMPORT-45B-SPEC fix 2), the remake's
	## 812 x 375 pt canvas over the content (Kit45.Stage), the title at the top left and the kicker at the right.
	## `back` = the page's own way back (Android back / Esc via bar_back); the remake has no BACK in the header.
	shell_open(crumb, tab, Callable(), f)
	shell_back = back
	var st := Kit45.Stage.new()
	st.setup(self, content.size)
	content.add_child(st)
	_stage = st
	if title != "":
		st.txt(title, 15, 45, 420, 26, 18.0, UiKit.INK, true)
	if sub != "":
		st.txt(sub, sub_box.x, 45, sub_box.y - sub_box.x, 26, 12.5, Kit45.KICK, true, 2)
	return st



func _sel45(st: Kit45.Stage, x: float, y: float, w: float, h: float, kicker: String, value: String, call: Callable, off := false) -> Kit45.Btn:
	## A SELECTOR-CARD: kicker over value (runtime text), chevron painted, an optional thumbnail / swatch (acc_tex / acc_col).
	var b := st.key("SELECTOR-CARD", x, y, w, h, kicker, call, false, off)
	b.value = value if value != "" else "-"
	return b



func _seat45(st: Kit45.Stage, i: int, id: int, colours: Dictionary, x: float, y: float) -> void:
	## One SEAT-CARD (45B 170 x 72 pt): FILLED / READY (seat rim lit) / LEAVING (away) / OPEN; the letter square and the edge
	## bar in the seat's room colour; the army in the avatar well; name + state; the three chosen skills in the chips.
	var seat: String = Net.SEATS[i]
	var col: Color = Rules.HUES.get(str(colours.get(seat, "")), Rules.SEATS.get(seat, Color.WHITE))
	var me := id >= 0 and id == Net.local_id()
	var team := Net.team_of_slot(i) if Net.mode in Net.TEAM_MODES else -1
	var sit := id < 0 and team >= 0 and Net.team_of(Net.local_id()) != team and Net.free_slot_in(team) >= 0 \
			and not Net.ready_locked() and not Net.active
	var stt := "OPEN"
	var state := ("AI " + Net.ai_fill.to_upper()) if Net.ai_fill != "" else "Waiting…"
	var state_col := UiKit.MUTED
	var name_t := "OPEN"
	if id >= 0:
		name_t = "YOU" if me else Net.name_of(id).to_upper()
		stt = "FILLED"
		if id == Net.room_owner or (id == 1 and not Net.server_hosted()):
			state = "HOST"
			state_col = col
		elif Net.is_away(id):
			state = "AWAY"
			stt = "LEAVING"
			state_col = UiKit.STAR
		elif Net.is_ready(id):
			state = "READY"
			stt = "READY"
			state_col = col
		else:
			state = "NOT READY"
	elif sit:
		state = "SIT HERE"
		state_col = _viewer_col()
	var p := st.piece("SEAT-CARD", x, y, 170, 72, stt)
	p.tints = {"edge": col, "letter": col, "seat": col}
	var ink := Kit45.ink_on("SEAT-CARD", p.key, stt, [53, 7, 108, 16])
	st.txt(seat, x + 8, y + 4, 16, 16, 12.5, Kit45.INK_DARK, true, 1)
	if id >= 0:
		var f: String = str(Net.roster[id]["faction"])
		st.add_child(_cutout_mark(f, st.P(x + 8, y + 23), Vector2(38, 38) * st.u))
		var lo = Net.roster[id].get("loadout", {})
		var eff := ArmyPresets.effective(f, lo if lo is Dictionary else {}, ArmyPresets.map_has_relays(_selected_map()))
		var ids := [eff["active"], eff["map"], eff["ultimate"]]
		for k in range(3):                             # Daniele 11-18: chips 22 pt (the 30 pt part, rim intact), icons 16 pt, no glow
			st.piece("SKILL-CHIP", x + 53 + 25 * k, y + 44, 22, 22, "STATIC", "30x30pt")
			var ic := st.pic(ArmyPresets.icon(str(ids[k])), x + 56 + 25 * k, y + 47, 16, 16, false, Color(UiKit.accent(f), 1.0 if Net.abilities else 0.35))
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		st.txt("+", x + 17, y + 34, 20, 16, 16.0, UiKit.MUTED, true, 1)
	st.txt(name_t, x + 53, y + 7, 108, 16, 13.0, ink if id >= 0 else Color(ink, 0.6), true)
	st.txt(state, x + 53, y + 25, 108, 16, 12.5, state_col if state_col != UiKit.MUTED else Color(ink, 0.7), true)
	var call := func(): _open_lobby_sheet("seat:%d" % i)
	if sit:
		call = func(): Net.switch_team(team)
	var tb := st.tap(x, y, 170, 72, call)
	tb.text = seat + " " + name_t                     # (tests find the seats by their text)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		tb.add_theme_color_override(k, Color(0, 0, 0, 0))



func _room_chat45(st: Kit45.Stage) -> void:
	## The ROOM-CODE-PANEL (197 x 177 pt at 600, 81): ROOM CODE + the code (cream, never red), SHARE, the newest chat lines
	## that fit the log, and the message field (web: the native chat field, phone keyboards). Rebuilt when a line arrives.
	var x := 600.0
	var y := 81.0
	st.piece("ROOM-CODE-PANEL", x, y, 197, 177)
	st.txt("ROOM CODE", x + 10, y + 10, 111, 16, 12.5, Kit45.KICK, true)
	st.txt(Net.room_code if Net.room_code != "" else "····", x + 10, y + 33, 111, 26, 22.0, UiKit.INK, true)
	st.key("KEY-SMALL", x + 123, y + 13, 62, 33, "SHARE", _share_code, false, Net.room_code == "")
	var lines: Array = Net.chat_history
	_chat_seen = int(lines[-1].get("id", lines.size())) if not lines.is_empty() else -1
	_chat_btn = null
	if lines.is_empty():
		st.txt("No messages yet. Say hi.", x + 16, y + 69, 165, 16, 12.5, UiKit.DIM)
	else:
		var shown := lines.slice(maxi(0, lines.size() - 4))
		var ly := y + 131.0 - 16.0 * shown.size()
		for m in shown:
			var who := "YOU" if int(m.get("pid", -1)) == Net.local_id() else str(m.get("who", "?")).to_upper()
			st.txt("%s: %s" % [who, str(m.get("text", ""))], x + 12, ly, 173, 16, 12.5, UiKit.INK)
			ly += 16.0
	var off := not Net.connected or not OS.has_feature("web")
	var cf := st.piece("CHAT-FIELD", x + 10, y + 135, 177, 33, "DISABLED" if off else "NORMAL")
	cf.tints = {"seat": Kit45.seat()}
	st.txt("Type a message…", x + 18, y + 143, 161, 16, 12.5, Color(UiKit.MUTED, 0.5 if off else 1.0))
	if not off:
		var tb := st.tap(x + 10, y + 135, 177, 33, Net.open_chat)
		tb.text = "TYPE A MESSAGE…"
		tb.add_theme_color_override("font_color", Color(0, 0, 0, 0))



func show_room_demo() -> void:
	## SCREENSHOT HELPER only (--menu-page=room_demo [--room-mode=2v2]): a made-up four-seat room (host YOU, a ready player,
	## an open seat, an away player) and two chat lines, so the ONLINE ROOM can be shot offline. Never reached in play.
	Net.bridge = RefCounted.new()
	Net.hosting = true
	Net.connected = true
	Net.room_owner = 1
	Net.room_code = "TSBP"
	Net.mode = "FFA4"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-mode="):
			Net.mode = arg.substr(12)
	var fs := [faction, "null", "", "bloom"]
	Net.roster = {}
	for k in range(Net.slots()):
		if fs[k % 4] == "":
			continue
		Net.roster[k + 1] = {"faction": fs[k % 4], "slot": k, "name": "Player %d" % (k + 1), "ready": k == 1, "away": k == 3}
	Net.chat_history = [{"id": 1, "pid": 2, "who": "Player 2", "text": "gl hf"}, {"id": 2, "pid": 1, "who": "you", "text": "ready when you are"}]
	Net.map_path = map_path
	show_lobby()



var _pg := {}                                      # 45B pagers: page -> the page index shown (no scrolling: ‹ › pages)



static func _thou(n: int) -> String:
	## 6620 -> "6,620" (the remake's numbers)
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out



func _profile_tabs(sel: String, crumb: String, back := Callable(), sub := "YOUR SYNDICATE RECORD", sub_box := Vector2(380, 797)) -> Kit45.Stage:
	## The PROFILE family (45B): PROFILE / YOUR SYNDICATE RECORD over four SUB-TABs (CHALLENGES, LEADERBOARD, MATCH HISTORY,
	## ACCOUNT); `sel` lit (copper + seat rim), "" on the overview. The nav keeps PROFILE lit.
	var st := _stage_page(crumb, "profile", "PROFILE", sub, back, faction, sub_box)
	var tabs := [["CHALLENGES", func(): show_challenges()], ["LEADERBOARD", show_leaderboard], ["MATCH HISTORY", show_history],
			["ACCOUNT", show_account]]
	for i in range(4):
		var t: String = tabs[i][0]
		var b := st.key("SUB-TAB", 15 + 197 * i, 74, 191, 34, t, tabs[i][1] if t != sel else Callable(), t == sel, false, "191x34pt")
		b.size_pt = 13.0
	return st



func _pager(st: Kit45.Stage, page: String, n_pages: int, redraw: Callable, x := 331.0, y := 299.0, more := Callable()) -> int:
	## ‹ p / n › (KEY-SMALL 36 x 33); returns the page index to show. `more`: › on the last page asks for more (history).
	var p := clampi(int(_pg.get(page, 0)), 0, maxi(0, n_pages - 1))
	_pg[page] = p
	var lb := st.key("KEY-SMALL", x, y, 36, 33, "‹", func():
		_pg[page] = p - 1
		redraw.call(), false, p <= 0)
	lb.size_pt = 18.0
	st.txt("%d / %d" % [p + 1, maxi(1, n_pages)], x + 42, y + 8, 66, 16, 12.5, UiKit.INK, true, 1)
	var last := p >= n_pages - 1
	var rb := st.key("KEY-SMALL", x + 114, y, 36, 33, "›", func():
		if last and more.is_valid():
			more.call()
		else:
			_pg[page] = p + 1
			redraw.call(), false, last and not more.is_valid())
	rb.size_pt = 18.0
	return p



func _challenge_row45(st: Kit45.Stage, kind: String, c: Dictionary, x: float, y: float, just_claimed: String, rerolled: bool) -> void:
	var claimed: bool = c["claimed"]
	var done: bool = c["done"]
	var id: String = c["id"]
	var state := "DONE" if claimed else ("CLAIM" if done else "IN-PROGRESS")
	var row := st.piece("CHALLENGE-ROW", x, y, 762, 72, state)
	row.fill = float(c["progress"]) / maxf(1.0, float(c["target"]))
	row.tints = {"fill": Kit45.seat(), "seat": Kit45.seat()}
	var ink := Kit45.ink_on("CHALLENGE-ROW", row.key, state, [13, 9, 426, 16])
	st.txt(str(c["text"]), x + 13, y + 9, 615, 16, 13.0, Color(ink, 0.55) if claimed else ink, true)   # FIX 2: the title gets the line
	st.txt(("DAILY · " if kind == "daily" else "WEEKLY · ") + "%d / %d" % [int(c["progress"]), int(c["target"])], x + 13, y + 29, 426, 16, 12.5, ink)
	var reward := "%s  ·  +%d XP" % [Progression.amount_text(int(c["soft"])), int(c["xp"])]
	if int(c["premium"]) > 0:
		reward += "  ·  " + Progression.amount_text(int(c["premium"]), "premium")
	st.txt(reward, x + 13, y + 49, 426, 16, 12.5, RewardTicker.COLOURS["soft"])
	var kx := x + 640.0
	var ky := y + 19.0
	if claimed:
		if id == just_claimed:                          # the paid SCRAP counts up on the row it came from
			var t := _ticker(int(c["soft"]), "soft", st.P(kx, ky), false)
			t.position.y = st.P(0, ky + 17).y - t.size.y / 2.0
		else:
			st.txt("DONE", kx, ky + 9, 109, 16, 13.0, Color(ink, 0.6), true, 1)
	elif done:
		st.key("KEY-SMALL", kx, ky, 109, 34, "CLAIM", func():
			if not Progression.claim(kind, id).is_empty():
				show_challenges(id), true)
	elif kind == "daily" and not rerolled:
		st.key("KEY-SMALL", kx, ky, 109, 34, "REROLL", func():
			Progression.reroll(id)
			show_challenges())
	else:
		st.txt("IN PROGRESS", kx, ky + 9, 109, 16, 12.5, Color(ink, 0.7), true, 1)



func _table45(st: Kit45.Stage, cols: Array, rows: Array, page: String, redraw: Callable, empty: String, more := Callable()) -> void:
	## The records table (45B LEADERBOARD / MATCH HISTORY): a HERO-CABINET, the column heads in bronze, four HERO-TITLE-BAR
	## rows a page, ‹ p / n › under it. cols = [[head, x, w]]; a row = [cells] or [cells, colours].
	st.piece("HERO-CABINET", 15, 114, 782, 180, "STATIC", "782x180pt")
	for c in cols:
		st.txt(str(c[0]), float(c[1]), 120, float(c[2]), 16, 12.5, Kit45.KICK, true)
	var n_pages := maxi(1, ceili(rows.size() / 4.0))
	var p := _pager(st, page, n_pages, redraw, 331, 299, more)
	if rows.is_empty():
		st.piece("HERO-TITLE-BAR", 26, 142, 760, 32, "STATIC", "760x32pt")
		st.txt(empty, 35, 150, 740, 16, 12.5, UiKit.MUTED)
		return
	for k in range(4):
		var i := p * 4 + k
		if i >= rows.size():
			break
		var y := 142.0 + 36.0 * k
		st.piece("HERO-TITLE-BAR", 26, y, 760, 32, "STATIC", "760x32pt")
		var r: Array = rows[i]
		var cells: Array = r[0]
		var cc: Array = r[1] if r.size() > 1 else []
		for j in range(mini(cells.size(), cols.size())):
			var col: Color = cc[j] if j < cc.size() and cc[j] is Color else UiKit.INK
			st.txt(str(cells[j]), float(cols[j][1]), y + 8, float(cols[j][2]), 16, 12.5, col, j == 0 or j == 1)



func show_join_demo() -> void:
	## SCREENSHOT HELPER only (--menu-page=join_demo): the JOIN page with two letters typed.
	_join_open = true
	_code_value = "TS"
	show_main()



func _opt45(st: Kit45.Stage, at: Array, label: String, opts: Array, off := false, redraw := true) -> void:
	## A settings row at at = [x, y] (advanced by 41 pt): the label, then the option keys (KEY-SMALL, the picked one SELECTED).
	var x: float = at[0]
	var y: float = at[1]
	st.txt(label, x, y + 9, 96, 16, 12.5, UiKit.INK, true)
	var room := 355.0 - 100.0
	var gap := 6.0
	var kw := minf(76.0, (room - gap * (opts.size() - 1)) / opts.size())
	if opts.size() == 1:
		kw = 155.0
	var kx := x + 100.0
	for o in opts:
		var apply: Callable = o[2]
		var b := st.key("KEY-SMALL", kx, y, kw, 34, str(o[0]), func():
			apply.call()
			if redraw:
				show_options(), bool(o[1]), off)
		b.size_pt = 12.5
		kx += kw + gap
	at[1] = y + 41.0



func _step45(st: Kit45.Stage, at: Array, label: String, n: int, now: int, shown: String, set_i: Callable) -> void:
	## A stepper row (3.0 WP4, OPTIONS > GAME > Count size): the label, a "-" key, the value, a "+" key; each tap moves one step
	## (greyed at either end) and applies at once.
	var x: float = at[0]
	var y: float = at[1]
	st.txt(label, x, y + 9, 96, 16, 12.5, UiKit.INK, true)
	var kw := 60.0
	var minus := st.key("KEY-SMALL", x + 100.0, y, kw, 34, "-", func():
		set_i.call(now - 1)
		show_options(), false, now <= 0)
	minus.size_pt = 16.0
	minus.name = "Step- " + label
	st.txt(shown, x + 100.0 + kw + 4.0, y + 9, 355.0 - 100.0 - 2.0 * kw - 8.0, 16, 12.5, UiKit.INK, true, 1)
	var plus := st.key("KEY-SMALL", x + 355.0 - kw, y, kw, 34, "+", func():
		set_i.call(now + 1)
		show_options(), false, now >= n - 1)
	plus.size_pt = 16.0
	plus.name = "Step+ " + label
	at[1] = y + 41.0


func _vol45(st: Kit45.Stage, at: Array, label: String, steps: Array, now: int, shown: String, set_v: Callable, off := false) -> void:
	## A volume row as the remake's slider (designer 11 FIX 10): the label, the track (XP-BAR, seat-colour fill) with a 34 pt
	## tap / drag box over it, the value at the right. Discrete steps of Rules; the value is set on release.
	var x: float = at[0]
	var y: float = at[1]
	st.txt(label, x, y + 9, 96, 16, 12.5, UiKit.INK, true)
	var i := maxi(0, steps.find(now))
	var bar := st.piece("XP-BAR", x + 100, y + 13, 200, 8)
	bar.fill = float(i + 1) / float(steps.size()) if not off else 0.0
	bar.tints = {"fill": Kit45.seat()}
	st.txt(shown, x + 304, y + 9, 50, 16, 12.5, UiKit.INK if not off else UiKit.MUTED, true, 1)
	if off:
		at[1] = y + 41.0
		return
	var hit := st.tap(x + 96, y, 208, 34, Callable())
	hit.name = "Slider " + label
	var pick := func(px: float) -> int:
		return clampi(int(round(clampf(px / hit.size.x, 0.0, 1.0) * steps.size() - 0.5)), 0, steps.size() - 1)
	hit.gui_input.connect(func(e: InputEvent):
		var pos := Vector2(-1, -1)
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pos = (e as InputEventMouseButton).position
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pos = (e as InputEventMouseMotion).position
		if pos.x < 0.0:
			return
		var k: int = pick.call(pos.x)
		bar.fill = float(k + 1) / float(steps.size())
		bar.queue_redraw()
		if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
			set_v.call(int(steps[k]))
			show_options())
	at[1] = y + 41.0



const GUIDE := {
	"basics": [
		["TAKE CONTROL", ["Drag from your vat to a connected target.", "Pick 25 %, 50 %, 75 % or 100 % before sending.",
				"Grey nodes never regrow: take them.", "Tap a node to inspect it; UPGRADE in its panel, or double-tap a node you own."]],
		["LEARN BY DOING", ["TRAINING walks you through a first match.", "PLAY VS AI: pick the AI level in MATCH SETUP.",
				"ONLINE: host a room and share its four-letter code.", "CHALLENGES pay SCRAP and XP: claim them in PROFILE."]]],
	"factions": [
		["FIVE SYNDICATES", ["VEX, NULL, BLOOM, EMBER and AEGIS: one army each.", "Every army has its own stats, skills and ultimate.",
				"ARMIES shows them all and keeps your picks.", "Win with a faction to unlock its own vat."]]],
	"skills": [
		["ABILITIES", ["Pick an active, a map skill and the ultimate in ARMIES.", "A ready ability has a bright frame.",
				"Tap it, then choose a valid target.", "Map skills need relays; without them a fallback skill plays."]]],
	"maps": [
		["RELAYS", ["Relays move bridges: retract, switch, ferry, conveyor, launcher.", "A laser relay is a laser tower anyone can take.",
				"Neutral relay buildings fire only when attacked.", "MAP PICKER shows each map's relays and node count."]]],
}
