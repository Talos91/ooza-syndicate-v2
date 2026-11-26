extends SceneTree
## LAB ZOOM BOX probe (lab4 job 1; 05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md, Daniele's phone test of lab3 points 1 and 4).
## A dev tool, not a suite. Headless, through the lab guard:
##   Godot --headless --path . --script res://tests/lab_box_probe.gd -- --pt-height=390 pw=844 notch=47 [ref=1]
##   (and --pt-height=375 pw=812 notch=44: the GMN reference phone)
## The window is (pw x pt-height) pt at 2 px per pt. Prints:
##   G <code> pitch <p> dist <m> plat <pt>       pool G's start view today (whole-map fit x MapCamera.zoom_for), ref=1 only
##   LABFIT <code> dist <m> plat <pt>            the lab maps' own fit (what lab3 showed), ref=1 only
##   TARGET median G plat <pt> x <gain> = <pt> -> dist <m> at pitch <p>   ref=1 only
##   BOX dist <m> pitch <p> aim_z <m> far_z <m> near_z <m> far_half_w <m> near_half_w <m> (rect <w> x <d> m)
##       at Rules.LAB_CAM_DIST / LAB_CAM_PITCH: the ground a platform RIM may reach (relative to the map centre, +z = towards the
##       viewer, the screen's bottom) so it shows inside main.pit_rect(); the far edge also keeps a 7.5 m tower on that platform in.
##   LOCKED <code> dist <m> pitch <p> plat <pt> rims_in_pit <bool>   each lab map with the lock on (the real start view)
const LabCards := preload("res://scripts/lab_cards.gd")
const GAIN := 1.18          # MAP-PLANNING-NUMBERS 2026-11-22: halving the bridges gains a median x1.18 zoom over pool G
const TOWER := 7.5          # the tallest tower (main._fit_nodes)


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


func _start(path: String) -> Node:
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1", "map": path}
	change_scene_to_file("res://main.tscn")
	await _frames(60)
	return current_scene


func _plat_pt(m: Node) -> float:
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var cam: Camera3D = m.cam
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var p: Vector3 = m.cam_target
	return (cam.unproject_position(p + right * Rules.R) - cam.unproject_position(p - right * Rules.R)).length() * UiKit.pt_per_px(vp)


func _aim(m: Node, dist: float, pitch: float, target: Vector3) -> void:
	m.cam_yaw = 0.0
	m.cam_pitch = pitch
	m.cam_target = target
	m.cam_dist = dist
	m._place_camera()


func _row_z(m: Node, y_screen: float, height: float) -> float:
	## The ground z whose point at `height` m above it projects to screen row y_screen (screen centre column).
	var lo: float = m.cam_target.z - 300.0           # beyond the far edge (the top ray meets the ground at pitch > fov / 2)
	var hi: float = (m.cam as Camera3D).global_position.z - 1.0   # in front of the camera
	for i in range(60):                               # screen y grows with z (towards the viewer)
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
	var notch := float(_arg("notch", "0"))            # the side safe areas in pt (a notched phone in landscape)
	var vp0 := root.get_visible_rect().size
	UiKit.test_insets = Vector4(notch / UiKit.pt_per_px(vp0), 0.0, notch / UiKit.pt_per_px(vp0), 0.0)
	var ref := _arg("ref", "0") == "1"
	var lab_path := LabCards.map_path("L09P")
	var dist: float = Rules.LAB_CAM_DIST
	var pitch: float = Rules.LAB_CAM_PITCH
	if ref:
		Rules.lab_opts["cam_lock"] = false            # today's fit, as lab3 and pool G show it
		var plats := []
		for i in range(1, 20):
			var code := "G-%02d" % i
			var path := LabCards.map_path(code)
			if path == "":
				continue
			var m := await _start(path)
			var pt := _plat_pt(m)
			plats.append(pt)
			print("G %s pitch %.0f dist %.1f plat %.1f" % [code, m.cam_pitch, m.cam_dist, pt])
		for code in MapPool.LAB:
			var m := await _start(LabCards.map_path(code))
			print("LABFIT %s pitch %.0f dist %.1f plat %.1f" % [code, m.cam_pitch, m.cam_dist, _plat_pt(m)])
		plats.sort()
		var med: float = plats[plats.size() / 2] if plats.size() % 2 == 1 else (plats[plats.size() / 2 - 1] + plats[plats.size() / 2]) / 2.0
		var want := med * GAIN
		var m := await _start(lab_path)
		var lo := 20.0
		var hi := 300.0
		for i in range(60):                           # platform pt falls as the camera backs off
			dist = (lo + hi) / 2.0
			_aim(m, dist, pitch, Vector3.ZERO)
			if _plat_pt(m) > want:
				lo = dist
			else:
				hi = dist
		print("TARGET median G plat %.1f (of %d) x %.2f = %.1f pt -> dist %.2f at pitch %.0f" % [med, plats.size(), GAIN, want, dist, pitch])
		Rules.lab_opts["cam_lock"] = true
	var m := await _start(lab_path)
	_aim(m, dist, pitch, Vector3.ZERO)
	var pit: Rect2 = m.pit_rect()
	var ppt := UiKit.pt_per_px(m.get_viewport().get_visible_rect().size)
	var far_ground := _row_z(m, pit.position.y, 0.0)
	var far_tower := _row_z(m, pit.position.y, TOWER) - Look.RIM_OUT   # a rim this far keeps its own tower top in the pit
	var far_z := maxf(far_ground, far_tower)
	var near_z := _row_z(m, pit.end.y, 0.0)
	var aim_z := -(far_z + near_z) / 2.0              # aim so the box is centred on the map centre
	_aim(m, dist, pitch, Vector3(0, 0, aim_z))
	far_z += aim_z
	near_z += aim_z
	var halfw := []
	for z in [far_z, near_z]:
		var y: float = (m.cam as Camera3D).unproject_position(Vector3(0, 0, z)).y
		var g: Vector3 = m._ground(Vector2(pit.end.x, y))
		halfw.append(g.x)
	print("PIT %s pt (%.0f x %.0f pt screen)" % [str(Rect2(pit.position * ppt, pit.size * ppt)), pw, ph])
	print("BOX dist %.2f pitch %.0f aim_z %.2f far_z %.2f near_z %.2f far_half_w %.2f near_half_w %.2f (rect %.1f x %.1f m; far edge by %s)" % [
			dist, pitch, aim_z, far_z, near_z, halfw[0], halfw[1],
			2.0 * minf(halfw[0], halfw[1]), near_z - far_z, "tower" if far_tower > far_ground else "ground"])
	if not ref:
		for code in MapPool.LAB:
			var lm := await _start(LabCards.map_path(code))
			var lpit: Rect2 = lm.pit_rect()
			var inside := true
			for n in lm.sim.nodes:
				for k in range(24):
					var a := TAU * k / 24.0
					var q := (lm.cam as Camera3D).unproject_position(n["pos"] + Vector3(cos(a), 0, sin(a)) * Look.RIM_OUT)
					inside = inside and lpit.grow(0.5).has_point(q)
				inside = inside and lpit.grow(0.5).has_point((lm.cam as Camera3D).unproject_position(n["pos"] + Vector3(0, TOWER, 0)))
			print("LOCKED %s dist %.2f pitch %.0f yaw %.2f plat %.1f rims_in_pit %s" % [code, lm.cam_dist, lm.cam_pitch, lm.cam_yaw, _plat_pt(lm), inside])
	print("PROBE DONE")
	quit(0)
