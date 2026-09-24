extends Node3D
## Ooze Syndicate 2.0 - Alpha 12. World, camera, input and orchestration; the interface lives in
## hud.gd, in-world effects in fx.gd, hordes in horde_view.gd, rules in sim.gd.
## Drag from one of your nodes to any node to send; tap a node to inspect; double-tap your own node
## to upgrade (Alpha 11 convention); the inspector offers costed actions and the relay's switch.
## Command-line user args (after `--`):
##   --map=res://maps/004-two-piers.json   map to load (skips the title screen)
##   --demo                                 both seats played by the AI
##   --ai=Casual|Standard|Veteran           AI level (title screen picks it otherwise)
##   --shots=4,12,25 --out=<dir>            save screenshots at those match times, then quit
##   --window=2340x1080                      size the window like a phone (landscape) for testing
##   --mobile                               force the phone quality profile on desktop
##   --scenario=fight|rear|queue             stage a contact on the deck between nodes 1 and 0
##   --seed=N                               deterministic Last Stand method / chaos order

const HUMAN := "A"
var SEAT_FACTIONS := {"A": "null", "B": "ember", "C": "bloom", "D": "vex", "E": "solar"}
const FACTION_NAMES := ["vex", "null", "bloom", "ember", "solar"]
const STARTER_MAPS := [
	"res://maps/004-two-piers.json", "res://maps/007-long-span.json",
	"res://maps/008-strait.json", "res://maps/010-first-switch.json",
	"res://maps/011-remote-span.json", "res://maps/061-switchback-foundry.json",
	"res://maps/047-trident-exchange.json",
]
const PROVES := {
	"004": "drag-to-send, capture, the horde line", "007": "bridge combat, tier reading, inward vs outward",
	"008": "RETRACT: troops carried into the hub", "010": "SWITCH: the deck dissolves - troops fall",
	"011": "REMOTE: the centre console swaps the diagonals", "061": "3-WAY ROTATION: troops ride the deck",
	"047": "team layout, retract on both spine decks",
}
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")

var map: Dictionary
var map_path := "res://maps/004-two-piers.json"
var sim := Sim.new()
var ais: Array = []
var vis: Dictionary
var hordes: HordeView
var fx: Fx
var hud: Hud
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_dist := 90.0
var cam_yaw := 0.0
var fraction := 0.5
var drag_from := -1
var selected := -1
var pan_from := Vector3.INF
var drag_mesh := ImmediateMesh.new()
var drag_line := MeshInstance3D.new()
var route_label: Label3D
var trace: Array = []
var _trace_t := 0.0
var shots: Array = []
var shot_dir := ""
var demo := false
var ai_level := "Standard"
var seed_value := -1
var paused := false
var scenario := ""
var scenario_focus := Vector3.INF
var scenario_zoom := 30.0
var _scenario_done := false
var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
var window_size := Vector2i.ZERO
var sun: DirectionalLight3D
var touches := {}
var pinch_dist := 0.0
var margins := Vector4(16, 12, 16, 12)
var _fitted_size := Vector2.ZERO
var _tap_node := -1
var _tap_time := 0.0
var _press_pos := Vector2.ZERO
var _press_time := 0.0
const DOUBLE_TAP_WINDOW := 0.35
const TAP_PIXELS := 14.0
var started := false
var menu_layer: CanvasLayer
static var relaunch := {}                     # survives a scene reload: Play again / Main menu


func _ready() -> void:
	var map_explicit := false
	if relaunch.has("faction"):
		SEAT_FACTIONS[HUMAN] = relaunch["faction"]
		ai_level = relaunch.get("ai", ai_level)
	if relaunch.has("map"):
		map_path = relaunch["map"]
		map_explicit = true
	relaunch = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_path = arg.substr(6)
			map_explicit = true
		elif arg == "--demo":
			demo = true
		elif arg.begins_with("--ai="):
			ai_level = arg.substr(5)
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
		elif arg.begins_with("--zoom="):
			scenario_zoom = float(arg.substr(7))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	if window_size != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
	if map_explicit or demo or scenario != "" or not shots.is_empty():
		_start_map(map_path)
	else:
		_build_map_menu()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--menu-shot="):           # screenshot the title screen, then quit
				var out := arg.substr(12)
				for i in range(20):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out)
				print("screenshot ", out)
				get_tree().quit()


func _start_map(path: String) -> void:
	map_path = path
	map = MapBuilder.load_map(path)
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	sim = Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, SEAT_FACTIONS, seed_value)
	_build_world()
	vis = MapBuilder.build(self, sim)
	if not vis["stretched"].is_empty():
		push_warning("edges stretched to fit (not honest): %s" % [vis["stretched"]])
	hordes = HordeView.new()
	add_child(hordes)
	fx = Fx.new()
	add_child(fx)
	fx.setup(self, sim, vis, hordes)
	drag_line.mesh = drag_mesh
	add_child(drag_line)
	route_label = Label3D.new()
	route_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	route_label.pixel_size = 0.018
	route_label.font_size = 72
	route_label.outline_size = 18
	route_label.no_depth_test = true
	route_label.modulate = Rules.seat_color(HUMAN)
	route_label.visible = false
	add_child(route_label)
	for seat in seats.values():
		if (seat != HUMAN or demo) and scenario == "":
			ais.append(SeatAI.new(seat, 2.5, ai_level))
	if scenario != "":
		_stage_scenario()
	sim.captured.connect(_on_captured)
	sim.finished.connect(_on_finished)
	for n in sim.nodes:
		vis[n["id"]]["model_key"] = MapBuilder.model_for(n)
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_apply_quality()
	get_viewport().size_changed.connect(_on_resized)
	started = true
	paused = false
	await get_tree().process_frame
	_on_resized()
	hud.toast("%s - you are seat %s (%s). Drag from your node to send." % [map.get("name", ""), HUMAN, str(SEAT_FACTIONS[HUMAN]).to_upper()])


func restart() -> void:
	relaunch = {"map": map_path, "faction": SEAT_FACTIONS[HUMAN], "ai": ai_level}
	get_tree().reload_current_scene()


func to_menu() -> void:
	relaunch = {"faction": SEAT_FACTIONS[HUMAN], "ai": ai_level}
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ title screen
static func panel_style(color: Color = Color("276578")) -> StyleBoxFlat:
	return Hud.panel_style(color)


func style_button(b: Button, accent: Color, width: float = 130.0, height: float = 78.0) -> void:
	b.add_theme_font_override("font", UI_FONT)
	b.custom_minimum_size = Vector2(width, height)
	b.add_theme_stylebox_override("normal", panel_style())
	b.add_theme_stylebox_override("hover", panel_style(accent))
	var pressed := panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", panel_style(Color("3a4650")))
	b.add_theme_color_override("font_disabled_color", Color("a6b2bb"))


func _build_map_menu() -> void:
	## Title screen: faction (with blurb), AI level, then one of the starter seven with its map
	## preview and what it proves (Docs STARTER-SEVEN.md).
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.01, 0.014)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_layer.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	centre.add_child(root)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/Ooze-Syndicate-Logo.svg")
	logo.custom_minimum_size = Vector2(0, 90)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(logo)
	var title := Label.new()
	title.add_theme_font_override("font", UI_FONT)
	title.text = "OOZE SYNDICATE 2.0  ·  %s  ·  v%s" % [Rules.VERSION_NAME.to_upper(), Rules.VERSION]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)
	var blurb := Label.new()
	blurb.add_theme_font_override("font", UI_FONT)
	blurb.text = Rules.FACTION_BLURB[SEAT_FACTIONS[HUMAN]]
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 17)
	blurb.modulate = Color(1, 1, 1, 0.75)
	var faction_row := HBoxContainer.new()
	faction_row.alignment = BoxContainer.ALIGNMENT_CENTER
	faction_row.add_theme_constant_override("separation", 8)
	root.add_child(faction_row)
	for faction in FACTION_NAMES:
		var accent: Color = Rules.FACTIONS[faction][1]
		var fb := Button.new()
		fb.text = faction.to_upper()
		fb.icon = load("res://assets/ui/%s.svg" % faction)
		fb.expand_icon = true
		fb.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		style_button(fb, accent, 150, 58)
		fb.add_theme_font_size_override("font_size", 20)
		if faction == SEAT_FACTIONS[HUMAN]:
			fb.add_theme_stylebox_override("normal", panel_style(accent))
		fb.pressed.connect(func():
			SEAT_FACTIONS[HUMAN] = faction
			blurb.text = Rules.FACTION_BLURB[faction]
			for c in faction_row.get_children():
				(c as Button).add_theme_stylebox_override("normal", panel_style())
			fb.add_theme_stylebox_override("normal", panel_style(accent)))
		faction_row.add_child(fb)
	root.add_child(blurb)
	var ai_row := HBoxContainer.new()
	ai_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ai_row.add_theme_constant_override("separation", 8)
	root.add_child(ai_row)
	var ai_label := Label.new()
	ai_label.add_theme_font_override("font", UI_FONT)
	ai_label.text = "OPPONENT "
	ai_label.add_theme_font_size_override("font_size", 20)
	ai_row.add_child(ai_label)
	for level in Rules.AI_LEVELS.keys():
		var lb := Button.new()
		lb.text = level.to_upper()
		style_button(lb, Color("2ee6ff"), 130, 50)
		lb.add_theme_font_size_override("font_size", 18)
		if level == ai_level:
			lb.add_theme_stylebox_override("normal", panel_style(Color("2ee6ff")))
		lb.pressed.connect(func():
			ai_level = level
			for c in ai_row.get_children():
				if c is Button:
					(c as Button).add_theme_stylebox_override("normal", panel_style())
			lb.add_theme_stylebox_override("normal", panel_style(Color("2ee6ff"))))
		ai_row.add_child(lb)
	var grid := GridContainer.new()
	grid.columns = 2 if get_viewport().get_visible_rect().size.x > 900 else 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)
	for mp in STARTER_MAPS:
		var m := MapBuilder.load_map(mp)
		var relays := {}
		for n in m["nodes"]:
			if n.get("relay") != null:
				relays[n["relay"]] = true
		var b := Button.new()
		var code: String = m.get("code", "?")
		b.text = "%s  %s\n%d nodes%s\n%s" % [code, str(m.get("name", mp)).replace("*", ""), m["nodes"].size(),
				("  ·  " + "/".join(relays.keys())) if not relays.is_empty() else "", PROVES.get(code, "")]
		b.icon = load(mp.replace("maps/", "assets/maps/").replace(".json", ".svg"))
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		style_button(b, Color("2ee6ff"), 470, 96)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			menu_layer.queue_free()
			menu_layer = null
			_start_map(mp))
		grid.add_child(b)
	var version := Label.new()
	version.text = "v%s %s  ·  reload twice after a new publish (PWA cache)" % [Rules.VERSION, Rules.VERSION_NAME]
	version.add_theme_font_size_override("font_size", 13)
	version.modulate = Color(1, 1, 1, 0.45)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(version)


# ------------------------------------------------------------------ world
func _apply_quality() -> void:
	Engine.max_fps = 60
	if mobile:
		sun.shadow_enabled = false
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED


func _on_resized() -> void:
	if not started:
		return
	var vp := get_viewport().get_visible_rect().size
	_fitted_size = vp
	_apply_safe_area()
	hud.layout(vp, margins)
	_fit_camera()


func _apply_safe_area() -> void:
	var vp := get_viewport().get_visible_rect().size
	var left := 16.0
	var right := 16.0
	var top := 10.0
	if OS.has_feature("mobile"):
		var screen := Vector2(DisplayServer.screen_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.screen_get_position())
		var k := vp.x / maxf(screen.x, 1.0)
		left = maxf(safe.position.x * k, left)
		right = maxf((screen.x - safe.end.x) * k, right)
		top = maxf(safe.position.y * k, top)
	if mobile:
		left = maxf(left, vp.x * 0.035)
		right = maxf(right, vp.x * 0.035)
	margins = Vector4(left, top, right, 12.0)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.014)
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
	cam_yaw = PI / 2.0 if ext.z > ext.x else 0.0
	# fit the map into the screen area left of the side panel and between the top bar and the
	# ability dock, then centre it there
	var vp := get_viewport().get_visible_rect().size
	var half_h := tan(hfov_half(vp))
	var half_v := tan(deg_to_rad(cam.fov) / 2.0)
	var panel := hud.side_panel_width() + margins.z + 20.0 if hud else 0.0
	var top_used := hud.top_used() if hud else 0.0
	var bottom_used := hud.bottom_used() if hud else 0.0
	var free_x := clampf((vp.x - panel - margins.x) / vp.x, 0.5, 1.0)
	var free_y := clampf((vp.y - top_used - bottom_used) / vp.y, 0.4, 1.0)
	var along := (ext.x if cam_yaw == 0.0 else ext.z) + 2.0 * Rules.R + 4.0      # screen-horizontal
	var across := ((ext.z if cam_yaw == 0.0 else ext.x) + 2.0 * Rules.R + 2.0) * sin(deg_to_rad(55.0))
	var dist_x := (along / 2.0) / (half_h * free_x)
	var dist_y := (across / 2.0) / (half_v * free_y) * 0.9   # the far half foreshortens more than the near
	cam_dist = maxf(dist_x, dist_y) * 1.02
	_place_camera()
	var screen_right := cam.global_transform.basis.x
	var shift := cam_dist * half_h * ((panel - margins.x) / vp.x)
	cam_target += screen_right * shift
	var screen_up := Vector3(0, 0, -1).rotated(Vector3.UP, cam_yaw)            # map-plane direction that reads as "up"
	var vshift := cam_dist * half_v * ((bottom_used - top_used) / vp.y) / sin(deg_to_rad(55.0))
	cam_target += screen_up * vshift
	if scenario_focus != Vector3.INF:
		cam_target = scenario_focus
		cam_dist = scenario_zoom
	_place_camera()


func _stage_scenario() -> void:
	## Staged situations for looking at one thing up close (no AI). fight/rear/queue: contacts on
	## the deck between nodes 1 and 0 (Two Piers). build: A owns node 1 with units to spend
	## (Strait: relay node -> cannon). switch: A's horde crosses node 1's switch deck on First Switch
	## while A fires it. rotate: A rides the Switchback hub deck. inspect: opens node 1's inspector.
	match scenario:
		"build", "inspect":
			sim.nodes[1]["owner"] = "A"
			sim.nodes[1]["units"] = 300.0
			scenario_focus = sim.nodes[1]["pos"]
		"switch":
			sim.nodes[1]["owner"] = "A"
			sim.nodes[1]["units"] = 60.0
			sim.nodes[5]["units"] = 200.0
			scenario_focus = (sim.nodes[1]["pos"] + sim.nodes[0]["pos"]) / 2.0
		"rotate":
			sim.nodes[0]["owner"] = "A"
			sim.nodes[1]["owner"] = "A"
			sim.nodes[1]["units"] = 200.0
			scenario_focus = sim.nodes[0]["pos"]
		_:
			sim.nodes[1]["owner"] = "A"
			sim.nodes[1]["units"] = 160.0
			sim.nodes[0]["owner"] = "B" if scenario == "fight" else "A"
			sim.nodes[0]["units"] = 160.0
			if scenario == "rear":
				sim.nodes[3]["owner"] = "B"
				sim.nodes[3]["units"] = 200.0
			scenario_focus = (sim.nodes[1]["pos"] + sim.nodes[0]["pos"]) / 2.0
	for n in sim.nodes:
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])


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
				var slow := sim.send(1, 0, 0.5)
				slow["speed"] = 0.2
			elif sim.time > 2.5:
				sim.send(3, 0, 1.0)
				_scenario_done = true
		"queue":
			if sim.hordes.is_empty():
				var slow := sim.send(1, 0, 0.3)
				slow["speed"] = 0.25
			elif sim.time > 2.0:
				sim.send(1, 0, 1.0)
				_scenario_done = true
		"build":
			sim.build_attachment(1, "cannon")
			_scenario_done = true
		"inspect":
			selected = 1
			hud.inspect(1, cam)
			_scenario_done = true
		"switch":
			if sim.hordes.is_empty():
				sim.send(5, 0, 1.0)
			elif sim.time > 5.0:
				sim.fire_relay(1)
				_scenario_done = true
		"rotate":
			if sim.hordes.is_empty():
				sim.send(1, 0, 1.0)
			elif sim.time > 3.0:
				sim.fire_relay(0)
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


# ------------------------------------------------------------------ node actions (HUD -> sim)
func node_action(method: String, id: int) -> bool:
	## Every tap gives feedback (Alpha 11): what happened, or why it couldn't.
	var n: Dictionary = sim.nodes[id]
	var ok := false
	match method:
		"switch":
			ok = sim.fire_relay(id)
			if ok:
				hud.toast("Relay fired - switching in %d s, then %d s cooldown" % [int(Rules.RELAY_WARNING), int(Rules.RELAY_COOLDOWN)])
			else:
				hud.toast("Relay on cooldown" if n["relay_cd"] > 0.0 else "Relay is already switching")
		"upgrade":
			var cost := sim.upgrade_cost(n)
			ok = sim.upgrade_structure(id)
			if ok:
				hud.toast("Upgrade started - %d units, %d s" % [cost, int(Rules.BUILD_SECONDS)])
			elif n["build_kind"] != "":
				hud.toast("Construction already in progress")
			elif n["attachment"] == "cannon" and n["cannon_tier"] >= 3:
				hud.toast("Cannon is already at max tier")
			elif n["attachment"] == "forge":
				hud.toast("A forge has no further tier")
			elif n["tier"] >= 4:
				hud.toast("Vat is already at max tier")
			elif n["units"] < cost:
				hud.toast("Upgrade needs %d units (%d here)" % [cost, int(n["units"])])
			else:
				hud.toast("Nothing to upgrade here")
		"build_cannon", "build_forge":
			var kind := method.substr(6)
			var cost: int = Rules.CANNON_COST[1] if kind == "cannon" else Rules.FORGE_COST
			ok = sim.build_attachment(id, kind)
			if ok:
				hud.toast("%s construction started - %d units, %d s" % [kind.capitalize(), cost, int(Rules.BUILD_SECONDS)])
			elif n["build_kind"] != "":
				hud.toast("Construction already in progress")
			elif n["swap_cd"] > 0.0:
				hud.toast("Attachment swap ready in %d s" % int(ceil(n["swap_cd"])))
			elif n["units"] < cost:
				hud.toast("%s needs %d units (%d here)" % [kind.capitalize(), cost, int(n["units"])])
			else:
				hud.toast("Can't build a %s here" % kind)
		"restore":
			ok = sim.restore_vat(id)
			hud.toast("Restoring the vat - %d s" % int(Rules.BUILD_SECONDS) if ok else "Can't restore the vat now")
	return ok


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if not started:
		return
	if get_viewport().get_visible_rect().size != _fitted_size:
		_on_resized()
	var dt := minf(delta, 0.05)
	if not paused:
		for ai in ais:
			ai.think(sim, dt)
		if scenario != "":
			_run_scenario()
		sim.step(dt)
	hordes.sync(sim, HUMAN)
	for n in sim.nodes:
		var entry: Dictionary = vis[n["id"]]
		if sim.collapsed.get(n["id"], false):
			continue
		var model := MapBuilder.model_for(n)
		if entry["model_key"] != model:
			MapBuilder.set_centre_model(self, entry, model, n["pos"], n["owner"])
	for ev in sim.fx_events:
		fx.handle(ev)
		match ev["type"]:
			"last_stand":
				var how := {"inward": "the rim falls first - hold the centre", "outward": "the centre falls first - hold the rim",
						"chaos": "nodes fall in a hidden order - your home last"}
				hud.show_banner("LAST STAND - %s\n%s" % [str(ev["method"]).to_upper(), how.get(ev["method"], "")], 5.0)
			"collapse_warning":
				var n: Dictionary = sim.nodes[ev["node"]]
				if n["owner"] == HUMAN:
					hud.toast("Your node %d falls in %d s - get out!" % [ev["node"], int(Rules.LAST_STAND_WARNING)])
			"shield_break":
				var n: Dictionary = sim.nodes[ev["node"]]
				if n["owner"] == HUMAN:
					hud.toast("Shield broken at node %d - the bond is down until it regenerates" % ev["node"])
			"relay_tick":
				var n: Dictionary = sim.nodes[ev["node"]]
				if n["owner"] == HUMAN:
					hud.toast("Relay %d switches now" % ev["node"])
	sim.fx_events.clear()
	fx.selected = selected if drag_from < 0 else drag_from
	fx.sync(dt)
	hud.sync(dt, cam)
	_trace_t += dt
	if _trace_t >= 2.0:
		_trace_t = 0.0
		var sample := {"t": sim.time}
		for s in sim.factions.keys():
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
	if new_owner == HUMAN:
		hud.toast("Node %d captured" % node_id)
	elif _old == HUMAN:
		hud.toast("Node %d lost to seat %s" % [node_id, new_owner])


func _on_finished(winner: String) -> void:
	var path := Telemetry.save(sim, map.get("code", ""), trace)
	print("match over, winner ", winner, " - telemetry ", path)
	hud.close_inspector()
	hud.show_end(winner)
	if not shots.is_empty():                              # automated run: the match ended before the
		var t: float = shots[-1]                          # last shot time - take it now and quit
		shots.clear()
		_take_shot(t, true)


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not started or paused:
		return
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
			route_label.visible = false
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
			if hud.pointer_over_ui(mb.position):
				return
			var hit := _ground(mb.position)
			if mb.pressed:
				var n := _node_at(hit, mb.position)
				_press_pos = mb.position
				_press_time = Time.get_ticks_msec() / 1000.0
				if n >= 0:
					if sim.nodes[n]["owner"] == HUMAN and n == _tap_node and _press_time - _tap_time < DOUBLE_TAP_WINDOW:
						hud.close_inspector()
						node_action("upgrade", n)               # double-tap (Alpha 11): upgrade what's there
						_tap_node = -1
						return
					_tap_time = _press_time
					_tap_node = n
					if sim.nodes[n]["owner"] == HUMAN:
						drag_from = n
					else:
						selected = n
				else:
					hud.close_inspector()
					selected = -1
					pan_from = hit
			else:
				if drag_from >= 0:
					var target := _node_at(hit, mb.position)
					var moved := (mb.position - _press_pos).length() >= TAP_PIXELS
					if target >= 0 and target != drag_from and moved:
						var count := int(floorf(sim.nodes[drag_from]["units"] * fraction))
						var h := sim.send(drag_from, target, fraction)
						if h.is_empty():
							hud.toast("No route to that node" if count > 0 else "No units to send")
						else:
							hud.toast("Sending %d units to node %d" % [count, target])
							fx._pulse(sim.nodes[target]["pos"], Rules.seat_color(HUMAN), Rules.R, 0.6)
						hud.close_inspector()
						selected = drag_from
					elif not moved:
						selected = drag_from
						hud.inspect(drag_from, cam)               # single tap: the ring inspector
				else:
					var target := _node_at(hit, mb.position)
					if target >= 0 and (mb.position - _press_pos).length() < TAP_PIXELS:
						selected = target
						hud.inspect(target, cam)
				drag_from = -1
				pan_from = Vector3.INF
				drag_mesh.clear_surfaces()
				route_label.visible = false
	elif event is InputEventMouseMotion:
		var hit := _ground((event as InputEventMouseMotion).position)
		if drag_from >= 0:
			_draw_drag(drag_from, hit, (event as InputEventMouseMotion).position)
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


func _node_at(p: Vector3, screen: Vector2 = Vector2(-1, -1)) -> int:
	if screen.x >= 0.0 and hud:
		var b := hud.badge_at(screen)
		if b >= 0:
			return b
	if p == Vector3.INF:
		return -1
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false):
			continue
		if (n["pos"] as Vector3).distance_to(p) <= Rules.R + (2.5 if mobile else 1.0):
			return n["id"]
	return -1


func _draw_drag(from: int, b: Vector3, screen: Vector2) -> void:
	## The send preview follows the actual route along the decks (not a straight line), with an
	## arrowhead at the target and the count + travel time at the cursor (Alpha 11's route label).
	drag_mesh.clear_surfaces()
	route_label.visible = false
	if b == Vector3.INF:
		return
	var a: Vector3 = sim.nodes[from]["pos"]
	var target := _node_at(b, screen)
	var up := Vector3(0, 1.0, 0)
	var mat := Mats.line(HUMAN)
	var count := int(floorf(sim.nodes[from]["units"] * fraction))
	if target >= 0 and target != from:
		var route := sim.find_route(from, target)
		if route.is_empty():
			drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, Mats.glow(Rules.state_color("warn")))
			drag_mesh.surface_add_vertex(a + up)
			drag_mesh.surface_add_vertex(sim.nodes[target]["pos"] + up)
			drag_mesh.surface_end()
			route_label.text = "NO ROUTE"
			route_label.position = sim.nodes[target]["pos"] + Vector3(0, 6, 0)
			route_label.visible = true
			return
		var path := sim.build_path(route)
		var pts: PackedVector3Array = path["pts"]
		var seconds := 0.0
		for i in range(route.size() - 1):
			seconds += sim.edges[sim._edge_index(route[i], route[i + 1])]["modules"] * Rules.MODULE_SECONDS + 1.0
		drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for k in range(-1, 2):
			for i in range(pts.size() - 1):
				var d := (pts[i + 1] - pts[i]).normalized()
				var off := d.cross(Vector3.UP) * 0.12 * k
				drag_mesh.surface_add_vertex(pts[i] + up + off)
				drag_mesh.surface_add_vertex(pts[i + 1] + up + off)
		var tip: Vector3 = pts[-1] + up
		var dir := (pts[-1] - pts[-2]).normalized()
		var side := dir.cross(Vector3.UP)
		for s in [-1.0, 1.0]:
			drag_mesh.surface_add_vertex(tip)
			drag_mesh.surface_add_vertex(tip - dir * 1.6 + side * 0.9 * s)
		drag_mesh.surface_end()
		var tn: Dictionary = sim.nodes[target]
		var verb := "reinforce" if tn["owner"] == HUMAN else ("attack" if tn["owner"] != "" else "take")
		route_label.text = "%s · %d units · %d s" % [verb.to_upper(), count, int(round(seconds))]
		route_label.position = tn["pos"] + Vector3(0, 6.5, 0)
		route_label.visible = true
	else:
		drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for k in range(-1, 2):
			var off := (b - a).cross(Vector3.UP).normalized() * 0.1 * k
			drag_mesh.surface_add_vertex(a + up + off)
			drag_mesh.surface_add_vertex(b + up + off)
		drag_mesh.surface_end()
