class_name NodeNoir
extends RefCounted
## Alpha 24 step 4, NODE UI in Neon Noir (🧩 ui-node, Daniele 2026-11-04): what is drawn at or round a node - the selection
## hex and its close hub, the action pie (wedges), the compact node card, the tier chip, the armour shields, the capture
## burst, the relay button's ring, the send ribbon / target ring / HOLD ring. Same vocabulary as the HUD (HudNoir / NoirBox):
## smoked glass, a neon tube with a halo and a hot core, lit ooze; dark only; your own node's things take your faction accent
## (HudNoir.accent), other players' their seat colour, fixed meanings stay fixed (ENEMY red, AMBER seconds, GOOD green).
## DROP-IN: every drawing first asks sprite(id): a part the art director delivered (References/UI direction 2026-11-02
## round-3/hud-redo/NODE-PROMPTS.md, imported by tools/hud_noir_import.py --node into HudNoirData.PARTS) draws instead of
## the placeholder geometry - white layers tinted by the caller where the game tints (rims, goo, shields, chips).

const GLASS_TOP := Color("16212c")
const GLASS_LOW := Color("0a1119")
const SHIELD_STEP := 0.1                        # one shield per 0.1 of armour above x1.0 (T2 = 2, T3 = 4, T4 = 6)


static func mine_or_seat(owner: String, human: String) -> Color:
	## The node UI's colour channel (Daniele 2026-11-04: "faction accent on yours"): your faction accent on your own nodes,
	## the owner's seat colour elsewhere, the neutral grey on nobody's.
	if owner == "":
		return HudNoir.NEUTRAL
	return HudNoir.accent if owner == human else Rules.seat_color(owner)


static func neon(ci: CanvasItem, loop: PackedVector2Array, col: Color, w: float, glow := 1.0, alpha := 1.0) -> void:
	## A closed (or open) path as a neon tube: wide faint halo strokes, the tube, a near-white core.
	if loop.size() < 2:
		return
	if glow > 0.0:
		for k in [[5.5, 0.06], [3.4, 0.11], [2.0, 0.18]]:
			ci.draw_polyline(loop, Color(col, float(k[1]) * glow * alpha), w * float(k[0]), true)
	ci.draw_polyline(loop, Color(col, 0.95 * alpha), w, true)
	if glow > 0.0:
		ci.draw_polyline(loop, Color(col.lerp(Color.WHITE, 0.65), 0.6 * glow * alpha), maxf(w * 0.38, 1.0), true)


static func clean(pts: PackedVector2Array) -> PackedVector2Array:
	## A polygon without repeated points (sampled hex corners land twice; the triangulator refuses those).
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[-1].distance_squared_to(p) > 0.0004:
			out.append(p)
	while out.size() > 1 and out[0].distance_squared_to(out[-1]) <= 0.0004:
		out.remove_at(out.size() - 1)
	return out


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a / 2.0


static func glass(ci: CanvasItem, pts: PackedVector2Array, alpha := 0.86, tint := Color(0, 0, 0, 0)) -> void:
	## Smoked glass over a polygon: lighter at the top, a darker belly (NoirBox's body), an optional meaning tint.
	pts = clean(pts)
	if pts.size() < 3:
		return
	var top := INF
	var low := -INF
	for p in pts:
		top = minf(top, p.y)
		low = maxf(low, p.y)
	var cols := PackedColorArray()
	for p in pts:
		var c := GLASS_TOP.lerp(GLASS_LOW, clampf((p.y - top) / maxf(low - top, 1.0), 0.0, 1.0))
		cols.append(Color(c.lerp(tint, tint.a * 0.45), alpha))
	ci.draw_polygon(pts, cols)


static func hexagon(c: Vector2, r: float, rot := 0.0) -> PackedVector2Array:
	## A closed hexagon of corner radius r (rot 0: pointy left / right, flat top).
	var out := PackedVector2Array()
	for k in range(7):
		var a := rot + TAU * float(k % 6) / 6.0
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func sprite(ci: CanvasItem, id: String, centre: Vector2, body_px: Vector2, tint := Color.WHITE, rot := 0.0) -> bool:
	## A delivered node part drawn whole, its BODY (the part's drawn size, without the glow band) at body_px round centre.
	## False while the part is still a placeholder (the caller draws its geometry).
	if not HudNoir.has(id):
		return false
	var p := HudNoir.part_data(id)
	var t := HudNoir.texture(str(p.get("file", "")))
	if t == null:
		return false
	var size_px: Array = p.get("size", [1, 1])
	var body: Array = p.get("body", [0, 0, 1, 1])
	var k := Vector2(body_px.x / float(body[2]), body_px.y / float(body[3]))
	var r := Rect2(-Vector2(float(body[0]) + float(body[2]) / 2.0, float(body[1]) + float(body[3]) / 2.0) * k,
			Vector2(size_px[0], size_px[1]) * k)
	ci.draw_set_transform(centre, rot, Vector2.ONE)
	ci.draw_texture_rect(t, r, false, tint)
	var rim := HudNoir.texture(str(p.get("rim", "")))
	if rim != null:
		ci.draw_texture_rect(rim, r, false, tint)
	var shine := HudNoir.texture(str(p.get("shine", "")))
	if shine != null:
		ci.draw_texture_rect(shine, r, false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


# ------------------------------------------------------------------ armour shields (Daniele 2026-11-04: "armor should be a
# simple shield maybe many of them and they gradually fill")
static func shield_count(cap: float) -> int:
	return maxi(0, int(round((cap - 1.0) / SHIELD_STEP)))


static func shield_fill(i: int, armour: float) -> float:
	## How full shield i is (0..1): shield 0 holds x1.0-x1.1, shield 1 x1.1-x1.2 ... (each fills in 10 s at 0.01/s).
	return clampf((armour - 1.0 - float(i) * SHIELD_STEP) / SHIELD_STEP, 0.0, 1.0)


static func shield_outline(c: Vector2, h: float) -> PackedVector2Array:
	## A heater shield, h tall, centred on c (flat top, curved sides into the point).
	var w := h * 0.84
	var out := PackedVector2Array()
	out.append(c + Vector2(-w / 2.0, -h / 2.0))
	out.append(c + Vector2(w / 2.0, -h / 2.0))
	for k in range(1, 9):                               # the right side down to the point
		var t := float(k) / 8.0
		out.append(c + Vector2(w / 2.0 * (1.0 - t * t), -h / 2.0 + h * 0.38 + h * 0.62 * t))
	for k in range(7, 0, -1):                           # the left side back up
		var t := float(k) / 8.0
		out.append(c + Vector2(-w / 2.0 * (1.0 - t * t), -h / 2.0 + h * 0.38 + h * 0.62 * t))
	return out


static func shield(ci: CanvasItem, c: Vector2, h: float, fill: float, col: Color, s: float, glow := 0.0) -> void:
	## One shield: dark glass, filling with lit goo from the bottom (fill 0..1), a neon rim (brighter once full).
	var shape := shield_outline(c, h)
	if sprite(ci, "node_shield_empty", c, Vector2(h * 0.84, h)):
		if fill > 0.0:
			var t := HudNoir.texture(str(HudNoir.part_data("node_shield_full").get("file", "")))
			if t != null:                                # the full shield clipped to its fill height
				var p := HudNoir.part_data("node_shield_full")
				var body: Array = p.get("body", [0, 0, 1, 1])
				var size_px: Array = p.get("size", [1, 1])
				var k := h / float(body[3])
				var top := (float(body[1]) + float(body[3]) * (1.0 - fill))
				var src := Rect2(0, top, float(size_px[0]), float(size_px[1]) - top)
				var dst := Rect2(c + Vector2(-float(body[0]) - float(body[2]) / 2.0, top - float(body[1]) - float(body[3]) / 2.0) * k,
						src.size * k)
				ci.draw_texture_rect_region(t, dst, src, col)
		return
	glass(ci, shape, 0.9)
	if fill > 0.0:
		var y := c.y + h / 2.0 - h * fill
		var clip := PackedVector2Array([Vector2(c.x - h, y), Vector2(c.x + h, y), Vector2(c.x + h, c.y + h), Vector2(c.x - h, c.y + h)])
		for part in Geometry2D.intersect_polygons(shape, clip):
			var cp := clean(part)
			if cp.size() >= 3 and absf(_area(cp)) > 0.5:     # (a sliver of a fill fails the triangulator)
				ci.draw_colored_polygon(cp, Color(col, 0.9 if fill >= 1.0 else 0.7))
		if fill < 1.0:                                  # the goo's lit surface while it climbs
			ci.draw_line(Vector2(c.x - h * 0.42 * (1.0 - maxf(0.0, (1.0 - fill) - 0.62) * 2.0), y), Vector2(c.x + h * 0.42 * (1.0 - maxf(0.0, (1.0 - fill) - 0.62) * 2.0), y),
					Color(col.lerp(Color.WHITE, 0.5), 0.9), maxf(1.0, 1.2 * s), true)
	var loop := shape.duplicate()
	loop.append(shape[0])
	neon(ci, loop, col if fill >= 1.0 else col.darkened(0.15), maxf(1.0, 1.3 * s), glow if fill >= 1.0 else 0.0, 1.0 if fill > 0.0 else 0.6)


static func shields_row(ci: CanvasItem, centre: Vector2, h: float, armour: float, cap: float, col: Color, s: float, t: float) -> Rect2:
	## The row of shields under a vat's badge: one per 0.1 of the cap; the one filling breathes. Returns its rect.
	var n := shield_count(cap)
	if n <= 0:
		return Rect2()
	var w := h * 0.84
	var gap := 2.0 * s
	var total := n * w + (n - 1) * gap
	var x0 := centre.x - total / 2.0 + w / 2.0
	for i in range(n):
		var f := shield_fill(i, armour)
		var g := 0.5 + 0.5 * sin(t * 5.0) if f > 0.0 and f < 1.0 else 0.7
		shield(ci, Vector2(x0 + i * (w + gap), centre.y), h, f, col, s, g)
	return Rect2(centre - Vector2(total / 2.0, h / 2.0), Vector2(total, h))


# ------------------------------------------------------------------ tier chip (decided: T1-T4 chips)
static func tier_chip(ci: CanvasItem, centre: Vector2, h: float, tier: int, col: Color, font: Font, s: float, label := "") -> Rect2:
	## A small hex-ended glass chip, "T2", its rim in the node's colour. Returns its rect.
	var txt := label if label != "" else "T%d" % tier
	var fs := int(round(h * 0.72))
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + h * 0.9
	var r := Rect2(centre - Vector2(w, h) / 2.0, Vector2(w, h))
	if HudNoir.has("node_tier_chip"):                  # DROP-IN: a 9-slice chip (its width follows the text)
		ci.draw_style_box(HudNoir.box("node_tier_chip", col, Vector4.ZERO), r)
	else:
		var e := h * 0.32
		var pts := PackedVector2Array([r.position + Vector2(e, 0), Vector2(r.end.x - e, r.position.y), Vector2(r.end.x, centre.y),
				Vector2(r.end.x - e, r.end.y), r.position + Vector2(e, h), Vector2(r.position.x, centre.y)])
		glass(ci, pts, 0.92)
		var loop := pts.duplicate()
		loop.append(pts[0])
		neon(ci, loop, col, maxf(1.0, 1.3 * s), 0.5)
	var base := Vector2(centre.x - tw / 2.0, centre.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0)
	ci.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3 * s), Color(0, 0, 0, 0.8))
	ci.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudNoir.INK)
	return r


# ------------------------------------------------------------------ pills (the send label, the relay hint)
static func pill(ci: CanvasItem, centre: Vector2, txt: String, col: Color, font: Font, fs: int, s: float, ink := HudNoir.INK) -> Rect2:
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var h := font.get_height(fs) + 8.0 * s
	var r := Rect2(centre - Vector2(sz.x + 20.0 * s, h) / 2.0, Vector2(sz.x + 20.0 * s, h))
	if HudNoir.has("node_label_pill"):                 # DROP-IN: a 9-slice pill (its width follows the words)
		ci.draw_style_box(HudNoir.box("node_label_pill", col, Vector4.ZERO), r)
	else:
		var pts := NoirBox.rounded(r, h / 2.0)
		glass(ci, pts, 0.9)
		pts.append(pts[0])
		neon(ci, pts, col, maxf(1.0, 1.5 * s), 0.6)
	var base := Vector2(centre.x - sz.x / 2.0, centre.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0)
	ci.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	return r


# ------------------------------------------------------------------ the send ribbon (the attack direction arrow)
static func tube(ci: CanvasItem, c: PackedVector2Array, col: Color, w: float, lit := 1.0) -> void:
	## A real neon tube (Daniele 2026-11-04: "should be neonish"): a wide bloom, a halo, the coloured tube, a white-hot core.
	if c.size() < 2:
		return
	for k in [[8.0, 0.10], [5.0, 0.18], [3.0, 0.32]]:
		ci.draw_polyline(c, Color(col, float(k[1]) * lit), w * float(k[0]), true)
	ci.draw_polyline(c, Color(col.lerp(Color.WHITE, 0.15), 0.98), w, true)
	ci.draw_polyline(c, Color(col.lerp(Color.WHITE, 0.85), 0.95 * lit), maxf(w * 0.4, 1.0), true)


static func ribbon(ci: CanvasItem, line: PackedVector2Array, col: Color, s: float, t: float, ok := true) -> void:
	## The send arrow as a GOO STREAM (Daniele 2026-11-04: "the attack arrow should be more in theme"): a thick tube of lit ooze
	## with a dark skin and a wet highlight, fat blobs swelling and travelling toward the target, a drop-shaped head. A blocked
	## route: a broken red neon dash, no flow.
	if line.size() < 2:
		return
	var w := 8.0 * s
	if not ok:
		var total0 := 0.0
		for i in range(line.size() - 1):
			total0 += line[i].distance_to(line[i + 1])
		var a0 := line[0]
		var b0 := line[-1]
		var n0 := maxi(2, int(total0 / (14.0 * s)))
		for k in range(0, n0, 2):
			tube(ci, PackedVector2Array([a0.lerp(b0, float(k) / n0), a0.lerp(b0, float(k + 1) / n0)]), col, 3.0 * s, 0.8)
		return
	var lens := PackedFloat32Array([0.0])
	for i in range(line.size() - 1):
		lens.append(lens[-1] + line[i].distance_to(line[i + 1]))
	var total: float = lens[-1]
	var at_len := func(d: float) -> Array:            # [point, direction] at length d along the line
		var i := 0
		while i < line.size() - 2 and lens[i + 1] < d:
			i += 1
		var seg := maxf(lens[i + 1] - lens[i], 0.001)
		return [line[i].lerp(line[i + 1], clampf((d - lens[i]) / seg, 0.0, 1.0)), (line[i + 1] - line[i]).normalized()]
	# the stream's body: a bloom, a dark skin, the goo, a highlight along the upper side
	ci.draw_polyline(line, Color(col, 0.10), w * 3.2, true)
	ci.draw_polyline(line, Color(col.darkened(0.6), 0.9), w * 1.25, true)
	ci.draw_polyline(line, Color(col.darkened(0.1), 0.95), w, true)
	ci.draw_polyline(line, Color(col.lerp(Color.WHITE, 0.25), 0.9), w * 0.55, true)
	var hi := PackedVector2Array()
	for k in range(int(total / (6.0 * s)) + 1):
		var r: Array = at_len.call(minf(k * 6.0 * s, total))
		var d: Vector2 = r[1]
		hi.append((r[0] as Vector2) + Vector2(d.y, -d.x).normalized() * w * 0.22 * (1.0 if d.x >= 0.0 else -1.0))
	if hi.size() > 1:
		ci.draw_polyline(hi, Color(1, 1, 1, 0.45), maxf(1.0, 1.4 * s), true)
	# blobs: swollen lumps of goo flowing to the target (each with a dark rim and a glint)
	var step := 34.0 * s
	var at := fposmod(t * 60.0 * s, step)
	var j := 0
	while at < total - 16.0 * s:
		var r2: Array = at_len.call(at)
		var p: Vector2 = r2[0]
		var swell := 1.0 + 0.25 * sin(t * 6.0 + j * 1.7)
		var br := w * 0.78 * swell
		ci.draw_circle(p, br * 1.2, Color(col.darkened(0.6), 0.85))
		ci.draw_circle(p, br, Color(col.lerp(Color.WHITE, 0.12), 1.0))
		ci.draw_circle(p - Vector2(br, br) * 0.35, br * 0.32, Color(1, 1, 1, 0.75))
		at += step
		j += 1
	# the head: a fat drop pointing along the last segment
	var tip := line[-1]
	var dir := (line[-1] - line[-2]).normalized()
	var side := Vector2(-dir.y, dir.x)
	if not sprite(ci, "node_send_head", tip - dir * 7.0 * s, Vector2(22, 22) * s, col, dir.angle()):
		var c := tip - dir * 9.0 * s
		var drop := PackedVector2Array()
		for k in range(13):                          # the round back of the drop: one side, round the back, the other side
			var ang := PI * float(k) / 12.0
			drop.append(c + (side * cos(ang) - dir * sin(ang)) * 8.0 * s)
		drop.append(tip + dir * 3.0 * s)               # the point
		ci.draw_colored_polygon(drop, Color(col.darkened(0.55), 0.9))
		var inner := PackedVector2Array()
		for q in drop:
			inner.append(c + (q - c) * 0.78)
		ci.draw_colored_polygon(inner, Color(col.lerp(Color.WHITE, 0.15), 1.0))
		ci.draw_circle(c - dir * 2.5 * s + side * 2.5 * s, 2.2 * s, Color(1, 1, 1, 0.8))


static func target_hex(ci: CanvasItem, c: Vector2, r: float, col: Color, s: float, t: float, word := "", lock := 1.0) -> void:
	## The snapped target / the HOLD ring as a REAL neon hexagon (bloom, halo, tube, white-hot core), corner brackets turning
	## slowly; `lock` 0 -> 1 over the first instant on a new target: it snaps in from wider and flickers like a tube striking.
	var k := clampf(lock, 0.0, 1.0)
	var breathe := 1.0 + 0.035 * sin(t * 5.0)
	var rr := r * breathe * (1.0 + 0.35 * (1.0 - k) * (1.0 - k))
	var flick := 1.0 if k >= 1.0 else (0.35 + 0.65 * absf(sin(k * 31.0)))
	if not sprite(ci, "node_target_ring", c, Vector2(rr, rr) * 2.0, Color(col, flick)):
		ci.draw_colored_polygon(hexagon(c, rr, PI / 6.0).slice(0, 6), Color(col, 0.07 * flick))   # a faint lit wash inside
		tube(ci, hexagon(c, rr, PI / 6.0), col, maxf(3.6 * s, 2.6), flick)
		for i in range(6):                              # corner brackets just outside, slowly turning: "locked on"
			var a := PI / 6.0 + TAU * i / 6.0 + t * 0.6
			var p := c + Vector2(cos(a), sin(a)) * (rr + 8.0 * s)
			var ta := Vector2(-sin(a), cos(a))
			tube(ci, PackedVector2Array([p - ta * 6.0 * s, p, p + Vector2(cos(a), sin(a)) * 6.0 * s]), col, maxf(2.0 * s, 1.5), 0.7 * flick)


static func burst(ci: CanvasItem, c: Vector2, r: float, col: Color, k: float, s: float) -> void:
	## A capture: two hexagons blooming out of the node in the new owner's colour, k 0 -> 1, a flash of goo at the start.
	if not sprite(ci, "node_capture_burst", c, Vector2.ONE * r * 2.0 * (0.8 + 0.7 * k), Color(col, 1.0 - k)):
		neon(ci, hexagon(c, r * (0.8 + 0.7 * k), PI / 6.0), col, (4.0 * (1.0 - k) + 1.0) * s, 1.0, 1.0 - k)
		neon(ci, hexagon(c, r * (0.6 + 0.35 * k), PI / 6.0), Color.WHITE, 2.0 * s, 0.0, (1.0 - k) * 0.8)
	if k < 0.35:
		ci.draw_circle(c, r * 0.55, Color(col, 0.35 * (1.0 - k / 0.35)))
