extends SceneTree
## OOZE 3.0 (WP5, ooze20-net-9): a whole online 1v1 on a joint map, headless, to the end.
##   Godot --headless --path . --script res://tests/test_net9_match.gd [-- --map=res://maps4/Z-02-clusters.json --ai=Standard]
## A host Net and a guest Net talk through test_net's fake transport (the real envelopes: JSON + base64 + deflate, the
## real delta snapshots). The AI plays both seats on the host's Sim (an online room's empty seats); the guest's Sim only
## follows the snapshots, as in a browser. Exit 0 = the match ended and the guest shows the host's winner and quota.

class FakeBridge:
	extends RefCounted
	var sent: Array = []
	func start(_host, _code) -> void: pass
	func send(remote, data) -> bool:
		sent.append([str(remote), str(data)])
		return true
	func close() -> void: pass
	func closePeer(_remote) -> void: pass
	func poll() -> String: return "[]"

const DT := 0.05                                   # the server host's step (main: minf(delta, 0.05))
const MAX_T := 1500.0                              # s of match time before the test gives up

var failures := 0
var host: Node
var guest: Node


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


func _deliver() -> void:
	for i in range(3):
		var out: Array = host.bridge.sent
		host.bridge.sent = []
		for p in out:
			if p[0] == "g1":
				guest._guest_receive(p[1])
		var back: Array = guest.bridge.sent
		guest.bridge.sent = []
		for q in back:
			host._host_receive("g1", q[1])


func _build_sim(info: Dictionary) -> Sim:
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), info.get("loadouts", {}))
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()
	m.sim = s
	return m


func _run() -> void:
	var map_path := "res://maps4/Z-02-clusters.json"   # Z-02 = lab L09C: clusters joined by joint edges
	var level := "Standard"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_path = a.substr(6)
		elif a.begins_with("--ai="):
			level = a.substr(5)
	var map := MapBuilder.load_map(map_path)
	var joints: int = (map["edges"] as Array).filter(func(e): return e.get("joint", false)).size()
	check(joints > 0, "the map %s has joint edges (%d)" % [map_path.get_file(), joints])
	check(Rules.quota and Rules.JOINTS, "the 3.0 rules are on (Last Stand = quota, joints)")

	host = _new_net()
	host.hosting = true
	host.connected = true
	host.room_code = "AB7K"
	host.mode = "1v1"
	host.map_path = map_path
	host.roster = {1: {"faction": "vex", "slot": 0}}
	host.room_owner = 1
	guest = _new_net()
	guest.remote_host = "host"
	guest.room_code = "AB7K"
	host.links["g1"] = host.next_peer
	host.next_peer += 1
	host._host_receive("g1", JSON.stringify({"op": "register", "version": host.version(), "faction": "null"}))
	_deliver()
	check(guest.assigned_id > 1, "the guest is in the room on %s" % host.version())
	guest.set_ready(true)
	_deliver()
	host.start_match()
	_deliver()
	check(guest.active and guest.match_round == host.match_round, "the guest got the launch")
	var hs := _build_sim(host.match_info)
	var gs := _build_sim(guest.match_info)
	host.world_ready(hs, _fake_main(hs))
	guest.world_ready(gs, _fake_main(gs))
	_deliver()
	check(host.started and guest.started, "both ends begin the round")
	var ais := []
	for seat in hs.factions:
		ais.append(SeatAI.new(seat, 2.5, level))     # the room's AI plays both seats on the host (the guest only watches)
	var after := 0
	var t0 := Time.get_ticks_msec()
	while hs.time < MAX_T:
		for ai in ais:
			ai.think(hs, DT)
		hs.step(DT)
		hs.fx_events.clear()
		host._process(DT)
		_deliver()
		guest._process(DT)
		if hs.over:
			after += 1
			if after > 40:                             # 2 s of end screen: the frozen state's slow resend is in
				break
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	print("      match: %.1f s of play in %.1f s wall, host winner '%s', quota %s (%s, last side '%s')"
			% [hs.time, wall, hs.winner, str(hs.quota), hs.quota_reason, hs.quota_last_side])
	print("      guest: over %s, winner '%s', quota %s (%s, last side '%s'); snapshots received %d"
			% [str(gs.over), gs.winner, str(gs.quota), gs.quota_reason, gs.quota_last_side, guest._rx_snaps])
	check(hs.over, "the match ends within %d s (%.1f s)" % [int(MAX_T), hs.time])
	check(gs.over and gs.winner == hs.winner, "the guest shows the host's winner ('%s' / '%s')" % [gs.winner, hs.winner])
	var gq := {}
	for k in gs.quota:
		gq[k] = int(round(float(gs.quota[k])))
	var hq := {}
	for k in hs.quota:
		hq[k] = int(round(float(hs.quota[k])))
	check(gq == hq and gs.quota_reason == hs.quota_reason and gs.quota_last_side == hs.quota_last_side,
			"the guest shows the host's quota (%s / %s)" % [str(gq), str(hq)])
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
