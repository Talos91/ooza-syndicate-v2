class_name PerfProfile
extends Node
## Alpha 21 OPT-RENDER: the graphics profile (Daniele: "phone overheats"; co-op "lag still a major problem" with
## the PAUSE CONNECTION line showing LOW FPS - the renderer, not the network) and the map batching.
## main.gd calls PerfProfile.apply(self) once at the top of _ready (one marked line); this node then
## - batches the map's static kit pieces once a match is set up (MapBatch, map_batch.gd), on every profile
##   (it draws the same pixels, only in fewer draw calls);
## - applies the 3D settings of the profile to each match: render scale, MSAA, shadows, glow, lights;
## - caps the frame rate: lower on phones, lower still while nothing moves (menus, a paused or ended match).
##
## OPTIONS > GRAPHICS (Daniele, Alpha 21 list: "low res mode (in OPTIONS) for weak phones"), saved in
## user://settings.cfg:
##   AUTO     - PHONE on a phone / tablet / touch browser (or --mobile), FULL on a desktop.
##   LOW RES  - the strongest savings: 3D at half resolution, 30 fps, no shadows / glow / extra lights,
##              LOW detail (half particles, fewer river patches, no normal maps), the lite goo shader.
##   FULL     - today's look (a phone still gets main._apply_quality's 0.75 scale / no shadows / no MSAA).
## The profile each one resolves to: "phone", "low" or "full" (level()).

const SETTINGS := "user://settings.cfg"
const MODES := ["auto", "low", "full"]
const MODE_NAMES := {"auto": "AUTO", "low": "LOW RES", "full": "FULL"}
# per profile: 3D render scale (null: leave it), fps while playing / while idle, shadows, glow, the two
# fill lights, LOW detail
const PROFILES := {
	"full": {"scale": null, "fps": 60, "idle_fps": 60, "shadows": true, "glow": true, "fill_lights": true, "low_detail": false},
	"phone": {"scale": 0.7, "fps": 45, "idle_fps": 30, "shadows": false, "glow": true, "fill_lights": true, "low_detail": false},
	"low": {"scale": 0.5, "fps": 30, "idle_fps": 30, "shadows": false, "glow": false, "fill_lights": false, "low_detail": true},
}

static var path := SETTINGS             # tests point this elsewhere
static var _mode := ""                  # the saved setting ("" until read)
static var _live: PerfProfile = null
static var _forced_low_detail := false  # LOW RES turned Rules.low_detail on (and turns it back off)

var main: Node3D
var _batched := false
var _applied_3d := false


# ------------------------------------------------------------------ the setting
static func mode() -> String:
	if _mode == "":
		var cf := ConfigFile.new()
		_mode = "auto"
		if cf.load(path) == OK:
			var m := str(cf.get_value("graphics", "mode", "auto"))
			_mode = m if m in MODES else "auto"
	return _mode


static func set_mode(m: String) -> void:
	## OPTIONS > GRAPHICS: save the choice and apply what can change at once (fps cap, detail); the 3D
	## settings follow at the next match.
	_mode = m if m in MODES else "auto"
	_level = ""
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("graphics", "mode", _mode)
	cf.save(path)
	_apply_static()
	if _live != null and is_instance_valid(_live):
		_live._applied_3d = false


static func next_mode() -> String:
	return MODES[(MODES.find(mode()) + 1) % MODES.size()]


static func is_phone() -> bool:
	## A phone, tablet or touch browser - or a desktop run with --mobile (main.mobile's test, plus touch web).
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if "--mobile" in OS.get_cmdline_user_args():
		return true
	return OS.has_feature("web") and DisplayServer.is_touchscreen_available()


static var _level := ""                 # level(), cached until the setting changes


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


static func lite() -> bool:
	## Cheaper geometry / shaders for the goo and the like: the phone and LOW RES profiles.
	return level() != "full"


static func label() -> String:
	## The OPTIONS button text.
	var m := mode()
	var what := {"auto": "phone profile on phones, full look on desktop  (now: %s)" % ("PHONE" if is_phone() else "FULL"),
			"low": "for weak phones - half-resolution 3D, 30 fps, no glow / shadows",
			"full": "the full look"}
	return "GRAPHICS: %s  -  %s" % [MODE_NAMES[m], what[m]]


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
	if "--no-batch" in OS.get_cmdline_user_args():
		MapBatch.disabled = true


func _exit_tree() -> void:
	if _live == self:
		_live = null


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
	var cap: int = p["idle_fps"] if idle else p["fps"]
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
