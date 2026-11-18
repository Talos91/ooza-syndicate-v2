class_name PitBackdrop
extends RefCounted
## ROUND 44 B4 MATCH BACKGROUND (Daniele 2026-11-18: "the first final background for the new game mode (the one with rocket
## nodes)"; screen layout: background = pit + near layer behind the HUD + crust, NO sky; the HUD sits on the mounts).
## Source: References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/44-background-B4 (approved,
## untouched); game derivatives at 2x in assets/art/bg44b4 (tools/bg44b4_derive.py, layout.json there).
##  - BACK (the Environment's background canvas, under the 3D map): goo floor (the tile repeated, pit_goo.gdshader), CRUST
##    (full viewport, its lake opening shows the goo), PIT-RIM (wet bank) - one 812 x 375 pt frame whose painted lake is
##    mapped onto THE PIT (main.pit_rect(), the box the 0.25.0 camera fit frames the map in), covering the viewport.
##  - MOUNTS (the HUD's first children, under every HUD control): NEAR-L behind the send tube, NEAR-R behind the skill
##    column, the score ledge behind the timer tube, the utility keys behind SOUND / PAUSE (/ CHAT when it shows), each
##    fitted round its control's rect every frame (sync), so they follow the HUD at every size.
##  - The river world's sky band, canyon, goo plane, cracks and mist are off (the painted pit replaces them).
## On: the QUOTA demo (Rules.quota) with the river world; off with --no-pit-bg.
## VIEW ONLY: nothing in the Sim or the protocol.

const DIR := "res://assets/art/bg44b4/"
const GOO_SHADER := preload("res://shaders/pit_goo.gdshader")
const MIRROR_SHADER := preload("res://shaders/pit_mirror.gdshader")
const MIRROR_BIAS := 4.5 / 255.0      # the goo plane's measured residual vs the 2D background (desktop GL Compatibility shots)
const REF := Vector2(812.0, 375.0)
static var on := false

var main: Node
var hud: Node
var layout: Dictionary = {}
var back: CanvasLayer
var _frame: Control                  # the 812 x 375 pt frame, scaled to cover
var _goo: ColorRect
var _mounts: Dictionary = {}         # id -> TextureRect
var _mount_root: Control
var _vp := Vector2.ZERO
var mirror: ShaderMaterial            # the river's goo plane, painted as the backdrop (pit_mirror.gdshader; WorldRiver uses it)


static func wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	return Rules.quota and Rules.world_layer and not "--no-river" in args and not "--no-pit-bg" in args \
			and ResourceLoader.exists(DIR + "crust.png")


func _tex(f: String) -> Texture2D:
	return load(DIR + f) as Texture2D


func _el(id: String) -> Dictionary:
	return (layout.get("elements", {}) as Dictionary).get(id, {})


func build_back(m: Node) -> CanvasLayer:
	## The background canvas layer (replaces Scenery's sky layer: same layer, drawn by the Environment as the background).
	main = m
	var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
	if f:
		layout = JSON.parse_string(f.get_as_text())
	back = CanvasLayer.new()
	back.layer = -50
	_goo = ColorRect.new()
	_goo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GOO_SHADER
	mat.set_shader_parameter("tile", _tex(str(_el("goo_tile").get("file", "goo_tile.png"))))
	_goo.material = mat
	back.add_child(_goo)                              # full viewport (the crust covers all but the lake)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = REF
	back.add_child(_frame)
	for id in ["crust", "rim"]:
		var e := _el(id)
		var t := TextureRect.new()
		t.texture = _tex(str(e.get("file", id + ".png")))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r: Array = e.get("pt", [0, 0, REF.x, REF.y])
		t.position = Vector2(r[0], r[1])
		t.size = Vector2(r[2], r[3])
		_frame.add_child(t)
	m.add_child(back)
	_relayout(m.get_viewport().get_visible_rect().size)
	return back


var _s := Vector2.ONE                # frame scale (x, y): the painted lake mapped onto main.pit_rect()
var _o := Vector2.ZERO               # frame origin on screen


func _stadium() -> Array:
	## [centre pt, half size pt] of the painted lake's stadium box (layout.json pit_stadium_pt, the 812 x 375 reference).
	var ps: Dictionary = layout.get("pit_stadium_pt", {})
	var c: Array = ps.get("center_pt", [422.24, 213.54])
	return [Vector2(c[0], c[1]), Vector2(float(ps.get("half_width_pt", 298.09)), float(ps.get("end_radius_pt", 144.79)))]


func _fit(vp: Vector2) -> void:
	## The frame's scale and origin: the painted stadium box onto THE PIT (main.pit_rect(), the adaptation rule of layout.json /
	## SCREEN-LAYOUT-SPEC: side margin max(11.25 % safe width, 88 pt k), top 66 pt k, bottom 16 pt k). At 812 x 375 that is
	## the art as painted (596 x 290 pt); other widths stretch the frame to the pit (16:9 narrower, the Fold wider), never
	## less than the viewport (the crust always covers it).
	var st := _stadium()
	var c: Vector2 = st[0]
	var hs: Vector2 = st[1]
	var pr := Rect2(Vector2(c - hs) * minf(vp.x / REF.x, vp.y / REF.y), hs * 2.0 * minf(vp.x / REF.x, vp.y / REF.y))
	if main != null and main.has_method("pit_rect"):
		pr = main.pit_rect()
	_s = Vector2(pr.size.x / (hs.x * 2.0), pr.size.y / (hs.y * 2.0))
	_s = Vector2(maxf(_s.x, vp.x / REF.x), maxf(_s.y, vp.y / REF.y))
	_o = pr.get_center() - c * _s
	_o = Vector2(clampf(_o.x, vp.x - REF.x * _s.x, 0.0), clampf(_o.y, vp.y - REF.y * _s.y, 0.0))
	if grow > 1.0001:                                  # SIZE NUDGE: the pit block grows round the lake centre (place_bases)
		var cen := _o + c * _s
		_s *= grow
		_o = cen - c * _s
	if absf(drop_pt) > 0.001:                         # DROP (Daniele 11-18): the painted pit block lower by drop_pt (pt of the frame)
		var cy := _o.y + c.y * _s.y + drop_pt * _s.y   # the lake centre's new screen y
		_o.y += drop_pt * _s.y
		if _o.y > 0.0:                                # the crust must still reach the screen top: stretch the frame down from y 0
			_s.y = cy / c.y
			_o.y = 0.0
		elif _o.y + REF.y * _s.y < vp.y:              # (a lift) ... and the bottom
			_s.y = (vp.y - cy) / (REF.y - c.y)
			_o.y = cy - c.y * _s.y


# BASES IN THE LAKE (Daniele 2026-11-18: "the problem is prolly just to move the pit a bit lower ... what needs to be in the pit is
# the bottom of the node (as in the drill) the top can end up visibly outside as long as its base is IN the pit"). A node's base =
# its drill foot at the goo surface (the river world's level at 0:00, WorldRiver.top_y), projected by the fitted start camera; the
# map fit and per-map zoom stay 0.25.0's. drop_pt = the smallest move (pt, + = lower; DROP_RANGE) that lands every base on the lake
# mask (lake_mask.png: the open goo eroded by 2 % of the lake's size); only when no drop does it, the block also grows round the lake
# centre by the smallest step (x1.02 .. GROW_MAX) that does. Picked once the start view is fitted (and again on a resize).
const DROP_RANGE := Vector2(-20.0, 90.0)
var drop_pt := 0.0
var grow := 1.0                       # only when no drop lands every base: the smallest size nudge that does (GROW_MAX)
const GROW_MAX := 1.3
var _mask: Image
var _placed := false
var bases_in := 0
var bases_n := 0


func _bases_screen() -> Array:
	var cam: Camera3D = main.get("cam")
	var sim = main.get("sim")
	if cam == null or sim == null:
		return []
	var y := 0.0
	var wl = main.get("world_layer")
	var lo := INF
	for n in sim.nodes:
		lo = minf(lo, (n["pos"] as Vector3).y)
	y = (wl.river.top_y if wl != null and wl.river != null else minf(lo, 0.0) - 5.0)
	var out := []
	for i in range(sim.nodes.size()):
		if sim.collapsed.has(i):                      # launched / dropped: no base left
			continue
		var p: Vector3 = sim.nodes[i]["pos"]
		out.append(cam.unproject_position(Vector3(p.x, y, p.z)))
	return out


func _inside(q: Vector2) -> bool:
	## screen px -> the frame's pt -> the lake mask (1 px per pt)
	if _mask == null:
		return true
	var f := (q - _o) / _s
	var x := int(floor(f.x))
	var y := int(floor(f.y))
	if x < 0 or y < 0 or x >= _mask.get_width() or y >= _mask.get_height():
		return false
	return _mask.get_pixel(x, y).r > 0.5


func count_inside() -> Array:
	var pts := _bases_screen()
	var k := 0
	for q in pts:
		if _inside(q):
			k += 1
	return [k, pts.size()]


func place_bases() -> void:
	_placed = true
	if _mask == null:
		var t := _tex(str((layout.get("lake_mask", {}) as Dictionary).get("file", "lake_mask.png")))
		_mask = t.get_image() if t != null else null
		if _mask != null and _mask.is_compressed():
			_mask.decompress()
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var best := [-1, 0.0, 1.0]
	var cands: Array = []
	for d in range(int(DROP_RANGE.x), int(DROP_RANGE.y) + 1):
		cands.append(float(d))
	cands.sort_custom(func(a, b): return absf(a) < absf(b) or (absf(a) == absf(b) and a > b))
	var g := 1.0
	while g <= GROW_MAX + 0.0001 and int(best[0]) < _bases_screen().size():
		grow = g
		for d in cands:
			drop_pt = d
			_relayout(vp)
			var c := count_inside()
			if int(c[0]) > int(best[0]):
				best = [int(c[0]), d, g]
			if int(c[0]) == int(c[1]):
				break
		g += 0.02
	grow = best[2]
	drop_pt = best[1]
	_relayout(vp)
	var c2 := count_inside()
	bases_in = c2[0]
	bases_n = c2[1]
	print("PIT DROP %.0f pt, size x%.2f: %d of %d bases inside (viewport %dx%d)" % [drop_pt, grow, bases_in, bases_n, vp.x, vp.y])


func _relayout(vp: Vector2) -> void:
	_vp = vp
	_fit(vp)
	_frame.scale = _s
	_frame.position = _o
	_goo.position = Vector2.ZERO
	_goo.size = vp
	var g := _el("goo_tile")
	var per: Array = g.get("period_pt", [395, 258])
	var an: Array = g.get("anchor_pt", [422.24, 213.54])
	var mat := _goo.material as ShaderMaterial
	mat.set_shader_parameter("rect_px", vp)
	mat.set_shader_parameter("anchor_px", _o + Vector2(an[0], an[1]) * _s)
	mat.set_shader_parameter("period_px", Vector2(per[0], per[1]) * _s)
	if mirror != null:
		_mirror_uniforms(vp)


func mirror_material() -> ShaderMaterial:
	## WorldRiver's goo plane material: the backdrop repainted in screen space (opaque: drills end at the goo surface).
	if mirror == null:
		mirror = ShaderMaterial.new()
		mirror.shader = MIRROR_SHADER
		mirror.set_shader_parameter("goo_tile", _tex(str(_el("goo_tile").get("file", "goo_tile.png"))))
		mirror.set_shader_parameter("crust", _tex(str(_el("crust").get("file", "crust.png"))))
		mirror.set_shader_parameter("rim", _tex(str(_el("rim").get("file", "rim.png"))))
		var r: Array = _el("rim").get("pt", [0, 0, REF.x, REF.y])
		mirror.set_shader_parameter("rim_pt", Vector4(r[0], r[1], r[2], r[3]))
		mirror.set_shader_parameter("ref", REF)
		var env: Environment = main.get_viewport().world_3d.environment if main.get_viewport().world_3d else null
		for e in main.find_children("*", "WorldEnvironment", true, false):
			env = (e as WorldEnvironment).environment
		if env != null:                               # undo the 3D post chain (pit_mirror.gdshader inv_post)
			mirror.set_shader_parameter("tonemap_on", false)   # measured (Compatibility, unshaded): no filmic curve on it
			mirror.set_shader_parameter("srgb_bias", MIRROR_BIAS)
			mirror.set_shader_parameter("exposure", env.tonemap_exposure)
			mirror.set_shader_parameter("white", env.tonemap_white)
			mirror.set_shader_parameter("contrast", env.adjustment_contrast if env.adjustment_enabled else 1.0)
			mirror.set_shader_parameter("saturation", env.adjustment_saturation if env.adjustment_enabled else 1.0)
		if _vp != Vector2.ZERO:
			_mirror_uniforms(_vp)
	return mirror


func _mirror_uniforms(vp: Vector2) -> void:
	var g := _el("goo_tile")
	var per: Array = g.get("period_pt", [395, 258])
	var an: Array = g.get("anchor_pt", [422.24, 213.54])
	mirror.set_shader_parameter("vp", vp)
	mirror.set_shader_parameter("frame_o", _o)
	mirror.set_shader_parameter("frame_s", _s)
	mirror.set_shader_parameter("anchor_px", _o + Vector2(an[0], an[1]) * _s)
	mirror.set_shader_parameter("period_px", Vector2(per[0], per[1]) * _s)


# ------------------------------------------------------------------ the mounts under the HUD
func build_mounts(h: Node) -> void:
	hud = h
	var root: Control = h.get("root")
	if root == null:
		return
	_mount_root = Control.new()
	_mount_root.name = "PitMounts"
	_mount_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_mount_root)
	root.move_child(_mount_root, 0)                   # under every HUD control
	for id in ZONE_OF:
		var e := _el(id)
		if e.is_empty():
			continue
		var t := TextureRect.new()
		t.texture = _tex(str(e["file"]))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.visible = false
		_mount_root.add_child(t)
		_mounts[id] = t
	sync()


# Each mount follows its HUD zone (Hud43.zones, the 0.25.0 HUD the B4 pack was drawn round: ui-build-43b ac44b3c). layout.json
# places them at the 812 x 375 reference with a 32.48 pt left safe inset; there the zones are Hud43.zones in pt at hud unit
# 375 / 360. A mount keeps its offset from its zone's corner and its size, in HUD units. The utility keys are laid by count
# (MUTE, PAUSE, CHAT, DEBUG right-aligned), so their backings sit on the live buttons instead.
const ZONE_OF := {"NEAR-L": "send", "NEAR-R": "skill", "MOUNT-SCORE-LEDGE": "score", "MOUNT-AI-L": "ai_l", "MOUNT-AI-MOOD-L": "ai_l",
		"MOUNT-AI-R": "ai_r", "MOUNT-AI-MOOD-R": "ai_r", "MOUNT-UTILITY-SOUND": "music_button", "MOUNT-UTILITY-PAUSE": "pause_button",
		"MOUNT-UTILITY-CHAT": "chat_button"}
const REF_INSET_L := 32.48
var _ref_zones: Dictionary = {}


func _ref_zone(z: String) -> Rect2:
	## The zone at the pack's reference, in pt (Hud43.zones' formulas, no device: unit = 375 / 360, left inset 32.48 pt).
	if _ref_zones.is_empty():
		var u := UiKit.hud_k_for(375.0) / UiKit.hud_k_for(360.0)
		var l := REF_INSET_L
		var r := REF.x
		var cy := REF.y / 2.0
		var ah := minf(Hud43.AI_PT.y, 66.0 + 2.0 - Hud43.AI_Y)
		_ref_zones = {"u": u,
			"send": Rect2(l, cy - Hud43.COL_H * u / 2.0, Hud43.SEND_W * u, Hud43.COL_H * u),
			"skill": Rect2(r - Hud43.SKILL_W * u, cy - Hud43.COL_H * u / 2.0, Hud43.SKILL_W * u, Hud43.COL_H * u),
			"score": Rect2((l + r) / 2.0 - Hud43.SCORE_PT.x * u / 2.0, 0.0, Hud43.SCORE_PT.x * u, Hud43.SCORE_PT.y * u),
			"ai_l": Rect2(l + Hud43.AI_X * u, Hud43.AI_Y * u, Hud43.AI_PT.x * u, ah * u),
			"ai_r": Rect2(r - (Hud43.AI_X + Hud43.AI_PT.x) * u, Hud43.AI_Y * u, Hud43.AI_PT.x * u, ah * u)}
	return _ref_zones.get(z, Rect2())


func _target(id: String, zones: Dictionary, upx: float) -> Rect2:
	## Where a mount goes now (global px; empty: hidden).
	var e := _el(id)
	var m: Array = e.get("pt", [0, 0, 0, 0])
	var mr := Rect2(m[0], m[1], m[2], m[3])
	var z: String = ZONE_OF[id]
	var k: float = upx / float(_ref_zones.get("u", 1.0))   # px per reference pt
	if z.ends_with("_button"):
		var b: Control = hud.get(z)
		if b == null or not b.is_visible_in_tree():
			return Rect2()
		return Rect2(b.get_global_rect().get_center() - mr.size * k / 2.0, mr.size * k)
	if not zones.has(z):
		return Rect2()
	if z == "skill":
		var d: Control = hud.get("dock")
		if d == null or not d.is_visible_in_tree():
			return Rect2()
	if z.begins_with("ai_") and hud.get("ai_screens") == null:
		return Rect2()
	var zr: Rect2 = zones[z]
	var ref := _ref_zone(z)
	return Rect2(zr.position + (mr.position - ref.position) * k, mr.size * k)


func sync() -> void:
	if back != null and main != null:
		var vp: Vector2 = main.get_viewport().get_visible_rect().size
		if vp != _vp:
			_relayout(vp)
			_placed = false
		if not _placed and bool(main.get("started")) and main.get("cam") != null:
			place_bases()
	if _mount_root == null or hud == null:
		return
	var vp2: Vector2 = hud.get_viewport().get_visible_rect().size
	var zones := Hud43.zones(vp2) if Hud43.on() else {}
	_ref_zone("send")
	var upx := Hud43.unit(vp2) if Hud43.on() else 1.0      # px per HUD pt now
	var o := _mount_root.get_global_rect().position
	for id in _mounts:
		var t: TextureRect = _mounts[id]
		var r := _target(id, zones, upx) if Hud43.on() else Rect2()
		if r.size.x < 2.0 or r.size.y < 2.0:
			t.visible = false
			continue
		t.position = r.position - o
		t.size = r.size
		t.visible = true
