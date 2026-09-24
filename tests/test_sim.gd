extends SceneTree
## Headless rules check:  Godot --headless --path . --script res://tests/test_sim.gd
## Exit code 0 = all passed.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	var map := MapBuilder.load_map("res://maps/004-two-piers.json")
	var pos := MapBuilder.layout(map)
	check(pos.size() == 5, "Two Piers lays out 5 nodes")
	for e in map["edges"]:
		var d: float = (pos[int(e["from"])] as Vector3).distance_to(pos[int(e["to"])])
		var want := Rules.span({"S": 1, "M": 2, "L": 3}[e["tier"]])
		check(absf(d - want) < 0.01, "edge %s-%s honest length %.1f m" % [e["from"], e["to"], want])

	var sim := Sim.new()
	sim.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	check(sim.nodes[3]["owner"] == "A" and sim.nodes[4]["owner"] == "B", "homes owned")
	var route := sim.find_route(3, 4)
	check(route == [3, 1, 0, 2, 4], "route home A -> home B passes 1, 0, 2")

	# a send to the neighbouring neutral node captures it
	var h := sim.send(3, 1, 1.0)
	check(not h.is_empty() and h["units"] == 80.0, "send 100% of 80")
	var path_len: float = h["L"]
	check(path_len > Rules.span(2) - 2.0 * Rules.R, "path length %.1f m" % path_len)
	var t := 0.0
	while t < 20.0 and sim.nodes[1]["owner"] != "A":
		sim.step(0.05)
		t += 0.05
	check(sim.nodes[1]["owner"] == "A", "neutral node 1 captured by A after %.1f s" % t)
	while not sim.hordes.is_empty():
		sim.step(0.05)
	check(absf(sim.nodes[1]["units"] - (80.0 - 30.0)) < 8.0, "after the whole horde is in, garrison ~50 (got %.1f)" % sim.nodes[1]["units"])

	# travel time: an M deck is 4 s at base speed, nodes crossed fast
	var sim2 := Sim.new()
	sim2.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	var h2 := sim2.send(3, 1, 0.5)
	var arrive := 0.0
	while h2["state"] == "move" and arrive < 30.0:
		sim2.step(0.02)
		arrive += 0.02
	check(arrive > 4.0 and arrive < 6.0, "M deck crossing takes %.2f s (4 s deck + <2 s node time)" % arrive)

	# two opposing hordes on the same deck meet at a frontline
	var sim3 := Sim.new()
	sim3.setup(map, pos, {1: "A", 0: "B"}, {"A": "null", "B": "ember"})
	sim3.nodes[1]["units"] = 100.0
	sim3.nodes[0]["units"] = 100.0
	sim3.send(1, 0, 1.0)
	sim3.send(0, 1, 0.5)
	var fought := false
	for k in range(400):
		sim3.step(0.05)
		for x in sim3.hordes:
			if x["state"] == "fight":
				fought = true
	check(fought, "frontline fight happens on the shared S deck")
	check(sim3.hordes.size() <= 1, "one side survives the frontline")
	check(sim3.combat_losses.size() == 2, "both sides lost units in combat")

	# rear attack: an enemy catching up from behind hits the slower horde's tail
	var sim5 := Sim.new()
	sim5.setup(map, pos, {1: "A", 3: "B"}, {"A": "null", "B": "ember"})
	sim5.nodes[1]["units"] = 120.0
	sim5.nodes[3]["units"] = 200.0
	var slow := sim5.send(1, 0, 1.0)
	slow["speed"] = 0.2                                # e.g. slowed - it will be caught
	sim5.send(3, 0, 1.0)
	var rear := false
	for k in range(600):
		sim5.step(0.05)
		if sim5.events.any(func(e): return e["type"] == "rear"):
			rear = true
			break
	check(rear, "enemy catching up from behind makes a rear attack")
	check(sim5.fights.size() == 1 and slow["state"] == "fight", "the caught horde is fighting its pursuer")

	# friendly queue: a faster friend behind cannot pass through, it waits at the tail
	var sim6 := Sim.new()
	sim6.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	sim6.nodes[3]["units"] = 240.0
	var front := sim6.send(3, 1, 0.5)
	front["speed"] = 0.25
	while front["s"] < front["spans"][0]["s0"] + 3.0:  # the slow one is out on the deck first
		sim6.step(0.05)
	var behind := sim6.send(3, 1, 1.0)
	var queued := false
	var overtook := false
	for k in range(400):
		sim6.step(0.05)
		if behind.get("blocked", false):
			queued = true
		var deck: Dictionary = behind["spans"][0]
		var on_deck: bool = behind["s"] >= deck["s0"] and behind["s"] <= deck["s1"]
		if on_deck and front in sim6.hordes and behind["s"] > front["s"]:
			overtook = true
	check(queued, "friendly horde queues behind a slower friend on the same deck")
	check(not overtook, "and never passes through it on the deck (platforms: next pass)")

	# AI vs AI finishes a match
	var sim4 := Sim.new()
	sim4.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	var a := SeatAI.new("A", 2.0)
	var b := SeatAI.new("B", 2.5)
	var steps := 0
	while not sim4.over and steps < 20 * 60 * 10:
		a.think(sim4, 0.1)
		b.think(sim4, 0.1)
		sim4.step(0.1)
		steps += 1
	print("      AI vs AI: over=%s winner=%s at %.0f s, captures=%d" % [sim4.over, sim4.winner, sim4.time,
			sim4.events.filter(func(e): return e["type"] == "capture").size()])
	check(sim4.events.filter(func(e): return e["type"] == "capture").size() >= 3, "AIs capture nodes")

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
