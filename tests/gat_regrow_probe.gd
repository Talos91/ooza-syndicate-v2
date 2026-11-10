extends SceneTree
## GooGat regrow probe (demo-rules-pass-2; Daniele 2026-11-09 Desk googat-unlimited = c, "slower regrow"): at the old and the new
## Rules.GOOGATLING_PROD, (1) seconds to refill from empty, per tier, neutral (to its neutral garrison) and owned (to its cap);
## (2) SUSTAINED FIRE: B's T2 GooGat on R-01 under a stream of small A lines, its ammo every 0.5 s (CSV for the curve).
## Numbers shown at Alpha 11 scale (Rules.shown).   Godot --headless --path . --script res://tests/gat_regrow_probe.gd [-- csv=<file>]

const OLD := 0.5


func _sim() -> Sim:
	var m := MapBuilder.load_map("res://maps4/R-01-strait.json")
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
	return s


func _gat(s: Sim) -> int:
	for n in s.nodes:
		if n["structure"] == "machinegoon":
			return n["id"]
	return -1


func _refill(prod: float, tier: int, owner: String) -> float:
	Rules.GOOGATLING_PROD = prod
	var s := _sim()
	var g: Dictionary = s.nodes[_gat(s)]
	g["tier"] = tier
	g["owner"] = owner
	g["units"] = 0.0
	var full: float = float(Rules.CAPS[tier]) if owner != "" else float(Rules.NEUTRAL_UNITS[tier])
	var t := 0.0
	while t < 900.0 and g["units"] < full - 0.5:
		s.step(0.1)
		t += 0.1
	return t


func _fight(prod: float, per_s: float, stream_s: float) -> Array:
	## SUSTAINED FIRE: B's T2 GooGat on R-01 (node 9, full: 60 shown) under a stream of small A lines from node 4 - `per_s`
	## shown units a second for `stream_s` s, one line a second - then nothing. Its ammo every 0.5 s.
	Rules.GOOGATLING_PROD = prod
	var s := _sim()
	var gid := 9 if s.nodes[9]["structure"] == "machinegoon" else _gat(s)
	var g: Dictionary = s.nodes[gid]
	g["owner"] = "B"
	g["units"] = float(Rules.CAPS[int(g["tier"])])
	s.nodes[4]["owner"] = "A"
	var rows := []
	var t := 0.0
	var dry := -1.0
	var back := -1.0
	var next_send := 0.0
	var fell := -1.0
	while t < 260.0:
		if t < stream_s and t >= next_send:
			s.nodes[4]["units"] = per_s * 5.0           # (shown -> sim: x5) exactly one second's worth
			s.send(4, gid, 1.0)
			next_send += 1.0
		s.step(0.05)
		t += 0.05
		if g["owner"] != "B" and fell < 0.0:
			fell = t
		if dry < 0.0 and g["units"] < 1.0:
			dry = t
		if t > stream_s and back < 0.0 and g["owner"] == "B" and g["units"] >= float(Rules.CAPS[int(g["tier"])]) - 0.5:
			back = t
		if int(round(t * 20.0)) % 10 == 0:
			rows.append([snappedf(t, 0.5), Rules.shown_f(g["units"]) if g["owner"] == "B" else -1.0])
	return [rows, dry, back, fell]


func _init() -> void:
	var NEW: float = Rules.GOOGATLING_PROD
	print("GOOGAT REGROW: Rules.GOOGATLING_PROD old %.2f -> new %.2f (x the same-tier vat rate); fire %s kills/s (sim)" % [OLD, NEW, Rules.MACHINEGOON_RATE])
	print("refill from EMPTY (seconds; shown units)        old      new")
	for tier in [1, 2, 3]:
		for owner in ["", "B"]:
			var full: int = Rules.shown(float(Rules.CAPS[tier]) if owner != "" else float(Rules.NEUTRAL_UNITS[tier]))
			print("  T%d %-7s to %3d shown  regrow %.2f -> %.2f /s   %5.1f s  %5.1f s" % [tier, "neutral" if owner == "" else "owned", full,
					Rules.shown_f(Rules.PROD[tier] * OLD), Rules.shown_f(Rules.PROD[tier] * NEW), _refill(OLD, tier, owner), _refill(NEW, tier, owner)])
	var csv := "t,old_ammo_shown,new_ammo_shown
"
	var per_s := 2.0
	var stream_s := 40.0
	var a := _fight(OLD, per_s, stream_s)
	var b := _fight(NEW, per_s, stream_s)
	print("SUSTAINED FIRE: B's T2 GooGat (60 shown) on R-01, A streams %.1f shown/s at it for %.0f s, then stops:" % [per_s, stream_s])
	for r in [["old", a], ["new", b]]:
		var x: Array = r[1]
		print("  %s: dry at %s, captured at %s, full again at %s" % [r[0], "%.1f s" % x[1] if x[1] >= 0.0 else "never",
				"%.1f s" % x[3] if x[3] >= 0.0 else "never", "%.1f s" % x[2] if x[2] >= 0.0 else "-"])
	for i in range(mini(a[0].size(), b[0].size())):
		csv += "%s,%s,%s
" % [a[0][i][0], a[0][i][1], b[0][i][1]]
	Rules.GOOGATLING_PROD = NEW
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("csv="):
			var f := FileAccess.open(arg.substr(4), FileAccess.WRITE)
			f.store_string(csv)
			f.close()
	quit(0)
