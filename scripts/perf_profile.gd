class_name PerfProfile
extends Node
## Alpha 21 OPT-RENDER: the graphics profile (Daniele: "phone overheats"; co-op "lag still a major problem" with
## the PAUSE CONNECTION line showing LOW FPS - the renderer, not the network) and the map batching.
## main.gd calls PerfProfile.apply(self) once at the top of _ready (one marked line); this node then
## - batches the map's kit pieces once a match is set up (MapBatch, map_batch.gd), on every profile (it
##   draws the same pixels in fewer draw calls);
## - applies the 3D settings of the profile to each match: render scale, MSAA, shadows, glow, fill lights;
## - caps the frame rate, lower while nothing moves (menus, a paused or ended match);
## - trims every particle burst on LOW RES (a share of CPUParticles3D.amount).
##
## OPTIONS > PERFORMANCE (Daniele, Alpha 21: "low res mode (in OPTIONS) for weak phones", and a 30 / 60 fps
## choice), saved in user://settings.cfg [graphics]:
##   GRAPHICS  AUTO     - PHONE on a phone / tablet / touch browser (or --mobile), FULL on a desktop. PHONE
##                        is today's phone look (no shadows, all effects) at full 3D resolution (no more
##                        pixel steps) with a 45 fps cap (30 while idle), and the light kit (hd() false).
##             LOW RES  - the strongest savings (opt-in, weak phones): 30 fps, no shadows / glow, LOW
##                        detail (half effects, fewer river patches, no normal maps), the lite goo,
##                        particle bursts at 40 %. (The fill and rim lights stay: without them the board
##                        went near black - they cost almost nothing, no shadows.)
##             FULL     - today's look, untouched (a phone keeps main._apply_quality's 0.75 scale / no
##                        shadows / no MSAA).
##   FPS       AUTO (the profile's: 60 FULL, 45 PHONE, 30 LOW RES) / 30 / 60 - LOW RES stays at 30.
## level() is what GRAPHICS resolves to: "full", "phone" or "low".

const MODES := ["auto", "low", "full"]
const MODE_NAMES := {"auto": "AUTO", "low": "LOW RES", "full": "FULL"}
const FPS_MODES := ["auto", "30", "60"]
# Daniele (Alpha 21): "i hope you are not reducing the graphic of the game" - AUTO (PHONE / FULL) looks exactly
# as before: the same resolution, effects, particles and shaders; its savings are the batching and the fps
# cap. Only LOW RES, an explicit opt-in for weak phones, trades looks (effects, not pixels).
# Render scale: GL Compatibility upscales a scaled 3D buffer WITHOUT filtering (measured in Alpha 21: at 0.75 -
# main._apply_quality's phone default since Alpha 14 - and 0.6 the edges turn into hard pixel steps,
# Daniele's "like minecraft"), so both lighter profiles render the 3D at full resolution (1.0) until a
# linear-filtered path exists (a SubViewport shown through a linear TextureRect). No profile scales today.
# per profile: 3D render scale (null: leave it), fps while playing / idle, shadows, glow, the fill and rim
# lights, LOW detail, the lite goo shader, the share of each particle burst
const PROFILES := {
	"full": {"scale": null, "fps": 60, "idle_fps": 60, "shadows": true, "glow": true, "fill_lights": true,
			"low_detail": false, "lite": false, "particles": 1.0},
	"phone": {"scale": 1.0, "fps": 45, "idle_fps": 30, "shadows": false, "glow": true, "fill_lights": true,
			"low_detail": false, "lite": false, "particles": 1.0},
	"low": {"scale": 1.0, "fps": 30, "idle_fps": 30, "shadows": false, "glow": false, "fill_lights": true,
			"low_detail": true, "lite": true, "particles": 0.4},
}

static var path := "user://settings.cfg"   # tests point this elsewhere
static var _mode := ""                  # the saved GRAPHICS setting ("" until read)
static var _fps := ""                   # the saved FPS setting
static var _level := ""                 # level(), cached until the setting changes
static var _live: PerfProfile = null
static var _forced_low_detail := false  # LOW RES turned Rules.low_detail on (and turns it back off)
static var _goo_lite: Shader = null

var main: Node3D
var _batched := false
var _applied_3d := false


# ------------------------------------------------------------------ the settings
static func _load() -> void:
	if _mode != "":
		return
	var cf := ConfigFile.new()
	_mode = "auto"
	_fps = "auto"
	if cf.load(path) == OK:
		var m := str(cf.get_value("graphics", "mode", "auto"))
		_mode = m if m in MODES else "auto"
		var f := str(cf.get_value("graphics", "fps", "auto"))
		_fps = f if f in FPS_MODES else "auto"
	for a in OS.get_cmdline_user_args():             # --graphics=low / --fps=30: a test run's choice, never saved
		if a.begins_with("--graphics=") and a.substr(11) in MODES:
			_mode = a.substr(11)
		elif a.begins_with("--fps=") and a.substr(6) in FPS_MODES:
			_fps = a.substr(6)


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("graphics", "mode", _mode)
	cf.set_value("graphics", "fps", _fps)
	cf.save(path)


static func mode() -> String:
	_load()
	return _mode


static func fps_mode() -> String:
	_load()
	return _fps


static func set_mode(m: String) -> void:
	## OPTIONS > GRAPHICS: saved; the fps cap and LOW detail change at once, the 3D settings at the next match.
	_load()
	_mode = m if m in MODES else "auto"
	_level = ""
	_save()
	_apply_static()
	if _live != null and is_instance_valid(_live):
		_live._applied_3d = false


static func set_fps(f: String) -> void:
	_load()
	_fps = f if f in FPS_MODES else "auto"
	_save()


static func next_mode() -> String:
	return MODES[(MODES.find(mode()) + 1) % MODES.size()]


static func next_fps() -> String:
	return FPS_MODES[(FPS_MODES.find(fps_mode()) + 1) % FPS_MODES.size()]


static func is_phone() -> bool:
	## A phone, tablet or touch browser - or a desktop run with --mobile (main.mobile's test, plus touch web).
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if "--mobile" in OS.get_cmdline_user_args():
		return true
	return OS.has_feature("web") and DisplayServer.is_touchscreen_available()


static func level() -> String:
	if _level == "":
		match mode():
			"low":
				_level = "low"
			"full":
				_level = "full"
			_:
				_level = "phone" if is_phone() else "full"
	return _level


static func force_level(l: String) -> void:
	## tests/perf_check: measure a profile whatever this machine is (never saved).
	_load()
	_level = l if PROFILES.has(l) else ""
	_apply_static()


static func hd() -> bool:
	## The full-detail kit models (OPT-MESH: hd.pck / skins_hd.pck) or the light phone copies: AUTO on a
	## desktop and FULL use HD, AUTO on a phone and LOW RES the light set (Daniele, Alpha 21: light models
	## for phones only).
	return level() == "full"


static func lite() -> bool:
	## Cheaper shaders (the goo): LOW RES only.
	return bool(PROFILES[level()]["lite"])


static func play_fps() -> int:
	## The frame cap while a match runs: the FPS setting, or the profile's own; LOW RES stays at 30.
	var own: int = PROFILES[level()]["fps"]
	if level() == "low" or fps_mode() == "auto":
		return own
	return int(fps_mode())


static func label() -> String:
	## The OPTIONS GRAPHICS button text.
	if mode() == "auto":
		return "GRAPHICS: AUTO (%s)" % ("PHONE" if is_phone() else "FULL")
	return "GRAPHICS: %s" % MODE_NAMES[mode()]


static func fps_label() -> String:
	if level() == "low":
		return "FPS: 30 (LOW RES)"
	if fps_mode() == "auto":
		return "FPS: AUTO (%d)" % play_fps()
	return "FPS: %s" % fps_mode()


static func goo_shader(full: Shader) -> Shader:
	## The goo territory shader, or on LOW RES its lite build (GOO_LITE: no clearcoat).
	if not lite():
		return full
	if _goo_lite == null:
		_goo_lite = Shader.new()
		_goo_lite.code = full.code.replace("shader_type spatial;", "shader_type spatial;\n#define GOO_LITE")
	return _goo_lite


static func _apply_static() -> void:
	var p: Dictionary = PROFILES[level()]
	if p["low_detail"] and not Rules.low_detail:
		Rules.low_detail = true
		_forced_low_detail = true
	elif not p["low_detail"] and _forced_low_detail:
		Rules.low_detail = false
		_forced_low_detail = false


# ------------------------------------------------------------------ main's hook
static func apply(m: Node3D) -> void:
	## main.gd, top of _ready (one marked line). A dedicated room server renders nothing: left alone.
	if Net.dedicated:
		return
	_apply_static()
	var node := PerfProfile.new()
	node.name = "PerfProfile"
	node.main = m
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	m.add_child(node)
	_live = node
	MapBatch.disabled = "--no-batch" in OS.get_cmdline_user_args()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _on_node_added(n: Node) -> void:
	if n is CPUParticles3D and float(PROFILES[level()]["particles"]) < 1.0:
		_cap_particles.call_deferred(n)               # after its maker has set the amount


func _cap_particles(n: Node) -> void:
	if not is_instance_valid(n) or n.has_meta("perf_capped"):
		return
	n.set_meta("perf_capped", true)
	var p := n as CPUParticles3D
	p.amount = maxi(1, roundi(p.amount * float(PROFILES[level()]["particles"])))


func _process(_dt: float) -> void:
	var started := bool(main.get("started"))
	var p: Dictionary = PROFILES[level()]
	if started and not _batched and main.get("vis") is Dictionary and main.get("sim") != null:
		_batched = true
		MapBatch.build(main)
	if started and not _applied_3d:
		_applied_3d = true
		_apply_3d(p)
	var sim = main.get("sim")
	var idle := not started or (bool(main.get("paused")) and not bool(main.get("online"))) \
			or (sim != null and bool(sim.get("over")))
	var play := play_fps()
	var cap: int = mini(int(p["idle_fps"]), play) if idle else play
	if Engine.max_fps != cap:
		Engine.max_fps = cap


func _apply_3d(p: Dictionary) -> void:
	var vp := main.get_viewport()
	if p["scale"] != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(p["scale"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
	var sun = main.get("sun")
	for c in main.get_children():
		if c is DirectionalLight3D:
			if c == sun:
				if not p["shadows"]:
					(c as DirectionalLight3D).shadow_enabled = false
			elif not p["fill_lights"]:
				(c as DirectionalLight3D).visible = false
		elif c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			var env := (c as WorldEnvironment).environment
			if not p["glow"]:
				env.glow_enabled = false
			if not p["fill_lights"]:                 # the fill and rim lights' share goes to the ambient
				env.ambient_light_energy = maxf(env.ambient_light_energy, 0.55)
