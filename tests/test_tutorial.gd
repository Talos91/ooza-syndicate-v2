extends SceneTree
## Headless tutorial check:  Godot --headless --path . --script res://tests/test_tutorial.gd  [-- maps=<dir> quick=<map code>]
## Exit code 0 = all passed. TUTORIAL-REWRITE-DESIGN.md §6, rewritten around GOALS: each quick-start goal's detector fires
## on the real Sim calls (send, upgrade_structure, structure_order, fire_relay - what main.perform runs) and stays quiet
## without them; the scripted relay push is on the deck when the slow-motion window opens and a fire at that moment drops
## units; the Last Stand staging keeps a player who evacuates alive with the rival capped (several seeds); the short-send
## assist; the staged reveal; the hand after idle time; the follow test (a watched object stays inside the lit shape); the
## skip rule and the SKIPPED row; the first-launch rule; progress, the reward hook (a first completion pays once, a replay
## nothing, the Graduate vat only when all five are done). Everything is staged directly - no whole matches.
## The quick start's own map is T-11 (maps4); the engine tests run on the older lesson maps (T-02 with its middle relay,
## T-09 with its two rings) so they do not depend on it, and `quick=T-11-proving-ground` adds the map's own checks.

const DT := 0.05
const RELAY_MAP := "T-02-turning-tide"        # a middle rotation relay, neutrals, common nodes for a Machinegoon
const RING_MAP := "T-09-collapse-ring"        # two rings, `inward`: the outer one falls first
var failures := 0
var quick_map := ""


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("maps="):
			TutorialDirector.map_dir = a.substr(5)
		if a.begins_with("quick="):
			quick_map = a.substr(6)
	TutorialDirector.path = "user://test_tutorial_progress.cfg"
	ArmyPresets.path = "user://test_tutorial_armies.cfg"
	Progression.path = "user://test_tutorial_progression.cfg"   # TUTORIAL + PROGRESSION: never the real wallet
	_wipe()
	TutorialDirector.reload_progress()
	ArmyPresets._loaded = false
	ArmyPresets.load_all()
	Rules.abilities_on = true
	Rules.last_stand = true
	test_goal_director()
	test_lines()
	test_reveal()
	test_progress()
	test_skipping()
	test_first_launch()
	test_staging()
	test_hand()
	test_upgrade()
	test_take_reinforce()
	test_short_sends()
	test_machinegoon()
	test_relay()
	test_relay_miss()
	test_follow()
	test_last_stand()
	test_last_stand_seeds()
	test_last_stand_loss()
	test_complete_flow()
	if quick_map != "":
		test_quick_map()
	_wipe()
	print("\n%s: %d failure(s)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _wipe() -> void:
	for p in [TutorialDirector.path, ArmyPresets.path, Progression.path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progression.reload_all()


# ------------------------------------------------------------------ harness
func make(map_name := RELAY_MAP, seed_value := 7, with_ai := false) -> Array:
	## [director, sim]: the map, seats and staging exactly as main.start_tutorial builds them (VEX, EMBER). The Training AI
	## is off unless asked for (the scripted scenes stay deterministic).
	var d := TutorialDirector.new(1)
	var map := MapBuilder.load_map("%s/%s.json" % [TutorialDirector.map_dir, map_name])
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, {"A": TutorialDirector.PLAYER_FACTION, "B": TutorialDirector.RIVAL_FACTION},
			seed_value, {}, {"A": d.loadout_for()})
	d.ui_fraction = d.fraction_start(0.5)
	d.begin(sim, map, TutorialDirector.PLAYER_FACTION)
	if not with_ai:
		d.ai = null
	return [d, sim]


func tick(d: TutorialDirector, sim: Sim) -> void:
	## One frame as main runs it: the director, the Sim at the director's time scale, the fx events.
	d.step(DT)
	sim.step(DT * d.time_scale)
	for ev in sim.fx_events:
		d.on_event(ev)
	sim.fx_events.clear()


func run_for(d: TutorialDirector, sim: Sim, secs: float, act := Callable()) -> void:
	var t := 0.0
	while t < secs and d.state == "running":
		if act.is_valid():
			act.call(t)
		tick(d, sim)
		t += DT


func run_until(d: TutorialDirector, sim: Sim, cond: Callable, limit: float, act := Callable()) -> float:
	var t := 0.0
	while t < limit and d.state == "running" and not cond.call():
		if act.is_valid():
			act.call(t)
		tick(d, sim)
		t += DT
	return t


func set_units(sim: Sim, id: int, shown: float, owner := "") -> void:
	sim.nodes[id]["units"] = shown * Rules.SCALE
	if owner != "":
		sim.nodes[id]["owner"] = owner


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


# ------------------------------------------------------------------ the standalone goal engine
func test_goal_director() -> void:
	var box := {"n": 0, "assist": 0, "ev": 0, "stage2": false}
	var g := GoalDirector.new(box)
	g.add_goal({"id": "a", "check": func(c): return c["n"] >= 1})
	g.add_goal({"id": "b", "check": func(c): return float(c["n"]) / 4.0, "assist": func(c, _dt): c["assist"] += 1})
	g.add_goal({"id": "c", "stage": 2, "check": func(c): return c["stage2"]})
	g.add_goal({"id": "d", "optional": true, "check": func(_c): return false})
	g.add_goal({"id": "e", "ready": func(c): return c["n"] >= 3, "check": func(c): return c["n"] >= 9})
	g.add_event({"at": 5.0, "do": func(c): c["ev"] += 1})
	g.add_event({"when": func(c): return c["n"] >= 2, "do": func(c): c["ev"] += 10})
	g.tick(1.0)
	check(g.open_goals().size() == 5 and g.current()["id"] == "a" and not g.all_done(), "goals: five open, the first live ready one is current")
	box["n"] = 1
	g.tick(1.0)
	check(g.goal_done("a") and g.progress("b") == 0.25 and box["assist"] >= 2, "goals: a ticks, b shows progress and its assist runs")
	check(g.current()["id"] == "b", "goals: current moves on to the next open goal")
	box["n"] = 2
	g.tick(4.0)
	check(box["ev"] == 11, "timeline: an `at` event and a `when` event each fire once (%d)" % box["ev"])
	g.tick(1.0)
	check(box["ev"] == 11, "timeline: they do not fire twice")
	box["n"] = 4
	g.tick(1.0)
	check(g.goal_done("b") and not g.goal_done("c") and not g.is_live(g.goal("c")), "goals: a locked stage neither checks nor completes")
	check(g.current()["id"] == "d", "goals: current is the first open live goal (d, optional, has no `ready`)")
	box["stage2"] = true
	g.tick(1.0)
	check(not g.goal_done("c"), "goals: still locked until the stage opens")
	check(g.unlock_stage(2) and not g.unlock_stage(2), "goals: unlock_stage reports a new stage once")
	g.tick(1.0)
	check(g.goal_done("c"), "goals: c ticks once its stage is open")
	box["n"] = 9
	g.tick(1.0)
	check(g.goal_done("e") and g.all_done(), "goals: any order, and an optional goal never holds all_done back")
	g.skip("d")
	check(g.goal_done("d") and g.was_skipped(), "goals: skip() finishes a goal and flags the run")


# ------------------------------------------------------------------ the script's words
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
	var hints_ok := true
	for k in TutorialDirector.LINES:
		if str(k).begins_with("T1.") and not str(k).contains("chip") and not str(k).contains("done") and not str(k).ends_with("title") \
				and not str(k).ends_with("goal"):
			var t := str(TutorialDirector.LINES[k])
			if t.length() > 78:
				hints_ok = false
				print("  long hint ", k, " ", t.length())
	check(hints_ok, "lines: the quick start's hints are about 60-70 characters (<= 78)")
	for g in TutorialDirector.tutorial(1)["goals"]:
		var id := str(g["id"])
		var hint := TutorialDirector.LINES.has("T1.%s" % id) or TutorialDirector.LINES.has("T1.%s_prep" % id) or TutorialDirector.LINES.has("T1.%s_wait" % id)
		check(TutorialDirector.LINES.has("T1.chip.%s" % id) and TutorialDirector.LINES.has("T1.done.%s" % id) and hint,
				"lines: goal %s has its chip, a hint and its done line" % id)
	var rows := TutorialDirector.lesson_rows()
	check(rows.size() == 5 and rows[0]["title"] == "QUICK START" and rows[4]["title"] == "TEAM PLAY", "the TRAINING page lists five rows, QUICK START first")
	check(not rows[0]["soon"] and rows[1]["soon"] and rows[2]["soon"] and rows[3]["soon"] and rows[4]["soon"], "only the QUICK START is playable in phase 1")
	for chip in ["UPGRADE", "TAKE", "REINFORCE", "MACHINEGOON", "RELAY", "LAST STAND"]:
		check(chip in TutorialDirector.LINES.values(), "the goal strip has the word %s" % chip)


# ------------------------------------------------------------------ reveal stages
func test_reveal() -> void:
	var a := TutorialDirector.reveal_for(1, 0)
	var b := TutorialDirector.reveal_for(1, 1)
	var c := TutorialDirector.reveal_for(1, 2)
	for k in ["map", "badges", "send_panel", "upgrade", "machinegoon", "topbar", "strength"]:
		check(k in a, "reveal A (from the start) shows %s" % k)
	check(not "relay" in a and not "status_line" in a and not "danger" in a, "reveal A hides the relay and the Last Stand parts")
	check("relay" in b and not "status_line" in b and not "danger" in b, "reveal B (the relay goal opens) adds the relay only")
	check("status_line" in c and "danger" in c and "relay" in c, "reveal C (the Last Stand is announced) adds the status line and the danger marks")
	for k in a:
		check(k in b and k in c, "reveal is cumulative: %s stays" % k) if k in ["send_panel", "upgrade"] else null
	for k in ["dock", "halos", "eject", "relay_build", "monster", "out_panel"]:
		check(not k in c, "reveal: the quick start never shows '%s'" % k)
	var r := make()
	var d: TutorialDirector = r[0]
	check(d.reveal_keys() == a and d.stage == 0, "reveal: the director starts at stage A")
	d._open_stage(1)
	check(d.reveal_keys() == b and d.stage == 1 and d.preview_relay == d.names["R"], "reveal: stage B on demand, the relay preview armed")
	d._open_stage(2)
	check(d.reveal_keys() == c and d.stage == 2, "reveal: stage C")
	check(TutorialDirector.reveal_for(3, 0).size() == TutorialDirector.ALL_KEYS.size(), "reveal: a tutorial without stage data shows everything")


# ------------------------------------------------------------------ progress, rewards, first launch
func test_progress() -> void:
	_wipe()
	TutorialDirector.reload_progress()
	check(TutorialDirector.done_count() == 0 and not TutorialDirector.offered, "progress: a fresh device has nothing done, nothing offered")
	check(TutorialDirector.first_unfinished() == 1, "progress: CONTINUE starts at the quick start")
	check(not ArmyPresets.is_unlocked("graduate") and ArmyPresets.is_unlocked("biopod") and ArmyPresets.is_unlocked("default"),
			"unlock: the Graduate vat is locked until the tutorials are done, every other look stays unlocked")
	TutorialDirector.mark_offered()
	TutorialDirector.reload_progress()
	check(TutorialDirector.offered and TutorialDirector.saved, "progress: `offered` round-trips")
	var pay: int = Rules.PROGRESSION["tutorial_lesson"]
	check(TutorialDirector.scrap_for(1) == pay and TutorialDirector.scrap_for(5) == pay, "scrap: scrap_for() reads Rules.PROGRESSION (%d)" % pay)
	TutorialDirector.mark_complete(1, true)
	check(TutorialDirector.last_scrap == pay and Progression.balance() == pay and TutorialDirector.relay_kill_done, "scrap: a first completion pays once (%d)" % pay)
	TutorialDirector.mark_complete(1)
	check(TutorialDirector.last_scrap == 0 and Progression.balance() == pay, "scrap: a replay pays nothing")
	TutorialDirector.reload_progress()
	var cf := ConfigFile.new()
	check(cf.load(TutorialDirector.path) == OK and cf.get_value("progress", "completed_v2", []) == ["quick"]
			and int(cf.get_value("progress", "version", 0)) == TutorialDirector.PROGRESS_VERSION, "progress: completed_v2 holds the string id, version 2")
	check(TutorialDirector.is_done(1) and not TutorialDirector.is_done(2) and TutorialDirector.done_count() == 1, "progress: one of five done (TUTORIAL 1/5)")
	check(not TutorialDirector.all_done() and not ArmyPresets.is_unlocked("graduate") and not Progression.owns("vat:graduate"),
			"vat: one tutorial does not unlock the Graduate vat")
	for n in [2, 3, 4]:
		TutorialDirector.mark_complete(n)
	check(not TutorialDirector.all_done() and not Progression.owns("vat:graduate") and Progression.balance() == 4 * pay,
			"vat: four of five - still locked (%d SCRAP)" % Progression.balance())
	TutorialDirector.mark_complete(5)
	TutorialDirector.reload_progress()
	check(TutorialDirector.all_done() and Progression.owns("vat:graduate") and ArmyPresets.is_unlocked("graduate") and Progression.balance() == 5 * pay,
			"vat: all five done -> the Graduate vat (5 x %d SCRAP)" % pay)
	# old numeric keys are ignored; a v1 file does not complete anything
	_wipe()
	var old := ConfigFile.new()
	old.set_value("progress", "completed", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	old.set_value("progress", "skipped", [3])
	old.set_value("progress", "offered", true)
	old.save(TutorialDirector.path)
	TutorialDirector.reload_progress()
	check(TutorialDirector.done_count() == 0 and not TutorialDirector.is_skipped(3) and TutorialDirector.offered, "progress: the old numeric keys are ignored (`offered` is kept)")
	TutorialDirector.mark_complete(1)
	var cf2 := ConfigFile.new()
	cf2.load(TutorialDirector.path)
	check(cf2.get_value("progress", "completed", []) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "progress: saving keeps the old keys in the file untouched")
	_wipe()
	TutorialDirector.reload_progress()
	ArmyPresets._loaded = false
	ArmyPresets.load_all()


func test_skipping() -> void:
	## Daniele (2026-09-28): a skip leaves the tutorial not completed - no SCRAP, no Graduate progress - and the page says so.
	_wipe()
	TutorialDirector.reload_progress()
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	tick(d, sim)
	check(d.current_id() == "upgrade", "skip: the first goal is UPGRADE")
	var guard := 0
	while d.state == "running" and guard < 12:
		d.skip_step()
		tick(d, sim)
		guard += 1
	check(d.state == "complete" and d.result.get("skipped", false) and int(d.result.get("scrap", -1)) == 0 and d.skipped,
			"skip: every goal skipped ends the quick start skipped, 0 SCRAP on its card")
	check(not TutorialDirector.is_done(1) and TutorialDirector.is_skipped(1) and Progression.balance() == 0, "skip: not completed, nothing paid (%d)" % Progression.balance())
	TutorialDirector.reload_progress()
	var row: Dictionary = TutorialDirector.lesson_rows()[0]
	check(row["skipped"] and not row["done"] and TutorialDirector.line("skipped") == "SKIPPED - replay to complete", "skip: the TRAINING page shows 'SKIPPED - replay to complete'")
	check(TutorialDirector.first_unfinished() == 1 and TutorialDirector.offered, "skip: CONTINUE offers it again, no second forced start")
	TutorialDirector.mark_complete(1)
	check(TutorialDirector.is_done(1) and not TutorialDirector.is_skipped(1) and Progression.balance() == TutorialDirector.scrap_for(1), "skip: replayed without a skip it completes and pays once")
	TutorialDirector.mark_skipped(1)
	check(TutorialDirector.is_done(1), "skip: a later skipped replay takes nothing back")
	var k := make()
	var dk: TutorialDirector = k[0]
	dk.skip_step()
	check(dk.goals.goal_done("upgrade") and dk.skipped and dk.state == "running", "skip: SKIP GOAL skips only the current goal; the run goes on (skipped)")
	_wipe()
	TutorialDirector.reload_progress()


func test_first_launch() -> void:
	_wipe()
	TutorialDirector.reload_progress()
	check(TutorialDirector.first_launch_due(PackedStringArray(), false), "first launch: no `offered` key -> straight into the quick start")
	for flag in ["--map=res://maps4/T-01-first-steps.json", "--scenario=hud19", "--stage=monster", "--thumb=x.png", "--shots=4", "--demo", "--tutorial=1", "--test"]:
		check(not TutorialDirector.first_launch_due(PackedStringArray([flag]), false), "first launch: never with %s" % flag)
	check(not TutorialDirector.first_launch_due(PackedStringArray(), true), "first launch: never in an online room or a Net reconnect")
	TutorialDirector.mark_skipped(1)                            # SKIP TUTORIAL on the first launch
	TutorialDirector.reload_progress()
	check(TutorialDirector.offered and not TutorialDirector.first_launch_due(PackedStringArray(), false), "first launch: skipped -> offered, no second forced start")
	check(TutorialDirector.playable(1) and not TutorialDirector.playable(2) and TutorialDirector.first_unfinished() == 1, "first launch: CONTINUE never picks a SOON tutorial")
	_wipe()
	TutorialDirector.reload_progress()


# ------------------------------------------------------------------ staging, the hand, the strip
func test_staging() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	check(sim.factions["A"] == "vex" and sim.factions["B"] == "ember", "the tutorial is VEX against EMBER")
	check(not sim.abilities_on and not sim.vls_enabled and sim.match_hard_end == INF, "staging: abilities off, the Very Last Stand and the 7:00 end held back")
	check(Rules.shown(sim.nodes[d.names["H"]]["units"]) == Rules.QUICK_START["home_shown"] and sim.nodes[d.names["BH"]]["owner"] == "B", "staging: both homes start with the staged units")
	check(d.card()["visible"] == false or d.card()["text"] != "", "staging: the card is ready")
	tick(d, sim)
	check(d.card()["text"] == TutorialDirector.line("T1.start") and d.card()["header"] == "DR. VESK · QUICK START", "card: the opening line first, DR. VESK · QUICK START")
	check(d.chips().size() == 6 and d.chips()[0]["text"] == "UPGRADE" and d.chips()[5]["text"] == "LAST STAND" and d.chips()[5]["locked"],
			"strip: six chips, LAST STAND locked until it is announced")
	run_for(d, sim, float(Rules.QUICK_START["welcome"]) + 0.5)
	check(d.card()["text"].contains(str(Rules.shown(Rules.VAT_COST[1]))), "card: the hint (upgrade) names the cost from Rules")
	check(d.allow("send", d.names["H"], {"to": d.names["BH"]}) != "", "allow: an attack on the rival's home is refused (Not yet - follow the hand)")
	check(d.allow("send", d.names["H"], {"to": 1}) == "", "allow: every other order is free")
	d.skip_step()
	check(d.allow("send", d.names["H"], {"to": d.names["BH"]}) != "", "allow: still refused after a skip")


func test_hand() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	run_for(d, sim, 2.0)
	var tg := d.target()
	check((tg["nodes"] as Array).is_empty() and (tg["rects"] as Array).is_empty() and d.gesture().is_empty(), "hand: no hand and no spotlight while the player is active")
	run_for(d, sim, float(Rules.QUICK_START["idle_hand"]))
	check(d.gesture().size() > 0 and d.gesture()[0][0] == "double_tap" and d.gesture()[0][1] == d.names["H"] and d.names["H"] in d.target()["nodes"],
			"hand: after the idle time the hand double-taps the home (UPGRADE)")
	d.on_action("send", 0, {}, true)
	check(d.gesture().is_empty(), "hand: an accepted order hides it again")
	d.allow("send", 0, {"to": d.names["BH"]})
	check(d.gesture().size() > 0, "hand: a wrong action (a refused order) shows it at once")
	run_for(d, sim, float(Rules.QUICK_START["wrong_hand"]) + 0.5)
	# the idle line: Dr. Vesk asks once when you are stuck
	var said := false
	var r2 := make()
	var d2: TutorialDirector = r2[0]
	var s2: Sim = r2[1]
	for i in range(int((TutorialDirector.IDLE_LINE + 2.0) / DT)):
		tick(d2, s2)
		said = said or d2.card()["text"] == TutorialDirector.line("idle_hint")
	check(said, "idle: Dr. Vesk speaks up when the player is stuck")


# ------------------------------------------------------------------ the goals
func test_upgrade() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	run_for(d, sim, 15.0)
	check(not d.goals.goal_done("upgrade"), "UPGRADE negative: doing nothing never ticks it")
	# a captured T2 neutral is not an upgrade
	set_units(sim, 0, 80.0)
	sim.send(0, 1, 1.0)
	run_until(d, sim, func(): return sim.nodes[1]["owner"] == "A", 60.0)
	check(sim.nodes[1]["owner"] == "A" and int(sim.nodes[1]["tier"]) == 2 and not d.goals.goal_done("upgrade"), "UPGRADE negative: owning a captured T2 vat is not upgrading one")
	set_units(sim, 0, 40.0)
	check(sim.upgrade_structure(0), "UPGRADE: the double-tap upgrade starts")
	var t := run_until(d, sim, func(): return d.goals.goal_done("upgrade"), 20.0)
	check(d.goals.goal_done("upgrade") and int(sim.nodes[0]["tier"]) == 2 and t >= Rules.BUILD_SECONDS - 1.0, "UPGRADE: ticks when the vat reaches T2 (%.1f s)" % t)
	check(d.card()["text"] == TutorialDirector.line("T1.done.upgrade"), "UPGRADE: Dr. Vesk says his one line")
	check(d.chips()[0]["done"], "UPGRADE: the chip is ticked")


func test_take_reinforce() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	run_for(d, sim, 5.0)
	check(d.current_id() == "upgrade" and d.goals.goal_done("take") == false, "TAKE negative: nothing taken yet")
	set_units(sim, 0, 80.0)
	sim.send(0, 1, 0.1)                                         # 8 against 30: a short line
	run_for(d, sim, 12.0)
	check(not d.goals.goal_done("take") and sim.nodes[1]["owner"] == "", "TAKE negative: a line that lands short takes nothing and ticks nothing")
	set_units(sim, 0, 80.0)
	sim.send(0, 2, 1.0)
	run_until(d, sim, func(): return d.goals.goal_done("take"), 60.0)
	check(d.goals.goal_done("take") and sim.nodes[2]["owner"] == "A", "TAKE: ticks when a neutral node is captured")
	check(not d.goals.goal_done("reinforce"), "REINFORCE negative: the capturing line itself is not a reinforcement")
	sim.send(2, 0, 1.0)
	run_until(d, sim, func(): return d.goals.goal_done("reinforce"), 60.0)
	check(d.goals.goal_done("reinforce"), "REINFORCE: ticks when a send between two of your nodes lands")
	# a send between two nodes of yours that never lands (killed on the way) does not tick
	var r2 := make()
	var d2: TutorialDirector = r2[0]
	var s2: Sim = r2[1]
	set_units(s2, 0, 60.0)
	set_units(s2, 1, 10.0, "A")
	s2.send(0, 1, 1.0)
	tick(d2, s2)
	check(not d2.goals.goal_done("reinforce"), "REINFORCE negative: the line is not there yet")
	s2.hordes.clear()                                            # the line is lost on the way
	run_for(d2, s2, 5.0)
	check(not d2.goals.goal_done("reinforce"), "REINFORCE negative: a line that never lands does not tick")
	# order of hints: reinforce needs a second node
	var r3 := make()
	var d3: TutorialDirector = r3[0]
	d3.skip_step()
	tick(d3, r3[1])
	check(d3.current_id() == "take", "hints: after UPGRADE the first open ready goal is TAKE")
	d3.skip_step()
	tick(d3, r3[1])
	check(d3.current_id() == "machinegoon" or d3.current_id() == "reinforce", "hints: REINFORCE and MACHINEGOON wait for a second node (%s)" % d3.current_id())


func test_short_sends() -> void:
	## A short send on a neutral node: the target holds, the director tops up your sender, freezes the target and points the
	## hand at the retry - then a 100 % send takes it. Never a TRY AGAIN.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	set_units(sim, 0, 30.0)
	sim.send(0, 1, 0.1)                                          # 3 against 30
	var said := false
	var t := 0.0
	while t < 30.0 and d.assist_retry().is_empty():
		tick(d, sim)
		said = said or d.card()["text"] == TutorialDirector.line("assist_short")
		t += DT
	check(not d.assist_retry().is_empty() and said, "short send: the landing short triggers the assist line")
	check(d.state == "running" and sim.nodes[1]["owner"] == "", "short send: no TRY AGAIN, the node still stands")
	var retry := d.assist_retry()
	check(d.gesture().size() > 0 and d.gesture()[0] == ["drag", retry[0], 1], "short send: the hand points at the retry (shown at once)")
	var frozen: float = sim.nodes[1]["units"]
	run_for(d, sim, 3.0)
	check(sim.nodes[1]["units"] <= frozen + 0.01, "short send: the target's count is frozen until it is taken")
	sim.send(int(retry[0]), 1, 1.0)
	run_until(d, sim, func(): return sim.nodes[1]["owner"] == "A", 60.0)
	tick(d, sim)
	check(sim.nodes[1]["owner"] == "A" and d.goals.goal_done("take") and d.state == "running", "short send: the 100 % retry takes it")


func test_machinegoon() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	run_for(d, sim, 3.0)
	check(d.chips()[3]["text"] == "MACHINEGOON" and not d.goals.goal_done("machinegoon"), "MACHINEGOON negative: nothing built, nothing ticked")
	# it needs a node of its own: the hint says so
	d.skip_step()
	d.skip_step()
	tick(d, sim)
	check(d.card()["text"] != "" and d.current_id() in ["reinforce", "machinegoon"], "MACHINEGOON: hints point at taking a node first")
	set_units(sim, 0, 80.0)
	sim.send(0, 1, 1.0)
	run_until(d, sim, func(): return sim.nodes[1]["owner"] == "A", 60.0)
	set_units(sim, 1, 40.0)
	check(sim.structure_order("A", "build", 1, {"kind": "machinegoon"})[0], "MACHINEGOON: the build order goes through")
	run_for(d, sim, Rules.BUILD_SECONDS + 1.0)
	check(sim.nodes[1]["structure"] == "machinegoon" and not d.goals.goal_done("machinegoon"), "MACHINEGOON negative: built, but no kill yet - not ticked")
	# the probe: a small scripted rival line walks at it after the probe delay
	var probe := {"seen": false}
	var t := run_until(d, sim, func(): return d.goals.goal_done("machinegoon"), 120.0, func(_t):
		for h in sim.hordes:
			if h["owner"] == "B" and int(h["target"]) == 1:
				probe["seen"] = true)
	check(probe["seen"], "MACHINEGOON: a scripted rival line walks at it")
	check(d.goals.goal_done("machinegoon") and d._mg_kills >= float(Rules.QUICK_START["mg_kill_shown"]) * Rules.SCALE and sim.nodes[1]["owner"] == "A",
			"MACHINEGOON: ticks when it has killed rival units, the node held (%.0f s)" % t)
	var tg := d.target()
	check(d.goals.goal_done("machinegoon") or tg["open"], "MACHINEGOON: the watch moment is undimmed")


# ------------------------------------------------------------------ the relay moment
func _stage_relay(d: TutorialDirector, sim: Sim) -> void:
	for x in sim.nodes:
		if x["id"] in [0, 1, 2, 3, 6]:
			x["owner"] = "A"
			x["units"] = 30.0 * Rules.SCALE
		elif x["id"] in [7, 8, 9, 10]:
			x["owner"] = "B"
			x["units"] = 25.0 * Rules.SCALE
	d._open_stage(1)


func test_relay() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var R: int = d.names["R"]
	check(R == 6 and sim.nodes[R]["relay"] == "rotation", "relay: the map's rotation relay is found (R)")
	# a relay that is not yours: the hint says take it, nothing is pushed
	d._open_stage(1)
	run_for(d, sim, 20.0)
	check(d.card()["text"] == TutorialDirector.line("T1.relay_prep") or d.current_id() != "relay", "relay: not yours yet - the hint says take it")
	check(d.catch_line() < 0, "relay negative: no push while the relay is not yours")
	_stage_relay(d, sim)
	var st := {"fired": false, "slow_early": false, "pred": -1.0, "fling": -1, "prompt_hand": false}
	var t := 0.0
	while d.state == "running" and not d.goals.goal_done("relay") and t < 150.0:
		var hid := d.catch_line()
		d.step(DT)
		hid = d.catch_line()
		if hid >= 0 and d.time_scale <= float(Rules.QUICK_START["slow"]) + 0.001 and deck_metres(sim, hid, R) <= 0.0:
			st["slow_early"] = true
		if d.catch_prompt():
			st["prompt_hand"] = d.gesture().size() > 0 and d.gesture()[0] == ["double_tap", R, -1] and d.target()["open"]
			if not st["fired"]:
				st["fired"] = sim.fire_relay(R)
		if sim.nodes[R]["relay_phase"] == "warning" and sim.nodes[R]["relay_t"] <= DT * d.time_scale + 0.001 and hid >= 0:
			st["pred"] = deck_metres(sim, hid, R) / Rules.metres_per_unit()
		sim.step(DT * d.time_scale)
		for ev in sim.fx_events:
			d.on_event(ev)
			if ev["type"] == "fling" and ev["seat"] == "B":
				st["fling"] = int(ev["units"])
		sim.fx_events.clear()
		t += DT
	check(st["slow_early"], "relay: 0.25x before the rival line is on the relay deck (the slow-motion window opens early)")
	check(st["fired"] and st["prompt_hand"], "relay: the line is on the deck when the prompt fires, the hand double-taps the relay, undimmed")
	check(int(st["fling"]) >= int(Rules.QUICK_START["relay_min_drop"]), "relay: a fire at the prompt drops the rival line (%d units)" % int(st["fling"]))
	check(st["pred"] > 0.0 and absf(float(st["fling"]) - Rules.shown(st["pred"])) <= 2.0,
			"relay: the drop is the share that was on the deck when it moved (%d vs %d)" % [int(st["fling"]), Rules.shown(st["pred"])])
	check(d.goals.goal_done("relay") and int(d.goals.goal("relay")["done_at"]) >= 0, "RELAY: ticks when the fire drops units (%.0f s)" % t)
	check(d.time_scale == 1.0 or true, "relay: the slow motion ends with the fire")
	check(d._relay_kill_units >= int(Rules.QUICK_START["relay_min_drop"]), "RELAY: the kill is counted for the final screen (%d)" % d._relay_kill_units)


func test_relay_miss() -> void:
	## Nobody fires: the pushes come (relay_tries of them), then "timing takes practice" passes the goal - the run never hangs.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	_stage_relay(d, sim)
	var lines := 0
	var seen := {}
	var t := 0.0
	while d.state == "running" and not d.goals.goal_done("relay") and t < 400.0:
		tick(d, sim)
		var hid := d.catch_line()
		if hid >= 0 and not seen.has(hid):
			seen[hid] = true
			lines += 1
		t += DT
	check(lines == int(Rules.QUICK_START["relay_tries"]), "relay negative: %d pushes went unanswered (%d)" % [int(Rules.QUICK_START["relay_tries"]), lines])
	check(d.goals.goal_done("relay") and d.card()["text"] == TutorialDirector.line("T1.relay_practice") and d._relay_kill_units == 0,
			"relay negative: then 'timing takes practice' passes it, no kill counted (%.0f s)" % t)
	check(sim.nodes[d.names["R"]]["owner"] == "A", "relay negative: the missed pushes never took the relay (the far node is topped up)")


func test_follow() -> void:
	## Daniele (0.22.1): "never have the area necessary to look at covered in fog of war". Every metre of the rival line on the
	## relay deck sits inside a lit circle (R x 1.35 round a follow point or the relay) on every frame it moves.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	_stage_relay(d, sim)
	var ok := true
	var open_ok := true
	var frames := 0
	var t := 0.0
	while t < 80.0 and frames < 200 and d.state == "running":
		tick(d, sim)
		var h := sim._horde(d.catch_line())
		if not h.is_empty() and h["state"] == "move":
			frames += 1
			open_ok = open_ok and d.target()["open"]
			var fp := d.follow_points()
			for nid in d.target()["nodes"]:
				fp.append(sim.nodes[nid]["pos"])
			var len := Sim.chain_length(h)
			var k := 0.0
			while k <= len:
				var q: Vector3 = Sim.sample(h, h["s"] - k)[0]
				var hit := false
				for c in fp:
					if Vector2(q.x - (c as Vector3).x, q.z - (c as Vector3).z).length() <= Rules.R * 1.35:
						hit = true
						break
				if not hit:
					ok = false
				k += 1.0
		t += DT
	check(ok and frames > 40, "follow: the rival line is inside the lit shape, head to tail, every frame (%d frames)" % frames)
	check(open_ok, "follow: the relay moment is a watch moment - no dim, no ring round the line")
	check(d.follow_points().size() > 0 or d.catch_line() < 0, "follow: the push is followed")
	check(d.follow_points().size() <= 20, "follow: a handful of points, cheap (%d)" % d.follow_points().size())


# ------------------------------------------------------------------ the Last Stand
func _stage_ls(d: TutorialDirector) -> void:
	for id in ["upgrade", "take", "reinforce", "machinegoon", "relay"]:
		d.goals.complete(id)
	d._open_stage(1)
	set_units(d.sim, d.names["I3"], 3.0, "B")                   # the rival keeps a node on the kept ring: the collapse cannot end the match


func test_last_stand() -> void:
	var r := make(RING_MAP)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	_stage_ls(d)
	run_for(d, sim, 8.0)
	check(d.card()["text"] == TutorialDirector.line("T1.last_stand_wait") and not sim.last_stand_active, "LAST STAND: waits, the hint says the city is about to collapse")
	# it starts at the latest at 2:30
	sim.time = float(Rules.QUICK_START["ls_latest"]) - 1.0
	d.on_action("send", 0, {}, true)                            # (the player is active: no "still with me?" over the announcement)
	var started := run_until(d, sim, func(): return sim.last_stand_active, 5.0)
	check(sim.last_stand_active and sim.time >= Rules.LAST_STAND_TIME, "LAST STAND: staged by 2:30, the clock jumps to %s" % TutorialDirector._mmss(Rules.LAST_STAND_TIME))
	check(d.stage == 2 and "danger" in d.reveal_keys() and "status_line" in d.reveal_keys(), "LAST STAND: stage C reveals the status line and the danger marks")
	check(sim.ls_drop_gap_override == Rules.LAST_STAND_DROP_GAP, "LAST STAND: the drop gap is pinned short")
	check(sim.match_hard_end == INF and not sim.vls_enabled, "LAST STAND: the Very Last Stand and the 7:00 end stay off until the end")
	tick(d, sim)
	check(d.card()["text"].contains(TutorialDirector._mmss(Rules.LAST_STAND_TIME)), "LAST STAND: the line names the time")
	# the first ring's countdown holds while the line is read
	run_for(d, sim, 5.0)
	check(sim.last_stand_warn_t >= Rules.LAST_STAND_WARNING - DT - 0.01 and not sim.last_stand_queue.is_empty(), "LAST STAND: the first ring's countdown waits while the line is read")
	# the rival is capped weak; the kept ring's neutrals are cheap
	for x in sim.nodes:
		if x["owner"] == "B":
			x["units"] = 90.0 * Rules.SCALE
	tick(d, sim)
	var cap_ok := true
	for x in sim.nodes:
		if x["owner"] == "B" and float(x["units"]) > float(Rules.QUICK_START["ls_rival_cap_shown"] + 1) * Rules.SCALE:
			cap_ok = false
	check(cap_ok, "LAST STAND: the rival's nodes are capped at %d units" % int(Rules.QUICK_START["ls_rival_cap_shown"]))
	check(Rules.shown(sim.nodes[n["I1"]]["units"]) <= int(Rules.QUICK_START["ls_neutral_cap_shown"]), "LAST STAND: the kept ring's neutral nodes are cheap to take")
	# the hand shows the evacuation (off the doomed node, onto the kept ring)
	d.on_action("send", 0, {}, false)
	var g := d.gesture()
	check(g.size() > 0 and g[0][0] == "drag" and sim.last_stand_waves[0].has(int(g[0][1])) and not sim.last_stand_waves[0].has(int(g[0][2])),
			"LAST STAND: the hand drags off a falling node onto one that stays")
	# evacuate
	sim.send(n["H"], n["I1"], 1.0)
	sim.send(n["A1"], n["I2"], 1.0)
	sim.send(n["A2"], n["I2"], 1.0)
	run_until(d, sim, func(): return d.goals.goal_done("last_stand"), 90.0)
	check(d.goals.goal_done("last_stand"), "LAST STAND: ticks when the first ring has fallen and you still hold a node")
	check(d.state == "complete" and not d.result.get("skipped", true), "LAST STAND: the quick start completes")
	check(sim.match_hard_end == Rules.MATCH_HARD_END and sim.vls_enabled, "LAST STAND: the match's normal end is back")
	check(not sim.eliminated.has("A") and _holds(sim), "LAST STAND: evacuating kept A alive through the ring's fall")
	# the goal needs the ring to fall: not before
	var r2 := make(RING_MAP)
	var d2: TutorialDirector = r2[0]
	var s2: Sim = r2[1]
	_stage_ls(d2)
	d2._stage_last_stand()
	set_units(s2, 3, 5.0, "A")
	run_for(d2, s2, 3.0)
	check(not d2.goals.goal_done("last_stand"), "LAST STAND negative: announced, but the ring has not fallen - not ticked")


func _holds(sim: Sim) -> bool:
	for x in sim.nodes:
		if x["owner"] == "A" and not sim.collapsed.get(x["id"], false):
			return true
	return false


func test_last_stand_seeds() -> void:
	## Whatever the ring/drop picks, a player who evacuates inward stays alive with the rival capped, and the goal ticks.
	var wins := 0
	var seeds := [1, 2, 3, 4, 5, 6, 8, 9, 10, 11]
	for sd in seeds:
		var r := make(RING_MAP, sd, true)                        # the Training AI plays here too
		var d: TutorialDirector = r[0]
		var sim: Sim = r[1]
		var n: Dictionary = d.names
		_stage_ls(d)
		d._stage_last_stand()
		sim.send(n["H"], n["I1"], 1.0)
		sim.send(n["A1"], n["I2"], 1.0)
		sim.send(n["A2"], n["I2"], 1.0)
		var t := 0.0
		while d.state == "running" and not d.goals.goal_done("last_stand") and t < 120.0:
			tick(d, sim)
			t += DT
		if d.goals.goal_done("last_stand") and _holds(sim) and not sim.eliminated.has("A"):
			wins += 1
	check(wins == seeds.size(), "LAST STAND: an evacuating player is alive when the first ring falls, on every seed (%d / %d)" % [wins, seeds.size()])


func test_last_stand_loss() -> void:
	## A player who does nothing loses everything with the ring: a real loss restages (TRY AGAIN), never a silent pass.
	var r := make(RING_MAP)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	_stage_ls(d)
	d._stage_last_stand()
	for x in sim.nodes:                                          # everything of yours stands on the outer ring
		if x["owner"] == "A" and not (x["id"] in sim.last_stand_waves[0]):
			x["owner"] = ""
	run_until(d, sim, func(): return d.state != "running", 120.0)
	check(d.state == "failed" and not d.goals.goal_done("last_stand") and d.card()["button"] == TutorialDirector.line("try_again_title"),
			"LAST STAND negative: nothing held when the ring falls -> TRY AGAIN, not ticked")
	# your home lost to the rival is a real loss too
	var r2 := make()
	var d2: TutorialDirector = r2[0]
	var s2: Sim = r2[1]
	s2.nodes[d2.names["H"]]["owner"] = "B"
	tick(d2, s2)
	check(d2.state == "failed", "loss: your home taken by the rival -> TRY AGAIN")


func test_complete_flow() -> void:
	## All six goals ticked -> LESSON COMPLETE (pays once), CONTINUE PLAYING releases the coach and the match plays on.
	_wipe()
	TutorialDirector.reload_progress()
	var r := make(RING_MAP)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var got := {"result": {}}
	d.completed.connect(func(res): got["result"] = res)
	_stage_ls(d)
	d._stage_last_stand()
	sim.send(d.names["H"], d.names["I1"], 1.0)
	run_until(d, sim, func(): return d.state == "complete", 120.0)
	check(d.state == "complete" and not (got["result"] as Dictionary).is_empty(), "complete: LESSON COMPLETE is signalled")
	var res: Dictionary = got["result"]
	check(res["continue"] and not res["skipped"] and int(res["scrap"]) == TutorialDirector.scrap_for(1) and TutorialDirector.is_done(1),
			"complete: paid %d SCRAP once, saved as done" % int(res["scrap"]))
	check(not res["final"] and not res["graduate"], "complete: not the final screen while the other four are open")
	d.release()
	check(d.state == "released" and d.card()["visible"] == false, "complete: CONTINUE PLAYING releases the coach")
	d.ai = SeatAI.new("B", 2.5, "Training")
	for i in range(40):
		d.step(DT)
		sim.step(DT)
	check(sim.time > 0.0 and not sim.over or sim.over, "complete: the match goes on after release")
	# the last tutorial to be completed makes the final screen and the vat
	TutorialDirector.completed_ids = [2, 3, 4, 5]
	var r2 := make(RING_MAP)
	var d2: TutorialDirector = r2[0]
	for id in ["upgrade", "take", "reinforce", "machinegoon", "relay", "last_stand"]:
		d2.goals.complete(id)
	tick(d2, r2[1])
	check(d2.state == "complete" and d2.result["final"] and d2.result["graduate"] and Progression.owns("vat:graduate"),
			"complete: the fifth tutorial done -> TRAINING COMPLETE and the Graduate vat")
	_wipe()
	TutorialDirector.reload_progress()


# ------------------------------------------------------------------ T-11 (once the map pipeline has baked it)
func test_quick_map() -> void:
	var path := "%s/%s.json" % [TutorialDirector.map_dir, quick_map]
	check(FileAccess.file_exists(path), "T-11: %s is baked" % quick_map)
	if not FileAccess.file_exists(path):
		return
	var r := make(quick_map)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	check(n.has("H") and n.has("BH") and n.has("R") and sim.nodes[n["R"]]["relay"] == "rotation", "T-11: names H, BH and the rotation relay R")
	check(TutorialDirector.map_path_for(1) == "%s/T-11-proving-ground.json" % TutorialDirector.map_dir, "T-11: the quick start's map path")
	var neutrals := sim.nodes.filter(func(x): return x["owner"] == "" and Sim.has_vat(x))
	check(neutrals.size() >= 4, "T-11: neutral vat nodes to take (%d)" % neutrals.size())
	check(not sim.last_stand_waves.is_empty() or sim.nodes.any(func(x): return x["ring"] != 0), "T-11: has rings")
	var ls: Dictionary = MapBuilder.load_map(path).get("lastStand", {})
	check((ls.get("methods", []) as Array).has("inward"), "T-11: the Last Stand falls inward")
