class_name GooTerritory
extends Node3D
## GOO territory (Daniele, 0.18.7: "the lane fight chat did some try with goo instead of neons, can you
## try adding it so i can get the feel of it and add it as a toggle (could be a cosmetic later on)").
## Rules.goo_territory (OPTIONS and the pause menu, TERRITORY: NEON / GOO) swaps BRAWL's owner-colour
## neon (Fx: deck halves, pier stripes, platform rims) for goo in the owner's PLAYER colour, round 3 of
## Models/2.0/goo_readability (renders_r3 S1-S4, S9): a thick slab over every owned platform and over
## each deck half from an owned end (the half belongs to its end's owner, as the neon halves do), with a
## lumpy top, a rounded meniscus edge, drips hanging off the deck sides and the platform rim and a few
## bubbles; goo_territory.gdshader keeps the top dark and glows at grazing angles. Neutral platforms
## and halves stay plain. A capture spreads the new goo from the side the capturing line came in
## (SPREAD_SPEED m/s: across a platform in ~0.8 s and on down its decks), a lost node's goo recedes, a
## retracted / switched / turning deck drops its goo and it spreads back out when the deck returns, and
## the goo falls with its platform in the Last Stand (Fx._collapse). Units take their race colour with a
## player-colour rim in this mode (UnitView). SIEGE keeps its look: its hordes and rivers are goo in the
## player colour already, a goo floor under them would hide them (renders, 0.18.7).
## Pure view: no sim state, no net traffic. Every mesh is built once, procedurally, the first time the
## mode is on (no Blender bake, no remesh at runtime); only materials, visibility and one shader
## parameter per animating piece change afterwards. One shared material per colour.

const SHADER := preload("res://shaders/goo_territory.gdshader")
const PLAT_TOP := 0.06               # kit platform plate top (Platform_Standard)
const DECK_TOP := 0.10               # kit deck plate top (Deck_S)
const SINK := 0.03                   # the goo's edge dips this far under the plate: no seam shows
const THICK := 0.12                  # slab thickness (the experiment: 0.14 over a 0.04 sink)
const MENISCUS := 0.28               # metres over which the edge rounds up to full thickness
const LUMP := 0.02                   # lumpy top (Blender: clouds displace 0.05, then smoothed); none on phones
const PLAT_EDGE := 5.45              # goo outline radius on a platform (the experiment's 5.55 slab, less the blobs' reach)
const PLAT_RIM := 6.16               # the kit platform's outer edge
const LEDGE_EDGE := 4.4              # outline pulled in where a relay ledge or retract gate straddles the rim
const DECK_HW := 1.3                 # half width of the deck goo (2.7 of the 3.5 m deck, less the blobs' reach)
const DECK_SIDE := 1.74              # the kit deck's side
const MID_GAP := 0.1                 # each half stops this short of the deck's middle (neon halves: 0.15)
const INTO_PLATFORM := 0.9           # a deck half starts this far inside the platform, under its goo
const SPREAD_SPEED := 15.0           # m/s the takeover front travels
const BUBBLES := true                # dropped on phones and in LOW detail

var sim: Sim
var vis: Dictionary
var collapsed_edges: Dictionary      # Fx._collapsed (shared): edges whose decks have fallen
var built := false
var _on := false
var _plat := {}                      # node id -> piece
var _half := {}                      # edge -> [piece a, piece b] (null: no deck there)
var _steady := {}                    # colour html -> ShaderMaterial
var _phone := false
var _lump := LUMP
var _lumps := FastNoiseLite.new()
var _tone := FastNoiseLite.new()
# a piece: {"mi": MeshInstance3D, "anim": ShaderMaterial (its own, used only while animating),
#  "drawn": owner shown when idle ("" hidden), "target": owner wanted ("?" before the first frame),
#  "t": seconds into the animation (< 0 idle), "delay": metres the front starts behind its origin,
#  "reach": metres to cover, "recede": bool, "exit": Vector3 (deck halves: the rim exit, world)}


func setup(s: Sim, v: Dictionary, fx_collapsed: Dictionary, phone: bool) -> void:
	sim = s
	vis = v
	collapsed_edges = fx_collapsed
	_phone = phone
	_lumps.seed = 23
	_lumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lumps.frequency = 0.6
	_lump = 0.0 if phone else LUMP
	_tone.seed = 5
	_tone.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	_tone.frequency = 0.35
	_tone.fractal_octaves = 3


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	var on := Rules.goo_look()
	if on and not built:
		_build()
	if on != _on:                                     # switched (options, pause menu): snap, no animation
		_on = on
		for p in _pieces():
			p["target"] = "?"
			p["t"] = -1.0
			(p["mi"] as MeshInstance3D).visible = false
			p["drawn"] = ""
	if not on:
		return
	for id in _plat:
		if sim.collapsed.get(id, false):
			continue                                  # fallen with its platform (Fx._collapse)
		var p: Dictionary = _plat[id]
		var owner: String = sim.nodes[id]["owner"]
		if owner != p["target"]:
			var origin: Vector3 = sim.nodes[id]["pos"]
			if owner != "":
				origin = _entry_point(id, owner)
			_retarget(p, owner, origin, 0.0, PLAT_RIM * 2.0 + 1.0, false)
		_step(p, dt)
	for i in _half:
		if collapsed_edges.has(i):
			continue                                  # fallen with the deck
		var e: Dictionary = sim.edges[i]
		var open := sim.is_edge_open(i) and not _moving(i)
		for h in range(2):
			var p = _half[i][h]
			if p == null:
				continue
			var nid: int = e["a"] if h == 0 else e["b"]
			var owner: String = sim.nodes[nid]["owner"] if open else ""
			if owner != p["target"]:
				var delay := 0.0
				var pp: Dictionary = _plat.get(nid, {})
				if open and not pp.is_empty() and pp["t"] >= 0.0 and not pp["recede"] and pp["target"] == owner:
					delay = (pp["anim"] as ShaderMaterial).get_shader_parameter("origin").distance_to(p["exit"])
				_retarget(p, owner, p["exit"], delay, p["reach"], not open)
			_step(p, dt)


func _pieces() -> Array:
	var out := _plat.values()
	for i in _half:
		for p in _half[i]:
			if p != null:
				out.append(p)
	return out


func _moving(i: int) -> bool:
	var ctrl: int = sim.edge_controller.get(i, -1)
	return ctrl >= 0 and sim.nodes[ctrl]["relay_phase"] == "moving" and i in sim.nodes[ctrl]["moving_edges"]


func _entry_point(id: int, owner: String) -> Vector3:
	## Where the capturing line came in: the rim exit of the edge its route arrived by (the platform's
	## centre when no such line is on the map any more).
	for h in sim.hordes:
		if h["owner"] == owner and int(h["target"]) == id:
			var route: Array = h["route"]
			if route.size() >= 2:
				var ei := sim._edge_index(int(route[-2]), id)
				if ei >= 0 and not sim.edges[ei].get("plaza", false):
					return sim.exit_of(ei, id)
	return sim.nodes[id]["pos"]


func _retarget(p: Dictionary, owner: String, origin: Vector3, delay: float, reach: float, instant: bool) -> void:
	var mi: MeshInstance3D = p["mi"]
	var was: String = p["target"]
	p["target"] = owner
	if was == "?" or instant or (owner == "" and p["drawn"] == "" and p["t"] < 0.0):
		p["t"] = -1.0                                 # first frame, a deck going away: no animation
		p["drawn"] = owner
		mi.visible = owner != ""
		if owner != "":
			mi.material_override = _steady_for(owner)
		return
	var anim: ShaderMaterial = p["anim"]
	var from: String = p["drawn"] if p["t"] < 0.0 else str(p.get("to", p["drawn"]))
	if owner == "":                                   # lost: the goo recedes toward the rim exit / centre
		anim.set_shader_parameter("col_in", Rules.seat_color(from))
		anim.set_shader_parameter("has_in", 1.0)
		anim.set_shader_parameter("has_out", 0.0)
		p["recede"] = true
	else:                                             # taken (or the deck came back): the new goo spreads
		anim.set_shader_parameter("col_in", Rules.seat_color(owner))
		anim.set_shader_parameter("has_in", 1.0)
		anim.set_shader_parameter("col_out", Rules.seat_color(from) if from != "" else Color.BLACK)
		anim.set_shader_parameter("has_out", 1.0 if from != "" else 0.0)
		p["recede"] = false
	anim.set_shader_parameter("origin", origin)
	p["to"] = owner
	p["delay"] = delay
	p["reach"] = reach
	p["t"] = 0.0
	_set_front(p)
	mi.material_override = anim
	mi.visible = true


func _set_front(p: Dictionary) -> float:
	var run: float = SPREAD_SPEED * float(p["t"])
	var f: float = (float(p["reach"]) - run) if p["recede"] else (run - float(p["delay"]))
	(p["anim"] as ShaderMaterial).set_shader_parameter("front", f)
	return f


func _step(p: Dictionary, dt: float) -> void:
	if p["t"] < 0.0:
		return
	p["t"] += dt
	var f := _set_front(p)
	var done: bool = f <= 0.0 if p["recede"] else f >= float(p["reach"])
	if not done:
		return
	p["t"] = -1.0
	p["drawn"] = p["target"]
	var mi: MeshInstance3D = p["mi"]
	mi.visible = p["drawn"] != ""
	if mi.visible:
		mi.material_override = _steady_for(p["drawn"])


func _steady_for(owner: String) -> ShaderMaterial:
	var c: Color = Rules.seat_color(owner)
	var key := c.to_html()
	if not _steady.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("col_in", c)
		_steady[key] = m
	return _steady[key]


func falling(node_id: int) -> Array:
	## Fx._collapse: the goo that drops with this node - its platform's and both halves of every deck
	## it still had (call after Fx has marked those edges collapsed). They are left alone afterwards.
	## The platform's goo rides on the platform itself (reparented, same tumble); the deck halves'
	## goo falls as its own sheets beside the deck fragments.
	var out := []
	var pf = vis[node_id]["platform"] if vis.has(node_id) else null
	if _plat.has(node_id) and (_plat[node_id]["mi"] as MeshInstance3D).visible:
		var mi: MeshInstance3D = _plat[node_id]["mi"]
		if pf != null and is_instance_valid(pf):
			mi.reparent(pf as Node3D, true)
		else:
			out.append(mi)
	for link in sim.adj.get(node_id, []):
		var i: int = link[1]
		if not _half.has(i) or not collapsed_edges.has(i):
			continue
		for p in _half[i]:
			if p != null and (p["mi"] as MeshInstance3D).visible:
				out.append(p["mi"])
	return out


# ------------------------------------------------------------------ build (once)
func _build() -> void:
	built = true
	var bubbles := BUBBLES and not _phone and not Rules.low_detail
	for n in sim.nodes:
		var id: int = n["id"]
		if n["plaza"] >= 0 or vis[id]["platform"] == null:
			continue                                  # a plaza socket has no platform of its own
		_plat[id] = _piece(_platform_mesh(n, bubbles), n["pos"])
	for i in range(sim.edges.size()):
		var e: Dictionary = sim.edges[i]
		var line: Array = sim.deck_line(i)
		if line.size() < 4:
			continue
		var deck: Array = line.slice(1, line.size() - 1)
		var total := 0.0
		for k in range(1, deck.size()):
			total += (deck[k] as Vector3).distance_to(deck[k - 1])
		if total <= 2.0 * MID_GAP + 0.1:
			continue
		var halves := [null, null]
		for h in range(2):
			var nid: int = e["a"] if h == 0 else e["b"]
			var ends: Array = line.duplicate()
			if h == 1:
				ends.reverse()
			var start: Array = []
			var n: Dictionary = sim.nodes[nid]
			var into: bool = n["plaza"] < 0 and vis[nid]["platform"] != null
			if into:
				var inward: Vector3 = ((n["pos"] as Vector3) - (ends[0] as Vector3)) * Vector3(1, 0, 1)
				start = [(ends[0] as Vector3) + inward.normalized() * INTO_PLATFORM]
			var pts: Array = start + [ends[0]]
			var pier_at := _poly_len(pts)             # arc length where the deck proper starts
			var run := 0.0
			var want := total / 2.0 - MID_GAP
			pts.append(ends[1])
			for k in range(2, ends.size() - 1):
				var seg: float = (ends[k] as Vector3).distance_to(ends[k - 1])
				if run + seg >= want:
					pts.append((ends[k - 1] as Vector3).lerp(ends[k], (want - run) / seg))
					break
				run += seg
				pts.append(ends[k])
			var built_mesh := _deck_mesh(pts, pier_at, into, i * 2 + h, bubbles)
			var p := _piece(built_mesh[0], built_mesh[1])
			p["exit"] = ends[0]
			p["reach"] = _poly_len(pts) + 2.0
			halves[h] = p
		_half[i] = halves


func _piece(mesh: ArrayMesh, at: Vector3) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.visible = false
	add_child(mi)
	var anim := ShaderMaterial.new()
	anim.shader = SHADER
	return {"mi": mi, "anim": anim, "drawn": "", "target": "?", "t": -1.0, "delay": 0.0, "reach": 1.0,
			"recede": false, "exit": at}


static func _poly_len(pts: Array) -> float:
	var s := 0.0
	for k in range(1, pts.size()):
		s += (pts[k] as Vector3).distance_to(pts[k - 1])
	return s


static func _prof(d: float) -> float:
	## The meniscus: a quarter round from the edge (d = 0) to full thickness MENISCUS in.
	var k := 1.0 - clampf(d / MENISCUS, 0.0, 1.0)
	return sqrt(maxf(1.0 - k * k, 0.0))


func _tone_at(w: Vector3) -> Color:
	return Color(clampf(_tone.get_noise_2d(w.x, w.z) * 0.5 + 0.5, 0.0, 1.0), 0.0, 0.0)


static func _blob_reach(off: float, centre: float, radius: float, s: float) -> float:
	## How far out (from the axis) a blob of `radius` at `centre` out and `s` along reaches at `off` along.
	var q := off - s
	if absf(q) >= radius:
		return -1.0
	return centre + sqrt(radius * radius - q * q)


func _platform_mesh(n: Dictionary, bubbles: bool) -> ArrayMesh:
	## One slab over the platform (local to its centre): a polar grid out to a wobbly outline, the
	## meniscus round its edge, blobs along the outline except at the pier mouths and relay ledges,
	## drips over the rim and a few bubbles.
	var id: int = n["id"]
	var c: Vector3 = n["pos"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + id * 7919
	var mouths := []                                  # [angle, half angle]
	var ledges := []
	for link in sim.adj.get(id, []):
		var ei: int = link[1]
		if sim.edges[ei].get("plaza", false):
			continue
		var ex := sim.exit_of(ei, id)
		mouths.append([atan2(ex.z - c.z, ex.x - c.x), 0.36])
	for p in vis[id]["parts"]:
		if not is_instance_valid(p):
			continue
		var path := (p as Node).scene_file_path
		if path.ends_with("/Relay_Mount.glb") or path.ends_with("/Relay_Retract.glb"):
			var ax: Vector3 = (p as Node3D).transform.basis.x
			ledges.append([atan2(ax.z, ax.x), 0.5])
	var clear := func(a: float, pad: float) -> bool:
		for m in mouths + ledges:
			if absf(wrapf(a - float(m[0]), -PI, PI)) < float(m[1]) + pad:
				return false
		return true
	var blobs := []                                   # [angle, centre radius, blob radius]
	for k in range(26):
		var a := rng.randf() * TAU
		if clear.call(a, 0.0):
			blobs.append([a, rng.randf_range(5.3, 5.75), rng.randf_range(0.3, 0.55)])
	var drips := []                                   # [angle, length]
	for k in range(7):
		var a := rng.randf() * TAU
		if clear.call(a, 0.1) and drips.all(func(d): return absf(wrapf(a - float(d[0]), -PI, PI)) > 0.35):
			drips.append([a, rng.randf_range(0.5, 1.3)])
			blobs.append([a, 6.0, 0.5])               # the tongue of goo the drip hangs from
	var sectors := 96 if _phone else 192
	var rings: Array = [0.07, 0.14, 0.21, 0.28, 0.35, 0.42, 0.49, 0.56, 0.62, 0.68, 0.74, 0.79, 0.84, 0.88, 0.92,
			0.95, 0.97, 0.985, 0.995, 1.0]           # ~0.35 m apart inside (the lumps), dense at the meniscus
	if _phone:
		rings = [0.2, 0.4, 0.58, 0.72, 0.83, 0.9, 0.95, 0.98, 1.0]   # no lumps on phones: the meniscus only
	var outline := PackedFloat32Array()
	for k in range(sectors):
		var a := TAU * k / sectors
		var r := PLAT_EDGE + 0.1 * _lumps.get_noise_2d(cos(a) * 3.0 + id * 11.0, sin(a) * 3.0)
		for b in blobs:
			var da := wrapf(a - float(b[0]), -PI, PI)
			if absf(da) < 0.5:
				r = maxf(r, _blob_reach(float(b[1]) * sin(da), 0.0, float(b[2]), 0.0) + float(b[1]) * cos(da))
		for m in ledges:
			var dl := absf(wrapf(a - float(m[0]), -PI, PI))
			if dl < float(m[1]) + 0.12:
				r = lerpf(r, LEDGE_EDGE, smoothstep(float(m[1]) + 0.12, float(m[1]), dl))
		outline.append(minf(r, PLAT_RIM + 0.22))
	outline = _smooth(outline, true, 3)               # round lobes, not teeth (Blender: remesh + smooth)
	var verts := PackedVector3Array()
	var tones := PackedColorArray()
	var idx := PackedInt32Array()
	var height := func(x: float, z: float, d: float) -> float:
		return PLAT_TOP - SINK + THICK * _prof(d) + _lump * _lumps.get_noise_2d(c.x + x, c.z + z) * smoothstep(0.0, 0.8, d)
	verts.append(Vector3(0.0, height.call(0.0, 0.0, 99.0), 0.0))
	for k in range(sectors):
		var a := TAU * k / sectors
		for t in rings:
			var r: float = float(t) * outline[k]
			var x := cos(a) * r
			var z := sin(a) * r
			verts.append(Vector3(x, height.call(x, z, outline[k] - r), z))
	var nr: int = rings.size()
	var at := func(k: int, j: int) -> int:           # j = 0 is the centre, 1..nr the rings
		return 0 if j == 0 else 1 + posmod(k, sectors) * nr + (j - 1)
	for k in range(sectors):
		idx.append_array([0, at.call(k, 1), at.call(k + 1, 1)])
		for j in range(1, nr):
			var a: int = at.call(k, j)
			var b: int = at.call(k + 1, j)
			var cc: int = at.call(k + 1, j + 1)
			var d: int = at.call(k, j + 1)
			idx.append_array([a, d, b, b, d, cc])
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms[0] = Vector3.UP
	for k in range(sectors):
		for j in range(1, nr + 1):
			var tan: Vector3 = verts[at.call(k + 1, j)] - verts[at.call(k - 1, j)]
			var rad: Vector3 = verts[at.call(k, mini(j + 1, nr))] - verts[at.call(k, j - 1)]
			var nn := tan.cross(rad).normalized()
			norms[at.call(k, j)] = nn if nn.y > -0.2 else Vector3.UP
	for v in verts:
		tones.append(_tone_at(c + v))
	for dr in drips:
		var a: float = dr[0]
		var axis := Vector3(cos(a), 0.0, sin(a)) * (PLAT_RIM + 0.06)   # just outside the rim's side
		_drip(verts, norms, tones, idx, axis + Vector3(0.0, PLAT_TOP, 0.0), float(dr[1]), rng, c)
	if bubbles:
		for k in range(10):
			var a := rng.randf() * TAU
			var r := rng.randf_range(2.2, 5.0)
			var x := cos(a) * r
			var z := sin(a) * r
			var sec := int(round(a / TAU * sectors)) % sectors
			var y: float = height.call(x, z, outline[sec] - r)
			_bubble(verts, norms, tones, idx, Vector3(x, y - 0.01, z), rng.randf_range(0.05, 0.14), c)
	return _commit(verts, norms, tones, idx)


func _deck_mesh(pts: Array, pier_at: float, into: bool, key: int, bubbles: bool) -> Array:
	## One deck half's goo along its centre line (world points, from inside the platform over the pier
	## to just short of the deck's middle): a strip with wobbly sides, blobs, a rounded tongue at the
	## middle end, drips over the deck sides. Returns [mesh, origin] (vertices local to the midpoint).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + key * 104729
	var line := Fx._polyline(pts)
	var total: float = line[1][-1]
	var step := 0.4 if _phone else 0.2
	var rows := maxi(2, int(ceil(total / step)))
	var cols: Array = [-1.0, -0.99, -0.96, -0.9, -0.8, -0.62, -0.35, 0.0, 0.35, 0.62, 0.8, 0.9, 0.96, 0.99, 1.0]
	if _phone:
		cols = [-1.0, -0.97, -0.88, -0.65, 0.0, 0.65, 0.88, 0.97, 1.0]
	var deck_from := pier_at + 0.4                    # blobs and drips on the deck proper only
	var side_blobs := [[], []]                        # per side: [s, centre, radius]
	var drips := []                                   # [s, side sign, length]
	for sd in range(2):
		var s := deck_from + rng.randf_range(0.0, 0.6)
		while s < total - 0.6:
			side_blobs[sd].append([s, rng.randf_range(1.15, 1.45), rng.randf_range(0.25, 0.45)])
			s += rng.randf_range(0.5, 1.1)
	var s_drip := deck_from + rng.randf_range(0.3, 1.5)
	while s_drip < total - 1.0:
		var sd := rng.randi() % 2
		drips.append([s_drip, 1.0 if sd == 1 else -1.0, rng.randf_range(0.4, 1.1)])
		side_blobs[sd].append([s_drip, DECK_SIDE - 0.2, 0.42])
		s_drip += rng.randf_range(2.5, 4.0)
	var mid: Vector3 = Fx._along(line, 0.5)[0]
	var verts := PackedVector3Array()
	var tones := PackedColorArray()
	var idx := PackedInt32Array()
	var nc: int = cols.size()
	var widths := [PackedFloat32Array(), PackedFloat32Array()]   # per side, per row, before the taper
	for sd in range(2):
		for r in range(rows + 1):
			var s := total * r / rows
			var w: float = DECK_HW + 0.07 * _lumps.get_noise_2d(s * 1.3, float(key * 2 + sd) * 17.0)
			for b in side_blobs[sd]:
				w = maxf(w, _blob_reach(s, float(b[1]), float(b[2]), float(b[0])))
			widths[sd].append(minf(w, DECK_SIDE + 0.14))
		widths[sd] = _smooth(widths[sd], false, 3)
	for r in range(rows + 1):
		var s := total * r / rows
		var at: Array = Fx._along(line, s / total)
		var p: Vector3 = at[0]
		var fwd: Vector3 = (at[1] as Vector3) * Vector3(1, 0, 1)
		var side := fwd.normalized().cross(Vector3.UP).normalized()
		var base := lerpf(PLAT_TOP, DECK_TOP, smoothstep(pier_at - 0.3, pier_at + 0.3, s)) - SINK
		var thick := THICK * (lerpf(0.5, 1.0, clampf(s / INTO_PLATFORM, 0.0, 1.0)) if into else 1.0)
		var taper := sqrt(clampf((total - s) / 0.5, 0.0, 1.0))   # the rounded tongue at the middle end
		var hw := [widths[0][r] * taper, widths[1][r] * taper]
		for v in cols:
			var sd := 1 if float(v) > 0.0 else 0
			var lat: float = float(v) * float(hw[sd])
			var d: float = float(hw[sd]) * (1.0 - absf(float(v)))
			var w: Vector3 = p + side * lat
			var y: float = base + thick * _prof(d) + _lump * _lumps.get_noise_2d(w.x, w.z) * smoothstep(0.0, 0.6, d)
			verts.append(Vector3(w.x, p.y + y, w.z) - mid)
	for r in range(rows):
		for q in range(nc - 1):
			var a := r * nc + q
			var b := a + 1
			var d := a + nc
			var cc := d + 1
			idx.append_array([a, d, b, b, d, cc])
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for r in range(rows + 1):
		for q in range(nc):
			var along: Vector3 = verts[mini(r + 1, rows) * nc + q] - verts[maxi(r - 1, 0) * nc + q]
			var across: Vector3 = verts[r * nc + mini(q + 1, nc - 1)] - verts[r * nc + maxi(q - 1, 0)]
			var nn := across.cross(along).normalized()
			norms[r * nc + q] = nn if nn.length() > 0.5 and nn.y > -0.2 else Vector3.UP
	for v in verts:
		tones.append(_tone_at(mid + v))
	for dr in drips:
		var at: Array = Fx._along(line, float(dr[0]) / total)
		var p: Vector3 = at[0]
		var side := ((at[1] as Vector3) * Vector3(1, 0, 1)).normalized().cross(Vector3.UP).normalized()
		_drip(verts, norms, tones, idx, p + side * float(dr[1]) * (DECK_SIDE + 0.08) + Vector3(0.0, DECK_TOP, 0.0) - mid,
				float(dr[2]), rng, mid)
	if bubbles:
		for k in range(int(total / 3.0)):
			var s := rng.randf_range(0.8, maxf(total - 1.0, 0.9))
			var at: Array = Fx._along(line, s / total)
			var side := ((at[1] as Vector3) * Vector3(1, 0, 1)).normalized().cross(Vector3.UP).normalized()
			var p: Vector3 = (at[0] as Vector3) + side * rng.randf_range(-0.9, 0.9)
			var base := lerpf(PLAT_TOP, DECK_TOP, smoothstep(pier_at - 0.3, pier_at + 0.3, s)) - SINK
			_bubble(verts, norms, tones, idx, p + Vector3(0.0, base + THICK - 0.01, 0.0) - mid, rng.randf_range(0.05, 0.12), mid)
	return [_commit(verts, norms, tones, idx), mid]


func _drip(verts: PackedVector3Array, norms: PackedVector3Array, tones: PackedColorArray, idx: PackedInt32Array,
		top: Vector3, length: float, rng: RandomNumberGenerator, origin: Vector3) -> void:
	## A drip hanging over an edge: a neck from the slab down to a tear-drop end, `length` m long.
	var rb := rng.randf_range(0.2, 0.28)
	var yb := -length + rb
	var prof := [[0.08, 0.26], [0.0, 0.22], [yb * 0.4, 0.15], [yb * 0.75, 0.12], [yb, rb],
			[yb - rb * 0.5, rb * 0.87], [yb - rb * 0.85, rb * 0.52], [yb - rb, 0.0]]
	_revolve(verts, norms, tones, idx, top, prof, 7 if _phone else 10, origin)


func _bubble(verts: PackedVector3Array, norms: PackedVector3Array, tones: PackedColorArray, idx: PackedInt32Array,
		at: Vector3, radius: float, origin: Vector3) -> void:
	var h := radius * 0.7
	var prof := [[h, 0.0], [h * 0.87, radius * 0.5], [h * 0.5, radius * 0.87], [0.0, radius]]
	_revolve(verts, norms, tones, idx, at, prof, 8, origin)


func _revolve(verts: PackedVector3Array, norms: PackedVector3Array, tones: PackedColorArray, idx: PackedInt32Array,
		at: Vector3, prof: Array, segs: int, origin: Vector3) -> void:
	## A surface of revolution about the vertical through `at` (local), profile [[y, radius]] top to bottom.
	var first := verts.size()
	var n := prof.size()
	for i in range(n):
		var y0: float = prof[maxi(i - 1, 0)][0]
		var y1: float = prof[mini(i + 1, n - 1)][0]
		var r0: float = prof[maxi(i - 1, 0)][1]
		var r1: float = prof[mini(i + 1, n - 1)][1]
		var nrm := Vector2(-(y1 - y0), r1 - r0).normalized()   # (radial, up), outward
		for s in range(segs):
			var a := TAU * s / segs
			var dir := Vector3(cos(a), 0.0, sin(a))
			verts.append(at + dir * float(prof[i][1]) + Vector3(0.0, float(prof[i][0]), 0.0))
			norms.append((dir * nrm.x + Vector3(0.0, nrm.y, 0.0)).normalized())
			tones.append(_tone_at(origin + at))
	for i in range(n - 1):
		for s in range(segs):
			var a := first + i * segs + s
			var b := first + i * segs + (s + 1) % segs
			var d := first + (i + 1) * segs + s
			var cc := first + (i + 1) * segs + (s + 1) % segs
			idx.append_array([a, d, b, b, d, cc])


static func _smooth(a: PackedFloat32Array, closed: bool, passes: int) -> PackedFloat32Array:
	## [1 2 1] / 4 passes over an outline (closed: it wraps round).
	var n := a.size()
	for k in range(passes):
		var b := a.duplicate()
		for i in range(n):
			var lo := posmod(i - 1, n) if closed else maxi(i - 1, 0)
			var hi := posmod(i + 1, n) if closed else mini(i + 1, n - 1)
			b[i] = 0.25 * a[lo] + 0.5 * a[i] + 0.25 * a[hi]
		a = b
	return a


static func _commit(verts: PackedVector3Array, norms: PackedVector3Array, tones: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = tones
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
