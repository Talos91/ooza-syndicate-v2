extends Node
## ROTATION relay stress probe (a dev tool, not a suite; Daniele 2026-10-27: "on rotation the animation always
## breaks"). Fires every rotation relay of a few boards again and again - back to back, with a line walking the deck,
## with a second (refused) fire during the warning - and compares the view with the sim every frame:
##  - at rest: every relay deck at its built transform, shown exactly when the sim has it open; the turntable at
##    minus the sum of the authoritative deltas (the host's, unrounded); no destination ghost of a moving relay;
##  - moving: the swinging deck shown, turning the sim's way, no frame-to-frame jump; MapBatch draws what the nodes say;
##  - landing: how far the swung deck's far end lands from the opening deck's far end (the snap at the end).
## Modes: offline (the view's own Sim) and guest (the view's Sim fed by snapshots of a host Sim at the server's 20 Hz,
## var_to_bytes + 1/64 rounding like the wire, released through a playout buffer with the effects queued behind the
## snapshot they followed - Net._playout).
## Run WINDOWED, off-screen and silent:
##   Godot --audio-driver Dummy --position -6000,-6000 --path . --resolution 1280x720 res://tests/relay_rot_probe.tscn
##       -- --no-telemetry [fires=6] [modes=offline,guest] [maps=T-06-pivot,...] [out=<dir> for before/mid/after shots]
## Prints one line per board and mode and "RELAYROT TOTAL desyncs=N"; exit code 1 when N > 0.

const MAIN := "res://main.tscn"
const MAPS := ["T-06-pivot", "res://tests/relay_multi.json", "B-03-khepri-wheel", "M-54-gearwheel-glade", "N-17-whirlpool"]
const SNAP_EVERY := 0.05            # Net.SNAPSHOT_EVERY_SERVER
const PLAYOUT := 0.12               # Net.PLAYOUT_DELAY
const POS_TOL := 0.05               # m
const ANG_TOL := 0.02               # rad
const JUMP_ANG := 0.3               # rad in one frame for a shown, moving deck
const JUMP_POS := 3.0               # m in one frame

var total := 0
var _log_left := 40


func _ready() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _run() -> void:
	var args := _args()
	var fires := int(args.get("fires", "6"))
	var modes: PackedStringArray = str(args.get("modes", "offline,guest")).split(",", false)
	var maps: Array = MAPS if not args.has("maps") else Array(str(args["maps"]).split(",", false))
	var out_dir := str(args.get("out", ""))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	for mp in maps:
		for mode in modes:
			await _board(str(mp), mode, fires, out_dir)
	print("RELAYROT TOTAL desyncs=%d" % total)
	get_tree().quit(1 if total > 0 else 0)


func _bad(stats: Dictionary, kind: String, msg: String) -> void:
	stats[kind] = int(stats.get(kind, 0)) + 1
	total += 1
	if _log_left > 0:
		_log_left -= 1
		print("  DESYNC %s: %s" % [kind, msg])


func _board(mp: String, mode: String, fires: int, out_dir: String) -> void:
	var path: String = mp if mp.begins_with("res://") else "res://maps4/%s.json" % mp
	var m := MapBuilder.load_map(path)
	var main_script = load("res://scripts/main.gd")
	main_script.relaunch = {"faction": "null", "mode": m["modes"][0], "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	inst.ais.clear()
	var view: Sim = inst.sim
	var host: Sim = view
	var guest := mode == "guest"
	if guest:                                             # the view only shows snapshots of a separate host Sim
		inst.paused = true
		host = Sim.new()
		var seats := {}
		for n in view.nodes:
			if n["owner"] != "":
				seats[n["id"]] = n["owner"]
		host.setup(inst.map, MapBuilder.layout(inst.map), seats, inst.SEAT_FACTIONS, inst.seed_value, {}, inst.LOADOUTS)
	var rots := []
	for n in host.nodes:
		if n["relay"] == "rotation" and not host.relay_states(n).is_empty():
			rots.append(n["id"])
	if rots.is_empty():
		print("RELAYROT %s %s: no rotation relay" % [mp, mode])
		inst.queue_free()
		await get_tree().process_frame
		return
	for id in rots:
		host.nodes[id]["owner"] = "A"
		host.nodes[id]["units"] = 60.0
	var acc := {}                                         # id -> sum of authoritative deltas
	var stats := {}
	var q := []                                           # guest playout: [release time, "state"|"effects", data]
	var prev := {}                                        # deck instance id -> [pos, yaw, visible]
	var was_moving := {}
	var last_swing := {}                                  # id -> {edge: far-end world pos of the swung deck}
	var shots := 0
	for round_i in range(fires):
		for id in rots:                                   # every relay ready: fire them all
			host.nodes[id]["relay_cd"] = 0.0
		var walked := false
		if round_i % 2 == 1:                              # a line on a rotation deck when it turns (flung)
			var id0: int = rots[0]
			for link in host.adj[id0]:
				if host.is_edge_open(int(link[1])) and host.edge_controller.get(int(link[1]), -1) == id0:
					walked = not host.send(id0, int(link[0]), 0.5).is_empty()
					break
			if walked:
				await _run_for(inst, host, view, guest, 0.6, q, rots, acc, stats, prev, was_moving, last_swing)
		for id in rots:
			if not host.fire_relay(id):
				_bad(stats, "fire_refused", "%s relay %d would not fire" % [mp, id])
		await _run_for(inst, host, view, guest, Rules.RELAY_WARNING * 0.5, q, rots, acc, stats, prev, was_moving, last_swing)
		for id in rots:                                   # a second fire during the warning: refused, nothing changes
			if host.fire_relay(id):
				_bad(stats, "double_fire", "relay %d fired twice" % id)
		await _run_for(inst, host, view, guest, Rules.RELAY_WARNING * 0.5 + Rules.RELAY_MOVE * 0.5, q, rots, acc, stats, prev, was_moving, last_swing)
		if out_dir != "" and round_i == 0 and shots == 0:
			await _shot(inst, "%s/%s-%s-mid.png" % [out_dir, mp.get_file().get_basename(), mode])
			shots += 1
		await _run_for(inst, host, view, guest, Rules.RELAY_MOVE * 0.5 + 0.4, q, rots, acc, stats, prev, was_moving, last_swing)
		if out_dir != "" and round_i == 0:
			await _shot(inst, "%s/%s-%s-after.png" % [out_dir, mp.get_file().get_basename(), mode])
	await _run_for(inst, host, view, guest, 0.5, q, rots, acc, stats, prev, was_moving, last_swing)
	var lm: float = stats.get("_landing_max", 0.0)
	var sm: float = stats.get("_step_max", 0.0)
	stats.erase("_landing_max")
	stats.erase("_step_max")
	print("RELAYROT %s %s: %d relays x %d fires, %d desync kinds %s, landing gap max %.2f m, swing step max %.3f rad/frame" % [
			mp, mode, rots.size(), fires, stats.size(), str(stats), lm, sm])
	inst.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(inst: Node, file: String) -> void:
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("  shot ", file)


func _run_for(inst: Node, host: Sim, view: Sim, guest: bool, seconds: float, q: Array, rots: Array, acc: Dictionary,
		stats: Dictionary, prev: Dictionary, was_moving: Dictionary, last_swing: Dictionary) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		var dt := minf(get_process_delta_time(), 0.05)
		t += dt
		# the check reads what last frame drew (main, Fx, RelayView and MapBatch all ran after the snapshot was
		# applied, as they do after Net's _process in a real guest); then this frame's snapshot goes in
		if not guest:
			for id in rots:                               # offline: the view's Sim is the host
				_track_acc(host, id, acc)
		_check(inst, view, rots, acc, stats, prev, was_moving, last_swing)
		if guest:
			_host_step(host, view, dt, q, rots, acc)


var _host_clock := 0.0
var _snap_clock := 0.0
var _host_phase := {}
var _since_applied := 0.0


func _track_acc(host: Sim, id: int, acc: Dictionary) -> void:
	var ph: String = host.nodes[id]["relay_phase"]
	if _host_phase.get(id, "") == "moving" and ph != "moving":
		acc[id] = float(acc.get(id, 0.0)) + float(host.nodes[id]["relay_anim"].get("delta", 0.0))
	_host_phase[id] = ph


func _host_step(host: Sim, view: Sim, dt: float, q: Array, rots: Array, acc: Dictionary) -> void:
	## The server: step, effects out at once (queued behind the last snapshot), snapshots at 20 Hz; the guest shows
	## each snapshot PLAYOUT after it was taken, and the effects queued behind it right after it.
	host.step(dt)
	for id in rots:
		_track_acc(host, id, acc)
	_host_clock += dt
	if not host.fx_events.is_empty():
		q.append([-1.0, "effects", host.fx_events.duplicate(true)])
		host.fx_events.clear()
	_snap_clock += dt
	if _snap_clock >= SNAP_EVERY:
		_snap_clock -= SNAP_EVERY
		var wire: PackedByteArray = var_to_bytes(Net._q64(Net.snapshot(host, true)))
		q.append([_host_clock, "state", bytes_to_var(wire)])
	var play_t := _host_clock - PLAYOUT
	while not q.is_empty():
		var e: Array = q[0]
		if e[1] == "state":
			if float(e[0]) > play_t:
				break
			Net.apply_snapshot(view, e[2])
			_since_applied = 0.0
		else:                                             # effects queued behind a shown snapshot (Net._playout)
			view.fx_events.append_array(e[2])
		q.pop_front()
	_since_applied += dt
	if _since_applied < 0.5:                              # Net: the guest's clock runs between snapshots (Net.predict)
		Net.predict(view, dt)
	Net.blend(view, dt)


func _check(inst: Node, view: Sim, rots: Array, acc: Dictionary, stats: Dictionary, prev: Dictionary,
		was_moving: Dictionary, last_swing: Dictionary) -> void:
	var vis: Dictionary = inst.vis
	var rv: RelayView = vis.get("relay_view")
	for id in rots:
		var n: Dictionary = view.nodes[id]
		var c: Vector3 = n["pos"]
		var moving: bool = n["relay_phase"] == "moving"
		var anim: Dictionary = n["relay_anim"]
		var pf = vis[id]["platform"]
		var edges: Array = view.controlled_edges(id)
		if moving:
			var delta: float = anim.get("delta", 0.0)
			var swing := {}
			for i in anim.get("closing", []):
				var decks: Array = vis["edge_decks"][int(i)]
				var any_shown := false
				var far_pos := Vector3.ZERO
				var far_d := -1.0
				for k in range(decks.size()):
					var d: Node3D = decks[k]
					if not d.is_visible_in_tree():
						continue
					any_shown = true
					var key := d.get_instance_id()
					var yaw := d.rotation.y
					var base: Transform3D = vis["edge_base"][int(i)][k]
					var turned := wrapf(yaw - base.basis.get_euler().y, -PI, PI)   # = -angle so far
					if absf(delta) > 0.01 and turned * -signf(delta) < -ANG_TOL:
						_bad(stats, "wrong_way", "relay %d edge %d turned %.2f, delta %.2f" % [id, i, turned, delta])
					if absf(turned) > absf(delta) + ANG_TOL:
						_bad(stats, "overshoot", "relay %d edge %d turned %.2f past delta %.2f" % [id, i, turned, delta])
					if prev.has(key) and bool(prev[key][2]):
						var dy := absf(wrapf(yaw - float(prev[key][1]), -PI, PI))
						var dp := (d.position - (prev[key][0] as Vector3)).length()
						stats["_step_max"] = maxf(float(stats.get("_step_max", 0.0)), dy)
						if dy > JUMP_ANG or dp > JUMP_POS:
							_bad(stats, "jump", "relay %d edge %d deck %d jumped %.2f rad / %.2f m in a frame" % [id, i, k, dy, dp])
					var fd := (d.position - c).length()
					if fd > far_d:
						far_d = fd
						far_pos = d.position
				if not any_shown:
					_bad(stats, "swing_hidden", "relay %d edge %d: no deck shown while it turns" % [id, i])
				swing[int(i)] = far_pos
			for i in anim.get("opening", []):
				for d in vis["edge_decks"][int(i)]:
					if (d as Node3D).is_visible_in_tree():
						_bad(stats, "opening_early", "relay %d edge %d shown before it landed" % [id, i])
						break
			if rv != null:
				for g in rv.groups:
					if int(g["ctrl"]) == id and bool(g["on"]):
						_bad(stats, "ghost_moving", "relay %d edge %d ghost on while moving" % [id, int(g["edge"])])
			last_swing[id] = swing
		else:
			if was_moving.get(id, false):                 # just landed: the far end's snap
				for ci in (last_swing.get(id, {}) as Dictionary):    # the nearest deck now shown on the relay
					var sw: Vector3 = last_swing[id][ci]
					var gap := INF
					var far := Vector3.ZERO
					for o in edges:
						if not view.is_edge_open(int(o)):
							continue
						var tip := Vector3.ZERO
						var fd := -1.0
						for d in vis["edge_decks"][int(o)]:
							var dd := ((d as Node3D).position - c).length()
							if dd > fd:
								fd = dd
								tip = (d as Node3D).position
						if (sw - tip).length() < gap:
							gap = (sw - tip).length()
							far = tip
					if gap == INF:
						continue
					stats["_landing_max"] = maxf(float(stats.get("_landing_max", 0.0)), gap)
					if gap > 0.5 and not inst.paused:             # offline: the swung deck must land on its bridge
						_bad(stats, "landing", "relay %d edge %d landed %.2f m off (swung end %.1f deg r %.1f, deck end %.1f deg r %.1f)" % [
								id, int(ci), gap, rad_to_deg(atan2(sw.z - c.z, sw.x - c.x)), (sw - c).length(),
								rad_to_deg(atan2(far.z - c.z, far.x - c.x)), (far - c).length()])
			if not view.collapsed.get(id, false):
				for i in edges:
					var open := view.is_edge_open(int(i))
					var decks: Array = vis["edge_decks"][int(i)]
					for k in range(decks.size()):
						var d: Node3D = decks[k]
						var base: Transform3D = vis["edge_base"][int(i)][k]
						if d.visible != open and not _demolished(view, int(i)):
							_bad(stats, "deck_visibility", "relay %d edge %d deck %d visible=%s open=%s" % [id, i, k, d.visible, open])
						if not d.transform.is_equal_approx(base) and (d.transform.origin - base.origin).length() > POS_TOL:
							_bad(stats, "deck_left_moved", "relay %d edge %d deck %d %.2f m off its place (shown=%s)" % [id, i, k,
									(d.transform.origin - base.origin).length(), d.visible])
				if pf != null and acc.has(id):
					var want := -float(acc[id])
					var err := absf(wrapf((pf as Node3D).rotation.y - want, -PI, PI))
					if err > ANG_TOL:
						_bad(stats, "turntable", "relay %d platform at %.3f, want %.3f (off %.3f rad)" % [id, (pf as Node3D).rotation.y, want, err])
		was_moving[id] = moving
		for i in edges:
			for d in vis["edge_decks"][int(i)]:
				prev[(d as Node3D).get_instance_id()] = [(d as Node3D).position, (d as Node3D).rotation.y, (d as Node3D).is_visible_in_tree()]
	for b in MapBatch.verify():
		if "Deck" in str(b) or "Platform" in str(b):
			_bad(stats, "batch", str(b))


func _demolished(view: Sim, i: int) -> bool:
	return view.demolished.has(i)
