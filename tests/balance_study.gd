extends SceneTree
## BALANCE STUDY (2026-10-27, Architect helper, measurement only): AI-vs-AI headless matches on the pooled BRAWL maps with the
## game's real settings (abilities on, Sim.ai_builds - each AI seat plays one of its faction's AI_LOADOUTS builds -, Last Stand on).
##   Godot --headless --path . --script res://tests/balance_study.gd -- --mode=1v1|2v2 [--level=Expert] [--seeds=1] [--seed0=0]
##       [--shard=k/n] [--out=user://x.jsonl] [--maps=N-01,N-02] [--fixed=a,b]
## 1v1: every ordered faction pair (a in seat A, b in seat B; mirrors included) on every pooled 1v1 map, `seeds` times.
## 2v2: each seat gets a faction drawn from the seed (deterministic), every pooled 2v2 map, `seeds` times.
## One JSON line per match: winner, time, Last Stand, hard end, builds, casts, captures, snapshots (nodes / production /
## strength per seat at 30..300 s), losses. tools/balance_report.py turns the lines into the report tables.

const Habit := preload("res://tests/balance_habit.gd")
var args := {}
var _maps := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var mode := str(args.get("mode", "1v1"))
	var level := str(args.get("level", "Expert"))
	var seeds := int(args.get("seeds", "1"))
	var seed0 := int(args.get("seed0", "0"))
	var want: Array = Array(str(args.get("maps", "")).split(",", false))
	var facs := ["vex", "null", "bloom", "ember", "solar"]
	var pool := []
	for p in MapPool.battlefield():
		var m := _map(p)
		if not (m["seats"] as Dictionary).has(mode):
			continue
		var code := str(m.get("code", p.get_file().substr(0, 4)))
		if not want.is_empty() and not code.substr(0, 4) in want:
			continue
		if not str(p.get_file()).begins_with("N-") and want.is_empty():
			continue                                  # the pooled N maps only (older maps just fill modes no N map offers)
		pool.append(p)
	var study := str(args.get("study", "base"))
	var jobs := []
	for p in pool:
		for s in range(seeds):
			if study == "habit":
				for h in ["noskills", "nomg", "noslot", "nomonster"]:
					for f in facs:
						for vs in ["A", "B"]:
							var spec := {}
							for seat in ["A", "B"]:
								spec[seat] = {"f": f, "h": h if seat == vs else "stock"}
							jobs.append([p, spec, seed0 + s, "habit:" + h, vs])
			elif study == "power":
				for slot in ["active", "map"]:
					for pid in (Rules.ACTIVE_SKILLS if slot == "active" else Rules.MAP_SKILLS):
						for f in facs:
							for vs in ["A", "B"]:
								var spec := {}
								for seat in ["A", "B"]:
									var d: Dictionary = Rules.FACTION_LOADOUT[f]
									var lo := {"active": d["active"], "map": d["map"]}
									if seat == vs:
										lo[slot] = pid
									spec[seat] = {"f": f, "h": "stock", "lo": lo}
								jobs.append([p, spec, seed0 + s, "power:" + slot + ":" + pid, vs])
			elif mode == "1v1":
				if args.has("fixed"):
					var f := str(args["fixed"]).split(",")
					jobs.append([p, {"A": {"f": f[0], "h": "stock"}, "B": {"f": f[1], "h": "stock"}}, seed0 + s, "base", ""])
				else:
					for a in facs:
						for b in facs:
							jobs.append([p, {"A": {"f": a, "h": "stock"}, "B": {"f": b, "h": "stock"}}, seed0 + s, "base", ""])
			else:
				var r := RandomNumberGenerator.new()
				r.seed = hash("%s|%d" % [p, seed0 + s])
				var spec := {}
				for seat in ["A", "B", "C", "D"]:
					spec[seat] = {"f": facs[r.randi() % facs.size()], "h": "stock"}
				jobs.append([p, spec, seed0 + s, "base", ""])
	var shard := str(args.get("shard", "0/1")).split("/")
	var k := int(shard[0])
	var nsh := int(shard[1])
	var f := FileAccess.open(str(args.get("out", "user://balance_study.jsonl")), FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	var done := 0
	for j in range(jobs.size()):
		if j % nsh != k:
			continue
		var rec := _play(jobs[j][0], mode, level, jobs[j][1], 5000 + int(jobs[j][2]) * 7919 + (j / 2) * 31)
		rec["study"] = jobs[j][3]
		rec["vseat"] = jobs[j][4]
		rec["mode"] = mode
		rec["level"] = level
		f.store_line(JSON.stringify(rec))
		f.flush()
		done += 1
	f.close()
	print("shard %d/%d: %d matches in %.0f s" % [k, nsh, done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _map(path: String) -> Dictionary:
	if not _maps.has(path):
		_maps[path] = MapBuilder.load_map(path)
	return _maps[path]


func _yaw(m: Dictionary) -> void:
	var pos := MapBuilder.layout(m)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for k in pos:
		lo = lo.min(pos[k])
		hi = hi.max(pos[k])
	Rules.view_yaw = PI / 2.0 if (hi - lo).z > (hi - lo).x else 0.0


func _snap(sim: Sim, seats: Array) -> Dictionary:
	var s := {}
	for seat in seats:
		var nodes := 0
		var prod := 0.0
		var tiers := 0
		var strucs := {}
		for n in sim.nodes:
			if n["owner"] == seat:
				nodes += 1
				prod += sim.production(n)
				if Sim.has_vat(n):
					tiers += int(n["tier"])
				if n["structure"] != "vat":
					strucs[n["structure"]] = int(strucs.get(n["structure"], 0)) + 1
		s[seat] = [nodes, snappedf(Rules.shown(prod), 0.01), snappedf(Rules.shown(sim.seat_strength(seat)), 0.1), tiers, strucs]
	return s


func _play(path: String, mode: String, level: String, spec: Dictionary, seed_value: int) -> Dictionary:
	var ov = JSON.parse_string(str(args.get("override", "{}")))
	Rules.apply_balance("", ov if ov is Dictionary else {})
	Rules.bridge_combat = false
	Rules.last_stand = true
	Rules.abilities_on = true
	var m: Dictionary = _map(path).duplicate(true)
	var seats := {}
	var teams := {}
	for s in m["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
		if typeof(s.get("team")) in [TYPE_INT, TYPE_FLOAT]:
			teams[s["seat"]] = int(s["team"])
	_yaw(m)
	var sim := Sim.new()
	sim.ai_builds = true
	var factions := {}
	var lo_by := {}
	for seat in spec:
		factions[seat] = spec[seat]["f"]
		if spec[seat].has("lo"):
			lo_by[seat] = spec[seat]["lo"]
	sim.setup(m, MapBuilder.layout(m), seats, factions, seed_value, teams, lo_by)
	var seat_list: Array = seats.values()
	seat_list.sort()
	var ais := []
	for seat in seat_list:
		ais.append(Habit.new(seat, level, spec[seat]["h"], seed_value))
	var snaps := {}
	var next_snap := 30.0
	var dt := 0.1
	while not sim.over and sim.time < 600.0:
		for ai in ais:
			ai.think(sim, dt)
		sim.step(dt)
		sim.fx_events.clear()
		if sim.time >= next_snap:
			snaps[str(int(next_snap))] = _snap(sim, seat_list)
			next_snap += 30.0
	var builds := []
	var casts := []
	var caps := []
	var ls_t := -1.0
	var vls_t := -1.0
	var forced := false
	var draw := false
	var monsters := {}
	var elim := {}
	for e in sim.events:
		match str(e["type"]):
			"build_start":
				builds.append([snappedf(e["t"], 0.1), e["seat"], e["kind"]])
			"skill":
				casts.append([snappedf(e["t"], 0.1), e["seat"], e["id"], e["slot"]])
			"capture":
				caps.append([snappedf(e["t"], 0.1), e["seat"], e.get("from", ""), int(sim.nodes[int(e["node"])]["tier"])])
			"last_stand":
				if ls_t < 0.0:
					ls_t = snappedf(e["t"], 0.1)
			"very_last_stand":
				vls_t = snappedf(e["t"], 0.1)
			"end":
				forced = bool(e.get("forced", false))
				draw = bool(e.get("draw", false))
			"monster_take":
				monsters[e["seat"]] = int(monsters.get(e["seat"], 0)) + 1
			"eliminated":
				elim[e["seat"]] = snappedf(e["t"], 0.1)
			"cannon_burst":
				pass
	var bursts := {}
	for e in sim.events:
		if str(e["type"]) == "cannon_burst":
			bursts[e["seat"]] = int(bursts.get(e["seat"], 0)) + 1
	var losses := {}
	for seat in seat_list:
		losses[seat] = [snappedf(Rules.shown(sim.combat_losses.get(seat, 0.0)), 0.1), snappedf(Rules.shown(sim.fall_losses.get(seat, 0.0)), 0.1)]
	var winner_side: String = ""
	if sim.winner != "":
		winner_side = sim.winner
	return {"map": str(m.get("code", path.get_file().substr(0, 4))), "file": path.get_file(), "spec": factions, "habits": {"A": spec["A"]["h"], "B": spec["B"]["h"]} if spec.has("B") else {}, "teams": teams,
			"loadouts": sim.loadouts, "winner": sim.winner, "t": snappedf(sim.time, 0.1), "over": sim.over, "forced": forced,
			"draw": draw, "ls_t": ls_t, "vls_t": vls_t, "builds": builds, "casts": casts, "caps": caps, "snaps": snaps,
			"losses": losses, "bursts": bursts, "monsters": monsters, "elim": elim, "seed": seed_value}
