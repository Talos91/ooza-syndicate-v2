extends SceneTree
## Headless mission check:  Godot --headless --path . --script res://tests/test_mission.gd
## Exit code 0 = all passed. CAMPAIGN-DESIGN.md §4 / §5: every playable District 1 mission (vex:01 / 02 / s1 / 03) is
## set up on its own map the way main.start_mission does (the mission faction against its rival's, 1v1), the
## MissionDirector stages it (rival units on the rival's home), and its objective is driven to a win and to a loss
## by changing the Sim's state or appending the events the Sim itself writes (relay falls, relay fires, skills,
## captures); the stars (par, a start node lost), the optional objectives and Campaign.record's summaries (on a temp
## progress file, no Progression) are checked. Also: the remaining objective / optional kinds on a mission dict of
## the test's own, HIDE ENEMY COUNTS staging put back, a collapse_at mission starting the Last Stand.

const DT := 0.05
var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	Campaign.path = "user://test_mission_progress.cfg"
	Campaign.use_progression(null)
	Campaign.reset_progress()
	ArmyPresets.path = "user://test_mission_armies.cfg"
	ArmyPresets._loaded = false
	Rules.abilities_on = true
	Rules.last_stand = true
	test_d1_playable()
	test_01_conquest()
	test_02_drops()
	test_s1_survive()
	test_03_duel()
	test_record()
	test_other_kinds()
	test_hide_counts()
	test_pins()
	test_collapse_at()
	Campaign.reset_progress()
	for p in [Campaign.path, ArmyPresets.path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("\n%s: %d failure(s)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ harness
func make(key: String, data := {}, seed_value := 7) -> Array:
	## [director, sim]: the mission's map, seats and factions exactly as main.start_mission builds them.
	var d := MissionDirector.new(key, data)
	var m := d.m
	var map := MapBuilder.load_map(str(m["map"]))
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var f := str(m.get("faction", "vex"))
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, {"A": f, "B": str(Campaign.rival_of(m)["faction"])}, seed_value, {},
			{"A": ArmyPresets.loadout_for(f)})
	sim.captured.connect(d.on_captured)            # main feeds captures the same way (_on_captured)
	d.begin(sim, map, "A")
	d.start()
	return [d, sim]


func tick(d: MissionDirector, sim: Sim, n := 1) -> void:
	for i in range(n):
		sim.step(DT)
		for ev in sim.fx_events:
			d.on_event(ev)
		sim.fx_events.clear()
		d.step(DT)


func take_all(sim: Sim, from: String, to: String) -> void:
	## Every node of `from` changes hands (a conquest compressed into one frame); lines of `from` are dropped.
	for n in sim.nodes:
		if n["owner"] == from:
			n["owner"] = to
	sim.hordes = sim.hordes.filter(func(h): return h["owner"] != from)


func capture(sim: Sim, id: int, seat: String) -> void:
	## A capture the way the Sim logs it (sim.events "capture" + the captured signal).
	var old: String = sim.nodes[id]["owner"]
	sim.nodes[id]["owner"] = seat
	sim.events.append({"t": sim.time, "type": "capture", "node": id, "seat": seat, "from": old})
	sim.captured.emit(id, seat, old)


func relay_drop(sim: Sim, shown_units: float, by := "A", seat := "B") -> void:
	## A relay's deck going from under a line: the event _relay_drop / _cut_range write (internal units).
	sim.events.append({"t": sim.time, "type": "fall", "seat": seat, "units": shown_units * Rules.SCALE, "why": "relay",
			"by": by, "relay": -1})


func fire(sim: Sim, seat := "A") -> void:
	sim.events.append({"t": sim.time, "type": "relay_fired", "node": -1, "seat": seat, "index": 0})


func outcome(d: MissionDirector) -> Array:
	## [results emitted] - connect before driving.
	var got := []
	d.completed.connect(func(r): got.append(r))
	return got


# ------------------------------------------------------------------ District 1
func test_d1_playable() -> void:
	for k in ["vex:01", "vex:02", "vex:s1", "vex:03"]:
		var m := Campaign.mission(k)
		check(not m.is_empty() and Campaign.playable(m), "%s is playable (map %s)" % [k, m.get("map", "")])
		var r := make(k)
		var d: MissionDirector = r[0]
		var sim: Sim = r[1]
		check(not d.start_nodes.is_empty() and sim.homes.has("A") and int(sim.homes["A"]) in d.start_nodes,
				"%s: the start nodes recorded (home included)" % k)
		check(d.state == "running" and d.objective_line() != "" and d.par_line().begins_with("PAR "),
				"%s: running with readouts ('%s' / '%s')" % [k, d.objective_line(), d.par_line()])
		tick(d, sim, 20)
		check(d.state == "running", "%s: a second of play decides nothing" % k)


func test_01_conquest() -> void:
	var k := "vex:01"
	# a clean win inside par: 3 stars, no vat lost
	var r := make(k)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	check(d.objective_line().begins_with("TAKE EVERY RIVAL NODE"), "01: the objective line '%s'" % d.objective_line())
	check(d.optional_ok(), "01: no vat lost yet (live tick)")
	tick(d, sim, 10)
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] and got[0]["stars"] == 3 and got[0]["objective"] and not got[0]["lost_start"],
			"01: conquest inside par -> won, 3 stars, optional met %s" % [got])
	# a start vat captured, then won inside par: 2 stars, optional failed
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	var home := int(sim.homes["A"])
	capture(sim, home, "B")
	tick(d, sim, 1)
	check(d.lost_start and d.vat_lost and not d.optional_ok() and d.optional_locked(),
			"01: a captured start vat -> ★★★ and the optional gone (live cross)")
	capture(sim, home, "A")
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] and got[0]["stars"] == 2 and not got[0]["objective"],
			"01: won with a start node lost -> 2 stars, no optional %s" % [got])
	# won after par: 1 star
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	sim.time = d.par() + 5.0
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] and got[0]["stars"] == 1, "01: won after par -> 1 star %s" % [got])
	# lost: A is out
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	take_all(sim, "A", "B")
	tick(d, sim, 30)
	check(got.size() == 1 and not got[0]["won"] and got[0]["stars"] == 0 and not got[0]["objective"],
			"01: A out -> lost, 0 stars (%s)" % [got[0].get("reason", "") if not got.is_empty() else "none"])


func test_02_drops() -> void:
	var k := "vex:02"
	var m := Campaign.mission(k)
	var n := int(m["objective"]["n"])
	# 40 dropped with 2 fires (the optional), then the rest: won, optional met
	var r := make(k)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	check(d.objective_line().begins_with("DROPS 0 / %d" % n), "02: '%s'" % d.objective_line())
	fire(sim)
	fire(sim)
	relay_drop(sim, 25)
	relay_drop(sim, 3, "B")                          # the rival's own relay dropping its own line: not yours
	relay_drop(sim, 10, "A", "A")                    # your own line: not a drop
	tick(d, sim, 1)
	check(Rules.shown(d.drops) == 25 and d.fires == 2 and d.pulse > 0.0 and d.objective_line().begins_with("DROPS 25 / %d" % n),
			"02: only your relays' rival falls count, the line glows ('%s')" % d.objective_line())
	check(not d.optional_ok(), "02: optional not met at 25 (live cross)")
	relay_drop(sim, 16)
	tick(d, sim, 1)
	check(d.drops_fires_at == 2 and d.optional_ok(), "02: 41 dropped with 2 fires -> optional met")
	fire(sim)
	fire(sim)
	relay_drop(sim, float(n))
	tick(d, sim, 1)
	check(got.size() == 1 and got[0]["won"] and got[0]["objective"] and got[0]["stars"] == 3,
			"02: %d dropped -> won, 3 stars, optional kept after more fires %s" % [n, got])
	# too many fires before 40: optional gone for good
	r = make(k)
	d = r[0]
	sim = r[1]
	for i in range(4):
		fire(sim)
	relay_drop(sim, 10)
	tick(d, sim, 1)
	check(not d.optional_ok() and d.optional_locked(), "02: 4 fires before 40 dropped -> optional locked")
	# the time limit passes: lost
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	relay_drop(sim, 12)
	sim.time = float(m["objective"]["limit"]) + 0.1
	tick(d, sim, 1)
	check(got.size() == 1 and not got[0]["won"] and got[0]["reason"] == "limit", "02: the limit passes -> lost %s" % [got])
	# conquered before the drops: the objective was not met -> lost
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and not got[0]["won"] and got[0]["reason"] == "objective",
			"02: a conquest without the drops is not the objective -> lost")


func test_s1_survive() -> void:
	var k := "vex:s1"
	var m := Campaign.mission(k)
	var t := float(m["objective"]["t"])
	var r := make(k)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	var bh: Dictionary = sim.nodes[int(sim.homes["B"])]
	# staging: the rival starts with its home's garrison + stage.rival_units (shown)
	var r2 := make(k, {}, 7)
	var plain := Sim.new()
	var map := MapBuilder.load_map(str(m["map"]))
	var seats := {}
	for s in map["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	plain.setup(map, MapBuilder.layout(map), seats, {"A": "vex", "B": "ember"}, 7, {}, {})
	var before := float(plain.nodes[int(plain.homes["B"])]["units"])
	check(is_equal_approx(float(bh["units"]), before + float(m["stage"]["rival_units"]) * Rules.SCALE),
			"s1: +%d shown units on the rival's home (%d -> %d shown)" % [int(m["stage"]["rival_units"]),
			Rules.shown(before), Rules.shown(float(bh["units"]))])
	check(d.objective_line().begins_with("HOLD UNTIL 3:00"), "s1: '%s'" % d.objective_line())
	check(not d.optional_ok(), "s1: no T3 Machinegoon yet (live cross)")
	var mg: Dictionary = sim.nodes[int(sim.homes["A"])]
	mg["structure"] = "machinegoon"
	mg["tier"] = 3
	check(d.optional_ok(), "s1: a T3 Machinegoon standing -> tick")
	sim.time = t - DT * 0.5
	tick(d, sim, 2)
	check(got.size() == 1 and got[0]["won"] and got[0]["objective"] and got[0]["reason"] == "survived" and got[0]["stars"] >= 2,
			"s1: still in at %d s -> won, optional met, %d stars" % [int(t), got[0]["stars"] if not got.is_empty() else -1])
	# out before the whistle: lost
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	sim.time = t - 30.0
	take_all(sim, "A", "B")
	tick(d, sim, 30)
	check(got.size() == 1 and not got[0]["won"], "s1: out before %d s -> lost" % int(t))
	r2.clear()


func test_03_duel() -> void:
	var k := "vex:03"
	var m := Campaign.mission(k)
	var r := make(k)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	check(float(sim.nodes[int(sim.homes["B"])]["units"]) > float(m["stage"]["rival_units"]) * Rules.SCALE,
			"03: the Foreman starts bigger")
	check(d.optional_ok(), "03: before the ultimate (live tick)")
	sim.events.append({"t": sim.time, "type": "skill", "id": "active_x", "seat": "B", "slot": "active", "target": null})
	tick(d, sim, 1)
	check(d.optional_ok(), "03: a rival ACTIVE skill is not the ultimate")
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] and got[0]["objective"], "03: won before the ultimate -> optional met")
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	sim.events.append({"t": sim.time, "type": "skill", "id": "inferno", "seat": "B", "slot": "ultimate", "target": null})
	tick(d, sim, 1)
	check(not d.optional_ok() and d.optional_locked(), "03: the rival's ultimate -> optional locked")
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] and not got[0]["objective"], "03: won after the ultimate -> no optional")
	r = make(k)
	d = r[0]
	sim = r[1]
	got = outcome(d)
	take_all(sim, "A", "B")
	tick(d, sim, 30)
	check(got.size() == 1 and not got[0]["won"], "03: the Foreman wins -> lost")


func test_record() -> void:
	Campaign.reset_progress()
	var r := make("vex:01")
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	var s := Campaign.record("vex:01", got[0])
	check(s["stars"] == 3 and s["objective"] and s["reward"]["state"] == "earned" and int(s["reward"]["amount"]) == 150
			and s["next"] == "vex:02" and s["first_win"], "record 01: 3 stars + optional -> +150 earned (no wallet), next 02 %s" % [s])
	r = make("vex:02")
	d = r[0]
	sim = r[1]
	got = outcome(d)
	sim.time = float(Campaign.mission("vex:02")["objective"]["limit"]) + 1.0
	tick(d, sim, 1)
	s = Campaign.record("vex:02", got[0])
	check(s["stars"] == 0 and s["reward"]["state"] == "none" and s["next"] == "vex:02" and not Campaign.is_won("vex:02"),
			"record 02 lost: 0 stars, no reward, 02 still next %s" % [s])
	check(Campaign.progress_match(sim, "A", "Casual").is_empty(), "progress_match without Progression -> {}")
	Campaign.reset_progress()


func test_other_kinds() -> void:
	## The kinds District 1 does not use, on a mission dict of the test's own (vex:01's map).
	var base := Campaign.mission("vex:01")
	var mk := func(objective: Dictionary, op: Dictionary) -> Dictionary:
		var m: Dictionary = base.duplicate(true)
		m["objective"] = objective
		m["optional"] = op
		return m
	# monster_take + monster_kicks
	var r := make("t:monster", mk.call({"kind": "monster_take"}, {"kind": "monster_kicks", "n": 30, "text": "k"}))
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	var got := outcome(d)
	sim.events.append({"t": sim.time, "type": "monster_kick", "id": 1, "seat": "A", "seat_hit": "B", "units": 31.0 * Rules.SCALE})
	sim.events.append({"t": sim.time, "type": "monster_take", "id": 1, "seat": "A", "node": 3, "friendly": false})
	tick(d, sim, 1)
	check(got.size() == 1 and got[0]["won"] and got[0]["objective"], "monster_take + monster_kicks 31/30 -> won, optional")
	# no_skill / fires / home_kept / units_at_end / unknown
	r = make("t:skill", mk.call({"kind": "conquest"}, {"kind": "no_skill", "skill": "demolish", "text": "s"}))
	d = r[0]
	sim = r[1]
	check(d.optional_ok(), "no_skill: tick before any cast")
	sim.events.append({"t": sim.time, "type": "skill", "id": "demolish", "seat": "A", "slot": "map", "target": 0})
	tick(d, sim, 1)
	check(not d.optional_ok() and d.optional_locked(), "no_skill: casting it -> locked")
	r = make("t:fires", mk.call({"kind": "conquest"}, {"kind": "fires", "n": 5, "text": "f"}))
	d = r[0]
	sim = r[1]
	for i in range(5):
		fire(sim)
	fire(sim, "B")
	tick(d, sim, 1)
	check(d.fires == 5 and d.optional_ok() and d.optional_line().ends_with("(5 / 5)"), "fires: 5 of yours -> tick ('%s')" % d.optional_line())
	r = make("t:home", mk.call({"kind": "conquest"}, {"kind": "home_kept", "text": "h"}))
	d = r[0]
	sim = r[1]
	capture(sim, int(sim.homes["A"]), "B")
	tick(d, sim, 1)
	check(d.home_lost and not d.optional_ok(), "home_kept: the home captured -> cross")
	r = make("t:units", mk.call({"kind": "outlast", "n": 5}, {"kind": "units_at_end", "n": 1, "text": "u"}))
	d = r[0]
	sim = r[1]
	got = outcome(d)
	check(d.optional_ok() and d.objective_line().begins_with("WIN WITH 5+ UNITS"), "units_at_end: live ('%s')" % d.objective_line())
	take_all(sim, "B", "A")
	tick(d, sim, 30)
	check(got.size() == 1 and got[0]["won"] == (Rules.shown(sim.seat_strength("A")) >= 5), "outlast: won iff 5+ units at the end %s" % [got])
	r = make("t:unknown", mk.call({"kind": "conquest"}, {"kind": "all_pods", "text": "p"}))
	d = r[0]
	check(not d.optional_ok(), "an unknown optional kind is never met")


func test_pins() -> void:
	## 2026-09-28 audit (a bug fix): a mission plays its own ABILITIES / LAST STAND / HIDDEN COUNTS, never SETUP's or a
	## room's; restore_settings() gives the player's own back.
	var keep := [Rules.abilities_on, Rules.last_stand, Rules.hide_enemy_counts]
	Rules.abilities_on = false
	Rules.last_stand = false
	Rules.hide_enemy_counts = true
	var m := Campaign.mission("vex:01").duplicate(true)
	MissionDirector.pin_settings(MissionDirector.mission_pins(m))   # main.start_mission, before sim.setup
	var r := make("t:pins", m)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	check(Rules.abilities_on and Rules.last_stand and not Rules.hide_enemy_counts and sim.abilities_on,
			"a mission pins ABILITIES on, LAST STAND on, HIDDEN COUNTS off (SETUP had them off / off / on)")
	MissionDirector.restore_settings()
	check(not Rules.abilities_on and not Rules.last_stand and Rules.hide_enemy_counts, "restore_settings -> the player's own three back")
	Rules.abilities_on = keep[0]
	Rules.last_stand = keep[1]
	Rules.hide_enemy_counts = keep[2]
	d = null


func test_hide_counts() -> void:
	var before := Rules.hide_enemy_counts
	Rules.hide_enemy_counts = false
	var m := Campaign.mission("vex:01").duplicate(true)
	m["stage"] = {"hide_counts": true}
	make("t:blind", m)
	check(Rules.hide_enemy_counts, "stage.hide_counts -> HIDE ENEMY COUNTS on")
	MissionDirector.restore_settings()
	check(not Rules.hide_enemy_counts, "restore_settings -> the player's own setting back")
	Rules.hide_enemy_counts = before


func test_collapse_at() -> void:
	var m := Campaign.mission("vex:01").duplicate(true)
	m["objective"] = {"kind": "outlast", "collapse_at": 2.0, "n": 1}
	var r := make("t:collapse", m)
	var d: MissionDirector = r[0]
	var sim: Sim = r[1]
	check(d.objective_line().contains("collapse in"), "collapse_at: the countdown shows ('%s')" % d.objective_line())
	tick(d, sim, 30)
	check(not d.collapse_started and not sim.last_stand_active, "collapse_at: nothing before 2 s")
	tick(d, sim, 20)
	check(d.collapse_started and sim.last_stand_active, "collapse_at: the Last Stand starts at 2 s (t=%.2f)" % sim.time)
