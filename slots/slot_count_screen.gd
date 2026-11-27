extends Node3D
## COUNT SCREEN SLOT (Slots3, plan 3.0-ARCHITECTURE-PLAN 2026-11-27 sec 2.5, WP4; WP4b: the node's notices). The screen of one
## node, a model of its own, separate from the structure: VatCount mounts one per node on its structure slot's ScreenMount (over
## the model). Contract of the root: origin = the panel's centre at its base size; local +y = the panel's up, local +z = its face
## (VatCount leans it back to the Board3 camera's pitch, so it faces the eye squarely and does not swim on a pinch).
##   build(digit_h)       sizes it (base panel = three digits; `size` stays that base size: placement, tap pick, top band)
##   set_seat_colour(col) the frame (neon = seat) and the ink, the idle look
##   set_frame(col)       the frame alone (an alarm: under attack, a Last Stand launch)
##   set_ink(col)         the words / digits alone
##   set_text(t)          the count, or a notice ("TAKEN", "5s", "▼T2", ...): a wider word widens the panel round its centre,
##                        a second line (one font line more) grows it upward, so its lower edge stays on the mount
##   set_tab(glyph, col)  a symbol over the frame's top edge ("" hides it): ▲ upgrade ready, the relay glyph when it can fire
## Today: a dark panel, a neon frame and Rajdhani digits drawn by the game (never the structure's Face_num_*); the new frame art
## replaces _quad() later, not the callers. Drawn without depth test above the units (render_priority 1..5), so neither the
## tower nor a line on the platform covers it.

const FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSansMono.woff2")   # ▲ and the relay glyphs (Rules.RELAY_GLYPH)
const DIGIT_EM := 0.643             # Rajdhani SemiBold digit height / em (fontTools bounds of 0-9)
const DIGIT_ADV := 0.533            # its digit advance / em
const FONT_PX := 96                 # Label3D font size (pixel_size = em / FONT_PX)
const PANEL_H := 1.5                # panel height / digit height
const FRAME := 0.12                 # m of neon frame round the panel (x digit height)
const TAB_H := 1.0                  # the tab glyph's height / digit height (>= 12.5 pt where the digits are)

var scale_k := 1.0
var digit_h := 1.0                  # m, set by build()
var size := Vector2.ZERO            # the panel's BASE size in m (frame excluded): three digits, one line
var shown := Vector2.ZERO           # the panel's size now (a word or two lines make it bigger)
var frame: MeshInstance3D
var panel: MeshInstance3D
var label: Label3D
var tab: Label3D
var _text := ""


func build(digit_height_m: float, digits := 3) -> void:
	## digit_height_m = the digits' height in m (VatCount.digit_height_m(): base x the OPTIONS count size).
	digit_h = digit_height_m
	var em := digit_h / DIGIT_EM
	size = Vector2(em * DIGIT_ADV * digits + digit_h * 0.5, digit_h * PANEL_H)
	for c in get_children():
		c.free()
	frame = _quad(Vector2.ONE, Color.WHITE, 1)
	add_child(frame)
	panel = _quad(Vector2.ONE, Color(0.03, 0.04, 0.06, 0.92), 2)
	add_child(panel)
	label = _label(_word_font(), em / FONT_PX, 4)
	add_child(label)
	tab = _label(SYMBOL_FONT, digit_h * TAB_H / FONT_PX / 0.73, 5)   # (DejaVu ▲ is ~0.73 em tall)
	tab.visible = false
	add_child(tab)
	_text = ""
	_fit()


func set_seat_colour(col: Color) -> void:
	set_frame(col)
	set_ink(col.lerp(Color.WHITE, 0.35))


func set_frame(col: Color) -> void:
	(frame.material_override as StandardMaterial3D).albedo_color = col


func set_ink(col: Color) -> void:
	label.modulate = col


func set_text(t: String) -> void:
	if t == _text:
		return
	_text = t
	label.text = t
	_fit()


func set_tab(glyph: String, col := Color.WHITE, lift := 0.0) -> void:
	## lift: m the glyph bobs up (VatCount pulses it).
	tab.visible = glyph != ""
	if glyph == "":
		return
	tab.text = glyph
	tab.modulate = col
	tab.position = Vector3(0.0, _top() + digit_h * (FRAME + TAB_H * 0.62) + lift, 0.03)


func _fit() -> void:
	## The panel round the text: never narrower than three digits, one line high per line; the lower edge stays put.
	var lines := _text.split("\n")
	var w := 0.0
	for l in lines:
		w = maxf(w, FONT.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x * label.pixel_size)
	shown = Vector2(maxf(size.x, w + digit_h * 0.5), size.y + FONT.get_height(FONT_PX) * label.pixel_size * float(lines.size() - 1))
	var dy := (shown.y - size.y) * 0.5
	(frame.mesh as QuadMesh).size = shown + Vector2.ONE * FRAME * 2.0 * digit_h
	(panel.mesh as QuadMesh).size = shown
	frame.position = Vector3(0.0, dy, 0.0)
	panel.position = Vector3(0.0, dy, 0.01)
	label.position = Vector3(0.0, dy, 0.02)
	if tab.visible:
		tab.position.y = _top() + digit_h * (FRAME + TAB_H * 0.62)


static var _wf: FontVariation


static func _word_font() -> Font:
	## Rajdhani with DejaVu behind it: "▼T2" and other symbols on a web build, which has no system fonts to fall back on.
	if _wf == null:
		_wf = FontVariation.new()
		_wf.base_font = FONT
		_wf.fallbacks = [SYMBOL_FONT]
	return _wf


func _top() -> float:
	return shown.y - size.y * 0.5


func _label(font: Font, px: float, prio: int) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = FONT_PX
	l.pixel_size = px
	l.outline_size = int(FONT_PX * 0.16)
	l.outline_modulate = Color(0.01, 0.01, 0.03, 1.0)
	l.no_depth_test = true
	l.fixed_size = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.render_priority = prio
	l.outline_render_priority = prio - 1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _quad(sz: Vector2, col: Color, prio: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = sz
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = prio
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
