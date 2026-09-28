extends SceneTree
## Telemetry / privacy check:  Godot --headless --path . --script res://tests/test_telemetry.gd [-- --live]
## Offline (always): consent by region (opt-in in the EU / UK, Daniele 2026-09-28), nothing kept once the switch is OFF,
## the queue's caps, scrubbing, crash signatures + dedupe, Godot's errors reaching the crash queue, the perf sample,
## the match event, the match-log pruning, web/privacy.html equal to the PRIVACY page. --live signs a real guest in,
## uploads a batch to the `telemetry` function and deletes the account through `delete-account` (so it leaves no
## test user behind; if the deletion fails, the printed id must be deleted by hand). Exit 0 = passed.

var failures := 0
const PRIV := "user://test_telemetry_privacy.cfg"
const QUEUE := "user://test_telemetry_queue.json"
const LOGS := "user://test_telemetry_logs"


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1
	else:
		print("PASS  " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Telemetry.path = PRIV
	Telemetry.queue_path = QUEUE
	Telemetry.enabled = true
	_wipe()
	_regions()
	_consent()
	_queue_caps()
	_scrubbing()
	_crashes()
	_logger()
	_perf()
	_match()
	_prune()
	_policy_page()
	if "--live" in OS.get_cmdline_user_args():
		await _live()
	_wipe()
	print("test_telemetry: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _wipe() -> void:
	for p in [PRIV, QUEUE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Telemetry.force_region = ""
	Telemetry.forget_all()


func _regions() -> void:
	check(Telemetry.is_eu("Europe/Rome", "it_IT"), "Europe/Rome is EU")
	check(Telemetry.is_eu("Europe/London", "en-GB"), "the UK counts (opt-in)")
	check(Telemetry.is_eu("Atlantic/Canary", "es_ES"), "the Canaries count")
	check(not Telemetry.is_eu("Asia/Singapore", "en-SG"), "Singapore is not EU")
	check(not Telemetry.is_eu("America/New_York", "en-US"), "New York is not EU")
	check(Telemetry.is_eu("Asia/Tokyo", "it-IT"), "an Italian locale abroad still counts (the stricter reading)")
	check(Telemetry.is_eu("", ""), "nothing readable: unsure = EU")
	check(Telemetry.is_eu("UTC", ""), "UTC with no locale region: unsure = EU")
	check(not Telemetry.is_eu("UTC", "en_US"), "UTC with a US locale: not EU")
	check(Telemetry.is_eu("W. Europe Standard Time", "en_US"), "a Windows European zone name counts")
	check(not Telemetry.is_eu("Pacific Standard Time", "en_US"), "a Windows US zone name doesn't")


func _consent() -> void:
	_wipe()
	Telemetry.force_region = "eu"
	check(Telemetry.opt_in() and not Telemetry.default_share(), "EU: the switch starts OFF (opt-in)")
	Telemetry.force_region = "other"
	check(not Telemetry.opt_in() and Telemetry.default_share(), "elsewhere: the switch starts ON (opt-out)")
	check(Telemetry.notice_due() and not Telemetry.sharing(), "before the notice: due, nothing shared")
	check(Telemetry.event("session", {"platform": "web"}), "an event before the notice is kept on the device")
	Telemetry.choose(false)
	check(not Telemetry.notice_due() and not Telemetry.sharing(), "TURN OFF: answered, OFF")
	check(Telemetry.queue().is_empty() and not FileAccess.file_exists(QUEUE), "TURN OFF drops what was waiting")
	check(not Telemetry.event("session", {"platform": "web"}), "OFF: nothing is queued")
	Telemetry.forget_all()
	check(not Telemetry.notice_due() and not Telemetry.sharing(), "the answer is saved (a new run: no notice, still OFF)")
	Telemetry.choose(true)
	check(Telemetry.sharing() and Telemetry.event("session", {"platform": "web"}), "ON again: events queue")
	Telemetry.forget_all()
	check(Telemetry.queue().size() == 1, "the queue survives a restart")
	Telemetry.enabled = false
	check(not Telemetry.event("session", {}) and not Telemetry.notice_due(), "disabled (host / headless): nothing, no notice")
	Telemetry.enabled = true
	check(not Telemetry.event("keystrokes", {"k": "a"}), "unknown kinds are refused")


func _queue_caps() -> void:
	_wipe()
	Telemetry.choose(true)
	for i in range(int(Rules.TELEMETRY["queue_max"]) + 25):
		Telemetry.event("funnel", {"step": "lesson_start", "id": str(i)})
	var q := Telemetry.queue()
	check(q.size() == int(Rules.TELEMETRY["queue_max"]), "the queue holds at most %d (%d)" % [Rules.TELEMETRY["queue_max"], q.size()])
	check(str(q[0]["data"]["id"]) == "25", "the oldest are dropped first")
	var big := "x".repeat(3000)
	check(not Telemetry.event("funnel", {"step": big}) or JSON.stringify(Telemetry.queue()[-1]).length() <= 2048,
			"an event over 2 KB is not queued (strings are cut to 500 first)")
	var deep = Telemetry.clean({"a": {"b": {"c": 1}}, "f": 1.23456, "n": NAN})
	check(deep["a"]["b"] == null and deep["f"] == 1.23 and deep["n"] == null, "clean: two levels, rounded, no NaN: %s" % str(deep))


func _scrubbing() -> void:
	var s := Telemetry.scrub("at https://talos91.github.io/ooza-syndicate-v2/#access_token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop&x=1 by me@mail.com key sb_publishable_3aX4T8IcNbI_BBg4wENMhA")
	check(not s.contains("access_token") and not s.contains("eyJ") and not s.contains("me@mail.com")
			and not s.contains("sb_publishable"), "scrub: no fragment, token, email or key: %s" % s)
	check(s.contains("https://talos91.github.io/ooza-syndicate-v2/"), "scrub keeps the page address")
	check(Telemetry.scrub("ab ".repeat(300)).length() == 500, "scrub cuts to 500")
	check(Telemetry.scrub("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop end") == "jwt <jwt> end",
			"a bare JWT is replaced")


func _crashes() -> void:
	_wipe()
	Telemetry.choose(true)
	check(Telemetry.signature("SCRIPT ERROR: Invalid index 12 at 0x7ffe1234 (line 88)\nat: foo")
			== "SCRIPT ERROR: Invalid index # at # (line #)", "the signature strips numbers and hex, first line only")
	check(Telemetry.crash("main.gd:88", "Invalid index 12", "frame 1\nframe 2"), "a crash is queued")
	check(not Telemetry.crash("main.gd:88", "Invalid index 13", ""), "the same bug again (other numbers) is not")
	var n := 1
	for i in range(30):
		if Telemetry.crash("x", "bug kind %s" % char(65 + i), ""):
			n += 1
	check(n == int(Rules.TELEMETRY["crashes_per_run"]), "at most %d crash reports per run (%d)" % [Rules.TELEMETRY["crashes_per_run"], n])
	var c: Dictionary = Telemetry.queue()[0]
	check(c["kind"] == "crash" and c["data"].has("sig") and c["data"].has("stack") and not c["data"].has("user"),
			"a crash carries sig / where / message / stack / platform only: %s" % str(c["data"].keys()))


func _logger() -> void:
	_wipe()
	Telemetry.choose(true)
	var lg := Telemetry.CrashLog.new()
	OS.add_logger(lg)
	Telemetry._logger = lg
	push_error("telemetry test error 77")
	push_warning("a warning is not a crash")
	Telemetry._drain_logger()
	OS.remove_logger(lg)
	Telemetry._logger = null
	var q := Telemetry.queue()
	check(q.size() == 1 and str(q[0]["data"]["message"]).contains("telemetry test error 77"),
			"push_error reaches the crash queue through the Logger, warnings don't (%d queued)" % q.size())


func _perf() -> void:
	_wipe()
	Telemetry.choose(true)
	Telemetry.perf_reset()
	Telemetry.frame(0.016, true)                    # first call in a match: a fresh sample
	for i in range(98):
		Telemetry.frame(0.016, true)
	Telemetry.frame(0.120, true)
	var st := Telemetry.perf_stats()
	check(st["frame_ms_p50"] == 16 and st["frame_ms_max"] == 120 and st["long_frames"] == 1,
			"perf: p50 16 ms, max 120 ms, one long frame: %s" % str(st))
	check(Telemetry.perf_event("match") and Telemetry.queue()[-1]["kind"] == "perf", "perf event queued")
	check(Telemetry.queue()[-1]["data"].get("extra") is Dictionary, "PerfProfile.match_stats() rides in extra")
	check(not Telemetry.perf_event("match"), "an empty sample sends nothing")
	# the menu sample says which page was open (📐 Architect: "so we can see which page stutters")
	for i in range(60):
		Telemetry.frame(0.033, false, "home")
	for i in range(30):
		Telemetry.frame(0.033, false, "FACTION")
	check(Telemetry.perf_event("menu"), "menu perf event queued")
	var md: Dictionary = Telemetry.queue()[-1]["data"]
	check(md["where"] == "menu:home" and md["extra"].has("home") and md["extra"].has("faction")
			and absf(float(md["extra"]["home"]) - 2.0) < 0.1, "menu sample: longest page in where, seconds per page: %s" % str(md))
	check(Telemetry.page_key("lesson 3 / L0!") == "lesson_3_l0_", "page keys fit the function's key rule")


func _match() -> void:
	_wipe()
	Telemetry.choose(true)
	var sim := Sim.new()
	sim.factions = {"A": "vex", "B": "ember"}
	sim.homes = {"A": 1, "B": 2}
	sim.winner = "A"
	sim.time = 301.4
	sim.events = [{"type": "capture", "node": 5, "seat": "A", "from": ""}, {"type": "relay_fired", "node": 9, "seat": "A"}]
	check(Telemetry.match_event(sim, "A", {"map": "M-07", "mode": "1v1", "ai_level": "Veteran"}), "the match event is queued")
	var d: Dictionary = Telemetry.queue()[-1]["data"]
	check(d["result"] == "win" and d["faction"] == "vex" and d["map"] == "M-07" and d["stats"]["captures"] == 1
			and d["stats"]["relay_fires"] == 1 and d["placed"] == 1 and d["duration_s"] == 301.0, "match fields: %s" % str(d))
	check(not d.has("names") and not str(d).contains("room"), "no names or room codes in the match event")
	check(Telemetry.match_event(sim, "B", {"left_early": true}) and Telemetry.queue()[-1]["data"]["result"] == "left",
			"leaving early says so")


func _prune() -> void:
	DirAccess.make_dir_recursive_absolute(LOGS)
	for f in DirAccess.get_files_at(LOGS):
		DirAccess.remove_absolute(LOGS.path_join(f))
	for i in range(25):
		var f := FileAccess.open(LOGS.path_join("match_%d.json" % (1790000000 + i)), FileAccess.WRITE)
		f.store_string("{}")
		f.close()
	check(Telemetry.prune_logs(LOGS, 20) == 5 and DirAccess.get_files_at(LOGS).size() == 20, "the match logs keep the newest 20")
	check(not FileAccess.file_exists(LOGS.path_join("match_1790000000.json"))
			and FileAccess.file_exists(LOGS.path_join("match_1790000024.json")), "the oldest go first")
	for f in DirAccess.get_files_at(LOGS):
		DirAccess.remove_absolute(LOGS.path_join(f))
	DirAccess.remove_absolute(LOGS)


func _policy_page() -> void:
	var html := FileAccess.get_file_as_string("res://web/privacy.html")
	var ok := html != ""
	for para in Telemetry.privacy_text().split("\n\n"):
		if not html.contains(para.xml_escape()):
			ok = false
			print("  missing in privacy.html: ", para.substr(0, 60))
	check(ok, "web/privacy.html says what the PRIVACY page says (tests/make_privacy_html.gd rewrites it)")
	check(Telemetry.notice_text().contains("%d days" % int(Rules.TELEMETRY["retention_days"])), "the notice names the retention")


func _live() -> void:
	_wipe()
	Telemetry.choose(true)
	Account.path = "user://test_telemetry_session.cfg"
	var a := Account.get_instance()
	await process_frame
	await a.start(true)
	check(a.signed_in(), "a guest account signs in (%s)" % a.user_id)
	print("LIVE test user: ", a.user_id, "  (deleted below; delete by hand if that fails)")
	Telemetry.event("session", Telemetry.session_data())
	Telemetry.event("funnel", {"step": "lesson_start", "id": "1"})
	Telemetry.crash("test", "live test crash %d" % randi(), "frame")
	var n := await Telemetry.flush(a)
	check(n == 3 and Telemetry.queue().is_empty(), "the telemetry function takes a batch (%d accepted)" % n)
	var forged := await a._call("GET", "/rest/v1/telemetry_events?select=id", null, true)
	check(not forged["ok"] or (forged["json"] is Array and (forged["json"] as Array).is_empty()),
			"RLS: players can't read telemetry (%d)" % int(forged["code"]))
	var old_refresh := a.refresh_token
	check(await a.delete_account() and a.state == "deleted" and not a.signed_in(), "DELETE ACCOUNT works (%s)" % a.last_error)
	a.refresh_token = old_refresh
	check(not await a.refresh(), "the deleted account's session is gone")
	a._clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Account.path))
