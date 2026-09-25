extends Node
## Phone-fit probe (Alpha 18; a dev tool, not part of the suites): run it WITHOUT --headless, as a scene so
## the Net autoload exists:
##   Godot_v4.6.1-stable_win64_console.exe --path . --resolution 1266x585 res://tests/phone_fit.tscn -- out=<file>
##   (pitches=auto measures each map at its own MapCamera pitch; pitches=50,54,.. sweeps them)
## For every pooled map and every candidate camera pitch it
## starts the real game on the phone HUD profile, lets the camera fit and the badges lay out, and
## measures what a player gets on a landscape phone:
##   tap   - smallest node tap target in points: min(tap circle's short axis, distance to the nearest
##           other node) on an 844 x 390 pt screen (iPhone 13/14 class) - Apple's minimum is 44 pt
##   off   - platforms (rim) outside the screen, under   hud - platforms under the HUD panels
##   bover - badges outside the screen or under the HUD, bhit - badge/badge overlaps,
##   bplat - badges covering another node's platform
## Output: one line per (map, pitch) and a CHOICE line per map (the sweep behind scripts/map_camera.gd).
## Args (after --): out=<file> pitches=auto|50,54,.. maps=C-05,S-19 (optional filter) pt=844

const MAIN := "res://main.tscn"

var out_lines: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _ground_axes(cam: Camera3D) -> Array:
	var right := cam.global_transform.basis.x
	right.y = 0.0
	var fwd := right.cross(Vector3.UP)
	return [right.normalized(), fwd.normalized()]


func _circle_screen(cam: Camera3D, p: Vector3, r: float) -> Dictionary:
	## Projected ground circle: centre, half axes (px) and bounding rect.
	var ax := _ground_axes(cam)
	var c := cam.unproject_position(p)
	var pts := []
	for k in range(16):
		var a := TAU * k / 16.0
		pts.append(cam.unproject_position(p + (ax[0] * cos(a) + ax[1] * sin(a)) * r))
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	var hx := (cam.unproject_position(p + ax[0] * r) - c).length()
	var hy := (cam.unproject_position(p + ax[1] * r) - c).length()
	return {"c": c, "hx": hx, "hy": hy, "box": box}


func _rect_hits_circle(rect: Rect2, circ: Dictionary, shrink: float = 0.85) -> bool:
	## Badge rect against a projected platform ellipse (shrunk a little: touching the rim is fine).
	var c: Vector2 = circ["c"]
	var hx: float = circ["hx"] * shrink
	var hy: float = circ["hy"] * shrink
	var q := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	var d := q - c
	return pow(d.x / maxf(hx, 0.01), 2) + pow(d.y / maxf(hy, 0.01), 2) < 1.0


func _measure(main: Node, pt_w: float) -> Dictionary:
	var cam: Camera3D = main.cam
	var hud = main.hud
	var sim = main.sim
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var ppt := pt_w / vp.x                                   # points per logical pixel
	var tap_r := Rules.R + 2.5                                # main.gd mobile tap radius on the ground
	var panels := []
	panels.append(hud.side_panel.get_global_rect())
	panels.append(Rect2(0, 0, vp.x, hud.top_used()))
	panels.append(Rect2(0, vp.y - hud.bottom_used(), vp.x, hud.bottom_used()))
	panels.append(hud.pause_button.get_global_rect())
	var screen := Rect2(Vector2.ZERO, vp)
	var circ := {}
	var off := 0
	var under := 0
	for n in sim.nodes:
		var c := _circle_screen(cam, n["pos"], Rules.R)
		circ[n["id"]] = c
		var box: Rect2 = c["box"]
		if not screen.encloses(box):
			off += 1
		else:
			for pr in panels:
				if (pr as Rect2).grow(-2.0).intersects(box):
					under += 1
					break
	var tap := INF
	var worst := -1
	for n in sim.nodes:
		var t := _circle_screen(cam, n["pos"], tap_r)
		var size: float = 2.0 * minf(t["hx"], t["hy"])
		var c0: Vector2 = t["c"]
		for m in sim.nodes:
			if m["id"] != n["id"]:
				size = minf(size, c0.distance_to(circ[m["id"]]["c"]))
		if size < tap:
			tap = size
			worst = n["id"]
	var bover := 0
	var bhit := 0
	var bplat := 0
	var rects := {}
	for id in hud.badges:
		var panel: Control = hud.badges[id]["panel"]
		if not panel.visible:
			continue
		rects[id] = panel.get_global_rect()
	var ids := rects.keys()
	for i in range(ids.size()):
		var r: Rect2 = rects[ids[i]]
		if not screen.encloses(r):
			bover += 1
		else:
			for pr in panels:
				if (pr as Rect2).intersects(r):
					bover += 1
					break
		for j in range(i + 1, ids.size()):
			if r.grow(-1.0).intersects(rects[ids[j]]):
				bhit += 1
		for n in sim.nodes:
			if n["id"] != ids[i] and _rect_hits_circle(r, circ[n["id"]]):
				bplat += 1
	return {"tap": tap * ppt, "worst": worst, "off": off, "hud": under, "bover": bover, "bhit": bhit, "bplat": bplat,
			"plat": 2.0 * minf(circ[worst]["hx"], circ[worst]["hy"]) * ppt if worst >= 0 else 0.0}


func _run() -> void:
	var out_path := _arg("out", "user://phonefit.txt")
	var pitches := []
	var auto := _arg("pitches", "auto") == "auto"
	if auto:
		pitches = [-1.0]                                   # the game's own pitch (MapCamera)
	else:
		for s in _arg("pitches", "").split(","):
			pitches.append(float(s))
	var only := _arg("maps", "")
	var pt_w := float(_arg("pt", "844"))
	var main_script = load("res://scripts/main.gd")
	for path in MapPool.all():
		var code: String = path.get_file().substr(0, 4)
		if only != "" and not code in only.split(","):
			continue
		var m := MapBuilder.load_map(path)
		var md: String = m["modes"][0]
		var rows := []
		for p in pitches:
			main_script.relaunch = {"faction": "null", "mode": md, "map": path}
			var inst: Node = (load(MAIN) as PackedScene).instantiate()
			inst.mobile = true
			if p > 0.0:
				inst.cam_pitch = p
				inst.pitch_forced = true
			get_tree().root.add_child(inst)
			for f in range(8):
				await get_tree().process_frame
			var r := _measure(inst, pt_w)
			r["pitch"] = inst.cam_pitch
			rows.append(r)
			var line := "%s %-6s pitch %2.0f  tap %5.1f pt (node %d, platform %4.1f pt)  off %d hud %d  badges: over %d hit %d on-platform %d" % [
					code, md, r["pitch"], r["tap"], r["worst"], r["plat"], r["off"], r["hud"], r["bover"], r["bhit"], r["bplat"]]
			print(line)
			out_lines.append(line)
			inst.queue_free()
			for f in range(2):
				await get_tree().process_frame
		# choice: no platform off-screen or under the HUD; then the biggest tap target; among pitches within
		# 5% of it, the fewest badge problems, then the steepest (most bird's-eye)
		var ok := rows.filter(func(r): return r["off"] == 0 and r["hud"] == 0)
		if ok.is_empty():
			ok = rows
		var best_tap: float = ok.map(func(r): return r["tap"]).max()
		var near := ok.filter(func(r): return r["tap"] >= best_tap * 0.95)
		near.sort_custom(func(a, b):
			var pa: int = a["bover"] + a["bhit"] + a["bplat"]
			var pb: int = b["bover"] + b["bhit"] + b["bplat"]
			return pa < pb if pa != pb else a["pitch"] > b["pitch"])
		var c: Dictionary = near[0]
		var line := "CHOICE %s pitch %2.0f tap %.1f pt platform %.1f pt off %d hud %d badges %d/%d/%d" % [code, c["pitch"], c["tap"], c["plat"], c["off"], c["hud"], c["bover"], c["bhit"], c["bplat"]]
		print(line)
		out_lines.append(line)
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		fa.store_string("\n".join(out_lines) + "\n")
		fa.close()
	print("PHONEFIT DONE")
	get_tree().quit()
