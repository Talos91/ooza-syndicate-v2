extends SceneTree
## REMATCH in a server room (Daniele's 0.20.10 playtest: "it just looks like it reloads and says 1 player ready").
## Needs a local relay whose match hosts end rounds early:
##   python server/relay.py --godot <Godot console exe> --project <this folder> --host-arg=--match-end=15
##   Godot --headless --path . --script res://tests/test_rematch.gd -- --relay=ws://127.0.0.1:8765
## Exit 0 = all passed, 2 = no match server / rounds don't end early (skipped). Covers: both votes count and the next round
## starts; the ready list names who voted; a random-map rematch into a bigger mode fills the extra seat with the AI
## instead of sending the room back to the lobby.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _net() -> Node:
	var n: Node = load("res://scripts/net.gd").new()
	n.no_reload = true
	n.allow_native = true
	root.add_child(n)
	return n


func _wait(cond: Callable, seconds := 10.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _build_sim(info: Dictionary) -> Sim:
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	var teams := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
		if info["mode"] in ["2v2", "3v3", "2v2v2"] and s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), teams, info.get("loadouts", {}))
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()
	m.sim = s
	return m


func _play_round(a: Node, b: Node, round_no: int) -> bool:
	## Load the round on both guests and wait for its (early) end.
	if not await _wait(func(): return a.active and b.active and int(a.match_round) == round_no and int(b.match_round) == round_no, 20.0):
		return false
	var sa := _build_sim(a.match_info)
	var sb := _build_sim(b.match_info)
	a.world_ready(sa, _fake_main(sa))
	b.world_ready(sb, _fake_main(sb))
	await _wait(func(): return a.started and b.started, 60.0)
	return await _wait(func(): return a.finished and b.finished, 45.0)


func _run() -> void:
	var a := _net()
	a.test_room = true                             # a test room: real players may take its slot
	a.host_room("vex")
	if not await _wait(func(): return (a.connected and a.room_owner > 0) or a.hosting or a.bridge == null, 30.0) or a.hosting:
		print("SKIP  no match server: ", a.status)
		quit(2)
		return
	var b := _net()
	b.join_room(a.room_code, "ember")
	await _wait(func(): return b.connected and a.roster.size() == 2)
	b.set_ready(true)                                  # READY (ooze20-net-6): DEPLOY waits for it
	await _wait(func(): return a.all_ready())
	a.start_match()
	if not await _play_round(a, b, 1):
		print("SKIP  round 1 did not end early (start the relay with --host-arg=--match-end=15)")
		quit(2)
		return
	check(true, "round 1 ended (%s)" % a.mode)

	b.request_rematch()                                # the second player first, the way Daniele's girlfriend did
	check(await _wait(func(): return a.rematch_votes.size() == 1 and b.rematch_votes.size() == 1), "one vote reaches both players")
	var sa: Dictionary = a.rematch_status()
	var sb: Dictionary = b.rematch_status()
	check(not sa["mine"] and sb["mine"] and (sa["ready"] as Array).size() == 1 and (sa["waiting"] as Array).size() == 1,
			"the ready list names who voted: ready %s, waiting %s" % [str(sa["ready"]), str(sa["waiting"])])
	a.request_rematch()
	check(await _wait(func(): return int(a.match_round) == 2 and int(b.match_round) == 2 and a.active and not a.finished, 15.0),
			"both votes count: round 2 starts for both")
	check(await _play_round(a, b, 2), "round 2 ended")

	var ffa := ""
	for p in a.maps_for("FFA3"):
		ffa = p
		break
	a.propose_rematch(ffa, "FFA3")                     # the owner's REMATCH ON A RANDOM MAP picked a 3-seat mode
	b.request_rematch()
	check(await _wait(func(): return int(a.match_round) == 3 and a.active, 15.0),
			"a random map for more seats than players still starts (no fall back to the lobby)")
	check(a.mode == "FFA3" and (a.match_info.get("ai", {}) as Dictionary).size() == 1 and a.match_info["ai"].values()[0] == "Standard",
			"the extra seat is AI (%s, ai %s)" % [a.mode, str(a.match_info.get("ai", {}))])

	a.leave()
	b.leave()
	await _wait(func(): return false, 1.0)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
