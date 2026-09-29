extends Node
## SOUND + MUSIC check (a scene: tests/sound_check.tscn), windowed - a headless run builds no Sfx / Music:
##   timeout 240 Godot --path . tests/sound_check.tscn [-- --sfx-log --music-log]
## Needs the soundtrack in res://assets/audio/music/ (python tools/copy_music.py, then import): the MUSIC checks fail
## without it.
## 1. MUSIC slots as a rule (Music.slot_for on a bare Sim): MENU / BATTLE / LAST STAND / VERY LAST STAND / VICTORY /
##    DEFEAT (a loss, a draw, spectating, a team-mate's win).
## 2. The menu: this node stands in for main (started = false) - the MENU track loads from res:// (native: no
##    music.pck) and plays; MUSIC ON / OFF and MUSIC VOLUME move the Music bus at once (saved to a test cfg, never the
##    player's), apart from the Sfx bus.
## 3. A match: spectates an AI-vs-AI BRAWL match (M-30 Sporefall Plain, FFA4, Veteran - the sound demo's board),
##    fast-forwarded silently to FF s of match time: the music crossfades MENU -> BATTLE, the playlist moves on at a
##    track's end (Music.test_len shortens the tracks), Sfx plays at least MIN_TYPES different match events in SECONDS of
##    real time, SOUND ON / OFF and VOLUME move the Sfx bus (not Master, not Music), a UI tap plays; then the Last Stand
##    (the real start, Sim.start_last_stand_now) switches to LAST STAND and its alarm ducks the music, the Very Last Stand
##    to VERY LAST STAND, and your win (seat A) plays the VICTORY stinger once, then the MENU music (0.22.1).
## Prints the counts; exit code 0 = passed. Headless it prints SKIP and exits 0.

const MAP := "res://maps4/M-30-sporefall-plain.json"
const SECONDS := 60.0
const FF := 150.0                                  # match time fast-forwarded (silent) first: the AI idles ~25 s at the start
const MIN_TYPES := 10
const CFG := "user://test_sound.cfg"
const MENU_SECONDS := 4.0                          # real seconds of the menu stand-in before the match loads
const LS_BY := 45.0                                # real s: the Last Stand, if 3:00 hasn't started it by then

var started := false                               # (Music reads this node as main until the match's main attaches)
var main: Node3D
var t := 0.0
var menu_t := 0.0
var fails := 0
var step := 0
var first_battle := ""
var ls_t := -1.0                                   # real s the Last Stand started at
var vls_t := -1.0
var sim: Sim


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	fails += 0 if cond else 1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP sound_check: needs a window (a headless run builds no Sfx / Music)")
		get_tree().quit(0)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	Sfx.path = CFG
	Sfx._volume = -1                                   # read the (empty) test cfg: the default levels
	Music._volume = -1
	check(Music.music_on() == Rules.MUSIC_ON_DEFAULT and Music.volume() == Rules.MUSIC_VOLUME_DEFAULT,
			"first run: MUSIC %s (0.23.0: ON again), MUSIC VOLUME %d %%" % ["ON" if Rules.MUSIC_ON_DEFAULT else "OFF", Rules.MUSIC_VOLUME_DEFAULT])
	Music.set_on(true)                                 # the default is OFF since the 0.22.2 hotfix: the check plays it on purpose
	_check_slots()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1266, 585))
	Music.attach(self)                                 # the menu: nothing started


func _start_match() -> void:
	Rules.abilities_on = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", MAP)
	main.set("mode", "FFA4")
	main.set("demo", true)
	main.set("ai_level", "Veteran")
	main.set("seed_value", 11)
	main.set("ff_to", FF)
	add_child(main)                                    # its _ready: Sfx.attach, Music.attach(main)


func _process(dt: float) -> void:
	if main == null:
		menu_t += dt
		if menu_t > MENU_SECONDS:
			_check_menu()
			_start_match()
		return
	if not bool(main.get("started")):
		return
	t += dt
	sim = main.get("sim")
	var np := Music.now_playing()
	match step:
		0:
			if t > 3.0:                                # MENU -> BATTLE took MUSIC_XFADE_PHASE
				step = 1
				first_battle = str(np.get("track", ""))
				check(str(np.get("slot", "")) == "BATTLE" and first_battle in Rules.MUSIC_TRACKS["BATTLE"] and float(np.get("pos", -1.0)) > 0.0,
						"the match: MENU -> BATTLE, %s playing (%s)" % [first_battle, np])
				_check_sfx_settings()
				Music.test_len = 5.0                   # every track "5 s long": the playlist moves on now
		1:
			if t > 6.0:
				step = 2
				check(str(np.get("slot", "")) == "BATTLE" and str(np.get("track", "")) != first_battle and int(Music.played.get("BATTLE", 0)) >= 2,
						"the playlist moved on at the track's end: %s -> %s (BATTLE started %d times)" % [first_battle,
						np.get("track", ""), int(Music.played.get("BATTLE", 0))])
				Music.test_len = 0.0
		2:                                             # the Last Stand: at 3:00 on its own (FF + ~30 s), else started here
			if sim.last_stand_active and ls_t < 0.0:
				ls_t = t
			elif not sim.last_stand_active and t > LS_BY:
				sim.start_last_stand_now()             # the real start: rings, the banner, the alarm (Sfx), the duck
			if ls_t >= 0.0 and t > ls_t + 0.6:
				step = 3
				check(str(np.get("slot", "")) == "LAST STAND" and str(np.get("track", "")) == str(Rules.MUSIC_TRACKS["LAST STAND"][0]),
						"LAST STAND starts (match t=%.0f): its track (%s)" % [sim.time, np])
				check(float(np.get("duck_db", 0.0)) < -0.5, "the Last Stand alarm ducks the music (%.2f dB, Sfx played last_stand %d)" % [
						float(np.get("duck_db", 0.0)), int(Sfx.played.get("last_stand", 0))])
		3:
			if t > ls_t + 4.0:
				step = 4
				check(is_equal_approx(float(np.get("duck_db", -9.0)), 0.0), "the duck is back up (%.2f dB)" % float(np.get("duck_db", -9.0)))
		4:
			if t > SECONDS:
				step = 5
				_check_sfx_events()
				sim.start_very_last_stand_now()
				vls_t = t
		5:
			if t > vls_t + 1.5:
				step = 6
				check(sim.very_last_stand_active and str(np.get("slot", "")) == "VERY LAST STAND", "VERY LAST STAND: its track (%s)" % [np])
				main.set("demo", false)                # you (seat A) win - the way main's --end-shot ends a match
				sim.winner = "A"
				sim.over = true
		6:
			if t > vls_t + 2.5:
				step = 7
				check(str(np.get("slot", "")) == "VICTORY" and float(np.get("pos", -1.0)) > 0.0, "your win: the VICTORY stinger (%s)" % [np])
		7:
			if t > vls_t + 2.5 + Rules.MUSIC_STINGER_LEN + 1.0:
				step = 8
				check(str(np.get("slot", "")) == "MENU" and float(np.get("pos", -1.0)) > 0.0 and str(np.get("phase", "")) == "VICTORY"
						and int(Music.played.get("VICTORY", 0)) == 1,
						"the stinger played once, then the MENU music on the results screen (Daniele, 0.22.1) (%s)" % [np])
				print("MUSIC CHECK: slots started %s" % [Music.played])
				get_tree().quit(1 if fails > 0 else 0)


func _check_slots() -> void:
	var s := Sim.new()
	check(Music.slot_for(false, s, "A", false) == "MENU" and Music.slot_for(true, null, "A", false) == "MENU", "slot: the menus = MENU")
	check(Music.slot_for(true, s, "A", false) == "MENU", "slot: a match whose clock hasn't run (load, VERSUS, briefing) = MENU")
	s.time = 12.0
	check(Music.slot_for(true, s, "A", false) == "BATTLE", "slot: the match = BATTLE")
	s.last_stand_active = true
	check(Music.slot_for(true, s, "A", false) == "LAST STAND", "slot: Last Stand = LAST STAND")
	s.very_last_stand_active = true
	check(Music.slot_for(true, s, "A", false) == "VERY LAST STAND", "slot: Very Last Stand = VERY LAST STAND")
	s.over = true
	s.winner = "A"
	check(Music.slot_for(true, s, "A", false) == "VICTORY", "slot: you won = VICTORY")
	check(Music.slot_for(true, s, "A", true) == "DEFEAT", "slot: spectating (an all-AI demo) = DEFEAT")
	s.winner = "B"
	check(Music.slot_for(true, s, "A", false) == "DEFEAT", "slot: lost = DEFEAT")
	s.winner = ""
	check(Music.slot_for(true, s, "A", false) == "DEFEAT", "slot: a draw = DEFEAT")
	s.teams = {"A": 0, "C": 0, "B": 1, "D": 1}
	s.winner = "C"
	check(Music.slot_for(true, s, "A", false) == "VICTORY", "slot: your team-mate won (2v2) = VICTORY")


func _check_menu() -> void:
	var np := Music.now_playing()
	var menu_track: String = Rules.MUSIC_TRACKS["MENU"][0]
	var st: AudioStream = Music._streams.get(menu_track)
	check(Music.pack_state() == "ready" and st != null and st.resource_path.begins_with(Rules.MUSIC_DIR),
			"native: the soundtrack loads straight from res:// (%s, pack %s)" % [st.resource_path if st else "missing", Music.pack_state()])
	check(str(np.get("slot", "")) == "MENU" and str(np.get("track", "")) == menu_track and float(np.get("pos", -1.0)) > 1.0,
			"the menu plays MENU: %s (%s)" % [menu_track, np])
	var mb := AudioServer.get_bus_index(Rules.SOUND_MUSIC_BUS)
	var sb := AudioServer.get_bus_index(Rules.SOUND_SFX_BUS)
	var mp: AudioStreamPlayer = Music._node.players[Music._node.cur]
	check(Music.music_on() == true and Music.volume("menu") == Rules.MUSIC_VOLUME_DEFAULT and Music.volume("match") == Rules.MUSIC_VOLUME_DEFAULT
			and is_equal_approx(AudioServer.get_bus_volume_db(mb), Rules.MUSIC_LEVEL_DB) and not AudioServer.is_bus_mute(mb)
			and absf(mp.volume_db - linear_to_db(Rules.MUSIC_VOLUME_DEFAULT / 100.0)) < 0.05,
			"MUSIC ON (switched on by the check: OFF is the default since 0.22.2): the Music bus %.1f dB, the MENU track at MENU MUSIC %d %% (%.1f dB)" % [AudioServer.get_bus_volume_db(mb), Rules.MUSIC_VOLUME_DEFAULT, mp.volume_db])
	Music.set_volume(60, "match")
	check(absf(mp.volume_db - linear_to_db(Rules.MUSIC_VOLUME_DEFAULT / 100.0)) < 0.05 and Music.volume("match") == 60,
			"MATCH MUSIC 60 %%: the MENU track keeps MENU MUSIC (%.1f dB)" % mp.volume_db)
	Music.set_volume(15, "menu")
	check(absf(mp.volume_db - linear_to_db(0.15)) < 0.05 and Music.volume("match") == 60,
			"MENU MUSIC 15 %%: the MENU track at once (%.1f dB), MATCH MUSIC kept" % mp.volume_db)
	var was_on := Music.music_on()
	check(Music.toggle_on() == not was_on and not Music.music_on() and not mp.playing and Music.toggle_on() and Music.music_on(),
			"the top-right MUSIC button (toggle_on): OFF stops the music at once, ON again")
	var sfx_db := AudioServer.get_bus_volume_db(sb)
	Music.set_volume(30)
	check(Music.volume("menu") == 30 and Music.volume("match") == 30 and is_equal_approx(AudioServer.get_bus_volume_db(mb), Rules.MUSIC_LEVEL_DB)
			and is_equal_approx(AudioServer.get_bus_volume_db(sb), sfx_db) and is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0),
			"one MUSIC VOLUME 30 %% sets both; the Music bus stays at its level (%.1f dB); Sfx and Master untouched" % AudioServer.get_bus_volume_db(mb))
	Music.set_on(false)
	var cf := ConfigFile.new()
	check(AudioServer.is_bus_mute(mb) and not AudioServer.is_bus_mute(sb) and cf.load(CFG) == OK
			and not bool(cf.get_value("audio", "music_on_v3", true)) and int(cf.get_value("audio", "music_volume_v2", 0)) == 30,
			"MUSIC OFF: the Music bus muted (Sfx not), saved in [audio] music_on_v3 / music_volume_v2")
	Music._volume = -1                                 # read back from the file, as the next run would
	check(not Music.music_on() and Music.volume() == 30 and Music.next_volume() == 60, "[audio] read back: OFF, 30 %; the cycle 30 -> 60")
	Music.set_on(true)
	Music.set_volume(Rules.MUSIC_VOLUME_DEFAULT)
	check(not AudioServer.is_bus_mute(mb), "MUSIC ON again")


func _check_sfx_settings() -> void:
	var bus := AudioServer.get_bus_index(Rules.SOUND_SFX_BUS)
	var mb := AudioServer.get_bus_index(Rules.SOUND_MUSIC_BUS)
	var music_db := AudioServer.get_bus_volume_db(mb)
	check(Sfx.volume() == Rules.SOUND_VOLUME_DEFAULT and is_equal_approx(AudioServer.get_bus_volume_db(bus),
			Rules.SOUND_SFX_BUS_DB + linear_to_db(Rules.SOUND_VOLUME_DEFAULT / 100.0)) and is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0),
			"first run: SOUND ON, VOLUME %d %% on the Sfx bus (%.1f dB), Master 0 dB" % [Rules.SOUND_VOLUME_DEFAULT, AudioServer.get_bus_volume_db(bus)])
	Sfx.set_volume(25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), Rules.SOUND_SFX_BUS_DB + linear_to_db(0.25)) and not AudioServer.is_bus_mute(bus)
			and is_equal_approx(AudioServer.get_bus_volume_db(mb), music_db),
			"VOLUME 25 %%: the Sfx bus at once (%.1f dB), the Music bus untouched" % AudioServer.get_bus_volume_db(bus))
	Sfx.set_on(false)
	var cf := ConfigFile.new()
	check(AudioServer.is_bus_mute(bus) and not AudioServer.is_bus_mute(mb) and not AudioServer.is_bus_mute(0) and not Sfx.sound_on()
			and cf.load(CFG) == OK and not bool(cf.get_value("audio", "on", true)) and bool(cf.get_value("audio", "music_on_v3", false)),
			"SOUND OFF: the Sfx bus muted (Music and Master not), saved in [audio] beside MUSIC's keys")
	Sfx.set_volume(100)
	check(AudioServer.is_bus_mute(bus), "SOUND OFF stays silent whatever the VOLUME")
	Sfx.set_on(true)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), Rules.SOUND_SFX_BUS_DB) and not AudioServer.is_bus_mute(bus), "SOUND ON at VOLUME 100 %: 0 dB")
	Sfx._volume = -1                                   # read back from the file, as the next run would
	check(Sfx.sound_on() and Sfx.volume() == 100, "[audio] read back: ON, 100 %")
	check(Sfx.next_volume() == int(Rules.SOUND_VOLUME_STEPS[0]) and Sfx.volume_label() == "100 %", "the cycle: 100 %% -> %d %%" % int(Rules.SOUND_VOLUME_STEPS[0]))
	Sfx.set_volume(Rules.SOUND_VOLUME_DEFAULT)
	var before := int(Sfx.played.get("ui_tap", 0))
	Sfx.play_ui("tap")
	check(int(Sfx.played.get("ui_tap", 0)) == before + 1, "a UI tap plays")


func _check_sfx_events() -> void:
	var types := []
	for k in Sfx.played:
		if not str(k).begins_with("ui_"):
			types.append(k)
	types.sort()
	var parts := []
	for k in types:
		parts.append("%s=%d" % [k, Sfx.played[k]])
	print("SOUND CHECK: %d match event types in %.0f s (match t=%.0f): %s" % [types.size(), t, sim.time, ", ".join(parts)])
	var tel := {}                                      # the Sim's own telemetry over the same match, for comparison
	for ev in sim.events:
		if float(ev.get("t", 0.0)) < FF:
			continue
		tel[ev["type"]] = int(tel.get(ev["type"], 0)) + 1
	print("SOUND CHECK: the Sim's telemetry: %s" % [tel])
	check(types.size() >= MIN_TYPES, "at least %d match event types played" % MIN_TYPES)
