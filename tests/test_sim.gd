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
	check(sim14b.fall_losses.get("A", 0.0) > 0.0, "a line that walks onto a dissolving deck falls off its lip")
	check(not crossed_late, "...and never reaches the far side over the missing deck")

	# retract (0.18.7, Daniele: "it takes the ground away from under the feet, not pull the unit"): troops
	# still on the deck when it starts to retract fall; nobody is carried into the relay's node
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
	h15["speed"] = 0.2                                # still on the deck when the motion starts
	var b15: float = sim15.nodes[1]["units"]
	sim15.fire_relay(1)
	run_until(sim15, func(): return sim15.nodes[1]["relay_phase"] == "", 8.0)
	check(sim15.fall_losses.get("A", 0.0) > 0.0 and sim15.nodes[1]["siege"].is_empty() and sim15.nodes[1]["owner"] == "B"
			and sim15.nodes[1]["units"] <= b15 + 0.01, "the retract dropped A's units into the void - none landed on B's platform (fell %.0f)" % sim15.fall_losses.get("A", 0.0))
	check(not sim15.events.any(func(e): return e["type"] == "carried"), "nothing is carried in")
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
	check(sim16.events.any(func(e): return e["type"] == "fall" and e.get("why", "") == "relay"), "the fall event is recorded (no combat credit)")
	check(not sim16.hordes.any(func(x): return x.has("ride")), "nobody rides a deck")
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
	# the relay kinds that do not turn drop their troops straight down (plain fall fx), no fling
	check(sim14.fx_events.any(func(e): return e["type"] == "fall") and not sim14.fx_events.any(func(e): return e["type"] == "fling"),
			"a switch deck still drops its troops with the plain fall")
	check(sim15.fx_events.any(func(e): return e["type"] == "fall" and e.get("relay", -1) == 1) and not sim15.fx_events.any(func(e): return e["type"] == "fling"),
			"a retract drops its troops with the plain fall (the HUD toast names the relay), nobody is flung")
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
	check(fired and not sw.is_edge_open(ew) and cut_ev.is_empty() and carried_w == 0.0 and fell > 590.0,
			"a retracted deck under an order: nobody carried in, the vat keeps sending and every unit pours into the void (fell %.0f of 600)" % fell)
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

	# ---------------------------------------------------------------- 0.18.7: relays take the ground away
	# (Daniele: "units on the bridge have 1 sec to clear the bridge then bye bye, this applies to all type of
	# switch including the retract ... rotation bridge when it starts moving, all on it falls") - both modes
	for brawl_r in [true, false]:
		Rules.bridge_combat = not brawl_r
		var mode_r: String = "BRAWL" if brawl_r else "SIEGE"
		for c in [["retract", "res://maps4/M-08-neon-delta.json", 7, 1, 7], ["remote", "res://maps4/M-08-neon-delta.json", 4, 6, 7],
				["switch", "res://maps/010-first-switch.json", 1, 5, 0], ["rotation", "res://maps/061-switchback-foundry.json", 0, 1, 0]]:
			var kind: String = c[0]
			var what := "%s %s" % [mode_r, kind]
			# a short line wholly on the deck at the warning, near enough its far pier to clear it in 1 s: safe
			var rs := _relay_sim(c[1], c[2], c[3])
			rs.nodes[c[3]]["units"] = 12.0
			var hs: Dictionary = rs.send(c[3], c[4], 1.0)
			var dk: Dictionary = _relay_deck(rs, hs, c[2])
			var reach: float = Rules.move_speed() * Rules.RELAY_WARNING * 0.75
			run_until(rs, func(): return not (hs in rs.hordes) or (not hs["streaming"] and hs["s"] - Sim.chain_length(hs) > dk["s0"]
					and hs["s"] - Sim.chain_length(hs) > dk["s1"] - reach), 30.0, 0.02)
			var whole: bool = hs in rs.hordes and hs["s"] < dk["s1"] and hs["s"] - Sim.chain_length(hs) > dk["s0"]
			var fired_r: bool = rs.fire_relay(c[2])
			run_until(rs, func(): return rs.nodes[c[2]]["relay_phase"] == "moving", 3.0, 0.02)
			rs.step(0.02)
			check(whole and fired_r and rs.fall_losses.get("A", 0.0) == 0.0,
					"%s: a line on the deck at the warning that clears it within %.0f s is safe (fell %.1f)" % [what, Rules.RELAY_WARNING, rs.fall_losses.get("A", 0.0)])
			# a long line still on the deck when the motion starts: that part falls at once, the rest pours off the lip
			var rl := _relay_sim(c[1], c[2], c[3])
			rl.nodes[c[3]]["units"] = 400.0
			var hl: Dictionary = rl.send(c[3], c[4], 1.0)
			var dl: Dictionary = _relay_deck(rl, hl, c[2])
			run_until(rl, func(): return hl["s"] > dl["s0"] + 1.0, 30.0, 0.02)
			hl["speed"] = 0.05                             # its head stays on the deck through the warning
			rl.fire_relay(c[2])
			var carried0: float = rl.nodes[c[2]]["units"]
			run_until(rl, func(): return rl.nodes[c[2]]["relay_phase"] == "moving", 3.0, 0.02)
			rl.step(0.02)
			var fell_tick: float = rl.fall_losses.get("A", 0.0)
			check(fell_tick > 0.0 and not hl.has("ride") and hl in rl.hordes and absf(hl["s"] - dl["s0"]) < 0.05 and hl.get("pour", false),
					"%s: the line on the deck at the motion's start falls at once (%.0f units), its head parked at the lip, nobody riding" % [what, fell_tick])
			hl["speed"] = 1.0
			for i in range(40):
				rl.step(0.05)
			check(rl.fall_losses.get("A", 0.0) > fell_tick + 20.0 and not rl.events.any(func(e): return e["type"] == "order_cut"),
					"%s: the rest of the order keeps coming and pours off the lip (%.0f -> %.0f)" % [what, fell_tick, rl.fall_losses.get("A", 0.0)])
			check(not rl.events.any(func(e): return e["type"] == "carried") and rl.nodes[c[2]]["siege"].is_empty()
					and (kind != "retract" or rl.nodes[c[2]]["units"] <= carried0 + 0.01),
					"%s: nothing is carried into the relay's node" % what)
			# a line straddling the deck when it goes: the front past the far pier made it and walks on as its
			# own line, the part behind pours off the lip, nothing walks over the gap
			var rm := _relay_sim(c[1], c[2], c[3])
			rm.nodes[c[3]]["units"] = 400.0
			var hm: Dictionary = rm.send(c[3], c[4], 1.0)
			var dm: Dictionary = _relay_deck(rm, hm, c[2])
			run_until(rm, func(): return hm["s"] > dm["s1"] + 1.5, 30.0, 0.02)
			rm.fire_relay(c[2])
			rm.nodes[c[2]]["relay_t"] = 0.0
			rm.step(0.02)
			var fronts := rm.hordes.filter(func(x): return x["owner"] == "A" and x["id"] != hm["id"])
			var front_ok: bool = fronts.size() == 1 and not fronts[0]["streaming"] and fronts[0]["s"] - Sim.chain_length(fronts[0]) >= dm["s1"] - 0.05
			check(front_ok and hm in rm.hordes and absf(hm["s"] - dm["s0"]) < Rules.move_speed() * 0.03 and hm["streaming"],
					"%s: a line straddling the deck splits - the front past the far pier walks on, the rest waits at the lip" % what)
			if front_ok:
				var fr: Dictionary = fronts[0]
				run_until(rm, func(): return not (fr in rm.hordes), 15.0, 0.05)
				check(not (fr in rm.hordes), "%s: ...and the front reaches its target" % what)
		# an appearing deck is walkable only once the motion ends (switch s2, remote on, retract out again)
		for c in [["switch", "res://maps/010-first-switch.json", 1], ["remote", "res://maps4/M-08-neon-delta.json", 4],
				["retract", "res://maps4/M-08-neon-delta.json", 7]]:
			var ra := _relay_sim(c[1], c[2], -1)
			if c[0] != "switch":                           # first take the deck away, then bring it back
				ra.fire_relay(c[2])
				run_until(ra, func(): return ra.nodes[c[2]]["relay_phase"] == "" and ra.nodes[c[2]]["relay_cd"] <= 0.0, 20.0, 0.1)
			var opening := []
			for i in ra.controlled_edges(c[2]):
				if not ra.is_edge_open(i) and ra._edge_open_at(i, ra.relay_next_index(ra.nodes[c[2]])):
					opening.append(i)
			ra.fire_relay(c[2])
			run_until(ra, func(): return ra.nodes[c[2]]["relay_phase"] == "moving", 3.0, 0.02)
			var closed_mid: bool = not opening.is_empty()
			for i in opening:
				var e: Dictionary = ra.edges[i]
				closed_mid = closed_mid and not ra.is_edge_open(i) and not (ra.find_route(e["a"], e["b"]) == [e["a"], e["b"]])
			run_until(ra, func(): return ra.nodes[c[2]]["relay_phase"] == "", 3.0, 0.02)
			var open_end: bool = opening.all(func(i): return ra.is_edge_open(i))
			check(closed_mid and open_end, "%s %s: an appearing deck is closed while it moves, walkable once the motion ends (%d decks)" % [mode_r, c[0], opening.size()])
	Rules.bridge_combat = false
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)



func _relay_sim(path: String, relay: int, src: int) -> Sim:
	## 0.18.7 relay tests: a map with A holding the relay (and the source); every other seat stays home.
	var m := MapBuilder.load_map(path)
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = st["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember"}, 1)
	sim.nodes[relay]["owner"] = "A"
	if src >= 0:
		sim.nodes[src]["owner"] = "A"
	return sim


func _relay_deck(sim: Sim, h: Dictionary, relay: int) -> Dictionary:
	## The span of the horde's route on a deck this relay fires.
	for sp in h["spans"]:
		if sp["edge"] in sim.controlled_edges(relay):
			return sp
	return {"s0": INF, "s1": INF, "edge": -1}


func _on_deck(h: Dictionary, sp: Dictionary) -> float:
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	return maxf(0.0, minf(head, sp["s1"]) - maxf(tail, sp["s0"])) / maxf(Sim.chain_length(h), 0.001)
