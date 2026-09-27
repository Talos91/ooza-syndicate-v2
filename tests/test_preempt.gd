extends SceneTree
## Real players first (0.20.13): with every match slot taken by TEST rooms, a real player's CREATE ROOM stops the oldest
## test room and gets a server room; test rooms never take a slot from a real one. Needs a local relay with ONE slot:
##   python server/relay.py --godot <Godot console exe> --project <this folder> --max-matches 1
##   Godot --headless --path . --script res://tests/test_preempt.gd -- --relay=ws://127.0.0.1:8765
## Exit 0 = all passed, 2 = no match server (skipped).

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


func _run() -> void:
	var t := _net()
	t.test_room = true
	t.host_room("vex")
	if not await _wait(func(): return (t.connected and t.room_owner > 0) or t.hosting or t.bridge == null, 30.0) or t.hosting:
		print("SKIP  no match server: ", t.status)
		quit(2)
		return
	check(t.server_hosted(), "a test room takes the only slot (%s)" % t.room_code)

	var t2 := _net()                                   # another test: no slot, no preemption among tests
	t2.test_room = true
	t2.host_room("bloom")
	check(await _wait(func(): return t2.connected and (t2.hosting or t2.bridge == null), 30.0) and t2.hosting,
			"a second test room falls back to browser hosting (tests never preempt tests)")
	t2.leave()

	var r := _net()                                    # a real player
	r.host_room("ember")
	check(await _wait(func(): return r.connected and r.server_hosted(), 30.0), "a real player's room still gets a server slot (%s)" % r.room_code)
	check(await _wait(func(): return t.bridge == null, 10.0), "the test room was closed for it: " + t.status)

	r.leave()
	await _wait(func(): return false, 1.0)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
