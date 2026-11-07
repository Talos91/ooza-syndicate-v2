extends Node
## FLOOR PLAN probe (a dev tool, not a suite): the data an art director needs to paint a map's world floor in world
## metres. Opens the map as the game draws it on a landscape phone (an AI match fast-forwarded to 60 s, like
## tests/world_shots.gd), then writes to out=<dir>:
##   probe.json        floor (y, centre, radius, fade radii, tile size / origin), camera (pitch, yaw, fov, fit, pan / zoom
##                     range, HUD rects), tubes, nodes, and one entry per camera state of the ID pass
##   board.bin         every board mesh triangle in world space (float32 x,y,z * 3 per triangle), ranges in probe.json
##   frame.png         the in-game frame at the default (fitted) camera, HUD on
##   id_<k>.png        ID pass per camera state: the floor drawn flat magenta (unshaded, no fog), the mist sheet, glow,
##                     fog and HUD off; everything else as the game draws it, so whatever covers the floor covers it here
## Camera states: k=0 the default fit, then the player zoom (Rules.CAM_ZOOM_MIN..1 of the fit) x pan (the _zoom_at clamp:
## +-_map_half * (1 - zoom) around the fit's target) on a 5 x 5 grid. tools/floor_plan.py turns this into the plan.
## Run WINDOWED, off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/floor_plan_probe.tscn -- out=<dir> map=R-01

const MAIN := "res://main.tscn"
const ZOOMS := [0.75, 0.5, 0.35]
const PANS := [-1.0, -0.5, 0.0, 0.5, 1.0]


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
	await RenderingServer.frame_post_draw
	inst.get_viewport().get_texture().get_image().save_png(file)


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _under(n: Node, roots: Array) -> int:
	var p := n
	while p != null:
		for i in range(roots.size()):
			for r in roots[i]:
				if p == r:
					return i
		p = p.get_parent()
	return -1


func _run() -> void:
	var args := _args()
	var out := str(args.get("out", "user://floor_plan"))
	DirAccess.make_dir_recursive_absolute(out)
	var code := str(args.get("map", "R-01"))
	var path := ""
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			path = "res://maps4/" + f
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	await _frames(10)
	inst.ais.clear()
	var sim: Sim = inst.sim
	var ais := [SeatAI.new("A", 2.5, "Veteran"), SeatAI.new("B", 2.5, "Veteran")]
	while sim.time < 60.0 and not sim.over:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
	sim.fx_events.clear()
	inst.paused = true
	await _frames(40)
	var cam: Camera3D = inst.cam
	var wl: WorldLayer = inst.world_layer
	var vp: Vector2 = inst.get_viewport().get_visible_rect().size
	await _shot(inst, out + "/frame.png")
	# --- data
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in sim.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	var centre := (lo + hi) / 2.0
	var radius := Vector2(hi.x - lo.x, hi.z - lo.z).length() / 2.0
	var hud = inst.hud
	var d := {"map": code, "map_path": path, "viewport": [vp.x, vp.y],
		"floor": {"y": wl.floor_y, "kind": wl.floor_kind, "centre_xz": [centre.x, centre.z], "radius": radius,
			"fade_r0": radius + 30.0, "fade_r1": radius + 110.0, "district_r": radius + 30.0,
			"plane_size": radius * 2.0 + 260.0, "tile_m": 16.0, "tile_origin_xz": [0.0, 0.0],
			"depth": WorldLayer.FLOOR_DEPTH},
		"camera": {"pitch": inst.cam_pitch, "yaw": inst.cam_yaw, "fov_v": cam.fov, "keep_aspect": cam.keep_aspect,
			"fit_target": _v3(inst._start_fit[0]), "fit_dist": inst._start_fit[1], "map_half": _v3(inst._map_half),
			"zoom_min": Rules.CAM_ZOOM_MIN,
			"hud_side_right_px": hud.side_panel.position.x + hud.side_panel_width(), "hud_top_px": hud.top_used(),
			"hud_bottom_px": vp.y - hud.bottom_used()},
		"tubes": [], "nodes": [], "meshes": [], "states": []}
	for tb in wl._tubes:
		d["tubes"].append({"id": tb["id"], "x": tb["x"], "z": tb["z"], "r": tb["r"], "shown": (tb["mi"] as Node3D).visible})
	for n in sim.nodes:
		d["nodes"].append({"id": n["id"], "pos": _v3(n["pos"]), "relay": str(n.get("relay", "")),
			"junction": str(n.get("junction", "")), "plaza": n.get("plaza", -1), "owner": n["owner"]})
	# board meshes: everything drawn above the floor except the world layer and effects; category by owner
	var plat_roots := []
	var part_roots := []
	var bridge_roots := []
	for id in inst.vis:
		var e = inst.vis[id]
		if id is int and e is Dictionary:
			if e.get("platform") != null:
				plat_roots.append(e["platform"])
			for p in e.get("parts", []):
				if p != e.get("platform"):
					part_roots.append(p)
		elif str(id) in ["edge_decks", "edge_base", "edge_piers", "conduits"] and e is Dictionary:
			for v in e.values():
				for q in (v if v is Array else [v]):
					if q is Node:
						bridge_roots.append(q)
		elif str(id) == "plazas" and e is Dictionary:
			for v in e.values():
				if v.get("node") != null:
					plat_roots.append(v["node"])
	var buf := PackedFloat32Array()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or wl.is_ancestor_of(m):
			continue
		if inst.scenery and inst.scenery.is_ancestor_of(m):
			continue
		var ui := _under(m, [bridge_roots, plat_roots, part_roots])
		var cat: String = ["bridge", "platform", "part"][ui] if ui >= 0 else "other"
		var start := buf.size() / 9
		var xf := m.global_transform
		for s in range(m.mesh.get_surface_count()):
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array = PackedInt32Array(idx) if idx != null else PackedInt32Array(range(verts.size()))
			for t in range(0, tri.size() - 2, 3):
				for k in range(3):
					var w := xf * verts[tri[t + k]]
					buf.append(w.x)
					buf.append(w.y)
					buf.append(w.z)
		d["meshes"].append({"path": str(inst.get_path_to(m)), "cat": cat, "tri0": start, "tri1": buf.size() / 9})
	var fb := FileAccess.open(out + "/board.bin", FileAccess.WRITE)
	fb.store_buffer(buf.to_byte_array())
	fb.close()
	# --- ID pass setup
	var flat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, fog_disabled, cull_disabled;\nvoid fragment() { ALBEDO = vec3(1.0, 0.0, 1.0); }\n"
	flat.shader = sh
	wl._floor.material_override = flat
	for c in wl.get_children():
		if c is MeshInstance3D and c != wl._floor and not wl._tubes.any(func(tb): return tb["mi"] == c):
			(c as MeshInstance3D).visible = false            # the mist sheet: haze, not a cover
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visible = false       # splats, blobs, drops, sockets lie on the floor
	for we in inst.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		env.glow_enabled = false
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	for cl in inst.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var states := [[1.0, 0.0, 0.0]]
	for z in ZOOMS:
		for px in PANS:
			for pz in PANS:
				states.append([z, px, pz])
	var home: Vector3 = inst._start_fit[0]
	var far: float = inst._start_fit[1]
	var mh: Vector3 = inst._map_half
	for k in range(states.size()):
		var st: Array = states[k]
		var room: float = 1.0 - st[0]
		inst.cam_target = home + Vector3(mh.x * room * st[1], 0.0, mh.z * room * st[2])
		inst.cam_dist = far * st[0]
		inst._place_camera()
		await _frames(3)
		await _shot(inst, "%s/id_%02d.png" % [out, k])
		var xf := cam.global_transform
		var probe := []
		for q in [Vector3(centre.x, wl.floor_y, centre.z), Vector3(centre.x + 20.0, wl.floor_y, centre.z - 10.0)]:
			var sp := cam.unproject_position(q)
			probe.append([_v3(q), [sp.x, sp.y]])
		d["states"].append({"k": k, "zoom": st[0], "pan": [st[1], st[2]], "target": _v3(inst.cam_target), "dist": inst.cam_dist,
			"origin": _v3(xf.origin), "basis_x": _v3(xf.basis.x), "basis_y": _v3(xf.basis.y), "basis_z": _v3(xf.basis.z),
			"probe": probe})
	var f := FileAccess.open(out + "/probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	print("FLOOR PLAN PROBE DONE ", out, " states ", states.size(), " tris ", buf.size() / 9)
	get_tree().quit()
