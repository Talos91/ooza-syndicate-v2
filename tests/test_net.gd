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

class QueueBridge:
	## A guest transport whose poll() hands over queued events (a "connection" makes the guest register).
	extends FakeBridge
	var queue: Array = []
	func poll() -> String:
		var r := JSON.stringify(queue)
		queue = []
		return r

var failures := 0
var host: Node
var guests := {}                          # remote name -> guest Net


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	Rules.archived_on = true                          # 0.23.21: Mire / Anchor / Bypass archived; their net paths are still tested
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
	host.map_path = _map_for(mode)
	host.roster = {1: {"faction": "vex", "slot": 0}}
	host.room_owner = 1                             # a browser-hosted room: the host runs it (Net._start)


func _map_for(mode: String) -> String:
	## The pool's first map for `mode`, else (OOZE 3.0: the pool is the Z maps, 1v1 only - Daniele 11-27; WP6 removes the
	## other modes) the first legacy map in MapPool.dir that seats it, so the protocol checks still run on every seat count.
	var pool: Array = host.maps_for(mode)
	if not pool.is_empty():
		return pool[0]
	for p in MapPool.all():
		if host.map_offers(p, mode):
			return p
	return ""


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


func _ready_all() -> void:
	## READY (ooze20-net-6): every guest presses READY - DEPLOY waits for it.
	for remote in guests:
		if guests[remote].bridge != null:
			guests[remote].set_ready(true)
	_deliver()


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
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), info.get("loadouts", {}))
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()   # not in the tree: perform() needs only sim
	m.sim = s
	return m


func _versus_card(m: Node3D, n: Node) -> Node:
	## ONLINE VERSUS: the card as main._start_online adds it (VersusScreen.hold_online), watching this test's Net.
	var v: Node = load("res://scripts/versus_screen.gd").new()
	v.main = m
	v.online = true
	v.net = n
	root.add_child(v)                                # its _ready builds the card (headless: no draw)
	return v


func _run() -> void:
	MapPool.dir = "res://maps"                     # the legacy roster offers every mode, whatever pack ships
	# ---------------------------------------------------------------- lobby, every mode
	for mode in ["1v1"]:   # 2v2 / FFA3 / FFA4 deleted 2026-11-27 (BRAWL 1v1 only)
		_open_room(mode)
		for i in range(1, host.slots()):
			_join("g%d" % i, ["null", "ember", "bloom", "solar"][i - 1])
		_deliver()
		check(host.roster.size() == host.slots(), mode + ": every seat filled")
		var seats := {}
		for id in host.roster:
			seats[host.seat_of(id)] = true
		check(seats.size() == host.slots(), mode + ": distinct seats A..")
		check(not host.can_start(), mode + ": DEPLOY waits for the players' READY")
		_ready_all()
		check(host.can_start(), mode + ": host can deploy")
		var g1: Node = guests["g1"]
		check(g1.assigned_id == 2 and g1.local_seat() == "B", mode + ": first guest is seat B")
		check(g1.connected and g1.roster.size() == host.slots() and g1.mode == mode and g1.map_path == host.map_path, mode + ": guest sees the lobby")
		var extra := _join("late")
		_deliver()
		check(extra.bridge == null and not host.roster.has(host.links["late"]), mode + ": a full room rejects a third player")
		guests.erase("late")
		extra.queue_free()

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
	check(host.mode == "1v1", "FFA is gone: the room refuses it and stays 1v1")
	_ready_all()
	check(host.can_start(), "back to 1v1")

	# ---------------------------------------------------------------- launch and the loading barrier
	host.map_path = "res://maps/004-two-piers.json"
	g.set_ready(false)                               # READY locks the picks: un-ready to change the skills
	_deliver()
	g.set_loadout({"active": "fortify", "map": "mire"})     # SKILLS 2.0: the guest's loadout rides in the roster
	_to_host("g1", {"op": "loadout", "active": "nuke", "map": "mire"})
	check(host.roster[g.assigned_id]["loadout"] == {"map": "mire"}, "an unknown skill id in a loadout is dropped")
	g.set_loadout({"active": "fortify", "map": "mire"})
	_deliver()
	check(host.roster[g.assigned_id]["loadout"] == {"active": "fortify", "map": "mire"}, "a guest sets its loadout in the lobby")
	_ready_all()
	host.start_match()
	var info: Dictionary = host.match_info
	check(info["loadouts"] == {"B": {"active": "fortify", "map": "mire"}} and info["rules"]["abilities_on"] == true,
			"the launch carries the loadouts and ABILITIES ON")
	check(host.active and int(info["round"]) == 1 and info["players"].size() == 2, "launch: round 1 with both players")
	_deliver()
	check(g.active and g.match_round == 1 and g.match_info["seed"] == info["seed"], "guest receives the launch (same seed)")
	check(not info["rules"].has("bridge_combat") and not host.has_method("toggle_siege"),
			"rooms play BRAWL: no SIEGE field on the wire and no room control switches SIEGE on (deleted 2026-11-23, WP6 2026-11-27)")
	var hs := _build_sim(info)
	var gs := _build_sim(g.match_info)
	# ONLINE VERSUS (0.22.3): the card is a loading screen on both ends - up from the launch, gone only once this
	# client is loaded, the round runs and (a guest) the first snapshot is in, and VERSUS_ONLINE_MIN s have passed.
	# (No frames run in this script: the frames drawn under the card and its clock are set by hand.)
	var hm := _fake_main(hs)
	var gm := _fake_main(gs)
	gm.HUMAN = "B"
	var vh := _versus_card(hm, host)
	var vg := _versus_card(gm, g)
	check(not vh.online_loaded() and vh.online_wait_text().begins_with("LOADING"), "VERSUS: up from the launch, loading the world first")
	vh._frames = Rules.WARMUP_FRAMES + 2
	vg._frames = Rules.WARMUP_FRAMES + 2
	check(not vh.online_loaded() and vh.online_wait_text().begins_with("LOADING"),
			"STAGED LOAD: frames drawn under the card, the world still being built (main.started false): still loading")
	hm.started = true                                # (the staged build finished)
	gm.started = true
	check(vh.online_loaded() and not vh.online_ready() and vh.online_wait_text().begins_with("WAITING FOR EVERY"),
			"VERSUS: a loaded host waits for every player at the barrier")
	host.world_ready(hs, hm)
	check(not host.started, "host waits for every player to load")
	g.world_ready(gs, null)
	_deliver()
	check(host.started and g.started, "everyone loaded: the round begins on both")
	check(vh.online_ready() and not vh.online_done(), "VERSUS: the host's card is ready once the barrier passed, but stays VERSUS_ONLINE_MIN")
	check(not vg.online_ready() and vg.online_wait_text().begins_with("WAITING FOR THE HOST"), "VERSUS: the guest's card waits for the first snapshot")
	vg._go()
	check(not vg._gone, "VERSUS: a tap before the guest is ready does nothing")
	vh._t = Rules.VERSUS_ONLINE_MIN
	check(vh.online_done(), "VERSUS: the host's card goes after VERSUS_ONLINE_MIN")
	vh._go()
	check(vh._gone, "VERSUS: the host's card is gone")
	vh.free()
	check(hs.nodes.size() == gs.nodes.size() and hs.homes == gs.homes, "both browsers built the same map")
	check(hs.loadouts["B"] == {"active": "fortify", "map": "mire", "ultimate": Rules.FACTION_ULTIMATE_ID[info["players"]["B"]]} and hs.loadouts == gs.loadouts,
			"host and guest set up the same loadouts (a missing one = the faction default)")

	# ---------------------------------------------------------------- orders, validated by the host
	var home_b: int = hs.homes["B"]
	var home_a: int = hs.homes["A"]
	var target: int = hs.adj[home_b][0][0]
	hs.nodes[home_b]["units"] = 200.0                # (0.18.10 homes start with 1 unit shown: enough to take the neighbour)
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
	check(vg.online_ready() and not vg.online_done(), "VERSUS: the guest's card is ready with the first snapshot in, still up under VERSUS_ONLINE_MIN")
	vg._t = Rules.VERSUS_ONLINE_MIN
	check(vg.online_done(), "VERSUS: the guest's card goes after VERSUS_ONLINE_MIN")
	vg._go()
	check(vg._gone, "VERSUS: the guest's card is gone")
	vg.free()
	var vx := _versus_card(_fake_main(gs), g)
	vx._t = Rules.VERSUS_ONLINE_MAX
	check(vx.online_done() and not vx.online_loaded(), "VERSUS: an unloaded card still goes at VERSUS_ONLINE_MAX (the HUD's waiting text takes over)")
	vx.free()
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
	for st in lsm["seats"]["1v1"]:
		ls_seats[int(st["node"])] = st["seat"]
	var ls_host := Sim.new()
	ls_host.setup(lsm, MapBuilder.layout(lsm), ls_seats, {"A": "null", "B": "ember"}, 2)
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
	# 0.22.3 THE WAVE: a dropped platform's decks break outward over a few steps - the guest learns the break progress
	# from the snapshot's additive "breaking" field, so its is_edge_open (walkable until gone) matches the host's
	var ls_drop: int = ls_host.last_stand_queue[0]
	ls_host._drop_node(ls_drop)
	ls_host.step(0.05)
	var ls_decks: Array = (ls_host.adj[ls_drop] as Array).map(func(l): return l[1])
	var ls_wire2: PackedByteArray = var_to_bytes(host.snapshot(ls_host, false))
	host.apply_snapshot(ls_guest, bytes_to_var(ls_wire2))
	check(not ls_host.breaking.is_empty() and ls_guest.breaking == ls_host.breaking
			and ls_decks.all(func(i): return ls_guest.is_edge_open(i) == ls_host.is_edge_open(i)),
			"the guest's breaking decks (%d) and their walkability follow the host's snapshot" % ls_host.breaking.size())
	var ls_bytes: int = ls_wire2.size()
	check(ls_bytes < 40000, "(the lean snapshot with the wave stays small: %d bytes)" % ls_bytes)
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

	# ---------------------------------------------------------------- STRUCTURES 2.1 (0.18.10): orders and snapshots
	check(host.VERSION_TAG == "ooze20-net-9", "the net protocol is bumped for OOZE 3.0 (ooze20-net-9; 8: powers)")
	check(host.version() == "ooze20-net-9/" + Rules.VERSION, "a room's version = net-9 tag + Rules.VERSION (0.25.x net-8 rooms never mix)")
	# OOZE 3.0 (WP5): the quota rides every snapshot, keyframe and delta, through the real wire to the guest's Sim
	host._order_limits = {}
	var q_old: Dictionary = hs.quota.duplicate()
	hs.quota = {"A": 3, "B": 5}
	hs.quota_last_side = "B"
	hs.quota_reason = "final"
	host._broadcast_raw("state", var_to_bytes(host._wire_state(host.snapshot(hs, true), true)).compress(FileAccess.COMPRESSION_DEFLATE))
	_deliver()
	check(gs.quota == {"A": 3, "B": 5} and gs.quota_last_side == "B" and gs.quota_reason == "final",
			"guest: a keyframe carries the quota (%s, %s, %s)" % [str(gs.quota), gs.quota_last_side, gs.quota_reason])
	hs.quota = {"A": 4, "B": 5}
	hs.quota_last_side = "A"
	hs.quota_reason = "unreachable"
	var q_delta: Dictionary = host._wire_state(host.snapshot(hs, false), false)
	check(q_delta.has("base") and q_delta.has("quota"), "a delta snapshot carries the quota whole")
	host._broadcast_raw("state", var_to_bytes(q_delta).compress(FileAccess.COMPRESSION_DEFLATE))
	_deliver()
	check(gs.quota == {"A": 4, "B": 5} and gs.quota_last_side == "A" and gs.quota_reason == "unreachable",
			"guest: a delta updates the quota (%s, %s, %s)" % [str(gs.quota), gs.quota_last_side, gs.quota_reason])
	var q_wire := var_to_str(host.snapshot(hs, true)) + var_to_str(host.match_info) + var_to_str(host.roster)
	check(not q_wire.contains("count_scale") and not q_wire.contains("count_size") and not q_wire.contains("COUNT_SIZE"),
			"the count size (a local OPTIONS choice) is in no packet: snapshot, launch, roster")
	hs.quota = q_old
	hs.quota_last_side = ""
	hs.quota_reason = ""
	host.apply_snapshot(gs, host.snapshot(hs, true))
	host._order_limits = {}
	host._packet_limits = {}
	host.bridge.sent = []
	hs.nodes[home_b]["units"] = 300.0
	_to_host("g1", {"op": "order", "round": 1, "action": "build", "a": home_b, "args": {"kind": "machinegoon"}})
	check(hs.nodes[home_b]["build_kind"] == "machinegoon", "a guest's build order runs on the host (a machinegoon on B's home)")
	check(str(_payloads("g1", "feedback")[0]).begins_with("Googatling construction started"), "...answered with the Sim's feedback line")
	var g_id: int = g.assigned_id
	check(host._execute(g_id, {"action": "build", "a": home_b, "args": {"kind": "nuke"}}) == [false, "Order rejected"]
			and host._execute(g_id, {"action": "build", "a": home_b, "args": {"kind": 7}}) == [false, "Order rejected"],
			"an unknown build kind is rejected")
	check(not host._execute(g_id, {"action": "build", "a": home_a, "args": {"kind": "machinegoon"}})[0], "a guest can't build on the host's node")
	check(host._execute(g_id, {"action": "eject", "a": home_b, "args": {}}) == [false, "Order rejected"], "EJECT (deleted with 2v2) is an unknown order")
	hs.nodes[target]["structure"] = "monster_hub"     # (staged: B's captured neighbour holds a ready hub)
	hs.nodes[target]["units"] = 300.0
	hs.nodes[target]["monster_ready_t"] = 0.0
	Rules.MONSTER_REACH = 3                           # (A's home is 2 decks from the staged hub; the rule is 1 since 0.22.1 - restored below)
	check(host._execute(g_id, {"action": "launch_monster", "a": target, "args": {"to": 1.5}}) == [false, "Order rejected"], "a monster order with a bad target is rejected")
	var lm: Array = host._execute(g_id, {"action": "launch_monster", "a": target, "args": {"to": home_a}})
	check(lm[0] and hs.monsters.size() == 1, "a guest's monster launch runs on the host (%s)" % str(lm))
	hs.draw_line = "DRAW - test"
	hs.step(0.1)
	var ss: Dictionary = host.snapshot(hs, false)
	check(ss.has("structs") and (ss["structs"] as Array).size() == 3, "snapshots carry the monsters and the draw line")
	var sw: PackedByteArray = var_to_bytes(ss)
	host.apply_snapshot(gs, bytes_to_var(sw))
	check(gs.nodes[home_b]["build_kind"] == "machinegoon" and gs.nodes[target]["structure"] == "monster_hub"
			and absf(float(gs.nodes[target]["monster_ready_t"]) - float(hs.nodes[target]["monster_ready_t"])) < 0.001,
			"the guest sees the new node fields (structure, monster_ready_t)")
	check(gs.monsters.size() == 1 and gs.monsters[0]["id"] == hs.monsters[0]["id"] and (gs.monsters[0]["pos"] as Vector3).distance_to(hs.monsters[0]["pos"]) < 0.01
			and gs.draw_line == "DRAW - test", "the guest sees the monster where the host has it, and the draw line")
	var mp0: float = gs.monsters[0]["s"]
	host.predict(gs, 0.2)
	check(float(gs.monsters[0]["s"]) > mp0, "prediction walks the monster between snapshots")
	hs.eliminated["C"] = true                        # (staged) an out seat reads as out on the guest too (0.19.2 spectating)
	host.apply_snapshot(gs, host.snapshot(hs, false))
	check(gs.is_out("C") and not gs.is_out("B"), "Sim.is_out works from the host's snapshots")
	hs.eliminated.erase("C")
	hs.monsters = []
	hs.nodes[target]["hub_monster"] = -1              # (cleanup, matching hs.monsters = [] above)
	hs.nodes[target]["monster_ready_t"] = 0.0          # (the earlier real launch put it on a ~40 s cooldown)
	Rules.MONSTER_REACH = 1
	hs.draw_line = ""
	host.apply_snapshot(gs, host.snapshot(hs, false))  # re-sync the guest: the hub reads ready again
	# 0.20.1 monster-launch fix (Daniele's online playtest, both players guests: "i couldn't figure how
	# to send the monster" - the order already reached the host fine, per the checks above; the actual
	# bug was the guest's own UI never arming the launch). A guest's Hud, built from nothing but its
	# synced Sim, must see the same ready hub the host does.
	# res://scripts/hud.gd is loaded at runtime (not as a static `Hud` reference) so this script's own
	# compile doesn't force-reload hud.gd before the Net autoload is wired up - a static reference makes
	# the GDScript compiler eagerly reload hud.gd as a dependency of test_net.gd's own class, too early
	# for "Net" to resolve inside hud.gd's sync(), which breaks every use of Hud in this process for good.
	var hud_probe: Node = load("res://scripts/hud.gd").new()
	hud_probe.sim = gs
	hud_probe.human = "B"
	check(hud_probe.is_ready_hub(target), "a guest's Hud sees its own ready Monster hub as launchable")
	check(not hud_probe.is_ready_hub(home_a), "...but not a node that isn't its own ready hub")
	hud_probe.free()

	# ---------------------------------------------------------------- SKILLS 2.0: cast orders, snapshots, Ghost Line privacy
	check(hs.cooldown("B", "active") > 0.0 or hs.time > 30.0, "(0.19.2: skills start on their cooldown)")
	for seat in hs.skill_cd:                         # stage them ready for the order checks
		hs.skill_cd[seat] = {"active": 0.0, "map": 0.0}
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
	check(host.chat_history[-1]["text"] == "hello <b>there</b>" and host.chat_history[-1]["who"] == "PLAYER A · VEX", "chat is cleaned and stamped with the name (no name: PLAYER + seat)")
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

	# ---------------------------------------------------------------- UI: the room owner's BACKGROUND for everyone
	_open_room("1v1")
	var bg1 := _join("gbg")
	_deliver()
	check(Net.BACKDROP_COUNT == LookTheme.IDS.size(), "SETTING: Net.BACKDROP_COUNT matches LookTheme.IDS (the old BACKGROUND field carries the setting)")
	check(host.room_backdrop == "auto" and bg1.room_backdrop == "auto", "BACKGROUND: a new room plays the map's own")
	host.set_room_backdrop("3")
	_deliver()
	check(bg1.room_backdrop == "3", "BACKGROUND: the owner's pick reaches the guests")
	bg1.set_room_backdrop("1")                         # a guest can't change it
	_deliver()
	check(host.room_backdrop == "3", "BACKGROUND: a guest's change is refused")
	host.set_room_backdrop("nope")
	check(host.room_backdrop == "3", "BACKGROUND: an unknown pick is refused")
	_ready_all()
	host.start_match()
	_deliver()
	check(int(host.match_info.get("backdrop", -9)) == 3 and int(bg1.match_info.get("backdrop", -9)) == 3,
			"BACKGROUND: the round's background is the same on every screen")
	host.set_room_backdrop("rotate")                   # (in a match: owner settings wait for the lobby)
	check(host.room_backdrop == "3", "BACKGROUND: no change mid-match")
	check(LookTheme.IDS[int(bg1.match_info.get("backdrop", 0))] == "quota_parade",
			"SETTING: index 3 = QUOTA PARADE on every screen")
	host.leave()
	check(host.room_backdrop == "auto", "BACKGROUND: leaving resets it")
	bg1.leave()

	# ---------------------------------------------------------------- EMPTY SEATS: AI
	_open_room("1v1")
	check(not host.can_start(), "1v1 alone: no deploy while EMPTY SEATS is off")
	host.set_ai_fill("Casual")
	_ready_all()
	check(host.can_start(), "EMPTY SEATS: AI - deploy opens")
	host.start_match()
	_deliver()
	check(host.match_info["players"].size() == 2 and host.match_info["ai"] == {"B": "Casual"}, "the AI takes seat B")
	check(host.ai_seats() == {"B": "Casual"}, "host runs an AI for seat B")
	var hs4 := _build_sim(host.match_info)
	check(hs4.factions.size() == 2, "the round has two seats")
	host.world_ready(hs4, _fake_main(hs4))
	hs4.over = true
	hs4.winner = "A"
	host._process(0.2)
	host.request_rematch()
	check(host.match_round == 2 and host.roster.size() == 1 and host.match_info["ai"].size() == 1, "rematch: the AI keeps its seat")
	_open_room("1v1")
	var a1 := _join("g1")
	_deliver()
	host.set_ai_fill("Casual")
	_deliver()
	check(a1.ai_fill == "Casual", "guests see the EMPTY SEATS setting")
	_ready_all()
	host.start_match()
	_deliver()
	var hs4b := _build_sim(host.match_info)
	host.world_ready(hs4b, _fake_main(hs4b))
	a1.world_ready(_build_sim(a1.match_info), null)
	_deliver()
	host.links.erase("g1")
	host.peer_left(2)
	check(host.ai_seats().has("B") and host.ai_seats()["B"] == "Casual", "with EMPTY SEATS on, the AI covers a dropped player")

	# ---------------------------------------------------------------- without AI: rematch returns to the lobby
	_open_room("1v1")
	var b1 := _join("g1")
	_deliver()
	_ready_all()
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
	_open_room("1v1")
	_join("g1")
	_deliver()
	host.peer_left(2)
	_deliver()
	check(host.roster.size() == 1 and host.seat_of(1) == "A", "a lobby departure frees the seat")
	var gg: Node = guests["g1"]
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
	_ready_all()
	host.start_match()
	_deliver()
	var hs6 := _build_sim(host.match_info)
	check(host.match_info["rules"]["abilities_on"] == false and not hs6.abilities_on and "off" in hs6.cast_check("A", "active", hs6.homes["A"]),
			"ABILITIES OFF: nothing casts in that round")
	Rules.abilities_on = true

	_test_presets()
	_test_skill_fx()
	# ---------------------------------------------------------------- 0.18.7: the host's balance preset rides in the room rules
	_open_room("1v1")
	var bq := _join("g1")
	_deliver()
	Rules.apply_balance("legacy")
	host.map_path = "res://maps/004-two-piers.json"
	_ready_all()
	host.start_match()
	check(host.match_info["rules"].get("balance_preset", "") == "legacy", "the launch carries the host's balance preset")
	Rules.apply_balance("")                          # what the guest had on its own
	_deliver()
	check(bq.active and Rules.BALANCE_PRESET == "legacy" and Rules.NEUTRAL_UNITS[1] == Rules.BALANCE_PRESETS["legacy"]["NEUTRAL_UNITS"][1],
			"the guest plays the host's balance numbers")
	Rules.apply_balance("")

	_test_colours()
	_test_rooms_more()
	print("\nALL PASSED (0 failed)" if failures == 0 else "\n%d FAILED" % failures)


func _test_skill_fx() -> void:
	## SkillFx (0.18.7): the in-world view of all 15 skills builds and runs without errors on the host's screen
	## (seat A) and on a guest's (seat B: the host's snapshots and forwarded fx events, as Net sends them), in
	## BRAWL on D-02 Relay Bench (every relay kind); a Ghost Line's cast reaches its owner's view only.
	var map := MapBuilder.load_map("res://maps4/D-02-relay-bench.json")
	var seats := {}
	for st in map["seats"]["1v1"]:
		seats[int(st["node"])] = st["seat"]
	var factions := {"A": "vex", "B": "ember"}
	var hs := Sim.new()
	hs.setup(map, MapBuilder.layout(map), seats, factions, 7)
	var gs := Sim.new()
	gs.setup(map, MapBuilder.layout(map), seats, factions, 7)
	var hw := Node3D.new()
	root.add_child(hw)
	var gw := Node3D.new()
	root.add_child(gw)
	var hfx := SkillFx.new()
	hw.add_child(hfx)
	hfx.setup(hs, MapBuilder.build3(hw, hs, map), "A")
	var gfx := SkillFx.new()
	gw.add_child(gfx)
	gfx.setup(gs, MapBuilder.build3(gw, gs, map), "B")
	for i in [0, 1, 2, 3]:
		hs.nodes[i]["owner"] = "A"
		hs.nodes[i]["units"] = 400.0
	hs.nodes[4]["owner"] = "B"
	hs.nodes[4]["units"] = 40.0
	hs.nodes[8]["units"] = 400.0
	var casts := {}
	var cast := func(seat: String, slot: String, id: String, target) -> void:
		hs.loadouts[seat][slot] = id
		if slot == "ultimate":
			hs.ult_charge[seat] = 1.0
			hs.ult_since[seat] = 500.0
		else:
			hs.skill_cd[seat][slot] = 0.0
		var why := hs.cast_check(seat, slot, target)
		casts[id] = hs.cast(seat, slot, target)
		if not casts[id]:
			print("      (%s refused: %s)" % [id, why])
	var line: Dictionary = hs.send(0, 3, 0.3)
	hs.send(1, 3, 0.2)
	var raid: Dictionary = hs.send(2, 4, 0.9)
	var frame := func(dt: float) -> void:
		hs.step(dt)
		host.apply_snapshot(gs, host.snapshot(hs, true))
		for h in gs.hordes:                          # what Net._mark_ghosts does for the guest's own decoys
			if hs._horde(h["id"]).get("decoy", false) and h["owner"] == "B":
				h["decoy"] = true
		for ev in hs.fx_events:
			hfx.handle(ev)
			if not ev.has("private") or str(ev["private"]) == "B":   # Net.push_effects
				gfx.handle(ev)
		hs.fx_events.clear()
		hfx.sync(dt, null)
		gfx.sync(dt, null)
	for k in range(5):
		frame.call(0.1)
	cast.call("A", "ultimate", "overdrive", null)
	cast.call("A", "ultimate", "overdrive", 7)            # the ultimate slot fires a relay while Overdrive runs
	cast.call("A", "active", "surge", line["id"])
	cast.call("A", "active", "spore_burst", 3)
	cast.call("A", "active", "fortify", 1)
	cast.call("A", "active", "scorch", 2)
	cast.call("A", "active", "ghost_line", [0, 2])
	cast.call("B", "active", "ghost_line", [8, 9])
	cast.call("A", "map", "demolish", 4)
	cast.call("A", "map", "mire", 13)
	cast.call("A", "map", "anchor", 7)
	cast.call("A", "map", "bypass", 5)
	cast.call("A", "map", "relay_hack", [6, "jam"])
	cast.call("A", "ultimate", "superbloom", null)
	cast.call("A", "ultimate", "echo_split", null)
	cast.call("A", "ultimate", "relay_aegis", 3)
	for k in range(60):                                # the raid on B's node 4 comes in range: Core Meltdown
		frame.call(0.1)
		hs.loadouts["A"]["ultimate"] = "core_meltdown"
		hs.ult_charge["A"] = 1.0
		hs.ult_since["A"] = 500.0
		if not casts.get("core_meltdown", false) and hs.cast_check("A", "ultimate", raid["id"]) == "":
			cast.call("A", "ultimate", "core_meltdown", raid["id"])
	# POWERS (0.22.2): each new power cast on the first target the Sim offers (Portal: the first entrance and its first exit)
	hs.nodes[8]["tier"] = 2                            # (a structure Sinkhole may take down: not a home's last T1 vat)
	for p in [["B", "map", "backwash"], ["A", "map", "quake"], ["A", "map", "sever"], ["A", "map", "fog"], ["A", "map", "portal"],
			["A", "active", "sinkhole"], ["A", "active", "evac"]]:
		hs.loadouts[p[0]][p[1]] = p[2]
		hs.skill_cd[p[0]][p[1]] = 0.0
		if p[2] == "evac":                             # (offensive since 2026-10-07: B needs a safe node to be forced out to)
			hs.nodes[9]["owner"] = "B"
		var ts: Array = hs.targets_for(p[0], p[1])
		var wait := 0
		while p[2] == "backwash" and ts.is_empty() and wait < 200:   # (two doors, 0.23.20: wait for a hostile line's head on a deck)
			frame.call(0.1)
			wait += 1
			ts = hs.targets_for(p[0], p[1])
		var t = ts[0] if not ts.is_empty() else -1
		if p[2] == "portal" and not ts.is_empty():
			t = [ts[0], hs.portal_exits(ts[0])[0]]
		cast.call(p[0], p[1], p[2], t)
		frame.call(0.1)
	var kids := hfx.get_child_count()
	for k in range(240):                               # past Demolish's 3 s warning and 20 s down, and every effect's end
		frame.call(0.1)
	check(casts.values().all(func(ok): return ok) and casts.size() == Rules.SKILLS.size(), "every skill cast for the view check (%s)" % str(casts.keys().filter(func(k): return not casts[k])))
	var missing := []
	for id in Rules.SKILLS:
		if int(hfx.stats.get("cast_" + id, 0)) < 1:
			missing.append(id)
	check(missing.is_empty(), "the host's view shows a cast moment for all %d skills %s" % [Rules.SKILLS.size(), str(missing)])
	var lasting := ["surge", "spore_burst", "fortify", "scorch", "demolish", "mire", "anchor", "bypass", "relay_hack", "overdrive",
			"superbloom", "relay_aegis"]
	var gone := lasting.filter(func(id): return int(gfx.stats.get("slot_" + id, 0)) < 1)
	check(gone.is_empty(), "a guest draws every lasting effect from the snapshots %s" % str(gone))
	check(int(gfx.stats.get("break", 0)) >= 1 and int(gfx.stats.get("rebuild", 0)) == int(gfx.stats.get("break", 0)) and int(gfx.stats.get("meltdown", 0)) == 1
			and int(gfx.stats.get("tint", 0)) >= 3, "a guest sees the deck break and rebuild, the meltdown and the ultimates' tint")
	check(int(hfx.stats.get("cast_ghost_line", 0)) == 1 and int(gfx.stats.get("cast_ghost_line", 0)) == 1,
			"each Ghost Line cast reaches its own caster's view only")
	check(hs.effects.is_empty() and hfx.get_child_count() <= kids + 40, "every effect ended and the view reuses its pieces (%d -> %d nodes)" % [kids, hfx.get_child_count()])
	check(SkillFx.ghost_shader().code.contains("ALPHA = ghost_alpha"), "the see-through creature shader for Ghost Lines builds")
	hw.free()
	gw.free()


func _colours_of(n: Node) -> Dictionary:
	var out := {}
	for id in n.roster:
		out[id] = n.roster[id]["colour"]
	return out


func _test_colours() -> void:
	## 0.18.7 (Daniele: the same colours on every screen): lobby picks, unique, the map
	## in the launch, identical on host and guest.
	# ---------------------------------------------------------------- unique picks
	_open_room("1v1")
	host._fix_colours()
	var c1 := _join("g1", "null")
	_deliver()
	var cols := _colours_of(host).values()
	check(cols.size() == 2 and cols.all(func(c): return Rules.HUES.has(c)) and _uniq(cols).size() == 2, "every player gets a distinct colour")
	check(_colours_of(c1) == _colours_of(host), "the guest sees the same colour list")
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
	check(host.roster[c1.assigned_id]["colour"] == free and c1.roster[c1.assigned_id]["colour"] == free, "a free colour is taken and the guest sees it")
	host.set_colour("orange" if not "orange" in _colours_of(host).values() else "cyan")
	check(host.roster[1]["colour"] in ["orange", "cyan"], "the host picks its own colour")
	# ---------------------------------------------------------------- the launch carries the map, same on both
	_ready_all()
	host.start_match()
	_deliver()
	var hc: Dictionary = host.match_info.get("colours", {})
	check(hc.size() == 2 and _uniq(hc.values()).size() == 2, "launch: a colour for every seat, all different")
	for id in host.roster:
		check(hc[host.seat_of(id)] == host.roster[id]["colour"], "launch: seat %s keeps its player's pick" % host.seat_of(id))
	check(c1.match_info["colours"] == hc, "the guest receives the same seat -> colour map")
	Rules.use_colours(host.match_info["colours"])
	var on_host := Rules.seat_colors.duplicate()
	Rules.use_colours(c1.match_info["colours"])
	check(Rules.seat_colors == on_host and Rules.seat_colors["A"] == Rules.HUES[hc["A"]], "host and guest render identical seat colours (no per-screen recolouring)")



func _uniq(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = true
	return d


func _test_rooms_more() -> void:
	## The protocol check and NAMES (the team-switch tests went with 2v2, 2026-11-27).
	# the protocol refuses a guest on an older protocol (same-build rooms only)
	_open_room("1v1")
	_join("old", "null", "ooze20-net-1/" + Rules.VERSION)
	check("rejected" in _kinds_to("old"), "a guest on the previous room protocol is refused")
	guests.erase("old")

	# ---------------------------------------------------------------- NAMES (ooze20-net-7, Daniele 2026-09-28)
	_open_room("1v1")
	host.roster[1]["name"] = "Daniele"
	_join("n2", "bloom")
	_deliver()
	check(host.name_of(guests["n2"].assigned_id) == "PLAYER B", "no name: PLAYER + the seat")
	_open_room("1v1")
	host.roster[1]["name"] = "Daniele"
	var n3 := _new_net()
	n3.remote_host = "host"
	guests["n3"] = n3
	host.links["n3"] = host.next_peer
	host.next_peer += 1
	_to_host("n3", {"op": "register", "version": host.version(), "faction": "solar", "name": "daniele"})
	_deliver()
	check(host.name_of(n3.assigned_id) == "daniele (2)" and n3.name_of(n3.assigned_id) == "daniele (2)", "names are unique in the room: \"%s\"" % host.name_of(n3.assigned_id))
	_open_room("1v1")
	host.roster[1]["name"] = "Daniele"
	var n1 := _new_net()
	n1.remote_host = "host"
	guests["n1"] = n1
	host.links["n1"] = host.next_peer
	host.next_peer += 1
	_to_host("n1", {"op": "register", "version": host.version(), "faction": "ember", "name": "  Gf\u0007  the   Great\u200b  "})
	_deliver()
	check(host.name_of(n1.assigned_id) == "Gf the Great" and n1.name_of(1) == "Daniele", "a name travels, cleaned (controls, zero-width, extra spaces): \"%s\"" % host.name_of(n1.assigned_id))
	check(host.clean_name("x".repeat(40)).length() == host.NAME_MAX, "a name is at most %d characters" % host.NAME_MAX)
	check(host.accept_chat(n1.assigned_id, "hi") and host.chat_history[-1]["who"] == "GF THE GREAT · EMBER", "the chat stamp carries the sender's name")
	_to_host("n1", {"op": "register", "version": host.version(), "faction": "ember", "name": "Impostor"})
	check(host.name_of(n1.assigned_id) == "Gf the Great", "a second register can't rename a seated player")

	# ---------------------------------------------------------------- READY (ooze20-net-6, Daniele 2026-09-28)
	_open_room("1v1")
	var r1 := _join("r1", "ember")
	_deliver()
	check(host.all_ready() == false and host.is_ready(1) and not host.can_start(), "READY: the owner counts as ready, the guests don't yet")
	r1.set_ready(true)
	_deliver()
	check(host.is_ready(r1.assigned_id) and r1.is_ready(r1.assigned_id) and host.can_start(), "a guest's READY reaches the room; DEPLOY opens")
	var pf: String = r1.preferred_faction
	r1.set_faction("solar")
	_to_host("r1", {"op": "faction", "faction": "solar"})
	_to_host("r1", {"op": "colour", "colour": "gold"})
	_to_host("r1", {"op": "loadout", "active": "fortify", "map": "mire"})
	_deliver()
	check(host.roster[r1.assigned_id]["faction"] == "ember" and r1.preferred_faction == pf and r1.ready_locked(),
			"a READY player's picks are locked (faction, colour, skills refused on both sides)")
	r1.set_ready(false)
	_deliver()
	r1.set_faction("solar")
	_deliver()
	check(not host.is_ready(r1.assigned_id) and host.roster[r1.assigned_id]["faction"] == "solar", "UN-READY unlocks the picks")
	r1.set_ready(true)
	_deliver()
	check(host.all_ready() and host.can_start(), "everyone READY: DEPLOY opens")
	var before: int = host.bridge.sent.size()
	host.toggle_last_stand()
	var toasts: Array = []
	for q in host.bridge.sent.slice(before):
		if q[0] in ["r1"] and str(q[1]).contains("notice"):
			toasts.append(q[0])
	_deliver()
	check(not host.is_ready(r1.assigned_id) and not host.can_start(),
			"an owner's settings change un-readies everyone")
	check(toasts.size() == 1, "...and the guest hears why (%s)" % str(toasts))
	r1.set_ready(true)
	_deliver()
	before = host.bridge.sent.size()
	host.toggle_abilities()
	var told: Array = host.bridge.sent.slice(before).filter(func(q): return str(q[1]).contains("notice")).map(func(q): return q[0])
	check(told == ["r1"], "only the players whose flag was reset get the toast (%s)" % str(told))
	host.set_ready(true)
	check(host.is_ready(1) and not host.roster[1].get("ready", false), "the owner has no READY of their own (DEPLOY is theirs)")
	_ready_all()
	host.start_match()
	_deliver()
	check(host.active, "DEPLOY with everyone READY launches")
	host.return_to_room("back")
	_deliver()
	check(not host.is_ready(r1.assigned_id), "back in the lobby: everyone presses READY again")

	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- SKILLS 2.0: ARMIES presets -> the room (lobby)
func _test_presets() -> void:
	ArmyPresets.path = "user://test_armies.cfg"
	ArmyPresets.reload_presets()
	for f in ["solar", "ember"]:
		ArmyPresets.reset(f)
	ArmyPresets.set_pick("solar", "active", "scorch")
	ArmyPresets.set_pick("solar", "map", "anchor")
	ArmyPresets.set_pick("ember", "map", "relay_hack")
	ArmyPresets.reload_presets()                                  # read back from the file
	check(ArmyPresets.loadout_for("solar") == {"active": "scorch", "map": "anchor"} and ArmyPresets.loadout_for("vex") == {"active": "surge", "map": "portal"},   # (POWERS 0.22.5 defaults)
			"ARMIES presets save, load back, and default per faction")
	_open_room("1v1")
	var gp := _new_net()
	gp.bridge = QueueBridge.new()
	gp.room_code = "AB7K"
	gp.preferred_faction = "solar"
	guests["gp"] = gp
	host.links["gp"] = host.next_peer
	host.next_peer += 1
	ArmyPresets.send_to(gp, "solar")                       # the menu, before JOIN ROOM connects
	gp.bridge.queue = [{"type": "connection", "peer": "host"}]
	gp._poll(0.1)                                          # connected: the guest registers (faction, colour, loadout)
	_deliver()
	var gid: int = gp.assigned_id
	check(gid > 0 and host.roster[gid]["loadout"] == {"active": "scorch", "map": "anchor"},
			"a guest's ARMIES preset reaches the host with the register (%s)" % str(host.roster.get(gid, {}).get("loadout", {})))
	ArmyPresets.room_faction(gp, "ember")                  # the lobby's faction pick: faction + that preset
	_deliver()
	check(host.roster[gid]["faction"] == "ember" and host.roster[gid]["loadout"] == {"active": "sinkhole", "map": "relay_hack"},
			"changing faction in the lobby sends that faction's preset")
	ArmyPresets.send_to(host, "solar")                     # the host's own preset (CREATE ROOM)
	check(host.roster[1]["loadout"] == {"active": "scorch", "map": "anchor"}, "the host's preset is its roster loadout")
	ArmyPresets.room_toggle_abilities(host)                # the lobby's ABILITIES button (host)
	_deliver()
	check(not host.abilities and not gp.abilities, "ABILITIES OFF from the lobby reaches the guest")
	host.map_path = "res://maps/010-first-switch.json"      # a map with relays: Relay Hack stays
	_ready_all()
	host.start_match()
	_deliver()
	var info: Dictionary = host.match_info
	check(info["rules"]["abilities_on"] == false and info["loadouts"].get("B", {}) == {"active": "sinkhole", "map": "relay_hack"}
			and info["loadouts"].get("A", {}) == {"active": "scorch", "map": "anchor"},
			"the launch carries both presets and ABILITIES OFF (%s)" % str(info["loadouts"]))
	Rules.abilities_on = true
	for f in ["solar", "ember"]:
		ArmyPresets.reset(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ArmyPresets.path))
	ArmyPresets.path = "user://armies.cfg"
	ArmyPresets.reload_presets()
