extends SceneTree
## AI never builds a Monster Hub (Daniele 2026-11-13, "Yes, AI too"):
##   Godot --headless --path . --script res://tests/probe_no_hub.gd -- map=R-01-strait [mode=<first>] [lvl=Expert] [limit=600] [seed=7]
## Every seat is the AI; the match runs at a fixed step to the end (or `limit` s). Prints the relays that offer a hub, the
## structures built per kind, and HUBS BUILT (a hub placed by the map at the start is not counted).

func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return fallback


func _run() -> void:
	var path := "res://maps4/%s.json" % _arg("map", "R-01-strait")
	var m := MapBuilder.load_map(path)
	var mode := _arg("mode", str(m["seats"].keys()[0]))
	var seats := {}
	var teams := {}
	for s in m["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
		if typeof(s.get("team")) in [TYPE_INT, TYPE_FLOAT]:
			teams[s["seat"]] = int(s["team"])
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {}, int(_arg("seed", "7")), teams)
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, _arg("lvl", "Expert")))
	var offer := 0
	var start_hubs := {}
	for n in sim.nodes:
		if "monster_hub" in n["buildable"]:
			offer += 1
		if n["structure"] == "monster_hub":
			start_hubs[n["id"]] = true
	var built := {}
	var hubs := {}
	var seen := 0
	var dt := 1.0 / 30.0
	var limit := float(_arg("limit", "600"))
	while not sim.over and sim.time < limit:
		for ai in ais:
			ai.think(sim, dt)
		sim.step(dt)
		for i in range(seen, sim.events.size()):
			var e: Dictionary = sim.events[i]
			if e.get("type", "") == "build_done":
				built[str(e["kind"])] = int(built.get(str(e["kind"]), 0)) + 1
		seen = sim.events.size()
		sim.fx_events.clear()
		for n in sim.nodes:
			if (n["structure"] == "monster_hub" or n["build_kind"] == "monster_hub") and not start_hubs.has(n["id"]):
				hubs[n["id"]] = true
	print("PROBE map=%s mode=%s seats=%d t=%.0f over=%s relays_offering_hub=%d built=%s HUBS BUILT=%d" % [
			path.get_file(), mode, seats.size(), sim.time, sim.over, offer, built, hubs.size()])
	quit(0 if hubs.is_empty() else 1)
