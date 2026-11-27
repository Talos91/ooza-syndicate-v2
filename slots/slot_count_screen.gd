extends Node3D
## COUNT SCREEN SLOT (Slots3, plan 3.0-ARCHITECTURE-PLAN 2026-11-27 sec 2.5, WP4). The unit count of one node, a model of its own,
## separate from the structure: VatCount mounts one per node on its structure slot's ScreenMount (over the model). Contract of
## the root: origin = the panel's centre; local +y = the panel's up, local +z = its face (VatCount leans it back to the Board3
## camera's pitch, so it faces the eye squarely and does not swim on a pinch); build(scale_k) sizes it, set_seat_colour(col)
## colours the frame (neon = seat) and the digits, set_text(t) the count. Today: a dark panel, a seat-colour neon frame and
## Rajdhani digits drawn by the game (never the structure's Face_num_*); the new frame art replaces _quad() later, not the callers.
## Drawn without depth test above the units (render_priority 1..4), so neither the tower nor a line on the platform covers it.

const FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const DIGIT_EM := 0.643             # Rajdhani SemiBold digit height / em (fontTools bounds of 0-9)
const DIGIT_ADV := 0.533            # its digit advance / em
const FONT_PX := 96                 # Label3D font size (pixel_size = em / FONT_PX)
const PANEL_H := 1.5                # panel height / digit height
const FRAME := 0.12                 # m of neon frame round the panel (x scale)

var scale_k := 1.0
var digit_h := 1.0                  # m, set by build()
var size := Vector2.ZERO            # the panel's size in m (frame excluded)
var frame: MeshInstance3D
var panel: MeshInstance3D
var label: Label3D


func build(digit_height_m: float, digits := 3) -> void:
	## digit_height_m = the digits' height in m (VatCount.digit_height_m(): base x the OPTIONS count size).
	digit_h = digit_height_m
	var em := digit_h / DIGIT_EM
	size = Vector2(em * DIGIT_ADV * digits + digit_h * 0.5, digit_h * PANEL_H)
	for c in get_children():
		c.free()
	frame = _quad(size + Vector2.ONE * FRAME * 2.0 * digit_h, Color.WHITE, 1)
	add_child(frame)
	panel = _quad(size, Color(0.03, 0.04, 0.06, 0.92), 2)
	add_child(panel)
	label = Label3D.new()
	label.font = FONT
	label.font_size = FONT_PX
	label.pixel_size = em / FONT_PX
	label.outline_size = int(FONT_PX * 0.16)
	label.outline_modulate = Color(0.01, 0.01, 0.03, 1.0)
	label.no_depth_test = true
	label.fixed_size = false
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.render_priority = 4
	label.outline_render_priority = 3
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector3(0.0, 0.0, 0.02)
	add_child(label)


func set_seat_colour(col: Color) -> void:
	(frame.material_override as StandardMaterial3D).albedo_color = col
	label.modulate = col.lerp(Color.WHITE, 0.35)


func set_text(t: String) -> void:
	label.text = t


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
