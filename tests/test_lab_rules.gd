extends SceneTree
## LAB rule options (WP4, 05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md): headless checks of
##   A  gat_own_platform - the Googatling fires only over its own platform (Daniele 2026-11-23: "covers only its node area not
##      beyond (or we have spawn kill)"), and the card's gat_start (a T1 Googatling next to each home);
##   C  relay_set - map L09R (a retract and a rotation relay on the long centre decks, a neutral Googatling T3 at the centre),
##      no archived relay kind (lift / tilt / remote / laser_relay) on any lab map;
##   B  quota_tier - quota by tier (a launch scores its node tier), relays never launch, the match ends by quota;
##   and the options-off identity (L11P AI vs AI equals the run recorded on the untouched lab tip 232c7787).
##   Godot --headless --path . --script res://tests/test_lab_rules.gd        Exit code 0 = all passed.

const LabOverlay := preload("res://scripts/lab_overlay.gd")
const LabCards := preload("res://scripts/lab_cards.gd")
const L09C := "res://maps4/L09C-clusters-9.json"
const L11P := "res://maps4/L11P-grid-11.json"
# L11P, AI vs AI, seed 5 (A Standard null / B Veteran ember), all three WP4 options off: recorded on the untouched lab tip
# 232c7787 before WP4 (hash = the chained hash of every event's text)
const L11P_BEFORE := {"winner": "B", "time": 185.3, "events": 163, "hash": 1116204576}
const OPTS := ["gat_own_platform", "gat_start", "quota_tier", "relay_set"]

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _opts(on: Dictionary) -> void:
	for k in OPTS:
		Rules.lab_opts[k] = bool(on.get(k, false))
	Rules.lab_opts["joints"] = bool(on.get("joints", true))


func _sim(path: String, seed_value := 5) -> Sim:
	var m := MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember"}, seed_value)
	return sim


func _ai_match(sim: Sim, limit_s := 900.0) -> void:
	var sa := SeatAI.new("A", 2.0, "Standard")
	var sb := SeatAI.new("B", 2.3, "Veteran")
	var n := 0
	while not sim.over and n < int(limit_s * 10.0):
		sa.think(sim, 0.1)
		sb.think(sim, 0.1)
		sim.step(0.1)
		n += 1


func _events_hash(sim: Sim) -> int:
	var h := 0
	for e in sim.events:
		h = hash([h, str(e)])
	return h


func _line_at(sim: Sim, seat: String, route: Array, target: int, head_d: float) -> Dictionary:
	## A small enemy line walking `route` whose head is `head_d` m from node `target`'s centre (searched along its path).
	var h := sim._new_horde(seat, 2.0, route)
	h["units"] = 2.0
	h["ordered"] = 2.0
	h["streaming"] = false
	h["speed"] = 0.0                                  # it stands where it is put (the relay checks step the sim)
	var total: float = (h["cum"] as Array)[-1] if h.has("cum") else 100.0
	var c: Vector3 = sim.nodes[target]["pos"]
	var best_s := 0.0
	var best_err := INF
	var s := 0.0
	while s <= total:
		var err := absf(c.distance_to(Sim.sample(h, s)[0]) - head_d)
		if err < best_err:
			best_err = err
			best_s = s
		s += 0.05
	h["s"] = best_s
	sim.hordes.append(h)
	return h


func _shot(sim: Sim, gat: int, h: Dictionary) -> bool:
	## Fire the Googatling once (0.1 s) at a board holding only `h`: did it hit it?
	sim._bodies = {}
	var before: float = h["units"]
	sim._fire_machinegoon(sim.nodes[gat], 0.1)
	return float(h["units"]) < before - 0.0001


func _part_a() -> void:
	# ------------------------------------------------------------ A: card start + own platform only
	_opts({"gat_own_platform": true, "gat_start": true})
	check(is_equal_approx(Sim.gat_reach(), Rules.R), "own platform: reach = platform radius %.1f m (got %.2f)" % [Rules.R, Sim.gat_reach()])
	var sim := _sim(L09C)
	var gats := sim.nodes.filter(func(n): return n["structure"] == "machinegoon")
	check(gats.size() == 2, "gat_start: two Googatlings at the start on L09C (got %d)" % gats.size())
	var by_seat := {}
	for n in gats:
		by_seat[n["owner"]] = n["id"]
	check(by_seat.get("A", -1) == 1 and by_seat.get("B", -1) == 7, "gat_start: A on node 1, B on node 7 (mirror; got %s)" % str(by_seat))
	var ga: int = by_seat.get("A", 1)
	check(int(sim.nodes[ga]["tier"]) == 1 and float(sim.nodes[ga]["units"]) >= Sim.gat_cap(sim.nodes[ga]) - 0.01,
			"gat_start: T1, full ammo (%.0f)" % float(sim.nodes[ga]["units"]))
	# B lines: on the joint neighbour's platform (node 2, 7 m from the gun), on the deck 1-3 (8 m), on the gun's own platform (3 m)
	for opt in [true, false]:
		Rules.lab_opts["gat_own_platform"] = opt
		var cases := [["neighbour platform (joint 2-1), 7 m", [2, 1], 7.0, not opt],
				["deck 3-1, 8 m", [3, 1], 8.0, not opt],
				["own platform, 3 m", [2, 1], 3.0, true]]
		for cs in cases:
			sim.hordes.clear()
			var h := _line_at(sim, "B", cs[1], ga, cs[2])
			var hd: float = (sim.nodes[ga]["pos"] as Vector3).distance_to(Sim.sample(h, h["s"])[0])
			var hit := _shot(sim, ga, h)
			check(hit == cs[3], "own_platform=%s: line on %s (head %.1f m) %s" % [opt, cs[0], hd, "hit" if cs[3] else "not hit"])
	sim.hordes.clear()
	Rules.lab_opts["gat_own_platform"] = true
	check(LabOverlay.rules_line(sim).contains("gat: own platform"), "overlay: '%s'" % LabOverlay.rules_line(sim))
	_opts({})
	check(LabOverlay.rules_line(_sim(L09C)) == "", "overlay: no rule line with the options off")
	check(is_equal_approx(Sim.gat_reach(), Rules.MACHINEGOON_RANGE), "option off: reach back to MACHINEGOON_RANGE")


func _relay_kill(sim: Sim, relay: int, route: Array, what: String) -> void:
	## A owns `relay`; a B line stands mid-deck on `route` (11 m from the relay centre); A fires: the line falls.
	sim.hordes.clear()
	sim.nodes[relay]["owner"] = "A"
	var h := _line_at(sim, "B", route, relay, 11.0)
	var before: float = sim.fall_losses.get("B", 0.0)
	check(sim.fire_relay(relay), "%s: A fires its relay %d" % [what, relay])
	for i in range(int((Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.5) / 0.1)):
		sim.step(0.1)
	var fell: float = sim.fall_losses.get("B", 0.0) - before
	check(fell > 0.0 and (not (h in sim.hordes) or float(h["units"]) < 2.0 - 0.0001),
			"%s: the B line on the deck falls (%.2f units fell)" % [what, fell])


func _part_c() -> void:
	# ------------------------------------------------------------ C: relay set, map L09R
	_opts({"relay_set": true, "gat_own_platform": true})
	var path := LabCards.map_path("L09R")
	check(path != "" and path in MapPool.battlefield(), "L09R baked and offered (%s)" % path)
	var sim := _sim(path)
	var plats := sim.nodes.filter(func(n): return n["node_kind"] != "relay")
	check(plats.size() == 9, "L09R: 9 platforms + %d relay nodes (got %d platforms)" % [sim.nodes.size() - plats.size(), plats.size()])
	var c: Dictionary = sim.nodes[2]
	check(c["structure"] == "machinegoon" and int(c["tier"]) == 3 and c["owner"] == "",
			"L09R centre: a neutral Googatling T3 (%s T%d owner '%s')" % [c["structure"], int(c["tier"]), c["owner"]])
	check(sim.nodes[9]["relay"] == "retract" and sim.nodes[10]["relay"] == "switch", "L09R relays: 9 retract, 10 switch")
	var long_relay := 0
	for ei in sim.edge_controller:
		var g: Dictionary = sim.edges[ei]["geo"]
		if float(g.get("L", 0.0)) - float(g.get("p0", 0.0)) - float(g.get("p1", 0.0)) >= 8.0:
			long_relay += 1
	check(long_relay == 4, "L09R: both lanes cross on long relay decks >= 8 m (4 decks, got %d)" % long_relay)
	_relay_kill(sim, 9, [6, 9], "RETRACT")
	_relay_kill(sim, 10, [8, 10], "SWITCH")
	# no archived relay kind on any lab map; the guard turns one into a plain node
	var bad := []
	for p in MapPool.all():
		if not p.get_file().substr(0, 4) in MapPool.LAB:
			continue
		var m := MapBuilder.load_map(p)
		for n in m["nodes"]:
			if str(n.get("relay")) in Rules.LAB_RELAY_ARCHIVED:
				bad.append("%s node %d %s" % [p.get_file(), n["id"], n["relay"]])
		for e in m["edges"]:
			if str(e.get("proto")) in Rules.LAB_RELAY_ARCHIVED:
				bad.append("%s deck %d-%d %s" % [p.get_file(), e["from"], e["to"], e["proto"]])
	check(bad.is_empty(), "no lab map uses lift / tilt / remote / laser_relay %s" % str(bad))
	var m2 := MapBuilder.load_map(path)
	m2["nodes"][9]["relay"] = "laser_relay"
	var seats := {0: "A", 4: "B"}
	var s2 := Sim.new()
	s2.setup(m2, MapBuilder.layout(m2), seats, {"A": "null", "B": "ember"}, 5)
	check(s2.nodes[9]["relay"] == "", "relay_set guard: an archived kind plays as a plain node")
	var s3 := _sim(path)
	_ai_match(s3)
	print("L09R AI vs AI (relay_set on): winner %s at %.1f s, %d events, relay fires %d, falls %d" % [s3.winner, s3.time, s3.events.size(),
			s3.events.filter(func(e): return e["type"] == "relay_fired").size(), s3.events.filter(func(e): return e["type"] == "fall").size()])
	check(s3.over, "L09R: an AI vs AI match ends")


func _identity() -> void:
	# ------------------------------------------------------------ options off: L11P unchanged
	_opts({})
	var sim := _sim(L11P)
	_ai_match(sim)
	var got := {"winner": sim.winner, "time": snappedf(sim.time, 0.1), "events": sim.events.size(), "hash": _events_hash(sim)}
	print("L11P options off: %s" % str(got))
	check(got["winner"] == L11P_BEFORE["winner"] and is_equal_approx(got["time"], L11P_BEFORE["time"]) \
			and got["events"] == L11P_BEFORE["events"] and got["hash"] == L11P_BEFORE["hash"],
			"options off: L11P AI vs AI identical to the pre-WP4 run %s" % str(L11P_BEFORE))


func _init() -> void:
	check(Rules.lab, "a lab build (VERSION %s)" % Rules.VERSION)
	_part_a()
	_part_c()
	_identity()
	_opts({"gat_own_platform": true, "relay_set": true})
	print("test_lab_rules: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
