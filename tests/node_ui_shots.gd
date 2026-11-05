extends Node
## NODE UI shots (Alpha 24 step 4, 🧩 ui-node): stages the per-node interface on one map and saves phone-size frames.
## Windowed only. No AI: the rival seats are cleared so the staged states hold still.
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/node_ui_shots.tscn --
##       [map=A-02] [faction=vex] [window=812x375] [shots=<dir>] [prefix=<name>]
## Frames: board (marks only), vat (your vat's pie), relay (a relay's pie), enemy (an enemy node), send (aiming a send),
## hold (dragged back onto the origin), captured (a vat just taken: armour climbing back).

const MAIN := "res://main.tscn"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("node_ui_shots: windowed only")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").begins_with(name + "="):
			return a.trim_prefix("--").substr(name.length() + 1)
	return def


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await get_tree().create_timer(0.6).timeout          # the pie deals out over ~0.3 s
	await _frames(2)
	await RenderingServer.frame_post_draw
	var dir := _arg("shots", "user://node_ui_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s%s.png" % [dir, _arg("prefix", ""), name]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


func _run() -> void:
	var wh := _arg("window", "812x375").split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await _frames(2)
	var code := _arg("map", "A-02")
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	var m := MapBuilder.load_map(path)
	var main_script = load("res://scripts/main.gd")
	main_script.relaunch = {"faction": _arg("faction", "vex"), "mode": str(m["modes"][0]), "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.mobile = true
	get_tree().root.add_child(inst)
	var t0 := Time.get_ticks_msec()
	while not bool(inst.get("started")) and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _frames(10)
	(inst.get("ais") as Array).clear()
	var sim = inst.get("sim")
	var hud = inst.get("hud")
	var human: String = inst.get("HUMAN")
	var cam: Camera3D = inst.get("cam")
	# ---- stage: your home vat T2 ready to upgrade, a relay you own, a vat you just took, an ally share, an enemy node
	var mine := -1
	var relay := -1
	var enemy := -1
	var spare: Array = []
	for n in sim.nodes:
		if n.get("node_kind", "") == "junction":
			continue
		if n["relay"] != "" and relay < 0:
			relay = n["id"]
		elif n["owner"] == human and mine < 0:
			mine = n["id"]
		elif n["owner"] != "" and n["owner"] != human and enemy < 0:
			enemy = n["id"]
		elif n["owner"] == "" and n["relay"] == "":
			spare.append(n["id"])
	var mn: Dictionary = sim.nodes[mine]
	mn["tier"] = 2
	mn["units"] = float(sim.upgrade_cost(mn)) + 40.0
	if relay >= 0:
		sim.nodes[relay]["owner"] = human
		sim.nodes[relay]["units"] = 120.0
	var took := -1
	if not spare.is_empty():
		took = int(spare[0])
		var tn: Dictionary = sim.nodes[took]
		tn["owner"] = human
		tn["structure"] = "vat"
		tn["tier"] = 3
		tn["units"] = 60.0
		sim._reset_armour(tn)                              # a capture: armour back to 1.0, climbing to T3's
		tn["armour"] = 1.0
		if spare.size() > 1:
			var an: Dictionary = sim.nodes[int(spare[1])]
			an["owner"] = human
			an["units"] = 80.0
			an["structure"] = "machinegoon"
			an["tier"] = 2
	# the skill cards in three states: ACTIVE ready, MAP half charged, ULTIMATE 60 %
	if sim.skill_cd.has(human):
		sim.skill_cd[human]["active"] = 0.0
		var lo: Dictionary = sim.loadouts.get(human, {})
		if lo.has("map") and Rules.SKILLS.has(lo["map"]):
			sim.skill_cd[human]["map"] = float(Rules.SKILLS[lo["map"]]["cd"]) * 0.5
		sim.ult_charge[human] = 0.6
	for n in sim.nodes:
		MapBuilder.apply_owner(inst.get("vis")[n["id"]]["parts"], n["owner"])
	await _frames(20)
	await _shot("board")
	hud.inspect(mine, cam)
	await _shot("vat")
	hud.close_inspector()
	if relay >= 0:
		hud.inspect(relay, cam)
		await _shot("relay")
		hud.close_inspector()
	if enemy >= 0:
		hud.inspect(enemy, cam)
		await _shot("enemy")
		hud.close_inspector()
	if spare.size() > 2:                                  # a capture as it happens: the burst in your colour
		var cn: Dictionary = sim.nodes[int(spare[2])]
		cn["owner"] = human
		cn["units"] = 12.0
		MapBuilder.apply_owner(inst.get("vis")[cn["id"]]["parts"], human)
		await get_tree().create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%scapture.png" % [_arg("shots", "user://node_ui_shots"), _arg("prefix", "")])
		print("shot capture")
	if took >= 0:
		hud.inspect(took, cam)
		await _shot("captured")
		hud.close_inspector()
	# ---- a send being aimed at the enemy node (the drag preview as the game draws it on a mouse move)
	var target := enemy if enemy >= 0 else took
	if target >= 0:
		inst.set("drag_from", mine)
		inst.set("_drag_out", true)                          # the finger has left the dead zone
		inst.set("_press_pos", cam.unproject_position(sim.nodes[mine]["pos"]))   # the press on your vat (the cone snaps from it)
		var sp: Vector2 = cam.unproject_position(sim.nodes[target]["pos"])
		inst.call("_draw_drag", mine, sim.nodes[target]["pos"], sp)
		await _shot("send")
		# back onto the origin: HOLD (send-order) or nothing (main without it)
		var op: Vector2 = cam.unproject_position(sim.nodes[mine]["pos"])
		inst.call("_draw_drag", mine, sim.nodes[mine]["pos"], op)
		await _shot("hold")
		inst.call("_end_drag")
	inst.queue_free()
	await _frames(3)
	get_tree().quit(0)
