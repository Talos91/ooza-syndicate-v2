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
var _parts_done := 0                                 # each part counts itself at its end (a script error aborts a part)


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
	_parts_done += 1


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
	_parts_done += 1


func _collapse_all_but(sim: Sim, keep: Array) -> void:
	## Marks every other platform as launched without scoring (a test shortcut; test_quota's).
	for n in sim.nodes:
		if not (n["id"] in keep):
			sim.collapsed[n["id"]] = true


func _qsim(path: String) -> Sim:
	var sim := _sim(path, 3)
	sim.last_stand_active = true                      # scoring only matters once the Last Stand runs
	return sim


func _part_b() -> void:
	# ------------------------------------------------------------ B: quota by tier (port of the demo's tests/test_quota.gd)
	_opts({"quota_tier": true, "gat_own_platform": true, "relay_set": true})
	check(Rules.quota, "quota_tier on: Rules.quota")
	var a := 0
	var b := 4                                        # L11P homes
	var sim := _qsim(L11P)
	check(int(sim.nodes[a]["ring"]) == 0 and int(sim.nodes[b]["ring"]) == 0 and int(sim.nodes[5]["ring"]) == 2 and int(sim.nodes[2]["ring"]) == 1,
			"launch order: the map's quota rings (homes 0 = last, centre 1, outer 2 = first)")
	# 1. a launch pays its owner its tier at liftoff; neutral pays nobody
	sim.nodes[1]["owner"] = "A"
	sim.nodes[1]["units"] = 20.0
	sim._drop_node(1)
	check(sim.quota_of("A") == 1 and sim.quota_of("B") == 0, "T1 launch: A +1 (A %d, B %d)" % [sim.quota_of("A"), sim.quota_of("B")])
	sim.nodes[2]["owner"] = "B"                       # the T2 centre
	sim._drop_node(2)
	check(sim.quota_of("B") == 2, "T2 launch: B +2 (B %d)" % sim.quota_of("B"))
	sim.nodes[3]["owner"] = "A"
	sim.nodes[3]["tier"] = 3
	sim.nodes[3]["structure"] = "laser"               # a tower node scores its node tier
	sim._drop_node(3)
	check(sim.quota_of("A") == 4, "T3 laser node launch: A +3 (A %d)" % sim.quota_of("A"))
	check(sim.events.any(func(e): return e["type"] == "launch" and e["node"] == 2 and e["seat"] == "B" and int(e["points"]) == 2),
			"launch event names the owner and its points")
	check(sim.fx_events.any(func(e): return e["type"] == "collapse" and bool(e.get("launch", false))), "the view gets a launch (not a plain collapse)")
	check(sim.collapsed.get(1, false) and sim.nodes[1]["owner"] == "" and sim.nodes[1]["units"] == 0.0 and float(sim.fall_losses.get("A", 0.0)) >= 20.0,
			"the platform is gone, its garrison splats (counted as fallen)")
	sim._drop_node(6)
	check(sim.quota_of("A") == 4 and sim.quota_of("B") == 2 and str(sim.quota_last_side) == "", "neutral launch pays nobody")
	check(not sim.over, "no end with a 2-point lead and %d points on the board" % sim.quota_points_left())
	check(LabOverlay.rules_line(sim).begins_with("quota A 4 - B 2, %d left" % sim.quota_left()), "overlay: '%s'" % LabOverlay.rules_line(sim))
	check(sim.quota_readout().contains("A 4 · B 2"), "HUD readout: '%s'" % sim.quota_readout())
	# 2. unreachable lead: lead > the points still on the board ends it; lead == points goes on
	sim = _qsim(L11P)
	_collapse_all_but(sim, [a, b, 1, 2])
	var pts := sim.quota_points_left()
	check(sim.quota_left() == 4 and pts == 2 * Rules.HOME_TIER + 1 + 2, "4 platforms left = %d points (homes T%d, T1, T2)" % [pts, Rules.HOME_TIER])
	sim.quota = {"A": pts, "B": 0}
	sim.step(0.05)
	check(not sim.over, "lead %d = %d points left: the match goes on" % [pts, pts])
	sim.quota = {"A": pts + 1, "B": 0}
	sim.step(0.05)
	check(sim.over and sim.winner == "A" and sim.quota_reason == "unreachable", "lead %d > %d points left: A wins on quota (winner '%s', %s)" % [pts + 1, pts, sim.winner, sim.quota_reason])
	# 3. the last platform: a tie goes to its holder (its launch scores); nobody is eliminated while the launches run
	sim = _qsim(L11P)
	_collapse_all_but(sim, [b])
	sim.nodes[a]["owner"] = ""                        # A holds nothing at all now
	var hb := Sim.launch_points(sim.nodes[b])
	sim.quota = {"A": 3 + hb, "B": 3}
	sim.quota_last_side = "A"
	sim.step(0.05)
	check(not sim.over and not sim.eliminated.has("A"), "A holds nothing but keeps its points: not out during the launches")
	sim._drop_node(b)
	check(sim.over and sim.winner == "B" and sim.quota_reason == "final" and sim.quota_of("B") == 3 + hb,
			"%d-%d after the last launch: its holder B wins (winner '%s', %s)" % [3 + hb, sim.quota_of("B"), sim.winner, sim.quota_reason])
	# 4. a neutral last platform on a tie: DRAW
	sim = _qsim(L11P)
	_collapse_all_but(sim, [b])
	sim.nodes[b]["owner"] = ""
	sim.quota = {"A": 2, "B": 2}
	sim._drop_node(b)
	check(sim.over and sim.winner == "" and sim.draw_line != "", "2-2 with a neutral last platform: DRAW (winner '%s')" % sim.winner)
	# 5. the Very Last Stand runs down to the last platform (its gap leaves QUOTA_END_SPARE)
	sim = _qsim(L11P)
	_collapse_all_but(sim, [a, b, 1])
	sim.time = Rules.VERY_LAST_STAND_TIME
	sim.very_last_stand_active = true
	sim._vls_queue_next()
	var want := (Rules.MATCH_HARD_END - Rules.QUOTA_END_SPARE - Rules.VERY_LAST_STAND_TIME) / 3.0
	check(absf(sim.very_last_stand_gap - want) < 0.01, "VLS gap = time to the end minus the spare over 3 survivors (%.2f, want %.2f)" % [sim.very_last_stand_gap, want])
	_collapse_all_but(sim, [b])
	sim._vls_queue_next()
	check(sim.last_stand_warn_node == b, "QUOTA: the last platform is queued to launch too")
	# 6. relays never launch (L09R: 9 platforms, 2 relays)
	var rpath := LabCards.map_path("L09R")
	sim = _sim(rpath, 3)
	check(sim.quota_left() == 9 and not Sim.launchable(sim.nodes[9]) and not Sim.launchable(sim.nodes[10]),
			"L09R: 9 platforms to launch, the 2 relays never (%d)" % sim.quota_left())
	sim.start_last_stand_now()
	check(not sim.last_stand_order.any(func(id): return sim.nodes[id]["node_kind"] == "relay"), "relays are in no launch wave %s" % str(sim.last_stand_waves))
	check(not sim._vls_surviving().has(9) and not sim._vls_surviving().has(10), "relays are not in the Very Last Stand")
	var q0 := sim.quota.duplicate()
	sim.nodes[9]["owner"] = "A"
	sim._drop_node(9)                                 # (should a relay ever be dropped by something else: no points)
	check(sim.quota == q0 and not sim.events.any(func(e): return e["type"] == "launch" and e["node"] == 9), "a dropped relay scores nothing")
	# 7. full AI matches with quota on: they end, every point is an owned launch at its tier, homes launch last, no relay launches
	for path in [L11P, rpath]:
		Rules.lab_opts["quota_tier"] = true
		sim = _sim(path, 11)
		_ai_match(sim, Rules.MATCH_HARD_END + 5.0)
		var launches := sim.events.filter(func(e): return e["type"] == "launch")
		var paid := 0
		for e in launches:
			if str(e["seat"]) != "":
				paid += int(e["points"])
		var total := 0
		for k in sim.quota:
			total += int(sim.quota[k])
		var home_seen := false
		var homes_last := true
		for e in launches:
			var home: bool = int(e["node"]) in sim.homes.values()
			if home_seen and not home:
				homes_last = false
			home_seen = home_seen or home
		var code: String = str(path).get_file().substr(0, 4)
		print("%s AI vs AI quota on: winner '%s' at %.1f s, reason '%s', quota %s, %d launches" % [code, sim.winner, sim.time, sim.quota_reason, sim.quota, launches.size()])
		check(sim.over, "%s: the quota match ends" % code)
		check(total == paid, "%s: every quota point is an owned launch at its tier (%d = %d)" % [code, total, paid])
		check(launches.all(func(e): return int(e["points"]) == Sim.launch_points(sim.nodes[int(e["node"])])), "%s: each launch paid its node tier" % code)
		check(homes_last, "%s: the homes launch last" % code)
		check(not launches.any(func(e): return sim.nodes[int(e["node"])]["node_kind"] == "relay"), "%s: no relay launched" % code)
	# 8. quota OFF: a drop scores nothing, no launch; the plain lab maps keep no Last Stand
	_opts({})
	check(not Rules.quota, "quota_tier off: Rules.quota off")
	sim = _qsim(L11P)
	check(int(sim.nodes[5]["ring"]) == 1 and int(sim.nodes[a]["ring"]) == 1, "quota off: the map's own rings")
	sim.nodes[1]["owner"] = "A"
	sim._drop_node(1)
	check(sim.quota.is_empty() and not sim.fx_events.any(func(e): return bool(e.get("launch", false))), "quota OFF: no score, no launch")
	_collapse_all_but(sim, [b])
	sim.time = Rules.VERY_LAST_STAND_TIME
	sim.very_last_stand_active = true
	sim._vls_queue_next()
	check(sim.last_stand_warn_node == -1, "quota OFF: the last platform never drops (unchanged)")
	_parts_done += 1


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
	_parts_done += 1


func _init() -> void:
	check(Rules.lab, "a lab build (VERSION %s)" % Rules.VERSION)
	_part_a()
	_part_c()
	_part_b()
	_identity()
	check(_parts_done == 4, "every part ran to its end (A, C, B, identity: %d of 4)" % _parts_done)
	_opts({"gat_own_platform": true, "relay_set": true})
	print("test_lab_rules: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
