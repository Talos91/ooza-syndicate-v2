class_name PitBackdrop
extends RefCounted
## ROUND 44 B4 MATCH BACKGROUND (Daniele 2026-11-18: "the first final background for the new game mode (the one with rocket
## nodes)"; screen layout: background = pit + near layer behind the HUD + crust, NO sky; the HUD sits on the mounts).
## Source: References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/44-background-B4 (approved,
## untouched); game derivatives at 2x in assets/art/bg44b4 (tools/bg44b4_derive.py, layout.json there).
##  - BACK (the Environment's background canvas, under the 3D map): goo floor (the tile repeated, pit_goo.gdshader), CRUST
##    (full viewport, its lake opening shows the goo), PIT-RIM (wet bank) - one 812 x 375 pt frame scaled to COVER the
##    viewport, centred; the 3D map is fitted into the lake opening (pit_rect, main._fit_nodes).
##  - MOUNTS (the HUD's first children, under every HUD control): NEAR-L behind the send tube, NEAR-R behind the skill
##    column, the score ledge behind the timer tube, the utility keys behind SOUND / PAUSE (/ CHAT when it shows), each
##    fitted round its control's rect every frame (sync), so they follow the HUD at every size.
##  - The river world's sky band, canyon, goo plane, cracks and mist are off (the painted pit replaces them).
## On: the QUOTA demo (Rules.quota) with the river world; off with --no-pit-bg.
## VIEW ONLY: nothing in the Sim or the protocol.

const DIR := "res://assets/art/bg44b4/"
const GOO_SHADER := preload("res://shaders/pit_goo.gdshader")
const REF := Vector2(812.0, 375.0)
const PAD := 1.06                    # a mount covers its control's rect plus 3 % round it
static var on := false

var main: Node
var hud: Node
var layout: Dictionary = {}
var back: CanvasLayer
var _frame: Control                  # the 812 x 375 pt frame, scaled to cover
var _goo: ColorRect
var _mounts: Dictionary = {}         # id -> TextureRect
var _mount_root: Control
var _vp := Vector2.ZERO


static func wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	return Rules.quota and Rules.world_layer and not "--no-river" in args and not "--no-pit-bg" in args \
			and ResourceLoader.exists(DIR + "crust.png")


func _tex(f: String) -> Texture2D:
	return load(DIR + f) as Texture2D


func _el(id: String) -> Dictionary:
	return (layout.get("elements", {}) as Dictionary).get(id, {})


func build_back(m: Node) -> CanvasLayer:
	## The background canvas layer (replaces Scenery's sky layer: same layer, drawn by the Environment as the background).
	main = m
	var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
	if f:
		layout = JSON.parse_string(f.get_as_text())
	back = CanvasLayer.new()
	back.layer = -50
	_goo = ColorRect.new()
	_goo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GOO_SHADER
	mat.set_shader_parameter("tile", _tex(str(_el("goo_tile").get("file", "goo_tile.png"))))
	_goo.material = mat
	back.add_child(_goo)                              # full viewport (the crust covers all but the lake)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = REF
	back.add_child(_frame)
	for id in ["crust", "rim"]:
		var e := _el(id)
		var t := TextureRect.new()
		t.texture = _tex(str(e.get("file", id + ".png")))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r: Array = e.get("pt", [0, 0, REF.x, REF.y])
		t.position = Vector2(r[0], r[1])
		t.size = Vector2(r[2], r[3])
		_frame.add_child(t)
	m.add_child(back)
	_relayout(m.get_viewport().get_visible_rect().size)
	return back


func frame_scale(vp: Vector2) -> float:
	return maxf(vp.x / REF.x, vp.y / REF.y)


func frame_origin(vp: Vector2) -> Vector2:
	return (vp - REF * frame_scale(vp)) / 2.0


func pit_rect(vp: Vector2) -> Rect2:
	## The lake opening on screen (the stadium box of layout.json pit_stadium_pt), for the camera fit.
	var ps: Dictionary = layout.get("pit_stadium_pt", {})
	var c: Array = ps.get("center_pt", [406.0, 213.5])
	var hw := float(ps.get("half_width_pt", 298.0))
	var hh := float(ps.get("end_radius_pt", 144.8))
	var s := frame_scale(vp)
	var o := frame_origin(vp)
	return Rect2(o + (Vector2(c[0], c[1]) - Vector2(hw, hh)) * s, Vector2(hw, hh) * 2.0 * s)


func _relayout(vp: Vector2) -> void:
	_vp = vp
	var s := frame_scale(vp)
	_frame.scale = Vector2(s, s)
	_frame.position = frame_origin(vp)
	_goo.position = Vector2.ZERO
	_goo.size = vp
	var g := _el("goo_tile")
	var per: Array = g.get("period_pt", [395, 258])
	var an: Array = g.get("anchor_pt", [422.24, 213.54])
	var mat := _goo.material as ShaderMaterial
	mat.set_shader_parameter("rect_px", vp)
	mat.set_shader_parameter("anchor_px", frame_origin(vp) + Vector2(an[0], an[1]) * s)
	mat.set_shader_parameter("period_px", Vector2(per[0], per[1]) * s)


# ------------------------------------------------------------------ the mounts under the HUD
func build_mounts(h: Node) -> void:
	hud = h
	var root: Control = h.get("root")
	if root == null:
		return
	_mount_root = Control.new()
	_mount_root.name = "PitMounts"
	_mount_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_mount_root)
	root.move_child(_mount_root, 0)                   # under every HUD control
	for id in ["NEAR-L", "NEAR-R", "MOUNT-SCORE-LEDGE", "MOUNT-UTILITY-SOUND", "MOUNT-UTILITY-PAUSE", "MOUNT-UTILITY-CHAT"]:
		var e := _el(id)
		if e.is_empty():
			continue
		var t := TextureRect.new()
		t.texture = _tex(str(e["file"]))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.visible = false
		_mount_root.add_child(t)
		_mounts[id] = t
	sync()


func _target(id: String) -> Rect2:
	## The HUD control a mount carries, as a global rect (empty: hide the mount).
	var c: Control = null
	match id:
		"NEAR-L":
			c = hud.get("side_panel")
		"NEAR-R":
			var d: Control = hud.get("dock")
			if d and d.is_visible_in_tree():
				var r := d.get_global_rect()
				if d.has_method("housing_margin"):
					var hm: Vector4 = d.housing_margin()
					r = Rect2(r.position - Vector2(hm.x, hm.y), r.size + Vector2(hm.x + hm.z, hm.y + hm.w))
				return r
			return Rect2()
		"MOUNT-SCORE-LEDGE":
			c = hud.get("lab_tube")
			if c == null or not c.is_visible_in_tree():
				c = hud.get("top_panel")
		"MOUNT-UTILITY-SOUND":
			c = hud.get("music_button")
		"MOUNT-UTILITY-PAUSE":
			c = hud.get("pause_button")
		"MOUNT-UTILITY-CHAT":
			c = hud.get("chat_button")
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


func sync() -> void:
	if back != null and main != null:
		var vp: Vector2 = main.get_viewport().get_visible_rect().size
		if vp != _vp:
			_relayout(vp)
	if _mount_root == null:
		return
	var o := _mount_root.get_global_rect().position
	for id in _mounts:
		var t: TextureRect = _mounts[id]
		var r := _target(id)
		if r.size.x < 2.0 or r.size.y < 2.0:
			t.visible = false
			continue
		var ts := t.texture.get_size()
		var k := maxf(r.size.x / ts.x, r.size.y / ts.y) * PAD   # cover the control, aspect kept
		t.size = ts * k
		t.position = r.get_center() - t.size / 2.0 - o
		t.visible = true
