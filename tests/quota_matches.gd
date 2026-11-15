extends SceneTree
## LAST STAND = QUOTA study (demo prototype): AI-vs-AI 1v1 matches on the G pool, quota ON (and the same seeds OFF as the
## baseline). Godot --headless --path . --script res://tests/quota_matches.gd -- [n=20] [lvl=Standard] [off=1] [dt=0.1]
## One line per match: map, seed, mode, end time, winner, how it ended, quota A-B, owned launches, neutral launches.

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return fallback


func _initialize() -> void:
	_run.call_deferred()


func _match(path: String, seed_v: int, lvl: String, dt: float) -> Dictionary:
	var m := MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	var facs := {}
	var pool := ["null", "ember"]
	var k := 0
	for id in seats:
		facs[seats[id]] = pool[(k + seed_v) % 2]
		k += 1
	sim.setup(m, MapBuilder.layout(m), seats, facs, seed_v)
	var ais := []
	for s in seats.values():
		ais.append(SeatAI.new(s, 2.5, lvl))
	while not sim.over and sim.time < Rules.MATCH_HARD_END + 5.0:
		for ai in ais:
			ai.think(sim, dt)
		sim.step(dt)
		sim.fx_events.clear()
	var owned := 0
	var neutral := 0
	for e in sim.events:
		if e["type"] == "launch":
			if str(e["seat"]) != "":
				owned += 1
			else:
				neutral += 1
	var how := "draw" if sim.winner == "" else ("quota-" + sim.quota_reason if sim.quota_reason != "" else ("elimination" if sim.time < Rules.MATCH_HARD_END - 0.01 else "7:00"))
	var names: Array = seats.values()
	names.sort()
	return {"t": sim.time, "winner": sim.winner, "how": how, "qa": sim.quota_of(names[0]), "qb": sim.quota_of(names[1]),
			"owned": owned, "neutral": neutral, "ls": sim.last_stand_active}


func _run() -> void:
	var n := int(_arg("n", "20"))
	var lvl := _arg("lvl", "Standard")
	var dt := float(_arg("dt", "0.1"))
	var maps: Array = []
	for code in MapPool.PROTO:
		for f in DirAccess.get_files_at("res://maps4"):
			if f.begins_with(code + "-") and f.ends_with(".json"):
				maps.append("res://maps4/" + f)
	var modes := [true, false] if _arg("off", "1") == "1" else [true]
	for i in range(n):
		var path: String = maps[i % maps.size()]
		var seed_v := 100 + i
		for q in modes:
			Rules.quota = q
			var t0 := Time.get_ticks_msec()
			var r := _match(path, seed_v, lvl, dt)
			print("MATCH|%s|%d|%s|%.1f|%s|%s|%d-%d|%d|%d|%d ms" % [path.get_file().get_basename(), seed_v, "quota" if q else "off",
					r["t"], r["winner"] if r["winner"] != "" else "-", r["how"], r["qa"], r["qb"], r["owned"], r["neutral"],
					Time.get_ticks_msec() - t0])
	print("QUOTA_MATCHES DONE")
	quit(0)
