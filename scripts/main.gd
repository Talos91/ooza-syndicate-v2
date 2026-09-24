extends Node3D
## Ooze Syndicate 2.0 prototype: Two Piers (starter map 1).
## Drag from one of your nodes to any node to send; the buttons set 25/50/75/100 %.
## Command-line user args (after `--`):
##   --map=res://maps/004-two-piers.json   map to load
##   --demo                                 both seats played by the AI
##   --shots=4,12,25 --out=<dir>            save screenshots at those match times, then quit
##   --window=2340x1080                      size the window like a phone (landscape) for testing
##   --mobile                                force the phone quality profile on desktop
##   --scenario=fight|rear|queue             stage a contact on the deck between nodes 1 and 0 and
##                                           zoom the camera onto it (no AI) - for looking at fights
## Phones are the target: iPhone 15/16 (~2556x1179) and Galaxy S2x/A5x (~2340x1080), ~19.5:9 landscape.

const HUMAN := "A"
const SEAT_FACTIONS := {"A": "null", "B": "ember", "C": "bloom", "D": "vex", "E": "solar"}

var map: Dictionary
var sim := Sim.new()
var ais: Array = []
var vis: Dictionary
var hordes: HordeView
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_dist := 90.0
var cam_yaw := 0.0
var fraction := 0.5
var drag_from := -1
var pan_from := Vector3.INF
var drag_mesh := ImmediateMesh.new()
var drag_line := MeshInstance3D.new()
var hud_time: Label
var hud_info: Label
var end_panel: PanelContainer
var trace: Array = []
var _trace_t := 0.0
var shots: Array = []
var shot_dir := ""
var demo := false
var scenario := ""                 # --scenario=: staged contact for looking at the fight visuals
var scenario_focus := Vector3.INF
var scenario_zoom := 30.0
var _scenario_done := false
var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
var window_size := Vector2i.ZERO
var sun: DirectionalLight3D
var touches := {}                  # touch index -> screen position (two-finger pinch / pan)
var pinch_dist := 0.0
var hud_root: Control
var hud_top: HBoxContainer
var hud_side: VBoxContainer
var margins := Vector4(16, 12, 16, 12)       # left, top, right, bottom (safe area)
var _fitted_size := Vector2.ZERO             # re-fit whenever the screen/canvas size changes
var rotate_hint: Label
var debug_button: Button
var debug_panel: PanelContainer


func _ready() -> void:
	var map_path := "res://maps/004-two-piers.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_path = arg.substr(6)
		elif arg == "--demo":
			demo = true
		elif arg.begins_with("--shots="):
			for t in arg.substr(8).split(","):
				shots.append(float(t))
		elif arg.begins_with("--out="):
			shot_dir = arg.substr(6)
		elif arg.begins_with("--window="):
			var wh := arg.substr(9).split("x")
			window_size = Vector2i(int(wh[0]), int(wh[1]))
		elif arg == "--mobile":
			mobile = true
		elif arg.begins_with("--scenario="):
			scenario = arg.substr(11)
		elif arg.begins_with("--zoom="):                 # camera distance for a --scenario (default 30)
			scenario_zoom = float(arg.substr(7))
	if window_size != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
	map = MapBuilder.load_map(map_path)
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	sim.setup(map, MapBuilder.layout(map), seats, SEAT_FACTIONS)
	_build_world()
	vis = MapBuilder.build(self, sim)
	if not vis["stretched"].is_empty():
		push_warning("edges stretched to fit (not honest): %s" % [vis["stretched"]])
	hordes = HordeView.new()
	add_child(hordes)
	drag_line.mesh = drag_mesh
	add_child(drag_line)
	for seat in seats.values():
		if (seat != HUMAN or demo) and scenario == "":
			ais.append(SeatAI.new(seat, 2.5 if seat != HUMAN else 3.1))
	if scenario != "":
		_stage_scenario()
	sim.captured.connect(_on_captured)
	sim.finished.connect(_on_finished)
	for n in sim.nodes:
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
	_build_hud()
	_apply_quality()
	get_viewport().size_changed.connect(_on_resized)
	await get_tree().process_frame                   # let a --window resize land before fitting
	_on_resized()


func _apply_quality() -> void:
	## Phone profile (GL Compatibility): no realtime shadows, 3D at 75 % resolution, no MSAA,
	## 60 fps cap. Neon lights and glow carry the look; the HUD stays full resolution.
	Engine.max_fps = 60
	if mobile:
		sun.shadow_enabled = false
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED


func _on_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	_fitted_size = vp
	_apply_safe_area()
	_fit_camera()
	rotate_hint.visible = vp.y > vp.x                 # landscape game: ask portrait phones to rotate
	rotate_hint.size = vp


func _apply_safe_area() -> void:
	## Keep the HUD clear of the notch / Dynamic Island / rounded corners on phones.
	var vp := get_viewport().get_visible_rect().size
	var left := 16.0
	var right := 16.0
	var top := 10.0
	if OS.has_feature("mobile"):                      # native phone builds report real insets
		var screen := Vector2(DisplayServer.screen_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.screen_get_position())   # desktop reports virtual-desktop coords
		var k := vp.x / maxf(screen.x, 1.0)
		left = maxf(safe.position.x * k, left)
		right = maxf((screen.x - safe.end.x) * k, right)
		top = maxf(safe.position.y * k, top)
	if mobile:                                        # notch / rounded corners even without a reported inset
		left = maxf(left, vp.x * 0.035)
		right = maxf(right, vp.x * 0.035)
	margins = Vector4(left, top, right, 12.0)
	hud_top.position = Vector2(left, top)
	if debug_button:                                  # bottom-left corner, panel opens above it
		debug_button.position = Vector2(left, vp.y - 12.0 - debug_button.size.y)
		debug_panel.size = debug_panel.get_combined_minimum_size()
		debug_panel.position = Vector2(left, debug_button.position.y - 8.0 - debug_panel.size.y)
	var side_size := hud_side.get_combined_minimum_size()
	hud_side.size = side_size
	hud_side.position = Vector2(vp.x - right - side_size.x, (vp.y - side_size.y) / 2.0)


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.014)          # the void
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, -145, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true


func _fit_camera() -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for n in sim.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	cam_target = (lo + hi) / 2.0
	var ext := hi - lo
	cam_yaw = PI / 2.0 if ext.z > ext.x else 0.0      # long axis across the landscape screen
	# fit the map into the screen area LEFT of the send buttons, and centre it there
	var vp := get_viewport().get_visible_rect().size
	var half_h := tan(hfov_half(vp))
	var panel := hud_side.size.x + margins.z + 20.0 if hud_side else 0.0
	var free := clampf((vp.x - panel - margins.x) / vp.x, 0.5, 1.0)
	var long_side := maxf(ext.x, ext.z) + 2.0 * Rules.R + 6.0     # whole platforms plus a margin
	cam_dist = (long_side / 2.0) / (half_h * free) * 1.04
	_place_camera()
	var screen_right := cam.global_transform.basis.x
	var shift := cam_dist * half_h * ((panel - margins.x) / vp.x)
	cam_target += screen_right * shift
	if scenario_focus != Vector3.INF:                 # staged contact: look at that deck up close
		cam_target = scenario_focus
		cam_dist = scenario_zoom
	_place_camera()


func _stage_scenario() -> void:
	## Staged contacts on the S deck between nodes 1 and 0 (the sends go out in _process once the
	## sim runs). fight: two lines meet head-on. rear: a slow A line is caught from behind by B.
	## queue: a fast A line queues behind a slow friend.
	sim.nodes[1]["owner"] = "A"
	sim.nodes[1]["units"] = 160.0
	sim.nodes[0]["owner"] = "B" if scenario == "fight" else "A"
	sim.nodes[0]["units"] = 160.0
	if scenario == "rear":                                # B's pursuer starts from node 3, behind node 1
		sim.nodes[3]["owner"] = "B"
		sim.nodes[3]["units"] = 200.0
	for n in sim.nodes:
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
	scenario_focus = (sim.nodes[1]["pos"] + sim.nodes[0]["pos"]) / 2.0


func _run_scenario() -> void:
	if _scenario_done or sim.time < 0.3:
		return
	match scenario:
		"fight":
			sim.send(1, 0, 1.0)
			sim.send(0, 1, 1.0)
			_scenario_done = true
		"rear":
			if sim.hordes.is_empty():
				var slow := sim.send(1, 0, 0.5)            # a slow A line on its way to a friendly node
				slow["speed"] = 0.2
			elif sim.time > 2.5:
				sim.send(3, 0, 1.0)                        # B's pursuer comes through node 1 behind it
				_scenario_done = true
		"queue":
			if sim.hordes.is_empty():
				var slow := sim.send(1, 0, 0.3)
				slow["speed"] = 0.25
			elif sim.time > 2.0:
				sim.send(1, 0, 1.0)
				_scenario_done = true
		_:
			_scenario_done = true


func hfov_half(vp: Vector2) -> float:
	return atan(tan(deg_to_rad(cam.fov) / 2.0) * vp.x / vp.y)


func _place_camera() -> void:
	var pitch := deg_to_rad(55.0)
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, cam_yaw)
	cam.position = cam_target + back * cam_dist
	cam.look_at(cam_target, Vector3.UP)


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_root = Control.new()                          # children placed by _apply_safe_area()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_root)
	var area := hud_root
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(top)
	hud_top = top
	hud_time = Label.new()
	hud_time.add_theme_font_size_override("font_size", 30)
	top.add_child(hud_time)
	hud_info = Label.new()
	hud_info.add_theme_font_size_override("font_size", 22)
	hud_info.text = "   Two Piers - you are cyan - drag from your node"
	top.add_child(hud_info)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	area.add_child(side)
	hud_side = side
	var group := ButtonGroup.new()
	for f in Rules.SEND_FRACTIONS:
		var b := Button.new()
		b.text = "%d%%" % int(f * 100)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(120, 78)      # ~9 mm tall on a 6" phone: thumb-sized
		b.add_theme_font_size_override("font_size", 28)
		b.button_pressed = is_equal_approx(f, fraction)
		b.pressed.connect(func(): fraction = f)
		side.add_child(b)
	_build_debug(area)
	rotate_hint = Label.new()
	rotate_hint.text = "Rotate your phone\nOoze Syndicate plays in landscape"
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rotate_hint.add_theme_font_size_override("font_size", 44)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.01, 0.012, 0.018, 0.94)
	rotate_hint.add_theme_stylebox_override("normal", bg)
	rotate_hint.visible = false
	layer.add_child(rotate_hint)
	end_panel = PanelContainer.new()
	end_panel.visible = false
	end_panel.anchor_left = 0.5
	end_panel.anchor_right = 0.5
	end_panel.anchor_top = 0.5
	end_panel.anchor_bottom = 0.5
	end_panel.offset_left = -220
	end_panel.offset_top = -90
	layer.add_child(end_panel)
	var box := VBoxContainer.new()
	end_panel.add_child(box)
	var l := Label.new()
	l.name = "Result"
	l.add_theme_font_size_override("font_size", 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(440, 0)
	box.add_child(l)
	var again := Button.new()
	again.text = "Play again"
	again.custom_minimum_size = Vector2(0, 60)
	again.add_theme_font_size_override("font_size", 26)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)


func _build_debug(area: Control) -> void:
	## Debug controls for playtests (Daniele, 2026-09-25). Live sliders, thumb-sized, bottom-left.
	## 1. blob speed on decks vs on platforms (PLAYTEST-NOTES 5).
	debug_button = Button.new()
	debug_button.text = "Debug"
	debug_button.toggle_mode = true
	debug_button.custom_minimum_size = Vector2(120, 60)
	debug_button.add_theme_font_size_override("font_size", 24)
	debug_button.size = debug_button.custom_minimum_size
	area.add_child(debug_button)
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	area.add_child(debug_panel)
	debug_button.toggled.connect(func(on: bool): debug_panel.visible = on)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	debug_panel.add_child(box)
	var title := Label.new()
	title.text = "Debug - live, resets on reload"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var deck := _debug_slider(box, "Deck speed", 1.0, 8.0, 0.1, Rules.deck_speed, "%.1f m/s",
			func(v: float): Rules.deck_speed = v)
	var node := _debug_slider(box, "Platform speed", 1.0, 10.0, 0.1, Rules.node_speed_mult, "x%.1f deck",
			func(v: float): Rules.node_speed_mult = v)
	var reset := Button.new()
	reset.text = "Reset to rules"
	reset.custom_minimum_size = Vector2(0, 48)
	reset.add_theme_font_size_override("font_size", 20)
	reset.pressed.connect(func():
		deck.value = Rules.DECK_SPEED_DEFAULT
		node.value = Rules.NODE_SPEED_MULT_DEFAULT)
	box.add_child(reset)


func _debug_slider(box: Control, text: String, lo: float, hi: float, step: float, value: float,
		fmt: String, apply: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 44)              # fat enough for a thumb
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var out := Label.new()
	out.text = fmt % value
	out.custom_minimum_size = Vector2(110, 0)
	out.add_theme_font_size_override("font_size", 20)
	row.add_child(out)
	slider.value_changed.connect(func(v: float):
		apply.call(v)
		out.text = fmt % v)
	return slider


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if get_viewport().get_visible_rect().size != _fitted_size:   # browsers resize the canvas late
		_on_resized()
	var dt := minf(delta, 0.05)
	for ai in ais:
		ai.think(sim, dt)
	if scenario != "":
		_run_scenario()
	sim.step(dt)
	hordes.sync(sim, HUMAN)
	for n in sim.nodes:
		var label: Label3D = vis[n["id"]]["label"]
		var owner: String = n["owner"]
		label.modulate = Rules.SEATS[owner] if owner != "" else Rules.NEUTRAL
		label.text = "" if owner != "" and owner != HUMAN else str(int(n["units"]))   # no numbers on enemy nodes
	hud_time.text = "%d:%02d" % [int(sim.time) / 60, int(sim.time) % 60]
	_trace_t += dt
	if _trace_t >= 2.0:
		_trace_t = 0.0
		var sample := {"t": sim.time}
		for s in ["A", "B"]:
			sample[s] = sim.seat_strength(s)
		trace.append(sample)
	if not shots.is_empty() and sim.time >= shots[0]:
		_take_shot(shots.pop_front(), shots.is_empty())


func _take_shot(t: float, last: bool) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%05.1f.png" % [shot_dir if shot_dir != "" else OS.get_user_data_dir(), t]
	img.save_png(path)
	print("screenshot ", path)
	if last:
		print("telemetry ", Telemetry.save(sim, map.get("code", ""), trace))
		get_tree().quit()


func _on_captured(node_id: int, new_owner: String, _old: String) -> void:
	MapBuilder.apply_owner(vis[node_id]["parts"], new_owner)


func _on_finished(winner: String) -> void:
	var path := Telemetry.save(sim, map.get("code", ""), trace)
	print("match over, winner ", winner, " - telemetry ", path)
	(end_panel.get_node("VBoxContainer/Result") as Label).text = \
			("You win!" if winner == HUMAN else "Seat %s wins" % winner) + "\n%d:%02d" % [int(sim.time) / 60, int(sim.time) % 60]
	end_panel.visible = true


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	# two fingers: pinch to zoom, move together to pan (a second finger cancels a send-drag)
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			touches[st.index] = st.position
		else:
			touches.erase(st.index)
		if touches.size() == 2:
			drag_from = -1
			pan_from = Vector3.INF
			drag_mesh.clear_surfaces()
			var p: Array = touches.values()
			pinch_dist = (p[0] as Vector2).distance_to(p[1])
		return
	if event is InputEventScreenDrag and touches.size() == 2:
		var sd := event as InputEventScreenDrag
		var before: Array = touches.values()
		var mid_before: Vector2 = (before[0] + before[1]) / 2.0
		touches[sd.index] = sd.position
		var p: Array = touches.values()
		var d := (p[0] as Vector2).distance_to(p[1])
		if pinch_dist > 0.0 and d > 0.0:
			cam_dist = clampf(cam_dist * pinch_dist / d, 25.0, 300.0)
		pinch_dist = d
		var g0 := _ground(mid_before)
		var g1 := _ground((p[0] + p[1]) / 2.0)
		if g0 != Vector3.INF and g1 != Vector3.INF:
			cam_target += g0 - g1
		_place_camera()
		return
	if touches.size() >= 2:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clampf(cam_dist * (0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 25.0, 300.0)
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _ground(mb.position)
			if mb.pressed:
				var n := _node_at(hit)
				if n >= 0 and sim.nodes[n]["owner"] == HUMAN:
					drag_from = n
				else:
					pan_from = hit
			else:
				if drag_from >= 0:
					var target := _node_at(hit)
					if target >= 0 and target != drag_from:
						sim.send(drag_from, target, fraction)
				drag_from = -1
				pan_from = Vector3.INF
				drag_mesh.clear_surfaces()
	elif event is InputEventMouseMotion:
		var hit := _ground((event as InputEventMouseMotion).position)
		if drag_from >= 0:
			_draw_drag(sim.nodes[drag_from]["pos"], hit)
		elif pan_from != Vector3.INF:
			cam_target += pan_from - hit
			_place_camera()
	elif event is InputEventMagnifyGesture:
		cam_dist = clampf(cam_dist / (event as InputEventMagnifyGesture).factor, 25.0, 300.0)
		_place_camera()


func _ground(screen: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	return o + d * (-o.y / d.y)


func _node_at(p: Vector3) -> int:
	if p == Vector3.INF:
		return -1
	for n in sim.nodes:
		if (n["pos"] as Vector3).distance_to(p) <= Rules.R + 1.0:
			return n["id"]
	return -1


func _draw_drag(a: Vector3, b: Vector3) -> void:
	drag_mesh.clear_surfaces()
	if b == Vector3.INF:
		return
	drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, Mats.line(HUMAN))
	var up := Vector3(0, 1.0, 0)
	for k in range(-2, 3):                            # a few parallel lines read as a thick stroke
		var off := (b - a).cross(Vector3.UP).normalized() * 0.08 * k
		drag_mesh.surface_add_vertex(a + up + off)
		drag_mesh.surface_add_vertex(b + up + off)
	drag_mesh.surface_end()
