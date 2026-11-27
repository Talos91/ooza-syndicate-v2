extends SceneTree
## SAFE AREA PROBE (Ooze 3.0 WP4, Daniele 2026-11-27: the HUD's side panels hug each edge by the device's real safe area per side,
## both landscape rotations). Headless, geometry only. For every EMULATED device below (CSS pt screen + the side insets its browser
## reports in landscape: iOS Safari = the same inset left and right; Android Chrome = the cut-out side only) and both rotations
## (90 = the phone's top / cut-out on the LEFT, 270 = on the RIGHT) it starts Z-05 at that size with those insets and prints
##   SAFE <device> rot <a>  vp <w>x<h>  reported L <l> R <r>  used L <l> R <r>  tank@ <pt>  skills@ <pt>  ai_l <x> ai_r <x>
## (tank@ = the SEND tank art's distance from the LEFT screen edge, skills@ = the skill plates' distance from the RIGHT edge, pt).
##   Godot --headless --path . --script res://tests/safe_area_probe.gd -- --mobile [devices=iPhone 13,Pixel 9]
## Checks (exit 1 on a failure): nothing of the HUD inside the used inset of either side; the side AWAY from the cut-out hugs its
## edge (<= HUG_PT); the cut-out side keeps the reported inset. Not a device test: the numbers are what each phone is documented
## to report (iOS) or assumed (Android: the cut-out band), the phone's own report is what the game uses.
const HUG_PT := 12.0
const MAP := "Z-05"
## name, landscape CSS w, h, reported left = right (iOS) or cut-out side (Android), platform
const DEVICES := [
	["iPhone 13 / 13 Pro / 14", 844, 390, 47, "ios"],
	["iPhone 13 Pro Max / 14 Plus", 926, 428, 47, "ios"],
	["iPhone 14 Pro / 15 / 15 Pro / 16", 852, 393, 59, "ios"],
	["iPhone 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus", 932, 430, 59, "ios"],
	["iPhone 16 Pro", 874, 402, 62, "ios"],
	["iPhone 16 Pro Max", 956, 440, 62, "ios"],
	["Galaxy S22 / S23 / S24 / S25", 780, 360, 30, "android"],
	["Galaxy S22+ / S23+ / S24+ / S25+", 832, 384, 30, "android"],
	["Galaxy S22 Ultra / S23 Ultra", 824, 384, 30, "android"],
	["Galaxy S24 Ultra", 832, 384, 30, "android"],
	["Galaxy S25 Ultra", 891, 412, 30, "android"],
	["Pixel 7 / 8", 915, 412, 32, "android"],
	["Pixel 7 Pro", 892, 412, 32, "android"],
	["Pixel 8 Pro", 998, 448, 32, "android"],
	["Pixel 9", 923, 412, 32, "android"],
	["Pixel 9 Pro", 914, 410, 32, "android"],
	["Pixel 9 Pro XL", 921, 414, 32, "android"],
	["(unknown phone: no insets read)", 812, 375, -1, "none"],
]


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := _arg("devices", "")
	var path := ""
	for f in DirAccess.get_files_at("res://maps4/"):
		if f.begins_with(MAP + "-") and f.ends_with(".json"):
			path = "res://maps4/" + f
	var fails := 0
	for d in DEVICES:
		if only != "" and not str(d[0]) in only.split(","):
			continue
		var w := float(d[1])
		var h := float(d[2])
		for rot in ([90, 270] if str(d[4]) != "none" else [-1]):
			UiKit.test_pt_h = h
			root.size = Vector2i(int(w * 2.0), int(h * 2.0))
			await _frames(3)
			var vp := root.get_visible_rect().size
			var k := 1.0 / UiKit.pt_per_px(vp)          # pt -> viewport px
			var rep := Vector2.ZERO                     # reported left, right (pt)
			match str(d[4]):
				"ios":
					rep = Vector2(float(d[3]), float(d[3]))
				"android":
					rep = Vector2(float(d[3]), 0.0) if rot == 90 else Vector2(0.0, float(d[3]))
			if str(d[4]) == "none":
				UiKit.test_insets = Vector4(-1, -1, -1, -1)
			else:
				UiKit.test_insets = Vector4(rep.x * k, 0.0, rep.y * k, (21.0 if str(d[4]) == "ios" else 0.0) * k)
			UiKit.test_orient = rot
			load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1", "map": path}
			change_scene_to_file("res://main.tscn")
			await _frames(45)
			var m: Node = current_scene
			var hud = m.hud
			var used := UiKit.safe_insets(vp)
			var ppp := UiKit.pt_per_px(vp)
			var g: Dictionary = hud.edge_gaps(vp)
			var tank_at: float = float(hud.side_panel.position.x) * ppp
			var dock = hud.dock
			var skills_at: float = (vp.x - (dock.position.x + dock.size.x + dock.housing_margin().z)) * ppp
			var zl: Dictionary = Hud43.zones(vp)
			var cut_left: bool = int(rot) == 90
			var line := "SAFE %-52s rot %3d  vp %dx%d pt  reported L %4.0f R %4.0f  used L %4.1f R %4.1f  margins L %4.1f R %4.1f  tank@ %5.1f  skills@ %5.1f  ai_l %5.1f  ai_r %5.1f" % [
					str(d[0]), rot, int(w), int(h), rep.x, rep.y, used.x * ppp, used.z * ppp, float(m.margins.x) * ppp, float(m.margins.z) * ppp,
					tank_at, skills_at, (zl["ai_l"] as Rect2).position.x * ppp, vp.x * ppp - (zl["ai_r"] as Rect2).end.x * ppp]
			print(line)
			var bad := []
			if tank_at < used.x * ppp - 0.5:
				bad.append("tank inside the left inset")
			if skills_at < used.z * ppp - 0.5:
				bad.append("skills inside the right inset")
			if str(d[4]) != "none":
				if cut_left and skills_at > HUG_PT:
					bad.append("right side (no cut-out) not hugging: %.1f pt" % skills_at)
				if not cut_left and tank_at > HUG_PT:
					bad.append("left side (no cut-out) not hugging: %.1f pt" % tank_at)
				if cut_left and absf(used.x * ppp - rep.x) > 0.5:
					bad.append("cut-out side inset changed")
				if not cut_left and absf(used.z * ppp - maxf(rep.x, rep.y)) > 0.5:
					bad.append("cut-out side inset changed")
			for b in bad:
				print("FAIL  %s rot %d: %s" % [d[0], rot, b])
			fails += bad.size()
	print("safe_area_probe: ", "PASS" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
