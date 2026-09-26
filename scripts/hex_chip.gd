class_name HexChip
extends Button
## A colour-picker chip (0.19.0, Daniele: "the actual hexagon should be in full color of the actual
## color, no words, border same color"): a hexagon filled solid in its colour, border the same colour,
## no text. FACTION has no single colour: its hexagon splits into wedges, one per faction. Because the
## border matches the fill, the picked chip needs another cue: a white outer ring plus a slight scale-up
## (Daniele: "a white (or light) outer ring or glow plus a slight scale-up on the picked chip"). Every
## chip keeps its colour name as `tooltip_text` (also read out via Control's accessible name) so a
## colour-blind player can still tell them apart.

var fill := Color.WHITE                # a solid hue chip
var wedges: Array = []                 # non-empty: a FACTION-style split hexagon instead (one Color per wedge)
var picked := false:
	set(v):
		picked = v
		scale = Vector2.ONE * (1.12 if v else 1.0)
		queue_redraw()


func _ready() -> void:
	flat = true
	text = ""
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	resized.connect(func(): pivot_offset = size / 2.0)


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) / 2.0 - 3.0
	var pts := PackedVector2Array()
	for k in range(6):
		var a := TAU * k / 6.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var dim := disabled
	if wedges.is_empty():
		draw_colored_polygon(pts, fill if not dim else Color(fill, 0.28))
	else:
		for k in range(wedges.size()):
			var a0 := TAU * k / wedges.size() - PI / 2.0
			var a1 := TAU * (k + 1) / wedges.size() - PI / 2.0
			var tri := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r])
			draw_colored_polygon(tri, wedges[k] if not dim else Color(wedges[k], 0.28))
	var edge := pts.duplicate()
	edge.append(pts[0])
	var border: Color = fill if wedges.is_empty() else Color.WHITE
	draw_polyline(edge, border if not dim else Color(0.4, 0.44, 0.47), 3.0, true)
	if picked:
		var ring := PackedVector2Array()
		for k in range(6):
			var a := TAU * k / 6.0 - PI / 2.0
			ring.append(c + Vector2(cos(a), sin(a)) * (r + 6.0))
		ring.append(ring[0])
		draw_polyline(ring, Color(1, 1, 1, 0.95), 3.5, true)
