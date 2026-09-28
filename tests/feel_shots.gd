extends Node
## Match-feel contact sheet (2026-09-28): stages the moments the pass changed and screenshots them (windowed):
##   timeout 120 Godot --path . tests/feel_shots.tscn -- --shot=fight --out=<dir> [--window=1688x780 --mobile --safe-insets=59,0,59,21]
##   timeout 120 Godot --path . tests/feel_shots.tscn -- --shot=laststand --out=<dir> [...]
## fight: A-01 1v1, no AI; seat A's line pours into a rival node next to one of A's own, and a line from another rival
##   neighbour pours into that node of A's. The Sim is then held (main.paused) with the counts set so the contest rings' sweeps settle at
##   25 % (A's attack) / 60 % (the rival's), then 75 % / 30 %: feel_<tag>_fight25.png / _fight75.png (whole map) and
##   _close25.png / _close75.png (the camera on the two nodes). YOUR node shows the under-attack cue.
## laststand: A-01, every seat the AI, fast-forwarded into the Last Stand's first warning: feel_<tag>_laststand.png.
## <tag> = phone when --mobile is given, else desktop.

var main: Node3D
var shot := "fight"
var out := "user://"
var tag := "desktop"
var _t := 0.0
var _stage := 0
var _a := -1        # A's node under attack
var _n := -1        # the rival node A attacks
var _m := -1        # the rival node attacking _a
var _ha := {}       # A's line into _n
var _hb := {}       # the rival's line into _a


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--mobile":
			tag = "phone"
	if DisplayServer.get_name() == "headless":
		print("SKIP feel_shots: needs a window")
		get_tree().quit(0)
		return
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", "res://maps4/A-01-orbital-nexus.json")
	main.set("demo", true)
	main.set("seed_value", 7)
	main.set("ai_level", "Standard")
	if shot == "laststand":
		main.set("ff_to", Rules.LAST_STAND_TIME + 3.0)
	else:
		main.set("ff_to", 45.0)
	add_child(main)


func _process(dt: float) -> void:
	if main == null or not bool(main.get("started")):
		return
	_t += dt
	if shot == "laststand":
		if _t > 2.5 and _stage == 0:
			_stage = 1
			await _save("laststand")
			get_tree().quit(0)
		return
	var sim: Sim = main.get("sim")
	match _stage:
		0:
			if _t < 0.5:
				return
			main.set("ais", [])
			main.set("demo", false)
			_pick(sim)
			if _a < 0:
				print("feel_shots: no A node next to a rival node")
				get_tree().quit(1)
				return
			for id in [_n, _m]:
				sim.nodes[id]["owner"] = "B"
				sim.nodes[id]["units"] = 400.0
			sim.nodes[_a]["units"] = 400.0
			_ha = sim.send(_a, _n, 0.5)
			_hb = sim.send(_m, _a, 0.5)
			print("feel_shots: A node %d attacks rival node %d; rival node %d attacks it" % [_a, _n, _m])
			_stage = 1
		1:                                               # both lines on their way: wait until both pour in
			var ready: bool = not _ha.is_empty() and not _hb.is_empty() and _ha.get("state", "") == "absorb" and _hb.get("state", "") == "absorb"
			if ready or _t > 30.0:
				main.set("paused", true)
				_hold(sim, 0.25, 0.6)
				_stage = 2
				_t = 0.0
		2:
			if _t > 2.0:
				_stage = 3
				await _save("fight25")
				_close(true)
				_t = 0.0
		3:
			if _t > 1.0:
				_stage = 4
				await _save("close25")
				_close(false)
				_hold(sim, 0.75, 0.3)
				_t = 0.0
		4:
			if _t > 2.0:
				_stage = 5
				await _save("fight75")
				_close(true)
				_t = 0.0
		5:
			if _t > 1.0:
				_stage = 6
				await _save("close75")
				get_tree().quit(0)


func _pick(sim: Sim) -> void:
	## An A node with two other (non-relay) neighbours, made the rival's (B): A attacks one, the other attacks A's.
	var best := INF
	for n in sim.nodes:
		if n["owner"] != "A":
			continue
		var others := []
		for link in sim.adj[n["id"]]:
			var o: Dictionary = sim.nodes[link[0]]
			if o["owner"] != "A" and o["relay"] == "":
				others.append(o["id"])
		if others.size() >= 2 and (n["pos"] as Vector3).length() < best:
			best = (n["pos"] as Vector3).length()
			_a = n["id"]
			_n = others[0]
			_m = others[1]


func _hold(sim: Sim, p_attack: float, p_defend: float) -> void:
	## The counts that put the sweeps at these shares: A's line vs _n's garrison, the rival's line vs _a's.
	var combat: CombatFx = main.get("combat")
	for spec in [[_ha, _n, p_attack], [_hb, _a, p_defend]]:
		var h: Dictionary = spec[0]
		var n: Dictionary = sim.nodes[spec[1]]
		var p: float = spec[2]
		n["units"] = 150.0
		var r := combat._kill_ratio(n, str(h["owner"]))
		h["units"] = p * 150.0 / ((1.0 - p) * maxf(r, 0.001))
	# the flicker's bright step (the Sim's clock is held too)
	sim.time = floor(sim.time) + 0.05


func _close(on: bool) -> void:
	var sim: Sim = main.get("sim")
	main.set("scenario_focus", ((sim.nodes[_a]["pos"] * 2.0 + sim.nodes[_n]["pos"] + sim.nodes[_m]["pos"]) as Vector3) / 4.0 if on else Vector3.INF)
	main.set("scenario_zoom", 55.0)
	main.call("_fit_camera")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/feel_%s_%s.png" % [out, tag, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path)
