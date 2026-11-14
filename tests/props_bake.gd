extends Node
## PROPS bake (props-place 2026-11-14): writes assets/props/placement/<map>_<setting>.json for the maps in --maps= and the
## settings in --sets= (default all five), with WorldProps.bake() on the live floor at the phone frame (812x375, game camera).
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/props_bake.tscn -- --maps=R-01,R-17 --out=<dir> --mobile
## The floor, the pits, the tubes and the walkway decks are the game's own; nothing is planned in the game at run time.
func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _run() -> void:
	var maps := ["R-01", "R-17"]
	var sets: Array = WorldProps.SPEC.keys()
	var out := "res://assets/props/placement"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="): maps = a.substr(7).split(",")
		elif a.begins_with("--sets="): sets = a.substr(7).split(",")
		elif a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	for mp in maps:
		var f := ""
		for g in DirAccess.get_files_at("res://maps4"):
			if g.begins_with(mp) and g.ends_with(".json"):
				f = g
		PerfProfile.force_level("phone")
		var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
		inst.set("map_path", "res://maps4/" + f)
		inst.set("demo", true)
		inst.set("ai_level", "Standard")
		inst.set("seed_value", 7)
		inst.set("mobile", true)
		get_tree().root.add_child(inst)
		await _frames(5)
		var wl: WorldLayer = inst.world_layer
		var tries := 0
		while (wl.locals == null or not wl.locals.placed or wl.locals.deck_ribbons.is_empty()) and tries < 900:
			await get_tree().process_frame
			tries += 1
			if tries % 100 == 0:
				print("PROPS wait ", tries, " locals ", wl.locals != null, " placed ", wl.locals.placed if wl.locals != null else false, " pipes ", wl.pipes != null, " started ", inst.started)
		await _frames(30)
		var cam := get_viewport().get_camera_3d()
		print("PROPS bake %s: camera %s, %d ribbons, %d discs, %d craters" % [mp, str(cam.global_position), wl.locals.deck_ribbons.size(),
				wl.locals.deck_discs.size(), wl.locals.craters.size()])
		var wp := WorldProps.new()
		wp.bake_mode = true
		wl.add_child(wp)
		wp.wl = wl
		for st in sets:
			var rows := wp.bake(st, mp, cam)
			var fa := FileAccess.open("%s/%s_%s.json" % [out, mp, st], FileAccess.WRITE)
			fa.store_string(JSON.stringify(rows))
			fa.close()
		wp.queue_free()
		inst.queue_free()
		await _frames(10)
	get_tree().quit(0)
