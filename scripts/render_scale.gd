class_name RenderScale
extends Node
## perf-ios (2026-11-01): the linear-filtered scaled 3D path. Daniele's girlfriend's new iPhone (dpr 2) got very hot over
## six online matches: the game held its 45 fps cap, it simply rendered the 3D at 2x resolution every frame. The Alpha 21
## decision stands (perf_profile.gd): GL Compatibility upscales its own scaled 3D buffer without filtering, so at 0.75 the
## edges turned into hard pixel steps ("like minecraft") and every profile rendered at 1.0 "until a linear-filtered path
## exists (a SubViewport shown through a linear TextureRect)". This is that path.
##
## PerfProfile._apply_3d calls attach(main, scale) once the match is built. The match's Camera3D moves into a SubViewport
## of `scale` x the window's pixels; the SubViewport shares the root's World3D (every platform, light and effect stays a
## child of main - nothing else moves) and its texture is drawn over the whole screen by a TextureRect with LINEAR
## filtering on a CanvasLayer under everything (-100), so the upscale is a smooth bilinear blend, not pixel steps. The
## HUD and every menu stay on the root at native resolution.
## - Coordinates: the SubViewport's size_2d_override is the root's visible rect, so Camera3D.unproject_position /
##   project_ray_* (picking, the HUD's badges, callouts, the coach's gestures, the phone-fit probe) keep answering in the
##   same screen points as before; the root's input events need no mapping.
## - The sky: the Environment draws the canvas layers at or under background_canvas_max_layer as its background, so the
##   backdrop layer (Scenery.make_backdrop, -50) moves into the SubViewport with the camera (a smooth image, fine at scale).
## - Screenshots (root get_texture) still see the whole frame: a SubViewport draws before its parent.
## - The root's own 3D pass is off while the path is up (disable_3d) and back on when the match scene goes (_exit_tree:
##   the root outlives a reload_current_scene).
## - iOS (Scenery.ios_safe): the SubViewport renders the 3D straight into its own texture - no scaling mode, no MSAA, no
##   glow - the same single-buffer path WebKit accepts on the root; only the texture is smaller.
## Nothing here changes a number: the scale comes from PerfProfile (PHONE: 1.5 3D pixels per CSS point, so 0.75 on a dpr-2
## phone, 1.0 on a dpr-1 desktop; --scale3d=0.75 forces one for a test run).

const LAYER := -100                     # the 3D texture's canvas layer: under the HUD (1), the ultimate tint (0), everything

static var current: RenderScale = null  # the live path (null: the root renders the 3D itself)

var main: Node3D
var scale := 1.0
var sub: SubViewport
var rect: TextureRect
var _root: Viewport
var _layer: CanvasLayer
var _moved: Array = []                  # [node, former parent]: the camera and the sky layers, back on detach


static func attach(m: Node3D, s: float) -> RenderScale:
	## Puts the match's 3D on the scaled path (no-op at scale >= 1 or while one is up). Returns the node, or null.
	if s >= 0.999 or current != null or m == null or not (m.get("cam") is Camera3D):
		return null
	var r := RenderScale.new()
	r.name = "RenderScale"
	r.main = m
	r.scale = clampf(s, 0.25, 1.0)
	r.process_mode = Node.PROCESS_MODE_ALWAYS
	m.add_child(r)
	r._setup()                                           # (not in _ready: main is still busy adding r there, no reparenting then)
	return r


static func scale_now() -> float:
	## The scale the 3D renders at right now (1.0: the root's own pass).
	return current.scale if current != null and is_instance_valid(current) else 1.0


static func viewport_3d(m: Node) -> Viewport:
	## The viewport the match's 3D renders in: the SubViewport while the path is up, else m's own.
	if current != null and is_instance_valid(current) and current.sub != null:
		return current.sub
	return m.get_viewport()


func _setup() -> void:
	_root = main.get_viewport()
	sub = SubViewport.new()
	sub.name = "Scaled3D"
	sub.own_world_3d = false                             # the root's World3D: the whole match stays where it is
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.handle_input_locally = false
	sub.gui_disable_input = true                         # input stays on the root (main._unhandled_input, the HUD)
	sub.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	sub.scaling_3d_scale = 1.0                           # never the unfiltered in-viewport scaling (the "minecraft" steps)
	sub.msaa_3d = Viewport.MSAA_DISABLED if Scenery.ios_safe() else _root.msaa_3d
	sub.screen_space_aa = _root.screen_space_aa
	sub.positional_shadow_atlas_size = _root.positional_shadow_atlas_size
	sub.size_2d_override_stretch = true                  # the sky's full-rect layout follows the override, drawn to the texture
	add_child(sub)
	var cam := main.get("cam") as Camera3D
	_move(cam)
	cam.current = true
	var env := _environment()
	var max_layer := env.background_canvas_max_layer if env != null else -10
	for c in main.get_children():                        # the sky (and any other background layer the Environment draws)
		if c is CanvasLayer and (c as CanvasLayer).layer <= max_layer:
			_move(c)
	_layer = CanvasLayer.new()
	_layer.name = "Scaled3DLayer"
	_layer.layer = LAYER
	rect = TextureRect.new()
	rect.name = "Scaled3DView"
	rect.texture = sub.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # the point of the path: a smooth upscale
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(rect)
	add_child(_layer)
	_root.disable_3d = true                              # nothing left for the root's 3D pass to draw
	_resize()
	_root.size_changed.connect(_resize)
	current = self


func _exit_tree() -> void:
	## The match scene goes (a reload, a quit): the root draws its own 3D again. (The camera and the sky leave with main.)
	if current == self:
		current = null
	if _root != null and is_instance_valid(_root):
		if _root.size_changed.is_connected(_resize):
			_root.size_changed.disconnect(_resize)
		_root.disable_3d = false


func detach() -> void:
	## Back to the root's own 3D pass while the match lives on (nothing calls it in play; a test's A/B).
	for m in _moved:
		var n: Node = m[0]
		var p: Node = m[1]
		if is_instance_valid(n) and is_instance_valid(p) and n.get_parent() == sub:
			var gt: Transform3D = (n as Node3D).global_transform if n is Node3D else Transform3D.IDENTITY
			sub.remove_child(n)
			p.add_child(n)
			if n is Node3D:
				(n as Node3D).global_transform = gt
			if n is Camera3D:
				(n as Camera3D).current = true
	_moved.clear()
	main.remove_child(self)
	queue_free()


func _move(n: Node) -> void:
	var p := n.get_parent()
	var gt: Transform3D = (n as Node3D).global_transform if n is Node3D else Transform3D.IDENTITY
	p.remove_child(n)
	sub.add_child(n)
	if n is Node3D:
		(n as Node3D).global_transform = gt
	_moved.append([n, p])


func _resize() -> void:
	var px := Vector2(_root.get_window().size)           # the window's pixels (on the web: CSS size x devicePixelRatio)
	if px.x <= 0.0 or px.y <= 0.0:
		return
	sub.size = Vector2i(maxi(1, roundi(px.x * scale)), maxi(1, roundi(px.y * scale)))
	sub.size_2d_override = Vector2i(_root.get_visible_rect().size)   # screen points: unproject / project_ray stay in them


func pixels() -> Vector2i:
	## The 3D texture's size in pixels (the PERF print, tests).
	return sub.size if sub != null else Vector2i.ZERO


func _environment() -> Environment:
	for c in main.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			return (c as WorldEnvironment).environment
	return null
