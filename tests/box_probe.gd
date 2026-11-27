extends SceneTree
## OOZE 3.0 ZOOM BOX probe (WP2; was tests/lab_box_probe.gd). Headless, one phone per run:
##   Godot --headless --path . --script res://tests/box_probe.gd -- --pt-height=390 pw=844 notch=47 [r=7.6] [map=Z-01]
##   Godot --headless --path . --script res://tests/box_probe.gd -- --pt-height=375 pw=812 notch=44
##   ... orient=90 | 270: the notch inset on that side only (the game's per-side safe area); the half-widths are the nearer column's
## The window is (pw x pt-height) pt at 2 px per pt. At Board3's camera (CAM_DIST, CAM_PITCH) it measures the ground a platform
## RIM (radius r + 0.14, r = Rules.R unless given) may reach and still show inside main.pit_rect(); the far edge also keeps a
## Board3.TOWER m tower on that platform in view. Prints:
##   PIT <rect pt>
##   BOX dist <m> pitch <p> aim_z <m> far_z <m> near_z <m> far_half_w <m> near_half_w <m> (rect <w> x <d> m; far edge by tower|ground)
##   PLAT r <m> <pt> pt             the platform's diameter on screen at the aim point
##   DIGIT x<k> <pt> pt             the count digit's height (VatCount.DIGIT_H x k, at the capital) at the aim point, each count size
##   LOCKED <code> rims_in_pit <bool> worst <m>   each MapPool.POOL3 map at Board3's camera (rims at Board3.BOX_RIM, tower tops)
##   SHOT <dir>/<code>.png               with shots=<dir> on a WINDOWED off-screen run: each pooled map's start view
##   CHECK box >= Board3: <PASS|FAIL> ...      the measured box (from Board3.CAM_AIM_Z) must hold Board3's constants
## Exit 1 when the measured box is smaller than the constants (camera, HUD bands or pit rect changed without a re-measure) or a
## pooled map's rims leave the pit; 0 otherwise.
const TOL := 0.05           # m: rounding allowance on the constants
const COUNT_SIZES := [0.7, 0.85, 1.0, 1.15, 1.3]   # plan 2.2 (Rules.COUNT_SIZES once WP1 lands it)
const CAPITAL_Y := 4.6      # m: the vat capital's height (VatCount.FALLBACK_Y), where the digits stand


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


func _path(code: String) -> String:
	for p in MapPool.all():
		if p.get_file().begins_with(code):
			return p
	return ""


func _start(path: String) -> Node:
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1", "map": path}
	change_scene_to_file("res://main.tscn")
	await _frames(60)
	return current_scene


func _aim(m: Node, dist: float, pitch: float, target: Vector3) -> void:
	m.cam_yaw = 0.0
	m.cam_pitch = pitch
	m.cam_target = target
	m.cam_dist = dist
	m._place_camera()


func _pt(m: Node, a: Vector3, b: Vector3) -> float:
	var cam: Camera3D = m.cam
	return (cam.unproject_position(a) - cam.unproject_position(b)).length() * UiKit.pt_per_px(m.get_viewport().get_visible_rect().size)


func _row_z(m: Node, y_screen: float, height: float) -> float:
	## The ground z whose point at `height` m above it projects to screen row y_screen (screen centre column).
	var lo: float = m.cam_target.z - 300.0
	var hi: float = (m.cam as Camera3D).global_position.z - 1.0
	for i in range(60):
		var mid := (lo + hi) / 2.0
		var sy: float = (m.cam as Camera3D).unproject_position(Vector3(m.cam_target.x, height, mid)).y
		if sy < y_screen:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


func _run() -> void:
	var pw := float(_arg("pw", "844"))
	var ph := UiKit.test_pt_h if UiKit.test_pt_h > 0.0 else 390.0
	root.size = Vector2i(int(pw * 2.0), int(ph * 2.0))
	await _frames(3)
	var notch := float(_arg("notch", "0"))
	var vp0 := root.get_visible_rect().size
	UiKit.test_insets = Vector4(notch / UiKit.pt_per_px(vp0), 0.0, notch / UiKit.pt_per_px(vp0), 0.0)
	UiKit.test_orient = int(_arg("orient", "-1"))     # 90 | 270: the iOS cut-out on one side only (UiKit.resolve_sides), the
	                                                   # screen-centred camera against the off-centre pit; -1 = both sides
	var r := float(_arg("r", str(Rules.R)))
	var rim := r + 0.14
	var code := _arg("map", "")
	if code == "":
		code = MapPool.POOL3[0] if not MapPool.POOL3.is_empty() and _path(MapPool.POOL3[0]) != "" else "L09P"
	var dist: float = Board3.CAM_DIST
	var pitch: float = Board3.CAM_PITCH
	var m := await _start(_path(code))
	_aim(m, dist, pitch, Vector3.ZERO)
	var pit: Rect2 = m.pit_rect()
	var ppt := UiKit.pt_per_px(m.get_viewport().get_visible_rect().size)
	var far_ground := _row_z(m, pit.position.y, 0.0)
	var far_tower := _row_z(m, pit.position.y, Board3.TOWER) - rim   # a rim this far keeps its own tower top in the pit
	var far_z := maxf(far_ground, far_tower)
	var near_z := _row_z(m, pit.end.y, 0.0)
	var aim_z := -(far_z + near_z) / 2.0
	# the box as seen from the phone's own centring aim (what the BOX line reports) ...
	var box: Array = _box(m, dist, pitch, aim_z, pit, rim)
	print("PIT %s pt (%.0f x %.0f pt screen, notch %.0f, orient %d)" % [str(Rect2(pit.position * ppt, pit.size * ppt)), pw, ph, notch, UiKit.test_orient])
	print("BOX dist %.2f pitch %.0f aim_z %.2f far_z %.2f near_z %.2f far_half_w %.2f near_half_w %.2f (rect %.1f x %.1f m; far edge by %s; rim %.2f)" % [
			dist, pitch, aim_z, box[0], box[1], box[2], box[3], 2.0 * minf(box[2], box[3]), box[1] - box[0],
			"tower" if far_tower > far_ground else "ground", rim])
	# ... and from Board3's shared aim, which is what the game uses and what the constants must fit in
	var own: Array = _box(m, dist, pitch, Board3.CAM_AIM_Z, pit, rim)
	_aim(m, dist, pitch, Vector3(0, 0, Board3.CAM_AIM_Z))
	var aim := Vector3(0, 0, 0)
	print("PLAT r %.2f %.1f pt" % [r, _pt(m, aim + Vector3(-r, 0, 0), aim + Vector3(r, 0, 0))])
	for k in COUNT_SIZES:
		var h: float = 1.15 * k                                # VatCount.DIGIT_H (1.15 m at x1.0) x the count size
		var up: Vector3 = (m.cam as Camera3D).global_transform.basis.y   # the count screen faces the eye (vat_count.gd)
		print("DIGIT x%.2f %.1f pt" % [k, _pt(m, aim + Vector3(0, CAPITAL_Y, 0), aim + Vector3(0, CAPITAL_Y, 0) + up * h)])
	var ok: bool = own[0] <= Board3.BOX_FAR_Z + TOL and own[1] >= Board3.BOX_NEAR_Z - TOL \
			and own[2] >= Board3.BOX_FAR_HALF_W - TOL and own[3] >= Board3.BOX_NEAR_HALF_W - TOL and absf(rim - Board3.BOX_RIM) < 0.01
	print("CHECK box >= Board3 (%s): %s  measured from aim %.2f: far_z %.2f near_z %.2f far_half_w %.2f near_half_w %.2f rim %.2f vs %.2f / %.2f / %.2f / %.2f rim %.2f" % [
			Board3.BOX_ID, "PASS" if ok else "FAIL", Board3.CAM_AIM_Z, own[0], own[1], own[2], own[3], rim,
			Board3.BOX_FAR_Z, Board3.BOX_NEAR_Z, Board3.BOX_FAR_HALF_W, Board3.BOX_NEAR_HALF_W, Board3.BOX_RIM])
	var maps_ok := true
	for c in MapPool.POOL3:
		var p := _path(c)
		if p == "":
			print("LOCKED %s not baked" % c)
			maps_ok = false
			continue
		var lm := await _start(p)
		_aim(lm, dist, pitch, Vector3(0, 0, Board3.CAM_AIM_Z))
		var lpit: Rect2 = lm.pit_rect()
		var inside := true
		var worst := INF
		var edge_pt := INF                            # the closest rim / tower top to a pit edge on screen, pt (< 0: outside)
		var lppt := UiKit.pt_per_px(lm.get_viewport().get_visible_rect().size)
		for n in lm.sim.nodes:
			var pos: Vector3 = n["pos"]
			worst = minf(worst, Board3.rim_margin(pos.x, pos.z))
			var probe := [pos + Vector3(0, Board3.TOWER, 0)]
			for k in range(24):
				var a := TAU * k / 24.0
				probe.append(pos + Vector3(cos(a), 0, sin(a)) * Board3.BOX_RIM)
			for q in probe:
				var sp: Vector2 = (lm.cam as Camera3D).unproject_position(q)
				inside = inside and lpit.grow(0.5).has_point(sp)
				edge_pt = minf(edge_pt, minf(minf(sp.x - lpit.position.x, lpit.end.x - sp.x), minf(sp.y - lpit.position.y, lpit.end.y - sp.y)) * lppt)
		maps_ok = maps_ok and inside
		print("LOCKED %s rims_in_pit %s worst %.2f m (box margin) edge %.1f pt" % [c, inside, worst, edge_pt])
		if _arg("shots", "") != "":                   # windowed run only (off-screen): the start view at Board3's camera
			await _frames(30)
			var img := lm.get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [_arg("shots", ""), c])
			print("SHOT %s/%s.png %dx%d" % [_arg("shots", ""), c, img.get_width(), img.get_height()])
	print("PROBE DONE %s" % ("PASS" if ok and maps_ok else "FAIL"))
	quit(0 if ok and maps_ok else 1)


func _box(m: Node, dist: float, pitch: float, aim_z: float, pit: Rect2, rim: float) -> Array:
	## [far_z, near_z, far_half_w, near_half_w] in metres from the frame centre, with the camera aimed at (0, 0, aim_z).
	_aim(m, dist, pitch, Vector3(0, 0, aim_z))
	var fg := _row_z(m, pit.position.y, 0.0)
	var ft := _row_z(m, pit.position.y, Board3.TOWER) - rim
	var far_z := maxf(fg, ft)
	var near_z := _row_z(m, pit.end.y, 0.0)
	var halfw := []
	for z in [far_z, near_z]:
		var y: float = (m.cam as Camera3D).unproject_position(Vector3(0, 0, z)).y
		var g: Vector3 = m._ground(Vector2(pit.end.x, y))
		var gl: Vector3 = m._ground(Vector2(pit.position.x, y))   # the camera is screen-centred: with one-side insets the pit
		halfw.append(minf(g.x, -gl.x))                            # is not, the nearer column sets the half-width
	return [far_z, near_z, halfw[0], halfw[1]]
