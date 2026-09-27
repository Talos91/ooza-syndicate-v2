class_name UiKit
extends RefCounted
## Alpha 21 UI pass (Daniele 2026-09-28: Mushroom Wars 2's structure, our neon cyber style): the theme and
## phone sizing shared by the app shell (TopBar, NavBar), FrameCard and the shell pages (HOME, the campaign
## hub, the versus screen). Sizes here are 1280x720 CANVAS units - what the shell pages lay out in - not
## Alpha 11's raw units (menu.gd's P() / K); the phone minimums (44 pt taps, 12.5 pt text) come from
## Menu's live viewport fit, so the shell keeps the same rules as every other page.

const HEAD := preload("res://assets/fonts/RussoOne-Regular.ttf")
const BODY := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const INK := Color("edf7fa")
const MUTED := Color("839da9")
const DIM := Color("5b7582")
const CYAN := Color("18dae8")
const BAR := Color("030b11f4")                    # top / bottom bars
const CARD := Color("06141cec")                   # card fill
const ORDER := ["vex", "null", "bloom", "ember", "solar"]
const TAGS := {"vex": "VEX / BIOENGINEERS", "null": "NULL / CARTEL", "bloom": "VIRIDIAN / BLOOM",
		"ember": "EMBER / MAW", "solar": "SOLAR / SHELLS"}
const CFG := "user://ui.cfg"
const K := 1280.0 / 1672.0                       # = Menu.K, Menu.MIN_TAP_PT, Menu.MIN_FONT_PT - copied so the pieces
const MIN_TAP_PT := 44.0                          #   (and their tests) load without menu.gd and its autoloads
const MIN_FONT_PT := 12.5


static func accent(f: String) -> Color:
	return Rules.FACTIONS[f][1] if Rules.FACTIONS.has(f) else CYAN


static func pt(m) -> float:
	## One canvas unit in pt at the live fit (landscape-phone reference); 0.0 on desktop (no minimum).
	var f: float = m._pt_factor()
	return f / K if f > 0.0 else 0.0


static func tap_h(m, h: float) -> float:
	## A tappable height in canvas units: `h`, or taller where a phone needs it for 44 pt.
	var p := pt(m)
	return maxf(h, MIN_TAP_PT / p) if p > 0.0 else h


static func px(m, size: float) -> int:
	## A font size in canvas units, grown on phones to >= 12.5 pt.
	var p := pt(m)
	return int(round(maxf(size, MIN_FONT_PT / p) if p > 0.0 else size))


static func label(m, text: String, size: float, col := INK, head := false, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	var font: Font = HEAD if head else BODY
	if spacing != 0:                                 # the spaced-out kickers / breadcrumbs of the mockups
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = spacing
		font = fv
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px(m, size))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func text_w(m, text: String, size: float, head := false) -> float:
	## A one-line text's width at its (phone-grown) size - Label.get_minimum_size() is unreliable before the tree.
	return (HEAD if head else BODY).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px(m, size)).x


static func text_h(m, text: String, size: float, width: float, head := false) -> float:
	## A word-wrapped text's height inside `width` (for laying out before the label is in the tree).
	var f: Font = HEAD if head else BODY
	return f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, px(m, size), -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y


static func flat_button(m, text: String, size: float, col := INK) -> Button:
	## A text-only button ("Continue campaign", "New here? Start training ->"): no frame, the accent on hover,
	## still a full-height tap target on phones.
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", BODY)
	b.add_theme_font_size_override("font_size", px(m, size))
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", CYAN)
	b.add_theme_color_override("font_pressed_color", CYAN)
	var none := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, none)
	return b


static func rect(pos: Vector2, dims: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = dims
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ------------------------------------------------------------------ the last played faction (HOME's hero)
static var path := CFG                             # tests point it elsewhere; UI preferences only, never progression


static func last_faction() -> String:
	## Daniele 2026-09-28: HOME always shows the faction you played last - VEX until you have played one.
	var c := ConfigFile.new()
	if c.load(path) != OK:                           # none yet, or no storage at all (private browsing)
		return "vex"
	var f := str(c.get_value("home", "faction", "vex"))
	return f if Rules.FACTIONS.has(f) else "vex"


static func save_last_faction(f: String) -> bool:
	if not Rules.FACTIONS.has(f):
		return false
	var c := ConfigFile.new()
	c.load(path)                                      # keep anything else saved there (none: a fresh file)
	c.set_value("home", "faction", f)
	return c.save(path) == OK


static func hero_art(f: String) -> Texture2D:
	## The faction's scene with its creature on the right (assets/art/<faction>.png; VEX's is the MAIN art,
	## minus its left edge where Alpha 11's buttons are baked in).
	if f == "vex":
		var art: Texture2D = load("res://assets/art/ui-main.png")
		var clean := AtlasTexture.new()
		clean.atlas = art
		clean.region = Rect2(Vector2(art.get_size()) * Vector2(0.36, 0.0), Vector2(art.get_size()) * Vector2(0.64, 1.0))
		return clean
	return load("res://assets/art/%s.png" % f)
