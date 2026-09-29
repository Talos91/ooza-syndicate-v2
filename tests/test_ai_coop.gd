extends SceneTree
## AI teamwork check:  Godot --headless --path . --script res://tests/test_ai_coop.gd
## Exit code 0 = all passed.
## Co-op (0.21.5, Daniele 2026-09-28: "make sure ai take advantage of coop mode and is more strong (but not
## unbeatable)"): on every 2v2 map one team plays with its teamwork (Rules.AI_LEVELS "teamwork" and friends), the
## other team is the same level with teamwork 0 - identical economy, combat and every other knob. Each map is
## played with SEEDS fixed seeds, twice each, the teams swapping which one coordinates. At Standard and Veteran the
## coordinating team must win clearly more (>= 60 %) but not always (<= 90 %). `-- levels=all` (or a comma list) also prints
## the other three levels (not checked: Training has no teamwork, Casual barely any); `-- maps=N` caps the sample.
## - Common enemy: with one rival seat played by a human (no SeatAI thinks for it), a team's focus is that human.
## The AI seats play what they get in a match (ai-retune-prep): Sim.ai_builds on, so each takes one of its faction's
## Rules.AI_LOADOUTS builds by the fixed seed. `-- guard=off` plays them without their home-defence reflex (SeatAI._guard).

const CHECKED := ["Standard", "Veteran"]
const SEEDS := 2
var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return fallback


func _match(path: String, level: String, coop_team: int, seed_value: int, limit := 420.0) -> float:
	## One 2v2 match, every seat `level`; only team `coop_team` keeps its teamwork. 1 = that team won, 0 = lost,
	## 0.5 = a draw or undecided at the limit with the teams level (ahead at the limit counts 0.75 / 0.25).
	var m := MapBuilder.load_map(path)
	var seats := {}
	var teams := {}
	for s in m["seats"]["2v2"]:
		seats[int(s["node"])] = s["seat"]
		teams[s["seat"]] = int(s["team"])
	var sim := Sim.new()
	sim.ai_builds = true                              # the AI seats' rotating builds, as in play
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null", "C": "null", "D": "null"}, seed_value, teams)
	var ais := []
	for seat in seats.values():
		var ai := SeatAI.new(seat, 2.5, level)
		if teams[seat] != coop_team:
			ai.cfg = ai.cfg.duplicate()               # Rules.AI_LEVELS is shared: never write into it
			ai.cfg["teamwork"] = 0
		ais.append(ai)
	while not sim.over and sim.time < limit:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	if sim.over and sim.winner != "":
		return 1.0 if teams[sim.winner] == coop_team else 0.0
	var mine := 0.0
	var theirs := 0.0
	for seat in teams:
		if teams[seat] == coop_team:
			mine += sim.seat_strength(seat)
		else:
			theirs += sim.seat_strength(seat)
	return 0.5 if sim.over or absf(mine - theirs) < 1.0 else (0.75 if mine > theirs else 0.25)


func _human_focus(pool: Array) -> void:
	## Every 2v2 map: AIs for three seats, the fourth (a rival) left to a "human"; after the first thinks the
	## AI team's common enemy is the human. Then the same with the other rival as the human.
	var ok := 0
	var runs := 0
	for p in pool:
		var m := MapBuilder.load_map(p)
		var seats := {}
		var teams := {}
		for s in m["seats"]["2v2"]:
			seats[int(s["node"])] = s["seat"]
			teams[s["seat"]] = int(s["team"])
		var mates: Array = teams.keys().filter(func(s): return teams[s] == teams["A"])
		var rivals: Array = teams.keys().filter(func(s): return teams[s] != teams["A"])
		for human in rivals:
			var sim := Sim.new()
			sim.ai_builds = true
			sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null", "C": "null", "D": "null"}, 7, teams)
			var ais := []
			for s in mates + rivals.filter(func(r): return r != human):
				ais.append(SeatAI.new(s, 2.5, "Veteran"))
			while sim.time < Rules.AI_TEAM_HUMAN_AFTER + 1.0:
				for ai in ais:
					ai.think(sim, 0.1)
				sim.step(0.1)
			runs += 1
			if ais[0]._team_focus(sim) == human:
				ok += 1
	check(ok == runs, "a team of AIs picks the human rival as its common enemy (%d / %d)" % [ok, runs])


func _run() -> void:
	Rules.last_stand = false                       # decide by play, not by the collapse (the Very Last Stand still runs)
	SeatAI.guard_on = _arg("guard", "on") != "off"
	var cap := int(_arg("maps", "0"))
	var pick := _arg("levels", "")                   # "all", or a comma list (a parallel run); default: CHECKED
	var levels: Array = CHECKED if pick == "" else (Rules.AI_LEVELS.keys() if pick == "all" else Array(pick.split(",")))
	# 0.23.0: teamwork is measured on every baked 2v2 map (the new pool has only 2 - too few for a win-rate band)
	var pool := MapPool.all().filter(func(p): return not p.get_file().substr(0, 4) in MapPool.TUTORIAL_ONLY and MapBuilder.load_map(p)["seats"].has("2v2"))
	_human_focus(pool)
	var games := pool.size() if cap <= 0 else mini(pool.size(), cap)
	print("      co-op on %d 2v2 maps: %s" % [games, ", ".join(pool.slice(0, games).map(func(p): return p.get_file().substr(0, 4)))])
	for lv in levels:
		var w := 0.0
		for i in range(games):
			for team in range(2):                         # each team coordinates once
				for k in range(SEEDS):
					w += _match(pool[i], lv, team, 300 + i + 1000 * k)
		var rate := w / (games * 2.0 * SEEDS)
		print("      %-8s teamwork on vs off: %.0f %%" % [lv, rate * 100.0])
		if lv in CHECKED:
			check(rate >= 0.60 and rate <= 0.90, "%s: the coordinating team wins clearly more but not always (%.0f %%, wanted 60-90 %%)" % [lv, rate * 100.0])
	Rules.last_stand = true
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
