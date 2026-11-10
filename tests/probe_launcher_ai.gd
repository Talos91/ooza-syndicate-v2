extends SceneTree
## Probe (ai-launcher-laser, 2026-11-10): AI launcher upgrades per tier on the launcher maps, AI vs AI, `seeds` seeds per map.
## Counts build_done "launcher" events by the tier reached, and checks every upgrade started with the launcher idle
## (no load, no salvo) and the price paid matched Rules.LAUNCHER_COST.
##   Godot --headless --path . --script res://tests/probe_launcher_ai.gd -- maps=R-10,R-14 seeds=10 level=Standard mode=1v1

func _initialize() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="):
			return str(a).substr(k.length() + 1)
	return d


func _run() -> void:
	Rules.last_stand = false
	var seeds := int(_arg("seeds", "10"))
	var level := _arg("level", "Standard")
	var mode := _arg("mode", "1v1")
	var bad := 0
	for mid in _arg("maps", "R-10,R-14").split(","):
		var path := ""
		for p in MapPool.all():
			if p.get_file().begins_with(mid):
				path = p
		print("map %s (%s, %s)" % [path, mode, level])
		var tot := {2: 0, 3: 0}
		for k in range(seeds):
			var m := MapBuilder.load_map(path)
			if not m["seats"].has(mode):
				print("  no %s seats" % mode)
				break
			var seats := {}
			for s in m["seats"][mode]:
				seats[int(s["node"])] = s["seat"]
			var sim := Sim.new()
			var fac := {}
			var pool := ["null", "ember", "vex", "bloom"]
			var i := 0
			for seat in seats.values():
				fac[seat] = pool[(i + k) % pool.size()]
				i += 1
			sim.setup(m, MapBuilder.layout(m), seats, fac, 500 + k)
			var ais := []
			for seat in seats.values():
				ais.append(SeatAI.new(seat, 2.5, level))
			var row := {2: 0, 3: 0}
			var first := {}
			var ev0 := 0
			while not sim.over and sim.time < float(_arg("limit", "300")):
				var before := {}
				for n in sim.nodes:
					if n["relay"] == "launcher":
						before[n["id"]] = [n["units"], n["relay_phase"], (n["load"] as Dictionary).size(), n["tier"], n["build_kind"]]
				for ai in ais:
					ai.think(sim, 0.1)
				for n in sim.nodes:                       # an upgrade ordered this think: idle + the right price
					if n["relay"] == "launcher" and n["build_kind"] == "launcher" and before.has(n["id"]) and before[n["id"]][4] == "":
						var b: Array = before[n["id"]]
						var paid: float = float(b[0]) - float(n["units"])
						var want: int = int(Rules.LAUNCHER_COST.get(int(b[3]) + 1, -1))
						if b[1] != "" or b[2] > 0 or absf(paid - want) > 0.01:
							bad += 1
							print("  BAD upgrade node %d phase '%s' load %d paid %.1f want %d" % [n["id"], b[1], b[2], paid, want])
				if _arg("trace", "") != "" and int(round(sim.time * 10.0)) % 200 == 0:
					for n in sim.nodes:
						if n["relay"] == "launcher":
							var ai0: SeatAI = null
							for a in ais:
								if a.seat == n["owner"]:
									ai0 = a
							print("    t=%.0f L%d own '%s' T%d units %.1f phase '%s' build '%s' reserve %s cost %d incoming %s" % [sim.time, n["id"], n["owner"], n["tier"], n["units"] / Rules.SCALE, n["relay_phase"], n["build_kind"], str(ai0._reserve(sim, n) / Rules.SCALE) if ai0 else "-", Rules.shown(sim.upgrade_cost(n)), str(ai0._incoming(sim, n["id"], true)) if ai0 else "-"])
				sim.step(0.1)
				for j in range(ev0, sim.events.size()):
					var e: Dictionary = sim.events[j]
					if e["type"] == "build_done" and e["kind"] == "launcher":
						var t: int = sim.nodes[int(e["node"])]["tier"]
						row[t] = row.get(t, 0) + 1
						if not first.has(t):
							first[t] = int(e["t"])
				ev0 = sim.events.size()
			for t in row:
				tot[t] = tot.get(t, 0) + row[t]
			print("  seed %d %s  ->T2 %d  ->T3 %d  first at %s  winner %s t=%.0f" % [500 + k, str(fac), row[2], row[3], str(first), str(sim.winner) if "winner" in sim else "?", sim.time])
		print("  TOTAL ->T2 %d  ->T3 %d" % [tot[2], tot[3]])
	print("bad upgrades: %d" % bad)
	quit(0)
