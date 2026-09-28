extends SceneTree
## Accounts end-to-end (0.20.5): a server room where one player carries a Supabase token, played to its end, so the
## match host verifies the token at join and posts the signed match-result report. Not a pass/fail test: check the
## match host's log on the server ("seat of player ...", "match report 200 ...").
##   Godot --headless --path . --script res://tests/accounts_probe.gd -- --relay=<url> --auth-file=<token file>

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
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), {}, info.get("loadouts", {}))
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()
	m.sim = s
	return m


func _run() -> void:
	Engine.max_fps = 30
	var token := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auth-file="):
			token = FileAccess.get_file_as_string(arg.substr(12)).strip_edges()
	var a := _net()
	a.auth_token = token
	a.test_room = true                             # a test room: real players may take its slot
	a.host_room("vex")
	if not await _wait(func(): return (a.connected and a.room_owner > 0) or a.hosting or a.bridge == null, 30.0) or a.hosting:
		print("no server room: ", a.status)
		quit(2)
		return
	var b := _net()
	b.join_room(a.room_code, "ember")
	await _wait(func(): return b.connected and a.roster.size() == 2)
	print("room %s: player A signed in (token %d chars), player B a plain guest" % [a.room_code, token.length()])
	b.set_ready(true)                                  # READY (ooze20-net-6): DEPLOY waits for it
	await _wait(func(): return a.all_ready())
	a.start_match()
	await _wait(func(): return a.active and b.active and not a.match_info.is_empty(), 15.0)
	var sa := _build_sim(a.match_info)
	var sb := _build_sim(b.match_info)
	a.world_ready(sa, _fake_main(sa))
	b.world_ready(sb, _fake_main(sb))
	await _wait(func(): return a.started and b.started, 60.0)
	print("round started on %s; nobody plays - waiting for the 7:00 end" % a.map_path.get_file())
	var ok := await _wait(func(): return sa.over, 8.0 * 60.0)
	print("round over: %s, winner '%s' at %.1f s" % [ok, sa.winner, sa.time])
	await _wait(func(): return false, 5.0)
	a.leave()
	b.leave()
	await _wait(func(): return false, 1.0)
	quit(0)
