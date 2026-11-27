extends Node
## 0.25.3 HOTFIX (Daniele 2026-11-27, four bugs on live 0.25.2) - the HUD side, in the real game scene:
##   Godot --headless --audio-driver Dummy --path . res://tests/test_hotfix_0253.tscn -- --map=res://maps4/G-02-fort.json
## (a) no line names the method (INWARD / OUTWARD) - since WP4b (Ooze 3.0) there is no Last Stand line at all, the warned
##     node's screen counts its drop down and gives the count back;
## (b) a laser relay holding its laser offers FORGE in its pie; (c) a node a sinkhole emptied offers VAT in its pie.
## The Sim side of (b) / (c) / (d) is test_sim --only=hotfix_0253. Exit code 0 = all passed.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


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
	# (a) the Last Stand: run the ring collapse to its end, before 6:00. WP4b (Daniele 2026-11-27: "no more last stand alert
	# message as it's on screen"): no status line while it runs (so no line can name the method), the warned node's own screen
	# counts its drop down (VatCount) and the count comes back on it.
	sim.time = Rules.LAST_STAND_TIME
	sim._step_last_stand(0.0)
	main.hud.sync(0.0, main.cam)
	var first: String = main.hud.status_label.text
	check(sim.last_stand_active and first == "", "WP4b (a): no Last Stand line in the HUD while it runs ('%s')" % first)
	var guard := 0
	while sim.last_stand_queue.is_empty() and guard < 4000:            # to the first warned ring
		sim._step_last_stand(0.05)
		sim.time += 0.05
		guard += 1
	var vc = main.vat_count
	var warned := -1
	for id in vc.screens:
		if sim.is_warned(id):
			warned = id
			break
	check(warned >= 0, "WP4b (a): a node is warned (time %.0f s)" % sim.time)
	if warned >= 0:
		vc._clock = 0.0                                               # the cycle's notice part: the seconds
		vc.sync()
		var said: String = vc.screens[warned]["text"]
		check(said.ends_with("s") and said.contains(str(int(ceil(sim.drop_in(warned))))),
				"WP4b (a): the warned node's screen counts its drop down ('%s', drop in %.1f s)" % [said, sim.drop_in(warned)])
		vc._clock = 2.0                                               # past VatCount.NOTICE_S (1.6 of 2.4 s): the count again
		vc.sync()
		said = vc.screens[warned]["text"]
		check(said == vc.count_text(sim.nodes[warned]), "WP4b (a): then the count comes back on that screen ('%s')" % said)
	while sim.time < Rules.VERY_LAST_STAND_TIME - 5.0 and not (sim.last_stand_queue.is_empty() and sim.last_stand_next >= sim.last_stand_waves.size()):
		sim._step_last_stand(0.05)
		sim.time += 0.05
	check(sim.time < Rules.VERY_LAST_STAND_TIME - 5.0, "G-02's ring collapse ends before the Very Last Stand (%.0f s)" % sim.time)
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
