class_name Sfx
extends Node
## SOUND, first pass: Set 4 "Mix 2+3", alternate 1 - the set Daniele picked in the sound demo (branch sound-demo,
## 2026-09-28: "2 and 3 are my fav so far"). Files: assets/audio/sfx/<pack>/ (CC0, CREDITS.txt there).
## main.gd calls Sfx.attach(self) once at the top of _ready, right after PerfProfile.apply (one marked line); the
## room server and headless runs build nothing. The node then plays the LOCAL VIEW's match:
## - the view's one-off events: main's sim.fx_events loop hands each one to Sfx.on_fx (a second marked line). Online
##   guests get the host's fx events through Net into that same list, so they hear the same match;
## - what fx_events does not carry (a send, a fight starting, a line wiped out, the win) from the board itself, each
##   frame, the way the views read it: new lines, lines entering a fight or pouring into a hostile node, lines gone,
##   machinegoon shot stamps, sim.over. A guest's board is the host's snapshots, so this works online too.
## Each event type is throttled (Rules.SOUND_GAP) and shares a pool of Rules.SOUND_VOICES players; with every voice
## busy a new sound is dropped, except the alarms / knock-out / win / collapse (Rules.SOUND_PRIORITY), which take
## the oldest ordinary voice. No positional audio: every sound is centred (the pan was optional in the brief).
## Menus: Sfx.play_ui("tap" | "confirm" | "back" | "error") - UiKit's shared button factory calls it.
## SETTINGS > DISPLAY > AUDIO (and PAUSE > SETTINGS): SOUND ON / OFF (Daniele 2026-09-28: "don't forget a sound
## on/off in the options"; OFF = silent, menus and matches alike) and VOLUME (Rules.SOUND_VOLUME_STEPS, %), saved in
## user://settings.cfg [audio] and applied to the Sfx bus at once (MUSIC / MUSIC VOLUME drive the Music bus the same way,
## music.gd, so the two are independent; Master stays 0 dB; Web's sample playback mirrors every bus's volume and mute).
## Web: browsers start audio on the first tap - Godot's web audio resumes its
## context on the first input event, so nothing plays before it and nothing needs unlocking here.
## Match feel (Daniele's phone test, 2026-09-28: "obnoxious (but a good starting point)"): the frequent battle noise
## (Rules.SOUND_BED: sends, fights, hits, machinegoon, laser, falls) is a soft bed - long throttles, quieter, a small
## pitch spread, only for your side's lines or ones on screen, held off for Rules.SOUND_DUCK s after a cue
## (Rules.SOUND_CUES: capture, node lost, Last Stand, knock-out, win, collapse), which stay clear. First run: 30 %.
## Web: every stream is registered as a WebAudio sample when the match node is made (no decode on its first play).
## Envelope (Daniele, with music: "less loud and that they fade more seamlessly"): each match sound fades in and its
## tail fades out (Rules.SOUND_FADE_IN / SOUND_FADE_OUT, a volume tween per voice), a repeat of an event still sounding
## crossfades (the old voice fades out over Rules.SOUND_XFADE, the new one starts on a free voice), and the priority
## sounds get spare voices (Rules.SOUND_PRIORITY_VOICES) so they seldom cut anything off. Every sound plays on the
## "Sfx" bus; the soundtrack plays on the "Music" bus beside it, both under Master (ensure_buses). Playing one of
## Rules.MUSIC_DUCK_EVENTS dips the music under it (Music.duck).
## Debug: --sfx-log (after `--`) prints every sound played.

const ROOT := "res://assets/audio/sfx/"
# event -> "<pack>/<file>" (Set 4 alt 1, the demo's table in README-DEMO.md)
const FILES := {
	"send": "slime/slime_05", "fight": "slime/slime_14", "hit": "impact/impactGeneric_light_000",
	"capture": "digital/powerUp5", "node_lost": "digital/phaserDown2", "rival_capture": "digital/powerUp5",
	"upgrade": "digital/powerUp2",
	"build": "digital/highUp", "laser": "scifi60/sfx_07a", "machinegoon": "scifi60/sfx_09a",
	"monster_launch": "slime/slime_03", "monster_stomp": "impact/impactPunch_heavy_002",
	"monster_take": "slime/slime_08", "monster_fall": "slime/splash_14", "skill": "digital/phaseJump2",
	"relay_warning": "digital/tone1", "relay_switch": "digital/twoTone1", "fall": "slime/splash_15",
	"collapse_warning": "scifi60/sfx_02a", "collapse": "impact/impactPlate_heavy_000",
	"last_stand": "digital/lowThreeTone", "very_last_stand": "digital/zapThreeToneDown",
	"eliminated": "digital/highDown", "win": "digital/powerUp1",
}
# The demo had no menu sounds: these reuse the set's own files (no new pack) - a soft click, the build's rising
# blip, the knock-out's falling one, the node-lost buzz. (An open question for Daniele: dedicated UI sounds.)
const UI_FILES := {"tap": "impact/impactGeneric_light_000", "confirm": "digital/highUp", "back": "digital/highDown",
		"error": "digital/phaserDown2", "test": "digital/powerUp5"}   # "test": AUDIO DIAG's TEST SOUND (the capture chime)
const HIT_MARGIN := 1.0                  # m: a line gone this far short of its node's door was wiped out, not landed

static var path := "user://settings.cfg"   # tests point this elsewhere
static var _volume := -1                  # VOLUME, % (-1 until read)
static var _on := true                    # SOUND ON / OFF
static var _streams := {}                 # "<pack>/<file>" -> AudioStream, loaded once per run
static var _live: Sfx = null
static var _ui_voices: Array = []         # AudioStreamPlayers under the tree root (they survive a scene reload)
static var _ui_last := 0
static var played := {}                   # event -> plays this run (debug / tests/sound_check.gd)

var main: Node
var sim: Sim = null
var log_on := "--sfx-log" in OS.get_cmdline_user_args()
var voices: Array[AudioStreamPlayer] = []
var voice_info: Array = []                # per voice [started msec, event, fading out]
var envelopes: Array = []                 # per voice its volume Tween (null when none runs)
var last_play := {}                       # event -> msec
var pending: Array = []                   # this frame's fx events (main's loop, before it clears the list)
var lines := {}                           # horde id -> [state, s, L, hostile target]: the board last frame
var owners := {}                          # node id -> owner last frame (a capture from someone = node_lost)
var builds := {}                          # node id -> [structure, tier] last frame (a build_done = upgrade or build)
var shot_t := {}                          # machinegoon node id -> its last shot stamp
var was_over := false
var duck_until := 0                       # msec: the bed stays quiet until then (a cue just played)
var human := "A"                          # the viewer's seat (main.HUMAN, read each frame)


# ------------------------------------------------------------------ the settings (user://settings.cfg [audio])
static func _load() -> void:
	if _volume >= 0:
		return
	_volume = Rules.SOUND_VOLUME_DEFAULT
	_on = true
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		_volume = clampi(int(cf.get_value("audio", "volume", _volume)), 1, 100)
		# 0.23.1 (Daniele: "sound effects still not working"): a new key, so SOUND starts ON again on every device - in 0.22.1
		# SOUND OFF was the only switch that seemed to "mute" the lagging music, and that choice stayed saved since.
		_on = bool(cf.get_value("audio", "on_v2", true))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(path)                                      # keep the other sections ([graphics], ...)
	cf.set_value("audio", "volume", _volume)
	cf.set_value("audio", "on_v2", _on)
	cf.save(path)


static func volume() -> int:
	_load()
	return _volume


static func sound_on() -> bool:
	_load()
	return _on


static func set_volume(pct: int) -> void:
	## SETTINGS > VOLUME: saved and heard at once (the Sfx bus).
	_load()
	_volume = clampi(pct, 1, 100)
	_save()
	apply_settings()


static func set_on(on: bool) -> void:
	## SETTINGS > SOUND ON / OFF: OFF mutes the Sfx bus (menus and matches; the music has its own MUSIC switch), keeping the
	## VOLUME for ON.
	_load()
	_on = on
	_save()
	apply_settings()


static func next_volume() -> int:
	## The step after the current one, round (a one-tap cycling control, e.g. the pause menu's SETTINGS).
	var steps: Array = Rules.SOUND_VOLUME_STEPS
	var i := steps.find(volume())
	return int(steps[(i + 1) % steps.size()])


static func volume_label(pct := -1) -> String:
	return "%d %%" % (volume() if pct < 0 else pct)


static func bus_db() -> float:
	## What the VOLUME setting puts on the Sfx bus (over Rules.SOUND_SFX_BUS_DB).
	return linear_to_db(volume() / 100.0)


static func apply_settings() -> void:
	_load()
	ensure_buses()
	var i := AudioServer.get_bus_index(Rules.SOUND_SFX_BUS)
	AudioServer.set_bus_volume_db(i, Rules.SOUND_SFX_BUS_DB + bus_db())
	AudioServer.set_bus_mute(i, not _on)


static func ensure_buses() -> void:
	## The "Sfx" bus every sound plays on and the "Music" bus the soundtrack plays on (music.gd), both sending to Master.
	for spec in [[Rules.SOUND_SFX_BUS, Rules.SOUND_SFX_BUS_DB], [Rules.SOUND_MUSIC_BUS, Rules.SOUND_MUSIC_BUS_DB]]:
		if AudioServer.get_bus_index(str(spec[0])) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, str(spec[0]))
		AudioServer.set_bus_send(i, "Master")
		AudioServer.set_bus_volume_db(i, float(spec[1]))


static func _can_play(n: Node) -> bool:
	## Never on the room server (Net.dedicated: nobody hears it) nor a headless run (tests, exports).
	if DisplayServer.get_name() == "headless":
		return false
	var net: Node = null
	if n != null and n.is_inside_tree():
		net = n.get_node_or_null("/root/Net")          # (by path: the --script tests have no autoloads)
	return net == null or not bool(net.get("dedicated"))


static func _stream(f: String) -> AudioStream:
	if not _streams.has(f):
		var p := ROOT + f + ".ogg"
		_streams[f] = load(p) if ResourceLoader.exists(p) else null
		if _streams[f] == null:
			push_warning("Sfx: missing " + p)
	return _streams[f]


# ------------------------------------------------------------------ the match node
static func attach(m: Node) -> void:
	## main.gd, top of _ready, after PerfProfile.apply (one marked line).
	if not _can_play(m):
		return
	apply_settings()
	var node := Sfx.new()
	node.name = "Sfx"
	node.main = m
	m.add_child(node)
	_live = node


static func on_fx(ev: Dictionary) -> void:
	## main.gd's sim.fx_events loop (one marked line): kept until this frame's _process (main clears the list first).
	if _live != null and is_instance_valid(_live):
		_live.pending.append(ev)


func _ready() -> void:
	for i in range(Rules.SOUND_VOICES + Rules.SOUND_PRIORITY_VOICES):   # the last ones: the priority sounds' spares
		var p := AudioStreamPlayer.new()
		p.bus = Rules.SOUND_SFX_BUS
		add_child(p)
		voices.append(p)
		voice_info.append([0, "", false])
		envelopes.append(null)
	for ev in FILES:                                   # load the set now, not on the first fight
		var st := _stream(FILES[ev])
		if st != null and OS.has_feature("web"):       # match feel: into WebAudio now, not on its first play
			AudioServer.register_stream_as_sample(st)


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _process(_delta: float) -> void:
	if main == null or not bool(main.get("started")):
		pending.clear()
		return
	var s: Sim = main.get("sim")
	if s == null:
		return
	if not _on:                                        # SOUND OFF: no board tracking at all (code audit); it is
		pending.clear()                                # learned afresh, silently, when the sound comes back on
		sim = null
		return
	if s != sim:                                       # a new match (or a rebuilt Sim): learn the board silently
		sim = s
		pending.clear()
		_remember()
		was_over = sim.over
		return
	human = str(main.get("HUMAN"))
	var taken := {}                                    # nodes a monster took this frame (its own sound says it)
	var gone := {}                                     # lines recalled / ghosts ended: not wiped out
	var fell := false
	for ev in pending:
		match str(ev.get("type", "")):
			"monster_take":
				taken[int(ev.get("node", -1))] = true
			"recall", "ghost_end":
				gone[int(ev.get("hid", -1))] = true
			"fall", "fling":
				fell = true
	for ev in pending:
		if ev.has("private") and str(ev["private"]) != human:
			continue                                   # another seat's secret (Ghost Line): not ours to hear
		match str(ev.get("type", "")):
			"capture":
				# by side (code audit A3): you / an ally took it = capture, you / an ally lost it = node lost, the
				# rivals among themselves (or off a neutral) = a quiet generic cue, only when on screen
				var id := int(ev["node"])
				if taken.has(id):
					continue
				var was := str(owners.get(id, ""))
				if sim.allied(str(ev.get("seat", "")), human):
					_play("capture")
				elif was != "" and sim.allied(was, human):
					_play("node_lost")
				else:
					_play("rival_capture", _near(false, sim.nodes[id]["pos"]))
			"build_done":
				var id := int(ev["node"])
				var n: Dictionary = sim.nodes[id]
				var b: Array = builds.get(id, ["", 0])
				_play("upgrade" if str(b[0]) == str(n.get("structure", "")) and int(n.get("tier", 0)) > int(b[1]) else "build")
			"cannon":
				_play("laser")
			"monster_launch", "monster_take", "monster_fall", "skill", "relay_warning", "fall", "collapse_warning", \
					"collapse", "last_stand", "very_last_stand", "eliminated":
				_play(str(ev["type"]))
			"monster_kick":
				_play("monster_stomp")
			"relay_tick":
				_play("relay_switch")
	pending.clear()
	# the board: lines sent, fights starting (a clash on a deck, or pouring into a hostile node at its door), lines
	# wiped out (gone short of their door while fighting or marching - a landing pours in at the door first)
	var now := {}
	for h in sim.hordes:
		var id := int(h["id"])
		var tn: Dictionary = sim.nodes[int(h["target"])] if int(h.get("target", -1)) >= 0 else {}
		var hostile: bool = str(h.get("state", "")) == "absorb" and float(h.get("units", 0.0)) > 0.0 \
				and not tn.is_empty() and not sim.collapsed.get(tn["id"], false) and not sim.allied(str(tn["owner"]), str(h["owner"]))
		var st := str(h.get("state", ""))
		var was: Array = lines.get(id, [])
		var mine: bool = sim.allied(str(h["owner"]), human) or (not tn.is_empty() and sim.allied(str(tn["owner"]), human))
		var at: Vector3 = Sim.sample(h, float(h.get("s", 0.0)))[0] if h.has("pts") and (h["pts"] as PackedVector3Array).size() > 1 else Vector3.INF
		var near := _near(mine, at)
		if was.is_empty():
			_play("send", near)
		elif (st == "fight" and str(was[0]) != "fight") or (hostile and not bool(was[3])):
			_play("fight", near)
		now[id] = [st, float(h.get("s", 0.0)), float(h.get("L", 0.0)), hostile, near]
	for id in lines:
		if now.has(id) or gone.has(id):
			continue
		var was: Array = lines[id]
		if str(was[0]) == "fight" or (str(was[0]) == "move" and float(was[1]) < float(was[2]) - HIT_MARGIN and not fell):
			_play("hit", was.size() < 5 or bool(was[4]))
	lines = now
	for n in sim.nodes:                                # machinegoon streams: a new shot stamp every firing frame
		if str(n.get("structure", "")) == "machinegoon":
			var shot: Dictionary = n.get("shot", {})
			if not shot.is_empty():
				var t := float(shot.get("t", -1.0))
				if t != float(shot_t.get(n["id"], -1.0)):
					shot_t[n["id"]] = t
					_play("machinegoon", _near(sim.allied(str(n["owner"]), human), n["pos"]))
	_remember_nodes()
	if sim.over and not was_over:                      # the win jingle for your side (every side in an all-AI demo)
		var w := str(sim.winner)
		if w != "" and (bool(main.get("demo")) or w == human or sim.allied(w, human)):
			_play("win")
	was_over = sim.over


func _remember() -> void:
	lines = {}
	for h in sim.hordes:
		lines[int(h["id"])] = [str(h.get("state", "")), float(h.get("s", 0.0)), float(h.get("L", 0.0)), false]
	shot_t = {}
	for n in sim.nodes:
		shot_t[n["id"]] = float((n.get("shot", {}) as Dictionary).get("t", -1.0))
	_remember_nodes()


func _remember_nodes() -> void:
	for n in sim.nodes:
		owners[n["id"]] = str(n.get("owner", ""))
		builds[n["id"]] = [str(n.get("structure", "")), int(n.get("tier", 0))]


func _near(mine: bool, at: Vector3) -> bool:
	## A bed sound is heard for your side's lines (and lines at your nodes) or ones on screen (the Last Stand's zoom
	## leaves part of the map out).
	if mine:
		return true
	var cam: Camera3D = main.get("cam") if main != null else null
	return at == Vector3.INF or cam == null or cam.is_position_in_frustum(at)


# ------------------------------------------------------------------ playback
func _play(event: String, heard := true) -> void:
	var now_ms := Time.get_ticks_msec()
	var bed: bool = event in Rules.SOUND_BED
	if bed and (not heard or now_ms < duck_until):
		return                                         # not your side's and off screen, or a cue is speaking
	var gap := float(Rules.SOUND_GAP.get(event, Rules.SOUND_GAP_DEFAULT))
	if now_ms - int(last_play.get(event, -100000)) < int(gap * 1000.0):
		return
	var st := _stream(str(FILES.get(event, "")))
	if st == null:
		return
	var prio: bool = event in Rules.SOUND_PRIORITY
	var vi := -1
	var usable := voices.size() if prio else Rules.SOUND_VOICES
	for i in range(usable):
		if not voices[i].playing:
			vi = i
			break
	if vi < 0:
		if not prio:
			return                                     # every voice busy: drop it (a busy map stays readable)
		var oldest := now_ms + 1
		for i in range(voices.size()):
			if int(voice_info[i][0]) < oldest and not str(voice_info[i][1]) in Rules.SOUND_PRIORITY:
				oldest = int(voice_info[i][0])
				vi = i
		if vi < 0:
			return
	for i in range(voices.size()):                     # the same event still sounding: it fades out under the new one
		if i != vi and voices[i].playing and str(voice_info[i][1]) == event and not bool(voice_info[i][2]):
			_fade_out(i, Rules.SOUND_XFADE)
	last_play[event] = now_ms
	var p := voices[vi]
	if envelopes[vi] != null:
		(envelopes[vi] as Tween).kill()
	p.stop()
	p.stream = st
	var level := float(Rules.SOUND_VOL.get(event, -6.0))
	p.pitch_scale = (1.0 + randf_range(-Rules.SOUND_BED_PITCH, Rules.SOUND_BED_PITCH)) if bed else 1.0
	if event in Rules.SOUND_CUES:
		duck_until = now_ms + int(Rules.SOUND_DUCK * 1000.0)
	p.volume_db = level - Rules.SOUND_ATTACK_DB
	p.play()
	voice_info[vi] = [now_ms, event, false]
	# the envelope: in over SOUND_FADE_IN, hold, the tail's last SOUND_FADE_OUT down by SOUND_TAIL_DB (the sample ends)
	var length := st.get_length() / maxf(p.pitch_scale, 0.01)
	var tail := minf(Rules.SOUND_FADE_OUT, length * 0.5) if length > 0.0 else 0.0
	var tw := create_tween()
	tw.tween_property(p, "volume_db", level, Rules.SOUND_FADE_IN)
	if tail > 0.0:
		tw.tween_interval(maxf(length - tail - Rules.SOUND_FADE_IN, 0.0))
		tw.tween_property(p, "volume_db", level - Rules.SOUND_TAIL_DB, tail).set_ease(Tween.EASE_IN)
	envelopes[vi] = tw
	played[event] = int(played.get(event, 0)) + 1
	if event in Rules.MUSIC_DUCK_EVENTS:
		Music.duck()                                   # MUSIC: the soundtrack dips under the big cues
	if log_on:
		print("SFX t=%.1f %s -> %s.ogg" % [sim.time if sim else 0.0, event, FILES[event]])


func _fade_out(i: int, seconds: float) -> void:
	## Voice i fades SOUND_TAIL_DB down over `seconds`, then stops (a crossfade under a repeat of its event).
	if envelopes[i] != null:
		(envelopes[i] as Tween).kill()
	voice_info[i][2] = true
	var p := voices[i]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", p.volume_db - Rules.SOUND_TAIL_DB, seconds).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.stop)
	envelopes[i] = tw


static func play_ui(kind: String, force := false) -> void:
	## A menu sound ("tap" | "confirm" | "back" | "error"); UiKit's buttons call it. Its players live under the tree
	## root, so a button that reloads the scene (DEPLOY, PLAY AGAIN) still finishes its sound.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not _can_play(tree.root):
		return
	var now_ms := Time.get_ticks_msec()
	if not force and now_ms - _ui_last < int(Rules.SOUND_UI_GAP * 1000.0):   # force: AUDIO DIAG's TEST (right after its tap)
		return
	var st := _stream(str(UI_FILES.get(kind, "")))
	if st == null:
		return
	if _ui_voices.is_empty() or not is_instance_valid(_ui_voices[0]):
		_ui_voices = []
		apply_settings()                               # the first sound of the run: the saved level first
		for i in range(Rules.SOUND_UI_VOICES):
			var p := AudioStreamPlayer.new()
			p.name = "SfxUi%d" % i
			p.bus = Rules.SOUND_SFX_BUS
			tree.root.add_child(p)
			_ui_voices.append(p)
	var pick: AudioStreamPlayer = _ui_voices[0]
	for p in _ui_voices:
		if not (p as AudioStreamPlayer).playing:
			pick = p
			break
	_ui_last = now_ms
	pick.stop()
	pick.stream = st
	pick.volume_db = float(Rules.SOUND_UI_VOL.get(kind, -10.0))
	pick.play()
	played["ui_" + kind] = int(played.get("ui_" + kind, 0)) + 1
