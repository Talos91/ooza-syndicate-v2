extends SceneTree
## POWERS (0.22.2): the AI uses every new power.  Godot --headless --path . --script res://tests/test_powers_ai.gd
## Exit code 0 = all passed. For each power, Standard vs Standard plays a few duel maps with that power in both
## seats' loadouts; the power must be cast at least once, and every cast must be one the Sim accepted (the AI
## never tries an illegal target: SeatAI only casts through Sim.cast, which validates). Prints casts per match.
## `-- maps=N` plays the first N duel maps (default 4).

const POWERS := {"quake": "map", "sever": "map", "backwash": "map", "fog": "map", "portal": "map", "sinkhole": "active", "evac": "active"}
var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _arg_maps() -> int:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("maps="):
			return int(str(a).substr(5))
	return 4


func _match(path: String, loadout: Dictionary, factions: Dictionary, seed_value: int, limit := 300.0) -> Sim:
	var m := MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, factions, seed_value, {}, {"A": loadout, "B": loadout})
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, "Standard"))
	while not sim.over and sim.time < limit:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	return sim


func _run() -> void:
	Rules.last_stand = false
	var duel := MapPool.battlefield().filter(func(p): return MapBuilder.load_map(p)["seats"].has("1v1"))
	duel = duel.slice(0, mini(_arg_maps(), duel.size()))
	for id in POWERS:
		var total := 0
		var per := []
		for i in range(duel.size()):
			var sim := _match(duel[i], {POWERS[id]: id}, {"A": "null", "B": "ember"}, 300 + i)
			var n := 0
			for e in sim.events:
				if e["type"] == "skill" and e["id"] == id:
					n += 1
			per.append(n)
			total += n
		check(total >= 1, "the AI casts %s (casts per map %s)" % [id, str(per)])
	# Core Meltdown, armed from the start of the trip: the EMBER AI still uses it
	var cm := 0
	for i in range(duel.size()):
		var sim := _match(duel[i], {}, {"A": "ember", "B": "ember"}, 400 + i)
		for e in sim.events:
			if e["type"] == "skill" and e["id"] == "core_meltdown":
				cm += 1
	check(cm >= 1, "the EMBER AI arms Core Meltdown (%d casts)" % cm)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
