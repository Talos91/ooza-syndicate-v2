extends SceneTree
## VAT ARMOUR check (2026-11-03):  Godot --headless --path . --script res://tests/armour_check.gd
## A captured T4 keeps its tier and climbs 1.0 -> 1.6 in 60 s; a captured T3 -> T2 climbs 1.0 -> 1.2 in 20 s; homes start
## at their tier's armour; garrison_div carries it. Uneven step sizes on purpose (the closed form must not drift).

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	var map := MapBuilder.load_map("res://maps/004-two-piers.json")
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), {3: "A", 4: "B"}, {"A": "null", "B": "ember"}, 1)
	var home: Dictionary = sim.nodes[3]
	check(is_equal_approx(float(home["armour"]), float(Rules.ARMOUR_TIER[int(home["tier"])])),
			"home T%d starts at armour %.2f" % [home["tier"], home["armour"]])
	var t4: Dictionary = sim.nodes[1]
	var t2: Dictionary = sim.nodes[2]
	for pair in [[t4, 4], [t2, 3]]:
		var n: Dictionary = pair[0]
		n["owner"] = "A"
		n["structure"] = "vat"
		n["tier"] = pair[1]
	sim.step(0.05)
	sim._capture(t4, "B", 10.0)
	sim._capture(t2, "B", 10.0)
	check(int(t4["tier"]) == 4 and int(t2["tier"]) == 2, "capture: T4 stays T4, T3 drops to T2")
	check(float(t4["armour"]) == 1.0 and float(t2["armour"]) == 1.0, "capture: armour 1.0")
	var t0 := sim.time
	var marks := [10.0, 19.9, 20.05, 30.0, 59.9, 60.05, 70.0]
	var steps := [0.05, 0.016, 0.033, 0.05, 0.1]
	var k := 0
	for m in marks:
		while sim.time - t0 < m:
			sim.step(steps[k % steps.size()])
			k += 1
		print("t+%5.2f s  T4 armour %.4f  T2 armour %.4f  T4 garrison_div %.3f" % [sim.time - t0, t4["armour"], t2["armour"], sim.garrison_div(t4)])
		if m == 19.9:
			check(float(t2["armour"]) < 1.2, "T2 still below 1.2 just before 20 s")
		if m == 20.05:
			check(is_equal_approx(float(t2["armour"]), 1.2), "T2 at 1.2 after 20 s")
		if m == 59.9:
			check(float(t4["armour"]) < 1.6, "T4 still below 1.6 just before 60 s")
		if m == 60.05:
			check(is_equal_approx(float(t4["armour"]), 1.6), "T4 at 1.6 after 60 s")
	check(is_equal_approx(float(t4["armour"]), 1.6) and is_equal_approx(float(t2["armour"]), 1.2), "capped at the tier value")
	check(sim.garrison_div(t4) >= 1.6 - 0.0001, "garrison_div includes the armour")
	print("armour_check: %d failure(s)" % failures)
	quit(1 if failures else 0)
