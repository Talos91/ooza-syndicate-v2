class_name HudLiquid
extends Control
## Alpha 24 Neon Noir (art director revisions 4-6, Daniele 2026-11-03): a glass vessel that fills with lit ooze - the skill
## column's hex vessels (charge / cooldown = the liquid level; full = ready) and the SEND share vats (each holds its share:
## 100 / 75 / 50 / 25 %, the picked one lit). The control's rect is the vessel's BODY; the director's glow band spills round it.
## The level eases to its target (a cast drains it fast), sloshes when it jumps, and breathes brighter when full and ready.
## Drawn as one quad with shaders/hud_liquid.gdshader (layers: <part> fill, <part>_liquid, <part>_shine, <part>_surface, rim).

const SHADER := preload("res://shaders/hud_liquid.gdshader")
const EASE := 5.0                              # per second, the level's approach to its target
const DRAIN := 2.6                             # per second: a cast empties the vessel this fast
const SLOSH_S := 1.1                           # seconds a jump keeps sloshing

var part := "skill_vessel"                     # "skill_vessel" | "send_button"
var fill_part := ""                            # the glass under the liquid (a state of `part`)
var rim_tex: Texture2D
var target := 1.0
var shown := 1.0
var ready_glow := false                        # ready (a full vessel) / the picked SEND vat: the ooze breathes brighter
var _slosh := 0.0
var _t := 0.0
var _mat: ShaderMaterial


func setup(kind: String, liquid: Color, seed := 0.0) -> void:
	part = kind
	fill_part = kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	var p := HudNoir.part_data(kind)
	var size_px: Array = p.get("size", [1, 1])
	var body: Array = p.get("body", [0, 0, 1, 1])
	_mat.set_shader_parameter("body", Vector4(float(body[0]) / size_px[0], float(body[1]) / size_px[1],
			float(body[2]) / size_px[0], float(body[3]) / size_px[1]))
	var s := HudNoir.part_data(kind + "_surface")
	var ss: Array = s.get("size", [1, 1])
	var sb: Array = s.get("body", [0, 0, 1, 1])
	_mat.set_shader_parameter("strip", Vector4(float(sb[0]) / ss[0], float(sb[1]) / ss[1], float(sb[2]) / ss[0], float(sb[3]) / ss[1]))
	_mat.set_shader_parameter("strip_h", float(sb[3]) / size_px[1])
	_mat.set_shader_parameter("liquid_tex", HudNoir.texture(str(HudNoir.part_data(kind + "_liquid").get("file", ""))))
	_mat.set_shader_parameter("shine_tex", HudNoir.texture(str(p.get("shine", ""))))
	_mat.set_shader_parameter("surface_tex", HudNoir.texture(str(s.get("file", ""))))
	_mat.set_shader_parameter("liquid_col", liquid)
	_mat.set_shader_parameter("seed", seed)
	set_rim(str(p.get("rim", "")), HudNoir.accent)
	_push()


func set_rim(path: String, col: Color) -> void:
	## The vessel's rim layer (a state's white rim) and its tint.
	var t := HudNoir.texture(path)
	if t != rim_tex:
		rim_tex = t
		_mat.set_shader_parameter("rim_tex", t)
	_mat.set_shader_parameter("rim_col", col)


func set_rim_lit(path: String, col: Color) -> void:
	## GMN-1 skill window: the burning ring (the armed rim) revealed from the bottom up to the level, over the dim rim; "" = off.
	var t := HudNoir.texture(path)
	_mat.set_shader_parameter("rim_lit_tex", t)
	_mat.set_shader_parameter("rim_lit_col", col if t != null else Color(0, 0, 0, 0))


func set_liquid(col: Color, alpha := 1.0) -> void:
	_mat.set_shader_parameter("liquid_col", col)
	_mat.set_shader_parameter("liquid_a", alpha)


func set_level(v: float, instant := false) -> void:
	## The level to show (0..1). A jump of more than a sliver sloshes; `instant` snaps (setup, a new skill).
	v = clampf(v, 0.0, 1.0)
	if absf(v - target) > 0.04 and not instant:
		_slosh = 1.0
	target = v
	if instant:
		shown = v
		_push()


func _process(delta: float) -> void:
	_t += delta
	var was := shown
	if target < shown - 0.25:                    # a cast: drained, not eased
		shown = maxf(target, shown - DRAIN * delta)
	else:
		shown = lerpf(shown, target, 1.0 - exp(-EASE * delta))
	if absf(shown - target) < 0.001:
		shown = target
	_slosh = maxf(0.0, _slosh - delta / SLOSH_S)
	if was != shown or _slosh > 0.0 or ready_glow:
		_push()


func _push() -> void:
	_mat.set_shader_parameter("level", shown)
	_mat.set_shader_parameter("slosh", _slosh * _slosh)
	_mat.set_shader_parameter("glow", (0.55 + 0.45 * sin(_t * 4.0)) if ready_glow and shown >= target - 0.001 else 0.0)


func _draw() -> void:
	var p := HudNoir.part_data(fill_part)
	var t := HudNoir.texture(str(p.get("file", "")))
	if t == null:
		return
	var size_px: Array = p.get("size", [1, 1])
	var body: Array = p.get("body", [0, 0, 1, 1])
	var k := Vector2(size.x / float(body[2]), size.y / float(body[3]))
	draw_texture_rect(t, Rect2(-Vector2(body[0], body[1]) * k, Vector2(size_px[0], size_px[1]) * k), false)
