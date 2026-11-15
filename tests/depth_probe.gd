extends SceneTree
func _initialize() -> void:
	var codes: Array = ["R-01","G-01","R-05","G-02","R-09","G-03","R-11","G-04","R-13","G-05","R-15","R-16","G-06","G-07","P-02","G-08","P-04","G-09","E-03","G-15","E-09","G-16"]
	var all := {}
	for f in DirAccess.get_files_at("res://maps4"):
		if not f.ends_with(".json"): continue
		if f.substr(0, 4) not in codes: continue
		var m := MapBuilder.load_map("res://maps4/" + f)
		var pos := MapBuilder.layout(m)
		var lo := 1e9
		for k in pos: lo = minf(lo, (pos[k] as Vector3).y)
		var fy := minf(lo, 0.0) - 16.0
		var out := {}
		for n in m["nodes"]:
			var rl = n.get("relay"); var pl := MapBuilder.platform_piece(n)
			if pl != "Platform_Pillar" and pl != "Platform_Rotation" and rl == null: continue
			var d := snappedf((pos[int(n["id"])] as Vector3).y - fy, 0.01)
			var key := ("relay " if rl != null else "pillar ") + str(d)
			out[key] = int(out.get(key, 0)) + 1
		print("%s  lowest %.2f  %s" % [f.substr(0, 4), lo, str(out)])
	quit()
