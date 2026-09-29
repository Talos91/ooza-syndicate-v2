extends Node
## PLAYER ZOOM check (0.23.6, Daniele: "zoom, use 2 fingers to zoom"). Run WINDOWED as a scene (the camera must project):
##   Godot --path . --resolution 1688x780 res://tests/zoom_check.tscn -- --no-telemetry [--mobile] [--out=<dir>]
## Through main._unhandled_input: a two-finger pinch out closes in around the fingers' midpoint, never past
## Rules.CAM_ZOOM_MIN; the first finger's release after a pinch taps nothing; the wheel zooms at the pointer; zoomed
## all the way out the view is exactly the fitted whole-map view again. --out saves before / zoomed screenshots.
## Exit code 0 = all passed.

const MAIN := "res://main.tscn"
var failures := 0
var m: Node


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _touch(i: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = pressed
	m._unhandled_input(e)
	if i == 0:                                        # emulate_mouse_from_touch: finger 0 is also the mouse
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		m._unhandled_input(mb)


func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	m._unhandled_input(e)


func _wheel(p: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = p
	e.factor = 1.0
	m._unhandled_input(e)


func _shot(out: String, name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))


func _pinch(c: Vector2, from_gap: float, to_gap: float) -> void:
	_touch(0, c - Vector2(from_gap, 0), true)
	_touch(1, c + Vector2(from_gap, 0), true)
	for k in range(1, 11):
		var g := lerpf(from_gap, to_gap, k / 10.0)
		_drag(0, c - Vector2(g, 0))
		_drag(1, c + Vector2(g, 0))
		await _frames(1)
	_touch(0, c - Vector2(to_gap, 0), false)
	_touch(1, c + Vector2(to_gap, 0), false)
	await _frames(2)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mobile := "--mobile" in args
	var out := ""
	for a in args:
		if a.begins_with("--out="):
			out = a.substr(6)
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": "1v1", "map": "res://maps4/N-01-knot.json"}
	m = (load(MAIN) as PackedScene).instantiate()
	m.mobile = mobile
	get_tree().root.add_child(m)
	await _frames(20)
	m.ais.clear()
	var fit_d: float = m._view_fit[1]
	var fit_t: Vector3 = m._view_fit[0]
	check(is_equal_approx(m.cam_dist, fit_d), "starts at the fitted view (%.1f m)" % fit_d)
	await _shot(out, "zoom_0_fit.png")
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var c := vp / 2.0 + Vector2(vp.x * 0.1, 0)
	var g0: Vector3 = m._ground(c)
	await _pinch(c, 60.0, 120.0)                     # fingers twice as far apart: twice as close
	check(absf(m.cam_dist - fit_d / 2.0) < fit_d * 0.03, "pinch x2 halves the distance (%.1f -> %.1f m)" % [fit_d, m.cam_dist])
	var g1: Vector3 = m._ground(c)
	check(Vector2(g1.x - g0.x, g1.z - g0.z).length() < 1.0 or m.cam_target != fit_t, "the ground under the fingers stays put (moved %.2f m)" % Vector2(g1.x - g0.x, g1.z - g0.z).length())
	check(m.hud.inspector_id < 0 and m.drag_from < 0 and m._pending_inspect < 0, "the pinch taps / sends nothing")
	await _frames(4)
	await _shot(out, "zoom_1_pinch2x.png")
	await _pinch(c, 40.0, 200.0)
	check(absf(m.cam_dist - fit_d * Rules.CAM_ZOOM_MIN) < 0.01, "never closer than CAM_ZOOM_MIN (%.1f m)" % m.cam_dist)
	await _frames(4)
	await _shot(out, "zoom_2_closest.png")
	for i in range(40):
		_wheel(vp * 0.3, false)
	check(is_equal_approx(m.cam_dist, fit_d) and m.cam_target.distance_to(fit_t) < 0.01, "wheel out: exactly the fitted view again")
	_wheel(vp / 2.0, true)
	check(absf(m.cam_dist - fit_d / Rules.CAM_WHEEL_STEP) < 0.01, "one wheel notch in: / %.2f" % Rules.CAM_WHEEL_STEP)
	for i in range(10):
		_wheel(vp / 2.0, false)
	# a normal one-finger send still works after zooming
	check(m.touches.is_empty(), "no finger left down")
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)
