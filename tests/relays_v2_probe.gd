extends SceneTree
## RELAYS 3.0 ROUND 2 probe (a dev tool, not a suite): the numbers behind the round-2 tuning on the 🗺️ test maps.
##   Godot --headless --path . --script res://tests/relays_v2_probe.gd
## FERRY (P-01): sends of 10 / 25 / 50 / 100 shown across the moving bridge at 40 moments spread over its cycle - how
## many cross (mean / min / max). CONVEYOR (P-02): a 50 send along the belt chain with the flow, against it, and with the
## flow switched off (the belt flipping all the time) - when the head arrives and when the last body is in.


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


func _ferry() -> void:
	var probe := _sim("P-01")
	var c := probe.ferry_cycle(3)
	print("FERRY P-01 node 3, deck %.1f m: crossing %.2f s, in line %.2f s, slide %.1f s, away %.1f s, half %.2f s, period %.2f s"
			% [c["gap"], c["cross"], c["open"], c["slide"], c["away"], c["half"], c["period"]])
	for shown in [10, 25, 50, 100]:
		var fr := []
		var leak := 0.0                                 # the worst |crossed + fell - sent| / sent (the tally adds up)
		for k in range(40):
			var s := _sim("P-01")
			s.time = float(c["period"]) * float(k) / 40.0
			s.nodes[3]["owner"] = "A"
			s.nodes[3]["units"] = float(shown) * Rules.SCALE
			s.nodes[4]["owner"] = "A"                   # (an own pier: no fight at the far end)
			var h := s.send(3, 4, 1.0)
			if h.is_empty():
				continue
			var t := 0.0
			var done := {}
			while t < 40.0 and done.is_empty():
				s.step(0.05)
				t += 0.05
				for e in s.events:
					if e["type"] == "ferry_cross" and int(e["node"]) == 3 and int(e["hid"]) == int(h["id"]):
						done = e
			if done.is_empty():
				continue
			var sent: float = float(done["ok"]) + float(done["fell"])
			fr.append(float(done["ok"]) / maxf(sent, 0.001))
			leak = maxf(leak, absf(sent - float(shown) * Rules.SCALE) / (float(shown) * Rules.SCALE))
		fr.sort()
		var mean := 0.0
		for x in fr:
			mean += x
		mean /= maxf(fr.size(), 1.0)
		print("  send %3d shown: crossed mean %.0f %%  min %.0f %%  max %.0f %%  (%d runs; tally off by at most %.1f %%)" % [shown,
				mean * 100.0, fr[0] * 100.0, fr[-1] * 100.0, fr.size(), leak * 100.0])


func _conveyor() -> void:
	var probe := _sim("P-02")
	var belt := []
	for i in probe.controlled_edges(7):
		belt.append("%d-%d" % [probe.edges[i]["a"], probe.edges[i]["b"]])
	print("CONVEYOR P-02 node 7 belts %s (flow A->B), with x%.1f, against x%.1f" % [str(belt), Rules.RELAYS_PROTO["conveyor"]["with"],
			Rules.RELAYS_PROTO["conveyor"]["against"]])
	for run in [["with the flow", 0, 1, false], ["against the flow", 1, 0, false], ["no flow", 0, 1, true], ["no flow (back)", 1, 0, true]]:
		var s := _sim("P-02")
		var a: int = run[1]
		var b: int = run[2]
		s.nodes[a]["owner"] = "A"
		s.nodes[a]["units"] = 50.0 * Rules.SCALE
		s.nodes[b]["owner"] = "A"
		if run[3]:                                      # the belt held mid-flip the whole run: no flow
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


func _init() -> void:
	_ferry()
	_conveyor()
	quit(0)
