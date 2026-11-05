class_name LookThumbs
extends Cosmetics.Preview
## ARMIES > CUSTOMIZE's category icons (Daniele 2026-11-05: "the categories show the MODEL as an icon"): a small
## still picture of a look's model - the family's default, or the equipped look - rendered ONCE by one hidden
## offscreen viewport, one look after another, and kept as a texture for the session (phones: never one 3D
## viewport per tile). LookThumbs.rect() hands out a TextureRect that fills in when its picture is ready.

const PX := 160                                          # the rendered picture's side (pixels)
static var _cache := {}                                  # model key -> ImageTexture
static var _waiting := {}                                # model key -> [TextureRect]
static var _queue := []                                  # [[family, id, faction, key]]
static var _stage: LookThumbs = null

var _job := []
var _frames := 0
var _settle := 0


static func rect(family: String, id: String, faction: String, dims: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = dims
	var key := Cosmetics.model_key(family, id, faction, 2 if family in ["vat", "machinegoon"] else 1)
	if _cache.has(key):
		r.texture = _cache[key]
		return r
	if not _waiting.has(key):
		_waiting[key] = []
		_queue.append([family, id, faction, key])
		if key.begins_with("skins/"):
			Cosmetics._ready(key)                        # every skin starts loading now, side by side
	(_waiting[key] as Array).append(r)
	_ensure_stage()
	return r


static func busy() -> bool:
	## A picture is still being made (the menu screenshot waits for them).
	return not _queue.is_empty() or (_stage != null and not _stage._job.is_empty())


static func _ensure_stage() -> void:
	if _stage != null and is_instance_valid(_stage):
		return
	var root := (Engine.get_main_loop() as SceneTree).root
	var layer := CanvasLayer.new()
	layer.layer = -100
	root.add_child.call_deferred(layer)
	_stage = LookThumbs.new()
	_stage.custom_minimum_size = Vector2(PX, PX)
	_stage.size = Vector2(PX, PX)
	_stage.position = Vector2(-8000, -8000)            # never on screen
	layer.add_child(_stage)


func _ready() -> void:
	family = "vat"
	super()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X if not Scenery.ios_safe() else Viewport.MSAA_DISABLED
	var fill := DirectionalLight3D.new()                 # a cool fill from the left: dark kits still read small
	fill.rotation = Vector3(deg_to_rad(-18), deg_to_rad(-75), 0)
	fill.light_color = Color(0.72, 0.84, 1.0)
	fill.light_energy = 0.7
	_vp.add_child(fill)


func _process(_dt: float) -> void:
	if _job.is_empty():
		if _queue.is_empty():
			return
		var pick := 0                                    # a look whose model is in first
		for qi in range(_queue.size()):
			var qk: String = _queue[qi][3]
			if not qk.begins_with("skins/") or Cosmetics._ready(qk):
				pick = qi
				break
		_job = _queue.pop_at(pick)
		family = _job[0]
		id = _job[1]
		faction = _job[2]
		tier = 0
		_key = ""
		_frames = 0
		_settle = 0
	_pivot.rotation.y = 0.55                           # one fixed three-quarter view
	_frames += 1
	_cam.fov = 32.0                                    # Preview frames the model for 32 degrees...
	var was := _key
	_refresh()
	_cam.fov = 21.0                                    # ...the icon looks closer, so the model fills its tile
	if _key != was:
		_settle = 0
	# a skin still loading: wait for it (up to ~2 s), else the picture shows the family's default
	if _key != str(_job[3]) and _frames < 120:
		return
	if _key == "":
		return
	_settle += 1
	if _settle < 3:                                    # the new model drawn at least once
		return
	var img := _vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	var k: String = _job[3]
	_cache[k] = tex
	for r in _waiting.get(k, []):
		if is_instance_valid(r):
			(r as TextureRect).texture = tex
	_waiting.erase(k)
	_job = []
