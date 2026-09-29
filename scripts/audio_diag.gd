class_name AudioDiag
extends RefCounted
## AUDIO DIAG (branch audio-diag, 2026-09-29): on Daniele's Android phone the sound effects are silent while the music
## (web/music.js, its own AudioContext) plays; desktop Chrome and its phone emulation play them. This collects data from
## the phone, changing nothing about how effects play:
## - SETTINGS > DISPLAY > AUDIO > TEST SOUND (and PAUSE > SETTINGS' TEST SOUND): (A) the capture chime through Sfx exactly
##   as the game plays a menu sound (Sfx.play_ui -> the Sfx bus), then, Rules.AUDIO_DIAG "gap_s" apart, (B) a raw
##   beep made in JavaScript on Godot's own AudioContext (past Godot's buses) and (C) a raw beep on a fresh AudioContext
##   made inside the tap (web/audio-diag.js runTest). Which of the three he hears tells where the sound stops.
## - the AUDIO readout under it (web only): Godot's context state / rate / latencies / clock, contexts made, the sample
##   starts JS saw, SOUND and VOLUME, the Sfx and Master buses, the effect samples registered, effects played, the
##   playback type, the last JS audio error, the last TEST's outcome.
## - the same numbers once per session in the telemetry (Telemetry.tick, Rules.AUDIO_DIAG "telemetry_after_s") and once
##   after the first TEST, as a "perf" event with where = "audio_diag" (the telemetry function keeps perf's "extra"
##   object, so no server change), only when the player shares play data (Telemetry.event checks).

static var tests := 0
static var _sent_test := false


static func web() -> bool:
	return OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")


static func js_state() -> Dictionary:
	## web/audio-diag.js's capture ({} off the web or when the file is missing).
	if not web():
		return {}
	var s := str(JavaScriptBridge.eval("window.OozeAudioDiag?JSON.stringify(OozeAudioDiag.state()):''", true))
	if s == "" or s == "null":
		return {}
	var d = JSON.parse_string(s)
	return d if d is Dictionary else {}


static func data() -> Dictionary:
	## The readout's numbers (flat, <= 24 keys, [a-z0-9_] - the telemetry function's rules).
	var j := js_state()
	var t: Dictionary = j.get("test", {}) if j.get("test", {}) is Dictionary else {}
	var sfx := AudioServer.get_bus_index(Rules.SOUND_SFX_BUS)
	var loaded := 0
	var samples := 0
	for f in Sfx._streams:
		var st = Sfx._streams[f]
		if st is AudioStream:
			loaded += 1
			if AudioServer.is_stream_registered_as_sample(st):
				samples += 1
	var played := 0
	for k in Sfx.played:
		played += int(Sfx.played[k])
	var ptype := int(ProjectSettings.get_setting_with_override("audio/general/default_playback_type"))
	return {
		"js": not j.is_empty(), "ctx_state": str(j.get("state", "none")), "ctx_rate": int(j.get("rate", 0)),
		"ctx_base_ms": int(j.get("base_ms", -1)), "ctx_out_ms": int(j.get("out_ms", -1)),
		"ctx_time": float(j.get("time", -1.0)), "ctx_count": int(j.get("n", 0)), "ctx_history": str(j.get("history", "")),
		"music_ctx": str(j.get("music", "none")), "starts": int(j.get("starts", 0)),
		"starts_godot": int(j.get("starts_godot", 0)), "sfx_on": Sfx.sound_on(), "sfx_vol": Sfx.volume(),
		"sfx_mute": AudioServer.is_bus_mute(sfx) if sfx >= 0 else true,
		"sfx_db": snappedf(AudioServer.get_bus_volume_db(sfx), 0.1) if sfx >= 0 else -99.0,
		"master_mute": AudioServer.is_bus_mute(0), "master_db": snappedf(AudioServer.get_bus_volume_db(0), 0.1),
		"samples": samples, "streams": loaded, "played": played, "playback": "sample" if ptype == 1 else "stream",
		"test": "%s|%s|%s" % [str(t.get("godot", "")), str(t.get("fresh_made", "")), str(t.get("fresh", ""))] if tests > 0 else "",
		"js_err": str(j.get("err", "")).substr(0, 80),
	}


static func meas() -> String:
	## 0.23.3: the last TEST's effect-chain measurement (web/audio-diag.js D.arm): data / src / out peaks and the path's gains.
	if not web() or tests == 0:
		return ""
	var j := js_state()
	return str((j.get("test", {}) as Dictionary).get("meas", "")).substr(0, 420) if j.get("test") is Dictionary else ""


static func readout() -> String:
	## The AUDIO line under TEST SOUND (web only: "" elsewhere).
	if not web():
		return ""
	var d := data()
	if not bool(d["js"]):
		return "AUDIO: no page capture (audio-diag.js not loaded)."
	var lines := [
		"AUDIO  GAME CONTEXT %s  ·  %d Hz  ·  latency %d / %d ms  ·  clock %.1f s  ·  contexts %d (music %s)" % [
			str(d["ctx_state"]).to_upper(), int(d["ctx_rate"]), int(d["ctx_base_ms"]), int(d["ctx_out_ms"]),
			float(d["ctx_time"]), int(d["ctx_count"]), str(d["music_ctx"])],
		"SOUND %s %d %%  ·  Sfx bus %s %.1f dB  ·  Master %s %.1f dB  ·  samples %d / %d  ·  played %d  ·  starts %d (game %d)  ·  %s" % [
			"ON" if bool(d["sfx_on"]) else "OFF", int(d["sfx_vol"]), "MUTED" if bool(d["sfx_mute"]) else "on",
			float(d["sfx_db"]), "MUTED" if bool(d["master_mute"]) else "on", float(d["master_db"]), int(d["samples"]),
			int(d["streams"]), int(d["played"]), int(d["starts"]), int(d["starts_godot"]), str(d["playback"])],
		"EFFECT 1 %s" % (meas() if meas() != "" else "- (tap TEST)"),
		"states %s  ·  last test %s  ·  error %s" % [str(d["ctx_history"]) if str(d["ctx_history"]) != "" else "-",
			_test_words(str(d["test"])), str(d["js_err"]) if str(d["js_err"]) != "" else "none"],
	]
	return "\n".join(lines)


static func _test_words(t: String) -> String:
	## "godot|fresh_made|fresh" -> "2: started running, 3: made suspended, started suspended" ("-" before a TEST).
	var p := t.split("|")
	if t == "" or p.size() < 3:
		return "-"
	return "2: %s, 3: made %s, %s" % [p[0] if p[0] != "" else "?", p[1] if p[1] != "" else "?", p[2] if p[2] != "" else "?"]


static func run_test(on_done := Callable()) -> void:
	## TEST SOUND: A now (Sfx, forced past the UI gap - the button's own tap just played), B and C from JavaScript;
	## `on_done` (the readout refresh) once the three are over. The first TEST also sends the readout (telemetry).
	tests += 1
	if web():                                        # 0.23.3: tap the game effect's chain while it plays (web/audio-diag.js D.arm)
		JavaScriptBridge.eval("window.OozeAudioDiag&&OozeAudioDiag.arm()", true)
	Sfx.play_ui("test", true)
	var A := Rules.AUDIO_DIAG
	if web():
		JavaScriptBridge.eval("window.OozeAudioDiag&&OozeAudioDiag.runTest(%d,%d,%f,%f)" % [
				int(float(A["gap_s"]) * 1000.0), int(float(A["beep_s"]) * 1000.0), float(A["beep_hz"]),
				float(A["beep_gain"])], true)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.create_timer(float(A["gap_s"]) * 2.0 + float(A["beep_s"]) + 0.5).timeout.connect(func():
		if not _sent_test:
			_sent_test = send("test")
		if on_done.is_valid():
			on_done.call())


static func send(trigger: String) -> bool:
	## The readout as telemetry (web only; Telemetry.event drops it unless the player shares play data).
	if not web():
		return false
	var d := data()
	d["trigger"] = trigger
	if tests > 0:                                   # 0.23.3: the measurement in place of the state history (24 keys max)
		d.erase("ctx_history")
		d["meas"] = meas()
	return Telemetry.event("perf", {"where": "audio_diag", "time_s": snappedf(Time.get_ticks_msec() / 1000.0, 1.0), "extra": d})
