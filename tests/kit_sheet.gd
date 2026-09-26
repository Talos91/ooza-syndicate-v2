extends SceneTree
## Kit look-dev sheet (0.18.7 look pass): the structure kit on platforms under the game's own light
## (Scenery.build_environment + the sky backdrop + the void), so vats, cannons, the forge and the relay
## housings can be judged side by side at phone scale and up close. Windowed (it renders):
##   Godot --path . --resolution 1688x780 --script res://tests/kit_sheet.gd -- out=<dir> [mobile] [fill=0.55]
## Writes vats_phone.png (the 4 tiers x 4 owners at the in-game phone scale), vats_close_<row>.png,
## family.png (vat T3, cannons T1-T3, forge, socket and the four relay housings) and family_phone.png.

const SPACING := 16.0
const OWNERS := ["", "A", "D", "B"]          # neutral, cyan, red, green (Rules.SEATS)
const FACTION_OF := {"A": "null", "D": "ember", "B": "bloom"}
var out := "user://kit_sheet"
var mobile := false
var fill := 0.55
var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a == "mobile":
			mobile = true
		elif a.begins_with("fill="):
			fill = float(a.substr(5))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	world = Node3D.new()
	root.add_child(world)
	Rules.view_yaw = 0.0
	var sun := Scenery.build_environment(world, mobile)
	Scenery.make_backdrop(world)
	Scenery.make_void(world, Vector3(0, 0, -1.5 * SPACING), Vector2(6, 9) * SPACING, not mobile)
	if mobile:
		sun.shadow_enabled = false
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 0.75
		root.msaa_3d = Viewport.MSAA_DISABLED
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 2000.0
	world.add_child(cam)
	cam.current = true
	# vats: tiers across (x), owners down (z, toward the camera)
	for row in range(OWNERS.size()):
		for t in range(1, 5):
			var p := Vector3((t - 2.5) * SPACING, 0.0, (row - 1.5) * SPACING)
			_node(p, "Vat_T%d" % t, OWNERS[row])
	# the structure family, one row further back
	var fam := ["Vat_T3", "Cannon_T1", "Cannon_T2", "Cannon_T3", "Forge", "Socket_Attachment"]
	for i in range(fam.size()):
		_node(Vector3((i - 2.5) * SPACING, 0.0, -3.5 * SPACING), fam[i], "A" if i % 2 == 0 else "")
	var relays := ["rotation", "retract", "switch", "remote"]
	for i in range(relays.size()):
		_relay(Vector3((i - 1.5) * SPACING * 1.35, 0.0, -5.2 * SPACING), relays[i], "A" if i % 2 == 1 else "D")
	await _frames(12)
	# phone scale: a platform ~95 px across on a 780 px high screen, as in the game on a phone
	await _shot(Vector3(0, 0, 0), 58.0, 128.0, "vats_phone.png")
	for row in range(OWNERS.size()):
		await _shot(Vector3(0, 2.5, (row - 1.5) * SPACING), 40.0, 58.0, "vats_close_%s.png" % (OWNERS[row] if OWNERS[row] != "" else "neutral"))
	await _shot(Vector3(0, 2.5, -3.5 * SPACING), 40.0, 62.0, "family.png")
	await _shot(Vector3(0, 1.5, -5.2 * SPACING), 45.0, 70.0, "relays.png")
	await _shot(Vector3(0, 0, -4.3 * SPACING), 58.0, 128.0, "family_phone.png")
	print("kit sheet -> ", out)
	quit()


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(target: Vector3, pitch: float, dist: float, file: String) -> void:
	var dir := Vector3(0, sin(deg_to_rad(pitch)), cos(deg_to_rad(pitch)))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(file))


func _node(p: Vector3, model: String, owner: String) -> void:
	var parts: Array = [MapBuilder.put(world, "Platform_Standard", p)]
	var vn := MapBuilder.put(world, model, p, Rules.view_yaw)
	parts.append(vn)
	MapBuilder.apply_owner(parts, owner)
	if model.begins_with("Vat_"):
		_liquid(vn, model, owner)


func _relay(p: Vector3, relay: String, owner: String) -> void:
	var parts: Array = [MapBuilder.put(world, "Platform_Rotation" if relay == "rotation" else "Platform_Standard", p)]
	var d := Vector3(1, 0, -1).normalized()
	if relay == "retract":
		parts.append(MapBuilder.put(world, "Relay_Retract", p, Rules.heading(d)))
		parts.append(MapBuilder.put(world, "Pier_Connector", p, Rules.heading(d)))
	else:
		parts.append(MapBuilder.put(world, "Relay_Mount", p, Rules.heading(d)))
		parts.append(MapBuilder.put(world, MapBuilder.RELAY_HOUSING[relay], p + d * MapBuilder.MOUNT_DIST, Rules.heading(-d)))
	parts.append(MapBuilder.put(world, "Socket_Attachment", p, Rules.view_yaw))
	MapBuilder.apply_owner(parts, owner)
	var key: String = {"rotation": "r1", "retract": "retract", "switch": "s1", "remote": "m1"}[relay]
	for mi in (parts[1] as Node).find_children("*", "MeshInstance3D", true, false) + (parts[2] as Node).find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s)
			if m and m.resource_name.begins_with("OS_State"):
				(mi as MeshInstance3D).set_surface_override_material(s, Mats.light_color(Rules.state_color(key)))


func _liquid(vn: Node3D, key: String, owner: String) -> void:
	var col: Color = Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL * 0.55
	for mi in vn.find_children("*", "MeshInstance3D", true, false):
		var info := Scenery.tank_info((mi as MeshInstance3D).mesh, key)
		if info["surface"] < 0 or (info["tanks"] as Array).is_empty():
			continue
		var mat := ShaderMaterial.new()
		mat.shader = Scenery.LIQUID_SHADER
		mat.set_shader_parameter("y_min", info["y0"])
		mat.set_shader_parameter("y_max", info["y1"])
		mat.set_shader_parameter("level", lerpf(info["y0"], info["y1"], fill))
		mat.set_shader_parameter("liquid_color", col)
		(mi as MeshInstance3D).set_surface_override_material(info["surface"], mat)
		var gs := Scenery.glass_surface((mi as MeshInstance3D).mesh)
		if gs >= 0:
			(mi as MeshInstance3D).set_surface_override_material(gs, Mats.glass(Scenery.glass_tint(owner)))
