extends Node
## RELAY V2 render probe (a dev tool, not a suite): close-ups of every relay kind - its button, the mechanism on its
## bridge, the marked relay decks and the violet ghost of where the bridge will be - plus a structure on a relay's
## centre, a rotation mid-turn, a warning (the ghost brightens), and a tight gap (the pad pushed out, its Strut
## stretched; synthetic - no baked map has a gap under 51.9 deg). Run WINDOWED as a scene (the Net autoload):
##   phone:   Godot --path . --resolution 1688x780 res://tests/relay_shots.tscn -- --no-telemetry --mobile --safe-insets=59,0,59,21 tag=phone out=<dir>
##   desktop: Godot --path . --resolution 1688x780 res://tests/relay_shots.tscn -- --no-telemetry tag=desktop out=<dir>
##   only=rotation,switch   a subset of the shots below
## Also prints each shot's relay button tap disc in points (RelayView.hit_disc; the phone minimum is Rules.RELAY_HIT_PT).

const MAIN := "res://main.tscn"
# name, map, focus node, zoom (m), staging
const SHOTS := [
	["rotation", "T-06-pivot", 3, 44.0, ""],
	["rotation_turn", "T-06-pivot", 3, 44.0, "turn"],
	["switch", "T-07-switchyard", 2, 40.0, ""],
	["switch_warning", "T-07-switchyard", 2, 40.0, "warn"],
	["remote", "T-07-switchyard", 3, 58.0, ""],
	["retract", "T-07-switchyard", 1, 40.0, "retract"],
	["structure", "T-08-relay-works", 2, 36.0, "laser"],
	["tight_gap", "D-02-relay-bench", 6, 48.0, "tight"],
	["relay_bench", "D-02-relay-bench", -1, 0.0, ""],
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
	## Plays the match on for `seconds` of match time at real frame rate (the views follow).
	var t0: float = inst.sim.time
	var guard := 0
	while inst.sim.time - t0 < seconds and guard < 2000:
		await get_tree().process_frame
		guard += 1


func _run() -> void:
	var args := _args()
	var out_dir := str(args.get("out", "user://relay_shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tag := str(args.get("tag", "desktop"))
	var only: PackedStringArray = str(args.get("only", "")).split(",", false)
	var mobile := "--mobile" in OS.get_cmdline_user_args()
	var main_script = load("res://scripts/main.gd")
	for sh in SHOTS:
		var name: String = sh[0]
		if not only.is_empty() and not name in only:
			continue
		var path := "res://maps4/%s.json" % sh[1]
		var m := MapBuilder.load_map(path)
		main_script.relaunch = {"faction": "null", "mode": m["modes"][0], "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.mobile = mobile
		inst.demo = false
		if int(sh[2]) >= 0:
			inst.focus_node = int(sh[2])
			inst.scenario_zoom = float(sh[3])
		get_tree().root.add_child(inst)
		await _frames(10)
		inst.ais.clear()                                     # a still board: nobody plays
		var sim: Sim = inst.sim
		var id: int = int(sh[2])
		if id >= 0:
			sim.nodes[id]["owner"] = "A"
			MapBuilder.apply_owner(inst.vis[id]["parts"], "A")
		match str(sh[4]):
			"turn":
				sim.fire_relay(id)
				await _step(inst, Rules.RELAY_WARNING + Rules.RELAY_MOVE * 0.45)
			"warn":
				sim.fire_relay(id)
				await _step(inst, Rules.RELAY_WARNING * 0.4)
			"retract":
				sim.fire_relay(id)
				await _step(inst, Rules.RELAY_WARNING + Rules.RELAY_MOVE + 0.3)
			"laser":
				sim.nodes[id]["structure"] = "laser"
				sim._sync_legacy(sim.nodes[id])
			"tight":                                         # a synthetic 40 deg gap: the pad out, the Strut stretched
				var b: Dictionary = inst.vis[id]["relay_button"]
				var gap := deg_to_rad(40.0)
				var dist := Rules.RELAY_BUTTON_CLEAR / sin(gap / 2.0)
				var hs := []                                 # in the node's narrowest real gap (as a tight map would)
				for link in sim.adj[id]:
					hs.append(RelayView.bridge_heading(sim, int(link[1]), id, Rules.RELAY_RIM_DIST))
				hs.sort()
				var mid := 0.0
				var small := INF
				for i in range(hs.size()):
					var a1: float = hs[(i + 1) % hs.size()] + (TAU if i == hs.size() - 1 else 0.0)
					if a1 - float(hs[i]) < small:
						small = a1 - float(hs[i])
						mid = (float(hs[i]) + a1) / 2.0
				b["dir"] = Vector3(cos(mid), 0, sin(mid))
				b["tap"] = RelayView.seat_button(b["node"], sim.nodes[id]["pos"], b["dir"], dist)
				print("TIGHT gap 40 deg: dist %.2f m, strut scale.x %.2f" % [dist, dist - Rules.RELAY_PAD_R - RelayView.STRUT_BASE])
		await _frames(12)
		if id >= 0:
			var disc := RelayView.hit_disc(inst.cam, sim, inst.vis, id, mobile)
			var ppt := UiKit.pt_per_px(inst.get_viewport().get_visible_rect().size)
			print("%s %s: button disc %.1f px radius = %.1f pt across" % [tag, name, disc[1], 2.0 * float(disc[1]) * ppt])
		await RenderingServer.frame_post_draw
		var file := "%s/%s-%s.png" % [out_dir, tag, name]
		inst.get_viewport().get_texture().get_image().save_png(file)
		print("shot ", file)
		inst.queue_free()
		await _frames(3)
	print("RELAYSHOTS DONE")
	get_tree().quit()
