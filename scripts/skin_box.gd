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


func _draw(ci: RID, r: Rect2) -> void:
	if texture == null or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rid := texture.get_rid()
	if axis == "fixed" or slice == Vector4.ZERO:
		var kf := minf(r.size.x / region.size.x, r.size.y / region.size.y)
		var d := region.size * kf
		RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(r.position + (r.size - d) / 2.0, d), rid, region, modulate)
		return
	var k := r.size.y / region.size.y if axis == "x" else scale
	k = minf(k, r.size.x / maxf(1.0, slice.x + slice.z))  # margins never overlap: a short or narrow box shrinks them
	k = minf(k, r.size.y / maxf(1.0, slice.y + slice.w))
	var sx := [0.0, slice.x, region.size.x - slice.z, region.size.x]
	var sy := [0.0, slice.y, region.size.y - slice.w, region.size.y]
	var dx := [0.0, slice.x * k, r.size.x - slice.z * k, r.size.x]
	var dy := [0.0, slice.y * k, r.size.y - slice.w * k, r.size.y]
	for j in 3:
		for i in 3:
			var src := Rect2(region.position + Vector2(sx[i], sy[j]), Vector2(sx[i + 1] - sx[i], sy[j + 1] - sy[j]))
			var dst := Rect2(r.position + Vector2(dx[i], dy[j]), Vector2(dx[i + 1] - dx[i], dy[j + 1] - dy[j]))
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				RenderingServer.canvas_item_add_texture_rect_region(ci, dst, rid, src, modulate)
