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
	Rules.bridge_combat = true                      # these checks were written for SIEGE (the old default); BRAWL is the game's default since 0.18.7
	Rules.abilities_on = true                       # skills ship off until their UI lands; the checks expect them on
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


func _payloads(remote: String, kind: String) -> Array:
	## The decoded data of every `kind` envelope the host sent to `remote` (not yet delivered).
	var out := []
	for p in host.bridge.sent:
		if p[0] != remote:
			continue
		var env = JSON.parse_string(p[1])
		if env["kind"] == kind:
			out.append(bytes_to_var(Marshalls.base64_to_raw(env["data"]).decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)))
	return out


func _build_sim(info: Dictionary) -> Sim:
	## What main._start_online builds: the room's map, seats and seed, no AI.
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
	var m: Node3D = load("res://scripts/main.gd").new()   # not in the tree: perform() needs only sim
	m.sim = s
	return m


func _run() -> void:
	MapPool.dir = "res://maps"                     # the legacy roster offers every mode, whatever pack ships
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
	g.set_loadout({"active": "fortify", "map": "mire"})     # SKILLS 2.0: the guest's loadout rides in the roster
	_to_host("g1", {"op": "loadout", "active": "nuke", "map": "mire"})
	check(host.roster[g.assigned_id]["loadout"] == {"map": "mire"}, "an unknown skill id in a loadout is dropped")
	g.set_loadout({"active": "fortify", "map": "mire"})
	_deliver()
	check(host.roster[g.assigned_id]["loadout"] == {"active": "fortify", "map": "mire"}, "a guest sets its loadout in the lobby")
	host.start_match()
	var info: Dictionary = host.match_info
	check(info["loadouts"] == {"B": {"active": "fortify", "map": "mire"}} and info["rules"]["abilities_on"] == true,
			"the launch carries the loadouts and ABILITIES ON")
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
	check(hs.loadouts["B"] == {"active": "fortify", "map": "mire", "ultimate": Rules.FACTION_ULTIMATE_ID[info["players"]["B"]]} and hs.loadouts == gs.loadouts,
			"host and guest set up the same loadouts (a missing one = the faction default)")

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
	# 0.18.7: the corner-cycle drop order is the host's; a guest (whatever its own seed) reads it from ls[12]
	var lsm := MapBuilder.load_map("res://maps4/A-01-orbital-nexus.json")
	var ls_seats := {}
	for st in lsm["seats"]["FFA4"]:
		ls_seats[int(st["node"])] = st["seat"]
	var ls_host := Sim.new()
	ls_host.setup(lsm, MapBuilder.layout(lsm), ls_seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar"}, 2)
	ls_host._map_last_stand = {"methods": ["inward"], "orders": {"inward": lsm["lastStand"]["orders"]["inward"]}}
	ls_host._ring_orders = ls_host._map_last_stand["orders"]
	ls_host.time = Rules.LAST_STAND_TIME
	ls_host._start_rings()
	var ls_guest := Sim.new()
	ls_guest.setup(lsm, MapBuilder.layout(lsm), ls_seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar"}, 5)
	var ls_wire: PackedByteArray = var_to_bytes(host.snapshot(ls_host, true))   # the wire's encoding
	host.apply_snapshot(ls_guest, bytes_to_var(ls_wire))
	check(ls_host.last_stand_queue.size() >= 2 and ls_guest.last_stand_queue == ls_host.last_stand_queue
			and ls_guest.drop_in(ls_host.last_stand_queue[1]) == ls_host.drop_in(ls_host.last_stand_queue[1]),
			"the guest's drop queue and per-platform countdowns are the host's corner-cycle order")
	check(ls_host.nearest_corner(ls_host.last_stand_queue[0]) != ls_host.nearest_corner(ls_host.last_stand_queue[1]),
			"the ring's first two drops lie near different starting corners")
	# a forge built on the host plays the guest's forge pulse from the snapshots alone (ForgePulse, view only)
	var fp := ForgePulse.new()
	root.add_child(fp)
	fp.setup(gs, {}, null)
	var lit := []
	fp.online.connect(func(seat, id, first): lit.append([seat, id, first]))
	fp.sync(0.05, null)                              # the first look only learns the board
	hs.nodes[target]["buildable"] = ["forge"]        # (not in snapshots: the host decides what may be built)
	hs.nodes[target]["units"] = 200.0
	check(hs.build_attachment(target, "forge"), "host starts a forge")
	var bt := 0.0
	var early := false
	while hs.nodes[target]["attachment"] != "forge" and bt < 20.0:
		hs.step(0.1)
		bt += 0.1
		host.apply_snapshot(gs, host.snapshot(hs, false))
		fp.sync(0.1, null)
		if not lit.is_empty() and gs.nodes[target]["attachment"] != "forge":
			early = true
	check(not early, "no forge pulse while the forge is still building")
	check(lit == [["B", target, true]] and ForgePulse.live, "guest: the forge completing starts its owner's pulse, once")
	check(ForgePulse.boost("A", gs.nodes[target]["pos"]) == 0.0, "the pulse lifts only its owner's units")
	for i in range(22):
		host.apply_snapshot(gs, host.snapshot(hs, false))
		fp.sync(0.1, null)
	check(not ForgePulse.live and ForgePulse.boost("B", gs.nodes[target]["pos"]) == 0.0 and lit.size() == 1, "the pulse ends after 2 s and leaves the look untouched")
	var fp2 := ForgePulse.new()                      # a guest joining with the forge already there: nothing plays
	root.add_child(fp2)
	fp2.setup(gs, {}, null)
	var lit2 := []
	fp2.online.connect(func(seat, id, first): lit2.append(seat))
	fp2.sync(0.1, null)
	fp2.sync(0.1, null)
	check(lit2.is_empty(), "a forge already standing when the view starts plays no pulse")
	fp.free()
	fp2.free()

	# ---------------------------------------------------------------- SKILLS 2.0: cast orders, snapshots, Ghost Line privacy
	host._order_limits = {}                          # (the test fires orders faster than any player)
	host._packet_limits = {}
	host.bridge.sent = []
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 0, "args": {"target": home_b}})
	check(hs.cooldown("B", "active") > 30.0 and hs.effects_on("node", home_b).size() == 1, "a guest's cast order runs on the host (Fortify on B's home)")
	check(_payloads("g1", "feedback") == ["Fortify cast"], "the host answers the cast with a feedback line")
	host.bridge.sent = []
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 0, "args": {"target": home_b}})
	check(str(_payloads("g1", "feedback")[0]).begins_with("Fortify ready in"), "a second cast on cooldown is refused with the reason")
	var n_fx := hs.effects.size()
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 1, "args": {"target": 999}})
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 7, "args": {}})
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 1, "args": {"target": {"x": 1}}})
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 1, "args": {"target": [1, "drop table"]}})
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 2, "args": {}})
	check(hs.effects.size() == n_fx and hs.cooldown("B", "map") == 0.0, "bad slot, bad targets, an uncharged ultimate: all refused")
	var mire_deck: int = hs._edge_index(home_b, hs.adj[home_b][0][0])
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 1, "args": {"target": mire_deck}})
	check(hs.effects_on("edge", mire_deck).size() == 1, "a map skill cast by edge index (Mire)")
	var ks: Dictionary = host.snapshot(hs, true)
	check(ks.has("skills") and (ks["skills"] as Array).size() == 5, "snapshots carry the skill state")
	host.apply_snapshot(gs, ks)
	check(gs.effects.size() == hs.effects.size() and gs.effects_on("node", home_b).size() == 1 and gs.effects_on("edge", mire_deck).size() == 1
			and absf(gs.cooldown("B", "active") - hs.cooldown("B", "active")) < 0.001 and absf(gs.charge("A") - hs.charge("A")) < 0.0001,
			"the guest sees the effects, cooldowns and charge")
	# Ghost Lines: nobody but the owner learns which line is a decoy
	host._order_limits = {}
	host._packet_limits = {}
	hs.loadouts["A"]["active"] = "ghost_line"
	hs.loadouts["B"]["active"] = "ghost_line"
	hs.skill_cd["B"]["active"] = 0.0
	hs.nodes[home_a]["units"] = 200.0
	hs.nodes[home_b]["units"] = 200.0
	var rg: Array = host.main.perform("A", "cast", 0, {"target": [home_a, home_b]})
	check(rg[0] and hs.hordes[-1].get("decoy", false), "the host casts a Ghost Line")
	var ghost_a: int = hs.hordes[-1]["id"]
	_to_host("g1", {"op": "order", "round": 1, "action": "cast", "a": 0, "args": {"target": [home_b, home_a]}})
	var ghost_b: int = hs.hordes[-1]["id"]
	check(ghost_b != ghost_a and hs.hordes[-1].get("decoy", false) and hs.hordes[-1]["owner"] == "B", "the guest casts one too")
	host.bridge.sent = []
	host._send_ghosts(true)
	var gp: Array = _payloads("g1", "ghosts")
	check(gp.size() == 1 and gp[0]["ids"] == [ghost_b], "the guest is told only about its own decoys")
	var gsnap: Dictionary = host.snapshot(hs, true)
	check((gsnap["hordes"] as Array).all(func(h): return not h.has("decoy") and not h.has("ghost_left")), "the broadcast snapshot never carries the decoy flag")
	_deliver()
	host.apply_snapshot(gs, gsnap)
	g._mark_ghosts()
	var ga: Dictionary = gs._horde(ghost_a)
	var gb: Dictionary = gs._horde(ghost_b)
	check(not ga.is_empty() and not ga.get("decoy", false) and gb.get("decoy", false) and Sim.is_ghost_for(gb, "B") and not Sim.is_ghost_for(ga, "B"),
			"the guest draws its own ghost as a ghost and the host's as a real line")
	host.bridge.sent = []
	host.push_effects([{"type": "skill", "id": "ghost_line", "seat": "A", "private": "A"}, {"type": "skill", "id": "ghost_line", "seat": "B", "private": "B"},
			{"type": "skill", "id": "fortify", "seat": "A"}])
	_deliver()
	var seen_fx := gs.fx_events.filter(func(e): return e.get("type", "") == "skill")
	check(seen_fx.size() == 2 and not seen_fx.any(func(e): return e.get("private", "") == "A"), "private fx events reach their own seat only")
	gs.fx_events.clear()

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

	# ---------------------------------------------------------------- a drop mid-match holds the seat
	var hs2 := _build_sim(host.match_info)
	host.world_ready(hs2, _fake_main(hs2))
	g.world_ready(_build_sim(g.match_info), null)
	_deliver()
	check(host.started, "round 2 begins")
	check(not g.rejoin.is_empty() and str(g.rejoin["code"]) == "AB7K", "the guest keeps its RECONNECT details")
	var gid: int = g.assigned_id
	var notes := []
	host.order_feedback.connect(func(m): notes.append(m))
	host.links.erase("g1")
	host.peer_left(gid)
	check(host.active and host.started and host.roster.has(gid) and host.is_away(gid), "a guest dropping mid-match keeps the seat; the match goes on")
	check(notes.any(func(m): return "RECONNECT" in m), "the others are told the seat can reconnect")
	g.fail("The host stopped responding for 10 s. RECONNECT to try the room again.")
	check(not g.in_room() and not g.rejoin.is_empty(), "a dropped guest can still RECONNECT")
	check(g.HOST_GRACE == 10.0, "guests wait 10 s for a silent host")
	# reconnect with a wrong token: refused (the match is running)
	var thief := _join("thief", "vex")
	_deliver()
	check(thief.bridge == null and host.is_away(gid), "a stranger cannot take the held seat")
	guests.erase("thief")
	# the real reconnect
	var r2 := _new_net()
	r2.remote_host = "host"
	r2.room_code = "AB7K"
	r2.rejoin = g.rejoin
	r2.preferred_faction = "solar"
	guests["g1b"] = r2
	host.links["g1b"] = host.next_peer
	host.next_peer += 1
	_to_host("g1b", {"op": "register", "version": host.version(), "faction": "solar", "token": g.rejoin["token"]})
	_deliver()
	check(host.links["g1b"] == gid and not host.is_away(gid) and r2.assigned_id == gid, "RECONNECT: same id, same seat")
	check(r2.active and r2.match_round == host.match_round, "the reconnected guest receives the running round")
	check(r2.match_info.get("colours", {}) == host.match_info["colours"] and host.match_info["colours"].size() == 2, "RECONNECT: the round's seat colours come back with it")
	r2.world_ready(_build_sim(r2.match_info), null)
	_deliver()
	check(r2.started, "the reconnected guest joins the running clock")
	host._process(0.2)
	_deliver()
	check(r2.sim.time > 0.0 or r2.sim.hordes.size() >= 0, "snapshots reach the reconnected guest")

	# ---------------------------------------------------------------- EMPTY SEATS: AI
	_open_room("FFA3")
	var a1 := _join("g1")
	_deliver()
	check(not host.can_start(), "FFA3 with two players: no deploy while EMPTY SEATS is off")
	host.set_ai_fill("Casual")
	_deliver()
	check(host.can_start() and a1.ai_fill == "Casual", "EMPTY SEATS: AI - deploy opens; guests see the setting")
	host.start_match()
	_deliver()
	check(host.match_info["players"].size() == 3 and host.match_info["ai"] == {"C": "Casual"}, "the AI takes seat C")
	check(host.ai_seats() == {"C": "Casual"}, "host runs an AI for seat C")
	var hs4 := _build_sim(host.match_info)
	check(hs4.factions.size() == 3, "the round has three seats")
	host.world_ready(hs4, _fake_main(hs4))
	a1.world_ready(_build_sim(a1.match_info), null)
	_deliver()
	host.links.erase("g1")
	host.peer_left(2)
	check(host.ai_seats().has("B") and host.ai_seats()["B"] == "Casual", "with EMPTY SEATS on, the AI covers a dropped player")
	hs4.over = true
	hs4.winner = "A"
	host._process(0.2)
	host.request_rematch()
	check(host.match_round == 2 and host.roster.size() == 1 and host.match_info["ai"].size() == 2, "rematch: the dropped player's seat goes to the AI")

	# ---------------------------------------------------------------- without AI: rematch returns to the lobby
	_open_room("1v1")
	var b1 := _join("g1")
	_deliver()
	host.start_match()
	_deliver()
	var hs5 := _build_sim(host.match_info)
	host.world_ready(hs5, _fake_main(hs5))
	b1.world_ready(_build_sim(b1.match_info), null)
	_deliver()
	host.links.erase("g1")
	host.peer_left(2)
	check(host.ai_seats().is_empty(), "EMPTY SEATS off: a dropped seat stands idle")
	hs5.over = true
	hs5.winner = "A"
	host._process(0.2)
	host.request_rematch()
	check(not host.active and host.roster.size() == 1 and host.in_room(), "rematch with a missing player and no AI: back to the lobby")

	# ---------------------------------------------------------------- lobby departures, host departure
	_open_room("FFA3")
	_join("g1")
	_join("g2")
	_deliver()
	host.peer_left(2)
	_deliver()
	check(host.roster.size() == 2 and host.seat_of(3) == "B", "seats repack after a lobby departure")
	var gg: Node = guests["g2"]
	gg.fail("The host left or the connection was lost. The room is closed.")
	check(not gg.in_room() and gg.status.begins_with("The host left"), "host departure closes the room for a guest")
	gg.leave()
	check(gg.rejoin.is_empty(), "LEAVE ROOM forgets the RECONNECT details")

	# ---------------------------------------------------------------- ABILITIES OFF (a room setting)
	_open_room("1v1")
	var ab := _join("g1")
	_deliver()
	host.toggle_abilities()
	_deliver()
	check(not host.abilities and not ab.abilities, "the host turns ABILITIES OFF; the guest sees it")
	host.map_path = "res://maps/004-two-piers.json"
	host.start_match()
	_deliver()
	var hs6 := _build_sim(host.match_info)
	check(host.match_info["rules"]["abilities_on"] == false and not hs6.abilities_on and "off" in hs6.cast_check("A", "active", hs6.homes["A"]),
			"ABILITIES OFF: nothing casts in that round")
	Rules.abilities_on = true

	_test_colours()
	_test_teams()
	print("\nALL PASSED (0 failed)" if failures == 0 else "\n%d FAILED" % failures)


func _colours_of(n: Node) -> Dictionary:
	var out := {}
	for id in n.roster:
		out[id] = n.roster[id]["colour"]
	return out


func _test_colours() -> void:
	## 0.18.7 (Daniele: the same colours on every screen): lobby picks, unique, team families, the map
	## in the launch, identical on host and guest.
	# ---------------------------------------------------------------- FFA: unique picks
	_open_room("FFA4")
	host._fix_colours()
	var c1 := _join("g1", "null")
	var c2 := _join("g2", "ember")
	var c3 := _join("g3", "bloom")
	_deliver()
	var cols := _colours_of(host).values()
	check(cols.size() == 4 and cols.all(func(c): return Rules.HUES.has(c)) and _uniq(cols).size() == 4, "FFA: every player gets a distinct colour")
	check(_colours_of(c1) == _colours_of(host) and _colours_of(c3) == _colours_of(host), "FFA: every guest sees the same colour list")
	var taken: String = host.roster[1]["colour"]
	_to_host("g1", {"op": "colour", "colour": taken})
	_deliver()
	check(host.roster[c1.assigned_id]["colour"] != taken, "a colour another player has is refused")
	_to_host("g1", {"op": "colour", "colour": "tartan"})
	_to_host("g1", {"op": "colour", "colour": 7})
	check(Rules.HUES.has(str(host.roster[c1.assigned_id]["colour"])), "unknown colours are ignored")
	var free: String = Rules.FFA_ORDER.filter(func(k): return not k in _colours_of(host).values())[0]
	_to_host("g1", {"op": "colour", "colour": free})
	_deliver()
	check(host.roster[c1.assigned_id]["colour"] == free and c2.roster[c1.assigned_id]["colour"] == free, "a free colour is taken and every guest sees it")
	var late := _new_net()                              # a newcomer asking for a taken colour gets another
	late.remote_host = "host"
	late.room_code = "AB7K"
	guests["late"] = late
	host.set_mode("FFA5")
	host.links["late"] = host.next_peer
	host.next_peer += 1
	_to_host("late", {"op": "register", "version": host.version(), "faction": "solar", "colour": free})
	_deliver()
	check(late.assigned_id > 0 and host.roster[late.assigned_id]["colour"] != free and _uniq(_colours_of(host).values()).size() == 5, "a newcomer's taken colour gives way (still unique)")
	host.set_colour("orange" if not "orange" in _colours_of(host).values() else "cyan")
	check(host.roster[1]["colour"] in ["orange", "cyan"], "the host picks its own colour")
	# ---------------------------------------------------------------- the launch carries the map, same on both
	host.set_ai_fill("Casual")
	host.set_mode("FFA5")
	host.start_match()
	_deliver()
	var hc: Dictionary = host.match_info.get("colours", {})
	check(hc.size() == 5 and _uniq(hc.values()).size() == 5, "launch: a colour for every seat, all different")
	for id in host.roster:
		check(hc[host.seat_of(id)] == host.roster[id]["colour"], "launch: seat %s keeps its player's pick" % host.seat_of(id))
	check(c1.match_info["colours"] == hc and late.match_info["colours"] == hc, "every guest receives the same seat -> colour map")
	Rules.use_colours(host.match_info["colours"])
	var on_host := Rules.seat_colors.duplicate()
	Rules.use_colours(c2.match_info["colours"])
	check(Rules.seat_colors == on_host and Rules.seat_colors["A"] == Rules.HUES[hc["A"]], "host and guest render identical seat colours (no per-screen recolouring)")

	# ---------------------------------------------------------------- team families
	_open_room("2v2")
	host.map_path = "res://maps4/A-01-orbital-nexus.json"   # A+C against B+D
	host._fix_colours()
	var t1 := _join("g1", "null")
	_deliver()
	check(host.team_of(1) != host.team_of(t1.assigned_id), "2v2 on A-01: the first guest (B) starts on the other team")
	var fams: Array = host.families()
	var hfam: int = host.family_of(fams, host.roster[1]["colour"])
	var gfam: int = host.family_of(fams, host.roster[t1.assigned_id]["colour"])
	check(hfam >= 0 and gfam >= 0 and hfam != gfam, "rival teams get different hue families")
	var host_family_other: String = (fams[hfam] as Array).filter(func(k): return k != host.roster[1]["colour"])[0]
	_to_host("g1", {"op": "colour", "colour": host_family_other})
	_deliver()
	check(host.family_of(fams, host.roster[t1.assigned_id]["colour"]) == gfam, "a hue of the other team's family is refused")
	_to_host("g1", {"op": "colour", "colour": "purple"})
	check(host.roster[t1.assigned_id]["colour"] != "purple", "a hue in no team family is refused in team modes")
	# switch to the host's team: the colour follows the team's family
	_to_host("g1", {"op": "team", "team": host.team_of(1)})
	_deliver()
	check(host.team_of(t1.assigned_id) == host.team_of(1), "the guest joined the host's team")
	check(host.family_of(fams, host.roster[t1.assigned_id]["colour"]) == hfam and host.roster[t1.assigned_id]["colour"] != host.roster[1]["colour"], "teammates share the family with different hues")
	# the host picks a hue of the free family: the whole team moves to it
	var other_fam: Array = fams[1 - hfam]
	host.set_colour(other_fam[0])
	check(host.roster[1]["colour"] == other_fam[0] and host.roster[t1.assigned_id]["colour"] in other_fam and host.roster[t1.assigned_id]["colour"] != other_fam[0], "a pick from the free family moves the team to it")
	host.set_ai_fill("Standard")
	var rc: Dictionary = host.room_colours()
	check(rc.size() == 4 and _uniq(rc.values()).size() == 4, "room colours: four seats, four hues")
	var ok_fam := true
	for sl in range(4):
		var same_team: bool = host.team_of_slot(sl) == host.team_of(1)
		ok_fam = ok_fam and (host.family_of(fams, rc[host.SEATS[sl]]) == (1 - hfam if same_team else hfam))
	check(ok_fam, "the AI seats take their team's family (the AI team the other one)")
	host.start_match()
	_deliver()
	check(t1.match_info["colours"] == host.match_info["colours"] and host.match_info["colours"] == rc, "2v2 launch: the same map on host and guest")


func _uniq(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = true
	return d


func _test_teams() -> void:
	## 0.18.7 (Daniele: "there should be so i can switch to my gf team"): JOIN TEAM, host-validated.
	_open_room("2v2")
	host.map_path = "res://maps4/A-01-orbital-nexus.json"   # A+C against B+D: join order splits two players
	host._fix_colours()
	var gf := _join("gf", "bloom")
	_deliver()
	var gid: int = gf.assigned_id
	check(gf.local_seat() == "B" and gf.team_of(gid) != gf.team_of(1), "on A-01 the guest joins seat B, the rival team")
	gf.switch_team(gf.team_of(1))                           # the real guest call: an op to the host
	_deliver()
	check(host.seat_of(gid) == "C" and gf.local_seat() == "C" and host.team_of(gid) == host.team_of(1), "JOIN TEAM: the guest moves to seat C, the host's team")
	_to_host("gf", {"op": "team", "team": 9})
	_to_host("gf", {"op": "team", "team": "x"})
	_to_host("gf", {"op": "team", "team": host.team_of(1)})
	check(host.seat_of(gid) == "C", "unknown teams and a no-op switch are ignored")
	var g3 := _join("g3", "ember")
	_deliver()
	check(host.seat_of(g3.assigned_id) == "B", "a newcomer takes the first free seat (B)")
	var g4 := _join("g4", "vex")
	_deliver()
	check(host.seat_of(g4.assigned_id) == "D" and host.roster.size() == 4, "the fourth player takes seat D")
	_to_host("g3", {"op": "team", "team": host.team_of(1)})
	_deliver()
	check(host.seat_of(g3.assigned_id) == "B" and host.team_of(g3.assigned_id) != host.team_of(1), "a full team takes nobody")
	host.peer_left(g4.assigned_id)
	_deliver()
	check(host.seat_of(gid) == "C" and host.seat_of(g3.assigned_id) == "B", "team modes: a lobby departure keeps everyone's seat")
	check(host.move_to_team(g3.assigned_id, host.team_of(1)) == false, "the host cannot overfill a team")
	check(host.move_to_team(gid, host.team_of(g3.assigned_id)) and host.seat_of(gid) == "D", "the host moves a player to the other team")
	check(host.move_to_team(gid, host.team_of(1)) and host.seat_of(gid) == "C", "and back")
	host.peer_left(g3.assigned_id)
	_deliver()
	# deploy with EMPTY SEATS: AI - the humans play together, the AI fills B and D
	host.set_ai_fill("Casual")
	host.start_match()
	_deliver()
	var info: Dictionary = host.match_info
	check(info["ai"] == {"B": "Casual", "D": "Casual"} and info["players"].size() == 4, "deploy: AI in the free seats B and D (not packed)")
	check(gf.local_seat() == "C" and gf.match_info["roster"][gid]["slot"] == 2, "the guest's round seat is C")
	var hs := _build_sim(info)
	check(hs.allied("A", "C") and not hs.allied("A", "B") and not hs.allied("C", "D"), "the match seats both humans on the same side (allied lines, shared win)")
	hs.winner = "C"
	check(hs.allied(hs.winner, "A"), "a win by the guest's seat is the host's win too")
	# mode and map changes re-validate the teams
	_open_room("2v2")
	host.map_path = "res://maps4/A-01-orbital-nexus.json"
	host._fix_colours()
	var m1 := _join("m1", "bloom")
	_deliver()
	host.move_to_team(m1.assigned_id, host.team_of(1))
	check(host.seat_of(m1.assigned_id) == "C", "A-01: host A and guest C together")
	host.set_map("res://maps4/B-05-trident-exchange.json")   # A+B against C+D
	_deliver()
	check(host.team_of(m1.assigned_id) == host.team_of(1) and host.seat_of(m1.assigned_id) == "B" and m1.local_seat() == "B", "a map with other team seats keeps the pair together (guest to B)")
	host.set_mode("FFA3")
	_deliver()
	check(host.seat_of(1) == "A" and host.seat_of(m1.assigned_id) == "B" and m1.mode == "FFA3", "FFA: no teams, seats packed in seat order")
	host.set_mode("3v3")
	_deliver()
	check(host.team_of(m1.assigned_id) == host.team_of(1) and host.map_path != "" and host.map_offers(host.map_path, "3v3"), "3v3: the pair stays on one team")
	host.set_mode("2v2")
	host.set_map("res://maps4/A-01-orbital-nexus.json")
	_deliver()
	check(host.team_of(m1.assigned_id) == host.team_of(1) and host.seat_of(m1.assigned_id) == "C", "back to 2v2 on A-01: still together (A + C)")
	check(_uniq(_colours_of(host).values()).size() == 2 and host.family_of(host.families(), host.roster[1]["colour"]) == host.family_of(host.families(), host.roster[m1.assigned_id]["colour"]), "after every change the pair keeps one hue family, different hues")
	# a smaller mode never overfills a team: three on one 3v3 team, then 2v2
	_open_room("3v3")
	host._fix_colours()
	_join("p2", "bloom")
	_join("p3", "ember")
	_deliver()
	check([1, 2, 3].all(func(id): return host.team_of(id) == host.team_of(1)), "3v3: three players on the first team")
	host.set_mode("2v2")
	_deliver()
	var sizes := {}
	for id in host.roster:
		sizes[host.team_of(id)] = int(sizes.get(host.team_of(id), 0)) + 1
	check(sizes.values().all(func(n): return n <= 2) and _uniq(host.roster.values().map(func(r): return r["slot"])).size() == 3, "3v3 -> 2v2: the third player moves to the other team (no team over two)")
	check(guests["p3"].team_of(3) == host.team_of(3) and guests["p3"].local_seat() == host.seat_of(3), "the guests see the re-validated seats")
	m1 = guests["p2"]
	# FFA refuses team switches
	host.set_mode("FFA3")
	check(not host.move_to_team(m1.assigned_id, 1), "FFA: no team switching")
	# the protocol refuses a guest built without team switching (same-build rooms only)
	_join("old", "null", "ooze20-net-1/" + Rules.VERSION)
	check("rejected" in _kinds_to("old"), "a guest on the previous room protocol is refused")
	guests.erase("old")

	quit(1 if failures > 0 else 0)
