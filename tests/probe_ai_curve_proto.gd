extends "res://tests/test_ai_curve.gd"
## Probe (ai-launcher-laser, 2026-11-10): test_ai_curve over the PROTO pool on a demo build (Rules.demo off for this
## run), so the level curve is measured on maps that offer every mode - the demo pool (R-01 only) gives -nan.

func _initialize() -> void:
	Rules.demo = false
	super._initialize()
