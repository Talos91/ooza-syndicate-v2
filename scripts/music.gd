class_name Music
extends Node
## MUSIC: the soundtrack (Cyberpunk Music Pack by SmellyCatCafe, smellycatcafe.itch.io - bought by Daniele, "free and
## commercial projects, crediting appreciated"), the slots and mix Daniele approved in the spectate demo (branch
## sound-demo 912ee68, demo/music_director.gd). Every number and the track of each slot: Rules' MUSIC block.
##   MENU             the menus (and the load / VERSUS / briefing before a match's clock runs), looping
##   BATTLE           a match: the playlist (Rules.MUSIC_TRACKS["BATTLE"]), the next track each time one ends (and at
##                    each new match), crossfading Rules.MUSIC_XFADE_PLAYLIST s
##   LAST STAND       crossfades in (Rules.MUSIC_XFADE_LAST_STAND) when the Last Stand starts
##   VERY LAST STAND  the same at the Very Last Stand (6:00)
##   VICTORY / DEFEAT a stinger at the match's end, played once: your side won = VICTORY; a draw, a loss, spectating
##                    (knocked out, or an all-AI demo) = DEFEAT. Then silence until the menu.
## One node for the whole run, under the tree root (it outlives the scene reloads between menu and match, so a
## crossfade survives them): main.gd calls Music.attach(self) at the top of _ready, next to Sfx.attach (one marked
## line), and the node reads that main each frame - `started`, its `sim` (over / winner / last_stand_active /
## very_last_stand_active / time), HUMAN, demo. An online guest's sim is the host's snapshots, so a guest hears the
## same slots; the room server (Net.dedicated) and headless runs build nothing (Sfx._can_play).
## Two AudioStreamPlayers crossfade (equal power) on the "Music" bus (Sfx.ensure_buses); Sfx calls Music.duck() when
## it plays one of Rules.MUSIC_DUCK_EVENTS (capture, Last Stand, Very Last Stand, win), which dips the bus
## Rules.MUSIC_DUCK_DB for a moment.
## The tracks are not in git (the repo is public; tools/copy_music.py copies them into Rules.MUSIC_DIR before an import /
## export). Native and editor runs load them straight from res:// and play them on two AudioStreamPlayers.
## WEB (0.22.4, Music session): the browser plays them, not Godot - web/music.js's two <audio> elements (JavaScriptBridge
## interface "OozeMusic"), each through a GainNode in the AudioContext the SFX unlock. The browser streams and decodes
## off the main thread: Godot's mixer decoded Vorbis on the main thread every frame (no threads on the web export) and
## lagged phones; a WebAudio sample decodes the whole track at once (seconds of stall, tens of MB). The files are loose
## beside index.html, fetched per track: Rules.MUSIC_WEB_DIR (desktop, stereo 44.1 kHz) or MUSIC_WEB_DIR_PHONE (mono
## 22 kHz, Daniele 2026-09-29) by PerfProfile.is_phone() - the light / HD rule. Not in any .pck (the "Web" preset
## excludes assets/audio/music/*); tools/copy_music.py --web fills both folders (BUILD-LOG sec10). Every failure
## (no WebAudio, a 404, autoplay refused until a tap, offline) is silence, never an error.
## SETTINGS > DISPLAY > AUDIO and PAUSE > SETTINGS: MUSIC ON / OFF and MUSIC VOLUME (Rules.MUSIC_VOLUME_STEPS, %), saved
## in user://settings.cfg [audio] music_on_v2 / music_volume_v2 (Sfx.path: the same file), applied to the Music bus (web:
## music.js's master gain) at once; OFF stops the players (nothing decodes, nothing downloads).
## Debug: --music-log (after `--`) prints every slot change.

static var _node: Music = null
static var _pack := ""                    # "" / "ready" / "failed" (the tracks: in res://, or web/music.js)
static var _jsm: JavaScriptObject = null  # web: window.OozeMusic (web/music.js)
static var _volume := -1                  # MUSIC VOLUME, % (-1 until read)
static var _on := true                    # MUSIC ON / OFF
static var _streams := {}                 # track name -> AudioStream (null: missing)
static var _battle_next := 0              # the playlist's next entry (it runs on across matches)
static var test_len := 0.0                # tests: > 0 treats every track as this long (the playlist changes sooner)
static var played := {}                   # slot -> times it started (debug / tests/sound_check.gd)
static var log_on := "--music-log" in OS.get_cmdline_user_args()

var main: Node = null                     # the scene's main (Music.attach); freed on a reload until the next attach
var players: Array[AudioStreamPlayer] = []
var amp := [0.0, 0.0]
var fades := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]   # per player [from, to, t, length]; length 0 = still
var cur := -1                             # the player holding the current track
var phase := ""                           # the slot the game wants ("" nothing yet / music off)
var slot := ""                            # the slot playing ("" silence)
var track := ""
var track_t := 0.0                        # s since the current track started (test_len)
var duck_left := 0.0
var duck_env := 0.0                       # dB the duck takes off the bus now (0 .. Rules.MUSIC_DUCK_DB)


# ------------------------------------------------------------------ the settings (user://settings.cfg [audio])
static func _load() -> void:
	if _volume >= 0:
		return
	_volume = Rules.MUSIC_VOLUME_DEFAULT
	_on = Rules.MUSIC_ON_DEFAULT
	var cf := ConfigFile.new()
	if cf.load(Sfx.path) == OK:
		# 0.22.4 (Daniele 2026-09-29: "default volume needs to be toned down"): a new key, so the lower default reaches everyone once.
		_volume = clampi(int(cf.get_value("audio", "music_volume_v2", _volume)), 1, 100)
		# HOTFIX 0.22.2 (Daniele: "audio is super laggy and the mute doesn't work, unplayable"): the key is new, so every device starts
		# OFF again whatever 0.22.1 saved; music plays only for who switches it ON.
		_on = bool(cf.get_value("audio", "music_on_v2", Rules.MUSIC_ON_DEFAULT))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(Sfx.path)                                  # keep the other keys and sections (SOUND's, [graphics], ...)
	cf.set_value("audio", "music_volume_v2", _volume)
	cf.set_value("audio", "music_on_v2", _on)
	cf.save(Sfx.path)


static func volume() -> int:
	_load()
	return _volume


static func music_on() -> bool:
	_load()
	return _on


static func set_volume(pct: int) -> void:
	## SETTINGS > MUSIC VOLUME: saved and heard at once (the Music bus).
	_load()
	_volume = clampi(pct, 1, 100)
	_save()
	apply_settings()


static func set_on(on: bool) -> void:
	## SETTINGS > MUSIC ON / OFF: OFF mutes the Music bus and stops the players (the VOLUME is kept for ON).
	_load()
	_on = on
	_save()
	apply_settings()
	if _node != null and is_instance_valid(_node):
		if on:
			_need_pack()
		else:
			_node._silence()                           # at once, not at the next frame: nothing decodes while OFF


static func next_volume() -> int:
	## The step after the current one, round (the pause menu's one-tap MUSIC VOLUME).
	var steps: Array = Rules.MUSIC_VOLUME_STEPS
	var i := steps.find(volume())
	return int(steps[(i + 1) % steps.size()])


static func volume_label(pct := -1) -> String:
	return "%d %%" % (volume() if pct < 0 else pct)


static func bus_db() -> float:
	## The Music bus without the duck: Rules.MUSIC_LEVEL_DB plus what MUSIC VOLUME puts on it.
	return Rules.MUSIC_LEVEL_DB + linear_to_db(volume() / 100.0)


static func apply_settings() -> void:
	_load()
	Sfx.ensure_buses()
	var i := AudioServer.get_bus_index(Rules.SOUND_MUSIC_BUS)
	var duck: float = _node.duck_env if _node != null and is_instance_valid(_node) else 0.0
	AudioServer.set_bus_volume_db(i, bus_db() + duck)
	AudioServer.set_bus_mute(i, not _on)
	_web_level(duck)


static func _web_level(duck: float) -> void:
	## Web: the Music bus's level on music.js's master gain (the <audio> elements bypass Godot's buses).
	var js := _js()
	if js != null:
		js.level(db_to_linear(bus_db() + duck) if _on else 0.0)


# ------------------------------------------------------------------ the node
static func attach(m: Node) -> void:
	## main.gd, top of _ready, next to Sfx.attach (one marked line): this scene's main drives the music from now on.
	if not Sfx._can_play(m):
		return
	apply_settings()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _node == null or not is_instance_valid(_node):
		_node = Music.new()
		_node.name = "Music"
		_node.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(_node)       # (the root may still be adding its children: a first launch)
	_node.main = m
	if _on:
		_need_pack()


static func duck() -> void:
	## Sfx, when it plays one of Rules.MUSIC_DUCK_EVENTS: the music dips under it.
	if _node != null and is_instance_valid(_node):
		_node.duck_left = Rules.MUSIC_DUCK_HOLD


static func pack_state() -> String:
	## Debug / tests: "" (not needed yet) / "loading" / "ready" / "failed".
	return _pack


static func now_playing() -> Dictionary:
	## Debug / tests: {"phase", "slot", "track", "pos", "duck_db"} ({} before the node exists).
	if _node == null or not is_instance_valid(_node):
		return {}
	var n := _node
	var pos := -1.0
	if n.cur >= 0 and n._p_playing(n.cur):
		pos = n._p_pos(n.cur)
	return {"phase": n.phase, "slot": n.slot, "track": n.track, "pos": pos, "duck_db": n.duck_env}


static func slot_for(started: bool, s: Sim, human: String, spectating: bool) -> String:
	## The slot the game wants: MENU before a match's clock runs, then BATTLE / LAST STAND / VERY LAST STAND, and at the
	## end VICTORY when your side won (never while spectating an all-AI demo), else DEFEAT (a draw, a loss).
	if not started or s == null:
		return "MENU"
	if s.over:
		var w := str(s.winner)
		return "VICTORY" if not spectating and w != "" and s.allied(w, human) else "DEFEAT"
	if s.time <= 0.0:
		return "MENU"
	if s.very_last_stand_active:
		return "VERY LAST STAND"
	if s.last_stand_active:
		return "LAST STAND"
	return "BATTLE"


static func _need_pack() -> void:
	## The tracks, the first time music is needed: web/music.js on the web (each track fetched when it plays), else
	## res:// (native, editor).
	if _pack != "":
		return
	if OS.has_feature("web"):
		var js := _js()
		_pack = "ready" if js != null and bool(js.available()) else "failed"
		if _pack == "failed":
			print("Music: no web/music.js or no WebAudio - silent")
		return
	if ResourceLoader.exists(_path(str((Rules.MUSIC_TRACKS["MENU"] as Array)[0]))):
		_pack = "ready"
		return
	_pack = "failed"
	print("Music: no soundtrack in %s (python tools/copy_music.py, then import) - silent" % Rules.MUSIC_DIR)


static func _js() -> JavaScriptObject:
	## Web: window.OozeMusic (web/music.js, in the page head), or null.
	if _jsm == null and OS.has_feature("web"):
		_jsm = JavaScriptBridge.get_interface("OozeMusic")
	return _jsm


static func web_url(name: String) -> String:
	## Web: a track's file beside index.html - the phone set (mono 22 kHz) on a phone, else the desktop set.
	var dir := Rules.MUSIC_WEB_DIR_PHONE if PerfProfile.is_phone() else Rules.MUSIC_WEB_DIR
	return "%s%s.ogg?v=%s" % [dir, name.uri_encode(), Rules.VERSION.uri_encode()]


static func _path(name: String) -> String:
	return Rules.MUSIC_DIR + name + ".ogg"


static func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var p := _path(name)
		var st: AudioStream = load(p) if ResourceLoader.exists(p) else null
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = false  # this node loops / chains them with a crossfade
		_streams[name] = st
	return _streams[name]


func _ready() -> void:
	for i in range(2):
		var p := AudioStreamPlayer.new()                # (native / editor; the web plays music.js's elements)
		p.bus = Rules.SOUND_MUSIC_BUS
		add_child(p)
		players.append(p)


func _exit_tree() -> void:
	if _node == self:
		_node = null


func _process(dt: float) -> void:
	_step_duck(dt)
	if not _on:                                        # MUSIC OFF: nothing plays or decodes; ON starts afresh
		if phase != "" or cur >= 0:
			_silence()
		return
	if _pack != "ready":
		return
	var want := _target()
	if want != phase:
		_enter(want)
	_step_fades(dt)
	track_t += dt
	if slot in Rules.MUSIC_STINGERS:
		# Daniele (2026-09-28): after the VICTORY / DEFEAT stinger the MENU music comes back on the results screen (was silence).
		# The phase stays the stinger's (it is not re-entered); only the slot moves on to MENU, which loops as usual.
		var ended := cur < 0 or not _p_playing(cur)
		if test_len > 0.0:
			ended = track_t >= test_len
		if ended and phase in Rules.MUSIC_STINGERS:
			_play("MENU", Rules.MUSIC_XFADE_START)
		return
	if cur >= 0 and track != "" and _p_ended(cur):   # web: ended before the crossfade (a length estimate): chain on
		_play(slot, Rules.MUSIC_XFADE_START)
		return
	if cur < 0 or track == "" or not _p_playing(cur):
		return
	var length: float = test_len if test_len > 0.0 else _p_len(cur)
	var pos: float = track_t if test_len > 0.0 else _p_pos(cur)
	if length > 0.0 and length - pos <= Rules.MUSIC_XFADE_PLAYLIST:    # the track's end: the playlist's next, or the slot loops
		_play(slot, Rules.MUSIC_XFADE_PLAYLIST)


func _silence() -> void:
	## MUSIC OFF: both players stopped now (a muted bus still decodes), the state cleared so ON starts afresh.
	for i in range(2):
		_fade(i, 0.0, 0.0)
		_p_stop(i)
		players[i].stream = null
	cur = -1
	phase = ""
	slot = ""
	track = ""


func _target() -> String:
	if main == null or not is_instance_valid(main):
		return phase                                   # a scene reload in between: keep what plays
	var s: Sim = main.get("sim") as Sim if main.get("sim") is Sim else null
	var human := str(main.get("HUMAN")) if main.get("HUMAN") != null else "A"
	return slot_for(main.get("started") == true, s, human, main.get("demo") == true)


func _enter(want: String) -> void:
	var was := phase
	phase = want
	var xf := Rules.MUSIC_XFADE_PHASE
	if cur < 0 or not _p_playing(cur):
		xf = Rules.MUSIC_XFADE_START                   # from silence
	elif want in ["LAST STAND", "VERY LAST STAND"]:
		xf = Rules.MUSIC_XFADE_LAST_STAND
	elif want in Rules.MUSIC_STINGERS:
		xf = Rules.MUSIC_XFADE_STINGER
	if log_on:
		print("MUSIC %s -> %s" % [was if was != "" else "(silence)", want])
	_play(want, xf)


func _play(to: String, xfade: float) -> void:
	## Crossfades from whatever plays to `to`'s track (BATTLE: the playlist's next).
	var names: Array = Rules.MUSIC_TRACKS.get(to, [])
	var name := ""
	if not names.is_empty():
		if to == "BATTLE":
			name = str(names[_battle_next % names.size()])
			_battle_next += 1
		else:
			name = str(names[0])
	if cur >= 0:
		_fade(cur, 0.0, xfade)
	var nxt := 0 if cur < 0 else 1 - cur
	amp[nxt] = 0.0 if xfade > 0.0 else 1.0
	_p_stop(nxt)
	_p_amp(nxt, amp[nxt])
	if name == "" or not _p_start(nxt, name):         # a slot without a track (a missing file): silence
		slot = ""
		track = ""
		return
	_fade(nxt, 1.0, xfade)
	cur = nxt
	slot = to
	track = name
	track_t = 0.0
	played[to] = int(played.get(to, 0)) + 1
	if log_on:
		print("MUSIC %s plays %s (crossfade %.1f s)" % [to, name, xfade])


func _fade(i: int, to: float, length: float) -> void:
	fades[i] = [amp[i], to, 0.0, maxf(length, 0.0)]
	if length <= 0.0:
		amp[i] = to
		_p_amp(i, to)
		if to <= 0.0:
			_p_stop(i)


func _step_fades(dt: float) -> void:
	for i in range(2):
		var f: Array = fades[i]
		if float(f[3]) <= 0.0:
			continue
		f[2] = float(f[2]) + dt
		var x := clampf(float(f[2]) / float(f[3]), 0.0, 1.0)
		var e := sin(x * PI * 0.5) if float(f[1]) > float(f[0]) else 1.0 - cos(x * PI * 0.5)   # equal power
		amp[i] = lerpf(float(f[0]), float(f[1]), e)
		_p_amp(i, amp[i])
		if x >= 1.0:
			f[3] = 0.0
			if float(f[1]) <= 0.0:
				_p_stop(i)                             # faded out: stopped (the web frees its buffer)


func _step_duck(dt: float) -> void:
	## The duck's envelope on the Music bus: down Rules.MUSIC_DUCK_DB in MUSIC_DUCK_IN s, held, up in MUSIC_DUCK_OUT s.
	var depth := Rules.MUSIC_DUCK_DB
	var goal := depth if duck_left > 0.0 else 0.0
	duck_left = maxf(duck_left - dt, 0.0)
	if is_equal_approx(goal, duck_env):
		return
	var secs := Rules.MUSIC_DUCK_IN if goal < duck_env else Rules.MUSIC_DUCK_OUT
	duck_env = move_toward(duck_env, goal, absf(depth) / maxf(secs, 0.01) * dt)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(Rules.SOUND_MUSIC_BUS), bus_db() + duck_env)
	_web_level(duck_env)


# ------------------------------------------------------------------ the two players: Godot's (native) or music.js's (web)
func _p_start(i: int, name: String) -> bool:
	## Player i plays track `name` from its start (its gain set before); false: no such track.
	var js := _js()
	if js != null:
		return bool(js.start(i, web_url(name)))
	var st := _stream(name)
	if st == null:
		return false
	players[i].stream = st
	players[i].play()
	return true


func _p_stop(i: int) -> void:
	var js := _js()
	if js != null:
		js.stop(i)
	players[i].stop()


func _p_amp(i: int, a: float) -> void:
	var js := _js()
	if js != null:
		js.gain(i, maxf(a, 0.0))
	else:
		players[i].volume_db = linear_to_db(maxf(a, 0.0001))


func _p_playing(i: int) -> bool:
	var js := _js()
	return bool(js.playing(i)) if js != null else players[i].playing


func _p_ended(i: int) -> bool:
	## Web only: the track played to its end without the crossfade (native players always crossfade first).
	var js := _js()
	return js != null and bool(js.ended(i))


func _p_pos(i: int) -> float:
	var js := _js()
	return float(js.pos(i)) if js != null else players[i].get_playback_position()


func _p_len(i: int) -> float:
	## The track's length, s (-1 while the web has no metadata yet).
	var js := _js()
	if js != null:
		return float(js.len(i))
	return players[i].stream.get_length() if players[i].stream != null else -1.0
