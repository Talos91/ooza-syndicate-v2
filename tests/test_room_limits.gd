extends SceneTree
## Server room limits (Daniele 2026-09-28): an idle server room closes, with a notice before; one address holds at
## most 2 server rooms. Needs a local relay with a short idle limit and three match slots:
##   python server/relay.py --godot <Godot console exe> --project <this folder> --max-matches 3 --host-arg=--idle-close=20
##   (the empty-room check waits 45 s: it holds for the relay's default --empty-grace 30)
##   Godot --headless --path . --script res://tests/test_room_limits.gd -- --relay=ws://127.0.0.1:8765
## Exit 0 = all passed, 2 = no relay / no match server / no short idle limit there (skipped).

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
	n.test_room = true
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
	## What main._start_online builds on a guest: the room's map, seats and seed, no AI.
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	var teams := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
		if info["mode"] in ["2v2", "3v3", "2v2v2"] and s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), teams, info.get("loadouts", {}))
	return sim


func _fake_main(sim: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()   # not in the tree: guests never run perform()
	m.sim = sim
	return m


func _server_room(faction: String) -> Node:
	var n := _net()
	n.host_room(faction)
	await _wait(func(): return (n.connected and n.room_owner > 0) or n.hosting or n.bridge == null or n.status.contains("rooms open"), 30.0)
	return n


func _run() -> void:
	# --- two rooms from this address, then a third is refused (not a browser fallback)
	var a: Node = await _server_room("null")
	print("relay: ", a.relay_url())
	if not (a.connected and a.room_owner > 0 and not a.hosting):
		print("SKIP  no match server (", a.status, ")")
		quit(2)
		return
	var b: Node = await _server_room("vex")
	check(b.connected and not b.hosting and b.room_code != a.room_code, "a second server room from the same address opens")
	var c: Node = await _server_room("ember")
	check(not c.hosting and not c.connected and c.status.contains("2 rooms"), "a third is refused with the limit: \"%s\"" % c.status)
	c.leave()
	b.leave()
	# --- the idle limit: a notice before, then the room closes and says why
	var notices: Array = []
	a.order_feedback.connect(func(m): notices.append(m))
	var t0 := Time.get_ticks_msec()
	var warned := await _wait(func(): return notices.any(func(m): return str(m).contains("closes in")), 40.0)
	if not warned and (Time.get_ticks_msec() - t0) > 39000:
		print("SKIP  no idle notice within 40 s (start the relay with --host-arg=--idle-close=20)")
		quit(2)
		return
	check(warned, "an idle room warns everyone before it closes: \"%s\"" % (notices.back() if not notices.is_empty() else ""))
	var closed := await _wait(func(): return a.bridge == null, 30.0)
	check(closed and a.status.begins_with("Room closed: nothing was played"), "then it closes and says why: \"%s\"" % a.status)
	check(a.rejoin.is_empty(), "a closed room leaves nothing to RECONNECT to")
	# --- a room with a round running is not idle: covered by test_dedicated / test_rematch (rounds reset the clock)
	# --- 0.22.x (Daniele: "when players leave a room the room needs to close on its own"): the last player leaves a running
	# round (the AI plays on) -> the relay closes the room after its empty grace (30 s; the game's own host would wait 90 s)
	var d: Node = await _server_room("vex")
	d.set_ai_fill("Standard")
	await _wait(func(): return d.ai_fill == "Standard")
	d.start_match()
	var launched := await _wait(func(): return d.active and not d.match_info.is_empty(), 15.0)
	if launched:
		var sd := _build_sim(d.match_info)
		d.world_ready(sd, _fake_main(sd))
	check(launched and await _wait(func(): return d.started, 60.0), "a round with one player and the AI begins")
	var code: String = d.room_code
	d.leave()
	await _wait(func(): return false, 45.0)             # one wait: a probe join meanwhile would count as a player back
	var e := _net()
	e.join_room(code, "null")
	await _wait(func(): return e.bridge == null or e.connected, 15.0)
	check(e.status.begins_with("Room not found"), "the last player left: the relay closed the room (a join finds nothing: \"%s\")" % e.status)
	print("ALL PASSED (0 failures)" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
