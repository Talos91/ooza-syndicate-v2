extends SceneTree
## Headless campaign check:  Godot --headless --path . --script res://tests/test_campaign.gd
## Exit code 0 = all passed. CAMPAIGN-DESIGN.md §2 / §5 / §5a: the data (every mission complete, maps exist for the
## playable ones, one-off sources unique), linear opening with side nodes, the three star rules, the one-off reward
## (3 stars + optional objective in the SAME run, never paid twice), the Progression bridge (with a stand-in wallet
## and without one: recorded, then paid by pay_pending), the faction vat unlock at the end, progress round-trip.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


const FAKE_PROGRESSION := """extends RefCounted
static var granted := {}
static var unlocks := {}
static func grant(source: String, amount: int, currency := "soft") -> bool:
	if granted.has(source):
		return false
	granted[source] = amount
	return true
static func has_granted(source: String) -> bool:
	return granted.has(source)
static func unlock(item: String, source: String) -> bool:
	if unlocks.has(item):
		return false
	unlocks[item] = source
	return true
static func is_unlocked(item: String) -> bool:
	return unlocks.has(item)
"""


func _init() -> void:
	Campaign.path = "user://test_campaign_progress.cfg"
	Campaign.use_progression(null)
	Campaign.reset_progress()
	_data()
	_opening()
	_stars()
	_rewards_without_progression()
	_rewards_with_progression()
	_round_trip()
	_audit_fixes()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.path))
	print("\n%s - %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _data() -> void:
	var ms := Campaign.missions("vex")
	check(ms.size() == 13, "VEX: 10 main + 3 side missions (%d)" % ms.size())
	check(Campaign.main_missions("vex").size() == 10, "VEX: 10 main missions")
	var sources := {}
	var fields_ok := true
	var maps_ok := true
	for m in ms:
		for f in ["id", "title", "story", "type", "kind", "map", "par", "objective", "optional", "ai", "rival", "brief", "pos"]:
			if not m.has(f):
				fields_ok = false
				print("   missing ", f, " in ", m.get("key"))
		sources[Campaign.source_of(str(m["key"]))] = true
		if str(m.get("needs", "")) == "" and not ResourceLoader.exists(str(m["map"])):
			maps_ok = false
			print("   no map for ", m["key"], ": ", m["map"])
		if str(m["kind"]) == "side":
			check(Campaign.mission(Campaign.key_of("vex", str(m["parent"]))).size() > 0, "%s hangs off an existing main mission" % m["key"])
		check(Rules.AI_LEVELS.has(str(m["ai"])), "%s: AI level %s exists" % [m["key"], m["ai"]])
		check(Campaign.RIVALS.has(str(m["rival"])), "%s: rival %s exists" % [m["key"], m["rival"]])
		check(str(m["optional"].get("text", "")) != "", "%s: optional objective has its text" % m["key"])
	check(fields_ok, "every mission has every field")
	check(maps_ok, "every playable mission's (placeholder) map exists")
	check(sources.size() == ms.size(), "one-off sources are unique")
	check(Campaign.source_of("vex:04") == "campaign:vex:04", "source tag format campaign:<faction>:<mission>")
	check(Campaign.reward_for(Campaign.mission("vex:01")) == 150 and Campaign.reward_for(Campaign.mission("vex:03")) == 200
			and Campaign.reward_for(Campaign.mission("vex:s1")) == 200 and Campaign.reward_for(Campaign.mission("vex:10")) == 300,
			"rewards 150 main / 200 duel / 200 side / 300 finale")
	var total := 0
	for m in ms:
		total += Campaign.reward_for(m)
	check(total == 2350, "VEX total reward 2 350 SCRAP (%d)" % total)
	check(Campaign.playable(Campaign.mission("vex:01")) and not Campaign.playable(Campaign.mission("vex:04")),
			"District 1 playable; a mission needing the event deck is not")
	check(not Campaign.has_content("null") and Campaign.has_content("vex"), "only VEX has content so far")
	check(Campaign.fill("Drop {n} units", Campaign.mission("vex:02")) == "Drop 60 units", "brief placeholders fill")
	# the CAMPAIGN MENU's episode cards (Alpha 21)
	Campaign.reset_progress()
	var eps := Campaign.episodes()
	check(eps.size() == 5 and str(eps[0]["faction"]) == "vex", "five episode cards, VEX first")
	check(str(eps[0]["state"]) == "open" and str(eps[0]["title"]) == "GOING UNDER" and int(eps[0]["stars_max"]) == 39
			and str(eps[0]["next"]) == "vex:01", "VEX: open, its episode title, 0 / 39, CONTINUE = 01")
	check(eps.slice(1).all(func(e): return str(e["state"]) == "coming" and int(e["stars_max"]) == 0 and str(e["next"]) == ""),
			"the other four: COMING LATER, no stars, nothing to continue")
	check(eps.all(func(e): return ResourceLoader.exists(str(e["art"]))), "every card's faction art exists")
	Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 3, "objective": false})
	check(Campaign.progress_total() == Vector2i(3, 39) and int(Campaign.episodes()[0]["stars"]) == 3,
			"progress totals follow the stars (3 / 39)")
	# the CAMPAIGN HUB (Alpha 21): one district's cards
	var h := Campaign.hub("vex")
	check(str(h["district_name"]) == "DOCKSIDE" and int(h["district_index"]) == 0 and int(h["district_count"]) == 4,
			"hub opens on the next mission's district: Dockside, 1 of 4")
	var st := {}
	for c in h["missions"]:
		st[str(c["key"])] = str(c["state"])
	check(st == {"vex:01": "won", "vex:02": "next", "vex:s1": "locked", "vex:03": "locked"}, "card states: won / next / locked (%s)" % st)
	check(str(h["missions"][2]["unlock_hint"]) == "Complete MIND THE GAP to unlock."
			and str(h["missions"][3]["unlock_hint"]) == "Complete MIND THE GAP to unlock." and str(h["missions"][1]["unlock_hint"]) == "",
			"unlock hints name the mission to beat")
	check(str(h["missions"][2]["number"]) == "S1" and int(h["stars"]) == 3 and int(h["stars_max"]) == 12, "numbers and district stars")
	var h2 := Campaign.hub("vex", 1)
	check(str(h2["missions"][0]["state"]) == "dev" and str(h2["missions"][0]["needs"]) != "", "an unbuilt mission reads dev")
	check(str(h["missions"][0]["backdrop"]) == "res://assets/art/campaign/vex-01.jpg", "vex:01's own art (tools/ui_art.py)")
	check(Campaign.backdrop_of("null:01") == "", "no art for a mission: empty path (the card falls back)")
	Campaign.reset_progress()


func _opening() -> void:
	Campaign.reset_progress()
	check(Campaign.owned("vex") and not Campaign.owned("ember"), "VEX is free, EMBER is not owned")
	check(Campaign.is_open("vex:01"), "the first mission is open")
	check(not Campaign.is_open("vex:02"), "the second is locked until the first is won")
	check(not Campaign.is_open("vex:s1"), "a side mission is locked until its parent is won")
	check(Campaign.next_open("vex") == "vex:01", "CONTINUE = the first mission")
	Campaign.record("vex:01", {"won": false, "time": 100.0, "stars": 0, "objective": false})
	check(not Campaign.is_open("vex:02"), "a loss opens nothing")
	Campaign.record("vex:01", {"won": true, "time": 100.0, "stars": 1, "objective": false})
	check(Campaign.is_open("vex:02"), "winning opens the next main mission")
	Campaign.record("vex:02", {"won": true, "time": 100.0, "stars": 1, "objective": false})
	check(Campaign.is_open("vex:s1") and Campaign.is_open("vex:03"), "winning 02 opens its side mission and 03")
	check(Campaign.next_open("vex") == "vex:03", "CONTINUE skips the optional side mission")
	var s := Campaign.record("vex:03", {"won": true, "time": 100.0, "stars": 1, "objective": false})
	check(bool(s["district_done"]), "winning the district's last main mission finishes Dockside (side missions optional)")
	check(not bool(s["campaign_done"]), "... not the campaign")
	Campaign.record("vex:03", {"won": true, "time": 100.0, "stars": 1, "objective": false})
	check(not Campaign.playable(Campaign.mission("vex:04")) and Campaign.is_open("vex:05"),
			"04 is IN DEVELOPMENT: 05 opens after 03, the chain never blocks")
	check(Campaign.next_open("vex") == "vex:05", "CONTINUE skips an IN DEVELOPMENT mission")
	check(not Campaign.district_done("vex", "exchange"), "a district with an unbuilt main mission never counts as done")
	Campaign.all_open = true
	check(Campaign.is_open("vex:10") and Campaign.owned("solar"), "--campaign-all opens everything")
	Campaign.all_open = false


func _stars() -> void:
	check(Campaign.stars_for(false, 10.0, 100.0, false) == 0, "a loss: 0 stars")
	check(Campaign.stars_for(true, 150.0, 100.0, false) == 1, "a win over par: 1 star")
	check(Campaign.stars_for(true, 90.0, 100.0, true) == 2, "within par but a starting node lost: 2 stars")
	check(Campaign.stars_for(true, 90.0, 100.0, false) == 3, "within par, nothing lost: 3 stars")
	check(Campaign.stars_for(true, 150.0, 100.0, false) == 1, "over par: the third star needs par too")
	Campaign.reset_progress()
	Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 3, "objective": false})
	Campaign.record("vex:01", {"won": true, "time": 200.0, "stars": 1, "objective": false})
	check(Campaign.stars_of("vex:01") == 3, "best stars are kept")
	check(Campaign.stars_total("vex") == 3 and Campaign.stars_max("vex") == 39, "star totals 3 / 39")


func _rewards_without_progression() -> void:
	Campaign.use_progression(null)
	Campaign.reset_progress()
	var s := Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 3, "objective": false})
	check(str(s["reward"]["state"]) == "none", "3 stars without the objective: no reward")
	s = Campaign.record("vex:01", {"won": true, "time": 200.0, "stars": 1, "objective": true})
	check(str(s["reward"]["state"]) == "none", "the objective without 3 stars: no reward (same run, Daniele)")
	check(Campaign.stars_of("vex:01") == 3 and bool(Campaign.record_of("vex:01")["objective"]),
			"... even though the best stars and the objective were each reached once")
	s = Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 3, "objective": true})
	check(str(s["reward"]["state"]) == "earned" and int(s["reward"]["amount"]) == 150,
			"3 stars + objective in one run, no Progression in the build: 150 recorded (earned)")
	check(Campaign.pay_pending() == 0, "pay_pending does nothing without Progression")


func _rewards_with_progression() -> void:
	var fake := GDScript.new()
	fake.source_code = FAKE_PROGRESSION
	fake.reload()
	Campaign.use_progression(fake)
	check(Campaign.pay_pending() == 1, "Progression arrives: the recorded reward is paid")
	check(bool(fake.call("has_granted", "campaign:vex:01")) and Campaign.reward_state("vex:01") == "paid",
			"granted with source campaign:vex:01, the card reads paid")
	check(Campaign.pay_pending() == 0, "paying again pays nothing")
	var s := Campaign.record("vex:01", {"won": true, "time": 80.0, "stars": 3, "objective": true})
	check(str(s["reward"]["state"]) == "taken", "a second perfect run: taken, nothing paid (one-off)")
	s = Campaign.record("vex:02", {"won": true, "time": 80.0, "stars": 3, "objective": true})
	check(str(s["reward"]["state"]) == "paid", "with Progression a perfect run pays at once")
	# the whole campaign: the last main mission unlocks the VEX vat
	for m in Campaign.main_missions("vex"):
		if not Campaign.is_won(str(m["key"])):
			s = Campaign.record(str(m["key"]), {"won": true, "time": 999.0, "stars": 1, "objective": false})
	check(bool(s["campaign_done"]) and "vat:faction:vex" in s["unlocked"], "the finale unlocks vat:faction:vex")
	check(str(fake.call("is_unlocked", "vat:faction:vex")) == "true" and Campaign.unlocks_pending.is_empty(),
			"... through Progression.unlock (source campaign:vex), nothing pending")
	check(Campaign.next_open("vex") == "", "every main mission won: no CONTINUE")
	# without Progression the unlock waits
	Campaign.use_progression(null)
	Campaign.reset_progress()
	for m in Campaign.main_missions("vex"):
		s = Campaign.record(str(m["key"]), {"won": true, "time": 999.0, "stars": 1, "objective": false})
	check(Campaign.unlocks_pending.has("vat:faction:vex"), "no Progression: the vat unlock is recorded")
	var fake2 := GDScript.new()
	fake2.source_code = FAKE_PROGRESSION
	fake2.reload()
	fake2.set("unlocks", {})
	fake2.set("granted", {})
	Campaign.use_progression(fake2)
	Campaign.pay_pending()
	check(Campaign.unlocks_pending.is_empty() and bool(fake2.call("is_unlocked", "vat:faction:vex")),
			"pay_pending replays the vat unlock")
	Campaign.use_progression(null)


func _audit_fixes() -> void:
	## 2026-09-28 audit: a failed storage read keeps the session's progress (private browsing); an already-paid
	## reward reads "taken".
	Campaign.use_progression(null)
	Campaign.reset_progress()
	Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 2, "objective": false})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.path))   # as if the browser never kept it
	Campaign.reload_all()
	Campaign.load_if_needed()
	check(Campaign.is_won("vex:01") and Campaign.is_open("vex:02"),
			"no storage: a failed reload keeps this session's progress (mission 02 still open)")
	var fake := GDScript.new()
	fake.source_code = FAKE_PROGRESSION
	fake.reload()
	fake.set("granted", {Campaign.source_of("vex:02"): 150})   # paid already (another device, a lost local record)
	Campaign.use_progression(fake)
	var sum := Campaign.record("vex:02", {"won": true, "time": 60.0, "stars": 3, "objective": true})
	check(str(sum["reward"]["state"]) == "taken" and Campaign.reward_state("vex:02") == "paid",
			"an already-paid reward shows TAKEN, recorded as paid")
	check(Campaign.reward_for(Campaign.mission("vex:01")) == int(Rules.PROGRESSION["campaign_reward"]["main"]),
			"the mission reward table lives in Rules.PROGRESSION")
	Campaign.use_progression(null)
	fake.set("granted", {})
	Campaign.reset_progress()


func _round_trip() -> void:
	Campaign.reset_progress()
	Campaign.record("vex:01", {"won": true, "time": 90.0, "stars": 3, "objective": true})
	Campaign.record("vex:02", {"won": true, "time": 120.0, "stars": 2, "objective": false})
	Campaign.mark_seen("collapse:dockside")
	Campaign.reload_all()
	check(Campaign.stars_of("vex:01") == 3 and Campaign.stars_of("vex:02") == 2, "stars survive a reload")
	check(Campaign.reward_state("vex:01") == "earned", "the recorded reward survives a reload")
	check(Campaign.was_seen("collapse:dockside"), "seen flags survive a reload")
	check(is_equal_approx(float(Campaign.record_of("vex:02")["best_time"]), 120.0), "best time survives")
	check(Campaign.saved, "the save worked")
	# the cloud save's copy (to_dict / from_dict, the Progression session's accounts)
	var d := Campaign.to_dict()
	var copy: Dictionary = JSON.parse_string(JSON.stringify(d))     # through JSON, like the account's store
	Campaign.reset_progress()
	check(Campaign.stars_of("vex:01") == 0, "reset clears the device")
	Campaign.from_dict(copy)
	check(Campaign.stars_of("vex:01") == 3 and Campaign.stars_of("vex:02") == 2 and Campaign.is_open("vex:03")
			and Campaign.reward_state("vex:01") == "earned" and Campaign.was_seen("collapse:dockside"),
			"from_dict(to_dict()) through JSON restores stars, openings, rewards and seen flags")
	Campaign.reload_all()
	check(Campaign.stars_of("vex:02") == 2, "... and saves them")
