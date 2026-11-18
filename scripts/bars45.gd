class_name Bars45
extends RefCounted
## The header / nav ornaments of the remake (IMPORT-45B-SPEC fix 1, designer 11, Daniele 11-18): the FLUTED-TRIM dash rule
## at mockup size (never scaled down) and the 3.75 pt BOLTs in the four corners of a bar, from the approved ARMIES pack.

const BOLT_PT := 3.75
const BOLT_IN := 5.0                                 # pt from the bar's edges to the bolt's centre


static func ornament(parent: Control, n: String, r: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Kit45.art(n)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = r.position
	t.size = r.size
	parent.add_child(t)
	return t


static func bolts(parent: Control, sz: Vector2, u: float) -> void:
	var b := BOLT_PT * u
	var i := BOLT_IN * u
	for c in [Vector2(i, i), Vector2(sz.x - i, i), Vector2(i, sz.y - i), Vector2(sz.x - i, sz.y - i)]:
		ornament(parent, "BOLT", Rect2(c - Vector2(b, b) / 2.0, Vector2(b, b)))
