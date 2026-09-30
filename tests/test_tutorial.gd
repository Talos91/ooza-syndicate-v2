extends SceneTree
## Headless tutorial check:  Godot --headless --path . --script res://tests/test_tutorial.gd  [-- maps=<dir>]
## Exit code 0 = all passed. TUTORIAL-REWRITE-DESIGN.md §3a / §6: the QUICK START is four chapters in order (guided basics,
## free play, a scripted relay kill, the Last Stand explained). Checked on its own map T-11 through the real Sim calls
## (send, upgrade_structure, structure_order, fire_relay - what main.perform runs): the steps come in order and a later one
## never passes before its turn; each step's detector fires on its action and stays quiet without it; the hand shows from
## the start of a guided step (free play: only after idle time); the short-send assist; the Machinegoon probe; free play
## ends on its timer with the rival passive; the relay push is on the deck when the slow motion opens and a fire drops it
## (and three misses pass it); the follow test; the Last Stand is explained with its countdown held, then an evacuation
## keeps the player alive over several seeds; real losses restage; the staged reveal; skipping, the first launch, progress
## and the reward hook; a scripted player finishes the whole quick start. Staged directly - no whole matches from 0:00
## except that one scripted run.

const DT := 0.05
const QUICK := "T-11-proving-ground"
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
	test_goal_director()
	test_lines()
	test_reveal()
	test_progress()
	test_skipping()
	test_first_launch()
	test_staging()
	test_order()
	test_take()
	test_short_sends()
	test_reinforce()
	test_upgrade()
	test_machinegoon()
	test_inspector_hand()
	test_free_play()
	test_relay()
	test_relay_miss()
	test_follow()
	test_last_stand()
	test_last_stand_seeds()
	test_losses()
	test_complete_flow()
	test_soak()
	_wipe()
	print("\n%s: %d failure(s)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _wipe() -> void:
	for p in [TutorialDirector.path, ArmyPresets.path, Progression.path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progression.reload_all()


# ------------------------------------------------------------------ harness
func make(seed_value := 7) -> Array:
	## [director, sim]: T-11, seats and staging exactly as main.start_tutorial builds them (VEX, EMBER).
	var d := TutorialDirector.new(1)
	var map := MapBuilder.load_map(TutorialDirector.map_path_for(1))
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, {"A": TutorialDirector.PLAYER_FACTION, "B": TutorialDirector.RIVAL_FACTION},
			seed_value, {}, {"A": d.loadout_for()})
	d.ui_fraction = d.fraction_start(0.5)
	d.begin(sim, map, TutorialDirector.PLAYER_FACTION)
	return [d, sim]


func goto(d: TutorialDirector, sim: Sim, id: String) -> void:
	## Pass every step before `id` without playing it (their detectors are not run), then one frame.
	var guard := 0
	while d.current_id() != id and d.current_id() != "" and guard < 20:
		d.goals.complete(d.current_id())
		guard += 1
	d._note = ""                                                 # (the passed steps' "done" lines are not what is tested)
	d._note_t = 0.0
	tick(d, sim)


func own(sim: Sim, ids: Array, shown := 30.0) -> void:
	for id in ids:
		set_units(sim, int(id), shown, "A")


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
	check(d.current_id() == "take", "skip: the first step is TAKE")
	var guard := 0
	while d.state == "running" and guard < 20:
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
	check(dk.goals.goal_done("take") and dk.current_id() == "reinforce" and dk.skipped and dk.state == "running", "skip: SKIP GOAL skips only the current step; the next one starts (the run is skipped)")
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
	for st in TutorialDirector.tutorial(1)["steps"]:
		var id := str(st["id"])
		check(TutorialDirector.LINES.has("T1.%s" % id) or TutorialDirector.LINES.has("T1.%s_wait" % id), "lines: step %s has its card" % id)
	var words := []
	for ch in range(4):
		words.append(TutorialDirector.line("T1.chapter.%d" % ch))
	check(words == ["BASICS", "YOUR TURN", "RELAY", "LAST STAND"], "the goal strip: four chapters %s" % str(words))
	var rows := TutorialDirector.lesson_rows()
	check(rows.size() == 5 and rows[0]["title"] == "QUICK START" and rows[4]["title"] == "TEAM PLAY", "the TRAINING page lists five rows, QUICK START first")
	check(not rows[0]["soon"] and rows[1]["soon"] and rows[2]["soon"] and rows[3]["soon"] and rows[4]["soon"], "only the QUICK START is playable")


# ------------------------------------------------------------------ reveal stages
func test_reveal() -> void:
	var r0 := TutorialDirector.reveal_for(1, 0)
	check("send_panel" in r0 and not "upgrade" in r0 and not "machinegoon" in r0 and not "relay" in r0, "reveal: the take step shows the SEND panel, not yet UPGRADE / MACHINEGOON")
	check("upgrade" in TutorialDirector.reveal_for(1, 1) and not "machinegoon" in TutorialDirector.reveal_for(1, 1), "reveal: UPGRADE with its step")
	check("machinegoon" in TutorialDirector.reveal_for(1, 2) and not "relay" in TutorialDirector.reveal_for(1, 2), "reveal: MACHINEGOON with its step (stage A ends)")
	check("relay" in TutorialDirector.reveal_for(1, 3) and not "danger" in TutorialDirector.reveal_for(1, 3), "reveal B: the relay at chapter 3")
	check("status_line" in TutorialDirector.reveal_for(1, 4) and "danger" in TutorialDirector.reveal_for(1, 4) and "send_panel" in TutorialDirector.reveal_for(1, 4),
			"reveal C: the status line and the danger marks at chapter 4, cumulative")
	for k in ["dock", "halos", "eject", "relay_build", "monster", "out_panel"]:
		check(not k in TutorialDirector.reveal_for(1, 4), "reveal: the quick start never shows '%s'" % k)
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	tick(d, sim)
	var seen := {}
	for id in ["take", "reinforce", "upgrade", "machinegoon", "free", "relay_take", "relay", "ls_intro"]:
		goto(d, sim, id)
		seen[id] = d.stage
	check(seen["take"] == 0 and seen["reinforce"] == 0 and seen["upgrade"] == 1 and seen["machinegoon"] == 2 and seen["free"] == 2,
			"reveal: chapters 1-2 stay in stage A, each mechanic revealed at its own step %s" % str(seen))
	check(seen["relay_take"] == 3 and seen["relay"] == 3 and seen["ls_intro"] == 4 and d.preview_relay == d.names["R"], "reveal: stage B at chapter 3, C at chapter 4")
	check(TutorialDirector.reveal_for(3, 0).size() == TutorialDirector.ALL_KEYS.size(), "reveal: a tutorial without stage data shows everything")


# ------------------------------------------------------------------ staging, the order
func test_staging() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	check(sim.factions["A"] == "vex" and sim.factions["B"] == "ember", "the tutorial is VEX against EMBER")
	check(not sim.abilities_on and not sim.vls_enabled and sim.match_hard_end == INF, "staging: abilities off, the Very Last Stand and the 7:00 end held back")
	check(Rules.shown(sim.nodes[d.names["H"]]["units"]) == Rules.QUICK_START["home_shown"], "staging: the home starts with %d units" % Rules.QUICK_START["home_shown"])
	tick(d, sim)
	check(d.current_id() == "take" and d.card()["header"] == "DR. VESK · QUICK START", "card: the first step is TAKE, DR. VESK · QUICK START")
	check(d.card()["text"].contains(str(Rules.shown(sim.nodes[d.names["N1"]]["units"]))), "card: the take line names the badge count from the board")
	var chips := d.chips()
	check(chips.size() == 4 and chips[0]["text"] == "BASICS 0/4" and chips[0]["current"] and chips[3]["locked"], "strip: four chapter chips, BASICS 0/4 current")
	check(d.allow("send", d.names["H"], {"to": d.names["BH"]}) != "" and d.allow("send", d.names["H"], {"to": d.names["N1"]}) == "",
			"allow: an attack on the rival's home is refused (Not yet), everything else is free")
	run_for(d, sim, float(Rules.QUICK_START["take_send_after"]) + 0.5)
	check(d.card()["text"] == TutorialDirector.line("T1.take_send"), "card: the take card then explains the SEND panel")


func test_order() -> void:
	## A later step never passes before its turn; the hand and the spotlight show a guided step from its start.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	tick(d, sim)
	var g := d.gesture()
	check(g.size() > 0 and g[0] == ["drag", n["H"], n["N1"]] and n["N1"] in d.target()["nodes"] and "send_panel" in d.target()["rects"] and not d.target()["open"],
			"order: TAKE shows the hand (home -> N1) and the spotlight from the first frame")
	# do later steps' actions first: an upgrade and a Machinegoon on the home
	set_units(sim, n["H"], 90.0)
	sim.upgrade_structure(n["H"])
	run_for(d, sim, Rules.BUILD_SECONDS + 1.0)
	check(int(sim.nodes[n["H"]]["tier"]) == 2 and d.current_id() == "take" and not d.goals.goal_done("upgrade"), "order: an upgrade during TAKE does not pass UPGRADE")
	check(d.chips()[0]["text"] == "BASICS 0/4", "order: nothing ticked yet")
	sim.send(n["H"], n["N1"], 0.5)
	run_until(d, sim, func(): return d.current_id() != "take", 30.0)
	check(d.current_id() == "reinforce" and d.chips()[0]["text"] == "BASICS 1/4", "order: TAKE done -> REINFORCE is next (BASICS 1/4)")
	var ids := []
	for st in TutorialDirector.tutorial(1)["steps"]:
		ids.append(st["id"])
	check(ids == ["take", "reinforce", "upgrade", "machinegoon", "free", "relay_take", "relay", "ls_intro", "ls_marks", "ls_rings", "ls_move", "ls_hold"],
			"order: the quick start's twelve steps in their order")


# ------------------------------------------------------------------ chapter 1: guided basics
func test_take() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	run_for(d, sim, 12.0)
	check(d.current_id() == "take", "TAKE negative: doing nothing never passes it")
	sim.send(n["H"], n["N1"], 0.5)                               # 20 against 15: the hand's move at 50 %
	var t := run_until(d, sim, func(): return d.goals.goal_done("take"), 30.0)
	check(d.goals.goal_done("take") and sim.nodes[n["N1"]]["owner"] == "A", "TAKE: a 50 %% send from the staged home takes N1 (%.1f s)" % t)
	check(d.card()["text"] == TutorialDirector.line("T1.done.take"), "TAKE: Dr. Vesk says his one line")


func test_short_sends() -> void:
	## A short send on the take step: the target holds, the director tops up your sender, freezes the target and points the
	## hand at the retry - then a 100 % send takes it. Never a TRY AGAIN.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	sim.send(n["H"], n["N1"], 0.05)                              # 2 against 15
	var said := false
	var t := 0.0
	while t < 30.0 and d.assist_retry().is_empty():
		tick(d, sim)
		said = said or d.card()["text"] == TutorialDirector.line("assist_short")
		t += DT
	check(not d.assist_retry().is_empty() and said, "short send: the landing short triggers the assist line")
	check(d.state == "running" and sim.nodes[n["N1"]]["owner"] == "", "short send: no TRY AGAIN, the node still stands")
	var retry := d.assist_retry()
	check(d.gesture()[0] == ["drag", retry[0], n["N1"]], "short send: the hand points at the retry")
	var frozen: float = sim.nodes[n["N1"]]["units"]
	run_for(d, sim, 3.0)
	check(sim.nodes[n["N1"]]["units"] <= frozen + 0.01, "short send: the target's count is frozen until it is taken")
	sim.send(int(retry[0]), n["N1"], 1.0)
	run_until(d, sim, func(): return d.goals.goal_done("take"), 60.0)
	check(sim.nodes[n["N1"]]["owner"] == "A" and d.goals.goal_done("take") and d.state == "running", "short send: the 100 % retry takes it")


func test_reinforce() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	own(sim, [n["N1"]], 5.0)
	goto(d, sim, "reinforce")
	var g := d.gesture()
	check(g.size() > 0 and g[0][0] == "drag" and int(g[0][1]) == n["H"] and int(g[0][2]) == n["N1"], "REINFORCE: the hand drags home -> the new node from the start")
	run_for(d, sim, 8.0)
	check(d.current_id() == "reinforce", "REINFORCE negative: nothing sent, nothing passed")
	sim.send(n["H"], n["N2"], 0.1)                               # a send at a grey node is not a reinforcement
	run_for(d, sim, 6.0)
	check(not d.goals.goal_done("reinforce"), "REINFORCE negative: a send at a grey node does not count")
	sim.send(n["H"], n["N1"], 0.5)
	run_until(d, sim, func(): return d.goals.goal_done("reinforce"), 30.0)
	check(d.goals.goal_done("reinforce") and d.current_id() == "upgrade", "REINFORCE: a send between two of your nodes lands -> UPGRADE is next")


func test_upgrade() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	own(sim, [n["N1"]], 5.0)
	set_units(sim, n["H"], 3.0)
	goto(d, sim, "upgrade")
	check(float(sim.nodes[n["H"]]["units"]) >= float(sim.upgrade_cost(sim.nodes[n["H"]])), "UPGRADE: the step makes sure the home can pay")
	check(d.gesture()[0] == ["double_tap", n["H"], -1] and d.card()["text"].contains(str(Rules.shown(Rules.VAT_COST[1]))),
			"UPGRADE: the hand double-taps the home; the card names the cost from Rules")
	run_for(d, sim, 6.0)
	check(not d.goals.goal_done("upgrade"), "UPGRADE negative: no double-tap, no pass")
	check(sim.upgrade_structure(n["H"]), "UPGRADE: the double-tap upgrade starts")
	tick(d, sim)
	check(d.card()["text"].begins_with("Building") and d.gesture().is_empty(), "UPGRADE: while it builds the card says so, the hand rests")
	var t := run_until(d, sim, func(): return d.goals.goal_done("upgrade"), 20.0)
	check(d.goals.goal_done("upgrade") and int(sim.nodes[n["H"]]["tier"]) == 2 and t >= Rules.BUILD_SECONDS - 1.0, "UPGRADE: done when the vat reaches T2 (%.1f s)" % t)


func test_machinegoon() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	own(sim, [n["N1"]], 5.0)
	goto(d, sim, "machinegoon")
	var g := d.gesture()
	check(d.card()["text"] == TutorialDirector.line("T1.machinegoon_prep") and g.size() > 0 and g[0][0] == "drag" and int(g[0][2]) == n["M"],
			"MACHINEGOON: first take M - the hand drags there")
	sim.send(n["H"], n["M"], 1.0)
	run_until(d, sim, func(): return sim.nodes[n["M"]]["owner"] == "A", 40.0)
	tick(d, sim)
	check(float(sim.nodes[n["M"]]["units"]) >= float(Rules.MACHINEGOON_COST[1]) and d.gesture()[0] == ["tap", n["M"], -1] and d.uses_inspector(),
			"MACHINEGOON: M is yours and can pay; the hand taps it (the inspector opens)")
	d.ui_inspector = n["M"]
	d._bump()
	check(d.gesture()[0] == ["press", "action:MACHINEGOON", -1] and "action:MACHINEGOON" in d.target()["rects"], "MACHINEGOON: then the hand presses the MACHINEGOON card")
	check(sim.structure_order("A", "build", n["M"], {"kind": "machinegoon"})[0], "MACHINEGOON: the build order goes through")
	d.ui_inspector = -1
	run_for(d, sim, Rules.BUILD_SECONDS + 0.5)
	check(sim.nodes[n["M"]]["structure"] == "machinegoon" and not d.goals.goal_done("machinegoon"), "MACHINEGOON negative: built, no kill yet - not passed")
	var probe := {"seen": false, "open": true}
	var t := run_until(d, sim, func(): return d.goals.goal_done("machinegoon"), 90.0, func(_t):
		probe["open"] = probe["open"] and d.target()["open"]
		for h in sim.hordes:
			if h["owner"] == "B" and int(h["target"]) == n["M"]:
				probe["seen"] = true)
	check(probe["seen"] and probe["open"], "MACHINEGOON: a scripted rival line walks at it - an undimmed watch moment")
	check(d.goals.goal_done("machinegoon") and sim.nodes[n["M"]]["owner"] == "A" and d.current_id() == "free",
			"MACHINEGOON: done when it has shot rival units, M held -> free play (%.0f s)" % t)


# ------------------------------------------------------------------ chapter 2: free play
func test_free_play() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	goto(d, sim, "free")
	check(d.card()["text"] == TutorialDirector.line("T1.free") or d.card()["text"] == TutorialDirector.line("T1.done.machinegoon"), "FREE: 'Your turn' card")
	check(d.gesture().is_empty() and (d.target()["nodes"] as Array).is_empty(), "FREE: no hand while the player plays")
	check(d.chips()[1]["text"] == "YOUR TURN %s" % TutorialDirector._mmss(Rules.QUICK_START["free_play"]) and d.chips()[0]["done"], "FREE: the strip counts down, BASICS ticked")
	var st := {"rival_lines": 0, "nudged": false, "hand": false}
	var t := run_until(d, sim, func(): return d.current_id() != "free", float(Rules.QUICK_START["free_play"]) + 5.0, func(_t):
		for h in sim.hordes:
			if h["owner"] == "B":
				st["rival_lines"] += 1
		st["nudged"] = st["nudged"] or d.card()["text"] == TutorialDirector.line("T1.free_nudge")
		st["hand"] = st["hand"] or not d.gesture().is_empty())
	check(st["rival_lines"] == 0, "FREE: the rival stays passive (no line of its own in %.0f s)" % t)
	check(st["nudged"] and st["hand"], "FREE: idle -> Dr. Vesk nudges and the hand shows a move")
	check(absf(t - float(Rules.QUICK_START["free_play"])) <= 1.0 and d.current_id() == "relay_take", "FREE: ends on its timer (%.1f s) -> chapter 3" % t)


# ------------------------------------------------------------------ chapter 3: the relay kill
func _stage_relay(d: TutorialDirector, sim: Sim) -> void:
	var n: Dictionary = d.names
	own(sim, [n["N1"], n["N2"], n["M"]])
	for id in [n["BH"], n["B1"], n["B2"], n["M2"]]:
		set_units(sim, id, 25.0, "B")
	goto(d, sim, "relay_take")


func test_relay() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	var R: int = n["R"]
	_stage_relay(d, sim)
	var g := d.gesture()
	check(d.card()["text"] == TutorialDirector.line("T1.relay_take") and g.size() > 0 and g[0][0] == "drag" and int(g[0][2]) == R,
			"RELAY: take the relay - the hand drags there from the start")
	run_for(d, sim, 10.0)
	check(d.catch_line() < 0 and d.current_id() == "relay_take", "RELAY negative: no push while the relay is not yours")
	sim.send(n["M"], R, 1.0)
	run_until(d, sim, func(): return d.current_id() == "relay", 40.0)
	check(d.current_id() == "relay" and sim.nodes[R]["owner"] == "A", "RELAY: the relay is yours -> the push step")
	var st := {"fired": false, "slow_early": false, "fling": 0, "prompt_hand": false}
	var t := 0.0
	while d.state == "running" and not d.goals.goal_done("relay") and t < 150.0:
		d.step(DT)
		var hid := d.catch_line()
		if hid >= 0 and d.time_scale <= float(Rules.QUICK_START["slow"]) + 0.001 and deck_metres(sim, hid, R) <= 0.0:
			st["slow_early"] = true
		if d.catch_prompt() and not st["fired"]:
			st["prompt_hand"] = d.gesture()[0] == ["double_tap", R, -1] and d.target()["open"] and d.card()["compact"]
			st["fired"] = sim.fire_relay(R)
		sim.step(DT * d.time_scale)
		for ev in sim.fx_events:
			d.on_event(ev)
			if ev["type"] == "fling" and ev["seat"] == "B":
				st["fling"] += int(ev["units"])
		sim.fx_events.clear()
		t += DT
	check(st["slow_early"], "RELAY: 0.25x before the rival line is on the relay deck")
	check(st["fired"] and st["prompt_hand"], "RELAY: at the prompt the hand double-taps the relay, undimmed, the card compact")
	check(st["fling"] >= int(Rules.QUICK_START["relay_min_drop"]) and d.goals.goal_done("relay"), "RELAY: the fire flings the line (%d units, %.0f s)" % [st["fling"], t])
	check(d.current_id() == "ls_intro" and d._relay_kill_units >= int(Rules.QUICK_START["relay_min_drop"]), "RELAY: the kill is counted -> chapter 4")


func test_relay_miss() -> void:
	## Nobody fires: the pushes come (relay_tries of them), then "timing takes practice" passes the step - no hang.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	_stage_relay(d, sim)
	own(sim, [d.names["R"]])
	var seen := {}
	var t := run_until(d, sim, func(): return d.goals.goal_done("relay"), 400.0, func(_t):
		if d.catch_line() >= 0:
			seen[d.catch_line()] = true)
	check(seen.size() == int(Rules.QUICK_START["relay_tries"]), "RELAY negative: %d pushes went unanswered (%d)" % [int(Rules.QUICK_START["relay_tries"]), seen.size()])
	check(d.goals.goal_done("relay") and d._relay_kill_units == 0 and sim.nodes[d.names["R"]]["owner"] == "A",
			"RELAY negative: then 'timing takes practice' passes it, no kill counted, the relay held (%.0f s)" % t)


func test_follow() -> void:
	## Daniele (0.22.1): "never have the area necessary to look at covered in fog of war". Every metre of the push on the
	## relay deck is inside a lit circle (R x 1.35 round a follow point or the relay) on every frame it moves.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	_stage_relay(d, sim)
	own(sim, [d.names["R"]])
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
	check(ok and frames > 40, "follow: the push is inside the lit shape, head to tail, every frame (%d frames)" % frames)
	check(open_ok, "follow: the relay moment is a watch moment - no dim")
	check(d.follow_points().size() <= 20, "follow: a handful of points, cheap (%d)" % d.follow_points().size())


# ------------------------------------------------------------------ chapter 4: the Last Stand explained
func _stage_ls(d: TutorialDirector, sim: Sim) -> void:
	var n: Dictionary = d.names
	own(sim, [n["N1"], n["N2"]], 20.0)
	own(sim, [n["M"], n["R"]], 10.0)
	goto(d, sim, "ls_intro")


func test_last_stand() -> void:
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	_stage_ls(d, sim)
	check(sim.last_stand_active and sim.time >= Rules.LAST_STAND_TIME and d.card()["text"].contains(TutorialDirector._mmss(Rules.LAST_STAND_TIME)),
			"LAST STAND: announced - the clock jumps to %s and the card says so" % TutorialDirector._mmss(Rules.LAST_STAND_TIME))
	check(d.card()["button"] == TutorialDirector.line("got_it") and d.gesture().is_empty() and d.target()["open"], "LAST STAND: an explanation card with GOT IT, undimmed, no hand")
	check(d.stage == 4 and "danger" in d.reveal_keys() and sim.ls_drop_gap_override == Rules.LAST_STAND_DROP_GAP and not sim.vls_enabled,
			"LAST STAND: stage C, the drops pinned short, the Very Last Stand still off")
	run_for(d, sim, 25.0)
	check(d.current_id() == "ls_intro" and sim.collapsed.is_empty() and sim.last_stand_warn_t >= Rules.LAST_STAND_WARNING - DT - 0.01,
			"LAST STAND: nothing falls while the explanation is read (25 s)")
	d.press_button()
	tick(d, sim)
	check(d.current_id() == "ls_marks" and (d.target()["nodes"] as Array).size() > 0 and (d.target()["nodes"] as Array).all(func(id): return sim.is_warned(id)),
			"LAST STAND: GOT IT -> the danger marks card lights the warned nodes")
	d.press_button()
	tick(d, sim)
	check(d.current_id() == "ls_rings" and (d.target()["nodes"] as Array).all(func(id): return sim.last_stand_keep.has(id)), "LAST STAND: -> the rings card lights the centre ring")
	check(sim.nodes.any(func(x): return x["owner"] == "B" and sim.last_stand_keep.has(x["id"])), "LAST STAND: the rival keeps a centre node, so the match goes on after")
	for x in sim.nodes:
		if x["owner"] == "B":
			x["units"] = 90.0 * Rules.SCALE
	tick(d, sim)
	check(sim.nodes.all(func(x): return x["owner"] != "B" or Rules.shown(x["units"]) <= int(Rules.QUICK_START["ls_rival_cap_shown"])), "LAST STAND: the rival is capped weak")
	d.press_button()
	tick(d, sim)
	var g := d.gesture()
	check(d.current_id() == "ls_move" and g.size() > 0 and g[0][0] == "drag" and sim.last_stand_waves[0].has(int(g[0][1])) and sim.last_stand_keep.has(int(g[0][2])),
			"LAST STAND: the move card - the hand drags off a falling node onto the centre ring, from the start")
	var mv := d._evac_move()
	sim.send(int(mv[0]), int(mv[1]), 1.0)
	run_until(d, sim, func(): return d.current_id() != "ls_move", 5.0)
	check(d.current_id() == "ls_hold" and sim.collapsed.is_empty(), "LAST STAND: the move sent -> 'hold on' (nothing has fallen yet)")
	var t := run_until(d, sim, func(): return d.state != "running", 120.0, func(_t):
		var m2 := d._evac_move()
		if not m2.is_empty() and sim.nodes[int(m2[0])]["streaming"].is_empty():
			sim.send(int(m2[0]), int(m2[1]), 1.0))
	check(d.state == "complete" and not d.result.get("skipped", true), "LAST STAND: the first ring falls with you on the centre -> LESSON COMPLETE (%.0f s)" % t)
	check(sim.match_hard_end == Rules.MATCH_HARD_END and sim.vls_enabled and not sim.eliminated.has("A"), "LAST STAND: the match's normal end is back, you are alive")


func test_last_stand_seeds() -> void:
	## Whatever the drop picks, a player who follows the move card stays alive and the quick start completes.
	var wins := 0
	var seeds := [1, 2, 3, 4, 5, 6, 8, 9, 10, 11]
	for sd in seeds:
		var r := make(sd)
		var d: TutorialDirector = r[0]
		var sim: Sim = r[1]
		_stage_ls(d, sim)
		for i in range(3):
			d.press_button()
			tick(d, sim)
		run_until(d, sim, func(): return d.state != "running", 150.0, func(_t):
			var mv := d._evac_move()
			if not mv.is_empty() and sim.nodes[int(mv[0])]["streaming"].is_empty():
				sim.send(int(mv[0]), int(mv[1]), 1.0))
		if d.state == "complete" and not sim.eliminated.has("A"):
			wins += 1
	check(wins == seeds.size(), "LAST STAND: an evacuating player completes it on every seed (%d / %d)" % [wins, seeds.size()])


func test_losses() -> void:
	## Real losses restage (TRY AGAIN); a short send never does.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	goto(d, sim, "ls_intro")                                     # nothing but the home (outer ring) and a skipped move
	for i in range(3):
		d.press_button()
		tick(d, sim)
	d.skip_step()                                                # (the move skipped: everything stays on the falling ring)
	run_until(d, sim, func(): return d.state != "running", 150.0)
	check(d.state == "failed" and d.card()["button"] == TutorialDirector.line("try_again_title"), "loss: nothing held when the ring falls -> TRY AGAIN")
	var r2 := make()
	var d2: TutorialDirector = r2[0]
	var s2: Sim = r2[1]
	s2.nodes[d2.names["H"]]["owner"] = "B"
	tick(d2, s2)
	check(d2.state == "failed", "loss: your home taken by the rival -> TRY AGAIN")


func test_complete_flow() -> void:
	## Every step done -> LESSON COMPLETE (pays once), CONTINUE PLAYING releases the coach and the rival's AI.
	_wipe()
	TutorialDirector.reload_progress()
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var got := {"result": {}}
	d.completed.connect(func(res): got["result"] = res)
	goto(d, sim, "ls_hold")
	d.goals.complete("ls_hold")
	tick(d, sim)
	var res: Dictionary = got["result"]
	check(d.state == "complete" and res["continue"] and not res["skipped"] and int(res["scrap"]) == TutorialDirector.scrap_for(1) and TutorialDirector.is_done(1),
			"complete: LESSON COMPLETE, paid %d SCRAP once, saved as done" % int(res.get("scrap", 0)))
	check(not res["final"] and not res["graduate"], "complete: not the final screen while the other four are open")
	d.release()
	check(d.state == "released" and not d.card()["visible"] and d.ai != null, "complete: CONTINUE PLAYING releases the coach, the Training AI takes over")
	TutorialDirector.completed_ids = [2, 3, 4, 5]
	var r2 := make()
	var d2: TutorialDirector = r2[0]
	goto(d2, r2[1], "ls_hold")
	d2.goals.complete("ls_hold")
	tick(d2, r2[1])
	check(d2.state == "complete" and d2.result["final"] and d2.result["graduate"] and Progression.owns("vat:graduate"),
			"complete: the fifth tutorial done -> TRAINING COMPLETE and the Graduate vat")
	_wipe()
	TutorialDirector.reload_progress()


# ------------------------------------------------------------------ the whole quick start, a scripted player
func bot(d: TutorialDirector, sim: Sim, t: float) -> void:
	## Plays what the card says, the way a new player would follow the hand: the hand's drag / double-tap / press, GOT IT on
	## the explanation cards, the relay at the prompt.
	if d.catch_prompt():
		sim.fire_relay(d.names["R"])
	if int(t * 20.0) % 20 != 0:                          # once a second otherwise
		return
	var cur := d.current_id()
	if d.card()["button"] != "" and d.state == "running":
		d.press_button()
		return
	if cur == "machinegoon" and d.ui_inspector == d.names["M"]:
		sim.structure_order("A", "build", d.names["M"], {"kind": "machinegoon"})
		d.ui_inspector = -1
		return
	var g := d.gesture()
	if cur == "free":                                    # free play: grow a little
		if sim.can_upgrade(d.names["N1"], "A") == "":
			sim.upgrade_structure(d.names["N1"])
		return
	if g.is_empty():
		return
	match str(g[0][0]):
		"drag":
			var from := int(g[0][1])
			if sim.nodes[from]["streaming"].is_empty():
				sim.send(from, int(g[0][2]), 0.5 if cur in ["take", "reinforce"] else 1.0)
		"double_tap":
			sim.upgrade_structure(int(g[0][1]))
		"tap":
			d.ui_inspector = int(g[0][1])                # (the inspector opens on a tap)


func test_soak() -> void:
	var r := make(11)
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var order := []
	d.goals.goal_completed.connect(func(id, _s): order.append("%s@%d" % [id, int(sim.time)]))
	var t := 0.0
	while d.state == "running" and t < 420.0:
		bot(d, sim, t)
		tick(d, sim)
		t += DT
	print("   soak: ", d.state, " steps ", order, " real ", int(t), " s, clock ", int(sim.time))
	check(d.state == "complete" and not d.skipped and order.size() == 12, "soak: a player following the hand finishes the quick start (%s, %d steps)" % [d.state, order.size()])
	check(t < 300.0, "soak: in about four to five minutes (%.0f s)" % t)


func test_inspector_hand() -> void:
	## 0.23.9's pie inspector has its close hub on the node centre: with it open, the hand points at the step's slice, or at
	## the hub to close it first - never at the node for another move.
	var r := make()
	var d: TutorialDirector = r[0]
	var sim: Sim = r[1]
	var n: Dictionary = d.names
	own(sim, [n["N1"]], 5.0)
	goto(d, sim, "upgrade")
	d.ui_inspector = n["H"]
	d._bump()
	check(d.gesture()[0] == ["press", "action:UPGRADE", -1] and "action:UPGRADE" in d.target()["rects"], "inspector: open on the home at UPGRADE -> the hand presses the UPGRADE slice")
	d.ui_inspector = n["N1"]
	d._bump()
	check(d.gesture()[0] == ["tap", n["N1"], -1], "inspector: open on another node -> the hand taps its hub to close it first")
	d.ui_inspector = -1
	d._bump()
	check(d.gesture()[0] == ["double_tap", n["H"], -1], "inspector: closed -> the double-tap on the home again")
