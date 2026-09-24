extends SceneTree
## Headless rules check:  Godot --headless --path . --script res://tests/test_sim.gd
## Exit code 0 = all passed. Checks Rules.deck_speed/node_speed_mult/door_rate/node_fight_mult at
## their defaults - reset them first if a previous run left the static vars changed.

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
	check(not h.is_empty() and h["ordered"] == 80.0 and h["units"] == 0.0, "send 100% of 80: ordered 80, none out yet")
	check(sim.nodes[3]["units"] == 80.0, "the units stay in the vat until the door emits them")
	sim.step(0.5)
	# 0.5 s at the 48 units/s door rate = 24 out; the vat also produces a couple units meanwhile
	check(absf(h["units"] - 24.0) < 0.5, "after 0.5 s at 48 units/s: 24 out (got %.1f)" % h["units"])
	var still_inside: float = sim.nodes[3]["units"]
	check(absf(still_inside - 56.0) < 3.0, "~56 still inside, plus production (got %.1f)" % still_inside)
	# a new order takes over the part still inside
	var h_b := sim.send(3, 4, 0.5)
	check(not h.get("streaming", true) and absf(h["ordered"] - 24.0) < 0.5, "the previous order is cut to what is out")
	check(absf(h_b["ordered"] - floorf(still_inside * 0.5)) < 0.1, "the new order counts the units still inside (half of %.1f)" % still_inside)
	check(sim.nodes[3]["streaming"]["hid"] == h_b["id"], "the door now emits the new order")
	# put things back for the capture check: cancel the new order (nothing out) and finish the first
	sim.hordes.erase(h_b)
	sim.nodes[3]["units"] += h_b["ordered"]            # the cancelled order's units return to the vat
	sim.nodes[3]["streaming"] = {"hid": h["id"], "remaining": sim.nodes[3]["units"]}
	h["streaming"] = true
	h["ordered"] = h["units"] + sim.nodes[3]["units"]
	var path_len: float = h["L"]
	check(path_len > Rules.span(2) - 2.0 * Rules.R, "path length %.1f m" % path_len)
	var t := 0.0
	while t < 20.0 and sim.nodes[1]["owner"] != "A":
		sim.step(0.05)
		t += 0.05
	check(sim.nodes[1]["owner"] == "A", "neutral node 1 captured by A after %.1f s" % t)
	while not sim.hordes.is_empty():
		sim.step(0.05)
	# platform fights are rate-based, not a 1-for-1 subtraction: an 80-unit order against a 30-unit
	# neutral garrison mostly survives (the garrison melts fast once enough attackers have landed)
	var g: float = sim.nodes[1]["units"]
	check(g > 40.0 and g < 90.0, "after the whole horde is in, garrison = survivors of the platform fight (got %.1f)" % g)
	check(sim.nodes[1]["siege"].is_empty(), "no siege left on the captured platform")

	# travel time: an M deck is 4 s at base speed, nodes crossed fast
	var sim2 := Sim.new()
	sim2.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	var h2 := sim2.send(3, 1, 0.5)
	var arrive := 0.0
	while h2["state"] == "move" and arrive < 30.0:
		sim2.step(0.02)
		arrive += 0.02
	check(arrive > 4.0 and arrive < 6.0, "M deck crossing takes %.2f s (4 s deck + <2 s node time)" % arrive)
	var land: Vector3 = h2["pts"][-1]
	check(absf((land - sim2.nodes[1]["pos"]).length() - Rules.ARC_R) < 0.01 and
			(land - sim2.nodes[1]["pos"]).normalized().dot((sim2.nodes[3]["pos"] - sim2.nodes[1]["pos"]).normalized()) > 0.99,
			"the line lands on the platform from the side it arrives by, up to the tower's footprint")

	# a besieged platform: attackers sit on it and fight the garrison; the node flips when it falls
	var sim7 := Sim.new()
	sim7.setup(map, pos, {3: "A", 1: "B"}, {"A": "null", "B": "ember"})
	sim7.nodes[3]["units"] = 200.0
	sim7.nodes[1]["units"] = 40.0
	sim7.send(3, 1, 1.0)
	var sieged := false
	var t7 := 0.0
	while t7 < 30.0 and sim7.nodes[1]["owner"] != "A":
		sim7.step(0.05)
		t7 += 0.05
		if sim7.nodes[1]["siege"].get("A", 0.0) > 0.0 and sim7.nodes[1]["owner"] == "B":
			sieged = true
	check(sieged, "arriving units sit on the enemy platform as a siege while the garrison stands")
	check(sim7.nodes[1]["owner"] == "A" and sim7.combat_losses.get("B", 0.0) > 30.0,
			"the garrison is beaten down on the platform and the node flips (B lost %.0f)" % sim7.combat_losses.get("B", 0.0))

	# an order passing through a node always counts as passing through that node (Daniele,
	# 2026-09-25): a hostile waypoint on the route (3 -> 1 -> 0 -> 2 -> 4 for a send 3 -> 4) is not
	# a free glide - it fights the garrison there while it overlaps the platform.
	var sim8 := Sim.new()
	sim8.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	sim8.nodes[0]["owner"] = "A"                       # friendly waypoints either side of the contest
	sim8.nodes[2]["owner"] = "A"
	sim8.nodes[1]["owner"] = "B"
	sim8.nodes[1]["units"] = 15.0                     # weak waypoint: grinds down but the order lives
	sim8.nodes[3]["units"] = 900.0                     # large enough to outlast the waypoint AND
	sim8.send(3, 4, 1.0)                               # still overwhelm node 4's home production
	var drained := false
	var t8 := 0.0
	while t8 < 90.0 and sim8.nodes[4]["owner"] != "A":
		sim8.step(0.05)
		t8 += 0.05
		if sim8.nodes[1]["units"] <= 0.0:
			drained = true
	check(drained, "passing through a weak enemy waypoint grinds its garrison down")
	check(sim8.nodes[1]["owner"] == "B", "but the waypoint is NOT captured by passing through - only an arrival captures")
	check(sim8.nodes[4]["owner"] == "A", "the surviving force fights on through and still takes its real destination")

	var sim9 := Sim.new()
	sim9.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"})
	sim9.nodes[1]["owner"] = "B"
	sim9.nodes[1]["units"] = 500.0                     # strong waypoint: the order dies there
	sim9.nodes[3]["units"] = 60.0
	var h9 := sim9.send(3, 4, 1.0)
	var wiped := false
	var t9 := 0.0
	while t9 < 30.0 and not wiped:
		sim9.step(0.05)
		t9 += 0.05
		wiped = not (h9 in sim9.hordes)
	check(wiped, "a weak order can be wiped out entirely at a hostile waypoint before reaching its destination")
	check(sim9.nodes[4]["owner"] == "B", "the real destination was never touched - the order died at the waypoint")
	check(sim9.events.any(func(e): return e["type"] == "horde_destroyed" and e["seat"] == "A"),
			"a horde_destroyed event is recorded for the order lost in transit")

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

	# the starter seven (Docs STARTER-SEVEN.md): every map lays out fully connected from its centre
	# and plays an AI vs AI match to completion - not a check of any map's own relay mechanic (none
	# is built yet; their relay decks are fixed open, see sim.gd setup()), just that the map itself
	# is a sound, playable graph.
	var starter := ["res://maps/004-two-piers.json", "res://maps/007-long-span.json",
			"res://maps/008-strait.json", "res://maps/010-first-switch.json",
			"res://maps/011-remote-span.json", "res://maps/061-switchback-foundry.json",
			"res://maps/047-trident-exchange.json"]
	for map_path in starter:
		var sm := MapBuilder.load_map(map_path)
		var spos := MapBuilder.layout(sm)
		check(spos.size() == sm["nodes"].size(), "%s: every node reachable from the centre (%d/%d)" %
				[sm["code"], spos.size(), sm["nodes"].size()])
		var s_seats := {}
		for s in sm["seats"]["1v1"]:
			s_seats[int(s["node"])] = s["seat"]
		check(s_seats.size() == 2, "%s: 1v1 has exactly two seats" % sm["code"])
		var ssim := Sim.new()
		ssim.setup(sm, spos, s_seats, {"A": "null", "B": "ember"})
		var sa := SeatAI.new("A", 2.0)
		var sb := SeatAI.new("B", 2.3)
		var ssteps := 0
		while not ssim.over and ssteps < 20 * 60 * 8:
			sa.think(ssim, 0.1)
			sb.think(ssim, 0.1)
			ssim.step(0.1)
			ssteps += 1
		check(ssim.over, "%s: AI vs AI finishes within 8 simulated minutes (t=%.0fs)" % [sm["code"], ssim.time])

	# structures (Daniele, 2026-09-25): vat upgrade, cannon, forge - rudimentary but functional.
	# Two Piers has no cannon/forge buildable node, so use Strait (relay nodes offer both).
	var st_map := MapBuilder.load_map("res://maps/008-strait.json")
	var st_pos := MapBuilder.layout(st_map)
	var sim10 := Sim.new()
	sim10.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"})
	check(sim10.nodes[5]["tier"] == 2, "home vat starts at T2")
	check(sim10.upgrade_vat(5), "vat upgrade starts")
	check(not sim10.upgrade_vat(5), "can't start a second upgrade while one is running")
	while sim10.nodes[5]["build_kind"] != "":
		sim10.step(0.5)
	check(sim10.nodes[5]["tier"] == 3, "vat upgrade completes to T3 after Rules.BUILD_SECONDS")
	check(not sim10.build_attachment(5, "cannon"), "a normal node's buildable list has no cannon/forge")
	sim10.nodes[1]["owner"] = "A"                     # node 1: relay, buildable cannon/forge
	check(sim10.build_attachment(1, "cannon"), "a relay node's buildable list accepts a cannon")
	while sim10.nodes[1]["build_kind"] != "":
		sim10.step(0.5)
	check(sim10.nodes[1]["attachment"] == "cannon", "the cannon finishes building")
	var enemy := sim10.send(6, 5, 1.0)                 # any live enemy horde; positioned by hand below
	var pos1: Vector3 = sim10.nodes[1]["pos"]
	enemy["pts"] = PackedVector3Array([pos1, pos1])    # drop it right on the cannon's node
	enemy["cum"] = PackedFloat32Array([0.0, 1.0])
	enemy["fast"] = PackedByteArray([1, 1])
	enemy["s"] = 0.5
	enemy["units"] = 50.0                              # units are 0 right after send() (door not emitted yet)
	sim10.nodes[1]["cannon_cd"] = 0.0
	var loss_before: float = sim10.combat_losses.get("B", 0.0)
	sim10.step(0.1)
	check(sim10.combat_losses.get("B", 0.0) > loss_before, "a built cannon bursts an enemy horde in range, bypassing normal fight math")

	var sim11 := Sim.new()
	sim11.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"})
	sim11.nodes[1]["owner"] = "A"
	sim11.build_attachment(1, "forge")
	while sim11.nodes[1]["build_kind"] != "":
		sim11.step(0.5)
	check(sim11.nodes[1]["attachment"] == "forge", "the forge finishes building")
	check(absf(sim11._forge_mult("A") - (1.0 - Rules.forge_bonus)) < 0.001, "a forge reduces its owner's incoming damage")
	check(is_equal_approx(sim11._forge_mult("B"), 1.0), "and only its owner's")

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
