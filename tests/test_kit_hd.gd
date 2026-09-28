extends SceneTree
## Headless check:  Godot --headless --path . --script res://tests/test_kit_hd.gd
## Alpha 21 "Phones only" (Daniele): both the light kit (assets/kit/) and the HD kit
## (assets/kit_hd/) resolve and load, on both sides of PerfProfile.hd() (native/editor - a web pack
## fetch is a separate, unavoidably manual check). Not part of the numbered rules suites; run it
## alongside them after any Cosmetics.kit_path / HD_DEFAULTS change.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	PerfProfile.force_level("full")                    # PerfProfile.hd() == true: desktop / FULL
	check(PerfProfile.hd(), "PerfProfile.hd() true on the full profile")
	for key in Cosmetics.HD_DEFAULTS.keys():
		var path := Cosmetics.kit_path(key)
		check(path == Cosmetics.KIT_HD % key, "desktop: %s resolves to kit_hd" % key)
		check(ResourceLoader.exists(path), "desktop: %s exists (%s)" % [key, path])
		var scene := load(path) as PackedScene
		check(scene != null and scene.instantiate() != null, "desktop: %s instantiates" % key)

	PerfProfile.force_level("phone")                   # PerfProfile.hd() == false: phone
	check(not PerfProfile.hd(), "PerfProfile.hd() false on the phone profile")
	for key in Cosmetics.HD_DEFAULTS.keys():
		var path := Cosmetics.kit_path(key)
		check(path == Cosmetics.KIT % key, "phone: %s resolves to light kit" % key)
		check(ResourceLoader.exists(path), "phone: %s exists (%s)" % [key, path])
		var scene := load(path) as PackedScene
		check(scene != null and scene.instantiate() != null, "phone: %s instantiates" % key)

	# a sample of skin keys (every "skins/" key has both a light and an HD copy - Skin Designer's
	# phone rebuilds cover all 69 1:1): one per source family is enough to catch a naming mismatch.
	var sample := ["skins/NULL_Vat_T2", "skins/Vat_Graduate_T3", "skins/Skin_Hive_T1",
		"skins/Forge_Anvil", "skins/Laser_Tesla", "skins/Machinegoon_T2_Pepperbox",
		"skins/MonsterHub_VEX_Pit", "skins/Monster_SOLAR_Eclipse"]
	for key in sample:
		PerfProfile.force_level("full")
		var hd_path := Cosmetics.kit_path(key)
		check(hd_path == Cosmetics.KIT_HD % key, "desktop: %s resolves to kit_hd/skins" % key)
		check(ResourceLoader.exists(hd_path), "desktop: %s exists (%s)" % [key, hd_path])
		PerfProfile.force_level("phone")
		var light_path := Cosmetics.kit_path(key)
		check(light_path == Cosmetics.KIT % key, "phone: %s resolves to skins.pck light" % key)
		check(ResourceLoader.exists(light_path), "phone: %s exists (%s)" % [key, light_path])

	# every current skins.pck / skins_hd.pck file exists under both directories with the same name
	for f in DirAccess.get_files_at("res://assets/kit/skins"):
		if not f.ends_with(".glb"):
			continue
		check(FileAccess.file_exists("res://assets/kit_hd/skins/" + f), "kit_hd/skins has %s" % f)

	PerfProfile.force_level("")
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	quit(1 if failures > 0 else 0)
