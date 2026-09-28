extends SceneTree
## The server's match result report (0.20.5, PROGRESSION-DESIGN §7a), offline: the payload from a finished Sim and the
## HMAC signature the edge function checks. Godot --headless --path . --script res://tests/test_match_report.gd

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _sim(path: String, mode: String, players: Dictionary) -> Sim:
	var map := MapBuilder.load_map(path)
	var seats := {}
	for s in map["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, players, 7, {}, {})
	return sim


func _run() -> void:
	# the signature, checked against Python's hmac (hmac.new(b"test-secret", b'1790000000.{"a":1}', sha256))
	check(MatchReport.sign("test-secret", 1790000000, "{\"a\":1}") == "e3e163d823c523325543883cf24137c2d1c65f9f82a34c639ea861da63349074",
			"x-ooze-sig = hex HMAC-SHA256(secret, ts + \".\" + body)")
	check(MatchReport.map_code("res://maps4/M-07-twin-docks.json") == "M-07" and MatchReport.map_code("res://maps4/A-01-orbital-nexus.json") == "A-01",
			"map codes from map paths")

	var path := ""
	for p in MapPool.battlefield():
		if MapBuilder.load_map(p).get("seats", {}).has("FFA3"):
			path = p
			break
	var sim := _sim(path, "FFA3", {"A": "vex", "B": "bloom", "C": "ember"})
	for i in range(200):                               # a few seconds of play so the counters exist
		sim.step(0.05)
	sim.over = true
	sim.winner = "B"
	sim.events.append({"t": sim.time, "type": "end", "winner": "B"})
	var info := {"map": path, "mode": "FFA3", "ai": {"C": "Standard"}, "rules": {"last_stand": true, "abilities_on": false}}
	var r := MatchReport.payload(sim, info, {"A": "uuid-a", "B": "uuid-b"}, {"A": true}, "WXYZ", 2, 1790000000)
	check(r["v"] == 1 and r["match_id"] == "WXYZ-2-1790000000" and r["build"] == Rules.VERSION, "version, match_id (room-round-start), build")
	check(r["map"] == MatchReport.map_code(path) and r["mode"] == "ffa3", "map code and mode (lower case)")
	check(r["rules"] == {"last_stand": true, "abilities": false}, "rules")
	check(r["outcome"]["winner_seat"] == "B" and r["outcome"]["end"] == "win" and not r["outcome"]["draw"], "outcome: B wins")
	var by := {}
	for st in r["seats"]:
		by[st["seat"]] = st
	check(by.size() == 3 and by["A"]["user_id"] == "uuid-a" and by["C"]["user_id"] == null, "every seat, user ids only where verified")
	check(by["C"]["ai_level"] == "Standard" and by["A"]["ai_level"] == null and by["B"]["ai_level"] == null, "ai_level for AI seats only")
	check(by["A"]["left_early"] and not by["B"]["left_early"], "left_early")
	check(by["B"]["won"] and not by["A"]["won"] and not by["C"]["won"], "won: only the winning seat")
	check(by["B"]["placed"] == 1 and by["A"]["placed"] > 1 and by["C"]["placed"] > 1, "placed: the winner first")
	var keys := ["captures", "sends", "void_drops", "relay_fires", "monster_launches", "monster_kicks", "nodes_lost", "home_lost",
			"units_lost_combat", "units_lost_falls", "out_at_s"]
	check(keys.all(func(k): return (by["A"]["stats"] as Dictionary).has(k)), "stats carry every §7a counter (Progression.seat_stats)")
	check(by["A"].has("final_strength") and by["A"].has("final_nodes") and by["A"]["faction"] == "vex", "final strength, nodes, faction")
	# UI (Alpha 21): MATCH DETAILS reads the same counters (MatchScreens.seat_table), you first, a column per seat
	var tb := MatchScreens.seat_table(sim, "A")
	check((tb["cols"] as Array).map(func(c): return c["seat"]) == ["A", "B", "C"] and tb["cols"][0]["head"] == "YOU"
			and tb["cols"][1]["head"] == "RIVAL 1", "MATCH DETAILS: you first, then each rival")
	var rows := {}
	for row in tb["rows"]:
		rows[row[0]] = row[1]
	check(rows.has("Captures") and int(rows["Captures"][0]) == int(by["A"]["stats"]["captures"]), "MATCH DETAILS: captures = seat_stats")
	check(rows.has("Placement") and rows["Placement"][1] == "1st", "MATCH DETAILS: FFA placements, the winner 1st")
	check(rows.has("Skills used") == sim.abilities_on, "MATCH DETAILS: a skills row only with ABILITIES on")
	check(tb["rows"].all(func(row): return (row[1] as Array).size() == 3), "MATCH DETAILS: a value per seat in every row")
	var body := JSON.stringify(r)
	check(JSON.parse_string(body) is Dictionary and body.length() < 16000, "serialises to JSON (%d bytes)" % body.length())

	sim.events.append({"t": sim.time, "type": "end", "winner": "", "forced": true, "draw": true})
	sim.winner = ""
	var d := MatchReport.outcome(sim)
	check(d["draw"] and d["end"] == "draw" and d["winner_seat"] == null, "a 7:00 draw")
	sim.winner = "A"
	sim.events.append({"t": sim.time, "type": "end", "winner": "A", "forced": true})
	check(MatchReport.outcome(sim)["end"] == "forced", "a forced 7:00 win")

	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
