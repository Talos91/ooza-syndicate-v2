class_name GooBox
extends StyleBox
## Alpha 24 step 2, neon pass (Daniele 2026-11-02 on the first HUD restyle: "a regression in style", "buttons should have an
## oozie feel, now are flat ovals"): a HUD button / card drawn as a lit blob of ooze - a rounded slab whose lower edge sags into
## a few drips, a dark glassy (or, `filled`, a lit) body, a slime gloss along the top, and a neon rim with its glow round the
## whole shape. The drips sit inside the box's bottom `drip` px, so the box never draws past its rect except the glow.
## Shape per box size, drips placed from a seed (the same button always drips the same way).

var accent := Color("2ee6ff")                     # the rim, the glow and (filled) the body
var filled := false                               # a picked / lit button: the body is the accent, its words dark
var fill := Color(0.03, 0.06, 0.09, 0.82)         # the glass body when not filled
var radius := 12.0
var drip := 7.0                                   # how far the drips hang (px), inside the rect
var glow := 1.0                                   # 0 = no glow ... 1 = full neon
var rim_w := 2.0
var seed := 0
var dim := false                                  # disabled / cooling: the rim and glow sink


func _outline(r: Rect2) -> PackedVector2Array:
	## The blob's outline, clockwise from the top-left corner: rounded top corners, sides, then a sagging, dripping bottom.
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.45)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var yb := r.end.y - drip                          # the bottom edge the drips hang from
	for k in range(7):                                # top-left corner
		var a := PI + PI * 0.5 * k / 6.0
		pts.append(Vector2(x0 + rad, y0 + rad) + Vector2(cos(a), sin(a)) * rad)
	for k in range(7):                                # top-right
		var a := -PI * 0.5 + PI * 0.5 * k / 6.0
		pts.append(Vector2(x1 - rad, y0 + rad) + Vector2(cos(a), sin(a)) * rad)
	for k in range(7):                                # bottom-right (a softer, wetter corner)
		var a := PI * 0.5 * k / 6.0
		pts.append(Vector2(x1 - rad, yb - rad) + Vector2(cos(a), sin(a)) * rad)
	# the bottom, right to left: a gentle wobble, and 2-3 drips - a stream with a meniscus at the top (the drop itself is a
	# round bead drawn at its end, _drops)
	var w := x1 - x0 - 2.0 * rad
	var steps := 48
	for k in range(steps + 1):
		var u := 1.0 - float(k) / float(steps)         # right to left
		var x := x0 + rad + w * u
		var y := yb + sin(u * PI) * drip * 0.12 + sin(u * TAU * 2.0 + float(seed)) * drip * 0.05
		for d in _drops(r):
			var dx: float = (x - float(d[0])) / float(d[2])
			y += (float(d[1]) - float(d[3])) * exp(-dx * dx)
		pts.append(Vector2(x, minf(y, r.end.y)))
	for k in range(7):                                # bottom-left
		var a := PI * 0.5 + PI * 0.5 * k / 6.0
		pts.append(Vector2(x0 + rad, yb - rad) + Vector2(cos(a), sin(a)) * rad)
	return pts


func _drops(r: Rect2) -> Array:
	## The drips of this box: [x, length, stream half-width, bead radius] (px), placed from the seed.
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.45)
	var w := r.size.x - 2.0 * rad
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, int(r.size.x), int(r.size.y)])
	var out := []
	var n := 2 if w < 80.0 else 3
	for i in range(n):
		var c := (float(i) + 0.5 + rng.randf_range(-0.22, 0.22)) / float(n)
		var bead := drip * rng.randf_range(0.26, 0.34)
		out.append([r.position.x + rad + w * c, drip * rng.randf_range(0.6, 1.0), drip * rng.randf_range(0.32, 0.45), bead])
	return out


func _draw(ci: RID, r: Rect2) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var pts := _outline(r)
	var loop := pts.duplicate()
	loop.append(pts[0])
	var g := glow * (0.45 if dim else 1.0)
	var rim := accent if not dim else accent.lerp(Color(0.45, 0.52, 0.58), 0.55)
	if g > 0.0:                                        # the neon halo: wide, faint strokes under the rim
		for gw in [14.0, 8.0, 4.5]:
			RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rim, 0.07 * g)]), gw * rim_w * 0.5, true)
	var body := Color(accent.lerp(Color.WHITE, 0.08), 0.96) if filled else fill
	if dim and filled:
		body = Color(body, 0.5)
	# one gradient body: a lighter, tinted top fading to a thicker, darker belly toward the drips
	var top_c := body.lerp(Color(rim.lightened(0.3), body.a), 0.18 if filled else 0.1)
	var low_c := body.lerp(Color(0, 0, 0, body.a), 0.3 if filled else 0.35)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top_c.lerp(low_c, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	# the drops: a round bead at the end of each stream, in the body's colour with the rim round its lower side
	var yb := r.end.y - drip
	for d in _drops(r):
		var c := Vector2(float(d[0]), minf(yb + float(d[1]) - float(d[3]), r.end.y - float(d[3])))
		var br: float = d[3]
		if g > 0.0:
			RenderingServer.canvas_item_add_circle(ci, c, br + 3.0 * rim_w * 0.5, Color(rim, 0.1 * g))
		RenderingServer.canvas_item_add_circle(ci, c, br, low_c)
		var arc := PackedVector2Array()
		for k in range(13):
			var a := deg_to_rad(-15.0 + 210.0 * k / 12.0)
			arc.append(c + Vector2(cos(a), sin(a)) * br)
		RenderingServer.canvas_item_add_polyline(ci, arc, PackedColorArray([Color(rim, 0.95 if not dim else 0.6)]), rim_w, true)
		RenderingServer.canvas_item_add_circle(ci, c + Vector2(-br * 0.35, -br * 0.35), maxf(br * 0.25, 1.0), Color(1, 1, 1, 0.5 if filled else 0.3))
	# the slime gloss: a thin wet highlight curving along the inside of the top edge, brighter at its left end
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.45)
	var gy := r.position.y + rim_w * 2.2
	var gloss := PackedVector2Array()
	for k in range(9):
		var u := float(k) / 8.0
		gloss.append(Vector2(r.position.x + rad * 0.9 + (r.size.x - rad * 1.8) * u, gy + sin(u * PI) * -0.5 + pow(absf(u - 0.5) * 2.0, 3.0) * rad * 0.35))
	RenderingServer.canvas_item_add_polyline(ci, gloss, PackedColorArray([Color(1, 1, 1, 0.3 if filled else 0.16)]), maxf(rim_w * 0.9, 1.0), true)
	var streak := PackedVector2Array([gloss[0], gloss[1], gloss[2]])
	RenderingServer.canvas_item_add_polyline(ci, streak, PackedColorArray([Color(1, 1, 1, 0.6 if filled else 0.4)]), maxf(rim_w * 1.2, 1.5), true)
	RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rim, 0.95 if not dim else 0.6)]), rim_w, true)
	if g > 0.0:                                        # the tube's hot core
		RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rim.lightened(0.6), 0.45 * g)]), maxf(rim_w * 0.4, 1.0), true)


static func make(accent_col: Color, ui_scale: float, filled_now := false, seed_v := 0, content := 6.0) -> GooBox:
	var b := GooBox.new()
	b.accent = accent_col
	b.filled = filled_now
	b.radius = 12.0 * ui_scale
	b.drip = 11.0 * ui_scale
	b.rim_w = 2.0 * ui_scale
	b.seed = seed_v
	b.set_content_margin_all(content)
	b.content_margin_bottom = content + b.drip * 0.75
	return b


static func glass(accent_col: Color, ui_scale: float, radius_px := 12.0, fill_a := 0.8, glow_k := 0.8) -> StyleBoxFlat:
	## A HUD panel (no drips: the top bar, the SEND panel, a pill): dark glass, a neon rim in accent, its glow.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.06, 0.09, fill_a)
	s.border_color = Color(accent_col, 0.9)
	s.set_border_width_all(maxi(int(round(1.5 * ui_scale)), 1))
	s.set_corner_radius_all(int(radius_px * ui_scale))
	s.shadow_color = Color(accent_col, 0.28 * glow_k)
	s.shadow_size = int(7 * ui_scale)
	s.anti_aliasing = true
	return s
