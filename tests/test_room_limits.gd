extends SceneTree
## Server room limits (Daniele 2026-09-28): an idle server room closes, with a notice before; one address holds at
## most 2 server rooms. Needs a local relay with a short idle limit and three match slots:
##   python server/relay.py --godot <Godot console exe> --project <this folder> --max-matches 3 --host-arg=--idle-close=20
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
	print("ALL PASSED (0 failures)" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
