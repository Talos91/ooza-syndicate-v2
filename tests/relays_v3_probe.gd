extends SceneTree
## RELAYS 3.0 ROUND 3 probe (a dev tool, not a suite): the numbers behind the round-3 proposals on the 🗺️ test maps.
##   Godot --headless --path . --script res://tests/relays_v3_probe.gd
## FERRY (P-01, node 3): sends of 10 / 25 / 50 / 100 shown across the moving bridge at 40 moments spread over its cycle -
## how many cross (mean / min / max) - for today's clock, two timing variants (a quicker clock, a kinder one), and today's
## clock with the owner's AI HOLD (round 3). The variants are injected as the deck's cached cycle (Sim.ferry_cycle_e), so
## nothing in Rules changes. CONVEYOR (P-02): a 50 send along the belt chain with / against the flow and with no flow.
## LAUNCHER (P-03, pad 6): a 50 line through the armed pad - caught, last body in the air, first landing.


func _sim(code: String) -> Sim:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			var m := MapBuilder.load_map("res://maps4/" + f)
			var seats := {}
			for st in m["seats"]["1v1"]:
				seats[int(st["node"])] = str(st["seat"])
			var s := Sim.new()
			s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
			return s
	return null


func _cycle(s: Sim, id: int, slide: float, away: float, survive: float) -> Dictionary:
	## Sim.ferry_cycle's formula with other numbers, cached into the node's proto (what ferry_cycle_e reads first).
	var cross: float = s.ferry_cycle(id)["cross"]
	var moving := 2.0 * slide + away
	var open := (cross + survive * moving) / (1.0 - survive)
	var c := {"open": open, "slide": slide, "away": away, "half": open + moving, "period": 2.0 * (open + moving), "cross": cross,
			"gap": s.ferry_cycle(id)["gap"]}
	s.nodes[id]["proto"]["cycle"] = c
	return c


func _ferry_run(variant: Array, shown: int, k: int, hold: bool) -> float:
	var s := _sim("P-01")
	var c := _cycle(s, 3, variant[1], variant[2], variant[3])
	s.time = float(c["period"]) * float(k) / 40.0
	s.nodes[3]["owner"] = "A"
	s.nodes[3]["units"] = float(shown) * Rules.SCALE
	s.nodes[4]["owner"] = "A"
	var h := s.send(3, 4, 1.0)
	if h.is_empty():
		return -1.0
	var ai := SeatAI.new("A", 2.0, "Standard")
	var t := 0.0
	while t < 40.0:
		if hold and s.nodes[3]["relay_phase"] == "" and s.nodes[3]["relay_cd"] <= 0.0 and ai._proto_fire(s, s.nodes[3]):
			s.fire_relay(3)
		s.step(0.05)
		t += 0.05
		for e in s.events:
			if e["type"] == "ferry_cross" and int(e["node"]) == 3 and int(e["hid"]) == int(h["id"]):
				return float(e["ok"]) / maxf(float(e["ok"]) + float(e["fell"]), 0.001)
	return -1.0


func _ferry() -> void:
	var base := _sim("P-01")
	var c0 := base.ferry_cycle(3)
	var cfg: Dictionary = Rules.RELAYS_PROTO["ferry"]
	print("FERRY P-01 node 3, deck %.1f m, crossing %.2f s; today: in line %.2f s, slide %.1f, away %.1f, period %.2f s; hold %.0f s, cooldown %.0f s"
			% [c0["gap"], c0["cross"], c0["open"], c0["slide"], c0["away"], c0["period"], cfg["hold"], cfg["cooldown"]])
	var variants := [
		["today (round 2 clock)", float(cfg["slide"]), float(cfg["away"]), float(cfg["survive"]), false],
		["today + owner HOLD (AI)", float(cfg["slide"]), float(cfg["away"]), float(cfg["survive"]), true],
		["quick clock: slide 0.6, away 0.3", 0.6, 0.3, float(cfg["survive"]), false],
		["kinder: survive 0.65", float(cfg["slide"]), float(cfg["away"]), 0.65, false],
	]
	for v in variants:
		var cv := _cycle(_sim("P-01"), 3, v[1], v[2], v[3])
		print("  %-34s in line %.2f s, period %.2f s" % [v[0], cv["open"], cv["period"]])
		for shown in [10, 25, 50, 100]:
			var fr := []
			for k in range(40):
				var x := _ferry_run(v, shown, k, v[4])
				if x >= 0.0:
					fr.append(x)
			fr.sort()
			var mean := 0.0
			for x in fr:
				mean += x
			mean /= maxf(fr.size(), 1.0)
			var spread := 0.0                               # mean distance from the mean: how much the timing matters
			for x in fr:
				spread += absf(x - mean)
			spread /= maxf(fr.size(), 1.0)
			print("    send %3d: crossed mean %3.0f %%  min %3.0f %%  max %3.0f %%  timing spread +-%2.0f %%  (%d runs)" % [shown,
					mean * 100.0, fr[0] * 100.0, fr[-1] * 100.0, spread * 100.0, fr.size()])


func _conveyor() -> void:
	print("CONVEYOR P-02 node 7, with x%.2f, against x%.2f" % [Rules.RELAYS_PROTO["conveyor"]["with"], Rules.RELAYS_PROTO["conveyor"]["against"]])
	for run in [["with the flow", 0, 1, false], ["against the flow", 1, 0, false], ["no flow", 0, 1, true], ["no flow (back)", 1, 0, true]]:
		var s := _sim("P-02")
		var a: int = run[1]
		var b: int = run[2]
		s.nodes[a]["owner"] = "A"
		s.nodes[a]["units"] = 50.0 * Rules.SCALE
		s.nodes[b]["owner"] = "A"
		if run[3]:
			s.nodes[7]["relay_phase"] = "moving"
			s.nodes[7]["relay_t"] = 999.0
			s.nodes[7]["relay_move"] = 999.0
			s.nodes[7]["relay_anim"] = {"progress": 0.0}
		var h := s.send(a, b, 1.0)
		var route: Array = h["route"]
		var t := 0.0
		var head := -1.0
		while t < 60.0 and h in s.hordes:
			s.step(0.02)
			t += 0.02
			if head < 0.0 and h["state"] == "absorb":
				head = t
		print("  %-17s %s: head in at %.2f s, last body in at %.2f s (path %.1f m)" % [run[0], str(route), head, t, float(h["L"])])


func _launcher() -> void:
	var cfg: Dictionary = Rules.RELAYS_PROTO["launcher"]
	print("LAUNCHER P-03 pad 6: pour x%.1f, flight %.1f s, land %.1f s, aim cycle %.0f s, armed %.0f s, misfire %.0f s" % [cfg["pour"],
			cfg["flight"], cfg["land"], cfg["cycle"], cfg["armed"], cfg["misfire"]])
	var s := _sim("P-03")
	var ab := []
	for la in s.adj[6]:
		for lb in s.adj[6]:
			if ab.is_empty() and int(la[0]) != int(lb[0]) and 6 in s.find_route(int(la[0]), int(lb[0])):
				ab = [int(la[0]), int(lb[0])]
	s.nodes[6]["owner"] = "A"
	s.nodes[ab[0]]["owner"] = "A"
	s.nodes[ab[0]]["units"] = 50.0 * Rules.SCALE
	s.fire_relay(6)
	s.nodes[6]["relay_t"] = 0.0
	s.step(0.05)
	var h := s.send(ab[0], ab[1], 1.0)
	var t := 0.0
	var caught := -1.0
	var aired := -1.0
	var landed := -1.0
	while t < 20.0:
		s.step(0.02)
		t += 0.02
		if caught < 0.0 and h.has("launch"):
			caught = t
		if caught >= 0.0 and aired < 0.0 and not (h in s.hordes):
			aired = t
		if landed < 0.0 and s.flights.any(func(f): return f.get("landed", false)):
			landed = t
	print("  a 50 line %s -> %s through the armed pad: caught at %.2f s, all in the air %.2f s later, first landing %.2f s after the catch"
			% [ab[0], ab[1], caught, aired - caught, landed - caught])


func _init() -> void:
	_ferry()
	_conveyor()
	_launcher()
	quit(0)
