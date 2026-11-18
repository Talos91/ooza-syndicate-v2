extends Node
## dev tool: close-ups of one v4 unit with its real game material. args after --: out=<dir> f=vex seat=B yaws=0,45,.. (windowed, hidden desktop)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var out := "user://"; var f := "vex"; var seat := "B"; var yaws := [-90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0, 180.0]
	var dist := 2.2; var ty := 0.55
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("f="): f = a.substr(2)
		if a.begins_with("seat="): seat = a.substr(5)
		if a.begins_with("dist="): dist = float(a.substr(5))
		if a.begins_with("ty="): ty = float(a.substr(3))
		if a.begins_with("yaws="):
			yaws = []
			for s in a.substr(5).split(","): yaws.append(float(s))
	var root: Node3D = load("res://assets/units/%s.glb" % f).instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
	mi.set_surface_override_material(0, Mats.creature(f, seat, src.albedo_texture))
	if "uv=1" in OS.get_cmdline_user_args():   # UV debug: R = u, G = v, unshaded
		var img := Image.create(2048, 2048, false, Image.FORMAT_RGB8)
		for yy in 2048:
			for xx in 2048: img.set_pixel(xx, yy, Color8(xx & 255, yy & 255, ((xx >> 8) << 4) | (yy >> 8)))
		var um := StandardMaterial3D.new(); um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		um.albedo_texture = ImageTexture.create_from_image(img); um.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mi.set_surface_override_material(0, um)
	var holder := Node3D.new(); add_child(holder); holder.add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.25, 0.25, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.8, 0.85, 0.9); e.ambient_light_energy = 0.7
	env.environment = e; add_child(env)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-45, -30, 0); l.light_energy = 1.2; add_child(l)
	var cam := Camera3D.new(); cam.fov = 35; add_child(cam)
	var aabb := mi.get_aabb(); print("aabb ", aabb)
	var c := aabb.get_center() * mi.global_transform.basis.get_scale()
	for y in yaws:
		holder.rotation_degrees.y = y
		cam.position = Vector3(0, aabb.position.y + aabb.size.y * ty, dist)
		cam.look_at(Vector3(0, aabb.position.y + aabb.size.y * ty, 0))
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s_y%d.png" % [out, f, seat, int(y)])
	get_tree().quit()
