extends SceneTree
## MAP SCORECARD probe (🗺️ map-score, 2026-11-02; measurement only, branch map-score, never merged): AI-vs-AI headless matches
## per pooled map with the game's real settings (abilities on, Sim.ai_builds, Last Stand, 7:00 hard end, two doors), plus the
## seat walk check. Built on tests/balance_study.gd (same AI wrapper, same seed formula, same settings).
##   Godot --headless --path . --script res://tests/map_score.gd -- --study=fair|skill|walk [--seeds=4] [--seed0=0]
##       [--shard=k/n] [--maps=N-01,E-02] [--out=user://x.jsonl]
## fair : Expert vs Expert, the same faction on both seats (each of the five), `seeds` times -> seat win rate, pace, leads, relays.
## skill: Standard vs Veteran, the same faction on both seats, Veteran in seat A and in seat B, `seeds` times -> skill gap.
## walk : no matches; per map the sim walk (find_route + build_path / BRAWL_SPEED, two doors on) from each home to every node.
## One JSON line per match (or per map for walk). tests/map_score_report.py turns the lines into the scorecard.

const Habit := preload("res://tests/balance_habit.gd")
const FACS := ["vex", "null", "bloom", "ember", "solar"]
var args := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var study := str(args.get("study", "fair"))
	var seeds := int(args.get("seeds", "4"))
	var seed0 := int(args.get("seed0", "0"))
	var want: Array = Array(str(args.get("maps", "")).split(",", false))
	var pool := []
	for p in MapPool.battlefield():
		var code: String = p.get_file().substr(0, 4)
		if not code.substr(0, 1) in MapPool.POOL_GROUPS:
			continue
		if not want.is_empty() and not code in want:
			continue
		if not (MapBuilder.load_map(p)["seats"] as Dictionary).has("1v1"):
			continue
		if not MapPool.mode_offered(p, "1v1"):
			continue
		pool.append(p)
	var jobs := []
	if study == "walk":
		for p in pool:
			jobs.append([p, {}, 0])
	for s in range(seeds if study != "walk" else 0):  # seed-major: a run cut by its cap still covers every map evenly
		for p in pool:
			for f in FACS:
				if study == "skill":
					for vet in ["A", "B"]:
						jobs.append([p, {"A": [f, "Veteran" if vet == "A" else "Standard"], "B": [f, "Veteran" if vet == "B" else "Standard"]}, seed0 + s])
				else:
					jobs.append([p, {"A": [f, "Expert"], "B": [f, "Expert"]}, seed0 + s])
	var shard := str(args.get("shard", "0/1")).split("/")
	var k := int(shard[0])
	var nsh := int(shard[1])
	var f := FileAccess.open(str(args.get("out", "user://map_score.jsonl")), FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	var done := 0
	for j in range(jobs.size()):
		if j % nsh != k:
			continue
		var rec: Dictionary
		if study == "walk":
			rec = _walk(jobs[j][0])
		else:
			rec = _play(jobs[j][0], jobs[j][1], 5000 + int(jobs[j][2]) * 7919 + j * 31)
		rec["study"] = study
		f.store_line(JSON.stringify(rec))
		f.flush()
		done += 1
	f.close()
	print("map_score %s shard %d/%d: %d jobs in %.0f s" % [study, k, nsh, done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _yaw(m: Dictionary) -> void:
	var pos := MapBuilder.layout(m)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for key in pos:
		lo = lo.min(pos[key])
		hi = hi.max(pos[key])
	Rules.view_yaw = PI / 2.0 if (hi - lo).z > (hi - lo).x else 0.0


func _setup(path: String, spec: Dictionary, seed_value: int) -> Array:
	Rules.apply_balance("", {})
	Rules.bridge_combat = false
	Rules.last_stand = true
	Rules.abilities_on = true
	var m: Dictionary = MapBuilder.load_map(path).duplicate(true)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	_yaw(m)
	var sim := Sim.new()
	sim.ai_builds = true
	var factions := {}
	for seat in spec:
		factions[seat] = spec[seat][0]
	if factions.is_empty():
		factions = {"A": "null", "B": "null"}
	sim.setup(m, MapBuilder.layout(m), seats, factions, seed_value)
	return [m, sim, seats]


func _walk(path: String) -> Dictionary:
	## Seat walk with two doors (Rules.TWO_DOORS / DOOR_EXITS as shipped): seconds from each home to every platform.
	var r := _setup(path, {}, 1)
	var m: Dictionary = r[0]
	var sim: Sim = r[1]
	var seats: Dictionary = r[2]
	var home := {}
	for id in seats:
		home[seats[id]] = int(id)
	var out := {}
	for seat in ["A", "B"]:
		var times := {}
		for n in sim.nodes:
			if n["node_kind"] == "junction" or int(n["id"]) == int(home[seat]):
				continue
			var route: Array = sim.find_route(home[seat], n["id"])
			if route.size() < 2:
				times[str(n["id"])] = -1.0
				continue
			var bp: Dictionary = sim.build_path(route)
			times[str(n["id"])] = snappedf((bp["cum"] as PackedFloat32Array)[-1] / Rules.BRAWL_SPEED, 0.01)
		out[seat] = times
	return {"map": str(m.get("code", path.get_file().substr(0, 4))), "file": path.get_file(), "home": home, "walk": out,
			"doors": [Rules.TWO_DOORS, Rules.DOOR_EXITS]}


func _play(path: String, spec: Dictionary, seed_value: int) -> Dictionary:
	var r := _setup(path, spec, seed_value)
	var m: Dictionary = r[0]
	var sim: Sim = r[1]
	var ais := []
	for seat in ["A", "B"]:
		ais.append(Habit.new(seat, spec[seat][1], "stock", seed_value))
	var dt := 0.1
	var next_snap := 5.0
	var share := []                                   # seat A's share of total strength every 5 s
	var nodes_a := []                                 # node lead (A - B) every 5 s
	var relay_kill := {"A": 0.0, "B": 0.0}            # enemy units dropped by relays this seat fired (shown)
	var relay_self := {"A": 0.0, "B": 0.0}            # own units dropped by relays this seat fired (shown)
	while not sim.over and sim.time < 600.0:
		for ai in ais:
			ai.think(sim, dt)
		sim.step(dt)
		for e in sim.fx_events:
			if str(e.get("type", "")) in ["fall", "fling"] and e.has("relay"):
				var by := str(e.get("by", ""))
				if by in ["A", "B"]:
					var u := float(e.get("shown", Rules.shown(float(e.get("units", 0.0)))))
					if str(e.get("seat", "")) == by:
						relay_self[by] += u
					else:
						relay_kill[by] += u
		sim.fx_events.clear()
		if sim.time >= next_snap:
			var sa := sim.seat_strength("A")
			var sb := sim.seat_strength("B")
			share.append(snappedf(sa / maxf(sa + sb, 0.001), 0.001))
			var na := 0
			var nb := 0
			for n in sim.nodes:
				if n["owner"] == "A":
					na += 1
				elif n["owner"] == "B":
					nb += 1
			nodes_a.append(na - nb)
			next_snap += 5.0
	var fires := {"A": 0, "B": 0}
	var fires_by_node := {}
	var caps := {"A": 0, "B": 0}
	var relay_caps := {"A": 0, "B": 0}
	var ls_t := -1.0
	var forced := false
	var draw := false
	var first_cap := -1.0
	for e in sim.events:
		match str(e["type"]):
			"relay_fired":
				var s := str(e["seat"])
				if s in fires:
					fires[s] += 1
				fires_by_node[str(e["node"])] = int(fires_by_node.get(str(e["node"]), 0)) + 1
			"capture":
				var s := str(e["seat"])
				if s in caps:
					caps[s] += 1
					if sim.nodes[int(e["node"])]["relay"] != "":
						relay_caps[s] += 1
				if first_cap < 0.0 and str(e.get("from", "")) in ["A", "B"]:
					first_cap = snappedf(e["t"], 0.1)
			"last_stand":
				if ls_t < 0.0:
					ls_t = snappedf(e["t"], 0.1)
			"end":
				forced = bool(e.get("forced", false))
				draw = bool(e.get("draw", false))
	var relay_kinds := {}
	for n in sim.nodes:
		if n["relay"] != "":
			relay_kinds[str(n["id"])] = str(n["relay"])
	return {"map": str(m.get("code", path.get_file().substr(0, 4))), "spec": spec, "winner": sim.winner, "t": snappedf(sim.time, 0.1),
			"over": sim.over, "forced": forced, "draw": draw, "ls_t": ls_t, "first_kill_cap": first_cap, "seed": seed_value,
			"share": share, "nlead": nodes_a, "fires": fires, "fires_by_node": fires_by_node, "relay_kinds": relay_kinds,
			"relay_kill": relay_kill, "relay_self": relay_self, "caps": caps, "relay_caps": relay_caps,
			"fall": {"A": snappedf(Rules.shown(sim.fall_losses.get("A", 0.0)), 0.1), "B": snappedf(Rules.shown(sim.fall_losses.get("B", 0.0)), 0.1)}}
