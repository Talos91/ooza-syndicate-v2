extends SceneTree
## Headless progression check:  Godot --headless --path . --script res://tests/test_progression.gd
## The wallet (one-off grants), XP / levels and their rewards, match pay (easy AI = XP only, first win of the day),
## unlocks and prices (free skills, the testing switch, faction vats by wins), challenges (the UTC day / week, progress,
## claim, reroll), saving, result_from_sim and the RewardTicker. Exit code 0 = all passed.

var failures := 0
const P1 := "user://test_progression.cfg"
const P2 := "user://test_progression_tutorial.cfg"


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _init() -> void:
	for p in [P1, P2]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progression.path = P1
	TutorialDirector.path = P2                    # a fresh tutorial save: the Graduate vat is locked
	Progression.unlock_all = false
	Progression.now_override = _unix("2026-09-27T10:00:00")   # a Sunday
	Progression.reload_all()
	_wallet()
	_levels()
	_unlocks()
	_matches()
	_faction_vat()
	_challenges()
	_saving()
	_from_sim()
	_ticker()
	for p in [P1, P2]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("test_progression: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _unix(s: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(s))


func _fresh() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(P1))
	Progression.reload_all()


func _wallet() -> void:
	_fresh()
	check(Progression.balance() == 0 and Progression.balance("premium") == 0, "a fresh wallet is empty")
	check(Progression.grant("tutorial:1", 140), "a first grant pays")
	check(not Progression.grant("tutorial:1", 140), "the same source pays once")
	check(Progression.balance() == 140 and Progression.has_granted("tutorial:1"), "140 SCRAP, source recorded")
	check(not Progression.grant("", 10) and not Progression.grant("x", 0) and not Progression.grant("y", 5, "gold"),
			"bad grants (no source, no amount, unknown currency) pay nothing")
	check(Progression.grant("founder", 50, "premium") and Progression.balance("premium") == 50, "premium grant")
	check(Progression.amount_text(1250) == "+1 250 SCRAP" and Progression.amount_text(-10, "premium") == "-10 CHIPS",
			"amount text: %s / %s" % [Progression.amount_text(1250), Progression.amount_text(-10, "premium")])
	for i in range(2, 10):
		Progression.grant("tutorial:%d" % i, Rules.PROGRESSION["tutorial_lesson"])
	check(Progression.balance() == 9 * 140 and Progression.balance() >= Rules.PRICES["skill"]["soft"],
			"the 9 lessons pay 1 260: a 3rd skill (%d)" % Progression.balance())
	check(Progression.third_skill_line() != "", "the tutorial's 3rd-skill line shows once the SCRAP covers it")


func _levels() -> void:
	_fresh()
	var b: int = Rules.PROGRESSION["level_base"]
	var s: int = Rules.PROGRESSION["level_step"]
	check(Progression.level_for(0)["level"] == 1, "level 1 at 0 XP")
	check(Progression.level_for(b - 1)["level"] == 1 and Progression.level_for(b)["level"] == 2, "level 2 at level_base")
	check(Progression.level_for(b + b + s)["level"] == 3, "level 3 at base + base + step")
	var lines := []
	var xp_to_5 := 0
	for lv in range(1, 5):
		xp_to_5 += b + s * (lv - 1)
	Progression._add_xp(xp_to_5, lines)
	check(Progression.level() == 5 and lines.size() == 4, "four level-ups to level 5 (%d)" % Progression.level())
	check(Progression.balance() == 4 * int(Rules.PROGRESSION["level_soft"]), "each level-up pays level_soft")
	check(Progression.balance("premium") == int(Rules.PROGRESSION["level_premium"]) and lines[3]["premium"] > 0,
			"the 5th level pays a few chips")


func _unlocks() -> void:
	_fresh()
	check(Progression.is_unlocked("skill:surge") and Progression.is_unlocked("skill:demolish"), "Surge + Demolish are free")
	check(Progression.is_unlocked("skill:rewire"), "ultimates come with the faction")
	check(not Progression.is_unlocked("skill:mire") and not Progression.is_unlocked("vat:biopod"), "others are locked")
	check(Progression.is_unlocked("vat:default") and Progression.is_unlocked("machinegoon:default"), "defaults are open")
	check(not Progression.is_unlocked("vat:graduate"), "the Graduate vat waits for the tutorial")
	check(Progression.price("skill:mire") == {"soft": 1250}, "a skill costs 1 250 SCRAP, not sold for chips")
	check(Progression.price("skill:surge").is_empty() and Progression.price("vat:graduate").is_empty()
			and Progression.price("skill:nope").is_empty() and Progression.price("vat:default").is_empty(), "not for sale")
	check(not Progression.price("machinegoon:spitter").is_empty() and not Progression.price("monster:alt:vex").is_empty()
			and not Progression.price("vat:faction:bloom").is_empty(), "structure / monster / faction vat prices")
	Progression.grant("t", 1300)
	check(not Progression.spend("skill:mire", "premium"), "skills are never bought with chips")
	check(Progression.spend("skill:mire") and Progression.is_unlocked("skill:mire") and Progression.balance() == 50,
			"buy Mire: 1 300 - 1 250 = 50")
	check(not Progression.spend("skill:mire"), "an owned skill isn't bought twice")
	check(not Progression.spend("skill:bypass"), "too poor for a second")
	Progression.unlock_all = true
	check(Progression.is_unlocked("vat:biopod") and not Progression.is_unlocked("vat:graduate"),
			"the testing switch opens everything but the Graduate vat")
	check(not Progression.owns("vat:biopod"), "owns() ignores the testing switch")
	Progression.unlock_all = false
	check(Progression.unlock("vat:faction:vex", "campaign:vex") and Progression.is_unlocked("vat:faction:vex"),
			"the campaign unlocks a faction vat")
	check(not Progression.unlock("vat:faction:vex", "campaign:vex"), "unlocked once")
	check(Progression.unlock("vat:graduate", "tutorial") and Progression.is_unlocked("vat:graduate"),
			"the tutorial's unlock call opens the Graduate vat")


func _matches() -> void:
	_fresh()
	var easy := {"faction": "vex", "won": true, "ai_level": "Casual", "stats": {}}
	var r := Progression.record_match(easy)
	check(Progression.balance() == 0, "easy AI pays no SCRAP (%d)" % Progression.balance())
	var P := Rules.PROGRESSION
	check(r["xp_after"] - r["xp_before"] == P["finish_xp"] + P["win_xp"] + P["first_win_xp"], "easy AI still pays XP")
	_fresh()
	var vet := {"faction": "vex", "won": true, "ai_level": "Veteran", "stats": {}}
	r = Progression.record_match(vet)
	check(Progression.balance() == P["finish_soft"] + P["win_soft"] + P["first_win_soft"],
			"a Veteran win pays finish + win + first win (%d)" % Progression.balance())
	check((r["lines"] as Array).size() == 3, "three lines on the result screen")
	var before := Progression.balance()
	Progression.record_match(vet)
	check(Progression.balance() - before == P["finish_soft"] + P["win_soft"], "one first-win bonus per UTC day")
	Progression.now_override += 86400
	var paid := 0
	for l in Progression.record_match(vet)["lines"]:
		if not l.has("level_up"):                   # a level-up line pays its own reward on top
			paid += int(l["soft"])
	check(paid == P["finish_soft"] + P["win_soft"] + P["first_win_soft"], "the next day pays it again (%d)" % paid)
	before = Progression.balance()
	Progression.record_match({"faction": "vex", "won": false, "online": true, "stats": {}})
	check(Progression.balance() - before == P["finish_soft"], "an online loss pays finishing")
	var xp := Progression.xp
	Progression.record_match({"faction": "vex", "won": true, "tutorial": true, "ai_level": "Expert"})
	Progression.record_match({"faction": "vex", "won": true, "left_early": true, "online": true})
	check(Progression.xp == xp, "tutorial lessons and matches left early pay nothing")
	check(Progression.faction_stats("vex")["plays"] == 4, "plays counted per faction")
	Progression.now_override -= 86400


func _faction_vat() -> void:
	_fresh()
	var need: int = Rules.PROGRESSION["faction_vat_wins"]
	for i in need:
		Progression.record_match({"faction": "bloom", "won": true, "ai_level": "Standard", "stats": {}})
	check(not Progression.is_unlocked("vat:faction:bloom"), "wins vs Standard AI don't count toward the vat")
	var got := []
	for i in need:
		got.append_array(Progression.record_match({"faction": "bloom", "won": true, "ai_level": "Expert", "stats": {}})["unlocked"])
	check(Progression.is_unlocked("vat:faction:bloom") and got == ["vat:faction:bloom"],
			"%d Expert wins unlock the BLOOM vat, announced once" % need)
	check(Progression.faction_stats("bloom")["wins"] == 2 * need, "every win counted in wins")


func _challenges() -> void:
	_fresh()
	check(Progression.day_key() == "2026-09-27", "UTC day key")
	check(Progression.week_key() == "2026-09-21" and Progression.week_key(_unix("2026-09-21T00:00:00")) == "2026-09-21"
			and Progression.week_key(_unix("2026-09-28T00:00:00")) == "2026-09-28", "weeks start Monday 00:00 UTC")
	check(Progression.seconds_to_reset("daily") == 14 * 3600, "14 h to the daily reset at 10:00 UTC")
	var a := Progression.current_challenges("daily")
	check(a.size() == Rules.PROGRESSION["daily_count"], "three dailies")
	_fresh()
	var b := Progression.current_challenges("daily")
	check(a.map(func(c): return c["text"]) == b.map(func(c): return c["text"]), "the same day gives the same set")
	Progression.now_override += 86400
	Progression.current_challenges("daily")
	check(Progression.challenges["daily"]["key"] == "2026-09-28", "a new day rolls a new set")
	Progression.now_override -= 86400
	_fresh()
	# make every current daily / weekly finishable by one big match
	var big := {"faction": "vex", "won": true, "ai_level": "Expert", "relay_map": true,
			"stats": {"captures": 200, "relay_fires": 200, "monster_kicked": 999, "skills": 99, "home_lost": false}}
	for kind in ["daily", "weekly"]:
		Progression.current_challenges(kind)
		for ch in Progression.challenges[kind]["list"]:
			if ch.has("faction"):
				ch["faction"] = "vex"
	var done: Array = []
	for i in 10:
		done.append_array(Progression.record_match(big)["challenges"])
	var daily := Progression.current_challenges("daily")
	check(daily.all(func(x): return x["done"]), "every daily done after ten big wins (%s)" % str(daily.map(func(x): return x["id"])))
	check(done.size() == Rules.PROGRESSION["daily_count"] + Progression.current_challenges("weekly").filter(func(x): return x["done"]).size(),
			"each challenge reported done once")
	var soft := Progression.balance()
	var line := Progression.claim("daily", daily[0]["id"])
	check(line.get("soft", 0) == Rules.PROGRESSION["daily_soft"] and Progression.balance() - soft == Rules.PROGRESSION["daily_soft"],
			"a claim pays daily_soft")
	check(Progression.claim("daily", daily[0]["id"]).is_empty(), "claimed once")
	var weekly := Progression.current_challenges("weekly").filter(func(x): return x["done"])
	if not weekly.is_empty():
		var chips := Progression.balance("premium")
		Progression.claim("weekly", weekly[0]["id"])
		check(Progression.balance("premium") - chips == Rules.PROGRESSION["weekly_premium"], "a weekly claim pays a few chips")
	_fresh()
	var first: String = Progression.current_challenges("daily")[0]["id"]
	check(Progression.reroll(first), "a daily reroll")
	check(not first in Progression.current_challenges("daily").map(func(x): return x["id"]), "the rerolled one is gone")
	check(not Progression.reroll(Progression.current_challenges("daily")[1]["id"]), "one reroll a day")


func _saving() -> void:
	_fresh()
	Progression.grant("campaign:vex:04", 150)
	Progression.spend("skill:mire")               # too poor: nothing
	Progression.unlock("vat:faction:ember", "campaign:ember")
	Progression.record_match({"faction": "ember", "won": true, "ai_level": "Veteran", "stats": {"captures": 3}})
	var bal := Progression.balance()
	var xp := Progression.xp
	var ch = Progression.challenges["daily"]["list"].duplicate(true)
	Progression.reload_all()
	check(Progression.saved and Progression.balance() == bal and Progression.xp == xp, "wallet and XP survive a reload")
	check(Progression.has_granted("campaign:vex:04") and not Progression.grant("campaign:vex:04", 150), "grants survive")
	check(Progression.is_unlocked("vat:faction:ember") and Progression.faction_stats("ember")["wins"] == 1, "unlocks and stats survive")
	check(Progression.challenges["daily"]["list"] == ch, "challenge progress survives")
	check(Progression.ledger.size() >= 2, "the ledger keeps recent lines")


func _from_sim() -> void:
	var sim := Sim.new()
	sim.factions = {"A": "solar", "B": "ember", "C": "null", "D": "bloom"}
	sim.homes = {"A": 1, "B": 2}
	sim.teams = {"A": 1, "C": 1, "B": 2, "D": 2}
	sim.has_relays = true
	sim.winner = "C"
	sim.events = [
		{"type": "capture", "node": 5, "seat": "A", "from": ""},
		{"type": "capture", "node": 6, "seat": "A", "from": "B"},
		{"type": "capture", "node": 1, "seat": "B", "from": "A"},
		{"type": "relay_fired", "node": 9, "seat": "A"},
		{"type": "monster_kick", "seat": "A", "seat_hit": "B", "units": Rules.SCALE * 12.0},
		{"type": "skill", "seat": "A", "id": "fortify"},
		{"type": "skill", "seat": "B", "id": "scorch"},
	]
	var r := Progression.result_from_sim(sim, "A", {"ai_level": "Expert"})
	check(r["won"] and r["faction"] == "solar" and r["relay_map"], "a team-mate's win is a win: %s" % str(r))
	var st: Dictionary = r["stats"]
	check(st["captures"] == 2 and st["relay_fires"] == 1 and st["monster_kicked"] == 12 and st["skills"] == 1 and st["home_lost"],
			"stats from the events: %s" % str(st))
	check(not Progression.result_from_sim(sim, "B")["won"], "the other team lost")
	var sb := Progression.seat_stats(sim, "B")
	check(sb["nodes_lost"] == 1 and not sb["home_lost"] and sb["captures"] == 1, "B lost node 6, not its home: %s" % str(sb))
	# the host's extras: a home lost to a Last Stand collapse, relay drops credited to the seat that fired, going out
	sim.events.append_array([
		{"t": 200.0, "type": "collapse", "node": 2, "from": "B"},
		{"t": 210.0, "type": "fall", "seat": "B", "units": Rules.SCALE * 30.0, "why": "relay", "by": "A", "relay": 9},
		{"t": 211.0, "type": "fall", "seat": "A", "units": Rules.SCALE * 5.0, "why": "relay", "by": "A", "relay": 9},
		{"t": 250.0, "type": "eliminated", "seat": "D"},
		{"t": 300.0, "type": "eliminated", "seat": "B"},
		{"t": 20.0, "type": "monster_launch", "seat": "A", "id": 1},
	])
	sb = Progression.seat_stats(sim, "B")
	check(sb["home_lost"] and sb["out_at_s"] == 300.0, "B's home fell in a collapse; out at 300 s: %s" % str(sb))
	var sa := Progression.seat_stats(sim, "A")
	check(sa["void_drops"] == 30 and sa["monster_launches"] == 1 and sa["monster_kicks"] == 1 and sa["out_at_s"] < 0.0,
			"A dropped 30 enemy units (its own 5 don't count): %s" % str(sa))
	var pl := Progression.placements(sim)
	check(pl["A"] == 1 and pl["C"] == 1 and pl["B"] == 2 and pl["D"] == 2, "2v2: the teams place together: %s" % str(pl))
	sim.teams = {}
	sim.winner = "A"
	pl = Progression.placements(sim, {"C": 500.0})
	check(pl["A"] == 1 and pl["C"] == 2 and pl["B"] == 3 and pl["D"] == 4,
			"FFA: winner, survivor, then the later out before the earlier: %s" % str(pl))


func _ticker() -> void:
	var fired := [false]
	var t := RewardTicker.make(140, "soft", func(n): return n * 2.0)
	t.finished.connect(func(): fired[0] = true)
	t.play()
	t._process(0.1)
	check(t._shown > 0 and t._shown < 140, "the count is under way (%d)" % t._shown)
	t._process(2.0)
	check(fired[0] and t._shown == 140, "finished fires on the full amount")
	t._resize()
	check(t.size.x <= 280.0 * 2.0 + 0.1 and t.size.y <= 44.0 * 2.0, "fits 280 x 44 pt (%s)" % str(t.size))
	t.free()
