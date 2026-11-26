extends Node3D
## LAB COUNT ON THE VAT SCREEN (lab4 job 3, LAB-BUILD-PLAN 2026-11-23 WP 6 / test card 2; Daniele 11-23: the unit count lives ON the
## vat screen, in the world, "try +15 %", no HUD badge). With Rules.lab_opt("count_on_screen") main adds one of these: every node gets
## a SCREEN on its vat's tower front - a dark panel with a seat-colour neon frame (neon = seat) and the count in the seat colour,
## brightened, with a dark outline (reads on every faction: the panel, not the goo, is behind the digits). Hud._badges hides the
## HUD count badge when lab_opt("hud_badge") is off.
##
## WHERE: centred on the tower's capital (the H_Capital band of the kit2 vat, measured from the model, so a tier swap moves it),
## just in front of the tower. FIXED to the vat, not a billboard: the panel leans back to the locked lab camera's pitch
## (Rules.LAB_CAM_PITCH 45 deg, yaw 0), so at that camera it faces the eye squarely (full height, no 45 deg foreshortening) and
## still reads as a mounted screen that does not swim when the player pinches. Drawn without depth test above the units
## (render_priority 1..3, like the tier labels of combat_fx.gd), so neither the tower nor a line on the platform covers it.
##
## SIZE: the base (x1.0) = three Rajdhani digits filling the capital's width (3.18 m) at 90 %: em 1.79 m, digit height
## DIGIT_H = 1.15 m (Rajdhani SemiBold digits are 0.643 em). count_scale (x1.0 / x1.15 / x1.3) scales the digits and the panel.
## digit_pt() is what the lab overlay shows: the projected digit height in pt at the node nearest the view's aim.

const FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const CAPITAL_W := 3.18             # m, the kit2 vat capital's width (Vat_T1..T4 H_Capital, 3.18 x 0.65 m)
const DIGIT_EM := 0.643             # Rajdhani SemiBold digit height / em (fontTools bounds of 0-9)
const DIGIT_ADV := 0.533            # its digit advance / em
const EM := CAPITAL_W * 0.9 / (3.0 * DIGIT_ADV)   # 1.79 m: three digits fill 90 % of the capital
const DIGIT_H := EM * DIGIT_EM      # 1.15 m at x1.0
const FONT_PX := 96                 # Label3D font size (pixel_size = EM / FONT_PX)
const FALLBACK_Y := 4.6             # m above the node when the vat has no H_Capital (other kits, relays)
const LIFT_FRONT := 0.25            # m in front of the capital's front face

var main: Node
var hud                             # Hud (untyped: a test may load this script before the autoloads exist)
var scale_k := 1.0
var screens := {}                   # node id -> {"pivot", "frame", "panel", "label", "vat", "owner", "text"}
var _t := 0.0


func setup(m: Node) -> void:
	main = m
	hud = m.hud
	name = "VatCount"
	scale_k = float(Rules.lab_opt("count_scale"))
	for n in main.sim.nodes:
		if n.get("node_kind", "") == "junction":
			continue
		screens[n["id"]] = _make()
	sync(true)


func _make() -> Dictionary:
	var pivot := Node3D.new()
	add_child(pivot)
	var h := DIGIT_H * scale_k * 1.55                 # panel: digits + margins
	var w := CAPITAL_W * scale_k
	var frame := _quad(Vector2(w + 0.24, h + 0.24), Color.WHITE, 1)
	pivot.add_child(frame)
	var panel := _quad(Vector2(w, h), Color(0.03, 0.04, 0.06, 0.92), 2)
	pivot.add_child(panel)
	var l := Label3D.new()
	l.font = FONT
	l.font_size = FONT_PX
	l.pixel_size = EM * scale_k / FONT_PX
	l.outline_size = int(FONT_PX * 0.16)
	l.outline_modulate = Color(0.01, 0.01, 0.03, 1.0)
	l.no_depth_test = true
	l.fixed_size = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.render_priority = 4
	l.outline_render_priority = 3
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector3(0.0, 0.0, 0.02)
	pivot.add_child(l)
	return {"pivot": pivot, "frame": frame, "panel": panel, "label": l, "vat": null, "owner": "?", "text": ""}


func _quad(size: Vector2, col: Color, prio: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = prio
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _process(dt: float) -> void:
	_t += dt
	if _t >= 0.1:                                     # 10 Hz is live enough for a count; positions follow tier swaps
		_t = 0.0
		sync()


func sync(force := false) -> void:
	for n in main.sim.nodes:
		if not screens.has(n["id"]):
			continue
		var s: Dictionary = screens[n["id"]]
		var pivot: Node3D = s["pivot"]
		if main.sim.collapsed.get(n["id"], false):
			pivot.visible = false
			continue
		pivot.visible = true
		var entry: Dictionary = main.vis.get(n["id"], {})
		var vat = entry.get("vat_node")
		if force or vat != s["vat"]:
			s["vat"] = vat
			_place(n, pivot, vat)
		var owner: String = n["owner"]
		if owner != s["owner"]:
			s["owner"] = owner
			var col := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			((s["frame"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = col
			(s["label"] as Label3D).modulate = col.lerp(Color.WHITE, 0.35)
		var t := count_text(n)
		if t != s["text"]:
			s["text"] = t
			(s["label"] as Label3D).text = t


func count_text(n: Dictionary) -> String:
	## What the HUD badge would show for this node (Hud._badges): the count, "?" under a rival's Fog, "" when masked.
	var sim = main.sim
	var human: String = hud.human
	var owner: String = n["owner"]
	var masked: bool = not (owner == "" or sim.allied(owner, human) or (not Rules.hide_enemy_counts and hud.shows("rival_counts")))   # Brawl only (as Hud._badges since the 0.25.2 cleanup)
	var fogged: bool = sim.node_hidden(n["id"], human) and (owner == "" or not sim.allied(owner, human))
	if fogged:
		return "?"
	if masked:
		return ""
	var units: float = sim.garrison_total(n) if sim.allied_units(n) > 0.0001 else sim.visible_units(n, human)
	return str(Rules.shown(units))


func _place(n: Dictionary, pivot: Node3D, vat) -> void:
	## Centre on the capital's front, in front of it; lean back to the lab camera's pitch.
	var centre := Vector3(n["pos"]) + Vector3(0.0, FALLBACK_Y, 0.0)
	var front := Vector3(0, 0, 1)
	var cap := _capital(vat)
	if vat is Node3D and (vat as Node3D).is_inside_tree():
		var vb := (vat as Node3D).global_transform.basis
		front = Vector3(vb.z.x, 0.0, vb.z.z)
		front = front.normalized() if front.length() > 0.001 else Vector3(0, 0, 1)
	if cap != null:
		var a: AABB = cap.global_transform * cap.get_aabb()
		var c := a.get_center()
		var half := maxf(absf(a.size.x * front.x), absf(a.size.z * front.z)) * 0.5
		centre = Vector3(c.x, c.y, c.z) + front * (half + LIFT_FRONT)
	var yaw := atan2(front.x, front.z)
	var pitch := Rules.LAB_CAM_PITCH if bool(Rules.lab_opt("cam_lock")) else float(main.cam_pitch)
	pivot.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(pitch)), centre)


func _capital(vat) -> MeshInstance3D:
	if not (vat is Node) or not (vat as Node).is_inside_tree():
		return null
	for c in (vat as Node).find_children("H_Capital*", "MeshInstance3D", true, false):
		return c as MeshInstance3D
	return null


func digit_height_m() -> float:
	return DIGIT_H * scale_k


func digit_pt_at(id: int, cam: Camera3D) -> float:
	## The digit height in pt on screen at node id (the label's centre +- half a digit along the panel's up).
	if not screens.has(id) or cam == null or not cam.is_inside_tree():
		return 0.0
	var pivot: Node3D = screens[id]["pivot"]
	var up := pivot.global_transform.basis.y.normalized() * digit_height_m() * 0.5
	var p := pivot.global_position
	var vp := get_viewport().get_visible_rect().size
	return (cam.unproject_position(p + up) - cam.unproject_position(p - up)).length() * UiKit.pt_per_px(vp)


func digit_pt(cam: Camera3D) -> float:
	## At the node nearest the view's aim point (what the overlay shows).
	var best := -1
	var bd := INF
	var aim: Vector3 = main.cam_target
	for n in main.sim.nodes:
		if not screens.has(n["id"]):
			continue
		var d := Vector3(n["pos"]).distance_to(aim)
		if d < bd:
			bd = d
			best = n["id"]
	return digit_pt_at(best, cam)
