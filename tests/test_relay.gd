extends SceneTree
## Room-server check (Alpha 20): real Net instances talk through a running server/relay.py.
##   python server/relay.py            (in another shell; or point at the live one)
##   Godot --headless --path . --script res://tests/test_relay.gd -- --relay=ws://127.0.0.1:8765
## Exit code 0 = all passed, 2 = the relay was unreachable (skipped). Covers: open a room, join by code,
## register + lobby, chat both ways (the base64 envelopes), a wrong code, a guest leaving, the host leaving,
## and CREATE ROOM (a server room, or hosting here when the relay has no match server).

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


func _wait(cond: Callable, seconds := 8.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	var host := _net()
	print("relay: ", host.relay_url())
	host.server_rooms = false                          # these rooms are hosted by a player (stage 1; stage 2: test_dedicated)
	host.host_room("null")
	if not await _wait(func(): return host.room_code != "" or host.bridge == null):
		print("SKIP  relay unreachable: ", host.status)
		quit(2)
		return
	check(host.room_code.length() == 4 and host.connected, "host opens room %s" % host.room_code)

	var guest := _net()
	guest.join_room(host.room_code, "vex")
	check(await _wait(func(): return guest.connected and host.roster.size() == 2), "guest joins and is seated")
	check(guest.roster.size() == 2 and str(guest.roster.get(guest.local_id(), {}).get("faction", "")) == "vex",
			"guest sees the lobby with its faction")

	guest.send_chat("hello from the guest")
	check(await _wait(func(): return host.chat_history.size() == 1 and guest.chat_history.size() == 1),
			"guest chat reaches the host and comes back")
	host.send_chat("hello from the host")
	check(await _wait(func(): return guest.chat_history.size() == 2), "host chat reaches the guest")

	var bad := _net()
	bad.join_room("ZZZZ", "null")
	check(await _wait(func(): return bad.bridge == null and bad.status.contains("not found")), "a wrong code is refused: " + bad.status)

	guest.leave()
	check(await _wait(func(): return host.roster.size() == 1), "a leaving guest frees the seat")

	var second := _net()
	second.join_room(host.room_code, "bloom")
	check(await _wait(func(): return second.connected), "a new guest joins the same room")
	host.leave()
	check(await _wait(func(): return second.bridge == null), "the host leaving closes the room for guests: " + second.status)

	var c := _net()                                    # CREATE ROOM: a server room, or (no match server) this game hosts
	c.host_room("ember")
	check(await _wait(func(): return c.connected and (c.hosting or c.can_control()), 30.0),
			"CREATE ROOM works either way: %s" % ("fell back to hosting here" if c.hosting else "server-hosted room " + c.room_code))
	c.leave()

	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
