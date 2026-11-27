extends SceneTree
## OOZE 3.0 SCREEN CENTRE probe (Daniele 2026-11-27 "Centre on screen"). Headless, one phone + rotation per run:
##   Godot --headless --path . --script res://tests/centre_probe.gd -- --pt-height=390 pw=844 notch=47 orient=90 [map=Y-05]
## The window is (pw x pt-height) pt at 2 px per pt, the notch inset on the cut-out side only (iOS symmetric insets + the screen
## angle, UiKit.resolve_sides). Prints, in pt from the screen centre (0 = centred):
##   SCORE   the score capsule's centre x (the live control and Hud43.zones' rect)
##   AI      the left AI screen's left edge to the screen left vs the right one's right edge to the screen right (mirror gap)
##   CAMERA  the map frame centre (layout 0, 0) projected at the start view
##   LAKE    the painted lake's centre (PitBackdrop) when it is on
##   COLUMNS the send column's left and the skill column's right, pt from their screen edge (they hug the safe area, not centred)
##   CHECK <PASS|FAIL>   score + AI mirror + camera within 1 pt of the screen centre
## Exit 1 on FAIL.
const TOL := 1.0


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
	var pw := float(_arg("pw", "844"))
	var ph := UiKit.test_pt_h if UiKit.test_pt_h > 0.0 else 390.0
	root.size = Vector2i(int(pw * 2.0), int(ph * 2.0))
	await _frames(3)
	var notch := float(_arg("notch", "47"))
	var vp0 := root.get_visible_rect().size
	UiKit.test_insets = Vector4(notch / UiKit.pt_per_px(vp0), 0.0, notch / UiKit.pt_per_px(vp0), 0.0)
	UiKit.test_orient = int(_arg("orient", "90"))
	var code := _arg("map", "Y-05")
	var path := ""
	for p in MapPool.all():
		if p.get_file().begins_with(code):
			path = p
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1", "map": path}
	change_scene_to_file("res://main.tscn")
	await _frames(60)
	var m: Node = current_scene
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var ppt := UiKit.pt_per_px(vp)
	var cx := vp.x / 2.0
	var ins := UiKit.safe_insets(vp)
	var z := Hud43.zones(vp)
	var hud = m.hud
	var sc: Rect2 = z["score"]
	var live := sc
	if hud.score43 is Control:
		live = (hud.score43 as Control).get_global_rect()
	var ai_l: Rect2 = z["ai_l"]
	var ai_r: Rect2 = z["ai_r"]
	var ai_live_l := ai_l
	var ai_live_r := ai_r
	if hud.ai_screens != null and (hud.ai_screens.rects as Array).size() == 2:   # the rects the live AI screens were laid in
		var rr: Array = hud.ai_screens.rects
		ai_live_l = rr[0]
		ai_live_r = rr[1]
	var cam_x: float = (m.cam as Camera3D).unproject_position(Vector3.ZERO).x
	var d_score := (live.get_center().x - cx) * ppt
	var d_zone := (sc.get_center().x - cx) * ppt
	var gap_l := ai_live_l.position.x * ppt
	var gap_r := (vp.x - ai_live_r.end.x) * ppt
	var d_cam := (cam_x - cx) * ppt
	print("PHONE %.0f x %.0f pt notch %.0f orient %d insets L %.1f R %.1f pt map %s board3 %s" % [pw, ph, notch, UiKit.test_orient,
			ins.x * ppt, ins.z * ppt, code, m.board3_cam()])
	print("SCORE centre %+.2f pt (zone %+.2f) width %.1f pt" % [d_score, d_zone, live.size.x * ppt])
	print("AI left edge %.2f pt from screen left, right edge %.2f pt from screen right (mirror %+.2f)" % [gap_l, gap_r, gap_l - gap_r])
	print("CAMERA frame centre %+.2f pt" % d_cam)
	if m.scenery and m.scenery.pit:
		var pit = m.scenery.pit
		var st: Array = pit._stadium()
		var lake_x: float = pit._o.x + (st[0] as Vector2).x * pit._s.x
		print("LAKE centre %+.2f pt" % ((lake_x - cx) * ppt))
	else:
		print("LAKE off")
	var send_l: float = z["send"].position.x * ppt
	var skill_r: float = (vp.x - (z["skill"] as Rect2).end.x) * ppt
	print("COLUMNS send left %.1f pt from screen left, skills right %.1f pt from screen right" % [send_l, skill_r])
	var pr: Rect2 = m.pit_rect()
	print("PIT %.1f .. %.1f pt (centre %+.2f pt)" % [pr.position.x * ppt, pr.end.x * ppt, (pr.get_center().x - cx) * ppt])
	var ok := absf(d_score) <= TOL and absf(d_zone) <= TOL and absf(gap_l - gap_r) <= TOL and absf(d_cam) <= TOL
	print("CHECK %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
