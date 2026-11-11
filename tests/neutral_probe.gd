extends Node
## NEUTRAL probe (rules-neutral, Daniele 2026-11-11: "neutral nodes stop regenerating troops, and locals don't march to them
## until a player captured it"). Runs on any build (before / after):
##   1. SIM: every neutral vat / GooGat node on the map is beaten down to half its garrison at t=0, nobody plays; the sum of
##      the neutral garrisons (shown units) at 0 / 30 / 60 / 120 s.  NEUTRAL_SIM <map> t=<s> chipped=<sum> full=<sum>
##   2. MATCH: main.tscn 1v1 (human idle, rival AI), Engine.time_scale x4, 150 s of sim time. Every frame: Locals in a line
##      (or walking a march) to a node that is neutral right now (must be 0), each node's capture time and the time its first
##      Local walks after it.  NEUTRAL_LOCALS <map> ...  /  NEUTRAL_CAPTURE <map> node=<id> owner=<s> t=<s> first_local=<s>
##   Godot --path . res://tests/neutral_probe.tscn -- map=R-01 [secs=150]   (--headless: an off-screen window pauses the match)

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""


func _sim_part(code: String) -> void:
	var m := MapBuilder.load_map("res://maps4/" + _map_file(code))
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
	var chipped := []
	var full := []
	for n in s.nodes:
		if n["owner"] != "" or not (Sim.has_vat(n) or n["structure"] == "machinegoon"):
			continue
		if chipped.size() <= full.size():
			n["units"] = float(n["units"]) * 0.5
			chipped.append(n["id"])
		else:
			full.append(n["id"])
	var t := 0.0
	for mark in [0.0, 30.0, 60.0, 120.0]:
		while t < mark - 0.001:
			s.step(0.1)
			t += 0.1
		var c := 0.0
		var f := 0.0
		for id in chipped:
			c += float(s.nodes[id]["units"])
		for id in full:
			f += float(s.nodes[id]["units"])
		print("NEUTRAL_SIM %s t=%d chipped(%d nodes)=%.1f full(%d nodes)=%.1f regen=%s" % [code, int(mark), chipped.size(),
				Rules.shown_f(c), full.size(), Rules.shown_f(f), str(Rules.NEUTRAL_REGEN)])


func _run() -> void:
	var code := "R-01"
	var secs := 150.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			code = a.substr(4)
		elif a.begins_with("secs="):
			secs = float(a.substr(5))
	_sim_part(code)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file(code)}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	var wl: WorldLayer = inst.world_layer
	var tries := 0
	while (wl.locals == null or not wl.locals.placed or wl.sim == null) and tries < 900:
		await get_tree().process_frame
		tries += 1
	if wl.locals == null or not wl.locals.placed:
		print("NEUTRAL_LOCALS %s locals never placed (locals %s, sim %s, world t %.1f, tries %d)" % [code, str(wl.locals), str(wl.sim), wl._t, tries])
		get_tree().quit(1)
		return
	Engine.time_scale = 4.0
	var lc: WorldLocals = wl.locals
	var sim: Sim = wl.sim
	var captured := {}      # node id -> [owner, t]
	var first_local := {}   # node id -> t of the first Local in its line after the capture
	var bad_frames := 0
	var bad_max := 0
	var bad_nodes := {}
	var march_wait := {}
	var owner0 := {}
	for n in sim.nodes:
		owner0[n["id"]] = str(n["owner"])
	var frames := 0
	while sim.time < secs:
		await get_tree().process_frame
		frames += 1
		var bad := 0
		for k in lc.feeds:
			var f: Dictionary = lc.feeds[k]
			var nid := int(wl._tubes[int(f["tube"])]["id"])
			var n: Dictionary = sim.nodes[nid]
			var ln := (f["line"] as Array).size()
			if str(n["owner"]) == "":
				if ln > 0:
					bad += ln
					bad_nodes[nid] = true
				if int(k) >= WorldLocals.MARCH_KEY or int(f.get("march", 0)) > 0:
					march_wait[nid] = true
			elif owner0[nid] == "" and ln > 0 and not first_local.has(nid):
				first_local[nid] = sim.time
		for n in sim.nodes:
			if owner0[n["id"]] == "" and str(n["owner"]) != "" and not captured.has(n["id"]):
				captured[n["id"]] = [str(n["owner"]), sim.time]
		if bad > 0:
			bad_frames += 1
			bad_max = maxi(bad_max, bad)
	Engine.time_scale = 1.0
	print("NEUTRAL_LOCALS %s t=%.0f frames=%d frames_with_locals_to_neutral=%d max_locals_to_neutral=%d neutral_nodes_hit=%s marches_waiting_on_neutral=%s spawned=%d admitted=%d" % [
			code, sim.time, frames, bad_frames, bad_max, str(bad_nodes.keys()), str(march_wait.keys()), lc.spawned, lc.admitted])
	for id in captured:
		var fl: float = float(first_local.get(id, -1.0))
		print("NEUTRAL_CAPTURE %s node=%d owner=%s t=%.1f first_local=%s" % [code, id, captured[id][0], captured[id][1],
				("%.1f (+%.1f s)" % [fl, fl - float(captured[id][1])]) if fl >= 0.0 else "none yet"])
	get_tree().quit(0)
