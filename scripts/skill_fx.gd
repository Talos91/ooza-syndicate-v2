class_name SkillFx
extends Node3D
## Skills 2.0 in the world (0.18.7). Standing rule (Daniele): "every mechanic ships with its animation" -
## and the draft (SKILLS-2.0-DRAFT sec6) asks for effects "readable in one second on a phone": a ring on a
## node, a tinted deck, a relay glow, a ghostly line. Every skill gets a cast moment, a lasting effect that
## drains with its time left, and an end:
##   Surge          speed streaks peeling off the line's bodies, a glow at its head
##   Spore Burst    the vat bubbling over with spores, a ground glow and a time-left ring
##   Fortify        a hexagon shield wall round the platform, draining round the circle; it shatters at the end
##   Scorch         the deck on fire, embers; enemy bodies on it smoulder, and pop one flash per unit it kills
##   Ghost Line     for its OWNER only (Sim.is_ghost_for): translucent flickering bodies (UnitView) and wisps;
##                  everyone else sees a real line. When it pops or lands, a ghostly dissolve everyone sees
##   Demolish       3 s of glowing cracks and a countdown on the deck, then it breaks and its pieces fall into
##                  the void (the bodies on it are the existing pour / fall); a faint outline while it is gone;
##                  the pieces fly back in over its last 1.3 s
##   Mire           sludge and vines spreading over the deck, drained at the end
##   Anchor         bolted rails along the deck, clamps at both ends and on its relay
##   Bypass         the relay glowing, every deck it controls shown at once as a hologram, a time-left ring
##   Relay Hack     fire: blocky static over the relay; jam: a clamp ring and the jam's seconds ("JAM 12")
##   Rewire         every own line streaking; the relays its caster may still fire marked (caster only)
##   Echo Split     split flashes where the echoes leave (caster only); a node an echo hits: static, sparks,
##                  "OFFLINE" and its time-left ring for 8 s
##   Superbloom     every own vat blooming (petals, a ground glow), "+N / 40" over the caster's home
##   Core Meltdown  a sacrifice explosion at the node, defenders blown away, "-N", a capture column if it takes
##   Relay Aegis    a hex dome over each node of the group, locked rails on its decks, clamps on its relays
## POWERS (0.22.2, NEW-POWERS-2026-09-28.md):
##   Quake          the platform's ground cracks from the centre, rumble rings and dust off its rim for the 1.5 s
##                  warning (its countdown over it); every deck touching it cracks and drops like Demolish's; a
##                  time-left band round the platform while it sits cut off
##   Sever          a glowing jagged cut line across the deck's middle, sparks spitting from it, the countdown; then
##                  the deck snaps in two and each half swings down into the void; "CUT" over the gap (relay decks too)
##   Backwash       a goo wave sweeping along the deck toward the lip it shoved the lines back to, a splash at each
##   Sinkhole       a black goo pit opening under the structure (CombatFx plays the old tier sinking, the new rising)
##   Fog of War     a dark churning goo dome over the circle for every rival; the caster's side sees a faint veil;
##                  a time-left band round its foot for everyone. Rivals' counts / lines inside are hidden elsewhere
##                  (Hud badges, HordeView / UnitView bodies); this view skips a rival's own-thing cast moments,
##                  streaks and line marks inside it too
##   Portal         a vortex on the entrance and one turning the other way on the exit, sparks streaming along an arc
##                  between them, IN / OUT over them, a time-left band; a flash at the exit as each line comes out
##   Emergency Evac a burst at the node's door; the line wears a pale shield shimmer until it lands
##   Core Meltdown  armed from the start of the trip: a pulsing ember aura at the line's head, embers along it and
##                  "ARMED" over it (everyone sees it); "FIZZLED" and a puff of smoke if its target turns friendly
## Ultimates also tint the screen's edges in the caster's colour for a moment (a CanvasLayer under the HUD
## that ignores the mouse: it never blocks input); every cast shows its name over the target.
## Pure view, like CombatFx / ForgePulse: driven only by the Sim's state (sim.effects, sim.demolished,
## the readouts) and its fx events ("skill", "skill_end", "demolish", "deck_rebuilt", "demolish_failed",
## "relay_settle", "meltdown", "disrupt", "ghost_end", "ghosts"; POWERS: "backwash", "sinkhole", "portal_pass",
## "evac", "meltdown_fizzled"), so online guests, who apply the host's
## snapshots and get its events, see the same. An event marked "private" for another seat is skipped.
## Budget: every mesh is made once per node / deck / effect slot and reused (hidden when idle); the deck
## strips are built once per deck; bursts, rings and labels come from small pools; sparks are one MultiMesh.

const FX_SHADER := preload("res://shaders/skill_fx.gdshader")
const SLUDGE_SHADER := preload("res://shaders/skill_sludge.gdshader")
const TINT_SHADER := preload("res://shaders/skill_tint.gdshader")
const FLARE_SHADER := preload("res://shaders/flare.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")   # Hud.UI_FONT (not referenced: the headless tests load this without the HUD)
const POWER_SHADER := preload("res://shaders/skill_powers.gdshader")   # POWERS: quake cracks, portal swirl, Sever's cut, Backwash's wave
const DARK_SHADER := preload("res://shaders/skill_dark.gdshader")      # POWERS: the fog cloud, the sinkhole pit

const IDS := ["surge", "spore_burst", "fortify", "scorch", "ghost_line", "demolish", "mire", "anchor", "bypass",
		"relay_hack", "rewire", "echo_split", "superbloom", "core_meltdown", "relay_aegis",
		"quake", "sever", "fog", "portal"]         # POWERS: the new powers with a lasting effect (Backwash, Sinkhole, Evac: moments)
const DECK_DROPS := ["demolish", "quake", "sever"]   # POWERS: Sim.DECK_DROPS - one deck-drop look for all three
const ONS := ["node", "edge", "horde", "relay", "seat"]
const SEATS := "ABCDEFGH"
# skill_fx.gdshader modes
const M_FIRE := 0
const M_CRACKS := 1
const M_LOCK := 2
const M_HOLO := 3
const M_HEX := 4
const M_GLITCH := 5
const M_CLAMP := 6
const M_ARC := 7

const DECK_W := 3.4                 # m: the strip over a deck (the kit's deck is ~3 m wide)
const STRIP_Y := 0.16               # m above the deck line
const WALL_H := 3.6                 # m: Fortify's wall
const FADE_IN := 0.3                # s: a lasting effect comes in
const FADE_OUT := 0.45              # s: and goes
const BREAK_T := 1.8                # s: a demolished deck's pieces fall
const REBUILD_T := 1.3              # s: they fly back in over the deck's last seconds
const TINT_T := 1.1                 # s: an ultimate's screen-edge tint
const MAX_SPARKS := 480
const HOT := Color(1.0, 0.9, 0.72)
const FIRE := Color(1.0, 0.42, 0.08)
const SPORE := Color(0.82, 1.0, 0.45)
const PETAL := Color(1.0, 0.55, 0.85)
const WISP := Color(0.78, 0.95, 1.0)
const SMOKE := Color(0.32, 0.3, 0.34)
# the pieces' fixed shader settings (const tables: a piece is made from one on first use)
const P_NONE := {}
const P_STAR := {"mode": 0}
const P_GROUND := {"mode": 1}
const P_ARC := {"mode": M_ARC}
const P_WALL := {"mode": M_HEX, "tiles": Vector2(48.0, 5.0)}
const P_DOME := {"mode": M_HEX, "tiles": Vector2(40.0, 9.0)}
const P_FIRE := {"mode": M_FIRE, "color2": FIRE}
const P_CRACKS := {"mode": M_CRACKS}
const P_LOCK := {"mode": M_LOCK}
const P_HOLO := {"mode": M_HOLO}
const P_CLAMP := {"mode": M_CLAMP}
const P_HACK := {"mode": M_GLITCH, "color2": Color(0.6, 1.0, 1.0), "heat": 0.8}
const P_JAMMED := {"mode": M_GLITCH, "color2": Color(1.0, 0.25, 0.3), "heat": 0.45}
# POWERS: skill_powers.gdshader / skill_dark.gdshader settings
const P_QUAKE := {"mode": 0}
const P_SWIRL := {"mode": 1}
const P_CUT := {"mode": 2}
const P_WAVE := {"mode": 3}
const P_FOG_DOME := {"mode": 0}
const P_FOG_DISC := {"mode": 1}
const P_HOLE := {"mode": 2}
const EMBER := Color(1.0, 0.5, 0.12)
const SHIELD := Color(0.8, 0.97, 1.0)
const WAVE_T := 0.9                 # s: Backwash's wave runs the deck
const HOLE_T := 2.4                 # s: Sinkhole's pit opens, holds and closes
const _BIG := AABB(Vector3(-2000, -400, -2000), Vector3(4000, 800, 4000))

var sim: Sim
var vis: Dictionary
var viewer := ""                    # whose screen this is (main.HUMAN)
var stats := {}                     # counters the tests read: "cast_<id>", "slot_<id>", "break", "rebuild", ...
var _cam: Camera3D
var _frame := 0
var _t := 0.0                       # this view's own clock (a guest's sim time steps with snapshots)
var _slots := {}                    # int key (_key) -> the visuals of one running effect
var _lines := {}                    # edge -> [PackedVector3Array pts, PackedFloat32Array cum, total]: deck centre lines
var _strips := {}                   # edge -> ArrayMesh: the deck strip, built once
var _hordes := {}                   # horde id -> horde (as of this frame): an event may name a line already gone
var _pieces := {}                   # edge -> [{node, mis, base, u, v, spin}]: copies of the deck's pieces (Demolish)
var _breaks := {}                   # edge -> seconds since it broke (its pieces falling)
var _markers := {}                  # relay id -> {ring, rmat, chev, seen}: Rewire's relays you may fire
var _blooms := {}                   # node id -> {glow, gmat, seen}: Superbloom's vats
var _stars: Array = []              # pooled bursts: {mi, mat, t, dur, pos, s0, s1, col, i0}
var _rings: Array = []              # pooled shock rings
var _labels: Array = []             # pooled rising labels: {l, t, dur, pos, rise, col, frac}
var _star_i := 0
var _ring_i := 0
var _label_i := 0
var _tint_rect: ColorRect
var _tint_mat: ShaderMaterial
var _tint_t := -1.0
var _annulus: ArrayMesh
var _wall: ArrayMesh
var _dome: ArrayMesh
var _plane: PlaneMesh
var _quad: QuadMesh
var _mm: MultiMesh
var _sp_pos := PackedVector3Array()
var _sp_vel := PackedVector3Array()
var _sp_col := PackedColorArray()
var _sp_life := PackedFloat32Array()
var _sp_max := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_grav := PackedFloat32Array()
var _sp_n := 0
var _waves := {}                    # POWERS: edge -> {mi, mat, t, dir, col}: Backwash's wave (t < 0: idle)
var _holes := {}                    # POWERS: node id -> {mi, mat, t, col}: Sinkhole's pit
var _marks := {}                    # POWERS: horde id -> {star, smat, lab, seen}: an armed (Core Meltdown) / immune (Evac) line


static var _ghost_shader: Shader


static func ghost_shader() -> Shader:
	## UnitView's Ghost Line column: the creature shader (Mats.CREATURE_SHADER, unchanged) made see-through,
	## with a cold ghostly glow as it fades.
	if _ghost_shader == null:
		var code: String = Mats.CREATURE_SHADER.code
		code = code.replace("shader_type spatial;", "shader_type spatial;
render_mode depth_draw_always;
uniform float ghost_alpha = 0.5;")
		var at := code.rfind("}")
		code = code.substr(0, at) + "	ALPHA = ghost_alpha;
	EMISSION += vec3(0.3, 0.55, 0.7) * (1.0 - ghost_alpha);
" + code.substr(at)
		_ghost_shader = Shader.new()
		_ghost_shader.code = code
	return _ghost_shader


static func ghost_alpha(time: float, id: int) -> float:
	## UnitView: how see-through its owner's Ghost Line bodies are this frame (1 - their alpha):
	## about half, breathing, with a quick flicker now and then.
	var k := 0.62 + 0.1 * sin(time * 5.0 + id) + 0.06 * sin(time * 13.0 + id * 1.7)
	if fposmod(time * 1.3 + id * 0.37, 1.0) < 0.07:
		k += 0.3
	return clampf(k, 0.4, 0.92)


func setup(s: Sim, v: Dictionary, who: String) -> void:
	sim = s
	vis = v
	viewer = who
	_annulus = _annulus_mesh(0.86, 72)
	_wall = _wall_mesh(64)
	_dome = _dome_mesh(48, 12)
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1.0, 1.0)
	_quad = QuadMesh.new()
	for i in range(24):
		_stars.append(_flare_entry(_quad, 0))
	for i in range(14):
		_rings.append(_flare_entry(_plane, 2))
	for i in range(8):
		_labels.append({"l": _new_label(96), "t": 0.0, "dur": 0.0, "pos": Vector3.ZERO, "rise": 0.0, "col": Color.WHITE, "frac": 0.05})
	_sp_pos.resize(MAX_SPARKS)
	_sp_vel.resize(MAX_SPARKS)
	_sp_col.resize(MAX_SPARKS)
	_sp_life.resize(MAX_SPARKS)
	_sp_max.resize(MAX_SPARKS)
	_sp_size.resize(MAX_SPARKS)
	_sp_grav.resize(MAX_SPARKS)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _quad
	_mm.instance_count = MAX_SPARKS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var sm := ShaderMaterial.new()
	sm.shader = SPARK_SHADER
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = _BIG
	add_child(mmi)
	var layer := CanvasLayer.new()                     # the ultimate's tint: under the HUD (layer 1), never takes input
	layer.layer = 0
	add_child(layer)
	_tint_rect = ColorRect.new()
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint_mat = ShaderMaterial.new()
	_tint_mat.shader = TINT_SHADER
	_tint_rect.material = _tint_mat
	_tint_rect.visible = false
	layer.add_child(_tint_rect)


# ------------------------------------------------------------------ events
func handle(ev: Dictionary) -> void:
	if ev.has("private") and str(ev["private"]) != viewer:
		return                                        # another seat's secret (a Ghost Line, its echoes)
	match str(ev.get("type", "")):
		"skill":
			_on_cast(ev)
		"skill_end":
			_on_end(ev)
		"demolish":                                   # (POWERS: Quake / Sever send it too, with their "id")
			_break(int(ev["edge"]), str(ev.get("seat", "")), str(ev.get("id", "demolish")))
		"deck_rebuilt":
			_rebuilt(int(ev["edge"]))
		"demolish_failed":
			var ei := int(ev["edge"])
			var mid := _deck_at(ei, 0.5) + Vector3(0, 0.6, 0)
			_star_at(mid, HOT, 7.0, 0.4)
			_ring_at(mid, Color(0.85, 0.9, 1.0), 9.0, 0.5)
			_label_at("HELD", mid + Vector3(0, 4.0, 0), Color(0.85, 0.9, 1.0), 1.2, 0.04)
			_burst(mid, Color(0.85, 0.9, 1.0), 26, 7.0, 0.5, 14.0)
			_count_stat("held")
		"relay_settle":
			for ei in ev.get("closing", []):
				for k in range(8):
					_spark(_deck_at(int(ei), randf()) + Vector3(0, 0.4, 0), Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)),
							Rules.state_color("warn"), randf_range(0.18, 0.3), randf_range(0.4, 0.7), 10.0)
		"meltdown":
			_meltdown(ev)
		"disrupt":
			var n: Dictionary = sim.nodes[int(ev["node"])]
			var col := Rules.seat_color(str(ev.get("seat", "")))
			_star_at(n["pos"] + Vector3(0, 4.0, 0), col.lerp(Color.WHITE, 0.3), 10.0, 0.45)
			_ring_at(n["pos"], col, Rules.R * 2.6, 0.6)
			_burst(n["pos"] + Vector3(0, 3.0, 0), col, 30, 8.0, 0.45, 8.0)
			_count_stat("disrupt")
		"ghost_end":
			_ghost_end(ev)
		"ghosts":                                     # Echo Split, caster only: where each echo leaves
			for hid in ev.get("hids", []):
				var h := sim._horde(int(hid))
				if h.is_empty():
					continue
				var src: Vector3 = sim.nodes[h["route"][0]]["pos"]
				_star_at(src + Vector3(0, 2.5, 0), WISP, 8.0, 0.5)
				_ring_at(src, WISP, Rules.R * 2.2, 0.6)
				_wisps_at(src + Vector3(0, 1.5, 0), 22, Rules.seat_color(str(ev.get("seat", ""))))
			_count_stat("echoes")
		# POWERS (0.22.2): the new powers' moments
		"backwash":
			_backwash(ev)
		"sinkhole":
			_sinkhole(ev)
		"portal_pass":                                # a line pours into the entrance and comes out of the exit
			var seat := str(ev.get("seat", ""))
			var col := Rules.seat_color(seat)
			var a: Vector3 = sim.nodes[int(ev["node"])]["pos"]
			var b: Vector3 = sim.nodes[int(ev["exit"])]["pos"]
			if not _fogged(a, seat):
				_ring_at(a, col.lerp(Color.WHITE, 0.3), Rules.R * 1.6, 0.45)
			if not _fogged(b, seat):
				_star_at(b + Vector3(0, 2.5, 0), col.lerp(Color.WHITE, 0.4), 11.0, 0.5)
				_ring_at(b, col, Rules.R * 2.4, 0.6)
				_burst(b + Vector3(0, 1.5, 0), col.lerp(Color.WHITE, 0.2), 30, 9.0, 0.5, 6.0)
			_count_stat("portal_pass")
		"evac":                                       # the garrison bursts out of the door, shielded
			var seat := str(ev.get("seat", ""))
			var n: Dictionary = sim.nodes[int(ev["node"])]
			var door: Vector3 = n["pos"] + Rules.front_dir() * (Rules.EXIT_R + 0.4) + Vector3(0, 1.0, 0)
			if not _fogged(n["pos"], seat):
				var col := Rules.seat_color(seat)
				_star_at(door + Vector3(0, 0.8, 0), SHIELD, 12.0, 0.5)
				_ring_at(n["pos"], SHIELD.lerp(col, 0.4), Rules.R * 2.2, 0.6)
				_burst(door, SHIELD.lerp(col, 0.3), 34, 11.0, 0.55, 6.0)
			_count_stat("evac")
		"meltdown_fizzled":                           # its target turned friendly first: the charge goes out
			var h = _hordes.get(int(ev.get("hid", -1)))
			if h is Dictionary and not (h as Dictionary).is_empty():
				var head: Vector3 = Sim.sample(h, h["s"])[0]
				if not _fogged(head, str(ev.get("seat", ""))):
					for k in range(24):
						_spark(head + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)), Vector3(randf_range(-0.8, 0.8), randf_range(1.5, 3.0), randf_range(-0.8, 0.8)),
								SMOKE, randf_range(0.4, 0.7), randf_range(0.7, 1.2), -0.5)
					_label_at("FIZZLED", head + Vector3(0, 5.0, 0), SMOKE.lerp(Color.WHITE, 0.5), 1.2, 0.04)
			_count_stat("fizzled")


static func touches(ev: Dictionary, s: Sim, viewer: String) -> bool:
	## A rival's skill that touches `viewer` (SkillDock.on_event names it in a callout at ev["pos"]; _on_cast then leaves out
	## its floating name there, which the callout covered - the Last Stand SCORCH shots).
	if ev.has("private") and str(ev["private"]) != viewer:
		return false
	var seat := str(ev.get("seat", ""))
	if seat == "" or seat == viewer or s.allied(seat, viewer):
		return false
	var hit: Array = ev.get("affects", []) if ev.get("affects", []) is Array else []
	return viewer in hit


func _on_cast(ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	var seat := str(ev.get("seat", ""))
	var col := Rules.seat_color(seat)
	var up := Vector3.UP
	_count_stat("cast_" + id)
	if ev.has("fire"):                                # Rewire firing a relay
		var r: Dictionary = sim.nodes[int(ev["fire"])]
		_star_at(r["pos"] + up * 6.0, col.lerp(Color.WHITE, 0.3), 12.0, 0.45)
		_ring_at(r["pos"], col, Rules.R * 2.4, 0.55)
		_glitch_burst(r["pos"], col, 36)
		_label_at("REWIRE", r["pos"] + up * 9.0, col, 1.1, 0.04)
		return
	var pos = ev.get("pos", null)
	if not pos is Vector3:
		pos = _target_pos(ev)
	var p: Vector3 = pos
	var ult := str(ev.get("slot", "")) == "ultimate"
	var kind := str(Rules.SKILLS.get(id, {}).get("target", ""))   # POWERS: a rival's cast on its own things inside
	if kind in ["own_line", "own_node", "own_vat"] and _fogged(p, seat):   # a fog you are blind to shows nothing
		return
	if id != "core_meltdown":                         # (its blast is the "meltdown" event's)
		_star_at(p + up * 2.0, col.lerp(Color.WHITE, 0.25), 16.0 if ult else 9.0, 0.55 if ult else 0.4)
		_ring_at(p, col, Rules.R * (3.4 if ult else 1.9), 0.8 if ult else 0.55)
	var name := str(Rules.SKILLS.get(id, {}).get("name", id)).to_upper()
	if not (ev.get("pos") is Vector3 and touches(ev, sim, viewer)):   # (else the callout there names it)
		_label_at(name, p + up * (8.0 if ult else 6.0), col, 1.5 if ult else 1.2, 0.06 if ult else 0.045)
	if ult:
		_tint_on(col)
		_burst(p + up * 2.0, col, 40, 12.0, 0.7, 10.0)
	match id:
		"surge":
			var h := sim._horde(_int(ev.get("target")))
			if not h.is_empty():
				_streaks(h, col, 400.0, 0.1)
		"spore_burst":
			_burst(p + up * 4.5, SPORE, 28, 5.0, 1.0, -1.0)
		"scorch":
			var ei := _int(ev.get("target"))
			for k in range(30):
				_spark(_deck_at(ei, randf()) + up * 0.4, Vector3(randf_range(-1, 1), randf_range(4, 9), randf_range(-1, 1)),
						FIRE if randf() < 0.6 else HOT, randf_range(0.25, 0.45), randf_range(0.4, 0.8), 6.0)
		"mire":
			var ei := _int(ev.get("target"))
			for k in range(20):
				_spark(_deck_at(ei, 0.5 + randf_range(-0.2, 0.2)) + up * 0.5, Vector3(randf_range(-4, 4), randf_range(2, 5), randf_range(-4, 4)),
						col * 0.8, randf_range(0.3, 0.5), randf_range(0.4, 0.7), 16.0)
		"anchor":
			var ei := _int(ev.get("target"))
			for u in [0.0, 1.0]:
				_burst(_deck_at(ei, u) + up * 0.6, HOT, 16, 7.0, 0.35, 16.0)
		"demolish":
			var ei := _int(ev.get("target"))
			_burst(_deck_at(ei, 0.5) + up * 0.5, Rules.state_color("warn"), 18, 5.0, 0.5, 12.0)
		"bypass", "relay_hack":
			var rt = ev.get("target")
			var rid := _int(rt[0] if rt is Array and not (rt as Array).is_empty() else rt)
			if rid >= 0 and rid < sim.nodes.size():
				_glitch_burst(sim.nodes[rid]["pos"], col, 30)
				if rt is Array and (rt as Array).size() > 1 and str(rt[1]) == "jam":
					_label_at("+%d s" % int(Rules.SKILLS["relay_hack"]["jam"]), sim.nodes[rid]["pos"] + up * 10.5, col, 1.4, 0.05)
		"superbloom":
			for n in sim.nodes:
				if n["owner"] == seat and Sim.has_vat(n) and not sim.collapsed.get(n["id"], false):
					_burst(n["pos"] + up * 4.5, PETAL.lerp(col, 0.4), 14, 5.0, 0.9, 2.0)
		"relay_aegis":
			var n: Dictionary = sim.nodes[clampi(_int(ev.get("target")), 0, sim.nodes.size() - 1)]
			_ring_at(n["pos"], col.lerp(Color.WHITE, 0.3), Rules.R * 4.5, 0.9)
		# POWERS (0.22.2)
		"core_meltdown":                              # armed at the start of the trip (the blast is "meltdown"'s)
			_star_at(p + up * 1.5, EMBER, 10.0, 0.5)
			_burst(p + up * 1.2, EMBER, 26, 7.0, 0.6, 4.0)
		"quake":                                      # the ground heaves: dust off the rim, a heavy ring
			_ring_at(p, Rules.state_color("warn"), Rules.R * 3.2, 0.7)
			for k in range(36):
				var a := randf() * TAU
				var d := Vector3(cos(a), 0.0, sin(a))
				_spark(p + d * Rules.R * randf_range(0.8, 1.05) + up * 0.4, d * randf_range(1.0, 3.0) + up * randf_range(3.0, 6.0),
						Color(0.62, 0.6, 0.66), randf_range(0.3, 0.5), randf_range(0.6, 1.0), 14.0)
		"sever":
			var ei := _int(ev.get("target"))
			_burst(_deck_at(ei, 0.5) + up * 0.5, col.lerp(HOT, 0.4), 22, 7.0, 0.45, 12.0)
		"fog":                                        # the cloud rolls out from the centre
			for k in range(30):
				var a := randf() * TAU
				var d := Vector3(cos(a), 0.0, sin(a))
				_spark(p + up * 1.0, d * randf_range(8.0, 16.0) + up * randf_range(0.5, 2.0), col * 0.7, randf_range(0.4, 0.7), randf_range(0.6, 1.0), 2.0)
		"portal":
			var t = ev.get("target")
			if t is Array and (t as Array).size() > 1:
				var b: Vector3 = sim.nodes[_int(t[1])]["pos"]
				_star_at(b + up * 2.0, col.lerp(Color.WHITE, 0.25), 9.0, 0.4)
				_ring_at(b, col, Rules.R * 1.9, 0.55)


func _on_end(ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	var col := Rules.seat_color(str(ev.get("seat", "")))
	var on := str(ev.get("on", ""))
	var tgt = ev.get("target")
	_count_stat("end_" + id)
	var up := Vector3.UP
	if on == "node" or on == "relay":
		var i := _int(tgt)
		if i < 0 or i >= sim.nodes.size():
			return
		var c: Vector3 = sim.nodes[i]["pos"]
		match id:
			"fortify":                                # the shield shatters
				for k in range(48):
					var a := randf() * TAU
					var d := Vector3(cos(a), 0.0, sin(a))
					_spark(c + d * (Rules.R + 0.6) + up * randf_range(0.3, WALL_H), d * randf_range(3.0, 7.0) + up * randf_range(0.5, 3.0),
							col.lerp(Color.WHITE, randf() * 0.5), randf_range(0.2, 0.36), randf_range(0.4, 0.8), 14.0)
			"relay_aegis":
				_ring_at(c, col, Rules.R * 3.0, 0.5)
				_burst(c + up * (Rules.R * 0.8), col, 24, 7.0, 0.6, 8.0)
			"bypass", "relay_hack", "echo_split":
				_ring_at(c, col, Rules.R * 2.0, 0.4)
	elif on == "edge":
		var ei := _int(tgt)
		match id:
			"scorch":                                 # the fire dies in smoke
				for k in range(26):
					_spark(_deck_at(ei, randf()) + up * 0.5, Vector3(randf_range(-0.6, 0.6), randf_range(1.5, 3.0), randf_range(-0.6, 0.6)),
							SMOKE, randf_range(0.5, 0.8), randf_range(0.8, 1.3), -0.5)
			"anchor", "relay_aegis":                  # the bolts pop
				for u in [0.0, 1.0]:
					_burst(_deck_at(ei, u) + up * 0.6, col.lerp(Color.WHITE, 0.4), 10, 6.0, 0.35, 14.0)


func _meltdown(ev: Dictionary) -> void:
	## Core Meltdown: the sacrifice blows up at the node; its defenders are thrown out; a capture flashes.
	var n: Dictionary = sim.nodes[int(ev["node"])]
	var col := Rules.seat_color(str(ev.get("seat", "")))
	var c: Vector3 = n["pos"]
	var up := Vector3.UP
	var took := bool(ev.get("captured", false))
	var def := Rules.NEUTRAL if took or n["owner"] == "" else Rules.seat_color(n["owner"])
	var detail := 0.6 if Rules.low_detail else 1.0
	_star_at(c + up * 3.5, HOT, 17.0, 0.55)
	_star_at(c + up * 3.0, col, 12.0, 0.8)
	_ring_at(c, FIRE.lerp(col, 0.4), Rules.R * 5.0, 0.9)
	_ring_at(c, col.lerp(Color.WHITE, 0.3), Rules.R * 3.0, 0.6)
	for k in range(int(90 * detail)):
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized() * randf_range(8.0, 22.0)
		var roll := randf()
		_spark(c + up * 3.0, v, HOT if roll < 0.35 else (FIRE if roll < 0.65 else col), randf_range(0.25, 0.6), randf_range(0.5, 1.1), 14.0)
	var killed := int(ev.get("killed", 0))
	for k in range(int(clampi(killed, 6, 40) * detail)):       # the defenders blown off the platform
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		_spark(c + d * randf_range(1.0, 3.5) + up * 1.0, d * randf_range(9.0, 16.0) + up * randf_range(5.0, 10.0), def,
				randf_range(0.5, 0.8), randf_range(0.9, 1.5), 18.0)
	_label_at("-%d" % killed, c + up * 4.5, FIRE.lerp(HOT, 0.3), 1.8, 0.06)      # (the cast shows the name above)
	if took:
		_label_at("CAPTURED", c + up * 14.0, col.lerp(Color.WHITE, 0.2), 1.8, 0.05)
		_ring_at(c, col.lerp(Color.WHITE, 0.5), Rules.R * 2.2, 1.2)
		for k in range(int(40 * detail)):                           # the capture column
			_spark(c + Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 2.0), randf_range(-1.5, 1.5)), up * randf_range(12.0, 22.0),
					col.lerp(Color.WHITE, randf() * 0.6), randf_range(0.35, 0.6), randf_range(0.5, 0.9), 0.0)
	_tint_on(col)
	_count_stat("meltdown")


func _ghost_end(ev: Dictionary) -> void:
	## A Ghost Line (or an echo) popped on contact or landed: a ghostly dissolve that EVERYONE sees - its
	## bodies thin into wisps along the line, or at the door it poured into.
	var h = _hordes.get(int(ev.get("hid", -1)))
	var seat := str(ev.get("seat", ""))
	var col := Rules.seat_color(seat)
	_count_stat("ghost_end")
	if str(ev.get("why", "")) == "landed" and ev.has("node"):
		var n: Dictionary = sim.nodes[int(ev["node"])]
		var door: Vector3 = n["pos"] + Rules.front_dir() * (Rules.EXIT_R + 0.4) + Vector3(0, 1.0, 0)
		_star_at(door, WISP, 7.0, 0.6)
		_wisps_at(door, 26, col)
		if not h is Dictionary:
			return
	if not h is Dictionary or (h as Dictionary).is_empty():
		return
	var hd: Dictionary = h
	var length := _line_len(hd)
	var head: Vector3 = Sim.sample(hd, hd["s"])[0]
	_star_at(head + Vector3(0, 1.2, 0), WISP, 8.0, 0.6)
	_ring_at(head, WISP, 6.0, 0.6)
	for k in range(int(40 * (0.6 if Rules.low_detail else 1.0))):
		var p: Vector3 = Sim.sample(hd, hd["s"] - randf() * length)[0]
		_spark(p + Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.4), randf_range(-1.0, 1.0)),
				Vector3(randf_range(-0.8, 0.8), randf_range(1.5, 3.5), randf_range(-0.8, 0.8)),
				WISP.lerp(col, randf() * 0.5), randf_range(0.3, 0.55), randf_range(0.7, 1.2), -1.5)


# ------------------------------------------------------------------ POWERS (0.22.2): the new powers
func _fogged(pos: Vector3, seat: String) -> bool:
	## Is this a rival's thing inside a Fog of War this screen is blind to? (Sim.fog_hides; your own side's stays shown.)
	return viewer != "" and seat != "" and not sim.allied(seat, viewer) and sim.fog_hides(pos, viewer)


func _countdown(slot: Dictionary, lab: Label3D, left_s: float, at: Vector3, heat: float, life: float) -> void:
	## The warning's seconds over a deck or a platform, blinking faster toward the drop (Demolish's).
	var warn := Rules.state_color("warn")
	var sec := int(ceil(maxf(left_s, 0.01)))
	if slot["txt"] != sec:
		slot["txt"] = sec
		lab.text = str(sec)
	_size_label(lab, at, 0.07 * (1.0 + 0.25 * (1.0 - fposmod(left_s, 1.0))))
	lab.visible = true
	var blink := 0.55 + 0.45 * float(int(_t * (4.0 + 10.0 * heat)) % 2)
	Mats.label_look(lab, Color(warn.lerp(Color.WHITE, 0.15), blink * life), 0.95 * blink * life)


func _deck_drop(slot: Dictionary, e: Dictionary, dt: float, col: Color, life: float, detail: float) -> void:
	## Demolish / Quake / Sever on a deck - one look (Demolish's): the warning's glowing cracks and countdown, then a
	## faint outline while it is gone and its pieces flying back in over the last seconds. Sever: a jagged cut line
	## glows across the middle through the warning (the rest of the deck barely cracks) and "CUT" hangs over the gap;
	## Quake: the countdown is over its platform (_quake_node), not on each deck.
	var id: String = slot["id"]
	var ei := _int(e["target"])
	var phase := str(e.get("phase", "warning"))
	var up := Vector3.UP
	var s := _strip_part(slot, "a", ei, FX_SHADER, P_CRACKS, float(ei) * 1.7)
	if s == null:
		return
	var m := _mat(slot, "a")
	var warn := Rules.state_color("warn")
	var sever := id == "sever"
	if phase != slot["phase"]:
		slot["phase"] = phase
		slot["txt"] = -1
		m.set_shader_parameter("mode", M_CRACKS if phase == "warning" else M_HOLO)
	var lab := _slot_label(slot)
	if phase == "warning":
		var heat := clampf(1.0 - float(slot["tl"]) / float(Rules.SKILLS[id]["warn"]), 0.0, 1.0)
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("color2", warn)
		m.set_shader_parameter("heat", heat * (0.3 if sever else 1.0))
		m.set_shader_parameter("intensity", (0.55 if sever else 1.3) * life)
		var mid := _deck_at(ei, 0.5)
		if sever:
			_strip_part(slot, "c", ei, POWER_SHADER, P_CUT, float(ei) * 2.3)
			var cm := _mat(slot, "c")
			cm.set_shader_parameter("color", col.lerp(HOT, 0.3))
			cm.set_shader_parameter("heat", heat)
			cm.set_shader_parameter("intensity", 1.5 * life)
			for k in range(_count((14.0 + 50.0 * heat) * detail * dt)):   # sparks spitting from the cut
				_spark(mid + Vector3(randf_range(-1.3, 1.3), 0.3, randf_range(-1.3, 1.3)), Vector3(randf_range(-3, 3), randf_range(2, 6), randf_range(-3, 3)),
						HOT if randf() < 0.5 else col.lerp(HOT, 0.5), randf_range(0.14, 0.26), randf_range(0.25, 0.5), 14.0)
		if id == "quake":
			lab.visible = false
		else:
			_countdown(slot, lab, float(slot["tl"]), mid + up * 5.0, heat, life)
		for k in range(_count((8.0 + 40.0 * heat) * detail * dt)):   # grit shaking off the deck
			_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.4, 1.4), 0.2, randf_range(-1.4, 1.4)),
					Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 2.0), randf_range(-0.5, 0.5)),
					warn.lerp(HOT, randf() * 0.6), randf_range(0.14, 0.26), randf_range(0.3, 0.6), 12.0)
	else:
		_hide_part(slot, "c")
		if sever:                                     # the gap reads CUT (relay decks too) until it is back
			if slot["txt"] != 0:
				slot["txt"] = 0
				lab.text = "CUT"
			lab.visible = true
			Mats.label_look(lab, Color(col.lerp(Color.WHITE, 0.3), 0.85 * life), 0.9 * life)
			_size_label(lab, _deck_at(ei, 0.5) + up * 3.0, 0.03)
		else:
			lab.visible = false
		m.set_shader_parameter("color", col.lerp(Color.WHITE, 0.25))
		m.set_shader_parameter("intensity", (0.22 + 0.08 * sin(_t * 4.0)) * life)
		if float(slot["tl"]) < REBUILD_T and not _breaks.has(ei):
			_rebuild_pieces(ei, 1.0 - clampf(float(slot["tl"]) / REBUILD_T, 0.0, 1.0))
		elif not _breaks.has(ei):
			_hide_pieces(ei)
		for k in range(_count(3.0 * detail * dt)):   # embers on the broken ends (Sever: on the cut)
			var u := (0.48 + randf() * 0.04) if sever else (0.02 if randf() < 0.5 else 0.98)
			_spark(_deck_at(ei, u) + up * 0.3, Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1)),
					FIRE.lerp(col, 0.4), randf_range(0.14, 0.24), randf_range(0.4, 0.8), 8.0)


func _quake_node(slot: Dictionary, e: Dictionary, dt: float, col: Color, life: float, detail: float) -> void:
	## Quake on its platform: the ground cracks open from the centre, rumble rings and dust shaken off the rim through
	## the warning (its countdown over it); then a time-left band round the platform while it sits cut off.
	var n: Dictionary = sim.nodes[_int(e["target"])]
	var up := Vector3.UP
	var warn_s := float(Rules.SKILLS["quake"]["warn"])
	var dur := maxf(float(e.get("dur", 1.0)), 0.001)
	var age := dur - float(slot["tl"])
	var warning := age < warn_s
	var heat := clampf(age / warn_s, 0.0, 1.0)
	var warn := Rules.state_color("warn")
	var g := _plane_part(slot, "a", POWER_SHADER, P_QUAKE, float(n["id"]) * 0.37)
	var shake := Vector3(sin(_t * 53.0), 0.0, cos(_t * 47.0)) * (0.3 * heat if warning else 0.0)
	g.position = n["pos"] + up * 0.42 + shake
	g.scale = Vector3.ONE * Rules.R * 2.3
	var m := _mat(slot, "a")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("color2", warn)
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("intensity", (1.4 if warning else 0.45) * life)
	var lab := _slot_label(slot)
	if warning:
		_hide_part(slot, "b")
		slot["acc"] = float(slot["acc"]) + dt
		if float(slot["acc"]) >= 0.3:                 # a rumble ring every 0.3 s
			slot["acc"] = 0.0
			_ring_at(n["pos"], warn.lerp(Color(0.8, 0.8, 0.85), 0.4), Rules.R * (1.4 + 0.6 * heat), 0.45)
		for k in range(_count((20.0 + 60.0 * heat) * detail * dt)):   # dust shaken off the rim
			var a := randf() * TAU
			var d := Vector3(cos(a), 0.0, sin(a))
			_spark(n["pos"] + d * Rules.R * randf_range(0.85, 1.05) + up * 0.4, d * randf_range(0.5, 2.0) + up * randf_range(1.5, 4.0),
					Color(0.62, 0.6, 0.66) if randf() < 0.7 else warn, randf_range(0.25, 0.45), randf_range(0.5, 0.9), 12.0)
		_countdown(slot, lab, warn_s - age, n["pos"] + up * 2.5, heat, life)   # (under the cast's name)
	else:
		lab.visible = false
		_arc(slot, "b", n, col, clampf(float(slot["tl"]) / maxf(dur - warn_s, 0.01), 0.0, 1.0), 1.1 * life)


func _fog(slot: Dictionary, e: Dictionary, col: Color, life: float, left: float, age: float) -> void:
	## Fog of War: a dark churning goo dome over the circle for every seat outside the caster's side (what is inside is
	## hidden by the HUD and the line views); the caster's side sees a faint veil. A time-left band round its foot.
	var n: Dictionary = sim.nodes[_int(e["target"])]
	var r := float(e.get("radius", 30.0))
	var blind := viewer != "" and not sim.allied(str(e["seat"]), viewer)
	var grow := smoothstep(0.0, 1.0, minf(age / 0.6, 1.0))
	var d := _part(slot, "a", _dome, DARK_SHADER, P_FOG_DOME, float(n["id"]) * 0.21)
	d.visible = true
	d.position = n["pos"] + Vector3(0, -0.6, 0)
	d.scale = Vector3(r * lerpf(0.25, 1.0, grow), (11.0 if blind else 7.0) * lerpf(0.3, 1.0, grow), r * lerpf(0.25, 1.0, grow))
	slot["adark"] = 0.9 if blind else 0.16
	var dm := _mat(slot, "a")
	dm.set_shader_parameter("color", col)
	dm.set_shader_parameter("alpha", float(slot["adark"]) * life)
	var f := _plane_part(slot, "b", DARK_SHADER, P_FOG_DISC, float(n["id"]) * 0.53)
	f.position = n["pos"] + Vector3(0, 0.45, 0)
	f.scale = Vector3.ONE * 2.0 * r * lerpf(0.25, 1.0, grow)
	slot["bdark"] = 0.75 if blind else 0.08
	var fm := _mat(slot, "b")
	fm.set_shader_parameter("color", col)
	fm.set_shader_parameter("alpha", float(slot["bdark"]) * life)
	var a := _part(slot, "c", _annulus, FX_SHADER, P_ARC)
	a.visible = true
	a.position = n["pos"] + Vector3(0, 0.5, 0)
	a.scale = Vector3.ONE * r * lerpf(0.25, 1.0, grow)
	a.rotation.y = -Rules.view_yaw - PI / 2.0
	var am := _mat(slot, "c")
	am.set_shader_parameter("color", col)
	am.set_shader_parameter("left", left)
	am.set_shader_parameter("intensity", (0.8 if blind else 1.4) * life)


func _portal(slot: Dictionary, e: Dictionary, dt: float, col: Color, life: float, left: float, detail: float) -> void:
	## Portal: a vortex on each end turning opposite ways, sparks streaming along an arc both ways (two-way, Daniele
	## 2026-09-29), PORTAL over both, a time-left band round the first end.
	var a: Dictionary = sim.nodes[_int(e["target"])]
	var bi := _int(e.get("exit", -1))
	if bi < 0 or bi >= sim.nodes.size():
		return
	var b: Dictionary = sim.nodes[bi]
	var up := Vector3.UP
	_swirl(slot, "a", a, col, 1.0, life)
	_swirl(slot, "b", b, col, -1.0, life)
	_arc(slot, "c", a, col, left, 1.2 * life)
	var pa: Vector3 = a["pos"] + up * 1.2
	var pb: Vector3 = b["pos"] + up * 1.2
	var hgt := pa.distance_to(pb) * 0.22
	for k in range(_count(70.0 * detail * life * dt)):   # sparks streaming along the link, both ways (a two-way portal)
		var t := randf()
		if k % 2 == 1:
			var sw := pa
			pa = pb
			pb = sw
		var p := pa.lerp(pb, t) + up * (sin(t * PI) * hgt)
		var tan := (pb - pa) + up * (cos(t * PI) * PI * hgt)
		_spark(p, tan.normalized() * randf_range(9.0, 13.0), col.lerp(Color.WHITE, randf() * 0.4) * 1.3, randf_range(0.2, 0.34),
				randf_range(0.25, 0.4), 0.0)
	var lab := _slot_label(slot)
	if not slot.has("lab2"):
		slot["lab2"] = _new_label(110)
	var lab2: Label3D = slot["lab2"]
	if slot["txt"] != 1:
		slot["txt"] = 1
		lab.text = "PORTAL"                           # (two-way: no IN / OUT)
		lab2.text = "PORTAL"
	for pair_i in range(2):
		var l: Label3D = lab if pair_i == 0 else lab2
		var n: Dictionary = a if pair_i == 0 else b
		l.visible = true
		Mats.label_look(l, Color(col.lerp(Color.WHITE, 0.35), life), 0.95 * life)
		_size_label(l, n["pos"] + up * 5.0, 0.035)


func _swirl(slot: Dictionary, k: String, n: Dictionary, col: Color, dir: float, life: float) -> void:
	var g := _plane_part(slot, k, POWER_SHADER, P_SWIRL, float(n["id"]) * 0.7)
	g.position = n["pos"] + Vector3(0, 0.44, 0)
	g.scale = Vector3.ONE * Rules.R * 2.1
	var m := _mat(slot, k)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("dir", dir)
	m.set_shader_parameter("intensity", 1.2 * life)


func _line_marks(dt: float) -> void:
	## An armed Core Meltdown line: a pulsing ember aura at its head, embers along it and "ARMED" over it; an Evac line:
	## a pale shield shimmer. Everyone sees them (a rival's inside a fog this screen is blind to: nothing). Pooled.
	var detail := 0.5 if Rules.low_detail else 1.0
	var up := Vector3.UP
	var used := 0
	for h in sim.hordes:
		var armed: bool = h.get("armed", false)
		if not armed and not h.get("immune", false):
			continue
		var head: Vector3 = Sim.sample(h, h["s"])[0]
		if _fogged(head, str(h["owner"])):
			continue
		if used >= _marks.size():
			var st := MeshInstance3D.new()
			st.mesh = _quad
			var smt := ShaderMaterial.new()
			smt.shader = FLARE_SHADER
			smt.set_shader_parameter("mode", 0)
			st.material_override = smt
			st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(st)
			var lb := _new_label(110)
			lb.text = "ARMED"
			_marks[used] = {"star": st, "smat": smt, "lab": lb}
		var mk: Dictionary = _marks[used]
		used += 1
		var id: int = h["id"]
		var col := EMBER if armed else SHIELD
		var pulse := 0.5 + 0.5 * sin(_t * (9.0 if armed else 5.0) + id)
		var star: MeshInstance3D = mk["star"]
		star.visible = true
		star.position = head + up * 1.4
		star.scale = Vector3.ONE * ((4.5 + 2.2 * pulse) if armed else (3.6 + 1.0 * pulse))
		var sm: ShaderMaterial = mk["smat"]
		sm.set_shader_parameter("color", col)
		sm.set_shader_parameter("intensity", (0.8 + 0.7 * pulse) if armed else (0.55 + 0.35 * pulse))
		sm.set_shader_parameter("spin", _t * (2.0 if armed else 0.6))
		var length := maxf(_line_len(h), 0.5)
		for k in range(_count((28.0 if armed else 20.0) * clampf(length / 8.0, 0.5, 3.0) * detail * dt)):
			var p: Vector3 = Sim.sample(h, h["s"] - randf() * length)[0]
			if armed:                                 # embers rising off the line
				_spark(p + Vector3(randf_range(-1.1, 1.1), randf_range(0.3, 1.2), randf_range(-1.1, 1.1)), Vector3(randf_range(-0.6, 0.6), randf_range(2.0, 4.5), randf_range(-0.6, 0.6)),
						EMBER if randf() < 0.6 else HOT, randf_range(0.18, 0.32), randf_range(0.4, 0.8), -1.0)
			else:                                     # the shield's shimmer round the bodies
				var a := randf() * TAU
				_spark(p + Vector3(cos(a) * 1.4, randf_range(0.2, 1.8), sin(a) * 1.4), Vector3(0.0, randf_range(0.3, 1.0), 0.0),
						SHIELD * 1.2, randf_range(0.16, 0.28), randf_range(0.3, 0.55), 0.0)
		var lab: Label3D = mk["lab"]
		lab.visible = armed
		if armed:
			Mats.label_look(lab, Color(EMBER.lerp(HOT, 0.3), 0.7 + 0.3 * pulse), 0.95)
			_size_label(lab, head + up * 5.5, 0.03)
	for i in range(used, _marks.size()):
		var mk: Dictionary = _marks[i]
		if (mk["star"] as Node3D).visible:
			(mk["star"] as Node3D).visible = false
			(mk["lab"] as Node3D).visible = false


func _backwash(ev: Dictionary) -> void:
	## A wave of goo sweeps along the deck toward the lip it shoved the lines back to; a splash where each one lands.
	var ei := int(ev["edge"])
	if ei < 0 or ei >= sim.edges.size():
		return
	var seat := str(ev.get("seat", ""))
	var col := Rules.seat_color(seat).lerp(SHIELD, 0.25)
	var dir := -1.0                                   # toward u = 0 (the deck's first end) unless the lines went the other way
	for hid in ev.get("hids", []):
		var h := sim._horde(int(hid))
		if h.is_empty():
			continue
		var at: Vector3 = Sim.sample(h, h["s"])[0]
		if dir < 0.0 and at.distance_to(_deck_at(ei, 1.0)) < at.distance_to(_deck_at(ei, 0.0)):
			dir = 1.0
		_burst(at + Vector3(0, 0.8, 0), col, 20, 7.0, 0.5, 12.0)
	if not _waves.has(ei):
		var mi := _strip_mi(ei, POWER_SHADER, P_WAVE, float(ei) * 0.9)
		if mi == null:
			return
		_waves[ei] = {"mi": mi, "mat": mi.material_override, "t": -1.0, "dir": 1.0, "col": col}
	var w: Dictionary = _waves[ei]
	w["t"] = 0.0
	w["dir"] = dir
	w["col"] = col
	(w["mat"] as ShaderMaterial).set_shader_parameter("dir", dir)
	(w["mat"] as ShaderMaterial).set_shader_parameter("color", col)
	_count_stat("backwash")


func _step_waves(dt: float) -> void:
	for ei in _waves:
		var w: Dictionary = _waves[ei]
		if float(w["t"]) < 0.0:
			continue
		w["t"] = float(w["t"]) + dt
		var k := float(w["t"]) / WAVE_T
		var mi: MeshInstance3D = w["mi"]
		if k >= 1.3:
			w["t"] = -1.0
			mi.visible = false
			continue
		mi.visible = true
		var dir: float = w["dir"]
		var front := k if dir > 0.0 else 1.0 - k      # it runs from the far end to the lip
		var m: ShaderMaterial = w["mat"]
		m.set_shader_parameter("front", front)
		m.set_shader_parameter("intensity", 1.4 * (1.0 - smoothstep(1.0, 1.3, k)))
		if k <= 1.0:
			var crest := _deck_at(int(ei), front)
			var fwd := (_deck_at(int(ei), 1.0) - _deck_at(int(ei), 0.0)).normalized() * dir
			for n in range(_count(70.0 * dt)):        # spray thrown off the crest
				_spark(crest + Vector3(randf_range(-1.3, 1.3), 0.4, randf_range(-1.3, 1.3)), fwd * randf_range(6.0, 12.0) + Vector3(0, randf_range(2.0, 5.0), 0),
						(w["col"] as Color).lerp(Color.WHITE, randf() * 0.5), randf_range(0.2, 0.36), randf_range(0.35, 0.6), 12.0)


func _sinkhole(ev: Dictionary) -> void:
	## A black goo pit opens under the structure (CombatFx sinks the old tier into it and raises the new one).
	var id := int(ev["node"])
	if id < 0 or id >= sim.nodes.size():
		return
	var n: Dictionary = sim.nodes[id]
	var col := Rules.seat_color(str(ev.get("seat", "")))
	if not _holes.has(id):
		var mi := MeshInstance3D.new()
		mi.mesh = _plane
		var m := ShaderMaterial.new()
		m.shader = DARK_SHADER
		for p in P_HOLE:
			m.set_shader_parameter(p, P_HOLE[p])
		m.set_shader_parameter("seed", float(id) * 1.3)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_holes[id] = {"mi": mi, "mat": m, "t": -1.0}
	var hole: Dictionary = _holes[id]
	hole["t"] = 0.0
	(hole["mat"] as ShaderMaterial).set_shader_parameter("color", col)
	var c: Vector3 = n["pos"]
	_ring_at(c, col.lerp(Color(0.2, 0.2, 0.25), 0.4), Rules.R * 2.2, 0.6)
	for k in range(int(40 * (0.6 if Rules.low_detail else 1.0))):   # goo and grit thrown off the rim of the pit
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		_spark(c + d * randf_range(1.5, 3.0) + Vector3(0, 0.6, 0), d * randf_range(3.0, 7.0) + Vector3(0, randf_range(3.0, 7.0), 0),
				col if randf() < 0.5 else Color(0.25, 0.24, 0.3), randf_range(0.25, 0.45), randf_range(0.5, 0.9), 16.0)
	_count_stat("sinkhole")


func _step_holes(dt: float) -> void:
	for id in _holes:
		var hole: Dictionary = _holes[id]
		if float(hole["t"]) < 0.0:
			continue
		hole["t"] = float(hole["t"]) + dt
		var k := float(hole["t"]) / HOLE_T
		var mi: MeshInstance3D = hole["mi"]
		if k >= 1.0 or sim.collapsed.get(id, false):
			hole["t"] = -1.0
			mi.visible = false
			continue
		mi.visible = true
		mi.position = sim.nodes[id]["pos"] + Vector3(0, 0.43, 0)
		mi.scale = Vector3.ONE * Rules.R * 1.5
		(hole["mat"] as ShaderMaterial).set_shader_parameter("opening", smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.7, 1.0, k)))
		(hole["mat"] as ShaderMaterial).set_shader_parameter("alpha", 0.95)


func _hide_dropped() -> void:
	## A deck that Demolish / Quake / Sever dropped stays hidden even while its relay swings it (Fx._relay_motion shows
	## moving decks): Sever may cut a relay deck.
	if sim.demolished.is_empty():
		return
	var decks: Dictionary = vis.get("edge_decks", {})
	for ei in sim.demolished:
		for d in decks.get(int(ei), []):
			if is_instance_valid(d) and (d as Node3D).visible:
				(d as Node3D).visible = false


# ------------------------------------------------------------------ per frame
func sync(dt: float, cam: Camera3D) -> void:
	var _pt := Time.get_ticks_usec()                 # perf pass: PerfProfile.lap (off in play)
	_frame += 1
	_t += dt
	_cam = cam
	_hordes.clear()
	for h in sim.hordes:
		_hordes[h["id"]] = h
	_effects(dt)
	_ghost_wisps(dt)
	_line_marks(dt)                               # POWERS: armed (Core Meltdown) / immune (Evac) lines
	_step_waves(dt)                               # POWERS: Backwash
	_step_holes(dt)                               # POWERS: Sinkhole
	_hide_dropped()                               # POWERS: a dropped deck stays hidden even while its relay moves
	_step_breaks(dt)
	_step_pools(dt)
	_step_tint(dt)
	_update_sparks(dt)
	PerfProfile.lap("skill_fx", _pt)


func _effects(dt: float) -> void:
	for e in sim.effects:
		var key := _key(e)
		if key < 0:
			continue
		var slot: Dictionary = _slots.get(key, {})
		if slot.is_empty():
			slot = {"id": str(e["id"]), "on": str(e["on"]), "life": 0.0, "seen": -1, "tl": float(e["t"]), "kills": float(e.get("kills", 0.0)),
					"acc": 0.0, "txt": -1, "phase": "", "extra": {}}
			_slots[key] = slot
			_count_stat("slot_" + str(e["id"]))
		if slot["seen"] < _frame - 1:                 # (re)starting: from the effect's own clock
			slot["tl"] = float(e["t"])
			slot["kills"] = float(e.get("kills", 0.0))
		slot["seen"] = _frame
		slot["life"] = minf(1.0, float(slot["life"]) + dt / FADE_IN)
		slot["tl"] = float(slot["tl"]) - dt           # smooth between a guest's snapshots
		if absf(float(slot["tl"]) - float(e["t"])) > 0.3:
			slot["tl"] = float(e["t"])
		_update(slot, e, dt)
	for key in _slots:
		var slot: Dictionary = _slots[key]
		if slot["seen"] == _frame or float(slot["life"]) <= 0.0:
			continue
		slot["life"] = maxf(0.0, float(slot["life"]) - dt / FADE_OUT)
		if slot["life"] <= 0.0:
			_hide(slot)
			if slot["id"] in DECK_DROPS and slot["on"] == "edge":   # (POWERS: Quake / Sever too)
				_hide_pieces(int(slot["target"]))
		else:
			_fade(slot)
	for id in _markers:                               # Rewire: a relay no longer offered
		var m: Dictionary = _markers[id]
		if m["seen"] != _frame and (m["ring"] as Node3D).visible:
			(m["ring"] as Node3D).visible = false
			(m["chev"] as Node3D).visible = false
	for id in _blooms:
		var b: Dictionary = _blooms[id]
		if b["seen"] != _frame and (b["glow"] as Node3D).visible:
			(b["glow"] as Node3D).visible = false


func _key(e: Dictionary) -> int:
	var i := IDS.find(str(e.get("id", "")))
	var o := ONS.find(str(e.get("on", "")))
	if i < 0 or o < 0:
		return -1
	var t = e.get("target")
	var tv := SEATS.find(str(t)) if o == 4 else _int(t)
	if tv < 0:
		return -1
	return (i * 8 + o) * 1000000 + tv


func _update(slot: Dictionary, e: Dictionary, dt: float) -> void:
	var id: String = slot["id"]
	var seat := str(e["seat"])
	var col := Rules.seat_color(seat)
	var life: float = slot["life"]
	var dur: float = maxf(float(e.get("dur", 1.0)), 0.001)
	var left := clampf(float(slot["tl"]) / dur, 0.0, 1.0)
	var age: float = dur - float(slot["tl"])
	var up := Vector3.UP
	var detail := 0.5 if Rules.low_detail else 1.0
	slot["target"] = e["target"]
	match id:
		"surge":
			var h = _hordes.get(_int(e["target"]))
			if h == null:
				return
			_streaks(h, col, 70.0 * life * detail, dt)
			var smp := Sim.sample(h, h["s"])
			var star := _part(slot, "a", _quad, FLARE_SHADER, P_STAR)
			star.visible = true
			star.position = (smp[0] as Vector3) + (smp[1] as Vector3) * 0.9 + up * 1.2
			star.scale = Vector3.ONE * (3.0 + 0.4 * sin(_t * 17.0))
			_mat(slot, "a").set_shader_parameter("color", col.lerp(Color.WHITE, 0.2))
			_mat(slot, "a").set_shader_parameter("intensity", 0.9 * life)
			_mat(slot, "a").set_shader_parameter("spin", _t * 3.0)
		"spore_burst":
			var n: Dictionary = sim.nodes[_int(e["target"])]
			_ground(slot, "a", n, col.lerp(SPORE, 0.45), Rules.R * 2.4, (1.3 + 0.4 * sin(_t * 6.0)) * life)
			_arc(slot, "b", n, col.lerp(SPORE, 0.3), left, 1.3 * life)
			var vat := _part(slot, "c", _quad, FLARE_SHADER, P_STAR)       # the vat glowing, pulsing with each bubble
			vat.visible = true
			vat.position = n["pos"] + up * 4.2 + Rules.front_dir() * 1.5
			vat.scale = Vector3.ONE * (6.0 + 1.5 * sin(_t * 8.0))
			_mat(slot, "c").set_shader_parameter("color", SPORE.lerp(col, 0.3))
			_mat(slot, "c").set_shader_parameter("intensity", (0.55 + 0.25 * sin(_t * 8.0)) * life)
			_mat(slot, "c").set_shader_parameter("spin", _t * 0.7)
			for k in range(_count(60.0 * detail * life * dt)):       # spores bubbling up and over
				var a := randf() * TAU
				var r := randf_range(0.0, 2.2)
				var d := Vector3(cos(a), 0.0, sin(a))
				_spark(n["pos"] + d * r + up * randf_range(3.6, 5.2), d * randf_range(0.8, 2.6) + up * randf_range(2.5, 5.5),
						SPORE.lerp(col, randf() * 0.4) * 1.5, randf_range(0.35, 0.6), randf_range(1.0, 1.7), -0.8)
			for k in range(_count(22.0 * detail * life * dt)):       # and spilling over the rim
				var a := randf() * TAU
				var d := Vector3(cos(a), 0.0, sin(a))
				_spark(n["pos"] + d * 2.0 + up * 4.4, d * randf_range(2.5, 4.5) + up * 2.0, col.lerp(SPORE, 0.4) * 1.3,
						randf_range(0.4, 0.6), randf_range(0.6, 0.9), 9.0)
		"fortify":
			var n: Dictionary = sim.nodes[_int(e["target"])]
			var w := _part(slot, "a", _wall, FX_SHADER, P_WALL, float(n["id"]))
			w.visible = true
			w.position = n["pos"] + up * 0.05
			var rise := smoothstep(0.0, 1.0, minf(age / 0.35, 1.0))
			w.scale = Vector3(Rules.R + 0.6, WALL_H * maxf(rise, 0.02), Rules.R + 0.6)
			var m := _mat(slot, "a")
			m.set_shader_parameter("color", col.lerp(Color.WHITE, 0.15))
			m.set_shader_parameter("left", left)
			m.set_shader_parameter("intensity", 1.5 * life * (1.0 + 0.6 * (1.0 - rise)))
		"scorch":
			var ei := _int(e["target"])
			var s := _strip_part(slot, "a", ei, FX_SHADER, P_FIRE, float(ei) * 3.1)
			if s == null:
				return
			var m := _mat(slot, "a")
			m.set_shader_parameter("color", col)
			m.set_shader_parameter("fill", minf(1.0, age * 3.0))
			m.set_shader_parameter("intensity", 0.65 * life)
			var len: float = _line(ei)[2]
			for k in range(_count(len * 3.0 * detail * life * dt)):   # tongues of flame
				_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.1, 1.1), 0.5, randf_range(-1.1, 1.1)),
						Vector3(randf_range(-0.4, 0.4), randf_range(2.5, 4.0), randf_range(-0.4, 0.4)),
						FIRE.lerp(col, 0.2) * 1.2, randf_range(0.6, 0.95), randf_range(0.35, 0.55), -2.0)
			for k in range(_count(len * 5.0 * detail * life * dt)):   # embers
				_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2)),
						Vector3(randf_range(-0.8, 0.8), randf_range(3.0, 6.5), randf_range(-0.8, 0.8)),
						FIRE if randf() < 0.55 else (HOT if randf() < 0.6 else col), randf_range(0.18, 0.34), randf_range(0.45, 0.9), -1.5)
			_scorch_victims(slot, e, ei, dt, detail)
		"demolish", "sever":                          # (POWERS: Sever shares the deck-drop look, with its cut line)
			_deck_drop(slot, e, dt, col, life, detail)
		"quake":                                      # POWERS: each deck drops like Demolish's; the platform shakes
			if slot["on"] == "edge":
				_deck_drop(slot, e, dt, col, life, detail)
			else:
				_quake_node(slot, e, dt, col, life, detail)
		"fog":                                        # POWERS
			_fog(slot, e, col, life, left, age)
		"portal":                                     # POWERS
			_portal(slot, e, dt, col, life, left, detail)
		"mire":
			var ei := _int(e["target"])
			var s := _strip_part(slot, "a", ei, SLUDGE_SHADER, P_NONE, float(ei) * 0.73)
			if s == null:
				return
			var m := _mat(slot, "a")
			m.set_shader_parameter("color", col)
			m.set_shader_parameter("fill", minf(1.0, age * 2.5))
			m.set_shader_parameter("intensity", life)
			for k in range(_count(_line(ei)[2] * 1.2 * detail * life * dt)):   # bubbles popping
				_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.0, 1.0), 0.35, randf_range(-1.0, 1.0)),
						Vector3(0.0, randf_range(0.6, 1.4), 0.0), col.lerp(SPORE, 0.3) * 0.8, randf_range(0.2, 0.34), randf_range(0.35, 0.6), 0.0)
		"anchor":
			var ei := _int(e["target"])
			_lock_deck(slot, ei, col, left, life, age, true)
		"relay_aegis":
			if slot["on"] == "edge":
				_lock_deck(slot, _int(e["target"]), col, left, life, age, false)
			else:
				var n: Dictionary = sim.nodes[_int(e["target"])]
				var centre: bool = _int(e.get("center", -1)) == n["id"]
				var d := _part(slot, "a", _dome, FX_SHADER, P_DOME, float(n["id"]) * 0.3)
				d.visible = true
				d.position = n["pos"]
				var grow := smoothstep(0.0, 1.0, minf(age / 0.45, 1.0))
				var r := (Rules.R + 1.8) * lerpf(0.3, 1.0, grow)
				d.scale = Vector3(r, r * 0.92, r)
				var m := _mat(slot, "a")
				m.set_shader_parameter("color", col.lerp(Color.WHITE, 0.12))
				m.set_shader_parameter("left", left)
				m.set_shader_parameter("intensity", (1.0 if centre else 0.75) * life * (1.0 + 0.8 * (1.0 - grow)))
				if n["relay"] != "":
					_clamp(slot, "b", n["pos"] + up * 0.4, Rules.R + 0.2, col, left, life)
		"bypass":
			var n: Dictionary = sim.nodes[_int(e["target"])]
			_ground(slot, "a", n, col, Rules.R * 2.5, (0.8 + 0.35 * sin(_t * 9.0)) * life)
			_arc(slot, "b", n, col, left, 1.3 * life)
			var star := _part(slot, "c", _quad, FLARE_SHADER, P_STAR)
			star.visible = true
			star.position = n["pos"] + up * 8.0
			star.scale = Vector3.ONE * (8.0 + 1.5 * sin(_t * 7.0))
			_mat(slot, "c").set_shader_parameter("color", col)
			_mat(slot, "c").set_shader_parameter("intensity", (0.8 + 0.3 * sin(_t * 23.0)) * life)
			_mat(slot, "c").set_shader_parameter("spin", _t)
			var extra: Dictionary = slot["extra"]
			if not slot.has("edges"):
				slot["edges"] = sim.controlled_edges(n["id"])
			for ei in slot["edges"]:                  # every deck it controls, both states at once
				if not extra.has(ei):
					var mi := _strip_mi(ei, FX_SHADER, P_HOLO, float(ei))
					if mi == null:
						continue
					extra[ei] = mi
				var hm: MeshInstance3D = extra[ei]
				hm.visible = true
				var mm := hm.material_override as ShaderMaterial
				mm.set_shader_parameter("color", col.lerp(Rules.state_color(sim.edges[ei]["state"] if sim.edges[ei]["state"] != "" else "retract"), 0.3))
				mm.set_shader_parameter("intensity", 0.9 * life)
				mm.set_shader_parameter("fill", minf(1.0, age * 3.0))
		"relay_hack":
			var n: Dictionary = sim.nodes[_int(e["target"])]
			var jam := str(e.get("mode", "fire")) == "jam"
			var lab := _slot_label(slot)
			if jam:
				_hide_part(slot, "a")
				_clamp(slot, "b", n["pos"] + up * 0.42, Rules.R + 0.3, col, left, life)
				var sec := int(ceil(maxf(float(slot["tl"]), 0.01)))
				if slot["txt"] != sec:
					slot["txt"] = sec
					lab.text = "JAM %d" % sec
				lab.visible = true
				Mats.label_look(lab, Color(col.lerp(Color.WHITE, 0.2), life), 0.95 * life)
				_size_label(lab, n["pos"] + up * 10.0, 0.04)
			else:
				_hide_part(slot, "b")
				lab.visible = false
				var g := _plane_part(slot, "a", FX_SHADER, P_HACK, float(n["id"]))
				g.position = n["pos"] + up * 0.45
				g.scale = Vector3.ONE * (Rules.R + 1.2) * 2.0
				_mat(slot, "a").set_shader_parameter("color", col)
				_mat(slot, "a").set_shader_parameter("intensity", 1.2 * life)
				_glitch_sparks(n["pos"], col, 40.0 * detail * life, dt)
		"echo_split":
			var n: Dictionary = sim.nodes[_int(e["target"])]
			var g := _plane_part(slot, "a", FX_SHADER, P_JAMMED, float(n["id"]) + 7.0)
			g.position = n["pos"] + up * 0.45
			g.scale = Vector3.ONE * (Rules.R + 0.6) * 2.0
			_mat(slot, "a").set_shader_parameter("color", col)
			_mat(slot, "a").set_shader_parameter("intensity", (0.9 + 0.3 * sin(_t * 31.0)) * life)
			_arc(slot, "b", n, col, left, 1.2 * life)
			_glitch_sparks(n["pos"], col, 46.0 * detail * life, dt)
			var lab := _slot_label(slot)
			if slot["txt"] != 1:
				slot["txt"] = 1
				lab.text = "OFFLINE"
			lab.visible = true
			var fl := 0.7 + 0.3 * float(int(_t * 9.0) % 2)
			Mats.label_look(lab, Color(1.0, 0.35, 0.4, life * fl), 0.95 * life * fl)
			_size_label(lab, n["pos"] + up * 9.0, 0.035)
		"rewire":
			for h in sim.hordes:
				if h["owner"] == seat:
					_streaks(h, col, 40.0 * life * detail, dt)
			if seat == viewer and int(e.get("fires", 0)) > 0:
				_rewire_marks(seat, col)
		"superbloom":
			var lf := float(e.get("left", -1.0))
			var capped := lf == 0.0
			var hb: Vector3 = Vector3.INF
			for n in sim.nodes:
				if n["owner"] != seat or sim.collapsed.get(n["id"], false):
					continue
				if hb == Vector3.INF or n["id"] == sim.homes.get(seat, -1):
					hb = n["pos"]
				if not Sim.has_vat(n):
					continue
				_bloom(n, col, life * (0.35 if capped else 1.0), dt * (0.2 if capped else 1.0), detail)
			var lab := _slot_label(slot)
			var cap := int(Rules.SKILLS["superbloom"]["cap_shown"])
			var got := -1                              # -1: uncapped (SUPERBLOOM_MODE "under_attack")
			if capped:
				got = cap
			elif lf > 0.0:
				got = clampi(int(round(cap - Rules.shown_f(lf))), 0, cap)
			if slot["txt"] != got:
				slot["txt"] = got
				lab.text = ("+%d / %d" % [got, cap]) if got >= 0 else "SUPERBLOOM"
			lab.visible = hb != Vector3.INF
			Mats.label_look(lab, Color(col.lerp(PETAL, 0.25), life), 0.95 * life)
			if hb != Vector3.INF:
				_size_label(lab, hb + up * 11.0, 0.05)


func _fade(slot: Dictionary) -> void:
	## A lasting effect that just ended: its visuals ease out (intensity, a mire drains to the middle).
	var life: float = slot["life"]
	for k in ["a", "b", "c", "d", "e"]:
		if slot.has(k + "m"):
			var m: ShaderMaterial = slot[k + "m"]
			if slot.get(k + "dark", false):               # POWERS: the dark goo fades by its alpha
				m.set_shader_parameter("alpha", float(slot[k + "dark"]) * life)
				continue
			m.set_shader_parameter("intensity", life * (1.1 if slot["id"] != "mire" else 1.0))
			if slot["id"] in ["mire", "scorch", "anchor", "relay_aegis"]:
				m.set_shader_parameter("fill", life)
	for mi in (slot["extra"] as Dictionary).values():
		((mi as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("intensity", 0.9 * life)
	for lk in ["lab", "lab2"]:                       # (POWERS: Portal's second label)
		if slot.has(lk):
			var lab: Label3D = slot[lk]
			Mats.label_look(lab, Color(lab.modulate, life), 0.95 * life)


func _hide(slot: Dictionary) -> void:
	for k in ["a", "b", "c", "d", "e"]:
		_hide_part(slot, k)
	for mi in (slot["extra"] as Dictionary).values():
		(mi as Node3D).visible = false
	for lk in ["lab", "lab2"]:
		if slot.has(lk):
			(slot[lk] as Node3D).visible = false
	slot["phase"] = ""
	slot["txt"] = -1


# ------------------------------------------------------------------ pieces of a lasting effect
func _part(slot: Dictionary, k: String, mesh: Mesh, shader: Shader, params: Dictionary, seed := 0.0) -> MeshInstance3D:
	## The slot's piece k, made on first use (params: a const table, so nothing is allocated per frame).
	if not slot.has(k):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = shader
		for p in params:
			m.set_shader_parameter(p, params[p])
		m.set_shader_parameter("seed", seed)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		slot[k] = mi
		slot[k + "m"] = m
	return slot[k]


func _mat(slot: Dictionary, k: String) -> ShaderMaterial:
	return slot[k + "m"]


func _hide_part(slot: Dictionary, k: String) -> void:
	if slot.has(k):
		(slot[k] as Node3D).visible = false


func _plane_part(slot: Dictionary, k: String, shader: Shader, params: Dictionary, seed := 0.0) -> MeshInstance3D:
	var mi := _part(slot, k, _plane, shader, params, seed)
	mi.visible = true
	return mi


func _ground(slot: Dictionary, k: String, n: Dictionary, col: Color, size: float, intensity: float) -> void:
	var g := _plane_part(slot, k, FLARE_SHADER, P_GROUND, float(n["id"]) * 5.1)
	g.position = n["pos"] + Vector3(0, 0.36, 0)
	g.scale = Vector3.ONE * size
	_mat(slot, k).set_shader_parameter("color", col)
	_mat(slot, k).set_shader_parameter("intensity", intensity)


func _arc(slot: Dictionary, k: String, n: Dictionary, col: Color, left: float, intensity: float) -> void:
	## A time-left band round the platform, just outside its rim.
	var a := _part(slot, k, _annulus, FX_SHADER, P_ARC)
	a.visible = true
	a.position = n["pos"] + Vector3(0, 0.34, 0)
	a.scale = Vector3.ONE * (Rules.R + 1.3)
	a.rotation.y = -Rules.view_yaw - PI / 2.0        # it drains from the top of the screen, clockwise
	var m := _mat(slot, k)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("left", left)
	m.set_shader_parameter("intensity", intensity)


func _clamp(slot: Dictionary, k: String, at: Vector3, radius: float, col: Color, left: float, life: float) -> void:
	var c := _plane_part(slot, k, FX_SHADER, P_CLAMP)
	c.position = at
	c.scale = Vector3.ONE * (2.0 * radius / 0.84)
	c.rotation.y = -Rules.view_yaw
	var m := _mat(slot, k)
	m.set_shader_parameter("color", col.lerp(Color.WHITE, 0.1))
	m.set_shader_parameter("left", left)
	m.set_shader_parameter("intensity", 1.6 * life)


func _lock_deck(slot: Dictionary, ei: int, col: Color, left: float, life: float, age: float, clamps: bool) -> void:
	## Anchor / Relay Aegis on a deck: bolted rails along it; Anchor adds clamps at both ends and on its relay.
	var s := _strip_part(slot, "a", ei, FX_SHADER, P_LOCK, float(ei))
	if s == null:
		return
	var m := _mat(slot, "a")
	m.set_shader_parameter("color", col.lerp(Color.WHITE, 0.1))
	m.set_shader_parameter("fill", minf(1.0, age * 4.0))
	m.set_shader_parameter("intensity", 1.8 * life)
	if not clamps:
		return
	_clamp(slot, "b", _deck_at(ei, 0.0) + Vector3(0, 0.3, 0), 1.9, col, left, life)
	_clamp(slot, "c", _deck_at(ei, 1.0) + Vector3(0, 0.3, 0), 1.9, col, left, life)
	var ctrl: int = sim.edge_controller.get(ei, -1)
	if ctrl >= 0:
		_clamp(slot, "d", sim.nodes[ctrl]["pos"] + Vector3(0, 0.42, 0), Rules.R + 0.3, col, left, life)


func _slot_label(slot: Dictionary) -> Label3D:
	if not slot.has("lab"):
		slot["lab"] = _new_label(110)
	return slot["lab"]


func _strip_part(slot: Dictionary, k: String, ei: int, shader: Shader, params: Dictionary, seed := 0.0) -> MeshInstance3D:
	if not slot.has(k):
		var mi := _strip_mi(ei, shader, params, seed)
		if mi == null:
			return null
		slot[k] = mi
		slot[k + "m"] = mi.material_override
	var s: MeshInstance3D = slot[k]
	s.visible = true
	return s


func _strip_mi(ei: int, shader: Shader, params: Dictionary, seed := 0.0) -> MeshInstance3D:
	var mesh := _strip(ei)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = shader
	for p in params:
		m.set_shader_parameter(p, params[p])
	m.set_shader_parameter("seed", seed)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = _BIG
	add_child(mi)
	return mi


# ------------------------------------------------------------------ line effects
func _line_len(h: Dictionary) -> float:
	## Metres of path the line's bodies cover behind its head (BRAWL: one body every BRAWL_SPACING).
	if Rules.bridge_combat:
		return minf(float(h["s"]), Sim.chain_length(h))
	return minf(float(h["s"]), Rules.shown_f(h["units"]) * Rules.BRAWL_SPACING)


func _streaks(h: Dictionary, col: Color, rate: float, dt: float) -> void:
	## Surge / Rewire: speed streaks peeling off the line's bodies, left behind as it runs.
	var length := _line_len(h)
	if length <= 0.2 or h["state"] == "absorb":
		return
	if _fogged(Sim.sample(h, h["s"])[0], str(h["owner"])):   # POWERS: a rival's line inside a fog you are blind to
		return
	var c := col.lerp(Color.WHITE, 0.3) * 1.6
	for k in range(_count(rate * clampf(length / 8.0, 0.4, 4.0) * dt)):
		var smp := Sim.sample(h, h["s"] - randf() * length)
		var fwd: Vector3 = smp[1]
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.RIGHT
		var side := fwd.cross(Vector3.UP)
		var low := randf() < 0.45                     # half the streaks run along the deck at the bodies' feet
		_spark((smp[0] as Vector3) + side * randf_range(-1.4, 1.4) + Vector3(0, 0.25 if low else randf_range(0.6, 1.7), 0),
				-fwd * randf_range(34.0, 52.0), c if randf() < 0.75 else HOT, randf_range(0.2, 0.32) if low else randf_range(0.14, 0.24),
				randf_range(0.16, 0.26), 0.0)


func _ghost_wisps(dt: float) -> void:
	## Your own Ghost Lines (and echoes) shed pale wisps - for your eyes only (Sim.is_ghost_for).
	var detail := 0.5 if Rules.low_detail else 1.0
	for h in sim.hordes:
		if not Sim.is_ghost_for(h, viewer):
			continue
		var length := _line_len(h)
		if length <= 0.2:
			continue
		var col := Rules.seat_color(h["owner"])
		for k in range(_count(10.0 * clampf(length / 8.0, 0.5, 3.0) * detail * dt)):
			var p: Vector3 = Sim.sample(h, h["s"] - randf() * length)[0]
			_spark(p + Vector3(randf_range(-1.2, 1.2), randf_range(0.5, 1.6), randf_range(-1.2, 1.2)), Vector3(0.0, randf_range(0.6, 1.6), 0.0),
					WISP.lerp(col, randf() * 0.4) * 0.8, randf_range(0.22, 0.4), randf_range(0.6, 1.0), -0.5)


func _scorch_victims(slot: Dictionary, e: Dictionary, ei: int, dt: float, detail: float) -> void:
	## Enemy bodies on a burning deck smoulder; every unit Scorch kills pops as a flash on them.
	var seat := str(e["seat"])
	var spots := 0
	var last := Vector3.INF
	for h in sim.hordes:
		if sim.allied(h["owner"], seat):
			continue
		var length := _line_len(h)
		var s1: float = h["s"]
		var s0: float = s1 - length
		for sp in h["spans"]:
			if int(sp["edge"]) != ei:
				continue
			var a := maxf(s0, float(sp["s0"]))
			var b := minf(s1, float(sp["s1"]))
			if b <= a:
				continue
			spots += 1
			for k in range(_count(22.0 * detail * dt * clampf((b - a) / 4.0, 0.5, 3.0))):
				var p: Vector3 = Sim.sample(h, randf_range(a, b))[0]
				_spark(p + Vector3(randf_range(-1.0, 1.0), randf_range(0.6, 1.4), randf_range(-1.0, 1.0)), Vector3(0.0, randf_range(1.0, 2.5), 0.0),
						SMOKE if randf() < 0.6 else FIRE, randf_range(0.3, 0.5), randf_range(0.5, 0.9), -0.6)
			last = Sim.sample(h, randf_range(a, b))[0]
	var kills := float(e.get("kills", 0.0))
	slot["acc"] = float(slot["acc"]) + Rules.shown_f(maxf(kills - float(slot["kills"]), 0.0))
	slot["kills"] = kills
	var pops := 0
	while float(slot["acc"]) >= 1.0 and pops < 4:
		slot["acc"] = float(slot["acc"]) - 1.0
		pops += 1
		var at: Vector3 = last if last != Vector3.INF else _deck_at(ei, randf())
		at += Vector3(randf_range(-1.0, 1.0), 0.9, randf_range(-1.0, 1.0))
		_star_at(at, FIRE.lerp(HOT, 0.4), 3.4, 0.25)
		_burst(at, FIRE, 8, 5.0, 0.35, 12.0)
		_count_stat("scorch_pop")


func _glitch_sparks(c: Vector3, col: Color, rate: float, dt: float) -> void:
	for k in range(_count(rate * dt)):
		var a := randf() * TAU
		var r := randf_range(1.2, Rules.R * 0.8)
		_spark(c + Vector3(cos(a) * r, randf_range(0.5, 7.0), sin(a) * r), Vector3(randf_range(-9, 9), 0.0, randf_range(-9, 9)),
				(col if randf() < 0.6 else Color(0.8, 1.0, 1.0)) * 1.3, randf_range(0.12, 0.22), randf_range(0.06, 0.14), 0.0)


func _glitch_burst(c: Vector3, col: Color, n: int) -> void:
	for k in range(n):
		var a := randf() * TAU
		var r := randf_range(0.5, Rules.R)
		_spark(c + Vector3(cos(a) * r, randf_range(0.5, 8.0), sin(a) * r), Vector3(randf_range(-12, 12), randf_range(-2, 2), randf_range(-12, 12)),
				(col if randf() < 0.6 else Color(0.8, 1.0, 1.0)) * 1.4, randf_range(0.14, 0.26), randf_range(0.1, 0.25), 0.0)


func _rewire_marks(seat: String, col: Color) -> void:
	## Rewire, caster only: every relay the ultimate slot may fire now gets a pulsing ring and a chevron.
	for n in sim.nodes:
		if n["relay"] == "" or sim.cast_check(seat, "ultimate", n["id"]) != "":
			continue
		var id: int = n["id"]
		if not _markers.has(id):
			var ring := MeshInstance3D.new()
			ring.mesh = _plane
			var rmat := ShaderMaterial.new()
			rmat.shader = FLARE_SHADER
			rmat.set_shader_parameter("mode", 2)
			rmat.set_shader_parameter("thickness", 0.06)
			ring.material_override = rmat
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
			var chev := _new_label(150)
			chev.text = "▼"
			_markers[id] = {"ring": ring, "rmat": rmat, "chev": chev, "seen": -1}
		var mk: Dictionary = _markers[id]
		mk["seen"] = _frame
		var ring: MeshInstance3D = mk["ring"]
		ring.visible = true
		var k := fposmod(_t * 1.4, 1.0)
		ring.position = n["pos"] + Vector3(0, 0.45, 0)
		ring.scale = Vector3.ONE * lerpf(Rules.R * 1.8, Rules.R * 2.8, k)
		(mk["rmat"] as ShaderMaterial).set_shader_parameter("color", col.lerp(Color.WHITE, 0.2))
		(mk["rmat"] as ShaderMaterial).set_shader_parameter("intensity", 1.6 * (1.0 - k))
		var chev: Label3D = mk["chev"]
		chev.visible = true
		Mats.label_look(chev, col.lerp(Color.WHITE, 0.2), chev.outline_modulate.a)
		_size_label(chev, n["pos"] + Vector3(0, 10.5 + 1.2 * sin(_t * 5.0), 0), 0.05)


func _bloom(n: Dictionary, col: Color, life: float, dt: float, detail: float) -> void:
	var id: int = n["id"]
	if not _blooms.has(id):
		var g := MeshInstance3D.new()
		g.mesh = _plane
		var m := ShaderMaterial.new()
		m.shader = FLARE_SHADER
		m.set_shader_parameter("mode", 1)
		m.set_shader_parameter("seed", float(id) * 2.3)
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_blooms[id] = {"glow": g, "gmat": m, "seen": -1}
	var b: Dictionary = _blooms[id]
	b["seen"] = _frame
	var g: MeshInstance3D = b["glow"]
	g.visible = true
	g.position = n["pos"] + Vector3(0, 0.37, 0)
	g.scale = Vector3.ONE * Rules.R * (2.2 + 0.15 * sin(_t * 3.0 + id))
	(b["gmat"] as ShaderMaterial).set_shader_parameter("color", col.lerp(PETAL, 0.4))
	(b["gmat"] as ShaderMaterial).set_shader_parameter("intensity", (1.5 + 0.4 * sin(_t * 5.0 + id)) * life)
	for k in range(_count(34.0 * detail * dt)):   # petals thrown off the vat, drifting down
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.0, sin(a))
		_spark(n["pos"] + d * randf_range(0.5, 2.0) + Vector3(0, randf_range(4.0, 5.5), 0), d * randf_range(2.0, 4.5) + Vector3(0, randf_range(1.5, 3.5), 0),
				(PETAL if randf() < 0.5 else col.lerp(SPORE, 0.3)) * 1.4, randf_range(0.36, 0.6), randf_range(1.0, 1.6), 2.2)


func _wisps_at(p: Vector3, n: int, col: Color) -> void:
	for k in range(n):
		_spark(p + Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 1.5), randf_range(-1.5, 1.5)),
				Vector3(randf_range(-1.2, 1.2), randf_range(1.5, 4.0), randf_range(-1.2, 1.2)), WISP.lerp(col, randf() * 0.4),
				randf_range(0.3, 0.55), randf_range(0.7, 1.2), -1.2)


# ------------------------------------------------------------------ Demolish: the deck breaks and comes back
func _pieces_of(ei: int) -> Array:
	## Copies of the deck's pieces (made once per deck, on its first Demolish): the real ones are hidden by
	## Fx._decks the moment the deck is gone, these fall in their place and fly back before it returns.
	if _pieces.has(ei):
		return _pieces[ei]
	var out := []
	var decks: Array = vis.get("edge_decks", {}).get(ei, [])
	var line: Array = _line(ei)
	var total: float = line[2]
	for d in decks:
		if not is_instance_valid(d):
			continue
		var src: Node3D = d
		var g: Node3D = src.duplicate()
		MapBatch.show_copy(g)                     # Alpha 21: a copy of a batched deck draws itself
		add_child(g)
		var xf: Transform3D = src.global_transform if src.is_inside_tree() else src.transform
		g.transform = xf
		g.visible = false
		var mis := []
		for mi in g.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mis.append(mi)
		var u := 0.5
		if total > 0.01:
			u = clampf(_nearest_u(ei, xf.origin), 0.0, 1.0)
		var v := Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 3.5), randf_range(-2.5, 2.5))
		var spin := Vector3(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5), randf_range(-2.5, 2.5))
		out.append({"node": g, "mis": mis, "base": xf, "u": u, "v": v, "spin": spin, "v0": v, "spin0": spin})   # (POWERS: v0 / spin0 kept for Sever)
	_pieces[ei] = out
	return out


func _break(ei: int, seat: String, id := "demolish") -> void:
	if ei < 0 or ei >= sim.edges.size():
		return
	_breaks[ei] = 0.0
	_count_stat("break")
	var along := _deck_at(ei, 1.0) - _deck_at(ei, 0.0)   # POWERS: Sever snaps it in two - each half falls away from the cut
	along.y = 0.0
	along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
	for p in _pieces_of(ei):
		if id == "sever":
			var out := -along if float(p["u"]) < 0.5 else along
			p["v"] = out * randf_range(1.5, 3.0) + Vector3(0, randf_range(0.5, 1.5), 0)
			p["spin"] = along.cross(Vector3.UP) * (1.0 if float(p["u"]) < 0.5 else -1.0) * randf_range(1.0, 2.0)
		else:
			p["v"] = p["v0"]
			p["spin"] = p["spin0"]
	var col := Rules.seat_color(seat) if seat != "" else Rules.state_color("warn")
	var total: float = _line(ei)[2]
	var detail := (0.6 if Rules.low_detail else 1.0) * (0.5 if id == "quake" else 1.0)   # (POWERS: a Quake drops several at once)
	for k in range(int(clampf(total * 5.0, 30.0, 90.0) * detail)):    # the deck bursts into grit and sparks
		var roll := randf()
		_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 0.6), randf_range(-1.5, 1.5)),
				Vector3(randf_range(-4, 4), randf_range(1.0, 6.0), randf_range(-4, 4)),
				HOT if roll < 0.3 else (Rules.state_color("warn") if roll < 0.6 else Color(0.62, 0.6, 0.7)), randf_range(0.2, 0.45),
				randf_range(0.6, 1.2), 16.0)
	var mid := _deck_at(ei, 0.5)
	_star_at(mid + Vector3(0, 0.8, 0), HOT, 10.0, 0.4)
	if id != "quake":                                 # (POWERS: Quake's one ring is on its platform)
		_ring_at(mid, col.lerp(Color(0.8, 0.8, 0.85), 0.5), maxf(total, 8.0) * 1.1, 0.7)


func _step_breaks(dt: float) -> void:
	for ei in _breaks.keys():
		var t: float = _breaks[ei] + dt
		_breaks[ei] = t
		for p in _pieces_of(ei):
			var g: Node3D = p["node"]
			var a := t - absf(float(p["u"]) - 0.5) * 0.4             # it gives way in the middle first
			var base: Transform3D = p["base"]
			g.visible = a < BREAK_T
			if a <= 0.0:
				g.transform = base
				_set_alpha(p, 0.0)
				continue
			var v: Vector3 = p["v"]
			var sp: Vector3 = p["spin"]
			var pos := base.origin + v * a + Vector3.DOWN * 0.5 * 22.0 * a * a
			var b := base.basis * Basis.from_euler(sp * a)
			g.transform = Transform3D(b, pos)
			_set_alpha(p, smoothstep(0.7, BREAK_T, a))
		if t > BREAK_T + 0.45:
			_breaks.erase(ei)
			_hide_pieces(ei)


func _rebuild_pieces(ei: int, k: float) -> void:
	## The deck's last REBUILD_T s: its segments fly back in from below, the ends first.
	for p in _pieces_of(ei):
		var g: Node3D = p["node"]
		var stagger := (1.0 - absf(float(p["u"]) - 0.5) * 2.0) * 0.35
		var pk := clampf((k - stagger) / 0.65, 0.0, 1.0)
		var base: Transform3D = p["base"]
		g.visible = pk > 0.0
		if pk <= 0.0:
			continue
		var e := 1.0 + 2.7 * pow(pk - 1.0, 3.0) + 1.7 * pow(pk - 1.0, 2.0)   # ease-out-back
		var off := (1.0 - clampf(e, 0.0, 1.1))
		var sp: Vector3 = p["spin"]
		g.transform = Transform3D(base.basis * Basis.from_euler(sp * off * 1.2), base.origin + Vector3(0, -14.0, 0) * off + (p["v"] as Vector3) * off)
		_set_alpha(p, 0.6 * (1.0 - pk))
		if pk > 0.95 and not p.get("landed", false):
			p["landed"] = true
			_burst(base.origin + Vector3(0, 0.4, 0), HOT, 6, 4.0, 0.3, 12.0)
		elif pk < 0.5:
			p["landed"] = false


func _rebuilt(ei: int) -> void:
	_count_stat("rebuild")
	_hide_pieces(ei)
	_breaks.erase(ei)
	var total: float = _line(ei)[2]
	for k in range(int(clampf(total * 3.0, 16.0, 50.0))):
		_spark(_deck_at(ei, randf()) + Vector3(randf_range(-1.4, 1.4), 0.3, randf_range(-1.4, 1.4)), Vector3(0, randf_range(2.0, 5.0), 0),
				Color(0.75, 0.95, 1.0), randf_range(0.2, 0.34), randf_range(0.4, 0.7), 6.0)
	for u in [0.0, 1.0]:
		_star_at(_deck_at(ei, u) + Vector3(0, 0.8, 0), Color(0.75, 0.95, 1.0), 6.0, 0.4)


func _hide_pieces(ei: int) -> void:
	if not _pieces.has(ei):
		return
	for p in _pieces[ei]:
		(p["node"] as Node3D).visible = false
		p["landed"] = false


func _set_alpha(p: Dictionary, a: float) -> void:
	for mi in p["mis"]:
		(mi as GeometryInstance3D).transparency = a


# ------------------------------------------------------------------ decks
func _line(ei: int) -> Array:
	if _lines.has(ei):
		return _lines[ei]
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	var total := 0.0
	var raw: Array = sim.deck_line(ei) if ei >= 0 and ei < sim.edges.size() else []
	for i in range(raw.size()):
		var p: Vector3 = raw[i]
		if i > 0:
			total += p.distance_to(pts[i - 1])
		pts.append(p)
		cum.append(total)
	if pts.is_empty():                                 # a plaza link: between its two nodes
		if ei >= 0 and ei < sim.edges.size():
			pts.append(sim.nodes[sim.edges[ei]["a"]]["pos"])
			pts.append(sim.nodes[sim.edges[ei]["b"]]["pos"])
			cum.append(0.0)
			total = pts[0].distance_to(pts[1])
			cum.append(total)
		else:
			pts.append(Vector3.ZERO)
			cum.append(0.0)
	_lines[ei] = [pts, cum, total]
	return _lines[ei]


func _deck_at(ei: int, u: float) -> Vector3:
	var line := _line(ei)
	var pts: PackedVector3Array = line[0]
	var cum: PackedFloat32Array = line[1]
	var total: float = line[2]
	if pts.size() < 2 or total <= 0.0:
		return pts[0]
	var s := clampf(u, 0.0, 1.0) * total
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var seg := maxf(cum[i] - cum[i - 1], 0.0001)
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / seg)
	return pts[pts.size() - 1]


func _nearest_u(ei: int, p: Vector3) -> float:
	var line := _line(ei)
	var pts: PackedVector3Array = line[0]
	var cum: PackedFloat32Array = line[1]
	var total: float = line[2]
	var best := INF
	var bu := 0.5
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			bu = (cum[i - 1] + t * (cum[i] - cum[i - 1])) / maxf(total, 0.001)
	return bu


func _strip(ei: int) -> ArrayMesh:
	## The deck's ribbon, rim to rim along its centre line (ramps included): UV.x across 0..1, UV.y metres
	## along, UV2 (0..1 along, length). Built once per deck.
	if _strips.has(ei):
		return _strips[ei]
	var line := _line(ei)
	var pts: PackedVector3Array = line[0]
	var cum: PackedFloat32Array = line[1]
	var total: float = line[2]
	if pts.size() < 2 or total <= 0.01:
		_strips[ei] = null
		return null
	var dense := PackedVector3Array()                  # at most 1 m apart, so the fill spreads smoothly
	var dcum := PackedFloat32Array()
	for i in range(pts.size()):
		if i > 0:
			var steps := maxi(1, int(ceil((cum[i] - cum[i - 1]) / 1.0)))
			for k in range(1, steps):
				var t := float(k) / steps
				dense.append(pts[i - 1].lerp(pts[i], t))
				dcum.append(lerpf(cum[i - 1], cum[i], t))
		dense.append(pts[i])
		dcum.append(cum[i])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in range(dense.size()):
		var a := dense[maxi(i - 1, 0)]
		var b := dense[mini(i + 1, dense.size() - 1)]
		var t := b - a
		t.y = 0.0
		t = t.normalized() if t.length() > 0.001 else Vector3.RIGHT
		var side := t.cross(Vector3.UP).normalized() * DECK_W * 0.5
		var c := dense[i] + Vector3(0, STRIP_Y, 0)
		verts.append(c - side)
		verts.append(c + side)
		uvs.append(Vector2(0.0, dcum[i]))
		uvs.append(Vector2(1.0, dcum[i]))
		var u := dcum[i] / total
		uv2s.append(Vector2(u, total))
		uv2s.append(Vector2(u, total))
	for i in range(dense.size() - 1):
		var k := i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_strips[ei] = m
	return m


# ------------------------------------------------------------------ pools: bursts, rings, labels, tint
func _flare_entry(mesh: Mesh, mode: int) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = FLARE_SHADER
	m.set_shader_parameter("mode", mode)
	if mode == 2:
		m.set_shader_parameter("thickness", 0.06)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return {"mi": mi, "mat": m, "t": 0.0, "dur": 0.0, "pos": Vector3.ZERO, "s0": 1.0, "s1": 1.0, "col": Color.WHITE, "i0": 1.0}


func _star_at(p: Vector3, col: Color, size: float, dur: float) -> void:
	var s: Dictionary = _stars[_star_i]
	_star_i = (_star_i + 1) % _stars.size()
	s["t"] = 0.0
	s["dur"] = dur
	s["pos"] = p
	s["s0"] = size * 1.3
	s["s1"] = size * 0.4
	s["col"] = col
	s["i0"] = 1.6
	(s["mat"] as ShaderMaterial).set_shader_parameter("spin", randf() * TAU)


func _ring_at(p: Vector3, col: Color, radius: float, dur: float) -> void:
	var s: Dictionary = _rings[_ring_i]
	_ring_i = (_ring_i + 1) % _rings.size()
	s["t"] = 0.0
	s["dur"] = dur
	s["pos"] = p + Vector3(0, 0.42, 0)
	s["s0"] = radius * 0.5
	s["s1"] = radius * 2.0 / 0.82
	s["col"] = col
	s["i0"] = 1.5


func _label_at(text: String, p: Vector3, col: Color, dur: float, frac: float) -> void:
	var e: Dictionary = _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	var l: Label3D = e["l"]
	l.text = text
	Mats.label_look(l, col.lerp(Color.WHITE, 0.15), 0.95)
	e["t"] = 0.0
	e["dur"] = dur
	e["pos"] = p
	e["rise"] = 2.5
	e["col"] = col
	e["frac"] = frac


func _step_flares(pool: Array, dt: float) -> void:
	for s in pool:
		var mi: MeshInstance3D = s["mi"]
		if s["t"] >= s["dur"]:
			if mi.visible:
				mi.visible = false
			continue
		s["t"] = float(s["t"]) + dt
		var k := clampf(float(s["t"]) / maxf(float(s["dur"]), 0.001), 0.0, 1.0)
		mi.visible = k < 1.0
		mi.position = s["pos"]
		mi.scale = Vector3.ONE * lerpf(float(s["s0"]), float(s["s1"]), sqrt(k))
		var m: ShaderMaterial = s["mat"]
		m.set_shader_parameter("color", s["col"])
		m.set_shader_parameter("intensity", float(s["i0"]) * (1.0 - k) * (1.0 - k))


func _step_pools(dt: float) -> void:
	_step_flares(_stars, dt)
	_step_flares(_rings, dt)
	for e in _labels:
		var l: Label3D = e["l"]
		if e["t"] >= e["dur"]:
			if l.visible:
				l.visible = false
			continue
		e["t"] = float(e["t"]) + dt
		var t: float = e["t"]
		var k := clampf(t / maxf(float(e["dur"]), 0.001), 0.0, 1.0)
		l.visible = k < 1.0
		var pop := 1.0 + 0.45 * (1.0 - smoothstep(0.0, 0.18, t))
		_size_label(l, (e["pos"] as Vector3) + Vector3(0, float(e["rise"]) * smoothstep(0.0, 1.0, k), 0), float(e["frac"]) * pop)
		var fade := 1.0 - smoothstep(0.7, 1.0, k)
		Mats.label_look(l, Color(l.modulate, fade), 0.95 * fade)


func _tint_on(col: Color) -> void:
	_tint_t = 0.0
	_tint_mat.set_shader_parameter("color", col)
	_count_stat("tint")


func _step_tint(dt: float) -> void:
	if _tint_t < 0.0:
		return
	_tint_t += dt
	var k := _tint_t / TINT_T
	if k >= 1.0:
		_tint_t = -1.0
		_tint_rect.visible = false
		return
	_tint_rect.visible = true
	_tint_mat.set_shader_parameter("amount", smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.25, 1.0, k)))


func _new_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.font = UI_FONT
	l.font_size = size
	l.outline_size = int(size * 0.22)
	l.outline_modulate = Color(0.02, 0.02, 0.05, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.visible = false
	add_child(l)
	return l


func _size_label(l: Label3D, p: Vector3, frac: float) -> void:
	## A label about `frac` of the screen's height tall, wherever the camera is.
	var h := 5.0
	if _cam:
		h = _cam.global_position.distance_to(p) * frac
	Mats.label_pixel(l, h / float(l.font_size))        # (its scale: pixel_size rebuilds the mesh)
	l.position = p


# ------------------------------------------------------------------ sparks (one MultiMesh)
func _burst(p: Vector3, col: Color, n: int, speed: float, life: float, grav: float) -> void:
	for k in range(int(n * (0.6 if Rules.low_detail else 1.0))):
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.3), randf_range(-1, 1)).normalized() * randf_range(speed * 0.4, speed)
		_spark(p, v, col if randf() < 0.7 else HOT, randf_range(0.18, 0.36), randf_range(life * 0.6, life), grav)


func _spark(p: Vector3, v: Vector3, c: Color, size: float, life: float, grav: float) -> void:
	if _sp_n >= MAX_SPARKS:
		return
	var i := _sp_n
	_sp_pos[i] = p
	_sp_vel[i] = v
	_sp_col[i] = c
	_sp_size[i] = size
	_sp_life[i] = life
	_sp_max[i] = life
	_sp_grav[i] = grav
	_sp_n += 1


func _update_sparks(dt: float) -> void:
	if _sp_n == 0 and _mm.visible_instance_count == 0:
		return
	var drag := maxf(0.0, 1.0 - 1.4 * dt)
	var i := 0
	while i < _sp_n:
		var life: float = _sp_life[i] - dt
		if life <= 0.0:
			_sp_n -= 1
			_sp_pos[i] = _sp_pos[_sp_n]
			_sp_vel[i] = _sp_vel[_sp_n]
			_sp_col[i] = _sp_col[_sp_n]
			_sp_size[i] = _sp_size[_sp_n]
			_sp_life[i] = _sp_life[_sp_n]
			_sp_max[i] = _sp_max[_sp_n]
			_sp_grav[i] = _sp_grav[_sp_n]
			continue
		_sp_life[i] = life
		var v: Vector3 = _sp_vel[i]
		v.y -= _sp_grav[i] * dt
		v *= drag
		_sp_vel[i] = v
		_sp_pos[i] += v * dt
		var k: float = life / _sp_max[i]
		var c: Color = _sp_col[i]
		c.a = minf(1.0, k * 3.0) * (0.35 + 0.65 * k)
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _sp_pos[i]))
		_mm.set_instance_color(i, c)
		_mm.set_instance_custom_data(i, Color(v.x, v.y, v.z, _sp_size[i] * (0.45 + 0.55 * k)))
		i += 1
	_mm.visible_instance_count = _sp_n


# ------------------------------------------------------------------ helpers
func _count_stat(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


static func _int(v) -> int:
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(v)
	return -1


func _target_pos(ev: Dictionary) -> Vector3:
	var t = ev.get("target")
	if t is Array and not (t as Array).is_empty():
		t = t[0]
	var i := _int(t)
	if i >= 0 and i < sim.nodes.size():
		return sim.nodes[i]["pos"]
	return Vector3.ZERO


static func _wall_mesh(segments: int) -> ArrayMesh:
	## An open cylinder, radius 1, height 0..1: UV.x round 0..1, UV.y up 0..1.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(segments + 1):
		var a := TAU * k / segments
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d)
		uvs.append(Vector2(float(k) / segments, 0.0))
		verts.append(d + Vector3.UP)
		uvs.append(Vector2(float(k) / segments, 1.0))
	for k in range(segments):
		var b := k * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _mesh(verts, uvs, idx)


static func _dome_mesh(segments: int, rings: int) -> ArrayMesh:
	## A hemisphere, radius 1: UV.x round 0..1, UV.y 0 at the rim .. 1 at the top.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in range(rings + 1):
		var el := PI / 2.0 * r / rings
		for k in range(segments + 1):
			var a := TAU * k / segments
			verts.append(Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)))
			uvs.append(Vector2(float(k) / segments, float(r) / rings))
	for r in range(rings):
		for k in range(segments):
			var b := r * (segments + 1) + k
			var c := b + segments + 1
			idx.append_array([b, c, b + 1, b + 1, c, c + 1])
	return _mesh(verts, uvs, idx)


static func _count(x: float) -> int:
	## A whole number of spawns this frame whose average is x (a rate times dt) - as CombatFx._count.
	var whole := int(x)
	return whole + (1 if randf() < x - whole else 0)


static func _annulus_mesh(inner: float, segments: int) -> ArrayMesh:
	## A flat ring, radius inner..1 in XZ; UV.x = angle / TAU, UV.y = 0 inside .. 1 outside (as CombatFx's).
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(segments + 1):
		var a := TAU * k / segments
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d * inner)
		uvs.append(Vector2(float(k) / segments, 0.0))
		verts.append(d)
		uvs.append(Vector2(float(k) / segments, 1.0))
	for k in range(segments):
		var b := k * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _mesh(verts, uvs, idx)


static func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
