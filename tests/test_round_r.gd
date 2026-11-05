extends SceneTree
## ROUND R (map round 2026-11, MAP-ROUND-2026-11.md) - the round-R hazards and relays on the R maps:
##   Godot --headless --path . --script res://tests/test_round_r.gd
## R-01 Strait: the 3-position ferry (one hull, lanes 0 / 1 / 2: exactly one lane in line at a time, order 0 1 2 1, a line
## on a lane the hull leaves falls), the retract pulling 2 decks at once, the two plain belts. R-05 Pinwheel: the two
## speed relays (conveyor relays) flip, the rotor, the 1-bridge ferry hazard. Both maps play to the end with two AIs.

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)


func _sim(code: String) -> Sim:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			var m := MapBuilder.load_map("res://maps4/" + f)
			var seats := {}
			for st in m["seats"]["1v1"]:
				seats[int(st["node"])] = str(st["seat"])
			var s := Sim.new()
			s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
			return s
	return null


func _strait() -> void:
	var s := _sim("R-01")
	check(s != null, "R-01 loads")
	if s == null:
		return
	check(s._ferry_groups.has("F"), "R-01: ferry group F set up")
	var lanes: Dictionary = s._ferry_groups["F"]["decks"]
	check(lanes.size() == 3, "R-01: the ferry serves 3 lanes (got %d)" % lanes.size())
	check(s._ferry_groups["F"]["seq"] == [0, 1, 2, 1], "R-01: lane order up, mid, down, mid (got %s)" % [s._ferry_groups["F"]["seq"]])
	var slot := s.ferry3_slot("F")
	var order: Array = []
	var both := 0
	var t := 0.0
	while t < float(slot["period"]) * 2.0:
		s.time = t
		var open: Array = []
		for pos in lanes:
			if not s.ferry_edge_out(int(lanes[pos])):
				open.append(pos)
		if open.size() > 1:
			both += 1
		if open.size() == 1 and (order.is_empty() or order[-1] != open[0]):
			order.append(open[0])
		t += 0.05
	check(both == 0, "R-01: never two lanes in line at once (%d samples)" % both)
	check(order.slice(0, 5) == [0, 1, 2, 1, 0], "R-01: lanes open in turn 0 1 2 1 0 (got %s)" % [order])
	print("R-01 ferry: open %.1f s, move %.1f s, period %.1f s" % [slot["open"], slot["move"], slot["period"]])
	# readout numbers: next_open counts down to the lane's turn
	s.time = 0.0
	var ph: Dictionary = s.ferry_phase_e(int(lanes[2]))
	check(ph["part"] != "open" and float(ph["next_open"]) > float(slot["slot"]) * 1.5, "R-01: the down lane waits ~2 slots at t 0 (%s)" % [ph])
	# retract: one relay, two decks
	var rid := -1
	for n in s.nodes:
		if n["relay"] == "retract":
			rid = n["id"]
	var mine: Array = s.controlled_edges(rid)
	check(mine.size() == 2, "R-01: the retract drives 2 decks (got %d)" % mine.size())
	s.time = 0.0
	for ei in mine:
		check(s.is_edge_open(ei), "R-01: retract deck %d starts out" % ei)
	s.nodes[rid]["owner"] = "A"
	s.fire_relay(rid)
	for i in range(80):
		s.step(0.05)
	for ei in mine:
		check(not s.is_edge_open(ei), "R-01: retract deck %d pulled in after the fire" % ei)
	check(s._belt_edges.size() == 2, "R-01: two plain belts (got %d)" % s._belt_edges.size())


func _pinwheel() -> void:
	var s := _sim("R-05")
	check(s != null, "R-05 loads")
	if s == null:
		return
	var conv := 0
	var rot := -1
	for n in s.nodes:
		if n["relay"] == "conveyor":
			conv += 1
		if n["relay"] == "rotation":
			rot = n["id"]
	check(conv == 2, "R-05: two speed relays (got %d)" % conv)
	check(s._conv_edges.size() == 2, "R-05: two speed decks (got %d)" % s._conv_edges.size())
	check(s._ferry_plain.size() == 1 and not (s._ferry_plain.values()[0] as Dictionary).has("group"), "R-05: one 1-bridge ferry hazard")
	check(rot >= 0 and s.controlled_edges(rot).size() == 4, "R-05: the rotor drives 4 decks")


func _gates() -> void:
	## R-02 Gate: each gatehouse is a retract relay pulling BOTH its doors (2 decks); R-03: three 1-bridge ferries.
	var s := _sim("R-02")
	check(s != null, "R-02 loads")
	if s != null:
		var n_ret := 0
		for n in s.nodes:
			if n["relay"] == "retract":
				n_ret += 1
				check(s.controlled_edges(n["id"]).size() == 2, "R-02: gatehouse %d pulls 2 doors" % n["id"])
		check(n_ret == 2, "R-02: two gatehouses (got %d)" % n_ret)
	var r3 := _sim("R-03")
	check(r3 != null and r3._ferry_plain.size() == 3 and r3._ferry_groups.is_empty(), "R-03: three 1-bridge ferries")
	## R-04 Gate 2: each waist gatehouse pulls its top door and its waist door (2 decks); its bottom door and home road stay.
	var r4 := _sim("R-04")
	check(r4 != null, "R-04 loads")
	if r4 != null:
		var gates: Array = []
		for n in r4.nodes:
			if n["relay"] == "retract":
				gates.append(n["id"])
		check(gates.size() == 2, "R-04: two gatehouses (got %d)" % gates.size())
		check(r4._belt_edges.size() == 2, "R-04: two plain belts (got %d)" % r4._belt_edges.size())
		for g in gates:
			var doors: Array = r4.controlled_edges(g)
			check(doors.size() == 2, "R-04: gatehouse %d pulls 2 doors (got %d)" % [g, doors.size()])
			var fixed := 0
			for ei in range(r4.edges.size()):
				var e: Dictionary = r4.edges[ei]
				if (int(e["a"]) == g or int(e["b"]) == g) and not (ei in doors):
					fixed += 1
			check(fixed >= 2, "R-04: gatehouse %d keeps %d fixed decks" % [g, fixed])
			r4.time = 0.0
			for ei in doors:
				check(r4.is_edge_open(ei), "R-04: door %d starts out" % ei)
			r4.nodes[g]["owner"] = "A"
			r4.fire_relay(g)
		for i in range(80):
			r4.step(0.05)
		for g in gates:
			for ei in r4.controlled_edges(g):
				check(not r4.is_edge_open(ei), "R-04: door %d pulled in after the fire" % ei)


func _play(code: String) -> void:
	var m := {}
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			m = MapBuilder.load_map("res://maps4/" + f)
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "vex", "B": "vex"}, 7)
	var ais := [SeatAI.new("A", 2.0, "Standard"), SeatAI.new("B", 2.0, "Standard")]
	var t := 0.0
	while t < 480.0 and s.winner == "":
		for ai in ais:
			ai.think(s, 0.1)
		s.step(0.1)
		t += 0.1
	check(s.winner != "" or t >= 480.0, "%s: a match runs (winner %s at %.0f s)" % [code, s.winner, t])
	print("%s AI match: winner '%s' at %.0f s" % [code, s.winner, t])


func _init() -> void:
	_strait()
	_pinwheel()
	_gates()
	for code in ["R-01", "R-02", "R-03", "R-04", "R-05"]:
		_play(code)
	print("test_round_r: %d checks, %d failed" % [checks, fails])
	print("ALL PASSED" if fails == 0 else "FAILED")
	quit(1 if fails else 0)
