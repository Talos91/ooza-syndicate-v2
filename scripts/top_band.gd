class_name TopBand
extends RefCounted
## TOP BAND (calm-pass, Daniele on staging 0.24.1, 2026-11-12: "top hud bar covers ingame text"). The score bar and the
## lines under it (the status line LAST STAND · NEXT DROP .., the banner, the catch-up tag) never cover in-world text:
##  - the Last Stand alarm signs and the upgrade chips (HudOverlay) take the band as a place to avoid (they go under or
##    beside their platform instead of over its top rim);
##  - every in-world Label3D (relay glyph beacons, + CAPTURED floaters, tier-down labels, relay tags, skill labels) is in the
##    WORLD_TEXT group and is pushed down on screen, along its own up axis, until its top clears the band (keep_clear,
##    every frame from Hud.sync); its own offset comes back as soon as the band no longer covers it.
## Callouts already avoid the band (Hud.callout_blocked). Dev: --top-band=off is 0.24.1 (the probe's "before").

const GROUP := &"world_text"
const PAD := 12.0                      # px of air between the band and the text (a rising label moves a few px after the keeper)
static var on := not ("--top-band=off" in OS.get_cmdline_user_args())


class Keeper:
	extends Node
	## Runs keep_clear after everything else this frame (process_priority 1000): beacons bob and floaters rise in their
	## owners' _process, so a keeper that ran before them would leave a frame's worth of overlap.
	var hud
	func _ready() -> void:
		process_priority = 1000
	func _process(_dt: float) -> void:
		if hud == null or not is_instance_valid(hud) or hud.main == null:
			return
		var cam: Camera3D = hud.main.cam
		var band: Array = hud.top_band_rects()
		TopBand.keep_clear(get_tree(), cam, band)


static func tag(l: Label3D) -> void:
	l.add_to_group(GROUP)


static func keep_clear(tree: SceneTree, cam: Camera3D, band: Array) -> void:
	if not on or cam == null or band.is_empty():
		return
	for node in tree.get_nodes_in_group(GROUP):
		var l := node as Label3D
		if l == null:
			continue
		if not l.has_meta(&"tb_base"):
			l.set_meta(&"tb_base", l.offset)
		var base: Vector2 = l.get_meta(&"tb_base")
		if l.offset != base and l.get_meta(&"tb_set", Vector2.INF) != l.offset:
			base = l.offset                     # the owner changed the offset itself: that is the new base
			l.set_meta(&"tb_base", base)
		l.offset = base
		if not l.is_visible_in_tree() or l.text == "" or l.modulate.a < 0.05:
			continue
		var r := screen_rect(l, cam)
		if r.size.y <= 0.0:
			continue
		var drop := 0.0
		for b in band:
			var br: Rect2 = b
			if r.position.x < br.end.x and r.end.x > br.position.x and r.position.y < br.end.y + PAD:
				drop = maxf(drop, br.end.y + PAD - r.position.y)
		if drop <= 0.0:
			continue
		var font: Font = l.font if l.font else ThemeDB.fallback_font
		var h_units := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size).y
		var px_per_unit := r.size.y / maxf(h_units, 1.0)
		var off := base - Vector2(0, drop / maxf(px_per_unit, 0.0001))
		l.offset = off
		l.set_meta(&"tb_set", off)


static func screen_rect(l: Label3D, cam: Camera3D) -> Rect2:
	## The label's box on screen (the probe and keep_clear): its text size x pixel_size along the camera axes (billboard) or
	## its own (flat labels), around its position plus its offset.
	var p := l.global_position
	if cam.is_position_behind(p):
		return Rect2()
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size) * l.pixel_size
	var sc := l.global_transform.basis.get_scale()
	sz *= Vector2(sc.x, sc.y)
	var bx := cam.global_transform.basis.x
	var by := cam.global_transform.basis.y
	if l.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		bx = l.global_transform.basis.x.normalized()
		by = l.global_transform.basis.y.normalized()
	elif l.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y:
		by = Vector3.UP
	var off := l.offset * l.pixel_size * Vector2(sc.x, sc.y)   # (a scaled label's offset scales with it)
	var c := p + bx * off.x + by * off.y
	var box := Rect2(cam.unproject_position(c), Vector2.ZERO)
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		box = box.expand(cam.unproject_position(c + bx * (k.x * sz.x * 0.5) + by * (k.y * sz.y * 0.5)))
	return box
