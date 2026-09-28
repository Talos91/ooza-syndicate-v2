class_name RelayView
extends Node3D
## RELAY V2 - the relay redo (Alpha 22; Skin Designer's build_relay_v2.py, approved by Daniele 2026-09-28: "they
## good" / "implement them (remember the tutorial gets touched too)"). Every number: Rules' RELAY V2 block, from
## Models/2.0/structures_2_1/relay_v2.json.
##  - BUTTON: one standard platform per relay (Relay_Button_<Kind>_v2) off the rim, in the middle of the widest gap
##    between the node's bridges; its "Button" empty is a second tap target for the relay node (main.gd RELAY V2
##    blocks; Daniele: "the tap target should be both the button or the whole node, as relays activate with double
##    tap anyway"): a double-tap on it or on the node fires the relay, a tap selects / inspects / sends from the node
##    as before. The node centre holds the structure. A gap under 51.9 deg moves the
##    pad out to CLEAR / sin(gap / 2) and stretches the child "Strut" back under the rim; "Glyph" faces the viewer.
##  - MECHANISM: Relay_Retract_v2 / Relay_Gate_<Kind>_v2 on the pier of every relay bridge (MapBuilder.build3).
##  - RELAY DECKS: Deck_<Kind>_v2 on relay bridges (flat decks; the maps have no raised relay deck).
##  - GHOSTS: Deck_Ghost_<Kind>_v2 (+ Pier_Ghost_v2 on a rotation's own pier) where the bridge WILL be - a deck that
##    is not there now and appears on the relay's next state (rotation's next heading, the switch's inactive
##    bridge, the remote target, the retract's extended length). This node shows them, live, every frame: pale
##    violet (never an owner / state colour), brighter while the relay's warning runs, hidden while the real deck
##    moves in, once it is there, or when an end has dropped. Never batched (MapBatch never sees them).
## Placement and hit testing are static helpers (main.gd, tests/phone_fit.gd, tests/test_maps4.gd use them).

const BUTTON := {"rotation": "Relay_Button_Rotation_v2", "retract": "Relay_Button_Retract_v2",
		"switch": "Relay_Button_Switch_v2", "remote": "Relay_Button_Remote_v2"}
const GATE := {"rotation": "Relay_Gate_Rotation_v2", "retract": "Relay_Retract_v2",
		"switch": "Relay_Gate_Switch_v2", "remote": "Relay_Gate_Remote_v2"}
const DECK := {"rotation": "Deck_Rotation_v2", "retract": "Deck_Retract_v2",
		"switch": "Deck_Switch_v2", "remote": "Deck_Remote_v2"}
const GHOST := {"rotation": "Deck_Ghost_Rotation_v2", "retract": "Deck_Ghost_Retract_v2",
		"switch": "Deck_Ghost_Switch_v2", "remote": "Deck_Ghost_Remote_v2"}
const PIER_GHOST := "Pier_Ghost_v2"
const STRUT_BASE := Rules.R - 0.5 - 0.1   # strut scale.x = dist - PAD_R - (R - 0.5) + 0.1 (json placement)
const GATE_LIFT := 0.012                  # m: a gate over a leaned pier sits this much above it (no z-fight)

var sim: Sim
var groups: Array = []                    # [{ctrl, edge, pieces: [Node3D], warm: bool}]
static var _mats := {}                    # "ghost" / "edge" / "ghost_w" / "edge_w" -> StandardMaterial3D (shared)


func setup(s: Sim) -> void:
	sim = s
	name = "RelayView"


# ------------------------------------------------------------------ placement (pure: sim geometry only)
static func edge_kind(e: Dictionary) -> String:
	## The relay kind a relay bridge belongs to ("" for a fixed deck).
	if e.get("retracts", false):
		return "retract"
	var st: String = e.get("state", "")
	return {"r": "rotation", "s": "switch", "m": "remote"}.get(st.substr(0, 1), "") if st != "" else ""


static func bridge_heading(sim: Sim, ei: int, id: int, r: float) -> float:
	## Angle (atan2(z, x) round node `id`) at which edge ei's deck centre line crosses the circle of radius r: where
	## the bridge actually is at the button's distance (a leaned pier leaves the rim at an angle).
	var line: Array = sim.deck_line(ei)
	if sim.edges[ei]["b"] == id:
		line.reverse()
	var c: Vector3 = sim.nodes[id]["pos"]
	if line.is_empty():
		var o: Vector3 = sim.nodes[sim._other_end(ei, id)]["pos"]
		return atan2(o.z - c.z, o.x - c.x)
	var q: Vector3 = line[-1]
	for k in range(1, line.size()):
		var a: Vector3 = line[k - 1] * Vector3(1, 0, 1)
		var b: Vector3 = line[k] * Vector3(1, 0, 1)
		var da := Vector2(a.x - c.x, a.z - c.z).length()
		var db := Vector2(b.x - c.x, b.z - c.z).length()
		if (da - r) * (db - r) <= 0.0:
			q = a.lerp(b, 0.0 if absf(db - da) < 1e-5 else clampf((r - da) / (db - da), 0.0, 1.0))
			break
	return atan2(q.z - c.z, q.x - c.x)


static func place(sim: Sim, id: int) -> Dictionary:
	## Where node `id`'s button goes: {"dir": Vector3, "dist": float, "gap": deg of the widest gap, "tight": bool,
	## "strut": Strut scale.x}. The middle of the widest gap between its bridge headings (every relay-controlled
	## bridge counts, open or not - a rotation's decks can stand on any of them); a gap under 2 x RELAY_MIN_SEP moves
	## the pad out until pad and bridges clear each other again (relay_v2.json "if_gap_is_smaller").
	var hs := []
	for link in sim.adj.get(id, []):
		if not sim.edges[link[1]].get("plaza", false):
			hs.append(bridge_heading(sim, int(link[1]), id, Rules.RELAY_RIM_DIST))
	var mid := PI / 2.0
	var gap := TAU
	if not hs.is_empty():
		hs.sort()
		gap = -1.0
		for i in range(hs.size()):
			var a0: float = hs[i]
			var a1: float = hs[(i + 1) % hs.size()] + (TAU if i == hs.size() - 1 else 0.0)
			if a1 - a0 > gap:
				gap = a1 - a0
				mid = (a0 + a1) / 2.0
	var tight := gap < 2.0 * deg_to_rad(Rules.RELAY_MIN_SEP)
	var dist := Rules.RELAY_RIM_DIST
	if tight:
		dist = maxf(dist, Rules.RELAY_BUTTON_CLEAR / maxf(sin(gap / 2.0), 0.05))
	return {"dir": Vector3(cos(mid), 0.0, sin(mid)), "dist": dist, "gap": rad_to_deg(gap), "tight": tight,
			"strut": dist - Rules.RELAY_PAD_R - STRUT_BASE}


static func gate_end(sim: Sim, ei: int) -> int:
	## The end (0 = a, 1 = b) of relay bridge ei that carries its mechanism: the controlling relay's own end, or for a
	## remote's far bridge the end nearer the remote. -1: not a relay bridge.
	var ctrl: int = sim.edge_controller.get(ei, -1)
	if ctrl < 0:
		return -1
	var e: Dictionary = sim.edges[ei]
	if e["a"] == ctrl:
		return 0
	if e["b"] == ctrl:
		return 1
	var c: Vector3 = sim.nodes[ctrl]["pos"]
	return 0 if (sim.nodes[e["a"]]["pos"] as Vector3).distance_to(c) <= (sim.nodes[e["b"]]["pos"] as Vector3).distance_to(c) else 1


static func put_button(parent: Node3D, sim: Sim, n: Dictionary) -> Dictionary:
	## Places node n's button; returns vis[id]["relay_button"]: {"node", "tap" (world pos of the Button empty),
	## "dir", "dist", "gap", "tight"}.
	var pl := place(sim, n["id"])
	var d: Vector3 = pl["dir"]
	var btn := MapBuilder.put(parent, BUTTON[n["relay"]], (n["pos"] as Vector3) + d * float(pl["dist"]), Rules.heading(d))
	var tap := (n["pos"] as Vector3) + d * float(pl["dist"]) + Vector3(0, Rules.RELAY_BUTTON_Y, 0)
	for c in btn.find_children("*", "Node3D", true, false):
		match String(c.name):
			"Glyph":
				(c as Node3D).rotation.y = Rules.view_yaw - btn.rotation.y   # square to the camera (every structure faces it)
			"Strut":
				(c as Node3D).scale.x = float(pl["strut"])
	if not btn.find_child("Button", true, false):
		push_warning("RELAY V2: %s has no Button empty" % BUTTON[n["relay"]])
	pl["node"] = btn
	pl["tap"] = _button_world(btn, tap)
	return pl


static func _button_world(btn: Node3D, fallback: Vector3) -> Vector3:
	## The Button empty's position in the piece's parent space (the map root: world), whatever its depth in the GLB.
	var b := btn.find_child("Button", true, false) as Node3D
	if b == null:
		return fallback
	var xf := Transform3D.IDENTITY
	var p: Node = b
	while p != null and p != btn:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return (btn.transform * xf).origin


# ------------------------------------------------------------------ ghosts
func add_ghosts(ctrl: int, ei: int, decks: Array, pier_xf) -> void:
	## A ghost of every module of relay bridge ei (same transform as the real deck) and, for a rotation's own
	## bridge, of its pier (pier_xf: the gate's Transform3D, or null).
	var kind := edge_kind(sim.edges[ei])
	if kind == "":
		return
	var pieces := []
	for dk in decks:
		var g := MapBuilder.put(self, GHOST[kind], Vector3.ZERO)
		g.transform = (dk as Node3D).transform
		pieces.append(g)
	if pier_xf is Transform3D:
		var pg := MapBuilder.put(self, PIER_GHOST, Vector3.ZERO)
		pg.transform = pier_xf
		pieces.append(pg)
	for g in pieces:
		_dress(g, false)
		(g as Node3D).visible = false
	groups.append({"ctrl": ctrl, "edge": ei, "pieces": pieces, "warm": false})


func has_ghost(ei: int) -> bool:
	## Does this node draw relay bridge ei's destination ghost (Fx then skips its own warning copy)?
	return groups.any(func(g): return int(g["edge"]) == ei)


static func _mat(key: String) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		var warm := key.ends_with("_w")
		var edge := key.begins_with("edge")
		var c: Color = Rules.RELAY_GHOST_EDGE if edge else Rules.RELAY_GHOST
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 1.0 if edge else Rules.RELAY_GHOST.a * (1.6 if warm else 1.0))
		if not edge:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = (1.4 if edge else 0.8) * (Rules.RELAY_GHOST_WARN if warm else 1.0)
		_mats[key] = m
	return _mats[key]


static func _dress(g: Node3D, warm: bool) -> void:
	## OS_Ghost / OS_Ghost_Edge -> the fixed pale violet (the GLB's own alpha is not trusted to survive import).
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in range(mesh.get_surface_count()):
			var src := mesh.surface_get_material(s)
			var nm := src.resource_name if src else ""
			var key := "edge" if nm.begins_with("OS_Ghost_Edge") else "ghost"
			(mi as MeshInstance3D).set_surface_override_material(s, _mat(key + ("_w" if warm else "")))


static func ghost_wanted(sim: Sim, ctrl: int, ei: int) -> bool:
	## Is relay bridge ei a destination right now: not there, and there on its relay's next state (the pending one
	## while the warning runs)? Never while it moves in, never for a deck Anchor / Aegis hold, never once an end fell.
	var e: Dictionary = sim.edges[ei]
	if sim.collapsed.get(e["a"], false) or sim.collapsed.get(e["b"], false) or sim.collapsed.get(ctrl, false):
		return false
	var n: Dictionary = sim.nodes[ctrl]
	if n["relay_phase"] == "moving" or sim.is_edge_open(ei) or sim.anchor_state(ei) != null:
		return false
	var cur: int = n["relay_index"]
	var nxt: int = n["relay_pending"] if n["relay_phase"] == "warning" else sim.relay_next_index(n)
	return nxt != cur and not sim._edge_open_at(ei, cur) and sim._edge_open_at(ei, nxt)


func _process(_dt: float) -> void:
	if sim == null:
		return
	for g in groups:
		var on := ghost_wanted(sim, int(g["ctrl"]), int(g["edge"]))
		var warm: bool = on and sim.nodes[int(g["ctrl"])]["relay_phase"] == "warning"
		if warm != bool(g["warm"]):
			g["warm"] = warm
			for p in g["pieces"]:
				_dress(p, warm)
		for p in g["pieces"]:
			if (p as Node3D).visible != on:
				(p as Node3D).visible = on


# ------------------------------------------------------------------ hit testing (main.gd, tests/phone_fit.gd)
static func hit_disc(cam: Camera3D, sim: Sim, vis: Dictionary, id: int, mobile: bool) -> Array:
	## The button's tap disc on screen: [centre px, radius px], or [] (no button / behind the camera): centred on the
	## pad, at least its projected radius x RELAY_HIT_PAD and on a phone at least RELAY_HIT_PT across (UiKit.pt_per_px).
	## It overlaps its own node's platform on a small map - both answer the same node, so that costs nothing.
	var b = vis.get(id, {}).get("relay_button")
	if not b is Dictionary or cam == null:
		return []
	var tap: Vector3 = b["tap"]
	if cam.is_position_behind(tap):
		return []
	var c := cam.unproject_position(tap)
	var r := cam.unproject_position(tap + cam.global_transform.basis.x * Rules.RELAY_PAD_R).distance_to(c) * Rules.RELAY_HIT_PAD
	if mobile:
		var vp := cam.get_viewport().get_visible_rect().size
		r = maxf(r, Rules.RELAY_HIT_PT * 0.5 / maxf(UiKit.pt_per_px(vp), 0.01))
	return [c, r]


static func button_at(cam: Camera3D, sim: Sim, vis: Dictionary, screen: Vector2, ground: Vector3, mobile: bool) -> int:
	## The relay whose button disc holds this screen point (the nearest disc centre wins), or -1. A point on another
	## node's platform (within R of its centre on the ground) stays that node's.
	var best := -1
	var best_d := INF
	for n in sim.nodes:
		if n["relay"] == "" or sim.collapsed.get(n["id"], false):
			continue
		var disc := hit_disc(cam, sim, vis, n["id"], mobile)
		if disc.is_empty():
			continue
		var dd := (disc[0] as Vector2).distance_to(screen)
		if dd <= float(disc[1]) and dd < best_d:
			best_d = dd
			best = n["id"]
	if best >= 0 and ground != Vector3.INF:
		for n in sim.nodes:
			if n["id"] != best and not sim.collapsed.get(n["id"], false) \
					and Vector2(ground.x - n["pos"].x, ground.z - n["pos"].z).length() <= Rules.R:
				return -1
	return best


static func button_screen(cam: Camera3D, vis: Dictionary, id: int) -> Array:
	## The pad on screen: [centre px, projected pad radius px], or [] (hud_overlay's ready glow and cue).
	var b = vis.get(id, {}).get("relay_button")
	if not b is Dictionary or cam == null or cam.is_position_behind(b["tap"]):
		return []
	var c := cam.unproject_position(b["tap"])
	return [c, cam.unproject_position((b["tap"] as Vector3) + cam.global_transform.basis.x * Rules.RELAY_PAD_R).distance_to(c)]
