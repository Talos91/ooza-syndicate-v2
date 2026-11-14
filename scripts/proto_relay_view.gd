class_name ProtoRelayView
extends Node3D
## RELAYS 3.0 PROTOTYPES - the look of the five test kinds (01 Rules/RELAYS-3.0-PROTOTYPES.md; Sim's RELAYS 3.0 section).
## PLACEHOLDER GEOMETRY until 🎨's models: every moving piece is a plain coloured mesh named after the GLB node it stands in
## for (Proto_Ferry_Rail, Proto_Conveyor_Chevron, Proto_Launcher_Pad, Proto_Launcher_Arc, Proto_Lift_Platform,
## Proto_Tilt_ExitStrip, Proto_Relay_Pointer) - swap the mesh, keep the node and its transform logic. Fx keeps the common
## relay readouts (the glyph beacon, its state colour, the warning blink, the ready / cooldown arc); this adds per kind:
##   ferry     (round 2) the gap's own deck sliding sideways out of line and back on its clock, two rails across both
##             piers (its fixed path), a lamp at each lip (green in line, blinking red its last second, red out), a red
##             hole where the bridge belongs while it is out
##   conveyor  chevrons running along the deck in the flow's colour (at the push's speed), reversing through the flip;
##             the line speed tags (x2.25 with the flow, x0.3 against since round 3) over every line on a belt
##   launcher  the pad, the dotted arc to the node it aims at (round 2: always shown, marching, it swings to the next target
##             every cycle), a ring on that target (small dim rings on the others; solid + LOCKED once fired), the throws
##             in flight as a stream of blobs in the seat's colour
##   lift      (round 2) the platform rides up / down (RELAYS_PROTO.lift.rise view metres) on a piston; the closed level's
##             decks sunk, standing back and dimmed, the open ones with a lit strip; an UP / DOWN badge over the node
##   tilt      the platform tips toward the exit and stays tipped for the hold (round 2), chevrons running down that exit;
##             the next exit's deck lit (bright in the warning); round 3 (redirect): +10 % / -10 % over each redirected line
##   all       a pointer over the node: the slide, the flow, the target, up / down, the next exit (ghosted toward the
##             next state during the warning)
## Round 3 (Daniele's proto4 verdict, 2026-11-02): the ferry's HOLD (steady green lamps, glowing rails, HELD n over the deck),
## the plain pieces with no relay (a moving bridge on its own clock, a belt always running), the launcher's throw (quicker,
## the pad kicks, blobs stretch along the arc and splash at the target; a MISFIRE wobbles the pad red and flings the throws
## off the map), the lift's decks read by level (a flat UP / DOWN on every lift deck, a ghost where a closed deck docks, a
## glowing edge riding the deck that moves), and the lift / tilt platforms drawn by themselves (_unbatch: the tilt lag).
## Created by main.gd only when the map has a prototype relay; synced after Fx (Fx shows / hides decks first).

const POINTER_UP := 6.2              # m over the node centre
const CHEVRON_GAP := 2.6             # m between two chevrons
const CHEVRON_SPEED := 2.4           # m/s the chevrons run at (x the conveyor's push)
const ARC_DOTS := 26
const FLIGHT_BLOBS := 96
const LIFT_GAP := 1.3                # m a closed lift deck stands back from the platform ...
const LIFT_SINK := 1.6               # ... sunk this far ...
const LIFT_DIM := 0.6                # ... and this see-through
const FERRY_LAMP := 0.6              # m: the lamp at each lip of the moving bridge
const TILT_TIP := 0.36               # rad the tilt tips by (round 2: 0.22 read as flat from the default camera)
const TILT_EASE := 0.4               # s it takes to tip / come back
const SPLASH := 0.45                 # s a launcher landing's ring spreads
const SPLASHES := 16
const MISFIRE_FLING := 30.0          # m a misfired throw travels out before it drops away
# Round 3: the relays-4.0 models Daniele ticked on the Hub (review-relay-looks: node, ferry, conveyor) replace the stand-ins
# here, when the kit has them: Platform_Relay_v3 under the ferry / conveyor / launcher nodes, Deck_Ferry_v3_<L> sliding
# instead of the ferry edge's module decks with Relay_Ferry_Rail_v3 at both lips (their Light = the lamp), and
# Deck_Conveyor_Relay_v3_<L> / Deck_Conveyor_v3_<L> (plain belt) with their own scrolling Treads instead of the chevrons.
# Not ticked (stand-ins kept): the launcher, lift and tilt pieces.
const LAUNCHER_SCALE := 1.3          # 2026-11-06 (Daniele: "scale it up"): the launcher stands off-centre, behind the
const LAUNCHER_OFF := 3.9            # node's vat from its target, and lobs over it (it used to sit hidden inside the vat)
const V3_NODE_KINDS := ["ferry", "conveyor", "launcher"]   # (2026-11-05: _v3_platforms now dresses every relay node)
const TREAD_PERIOD := {4: 0.9850, 8: 0.9943, 12: 0.9964}   # relays_4_0.json: the Treads' scroll period per deck length
# Conveyors 4.1 (🎨 2026-11-05, Daniele: "conveyor for all type of bridge" + "a visually different conveyor" for the plain
# belts): native deck lengths 2..20 m (Deck_Conveyor_Relay_v3_<L> treads / Deck_Conveyor_Belt_v4_<L> slats) and conveyor
# versions of the curves (<Curve>_Conveyor_Relay_v4 / _Belt_v4) whose Treads turn round the curve centre.
# Models/2.0/conveyors-4.1/conveyors_4_1.json: the scroll period of every piece (m; curves: radians).
const CONV_LENGTHS := [2, 4, 6, 8, 10, 12, 14, 16, 20]
const CONV_PERIOD := {
		"Deck_Conveyor_Relay_v3_4": 0.985,
		"Deck_Conveyor_Relay_v3_8": 0.9943,
		"Deck_Conveyor_Relay_v3_12": 0.9964,
		"Deck_Conveyor_v3_4": 0.985,
		"Deck_Conveyor_v3_8": 0.9943,
		"Deck_Conveyor_v3_12": 0.9964,
		"Deck_Conveyor_Relay_v3_2": 0.4774,
		"Deck_Conveyor_Relay_v3_6": 0.992,
		"Deck_Conveyor_Relay_v3_10": 0.9956,
		"Deck_Conveyor_Relay_v3_14": 0.9969,
		"Deck_Conveyor_Relay_v3_16": 0.9973,
		"Deck_Conveyor_Relay_v3_20": 0.9979,
		"Curve_30_Conveyor_Relay_v4": 0.129293,
		"Curve_60_Conveyor_Relay_v4": 0.130157,
		"Curve_45_Conveyor_Relay_v4": 0.193929,
		"Curve_90_Conveyor_Relay_v4": 0.195206,
		"Curve_W45_Conveyor_Relay_v4": 0.097615,
		"Curve_W90_Conveyor_Relay_v4": 0.09792,
		"Deck_Conveyor_Belt_v4_2": 0.5041,
		"Deck_Conveyor_Belt_v4_4": 1.0409,
		"Deck_Conveyor_Belt_v4_6": 1.024,
		"Deck_Conveyor_Belt_v4_8": 1.0171,
		"Deck_Conveyor_Belt_v4_10": 1.0133,
		"Deck_Conveyor_Belt_v4_12": 1.0109,
		"Deck_Conveyor_Belt_v4_14": 1.0092,
		"Deck_Conveyor_Belt_v4_16": 1.008,
		"Deck_Conveyor_Belt_v4_20": 1.0063,
		"Curve_30_Conveyor_Belt_v4": 0.136257,
		"Curve_60_Conveyor_Belt_v4": 0.133141,
		"Curve_45_Conveyor_Belt_v4": 0.204381,
		"Curve_90_Conveyor_Belt_v4": 0.199705,
		"Curve_W45_Conveyor_Belt_v4": 0.099863,
		"Curve_W90_Conveyor_Belt_v4": 0.09896}

var sim: Sim
var vis: Dictionary
var _r := {}                         # relay node id -> its pieces
var _tags := {}                      # horde id -> Label3D (conveyor speed tag)
var _flights: MultiMeshInstance3D
var _splash: MultiMeshInstance3D
var _plain_ferry := []               # round 3: moving bridges with no relay (Sim._ferry_edges -1): their deck parts
var _belts := []                     # round 3: plain belts with no relay (Sim._belt_edges): their chevrons
var _belt_phase := 0.0
var _fall_watch := []               # 2026-11-05 ("they all have destroy animation"): {node, edge, done} - a moving
                                     # deck piece that tumbles down when an end node collapses (Fx._collapse's fall)
var _belt_curves := []               # conveyors 4.1: the plain belts' curve pieces (_curve_treads)
var _v3_plats := {}                  # round 3: node id -> its Platform_Relay_v3
var _t := 0.0
var _dt := 0.0
var human := "A"                     # the seat this screen plays (main.gd): whose launcher aim is "TARGET"
var _unbatched := false              # round 3: the lift / tilt platforms left MapBatch (see _unbatch)


static func wanted(s: Sim) -> bool:
	## A prototype relay node, OR a hazard with no relay (a plain ferry / belt deck: round 3 / round R). Round R fix
	## (Daniele 2026-11-05, "ferry are invisible"): R-01 / R-03 / R-04 have hazards but no prototype node, so the view was
	## never built - the decks stood still on screen while the sim moved them.
	if not s._ferry_edges.is_empty() or not s._belt_edges.is_empty():
		return true
	for n in s.nodes:
		if Rules.is_proto(str(n["relay"])):
			return true
	return false


func setup(s: Sim, v: Dictionary) -> void:
	sim = s
	vis = v
	name = "ProtoRelayView"
	for n in sim.nodes:
		var k: String = n["relay"]
		if not Rules.is_proto(k):
			continue
		var id: int = n["id"]
		var r := {"kind": k, "pointer": _pointer(), "ghost_pointer": _pointer(true)}
		match k:
			"ferry":
				r["ferry"] = []
				for ei in sim.controlled_edges(id):
					r["ferry"].append(_ferry_deck(ei))
			"conveyor":
				r["chev"] = _chevrons(sim.controlled_edges(id))
				r["phase"] = 0.0
			"launcher":
				r["pad"] = _pad(n)
				r["arc"] = _arc_dots()
				r["rings"] = _target_rings(n)
				r["aim"] = -1
				r["aim_pop"] = 0.0
				r["kick"] = 0.0                       # round 3: the pad's kick per throw
				r["thrown"] = 0
			"lift", "tilt":
				var base := {}
				for p in vis[id]["parts"]:
					if p != null:
						base[p] = (p as Node3D).transform
				r["base"] = base
				if k == "tilt":
					r["strips"] = _exit_strips(n)
					r["chev"] = {}
					r["phase"] = 0.0
					r["arrow"] = {}
					for x in n["proto"].get("exits", []):
						var ei := sim._edge_index(id, int(x))
						if ei >= 0:
							r["chev"][int(x)] = _chevrons([ei], Rules.RELAY_GHOST_COLORS["tilt"])[0]
							r["arrow"][int(x)] = _platform_arrow(n, int(x))
				else:
					r["lift"] = _lift_parts(n)
		_r[id] = r
	_flights = MultiMeshInstance3D.new()
	_flights.name = "Proto_Launcher_Flight"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 8
	blob.rings = 4
	mm.mesh = blob
	mm.instance_count = FLIGHT_BLOBS
	mm.visible_instance_count = 0
	_flights.multimesh = mm
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flights.material_override = fm
	add_child(_flights)
	_splash = MultiMeshInstance3D.new()               # round 3: a landing's ring in the thrower's colour
	_splash.name = "Proto_Launcher_Splash"
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.use_colors = true
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 2.2
	tm.rings = 24
	tm.ring_segments = 6
	smm.mesh = tm
	smm.instance_count = SPLASHES
	smm.visible_instance_count = 0
	_splash.multimesh = smm
	var spm := StandardMaterial3D.new()
	spm.vertex_color_use_as_albedo = true
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash.material_override = spm
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	for ei in sim._ferry_edges:                       # round 3: the plain pieces (no relay, no button, no pointer)
		if int(sim._ferry_edges[ei]) < 0:
			_plain_ferry.append(_ferry_deck(int(ei)))
	_belts = _chevrons(sim._belt_edges.keys(), Rules.state_color("cAB"))
	for c in _belts:
		_v3_belt(c, false)
	for id in _r:
		if _r[id]["kind"] == "conveyor":
			for c in _r[id]["chev"]:
				_v3_belt(c, true)
	_belt_curves = _curve_treads(sim._belt_edges.keys(), false)   # round R: speed / belt curves (conveyors 4.1)
	for id in _r:
		if _r[id]["kind"] == "conveyor":
			_r[id]["curves"] = _curve_treads(sim.controlled_edges(id), true)
	_v3_platforms()


func _v3_belt(c: Dictionary, relay: bool) -> void:
	## Round 3: the conveyor deck model (with its Treads) instead of the edge's module decks and the stand-in chevrons.
	## Conveyors 4.1: the nearest native length (2..20 m), the plain belt in its own slat look.
	var a: Vector3 = c["a"]
	var b: Vector3 = c["b"]
	var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var L := 4
	for l in CONV_LENGTHS:
		if absf(d - l) < absf(d - L):
			L = l
	var nm := ("Deck_Conveyor_Relay_v3_%d" if relay else "Deck_Conveyor_Belt_v4_%d") % L
	if not _kit(nm):                                  # (an older kit: the 4 / 8 / 12 m round-3 pieces, stretched)
		L = _deck_len(a, b)
		nm = ("Deck_Conveyor_Relay_v3_%d" if relay else "Deck_Conveyor_v3_%d") % L
		if not _kit(nm):
			return
	c["v3"] = _v3_piece(nm, a, (b - a).normalized())
	(c["v3"] as Node3D).scale = Vector3(d / float(L), 1.0, 1.0)   # the rest of the way to the lips (the treads stay on)
	c["v3_len"] = L
	_fall_watch.append({"node": c["v3"], "edge": int(c["edge"]), "done": false})
	c["v3_period"] = float(CONV_PERIOD.get(nm, TREAD_PERIOD.get(L, 1.0)))
	var tr := (c["v3"] as Node).find_child("Treads", true, false)
	c["treads"] = tr
	c["treads_x"] = (tr as Node3D).position.x if tr is Node3D else 0.0
	var rv := (c["v3"] as Node).find_child("TreadsRev", true, false)
	if rv is Node3D:                                  # (straight decks turn round instead)
		(rv as Node3D).visible = false
	c["v3_fwd"] = true

# ------------------------------------------------------------------ pieces
func _mat(c: Color, a := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, a)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _pointer(ghost := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Proto_Relay_Pointer" + ("_Ghost" if ghost else "")
	var pm := PrismMesh.new()                         # apex at +Y, turned to point along +X
	pm.size = Vector3(1.6, 2.6, 0.45)
	mi.mesh = pm
	mi.material_override = _mat(Color.WHITE, 0.4 if ghost else 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _label(font_size: int) -> Label3D:
	var l := Label3D.new()
	TopBand.tag(l)
	l.font = Fx.SYMBOL_FONT
	l.font_size = font_size
	l.pixel_size = 0.03
	l.outline_size = 16
	l.outline_modulate = Color(0.02, 0.02, 0.05, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	add_child(l)
	return l


func _aim(mi: MeshInstance3D, at: Vector3, dir: Vector3) -> void:
	## Points the pointer at `at` along `dir` (horizontal), or straight up / down when dir is vertical.
	mi.position = at
	if absf(dir.y) > 0.9:
		mi.basis = Basis(Vector3.RIGHT, 0.0 if dir.y > 0.0 else PI)
	else:
		var d := Vector3(dir.x, 0.0, dir.z).normalized()
		mi.basis = Basis(Vector3.UP, Rules.heading(d)) * Basis(Vector3.BACK, -PI / 2.0)


func _tint(mi: MeshInstance3D, c: Color) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
	m.emission = c


static func _kit(name: String) -> bool:
	return ResourceLoader.exists(Cosmetics.kit_path(name))


func _deck_len(a: Vector3, b: Vector3) -> int:
	## The kit length (4 / 8 / 12 m) of the deck between pier lips a and b.
	var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var best := 4
	for L in [4, 8, 12]:
		if absf(d - L) < absf(d - best):
			best = L
	return best


func _v3_piece(name: String, at: Vector3, dir: Vector3) -> Node3D:
	## A relays-4.0 kit piece at `at`, its local +X along `dir` (kit convention), drawing itself (never batched).
	var p := MapBuilder.put(self, name, at, Rules.heading(dir))
	p.name = name
	return p


func _hide_decks(ei: int) -> void:
	for d in vis["edge_decks"].get(ei, []):
		(d as Node3D).visible = false


func _v3_platforms() -> void:
	## Platform_Relay_v3 (the relay node: lit hex pedestal + inlaid ring) on EVERY relay node (Daniele 2026-11-05: "apply
	## new relay node model to all relay and make sure they all have destroy animation"): set INTO the node's own platform
	## piece, whose meshes give way, so it rides the lift / tilt motion and falls with the node in Fx._collapse (it used to
	## sit beside it and stay standing). The rotor keeps its turning platform and gets the inlaid ring (Relay_Node_Ring_v3).
	if not _kit("Platform_Relay_v3"):
		return
	for n in sim.nodes:
		if str(n["relay"]) == "":
			continue
		var plat = vis[n["id"]].get("platform")
		if not plat is Node3D or not is_instance_valid(plat):
			continue
		var kind := str(n["relay"])
		var ring := kind == "rotation"
		if ring and not _kit("Relay_Node_Ring_v3"):
			continue
		if not ring:
			for ch in (plat as Node).get_children():
				if ch is Node3D:
					(ch as Node3D).visible = false
		_v3_relay_models(n, plat)
		if kind == "tilt" and _r.get(n["id"], {}).has("v3"):
			continue                                  # (Relay_Tilt_v3 carries its own base and top)
		var nest := "Relay_Lift_Platform_v3" if kind == "lift" and _kit("Relay_Lift_Platform_v3") else "Platform_Relay_v3"
		if nest == "Platform_Relay_v3":
			nest += MapBuilder.deep_tag(n, sim.nodes)       # relay-v3-column: the column's one foot at this node's floor depth
		var p := MapBuilder.piece("Relay_Node_Ring_v3" if ring else nest)
		p.name = "Platform_Relay_v3_%d" % n["id"]
		(plat as Node).add_child(p)
		_v3_plats[n["id"]] = p


func _v3_relay_models(n: Dictionary, plat: Node3D) -> void:
	## 2026-11-05 (Daniele: "create all relay model that are missing for the new relays"): the relays-4.0 pieces for the
	## launcher (Relay_Launcher_v3: Turret aims, Arm throws), the lift (Relay_Lift_Base_v3 stays, the raised platform is
	## Relay_Lift_Platform_v3 nested in the node's own platform) and the tilt (Relay_Tilt_v3: Top tips, Dial points at the
	## next exit). Each joins the node's parts, so it falls with it (Fx._collapse).
	var id: int = n["id"]
	if not _r.has(id):
		return
	var r: Dictionary = _r[id]
	var nm: String = {"launcher": _cannon_name(int(n["tier"])), "lift": "Relay_Lift_Base_v3", "tilt": "Relay_Tilt_v3"}.get(str(n["relay"]), "")
	if nm == "" or not _kit(nm):
		return
	var p := MapBuilder.piece(nm)
	p.name = "%s_%d" % [nm, id]
	add_child(p)
	p.position = n["pos"]
	(vis[id]["parts"] as Array).append(p)
	r["v3"] = p
	match str(n["relay"]):
		"launcher":
			r["turret"] = p.find_child("Turret", true, false)
			r["arm"] = p.find_child("Arm", true, false)
			r["swing"] = 0.0
			r["orbit"] = 0.0
			r["cannon"] = nm.begins_with("Relay_Cannon_v4")   # 2026-11-06 (Daniele): the old cannon IS the launcher's building
			r["tier"] = int(n["tier"])                   # LAUNCHER TURRET: the cannon of its tier (T1 / T2 / T3, a bigger one each)
			r["grow"] = 0.0
			r["head"] = p.find_child("Head", true, false)
			r["head_rest"] = (r["head"] as Node3D).position if r["head"] is Node3D else Vector3.ZERO
			if not r["cannon"]:
				p.scale = Vector3.ONE * LAUNCHER_SCALE
			(r["pad"] as Node3D).visible = false
		"lift":
			(r["lift"]["piston"] as Node3D).visible = false
		"tilt":
			var top = p.find_child("Top", true, false)
			r["top"] = top
			r["top_rest"] = (top as Node3D).transform if top is Node3D else Transform3D.IDENTITY
			r["dial"] = p.find_child("Dial", true, false)


func _cannon_name(tier: int) -> String:
	## LAUNCHER TURRET: the kit's cannon for this tier (8a5fc1a: Relay_Cannon_v4 / _T2 / _T3), else the older stand-ins.
	var nm := "Relay_Cannon_v4" + ("" if tier <= 1 else "_T%d" % mini(tier, 3))
	if _kit(nm):
		return nm
	return "Relay_Cannon_v4" if _kit("Relay_Cannon_v4") else "Relay_Launcher_v3"


func _cannon_retier(n: Dictionary, r: Dictionary) -> void:
	## LAUNCHER TURRET: an upgrade (or a capture / Sinkhole that cost a tier) swaps the cannon for its tier's model, with a pop.
	var id: int = n["id"]
	var old: Node3D = r["v3"]
	var nm := _cannon_name(int(n["tier"]))
	r["tier"] = int(n["tier"])
	if not _kit(nm) or old.name.begins_with(nm + "_"):
		return
	var p := MapBuilder.piece(nm)
	p.name = "%s_%d" % [nm, id]
	add_child(p)
	p.position = old.position
	p.rotation = old.rotation
	var parts: Array = vis[id]["parts"]
	parts.erase(old)
	parts.append(p)
	old.queue_free()
	r["v3"] = p
	r["head"] = p.find_child("Head", true, false)
	r["head_rest"] = (r["head"] as Node3D).position if r["head"] is Node3D else Vector3.ZERO
	r["arm"] = p.find_child("Arm", true, false)
	r["grow"] = 1.0


func _deck_ends(ei: int) -> Array:
	## [the deck's A-end, its B-end] (pier ends, world).
	var pts: Array = sim.deck_points(ei, sim.edges[ei]["a"])
	return [pts[0], pts[-1]]


func _box(nm: String, size: Vector3, c: Color, a := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, a)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _ferry_deck(ei: int) -> Dictionary:
	## One moving-bridge deck: its two rails (the fixed path across both piers), a lamp at each lip, the hole marker, the
	## HELD label (round 3).
	var side: float = float(Rules.RELAYS_PROTO["ferry"]["side"])
	var ends := _deck_ends(ei)
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	var u := (b - a).normalized()
	var perp := Vector3(-u.z, 0.0, u.x)
	var yaw := Rules.heading(u)
	var parts := {"edge": ei, "a": a, "b": b, "u": u, "perp": perp, "rails": [], "lamps": []}
	for end in [a, b]:
		var rail := _box("Proto_Ferry_Rail", Vector3(0.35, 0.18, 2.0 * side + Rules.W), Rules.RELAY_GHOST_COLORS["ferry"], 0.85)
		rail.position = end + Vector3(0, -0.05, 0)
		rail.rotation.y = yaw
		parts["rails"].append(rail)
		var lamp := MeshInstance3D.new()
		lamp.name = "Proto_Ferry_Lamp"
		var sm := SphereMesh.new()
		sm.radius = FERRY_LAMP
		sm.height = FERRY_LAMP * 2.0
		lamp.mesh = sm
		lamp.material_override = _mat(Color.WHITE)
		lamp.position = end + perp * (Rules.W * 0.5 + 0.7) + Vector3(0, 1.0, 0)
		add_child(lamp)
		parts["lamps"].append(lamp)
	var hole := _box("Proto_Ferry_Hole", Vector3(a.distance_to(b), 0.06, Rules.W), Rules.state_color("warn"), 0.3)
	hole.position = (a + b) * 0.5 + Vector3(0, 0.25, 0)
	hole.rotation.y = yaw
	parts["hole"] = hole
	var L := _deck_len(a, b)                       # round 3: the relays-4.0 barge + rails, when the kit has them
	var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var L4 := 4                                    # ferry 4.1 (🎨 2026-11-05, "better model for ferry including different
	for l in CONV_LENGTHS:                         # sizes"): Deck_Ferry_v4_<L>, every length 2..20 m, stretched the rest
		if absf(d - l) < absf(d - L4):
			L4 = l
	if _kit("Deck_Ferry_v4_%d" % L4):
		parts["v3"] = _v3_piece("Deck_Ferry_v4_%d" % L4, a, u)
		(parts["v3"] as Node3D).scale = Vector3(d / float(L4), 1.0, 1.0)
		parts["v3_at"] = a
		_fall_watch.append({"node": parts["v3"], "edge": ei, "done": false})
	elif _kit("Deck_Ferry_v3_%d" % L):
		parts["v3"] = _v3_piece("Deck_Ferry_v3_%d" % L, a, u)
		parts["v3_at"] = a
	if _kit("Relay_Ferry_Rail_v3"):
		for rail in parts["rails"]:
			(rail as Node3D).queue_free()
		for lamp in parts["lamps"]:
			(lamp as Node3D).queue_free()
		parts["rails"] = []
		parts["lamps"] = []
		for end in [[a, u], [b, -u]]:
			var rv := _v3_piece("Relay_Ferry_Rail_v3", end[0], end[1])
			parts["rails"].append(rv)
			var light := rv.find_child("Light", true, false)
			if light is MeshInstance3D:
				(light as MeshInstance3D).material_override = _mat(Color.WHITE)
				parts["lamps"].append(light)
	var held := _label(64)                         # round 3: HELD n over the deck while its owner holds it
	held.position = (a + b) * 0.5 + Vector3(0, 6.5, 0)   # (above the FERRY n / m CROSSED callout)
	held.visible = false
	parts["held"] = held
	return parts


func _chevrons(eis: Array, col := Color.WHITE) -> Array:
	var out := []
	for ei in eis:
		var ends := _deck_ends(ei)
		var L: float = (ends[1] as Vector3).distance_to(ends[0])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var pm := PrismMesh.new()
		pm.size = Vector3(2.0, 1.3, 0.12)
		mm.mesh = pm
		mm.instance_count = maxi(1, int(L / CHEVRON_GAP))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Proto_Conveyor_Chevron"
		mmi.multimesh = mm
		mmi.material_override = _mat(col)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		out.append({"edge": ei, "mmi": mmi, "a": ends[0], "b": ends[1], "L": L})
	return out


func _curve_treads(eis: Array, relay: bool) -> Array:
	## Round R (Daniele 2026-11-05: "speed and slow can be curves - the whole curve piece looks like a speed one"; proto13:
	## "the speed relay bridge indicator needs to be consistent and look like on normal bridges"): every curve junction
	## (Sim._conv_pieces) at an end of these decks wears its conveyor version (<Curve>_Conveyor_Relay_v4 on a relay lane,
	## _Belt_v4 on a plain belt), set INTO the plain curve's node so it falls with it; its Treads turn round the curve
	## centre in the deck's flow. Each curve once (the lower deck index carries it).
	var out := []
	for ei in eis:
		var e: Dictionary = sim.edges[ei]
		for end in [e["a"], e["b"]]:
			if not sim._conv_pieces.has(end) or not str(sim.nodes[end]["junction"]).begins_with("Curve_"):
				continue                                  # (a Crossing lane is straight: its decks' treads carry the look)
			var other := -1
			for k in range(sim.edges.size()):
				if k != ei and (sim.edges[k]["a"] == end or sim.edges[k]["b"] == end):
					other = k
			if other < 0 or other < ei:
				continue
			var j: Dictionary = sim.nodes[end]
			var nm := "%s_Conveyor_%s_v4" % [str(j["junction"]), "Relay" if relay else "Belt"]
			var plat = vis.get(end, {}).get("platform")
			if not _kit(nm) or not plat is Node3D:
				continue
			for ch in (plat as Node).get_children():      # the plain curve's own meshes give way to the conveyor one
				if ch is Node3D:
					(ch as Node3D).visible = false
			var piece := MapBuilder.piece(nm)
			piece.name = nm
			(plat as Node).add_child(piece)               # same origin (start port) and yaw as the plain curve
			var pos: Vector3 = j["pos"]
			var p_this: Vector3 = sim.exit_of(ei, end)
			var p_other: Vector3 = sim.exit_of(other, end)
			var this_is_start := p_this.distance_to(pos) < p_other.distance_to(pos)
			out.append({"edge": ei, "curve": piece, "treads": piece.find_child("Treads", true, false),
					"treads_rev": piece.find_child("TreadsRev", true, false), "period": float(CONV_PERIOD.get(nm, 0.13)),
					"r": Sim.curve_r(str(j["junction"])), "ab_is_start_end": this_is_start == (end == e["b"])})
	return out


func _curve_sync(c: Dictionary, phase: float, forward: bool, shown: bool) -> void:
	## A conveyor curve: the Treads (start -> end) or TreadsRev (end -> start) shown for the flow, turned round the centre.
	var se: bool = forward == bool(c["ab_is_start_end"])
	var tr = c["treads"]
	var rv = c["treads_rev"]
	var ang := fposmod(absf(phase) * 0.4 / float(c["r"]), float(c["period"]))
	if tr is Node3D:
		(tr as Node3D).visible = shown and se
		(tr as Node3D).rotation.y = ang
	if rv is Node3D:
		(rv as Node3D).visible = shown and not se
		(rv as Node3D).rotation.y = -ang


func _run_poly(c: Dictionary, phase: float, move_fwd: bool, face_fwd: bool, y: float) -> void:
	## A curve's chevrons: `phase` m along its arc, each turned along the arc there (A -> B, or B -> A).
	var pts: Array = c["pts"]
	var cum: Array = c["cum"]
	var L: float = c["L"]
	var mm: MultiMesh = (c["mmi"] as MultiMeshInstance3D).multimesh
	for k in range(mm.instance_count):
		var s := fposmod(float(k) * CHEVRON_GAP + (phase if move_fwd else -phase), maxf(L, 0.01))
		var i := 1
		while i < pts.size() - 1 and float(cum[i]) < s:
			i += 1
		var p0: Vector3 = pts[i - 1]
		var p1: Vector3 = pts[i]
		var seg := maxf(float(cum[i]) - float(cum[i - 1]), 0.001)
		var u := (p1 - p0).normalized()
		var face := u * (1.0 if face_fwd else -1.0)
		var basis := Basis(Vector3.UP, Rules.heading(face)) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, -PI / 2.0)
		mm.set_instance_transform(k, Transform3D(basis, p0.lerp(p1, clampf((s - float(cum[i - 1])) / seg, 0.0, 1.0)) + Vector3(0, y, 0)))


func _platform_arrow(n: Dictionary, toward: int) -> Dictionary:
	## Tilt (round 2): big chevrons across the platform from its centre to the rim toward `toward` - a tip toward or away
	## from the camera barely shows, the running arrow always does. Same shape as a deck's chevrons (_run_chevrons).
	var c: Vector3 = n["pos"]
	var dir := ((sim.nodes[toward]["pos"] as Vector3) - c)
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PrismMesh.new()
	pm.size = Vector3(3.6, 2.2, 0.16)
	mm.mesh = pm
	mm.instance_count = 3
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Proto_Tilt_Arrow"
	mmi.multimesh = mm
	mmi.material_override = _mat(Rules.RELAY_GHOST_COLORS["tilt"])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return {"edge": -1, "mmi": mmi, "a": c - dir * (Rules.R * 0.6), "b": c + dir * (Rules.R + 0.4), "L": Rules.R * 1.6 + 0.4}


func _run_chevrons(c: Dictionary, phase: float, forward: bool, y := 0.36) -> void:
	## Lays the deck's chevrons out `phase` m along it, pointing A -> B (forward) or B -> A.
	if c.has("pts"):                                   # round R: a speed curve
		c["ph"] = phase
		c["y"] = y
		_run_poly(c, phase, forward, forward, y)
		return
	var a: Vector3 = c["a"]
	var b: Vector3 = c["b"]
	var u := (b - a).normalized()
	var L: float = c["L"]
	var face := u * (1.0 if forward else -1.0)
	var basis := Basis(Vector3.UP, Rules.heading(face)) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, -PI / 2.0)   # flat, apex along the flow
	var mm: MultiMesh = (c["mmi"] as MultiMeshInstance3D).multimesh
	for k in range(mm.instance_count):
		var s := fposmod(float(k) * CHEVRON_GAP + (phase if forward else -phase), L)
		mm.set_instance_transform(k, Transform3D(basis, a + u * s + Vector3(0, y, 0)))


func _lift_parts(n: Dictionary) -> Dictionary:
	## Round 2: the piston under the platform, a lit strip on each lift deck (shown while open), the UP / DOWN badge.
	var id: int = n["id"]
	var piston := MeshInstance3D.new()
	piston.name = "Proto_Lift_Piston"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 2.0
	cm.height = 1.0
	piston.mesh = cm
	piston.material_override = _mat(Rules.RELAY_GHOST_COLORS["lift"], 0.8)
	piston.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piston)
	var strips := {}
	var tags := {}
	var ghosts := {}
	var edges_m := {}
	for ei in sim.controlled_edges(id):
		var line: Array = sim.deck_line(ei)
		var a: Vector3 = line[0]
		var b: Vector3 = line[-1]
		var yaw := Rules.heading((b - a).normalized())
		var lvl_col: Color = Rules.RELAY_GHOST_COLORS["lift"] if int(sim.edges[ei]["lift_level"]) == 1 else Rules.RELAY_GHOST_COLORS["ferry"]
		var mi := _box("Proto_Lift_OpenStrip", Vector3(a.distance_to(b), 0.12, Rules.W * 0.5), Rules.RELAY_GHOST_COLORS["lift"], 0.85)
		mi.position = (a + b) * 0.5 + Vector3(0, 0.42, 0)
		mi.basis = _along(a, b)                       # (an UP deck is a ramp to the raised platform: tilt with it)
		strips[ei] = mi
		# round 3 (Daniele: "players may misread the bridge animation"): a flat UP / DOWN painted on every lift deck in its
		# level's colour (lit while it connects), a ghost of the deck where it docks when it is closed, and a glowing
		# edge riding the deck's platform end while it moves
		var tag := Label3D.new()
		TopBand.tag(tag)
		tag.font = Fx.SYMBOL_FONT
		tag.font_size = 96
		tag.pixel_size = 0.02
		tag.no_depth_test = true                    # (a sunk deck's rails would cut it)
		tag.render_priority = 2
		tag.outline_size = 18
		tag.outline_modulate = Color(0.02, 0.02, 0.05, 0.9)
		tag.text = "▲ UP" if int(sim.edges[ei]["lift_level"]) == 1 else "▼ DOWN"
		tag.modulate = lvl_col
		tag.rotation = Vector3(-PI / 2.0, 0.0, 0.0)       # flat on the deck, read from the camera
		tag.rotation.y = 0.0
		add_child(tag)
		tags[ei] = tag
		var ghost := _box("Proto_Lift_DockGhost", Vector3(a.distance_to(b), 0.3, Rules.W), lvl_col, 0.22)
		ghost.position = (a + b) * 0.5 + Vector3(0, 0.2, 0)
		ghost.basis = _along(a, b)
		ghosts[ei] = ghost
		var edge := _box("Proto_Lift_MovingEdge", Vector3(0.5, 0.5, Rules.W + 0.6), Color.WHITE, 0.95)
		edge.rotation.y = yaw
		edge.visible = false
		edges_m[ei] = edge
	return {"piston": piston, "strips": strips, "badge": _label(96), "tags": tags, "ghosts": ghosts, "edges": edges_m}


func _pad(n: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Proto_Launcher_Pad"
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4
	cm.bottom_radius = 2.8
	cm.height = 0.5
	mi.mesh = cm
	mi.position = (n["pos"] as Vector3) + Vector3(0, 0.3, 0)
	mi.material_override = _mat(Rules.RELAY_GHOST_COLORS["launcher"])
	add_child(mi)
	return mi


func arc_point(from: Vector3, to: Vector3, k: float) -> Vector3:
	var d := from.distance_to(to)
	var apex := maxf(8.0, 0.35 * d)
	return from.lerp(to, k) + Vector3(0, 4.0 * apex * k * (1.0 - k) + 1.0, 0)


func _arc_dots() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = ARC_DOTS
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Proto_Launcher_Arc"
	mmi.multimesh = mm
	mmi.material_override = _mat(Rules.RELAY_GHOST_COLORS["launcher"], 0.5)
	mmi.visible = false
	add_child(mmi)
	return mmi


func _target_rings(n: Dictionary) -> Dictionary:
	## Round 2: a ring over every node the launcher can aim at (the aimed one bright, the others small and dim) + the
	## TARGET / LOCKED label (key -1).
	var out := {}
	for x in n["proto"].get("targets", []):
		var mi := MeshInstance3D.new()
		mi.name = "Proto_Launcher_TargetRing"
		var tm := TorusMesh.new()
		tm.inner_radius = Rules.R + 0.6
		tm.outer_radius = Rules.R + 1.6
		tm.rings = 32
		tm.ring_segments = 8
		mi.mesh = tm
		mi.material_override = _mat(Rules.RELAY_GHOST_COLORS["launcher"], 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = (sim.nodes[int(x)]["pos"] as Vector3) + Vector3(0, 0.9, 0)
		add_child(mi)
		out[int(x)] = mi
	out[-1] = _label(72)
	return out


func _exit_strips(n: Dictionary) -> Dictionary:
	var out := {}
	for x in n["proto"].get("exits", []):
		var ei := sim._edge_index(n["id"], int(x))
		if ei < 0:
			continue
		var line: Array = sim.deck_line(ei)
		var a: Vector3 = line[0]
		var b: Vector3 = line[-1]
		var mi := _box("Proto_Tilt_ExitStrip", Vector3(a.distance_to(b), 0.12, Rules.W * 0.55), Rules.RELAY_GHOST_COLORS["tilt"], 0.5)
		mi.position = (a + b) * 0.5 + Vector3(0, 0.42, 0)
		mi.rotation.y = Rules.heading((b - a).normalized())
		mi.visible = false
		out[int(x)] = mi
	return out


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	_unbatch()
	_watch_falls()
	_t += dt
	_dt = dt
	for id in _r:
		var n: Dictionary = sim.nodes[id]
		var r: Dictionary = _r[id]
		var gone: bool = sim.collapsed.get(id, false)
		var phase: String = n["relay_phase"]
		var blink := int(sim.time * 5.0) % 2 == 0
		var col := Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
		var next_col := Rules.state_color(sim.relay_state_key(n, n["relay_pending"]))
		var top: Vector3 = (n["pos"] as Vector3) + Vector3(0, POINTER_UP, 0)
		var p: MeshInstance3D = r["pointer"]
		var gp: MeshInstance3D = r["ghost_pointer"]
		p.visible = not gone
		gp.visible = not gone and phase == "warning"
		(p.material_override as StandardMaterial3D).albedo_color = col
		(p.material_override as StandardMaterial3D).emission = col
		(gp.material_override as StandardMaterial3D).albedo_color = Color(next_col.r, next_col.g, next_col.b, 0.75 if blink else 0.3)
		(gp.material_override as StandardMaterial3D).emission = next_col
		match r["kind"]:
			"ferry":
				_ferry(n, r, top, gone)
			"conveyor":
				_conveyor(n, r, top, phase, blink, dt, gone)
			"launcher":
				_launcher(n, r, top, phase, blink, gone)
			"lift":
				_lift(n, r, top, phase)
			"tilt":
				_tilt(n, r, top, phase, blink, gone)
	for parts in _plain_ferry:                        # round 3: the plain pieces
		_ferry_deck_sync(parts, sim.ferry_phase_e(int(parts["edge"])), false)
	_ferry3_hulls()
	if not _belts.is_empty() or not _belt_curves.is_empty():
		_belt_phase += dt * CHEVRON_SPEED * float(Rules.RELAYS_PROTO["conveyor"]["with"])
		for c in _belt_curves:
			var fab: bool = int(sim._belt_edges[int(c["edge"])]) == 0
			_curve_sync(c, _belt_phase if fab else -_belt_phase, fab,
					not sim.demolished.has(int(c["edge"])) and sim.is_edge_open(int(c["edge"])))
		for c in _belts:
			var flow_ab: bool = int(sim._belt_edges[int(c["edge"])]) == 0
			var mmi: MultiMeshInstance3D = c["mmi"]
			var shown: bool = not sim.demolished.has(int(c["edge"])) and sim.is_edge_open(int(c["edge"]))
			if c.has("v3"):
				mmi.visible = false
				_v3_belt_sync(c, _belt_phase if flow_ab else -_belt_phase, flow_ab, shown)
				continue
			mmi.visible = shown
			_run_chevrons(c, _belt_phase, flow_ab)
	_flight_stream()
	_speed_tags()
	PerfProfile.lap("proto_view", _pt)


func _watch_falls() -> void:
	## A moving deck piece (ferry barge, conveyor deck) whose end node collapsed: a copy tumbles 26 m down over 1.5 s
	## like the kit decks in Fx._fall_pieces (the piece itself is hidden by its sync as the edge closes).
	for it in _fall_watch:
		if it["done"] or not is_instance_valid(it["node"]):
			continue
		var e: Dictionary = sim.edges[int(it["edge"])]
		if not (sim.collapsed.get(e["a"], false) or sim.collapsed.get(e["b"], false)):
			continue
		it["done"] = true
		var src: Node3D = it["node"]
		if not src.is_visible_in_tree():
			continue
		var cp := src.duplicate() as Node3D
		add_child(cp)
		cp.global_transform = src.global_transform
		cp.name = src.name + "_Fall"
		var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)) * 1.2
		var tw := create_tween().set_parallel(true)
		tw.tween_property(cp, "position:y", cp.position.y - 26.0, 1.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(cp, "rotation", cp.rotation + spin, 1.5).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(cp.queue_free)


func _unbatch() -> void:
	## Round 3 (the TILT lag, Daniele 2026-11-02 "the animation lags badly"): MapBatch draws a platform's kit pieces as
	## STATIC batch slots (map_batch.gd STATIC_KIT) and never re-reads their transforms, so a tipped / raised platform
	## moved its nodes while its drawn copy stayed flat - only the polled vat tipped, then the whole thing snapped. The
	## lift and tilt platforms draw themselves instead (MapBatch.release, as a falling piece does): a few more draw
	## calls on the P maps, nothing per frame. Waits for the batch, which PerfProfile builds after this view's setup.
	if _unbatched:
		return
	if MapBatch.disabled:
		_unbatched = true
		return
	if MapBatch.current == null:
		return
	_unbatched = true
	for id in _r:
		if _r[id].has("base"):
			MapBatch.release((_r[id]["base"] as Dictionary).keys())


func _ferry(n: Dictionary, r: Dictionary, top: Vector3, gone: bool) -> void:
	## Round 2: the deck itself slides sideways along its rails (Sim.ferry_phase), lamps green / red, the hole while out.
	## Round 3: held in line by its owner - steady bright lamps, glowing rails, HELD n over the deck.
	var fp := sim.ferry_phase(n["id"])
	var lc := Color.WHITE
	for parts in r["ferry"]:
		lc = _ferry_deck_sync(parts, sim.ferry_phase_e(int(parts["edge"])), gone)
	if not (r["ferry"] as Array).is_empty():
		var c0: Dictionary = r["ferry"][0]
		_aim(r["pointer"], top, (c0["u"] as Vector3) if fp["part"] == "open" else (c0["perp"] as Vector3) * float(fp["side"]))
		_tint(r["pointer"], lc)
	(r["ghost_pointer"] as Node3D).visible = false


func _ferry_deck_sync(parts: Dictionary, fp: Dictionary, gone: bool) -> Color:
	## One moving-bridge deck this frame; returns its lamps' colour.
	var side: float = float(Rules.RELAYS_PROTO["ferry"]["side"])
	var ei0: int = parts["edge"]
	var lane3: bool = (sim._ferry_plain.get(ei0, {}) as Dictionary).has("group")   # round R: one hull over 2-3 lanes
	if lane3:
		side *= 0.35                                   # parallel lanes: the empty lane slides only a little out of line
	var off: float = float(fp["off"]) * float(fp["side"]) * side
	var open: bool = fp["part"] == "open"
	var held: float = float(fp.get("held", 0.0))
	var soon: bool = open and held <= 0.0 and float(fp["left"]) <= 1.0   # it slides out within a second: the lamps blink red
	var blink_fast := int(sim.time * 8.0) % 2 == 0
	var lc: Color = Color("#5cff7a") if open and not (soon and blink_fast) else Rules.state_color("warn")
	var ei: int = parts["edge"]
	var down: bool = gone or sim.demolished.has(ei) or sim.collapsed.get(sim.edges[ei]["a"], false) \
			or sim.collapsed.get(sim.edges[ei]["b"], false)
	var decks: Array = vis["edge_decks"][ei]
	if parts.has("v3"):                              # round 3: the barge model slides; the module decks stay hidden
		_hide_decks(ei)
		(parts["v3"] as Node3D).visible = not down
		(parts["v3"] as Node3D).position = (parts["v3_at"] as Vector3) + (parts["perp"] as Vector3) * off
	else:
		for k in range(decks.size()):
			var d: Node3D = decks[k]
			d.visible = not down
			d.transform = (vis["edge_base"][ei][k] as Transform3D).translated((parts["perp"] as Vector3) * off)
	var pulse := 0.5 + 0.5 * sin(sim.time * 7.0)
	for rail in parts["rails"]:
		(rail as Node3D).visible = not down
		if not rail is MeshInstance3D:
			continue                                     # (the relays-4.0 rail: its Light is the lamp below)
		var rm := (rail as MeshInstance3D).material_override as StandardMaterial3D
		rm.emission = Color("#5cff7a") if held > 0.0 else Rules.RELAY_GHOST_COLORS["ferry"]
		rm.emission_energy_multiplier = (2.5 + 2.0 * pulse) if held > 0.0 else 1.4
	for lamp in parts["lamps"]:
		_tint(lamp, lc)
		((lamp as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 5.0 if held > 0.0 else 3.0
		(lamp as Node3D).visible = not down
	var hole: MeshInstance3D = parts["hole"]
	hole.visible = not down and not open
	(hole.material_override as StandardMaterial3D).albedo_color.a = 0.18 + (0.14 if blink_fast else 0.0)
	var hl: Label3D = parts["held"]
	hl.visible = not down and held > 0.0
	if held > 0.0:
		hl.text = "HELD · %d" % int(ceil(held))
		hl.modulate = Color("#5cff7a")
	elif lane3 and not down:                          # round R readout: which lane the ferry serves, and when
		hl.visible = true
		if open:
			hl.text = "FERRY · %d" % int(ceil(float(fp["left"])))
			hl.modulate = Color("#5cff7a")
		else:
			hl.text = "IN %d" % int(ceil(float(fp["next_open"])))
			hl.modulate = Rules.RELAY_GHOST_COLORS["ferry"]
			if Calm.labels() and float(fp["next_open"]) > Calm.IN_TAG_S:
				hl.visible = false                         # calm-pass B: the lane's IN n only while it is about to open
	return lc


func _ferry3_hulls() -> void:
	## Round R 3-lane ferry (demo-rules-pass, Daniele 2026-11-09: "ferry animation broken"): the rule is ONE hull serving the
	## lanes (Sim.ferry3_lane), but every lane drew its own barge nudged 2.6 m aside, so nothing ever travelled. Now one
	## barge is shown: in line on the lane the hull sits on, gliding from lane to lane (eased) while it moves; the other
	## lanes' barges hide (their lips keep the red hole + IN n). A lane whose end node collapsed hides with it.
	var by_group := {}
	for parts in _plain_ferry:
		var rec: Dictionary = sim._ferry_plain.get(int(parts["edge"]), {})
		if not rec.has("group") or not parts.has("v3"):
			continue
		if not by_group.has(rec["group"]):
			by_group[rec["group"]] = {}
		by_group[rec["group"]][int(rec["pos"])] = parts
	for g in by_group:
		var lanes: Dictionary = by_group[g]
		var L := sim.ferry3_lane(g)
		var s := sim.ferry3_slot(g)
		var from: int = int(L["from"])
		var to: int = int(L["to"])
		var hull_lane: int = int(L["at"]) if int(L["at"]) >= 0 else from
		for pos in lanes:
			var ei: int = lanes[pos]["edge"]
			var down: bool = sim.demolished.has(ei) or sim.collapsed.get(sim.edges[ei]["a"], false) \
					or sim.collapsed.get(sim.edges[ei]["b"], false)
			(lanes[pos]["v3"] as Node3D).visible = pos == hull_lane and not down
		if not lanes.has(hull_lane):
			continue
		var hull: Node3D = lanes[hull_lane]["v3"]
		if bool(L["moving"]) and lanes.has(from) and lanes.has(to):
			var k := smoothstep(0.0, 1.0, clampf(float(L["u"]) / maxf(float(s["move"]), 0.01), 0.0, 1.0))
			hull.position = (lanes[from]["v3_at"] as Vector3).lerp(lanes[to]["v3_at"], k)
		else:
			hull.position = lanes[hull_lane]["v3_at"]


func _conveyor(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, dt: float, gone: bool) -> void:
	var sign := 1.0 if int(n["relay_index"]) == 0 else -1.0          # +1: flowing A -> B
	var speed := sign
	if phase == "moving":                              # the arrows reverse through the flip
		var p := float(n["relay_anim"].get("progress", 0.0))
		speed = lerpf(-sign, sign, p)                  # (relay_index is already the new direction)
	r["phase"] = float(r["phase"]) + dt * CHEVRON_SPEED * float(Rules.RELAYS_PROTO["conveyor"]["with"]) * speed
	var col := Rules.state_color(sim.relay_state_key(n, n["relay_index"]))
	if phase == "warning":
		col = Rules.state_color(sim.relay_state_key(n, n["relay_pending"])) if blink else Rules.state_color("warn")
	for c in r["chev"]:
		var mmi: MultiMeshInstance3D = c["mmi"]
		if c.has("v3"):                                # round 3: the belt model's own Treads run instead
			mmi.visible = false
			_v3_belt_sync(c, float(r["phase"]), speed >= 0.0, not gone and sim.is_edge_open(int(c["edge"])))
			continue
		mmi.visible = not gone and sim.is_edge_open(int(c["edge"]))
		_tint_mm(mmi, col)
		_run_chevrons(c, float(r["phase"]), true)      # (the phase already runs backwards against A -> B)
		_face_chevrons(c, speed >= 0.0)
	for c in r.get("curves", []):
		_curve_sync(c, float(r["phase"]), speed >= 0.0, not gone and sim.is_edge_open(int(c["edge"])))
	if not (r["chev"] as Array).is_empty():
		var c0: Dictionary = r["chev"][0]
		var flow: Vector3 = ((c0["b"] as Vector3) - (c0["a"] as Vector3)) * sign
		_aim(r["pointer"], top, flow)
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), -flow)


func _v3_belt_sync(c: Dictionary, phase: float, forward: bool, shown: bool) -> void:
	## The relays-4.0 belt: the deck model faces the flow (from A, or turned round from B) and its Treads scroll along.
	var deck: Node3D = c["v3"]
	_hide_decks(int(c["edge"]))
	deck.visible = shown
	if bool(c["v3_fwd"]) != forward:
		c["v3_fwd"] = forward
		var a: Vector3 = c["a"]
		var b: Vector3 = c["b"]
		deck.position = a if forward else b
		deck.rotation.y = Rules.heading((b - a).normalized() * (1.0 if forward else -1.0))
	var tr = c.get("treads")
	if tr is Node3D:
		var period: float = float(c.get("v3_period", TREAD_PERIOD.get(int(c["v3_len"]), 1.0)))
		(tr as Node3D).position.x = float(c["treads_x"]) + fposmod(absf(phase) * 0.4, period)


func _tint_mm(mmi: MultiMeshInstance3D, c: Color) -> void:
	var m := mmi.material_override as StandardMaterial3D
	m.albedo_color = c
	m.emission = c


func _face_chevrons(c: Dictionary, forward: bool) -> void:
	## Turns the deck's chevrons to point A -> B (forward) or B -> A, keeping where they are.
	if c.has("pts"):                                   # round R: a speed curve (positions from its last run)
		_run_poly(c, float(c.get("ph", 0.0)), true, forward, float(c.get("y", 0.36)))
		return
	var u := ((c["b"] as Vector3) - (c["a"] as Vector3)).normalized()
	var face := u * (1.0 if forward else -1.0)
	var basis := Basis(Vector3.UP, Rules.heading(face)) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, -PI / 2.0)
	var mm: MultiMesh = (c["mmi"] as MultiMeshInstance3D).multimesh
	for k in range(mm.instance_count):
		mm.set_instance_transform(k, Transform3D(basis, mm.get_instance_transform(k).origin))


func _launcher(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, gone: bool) -> void:
	## Round 2: the arc always runs to the node it aims at now (dots marching along it); the aim swings every cycle (a
	## pop on the new target) and locks (solid ring, LOCKED) from the fire to the end of the arm.
	var id: int = n["id"]
	var tgt: int = sim.launcher_aim(id)
	var arc: MultiMeshInstance3D = r["arc"]
	var pad: MeshInstance3D = r["pad"]
	pad.visible = not gone and not r.has("v3")
	var armed := phase == "moving"
	var locked := phase != ""
	if tgt != int(r["aim"]):
		r["aim"] = tgt
		r["aim_pop"] = 1.0
	r["aim_pop"] = maxf(0.0, float(r["aim_pop"]) - _dt * 2.0)
	arc.visible = not gone and tgt >= 0
	var ac: Color = Rules.RELAY_GHOST_COLORS["launcher"]
	if tgt >= 0:
		var from: Vector3 = n["pos"]
		var to: Vector3 = sim.nodes[tgt]["pos"]
		var mm: MultiMesh = arc.multimesh
		var march := fposmod(sim.time * (1.6 if locked else 0.6), 1.0)
		for k in range(ARC_DOTS):
			var q := (float(k) + march) / float(ARC_DOTS + 1)
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (1.4 if locked else 1.0)), arc_point(from, to, q)))
	var m := arc.material_override as StandardMaterial3D
	m.albedo_color = Color(ac.r, ac.g, ac.b, (0.95 if blink else 0.5) if phase == "warning" else (0.9 if armed else 0.45))
	m.emission_energy_multiplier = 3.0 if locked else 1.2
	var pm := pad.material_override as StandardMaterial3D
	var k2 := 0.5 + 0.5 * sin(sim.time * 6.0)        # the armed pad pulses (its ready ring)
	var misfire: bool = n.get("misfire", "") != ""
	var thrown := 0                                   # round 3: every new throw kicks the pad (squash, then pop)
	for f in sim.flights:
		if int(f["from"]) == id:
			thrown += 1
	if thrown > int(r["thrown"]):
		r["kick"] = 1.0
	r["thrown"] = thrown
	r["kick"] = maxf(0.0, float(r["kick"]) - _dt * 5.0)
	var kick := float(r["kick"])
	pm.emission_energy_multiplier = (1.5 + 3.0 * k2) if armed else (1.0 if n["relay_cd"] > 0.0 else 1.8)
	pad.scale = Vector3.ONE * ((1.0 + 0.08 * k2) if armed else 1.0) * Vector3(1.0 + 0.18 * kick, 1.0 - 0.45 * kick, 1.0 + 0.18 * kick)
	pad.position = (n["pos"] as Vector3) + Vector3(0, 0.3 + 0.25 * kick, 0)
	pad.rotation = Vector3.ZERO
	var red := Rules.state_color("warn")
	if misfire:                                       # round 3: scrambled - it wobbles like a tipped plate, blinking red
		pad.rotation = Vector3(0.28 * sin(sim.time * 9.0), 0.0, 0.28 * cos(sim.time * 7.0))
		pm.albedo_color = red if blink else Rules.RELAY_GHOST_COLORS["launcher"]
		pm.emission = red
		pm.emission_energy_multiplier = 4.0
	else:
		pm.albedo_color = Rules.RELAY_GHOST_COLORS["launcher"]
		pm.emission = Rules.RELAY_GHOST_COLORS["launcher"]
	if r.has("v3"):                                   # the relays-4.0 launcher: turret aims, arm throws on each launch
		if kick > 0.75 and float(r["swing"]) < 0.5:
			r["swing"] = 1.0
		r["swing"] = maxf(0.0, float(r["swing"]) - _dt * 1.4)
		if tgt >= 0 and not misfire:                  # the whole launcher circles the vat to stand opposite its target,
			var to3: Vector3 = sim.nodes[tgt]["pos"]     # facing it (turret +X at the target)
			var want := Rules.heading(((to3 - (n["pos"] as Vector3)) * Vector3(1, 0, 1)).normalized())
			r["orbit"] = lerp_angle(float(r["orbit"]), want, minf(1.0, _dt * 4.0))
		if bool(r.get("cannon", false)) and not gone and int(r.get("tier", 1)) != int(n["tier"]):
			_cannon_retier(n, r)                      # LAUNCHER TURRET: a new tier, a bigger cannon
		var v3n: Node3D = r["v3"]
		if bool(r.get("cannon", false)):              # the cannon: on the node's building slot, turned to the target; its
			if not gone:                              # head lifts for the lob while locked, kicks back on every throw
				v3n.position = n["pos"]
				# LAUNCHER TURRET: loading, it throbs and swells with its load (x1.12 full); an upgrade pops it
				var fill: float = clampf(Sim.launcher_loaded(n) / maxf(Sim.launcher_load(n), 0.001), 0.0, 1.0) if armed and not misfire else 0.0
				r["grow"] = maxf(0.0, float(r.get("grow", 0.0)) - _dt * 2.5)
				var g := float(r["grow"])
				v3n.scale = Vector3.ONE * (1.0 + 0.12 * fill + (0.035 * sin(sim.time * (8.0 + 10.0 * fill)) if armed and not misfire else 0.0)
						+ 0.25 * g * (1.0 - g) * 4.0)
				v3n.rotation = Vector3(0.1 * sin(sim.time * 9.0), float(r["orbit"]), 0.1 * cos(sim.time * 7.0)) if misfire 						else Vector3(0.0, float(r["orbit"]), 0.0)
				var hd = r.get("head")
				if hd is Node3D:
					var sw2 := clampf(float(r["swing"]), 0.0, 1.0)
					var lift := deg_to_rad(28.0) if locked else deg_to_rad(8.0)
					(hd as Node3D).rotation.z = lerp_angle((hd as Node3D).rotation.z, lift, minf(1.0, _dt * 4.0)) + deg_to_rad(10.0) * sw2
					(hd as Node3D).position = (r["head_rest"] as Vector3) + Vector3(-0.7 * sw2 * sw2, 0.0, 0.0)
		elif not gone:                                  # (once the node collapses, Fx._collapse's fall owns it)
			var face := Vector3(cos(float(r["orbit"])), 0.0, -sin(float(r["orbit"])))   # (inverse of Rules.heading)
			v3n.position = (n["pos"] as Vector3) - face * LAUNCHER_OFF
			v3n.rotation = Vector3(0.12 * sin(sim.time * 9.0), float(r["orbit"]), 0.12 * cos(sim.time * 7.0)) if misfire 					else Vector3(0.0, float(r["orbit"]), 0.0)
		var am = r.get("arm")
		if am is Node3D:                               # Blender rot.y rest -12 / fire 125 deg = Godot rotation.z -angle
			var sw := clampf(float(r["swing"]) * 1.6, 0.0, 1.0)
			(am as Node3D).rotation.z = lerpf(deg_to_rad(12.0), deg_to_rad(-125.0), sw * sw * (3.0 - 2.0 * sw))
	if misfire:
		arc.visible = false                           # (no aim: the throws go anywhere)
	var rings: Dictionary = r["rings"]
	for x in rings:
		if int(x) < 0:
			continue
		var ring: MeshInstance3D = rings[x]
		var on := int(x) == tgt
		ring.visible = not gone and not sim.collapsed.get(int(x), false) and not misfire
		var rm := ring.material_override as StandardMaterial3D
		var dim := 1.0 if n["owner"] != "" else 0.45   # a neutral pad's aim: shown, quieter
		rm.albedo_color = Color(ac.r, ac.g, ac.b, ((0.95 if locked else 0.75) if on else 0.22) * dim)
		rm.emission_energy_multiplier = ((3.5 if locked else 2.0) if on else 0.6) * dim
		var pop := float(r["aim_pop"]) if on else 0.0
		ring.scale = Vector3.ONE * ((1.0 + 0.35 * pop + (0.06 * k2 if locked else 0.0)) if on else 0.55)
	var lab: Label3D = rings[-1]                      # yours: TARGET n / LOCKED; a rival's: ENEMY AIM / INCOMING; neutral: none
	var own: String = n["owner"]
	var mine := own != "" and (own == human or sim.allied(own, human))
	lab.visible = not gone and tgt >= 0 and own != ""
	if misfire:                                       # round 3: MISFIRE n over the pad itself
		lab.visible = not gone
		lab.position = (n["pos"] as Vector3) + Vector3(0, 7.5, 0)
		lab.text = "MISFIRE · %d" % int(ceil(float(n["relay_t"])))
		lab.modulate = red
		return
	if tgt >= 0:
		lab.position = (sim.nodes[tgt]["pos"] as Vector3) + Vector3(0, 7.5, 0)
		var left := sim.launcher_aim_left(id)
		if mine and armed:                           # LAUNCHER TURRET: what it has loaded, over the frozen target
			lab.text = "LOADING %d/%d" % [Rules.shown(Sim.launcher_loaded(n)), Rules.shown(Sim.launcher_load(n))]
			lab.modulate = Color.WHITE
		elif mine:
			lab.text = "LOCKED" if locked else ("TARGET" if left == INF else "TARGET · %d" % int(ceil(left)))
			lab.modulate = Color.WHITE if locked else ac
		else:
			lab.text = "INCOMING" if locked else "ENEMY AIM"
			lab.modulate = Rules.state_color("warn")
		_aim(r["pointer"], top, (sim.nodes[tgt]["pos"] as Vector3) - (n["pos"] as Vector3))
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), (sim.nodes[tgt]["pos"] as Vector3) - (n["pos"] as Vector3))


func _flight_stream() -> void:
	## Round 3: the blobs (up to 8 per throw, 0.05 s apart) stretch along the arc and spin, drop onto the target and
	## splash a ring there; a misfire's throws fly off the map along their random heading and fall away.
	var mm: MultiMesh = _flights.multimesh
	var smm: MultiMesh = _splash.multimesh
	var flight: float = float(Rules.RELAYS_PROTO["launcher"]["flight"])
	var k := 0
	var ks := 0
	for f in sim.flights:
		var from: Vector3 = sim.nodes[int(f["from"])]["pos"]
		var void_: bool = f.get("void", false)
		var hd := float(f.get("heading", 0.0))
		var away := Vector3(cos(hd), 0.0, sin(hd))
		var to: Vector3 = from + away * MISFIRE_FLING if void_ else sim.nodes[int(f["to"])]["pos"]
		var blobs := clampi(int(ceilf(Rules.shown(float(f["left"])))), 1, 8)
		var col := Rules.seat_color(str(f["seat"]))
		for b in range(blobs):
			if k >= FLIGHT_BLOBS:
				break
			var age := sim.time - float(f["t0"]) - b * 0.05
			if age < 0.0:
				continue
			var q := clampf(age / flight, 0.0, 1.0)
			var pos: Vector3
			var vel: Vector3
			if void_:                                 # out over the edge, then a long drop into the void
				pos = from.lerp(to, minf(age / flight, 1.6)) + Vector3(0, 6.0 * sin(minf(q, 1.0) * PI * 0.7) - 18.0 * maxf(age / flight - 0.6, 0.0) ** 2, 0)
				vel = (to - from).normalized() + Vector3(0, -maxf(age / flight - 0.6, 0.0) * 2.0, 0)
				if pos.y < from.y - 30.0:
					continue
			elif q < 1.0:
				pos = arc_point(from, to, q)
				vel = arc_point(from, to, minf(q + 0.02, 1.0)) - pos
			else:
				var d := clampf((age - flight) / 0.25, 0.0, 1.0)
				pos = to + Vector3(0, 1.0 + 2.0 * (1.0 - d), 0)
				vel = Vector3.DOWN
			var fwd := vel.normalized() if vel.length() > 0.001 else Vector3.UP
			var side := fwd.cross(Vector3.UP).normalized() if absf(fwd.y) < 0.99 else Vector3.RIGHT
			var up := side.cross(fwd).normalized()
			var spin := Basis(fwd, age * 9.0 + b)
			var basis := spin * Basis(side * 0.85, up * 0.85, fwd * 1.6)   # stretched along its flight
			mm.set_instance_transform(k, Transform3D(basis, pos))
			mm.set_instance_color(k, col)
			k += 1
		var since := sim.time - float(f["land"])
		if not void_ and since >= 0.0 and since < SPLASH and ks < SPLASHES:
			var g := since / SPLASH
			smm.set_instance_transform(ks, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0 + 2.2 * g, 1.0, 1.0 + 2.2 * g)), to + Vector3(0, 0.6, 0)))
			smm.set_instance_color(ks, Color(col.r, col.g, col.b, 0.85 * (1.0 - g)))
			ks += 1
	mm.visible_instance_count = k
	smm.visible_instance_count = ks


func _lift(n: Dictionary, r: Dictionary, top: Vector3, phase: String) -> void:
	## Round 2 (Daniele: "needs to be more visually clear"): the platform stands RELAYS_PROTO.lift.rise up on a piston at
	## level 1; the decks of the closed level sink LIFT_SINK, stand LIFT_GAP back and fade to LIFT_DIM, the open ones
	## carry a lit strip; an UP / DOWN badge over the node in the level's colour. All of it eases over the 1.4 s move.
	var id: int = n["id"]
	var level := float(int(n["relay_index"]))
	if phase == "moving":                             # relay_index is already the new level
		var p := smoothstep(0.0, 1.0, float(n["relay_anim"].get("progress", 0.0)))
		level = lerpf(1.0 - level, level, p)
	var rise: float = float(Rules.RELAYS_PROTO["lift"]["rise"]) * (level + float(sim.lift_base(id)))   # base -1: a lowered lift
	var gone: bool = sim.collapsed.get(id, false)
	if not gone:
		var base: Dictionary = r["base"]
		for part in base:
			if is_instance_valid(part):
				(part as Node3D).transform = (base[part] as Transform3D).translated(Vector3(0, rise, 0))
	var lp: Dictionary = r["lift"]
	var piston: MeshInstance3D = lp["piston"]
	piston.visible = not gone and rise > 0.05
	piston.scale = Vector3(1.0, maxf(rise + 1.2, 0.01), 1.0)
	piston.position = (n["pos"] as Vector3) + Vector3(0, (rise + 1.2) * 0.5 - 1.2, 0)
	var up := int(n["relay_index"]) == 1
	var lvl_col: Color = Rules.RELAY_GHOST_COLORS["lift"] if up else Rules.RELAY_GHOST_COLORS["ferry"]   # UP amber, DOWN cyan
	for ei in sim.controlled_edges(id):              # a closed level's deck: sunk, standing back, dimmed
		var strip: MeshInstance3D = lp["strips"][ei]
		if sim.collapsed.get(sim.edges[ei]["a"], false) or sim.collapsed.get(sim.edges[ei]["b"], false):
			strip.visible = false
			continue
		var open: bool = sim._edge_open_at(ei, int(n["relay_index"]))
		var away: Vector3 = ((sim.nodes[sim._other_end(ei, id)]["pos"] as Vector3) - (n["pos"] as Vector3)).normalized()
		var off := 0.0
		if phase == "moving":
			var p2 := smoothstep(0.0, 1.0, float(n["relay_anim"].get("progress", 0.0)))
			off = p2 if not open else 1.0 - p2
		elif not open:
			off = 1.0
		var shift := away * LIFT_GAP * off - Vector3(0, LIFT_SINK * off, 0)
		var ramp := _ramp(ei, id)                    # an UP deck: sheared into a ramp up to the raised platform
		var decks: Array = vis["edge_decks"][ei]
		for k in range(decks.size()):
			var d: Node3D = decks[k]
			d.visible = true
			d.transform = (ramp * (vis["edge_base"][ei][k] as Transform3D)).translated(shift)
			for gi in d.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).transparency = LIFT_DIM * off
		strip.visible = off < 0.99
		var dl: Array = sim.deck_line(ei)
		var mid: Vector3 = (dl[0] as Vector3).lerp(dl[-1], 0.5)
		strip.position.y = mid.y + 0.42 - LIFT_SINK * off
		var sm := strip.material_override as StandardMaterial3D
		sm.albedo_color = Color(lvl_col.r, lvl_col.g, lvl_col.b, 0.85 * (1.0 - off))
		sm.emission = lvl_col
		var deck_up: bool = int(sim.edges[ei]["lift_level"]) == 1    # round 3: this deck's own level, not the platform's
		var dcol: Color = Rules.RELAY_GHOST_COLORS["lift"] if deck_up else Rules.RELAY_GHOST_COLORS["ferry"]
		var tag: Label3D = lp["tags"][ei]
		tag.visible = true
		tag.position = mid + shift + Vector3(0, 0.55, 0)
		tag.rotation = Vector3(-PI / 2.0, Rules.view_yaw, 0.0)
		tag.modulate = Color(dcol.r, dcol.g, dcol.b, lerpf(1.0, 0.35, off))
		var ghost: MeshInstance3D = lp["ghosts"][ei]    # where a closed deck docks once the lift comes to its level
		ghost.visible = off > 0.05
		var gm := ghost.material_override as StandardMaterial3D
		var docking: bool = phase == "warning" and int(n["relay_pending"]) == int(sim.edges[ei]["lift_level"])
		gm.albedo_color = Color(dcol.r, dcol.g, dcol.b, 0.08 + 0.06 * off + (0.14 if docking else 0.0))
		gm.emission = dcol
		gm.emission_energy_multiplier = 1.6 if docking else 0.5
		var edge: MeshInstance3D = lp["edges"][ei]      # the deck's platform end, glowing while it moves
		edge.visible = phase == "moving"
		if phase == "moving":
			var near_end: Vector3 = dl[0] if (dl[0] as Vector3).distance_to(n["pos"]) < (dl[-1] as Vector3).distance_to(n["pos"]) else dl[-1]
			edge.position = near_end + shift + Vector3(0, 0.45, 0)
			_tint(edge, dcol.lightened(0.4))
			(edge.material_override as StandardMaterial3D).emission_energy_multiplier = 4.0
	var badge: Label3D = lp["badge"]
	badge.visible = not gone
	badge.position = top + Vector3(0, rise + 2.4, 0)
	badge.text = "▲ UP" if up else "▼ DOWN"
	badge.modulate = Color.WHITE if phase == "moving" else lvl_col
	_aim(r["pointer"], top + Vector3(0, rise, 0), Vector3.UP if up else Vector3.DOWN)
	_aim(r["ghost_pointer"], top + Vector3(0, rise + 0.8, 0), Vector3.UP if int(n["relay_pending"]) == 1 else Vector3.DOWN)
	_tint(r["pointer"], lvl_col)


func _along(a: Vector3, b: Vector3) -> Basis:
	## a box whose x runs a -> b (tilted when the ends stand at different heights)
	var x := (b - a).normalized()
	var z := x.cross(Vector3.UP).normalized()
	return Basis(x, z.cross(x), z)


func _ramp(ei: int, lift_id: int) -> Transform3D:
	## Daniele 2026-11-05 ("the lift node raises and dips but the bridges it connects are all at the same level"): a lift
	## deck's lift end docks at the lift's level (Sim._lift_end_y), its far end at its platform's level (round R levels,
	## 2026-11-06), so its flat baked pieces are sheared into the ramp between the pier ends - the line Sim.deck_points walks.
	var ends: Array = sim.ramp_ends(ei, lift_id)
	return MapBuilder.ramp_xf(ends[0], ends[1])


func _tilt(n: Dictionary, r: Dictionary, top: Vector3, phase: String, blink: bool, gone: bool) -> void:
	var id: int = n["id"]
	var next := sim.tilt_next_exit(id)
	var tipping: int = int(n.get("tilt_exit", next)) if phase == "moving" else next
	var c: Vector3 = n["pos"]
	var angle := 0.0
	var axis := Vector3.RIGHT
	if phase == "moving" and tipping >= 0:               # round 2: tipped for the whole hold, easing in and out
		var dir := ((sim.nodes[tipping]["pos"] as Vector3) - c).normalized()
		axis = Vector3.UP.cross(dir).normalized()
		var hold: float = float(n["relay_move"])
		var el: float = clampf(float(n["relay_anim"].get("progress", 0.0)), 0.0, 1.0) * hold
		angle = -TILT_TIP * clampf(el / TILT_EASE, 0.0, 1.0) * clampf((hold - el) / TILT_EASE, 0.0, 1.0)
	if not gone:
		var base: Dictionary = r["base"]
		for part in base:
			if is_instance_valid(part):
				var t: Transform3D = base[part]
				var rot := Basis(axis, angle)
				(part as Node3D).transform = Transform3D(rot * t.basis, c + rot * (t.origin - c))
	if r.has("v3") and not gone:                      # Relay_Tilt_v3: the Top tips about the platform centre (its
		var tt = r.get("top")                         # origin), the Dial's arrow points at the next exit
		if tt is Node3D:
			var rest: Transform3D = r["top_rest"]
			var rb := Basis(axis, angle)
			(tt as Node3D).transform = Transform3D(rb * rest.basis, rb * rest.origin)
		var dial = r.get("dial")
		if dial is Node3D and next >= 0:
			var want := Rules.heading(((sim.nodes[next]["pos"] as Vector3) - c) * Vector3(1, 0, 1))
			(dial as Node3D).rotation.y = lerp_angle((dial as Node3D).rotation.y, want, minf(1.0, _dt * 5.0))
	for x in r["strips"]:
		var mi: MeshInstance3D = r["strips"][x]
		var lit := int(x) == tipping
		mi.visible = not gone and lit
		var m := mi.material_override as StandardMaterial3D
		var bright := phase == "warning" and blink    # (held tipped: a steady strip under the running chevrons)
		m.albedo_color.a = 0.85 if bright else (0.45 if phase == "moving" else 0.35)
		m.emission_energy_multiplier = 3.0 if bright else (1.6 if phase == "moving" else 1.0)
	r["phase"] = float(r["phase"]) + _dt * CHEVRON_SPEED * 2.0
	for x in r["chev"]:                                  # round 2: chevrons run down the exit while it is tipped, and a
		var ch: Dictionary = r["chev"][x]                # big arrow across the platform toward it
		var on: bool = phase == "moving" and int(x) == tipping and not gone
		(ch["mmi"] as Node3D).visible = on
		var ar: Dictionary = r["arrow"][x]
		(ar["mmi"] as Node3D).visible = on
		if on:
			_run_chevrons(ch, float(r["phase"]), sim.edges[int(ch["edge"])]["a"] == id, 0.75)
			_run_chevrons(ar, float(r["phase"]) * 0.6, true, 1.6)
	if next >= 0:
		_aim(r["pointer"], top, (sim.nodes[next]["pos"] as Vector3) - c)
		var after: int = int(n["proto"]["exits"][int(n["relay_pending"]) % (n["proto"]["exits"] as Array).size()])
		_aim(r["ghost_pointer"], top + Vector3(0, 0.6, 0), (sim.nodes[after]["pos"] as Vector3) - c)


func _speed_tags() -> void:
	## (round 3: also +10 % / -10 % over a TILT-redirected line - its attack at the node it was sent to)
	## Conveyor: x2.25 (with the flow) / x0.3 (against) over every line with bodies on a belt (relay or plain).
	var seen := {}
	var cfg: Dictionary = Rules.RELAYS_PROTO["conveyor"]
	for h in sim.hordes:
		var sense: Array = sim.conveyor_sense(h)
		var tm := sim.tilt_mult(h, sim.nodes[int(h["target"])]) if h.has("tilt_by") else 1.0   # round 3: a TILT-redirected line
		if int(sense[0]) == 0 and is_equal_approx(tm, 1.0):
			continue
		var hid: int = h["id"]
		seen[hid] = true
		var l: Label3D = _tags.get(hid)
		if l == null:
			l = _label(64)
			_tags[hid] = l
		if not is_equal_approx(tm, 1.0):              # its attack at the node it was sent to: +10 % / -10 %
			l.text = "%+d %%" % int(roundf((tm - 1.0) * 100.0))
			l.modulate = Rules.state_color("cAB") if tm > 1.0 else Rules.state_color("warn")
		else:
			var with := int(sense[0]) > 0
			l.text = "x" + _num(float(cfg["with"] if with else cfg["against"]))
			l.modulate = Rules.state_color("cAB") if with else Rules.state_color("warn")
		l.position = (Sim.sample(h, h["s"])[0] as Vector3) + Vector3(0, 2.6, 0)
	for hid in _tags.keys():
		if not seen.has(hid):
			(_tags[hid] as Label3D).queue_free()
			_tags.erase(hid)


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.01))   # (round 3: x2.25)
