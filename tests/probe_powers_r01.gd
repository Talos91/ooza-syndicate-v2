extends SceneTree
## Probe (ai-launcher-laser, 2026-11-10): fog / portal / evac casts per seed on one map, Standard vs Standard,
## like test_powers_ai. Also counts the AI attack lines that could carry each cast (hostile goal, size).
##   Godot --headless --path . --script res://tests/probe_powers_r01.gd -- map=R-01 seeds=10 powers=fog,portal,evac

func _initialize() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="):
			return str(a).substr(k.length() + 1)
	return d


func _run() -> void:
	Rules.last_stand = false
	var mid := _arg("map", "R-01")
	var seeds := int(_arg("seeds", "10"))
	var powers := _arg("powers", "fog,portal,evac").split(",")
	var path := ""
	for p in MapPool.all():
		if p.get_file().begins_with(mid):
			path = p
	print("map ", path)
	for id in powers:
		var row := []
		var lines12 := 0
		var lines15 := 0
		var maxl := 0.0
		for k in range(seeds):
			var m := MapBuilder.load_map(path)
			var seats := {}
			for s in m["seats"]["1v1"]:
				seats[int(s["node"])] = s["seat"]
			var slot: String = Rules.SKILLS[id]["slot"]
			var sim := Sim.new()
			sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember"}, 300 + k, {}, {"A": {slot: id}, "B": {slot: id}})
			var ais := []
			for seat in seats.values():
				ais.append(SeatAI.new(seat, 2.5, "Standard"))
			var seen := {}
			while not sim.over and sim.time < 300.0:
				for ai in ais:
					ai.think(sim, 0.1)
				sim.step(0.1)
				for h in sim.hordes:
					if h.get("decoy", false) or h["state"] == "absorb" or seen.has(h["id"]):
						continue
					var g: Dictionary = sim.nodes[sim.line_goal(h)]
					if g["owner"] == "" or g["owner"] == h["owner"]:
						continue
					if h["units"] >= 12.0 * Rules.SCALE:
						seen[h["id"]] = true
						lines12 += 1
						if h["units"] >= 15.0 * Rules.SCALE:
							lines15 += 1
					maxl = maxf(maxl, h["units"] / Rules.SCALE)
			var n := 0
			for e in sim.events:
				if e["type"] == "skill" and e["id"] == id:
					n += 1
			row.append(n)
		print("%-7s casts per seed %s  total %d  | enemy-goal lines >=12: %d, >=15: %d, biggest %.1f" % [id, str(row), row.reduce(func(a, b): return a + b, 0), lines12, lines15, maxl])
	quit(0)
