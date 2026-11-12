class_name WorldLayer
extends Node3D
## WORLD LAYER (Daniele, 2026-11-06: "background we have a setting with an actual floor, when units fall down they
## splat on the floor underneath and return to tubes that send unit up from below ... those columns should be tubes
## pumping goo up to our vats ... when they enter an enemy vat they invade the tube on that node until conquering ...
## turning into goo of that color pushing the other one down (or simply conquering it if neutral) ... crawl to the
## nearest tube (in form of goo not as units) here they enter and up the tube they go (just visual effect)").
## Spec: Docs/Game Design/Ooze Syndicate 2.0/05 Handoff/WORLD-LAYER-2026-11.md. PLACEHOLDER art (primitives +
## shaders) until the kit pieces from world-layer/WORLD-PROMPTS.md are built.
## VIEW ONLY: reads sim.nodes (owner, units, siege), sim.collapsed and the "fall" / "fling" fx events. It never
## writes to the Sim and adds nothing to the protocol - a guest draws the same from the host's snapshots and events.
##  - the floor: a plane FLOOR_DEPTH under the lowest node, dark plates, hazed and faded out at the edges;
## Daniele's answers (2026-11-06, OPEN-QUESTIONS): the floor varies per map - street / factory / sewer / lab; NO tubes on
## relays; drifting fog / clouds separate the arena from the floor; goo crawls to the nearest tube and an ENEMY tube's
## door lasers it (a background detail).
##  - a tube per node platform (not relays / junctions / plazas), from under the platform to the floor: goo flows up in the
##    owner's colour; a siege pushes the attacker's colour down from the top (share of the fight); a capture pushes
##    the old colour out of the bottom (neutral: it pushes out the gray native goo); a dropped node's tube drains and sinks;
##  - falls: a splat where the bodies land + droplets, then goo blobs crawl to the nearest tube and ride up inside it.
## Budget (phones): one draw per tube, one floor, three MultiMeshes (blobs, droplets, splats) with fixed pools;
## a 100+ unit fall makes at most SPLATS_PER_FALL splats and CRAWL_PER_FALL blobs, the oldest are recycled.

const SHADER_FLOOR := preload("res://shaders/world_floor.gdshader")
const FLOORS_V2 := "res://assets/world/floors_v2/"   # R3A-2 geometry tiles: <kind>-base-v2.png, -variant-B..E-v2.png, crust
const SHADER_TUBE := preload("res://shaders/world_tube.gdshader")
const SHADER_GOO := preload("res://shaders/world_goo.gdshader")
const SHADER_SPLAT := preload("res://shaders/world_splat.gdshader")
const SHADER_SOCKET := preload("res://shaders/world_socket.gdshader")
const SHADER_ENTRANCE := preload("res://shaders/world_entrance.gdshader")
# TUBE ENTRANCE v1 (Models/2.0/world-1.0/build_tube_entrance.py): collar + foot housing + the Locals' door (+Z, toward
# the camera) + lens + drains, for the r 0.95 tube; it replaces the flat socket ring there. Pillar sleeves (r 2.6) keep it.
# TUBE ENTRANCE v2 (build_tube_entrance_v2.py, 704 tris): the same foot with FOUR doors (+Z, +X, -Z, -X) so the Locals
# walk to the door nearest their crater (world_locals.gd); v1 (one door, 536 tris) stays in assets for comparison.
const ENTRANCE_GLB := "res://assets/world/tube_entrance_v2.glb"
# PITS / TUBES (Daniele 2026-11-07, 05 Handoff/PITS-TUBES-2026-11.md): v2 and the per-tier v3 doors are superseded by ONE
# column base for every tier - 4 corner tube sockets + 4 cardinal doors with a double laser (WorldTubes.column_base_mesh);
# the transport tubes from the sockets to the pits are world_tubes.gd. The GLBs stay in assets for comparison.
const LAB_PIC := "res://assets/world/lab_clean_floor_rect.png"   # --floor=labpic: Daniele's painted lab floor, top-down
const LAB_PIC_SIZE := Vector2(53.785, 40.744)    # metres (rectify_lab_clean_floor.py: 20 px/m, 1075 x 814)
const LAB_PIC_GRID0 := Vector2(0.892, 0.375)     # metres from its top-left corner to its first 2 m grid line (x, z)
const LAB_PIC_HAZE := 0.035                      # the picture is already dark: much less floor haze than the tiles
const LAB_PIC_MIST := 0.5                        # and a thinner fog sheet between arena and floor (still on) so it reads
const LAB_PIC_GAIN := 1.8                        # x brightness: at 1.0 the picture (mean #20262F) vanishes under the
                                                 # arena's fog at the game camera; 1.8 lets its arcs, patches and grid read
const LAB_PIC_MIRROR := true                     # mirror-repeat it over the floor (false: fade its edge into its mean colour)
# WORLD PASS 2 (director round 5, 2026-11-07): the LAB biome's default floor is R5-lab-floor (a seamless 32 x 32 m tile,
# mean #343C4A), the side backdrop LAB-SIDE-B-MACHINERY (--lab-side=a: A-CALM), the floor decals from one atlas
# (world_decals.gd). --floor=lab5 forces it on any map; --floor=labpic keeps the rectified picture, --floor-v1 the
# procedural placeholder.
const LAB5_FLOOR := "res://assets/world/lab5_floor_2048_flush.png"   # FLUSH slabs (Daniele 2026-11-07: one continuous
                                                 # pavement; tools/floor_flush.py, 1 px seam 5 % darker); --floor-grout: the original
const LAB5_FLOOR_GROUT := "res://assets/world/lab5_floor_2048.png"
const LAB5_TILE_M := 32.0
const LAB5_HAZE := 0.03                          # already mid-gray: a touch of floor haze only
const LAB5_MIST := 0.45                          # the fog sheet between arena and floor, x its density
const LAB5_GAIN := 1.0
const LAB5_FOG_HEIGHT_DENSITY := 0.035           # the scene's height fog under the decks (Scenery 0.24): the falling
                                                 # bodies stay visible down to the floor (F2) instead of fogging out at -10 m
# the floor's far haze and the backdrop's middle meet in this colour (round 5: backdrop middle ~#2B3443, floor #333C4A)
const LAB_FAR := Color(0.168, 0.204, 0.263)
# WORLD FOG (Daniele 2026-11-11: "the tubes in the background are a bit too distracting, increase the fog between the play
# area and the background"; then: "one layer of clouds roaming the map at 0.9 and a fog underneath drifting at 0.6, where
# they overlap it completely covers"). Two noise layers over the lab side backdrop (lab_backdrop.gdshader cloud_amt / fog_amt,
# set in WorldDressing._backdrop): 0 = absent, 1 = fully opaque where present. A 2D layer behind the 3D scene: playfield,
# units, goo and HUD are untouched. Strengths are [cloud, fog]; the default is mid. Dev: --backdrop-fog=<low|mid|high>.
const BACKDROP_FOG_LEVELS := {"low": [0.6, 0.4], "mid": [0.4, 0.4], "high": [1.0, 0.8]}
const BACKDROP_FOG := "mid"
const BACKDROP_DENSITY := [0.3, 0.55]   # [cloud, fog] how much of each layer is present (0 sparse .. 1 solid); --fog-density=<c>,<f>
const CLOUD_TONE := 0.08         # how much lighter than the far lab colour the clouds are (was 0.3: too white, Daniele 2026-11-11)
const TUBE_GOO_DIM := 0.6        # transport-tube goo brightness: 1 = as before, 0 = black
const CENTRE_LEVELS := [0.35, 0.45]   # Daniele 2026-11-11 (playground sliders): the centre plane's [cloud, fog] amounts
const CENTRE_FOG := 1.0          # x CENTRE_LEVELS for the plane between decks and floor that covers the CENTRE
                                 # (0 = off, 1 = same numbers as the sides). Off by default: it hazes the floor under the goo falls.
var center_fog_mat: ShaderMaterial   # set by WorldDressing._backdrop; FogLead tints its fog colour
const LAB_SIDE := "res://assets/art/backdrops/lab-side-%s-%d.jpg"   # a / b, 1184 (phone, 2.16:1) or 1440 (16:9)

const FLOOR_DEPTH := 16.0        # metres under the lowest node (decks sit at 0 / -4: the floor at -16 / -20)
const TUBE_R := 0.95             # a common platform's tube, under its machinery core
const TUBE_R_PILLAR := 2.6       # a pillar node: a glass sleeve around the column
const TUBE_TOP := -3.5           # under the platform centre (legs and core end at -3.6)
const TUBE_TOP_PILLAR := -2.3    # under the pillar's collar
const PUSH_T := 1.6              # s: a capture pushes the old colour out of the tube
const INV_MAX := 0.6             # a siege fills at most this share of the tube from the top
const INV_RATE := 0.8            # tube share per second the invader band moves
const LAND_DROP := 26.0          # Fx.FLING_DROP: the bodies drop this far over FALL_S (ease-in)
const FALL_S := 1.4
const SPLATS_PER_FALL := 3
const CRAWL_PER_FALL := 6        # blobs per fall event (one per CRAWL_UNITS shown units, at least one)
const CRAWL_UNITS := 8.0
const CRAWL_V := 2.4             # m/s along the floor
# Crawl time: whatever the distance takes (Daniele 2026-11-06: "takes whatever time the splatted goo needs").
const RISE_V := 5.0              # m/s up the tube
const SPLAT_LIFE := 7.0
const SPLAT_MAX := 48
const MERGE_R := 0.5             # m past a fresh splat's blot edge (0.62 x size) where a body landing grows it instead
const MERGE_T := 0.9             # s: how long a splat stays "fresh" for that
const CRAWL_MAX := 48
const DROP_MAX := 96
const DROPS_PER_SPLAT := 8
const RIDERS_PER_TUBE := 4
# WORLD LORE (01 Rules/WORLD-LORE-2026-11.md): the native goo (the Locals) is plain GRAY - the colour no player picks. A
# neutral tube holds gray native goo (a capture pushes it down); a splat is a "clock out": the goo turns gray on the
# floor and crawls back gray, riding up the tube gray.
const NATIVE_GRAY := Color(0.36, 0.37, 0.41, 1.0)
const CLOCK_OUT_T := 1.2         # s for a splat's colour to fade to gray
const FLOOR_KINDS := ["street", "factory", "sewer", "lab"]   # per map (code hash); --floor=<kind> forces one
const MIST_ABOVE := 7.0          # the drifting fog layer between arena and floor, this far above the floor
const MIST_DENSITY := 0.3
const ZAP_T := 0.22              # an enemy tube's door laser: beam time
const ZAP_POOL := 6

var sim: Sim
var vis: Dictionary
var floor_y := -16.0
var floor_kind := "factory"
var floor_pic := false            # --floor=labpic
var floor_lab5 := false           # the lab biome's R5 tile floor (default for "lab", --floor=lab5 anywhere)
var floor_haze := -1.0            # the world props' haze toward the void (-1: each shader's own default)
static var active: WorldLayer     # the match's world layer (the fall views drop their bodies onto its floor: F1 / F2)
var decals: WorldDecals           # the floor decals (one MultiMesh, one atlas)
var _landed: Array = []           # bodies that hit the floor this frame: [Vector3, seat]
var bodies_landed := 0
var log_landings := false         # probes: [landing, its splat's centre, size] per body
var landing_log: Array = []
var locals: WorldLocals          # LOCALS MARCH: containment ring craters + the Locals walking to the tube doors
var _zaps: Array = []            # pooled beams: {mi, t0}
var zaps_done := 0
var _floor: MeshInstance3D
var _tubes: Array = []           # [{id, mi, mat, r, top_off, owner, base, base_old, inv, inv_col, inv_seat, pushing, riders, alive, x, z, dirty}]
var _t := 0.0
var _pending: Array = []         # [land time, event]
var _low := false
# pools (ring buffers)
var _blob_mm: MultiMesh
var _drop_mm: MultiMesh
var _splat_mm: MultiMesh
var _socket_mm: MultiMesh         # one floor socket per tube (owner-coloured ring)
const SOCKET_PAD := 1.8           # metres of collar and drains around a tube's foot
var _ent_mm: MultiMesh            # one tube entrance per common tube (owner light in INSTANCE_CUSTOM)
var _ent_mat: ShaderMaterial
var _ent_mms: Array = [null, null, null, null]   # VAT COLUMN readers: [_, base, base, base] - one column base for every tier
var pipes: WorldTubes            # PITS / TUBES: the transport tubes socket -> pit, the pits' colour (null while FLOOR_TUBES is off)
# FLOOR TUBES SPLIT (Daniele 2026-11-10, Desk floor-tubes: "I wanted only the props removed, not the coloured tubes from nodes
# to pit in the colour of each faction, those remain"; chat on demo12: "why are the pipes from pit to node gone? they should be
# there"): the transport tubes column -> pit (WorldTubes) are ON again; the lab dressing's floor pipe runs along the lanes
# (the props, removed 2026-11-09 proto25 review) stay OFF - FLOOR_PIPE_PROPS or the dev arg --floor-pipe-props brings them back.
# --no-floor-tubes hides the transport tubes (before / after shots).
static var FLOOR_TUBES := true
static var FLOOR_PIPE_PROPS := false
var column: VatColumn            # VAT COLUMN: upgrade blueprint + the entrance module from the pit (vat_column.gd)
var _blobs: Array = []           # {p, tube, col, t0, mode (0 hop, 1 crawl, 2 enter), v, dur, from}
var _drops: Array = []           # {p, v, t0, col}
var _splats: Array = []          # {p, size, t0, col, seed}
var splats_made := 0             # probes read these
var blobs_made := 0
var riders_done := 0
var sync_us := 0                 # the last sync's cost (perf probe)
var _warm := 3                   # frames the pools draw one hidden instance so their shaders compile at load


static func wanted() -> bool:
	return Rules.world_layer


func setup(_main: Node3D, s: Sim, v: Dictionary, mobile := false) -> void:
	sim = s
	vis = v
	_low = mobile or PerfProfile.level() == "low"
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in sim.nodes:
		var p: Vector3 = n["pos"]
		lo = lo.min(p)
		hi = hi.max(p)
	if sim.nodes.is_empty():
		lo = Vector3.ZERO
		hi = Vector3.ZERO
	floor_y = minf(lo.y, 0.0) - FLOOR_DEPTH
	var centre := (lo + hi) / 2.0
	var radius := Vector2(hi.x - lo.x, hi.z - lo.z).length() / 2.0
	floor_kind = _floor_kind_for(str(_main.get("map_path")) if _main.get("map_path") != null else "")
	var args := OS.get_cmdline_user_args()
	floor_pic = "--floor=labpic" in args
	var demo_default: bool = (Rules.demo or Rules.WORLD_LAB_FLOOR) and not Array(args).any(func(a): return str(a).begins_with("--floor"))   # DEMO BUILD: lab5 floor by default (Daniele, world pass 2)
	if floor_pic or "--floor=lab5" in args or demo_default or Look.lab:   # LAB LOOK TEST: the lab floor path, TILE-LAB below
		floor_kind = "lab"
	floor_lab5 = floor_kind == "lab" and not floor_pic and not "--floor-v1" in args
	if Look.lab:
		floor_pic = false
		floor_lab5 = true
	if "--floor-clear" in args:
		floor_haze = 0.0
	elif floor_pic:
		floor_haze = LAB_PIC_HAZE
	elif floor_lab5:
		floor_haze = LAB5_HAZE
	if Look.lab:
		floor_haze = 0.0                              # LAB LOOK TEST: the tile at its own value
	active = self
	_build_floor(centre, radius)
	Look.add_surround(self, minf(lo.y, 0.0))         # LAB LOOK TEST: the screen-pinned surround (null without --look=lab)
	if floor_lab5:
		_lab_backdrop(_main)
	if not "--floor-clear" in OS.get_cmdline_user_args() and not Look.lab:   # dev: --floor-clear = no floor fog sheet, no floor haze
		_build_mist(centre, radius)
	for n in sim.nodes:
		_build_tube(n)
	_build_pools()
	if (FLOOR_TUBES or "--floor-tubes" in OS.get_cmdline_user_args()) and not "--no-floor-tubes" in OS.get_cmdline_user_args():
		pipes = WorldTubes.new()                      # PITS / TUBES (built once the pits are placed: WorldLocals.place)
		add_child(pipes)
		pipes.setup(self)
	if not "--no-locals" in OS.get_cmdline_user_args():
		locals = WorldLocals.new()
		add_child(locals)
		locals.setup(self)
	_orient_entrances()
	column = VatColumn.new()
	add_child(column)
	column.setup(self)
	if floor_lab5 and not "--no-dressing" in OS.get_cmdline_user_args() and not Look.lab: add_child(WorldDressing.new())   # WORLD COMPLETE LAB (LAB LOOK TEST: the surround replaces it)
	Look.lab_world(_main)                            # LAB LOOK TEST (no-op without --look=lab)


func _lab_backdrop(main: Node) -> void:
	## the lab biome's side backdrop (round 5) on Scenery's sky layer, hazed toward LAB_FAR in the middle so the floor's
	## fade ring melts into it; and the scene's height fog thinned so a fall stays visible down to the floor
	var sc = main.get("scenery")
	var layer: CanvasLayer = sc.backdrop if sc != null else null
	if layer != null and layer.get_child_count() > 0 and layer.get_child(0) is TextureRect:
		var sky := layer.get_child(0) as TextureRect
		var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(812, 375)
		var side := "a" if "--lab-side=a" in OS.get_cmdline_user_args() else "b"
		sky.texture = load(PerfProfile.hi_path(LAB_SIDE % [side, 1184 if vp.x / maxf(vp.y, 1.0) >= 2.0 else 1440]))
		var m := sky.material as ShaderMaterial
		m.set_shader_parameter("abyss", LAB_FAR)
		m.set_shader_parameter("tint", Color(1, 1, 1, 1))
		m.set_shader_parameter("brightness", 0.9)
		m.set_shader_parameter("abyss_haze", 0.55)
	if sc != null:                                    # the arena's mist sheets: the lab's gray-blue air, not the violet void
		for c in (sc as Node).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial 					and ((c as MeshInstance3D).material_override as ShaderMaterial).shader == Scenery.VOID_SHADER:
				((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("mist_color", LAB_FAR.lightened(0.12))
	for c in main.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			var env := (c as WorldEnvironment).environment
			env.fog_height_density = LAB5_FOG_HEIGHT_DENSITY
			env.fog_light_color = LAB_FAR


func haze_abyss() -> Color:
	## the colour the world props haze toward (the floor's far haze is this x 0.6)
	return LAB_FAR / 0.6 if floor_lab5 else Scenery.ABYSS


func _exit_tree() -> void:
	if active == self:
		active = null


static func _floor_kind_for(map_path: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--floor=") and a.substr(8) in FLOOR_KINDS:
			return a.substr(8)
		if a == "--floor=lab5":
			return "lab"
	var code := map_path.get_file().substr(0, 4)
	return FLOOR_KINDS[absi(hash(code)) % FLOOR_KINDS.size()] if code != "" else "factory"


func _build_mist(centre: Vector3, radius: float) -> void:
	## Daniele: "drifting fog/clouds separate arena and splat floor" - one more mist sheet (the void's own shader) between
	## the decks and the floor, denser than the arena's near layer, drifting slower.
	var noise := FastNoiseLite.new()
	noise.seed = 23
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * (radius * 2.0 + 160.0)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = Scenery.VOID_SHADER
	mat.set_shader_parameter("noise_tex", tex)
	mat.set_shader_parameter("mist_color", Scenery.ABYSS.lightened(0.18))
	mat.set_shader_parameter("density", MIST_DENSITY * (LAB_PIC_MIST if floor_pic else (LAB5_MIST if floor_lab5 else 1.0)))
	if floor_lab5:
		mat.set_shader_parameter("mist_color", LAB_FAR.lightened(0.1))
	mat.set_shader_parameter("scale", 0.009)
	mat.set_shader_parameter("motes", 0.5)
	mat.set_shader_parameter("wind", Vector2(0.004, 0.0018))
	mat.render_priority = -5                         # after the floor, splats and sockets
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(centre.x, floor_y + MIST_ABOVE, centre.z)
	add_child(mi)


func _build_floor(centre: Vector3, radius: float) -> void:
	_floor = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * (radius * 2.0 + 260.0)
	_floor.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = SHADER_FLOOR
	m.set_shader_parameter("abyss", Scenery.ABYSS)
	m.set_shader_parameter("centre", Vector2(centre.x, centre.z))
	m.set_shader_parameter("r0", radius + 30.0)
	m.set_shader_parameter("r1", radius + 110.0)
	m.set_shader_parameter("kind", FLOOR_KINDS.find(floor_kind))
	# R3A-2 geometry v2 tiles (director, 2026-11-07); --floor-v1 keeps the old procedural placeholder for before/after.
	var v1 := "--floor-v1" in OS.get_cmdline_user_args()
	m.set_shader_parameter("tiles", not v1 and not floor_pic and not floor_lab5)
	if floor_lab5:
		m.set_shader_parameter("lab5", true)
		m.set_shader_parameter("t_lab5", load(Look.FLOOR) if Look.lab else load(PerfProfile.hi_path(LAB5_FLOOR_GROUT if "--floor-grout" in OS.get_cmdline_user_args() else LAB5_FLOOR)))
		m.set_shader_parameter("lab5_m", Look.FLOOR_M if Look.lab else LAB5_TILE_M)
		m.set_shader_parameter("lab5_gain", LAB5_GAIN)
		m.set_shader_parameter("haze", LAB5_HAZE)
		m.set_shader_parameter("abyss", LAB_FAR / 0.6)   # its far haze (abyss x 0.6) is the backdrop's middle
	elif floor_pic:                                    # world-locked: centred under the board, its 2 m grid on the world's
		var o := Vector2(centre.x, centre.z) - LAB_PIC_SIZE / 2.0
		o = Vector2(snappedf(o.x + LAB_PIC_GRID0.x, 2.0) - LAB_PIC_GRID0.x, snappedf(o.y + LAB_PIC_GRID0.y, 2.0) - LAB_PIC_GRID0.y)
		m.set_shader_parameter("pic", true)
		m.set_shader_parameter("t_pic", load(LAB_PIC))
		m.set_shader_parameter("pic_origin", o)
		m.set_shader_parameter("pic_size", LAB_PIC_SIZE)
		m.set_shader_parameter("haze", LAB_PIC_HAZE)
		m.set_shader_parameter("pic_gain", LAB_PIC_GAIN)
		m.set_shader_parameter("pic_mirror", LAB_PIC_MIRROR and not "--labpic-fade" in OS.get_cmdline_user_args())
	elif not v1:
		var dir := FLOORS_V2 + floor_kind
		m.set_shader_parameter("t_base", load(dir + "-base-v2.png"))
		for v in ["b", "c", "d", "e"]:
			m.set_shader_parameter("t_" + v, load("%s-variant-%s-v2.png" % [dir, v.to_upper()]))
		m.set_shader_parameter("t_crust", load(FLOORS_V2 + "crust-tile-v2.png"))
		m.set_shader_parameter("r_district", radius + 30.0)
	if "--floor-clear" in OS.get_cmdline_user_args():
		m.set_shader_parameter("haze", 0.0)
	m.render_priority = -10                          # the first transparent drawn: everything above blends over it
	_floor.material_override = m
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.position = Vector3(centre.x, floor_y, centre.z)
	add_child(_floor)


func _build_tube(n: Dictionary) -> void:
	var id: int = n["id"]
	if not vis.has(id) or str(n.get("junction", "")) != "" or str(n.get("lane", "")) == "over":
		return
	if str(n.get("relay", "")) != "":                # Daniele 2026-11-06: no tubes on relays
		return
	if vis[id].get("platform") == null:              # a plaza member: the plaza piece is shared (spec: later)
		return
	var pillar := MapBuilder.platform_piece(n) == "Platform_Pillar"
	var b: Array = n.get("buildable", [])
	# fog-maps-fix (P-03 node 7): a pillar that can hold a vat / machinegoon gets the common column (base, doors, sockets) so its
	# tubes and Locals exist like every other buildable node's; the wide glass sleeve stays on the pillars that cannot
	var r := TUBE_R_PILLAR if (pillar and not ("vat" in b or "machinegoon" in b)) else TUBE_R
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 20 if not _low else 14
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = SHADER_TUBE
	m.set_shader_parameter("abyss", Scenery.ABYSS)
	if Calm.world():                                  # calm-pass A: the column tubes glow less
		m.set_shader_parameter("glow", Calm.TUBE_GLOW)
	m.set_shader_parameter("y_bot", floor_y)
	m.set_shader_parameter("fade_top", Scenery.FOG_HEIGHT)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var owner: String = n["owner"]
	var tb := {"id": id, "mi": mi, "mat": m, "r": r, "top_off": TUBE_TOP_PILLAR if pillar else TUBE_TOP,
			"owner": owner, "base": _col(owner), "base_old": _col(owner), "inv": 0.0, "inv_col": _col(owner),
			"inv_seat": "", "pushing": false, "riders": [], "alive": true, "drain": 0.0,
			"x": (n["pos"] as Vector3).x, "z": (n["pos"] as Vector3).z, "top_y": 999.0}
	_tubes.append(tb)


static func _col(seat: String) -> Color:
	if seat == "":
		return NATIVE_GRAY                           # neutral: the planet's native gray goo
	var c := GooTone.of_seat(seat, Rules.seat_color(seat))   # goo = the faction's body tone (GooTone), not the neon
	if Calm.world():                                  # calm-pass A (dev flag): the tubes' goo dimmer still
		c = Calm.desat(c, Calm.TUBE_SAT).darkened(0.25)
	return Color(c.r, c.g, c.b, 1.0)


func _build_pools() -> void:
	var gm := ShaderMaterial.new()
	gm.shader = SHADER_GOO
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 5
	sphere.material = gm
	_blob_mm = _mm(sphere, CRAWL_MAX, false)
	var small := SphereMesh.new()
	small.radius = 0.5
	small.height = 1.0
	small.radial_segments = 6
	small.rings = 3
	small.material = gm
	_drop_mm = _mm(small, DROP_MAX if not _low else DROP_MAX / 2, false)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var sm := ShaderMaterial.new()
	sm.shader = SHADER_SPLAT
	sm.render_priority = -8                          # over the floor and its decals
	quad.material = sm
	_splat_mm = _mm(quad, SPLAT_MAX, true)
	var squad := PlaneMesh.new()
	squad.size = Vector2.ONE
	var skm := ShaderMaterial.new()
	skm.shader = SHADER_SOCKET
	skm.render_priority = -9
	squad.material = skm
	_socket_mm = _mm(squad, maxi(_tubes.size(), 1), true)
	var ent_mesh: Mesh = WorldTubes.column_base_mesh()
	_ent_mat = ShaderMaterial.new()
	_ent_mat.shader = SHADER_ENTRANCE
	_ent_mat.set_shader_parameter("abyss", haze_abyss())
	_ent_mat.set_shader_parameter("kit", Look.v2 and ent_mesh != null and ent_mesh.resource_name == "labkit")
	if floor_haze >= 0.0:
		_ent_mat.set_shader_parameter("haze", floor_haze)
	var emm := MultiMesh.new()                       # PITS / TUBES: one column base for every tier
	emm.transform_format = MultiMesh.TRANSFORM_3D
	emm.use_custom_data = true
	emm.use_colors = true                            # white: the Compatibility renderer multiplies COLOR by it (0 without)
	emm.mesh = ent_mesh
	emm.instance_count = maxi(_tubes.size(), 1)
	var emi := MultiMeshInstance3D.new()
	emi.multimesh = emm
	emi.material_override = _ent_mat
	emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emi)
	_ent_mms = [null, emm, emm, emm]                 # (VatColumn reads _ent_mms[tier].mesh)
	_ent_mm = emm
	for i in range(_tubes.size()):
		var tb: Dictionary = _tubes[i]
		var half: float = float(tb["r"]) + SOCKET_PAD
		tb["sock"] = i
		tb["ent"] = ent_mesh != null and is_equal_approx(float(tb["r"]), TUBE_R)
		tb["ent_xf"] = Transform3D(Basis.IDENTITY, Vector3(tb["x"], floor_y, tb["z"]))
		var sx := Transform3D(Basis.from_scale(Vector3(half * 2.0, 1.0, half * 2.0)), Vector3(tb["x"], floor_y + 0.02, tb["z"]))
		_socket_mm.set_instance_transform(i, HIDDEN if tb["ent"] else sx)
		_socket_mm.set_instance_custom_data(i, Color(float(tb["r"]) / half, 0, 0, 0))
		_ent_mm.set_instance_transform(i, HIDDEN)
		_ent_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
		_ent_mm.set_instance_color(i, Color.WHITE)
		_sock_lit(tb, tb["base"])
	_socket_mm.visible_instance_count = _tubes.size()
	_ent_mm.visible_instance_count = _tubes.size()


func _orient_entrances() -> void:
	## the base's front (+Z) door faces the crater that feeds the tube (world_locals' feed door; a quarter turn of the
	## symmetric base, so its sockets stay on the world diagonals); no Locals / craters: front +Z
	for i in range(_tubes.size()):
		var tb: Dictionary = _tubes[i]
		if not tb.get("ent", false):
			continue
		var d: Vector2 = WorldLocals.door_dirs()[0]
		if locals != null and locals.feeds.has(i):
			d = locals.feeds[i]["dir"]
		tb["ent_yaw"] = atan2(d.x, d.y)
		if WorldTubes.base45():                       # the base is 4-fold symmetric: the quarter turn that puts its flat (floor-level)
			var yw := float(tb["ent_yaw"])            # sockets on world x (mesh faces 1 / 5) and the tilted ones on world z
			tb["ent_yaw"] = PI / 4.0 if absf(angle_difference(yw, PI / 4.0)) <= PI / 2.0 else PI / 4.0 + PI
		tb["ent_xf"] = Transform3D(Basis(Vector3.UP, float(tb["ent_yaw"])), Vector3(tb["x"], floor_y, tb["z"]))
		_sock_lit(tb, tb["base"] if (tb["mi"] as MeshInstance3D).visible else Color(0, 0, 0, 0))


const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -9999, 0))


static func _entrance_mesh(path := ENTRANCE_GLB) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := ps.instantiate()
	var found: Mesh = null
	var stack: Array = [root]
	while not stack.is_empty() and found == null:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			found = (nd as MeshInstance3D).mesh
		stack.append_array(nd.get_children())
	root.free()
	return found


func _sock_lit(tb: Dictionary, c: Color) -> void:
	## the tube's foot shows its owner: the entrance's owner light (common tubes) or the flat socket ring (pillar
	## sleeves); a clear colour hides it (no structure / tube gone)
	var i := int(tb["sock"])
	if decals != null:
		decals.tint_pool(i, c)
	if tb.get("ent", false):                         # (hidden while the VAT COLUMN blueprint shows)
		var show: bool = c.a > 0.0 and not tb.get("holo", false)
		_ent_mm.set_instance_transform(i, tb["ent_xf"] if show else HIDDEN)
		_ent_mm.set_instance_custom_data(i, c)
	else:
		_socket_mm.set_instance_color(i, c)


func _mm(mesh: Mesh, count: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


# ------------------------------------------------------------------ events
func handle(ev: Dictionary) -> void:
	var ty: String = ev.get("type", "")
	if ty != "fall" and ty != "fling":
		return
	if bool(ev.get("decoy", false)):
		return
	var pts: Array = ev.get("pts", [])
	if pts.is_empty():
		return
	if not Rules.bridge_combat and active == self:
		return                                        # BRAWL (F1): every falling body reports where it hits (land_body)
	var shown := float(ev.get("units", 0.0)) if ty == "fling" else Rules.shown_f(float(ev.get("units", 0.0)))
	if shown <= 0.0:
		return
	var p0: Vector3 = pts[0]
	var depth := clampf(p0.y - floor_y, 0.0, LAND_DROP)
	var land := FALL_S * sqrt(depth / LAND_DROP)      # the bodies' ease-in drop reaches the floor here
	if ev.get("pour", false):
		land = 1.3                                    # horde_view's pour fallers (POUR_G): about the same
	_pending.append([_t + land, ev, shown])


func fall_depth(y: float) -> float:
	## F2: metres from a falling body's start height down to the floor - the fall views (Fx, UnitView) drop it that far,
	## in true 3D (no scaling: it shrinks with the perspective), and report the hit with land_body.
	return maxf(y - floor_y, 0.5)


func land_body(p: Vector3, seat: String) -> void:
	## F1: a falling body hit the floor at p (x, z): the splat appears exactly there (sync, this frame)
	if Rules.bridge_combat:
		return                                        # SIEGE (paused): handle() keeps its event splats
	_landed.append([p, seat])


func _land_bodies() -> void:
	## Each landing makes a splat at its own x, z - or grows a fresh splat of its colour it fell into (a line pouring
	## off a lip lands as one growing puddle) - with droplets; one gray crawler per new splat and per CRAWL_UNITS bodies.
	for L in _landed:
		var p: Vector3 = L[0]
		var seat: String = L[1]
		var at := Vector3(p.x, floor_y + 0.03, p.z)
		var col := _col(seat)
		bodies_landed += 1
		var hit: Dictionary = {}
		for k in range(_splats.size() - 1, -1, -1):
			var sp: Dictionary = _splats[k]
			if _t - float(sp["t0"]) > MERGE_T:
				break
			var dxz := Vector2((sp["p"] as Vector3).x - at.x, (sp["p"] as Vector3).z - at.z).length()
			if str(sp.get("seat", "?")) == seat and dxz < MERGE_R + float(sp["size"]) * 0.62 and dxz < 0.62 * 4.5 - 0.45:
				hit = sp
				hit["dxz"] = dxz
				break
		if hit.is_empty():
			_add_splat(at, 1.1, col)
			_splats[-1]["seat"] = seat
			_splats[-1]["n"] = 1
			_add_blob(at, NATIVE_GRAY, seat)
		else:
			hit["n"] = int(hit["n"]) + 1                # the blot grows to take it in (its edge at 0.62 x size)
			hit["size"] = minf(maxf(float(hit["size"]) + 0.12, (float(hit["dxz"]) + 0.45) / 0.62), 4.5)
			if int(hit["n"]) % int(CRAWL_UNITS) == 0:
				_add_blob(hit["p"], NATIVE_GRAY, seat)
		if log_landings:
			var sp3: Dictionary = _splats[-1] if hit.is_empty() else hit
			landing_log.append([at, sp3["p"], float(sp3["size"])])
		for j in range(3 if not _low else 2):
			var a := randf() * TAU
			var sp2 := randf_range(1.5, 3.5)
			_add_drop(at + Vector3(0, 0.2, 0), Vector3(cos(a) * sp2, randf_range(2.5, 5.0), sin(a) * sp2), col)
	_landed.clear()


func _land(ev: Dictionary, shown: float) -> void:
	var pts: Array = ev["pts"]
	var col := _col(str(ev.get("seat", "")))
	var n_spl := mini(SPLATS_PER_FALL, maxi(1, int(ceil(shown / 12.0))))
	n_spl = mini(n_spl, pts.size())
	var size := clampf(1.4 + 0.5 * sqrt(shown / float(n_spl)), 1.6, 5.0)
	var n_crawl := clampi(int(ceil(shown / CRAWL_UNITS)), 1, CRAWL_PER_FALL)
	var fling: bool = ev.get("type", "") == "fling"
	var centre: Vector3 = ev.get("centre", Vector3.ZERO)
	for k in range(n_spl):
		var p: Vector3 = pts[int(float(k) * pts.size() / n_spl)]
		var at := Vector3(p.x + randf_range(-1.2, 1.2), floor_y + 0.03, p.z + randf_range(-1.2, 1.2))
		if fling:                                     # flung outward off the turning deck
			var out := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
			if out.length() > 0.01:
				at += out.normalized() * 4.0
		_add_splat(at, size, col)
		for j in range(DROPS_PER_SPLAT if not _low else DROPS_PER_SPLAT / 2):
			var a := randf() * TAU
			var sp := randf_range(2.0, 4.5)
			_add_drop(at + Vector3(0, 0.2, 0), Vector3(cos(a) * sp, randf_range(3.0, 6.0), sin(a) * sp), col)
		var mine := n_crawl / n_spl + (1 if k < n_crawl % n_spl else 0)
		for j in range(mine):
			_add_blob(at + Vector3(randf_range(-0.5, 0.5) * size * 0.5, 0, randf_range(-0.5, 0.5) * size * 0.5), NATIVE_GRAY,
					str(ev.get("seat", "")))


func _add_splat(at: Vector3, size: float, col: Color) -> void:
	if _splats.size() >= SPLAT_MAX:
		_splats.pop_front()
	_splats.append({"p": at, "size": size, "t0": _t, "col": col, "seed": randf()})
	splats_made += 1


func _add_drop(at: Vector3, v: Vector3, col: Color) -> void:
	if _drops.size() >= _drop_mm.instance_count:
		_drops.pop_front()
	_drops.append({"p": at, "v": v, "t0": _t, "col": col})


func _add_blob(at: Vector3, col: Color, seat := "") -> void:
	var best := -1
	var bd := INF
	for i in range(_tubes.size()):
		var tb: Dictionary = _tubes[i]
		if not tb["alive"] or not tb.get("shown", true):
			continue
		var d := Vector2(tb["x"] - at.x, tb["z"] - at.z).length()
		if d < bd:
			bd = d
			best = i
	if _blobs.size() >= CRAWL_MAX:
		_blobs.pop_front()
	var dist := maxf(bd - (_tubes[best]["r"] if best >= 0 else 0.0) - 0.2, 0.0)
	if best >= 0 and _tubes[best].get("ent", false):   # R8: it crawls to the nearest door
		var df := _door_front(_tubes[best], at)
		dist = Vector2(df.x - at.x, df.z - at.z).length()
	var dur := dist / CRAWL_V if best >= 0 else 2.0
	_blobs.append({"p": at, "from": at, "tube": best, "col": col, "t0": _t + randf_range(0.0, 0.35), "mode": 0,
			"dur": maxf(dur, 0.3), "size": randf_range(0.75, 1.15), "ph": randf() * TAU, "seat": seat})
	blobs_made += 1


# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += dt
	while not _pending.is_empty() and _pending[0][0] <= _t:
		var pe: Array = _pending.pop_front()
		_land(pe[1], pe[2])
	if not _landed.is_empty():
		_land_bodies()
	if _pending.size() > 1 and _pending[-1][0] < _pending[-2][0]:
		_pending.sort_custom(func(a, b): return a[0] < b[0])
	_tubes_step(dt)
	if locals != null:
		locals.step(dt)
	if pipes != null:
		pipes.step(dt)
	if column != null:
		column.step(dt)
	_blobs_step(dt)
	_drops_step()
	_splats_step()
	_zaps_step()
	if _warm > 0:                                     # shader warm-up: one instance each, under the floor (the first
		_warm -= 1                                    # real fall must not hitch on a compile - 63 ms seen without it)
		var under := Transform3D(Basis.from_scale(Vector3.ONE * 0.01), Vector3(_floor.position.x, floor_y - 2.0, _floor.position.z))
		for mm in [_blob_mm, _drop_mm, _splat_mm]:
			if (mm as MultiMesh).visible_instance_count == 0:
				(mm as MultiMesh).set_instance_transform(0, under)
				(mm as MultiMesh).visible_instance_count = 1
	sync_us = Time.get_ticks_usec() - t0


func _tubes_step(dt: float) -> void:
	for tb in _tubes:
		var n: Dictionary = sim.nodes[tb["id"]]
		var mi: MeshInstance3D = tb["mi"]
		var plat = vis[tb["id"]].get("platform")
		var top := floor_y + 0.5
		if plat is Node3D and is_instance_valid(plat) and (plat as Node3D).is_visible_in_tree():
			top = (plat as Node3D).global_position.y + float(tb["top_off"])
		elif tb.get("holo", false) and float(tb["top_y"]) < 900.0:   # VAT COLUMN: the platform is the blueprint now
			top = float(tb["top_y"])
		if sim.collapsed.get(tb["id"], false):        # Last Stand: the tube drains and sinks with its platform
			tb["alive"] = false
			tb["drain"] = minf(float(tb["drain"]) + dt / 1.2, 1.0)
		var has_structure := str(n.get("structure", "")) != ""   # Daniele: tubes only under a vat / structure
		tb["shown"] = has_structure
		if top <= floor_y + 0.4 or not has_structure:
			if mi.visible:
				mi.visible = false
				_sock_lit(tb, Color(0, 0, 0, 0))
			continue
		if not mi.visible:                            # a structure (re)built: the socket lights again
			mi.visible = true
			_sock_lit(tb, tb["base"])
		if absf(top - float(tb["top_y"])) > 0.01:
			tb["top_y"] = top
			var h := top - floor_y
			mi.transform = Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(tb["x"], floor_y + h / 2.0, tb["z"]))
			(tb["mat"] as ShaderMaterial).set_shader_parameter("y_top", top)
		var owner: String = n["owner"]
		if owner != tb["owner"]:                      # a capture: the capturer's goo pushes the old colour out
			tb["base_old"] = tb["base_old"] if tb["pushing"] else tb["base"]
			if tb["inv_seat"] != owner:
				tb["inv"] = 0.0
			tb["inv_seat"] = owner
			tb["inv_col"] = _col(owner)
			tb["base"] = _col(owner)
			tb["owner"] = owner
			tb["pushing"] = true
			_sock_lit(tb, tb["base"])
		if tb["pushing"]:
			tb["inv"] = minf(float(tb["inv"]) + dt / PUSH_T, 1.0)
			if tb["inv"] >= 1.0:
				tb["pushing"] = false
				tb["inv"] = 0.0
				tb["base_old"] = tb["base"]
		else:
			var best_seat := ""
			var best_u := 0.0
			var siege: Dictionary = n.get("siege", {})
			for s in siege:
				if s != owner and float(siege[s]) > best_u:
					best_u = float(siege[s])
					best_seat = s
			var target := 0.0
			if best_seat != "":
				target = INV_MAX * best_u / (best_u + maxf(float(n["units"]), 0.01))
				if best_seat != tb["inv_seat"] and float(tb["inv"]) < 0.02:
					tb["inv_seat"] = best_seat
					tb["inv_col"] = _col(best_seat)
			if best_seat != tb["inv_seat"]:
				target = 0.0
			tb["inv"] = move_toward(float(tb["inv"]), target, dt * INV_RATE)
		var m: ShaderMaterial = tb["mat"]
		var top_c: Color = tb["inv_col"]
		var bot_c: Color = tb["base_old"] if tb["pushing"] else tb["base"]
		var drain: float = tb["drain"]
		if drain > 0.0:
			top_c.a *= 1.0 - drain
			bot_c.a *= 1.0 - drain
		if VatColumn.upgrading(n):                    # VAT COLUMN 2 / R4: the lift stays EMPTY glass while the upgrade builds
			top_c.a = 0.0
			bot_c.a = 0.0
		var sp: float = tb["inv"]
		if tb["pushing"]:
			sp = smoothstep(0.0, 1.0, sp)
		m.set_shader_parameter("col_top", top_c)
		m.set_shader_parameter("col_bot", bot_c)
		m.set_shader_parameter("split", sp)
		m.set_shader_parameter("push", 1.0 if tb["pushing"] else 0.0)
		_riders_step(tb, dt, top)


func _riders_step(tb: Dictionary, dt: float, top: float) -> void:
	## WORLD PASS 2 (F3, Daniele: no gray circle / slug riding up inside the tube - the tube's own flow already shows the
	## goo going up): riders are counted (probes) but no longer drawn; the tube shader's rider_y stays at its -999 default.
	var riders: Array = tb["riders"]
	if riders.is_empty():
		return
	var keep := []
	for r in riders:
		r[0] = float(r[0]) + RISE_V * dt
		if r[0] < top - 0.3:
			keep.append(r)
		else:
			riders_done += 1
	tb["riders"] = keep


func _blobs_step(_dt: float) -> void:
	var keep := []
	var shown := 0
	for b in _blobs:
		var age: float = _t - float(b["t0"])
		var tb: Dictionary = _tubes[b["tube"]] if int(b["tube"]) >= 0 else {}
		var size: float = b["size"]
		var p: Vector3 = b["p"]
		var dir := Vector3.FORWARD
		var squash := 1.0
		var target := Vector3(tb["x"], floor_y, tb["z"]) if not tb.is_empty() else p
		var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
		if to.length() > 0.01:
			dir = to.normalized()
		if age < 0.0:                                 # not out of the splat yet
			keep.append(b)
			continue
		if age < 0.35:                                # recoil out of the splat
			p = b["from"] + Vector3(0, sin(age / 0.35 * PI) * 0.5, 0)
			squash = 1.0 + 0.4 * sin(age / 0.35 * PI)
		elif age < 0.35 + float(b["dur"]):             # crawl
			var k := (age - 0.35) / float(b["dur"])
			var from: Vector3 = b["from"]
			var end := Vector3(target.x, floor_y, target.z)
			if not tb.is_empty() and tb.get("ent", false):   # R8: to the column base's nearest door
				end = _door_front(tb, from)
			elif not tb.is_empty():
				var away := Vector3(from.x - target.x, 0.0, from.z - target.z)
				end = Vector3(target.x, floor_y, target.z) + (away.normalized() if away.length() > 0.01 else Vector3.RIGHT) * (float(tb["r"]) + 0.15)
			p = from.lerp(end, k)
			p.y = floor_y + 0.12
			squash = 1.0 + 0.25 * sin(age * 9.0 + float(b["ph"]))
		elif not tb.is_empty() and _hostile(tb, str(b["seat"])):   # an ENEMY tube: its door lasers the goo
			_zap(tb, p, b["col"])                       # the blob pops (not kept)
			continue
		elif age < 0.35 + float(b["dur"]) + 0.3 and not tb.is_empty():   # squeeze into the tube
			var k2 := (age - 0.35 - float(b["dur"])) / 0.3
			size *= 1.0 - k2
		else:
			if not tb.is_empty() and tb["alive"]:
				(tb["riders"] as Array).append([floor_y + 0.4, b["col"]])
			continue
		b["p"] = p
		var s := 0.95 * size
		var basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(s / squash, s * 0.5 * squash, s * squash))
		_blob_mm.set_instance_transform(shown, Transform3D(basis, p))
		_blob_mm.set_instance_color(shown, b["col"])
		shown += 1
		keep.append(b)
	_blobs = keep
	_blob_mm.visible_instance_count = shown


func _door_front(tb: Dictionary, from: Vector3) -> Vector3:
	## the point just in front of the column base's door nearest `from` (doors on the world's +-X / +-Z)
	var best := Vector3.ZERO
	var bd := INF
	for d in WorldLocals.door_dirs():
		var q := Vector3(float(tb["x"]) + d.x * (WorldTubes.APOTHEM + 0.3), floor_y, float(tb["z"]) + d.y * (WorldTubes.APOTHEM + 0.3))
		var dd := Vector2(q.x - from.x, q.z - from.z).length()
		if dd < bd:
			bd = dd
			best = q
	return best


func _hostile(tb: Dictionary, seat: String) -> bool:
	var owner: String = tb["owner"]
	return owner != "" and seat != "" and owner != seat and not sim.allied(owner, seat)


func _zap(tb: Dictionary, at: Vector3, col: Color) -> void:
	## Daniele: "an ENEMY tube's door lasers it" - a beam from the door at the tube's foot to the blob, the blob pops.
	if _zaps.is_empty():
		for i in range(ZAP_POOL):
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.08, 1.0)
			mi.mesh = bm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			_zaps.append({"mi": mi, "t0": -99.0})
	var z: Dictionary = _zaps[zaps_done % ZAP_POOL]
	zaps_done += 1
	var dir := Vector3(at.x - float(tb["x"]), 0.0, at.z - float(tb["z"]))
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var door := Vector3(tb["x"], floor_y + 0.7, tb["z"]) + dir * float(tb["r"])
	if tb.get("ent", false):                          # the upper laser strand of the base's door that faces the blob
		var ax := Vector3(signf(dir.x), 0, 0) if absf(dir.x) > absf(dir.z) else Vector3(0, 0, signf(dir.z))
		if WorldTubes.base45():
			ax = Vector3(signf(dir.x), 0, signf(dir.z)).normalized()
		door = Vector3(tb["x"], floor_y + WorldTubes.LASER_Y[1], tb["z"]) + ax * (WorldTubes.APOTHEM + 0.06)
	var to := at + Vector3(0, 0.25, 0)
	var mi2: MeshInstance3D = z["mi"]
	var tc: Color = tb["base"]
	mi2.material_override = Mats.glow(Color(tc.r, tc.g, tc.b).lightened(0.35))
	var ln := maxf(door.distance_to(to), 0.05)
	mi2.transform = Transform3D(Basis.looking_at((to - door) / ln, Vector3.UP).scaled(Vector3(1, 1, ln)), (door + to) / 2.0)
	mi2.visible = true
	z["t0"] = _t
	for j in range(6):
		var a := randf() * TAU
		_add_drop(to, Vector3(cos(a) * 2.5, randf_range(2.0, 4.0), sin(a) * 2.5), col)


func _zaps_step() -> void:
	for z in _zaps:
		if (z["mi"] as MeshInstance3D).visible and _t - float(z["t0"]) > ZAP_T:
			(z["mi"] as MeshInstance3D).visible = false


func _drops_step() -> void:
	var keep := []
	var shown := 0
	for d in _drops:
		var age: float = _t - float(d["t0"])
		if age > 1.2:
			continue
		var v: Vector3 = d["v"]
		var p: Vector3 = (d["p"] as Vector3) + v * age + Vector3(0, -9.0 * age * age, 0)
		if p.y < floor_y + 0.05:
			p.y = floor_y + 0.05
		var s := 0.22 * (1.0 - age / 1.2) + 0.05
		_drop_mm.set_instance_transform(shown, Transform3D(Basis.from_scale(Vector3(s, s * (0.6 if p.y <= floor_y + 0.06 else 1.2), s)), p))
		_drop_mm.set_instance_color(shown, d["col"])
		shown += 1
		keep.append(d)
	_drops = keep
	_drop_mm.visible_instance_count = shown


func _splats_step() -> void:
	var keep := []
	var shown := 0
	for s in _splats:
		var age: float = _t - float(s["t0"])
		if age > SPLAT_LIFE:
			continue
		var grow := 1.0 - pow(1.0 - clampf(age / 0.35, 0.0, 1.0), 3.0)
		var size: float = float(s["size"]) * 2.0
		_splat_mm.set_instance_transform(shown, Transform3D(Basis.from_scale(Vector3(size, 1.0, size)).rotated(Vector3.UP, float(s["seed"]) * TAU), s["p"]))
		_splat_mm.set_instance_color(shown, (s["col"] as Color).lerp(NATIVE_GRAY, clampf(age / CLOCK_OUT_T, 0.0, 1.0)))
		_splat_mm.set_instance_custom_data(shown, Color(age / SPLAT_LIFE, s["seed"], grow, 0.0))
		shown += 1
		keep.append(s)
	_splats = keep
	_splat_mm.visible_instance_count = shown
