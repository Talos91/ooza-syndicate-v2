extends Node
## units-wire proof (a dev tool, not a suite): the ORIGINAL Rodin GLB next to the in-game unit (creature shader, seat colour neon),
## and a walk frame strip. Windowed, off-screen:
##   Godot --path . --resolution 1624x750 --audio-driver Dummy --position -6000,-6000 res://tests/rodin_vs_game.tscn -- out=<dir> [mode=compare|walk] [colour=A] [f=vex]
const SRC := "H:/My Drive/PROJECTS/Ooze Syndicate/Models/2.0/factions-v4/generated/%s/%s_rodin_v1.glb"
const KEYS := {"vex": "vex", "null": "null", "bloom": "bloom", "ember": "ember", "solar": "aegis"}


func _ready() -> void:
	_run.call_deferred()


func _game_unit(f: String, seat: String) -> Node3D:
	var root: Node = load("res://assets/units/%s.glb" % f).instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var tex: Texture2D = (mi.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
	var m := Mats.creature(f, seat, tex).duplicate() as ShaderMaterial
	UnitView.style(m, f, seat, false)
	mi.material_override = m
	root.remove_child(mi)
	root.free()
	return mi


func _orig(f: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(SRC % [KEYS[f], KEYS[f]], st)
	return doc.generate_scene(st) as Node3D


func _run() -> void:
	var out := "user://"
	var mode := "compare"
	var seat := "A"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("mode="): mode = a.substr(5)
		if a.begins_with("colour="): seat = a.substr(7)
		if a.begins_with("f="): only = a.substr(2)
	Rules.assign_colors(["A", "B"], {"A": "vex", "B": "ember"}, "A", seat if seat.length() == 1 else "A", {})
	var world := Node3D.new()
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	var facs := ["vex", "null", "bloom", "ember", "solar"] if only == "" else [only]
	if mode == "compare":
		for i in facs.size():
			var o := _orig(facs[i])
			o.position = Vector3((i - (facs.size() - 1) * 0.5) * 3.3, 0, 1.5)
			world.add_child(o)
			var g := _game_unit(facs[i], "A")
			g.position = Vector3((i - (facs.size() - 1) * 0.5) * 3.3, 0, -1.5)
			var sc: float = 1.0
			g.scale = Vector3.ONE * sc
			world.add_child(g)
		cam.position = Vector3(0, 5.5 if facs.size() > 1 else 3.0, 9.0 if facs.size() > 1 else 5.0)
		cam.look_at(Vector3(0, 0.7, 0))
		cam.fov = 40
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/rvg_%s_%s.png" % [out, "all" if only == "" else only, seat])
	else:
		for k in range(6):                      # walk strip: the unit advances 1/6 stride per frame along its forward axis
			var g := _game_unit(facs[0], "A")
			g.position = Vector3((k - 2.5) * 1.5, 0, 0.55 * k / 6.0)
			g.set_meta("k", k)
			world.add_child(g)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL   # no perspective skew: every phase is seen from the same angle
		cam.size = 4.2
		cam.position = Vector3(0, 0.9, 7.0)
		cam.look_at(Vector3(0, 0.55, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/walk_%s.png" % [out, facs[0]])
	get_tree().quit(0)
