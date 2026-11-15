extends SceneTree
## LAST STAND = QUOTA (Rules.quota, Daniele 2026-11-15; demo prototype):
##   Godot --headless --path . --script res://tests/test_quota.gd
## Scoring at liftoff (seat / team / neutral), the unreachable-lead end (1v1 and FFA), the last-platform tie-break, a
## neutral last platform (DRAW), the Very Last Stand running down to the last platform, and quota OFF untouched.

var failures := 0
const MAP := "res://maps4/G-01-gate.json"


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _sim(seats: Dictionary, teams := {}) -> Sim:
	var m := MapBuilder.load_map(MAP)
	var sim := Sim.new()
	var facs := {}
	var pool := ["null", "ember", "null", "ember"]
	var k := 0
	for id in seats:
		facs[seats[id]] = pool[k % pool.size()]
		k += 1
	sim.setup(m, MapBuilder.layout(m), seats, facs, 3, teams)
	sim.last_stand_active = true                      # scoring only matters once the Last Stand runs
	return sim


func _homes() -> Array:
	var m := MapBuilder.load_map(MAP)
	var out := []
	for s in m["seats"]["1v1"]:
		out.append(int(s["node"]))
	return out


func _others(sim: Sim, skip: Array) -> Array:
	var out := []
	for n in sim.nodes:
		if not (n["id"] in skip):
			out.append(n["id"])
	return out


func _collapse_all_but(sim: Sim, keep: Array) -> void:
	## Marks every other platform as launched without scoring (a test shortcut).
	for n in sim.nodes:
		if not (n["id"] in keep):
			sim.collapsed[n["id"]] = true


func _init() -> void:
	Rules.quota = true
	var h := _homes()
	var a: int = h[0]
	var b: int = h[1]

	# 1. a launch pays its owner 1 at liftoff; neutral pays nobody
	var sim := _sim({a: "A", b: "B"})
	var free := _others(sim, [a, b])
	sim.nodes[free[0]]["owner"] = "A"
	sim.nodes[free[0]]["units"] = 20.0
	sim._drop_node(free[0])
	check(sim.quota_of("A") == 1 and sim.quota_of("B") == 0, "seat launch: A +1 (A %d, B %d)" % [sim.quota_of("A"), sim.quota_of("B")])
	check(sim.events.any(func(e): return e["type"] == "launch" and e["node"] == free[0] and e["seat"] == "A"), "launch event names the owner")
	check(sim.fx_events.any(func(e): return e["type"] == "collapse" and bool(e.get("launch", false))), "the view gets a launch (not a plain collapse)")
	check(sim.collapsed.get(free[0], false) and sim.nodes[free[0]]["owner"] == "" and sim.nodes[free[0]]["units"] == 0.0, "the platform is gone, its garrison splats")
	check(float(sim.fall_losses.get("A", 0.0)) >= 20.0, "the garrison counts as fallen (splat en masse)")
	sim.nodes[free[1]]["owner"] = ""
	sim._drop_node(free[1])
	check(sim.quota_of("A") == 1 and sim.quota_of("B") == 0 and str(sim.quota_last_side) == "", "neutral launch pays nobody")
	check(not sim.over, "no end with a 1-point lead and %d to launch" % sim.quota_left())

	# 2. team mode: a launch scores for the team
	var c: int = free[2]
	var d: int = free[3]
	sim = _sim({a: "A", b: "B", c: "C", d: "D"}, {"A": 0, "C": 0, "B": 1, "D": 1})
	free = _others(sim, [a, b, c, d])
	sim.nodes[free[0]]["owner"] = "C"
	sim._drop_node(free[0])
	check(sim.quota_of("A") == 1 and sim.quota_of("C") == 1 and sim.quota_of("B") == 0, "team launch: C scores for team A+C")

	# 3. unreachable lead ends it (1v1): lead > platforms left; lead == left keeps playing
	sim = _sim({a: "A", b: "B"})
	free = _others(sim, [a, b])
	_collapse_all_but(sim, [a, b, free[0], free[1]])   # 4 left
	sim.quota = {"A": 4, "B": 0}
	sim.step(0.05)
	check(not sim.over, "lead 4 = 4 left: the match goes on")
	sim.quota = {"A": 5, "B": 0}
	sim.step(0.05)
	check(sim.over and sim.winner == "A" and sim.quota_reason == "unreachable", "lead 5 > 4 left: A wins on quota (over %s, winner '%s', %s)" % [sim.over, sim.winner, sim.quota_reason])

	# 4. FFA: the leader against the best other side
	sim = _sim({a: "A", b: "B", c: "C"})
	free = _others(sim, [a, b, c])
	_collapse_all_but(sim, [a, b, c])                  # 3 left
	sim.quota = {"A": 5, "B": 2, "C": 1}
	sim.step(0.05)
	check(not sim.over, "FFA lead 3 (over B) = 3 left: goes on")
	sim.quota = {"A": 6, "B": 2, "C": 5}
	sim.step(0.05)
	check(not sim.over, "FFA A 6 B 2 C 5: lead 1 over C, goes on")
	sim.quota = {"A": 7, "B": 2, "C": 3}
	sim.step(0.05)
	check(sim.over and sim.winner == "A", "FFA lead 4 over the best other > 3 left: A wins")

	# 5. last platform: a tie goes to its holder (it scores, so the holder wins); elimination by the launch is not first
	sim = _sim({a: "A", b: "B"})
	_collapse_all_but(sim, [b])
	sim.nodes[a]["owner"] = ""                         # A holds nothing now but a line keeps it in (no elimination)
	sim.quota = {"A": 3, "B": 2}
	sim.quota_last_side = "A"
	sim.hordes.append({"owner": "A", "decoy": false, "units": 5.0, "target": a, "route": [a], "node_spans": [], "spans": [], "L": 1.0})
	sim._drop_node(b)                                  # B launches the last platform: 3 - 3, B held it
	check(sim.over and sim.winner == "B" and sim.quota_reason == "final", "3-3 after the last launch: its holder B wins (over %s, winner '%s', %s)" % [sim.over, sim.winner, sim.quota_reason])
	check(sim.quota_of("B") == 3, "the last launch scored for B")

	# 6. a neutral last platform on a tie: DRAW
	sim = _sim({a: "A", b: "B"})
	_collapse_all_but(sim, [b])
	sim.nodes[b]["owner"] = ""
	sim.quota = {"A": 2, "B": 2}
	sim.hordes.append({"owner": "A", "decoy": false, "units": 5.0, "target": a, "route": [a], "node_spans": [], "spans": [], "L": 1.0})
	sim.hordes.append({"owner": "B", "decoy": false, "units": 5.0, "target": a, "route": [a], "node_spans": [], "spans": [], "L": 1.0})
	sim._drop_node(b)
	check(sim.over and sim.winner == "" and sim.draw_line != "", "2-2 with a neutral last platform: DRAW (winner '%s')" % sim.winner)

	# 7. a side's own launch banks its winning point before the elimination check
	sim = _sim({a: "A", b: "B"})
	free = _others(sim, [a, b])
	_collapse_all_but(sim, [a, b, free[0], free[1]])
	sim.quota = {"A": 0, "B": 3}
	sim.nodes[a]["owner"] = ""
	sim._drop_node(b)                                  # B's last own platform: B 4, A 0, 3 left
	check(sim.over and sim.winner == "B" and sim.quota_reason == "unreachable", "B's own last launch: 4 > 3 left, B wins on quota, not out")

	# 8. the Very Last Stand runs down to the last platform (and its gap leaves QUOTA_END_SPARE)
	sim = _sim({a: "A", b: "B"})
	free = _others(sim, [a, b])
	_collapse_all_but(sim, [a, b, free[0]])
	sim.time = Rules.VERY_LAST_STAND_TIME
	sim.very_last_stand_active = true
	sim._vls_queue_next()
	var want := (Rules.MATCH_HARD_END - Rules.QUOTA_END_SPARE - Rules.VERY_LAST_STAND_TIME) / 3.0
	check(absf(sim.very_last_stand_gap - want) < 0.01, "VLS gap = time to the end minus the spare over 3 survivors (%.2f, want %.2f)" % [sim.very_last_stand_gap, want])
	_collapse_all_but(sim, [b])
	sim._vls_queue_next()
	check(sim.last_stand_warn_node == b, "QUOTA: the last platform is queued to launch too")
	Rules.quota = false
	sim._vls_queue_next()
	check(sim.last_stand_warn_node == -1, "quota OFF: the last platform never drops (unchanged)")

	# 9. quota OFF: a drop scores nothing, the 7:00 end is the old last-vat rule
	sim = _sim({a: "A", b: "B"})
	free = _others(sim, [a, b])
	sim.nodes[free[0]]["owner"] = "A"
	sim._drop_node(free[0])
	check(sim.quota.is_empty() and not sim.fx_events.any(func(e): return bool(e.get("launch", false))), "quota OFF: no score, no launch")

	# 10. a full AI match on the G map with quota ON ends, and every point came from a launch
	Rules.quota = true
	var m := MapBuilder.load_map(MAP)
	sim = Sim.new()
	sim.setup(m, MapBuilder.layout(m), {a: "A", b: "B"}, {"A": "null", "B": "ember"}, 11)
	var ais := [SeatAI.new("A", 2.5, "Standard"), SeatAI.new("B", 2.5, "Standard")]
	while not sim.over and sim.time < Rules.MATCH_HARD_END + 5.0:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
		sim.fx_events.clear()
	var launches := sim.events.filter(func(e): return e["type"] == "launch" and str(e["seat"]) != "").size()
	var total := 0
	for k2 in sim.quota:
		total += int(sim.quota[k2])
	check(sim.over, "AI match ends (t %.0f s, winner '%s', reason '%s', quota %s)" % [sim.time, sim.winner, sim.quota_reason, sim.quota])
	check(total == launches, "every quota point is one owned launch (%d = %d)" % [total, launches])

	print("test_quota: %d failure(s)" % failures)
	quit(1 if failures else 0)
