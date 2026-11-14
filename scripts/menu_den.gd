class_name MenuDen
extends Node2D
## MAIN MENU BACKGROUND (round 35C2, locked by Daniele 2026-11-15; 0.24.4): the overlord on his couch, seen from behind,
## watching a TV. One painting for every setting, in two canvases (WIDE 3840 x 2160 only: cropped from the floor, its extra ceiling keeps the TV under the top bar - designer 8), cover-scaled. Its TV picture is a hole (alpha 0 where the delivery's key is #FF00FF); behind the hole
## this node draws the screen: a looped capture of a real demo match (assets/art/menu/tv_loop.webp, 24 frames in a 6 x 4
## atlas, tools/make_tv_loop.py) on a quad mapped to the TV's four corners, and a faint glare layer over the painting.
## The loop is frames, not a second live match: a second Main in the same process shares Rules / GooTone / LookTheme /
## Net (and a second world on a phone costs far more than the menu is worth). Nothing runs while HOME is not shown.
##
## Menu usage: `den.show(backdrop)` on HOME (sets the backdrop's texture, places it, starts the loop), `den.hide_den()` on
## every other page; `den.place(backdrop)` after a resize; `den.quiet_right()` = the right edge (screen px) of the painting's
## quiet zone, where the menu column must stay.

const CANVAS := {
	"wide": {"bg": "res://assets/art/menu/menu_bg_wide.webp", "glass": "res://assets/art/menu/tv_glass_wide.png",
			"size": Vector2(3840, 2160), "quiet": 1153.0,
			"tv": [Vector2(2335, 398), Vector2(3620, 293), Vector2(3619, 1070), Vector2(2335, 1037)]},
}
const LOOP_PATH := "res://assets/art/menu/tv_loop.webp"
const LOOP_FRAMES := 24
const LOOP_COLS := 6
const LOOP_FRAME := Vector2(480, 270)
const LOOP_FPS := 8.0

var enabled_loop := true                  # false = one still frame (the Web fallback; Menu sets it from PerfProfile / the --menu-still arg)
var _canvas := "wide"
var _bg: Dictionary = {}
var _tv := Polygon2D.new()
var _glass := TextureRect.new()
var _loop: Texture2D
var _frame := 0
var _t := 0.0
var _backdrop: TextureRect                # the menu's backdrop (it draws the painting, hole and all)
var _ax := 0.3                            # horizontal crop anchor when the screen is narrower than the canvas: keep the quiet zone


func _init() -> void:
	name = "MenuDen"
	enabled_loop = not ("--menu-still" in OS.get_cmdline_user_args())   # (measuring: the still frame instead of the loop)
	_tv.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tv.antialiased = false
	add_child(_tv)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glass.stretch_mode = TextureRect.STRETCH_SCALE
	_glass.visible = false
	_tv.visible = false
	set_process(false)


func _pick() -> String:
	var vp := get_viewport().get_visible_rect().size
	return "wide"                          # always the WIDE canvas, cropped from the floor (ay 0): its extra ceiling keeps the TV under the top bar


func show_den(backdrop: TextureRect) -> void:
	_backdrop = backdrop
	_canvas = _pick()
	_bg = CANVAS[_canvas]
	backdrop.texture = load(_bg["bg"])
	backdrop.modulate = Color.WHITE
	if _loop == null:
		_loop = load(LOOP_PATH)
	if _glass.get_parent() == null:
		_backdrop.add_child(_glass)          # on top of the painting, inside the backdrop's own box
	_glass.texture = load(_bg["glass"])
	visible = true
	_tv.visible = true
	_glass.visible = true
	_apply_frame()
	set_process(enabled_loop)
	place(backdrop)


func hide_den() -> void:
	visible = false
	_tv.visible = false
	_glass.visible = false
	set_process(false)


func place(backdrop: TextureRect) -> void:
	## Called after the menu has placed the backdrop (position + size on screen): maps the TV quad onto it.
	if not visible or _bg.is_empty():
		return
	var k: Vector2 = backdrop.size / (_bg["size"] as Vector2)
	var pts := PackedVector2Array()
	for c in _bg["tv"]:
		pts.append(backdrop.position + (c as Vector2) * k)
	_tv.polygon = pts
	_glass.position = Vector2.ZERO
	_glass.size = backdrop.size
	_apply_frame()


func backdrop_anchor_x() -> float:
	return _ax


func quiet_right() -> float:
	## Screen x of the quiet zone's right edge (the painting's left ~30 %), from the backdrop's current placement.
	if _bg.is_empty() or _backdrop == null:
		return 0.0
	return _backdrop.position.x + float(_bg["quiet"]) * _backdrop.size.x / (_bg["size"] as Vector2).x


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	var step := 1.0 / LOOP_FPS
	if _t >= step:
		_t = fmod(_t, step)
		_frame = (_frame + 1) % LOOP_FRAMES
		_apply_frame()


func _apply_frame() -> void:
	if _loop == null:
		return
	var f := _frame if enabled_loop else 9      # the still: a frame with both armies out
	var o := Vector2(f % LOOP_COLS, f / LOOP_COLS) * LOOP_FRAME
	var in_px := 0.5                              # inset: no bleed from the neighbouring frame
	var a := o + Vector2(in_px, in_px)
	var b := o + LOOP_FRAME - Vector2(in_px, in_px)
	_tv.texture = _loop
	_tv.uv = PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])
