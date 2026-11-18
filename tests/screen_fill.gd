extends Node
## Screen-fill probe (map-targets 2026-11-18; a dev tool, not a suite). Measures how much of the PIT BOX a map's start view fills on
## the Galaxy Z Fold 7 front screen (840x360 pt; the frame 05 Handoff/handoffs/screen-layout Daniele 2026-11-18/hud-zones-over-game.png).
##   Godot_console --path . --audio-driver Dummy --resolution 1266x585 res://tests/screen_fill.tscn -- out=<file> [maps=G-05,G-08] [profile=zfold7-cover]
## Lines: "FILL <code> k=v ..." and "TILT <code> x0,y0,x1,y1;..." (normalised 0..1 screen coords of the sloped / conveyor decks).
## Zones: SAFE = the screen minus the left bezel strip (4 % of the width); PIT = x 11.3..88.7 %, y 18.3..95.6 % of the safe area
## (his frame measured at 1500x643, bezel 60 px; bezel=0 for a screen without a cut-out). Desktop emulation only (no real phone).

const MAIN := "res://main.tscn"
const PROFILES := {"phone": Vector2i(812, 375), "phone-wide": Vector2i(844, 390), "zfold7-cover": Vector2i(840, 360), "p16x9": Vector2i(640, 360), "tablet": Vector2i(1024, 768)}
const BEZEL := 0.04
const PIT_X := Vector2(0.113, 0.887)
const PIT_Y := Vector2(0.183, 0.956)
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


func _circle(cam: Camera3D, p: Vector3, r: float) -> Dictionary:
	var ax := _ground_axes(cam)
	var c := cam.unproject_position(p)
	var pts := PackedVector2Array()
	for k in range(24):
		var a := TAU * k / 24.0
		pts.append(cam.unproject_position(p + (ax[0] * cos(a) + ax[1] * sin(a)) * r))
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	return {"c": c, "hx": (cam.unproject_position(p + ax[0] * r) - c).length(), "hy": (cam.unproject_position(p + ax[1] * r) - c).length(), "box": box, "pts": pts}


func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _measure(main: Node, pt_w: float) -> Dictionary:
	var cam: Camera3D = main.cam
	var sim = main.sim
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var ppt := pt_w / vp.x
	var sx0 := vp.x * float(_arg("bezel", str(BEZEL)))
	var sw := vp.x - sx0
	var pit := Rect2(sx0 + sw * PIT_X.x, vp.y * PIT_Y.x, sw * (PIT_X.y - PIT_X.x), vp.y * (PIT_Y.y - PIT_Y.x))
	if _arg("adapt", "0") == "1":
		# adaptation rule (SCREEN-LAYOUT-SPEC section 1): side columns + gaps = max(11.25 % of the safe width, 88 pt x k), top 66 pt x k, bottom 16 pt x k
		var k := UiKit.hud_k_for(vp.y * ppt) / UiKit.hud_k_for(360.0)
		var mx := maxf(0.1125 * sw * ppt, 88.0 * k) / ppt
		pit = Rect2(sx0 + mx, 66.0 * k / ppt, sw - 2.0 * mx, vp.y - (66.0 + 16.0) * k / ppt)
	var tap_r := Rules.R + 2.5
	var circ := {}
	var box := Rect2()
	var first := true
	var all_pts := PackedVector2Array()
	var real := []
	for n in sim.nodes:
		if n["node_kind"] == "junction":
			continue
		real.append(n)
		var c := _circle(cam, n["pos"], Rules.R)
		circ[n["id"]] = c
		box = c["box"] if first else box.merge(c["box"])
		first = false
		all_pts.append_array(c["pts"])
	var out_of_pit := 0
	for n in real:
		if not pit.encloses((circ[n["id"]]["box"] as Rect2).grow(-1.0)):
			out_of_pit += 1
	var hull := Geometry2D.convex_hull(all_pts)
	var rectp := PackedVector2Array([pit.position, Vector2(pit.end.x, pit.position.y), pit.end, Vector2(pit.position.x, pit.end.y)])
	var inter := Geometry2D.intersect_polygons(hull, rectp)
	var inter_a := 0.0
	for pl in inter:
		inter_a += _area(pl)
	var bb_in := box.intersection(pit)
	var tap := INF
	var spacing := INF
	var gap := INF
	var plat_pt := INF
	for n in real:
		var t := _circle(cam, n["pos"], tap_r)
		var size: float = 2.0 * minf(t["hx"], t["hy"])
		var c0: Vector2 = t["c"]
		plat_pt = minf(plat_pt, 2.0 * minf(circ[n["id"]]["hx"], circ[n["id"]]["hy"]) * ppt)
		for m in real:
			if m["id"] != n["id"]:
				var d: float = c0.distance_to(circ[m["id"]]["c"])
				size = minf(size, d)
				spacing = minf(spacing, d)
				gap = minf(gap, d - circ[n["id"]]["hx"] - circ[m["id"]]["hx"])
		tap = minf(tap, size)
	var tilt := PackedStringArray()
	var min_len := INF
	var sum_len := 0.0
	var bridges := 0
	for e in sim.edges:
		bridges += 1
		var a: Dictionary = sim.nodes[e["a"]]
		var b: Dictionary = sim.nodes[e["b"]]
		var pa := cam.unproject_position(a["pos"])
		var pb := cam.unproject_position(b["pos"])
		var l := pa.distance_to(pb) * ppt
		min_len = minf(min_len, l)
		sum_len += l
		var g: Dictionary = e.get("geo", {})
		var sloped: bool = absf(float(g.get("p0", 0.0)) - float(g.get("p1", 0.0))) > 0.05
		if e.get("proto", "") == "conveyor" or sloped:
			tilt.append("%.4f,%.4f,%.4f,%.4f" % [pa.x / vp.x, pa.y / vp.y, pb.x / vp.x, pb.y / vp.y])
	var pw := pit.size.x
	var ph := pit.size.y
	return {"nodes": real.size(), "bridges": bridges, "tilted": tilt.size(),
		"bbox_fill": bb_in.get_area() / pit.get_area() * 100.0, "hull_fill": inter_a / pit.get_area() * 100.0,
		"bbox_w": box.size.x / pw * 100.0, "bbox_h": box.size.y / ph * 100.0,
		"m_left": (box.position.x - pit.position.x) / pw * 100.0, "m_right": (pit.end.x - box.end.x) / pw * 100.0,
		"m_top": (box.position.y - pit.position.y) / ph * 100.0, "m_bottom": (pit.end.y - box.end.y) / ph * 100.0,
		"out_of_pit": out_of_pit, "spacing": spacing * ppt, "gap": gap * ppt, "tap": tap * ppt, "plat": plat_pt,
		"min_len": min_len, "mean_len": sum_len / maxf(bridges, 1),
		"pit_w": pw * ppt, "pit_h": ph * ppt, "density": real.size() / (pw * ppt * ph * ppt) * 10000.0, "tilt": tilt}


func _run() -> void:
	var prof := _arg("profile", "zfold7-cover")
	var wh: Vector2i = PROFILES[prof]
	get_window().size = wh
	UiKit.test_pt_h = float(wh.y)
	UiKit.test_insets = Vector4(wh.x * float(_arg("bezel", str(BEZEL))), 0, 0, 0)   # map-pass: the Fold's camera strip is a real safe inset, so the game's pit_rect() = this probe's pit
	for f in range(6):
		await get_tree().process_frame
	var only := _arg("maps", "")
	var main_script = load("res://scripts/main.gd")
	for path in MapPool.all():
		var code: String = path.get_file().substr(0, 4)
		if only != "" and not code in only.split(","):
			continue
		if only == "" and not code in MapPool.PROTO:
			continue
		var m := MapBuilder.load_map(path)
		main_script.relaunch = {"faction": "null", "mode": m["modes"][0], "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.mobile = true
		get_tree().root.add_child(inst)
		for f in range(10):
			await get_tree().process_frame
		var sweep: Array = [inst.cam_pitch] if _arg("pitches", "") == "" else Array(_arg("pitches", "").split(",")).map(func(v): return float(v))
		for pv in sweep:
			if _arg("pitches", "") != "":
				inst.cam_pitch = pv
				inst._fit_camera()
				for f in range(2):
					await get_tree().process_frame
			var r := _measure(inst, float(wh.x))
			var line := "FILL(%s) %s %s mode=%s pitch=%.0f zoom=%.2f dist=%.1f nodes=%d bridges=%d tilted=%d bbox_fill=%.1f hull_fill=%.1f bbox_w=%.1f bbox_h=%.1f m_left=%.1f m_right=%.1f m_top=%.1f m_bottom=%.1f out_of_pit=%d spacing=%.1f gap=%.1f tap=%.1f plat=%.1f min_len=%.1f mean_len=%.1f density=%.2f" % [
					prof, code, str(m.get("name", "")).replace(" ", "_"), m["modes"][0], inst.cam_pitch, MapCamera.zoom_for(code), inst.cam_dist,
					r["nodes"], r["bridges"], r["tilted"], r["bbox_fill"], r["hull_fill"], r["bbox_w"], r["bbox_h"], r["m_left"], r["m_right"], r["m_top"], r["m_bottom"],
					r["out_of_pit"], r["spacing"], r["gap"], r["tap"], r["plat"], r["min_len"], r["mean_len"], r["density"]]
			print(line)
			out_lines.append(line + " pit_pt=%.0fx%.0f" % [r["pit_w"], r["pit_h"]])
			if r["tilt"].size() > 0:
				out_lines.append("TILT %s %s" % [code, ";".join(r["tilt"])])
		inst.queue_free()
		for f in range(2):
			await get_tree().process_frame
	var fa := FileAccess.open(_arg("out", "user://screenfill.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(out_lines) + "\n")
	fa.close()
	print("SCREENFILL DONE")
	get_tree().quit()
