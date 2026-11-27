class_name ContactShade
extends Node3D
## READABILITY D (0.24.5, Daniele 2026-11-15 "yes all five"): view only, no rules.
##  - seat plates: a soft seat-colour disc (alpha PLATE_A, Rules.R x PLATE_K across) on every owned node, set when the
##    owner changes (main._on_captured / the start), never per frame. COLOUR RULE: neon = seat colour, so the plate is too.
##  - contact shadows (SHADOW_A): a soft drop shadow on the floor under each elevated platform and along each bridge, and
##    a grounding ring on the deck under each building. Offset = the deck's height above the floor x SUN (so a shallower
##    board / closer camera keeps the shadow attached); bridge band width = the kit deck's measured width x BAND_K.
##    Nothing less than MIN_H above the floor gets a drop shadow; pits (ground level) get nothing.
## One shader (shaders/contact_shade.gdshader), shared materials, no textures.

const SHADER := preload("res://shaders/contact_shade.gdshader")
const PLATE_A := 0.4
const PLATE_K := 1.86                 # plate diameter / Rules.R (inside the rim)
const SHADOW_A := 0.275               # 50 % of option C (Daniele: "shadows but at lets say 50% intensity of your step C")
const DROP_K := 2.9                   # floor drop disc diameter / Rules.R
const RING_K := 2.0                   # grounding ring quad / Rules.R
const SUN := Vector2(0.075, 0.1)      # floor offset (x, z) per metre of height above the floor (1.2, 1.6 m at 16 m)
const BAND_K := 1.2                   # bridge band width / kit deck width (4.18 m on today's 3.48 m Deck_S)
const MIN_H := 1.0                    # m above the floor: anything lower casts no drop shadow
const SHADE := Color(0.02, 0.03, 0.05)
const DECK_PIECE := "Deck_S"

static var _deck_w := -1.0
var plates := {}                      # node id -> MeshInstance3D
var _plate_mats := {}                 # seat -> ShaderMaterial


static func wanted() -> bool:
	return Look.v2


static func deck_width() -> float:
	## The kit bridge deck's width (across the bridge), measured once from the piece.
	if _deck_w > 0.0:
		return _deck_w
	_deck_w = 3.4 * Rules.DECK_SCALE
	var path := Cosmetics.kit_path(DECK_PIECE)
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate() as Node3D
		var box := AABB()
		var first := true
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			var xf := m3.transform
			var p := m3.get_parent()
			while p != null and p != root and p is Node3D:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var b := xf * m3.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		root.free()
		if not first and box.size.z > 0.5:
			_deck_w = box.size.z * Rules.DECK_SCALE   # pieces lie along +X (Rules.heading), width across = Z; 3.0 WP2c: widened in build3
	return _deck_w


static func _mat(strength: float, inner: float, mode: int, c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("inner", inner)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", c)
	return m


func _quad(size: Vector2, m: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	add_child(mi)
	return mi


static func _platformed(vis: Dictionary, n: Dictionary) -> bool:
	## A node with its own platform piece (not a plaza member, not a junction piece).
	var v: Dictionary = vis.get(int(n["id"]), {})
	return v.get("platform") != null and str(n.get("junction", "")) == ""


func setup(sim: Sim, vis: Dictionary, floor_y: float) -> void:
	## floor_y: the world layer's floor (NAN = no floor: no drop shadows).
	var drop := _mat(SHADOW_A, 0.55, 0, SHADE)
	var band := _mat(SHADOW_A * 0.85, 0.35, 1, SHADE)
	var ring := _mat(SHADOW_A * 1.1, 0.0, 2, Color(0, 0, 0))
	var has_floor := not is_nan(floor_y)
	for n in sim.nodes:
		var id: int = n["id"]
		if not _platformed(vis, n):
			continue
		var p: Vector3 = n["pos"]
		_quad(Vector2.ONE * Rules.R * RING_K, ring, Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.07))
		var plate := _quad(Vector2.ONE * Rules.R * PLATE_K, _plate_mat("A"), Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.05))
		plate.visible = false
		plates[id] = plate
		var h := p.y - floor_y
		if has_floor and h >= MIN_H:
			_quad(Vector2.ONE * Rules.R * DROP_K, drop, Transform3D(Basis.IDENTITY, Vector3(p.x + SUN.x * h, floor_y + 0.06, p.z + SUN.y * h)))
	if not has_floor:
		return
	var w := deck_width() * BAND_K
	for e in sim.edges:
		if e.get("plaza", false):
			continue
		var a: Vector3 = sim.nodes[e["a"]]["pos"]
		var b: Vector3 = sim.nodes[e["b"]]["pos"]
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		var L := d.length()
		var h := (a.y + b.y) / 2.0 - floor_y
		if L < 0.1 or h < MIN_H:
			continue
		var c := (a + b) / 2.0
		_quad(Vector2(L, w), band, Transform3D(Basis(Vector3.UP, atan2(d.x, d.z) + PI / 2.0),
				Vector3(c.x + SUN.x * h, floor_y + 0.05, c.z + SUN.y * h)))


func _plate_mat(seat: String) -> ShaderMaterial:
	if not _plate_mats.has(seat):
		_plate_mats[seat] = _mat(PLATE_A, 0.80, 0, Rules.seat_color(seat))
	return _plate_mats[seat]


func set_seat(id: int, owner: String) -> void:
	## The node's plate in its owner's seat colour, hidden while neutral.
	var mi: MeshInstance3D = plates.get(id)
	if mi == null:
		return
	var owned := Rules.SEATS.has(owner)
	mi.visible = owned
	if owned:
		mi.material_override = _plate_mat(owner)
