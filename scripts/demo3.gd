class_name Demo3
extends Node
## DEMO 3 (throwaway, branch demo3-pit-v4, 2026-11-21; NOT for main): /staging/demo3/ opens straight into G-05 Catapult Bay
## with the 🎨 UI designer's Blender scene (r7 nodes, 4.4 m bridges, pit v4 + goo) in place of the game's own platforms,
## bridges, background and goo, so Daniele can judge the proportions on his phone with the real match HUD on top.
## The board is frozen (main._process does not step the Sim or the AI). One HUD control: DRAIN / FILL moves the goo plane
## (and its collars) between the two heights of the alignment json. On only when Rules.VERSION contains "-demo3".

## ROUND 3 (2026-11-22, 0.25.1-demo3-g03half): G-03 Crescent with HALF-length bridges (closer platforms, zoomed-in camera).
## patch_map() moves G-03's 15 nodes to the designer's half layout (G03_half_node_positions_game.json); each deck's rim exits
## A / B move with their platform (same 6 m rim radius, same angle to the deck), so L (= the travel time at the constant
## speed, Sim.edge_cost) and deckMetres follow the new positions. Graph, edges, relays and seats are G-03's own.
const MAP := "res://maps4/G-03-crescent.json"
const GLB := "res://assets/demo3/g03half_pit_v4.glb"
const PFX := "D3H_"                      # the GLB's node prefix (D3H_MAP_node00.., D3H_BG_pit_v4_goo, D3H_BGc_* collars)
const HALF_NODES := {                    # demo3-export/G03_half_node_positions_game.json (layout x, layout y = glTF X, Z)
	"0": [-37.613, -16.78], "1": [37.612, -16.783], "2": [-25.043, -17.683], "3": [25.041, -17.682],
	"4": [-11.766, -14.309], "5": [11.765, -14.308], "6": [-0.002, -7.458], "7": [-25.404, -3.964],
	"8": [25.407, -3.964], "9": [-37.855, -0.225], "10": [37.858, -0.227], "11": [-10.958, 0.217],
	"12": [10.962, 0.206], "13": [-18.584, 10.718], "14": [18.581, 10.714]}
const GOO_FULL := -9.471                 # G03_half_alignment.json goo_y_full (game metres, glTF Y; same as G-05)
const GOO_DRAINED := -11.681             # goo_y_drained
const GOO_TIME := 1.6                    # s for the goo to move between the two

var main: Node3D
var root: Node3D
var goo: Array = []                      # [Node3D, y at FULL]
var drained := false
var btn: Button
var readout: Label
var _tw: Tween


static func on() -> bool:
	return Rules.VERSION.contains("-demo3")


static func patch_map(map: Dictionary) -> void:
	## ROUND 3: G-03's layout nodes -> the half layout; deck rim exits follow (radius and angle to the deck kept); L and
	## deckMetres recomputed. Prints old -> new travel seconds with --demo3-dump.
	var lay: Dictionary = map["layout"]
	var old: Dictionary = (lay["nodes"] as Dictionary).duplicate(true)
	for k in HALF_NODES:
		lay["nodes"][k] = (HALF_NODES[k] as Array).duplicate()
	var dump := "--demo3-dump" in OS.get_cmdline_user_args()
	for i in range(map["edges"].size()):
		var e: Dictionary = map["edges"][i]
		var g: Dictionary = lay["edges"][i]
		var a := str(int(e["from"]))
		var b := str(int(e["to"]))
		var oa := Vector2(old[a][0], old[a][1])
		var ob := Vector2(old[b][0], old[b][1])
		var na := Vector2(lay["nodes"][a][0], lay["nodes"][a][1])
		var nb := Vector2(lay["nodes"][b][0], lay["nodes"][b][1])
		var turn_a := (nb - na).angle() - (ob - oa).angle()
		var turn_b := (na - nb).angle() - (oa - ob).angle()
		var A := na + (Vector2(g["A"][0], g["A"][1]) - oa).rotated(turn_a)
		var B := nb + (Vector2(g["B"][0], g["B"][1]) - ob).rotated(turn_b)
		var l_old := float(g["L"])
		var l_new := A.distance_to(B)
		g["A"] = [A.x, A.y]
		g["B"] = [B.x, B.y]
		g["L"] = l_new
		var piers := float(g["p0"]) + float(g["p1"])  # 1.6 m pier stubs each: on the shortest half decks (1.6 m rim to rim)
		if piers > 0.6 * l_new:                      # they would overlap, so they shrink to 30 % of the deck each (the game's
			g["p0"] = float(g["p0"]) * 0.6 * l_new / piers   # piers are hidden in demo3; this keeps Sim.deck_line forward)
			g["p1"] = float(g["p1"]) * 0.6 * l_new / piers
		if e.get("deckMetres") != null:
			e["deckMetres"] = maxf(float(e["deckMetres"]) + l_new - l_old, 0.5)
		if dump:
			print("DEMO3 edge %s-%s L %.2f -> %.2f m  %.2f -> %.2f s" % [a, b, l_old, l_new,
					l_old / Rules.move_speed(), l_new / Rules.move_speed()])


static func apply(m: Node3D) -> Demo3:
	var d := Demo3.new()
	d.name = "Demo3"
	m.add_child(d)
	d._setup(m)
	return d


func _setup(m: Node3D) -> void:
	main = m
	var vis: Dictionary = m.get("vis")
	var sim = m.get("sim")
	for n in sim.nodes:                              # the game's platforms / junction pieces go; vats, towers, relays stay
		var e = vis.get(n["id"])
		if e is Dictionary and e.get("platform") is Node3D:
			(e["platform"] as Node3D).visible = false
	for key in ["edge_decks", "edge_piers", "edge_conn"]:   # the game's bridges, piers and connectors go
		for arr in (vis.get(key, {}) as Dictionary).values():
			for x in arr:
				if x is Node3D:
					(x as Node3D).visible = false
	for c in (vis.get("conduits", {}) as Dictionary).values():
		if c is Node3D:
			(c as Node3D).visible = false
	var wl = m.get("world_layer")                    # columns, goo plane, splats
	if wl is Node3D:
		(wl as Node3D).visible = false
	var cs = m.get("contact_shade")                  # seat plates / contact shadows drawn for the game's platforms
	if cs is Node3D:
		(cs as Node3D).visible = false
	var sc = m.get("scenery")                        # the painted pit backdrop (CanvasLayer -50)
	if sc != null and sc.get("pit") != null and sc.pit.back != null:
		sc.pit.back.visible = false
	root = (load(GLB) as PackedScene).instantiate()  # already in game metres, centred on the map centre = world origin
	m.add_child(root)
	for c in root.find_children("*", "Node3D", true, false):
		var nm := String(c.name)
		if nm.begins_with(PFX + "BG_pit_v4_goo") or nm.begins_with(PFX + "BGc_"):
			goo.append([c, (c as Node3D).global_position.y])
	_build_control()
	if "--demo3-dump" in OS.get_cmdline_user_args():
		_dump(sim)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo3-shot="):            # dev: full + drained frames as demo3_full.png / demo3_drained.png, then quit
			_shot_dir = a.substr(13)


var _shot_dir := ""
var _frames := 0


func _process(_dt: float) -> void:
	var hud = main.get("hud")                        # round 2 (Daniele 11-21): no garrison / unit-count plates on the nodes
	if hud != null and hud.get("badge_layer") != null and hud.badge_layer.visible:   # (the HUD is built after apply())
		hud.badge_layer.visible = false
	if _shot_dir == "":
		return
	_frames += 1
	if _frames == 120:
		get_viewport().get_texture().get_image().save_png(_shot_dir + "/demo3_full.png")
		set_drained(true)
	elif _frames == 160:
		get_viewport().get_texture().get_image().save_png(_shot_dir + "/demo3_drained.png")
		get_tree().quit()


func _build_control() -> void:
	## A small neon chip (44 pt tap target) with its readout (GOO FULL / GOO DRAINED) beside it; placed by _place.
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(96, 44)
	btn.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.86)
	sb.border_color = Color(0.25, 1.0, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	var sp := sb.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.1, 0.3, 0.24, 0.9)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(0.85, 1.0, 0.95))
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.pressed.connect(toggle)
	box.add_child(btn)
	readout = Label.new()
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", 13)
	readout.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
	readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	readout.add_theme_constant_override("outline_size", 4)
	box.add_child(readout)
	_label()
	_place(box)
	get_viewport().size_changed.connect(func(): _place(box))


func _place(box: Control) -> void:
	## bottom-left, right of the map's name (free there in the match HUD), scaled with the HUD (hud.ui_scale)
	var vp := get_viewport().get_visible_rect().size
	var h = main.get("hud")
	var k: float = float(h.ui_scale) if h != null and h.get("ui_scale") != null else 1.0
	box.scale = Vector2(k, k)
	box.position = Vector2(vp.x * 0.135, vp.y - 50.0 * k)


func _label() -> void:
	btn.text = "FILL" if drained else "DRAIN"
	readout.text = "GOO DRAINED" if drained else "GOO FULL"


func toggle() -> void:
	set_drained(not drained, true)


func set_drained(d: bool, animate := false) -> void:
	drained = d
	_label()
	var dy := (GOO_DRAINED - GOO_FULL) if drained else 0.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not animate:
		for g in goo:
			(g[0] as Node3D).global_position.y = float(g[1]) + dy
		return
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for g in goo:
		_tw.tween_property(g[0], "global_position:y", float(g[1]) + dy, GOO_TIME)


func _dump(sim) -> void:
	## dev: --demo3-dump prints the GLB node / junction centres and tops against the Sim's node positions
	for c in root.find_children(PFX + "MAP_*", "Node3D", true, false):
		var nm := String(c.name)
		if not (nm.begins_with(PFX + "MAP_node") or (nm.begins_with(PFX + "MAP_j") and not nm.ends_with("_col"))):
			continue
		var id := int(nm.trim_prefix(PFX + "MAP_node").trim_prefix(PFX + "MAP_j"))
		var top := -INF
		var box := AABB()
		for mi in c.find_children("*", "MeshInstance3D", true, false) + ([c] if c is MeshInstance3D else []):
			var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			top = maxf(top, ab.end.y)
			box = ab if box.size == Vector3.ZERO else box.merge(ab)
		var gp: Vector3 = (c as Node3D).global_position
		var sp: Vector3 = sim.nodes[id]["pos"] if id < sim.nodes.size() else Vector3.INF
		print("DEMO3 %s w=%.2f d=%.2f glb=(%.3f, %.3f, %.3f) top=%.3f sim=(%.3f, %.3f, %.3f) dxz=%.3f" % [nm, box.size.x, box.size.z, gp.x, gp.y, gp.z, top,
				sp.x, sp.y, sp.z, Vector2(gp.x - sp.x, gp.z - sp.z).length()])
	print("DEMO3 goo nodes %d" % goo.size())
