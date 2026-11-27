extends Control
## LAB 6 SEND RING (Daniele 2026-11-27, "love this send to lab for test"): how many units go is picked INSIDE the send gesture,
## not on the HUD send panel. Drag from your node to the target as today; when the finger reaches the target's tap area a ring
## opens round it, split into 25 / 50 / 75 / ALL. Let go in the centre = the default (ALL at match start, then whatever you
## picked last); slide out onto a segment = that share. Let go anywhere else = cancel (no cone pick, no flick send in this mode).
## The share about to leave shows live on the ring (centre "-24" + the pick above the ring, clear of the finger) and on the
## SOURCE vat's screen (VatCount.override). Lab option send_ui = "panel" (today, default) / "ring" (card SEND RING).
##
## Only a VIEW + input filter: the release goes through main's existing send path (node_action "send", {to, fraction}) - the same
## sim command the panel's fraction feeds, so AI, online and replays are untouched. There are no multi-source sends in the game
## (a send always has one origin), so there is nothing to share across sources.
##
## LOOK: the in-match radial's ring geometry (Hud.ActionWedge, GMN-1 ROUND: slices of a round ring, smoked glass, the neon tube on
## the outer edge in the player's seat colour) drawn with the same NodeNoir.glass / NodeNoir.neon helpers its fallback path uses.
## The lab HUD's textured slices (HudLab.draw_slice) only come at 40 / 50 deg, so the 45 / 67.5 / 90 deg segments here are drawn.
##
## SIZES (pt; px = pt / UiKit.pt_per_px): the centre zone covers the target's tap disc (40..60 pt radius), each segment is BAND_PT
## deep (>= 44 pt touch) and, for the narrowest layout (a 135 deg fan, 4 x 33.75 deg), >= 44 pt across at its middle. The ring
## stays inside the safe screen: a full ring when it fits, else a 3/4 ring, else a half-ring / 135 deg fan turned away from the edges
## (the direction closest to "onward", away from the source). Hit-testing allows SLACK_PT past the outer edge.
##
## Another reachable node under the finger moves the ring there (a drag passing over a node on its way): with the ring open,
## only when the finger is within TAKEOVER_PT of that node's centre, so a segment lying over a neighbour's tap disc still picks.
##
## main.gd hooks (marked "LAB6 SEND RING"): created in _start_map when on(); filter_aim() in _draw_drag and at the release; end()
## in _end_drag. Hud.shows("send_panel") is false when on(). VatCount.override carries the "-24".

const FRACTIONS := [0.25, 0.5, 0.75, 1.0]
const NAMES := ["25%", "50%", "75%", "ALL"]
const CENTRE_MIN_PT := 40.0      # centre zone radius: at least this, at most CENTRE_MAX_PT (covers the target's tap disc)
const CENTRE_MAX_PT := 60.0
const BAND_PT := 52.0            # segment depth, ring inner -> outer edge (>= 44 pt touch)
const SLACK_PT := 18.0           # past the outer edge still picks the segment (an overshooting finger)
const TAKEOVER_PT := 28.0       # with a ring open, another node takes it over only this near its centre (passing through)
const EDGE_PT := 4.0             # kept clear of the safe screen edge
const GAP_PT := 3.0              # the dark seam between segments
const LABEL_PT := 16.0
const BUBBLE_PT := 18.0
const FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")

static var last_fraction := 1.0  # the centre's share: ALL at match start (setup), then the last segment picked

var main: Node
var from := -1                   # the drag's origin (-1: no drag)
var target := -1                 # the node the ring is open on (-1: closed)
var lay := {}                    # layout(): {"c", "r_in", "r_out", "a0", "span"} in px
var pick := -1                   # -1 outside (cancel), 0 centre (last_fraction), 1..4 = FRACTIONS[pick - 1]
var bounds := Rect2()            # the safe screen in px the ring keeps inside
var ppx := 1.0                   # px per pt
var _t := 0.0


static func on() -> bool:
	return str(Rules.lab_opt("send_ui")) == "ring"


func setup(m: Node) -> void:
	main = m
	name = "SendRing"
	last_fraction = 1.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ pure geometry (tests/test_send_ring.gd)
static func seg_angles(l: Dictionary, i: int) -> Vector2:
	## Segment i (0..3) as [a0, a1] radians, screen space (0 = right, + = clockwise).
	var w: float = float(l["span"]) / 4.0
	return Vector2(float(l["a0"]) + w * i, float(l["a0"]) + w * (i + 1))


static func _arc_margin(c: Vector2, r: float, a0: float, span: float, b: Rect2) -> float:
	## The smallest distance from the outer arc (and the label ring) to the bounds' edges; < 0 = it crosses an edge.
	var steps := maxi(8, int(ceil(span / deg_to_rad(5.0))))
	var worst := INF
	for k in range(steps + 1):
		var a := a0 + span * float(k) / steps
		var p := c + Vector2(cos(a), sin(a)) * r
		worst = minf(worst, minf(minf(p.x - b.position.x, b.end.x - p.x), minf(p.y - b.position.y, b.end.y - p.y)))
	return worst


static func layout(c: Vector2, r_in: float, r_out: float, b: Rect2, prefer: float) -> Dictionary:
	## The ring round screen point c: a full ring when it fits inside b, else a 3/4 ring, else a half-ring fan, else a 135 deg
	## fan (a pit corner); a partial ring turns to the fitting direction closest to `prefer` (radians; onward = away from the
	## source). Nothing fits: the 135 deg fan with the most room.
	var l := {"c": c, "r_in": r_in, "r_out": r_out, "a0": -PI, "span": TAU}
	if _arc_margin(c, r_out, -PI, TAU, b) >= 0.0:
		return l
	var best_span := PI * 0.75
	var best_a0 := prefer - PI / 2.0
	var best_m := -INF
	for span: float in [PI * 1.5, PI, PI * 0.75]:
		var found := false
		var best_off := INF
		for k in range(48):                           # 7.5 deg steps
			var d := float(k) * TAU / 48.0
			var a0 := d - span / 2.0
			var mg := _arc_margin(c, r_out, a0, span, b)
			if mg >= 0.0:
				var off := absf(angle_difference(d, prefer))
				if off < best_off:
					best_off = off
					l["a0"] = a0
					l["span"] = span
					found = true
			elif span == PI * 0.75 and mg > best_m:
				best_m = mg
				best_a0 = a0
		if found:
			return l
	l["a0"] = best_a0
	l["span"] = best_span
	return l


static func hit(l: Dictionary, p: Vector2, slack: float) -> int:
	## -1 = outside (a release cancels), 0 = the centre or a fan's open side (the default share), 1..4 = a segment.
	var v: Vector2 = p - (l["c"] as Vector2)
	var r := v.length()
	if r <= float(l["r_in"]):
		return 0
	if r > float(l["r_out"]) + slack:
		return -1
	var span: float = l["span"]
	var rel := wrapf(v.angle() - float(l["a0"]), 0.0, TAU)
	if rel >= span - 0.0001 and span < TAU - 0.001:
		return 0                                      # a fan's open side, inside the ring's reach: still the default
	return 1 + mini(3, int(rel / (span / 4.0)))


static func fraction_for(p: int) -> float:
	if p == 0:
		return last_fraction
	if p >= 1 and p <= 4:
		return FRACTIONS[p - 1]
	return 0.0


static func seg_size_pt(l: Dictionary, pt_px: float) -> Dictionary:
	## A segment's touch size in pt: depth (inner -> outer edge) and the chord across its middle radius.
	var r_mid := (float(l["r_in"]) + float(l["r_out"])) / 2.0
	var w: float = float(l["span"]) / 4.0
	var depth := (float(l["r_out"]) - float(l["r_in"])) * pt_px
	var chord := 2.0 * r_mid * sin(w / 2.0) * pt_px
	return {"depth": depth, "chord": chord, "min": minf(depth, chord)}


static func radii(tap_r_px: float, ppx_: float) -> Vector2:
	## (r_in, r_out) in px: the centre covers the target's tap disc (40..60 pt), BAND_PT of segment outside it.
	var r_in := clampf(tap_r_px + 4.0 * ppx_, CENTRE_MIN_PT * ppx_, CENTRE_MAX_PT * ppx_)
	return Vector2(r_in, r_in + BAND_PT * ppx_)


# ------------------------------------------------------------------ the gesture (main.gd hooks)
func is_open() -> bool:
	return target >= 0


func fraction_now() -> float:
	return fraction_for(pick)


func filter_aim(aim: Dictionary, f: int, screen: Vector2, release := false) -> Dictionary:
	## main._send_aim's answer, seen through the ring: ring open + finger inside it = a send to the ring's target with the
	## picked share ({"fraction"}); a send the ring did not give (cone pick, flick) = cancel; hold / fail / cancel unchanged.
	track(f, screen)
	if target >= 0 and pick >= 0:
		var out := {"kind": "send", "to": target, "fraction": fraction_now(), "ring": pick}
		if release and pick >= 1:
			last_fraction = FRACTIONS[pick - 1]
		return out
	if str(aim.get("kind", "")) == "send":
		return {"kind": "cancel", "ring_cancel": true}
	return aim


func track(f: int, screen: Vector2) -> void:
	## The finger moved: keep the ring on its target while the finger is inside it, else close it and open one on the node
	## under the finger (reachable, not the origin).
	from = f
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(844, 390)
	ppx = 1.0 / maxf(UiKit.pt_per_px(vp), 0.01)
	var ins := UiKit.safe_insets(vp)
	bounds = Rect2(Vector2(ins.x, ins.y), vp - Vector2(ins.x + ins.z, ins.y + ins.w)).grow(-EDGE_PT * ppx)
	var under: int = main._node_at(main._ground(screen), screen)
	if under >= 0 and (under == f or under == target or main.sim.find_route(f, under).is_empty()):
		under = -1                                    # only ANOTHER reachable node takes the ring away,
	if under >= 0 and target >= 0 and 			screen.distance_to(main.cam.unproject_position(main.sim.nodes[under]["pos"])) > TAKEOVER_PT * ppx:
		under = -1                                    # and with the ring open only near its middle (a segment may lie on its disc)
	if target >= 0:
		var old := pick
		pick = hit(lay, screen, SLACK_PT * ppx)
		if pick >= 0 and under < 0 and not main.sim.collapsed.get(target, false):
			if pick != old:
				_sync()
			return
		_close()
	if under < 0:
		return
	var c: Vector2 = main.cam.unproject_position(main.sim.nodes[under]["pos"])
	var rr := radii(_tap_r_px(under), ppx)
	var o: Vector2 = main.cam.unproject_position(main.sim.nodes[f]["pos"])
	lay = layout(c, rr.x, rr.y, bounds, (c - o).angle())
	target = under
	pick = hit(lay, screen, SLACK_PT * ppx)
	if pick < 0:                                      # opened by a badge far off the disc: the default share
		pick = 0
	_sync()


func end() -> void:
	## The gesture is over (sent, cancelled, lost).
	_close()
	from = -1


func _close() -> void:
	target = -1
	pick = -1
	lay = {}
	_sync()


func _tap_r_px(id: int) -> float:
	## main._node_at's tap disc (R + 2.5 m on a phone) on screen: its longer axis, so a finger entering it lands in the centre.
	var cam: Camera3D = main.cam
	var c: Vector3 = main.sim.nodes[id]["pos"]
	var m: float = Rules.R + (2.5 if main.mobile else 1.0)
	var p0 := cam.unproject_position(c)
	var right := cam.global_transform.basis.x
	var fwd := Vector3(right.z, 0.0, -right.x).normalized()
	return maxf(cam.unproject_position(c + right * m).distance_to(p0), cam.unproject_position(c + fwd * m).distance_to(p0))


func leaving() -> int:
	## The units this release would send, shown (Alpha 11 scale) - the main label's own count.
	if from < 0 or target < 0 or pick < 0:
		return 0
	return Rules.shown(int(floorf(float(main.sim.nodes[from]["units"]) * fraction_now())))


func _sync() -> void:
	## The source vat's screen shows the number about to leave while the ring is open (a release here sends), else its count.
	var vc = main.get("vat_count") if main else null
	if vc != null and "override" in vc:
		(vc.override as Dictionary).clear()
		if from >= 0 and target >= 0 and pick >= 0:
			vc.override[from] = "-%d" % leaving()
		vc.sync()
	queue_redraw()


func _process(dt: float) -> void:
	if target < 0:
		return
	_t += dt
	if _t >= 0.1:                                     # the vat still fills while you hold: the "-24" follows (10 Hz)
		_t = 0.0
		_sync()


# ------------------------------------------------------------------ drawing
func _slice(c: Vector2, ri: float, ro: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(4, int(ceil((a1 - a0) / deg_to_rad(5.0))))
	for k in range(steps + 1):
		var a := lerpf(a0, a1, float(k) / steps)
		pts.append(c + Vector2(cos(a), sin(a)) * ro)
	for k in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(k) / steps)
		pts.append(c + Vector2(cos(a), sin(a)) * ri)
	return pts


func _arc(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(4, int(ceil((a1 - a0) / deg_to_rad(5.0))))
	for k in range(steps + 1):
		var a := lerpf(a0, a1, float(k) / steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _text(p: Vector2, s: String, size_pt: float, col: Color) -> void:
	var fs := int(round(size_pt * ppx))
	var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := FONT.get_ascent(fs)
	var desc := FONT.get_descent(fs)
	var at := p + Vector2(-w / 2.0, (asc - desc) / 2.0)
	draw_string_outline(FONT, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.22)), Color(0, 0, 0, 0.85))
	draw_string(FONT, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	if target < 0 or lay.is_empty():
		return
	var accent := Rules.seat_color(main.HUMAN)
	var c: Vector2 = lay["c"]
	var ri: float = lay["r_in"]
	var ro: float = lay["r_out"]
	var gap := GAP_PT * ppx / ((ri + ro) / 2.0)        # the seam, radians at the middle radius
	var units: float = float(main.sim.nodes[from]["units"]) if from >= 0 else 0.0
	for i in range(4):
		var a := seg_angles(lay, i)
		var on_it := pick == i + 1
		var poly := _slice(c, ri, ro, a.x + gap / 2.0, a.y - gap / 2.0)
		NodeNoir.glass(self, poly, 0.9, Color(accent, 0.28 if on_it else 0.0))
		if on_it:                                     # the picked slice: lit, the accent glowing up to its rim
			var gc := PackedColorArray()
			for q in poly:
				var u := clampf(((q - c).length() - ri) / maxf(ro - ri, 1.0), 0.0, 1.0)
				gc.append(Color(accent.darkened(0.5).lerp(accent, u), 0.2 + 0.3 * u))
			draw_polygon(NodeNoir.clean(poly), gc)
		var edge := poly.duplicate()
		edge.append(poly[0])
		draw_polyline(edge, Color(accent, 0.3), 1.0 * ppx, true)
		NodeNoir.neon(self, _arc(c, ro - 1.5 * ppx, a.x + gap / 2.0, a.y - gap / 2.0), accent, (3.0 if on_it else 2.0) * ppx,
				0.9 if on_it else 0.25)
		var m := (a.x + a.y) / 2.0
		var lp := c + Vector2(cos(m), sin(m)) * (ri + ro) / 2.0
		var n := Rules.shown(int(floorf(units * FRACTIONS[i])))
		_text(lp + Vector2(0, -7.0 * ppx), NAMES[i], LABEL_PT, Color.WHITE if on_it else Color(1, 1, 1, 0.8))
		_text(lp + Vector2(0, 9.0 * ppx), "-%d" % n, LABEL_PT * 0.75, accent.lerp(Color.WHITE, 0.5 if on_it else 0.2))
	# the centre: its own ring (the default share's zone) and the count about to leave, on the target
	NodeNoir.neon(self, _arc(c, ri, 0.0, TAU), accent, (2.5 if pick == 0 else 1.5) * ppx, 0.9 if pick == 0 else 0.3)
	_text(c + Vector2(0, -8.0 * ppx), "-%d" % leaving(), BUBBLE_PT, accent.lerp(Color.WHITE, 0.45))
	_text(c + Vector2(0, 10.0 * ppx), _share_name(fraction_for(0)) if pick == 0 else "", LABEL_PT * 0.7, Color(1, 1, 1, 0.75))
	_bubble(accent)


func _share_name(f: float) -> String:
	return "ALL" if f >= 0.999 else "%d%%" % int(round(f * 100.0))


func bubble_rect() -> Rect2:
	## The pick, clear of the finger: above the ring; beside it (the side with room) when the top has none; below as a last resort.
	var s := "SEND %d · %s" % [leaving(), _share_name(fraction_now())]
	var fs := int(round(BUBBLE_PT * ppx))
	var sz := Vector2(FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0 * ppx, 30.0 * ppx)
	var c: Vector2 = lay["c"]
	var ro: float = lay["r_out"]
	var tries := [c + Vector2(-sz.x / 2.0, -ro - 8.0 * ppx - sz.y), c + Vector2(ro + 8.0 * ppx, -sz.y / 2.0),
			c + Vector2(-ro - 8.0 * ppx - sz.x, -sz.y / 2.0), c + Vector2(-sz.x / 2.0, ro + 8.0 * ppx)]
	for p in tries:
		if bounds.encloses(Rect2(p, sz)):
			return Rect2(p, sz)
	var r := Rect2(tries[0], sz)
	r.position = r.position.clamp(bounds.position, bounds.end - sz)
	return r


func _bubble(accent: Color) -> void:
	var r := bubble_rect()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	NodeNoir.glass(self, pts, 0.92, Color(accent, 0.18))
	var loop := pts.duplicate()
	loop.append(pts[0])
	NodeNoir.neon(self, loop, accent, 1.5 * ppx, 0.6)
	_text(r.get_center(), "SEND %d · %s" % [leaving(), _share_name(fraction_now())], BUBBLE_PT, Color.WHITE)
