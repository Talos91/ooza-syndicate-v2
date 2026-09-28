class_name CampaignPage
extends Control
## The CAMPAIGN menu page (CAMPAIGN-DESIGN.md §3, `Menu.show_campaign`): the sinking city seen from above IS the
## campaign map (Daniele, 2026-09-27). Each district (a chapter) is a small diorama built from the game's own kit
## (MapBuilder.piece / put, Scenery's light, sky and void) in a SubViewport behind the 2D page, under a top camera
## like a match: a mission is a node, main missions are joined in order by retract bridges, a side mission hangs off
## its parent behind a switch relay, THE DESCENT hangs under the city. Self-contained like TutorialPage (its own
## 1280x720 canvas scaled by _fit(), NeonPanel frames, Hud.panel_style + UiSkin buttons, Rajdhani / Russo One, the
## phone tap() / rh() / fsz() minimums: every tap target >= 44 pt and every text >= 12.5 pt on a landscape phone).
## Everything it shows comes from Campaign (data, progress, stars, rewards); it never changes Campaign's rules.
##
## Mission node states (§3): locked (grey kit, empty socket), open (neutral vat, a pulsing ring), won (the campaign
## faction's goo ring, a vat one tier up per star, 1-3 star pips and a SCRAP mark on its plate), IN DEVELOPMENT
## (Campaign.playable() false: a construction-yellow ring and tag). Every node and relay has an invisible tap target
## over its projected position.
## Animations (every mechanic ships with its animation, readout and control):
##   after a mission (Campaign.last_run, set by main.gd): the new stars pop, a first win extends the bridge to the
##   mission it opened (the retract motion in reverse); then last_run is cleared;
##   the side relay: tapping it swings its deck over to the side mission (~1 s), then opens its card;
##   district collapse: a done district not yet seen ("collapse:<id>") drops ring by ring into the void in its
##   `collapse` order (3-4 s, tap to skip), the camera pans on, and the district stays as a sunk, desaturated
##   memorial (still tappable to replay);
##   THE DESCENT (`descent: true`): darker, the camera tipped low to look under the city.
##
## Public API
##   set_faction(key)        the campaign tab to open (falls back to the first with content) and the page skin
##   set_mobile(is_mobile)   phone minimums
##   show_district(i, animate := true)   / open_card(key) / close_card() / skip()    (tests, screenshot helpers)
## Signals
##   play_pressed(key)       PLAY on a mission card (open and playable only)
##   back_pressed            BACK

signal play_pressed(key: String)
signal back_pressed
signal view_pressed                                # UI (Alpha 21): the menu's switch to the mission cards view

var view_switch := ""                              # UI: a label shows the view switch under BACK ("" = none)

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const CANVAS := Vector2(1280.0, 720.0)

# Phone sizing - TutorialPage's numbers (menu.gd's "Phone sizing").
const MIN_TAP_PT := 44.0
const MIN_FONT_PT := 12.5
const PHONE_PT_H := 390.0

# The diorama (metres, the kit's sizes: Rules.R / PIER / S).
const DISTRICT_GAP := 200.0            # districts side by side along x; the camera pans between them
const PITCH := 58.0                    # the top camera, like a match (degrees above the horizon)
const DESCENT_PITCH := 24.0            # THE DESCENT: tipped low, looking under the city
const DESCENT_STEP := 4.0              # each Descent mission one layer lower than the last
const FOV := 42.0                      # main.gd's match camera
const SWING_PARK := 1.3                # the side relay's deck parked this far off its line (radians)
const SWING_TIME := 1.0                # §3: the relay animation, 1 s
const BRIDGE_TIME := 1.2
const DROP_STAGGER := 0.42             # collapse: one ring every DROP_STAGGER s (8 rings -> ~3.5 s)
const DROP_TIME := 1.0
const SCRAP := Color("ffc94a")         # the free currency's mark
const GREY := Color("5d6a73")

var faction := "vex"                   # the campaign shown (and the page skin)
var mobile := false
var standalone_backdrop := true        # Menu sets false; the 3D view is opaque either way

var content: Control                   # the 1280x720 canvas
var _view: SubViewportContainer
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _env: Environment
var _sky: CanvasItem
var _catcher: Control                  # behind the canvas: taps on the empty diorama close the card, swipes page
var _districts: Array = []             # per district: {d, root, groups, decor, nodes, bridges, relays, descent}
var _cur := 0
var _cam_now := [Vector3.ZERO, 100.0, PITCH]   # target, distance, pitch
var _card_key := ""
var _card: Control
var _busy := false                     # an intro / collapse is playing: node taps wait
var _skip := false
var _tweens: Array = []
var _skip_btn: Button
var _skip_label: Label
var _swung := {}                       # side key -> true once its deck was swung over this visit
var _press_at := Vector2.INF
var _swiped_ms := -10000
var _pulse_t := 0.0
var _mats := {}
var _void: Array = []                  # the void's mist layers (rebuilt with the world)
var _look_from := 0                    # the district whose look (normal / memorial / descent) is on


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Campaign.load_if_needed()                          # AUDIT FIX: never re-read (private browsing: the file never saved)
	if not Campaign.has_content(faction):
		faction = _first_with_content()
	_build_view()
	_catcher = Control.new()
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_fit)
	_build_world()
	var lr := _take_last_run()
	_cur = _start_district(lr)
	_fit()
	_rebuild_ui()
	_snap_camera()
	_intro(lr)


func _fit() -> void:
	## TutorialPage's recipe: the canvas scaled to fit and centred; the 3D view fills the whole screen behind it.
	if not is_instance_valid(content):
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var s := minf(vp.x / CANVAS.x, vp.y / CANVAS.y)
	content.size = CANVAS
	content.scale = Vector2(s, s)
	content.position = (vp - CANVAS * s) / 2.0
	_catcher.position = Vector2.ZERO
	_catcher.size = vp
	_view.position = Vector2.ZERO
	_view.size = vp
	_vp.size = Vector2i(maxi(1, int(vp.x)), maxi(1, int(vp.y)))
	if not _districts.is_empty():
		_snap_camera()


func _pt_factor() -> float:
	if not mobile:
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0
	var s := minf(vp.x / CANVAS.x, vp.y / CANVAS.y)
	return s * (PHONE_PT_H / vp.y) if s > 0.0 else 0.0


func tap(dims: Vector2) -> Vector2:
	## Both sides at least the phone tap minimum (a square icon button must be 44 pt wide as well as tall).
	return Vector2(rh(dims.x), rh(dims.y))


func rh(base: float) -> float:
	var f := _pt_factor()
	return maxf(base, (MIN_TAP_PT / f) if f > 0.0 else 0.0)


func fsz(size_value: int) -> int:
	var f := _pt_factor()
	return maxi(size_value, int(ceil(MIN_FONT_PT / f))) if f > 0.0 else size_value


func _color() -> Color:
	return Rules.FACTIONS[faction][1] if Rules.FACTIONS.has(faction) else Color("18dae8")


# ------------------------------------------------------------------ public API
func set_faction(key: String) -> void:
	faction = key if Campaign.has_content(key) else _first_with_content()


func set_mobile(is_mobile: bool) -> void:
	mobile = is_mobile


func show_district(i: int, animate := true) -> void:
	if _districts.is_empty():
		return
	i = clampi(i, 0, _districts.size() - 1)
	close_card(false)
	_cur = i
	_rebuild_ui()
	if animate:
		await _pan_to(i, 0.6)
	else:
		_snap_camera()
	if is_inside_tree():
		_arrive()


func current_district() -> int:
	return _cur


func open_card(key: String) -> void:
	var m := Campaign.mission(key)
	if m.is_empty():
		return
	var di := _district_index(str(m["district"]))
	if di != _cur:
		_cur = di
		_rebuild_ui()
		_snap_camera()
	_card_key = key
	_build_card(m)
	_rebuild_ui()
	_tween_camera(0.35)


func close_card(refit := true) -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	if _card_key == "":
		return
	_card_key = ""
	if refit and is_inside_tree():
		_rebuild_ui()
		_tween_camera(0.35)


func card_key() -> String:
	return _card_key


func busy() -> bool:
	return _busy


func skip() -> void:
	## Finish whatever intro / collapse is playing (the TAP TO SKIP target).
	_skip = true
	for tw in _tweens:
		if (tw as Tween).is_valid():
			(tw as Tween).custom_step(60.0)
	_tweens.clear()


# ------------------------------------------------------------------ helpers
func _first_with_content() -> String:
	for f in Campaign.FACTION_ORDER:
		if Campaign.has_content(f):
			return f
	return "vex"


func _district_index(id: String) -> int:
	for i in range(_districts.size()):
		if str(_districts[i]["d"]["id"]) == id:
			return i
	return 0


func _take_last_run() -> Dictionary:
	## main.gd hands a finished mission over once (Campaign.last_run = {key, summary}); the page plays it, then clears it.
	var lr: Dictionary = Campaign.last_run
	Campaign.last_run = {}
	if lr.is_empty() or Campaign.faction_of(str(lr.get("key", ""))) != faction or Campaign.mission(str(lr["key"])).is_empty():
		return {}
	return lr


func _start_district(lr: Dictionary) -> int:
	if not lr.is_empty():
		return _district_index(str(Campaign.mission(str(lr["key"]))["district"]))
	for i in range(_districts.size()):                 # a done district whose collapse was never seen plays it first
		if _collapse_due(i):
			return i
	var nxt := Campaign.next_open(faction)
	if nxt != "":
		return _district_index(str(Campaign.mission(nxt)["district"]))
	return maxi(0, _districts.size() - 1)


func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _state(m: Dictionary) -> String:
	## "won" / "open" / "locked"; IN DEVELOPMENT is shown on top (playable()).
	var key := str(m["key"])
	if Campaign.is_won(key):
		return "won"
	return "open" if Campaign.is_open(key) else "locked"


func _kind_name(m: Dictionary) -> String:
	match str(m.get("kind", "main")):
		"side":
			return "SIDE MISSION"
		"duel":
			return "RIVAL DUEL"
		"finale":
			return "FINALE"
	return "MISSION"


func _mat(key: String, c: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.roughness = 0.85
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


func _tint(node: Node, light: Material, ooze: Material) -> void:
	## Ownership = material (MapBuilder.apply_owner's rule), in a faction colour instead of a seat's.
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if nm.begins_with("OS_Light") or nm.begins_with("OS_State"):
				mi.set_surface_override_material(s, light)
			elif nm.begins_with("OS_Ooze") and ooze != null:
				mi.set_surface_override_material(s, ooze)


func _grey(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _mat("locked", Color(0.13, 0.145, 0.165))


func _ring(parent: Node3D, radius: float, c: Color, alpha: float, emit: float, own := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.35
	t.outer_radius = radius + 0.35
	t.rings = 48
	t.ring_segments = 8
	mi.mesh = t
	mi.scale = Vector3(1.0, 0.35, 1.0)
	mi.position = Vector3(0, 0.25, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if own:                              # its own material: it pulses
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
		mi.material_override = m
	else:
		mi.material_override = Mats.glow(c, alpha)
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ the 3D diorama
func _build_view() -> void:
	_view = SubViewportContainer.new()
	_view.stretch = false
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var sun := Scenery.build_environment(_world, mobile)   # the match's light, glow and height fog
	sun.shadow_enabled = not mobile
	for c in _world.get_children():
		if c is WorldEnvironment:
			_env = (c as WorldEnvironment).environment
	var sky_layer := Scenery.make_backdrop(_world)          # the cloud-city sky, drawn as the 3D background
	if sky_layer.get_child_count() > 0:
		_sky = sky_layer.get_child(0) as CanvasItem
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_world.add_child(_cam)
	_cam.current = true


func _build_world() -> void:
	for d in _districts:
		(d["root"] as Node3D).queue_free()
	_districts = []
	var ds := Campaign.districts(faction)
	if ds.is_empty():
		return
	for v in _void:
		(v as Node).queue_free()
	_void = Scenery.make_void(_world, Vector3(DISTRICT_GAP * (ds.size() - 1) / 2.0, 0, 0),
			Vector2(DISTRICT_GAP * ds.size() + 60.0, 110.0), not mobile)
	for i in range(ds.size()):
		_districts.append(_build_district(i, ds[i]))


func _pos3(dd: Dictionary, p: Vector2, layer: int) -> Vector3:
	## Diorama metres (x right, y toward the camera) -> world, inside district dd; Descent layers go down.
	return Vector3(p.x, -DESCENT_STEP * layer if bool(dd.get("descent", false)) else 0.0, p.y)


func _build_district(i: int, d: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(DISTRICT_GAP * i, 0, 0)
	_world.add_child(root)
	var descent := bool(d.get("descent", false))
	var dd := {"d": d, "root": root, "groups": {}, "decor": [], "nodes": {}, "bridges": {}, "relays": {},
			"descent": descent, "done": Campaign.district_done(faction, str(d["id"])),
			"memorial": false}
	dd["memorial"] = bool(dd["done"]) and not (d.get("collapse", []) as Array).is_empty() \
			and Campaign.was_seen("collapse:" + str(d["id"]))
	# decor: city dressing, platforms without a mission (an empty socket, dim lights)
	var k := 0
	for p in d.get("decor", []):
		var g := Node3D.new()
		g.position = _pos3(dd, p, 1 + (k % 2)) if descent else _pos3(dd, p, 0)
		root.add_child(g)
		MapBuilder.put(g, "Platform_Standard", Vector3.ZERO)
		MapBuilder.put(g, "Socket_Attachment", Vector3.ZERO)
		_tint(g, _mat("decor_light", Color(0.35, 0.4, 0.46), 0.6), null)
		(dd["decor"] as Array).append(g)
		k += 1
	# mission nodes
	var ms := Campaign.missions(faction).filter(func(x): return str(x["district"]) == str(d["id"]))
	var layer := 0
	for m in ms:
		var g := Node3D.new()
		g.position = _pos3(dd, m["pos"], layer)
		if str(m["kind"]) != "side":
			layer += 1
		root.add_child(g)
		dd["groups"][str(m["key"])] = g
		dd["nodes"][str(m["key"])] = _build_node(g, m)
	# main bridges in order; each side mission behind its parent's relay
	var mains := ms.filter(func(x): return str(x["kind"]) != "side")
	for j in range(mains.size() - 1):
		var a: Dictionary = mains[j]
		var b: Dictionary = mains[j + 1]
		dd["bridges"][str(b["key"])] = _build_bridge(dd, a, b)
	for m in ms:
		if str(m["kind"]) == "side":
			dd["relays"][str(m["key"])] = _build_relay(dd, m)
	# decor stubs toward the nearest node: the city was joined up once
	for g in dd["decor"]:
		var best: Node3D = null
		for key in dd["groups"]:
			var og: Node3D = dd["groups"][key]
			if best == null or og.position.distance_to((g as Node3D).position) < best.position.distance_to((g as Node3D).position):
				best = og
		if best != null:
			var dir := best.position - (g as Node3D).position
			dir.y = 0.0
			dir = dir.normalized()
			MapBuilder.angled_pier(g, dir * Rules.R, dir, 0.0, false)
			MapBuilder.put(g, "Deck_S", dir * (Rules.R + Rules.PIER), Rules.heading(dir))
	if descent:
		_build_underside(dd)
	if bool(dd["memorial"]):
		_memorial_pose(dd)
	return dd


func _build_node(g: Node3D, m: Dictionary) -> Dictionary:
	var key := str(m["key"])
	var st := _state(m)
	var kind := str(m.get("kind", "main"))
	var special := kind == "duel" or kind == "finale"
	var plat := MapBuilder.put(g, "Platform_Pillar" if special else "Platform_Standard", Vector3.ZERO)
	var fc := _color()
	var rec := {"key": key, "m": m, "group": g, "ring": null, "state": st, "plate": null, "button": null,
			"playable": Campaign.playable(m)}
	match st:
		"won":
			var tier := clampi(Campaign.stars_of(key) + 1, 2, 4)      # the vat grows a tier per star
			var vat := MapBuilder.put(g, MapBuilder.VAT_MODEL[tier], Vector3.ZERO)
			_tint(vat, Mats.light_color(fc), _mat("ooze_" + faction, fc * 0.6, 1.2))
			_tint(plat, Mats.light_color(fc), null)
			_ring(g, Rules.R - 0.4, fc, 0.85, 1.4)                      # the faction's goo ring
		"open":
			var vat := MapBuilder.put(g, "Vat_T1", Vector3.ZERO)
			_tint(vat, Mats.light_color(Rules.NEUTRAL), null)
			rec["ring"] = _ring(g, Rules.R + 0.3, Color("dff6ff"), 0.6, 1.6, true)   # open: pulses
		_:
			MapBuilder.put(g, "Socket_Attachment", Vector3.ZERO)
			_grey(g)
	if not bool(rec["playable"]):
		_ring(g, Rules.R + 1.0, Rules.state_color("build"), 0.75, 1.6)    # IN DEVELOPMENT: construction yellow
	return rec


func _build_bridge(dd: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	## A retract bridge from a to b: the gate on a's rim, decks sliding out of it (Deck_Retract), piers at both rims.
	## Extended when b is open; retracted into its gate otherwise.
	var ga: Node3D = dd["groups"][str(a["key"])]
	var gb: Node3D = dd["groups"][str(b["key"])]
	var v := gb.position - ga.position
	var dy := v.y
	v.y = 0.0
	var d := v.normalized()
	var L := v.length()
	var gap := L - 2.0 * (Rules.R + Rules.PIER)
	var nmod := maxi(1, roundi(gap / Rules.S))
	var f := gap / (nmod * Rules.S)
	var won := Campaign.is_won(str(a["key"]))
	var light := Mats.light_color(_color()) if won else _mat("bridge_idle", Color(0.55, 0.62, 0.7), 1.2)
	var holder := Node3D.new()                        # everything of this bridge rides with a's group
	ga.add_child(holder)
	var gate := MapBuilder.put(holder, "Relay_Retract", Vector3.ZERO, Rules.heading(d))
	_tint(gate, Mats.light_color(Rules.state_color("retract")) if not won else light, null)
	MapBuilder.angled_pier(holder, d * Rules.R, d, 0.0, false)
	var far := MapBuilder.angled_pier(holder, v + Vector3(0, dy, 0) - d * Rules.R, -d, 0.0, false)
	if not Campaign.is_open(str(b["key"])):
		_grey(far)
	var decks := []
	for k in range(nmod):
		var dk := MapBuilder.put(holder, "Deck_Retract", d * (Rules.R + Rules.PIER), Rules.heading(d), f)
		MapBuilder.set_lights(dk, light)
		decks.append(dk)
	# a Descent bridge slopes down to the next layer
	var slope := atan2(dy, gap) if absf(dy) > 0.01 else 0.0
	var rec := {"holder": holder, "decks": decks, "d": d, "gap": gap, "f": f, "slope": slope, "dy": dy, "L": L, "p": 0.0}
	_bridge_set(rec, 1.0 if Campaign.is_open(str(b["key"])) else 0.0)
	return rec


func _bridge_set(rec: Dictionary, p: float) -> void:
	## p 0 = retracted into its gate, 1 = extended to the next rim. Each deck module slides out in turn, the one
	## leaving the gate growing out of it.
	rec["p"] = p
	var d: Vector3 = rec["d"]
	var f: float = rec["f"]
	var gap: float = rec["gap"]
	var mod := Rules.S * f
	var s0 := Rules.R + Rules.PIER
	var out := p * gap                                 # how much deck is out of the gate
	var decks: Array = rec["decks"]
	var n := decks.size()
	for k in range(n):
		var dk: Node3D = decks[k]
		# module k (0 = nearest the far end) is the first out; it sits `out` - its length from the gate
		var lead := out - float(n - 1 - k) * mod           # length of this module outside the gate
		if lead <= 0.01:
			dk.visible = false
			continue
		dk.visible = true
		var along := s0 + float(k) * mod - (gap - out)     # extended: s0 + k*mod
		var len := mod
		if along < s0:
			len = maxf(0.05, mod - (s0 - along))
			along = s0
		var slope: float = rec["slope"]
		var y := float(rec["dy"]) * clampf((along - s0) / maxf(gap, 0.1), 0.0, 1.0)
		dk.position = d * along + Vector3(0, y, 0)
		dk.scale = Vector3(len / Rules.S / cos(slope), 1.0, 1.0)
		dk.rotation = Vector3(0, Rules.heading(d), 0)
		if absf(slope) > 0.001:
			dk.rotate_object_local(Vector3(0, 0, 1), slope)


func _build_relay(dd: Dictionary, m: Dictionary) -> Dictionary:
	## §3: a side node hangs off its parent behind a relay - a switch hub on the parent's ledge, a deck on a pivot
	## at the parent's rim that swings over to the side node (parked off the line until then).
	var parent_key := Campaign.key_of(faction, str(m.get("parent", "")))
	var gp: Node3D = dd["groups"].get(parent_key)
	var gs: Node3D = dd["groups"][str(m["key"])]
	if gp == null:
		return {}
	var v := gs.position - gp.position
	v.y = 0.0
	var d := v.normalized()
	var gap := v.length() - 2.0 * (Rules.R + Rules.PIER)
	var nmod := maxi(1, roundi(gap / Rules.S))
	var f := gap / (nmod * Rules.S)
	var others := []                                   # the parent's other connections (the ledge avoids them)
	for key in dd["groups"]:
		if key != parent_key:
			var og: Node3D = dd["groups"][key]
			if og.position.distance_to(gp.position) < 34.0:
				others.append(Vector3(og.position.x, 0, og.position.z) - Vector3(gp.position.x, 0, gp.position.z))
	var md := MapBuilder.widest_gap_dir(Vector3.ZERO, others)
	# park the deck on the side away from the ledge
	var park := SWING_PARK if d.rotated(Vector3.UP, SWING_PARK).dot(md) < d.rotated(Vector3.UP, -SWING_PARK).dot(md) else -SWING_PARK
	var holder := Node3D.new()
	gp.add_child(holder)
	var open := Campaign.is_open(str(m["key"]))
	var won := Campaign.is_won(str(m["key"]))
	MapBuilder.put(holder, "Relay_Mount", Vector3.ZERO, Rules.heading(md))
	var tower := MapBuilder.put(holder, "Relay_Switch_Hub", md * MapBuilder.MOUNT_DIST, Rules.heading(-md))
	var light := Mats.light_color(_color()) if won else (Mats.light_color(Rules.state_color("s2")) if open else null)
	if light != null:
		_tint(tower, light, null)
	else:
		_grey(tower)
	var pivot := Node3D.new()
	pivot.position = d * Rules.R
	holder.add_child(pivot)
	MapBuilder.put(pivot, "Pier_Angled_00_Switch", Vector3.ZERO)
	for k in range(nmod):
		var dk := MapBuilder.put(pivot, "Deck_S", Vector3(Rules.PIER + k * Rules.S * f, 0, 0), 0.0, f)
		if light != null:
			MapBuilder.set_lights(dk, light)
	if light == null:
		_grey(pivot)
	var far := MapBuilder.angled_pier(gs, -d * Rules.R, -d, 0.0, false)
	if not open:
		_grey(far)
	var rec := {"pivot": pivot, "d": d, "park": park, "tower_local": md * MapBuilder.MOUNT_DIST, "group": gp,
			"parent": parent_key, "open": open, "button": null}
	var swung := won or bool(_swung.get(str(m["key"]), false))
	_swing_set(rec, 1.0 if swung else 0.0)
	return rec


func _swing_set(rec: Dictionary, p: float) -> void:
	(rec["pivot"] as Node3D).rotation.y = Rules.heading(rec["d"]) + float(rec["park"]) * (1.0 - p)


func _build_underside(dd: Dictionary) -> void:
	## THE DESCENT: the city hangs above and behind (the districts already played, dark), cables run down from its
	## rims to each mission's platform, and the void is closer.
	var root: Node3D = dd["root"]
	var above := [Vector3(-58, 9, -26), Vector3(-26, 11, -30), Vector3(8, 9, -27), Vector3(40, 12, -31),
			Vector3(70, 10, -26)]
	for p in above:
		var up := MapBuilder.put(root, "Platform_Standard", p)
		up.scale = Vector3(1.3, 1.3, 1.3)
		_grey(up)
	var steel := _mat("cable", Color(0.2, 0.21, 0.25))
	for key in dd["groups"]:
		var g: Node3D = dd["groups"][key]
		var best: Vector3 = above[0]
		for p in above:
			if absf((p as Vector3).x - g.position.x) < absf(best.x - g.position.x):
				best = p
		for side in [-1.0, 1.0]:
			var a := g.position + Vector3(side * (Rules.R - 1.0), 0.3, -Rules.R + 1.0)
			var b := best + Vector3(side * 5.0, -1.0, 4.0)
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, a.distance_to(b), 0.22)
			mi.mesh = box
			mi.material_override = steel
			root.add_child(mi)
			mi.transform = Transform3D(Basis.looking_at(b - a, Vector3.RIGHT), (a + b) / 2.0)
			mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	Scenery.make_void(root, Vector3(0, -2.0 - DESCENT_STEP, 0), Vector2(110, 60), false)   # the void, closer


func _memorial_pose(dd: Dictionary) -> void:
	## A done district after its collapse: floating remains, sunk and tilted (the look desaturates too, _look()).
	var i := 0
	for g in _all_groups(dd):
		(g as Node3D).position.y = -2.2 - 0.9 * float(i % 3)
		(g as Node3D).rotation = Vector3(0.05 * float((i % 3) - 1), 0.0, 0.06 * float(((i + 1) % 3) - 1))
		(g as Node3D).visible = true
		i += 1


func _all_groups(dd: Dictionary) -> Array:
	var out: Array = (dd["decor"] as Array).duplicate()
	for key in dd["groups"]:
		out.append(dd["groups"][key])
	return out


# ------------------------------------------------------------------ camera
func _fit_rect() -> Rect2:
	## The canvas area the district must fit: under the top bar, over the bottom bar (and the node plates), left of
	## the mission card when one is open.
	var top := 12.0 + rh(56.0) + 12.0
	var bottom := CANVAS.y - 12.0 - _bar_h() - 10.0 - rh(46.0)
	var right := (CANVAS.x - 30.0) if _card_key == "" else (_card_x() - 20.0)
	return Rect2(Vector2(30.0, top), Vector2(right - 30.0, bottom - top))


func _bar_h() -> float:
	return maxf(rh(64.0) + 20.0, 88.0)


func _card_x() -> float:
	return CANVAS.x - 16.0 - 460.0


func _district_points(dd: Dictionary) -> Array:
	var pts := []
	var off: Vector3 = (dd["root"] as Node3D).position
	for g in _all_groups(dd):
		var c: Vector3 = off + (g as Node3D).position
		for v in [Vector3(Rules.R, 0, 0), Vector3(-Rules.R, 0, 0), Vector3(0, 0, Rules.R), Vector3(0, 0, -Rules.R), Vector3(0, 3.5, 0)]:
			pts.append(c + v)
	return pts


func _place(target: Vector3, dist: float, pitch: float) -> void:
	var p := deg_to_rad(pitch)
	_cam.position = target + Vector3(0, sin(p), cos(p)) * dist
	_cam.look_at(target, Vector3.UP)


func _ground(screen: Vector2, y: float) -> Vector3:
	var o := _cam.project_ray_origin(screen)
	var n := _cam.project_ray_normal(screen)
	if absf(n.y) < 0.0001:
		return o
	return o + n * ((y - o.y) / n.y)


func _fit_camera(i: int) -> Array:
	## Distance and aim that fit district i's platforms inside _fit_rect() on the real screen (the canvas is
	## letterboxed inside the 3D view), by projecting and correcting - main.gd's _fit_camera idea.
	var dd: Dictionary = _districts[i]
	var pitch := DESCENT_PITCH if bool(dd["descent"]) else PITCH
	var pts := _district_points(dd)
	var target := Vector3.ZERO
	for p in pts:
		target += p
	target /= float(maxi(1, pts.size()))
	var r := _fit_rect()
	var s := content.scale.x
	var rv := Rect2(content.position + r.position * s, r.size * s)
	var dist := 110.0
	for it in range(10):
		_place(target, dist, pitch)
		var bb := _bbox(pts)
		var k := maxf(bb.size.x / maxf(rv.size.x, 1.0), bb.size.y / maxf(rv.size.y, 1.0))
		dist = clampf(dist * k, 20.0, 800.0)
		_place(target, dist, pitch)
		bb = _bbox(pts)
		target += _ground(bb.get_center(), target.y) - _ground(rv.get_center(), target.y)
	return [target, dist, pitch]


func _bbox(pts: Array) -> Rect2:
	var bb := Rect2(_cam.unproject_position(pts[0]), Vector2.ZERO)
	for p in pts:
		bb = bb.expand(_cam.unproject_position(p))
	return bb


func _snap_camera() -> void:
	if _districts.is_empty():
		return
	_cam_now = _fit_camera(_cur)
	_place(_cam_now[0], _cam_now[1], _cam_now[2])
	_look(_cur, 1.0, _cur)


func _cam_lerp(t: float, a: Array, b: Array) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	_cam_now = [(a[0] as Vector3).lerp(b[0], e), lerpf(a[1], b[1], e), lerpf(a[2], b[2], e)]
	_place(_cam_now[0], _cam_now[1], _cam_now[2])


func _tween_camera(dur: float) -> void:
	var a := _cam_now.duplicate()
	var b := _fit_camera(_cur)
	_place(a[0], a[1], a[2])
	var tw := create_tween()
	tw.tween_method(func(t): _cam_lerp(t, a, b), 0.0, 1.0, dur)


func _pan_to(i: int, dur: float) -> void:
	var from := _look_from
	var a := _cam_now.duplicate()
	var b := _fit_camera(i)
	_place(a[0], a[1], a[2])
	var tw := create_tween()
	tw.tween_method(func(t):
		_cam_lerp(t, a, b)
		_look(from, t, i), 0.0, 1.0, dur)
	_tweens.append(tw)
	_look_from = from
	await tw.finished
	_look_from = i


func _look_of(i: int) -> Array:
	## [saturation, brightness, ambient, sky modulate] - a normal district, a memorial (desaturated, dim) or
	## THE DESCENT (dark, the sky nearly gone).
	var dd: Dictionary = _districts[i]
	if bool(dd["descent"]):
		return [0.95, 0.72, 0.16, Color(0.32, 0.28, 0.42)]
	if bool(dd["memorial"]):
		return [0.22, 0.8, 0.26, Color(0.62, 0.62, 0.66)]
	return [1.08, 1.0, 0.3, Color(1, 1, 1)]


func _look(a: int, t: float, b: int) -> void:
	if _env == null or _districts.is_empty():
		return
	var la := _look_of(a)
	var lb := _look_of(b)
	_env.adjustment_saturation = lerpf(la[0], lb[0], t)
	_env.adjustment_brightness = lerpf(la[1], lb[1], t)
	_env.ambient_light_energy = lerpf(la[2], lb[2], t)
	if _sky != null:
		_sky.modulate = (la[3] as Color).lerp(lb[3], t)
	_look_from = b if t >= 1.0 else _look_from


# ------------------------------------------------------------------ per frame: tap targets, plates, pulses
func _process(dt: float) -> void:
	_pulse_t += dt
	if _districts.is_empty() or not is_instance_valid(content):
		return
	var s := content.scale.x
	var moving := _busy
	var fac_ok := _faction_ok()                        # (once per frame: audit-tutorial-campaign B5)
	for i in range(_districts.size()):
		var dd: Dictionary = _districts[i]
		for key in dd["nodes"]:
			var rec: Dictionary = dd["nodes"][key]
			if rec["ring"] != null:
				var ring: MeshInstance3D = rec["ring"]
				var w := 0.5 + 0.5 * sin(_pulse_t * 3.2)
				ring.scale = Vector3(1.0 + 0.06 * w, 0.35, 1.0 + 0.06 * w)
				(ring.material_override as StandardMaterial3D).albedo_color.a = 0.3 + 0.5 * w
			var btn: Button = rec["button"]
			var plate: Control = rec["plate"]
			var here := i == _cur and not moving and fac_ok
			if is_instance_valid(btn):
				btn.visible = here
			if is_instance_valid(plate):
				plate.visible = here
			if not here:
				continue
			var g: Node3D = rec["group"]
			var c := (_cam.unproject_position(g.global_position + Vector3(0, 1.0, 0)) - content.position) / s
			var front := (_cam.unproject_position(g.global_position + Vector3(0, 0, Rules.R + 0.5)) - content.position) / s
			if is_instance_valid(btn):
				btn.position = c - btn.size / 2.0
			if is_instance_valid(plate):
				plate.position = Vector2(front.x - plate.size.x / 2.0, maxf(front.y, c.y + btn.size.y * 0.5 if is_instance_valid(btn) else front.y) - 4.0)
				plate.position = plate.position.clamp(Vector2(4, 4), CANVAS - plate.size - Vector2(4, 4))
		for key in dd["relays"]:
			var rr: Dictionary = dd["relays"][key]
			if rr.is_empty():
				continue
			var rb: Button = rr["button"]
			if not is_instance_valid(rb):
				continue
			rb.visible = i == _cur and not moving and fac_ok
			if rb.visible:
				var gp: Node3D = rr["group"]
				var tp := gp.global_transform * (rr["tower_local"] as Vector3) + Vector3(0, 2.0, 0)
				rb.position = (_cam.unproject_position(tp) - content.position) / s - rb.size / 2.0


func _faction_ok() -> bool:
	return Campaign.has_content(faction) and Campaign.owned(faction)


# ------------------------------------------------------------------ input: swipe between districts, tap to close
func _input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		released = not pressed
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = (event as InputEventMouseButton).pressed
		released = not pressed
		pos = (event as InputEventMouseButton).position
	else:
		return
	if pressed:
		_press_at = pos
	elif released and _press_at != Vector2.INF:
		var dv := pos - _press_at
		_press_at = Vector2.INF
		var s := maxf(content.scale.x, 0.01)
		if absf(dv.x) / s > 110.0 and absf(dv.x) > absf(dv.y) * 1.6 and not _busy and _card_key == "":
			_swiped_ms = Time.get_ticks_msec()
			show_district(_cur + (1 if dv.x < 0.0 else -1))


func _swiped() -> bool:
	return Time.get_ticks_msec() - _swiped_ms < 300


func _on_catcher_input(event: InputEvent) -> void:
	var up := (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed)
	if up and not _swiped() and _card_key != "" and not _busy:
		close_card()


# ------------------------------------------------------------------ building blocks (TutorialPage's shapes)
func _label(text: String, size_value: int, col: Color, head := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HEAD_FONT if head else UI_FONT)
	l.add_theme_font_size_override("font_size", fsz(size_value))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label_at(parent: Control, text: String, pos: Vector2, size_value: int, col: Color, head := false, width := 0.0) -> Label:
	var l := _label(text, size_value, col, head)
	l.position = pos
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
		l.size = Vector2(width, 0)
	parent.add_child(l)
	return l


func _frame(parent: Control, pos: Vector2, dims: Vector2, accent: Color, block := false) -> NeonPanel:
	if block:                                           # the panel eats taps (the diorama behind stays put)
		var b := Control.new()
		b.position = pos
		b.size = dims
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		parent.add_child(b)
	var p := NeonPanel.new()
	p.accent = accent
	p.position = pos
	p.custom_minimum_size = dims
	p.size = dims
	parent.add_child(p)
	return p


func _button(parent: Control, text: String, pos: Vector2, dims: Vector2, cb: Callable, primary := false,
		font_size := 20, skin := "") -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.add_theme_font_override("font", UI_FONT)
	b.custom_minimum_size = dims
	b.size = dims
	b.position = pos
	b.add_theme_stylebox_override("normal", Hud.panel_style())
	b.add_theme_stylebox_override("hover", Hud.panel_style(_color()))
	b.add_theme_font_size_override("font_size", fsz(font_size))
	b.pressed.connect(func(): cb.call_deferred())
	UiSkin.button(b, skin if skin != "" else faction, primary)
	parent.add_child(b)
	return b


func _hit(parent: Control, dims: Vector2, cb: Callable, always := false) -> Button:
	## A flat, invisible tap target (TutorialPage's row hit) over a projected 3D position.
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = dims
	b.custom_minimum_size = dims
	b.modulate = Color(1, 1, 1, 0)
	b.pressed.connect(func():
		if always or (not _swiped() and not _busy):
			cb.call_deferred())
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ the 2D page
func _rebuild_ui() -> void:
	if not is_instance_valid(content):
		return
	for c in content.get_children():
		if c != _card:
			c.queue_free()
			content.remove_child(c)
	var fc := _color()
	# the node plates and tap targets (positioned every frame in _process)
	for i in range(_districts.size()):
		var dd: Dictionary = _districts[i]
		for key in dd["nodes"]:
			var rec: Dictionary = dd["nodes"][key]
			rec["plate"] = null
			rec["button"] = null
			if i != _cur:
				continue
			rec["plate"] = _make_plate(rec)
			var sz := rh(84.0)
			rec["button"] = _hit(content, Vector2(sz, sz), func(): _node_tapped(str(key)))
		for key in dd["relays"]:
			var rr: Dictionary = dd["relays"][key]
			if rr.is_empty():
				continue
			rr["button"] = null
			if i == _cur:
				var sz := rh(60.0)
				rr["button"] = _hit(content, Vector2(sz, sz), func(): _relay_tapped(str(key)))
	# top bar: BACK, the campaign's name, the faction tabs, the star count
	var top_h := rh(56.0)
	_button(content, "BACK", Vector2(16, 12), tap(Vector2(150, 56)), func(): back_pressed.emit(), false, 20)
	if view_switch != "":                             # UI (Alpha 21, Daniele: "maybe we can have a switch for the 2 modes")
		_button(content, view_switch, Vector2(16, 12 + top_h + 10.0), tap(Vector2(150, 48)), func(): view_pressed.emit(), false, 18)
	var info: Dictionary = Campaign.CAMPAIGNS.get(faction, {})
	_label_at(content, "CAMPAIGN", Vector2(16 + rh(150.0) + 18.0, 12), 14, fc.lightened(0.3))
	_label_at(content, str(info.get("title", "")), Vector2(16 + rh(150.0) + 18.0, 12 + top_h * 0.34), 24, Color("edf7fa"), true)
	var tab_w := rh(100.0)
	var tab_x := 1264.0 - 206.0 - 5.0 * tab_w - 4.0 * 8.0
	for k in range(Campaign.FACTION_ORDER.size()):
		var f: String = Campaign.FACTION_ORDER[k]
		var state := "OPEN" if Campaign.has_content(f) and Campaign.owned(f) else ("LOCKED" if Campaign.has_content(f) else "LATER")
		var b := _button(content, "%s\n%s" % [f.to_upper(), state], Vector2(tab_x + k * (tab_w + 8.0), 12), Vector2(tab_w, top_h),
				func(): _pick_faction(f), f == faction, 14, f)
		if f != faction and state != "OPEN":
			b.modulate = Color(1, 1, 1, 0.6)
	var star := StarIcon.new()
	star.fill = SCRAP
	star.size = Vector2(30, 30) * (fsz(24) / 24.0)
	star.position = Vector2(1264.0 - 196.0, 12 + top_h / 2.0 - star.size.y / 2.0)
	content.add_child(star)
	_label_at(content, "%d / %d" % [Campaign.stars_total(faction), Campaign.stars_max(faction)],
			Vector2(star.position.x + star.size.x + 10.0, 12 + top_h / 2.0 - fsz(24) * 0.7), 24, Color("edf7fa"), true)
	if not _faction_ok():
		_coming_later()
		return
	# bottom bar: the district, its blurb and prev / next; CONTINUE
	var dd: Dictionary = _districts[_cur]
	var d: Dictionary = dd["d"]
	var bar_h := _bar_h()
	var by := CANVAS.y - 12.0 - bar_h
	var pw := 800.0 - 16.0
	_frame(content, Vector2(16, by), Vector2(pw, bar_h), fc, true)
	var nb := rh(64.0)
	var prev := _button(content, "‹", Vector2(26, by + (bar_h - nb) / 2.0), Vector2(nb, nb), func(): show_district(_cur - 1), false, 30)
	prev.disabled = _cur == 0
	var nxt := _button(content, "›", Vector2(16 + pw - 10.0 - nb, by + (bar_h - nb) / 2.0), Vector2(nb, nb), func(): show_district(_cur + 1), false, 30)
	nxt.disabled = _cur >= _districts.size() - 1
	var tx := 26.0 + nb + 16.0
	var tw := pw - 2.0 * (nb + 26.0)
	var tag := ""
	if bool(dd["memorial"]):
		tag = "   MEMORIAL - replay any mission"
	elif bool(dd["done"]):
		tag = "   DONE"
	var name_l := _label_at(content, str(d["name"]) + tag, Vector2(tx, by + 10.0), 22, Color("edf7fa"), true)
	name_l.size = Vector2(tw - 90.0, 0)
	name_l.clip_text = true
	_label_at(content, "%d / %d" % [_cur + 1, _districts.size()], Vector2(16 + pw - 26.0 - nb - 70.0, by + 12.0), 14, fc.lightened(0.2))
	var blurb := _label_at(content, str(d["blurb"]), Vector2(tx, by + 12.0 + fsz(22) * 1.3), 14, Color("9fb6c0"), false, tw)
	blurb.max_lines_visible = 2
	if _card_key == "":
		var nk := Campaign.next_open(faction)
		var text := "CONTINUE\n" + (("%s  %s" % [str(Campaign.mission(nk)["id"]).to_upper(), str(Campaign.mission(nk)["title"])]) if nk != "" else "EVERY MISSION WON")
		var cb := _button(content, text, Vector2(816, by), Vector2(1264.0 - 816.0, bar_h), func(): _continue(), true, 18)
		cb.disabled = nk == ""
	if not Campaign.saved:
		_label_at(content, "Progress isn't saved on this browser", Vector2(16, by - fsz(13) * 1.6), 13, Color("7795a4"))
	if is_instance_valid(_card):
		content.move_child(_card, -1)
	if _busy:
		_skip_btn = _hit(content, CANVAS, skip, true)      # TAP TO SKIP: the whole canvas
		_skip_btn.position = Vector2.ZERO
		_skip_label = _label_at(content, "TAP TO SKIP", Vector2(CANVAS.x / 2.0 - 70.0, by - fsz(16) * 2.0), 16, Color("edf7fa"))
		_skip_label.visible = false


func _coming_later() -> void:
	## A faction campaign with no content yet (or not owned): its name and "coming later" over the empty void.
	var info: Dictionary = Campaign.CAMPAIGNS.get(faction, {})
	var fc := _color()
	var w := 640.0
	var h := 250.0 + rh(56.0)
	var pos := Vector2((CANVAS.x - w) / 2.0, (CANVAS.y - h) / 2.0 + 30.0)
	_frame(content, pos, Vector2(w, h), fc, true)
	_label_at(content, str(info.get("title", faction.to_upper())), pos + Vector2(36, 28), 30, Color("edf7fa"), true)
	var owned := Campaign.owned(faction)
	var line := "COMING LATER" if not Campaign.has_content(faction) else ("LOCKED - a paid campaign" if not owned else "")
	_label_at(content, line, pos + Vector2(36, 28 + fsz(30) * 1.5), 20, fc)
	_label_at(content, "Every syndicate plays the same sinking city from its own side. VEX's campaign is free.",
			pos + Vector2(36, 28 + fsz(30) * 1.5 + fsz(20) * 1.6), 15, Color("9fb6c0"), false, w - 72.0)
	var free := _first_with_content()
	_button(content, "PLAY THE %s CAMPAIGN" % free.to_upper(), pos + Vector2(36, h - rh(56.0) - 24.0), Vector2(w - 72.0, rh(56.0)),
			func(): _pick_faction(free), true, 18, free)


func _make_plate(rec: Dictionary) -> Control:
	## A node's plate under its platform: number + title (the title hides while a card is open), star pips, the
	## SCRAP mark, and LOCKED / IN DEVELOPMENT.
	var m: Dictionary = rec["m"]
	var key := str(m["key"])
	var p := Plate.new()
	p.accent = _color() if rec["state"] == "won" else (Color("dff6ff") if rec["state"] == "open" else GREY)
	p.stars = Campaign.stars_of(key)
	p.reward = Campaign.reward_state(key)
	p.star_px = float(fsz(15))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compact := _card_key != "" and _card_key != key
	var title := str(m["id"]).to_upper() if compact else "%s  %s" % [str(m["id"]).to_upper(), str(m["title"])]
	var tl := _label(title, 15, Color("edf7fa") if rec["state"] != "locked" else Color("8d9aa3"))
	p.add_child(tl)
	var tag := ""
	if not bool(rec["playable"]):
		tag = "IN DEV" if compact else "IN DEVELOPMENT"
	elif rec["state"] == "locked":
		tag = "LOCKED"
	elif str(m["kind"]) == "side" and not compact:
		tag = "SIDE"
	var tagl: Label = null
	if tag != "":
		tagl = _label(tag, 12, Rules.state_color("build") if not bool(rec["playable"]) else Color("8d9aa3"))
		p.add_child(tagl)
	p.title = tl
	p.tag = tagl
	content.add_child(p)                               # measured in the page (Daniele's note: a plate sized off-tree ran
	p.fit()                                            # shorter than its title + LOCKED on phones), and again once shaped
	p.fit.call_deferred()
	return p


func _build_card(m: Dictionary) -> void:
	## The mission card (§3 HUD): what, who, how to win, what it pays, PLAY.
	if is_instance_valid(_card):
		_card.queue_free()
	var key := str(m["key"])
	var fc := _color()
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(card)
	_card = card
	var x := _card_x()
	var y := 12.0 + rh(56.0) + 12.0
	var w := 460.0
	var h := CANVAS.y - 12.0 - y
	_frame(card, Vector2(x, y), Vector2(w, h), fc, true).glowing = true
	var pad := 22.0
	var close := tap(Vector2(52, 52))
	_button(card, "X", Vector2(x + w - pad - close.x + 8.0, y + 12.0), close, func(): close_card(), false, 20)
	var d := Campaign.district_of(key)
	var kind := "%s  ·  %s %s" % [str(d.get("name", "")), _kind_name(m), str(m["id"]).to_upper()]
	_label_at(card, kind, Vector2(x + pad, y + 14.0), 13, fc.lightened(0.25))
	var title := _label_at(card, str(m["title"]), Vector2(x + pad, y + 14.0 + fsz(13) * 1.35), 26, Color("edf7fa"), true)
	title.size = Vector2(w - pad * 2.0 - close.x, 0)
	title.clip_text = true
	var head_h := maxf(close.y + 12.0, 14.0 + fsz(13) * 1.35 + fsz(26) * 1.3) + 8.0
	var play_h := rh(60.0)
	var body_y := y + head_h
	var body_h := h - head_h - play_h - 34.0
	var scroll := TouchScroll.new()
	scroll.position = Vector2(x + pad, body_y)
	scroll.size = Vector2(w - pad * 2.0, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var bw := w - pad * 2.0 - 14.0
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(bw, 0)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(box)
	var add := func(text: String, size_value: int, col: Color) -> Label:
		var l := _label(text, size_value, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(bw, 0)
		box.add_child(l)
		return l
	add.call(str(m.get("story", "")), 16, Color("c9dbe2"))
	var rv := Campaign.rival_of(m)
	var rc: Color = Rules.FACTIONS.get(str(rv.get("faction", "ember")), [0, Color.WHITE])[1]
	add.call("RIVAL  %s  -  %s" % [str(rv.get("name", "")), str(rv.get("title", ""))], 15, rc.lightened(0.15))
	add.call("OBJECTIVE", 13, fc.lightened(0.25))
	add.call(Campaign.objective_text(m), 18, Color("edf7fa"))
	var opt: Dictionary = m.get("optional", {})
	if not opt.is_empty():
		add.call("OPTIONAL", 13, fc.lightened(0.25))
		add.call(str(opt.get("text", "")), 16, Color("edf7fa"))
	var rec := Campaign.record_of(key)
	var par := "PAR %s" % _clock(float(m.get("par", 0.0)))
	if float(rec.get("best_time", 0.0)) > 0.0:
		par += "      BEST %s" % _clock(float(rec["best_time"]))
	add.call(par, 16, Color("edf7fa"))
	var srow := HBoxContainer.new()
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_theme_constant_override("separation", 10)
	var pips := Plate.new()
	pips.stars = Campaign.stars_of(key)
	pips.star_px = float(fsz(22))
	pips.stars_x = 0.0
	pips.stars_y = pips.star_px * 0.6
	pips.bare = true
	pips.custom_minimum_size = Vector2(pips.star_px * 3.4, pips.star_px * 1.2)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(pips)
	srow.add_child(_label("%d / 3 STARS" % Campaign.stars_of(key), 16, Color("edf7fa")))
	box.add_child(srow)
	add.call("1 star: win  ·  2: within par  ·  3: within par, no starting node lost", 13, Color("8fa6b0"))
	var amount := Campaign.reward_for(m)
	var reward := ""
	match Campaign.reward_state(key):
		"paid":
			reward = "REWARD TAKEN  (+%d SCRAP)" % amount
		"earned":
			reward = "EARNED +%d SCRAP - paid when your wallet arrives" % amount
		_:
			reward = "3 stars + the optional objective in one run: +%d SCRAP" % amount
	add.call(reward, 15, SCRAP)
	if bool(m.get("placeholder", false)):
		add.call("PLACEHOLDER MAP - the mission's own map comes later", 13, Color("7795a4"))
	if not Campaign.saved:
		add.call("Progress isn't saved on this browser", 13, Color("7795a4"))
	var foot := Vector2(x + pad, y + h - play_h - 18.0)
	var playable := Campaign.playable(m)
	var open := Campaign.is_open(key)
	var text := "PLAY"
	if not playable:
		var needs := str(m.get("needs", ""))
		text = "IN DEVELOPMENT\nneeds %s" % (needs if needs != "" else "its map")
	elif not open:
		text = "LOCKED\n%s" % ("win %s first" % str(Campaign.mission(Campaign.key_of(faction, str(m.get("parent", ""))))["title"]) \
				if str(m["kind"]) == "side" else "win the mission before it")
	var pb := _button(card, text, foot, Vector2(w - pad * 2.0, play_h), func(): _play(key), true, 22 if text == "PLAY" else 15)
	pb.disabled = not (playable and open)
	card.set_meta("play", pb)


# ------------------------------------------------------------------ actions
func _pick_faction(f: String) -> void:
	if f == faction:
		return
	close_card(false)
	faction = f
	if Campaign.has_content(f):
		_swung = {}
		_build_world()
		_cur = _start_district({})
		_snap_camera()
	(_world as Node3D).visible = true
	for dd in _districts:
		(dd["root"] as Node3D).visible = _faction_ok()
	_rebuild_ui()


func _continue() -> void:
	var nk := Campaign.next_open(faction)
	if nk == "":
		return
	var di := _district_index(str(Campaign.mission(nk)["district"]))
	if di != _cur:
		await show_district(di)
	if is_inside_tree():
		open_card(nk)


func _play(key: String) -> void:
	var m := Campaign.mission(key)
	if Campaign.playable(m) and Campaign.is_open(key):
		play_pressed.emit(key)


func _node_tapped(key: String) -> void:
	var m := Campaign.mission(key)
	if str(m.get("kind", "")) == "side":
		var dd: Dictionary = _districts[_cur]
		var rr: Dictionary = dd["relays"].get(key, {})
		if not rr.is_empty() and bool(rr["open"]) and not _swung.get(key, false) and not Campaign.is_won(key):
			await _swing(key)
	if is_inside_tree():
		open_card(key)


func _relay_tapped(key: String) -> void:
	## §3: tapping the relay swings its deck over to the side node (the relay animation, 1 s), then opens its card.
	var rr: Dictionary = _districts[_cur]["relays"].get(key, {})
	if not rr.is_empty() and bool(rr["open"]) and not _swung.get(key, false) and not Campaign.is_won(key):
		await _swing(key)
	if is_inside_tree():
		open_card(key)


func _swing(key: String) -> void:
	var rr: Dictionary = _districts[_cur]["relays"][key]
	_swung[key] = true
	_busy = true
	var tw := create_tween()
	tw.tween_method(func(t): _swing_set(rr, t), 0.0, 1.0, SWING_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_busy = false


# ------------------------------------------------------------------ after a mission / arriving at a district
func _intro(lr: Dictionary) -> void:
	## Campaign.last_run played once: the new stars pop, a first win extends the bridge it opened; then (for any
	## district arrived at) the collapse of a done district not yet seen.
	if lr.is_empty():
		_arrive()
		return
	var key := str(lr["key"])
	var sm: Dictionary = lr.get("summary", {})
	var dd: Dictionary = _districts[_cur]
	var bridge_to := ""
	if bool(sm.get("first_win", false)):
		var ms := Campaign.missions(faction).filter(func(x): return str(x["district"]) == str(dd["d"]["id"]) and str(x["kind"]) != "side")
		for j in range(ms.size() - 1):
			if str(ms[j]["key"]) == key:
				bridge_to = str(ms[j + 1]["key"])
	_busy = true
	_skip = false
	if bridge_to != "" and dd["bridges"].has(bridge_to):
		_bridge_set(dd["bridges"][bridge_to], 0.0)
	_rebuild_ui()
	await get_tree().process_frame
	# the stars pop in one by one on the mission's plate
	var rec: Dictionary = dd["nodes"].get(key, {})
	if bool(sm.get("new_best", false)) and not rec.is_empty():
		_busy = false                                   # plates show while the stars pop
		var plate: Plate = rec["plate"]
		var n := int(sm.get("best_stars", Campaign.stars_of(key)))
		if is_instance_valid(plate):
			plate.stars = 0
			plate.queue_redraw()
			for k in range(n):
				var tw := create_tween()
				_tweens.append(tw)
				plate.stars = k + 1
				tw.tween_method(func(t):
					if is_instance_valid(plate):
						plate.pop = [1.0, 1.0, 1.0]
						plate.pop[k] = 1.0 + 0.8 * sin(t * PI)
						plate.queue_redraw(), 0.0, 1.0, 0.32)
				await tw.finished
				if not is_inside_tree():
					return
		_busy = true
	if bridge_to != "" and dd["bridges"].has(bridge_to) and is_inside_tree():
		_busy = false
		var br: Dictionary = dd["bridges"][bridge_to]
		var tw := create_tween()
		_tweens.append(tw)
		tw.tween_method(func(t): _bridge_set(br, t), 0.0, 1.0, BRIDGE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw.finished
	_busy = false
	if is_inside_tree():
		_rebuild_ui()
		_arrive()


func _arrive() -> void:
	## Arriving at a district: if it is done and its collapse was never seen, it plays now.
	if _districts.is_empty() or not _faction_ok():
		return
	if _collapse_due(_cur):
		_collapse(_cur)


func _collapse_due(i: int) -> bool:
	var dd: Dictionary = _districts[i]
	var d: Dictionary = dd["d"]
	return bool(dd["done"]) and not bool(dd["memorial"]) and not (d.get("collapse", []) as Array).is_empty() \
			and not Campaign.was_seen("collapse:" + str(d["id"]))


func _collapse(i: int) -> void:
	## §3 district collapse: a small Last Stand - its platforms drop ring by ring into the void (decor, the outer
	## ring, first; then the missions in the district's `collapse` order), 3-4 s, tap to skip; then the camera pans
	## to the next district and the district stays as a memorial.
	var dd: Dictionary = _districts[i]
	var d: Dictionary = dd["d"]
	close_card(false)
	_busy = true
	_skip = false
	_rebuild_ui()
	if is_instance_valid(_skip_label):
		_skip_label.visible = true
	var order: Array = (dd["decor"] as Array).duplicate()
	for id in d.get("collapse", []):
		var g = dd["groups"].get(Campaign.key_of(faction, str(id)))
		if g != null:
			order.append(g)
	for key in dd["groups"]:
		if not (dd["groups"][key] in order):
			order.append(dd["groups"][key])
	var tw := create_tween().set_parallel(true)
	_tweens.append(tw)
	for j in range(order.size()):
		var g: Node3D = order[j]
		var y0 := g.position.y
		var x0 := g.position.x
		var delay := j * DROP_STAGGER
		tw.tween_method(func(t):
			if is_instance_valid(g):
				g.position.x = x0 + sin(t * 70.0) * 0.35 * (1.0 - t), 0.0, 1.0, 0.3).set_delay(delay)
		tw.tween_property(g, "position:y", y0 - 70.0, DROP_TIME).set_delay(delay + 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var spin := Vector3(0.5 * (1.0 if j % 2 == 0 else -1.0), 0.0, 0.35 * (1.0 if j % 3 == 0 else -1.0))
		tw.tween_property(g, "rotation", spin, DROP_TIME).set_delay(delay + 0.3)
	await tw.finished
	Campaign.mark_seen("collapse:" + str(d["id"]))
	dd["memorial"] = true
	if not is_inside_tree():
		return
	if i + 1 < _districts.size():
		_cur = i + 1
		var skipped := _skip
		_skip = false
		await _pan_to(i + 1, 0.05 if skipped else 1.2)
	_memorial_pose(dd)
	_busy = false
	_skip = false
	_tweens.clear()
	if is_inside_tree():
		_rebuild_ui()


# ------------------------------------------------------------------ drawn bits: star pips, the SCRAP mark
static func star_points(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(10):
		var a := -PI / 2.0 + k * PI / 5.0
		var r := r_out if k % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


class StarIcon extends Control:
	## The header's star (Rajdhani has no ★ glyph; drawn, like the plates' pips).
	var fill := Color("ffc94a")

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		draw_colored_polygon(CampaignPage.star_points(size / 2.0, r, r * 0.45), fill)


class Plate extends Control:
	## A mission node's plate (labels are children; this draws the panel, three star pips and the SCRAP mark).
	var accent := Color("dff6ff")
	var stars := 0
	var reward := ""                   # "" / "earned" / "paid" (Campaign.reward_state)
	var star_px := 15.0
	var stars_x := 8.0
	var stars_y := 20.0
	var pop := [1.0, 1.0, 1.0]         # per pip scale (the pop after a mission)
	var bare := false                  # pips only (the mission card)
	var title: Label                   # the number + title line (a child)
	var tag: Label                     # LOCKED / IN DEVELOPMENT / SIDE beside the pips (a child), or null

	func fit() -> void:
		## The plate around its labels: the title on top, the pips + tag under it, sized from the labels' own fonts.
		if not is_instance_valid(title):
			return
		var pad := 8.0
		var tsz := _text_size(title)
		var row_h := star_px * 1.2
		var stars_w := star_px * 3.4 + (star_px * 1.3 if reward != "" else 0.0)
		var gsz := _text_size(tag) if is_instance_valid(tag) else Vector2.ZERO
		var tag_w := gsz.x + 8.0 if is_instance_valid(tag) else 0.0
		title.position = Vector2(pad, 2.0)
		stars_y = 2.0 + tsz.y + row_h * 0.5
		stars_x = pad
		if is_instance_valid(tag):
			tag.position = Vector2(pad + stars_w + 8.0, 2.0 + tsz.y + (row_h - gsz.y) / 2.0)
		size = Vector2(ceilf(maxf(tsz.x, stars_w + tag_w) + pad * 2.0 + 2.0), 2.0 + tsz.y + row_h + 6.0)
		queue_redraw()

	static func _text_size(l: Label) -> Vector2:
		## The line's real extent: the label's min size, or its font's measure if that is wider (off-tree shaping).
		var m := l.get_combined_minimum_size()
		var f := l.get_theme_font("font")
		if f != null:
			var fs := l.get_theme_font_size("font_size")
			m.x = maxf(m.x, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		return m

	func _draw() -> void:
		if not bare:
			var w := size.x
			var h := size.y
			var c := 6.0
			var pts := PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c), Vector2(w - c, h),
					Vector2(0, h), Vector2(0, c)])
			draw_colored_polygon(pts, Color(0.02, 0.06, 0.08, 0.82))
			pts.append(pts[0])
			draw_polyline(pts, Color(accent, 0.8), 1.2, true)
		var r := star_px * 0.55
		for k in range(3):
			var cx := stars_x + r + k * star_px * 1.12
			var s: float = pop[k]
			var p := CampaignPage.star_points(Vector2(cx, stars_y), r * s, r * 0.45 * s)
			if k < stars:
				draw_colored_polygon(p, Color("ffc94a"))
			else:
				var q := p.duplicate()
				q.append(p[0])
				draw_polyline(q, Color(0.6, 0.66, 0.7, 0.7), 1.2, true)
		if reward != "":
			var cx := stars_x + 3.0 * star_px * 1.12 + r + 2.0
			var col := Color("ffc94a")
			if reward == "paid":
				draw_circle(Vector2(cx, stars_y), r * 0.85, col)
				draw_circle(Vector2(cx, stars_y), r * 0.4, Color(0.02, 0.06, 0.08))
			else:                      # earned, waiting for the wallet: the mark hollow
				draw_arc(Vector2(cx, stars_y), r * 0.8, 0.0, TAU, 24, col, 1.6, true)
