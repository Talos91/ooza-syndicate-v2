extends SceneTree
## Headless rules check:  Godot --headless --path . --script res://tests/test_sim.gd
## Exit code 0 = all passed. Checks Rules.deck_speed/node_speed_mult/door_rate/node_fight_mult at
## their defaults - reset them first if a previous run left the static vars changed.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func run_until(sim: Sim, cond: Callable, limit: float, dt := 0.05) -> float:
	var t := 0.0
	while t < limit and not cond.call():
		sim.step(dt)
		t += dt
	return t


func _init() -> void:
	var map := MapBuilder.load_map("res://maps/004-two-piers.json")
	var pos := MapBuilder.layout(map)
	check(pos.size() == 5, "Two Piers lays out 5 nodes")
	for e in map["edges"]:
		var d: float = (pos[int(e["from"])] as Vector3).distance_to(pos[int(e["to"])])
		var want := Rules.span({"S": 1, "M": 2, "L": 3}[e["tier"]])
		check(absf(d - want) < 0.01, "edge %s-%s honest length %.1f m" % [e["from"], e["to"], want])

	var sim := Sim.new()
	sim.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	check(sim.nodes[3]["owner"] == "A" and sim.nodes[4]["owner"] == "B", "homes owned")
	var route := sim.find_route(3, 4)
	check(route == [3, 1, 0, 2, 4], "route home A -> home B passes 1, 0, 2")

	# a send to the neighbouring neutral node captures it
	var h := sim.send(3, 1, 1.0)
	check(not h.is_empty() and h["ordered"] == 80.0 and h["units"] == 0.0, "send 100% of 80: ordered 80, none out yet")
	check(sim.nodes[3]["units"] == 80.0, "the units stay in the vat until the door emits them")
	sim.step(0.5)
	check(absf(h["units"] - 24.0) < 0.5, "after 0.5 s at 48 units/s: 24 out (got %.1f)" % h["units"])
	var still_inside: float = sim.nodes[3]["units"]
	check(absf(still_inside - 56.0) < 5.0, "~56 still inside, plus production (got %.1f)" % still_inside)
	var h_b := sim.send(3, 4, 0.5)
	check(not h.get("streaming", true) and absf(h["ordered"] - 24.0) < 0.5, "the previous order is cut to what is out")
	check(absf(h_b["ordered"] - floorf(still_inside * 0.5)) < 0.1, "the new order counts the units still inside (half of %.1f)" % still_inside)
	check(sim.nodes[3]["streaming"]["hid"] == h_b["id"], "the door now emits the new order")
	sim.hordes.erase(h_b)
	sim.nodes[3]["units"] += h_b["ordered"]
	sim.nodes[3]["streaming"] = {"hid": h["id"], "remaining": sim.nodes[3]["units"]}
	h["streaming"] = true
	h["ordered"] = h["units"] + sim.nodes[3]["units"]
	var t := run_until(sim, func(): return sim.nodes[1]["owner"] == "A", 20.0)
	check(sim.nodes[1]["owner"] == "A", "neutral node 1 captured by A after %.1f s" % t)
	run_until(sim, func(): return sim.hordes.is_empty(), 30.0)
	var g: float = sim.nodes[1]["units"]
	check(g > 40.0 and g < 130.0, "after the whole horde is in, garrison = survivors of the platform fight + production (got %.1f)" % g)
	check(sim.nodes[1]["siege"].is_empty(), "no siege left on the captured platform")
	check(not sim.nodes[1]["shield_up"] or sim.nodes[1]["shield"] >= 0.0, "a captured node starts with its shield down")

	# travel time: an M deck is 4 s at base speed, nodes crossed fast
	var sim2 := Sim.new()
	sim2.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	var h2 := sim2.send(3, 1, 0.5)
	var arrive := run_until(sim2, func(): return h2["state"] != "move", 30.0, 0.02)
	check(arrive > 4.0 and arrive < 6.0, "M deck crossing takes %.2f s (4 s deck + <2 s node time)" % arrive)
	var land: Vector3 = h2["pts"][-1]
	check(absf((land - sim2.nodes[1]["pos"]).length() - Rules.ARC_R) < 0.01,
			"the line lands on the platform from the side it arrives by, up to the tower's footprint")

	# a besieged platform: attackers sit on it and fight the garrison; the node flips when it falls
	var sim7 := Sim.new()
	sim7.setup(map, pos, {3: "A", 1: "B"}, {"A": "null", "B": "ember"}, 1)
	sim7.nodes[3]["units"] = 200.0
	sim7.nodes[1]["units"] = 40.0
	sim7.send(3, 1, 1.0)
	var sieged := [false]
	run_until(sim7, func():
		if sim7.nodes[1]["siege"].get("A", 0.0) > 0.0 and sim7.nodes[1]["owner"] == "B":
			sieged[0] = true
		return sim7.nodes[1]["owner"] == "A", 30.0)
	check(sieged[0], "arriving units sit on the enemy platform as a siege while the garrison stands")
	check(sim7.nodes[1]["owner"] == "A" and sim7.combat_losses.get("B", 0.0) > 30.0,
			"the garrison is beaten down on the platform and the node flips (B lost %.0f)" % sim7.combat_losses.get("B", 0.0))

	# THE SHIELD BOND (Daniele, Alpha 12): a transiting force fights the shield of an enemy waypoint,
	# never its garrison; breaking the shield destroys NO bridge - it drops the goo bond between that
	# node and its neighbours until the shield regenerates, and passage is free meanwhile.
	var sim8 := Sim.new()
	sim8.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim8.nodes[0]["owner"] = "B"                       # B holds 1 and 0: a bonded pair
	sim8.nodes[2]["owner"] = "A"
	sim8.nodes[1]["owner"] = "B"
	sim8.nodes[1]["units"] = 15.0
	sim8.nodes[1]["shield"] = 3.0
	sim8.nodes[0]["units"] = 15.0
	sim8.nodes[0]["shield"] = 3.0
	sim8.nodes[3]["units"] = 900.0
	var e10 := sim8._edge_index(1, 0)
	check(sim8.bonded(e10), "two adjacent nodes of one owner with shields up are bonded (goo trail)")
	sim8.send(3, 4, 1.0)
	var broke := [false]
	run_until(sim8, func():
		if not sim8.nodes[1]["shield_up"]:
			broke[0] = true
		return sim8.nodes[4]["owner"] == "A", 90.0)
	check(broke[0], "passing through breaks the weak waypoint's shield")
	check(sim8.is_edge_open(sim8._edge_index(3, 1)), "...but no deck is destroyed (the bridge stays)")
	check(sim8.events.any(func(e): return e["type"] == "shield_broken"), "a shield_broken event is recorded")
	check(sim8.nodes[1]["units"] >= 15.0, "the real garrison behind the shield is never reduced by transit")
	check(sim8.nodes[1]["owner"] == "B", "and the waypoint is NOT captured by passing through - only an arrival captures")
	check(sim8.nodes[4]["owner"] == "A", "the surviving force fights on through and still takes its real destination")
	var sim8b := Sim.new()
	sim8b.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim8b.nodes[1]["owner"] = "B"
	sim8b.nodes[0]["owner"] = "B"
	sim8b.nodes[1]["shield"] = 0.0
	sim8b.nodes[1]["shield_up"] = false
	check(not sim8b.bonded(sim8b._edge_index(1, 0)), "a node with its shield down has no bond with its neighbour")
	sim8b.nodes[1]["units"] = 100.0
	run_until(sim8b, func(): return sim8b.nodes[1]["shield_up"], 30.0)
	check(sim8b.nodes[1]["shield_up"] and sim8b.bonded(sim8b._edge_index(1, 0)), "the shield regenerates to full and the bond returns")

	var sim9 := Sim.new()
	sim9.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim9.nodes[1]["owner"] = "B"
	sim9.nodes[1]["units"] = 500.0                     # strong waypoint: the order dies there
	sim9.nodes[1]["shield"] = 100.0
	sim9.nodes[3]["units"] = 60.0
	var h9 := sim9.send(3, 4, 1.0)
	run_until(sim9, func(): return not (h9 in sim9.hordes), 30.0)
	check(not (h9 in sim9.hordes), "a weak order can be wiped out entirely at a hostile waypoint before reaching its destination")
	check(sim9.nodes[4]["owner"] == "B", "the real destination was never touched - the order died at the waypoint")

	# a neutral waypoint is a free glide
	var sim9b := Sim.new()
	sim9b.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim9b.nodes[0]["owner"] = "A"
	sim9b.nodes[2]["owner"] = "A"
	sim9b.nodes[3]["units"] = 900.0
	var units_before: float = sim9b.nodes[1]["units"]
	sim9b.send(3, 4, 1.0)
	var t9b := run_until(sim9b, func(): return sim9b.nodes[4]["owner"] == "A", 90.0)
	check(t9b < 90.0, "capture happened within the loop's budget (t=%.0fs)" % t9b)
	check(sim9b.nodes[1]["owner"] == "" and absf(sim9b.nodes[1]["units"] - units_before) < 0.5,
			"a neutral waypoint is a free glide - untouched by a passing order")

	# two opposing hordes on the same deck meet at a frontline and fight to the death
	var sim3 := Sim.new()
	sim3.setup(map, pos, {1: "A", 0: "B"}, {"A": "null", "B": "ember"}, 1)
	sim3.nodes[1]["units"] = 100.0
	sim3.nodes[0]["units"] = 100.0
	sim3.send(1, 0, 1.0)
	sim3.send(0, 1, 0.5)
	var fought := [false]
	for k in range(400):
		sim3.step(0.05)
		for x in sim3.hordes:
			if x["state"] == "fight":
				fought[0] = true
	check(fought[0], "frontline fight happens on the shared S deck")
	check(sim3.hordes.size() <= 1, "one side survives the frontline")
	check(sim3.combat_losses.size() == 2, "both sides lost units in combat")

	# CONTACT ANYWHERE (Alpha 12): two enemy hordes crossing the same NEUTRAL platform (a free glide
	# for the platform itself) still meet and fight there instead of passing through each other.
	var sim3b := Sim.new()
	sim3b.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim3b.nodes[1]["owner"] = "A"
	sim3b.nodes[2]["owner"] = "B"
	sim3b.nodes[1]["units"] = 120.0
	sim3b.nodes[2]["units"] = 120.0
	sim3b.send(1, 2, 1.0)                              # both cross neutral node 0 at the same time
	sim3b.send(2, 1, 1.0)
	var met := [false]
	for k in range(600):
		sim3b.step(0.05)
		if not sim3b.fights.is_empty():
			met[0] = true
			break
	check(met[0], "enemy hordes crossing paths engage each other wherever they meet")
	check(sim3b.events.any(func(e): return e["type"] == "frontline" or e["type"] == "rear"), "the contact is logged")

	# rear attack: an enemy catching up from behind hits the slower horde's tail
	var sim5 := Sim.new()
	sim5.setup(map, pos, {1: "A", 3: "B"}, {"A": "null", "B": "ember"}, 1)
	sim5.nodes[1]["units"] = 120.0
	sim5.nodes[3]["units"] = 200.0
	var slow := sim5.send(1, 0, 1.0)
	slow["speed"] = 0.2
	sim5.send(3, 0, 1.0)
	var rear := [false]
	for k in range(600):
		sim5.step(0.05)
		if sim5.events.any(func(e): return e["type"] == "rear"):
			rear[0] = true
			break
	check(rear[0], "enemy catching up from behind makes a rear attack")
	check(sim5.fights.size() >= 1 and slow["state"] == "fight", "the caught horde is fighting its pursuer")

	# friendly queue: a faster friend behind cannot pass through, it waits at the tail
	var sim6 := Sim.new()
	sim6.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim6.nodes[3]["units"] = 240.0
	var front := sim6.send(3, 1, 0.5)
	front["speed"] = 0.25
	while front["s"] < front["spans"][0]["s0"] + 3.0:
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
	check(not overtook, "and never passes through it")

	# structures: Alpha 11 costs x SCALE, paid from the node; production only on vat nodes
	var st_map := MapBuilder.load_map("res://maps/008-strait.json")
	var st_pos := MapBuilder.layout(st_map)
	var sim10 := Sim.new()
	sim10.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	check(sim10.nodes[5]["tier"] == 2, "home vat starts at T2")
	sim10.nodes[5]["units"] = 50.0
	check(not sim10.upgrade_vat(5), "a T2 upgrade costs %d units - not affordable with 50" % Rules.VAT_COST[2])
	sim10.nodes[5]["units"] = 120.0
	check(sim10.upgrade_vat(5), "vat upgrade starts once affordable")
	check(absf(sim10.nodes[5]["units"] - 20.0) < 0.01, "the cost is paid from the vat (Alpha 11 logic)")
	check(not sim10.upgrade_vat(5), "can't start a second upgrade while one is running")
	check(Sim.build_progress(sim10.nodes[5]) < 0.01, "build progress starts at 0")
	while sim10.nodes[5]["build_kind"] != "":
		sim10.step(0.5)
	check(sim10.nodes[5]["tier"] == 3, "vat upgrade completes to T3 after Rules.BUILD_SECONDS")
	check(not sim10.build_attachment(5, "cannon"), "a normal node's buildable list has no cannon/forge")
	sim10.nodes[1]["owner"] = "A"                     # node 1: relay, buildable cannon/forge, no vat
	var relay_units: float = sim10.nodes[1]["units"]
	sim10.step(1.0)
	check(absf(sim10.nodes[1]["units"] - relay_units) < 0.01, "a relay node has no vat: no production")
	sim10.nodes[1]["units"] = 100.0
	check(sim10.build_attachment(1, "cannon"), "a relay node's slot accepts a cannon it can pay for")
	check(absf(sim10.nodes[1]["units"] - (100.0 - Rules.CANNON_COST[1])) < 0.01, "the cannon's cost is paid")
	while sim10.nodes[1]["build_kind"] != "":
		sim10.step(0.5)
	check(sim10.nodes[1]["attachment"] == "cannon", "the cannon finishes building")
	var enemy := sim10.send(6, 5, 1.0)
	var pos1: Vector3 = sim10.nodes[1]["pos"]
	enemy["pts"] = PackedVector3Array([pos1, pos1])
	enemy["cum"] = PackedFloat32Array([0.0, 1.0])
	enemy["fast"] = PackedByteArray([1, 1])
	enemy["s"] = 0.5
	enemy["units"] = 50.0
	sim10.nodes[1]["cannon_cd"] = 0.0
	var loss_before: float = sim10.combat_losses.get("B", 0.0)
	sim10.step(0.1)
	sim10.step(0.1)
	check(sim10.combat_losses.get("B", 0.0) > loss_before, "a built cannon bursts an enemy horde in range, bypassing normal fight math")
	check(sim10.nodes[1]["cannon_burst"] > 0.0, "the burst lasts CANNON_BURST seconds, then recharges")
	# swap: cannon -> forge needs the cooldown, pays the forge cost; restore only on a final's vat
	sim10.nodes[1]["units"] = 300.0
	sim10.nodes[1]["swap_cd"] = 5.0
	check(not sim10.build_attachment(1, "forge"), "an attachment swap waits for the swap cooldown")
	sim10.nodes[1]["swap_cd"] = 0.0
	check(sim10.build_attachment(1, "forge"), "cannon -> forge swap starts once off cooldown")
	while sim10.nodes[1]["build_kind"] != "":
		sim10.step(0.5)
	check(sim10.nodes[1]["attachment"] == "forge" and sim10.nodes[1]["swap_cd"] > 0.0, "the swap completes and starts the cooldown")
	sim10.nodes[3]["owner"] = "A"                     # node 3: a final with a vat; buildable vat/cannon/forge
	sim10.nodes[3]["units"] = 300.0
	check(sim10.build_attachment(3, "cannon"), "a final node can replace its vat with a cannon")
	while sim10.nodes[3]["build_kind"] != "":
		sim10.step(0.5)
	check(not Sim.has_vat(sim10.nodes[3]) and sim10.production(sim10.nodes[3]) == 0.0, "...and then produces nothing")
	sim10.nodes[3]["swap_cd"] = 0.0
	check(sim10.restore_vat(3), "RESTORE VAT is offered on a final node")
	while sim10.nodes[3]["build_kind"] != "":
		sim10.step(0.5)
	check(Sim.has_vat(sim10.nodes[3]) and sim10.nodes[3]["tier"] == 3, "the vat comes back at its old tier")

	var sim11 := Sim.new()
	sim11.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim11.nodes[1]["owner"] = "A"
	sim11.nodes[1]["units"] = 200.0
	sim11.build_attachment(1, "forge")
	while sim11.nodes[1]["build_kind"] != "":
		sim11.step(0.5)
	check(sim11.nodes[1]["attachment"] == "forge", "the forge finishes building")
	check(absf(sim11.forge_of("A") - (1.0 + Rules.forge_bonus)) < 0.001, "a forge multiplies the damage its owner deals (Alpha 11 +50 attack)")
	check(is_equal_approx(sim11.forge_of("B"), 1.0), "and only its owner's")

	var sim12 := Sim.new()
	sim12.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim12.nodes[1]["owner"] = "A"
	sim12.nodes[1]["units"] = 500.0
	sim12.build_attachment(1, "cannon")
	while sim12.nodes[1]["build_kind"] != "":
		sim12.step(0.5)
	check(sim12.nodes[1]["cannon_tier"] == 1, "a fresh cannon starts at T1")
	check(sim12.upgrade_cost(sim12.nodes[1]) == Rules.CANNON_COST[2], "the HUD cost of the next cannon tier")
	check(sim12.upgrade_structure(1), "double-tap upgrades the built cannon, not the vat")
	while sim12.nodes[1]["build_kind"] != "":
		sim12.step(0.5)
	check(sim12.nodes[1]["cannon_tier"] == 2, "the cannon reaches T2")
	sim12.nodes[5]["units"] = 300.0
	check(sim12.upgrade_structure(5), "double-tap upgrades the vat where there's no attachment")

	# RELAYS (GAME-RULES sec8): player-fired, 3 s warning, then the tick applies the troop fate.
	var sw_map := MapBuilder.load_map("res://maps/010-first-switch.json")
	var sw_pos := MapBuilder.layout(sw_map)
	var sim13 := Sim.new()
	sim13.setup(sw_map, sw_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	var edges_1 := []
	for i in range(sim13.edges.size()):
		if sim13.edges[i]["state"] != "" and (sim13.edges[i]["a"] == 1 or sim13.edges[i]["b"] == 1):
			edges_1.append(i)
	var s1_open := edges_1.filter(func(i): return sim13.edges[i]["state"] == "s1").all(func(i): return sim13.is_edge_open(i))
	check(s1_open, "an unclaimed relay sits at its first authored state")
	check(not sim13.fire_relay(1), "nobody can fire an unclaimed relay")
	sim13.nodes[1]["owner"] = "A"
	check(sim13.fire_relay(1), "the owner can fire it")
	check(sim13.nodes[1]["relay_phase"] == "warning", "firing starts the 3 s warning, nothing moves yet")
	check(s1_open == edges_1.filter(func(i): return sim13.edges[i]["state"] == "s1").all(func(i): return sim13.is_edge_open(i)),
			"during the warning the old deck is still there")
	check(not sim13.fire_relay(1), "and it can't be fired again meanwhile")
	run_until(sim13, func(): return sim13.nodes[1]["relay_phase"] == "moving", 5.0)
	check(sim13.nodes[1]["relay_phase"] == "moving", "after the warning the tick starts the deck's motion")
	run_until(sim13, func(): return sim13.nodes[1]["relay_phase"] == "", 5.0)
	var s2_open := edges_1.filter(func(i): return sim13.edges[i]["state"] == "s2").all(func(i): return sim13.is_edge_open(i))
	check(s2_open, "when the motion ends the next state's deck is open")
	check(sim13.nodes[1]["relay_cd"] > 0.0 and not sim13.fire_relay(1), "then the 15 s cooldown runs")
	run_until(sim13, func(): return sim13.nodes[1]["relay_cd"] <= 0.0, 20.0, 0.5)
	check(sim13.fire_relay(1), "the cooldown expires and it can be fired again")
	sim13._capture(sim13.nodes[1], "B", 10.0)
	check(sim13.nodes[1]["relay_phase"] == "", "capturing a relay during its warning cancels the pending switch")

	# switch: troops on the dissolving deck FALL
	var sim14 := Sim.new()
	sim14.setup(sw_map, sw_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim14.nodes[1]["owner"] = "B"
	sim14.nodes[1]["units"] = 50.0
	sim14.nodes[5]["units"] = 200.0
	var h14 := sim14.send(5, 0, 1.0)                  # A: 5 -> 1 -> 0 over the s1 deck
	var deck14: Dictionary = h14["spans"][1]
	run_until(sim14, func(): return h14["s"] > deck14["s0"] + 4.0, 30.0)
	check(h14["s"] > deck14["s0"], "A's horde is on the switch deck")
	var a_before: float = h14["units"]
	sim14.fire_relay(1)
	run_until(sim14, func(): return sim14.nodes[1]["relay_phase"] == "", 8.0)
	check(sim14.fall_losses.get("A", 0.0) > 0.0, "units on the dissolved deck fell (A lost %.0f of %.0f)" % [sim14.fall_losses.get("A", 0.0), a_before])
	check(sim14.events.any(func(e): return e["type"] == "fall"), "a fall event is recorded (no combat credit)")

	# retract: troops on the deck are carried into the relay's node (enemies = early assault)
	var sim15 := Sim.new()
	sim15.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim15.nodes[1]["owner"] = "B"
	sim15.nodes[1]["units"] = 30.0
	sim15.nodes[1]["shield"] = 0.0
	sim15.nodes[1]["shield_up"] = false
	sim15.nodes[0]["owner"] = "A"
	sim15.nodes[0]["units"] = 200.0
	var h15 := sim15.send(0, 5, 1.0)                  # A: 0 -> 1 (retract deck) -> 5
	var deck15: Dictionary = h15["spans"][0]
	check(sim15.edges[deck15["edge"]]["retracts"], "the first deck of the route is the retracting one")
	run_until(sim15, func(): return h15["s"] > deck15["s0"] + 4.0, 30.0)
	sim15.fire_relay(1)
	run_until(sim15, func(): return sim15.nodes[1]["relay_phase"] == "", 8.0)
	check(sim15.nodes[1]["siege"].get("A", 0.0) > 0.0 or sim15.nodes[1]["owner"] == "A",
			"the retract pulled A's units straight onto B's platform as an early assault")
	check(not sim15.is_edge_open(deck15["edge"]), "the retracted deck is gone until fired again")

	# rotation (Switchback Foundry): the deck pivots and its troops RIDE it, same order
	var rot_map := MapBuilder.load_map("res://maps/061-switchback-foundry.json")
	var rot_pos := MapBuilder.layout(rot_map)
	var sim16 := Sim.new()
	sim16.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, 1)
	sim16.nodes[0]["owner"] = "A"
	sim16.nodes[1]["owner"] = "A"
	sim16.nodes[1]["units"] = 200.0
	var r16 := sim16.find_route(1, 0)
	check(r16 == [1, 0], "with r1 the hub deck links node 1 to the centre")
	var h16 := sim16.send(1, 0, 1.0)
	var deck16: Dictionary = h16["spans"][0]
	run_until(sim16, func(): return h16["s"] > deck16["s0"] + 2.0, 30.0)
	check(h16 in sim16.hordes and h16["s"] > deck16["s0"], "A's horde is on the rotating deck")
	sim16.fire_relay(0)
	run_until(sim16, func(): return sim16.nodes[0]["relay_phase"] == "moving", 5.0)
	check(h16["state"] == "ride" and h16.has("ride"), "during the pivot the horde rides the deck")
	run_until(sim16, func(): return sim16.nodes[0]["relay_phase"] == "", 5.0)
	check(h16 in sim16.hordes and not h16.has("ride"), "after the pivot it is still alive and free")
	check(h16["route"][0] == 2 or h16["route"][0] == 6, "and now stands on the deck to the pier it was rotated to (route from %s)" % str(h16["route"][0]))
	check(sim16.fall_losses.get("A", 0.0) == 0.0, "nothing fell: the new state points at a pier, not the void")

	# remote (Remote Span): the centre console controls the diagonal decks elsewhere
	var rem_map := MapBuilder.load_map("res://maps/011-remote-span.json")
	var rem_pos := MapBuilder.layout(rem_map)
	var sim17 := Sim.new()
	sim17.setup(rem_map, rem_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	var m_edges := sim17.controlled_edges(0)
	check(m_edges.size() == 4, "the remote console governs all four diagonal decks (got %d)" % m_edges.size())
	check(sim17.find_route(1, 3).size() == 2, "m1: 1-3 is a direct deck")
	sim17.nodes[0]["owner"] = "A"
	sim17.fire_relay(0)
	run_until(sim17, func(): return sim17.nodes[0]["relay_phase"] == "", 8.0)
	check(sim17.find_route(1, 4).size() == 2 and sim17.find_route(1, 3).size() != 2, "m2: 1-4 is direct now and 1-3 is gone")

	# LAST STAND (GAME-RULES sec10): hidden method from the map's list, revealed with the order at
	# the start; 10 s warning per node; everything on the node dies; the final never drops.
	var sim18 := Sim.new()
	sim18.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 7)
	sim18.nodes[1]["owner"] = "A"
	sim18.nodes[1]["units"] = 100.0
	check(sim18.last_stand_method == "", "the method is hidden before the start")
	run_until(sim18, func(): return sim18.last_stand_active, Rules.LAST_STAND_TIME + 2.0, 0.5)
	check(sim18.last_stand_active and sim18.last_stand_method in map["lastStand"]["methods"],
			"Last Stand starts at %d s with a method the map lists (%s)" % [int(Rules.LAST_STAND_TIME), sim18.last_stand_method])
	check(sim18.last_stand_final == 0 and not (0 in sim18.last_stand_order), "the final (centre) is never in the drop order")
	check(sim18.last_stand_order.size() == 4, "every other node is in the revealed order")
	check(sim18.last_stand_warn_node == sim18.last_stand_order[0], "the first node is under warning right away")
	var first: int = sim18.last_stand_warn_node
	var owner_first: String = sim18.nodes[first]["owner"]
	var units_first: float = sim18.nodes[first]["units"]
	run_until(sim18, func(): return sim18.collapsed.get(first, false), Rules.LAST_STAND_WARNING + 1.0, 0.5)
	check(sim18.collapsed.get(first, false), "after the 10 s warning the node drops")
	check(sim18.nodes[first]["owner"] == "" and sim18.nodes[first]["units"] == 0.0, "the dropped node is empty and ownerless")
	if owner_first != "":
		check(sim18.fall_losses.get(owner_first, 0.0) >= units_first - 0.01, "its garrison died as a fall loss")
	check(sim18.find_route(3, first).is_empty() or sim18.collapsed.get(3, false), "no route leads to a dropped node")
	# a home that drops with no other node = elimination
	var sim19 := Sim.new()
	sim19.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 3)
	sim19.time = Rules.LAST_STAND_TIME - 0.1
	sim19.nodes[1]["owner"] = "A"                     # A holds 3 and 1; B only its home 4
	run_until(sim19, func(): return sim19.over, 200.0, 0.5)
	check(sim19.over and sim19.winner == "A", "with only its home, B is eliminated when the collapse takes it (winner %s at %.0f s)" % [sim19.winner, sim19.time])
	check(sim19.eliminated.has("B"), "an elimination is recorded")
	var ls_map := MapBuilder.load_map("res://maps/007-long-span.json")
	var ls_pos := MapBuilder.layout(ls_map)
	# no horde ever crosses a deck that is gone (Daniele: "the enemy crossed a bridge even if there
	# was no bridge"): a horde whose route runs over a fallen node's deck re-routes at the pier, or
	# stops at that node when no route is left
	var sim21 := Sim.new()
	sim21.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim21.nodes[4]["units"] = 200.0
	var h21 := sim21.send(4, 3, 1.0)                  # B: 4 -> 2 -> 0 -> 1 -> 3
	run_until(sim21, func(): return h21["s"] > h21["spans"][0]["s0"] + 2.0, 20.0)
	sim21.last_stand_final = 1
	sim21._drop_node(0)                               # the centre falls while B is still on deck 4-2
	var crossed := [false]
	var dead_span: Dictionary = h21["spans"][1]
	run_until(sim21, func():
		if h21 in sim21.hordes and h21["route"].has(0) and h21["s"] > dead_span["s0"] + 1.5:
			crossed[0] = true
		return not (h21 in sim21.hordes), 60.0)
	check(not crossed[0], "a horde never walks onto the fallen node's deck")
	check(sim21.fall_losses.get("B", 0.0) == 0.0, "nothing fell: it stopped at the pier instead")
	check(sim21.nodes[2]["siege"].get("B", 0.0) > 0.0 or sim21.nodes[2]["owner"] == "B", "with no route left it stays at node 2")
	# the drop order never cuts the map into islands; chaos falls back to inward where "homes last"
	# and connectivity cannot both hold (Two Piers is a line)
	var never_chaos := true
	for seed_value in range(10):
		var s22 := Sim.new()
		s22.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, seed_value)
		s22.time = Rules.LAST_STAND_TIME
		s22.step(0.1)
		if s22.last_stand_method == "chaos":
			never_chaos = false
		var gone := {}
		for id in s22.last_stand_order:
			gone[id] = true
			if not s22._connected_to(s22.last_stand_final, gone):
				check(false, "Two Piers order isolates a node after dropping %d (seed %d)" % [id, seed_value])
	check(never_chaos, "chaos never activates on Two Piers (falls back to inward)")
	var chaos_seen := false
	for seed_value in range(16):
		var s23 := Sim.new()
		s23.setup(ls_map, ls_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, seed_value)
		s23.time = Rules.LAST_STAND_TIME
		s23.step(0.1)
		var gone := {}
		var isolated := false
		for id in s23.last_stand_order:
			gone[id] = true
			if not s23._connected_to(s23.last_stand_final, gone):
				isolated = true
		check(not isolated, "Long Span %s order (seed %d) never isolates a node" % [s23.last_stand_method, seed_value])
	for seed_value in range(16):
		var s24 := Sim.new()
		s24.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, seed_value)
		s24.time = Rules.LAST_STAND_TIME
		s24.step(0.1)
		var gone := {}
		for id in s24.last_stand_order:
			gone[id] = true
			if not s24._connected_to(s24.last_stand_final, gone):
				check(false, "Switchback %s order isolates a node (seed %d)" % [s24.last_stand_method, seed_value])
		if s24.last_stand_method == "chaos":
			chaos_seen = true
			var half: int = s24.last_stand_order.size() / 2
			check(s24.last_stand_order.find(7) >= half and s24.last_stand_order.find(10) >= half,
					"chaos keeps the homes out of the first half of the order (seed %d)" % seed_value)
	check(chaos_seen, "chaos is still possible on a ring map like Switchback Foundry")

	# outward is only offered on maps that author an outward final
	var seen_methods := {}
	for seed_value in range(12):
		var s20 := Sim.new()
		s20.setup(ls_map, ls_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, seed_value)
		s20.time = Rules.LAST_STAND_TIME
		s20.step(0.1)
		seen_methods[s20.last_stand_method] = true
		if s20.last_stand_method == "outward":
			check(s20.last_stand_final == 3 and s20.last_stand_order[0] == 0, "outward drops the centre first and keeps the outward final")
	check(seen_methods.size() >= 2, "over several seeds Long Span rolls more than one method (%s)" % str(seen_methods.keys()))

	# AI vs AI finishes a match on every starter map
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
		var ssim := Sim.new()
		ssim.setup(sm, spos, s_seats, {"A": "null", "B": "ember"}, 5)
		var sa := SeatAI.new("A", 2.0, "Standard")
		var sb := SeatAI.new("B", 2.3, "Veteran")
		var ssteps := 0
		while not ssim.over and ssteps < 20 * 60 * 8:
			sa.think(ssim, 0.1)
			sb.think(ssim, 0.1)
			ssim.step(0.1)
			ssteps += 1
		var caps := ssim.events.filter(func(e): return e["type"] == "capture").size()
		var fires := ssim.events.filter(func(e): return e["type"] == "relay_fired").size()
		print("      %s: over=%s winner=%s at %.0f s, captures=%d relay fires=%d falls=%s" % [sm["code"], ssim.over, ssim.winner, ssim.time, caps, fires, str(ssim.fall_losses)])
		check(ssim.over, "%s: AI vs AI finishes within 8 simulated minutes (t=%.0fs)" % [sm["code"], ssim.time])
		check(caps >= 2, "%s: AIs capture nodes" % sm["code"])

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
