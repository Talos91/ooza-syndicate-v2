extends SceneTree
## MapBatch and a piece re-meshed under its slots (0.22.0 web crash report: surface_get_material / get_surface_override_material
## "p_idx = 7 out of bounds (surfaces.size() = 7)" and _set_surfaces "!d.has(format)"):
##   Godot --headless --path . --script res://tests/test_map_batch_swap.gd        exit code 0 = passed
## A match on M-39 is batched; every batched structure and static piece with 2+ surfaces gets a mesh with one surface fewer
## (as MapBuilder.split_spinner does to a turret), then a recolour (MapBuilder.set_lights -> MapBatch.refresh) and a
## poll run before and after. Checks: no engine error on the way (the error count Godot logs), MapBatch.verify() clean
## (headless: all but the MultiMesh transforms, which the headless RenderingServer does not keep). The 0.22.0 base logs
## the report's "p_idx out of bounds" errors here.

var main: Node3D
var frames := 0
var failures := 0
var _errors := 0


class _Log extends Logger:
	var host
	func _log_error(_f: String, _file: String, _line: int, _code: String, _rationale: String, _editor: bool, _type: int,
			_bt: Array[ScriptBacktrace]) -> void:
		host._errors += 1


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	var lg := _Log.new()
	lg.host = self
	OS.add_logger(lg)
	PerfProfile.force_level("phone")
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", "res://maps4/M-39-circuit-warren.json")
	main.set("demo", true)
	main.set("ff_to", 60.0)
	main.set("seed_value", 7)
	root.add_child(main)
	process_frame.connect(_frame)


func _frame() -> void:
	if not bool(main.get("started")):
		return
	frames += 1
	if frames == 5:
		check(MapBatch.current != null, "the map is batched")
		if MapBatch.current == null:
			quit(1)
			return
		_errors = 0
		var swapped := 0
		for id in MapBatch.current._pieces:
			var p = MapBatch.current._pieces[id]
			if not is_instance_valid(p.mi) or p.mesh == null or p.mesh.get_surface_count() < 2:
				continue
			var fewer := ArrayMesh.new()                   # the mesh minus its last surface (a split turret's "keep")
			for s in range(p.mesh.get_surface_count() - 1):
				fewer.add_surface_from_arrays(p.mesh.surface_get_primitive_type(s), p.mesh.surface_get_arrays(s))
				fewer.surface_set_material(s, p.mesh.surface_get_material(s))
			p.mi.mesh = fewer
			swapped += 1
			if swapped >= 40:
				break
		check(swapped > 0, "re-meshed %d batched pieces" % swapped)
		for n in (main.get("vis") as Dictionary).values():
			if n is Dictionary:
				for part in n.get("parts", []):
					if is_instance_valid(part):
						MapBatch.refresh(part)                # a recolour lands before the next poll
	if frames == 12:
		check(_errors == 0, "no engine errors after the swap (%d)" % _errors)
		var bad := MapBatch.verify()
		if DisplayServer.get_name() == "headless":        # (the headless RenderingServer keeps no MultiMesh transforms)
			bad = bad.filter(func(b): return not str(b).ends_with("at the wrong place"))
		check(bad.is_empty(), "batched pieces consistent (%d mismatches) %s" % [bad.size(), bad.slice(0, 4)])
		print("ALL PASSED" if failures == 0 else "FAILURES (%d failed)" % failures)
		quit(0 if failures == 0 else 1)
