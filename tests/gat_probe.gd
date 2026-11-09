extends SceneTree
## GooGat probe (demo-rules-pass): R-01's neutral T2 GooGat (node 9) under an attacking line - its garrison (= ammo), the
## shots, the attacker's units, every 0.5 s.  Godot --headless --path . --script res://tests/gat_probe.gd

func _sim() -> Sim:
	var m := MapBuilder.load_map("res://maps4/R-01-strait.json")
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
	return s


func _case(label: String, gat_owner: String, src: int, units: float) -> void:
	var s := _sim()
	var g: Dictionary = s.nodes[9]
	if gat_owner != "":
		g["owner"] = gat_owner
	print("== %s: GooGat 9 owner '%s' T%d garrison %.0f (shown %.0f), fire %.1f/s, regrow %.2f/s, range %.0f" % [label, g["owner"], g["tier"],
			g["units"], Rules.shown(g["units"]), Sim.gat_fire_rate(g), s.gat_rate(g), Rules.MACHINEGOON_RANGE])
	s.nodes[src]["owner"] = "A"
	s.nodes[src]["units"] = units
	var h := s.send(src, 9, 1.0)
	var t := 0.0
	var fired := 0.0
	var last := -1.0
	var g0: float = g["units"]
	while t < 25.0:
		var gu: float = g["units"]
		s.step(0.05)
		t += 0.05
		var sh: Dictionary = g.get("shot", {})
		if not sh.is_empty() and absf(float(sh["t"]) - s.time) < 0.001:
			fired += float(sh["kills"])
		if t - last >= 0.5:
			last = t
			print("  t %4.1f  gat garrison %6.1f  owner '%s'  shots so far %6.1f  attacker %s" % [t, g["units"], g["owner"], fired,
					"%.1f %s" % [h["units"], h["state"]] if h in s.hordes else "gone"])
		if g["owner"] == "A":
			break
	print("  -> garrison %.1f -> %.1f, fired %.1f units" % [g0, g["units"], fired])


func _init() -> void:
	_case("neutral, 100 send", "", 4, 100.0)
	_case("neutral, 400 send", "", 4, 400.0)
	_case("B's GooGat, 400 send", "B", 4, 400.0)
	quit(0)
