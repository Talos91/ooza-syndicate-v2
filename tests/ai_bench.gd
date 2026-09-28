extends SceneTree
## AI think cost and determinism (perf pass, 2026-09-28):
##   Godot --headless --path . --script res://tests/ai_bench.gd -- [lvl=Expert] [map=M-39-circuit-warren] [mode=2v2]
##       [dt=0.016667] [limit=420] [seed=7] [log=user://ai_orders.txt]
## Every seat is the AI at `lvl`; the match runs at a fixed step. Prints the think cost (per frame: the sum of every
## seat's think that frame; worst / p99 / mean over frames with a think; frames where two seats thought together),
## the time per think phase (SeatAI.phases), Sim.step's cost, and a hash of the whole event log (every send, build,
## cast, relay fire... in order): the same seed must give the same hash before and after an AI refactor that keeps
## the decisions. `log=` also writes the event log, one line per event, to diff.

func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return fallback


func _run() -> void:
	var lvl := _arg("lvl", "Expert")
	var path := "res://maps4/%s.json" % _arg("map", "M-39-circuit-warren")
	var mode := _arg("mode", "2v2")
	var dt := float(_arg("dt", str(1.0 / 60.0)))
	var limit := float(_arg("limit", "420"))
	var m := MapBuilder.load_map(path)
	var seats := {}
	var teams := {}
	for s in m["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
		if mode != "ffa" and s.has("team"):
			teams[s["seat"]] = int(s["team"])
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {}, int(_arg("seed", "7")), teams)
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, lvl))
	SeatAI.phases_on = true
	SeatAI.phases = {}
	var frame_us := PackedInt32Array()
	var single_max := 0
	var together := 0
	var step_us := 0
	var step_max := 0
	var frames := 0
	while not sim.over and sim.time < limit:
		var total := 0
		var n := 0
		for ai in ais:
			var had := float(ai.get("_t"))
			var t0 := Time.get_ticks_usec()
			ai.think(sim, dt)
			var us := Time.get_ticks_usec() - t0
			if float(ai.get("_t")) < had + dt * 0.5:  # it thought (its clock was reset)
				n += 1
				total += us
				single_max = maxi(single_max, us)
		if n > 0:
			frame_us.append(total)
		if n > 1:
			together += 1
		var t1 := Time.get_ticks_usec()
		sim.step(dt)
		var su := Time.get_ticks_usec() - t1
		step_us += su
		step_max = maxi(step_max, su)
		sim.fx_events.clear()
		frames += 1
	var sorted := Array(frame_us)
	sorted.sort()
	var sum := 0
	for v in sorted:
		sum += v
	print("ai_bench %s %s %s dt %.4f: %d frames, sim time %.1f, over %s, winner '%s'" % [path.get_file(), mode, lvl, dt, frames,
			sim.time, sim.over, sim.winner])
	print("think frames %d: worst %.2f ms, p99 %.2f ms, mean %.3f ms; worst single think %.2f ms; frames with 2+ thinks %d" % [
			sorted.size(), sorted[-1] / 1000.0, sorted[int(sorted.size() * 0.99)] / 1000.0, sum / 1000.0 / maxf(sorted.size(), 1.0),
			single_max / 1000.0, together])
	var names := SeatAI.phases.keys()
	names.sort_custom(func(a, b): return SeatAI.phases[a][0] > SeatAI.phases[b][0])
	var line := "phases (total ms / worst ms):"
	for k in names:
		line += " %s %.0f/%.2f" % [k, SeatAI.phases[k][0] / 1000.0, SeatAI.phases[k][1] / 1000.0]
	print(line)
	print("sim.step mean %.3f ms, worst %.2f ms" % [step_us / 1000.0 / maxf(frames, 1.0), step_max / 1000.0])
	var log := PackedStringArray()
	for e in sim.events:
		log.append(str(e))
	var text := "\n".join(log)
	var casts := 0
	for ai in ais:
		casts += int(ai.casts)
	print("events %d, casts %d, log hash %s" % [sim.events.size(), casts, text.sha256_text().substr(0, 16)])
	var out := _arg("log", "")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	quit(0)
