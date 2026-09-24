class_name HordeView
extends Node3D
## Draws every horde as a chain of patches (assets/horde/patches_<faction>.glb) laid along its
## path: head at the horde's position, patches trailing back at Rules.PATCH_SPACING, one patch per
## Rules.UNITS_PER_PATCH units. Goo = seat colour; creatures = seat hue + race accent.
## Absorbing into a node: the head squeezes into the door and the chain shortens as units drain.

const KINDS := ["head", "body_a", "body_b", "body_c", "tail"]
var meshes := {}      # faction -> kind -> Mesh
var textures := {}    # faction -> creature Texture2D
var pools := {}       # horde id -> {"patches": [MeshInstance3D], "label": Label3D}


func load_faction(faction: String) -> void:
	if meshes.has(faction):
		return
	var root: Node = load("res://assets/horde/patches_%s.glb" % faction).instantiate()
	meshes[faction] = {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		for kind in KINDS:
			if String(mi.name).ends_with("_" + kind) or String(mi.get_parent().name).ends_with("_" + kind):
				meshes[faction][kind] = (mi as MeshInstance3D).mesh
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m and m.albedo_texture and not textures.has(faction):
				textures[faction] = m.albedo_texture
	root.free()


func sync(sim: Sim, viewer: String) -> void:
	var alive := {}
	for h in sim.hordes:
		alive[h["id"]] = true
		_draw(h, viewer)
	for id in pools.keys():
		if not alive.has(id):
			for p in pools[id]["patches"]:
				p.queue_free()
			pools[id]["label"].queue_free()
			pools.erase(id)


func _draw(h: Dictionary, viewer: String) -> void:
	var faction: String = h["faction"]
	load_faction(faction)
	if not pools.has(h["id"]):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.016
		label.font_size = 80
		label.outline_size = 20
		label.no_depth_test = true
		label.modulate = Rules.SEATS[h["owner"]]
		add_child(label)
		pools[h["id"]] = {"patches": [], "label": label}
	var pool: Dictionary = pools[h["id"]]
	var n := clampi(ceili(h["units"] / Rules.UNITS_PER_PATCH), 1, Rules.MAX_PATCHES)
	var arr: Array = pool["patches"]
	while arr.size() < n:
		var mi := MeshInstance3D.new()
		add_child(mi)
		arr.append(mi)
	for i in range(arr.size()):
		var mi: MeshInstance3D = arr[i]
		var s: float = h["s"] - i * Rules.PATCH_SPACING
		if i >= n or s < 0.0:
			mi.visible = false
			continue
		var kind: String = "head" if i == 0 else ("tail" if i == n - 1 else KINDS[1 + (i % 3)])
		var mesh: Mesh = meshes[faction][kind]
		if mi.mesh != mesh:
			mi.mesh = mesh
			for sidx in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(sidx) as BaseMaterial3D
				var is_creature := m != null and m.albedo_texture != null
				mi.set_surface_override_material(sidx, Mats.creature(faction, h["owner"], textures[faction])
						if is_creature else Mats.goo(h["owner"]))
		mi.visible = true
		var smp := Sim.sample(h, s)
		var fwd: Vector3 = smp[1]
		mi.position = smp[0]
		mi.rotation = Vector3(0.0, Rules.heading(fwd), 0.0)
		var sc := 1.0
		if h["state"] == "absorb" and i == 0:
			sc = 0.45                                  # squeezing in through the door
		elif s < 2.0:
			sc = 0.5 + 0.25 * s                        # emerging from the tank bottoms
		mi.scale = Vector3(sc, sc, sc)
	var label: Label3D = pool["label"]
	var head: Vector3 = Sim.sample(h, h["s"])[0]
	label.position = head + Vector3(0, 3.0, 0)
	label.text = str(int(h["units"])) if h["owner"] == viewer else ""
