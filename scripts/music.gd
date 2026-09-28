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
## export). Native and editor runs load them straight from res://. WEB: they are not in index.pck (the "Web" preset
## excludes assets/audio/music/*) but in music.pck beside it (the "Web Music" preset, BUILD-LOG sec10), fetched once
## the first time music is needed (the skins.pck pattern, Cosmetics._fetch_pack) and mounted with
## ProjectSettings.load_resource_pack; nothing plays until it is in, and a failed fetch stays silent (no error).
## On the web the players use PLAYBACK_TYPE_STREAM (Godot's mixer), not the WebAudio samples the SFX use: a sample is
## the whole track decoded at once (seconds of stall and ~40-80 MB per track on a phone).
## SETTINGS > DISPLAY > AUDIO and PAUSE > SETTINGS: MUSIC ON / OFF and MUSIC VOLUME (Rules.MUSIC_VOLUME_STEPS, %), saved
## in user://settings.cfg [audio] music_on / music_volume (Sfx.path: the same file), applied to the Music bus at once;
## OFF stops the players (nothing decodes) and never fetches music.pck.
## Debug: --music-log (after `--`) prints every slot change.

const PACK_FILE := "user://music.pck"

static var _node: Music = null
static var _pack := ""                    # "" / "loading" / "ready" / "failed"
static var _http: HTTPRequest = null
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
		_volume = clampi(int(cf.get_value("audio", "music_volume", _volume)), 1, 100)
		# HOTFIX 0.22.2 (Daniele: "audio is super laggy and the mute doesn't work, unplayable"): the key is new, so every device starts
		# OFF again whatever 0.22.1 saved; music plays only for who switches it ON.
		_on = bool(cf.get_value("audio", "music_on_v2", Rules.MUSIC_ON_DEFAULT))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(Sfx.path)                                  # keep the other keys and sections (SOUND's, [graphics], ...)
	cf.set_value("audio", "music_volume", _volume)
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
	if n.cur >= 0 and n.players[n.cur].playing:
		pos = n.players[n.cur].get_playback_position()
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
	## The tracks, the first time music is needed: in res:// already (native, editor), else music.pck (web).
	if _pack != "":
		return
	if ResourceLoader.exists(_path(str((Rules.MUSIC_TRACKS["MENU"] as Array)[0]))):
		_pack = "ready"
		return
	if not OS.has_feature("web"):
		_pack = "failed"
		print("Music: no soundtrack in %s (python tools/copy_music.py, then import) - silent" % Rules.MUSIC_DIR)
		return
	_fetch_pack()


static func _fetch_pack() -> void:
	## Web: download music.pck from beside index.pck once and mount it (every failure: silence, no error).
	_pack = "loading"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_pack = "failed"
		return
	var url := str(JavaScriptBridge.eval("new URL('%s?v=%s', window.location.href).href" % [Rules.MUSIC_PACK, Rules.VERSION], true))
	_http = HTTPRequest.new()
	_http.download_file = PACK_FILE
	_http.accept_gzip = false                          # GitHub Pages gzips the .pck; never gunzip here (Cosmetics._fetch_pack)
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and ProjectSettings.load_resource_pack(PACK_FILE, false)
		_pack = "ready" if ok else "failed"
		print("Music: %s %s (result %d, HTTP %d)" % [Rules.MUSIC_PACK, "loaded" if ok else "not available - no music", result, code])
		_http.queue_free()
		_http = null)
	print("Music: fetching ", url)
	var http := _http                                  # deferred, then requested once in the tree (a first launch)
	http.tree_entered.connect(func() -> void:
		if http.request(url) != OK:
			_pack = "failed", CONNECT_ONE_SHOT)
	tree.root.add_child.call_deferred(http)


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
		var p := AudioStreamPlayer.new()
		p.bus = Rules.SOUND_MUSIC_BUS
		if OS.has_feature("web"):
			p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM   # the mixer, not a whole-track WebAudio sample
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
		var ended := cur < 0 or not players[cur].playing
		if test_len > 0.0:
			ended = track_t >= test_len
		if ended and phase in Rules.MUSIC_STINGERS:
			_play("MENU", Rules.MUSIC_XFADE_START)
		return
	if cur < 0 or track == "" or not players[cur].playing:
		return
	var length: float = test_len if test_len > 0.0 else players[cur].stream.get_length()
	var pos: float = track_t if test_len > 0.0 else players[cur].get_playback_position()
	if length - pos <= Rules.MUSIC_XFADE_PLAYLIST:    # the track's end: the playlist's next, or the slot loops
		_play(slot, Rules.MUSIC_XFADE_PLAYLIST)


func _silence() -> void:
	## MUSIC OFF: both players stopped now (a muted bus still decodes), the state cleared so ON starts afresh.
	for i in range(2):
		_fade(i, 0.0, 0.0)
		players[i].stop()
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
	if cur < 0 or not players[cur].playing:
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
	var st := _stream(name) if name != "" else null
	if cur >= 0:
		_fade(cur, 0.0, xfade)
	if st == null:                                     # a slot without a track (a missing file): silence
		slot = ""
		track = ""
		return
	var nxt := 0 if cur < 0 else 1 - cur
	var p := players[nxt]
	p.stop()
	p.stream = st
	amp[nxt] = 0.0 if xfade > 0.0 else 1.0
	p.volume_db = linear_to_db(maxf(amp[nxt], 0.0001))
	p.play()
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
		players[i].volume_db = linear_to_db(maxf(to, 0.0001))
		if to <= 0.0:
			players[i].stop()


func _step_fades(dt: float) -> void:
	for i in range(2):
		var f: Array = fades[i]
		if float(f[3]) <= 0.0:
			continue
		f[2] = float(f[2]) + dt
		var x := clampf(float(f[2]) / float(f[3]), 0.0, 1.0)
		var e := sin(x * PI * 0.5) if float(f[1]) > float(f[0]) else 1.0 - cos(x * PI * 0.5)   # equal power
		amp[i] = lerpf(float(f[0]), float(f[1]), e)
		players[i].volume_db = linear_to_db(maxf(amp[i], 0.0001))
		if x >= 1.0:
			f[3] = 0.0
			if float(f[1]) <= 0.0:
				players[i].stop()


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
