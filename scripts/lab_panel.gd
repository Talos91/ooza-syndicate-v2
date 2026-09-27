class_name LabPanel
extends CanvasLayer
## MAP LAB in-match tools (branch map-lab only): a LAB button in the HUD's right column opens speed
## (1x / 2x / 4x / 8x: extra Sim steps per frame), LAST STAND NOW / VERY LAST STAND NOW (Sim.start_*_now),
## the rulebook overlay (the map's findings from maps/index.json drawn on the board: red = hard, amber =
## soft) with a live size readout (platform diameter and the closest two platforms, in points), RESTART and
## BACK TO LAB.

const SPEEDS := [1, 2, 4, 8]
const HARD := Color(1.0, 0.25, 0.25, 0.95)
const SOFT := Color(1.0, 0.75, 0.2, 0.9)

static var speed := 1
static var overlay := false                      # the rule overlay starts off (Daniele: "why maps have red circles?"): LAB > RULE OVERLAY
# CAMERA trial (Daniele 2026-09-27: "the tall notification on top covers the platforms ... add a lab function to
# play with camera axis"): pitch (0 = the map's own), the map shifted down the screen (fraction of the map's
# depth; + = lower on screen, room under the top bar) and zoom (x the fit distance; > 1 = further away).
static var cam_pitch := 0.0
static var cam_shift := 0.0
static var cam_zoom := 1.0


static func adjust_camera(m: Node) -> void:
	## Called at the end of main._fit_camera (the fit already done at the current pitch): zoom, then slide the
	## aim point away from the camera so the board sits lower on the screen.
	if m.sim == null:
		return
	m.cam_dist *= cam_zoom
	if cam_shift != 0.0:
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for n in m.sim.nodes:
			lo = lo.min(n["pos"])
			hi = hi.max(n["pos"])
		var f := Rules.front_dir()
		var depth: float = absf((hi - lo).dot(f)) + 2.0 * Rules.R
		m.cam_target -= f * depth * cam_shift

var main: Node
var toggle: Button
var panel: PanelContainer
var box: VBoxContainer
var info: Label
var canvas: Control
var entry := {}
# PERF readout (Architect, Alpha 21 optimization: "FPS avg + 1 % low over the last 5 s, frame time, draw calls,
# primitives, objects, render scale / viewport, device pixel ratio ... a 60 s report to screenshot")
static var perf_on := false
var perf_box: PanelContainer
var perf_label: Label
var _frames: Array = []                               # [time, dt, draws, prims, objs] over the last 5 s
var _rep: Array = []                                  # the same over the 60 s report
var _rep_until := -1.0
var _report := ""


func _init(m: Node) -> void:
	main = m
	layer = 30


func _ready() -> void:
	entry = MapLab.entry_for(str(main.map.get("code", "")))
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_overlay)
	add_child(canvas)
	toggle = _button("LAB", _toggle, 24)
	toggle.custom_minimum_size = Vector2(96, 72)
	add_child(toggle)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, 0.94)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.custom_minimum_size.x = 380
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 20)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var sp := HBoxContainer.new()
	for s in SPEEDS:
		var v: int = s
		var b := _button("%dx" % v, func(): _set_speed(v), 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("speed", v)
		sp.add_child(b)
	box.add_child(sp)
	box.add_child(_button("LAST STAND NOW", func(): main.sim.start_last_stand_now(), 22))
	box.add_child(_button("VERY LAST STAND NOW", func(): main.sim.start_very_last_stand_now(), 22))
	box.add_child(_button("RULE OVERLAY", _toggle_overlay, 22))
	box.add_child(_button("PERF READOUT", _toggle_perf, 22))
	box.add_child(_button("PERF REPORT (60 s)", _start_report, 22))
	var cam_lbl := Label.new()
	cam_lbl.text = "CAMERA"
	cam_lbl.add_theme_font_size_override("font_size", 18)
	box.add_child(cam_lbl)
	for row in [[["PITCH -", func(): _cam("pitch", -2.0)], ["PITCH +", func(): _cam("pitch", 2.0)]],
			[["MAP LOWER", func(): _cam("shift", 0.05)], ["MAP HIGHER", func(): _cam("shift", -0.05)]],
			[["ZOOM IN", func(): _cam("zoom", -0.05)], ["ZOOM OUT", func(): _cam("zoom", 0.05)]],
			[["CAMERA RESET", func(): _cam("reset", 0.0)]]]:
		var hb := HBoxContainer.new()
		for it in row:
			var b := _button(it[0], it[1], 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(b)
		box.add_child(hb)
	box.add_child(_button("RESTART", _restart, 22))
	box.add_child(_button("BACK TO LAB", _back, 22))
	for f in entry.get("findings", []):
		var l := Label.new()
		l.text = "%s %s  %s" % [f.get("rule", ""), str(f.get("sev", "")).to_upper(), f.get("msg", "")]
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", HARD if f.get("sev") == "hard" else SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	perf_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	psb.set_corner_radius_all(8)
	psb.content_margin_left = 10
	psb.content_margin_right = 10
	psb.content_margin_top = 6
	psb.content_margin_bottom = 6
	perf_box.add_theme_stylebox_override("panel", psb)
	perf_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	perf_label = Label.new()
	perf_label.add_theme_font_size_override("font_size", 19)
	perf_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.6))
	perf_box.add_child(perf_label)
	add_child(perf_box)
	_refresh()
	if "--lab-perf" in OS.get_cmdline_user_args():     # testing: the readout on from the start
		perf_on = true
	if "--lab-open" in OS.get_cmdline_user_args():     # testing: the panel open for --shots
		panel.visible = true


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	toggle.position = Vector2(vp.x - toggle.custom_minimum_size.x - 10, vp.y * 0.5 - 36)
	panel.size = Vector2(410, minf(vp.y - 130, 640))
	panel.position = Vector2(vp.x - panel.size.x - toggle.custom_minimum_size.x - 20, 110)


var _vat_r := {}                                    # model key -> its footprint radius (m)


func _big_vats() -> void:
	## MAP LAB bigVat: every common / special node's centre model scaled to fill the platform (rim minus
	## 0.4 m), height grown half as much so it doesn't wall off the view. Re-applied every frame: tier-ups
	## and captures swap the model (MapBuilder.set_centre_model).
	for n in main.sim.nodes:
		if n["relay"] != "":
			continue
		var entry: Dictionary = main.vis[n["id"]]
		var node: Node3D = entry.get("vat_node")
		if node == null or not is_instance_valid(node):
			continue
		var key: String = entry.get("model_key", "")
		if not _vat_r.has(key):
			var box := AABB()
			var first := true
			var inv := node.global_transform.affine_inverse()
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				var bb: AABB = inv * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			var c := box.get_center()                  # node-local, at the model's current scale
			var sc := node.scale
			_vat_r[key] = [maxf(0.5, maxf(box.size.x * sc.x, box.size.z * sc.z) / 2.0 / maxf(sc.x, 0.001)),
					Vector3(c.x * sc.x / maxf(sc.x, 0.001), 0.0, c.z * sc.z / maxf(sc.z, 0.001))]
		var r: float = _vat_r[key][0]
		var off: Vector3 = _vat_r[key][1]
		var k: float = (Rules.R - 0.4) / r
		entry["lab_scale"] = Vector3(k, 1.0 + (k - 1.0) * 0.5, k)   # fx.gd keeps it (its build grow / reset)
		var rot := Basis(Vector3.UP, node.rotation.y)
		var p: Vector3 = n["pos"] - rot * (off * k)      # the grown footprint centred on the platform
		node.position = Vector3(p.x, node.position.y, p.z)


func _perf_sample(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var row := [now, delta, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)]
	_frames.append(row)
	while not _frames.is_empty() and now - float(_frames[0][0]) > 5.0:
		_frames.pop_front()
	if _rep_until > 0.0:
		_rep.append(row)
		if now >= _rep_until:
			_rep_until = -1.0
			_report = _stats_text(_rep, true)
			print("LAB PERF REPORT
" + _report)
			DisplayServer.clipboard_set(_report)
	perf_box.visible = perf_on or _report != "" or _rep_until > 0.0
	if not perf_box.visible:
		return
	var head := ""
	if _rep_until > 0.0:
		head = "REPORT: recording, %d s left
" % int(ceil(_rep_until - now))
	perf_label.text = head + (_report if _report != "" and _rep_until < 0.0 else _stats_text(_frames, false))
	var vp := get_viewport().get_visible_rect().size
	perf_box.position = Vector2(12, vp.y * 0.5 + 40)


func _stats_text(rows: Array, report: bool) -> String:
	if rows.size() < 2:
		return "PERF: measuring..."
	var dts: Array = []
	var d_sum := 0.0
	var d_max := 0.0
	var p_sum := 0.0
	var p_max := 0.0
	var o_sum := 0.0
	var o_max := 0.0
	for r in rows:
		dts.append(float(r[1]))
		d_sum += float(r[2])
		d_max = maxf(d_max, float(r[2]))
		p_sum += float(r[3])
		p_max = maxf(p_max, float(r[3]))
		o_sum += float(r[4])
		o_max = maxf(o_max, float(r[4]))
	var n := float(rows.size())
	var span := maxf(float(rows[-1][0]) - float(rows[0][0]), 0.001)
	var fps := n / span
	dts.sort()
	var worst := maxi(1, int(ceil(dts.size() * 0.01)))
	var w_sum := 0.0
	for k in range(worst):
		w_sum += float(dts[dts.size() - 1 - k])
	var low := worst / maxf(w_sum, 0.0001)
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var win := DisplayServer.window_get_size()
	var dpr := 1.0
	var ua := OS.get_name()
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var v = JavaScriptBridge.eval("window.devicePixelRatio", true)
		if v is float or v is int:
			dpr = float(v)
		var u = JavaScriptBridge.eval("navigator.userAgent", true)
		if u is String:
			ua = u
	var t := "FPS %.0f avg · %.0f 1%% low · %.1f ms (max %.0f)
draws %.0f (max %.0f) · prims %.0fk · objects %.0f
viewport %dx%d · window %dx%d · 3D scale %.2f · dpr %.2f" % [
			fps, low, 1000.0 * span / n, 1000.0 * float(dts[-1]), d_sum / n, d_max, p_sum / n / 1000.0, o_sum / n,
			int(size.x), int(size.y), win.x, win.y, vp.scaling_3d_scale, dpr]
	if report:
		t = "PERF REPORT %.0f s · %s %s · %d nodes · speed %dx · t %d:%02d · %s
" % [span, main.map.get("code", ""),
				main.map.get("name", ""), main.sim.nodes.size(), speed, int(main.sim.time) / 60, int(main.sim.time) % 60,
				Rules.VERSION] + t + "
prims max %.0fk · objects max %.0f · %s" % [p_max / 1000.0, o_max, ua.substr(0, 120)]
	return t


func _toggle_perf() -> void:
	perf_on = not perf_on
	if not perf_on:
		_report = ""


func _start_report() -> void:
	_report = ""
	_rep.clear()
	_rep_until = Time.get_ticks_msec() / 1000.0 + 60.0
	panel.visible = false                              # the panel off the board while it measures


func _process(delta: float) -> void:
	_layout()
	_perf_sample(delta)
	if MapLab.big_vat and main.sim != null:
		_big_vats()
	if overlay:
		canvas.queue_redraw()
	if panel.visible:
		info.text = _size_text()
	if speed <= 1 or not main.started or main.paused or main.online or main.sim == null or main.sim.over:
		return
	var dt := minf(delta, 0.05)
	for k in range(speed - 1):                       # extra Sim steps: the rendering follows the Sim
		for ai in main.ais:
			ai.think(main.sim, dt)
		main.sim.step(dt)


func _pt_per_px() -> float:
	var vp := get_viewport().get_visible_rect().size
	var css := 844.0                                 # desktop: an 844 pt landscape phone (the phone-fit probe's)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var w = JavaScriptBridge.eval("Math.max(window.innerWidth, window.innerHeight)", true)
		if w is float or w is int:
			css = float(w)
	return css / maxf(vp.x, 1.0)


func _screen(p: Vector3) -> Vector2:
	return main.cam.unproject_position(p)


func _size_text() -> String:
	var k := _pt_per_px()
	var plat := 1e9
	var near := 1e9
	var nodes: Array = main.sim.nodes
	for i in range(nodes.size()):
		var p: Vector3 = nodes[i]["pos"]
		var c := _screen(p)
		plat = minf(plat, 2.0 * c.distance_to(_screen(p + Vector3(Rules.R, 0, 0))) * k)
		for j in range(i + 1, nodes.size()):
			near = minf(near, c.distance_to(_screen(nodes[j]["pos"])) * k)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for n in nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	var fp: Array = [hi.x - lo.x + 2.0 * Rules.R, hi.z - lo.z + 2.0 * Rules.R]   # the footprint, as the rulebook measures it
	var rb := "PASS" if entry.get("pass", false) else "%d hard" % int(entry.get("hard", 0))
	return "%s %s\n%d x %d m · %d nodes · rulebook %s\nplatform %.0f pt · closest platforms %.0f pt apart\ncamera: pitch %.0f deg · map lower %+d %% · zoom %.2f\nspeed %dx · t %d:%02d" % [
			main.map.get("code", ""), main.map.get("name", ""), int(fp[0]), int(fp[1]), nodes.size(), rb, plat, near,
			main._base_pitch, int(round(cam_shift * 100.0)), cam_zoom, speed, int(main.sim.time) / 60, int(main.sim.time) % 60]


func _draw_overlay() -> void:
	if not overlay or main.sim == null:
		return
	var nodes: Array = main.sim.nodes
	var r_px := 0.0
	if not nodes.is_empty():
		var p0: Vector3 = nodes[0]["pos"]
		r_px = _screen(p0).distance_to(_screen(p0 + Vector3(Rules.R, 0, 0)))
	for f in entry.get("findings", []):
		var col := HARD if f.get("sev") == "hard" else SOFT
		for i in f.get("nodes", []):
			if int(i) < nodes.size():
				canvas.draw_arc(_screen(nodes[int(i)]["pos"]), r_px + 6.0, 0.0, TAU, 40, col, 5.0)
		for k in f.get("edges", []):
			var e: Dictionary = main.map["edges"][int(k)]
			canvas.draw_line(_screen(nodes[int(e["from"])]["pos"]), _screen(nodes[int(e["to"])]["pos"]), col, 5.0)


func _cam(what: String, step: float) -> void:
	match what:
		"pitch":
			cam_pitch = clampf((cam_pitch if cam_pitch > 0.0 else main._base_pitch) + step, 30.0, 88.0)
		"shift":
			cam_shift = clampf(cam_shift + step, -0.5, 0.5)
		"zoom":
			cam_zoom = clampf(cam_zoom + step, 0.6, 1.6)
		"reset":
			cam_pitch = 0.0
			cam_shift = 0.0
			cam_zoom = 1.0
	main.pitch_forced = cam_pitch > 0.0
	main._base_pitch = cam_pitch if cam_pitch > 0.0 else MapCamera.pitch_for(str(main.map.get("code", "")))
	main.cam_pitch = main._base_pitch
	main._fit_camera()
	info.text = _size_text()


func _toggle() -> void:
	panel.visible = not panel.visible
	_refresh()


func _toggle_overlay() -> void:
	overlay = not overlay
	canvas.queue_redraw()
	_refresh()


func _set_speed(v: int) -> void:
	speed = v
	_refresh()


func _refresh() -> void:
	for row in box.get_children():
		if row is HBoxContainer:
			for b in row.get_children():
				_style(b, Color(0.1, 0.45, 0.55) if int(b.get_meta("speed", 0)) == speed else Color(0.1, 0.14, 0.18))
		elif row is Button and row.text == "RULE OVERLAY":
			_style(row, Color(0.1, 0.45, 0.55) if overlay else Color(0.1, 0.14, 0.18))
	info.text = _size_text()


func _restart() -> void:
	main.restart()


func _back() -> void:
	speed = 1
	main.to_menu()


func _button(t: String, cb: Callable, size: int) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size.y = 64
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	_style(b, Color(0.1, 0.14, 0.18))
	return b


func _style(b: Button, col: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.08) if st == "hover" else (col.darkened(0.2) if st == "pressed" else col)
		sb.set_corner_radius_all(10)
		if st == "focus":
			sb.draw_center = false
		b.add_theme_stylebox_override(st, sb)
