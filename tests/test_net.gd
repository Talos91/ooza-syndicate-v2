extends SceneTree
## Headless room / netcode check:  Godot --headless --path . --script res://tests/test_net.gd
## Exit code 0 = all passed. A host Net and guest Nets talk through fake transports that carry the
## real envelopes (JSON + base64 + deflate), so lobby, seats, validation, snapshots, rematch and
## chat are exercised exactly as in the browser - only PeerJS itself is missing.

class FakeBridge:
	extends RefCounted
	var sent: Array = []                  # [remote, raw string]
	var closed_peers: Array = []
	func start(_host, _code) -> void: pass
	func send(remote, data) -> bool:
		sent.append([str(remote), str(data)])
		return true
	func close() -> void: pass
	func closePeer(remote) -> void: closed_peers.append(remote)
	func poll() -> String: return "[]"

var failures := 0
var host: Node
var guests := {}                          # remote name -> guest Net


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _new_net() -> Node:
	var n: Node = load("res://scripts/net.gd").new()
	n.no_reload = true
	n.bridge = FakeBridge.new()
	root.add_child(n)
	return n


func _open_room(mode: String) -> void:
	for g in guests.values():
		g.queue_free()
	guests = {}
	if host:
		host.queue_free()
	host = _new_net()
	host.hosting = true
	host.connected = true
	host.room_code = "AB7K"
	host.mode = mode
	host.map_path = host.maps_for(mode)[0]
	host.roster = {1: {"faction": "vex", "slot": 0}}


func _join(remote: String, faction := "null", version := "") -> Node:
	var g := _new_net()
	g.remote_host = "host"
	g.room_code = "AB7K"
	guests[remote] = g
	host.links[remote] = host.next_peer
	host.next_peer += 1
	_to_host(remote, {"op": "register", "version": version if version != "" else host.version(), "faction": faction})
	return g


func _to_host(remote: String, packet: Dictionary) -> void:
	host._host_receive(remote, JSON.stringify(packet))


func _deliver() -> void:
	## Host -> guests: every envelope the host sent, through the guest's real decoder; then any
	## guest -> host packets back through the host's real validator.
	for i in range(3):
		var out: Array = host.bridge.sent
		host.bridge.sent = []
		for p in out:
			if guests.has(p[0]):
				guests[p[0]]._guest_receive(p[1])
		for remote in guests:
			var g: Node = guests[remote]
			if g.bridge == null:
				continue
			var back: Array = g.bridge.sent
			g.bridge.sent = []
			for q in back:
				host._host_receive(remote, q[1])


func _kinds_to(remote: String) -> Array:
	return host.bridge.sent.filter(func(p): return p[0] == remote).map(func(p): return JSON.parse_string(p[1])["kind"])


func _build_sim(info: Dictionary) -> Sim:
	## What main._start_online builds: the room's map, seats and seed, no AI.
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	var teams := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
		if info["mode"] == "2v2" and s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), teams)
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()   # not in the tree: perform() needs only sim
	m.sim = s
	return m


func _run() -> void:
	# ---------------------------------------------------------------- lobby, every mode
	for mode in ["1v1", "FFA3", "FFA4", "FFA5", "2v2"]:
		_open_room(mode)
		for i in range(1, host.slots()):
			_join("g%d" % i, ["null", "ember", "bloom", "solar"][i - 1])
		_deliver()
		check(host.roster.size() == host.slots(), mode + ": every seat filled")
		var seats := {}
		for id in host.roster:
			seats[host.seat_of(id)] = true
		check(seats.size() == host.slots(), mode + ": distinct seats A..")
		check(host.can_start(), mode + ": host can deploy")
		var g1: Node = guests["g1"]
		check(g1.assigned_id == 2 and g1.local_seat() == "B", mode + ": first guest is seat B")
		check(g1.connected and g1.roster.size() == host.slots() and g1.mode == mode and g1.map_path == host.map_path, mode + ": guest sees the lobby")
		var extra := _join("late")
		_deliver()
		check(extra.bridge == null and not host.roster.has(host.links["late"]), mode + ": a full room rejects a sixth player")
		guests.erase("late")
		extra.queue_free()
		if mode == "2v2":
			check(host.team_of_slot(0) == host.team_of_slot(1) and host.team_of_slot(0) != host.team_of_slot(2), "2v2: A+B against C+D")

	# ---------------------------------------------------------------- version check, faction change
	_open_room("1v1")
	_join("old", "null", "ooze20-net-0/0.0.1")
	check("rejected" in _kinds_to("old") and host.roster.size() == 1, "a different game version is rejected")
	guests.erase("old")
	var g := _join("g1", "ember")
	_deliver()
	_to_host("g1", {"op": "faction", "faction": "solar"})
	_deliver()
	check(host.roster[g.assigned_id]["faction"] == "solar" and g.roster[g.assigned_id]["faction"] == "solar", "a guest changes faction in the lobby")
	_to_host("g1", {"op": "faction", "faction": "pirates"})
	check(host.roster[g.assigned_id]["faction"] == "solar", "unknown factions are ignored")
	host.set_mode("FFA3")
	check(host.mode == "FFA3" and not host.can_start(), "host widens the room; deploy waits for the new seat")
	host.set_mode("1v1")
	check(host.can_start(), "back to 1v1")

	# ---------------------------------------------------------------- launch and the loading barrier
	host.map_path = "res://maps/004-two-piers.json"
	host.start_match()
	var info: Dictionary = host.match_info
	check(host.active and int(info["round"]) == 1 and info["players"].size() == 2, "launch: round 1 with both players")
	_deliver()
	check(g.active and g.match_round == 1 and g.match_info["seed"] == info["seed"], "guest receives the launch (same seed)")
	var hs := _build_sim(info)
	var gs := _build_sim(g.match_info)
	host.world_ready(hs, _fake_main(hs))
	check(not host.started, "host waits for every player to load")
	g.world_ready(gs, null)
	_deliver()
	check(host.started and g.started, "everyone loaded: the round begins on both")
	check(hs.nodes.size() == gs.nodes.size() and hs.homes == gs.homes, "both browsers built the same map")

	# ---------------------------------------------------------------- orders, validated by the host
	var home_b: int = hs.homes["B"]
	var home_a: int = hs.homes["A"]
	var target: int = hs.adj[home_b][0][0]
	_to_host("g1", {"op": "order", "round": 1, "action": "send", "a": home_b, "args": {"to": target, "fraction": 1.0}})
	check(hs.hordes.size() == 1 and hs.hordes[0]["owner"] == "B", "guest's send runs on the host for seat B")
	check("feedback" in _kinds_to("g1"), "the host answers the order with a feedback line")
	_to_host("g1", {"op": "order", "round": 1, "action": "send", "a": home_a, "args": {"to": target, "fraction": 1.0}})
	check(hs.hordes.size() == 1, "sending from someone else's node is refused")
	_to_host("g1", {"op": "order", "round": 0, "action": "send", "a": home_b, "args": {"to": target, "fraction": 1.0}})
	_to_host("g1", {"op": "order", "round": 1, "action": "nuke", "a": home_b, "args": {}})
	_to_host("g1", {"op": "order", "round": 1, "action": "send", "a": home_b, "args": {"to": target, "fraction": 7.0}})
	_to_host("g1", {"op": "order", "round": 1, "action": "send", "a": 1.5, "args": {"to": target, "fraction": 1.0}})
	check(hs.hordes.size() == 1, "stale round, unknown action, bad fraction, bad id: all refused")
	_to_host("g1", {"op": "order", "round": 1, "action": "upgrade", "a": home_a, "args": {}})
	check(hs.nodes[home_a]["build_kind"] == "", "a guest can't upgrade the host's node")
	var r: Array = host.main.perform("A", "recall", hs.hordes[0]["id"])
	check(not r[0], "recall checks the line's owner")
	host.bridge.sent = []
	_deliver()

	# ---------------------------------------------------------------- snapshots
	for i in range(60):                              # 3 s: the line is out on the deck
		hs.step(0.05)
	var snap: Dictionary = host.snapshot(hs, true)
	var wire: PackedByteArray = var_to_bytes(snap).compress(FileAccess.COMPRESSION_DEFLATE)
	print("      keyframe snapshot: %d bytes compressed" % wire.size())
	host._broadcast_raw("state", wire)
	_deliver()
	check(gs.hordes.size() == 1 and gs.hordes[0]["owner"] == "B", "guest sees the host's horde")
	check(absf(gs.hordes[0]["s"] - hs.hordes[0]["s"]) < 0.001 and absf(gs.time - hs.time) < 0.001, "guest line and clock match the host")
	var same := true
	for i in range(hs.nodes.size()):
		same = same and hs.nodes[i]["owner"] == gs.nodes[i]["owner"] and absf(hs.nodes[i]["units"] - gs.nodes[i]["units"]) < 0.001
	check(same, "guest node owners and counts match the host")
	check((gs.hordes[0]["pts"] as PackedVector3Array) == (hs.hordes[0]["pts"] as PackedVector3Array), "keyframe carries the path")
	var head_host: Vector3 = Sim.sample(hs.hordes[0], hs.hordes[0]["s"])[0]
	var head_guest: Vector3 = Sim.sample(gs.hordes[0], gs.hordes[0]["s"])[0]
	check(head_host.distance_to(head_guest) < 0.01, "guest draws the head where the host has it")
	for i in range(30):                              # 1.5 s later: path unchanged, so it stays home
		hs.step(0.05)
	var lean: Dictionary = host.snapshot(hs, false)
	check(not (lean["hordes"][0] as Dictionary).has("pts"), "an unchanged path is not re-sent")
	check(var_to_bytes(lean).compress(FileAccess.COMPRESSION_DEFLATE).size() < wire.size(), "a lean snapshot is smaller than a keyframe")
	host.apply_snapshot(gs, lean)
	check((gs.hordes[0]["pts"] as PackedVector3Array).size() > 0 and absf(gs.hordes[0]["s"] - hs.hordes[0]["s"]) < 0.001, "guest keeps its path and follows the line")
	var s0: float = gs.hordes[0]["s"]
	host.predict(gs, 0.1)
	check(gs.hordes[0]["s"] > s0 or gs.hordes[0]["state"] != "move", "prediction moves the line between snapshots")
	var captured := []
	gs.captured.connect(func(id, o, _p): captured.append([id, o]))
	var t := 0.0
	while hs.nodes[target]["owner"] != "B" and t < 60.0:
		hs.step(0.05)
		t += 0.05
	host.apply_snapshot(gs, host.snapshot(hs, false))
	check(gs.nodes[target]["owner"] == "B" and captured.size() >= 1 and captured[-1] == [target, "B"], "a capture on the host fires `captured` on the guest")
	host.push_effects([{"type": "cannon", "node": target}])
	_deliver()
	check(gs.fx_events.any(func(e): return e.get("type", "") == "cannon"), "host effects reach the guest's view queue")

	# ---------------------------------------------------------------- chat
	check(host.accept_chat(1, "  hello <b>there</b>\u0007 "), "host chats")
	check(host.chat_history[-1]["text"] == "hello <b>there</b>" and host.chat_history[-1]["who"] == "A · VEX", "chat is cleaned and stamped with the seat")
	check(not host.accept_chat(1, "again"), "chat rate limit: 0.7 s between messages")
	check(not host.accept_chat(1, "   "), "empty chat is dropped")
	_to_host("g1", {"op": "chat", "text": "x".repeat(400)})
	_deliver()
	check(g.chat_history.size() == 2 and str(g.chat_history[-1]["text"]).length() == 256 and g.chat_history[-1]["seat"] == "B", "guest chat: 256 chars, host-assigned sender, history on the guest")
	for i in range(60):
		host._chat_limits = {}
		host.accept_chat(1, "m%d" % i)
	check(host.chat_history.size() == 50, "chat keeps 50 messages")

	# ---------------------------------------------------------------- the end, rematch
	hs.over = true
	hs.winner = "A"
	host._process(0.2)
	_deliver()
	check(host.finished and g.finished and gs.over and gs.winner == "A", "the end reaches the guest")
	host.request_rematch()
	check(host.match_round == 1 and host.rematch_votes.size() == 1, "one vote is not enough")
	_deliver()
	check(g.rematch_votes.size() == 1, "guest sees the vote count")
	g.request_rematch()
	_deliver()
	check(host.match_round == 2 and g.match_round == 2 and host.active and not host.started, "everyone accepted: round 2 in the same room")
	check(host.room_code == "AB7K" and g.chat_history.size() > 0, "room code and chat survive the rematch")
	_to_host("g1", {"op": "order", "round": 1, "action": "send", "a": home_b, "args": {"to": target, "fraction": 1.0}})
	check(not ("feedback" in _kinds_to("g1")), "orders from the old round are ignored")

	# ---------------------------------------------------------------- departures
	var hs2 := _build_sim(host.match_info)
	host.world_ready(hs2, _fake_main(hs2))
	g.world_ready(_build_sim(g.match_info), null)
	_deliver()
	check(host.started, "round 2 begins")
	host.peer_left(g.assigned_id)
	_deliver()
	check(not host.active and host.roster.size() == 1 and host.in_room(), "a guest leaving mid-match returns the host to the lobby")
	_open_room("FFA3")
	var q1 := _join("g1")
	var q2 := _join("g2")
	_deliver()
	host.start_match()
	_deliver()
	var hs3 := _build_sim(host.match_info)
	host.world_ready(hs3, _fake_main(hs3))
	q1.world_ready(_build_sim(q1.match_info), null)
	q2.world_ready(_build_sim(q2.match_info), null)
	_deliver()
	check(host.started and q2.started, "FFA3 round begins for three")
	host.peer_left(2)
	_deliver()
	check(not q2.active and q2.in_room() and q2.roster.size() == 2, "the other players are sent back to the lobby too")
	check(host.roster.size() == 2 and host.seat_of(3) == "B", "seats repack after a lobby departure")
	var gg: Node = guests["g2"]
	gg.fail("The host left or the connection was lost. The room is closed.")
	check(not gg.in_room() and gg.status.begins_with("The host left"), "host departure closes the room for a guest")

	print("\nALL PASSED (0 failed)" if failures == 0 else "\n%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
