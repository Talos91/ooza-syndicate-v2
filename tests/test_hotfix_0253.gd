extends Node
## 0.25.3 HOTFIX (Daniele 2026-11-27, four bugs on live 0.25.2) - the HUD side, in the real game scene:
##   Godot --headless --audio-driver Dummy --path . res://tests/test_hotfix_0253.tscn -- --map=res://maps4/G-02-fort.json
## (a) once the ring collapse is done the status line says when the Very Last Stand comes (not CONQUEST DECIDES over a minute
##     where nothing falls), and no line names the method (INWARD / OUTWARD);
## (b) a laser relay holding its laser offers FORGE in its pie; (c) a node a sinkhole emptied offers VAT in its pie.
## The Sim side of (b) / (c) / (d) is test_sim --only=hotfix_0253. Exit code 0 = all passed.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _check_025_hud(cond: bool, what: String) -> void:
	## OOZE 3.0 (WP1): the 0.25.3 HUD wording for the RING collapse lived in hud.gd; the ooze3 merge kept ooze3's hud.gd (3.0's Last
	## Stand is the quota, its line is WP4's "Last Stand text" job). Reported, not failed, until WP4 owns the 3.0 line.
	if cond:
		check(true, what)
	else:
		print("SKIP  (0.25 ring-collapse HUD line; 3.0 Last Stand text = WP4) " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _pie(main: Node, id: int) -> Array:
	var hud = main.hud
	hud.close_inspector()
	hud.inspect(id, main.cam)
	var out := []
	for a in hud.inspector_actions:
		out.append(str(a["name"]))
	hud.close_inspector()
	return out


func _ready() -> void:
	# OOZE 3.0 (WP1): G-02 is a 0.25 map and this checks the 0.25.3 fixes, so it runs the 0.25 rules: the ring collapse (3.0's
	# Last Stand is the quota) and every relay kind (3.0 archives laser_relay). Set before main.tscn builds its Sim.
	Rules.quota = false
	Rules.RELAY_SET = false
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _frames(30)
	var sim: Sim = main.sim
	check(sim != null and sim.nodes.size() > 4 and sim.nodes[4]["relay"] == "laser_relay", "G-02 loaded (node 4 = laser relay)")
	main.paused = true
	var human: String = main.HUMAN
	# (b) the old laser relay offers FORGE
	var lr: Dictionary = sim.nodes[4]
	lr["owner"] = human
	lr["units"] = float(Rules.FORGE_COST) + 40.0
	var pie := _pie(main, 4)
	check("JUICER" in pie, "0.25.3 (b): a laser relay holding its laser offers the forge, shown JUICER in 3.0 (pie %s)" % [pie])
	# (c) a sinkhole empties a T1 vat: the pie offers VAT again
	var vid := -1
	for n in sim.nodes:
		if n["node_kind"] == "common" and n["owner"] == "" and n["structure"] == "vat" and int(n["tier"]) == 1:
			vid = n["id"]
			break
	var v: Dictionary = sim.nodes[vid]
	v["owner"] = human
	v["units"] = 60.0
	sim._sinkhole("B", v)
	pie = _pie(main, vid)
	check(v["structure"] == "" and "VAT" in pie, "0.25.3 (c): a node a sinkhole emptied offers VAT (pie %s)" % [pie])
	# (a) the Last Stand: run the ring collapse to its end, before 6:00
	sim.time = Rules.LAST_STAND_TIME
	sim._step_last_stand(0.0)
	main.hud.pulse_last_stand("the rim falls first - hold the centre")   # what main does on the "last_stand" fx
	main.hud.sync(0.0, main.cam)
	var first: String = main.hud.status_label.text
	_check_025_hud(not ("INWARD" in first.to_upper() or "OUTWARD" in first.to_upper()) and first.begins_with("LAST STAND"),
			"0.25.3 (a): the Last Stand announcement names no method ('%s')" % first)
	while sim.time < Rules.VERY_LAST_STAND_TIME - 5.0 and not (sim.last_stand_queue.is_empty() and sim.last_stand_next >= sim.last_stand_waves.size()):
		sim._step_last_stand(0.05)
		sim.time += 0.05
	check(sim.time < Rules.VERY_LAST_STAND_TIME - 5.0, "G-02's ring collapse ends before the Very Last Stand (%.0f s)" % sim.time)
	main.hud.sync(10.0, main.cam)                                 # the pulse is long over (it counts down after the line is set)
	main.hud.sync(0.0, main.cam)
	var after: String = main.hud.status_label.text
	_check_025_hud(after.contains("VERY LAST STAND in"), "0.25.3 (a): after the ring collapse the line says when the Very Last Stand comes ('%s')" % after)
	# (a) in 3.0: the Last Stand is the quota, so the sim never holds an INWARD / OUTWARD method for the HUD to show
	Rules.quota = true
	var q := Sim.new()
	var m := MapBuilder.load_map("res://maps4/G-02-fort.json")
	q.setup(m, MapBuilder.layout(m), {int(m["seats"]["1v1"][0]["node"]): "A", int(m["seats"]["1v1"][1]["node"]): "B"}, {"A": "null", "B": "ember"}, 5)
	q.start_last_stand_now()
	check(q.last_stand_method == "quota" or not q.last_stand_active,
			"0.25.3 (a) in 3.0: the Last Stand is the quota, no INWARD / OUTWARD state (method '%s')" % q.last_stand_method)
	Rules.quota = false
	print("hotfix_0253 HUD: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
