class_name WardrobePreview
extends Cosmetics.Preview
## ARMIES > COSMETICS' one big preview (Alpha 21 UI pass, screen 08): Cosmetics.Preview - the look's model in its
## own world, framed to fit, a skin swapping in once it has loaded - turning slowly all the way round, with a fill
## and an accent rim light over the preview's key light and a dark plinth ringed in the accent. The page has one of
## these (phones: one 3D viewport, never one per tile); set_tier() switches the tier in place.

var accent := UiKit.CYAN
var _plinth: Node3D


static func make(p_family: String, p_id: String, p_faction: String, p_tier: int, dims: Vector2) -> WardrobePreview:
	var p := WardrobePreview.new()
	p.family = p_family
	p.id = p_id
	p.faction = p_faction
	p.tier = p_tier
	p.accent = UiKit.accent(p_faction)
	p.custom_minimum_size = dims
	p.size = dims
	return p


func set_tier(t: int) -> void:
	tier = t
	_refresh()


func _ready() -> void:
	super()
	var fill := DirectionalLight3D.new()                 # a cool fill from the left, so the shadow side reads
	fill.rotation = Vector3(deg_to_rad(-18), deg_to_rad(-75), 0)
	fill.light_color = Color(0.72, 0.84, 1.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	var rim := DirectionalLight3D.new()                  # the accent from behind: the silhouette's edge glows
	rim.rotation = Vector3(deg_to_rad(-25), deg_to_rad(165), 0)
	rim.light_color = accent.lightened(0.25)
	rim.light_energy = 1.4
	rim.light_cull_mask = 1                               # the model only: the plinth (layer 2) stays dark
	_vp.add_child(rim)
	_plinth = Node3D.new()
	var top := MeshInstance3D.new()                      # a dark, slightly glossy disc under the model
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.04
	disc.height = 0.08
	disc.radial_segments = 48
	top.mesh = disc
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.045, 0.055)
	dark.metallic = 0.3
	dark.roughness = 0.55
	top.material_override = dark
	top.position.y = -0.04
	top.layers = 2
	_plinth.add_child(top)
	var ring := MeshInstance3D.new()                     # its accent edge
	var band := CylinderMesh.new()
	band.top_radius = 1.055
	band.bottom_radius = 1.055
	band.height = 0.02
	band.radial_segments = 48
	ring.mesh = band
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = accent
	ring.material_override = glow
	ring.position.y = -0.06
	ring.layers = 2
	_plinth.add_child(ring)
	_vp.add_child(_plinth)
	_fit_plinth()


func _process(dt: float) -> void:
	super(dt)
	_pivot.rotation.y = _t * 0.35 + 0.35                 # a slow full turn instead of the rows' sway


func _refresh() -> void:
	var was := _key
	super()
	if _key != was:
		# a closer frame than the rows' small previews: the look fills the stage
		var z := _cam.position.z
		var h := _cam.position.y - 0.5 * z
		var d := z / 0.9 * 0.8
		_cam.position = Vector3(0, h + d * 0.45, d * 0.9)
		_cam.look_at(Vector3(0, h, 0), Vector3.UP)
		_fit_plinth()


func _fit_plinth() -> void:
	## The plinth follows the model's footprint (the widest mesh extent across x / z, from the framed model).
	if _plinth == null or _pivot.get_child_count() == 0:
		return
	var node := _pivot.get_child(_pivot.get_child_count() - 1) as Node3D
	var reach := 0.5
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		for c in [box.position, box.end]:
			var v: Vector3 = _pivot.global_transform.affine_inverse() * (c as Vector3)
			reach = maxf(reach, maxf(absf(v.x), absf(v.z)))
	_plinth.scale = Vector3(reach * 1.08, 1.0, reach * 1.08)
