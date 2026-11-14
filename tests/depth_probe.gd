extends SceneTree
func _initialize() -> void:
	var codes: Array = ["R-01","R-02","R-05","R-06","R-09","R-10","R-11","R-12","R-13","R-14","R-15","R-16","R-17","P-01","P-02","P-03","P-04","P-05","E-03","E-08","E-09","E-10"]
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
