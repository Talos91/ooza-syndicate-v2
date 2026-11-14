class_name Look
extends RefCounted
## LAB LOOK (Daniele 2026-11-12: lab2 = the new standard, default since 0.24.2 via Rules.LOOK_LAB2; --look-old = 0.24.1). --look=lab swaps
##  - the kit pieces to their "_lab" recolours (assets/kit/<key>_lab.glb, Models/2.0/look-lab/recolour_kit_lab.py;
##    geometry identical, colours from the 26S-structure-A zone sheets: ivory shell, mint glass, goo = AI tint,
##    neon = the thin player rim only), when the file is there (else the normal piece);
##  - lab2 (default): the PRODUCTION LAB KIT first (assets/kit/labkit/<key>.glb, branch lab-kit 9d2f186: vats = the
##    capneon set, Daniele's pick; structures, piers, conveyors, platforms; node base + pit as vertex-colour meshes for
##    the world shaders), then the "_lab2" recolour, then the normal piece. Runtime tint slots kept (OS_Light / OS_Ooze_*).
##  - the floor to deliveries/26F-floors-B/TILE-LAB.png (2048 px = 16 m);
##  - a screen-pinned surround in front of the floor, behind the board and the HUD: lab2 = the 26B2 surround
##    (deliveries/26B2-lab-surround/SURROUND-*-WALLS.png, tools/lab_wire/make_surround.py): the PHONE plate on phone
##    aspects, the WIDE plate on 16:9 and narrower; v1 = generated/look-test-2026-11-12/LAB-SURROUND-cutout.png.
## Pure view: no rule changes.

static var lab := _arg() in ["lab", "lab2"]
static var v2 := _arg() == "lab2"   # designer v2 (2026-11-12): cream satin shell kept under the glow, owner rim ~2x and brighter,
                                    # goo shows through clearer glass; floor / surround / lights as v1
const RIM_IN := 5.86                # v2 owner rim: a 0.28 m flat band on the platform lip (the kit band is 0.14 m on the side)
const RIM_OUT := 6.14
const RIM_ENERGY := 1.5             # v2 owned rim emission (Mats.light: 3.0)
const KIT_RIM_ENERGY := 1.5         # vat-neon round 2: 4.5 / 2.2 tonemapped every channel > 1 to WHITE (the owner colour only in the halo); <= ~1.5 keeps the hue. Was 2.2 (owner neon far too faint on a phone, Daniele 2026-11-13); owner reads at a glance
static var _rim_mesh: ArrayMesh
static var _missing := {}

const GLASS := Color("#AECAC7")    # 26S GLASS (neutral mint)
const FLOOR := "res://assets/world/look_lab/tile_lab.png"
const FLOOR_M := 16.0
const SURROUND := "res://assets/world/look_lab/lab_surround_cutout.png"     # v1 only (out of the Web export)
const SURROUND_PHONE := "res://assets/world/look_lab/lab_surround_phone.png"  # 26B2, 2436 x 1125 (3248 x 1500 source)
const SURROUND_WIDE := "res://assets/world/look_lab/lab_surround_wide.png"    # 26B2, 2560 x 1440 (3840 x 2160 source)
const LABKIT := "res://assets/kit/labkit/%s.glb"
const LABKIT_SKIP := ["Relay_Mount"]   # fx / goo_territory match its path; the kit's reference pieces are not kit keys
const SURROUND_SHADER := preload("res://shaders/look_surround.gdshader")
const SURROUND_DROP := 3.0       # metres under the lowest deck: the surround plane (board above it, floor under it)


static func _arg() -> String:
	## Default = "lab2" while Rules.LOOK_LAB2 (staging 0.24.2, Daniele 2026-11-12). Dev: --look-old = the 0.24.1 look,
	## --look=lab = the v1 test (its _lab kit twins are not in the Web export, so on Web it falls back to the normal kit).
	var args := OS.get_cmdline_user_args()
	if "--look-old" in args:
		return ""
	for a in args:
		if a.begins_with("--look="):
			var v := a.substr(7).to_lower()
			if v in ["lab", "lab2"]:
				return v                      # (other --look= values are the FACTION LOOK debug in main.gd)
	return "lab2" if Rules.LOOK_LAB2 else ""


static func kit_key(key: String) -> String:
	## The lab twin of a kit key when --look=lab and the file exists; logs each key without a twin once.
	if not lab or key.begins_with("skins/") or key in ["Relay_Mount", "Relay_Retract"]:   # fx / goo_territory match those paths
		return key
	if v2:
		var lk := ("labkit/%s_capneon" % key) if key.begins_with("Vat_T") else "labkit/" + key
		if not key in LABKIT_SKIP and ResourceLoader.exists(LABKIT % lk.substr(7)):
			return lk
	var k := key + ("_lab2" if v2 else "_lab")
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
	if v2:
		var vs := parent.get_viewport().get_visible_rect().size if parent.is_inside_tree() else Vector2(812, 375)
		var phone := vs.x / maxf(vs.y, 1.0) > 1.97      # between 16:9 (1.78) and the phone plate (2.165)
		m.set_shader_parameter("tex", load(LookTheme.world("surround_phone", SURROUND_PHONE) if phone else LookTheme.world("surround_wide", SURROUND_WIDE)))   # THEMES
		m.set_shader_parameter("tex_aspect", 3248.0 / 1500.0 if phone else 16.0 / 9.0)
	else:
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
		elif d.light_color.r > 0.99 and d.light_color.b < 0.9:   # the sun (warm key; the phone profile has switched its shadows off)
			d.light_energy *= 0.45 if v2 else 0.78               # v2: deck luma ~214 at 812 --mobile (designer: 200-215)
	for c in main.find_children("*", "WorldEnvironment", true, false):
		var env := (c as WorldEnvironment).environment
		if env != null:
			env.ambient_light_color = Color(0.86, 0.9, 0.86)
			env.fog_height_density = 0.008
			if v2:
				env.glow_hdr_threshold = 1.4      # v2: the cream shell stays under the bloom threshold, neon (energy 3-5) still glows
				env.glow_bloom = 0.0              # (bloom > 0 blooms every pixel whatever the threshold: the white haze at 1920)
				env.glow_intensity = 0.5           # the neon halo stays, the cream shell does not haze over
				if not bool(main.get("mobile")):   # the desktop path (no RenderScale SubViewport) renders the cream ~1.5x brighter:
					env.tonemap_exposure = 0.5     # 0.9 clipped 19 % of the 1920 board at >= 250 luma; 0.5: 2.5 % (baseline 2.9 %)


static func rim(part: Node, seat: String) -> void:
	## v2: owned platforms get a flat 0.28 m rim band in the owner colour on the lip (twice the kit band, seen from the
	## game camera); neutral platforms stay rimless (the _lab2 kit band is shell cream, no emission).
	if not v2 or not is_instance_valid(part) or not (part as Node).scene_file_path.contains("/Platform_"):
		return
	var mi := (part as Node).get_node_or_null("LookRim") as MeshInstance3D
	if mi == null:
		if _rim_mesh == null:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 64
			for i in range(n):
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var p := [Vector3(cos(a0) * RIM_IN, 0, sin(a0) * RIM_IN), Vector3(cos(a0) * RIM_OUT, 0, sin(a0) * RIM_OUT),
						Vector3(cos(a1) * RIM_OUT, 0, sin(a1) * RIM_OUT), Vector3(cos(a1) * RIM_IN, 0, sin(a1) * RIM_IN)]
				st.set_normal(Vector3.UP)
				for k in [0, 2, 1, 0, 3, 2]:
					st.add_vertex(p[k])
			_rim_mesh = st.commit()
		mi = MeshInstance3D.new()
		mi.name = "LookRim"
		mi.mesh = _rim_mesh
		mi.position = Vector3(0, 0.03, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _rim_mat(Color.WHITE)  # an override from the start: MapBatch never adopts it (layers 0)
		(part as Node).add_child(mi)
	mi.visible = seat != ""
	mi.layers = 1
	if seat != "":
		mi.material_override = _rim_mat(Rules.seat_color(seat))


static func light_energy() -> float:
	## v2: the owner neon strips brighter than the normal 3.0
	return KIT_RIM_ENERGY if v2 and ResourceLoader.exists(LABKIT % "Platform_Standard") else (RIM_ENERGY if v2 else 3.0)


static var _rim_mats := {}
static func _rim_mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _rim_mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c * 0.35
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = RIM_ENERGY
		m.cull_mode = BaseMaterial3D.CULL_DISABLED      # a flat band seen from above whatever its winding
		_rim_mats[k] = m
	return _rim_mats[k]


static func kit_vc_mesh(key: String, light_k := 0.6, goo := true) -> ArrayMesh:
	## lab2: a production lab-kit piece (assets/kit/labkit/<key>.glb) merged into ONE vertex-colour surface for the world
	## shaders (world_entrance / world_ring), so it drops into their MultiMesh as the procedural mesh did: OS_Light* = the
	## magenta owner-light key (k, 0, k), OS_Ooze* = the green goo key (0, 0.6, 0) when goo, every other material its albedo
	## (display value) - the shaders' kit branch shades it like the kit pieces. Null when not lab2 or the file is not there.
	if not v2 or not ResourceLoader.exists(LABKIT % key):
		return null
	var root := (load(LABKIT % key) as PackedScene).instantiate()
	var kind := LookTheme.kind_of(key + ".glb")         # THEMES: Node_Base = deck zones, Pit = pit zones
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		var xf := m3.transform
		var p := m3.get_parent()
		while p != null and p != root and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for s in range(m3.mesh.get_surface_count()):
			var mat := m3.mesh.surface_get_material(s)
			var nm := mat.resource_name if mat != null else ""
			var c := Color(0.5, 0.5, 0.5)
			if nm.begins_with("OS_Light"):
				c = Color(light_k, 0.0, light_k)
			elif goo and nm.begins_with("OS_Ooze"):
				c = Color(0.0, 0.6, 0.0)
			elif mat is StandardMaterial3D:
				c = (mat as StandardMaterial3D).albedo_color           # display values: the world shaders output COLOR as is
				var th := LookTheme.role(kind, nm)
				if not th.is_empty():
					c = th[0]
				if c.g < 0.02 and c.r > 0.03 and absf(c.r - c.b) < 0.03:
					c.g = 0.03                                  # never read as the owner key
			var arr := m3.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			var order: Array = range(vs.size()) if idx == null else Array(idx)
			for i in order:
				st.set_color(c)
				st.set_normal((xf.basis * ns[i]).normalized() if ns.size() > i else Vector3.UP)
				st.add_vertex(xf * vs[i])
				n += 1
	root.free()
	if n == 0:
		return null
	var out := st.commit()
	out.resource_name = "labkit"                         # world_layer: the entrance shader's kit branch
	return out
