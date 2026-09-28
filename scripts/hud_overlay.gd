class_name HudOverlay
extends Control
## Structures 2.1 (0.19.0): on-screen overlays drawn over the 3D scene, on a layer over the badges and
## under the panels (added right after SkillDock's target layer in Hud.setup):
##  - the Monster hub's reach ring while LAUNCH is armed (main.monster_from) or being dragged to a
##    target (Daniele: "show the reach ring / highlight while dragging from a hub");
##  - allied halo rings round any node holding allied troops (Sim.halo_tier, GAME-RULES sec11);
##  - the relay-outcome preview while SWITCH is focused / pressed-and-held, and for any relay in its
##    1 s warning (Bypass / Relay Hack targets included) - Daniele: "impossible right now to know in
##    advance what a lot of the buttons do (rotation/switch and even retraction isn't easy to see)";
##  - the Last Stand danger symbols, replacing the falling badge's circle (Hud._badges hides it):
##    a floating pulsing warning sign over the platform's camera-facing rim, the countdown beside it.

var main: Node3D
var sim: Sim
var hud: Hud
var human := "A"
var ui_scale := 1.0
var _t := 0.0
var hover_relay := -1                 # set by Hud while the SWITCH action is hovered / held down
var _relay_ready_prev := {}            # node id -> was it ready last frame (edge-detects "just became ready")
var _relay_cue_count := {}             # node id -> how many times the "double-tap to switch" cue has shown
var _relay_cue_t := {}                 # node id -> seconds left showing that cue
const RELAY_CUE_MAX := 3               # only the first few times (Daniele's ask)
const RELAY_CUE_SECONDS := 4.0


const HALO_WIDTH := [0.0, 3.0, 5.0, 7.0]   # 0.20.13: a touch thicker at tier 1 - it used to read as barely there
const HALO_PAD := [0.0, 4.0, 10.0, 17.0]


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
	for n in sim.nodes:
		var id: int = n["id"]
		if n["relay"] == "" or n["owner"] != human or sim.collapsed.get(id, false):
			continue
		var ready: bool = n["relay_cd"] <= 0.0 and n["relay_phase"] == ""
		var was: bool = _relay_ready_prev.get(id, false)
		if ready and not was and int(_relay_cue_count.get(id, 0)) < RELAY_CUE_MAX:
			_relay_cue_count[id] = int(_relay_cue_count.get(id, 0)) + 1
			_relay_cue_t[id] = RELAY_CUE_SECONDS
		_relay_ready_prev[id] = ready
		if float(_relay_cue_t.get(id, 0.0)) > 0.0:
			_relay_cue_t[id] = maxf(0.0, float(_relay_cue_t[id]) - dt)
	queue_redraw()                    # cheap: a handful of arcs/lines - the danger symbols pulse continuously
	PerfProfile.lap("overlay_sync", _pt)


func _draw() -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	var cam: Camera3D = main.cam
	if cam == null or sim == null or (main._start_fit as Array).is_empty():   # (not before the camera's first fit:
		return                                                               # a tutorial owns a relay from frame 1)
	# (TUTORIAL: each part draws once its lesson is reached - Hud.shows(); outside the tutorial, always)
	if hud.shows("halos"):
		_draw_halos(cam)
	if hud.shows("relay"):
		_draw_relay_cues(cam)
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
	if hud.shows("danger"):
		_draw_danger_symbols(cam)
	PerfProfile.lap("overlay_draw", _pt)


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


# ------------------------------------------------------------------ halos (allied troops stored here)
func _draw_halos(cam: Camera3D) -> void:
	## 0.20.13 (Daniele's 2v2 co-op playtest: "i sent troops to her node and except the count going up i
	## couldn't see any other indicator"): one ring per seat with troops stored here, each in THAT seat's
	## own colour (a single fixed gold ring never said whose troops they were, and read as barely there
	## at tier 1) - stacked outward so more than one ally's rings don't just merge into one blob.
	for n in sim.nodes:
		var id: int = n["id"]
		if sim.collapsed.get(id, false):
			continue
		var allies: Dictionary = n.get("allies", {})
		if allies.is_empty():
			continue
		var ns := _node_screen(id, cam)
		var ring := 0
		for seat in allies:
			var tier := sim.halo_tier(id, str(seat))
			if tier <= 0:
				continue
			draw_arc(ns[0], float(ns[1]) + (HALO_PAD[tier] + ring * 5.0) * ui_scale, 0.0, TAU, 40,
					Color(Rules.seat_color(str(seat)), 0.85), HALO_WIDTH[tier] * ui_scale, true)
			ring += 1


# ------------------------------------------------------------------ relay badge cues (0.19.0, Daniele:
# "add some visibility to the buttons / models of the relays")
func _draw_relay_cues(cam: Camera3D) -> void:
	for n in sim.nodes:
		var id: int = n["id"]
		if n["relay"] == "" or n["owner"] != human or sim.collapsed.get(id, false):
			continue
		var ready: bool = n["relay_cd"] <= 0.0 and n["relay_phase"] == ""
		var ns := _node_screen(id, cam)
		if ready:                                      # a ready glow round the badge's spot (Hud.RELAY_ACCENT)
			var a := 0.5 + 0.5 * sin(_t * 3.0)
			draw_arc(ns[0], float(ns[1]) + 5.0 * ui_scale, 0.0, TAU, 32, Color(Hud.RELAY_ACCENT, 0.55 * a), 2.5 * ui_scale, true)
		if float(_relay_cue_t.get(id, 0.0)) > 0.0:      # the first few times: spell it out
			var txt := "DOUBLE-TAP TO SWITCH"
			var f := int(13 * ui_scale)
			var sz := Hud.UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
			var p: Vector2 = ns[0] + Vector2(-sz.x / 2.0, -float(ns[1]) - 16.0 * ui_scale)
			_label(p, txt, Hud.RELAY_ACCENT, 13)


# ------------------------------------------------------------------ monster launch reach / drag
func _draw_monster_reach(cam: Camera3D, hub: int) -> void:
	if hub < 0 or hub >= sim.nodes.size() or sim.collapsed.get(hub, false):
		return
	var col := Rules.seat_color(human)
	var a := 0.6 + 0.4 * sin(_t * 5.0)
	var hs := _node_screen(hub, cam)
	_ring(hs[0], float(hs[1]) + 6.0 * ui_scale, Color.WHITE, 1.0, true)
	_label((hs[0] as Vector2) + Vector2(0, -float(hs[1]) - 14.0 * ui_scale), "LAUNCH FROM", Color.WHITE, 14)
	for id in sim.monster_reach(hub):
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


# ------------------------------------------------------------------ Last Stand danger symbols
func _draw_danger_symbols(cam: Camera3D) -> void:
	for n in sim.nodes:
		var id: int = n["id"]
		if sim.collapsed.get(id, false) or not sim.is_warned(id):
			continue
		var ns := _node_screen(id, cam)
		var c: Vector2 = ns[0]
		var r: float = float(ns[1])
		# the camera-facing rim, clear of the platform's centre (Daniele: "a symbol of danger floating
		# over the border of the platform in a way it doesn't cover what's going on")
		var p := c + Vector2(0, r * 0.92)
		var pulse := 0.55 + 0.45 * sin(_t * 6.0)
		_warning_glyph(p, r * 0.36, Color(1.0, 0.22 * pulse + 0.1, 0.16 * pulse + 0.08, 1.0))
		var secs := int(ceil(sim.drop_in(id) if sim.v3 else sim.last_stand_warn_t))
		_label(p + Vector2(r * 0.55, -r * 0.12), "%d" % maxi(secs, 0), Color(1, 0.86, 0.82), 20)


func _warning_glyph(c: Vector2, size: float, col: Color) -> void:
	## A triangle with "!" (or a skull-drop glyph), pulsing red - unmistakable without covering the node.
	var h := size * 1.7
	var pts := PackedVector2Array([c + Vector2(0, -h * 0.6), c + Vector2(-size, h * 0.4), c + Vector2(size, h * 0.4)])
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 2.0 * ui_scale, true)
	var f := int(size * 1.3)
	var s := "!"
	var sz := Hud.UI_FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	draw_string(Hud.UI_FONT, c + Vector2(-sz.x / 2.0, h * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color.BLACK)
