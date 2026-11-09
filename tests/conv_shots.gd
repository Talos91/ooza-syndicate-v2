extends Node
## CONVEYOR CARRY shots (demo-rules-pass-2, a dev tool): a line of A's over a belt and on to its target, as the game draws it -
## frames before the belt, on it, off it (carrying the push: the speed trail) and arrived (trail gone). Run WINDOWED:
##   Godot --path . --resolution 1280x592 --audio-driver Dummy --position -6000,-6000 res://tests/conv_shots.tscn -- --test out=<dir> [map=R-01 from=7 to=1]
## Prints each frame's sim state (zone, conv, conv_carry, HordeView.speed_trails) and the head's screen point (for crops).

const MAIN := "res://main.tscn"


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(inst: Node, sim: Sim, h: Dictionary, file: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = inst.get_viewport().get_texture().get_image()
	img.save_png(file + ".png")
	var cam := inst.get_viewport().get_camera_3d()
	var hp := cam.unproject_position(Sim.sample(h, maxf(float(h["s"]) - 3.0, 0.0))[0]) if h in sim.hordes else Vector2(-1, -1)
	hp *= Vector2(img.get_size()) / inst.get_viewport().get_visible_rect().size   # (canvas_items stretch: canvas -> pixels)
	var r := Rect2i(int(hp.x) - 160, int(hp.y) - 110, 320, 220).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x > 10 and r.size.y > 10:
		img.get_region(r).save_png(file + "-zoom.png")
	print("SHOT %s %s t %.2f s %.1f/%.1f conv %s carry %s trails %d head %s" % [file.get_file(), label, sim.time, h["s"], h["L"],
			h.get("conv", 0), h.get("conv_carry", 0), inst.hordes.speed_trails, hp])


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://conv_shots"))
	var code := str(args.get("map", "R-01"))
	var a := int(args.get("from", "7"))
	var b := int(args.get("to", "1"))
	DirAccess.make_dir_recursive_absolute(out)
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(30)
	inst.ais.clear()
	var sim: Sim = inst.sim
	for id in sim.find_route(a, b):
		if str(sim.nodes[id].get("node_kind", "")) != "junction":
			sim.nodes[id]["owner"] = "A"
			if inst.vis.has(id):
				MapBuilder.apply_owner(inst.vis[id]["parts"], "A")
	sim.nodes[a]["units"] = 20.0 * Rules.SCALE
	var h := sim.send(a, b, 1.0)
	var belts := []
	for sp in h["spans"]:
		if sim._conv_edges.has(sp["edge"]) or sim._belt_edges.has(sp["edge"]):
			belts.append(sp)
	print("route %s belts %s" % [h["route"], belts])
	var stage := 0
	var t0: float = sim.time
	while sim.time - t0 < 40.0 and stage < 4:
		await get_tree().process_frame
		var on := int(h.get("conv", 0)) != 0
		var carry := int(h.get("conv_carry", 0))
		if stage == 0 and h["s"] > 3.0 and not on and carry == 0:
			await _shot(inst, sim, h, "%s/%s-1-before" % [out, code], "before")
			stage = 1
		elif stage == 1 and on and h["s"] - Sim.chain_length(h) > float(belts[0]["s0"]) if not belts.is_empty() else false:
			await _shot(inst, sim, h, "%s/%s-2-on-belt" % [out, code], "on")
			stage = 2
		elif stage == 2 and not on and carry != 0 and h["s"] - Sim.chain_length(h) > float(belts[-1]["s1"]) + 1.5:
			await _shot(inst, sim, h, "%s/%s-3-carried" % [out, code], "carried")
			stage = 3
		elif stage == 3 and (h["state"] == "absorb" or not (h in sim.hordes)):
			await _frames(2)
			await _shot(inst, sim, h, "%s/%s-4-arrived" % [out, code], "arrived")
			stage = 4
	print("CONV SHOTS DONE stage %d" % stage)
	get_tree().quit()
