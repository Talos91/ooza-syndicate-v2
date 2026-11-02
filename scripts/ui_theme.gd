class_name UiTheme
extends RefCounted
## Alpha 24 (UI round 3, Daniele 2026-11-02: "UI first", DARK and LIGHT with a switch in settings): the theme layer over
## Daniele's coordinate-ready pack (References/UI direction 2026-11-02 round-3/generated, imported by
## tools/ui_round3_import.py into assets/ui/round3/ and scripts/ui_round3_data.gd).
##   mode() / set_mode()   "dark" (default) | "light" - SETTINGS > DISPLAY > THEME, saved in user://settings.cfg [display]
##                         theme (with COLOUR-BLIND); --theme=light|dark on the command line wins (screenshots, tests)
##   box(id, ...)          a sprite (A1 panel, A5 primary, G1 list_row...) of the current mode as a SkinBox
##   icon(name)            a D / E / F icon (white, 160 px canvas) - tint it with modulate / self_modulate
##   theme()               one Godot Theme per mode for the plain controls a page makes (LineEdit, Panel, ScrollBar...)
## UiKit's colour tokens follow the mode (UiKit.apply_tokens); the HUD keeps its own colours (Alpha 24 step 2).

const DIR := "res://assets/ui/round3/"
const DATA := preload("res://scripts/ui_round3_data.gd")
const MODES := ["dark", "light"]
const SCALE := 0.36                                # source px -> canvas units: a 128 px primary is ~46 units tall
const PILLS := ["A5", "A6", "A7", "A8", "A9", "A10", "A11"]   # the pill buttons scale with their height (round ends stay round)

static var _mode := ""                             # "" until read
static var _match_dark := false                    # a match is on: dark only (match_dark)
static var _themes := {}                           # mode -> Theme
static var _by_name := {}                          # icon name -> id


static func _arg_mode() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--theme="):
			var v := a.substr(8)
			if v in MODES:
				return v
	return ""


static func match_dark(on: bool) -> void:
	## Alpha 24 Neon Noir (Daniele 2026-11-02: the in-match HUD is dark only): while a match runs (Hud.setup ... Hud exits) every
	## page built - pause, settings, results - is dark; the saved choice is untouched and comes back after the match.
	if _match_dark == on:
		return
	_match_dark = on
	UiKit.apply_tokens(light())


static func mode() -> String:
	if _match_dark:
		return "dark"
	if _mode == "":
		_mode = _arg_mode()
		if _mode == "":
			var c := ConfigFile.new()
			var v := str(c.get_value("display", "theme", "dark")) if c.load(Rules.settings_path) == OK else "dark"
			_mode = v if v in MODES else "dark"
	return _mode


static func light() -> bool:
	return mode() == "light"


static func set_mode(v: String) -> bool:
	## Switches the theme now (the next page built uses it) and saves it with the other display settings.
	if not v in MODES:
		return false
	_mode = v
	UiKit.apply_tokens(light())                        # (a match keeps dark until it ends)
	var c := ConfigFile.new()
	c.load(Rules.settings_path)                        # keep the rest of [display] / [audio]
	c.set_value("display", "theme", v)
	return c.save(Rules.settings_path) == OK


static func atlas(sheet: String, m := "") -> Texture2D:
	return UiKit.tex(DIR + (m if m != "" else mode()) + "/" + sheet + ".png")


static func has(id: String) -> bool:
	return DATA.SPRITES.has(id)


static func box(id: String, scale := SCALE, mod := Color.WHITE, content := 10.0, m := "") -> SkinBox:
	## The sprite `id` of mode `m` (the current one when "") as a StyleBox, its corners at `scale`.
	var s: Dictionary = DATA.SPRITES[id]
	var b := SkinBox.new()
	b.texture = atlas(str(s["sheet"]), m)
	var rc: Array = s["rect"]
	b.region = Rect2(rc[0], rc[1], rc[2], rc[3])
	var sl = s["slice"]
	if sl is Array:
		b.slice = Vector4(sl[0], sl[1], sl[2], sl[3])
	b.axis = "x" if id in PILLS else str(s["axis"])
	b.scale = scale
	b.modulate = mod
	b.set_content_margin_all(content)
	return b


static func sub_box(id: String, part: String, scale := SCALE, m := "") -> SkinBox:
	## One of a sprite's sub-parts (G9 scrollbar_parts: "track" / "thumb"), sliced by its subpart_slice.
	var s: Dictionary = DATA.SPRITES[id]
	var rc: Array = s["subparts"][part]
	var sl: Array = s["subpart_slice"]
	var b := SkinBox.new()
	b.texture = atlas(str(s["sheet"]), m)
	b.region = Rect2(rc[0], rc[1], rc[2], rc[3])
	b.slice = Vector4(sl[0], sl[1], sl[2], sl[3])
	b.scale = scale
	b.set_content_margin_all(0)
	return b


static func icon(n: String) -> Texture2D:
	## A D / E / F icon by name ("settings", "lock", "quake") or id ("D6"); null when the pack has none.
	if _by_name.is_empty():
		for id in DATA.ICONS:
			_by_name[str(DATA.ICONS[id]["name"])] = id
	var id: String = _by_name.get(n, n)
	if not DATA.ICONS.has(id):
		return null
	return UiKit.tex(DIR + str(DATA.ICONS[id]["file"]))


static func icon_rect(n: String, side: float, col: Color, pos := Vector2.ZERO) -> TextureRect:
	## The icon `side` units square, tinted `col`, not yet added (a button's or a row's child).
	var r := TextureRect.new()
	r.texture = icon(n)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.self_modulate = col
	r.position = pos
	r.size = Vector2(side, side)
	return r


static func theme() -> Theme:
	## The current mode's Theme (made once per mode): what a plain Button / Panel / LineEdit / ScrollBar / Label on a menu
	## page looks like before UiKit dresses it. Menu.clear_page sets it on each page's root.
	var m := mode()
	if _themes.has(m):
		return _themes[m]
	var t := Theme.new()
	t.default_font = UiKit.BODY
	t.set_color("font_color", "Label", UiKit.INK)
	t.set_stylebox("panel", "Panel", box("A1", SCALE, Color.WHITE, 10.0, m))
	t.set_stylebox("panel", "PanelContainer", box("A1", SCALE, Color.WHITE, 12.0, m))
	t.set_stylebox("normal", "Button", box("A7", SCALE, Color.WHITE, 10.0, m))
	t.set_stylebox("hover", "Button", box("A7", SCALE, Color(1.08, 1.08, 1.08), 10.0, m))
	t.set_stylebox("pressed", "Button", box("A8", SCALE, Color.WHITE, 10.0, m))
	t.set_stylebox("disabled", "Button", box("A9", SCALE, Color.WHITE, 10.0, m))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", UiKit.INK)
	t.set_stylebox("normal", "LineEdit", box("G4", SCALE, Color.WHITE, 14.0, m))
	t.set_stylebox("focus", "LineEdit", box("G5", SCALE, Color.WHITE, 14.0, m))
	t.set_stylebox("read_only", "LineEdit", box("G4", SCALE, Color(1, 1, 1, 0.6), 14.0, m))
	t.set_color("font_color", "LineEdit", UiKit.INK)
	t.set_color("font_placeholder_color", "LineEdit", UiKit.DIM)
	t.set_color("caret_color", "LineEdit", UiKit.INK)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, sub_box("G9", "track", 0.5, m))
		t.set_stylebox("grabber", sb, sub_box("G9", "thumb", 0.5, m))
		t.set_stylebox("grabber_highlight", sb, sub_box("G9", "thumb", 0.5, m))
		t.set_stylebox("grabber_pressed", sb, sub_box("G9", "thumb", 0.5, m))
	t.set_stylebox("panel", "PopupMenu", box("G7", SCALE, Color.WHITE, 10.0, m))
	t.set_stylebox("panel", "TooltipPanel", box("A1", SCALE, Color.WHITE, 8.0, m))
	t.set_color("font_color", "TooltipLabel", UiKit.INK)
	_themes[m] = t
	return t
