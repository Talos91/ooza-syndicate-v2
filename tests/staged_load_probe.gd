extends Node
## STAGED LOAD probe (Daniele 2026-09-30: "the vs screen should be the loading, so when you click deploy that's what players
## see until the map is ready, not the frozen deploy screen"). Runs a room's real launch path in this process, windowed:
## the autoload Net hosts a browser room (the owner + AI seats), main opens the lobby, then DEPLOY (Net.start_match) - the
## lobby VERSUS card, the launch, main's online start, the map build, the warm-up - exactly as a player's browser does it,
## with no reload shortcut. It records every frame's wall-clock gap from DEPLOY until the match's VERSUS card has gone and
## prints the load steps (Net.load_marks, ms after DEPLOY), the longest frame gaps (with the steps that fell inside them)
## and a verdict against TARGET_MS (250 ms, the desktop goal).
##   Godot --path . res://tests/staged_load_probe.tscn -- [--probe-map=res://maps4/A-01-orbital-nexus.json] [--probe-mode=2v2]
##       [--window=1280x720] [--runs=2] [--shot=<png>: the card mid-load, its bar part-filled (skews that run's frame times)]
## (--runs: DEPLOY again after LEAVE-and-rehost, so the second run shows a warm cache; the first run is the cold one.)
## Windowed only: headless has no VERSUS card and no drawing to measure.

class Loop:
	extends RefCounted
	var name := ""
	var hub: Dictionary
	var queue: Array = []
	func _init(n: String, h: Dictionary) -> void:
		name = n
		hub = h
		hub[n] = self
	func start(_host, _code) -> void: pass
	func send(remote, data) -> bool:
		if hub.has(str(remote)):
			hub[str(remote)].queue.append({"type": "data", "peer": name, "data": str(data)})
		return true
	func close() -> void: pass
	func closePeer(_remote) -> void: pass
	func poll() -> String:
		var r := JSON.stringify(queue)
		queue = []
		return r

const TARGET_MS := 250.0                           # the goal on desktop: no frame gap longer than this after DEPLOY
var args := {}
var hub := {}
var _recording := false
var _last_us := 0
var _gaps: Array = []                              # [start usec, gap ms]
var _t0 := 0
var _worst_all := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000                       # first in the frame: the gap is the whole previous frame
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		print("staged_load_probe: windowed only")
		get_tree().quit(2)
		return
	if args.has("window"):
		var wh := str(args["window"]).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await get_tree().process_frame                 # (the root is busy setting up its children in _ready)
	var runs := int(args.get("runs", "1"))
	var fails := 0
	for r in range(runs):
		fails += await _run(r + 1)
	print("STAGED LOAD PROBE: %s (worst frame after DEPLOY over %d run(s): %.0f ms, target %.0f ms)" % [
			"PASS" if fails == 0 else "FAIL", runs, _worst_all, TARGET_MS])
	get_tree().quit(0 if fails == 0 else 1)


func _process(_dt: float) -> void:
	if not _recording:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_gaps.append([_last_us, (now - _last_us) / 1000.0])
	_last_us = now


func _run(n: int) -> int:
	var h: Node = Net
	hub = {}
	h.bridge = Loop.new("host", hub)
	h.hosting = true
	h.connected = true
	h.room_code = "PRB%d" % n
	h.mode = str(args.get("probe-mode", "2v2"))
	h.map_path = str(args.get("probe-map", "res://maps4/A-01-orbital-nexus.json"))
	h.preferred_faction = "null"
	h.loadout = {"active": "ghost_line", "map": "relay_hack"}
	h.roster = {1: {"faction": "null", "slot": 0, "colour": "", "loadout": h.loadout}}
	h.room_owner = 1
	h.no_reload = false                            # the real path: whatever the launch does in a browser
	h._fix_colours()
	h.set_ai_fill("Standard")
	_open_main()                                   # main opens the lobby (Net is in a room)
	await _frames(30)                              # the lobby drawn and settled (its warm_art too)
	print("probe run %d: lobby up, can_start=%s, map %s %s" % [n, h.can_start(), h.map_path, h.mode])
	_gaps = []
	_last_us = 0
	_recording = true
	_t0 = Time.get_ticks_usec()
	h.start_match()                                # DEPLOY
	var card_gone_at := -1
	var saw_match_card := false
	var shot_done := false
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var m = get_tree().current_scene
		var card: Node = null
		if m != null and is_instance_valid(m):
			for c in m.get_children():
				if c is VersusScreen:
					card = c
		if card != null:
			saw_match_card = true
			var lp = m.get("load_progress")
			if args.has("shot") and not shot_done and lp != null and float(lp) > 0.3 and float(lp) < 0.7:
				shot_done = true                   # (the read-back costs a frame: only with --shot)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(str(args["shot"]))
				print("screenshot %s at load_progress %.2f" % [args["shot"], float(lp)])
		elif saw_match_card and card_gone_at < 0:
			card_gone_at = Time.get_ticks_usec()
		if card_gone_at > 0 and Time.get_ticks_usec() - card_gone_at > 1000000:   # a second of the battlefield
			break
	_recording = false
	var ok := card_gone_at > 0 and bool(h.started)
	var marks: Array = h.load_marks.duplicate()
	print("---- run %d  load steps (ms after DEPLOY, +ms since the previous step)" % n)
	var prev := _t0
	for mk in marks:
		print("  %-12s %8.0f  (+%.0f)" % [mk[0], (int(mk[1]) - _t0) / 1000.0, (int(mk[1]) - prev) / 1000.0])
		prev = int(mk[1])
	if card_gone_at > 0:
		print("  %-12s %8.0f" % ["card_gone", (card_gone_at - _t0) / 1000.0])
	var sorted := _gaps.duplicate()
	sorted.sort_custom(func(a, b): return a[1] > b[1])
	print("---- run %d  frames recorded %d, longest gaps:" % [n, _gaps.size()])
	var worst := 0.0
	for i in range(mini(8, sorted.size())):
		var g: Array = sorted[i]
		var from_ms := (int(g[0]) - _t0) / 1000.0
		var inside := []
		for mk in marks:
			var t := (int(mk[1]) - int(g[0])) / 1000.0
			if t >= 0.0 and t <= float(g[1]):
				inside.append(mk[0])
		print("  %7.0f ms  at %7.0f ms  %s" % [g[1], from_ms, ", ".join(inside)])
		worst = maxf(worst, float(g[1]))
	var over := sorted.filter(func(g): return float(g[1]) > TARGET_MS).size()
	_worst_all = maxf(_worst_all, worst)
	print("run %d: %s - worst gap %.0f ms, %d gap(s) over %.0f ms, card gone %s, round started %s" % [n, "ok" if ok else "NOT LOADED",
			worst, over, TARGET_MS, "yes" if card_gone_at > 0 else "no", h.started])
	# back to a fresh room for the next run: leave the round the way LEAVE ROOM does (no reload of our own)
	h.no_reload = true
	h.leave()
	var m2 = get_tree().current_scene
	if m2 != null and is_instance_valid(m2):
		m2.queue_free()
	await _frames(10)
	return 0 if ok and over == 0 else 1


func _open_main() -> void:
	## The match scene next to this probe; it is the current scene, so the launch's reload (if any) reloads it, not the probe.
	var m: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame
