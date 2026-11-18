class_name KitDrill
extends Node3D
## KIT2 at drill node SIZE D on staging (kit2-staging, Daniele 2026-11-18 "also in staging gogogogo"; spec
## Docs/Game Design/Ooze Syndicate 2.0/05 Handoff/handoffs/bg-44b4 2026-11-18/NODE-SIZE-D-SPEC.md).
## The wine bands with copper edges (assets/kit/kit2/Drill_Band.glb, bake_demo2_D.py) down every Platform_Standard node's
## full-size column (WorldLayer.DRILL_R_KIT2), at the mobile spacing from under the kit2 hub cone; only bands over the goo
## surface (WorldLayer.floor_y: the flat goo plane, or the floor) are drawn. STATIC: no launcher, no QUOTA, no river - the demo's
## collar / bit / legs sit ~9 m under its 0:00 goo, so they are not here. VIEW ONLY: reads WorldLayer's tubes, nothing in the Sim.
## From bg-44b4 ea662788 WorldDrill (bands + Pack + the GLB merge), trimmed to the static case.

const BAND := "res://assets/kit/kit2/Drill_Band.glb"
const HUB_UNDER_TOP := 0.87    # m: the kit2 hub cone's bottom under the tube's top (the column top sits up inside the cone)
const BANDS := [0.91, 4.12, 7.33, 10.54, 13.75]   # m under the hub cone: the mobile band centres (3.21 m apart), as many as fit
const BAND_HH := 0.51          # m: a band's half height
const TINT_SHADER := """
shader_type spatial;
uniform bool goo = false;
uniform float alb = 0.45;
uniform float glow = 1.4;
uniform float rough = 0.3;
varying vec3 tint;
void vertex() { tint = goo ? INSTANCE_CUSTOM.rgb : COLOR.rgb; }
void fragment() { ALBEDO = tint * alb; EMISSION = tint * glow; ROUGHNESS = rough; }
"""

var wl: WorldLayer
var mm: MultiMesh
var _d: Array = []             # per kit2 tube: {tb, key, spin}
var _xf: Array = []            # per band slot: Transform3D or null
var _col := PackedColorArray()
var _cus := PackedColorArray()
var _dirty := true
var drawn := 0                 # probe: bands drawn


func build(w: WorldLayer) -> void:
	wl = w
	for tb in wl._tubes:
		if is_equal_approx(float(tb["top_off"]), WorldLayer.TUBE_TOP_KIT2):
			_d.append({"tb": tb, "key": "", "owner": null,
					"spin": fposmod(float(tb["x"]) * 0.37 + float(tb["z"]) * 0.61, TAU)})
	var n := _d.size() * BANDS.size()
	_xf.resize(n)
	_col.resize(n)
	_cus.resize(n)
	_col.fill(Color.WHITE)
	_cus.fill(Color(0, 0, 0, 0))
	mm = _mm_glb(BAND, n)


func step() -> void:
	var nb := BANDS.size()
	for i in range(_d.size()):
		var d: Dictionary = _d[i]
		var tb: Dictionary = d["tb"]
		var shown: bool = (tb["mi"] as MeshInstance3D).visible and bool(tb.get("alive", true))
		var top: float = tb.get("top_y", 999.0)
		var key := "%.2f|%s" % [top, shown]
		if key != str(d["key"]):
			d["key"] = key
			_dirty = true
			for b in range(nb):
				var y := top - HUB_UNDER_TOP - float(BANDS[b])
				if not shown or top > 900.0 or y + BAND_HH <= wl.floor_y:
					_xf[i * nb + b] = null
				else:
					_xf[i * nb + b] = Transform3D(Basis(Vector3.UP, float(d["spin"])), Vector3(float(tb["x"]), y, float(tb["z"])))
		var owner: String = str(tb.get("owner", ""))
		if owner != d["owner"]:                           # neon = seat colour, goo = faction goo (the COLOUR RULE)
			d["owner"] = owner
			var neon := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
			var goo := WorldLayer._col(owner)
			for b in range(nb):
				_col[i * nb + b] = neon
				_cus[i * nb + b] = goo
			_dirty = true
	if _dirty:
		_flush()


func _flush() -> void:
	## written packed: only the bands in use go first and visible_instance_count stops there (a zero-scale hidden instance still
	## runs its vertices: bg-44b4 measured +124k prims before packing)
	var k := 0
	for i in range(_xf.size()):
		if _xf[i] != null:
			mm.set_instance_transform(k, _xf[i])
			mm.set_instance_color(k, _col[i])
			mm.set_instance_custom_data(k, _cus[i])
			k += 1
	mm.visible_instance_count = k
	drawn = k
	_dirty = false


func _mm_glb(path: String, count: int) -> MultiMesh:
	## A kit2 GLB merged into one multi-surface mesh (node transforms applied); OS_Light -> seat neon (instance colour),
	## OS_Ooze* -> faction goo (instance custom data), other surfaces keep their GLB material.
	var mesh := ArrayMesh.new()
	var root := (load(path) as PackedScene).instantiate()
	var neon := ShaderMaterial.new()
	neon.shader = Shader.new()
	neon.shader.code = TINT_SHADER
	var goo := ShaderMaterial.new()
	goo.shader = neon.shader
	goo.set_shader_parameter("goo", true)
	goo.set_shader_parameter("alb", 0.6)
	goo.set_shader_parameter("glow", 0.9)
	goo.set_shader_parameter("rough", 0.12)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var nd: Node = mi
		while nd != root and nd is Node3D:
			xf = (nd as Node3D).transform * xf
			nd = nd.get_parent()
		var src := (mi as MeshInstance3D).mesh
		for s in range(src.get_surface_count()):
			var arr := src.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in range(v.size()):
				v[k] = xf * v[k]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for k in range(nn.size()):
					nn[k] = (xf.basis * nn[k]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nn
			arr[Mesh.ARRAY_TANGENT] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var m := src.surface_get_material(s)
			var nm := m.resource_name if m else ""
			mesh.surface_set_material(mesh.get_surface_count() - 1,
					neon if nm.begins_with("OS_Light") else (goo if nm.begins_with("OS_Ooze") else m))
	root.free()
	var m2 := MultiMesh.new()
	m2.transform_format = MultiMesh.TRANSFORM_3D
	m2.use_colors = true
	m2.use_custom_data = true
	m2.mesh = mesh
	m2.instance_count = maxi(count, 1)
	m2.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = m2
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return m2
