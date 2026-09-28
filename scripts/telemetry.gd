class_name Telemetry
extends RefCounted
## Two jobs:
## 1. The per-match log on the device (GAME-RULES §13): duration, sends, captures, frontlines, units lost to combat vs
##    falls, deciding event, winner-was-behind flag, as JSON in user://telemetry/ (the last Rules.TELEMETRY
##    "match_logs_kept" files are kept).
## 2. PROGRESSION (Alpha 21, 01 Rules/TELEMETRY-PRIVACY-DESIGN.md): the play / performance / crash events the player
##    may share. One switch (SHARE PLAY & CRASH DATA); nothing is uploaded before the privacy notice has been answered
##    or while the switch is OFF (then the queue is dropped). Consent (Daniele, 2026-09-28): opt-in in the EU / UK,
##    opt-out elsewhere (Rules.TELEMETRY "consent"). Events carry numbers, ids and enums only - no names, room codes,
##    typed text or input streams - and go to the `telemetry` edge function with the player's own account session.

# ------------------------------------------------------------------ 1. the per-match log
static func save(sim: Sim, map_code: String, strength_trace: Array) -> String:
	var sends := {}
	var captures := 0
	var last_capture := {}
	for e in sim.events:
		if e["type"] == "send":
			sends[e["seat"]] = sends.get(e["seat"], 0) + 1
		elif e["type"] == "capture":
			captures += 1
			last_capture = e
	var behind := false
	for sample in strength_trace:                   # was the winner ever clearly behind?
		if sim.winner != "" and sample.has(sim.winner):
			for seat in sample.keys():
				if seat != sim.winner and seat != "t" and sample[seat] > sample[sim.winner] * 1.25:
					behind = true
	var record := {
		"map": map_code, "duration_s": snappedf(sim.time, 0.1), "winner": sim.winner,
		"winner_was_behind": behind, "sends": sends, "captures": captures,
		"deciding_event": last_capture, "units_lost_combat": sim.combat_losses,
		"units_lost_falls": sim.fall_losses, "last_stand_reached": sim.last_stand_active,
		"events": sim.events,
	}
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var path := "user://telemetry/match_%d.json" % Time.get_unix_time_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:                                   # user:// not writable (private browser storage, read-only profile)
		return ""
	f.store_string(JSON.stringify(record, "  "))
	f.close()
	prune_logs("user://telemetry", int(Rules.TELEMETRY["match_logs_kept"]))
	return ProjectSettings.globalize_path(path)


static func prune_logs(dir: String, keep: int) -> int:
	## Keeps the newest `keep` match_*.json files (OPEN-QUESTIONS 2026-09-26 item 8: uncapped before Alpha 21).
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("match_") and f.ends_with(".json"):
			files.append(f)
	files.sort_custom(func(a: String, b: String) -> bool:     # match_<unix>.json: by the number, newest last
		return int(a.trim_prefix("match_").trim_suffix(".json")) < int(b.trim_prefix("match_").trim_suffix(".json")))
	var removed := 0
	while files.size() > keep:
		DirAccess.remove_absolute(dir.path_join(files.pop_front()))
		removed += 1
	return removed


# ------------------------------------------------------------------ 2. consent
const KINDS := ["session", "match", "perf", "funnel", "crash"]
# EU + EEA + UK (+ Switzerland, its own law of the same kind): the region codes a locale may carry
const EU_REGIONS := ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
		"LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "GB", "UK", "GI", "CH",
		"AX", "GF", "GP", "MQ", "RE", "YT", "MF"]
const EU_ZONES := ["Atlantic/Canary", "Atlantic/Madeira", "Atlantic/Azores", "Atlantic/Reykjavik", "Atlantic/Faroe",
		"Arctic/Longyearbyen", "America/Cayenne", "America/Guadeloupe", "America/Martinique", "Indian/Reunion",
		"Indian/Mayotte", "GB", "Eire", "Iceland", "Poland", "Portugal"]

static var path := "user://privacy.cfg"            # the choice; tests point this elsewhere
static var queue_path := "user://telemetry_queue.json"
static var enabled := true                          # false: never queue or send (tests, headless, the match host)
static var force_region := ""                       # "eu" / "other": tests and --region= (screenshots)
static var _loaded := false
static var _seen := false                           # the privacy notice has been answered
static var _share := false
static var _eu_cache := -1                          # -1 unknown, 0 / 1


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	_seen = bool(cf.get_value("privacy", "seen", false))
	_share = bool(cf.get_value("privacy", "share", false))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(path)                                   # keep other keys (funnel "once" flags)
	cf.set_value("privacy", "seen", _seen)
	cf.set_value("privacy", "share", _share)
	cf.set_value("privacy", "region", "eu" if eu() else "other")
	cf.set_value("privacy", "at", int(Time.get_unix_time_from_system()))
	cf.save(path)


static func forget_all() -> void:
	## Tests: forget the cached choice and queue, read them again from `path` / `queue_path` (not "reload" / "reset_state": those are
	## the script resource's own reload() / reset_state(), which a static call on the class reaches first).
	_loaded = false
	_seen = false
	_share = false
	_eu_cache = -1
	_queue = []
	_queue_loaded = false
	_crash_sigs = {}
	_load()


static func notice_due() -> bool:
	_load()
	return enabled and not _seen


static func opt_in() -> bool:
	## True when this player must turn the switch ON themselves (the notice asks; the switch starts OFF).
	return str(Rules.TELEMETRY["consent"]) == "opt_in_eu_uk" and eu()


static func default_share() -> bool:
	return not opt_in()


static func sharing() -> bool:
	_load()
	return _seen and _share


static func choose(share: bool) -> void:
	## The notice's answer, or the switch in OPTIONS / ACCOUNT. OFF drops everything queued.
	_load()
	_seen = true
	_share = share
	_save()
	if not share:
		drop_queue()


static func eu() -> bool:
	if force_region != "":
		return force_region == "eu"
	if _eu_cache < 0:
		var r := region_info()
		_eu_cache = 1 if is_eu(str(r["tz"]), str(r["locale"])) else 0
	return _eu_cache == 1


static func region_info() -> Dictionary:
	## The device's time zone name and locale ("Europe/Rome", "it-IT"); both read locally, neither is ever sent.
	var tz := ""
	var loc := OS.get_locale()
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		tz = str(JavaScriptBridge.eval("(()=>{try{return Intl.DateTimeFormat().resolvedOptions().timeZone||''}catch(e){return ''}})()", true))
		var nl := str(JavaScriptBridge.eval("navigator.language||''", true))
		if nl != "" and nl != "null":
			loc = nl
	else:
		tz = str(Time.get_time_zone_from_system().get("name", ""))
	return {"tz": "" if tz == "null" else tz, "locale": loc}


static func is_eu(tz: String, locale: String) -> bool:
	## EU / EEA / UK by the IANA time zone first (where the device is), then the locale's region; unsure = EU.
	if tz.begins_with("Europe/") or tz in EU_ZONES:
		return true
	var region := ""
	var parts := locale.replace("-", "_").split("_")
	for i in range(1, parts.size()):
		if parts[i].length() == 2:
			region = parts[i].to_upper()
	if region in EU_REGIONS:
		return true
	if tz.contains("/") or tz == "UTC":             # a real zone outside Europe (UTC alone says nothing: use the region)
		return tz == "UTC" and region == ""
	if tz.contains("Europe") or tz.begins_with("GMT Standard") or tz.begins_with("Greenwich") \
			or tz.begins_with("Romance") or tz.begins_with("FLE ") or tz.begins_with("GTB "):
		return true                                 # Windows zone names ("W. Europe Standard Time", "GMT Standard Time")
	return region == ""                             # no zone we can read: the locale's region decides; none = EU


# ------------------------------------------------------------------ the queue
static var _queue: Array = []
static var _queue_loaded := false
static var _flushing := false
static var _flush_t := 0.0
static var _flush_now := false


static func queue() -> Array:
	_queue_load()
	return _queue


static func _queue_load() -> void:
	if _queue_loaded:
		return
	_queue_loaded = true
	_queue = []
	if FileAccess.file_exists(queue_path):
		var js = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
		if js is Array:
			_queue = js


static func _queue_save() -> void:
	var f := FileAccess.open(queue_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))


static func drop_queue() -> void:
	_queue = []
	_queue_loaded = true
	if FileAccess.file_exists(queue_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(queue_path))


static func event(kind: String, data: Dictionary) -> bool:
	## Queues one event (numbers / ids / enums; strings are scrubbed). Kept before the notice is answered (dropped if
	## the answer is no), never while the switch is OFF. Returns whether it was queued.
	if not enabled or not kind in KINDS:
		return false
	_load()
	if _seen and not _share:
		return false
	var e := {"kind": kind, "t": int(Time.get_unix_time_from_system()), "data": clean(data)}
	if JSON.stringify(e).to_utf8_buffer().size() > int(Rules.TELEMETRY["event_bytes"]):
		return false
	_queue_load()
	_queue.append(e)
	while _queue.size() > int(Rules.TELEMETRY["queue_max"]):
		_queue.pop_front()
	_queue_save()
	return true


static func clean(v, depth := 0):
	## Numbers, bools, short scrubbed strings; nested at most two levels, at most 24 keys / 10 items.
	if v is String or v is StringName:
		return scrub(str(v), 500)
	if v is int or v is bool or v == null:
		return v
	if v is float:
		return snappedf(v, 0.01) if is_finite(v) else null
	if depth >= 2:
		return null
	if v is Array:
		var out := []
		for x in (v as Array).slice(0, 10):
			out.append(clean(x, depth + 1))
		return out
	if v is Dictionary:
		var out := {}
		for k in (v as Dictionary).keys().slice(0, 24):
			out[str(k)] = clean(v[k], depth + 1)
		return out
	return null


static func scrub(s: String, max_len := 500) -> String:
	## Before anything is sent: URL queries / fragments (a Google sign-in lands with tokens there), JWT-shaped strings,
	## keys, emails; then the length cap. The telemetry function scrubs again.
	var rx := [
		["(https?://[^\\s?#\"']+)[?#][^\\s\"']*", "$1"],
		["eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}", "<jwt>"],
		["\\b(sb_[a-z]+_[A-Za-z0-9_-]{8,}|[A-Za-z0-9_-]{32,})\\b", "<key>"],
		["[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<email>"],
	]
	for pair in rx:
		var re := RegEx.create_from_string(pair[0])
		s = re.sub(s, pair[1], true)
	return s.substr(0, max_len)


static func flush_soon() -> void:
	_flush_now = true


static func tick(acct: Account, dt: float) -> void:
	## From Account._process: drain captured errors, upload every Rules.TELEMETRY "flush_s" (or when asked).
	_drain_logger()
	_poll_web_crashes(dt)
	_flush_t += dt
	if _flush_now or _flush_t >= float(Rules.TELEMETRY["flush_s"]):
		_flush_t = 0.0
		_flush_now = false
		flush(acct)


static func flush(acct: Account) -> int:
	## Uploads up to one batch. Returns the number the server accepted (-1: nothing tried). Sent events leave the queue;
	## a 400 / 413 drops the batch (it will never pass), a 429 (today's cap is full) drops the queue, offline keeps it.
	if _flushing or not enabled or not sharing() or acct == null or not acct.signed_in():
		return -1
	_queue_load()
	if _queue.is_empty():
		return -1
	_flushing = true
	var batch: Array = _queue.slice(0, int(Rules.TELEMETRY["batch"]))
	var r: Dictionary = await acct._call("POST", "/functions/v1/telemetry", {"build": Rules.VERSION, "events": batch}, true)
	_flushing = false
	var code := int(r["code"])
	if code == 429:
		drop_queue()
		return 0
	if r["ok"] or code in [400, 413]:
		_queue_load()
		var n := 0
		while n < batch.size() and not _queue.is_empty() and _queue[0] == batch[n]:   # the queue may have changed meanwhile
			_queue.pop_front()
			n += 1
		_queue_save()
		return int((r["json"] as Dictionary).get("accepted", 0)) if r["ok"] and r["json"] is Dictionary else 0
	return 0


# ------------------------------------------------------------------ crash reports (§4)
static var _crash_sigs := {}
static var _logger: CrashLog = null
static var _installed := false
static var _web_t := 0.0


class CrashLog extends Logger:
	## Godot's own errors (engine and SCRIPT ERROR) on every platform, the web included. Called from any thread: only
	## collect here, Telemetry drains on the main thread.
	var mutex := Mutex.new()
	var pending: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var stack := ""
		if not script_backtraces.is_empty() and script_backtraces[0] != null:
			stack = script_backtraces[0].format()
		mutex.lock()
		if pending.size() < 20:
			pending.append({"where": "%s:%d %s" % [file.get_file(), line, function],
					"message": rationale if rationale != "" else code, "stack": stack,
					"kind": ["error", "warning", "script", "shader"][clampi(error_type, 0, 3)]})
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		mutex.lock()
		var out := pending
		pending = []
		mutex.unlock()
		return out


# the web build's browser-level hooks (JS errors, promise rejections, a lost WebGL context, WebAssembly aborts) and the
# "session running" flag: set while the page is visible, cleared when it is hidden or closed - a flag still set at the
# next launch means the page died while playing (an unclean exit). Defined at runtime, like the name field.
const CRASH_JS := """(()=>{if(window.OozeCrash)return;const K='ooze20-running',L='ooze20-crashlog';let q=[],prev=null;
try{if(localStorage.getItem(K)==='1')prev=localStorage.getItem(L)||'[]';localStorage.setItem(L,'[]')}catch(e){}
function mark(on){try{on?localStorage.setItem(K,'1'):localStorage.removeItem(K)}catch(e){}}
mark(document.visibilityState!=='hidden');document.addEventListener('visibilitychange',()=>mark(document.visibilityState!=='hidden'));
window.addEventListener('pagehide',()=>mark(false));
const cut=s=>s.replace(/(https?:[^ ?#"']+)[?#][^ "']*/g,'$1');
function add(where,msg,stack){msg=cut(String(msg||'')).slice(0,500);stack=cut(String(stack||'')).split('\\n').slice(0,10).join('\\n');if(q.length<20)q.push({where:where,message:msg,stack:stack});
try{const l=JSON.parse(localStorage.getItem(L)||'[]');l.push({where:where,message:msg});localStorage.setItem(L,JSON.stringify(l.slice(-5)))}catch(e){}}
window.addEventListener('error',e=>add('js_error',e.message||(e.error&&e.error.message),e.error&&e.error.stack));
window.addEventListener('unhandledrejection',e=>{const r=e.reason;add('js_rejection',(r&&r.message)||r,r&&r.stack)});
const c=document.getElementById('canvas');if(c)c.addEventListener('webglcontextlost',()=>add('webgl_lost','WebGL context lost',''));
const ce=console.error.bind(console);console.error=function(...a){try{const s=a.map(String).join(' ');if(/Aborted|out of memory|RuntimeError|unreachable|memory access out of bounds/i.test(s))add('wasm',s,'')}catch(e){}return ce(...a)};
window.OozeCrash={take:()=>{const o=q;q=[];return JSON.stringify(o)},previous:()=>{const p=prev;prev=null;return p===null?'':p}};})()"""


static func install() -> void:
	## Once per run on a player's device (never the match host / headless / tests): the error logger, the web hooks,
	## the unclean-exit check, and the session event.
	if _installed or not enabled:
		return
	_installed = true
	_logger = CrashLog.new()
	OS.add_logger(_logger)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval(CRASH_JS, true)
		var prev := str(JavaScriptBridge.eval("window.OozeCrash?OozeCrash.previous():''", true))
		if prev != "" and prev != "null":
			var last = JSON.parse_string(prev)
			var lines := []
			if last is Array:
				for x in last:
					if x is Dictionary:
						lines.append("%s: %s" % [x.get("where", ""), x.get("message", "")])
			crash("unclean_exit", "the page stopped while playing" if lines.is_empty() else str(lines[-1]),
					"\n".join(lines))
	event("session", session_data())


static func session_data() -> Dictionary:
	var vp := DisplayServer.window_get_size()
	var platform := "web" if OS.has_feature("web") else OS.get_name().to_lower()
	if OS.has_feature("web_android"):
		platform = "web_android"
	elif OS.has_feature("web_ios"):
		platform = "web_ios"
	return {"platform": platform, "mobile": PerfProfile.is_phone(),
			"screen": "%dx%d" % [int(round(vp.x / 10.0)) * 10, int(round(vp.y / 10.0)) * 10],   # a bucket, not exact
			"dpr": snappedf(DisplayServer.screen_get_scale(), 0.25),
			"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"touch": DisplayServer.is_touchscreen_available(), "graphics": PerfProfile.level(),
			"fps_cap": PerfProfile.play_fps()}             # the match cap (the menu idles lower by design)


static func signature(message: String) -> String:
	## One bug = one row: the first line, numbers and hex ids stripped, cut to 160 (the build is its own column).
	var first := message.strip_edges().split("\n")[0]
	first = RegEx.create_from_string("0x[0-9a-fA-F]+|[0-9]+").sub(first, "#", true)
	return first.substr(0, 160)


static func crash(where: String, message: String, stack := "") -> bool:
	## A crash / error report (deduplicated per run by signature, at most Rules.TELEMETRY "crashes_per_run").
	var msg := scrub(message, 500)
	var sig := signature(msg)
	if sig == "" or _crash_sigs.has(sig) or _crash_sigs.size() >= int(Rules.TELEMETRY["crashes_per_run"]):
		return false
	_crash_sigs[sig] = true
	var st := "\n".join(Array(scrub(stack, 1400).split("\n")).slice(0, 10))
	var platform := "web" if OS.has_feature("web") else OS.get_name().to_lower()
	return event("crash", {"sig": sig, "where": scrub(where, 120), "message": msg, "stack": st, "platform": platform})


static func _drain_logger() -> void:
	if _logger == null:
		return
	for x in _logger.take():
		crash(str(x["where"]), "%s: %s" % [x["kind"], x["message"]], str(x["stack"]))


static func _poll_web_crashes(dt: float) -> void:
	if not _installed or not OS.has_feature("web"):
		return
	_web_t += dt
	if _web_t < 3.0:
		return
	_web_t = 0.0
	var js = JSON.parse_string(str(JavaScriptBridge.eval("window.OozeCrash?OozeCrash.take():'[]'", true)))
	if js is Array:
		for x in js:
			if x is Dictionary:
				crash(str(x.get("where", "js")), str(x.get("message", "")), str(x.get("stack", "")))


# ------------------------------------------------------------------ performance (§2 perf)
static var _hist := PackedInt32Array()              # frame times, 1 ms buckets 0..250
static var _frames := 0
static var _sum := 0.0
static var _max := 0.0
static var _long := 0
static var _draws := PackedInt32Array()
static var _sec_t := 0.0
static var _sec_n := 0
static var _fps_min := 1000
static var _in_match := false
static var _menu_t := 0.0
static var _page_t := {}                            # page -> seconds in this sample (the menu perf sample says which page stutters)
static var _phone := -1                            # PerfProfile.is_phone(), read once


static func perf_reset() -> void:
	_hist = PackedInt32Array()
	_hist.resize(251)
	_frames = 0
	_sum = 0.0
	_max = 0.0
	_long = 0
	_draws = PackedInt32Array()
	_sec_t = 0.0
	_sec_n = 0
	_fps_min = 1000
	_page_t = {}


static func frame(dt: float, in_match: bool, page := "") -> void:
	## Every frame from main.gd (menu and match). A new match (or the menu again) starts a fresh sample; phones send a
	## menu sample once a minute.
	if not enabled:
		return
	if _hist.is_empty() or in_match != _in_match:
		_in_match = in_match
		perf_reset()
		_menu_t = 0.0
	if page != "" and (_page_t.has(page) or _page_t.size() < 12):
		_page_t[page] = float(_page_t.get(page, 0.0)) + dt
	var ms := clampi(int(dt * 1000.0), 0, 250)
	_hist[ms] += 1
	_frames += 1
	_sum += dt
	_max = maxf(_max, dt)
	if ms >= int(Rules.TELEMETRY["long_frame_ms"]):
		_long += 1
	if _frames % 30 == 0 and _draws.size() < 4000:
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_sec_t += dt
	_sec_n += 1
	if _sec_t >= 1.0:
		_fps_min = mini(_fps_min, _sec_n)
		_sec_t = 0.0
		_sec_n = 0
	if _phone < 0:
		_phone = 1 if PerfProfile.is_phone() else 0
	if not in_match and _phone == 1:
		_menu_t += dt
		if _menu_t >= float(Rules.TELEMETRY["menu_perf_s"]):
			perf_event("menu")


static func perf_stats() -> Dictionary:
	var pct := func(p: float) -> int:
		var want := int(ceil(_frames * p))
		var acc := 0
		for i in range(_hist.size()):
			acc += _hist[i]
			if acc >= want:
				return i
		return 250
	var draws := Array(_draws)
	draws.sort()
	return {"frame_ms_p50": pct.call(0.5), "frame_ms_p95": pct.call(0.95), "frame_ms_max": int(_max * 1000.0),
			"fps_avg": snappedf(_frames / _sum, 0.1) if _sum > 0.0 else 0.0,
			"fps_min": _fps_min if _fps_min < 1000 else 0,
			"draw_p95": int(draws[int(draws.size() * 0.95)]) if not draws.is_empty() else 0,
			"objects": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "time_s": snappedf(_sum, 0.1),
			"long_frames": _long, "graphics": PerfProfile.level()}


static func page_key(p: String) -> String:
	## "SETTINGS" / "lesson_3" -> a telemetry key ([a-z0-9_], <= 32; the telemetry function drops other keys).
	var k := RegEx.create_from_string("[^a-z0-9_]+").sub(p.to_lower().strip_edges(), "_", true)
	return k.substr(0, 32) if k != "" else "unknown"


static func perf_event(where: String) -> bool:
	## Sends the sample so far and starts a new one; the Architect's PerfProfile.match_stats() (playing time only,
	## first second skipped) rides in "extra".
	if _frames < 30:
		return false
	var d := perf_stats()
	d["where"] = where
	d["extra"] = PerfProfile.match_stats()             # 0.21.4: the match's playing-time sample ({} off a match)
	if where == "menu" and not _page_t.is_empty():       # which page: the longest-open one in "where", seconds per page
		var top := ""
		var pages := {}
		for k in _page_t:
			var key := page_key(str(k))
			pages[key] = snappedf(float(pages.get(key, 0.0)) + float(_page_t[k]), 0.1)
			if top == "" or float(pages[key]) > float(pages[top]):
				top = key
		d["where"] = "menu:" + top
		d["extra"] = pages
	perf_reset()
	_menu_t = 0.0
	return event("perf", d)


# ------------------------------------------------------------------ match / funnel (§2)
static func match_event(sim: Sim, seat: String, info: Dictionary) -> bool:
	## One finished (or abandoned) match for this device's seat. info: map, mode, online, server_hosted, ai_level,
	## left_early.
	if not sim.factions.has(seat):
		return false
	var won := sim.winner != "" and (sim.winner == seat or sim.allied(seat, sim.winner))
	var st := Progression.seat_stats(sim, seat)
	return event("match", {"map": str(info.get("map", "")), "mode": str(info.get("mode", "")),
			"faction": str(sim.factions.get(seat, "")),
			"result": "left" if info.get("left_early", false) else ("draw" if sim.winner == "" else ("win" if won else "loss")),
			"duration_s": snappedf(sim.time, 1.0), "ai_level": str(info.get("ai_level", "")),
			"online": bool(info.get("online", false)), "server_hosted": bool(info.get("server_hosted", false)),
			"abilities": Rules.abilities_on, "last_stand": sim.last_stand_active,
			"left_early": bool(info.get("left_early", false)),
			"placed": int(Progression.placements(sim).get(seat, 0)),
			"stats": {"captures": st["captures"], "sends": st["sends"], "relay_fires": st["relay_fires"],
					"void_drops": st["void_drops"], "monster_launches": st["monster_launches"],
					"monster_kicks": st["monster_kicks"], "skills": st["skills"], "nodes_lost": st["nodes_lost"],
					"units_lost_combat": st["units_lost_combat"], "units_lost_falls": st["units_lost_falls"]},
			"net": _net_numbers(info.get("net", {}))})   # NET (🖥️ Server): a guest's connection over the round; {} otherwise


static func _net_numbers(n) -> Dictionary:
	## NET: only the known numeric keys of Net.round_net_stats() travel (nothing identifying).
	var out := {}
	if n is Dictionary:
		for k in ["hz", "gap_max_ms", "freezes", "freeze_s", "rtt_ms", "rtt_max_ms", "buffer_max_s", "corrections", "hard_snaps"]:
			if n.has(k) and (n[k] is int or n[k] is float):
				out[k] = n[k]
		if n.has("server_hosted"):
			out["server_hosted"] = bool(n["server_hosted"])
	return out


static func funnel(step: String, id := "", extra := {}) -> bool:
	## Tutorial lessons, campaign missions, the first online round: step + id (+ seconds, stars, result).
	var d := {"step": step, "id": id}
	for k in extra:
		if k in ["seconds", "stars", "result"]:
			d[k] = extra[k]
	return event("funnel", d)


static func funnel_once(step: String) -> bool:
	## A step that counts once per device ever (the first online round).
	var cf := ConfigFile.new()
	cf.load(path)
	if bool(cf.get_value("once", step, false)):
		return false
	cf.set_value("once", step, true)
	cf.save(path)
	return funnel(step)


# ------------------------------------------------------------------ what the player reads (§6; wording: Daniele's call)
static func notice_text() -> String:
	var TL := Rules.TELEMETRY
	return ("Ooze Syndicate can send gameplay and performance numbers (maps, factions, match length, frame rate) and "
			+ "crash reports, so we can fix bugs and balance the game. They are tied only to your game account id: "
			+ "no name, email, contacts or location, no ads, never sold. Kept %d days (crash reports %d). " % [
				int(TL["retention_days"]), int(TL["crash_retention_days"])]
			+ "Change it any time in SETTINGS or ACCOUNT, where you can also delete your account.")


static func privacy_text() -> String:
	## The PRIVACY page and privacy.html say the same (the store listings link the page).
	var TL := Rules.TELEMETRY
	return "\n\n".join([
		"WHAT THE GAME KEEPS TO WORK",
		"Your progress (level, SCRAP, SYNDICATE CHIPS, unlocks, challenges, tutorial and campaign) is saved on this device. "
			+ "When you are online the game also gives you an automatic guest account: a random id and a player name "
			+ "(SLIME-xxxxx until you rename it), a cloud copy of your progress, your server-hosted match results for MATCH "
			+ "HISTORY and the leaderboards. If you add Google, the account also holds the email address Google gives us, "
			+ "used only to sign you in.",
		"SHARE PLAY & CRASH DATA (THE SWITCH IN SETTINGS AND ACCOUNT)",
		"When it is ON the game sends: a session record (platform, phone or not, a rounded screen size, graphics setting), "
			+ "a record per match (map, mode, faction, result, length, AI level, your counters such as captures and relay "
			+ "fires), performance numbers (frame times, frame rate, draw calls), online connection quality (updates per second, freezes, round trip), tutorial / campaign progress steps, and "
			+ "crash reports (the error text and where in the game it happened, with web addresses, keys and email "
			+ "addresses removed). Records carry your game account id and the game version - never your name, email, "
			+ "room codes, chat, what you type or where you are.",
		"When it is OFF nothing of this leaves the device and anything waiting to be sent is deleted. "
			+ "Players in the EU, EEA, UK and Switzerland start with it OFF and choose; elsewhere it starts ON.",
		"HOW LONG",
		"Play and performance records: %d days. Crash reports: %d days after that error was last seen. Then they are "
			% [int(TL["retention_days"]), int(TL["crash_retention_days"])]
			+ "deleted automatically. Your account and its cloud save stay until you delete them.",
		"WHO",
		"No ads, no selling, no third-party trackers. The data is stored with Supabase (servers in Singapore) and read "
			+ "only by the Ooze Syndicate team. Like any website, the servers see your IP address when the game connects; "
			+ "the game never stores it with your records.",
		"DELETE YOUR ACCOUNT",
		"ACCOUNT > DELETE ACCOUNT deletes your account, cloud save, match history, leaderboard entries and shared play "
			+ "data at once. Your finished rounds stay in other players' history without your name. The progress saved on "
			+ "this device stays; the next time you play online you get a new guest account. You can also ask by email.",
		"AGE",
		"Ooze Syndicate is for players aged %d and over." % int(TL["min_age"]),
		"CONTACT",
		"%s  ·  %s" % [str(TL["contact"]), str(TL["policy_url"])],
	])
