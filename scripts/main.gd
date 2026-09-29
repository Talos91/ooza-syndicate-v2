extends Node3D
## Ooze Syndicate 2.0 (version: Rules.VERSION / VERSION_NAME). World, camera, input and orchestration;
## the interface lives in hud.gd, in-world effects in fx.gd (fights, tier-downs and the cannon laser in
## combat_fx.gd), hordes in horde_view.gd, rules in sim.gd.
## Drag from one of your nodes to any node to send; tap a node to inspect; double-tap your own node
## to upgrade (Alpha 11 convention); the inspector offers costed actions and the relay's switch. RELAY V2: a
## relay's button platform off the rim is a second tap target for its node (double-tap it, or the node, to fire).
## Command-line user args (after `--`):
##   --map=res://maps4/T-01-first-steps.json  map to load (skips the title screen)
##   --mode=1v1|2v2|3v3|2v2v2|FFA3|FFA4|FFA5  match mode (the map's first mode if it lacks this one)
##   --demo                                 every seat played by the AI
##   --ai=Training|Casual|Standard|Veteran|Expert  AI level (Rules.AI_LEVELS; the menu picks it otherwise)
##   --brawl (alias --classic)              no-op: BRAWL is the only mode since 0.18.7 (SIEGE deactivated)
##   --seed=N                               deterministic Last Stand method / chaos order
##   --shots=4,12,25 --out=<dir>            save screenshots at those match times, then quit
##   --ff=350                               step the sim headless-fast (no rendering) to this match
##                                           time before playing on at 1x - for rendering a late-match
##                                           moment (Last Stand, Very Last Stand) without sitting
##                                           through real time; combine with --shots for a contact sheet
##   --perf                                 print frame timing every 3 s
##   --window=2340x1080                      size the window like a phone (landscape) for testing
##   --mobile                               force the phone quality profile on desktop
##   --pitch=58                              camera pitch in degrees above the horizon (MapCamera's per-map pitch otherwise)
##   --thumb=<png>                          render the map's menu thumbnail (no HUD), then quit
##   --menu-page=<page> --menu-shot=<png>   open a menu page / screenshot the menu, then quit
##   --menu-filter=brawl                     screenshot helper: pre-set the BATTLEFIELD TYPE filter chip
##   --menu-mode=FFA4 --menu-colour=faction   screenshot helper: pre-set SETUP's PLAYERS mode / YOUR COLOUR
##   --scenario=fight|rear|queue|build|inspect|switch|rotate --zoom=N  stage one situation up close
##   --goo                                  TERRITORY: GOO (Rules.goo_territory) instead of the neon
##   --faction=null --rival=null            your faction (seat A) and seat B's (a mirror match: the same one)
##   --focus=N --zoom=N                     frame node N up close (camera distance N m) in a normal match
##   --tutorial=N                           start tutorial lesson N (0 the tour, 1-9) straight away (screenshots, testing)
##   --mission=vex:01                       CAMPAIGN: start that mission straight away (its briefing first)
##   --campaign-all                         CAMPAIGN: every playable mission open (Campaign.all_open)
##   --mission-start                        CAMPAIGN: skip the briefing (headless boot checks)
##   --mission-shot=brief|hud|win|lose|details|endline --out=<dir>   CAMPAIGN: screenshot that screen as mission_<shot>.png, then quit
##   --versus-shot=<png>                    UI: DEPLOY with the menu's saved picks (--menu-mode=, --ui-cfg=...), screenshot
##                                           the VERSUS card, then quit (with --mission=<key> --mission-start: a mission's)
##   --end-shot=win|lose|draw|details|pause|settings|out|reconnect --out=<dir>  UI: with --map=: that in-match screen as end_<shot>.png, then quit
##   --player-name=NAME                     HUD pass: your name for this run only (screenshots; nothing is saved)
##   --scenario=notices [--focus=N --zoom=N]  HUD pass: every placed message at once (callouts, an off-screen arrow
##                                           with --focus, a skill refusal, the Last Stand line's pulse)
##   --cast-at=<t>:<seat>:<slot>:<skill>[:<target>]  POWERS (DEBUG, offline): from match time t, put <skill> in that seat's
##                                           <slot> (active / map / ultimate), ready, and cast it on <target> (a node / deck /
##                                           line id, "a,b" for a pair; "auto" or none: the Sim's target nearest the view's
##                                           centre) as soon as the Sim accepts it; repeatable. --cast-zoom=N: the camera
##                                           then frames the cast N m away; --cast-shots=0.3,1.5: the screenshots are
##                                           taken that long after the first cast instead (the run quits after the last)
##   --send-at=<t>:<from>:<to>               POWERS (DEBUG): at time t, send the whole garrison of <from> to <to>
##   --aim=<t>:<slot>:<skill>[:<first>]      POWERS (DEBUG): at time t your <slot> holds <skill>, ready, and the dock arms
##                                           it (the first tap of a two-tap skill: <first>, e.g. Portal's entrance)

var HUMAN := "A"                                  # your seat: always A offline, host-assigned online
var online := false                               # this match is an online room (Net)
var SEAT_FACTIONS := {"A": "null", "B": "ember", "C": "bloom", "D": "vex", "E": "solar"}
# SKILLS 2.0 (0.18.7): seat -> {"active": id, "map": id} chosen in the ARMIES page (or the room); a seat
# without one (every AI) gets its faction's Rules.FACTION_LOADOUT. The ultimate follows the faction.
var LOADOUTS := {}
const FACTION_NAMES := ["vex", "null", "bloom", "ember", "solar"]

var map: Dictionary
var map_path := "res://maps4/A-01-orbital-nexus.json"   # 0.20.4: the T- maps are tutorial-only (MapPool.TUTORIAL_ONLY)
var sim := Sim.new()
var ais: Array = []
var vis: Dictionary
var hordes: HordeView
var fx: Fx
var combat: CombatFx                               # fights for a tower, conquest tier-downs, the cannon laser
var forge_pulse: ForgePulse                        # a forge coming online: the owner's 2 s power-up wave
var skill_fx: SkillFx                              # Skills 2.0 in the world: every cast, lasting effect and end
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
var _view_fit := []                               # [cam_target, cam_dist] the player zoom widens back to (start / survivor fit)
var _map_half := Vector3.ZERO                     # half the nodes' extent (x, z): how far a zoomed view may pan
var _pinch := {}                                  # two fingers down: {"d": their distance, "mid": their midpoint}
var _gone_seen := 0                               # Last Stand: nodes collapsed at the last check
var _gone_wait := 0.0                             # seconds left before the camera re-fits (the fall plays first)
var _fit_gone := 0                                # collapsed count the camera is fitted to (0 = the whole map)
var _zoom_from := []
var _zoom_to := []
var _zoom_t := -1.0                               # 0..1 through the ease, < 0 when still
const COLLAPSE_ZOOM_DELAY := 1.0                  # the platforms' fall first (fx._collapse, ~1.5 s)
const COLLAPSE_ZOOM_SECONDS := 1.5
const COLLAPSE_PITCH_DROP := 14.0                 # degrees the pitch lowers by once almost every node has fallen
const COLLAPSE_PITCH_MIN := 44.0                  # never flatter than this
var fraction := 0.5
var drag_from := -1
var selected := -1
var monster_from := -1                            # Structures 2.1: a hub's LAUNCH is armed - drag, or tap
                                                   # a highlighted node in sim.monster_reach(monster_from)
var drag_mesh := ImmediateMesh.new()
var drag_line: MeshInstance3D                     # made in _start_map: a menu-only run never parents it
var route_label: Label3D
var trace: Array = []
var _trace_t := 0.0
var shots: Array = []
var shot_dir := ""
var ff_to := -1.0        # --ff=<seconds>: step the sim headless-fast to this match time before playing on
var _cast_at: Array = []  # POWERS (DEBUG): --cast-at orders still to cast [t, seat, slot, skill, target string]
var _cast_zoom := -1.0    # POWERS (DEBUG): --cast-zoom=N
var _cast_shots: Array = []   # POWERS (DEBUG): --cast-shots=0.3,1.5: screenshots that long after the first --cast-at cast
var _aim: Array = []      # POWERS (DEBUG): --aim [t, slot, skill, first tap string]
var demo := false
var ai_level := "Standard"
var seed_value := -1
var paused := false
var show_out_panel := true                        # 0.19.2 spec H7: the tutorial sets this false in lessons
var scenario := ""
var scenario_focus := Vector3.INF
var scenario_zoom := 30.0
var focus_node := -1                              # --focus=N: a close-up of node N in a normal match
var _scenario_done := false
var _hud19_phase := -1                            # --scenario=hud19: the contact sheet's timed phases
var player_name := ""                             # --player-name=: overrides the account's name for this run (seat_who)
var _forge_node := {}                             # seat -> the node of its last forge that came online (FORGE LOST's place)
var _last_order := [-1, "", 0]                    # a guest's last order [id, method, msec]: where the host's answer shows
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
static var last_map_path := ""                 # MAIN MENU remembers the last map played (0.19.0)
# --- TUTORIAL (TUTORIAL-DESIGN.md §8): the lesson director, its coach overlay, the half-speed clock ---
var director: TutorialDirector = null            # a lesson is on (null: a normal match)
var coach: CoachOverlay = null
var menu_faction := ""                           # the player's own menu faction, kept while a lesson plays VEX
var menu_ai := ""                                # AUDIT FIX: the player's own menu AI level, kept while a lesson plays its own
var _coach_version := -1
static var menu_open := ""                       # after a relaunch: open this menu page instead of MAIN
var relaunched := false                          # AUDIT FIX: this scene came from a relaunch carrying your faction (Menu)
# --- CAMPAIGN (CAMPAIGN-DESIGN.md §4 / §5): the mission director, its overlay, the menu settings kept for afterwards ---
var mission: MissionDirector = null              # a campaign mission is on (null: not one)
var mission_overlay: MissionOverlay = null
var mission_menu_faction := ""                   # the player's own menu faction / AI level, back after the mission
var mission_menu_ai := ""
var end_shot := ""                               # UI: --end-shot=win|lose|draw|details|pause|settings|out|reconnect (_end_shot)
static var mission_arg_used := false             # --mission=<key> starts it once per run (a leave never loops back)
# --- end CAMPAIGN ---
# --- AUDIT FIX (2026-09-28, audit-sim A4 + audit-client A1): a room's settings never stay applied offline ---
static var own_settings := {}                    # the player's own LAST STAND / ABILITIES / HIDDEN COUNTS, taken offline
static var room_rules := false                   # a room's round wrote its settings and numbers into Rules (Net._launch)
# --- end AUDIT FIX ---


func _ready() -> void:
	var map_explicit := false
	if FullscreenGate.needed():                        # phones play fullscreen (Alpha 14 playtest)
		add_child(FullscreenGate.new())
	Engine.max_fps = Net.DEDICATED_FPS if Net.dedicated else 60   # never spin faster than the screen (menu included)
	PerfProfile.apply(self)                            # Alpha 21 OPT-RENDER: graphics profile, fps cap, map batching (perf_profile.gd)
	Sfx.attach(self)                                   # SOUND: the match's sounds + the saved volume (sfx.gd; never on the room server)
	Music.attach(self)                                 # MUSIC: the soundtrack follows this scene (music.gd; never on the room server)
	MissionDirector.restore_settings()                 # CAMPAIGN / TUTORIAL: a mission's or lesson's pinned settings go back
	if Net.online():                                   # a room launched (or relaunched) a round
		Net.load_mark("main_ready")
		room_rules = true                              # AUDIT FIX: Net._launch wrote the room's settings into Rules
		_start_online()
		return
	if not Net.dedicated:                              # AUDIT FIX: offline - the room's numbers and toggles go, yours come back
		restore_own_settings()
		keep_own_settings()
	if Net.dedicated:                                  # the room server's match host between rounds: no menu, no screen
		return
	relaunched = relaunch.has("faction")
	if relaunch.has("faction"):
		SEAT_FACTIONS[HUMAN] = relaunch["faction"]
		ai_level = relaunch.get("ai", ai_level)
		if relaunch.get("loadout", {}) is Dictionary and not (relaunch.get("loadout", {}) as Dictionary).is_empty():
			LOADOUTS[HUMAN] = relaunch["loadout"]
		if relaunch.has("rival"):
			SEAT_FACTIONS["B"] = relaunch["rival"]
		mode = relaunch.get("mode", mode)
		color_choice = relaunch.get("colour", color_choice)
	if relaunch.has("map"):
		map_path = relaunch["map"]
		map_explicit = true
	var tut_id := int(relaunch.get("tutorial", -1))     # TUTORIAL: a lesson relaunched (NEXT / REPLAY / RESTART; 0 = the tour)
	var tut_first := bool(relaunch.get("first", false))
	menu_open = str(relaunch.get("menu", ""))
	var mission_key := str(relaunch.get("mission", ""))   # CAMPAIGN: RETRY / NEXT MISSION
	var army_open := str(relaunch.get("army", ""))      # UI: CHANGE LOADOUT from a mission's result
	relaunch = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--progress="):              # PROGRESSION screenshot helper: a scratch save, never the real one
			Progression.path = arg.substr(11)
			Progression.reload_all()
		elif arg == "--locks=on":                        # PROGRESSION screenshot helper: the locks as players will see them
			Progression.unlock_all = false
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
		elif arg.begins_with("--ff="):
			ff_to = float(arg.substr(5))
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
		elif arg == "--classic" or arg == "--brawl":  # harmless: BRAWL is the only mode (0.18.7)
			pass
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg == "--goo":
			Rules.goo_territory = true
		elif arg.begins_with("--faction="):
			SEAT_FACTIONS[HUMAN] = arg.substr(10)
		elif arg.begins_with("--rival="):
			SEAT_FACTIONS["B"] = arg.substr(8)
		elif arg.begins_with("--player-name="):
			player_name = arg.substr(14)
		elif arg.begins_with("--focus="):
			focus_node = int(arg.substr(8))
		elif arg.begins_with("--thumb="):              # map thumbnail for the menu: no HUD, first frame
			thumb_path = arg.substr(8)
			map_explicit = true
		elif arg.begins_with("--tutorial="):
			tut_id = int(arg.substr(11))
		elif arg.begins_with("--cast-at="):           # POWERS (DEBUG): a forced cast for screenshots (_debug_casts)
			var cp := arg.substr(10).split(":")
			if cp.size() >= 4:
				_cast_at.append([float(cp[0]), cp[1], cp[2], cp[3], cp[4] if cp.size() > 4 else "auto"])
		elif arg.begins_with("--send-at="):           # POWERS (DEBUG): --send-at=<t>:<from>:<to> - a whole-garrison send then
			var sp := arg.substr(10).split(":")
			if sp.size() >= 3:
				_cast_at.append([float(sp[0]), "", "send", "", "%s,%s" % [sp[1], sp[2]]])
		elif arg.begins_with("--cast-zoom="):
			_cast_zoom = float(arg.substr(12))
		elif arg.begins_with("--cast-shots="):
			for t in arg.substr(13).split(","):
				_cast_shots.append(float(t))
		elif arg.begins_with("--aim="):               # POWERS (DEBUG): the dock armed for screenshots (_debug_casts)
			var ap := arg.substr(6).split(":")
			if ap.size() >= 3:
				_aim = [float(ap[0]), ap[1], ap[2], ap[3] if ap.size() > 3 else ""]
		elif arg.begins_with("--end-shot="):          # UI: screenshot an in-match screen (_end_shot)
			end_shot = arg.substr(11)
			map_explicit = true
	MapPool.phone = MapPool.phone_screen(mobile)       # Alpha 18: phones get the phone-fit maps only
	_start_telemetry()                                 # PROGRESSION (Alpha 21): consent, crash hooks, the privacy notice
	if window_size != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
	# CAMPAIGN: a mission relaunched (RETRY / NEXT MISSION) or --mission=<key> goes straight in - checked before
	# the tutorial's first launch, so a fresh profile never lands in the L0 tour instead
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mission=") and not mission_arg_used:
			mission_key = arg.substr(10)
			mission_arg_used = true
		elif arg == "--campaign-all":
			Campaign.all_open = true
	if mission_key != "":
		start_mission(mission_key)
		return
	# --- end CAMPAIGN ---
	if tut_id >= 0 and not map_explicit:              # TUTORIAL: a lesson, straight in
		start_tutorial(tut_id, tut_first)
	elif map_explicit or demo or scenario != "" or not shots.is_empty():
		_start_map(map_path)
	elif TutorialDirector.first_launch_due(OS.get_cmdline_user_args(), Net.online() or Net.in_room() or Net.status != "" \
			or not Net.rejoin.is_empty()):
		start_tutorial(TutorialDirector.FIRST_ID, true)   # TUTORIAL §7: the first launch opens the tour (L0), then L1
	else:
		if not map_explicit and last_map_path != "":   # MAIN MENU keeps the last map played (0.19.0)
			map_path = last_map_path
		if not Net.in_room():                          # the menu, no room: a new build may reload the page
			Net.set_busy(false)
		menu_layer = Menu.new()
		add_child(menu_layer)
		(menu_layer as Menu).setup(self)
		_start_account()                               # PROGRESSION: the guest / linked account, once per run
		if Net.in_room():                              # back from a round, or a player left: the lobby
			(menu_layer as Menu).show_lobby()
		elif Net.status != "":                         # the room closed: say why on the ONLINE page
			(menu_layer as Menu).show_online()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--menu-filter="):          # screenshot helper: pre-set the BATTLEFIELD TYPE filter
				Menu.map_filter_type = arg.substr(14)
			elif arg.begins_with("--menu-map="):            # screenshot helper: pre-set SETUP's selected map
				(menu_layer as Menu).map_path = arg.substr(11)
			elif arg.begins_with("--menu-mode="):          # screenshot helper: pre-set SETUP's PLAYERS mode
				(menu_layer as Menu).mode = arg.substr(12)
			elif arg.begins_with("--menu-colour="):        # screenshot helper: pre-set SETUP's YOUR COLOUR
				(menu_layer as Menu).colour = arg.substr(14)
		if menu_open != "":                              # TUTORIAL: LESSONS / ARMIES / NEW GAME from a lesson
			if menu_open == "cosmetics":                 # (COSMETICS' BACK returns through ARMIES)
				(menu_layer as Menu).show_armies()
			if menu_open == "armies" and army_open != "":   # UI: a mission's CHANGE LOADOUT - its faction, BACK to CAMPAIGN
				(menu_layer as Menu).show_armies(army_open, Callable(menu_layer, "show_campaign"))
			else:
				(menu_layer as Menu).call("show_" + menu_open)
			menu_open = ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--menu-page="):            # screenshot helper: open a menu page
				(menu_layer as Menu).call("show_" + arg.substr(12))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--versus-shot="):         # UI: screenshot helper - DEPLOY, the VERSUS card shoots itself
				(menu_layer as Menu).deploy()
				return
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
	last_map_path = path                               # MAIN MENU remembers it (0.19.0)
	map = MapBuilder.load_map(path)
	_lm("map_json")
	if not pitch_forced:                               # Alpha 18: each map's own camera angle (phone-fit probe)
		cam_pitch = MapCamera.pitch_for(str(map.get("code", "")), str((map.get("tags", {}) as Dictionary).get("size", "")))
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
	# 0.19.2 spec H3: every seat's faction is resolved the one canonical way (Sim.resolve_factions) -
	# a concrete pick (yours, an online room's, a menu rival pick) stays; "random" (menu picks, AI-filled
	# online seats) is drawn from the seed, so every client resolves it the same way. The seed is pinned
	# to a concrete value first (sim.setup() would otherwise roll a different one for the same purpose).
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) % 100000
	SEAT_FACTIONS = Sim.resolve_factions(SEAT_FACTIONS, seats.values(), seed_value)
	if online and Net.match_info.get("colours") is Dictionary:   # a room: the host's seat colours, the same on every screen
		Rules.use_colours(Net.match_info["colours"])
	else:
		Rules.assign_colors(seats.values(), SEAT_FACTIONS, HUMAN, color_choice, teams)
	Rules.apply_colour_blind(seats.values(), teams, HUMAN)   # UI: SETTINGS > COLOUR-BLIND (your screen only)
	sim = Sim.new()
	sim.ai_builds = true                               # POWERS: AI seats mix their builds (Rules.AI_LOADOUTS)
	sim.setup(map, MapBuilder.layout(map), seats, SEAT_FACTIONS, seed_value, teams, LOADOUTS)
	_lm("sim_setup")
	var lo := Vector3(INF, 0, INF)                     # the camera looks along the map's short side
	var hi := Vector3(-INF, 0, -INF)
	for n in sim.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	Rules.view_yaw = PI / 2.0 if (hi - lo).z > (hi - lo).x else 0.0
	# --- SERVER HOST (Alpha 21, the server session): the room server's match host runs the Sim, the AI and Net only.
	# Nobody sees its screen, so no world, views, effects or HUD are built (_process has the matching block); the
	# guests get everything from the Sim's snapshots and fx events. Keep this block whole when editing _start_map. ---
	if Net.dedicated:
		sim.finished.connect(_on_finished_server)
		started = true
		paused = false
		return
	# --- end SERVER HOST ---
	if _online_card_pending:                          # UI (Daniele 2026-09-30: "shows the vs load screen for a frame"): online, the
		_online_card_pending = false                  # VERSUS card goes up BEFORE the heavy world build and is drawn first,
		if VersusScreen.hold_online(self):           # so the load happens under it instead of freezing the DEPLOY page
			_staged = true                             # STAGED LOAD (0.23.4): the build below goes a step per frame under the card
			load_progress = 0.0
			_pace_us = Time.get_ticks_usec()
			for i in range(Rules.VERSUS_ONLINE_PREDRAW_FRAMES):   # (no card - headless, a lesson, the server - no wait)
				await get_tree().process_frame
		_lm("card")
	# --- STAGED LOAD (0.23.4, Daniele 2026-09-30: "the vs screen should be the loading, so when you click deploy that's what
	# players see until the map is ready, not the frozen deploy screen"): online, under the VERSUS card (_staged), each block
	# of the build below is followed by _staged_frame - the views built so far are held (no _process: nothing runs on a
	# half-built world, `started` stays false) and what the block added is revealed a few materials per frame, so the card
	# keeps animating and the first-draw shader compiles are spread out. Offline, lessons, missions, headless runs and the
	# room server's match host (returned above) build in one block, as before. ---
	_build_world()
	if _staged:
		_fit_camera()                                  # the whole map in view now: what each step reveals is drawn (and compiled)
		await _staged_frame("build_world", 1)
	if not map.has("layout"):
		vis = MapBuilder.build(self, sim)
	elif _staged:
		vis = await MapBuilder.build3_paced(self, sim, map, Callable(self, "_pace"))
	else:
		vis = MapBuilder.build3(self, sim, map)
	if _staged:                                        # the owners' lights now, so the map is first drawn as it will look
		for n in sim.nodes:                            # (the same loop runs again below: idempotent)
			MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
		await _staged_frame("build3", 2)
	if not vis["stretched"].is_empty():
		push_warning("edges stretched to fit (not honest): %s" % [vis["stretched"]])
	hordes = HordeView.new()
	hordes.vis = vis                                   # the vat models its lines drop out of
	add_child(hordes)
	scenery = Scenery.new()
	add_child(scenery)
	if _staged:                                        # (the backdrop, the mist, each faction's model: a frame each)
		var n_step := 0
		for step in scenery.setup_steps(self, sim, vis):
			step.call()
			n_step += 1
			await _staged_frame("scenery%d" % n_step, 3)
	else:
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
	skill_fx = SkillFx.new()
	add_child(skill_fx)
	skill_fx.setup(sim, vis, HUMAN)
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
		if (seat != HUMAN or demo) and scenario == "" and not online and director == null:   # (a lesson scripts its rival)
			ais.append(SeatAI.new(seat, 2.5, ai_level))
	if ff_to > 0.0 and not online and scenario == "" and director == null:
		var ff_dt := 0.1                                # coarser than real frames (~0.05): still exact,
		while sim.time < ff_to and not sim.over:         # much faster - only the end state is rendered
			for ai in ais:
				ai.think(sim, ff_dt)
			sim.step(ff_dt)
		sim.fx_events.clear()                           # the fast-forwarded bursts are stale by now
		print("fast-forwarded to t=%.1f%s" % [sim.time, " (match already over)" if sim.over else ""])
	if director:                                       # TUTORIAL: the lesson stages its board (tutorial.gd)
		director.begin(sim, map, SEAT_FACTIONS[HUMAN])
	if mission:                                        # CAMPAIGN: the mission stages its board (mission_director.gd)
		mission.begin(sim, map, HUMAN)
	if scenario != "":
		_stage_scenario()
	elif focus_node >= 0 and focus_node < sim.nodes.size():
		scenario_focus = sim.nodes[focus_node]["pos"]
	sim.captured.connect(_on_captured)
	sim.finished.connect(_on_finished)
	for n in sim.nodes:
		vis[n["id"]]["model_key"] = MapBuilder.model_for(n)
		MapBuilder.apply_owner(vis[n["id"]]["parts"], n["owner"])
	# --- 0.19.0 cosmetics (HUD agent, spec E/I): each seat's structure look, applied once. Offline:
	# your ARMIES pick for your seat, every other seat (AI) the default. Online: every seat's pick came
	# from the host's launch packet (net.gd's "cosmetics", built from each player's roster "cosmetic" -
	# empty for an AI-filled seat), so this same loop on every client covers remote seats too.
	var net_cosmetics: Dictionary = Net.match_info.get("cosmetics", {}) if online else {}
	for seat in seats.values():
		var co: Dictionary = ArmyPresets.cosmetic_loadout_for(SEAT_FACTIONS[HUMAN]) if (seat == HUMAN and not online) else net_cosmetics.get(seat, {})
		Cosmetics.set_loadout(seat, co)
	if _staged:
		await _staged_frame("views", 4)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	if director:
		_tutorial_setup()
	_apply_quality()
	if _staged:
		await _staged_frame("hud", 5)
		_release_held()                                # the world is whole: every view runs from here
	get_viewport().size_changed.connect(_on_resized)
	started = true
	paused = false
	_lm("started")
	Warmup.run(self, _staged)                          # MATCH FEEL: every effect's shader drawn once now, behind the VERSUS card (warmup.gd)
	_lm("warmup_made")
	if mission:                                        # CAMPAIGN: the briefing card, the match paused until START
		_mission_setup()
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
	_lm("first_frame")
	_on_resized()
	# HUD pass (Daniele's "option A": no notification box): online, "waiting for every player to load" is the
	# waiting text in the middle until the round starts (_process clears it); offline the start lines are a short
	# banner - the map and who you are only where the VERSUS card didn't just say it (a restart, a rematch, a
	# command-line run), the dock's note (a relay skill this map swapped) always.
	var note: String = hud.dock.start_note() if hud.dock.visible else ""
	if online:
		var me := seat_who(HUMAN)
		hud.set_waiting(["WAITING FOR EVERY PLAYER TO LOAD", "ROOM %s  ·  ROUND %d  ·  you are %s" % [Net.room_code, Net.match_round,
				("%s · %s" % [me["name"], me["faction"]]) if str(me["name"]) != "" else str(me["faction"])]])
		if note != "":
			hud.start_banner("", [note])
	elif director == null:                             # (a lesson's coach card says what to do)
		var lines := []
		var said := mission != null or VersusScreen.wanted(self)
		if not said:
			var me := seat_who(HUMAN)
			lines.append("%s · %s  ·  drag from your node to send" % [me["name"], me["faction"]])
		if note != "":
			lines.append(note)
		hud.start_banner("" if said else str(map.get("name", "")).replace("*", "").to_upper(), lines)
	if end_shot != "" and mission == null and director == null:   # UI
		_end_shot(end_shot)


func start_match(path: String, faction: String, seat_factions: Dictionary, level: String, match_mode := "1v1", colour := "A", loadout := {}) -> void:
	## Entry from the front menu (Menu.deploy): your faction (seat A), every enemy seat's pick (0.19.2
	## spec H3: Menu._seat_faction_picks - one rival-faction picker per seat, a faction id or "random";
	## _start_map() resolves "random" through Sim.resolve_factions, the same way Sim.setup() would), the
	## AI level, the map, the mode (1v1 / 2v2 / FFA3-5), your colour and your skill loadout ({"active":
	## id, "map": id}; empty = the default).
	mode = match_mode
	LOADOUTS = {HUMAN: loadout}                        # (POWERS: always an entry - a seat with none is an AI seat)
	color_choice = colour
	SEAT_FACTIONS[HUMAN] = faction
	for seat in seat_factions:
		SEAT_FACTIONS[seat] = str(seat_factions[seat])
	ai_level = level
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	_start_map(path)
	VersusScreen.hold_match(self)                      # UI: the VERSUS card over the built match, held paused until it ends


var _online_card_pending := false                     # UI: set by _start_online, read once by _start_map
var _staged := false                                  # STAGED LOAD: this online round's world is built a step per frame (_start_map)
var load_progress := -1.0                             # STAGED LOAD: 0..1 through the build (the VERSUS card's bar); -1: not staged
var _held: Array[Node] = []                           # STAGED LOAD: the views held (process off) until the world is whole
var _held_ids := {}                                   # (instance id -> true: every child already seen by _staged_frame)
const STAGED_STEPS := 5                               # _staged_frame's steps (the bar); the warm-up fills the last share


func _staged_frame(label: String, step: int) -> void:
	## STAGED LOAD: after one block of an online round's build, under the VERSUS card. The children the block added are held
	## (process off: no view runs on a half-built world) and their meshes hidden, then revealed a few materials' worth per
	## frame - each drawn frame compiles only the new shaders it shows (Rules.STAGED_LOAD_FRAME_MS adapts the pace).
	_lm(label)
	var fresh := _hold_fresh()
	var groups := {}                                   # draw signature -> the meshes that share it
	var order: Array = []
	for c in fresh:
		var list: Array = [c] if c is GeometryInstance3D else []
		list.append_array(c.find_children("*", "GeometryInstance3D", true, false))
		for g in list:
			if not (g as GeometryInstance3D).is_visible_in_tree():
				continue
			var sig := _draw_sig(g)
			if not groups.has(sig):
				groups[sig] = []
				order.append(sig)
			groups[sig].append(g)
			g.visible = false
	var from := float(step - 1) / float(STAGED_STEPS + 1)
	var span := 1.0 / float(STAGED_STEPS + 1)
	var k: int = Rules.STAGED_LOAD_FIRST_GROUPS
	var i := 0
	while true:
		var t0 := Time.get_ticks_usec()
		for j in range(i, mini(i + k, order.size())):
			for g in groups[order[j]]:
				if is_instance_valid(g):
					g.visible = true
		i += k
		load_progress = maxf(load_progress, from + span * (float(mini(i, order.size())) / float(maxi(order.size(), 1))))
		await get_tree().process_frame
		if i >= order.size():
			break
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > Rules.STAGED_LOAD_FRAME_MS:
			k = maxi(1, k / 2)
		elif ms < Rules.STAGED_LOAD_FRAME_MS / 3.0:
			k *= 2
	load_progress = maxf(load_progress, from + span)
	_lm("%s_drawn(%d)" % [label, order.size()])


func _draw_sig(g: GeometryInstance3D) -> String:
	## STAGED LOAD: what a mesh needs compiled to draw - its kind and its materials (distinct materials may share a shader:
	## the grouping is only ever finer than the compiles, never coarser).
	var sig := g.get_class()
	if g.material_override != null:
		return "%s|%d" % [sig, g.material_override.get_instance_id()]
	var mesh: Mesh = null
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
		mesh = (g as MultiMeshInstance3D).multimesh.mesh
	if mesh == null:
		return sig
	for s in range(mesh.get_surface_count()):
		var m: Material = (g as MeshInstance3D).get_active_material(s) if g is MeshInstance3D else mesh.surface_get_material(s)
		sig += "|%d" % (m.get_instance_id() if m != null else 0)
	return sig


func _hold_fresh() -> Array[Node]:
	## STAGED LOAD: the children added since the last call, held (process off: no view runs on a half-built world).
	var fresh: Array[Node] = []
	for c in get_children():
		if _held_ids.has(c.get_instance_id()) or c is VersusScreen or c is PerfProfile or c is FullscreenGate:
			continue
		_held_ids[c.get_instance_id()] = true
		fresh.append(c)
		if c.process_mode == Node.PROCESS_MODE_INHERIT:
			c.process_mode = Node.PROCESS_MODE_DISABLED
			_held.append(c)
	return fresh


var _pace_us := 0                                     # STAGED LOAD: when the build last drew a frame (_pace)


func _pace() -> void:
	## STAGED LOAD (0.23.5, Daniele's phone on 0.23.4: "the versus wallpaper fires for a frame, the rest is freeze" - the map
	## build was still one block there): MapBuilder.build3 calls this before each node and edge; once Rules.STAGED_LOAD_FRAME_MS
	## of work has piled up, the pieces so far are held and a frame is drawn (the card animates, their shaders compile now).
	if (Time.get_ticks_usec() - _pace_us) / 1000.0 < Rules.STAGED_LOAD_FRAME_MS:
		return
	_hold_fresh()
	await get_tree().process_frame
	_pace_us = Time.get_ticks_usec()


func _release_held() -> void:
	## STAGED LOAD: the world is whole - every held view processes again.
	for c in _held:
		if is_instance_valid(c) and c.process_mode == Node.PROCESS_MODE_DISABLED:
			c.process_mode = Node.PROCESS_MODE_INHERIT
	_held.clear()


func _lm(label: String) -> void:
	## LOAD TRACE: a step of an online round's build (Net.load_marks; tests/staged_load_probe).
	if online:
		Net.load_mark(label)
		if label == "warmup_done" and OS.has_feature("web") and not Net.dedicated:   # 0.23.5: the trace rides in the telemetry
			Telemetry.event("perf", {"where": "load_trace", "time_s": snappedf(Time.get_ticks_msec() / 1000.0, 1.0),   # (Daniele's phone: which step froze?)
					"extra": {"trace": Net.load_summary(), "map": str(map.get("code", "")), "staged": _staged}})


func _start_online() -> void:
	## A room's round (Net): players, plus the AI in empty or dropped seats (host only). The host
	## steps the Sim; guests build the same world from the same seed and render the host's snapshots.
	var info: Dictionary = Net.match_info
	online = true
	mode = str(info["mode"])
	seed_value = int(info["seed"])
	for seat in info["players"]:
		SEAT_FACTIONS[seat] = info["players"][seat]
	LOADOUTS = (info.get("loadouts", {}) as Dictionary).duplicate()   # every seat's, from the host
	HUMAN = Net.local_seat()
	if Net.dedicated:                                  # the server's match host has no seat: view as the first one
		var seats: Array = (info["players"] as Dictionary).keys()
		seats.sort()
		HUMAN = str(seats[0])
	_online_card_pending = not Net.dedicated          # UI: _start_map raises the VERSUS card before building (the round's loading screen)
	await _start_map(str(info["map"]))
	for arg in OS.get_cmdline_user_args():             # tests only (a local relay's --host-arg): a short server round
		if Net.dedicated and arg.begins_with("--match-end="):
			sim.match_hard_end = float(arg.substr(12))
	_lm("world_ready")
	if not Net.dedicated:                              # LOAD TRACE: the steps in the console (the web build's too)
		print("LOAD ", Net.load_summary())
	Net.world_ready(sim, self)
	Net.order_feedback.connect(_on_order_feedback)
	if not Net.dedicated:
		Telemetry.funnel_once("first_online_round")    # PROGRESSION (Alpha 21): the funnel's online step
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
	## Net's lines: the host's answer to this guest's order (shown where that order was given, when it was recent)
	## or a room notice (a seat's drop / reconnect: Hud.toast puts it under that seat's chip).
	if hud == null:
		return
	var notice := msg.begins_with("Seat ")              # Net._notice: drops, reconnects, the room changing hands
	if not notice and int(_last_order[0]) >= 0 and Time.get_ticks_msec() - int(_last_order[2]) < 3000:
		if hud.kind_of(msg) == "warn":                  # a refusal: said where the order was given
			_placed_refusal(str(_last_order[1]), int(_last_order[0]), msg)
		_last_order[0] = -1                             # an accepted order is routine (0.20.6 declutter, as offline)
		return
	hud.toast(msg)


func _placed_refusal(method: String, id: int, msg: String) -> void:
	## A refused order's reason, where it was given: above the skill slot (a cast), at the line (a recall), at the
	## node (everything else) - Hud.toast's line only when the place is gone.
	if method == "cast":
		hud.skill_refusal(id, msg)
	elif method == "recall":
		var h := sim._horde(id)
		if h.is_empty():
			hud.toast(msg)
		else:
			hud.callout_at(Sim.sample(h, float(h["s"]))[0], "line:%d" % id, msg, "warn")
	elif id >= 0 and id < sim.nodes.size():
		hud.callout_node(id, msg, hud.kind_of(msg))
	else:
		hud.toast(msg)


func seat_who(seat: String) -> Dictionary:
	## HUD pass (Daniele, 2026-09-28: "if the user is a human his name needs to be shown in the various screens like
	## versus / match stats etc instead of his faction only"): how every screen names a seat - {name: a human's name
	## ("" where this device doesn't know it), faction: VEX / NULL / ..., tag: an AI's "VETERAN AI", human, you}.
	## Offline your seat is the one human (the account's name, --player-name, else YOU); online every seat a player
	## holds (Net.roster) is human, and only your own name is known here - the room carries no names yet.
	var f := str(sim.factions.get(seat, SEAT_FACTIONS.get(seat, "")))
	var out := {"name": "", "faction": str(UiKit.NAMES.get(f, f.to_upper())), "tag": "", "human": false, "you": seat == HUMAN}
	var humans := []
	if online:
		for id in Net.roster:
			humans.append(Net.seat_of(int(id)))
	elif not demo:
		humans = [HUMAN]
	out["human"] = seat in humans
	if out["human"]:
		if seat == HUMAN:
			out["name"] = _my_name()
		elif online:                                   # NAMES (net-7): the room carries every player's name
			for id in Net.roster:
				if Net.seat_of(int(id)) == seat:
					var nm := Net.name_of(int(id)).to_upper()
					out["name"] = nm if nm.length() <= Rules.HUD_NAME_MAX else nm.substr(0, Rules.HUD_NAME_MAX - 1) + "…"
		return out
	var level := str(Net.ai_seats().get(seat, "")) if online else ai_level
	for a in ais:
		if a.seat == seat:
			level = str(a.level)
	out["tag"] = ("%s AI" % level.to_upper()) if level != "" else "AI"
	return out


func _my_name() -> String:
	## Your display name: --player-name, the account's profile name (its last stored copy when it isn't signed in
	## this run), else YOU - cut at Rules.HUD_NAME_MAX characters.
	var nm := player_name
	if nm == "" and Account.enabled:
		var acct := Account.get_instance()
		nm = acct.player_name
		if nm == "":
			var cf := ConfigFile.new()
			if cf.load(Account.path) == OK:
				nm = str(cf.get_value("session", "name", ""))
	nm = nm.strip_edges().to_upper()
	if nm == "":
		return "YOU"
	return nm if nm.length() <= Rules.HUD_NAME_MAX else nm.substr(0, Rules.HUD_NAME_MAX - 1) + "…"


func restart() -> void:
	if mission:                                        # CAMPAIGN: RESTART / RETRY replays the mission
		_mission_relaunch(mission.key)
		return
	if director:                                       # TUTORIAL: RESTART / TRY AGAIN restages the lesson
		_tutorial_relaunch({"tutorial": director.lesson_id, "first": director.first_launch})
		return
	relaunch = {"map": map_path, "faction": SEAT_FACTIONS[HUMAN], "rival": SEAT_FACTIONS["B"], "ai": ai_level, "mode": mode, "colour": color_choice,
			"loadout": LOADOUTS.get(HUMAN, {})}
	get_tree().reload_current_scene()


func _human_count() -> int:
	## Offline: just you. Online: everyone actually present (EMPTY SEATS fills the rest with AI).
	return Net.present_ids().size() if online else 1


func _rematch_mode_for(m: Dictionary, need: int) -> String:
	## The map's mode that best fits `need` humans (the fewest seats that still covers everyone,
	## AI filling any left over) - "" if none of its modes seats that many.
	var best := ""
	var best_n := 1000000
	for md in (m.get("seats", {}) as Dictionary).keys():
		var n: int = (m["seats"][md] as Array).size()
		if n >= need and n < best_n:
			best = md
			best_n = n
	return best


func _random_rematch_map() -> Dictionary:
	## REMATCH ON A RANDOM MAP (Daniele, 0.19.0): any map fits an offline 1-human game; online, a
	## mode that seats at least every human present, AI filling the rest (EMPTY SEATS).
	var need := _human_count()
	var candidates := []
	for mp in MapPool.battlefield():
		var m := pool_map(mp)                          # AUDIT FIX (B1): parsed once per session
		var md := _rematch_mode_for(m, need)
		if md != "" and MapPool.mode_offered(mp, md):  # 0.23.0: a kept older map only for a mode the new pool lacks
			candidates.append({"map": mp, "mode": md})
	if candidates.is_empty():                           # never happens (every map seats at least 1v1), but be safe
		return {"map": map_path, "mode": mode}
	return candidates[randi() % candidates.size()]


func rematch_random() -> void:
	## The results screen's REMATCH ON A RANDOM MAP: same settings otherwise. Online: only the host
	## picks (Net.request_rematch()'s vote-then-launch still runs the same way for everyone else).
	if online:
		if Net.is_host():
			var pick := _random_rematch_map()
			Net.map_path = str(pick["map"])
			Net.mode = str(pick["mode"])
		elif Net.can_control():                        # a server room's owner: the host applies the pick (and the vote)
			var pick := _random_rematch_map()
			Net.propose_rematch(str(pick["map"]), str(pick["mode"]))
			return
		Net.request_rematch()
		return
	var pick := _random_rematch_map()
	map_path = str(pick["map"])
	mode = str(pick["mode"])
	restart()


# --- AUDIT FIX (2026-09-28, audit-client B1): the battlefield pool's maps parsed once per session ---
static var _pool_maps := {}                      # path -> the parsed map (shared, read-only: the menu and REMATCH)


static func pool_map(path: String) -> Dictionary:
	## A pool map's parsed JSON for the menu's cards and REMATCH ON A RANDOM MAP - read-only, never handed to a Sim
	## (a match loads its own copy: MapBuilder.load_map). Parsing all 88 cost ~37 ms (desktop) on every menu entry.
	if not _pool_maps.has(path):
		_pool_maps[path] = MapBuilder.load_map(path)
	return _pool_maps[path]


# --- AUDIT FIX (2026-09-28): the player's own match settings around online rounds ---
static func keep_own_settings() -> void:
	## Offline (main._ready, the SETUP toggles): remember the player's own LAST STAND / ABILITIES / HIDDEN COUNTS,
	## so they come back after a room's round has written the room's into Rules.
	if room_rules:
		return
	own_settings = {"last_stand": Rules.last_stand, "abilities_on": Rules.abilities_on,
			"hide_enemy_counts": Rules.hide_enemy_counts}


static func restore_own_settings() -> void:
	## After a room's round (LEAVE ROOM, back offline): the default numbers again - no balance preset, the default
	## forge bonus and speeds (Net._launch sets them for the round) - and the player's own toggles. A no-op while no
	## room wrote anything, so the Debug panel's offline tuning still carries to the next match.
	if not room_rules:
		return
	room_rules = false
	Rules.apply_balance("")
	Rules.forge_bonus = Rules.FORGE_BONUS_DEFAULT
	Rules.deck_speed = Rules.DECK_SPEED_DEFAULT
	Rules.node_speed_mult = Rules.NODE_SPEED_MULT_DEFAULT
	Rules.door_rate = Rules.DOOR_RATE_DEFAULT
	Rules.node_fight_mult = Rules.NODE_FIGHT_MULT_DEFAULT
	if not own_settings.is_empty():
		Rules.last_stand = bool(own_settings["last_stand"])
		Rules.abilities_on = bool(own_settings["abilities_on"])
		Rules.hide_enemy_counts = bool(own_settings["hide_enemy_counts"])
# --- end AUDIT FIX ---


func to_menu(page := "") -> void:
	## `page` (UI, Alpha 21: the result screen's CONTINUE / CHANGE LOADOUT): open that menu page instead of MAIN.
	if started and not sim.over and director == null and mission == null:   # PROGRESSION (Alpha 21): left early
		_telemetry_match(true)
		Telemetry.perf_event("match")
	if mission:                                        # CAMPAIGN: leaving a mission returns to the campaign page
		_mission_leave(page)
		return
	if director:                                       # TUTORIAL §7: leaving a lesson marks the tutorial offered, and the
		_tutorial_leave({"menu": page} if page != "" else {})   # menu gets your own faction, AI level and loadout back (AUDIT FIX)
		return
	if online:                                         # LEAVE ROOM: the room closes for us
		Net.leave()
	relaunch = {"faction": SEAT_FACTIONS[HUMAN], "rival": SEAT_FACTIONS["B"], "ai": ai_level, "mode": mode, "colour": color_choice,
			"loadout": LOADOUTS.get(HUMAN, {})}
	if page != "" and not online:                      # UI: "play" (CONTINUE) / "armies" (CHANGE LOADOUT)
		relaunch["menu"] = page
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ world
func _apply_quality() -> void:
	## Phones: no shadows, no MSAA. (AUDIT FIX: the old 0.75 3D render scale is gone - PerfProfile renders every
	## profile at full resolution, the unfiltered upscale gave the "minecraft" steps; a phone on FULL got it back.)
	if mobile:
		sun.shadow_enabled = false
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
	var bottom := 12.0
	# Alpha 21 (iPhone 14 Pro home-screen app): on the web the safe-area insets come from the page (CSS env(),
	# web/viewport-fix.js) - the notch / Dynamic Island side and the home indicator stay clear of the HUD
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js = JavaScriptBridge.eval("window.OozeViewport ? OozeViewport.safe().concat(OozeViewport.size()).join(',') : ''", true)
		var f := str(js).split(",")
		if f.size() == 6 and float(f[4]) > 0.0:
			var kw := vp.x / float(f[4])                 # CSS px -> viewport units
			left = maxf(float(f[0]) * kw, left)
			top = maxf(float(f[1]) * kw, top)
			right = maxf(float(f[2]) * kw, right)
			bottom = maxf(float(f[3]) * kw, bottom)
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
	margins = Vector4(left, top, right, bottom)


func _build_world() -> void:
	sun = Scenery.build_environment(self, mobile)      # sky light, lights, glow and fog (scenery.gd)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true


func _fit_camera() -> void:
	## Fits the whole map - every platform rim and the badge hanging under it - inside the screen area
	## the HUD leaves free (right of the send panel, below the top bar, above the bottom strip), by
	## projecting those points and correcting distance and aim until they fit (Alpha 14 playtest:
	## "the HUD should never overlap a corridor or a platform"). The player may zoom in from it (pinch / wheel,
	## _zoom_at) but never out past it; the Last Stand closes in on the nodes still standing (_collapse_zoom).
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
	_view_fit = [cam_target, cam_dist]
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for n in sim.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	_map_half = ((hi - lo) / 2.0).abs() + Vector3(Rules.R, 0, Rules.R)
	_place_camera()


func _zoom_enabled() -> bool:
	## Player zoom: normal matches, missions and online; not lessons (the coach's spotlight), staged scenarios,
	## thumbnails, or while the Last Stand eases in.
	return director == null and scenario_focus == Vector3.INF and thumb_path == "" and not _view_fit.is_empty() 			and _zoom_t < 0.0


func _zoom_at(from: Vector2, to: Vector2, factor: float) -> void:
	## Zooms by `factor` (> 1 closer) keeping the ground under screen point `from` under `to` (a pinch's midpoint
	## moves too: two fingers also pan), clamped to Rules.CAM_ZOOM_MIN..1 of the fitted view (_view_fit).
	var g := _ground(from)
	var far: float = _view_fit[1]
	cam_dist = clampf(cam_dist / maxf(factor, 0.01), far * Rules.CAM_ZOOM_MIN, far)
	_place_camera()
	var h := _ground(to)
	if g != Vector3.INF and h != Vector3.INF:
		cam_target += Vector3(g.x - h.x, 0.0, g.z - h.z)
	var home: Vector3 = _view_fit[0]
	var room := 1.0 - cam_dist / far                  # 0 at the fitted view: exactly the fit again
	cam_target.x = clampf(cam_target.x, home.x - _map_half.x * room, home.x + _map_half.x * room)
	cam_target.z = clampf(cam_target.z, home.z - _map_half.z * room, home.z + _map_half.z * room)
	_place_camera()                                   # hud.sync lets the badges follow, then re-lays them


func _pinch_move() -> void:
	var pts := touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var d := a.distance_to(b)
	var mid := (a + b) / 2.0
	if not _pinch.is_empty() and d > 1.0 and float(_pinch["d"]) > 1.0 and _zoom_enabled():
		_zoom_at(_pinch["mid"], mid, d / float(_pinch["d"]))
	_pinch = {"d": d, "mid": mid}


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
	if use_hud and mission_overlay:                    # CAMPAIGN: the map fits under the objective strip too
		top = maxf(top, mission_overlay.strip_bottom() + 6.0)
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
	## distance (Daniele, 0.19.0: "all eyes on winner" - the zoom cap is gone: it closes in until the
	## survivors fill the view, however few are left), never wider than the start distance.
	var alive := sim.nodes.filter(func(n): return not sim.collapsed.get(n["id"], false))
	if alive.is_empty():
		return [_start_fit[0], _start_fit[1], _base_pitch]
	var gone := 1.0 - float(alive.size()) / float(maxi(sim.nodes.size(), 1))
	var pitch := lerpf(_base_pitch, maxf(COLLAPSE_PITCH_MIN, _base_pitch - COLLAPSE_PITCH_DROP), gone)
	var keep := cam_pitch
	cam_pitch = pitch                                 # _fit_nodes measures at the current pitch
	var fit := _fit_nodes(alive)
	cam_pitch = keep
	fit[1] = minf(fit[1], _start_fit[1])
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
			_view_fit = [_zoom_to[0], _zoom_to[1]]     # the player zoom now widens back to the survivors' view
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
		"notices":                                      # HUD pass: the normal view (--focus=N: a close-up)
			if focus_node >= 0 and focus_node < sim.nodes.size():
				scenario_focus = sim.nodes[focus_node]["pos"]
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
		"hud19draw":
			# 0.19.0 HUD contact sheet: the DRAW results screen alone (sim.draw_line), staged at once -
			# no timing race with a pause mid-match (see "hud19"'s own note on that).
			sim.draw_line = str(Rules.DRAW_LINES[0])
		"hud19":
			# 0.19.0 HUD contact sheet (--map=res://maps4/A-02-switchback-foundry.json): 7 nodes, one
			# relay (node 4, "retract"), one strategic centre (node 2) - every node kind's inspector,
			# LAUNCH's reach highlight, the relay-outcome preview, a faked Last Stand warning and the
			# DRAW screen, timed by _run_scenario (no AI, no real time needed).
			sim.nodes[0]["owner"] = HUMAN
			sim.nodes[0]["units"] = 120.0
			sim.nodes[1]["owner"] = HUMAN
			sim.nodes[1]["units"] = 200.0
			sim.nodes[1]["structure"] = "vat"
			sim.nodes[1]["tier"] = 2
			sim.nodes[3]["owner"] = HUMAN
			sim.nodes[3]["units"] = 90.0
			sim.nodes[3]["structure"] = "machinegoon"
			sim.nodes[3]["tier"] = 2
			sim.nodes[3]["allies"]["B"] = 40.0                # a staged ally share: halo ring + EJECT + "total + own"
			sim.nodes[3]["arrivals"] = ["B"]
			sim.nodes[2]["owner"] = HUMAN
			sim.nodes[2]["units"] = 300.0
			sim.nodes[2]["tier"] = 4                          # special: T4 vat only
			sim.nodes[4]["owner"] = HUMAN
			sim.nodes[4]["units"] = 260.0
			scenario_focus = sim.nodes[1]["pos"]
		"hud19b":
			# 0.19.0 follow-up (double-tap SWITCH + its visibility pass): node 4's relay, ready at first
			# (the SWITCH button's amber ring, the badge's ready glow / cue), then fired exactly as a
			# double-tap now does (sim.fire_relay) to show the warning ring + the relay-outcome preview.
			sim.nodes[4]["owner"] = HUMAN
			sim.nodes[4]["units"] = 260.0
			scenario_focus = sim.nodes[4]["pos"]
		"hud192":
			# 0.19.2 contact sheet: node 0 owned normally (the new top bar, 1v1), then node 4 becomes a
			# ready Monster hub (the launch icon + reach area), then every human node is cleared (YOU'RE OUT).
			sim.nodes[0]["owner"] = HUMAN
			sim.nodes[0]["units"] = 140.0
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


func _debug_casts() -> void:
	## POWERS (DEBUG, screenshots): the --cast-at casts that are due (retried each frame until the Sim takes them) and
	## the --aim arming. Offline only; never used by a player.
	for c in _cast_at.duplicate():
		if sim.time < float(c[0]):
			continue
		var seat := str(c[1])
		var slot := str(c[2])
		if slot == "send":                            # --send-at
			var ft := str(c[4]).split(",")
			sim.send(int(ft[0]), int(ft[1]), 1.0)
			_cast_at.erase(c)
			continue
		if not sim.loadouts.has(seat):
			_cast_at.erase(c)
			continue
		sim.loadouts[seat][slot] = str(c[3])
		if slot == "ultimate":
			sim.ult_charge[seat] = 1.0
			sim.ult_since[seat] = 999.0
		else:
			sim.skill_cd[seat][slot] = 0.0
		var t = _debug_target(seat, slot, str(c[4]))
		if t is String or not sim.cast(seat, slot, t):
			if sim.time > float(c[0]) + 30.0:
				print("cast-at: %s gave up (%s)" % [str(c[3]), sim.cast_check(seat, slot, null if t is String else t)])
				_cast_at.erase(c)
			continue
		print("cast-at t=%.1f %s %s -> %s" % [sim.time, seat, str(c[3]), str(t)])
		_cast_at.erase(c)
		if not _cast_shots.is_empty():
			shots.clear()
			for o in _cast_shots:
				shots.append(sim.time + float(o))
			_cast_shots = []
		if _cast_zoom > 0.0:
			var at: Vector3 = sim._target_pos(str(Rules.SKILLS[str(c[3])]["target"]), t, seat)
			scenario_focus = at
			scenario_zoom = _cast_zoom
			cam_target = at
			cam_dist = _cast_zoom
			_place_camera()
	if not _aim.is_empty() and sim.time >= float(_aim[0]) and hud and hud.dock:
		var slot := str(_aim[1])
		var i := SkillDock.SLOTS.find(slot)
		sim.loadouts[HUMAN][slot] = str(_aim[2])
		sim.skill_cd[HUMAN][slot] = 0.0
		hud.dock.press_slot(i)
		if str(_aim[3]) != "" and hud.dock.armed == i:
			hud.dock.pick(int(_aim[3]))
		_aim = []


func _debug_target(seat: String, slot: String, spec: String):
	## POWERS (DEBUG): a --cast-at target: as given, or the Sim's candidate nearest the view's centre ("" = none yet).
	if spec != "auto":
		if "," in spec:
			var ab := spec.split(",")
			return [int(ab[0]), int(ab[1])]
		return int(spec)
	var id := sim.skill_id(seat, slot)
	var kind := str(Rules.SKILLS[id]["target"])
	var cands := sim.targets_for(seat, slot)
	if cands.is_empty():
		return ""
	var best = cands[0]
	var best_d := INF
	for c in cands:
		var p: Vector3 = sim._target_pos("node" if kind == "node_pair" else kind, c, seat)
		var d := Vector2(p.x - cam_target.x, p.z - cam_target.z).length()
		if kind == "own_line":                        # a line: the one with the longest way still to go
			var h := sim._horde(int(c))
			d = -(float(h["L"]) - float(h["s"]))
		if d < best_d:
			best_d = d
			best = c
	if kind == "node_pair":
		var exits := sim.portal_exits(int(best))
		return [int(best), int(exits[0])] if not exits.is_empty() else ""
	return best


func _run_scenario() -> void:
	if scenario == "hud19draw":
		# no sim.time gate: show_end() pauses the match (freezes sim.time) - waiting for a later
		# threshold would never arrive, so this fires on the very first tick instead.
		if not _scenario_done:
			_scenario_done = true
			hud.show_end("")
		return
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
		"hud19":
			var phase: int = mini(int(sim.time), 5)
			if phase != _hud19_phase:
				_hud19_phase = phase
				hud.overlay.hover_relay = -1
				monster_from = -1
				match phase:
					0:
						hud.inspect(1, cam)                    # common: VAT (UPGRADE / MACHINEGOON)
						scenario_focus = sim.nodes[1]["pos"]
					1:
						sim.nodes[4]["structure"] = ""          # relay: empty socket (SWITCH / LASER / FORGE / MONSTER HUB)
						hud.inspect(4, cam)
						hud.overlay.hover_relay = 4             # relay-outcome preview: SWITCH held
						scenario_focus = sim.nodes[4]["pos"]
					2:
						hud.inspect(2, cam)                    # special: T4 vat only
						scenario_focus = sim.nodes[2]["pos"]
					3:
						sim.nodes[4]["structure"] = "monster_hub"
						sim.nodes[4]["monster_ready_t"] = 0.0
						hud.inspect(4, cam)
						monster_from = 4                        # LAUNCH armed: the reach ring highlight
						scenario_focus = sim.nodes[4]["pos"]
					4:
						hud.close_inspector()                  # Last Stand danger symbol (faked: no real timer run)
						sim.last_stand_active = true
						sim.last_stand_warn[3] = true
						sim.last_stand_queue = [3]
						sim.last_stand_warn_t = 6.0
						scenario_focus = sim.nodes[3]["pos"]
					5:
						sim.draw_line = str(Rules.DRAW_LINES[0])   # the results screen's DRAW call-out
						hud.show_end("")
				_fit_camera()
		"hud19b":
			var phase: int = mini(int(sim.time), 1)
			if phase != _hud19_phase:
				_hud19_phase = phase
				match phase:
					0:
						hud.inspect(4, cam)                     # ready: the amber SWITCH ring, badge glow + cue
					1:
						sim.fire_relay(4)                        # exactly what double-tap now does (main.gd)
						hud.inspect(4, cam)                      # re-synced: the warning ring + outcome preview
				_fit_camera()
		"hud192":
			var phase: int = mini(int(sim.time), 2)
			if phase != _hud19_phase:
				_hud19_phase = phase
				match phase:
					1:
						sim.nodes[4]["owner"] = HUMAN            # the Monster hub: ready at once (icon + reach area)
						sim.nodes[4]["structure"] = "monster_hub"
						sim.nodes[4]["units"] = 260.0
						sim.nodes[4]["monster_ready_t"] = 0.0
						hud.inspect(4, cam)
						scenario_focus = sim.nodes[4]["pos"]
					2:
						hud.close_inspector()
						for n in sim.nodes:                      # YOU'RE OUT: every node of yours, gone
							if n["owner"] == HUMAN:
								n["owner"] = ""
						scenario_focus = Vector3.INF
				_fit_camera()
		"declutter":
			# 0.20.6 (Daniele's HUD declutter notes): phase 0 is a quiet moment; phase 1 piles on every
			# declutter case at once (two toasts, a capture floater, the Last Stand status line) to show
			# they now share a small top-right corner and a node label instead of covering the map.
			var phase: int = mini(int(sim.time), 1)
			if phase != _hud19_phase:
				_hud19_phase = phase
				match phase:
					1:
						hud.callout_node(3, "FORGE LOST", "warn")
						hud.callout_node(1, "HANDED OVER", "warn", "B")
						fx.floater(sim.nodes[2]["pos"], "+ CAPTURED", Rules.seat_color(HUMAN))
						sim.last_stand_active = true
						sim.last_stand_warn[3] = true
						sim.last_stand_queue = [3]
						sim.last_stand_warn_t = 6.0
				_fit_camera()
		"notices":
			# HUD pass (Daniele's "option A"): every placed message at once - phase 1 the map callouts (a monster
			# launched at you, a deck's kicked units, forge online / lost, a handover, stored troops sent home),
			# a skill refusal above its slot and the Last Stand line's pulse; phase 2 (with --focus=N) a launch at a
			# node off screen, which points there from the screen edge.
			var phase: int = mini(int(sim.time), 2)
			if phase != _hud19_phase:
				_hud19_phase = phase
				var mine := sim.nodes.filter(func(n): return n["owner"] == HUMAN)
				var theirs := sim.nodes.filter(func(n): return n["owner"] != HUMAN and n["owner"] != "")
				var free := sim.nodes.filter(func(n): return n["owner"] == "")
				match phase:
					1:
						if not mine.is_empty():
							hud.callout_node(mine[0]["id"], "MONSTER INCOMING", "warn", "B")
						if not theirs.is_empty():
							hud.callout_node(theirs[0]["id"], "FORGE ONLINE  +%d%% ATTACK" % roundi(Rules.forge_bonus * 100.0), "warn", str(theirs[0]["owner"]))
						if free.size() >= 2:
							hud.callout_node(free[0]["id"], "HANDED OVER TO YOU", "good")
							hud.callout_node(free[1]["id"], "STORED TROOPS SENT HOME", "info")
						if not sim.edges.is_empty():
							var line: Array = sim.deck_line(sim.edges.size() / 2)
							hud.callout_at(line[line.size() / 2], "deck", "MONSTER KICKED 12 OFF", "warn")
						if hud.dock.visible:
							hud.skill_refusal(1, "Pick a deck")
						sim.last_stand_active = true
						sim.last_stand_method = "inward"
						hud.pulse_last_stand("the rim falls first - hold the centre")
					2:
						var far := -1
						var best := -1.0
						for n in sim.nodes:                   # the node farthest from the close-up
							var d := (n["pos"] as Vector3).distance_to(scenario_focus) if scenario_focus != Vector3.INF else 0.0
							if d > best:
								best = d
								far = n["id"]
						if far >= 0:
							hud.callout_node(far, "MONSTER INCOMING", "warn", "B")
				_fit_camera()
		"monlaunch":
			# 0.20.1 (Daniele's online playtest: "i couldn't figure how to send the monster"): the fix in
			# one sheet - phase 0 is the ready hub with its icon, untouched; phase 1 is the same tap that
			# now arms LAUNCH directly (hud.is_ready_hub, main.gd's tap handler), reach ring and all.
			var phase: int = mini(int(sim.time), 1)
			if phase != _hud19_phase:
				_hud19_phase = phase
				match phase:
					0:
						sim.nodes[4]["owner"] = HUMAN
						sim.nodes[4]["structure"] = "monster_hub"
						sim.nodes[4]["units"] = 260.0
						sim.nodes[4]["monster_ready_t"] = 0.0
						scenario_focus = sim.nodes[4]["pos"]
					1:
						monster_from = 4                        # the tap: LAUNCH armed, reach ring + lit targets
						scenario_focus = sim.nodes[4]["pos"]
				_fit_camera()
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
	if online and not Net.started:                    # (the waiting text in the middle says why - HUD pass)
		return false
	if online and not Net.is_host():
		Net.order(method, id, args)
		_last_order = [id, method, Time.get_ticks_msec()]   # the host's answer shows at this order's place
		return true
	if director:                                       # TUTORIAL: an order that would wreck the lesson's staging
		var why := director.allow(method, id, args)
		if why != "":
			director.say(why)
			return false
	var r := perform(HUMAN, method, id, args)
	if director:
		director.on_action(method, id, args, r[0])
		if not r[0] and str(r[1]) != "" and not hud.shows("notices"):
			director.say(str(r[1]))                   # before L3 the refusals speak on the coach card
	# 0.20.6 declutter (Daniele: "remove all notices of things like send... better is in game text"): an
	# accepted order is routine (drag preview / node badges / floaters already show it); only a refusal
	# needs a word, since nothing else on screen explains why nothing happened - HUD pass: said where the order was
	# given (the node, the line, the skill slot), never in a box.
	if not r[0] and str(r[1]) != "" and hud.shows("notices"):
		_placed_refusal(method, id, str(r[1]))
		Sfx.play_ui("error")                          # SOUND: a refused order
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
	if method == "cast":                               # SKILLS 2.0: id = slot index (0 active, 1 map, 2 ultimate)
		var slot: String = ["active", "map", "ultimate"][id] if id >= 0 and id <= 2 else ""
		var target = args.get("target", null)
		var why := sim.cast_check(seat, slot, target) if slot != "" else "No such slot"
		if why != "":
			return [false, why]
		var sid := sim.skill_id(seat, slot)
		sim.cast(seat, slot, target)
		return [true, "%s cast" % Rules.SKILLS[sid]["name"]]
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
				return [true, "Relay fired - switching in %d s, then %d s cooldown" % [int(Rules.RELAY_WARNING), int(Rules.relay_cooldown(str(n["relay"])))]]
			return [false, "Relay on cooldown" if n["relay_cd"] > 0.0 else "Relay is already switching"]
		"upgrade":
			var cost := sim.upgrade_cost(n)
			if sim.upgrade_structure(id):
				return [true, "Upgrade started - %d units, %d s" % [Rules.shown(cost), int(Rules.BUILD_SECONDS)]]
			elif n["build_kind"] != "":
				return [false, "Construction already in progress"]
			elif n["attachment"] == "cannon" and n["cannon_tier"] >= 3:
				return [false, "Laser tower has no upgrades"]
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
		"build", "launch_monster", "eject":
			# Structures 2.1 (0.19.0): offline runs the order straight through the Sim, checked and
			# reported exactly like net.gd already does for guests (Net._execute -> sim.structure_order).
			return sim.structure_order(seat, method, id, args)
	return [false, ""]


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if perf_on:
		_perf(delta)
	Telemetry.frame(delta, started, _telemetry_page())   # PROGRESSION (Alpha 21): frame times for the perf event
	if not started:
		return
	# --- SERVER HOST (Alpha 21): step the Sim and the AI, hand the fx events to the guests, draw nothing ---
	if Net.dedicated:
		if Net.is_host() and Net.started:
			var ddt := minf(delta, 0.05)
			for ai in ais:
				ai.think(sim, ddt)
			sim.step(ddt)
		Net.push_effects(sim.fx_events)
		sim.fx_events.clear()
		return
	# --- end SERVER HOST ---
	if get_viewport().get_visible_rect().size != _fitted_size:
		_on_resized()
	var dt := minf(delta, 0.05)
	_flush_inspect()
	if online and Net.started and not hud.callouts.find("wait").is_empty():
		hud.set_waiting([])                           # HUD pass: every player loaded - the round is on
	if online:                                    # the host's Sim is the only simulation (Net)
		if Net.is_host() and Net.started:
			for ai in ais:
				ai.think(sim, dt)
			sim.step(dt)
	elif not paused:
		var sdt := dt
		if director:                                   # TUTORIAL: the director first, then the Sim at its scale
			sdt = _tutorial_step(dt)
		for ai in ais:
			ai.think(sim, sdt)
		if scenario != "":
			_run_scenario()
		if not _cast_at.is_empty() or not _aim.is_empty():   # POWERS (DEBUG): --cast-at / --aim
			_debug_casts()
		sim.step(sdt)
		if mission:                                    # CAMPAIGN: the objective after the Sim's step
			mission.step(sdt)
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
	# --- 0.19.0 views --- monsters and their hubs (MonsterView reads this frame's fx events before they are
	# drained below), each seat's faction for Cosmetics, and the --stage=monster|guns|vats:<look> debug moments
	var monster_view := get_node_or_null("MonsterView") as MonsterView
	if monster_view == null:
		Cosmetics.set_factions(sim.factions)
		monster_view = MonsterView.new()
		monster_view.name = "MonsterView"
		add_child(monster_view)
		monster_view.setup(self, sim, vis, combat)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--stage=") and not online:
				MonsterView.stage(self, arg.substr(8))
	MonsterView.stage_tick(self)
	monster_view.sync(dt, cam)
	# --- end 0.19.0 views ---
	if online:
		Net.push_effects(sim.fx_events)              # host: the guests see the same bursts and falls
	for ev in sim.fx_events:
		if director:
			director.on_event(ev)
		if mission:                                   # CAMPAIGN
			mission.on_event(ev)
		fx.handle(ev)
		skill_fx.handle(ev)
		Sfx.on_fx(ev)                                 # SOUND: the same events (a guest's come from the host through Net)
		match ev["type"]:
			"skill":                                  # a rival's skill that touches you: a callout there (SkillDock.on_event)
				hud.skill_event(ev)
			"last_stand":
				# 0.20.13 (Daniele's online co-op playtest: "last stand still fills the whole screen"): this
				# was the culprit - a 44 pt two-line banner held 5 s dead centre. The status line already
				# says LAST STAND continuously right under the top bar, so the one-time announcement is that
				# line's own pulse now (HUD pass: no toast), saying how the method falls meanwhile; the per-node
				# danger symbols still carry the actual warning.
				var how := {"inward": "the rim falls first - hold the centre", "outward": "the centre falls first - hold the rim",
						"chaos": "nodes fall in a hidden order - your home last"}
				if hud.shows("status_line"):
					hud.pulse_last_stand(str(how.get(ev["method"], "")))
			# 0.20.6 declutter (Daniele: "too many notifications and many notifications cover the map...
			# remove all notices of things like send and capture"): VERY LAST STAND repeats the status
			# line (H5/top bar), the node's own falls are the danger symbols, and relay switches are
			# visible on the relay itself - none of those need a toast of their own any more. "fling" /
			# "fall" are ordinary battle noise already shown by the falling units themselves.
			# HUD pass (Daniele's "option A": "no notification box at all"): each of these is a short callout at the
			# node / deck it is about (Hud.callout_node / callout_at: an edge arrow when it is off screen), the
			# owner's emblem as its icon.
			"monster_launch":                          # Structures 2.1: only a launch aimed at you is worth a word
				var to_you: bool = str(ev["seat"]) != HUMAN and sim.nodes[int(ev["target"])]["owner"] == HUMAN
				if to_you:
					hud.callout_node(int(ev["target"]), "MONSTER INCOMING", "warn", str(ev["seat"]))
			"monster_kick":                            # only your own lines' losses: at the deck, the count adding up
				if str(ev.get("seat_hit", "")) == HUMAN and ev.get("pos") is Vector3:
					var kicked := int(ev.get("shown", 0))
					var place := "kick:%d" % int(ev.get("id", -1))
					var had: Dictionary = hud.callouts.find(place)
					if not had.is_empty():
						kicked += int(had.get("count", 0))
					if kicked > 0:
						hud.callout_at(ev["pos"], place, "MONSTER KICKED %d OFF" % kicked, "warn", str(ev.get("seat", "")))
						var it: Dictionary = hud.callouts.find(place)
						if not it.is_empty():
							it["count"] = kicked
			"forge_lost":                              # red (spec E): the bonus is gone - at the forge it was
				if str(ev.get("seat", "")) == HUMAN:
					var at := int(_forge_node.get(HUMAN, -1))
					if at >= 0:
						hud.callout_node(at, "FORGE LOST · BONUS GONE", "warn")
					else:
						hud.toast("Forge lost - the attack and defence bonus is gone", "warn")
			"hub_destroyed":                           # AUDIT FIX (Daniele, 2026-09-28): one Monster hub per player - a second
				var hid := int(ev.get("node", -1))     # one taken is demolished on capture (a red burst, a word why)
				if hid >= 0 and hid < sim.nodes.size():
					var hpos: Vector3 = sim.nodes[hid]["pos"]
					fx._pulse(hpos, Rules.state_color("warn"), Rules.R + 1.5, 0.9)
					fx.floater(hpos, "HUB DESTROYED", Rules.state_color("warn"))
					if str(ev.get("seat", "")) == HUMAN:
						hud.callout_node(hid, "HUB DESTROYED · ONE PER PLAYER", "warn")
			"eject":                                   # your own eject is a routine order (nothing to say, see node_action);
				if str(ev.get("seat", "")) != HUMAN and sim.allied(str(ev.get("seat", "")), HUMAN):
					hud.callout_node(int(ev["node"]), "STORED TROOPS SENT HOME", "info", str(ev["seat"]))
			"handover":                                 # a silent production-only takeover (no fight to see it by)
				if str(ev.get("seat", "")) == HUMAN:
					hud.callout_node(int(ev["node"]), "HANDED OVER TO YOU", "good")
				elif str(ev.get("from", "")) == HUMAN:
					hud.callout_node(int(ev["node"]), "HANDED OVER TO %s" % hud.seat_label(str(ev["seat"])), "warn", str(ev["seat"]))
			"capture":                                  # (the Sim's fx event for a handover: "handover" is in sim.events)
				if ev.get("handover", false):
					var id := int(ev.get("node", -1))
					if str(ev.get("seat", "")) == HUMAN:
						hud.callout_node(id, "HANDED OVER TO YOU", "good")
					elif str(_took_from.get(id, "")) == HUMAN:
						hud.callout_node(id, "HANDED OVER TO %s" % hud.seat_label(str(ev["seat"])), "warn", str(ev["seat"]))
	sim.fx_events.clear()
	_collapse_zoom(dt)
	fx.selected = selected if drag_from < 0 else drag_from
	fx.sync(dt)
	combat.sync(dt, cam)                          # after Fx: it scales the tier-down's rising model
	skill_fx.sync(dt, cam)                        # after Fx: it hides a demolished deck, whose pieces fall here
	forge_pulse.sync(dt, cam)                     # after both (it pumps the models) and the views (their glows)
	hud.sync(dt, cam)
	if director:
		_coach_sync()
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


# UI (Alpha 21 UI pass): --end-shot - the results / MATCH DETAILS / PAUSE / YOU'RE OUT screens on a real board
func _end_shot(what: String) -> void:
	## The match ends here as `what` says (win: seat A, lose: seat B, draw: nobody), paid into a scratch progress file
	## (never the player's own), so Progression's strip shows real lines; then the screen, saved as end_<what>.png.
	for i in range(60):                                # the board settles (and --ff's end state renders)
		await get_tree().process_frame
	match what:
		"pause":
			hud.pause_menu()
		"out":
			hud.show_out_panel()
		"reconnect":                                   # UI: CONNECTION INTERRUPTED as a guest would see it
			hud.show_reconnect(7)
		"settings":                                    # UI: PAUSE > SETTINGS
			hud.pause_menu()
			hud._pause_settings()
		_:
			Progression.path = "user://progress_shots.cfg"
			Progression.reload_all()
			var w := "" if what == "draw" else (HUMAN if what in ["win", "details"] else "B")
			sim.over = true
			sim.winner = w
			sim.events.append({"t": sim.time, "type": "end", "winner": w, "forced": false, "draw": w == ""})
			hud.close_inspector()
			var info := {"online": false, "ai_level": ai_level}
			rewards = Progression.record_match(Progression.result_from_sim(sim, HUMAN, info))
			rewards["full_pay"] = Progression.full_pay(info)
			rewards["ai_level"] = ai_level
			hud.show_end(w)
			if what == "details":
				hud.show_end_details()
	for i in range(100):                               # the count-ups play out
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "%s/end_%s.png" % [shot_dir if shot_dir != "" else OS.get_user_data_dir(), what]
	get_viewport().get_texture().get_image().save_png(out)
	print("screenshot ", out)
	get_tree().quit()


var _took_from := {}                              # node id -> its owner before the last capture (a handover's callout)


func _on_captured(node_id: int, new_owner: String, _old: String) -> void:
	if mission:                                        # CAMPAIGN: a start node / vat / home lost
		mission.on_captured(node_id, new_owner, _old)
	_took_from[node_id] = _old
	MapBuilder.apply_owner(vis[node_id]["parts"], new_owner)
	# 0.20.6 declutter (Daniele: "remove all notices of things like send and capture - better is in game
	# text coming out of the conquer place"): a fight is already visible on the node itself (fx.gd's
	# capture pulse), so the toast becomes a short rising label there instead of covering the map.
	if not hud.shows("floaters"):                       # TUTORIAL: the reveal set names when this is taught
		return
	var last: Dictionary = sim.fx_events[-1] if not sim.fx_events.is_empty() else {}
	if last.get("handover", false) and int(last.get("node", -1)) == node_id:
		return                                          # a handover: its own callout says it (the fx loop, HUD pass)
	if new_owner == HUMAN:
		fx.floater(sim.nodes[node_id]["pos"], "+ CAPTURED", Rules.seat_color(HUMAN))
	elif _old == HUMAN:
		fx.floater(sim.nodes[node_id]["pos"], "LOST", Color("ff5b5b"))


func _on_forge_online(seat: String, node_id: int, first: bool) -> void:
	## ForgePulse: a forge just came online (built or captured). HUD pass: a callout at the forge, the owner's
	## emblem as its icon; good news in your colour for your side, red for a rival's.
	_forge_node[seat] = node_id                        # where FORGE LOST shows, should this one go
	var kind := "good" if sim.allied(seat, HUMAN) else "warn"
	if first:
		hud.callout_node(node_id, "FORGE ONLINE  +%d%% ATTACK" % roundi(Rules.forge_bonus * 100.0), kind, seat)
	else:                                              # the bonus does not stack (Sim.forge_of)
		hud.callout_node(node_id, "FORGE ONLINE · BONUS KEPT", kind, seat)


func _on_finished_server(winner: String) -> void:
	## SERVER HOST (Alpha 21): the round's end on the room server - a line in the room log (no screen). 0.21.4: no
	## telemetry file (nobody read them, they were never pruned, and rooms ending in the same second overwrote each other).
	print("match over, winner ", winner, " after %.0f s" % sim.time)


func _on_finished(winner: String) -> void:
	var path := Telemetry.save(sim, map.get("code", ""), trace)
	print("match over, winner ", winner, " - telemetry ", path)
	Telemetry.perf_event("match")                      # PROGRESSION (Alpha 21): this match's frame times
	Telemetry.flush_soon()
	hud.close_inspector()
	if director:                                       # TUTORIAL: the lesson's completion screen replaces the results
		return
	if mission:                                        # CAMPAIGN: the mission's result screen replaces the results
		mission.step(0.0)
		return
	_record_progress()                                 # PROGRESSION: XP / SCRAP / challenges, before the results show them
	hud.show_end(winner)
	if not shots.is_empty():                              # automated run: the match ended before the
		var t: float = shots[-1]                          # last shot time - take it now and quit
		shots.clear()
		_take_shot(t, true)


# ------------------------------------------------------------------ PROGRESSION (0.20.1)
var rewards := {}                                  # Progression.record_match's lines for the results screen ({} = none)


func _record_progress() -> void:
	## Pays this device's player for a finished match (PROGRESSION-DESIGN §1: offline first - online rooms are paid
	## here too until accounts exist; then the server pays server-hosted rooms). Never on a headless run (the
	## dedicated match host, tests), a demo / scenario / fast-forward / screenshot run, or a seat that isn't playing.
	rewards = {}
	if Net.dedicated or DisplayServer.get_name() == "headless" or demo or scenario != "" or ff_to > 0.0 or not shots.is_empty():
		return
	if not sim.factions.has(HUMAN):
		return
	var info := {"online": online, "ai_level": "" if online else ai_level}
	var result := Progression.result_from_sim(sim, HUMAN, info)
	result["history"] = Progression.history_entry(sim, HUMAN, _history_info())   # MATCH HISTORY (0.20.5)
	rewards = Progression.record_match(result)
	rewards["full_pay"] = Progression.full_pay(info)
	# 0.20.13: a browser-hosted room (the server was busy or on another version) is never reported online - say so
	# (Net.server_hosted() comes from the server session; until it exists nothing is claimed)
	if online and Net.has_method("server_hosted") and not bool(Net.call("server_hosted")):
		rewards["unranked"] = true
	rewards["ai_level"] = info["ai_level"]
	_telemetry_match(false)                            # PROGRESSION (Alpha 21): the shared match event


func _history_info() -> Dictionary:
	## MATCH HISTORY: what this device knows of the match - the map, mode, room + round (joins the server's record),
	## your name, and which seats were AI (offline: their level; online: the seats no player holds).
	var you := "YOU"
	var acct := Account.get_instance() if Account.enabled else null
	if acct != null and acct.player_name != "":
		you = acct.player_name
	var ai := {}
	if online:
		var humans := []
		for id in Net.roster:
			humans.append(Net.seat_of(int(id)))
		for s in sim.factions.keys():
			if not s in humans:
				ai[s] = "AI"
	else:
		for a in ais:
			ai[a.seat] = a.level
	return {"map": str(map.get("code", "")), "mode": mode, "online": online,
			"room_key": "%s-%d" % [Net.room_code, Net.match_round] if online else "", "names": {HUMAN: you}, "ai": ai}


# --- PROGRESSION: telemetry (Alpha 21, 01 Rules/TELEMETRY-PRIVACY-DESIGN.md) ---
func _start_telemetry() -> void:
	## A player's device only: never the match host, a headless run, a demo / scenario / fast-forward / screenshot run.
	## First launch: the privacy notice (once; over the tutorial's first card or the menu, under the fullscreen gate).
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--region="):               # screenshot / test helper: the EU (opt-in) or elsewhere notice
			Telemetry.force_region = arg.substr(9)
	var shot_run := false
	for arg in args:
		if arg.begins_with("--menu-shot=") or arg.begins_with("--mission-shot=") or arg == "--no-telemetry":
			shot_run = true
	if "--privacy-preview" in args:                   # screenshot helper: the notice on scratch files, never the real ones
		Telemetry.path = "user://privacy_preview.cfg"
		Telemetry.queue_path = "user://privacy_preview_queue.json"
		for p in [Telemetry.path, Telemetry.queue_path]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		Telemetry.forget_all()
		shot_run = false
	if Net.dedicated or DisplayServer.get_name() == "headless" or demo or scenario != "" or ff_to > 0.0 \
			or not shots.is_empty() or thumb_path != "" or shot_run:
		Telemetry.enabled = false
		return
	Telemetry.install()
	if Telemetry.notice_due() and get_node_or_null("PrivacyNotice") == null and not "--no-notice" in args:
		var n := PrivacyNotice.new()
		n.name = "PrivacyNotice"
		add_child(n)


func _telemetry_page() -> String:
	## What is on screen, for the perf sample: a lesson, a mission, a match, or the menu page.
	if director != null:
		return "lesson_%d" % director.lesson_id
	if mission != null:
		return "mission"
	if started:
		return "match"
	if is_instance_valid(menu_layer) and menu_layer.has_method("telemetry_page_name"):
		return str(menu_layer.call("telemetry_page_name"))
	return ""


func _telemetry_match(left_early: bool) -> void:
	if not Telemetry.enabled or not sim.factions.has(HUMAN):
		return
	var hosted := online and Net.has_method("server_hosted") and bool(Net.call("server_hosted"))
	Telemetry.match_event(sim, HUMAN, {"map": str(map.get("code", "")), "mode": mode, "online": online,
			"server_hosted": hosted, "ai_level": "" if online else ai_level, "left_early": left_early,
			"net": Net.call("round_net_stats") if online and Net.has_method("round_net_stats") else {}})   # NET: a guest's connection
# --- end PROGRESSION: telemetry ---


static var _account_started := false


func _start_account() -> void:
	## Every player gets a silent guest account the first time the game is online (Daniele: guest first, link later);
	## never on the match host, a headless run, a demo / scenario / screenshot run. Offline: nothing happens.
	if _account_started or Net.dedicated or DisplayServer.get_name() == "headless" or demo or scenario != "" 			or not shots.is_empty() or not Account.enabled:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-shot=") or arg == "--no-account":
			return
	_account_started = true
	Account.get_instance().start()


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
			_swallow_release = true                   # the first finger's (emulated) release never taps
		_pinch = {}
		return
	if event is InputEventScreenDrag and touches.size() == 2:
		var sd := event as InputEventScreenDrag
		if touches.has(sd.index):
			touches[sd.index] = sd.position
			_pinch_move()                             # pinch zoom + two-finger pan
		return
	if touches.size() >= 2:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if _zoom_enabled() and not hud.pointer_over_ui(mb.position):
				var step := Rules.CAM_WHEEL_STEP * maxf(mb.factor, 1.0) if mb.factor > 0.0 else Rules.CAM_WHEEL_STEP
				_zoom_at(mb.position, mb.position, step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if hud.pointer_over_ui(mb.position):
				if not mb.pressed:                      # a drag released on the HUD is cancelled, never left hanging
					_swallow_release = false
					_end_drag()
				return
			if hud.dock.take_input(mb):                 # SKILLS 2.0: a slot is armed - this tap picks its target
				return
			var hit := _ground(mb.position)
			if monster_from >= 0:                       # LAUNCH armed: drag from the hub, or tap a reachable node
				if mb.pressed:
					_press_pos = mb.position
					_press_time = Time.get_ticks_msec() / 1000.0
				else:
					var target := _node_at(hit, mb.position)
					var hub := monster_from
					monster_from = -1
					if target >= 0 and target != hub:
						node_action("launch_monster", hub, {"to": target})
					drag_mesh.clear_surfaces()
					route_label.visible = false
				return
			if mb.pressed:
				var n := _node_at(hit, mb.position)
				_press_pos = mb.position
				_press_time = Time.get_ticks_msec() / 1000.0
				# RELAY V2 (Daniele: "the tap target should be both the button or the whole node, as relays activate
				# with double tap anyway"): _node_at answers the relay for its button disc too, so a double-tap on the
				# button, the platform or the badge fires it - two taps on either target count as one double-tap
				if n >= 0:
					if sim.nodes[n]["owner"] == HUMAN and n == _tap_node and _press_time - _tap_time < DOUBLE_TAP_WINDOW \
							and hud.shows("relay" if sim.nodes[n]["relay"] != "" else "upgrade"):   # (TUTORIAL: from L2 / L4)
						hud.close_inspector()
						_pending_inspect = -1                   # the first tap's inspector never opens
						_swallow_release = true                 # nor does this tap's release reopen it
						# double-tap (Alpha 11): upgrade what's there - a relay has no upgrade, so its
						# double-tap fires SWITCH instead (Daniele, 0.19.0: "the relays switch is clicked
						# by double tapping relays since we have no upgradable buildings there")
						node_action("switch" if sim.nodes[n]["relay"] != "" else "upgrade", n)
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
						if hud.is_ready_hub(drag_from):
							# 0.20.1 (Daniele's online playtest: "tap IT - the hub / the monster on the hub -
							# the guided send lights up every target"): a ready hub arms LAUNCH straight from
							# the tap, no inspector detour; charging, the inspector still opens as usual.
							hud.close_inspector()
							monster_from = drag_from
							hud.note_monster_hint()
						else:
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
		elif monster_from >= 0:
			_draw_monster_drag(monster_from, hit)


func _end_drag() -> void:
	## Clears the send gesture (and a Monster hub's armed LAUNCH): no source node, no preview line, no
	## route label.
	drag_from = -1
	monster_from = -1
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
		var rb := _relay_button_at(p, screen)          # RELAY V2: a relay's button disc selects its relay
		if rb >= 0:
			return rb
		var b := hud.badge_at(screen)
		if b >= 0:
			return b
	if p == Vector3.INF:
		return -1
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false) or n.get("node_kind", "") == "junction":   # JUNCTION: not tappable
			continue
		if (n["pos"] as Vector3).distance_to(p) <= Rules.R + (2.5 if mobile else 1.0):
			return n["id"]
	return -1


func _relay_button_at(p: Vector3, screen: Vector2) -> int:
	## RELAY V2: the relay whose button tap disc (RelayView.hit_disc: >= Rules.RELAY_HIT_PT on a phone) holds this
	## screen point, or -1. A badge drawn right over the point keeps it (badges are the explicit node targets).
	if screen.x < 0.0 or vis.is_empty() or cam == null:
		return -1
	var rb := RelayView.button_at(cam, sim, vis, screen, p, mobile)
	if rb >= 0 and hud:
		for id in hud.badges:
			var panel: Control = hud.badges[id]["panel"]
			if panel.visible and panel.get_global_rect().has_point(screen):
				return -1
	return rb


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


func _draw_monster_drag(hub: int, hit: Vector3) -> void:
	## Structures 2.1: LAUNCH armed - the reach ring is HudOverlay's job; this is just the aim line,
	## coloured by whether the node under the cursor is in sim.monster_reach(hub).
	drag_mesh.clear_surfaces()
	route_label.visible = false
	if hit == Vector3.INF:
		return
	var a: Vector3 = sim.nodes[hub]["pos"]
	var target := _node_at(hit)
	var ok := target in sim.monster_reach(hub)
	var up := Vector3(0, 1.0, 0)
	var mat := Mats.glow(Rules.seat_color(HUMAN) if ok else Rules.state_color("warn"))
	drag_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	drag_mesh.surface_add_vertex(a + up)
	drag_mesh.surface_add_vertex((sim.nodes[target]["pos"] if target >= 0 else hit) + up)
	drag_mesh.surface_end()
	if target >= 0 and target != hub:
		route_label.text = "SEND MONSTER" if ok else "OUT OF REACH"
		route_label.position = sim.nodes[target]["pos"] + Vector3(0, 6, 0)
		route_label.visible = true


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


# ================================================================== TUTORIAL (TUTORIAL-DESIGN.md §8)
# The lesson hooks, all here: start_tutorial (like start_match), the director stepped before the Sim with its
# time scale (half speed at a relay prompt), the coach overlay fed from the director each frame (card, spotlight,
# hand, completion screens), and the ways out (NEXT / REPLAY / LESSONS / ARMIES / MAIN MENU / SKIP TUTORIAL).
func start_tutorial(lesson_id: int, first := false, faction := "", colour := "") -> void:
	## Entry from the TUTORIAL page, the first launch or a relaunch: lesson `lesson_id` on its map, your colour,
	## VEX against EMBER (Daniele, 0.19.3: one faction for the whole tutorial - your menu faction is kept for
	## afterwards), a scripted rival (no SeatAI; the Training AI in the first match).
	director = TutorialDirector.new(lesson_id)
	director.first_launch = first
	Telemetry.funnel("lesson_start", str(lesson_id))   # PROGRESSION (Alpha 21): the tutorial funnel
	show_out_panel = lesson_id == TutorialDirector.LESSON_COUNT   # no YOU'RE OUT in lessons 0-8: a TRY AGAIN instead
	menu_faction = faction if faction != "" else str(SEAT_FACTIONS[HUMAN])
	if colour != "":
		color_choice = colour
	SEAT_FACTIONS[HUMAN] = TutorialDirector.PLAYER_FACTION
	SEAT_FACTIONS["B"] = TutorialDirector.RIVAL_FACTION
	mode = "1v1"
	menu_ai = ai_level                                 # AUDIT FIX: back on the menu after the lesson
	ai_level = str(director.L.get("ai", ai_level))
	MissionDirector.pin_settings({"last_stand": true, "hide_enemy_counts": false})   # AUDIT FIX: a lesson's own settings
	# (ABILITIES: the lesson's own data, TutorialDirector.begin; restored by main._ready's MissionDirector.restore_settings)
	LOADOUTS = {HUMAN: director.loadout_for()}
	fraction = director.fraction_start(fraction)
	pitch_forced = false
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	var keep_last := last_map_path                    # a lesson map never becomes MAIN MENU's "last map"
	_start_map(TutorialDirector.map_path_for(lesson_id))
	last_map_path = keep_last


func _tutorial_setup() -> void:
	## After the HUD: the reveal set, the coach overlay and its signals.
	if director.lesson_id in [TutorialDirector.FIRST_ID, TutorialDirector.LESSON_COUNT]:
		hud.reveal_all()                              # the tour and the first match: the whole HUD, as in any match
	else:
		hud.reveal(director.reveal_keys(), _tutorial_new_keys())
	coach = CoachOverlay.new()
	coach.set_mobile(mobile)
	coach.set_accent(Rules.seat_color(HUMAN))
	coach.set_first_launch(director.first_launch)
	add_child(coach)
	coach.set_labels({"skip_step": TutorialDirector.line("skip_step"), "restart": TutorialDirector.line("restart"),
			"exit": TutorialDirector.line("exit"), "skip_tutorial": TutorialDirector.line("skip_tutorial")})
	coach.button_pressed.connect(_on_coach_button)
	coach.skip_step.connect(func(): director.skip_step())
	coach.restart.connect(restart)
	coach.exit.connect(to_lessons)
	coach.skip_tutorial.connect(func():                # SKIP TUTORIAL: MAIN, offered marked (to_menu); the lesson counts as
		TutorialDirector.mark_skipped(director.lesson_id)   # skipped - the next one opens, nothing paid (Daniele, 2026-09-28)
		to_menu())
	director.completed.connect(_on_lesson_completed)
	director.handler.connect(coach.handler_mood)      # the handler hops on a pass, droops on a fail
	var step_seen := {"i": director.step_i}
	director.changed.connect(func():                  # a step that adds HUD parts reveals them with a glow
		if director.step_i != int(step_seen["i"]) and not director.uses_inspector():
			hud.close_inspector()                     # an inspector from an earlier step never lingers over this one
		if director.step_i != int(step_seen["i"]) and hud.gated:
			step_seen["i"] = director.step_i
			var before := TutorialDirector.reveal_for(director.lesson_id, director.step_i - 1)
			hud.reveal(director.reveal_keys(), director.reveal_keys().filter(func(k): return not k in before)))


func _tutorial_new_keys() -> Array:
	## The keys this lesson adds to the ones before it (they glow in at the start).
	var before := TutorialDirector.reveal_for(director.lesson_id - 1, 99) if director.lesson_id > 1 else []
	return director.reveal_keys().filter(func(k): return not k in before)


func _tutorial_step(dt: float) -> float:
	## One frame of the lesson: the UI state the steps read, the director, and the Sim's dt at its time scale.
	director.ui_fraction = fraction
	director.ui_inspector = hud.inspector_id
	director.ui_armed = hud.dock.armed if hud.dock else -1
	director.ui_monster_from = monster_from
	director.step(dt)
	return dt * director.time_scale


func _coach_sync() -> void:
	## The coach overlay follows the director: the card when it changed; the spotlight, the hand, the dodge
	## rects and the UI rects every frame (the camera moves in the Last Stand).
	if coach == null or _start_fit.is_empty():        # (the camera is fitted on the second frame)
		return
	if director.version != _coach_version and director.state != "complete":
		_coach_version = director.version
		var c := director.card()
		if c["visible"]:
			coach.show_step(c["header"], c["text"], int(c["dots"]), int(c["dot"]), str(c["button"]))
		else:
			coach.hide_card()
	var want := director.inspect_request()            # the tour opens the inspector on your home, then closes it
	if want >= 0 and hud.inspector_id != want:
		hud.inspect(want, cam)
	elif want < 0 and director.is_tour() and hud.inspector_id >= 0:
		hud.close_inspector()
	var tg := director.target()
	var pts := []
	for id in tg["nodes"]:
		pts.append(cam.unproject_position(sim.nodes[id]["pos"]))
		if _tap_point(id) != sim.nodes[id]["pos"]:     # RELAY V2: the relay's button is lit with its node
			pts.append(cam.unproject_position(_tap_point(id)))
	for q in director.follow_points(tg):              # 0.22.1: lines head to tail, the monster, the decks - never fogged
		pts.append(cam.unproject_position(q))
	var rects := []
	for key in tg["rects"]:
		var r := _tutorial_rect(str(key))
		if r.size != Vector2.ZERO:
			rects.append(r.grow(4.0))
	var radius: float = 30.0
	if not sim.nodes.is_empty():
		var c0: Vector3 = sim.nodes[0]["pos"]
		radius = cam.unproject_position(c0).distance_to(cam.unproject_position(c0 + cam.global_transform.basis.x * Rules.R)) * 1.35 \
				* float(tg.get("radius", 1.0))
	if director.state == "complete":
		pts = []
		rects = []
	var platforms := []                               # the card rather sits over empty sky than over a platform
	for n in sim.nodes:
		if not sim.collapsed.get(n["id"], false):
			platforms.append(cam.unproject_position(n["pos"]))
	coach.set_obstacles(platforms)
	var avoid := []                                   # the banner and the toasts never sit under the card
	if hud.banner.visible:
		avoid.append(hud.banner.get_global_rect())
	avoid.append_array(hud.callouts.rects())          # HUD pass: the placed messages
	coach.set_avoid(avoid)
	coach.spotlight(pts, radius, rects, not tg.get("open", false))   # a watch step: rings without the dim
	_tutorial_gesture()
	_tutorial_label(tg.get("label", []))
	coach.set_finger_down(not touches.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	coach.set_dodge_rects(hud.top_panel.get_global_rect(), hud.side_panel.get_global_rect() if hud.side_panel.visible else Rect2(),
			hud.dock.get_global_rect() if hud.dock.visible else Rect2(), hud.pause_button.get_global_rect())
	hud.extra_ui_rects = coach.ui_rects()
	if director.preview_relay >= 0 and hud.inspector_id == director.preview_relay and director.state == "running":
		hud.overlay.hover_relay = director.preview_relay   # L4: the relay-outcome preview stays up while inspected


func _tutorial_label(pair: Array) -> void:
	## L1's "label" step: the line walking there carries the drag preview's own label (TAKE · units · seconds),
	## so the line the handler talks about is on screen.
	if drag_from >= 0 or monster_from >= 0:
		return
	var show := false
	if pair.size() == 2 and int(pair[1]) >= 0:
		for h in sim.hordes:
			if h["owner"] == HUMAN and int(h["target"]) == int(pair[1]):
				var tn: Dictionary = sim.nodes[int(pair[1])]
				var verb := "reinforce" if tn["owner"] == HUMAN else ("attack" if tn["owner"] != "" else "take")
				var units: float = float(h["units"]) + float(sim.nodes[int(h["route"][0])]["streaming"].get("remaining", 0.0) if h["streaming"] else 0.0)
				var secs := maxf(float(h["L"]) - float(h["s"]), 0.0) / maxf(Rules.move_speed() * sim.stat(HUMAN, "speed"), 0.1)
				route_label.text = "%s · %d units · %d s" % [verb.to_upper(), Rules.shown(units), int(ceil(secs))]
				route_label.position = tn["pos"] + Vector3(0, 6.5, 0)
				show = true
				break
	if show or route_label.has_meta("tutorial"):
		route_label.visible = show
		if show:
			route_label.set_meta("tutorial", true)
		else:
			route_label.remove_meta("tutorial")


func _tutorial_rect(key: String) -> Rect2:
	## A coach rect key on screen: "send:0.25", "action:<NAME>" (Hud.action_rect), "dock:<slot>", "badge:<id>",
	## "send_panel", "top_bar", "dock", "inspector", "handler" (the creature beside the card).
	var parts := key.split(":", true, 1)
	match parts[0]:
		"badge":
			return hud.badge_rect(int(parts[1]))
		"monster_icon":                               # 0.19.2: the monster over your ready hub
			return hud.monster_icon_rect(int(parts[1]))
		"send_panel":
			return hud.side_panel.get_global_rect() if hud.side_panel.visible else Rect2()
		"top_bar":
			return hud.top_panel.get_global_rect()
		"dock":                                       # "dock" = the whole dock, "dock:<slot>" one slot
			if parts.size() > 1:
				return hud.dock_slot_rect(int(parts[1]))
			return hud.dock.get_global_rect() if hud.dock.visible else Rect2()
		"inspector":
			return hud.inspector_rect()
		"handler":
			return coach.handler_rect() if coach else Rect2()
		"send":
			return hud.send_button_rect(float(parts[1]))
		"action":
			return hud.action_rect(parts[1])
	return Rect2()


func _tap_point(id: int) -> Vector3:
	## RELAY V2: where the coach's hand taps node `id` - a relay's button (its visible cue; the node answers a double-tap
	## too), otherwise the node centre.
	var b = vis.get(id, {}).get("relay_button") if vis.has(id) else null
	return b["tap"] if b is Dictionary else sim.nodes[id]["pos"]


func _tutorial_gesture() -> void:
	## The first of the step's gesture alternatives that can be drawn right now (a press needs its button on
	## screen - otherwise the next alternative, e.g. the tap that opens the inspector).
	for g in director.gesture():
		var kind := str(g[0])
		match kind:
			"tap", "double_tap":
				if int(g[1]) >= 0:
					coach.gesture(kind, cam.unproject_position(_tap_point(int(g[1]))))   # RELAY V2: a relay's button
					return
			"drag":
				var a := int(g[1])
				var b := int(g[2])
				if a >= 0 and b >= 0:
					var path := PackedVector2Array()
					for q in director.route_points(a, b):   # AUDIT FIX (B1): the route and its path cached by the director
						path.append(cam.unproject_position(q))
					coach.gesture("drag", cam.unproject_position(sim.nodes[a]["pos"]), cam.unproject_position(sim.nodes[b]["pos"]), path)
					return
			"press":
				var r := _tutorial_rect(str(g[1]))
				if r.size != Vector2.ZERO:
					coach.gesture("press", r.get_center())
					return
			"tap_line":
				var h := sim._horde(int(g[1]))
				if not h.is_empty():
					coach.gesture("tap", cam.unproject_position(Sim.sample(h, maxf(h["s"] - 1.0, 0.0))[0]))
					return
			"tap_deck":
				var line := sim.deck_line(int(g[1]))
				if line.size() >= 2:
					coach.gesture("tap", cam.unproject_position(((line[0] as Vector3) + (line[-1] as Vector3)) / 2.0))
					return
	coach.clear_gesture()


func _on_coach_button(id: String) -> void:
	if director.state == "complete":                   # a completion screen
		var r := director.result
		match id:
			"primary":
				if r.get("final", false):              # PLAY YOUR FIRST MATCH: NEW GAME, Casual preselected
					_tutorial_leave({"ai": "Casual", "menu": "factions"})
				else:
					_tutorial_relaunch({"tutorial": int(r.get("next", 1))})
			"secondary:0":
				if r.get("final", false):              # ARMIES: put the Graduate vat on
					_tutorial_leave({"menu": "cosmetics"})
				else:
					_tutorial_relaunch({"tutorial": director.lesson_id})   # REPLAY
			"secondary:1":
				if r.get("final", false):
					_tutorial_leave({})                   # MAIN MENU
				else:
					to_lessons()
		return
	if director.state == "failed":                     # TRY AGAIN: the same board, fresh crews
		restart()
	elif director.L.get("match", false):
		director.skip_step()                            # the first match's opening card
	else:
		director.press_button()


func _on_lesson_completed(r: Dictionary) -> void:
	## LESSON COMPLETE / TRAINING COMPLETE instead of the results screen (§6). The tour goes straight on to L1.
	Telemetry.funnel("lesson_done", str(director.lesson_id),   # PROGRESSION (Alpha 21): the tutorial funnel
			{"seconds": int(r.get("time", sim.time))})
	if r.get("tour", false):
		_tutorial_relaunch({"tutorial": 1, "first": director.first_launch})
		return
	paused = true
	hud.close_inspector()
	_end_drag()
	if coach == null:
		return
	coach.hide_card()
	if r.get("final", false):
		var lines := []
		if r.get("relay_kill", false):
			lines.append(TutorialDirector.final_kill_line(int(r.get("kill_units", 0))))
		var third := Progression.third_skill_line()        # TUTORIAL + PROGRESSION: above the Graduate vat line
		if third != "":
			lines.append(third)
		if r.get("graduate", false):
			lines.append(TutorialDirector.line("final_reward"))
			lines.append(TutorialDirector.line("final_reward_line"))
		else:
			lines.append(TutorialDirector.line("final_locked"))
		coach.show_training_complete(TutorialDirector.line("final_title"), lines, TutorialDirector.line("final_play"),
				[TutorialDirector.line("final_armies"), TutorialDirector.line("final_menu")],
				{"unlocked": r.get("graduate", false), "title": "GRADUATE VAT", "faction": SEAT_FACTIONS[HUMAN],
				"scrap": int(r.get("scrap", 0))})              # TUTORIAL + PROGRESSION
	else:
		var lines: Array = (r.get("lines", []) as Array).duplicate()
		lines.append("%s · %d:%02d" % [str(r.get("title", "")), int(r.get("time", 0.0)) / 60, int(r.get("time", 0.0)) % 60])
		if r.get("skipped", false):                    # AUDIT FIX (Daniele, 2026-09-28): a skip doesn't complete it
			lines.append(TutorialDirector.line("skipped_note"))
		coach.show_complete(TutorialDirector.line("lesson_complete"), lines, TutorialDirector.line("next"), [TutorialDirector.line("replay"), TutorialDirector.line("lessons")],
				int(r.get("scrap", 0)))                       # TUTORIAL + PROGRESSION
	hud.extra_ui_rects = coach.ui_rects()


func to_lessons() -> void:
	## PAUSE > LESSONS, the card's EXIT, a completion screen's LESSONS: the TUTORIAL page.
	_tutorial_leave({"menu": "tutorial"})


func _tutorial_leave(extra: Dictionary) -> void:
	TutorialDirector.mark_offered()
	var own_ai := menu_ai if menu_ai != "" else ai_level   # AUDIT FIX: the menu's AI level, not the lesson's
	relaunch = {"faction": menu_faction, "ai": own_ai if not extra.has("ai") else extra["ai"], "colour": color_choice,
			"loadout": ArmyPresets.loadout_for(menu_faction)}
	if extra.has("menu"):
		relaunch["menu"] = extra["menu"]
	if extra.has("ai"):
		relaunch["ai"] = extra["ai"]
	get_tree().reload_current_scene()


func _tutorial_relaunch(extra: Dictionary) -> void:
	relaunch = {"faction": menu_faction, "colour": color_choice}
	if menu_ai != "":                                  # AUDIT FIX: the menu's AI level survives NEXT / REPLAY / RESTART
		relaunch["ai"] = menu_ai
	relaunch.merge(extra, true)
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	## The tour (L0): a tap on the spotlit element counts as NEXT - taken here, before the HUD or the map, so it
	## never also arms a skill, sends or selects.
	if director == null or coach == null or not director.is_tour() or paused:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for r in hud.extra_ui_rects:                      # the card's own buttons stay the card's
		if (r as Rect2).has_point(mb.position):
			return
	if coach.spotlit(mb.position):
		get_viewport().set_input_as_handled()
		director.press_button()


# ================================================================== CAMPAIGN (CAMPAIGN-DESIGN.md §4 / §5)
# The mission hooks, all here: start_mission (like start_tutorial), the director stepped after the Sim, the overlay
# (briefing, objective strip, result screen), the result recorded through Campaign.record, and the ways out
# (NEXT MISSION / RETRY / CAMPAIGN; the pause menu's RESTART / MAIN MENU go the same ways).
func start_mission(key: String, colour := "") -> void:
	## Entry from the campaign page or a relaunch: the mission's faction (seat A) against its rival's (a normal
	## SeatAI at the mission's level - never `director`, that is the tutorial's), 1v1, your ARMIES loadout for
	## that faction; the last map played stays MAIN MENU's. A mission that can't be played yet (no map, a system
	## not built) goes back to the campaign page.
	var m := Campaign.mission(key)
	Campaign.last_run = {}                             # AUDIT FIX: an earlier mission's result never replays
	mission_menu_faction = str(SEAT_FACTIONS[HUMAN])
	mission_menu_ai = ai_level
	if colour != "":
		color_choice = colour
	if m.is_empty() or not Campaign.playable(m):
		push_warning("mission %s is not playable in this build" % key)
		mission = null
		call_deferred("_mission_leave")
		return
	mission = MissionDirector.new(key)
	Telemetry.funnel("mission_start", key)            # PROGRESSION (Alpha 21): the campaign funnel
	show_out_panel = false                             # the result screen says it; no YOU'RE OUT on top
	SEAT_FACTIONS[HUMAN] = str(m["faction"])
	SEAT_FACTIONS["B"] = str(Campaign.rival_of(m).get("faction", "ember"))
	mode = "1v1"
	ai_level = str(m.get("ai", ai_level))
	LOADOUTS = {HUMAN: ArmyPresets.loadout_for(SEAT_FACTIONS[HUMAN])}
	VersusScreen.note_mission(key, menu_layer != null)   # UI: from the campaign page or a new mission: VERSUS after START
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
	MissionDirector.pin_settings(MissionDirector.mission_pins(m))   # AUDIT FIX: the mission's own ABILITIES / LAST STAND / HIDDEN COUNTS
	var keep_last := last_map_path                     # a mission map never becomes MAIN MENU's "last map"
	_start_map(str(m["map"]))
	last_map_path = keep_last


func _mission_setup() -> void:
	## After the HUD: the whole HUD (a mission gates nothing), the overlay, the briefing (paused until START).
	hud.reveal_all()
	mission_overlay = MissionOverlay.new()
	add_child(mission_overlay)
	mission_overlay.setup(self, mission, mobile)
	mission_overlay.start_pressed.connect(_mission_start)
	mission_overlay.action.connect(_on_mission_action)
	mission.completed.connect(_on_mission_completed)
	print("mission %s on %s: %s vs %s (%s AI)" % [mission.key, map_path, SEAT_FACTIONS[HUMAN], SEAT_FACTIONS["B"], ai_level])
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mission-shot="):
			shot = arg.substr(15)
	if "--mission-start" in OS.get_cmdline_user_args() or shot in ["hud", "win", "lose", "details", "endline"]:
		mission_overlay.begin_match()
		_mission_start()
	else:
		paused = true
		mission_overlay.show_briefing()
	if shot != "":
		_mission_shot(shot)


func _mission_start() -> void:
	if VersusScreen.hold_mission(self):                # UI: the VERSUS card first; it calls _mission_start again
		return
	paused = false
	mission.start()


func _on_mission_completed(res: Dictionary) -> void:
	## The mission is decided: the match stops, the run is recorded (best stars, the one-off SCRAP, unlocks), it
	## also counts as a match for XP / challenges (Campaign.progress_match), and the result screen shows.
	paused = true
	hud.close_inspector()
	_end_drag()
	var summary := Campaign.record(mission.key, res)
	Telemetry.funnel("mission_done", mission.key, {"result": "win" if res["won"] else "loss",   # PROGRESSION (Alpha 21)
			"stars": int(res["stars"]), "seconds": int(float(res["time"]))})
	Campaign.last_run = {"key": mission.key, "summary": summary}
	var xp := Campaign.progress_match(sim, HUMAN, ai_level)
	print("mission %s %s at %.1f s - %d star(s), optional %s, reward %s" % [mission.key, "won" if res["won"] else "lost",
			float(res["time"]), int(res["stars"]), res["objective"], summary.get("reward", {}).get("state", "")])
	mission_overlay.show_end(res, summary, xp)


func _on_mission_action(id: String) -> void:
	match id:
		"next":
			var nxt := str(Campaign.last_run.get("summary", {}).get("next", ""))
			_mission_relaunch(nxt if nxt != "" else mission.key)
		"retry":
			_mission_relaunch(mission.key)
		"loadout":                                     # UI: the result's CHANGE LOADOUT
			_mission_leave("armies")
		_:
			_mission_leave()


func _mission_relaunch(key: String) -> void:
	relaunch = {"mission": key, "faction": mission_menu_faction, "colour": color_choice, "ai": mission_menu_ai}   # AUDIT FIX: + the menu AI
	get_tree().reload_current_scene()


func _mission_leave(page := "") -> void:
	## CAMPAIGN / the pause menu's MAIN MENU: back to the campaign page (MAIN while this build's menu has none).
	## UI: page "armies" (the result's CHANGE LOADOUT) opens ARMIES on the mission's faction instead.
	MissionDirector.restore_settings()
	var f := mission_menu_faction if mission_menu_faction != "" else str(SEAT_FACTIONS[HUMAN])
	relaunch = {"faction": f, "ai": mission_menu_ai if mission_menu_ai != "" else ai_level, "colour": color_choice,
			"loadout": ArmyPresets.loadout_for(f)}
	relaunch["menu"] = "campaign"                      # (Menu.show_campaign)
	if page == "armies":                               # UI: its BACK returns to the campaign page
		relaunch["menu"] = "armies"
		relaunch["army"] = str(SEAT_FACTIONS[HUMAN])
	get_tree().reload_current_scene()


func _mission_shot(what: String) -> void:
	## --mission-shot=brief|hud|win|lose --out=<dir>: that screen, saved as mission_<what>.png, then quit. The
	## result shots record into a scratch progress file, never the player's own.
	if what in ["win", "lose", "details", "endline"]:   # (UI: details = the win's MATCH DETAILS page, endline its closing line)
		Campaign.path = "user://campaign_shots.cfg"
		Campaign.reset_progress()
		Progression.path = "user://progress_shots.cfg"   # the XP / SCRAP of a shot never reaches the player's wallet
		Progression.reload_all()
	var wait: float = {"brief": 1.0, "hud": 9.0, "win": 3.0, "lose": 3.0, "details": 3.0, "endline": 3.0}.get(what, 1.0)
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < wait:
		await get_tree().process_frame
	if what in ["win", "lose", "details", "endline"]:
		mission.finish_now(what != "lose", what != "lose", false)
		t0 = Time.get_ticks_msec()
		while (Time.get_ticks_msec() - t0) / 1000.0 < (1.0 if what == "endline" else MissionOverlay.END_LINE_SECONDS + 2.6):
			await get_tree().process_frame
		if what == "details":
			mission_overlay.show_details()
			for i in range(10):
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "%s/mission_%s.png" % [shot_dir if shot_dir != "" else OS.get_user_data_dir(), what]
	get_viewport().get_texture().get_image().save_png(out)
	print("screenshot ", out)
	get_tree().quit()
# --- end CAMPAIGN ---
