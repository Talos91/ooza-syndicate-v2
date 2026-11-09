extends SceneTree
## demo-rules-pass: test_powers_ai's match on R-01 over 10 seeds per power (the suite plays one seed on the one demo map).
##   Godot --headless --path . --script res://tests/powers_seeds_probe.gd

func _init() -> void:
	Rules.last_stand = false
	var t = load("res://tests/test_powers_ai.gd").new()
	for id in ["fog", "portal", "evac"]:
		var per := []
		for k in range(int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 10):
			var sim: Sim = t._match("res://maps4/R-01-strait.json", {t.POWERS[id]: id}, {"A": "null", "B": "ember"}, 300 + k)
			per.append(sim.events.filter(func(e): return e["type"] == "skill" and e["id"] == id).size())
			if k == 0:
				var ids := {}
				for e in sim.events:
					if e["type"] == "skill":
						ids[e["id"]] = int(ids.get(e["id"], 0)) + 1
				var own := {}
				for n in sim.nodes:
					own[n["owner"]] = int(own.get(n["owner"], 0)) + 1
				print("  %s seed 300: t %.0f over %s winner '%s' skills %s loadout A %s nodes %s" % [id, sim.time, sim.over, sim.winner, ids, sim.loadouts.get("A"), own])
		print("%s casts per seed %s" % [id, per])
	quit(0)
