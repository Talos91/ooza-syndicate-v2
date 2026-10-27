extends Node
## RELAYS 3.0 PROTOTYPES render probe (a dev tool, not a suite): each prototype kind and the switch's drawbridge,
## BEFORE / WARNING (the ghost) / AFTER (the motion) with lines staged on it. Run WINDOWED as a scene (the Net autoload),
## off-screen and silent:
##   Godot --path . --resolution 1688x780 --audio-driver Dummy --position -6000,-6000 res://tests/proto_shots.tscn -- --no-telemetry out=<dir>
##   only=ferry,tilt     a subset;  maps=P   use the 🗺️ test maps maps4/P-0x-*.json instead of the fixtures
## Then tests/proto_sheet.py <dir> lays them out as one contact sheet.

const MAIN := "res://main.tscn"
# kind, fixture, focus node, zoom (m)
const KINDS := [
	["ferry", "res://tests/relays_proto/P-91-fixture-ferry.json", 4, 52.0],
	["conveyor", "res://tests/relays_proto/P-92-fixture-conveyor.json", 4, 58.0],
	["launcher", "res://tests/relays_proto/P-93-fixture-launcher.json", 4, 62.0],
	["lift", "res://tests/relays_proto/P-94-fixture-lift.json", 4, 46.0],
	["tilt", "res://tests/relays_proto/P-95-fixture-tilt.json", 4, 46.0],
	["switch", "res://maps4/T-07-switchyard.json", 2, 40.0],
]


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


func _step(inst: Node, seconds: float) -> void:
	var t0: float = inst.sim.time
	var guard := 0
	while inst.sim.time - t0 < seconds and guard < 4000:
		await get_tree().process_frame
		guard += 1


func _own(inst: Node, id: int, seat: String, units := -1.0) -> void:
	inst.sim.nodes[id]["owner"] = seat
	if units >= 0.0:
		inst.sim.nodes[id]["units"] = units
	MapBuilder.apply_owner(inst.vis[id]["parts"], seat)


func _shot(inst: Node, file: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


func _p_map(kind: String) -> String:
	## The 🗺️ test map for this kind (maps4/P-0x-*.json), or "" if not baked yet.
	var code: String = {"ferry": "P-01", "conveyor": "P-02", "launcher": "P-03", "lift": "P-04", "tilt": "P-05"}.get(kind, "")
	for f in DirAccess.get_files_at("res://maps4"):
		if code != "" and f.begins_with(code) and f.ends_with(".json"):
			return "res://maps4/" + f
	return ""


func _run() -> void:
	var args := _args()
	var out_dir := str(args.get("out", "user://proto_shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only: PackedStringArray = str(args.get("only", "")).split(",", false)
	var use_p := str(args.get("maps", "")) == "P"
	var main_script = load("res://scripts/main.gd")
	for k in KINDS:
		var kind: String = k[0]
		if not only.is_empty() and not kind in only:
			continue
		var path: String = k[1]
		var focus: int = k[2]
		if use_p and kind != "switch":
			path = _p_map(kind)
			if path == "":
				print("no P map for ", kind)
				continue
		var m := MapBuilder.load_map(path)
		main_script.relaunch = {"faction": "null", "mode": "1v1" if "1v1" in m["modes"] else m["modes"][0], "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.demo = false
		var rid := -1
		for n in m["nodes"]:
			if str(n.get("relay", "")) == kind and rid < 0:
				rid = int(n["id"])
		if use_p and kind != "switch":
			focus = rid
		inst.focus_node = focus
		inst.scenario_zoom = float(k[3])
		get_tree().root.add_child(inst)
		await _frames(10)
		if not use_p or kind == "switch":
			inst.ais.clear()                          # a still board; a P map keeps its AIs playing (traffic on it)
		var sim: Sim = inst.sim
		if kind == "switch":
			rid = focus
		_own(inst, rid, "A")
		var fire_wait := Rules.RELAY_WARNING + Rules.RELAY_MOVE * 0.5    # AFTER: mid-motion
		if not use_p or kind == "switch":
			match kind:
				"ferry":
					_own(inst, 3, "A", 60.0)
					sim.send(3, 4, 0.5)
					await _step(inst, 6.0)
					fire_wait = Rules.RELAY_WARNING + 1.0
				"conveyor":
					_own(inst, 3, "A", 40.0)
					sim.nodes[5]["units"] = 40.0
					sim.send(3, 4, 0.5)
					sim.send(5, 4, 0.5)
					await _step(inst, 2.5)
					fire_wait = Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.6
				"launcher":
					_own(inst, 0, "A", 50.0)
					sim.send(0, 2, 0.6)
					await _step(inst, 0.6)
					fire_wait = Rules.RELAY_WARNING + 3.2
				"lift":
					_own(inst, 0, "A", 40.0)
					sim.send(0, 8, 0.6)
					await _step(inst, 3.0)
				"tilt":
					sim.nodes[4]["units"] = 20.0
					sim.nodes[4]["relay_index"] = 1
					sim.nodes[5]["units"] = 60.0
					sim.send(5, 3, 0.5)
					await _step(inst, 3.5)
					fire_wait = Rules.RELAY_WARNING + Rules.RELAY_MOVE * 0.45
				"switch":
					await _step(inst, 0.2)
		else:                                         # a P map: let the AIs play a little first
			await _step(inst, float(args.get("play", "20")))
		await _shot(inst, "%s/%s-1-before.png" % [out_dir, kind])
		sim.nodes[rid]["relay_cd"] = 0.0
		sim.fire_relay(rid)
		await _step(inst, Rules.RELAY_WARNING * 0.5)
		await _shot(inst, "%s/%s-2-warning.png" % [out_dir, kind])
		if args.has("seq"):                           # seq=0.2,0.5,0.8: extra frames at these fractions of the motion
			var done := Rules.RELAY_WARNING * 0.5
			for f in str(args["seq"]).split(",", false):
				var at: float = Rules.RELAY_WARNING + float(sim.nodes[rid]["relay_move"]) * float(f)
				await _step(inst, at - done)
				done = at
				await _shot(inst, "%s/%s-seq-%s.png" % [out_dir, kind, f])
			fire_wait = done
		else:
			await _step(inst, fire_wait - Rules.RELAY_WARNING * 0.5)
		await _shot(inst, "%s/%s-3-after.png" % [out_dir, kind])
		inst.queue_free()
		await _frames(3)
	print("PROTOSHOTS DONE")
	get_tree().quit()
