extends Node
## Proves the R-01 floor-plan mask loads from res:// (run with OOZE_NO_DRIVE_PLAN=1 to rule out the Drive fallback).
##   OOZE_NO_DRIVE_PLAN=1 Godot --headless --path . res://tests/plan_probe.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var f := ""
	for n in DirAccess.get_files_at("res://maps4"):
		if n.begins_with("R-01") and n.ends_with(".json"):
			f = n
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + f}
	var inst: Node = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	for i in range(30):
		await get_tree().process_frame
	var lc: WorldLocals = inst.world_layer.locals
	var m: Image = lc._mask
	var vis := lc.crater_vis.map(func(v): return snappedf(v, 0.01))
	print("PLAN_PROBE mask %s craters %d vis %s" % [("null" if m == null else "%dx%d" % [m.get_width(), m.get_height()]), lc.craters.size(), str(vis)])
	get_tree().quit(0 if m != null else 1)
