extends SceneTree
## Server-hosted rooms (Alpha 20 stage 2): the room server starts a headless match host; two players join.
##   python server/relay.py --godot <Godot console exe> --project <this folder>     (another shell)
##   Godot --headless --path . --script res://tests/test_dedicated.gd -- --relay=ws://127.0.0.1:8765
## Exit 0 = all passed, 2 = no relay or no match server there (skipped). Covers: CREATE ROOM -> a server room
## with the creator as owner, a second player, owner-only lobby changes, DEPLOY, the loading barrier, snapshots
## from the server's Sim, an order answered, the owner dropping (the next player runs the room), an empty lobby closing.

var failures := 0
var feedback: Array = []


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
	## What main._start_online builds on a guest: the room's map, seats and seed, no AI.
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
	var m: Node3D = load("res://scripts/main.gd").new()   # not in the tree: guests never run perform()
	m.sim = s
	return m


func _run() -> void:
	var a := _net()
	print("relay: ", a.relay_url())
	a.test_room = true                             # a test room: real players may take its slot
	a.player_name = "Alice"
	a.host_room("null")
	var up := await _wait(func(): return (a.connected and a.room_owner > 0) or a.hosting or a.bridge == null, 30.0)
	if not up or a.hosting:
		print("SKIP  no match server (", a.status, ")")
		quit(2)
		return
	check(not a.hosting and a.room_code.length() == 4, "CREATE ROOM opens a server-hosted room %s" % a.room_code)
	check(a.can_control() and a.room_owner == a.assigned_id and a.roster.size() == 1, "the creator is the room owner, alone in the room")
	check(str(a.roster.get(a.assigned_id, {}).get("faction", "")) == "null" and a.local_seat() == "A", "the owner holds seat A")

	var b := _net()
	b.player_name = "Bob"                          # NAMES (net-7): what the ACCOUNT's name would be
	b.join_room(a.room_code, "vex")
	check(await _wait(func(): return b.connected and a.roster.size() == 2), "a second player joins")
	check(a.name_of(b.assigned_id) == "Bob" and b.name_of(a.assigned_id) == "Alice", "NAMES: each player sees the other's name")
	check(not b.can_control() and b.room_owner == a.assigned_id, "the second player sees the owner, and has no controls")
	check(a.server_hosted() and b.server_hosted(), "both players know the room is server-hosted (ranked)")

	b.set_mode("FFA3")
	await _wait(func(): return false, 1.0)
	check(a.mode == "1v1" and b.mode == "1v1", "a non-owner's lobby change is ignored")
	a.set_mode("FFA3")
	check(await _wait(func(): return a.mode == "FFA3" and b.mode == "FFA3"), "the owner changes the mode for everyone")
	check(not a.can_start(), "FFA 3 with two players cannot DEPLOY")
	a.set_mode("1v1")
	var ls: bool = a.last_stand
	a.toggle_last_stand()
	check(await _wait(func(): return a.mode == "1v1" and a.last_stand != ls and b.last_stand != ls), "the owner toggles LAST STAND")

	check(not a.can_start(), "READY: DEPLOY waits for the second player's READY")
	b.set_ready(true)
	check(await _wait(func(): return a.is_ready(b.assigned_id) and a.can_start()), "the second player presses READY: DEPLOY opens")
	b.set_faction("solar")
	b._send_to_host({"op": "faction", "faction": "solar"})
	await _wait(func(): return false, 1.0)
	check(str(a.roster[b.assigned_id]["faction"]) == "vex" and b.ready_locked(), "the server locks a READY player's faction")
	check(a.can_start() and not b.can_start(), "the room is full: only the owner may DEPLOY")
	a.start_match()
	check(await _wait(func(): return a.active and b.active and not a.match_info.is_empty(), 15.0), "DEPLOY launches the round on both")
	var sa := _build_sim(a.match_info)
	var sb := _build_sim(b.match_info)
	a.world_ready(sa, _fake_main(sa))
	b.world_ready(sb, _fake_main(sb))
	check(await _wait(func(): return a.started and b.started, 60.0), "the server's match host loads, and the round begins")
	check(await _wait(func(): return sa.time > 2.0 and sb.time > 2.0, 20.0), "snapshots from the server's Sim arrive (t = %.1f s)" % sa.time)

	b.order_feedback.connect(func(m): feedback.append(m))
	var mine := -1
	for i in range(sb.nodes.size()):
		if str(sb.nodes[i].get("owner", "")) == b.local_seat():
			mine = i
	b.order("upgrade", mine)
	check(await _wait(func(): return not feedback.is_empty(), 5.0), "an order is answered by the server: %s" % str(feedback))
	var line: String = b.net_stats_line()              # the PAUSE panel's connection line
	check(b._rtt_ms > 0.0 and b._arrivals.size() >= 10 and line.contains("updates/s") and line.contains("round trip"),
			"the connection line has real numbers: " + line)
	var ns: Dictionary = b.round_net_stats()               # NET: the round's totals the match telemetry carries
	check(float(ns.get("hz", 0.0)) > 10.0 and int(ns.get("rtt_ms", -1)) >= 0 and ns.has("gap_max_ms") and bool(ns.get("server_hosted", false)),
			"NET: the guest's round network totals are filled: %s" % str(ns))

	var t_before: float = sb.time
	a.leave()                                          # the owner drops out mid-match
	check(await _wait(func(): return b.can_control(), 8.0), "the owner drops: the next player runs the room")
	check(await _wait(func(): return sb.time > t_before + 1.5, 8.0), "the match keeps running on the server without the owner")

	b.leave()

	var c := _net()                                    # an empty lobby frees its match host at once (0.20.1)
	c.test_room = true                             # a test room: real players may take its slot
	c.host_room("bloom")
	var code := ""
	if await _wait(func(): return c.connected and c.can_control(), 30.0):
		code = c.room_code
	c.leave()
	await _wait(func(): return false, 8.0)             # DEDICATED_LOBBY_IDLE 5 s, then the relay drops the room
	var d := _net()
	d.join_room(code, "ember")
	check(code != "" and await _wait(func(): return d.bridge == null and d.status.contains("not found"), 10.0),
			"an empty lobby closes within seconds: " + d.status)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
