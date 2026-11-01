extends "res://tests/test_ai_curve.gd"
## bal-audit (2026-11-02, measurement only): test_ai_curve with a balance proposal applied first.
##   Godot --headless --path . --script res://tests/bal_curve.gd -- '--override={"SKILLS":{...},"MACHINEGOON_PROD":1.0}'


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--override="):
			var ov = JSON.parse_string(a.substr(11))
			Rules.apply_balance("", ov if ov is Dictionary else {})
			print("bal_curve override: ", a.substr(11))
	super()
