class_name HudOverlay
extends Control
## Structures 2.1 (0.19.0): on-screen overlays drawn over the 3D scene, on a layer over the badges and
## under the panels (added right after SkillDock's target layer in Hud.setup):
##  - the Monster hub's reach ring while LAUNCH is armed (main.monster_from) or being dragged to a
##    target (Daniele: "show the reach ring / highlight while dragging from a hub");
##  - the relay-outcome preview while SWITCH is focused / pressed-and-held, and for any relay in its
##    1 s warning (Bypass / Relay Hack targets included) - Daniele: "impossible right now to know in
##    advance what a lot of the buttons do (rotation/switch and even retraction isn't easy to see)";
##  - the aimed route while a send is dragged (Alpha 24).
## OOZE 3.0 (WP4b, Daniele 2026-11-27): the node notices it drew (Last Stand alarm signs, upgrade / relay-ready chips, the
## relay's ready ring and DOUBLE-TAP pill, capture bursts) are on each node's screen now (vat_count.gd).

var main: Node3D
var sim: Sim
var hud: Hud
var human := "A"
var ui_scale := 1.0
var _t := 0.0
var hover_relay := -1                 # set by Hud while the SWITCH action is hovered / held down
var _reach_hub := -1                  # perf pass (audit B2): sim.monster_reach of the shown hub, worked out once per
var _reach_sig := []                   # hub and board (the decks' open states, the fallen nodes), not every frame
var _reach: Array = []
var _lock_id := -2                    # ui-node: the target the ring last locked on, and when (the strike-up flicker)
var _lock_t := 0.0
var route := {}                        # Alpha 24: the drag being aimed (main._route_hud): pts (world), ok, target, monster
var _drew := true                      # the last frame drew something (a frame that draws nothing clears it once)




func setup(m: Node3D, s: Sim, h: Hud, seat: String, scale_ui: float) -> void:
	main = m
	sim = s
	hud = h
	human = seat
	ui_scale = scale_ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func sync(dt: float) -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	_t += dt
	# perf pass (audit B11): redrawn while it shows anything (it pulses), once more to clear, then left alone
	var draws := _draws_something()
	if draws or _drew:
		queue_redraw()
	_drew = draws
	PerfProfile.lap("overlay_sync", _pt)


func _draws_something() -> bool:
	## Would _draw put anything on screen this frame (the monster reach, a relay preview, the aimed route)? A cheap
	## scan: false means the overlay can stay as it is.
	if not route.is_empty():
		return true
	if main.monster_from >= 0 or hover_relay >= 0 or (hud.inspector_id >= 0 and hud.inspector_id < sim.nodes.size() 			and sim.nodes[hud.inspector_id]["structure"] == "monster_hub"):
		return true
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false):
			continue
		if n["relay"] != "" and n["relay_phase"] == "warning":
			return true
	return false


func reach(hub: int) -> Array:
	## sim.monster_reach(hub), again only when the hub or the board's routes changed (a deck opened / closed, a
	## node fell): the ring is drawn every frame while a hub is selected or LAUNCH is armed.
	var sig := [hub, sim.collapsed.size(), sim.demolished.size()]
	for ei in sim.edge_controller:
		sig.append(sim._edge_open(ei))
	if hub != _reach_hub or sig != _reach_sig:
		_reach_hub = hub
		_reach_sig = sig
		_reach = sim.monster_reach(hub)
	return _reach


func _draw() -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	var cam: Camera3D = main.cam
	if cam == null or sim == null or (main._start_fit as Array).is_empty():   # (not before the camera's first fit:
		return                                                               # a tutorial owns a relay from frame 1)
	# (TUTORIAL: each part draws once its lesson is reached - Hud.shows(); outside the tutorial, always)
	# WP4b (Daniele 2026-11-27): the node notices - Last Stand alarm signs, upgrade / relay-ready chips, the relay's ready ring
	# and its DOUBLE-TAP pill, capture bursts - are on each node's screen now (VatCount), not drawn here.
	if hud.shows("monster"):
		var reach_hub: int = main.monster_from
		if reach_hub < 0 and hud.inspector_id >= 0:            # 0.19.2 spec H1: also while the hub is selected
			var isel: Dictionary = sim.nodes[hud.inspector_id]
			if isel["owner"] == human and isel["structure"] == "monster_hub":
				reach_hub = hud.inspector_id
		if reach_hub >= 0:
			_draw_monster_reach(cam, reach_hub)
	if hud.shows("relay"):
		for id in _relay_preview_nodes():
			_draw_relay_preview(cam, id)
	if not route.is_empty():
		_draw_route(cam)
	PerfProfile.lap("overlay_draw", _pt)


# ------------------------------------------------------------------ the aimed route (Alpha 24, round-3 ROUTE FEEDBACK)
func _draw_route(cam: Camera3D) -> void:
	## ui-node (Alpha 24 step 4, the attack direction arrow in Neon Noir): the aimed route as a neon ribbon in your faction
	## accent with lit goo marching to the target and an arrowhead (a dashed red tube when there is no route), the snapped
	## target in a neon hex with turning ticks, the order in a pill above it (ATTACK · 15 UNITS · 15 s / NO ROUTE); dragged
	## back onto your vat, the HOLD ring sits there and says HOLD (CANCEL when nothing is queued). main's 3D line is hidden.
	var s := ui_scale
	var hold := int(route.get("hold", -1))
	if hold >= 0 and hold < sim.nodes.size():
		var hs := _node_screen(hold, cam)
		var hr := _ring_px(hold, cam)
		if _lock_id != -10 - hold:
			_lock_id = -10 - hold
			_lock_t = _t
		NodeNoir.target_hex(self, hs[0], hr, HudNoir.accent, s, _t, "", (_t - _lock_t) / 0.28)
		NodeNoir.pill(self, (hs[0] as Vector2) + Vector2(0, -hr - 16.0 * s), str(route.get("label", "HOLD")), HudNoir.accent,
				Hud.UI_FONT, maxi(int(16 * s), 13), s)
		return
	var ok := bool(route.get("ok", false))
	var col := HudNoir.accent if ok else HudNoir.ENEMY
	var line := PackedVector2Array()
	for q in (route.get("pts", PackedVector3Array()) as PackedVector3Array):
		line.append(cam.unproject_position(q + Vector3(0, 1.0, 0)))
	var target := int(route.get("target", -1))
	var tr := 0.0
	var ts := Vector2.ZERO
	if target >= 0 and target < sim.nodes.size():
		ts = (_node_screen(target, cam)[0]) as Vector2
		tr = _ring_px(target, cam)
	if line.size() >= 2 and tr > 0.0:                # the ribbon stops at the target's ring (the head touches it)
		var cut := PackedVector2Array([line[0]])
		for i in range(1, line.size()):
			if line[i].distance_to(ts) > tr + 2.0 * s:
				cut.append(line[i])
			else:
				var a2: Vector2 = cut[-1]
				var d := (line[i] - a2)
				var t0 := 0.0
				var t1 := 1.0
				for k in range(18):                    # bisect the ring crossing
					var tm := (t0 + t1) / 2.0
					if (a2 + d * tm).distance_to(ts) > tr + 2.0 * s:
						t0 = tm
					else:
						t1 = tm
				cut.append(a2 + d * t0)
				break
		line = cut
	if line.size() >= 2:
		NodeNoir.ribbon(self, line, col, s, _t, ok)
	if tr > 0.0:
		if target != _lock_id:
			_lock_id = target
			_lock_t = _t
		NodeNoir.target_hex(self, ts, tr, col, s, _t, "", (_t - _lock_t) / 0.28)
		var txt := str(route.get("label", ""))
		if txt != "":
			NodeNoir.pill(self, ts + Vector2(0, -tr - 16.0 * s), txt, col, Hud.UI_FONT, maxi(int(15 * s), 13), s,
					HudNoir.INK)


func _ring_px(id: int, cam: Camera3D) -> float:
	## The send ring's radius on screen (main.ring_radius: around the platform, never under Rules.SEND_RING_PT across).
	var c: Vector3 = sim.nodes[id]["pos"]
	var rr: float = main.ring_radius(id) if main.has_method("ring_radius") else Rules.R * 1.15
	return cam.unproject_position(c + cam.global_transform.basis.x * rr).distance_to(cam.unproject_position(c))


# ------------------------------------------------------------------ shared helpers (SkillDock's pattern)
func _node_screen(id: int, cam: Camera3D) -> Array:
	var pos: Vector3 = sim.nodes[id]["pos"]
	var c := cam.unproject_position(pos)
	var r := cam.unproject_position(pos + cam.global_transform.basis.x * Rules.R).distance_to(c)
	return [c, r]


func _deck_pts(ei: int, cam: Camera3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in sim.deck_line(ei):
		out.append(cam.unproject_position(q + Vector3(0, 0.3, 0)))
	return out


func _ring(c: Vector2, r: float, col: Color, a: float, solid: bool) -> void:
	var s := ui_scale
	draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.22 * a), 12.0 * s, true)
	draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.95 if solid else 0.75 + 0.25 * a), 2.5 * s, true)
	for k in range(4):                # four ticks turning round the ring: "tap me" (SkillDock's convention)
		var ang := _t * 1.6 + TAU * k / 4.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (r + 5.0 * s), c + d * (r + 13.0 * s), Color(col, 0.95), 3.0 * s, true)


func _label(at: Vector2, txt: String, col: Color, size_px: int) -> void:
	var f := int(size_px * ui_scale)
	draw_string_outline(Hud.UI_FONT, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, int(4 * ui_scale), Color(0, 0, 0, 0.9))
	draw_string(Hud.UI_FONT, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


# ------------------------------------------------------------------ monster launch reach / drag
func _draw_monster_reach(cam: Camera3D, hub: int) -> void:
	if hub < 0 or hub >= sim.nodes.size() or sim.collapsed.get(hub, false):
		return
	var col := Rules.seat_color(human)
	var a := 0.6 + 0.4 * sin(_t * 5.0)
	var hs := _node_screen(hub, cam)
	_ring(hs[0], float(hs[1]) + 6.0 * ui_scale, Color.WHITE, 1.0, true)
	_label((hs[0] as Vector2) + Vector2(0, -float(hs[1]) - 14.0 * ui_scale), "LAUNCH FROM", Color.WHITE, 14)
	for id in reach(hub):
		var ns := _node_screen(id, cam)
		_ring(ns[0], float(ns[1]) + 6.0 * ui_scale, col, a, false)


# ------------------------------------------------------------------ relay-outcome preview
func _relay_preview_nodes() -> Array:
	## Every relay to preview right now: the one Hud says is focused/held, plus any relay mid-warning
	## (a Bypass / Relay Hack target included - the same preview applies to those, Daniele's ask).
	var out := []
	if hover_relay >= 0 and not sim.collapsed.get(hover_relay, false):
		out.append(hover_relay)
	for n in sim.nodes:
		if n["relay"] != "" and n["relay_phase"] == "warning" and not sim.collapsed.get(n["id"], false) and not n["id"] in out:
			out.append(n["id"])
	return out


func _draw_relay_preview(cam: Camera3D, node_id: int) -> void:
	var n: Dictionary = sim.nodes[node_id]
	if n["relay"] == "":
		return
	var cur: int = n["relay_index"]
	var nxt: int = n["relay_pending"] if n["relay_phase"] != "" else sim.relay_next_index(n)
	if cur == nxt:
		return
	var col := Rules.seat_color(n["owner"]) if n["owner"] != "" else Rules.NEUTRAL
	var any := false
	for i in sim.controlled_edges(node_id):
		if sim.anchor_state(i) != null or sim.is_bypassed(node_id):
			continue                  # Anchor / Aegis hold the deck as it was: nothing changes to preview
		var was: bool = sim._edge_open_at(i, cur)
		var now: bool = sim._edge_open_at(i, nxt)
		if was and not now:
			_dashed_deck(i, cam, Rules.state_color("warn"))          # vanishing: red dashed
			any = true
		elif now and not was:
			_ghost_deck(i, cam, col)                                 # appearing: a ghost in the new state's colour
			any = true
	if any and n["relay"] == "rotation":
		_rotation_arrow(cam, node_id, col)


func _dashed_deck(ei: int, cam: Camera3D, col: Color) -> void:
	var pts := _deck_pts(ei, cam)
	var dash := 11.0 * ui_scale
	var gap := 8.0 * ui_scale
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var t := 0.0
		while t < seg:
			var t2 := minf(t + dash, seg)
			draw_line(a + dir * t, a + dir * t2, col, 4.0 * ui_scale, true)
			t += dash + gap


func _ghost_deck(ei: int, cam: Camera3D, col: Color) -> void:
	var pts := _deck_pts(ei, cam)
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(col, 0.30), 11.0 * ui_scale, true)
	draw_polyline(pts, Color(col, 0.85), 2.0 * ui_scale, true)


func _rotation_arrow(cam: Camera3D, node_id: int, col: Color) -> void:
	## A curved arrow over a rotary hub: which way its open spoke turns.
	var ns := _node_screen(node_id, cam)
	var c: Vector2 = ns[0]
	var r: float = float(ns[1]) + 16.0 * ui_scale
	var a := 0.6 + 0.4 * sin(_t * 4.0)
	var a0 := -0.2
	var a1 := PI * 0.85
	draw_arc(c, r, a0, a1, 24, Color(col, 0.85 * a), 3.0 * ui_scale, true)
	var tip := c + Vector2(cos(a1), sin(a1)) * r
	var tdir := Vector2(-sin(a1), cos(a1))
	var side := tdir.orthogonal()
	draw_line(tip, tip - tdir * 9.0 * ui_scale + side * 6.0 * ui_scale, Color(col, 0.9), 3.0 * ui_scale, true)
	draw_line(tip, tip - tdir * 9.0 * ui_scale - side * 6.0 * ui_scale, Color(col, 0.9), 3.0 * ui_scale, true)
