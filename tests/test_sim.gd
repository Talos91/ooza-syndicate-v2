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
	Rules.bridge_combat = true                      # these checks were written for SIEGE (the old default); BRAWL is the game's default since 0.18.7
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
	var out_expect: float = Rules.door_rate * 0.5
	check(absf(h["units"] - out_expect) < 0.5, "after 0.5 s at %.0f units/s: %.0f out (got %.1f)" % [Rules.door_rate, out_expect, h["units"]])
	var still_inside: float = sim.nodes[3]["units"]
	check(absf(still_inside - (80.0 - out_expect)) < 5.0, "~%.0f still inside, plus production (got %.1f)" % [80.0 - out_expect, still_inside])
	var h_b := sim.send(3, 4, 0.5)
	check(not h.get("streaming", true) and absf(h["ordered"] - out_expect) < 0.5, "the previous order is cut to what is out")
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

	# travel time: an M deck is 4 s at base speed, nodes crossed fast
	var sim2 := Sim.new()
	sim2.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	var h2 := sim2.send(3, 1, 0.5)
	var arrive := run_until(sim2, func(): return h2["state"] != "move", 30.0, 0.02)
	check(arrive > 2.5 and arrive < 5.5, "M deck crossing takes %.2f s at %.0f m/s, platforms at the same speed" % [arrive, Rules.deck_speed])
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

	# ALPHA 14 CORRIDORS AND TRANSIT (Daniele): goo corridors always on between two adjacent nodes
	# one player owns; passing through an enemy node fights its garrison (the badge number, no
	# hidden pool) but only an arrival captures; capture either end and the corridor drains.
	var sim8 := Sim.new()
	sim8.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim8.nodes[0]["owner"] = "B"                       # B holds 1 and 0: a corridor between them
	sim8.nodes[2]["owner"] = "A"
	sim8.nodes[1]["owner"] = "B"
	sim8.nodes[1]["units"] = 30.0
	sim8.nodes[0]["units"] = 15.0
	sim8.nodes[3]["units"] = 900.0
	var e10 := sim8._edge_index(1, 0)
	check(sim8.bonded(e10) and sim8.goo_owner(e10) == "B", "two adjacent nodes of one owner share a goo corridor, always on")
	sim8.send(3, 4, 1.0)
	var g_dropped := [false]
	run_until(sim8, func():
		if sim8.nodes[1]["owner"] == "B" and sim8.nodes[1]["units"] < 25.0:
			g_dropped[0] = true
		return sim8.nodes[4]["owner"] == "A", 90.0)
	check(g_dropped[0], "passing through an enemy node fights its real garrison (no hidden shield)")
	check(sim8.nodes[1]["owner"] == "B", "and the waypoint is NOT captured by passing through - only an arrival captures")
	check(sim8.nodes[4]["owner"] == "A", "the surviving force fights on through and still takes its real destination")
	check(sim8.is_edge_open(sim8._edge_index(3, 1)), "no deck is destroyed by passing through")
	sim8._capture(sim8.nodes[0], "A", 10.0)
	check(not sim8.bonded(e10), "capture either end and that corridor's goo drains")
	# home advantage: a horde on enemy goo is slower and pushes at a disadvantage
	var sim8b := Sim.new()
	sim8b.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	sim8b.nodes[1]["owner"] = "B"
	sim8b.nodes[0]["owner"] = "B"
	sim8b.nodes[3]["units"] = 120.0
	var hg := sim8b.send(3, 0, 1.0)                    # A crosses B's 1-0 corridor
	var seen_goo := [false]
	var p_goo := [0.0]
	run_until(sim8b, func():
		if sim8b.on_enemy_goo(hg) and hg["units"] > 10.0:
			seen_goo[0] = true
			p_goo[0] = sim8b.power_of(hg) / (hg["units"] * sim8b.attack_of("A"))
		return seen_goo[0] or not (hg in sim8b.hordes), 30.0)
	check(seen_goo[0], "a horde crossing an enemy corridor is on enemy goo")
	check(absf(p_goo[0] - Rules.GOO_PUSH) < 0.01, "on enemy goo it pushes at %.2f of its weight in a tug-of-war" % Rules.GOO_PUSH)

	var sim9 := Sim.new()
	sim9.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	sim9.nodes[1]["owner"] = "B"
	sim9.nodes[1]["units"] = 500.0                     # strong waypoint: the order dies there
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

	# a line that walks onto a switch deck WHILE it is dissolving, and a line whose head is past the
	# deck when it goes, both lose what is on it (Daniele, Alpha 14: "they still don't consistently fall")
	var sim14b := Sim.new()
	sim14b.setup(sw_map, sw_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim14b.nodes[1]["owner"] = "B"
	sim14b.nodes[1]["units"] = 1.0
	sim14b.nodes[5]["units"] = 400.0
	var late := sim14b.send(5, 0, 1.0)                 # 5 -> 1 -> 0 over node 1's s1 deck
	var late_deck: Dictionary = late["spans"][1]
	sim14b.fire_relay(1)
	run_until(sim14b, func(): return sim14b.nodes[1]["relay_phase"] == "moving", 5.0)
	run_until(sim14b, func(): return late["s"] > late_deck["s0"] + 0.5 or not (late in sim14b.hordes), 10.0)
	run_until(sim14b, func(): return sim14b.nodes[1]["relay_phase"] == "", 5.0)
	sim14b.step(0.05)
	var crossed_late: bool = late in sim14b.hordes and late["route"].has(0) and late["s"] > late_deck["s1"] + 1.0
	check(sim14b.fall_losses.get("A", 0.0) > 0.0, "a line that walked onto a deck mid-dissolve falls when the motion ends")
	check(not crossed_late, "...and never reaches the far side over the missing deck")

	# retract: troops on the deck are carried into the relay's node (enemies = early assault)
	var sim15 := Sim.new()
	sim15.setup(st_map, st_pos, {5: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim15.nodes[1]["owner"] = "B"
	sim15.nodes[1]["units"] = 30.0
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

	# rotation (Switchback Foundry; Daniele, 0.18.3: "when a rotating bridge turns all units that are on
	# it are shaken down into the void as if the fall due to centrifugal power"): when the deck starts
	# to turn every body on it is flung off - any owner, the relay owner's own included - as a fall loss
	var rot_map := MapBuilder.load_map("res://maps/061-switchback-foundry.json")
	var rot_pos := MapBuilder.layout(rot_map)
	var sim16 := Sim.new()
	sim16.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, 1)
	sim16.nodes[0]["owner"] = "A"
	sim16.nodes[1]["owner"] = "A"
	sim16.nodes[1]["units"] = 12.0                    # a short line that fits on the deck
	var r16 := sim16.find_route(1, 0)
	check(r16 == [1, 0], "with r1 the hub deck links node 1 to the centre")
	var h16 := sim16.send(1, 0, 1.0)
	var deck16: Dictionary = h16["spans"][0]
	run_until(sim16, func(): return not h16["streaming"] and h16["s"] - Sim.chain_length(h16) > deck16["s0"] + 0.3, 30.0)
	check(h16 in sim16.hordes and h16["s"] < deck16["s1"] and h16["s"] - Sim.chain_length(h16) > deck16["s0"],
			"A's whole line is on the rotating deck")
	var a16: float = h16["units"]
	sim16.fx_events.clear()
	sim16.fire_relay(0)
	sim16.nodes[0]["relay_t"] = 0.0                   # skip the warning: the line must still be on the deck at the tick
	sim16.step(0.02)
	check(sim16.nodes[0]["relay_phase"] == "moving", "the deck starts to turn")
	check(not (h16 in sim16.hordes), "the relay owner's own line on the turning deck is gone: flung off")
	check(absf(sim16.fall_losses.get("A", 0.0) - a16) < 0.01, "all of it counts as a fall loss (%.1f of %.1f)" % [sim16.fall_losses.get("A", 0.0), a16])
	var fl16 := sim16.fx_events.filter(func(e): return e["type"] == "fling")
	check(fl16.size() == 1 and fl16[0]["node"] == 0 and fl16[0]["seat"] == "A" and fl16[0]["units"] == Rules.shown(a16),
			"one fling fx for the HUD: node, owner of the flung units, shown units (%s)" % str(fl16.map(func(e): return [e["node"], e["seat"], e["units"]])))
	check(not sim16.fx_events.any(func(e): return e["type"] == "fall"), "flung, not the plain fall visual")
	check(sim16.events.any(func(e): return e["type"] == "fall" and e.get("why", "") == "fling"), "the fall event is recorded (no combat credit)")
	check(not sim16.hordes.any(func(x): return x.has("ride")), "nobody rides a rotation")
	run_until(sim16, func(): return sim16.nodes[0]["relay_phase"] == "", 5.0)
	check(sim16.nodes[0]["relay_phase"] == "" and sim16.nodes[0]["relay_cd"] > 0.0, "the turn ends and the cooldown runs as before")
	# an enemy line partly on the deck loses only the part on it; the rest is behind a deck that is gone
	var sim16b := Sim.new()
	sim16b.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, 1)
	sim16b.nodes[0]["owner"] = "A"
	sim16b.nodes[0]["units"] = 50.0
	sim16b.nodes[1]["owner"] = "B"
	sim16b.nodes[1]["units"] = 200.0
	var h16b := sim16b.send(1, 0, 1.0)                # B attacks A's relay over its turning deck
	var deck16b: Dictionary = h16b["spans"][0]
	run_until(sim16b, func(): return h16b["s"] > deck16b["s0"] + 3.0, 30.0)
	var tail16b: float = h16b["s"] - Sim.chain_length(h16b)
	check(tail16b < deck16b["s0"], "B's line is only partly on the deck (tail %.1f m before it)" % (deck16b["s0"] - tail16b))
	var b16: float = h16b["units"]
	var on16b: float = b16 * (h16b["s"] - deck16b["s0"]) / Sim.chain_length(h16b)
	sim16b.fire_relay(0)
	sim16b.nodes[0]["relay_t"] = 0.0
	sim16b.step(0.02)
	var lost16b: float = sim16b.fall_losses.get("B", 0.0)
	check(absf(lost16b - on16b) < 0.5 * on16b + 1.0, "the enemy loses the part on the deck (%.1f, expected about %.1f of %.1f)" % [lost16b, on16b, b16])
	check(lost16b < b16 - 1.0 and (h16b in sim16b.hordes or sim16b.nodes[1]["units"] > 0.0), "the rest survives behind the deck")
	check(sim16b.fx_events.filter(func(e): return e["type"] == "fling" and e["seat"] == "B").size() == 1, "one fling fx for B's line")
	# the relay kinds that do not turn keep their fate: switch falls (plain fall fx), retract carries
	check(sim14.fx_events.any(func(e): return e["type"] == "fall") and not sim14.fx_events.any(func(e): return e["type"] == "fling"),
			"a switch deck still drops its troops with the plain fall")
	check(not sim15.fx_events.any(func(e): return e["type"] == "fling"), "a retract still carries, nobody is flung")
	# AI: a rotation is lethal now - it fires for the kill, never with its own line on the deck
	var sim16c := Sim.new()
	sim16c.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, 1)
	sim16c.nodes[0]["owner"] = "A"
	sim16c.nodes[0]["units"] = 80.0
	sim16c.nodes[1]["owner"] = "B"
	sim16c.nodes[1]["units"] = 60.0
	var h16c := sim16c.send(1, 0, 1.0)
	run_until(sim16c, func(): return not h16c["streaming"] and h16c["s"] - Sim.chain_length(h16c) > h16c["spans"][0]["s0"], 30.0)
	SeatAI.new("A", 2.0, "Standard").think(sim16c, 10.0)
	check(sim16c.nodes[0]["relay_phase"] == "warning", "the AI fires its rotation when an enemy line is on the deck")
	var sim16d := Sim.new()
	sim16d.setup(rot_map, rot_pos, {7: "A", 10: "B"}, {"A": "null", "B": "ember"}, 1)
	sim16d.nodes[0]["owner"] = "A"
	sim16d.nodes[1]["owner"] = "A"
	sim16d.nodes[1]["units"] = 12.0
	sim16d.nodes[4]["owner"] = "B"
	sim16d.nodes[4]["units"] = 12.0
	var h16d := sim16d.send(1, 0, 1.0)                # A's own line on deck 1-0, B's on deck 4-0: both turn
	var e16d := sim16d.send(4, 0, 1.0)
	run_until(sim16d, func(): return not e16d["streaming"] and e16d["s"] - Sim.chain_length(e16d) > e16d["spans"][0]["s0"] + 0.3, 30.0)
	var both16d: bool = h16d in sim16d.hordes and e16d in sim16d.hordes and h16d["s"] > h16d["spans"][0]["s0"] \
			and h16d["s"] < h16d["spans"][0]["s1"] and e16d["s"] < e16d["spans"][0]["s1"]
	check(both16d, "A's own line and B's line are both on decks the rotation turns")
	SeatAI.new("A", 2.0, "Standard").think(sim16d, 10.0)
	check(sim16d.nodes[0]["relay_phase"] == "", "...and the AI never fires it while its own line is on it")
	sim16d.hordes.erase(h16d)
	SeatAI.new("A", 2.0, "Standard").think(sim16d, 10.0)
	check(sim16d.nodes[0]["relay_phase"] == "warning", "(with its own line gone it fires for the kill)")

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
	check(not crossed[0], "a horde never crosses the fallen node's deck")
	check(sim21.fall_losses.get("B", 0.0) > 100.0, "it walked off the pier into the void instead (B lost %.0f)" % sim21.fall_losses.get("B", 0.0))
	check(not (h21 in sim21.hordes), "nothing of it reached the other side")
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

	# faction stat profiles (Alpha 11's leans, GAME-RULES sec3): VEX travels faster, Bloom produces
	# more, Ember hits harder, Solar takes less
	check(absf(Rules.stat("vex", "speed") - 1.15) < 0.001 and Rules.stat("null", "speed") == 1.0, "VEX is 15 % faster, NULL baseline")
	var sim25 := Sim.new()
	sim25.setup(map, pos, {3: "A", 4: "B"}, {"A": "vex", "B": "null"}, 1)
	var sim25b := Sim.new()
	sim25b.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	var hv := sim25.send(3, 1, 0.5)
	var hn := sim25b.send(3, 1, 0.5)
	var tv := run_until(sim25, func(): return hv["state"] != "move", 30.0, 0.02)
	var tn := run_until(sim25b, func(): return hn["state"] != "move", 30.0, 0.02)
	check(tv < tn, "a VEX horde arrives before a NULL one on the same deck (%.2f vs %.2f s)" % [tv, tn])
	var sim26 := Sim.new()
	sim26.setup(map, pos, {3: "A", 4: "B"}, {"A": "bloom", "B": "ember"}, 1)
	check(absf(sim26.production(sim26.nodes[3]) - Rules.PROD[2] * 1.15) < 0.001, "Bloom's home produces 15 % more")
	check(absf(sim26.production(sim26.nodes[4]) - Rules.PROD[2] * 0.9) < 0.001, "Ember's home produces 10 % less")
	check(absf(sim26.attack_of("B") - 1.15) < 0.001 and absf(sim26.attack_of("A") - 1.0) < 0.001, "Ember deals 15 % more damage")

	# TUG-OF-WAR (Alpha 14): the front slides toward the weaker side
	var sim28 := Sim.new()
	sim28.setup(ls_map, ls_pos, {1: "A", 0: "B"}, {"A": "null", "B": "null"}, 1)
	sim28.nodes[1]["units"] = 300.0
	sim28.nodes[0]["units"] = 100.0
	var strong := sim28.send(1, 0, 1.0)
	var weak := sim28.send(0, 1, 1.0)
	var contact_at := [-1.0, -1.0]
	var pushed := [false]
	for k in range(600):
		sim28.step(0.05)
		if not sim28.fights.is_empty() and contact_at[0] < 0.0 and weak in sim28.hordes:
			contact_at = [strong["s"], weak["s"]]
		elif contact_at[0] >= 0.0 and strong in sim28.hordes and weak in sim28.hordes:
			if strong["s"] > contact_at[0] + 0.5 and weak["s"] < contact_at[1] - 0.5:
				pushed[0] = true
		if not (weak in sim28.hordes):
			break
	check(contact_at[0] >= 0.0, "the two lines meet on the M deck")
	check(pushed[0], "the front slides: the stronger head advances and the weaker line is shoved back")
	# RECALL: a horde turns round and flows back to the node it left
	var sim29 := Sim.new()
	sim29.setup(ls_map, ls_pos, {1: "A", 6: "B"}, {"A": "null", "B": "ember"}, 1)
	sim29.nodes[1]["units"] = 100.0
	var h29 := sim29.send(1, 0, 1.0)                 # the M deck to the centre
	run_until(sim29, func(): return h29["s"] > h29["spans"][0]["s0"] + 3.0, 20.0)
	var carried: float = h29["units"]
	var home_before: float = sim29.nodes[1]["units"]
	check(sim29.recall(h29["id"]), "an own horde on a deck can be recalled")
	check(h29["target"] == 1 and h29.get("retreat", false), "it now heads back to the node it left")
	run_until(sim29, func(): return not (h29 in sim29.hordes), 20.0)
	check(sim29.nodes[1]["units"] > home_before + carried * 0.9, "and pours back into it (%.0f -> %.0f)" % [home_before, sim29.nodes[1]["units"]])
	check(sim29.nodes[0]["owner"] == "", "the old target was never reached")
	var sim30 := Sim.new()                             # recall mid-fight: it breaks off and gets out
	sim30.setup(ls_map, ls_pos, {1: "A", 0: "B"}, {"A": "null", "B": "null"}, 1)
	sim30.nodes[1]["units"] = 100.0
	sim30.nodes[0]["units"] = 300.0
	var losing := sim30.send(1, 0, 1.0)
	sim30.send(0, 1, 1.0)
	run_until(sim30, func(): return not sim30.fights.is_empty(), 20.0)
	check(sim30.recall(losing["id"]), "a horde can be recalled mid-fight")
	var escaped := false
	for k in range(400):
		sim30.step(0.05)
		if not (losing in sim30.hordes):
			escaped = sim30.nodes[1]["owner"] == "A" and sim30.events.any(func(e): return e["type"] == "recall")
			break
	check(escaped or (losing in sim30.hordes and losing["state"] == "move"), "the retreating line keeps moving under pressure")

	# CLASSIC = Alpha 11's landing rule: each arriving unit is resolved at once, one-for-one at
	# baseline; nothing waits outside as a siege; survivors take the node
	Rules.bridge_combat = false
	var sim32 := Sim.new()
	sim32.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	sim32.nodes[1]["units"] = 20.0
	sim32._land_classic(sim32.nodes[1], "A", 12.0)
	check(sim32.nodes[1]["owner"] == "" and absf(sim32.nodes[1]["units"] - 8.0) < 0.01 and sim32.nodes[1]["siege"].is_empty(),
			"classic: 12 attackers kill 12 of 20 defenders one-for-one and leave no siege")
	sim32._land_classic(sim32.nodes[1], "A", 18.0)
	check(sim32.nodes[1]["owner"] == "A" and absf(sim32.nodes[1]["units"] - 10.0) < 0.01, "classic: the next 18 kill the last 8 and 10 take the node")
	sim32.nodes[3]["units"] = 300.0                    # the centre holds 120
	var hc := sim32.send(3, 0, 1.0)
	run_until(sim32, func(): return not (hc in sim32.hordes), 40.0)
	check(sim32.nodes[0]["owner"] == "A" and sim32.nodes[0]["siege"].is_empty(), "classic: a send walks in and takes the node, never besieging it")
	Rules.bridge_combat = true

	# bridge combat toggle (Daniele): OFF = Alpha 11 - hordes pass each other on decks, fights only
	# at nodes; ON = Alpha 12
	# conquest downgrades a vat or cannon one tier (minimum 1); neutral captures don't
	var sim34 := Sim.new()
	sim34.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	sim34.nodes[4]["tier"] = 3
	sim34._capture(sim34.nodes[4], "A", 10.0)
	check(sim34.nodes[4]["tier"] == 2, "a conquered T3 vat drops to T2")
	sim34.nodes[1]["tier"] = 1
	sim34.nodes[1]["owner"] = "B"
	sim34._capture(sim34.nodes[1], "A", 10.0)
	check(sim34.nodes[1]["tier"] == 1, "a T1 vat stays T1")
	sim34.nodes[0]["tier"] = 3
	sim34._capture(sim34.nodes[0], "A", 10.0)
	check(sim34.nodes[0]["tier"] == 3, "taking a neutral node costs no tier")

	# Last Stand toggle: off = no collapse ever starts
	Rules.last_stand = false
	var sim33 := Sim.new()
	sim33.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	sim33.time = Rules.LAST_STAND_TIME + 1.0
	for k in range(40):
		sim33.step(0.5)
	check(not sim33.last_stand_active and sim33.collapsed.is_empty(), "Last Stand OFF: nothing collapses")
	Rules.last_stand = true

	Rules.bridge_combat = false
	var sim27 := Sim.new()
	sim27.setup(map, pos, {1: "A", 0: "B"}, {"A": "null", "B": "ember"}, 1)
	sim27.nodes[1]["units"] = 100.0
	sim27.nodes[0]["units"] = 100.0
	sim27.send(1, 0, 1.0)
	sim27.send(0, 1, 1.0)
	for k in range(200):
		sim27.step(0.05)
	check(sim27.fights.is_empty() and sim27.events.filter(func(e): return e["type"] == "frontline").is_empty(),
			"with bridge combat OFF two hordes pass each other on the deck")
	check(sim27.nodes[1]["siege"].get("B", 0.0) > 0.0 or sim27.nodes[0]["siege"].get("A", 0.0) > 0.0 or sim27.nodes[1]["owner"] == "B" or sim27.nodes[0]["owner"] == "A",
			"...and fight at the nodes instead")
	Rules.bridge_combat = true

	# TEAM AND FFA MODES (Alpha 14): allies never fight each other, reinforce each other's nodes, and
	# a team wins together; FFA up to five seats plays to the end
	var tx_map := MapBuilder.load_map("res://maps/047-trident-exchange.json")
	var tx_pos := MapBuilder.layout(tx_map)
	var tseats := {}
	var tteams := {}
	for s in tx_map["seats"]["2v2"]:
		tseats[int(s["node"])] = s["seat"]
		tteams[s["seat"]] = int(s["team"])
	var sim31 := Sim.new()
	sim31.setup(tx_map, tx_pos, tseats, {"A": "null", "B": "vex", "C": "ember", "D": "solar"}, 2, tteams)
	var ally: String = tteams.keys().filter(func(k): return k != "A" and tteams[k] == tteams["A"])[0]
	check(sim31.allied("A", ally) and not sim31.allied("A", tteams.keys().filter(func(k): return tteams[k] != tteams["A"])[0]),
			"2v2: A and %s are allies, the other team is not" % ally)
	var ally_home: int = tseats.keys().filter(func(id): return tseats[id] == ally)[0]
	var a_home: int = tseats.keys().filter(func(id): return tseats[id] == "A")[0]
	var before_ally: float = sim31.nodes[ally_home]["units"]
	sim31.nodes[a_home]["units"] = 100.0
	var hally := sim31.send(a_home, ally_home, 1.0)
	check(not hally.is_empty(), "A can send to an ally's node")
	run_until(sim31, func(): return not (hally in sim31.hordes), 40.0)
	check(sim31.nodes[ally_home]["owner"] == ally and sim31.nodes[ally_home]["units"] > before_ally + 50.0,
			"sending to an ally reinforces it, never captures it")
	var ais_t := []
	for s in tseats.values():
		ais_t.append(SeatAI.new(s, 2.0, "Standard"))
	var steps_t := 0
	while not sim31.over and steps_t < 20 * 60 * 8:
		for ai in ais_t:
			ai.think(sim31, 0.1)
		sim31.step(0.1)
		steps_t += 1
	print("      2v2 047: over=%s winner=%s (team %s) at %.0f s" % [sim31.over, sim31.winner, str(tteams.get(sim31.winner, "?")), sim31.time])
	check(sim31.over, "2v2 AI match on Trident Exchange finishes")
	for code in ["036-khepri-carousel", "037-aurelia-orbital"]:
		var fm := MapBuilder.load_map("res://maps/%s.json" % code)
		var fpos := MapBuilder.layout(fm)
		check(fpos.size() == fm["nodes"].size(), "%s lays out every node" % code)
		var fseats := {}
		for s in fm["seats"]["FFA5"]:
			fseats[int(s["node"])] = s["seat"]
		check(fseats.size() == 5, "%s seats five players" % code)
		var fsim := Sim.new()
		fsim.setup(fm, fpos, fseats, {"A": "null", "B": "vex", "C": "ember", "D": "solar", "E": "bloom"}, 3)
		var fais := []
		for s in fseats.values():
			fais.append(SeatAI.new(s, 2.0, "Standard"))
		var fsteps := 0
		while not fsim.over and fsteps < 20 * 60 * 8:
			for ai in fais:
				ai.think(fsim, 0.1)
			fsim.step(0.1)
			fsteps += 1
		print("      FFA5 %s: over=%s winner=%s at %.0f s" % [code, fsim.over, fsim.winner, fsim.time])
		check(fsim.over, "FFA 5 AI match on %s finishes" % code)

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

	# ---------------------------------------------------------------- Alpha 16: Brawl moves like Alpha 11
	Rules.bridge_combat = false
	check(is_equal_approx(Rules.move_speed(), 8.9 * 0.8 * 0.8) and Rules.platform_mult() == 1.0, "BRAWL: 5.7 m/s on decks and platforms alike (Alpha 11 speed less 20 % twice)")
	check(absf(Rules.exit_rate() - 47.9167) < 0.01, "BRAWL: 9.6 shown units/s out of the door (Alpha 11: one every 12 px)")
	var bmap := MapBuilder.load_map("res://maps/004-two-piers.json")
	var bsim := Sim.new()
	bsim.setup(bmap, MapBuilder.layout(bmap), {3: "A", 4: "B"}, {"A": "null", "B": "null"}, 1)
	bsim.nodes[3]["units"] = 400.0
	var bh := bsim.send(3, 1, 1.0)
	var t_in := -1.0
	var t_done := -1.0
	var before: float = bsim.nodes[1]["units"]
	var bt := 0.0
	while bt < 40.0 and t_done < 0.0:
		bsim.step(0.02)
		bt += 0.02
		if t_in < 0.0 and (bsim.nodes[1]["owner"] == "A" or bsim.nodes[1]["units"] != before):
			t_in = bt
		if t_in >= 0.0 and not bsim.hordes.any(func(x): return x["id"] == bh["id"]):
			t_done = bt
	var enter_rate := 400.0 / maxf(t_done - t_in, 0.01)
	print("      brawl: first arrival %.2f s, 400 units poured in over %.2f s (%.1f/s)" % [t_in, t_done - t_in, enter_rate])
	check(absf(enter_rate - Rules.exit_rate()) / Rules.exit_rate() < 0.1, "BRAWL: units enter at the rate they left (Alpha 11 spacing)")
	var bh2 := bsim.send(4, 2, 1.0)
	bsim.step(0.5)
	check(not bsim.recall(bh2["id"]), "BRAWL: no RECALL - it is SIEGE only")
	Rules.bridge_combat = true

	# ---------------------------------------------------------------- Alpha 16: colours read per player
	Rules.assign_colors(["A", "B", "C", "D"], {"A": "null", "B": "null", "C": "null", "D": "null"}, "A", "A", {})
	var cols := ["A", "B", "C", "D"].map(func(s): return Rules.seat_color(s))
	var min_gap := 1.0
	for i in range(cols.size()):
		for j in range(i + 1, cols.size()):
			min_gap = minf(min_gap, Rules._hue_gap(cols[i], cols[j]))
	check(min_gap > 0.12, "FFA4: every player a clearly different hue (closest %.2f)" % min_gap)
	Rules.assign_colors(["A", "B", "C", "D"], {"A": "null", "B": "null", "C": "null", "D": "null"}, "A", "A", {"A": 0, "B": 0, "C": 1, "D": 1})
	var ta := Rules._hue_gap(Rules.seat_color("A"), Rules.seat_color("B"))
	var tc := Rules._hue_gap(Rules.seat_color("C"), Rules.seat_color("D"))
	check(ta > 0.12 and tc > 0.12, "2v2: team-mates have different hues too (%.2f / %.2f)" % [ta, tc])
	check(Rules._hue_gap(Rules.seat_color("A"), Rules.seat_color("C")) > 0.2, "2v2: the other team is another colour family")
	# 2v2v2: three teams, three families (cool / warm / violet) - two opposing teams never share a colour
	var six := ["A", "B", "C", "D", "E", "F"]
	var t3 := {"A": 0, "B": 0, "C": 1, "D": 1, "E": 2, "F": 2}
	var fam_of := func(c: Color) -> int:
		var best := 0
		var best_gap := 1.0
		for fi in range(Rules.TEAM_FAMILIES_3.size()):
			for k in Rules.TEAM_FAMILIES_3[fi]:
				var fg := Rules._hue_gap(c, Rules.HUES[k])
				if fg < best_gap:
					best_gap = fg
					best = fi
		return best
	for pick in ["A", "B", "C", "D", "E", "F", "faction"]:
		Rules.assign_colors(six, {"A": "null", "B": "null", "C": "null", "D": "null", "E": "null", "F": "null"}, "A", pick, t3)
		var c3 := {}
		var html := {}
		for s in six:
			c3[s] = Rules.seat_color(s)
			html[(c3[s] as Color).to_html()] = true
		check(html.size() == 6, "2v2v2 pick %s: six distinct colours" % pick)
		var opp_gap := 1.0
		for i in range(six.size()):
			for j in range(i + 1, six.size()):
				if t3[six[i]] != t3[six[j]]:
					opp_gap = minf(opp_gap, Rules._hue_gap(c3[six[i]], c3[six[j]]))
		check(opp_gap > 0.07, "2v2v2 pick %s: no two opposing players share a hue (closest %.3f)" % [pick, opp_gap])
		var mates := [Rules._hue_gap(c3["A"], c3["B"]), Rules._hue_gap(c3["C"], c3["D"]), Rules._hue_gap(c3["E"], c3["F"])]
		check(mates.min() > 0.12, "2v2v2 pick %s: team-mates differ (%.2f / %.2f / %.2f)" % [pick, mates[0], mates[1], mates[2]])
		var fams := {}
		for pair in [["A", "B"], ["C", "D"], ["E", "F"]]:
			var fa: int = fam_of.call(c3[pair[0]])
			if fa == fam_of.call(c3[pair[1]]):
				fams[fa] = true
		check(fams.size() == 3, "2v2v2 pick %s: each team reads as one family, three distinct families" % pick)

	# ---------------------------------------------------------------- AI: one order per vat per think
	# (a send supersedes the node's earlier order, and units leave only as the door emits them)
	var aim := MapBuilder.load_map("res://maps/004-two-piers.json")
	var aisim := Sim.new()
	aisim.setup(aim, MapBuilder.layout(aim), {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	for tid in [0, 1]:                                 # two threatened nodes of A, too weak to donate
		aisim.nodes[tid]["owner"] = "A"
		aisim.nodes[tid]["units"] = 5.0
		aisim.nodes[tid]["siege"] = {"B": 100.0}
	aisim.nodes[3]["units"] = 400.0                    # one strong donor
	SeatAI.new("A", 2.0, "Standard").think(aisim, 10.0)
	var from_d := aisim.hordes.filter(func(x): return x["route"][0] == 3)
	check(from_d.size() == 1 and from_d[0]["streaming"] and from_d[0]["target"] == 0,
			"AI never cancels its own order in the same think (one order from the donor, still streaming to the first target)")

	# ---------------------------------------------------------------- 0.18.6: a one-deck remote toggles
	var mr := MapBuilder.load_map("res://maps4/M-08-neon-delta.json")
	var seats_r := {}
	for st in mr["seats"]["1v1"]:
		seats_r[int(st["node"])] = st["seat"]
	var sr := Sim.new()
	sr.setup(mr, MapBuilder.layout(mr), seats_r, {"A": "null", "B": "ember"}, 1)
	sr.nodes[4]["owner"] = "A"
	var open0 := sr.is_edge_open(11)
	sr.fire_relay(4)
	for i in range(int((Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.5) / 0.1)):
		sr.step(0.1)
	check(open0 and not sr.is_edge_open(11), "a remote driving a single deck switches it off (Neon Delta)")
	for i in range(int(Rules.RELAY_COOLDOWN / 0.1) + 2):
		sr.step(0.1)
	sr.fire_relay(4)
	for i in range(int((Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.5) / 0.1)):
		sr.step(0.1)
	check(sr.is_edge_open(11), "... and back on")

	# ---------------------------------------------------------------- 0.18.6: waterfall
	# an order across a deck that retracts is still obeyed: the vat keeps sending and every unit pours
	# into the void (Daniele: "they should go even if the bridge is no longer there hence... waterfall")
	var sw := Sim.new()
	sw.setup(mr, MapBuilder.layout(mr), seats_r, {"A": "null", "B": "ember"}, 1)
	var ew := -1
	for i in range(sw.edges.size()):
		var e: Dictionary = sw.edges[i]
		if [int(e["a"]), int(e["b"])] in [[1, 7], [7, 1]]:
			ew = i
	var cw: int = sw.edge_controller.get(ew, -1)
	sw.nodes[1]["owner"] = "A"
	sw.nodes[1]["units"] = 600.0
	sw.nodes[7]["owner"] = "B"
	sw.nodes[7]["units"] = 5000.0
	if cw >= 0:
		sw.nodes[cw]["owner"] = "B"
	sw.send(1, 7, 1.0)
	for i in range(20):
		sw.step(0.1)
	var fired := cw >= 0 and sw.fire_relay(cw)
	for i in range(400):
		sw.step(0.1)
	var cut_ev := sw.events.filter(func(x): return x["type"] == "order_cut")
	var fell: float = sw.fall_losses.get("A", 0.0)
	var carried_w: float = 0.0
	for x in sw.events:
		if x["type"] == "carried" and x["seat"] == "A":
			carried_w += x["units"]
	check(fired and not sw.is_edge_open(ew) and cut_ev.is_empty() and fell > 350.0 and carried_w + fell > 590.0,
			"a retracted deck under an order: riders carried in, the vat keeps sending and the rest pours into the void (carried %.0f + fell %.0f of 600)" % [carried_w, fell])
	var pour_evs := 0
	var chunk_evs := 0
	for x in sw.fx_events:
		if x["type"] == "fall":
			if x.get("pour", false):
				pour_evs += 1
			else:
				chunk_evs += 1
	check(pour_evs > 20 and chunk_evs <= 3,
			"the waterfall is one motion: the line walks off the lip (%d pour steps, %d whole-stretch falls)" % [pour_evs, chunk_evs])

	# ---------------------------------------------------------------- 0.18.7: cannons kill where the laser hits
	# (Daniele: "towers kills enemies blobs from the bottom instead of from the top") - both modes
	for brawl_k in [true, false]:
		Rules.bridge_combat = not brawl_k
		var mode_k: String = "BRAWL" if brawl_k else "SIEGE"
		for send_k in [400.0, 20.0]:                       # a line still streaming out, a finished one
			var kc := Sim.new()
			kc.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
			var cn: Dictionary = kc.nodes[1]
			cn["owner"] = "A"
			cn["units"] = 50.0
			cn["attachment"] = "cannon"
			cn["cannon_tier"] = 3
			cn["cannon_cd"] = 99.0                         # held until the line is in place
			kc.nodes[0]["owner"] = "B"
			kc.nodes[0]["units"] = send_k
			var kh := kc.send(0, 1, 1.0)                   # a line coming at the tower
			var c1: Vector3 = cn["pos"]
			run_until(kc, func(): return (Sim.sample(kh, kh["s"])[0] as Vector3).distance_to(c1) < Rules.CANNON_RANGE - 1.0, 10.0, 0.02)
			var what := "%s, %s line" % [mode_k, "streaming" if kh["streaming"] else "finished"]
			check(kh["streaming"] == (send_k > 100.0) and kc._hit_head(cn, kh), "%s: a line coming at a tower is hit at its head" % what)
			kh["speed"] = 0.0                              # hold it still: only the cannon moves it
			cn["cannon_cd"] = 0.0
			kc.step(0.02)                                  # the burst starts
			var u0: float = kh["units"]
			var s0k: float = kh["s"]
			var len0: float = Sim.chain_length(kh)
			var left0: float = cn["cannon_kill_left"]
			var lost0: float = kc.combat_losses.get("B", 0.0)
			var emit0: float = kc.nodes[0]["streaming"].get("remaining", 0.0)
			kc.step(0.1)
			var emitted: float = emit0 - kc.nodes[0]["streaming"].get("remaining", 0.0)
			var budget_k: float = left0 - cn["cannon_kill_left"]
			var back_want: float = budget_k * len0 / u0 if len0 >= s0k - 0.001 else maxf(0.0, len0 - Sim.full_length(u0 - budget_k))
			var tail0: float = s0k - len0
			var tail1: float = kh["s"] - Sim.chain_length(kh)
			check(absf((u0 + emitted - kh["units"]) - budget_k) < 0.01 and absf(kc.combat_losses.get("B", 0.0) - lost0 - budget_k) < 0.01
					and budget_k > 0.0, "%s: a burst step kills exactly its budget (%.1f units)" % [what, budget_k])
			check(absf((s0k - kh["s"]) - back_want) < 0.01 and absf(kh["fcut"] - back_want) < 0.01 and absf(tail1 - tail0) < 0.05,
					"%s: the kill pulls the head back by the length it took (%.2f m) and leaves the tail where it was (%.2f -> %.2f)" % [what, s0k - kh["s"], tail0, tail1])
			check(s0k - kh["s"] > 0.2 * budget_k * Rules.metres_per_unit(), "%s: the front bodies are the ones gone (head %.2f m back)" % [what, s0k - kh["s"]])
			if kh["streaming"] or send_k > 100.0:
				check(kh["streaming"] and kc.nodes[0]["streaming"].get("hid", -1) == kh["id"], "%s: a streaming line keeps streaming under fire" % what)
			check((cn["cannon_target"] as Vector3).distance_to(Sim.sample(kh, kh["s"])[0]) < 0.01, "%s: the laser aims at the head it kills" % what)
			var lost1: float = kc.combat_losses.get("B", 0.0)
			for i in range(40):
				kc.step(0.05)
			var burst_kill: float = kc.combat_losses.get("B", 0.0) - lost1 + budget_k
			var want_k: float = Rules.CANNON_STATS[3]["kill"] if send_k > 100.0 else u0
			check(absf(burst_kill - want_k) < 0.5 or (not (kh in kc.hordes) and burst_kill < want_k),
					"%s: the whole burst kills its budget or the whole line, no more (%.1f of %.0f)" % [what, burst_kill, want_k])
		# a line leaving the tower: the beam hits its tail, the head is untouched
		var kt := Sim.new()
		kt.setup(map, pos, {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
		kt.nodes[1]["owner"] = "B"
		kt.nodes[1]["units"] = 30.0
		var lh := kt.send(1, 0, 1.0)
		run_until(kt, func(): return not lh["streaming"], 5.0, 0.02)
		var ct: Dictionary = kt.nodes[1]
		ct["owner"] = "A"
		ct["attachment"] = "cannon"
		ct["cannon_tier"] = 3
		ct["cannon_cd"] = 0.0
		lh["speed"] = 0.0
		kt.step(0.02)
		var ls0: float = lh["s"]
		var lu0: float = lh["units"]
		kt.step(0.05)
		check(not kt._hit_head(ct, lh) and lh["units"] < lu0 and absf(lh["s"] - ls0) < 0.001,
				"%s: a line leaving the tower is hit at its tail (head stays at %.1f m, %.1f -> %.1f units)" % [mode_k, ls0, lu0, lh["units"]])
	Rules.bridge_combat = true
	_goo_territory()
	_skills_tests()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)


func _goo_territory() -> void:
	## TERRITORY: GOO (0.18.7) is a pure view: the toggle only counts in BRAWL, the goo follows the
	## owners (homes covered, neutral bare), a capture spreads and settles, a closed deck drops its goo,
	## switching back to NEON hides every piece. No sim state is touched.
	var was_goo := Rules.goo_territory
	var was_bc := Rules.bridge_combat
	Rules.goo_territory = true
	Rules.bridge_combat = true
	check(not Rules.goo_look(), "GOO territory is off in SIEGE (its hordes are goo already)")
	Rules.bridge_combat = false
	check(Rules.goo_look(), "GOO territory is on in BRAWL when the option is")
	var map := MapBuilder.load_map("res://maps4/A-01-orbital-nexus.json")
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var gs := Sim.new()
	gs.setup(map, MapBuilder.layout(map), seats, {"A": "null", "B": "ember"}, 3)
	var holder := Node3D.new()
	root.add_child(holder)
	var gvis := MapBuilder.build3(holder, gs, map)
	var goo := GooTerritory.new()
	holder.add_child(goo)
	var collapsed_edges := {}
	goo.setup(gs, gvis, collapsed_edges, false)
	var before := JSON.stringify(gs.nodes)
	goo.sync(0.05)
	var home: int = seats.keys()[0]
	var neutral := -1
	for n in gs.nodes:
		if n["owner"] == "" and goo._plat.has(n["id"]):
			neutral = n["id"]
			break
	var home_mi: MeshInstance3D = goo._plat[home]["mi"]
	check(goo.built and home_mi.visible and (home_mi.mesh as ArrayMesh).get_surface_count() == 1,
			"GOO: the home platform is under goo from the first frame (%d vertices)" % (home_mi.mesh as ArrayMesh).surface_get_array_len(0))
	check(neutral >= 0 and not (goo._plat[neutral]["mi"] as MeshInstance3D).visible, "GOO: a neutral platform stays bare")
	var half_on := 0
	var half_off := 0
	for i in goo._half:
		for h in range(2):
			var p = goo._half[i][h]
			if p == null:
				continue
			var nid: int = gs.edges[i]["a"] if h == 0 else gs.edges[i]["b"]
			var owned: bool = gs.nodes[nid]["owner"] != "" and gs.is_edge_open(i)
			if (p["mi"] as MeshInstance3D).visible == owned:
				half_on += 1
			else:
				half_off += 1
	check(half_off == 0 and half_on > 0, "GOO: every deck half follows its end's owner (%d right, %d wrong)" % [half_on, half_off])
	check(JSON.stringify(gs.nodes) == before, "GOO touched no sim state (a pure view)")
	gs.nodes[neutral]["owner"] = "B"
	goo.sync(0.05)
	var np: Dictionary = goo._plat[neutral]
	check(np["t"] >= 0.0 and (np["mi"] as MeshInstance3D).visible and (np["mi"] as MeshInstance3D).material_override == np["anim"],
			"GOO: a capture starts the spread on the platform's own animation material")
	for k in range(40):
		goo.sync(0.05)
	check(np["t"] < 0.0 and np["drawn"] == "B" and (np["mi"] as MeshInstance3D).material_override == goo._steady_for("B"),
			"GOO: the spread settles within 2 s on the shared seat material")
	var shared := goo._steady_for("B") == goo._steady_for("B") and goo._steady.size() <= 2
	check(shared, "GOO: one shared material per colour (%d)" % goo._steady.size())
	Rules.goo_territory = false
	goo.sync(0.05)
	var any_visible := false
	for p in goo._pieces():
		any_visible = any_visible or (p["mi"] as MeshInstance3D).visible
	check(not any_visible, "NEON again: no goo piece shows")
	holder.queue_free()
	Rules.goo_territory = was_goo
	Rules.bridge_combat = was_bc


# ------------------------------------------------------------------ SKILLS 2.0 (0.18.7)
func _mk(m: Dictionary, fa: String, fb: String, lo := {}, seats := {}) -> Sim:
	var s := Sim.new()
	var st: Dictionary = seats if not seats.is_empty() else {int(m["seats"]["1v1"][0]["node"]): "A", int(m["seats"]["1v1"][1]["node"]): "B"}
	s.setup(m, MapBuilder.layout(m), st, {"A": fa, "B": fb}, 1, {}, lo)
	return s


func _steps(s: Sim, seconds: float, dt := 0.05) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		s.step(dt)
		t += dt


func _charged(s: Sim, seat: String) -> void:
	s.ult_charge[seat] = 1.0
	s.ult_since[seat] = 100.0


func _skills_tests() -> void:
	var tp := MapBuilder.load_map("res://maps/004-two-piers.json")       # 3 - 1 - 0 - 2 - 4, no relays
	var sw := MapBuilder.load_map("res://maps/010-first-switch.json")    # switch relays 1 and 2
	var rot := MapBuilder.load_map("res://maps/061-switchback-foundry.json")   # rotation relay 0
	# ---------------------------------------------------------------- the table
	var ok := true
	for id in Rules.SKILLS:
		var sk: Dictionary = Rules.SKILLS[id]
		ok = ok and sk.has("name") and sk.has("slot") and sk.has("cd") and sk.has("target") and sk.has("desc")
		if sk["slot"] == "ultimate":
			ok = ok and Rules.FACTION_ULTIMATE_ID[sk["faction"]] == id
	check(ok and Rules.ACTIVE_SKILLS.size() == 5 and Rules.MAP_SKILLS.size() == 5 and Rules.FACTION_ULTIMATE_ID.size() == 5 and Rules.SKILLS.size() == 15,
			"skills table: 5 active + 5 map + 5 ultimates, each with name, slot, cd, target and desc")
	check(Rules.FACTION_ULTIMATE.values().map(func(v): return v[0]) == ["Rewire", "Echo Split", "Superbloom", "Core Meltdown", "Relay Aegis"],
			"FACTION_ULTIMATE carries the approved names")
	# ---------------------------------------------------------------- loadouts
	var s := _mk(sw, "vex", "bloom", {"A": {"active": "scorch", "map": "anchor"}})
	check(s.loadouts["A"] == {"active": "scorch", "map": "anchor", "ultimate": "rewire"}, "a chosen loadout; the ultimate follows the faction")
	check(s.loadouts["B"] == {"active": "spore_burst", "map": "mire", "ultimate": "superbloom"}, "a seat without one gets its faction's default")
	s = _mk(sw, "vex", "null", {"A": {"active": "nuke"}})
	check(s.loadouts["A"]["active"] == "surge" and s.loadouts["A"]["map"] == "relay_hack", "unknown ids fall back to the default; relay skills kept on a relay map")
	s = _mk(tp, "vex", "null", {"B": {"map": "relay_hack"}})
	check(s.loadouts["A"]["map"] == "mire" and s.loadouts["B"]["map"] == "demolish", "no relays on the map: Relay Hack / Bypass become the faction's other map skill")
	# ---------------------------------------------------------------- validation, cooldown, ABILITIES OFF
	Rules.abilities_on = false
	s = _mk(tp, "solar", "null")
	check(not s.can_cast("A", "active", 3) and "off" in s.cast_check("A", "active", 3), "ABILITIES OFF: nothing casts")
	Rules.abilities_on = true
	s = _mk(tp, "solar", "null")
	check(s.can_cast("A", "active", 3) and not s.can_cast("A", "active", 4) and not s.can_cast("A", "active", 99) and not s.can_cast("A", "banana", 3),
			"Fortify: own node only (not the enemy's, not a bad id, not a bad slot)")
	check(s.cast("A", "active", 3) and absf(s.cooldown("A", "active") - 35.0) < 0.001 and not s.can_cast("A", "active", 3), "a cast starts its 35 s cooldown")
	check(s.fx_events.any(func(e): return e["type"] == "skill" and e["id"] == "fortify" and e["seat"] == "A"), "a cast pushes a skill fx event")
	_steps(s, 35.1, 0.5)
	check(s.can_cast("A", "active", 3), "the cooldown runs out")
	check("charging" in s.cast_check("A", "ultimate", 3), "the ultimate waits for its charge")
	# ---------------------------------------------------------------- Surge (both modes)
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		s = _mk(tp, "null", "null", {"A": {"active": "surge"}})
		s.nodes[3]["units"] = 150.0
		var h := s.send(3, 0, 1.0)
		_steps(s, 1.5)
		var a0: float = h["s"]
		_steps(s, 1.0)
		var plain: float = h["s"] - a0
		check(s.cast("A", "active", h["id"]), tag + ": Surge on a moving line")
		a0 = h["s"]
		_steps(s, 1.0)
		check(absf((h["s"] - a0) / plain - 1.5) < 0.05, tag + ": Surge = +50 %% speed (%.2f)" % ((h["s"] - a0) / plain))
		_steps(s, 7.5)
		check(s.effects_on("horde", h["id"]).is_empty(), tag + ": Surge ends after 8 s (or with the line)")
	Rules.bridge_combat = true
	# ---------------------------------------------------------------- Spore Burst
	s = _mk(tp, "bloom", "null")
	s.nodes[3]["units"] = 20.0
	var u0: float = s.nodes[3]["units"]
	_steps(s, 1.0)
	var d0: float = s.nodes[3]["units"] - u0
	check(not s.can_cast("A", "active", 4), "Spore Burst: not on an enemy vat")
	check(s.cast("A", "active", 3), "Spore Burst on an own vat")
	u0 = s.nodes[3]["units"]
	_steps(s, 1.0)
	check(absf((s.nodes[3]["units"] - u0) / d0 - 1.8) < 0.02, "Spore Burst: the vat produces 1.8x (%.2f)" % ((s.nodes[3]["units"] - u0) / d0))
	s.nodes[3]["units"] = Rules.CAPS[s.nodes[3]["tier"]] - 1.0
	_steps(s, 1.0)
	check(s.nodes[3]["units"] <= Rules.CAPS[s.nodes[3]["tier"]], "Spore Burst stays within the cap")
	# ---------------------------------------------------------------- Fortify: the garrison damage divisor, both modes
	s = _mk(tp, "null", "null", {"B": {"active": "fortify"}})
	s.nodes[1]["owner"] = "B"
	s.nodes[1]["units"] = 100.0
	s.cast("B", "active", 1)
	Rules.bridge_combat = false
	s._land_classic(s.nodes[1], "A", 33.0)
	check(absf(s.nodes[1]["units"] - (100.0 - 33.0 / 1.65)) < 0.01, "BRAWL: a fortified garrison loses 1.65x less (33 attackers kill %.1f)" % (100.0 - s.nodes[1]["units"]))
	Rules.bridge_combat = true
	var losses := []
	for fort in [false, true]:
		s = _mk(tp, "null", "null", {"B": {"active": "fortify"}})
		s.nodes[1]["owner"] = "B"
		s.nodes[1]["units"] = 400.0
		s.nodes[1]["siege"]["A"] = 200.0
		if fort:
			s.cast("B", "active", 1)
		s._node_fights(0.1)
		losses.append(400.0 - s.nodes[1]["units"])
	check(absf(losses[0] / losses[1] - 1.65) < 0.01, "SIEGE: the besieged garrison takes 1.65x less damage (%.2f)" % (losses[0] / losses[1]))
	# ---------------------------------------------------------------- Scorch (both modes)
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		s = _mk(tp, "null", "ember")
		s.nodes[3]["units"] = 300.0
		var h := s.send(3, 0, 1.0)
		var deck: Dictionary = h["spans"][0]
		var t := run_until(s, func(): return h["s"] > deck["s1"], 20.0)
		var before: float = s.combat_losses.get("A", 0.0)
		check(s.cast("B", "active", deck["edge"]), tag + ": Scorch on the deck under A's line")
		check(s.events[-1].get("affects", []) == ["A"], tag + ": the cast names the seat it hits")
		_steps(s, 5.2)
		var burnt: float = s.combat_losses.get("A", 0.0) - before
		var ends := s.events.filter(func(e): return e["type"] == "skill_end" and e["id"] == "scorch")
		check(not ends.is_empty() and absf(ends[-1]["kills"] - 10.0 * Rules.SCALE) < 0.5 and burnt >= 10.0 * Rules.SCALE - 0.5,
				tag + ": Scorch burns enemy lines on the deck, at most 10 shown units (%.1f sim)" % (ends[-1]["kills"] if not ends.is_empty() else -1.0))
	Rules.bridge_combat = true
	# ---------------------------------------------------------------- Ghost Line (both modes)
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		s = _mk(tp, "null", "null")
		s.nodes[3]["units"] = 200.0
		var home_b: float = s.nodes[4]["units"]
		check(not s.can_cast("A", "active", [4, 3]) and not s.can_cast("A", "active", 3), tag + ": Ghost Line starts from an own node, with a destination")
		check(s.cast("A", "active", [3, 4]), tag + ": Ghost Line cast 3 -> 4")
		var g: Dictionary = s.hordes[-1]
		var ev: Dictionary = s.fx_events.filter(func(e): return e["type"] == "skill")[-1]
		check(g.get("decoy", false) and g["ordered"] == 100.0 and s.nodes[3]["units"] >= 200.0 and ev.get("private", "") == "A",
				tag + ": a decoy of half the vat, no units spent, the cast event private to its owner")
		_steps(s, 1.0)
		check(g["units"] > 0.0 and g["streaming"] and s.seat_strength("A") < s.nodes[3]["units"] + 1.0,
				tag + ": it streams out like a send but adds nothing to A's strength")
		run_until(s, func(): return not (g in s.hordes), 40.0)
		check(s.nodes[4]["owner"] == "B" and s.nodes[4]["units"] >= home_b and s.nodes[1]["owner"] == "" and s.combat_losses.get("B", 0.0) == 0.0,
				tag + ": it lands and vanishes: nothing captured, no garrison hurt")
		# cannons fire at it; no charge for decoy kills
		s = _mk(tp, "null", "null")
		s.nodes[3]["units"] = 200.0
		s.nodes[1]["owner"] = "B"
		s.nodes[1]["attachment"] = "cannon"
		s.nodes[1]["cannon_tier"] = 1
		s.nodes[1]["units"] = 30.0
		s.cast("A", "active", [3, 4])
		g = s.hordes[-1]
		run_until(s, func(): return s.events.any(func(e): return e["type"] == "cannon_burst"), 20.0)
		check(s.events.any(func(e): return e["type"] == "cannon_burst" and e["seat"] == "B"), tag + ": a Ghost Line triggers the cannons")
		_steps(s, 1.0)
		check(s.combat_losses.get("A", 0.0) == 0.0 and absf(s.charge("B") - s.time / Rules.ULT_CHARGE_TIME) < 0.001,
				tag + ": its losses are not real and give no ultimate charge")
		if not brawl:                                    # SIEGE: an enemy line touching it dissolves it
			s = _mk(tp, "null", "null")
			s.nodes[3]["units"] = 200.0
			s.nodes[4]["units"] = 200.0
			s.cast("A", "active", [3, 4])
			g = s.hordes[-1]
			var hb := s.send(4, 3, 1.0)
			run_until(s, func(): return not (g in s.hordes), 30.0)
			check(not (g in s.hordes) and s.fx_events.any(func(e): return e["type"] == "ghost_end" and e["why"] == "contact") and s.combat_losses.get("B", 0.0) == 0.0,
					"SIEGE: an enemy line touching a Ghost Line dissolves it; nobody fights")
	Rules.bridge_combat = true
	# ---------------------------------------------------------------- Demolish (both modes): warning, waterfall, rebuild
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		s = _mk(tp, "null", "ember")
		var e10 := s._edge_index(1, 0)
		s.nodes[3]["units"] = 300.0
		var h := s.send(3, 4, 1.0)
		check(s.cast("B", "map", e10), tag + ": Demolish the 1-0 deck")
		_steps(s, 2.9)
		check(s.is_edge_open(e10), tag + ": during the 3 s warning the deck still stands")
		_steps(s, 0.2)
		check(not s.is_edge_open(e10) and s.demolished.has(e10) and s.fx_events.any(func(e): return e["type"] == "demolish"), tag + ": then it is gone")
		check(s.find_route(3, 4).is_empty(), tag + ": no route crosses it")
		_steps(s, 8.0)
		check(s.fall_losses.get("A", 0.0) > 50.0 and (h in s.hordes and h["target"] == 4 or s.fall_losses.get("A", 0.0) > 250.0),
				tag + ": the order across it keeps streaming off the lip (waterfall: %.0f fell)" % s.fall_losses.get("A", 0.0))
		_steps(s, 12.2)
		check(s.is_edge_open(e10) and not s.demolished.has(e10), tag + ": the deck rebuilds after 20 s")
	Rules.bridge_combat = true
	s = _mk(sw, "null", "ember")
	check("relay" in s.cast_check("B", "map", 2), "Demolish refuses a relay deck")
	s = _mk(tp, "null", "ember", {"A": {"map": "anchor"}})
	var e10b := s._edge_index(1, 0)
	s.cast("B", "map", e10b)
	check(s.cast("A", "map", e10b), "Anchor the deck under a Demolish warning")
	_steps(s, 3.5)
	check(s.is_edge_open(e10b) and s.events.any(func(e): return e["type"] == "demolish_failed"), "Demolish fails on an anchored deck")
	check("anchored" in s.cast_check("B", "map", e10b) or s.cooldown("B", "map") > 0.0, "and an anchored deck can't be demolished")
	# ---------------------------------------------------------------- Mire (both modes; SIEGE: the stronger of Mire and goo, no stacking)
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		s = _mk(tp, "null", "bloom")
		s.nodes[3]["units"] = 150.0
		var h := s.send(3, 0, 1.0)
		var deck: Dictionary = h["spans"][0]
		run_until(s, func(): return h["s"] > deck["s0"] + 1.0, 20.0)
		var a0: float = h["s"]
		_steps(s, 0.5)
		var plain: float = h["s"] - a0
		check(s.cast("B", "map", deck["edge"]), tag + ": Mire on the deck under A's line")
		a0 = h["s"]
		_steps(s, 0.5)
		check(absf((h["s"] - a0) / plain - 0.6) < 0.03, tag + ": enemy lines 40 %% slower on it (%.2f)" % ((h["s"] - a0) / plain))
	Rules.bridge_combat = true
	s = _mk(tp, "null", "bloom")
	s.nodes[1]["owner"] = "B"
	s.nodes[0]["owner"] = "B"
	s.nodes[3]["units"] = 300.0
	var hg := s.send(3, 0, 1.0)
	run_until(s, func(): return s.on_enemy_goo(hg) or not (hg in s.hordes), 30.0)
	var goo_only := s.deck_slow(hg)
	s.cast("B", "map", s._current_span(hg)["edge"])
	check(absf(goo_only - Rules.GOO_SLOW) < 0.001 and absf(s.deck_slow(hg) - 0.6) < 0.001, "SIEGE: Mire on an enemy goo corridor: the stronger slow (0.6), not 0.7 x 0.6")
	# ---------------------------------------------------------------- Anchor: relays can't move it, no fling, half cannon kills
	s = _mk(sw, "null", "null", {"A": {"map": "anchor"}})
	s.nodes[1]["owner"] = "B"
	check(s.cast("A", "map", 2), "Anchor a switch deck")
	s.fire_relay(1)
	_steps(s, Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.2)
	check(s.nodes[1]["relay_index"] == 1 and s.is_edge_open(2) and s.is_edge_open(6), "the relay switches, but the anchored deck stays")
	_steps(s, 10.0 - Rules.RELAY_WARNING - Rules.RELAY_MOVE)
	check(not s.is_edge_open(2) and s.fx_events.any(func(e): return e["type"] == "relay_settle"), "when the anchor ends the relay's state applies")
	s = _mk(rot, "null", "null", {"A": {"map": "anchor"}})
	s.nodes[0]["owner"] = "B"
	s.nodes[1]["owner"] = "A"
	s.nodes[1]["units"] = 200.0
	var hr := s.send(1, 4, 1.0)                        # 1 -> 0 -> 4 over two r1 decks
	run_until(s, func(): return hr["s"] > hr["spans"][0]["s0"] + 2.0, 20.0)
	s.cast("A", "map", hr["spans"][0]["edge"])
	s.fire_relay(0)
	s.nodes[0]["relay_t"] = 0.0
	s.step(0.02)
	check(hr in s.hordes and s.fall_losses.get("A", 0.0) == 0.0, "a rotation does not fling a line off an anchored deck")
	var cannon_loss := []
	for anchored in [false, true]:
		s = _mk(tp, "null", "null", {"A": {"map": "anchor"}})
		s.nodes[1]["owner"] = "B"
		s.nodes[1]["attachment"] = "cannon"
		s.nodes[1]["cannon_tier"] = 1
		s.nodes[3]["units"] = 300.0
		var hc := s.send(3, 1, 1.0)
		s.nodes[3]["streaming"] = {}
		hc["streaming"] = false
		hc["units"] = 300.0
		hc["s"] = hc["spans"][0]["s1"] - 1.0
		if anchored:
			s.cast("A", "map", hc["spans"][0]["edge"])
		for k in range(60):
			s._step_structures(0.05)
		cannon_loss.append(300.0 - hc["units"])
	check(absf(cannon_loss[0] - 50.0) < 0.5 and absf(cannon_loss[1] - 25.0) < 0.5, "Anchor: your lines on it take half the cannon kills (%.0f vs %.0f)" % [cannon_loss[1], cannon_loss[0]])
	# ---------------------------------------------------------------- Bypass: both states for 8 s, then the normal outcome
	s = _mk(sw, "null", "null", {"A": {"map": "bypass"}})
	s.nodes[1]["owner"] = "B"
	check(s.cast("A", "map", 1), "Bypass an enemy relay")
	check(s.is_edge_open(2) and s.is_edge_open(6) and s.find_route(5, 3) == [5, 1, 3], "the relay holds both states: both decks stand, routes use either")
	s.fire_relay(1)
	s.nodes[5]["units"] = 300.0
	var hb2 := s.send(5, 0, 1.0)
	var ab: Dictionary = hb2["spans"][1]
	run_until(s, func(): return hb2["s"] > ab["s0"] + 3.0 and s.nodes[1]["relay_phase"] == "", 30.0)
	check(s.is_edge_open(2) and s.fall_losses.get("A", 0.0) == 0.0, "fired while bypassed, nothing moves and nobody falls")
	for e in s.effects:
		if e["id"] == "bypass":
			e["t"] = 0.01
	s.step(0.05)
	check(not s.is_edge_open(2) and s.fall_losses.get("A", 0.0) > 0.0, "Bypass over: the deck that goes away drops its riders (switch fate)")
	# ---------------------------------------------------------------- Relay Hack: fire or jam an enemy / neutral relay
	s = _mk(sw, "null", "null", {"A": {"map": "relay_hack"}})
	s.nodes[1]["owner"] = "B"
	check(s.cast("A", "map", 1) and s.nodes[1]["relay_phase"] == "warning" and absf(s.nodes[1]["relay_t"] - Rules.RELAY_WARNING) < 0.001,
			"Relay Hack fires an enemy relay with its normal warning")
	s = _mk(sw, "null", "null", {"A": {"map": "relay_hack"}})
	s.nodes[1]["owner"] = "B"
	check(s.cast("A", "map", [1, "jam"]) and absf(s.nodes[1]["relay_cd"] - 10.0) < 0.001 and not s.fire_relay(1), "...or jams it: +10 s on its cooldown")
	s = _mk(sw, "null", "null", {"A": {"map": "relay_hack"}})
	check(s.cast("A", "map", 2), "Relay Hack fires a neutral relay")
	_steps(s, Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.2)
	check(not s.is_edge_open(3) and s.is_edge_open(7), "a hacked neutral relay really switches")
	s = _mk(sw, "null", "null", {"A": {"map": "relay_hack"}})
	s.nodes[1]["owner"] = "A"
	check("enemy or neutral" in s.cast_check("A", "map", 1), "not on your own relay")
	# ---------------------------------------------------------------- Rewire
	s = _mk(sw, "vex", "null")
	s.nodes[1]["owner"] = "B"
	check("charging" in s.cast_check("A", "ultimate", null), "Rewire needs its charge")
	_charged(s, "A")
	s.nodes[5]["units"] = 200.0
	var hv := s.send(5, 0, 1.0)
	check(s.cast("A", "ultimate", null) and s.rewire_left("A") == 3 and absf(s.skill_speed(hv) - 1.5) < 0.001 and s.charge("A") == 0.0,
			"Rewire: all own lines +50 % speed, 3 relay fires, the charge spent")
	check(s.cast("A", "ultimate", 1) and s.nodes[1]["relay_phase"] == "warning" and s.rewire_left("A") == 2, "Rewire fires an enemy relay")
	check(s.cast("A", "ultimate", 2) and s.rewire_left("A") == 1 and not s.can_cast("A", "ultimate", 2), "and a neutral one, each relay once")
	_steps(s, 10.1)
	check(s.rewire_left("A") == 0 and s.skill_speed(hv) == 1.0, "Rewire ends after 10 s")
	# ---------------------------------------------------------------- Echo Split: up to 3 echoes; a landing jams the node
	s = _mk(rot, "null", "null", {}, {7: "A", 10: "B"})
	for id in [8, 9, 12]:
		s.nodes[id]["owner"] = "A"
		s.nodes[id]["units"] = 100.0
	s.nodes[7]["units"] = 100.0
	s.nodes[11]["owner"] = "B"
	for id in [7, 8, 9, 12]:
		s.send(id, 10, 1.0)
	_steps(s, 1.0)
	_charged(s, "A")
	var n_before := s.hordes.size()
	check(s.cast("A", "ultimate", null), "Echo Split with four lines on the move")
	var echoes := s.hordes.filter(func(h): return h.get("echo", false))
	check(echoes.size() == 3 and s.hordes.size() == n_before + 3 and echoes.all(func(h): return h["target"] == 11 and h.get("decoy", false)),
			"at most 3 echoes, each a decoy toward another enemy node")
	check(s.fx_events.any(func(e): return e["type"] == "ghosts" and e.get("private", "") == "A" and (e["hids"] as Array).size() == 3), "the echo ids go to their owner only")
	s = _mk(tp, "null", "null")
	s.nodes[2]["owner"] = "B"
	s.nodes[2]["attachment"] = ""
	var fake := {"id": 999, "owner": "A", "decoy": true, "echo": true}
	s._decoy_arrive(s.nodes[2], fake)
	check(s.is_disrupted(2) and s.production(s.nodes[2]) == 0.0, "an echo landing on an enemy node stops its vat")
	s.nodes[4]["attachment"] = "cannon"
	s.nodes[4]["cannon_tier"] = 1
	s.nodes[3]["units"] = 200.0
	var hx := s.send(3, 4, 1.0)
	run_until(s, func(): return (Sim.sample(hx, hx["s"])[0] as Vector3).distance_to(s.nodes[4]["pos"]) < Rules.CANNON_RANGE + 4.0 or not (hx in s.hordes), 30.0)
	s._decoy_arrive(s.nodes[4], {"id": 998, "owner": "A", "decoy": true, "echo": true})
	run_until(s, func(): return (Sim.sample(hx, hx["s"])[0] as Vector3).distance_to(s.nodes[4]["pos"]) < Rules.CANNON_RANGE - 1.0 or not (hx in s.hordes), 30.0)
	check(not s.events.any(func(e): return e["type"] == "cannon_burst"), "...and its cannon")
	_steps(s, 8.0)
	check(not s.is_disrupted(2), "the jam lasts 8 s")
	# ---------------------------------------------------------------- Superbloom: "cap" (default) and "under_attack"
	check(Rules.SUPERBLOOM_MODE == "cap", "Superbloom defaults to the cap variant (Daniele, 0.18.7)")
	s = _mk(tp, "bloom", "null")
	for id in [3, 1, 0]:
		s.nodes[id]["owner"] = "A"
		s.nodes[id]["tier"] = 4
		s.nodes[id]["units"] = 0.0
	_charged(s, "A")
	var base: float = 3.0 * Rules.PROD[4] * Rules.stat("bloom", "production")
	check(s.cast("A", "ultimate", null), "cap: castable with nothing under attack")
	u0 = s.nodes[3]["units"] + s.nodes[1]["units"] + s.nodes[0]["units"]
	s.step(0.1)
	var g1: float = s.nodes[3]["units"] + s.nodes[1]["units"] + s.nodes[0]["units"] - u0
	check(absf(g1 / (base * 0.1) - 1.5) < 0.01, "cap: every vat 1.5x (%.2f)" % (g1 / (base * 0.1)))
	_steps(s, 12.0)
	var total: float = s.nodes[3]["units"] + s.nodes[1]["units"] + s.nodes[0]["units"] - u0
	check(absf(total - (base * 12.1 + 40.0 * Rules.SCALE)) < 1.0, "cap: the extra stops at 40 shown units (extra %.1f sim)" % (total - base * 12.1))
	Rules.SUPERBLOOM_MODE = "under_attack"
	s = _mk(tp, "bloom", "null")
	_charged(s, "A")
	check("under attack" in s.cast_check("A", "ultimate", null), "under_attack: refused while nothing is attacked")
	s.nodes[4]["units"] = 100.0
	s.send(4, 3, 1.0)
	check(s.cast("A", "ultimate", null) and float(s.effects_on("seat", "A")[0]["left"]) < 0.0, "under_attack: castable once a line comes for you, no cap")
	u0 = s.nodes[3]["units"]
	s.step(0.1)
	check(absf((s.nodes[3]["units"] - u0) / (Rules.PROD[2] * Rules.stat("bloom", "production") * 0.1) - 1.5) < 0.01, "under_attack: 1.5x")
	Rules.SUPERBLOOM_MODE = "cap"
	# ---------------------------------------------------------------- Core Meltdown (both modes)
	for brawl in [false, true]:
		Rules.bridge_combat = not brawl
		var tag := "BRAWL" if brawl else "SIEGE"
		for garrison in [[40.0, 1], [400.0, 4]]:
			s = _mk(tp, "ember", "null")
			s.nodes[1]["owner"] = "B"
			s.nodes[1]["units"] = garrison[0]
			s.nodes[1]["tier"] = garrison[1]
			s.nodes[3]["units"] = 200.0
			_charged(s, "A")
			var h := s.send(3, 1, 1.0)
			_steps(s, 0.5)
			check("reaches its target" in s.cast_check("A", "ultimate", h["id"]), tag + ": Core Meltdown waits until the line is at its target")
			run_until(s, func(): return float(h["L"]) - float(h["s"]) <= 12.0, 20.0)
			var line: float = h["units"]
			var g0: float = s.nodes[1]["units"]
			var sac: float = maxf(line * 0.25, 20.0)
			var kills: float = minf(sac * 3.0, 300.0)
			var charge_b := s.charge("B")
			check(s.cast("A", "ultimate", h["id"]), tag + ": Core Meltdown on the arriving line")
			if g0 <= kills:
				check(s.nodes[1]["owner"] == "A" and absf(s.nodes[1]["units"] - (line - sac)) < 0.5 and not (h in s.hordes),
						tag + ": the garrison hits zero and the rest of the line (%.0f) captures" % (line - sac))
			else:
				check(s.nodes[1]["owner"] == "B" and absf(s.nodes[1]["units"] - (g0 - kills)) < 0.01 and absf(h["units"] - (line - sac)) < 0.01,
						tag + ": 25 %% sacrificed (%.0f), 3 defenders each (%.0f killed)" % [sac, kills])
			s.step(0.05)
			check(absf(s.charge("B") - charge_b - 0.05 / Rules.ULT_CHARGE_TIME) < 0.0001, tag + ": no charge from the meltdown")
	Rules.bridge_combat = true
	s = _mk(tp, "ember", "null")
	s.nodes[3]["units"] = 1000.0
	s.nodes[3]["tier"] = 4
	_charged(s, "A")
	s.nodes[2]["owner"] = "B"
	s.nodes[2]["units"] = 800.0
	s.nodes[2]["tier"] = 4
	var hm := s.send(3, 2, 1.0)
	run_until(s, func(): return float(hm["L"]) - float(hm["s"]) <= 12.0, 30.0)
	var gm: float = s.nodes[2]["units"]
	var lm: float = hm["units"]
	s.cast("A", "ultimate", hm["id"])
	check(lm * 0.25 * 3.0 > 300.0 and absf(gm - s.nodes[2]["units"] - 300.0) < 0.01 and absf(lm - hm["units"] - lm * 0.25) < 0.01, "a big line: no cap on the sacrifice, 60 shown kills at most")
	# ---------------------------------------------------------------- Relay Aegis
	s = _mk(tp, "solar", "null")
	for id in [1, 0]:
		s.nodes[id]["owner"] = "A"
	_charged(s, "A")
	check(s.cast("A", "ultimate", 1), "Relay Aegis on node 1")
	check(s.garrison_div(s.nodes[3]) == 1.8 and s.garrison_div(s.nodes[0]) == 1.8 and s.garrison_div(s.nodes[2]) == 1.0 and absf(s.prod_mult(s.nodes[1]) - 1.2) < 0.001,
			"the node and its own neighbours: 1.8x less garrison damage, +20 % production")
	check(s.anchor_state(s._edge_index(1, 3)) == true and s.anchor_state(s._edge_index(1, 0)) == true and s.anchor_state(s._edge_index(0, 2)) == null,
			"the decks between them are anchored")
	Rules.bridge_combat = false
	s.nodes[3]["units"] = 100.0
	s._land_classic(s.nodes[3], "B", 18.0)
	var aegis_kill := 18.0 / (Rules.stat("solar", "health") * Rules.stat("solar", "garrison") * 1.8)
	check(absf(s.nodes[3]["units"] - (100.0 - aegis_kill)) < 0.01, "BRAWL: 18 attackers kill %.1f of a SOLAR Aegis garrison (1.8x less)" % aegis_kill)
	Rules.bridge_combat = true
	s = _mk(sw, "solar", "null", {"B": {"map": "relay_hack"}})
	s.nodes[1]["owner"] = "A"
	_charged(s, "A")
	s.cast("A", "ultimate", 5)
	check(s.is_relay_locked(1) and not s.fire_relay(1) and "locked" in s.cast_check("B", "map", 1), "the relays among them are locked, for their owner and for a hacker")
	_steps(s, 12.1)
	check(not s.is_relay_locked(1) and s.effects.is_empty(), "Relay Aegis ends after 12 s")
	# ---------------------------------------------------------------- ultimate charge: ~120 s, kills speed it, never under 90 s
	s = _mk(tp, "null", "null")
	_steps(s, 119.0, 0.5)
	check(s.charge("A") < 1.0 and s.charge("A") > 0.98, "natural charge: not ready at 119 s")
	_steps(s, 1.5, 0.5)
	check(s.charge("A") >= 1.0, "ready at 120 s")
	s = _mk(tp, "null", "null")
	s._credit("A", "B", 10000.0)
	s.step(0.5)
	check(absf(s.charge("A") - 0.5 / Rules.ULT_MIN_TIME) < 0.0001, "enemy kills speed the charge, capped by the 90 s floor")
	_steps(s, 88.5, 0.5)
	s._credit("A", "B", 10000.0)
	s.step(0.5)
	check(s.charge("A") < 1.0, "never ready before 90 s (%.3f at 89.5 s)" % s.charge("A"))
	_steps(s, 1.0, 0.5)
	check(s.charge("A") >= 1.0, "ready at 90 s with enough kills")
	s = _mk(tp, "null", "null", {}, {3: "A", 4: "B"})
	s.teams = {"A": 0, "B": 0}
	s._credit("A", "", 5000.0)                          # neutral
	s._credit("A", "B", 5000.0)                         # an ally
	s.step(0.5)
	check(absf(s.charge("A") - 0.5 / Rules.ULT_CHARGE_TIME) < 0.0001, "no charge from neutrals or allies")
	s = _mk(tp, "null", "null")
	s.nodes[3]["units"] = 200.0
	s.nodes[1]["owner"] = "B"
	s.nodes[1]["units"] = 2000.0
	s.nodes[1]["tier"] = 4
	var hk := s.send(3, 1, 1.0)
	run_until(s, func(): return not (hk in s.hordes), 30.0)
	check(s.charge("B") > s.time / Rules.ULT_CHARGE_TIME + 0.001, "a garrison killing attackers charges its owner (%.3f vs %.3f natural)" % [s.charge("B"), s.time / Rules.ULT_CHARGE_TIME])
	s = _mk(sw, "null", "null")
	s.nodes[1]["owner"] = "B"
	s.nodes[1]["units"] = 0.0                            # (no garrison to fight on the way: only the fall)
	s.nodes[5]["units"] = 300.0
	var hf := s.send(5, 0, 1.0)
	run_until(s, func(): return hf["s"] > hf["spans"][1]["s0"] + 4.0, 30.0)
	s.fire_relay(1)
	run_until(s, func(): return s.nodes[1]["relay_phase"] == "", 8.0)
	check(s.fall_losses.get("A", 0.0) > 0.0 and absf(s.charge("B") - s.time / Rules.ULT_CHARGE_TIME) < 0.001, "no charge from falls")
	# ---------------------------------------------------------------- AI: every level casts in a match
	for lv in Rules.AI_LEVELS:
		var m4 := MapBuilder.load_map("res://maps4/M-08-neon-delta.json")
		s = _mk(m4, "ember", "vex")
		var ais := [SeatAI.new("A", 2.5, lv), SeatAI.new("B", 2.5, lv)]
		while not s.over and s.time < 240.0:
			for ai in ais:
				ai.think(s, 0.1)
			s.step(0.1)
		var n_casts: int = ais[0].casts + ais[1].casts
		check(n_casts > 0, "AI %s casts skills in a match (%d casts in %.0f s)" % [lv, n_casts, s.time])
