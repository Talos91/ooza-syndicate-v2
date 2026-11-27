extends SceneTree
## Headless map-pool check:  Godot --headless --path . --script res://tests/test_map_pool.gd
## Every map in MapPool loads, has seats (1v1, or its first team/FFA mode), lays out every node, and an AI vs AI match on it
## finishes with captures. Exit code 0 = all passed.
## The AI seats play what they get in a match (ai-retune-prep): Sim.ai_builds on, so each takes one of its faction's
## Rules.AI_LOADOUTS builds by the fixed seed. `-- guard=off` plays them without their home-defence reflex (SeatAI._guard).

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


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return fallback


func _init() -> void:
	SeatAI.guard_on = _arg("guard", "on") != "off"
	if not MapPool.POOL3.is_empty():
		_pool3()
		return
	var paths := MapPool.battlefield()
	if Rules.proto_debug:   # proto / demo build: check the proto + keep-list scope (Daniele 2026-11-10), not just the demo's one map
		paths = MapPool.all().filter(func(p): return p.get_file().substr(0, 4) in MapPool.test_scope())
	print("%d maps in the pool" % paths.size())
	# KEEP LIST (Daniele 2026-11-10): every kept old map is baked and not archived; every archived map is baked, withheld and unmodeled
	for code in MapPool.KEEP_OLD:
		check(not code in MapPool.ARCHIVED and MapPool.all().any(func(p): return p.get_file().begins_with(code)), "%s: kept, baked, not archived" % code)
	for code in MapPool.ARCHIVED:
		check(not MapPool.mode_offered(code, "1v1"), "%s: archived (no mode offered; 65 archived files deleted 2026-11-23, tag archive-2026-11-23)" % code)
	check(not MapPool.battlefield().any(func(p): return MapPool.archived(p)), "no archived map on the battlefield")
	# POOL G (Daniele 2026-11-15): the pool is the 19 G maps; the 18 REWORK maps stay baked but are never offered
	check(MapPool.PROTO.size() == 19 and MapPool.PROTO.all(func(c): return MapPool.all().any(func(p): return p.get_file().begins_with(c))), "POOL G: 19 G maps, all baked")
	for code in MapPool.REWORK:
		var fill: bool = code in MapPool.MULTI_FILL   # hotfix 0.24.5.1: M-15 / N-06 are offered as is for the modes no G map seats
		check(MapPool.all().any(func(p): return p.get_file().begins_with(code)) and not MapPool.mode_offered(code, "1v1")
				and (fill or (not MapPool.mode_offered(code, "2v2") and not MapPool.battlefield().any(func(p): return p.get_file().begins_with(code)))) and not code in MapPool.DEMO, "%s: REWORK (file kept, %s)" % [code, "offered only for modes the G pool lacks" if fill else "offered nowhere"])
	for code in MapPool.MULTI_FILL:
		check(MapPool.mode_offered(code, "2v2") and MapPool.battlefield().any(func(p): return p.get_file().begins_with(code)), "%s: MULTI_FILL offered for 2v2" % code)
	for old in MapPool.RECODED:
		check(not MapPool.all().any(func(p): return p.get_file().begins_with(old)), "%s: re-coded %s (no old-coded file left)" % [old, MapPool.RECODED[old]])
	if not Rules.proto_debug:
		check(MapPool.battlefield().all(func(p): return p.get_file().begins_with("G-") or p.get_file().substr(0, 4) in MapPool.MULTI_FILL), "POOL G: 02 BATTLEFIELD offers only G maps (+ MULTI_FILL for 2v2 / FFA)")
	# SEAT BIAS: N-24 / N-04 were out of 1v1 from 0.23.15; back in since 0.23.18 (Daniele 2026-11-01, Desk vls-fair: the Very Last
	# Stand tie-break fixed the bias) - offered in 1v1 and on 02 BATTLEFIELD again
	for code in ([] if Rules.proto_debug else ["N-24", "N-04"]):   # (old maps: not checked on a proto/demo build, Daniele 2026-11-06)
		check(not MapPool.WITHHELD_MODES.get(code, []).has("1v1") and MapPool.mode_offered(code, "1v1"), "%s: offered in 1v1 again (vls-fair)" % code)
		check(paths.any(func(p): return p.get_file().begins_with(code)), "%s: on 02 BATTLEFIELD / the random rematch again" % code)
		check(MapPool.all().any(func(p): return p.get_file().begins_with(code)), "%s: still baked and in MapPool.all()" % code)
	if Rules.proto_debug:   # proto build: the picker lists only the prototype maps (MapPool.PROTO)
		check(paths.size() == MapPool.test_scope().size() and paths.all(func(p): return p.get_file().substr(0, 4) in MapPool.test_scope()), "proto build: the checked scope is exactly MapPool.PROTO + KEEP_OLD (%d)" % paths.size())
	else:
		check(MapPool.mode_offered("N-01", "1v1") and paths.any(func(p): return p.get_file().begins_with("N-01")), "an unbiased 1v1 map (N-01) is still offered")
	check(not paths.any(func(p): return p.get_file().substr(0, 4) in MapPool.TUTORIAL_ONLY), "no tutorial map on 02 BATTLEFIELD")
	for map_path in paths:
		var sm := MapBuilder.load_map(map_path)
		check(sm.has("seats") and not sm["seats"].is_empty(), "%s: has seats" % map_path)
		if sm.get("seats", {}).is_empty():
			continue
		# 1v1 where the map has it, otherwise its first mode (2v2 / 3v3 / FFA) - Alpha 14 plays them all
		var md: String = "1v1" if sm["seats"].has("1v1") else sm["seats"].keys()[0]
		var spos := MapBuilder.layout(sm)
		check(spos.size() == sm["nodes"].size(), "%s: every node reachable from the centre (%d/%d)" %
				[sm["code"], spos.size(), sm["nodes"].size()])
		var s_seats := {}
		for s in sm["seats"][md]:
			s_seats[int(s["node"])] = s["seat"]
		# every map plays BRAWL (SIEGE deleted 2026-11-23 - a map's "combatMode" no longer picks the mode)
		_play(sm, spos, s_seats, md)

	_check_overpass()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)


func _pool3() -> void:
	## OOZE 3.0 (plan 2.4, Daniele 2026-11-27: old pool-G maps are not in the 3.0 build): the pickers offer ONLY the Z maps
	## (MapPool.POOL3) on every build line; every older map stays baked (nothing deleted) and is offered nowhere;
	## every Z map loads, seats 1v1, lays out every node and finishes a headless AI vs AI match.
	var demo0 := Rules.demo
	var proto0 := Rules.proto_debug
	for line in [[false, false, false, "release"], [false, false, true, "-dev / proto"], [false, true, true, "demo"]]:
		Rules.demo = line[1]
		Rules.proto_debug = line[2]
		MapPool._battlefield_cache = []
		var bf := MapPool.battlefield()
		var codes := bf.map(func(p): return p.get_file().substr(0, 4))
		check(codes == Array(MapPool.POOL3), "%s line: the picker offers exactly the Z maps %s (got %s)" % [line[3], str(MapPool.POOL3), str(codes)])
		for code in ["G-01", "G-19", "N-06", "M-15", "T-02"]:
			check(not MapPool.mode_offered(code, "1v1") and not MapPool.mode_offered(code, "2v2"), "%s line: old map %s offered in no mode" % [line[3], code])
		for code in MapPool.POOL3:
			check(MapPool.mode_offered(code, "1v1"), "%s line: %s offered in 1v1" % [line[3], code])
	Rules.demo = demo0
	Rules.proto_debug = proto0
	MapPool._battlefield_cache = []
	check(MapPool.test_scope() == MapPool.POOL3, "test_scope() is POOL3")
	check(MapPool.all().any(func(p): return p.get_file().begins_with("G-01")), "old maps stay baked (G-01 in MapPool.all())")
	var paths := MapPool.all().filter(func(p): return p.get_file().substr(0, 4) in MapPool.POOL3)
	check(paths.size() == MapPool.POOL3.size(), "every POOL3 map is baked (%d of %d)" % [paths.size(), MapPool.POOL3.size()])
	print("%d maps in the pool (POOL3)" % paths.size())
	for map_path in paths:
		var sm := MapBuilder.load_map(map_path)
		check(sm.get("seats", {}).has("1v1"), "%s: seats 1v1" % map_path)
		if not sm.get("seats", {}).has("1v1"):
			continue
		var spos := MapBuilder.layout(sm)
		check(spos.size() == sm["nodes"].size(), "%s: every node laid out (%d/%d)" % [sm["code"], spos.size(), sm["nodes"].size()])
		var s_seats := {}
		for st in sm["seats"]["1v1"]:
			s_seats[int(st["node"])] = st["seat"]
		_play(sm, spos, s_seats, "1v1")
	_check_overpass()
	print("
%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)


func _play(sm: Dictionary, spos: Dictionary, s_seats: Dictionary, md: String) -> void:
		var ssim := Sim.new()
		ssim.ai_builds = true                              # the AI seats' rotating builds, as in play (seed 5)
		ssim.setup(sm, spos, s_seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 5)
		var s_ais := []
		for seat in s_seats.values():
			s_ais.append(SeatAI.new(seat, 2.0, "Standard" if seat == "A" else "Veteran"))
		var ssteps := 0
		while not ssim.over and ssteps < 20 * 60 * 8:
			for ai in s_ais:
				ai.think(ssim, 0.1)
			ssim.step(0.1)
			ssteps += 1
		var caps := ssim.events.filter(func(e): return e["type"] == "capture").size()
		var fires := ssim.events.filter(func(e): return e["type"] == "relay_fired").size()
		var builds := {}                                   # structures 2.1 (0.18.10): what the AIs built and launched
		for e in ssim.events:
			if e["type"] == "build_start" and e["kind"] in ["machinegoon", "laser", "forge", "monster_hub"]:
				builds[e["kind"]] = builds.get(e["kind"], 0) + 1
		var monsters := ssim.events.filter(func(e): return e["type"] == "monster_launch").size()
		var guards := 0
		for ai in s_ais:
			guards += int(ai.guards)
		var home_fall := -1.0                              # when a home first changed hands (-1: never)
		for e in ssim.events:
			if e["type"] == "capture" and int(e.get("node", -1)) in ssim.homes.values() and home_fall < 0.0:
				home_fall = float(e["t"])
		var tag := "BRAWL"
		print("      %s %-24s %-5s %-5s over=%s winner=%s at %.0f s, captures=%d relay fires=%d builds=%s monsters=%d guards=%d home fall=%.0f" % [sm["code"],
				str(sm["name"]), md, tag, ssim.over, ssim.winner, ssim.time, caps, fires, str(builds), monsters, guards, home_fall])
		check(ssim.over, "%s %s: AI vs AI finishes within 8 simulated minutes (t=%.0fs)" % [sm["code"], tag, ssim.time])
		check(caps >= 2, "%s %s: AIs capture nodes (%d)" % [sm["code"], tag, caps])
