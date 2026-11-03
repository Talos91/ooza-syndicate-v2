class_name NoirBox
extends StyleBox
## Alpha 24 step 2, Neon Noir (Daniele 2026-11-02, the art director's board C): the in-match HUD's placeholder look, drawn in code
## until the director's cut sprites land (HudNoir.box swaps any part for its sprite without touching layout code).
##   smoked graphite glass   a rounded slab, #16212C at the top to #0E1620 at the belly, the board faintly through it; a crisp
##                           bevel along the top edge, a soft inner shadow along the bottom
##   neon tube rim           `rim` (the accent channel: the player's faction colour, or a fixed meaning colour) with a hot white
##                           core and a halo bleeding into the dark
##   living ooze             `ooze` px of lit goo pooled in the bottom of a container, its surface wavy, a few bubbles
##   drips                   containers only (`drip` px reserved under the slab, inside the rect): goo streams with a bead each
##   filled                  a picked button: the whole slab is lit ooze in the rim colour (its words dark), a wet gloss
## Shapes come from the box size and a seed, so the same panel always drips the same way.

const GLASS_TOP := Color("16212c")
const GLASS_LOW := Color("0e1620")

var rim := Color("19d6ea")
var rim_a := 0.95                                 # the tube's own alpha (sections inside a housing: faint)
var glow := 1.0                                   # 0 = no halo ... 1 = full neon
var fill_a := 0.84                                # the glass body's alpha
var tint := Color(0, 0, 0, 0)                     # a meaning colour mixed into the glass (the red status pill)
var radius := 12.0
var rim_w := 2.0
var drip := 0.0                                   # px under the slab for the drips (0: none - tappable things never drip)
var ooze := 0.0                                   # px of living ooze pooled in the slab's bottom (0: none)
var filled := false
var dim := false                                  # disabled / out: the rim sinks to grey, no halo
var gloss := true                                 # the wet streak along the top-left
var seed := 0


static func rounded(r: Rect2, rad: float, seg := 6) -> PackedVector2Array:
	## A rounded rectangle's outline, clockwise from the top-left corner.
	var pts := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var cs := [Vector2(r.position.x + rad, r.position.y + rad), Vector2(r.end.x - rad, r.position.y + rad),
			Vector2(r.end.x - rad, r.end.y - rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for c in range(4):
		for k in range(seg + 1):
			var a := PI + PI * 0.5 * float(c) + PI * 0.5 * float(k) / float(seg)
			pts.append((cs[c] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return pts


func _rim() -> Color:
	return rim.lerp(Color("5a6672"), 0.6) if dim else rim


func _drips(slab: Rect2) -> Array:
	## [x, length, stream half-width, bead radius] per drip, placed from the seed: 2 on a narrow slab, 3 on a wide one.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, int(slab.size.x), int(slab.size.y)])
	var rad := minf(radius, slab.size.x * 0.5)
	var w := slab.size.x - 2.0 * rad
	var n := 2 if w < 110.0 else 3
	var out := []
	for i in range(n):
		var u := (float(i) + 0.5 + rng.randf_range(-0.25, 0.25)) / float(n)
		var bead := drip * rng.randf_range(0.19, 0.25)
		var hang := drip * rng.randf_range(0.6, 1.0) - bead     # the bead's centre under the slab's foot
		out.append([slab.position.x + rad + w * u, hang, bead * rng.randf_range(0.42, 0.55), bead])
	return out


func _draw(ci: RID, r: Rect2) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var slab := Rect2(r.position, Vector2(r.size.x, maxf(r.size.y - drip, 4.0)))
	var pts := rounded(slab, radius)
	var loop := pts.duplicate()
	loop.append(pts[0])
	var rc := _rim()
	var g := 0.0 if dim else glow
	if g > 0.0:                                        # the halo: wide faint strokes under the tube
		for k in [[13.0, 0.05], [8.0, 0.08], [4.5, 0.12]]:
			RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rc, float(k[1]) * g)]), float(k[0]) * rim_w * 0.5, true)
	# the body: smoked glass (or lit ooze), lighter at the top, a thicker darker belly
	var top_c: Color
	var low_c: Color
	if filled:
		var lit := rc if not dim else rc.darkened(0.4)
		top_c = Color(lit.lerp(Color.WHITE, 0.16), 0.97)
		low_c = Color(lit.darkened(0.3), 0.97)
	else:
		top_c = Color(GLASS_TOP.lerp(tint, tint.a * 0.5), fill_a)
		low_c = Color(GLASS_LOW.lerp(tint, tint.a * 0.3), fill_a)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top_c.lerp(low_c, clampf((p.y - slab.position.y) / slab.size.y, 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, 7, int(slab.size.x)])
	if ooze > 0.0 and not filled:                      # living ooze pooled in the bottom, under a wavy surface
		var rad0 := minf(radius, minf(slab.size.x, slab.size.y) * 0.5)
		var surf := slab.end.y - ooze
		var amp := minf(ooze * 0.14, 3.0 * rim_w)
		var x_in := func(y: float) -> Vector2:          # the slab's inside at height y (its rounded corners)
			var dy := maxf(y - (slab.end.y - rad0), (slab.position.y + rad0) - y)
			var dx := rad0 - sqrt(maxf(rad0 * rad0 - dy * dy, 0.0)) if dy > 0.0 else 0.0
			return Vector2(slab.position.x + dx + rim_w * 0.5, slab.end.x - dx - rim_w * 0.5)
		var ends: Vector2 = x_in.call(surf)
		var opts := PackedVector2Array()
		var ocol := PackedColorArray()
		var line := PackedVector2Array()
		for k in range(25):                            # the surface, left to right
			var x := lerpf(ends.x, ends.y, float(k) / 24.0)
			var u := (x - slab.position.x) / slab.size.x
			var y := surf + (sin(u * TAU * 1.5 + float(seed)) * 0.7 + sin(u * TAU * 3.7 + float(seed) * 2.0) * 0.3) * amp * sin(PI * float(k) / 24.0)
			opts.append(Vector2(x, y))
			ocol.append(Color(rc, 0.2))
			line.append(Vector2(x, y))
		for k in range(13):                            # the foot, right to left along the rounded bottom
			var y := lerpf(surf, slab.end.y - rim_w * 0.5, float(k + 1) / 13.0)
			var xi: Vector2 = x_in.call(y)
			opts.append(Vector2(xi.y, y))
			ocol.append(Color(rc, lerpf(0.2, 0.42, float(k + 1) / 13.0)))
		for k in range(12, -1, -1):
			var y := lerpf(surf, slab.end.y - rim_w * 0.5, float(k + 1) / 13.0)
			var xi: Vector2 = x_in.call(y)
			opts.append(Vector2(xi.x, y))
			ocol.append(Color(rc, lerpf(0.2, 0.42, float(k + 1) / 13.0)))
		RenderingServer.canvas_item_add_polygon(ci, opts, ocol)
		RenderingServer.canvas_item_add_polyline(ci, line, PackedColorArray([Color(rc.lerp(Color.WHITE, 0.35), 0.6)]), maxf(rim_w * 0.6, 1.0), true)
		for i in range(int(slab.size.x / 28.0) + 1):     # suspended bubbles
			var b := Vector2(rng.randf_range(ends.x + rad0 * 0.5, ends.y - rad0 * 0.5), rng.randf_range(surf + ooze * 0.35, slab.end.y - rim_w * 2.5))
			RenderingServer.canvas_item_add_circle(ci, b, maxf(rim_w * rng.randf_range(0.5, 0.9), 1.0), Color(rc.lerp(Color.WHITE, 0.5), 0.35))
	if filled:                                         # lit ooze: a few bubbles suspended in it
		for i in range(3):
			var b := Vector2(slab.position.x + slab.size.x * rng.randf_range(0.2, 0.85), slab.position.y + slab.size.y * rng.randf_range(0.5, 0.82))
			RenderingServer.canvas_item_add_circle(ci, b, maxf(rim_w * rng.randf_range(0.6, 1.1), 1.0), Color(1, 1, 1, 0.22))
	# the bevel: a crisp highlight just under the top edge, a soft shadow above the bottom one
	var rad := minf(radius, minf(slab.size.x, slab.size.y) * 0.5)
	var by := slab.position.y + rim_w * 1.6
	RenderingServer.canvas_item_add_line(ci, Vector2(slab.position.x + rad, by), Vector2(slab.end.x - rad, by),
			Color(1, 1, 1, 0.3 if filled else 0.13), maxf(rim_w * 0.6, 1.0), true)
	if not filled:
		var sy := slab.end.y - rim_w * 1.8
		RenderingServer.canvas_item_add_line(ci, Vector2(slab.position.x + rad, sy), Vector2(slab.end.x - rad, sy), Color(0, 0, 0, 0.3), rim_w * 1.5, true)
	if gloss:                                          # the wet streak, top-left
		var gl := PackedVector2Array()
		for k in range(6):
			var a := PI * 1.06 + PI * 0.36 * float(k) / 5.0
			gl.append(Vector2(slab.position.x + rad, slab.position.y + rad) + Vector2(cos(a), sin(a)) * (rad - rim_w * 2.2))
		RenderingServer.canvas_item_add_polyline(ci, gl, PackedColorArray([Color(1, 1, 1, 0.55 if filled else 0.32)]), maxf(rim_w * 0.9, 1.0), true)
	if drip > 0.0:                                     # the drips: lit goo hanging from the slab's foot - a meniscus, a stream, a bead
		for d in _drips(slab):
			var x: float = d[0]
			var top := slab.end.y - rim_w * 1.5
			var hang: float = d[1]
			var hw: float = d[2]
			var bead: float = d[3]
			var bc := Vector2(x, top + hang)
			var stream := PackedVector2Array()
			var scol := PackedColorArray()
			for k in range(9):                         # the right side down, then the left side up: wide at the foot, waisted
				var v := float(k) / 8.0
				stream.append(Vector2(x + lerpf(hw * 2.6, hw * 0.75, sqrt(v)), top + hang * v))
				scol.append(Color(rc.darkened(0.25 * v), 0.95))
			for k in range(8, -1, -1):
				var v := float(k) / 8.0
				stream.append(Vector2(x - lerpf(hw * 2.6, hw * 0.75, sqrt(v)), top + hang * v))
				scol.append(Color(rc.darkened(0.25 * v), 0.95))
			if g > 0.0:
				RenderingServer.canvas_item_add_circle(ci, bc, bead + 3.0 * rim_w * 0.5, Color(rc, 0.16 * g))
			RenderingServer.canvas_item_add_polygon(ci, stream, scol)
			RenderingServer.canvas_item_add_circle(ci, bc, bead, Color(rc.darkened(0.2), 0.97))
			RenderingServer.canvas_item_add_line(ci, Vector2(x - hw * 0.25, top + hang * 0.15), Vector2(x - hw * 0.15, top + hang * 0.75), Color(1, 1, 1, 0.35), maxf(hw * 0.35, 1.0), true)
			RenderingServer.canvas_item_add_circle(ci, bc + Vector2(-bead * 0.35, -bead * 0.35), maxf(bead * 0.3, 1.0), Color(1, 1, 1, 0.65))
	RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rc, rim_a * (0.6 if dim else 1.0))]), rim_w, true)
	if g > 0.0:                                        # the tube's hot core
		RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(rc.lerp(Color.WHITE, 0.65), 0.55 * g * rim_a)]), maxf(rim_w * 0.4, 1.0), true)
