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
##                        pixel steps) with a 45 fps cap (15 while idle: menus, pause, results), and the light kit
##                        (hd() false); perf-ios: its 3D renders at PHONE_3D_PX_PER_PT pixels per CSS point (RenderScale).
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
# Daniele's "like minecraft"), so no profile ever uses the viewport's own scaling_3d_scale below 1.0. perf-ios
# (2026-11-01, her new iPhone hot after six matches: the 3D drawn at 2x resolution every frame): the linear-filtered
# path exists now (RenderScale, render_scale.gd: the 3D in a SubViewport shown through a LINEAR TextureRect, the HUD at
# native resolution), and PHONE uses it: "dpr" = PHONE_3D_PX_PER_PT 3D pixels per CSS point, so 0.75 of native on a
# dpr-2 phone (1.5x instead of 2x: 44 % fewer 3D pixels), 1.0 on a dpr-1 desktop (nothing lost), never under
# SCALE_3D_MIN. LOW RES keeps 1.0 (an open question for Daniele: it could take the same rule). --scale3d=0.75 forces a
# scale for a test run (never saved; 1 = off).
# Idle: PHONE idles at 30 fps - the menus, the result screen, a paused or ended match; a match being built under the VERSUS
# card is not idle (the staged load paces itself by frames). LOW RES stays at 30 everywhere. (perf-ios set 15 in 0.23.18;
# hotfix-02319 put it back to 30: Daniele found the menus laggy on his phone.)
const PHONE_3D_PX_PER_PT := 1.5          # PHONE: 3D pixels per CSS point (devicePixelRatio 2 -> scale 0.75)
const SCALE_3D_MIN := 0.6                # never softer than this (a dpr-3 phone would compute 0.5)
# per profile: 3D render scale (null: leave it; "dpr": the PHONE_3D_PX_PER_PT rule), fps while playing / idle, shadows,
# glow, the fill and rim lights, LOW detail, the lite goo shader, the share of each particle burst
const PROFILES := {
	"full": {"scale": null, "fps": 60, "idle_fps": 60, "shadows": true, "glow": true, "fill_lights": true,
			"low_detail": false, "lite": false, "particles": 1.0},
	"phone": {"scale": "dpr", "fps": 45, "idle_fps": 30, "shadows": false, "glow": true, "fill_lights": true,
			"low_detail": false, "lite": false, "particles": 1.0},
	"low": {"scale": 1.0, "fps": 30, "idle_fps": 30, "shadows": false, "glow": false, "fill_lights": true,
			"low_detail": true, "lite": true, "particles": 0.4},
}

static var path := "user://settings.cfg"   # tests point this elsewhere
static var _mode := ""                  # the saved GRAPHICS setting ("" until read)
static var _fps := ""                   # the saved FPS setting
static var _level := ""                 # level(), cached until the setting changes
static var _live: PerfProfile = null
static var _scale_arg := -1.0           # --scale3d=<f>: a test run's 3D scale on every profile (never saved)
static var _forced_low_detail := false  # LOW RES turned Rules.low_detail on (and turns it back off)
static var _goo_lite: Shader = null

# Perf pass (2026-09-28): a script-time breakdown per view, for tests/perf_pass_probe.tscn. Off in play (one bool
# per sync); the probe turns it on and reads / clears `sections` (name -> [total us, max us, calls]).
static var sections_on := false
static var sections := {}


static func lap(name: String, t0: int) -> void:
	## Adds the time since `t0` (Time.get_ticks_usec) to section `name` while sections_on.
	if not sections_on:
		return
	var us := Time.get_ticks_usec() - t0
	var s: Array = sections.get(name, [])
	if s.is_empty():
		s = [0, 0, 0]
		sections[name] = s
	s[0] += us
	s[1] = maxi(s[1], us)
	s[2] += 1


var main: Node3D
var _batched := false
var _applied_3d := false
var _hi_checked := false                 # FOLDABLES: the hi tier's one frame-time check (_hi_check)
# per-match frame stats (Alpha 21, for Progression's telemetry `perf` event): sampled only while the match plays
const STATS_SKIP := 1.0                 # s after the match starts left out (the batching / first-frame hitch)
const LONG_FRAME_MS := 50.0             # a frame slower than this counts as a long frame (under 20 fps)
const STATS_CAP := 60000                # samples kept (~16 min at 60 fps); later frames only feed max / long / fps
var _frame_ms := PackedFloat32Array()
var _draw_calls := PackedInt32Array()
var _play_time := 0.0                   # s of play seen (including the skipped start)
var _frames := 0
var _ms_max := 0.0
var _long := 0
var _win_t := 0.0                       # the current 1 s window for fps_min
var _win_n := 0
var _fps_min := -1.0


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
		elif a.begins_with("--scale3d=") and a.substr(10).is_valid_float():
			_scale_arg = clampf(float(a.substr(10)), 0.25, 1.0)


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


static var uncapped := false                          # main --world-probe: no frame cap while it measures
static func device_pixel_ratio() -> float:
	## The screen's pixels per CSS point (the web's window.devicePixelRatio, which web/viewport-fix.js caps at 2 on iOS;
	## a desktop's display scale otherwise; 1.0 when unknown).
	var s := DisplayServer.screen_get_scale()
	return s if s > 0.0 else 1.0


# ------------------------------------------------------------------ FOLDABLES (ui-fold, 2026-11-07): quality tier "hi"
# Daniele: "load backgrounds and graphics in higher quality when such a device is identified" (foldables, inner screen). The
# rule is capability, never the brand: a BIG screen (CSS short side >= HI_MIN_SHORT_PT: a book foldable's inner screen, a
# tablet) AND a capable GPU / device as the browser reports them (WebGL MAX_TEXTURE_SIZE >= HI_MIN_TEX; navigator.deviceMemory
# >= HI_MIN_MEM_GB and hardwareConcurrency >= HI_MIN_CORES where the browser tells - Safari reports neither, so there the
# texture size alone decides), on the PHONE profile only (LOW RES never; FULL is a desktop, already native). What hi changes:
#   - the 3D renders at HI_3D_PX_PER_PT pixels per CSS point instead of PHONE_3D_PX_PER_PT (native on a DPR-2 screen);
#   - hi_path() swaps a texture for its higher-resolution copy where one is shipped (HI_FILES; none yet, see there).
# Safe fallback: after HI_CHECK_S s of play, if the median frame is slower than HI_MAX_MS, the 3D drops back to the PHONE
# scale for the rest of the session (hi_dropped; the textures stay - memory only). --tier=hi / --tier=std force it (tests,
# emulation captures; never saved).
const HI_3D_PX_PER_PT := 2.0
const HI_MIN_SHORT_PT := 560.0
const HI_MIN_TEX := 8192
const HI_MIN_MEM_GB := 6.0
const HI_MIN_CORES := 6
const HI_CHECK_S := 8.0
const HI_MAX_MS := 1000.0 / 40.0
# hi copies: shipped path -> its higher-resolution file. EMPTY on purpose (2026-11-07): no higher-resolution source exists yet -
# the lab floor is R5-lab-floor-2048 (made from a 1254 px tile), the decal atlas is a native-resolution 2048 crop of
# LAB-FLOOR-DECALS-4096, the lab sides are 2560 px natives. The director asks are in 05 Handoff/FOLDABLES-2026-11.md; a new file
# goes in assets/world/hi/ and gets one row here (worlds load through hi_path).
const HI_FILES := {}
static var hi_dropped := false
static var _caps := {}


static func caps() -> Dictionary:
	## What the browser reports about the device (web only; {} elsewhere): max_tex, mem (GB, 0 unknown), cores (0 unknown),
	## short / long (the CSS screen, landscape), dpr. Read once (web/viewport-fix.js OozeViewport.caps()).
	if not _caps.is_empty() or not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return _caps
	var js = JavaScriptBridge.eval("window.OozeViewport && OozeViewport.caps ? JSON.stringify(OozeViewport.caps()) : ''", true)
	var d = JSON.parse_string(str(js)) if str(js) != "" else null
	_caps = d if d is Dictionary else {"none": true}
	return _caps


static func tier_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tier="):
			return a.substr(7)
	return ""


static func hi_capable() -> bool:
	## The device test alone (big screen + capable GPU), before the profile and the fallback.
	var t := tier_arg()
	if t != "":
		return t == "hi"
	var c := caps()
	if not c.has("max_tex"):
		return false
	var short := minf(float(c.get("w", 0)), float(c.get("h", 0)))
	var mem := float(c.get("mem", 0))
	var cores := int(c.get("cores", 0))
	return short >= HI_MIN_SHORT_PT and int(c["max_tex"]) >= HI_MIN_TEX 			and (mem <= 0.0 or mem >= HI_MIN_MEM_GB) and (cores <= 0 or cores >= HI_MIN_CORES)


static func hi() -> bool:
	## Quality tier "hi" right now (see above).
	if tier_arg() == "hi":
		return not hi_dropped
	return level() == "phone" and not hi_dropped and hi_capable()


static func hi_textures() -> bool:
	## The higher-resolution textures: chosen once at load, kept after a fallback (a swap mid-match would hitch).
	return (tier_arg() == "hi") or (tier_arg() == "" and level() == "phone" and hi_capable())


static func hi_path(path: String) -> String:
	## A texture's hi copy when the tier is hi and one is shipped, else the path itself.
	if hi_textures() and HI_FILES.has(path) and ResourceLoader.exists(HI_FILES[path]):
		return HI_FILES[path]
	return path


static func scale_3d() -> float:
	## The 3D render scale of the current profile, 1.0 = native (no scaled path). --scale3d= wins for a test run.
	_load()
	if _scale_arg > 0.0:
		return _scale_arg
	var sc = PROFILES[level()]["scale"]
	if sc == null:
		return 1.0
	if sc is String:                                      # "dpr": PHONE_3D_PX_PER_PT 3D pixels per CSS point
		return clampf((HI_3D_PX_PER_PT if hi() else PHONE_3D_PX_PER_PT) / device_pixel_ratio(), SCALE_3D_MIN, 1.0)
	return clampf(float(sc), 0.25, 1.0)


static func play_fps() -> int:
	## The frame cap while a match runs: the FPS setting, or the profile's own; LOW RES stays at 30.
	var own: int = PROFILES[level()]["fps"]
	if level() == "low" or fps_mode() == "auto":
		return own
	return int(fps_mode())


static func label() -> String:
	## The OPTIONS GRAPHICS button text.
	if mode() == "auto":
		return "GRAPHICS: AUTO (%s)" % (("PHONE HI" if hi() else "PHONE") if is_phone() else "FULL")   # FOLDABLES: the hi tier shows here; LOW RES turns it off
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


static func match_stats() -> Dictionary:
	## This match's frame stats so far ({} before any play or on a room server): frame time p50 / p95 / max (ms),
	## fps average and the worst 1 s window, draw calls p95, the count of long frames (> LONG_FRAME_MS), the
	## frames and seconds sampled and the GRAPHICS level. Only time spent playing counts (not menus, pauses or
	## the result screen). Progression's telemetry reads it once per match.
	if _live == null or _live._frames == 0:
		return {}
	return _live._stats()


func _stats() -> Dictionary:
	var ms := _frame_ms.duplicate()
	ms.sort()
	var dc := _draw_calls.duplicate()
	dc.sort()
	var sampled := 0.0
	for v in _frame_ms:
		sampled += v
	return {"frame_ms_p50": _pct(ms, 0.5), "frame_ms_p95": _pct(ms, 0.95), "frame_ms_max": snappedf(_ms_max, 0.1),
			"fps_avg": snappedf(ms.size() * 1000.0 / maxf(sampled, 1.0), 0.1),
			"fps_min": snappedf(_fps_min if _fps_min >= 0.0 else ms.size() * 1000.0 / maxf(sampled, 1.0), 0.1),
			"draw_calls_p95": int(_pct(dc, 0.95)), "long_frames": _long, "frames": _frames,
			"seconds": snappedf(maxf(0.0, _play_time - STATS_SKIP), 0.1), "level": level()}


static func _pct(sorted: Variant, q: float) -> float:
	if sorted.size() == 0:
		return 0.0
	return snappedf(float(sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)]), 0.1)


func _sample(dt: float) -> void:
	_play_time += dt
	if _play_time < STATS_SKIP:
		return
	var ms := dt * 1000.0
	_frames += 1
	_ms_max = maxf(_ms_max, ms)
	if ms > LONG_FRAME_MS:
		_long += 1
	if _frame_ms.size() < STATS_CAP:
		_frame_ms.append(ms)
		_draw_calls.append(int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	_win_t += dt
	_win_n += 1
	if _win_t >= 1.0:
		var f := _win_n / _win_t
		_fps_min = f if _fps_min < 0.0 else minf(_fps_min, f)
		_win_t = 0.0
		_win_n = 0


# ------------------------------------------------------------------ main's hook
static func apply(m: Node3D) -> void:
	## main.gd, top of _ready (one marked line). A dedicated room server renders nothing: left alone.
	var net := m.get_node_or_null("/root/Net")         # (by path: the headless --script tests have no autoloads)
	if net != null and bool(net.get("dedicated")):
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


func _process(dt: float) -> void:
	var started := bool(main.get("started"))
	var p: Dictionary = PROFILES[level()]
	if started and not _batched and main.get("vis") is Dictionary and main.get("sim") != null:
		_batched = true
		MapBatch.build(main)
	if started and not _applied_3d:
		_applied_3d = true
		_apply_3d(p)
	var sim = main.get("sim")
	# idle: the menus (not started, the menu up - a match being built under the VERSUS card keeps the play cap: the
	# staged load paces itself by frames), a paused offline match, an ended one (the result screen)
	var menu_up := main.get("menu_layer") != null and is_instance_valid(main.get("menu_layer"))
	var idle := (not started and menu_up) or (bool(main.get("paused")) and not bool(main.get("online"))) \
			or (sim != null and bool(sim.get("over")))
	var play := play_fps()
	var cap: int = mini(int(p["idle_fps"]), play) if idle else play
	if PerfProfile.uncapped:                           # a frame-time probe (main --world-probe) measures uncapped
		cap = 0
	if Engine.max_fps != cap:
		Engine.max_fps = cap
	if not idle:
		_sample(dt)
		_hi_check()


func _hi_check() -> void:
	## FOLDABLES: the hi tier's safe fallback - too slow after HI_CHECK_S s of play: the 3D back to the PHONE scale.
	if _hi_checked or not hi() or _play_time < HI_CHECK_S or _frame_ms.size() < 60:
		return
	_hi_checked = true
	var ms := _frame_ms.duplicate()
	ms.sort()
	var p50 := _pct(ms, 0.5)
	if p50 <= HI_MAX_MS:
		return
	hi_dropped = true
	var sc := scale_3d()
	print("PERF hi tier dropped: median frame %.1f ms > %.1f; 3D scale -> %.2f" % [p50, HI_MAX_MS, sc])
	if RenderScale.current != null and is_instance_valid(RenderScale.current):
		RenderScale.current.scale = sc
		RenderScale.current._resize()
	elif sc < 1.0:
		RenderScale.attach(main, sc)


func _apply_3d(p: Dictionary) -> void:
	var vp := main.get_viewport()
	var sc := scale_3d()
	if sc < 1.0:                                     # perf-ios: the linear-filtered scaled path (render_scale.gd)
		var rs := RenderScale.attach(main, sc)
		if rs != null:
			vp = rs.sub
	if Scenery.ios_safe():                           # no off-screen 3D buffer on iOS (Scenery.ios_safe); never the viewport's own scaling
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif p["scale"] != null:                         # (the viewport's own scaling stays at 1.0: it would upscale unfiltered)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
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
