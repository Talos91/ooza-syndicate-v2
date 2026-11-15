extends Node
## Map-size probe (map-size study 2026-11-15; a dev tool, not a suite). Run WITHOUT --headless, as a scene:
##   Godot_console --path . --audio-driver Dummy --position -6000,-6000 res://tests/map_size_probe.tscn -- profile=zfold7-cover,phone-wide
## 1. CRESCENT (R-10) at Daniele's last-stand moment (staging 0.24.4 shot: nodes 0,1,2,3,9,10,14 dropped): the survivor
##    view's platform diameter in pt (P_LS) and its camera distance.
## 2. Every map in MapPool.PROTO: the start view's platform pt today, and the node-spacing scale s (positions scaled about
##    the centre; platforms keep Rules.R) whose fitted start view (x MapCamera.zoom_for) shows platforms at P_LS.
## Lines: "SIZE <profile> <code> ..." Desktop emulation only.

const MAIN := "res://main.tscn"
const PROFILES := {"phone": Vector2i(812, 375), "phone-wide": Vector2i(844, 390), "zfold7-cover": Vector2i(840, 360)}
const LS_DROPPED := [0, 1, 2, 3, 9, 10, 14]


func _ready() -> void:
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _plat_pt(main: Node, pt_w: float) -> float:
	## Platform diameter (screen-horizontal axis) in pt at the view's aim point.
	var cam: Camera3D = main.cam
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var p: Vector3 = main.cam_target
	var a := cam.unproject_position(p - right * Rules.R)
	var b := cam.unproject_position(p + right * Rules.R)
	return (b - a).length() * pt_w / vp.x


func _start(path: String) -> Node:
	var m := MapBuilder.load_map(path)
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": m["modes"][0], "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.mobile = true
	get_tree().root.add_child(inst)
	for f in range(8):
		await get_tree().process_frame
	return inst


func _view_at_scale(main: Node, s: float, zoom: float, axis := "xz") -> void:
	var sim = main.sim
	var c := Vector3.ZERO
	var keep := []
	for n in sim.nodes:
		keep.append(n["pos"])
		c += n["pos"]
	c /= float(sim.nodes.size())
	for n in sim.nodes:
		var v: Vector3 = (n["pos"] as Vector3) - c
		n["pos"] = c + Vector3(v.x * (s if "x" in axis else 1.0), v.y, v.z * (s if "z" in axis else 1.0))
	var fit: Array = main._fit_nodes(sim.nodes)
	main.cam_target = fit[0]
	main.cam_dist = float(fit[1]) * zoom
	main._place_camera()
	for i in range(sim.nodes.size()):
		sim.nodes[i]["pos"] = keep[i]


func _run() -> void:
	var out := PackedStringArray()
	for name in _arg("profile", "zfold7-cover").split(","):
		var wh: Vector2i = PROFILES[name]
		get_window().size = wh
		UiKit.test_pt_h = float(wh.y)
		for f in range(6):
			await get_tree().process_frame
		var pt_w := float(wh.x)
		# 1. CRESCENT at the last stand
		var r10: Node = await _start("res://maps4/R-10-crescent.json")
		var p_start := _plat_pt(r10, pt_w)
		var d_start: float = r10.cam_dist
		for id in LS_DROPPED:
			r10.sim.collapsed[id] = true
		var fit: Array = r10._survivor_fit()
		r10.cam_target = fit[0]
		r10.cam_dist = fit[1]
		r10.cam_pitch = fit[2]
		r10._place_camera()
		var p_ls := _plat_pt(r10, pt_w)
		var line := "SIZE %s R-10 LASTSTAND start plat %.1f pt dist %.1f pitch %.0f | last stand plat %.1f pt dist %.1f pitch %.1f | zoom-in x%.2f" % [
				name, p_start, d_start, r10._base_pitch, p_ls, fit[1], fit[2], d_start / float(fit[1])]
		print(line)
		out.append(line)
		await get_tree().create_timer(0.3).timeout
		r10.queue_free()
		for f in range(3):
			await get_tree().process_frame
		# 2. every proto map
		for code in (Array(_arg("maps", "").split(",")) if _arg("maps", "") != "" else MapPool.PROTO):   # maps=<codes> (map-shrink: the pool)
			var path := ""
			for p in MapPool.all():
				if p.get_file().substr(0, 4) == code:
					path = p
			if path == "":
				continue
			var inst: Node = await _start(path)
			var z := MapCamera.zoom_for(code)
			var p0 := _plat_pt(inst, pt_w)
			var d0: float = inst.cam_dist
			var res := {}
			for axis in ["xz", "x", "z"]:
				var lo := 0.25
				var hi := 1.0
				for it in range(18):
					var mid := (lo + hi) / 2.0
					_view_at_scale(inst, mid, z, axis)
					if _plat_pt(inst, pt_w) < p_ls:
						hi = mid
					else:
						lo = mid
				res[axis] = (lo + hi) / 2.0
			_view_at_scale(inst, res["xz"], z)
			var p1 := _plat_pt(inst, pt_w)
			var est := float(_arg("est_" + code, "0"))     # an estimated uniform scale (deck-tier option) to read back
			var pe := 0.0
			if est > 0.0:
				_view_at_scale(inst, est, z)
				pe = _plat_pt(inst, pt_w)
			line = "SIZE %s %s start plat %.1f pt dist %.1f pitch %.0f zoom %.2f | scale %.3f -> plat %.1f pt dist %.1f | x-only %s z-only %s | est %.3f -> %.1f pt" % [
					name, code, p0, d0, inst.cam_pitch, z, res["xz"], p1, inst.cam_dist,
					("%.3f" % res["x"]) if res["x"] > 0.26 else "never", ("%.3f" % res["z"]) if res["z"] > 0.26 else "never", est, pe]
			print(line)
			out.append(line)
			inst.queue_free()
			for f in range(3):
				await get_tree().process_frame
	var f := FileAccess.open(_arg("out", "user://map_size.txt"), FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	print("MAPSIZE DONE")
	get_tree().quit()
