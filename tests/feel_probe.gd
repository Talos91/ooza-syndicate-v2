extends Node
## Match-feel probe (2026-09-28, Daniele's phone test: "first interaction with tower lags only on first time you send
## and first time you enter a tower"; "map zoom in Last Stand still slows the game down"). A windowed scene:
##   timeout 120 Godot --path . tests/feel_probe.tscn -- --phase=hitch     (the first send / first node entry)
##   timeout 180 Godot --path . tests/feel_probe.tscn -- --phase=zoom      (the Last Stand camera zoom)
## PHONE profile at 1266x585 (as tests/perf_check.tscn). Headless it prints SKIP and exits 0.
## hitch: A-01 1v1 against the AI; seat A drags (real mouse events through the viewport) from its home to its
##   nearest neighbour at 2.5 s and again at 7 s, and taps its home at 10 s (the inspector); prints the longest frame
##   of the 1 s after each send, each of its lines' first entry into a node (absorb), each capture (own<id>) and the
##   tap, the median frame, and every frame over 34 ms with the script time in it, in ms.
## zoom: Rules.PERF_CHECK_MAP, every seat the AI, fast-forwarded to just before the first Last Stand wave drops; prints
##   the frame time (median / max) and draw calls (max) of the 2 s before the camera zoom and during it.

var main: Node3D
var phase := "hitch"
var t := 0.0
var frames: Array = []          # [t, dt ms, draw calls]
var marks := {}                 # name -> t
var _sent := 0
var _drag_step := -1
var _drag_from := -1
var _drag_to := -1
var _zoom_was := false
var _ended := -1.0
var _last_us := 0
var _tail_us := 0              # set by the last node's _process each frame (see _Tail)
var _head_us := 0
var _added: Array = []          # nodes added since the last frame ("Class:name"), for the spike list
var _added_log := {}            # frame t -> what was added in the frame before it


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.substr(8)
	if DisplayServer.get_name() == "headless":
		print("SKIP feel_probe: needs a window")
		get_tree().quit(0)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1266, 585))
	PerfProfile.force_level("phone")
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("seed_value", 7)
	main.set("mobile", true)
	main.set("ai_level", "Standard")
	if phase == "zoom":
		main.set("map_path", Rules.PERF_CHECK_MAP)
		main.set("demo", true)
		main.set("ff_to", Rules.LAST_STAND_TIME + 2.0)
	else:
		main.set("map_path", "res://maps4/A-01-orbital-nexus.json")
		main.set("demo", true)                        # straight into the match; seat A's AI is dropped below
	add_child(main)
	get_tree().node_added.connect(func(n: Node): _added.append("%s:%s" % [n.get_class(), n.name]))


func _process(dt: float) -> void:
	if main == null or not bool(main.get("started")):
		return
	if main.get_node_or_null("FeelTail") == null:      # the scripts' frame cost: this parent's _process runs first, the
		var tail := _Tail.new()                         # tail (main's last child) after main and all of its children
		tail.name = "FeelTail"
		tail.probe = self
		main.add_child(tail)
	var cpu := (_tail_us - _head_us) / 1000.0 if _tail_us > _head_us else 0.0
	_head_us = Time.get_ticks_usec()
	var now := _head_us                                # real frame time (the engine's delta is smoothed)
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else dt * 1000.0
	_last_us = now
	t += dt
	if ms > 34.0:
		_added_log[t] = _added.slice(0, 12)
	_added = []
	frames.append([t, ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			cpu])
	if phase == "zoom":
		_zoom_phase()
	else:
		_hitch_phase()


# ------------------------------------------------------------------ first send / first entry
func _hitch_phase() -> void:
	var sim: Sim = main.get("sim")
	if t < 0.1:
		main.set("demo", false)
		main.set("ais", (main.get("ais") as Array).filter(func(ai): return str(ai.seat) != "A"))
	if _drag_step < 0 and ((_sent == 0 and t > 2.5) or (_sent == 1 and t > 7.0)):
		_pick_pair(sim)
		_drag_step = 0
	elif _drag_step < 0 and _sent == 2 and t > 10.0:     # a tap on your node: the inspector opens (its first time)
		_pick_pair(sim)
		_drag_to = -1
		_drag_step = 0
	if _drag_step >= 0:
		_drag()
	for h in sim.hordes:
		if h["owner"] == "A" and not marks.has("line%d" % int(h["id"])):
			marks["line%d" % int(h["id"])] = t
		if h["owner"] == "A" and h["state"] == "absorb":
			var k := "entry%d" % int(h["id"])
			if not marks.has(k):
				marks[k] = t
	for n in sim.nodes:
		if n["owner"] == "A" and not marks.has("own%d" % int(n["id"])) and t > 0.5:
			marks["own%d" % int(n["id"])] = t          # a capture (the first frames: the home)
	if t > 20.0:
		var names := marks.keys()
		names.sort_custom(func(a, b): return marks[a] < marks[b])
		print("feel_probe hitch: median frame %.1f ms over %d frames; the first 2 s: max %.1f ms" % [_median(0.0, t), frames.size(), _max_ms(0.0, 2.0)])
		var spikes := frames.filter(func(f): return f[1] > 34.0).map(func(f): return "%.2f:%.0f(scripts %.0f)" % [f[0], f[1], f[3]])
		print("  frames over 34 ms (t:ms): ", " ".join(spikes))
		for k in _added_log:
			print("    %.2f added: %s" % [k, _added_log[k]])
		for k in names:
			print("  %-10s at %5.2f s: max frame %.1f ms in the next 1 s" % [k, marks[k], _max_ms(marks[k] - 0.02, marks[k] + 1.0)])
		get_tree().quit(0)


func _pick_pair(sim: Sim) -> void:
	_drag_from = -1
	for n in sim.nodes:
		if n["owner"] == "A" and (_drag_from < 0 or n["units"] > sim.nodes[_drag_from]["units"]):
			_drag_from = n["id"]
	var best := INF
	for link in sim.adj[_drag_from]:
		var o: Dictionary = sim.nodes[link[0]]
		var d: float = float(o["units"])                   # the weakest neighbour: the line takes it (a capture)
		if o["owner"] != "A" and d < best:
			best = d
			_drag_to = o["id"]
	main.set("fraction", 1.0)
	if _sent == 0:                                     # enough for the line to take the node: a capture to time too
		sim.nodes[_drag_from]["units"] = maxf(float(sim.nodes[_drag_from]["units"]), float(sim.nodes[_drag_to]["units"]) * 3.0 + 60.0)


func _drag() -> void:
	## Real mouse events (press on the home node, move, release on the target): the drag line, the route label and
	## main.node_action("send") all run as for a player.
	var cam: Camera3D = main.get("cam")
	var sim: Sim = main.get("sim")
	var a := cam.unproject_position(sim.nodes[_drag_from]["pos"])
	var b := cam.unproject_position(sim.nodes[_drag_to]["pos"]) if _drag_to >= 0 else a
	var ev: InputEvent
	match _drag_step:
		0:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			mb.position = a
			ev = mb
		1, 2, 3:
			var mm := InputEventMouseMotion.new()
			mm.position = a.lerp(b, _drag_step / 3.0) if _drag_to >= 0 else a
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			ev = mm
		4:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = false
			mb.position = b
			ev = mb
			_sent += 1
			marks[("send%d" % _sent) if _drag_to >= 0 else "tap"] = t
			print("probe send %d -> %d (%s -> %s)" % [_drag_from, _drag_to, a, b])
	get_viewport().push_input(ev, true)                 # (viewport coordinates, as unproject_position gives)
	_drag_step = _drag_step + 1 if _drag_step < 4 else -1


# ------------------------------------------------------------------ Last Stand zoom
func _zoom_phase() -> void:
	var zooming: bool = float(main.get("_zoom_t")) >= 0.0
	if zooming and not _zoom_was:
		marks["zoom"] = t
	if not zooming and _zoom_was:
		marks["zoom_end"] = t
		_ended = t
	_zoom_was = zooming
	if (_ended > 0.0 and t > _ended + 2.0) or t > 60.0:
		if not marks.has("zoom"):
			print("feel_probe zoom: no zoom seen by t=%.1f (sim %.1f)" % [t, float(main.get("sim").get("time"))])
			get_tree().quit(1)
			return
		var z0: float = marks["zoom"]
		var z1: float = marks.get("zoom_end", t)
		for w in [["before (2 s)", z0 - 2.0, z0], ["during %.1f s" % (z1 - z0), z0, z1], ["after (2 s) ", z1, z1 + 2.0]]:
			print("feel_probe zoom: %s  frame median %.1f / max %.1f ms  scripts median %.1f / max %.1f ms  draw calls max %d"
					% [w[0], _median(w[1], w[2]), _max_ms(w[1], w[2]), _median(w[1], w[2], 3), _max_ms(w[1], w[2], 3), _max_dc(w[1], w[2])])
		var hud: Hud = main.get("hud")
		var t0 := Time.get_ticks_usec()
		for i in range(5):
			hud._layout_badges(main.get("cam"))
		print("feel_probe zoom: one full badge layout (Hud._layout_badges) %.1f ms" % ((Time.get_ticks_usec() - t0) / 5000.0))
		get_tree().quit(0)


# ------------------------------------------------------------------ numbers
func _in(t0: float, t1: float) -> Array:
	return frames.filter(func(f): return f[0] > t0 and f[0] <= t1)


func _max_ms(t0: float, t1: float, col := 1) -> float:
	var m := 0.0
	for f in _in(t0, t1):
		m = maxf(m, f[col])
	return m


func _max_dc(t0: float, t1: float) -> int:
	var m := 0
	for f in _in(t0, t1):
		m = maxi(m, int(f[2]))
	return m


func _median(t0: float, t1: float, col := 1) -> float:
	var v: Array = _in(t0, t1).map(func(f): return f[col])
	if v.is_empty():
		return 0.0
	v.sort()
	return v[v.size() / 2]


class _Tail extends Node:
	var probe: Node

	func _process(_dt: float) -> void:
		probe.set("_tail_us", Time.get_ticks_usec())
