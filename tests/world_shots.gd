extends Node
## WORLD LAYER shots (a dev tool, not a suite): per map, as the game draws it on a landscape phone -
## 1 idle (an AI match fast-forwarded to 60 s: both colours in the tubes), 2 a capture mid-push (the next real
## capture, or a forced one after 40 s), 3-5 a forced 100-shown-unit fall off the longest bridge (splat, crawl, ride).
## Run WINDOWED as a scene, off-screen and silent:
## entrance=1 adds two TUBE ENTRANCE frames after the idle one: the player's closest zoom (Rules.CAM_ZOOM_MIN) panned
## onto a lit tube's foot, and a debug close-up of that entrance (camera 14 m from it, same pitch).
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/world_shots.tscn -- out=<dir> maps=R-01,R-10 [noworld=1]

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


func _wait(inst: Node, s: float) -> void:
	var t0: float = inst.sim.time
	while inst.sim.time - t0 < s:
		await get_tree().process_frame


func _shot(inst: Node, file: String) -> void:
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _open(path: String) -> Node:
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()
	return inst


func _entrance_shots(inst: Node, wl: WorldLayer, base: String) -> void:
	var pick: Dictionary = {}
	for tb in wl._tubes:
		if tb.get("ent", false) and tb.get("shown", false) and (pick.is_empty() or tb["owner"] == "A"):
			pick = tb
	if pick.is_empty():
		print("entrance: no lit tube entrance")
		return
	var node_y: float = (inst.sim.nodes[pick["id"]]["pos"] as Vector3).y
	var far: float = inst._view_fit[1]
	var home: Vector3 = inst._view_fit[0]
	var pitch := deg_to_rad(float(inst.cam_pitch))
	var foot := Vector3(pick["x"], node_y, float(pick["z"]) + (node_y - wl.floor_y) / tan(pitch))
	inst.cam_dist = far * Rules.CAM_ZOOM_MIN                 # the player's closest pinch zoom
	var room := 1.0 - Rules.CAM_ZOOM_MIN
	inst.cam_target = Vector3(clampf(foot.x, home.x - inst._map_half.x * room, home.x + inst._map_half.x * room), home.y,
			clampf(foot.z, home.z - inst._map_half.z * room, home.z + inst._map_half.z * room))
	inst._place_camera()
	await _frames(20)
	await _shot(inst, base + "-7-entrance-zoom.png")
	inst.cam_target = Vector3(pick["x"], wl.floor_y + 0.5, pick["z"])
	inst.cam_dist = 14.0
	inst._place_camera()
	await _frames(20)
	await _shot(inst, base + "-8-entrance-debug-closeup.png")
	print("entrance: node %d owner %s, zoom dist %.1f (fit %.1f)" % [pick["id"], pick["owner"], far * Rules.CAM_ZOOM_MIN, far])
	inst.cam_target = home
	inst.cam_dist = far
	inst._place_camera()


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://world_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	if str(args.get("noworld", "")) == "1":
		Rules.world_layer = false
	var tag := "noworld" if not Rules.world_layer else "world"
	var only: PackedStringArray = str(args.get("maps", "R-01")).split(",", false)
	for f in DirAccess.get_files_at("res://maps4"):
		if not (f.begins_with("R-") and f.ends_with(".json") and f.substr(0, 4) in only):
			continue
		var code: String = f.substr(0, 4)
		var inst: Node = await _open("res://maps4/" + f)
		var sim: Sim = inst.sim
		var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
		while sim.time < 60.0 and not sim.over:
			for ai in ais:
				ai.think(sim, 0.1)
			sim.step(0.1)
		sim.fx_events.clear()
		await _frames(40)
		await _shot(inst, "%s/%s-%s-1-idle.png" % [out, code, tag])
		var wl0 = inst.get("world_layer")
		print("%s idle: floor %s, pitch %.1f" % [code, wl0.floor_kind if wl0 != null else "-", float(inst.get("cam_pitch"))])
		if str(args.get("entrance", "")) == "1" and wl0 != null:
			await _entrance_shots(inst, wl0, "%s/%s-%s" % [out, code, tag])
		if str(args.get("idle_only", "")) == "1":
			inst.queue_free()
			await _frames(5)
			continue
		# 2 a capture: let the AIs play in real time until an owner changes
		for ai in ais:
			inst.ais.append(ai)
		var owners := sim.nodes.map(func(n): return n["owner"])
		var t0: float = sim.time
		var hit := -1
		while hit < 0 and sim.time - t0 < 40.0:
			await get_tree().process_frame
			for i in range(sim.nodes.size()):
				if sim.nodes[i]["owner"] != owners[i]:
					hit = i
					break
		var forced := ""
		if hit < 0:                                   # none came: flip a B node to A (view probe only)
			for n in sim.nodes:
				if n["owner"] == "B" and str(n["relay"]) == "":
					hit = n["id"]
					n["owner"] = "A"
					MapBuilder.apply_owner(inst.vis[hit]["parts"], "A")
					forced = "-forced"
					break
		inst.ais.clear()
		await _wait(inst, 0.7)
		print("%s capture node %d%s" % [code, hit, forced])
		await _shot(inst, "%s/%s-%s-2-capture%s.png" % [out, code, tag, forced])
		# 3-5 a 100-shown-unit fall off the longest bridge
		var best := -1
		var bl := 0.0
		for i in range(sim.edges.size()):
			if not sim.edges[i]["plaza"] and float(sim.edges[i]["geo"]["L"]) > bl:
				bl = float(sim.edges[i]["geo"]["L"])
				best = i
		var g: Dictionary = sim.edges[best]["geo"]
		var a := Vector3(g["A"][0], (sim.nodes[sim.edges[best]["a"]]["pos"] as Vector3).y, g["A"][1])
		var b := Vector3(g["B"][0], (sim.nodes[sim.edges[best]["b"]]["pos"] as Vector3).y, g["B"][1])
		var pts := []
		for k in range(24):
			pts.append(a.lerp(b, (k + 0.5) / 24.0) + Vector3(0, 0.3, 0))
		var ev := {"type": "fall", "seat": "B", "faction": "ember", "pts": pts, "units": 100.0 * Rules.SCALE, "pour": false}
		inst.fx.handle(ev)
		if inst.world_layer:
			inst.world_layer.handle(ev)
		await _wait(inst, 0.7)
		await _shot(inst, "%s/%s-%s-3-fall-0.7s.png" % [out, code, tag])
		await _wait(inst, 0.8)
		await _shot(inst, "%s/%s-%s-4-fall-splat-1.5s.png" % [out, code, tag])
		await _wait(inst, 2.5)
		await _shot(inst, "%s/%s-%s-5-fall-crawl-4s.png" % [out, code, tag])
		await _wait(inst, 3.0)
		await _shot(inst, "%s/%s-%s-6-fall-ride-7s.png" % [out, code, tag])
		if inst.world_layer:
			var wl: WorldLayer = inst.world_layer
			print("%s world: floor %s, tubes %d, splats %d, blobs %d, riders %d, zaps %d" % [code, wl.floor_kind,
					wl._tubes.size(), wl.splats_made, wl.blobs_made, wl.riders_done, wl.zaps_done])
		inst.queue_free()
		await _frames(3)
	print("WORLD SHOTS DONE")
	get_tree().quit()
