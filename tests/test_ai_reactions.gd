extends SceneTree
## AI REACTIONS (ai-reactions 2026-11-18): Godot --headless --path . --script res://tests/test_ai_reactions.gd [-- secs=300]
## Plays real AI matches (1v1 G-05 / G-01, FFA4 on A-01; Standard AIs with their builds, so skills are cast) for `secs` of match time
## with the AI screens fed exactly as in play (sim.captured -> on_capture, sim.events, the share every 0.5 s), then checks:
## - THROTTLE: on every screen two reaction starts are >= AiScreens.GAP s apart (the end / an out excepted), no spam;
## - LIVE: the match triggers several different reactions on both screens (wired to real events, not only dev flags);
## - FONT AUDIT: every plate line / mood word fits the plate at 12.5 pt (designer 12: never shrunk, swap the word).
## - TABLE: >= 10 reactions, every faction has a line for each, every layer texture and box exists.
## Exit code 0 = all passed.

var failures := 0


class StubHud:
	extends RefCounted
	var sim: Sim
	var human := "A"
	var pause_panel = null

	func _seat_groups() -> Array:
		var g := [[human]]
		for s in sim.factions.keys():
			if s != human:
				g.append([s])
		return g

	func _seat_out(seat: String) -> bool:
		return sim.is_out(seat)


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(k + "="):
			return a.substr(k.length() + 1)
	return d


func _match(path: String, mode: String, factions: Dictionary, secs: float) -> Dictionary:
	var m := MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.ai_builds = true
	sim.setup(m, MapBuilder.layout(m), seats, factions, 11)
	var hud := StubHud.new()
	hud.sim = sim
	var scr := AiScreens.new()
	root.add_child(scr)
	scr.set_process(false)                         # driven by hand at the sim's step
	scr.setup(hud)
	sim.captured.connect(func(nid, new_owner, old): scr.on_capture(new_owner, old, float(sim.nodes[nid]["units"])))
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, "Standard"))
	while sim.time < secs and not sim.over:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
		scr._process(0.1)
	for k in range(30):                              # the end plays out
		scr._process(0.1)
	var out := {"log": scr.log_.duplicate(), "over": sim.over, "t": sim.time, "winner": sim.winner}
	scr.queue_free()
	return out


func _check_log(tag: String, r: Dictionary) -> void:
	var log_: Array = r["log"]
	var worst := 999.0
	var ids := [{}, {}]
	var n := [0, 0]
	var last := [-99.0, -99.0]
	for e in log_:
		var i: int = e[1]
		n[i] += 1
		ids[i][e[2]] = true
		if int(AiScreens.REACT[e[2]]["prio"]) < 6:
			worst = minf(worst, float(e[0]) - float(last[i]))
		last[i] = float(e[0])
	print("  %s: %.0f s%s, starts L %d / R %d, worst gap %.2f s, L %s, R %s" % [tag, r["t"], " (over, winner %s)" % r["winner"] if r["over"] else "",
			n[0], n[1], worst, ",".join(ids[0].keys()), ",".join(ids[1].keys())])
	check(worst >= AiScreens.GAP - 0.051, "%s THROTTLE: >= %.1f s between two starts on a screen (worst %.2f s)" % [tag, AiScreens.GAP, worst])
	var minutes := maxf(float(r["t"]) / 60.0, 1.0)
	check(n[0] / minutes <= 30.0 and n[1] / minutes <= 30.0, "%s no spam: <= 30 starts a minute per screen (L %.1f, R %.1f)" % [tag, n[0] / minutes, n[1] / minutes])
	check(ids[0].size() >= 4 and ids[1].size() >= 4, "%s LIVE: >= 4 different reactions on each screen (L %d, R %d)" % [tag, ids[0].size(), ids[1].size()])


func _run() -> void:
	var secs := float(_arg("secs", "300"))
	# TABLE
	check(AiScreens.REACT.size() >= 10, "TABLE: %d reactions (>= 10)" % AiScreens.REACT.size())
	for f in ["vex", "null", "bloom", "ember", "solar"]:
		var P: Dictionary = AiScreens.PERSONA[f]
		var miss := AiScreens.REACT.keys().filter(func(k): return not P["lines"].has(k))
		check(miss.is_empty(), "TABLE: %s has a line for every reaction %s" % [f, miss])
		var tex := ["_glow", "_body", "_eyes", "_shut"].filter(func(x): return AiScreens._layer(f + x) == null or AiScreens._box(f + x).size.x <= 0)
		check(tex.is_empty() and AiScreens._box("glitch@" + f).size.x > 0, "LAYERS: %s textures + boxes %s" % [f, tex])
	# FONT AUDIT (designer 12 FIX): every plate line + mood word fits the plate at 12.5 pt, never shrunk
	var font := HudLab.bold()
	var room := AiScreens.plate_room_pt()
	var over := []
	var widest := 0.0
	var words := []
	for f in AiScreens.PERSONA:
		words.append_array(AiScreens.PERSONA[f]["lines"].values())
	for m in AiScreens.MOODS:
		words.append(AiScreens.MOODS[m][1])
	for w in words:
		var px := font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, int(AiScreens.PLATE_FONT_PT * 10.0)).x / 10.0
		widest = maxf(widest, px)
		if px > room:
			over.append("%s %.1f" % [w, px])
	check(over.is_empty(), "FONT AUDIT: %d lines at %.1f pt fit the %.1f pt plate (widest %.1f) %s" % [words.size(), AiScreens.PLATE_FONT_PT, room, widest, over])
	check(AiScreens._layer("glass") != null and AiScreens._layer("frame") != null and AiScreens._layer("glitch") != null, "LAYERS: glass, frame, glitch")
	# LIVE matches
	_check_log("1v1 G-05", _match("res://maps4/G-05-catapult-bay.json", "1v1", {"A": "vex", "B": "null"}, secs))
	_check_log("1v1 G-01", _match("res://maps4/G-01-gate.json", "1v1", {"A": "bloom", "B": "solar"}, secs))
	_check_log("FFA4 A-01", _match("res://maps4/A-01-orbital-nexus.json", "FFA4", {"A": "solar", "B": "ember", "C": "bloom", "D": "null"}, secs))
	print("ALL PASSED (0 failed)" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
