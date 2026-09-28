extends Node
## RELAY V2 tap check (Daniele: "the tap target should be both the button or the whole node, as relays activate with
## double tap anyway"). Run WINDOWED as a scene (the camera must project; the Net autoload):
##   Godot --path . --resolution 1688x780 res://tests/relay_tap_check.tscn -- --no-telemetry [--mobile]
## On T-07 (retract, switch, remote relays) and tests/relay_multi.json (many bridges per relay), your seat owning them, clicks through main._unhandled_input:
##  - a double-tap on the relay's BUTTON fires it; so does a double-tap on the node centre, and one tap on each;
##  - a single tap on the button selects the relay node (the inspector opens as for a tap on the node) and fires
##    nothing; the button's tap disc is at least Rules.RELAY_HIT_PT across on a phone (RelayView.hit_disc).
## Exit code 0 = all passed.

const MAIN := "res://main.tscn"
var failures := 0
var m: Node


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		m._unhandled_input(e)


func _reset(id: int) -> void:
	var n: Dictionary = m.sim.nodes[id]
	n["relay_phase"] = ""
	n["relay_cd"] = 0.0
	n["relay_t"] = 0.0
	m._tap_node = -1
	m._pending_inspect = -1
	m.hud.close_inspector()
	await _frames(2)


func _run() -> void:
	var mobile := "--mobile" in OS.get_cmdline_user_args()
	# T-07 (one relay of each kind) and tests/relay_multi.json (a 6-way switch, a rotation turning 3 decks, a 2-bridge
	# retract, a remote driving decks at 2 nodes: no cap on bridges per relay)
	for path in ["res://maps4/T-07-switchyard.json", "res://tests/relay_multi.json"]:
		await _map(path, mobile)
	print("
%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _map(path: String, mobile: bool) -> void:
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": "1v1", "map": path}
	m = (load(MAIN) as PackedScene).instantiate()
	m.mobile = mobile
	get_tree().root.add_child(m)
	await _frames(12)
	m.ais.clear()
	print("-- ", path.get_file())
	var ppt := UiKit.pt_per_px(m.get_viewport().get_visible_rect().size)
	for n in m.sim.nodes:
		if n["relay"] == "":
			continue
		var id: int = n["id"]
		n["owner"] = m.HUMAN
		await _frames(2)
		var cam: Camera3D = m.cam
		var btn: Vector2 = cam.unproject_position(m.vis[id]["relay_button"]["tap"])
		var centre: Vector2 = cam.unproject_position(n["pos"])
		var disc := RelayView.hit_disc(cam, m.sim, m.vis, id, mobile)
		if mobile:
			check(2.0 * float(disc[1]) * ppt >= Rules.RELAY_HIT_PT - 0.01, "%s relay %d: button disc %.1f pt >= %.0f" % [n["relay"], id, 2.0 * float(disc[1]) * ppt, Rules.RELAY_HIT_PT])
		for pair in [["button + button", btn, btn], ["node + node", centre, centre], ["button + node", btn, centre]]:
			await _reset(id)
			_click(pair[1])
			_click(pair[2])
			check(n["relay_phase"] == "warning", "%s relay %d: a double-tap on %s fires it" % [n["relay"], id, pair[0]])
		await _reset(id)
		_click(btn)
		check(m.selected == id and n["relay_phase"] == "", "%s relay %d: one tap on the button selects it, fires nothing" % [n["relay"], id])
		await get_tree().create_timer(0.5).timeout
		m._flush_inspect()
		check(m.hud.inspector_id == id, "%s relay %d: ... and opens its inspector" % [n["relay"], id])
		await _reset(id)
	m.queue_free()
	await _frames(3)
