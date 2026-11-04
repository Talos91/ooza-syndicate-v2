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
var _reach_hub := -1                  # perf pass (audit B2): sim.monster_reach of the shown hub, worked out once per
var _reach_sig := []                   # hub and board (the decks' open states, the fallen nodes), not every frame
var _reach: Array = []
var route := {}                        # Alpha 24: the drag being aimed (main._route_hud): pts (world), ok, target, monster
var _drew := true                      # the last frame drew something (a frame that draws nothing clears it once)
const RELAY_CUE_MAX := 3               # only the first few times (Daniele's ask)
const RELAY_CUE_SECONDS := 4.0


const HALO_RING_WIDTH := 3.0          # 0.22.4: one thin, clean ring width at every tier (no more "fatter = tier" blob)
const HALO_BASE_PAD := 6.0            # ring radius past the node's rim
const HALO_RING_GAP := 6.0            # radius step between stacked seats' rings on the same node
const HALO_SEGMENT_GAP := 0.35        # rad, gap left between a ring's bright segments
const HALO_SEGMENT_ALPHA := 0.95
const HALO_BACKDROP_ALPHA := 0.22     # the faint full ring under the segments
const HALO_SPIN := 0.5                # rad/s the segments slowly turn (reads as "alive", not static)

# ui-neon (Daniele 2026-11-02: "the upgrade HUD is too small and flat too: make it neon as well"): the upgrade-ready chip is a
# neon hex plate with a double chevron, sized in phone points (it was an 18 px card, ~11 pt on a phone), on the platform's rim
# clear of the badges, pulsing for SIGN_PULSE_S when it lights up.
const UPGRADE_CHIP_PT := 17.0         # hex circumradius in points: 34 pt across on a phone (>= 33 pt readable)
const UPGRADE_ARROW_BOB := 2.0        # pt it gently bobs
const UPGRADE_ARROW_SPEED := 2.4      # rad/s of the bob/pulse

# ui-neon Last Stand alarm signs (Daniele 2026-11-02: "the next platform to fall should be RED, the second YELLOW and the others
# greyed out ... like a NEON ALARM SIGN, not a flat HUD, and when one changes state it PULSES for a bit"): a neon hex plate with
# the seconds, a warning beacon on top; tier 0 = next to fall, 1 = the one after, 2 = every other warned node.
const SIGN_COL := [Color(1.0, 0.17, 0.22), Color(1.0, 0.82, 0.12), Color(0.64, 0.69, 0.77)]
# 0.23.23 (Daniele on staging 0.23.22: "hud for last stand is way too small and anonymous and should be positioned on top not
# bottom"): bigger plates, the seconds say "s", the red one carries a NEXT DROP caption, and the sign goes over the platform's
# top rim first (under it only when the top is taken).
const SIGN_PT := [22.0, 17.0, 14.0]   # plate circumradius in points per tier (red 44 pt across)
const SIGN_FONT_PT := [20.0, 16.0, 13.5]   # the seconds (text >= 12.5 pt on a phone)
const SIGN_CAPTION := "NEXT DROP"     # over the red sign
const SIGN_CAPTION_PT := 12.5
const SIGN_ALPHA := [1.0, 0.95, 0.8]
const SIGN_PULSE_S := 1.5             # seconds a sign (or the upgrade chip) pulses after it changes state
const SIGN_PULSE_BEATS := 3.0
var _sign_tier := {}                  # node id -> its tier last frame
var _sign_pulse := {}                 # node id -> seconds left of its state-change pulse
var _up_ready := {}                   # node id -> upgrade chip lit last frame
var _up_pulse := {}                   # node id -> seconds left of the chip's pulse


func setup(m: Node3D, s: Sim, h: Hud, seat: String, scale_ui: float) -> void:
	main = m
	sim = s
	hud = h
	human = seat
	ui_scale = scale_ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	neon_atlas(Rules.seat_color(seat))                 # ui-neon: baked now, while the match loads (not at the Last Stand)


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
	_sync_pulses(dt)
	# perf pass (audit B11): redrawn while it shows anything (it pulses), once more to clear, then left alone
	var draws := _draws_something()
	if draws or _drew:
		queue_redraw()
	_drew = draws
	PerfProfile.lap("overlay_sync", _pt)


func _sync_pulses(dt: float) -> void:
	## ui-neon: a sign that is new or changed tier (grey -> yellow -> red), or an upgrade chip that just lit, pulses for
	## SIGN_PULSE_S; the timers run here (sync), the drawing reads them.
	var tiers := danger_tiers()
	for id in tiers:
		if int(_sign_tier.get(id, -1)) != int(tiers[id]):
			_sign_pulse[id] = SIGN_PULSE_S
	for id in _sign_pulse.keys():
		_sign_pulse[id] = float(_sign_pulse[id]) - dt
		if not tiers.has(id) or float(_sign_pulse[id]) <= 0.0:
			_sign_pulse.erase(id)
	_sign_tier = tiers
	var lit := {}
	for n in sim.nodes:
		if n["owner"] == human and _upgrade_ready(n["id"]):
			lit[n["id"]] = true
			if not _up_ready.has(n["id"]):
				_up_pulse[n["id"]] = SIGN_PULSE_S
	for id in _up_pulse.keys():
		_up_pulse[id] = float(_up_pulse[id]) - dt
		if not lit.has(id) or float(_up_pulse[id]) <= 0.0:
			_up_pulse.erase(id)
	_up_ready = lit


func danger_tiers() -> Dictionary:
	## Every warned node -> its alarm tier: 0 the next to fall, 1 the one after, 2 the rest (by sim.drop_in, so a warned node
	## missing from the queue never jumps to red). Outside a v3 ring there is one warned node: red.
	var warned := []
	for n in sim.nodes:
		var id: int = n["id"]
		if not sim.collapsed.get(id, false) and sim.is_warned(id):
			warned.append([sim.drop_in(id) if sim.v3 else 0.0, id])
	warned.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out := {}
	for i in range(warned.size()):
		out[warned[i][1]] = mini(i, 2)
	return out


func _pt() -> float:
	## Canvas units per phone point (UiKit.pt_per_px: the page's CSS size on the web, the 390 pt phone elsewhere).
	return 1.0 / maxf(UiKit.pt_per_px(get_viewport_rect().size), 0.01)


func _pulse_k(t_left: float) -> Array:
	## [beat 0..1, the pulse's envelope 1..0, the beat's phase 0..1] of a state-change pulse with t_left seconds to run.
	if t_left <= 0.0:
		return [0.0, 0.0, 0.0]
	var env := clampf(t_left / SIGN_PULSE_S, 0.0, 1.0)
	var ph := fposmod((1.0 - env) * SIGN_PULSE_BEATS, 1.0)
	return [absf(sin(ph * PI)), env, ph]


func _flicker(id: int) -> float:
	## A neon tube's slight flicker: now and then a short dip (never below 0.8), different per sign.
	var f := sin(_t * 31.0 + id * 1.7) * sin(_t * 4.3 + id * 0.9)
	return 1.0 - 0.2 * clampf((f - 0.7) / 0.3, 0.0, 1.0)


func _badge_rects() -> Array:
	## The badges on screen this frame (their boxes): the signs and the chip are placed clear of them.
	var out := []
	for id in hud.badges:
		var p: Control = hud.badges[id]["panel"]
		if p.visible:
			out.append(Rect2(p.position, p.size))
	return out


func _clear_spot(c: Vector2, offsets: Array, half: Vector2, avoid: Array) -> Vector2:
	## The first of the candidate centres (c + offset) whose box (2 x half) overlaps none of `avoid`; else the least covered.
	var best := c + (offsets[0] as Vector2)
	var best_cover := INF
	for o in offsets:
		var q: Vector2 = c + (o as Vector2)
		var box := Rect2(q - half, half * 2.0)
		var cover := 0.0
		for a in avoid:
			var x := box.intersection(a as Rect2)
			cover += x.get_area()
		if cover <= 0.0:
			return q
		if cover < best_cover:
			best_cover = cover
			best = q
	return best


func _draws_something() -> bool:
	## Would _draw put anything on screen this frame (halos, relay cues, the monster reach, a relay preview, a
	## danger symbol)? A cheap scan: false means the overlay can stay as it is.
	if not route.is_empty():
		return true
	if main.monster_from >= 0 or hover_relay >= 0 or (hud.inspector_id >= 0 and hud.inspector_id < sim.nodes.size() 			and sim.nodes[hud.inspector_id]["structure"] == "monster_hub"):
		return true
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false):
			continue
		if not (n.get("allies", {}) as Dictionary).is_empty() or sim.is_warned(n["id"]):
			return true
		if n["owner"] == human and _upgrade_ready(n["id"]):
			return true
		if n["relay"] != "" and (n["relay_phase"] == "warning" or (n["owner"] == human and n["relay_cd"] <= 0.0) 				or float(_relay_cue_t.get(n["id"], 0.0)) > 0.0):
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
	if hud.shows("halos"):
		_draw_halos(cam)
	var avoid := _badge_rects()                      # ui-neon: the signs, then the upgrade chips, clear of the counts
	_layout_signs(cam, avoid)
	_chips.clear()
	if hud.shows("upgrade_arrow"):
		_draw_upgrade_arrows(cam, avoid)
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
	if not route.is_empty():
		_draw_route(cam)
	if hud.shows("danger"):
		_draw_danger_symbols(cam)
	PerfProfile.lap("overlay_draw", _pt)


# ------------------------------------------------------------------ the aimed route (Alpha 24, round-3 ROUTE FEEDBACK)
func _draw_route(cam: Camera3D) -> void:
	## Over main's 3D drag line: the pack's route chevrons (B23) marching along a valid route in your colour, its NO ROUTE
	## blocks (B24) on a blocked one, and the target's marker - VALID (B21) / INVALID (B22).
	var ok := bool(route.get("ok", false))
	var col := Rules.seat_color(human) if ok else Rules.state_color("warn")
	var line := PackedVector2Array()
	for q in (route.get("pts", PackedVector3Array()) as PackedVector3Array):
		line.append(cam.unproject_position(q + Vector3(0, 1.0, 0)))
	var s := ui_scale
	if line.size() >= 2:
		var step := (24.0 if ok else 26.0) * s
		var k := fposmod(_t * (36.0 if ok else 0.0) * s, step)
		var seg := 0
		var done := 0.0                                  # path length before line[seg]
		var total := 0.0
		for i in range(line.size() - 1):
			total += line[i].distance_to(line[i + 1])
		var at := k
		while at < total - 10.0 * s:
			while seg < line.size() - 2 and done + line[seg].distance_to(line[seg + 1]) < at:
				done += line[seg].distance_to(line[seg + 1])
				seg += 1
			var a: Vector2 = line[seg]
			var b: Vector2 = line[seg + 1]
			var l := maxf(a.distance_to(b), 0.001)
			var pos := a.lerp(b, clampf((at - done) / l, 0.0, 1.0))
			draw_set_transform(pos, (b - a).angle(), Vector2.ONE)
			if ok:
				var h := 9.0 * s
				HudSkin.draw_sprite(self, "B23", Rect2(-h, -h, 2.0 * h, 2.0 * h), Color(col.lightened(0.25), 0.95))
			else:
				var bw := 16.0 * s
				HudSkin.draw_sprite(self, "B24", Rect2(-bw / 2.0, -bw / 8.0, bw, bw / 4.0))
			at += step
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var target := int(route.get("target", -1))
	if target >= 0 and target < sim.nodes.size():
		var ns := _node_screen(target, cam)
		var r: float = float(ns[1]) * 1.2 + 6.0 * s
		var breathe := 1.0 + 0.04 * sin(_t * 5.0)
		HudSkin.draw_sprite(self, "B21" if ok else "B22", Rect2((ns[0] as Vector2) - Vector2(r, r) * breathe, Vector2(r, r) * 2.0 * breathe),
				Color(col.lightened(0.2), 0.9) if ok else Color.WHITE)


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
	## own colour - stacked outward so more than one ally's rings don't merge into one blob.
	## 0.22.4 playtest redesign (Daniele: "a nicer ally halo"): the old ring grew THICKER with tier, which
	## at tier 3 read as a fat glowing blob rather than a ring. Now every tier draws the same thin, clean
	## ring (HALO_RING_WIDTH) plus a faint full backdrop so it still reads at a glance; the tier shows as
	## the number of bright segments round it (1 / 2 / 3), slowly turning - readable at phone size without
	## the "more troops = bigger smear" look.
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
			var r := float(ns[1]) + (HALO_BASE_PAD + ring * HALO_RING_GAP) * ui_scale
			_draw_halo_ring(ns[0], r, Rules.seat_color(str(seat)), tier)
			ring += 1


func _draw_halo_ring(c: Vector2, r: float, col: Color, tier: int) -> void:
	var w := HALO_RING_WIDTH * ui_scale
	draw_arc(c, r, 0.0, TAU, 40, Color(col, HALO_BACKDROP_ALPHA), w, true)   # a faint full ring (always reads)
	var seg_len := TAU / float(tier) - HALO_SEGMENT_GAP
	for i in range(tier):                              # tier bright segments, slowly turning round the ring
		var start := _t * HALO_SPIN + i * (TAU / float(tier))
		draw_arc(c, r, start, start + seg_len, 20, Color(col, HALO_SEGMENT_ALPHA), w, true)


# ------------------------------------------------------------------ upgrade-ready arrow (playtest 2026-09-28,
# Daniele's cousins: "how do I know when I can upgrade?"): a small pulsing chevron over the badge of any of the
# human's own nodes that can go up a tier RIGHT NOW - enough units, not mid-construction (Sim.can_upgrade already
# refuses both), and not under attack (Sim.node_under_attack). It hides itself the moment any of that stops being
# true: the inspector opening on that node, or the upgrade starting, both make can_upgrade refuse next frame.
func _upgrade_ready(id: int) -> bool:
	if sim.collapsed.get(id, false) or hud.inspector_id == id:
		return false
	var n: Dictionary = sim.nodes[id]
	if n["owner"] != human:
		return false
	return sim.can_upgrade(id, human) == "" and not sim.node_under_attack(id, human)


func upgrade_chip_rect(id: int) -> Rect2:
	## Where the upgrade-ready chip of node `id` is drawn this frame (empty when it is not lit) - tests / the tutorial.
	var c = _chips.get(id)
	if c == null:
		return Rect2()
	var half := Vector2(float(c[1]), float(c[1]) * 0.866)
	return Rect2((c[0] as Vector2) - half, half * 2.0)


var _chips := {}                       # node id -> [centre, circumradius]: the chips drawn this frame


func _draw_upgrade_arrows(cam: Camera3D, avoid: Array) -> void:
	## The upgrade-ready chip (ui-neon): a neon hex plate in your own colour with a double chevron, on the platform's upper rim
	## clear of every badge and alarm sign, gently bobbing; it pulses for SIGN_PULSE_S when it lights up.
	_chips.clear()
	var col := Rules.seat_color(human)
	var pt := _pt()
	for n in sim.nodes:
		var id: int = n["id"]
		if n["owner"] != human or not _upgrade_ready(id):
			continue
		var ns := _node_screen(id, cam)
		var r: float = float(ns[1])
		var k := 0.5 + 0.5 * sin(_t * UPGRADE_ARROW_SPEED + float(id))
		var pk := _pulse_k(float(_up_pulse.get(id, 0.0)))
		var R := UPGRADE_CHIP_PT * pt
		var d := r * 0.62
		var c := _clear_spot(ns[0], [Vector2(d, -d), Vector2(-d, -d), Vector2(d, d * 0.7), Vector2(-d, d * 0.7)],
				Vector2(R, R * 0.866), avoid)
		_chips[id] = [c, R]
		avoid.append(upgrade_chip_rect(id))              # (the next chip keeps clear of this one too)
		c.y -= UPGRADE_ARROW_BOB * pt * k
		_chips[id] = [c, R]
		var grow := 1.0 + 0.3 * float(pk[0]) * float(pk[1])
		_neon(NT_CHIP, c, R * grow, Color(1, 1, 1, 0.88 + 0.12 * k))
		if float(pk[1]) > 0.0:
			_pulse_ring(c, R, col, pk, NT_CHIP)


# ------------------------------------------------------------------ the neon atlas (ui-neon)
# Every neon sign is baked whole (dark plate, outer halo, inner glow, the lit tube and its hot core, the beacon) into one
# texture, a cell per look - the three alarm tiers and your upgrade chip - plus a white tube for the pulse rings, and drawn as
# one tinted rect: the 2D renderer batches rects that share a texture, and a sign costs one object, not eight. (Drawn as
# polygons and polylines, one draw call each on GL Compatibility, M-39's Last Stand went from 402 to 685 draw calls.) No shader.
const NT_W := 88                       # one cell (px): the plate's centre sits at NT_CY, the beacon over it
const NT_H := 112
const NT_CY := 62.0
const NT_R := 28.0                     # the plate's circumradius in its cell (px)
enum { NT_RED, NT_YELLOW, NT_GREY, NT_CHIP, NT_TUBE }
const NT_GLOW := [1.0, 0.8, 0.5, 0.8]  # how much each look glows (the grey one barely)
static var _atlas: ImageTexture = null
static var _atlas_chip := Color(0, 0, 0, 0)
static var _atlas_mode := ""


static func neon_atlas(chip: Color) -> Texture2D:
	## The baked signs, one NT_W x NT_H cell each; rebuilt only when the chip's colour (your seat's) changes (~50k px).
	## Alpha 24 (round-3 pack, current theme): the plates are the pack's alarm hexes (B16 red / B17 amber / B18 grey), the
	## beacons its warning triangles (B13 next / B14 second / B15 queued), the chip its upgrade hex (B11, in your colour) with the
	## E upgrade chevrons; the neon halo round each and the pulse tube stay drawn here. Without the pack: the ui-neon drawing.
	var mode := UiTheme.mode()
	if _atlas != null and _atlas_chip == chip and _atlas_mode == mode:
		return _atlas
	_atlas_chip = chip
	_atlas_mode = mode
	var img := Image.create(NT_W * 5, NT_H, false, Image.FORMAT_RGBA8)
	var ap := NT_R * 0.8660254                          # the plate's apothem
	var bc := Vector2(0, -NT_R * 1.086)                 # the beacon's centre, its half-width and height
	var bw := NT_R * 0.6
	var bh := bw * 1.5
	var bl := sqrt(bh * bh + bw * bw)
	var dark := Color(0.02, 0.03, 0.05)
	var pack := HudSkin.sheet() != null
	for cell in range(5):
		var col: Color = chip if cell == NT_CHIP else (Color.WHITE if cell == NT_TUBE else SIGN_COL[cell])
		var g: float = 1.0 if cell == NT_TUBE else float(NT_GLOW[cell])
		var light := col.lightened(0.65)
		for y in range(NT_H):
			for x in range(NT_W):
				var p := Vector2(x + 0.5 - NT_W / 2.0, y + 0.5 - NT_CY)
				# the pack's hexes stand on a point (the ui-neon ones lay flat): signed distance (px) to that hex
				var d := (maxf(absf(p.x), 0.8660254 * absf(p.y) + 0.5 * absf(p.x)) if pack else maxf(absf(p.y), 0.8660254 * absf(p.x) + 0.5 * absf(p.y))) - ap
				var tube := clampf(2.0 - absf(d), 0.0, 1.0)
				var px := Color(col, 0.0)
				if cell == NT_TUBE:
					px = Color(1, 1, 1, tube)
				elif pack:
					px = Color(col, g * 0.5 * exp(-maxf(d, 0.0) / 5.0) if d > 0.0 else 0.0)                  # outer halo
					var q := p - bc
					var dt := maxf(q.y - 0.38 * bh, (absf(q.x) * bh - (q.y + 0.62 * bh) * bw) / bl)
					if cell != NT_CHIP:
						px = _over(px, Color(col, g * 0.4 * exp(-maxf(dt, 0.0) / 4.0) if dt > 0.0 else 0.0))   # the beacon's halo
				else:
					px = _over(px, Color(col, g * 0.45 * exp(-maxf(d, 0.0) / 5.5) if d > 0.0 else 0.0))   # outer halo
					px = _over(px, Color(dark, 0.85 * clampf(0.5 - d, 0.0, 1.0)))                     # the plate
					px = _over(px, Color(col, g * 0.32 * exp(d / 4.0) if d <= 0.0 else 0.0))            # inner glow
					px = _over(px, Color(col, 0.95 * tube))                                             # the tube
					px = _over(px, Color(light, 0.9 * clampf(0.9 - absf(d), 0.0, 1.0)))                 # its hot core
					if cell == NT_CHIP:                                                                 # two chevrons
						var dmin := INF
						var cw := NT_R * 0.42
						for step in [-0.2, 0.16]:
							var yy: float = NT_R * step
							var l := Vector2(-cw, yy + cw * 0.55)
							var m := Vector2(0, yy - cw * 0.45)
							var r := Vector2(cw, yy + cw * 0.55)
							dmin = minf(dmin, minf(_seg_d(p, l, m), _seg_d(p, m, r)))
						var dc := dmin - 1.8
						px = _over(px, Color(col, 0.4 * exp(-maxf(dc, 0.0) / 3.0)))
						px = _over(px, Color(col.lightened(0.45), clampf(0.5 - dc, 0.0, 1.0)))
					else:                                                                               # the beacon
						var q := p - bc
						var dt := maxf(q.y - 0.38 * bh, (absf(q.x) * bh - (q.y + 0.62 * bh) * bw) / bl)
						px = _over(px, Color(col, g * 0.4 * exp(-maxf(dt, 0.0) / 4.0) if dt > 0.0 else 0.0))
						px = _over(px, Color(dark, 0.9 * clampf(0.5 - dt, 0.0, 1.0)))
						px = _over(px, Color(col.lightened(0.2), clampf(1.8 - absf(dt), 0.0, 1.0)))
						var bar := _seg_d(q, Vector2(0, -0.3 * bh), Vector2(0, 0.08 * bh)) - 1.9         # the "!"
						var dot := q.distance_to(Vector2(0, 0.24 * bh)) - 2.2
						px = _over(px, Color(col.lightened(0.6), clampf(0.5 - minf(bar, dot), 0.0, 1.0)))
				img.set_pixel(cell * NT_W + x, y, px)
		if pack and cell != NT_TUBE:
			_bake_pack_cell(img, cell, chip, bc, bw, bh)
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(img)
	else:
		_atlas.update(img)
	return _atlas


# Neon Noir revision 6 (the art director): the alarm signs alert_sign_red / _amber / _grey (fixed colours) and the upgrade chip
# (fill + white rim in your colour); measured on their 216 x 246 / 196 x 196 canvases: the plate's centre and circumradius (px)
const NOIR_CELL := ["alert_sign_red", "alert_sign_amber", "alert_sign_grey", "upgrade_chip", "alert_sign_pulse"]
const CHIP_SQUASH := 0.87             # upgrade_chip: drawn at 87 % height (its painted hex is 100 x 101, a regular one 100 x 87)
const NOIR_PLATE := [Vector3(108, 145, 62), Vector3(108, 145, 62), Vector3(108, 145, 62), Vector3(98, 98, 50), Vector3(108, 145, 62)]


static var _noir_tex := {}                # "cell|chip colour" -> the director's sign / chip, baked whole (glow band included)


static func noir_tex(cell: int, chip: Color) -> Texture2D:
	## One sign or the chip from the director's art, baked once at ~2x its usual size with mipmaps (drawn by _neon, not from
	## the atlas: its glow band is wider than an atlas cell). null when not imported.
	var key := "%d|%s" % [cell, chip.to_html()]
	if not _noir_tex.has(key):
		var pl: Vector3 = NOIR_PLATE[cell]
		var im := HudSkin.noir_image(NOIR_CELL[cell], 2.0 * NT_R / pl.z, chip if cell == NT_CHIP else Color.WHITE)
		if im != null:
			if cell == NT_CHIP:                                # the art's hex is ~15 % taller than a regular one: squared up
				im.resize(im.get_width(), int(round(im.get_height() * CHIP_SQUASH)), Image.INTERPOLATE_LANCZOS)
			im.generate_mipmaps()
		_noir_tex[key] = ImageTexture.create_from_image(im) if im != null else null
	return _noir_tex[key]


static func _bake_pack_cell(img: Image, cell: int, chip: Color, bc: Vector2, bw: float, bh: float) -> void:
	## Alpha 24: one cell's sprites over its halo - the plate (a pointy hex of circumradius NT_R), then the beacon / chevrons.
	var o := Vector2(cell * NT_W + NT_W / 2.0, NT_CY)       # the plate's centre in the atlas
	var side := int(round(NT_R * 2.0))
	var plate := HudSkin.sprite_image(["B16", "B17", "B18", "B11"][cell], Vector2i(side, side), chip if cell == NT_CHIP else Color.WHITE)
	if plate != null:
		img.blend_rect(plate, Rect2i(Vector2i.ZERO, plate.get_size()), Vector2i((o - Vector2(side, side) / 2.0).round()))
	if cell == NT_CHIP:                                    # the E upgrade chevrons, dark on your colour
		var t := UiTheme.icon("upgrade")
		var ic: Image = t.get_image() if t != null else null
		if ic != null:
			ic = ic.duplicate()
			if ic.is_compressed():
				ic.decompress()
			ic.clear_mipmaps()
			ic.convert(Image.FORMAT_RGBA8)
			var isz := int(round(NT_R * 1.25))
			ic.resize(isz, isz, Image.INTERPOLATE_LANCZOS)
			var ink := Color(0.02, 0.07, 0.1)
			for y in range(isz):
				for x in range(isz):
					ic.set_pixel(x, y, Color(ink, ic.get_pixel(x, y).a))
			img.blend_rect(ic, Rect2i(0, 0, isz, isz), Vector2i((o - Vector2(isz, isz) / 2.0).round()))
		return
	var tri_id: String = ["B13", "B14", "B15"][cell]
	var rc: Array = UiTheme.DATA.SPRITES[tri_id]["rect"]
	var tw := int(round(bw * 2.3))
	var th := int(round(tw * float(rc[3]) / float(rc[2])))
	var tri := HudSkin.sprite_image(tri_id, Vector2i(tw, th))
	if tri == null:
		return
	var at := o + bc - Vector2(tw / 2.0, th * 0.58)
	img.blend_rect(tri, Rect2i(0, 0, tw, th), Vector2i(at.round()))
	if cell != NT_RED or UiTheme.light():                # B14 / B15 carry no "!" (LIGHT B13's is white on pale): draw it in the tier's colour
		var col: Color = SIGN_COL[cell]
		var ink := col.darkened(0.35) if UiTheme.light() else col.lightened(0.45)
		var tc := o + bc + Vector2(0, th * 0.12)
		for y in range(int(at.y), int(at.y) + th):
			for x in range(int(at.x), int(at.x) + tw):
				var q := Vector2(x + 0.5, y + 0.5) - tc
				var bar := _seg_d(q, Vector2(0, -0.3 * bh), Vector2(0, 0.06 * bh)) - 1.6
				var dot := q.distance_to(Vector2(0, 0.24 * bh)) - 1.9
				var a := clampf(0.5 - minf(bar, dot), 0.0, 1.0)
				if a > 0.0 and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, _over(img.get_pixel(x, y), Color(ink, a)))


static func _over(dst: Color, src: Color) -> Color:
	## src over dst (straight alpha).
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(src, 0.0)
	var k := dst.a * (1.0 - src.a)
	return Color((src.r * src.a + dst.r * k) / a, (src.g * src.a + dst.g * k) / a, (src.b * src.a + dst.b * k) / a, a)


static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _neon(cell: int, c: Vector2, R: float, mod: Color) -> void:
	## One baked sign with its plate's centre on c and circumradius R (screen units), tinted / faded by mod.
	if HudNoir.has(NOIR_CELL[cell]):   # Neon Noir revision 6: the director's sign / chip, its plate on c
		var t := noir_tex(cell, Rules.seat_color(human))
		if t != null:
			var pl: Vector3 = NOIR_PLATE[cell]
			var kk := R / pl.z                                    # screen px per source px
			var kb := 2.0 * NT_R / pl.z                           # texture px per source px
			var sq := CHIP_SQUASH if cell == NT_CHIP else 1.0
			draw_texture_rect(t, Rect2(c - Vector2(pl.x, pl.y * sq) * kk, t.get_size() * kk / kb), false, mod)
			return
	var k := R / NT_R
	var sz := Vector2(NT_W, NT_H) * k
	draw_texture_rect_region(neon_atlas(Rules.seat_color(human)), Rect2(c - Vector2(NT_W / 2.0, NT_CY) * k, sz),
			Rect2(cell * NT_W, 0, NT_W, NT_H), mod)


func _pulse_ring(c: Vector2, R: float, col: Color, pk: Array, cell := NT_TUBE) -> void:
	## A state-change beat: a hex outline swelling out from the plate and fading (Neon Noir: the director's pulse outline for a
	## sign; the chip's own shape, faded, for the upgrade chip).
	var ph := float(pk[2])
	var a := 0.75 * (1.0 - ph) * float(pk[1])
	if cell == NT_CHIP and HudNoir.has("upgrade_chip"):
		_neon(NT_CHIP, c, R * (1.1 + 0.9 * ph), Color(1, 1, 1, a * 0.6))
		return
	_neon(NT_TUBE, c, R * (1.1 + 0.9 * ph), Color(col, a))


# ------------------------------------------------------------------ relay badge cues (0.19.0, Daniele:
# "add some visibility to the buttons / models of the relays")
func _draw_relay_cues(cam: Camera3D) -> void:
	for n in sim.nodes:
		var id: int = n["id"]
		if n["relay"] == "" or n["owner"] != human or sim.collapsed.get(id, false):
			continue
		var ready: bool = n["relay_cd"] <= 0.0 and n["relay_phase"] == ""
		var ns := _node_screen(id, cam)
		var bs := RelayView.button_screen(cam, main.vis, id)   # RELAY V2: the glow and the cue sit on the button
		if not bs.is_empty():
			ns = bs
		if ready:                                      # a ready glow round the button (Hud.RELAY_ACCENT)
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


# ------------------------------------------------------------------ Last Stand alarm signs
func sign_rect(id: int) -> Rect2:
	## Where node `id`'s alarm sign is drawn this frame (plate and beacon; empty when it has none) - tests.
	var s = _signs.get(id)
	if s == null:
		return Rect2()
	var R := float(s[1])
	var r := Rect2((s[0] as Vector2) - Vector2(R, R * 1.65), Vector2(2.0 * R, R * 2.52))
	if int(s[2]) == 0:                                    # the NEXT DROP caption over the beacon
		var cap := _caption_size()
		var top := r.position.y - cap.y
		r = r.merge(Rect2(Vector2((s[0] as Vector2).x - cap.x / 2.0, top), cap))
	return r


func _caption_size() -> Vector2:
	var f := int(round(SIGN_CAPTION_PT * _pt()))
	return Vector2(Hud.UI_FONT.get_string_size(SIGN_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x + 6.0, Hud.UI_FONT.get_height(f))


var _signs := {}                       # node id -> [plate centre, circumradius, tier]: laid out this frame


func _layout_signs(cam: Camera3D, avoid: Array) -> void:
	## Each warned node's sign: over the platform's top rim when that is clear of every badge (0.23.23; it was under the
	## camera-facing rim first), else under it, else beside it (Daniele, 0.19.0: "floating over the border of the platform in a way it doesn't cover what's
	## going on"; ui-neon: and never over a count).
	_signs.clear()
	if not hud.shows("danger"):
		return
	var pt := _pt()
	for id in _sign_tier:
		var tier: int = _sign_tier[id]
		var ns := _node_screen(id, cam)
		var r: float = float(ns[1])
		var pk := _pulse_k(float(_sign_pulse.get(id, 0.0)))
		var R: float = float(SIGN_PT[tier]) * pt * (1.0 + 0.3 * float(pk[0]) * float(pk[1]))
		var below := r * 0.86 + R * 0.6
		var lift := Vector2(0, R * 0.39)                # the sign's box centre sits that far over the plate's (the beacon)
		var c := lift + _clear_spot((ns[0] as Vector2) - lift, [Vector2(0, -r * 0.86 - R * 0.6), Vector2(0, below),
				Vector2(-r - R * 0.7, 0), Vector2(r + R * 0.7, 0)], Vector2(R, R * 1.26), avoid)
		_signs[id] = [c, R, tier]
		avoid.append(sign_rect(id))


func _draw_danger_symbols(_cam: Camera3D) -> void:
	## ui-neon (Daniele 2026-11-02): RED for the next node to fall, YELLOW for the one after, GREY for every other warned node -
	## each a neon alarm sign (a hex plate with the seconds, a warning beacon on top) with a slight flicker; the red one
	## breathes; a sign that is new or changes tier pulses for SIGN_PULSE_S. The count stays on the node's badge (Hud._badges).
	for id in _signs:
		var s: Array = _signs[id]
		var c: Vector2 = s[0]
		var R: float = s[1]
		var tier: int = s[2]
		var col: Color = SIGN_COL[tier]
		var pk := _pulse_k(float(_sign_pulse.get(id, 0.0)))
		var a: float = float(SIGN_ALPHA[tier]) * _flicker(id)
		if tier == 0 and float(pk[1]) <= 0.0:
			a *= 0.84 + 0.16 * sin(_t * 6.0)               # the next to fall breathes
		_neon(tier, c, R, Color(1, 1, 1, a))
		if float(pk[1]) > 0.0:
			_pulse_ring(c, R, col, pk)
	var words := []                                     # the seconds, after every plate, so the glyphs batch too (one font
	for id in _signs:                                    # size per tier - a pulse grows the plate only)
		var s: Array = _signs[id]
		var tier: int = s[2]
		var col: Color = SIGN_COL[tier]
		var a: float = float(SIGN_ALPHA[tier]) * _flicker(id)
		var secs := int(ceil(sim.drop_in(id) if sim.v3 else sim.last_stand_warn_t))
		var f := int(round(float(SIGN_FONT_PT[tier]) * _pt()))
		var txt := "%ds" % maxi(secs, 0)
		var sz := Hud.UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		var room := float(s[1]) * 1.45                      # the plate's inner width: "12s" shrinks to fit
		if sz.x > room:
			f = int(floor(f * room / sz.x))
			sz = Hud.UI_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		words.append([(s[0] as Vector2) + Vector2(-sz.x / 2.0, Hud.UI_FONT.get_ascent(f) * 0.5 - 1.0), txt, f, col, a])
		if tier == 0:                                       # NEXT DROP over the beacon, outlined so it reads on any floor
			var cf := int(round(SIGN_CAPTION_PT * _pt()))
			var cs := Hud.UI_FONT.get_string_size(SIGN_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, cf)
			var top := (s[0] as Vector2).y - float(s[1]) * 1.65
			var at := Vector2((s[0] as Vector2).x - cs.x / 2.0, top - Hud.UI_FONT.get_descent(cf) - 1.0)
			draw_string_outline(Hud.UI_FONT, at, SIGN_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, cf, maxi(2, int(round(3.0 * _pt()))), Color(0, 0, 0, 0.85 * a))
			draw_string(Hud.UI_FONT, at, SIGN_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, cf, Color(col.lightened(0.35), a))
	for w in words:                                      # (no outline pass: the plate is dark - every glyph is an object)
		var wc: Color = (w[3] as Color).darkened(0.45) if UiTheme.light() else (w[3] as Color).lightened(0.55)   # Alpha 24: a pale plate in LIGHT
		draw_string(Hud.UI_FONT, w[0], w[1], HORIZONTAL_ALIGNMENT_LEFT, -1, w[2], Color(wc, w[4]))
