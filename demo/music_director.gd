extends Node
## SOUND DEMO music (branch sound-demo, never shipped): the match's music slots, each with a pick Daniele can
## cycle through all 15 tracks of the Cyberpunk Music Pack (SmellyCatCafe). Two players crossfade (equal power)
## on a "Music" bus under the "SFX" bus; big cues duck it. sound_demo.gd feeds it the match phase every frame.
##   MENU        the first SOUND.menu_seconds of every match (a menu preview), or while H holds it
##   BATTLE 1-3  the battle playlist (2-3 tracks, BATTLE 2 / 3 may be off), crossfading at each track's end
##   LAST STAND  crossfades in when Last Stand starts;  VERY LAST STAND the same at Very Last Stand (may be off)
##   VICTORY / DEFEAT  stingers at the match end: the first SOUND.stinger_len s of the track, fading out over SOUND.stinger_fade
## Single-track slots loop with the same crossfade.

const DIR := "res://demo_music/"
const TRACKS := ["Boss Battle", "Cyber Alley", "Cyber Sunrise", "Drone Patrol", "Ending Theme", "Game Over",
		"Hidden Lab", "Holo Arcade", "Holo Bazaar", "Midnight Hack", "Neon Escape", "Neon Rain", "Neon Street",
		"Rooftop Chase", "Synth Syndicate"]
const SLOTS := ["MENU", "BATTLE 1", "BATTLE 2", "BATTLE 3", "LAST STAND", "VERY LAST STAND", "VICTORY", "DEFEAT"]
const MAY_BE_OFF := ["BATTLE 2", "BATTLE 3", "VERY LAST STAND"]
# Every number (crossfades, stinger, ducking, the music level) comes from sound_demo.gd's SOUND table (`cfg`).

# Kept across a restart (the scene reloads).
static var picks := {"MENU": "Cyber Sunrise", "BATTLE 1": "Drone Patrol", "BATTLE 2": "Neon Street",
		"BATTLE 3": "Synth Syndicate", "LAST STAND": "Midnight Hack", "VERY LAST STAND": "Boss Battle",
		"VICTORY": "Ending Theme", "DEFEAT": "Game Over"}
static var sel := 0                # the slot TAB selected
static var on := true
static var music_db := 0.0         # the music bus (the SOUND table's "music_db" at the first start; , / . change it)
static var _db_set := false
static var hold_menu := false      # H
static var preview := ""           # P: this slot plays now, whatever the match does

var log_on := false
var cfg: Dictionary = {}
var track_len := 0.0               # > 0: treat every track as this long (verification: playlist changes sooner)
var players: Array[AudioStreamPlayer] = []
var amp := [0.0, 0.0]
var fade := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]   # per player [from, to, t, len]; len 0 = still
var cur := -1                      # the player that holds the current track
var cur_slot := ""
var cur_track := ""
var cur_started := 0.0             # real seconds since the current track started
var phase := ""
var battle_i := 0
var stinger_left := -1.0
var duck_left := 0.0
var duck_env := 0.0
var streams := {}
var clock := 0.0
var missing := []


static func ensure_buses() -> void:
	## "SFX" and "Music" buses into Master (the layout survives a scene reload: made once).
	for n in ["SFX", "Music"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")


func setup(log_: bool, len_override: float, sound: Dictionary) -> void:
	log_on = log_
	cfg = sound
	if not _db_set:
		_db_set = true
		music_db = float(cfg["music_db"])
	track_len = len_override
	ensure_buses()
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		players.append(p)
	for t in TRACKS:
		var path: String = DIR + t + ".ogg"
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s == null:
			missing.append(path)
			continue
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = false      # the director loops / chains with a crossfade
		streams[t] = s
	print("MUSIC: %d tracks loaded, %d missing %s" % [streams.size(), missing.size(), missing])
	_apply_bus()


# ------------------------------------------------------------------ every frame

func update(dt: float, info: Dictionary) -> void:
	## dt: real seconds. info: {"clock": real s since the match started, "ls", "vls", "over", "won"}.
	clock = float(info.get("clock", 0.0))
	var target := _target(info)
	if target != phase:
		_enter(target)
	_step_fades(dt)
	cur_started += dt
	if stinger_left >= 0.0:
		stinger_left -= dt
		if stinger_left <= float(cfg["stinger_fade"]) and cur >= 0 and float(fade[cur][1]) > 0.0:
			_fade(cur, 0.0, maxf(stinger_left, 0.05))
			if log_on:
				print("MUSIC t=%.1f %s stinger fades out (%.1f s)" % [clock, cur_slot, float(cfg["stinger_fade"])])
		if stinger_left <= 0.0:
			stinger_left = -1.0
	elif cur >= 0 and players[cur].playing and cur_track != "":
		var length: float = track_len if track_len > 0.0 else players[cur].stream.get_length()
		var pos: float = cur_started if track_len > 0.0 else players[cur].get_playback_position()
		var xf := float(cfg["xfade_playlist"])
		if length - pos <= xf:                           # the track's end: the next in the playlist, or loop
			if phase == "BATTLE":
				battle_i += 1
				_play("BATTLE", xf)
			else:
				_play(phase if preview == "" else preview, xf)
	_step_duck(dt)


func _target(info: Dictionary) -> String:
	if preview != "":
		return "PREVIEW:" + preview
	if bool(info.get("over", false)):
		return "VICTORY" if bool(info.get("won", false)) else "DEFEAT"
	if hold_menu or clock < float(cfg["menu_seconds"]):
		return "MENU"
	if bool(info.get("vls", false)) and str(picks["VERY LAST STAND"]) != "":
		return "VERY LAST STAND"
	if bool(info.get("ls", false)):
		return "LAST STAND"
	return "BATTLE"


func _enter(target: String) -> void:
	var was := phase
	phase = target
	stinger_left = -1.0
	var slot := target.substr(8) if target.begins_with("PREVIEW:") else target
	if log_on:
		print("MUSIC t=%.1f phase %s -> %s" % [clock, was if was != "" else "(start)", target])
	if slot in ["VICTORY", "DEFEAT"]:
		_play(slot, float(cfg["xfade_stinger"]))
		stinger_left = float(cfg["stinger_len"])
	elif slot.begins_with("BATTLE"):
		if slot != "BATTLE":                              # a preview of one playlist entry
			_play(slot, _phase_xfade(was, slot))
		else:
			_play("BATTLE", _phase_xfade(was, slot))
	else:
		_play(slot, _phase_xfade(was, slot))


func _phase_xfade(was: String, to: String) -> float:
	## The crossfade into a new phase: a fade-in from silence at a match's start, the Last Stand alarm's own switch,
	## else the phase crossfade.
	if was == "":
		return float(cfg["xfade_start"])
	if to in ["LAST STAND", "VERY LAST STAND"]:
		return float(cfg["xfade_last_stand"])
	return float(cfg["xfade_phase"])


func _battle_list() -> Array:
	var out := []
	for s in ["BATTLE 1", "BATTLE 2", "BATTLE 3"]:
		if str(picks[s]) != "":
			out.append(s)
	return out


func _play(slot: String, xfade: float) -> void:
	## Crossfades from whatever plays to `slot`'s pick ("BATTLE": the playlist's current entry).
	var real_slot := slot
	if slot == "BATTLE":
		var bl := _battle_list()
		if bl.is_empty():
			real_slot = "BATTLE 1"
		else:
			real_slot = bl[battle_i % bl.size()]
	var track := str(picks.get(real_slot, ""))
	if track == "" or not streams.has(track):
		_stop_all(xfade)
		cur_slot = real_slot
		cur_track = ""
		return
	var nxt := 0 if cur < 0 else 1 - cur
	if cur >= 0:
		_fade(cur, 0.0, xfade)
	var p := players[nxt]
	p.stop()
	p.stream = streams[track]
	amp[nxt] = 0.0 if xfade > 0.0 else 1.0
	p.volume_db = linear_to_db(maxf(amp[nxt], 0.0001))
	p.play()
	_fade(nxt, 1.0, xfade)
	var from := cur_track
	cur = nxt
	cur_slot = real_slot
	cur_track = track
	cur_started = 0.0
	if log_on:
		print("MUSIC t=%.1f %s plays %s (crossfade %.1f s%s)" % [clock, real_slot, track, xfade,
				" from " + from if from != "" else ""])


func _stop_all(xfade: float) -> void:
	for i in range(2):
		if players[i].playing:
			_fade(i, 0.0, xfade)


func _fade(i: int, to: float, length: float) -> void:
	fade[i] = [amp[i], to, 0.0, maxf(length, 0.0)]
	if length <= 0.0:
		amp[i] = to
		fade[i][3] = 0.0
		players[i].volume_db = linear_to_db(maxf(to, 0.0001))
		if to <= 0.0:
			players[i].stop()


func _step_fades(dt: float) -> void:
	for i in range(2):
		var f: Array = fade[i]
		if float(f[3]) <= 0.0:
			continue
		f[2] = float(f[2]) + dt
		var x := clampf(float(f[2]) / float(f[3]), 0.0, 1.0)
		var s := sin(x * PI * 0.5) if float(f[1]) > float(f[0]) else 1.0 - cos(x * PI * 0.5)   # equal power
		amp[i] = lerpf(float(f[0]), float(f[1]), s)
		players[i].volume_db = linear_to_db(maxf(amp[i], 0.0001))
		if x >= 1.0:
			f[3] = 0.0
			if float(f[1]) <= 0.0:
				players[i].stop()
			if log_on and i == cur and float(f[1]) > 0.0:
				print("MUSIC t=%.1f crossfade done: %s (%s)" % [clock, cur_track, cur_slot])


# ------------------------------------------------------------------ mix

func duck() -> void:
	duck_left = float(cfg["duck_hold"])


func _step_duck(dt: float) -> void:
	var depth := float(cfg["duck_db"])
	var goal := depth if duck_left > 0.0 else 0.0
	duck_left = maxf(duck_left - dt, 0.0)
	var secs := float(cfg["duck_in"]) if goal < duck_env else float(cfg["duck_out"])   # down in duck_in, up in duck_out
	duck_env = move_toward(duck_env, goal, absf(depth) / maxf(secs, 0.01) * dt)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db + duck_env)


func _apply_bus() -> void:
	var i := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_mute(i, not on)
	AudioServer.set_bus_volume_db(i, music_db + duck_env)


# ------------------------------------------------------------------ controls (sound_demo.gd's keys)

func next_slot(dir: int) -> void:
	sel = (sel + dir + SLOTS.size()) % SLOTS.size()


func cycle_pick(dir: int) -> void:
	var slot: String = SLOTS[sel]
	var list: Array = TRACKS.duplicate()
	if slot in MAY_BE_OFF:
		list.append("")                                  # "(off)"
	var i := list.find(str(picks[slot]))
	picks[slot] = list[(i + dir + list.size()) % list.size()]
	if log_on:
		print("MUSIC pick %s -> %s" % [slot, _name(str(picks[slot]))])
	if slot == cur_slot or (preview == slot):            # the slot that is playing: hear the new pick now
		if phase == "BATTLE" and slot.begins_with("BATTLE") and str(picks[slot]) == "":
			battle_i += 1
			_play("BATTLE", float(cfg["xfade_pick"]))
		elif stinger_left < 0.0:
			_play(slot if preview == "" else preview, float(cfg["xfade_pick"]))
		else:
			_enter(phase)                                # a stinger restarts with the new track
	elif slot == "VERY LAST STAND":
		phase = ""                                       # on / off can change what should play: recompute


func toggle_on() -> void:
	on = not on
	_apply_bus()
	if log_on:
		print("MUSIC %s" % ("on" if on else "off"))


func change_volume(d: float) -> void:
	music_db = clampf(music_db + d, -40.0, 6.0)
	_apply_bus()
	if log_on:
		print("MUSIC volume %+.0f dB" % music_db)


func toggle_hold_menu() -> void:
	hold_menu = not hold_menu
	if log_on:
		print("MUSIC menu hold %s" % ("on" if hold_menu else "off"))


func toggle_preview() -> void:
	preview = "" if preview == SLOTS[sel] else SLOTS[sel]


func status_lines() -> Array[String]:
	var out: Array[String] = []
	var now := "(silence)"
	if cur >= 0 and players[cur].playing and cur_track != "":
		var p := players[cur]
		now = "%s: %s  %s / %s" % [cur_slot, cur_track, _mmss(p.get_playback_position()), _mmss(p.stream.get_length())]
	var flags := ""
	if not on:
		flags += "  OFF"
	if hold_menu:
		flags += "  MENU HELD"
	if preview != "":
		flags += "  PREVIEW " + preview
	out.append("MUSIC %+.0f dB%s" % [music_db, flags])
	out.append("now  " + now)
	for i in range(SLOTS.size()):
		var s: String = SLOTS[i]
		var playing := s == cur_slot and cur >= 0 and players[cur].playing
		out.append("%s %s %s:  %s" % [">" if i == sel else " ", "*" if playing else " ", s, _name(str(picks[s]))])
	return out


func _name(t: String) -> String:
	return t if t != "" else "(off)"


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
