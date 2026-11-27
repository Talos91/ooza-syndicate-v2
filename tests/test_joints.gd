extends SceneTree
## LAB JOINT edges (WP3, 05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md; Daniele 2026-11-23: "a cluster is two or three
## platforms joined directly"): headless check of the cluster maps L09C / L11C / L13C and of the plain maps with the option off.
##   Godot --headless --path . --script res://tests/test_joints.gd        Exit code 0 = all passed.
## OOZE 3.0 (WP1; was tests/test_lab_joints.gd): joints are a rule now, Rules.JOINTS (default true; false = the 0.25 game). Which
## maps the pickers offer is WP2's (MapPool), so the "offered" checks left with the lab pool; the lab overlay's counts are
## counted here; the L11P golden replay became "joints on = joints off" on a map without joints (the 3.0 sizes and rules
## changed every event).

const CLUSTER_MAPS := ["res://maps4/L09C-clusters-9.json", "res://maps4/L11C-clusters-11.json", "res://maps4/L13C-clusters-13.json"]
# L11P, AI vs AI, seed 5 (A Standard null / B Veteran ember): recorded on the untouched lab tip 22134b70 before WP3 (B at 185.3 s,
# 163 events); re-recorded for lab4 (L11P rebuilt into the zoom box, same graph) with joints off AND on agreeing

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


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


func _joint(sim: Sim, a: int, b: int) -> int:
	var ei := sim._edge_index(a, b)
	return ei if ei >= 0 and sim.edges[ei].get("joint", false) else -1


func _init() -> void:
	check(not Rules.lab and Rules.JOINTS, "3.0: joints are a rule (Rules.JOINTS), not a lab option")

	# ------------------------------------------------------------ the maps
	var m9 := MapBuilder.load_map(CLUSTER_MAPS[0])
	var nj: int = (m9["edges"] as Array).filter(func(e): return e.get("joint", false) == true).size()
	check(nj == 8, "L09C: 8 joints (got %d)" % nj)

	# ------------------------------------------------------------ a joint hop: vat -> contact -> vat, straight
	var sim := _sim(CLUSTER_MAPS[0])
	var home: int = sim.homes["A"]
	var jei := _joint(sim, home, 1)
	check(jei >= 0, "L09C: home A (%d) and node 1 are joined by a joint" % home)
	check(sim.edges[jei]["plaza"] and sim.edges[jei]["modules"] == 0.0, "the joint has no deck (modules 0)")
	check(not sim.edge_controller.has(jei), "no relay governs a joint")
	check(sim.find_route(home, 1) == [home, 1], "route home -> 1 is the joint")
	var path := sim.build_path([home, 1])
	var pts: PackedVector3Array = path["pts"]
	var pa: Vector3 = sim.nodes[home]["pos"]
	var pb: Vector3 = sim.nodes[1]["pos"]
	var on_ring := 0
	for p in pts:
		for c in [pa, pb]:
			if absf(((p - c) * Vector3(1, 0, 1)).length() - Rules.BRAWL_RING) < 0.05:
				on_ring += 1
	var corners := 1                                   # (the contact point is laid twice: A's exit and B's way in)
	for k in range(1, pts.size()):
		if pts[k].distance_to(pts[k - 1]) > 0.01:
			corners += 1
	check(corners == 3, "joint path = 3 points: A's door, the contact point, B's door (got %d)" % corners)
	check(on_ring == 0, "no rim-ring points on the joint path (got %d)" % on_ring)
	check(pts[1].distance_to(sim.joint_point(jei)) < 0.01, "the path crosses at the contact point")
	var cum: PackedFloat32Array = path["cum"]
	var want: float = cum[cum.size() - 1] / Rules.move_speed()
	var hops := sim.joint_hops()
	print("      hop: walk %.2f m = %.2f s at %.2f m/s; joint_hops %.2f - %.2f s" % [cum[cum.size() - 1], want, Rules.move_speed(), hops.x, hops.y])
	sim.nodes[home]["units"] = 400.0
	var before: float = sim.nodes[1]["units"]
	var h := sim.send(home, 1, 1.0)
	check(not h.is_empty(), "send home -> 1 across the joint")
	var t := 0.0
	var t_in := -1.0
	while t < 30.0 and t_in < 0.0:
		sim.step(0.02)
		t += 0.02
		if sim.nodes[1]["owner"] == "A" or sim.nodes[1]["units"] != before:
			t_in = t
	print("      hop: first arrival %.2f s (expected %.2f s)" % [t_in, want])
	check(t_in > 0.0 and absf(t_in - want) <= want * 0.1, "the line reaches the neighbour in %.2f s (+-10 %% of %.2f)" % [t_in, want])

	# ------------------------------------------------------------ unbreakable, no deck skill
	sim = _sim(CLUSTER_MAPS[0])
	home = sim.homes["A"]
	jei = _joint(sim, home, 1)
	check(sim._power_check("A", "sever", jei) != "", "Sever cannot target a joint (%s)" % sim._power_check("A", "sever", jei))
	check(sim._power_check("A", "backwash", jei) != "", "Backwash cannot target a joint")
	check(sim._target_check("A", "demolish", jei) != "", "Demolish cannot target a joint (%s)" % sim._target_check("A", "demolish", jei))
	check(sim._target_check("A", "scorch", jei) != "", "Scorch cannot target a joint")
	check(not (jei in sim._quake_decks(1)), "Quake drops no joint")
	var deck13 := sim._edge_index(1, 3)
	check(deck13 >= 0 and sim._target_check("A", "demolish", deck13) == "", "(control) Demolish can target the deck 1-3")
	sim._begin_break(jei, 1)
	check(not sim.breaking.has(jei), "a deck break never starts on a joint")
	sim._drop_node(1)                                  # Last Stand: node 1 falls
	check(not sim.breaking.has(jei) and not sim.breaking.has(_joint(sim, 1, 2)), "the Last Stand wave skips the joints of a fallen node")
	check(sim.breaking.has(deck13), "(control) its deck 1-3 breaks")
	sim._check_missing_decks()
	check(sim.find_route(home, 2) == [home, 2], "the other joint of the home still carries (route home -> 2)")

	# ------------------------------------------------------------ a route through a middle cluster node
	sim = _sim(CLUSTER_MAPS[0])
	home = sim.homes["A"]
	var r := sim.find_route(home, 3)
	check(r == [home, 1, 3] or r == [home, 2, 1, 3], "route home -> 3 goes through cluster node 1 (%s)" % str(r))
	var p2 := sim.build_path([home, 1, 3])
	var pts2: PackedVector3Array = p2["pts"]
	var ring1 := 0
	for p in pts2:
		if absf(((p - (sim.nodes[1]["pos"] as Vector3)) * Vector3(1, 0, 1)).length() - Rules.BRAWL_RING) < 0.05:
			ring1 += 1
	check(ring1 >= 2, "through the middle node the line goes round its route ring (%d ring points)" % ring1)
	check((p2["node_spans"] as Array).size() == 1 and int(p2["node_spans"][0]["node"]) == 1, "node 1 is the one crossed")
	check(pts2[1].distance_to(sim.joint_point(_joint(sim, home, 1))) < 0.01, "out of the vat straight to the contact point")
	sim.nodes[home]["units"] = 600.0
	var b3: float = sim.nodes[3]["units"]
	var h3 := sim.send(home, 3, 1.0)
	t = 0.0
	var hit3 := false
	while t < 40.0 and not hit3:
		sim.step(0.05)
		t += 0.05
		hit3 = sim.nodes[3]["owner"] == "A" or sim.nodes[3]["units"] != b3
	check(not h3.is_empty() and hit3, "a send through the middle node reaches node 3 (%.1f s)" % t)

	# ------------------------------------------------------------ AI vs AI on every cluster map
	for path_c in CLUSTER_MAPS:
		var s := _sim(path_c)
		_ai_match(s)
		var caps := s.events.filter(func(e): return e["type"] == "capture").size()
		print("      %s: over=%s winner=%s at %.1f s, captures %d" % [path_c.get_file(), s.over, s.winner, s.time, caps])
		check(s.over and s.winner != "", "%s: AI vs AI ends with a winner" % path_c.get_file())

	# ------------------------------------------------------------ JOINTS off: a map without joints plays the same
	var runs := []
	for opt in [false, true]:
		Rules.JOINTS = opt
		var s := _sim("res://maps4/L11P-grid-11.json")
		_ai_match(s, 600.0)
		runs.append([s.winner, snappedf(s.time, 0.1), s.events.size()])
		print("      L11P joints=%s: winner %s at %.1f s, %d events" % [opt, s.winner, s.time, s.events.size()])
	check(runs[0] == runs[1], "L11P (no joints) plays the same with JOINTS off and on %s" % str(runs[1]))
	Rules.JOINTS = false
	var off := _sim(CLUSTER_MAPS[0])
	check(not off.edges.any(func(e): return e.get("joint", false)), "JOINTS off: the sim makes no joint edge")
	Rules.JOINTS = true

	print("test_joints: %d failure(s)" % failures)
	_tap_cases()
	quit(1 if failures else 0)


func _tap_cases() -> void:
	## OOZE 3.0 WP4: NEAREST-NODE TAP on touching platforms (TapPick.nearest = main._node_at's ground pick). On every joint of the
	## Z cluster maps: a point 1 m off either centre picks that node, a point just either side of the contact picks the near side,
	## and a phone finger past the rim (R + 2 m, away from the partner) still picks it.
	var maps := []
	for f in DirAccess.get_files_at("res://maps4/"):
		if f.begins_with("Z-") and f.ends_with(".json"):
			maps.append("res://maps4/" + f)
	var joints := 0
	var bad := 0
	for path in maps:
		var sim := _sim(path)
		for ei in range(sim.edges.size()):
			if sim.edge_kind(ei) != "joint":
				continue
			joints += 1
			var a: int = sim.edges[ei]["a"]
			var b: int = sim.edges[ei]["b"]
			var pa: Vector3 = sim.nodes[a]["pos"]
			var pb: Vector3 = sim.nodes[b]["pos"]
			var dir := (pb - pa).normalized()
			var mid := (pa + pb) * 0.5
			var cases := [[pa + dir, a, true], [pb - dir, b, true], [mid - dir * 0.2, a, true], [mid + dir * 0.2, b, true],
					[mid - dir * 0.2, a, false], [mid + dir * 0.2, b, false]]
			for end in [[a, pa], [b, pb]]:                # a phone finger past the rim, on the side with no other platform near
				var far := _open_side(sim, int(end[0]))
				if far != Vector3.ZERO:
					cases.append([(end[1] as Vector3) + far * (Rules.R + 2.0), end[0], true])
			for c in cases:
				var got := TapPick.nearest(sim, c[0], c[2])
				if got != int(c[1]):
					bad += 1
					print("FAIL  tap %s joint %d-%d at %s (%s): got %d, want %d" % [path.get_file(), a, b, str(c[0]), "phone" if c[2] else "desktop", got, c[1]])
	check(joints > 0, "Z cluster maps have joints to tap (%d)" % joints)
	check(bad == 0, "nearest-node tap holds on every joint of the Z maps (%d joints x 6-8 taps, %d wrong)" % [joints, bad])


func _open_side(sim: Sim, id: int) -> Vector3:
	## A unit direction from node id whose point at R + 2 m is farther than R + 2.5 m from every other node (ZERO if none).
	var c: Vector3 = sim.nodes[id]["pos"]
	for k in range(16):
		var d := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0))
		var p := c + d * (Rules.R + 2.0)
		if sim.nodes.all(func(n): return int(n["id"]) == id or (n["pos"] as Vector3).distance_to(p) > Rules.R + 2.5):
			return d
	return Vector3.ZERO
