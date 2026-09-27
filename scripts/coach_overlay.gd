class_name CoachOverlay
extends CanvasLayer
## Tutorial teaching UI (TUTORIAL-DESIGN.md §6): the coach card, the pointing hand, the spotlight, the
## card's controls and the lesson / training completion screens, drawn in the HUD's own skin (NeonPanel,
## Hud.panel_style, Rajdhani / Russo One). UI only - it knows nothing about the Sim or the lesson table;
## main.gd's tutorial block feeds it from TutorialDirector (tutorial.gd) frame by frame. A CanvasLayer
## sitting above Hud (layer 50; Hud itself has no explicit layer).
##
## Public API
##   show_step(header, text, dots, dot_index, button_text := "")
##       The coach card. `header` e.g. "DR. VESK · LESSON 3 / 8 · THE RIVAL"; `dots`/`dot_index` are the
##       step markers; `button_text` == "" for a doing-step (no GOT IT, just SKIP/RESTART/EXIT), any
##       other string shows it as the one allowed button (read-only steps: "GOT IT").
##   point_nodes(screen_points: Array[Vector2], radius: float)
##       Spotlight: one soft circle per screen point (already projected, e.g. cam.unproject_position()),
##       `radius` in pixels. Repositions the card to the free corner farthest from the target.
##   point_rect(rect: Rect2)
##       Spotlight: one soft rounded rect around a HUD control (already in screen / global space).
##   spotlight(screen_points: Array, radius: float, rects: Array)
##       Both at once (circles round nodes and lines, rounded rects round HUD controls). Safe every frame
##       (the camera moves in the Last Stand): the card only eases to a corner when its best corner changes.
##   clear_spotlight()
##       No dim, no target (a plain read-only line with nothing to point at).
##   gesture(kind: String, from: Vector2, to := Vector2.ZERO, path := PackedVector2Array())
##       The pointing hand (assets/ui/tutorial/hand.svg, tinted in the player colour, a soft glow, ~50 pt
##       on phones, the fingertip on the point). kind: "tap" | "double_tap" | "drag" | "press".
##       `from`/`to`/`path` are screen points; "drag" follows `path` if given (>= 2 points), else the
##       straight `from` -> `to` line, trailing arrow included; the animation loops every GESTURE_LOOP
##       (1.6 s). Calling it again with the same kind keeps the loop running (safe every frame).
##   set_finger_down(down: bool)   the hand hides while a finger is on the screen (§6).
##   clear_gesture()
##   show_complete(title, lines: Array, primary_text, secondary: Array)
##       The per-lesson LESSON COMPLETE screen. `secondary` is an Array of button strings (REPLAY,
##       LESSONS, ...); hides the card, spotlight and hand.
##   show_training_complete(title, lines: Array, primary_text, secondary: Array, reward := {})
##       The final TRAINING COMPLETE variant: the same, plus the Graduate vat's reveal - the skin model on
##       a turntable in an ivory / brass frame (reward {"unlocked": bool, "title", "faction"}).
##   hide_complete()
##   set_dodge_rects(top_bar: Rect2, send_panel: Rect2, dock: Rect2, pause_button: Rect2)
##       Optional: the HUD's real control rects (global / screen space), so the card's corner search
##       dodges them exactly. Without this it falls back to viewport-edge guesses.
##   set_accent(color: Color)   the player's seat colour - the hand, spotlight ring and card accent.
##   set_mobile(is_mobile: bool)   phone tap (>= 44 pt) / text (>= 14 pt) minimums, same numbers as menu.gd.
##   set_first_launch(on: bool)   the forced first run: EXIT becomes SKIP TUTORIAL (signal skip_tutorial).
##   set_labels(dict)              the card's button words (keys skip_step / restart / exit / skip_tutorial).
##   ui_rects() -> Array           what the card and a completion screen cover (Hud counts them as UI).
##   set_obstacles(points: Array)  screen points the card should rather not cover (every node): among the
##                                 corners clear of the target, the one covering the fewest wins.
##   handler_mood(mood: String)    the handler creature: "happy" (a hop) / "droop" (a fail); it "talks" by itself
##                                 while a line types in (~35 characters/s, a tap on the card shows it all).
##   handler_rect() -> Rect2       where the creature is on screen.
##   spotlit(p: Vector2) -> bool   is `p` inside the current spotlight (the tour takes a tap there as NEXT).
##
## Signals
##   button_pressed(id: String)   "got_it" from the card's one button; "primary" / "secondary:<i>" from
##                                a completion screen (i = index into that call's `secondary` array).
##   skip_step, restart, exit     the card's three always-on controls.
##   skip_tutorial                the first-launch card's SKIP TUTORIAL (in EXIT's place).
##
## Mouse input passes through everywhere except the card's and the completion screen's own buttons
## (every other child has MOUSE_FILTER_IGNORE).
##
## Coordinate spaces (confirmed empirically, not assumed - see world_to_overlay()): the project's
## canvas_items/expand stretch (base 1280x720) means `Camera3D.unproject_position()` and
## `Control.get_global_rect()` both land in the viewport's LOGICAL (visible_rect) space, which differs
## from the final, already-stretched DEVICE-PIXEL space whenever a window's aspect ratio isn't 1280:720
## (e.g. a landscape phone). Regular _draw() calls and Control positions are auto-transformed by the
## engine at raster time, so callers pass plain viewport/global points into show_step() / point_nodes()
## / point_rect() / gesture() with NO conversion needed. The ONE place this bites is the spotlight
## shader: a canvas_item shader's FRAGCOORD is already in device-pixel space, so anything compared
## against it must go through world_to_overlay() first - _apply_spotlight() is the only caller.

signal button_pressed(id: String)
signal skip_step
signal restart
signal exit
signal skip_tutorial

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const HAND_TEX := preload("res://assets/ui/tutorial/hand.svg")
const HAND_TIP := Vector2(40.5 / 100.0, 4.0 / 128.0)   # the fingertip in hand.svg (fraction of its 100 x 128 box)
const HANDLER_EMBLEM := "res://assets/ui/Ooze-Syndicate-Logo.svg"
const HANDLER_MODEL := "res://assets/units/vex.glb"      # the game's own VEX creature (UnitView, vat residents)
const TYPE_RATE := 35.0                                  # characters per second of the typewriter

const MARGIN := 18.0
const EASE_TIME := 0.2
const GESTURE_LOOP := 1.6
const DRAG_TRAVEL_T := 1.0
const DRAG_HOLD_T := 0.25

const SPOTLIGHT_SHADER := "
shader_type canvas_item;
uniform vec4 dim_color : source_color = vec4(0.008, 0.016, 0.024, 0.55);
uniform vec4 ring_color : source_color = vec4(0.094, 0.855, 0.910, 1.0);
uniform int num_c;
uniform vec3 circles[8];
uniform int num_r;
uniform vec4 rects[8];
uniform float feather = 16.0;
uniform float ring_w = 2.5;

float circle_d(vec2 p, vec3 c) { return length(p - c.xy) - c.z; }
float rrect_d(vec2 p, vec4 r) {
	vec2 c = r.xy + r.zw * 0.5;
	vec2 h = r.zw * 0.5;
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
void fragment() {
	vec2 p = FRAGCOORD.xy;
	float inside = 0.0;
	float ring = 0.0;
	float pulse = 0.55 + 0.45 * sin(TIME * 3.0);
	for (int i = 0; i < 8; i++) {
		if (i >= num_c) break;
		float d = circle_d(p, circles[i]);
		inside = max(inside, 1.0 - smoothstep(-feather, feather, d));
		float rd = abs(d - (6.0 * pulse));
		ring = max(ring, 1.0 - smoothstep(0.0, ring_w * 2.5, rd));
	}
	for (int i = 0; i < 8; i++) {
		if (i >= num_r) break;
		float d = rrect_d(p, rects[i]);
		inside = max(inside, 1.0 - smoothstep(-feather, feather, d));
		float rd = abs(d - (5.0 * pulse));
		ring = max(ring, 1.0 - smoothstep(0.0, ring_w * 2.2, rd));
	}
	vec4 col = mix(dim_color, vec4(0.0), inside);
	col = mix(col, vec4(ring_color.rgb, ring_color.a), ring * (1.0 - inside * 0.4));
	COLOR = col;
}
"


# ------------------------------------------------------------------ inner helpers (no extra files)
class DotsRow extends Control:
	var count := 1
	var index := 0
	var accent := Color("18dae8")
	var dot_r := 5.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if count <= 0:
			return
		var gap := dot_r * 3.2
		var w := (count - 1) * gap
		var start := Vector2((size.x - w) / 2.0, size.y / 2.0)
		for i in range(count):
			var c := start + Vector2(i * gap, 0.0)
			var col := accent if i <= index else Color(accent, 0.28)
			draw_circle(c, dot_r if i == index else dot_r * 0.72, col)


class HandLayer extends Control:
	const GESTURE_LOOP := 1.6            # kept in step with the outer class's own GESTURE_LOOP
	const DRAG_TRAVEL_T := 1.0
	const DRAG_HOLD_T := 0.25
	var kind := ""                       # "" | "tap" | "double_tap" | "drag" | "press"
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var path := PackedVector2Array()
	var t := 0.0
	var accent := Color("18dae8")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hand_px := 58.0                 # the hand's height on screen (CoachOverlay._hand_target_px)
	var finger_down := false

	func _draw_hand_at(pos: Vector2, alpha: float, press_t: float) -> void:
		## hand.svg, tinted in the player colour (white -> the colour, its outline -> the colour's dark
		## shade) with a soft glow behind it; `pos` is the exact fingertip.
		if alpha <= 0.01 or finger_down:
			return
		var tex_size: Vector2 = HAND_TEX.get_size()
		var h := hand_px * (0.92 + 0.08 * press_t)
		var sz := tex_size * (h / tex_size.y)
		var origin := pos - HAND_TIP * sz
		var core := origin + sz * Vector2(0.55, 0.62)
		for k in range(3):                                          # soft glow
			draw_circle(core, sz.y * (0.30 + 0.12 * k), Color(accent, 0.07 * alpha))
		draw_texture_rect(HAND_TEX, Rect2(origin - sz * 0.05, sz * 1.10), false, Color(accent, 0.28 * alpha))
		draw_texture_rect(HAND_TEX, Rect2(origin, sz), false, Color(accent.lightened(0.12), alpha))

	func _draw_ripple(center: Vector2, phase: float, alpha: float) -> void:
		var r := lerpf(4.0, 30.0, phase)
		var a := (1.0 - phase) * alpha
		if a > 0.01:
			draw_arc(center, r, 0.0, TAU, 24, Color(accent, 0.85 * a), 3.0, true)

	func _path_along(pts: PackedVector2Array, frac: float) -> Vector2:
		var total := 0.0
		for i in range(pts.size() - 1):
			total += pts[i].distance_to(pts[i + 1])
		if total <= 0.0:
			return pts[0]
		var target := total * clampf(frac, 0.0, 1.0)
		var acc := 0.0
		for i in range(pts.size() - 1):
			var seg := pts[i].distance_to(pts[i + 1])
			if acc + seg >= target or i == pts.size() - 2:
				var local := (target - acc) / seg if seg > 0.0 else 0.0
				return pts[i].lerp(pts[i + 1], clampf(local, 0.0, 1.0))
			acc += seg
		return pts[pts.size() - 1]

	func _draw_trail(pts: PackedVector2Array, extent: float, alpha: float) -> void:
		const STEPS := 18
		var prev := _path_along(pts, 0.0)
		for i in range(1, STEPS + 1):
			var f := extent * float(i) / float(STEPS)
			var p := _path_along(pts, f)
			var a := alpha * (float(i) / float(STEPS)) * 0.7
			draw_line(prev, p, Color(accent, a), 3.0, true)
			prev = p
		# arrowhead at the tip, pointing along the last small step of travel
		var tip := _path_along(pts, extent)
		var back := _path_along(pts, maxf(extent - 0.03, 0.0))
		var dir := (tip - back)
		if dir.length() > 0.001:
			dir = dir.normalized()
			var side := dir.orthogonal()
			var head := PackedVector2Array([tip + dir * 10.0, tip - dir * 6.0 + side * 6.0, tip - dir * 6.0 - side * 6.0])
			draw_colored_polygon(head, Color(accent, 0.85 * alpha))

	func _draw() -> void:
		if kind == "":
			return
		match kind:
			"tap", "press":
				var phase := fmod(t, 1.0)
				_draw_ripple(from, phase, 1.0)
				var press_t := 0.5 + 0.5 * sin(phase * TAU * 2.0)
				_draw_hand_at(from, 1.0, press_t)
			"double_tap":
				var phase2 := fmod(t, 1.0)
				_draw_ripple(from, phase2, 1.0)
				_draw_ripple(from, fmod(phase2 + 0.5, 1.0), 1.0)
				_draw_hand_at(from, 1.0, 0.5 + 0.5 * sin(phase2 * TAU * 2.0))
			"drag":
				var pts := path if path.size() >= 2 else PackedVector2Array([from, to])
				var travel := clampf(t / DRAG_TRAVEL_T, 0.0, 1.0)
				var eased := smoothstep(0.0, 1.0, travel)
				var alpha := 1.0
				var fade_from := DRAG_TRAVEL_T + DRAG_HOLD_T
				if t > fade_from:
					alpha = 1.0 - (t - fade_from) / maxf(GESTURE_LOOP - fade_from, 0.05)
				_draw_trail(pts, eased, alpha)
				_draw_hand_at(_path_along(pts, eased), alpha, 0.0)


class HandlerView extends SubViewportContainer:
	## The handler on screen (TUTORIAL-SCRIPT draft 2, Daniele: "no trace of the handler just flat text"): the game's
	## own VEX creature in one small SubViewport of its own - its own light, a transparent background, rendered only
	## while the card is on screen (UPDATE_WHEN_VISIBLE). Idle: a gentle bob and turn; talking (while the line types
	## in): squash and stretch; a passed step: a happy hop; a fail: a droop.
	var talking := false
	var _vp: SubViewport
	var _pivot: Node3D
	var _t := 0.0
	var _mood := ""
	var _mood_t := 0.0

	func _init() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.msaa_3d = Viewport.MSAA_DISABLED
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(_vp)
		var cam := Camera3D.new()
		cam.fov = 28.0
		_vp.add_child(cam)
		cam.look_at_from_position(Vector3(0, 0.75, 3.4), Vector3(0, 0.5, 0), Vector3.UP)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-35, 30, 0)
		key.light_energy = 1.4
		_vp.add_child(key)
		var rim := OmniLight3D.new()
		rim.position = Vector3(-1.2, 1.6, -1.0)
		rim.light_color = Color("7fe9f5")
		rim.light_energy = 2.0
		rim.omni_range = 5.0
		_vp.add_child(rim)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("b8c8e0")
		env.environment.ambient_light_energy = 0.7
		_vp.add_child(env)
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		var scene := load(HANDLER_MODEL) as PackedScene
		if scene == null:
			return
		var body: Node3D = scene.instantiate()
		_pivot.add_child(body)
		var box := _bounds(body)                       # one metre tall, feet on the ground, centred
		var k := 1.0 / maxf(box.size.y, 0.01)
		body.scale = Vector3.ONE * k
		body.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k

	func _bounds(n: Node) -> AABB:
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var b: AABB = m.get_aabb()
			var xf: Transform3D = (n as Node3D).global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else m.transform
			b = xf * b
			box = b if first else box.merge(b)
			first = false
		return box

	func mood(kind: String) -> void:
		_mood = kind
		_mood_t = 0.0

	func _process(delta: float) -> void:
		if _pivot == null or not is_visible_in_tree():
			return
		_t += delta
		var y := 0.03 * sin(_t * 2.2)                       # idle: a gentle bob and turn, three-quarter to the viewer
		var yaw := 0.55 + 0.3 * sin(_t * 0.8)
		var sx := 1.0
		var sy := 1.0
		var tilt := 0.0
		if talking:                                         # talking: squash and stretch
			var q := sin(_t * 17.0)
			sy += 0.07 * q
			sx -= 0.04 * q
		if _mood != "":
			_mood_t += delta
			match _mood:
				"happy":                                    # a hop with a spin
					var k := _mood_t / 0.6
					if k >= 1.0:
						_mood = ""
					else:
						y += 0.32 * sin(PI * k)
						yaw += TAU * k
						sy *= 1.0 + 0.1 * sin(TAU * k)
				"droop":                                    # sags and bows its head, then recovers
					var d := minf(_mood_t / 0.4, 1.0) * clampf((2.4 - _mood_t) / 0.5, 0.0, 1.0)
					sy *= 1.0 - 0.18 * d
					sx *= 1.0 + 0.08 * d
					tilt = 0.4 * d
					if _mood_t > 2.4:
						_mood = ""
		_pivot.position = Vector3(0, y, 0)
		_pivot.rotation = Vector3(tilt, yaw, 0)
		_pivot.scale = Vector3(sx, sy, sx)


class GraduatePanel extends Control:
	## The Graduate vat's reveal (§6 / §7): the skin's model (Cosmetics, loaded on demand like every skin) on a
	## slow turntable in an ivory and brass frame; a drawn silhouette stands in until the model is in (the web
	## build fetches skins.pck the first time). Locked (a lesson was skipped): the frame greys, no model.
	var head_font: Font
	var ui_font: Font
	var title := "GRADUATE VAT"
	var unlocked := true
	var faction := "null"
	var _pivot: Node3D
	var _tier := 2
	var _tried := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			return
		var holder := SubViewportContainer.new()
		holder.stretch = true
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2(12, 10)
		holder.size = size - Vector2(24, 40)
		add_child(holder)
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		holder.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 32.0
		cam.position = Vector3(0, 4.0, 12.5)
		vp.add_child(cam)
		cam.look_at_from_position(cam.position, Vector3(0, 2.2, 0), Vector3.UP)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-38, 35, 0)
		sun.light_energy = 1.5
		vp.add_child(sun)
		var rim := OmniLight3D.new()
		rim.position = Vector3(-4, 5, -4)
		rim.light_color = Color("ffd98a")
		rim.light_energy = 2.5
		rim.omni_range = 16.0
		vp.add_child(rim)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("ede3cf")
		env.environment.ambient_light_energy = 0.6
		vp.add_child(env)
		_pivot = Node3D.new()
		vp.add_child(_pivot)

	func _process(delta: float) -> void:
		if _pivot == null:
			return
		_pivot.rotate_y(delta * 0.8)
		if _pivot.get_child_count() == 0:
			_tried -= delta
			if _tried <= 0.0:
				_tried = 0.25
				var scene: PackedScene = Cosmetics.scene_for("vat", "graduate", faction, _tier)
				if scene != null:
					_pivot.add_child(scene.instantiate())
					queue_redraw()

	func _draw() -> void:
		var ivory := Color("ede3cf") if unlocked else Color("8a9098")
		var brass := Color("c9a24b") if unlocked else Color("5d6670")
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.14, 0.12, 0.08, 0.9) if unlocked else Color(0.08, 0.09, 0.1, 0.9)
		bg.border_color = brass
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(10)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var fsize := 18
		var w := head_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(head_font, Vector2((size.x - w) / 2.0, size.y - 12.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, brass)
		if _pivot != null and _pivot.get_child_count() > 0:
			return
		# the stand-in until the model is in: a rounded trapezoid, a star over the door
		var cx := size.x / 2.0
		var top_y := 24.0
		var base_y := size.y - 46.0
		var pts := PackedVector2Array([
			Vector2(cx - 30, base_y), Vector2(cx - 40, top_y + 46), Vector2(cx - 26, top_y),
			Vector2(cx + 26, top_y), Vector2(cx + 40, top_y + 46), Vector2(cx + 30, base_y)])
		draw_colored_polygon(pts, Color(ivory, 0.16))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, brass, 2.0, true)
		var star := PackedVector2Array()
		for k in range(10):
			var a := -PI / 2.0 + TAU * k / 10.0
			star.append(Vector2(cx, top_y + 30) + Vector2(cos(a), sin(a)) * (9.0 if k % 2 == 0 else 4.0))
		draw_colored_polygon(star, brass)


# ------------------------------------------------------------------ state
var accent := Color("18dae8")
var mobile := false

var root: Control
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _hand: HandLayer
var _card: Control
var _card_bg: NeonPanel
var _card_header: Label
var _card_dots: DotsRow
var _card_text: Label
var _card_button: Button
var _controls_row: HBoxContainer
var _card_vb: VBoxContainer

var _complete: Control
var _complete_bg: NeonPanel
var _complete_vb: VBoxContainer

var _targets_px: Array = []           # [{"c": Vector2, "r": float}]
var _target_rects: Array = []         # [Rect2]
var _dodge := {"top_bar": Rect2(), "send_panel": Rect2(), "dock": Rect2(), "pause_button": Rect2()}
var _has_dodge := false

var _card_tween: Tween
var _card_dest := Vector2(-1, -1)
var _obstacles: Array = []
var _handler: HandlerView
var _typing := false
var _typed := 0.0
var _reward := {}      # where the card is easing to (no new tween for the same corner)
var _exit_button: Button
var _skip_button: Button
var _restart_button: Button
var _first_launch := false
var _header_emblem: TextureRect


func _ready() -> void:
	layer = 50
	root = Control.new()                                # sized explicitly by _fit_root(), not anchors
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_dim()
	_hand = HandLayer.new()
	_hand.hand_px = _hand_target_px()           # picks up set_mobile()/set_accent() called pre-_ready
	_hand.accent = accent
	root.add_child(_hand)
	_build_card()
	_build_complete()
	_fit_root()
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_on_resize)


func _process(delta: float) -> void:
	if _typing:                                     # the line types in; the handler talks meanwhile
		_typed += TYPE_RATE * delta
		var total := _card_text.get_total_character_count()
		if int(_typed) >= total:
			_finish_typing()
		else:
			_card_text.visible_characters = int(_typed)
	if _hand.kind != "":
		_hand.t = fmod(_hand.t + delta, GESTURE_LOOP)
		_hand.queue_redraw()
	if _dim.visible:
		_dim.queue_redraw()          # the shader reads TIME itself; this just keeps ring uniforms fresh if changed


func _fit_root() -> void:
	## root/_dim/_hand are FULL_RECT-anchored, but a Control added straight under a CanvasLayer (not
	## another Control) only gets that anchor-driven size once the engine's own resize notification
	## reaches it - which can lag a frame behind _ready(), and the very first show_step()/point_nodes()
	## call can land before that (the same class of bug tutorial_page.gd's backdrop had). Sized
	## explicitly instead: get_viewport().get_visible_rect() is the same logical space _dim's shader
	## covers once world_to_overlay() maps its corners to device pixels, so filling it here guarantees
	## the dim actually spans the whole screen from the first frame.
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	for c in [root, _dim, _hand]:
		c.position = Vector2.ZERO
		c.size = vp


func _on_resize() -> void:
	_fit_root()
	if _dim.visible:
		_apply_spotlight()            # the shader's uniforms are in device pixels - a resize changes them
	_position_card()
	for p in [_complete]:
		if p.visible:
			_center_complete()


# ------------------------------------------------------------------ build
func _build_dim() -> void:
	_dim = ColorRect.new()                              # sized explicitly by _fit_root(), not anchors
	_dim.color = Color.WHITE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SPOTLIGHT_SHADER
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = shader
	_dim.material = _dim_mat
	_dim.visible = false
	root.add_child(_dim)


func _label(text: String, size_value: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HEAD_FONT if size_value >= 22 else UI_FONT)
	l.add_theme_font_size_override("font_size", size_value)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


const PHONE_PT_H := 390.0     # menu.gd's landscape-phone reference height, in points


func _pt(n: float) -> float:
	## n points (the PHONE_PT_H reference) -> local (CoachOverlay-canvas / visible-rect) units.
	## CoachOverlay draws directly in the viewport's own logical space with no extra content-scale
	## layer (unlike menu.gd/tutorial_page.gd's K/_fit() chain) - get_viewport().get_visible_rect() is
	## exactly that space, and the engine's own canvas_items/expand stretch (get_final_transform(), see
	## world_to_overlay()) maps it to real device pixels. Sizing local units off DEVICE pixels directly
	## (as this file first did) under-sized everything by the stretch's scale factor whenever the
	## window wasn't exactly 1280:720 - e.g. a hardcoded "66.0" for 44 pt rendered at ~54 device px on
	## a 1266x585 phone shot instead of 66. This is the fix: local_units = pt * visible_rect.y / 390.
	return n * get_viewport().get_visible_rect().size.y / PHONE_PT_H


func _btn_h() -> float:
	return _pt(44.0) if mobile else 46.0


func _btn_fsz() -> int:
	return int(round(_pt(15.0))) if mobile else 17


func _body_fsz() -> int:
	return int(round(_pt(16.0))) if mobile else 18     # >= 14 pt with a little headroom


func _header_fsz() -> int:
	return int(round(_pt(12.0))) if mobile else 14


func _card_w() -> float:
	## "about 300 pt wide on phones" (TUTORIAL-DESIGN.md §6) for the text, plus the handler's column at its left
	return (_pt(300.0) if mobile else 340.0) + _handler_size().x + 8.0


func _handler_size() -> Vector2:
	## ~70 pt tall on phones.
	var h := _pt(70.0) if mobile else 84.0
	return Vector2(h * 0.78, h)


func _dots_h() -> float:
	return _pt(11.0) if mobile else 16.0


func _hand_target_px() -> float:
	## ~50 pt tall on phones (the 44-56 pt the design calls for, §6), a flat comfortably-visible size on
	## desktop (no phone pt reference applies there).
	return _pt(50.0) if mobile else 68.0


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", UI_FONT)
	b.add_theme_font_size_override("font_size", _btn_fsz())
	b.custom_minimum_size = Vector2(0, _btn_h())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", Hud.panel_style(accent))
	b.add_theme_stylebox_override("hover", Hud.panel_style(Color("00ddf2")))
	var pressed := Hud.panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color("edf7fa"))
	b.add_theme_color_override("font_hover_color", Color("edf7fa"))
	b.pressed.connect(func(): cb.call())
	return b


func _build_card() -> void:
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card)
	_card_bg = NeonPanel.new()
	_card_bg.accent = accent
	_card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_bg.mouse_filter = Control.MOUSE_FILTER_STOP      # a tap on the card shows the whole line (and never
	_card_bg.gui_input.connect(func(ev):                   # reaches the map)
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_finish_typing())
	_card.add_child(_card_bg)
	_handler = HandlerView.new()                           # the handler, at the card's left
	_handler.position = Vector2(10, 12)
	_handler.size = _handler_size()
	_card.add_child(_handler)
	_card_vb = VBoxContainer.new()
	_card_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_vb.add_theme_constant_override("separation", 8)
	_card_vb.offset_left = 18 + _handler_size().x
	_card_vb.offset_top = 14
	_card_vb.offset_right = -18
	_card_vb.offset_bottom = -14
	_card.add_child(_card_vb)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_vb.add_child(head_row)
	_header_emblem = TextureRect.new()                   # the Syndicate emblem beside HANDLER (§5)
	_header_emblem.texture = load(HANDLER_EMBLEM) if ResourceLoader.exists(HANDLER_EMBLEM) else null
	_header_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header_emblem.custom_minimum_size = Vector2(_header_fsz() * 2.2, _header_fsz() * 1.3)
	_header_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_emblem.visible = false                         # (0.19.3: the handler creature is the card's face now)
	head_row.add_child(_header_emblem)
	_card_header = _label(TutorialDirector.HANDLER_NAME, _header_fsz(), Color("8fd8e6"))
	_card_header.clip_text = true
	_card_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_card_header)
	_card_dots = DotsRow.new()
	_card_dots.custom_minimum_size = Vector2(0, _dots_h())
	_card_dots.dot_r = _pt(3.0) if mobile else 4.0
	_card_vb.add_child(_card_dots)
	_card_text = _label("", _body_fsz(), Color("edf7fa"))
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING   # the typewriter never re-wraps: the
		# layout (and the buttons under the text) is the full line's from the first frame (0.19.3 hotfix)
	_card_vb.add_child(_card_text)
	var button_row := HBoxContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_vb.add_child(button_row)
	_card_button = _make_button("GOT IT", func(): button_pressed.emit("got_it"))
	_card_button.visible = false
	button_row.add_child(_card_button)
	_controls_row = HBoxContainer.new()
	_controls_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_row.add_theme_constant_override("separation", 6)
	_card_vb.add_child(_controls_row)
	_skip_button = _make_button("SKIP STEP", func(): skip_step.emit())
	_controls_row.add_child(_skip_button)
	_restart_button = _make_button("RESTART", func(): restart.emit())
	_controls_row.add_child(_restart_button)
	_exit_button = _make_button("EXIT", func():
		if _first_launch:
			skip_tutorial.emit()
		else:
			exit.emit())
	_controls_row.add_child(_exit_button)
	_card.visible = false


func _build_complete() -> void:
	_complete = Control.new()
	_complete.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_complete)
	_complete_bg = NeonPanel.new()
	_complete_bg.accent = accent
	_complete_bg.glowing = true
	_complete_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_complete.add_child(_complete_bg)
	_complete_vb = VBoxContainer.new()
	_complete_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_complete_vb.add_theme_constant_override("separation", 10)
	_complete_vb.offset_left = 26
	_complete_vb.offset_top = 22
	_complete_vb.offset_right = -26
	_complete_vb.offset_bottom = -22
	_complete.add_child(_complete_vb)
	_complete.visible = false


# ------------------------------------------------------------------ public API
func set_accent(color: Color) -> void:
	## Safe to call before this node enters the tree (its children don't exist yet - _ready() picks up
	## `accent` itself then) or any time after (updates what's already built in place).
	accent = color
	if is_instance_valid(_card_bg):
		_card_bg.accent = accent
	if is_instance_valid(_complete_bg):
		_complete_bg.accent = accent
	if is_instance_valid(_hand):
		_hand.accent = accent


func set_mobile(is_mobile: bool) -> void:
	## Safe before or after _ready() - see set_accent(). The card is built once in _ready(), so calling
	## this afterwards restyles its buttons in place rather than requiring a particular call order.
	mobile = is_mobile
	if is_instance_valid(_hand):
		_hand.hand_px = _hand_target_px()
	if is_instance_valid(_card_button):
		for b in [_card_button] + _controls_row.get_children():
			b.custom_minimum_size = Vector2(0, _btn_h())
			b.add_theme_font_size_override("font_size", _btn_fsz())
		_resize_card()
		_position_card()


func set_dodge_rects(top_bar: Rect2, send_panel: Rect2, dock: Rect2, pause_button: Rect2) -> void:
	var d := {"top_bar": top_bar, "send_panel": send_panel, "dock": dock, "pause_button": pause_button}
	if _has_dodge and d == _dodge:
		return
	_dodge = d
	_has_dodge = true
	_position_card()


var _labels := {"skip_step": "SKIP STEP", "restart": "RESTART", "exit": "EXIT", "skip_tutorial": "SKIP TUTORIAL"}


func set_labels(words: Dictionary) -> void:
	for k in _labels:
		if words.has(k):
			_labels[k] = str(words[k])
	if is_instance_valid(_skip_button):
		_skip_button.text = _labels["skip_step"]
		_restart_button.text = _labels["restart"]
		_exit_button.text = _labels["skip_tutorial"] if _first_launch else _labels["exit"]


func set_first_launch(on: bool) -> void:
	## The forced first run (§7): the card's EXIT is SKIP TUTORIAL (back to MAIN, offered marked).
	_first_launch = on
	set_labels({})


func handler_mood(mood: String) -> void:
	if is_instance_valid(_handler):
		_handler.mood(mood)


func handler_rect() -> Rect2:
	return _handler.get_global_rect() if is_instance_valid(_handler) and _card.visible else Rect2()


func spotlit(p: Vector2) -> bool:
	for t in _targets_px:
		if (t["c"] as Vector2).distance_to(p) <= float(t["r"]):
			return true
	for r in _target_rects:
		if (r as Rect2).grow(6.0).has_point(p):
			return true
	return false


func _finish_typing() -> void:
	_typing = false
	_card_text.visible_characters = -1
	if is_instance_valid(_handler):
		_handler.talking = false


var _avoid: Array = []


func set_avoid(rects: Array) -> void:
	## HUD parts the card must not cover while they show (the Last Stand banner, the toast stack).
	_avoid = rects


func set_obstacles(points: Array) -> void:
	_obstacles = points


func set_finger_down(down: bool) -> void:
	if is_instance_valid(_hand) and _hand.finger_down != down:
		_hand.finger_down = down
		_hand.queue_redraw()


func ui_rects() -> Array:
	## Screen rects of whatever takes taps here (the card, a completion screen): Hud.pointer_over_ui counts
	## them, so a tap on the card never reaches the map.
	var out := []
	if is_instance_valid(_card) and _card.visible:
		out.append(Rect2(_card_dest if _card_dest.x >= 0.0 else _card.position, _card.size).merge(Rect2(_card.position, _card.size)))
	if is_instance_valid(_complete) and _complete.visible:
		out.append(Rect2(_complete.position, _complete.size))
	return out


func hide_card() -> void:
	if is_instance_valid(_card):
		_card.visible = false
	clear_spotlight()
	clear_gesture()


func show_step(header: String, text: String, dots: int, dot_index: int, button_text := "") -> void:
	if not _card.visible and is_instance_valid(_handler):
		_handler.mood("happy")                         # the handler greets as its card comes up
	_complete.visible = false
	_card.visible = true
	_card_header.text = header
	if _card_text.text != text:                            # a new line types in; the handler talks
		_card_text.text = text
		_card_text.visible_characters = 0
		_typed = 0.0
		_typing = true
		_handler.talking = true
	_card_dots.count = dots
	_card_dots.index = dot_index
	_card_dots.accent = accent
	_card_dots.queue_redraw()
	_card_button.visible = button_text != ""
	_card_button.text = button_text
	_resize_card()
	_position_card()


func point_nodes(screen_points: Array[Vector2], radius: float) -> void:
	_targets_px.clear()
	for p in screen_points:
		_targets_px.append({"c": p, "r": radius})
	_target_rects.clear()
	_apply_spotlight()
	_position_card()


func point_rect(rect: Rect2) -> void:
	_targets_px.clear()
	_target_rects = [rect]
	_apply_spotlight()
	_position_card()


func spotlight(screen_points: Array, radius: float, rects: Array) -> void:
	## Circles round nodes / lines and rounded rects round HUD controls, at once (safe every frame).
	_targets_px.clear()
	for p in screen_points:
		_targets_px.append({"c": p, "r": radius})
	_target_rects = rects.duplicate()
	if _targets_px.is_empty() and _target_rects.is_empty():
		_dim.visible = false
	else:
		_apply_spotlight()
	_position_card()


func clear_spotlight() -> void:
	_targets_px.clear()
	_target_rects.clear()
	_dim.visible = false


func world_to_overlay(p: Vector2) -> Vector2:
	## Converts a point already in the viewport's logical/visible-rect space (what
	## Camera3D.unproject_position() and Control.get_global_rect() both return) into the final
	## device-pixel space a canvas_item shader's FRAGCOORD uses. Only ever needed for the spotlight
	## shader's own uniforms (_apply_spotlight()) - see the coordinate-spaces note at the top of this
	## file. Do NOT apply this to _draw() points (the hand) or Control positions (the card): the engine
	## already transforms those correctly, and converting them again would double it up.
	return get_viewport().get_final_transform() * p


func _overlay_scale() -> float:
	## The uniform scale part of world_to_overlay()'s transform, for converting a LENGTH (a radius)
	## rather than a point.
	return get_viewport().get_final_transform().get_scale().x


func _apply_spotlight() -> void:
	_dim.visible = true
	var circles := []
	for t in _targets_px:
		var c: Vector2 = world_to_overlay(t["c"])
		circles.append(Vector3(c.x, c.y, (t["r"] as float) * _overlay_scale()))
	while circles.size() < 8:
		circles.append(Vector3(-99999.0, -99999.0, 0.0))
	_dim_mat.set_shader_parameter("circles", circles)
	_dim_mat.set_shader_parameter("num_c", _targets_px.size())
	var rects := []
	for r in _target_rects:
		var rr: Rect2 = r
		var p0: Vector2 = world_to_overlay(rr.position)
		var p1: Vector2 = world_to_overlay(rr.position + rr.size)
		rects.append(Vector4(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y))
	while rects.size() < 8:
		rects.append(Vector4(-99999.0, -99999.0, 0.0, 0.0))
	_dim_mat.set_shader_parameter("rects", rects)
	_dim_mat.set_shader_parameter("num_r", _target_rects.size())


func gesture(kind: String, from: Vector2, to := Vector2.ZERO, path := PackedVector2Array()) -> void:
	if _hand.kind != kind:
		_hand.t = 0.0                    # a new gesture starts its loop; the same one keeps running
	_hand.kind = kind
	_hand.from = from
	_hand.to = to
	_hand.path = path
	_hand.accent = accent
	_hand.visible = true
	_hand.queue_redraw()


func clear_gesture() -> void:
	_hand.kind = ""
	_hand.visible = false


func show_complete(title: String, lines: Array, primary_text: String, secondary: Array) -> void:
	_card.visible = false
	_dim.visible = false
	clear_gesture()
	_fill_complete(title, lines, primary_text, secondary, false)
	_complete.visible = true
	_center_complete()


func show_training_complete(title: String, lines: Array, primary_text: String, secondary: Array, reward := {}) -> void:
	_card.visible = false
	_dim.visible = false
	clear_gesture()
	_reward = reward
	_fill_complete(title, lines, primary_text, secondary, true)
	_complete.visible = true
	_center_complete()


func hide_complete() -> void:
	_complete.visible = false


# ------------------------------------------------------------------ layout
func _resize_card() -> void:
	## A deterministic height (not a live container measurement: an autowrap Label's minimum size
	## only settles after a layout pass, and the card must be right the same frame show_step() is
	## called) - budgeted for the design's own cap of one or two short lines (§2.4, §6).
	var w := _card_w()
	var h := _header_fsz() * 1.3 + 8.0 + _dots_h() + 8.0 + _body_fsz() * 1.35 * 2.0 + 10.0 + _btn_h()
	if _card_button.visible:
		h += _btn_h() + 8.0
	h += 28.0 + 8.0 * 3.0             # the VBox's own separation (4 gaps) + top/bottom padding
	_card.size = Vector2(w, h)        # _card_bg / _card_vb are FULL_RECT-anchored: the engine resizes
	_card.custom_minimum_size = _card.size    # them to match immediately, no manual follow-up needed


func _fallback_rect(which: String, vp: Vector2) -> Rect2:
	match which:
		"top_bar":
			return Rect2(0, 0, 340, 100)
		"pause_button":
			return Rect2(vp.x - 130, 0, 130, 60)
		"send_panel":
			return Rect2(0, 0, 150, vp.y)
		"dock":
			return Rect2(vp.x * 0.5 - 220, vp.y - 110, 440, 110)
	return Rect2()


func _place_rects() -> Array:
	## The target rects the card must dodge: never the handler beside the card itself (L0's first step spotlights it -
	## dodging its own creature made the card hop corner to corner every frame, unclickable; 0.19.3 hotfix).
	var own := handler_rect()
	if own.size == Vector2.ZERO:
		return _target_rects
	return _target_rects.filter(func(r): return not (r as Rect2).grow(4.0).intersects(own))


func _target_center(vp: Vector2) -> Vector2:
	if not _targets_px.is_empty():
		var sum := Vector2.ZERO
		for t in _targets_px:
			sum += t["c"]
		return sum / _targets_px.size()
	if not _place_rects().is_empty():
		var r: Rect2 = _place_rects()[0]
		return r.get_center()
	return vp / 2.0


func _target_bounds(vp: Vector2) -> Rect2:
	var b := Rect2(_target_center(vp), Vector2.ZERO)
	for t in _targets_px:
		b = b.expand(t["c"] - Vector2.ONE * t["r"])
		b = b.expand(t["c"] + Vector2.ONE * t["r"])
	for r in _place_rects():
		b = b.merge(r)
	return b


func _position_card() -> void:
	if not is_instance_valid(_card) or not _card.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var top_bar: Rect2 = _dodge["top_bar"] if _has_dodge else _fallback_rect("top_bar", vp)
	var pause_button: Rect2 = _dodge["pause_button"] if _has_dodge else _fallback_rect("pause_button", vp)
	var send_panel: Rect2 = _dodge["send_panel"] if _has_dodge else _fallback_rect("send_panel", vp)
	var dock: Rect2 = _dodge["dock"] if _has_dodge else _fallback_rect("dock", vp)
	var cs := _card.size
	var dock_top := dock.position.y if dock.size.y > 0.0 else vp.y - 110.0
	# each corner starts at the plain screen corner, then is pushed clear of whichever real HUD rect
	# it would actually land on (checked by intersection, not assumed - the send panel is vertically
	# centred, so a top-left card can clear the top bar and still land on top of it otherwise).
	var tl := Vector2(MARGIN, MARGIN)
	tl.y = maxf(tl.y, top_bar.position.y + top_bar.size.y + MARGIN)
	if Rect2(tl, cs).intersects(send_panel):
		tl.x = send_panel.position.x + send_panel.size.x + MARGIN
	var bl := Vector2(MARGIN, vp.y - cs.y - MARGIN)
	if Rect2(bl, cs).intersects(dock):
		bl.y = dock_top - cs.y - MARGIN
	if Rect2(bl, cs).intersects(send_panel):
		bl.x = send_panel.position.x + send_panel.size.x + MARGIN
	var tr := Vector2(vp.x - cs.x - MARGIN, MARGIN)
	tr.y = maxf(tr.y, top_bar.position.y + top_bar.size.y + MARGIN)
	tr.y = maxf(tr.y, pause_button.position.y + pause_button.size.y + MARGIN)
	var br := Vector2(vp.x - cs.x - MARGIN, vp.y - cs.y - MARGIN)
	if Rect2(br, cs).intersects(dock):
		br.y = dock_top - cs.y - MARGIN
	var corners := {"tl": tl, "tr": tr, "bl": bl, "br": br}
	var target_center := _target_center(vp)
	var best_key := "br"
	var best_score := -INF
	for key in corners.keys():
		var pos: Vector2 = corners[key]
		var rect := Rect2(pos, cs)
		var center := rect.get_center()
		var score := center.distance_to(target_center)
		for a in _avoid:
			if rect.intersects(a):
				score -= 2500.0
		score -= 4000.0 * _covered(rect)   # heavily discourage covering targets: each ring / rect counts (not their bounding box)
		for o in _obstacles:               # then the nodes: a corner over the map's empty sky wins
			if rect.grow(10.0).has_point(o):
				score -= 700.0
		if _card_dest.x >= 0.0 and pos.distance_to(_card_dest) < 1.0 and not _covers_target(rect):
			score += 1600.0                # keep the corner it is in: no hop between steps unless the target needs it
		if score > best_score:
			best_score = score
			best_key = key
	var chosen: Vector2 = corners[best_key]
	chosen.x = clampf(chosen.x, MARGIN, maxf(MARGIN, vp.x - cs.x - MARGIN))
	chosen.y = clampf(chosen.y, MARGIN, maxf(MARGIN, vp.y - cs.y - MARGIN))
	if chosen.distance_to(_card_dest) < 1.0:
		return
	_card_dest = chosen
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	if _card.position == Vector2.ZERO:
		_card.position = chosen
	else:
		_card_tween = create_tween()
		_card_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_card_tween.tween_property(_card, "position", chosen, EASE_TIME)


func _covered(rect: Rect2) -> int:
	var k := 0
	for t in _targets_px:
		if rect.grow(float(t["r"]) * 0.8).has_point(t["c"]):
			k += 1
	for r in _place_rects():
		if rect.intersects(r):
			k += 1
	return k


func _covers_target(rect: Rect2) -> bool:
	for t in _targets_px:
		if rect.grow(float(t["r"])).has_point(t["c"]):
			return true
	for r in _place_rects():
		if rect.intersects(r):
			return true
	return false


func _fill_complete(title: String, lines: Array, primary_text: String, secondary: Array, graduate: bool) -> void:
	for c in _complete_vb.get_children():
		c.queue_free()
	_complete_vb.add_child(_label(title, 30, Color("edf7fa")))
	for line in lines:
		var l := _label(str(line), _body_fsz(), Color("c8e6ee"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_complete_vb.add_child(l)
	if graduate:
		var slot := GraduatePanel.new()
		slot.head_font = HEAD_FONT
		slot.ui_font = UI_FONT
		slot.unlocked = bool(_reward.get("unlocked", true))
		slot.title = str(_reward.get("title", "GRADUATE VAT"))
		slot.faction = str(_reward.get("faction", "null"))
		slot.custom_minimum_size = Vector2(_pt(150.0) if mobile else 240.0, _pt(118.0) if mobile else 190.0)
		slot.size = slot.custom_minimum_size
		var wrap := CenterContainer.new()
		wrap.add_child(slot)
		_complete_vb.add_child(wrap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_complete_vb.add_child(row)
	var primary := _make_button(primary_text, func(): button_pressed.emit("primary"))
	primary.add_theme_stylebox_override("normal", Hud.panel_style(Color("00ddf2")))
	row.add_child(primary)
	for i in range(secondary.size()):
		var idx := i
		row.add_child(_make_button(str(secondary[idx]), func(): button_pressed.emit("secondary:%d" % idx)))
	# a deterministic height, for the same reason _resize_card() avoids a live measurement
	var h := 44.0 + float(lines.size()) * (_body_fsz() * 1.35 * 1.25) + _btn_h() + 60.0
	if graduate:
		h += (_pt(118.0) if mobile else 190.0) + 10.0
	var w := _card_w() * (2.0 if mobile else 1.7)
	_complete.size = Vector2(w, h)
	_complete.custom_minimum_size = _complete.size


func _center_complete() -> void:
	var vp := get_viewport().get_visible_rect().size
	_complete.position = (vp - _complete.size) / 2.0
