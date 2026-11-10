extends SceneTree
## Probe: why the AI's portal pick finds nothing on a map (route lengths, entrances, best gain per qualifying line).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Rules.last_stand = false
	var mid := "R-01"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("map="):
			mid = str(a).substr(4)
	var path := ""
	for p in MapPool.all():
		if p.get_file().begins_with(mid):
			path = p
	var m := MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember"}, 300, {}, {"A": {"map": "portal"}, "B": {"map": "portal"}})
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, "Standard"))
	var seen := {}
	print("nodes %d" % sim.nodes.size())
	while not sim.over and sim.time < 300.0:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
		if int(sim.time * 10.0) % 10 == 0:
			for ai in ais:
				for h in ai._my_lines(sim):
					var size: float = maxf(h["units"], float(h["ordered"])) if h["streaming"] else float(h["units"])
					var goal: int = sim.line_goal(h)
					if not ai._hostile(sim, sim.nodes[goal]["owner"]) or size < 12.0 * Rules.SCALE:
						continue
					var ent := -1
					for ns in h["node_spans"]:
						if float(ns["s1"]) > float(h["s"]) and int(ns["node"]) != h["route"][0] and int(ns["node"]) != goal:
							ent = int(ns["node"])
							break
					var g := -1.0
					var why := ""
					if ent >= 0:
						var rest := sim.find_route(ent, goal)
						g = ai._travel(sim, rest) if rest.size() >= 2 else 0.0
						why = sim.cast_check(ai.seat, "map", [ent, goal])
					print("  T t=%.0f %s %s size %.1f s %.0f/%.0f ent %d gain %.1f cd %.0f why '%s'" % [sim.time, ai.seat, str(h["route"]), size / Rules.SCALE, h["s"], h["L"], ent, g, sim.cooldown(ai.seat, "map"), why])
		for h in sim.hordes:
			if h.get("decoy", false) or h["state"] == "absorb" or seen.has(h["id"]) or h["units"] < 12.0 * Rules.SCALE:
				continue
			var goal: int = sim.line_goal(h)
			if sim.nodes[goal]["owner"] == "" or sim.nodes[goal]["owner"] == h["owner"]:
				continue
			seen[h["id"]] = true
			var route: Array = h["route"]
			var ents := []
			for ns in h["node_spans"]:
				if float(ns["s1"]) > float(h["s"]) and int(ns["node"]) != route[0] and int(ns["node"]) != goal:
					ents.append(int(ns["node"]))
			var ai: SeatAI = ais[0] if ais[0].seat == h["owner"] else ais[1]
			var info := ""
			if not ents.is_empty():
				var e: int = ents[0]
				var rest := sim.find_route(e, goal)
				var t_in := ai._travel(sim, rest) if rest.size() >= 2 else 0.0
				var bestg := -999.0
				for ex in sim.portal_exits(e):
					var r2: Array = [] if ex == goal else sim.find_route(ex, goal)
					if ex != goal and r2.size() < 2:
						continue
					bestg = maxf(bestg, t_in - (ai._travel(sim, r2) if ex != goal else 0.0))
				info = "entr %d t_in %.1f bestgain %.1f exits %s" % [e, t_in, bestg, str(sim.portal_exits(e))]
			print("t=%.0f %s %d->%d units %.1f route %s L %.0f s %.0f ents %s %s" % [sim.time, h["owner"], route[0], goal, h["units"] / Rules.SCALE, str(route), h["L"], h["s"], str(ents), info])
	quit(0)
