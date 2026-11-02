class_name SkinBox
extends StyleBox
## Alpha 24 (UI round 3): one sprite of Daniele's round-3 pack as a StyleBox - a 9-slice drawn at a chosen scale (the art
## is ~3x the size it shows at; StyleBoxTexture can only draw its margins 1:1). `axis` is the manifest's stretch_axis:
##   "xy"    the usual 9-slice: the corners keep `scale`, the edges and centre stretch
##   "x"     the height is the source's, scaled to the box (corners grow with it): only the middle column stretches - a
##           socket, badge or pointer on the left / right never squashes (A4 card_selected, A12 callout, G11 mission...)
##   "fixed" no slicing: the whole sprite, aspect kept, centred in the box
## Built by UiTheme.box(); draws with the texture's mipmaps when the control filters LINEAR_WITH_MIPMAPS.

var texture: Texture2D
var region := Rect2()                              # the sprite in its atlas (the manifest's object_rect)
var slice := Vector4.ZERO                          # margins left, top, right, bottom inside `region`, source px
var axis := "xy"
var scale := 0.4                                   # source px -> canvas units, for "xy"
var modulate := Color.WHITE
var rim: Texture2D                                 # Neon Noir drop-in (HudNoir): a white RIM + GLOW layer cut to the same cell,
var rim_modulate := Color.WHITE                    # drawn over `texture` with the same slicing, tinted per seat / faction


func _draw(ci: RID, r: Rect2) -> void:
	if texture == null or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	_draw_layer(ci, r, texture.get_rid(), modulate)
	if rim != null:
		_draw_layer(ci, r, rim.get_rid(), rim_modulate)


func _draw_layer(ci: RID, r: Rect2, rid: RID, mod: Color) -> void:
	if axis == "fixed" or slice == Vector4.ZERO:
		var kf := minf(r.size.x / region.size.x, r.size.y / region.size.y)
		var d := region.size * kf
		RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(r.position + (r.size - d) / 2.0, d), rid, region, mod)
		return
	var ky := r.size.y / region.size.y if axis == "x" else scale
	ky = minf(ky, r.size.y / maxf(1.0, slice.y + slice.w))
	var sx := [0.0, slice.x, region.size.x - slice.z, region.size.x]
	var sy := [0.0, slice.y, region.size.y - slice.w, region.size.y]
	var dx := [0.0, slice.x * ky, r.size.x - slice.z * ky, r.size.x]
	var dy := [0.0, slice.y * ky, r.size.y - slice.w * ky, r.size.y]
	if dx[1] >= dx[2]:
		# narrower than both caps: each cap is cut down to its outer part at the same scale (a short pill like ON / OFF is
		# the same pill, just shorter)
		var half := r.size.x / 2.0
		sx = [0.0, half / ky, region.size.x - half / ky, region.size.x]
		dx = [0.0, half, half, r.size.x]
	# the centre is never squeezed: a box shorter than the art samples only that much of the middle, at the corners' scale
	# (a 320 px middle squeezed into a few px picked a tiny mip level and drew a grey line down a short pill)
	var cw: float = minf(sx[2] - sx[1], (dx[2] - dx[1]) / ky)
	var mx: float = (sx[1] + sx[2]) / 2.0
	var ch: float = minf(sy[2] - sy[1], (dy[2] - dy[1]) / ky)
	var my: float = (sy[1] + sy[2]) / 2.0
	var cols := [[sx[0], sx[1]], [mx - cw / 2.0, mx + cw / 2.0], [sx[2], sx[3]]]   # source spans: cap, middle, cap
	var rows := [[sy[0], sy[1]], [my - ch / 2.0, my + ch / 2.0], [sy[2], sy[3]]]
	for j in 3:
		for i in 3:
			var src := Rect2(region.position + Vector2(cols[i][0], rows[j][0]),
					Vector2(cols[i][1] - cols[i][0], rows[j][1] - rows[j][0]))
			var dst := Rect2(r.position + Vector2(dx[i], dy[j]), Vector2(dx[i + 1] - dx[i], dy[j + 1] - dy[j]))
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				RenderingServer.canvas_item_add_texture_rect_region(ci, dst, rid, src, mod)
