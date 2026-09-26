extends Node3D
## Ooze Syndicate 2.0 (version: Rules.VERSION / VERSION_NAME). World, camera, input and orchestration;
## the interface lives in hud.gd, in-world effects in fx.gd (fights, tier-downs and the cannon laser in
## combat_fx.gd), hordes in horde_view.gd, rules in sim.gd.
## Drag from one of your nodes to any node to send; tap a node to inspect; double-tap your own node
## to upgrade (Alpha 11 convention); the inspector offers costed actions and the relay's switch.
## Command-line user args (after `--`):
##   --map=res://maps4/T-01-first-steps.json  map to load (skips the title screen)
##   --mode=1v1|2v2|3v3|2v2v2|FFA3|FFA4|FFA5  match mode (the map's first mode if it lacks this one)
##   --demo                                 every seat played by the AI
##   --ai=Training|Casual|Standard|Veteran|Expert  AI level (Rules.AI_LEVELS; the menu picks it otherwise)
##   --brawl (alias --classic)              BRAWL: bridge combat off, Alpha 11 rules
##   --seed=N                               deterministic Last Stand method / chaos order
##   --shots=4,12,25 --out=<dir>            save screenshots at those match times, then quit
##   --perf                                 print frame timing every 3 s
##   --window=2340x1080                      size the window like a phone (landscape) for testing
##   --mobile                               force the phone quality profile on desktop
##   --pitch=58                              camera pitch in degrees above the horizon (MapCamera's per-map pitch otherwise)
##   --thumb=<png>                          render the map's menu thumbnail (no HUD), then quit
##   --menu-page=<page> --menu-shot=<png>   open a menu page / screenshot the menu, then quit
##   --scenario=fight|rear|queue|build|inspect|switch|rotate --zoom=N  stage one situation up close

var HUMAN := "A"                                  # your seat: always A offline, host-assigned online
var online := false                               # this match is a peer-to-peer room (Net)
var SEAT_FACTIONS := {"A": "null", "B": "ember", "C": "bloom", "D": "vex", "E": "solar"}
const FACTION_NAMES := ["vex", "null", "bloom", "ember", "solar"]

var map: Dictionary
var map_path := "res://maps4/T-01-first-steps.json"
var sim := Sim.new()
var ais: Array = []
var vis: Dictionary
var hordes: HordeView
var fx: Fx
var combat: CombatFx                               # fights for a tower, conquest tier-downs, the cannon laser
var forge_pulse: ForgePulse                        # a forge coming online: the owner's 2 s power-up wave
var scenery: Scenery
var hud: Hud
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_dist := 90.0
var cam_pitch: float = Rules.CAM_PITCH              # degrees above the horizon: MapCamera's per-map pitch
var _base_pitch: float = Rules.CAM_PITCH            # the start view's pitch (the Last Stand zoom lowers cam_pitch)
var pitch_forced := false                          # --pitch=N (or the phone-fit probe) overrides it
var cam_yaw := 0.0
var _start_fit := []                              # [cam_target, cam_dist] of the whole-map fit (_fit_camera)
var _gone_seen := 0                               # Last Stand: nodes collapsed at the last check
var _gone_wait := 0.0                             # seconds left before the camera re-fits (the fall plays first)
var _fit_gone := 0                                # collapsed count the camera is fitted to (0 = the whole map)
var _zoom_from := []
var _zoom_to := []
var _zoom_t := -1.0                               # 0..1 through the ease, < 0 when still
const COLLAPSE_ZOOM_DELAY := 1.0                  # the platforms' fall first (fx._collapse, ~1.5 s)
const COLLAPSE_ZOOM_SECONDS := 1.5
const COLLAPSE_ZOOM_MAX := 2.5                    # never closer than 1/2.5 of the start distance
const COLLAPSE_PITCH_DROP := 14.0                 # degrees the pitch lowers by once almost every node has fallen
const COLLAPSE_PITCH_MIN := 44.0                  # never flatter than this
var fraction := 0.5
var drag_from := -1
var selected := -1
var drag_mesh := ImmediateMesh.new()
var drag_line: MeshInstance3D                     # made in _start_map: a menu-only run never parents it
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
var margins := Vector4(16, 12, 16, 12)
var _fitted_size := Vector2.ZERO
var _tap_node := -1
var _tap_time := 0.0
var _press_pos := Vector2.ZERO
var _press_time := 0.0
const DOUBLE_TAP_WINDOW := 0.35
const TAP_PIXELS := 14.0
var started := false
var thumb_path := ""
var perf_on := "--perf" in OS.get_cmdline_user_args()   # debug flag, read once
var _pending_inspect := -1                    # single tap: inspector opens after the double-tap window
var _pending_at := 0.0
var _swallow_release := false
var mode := "1v1"                             # 1v1 / 2v2 / 3v3 / 2v2v2 / FFA3-5 (the map's seats key)
var color_choice := "A"                       # your ownership colour: palette key or "faction"
var menu_layer: CanvasLayer
static var relaunch := {}                     # survives a scene reload: Play again / Main menu


func _ready() -> void:
	var map_explicit := false
	if FullscreenGate.needed():                        # phones play fullscreen (Alpha 14 playtest)
		add_child(FullscreenGate.new())
	Engine.max_fps = 60                                # never spin faster than the screen (menu included)
	if Net.online():                                   # a room launched (or relaunched) a round
		_start_online()
		return
	if relaunch.has("faction"):
		SEAT_FACTIONS[HUMAN] = relaunch["faction"]
		ai_level = relaunch.get("ai", ai_level)
		if relaunch.has("rival"):
			SEAT_FACTIONS["B"] = relaunch["rival"]
		mode = relaunch.get("mode", mode)
		color_choice = relaunch.get("colour", color_choice)
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
		elif arg.begins_with("--pitch="):
			cam_pitch = float(arg.substr(8))
			pitch_forced = true
		elif arg.begins_with("--scenario="):
			scenario = arg.substr(11)
		elif arg.begins_with("--zoom="):
			scenario_zoom = float(arg.substr(7))
		elif arg.begins_with("--mode="):
			mode = arg.substr(7)
		elif arg == "--classic" or arg == "--brawl":  # BRAWL mode (bridge combat off, Alpha 11 rules)
			Rules.bridge_combat = false
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--thumb="):              # map thumbnail for the menu: no HUD, first frame
			thumb_path = arg.substr(8)
			map_explicit = true
	MapPool.phone = MapPool.phone_screen(mobile)       # Alpha 18: phones get the phone-fit maps only
	if window_size != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
	if map_explicit or demo or scenario != "" or not shots.is_empty():
		_start_map(map_path)
	else:
		if not Net.in_room():                          # the menu, no room: a new build may reload the page
			Net.set_busy(false)
		menu_layer = Menu.new()
		add_child(menu_layer)
		(menu_layer as Menu).setup(self)
		if Net.in_room():                              # back from a round, or a player left: the lobby
			(menu_layer as Menu).show_lobby()
		elif Net.status != "":                         # the room closed: say why on the ONLINE page
			(menu_layer as Menu).show_online()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--menu-page="):            # screenshot helper: open a menu page
				(menu_layer as Menu).call("show_" + arg.substr(12))
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
	Net.set_busy(true)                                 # a match is on: a new build waits for the menu (web)
	map_path = path
	map = MapBuilder.load_map(path)
	if not pitch_forced:                               # Alpha 18: each map's own camera angle (phone-fit probe)
		cam_pitch = MapCamera.pitch_for(str(map.get("code", "")))
	_base_pitch = cam_pitch
	if not map["seats"].has(mode):                     # this map doesn't offer the mode: its first one
		mode = "1v1" if map["seats"].has("1v1") else map["seats"].keys()[0]
	var seats := {}
	var teams := {}
	for s in map["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
		if mode in ["2v2", "3v3", "2v2v2"] and s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	if not HUMAN in seats.values() and not online:     # FFA maps may seat A elsewhere; A is always you
		var first: int = seats.keys()[0]
		seats[first] = HUMAN
	if not online:                                     # online: every seat's faction comes from the room
		var pool := FACTION_NAMES.filter(func(f): return f != SEAT_FACTIONS[HUMAN] and f != SEAT_FACTIONS["B"])
		pool.shuffle()
		for seat in ["C", "D", "E", "F"]:             # extra AI seats get the factions not yet taken
			if not pool.is_empty():
				SEAT_FACTIONS[seat] = pool.pop_front()
	if online and Net.match_info.get("colours") is Dictionary:   # a room: the host's seat colours, the same on every screen
		Rules.use_colours(Net.match_info["colours"])
	else:
		Rules.assign_colors(seats.values(), SEAT_FACTIONS, HUMAN, color_choice, teams)
	sim = Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, SEAT_FACTIONS, seed_value, teams)
	var lo := Vector3(INF, 0, INF)                     # the camera looks along the map's short side
	var hi := Vector3(-INF, 0, -INF)
	for n in sim.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	Rules.view_yaw = PI / 2.0 if (hi - lo).z > (hi - lo).x else 0.0
	_build_world()
	vis = MapBuilder.build3(self, sim, map) if map.has("layout") else MapBuilder.build(self, sim)
	if not vis["stretched"].is_empty():
		push_warning("edges stretched to fit (not honest): %s" % [vis["stretched"]])
	hordes = HordeView.new()
	hordes.vis = vis                                   # the vat models its lines drop out of
	add_child(hordes)
	scenery = Scenery.new()
	add_child(scenery)
	scenery.setup(self, sim, vis)
	fx = Fx.new()
	add_child(fx)
	fx.setup(self, sim, vis, hordes)
	combat = CombatFx.new()
	add_child(combat)
	combat.setup(self, sim, vis, fx)
	forge_pulse = ForgePulse.new()
	add_child(forge_pulse)
	forge_pulse.setup(sim, vis, combat)
	forge_pulse.online.connect(_on_forge_online)
	drag_line = MeshInstance3D.new()
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
		if (seat != HUMAN or demo) and scenario == "" and not online:
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
	if thumb_path != "":
		hud.root.visible = false
		for i in range(40):                           # let the rivers ease in
			await get_tree().process_frame
		paused = true
		for i in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(thumb_path)
		print("thumbnail ", thumb_path)
		get_tree().quit()
		return
	await get_tree().process_frame
	_on_resized()
	if online:
		hud.toast("ROOM %s · ROUND %d · you are seat %s (%s) - waiting for every player to load" % [
				Net.room_code, Net.match_round, HUMAN, str(SEAT_FACTIONS[HUMAN]).to_upper()])
	else:
		hud.toast("%s - you are seat %s (%s). Drag from your node to send." % [map.get("name", ""), HUMAN, str(SEAT_FACTIONS[HUMAN]).to_upper()])


func start_match(path: String, faction: String, rival_faction: String, level: String, match_mode := "1v1", colour := "A") -> void:
	## Entry from the front menu (Menu.deploy): your faction (seat A), the rival's (seat B), the AI
	## level, the map, the mode (1v1 / 2v2 / FFA3-5) and your colour.
	mode = match_mode
	color_choice = colour
	SEAT_FACTIONS[HUMAN] = faction
	SEAT_FACTIONS["B"] = rival_faction
	ai_level = level
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	_start_map(path)


func _start_online() -> void:
	## A room's round (Net): players, plus the AI in empty or dropped seats (host only). The host
	## steps the Sim; guests build the same world from the same seed and render the host's snapshots.
	var info: Dictionary = Net.match_info
	online = true
	mode = str(info["mode"])
	seed_value = int(info["seed"])
	for seat in info["players"]:
		SEAT_FACTIONS[seat] = info["players"][seat]
	HUMAN = Net.local_seat()
	_start_map(str(info["map"]))
	Net.world_ready(sim, self)
	Net.order_feedback.connect(_on_order_feedback)
	if Net.is_host():                                  # EMPTY SEATS and dropped players: the AI plays them
		_sync_online_ais()
		Net.seats_changed.connect(_sync_online_ais)


func _sync_online_ais() -> void:
	var seats: Dictionary = Net.ai_seats()
	ais = ais.filter(func(ai): return seats.has(ai.seat))
	var have := ais.map(func(ai): return ai.seat)
	for seat in seats:
		if not seat in have and sim.factions.has(seat):
			ais.append(SeatAI.new(seat, 2.5, seats[seat]))


func _on_order_feedback(msg: String) -> void:
	if hud:
		hud.toast(msg)


func restart() -> void:
	relaunch = {"map": map_path, "faction": SEAT_FACTIONS[HUMAN], "rival": SEAT_FACTIONS["B"], "ai": ai_level, "mode": mode, "colour": color_choice}
	get_tree().reload_current_scene()


func to_menu() -> void:
	if online:                                         # LEAVE ROOM: the room closes for us
		Net.leave()
	relaunch = {"faction": SEAT_FACTIONS[HUMAN], "rival": SEAT_FACTIONS["B"], "ai": ai_level, "mode": mode, "colour": color_choice}
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ world
func _apply_quality() -> void:
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
	combat.top_limit = hud.top_used() + 3.0 * 38.0 * hud.ui_scale   # the top bar and up to three toasts
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
	# Alpha 16 visual pass: the cloud-city sky behind the arena (Scenery's canvas layer) and light that
	# belongs to it - violet ambient from the sky, a warm key, a cool violet fill and a back rim that
	# lifts the platform edges off the brighter background.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -10
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.54, 0.78)
	env.ambient_light_energy = 0.3
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
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, -145, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.62, 0.58, 1.0)
	add_child(fill)
	var rim := DirectionalLight3D.new()                # from behind the board, toward the camera
	rim.rotation_degrees = Vector3(-18, 180.0 + rad_to_deg(Rules.view_yaw), 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.7, 0.62, 1.0)
	add_child(rim)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true


func _fit_camera() -> void:
	## Fits the whole map - every platform rim and the badge hanging under it - inside the screen area
	## the HUD leaves free (right of the send panel, below the top bar, above the bottom strip), by
	## projecting those points and correcting distance and aim until they fit (Alpha 14 playtest:
	## "the HUD should never overlap a corridor or a platform"). Fixed from then on: no player zoom or
	## pan; only the Last Stand closes in on the nodes still standing (_collapse_zoom).
	cam_yaw = Rules.view_yaw
	if _fit_gone == 0 and _zoom_t < 0.0:              # no Last Stand zoom yet: cam_pitch is the start view's
		_base_pitch = cam_pitch                       # (a probe may have set it after _start_map)
	cam_pitch = _base_pitch                           # the start view stays exactly as it was
	_start_fit = _fit_nodes(sim.nodes)
	cam_target = _start_fit[0]
	cam_dist = _start_fit[1]
	if _fit_gone > 0 and scenario_focus == Vector3.INF:   # resized after a Last Stand zoom: keep the survivors framed
		var fit := _survivor_fit()
		cam_target = fit[0]
		cam_dist = fit[1]
		cam_pitch = fit[2]
		_zoom_t = -1.0
	if scenario_focus != Vector3.INF:
		cam_target = scenario_focus
		cam_dist = scenario_zoom
	_place_camera()


func _fit_nodes(nodes: Array) -> Array:
	## The fit of _fit_camera for a set of nodes: [cam_target, cam_dist] at the current pitch and yaw.
	## It moves the camera to measure, then puts it back where it was.
	var keep := [cam_target, cam_dist]
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for n in nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	cam_target = (lo + hi) / 2.0
	var vp := get_viewport().get_visible_rect().size
	var use_hud: bool = hud != null and thumb_path == ""
	var left: float = (hud.side_panel.position.x + hud.side_panel_width() + 14.0) if use_hud else 8.0
	var top: float = hud.top_used() if use_hud else 8.0
	var bottom: float = vp.y - (hud.bottom_used() if use_hud else 8.0)
	var right: float = vp.x - (margins.z + hud.pause_button.size.x + 12.0 if use_hud else 8.0)   # PAUSE and Debug column
	var free := Rect2(left, top, maxf(right - left, 100.0), maxf(bottom - top, 100.0))
	var pts := []
	for n in nodes:
		var p: Vector3 = n["pos"]
		for k in range(12):
			var a := TAU * k / 12.0
			pts.append(p + Vector3(cos(a), 0.0, sin(a)) * (Rules.R + 1.0))
		pts.append(p + Vector3(0, 7.5, 0))                    # the top of the tallest tower
		if n["plaza"] >= 0:                                     # maps 3.0 plazas reach past their sockets
			var pl: Dictionary = map["layout"]["plazas"][str(n["plaza"])]
			for k in range(16):
				var a := TAU * k / 16.0
				var q := Vector2(float(pl["ax"]) * cos(a), float(pl["ay"]) * sin(a)).rotated(float(pl["phi"]))
				pts.append(Vector3(float(pl["c"][0]) + q.x, 0.0, float(pl["c"][1]) + q.y))
		if use_hud:
			var ba: Vector3 = hud.badge_anchor(n)            # room for the badge beside the platform
			pts.append(ba)
			pts.append(ba + (ba - p).normalized() * 2.0)
	cam_dist = 120.0
	for it in range(24):
		_place_camera()
		var box := Rect2(cam.unproject_position(pts[0]), Vector2.ZERO)
		for q in pts:
			box = box.expand(cam.unproject_position(q))
		var k := maxf(box.size.x / free.size.x, box.size.y / free.size.y)
		cam_dist *= lerpf(1.0, k, 0.8)
		var miss := free.get_center() - box.get_center()   # screen offset to move the map by
		var g0 := _ground(vp / 2.0)
		var g1 := _ground(vp / 2.0 - miss)
		if g0 != Vector3.INF and g1 != Vector3.INF:
			cam_target += (g1 - g0) * 0.8
	var fit := [cam_target, cam_dist]
	cam_target = keep[0]
	cam_dist = keep[1]
	_place_camera()
	return fit


func _survivor_fit() -> Array:
	## [cam_target, cam_dist, cam_pitch] for the nodes the Last Stand has not dropped. Daniele (0.18.6):
	## "the camera axis could benefit of being a bit lower, right now is maybe a bit too vertical when less
	## nodes are present" - the pitch lowers as the map shrinks, lerp(map pitch, max(44, map pitch - 14),
	## 1 - survivors / nodes), and the survivors are fitted at that pitch: never wider than the start
	## distance, never closer than 1 / COLLAPSE_ZOOM_MAX of it.
	var alive := sim.nodes.filter(func(n): return not sim.collapsed.get(n["id"], false))
	if alive.is_empty():
		return [_start_fit[0], _start_fit[1], _base_pitch]
	var gone := 1.0 - float(alive.size()) / float(maxi(sim.nodes.size(), 1))
	var pitch := lerpf(_base_pitch, maxf(COLLAPSE_PITCH_MIN, _base_pitch - COLLAPSE_PITCH_DROP), gone)
	var keep := cam_pitch
	cam_pitch = pitch                                 # _fit_nodes measures at the current pitch
	var fit := _fit_nodes(alive)
	cam_pitch = keep
	fit[1] = clampf(fit[1], _start_fit[1] / COLLAPSE_ZOOM_MAX, _start_fit[1])
	return [fit[0], fit[1], pitch]


func _collapse_zoom(dt: float) -> void:
	## Daniele: "if the borders are gone have the camera zoom in to make it more epic". After each
	## Last Stand wave, once the fall has played, the camera eases in on the surviving nodes, same yaw,
	## the pitch lowering as fewer nodes remain (_survivor_fit). Read from the Sim's collapsed set every
	## frame (not the fx events), so
	## online guests, who apply the host's snapshots, close in too. Staged scenarios and thumbnails keep
	## their camera.
	if scenario_focus != Vector3.INF or thumb_path != "" or _start_fit.is_empty():
		return
	var gone := 0
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false):
			gone += 1
	if gone != _gone_seen:                            # a new wave fell: wait for its fall, then re-fit
		_gone_seen = gone
		_gone_wait = COLLAPSE_ZOOM_DELAY
	if _gone_wait > 0.0:
		_gone_wait -= dt
		if _gone_wait <= 0.0 and gone > 0 and gone != _fit_gone:
			_fit_gone = gone
			_zoom_from = [cam_target, cam_dist, cam_pitch]
			_zoom_to = _survivor_fit()
			_zoom_t = 0.0
	if _zoom_t >= 0.0:
		_zoom_t = minf(_zoom_t + dt / COLLAPSE_ZOOM_SECONDS, 1.0)
		var k := ease(_zoom_t, -2.0)                  # ease in and out
		cam_target = (_zoom_from[0] as Vector3).lerp(_zoom_to[0], k)
		cam_dist = lerpf(_zoom_from[1], _zoom_to[1], k)
		cam_pitch = lerpf(_zoom_from[2], _zoom_to[2], k)   # the pitch lowers with the same ease
		_place_camera()                               # hud.sync re-lays the badges on the new transform
		if _zoom_t >= 1.0:
			_zoom_t = -1.0


func _stage_scenario() -> void:
	## Staged situations for looking at one thing up close (no AI). fight/rear/queue: contacts on
	## the deck between nodes 1 and 0 (Two Piers). build: A owns node 1 with units to spend
	## (Strait: relay node -> cannon). switch: A's horde crosses node 1's switch deck on First Switch
	## while A fires it. rotate: A rides the Switchback hub deck. inspect: opens node 1's inspector.
	## The node indices assume the legacy maps: pass --map=res://maps/004-two-piers.json (fight/rear/
	## queue/inspect), 008-strait (build), 010-first-switch (switch), 061-switchback-foundry (rotate).
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


func _place_camera() -> void:
	var pitch := deg_to_rad(cam_pitch)
	var back := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, cam_yaw)
	cam.position = cam_target + back * cam_dist
	cam.look_at(cam_target, Vector3.UP)


# ------------------------------------------------------------------ node actions (HUD -> sim)
func node_action(method: String, id: int, args := {}) -> bool:
	## Every tap gives feedback (Alpha 11): what happened, or why it couldn't. Online guests send the
	## order to the host, which runs perform() for their seat and answers with the same line.
	if online and not Net.started:
		hud.toast("Waiting for every player to load")
		return false
	if online and not Net.is_host():
		Net.order(method, id, args)
		return true
	var r := perform(HUMAN, method, id, args)
	if str(r[1]) != "":
		hud.toast(r[1])
	return r[0]


func perform(seat: String, method: String, id: int, args := {}) -> Array:
	## One player's order, checked for that seat: [accepted, feedback line]. The host runs guests'
	## orders through here too (Net._execute), so ownership is always checked against the Sim.
	if method == "recall":
		var h := sim._horde(id)
		if h.is_empty() or h["owner"] != seat:
			return [false, "That line can't turn back now"]
		var units: float = h["units"]
		if sim.recall(id):
			return [true, "Recalled - %d units turning back" % Rules.shown(units)]
		return [false, "That line can't turn back now"]
	if id < 0 or id >= sim.nodes.size() or sim.collapsed.get(id, false) or sim.over:
		return [false, ""]
	var n: Dictionary = sim.nodes[id]
	if n["owner"] != seat:
		return [false, "Not your node"]
	match method:
		"send":
			var to: int = int(args.get("to", -1))
			var f: float = clampf(float(args.get("fraction", 0.5)), 0.0, 1.0)
			if to < 0 or to >= sim.nodes.size() or to == id:
				return [false, ""]
			var count := int(floorf(n["units"] * f))
			if sim.send(id, to, f).is_empty():
				return [false, "No route to that node" if count > 0 else "No units to send"]
			return [true, "Sending %d units to node %d" % [Rules.shown(count), to]]
		"switch":
			if sim.fire_relay(id):
				return [true, "Relay fired - switching in %d s, then %d s cooldown" % [int(Rules.RELAY_WARNING), int(Rules.RELAY_COOLDOWN)]]
			return [false, "Relay on cooldown" if n["relay_cd"] > 0.0 else "Relay is already switching"]
		"upgrade":
			var cost := sim.upgrade_cost(n)
			if sim.upgrade_structure(id):
				return [true, "Upgrade started - %d units, %d s" % [Rules.shown(cost), int(Rules.BUILD_SECONDS)]]
			elif n["build_kind"] != "":
				return [false, "Construction already in progress"]
			elif n["attachment"] == "cannon" and n["cannon_tier"] >= 3:
				return [false, "Cannon is already at max tier"]
			elif n["attachment"] == "forge":
				return [false, "A forge has no further tier"]
			elif n["tier"] >= 4:
				return [false, "Vat is already at max tier"]
			elif n["units"] < cost:
				return [false, "Upgrade needs %d units (%d here)" % [Rules.shown(cost), Rules.shown(n["units"])]]
			return [false, "Nothing to upgrade here"]
		"build_cannon", "build_forge":
			var kind := method.substr(6)
			var cost: int = Rules.CANNON_COST[1] if kind == "cannon" else Rules.FORGE_COST
			if sim.build_attachment(id, kind):
				return [true, "%s construction started - %d units, %d s" % [kind.capitalize(), Rules.shown(cost), int(Rules.BUILD_SECONDS)]]
			elif n["build_kind"] != "":
				return [false, "Construction already in progress"]
			elif n["swap_cd"] > 0.0:
				return [false, "Attachment swap ready in %d s" % int(ceil(n["swap_cd"]))]
			elif n["units"] < cost:
				return [false, "%s needs %d units (%d here)" % [kind.capitalize(), Rules.shown(cost), Rules.shown(n["units"])]]
			return [false, "Can't build a %s here" % kind]
		"restore":
			if sim.restore_vat(id):
				return [true, "Restoring the vat - %d s" % int(Rules.BUILD_SECONDS)]
			return [false, "Can't restore the vat now"]
	return [false, ""]


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if perf_on:
		_perf(delta)
	if not started:
		return
	if get_viewport().get_visible_rect().size != _fitted_size:
		_on_resized()
	var dt := minf(delta, 0.05)
	_flush_inspect()
	if online:                                    # the host's Sim is the only simulation (Net)
		if Net.is_host() and Net.started:
			for ai in ais:
				ai.think(sim, dt)
			sim.step(dt)
	elif not paused:
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
			combat.before_swap(n, entry)              # a conquest's tier-down keeps a ghost of the old tier
			MapBuilder.set_centre_model(self, entry, model, n["pos"], n["owner"])
			combat.after_swap(n, entry)
	scenery.sync(dt)
	if online:
		Net.push_effects(sim.fx_events)              # host: the guests see the same bursts and falls
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
					var left: float = sim.drop_in(ev["node"]) if sim.v3 else Rules.LAST_STAND_WARNING
					hud.toast("Your node %d falls in %d s - get out!" % [ev["node"], int(ceil(left))])
			"relay_tick":
				var n: Dictionary = sim.nodes[ev["node"]]
				if n["owner"] == HUMAN:
					hud.toast("Relay %d switches now" % ev["node"])
			"fling":                                  # a turning deck threw a line into the void (units already shown scale)
				var ours := sim.allied(str(ev["seat"]), HUMAN)
				var flung := int(ev["units"])
				if flung > 0:                         # a sliver under half a shown unit still counts, but gets no toast
					hud.toast("%d unit%s flung off the turning deck" % [flung, "" if flung == 1 else "s"], "warn" if ours else "good")
			"fall":                                   # 0.18.7: a retract / switch / remote took the deck from under a line
				if ev.has("relay") and int(ev.get("shown", 0)) > 0:
					var fell := int(ev["shown"])
					var kind := str(sim.nodes[int(ev["relay"])]["relay"])
					var what: String = {"retract": "the retracting deck", "switch": "the switched deck", "remote": "the switched-off deck"}.get(kind, "the deck")
					hud.toast("%d unit%s fell with %s" % [fell, "" if fell == 1 else "s", what], "warn" if sim.allied(str(ev["seat"]), HUMAN) else "good")
	sim.fx_events.clear()
	_collapse_zoom(dt)
	fx.selected = selected if drag_from < 0 else drag_from
	fx.sync(dt)
	combat.sync(dt, cam)                          # after Fx: it scales the tier-down's rising model
	forge_pulse.sync(dt, cam)                     # after both (it pumps the models) and the views (their glows)
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


func _on_forge_online(seat: String, _node_id: int, first: bool) -> void:
	## ForgePulse: a forge just came online (built or captured). The toast names the owner by emblem and
	## faction ("seat X" -> Hud._SEAT_WORD); good news in your colour for your side, red for a rival's.
	var kind := "good" if sim.allied(seat, HUMAN) else "warn"
	if first:
		hud.toast("seat %s FORGE ONLINE: +%d%% attack" % [seat, roundi(Rules.forge_bonus * 100.0)], kind)
	else:                                              # the bonus does not stack (Sim.forge_of)
		hud.toast("seat %s FORGE ONLINE: attack bonus kept" % seat, kind)


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
	if not started:
		return
	if paused:                                    # pause menu / end panel: drop any gesture in flight
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			touches.erase((event as InputEventScreenTouch).index)
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			_swallow_release = false                  # a double-tap's release: never swallow the next one
		if drag_from >= 0:
			_end_drag()
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			touches[st.index] = st.position
		else:
			touches.erase(st.index)
		if touches.size() == 2:
			_end_drag()
		return
	if event is InputEventScreenDrag and touches.size() == 2:
		return                                        # fixed camera: no pinch zoom or two-finger pan
	if touches.size() >= 2:
		return
	if event is InputEventMouseButton:                # fixed camera: the wheel does nothing
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if hud.pointer_over_ui(mb.position):
				if not mb.pressed:                      # a drag released on the HUD is cancelled, never left hanging
					_swallow_release = false
					_end_drag()
				return
			var hit := _ground(mb.position)
			if mb.pressed:
				var n := _node_at(hit, mb.position)
				_press_pos = mb.position
				_press_time = Time.get_ticks_msec() / 1000.0
				if n >= 0:
					if sim.nodes[n]["owner"] == HUMAN and n == _tap_node and _press_time - _tap_time < DOUBLE_TAP_WINDOW:
						hud.close_inspector()
						_pending_inspect = -1                   # the first tap's inspector never opens
						_swallow_release = true                 # nor does this tap's release reopen it
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
					var own := _horde_at(hit) if Rules.bridge_combat else {}   # RECALL is SIEGE only (Alpha 16)
					if not own.is_empty():                       # tap one of your lines: RECALL it
						node_action("recall", own["id"])
						return
			else:
				if _swallow_release:
					_swallow_release = false
					_end_drag()
					return
				if drag_from >= 0:
					var target := _node_at(hit, mb.position)
					var moved := (mb.position - _press_pos).length() >= TAP_PIXELS
					if moved and target != drag_from:
						_tap_node = -1                     # Alpha 11 (game.gd:723): a drag never arms the double-tap
					if target >= 0 and target != drag_from and moved:
						if node_action("send", drag_from, {"to": target, "fraction": fraction}):
							fx._pulse(sim.nodes[target]["pos"], Rules.seat_color(HUMAN), Rules.R, 0.6)
						hud.close_inspector()
						selected = drag_from
					elif not moved:
						selected = drag_from
						_queue_inspect(drag_from)                 # single tap: the ring inspector, once no second tap comes
				else:
					var target := _node_at(hit, mb.position)
					if target >= 0 and (mb.position - _press_pos).length() < TAP_PIXELS:
						selected = target
						_queue_inspect(target)
				_end_drag()
	elif event is InputEventMouseMotion:
		var hit := _ground((event as InputEventMouseMotion).position)
		if drag_from >= 0:
			_draw_drag(drag_from, hit, (event as InputEventMouseMotion).position)


func _end_drag() -> void:
	## Clears the send gesture: no source node, no preview line, no route label.
	drag_from = -1
	drag_mesh.clear_surfaces()
	route_label.visible = false


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
		# the real walk: path length at the constant speed, the owner's faction speed included
		var seconds: float = float(path["cum"][-1]) / maxf(Rules.move_speed() * sim.stat(HUMAN, "speed"), 0.1)
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
		route_label.text = "%s · %d units · %d s" % [verb.to_upper(), Rules.shown(count), int(round(seconds))]
		route_label.position = tn["pos"] + Vector3(0, 6.5, 0)
		route_label.visible = true
	else:
		drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for k in range(-1, 2):
			var off := (b - a).cross(Vector3.UP).normalized() * 0.1 * k
			drag_mesh.surface_add_vertex(a + up + off)
			drag_mesh.surface_add_vertex(b + up + off)
		drag_mesh.surface_end()


var _perf_t := 0.0
func _perf(dt: float) -> void:
	## --perf: print frame timing every 3 s (process / physics / draw calls / objects) to find hogs.
	_perf_t += dt
	if _perf_t < 3.0:
		return
	_perf_t = 0.0
	print("PERF fps=%d process=%.2fms physics=%.2fms nav=%.2fms objects=%d draw=%d prims=%d" % [
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _horde_at(p: Vector3) -> Dictionary:
	## The player's own horde whose line passes within reach of a ground point (recall target).
	if p == Vector3.INF:
		return {}
	var best := {}
	var best_d := 2.2 if not mobile else 3.2
	for h in sim.hordes:
		if h["owner"] != HUMAN or h["state"] == "absorb" or h.get("retreat", false):
			continue
		var len := Sim.chain_length(h)
		var k := 0.0
		while k <= len:
			var q: Vector3 = Sim.sample(h, h["s"] - k)[0]
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if d < best_d:
				best_d = d
				best = h
			k += 1.2
	return best


func _queue_inspect(id: int) -> void:
	## Alpha 11: a single tap inspects only once it is clear no second tap is coming, so a
	## double-tap upgrade never flashes the inspector open.
	_pending_inspect = id
	_pending_at = Time.get_ticks_msec() / 1000.0


func _flush_inspect() -> void:
	if _pending_inspect >= 0 and Time.get_ticks_msec() / 1000.0 - _pending_at >= DOUBLE_TAP_WINDOW:
		var id := _pending_inspect
		_pending_inspect = -1
		# only your own nodes open the ring (Daniele, 0.18.7: "i shouldn't be able to click enemy vault ... an
		# empty radial menu appears"); enemy, neutral and allied nodes are read from their badges
		if not paused and not sim.over and sim.nodes[id]["owner"] == HUMAN:   # Alpha 11 game.gd:588: never over the pause or end panel
			hud.inspect(id, cam)
