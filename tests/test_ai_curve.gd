extends SceneTree
## AI difficulty and fairness check:  Godot --headless --path . --script res://tests/test_ai_curve.gd
## Exit code 0 = all passed.
## - Fairness (Daniele, Alpha 17: "all AIs work together to kill the human"): in FFA matches where
##   every seat is the same AI, seat A - the human's seat - must not draw more than its share of the
##   hostile sends aimed at players (at most 1.5x an even split).
## - Curve (Alpha 11's five levels): each level plays a fixed Standard AI on the same 1v1 maps; the
##   stronger the level, the more it wins, and Training never beats Standard more often than Expert.

const LEVELS := ["Training", "Casual", "Standard", "Veteran", "Expert"]
var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	Rules.bridge_combat = true                      # these checks were written for SIEGE (the old default); BRAWL is the game's default since 0.18.7
	_run.call_deferred()


func _match(path: String, mode: String, levels: Dictionary, seed_value: int, limit := 420.0) -> Sim:
	var m := MapBuilder.load_map(path)
	var seats := {}
	var teams := {}
	for s in m["seats"][mode]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null", "C": "null", "D": "null", "E": "null", "F": "null"}, seed_value, teams)
	var ais := []
	for seat in seats.values():
		ais.append(SeatAI.new(seat, 2.5, levels.get(seat, "Standard")))
	while not sim.over and sim.time < limit:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	return sim


func _run() -> void:
	Rules.last_stand = false                       # decide by play, not by the collapse
	# ---------------------------------------------------------------- fairness in FFA
	var ffa := MapPool.all().filter(func(p): return MapBuilder.load_map(p)["seats"].has("FFA4"))
	var on_a := 0
	var on_players := 0
	var seats_n := 4
	for i in range(mini(ffa.size(), 8)):
		var sim := _match(ffa[i], "FFA4", {}, 11 + i, 240.0)
		for e in sim.events:
			if e["type"] != "send":
				continue
			var owner_at: String = e.get("target_owner", "")
			if owner_at != "" and owner_at != e["seat"]:
				on_players += 1
				if owner_at == "A":
					on_a += 1
	var share := float(on_a) / maxf(on_players, 1.0)
	print("      FFA4: %d hostile sends at players, %d at seat A (share %.2f, even %.2f)" % [on_players, on_a, share, 1.0 / (seats_n - 1)])
	check(on_players > 20, "FFA4 AIs attack players (%d sends)" % on_players)
	check(share <= 1.5 / (seats_n - 1), "seat A draws no more than 1.5x its share of the attacks (%.2f)" % share)
	# ---------------------------------------------------------------- the curve
	var duel := MapPool.all().filter(func(p):
		var m := MapBuilder.load_map(p)
		return m["seats"].has("1v1") and m.get("group", "") in ["core", "brawl", "siege"])
	var games := mini(duel.size(), 10)
	var wins := {}
	for lv in LEVELS:
		var w := 0.0
		for i in range(games):
			for side in range(2):                         # each level plays both seats
				var seat := "A" if side == 0 else "B"
				var other := "B" if side == 0 else "A"
				var sim := _match(duel[i], "1v1", {seat: lv, other: "Standard"}, 100 + i)
				if sim.over and sim.winner == seat:
					w += 1.0
				elif not sim.over and sim.seat_strength(seat) > sim.seat_strength(other):
					w += 0.5                               # undecided at the limit: ahead counts half
		wins[lv] = w / (games * 2.0)
		print("      %-8s vs Standard: %.0f %%" % [lv, wins[lv] * 100.0])
	check(wins["Training"] < wins["Standard"] + 0.05 and wins["Casual"] < wins["Veteran"] + 0.05, "levels below Standard win less than those above")
	check(wins["Expert"] >= wins["Training"] + 0.25, "Expert wins clearly more than Training (%.2f vs %.2f)" % [wins["Expert"], wins["Training"]])
	Rules.last_stand = true
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
