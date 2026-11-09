extends Node
## WORLD v3 shots (a dev tool, not a suite): R-01 STRAIT, Daniele's 2026-11-09/10 corrections on pits-tubes v2 + demo12.
## Nobody plays (AIs off); states are forced. Seat A = left, seat B = right (two different seat colours).
##   1-game-before.png / 1-game-after.png  game camera, columns at T2/T3 for A and B: transport tubes hidden (= demo12) / shown
##   2-pit-entry.png      every column at T3, low over pit 0: each tube climbs over the rim into the goo on its own (no collector)
##   3-rack-foot.png      A's home column at T3, side-on: the coupling angled up, the 2 m rack, the Locals walking under
##   4a-one-column.png    straight down, only A's home column built (T3, 4 tubes): one tube to each of the 4 pits
##   4b-all-columns.png   straight down, every column at T3
##   5-googat-before.png / 5-googat-after.png   a GooGat (machinegoon, B, T3) column: tubes hidden / shown, like a vat
##   6-two-seats.png      an A vat and a B GooGat side by side at T3: tubes, lift, door lasers, pits each in their seat colour
## Run WINDOWED, off-screen and silent (phone: --resolution 740x340 ... -- --mobile; desktop: --resolution 1280x720):
##   Godot --path . --resolution 740x340 --audio-driver Dummy --position -6000,-6000 res://tests/world_v3_shots.tscn -- \
##       out=<dir> --test --mobile

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(inst: Node, file: String) -> void:
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""


func _home(inst: Node) -> void:
	inst.cam_target = inst._view_fit[0]
	inst.cam_dist = inst._view_fit[1]
	inst._place_camera()


func _cam_shot(inst: Node, from: Vector3, look: Vector3, file: String, fov := 50.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 600.0
	inst.add_child(cam)
	cam.global_position = from
	cam.look_at(look, Vector3.UP if absf((look - from).normalized().y) < 0.99 else Vector3(0, 0, -1))
	var was := inst.get_viewport().get_camera_3d()
	cam.make_current()
	await _frames(3)
	await _shot(inst, file)
	if was:
		was.make_current()
	cam.queue_free()


func _wait_world(wl: WorldLayer, s: float) -> void:
	var t0 := wl._t
	while wl._t - t0 < s:
		await get_tree().process_frame


func _col_near(wl: WorldLayer, x: float, z: float) -> int:
	var best := -1
	var bd := INF
	for i in wl.pipes.cols:
		var d := Vector2(float(wl._tubes[i]["x"]) - x, float(wl._tubes[i]["z"]) - z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _own(sim: Sim, wl: WorldLayer, i: int, owner: String, structure: String, tier: int) -> void:
	var n: Dictionary = sim.nodes[wl._tubes[i]["id"]]
	n["owner"] = owner
	n["structure"] = structure
	n["tier"] = tier


func _pipes_shown(wl: WorldLayer, on: bool) -> void:
	(wl.pipes.get_child(0) as Node3D).visible = on


func _top(inst: Node, wl: WorldLayer, file: String) -> void:
	var lc: WorldLocals = wl.locals
	var bb := lc.board_bounds()
	var vp: Vector2 = inst.get_viewport().get_visible_rect().size
	var ext := 0.0
	for c in lc.craters:
		ext = maxf(ext, maxf(absf((c as Vector3).x - bb.get_center().x) * vp.y / vp.x, absf((c as Vector3).z - bb.get_center().y)) + WorldLocals.RING_R + 10.0)
	var ctr := Vector3(bb.get_center().x, wl.floor_y, bb.get_center().y)
	await _cam_shot(inst, ctr + Vector3(0, ext / tan(deg_to_rad(25.0)), 0.01), ctr, file)


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://world_v3"))
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file("R-01")}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(5)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var wl: WorldLayer = inst.world_layer
	var tries := 0
	while (wl.pipes == null or not wl.pipes.built) and tries < 600:
		await get_tree().process_frame
		tries += 1
	if wl.pipes == null or not wl.pipes.built:
		print("WV3 tubes never built")
		get_tree().quit(1)
		return
	var fy := wl.floor_y
	var ha: int = -1
	for i in wl.pipes.cols:
		if int(wl._tubes[i]["id"]) == int(sim.homes.get("A", -1)):
			ha = i
	var hb := -1
	for i in wl.pipes.cols:
		if int(wl._tubes[i]["id"]) == int(sim.homes.get("B", -1)):
			hb = i
	var ax := float(wl._tubes[ha]["x"])
	var left := ax < 0.0
	var va := _col_near(wl, -13.6 if left else 13.6, 0.0)      # A's common vat (its side of the board centre)
	var gb := _col_near(wl, 13.6 if left else -13.6, 0.0)      # B's GooGat (the other side)
	print("WV3 homes A col %d B col %d | A vat col %d | B GooGat col %d | slots %d tris %d stands %d" % [ha, hb, va, gb,
			wl.pipes._slots, wl.pipes.tris, wl.pipes.posts.size()])
	_own(sim, wl, ha, "A", "vat", 3)
	_own(sim, wl, hb, "B", "vat", 3)
	_own(sim, wl, va, "A", "vat", 2)
	_own(sim, wl, gb, "B", "machinegoon", 3)
	await _wait_world(wl, WorldTubes.FILL_S + 6.0)
	_home(inst)
	await _frames(3)
	_pipes_shown(wl, false)
	await _frames(2)
	await _shot(inst, "%s/1-game-before.png" % out)
	_pipes_shown(wl, true)
	await _frames(2)
	await _shot(inst, "%s/1-game-after.png" % out)
	# 5: the GooGat column (B), low and three-quarter
	var g := Vector3(wl._tubes[gb]["x"], fy, wl._tubes[gb]["z"])
	var gfrom := g + Vector3(6.0 if left else -6.0, 9.0, 13.0)
	_pipes_shown(wl, false)
	await _cam_shot(inst, gfrom, g + Vector3(0, 1.0, 0), "%s/5-googat-before.png" % out)
	_pipes_shown(wl, true)
	await _cam_shot(inst, gfrom, g + Vector3(0, 1.0, 0), "%s/5-googat-after.png" % out)
	# 6: A's vat and B's GooGat side by side
	var v := Vector3(wl._tubes[va]["x"], fy, wl._tubes[va]["z"])
	var mid := v.lerp(g, 0.5)
	await _cam_shot(inst, mid + Vector3(0, 14.0, 24.0), mid + Vector3(0, 1.5, 0), "%s/6-two-seats.png" % out)
	# 3: A's home column side-on at eye level over the floor: angled couplings, the 2 m rack, Locals under it
	var h := Vector3(wl._tubes[ha]["x"], fy, wl._tubes[ha]["z"])
	var pit := wl.pipes.pit_of(wl._tubes[ha])
	var to := (pit - h).normalized()
	var side := to.cross(Vector3.UP).normalized()
	await _wait_world(wl, 2.0)
	await _cam_shot(inst, h + to * 4.0 + side * 9.0 + Vector3(0, 2.6, 0), h + to * 4.0 + Vector3(0, 1.2, 0), "%s/3-rack-foot.png" % out, 55.0)
	# 4a: only A's home column built
	var keep := {}
	for i in wl.pipes.cols:
		var n: Dictionary = sim.nodes[wl._tubes[i]["id"]]
		keep[i] = [n["owner"], n["structure"], n["tier"]]
		if i != ha:
			n["structure"] = ""
	await _wait_world(wl, 1.0)
	await _top(inst, wl, "%s/4a-one-column.png" % out)
	print("WV3 A home col %d pits %s" % [ha, str(wl.pipes.cols[ha]["pits"])])
	# 4b / 2: every column at T3 (left half A, right half B)
	for i in wl.pipes.cols:
		_own(sim, wl, i, "A" if (float(wl._tubes[i]["x"]) < 0.0) == left else "B", "vat", 3)
	await _wait_world(wl, WorldTubes.FILL_S + 4.0)
	await _top(inst, wl, "%s/4b-all-columns.png" % out)
	var c0: Vector3 = wl.locals.craters[0]
	var bc := wl.locals.board_bounds().get_center()
	var inward := (Vector3(bc.x, fy, bc.y) - c0).normalized()
	await _cam_shot(inst, c0 - inward * 6.0 + Vector3(0, 20.0, 0) + inward.cross(Vector3.UP) * 8.0, c0 + inward * 9.0 + Vector3(0, 1.0, 0), "%s/2-pit-entry.png" % out)
	print("WV3 pit colours %s" % str(wl.pipes.pit_cols))
	get_tree().quit(0)
