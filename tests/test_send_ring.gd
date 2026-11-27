extends Node
## LAB6 SEND RING check (scripts/send_ring.gd). Headless, as a scene (main + its camera run):
##   Godot --headless --path . res://tests/test_send_ring.tscn -- --no-telemetry --mobile
## A. geometry: segment hit-testing at several angles / radii (full ring and fans), centre = last used (ALL at start), sizes in pt
##    on 844 x 390 and 812 x 375 (every segment >= 44 pt, the ring inside the safe screen for targets in the pit);
## B. the option: send_ui default "panel" (the real game and the lab default), the card SEND RING offers PANEL / RING;
## C. a real match on the card's map (L11P): with "ring" the HUD send panel is hidden, a drag onto a target opens the ring, the
##    source vat screen shows "-N", each segment's release sends exactly that share through the existing send command (the sim's
##    send event), the centre sends the last pick, a release outside the ring / a cone drag cancels; with "panel" the panel shows
##    and the cone drag still sends.
## Exit code 0 = all passed.

const SR := preload("res://scripts/send_ring.gd")
const LabMenu := preload("res://scripts/lab_menu.gd")
const LabCards := preload("res://scripts/lab_cards.gd")
const MAIN := "res://main.tscn"
const PHONES := [[Vector2(844, 390), 47.0], [Vector2(812, 375), 44.0]]   # landscape pt, notch inset each side
const TAP_R_PT := 53.0      # the tap disc R + 2.5 m at the lab camera (platform ~80 pt across = 7.6 m)
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


func _run() -> void:
	_geometry()
	_option()
	Rules.lab = true                                  # a lab build (the LAB screen's cards)
	await _match("ring")
	await _match("panel")
	Rules.lab = false
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ A
func _geometry() -> void:
	print("-- A geometry")
	var rr := SR.radii(TAP_R_PT, 1.0)
	check(rr.x >= 40.0 and rr.x <= 60.0 and rr.y - rr.x >= 44.0, "radii: centre %.0f pt, outer %.0f pt, band %.0f pt" % [rr.x, rr.y, rr.y - rr.x])
	var b := Rect2(0, 0, 2000, 2000)
	var full := SR.layout(Vector2(1000, 1000), rr.x, rr.y, b, 0.0)
	check(is_equal_approx(float(full["span"]), TAU), "room all round: a full ring")
	var slack := SR.SLACK_PT
	var bad := 0
	var tried := 0
	for l in [full, SR.layout(Vector2(1000, 1000), rr.x, rr.y, Rect2(0, 0, 2000, 1000 + rr.y * 0.5), PI / 2.0),
			SR.layout(Vector2(1000, 60), rr.x, rr.y, Rect2(0, 0, 2000, 2000), 0.0)]:
		var c: Vector2 = l["c"]
		for i in range(4):
			var a := SR.seg_angles(l, i)
			for t in [0.1, 0.5, 0.9]:                 # three angles inside the segment
				var ang := lerpf(a.x, a.y, t)
				for r in [rr.x + 1.0, (rr.x + rr.y) / 2.0, rr.y - 1.0, rr.y + slack - 1.0]:
					tried += 1
					if SR.hit(l, c + Vector2(cos(ang), sin(ang)) * r, slack) != i + 1:
						bad += 1
		tried += 3
		if SR.hit(l, c, slack) != 0 or SR.hit(l, c + Vector2(rr.x - 1.0, 0), slack) != 0:
			bad += 1
		if SR.hit(l, c + Vector2(0, -(rr.y + slack + 1.0)), slack) != -1:
			bad += 1
	check(bad == 0, "hit-test: %d points over full ring + two fans (4 segments x 3 angles x 4 radii, centre, outside), %d wrong" % [tried, bad])
	var fan := SR.layout(Vector2(1000, 60), rr.x, rr.y, Rect2(0, 0, 2000, 2000), 0.0)
	check(float(fan["span"]) < TAU, "near the top edge: a partial ring (span %.0f deg, mid %.0f deg)" % [rad_to_deg(float(fan["span"])), rad_to_deg(float(fan["a0"]) + float(fan["span"]) / 2.0)])
	var gap_a := float(fan["a0"]) + float(fan["span"]) + (TAU - float(fan["span"])) / 2.0
	check(SR.hit(fan, Vector2(1000, 60) + Vector2(cos(gap_a), sin(gap_a)) * (rr.x + 10.0), slack) == 0, "a fan's open side, inside the ring = centre (default)")
	var order := []
	for i in range(4):
		var a := SR.seg_angles(full, i)
		order.append(snappedf(rad_to_deg((a.x + a.y) / 2.0), 1.0))
	check(order == [-135.0, -45.0, 45.0, 135.0], "full ring: 25 upper-left, 50 upper-right, 75 lower-right, ALL lower-left %s" % str(order))
	SR.last_fraction = 1.0
	check(is_equal_approx(SR.fraction_for(0), 1.0), "centre = ALL at match start")
	SR.last_fraction = 0.5
	check(is_equal_approx(SR.fraction_for(0), 0.5) and is_equal_approx(SR.fraction_for(3), 0.75) and SR.fraction_for(-1) == 0.0,
			"centre = last used (50%), segment 3 = 75%, outside = nothing")
	SR.last_fraction = 1.0
	# sizes + on-screen over a grid of target spots in the pit, every onward direction, on both phones (1 px = 1 pt here)
	for ph in PHONES:
		var vp: Vector2 = ph[0]
		var ins: float = ph[1]
		var bounds := Rect2(Vector2(ins, 0), vp - Vector2(ins * 2.0, 0)).grow(-SR.EDGE_PT)
		var sw := vp.x - ins * 2.0
		var mx := maxf(0.1125 * sw, 88.0)
		var pit := Rect2(Vector2(ins + mx, 66.0), Vector2(sw - 2.0 * mx, vp.y - 66.0 - 16.0))
		var worst := INF
		var worst_depth := INF
		var off := 0
		var n := 0
		var spans := {}
		for gx in range(9):
			for gy in range(6):
				var c := pit.position + pit.size * Vector2(gx / 8.0, gy / 5.0)
				for k in range(8):
					var l := SR.layout(c, rr.x, rr.y, bounds, TAU * k / 8.0)
					var sz := SR.seg_size_pt(l, 1.0)
					worst = minf(worst, sz["chord"])
					worst_depth = minf(worst_depth, sz["depth"])
					spans[int(round(rad_to_deg(float(l["span"]))))] = true
					n += 1
					if SR._arc_margin(c, rr.y, float(l["a0"]), float(l["span"]), bounds) < 0.0:
						off += 1
		check(worst >= 44.0 and worst_depth >= 44.0, "%dx%d: segment >= 44 pt: narrowest across %.1f pt, depth %.1f pt (%d layouts, spans %s deg)" % [vp.x, vp.y, worst, worst_depth, n, str(spans.keys())])
		check(off == 0, "%dx%d: ring inside the safe screen for every target in the pit (%d of %d off)" % [vp.x, vp.y, off, n])


# ------------------------------------------------------------------ B
func _option() -> void:
	print("-- B option")
	Rules.lab = false
	check(str(Rules.lab_opt("send_ui")) == "panel" and not SR.on(), "real game (lab off): send_ui = panel, no ring")
	Rules.lab = true
	check(str(Rules.lab_opts.get("send_ui")) == "panel" and not SR.on(), "lab default: send_ui = panel")
	var card := LabCards.find("send-ring")
	check(not card.is_empty() and str(card["map"]) == "L11P" and (card["choices"][0]["values"] as Array) == ["panel", "ring"],
			"card SEND RING on L11P, choices PANEL / RING")
	LabMenu.picks["send-ring"] = {"send_ui": 0}
	LabMenu.apply_card(card)
	check(not SR.on(), "card pick PANEL: panel")
	LabMenu.picks["send-ring"] = {"send_ui": 1}
	LabMenu.apply_card(card)
	check(SR.on() and LabMenu.pick_tag(card) == "RING", "card pick RING: ring (tag %s)" % LabMenu.pick_tag(card))
	LabMenu.reset_card()
	check(not SR.on(), "back on the LAB screen: panel again")
	Rules.lab = false


# ------------------------------------------------------------------ C
func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	m._unhandled_input(e)


func _move(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	m._unhandled_input(mv)


func _sends() -> Array:
	return m.sim.events.filter(func(e): return e.get("type", "") == "send")


func _clear_order(from: int) -> void:
	var st: Dictionary = m.sim.nodes[from]["streaming"]
	if not st.is_empty():
		m.sim.hordes.erase(m.sim._horde(int(st["hid"])))
		m.sim.nodes[from]["streaming"] = {}


func _open_spot(p: Vector2, r: float) -> Vector2:
	## A screen point r from p on open ground (no node, no HUD), or p when none.
	for k in range(24):
		var q := p + Vector2.RIGHT.rotated(TAU * k / 24.0) * r
		var vp: Vector2 = m.get_viewport().get_visible_rect().size
		if Rect2(Vector2.ZERO, vp).has_point(q) and m._node_at(m._ground(q), q) < 0 and not m.hud.pointer_over_ui(q):
			return q
	return p


func _match(mode: String) -> void:
	print("-- C match, send_ui ", mode)
	var card := LabCards.find("send-ring")
	LabMenu.picks["send-ring"] = {"send_ui": 0 if mode == "panel" else 1}
	LabMenu.apply_card(card)
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "mode": "1v1", "map": LabCards.map_path("L11P")}
	m = (load(MAIN) as PackedScene).instantiate()
	m.mobile = true
	get_tree().root.add_child(m)
	await _frames(12)
	m.ais.clear()
	m.paused = false
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var ppt := UiKit.pt_per_px(vp)
	print("viewport %s px, %.3f pt/px" % [str(vp), ppt])
	var ring: bool = mode == "ring"
	check(m.hud.side_panel.visible == (not ring), "HUD send panel %s" % ("hidden" if ring else "shown"))
	check((m.send_ring != null) == ring, "send ring %s" % ("made" if ring else "not made"))
	# a source of ours with units and a reachable target, both on open screen
	for n in m.sim.nodes:                               # (as send_aim_check: the neutrals are ours, so a source sits on screen)
		n["owner"] = m.HUMAN if n["owner"] == "" else n["owner"]
	var cam: Camera3D = m.cam
	var from := -1
	var to := -1
	for n in m.sim.nodes:
		if n["owner"] != m.HUMAN or n.get("node_kind", "") == "junction":
			continue
		var o := cam.unproject_position(n["pos"])
		if not Rect2(Vector2.ZERO, vp).grow(-60.0).has_point(o) or m.hud.pointer_over_ui(o) or m._node_at(m._ground(o), o) != n["id"]:
			continue
		for t in m.sim.nodes:
			if t["id"] == n["id"] or t.get("node_kind", "") == "junction" or m.sim.find_route(n["id"], t["id"]).is_empty():
				continue
			var p := cam.unproject_position(t["pos"])
			if not Rect2(Vector2.ZERO, vp).grow(-60.0).has_point(p) or m.hud.pointer_over_ui(p) or m._node_at(m._ground(p), p) != t["id"] or p.distance_to(o) < 120.0 / ppt:
				continue
			from = n["id"]
			to = t["id"]
			break
		if from >= 0:
			break
	check(from >= 0, "a source %d and a reachable target %d on screen" % [from, to])
	if from < 0:
		m.queue_free()
		await _frames(2)
		return
	m.sim.nodes[from]["units"] = 400.0                   # 80 shown: every share sends something
	var o := cam.unproject_position(m.sim.nodes[from]["pos"])
	var p := cam.unproject_position(m.sim.nodes[to]["pos"])
	var before := _sends().size()
	if ring:
		SR.last_fraction = 1.0
		# centre at match start = ALL
		m._tap_node = -1
		_mouse(o, true)
		_move(o.lerp(p, 0.5))
		_move(p)
		check(m.send_ring.is_open() and m.send_ring.target == to and m.send_ring.pick == 0, "drag onto the target opens the ring, centre picked")
		var vc = m.vat_count
		check(vc != null and str(vc.override.get(from, "")) == "-80", "source vat screen shows %s (want -80)" % (str(vc.override.get(from, "")) if vc else "no vat screens"))
		var sz := SR.seg_size_pt(m.send_ring.lay, ppt)
		print("live ring at %s: span %.0f deg, segment depth %.1f pt, across %.1f pt" % [str(p), rad_to_deg(float(m.send_ring.lay["span"])), sz["depth"], sz["chord"]])
		check(sz["min"] >= 44.0, "live ring segment >= 44 pt (%.1f)" % sz["min"])
		check(m.send_ring.bubble_rect().position.y + m.send_ring.bubble_rect().size.y <= p.y - 30.0 / ppt or
				absf(m.send_ring.bubble_rect().get_center().x - p.x) > 60.0 / ppt, "the pick label sits clear of the finger")
		_mouse(p, false)
		var s := _sends()
		check(s.size() == before + 1 and int(s[-1]["to"]) == to and is_equal_approx(float(s[-1]["units"]), 400.0),
				"centre release: ALL (400 sim units) to the target")
		check(vc == null or not vc.override.has(from), "vat screen back to its count after the release")
		_clear_order(from)
		# each segment: the share sent = the pick; then the centre sends that last pick
		for i in range(4):
			var l: Dictionary = m.send_ring.lay if m.send_ring.is_open() else {}
			m._tap_node = -1
			_mouse(o, true)
			_move(o.lerp(p, 0.5))
			_move(p)
			l = m.send_ring.lay
			var a := SR.seg_angles(l, i)
			var sp: Vector2 = l["c"]
			for t in [0.5, 0.3, 0.7, 0.15, 0.85]:     # a spot in the segment off any other node's middle (TAKEOVER_PT)
				var ang := lerpf(a.x, a.y, t)
				var q: Vector2 = (l["c"] as Vector2) + Vector2(cos(ang), sin(ang)) * (float(l["r_in"]) + float(l["r_out"])) / 2.0
				var clear := true
				for nn in m.sim.nodes:
					if nn["id"] != to and cam.unproject_position(nn["pos"]).distance_to(q) * ppt <= SR.TAKEOVER_PT + 2.0:
						clear = false
				if clear and sp == (l["c"] as Vector2):
					sp = q
			_move(sp)
			var f: float = SR.FRACTIONS[i]
			check(m.send_ring.pick == i + 1 and str(vc.override.get(from, "")) == "-%d" % Rules.shown(floorf(400.0 * f)),
					"segment %s: picked, vat shows %s" % [SR.NAMES[i], str(vc.override.get(from, ""))])
			var n0 := _sends().size()
			_mouse(sp, false)
			s = _sends()
			check(s.size() == n0 + 1 and is_equal_approx(float(s[-1]["units"]), floorf(400.0 * f)),
					"segment %s release sends %.0f (= 400 x %.2f)" % [SR.NAMES[i], float(s[-1]["units"]) if s.size() > n0 else -1.0, f])
			_clear_order(from)
		SR.last_fraction = 0.5
		m._tap_node = -1
		_mouse(o, true)
		_move(o.lerp(p, 0.5))
		_move(p)
		var n1 := _sends().size()
		_mouse(p, false)
		s = _sends()
		check(s.size() == n1 + 1 and is_equal_approx(float(s[-1]["units"]), 200.0), "centre after a 50% pick sends the last used (200)")
		_clear_order(from)
		# release outside the ring = cancel
		m._tap_node = -1
		_mouse(o, true)
		_move(o.lerp(p, 0.5))
		_move(p)
		var away := _open_spot(p, float(m.send_ring.lay["r_out"]) + (SR.SLACK_PT + 30.0) / ppt)
		_move(away)
		var n2 := _sends().size()
		_mouse(away, false)
		check(_sends().size() == n2, "release outside the ring at %s, off any node: cancelled (%d new sends)" % [str(away), _sends().size() - n2])
		check(not m.send_ring.is_open() and not vc.override.has(from), "ring closed, vat count back")
	# a cone drag (toward the target, never onto it): ring = cancel, panel = today's send
	var cone := o
	for k in range(13):                                 # toward the target, never on a node: a spot along a slightly turned line
		for t in [0.3, 0.4, 0.5]:
			var q: Vector2 = o + (p - o).rotated(deg_to_rad(float(k - 6) * 4.0)) * t
			if cone == o and m._node_at(m._ground(q), q) < 0 and not m.hud.pointer_over_ui(q) and (q - o).length() * ppt > 40.0:
				cone = q
	m._tap_node = -1
	var n3 := _sends().size()
	_mouse(o, true)
	_move(cone)
	var cone_under: int = m._node_at(m._ground(cone), cone)
	var cone_aim: Dictionary = m._send_aim(from, cone)
	_mouse(cone, false)
	if cone_under < 0 and cone != o and str(cone_aim.get("kind")) == "send":   # today this cone drag would send
		check((_sends().size() - n3) == (0 if ring else 1), "cone drag (no node under the finger): %s" % ("cancelled" if ring else "sends (today)"))
		if not ring:
			check(is_equal_approx(float(_sends()[-1]["units"]) if _sends().size() > n3 else -1.0, floorf(400.0 * m.fraction)),
					"panel: the send uses the panel's share (%.2f)" % m.fraction)
	else:
		print("SKIP  cone drag: no open spot toward the target (aim %s)" % str(cone_aim))
	m.queue_free()
	await _frames(3)
	LabMenu.reset_card()
