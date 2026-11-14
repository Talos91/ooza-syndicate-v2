extends Node
## relay-v3-column: forced-owner board shots + band/rim colour probe (owners go through the game's own captured signal).
##   Godot --path . --resolution 1624x750 ... res://tests/relay_col_force.tscn -- out=<dir> map=R-01 theme=lab
func _ready() -> void:
	_run.call_deferred()

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(inst: Node, file: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)

func _col(m) -> String:
	if m is StandardMaterial3D:
		return (m as StandardMaterial3D).emission.to_html(false)
	return "-"

func _probe(inst: Node, sim: Sim) -> void:
	for n in sim.nodes:
		if str(n["relay"]) == "":
			continue
		var plat: Node = inst.vis[n["id"]].get("platform")
		var band := []
		var goo := []
		var piece := plat.get_node_or_null("Platform_Relay_v3_%d" % n["id"])
		if piece:
			for mi in piece.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for s in range(mesh.get_surface_count()):
					var m := mesh.surface_get_material(s)
					if m and m.resource_name.begins_with("OS_Light"):
						band.append(_col((mi as MeshInstance3D).get_surface_override_material(s)))
					elif m and m.resource_name.begins_with("OS_Ooze"):
						goo.append(_col((mi as MeshInstance3D).get_surface_override_material(s)))
		var rim := plat.get_node_or_null("LookRim")
		print("PROBE node %d seat=%s faction=%s band(seat)=%s goo(faction)=%s rim=%s" % [n["id"], n["owner"], str(GooTone.factions.get(n["owner"], "?")), str(band), str(goo), _col((rim as MeshInstance3D).material_override) if rim else "none"])

func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://relay_col"))
	DirAccess.make_dir_recursive_absolute(out)
	var code := str(args.get("map", "R-01"))
	var theme := str(args.get("theme", "lab"))
	UiKit.save_setting_choice(theme)
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(40)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var rel := []
	for n in sim.nodes:
		if str(n["relay"]) != "" and str(n["relay"]) != "rotation":
			rel.append(n)
	for pass_i in range(2):                       # pass 0: relay k owned by A (cyan) / B alternately; pass 1 swapped (a re-capture)
		for k in range(rel.size()):
			var n: Dictionary = rel[k]
			var seat := "A" if (k + pass_i) % 2 == 0 else "B"
			var old: String = n["owner"]
			n["owner"] = seat
			sim.captured.emit(int(n["id"]), seat, old)
		await _frames(30)
		print("pass %d" % pass_i)
		_probe(inst, sim)
		await _shot(inst, "%s/FORCE-%s-%s-board-pass%d-%s.png" % [out, code, theme, pass_i, "_".join(rel.map(func(n): return "r%d-seat%s-%s" % [n["id"], n["owner"], GooTone.factions.get(n["owner"], "?")]))])
	var n0: Dictionary = rel[0]
	var p: Vector3 = n0["pos"]
	inst.set_process(false)
	var d := 34.0
	var yaw := deg_to_rad(55.0)
	inst.cam.position = p + Vector3(sin(yaw) * d, 2.0, cos(yaw) * d)
	inst.cam.look_at(p + Vector3(0, -7.0, 0), Vector3.UP)
	await _frames(30)
	await _shot(inst, "%s/FORCE-%s-%s-col%d-seat%s-%s-yaw55.png" % [out, code, theme, n0["id"], n0["owner"], GooTone.factions.get(n0["owner"], "?")])
	print("DONE")
	get_tree().quit()
