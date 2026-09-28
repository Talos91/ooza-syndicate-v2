extends Node
## playtest-hud contact-sheet shots (2026-09-28, cousins playtest branch):
##   timeout 90 Godot --path . --resolution 1266x585 tests/playtest_hud_shots.tscn -- --shot=arrow --out=<dir>
##   timeout 90 Godot --path . --resolution 1266x585 tests/playtest_hud_shots.tscn -- --shot=halo --out=<dir>
##   timeout 90 Godot --path . --resolution 1266x585 tests/playtest_hud_shots.tscn -- --shot=relay --out=<dir>
##   timeout 90 Godot --path . --resolution 1266x585 tests/playtest_hud_shots.tscn -- --shot=pause --out=<dir> --tag=1266x585
##   timeout 90 Godot --path . --resolution 1136x640 tests/playtest_hud_shots.tscn -- --shot=pause --out=<dir> --tag=1136x640
## windowed only (feel_shots.gd's pattern): a fixed A-01 1v1, no AI, camera held. Saves <out>/hud_<shot>[_<tag>].png.

var main: Node3D
var shot := "arrow"
var out := "user://"
var tag := ""
var _t := 0.0
var _a := -1
var _done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	if DisplayServer.get_name() == "headless":
		print("SKIP playtest_hud_shots: needs a window")
		get_tree().quit(0)
		return
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", "res://maps4/A-01-orbital-nexus.json")
	main.set("demo", true)
	main.set("seed_value", 7)
	main.set("ai_level", "Standard")
	main.set("ff_to", 3.0)
	add_child(main)


func _process(dt: float) -> void:
	if main == null or not bool(main.get("started")) or _done:
		return
	_t += dt
	if _t < 0.4:
		return
	_done = true
	main.set("ais", [])
	main.set("demo", false)
	var sim: Sim = main.get("sim")
	if _a < 0:
		for n in sim.nodes:
			if n["owner"] == "A" and n["structure"] == "vat":
				_a = n["id"]
				break
	if _a < 0:
		print("playtest_hud_shots: no A vat found")
		get_tree().quit(1)
		return
	main.set("paused", true)
	match shot:
		"arrow":
			sim.nodes[_a]["units"] = 500.0            # comfortably over T1->T2's cost: the arrow shows
			await _save("arrow")
		"halo":
			sim.nodes[_a]["allies"]["B"] = sim.node_cap(sim.nodes[_a]) * 0.85   # tier 3
			var other := _second_a_node(sim)
			if other >= 0:
				sim.nodes[other]["allies"]["B"] = sim.node_cap(sim.nodes[other]) * 0.4   # tier 2, elsewhere
			await _save("halo")
		"relay":
			var r := _relay_node(sim)
			if r >= 0:
				sim.nodes[r]["relay_cd"] = 0.0
				sim.nodes[r]["relay_phase"] = ""
				main.set("scenario_focus", sim.nodes[r]["pos"])
				main.set("scenario_zoom", 18.0)
				main.call("_fit_camera")
			await get_tree().process_frame
			await _save("relay")
		"pause":
			var hud = main.get("hud")
			hud.call("_pause_settings")
			await get_tree().process_frame
			await _save("pause" + ("_" + tag if tag != "" else ""))
	get_tree().quit(0)


func _second_a_node(sim: Sim) -> int:
	for n in sim.nodes:
		if n["owner"] == "A" and n["id"] != _a:
			return n["id"]
	return -1


func _relay_node(sim: Sim) -> int:
	for n in sim.nodes:
		if n["relay"] != "" and n["owner"] == "A":
			return n["id"]
	for n in sim.nodes:                                   # no owned relay on A-01: take any and claim it
		if n["relay"] != "":
			n["owner"] = "A"
			return n["id"]
	return -1


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/hud_%s.png" % [out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path)
