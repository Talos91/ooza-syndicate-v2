extends SceneTree
## Accounts check:  Godot --headless --path . --script res://tests/test_account.gd [-- --live]
## Offline (always): the redirect fragment parser; the cloud save packs the device's save files and restores them
## (account wins), on scratch paths. --live also signs a real guest in on Supabase, renames it, pushes and reads back
## its cloud save and reads the leaderboard - it creates one anonymous user (the printed id) to delete afterwards.
## Exit 0 = passed.

var failures := 0
const PATHS := {"progress": "user://test_account_progress.cfg", "armies": "user://test_account_armies.cfg",
		"tutorial": "user://test_account_tutorial.cfg", "account": "user://test_account_session.cfg"}


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1
	else:
		print("PASS  " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Progression.path = PATHS["progress"]
	ArmyPresets.path = PATHS["armies"]
	TutorialDirector.path = PATHS["tutorial"]
	Account.path = PATHS["account"]
	_wipe()
	_fragment()
	_save_round_trip()
	if "--live" in OS.get_cmdline_user_args():
		await _live()
	_wipe()
	print("test_account: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _wipe() -> void:
	for p in PATHS.values():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progression.reload_all()
	ArmyPresets.reload_presets()
	TutorialDirector.reload_progress()


func _fragment() -> void:
	var d := Account.parse_fragment("#access_token=abc.def&refresh_token=r1&expires_in=3600&token_type=bearer&type=magiclink")
	check(d.get("access_token") == "abc.def" and d.get("refresh_token") == "r1" and d.get("expires_in") == 3600,
			"the redirect fragment gives the session: %s" % str(d))
	var e := Account.parse_fragment("#error=access_denied&error_description=Email+link+is+invalid")
	check(e.get("error_description") == "Email link is invalid", "an error fragment is read too (+ decodes as a space)")
	check(Account.parse_fragment("").is_empty(), "no fragment, no session")


func _save_round_trip() -> void:
	Progression.grant("tutorial:1", 140)
	Progression.unlock("vat:faction:vex", "campaign:vex")
	ArmyPresets.set_pick("vex", "active", "fortify")
	TutorialDirector.mark_complete(2)
	var pack := Account.pack_save()
	check(pack.get("v") == 1 and str(pack["files"]["progress"]).contains("tutorial:1"), "the pack carries the progress file")
	var text := JSON.stringify(pack)
	_wipe()
	check(Progression.balance() == 0 and not Progression.has_granted("tutorial:1"), "a fresh device has nothing")
	check(Account.restore_save(JSON.parse_string(text)), "a restore from the JSON copy works")
	check(Progression.balance() == 280 and Progression.owns("vat:faction:vex") and Progression.has_granted("tutorial:2"),   # lesson 2 paid 140 too
			"wallet, unlocks and grants come back")
	check(ArmyPresets.loadout_for("vex", true)["active"] == "fortify", "ARMIES picks come back")
	check(TutorialDirector.is_done(2), "tutorial progress comes back")
	check(not Account.restore_save({"v": 2}), "an unknown save version is refused")


func _live() -> void:
	var a := Account.get_instance()
	await process_frame
	await a.start(true)
	check(a.signed_in() and a.is_anonymous and a.user_id != "", "a guest account signs in (%s)" % a.user_id)
	print("LIVE test user: ", a.user_id, "  (delete it afterwards)")
	check(a.player_name.begins_with("SLIME-"), "its profile has the default name (%s)" % a.player_name)
	check(await a.rename("test slime"), "rename works")
	check(a.player_name == "TEST SLIME", "names come back upper case")
	check(not await a.rename("x"), "a too-short name is refused (%s)" % a.last_error)
	Progression.grant("live:test", 77)
	check(await a.push_save(), "the cloud save uploads")
	var r := await a._call("GET", "/rest/v1/cloud_saves?select=save,build&user_id=eq." + a.user_id, null, true)
	check(r["ok"] and r["json"] is Array and (r["json"] as Array).size() == 1
			and str(r["json"][0]["save"]["files"]["progress"]).contains("live:test"), "the cloud copy holds this device's progress")
	var board := await a.leaderboard()
	check(board is Array, "the season board answers (%d rows)" % board.size())
	var t := a.access_token
	check(await a.refresh() and a.access_token != "" and a.user_id != "", "the session refreshes")
	var other := await a._call("GET", "/rest/v1/cloud_saves?select=user_id", null, true)
	check(other["ok"] and (other["json"] as Array).all(func(row): return row["user_id"] == a.user_id),
			"RLS: a player reads only their own cloud save")
	var forged := await a._call("POST", "/rest/v1/match_seats", {"match_id": "x", "seat": "A", "won": true}, true)
	check(not forged["ok"], "RLS: a player can't write match results (%d)" % int(forged["code"]))
	# "account wins": account 1 saved above; a device that is account 2 with its own progress signs into account 1
	var first_id := a.user_id
	var first_refresh := a.refresh_token
	a._clear()
	_wipe()
	Progression.grant("device:two", 999)
	check(await a.sign_in_guest() and a.user_id != first_id, "a second guest account (%s)" % a.user_id)
	print("LIVE test user: ", a.user_id, "  (delete it afterwards)")
	check(Progression.has_granted("device:two"), "account 2 keeps this device's progress (a brand-new account)")
	a.refresh_token = first_refresh
	check(await a.refresh() and a.user_id == first_id, "signing back into account 1")
	check(Progression.has_granted("live:test") and not Progression.has_granted("device:two"),
			"account 1's cloud progress replaced the device's (account wins)")
