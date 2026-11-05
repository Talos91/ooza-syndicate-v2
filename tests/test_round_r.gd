extends SceneTree
## ROUND R (map round 2026-11, MAP-ROUND-2026-11.md) - the round-R hazards and relays on the R maps:
##   Godot --headless --path . --script res://tests/test_round_r.gd
## R-01 Strait: the 3-position ferry (one hull, lanes 0 / 1 / 2: exactly one lane in line at a time, order 0 1 2 1, a line
## on a lane the hull leaves falls), two mirrored laser lifts (top / bottom stone, 2 decks per level), the two plain belts. R-05 Pinwheel: the two
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
	# Daniele 2026-11-05 (Strait 1 + 2 merged): two laser LIFTS, top stone (starts DOWN: the outer roads) and bottom stone
	# (starts UP: the banks' end platforms); each drives 4 decks, 2 per level, and firing swaps the level
	var lifts := []
	for n in s.nodes:
		if n["relay"] == "lift":
			lifts.append(n)
	check(lifts.size() == 2, "R-01: two lifts (got %d)" % lifts.size())
	var starts := []
	for n in lifts:
		check(s.controlled_edges(n["id"]).size() == 4, "R-01: lift %d drives 4 decks" % n["id"])
		starts.append(int(n["relay_index"]))
		check(str(n.get("structure", n.get("neutral", {}).get("structure", ""))) != "" , "R-01: lift %d has a structure" % n["id"])
	starts.sort()
	check(starts == [0, 1], "R-01: one stone starts down, the other up (got %s)" % [starts])
	s.time = 0.0
	var lt: Dictionary = lifts[0]
	var lid: int = lt["id"]
	var open0 := s.controlled_edges(lid).filter(func(ei): return s.is_edge_open(ei))
	check(open0.size() == 2, "R-01: lift %d opens 2 decks at a time (got %d)" % [lid, open0.size()])
	lt["owner"] = "A"
	s.fire_relay(lid)
	for i in range(120):
		s.step(0.05)
	var open1 := s.controlled_edges(lid).filter(func(ei): return s.is_edge_open(ei))
	check(open1.size() == 2 and open1.filter(func(ei): return ei in open0).is_empty(), "R-01: firing lift %d swaps its decks (%s -> %s)" % [lid, open0, open1])
	check(s._belt_edges.size() == 2, "R-01: two plain belts (got %d)" % s._belt_edges.size())


func _pinwheel() -> void:
	## Daniele 2026-11-05 (proto9 review): R-05 = three rotors on the middle line (4 decks each), a 1-bridge ferry top and
	## bottom, two plain belts (top-left, bottom-right). R-11 (version B) = one rotor + two speed relays driving the outer
	## roads above / below them (2 decks each), same ferries and belts.
	for code in ["R-05", "R-11"]:
		var s := _sim(code)
		check(s != null, "%s loads" % code)
		if s == null:
			continue
		var rots := []
		var convs := []
		for n in s.nodes:
			if n["relay"] == "rotation":
				rots.append(n["id"])
			if n["relay"] == "conveyor":
				convs.append(n["id"])
		check(rots.size() == (3 if code == "R-05" else 1), "%s: rotors (got %d)" % [code, rots.size()])
		check(convs.size() == (0 if code == "R-05" else 2), "%s: speed relays (got %d)" % [code, convs.size()])
		for r in rots:
			check(s.controlled_edges(r).size() == 4, "%s: rotor %d drives 4 decks" % [code, r])
		for r in convs:                                # R-11 (Daniele's correction): 4 roads = 6 decks (2 curved roads of 2)
			check(s.controlled_edges(r).size() == 6, "%s: speed relay %d drives 6 decks (got %d)" % [code, r, s.controlled_edges(r).size()])
		if code == "R-11":
			check(s._conv_pieces.size() == 4, "R-11: 4 curve pieces are speed lanes (got %d)" % s._conv_pieces.size())
			# a line walking the left bottom pier road (P2 -> Dl, fast at the start) is pushed while on its curve
			var cv: int = s._conv_pieces.keys()[0]
			check(s.nodes[cv]["node_kind"] == "junction", "R-11: a speed curve is a junction piece")
			# a short line standing wholly ON a speed curve is pushed (Sim.conveyor_sense reads the curve with its deck)
			var pushed := 0
			for j in s._conv_pieces:
				var ends := []
				for e in s.edges:
					if e["a"] == j or e["b"] == j:
						ends.append(e["b"] if e["a"] == j else e["a"])
				var src: Dictionary = s.nodes[ends[0]]
				src["owner"] = "A"
				src["units"] = 3.0
				var h: Dictionary = s.send(ends[0], ends[1], 1.0)
				if h.is_empty():
					continue
				for ns in h["node_spans"]:
					if ns["node"] == j:
						h["s"] = (float(ns["s0"]) + float(ns["s1"])) * 0.5 + 0.01
				var keep: Dictionary = s._conv_pieces
				var on_curve: int = s.conveyor_sense(h)[0]
				s._conv_pieces = {}
				var without: int = s.conveyor_sense(h)[0]
				s._conv_pieces = keep
				if on_curve != 0 and without == 0:
					pushed += 1
			check(pushed == 4, "R-11: a line wholly on each speed curve is pushed (got %d of 4)" % pushed)
		var ones := s._ferry_plain.values().filter(func(f): return not (f as Dictionary).has("group"))
		check(s._ferry_plain.size() == 2 and ones.size() == 2, "%s: two 1-bridge ferries (got %d)" % [code, s._ferry_plain.size()])
		check(s._belt_edges.size() == (2 if code == "R-05" else 0), "%s: plain belts (got %d)" % [code, s._belt_edges.size()])


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
		# Daniele 2026-11-05: the hub speed relay joined six ways, its four side decks speed / slow (alternated); each
		# gatehouse also linked to its lower outer corner (5 decks: home, both corners, both doors)
		for n in s.nodes:
			var deg := s.edges.filter(func(e): return e["a"] == n["id"] or e["b"] == n["id"]).size()
			if n["relay"] == "conveyor":
				check(deg == 6, "R-02: the hub has 6 decks (got %d)" % deg)
				check(s.controlled_edges(n["id"]).size() == 4, "R-02: the hub drives its 4 side decks (got %d)" % s.controlled_edges(n["id"]).size())
			if n["relay"] == "retract":
				check(deg == 5, "R-02: gatehouse %d has 5 decks (got %d)" % [n["id"], deg])
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
	for code in ["R-01", "R-02", "R-04", "R-05", "R-11"]:   # R-03 merged into R-01 (Daniele 2026-11-05)
		_play(code)
	print("test_round_r: %d checks, %d failed" % [checks, fails])
	print("ALL PASSED" if fails == 0 else "FAILED")
	quit(1 if fails else 0)
