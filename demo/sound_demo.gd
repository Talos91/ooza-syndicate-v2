extends Node
## SOUND DEMO (branch sound-demo, never shipped): spectate an AI-vs-AI BRAWL match and compare four candidate
## sound sets by ear. Boots main.tscn the way tests/perf_check.gd does (main.set(...) before add_child) and
## hooks the match READ-ONLY: every frame it reads the new entries of the Sim's telemetry list (sim.events,
## never cleared) plus the machinegoons' `shot` stamps, maps them to demo events and plays the current set's
## file. No game script is changed.
##   Keys: 1 / 2 / 3 / 4 sound set, A alternate (1-3), M mute, + / - master volume, S speed 1x/2x/3x, R restart (new seed),
##         SPACE pause. The match restarts by itself 5 s after it ends (8 s with music on: the stinger plays first).
##   Music (music_director.gd): TAB / Shift+TAB slot, [ / ] the slot's track (all 15), P play the selected slot now,
##         H hold the MENU track, N music on / off, , / . music volume.
##   User args (after `--`):
##     --demo-log             print every sound played ("SOUND ...") and a summary on quit
##     --demo-cycle=20        switch to the next set every 20 s, the next alternate after each full round (verification)
##     --demo-speed=2         start at 2x speed (1-3)
##     --demo-shot=<png>@<s>  save a screenshot at <s> seconds of real time
##     --demo-quit=<s>        quit after <s> seconds of real time (prints the summary)
##     --demo-track-len=20    treat every music track as 20 s long (the playlist crossfades sooner; verification)
##     --demo-keys=12:Tab,13:BracketRight   press these keys at these seconds of real time (verification)
##     --demo-ff=150          fast-forward the first match to 150 s of match time (silent) before playing on
##     --demo-map=res://maps4/<file>.json  --demo-mode=FFA4|2v2  --demo-ai=Standard|Veteran

# ------------------------------------------------------------------ SOUND: every mix number in one table
# (copy into rules.gd's SOUND block when sound goes into the game). Levels are dB against the music at 0 dB; the
# master volume (+ / -) sits on top of both. Times are seconds. Daniele, 2026-09-28: "the sounds are too
# overpowering vs the background music, make them less loud and that they fade more seamlessly".
const SOUND := {
	"music_db": 0.0,                 # the music bus: the reference
	"sfx_db": {                      # per event, on the SFX bus (0 dB): the frequent ones quietest, big cues on top
		"send": -12.0, "fight": -12.0, "hit": -12.0, "machinegoon": -12.0,
		"laser": -11.0, "fall": -11.0, "relay_warning": -11.0, "relay_switch": -11.0,
		"skill": -10.0, "upgrade": -10.0, "build": -10.0, "collapse_warning": -10.0,
		"monster_launch": -10.0, "monster_stomp": -10.0, "monster_take": -10.0, "monster_fall": -10.0,
		"collapse": -9.0, "eliminated": -9.0,
		"capture": -8.0, "node_lost": -8.0, "last_stand": -8.0, "very_last_stand": -8.0, "win": -8.0,
	},
	"sfx_gap": {                     # the least time between two sounds of one event (real time; default 0.3)
		"send": 0.25, "fight": 0.3, "hit": 0.2, "capture": 0.2, "node_lost": 0.25, "upgrade": 0.3, "build": 0.3,
		"laser": 0.25, "machinegoon": 0.45, "skill": 0.3, "fall": 0.3, "collapse_warning": 0.3, "collapse": 0.3,
		"last_stand": 1.0, "very_last_stand": 1.0, "eliminated": 0.5, "win": 2.0,
	},
	"voices": 12,                    # sounds at once (fading-out tails not counted)
	"attack": 0.02,                  # fade-in of every sound (no click on)
	"release": 0.25,                 # fade-out tail at every sound's end or cut (no cut off) ...
	"release_share": 0.4,            # ... but never more than this share of a short file
	"repeat_fade": 0.15,             # a repeat of the same event fades the earlier one out (a crossfade, no restart)
	"steal_fade": 0.1,               # a voice given up for a priority cue fades out this fast
	"duck_events": ["capture", "last_stand", "very_last_stand", "win"],
	"duck_db": -2.0,                 # the music under those cues
	"duck_in": 0.3,
	"duck_hold": 0.5,
	"duck_out": 0.8,
	"menu_seconds": 8.0,             # the MENU track at each match's start
	"xfade_start": 0.5,              # music fade-in from silence
	"xfade_phase": 1.5,              # MENU -> BATTLE, a preview on / off
	"xfade_last_stand": 1.0,         # into LAST STAND / VERY LAST STAND (the alarm leads)
	"xfade_playlist": 2.0,           # BATTLE track to track, a slot looping
	"xfade_pick": 0.8,               # a new pick ([ / ]) for the slot that is playing
	"xfade_stinger": 0.4,            # into VICTORY / DEFEAT
	"stinger_len": 7.0,              # VICTORY / DEFEAT play the track's first 7 s ...
	"stinger_fade": 1.5,             # ... the last 1.5 of them fading out
	"restart_after": 5.0,            # the demo's next match (8 s with music on: stinger_len + 1)
}

const MAP := "res://maps4/M-30-sporefall-plain.json"   # FFA4, 17 nodes, 6 lasers, relays: busy but readable
const MODE := "FFA4"
const AI := "Veteran"
const ROOT := "res://demo_sounds/"
const POOL := 18                                  # players: SOUND.voices plus room for fading tails
const MusicDirector := preload("res://demo/music_director.gd")

# Sound sets: event -> alternates ("<pack>/<file>" under demo_sounds/, without .ogg). Key A cycles the alternate
# (alt 1 / 2 / 3) for every event at once; an event with fewer alternates wraps round (each overlay line says
# which one played). Daniele's listening so far (2026-09-28): "set 1 and 3 are best so far", then "2 and 3 are my
# fav so far" - Set 3 is the keeper, Set 4 mixes 2 + 3.
const SETS := [
	{"name": "Kenney mix", "ev": {
		"send": ["slime/slime_12", "slime/slime_06", "slime/slime_11"],
		"fight": ["slime/slime_02", "slime/slime_07", "slime/splash_09"],
		"hit": ["impact/impactSoft_medium_000", "impact/impactSoft_medium_002", "impact/impactGeneric_light_001"],
		"capture": ["impact/impactGlass_light_000", "impact/impactGlass_light_002", "impact/impactBell_heavy_004"],
		"node_lost": ["impact/impactPunch_medium_001", "impact/impactPlate_light_002", "impact/impactGlass_heavy_000"],
		"upgrade": ["interface/confirmation_001", "interface/maximize_006", "interface/confirmation_003"],
		"build": ["interface/maximize_003", "interface/maximize_008", "interface/drop_002"],
		"laser": ["scifi/laserSmall_000", "scifi/laserSmall_002", "scifi/laserRetro_002"],
		"machinegoon": ["scifi/laserRetro_000", "scifi/laserRetro_004", "scifi/laserSmall_004"],
		"monster_launch": ["slime/splash_06", "slime/slime_03", "scifi/slime_000"],
		"monster_stomp": ["slime/slime_09", "impact/impactSoft_heavy_000", "impact/impactPunch_heavy_002"],
		"monster_take": ["slime/slime_13", "slime/slime_10", "slime/splash_14"],
		"monster_fall": ["slime/splash_02", "slime/splash_08", "slime/splash_12"],
		"skill": ["scifi/forceField_000", "scifi/forceField_002", "scifi/doorOpen_002"],
		"relay_warning": ["scifi/doorClose_000", "scifi/impactMetal_004", "scifi/doorClose_002"],
		"relay_switch": ["scifi/doorOpen_000", "scifi/doorOpen_001", "scifi/impactMetal_002"],
		"fall": ["slime/splash_10", "slime/splash_15", "slime/splash_06"],
		"collapse_warning": ["interface/error_004", "interface/error_008", "interface/tick_004"],
		"collapse": ["scifi/explosionCrunch_000", "scifi/lowFrequency_explosion_001", "scifi/impactMetal_003"],
		"last_stand": ["scifi/engineCircular_000", "scifi/engineCircular_003", "scifi/forceField_004"],
		"very_last_stand": ["scifi/engineCircular_002", "scifi/engineCircular_004", "scifi/lowFrequency_explosion_000"],
		"eliminated": ["interface/minimize_005", "interface/minimize_006", "interface/error_005"],
		"win": ["interface/confirmation_002", "interface/confirmation_004", "interface/maximize_005"],
	}},
	# (the 60 CC0 sci-fi files are unnamed: picked by length and group, sfx_07* short blips, sfx_09* ticks, ...)
	{"name": "Sci-fi + goo", "ev": {
		"send": ["slime/slime_05", "slime/slime_16", "slime/splash_09"],
		"fight": ["slime/slime_14", "slime/slime_10", "slime/slime_07"],
		"hit": ["impact/impactGeneric_light_000", "impact/impactGeneric_light_002", "impact/impactGeneric_light_004"],
		"capture": ["interface/confirmation_003", "scifi60/sfx_04a", "scifi60/sfx_05a"],
		"node_lost": ["interface/error_007", "scifi60/sfx_03a", "interface/error_002"],
		"upgrade": ["scifi60/sfx_14a", "scifi60/sfx_14b", "scifi60/sfx_15a"],
		"build": ["interface/maximize_007", "scifi60/sfx_10a", "scifi60/sfx_17a"],
		"laser": ["scifi60/sfx_07a", "scifi60/sfx_07b", "scifi60/sfx_07c"],
		"machinegoon": ["scifi60/sfx_09a", "scifi60/sfx_09b", "scifi60/sfx_20b"],
		"monster_launch": ["slime/slime_03", "slime/splash_12", "slime/slime_13"],
		"monster_stomp": ["impact/impactPunch_heavy_002", "impact/impactPunch_heavy_000", "impact/impactSoft_heavy_001"],
		"monster_take": ["slime/slime_08", "slime/slime_15", "slime/slime_06"],
		"monster_fall": ["slime/splash_14", "slime/splash_13", "slime/splash_03"],
		"skill": ["scifi60/sfx_13a", "scifi60/sfx_13b", "scifi60/sfx_21a"],
		"relay_warning": ["scifi60/sfx_20a", "scifi60/sfx_20c", "scifi60/sfx_22a"],
		"relay_switch": ["scifi60/sfx_12a", "scifi60/sfx_12b", "scifi60/sfx_10b"],
		"fall": ["slime/splash_15", "slime/splash_10", "slime/splash_06"],
		"collapse_warning": ["scifi60/sfx_02a", "scifi60/sfx_02b", "scifi60/sfx_02c"],
		"collapse": ["impact/impactPlate_heavy_000", "impact/impactPlate_heavy_002", "scifi60/sfx_08a"],
		"last_stand": ["scifi60/sfx_18b", "scifi60/sfx_16a", "scifi60/sfx_01a"],
		"very_last_stand": ["scifi60/sfx_18a", "scifi60/sfx_16b", "scifi60/sfx_06b"],
		"eliminated": ["interface/minimize_004", "scifi60/sfx_05c", "scifi60/sfx_03b"],
		"win": ["scifi60/sfx_06", "scifi60/sfx_01b", "interface/maximize_004"],
	}},
	{"name": "Digital bleeps", "ev": {
		"send": ["slime/bubble_02", "slime/bubble_03", "slime/slime_16"],
		"fight": ["slime/slime_01", "slime/slime_04", "slime/slime_11"],
		"hit": ["impact/impactSoft_medium_001", "impact/impactSoft_medium_003", "impact/impactSoft_medium_004"],
		"capture": ["digital/powerUp5", "digital/powerUp6", "digital/powerUp9"],
		"node_lost": ["digital/phaserDown2", "digital/phaserDown1", "digital/phaserDown3"],
		"upgrade": ["digital/powerUp2", "digital/powerUp7", "digital/powerUp10"],
		"build": ["digital/highUp", "digital/powerUp4", "digital/twoTone2"],
		"laser": ["digital/laser5", "digital/laser3", "digital/zap1"],
		"machinegoon": ["digital/pepSound3", "digital/phaserUp5", "digital/phaserUp6"],
		"monster_launch": ["slime/splash_09", "digital/phaseJump1", "slime/splash_06"],
		"monster_stomp": ["impact/impactSoft_heavy_002", "impact/impactSoft_heavy_004", "digital/lowRandom"],
		"monster_take": ["slime/slime_15", "slime/slime_08", "digital/powerUp11"],
		"monster_fall": ["slime/splash_06", "slime/splash_08", "digital/spaceTrash1"],
		"skill": ["digital/phaseJump2", "digital/phaseJump4", "digital/phaserUp3"],
		"relay_warning": ["digital/tone1", "digital/pepSound2", "digital/pepSound4"],
		"relay_switch": ["digital/twoTone1", "digital/threeTone1", "digital/zapTwoTone"],
		"fall": ["slime/bubble_01", "slime/splash_10", "slime/slime_12"],
		"collapse_warning": ["digital/pepSound1", "digital/pepSound5", "digital/highDown"],
		"collapse": ["digital/lowDown", "digital/spaceTrash2", "impact/impactSoft_heavy_000"],
		"last_stand": ["digital/lowThreeTone", "digital/zapThreeToneUp", "digital/threeTone2"],
		"very_last_stand": ["digital/zapThreeToneDown", "digital/zapTwoTone2", "digital/lowThreeTone"],
		"eliminated": ["digital/highDown", "digital/lowRandom", "digital/spaceTrash3"],
		"win": ["digital/powerUp1", "digital/powerUp3", "digital/powerUp12"],
	}},
	# Set 4 (Daniele, 2026-09-28: "2 and 3 are my fav so far"): Set 3's digital bleeps for UI / relays / skills,
	# Set 2's sci-fi lasers / beeps plus its impacts and slime for combat; collapse warning, collapse, the alarms, the
	# knock-out and the win offer both sets' picks as alternates.
	{"name": "Mix 2+3", "ev": {
		"send": ["slime/slime_05", "slime/slime_16", "slime/splash_09"],
		"fight": ["slime/slime_14", "slime/slime_10", "slime/slime_07"],
		"hit": ["impact/impactGeneric_light_000", "impact/impactGeneric_light_002", "impact/impactGeneric_light_004"],
		"capture": ["digital/powerUp5", "digital/powerUp6", "digital/powerUp9"],
		"node_lost": ["digital/phaserDown2", "digital/phaserDown1", "digital/phaserDown3"],
		"upgrade": ["digital/powerUp2", "digital/powerUp7", "digital/powerUp10"],
		"build": ["digital/highUp", "digital/powerUp4", "digital/twoTone2"],
		"laser": ["scifi60/sfx_07a", "scifi60/sfx_07b", "scifi60/sfx_07c"],
		"machinegoon": ["scifi60/sfx_09a", "scifi60/sfx_09b", "scifi60/sfx_20b"],
		"monster_launch": ["slime/slime_03", "slime/splash_12", "slime/slime_13"],
		"monster_stomp": ["impact/impactPunch_heavy_002", "impact/impactPunch_heavy_000", "impact/impactSoft_heavy_001"],
		"monster_take": ["slime/slime_08", "slime/slime_15", "slime/slime_06"],
		"monster_fall": ["slime/splash_14", "slime/splash_13", "slime/splash_03"],
		"skill": ["digital/phaseJump2", "digital/phaseJump4", "digital/phaserUp3"],
		"relay_warning": ["digital/tone1", "digital/pepSound2", "digital/pepSound4"],
		"relay_switch": ["digital/twoTone1", "digital/threeTone1", "digital/zapTwoTone"],
		"fall": ["slime/splash_15", "slime/splash_10", "slime/splash_06"],
		"collapse_warning": ["scifi60/sfx_02a", "digital/pepSound1", "digital/pepSound5"],
		"collapse": ["impact/impactPlate_heavy_000", "impact/impactPlate_heavy_002", "digital/lowDown"],
		"last_stand": ["digital/lowThreeTone", "scifi60/sfx_18b", "digital/zapThreeToneUp"],
		"very_last_stand": ["digital/zapThreeToneDown", "scifi60/sfx_18a", "digital/zapTwoTone2"],
		"eliminated": ["digital/highDown", "interface/minimize_004", "digital/lowRandom"],
		"win": ["digital/powerUp1", "scifi60/sfx_06", "digital/powerUp3"],
	}},
]
const ALTS := 3
# Long files are cut (with a short fade) after this many seconds.
const MAX_LEN := {"scifi/engineCircular_000": 1.8, "scifi/engineCircular_002": 2.2, "scifi/engineCircular_003": 1.8,
		"scifi/engineCircular_004": 2.2, "scifi/lowFrequency_explosion_000": 1.5, "scifi60/sfx_18a": 2.5, "scifi60/sfx_16a": 2.0, "scifi60/sfx_16b": 2.0,
		"digital/laser5": 0.6, "digital/laser3": 0.6, "digital/zap1": 0.6, "digital/zapTwoTone": 0.8,
		"digital/spaceTrash1": 1.0, "digital/spaceTrash2": 1.0, "digital/spaceTrash3": 1.0}
# Events that may take a voice when all are busy (the rest are dropped then).
const PRIORITY := ["win", "last_stand", "very_last_stand", "eliminated", "collapse"]

# Kept across a restart (the scene reloads).
static var set_idx := 3                          # Set 4 "Mix 2+3": Daniele's pick (2026-09-28)
static var alt_idx := 0                          # the alternate every event plays (key A)
static var shot_done := false
static var vol_db := -6.0
static var muted := false
static var speed := 1
static var seed_now := -1
static var runs := 0
static var played_types := {}                    # event -> count (whole run, all restarts)
static var played_sets := {}                     # set index -> count
static var clock0 := -1                          # ticks at the first start (for --demo-quit / --demo-shot)

var main: Node3D
var sim: Sim = null
var ev_index := 0
var last_play := {}                              # event -> ticks msec
var upgrading := {}                              # node id -> true: its running build is an upgrade
var shot_t := {}                                 # machinegoon node id -> last shot stamp
var absorbing := {}                              # horde id -> true: pouring into a hostile node (a fight on)
var voices: Array[AudioStreamPlayer] = []
var voice_info: Array = []                       # per player {event, base_db, start ms, length s, rel_start ms (-1), rel_len s}
var streams := {}                                # "<pack>/<file>" -> AudioStream
var recent: Array[String] = []
var end_wait := -1.0
var log_on := false
var cycle := 0.0
var cycle_t := 0.0
var shot_path := ""
var shot_at := -1.0
var quit_at := -1.0
var map_path := MAP
var mode := MODE
var ai := AI
var ff := -1.0
var music: Node                                  # MusicDirector
var track_len := 0.0
static var key_script: Array = []                # [[seconds, keycode], ...] (--demo-keys; survives a restart)
var match_clock := 0.0                           # real seconds since this match started
var ls_seen := false
var vls_seen := false
var music_label: Label
# overlay
var title_label: Label
var status_label: Label
var lines_label: Label
var set_buttons: Array[Button] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo-log":
			log_on = true
		elif arg.begins_with("--demo-cycle="):
			cycle = float(arg.substr(13))
		elif arg.begins_with("--demo-speed=") and runs == 0:
			speed = clampi(int(arg.substr(13)), 1, 3)
		elif arg.begins_with("--demo-shot="):
			var p := arg.substr(12).split("@")
			shot_path = p[0]
			shot_at = float(p[1]) if p.size() > 1 else 20.0
		elif arg.begins_with("--demo-quit="):
			quit_at = float(arg.substr(12))
		elif arg.begins_with("--demo-map="):
			map_path = arg.substr(11)
		elif arg.begins_with("--demo-mode="):
			mode = arg.substr(12)
		elif arg.begins_with("--demo-ai="):
			ai = arg.substr(10)
		elif arg.begins_with("--demo-ff=") and runs == 0:
			ff = float(arg.substr(10))
		elif arg.begins_with("--demo-track-len="):
			track_len = float(arg.substr(17))
		elif arg.begins_with("--demo-keys=") and runs == 0:
			for kv in arg.substr(12).split(","):
				var pr := kv.split(":")
				key_script.append([float(pr[0]), OS.find_keycode_from_string(pr[1])])
	if clock0 < 0:
		clock0 = Time.get_ticks_msec()
	_load_sets()
	MusicDirector.ensure_buses()
	music = MusicDirector.new()
	add_child(music)
	music.setup(log_on, track_len, SOUND)
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		voices.append(p)
		voice_info.append({"event": "", "base_db": 0.0, "start": 0, "len": 0.0, "rel_start": -1, "rel_len": 0.0})
	_apply_volume()
	Engine.time_scale = float(speed)
	Rules.abilities_on = true
	if seed_now < 0:
		seed_now = randi() % 100000
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", map_path)
	main.set("mode", mode)
	main.set("demo", true)
	main.set("ai_level", ai)
	main.set("seed_value", seed_now)
	if ff > 0.0:
		main.set("ff_to", ff)
	add_child(main)
	_build_overlay()
	runs += 1
	print("SOUND DEMO run %d: %s %s, AI %s, seed %d, set %d %s" % [runs, map_path.get_file(), mode, ai, seed_now,
			set_idx + 1, SETS[set_idx]["name"]])


func _load_sets() -> void:
	## Loads every file of every set once; prints what is missing (the verification run checks this line).
	var missing := []
	for si in range(SETS.size()):
		var n := 0
		for ev in SETS[si]["ev"]:
			for f in SETS[si]["ev"][ev]:
				if streams.has(f):
					n += 1
					continue
				var path: String = ROOT + f + ".ogg"
				var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
				if s == null:
					missing.append(path)
				else:
					streams[f] = s
					n += 1
		if runs == 0:
			print("SET %d %s: %d files loaded" % [si + 1, SETS[si]["name"], n])
	if runs == 0 or not missing.is_empty():
		print("SETS: %d distinct files, %d missing %s" % [streams.size(), missing.size(), missing])


# ------------------------------------------------------------------ the hook (read-only)

func _process(delta: float) -> void:
	var now := _clock()
	if cycle > 0.0:
		cycle_t += delta / Engine.time_scale
		if cycle_t >= cycle:
			cycle_t = 0.0
			if set_idx == SETS.size() - 1:
				_next_alt()
			_set_set((set_idx + 1) % SETS.size())
	if shot_at >= 0.0 and now >= shot_at and not shot_done:
		shot_at = -1.0
		shot_done = true
		_screenshot()
	if quit_at >= 0.0 and now >= quit_at:
		quit_at = -1.0
		_summary()
		get_tree().quit()
		return
	_trim_voices()
	var real_dt := delta / Engine.time_scale
	while not key_script.is_empty() and now >= float(key_script[0][0]):
		var ke := InputEventKey.new()
		ke.keycode = int(key_script[0][1])
		ke.pressed = true
		key_script.pop_front()
		if log_on:
			print("DEMO key ", OS.get_keycode_string(ke.keycode))
		Input.parse_input_event(ke)
	var started := main != null and bool(main.get("started"))
	if started:
		match_clock += real_dt
	music.update(real_dt, {"clock": match_clock, "ls": ls_seen, "vls": vls_seen,
			"over": sim != null and sim.over, "won": sim != null and sim.winner == str(main.get("HUMAN"))})
	if not started:
		_refresh_overlay()
		return
	var s: Sim = main.get("sim")
	if s != sim:                                   # a new match (or main rebuilt its Sim): start reading afresh
		sim = s
		ev_index = sim.events.size() if sim.time > 1.0 else 0   # (--demo-ff: the fast-forwarded past stays silent)
		for i in range(ev_index):                  # ...but a fast-forward into Last Stand still sets its music
			var ty := str(sim.events[i].get("type", ""))
			ls_seen = ls_seen or ty == "last_stand"
			vls_seen = vls_seen or ty == "very_last_stand"
		upgrading.clear()
		shot_t.clear()
		absorbing.clear()
	while ev_index < sim.events.size():
		_on_event(sim.events[ev_index])
		ev_index += 1
	var still := {}
	for h in sim.hordes:                           # BRAWL fights: a line pouring into an enemy / neutral node is
		if h["state"] != "absorb" or h["units"] <= 0.0:   # resolved at its door (what CombatFx draws as the clash)
			continue
		var tn: Dictionary = sim.nodes[h["target"]]
		if sim.collapsed.get(tn["id"], false) or sim.allied(tn["owner"], h["owner"]):
			continue
		still[h["id"]] = true
		if not absorbing.has(h["id"]):
			_play("fight")
	absorbing = still
	for n in sim.nodes:                            # machinegoon streams: a new `shot` stamp every firing frame
		if str(n.get("structure", "")) != "machinegoon":
			continue
		var shot: Dictionary = n.get("shot", {})
		if shot.is_empty():
			continue
		var t := float(shot.get("t", -1.0))
		if t != float(shot_t.get(n["id"], -1.0)):
			shot_t[n["id"]] = t
			_play("machinegoon")
	if sim.over:
		if end_wait < 0.0:
			end_wait = maxf(float(SOUND["restart_after"]), float(SOUND["stinger_len"]) + 1.0) if MusicDirector.on \
					else float(SOUND["restart_after"])
		end_wait -= delta / Engine.time_scale
		if end_wait <= 0.0:
			_restart()
			return
	_refresh_overlay()


func _on_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"send":
			_play("send")
		"capture", "handover":
			if ev.get("monster", false):
				return                                 # the monster_take event right after says it
			_play("node_lost" if str(ev.get("from", "")) != "" else "capture")
		"frontline", "rear":
			_play("fight")
		"horde_destroyed":
			_play("hit")
		"build_start":
			var nid := int(ev["node"])
			upgrading[nid] = str(ev.get("kind", "")) == str(sim.nodes[nid].get("structure", "")) \
					and str(ev.get("kind", "")) in ["vat", "machinegoon"]
		"build_done":
			_play("upgrade" if upgrading.get(int(ev["node"]), false) else "build")
		"cannon_burst":
			_play("laser")
		"monster_launch":
			_play("monster_launch")
		"monster_kick":
			_play("monster_stomp")
		"monster_take":
			_play("monster_take")
		"monster_fall":
			_play("monster_fall")
		"skill":
			_play("skill")
		"relay_fired":
			_play("relay_warning")
		"relay_tick":
			_play("relay_switch")
		"fall":
			_play("fall")
		"collapse_warning":
			_play("collapse_warning")
		"collapse":
			_play("collapse")
		"last_stand":
			ls_seen = true
			_play("last_stand")
		"very_last_stand":
			vls_seen = true
			_play("very_last_stand")
		"eliminated":
			_play("eliminated")
		"end":
			if str(ev.get("winner", "")) != "":
				_play("win")


# ------------------------------------------------------------------ playback

func _play(event: String) -> void:
	var now_ms := Time.get_ticks_msec()
	var gap := float(SOUND["sfx_gap"].get(event, 0.3))
	if now_ms - int(last_play.get(event, -100000)) < int(gap * 1000.0):
		return
	var files: Array = SETS[set_idx]["ev"].get(event, [])
	if files.is_empty():
		return
	var ai_ := alt_idx % files.size()
	var f: String = files[ai_]
	if not streams.has(f):
		return
	var active := 0                                    # sounding voices, not counting tails or this event's own
	for i in range(POOL):
		if voices[i].playing and int(voice_info[i]["rel_start"]) < 0 and str(voice_info[i]["event"]) != event:
			active += 1
	if active >= int(SOUND["voices"]):
		if not event in PRIORITY:
			return                                     # every voice busy: drop it (a busy map stays readable)
		var oldest := -1
		for i in range(POOL):                          # a priority cue: the oldest ordinary sound fades out for it
			var vinf: Dictionary = voice_info[i]
			if voices[i].playing and int(vinf["rel_start"]) < 0 and not str(vinf["event"]) in PRIORITY \
					and (oldest < 0 or int(vinf["start"]) < int(voice_info[oldest]["start"])):
				oldest = i
		if oldest < 0:
			return
		_release(oldest, float(SOUND["steal_fade"]))
	for i in range(POOL):                              # a repeat: the earlier sound of this event fades out under it
		if voices[i].playing and str(voice_info[i]["event"]) == event:
			_release(i, float(SOUND["repeat_fade"]))
	var vi := -1
	for i in range(POOL):
		if not voices[i].playing:
			vi = i
			break
	if vi < 0:                                         # (every player busy with tails: the quietest tail gives way)
		var low := INF
		for i in range(POOL):
			if int(voice_info[i]["rel_start"]) >= 0 and voices[i].volume_db < low:
				low = voices[i].volume_db
				vi = i
		if vi < 0:
			return
	last_play[event] = now_ms
	if event in SOUND["duck_events"]:
		music.duck()
	var p := voices[vi]
	p.stop()
	p.stream = streams[f]
	var cut := float(MAX_LEN.get(f, 0.0))
	voice_info[vi] = {"event": event, "base_db": float(SOUND["sfx_db"].get(event, -10.0)), "start": now_ms,
			"len": cut if cut > 0.0 else p.stream.get_length(), "rel_start": -1, "rel_len": 0.0}
	p.volume_db = -80.0                                # the attack ramps it up (_trim_voices)
	p.play()
	var pack := f.get_slice("/", 0)
	var line := "%s  a%d -> %s/%s.ogg" % [event, ai_ + 1, pack, f.get_slice("/", 1)]
	recent.push_front(line)
	if recent.size() > 6:
		recent.resize(6)
	played_types[event] = int(played_types.get(event, 0)) + 1
	played_sets[set_idx] = int(played_sets.get(set_idx, 0)) + 1
	if log_on:
		print("SOUND t=%.1f set%d %s" % [sim.time if sim else 0.0, set_idx + 1, line])


func _trim_voices() -> void:
	## Every sound's soft envelope: SOUND.attack in, SOUND.release out at its end (or its MAX_LEN cut), and the
	## faster fades of a repeat or a stolen voice (_release).
	var now_ms := Time.get_ticks_msec()
	for i in range(POOL):
		if not voices[i].playing:
			continue
		var v: Dictionary = voice_info[i]
		var t := (now_ms - int(v["start"])) / 1000.0
		var length := float(v["len"])
		var rel := minf(float(SOUND["release"]), length * float(SOUND["release_share"]))
		if int(v["rel_start"]) < 0 and t >= length - rel:
			v["rel_start"] = now_ms
			v["rel_len"] = maxf(length - t, 0.01)
		var a := clampf(t / float(SOUND["attack"]), 0.0, 1.0)
		if int(v["rel_start"]) >= 0:
			var r := 1.0 - (now_ms - int(v["rel_start"])) / 1000.0 / float(v["rel_len"])
			if r <= 0.0:
				voices[i].stop()
				continue
			a *= r * r                                  # (quadratic: a smooth tail)
		voices[i].volume_db = float(v["base_db"]) + linear_to_db(maxf(a, 0.0001))


func _release(i: int, secs: float) -> void:
	## Fades voice i out over `secs` (or sooner, if it was already fading faster).
	var v: Dictionary = voice_info[i]
	var now_ms := Time.get_ticks_msec()
	if int(v["rel_start"]) >= 0:
		var left := float(v["rel_len"]) - (now_ms - int(v["rel_start"])) / 1000.0
		if left <= secs:
			return
	v["rel_start"] = now_ms
	v["rel_len"] = maxf(secs, 0.01)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, vol_db)
	AudioServer.set_bus_mute(0, muted)


# ------------------------------------------------------------------ controls

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	var handled := true
	match k:
		KEY_1, KEY_KP_1:
			_set_set(0)
		KEY_2, KEY_KP_2:
			_set_set(1)
		KEY_3, KEY_KP_3:
			_set_set(2)
		KEY_4, KEY_KP_4:
			_set_set(3)
		KEY_A:
			_next_alt()
		KEY_M:
			_toggle_mute()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			vol_db = minf(vol_db + 3.0, 6.0)
			_apply_volume()
		KEY_MINUS, KEY_KP_SUBTRACT:
			vol_db = maxf(vol_db - 3.0, -40.0)
			_apply_volume()
		KEY_S:
			speed = speed % 3 + 1
			Engine.time_scale = float(speed)
		KEY_R:
			_restart()
		KEY_SPACE:
			if main != null and bool(main.get("started")):
				main.set("paused", not bool(main.get("paused")))
		KEY_TAB:
			music.next_slot(-1 if (event as InputEventKey).shift_pressed else 1)
		KEY_BRACKETRIGHT:
			music.cycle_pick(1)
		KEY_BRACKETLEFT:
			music.cycle_pick(-1)
		KEY_P:
			music.toggle_preview()
		KEY_H:
			music.toggle_hold_menu()
		KEY_N:
			music.toggle_on()
		KEY_PERIOD:
			music.change_volume(2.0)
		KEY_COMMA:
			music.change_volume(-2.0)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()        # (1/2/3 would otherwise arm seat A's skill dock)
		_refresh_overlay()


func _set_set(i: int) -> void:
	set_idx = i
	for vi in range(POOL):
		if voices[vi].playing:
			_release(vi, float(SOUND["repeat_fade"]))
	recent.push_front("--- set %d: %s ---" % [i + 1, SETS[i]["name"]])
	if recent.size() > 6:
		recent.resize(6)
	if log_on:
		print("SET -> %d %s" % [i + 1, SETS[i]["name"]])
	_refresh_overlay()


func _next_alt() -> void:
	alt_idx = (alt_idx + 1) % ALTS
	for vi in range(POOL):
		if voices[vi].playing:
			_release(vi, float(SOUND["repeat_fade"]))
	recent.push_front("--- alternate %d/%d ---" % [alt_idx + 1, ALTS])
	if recent.size() > 6:
		recent.resize(6)
	if log_on:
		print("ALT -> %d" % (alt_idx + 1))
	_refresh_overlay()


func _toggle_mute() -> void:
	muted = not muted
	_apply_volume()
	_refresh_overlay()


func _restart() -> void:
	seed_now = randi() % 100000
	Engine.time_scale = float(speed)
	set_process(false)
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ overlay

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.72)
	sb.border_color = Color(0.45, 1.0, 0.6, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 150)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	box.add_child(title_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for i in range(SETS.size()):
		var b := Button.new()
		b.text = "%d %s" % [i + 1, SETS[i]["name"]]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_set_set.bind(i))
		row.add_child(b)
		set_buttons.append(b)
	var ab := Button.new()
	ab.text = "A  alt"
	ab.focus_mode = Control.FOCUS_NONE
	ab.add_theme_font_size_override("font_size", 13)
	ab.pressed.connect(_next_alt)
	row.add_child(ab)
	var mb := Button.new()
	mb.text = "M  mute"
	mb.focus_mode = Control.FOCUS_NONE
	mb.add_theme_font_size_override("font_size", 13)
	mb.pressed.connect(_toggle_mute)
	row.add_child(mb)
	var rb := Button.new()
	rb.text = "R  restart"
	rb.focus_mode = Control.FOCUS_NONE
	rb.add_theme_font_size_override("font_size", 13)
	rb.pressed.connect(_restart)
	row.add_child(rb)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	box.add_child(status_label)
	lines_label = Label.new()
	lines_label.add_theme_font_size_override("font_size", 14)
	lines_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	lines_label.custom_minimum_size = Vector2(440, 6 * 19)
	box.add_child(lines_label)
	var keys := Label.new()
	keys.text = "1/2/3/4 set   A alternate   M mute   +/- volume   S speed   R restart   SPACE pause\n" \
			+ "music: TAB slot   [ / ] track   P play slot now   H hold menu   N on/off   , / . volume"
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color(0.65, 0.75, 0.8))
	box.add_child(keys)
	var mpanel := PanelContainer.new()                # music: top right, under PAUSE
	mpanel.add_theme_stylebox_override("panel", sb)
	mpanel.anchor_left = 1.0
	mpanel.anchor_right = 1.0
	mpanel.offset_left = -330
	mpanel.offset_right = -12
	mpanel.offset_top = 96
	mpanel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mpanel)
	music_label = Label.new()
	music_label.add_theme_font_size_override("font_size", 13)
	music_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	mpanel.add_child(music_label)
	_refresh_overlay()


func _refresh_overlay() -> void:
	if title_label == null:
		return
	title_label.text = "SOUND DEMO  -  set %d: %s   -   alt %d/%d" % [set_idx + 1, SETS[set_idx]["name"], alt_idx + 1, ALTS]
	for i in range(set_buttons.size()):
		set_buttons[i].set_pressed_no_signal(i == set_idx)
	var paused := main != null and bool(main.get("paused"))
	var t := sim.time if sim != null else 0.0
	var st := "vol %+.0f dB%s   speed %dx%s   %s %s  seed %d  t=%d s" % [vol_db, "  MUTED" if muted else "", speed,
			"   PAUSED" if paused else "", map_path.get_file().get_basename(), mode, seed_now, int(t)]
	if end_wait >= 0.0:
		st += "   restart in %d s" % ceili(end_wait)
	status_label.text = st
	lines_label.text = "\n".join(recent) if not recent.is_empty() else "(waiting for the first sound...)"
	music_label.text = "\n".join(music.status_lines())


# ------------------------------------------------------------------ verification helpers

func _clock() -> float:
	return (Time.get_ticks_msec() - clock0) / 1000.0


func _screenshot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	print("DEMO screenshot ", shot_path)


func _summary() -> void:
	var names := played_types.keys()
	names.sort()
	var parts := []
	for n in names:
		parts.append("%s=%d" % [n, played_types[n]])
	print("DEMO SUMMARY: %d event types played: %s" % [names.size(), ", ".join(parts)])
	print("DEMO SUMMARY: sounds per set %s, runs %d" % [played_sets, runs])
