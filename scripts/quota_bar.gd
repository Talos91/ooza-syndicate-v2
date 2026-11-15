class_name QuotaBar
extends Control
## LAST STAND = QUOTA (Rules.quota, Daniele 2026-11-15): the match score on both flanks of the score tube, at the screen
## top. Left capsule = your side: "QUOTA", then your hex (SEAT neon rim, the count inside) against the tube; right capsule =
## the rival sides' hexes against the tube, then "10 LEFT" (platforms still to launch). The leader's hex gets a brighter,
## thicker seat-neon rim and a small crown (designer 9, 11-15: no gold in this HUD); a launch flashes its side's hex.
## Labels drop first when the flanks run short (>= 8 pt from the screen edges and the top keys). Shows from the Last
## Stand's start. View only: reads sim.quota / quota_standing (on a guest from the snapshot's "quota").
## (When it ships: re-skin with the locked 40B4 / 40B5 HUD kit - designer 9.)

var hud
var u := 1.0
var _groups: Array = []                 # [[seats of a side]] your side first
var _flash := {}                        # side index -> seconds of flash left
var _last := {}                         # side index -> quota last drawn
var _tube_x := Vector2.ZERO             # pt: the tube's left / right edge inside this control
var _labels := true                     # "QUOTA" / "N LEFT" fit
var _pops: Array = []                   # {"pos": Vector3, "col", "t"}: "+1 QUOTA" labels over launching pads
const POP_TIME := 1.8

const GLASS := Color(0.035, 0.05, 0.07, 0.88)
const RIM := Color(0.93, 0.95, 0.94, 0.18)
const DIM := Color(0.62, 0.68, 0.70)
const H := 30.0                          # pt: capsule height
const HEX_R := 13.0                      # pt: a side hex's outer radius
const LABEL_W := 44.0                    # pt: "QUOTA" / "10 LEFT"
const PAD := 7.0
const OVERLAP := 6.0                     # pt the capsule tucks under the tube's rounded end
const CLEAR := 8.0                       # pt kept from the screen edges and the top keys


func setup(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_groups = hud._seat_groups()


func _flank_w(labels: bool) -> float:
	var hexes := maxi(_groups.size() - 1, 1)
	return PAD + (LABEL_W if labels else 0.0) + hexes * (HEX_R * 2.0 + 3.0) + PAD + OVERLAP


func lay(tube: Rect2, scale_u: float, left_limit: float, right_limit: float) -> void:
	## tube: the score tube's rect (px); left_limit / right_limit: px x the capsules stay inside (safe edge, MUSIC key).
	u = scale_u
	var room := minf(tube.position.x - left_limit, right_limit - tube.end.x) / u - CLEAR
	_labels = _flank_w(true) <= room
	var fw := _flank_w(_labels) * u
	position = Vector2(tube.position.x - fw, tube.position.y + (tube.size.y - H * u) * 0.5)
	size = Vector2(tube.size.x + fw * 2.0, H * u)
	_tube_x = Vector2(fw, fw + tube.size.x) / u


func pop(pos: Vector3, seat: String) -> void:
	## "+1 QUOTA" over a launching pad: the bold label style on a dark plate (designer 9, 11-15), rising and fading.
	_pops.append({"pos": pos, "col": Rules.seat_color(seat), "t": 0.0})


func sync(dt: float) -> void:
	visible = Rules.quota and hud.sim.last_stand_active and not hud.sim.over
	for p in _pops.duplicate():
		p["t"] = float(p["t"]) + dt
		if float(p["t"]) > POP_TIME:
			_pops.erase(p)
	if not visible:
		return
	for i in range(_groups.size()):
		var q: int = hud.sim.quota_of(str(_groups[i][0]))
		if q != int(_last.get(i, 0)):
			_flash[i] = 0.9
			_last[i] = q
		if _flash.has(i):
			_flash[i] = float(_flash[i]) - dt
			if float(_flash[i]) <= 0.0:
				_flash.erase(i)
	queue_redraw()


func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(6):
		var a := PI / 6.0 + k * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _capsule(x0: float, x1: float) -> void:
	var sb := StyleBoxFlat.new()                      # dark glass, rounded, a faint light rim (staging-menu look)
	sb.bg_color = GLASS
	sb.set_corner_radius_all(int(round(H * 0.5 * u)))
	sb.set_border_width_all(maxi(1, int(round(1.0 * u))))
	sb.border_color = RIM
	draw_style_box(sb, Rect2(Vector2(x0, 0) * u, Vector2(x1 - x0, H) * u))


func _draw() -> void:
	var sim = hud.sim
	var st: Dictionary = sim.quota_standing()
	var lead_side = (st["sides"] as Array)[0] if not (st["sides"] as Array).is_empty() and int(st["lead"]) > 0 else null
	var mid := H * 0.5
	var w := size.x / u
	_capsule(0.0, _tube_x.x + OVERLAP)
	_capsule(_tube_x.y - OVERLAP, w)
	if _labels:
		HudLab.text_c(self, "QUOTA", Vector2(PAD + LABEL_W * 0.5, mid) * u, int(round(12.0 * u)), HudLab.LIGHT, HudLab.bold())
		HudLab.text_c(self, "%d LEFT" % int(st["left"]), Vector2(w - PAD - LABEL_W * 0.5, mid) * u, int(round(12.0 * u)), HudLab.LIGHT, HudLab.bold())
	_side(0, _tube_x.x - 3.0 - HEX_R, lead_side, mid)  # your hex against the tube's left end
	var x := _tube_x.y + 3.0 + HEX_R                 # rivals from the tube's right end outward
	for i in range(1, _groups.size()):
		_side(i, x, lead_side, mid)
		x += HEX_R * 2.0 + 3.0
	_draw_pops()


func _draw_pops() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fs := int(round(22.0 * u))
	var font := HudLab.bold()
	for p in _pops:
		var t := float(p["t"])
		var world: Vector3 = p["pos"] + Vector3(0, 5.0, 0)
		if cam.is_position_behind(world):
			continue
		var c := cam.unproject_position(world) - global_position - Vector2(0, 26.0 * u * minf(t / 0.6, 1.0))
		var a := clampf((POP_TIME - t) / 0.4, 0.0, 1.0) * clampf(t / 0.12, 0.0, 1.0)
		var txt := "+%d QUOTA" % Rules.QUOTA_PER_LAUNCH
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(c - Vector2(tw * 0.5 + 10.0 * u, 16.0 * u), Vector2(tw + 20.0 * u, 32.0 * u))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.06, 0.88 * a)
		sb.set_corner_radius_all(int(round(10.0 * u)))
		sb.set_border_width_all(maxi(1, int(round(2.0 * u))))
		sb.border_color = Color(p["col"], 0.9 * a)
		draw_style_box(sb, box)
		HudLab.text_c(self, txt, c, fs, Color((p["col"] as Color).lerp(Color.WHITE, 0.3), a), font)


func _side(i: int, hx: float, lead_side, mid: float) -> void:
	var sim = hud.sim
	var seat := str(_groups[i][0])
	var col := Rules.seat_color(seat)
	var q: int = sim.quota_of(seat)
	if (_groups[i] as Array).all(func(s): return hud._seat_out(str(s))):
		col = col.lerp(DIM, 0.7)
	var lead: bool = lead_side != null and str(sim.side_of(seat)) == str(lead_side)
	var fl := float(_flash.get(i, 0.0))
	var hc := Vector2(hx, mid) * u
	var hex := _hex(hc, (HEX_R + 2.5 * fl) * u)
	draw_colored_polygon(hex, Color(col.darkened(0.75), 0.96))
	var closed := hex.duplicate()
	closed.append(hex[0])
	var rim := col.lerp(Color.WHITE, (0.35 if lead else 0.0) + 0.4 * fl)
	draw_polyline(closed, Color(col, (0.55 if lead else 0.30) + 0.45 * fl), (7.0 if lead else 5.0) * u, true)   # neon halo
	draw_polyline(closed, rim, (3.0 if lead else 2.0) * u, true)
	HudLab.text_c(self, str(q), hc + Vector2(0, 0.5 * u), int(round(15.0 * u)), HudLab.LIGHT, HudLab.bold())
	if lead:                                         # the leader's crown: three points over the hex, in its seat neon
		var b := hc + Vector2(0, -(HEX_R + 1.0) * u)
		var cw := 5.0 * u
		var ch := 4.0 * u
		draw_colored_polygon(PackedVector2Array([b + Vector2(-cw, 0), b + Vector2(-cw, -ch), b + Vector2(-cw * 0.5, -ch * 0.45),
				b + Vector2(0, -ch * 1.2), b + Vector2(cw * 0.5, -ch * 0.45), b + Vector2(cw, -ch), b + Vector2(cw, 0)]), rim)
