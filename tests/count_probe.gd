extends SceneTree
## COUNT PROBE (Ooze 3.0 WP4): the count screens' digit height on screen, in pt, at every OPTIONS count size, on every Z map, at
## the Board3 start camera. Headless, geometry only (render-free):
##   Godot --headless --path . --script res://tests/count_probe.gd -- --pt-height=375 pw=812 notch=44 [maps=Z-01,Z-05]
## Prints one line per map and size: COUNT <map> x<k> min <pt> max <pt> (nodes <n>) badges_shown <n> cam <dist> pitch <deg>, then
## COUNT_SUMMARY x<k> min <pt> over every map. Exit 1 when the default size (x1.0) has a digit under FLOOR_PT on any node, when
## a badge still shows a count, or when a map is not at the Board3 camera.
const FLOOR_PT := 12.5


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
	var pw := float(_arg("pw", "812"))
	var ph := UiKit.test_pt_h if UiKit.test_pt_h > 0.0 else 375.0
	root.size = Vector2i(int(pw * 2.0), int(ph * 2.0))
	await _frames(3)
	var notch := float(_arg("notch", "0"))
	var vp0 := root.get_visible_rect().size
	UiKit.test_insets = Vector4(notch / UiKit.pt_per_px(vp0), 0.0, notch / UiKit.pt_per_px(vp0), 0.0)
	var codes: Array = Array(_arg("maps", ",".join(MapPool.POOL3)).split(","))
	var fails := 0
	var worst := {}
	for code in codes:
		var path := ""
		for f in DirAccess.get_files_at("res://maps4/"):
			if f.begins_with(str(code) + "-") and f.ends_with(".json"):
				path = "res://maps4/" + f
		if path == "":
			print("COUNT %s: no map file" % code)
			fails += 1
			continue
		for k in range(Rules.COUNT_SIZES.size()):
			Rules._count_size = k
			load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1", "map": path}
			change_scene_to_file("res://main.tscn")
			await _frames(60)
			var m: Node = current_scene
			var vc = m.get("vat_count")
			if vc == null:
				print("COUNT %s x%s: no vat_count" % [code, Rules.COUNT_SIZES[k]])
				fails += 1
				continue
			var lo := INF
			var hi := 0.0
			for id in vc.screens:
				var p: float = vc.digit_pt_at(id, m.cam)
				lo = minf(lo, p)
				hi = maxf(hi, p)
			var shown := 0
			for id in m.hud.badges:
				if (m.hud.badges[id]["panel"] as Control).visible:
					shown += 1
			var at_board := bool(m.call("board3_cam")) and is_equal_approx(float(m.cam_pitch), Board3.CAM_PITCH) \
					and absf(float(m.cam_dist) - Board3.CAM_DIST) < 0.01
			print("COUNT %s x%s digit %.2f m  min %.1f pt  max %.1f pt  (nodes %d)  badges_shown %d  view %s pt  cam %.1f m pitch %.0f board3 %s" % [
					code, str(Rules.COUNT_SIZES[k]), vc.digit_height_m(), lo, hi, vc.screens.size(), shown,
					str(vp0 * UiKit.pt_per_px(vp0)), float(m.cam_dist), float(m.cam_pitch), at_board])
			worst[k] = minf(float(worst.get(k, INF)), lo)
			if shown > 0 or not at_board:
				fails += 1
			if k == Rules.COUNT_SIZE_DEFAULT and lo < FLOOR_PT:
				print("FAIL  %s: default count digits %.1f pt < %.1f pt" % [code, lo, FLOOR_PT])
				fails += 1
	for k in worst:
		print("COUNT_SUMMARY x%s min %.1f pt" % [str(Rules.COUNT_SIZES[k]), float(worst[k])])
	Rules._count_size = -1
	print("count_probe: ", "PASS" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
