class_name Look
extends RefCounted
## LAB LOOK TEST (Daniele 2026-11-12, test branch lab-look-test only - NOT for release): --look=lab swaps
##  - the kit pieces to their "_lab" recolours (assets/kit/<key>_lab.glb, Models/2.0/look-lab/recolour_kit_lab.py;
##    geometry identical, colours from the 26S-structure-A zone sheets: ivory shell, mint glass, goo = AI tint,
##    neon = the thin player rim only), when the file is there (else the normal piece);
##  - the floor to deliveries/26F-floors-B/TILE-LAB.png (2048 px = 16 m);
##  - a screen-pinned surround (generated/look-test-2026-11-12/LAB-SURROUND-cutout.png) in front of the floor,
##    behind the board and the HUD (lines up only at the default camera, ~2.15:1).
## With no flag the game is exactly the base branch. Pure view.

static var lab := _arg() == "lab"
static var _missing := {}

const GLASS := Color("#AECAC7")    # 26S GLASS (neutral mint)
const FLOOR := "res://assets/world/look_lab/tile_lab.png"
const FLOOR_M := 16.0
const SURROUND := "res://assets/world/look_lab/lab_surround_cutout.png"
const SURROUND_SHADER := preload("res://shaders/look_surround.gdshader")
const SURROUND_DROP := 3.0       # metres under the lowest deck: the surround plane (board above it, floor under it)


static func _arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			return a.substr(7).to_lower()
	return ""


static func kit_key(key: String) -> String:
	## The lab twin of a kit key when --look=lab and the file exists; logs each key without a twin once.
	if not lab or key.begins_with("skins/") or key in ["Relay_Mount", "Relay_Retract"]:   # fx / goo_territory match those paths
		return key
	var k := key + "_lab"
	if ResourceLoader.exists("res://assets/kit/%s.glb" % k):
		return k
	if not _missing.has(key):
		_missing[key] = true
		print("LOOK lab: no twin for ", key)
	return key


static func add_surround(parent: Node3D, deck_low_y: float) -> MeshInstance3D:
	## A big horizontal plane SURROUND_DROP under the lowest deck, coloured from the screen-space picture: the board
	## (above it) occludes it, the floor / mist (under it) are covered where the picture is opaque.
	if not lab:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "LookSurround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = SURROUND_SHADER
	m.set_shader_parameter("tex", load(SURROUND))
	m.set_shader_parameter("tex_aspect", 1840.0 / 854.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, deck_low_y - SURROUND_DROP, 0)
	parent.add_child(mi)
	return mi


static func lab_world(main: Node) -> void:
	## The lab setting's air (WorldLayer.setup, after the lab backdrop): the scene's violet fill / rim / ambient made a
	## neutral mint-white so the ivory shell stays warm ivory (26S), and the height fog thinned so the TILE-LAB floor
	## shows at its own value (26F in-frame mock). The floor mist sheet and floor haze are skipped in WorldLayer.
	if not lab:
		return
	for l in main.find_children("*", "DirectionalLight3D", true, false):
		var d := l as DirectionalLight3D
		if d.light_color.b > 0.9 and d.light_color.r < 0.8:      # fill / rim (violet)
			d.light_color = Color(0.86, 0.95, 0.92)
			d.light_energy *= 0.7
		elif d.shadow_enabled:                                   # the sun: the ivory at its sheet value, not clipped white
			d.light_energy *= 0.78
	for c in main.find_children("*", "WorldEnvironment", true, false):
		var env := (c as WorldEnvironment).environment
		if env != null:
			env.ambient_light_color = Color(0.86, 0.9, 0.86)
			env.fog_height_density = 0.008
