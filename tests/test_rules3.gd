extends SceneTree
## OOZE 3.0 RULES (WP1, plan 05 Handoff/handoffs/3.0-ARCHITECTURE-PLAN 2026-11-27.md sec 2.2; Daniele's Desk answers 2026-11-27).
## Was tests/test_lab_rules.gd (the lab4 rule options); the lab options are the game now, read from Rules static vars, and the
## lab cards / overlay / count-size UI checks went with the lab UI (WP4 / WP6 own those files). Headless checks of
##   A  the Googatling: reach = its own platform (Rules.GAT_REACH = R 7.6), never a neighbour platform or a deck;
##   C  the relay set - map L09R (one retract between the homes; the way round passes a neutral Googatling T3), no archived kind;
##   B  the quota is the Last Stand - a launch scores its node tier, relays never launch, the match ends by quota (and the
##      legacy ring collapse still runs with Rules.quota = false);
##   D  unit speed x0.75 (travel speed and door rate), Googatling reach / power / ammo (1 unit per 3 kills);
##   F  3.0 node categories (normal / SPECIAL T4 / relay laser-or-juicer / relay special), vats produce while upgrading, the
##      sinkhole rebuild (player and AI), no INWARD / OUTWARD Last Stand state, edge_kind, 3.0 rule values;
##   and determinism (L11P AI vs AI twice = the same events).
##   Godot --headless --path . --script res://tests/test_rules3.gd        Exit code 0 = all passed.

const L09C := "res://maps4/L09C-clusters-9.json"
const L09R := "res://maps4/L09R-relay-9.json"
const L11P := "res://maps4/L11P-grid-11.json"

var failures := 0
var _parts_done := 0                                 # each part counts itself at its end (a script error aborts a part)


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _rules3() -> void:
	## The 3.0 defaults (what rules.gd ships).
	Rules.quota = true
	Rules.JOINTS = true
	Rules.RELAY_SET = true
	Rules.GAT_REACH = Rules.R
	Rules.GAT_POWER = 1.0
	Rules.GAT_AMMO = 1.0 / 3.0
	Rules.UNIT_SPEED = 0.75
	Rules.VAT_UPGRADE_PAUSES = false


func _opts(on: Dictionary) -> void:
	## The old lab option names, mapped onto the 3.0 rule vars (unnamed = the 0.25 game). joints default on.
	Rules.GAT_REACH = Rules.R if bool(on.get("gat_own_platform", false)) else Rules.MACHINEGOON_RANGE
	Rules.quota = bool(on.get("quota_tier", false))
	Rules.RELAY_SET = bool(on.get("relay_set", false))
	Rules.JOINTS = bool(on.get("joints", true))


func _sim(path: String, seed_value := 5, loadouts := {}) -> Sim:
	var m := MapBuilder.load_map(path)
	return _sim_m(m, seed_value, loadouts)


func _sim_m(m: Dictionary, seed_value := 5, loadouts := {}) -> Sim:
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember"}, seed_value, loadouts)
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


func _gun(sim: Sim, id: int, seat := "A", tier := 1) -> void:
	var n: Dictionary = sim.nodes[id]
	n["owner"] = seat
	n["structure"] = "machinegoon"
	n["tier"] = tier
	n["units"] = Sim.gat_cap(n)


func _part_a() -> void:
	# ------------------------------------------------------------ A: the Googatling covers its own platform only (3.0 default)
	# (L09C is baked at R 6: its joint platforms overlap at R 7.6 until WP2 rebakes, so distances are taken from Rules.R)
	_rules3()
	check(is_equal_approx(Sim.gat_reach(), Rules.R) and is_equal_approx(Rules.R, 7.6), "3.0: reach = own platform radius %.1f m (got %.2f)" % [Rules.R, Sim.gat_reach()])
	var sim := _sim(L09C)
	var ga := 1
	_gun(sim, ga)
	for cs in [["neighbour platform (joint 2-1), R + 1 m", [2, 1], Rules.R + 1.0, false],
			["deck 3-1, R + 1.5 m", [3, 1], Rules.R + 1.5, false],
			["own platform, 3 m", [2, 1], 3.0, true],
			["own platform, R - 0.5 m", [3, 1], Rules.R - 0.5, true]]:
		sim.hordes.clear()
		var h := _line_at(sim, "B", cs[1], ga, cs[2])
		var hd: float = (sim.nodes[ga]["pos"] as Vector3).distance_to(Sim.sample(h, h["s"])[0])
		var hit := _shot(sim, ga, h)
		check(hit == cs[3], "3.0 Googatling: line on %s (head %.1f m) %s" % [cs[0], hd, "hit" if cs[3] else "not hit"])
	sim.hordes.clear()
	_opts({})
	check(is_equal_approx(Sim.gat_reach(), Rules.MACHINEGOON_RANGE), "legacy (GAT_REACH = MACHINEGOON_RANGE): reach 10 m")
	_rules3()
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
	var path := L09R                                  # (which maps the pickers offer is WP2's: MapPool)
	var sim := _sim(path)
	var plats := sim.nodes.filter(func(n): return n["node_kind"] != "relay")
	check(plats.size() == 9, "L09R: 9 platforms + %d relay nodes (got %d platforms)" % [sim.nodes.size() - plats.size(), plats.size()])
	var c: Dictionary = sim.nodes[2]
	check(c["structure"] == "machinegoon" and int(c["tier"]) == 3 and c["owner"] == "",
			"L09R centre: a neutral Googatling T3 (%s T%d owner '%s')" % [c["structure"], int(c["tier"]), c["owner"]])
	check(sim.nodes[9]["relay"] == "retract" and sim.nodes.filter(func(n): return n["node_kind"] == "relay").size() == 1,
			"L09R: one relay, node 9, a retract")
	var ret := []
	for ei in sim.edge_controller:
		var g: Dictionary = sim.edges[ei]["geo"]
		if sim.edges[ei]["retracts"] and float(g.get("L", 0.0)) - float(g.get("p0", 0.0)) - float(g.get("p1", 0.0)) >= 6.0:
			ret.append(ei)
	check(ret.size() == 2, "L09R: the relay retracts two decks >= 6 m, one to each home (got %d)" % ret.size())
	# lab4 job 4 (Daniele on lab3: "all bridges are super easily avoidable"): home - relay - home is the only short way across;
	# with the relay decks left out the way round (over the Googatling) is at least twice as long, walked and by route time.
	var hA: int = sim.homes["A"]
	var hB: int = sim.homes["B"]
	var avoid := {}
	for ei in ret:
		avoid[ei] = true
	var r1 := sim.find_route(hA, hB)
	var r2 := sim.find_route(hA, hB, avoid)
	var len1: float = sim.build_path(r1)["cum"][-1]
	var len2: float = sim.build_path(r2)["cum"][-1]
	print("L09R home to home: over the relay %s %.1f m (%.1f s), the way round %s %.1f m (%.1f s), x%.2f" % [str(r1), len1,
			len1 / Rules.move_speed(), str(r2), len2, len2 / Rules.move_speed(), len2 / len1])
	check(9 in r1 and not (9 in r2) and 2 in r2, "L09R: the short route crosses the relay, the way round passes the Googatling")
	check(len2 >= 2.0 * len1, "L09R: the way round is at least twice the relay route (%.1f vs %.1f m)" % [len2, len1])
	_relay_kill(sim, 9, [hB, 9], "RETRACT")
	# no archived relay kind on any lab map; the guard turns one into a plain node
	var bad := []
	for p in MapPool.all():
		if not p.get_file().substr(0, 4) in ["L09P", "L11P", "L13P", "L09C", "L11C", "L13C", "L09R"]:   # the old lab maps (MapPool.LAB went in WP6)
			continue
		var m := MapBuilder.load_map(p)
		for n in m["nodes"]:
			if str(n.get("relay")) in Rules.RELAY_ARCHIVED:
				bad.append("%s node %d %s" % [p.get_file(), n["id"], n["relay"]])
		for e in m["edges"]:
			if str(e.get("proto")) in Rules.RELAY_ARCHIVED:
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
	check(Rules.quota, "quota on: Rules.quota")
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
	# 6. relays never launch (L09R: 9 platforms, 1 relay)
	var rpath := L09R
	sim = _sim(rpath, 3)
	check(sim.quota_left() == 9 and not Sim.launchable(sim.nodes[9]), "L09R: 9 platforms to launch, the relay never (%d)" % sim.quota_left())
	sim.start_last_stand_now()
	check(not sim.last_stand_order.any(func(id): return sim.nodes[id]["node_kind"] == "relay"), "relays are in no launch wave %s" % str(sim.last_stand_waves))
	check(not sim._vls_surviving().has(9), "the relay is not in the Very Last Stand")
	var q0 := sim.quota.duplicate()
	sim.nodes[9]["owner"] = "A"
	sim._drop_node(9)                                 # (should a relay ever be dropped by something else: no points)
	check(sim.quota == q0 and not sim.events.any(func(e): return e["type"] == "launch" and e["node"] == 9), "a dropped relay scores nothing")
	# 7. full AI matches with quota on: they end, every point is an owned launch at its tier, homes launch last, no relay launches
	for path in [L11P, rpath]:
		_rules3()                                     # the 3.0 game: quota, unit speed x0.75, Googatling 1 per 3 kills
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
	check(not Rules.quota, "legacy Rules.quota = false: the ring collapse")
	sim = _qsim(L11P)
	# (lab4 job 4: the check reads the rings from the map file. lab3 hard-coded home ring 1; lab4 job 1 built L11P into the zoom
	# box, its homes moved inside the 18 m ellipse and the generator now gives them ring 0 - the same as their quota ring, so
	# node 5 (own ring 1, quota ring 2) is what tells the two apart.)
	var own := MapBuilder.load_map(L11P)
	var own_ok := true
	for n in own["nodes"]:
		own_ok = own_ok and int(sim.nodes[int(n["id"])]["ring"]) == int(n["ring"])
	check(own_ok and int(sim.nodes[5]["ring"]) == 1, "quota off: the map's own rings (node 5 ring %d, not its quota ring 2)" % int(sim.nodes[5]["ring"]))
	sim.nodes[1]["owner"] = "A"
	sim._drop_node(1)
	check(sim.quota.is_empty() and not sim.fx_events.any(func(e): return bool(e.get("launch", false))), "quota OFF: no score, no launch")
	_collapse_all_but(sim, [b])
	sim.time = Rules.VERY_LAST_STAND_TIME
	sim.very_last_stand_active = true
	sim._vls_queue_next()
	check(sim.last_stand_warn_node == -1, "quota OFF: the last platform never drops (unchanged)")
	_parts_done += 1


func _walked(speed: float, dt_total := 0.5) -> float:
	## Metres a B line walks along deck 3-1 of L09C in dt_total s at Rules.UNIT_SPEED = speed.
	Rules.UNIT_SPEED = speed
	var sim := _sim(L09C)
	var h := sim._new_horde("B", 2.0, [3, 1])
	h["units"] = 2.0
	h["ordered"] = 2.0
	h["streaming"] = false
	h["s"] = 1.0
	sim.hordes.append(h)
	var s0: float = h["s"]
	var n := 0
	while n < int(round(dt_total / 0.05)):
		sim.step(0.05)
		n += 1
	return float(h["s"]) - s0


func _part_d() -> void:
	# ------------------------------------------------------------ D: unit speed, Googatling reach / power / ammo
	_rules3()
	check(Rules.UNIT_SPEED == 0.75 and is_equal_approx(Rules.move_speed(), Rules.BRAWL_SPEED * 0.75)
			and is_equal_approx(Rules.exit_rate(), Rules.BRAWL_DOOR_RATE * 0.75),
			"3.0 unit speed x0.75 (Daniele 11-27): move %.3f m/s, door %.2f units/s" % [Rules.move_speed(), Rules.exit_rate()])
	var base := _walked(1.0)
	for sp in [0.75, 0.9]:
		var d := _walked(sp)
		check(absf(d / base - sp) < 0.005, "UNIT_SPEED x%.2f: walks %.3f m vs %.3f m in 0.5 s (ratio %.4f)" % [sp, d, base, d / base])
		check(is_equal_approx(Rules.metres_per_unit(), Rules.BRAWL_SPEED / Rules.BRAWL_DOOR_RATE),
				"UNIT_SPEED x%.2f: spacing unchanged" % sp)
	Rules.UNIT_SPEED = 1.0
	var hop1: Vector2 = _sim(L09C).joint_hops()
	Rules.UNIT_SPEED = 0.75
	var hop75: Vector2 = _sim(L09C).joint_hops()
	check(absf(hop75.x * 0.75 - hop1.x) < 0.01, "UNIT_SPEED x0.75: cluster hop %.2f s -> %.2f s" % [hop1.x, hop75.x])
	# reach: 5 / 8 / 10 m from the node centre
	var sim := _sim(L09C)
	var ga := 1
	_gun(sim, ga)
	for cs in [[5.0, [[2, 1], 4.0, true], [[2, 1], 7.0, false], [[3, 1], 9.0, false]],
			[8.0, [[2, 1], 4.0, true], [[2, 1], 7.0, true], [[3, 1], 9.0, false]],
			[10.0, [[2, 1], 4.0, true], [[2, 1], 7.0, true], [[3, 1], 9.0, true]]]:
		Rules.GAT_REACH = cs[0]
		check(is_equal_approx(Sim.gat_reach(), cs[0]), "GAT_REACH %.0f: reach %.1f m" % [cs[0], Sim.gat_reach()])
		for k in [1, 2, 3]:
			var c: Array = cs[k]
			sim.hordes.clear()
			sim.nodes[ga]["units"] = Sim.gat_cap(sim.nodes[ga])
			var h := _line_at(sim, "B", c[0], ga, c[1])
			var hd: float = (sim.nodes[ga]["pos"] as Vector3).distance_to(Sim.sample(h, h["s"])[0])
			check(_shot(sim, ga, h) == c[2], "GAT_REACH %.0f: line head %.1f m %s" % [cs[0], hd, "hit" if c[2] else "not hit"])
	Rules.GAT_REACH = Rules.R
	# power and ammo: one 0.1 s shot at a big line on the gun's own platform
	var shots := {}
	for pw in [1.0, 1.5]:
		for am in [1.0, 1.0 / 3.0, 0.0]:
			Rules.GAT_POWER = pw
			Rules.GAT_AMMO = am
			sim.hordes.clear()
			sim.nodes[ga]["units"] = Sim.gat_cap(sim.nodes[ga])
			var g0: float = sim.nodes[ga]["units"]
			var h := _line_at(sim, "B", [2, 1], ga, 3.0)
			h["units"] = 100.0
			var u0: float = h["units"]
			_shot(sim, ga, h)
			shots["%s/%s" % [pw, snappedf(am, 0.01)]] = [u0 - float(h["units"]), g0 - float(sim.nodes[ga]["units"])]
	var k1: float = shots["1.0/1.0"][0]
	check(is_equal_approx(k1, 8.0 * 0.1) and is_equal_approx(shots["1.0/1.0"][1], k1),
			"x1 / 1 per kill: T1 kills %.2f in 0.1 s (MACHINEGOON_RATE 8/s), spends %.2f" % [k1, shots["1.0/1.0"][1]])
	check(is_equal_approx(shots["1.5/1.0"][0], k1 * 1.5), "GAT_POWER x1.5: kills %.2f in 0.1 s" % shots["1.5/1.0"][0])
	var r3: Array = shots["1.0/0.33"]
	check(is_equal_approx(r3[0], k1) and absf(r3[1] - r3[0] / 3.0) < 0.0001,
			"3.0 ammo (Daniele 11-27 '1 unit per 3 kills'): kills %.2f, spends %.3f own units" % [r3[0], r3[1]])
	var r0: Array = shots["1.0/0.0"]
	check(is_equal_approx(r0[1], 0.0), "GAT_AMMO 0: free (spends %.2f)" % r0[1])
	for am in [1.0 / 3.0, 0.0]:
		Rules.GAT_POWER = 1.0
		Rules.GAT_AMMO = am
		sim.hordes.clear()
		sim.nodes[ga]["units"] = 0.0
		var h := _line_at(sim, "B", [2, 1], ga, 3.0)
		check(_shot(sim, ga, h) == (am == 0.0), "GAT_AMMO %.2f, empty garrison: %s" % [am, "fires" if am == 0.0 else "silent"])
	_rules3()
	_parts_done += 1


func _determinism() -> void:
	# ------------------------------------------------------------ L11P AI vs AI twice under the 3.0 rules: the same match
	# (replaces lab4's options-off golden replay: the 3.0 sizes and rules changed every event, a fixed hash would only freeze them)
	_rules3()
	var got := []
	for k in range(2):
		var sim := _sim(L11P)
		_ai_match(sim, Rules.MATCH_HARD_END + 5.0)
		got.append({"winner": sim.winner, "time": snappedf(sim.time, 0.1), "events": sim.events.size(), "hash": _events_hash(sim),
				"reason": sim.quota_reason})
	print("L11P 3.0 AI vs AI: %s" % str(got[0]))
	check(got[0] == got[1], "L11P AI vs AI twice: identical (%s)" % str(got[1]))
	_parts_done += 1


func _ctl_node(sim: Sim) -> int:
	## A plain node given to B as a T2 vat (a Sinkhole may hit it).
	var n: Dictionary = sim.nodes[3]
	n["owner"] = "B"
	n["structure"] = "vat"
	n["tier"] = 2
	return 3


func _special_map() -> Dictionary:
	## L09C with its centre (node 4) a map-placed neutral T4: setup makes it a SPECIAL node.
	var m := MapBuilder.load_map(L09C)
	for n in m["nodes"]:
		if int(n["id"]) == 4:
			n["neutral"] = {"tier": 4}
	return m


func _part_f() -> void:
	# ------------------------------------------------------------ F: 3.0 node categories, upgrades, sinkhole rebuild, Last Stand
	_rules3()
	# the 3.0 rule values (the lab option shim went in WP6)
	check(Rules.quota and Rules.JOINTS and Rules.RELAY_SET and is_equal_approx(Rules.GAT_AMMO, 1.0 / 3.0)
			and is_equal_approx(Rules.UNIT_SPEED, 0.75) and is_equal_approx(Rules.GAT_REACH, Rules.R),
			"3.0 rules: quota, joints, relay set, Googatling ammo 1/3, unit speed x0.75, reach = own platform")
	# SPECIAL: always a T4 vat, indestructible, irreplaceable
	var sl := {"A": {"active": "sinkhole"}, "B": {"active": "sinkhole"}}
	var sim := _sim_m(_special_map(), 5, sl)
	var sp: Dictionary = sim.nodes[4]
	check(Sim.node_category(sp) == "special" and int(sp["tier"]) == 4 and sp["structure"] == "vat" and sp["buildable"] == ["vat"],
			"SPECIAL: a map T4 is its own category, a T4 vat, builds only its vat (%s T%d %s)" % [Sim.node_category(sp), int(sp["tier"]), str(sp["buildable"])])
	# the HOTSPOT (Daniele 11-27: "start with huge neutral garrison but once conquered offer the most production in the game")
	check(sp["owner"] == "" and float(sp["units"]) == float(Rules.SPECIAL_GARRISON)
			and Rules.SPECIAL_GARRISON > int(Rules.NEUTRAL_UNITS[3]),
			"HOTSPOT: starts NEUTRAL with the biggest garrison (%d shown; a neutral T3 %d)" % [Rules.shown(sp["units"]), Rules.shown(Rules.NEUTRAL_UNITS[3])])
	var g0: float = sp["units"]
	for i in range(40):
		sim.step(0.05)
	check(sp["owner"] == "" and is_equal_approx(float(sp["units"]), g0) and sim.production(sp) == 0.0,
			"HOTSPOT: a neutral one holds its garrison (%.0f -> %.0f in 2 s, makes nothing)" % [g0, float(sp["units"])])
	check(not sim.homes.values().has(4) and _sim_m(_special_map()).nodes.all(func(n): return not (Sim.is_special(n) and n["owner"] != "")),
			"HOTSPOT: never a home node (no seat starts on a SPECIAL)")
	sim._land_classic(sp, "B", g0 + 50.0)
	check(sp["owner"] == "B" and int(sp["tier"]) == 4 and float(sp["units"]) > 0.0, "HOTSPOT: a bigger line conquers it (owner %s, T%d)" % [sp["owner"], int(sp["tier"])])
	var best := 0.0
	for t in [1, 2, 3]:
		best = maxf(best, float(Rules.PROD[t]))
	var pr_sp: float = sim.production(sp)
	var cmp: Dictionary = sim.nodes[sim.homes["B"]]
	cmp["tier"] = 3
	var pr_t3: float = sim.production(cmp)
	check(pr_sp > pr_t3 and Rules.SPECIAL_PROD > best and is_equal_approx(sim._base_production(sp), Rules.SPECIAL_PROD * sim.stat("B", "production")),
			"HOTSPOT: conquered, it makes the most in the game (%.2f shown/s vs a T3 vat %.2f; SPECIAL_PROD %.3f)" % [Rules.shown_f(pr_sp), Rules.shown_f(pr_t3), Rules.SPECIAL_PROD])
	check(is_equal_approx(sim.node_cap(sp), float(Rules.SPECIAL_CAP)), "HOTSPOT: its cap is SPECIAL_CAP (%d shown)" % Rules.shown(Rules.SPECIAL_CAP))
	sp["owner"] = "B"
	sp["units"] = 500.0
	check(sim.can_build(4, "B", "machinegoon") != "", "SPECIAL: irreplaceable - no Googatling (%s)" % sim.can_build(4, "B", "machinegoon"))
	check(sim.can_build(4, "B", "laser") != "" and sim.can_build(4, "B", "forge") != "", "SPECIAL: no relay structure either")
	check(sim.can_upgrade(4, "B") != "", "SPECIAL: no tier above T4 (%s)" % sim.can_upgrade(4, "B"))
	sim.skill_cd["A"]["active"] = 0.0                 # (ready: the refusal must be the node's, not the cooldown's)
	var ctl := _ctl_node(sim)
	check(sim.cast_check("A", "active", ctl) == "", "Sinkhole is castable on a plain enemy T2 vat (%s)" % sim.cast_check("A", "active", ctl))
	check(sim.cast_check("A", "active", 4).contains("holds its ground"), "SPECIAL: a Sinkhole is refused (%s)" % sim.cast_check("A", "active", 4))
	sim._sinkhole("A", sp)
	check(int(sp["tier"]) == 4 and sp["structure"] == "vat", "SPECIAL: indestructible even when a Sinkhole lands (T%d %s)" % [int(sp["tier"]), sp["structure"]])
	sim._land_classic(sp, "A", 600.0)
	check(sp["owner"] == "A" and int(sp["tier"]) == 4 and sp["structure"] == "vat" and Sim.node_category(sp) == "special",
			"SPECIAL: captured, it stays a T4 vat of its category (owner %s T%d %s)" % [sp["owner"], int(sp["tier"]), sp["structure"]])
	check(sim.can_build(4, "A", "machinegoon") != "", "SPECIAL: the capturer cannot turn it into another structure")
	# NORMAL: a vat or a Googatling, T1-T3, never T4
	var nn: Dictionary = sim.nodes[3]
	nn["owner"] = "A"
	nn["units"] = 900.0
	nn["tier"] = 3
	nn["structure"] = "vat"
	check(Sim.node_category(nn) == "normal" and nn["buildable"] == ["vat", "machinegoon"], "NORMAL: vat or Googatling (%s)" % str(nn["buildable"]))
	check(sim.can_upgrade(3, "A") != "" and not sim.upgrade(3, "A") and int(nn["tier"]) == 3,
			"NORMAL: a T3 vat cannot go to T4 (%s)" % sim.can_upgrade(3, "A"))
	nn["structure"] = "machinegoon"
	check(sim.can_upgrade(3, "A") != "", "NORMAL: a T3 Googatling cannot go to T4 either")
	nn["structure"] = "vat"
	# vats produce while upgrading (Daniele 11-27)
	nn["tier"] = 1
	nn["units"] = float(sim.upgrade_cost(nn)) + 20.0      # (well under the T1 cap, so production shows)
	check(sim.upgrade(3, "A") and nn["build_kind"] == "vat" and not Sim.vat_paused(nn), "a vat upgrade starts; the vat is not paused")
	var u0: float = nn["units"]
	for i in range(20):
		sim.step(0.05)
	check(float(nn["units"]) > u0 + 0.01 and nn["build_kind"] == "vat",
			"a vat under upgrade gains units (%.2f -> %.2f in 1 s, still upgrading)" % [u0, float(nn["units"])])
	Rules.VAT_UPGRADE_PAUSES = true
	var u1: float = nn["units"]
	for i in range(20):
		sim.step(0.05)
	check(absf(float(nn["units"]) - u1) < 0.001, "legacy VAT_UPGRADE_PAUSES = true: paused (%.2f -> %.2f)" % [u1, float(nn["units"])])
	Rules.VAT_UPGRADE_PAUSES = false
	# RELAY: a laser or a juicer only
	var rs := _sim(L09R)
	var rn: Dictionary = rs.nodes[9]
	rn["owner"] = "A"
	rn["units"] = 900.0
	check(Sim.node_category(rn) == "relay" and rn["buildable"] == ["laser", "forge"], "RELAY: offers laser or juicer only (%s)" % str(rn["buildable"]))
	check(rs.can_build(9, "A", "monster_hub") != "" and rs.can_build(9, "A", "vat") != "" and rs.can_build(9, "A", "machinegoon") != "",
			"RELAY: no monster hub, vat or Googatling (%s)" % rs.can_build(9, "A", "monster_hub"))
	check(rs.can_build(9, "A", "laser") == "" and rs.can_build(9, "A", "forge") == "", "RELAY: laser and juicer both buildable")
	check(Sim.STRUCTURE_NAMES["forge"] == "Juicer" and rs.can_build(9, "A", "monster_hub").contains("Juicer"),
			"the forge is called Juicer ('%s')" % rs.can_build(9, "A", "monster_hub"))
	var ln := {"node_kind": "relay", "relay": "launcher"}
	check(Sim.node_category(ln) == "relay_special", "RELAY SPECIAL: the launcher's slot is its own category")
	# a node can be rebuilt after a sinkhole (player, then AI)
	var ks := _sim(L09C, 5, sl)
	var kn: Dictionary = ks.nodes[3]
	kn["owner"] = "B"
	kn["tier"] = 1
	kn["structure"] = "vat"
	kn["units"] = 30.0
	ks._sinkhole("A", kn)
	check(kn["structure"] == "" and kn["owner"] == "B", "Sinkhole: a T1 vat is destroyed, the node stays B's")
	kn["units"] = 200.0
	check(ks.can_build(3, "B", "vat") == "" and ks.build(3, "B", "vat"), "SINKHOLE REBUILD: the owner builds the vat again (%s)" % ks.can_build(3, "B", "vat"))
	for i in range(int(Rules.BUILD_SECONDS / 0.1) + 2):
		ks.step(0.1)
	check(kn["structure"] == "vat" and int(kn["tier"]) == 1, "SINKHOLE REBUILD: the vat stands again (%s T%d)" % [kn["structure"], int(kn["tier"])])
	ks._sinkhole("A", kn)
	kn["units"] = 200.0
	var ai := SeatAI.new("B", 2.0, "Standard")
	for i in range(60):
		ai.think(ks, 0.1)
		ks.step(0.1)
		if kn["build_kind"] != "" or kn["structure"] != "":
			break
	check(kn["build_kind"] == "vat_restore" or kn["structure"] == "vat", "SINKHOLE REBUILD: the AI rebuilds its emptied node (%s / %s)" % [kn["build_kind"], kn["structure"]])
	# Last Stand = the quota: no INWARD / OUTWARD state
	var ls := _sim(L11P)
	ls.start_last_stand_now()
	check(ls.last_stand_active and ls.last_stand_method == "quota", "Last Stand: the quota names it, no method (got '%s')" % ls.last_stand_method)
	check(ls.events.any(func(e): return e["type"] == "last_stand" and e["method"] == "quota"), "the last_stand event says quota")
	# edge kinds (the one read for special bridges)
	var es := _sim(L09C)
	var kinds := {}
	for ei in range(es.edges.size()):
		kinds[es.edge_kind(ei)] = kinds.get(es.edge_kind(ei), 0) + 1
	check(kinds.has("joint") and kinds.has("deck") and kinds.size() == 2, "edge_kind on L09C: joints and decks only %s" % str(kinds))
	check(es.nodes.all(func(n): return n.has("edge_rule") and n["edge_rule"] == ""), "nodes carry an empty edge_rule (hook, ignored now)")
	Rules.JOINTS = false
	var es2 := _sim(L09C)
	check(not range(es2.edges.size()).any(func(ei): return es2.edge_kind(ei) == "joint"), "JOINTS false (legacy): no joint edge")
	_rules3()
	_parts_done += 1


func _init() -> void:
	_part_a()
	_part_c()
	_part_b()
	_part_d()
	_part_f()
	_determinism()
	_rules3()
	check(_parts_done == 6, "every part ran to its end (A, C, B, D, F, determinism: %d of 6)" % _parts_done)
	print("test_rules3: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
