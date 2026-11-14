extends SceneTree
# units-v4-vex: does the imported vex.glb give UnitView a v4 material? (headless)
func _init() -> void:
	var root: Node = load("res://assets/units/vex.glb").instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := mi.mesh
	var src := mesh.surface_get_material(0) as BaseMaterial3D
	print("V4PROBE tris ", mesh.surface_get_array_index_len(0) / 3, " aabb ", mesh.get_aabb(), " tex ", src.albedo_texture.resource_path, " size ", src.albedo_texture.get_size())
	var m := Mats.creature("vex", "p2", src.albedo_texture)
	print("V4PROBE is_v4 ", Mats.is_v4(m), " hue ", m.get_shader_parameter("hue_shift"), " tint ", m.get_shader_parameter("tint_color"))
	var old := Mats.creature("vex", "p2", load("res://assets/units/legacy/vex_v2_texture_diffuse.png"))
	print("V4PROBE legacy is_v4 ", Mats.is_v4(old))
	var gm := ShaderMaterial.new()
	gm.shader = SkillFx.ghost_shader()
	print("V4PROBE ghost shader code ok ", gm.shader.code.find("ghost_alpha") > 0)
	root.free()
	quit()
