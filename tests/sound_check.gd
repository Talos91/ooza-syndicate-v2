extends Node
## SOUND first-pass check (a scene: tests/sound_check.tscn), windowed - a headless run builds no Sfx:
##   timeout 120 Godot --path . tests/sound_check.tscn [-- --sfx-log]
## Spectates an AI-vs-AI BRAWL match (M-30 Sporefall Plain, FFA4, Veteran - the sound demo's board), fast-forwarded
## silently to FF s of match time, for SECONDS of real time and checks that Sfx played at least MIN_TYPES different match events, that the SOUND ON / OFF and VOLUME settings
## move the Master bus at once (saved to a test cfg, never the player's), and that a UI tap plays. Prints the counts;
## exit code 0 = passed. Headless it prints SKIP and exits 0.

const MAP := "res://maps4/M-30-sporefall-plain.json"
const SECONDS := 60.0
const FF := 150.0                                  # match time fast-forwarded (silent) first: the AI idles ~25 s at the start
const MIN_TYPES := 10
const CFG := "user://test_sound.cfg"

var main: Node3D
var t := 0.0
var fails := 0
var settings_done := false


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	fails += 0 if cond else 1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP sound_check: needs a window (a headless run builds no Sfx)")
		get_tree().quit(0)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	Sfx.path = CFG
	Sfx._volume = -1                                   # read the (empty) test cfg: the default level
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1266, 585))
	Rules.abilities_on = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.set("map_path", MAP)
	main.set("mode", "FFA4")
	main.set("demo", true)
	main.set("ai_level", "Veteran")
	main.set("seed_value", 11)
	main.set("ff_to", FF)
	add_child(main)


func _process(dt: float) -> void:
	if main == null or not bool(main.get("started")):
		return
	t += dt
	if t > 5.0 and not settings_done:
		settings_done = true
		_check_settings()
	if t < SECONDS:
		return
	set_process(false)
	var types := []
	for k in Sfx.played:
		if not str(k).begins_with("ui_"):
			types.append(k)
	types.sort()
	var parts := []
	for k in types:
		parts.append("%s=%d" % [k, Sfx.played[k]])
	print("SOUND CHECK: %d match event types in %.0f s (match t=%.0f): %s" % [types.size(), t,
			float((main.get("sim") as Sim).time), ", ".join(parts)])
	var tel := {}                                      # the Sim's own telemetry over the same match, for comparison
	for ev in (main.get("sim") as Sim).events:
		if float(ev.get("t", 0.0)) < FF:
			continue
		tel[ev["type"]] = int(tel.get(ev["type"], 0)) + 1
	print("SOUND CHECK: the Sim's telemetry: %s" % [tel])
	check(types.size() >= MIN_TYPES, "at least %d match event types played" % MIN_TYPES)
	get_tree().quit(1 if fails > 0 else 0)


func _check_settings() -> void:
	var bus := 0
	check(Sfx.volume() == Rules.SOUND_VOLUME_DEFAULT and is_equal_approx(AudioServer.get_bus_volume_db(bus),
			linear_to_db(Rules.SOUND_VOLUME_DEFAULT / 100.0)), "first run: SOUND ON, VOLUME %d %% on the Master bus (%.1f dB)" % [
			Rules.SOUND_VOLUME_DEFAULT, AudioServer.get_bus_volume_db(bus)])
	Sfx.set_volume(25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25)) and not AudioServer.is_bus_mute(bus),
			"VOLUME 25 %%: the bus at once (%.1f dB)" % AudioServer.get_bus_volume_db(bus))
	Sfx.set_on(false)
	var cf := ConfigFile.new()
	check(AudioServer.is_bus_mute(bus) and not Sfx.sound_on() and cf.load(CFG) == OK and not bool(cf.get_value("audio", "on", true)),
			"SOUND OFF: the bus muted, saved in [audio]")
	Sfx.set_volume(100)
	check(AudioServer.is_bus_mute(bus), "SOUND OFF stays silent whatever the VOLUME")
	Sfx.set_on(true)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), 0.0) and not AudioServer.is_bus_mute(bus), "SOUND ON at VOLUME 100 %: 0 dB")
	Sfx._volume = -1                                   # read back from the file, as the next run would
	check(Sfx.sound_on() and Sfx.volume() == 100, "[audio] read back: ON, 100 %")
	check(Sfx.next_volume() == int(Rules.SOUND_VOLUME_STEPS[0]) and Sfx.volume_label() == "100 %", "the cycle: 100 %% -> %d %%" % int(Rules.SOUND_VOLUME_STEPS[0]))
	Sfx.set_volume(Rules.SOUND_VOLUME_DEFAULT)
	var before := int(Sfx.played.get("ui_tap", 0))
	Sfx.play_ui("tap")
	check(int(Sfx.played.get("ui_tap", 0)) == before + 1, "a UI tap plays")
