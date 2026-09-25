extends SceneTree
## Headless map-pool check:  Godot --headless --path . --script res://tests/test_map_pool.gd
## Every map in MapPool loads, has 1v1 seats, lays out every node, and an AI vs AI match on it
## finishes with captures. Exit code 0 = all passed.

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _check_overpass() -> void:
	## Oberon Keep (049): deck 1-4 is an overpass crossing deck 6-7. A horde over and an enemy horde
	## under pass the same spot on the map at different heights and never engage.
	var m := MapBuilder.load_map("res://maps/049-oberon-keep.json")
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), {1: "A", 6: "B"}, {"A": "null", "B": "ember"}, 3)
	var over := sim._edge_index(1, 4)
	check(sim.edges[over]["overpass"] and not sim.edges[sim._edge_index(6, 7)]["overpass"], "049: 1-4 overpass, 6-7 not")
	var top := -INF
	for p in sim.build_path([1, 4])["pts"]:
		top = maxf(top, (p as Vector3).y)
	check(absf(top - Rules.OVERPASS_H) < 0.01, "049: the path over 1-4 rises to OVERPASS_H (%.2f)" % top)
	var flat := -INF
	for p in sim.build_path([6, 7])["pts"]:
		flat = maxf(flat, (p as Vector3).y)
	check(absf(flat) < 0.01, "049: the path along 6-7 stays at deck level")
	for id in [1, 6]:
		sim.nodes[id]["units"] = 200.0
	var ha := sim.send(1, 4, 1.0)
	var hb := sim.send(6, 7, 1.0)
	check(not ha.is_empty() and not hb.is_empty(), "049: both sends go out")
	var closest := INF
	var fought := false
	for step in range(200):
		sim.step(0.05)
		for pair in sim.fights:
			fought = fought or (ha["id"] in pair and hb["id"] in pair)
		if sim.hordes.has(ha) and sim.hordes.has(hb):
			var n := int(Sim.chain_length(hb) / Rules.PATCH_SPACING) + 1
			var pa: Vector3 = Sim.sample(ha, ha["s"])[0]
			for k in range(n):
				var pb: Vector3 = Sim.sample(hb, hb["s"] - k * Rules.PATCH_SPACING)[0]
				closest = minf(closest, Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)))
	check(closest < Rules.CONTACT_R, "049: the over horde passes right above the under line (%.2f m apart on the map)" % closest)
	check(not fought, "049: over and under never engage")


func _init() -> void:
	var paths := MapPool.all()
	print("%d maps in the pool" % paths.size())
	for map_path in paths:
		var sm := MapBuilder.load_map(map_path)
		check(sm.has("seats") and sm["seats"].has("1v1"), "%s: has 1v1 seats" % map_path)
		if not sm.get("seats", {}).has("1v1"):
			continue
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
		print("      %s %-24s over=%s winner=%s at %.0f s, captures=%d relay fires=%d" % [sm["code"],
				str(sm["name"]), ssim.over, ssim.winner, ssim.time, caps, fires])
		check(ssim.over, "%s: AI vs AI finishes within 8 simulated minutes (t=%.0fs)" % [sm["code"], ssim.time])
		check(caps >= 2, "%s: AIs capture nodes (%d)" % [sm["code"], caps])

	_check_overpass()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
