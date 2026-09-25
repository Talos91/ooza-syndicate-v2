class_name Telemetry
extends RefCounted
## Per-match log (GAME-RULES §13): duration, sends, captures, frontlines, units lost to combat vs
## falls, deciding event, winner-was-behind flag. Written to user://telemetry/ as JSON.

static func save(sim: Sim, map_code: String, strength_trace: Array) -> String:
	var sends := {}
	var captures := 0
	var last_capture := {}
	for e in sim.events:
		if e["type"] == "send":
			sends[e["seat"]] = sends.get(e["seat"], 0) + 1
		elif e["type"] == "capture":
			captures += 1
			last_capture = e
	var behind := false
	for sample in strength_trace:                   # was the winner ever clearly behind?
		if sim.winner != "" and sample.has(sim.winner):
			for seat in sample.keys():
				if seat != sim.winner and seat != "t" and sample[seat] > sample[sim.winner] * 1.25:
					behind = true
	var record := {
		"map": map_code, "duration_s": snappedf(sim.time, 0.1), "winner": sim.winner,
		"winner_was_behind": behind, "sends": sends, "captures": captures,
		"deciding_event": last_capture, "units_lost_combat": sim.combat_losses,
		"units_lost_falls": sim.fall_losses, "last_stand_reached": sim.last_stand_active,
		"events": sim.events,
	}
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var path := "user://telemetry/match_%d.json" % Time.get_unix_time_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:                                   # user:// not writable (private browser storage, read-only profile)
		return ""
	f.store_string(JSON.stringify(record, "  "))
	return ProjectSettings.globalize_path(path)
