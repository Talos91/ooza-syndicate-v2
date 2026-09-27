extends SceneTree
## Headless tutorial check:  Godot --headless --path . --script res://tests/test_tutorial.gd  [-- maps=<dir>]
## Exit code 0 = all passed. TUTORIAL-DESIGN.md §9: every lesson is staged on its baked map and each step's
## correct action is played through the same Sim calls the controls use (send, upgrade_structure,
## structure_order, fire_relay, cast - what main.perform runs), stepping at 0.05 s until the step passes; it must
## pass within its budget and the next step must start. One negative check per lesson (doing nothing / the
## wrong thing does not pass a doing-step). L4 / L9: the scripted push is on the relay deck when the prompt
## fires, half speed is asked for only while it is there, and firing drops the expected share. L7: the collapse
## starts at the staged time, evacuating keeps A alive, the Very Last Stand reaches one platform. Reveal sets
## are cumulative; progress + the Graduate unlock round-trip on temp paths; the first-launch rule. Everything is
## staged directly - no whole matches (L9 starts from a staged mid-match board).
## `maps=<dir>` points the lesson maps at another folder of baked maps (default res://maps4).

const DT := 0.05
var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("maps="):
			TutorialDirector.map_dir = a.substr(5)
	TutorialDirector.path = "user://test_tutorial_progress.cfg"
	ArmyPresets.path = "user://test_tutorial_armies.cfg"
	Progression.path = "user://test_tutorial_progression.cfg"   # TUTORIAL + PROGRESSION: never the real wallet
	_wipe()
	TutorialDirector.reload_progress()
	ArmyPresets._loaded = false
	ArmyPresets.load_all()
	Rules.abilities_on = true
	Rules.last_stand = true
	test_lines()
	test_reveal()
	test_progress()
	test_l0()
	test_senders()
	test_short_sends()
	test_l1()
	test_l2()
	test_l3()
	test_l4()
	test_l5()
	test_l6()
	test_l7()
	test_l7_seeds()
	test_l8()
	test_l9()
	_wipe()
	print("\n%s: %d failure(s)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _wipe() -> void:
	for p in [TutorialDirector.path, ArmyPresets.path, Progression.path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progression.reload_all()


# ------------------------------------------------------------------ harness
func make(id: int, seed_value := 7) -> Array:
	## [director, sim]: the lesson's map, seats and loadout exactly as main.start_tutorial builds them (VEX, EMBER).
	var d := TutorialDirector.new(id)
	var map := MapBuilder.load_map(TutorialDirector.map_path_for(id))
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, {"A": TutorialDirector.PLAYER_FACTION, "B": TutorialDirector.RIVAL_FACTION},
			seed_value, {}, {"A": d.loadout_for()})
	d.ui_fraction = d.fraction_start(0.5)
	d.begin(sim, map, TutorialDirector.PLAYER_FACTION)
	return [d, sim]


func tick(d: TutorialDirector, sim: Sim) -> void:
	## One frame as main runs it: the director, the Sim at the director's time scale, the fx events.
	d.step(DT)
	sim.step(DT * d.time_scale)
	for ev in sim.fx_events:
		d.on_event(ev)
	sim.fx_events.clear()


func play(d: TutorialDirector, sim: Sim, key: String, act: Callable, budget := -1.0) -> bool:
	## Play step `key` with `act.call(t)` every frame until the next step starts (or the lesson completes);
	## checks it happened within the step's budget.
	var st: Dictionary = d.L["steps"][d.step_i]
	check(str(st["key"]) == key, "L%d: step '%s' is the current step" % [d.lesson_id, key])
	var lim: float = budget if budget > 0.0 else float(st.get("budget", 5.0)) + TutorialDirector.INTERLUDE + 0.5
	var k := d.step_i
	var t := 0.0
	while d.step_i == k and d.state in ["running", "interlude"] and t < lim:
		act.call(t)
		tick(d, sim)
		t += DT
	var ok := d.step_i != k or d.state == "complete"
	check(ok, "L%d step '%s' passes within %.0f s (took %.1f s, state %s)" % [d.lesson_id, key, lim, t, d.state])
	return ok


func wait(_t: float) -> void:
	pass


func first(t: float) -> bool:
	return t < DT * 0.5


func deck_metres(sim: Sim, hid: int, relay: int) -> float:
	var h := sim._horde(hid)
	if h.is_empty():
		return 0.0
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	var m := 0.0
	for sp in h["spans"]:
		if sp["edge"] in sim.controlled_edges(relay) and sim.is_edge_open(sp["edge"]):
			m += maxf(0.0, minf(head, sp["s1"]) - maxf(tail, sp["s0"]))
	return m


# ------------------------------------------------------------------ the script's words (draft 2)
func test_lines() -> void:
	var banned := RegEx.create_from_string("(?i)\\b(platforms?|crews?|bridges?|batch|boss|cannons?)\\b")
	var bad := []
	var long := []
	for k in TutorialDirector.LINES:
		var t := str(TutorialDirector.LINES[k])
		if banned.search(t):
			bad.append(k)
		var shown_t := RegEx.create_from_string("[{][a-z_0-9]+[}]").sub(t, "000000", true)   # a placeholder ~ 6 characters
		if shown_t.length() > 90:
			long.append(k)
		if str(k).ends_with(".title") and t.length() > 18:
			long.append(k)
	check(bad.is_empty(), "lines: none of the banned words (platform, crew, bridge, batch, boss, cannon) %s" % str(bad))
	check(long.is_empty(), "lines: <= 90 characters, titles <= 18 %s" % str(long))
	for l in TutorialDirector.LESSONS:
		for st in l["steps"]:
			var key := "%s.%s" % [l["key"], st["key"]]
			check(TutorialDirector.LINES.has(key), "lines: step %s has its line" % key)
	check(TutorialDirector.lesson_rows().size() == TutorialDirector.TOTAL_LESSONS and TutorialDirector.lesson_rows()[0]["title"] == "THE CITY",
			"the TRAINING page lists 10 rows, 0 THE CITY first")


# ------------------------------------------------------------------ reveal sets
func test_reveal() -> void:
	var before := TutorialDirector.REVEAL_BASE.duplicate()
	check(TutorialDirector.reveal_for(0, 0).size() == TutorialDirector.ALL_KEYS.size(), "reveal L0: the tour shows every HUD part")
	for l in TutorialDirector.LESSONS:
		var id := int(l["id"])
		var got := TutorialDirector.reveal_for(id, 0)
		if id == TutorialDirector.FIRST_ID:
			continue
		if id == TutorialDirector.LESSON_COUNT:
			check(got.size() == TutorialDirector.ALL_KEYS.size(), "reveal L9: everything (%d keys)" % got.size())
			continue
		var want := before.duplicate()
		for k in l.get("reveal", []) + (l["steps"][0] as Dictionary).get("reveal", []):
			if not k in want:
				want.append(k)
		check(_same(got, want), "reveal L%d step 1 = the lessons before it + its own start keys %s" % [id, str(got)])
		for k in ["halos", "eject", "out_panel"]:
			check(not k in got, "reveal L%d: no team part '%s' in a 1v1 lesson" % [id, k])
		var last := TutorialDirector.reveal_for(id, (l["steps"] as Array).size() - 1)
		for k in before:
			check(k in last, "reveal L%d keeps '%s' from the lessons before" % [id, k])
		before = last
	check("send_panel" in TutorialDirector.reveal_for(1, 2) and not "send_panel" in TutorialDirector.reveal_for(1, 1),
			"reveal: the SEND panel appears at L1 step 3, not before")
	check("dock" in TutorialDirector.reveal_for(8, 0) and not "dock" in TutorialDirector.reveal_for(7, 3), "reveal: the dock appears in L8")
	check("danger" in TutorialDirector.reveal_for(7, 0) and not "danger" in TutorialDirector.reveal_for(6, 7), "reveal: danger marks from L7")
	check("relay" in TutorialDirector.reveal_for(4, 0) and not "relay" in TutorialDirector.reveal_for(3, 4), "reveal: the relay cue from L4")
	check("topbar" in TutorialDirector.reveal_for(1, 0) and not "strength" in TutorialDirector.reveal_for(1, 0), "reveal: L1 shows the top bar, the clock only")
	check("floaters" in TutorialDirector.reveal_for(1, 0) and "floaters" in TutorialDirector.reveal_for(8, 3),
			"reveal: the capture floaters from L1 step 1, kept in every later lesson")
	check("monster_icon" in TutorialDirector.reveal_for(6, 0) and not "monster_icon" in TutorialDirector.reveal_for(5, 3), "reveal: the monster icon from L6")
	check("out_panel" in TutorialDirector.reveal_for(9, 0) and "out_panel" in TutorialDirector.reveal_for(0, 0), "reveal: YOU'RE OUT only in the tour and the first match")


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not k in b:
			return false
	return true


# ------------------------------------------------------------------ progress, unlock, first launch
func test_progress() -> void:
	_wipe()
	TutorialDirector.reload_progress()
	check(TutorialDirector.done_count() == 0 and not TutorialDirector.offered, "progress: a fresh device has nothing done, nothing offered")
	check(TutorialDirector.first_launch_due(PackedStringArray(), false) and TutorialDirector.first_unfinished() == 0,
			"first launch: no `offered` key -> straight into the tour (L0)")
	for flag in ["--map=res://maps4/T-01-first-steps.json", "--scenario=hud19", "--stage=monster", "--thumb=x.png", "--shots=4", "--demo"]:
		check(not TutorialDirector.first_launch_due(PackedStringArray([flag]), false), "first launch: never with %s" % flag)
	check(not TutorialDirector.first_launch_due(PackedStringArray(), true), "first launch: never in an online room or a Net reconnect")
	check(not ArmyPresets.is_unlocked("graduate") and ArmyPresets.is_unlocked("biopod") and ArmyPresets.is_unlocked("default"),
			"unlock: the Graduate vat is locked until the tutorial is done, every other look stays unlocked")
	ArmyPresets.set_cosmetic_pick("null", "vat", "graduate")
	check(ArmyPresets.cosmetic_loadout_for("null")["vat"] == "default" and ArmyPresets.cosmetic_loadout_for("null", true)["vat"] == "graduate",
			"unlock: a locked Graduate pick plays as the default vat, ARMIES still shows the pick")
	TutorialDirector.mark_offered()
	check(TutorialDirector.saved, "progress: saved to the temp path")
	TutorialDirector.reload_progress()
	check(TutorialDirector.offered and not TutorialDirector.first_launch_due(PackedStringArray(), false), "progress: `offered` round-trips; no second forced start")
	for i in range(1, 9):
		TutorialDirector.mark_complete(i)
	var lesson_pay: int = Rules.PROGRESSION["tutorial_lesson"]
	check(TutorialDirector.last_scrap == lesson_pay and Progression.balance() == 8 * lesson_pay,
			"scrap: each first completion pays %d (%d after 8)" % [lesson_pay, Progression.balance()])
	TutorialDirector.mark_complete(3)
	check(TutorialDirector.last_scrap == 0 and Progression.balance() == 8 * lesson_pay, "scrap: a replay pays nothing")
	TutorialDirector.reload_progress()
	check(TutorialDirector.done_count() == 8 and TutorialDirector.first_unfinished() == 0 and not ArmyPresets.is_unlocked("graduate"),
			"progress: 8 lessons round-trip, CONTINUE = the tour (L0), Graduate still locked")
	TutorialDirector.mark_complete(9, true)
	TutorialDirector.reload_progress()
	check(TutorialDirector.all_done() and TutorialDirector.relay_kill_done and ArmyPresets.is_unlocked("graduate"),
			"progress: lessons 1-9 + relay kill round-trip; the Graduate vat unlocks without the tour")
	check(Progression.balance() == 9 * lesson_pay and Progression.third_skill_line() != "", "scrap: lesson 9 brings 1 260 - a 3rd skill")
	TutorialDirector.mark_complete(0)
	check(TutorialDirector.last_scrap == 0 and Progression.balance() == 9 * lesson_pay, "scrap: the tour (L0) pays nothing")
	TutorialDirector.reload_progress()
	check(TutorialDirector.done_count() == TutorialDirector.TOTAL_LESSONS, "progress: the tour counts toward n/10")
	check(ArmyPresets.cosmetic_loadout_for("null")["vat"] == "graduate", "unlock: the Graduate pick plays once unlocked")
	var cf := ConfigFile.new()
	check(cf.load(TutorialDirector.path) == OK and int(cf.get_value("progress", "version", 0)) == TutorialDirector.PROGRESS_VERSION,
			"progress: the file carries [progress] version")
	_wipe()
	TutorialDirector.reload_progress()
	ArmyPresets._loaded = false
	ArmyPresets.load_all()


# ------------------------------------------------------------------ L0 THE CITY
func test_l0() -> void:
	var r := make(0)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	check(sim.factions["A"] == "vex" and sim.factions["B"] == "ember", "the tutorial is VEX against EMBER")
	check(d.card()["button"] == TutorialDirector.line("next_step") and d.header() == "DR. VESK · THE CITY", "L0: a NEXT card, DR. VESK · THE CITY")
	var seen := []
	while d.state == "running" and seen.size() < 20:
		var st: Dictionary = d.L["steps"][d.step_i]
		seen.append(st["key"])
		if st["key"] == "inspector":
			check(d.inspect_request() == d.names["H"], "L0: the inspector step opens the inspector on your home")
		if st["key"] == "deck":
			check((d.target()["decks"] as Array).size() == 1, "L0: the deck step spotlights one deck")
		if st["key"] == "badge":
			check(d.target()["rects"] == ["badge:%d" % d.names["H"]], "L0: the badge step spotlights your home's badge")
		for i in range(10):
			tick(d, sim)
		d.press_button()
		tick(d, sim)
	check(seen.size() == 14 and d.state == "complete" and d.result.get("tour", false), "L0: 14 tour steps, then on to L1 (%s)" % str(seen))
	check(TutorialDirector.is_done(0) and not TutorialDirector.all_done(), "L0 done does not unlock the Graduate vat")


# ------------------------------------------------------------------ 0.20.2: senders under the spotlight, short sends
func test_senders() -> void:
	## Every step where you send lights the node you send FROM (the drag's source), not only the target.
	for l in TutorialDirector.LESSONS:
		var steps: Array = l["steps"]
		for i in range(steps.size()):
			var src := ""
			for g in (steps[i] as Dictionary).get("gesture", []):
				if str(g[0]) == "drag":
					src = str(g[1])
			if src == "":
				continue
			var r := make(int(l["id"]))
			var d: TutorialDirector = r[0]
			while d.step_i < i and d.state == "running":
				d.skip_step()
			check(d.step_i == i and d.names[src] in d.target()["nodes"],
					"senders: L%d '%s' spotlights its source %s" % [l["id"], steps[i]["key"], src])
	var r7 := make(7)
	var d7: TutorialDirector = r7[0]
	d7.skip_step()
	var lit: Array = d7.target()["nodes"]
	check(d7.names["H"] in lit and d7.names["A1"] in lit and d7.names["A2"] in lit, "senders: L7 evacuate lights every node you can send from")


func test_short_sends() -> void:
	## A short send on a capture step: the target holds, the director tops up your sender, freezes the target and
	## points the hand at the retry - then a 100 % send takes it. Never a TRY AGAIN.
	var r := make(1)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	d.skip_step()
	d.skip_step()
	d.skip_step()                                             # send25
	check(str(d.L["steps"][d.step_i]["key"]) == "send25", "short send: at L1 send25")
	sim.nodes[n["H"]]["units"] = 20.0 * Rules.SCALE
	sim.send(n["H"], n["N2"], 0.1)                            # 2 against 15
	var said := false
	var t := 0.0
	while t < 20.0 and d.assist_retry().is_empty():
		tick(d, sim)
		said = said or d.card()["text"] == TutorialDirector.line("assist_short")
		t += DT
	check(not d.assist_retry().is_empty() and said, "short send: the landing short of the target triggers the assist line")
	check(d.state == "running" and sim.nodes[n["N2"]]["owner"] == "", "short send: no TRY AGAIN, the node still stands")
	var retry := d.assist_retry()
	check(d.gesture()[0] == ["drag", retry[0], n["N2"]], "short send: the hand points at the retry")
	var frozen: float = sim.nodes[n["N2"]]["units"]
	for i in range(int(3.0 / DT)):
		tick(d, sim)
	check(sim.nodes[n["N2"]]["units"] <= frozen + 0.01, "short send: the target's count is frozen for the step")
	sim.send(int(retry[0]), n["N2"], 1.0)
	var k := d.step_i
	t = 0.0
	while d.step_i == k and t < 30.0:
		tick(d, sim)
		t += DT
	check(d.step_i == k + 1 and sim.nodes[n["N2"]]["owner"] == "A", "short send: the 100 %% retry takes it and the step passes (%.1f s)" % t)
	# L3's attack on the rival node: the same, against a producing rival vat
	var r3 := make(3)
	var d3: TutorialDirector = r3[0]
	var s3: Sim = r3[1]
	var n3: Dictionary = d3.names
	while str(d3.L["steps"][d3.step_i]["key"]) != "attack":
		d3.skip_step()
	s3.nodes[n3["B1"]]["units"] = 40.0 * Rules.SCALE
	s3.nodes[n3["N1"]]["units"] = 10.0 * Rules.SCALE
	s3.nodes[n3["H"]]["units"] = 5.0 * Rules.SCALE
	for i in range(3):
		tick(d3, s3)
	var retry3 := d3.assist_retry()
	check(not retry3.is_empty() and s3.nodes[int(retry3[0])]["units"] > s3.nodes[n3["B1"]]["units"],
			"short send: nodes that clearly can't win are topped up at once (L3 attack)")
	s3.send(int(retry3[0]), n3["B1"], 1.0)
	var k3 := d3.step_i
	t = 0.0
	while d3.step_i == k3 and t < 40.0:
		tick(d3, s3)
		t += DT
	check(s3.nodes[n3["B1"]]["owner"] == "A" and d3.state == "running", "short send: L3's rival vat taken after the top-up")


# ------------------------------------------------------------------ L1 SEND
func test_l1() -> void:
	var r := make(1)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	check(sim.nodes[n["H"]]["owner"] == "A" and Rules.shown(sim.nodes[n["H"]]["units"]) == 30, "L1 staged: A's home with 30")
	check(d.gesture()[0][0] == "drag" and d.gesture()[0][1] == n["H"] and d.gesture()[0][2] == n["N1"], "L1: the hand drags H -> N1")
	# negative: nothing happens, nothing passes
	for i in range(int(20.0 / DT)):
		tick(d, sim)
	check(d.step_i == 0, "L1 negative: doing nothing never passes the drag step")
	check(d.allow("send", n["H"], {"to": n["BH"]}) != "", "L1: sending the home at B is refused (Not yet)")
	play(d, sim, "drag", func(t): if first(t): sim.send(n["H"], n["N1"], d.fraction_start(0.5)))
	play(d, sim, "label", wait)
	play(d, sim, "percent", func(t): if first(t): d.ui_fraction = 0.25)
	play(d, sim, "send25", func(t): if first(t): check(not sim.send(n["H"], n["N2"], 0.25).is_empty(), "L1: a 25 % send goes"))
	play(d, sim, "reinforce", func(t): if first(t): sim.send(n["N1"], n["H"], 0.5))
	check(d.state == "complete" and TutorialDirector.is_done(1), "L1 complete and saved")


# ------------------------------------------------------------------ L2 VATS
func test_l2() -> void:
	var r := make(2)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	for i in range(int(10.0 / DT)):
		tick(d, sim)
	check(d.step_i == 0, "L2 negative: no inspector, no pass")
	play(d, sim, "inspect", func(t): d.ui_inspector = n["H"])
	d.ui_inspector = -1
	check(d.card()["text"].contains(str(Rules.shown(Rules.VAT_COST[1]))), "L2: the upgrade line names the cost from Rules")
	play(d, sim, "upgrade", func(t): if first(t): check(sim.upgrade_structure(n["H"]), "L2: double-tap upgrade starts"))
	play(d, sim, "build", wait)
	play(d, sim, "t3", func(t): if sim.can_upgrade(n["H"], "A") == "": sim.upgrade_structure(n["H"]))
	check(sim.nodes[n["H"]]["tier"] == 3, "L2: the vat reached T3")
	play(d, sim, "machinegoon", func(t): if first(t): check(sim.structure_order("A", "build", n["N1"], {"kind": "machinegoon"})[0], "L2: MACHINEGOON builds"))
	var b_lost0: float = sim.combat_losses.get("B", 0.0)
	play(d, sim, "watch", wait)
	check(sim.nodes[n["N1"]]["owner"] == "A" and sim.combat_losses.get("B", 0.0) > b_lost0, "L2: the Machinegoon held N1 and killed rival crews")
	play(d, sim, "mg_upgrade", func(t): if first(t): check(sim.upgrade_structure(n["N1"]), "L2: the Machinegoon upgrade starts"))
	play(d, sim, "t4", func(t): if first(t): d.press_button())
	check(d.state == "complete", "L2 complete")


# ------------------------------------------------------------------ L3 THE ENEMY
func test_l3() -> void:
	var neg := make(3)
	var dn: TutorialDirector = neg[0]
	var sn: Sim = neg[1]
	sn.send(dn.names["H"], dn.names["N2"], 0.5)                 # 12 against 15: too small
	var said := false
	for i in range(int(20.0 / DT)):
		tick(dn, sn)
		said = said or dn.card()["text"] == TutorialDirector.line("L3.too_small")
	check(dn.step_i == 0 and sn.nodes[dn.names["N2"]]["owner"] == "", "L3 negative: a line smaller than the garrison does not take it")
	check(said, "L3: the handler says 'Not enough. Try 75 %.'")
	var r := make(3)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	check(d.card()["text"].contains(str(Rules.shown(Rules.NEUTRAL_UNITS[1]))), "L3: the neutral line names its garrison")
	play(d, sim, "neutral", func(t): if first(t): sim.send(n["H"], n["N2"], 0.75))
	play(d, sim, "trade", func(t): if first(t): d.press_button())
	var b_line := {"seen": false}
	play(d, sim, "defend", func(t):
		if first(t):
			b_line["seen"] = sim.hordes.any(func(h): return h["owner"] == "B" and int(h["target"]) == n["N1"])
			sim.send(n["H"], n["N1"], 1.0))
	check(b_line["seen"], "L3: the rival attack on N1 was launched")
	check(sim.nodes[n["N1"]]["owner"] == "A", "L3: reinforcing held N1")
	var tier0: int = sim.nodes[n["B1"]]["tier"]
	var sent := {"at": -99.0}
	play(d, sim, "attack", func(t):                            # gather, then hit back with both vats
		var mine: float = sim.nodes[n["N1"]]["units"] + sim.nodes[n["H"]]["units"]
		var busy := sim.hordes.any(func(h): return h["owner"] == "A")
		if not busy and t - float(sent["at"]) > 3.0 and mine > sim.nodes[n["B1"]]["units"] + 12.0 * Rules.SCALE:
			sent["at"] = t
			sim.send(n["N1"], n["B1"], 1.0)
			sim.send(n["H"], n["B1"], 1.0))
	check(sim.nodes[n["B1"]]["tier"] == tier0 - 1, "L3: the captured vat dropped a tier (T%d -> T%d)" % [tier0, sim.nodes[n["B1"]]["tier"]])
	play(d, sim, "alive", func(t): if first(t): d.press_button())
	check(d.state == "complete", "L3 complete")


# ------------------------------------------------------------------ L4 RELAYS
func test_l4() -> void:
	var r := make(4)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	var R: int = n["R"]
	check(sim.nodes[R]["owner"] == "A" and sim.nodes[R]["relay"] == "rotation", "L4 staged: A holds the rotation relay")
	check(d.preview_relay == R, "L4: the relay-outcome preview stays up on R")
	for i in range(int(10.0 / DT)):
		tick(d, sim)
	check(d.step_i == 0, "L4 negative: no tap, no pass")
	play(d, sim, "inspect", func(t): d.ui_inspector = R)
	play(d, sim, "fire", func(t): if first(t): check(sim.fire_relay(R), "L4: double-tap fires the relay"))
	play(d, sim, "warning", func(t): if first(t): d.press_button())
	var st := {"fired": false, "slow_early": false, "pred": -1.0, "fling": -1}
	var catch_step := func(t):                                  # the player fires the moment the prompt shows
		var hid := d.catch_line()
		if hid >= 0 and d.time_scale <= 0.25 + 0.001 and deck_metres(sim, hid, R) <= 0.0:
			st["slow_early"] = true
		if not st["fired"] and hid >= 0 and d.catch_prompt():
			st["fired"] = sim.fire_relay(R)
		if sim.nodes[R]["relay_phase"] == "warning" and sim.nodes[R]["relay_t"] <= DT * d.time_scale + 0.001 and hid >= 0:
			st["pred"] = deck_metres(sim, hid, R) / Rules.metres_per_unit()
	var k := d.step_i
	var t := 0.0
	while d.step_i == k and t < 90.0:
		d.step(DT)
		catch_step.call(t)
		sim.step(DT * d.time_scale)
		for ev in sim.fx_events:
			d.on_event(ev)
			if ev["type"] == "fling" and ev["seat"] == "B":
				st["fling"] = int(ev["units"])
		sim.fx_events.clear()
		t += DT
	check(d.step_i == k + 1, "L4 'prompt' passes within 90 s (%.1f s)" % t)
	check(st["slow_early"], "L4: 0.25x before the rival line is on the relay deck")
	check(int(st["fling"]) >= 5, "L4: a fire at the prompt flings >= 5 rival units on the first line (%d)" % int(st["fling"]))
	check(int(d._log.filter(func(e): return e.get("type") == "fling").size()) == 1, "L4: caught on the first try")
	check(st["pred"] > 0.0 and absf(float(st["fling"]) - Rules.shown(st["pred"])) <= 2.0,
			"L4: the fling is the share that was on the deck when it moved (%d vs %d)" % [int(st["fling"]), Rules.shown(st["pred"])])
	play(d, sim, "waterfall", wait)
	check(d.state == "complete", "L4 complete")
	# a miss: nobody fires - three lines, then "Timing takes practice" and the step passes
	var m := make(4)
	var dm: TutorialDirector = m[0]
	var sm: Sim = m[1]
	dm.skip_step()
	dm.skip_step()
	dm.skip_step()
	var tt := 0.0
	while dm.step_i == 3 and tt < 120.0:
		tick(dm, sm)
		tt += DT
	check(dm.step_i == 4 and sm.nodes[dm.names["R"]]["owner"] == "A", "L4 negative: three missed lines pass the step without a fling, R never falls (%.0f s)" % tt)


# ------------------------------------------------------------------ L5 RELAY KINDS
func test_l5() -> void:
	var r := make(5)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	for i in range(int(8.0 / DT)):                             # negative: the line comes, nobody pulls
		tick(d, sim)
	check(d.step_i == 0, "L5 negative: the retract step does not pass on its own")
	for key in ["retract", "switch", "remote"]:
		var relay: int = n[{"retract": "RT", "switch": "SW", "remote": "RC"}[key]]
		var st := {"fired": false, "slow_early": false}
		play(d, sim, key, func(t):
			var hid := d.catch_line()
			if hid >= 0 and d.time_scale <= 0.25 + 0.001 and deck_metres(sim, hid, relay) <= 0.0:
				st["slow_early"] = true
			if not st["fired"] and hid >= 0 and d.catch_prompt():
				st["fired"] = sim.fire_relay(relay))
		check(st["slow_early"], "L5 %s: 0.25x before the rival line is on the deck" % key)
		check(st["fired"], "L5 %s: fired with the rival on its deck" % key)
		var fell := 0
		for ev in d._log:
			if ev.get("type") == "fall" and ev.get("seat") == "B" and int(ev.get("relay", -1)) == relay:
				fell += int(ev.get("shown", 0))
		check(fell >= 1, "L5 %s: rival units fell with the deck (%d)" % [key, fell])
	play(d, sim, "own", func(t): if first(t): d.press_button())
	check(d.state == "complete", "L5 complete")


# ------------------------------------------------------------------ L6 RELAY WORKS
func test_l6() -> void:
	var r := make(6)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	play(d, sim, "inspect", func(t): d.ui_inspector = n["R1"])
	for i in range(int(12.0 / DT)):
		tick(d, sim)
	check(d.step_i == 1, "L6 negative: no LASER order, no laser step pass")
	play(d, sim, "laser", func(t): if first(t): check(sim.structure_order("A", "build", n["R1"], {"kind": "laser"})[0], "L6: LASER builds"))
	var lost0: float = sim.combat_losses.get("B", 0.0)
	play(d, sim, "burst", wait)
	check(sim.combat_losses.get("B", 0.0) - lost0 > 0.0 and sim.nodes[n["R1"]]["owner"] == "A", "L6: the laser burst killed rival crews, R1 held")
	play(d, sim, "forge", func(t): if first(t): sim.structure_order("A", "build", n["R2"], {"kind": "forge"}))
	check(sim.has_forge("A"), "L6: FORGE ONLINE (the attack and defence bonus)")
	play(d, sim, "hub", func(t): if first(t): sim.structure_order("A", "build", n["R3"], {"kind": "monster_hub"}))
	check(d.allow("launch_monster", n["R3"], {"to": n["M1"]}) != "" and d.allow("launch_monster", n["R3"], {"to": n["M2"]}) == "",
			"L6: the monster goes to the lane's end (other targets: Not yet)")
	check(n["M2"] in sim.monster_reach(n["R3"]), "L6: the lane's end is within the monster's reach")
	check(d.gesture()[0] == ["press", "monster_icon:%d" % n["R3"], -1], "L6: the hand presses the monster over its hub first")
	d.ui_monster_from = n["R3"]                                 # (the icon armed the launch)
	check(d.gesture()[0] == ["tap", n["M2"], -1], "L6: then the hand taps the lane's end")
	play(d, sim, "send", func(t): if first(t): check(sim.structure_order("A", "launch_monster", n["R3"], {"to": n["M2"]})[0], "L6: the monster launches"))
	play(d, sim, "take", wait)
	var kicked := 0.0
	for ev in d._log:
		if ev.get("type") == "monster_kick" and ev.get("seat_hit") == "B":
			kicked += float(ev["units"])
	check(sim.nodes[n["M2"]]["owner"] == "A", "L6: the monster took the lane's end")
	check(kicked > 0.0, "L6: the monster kicked rival crews off (%d)" % Rules.shown(kicked))
	play(d, sim, "cooldown", func(t): if first(t): d.press_button())
	check(d.state == "complete", "L6 complete")


# ------------------------------------------------------------------ L7 LAST STAND
func test_l7() -> void:
	var r := make(7)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	check(d.allow("send", n["H"], {"to": n["BH"]}) != "", "L7: no attacks on the rival before the last platform")
	var ls := {"at": -1.0}
	for i in range(int(3.0 / DT)):                             # reading the reveal: the first wave's countdown waits
		tick(d, sim)
		if ls["at"] < 0.0 and sim.last_stand_active:
			ls["at"] = d.lesson_t - DT
	check(sim.last_stand_active and sim.last_stand_warn_t >= Rules.LAST_STAND_WARNING - DT - 0.001,
			"L7: the Last Stand is on and its first countdown holds while the reveal card is up")
	play(d, sim, "reveal", func(t): if first(t): d.press_button())
	play(d, sim, "evacuate", func(t):
		if first(t):
			sim.send(n["H"], n["I1"], 1.0)
			sim.send(n["A1"], n["I2"], 1.0)
			sim.send(n["A2"], n["I2"], 1.0)
		if ls["at"] < 0.0 and sim.last_stand_active:
			ls["at"] = d.lesson_t
			for nm in ["H", "A1", "A2"]:
				if sim.nodes[n[nm]]["owner"] == "A":
					sim.send(n[nm], n["I1"], 1.0))
	check(absf(float(ls["at"]) - float(d.L["last_stand_at"])) <= DT * 2.0, "L7: the Last Stand starts at the staged %.0f s (%.2f)" % [d.L["last_stand_at"], ls["at"]])
	check(sim.events.any(func(e): return e["type"] == "last_stand" and absf(float(e["t"]) - Rules.LAST_STAND_TIME) < 0.01),
			"L7: the clock reads %s when the Last Stand starts" % TutorialDirector._mmss(Rules.LAST_STAND_TIME))
	check(not sim.eliminated.has("A") and sim.nodes.any(func(x): return x["owner"] == "A" and not sim.collapsed.get(x["id"], false)),
			"L7: evacuating to the centre kept A alive through the ring's fall")
	play(d, sim, "vls", func(t): if first(t):
		check(sim.very_last_stand_active and absf(sim.very_last_stand_gap - d.vls_gap()) < 0.01, "L7: the Very Last Stand runs at once, gap from the lesson table")
		check(sim.time >= Rules.VERY_LAST_STAND_TIME - 0.01 and sim.time < Rules.VERY_LAST_STAND_TIME + 1.0, "L7: the clock reads %s at the Very Last Stand" % TutorialDirector._mmss(Rules.VERY_LAST_STAND_TIME))
		check(sim.match_hard_end == INF, "L7: the 7:00 end can't cut the lesson short")
		d.press_button())
	if d.state != "complete":
		play(d, sim, "hold", func(t):
			for x in sim.nodes:                               # the player: off a warned platform, onto the next one
				if x["owner"] == "A" and sim.is_warned(x["id"]) and x["units"] > 1.0:
					for y in sim.nodes:
						if y["id"] != x["id"] and not sim.collapsed.get(y["id"], false) and not sim.is_warned(y["id"]):
							sim.send(x["id"], y["id"], 1.0)
							break, 90.0)
	check(d.state == "complete" and sim.winner == "A", "L7: VICTORY on the last platform")
	# the Very Last Stand on its own: down to one platform (a 0.1 s gap, before the end check runs at 1 s)
	var r2 := make(7)
	var s2: Sim = r2[1]
	s2.start_very_last_stand_now(0.1)
	while s2.time < 0.98:
		s2.step(DT)
	var left := s2.nodes.filter(func(x): return not s2.collapsed.get(x["id"], false)).size()
	check(left == 1, "L7: the Very Last Stand drops the survivors one by one to one platform (%d left)" % left)
	var r3 := make(1)
	check(not (r3[1] as Sim).vls_enabled, "the Very Last Stand stays off in the other lessons")


func test_l7_seeds() -> void:
	## The Very Last Stand's picks are random: whichever node drops first, a player who evacuates to the centre
	## and then follows the hand (off the warned node, onto the one that stays) wins.
	var wins := 0
	var seeds := [1, 2, 3, 4, 5, 6, 8, 9]
	for sd in seeds:
		var r := make(7, sd)
		var d: TutorialDirector = r[0]
		var sim: Sim = r[1]
		var n: Dictionary = d.names
		d.press_button()
		tick(d, sim)
		sim.send(n["H"], n["I1"], 1.0)
		sim.send(n["A1"], n["I2"], 1.0)
		sim.send(n["A2"], n["I2"], 1.0)
		var t := 0.0
		while d.state in ["running", "interlude"] and t < 200.0:
			var key := str(d.L["steps"][d.step_i]["key"])
			if key == "vls":
				d.press_button()
			if key == "evacuate":
				for nm in ["H", "A1", "A2"]:
					if sim.nodes[n[nm]]["owner"] == "A" and sim.nodes[n[nm]]["units"] > 2.0 * Rules.SCALE and sim.nodes[n[nm]]["streaming"].is_empty():
						sim.send(n[nm], n["I2"], 1.0)
			var mv := d._vls_move()
			if not mv.is_empty() and sim.nodes[int(mv[0])]["streaming"].is_empty():
				sim.send(int(mv[0]), int(mv[1]), 1.0)
			tick(d, sim)
			t += DT
		if d.state == "complete" and sim.winner == "A":
			wins += 1
	check(wins == seeds.size(), "L7: the Very Last Stand is winnable on every seed (%d / %d, gap %.0f s)" % [wins, seeds.size(), TutorialDirector.new(7).vls_gap()])


# ------------------------------------------------------------------ L8 SKILLS
func test_l8() -> void:
	var faction := "vex"
	var r := make(8)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	check(sim.abilities_on and sim.skill_id("A", "active") == "surge" and sim.skill_id("A", "map") == "demolish"
			and sim.skill_id("A", "ultimate") == "rewire", "L8: abilities on, Surge + Demolish + VEX's Rewire")
	check(sim.cooldown("A", "active") <= 0.0 and sim.cooldown("A", "map") <= 0.0, "L8: the skills stand ready")
	for i in range(int(8.0 / DT)):
		tick(d, sim)
	check(d.step_i == 0, "L8 (%s) negative: no cast, no pass" % faction)
	play(d, sim, "surge", func(t):
		for h in sim.hordes:
			if h["owner"] == "A" and sim.cast_check("A", "active", h["id"]) == "":
				sim.cast("A", "active", h["id"])
				break)
	play(d, sim, "demolish", func(t):
		for h in sim.hordes:
			if h["owner"] != "B":
				continue
			for sp in h["spans"]:
				if h["s"] >= sp["s0"] + 2.0 and h["s"] <= sp["s1"] and sim.cast_check("A", "map", sp["edge"]) == "":
					sim.cast("A", "map", sp["edge"])
					return)
	play(d, sim, "ultimate", func(t):
		var ts := sim.targets_for("A", "ultimate")
		if not ts.is_empty():
			sim.cast("A", "ultimate", ts[0]))
	play(d, sim, "armies", func(t): if first(t): d.press_button())
	check(d.state == "complete", "L8 (%s) complete" % faction)


# ------------------------------------------------------------------ L9 FIRST MATCH (staged mid-match)
func _stage_l9(d: TutorialDirector, sim: Sim) -> void:
	var R: int = d.names["R"]
	var a_side := [d.names["H"], 1, 2, 3, R]
	var b_side := [d.names["BH"], 8, 9, 10]
	for x in sim.nodes:
		if x["id"] in a_side:
			x["owner"] = "A"
			x["units"] = 30.0 * Rules.SCALE
		elif x["id"] in b_side:
			x["owner"] = "B"
			x["units"] = 25.0 * Rules.SCALE


func test_l9() -> void:
	var r := make(9)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var R: int = d.names["R"]
	check(R >= 0 and sim.nodes[R]["relay"] != "", "L9: T-02's relay found without lesson names")
	check(d.card()["visible"] and d.card()["text"] == TutorialDirector.line("L9.start"), "L9: the one opening card")
	check(sim.skill_id("A", "active") == "surge" and sim.skill_id("A", "map") == "demolish", "L9: VEX with Surge + Demolish (not the ARMIES preset)")
	var low_ok := true
	for x in sim.nodes:
		if x["owner"] == "" and Sim.has_vat(x) and Rules.shown(x["units"]) != int(TutorialDirector.L9_NEUTRALS[int(x["tier"])]):
			low_ok = false
	check(low_ok, "L9: the neutrals start low %s" % str(TutorialDirector.L9_NEUTRALS))
	var probe := make(9)
	var ps: Sim = probe[1]
	for x in ps.nodes:
		if x["owner"] == "" and Sim.has_vat(x):
			x["units"] = 1.0
	for i in range(int(60.0 / DT)):
		ps.step(DT)
	var capped := true
	for x in ps.nodes:
		if x["owner"] == "" and Sim.has_vat(x) and x["units"] > float(TutorialDirector.L9_NEUTRALS[int(x["tier"])]) * Rules.SCALE + 0.01:
			capped = false
	check(capped, "L9: a neutral regrows only to its staged garrison")
	_stage_l9(d, sim)
	var st := {"fired": false, "slow_early": false, "prompted": false}
	var t := 0.0
	while d.state != "complete" and t < 120.0:
		d.step(DT)
		var hid := d.catch_line()
		if hid >= 0 and str(d._match.get("phase", "")) == "push" and d.time_scale <= 0.25 + 0.001 and deck_metres(sim, hid, R) <= 0.0:
			st["slow_early"] = true
		if d.catch_prompt():
			st["prompted"] = true
		if not st["fired"] and d.catch_prompt():               # the player fires the moment the prompt shows
			st["fired"] = sim.fire_relay(R)
		sim.step(DT * d.time_scale)
		for ev in sim.fx_events:
			d.on_event(ev)
		sim.fx_events.clear()
		t += DT
	check(st["prompted"], "L9: the push reached the relay deck and the prompt fired")
	check(st["slow_early"], "L9: 0.25x before the push is on the relay deck")
	check(d.state == "complete" and bool(d.result.get("relay_kill", false)),
			"L9: firing under the push is a RELAY KILL and ends the tutorial on the spot (%.0f s, %d units)" % [t, int(d.result.get("kill_units", 0))])
	check(d.result.get("final", false), "L9: the final (TRAINING COMPLETE) screen follows")
	# a miss: the push crosses, the match goes on, nothing completes
	var m := make(9)
	var dm: TutorialDirector = m[0]
	var sm: Sim = m[1]
	_stage_l9(dm, sm)
	var tt := 0.0
	var pushed := false
	while tt < 90.0 and str(dm._match.get("phase", "")) != "done":
		tick(dm, sm)
		pushed = pushed or str(dm._match.get("phase", "")) == "push"
		tt += DT
	check(pushed and str(dm._match.get("phase", "")) == "done" and dm.state != "complete",
			"L9 negative: a missed push hands the match back, the lesson does not complete (%.0f s)" % tt)
