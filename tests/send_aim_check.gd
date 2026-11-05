extends Node
## SEND GESTURE check (Daniele, 2026-11-03, relay review item 19). Run WINDOWED as a scene (the camera must project):
##   Godot --path . --resolution 1688x780 --audio-driver Dummy --position -6000,-6000 res://tests/send_aim_check.tscn -- --no-telemetry --mobile
## Drags fired through main._unhandled_input (press on your vat, move, release on open ground):
##  - 20 drags at known screen angles: the order goes to the node this test picks on its own (inside the +-SEND_CONE_DEG
##    cone from the origin's centre, reachable, nearest to the finger); a cone with no node fails as "no_target";
##  - release inside the dead zone = no order; a quick flick sends; dragged out and back onto the origin = HOLD (the
##    queued units stop, the line already out walks on); every failure lands in the send_failed device file;
##  - the live target ring is at least Rules.SEND_RING_PT (>= 33 pt) across on screen along both axes, every node.
## Exit code 0 = all passed.

const MAIN := "res://main.tscn"
const MAPS := ["res://maps4/A-01-orbital-nexus.json", "res://maps4/C-01-meridian-rotunda.json"]
const OFFSETS := [0.0, 18.0, -22.0, 9.0, -12.0, 26.0]   # degrees off the node's own bearing
var failures := 0
var m: Node
var drags := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	m._unhandled_input(e)


func _drag(a: Vector2, b: Vector2) -> void:
	m._tap_node = -1
	_mouse(a, true)
	var mv := InputEventMouseMotion.new()
	mv.position = b
	m._unhandled_input(mv)
	_mouse(b, false)


func _sent_to(from: int) -> int:
	## The node the vat's new order goes to (-1: no order), then the order is wiped for the next drag.
	var st: Dictionary = m.sim.nodes[from]["streaming"]
	if st.is_empty():
		return -1
	var h: Dictionary = m.sim._horde(int(st["hid"]))
	var to: int = int(h["route"][-1]) if not h.is_empty() else -1
	m.sim.nodes[from]["streaming"] = {}
	m.sim.hordes.erase(h)
	return to


func _expected(from: int, o: Vector2, dir: Vector2, finger: Vector2) -> int:
	## This test's own pick: the reachable node inside the cone nearest to the finger, -1 when none.
	var best := -1
	var best_d := INF
	for n in m.sim.nodes:
		var id: int = n["id"]
		if id == from or m.sim.collapsed.get(id, false) or n.get("node_kind", "") == "junction":
			continue
		var p: Vector2 = m.cam.unproject_position(n["pos"])
		if rad_to_deg(absf(dir.angle_to(p - o))) > Rules.SEND_CONE_DEG:
			continue
		if m.sim.find_route(from, id).is_empty():
			continue
		if p.distance_to(finger) < best_d:
			best_d = p.distance_to(finger)
			best = id
	return best


func _run() -> void:
	var mobile := "--mobile" in OS.get_cmdline_user_args()
	Telemetry.send_fail_path = OS.get_user_data_dir().path_join("send_aim_check_fails.json")
	if FileAccess.file_exists(Telemetry.send_fail_path):
		DirAccess.remove_absolute(Telemetry.send_fail_path)
	for path in MAPS:
		await _map(path, mobile)
	check(drags >= 20, "%d angle drags fired (>= 20)" % drags)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _map(path: String, mobile: bool) -> void:
	load("res://scripts/main.gd").relaunch = {"faction": "null", "mode": "1v1", "map": path}
	m = (load(MAIN) as PackedScene).instantiate()
	m.mobile = mobile
	get_tree().root.add_child(m)
	await _frames(12)
	m.ais.clear()
	m.paused = false
	print("-- ", path.get_file())
	var cam: Camera3D = m.cam
	var ppt := UiKit.pt_per_px(m.get_viewport().get_visible_rect().size)
	var px_pt := 1.0 / ppt
	for n in m.sim.nodes:
		n["owner"] = m.HUMAN if n["owner"] == "" else n["owner"]
	# the ring: >= SEND_RING_PT across on screen along both axes, at every node
	var worst := INF
	for n in m.sim.nodes:
		if n.get("node_kind", "") == "junction":
			continue
		var c: Vector3 = n["pos"] + Vector3(0, 1.0, 0)
		var r: float = m.ring_radius(n["id"])
		var w := cam.unproject_position(c + cam.global_transform.basis.x * r).distance_to(cam.unproject_position(c - cam.global_transform.basis.x * r))
		var right := cam.global_transform.basis.x
		var fwd := Vector3(right.z, 0.0, -right.x).normalized()
		var h := cam.unproject_position(c + fwd * r).distance_to(cam.unproject_position(c - fwd * r))
		worst = minf(worst, minf(w, h) * ppt)
	check(worst >= 33.0, "ring: narrowest axis over all nodes %.1f pt >= 33 (Rules.SEND_RING_PT %.0f)" % [worst, Rules.SEND_RING_PT])
	var vp := m.get_viewport().get_visible_rect().size
	var made := 0
	for src in m.sim.nodes:
		if made >= 12 or src.get("node_kind", "") == "junction":
			continue
		var from: int = src["id"]
		var o: Vector2 = cam.unproject_position(src["pos"])
		if m.hud.pointer_over_ui(o) or m._node_at(m._ground(o), o) != from:
			continue
		for other in m.sim.nodes:
			if made >= 12:
				break
			var to: int = other["id"]
			if to == from or other.get("node_kind", "") == "junction" or m.sim.find_route(from, to).is_empty():
				continue
			var po: Vector2 = cam.unproject_position(other["pos"])
			var off: float = OFFSETS[made % OFFSETS.size()]
			var dir := (po - o).rotated(deg_to_rad(off)).normalized()
			var finger := o + dir * maxf((po - o).length() * 0.55, 40.0 * px_pt)
			if not Rect2(Vector2.ZERO, vp).has_point(finger) or m._node_at(m._ground(finger), finger) >= 0:
				continue
			var want := _expected(from, o, dir, finger)
			src["units"] = 40.0
			_drag(o, finger)
			var got := _sent_to(from)
			check(got == want and want >= 0, "drag %2d  origin %2d  angle %6.1f deg (bearing to %2d %+5.1f)  expected %2d  actual %2d" \
					% [drags + 1, from, rad_to_deg(dir.angle()), to, off, want, got])
			made += 1
			drags += 1
			await _frames(1)
	# the special gestures, on the first vat that has a free direction
	var from := -1
	for src in m.sim.nodes:
		var o0: Vector2 = cam.unproject_position(src["pos"])
		if src.get("node_kind", "") != "junction" and not m.hud.pointer_over_ui(o0) and m._node_at(m._ground(o0), o0) == src["id"]:
			from = src["id"]
			break
	var o: Vector2 = cam.unproject_position(m.sim.nodes[from]["pos"])
	m.sim.nodes[from]["units"] = 40.0
	var fails_before: int = Telemetry.send_fails.size()
	# dead zone: out 12 pt, slow (the press is older than a flick) -> no order
	m._tap_node = -1
	_mouse(o, true)
	m._press_time -= 1.0
	var dz := o + Vector2(12.0 * px_pt, 0)
	var mv := InputEventMouseMotion.new()
	mv.position = dz
	m._unhandled_input(mv)
	_mouse(dz, false)
	check(_sent_to(from) == -1, "dead zone: a slow release 12 pt from the press places no order")
	# flick: 16 pt, at once -> sends the current share toward the nearest reachable node in that direction
	var tgt := -1
	for other in m.sim.nodes:
		if other["id"] != from and other.get("node_kind", "") != "junction" and not m.sim.find_route(from, other["id"]).is_empty():
			tgt = other["id"]
			break
	var fdir: Vector2 = (cam.unproject_position(m.sim.nodes[tgt]["pos"]) - o).normalized()
	var flick := o + fdir * 16.0 * px_pt
	var fwant := _expected(from, o, fdir, flick)
	await _frames(1)
	_drag(o, flick)
	var fgot := _sent_to(from)
	check(fgot == fwant and fgot >= 0, "flick 16 pt toward %d: sent to %d (expected %d), share %.0f %%" % [tgt, fgot, fwant, m.fraction * 100.0])
	# no node in the cone -> "no_target" logged, no order
	var empty_dir := Vector2.ZERO
	for k in range(36):
		var d := Vector2.RIGHT.rotated(deg_to_rad(k * 10.0))
		var f := o + d * 60.0 * px_pt
		if Rect2(Vector2.ZERO, vp).has_point(f) and m._node_at(m._ground(f), f) < 0 and not m.hud.pointer_over_ui(f) \
				and _cone_empty(from, o, d):
			empty_dir = d
			break
	if empty_dir != Vector2.ZERO:
		await _frames(1)
		_drag(o, o + empty_dir * 60.0 * px_pt)
		check(_sent_to(from) == -1, "empty cone at %.0f deg: no order" % rad_to_deg(empty_dir.angle()))
		var last: Dictionary = Telemetry.send_fails[-1] if Telemetry.send_fails.size() > fails_before else {}
		check(str(last.get("reason", "")) == "no_target", "empty cone: send_failed {reason: %s}" % str(last.get("reason", "-")))
	else:
		print("SKIP  no empty direction on this map")
	# HOLD: a real send, the door has started, then drag out and back onto the origin
	m.sim.nodes[from]["units"] = 40.0
	var h: Dictionary = m.sim.send(from, tgt, 1.0)
	for i in range(10):
		m.sim.step(0.05)                             # some units are out on the deck, the rest still queued
	var out_before: float = h["units"]
	var inside: float = m.sim.nodes[from]["units"]
	var away := o + fdir * 50.0 * px_pt
	m._tap_node = -1
	_mouse(o, true)
	var mv2 := InputEventMouseMotion.new()
	mv2.position = away
	m._unhandled_input(mv2)
	var mv3 := InputEventMouseMotion.new()
	mv3.position = o
	m._unhandled_input(mv3)
	check(m.route_label.visible and m.route_label.text == "HOLD", "back on the origin the ring says %s" % m.route_label.text)
	_mouse(o, false)
	check((m.sim.nodes[from]["streaming"] as Dictionary).is_empty(), "HOLD: the vat stops emitting (queued units stay: %.0f inside)" % inside)
	check(h in m.sim.hordes and is_equal_approx(float(h["units"]), out_before), "HOLD: the %.1f units already on the bridge walk on" % out_before)
	for i in range(10):
		m.sim.step(0.05)
	check(float(m.sim.nodes[from]["units"]) >= inside - 0.01, "HOLD: nothing more leaves the vat")
	# the device file
	var f := FileAccess.get_file_as_string(Telemetry.send_fail_path)
	var arr = JSON.parse_string(f) if f != "" else null
	check(arr is Array and not (arr as Array).is_empty() and str(arr[-1].get("kind", "")) == "send_failed",
			"device file %s holds %d send_failed entries" % [Telemetry.send_fail_path, (arr as Array).size() if arr is Array else 0])
	m.queue_free()
	await _frames(3)


func _cone_empty(from: int, o: Vector2, d: Vector2) -> bool:
	for n in m.sim.nodes:
		if n["id"] == from or n.get("node_kind", "") == "junction":
			continue
		var p: Vector2 = m.cam.unproject_position(n["pos"])
		if rad_to_deg(absf(d.angle_to(p - o))) <= Rules.SEND_CONE_DEG + 2.0:
			return false
	return true
