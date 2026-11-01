extends Node
## PROTO DEBUG check (Daniele, 2026-11-02: "speed up player production and speed up time so I can test fast"):
## Sim.debug_prod / debug_refill / debug_add_units, then two real matches on a P map - flag OFF first (no Debug button,
## no tag, GAME SPEED x4 and MY PRODUCTION x10 do nothing), then flag ON (x4 runs the sim 4x, the tag reads it).
##   Godot --path . --resolution 1266x585 --audio-driver Dummy --position -6000,-6000 res://tests/test_proto_debug.tscn \
##       -- --map=res://maps4/P-02-conveyor.json --no-notice --no-account --no-telemetry
## (windowed: the HUD lays out as in play). Exit code 0 = all passed.

var failures := 0
var _real := 0.0                                      # summed frame time as main steps it (min(delta, 0.05))


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _process(delta: float) -> void:
	_real += minf(delta, 0.05)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func():      # a script error must not hang the run
		print("test_proto_debug: TIMEOUT")
		get_tree().quit(3))
	var was: bool = Rules.proto_debug
	check(was and Rules.VERSION.contains("-proto"), "a proto build (%s) has the flag on" % Rules.VERSION)
	_sim_checks()
	# --- a real match with the flag OFF: the real game's path
	Rules.proto_debug = false
	Rules.debug_speed = 4
	Rules.debug_prod = 10.0
	var main := await _match()
	if main.hud == null:
		check(false, "the match started")
		get_tree().quit(1)
		return
	check(not main.hud.debug_button.visible and main.hud.debug_tag == null, "flag off: no Debug button, no DEBUG tag")
	check(main.debug_speed() == 1, "flag off: GAME SPEED reads x1 whatever was set")
	var r := await _ratio(main, 90)
	check(absf(r - 1.0) < 0.05, "flag off: the sim runs at x1 (%.2f)" % r)
	check(main.sim.debug_prod.is_empty(), "flag off: MY PRODUCTION never reaches the sim")
	main.queue_free()
	await _frames(10)
	# --- flag ON (the proto build)
	Rules.proto_debug = true
	Rules.debug_speed = 1
	Rules.debug_prod = 1.0
	main = await _match()
	var hud = main.hud
	check(hud.debug_button.visible, "flag on, offline: the Debug button is there")
	check(hud.debug_button.size.y >= 44.0, "the Debug button is a thumb-sized tap (%.0f px)" % hud.debug_button.size.y)
	hud.debug_button.button_pressed = true
	await _frames(3)
	check(hud._debug_proto.visible and not hud._debug_off_note.visible, "the panel shows the proto tools offline")
	var dp: Rect2 = hud.debug_panel.get_global_rect()
	check(dp.size.y >= 150.0 and dp.end.y <= hud.root.get_viewport_rect().size.y + 0.5,
			"the panel opens to its content, on screen (%.0f x %.0f)" % [dp.size.x, dp.size.y])
	check(not hud.debug_tag.visible, "all x1: no DEBUG tag")
	r = await _ratio(main, 60)
	check(absf(r - 1.0) < 0.05, "x1: the sim runs at x1 (%.2f)" % r)
	_press(hud._debug_proto.get_child(0), 4.0)        # GAME SPEED x4
	_press(hud._debug_proto.get_child(1), 10.0)       # MY PRODUCTION x10
	await _frames(3)
	check(Rules.debug_speed == 4 and is_equal_approx(float(main.sim.debug_prod.get(main.HUMAN, 0.0)), 10.0),
			"the panel's x4 / x10 set GAME SPEED and the human seat's production")
	check(hud.debug_tag.visible and hud.debug_tag.text == "DEBUG x4 · PROD x10", "the tag reads it (%s)" % hud.debug_tag.text)
	var lbl: Label = hud._debug_proto.get_child(0).get_child(0)
	check(lbl.text == "GAME SPEED  x4", "the GAME SPEED row reads x4 (%s)" % lbl.text)
	var tag_r: Rect2 = hud.debug_tag.get_global_rect()
	check(tag_r.end.x <= hud.debug_button.position.x + 0.5 and tag_r.position.y >= 0.0, "the tag sits left of the Debug button")
	r = await _ratio(main, 90)
	check(absf(r - 4.0) < 0.2, "x4: the sim runs 4x real time (%.2f)" % r)
	var ais_seat: String = main.ais[0].seat if not main.ais.is_empty() else ""
	check(main.sim.debug_prod.get(ais_seat, 1.0) == 1.0, "the AI seat keeps x1 production")
	_press(hud._debug_proto.get_child(0), 1.0)
	_press(hud._debug_proto.get_child(1), 1.0)
	await _frames(2)
	check(not hud.debug_tag.visible, "back to x1 / x1: the tag goes")
	main.queue_free()
	Rules.debug_speed = 1
	Rules.debug_prod = 1.0
	Rules.proto_debug = was
	print("test_proto_debug: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _press(row: HBoxContainer, v: float) -> void:
	for b in row.get_children():
		if b is Button and is_equal_approx(float(b.get_meta("v")), v):
			b.emit_signal("pressed")
			return
	check(false, "a x%d button" % int(v))


func _match() -> Node:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in range(600):
		await get_tree().process_frame
		if is_instance_valid(main) and main.is_inside_tree() and main.started and main.hud != null:
			break
	await _frames(20)
	return main


func _ratio(main: Node, frames: int) -> float:
	await _frames(2)
	var t0: float = main.sim.time
	_real = 0.0
	await _frames(frames)
	return (main.sim.time - t0) / maxf(_real, 0.001)


func _sim_checks() -> void:
	var map := MapBuilder.load_map("res://maps4/P-02-conveyor.json")
	var pos := MapBuilder.layout(map)
	var homes: Dictionary = {}
	for n in map["nodes"]:
		if n.get("home", false) == true and homes.size() < 2:
			homes[int(n["id"])] = "A" if homes.is_empty() else "B"
	var a_home: int = homes.find_key("A")
	var made := []
	for mult in [1.0, 10.0]:
		var sim := Sim.new()
		sim.setup(map, pos, homes, {"A": "null", "B": "ember"}, 1)
		var id: int = a_home
		if mult != 1.0:
			sim.debug_prod["A"] = mult
		sim.nodes[id]["units"] = 0.0
		for i in range(20):
			sim.step(0.05)
		made.append(float(sim.nodes[id]["units"]))
	check(made[0] > 0.0 and absf(made[1] / made[0] - 10.0) < 0.5, "MY PRODUCTION x10 makes 10x in 1 s (%.2f vs %.2f)" % [made[1], made[0]])
	Rules.proto_debug = false
	var sim2 := Sim.new()
	sim2.setup(map, pos, homes, {"A": "null", "B": "ember"}, 1)
	var id2: int = a_home
	sim2.debug_prod["A"] = 10.0
	sim2.nodes[id2]["units"] = 0.0
	for i in range(20):
		sim2.step(0.05)
	check(absf(float(sim2.nodes[id2]["units"]) - made[0]) < 0.01, "flag off: a set multiplier does nothing (%.2f)" % sim2.nodes[id2]["units"])
	sim2.skill_cd["A"] = {"active": 20.0}
	check(sim2.debug_refill("A") == 0 and float(sim2.skill_cd["A"]["active"]) == 20.0, "flag off: REFILL does nothing")
	check(not sim2.debug_add_units(id2, "A"), "flag off: +100 does nothing")
	Rules.proto_debug = true
	var u: float = sim2.nodes[id2]["units"]
	check(sim2.debug_add_units(id2, "A") and Rules.shown(sim2.nodes[id2]["units"] - u) == Rules.DEBUG_ADD_UNITS,
			"+%d (shown) on an own node" % Rules.DEBUG_ADD_UNITS)
	var rival := -1
	for n in sim2.nodes:
		if n["owner"] == "B":
			rival = n["id"]
	check(rival >= 0 and not sim2.debug_add_units(rival, "A"), "+100 refused on a rival node")
	var relay_id := -1
	for n in sim2.nodes:
		if n["relay"] != "":
			relay_id = n["id"]
			break
	if relay_id >= 0:
		sim2.nodes[relay_id]["owner"] = "A"
		sim2.nodes[relay_id]["relay_cd"] = 12.0
	sim2.ult_charge["A"] = 0.2
	var nrel := sim2.debug_refill("A")
	check(float(sim2.skill_cd["A"]["active"]) == 0.0 and sim2.cooldown("A", "ultimate") == 0.0, "REFILL: skills and the ultimate ready")
	check(relay_id < 0 or (nrel >= 1 and float(sim2.nodes[relay_id]["relay_cd"]) == 0.0), "REFILL: own relays off cooldown (%d)" % nrel)
	sim2.start_last_stand_now()
	check(sim2.last_stand_active, "LAST STAND NOW starts it (t=%.1f)" % sim2.time)
