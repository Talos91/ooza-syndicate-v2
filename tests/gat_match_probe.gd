extends SceneTree
## GooGat in play (demo-rules-pass): R-01, two Veteran AIs, 300 s; per GooGat every 10 s: owner, garrison (= ammo), shots
## fired, seconds firing, seconds firing while EMPTY (the trickle), steps with an enemy line in range but no shot.
##   Godot --headless --path . --script res://tests/gat_match_probe.gd

func _init() -> void:
	var m := MapBuilder.load_map("res://maps4/R-01-strait.json")
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 7)
	var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
	var gats := []
	for n in s.nodes:
		if n["structure"] == "machinegoon":
			gats.append(n["id"])
	var st := {}
	for id in gats:
		st[id] = {"fired": 0.0, "t_fire": 0.0, "t_empty_fire": 0.0, "missed": 0}
	var dt := 0.1
	var last := 0.0
	while s.time < 300.0 and not s.over:
		for ai in ais:
			ai.think(s, dt)
		s.step(dt)
		for id in gats:
			var n: Dictionary = s.nodes[id]
			if n["structure"] != "machinegoon":
				continue
			var sh: Dictionary = n.get("shot", {})
			var shot_now: bool = not sh.is_empty() and absf(float(sh["t"]) - s.time) < 0.001
			if shot_now:
				st[id]["fired"] += float(sh["kills"])
				st[id]["t_fire"] += dt
				if bool(sh.get("trickle", false)):
					st[id]["t_empty_fire"] += dt
			elif not s.is_disrupted(id) and not s._hordes_in_range(n, Rules.MACHINEGOON_RANGE).is_empty() and n["build_kind"] == "":
				st[id]["missed"] += 1
		if s.time - last >= 30.0:
			last = s.time
			for id in gats:
				var n: Dictionary = s.nodes[id]
				print("t %3.0f gat %d %-11s owner '%s' T%d garrison %5.1f/%d  fired %6.1f  firing %5.1f s (empty-trickle %5.1f s)  in-range-no-shot steps %d" % [s.time, id,
						n["structure"], n["owner"], n["tier"], n["units"], int(Rules.CAPS[n["tier"]]), st[id]["fired"], st[id]["t_fire"], st[id]["t_empty_fire"], st[id]["missed"]])
	print("end t %.0f over %s winner '%s'" % [s.time, s.over, s.winner])
	quit(0)
