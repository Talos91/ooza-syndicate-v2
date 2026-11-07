extends Node
## Deck (bridge) tap-width probe (2026-11-01, Daniele: "bridges are sometimes hard to click"). A dev tool, not a suite.
## Run WINDOWED as a scene (the camera must project; the Net autoload):
##   Godot --path . --resolution 1266x585 res://tests/deck_tap_probe.tscn -- maps=A-01,M-39,M-57 [pt=844] [out=<file>]
## For every map it starts the real game on the phone profile, lets the camera fit, then for every deck measures the
## band across its middle (perpendicular to the deck on screen) within which SkillDock._deck_at - the pick behind
## Scorch / Mire / Anchor / Demolish / Backwash / Sever - answers that deck: its width in points on an 844 x 390 pt
## screen (phone_fit's reference). Also counts how many node centres a deck pick would steal (should be 0: nodes keep
## priority). Output: one line per map (min / median / max width, decks under 33 and 44 pt), a LIST of the narrowest.

const MAIN := "res://main.tscn"
var out_lines: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _measure(m: Node, pt_w: float) -> Dictionary:
	var cam: Camera3D = m.cam
	var dock = m.hud.dock
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var ppt := pt_w / vp.x
	var widths := []                                   # [pt, edge index]
	for ei in range(m.sim.edges.size()):
		var pts: PackedVector2Array = dock._deck_px(ei, cam)
		if pts.size() < 2:
			continue
		# the middle segment's midpoint, and its screen normal
		var k := (pts.size() - 1) / 2
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var mid := (a + b) / 2.0
		var dir := (b - a).normalized()
		if dir.length() < 0.5:
			continue
		var nrm := Vector2(-dir.y, dir.x)
		if dock._deck_at(mid, cam) != ei:
			widths.append([0.0, ei])
			continue
		var reach := [0.0, 0.0]
		for side in range(2):
			var sgn := 1.0 if side == 0 else -1.0
			var t := 0.0
			while t < 160.0:
				t += 0.5
				if dock._deck_at(mid + nrm * sgn * t, cam) != ei:
					break
			reach[side] = t - 0.5
		widths.append([(reach[0] + reach[1]) * ppt, ei])
	widths.sort_custom(func(x, y): return x[0] < y[0])
	var stolen := 0                                    # node centres a deck pick would take
	for n in m.sim.nodes:
		if m.sim.collapsed.get(n["id"], false) or n.get("node_kind", "") == "junction":
			continue
		if dock._deck_at(cam.unproject_position(n["pos"]), cam) >= 0:
			stolen += 1
	var vals := widths.map(func(x): return x[0])
	return {"n": widths.size(), "min": vals.min() if not vals.is_empty() else 0.0,
			"med": vals[vals.size() / 2] if not vals.is_empty() else 0.0, "max": vals.max() if not vals.is_empty() else 0.0,
			"under33": vals.filter(func(v): return v < 33.0).size(), "under44": vals.filter(func(v): return v < 44.0).size(),
			"stolen": stolen, "narrow": widths.slice(0, 3), "vp": vp, "scale": dock.ui_scale, "ppt": ppt}


func _run() -> void:
	var out_path := _arg("out", "")
	var only := _arg("maps", "A-01,M-39,M-57").split(",")
	var pt_w := float(_arg("pt", "844"))
	var main_script = load("res://scripts/main.gd")
	for path in MapPool.all():
		var code: String = path.get_file().substr(0, 4)
		if not code in only:
			continue
		var mp := MapBuilder.load_map(path)
		main_script.relaunch = {"faction": "null", "mode": mp["modes"][0], "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.mobile = true
		get_tree().root.add_child(inst)
		await _frames(10)
		var r := _measure(inst, pt_w)
		var line := "%s  (vp %dx%d, dock scale %.2f, %.3f pt/px)  decks %2d  hit band pt: min %5.1f  median %5.1f  max %5.1f   under 33 pt: %d  under 44 pt: %d   node centres taken by a deck: %d   narrowest: %s" % [
				code, int(r["vp"].x), int(r["vp"].y), r["scale"], r["ppt"], r["n"], r["min"], r["med"], r["max"], r["under33"], r["under44"], r["stolen"],
				", ".join(r["narrow"].map(func(x): return "e%d %.1f" % [x[1], x[0]]))]
		print(line)
		out_lines.append(line)
		inst.queue_free()
		await _frames(3)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(out_lines) + "\n")
		f.close()
	get_tree().quit(0)
