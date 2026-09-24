extends Node3D
## Ooze Syndicate 2.0 prototype: Two Piers (starter map 1).
## Drag from one of your nodes to any node to send; the buttons set 25/50/75/100 %.
## Command-line user args (after `--`):
##   --map=res://maps/004-two-piers.json   map to load
##   --demo                                 both seats played by the AI
##   --shots=4,12,25 --out=<dir>            save screenshots at those match times, then quit

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
		if seat != HUMAN or demo:
			ais.append(SeatAI.new(seat, 2.5 if seat != HUMAN else 3.1))
	sim.captured.connect(_on_captured)
	sim.finished.connect(_on_finished)
	for n in sim.nodes:
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
	_build_hud()
	_fit_camera()


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
	var sun := DirectionalLight3D.new()
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
	var vp := get_viewport().get_visible_rect().size
	var hfov := 2.0 * atan(tan(deg_to_rad(cam.fov) / 2.0) * vp.x / vp.y)
	var long_side := maxf(ext.x, ext.z) + 2.0 * Rules.R + 8.0     # whole platforms plus a margin
	cam_dist = (long_side / 2.0) / tan(hfov / 2.0) * 1.08
	_place_camera()


func _place_camera() -> void:
	var pitch := deg_to_rad(55.0)
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, cam_yaw)
	cam.position = cam_target + back * cam_dist
	cam.look_at(cam_target, Vector3.UP)


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	layer.add_child(top)
	hud_time = Label.new()
	hud_time.add_theme_font_size_override("font_size", 28)
	top.add_child(hud_time)
	hud_info = Label.new()
	hud_info.add_theme_font_size_override("font_size", 20)
	hud_info.text = "   Two Piers  -  you are seat A (cyan)  -  drag from your node to send"
	top.add_child(hud_info)
	var side := VBoxContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.5
	side.anchor_bottom = 0.5
	side.offset_left = -130
	side.offset_top = -150
	layer.add_child(side)
	var group := ButtonGroup.new()
	for f in Rules.SEND_FRACTIONS:
		var b := Button.new()
		b.text = "%d%%" % int(f * 100)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(110, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.button_pressed = is_equal_approx(f, fraction)
		b.pressed.connect(func(): fraction = f)
		side.add_child(b)
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


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for ai in ais:
		ai.think(sim, dt)
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
