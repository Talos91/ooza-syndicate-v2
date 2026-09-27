class_name Cosmetics
extends RefCounted
## Cosmetic looks per player (0.19.0 "Alpha 19"; Lane fight fun batch 2, Daniele 2026-09-27). One generic
## system: each seat picks one look per structure family (its loadout); a node shows the look its OWNER
## picked, looked up when it is built or captured (MapBuilder.model_for asks key_for every frame, so a
## capture swaps the model like a tier change does). Pure view: the rules never read it.
##
## CONTRACT (the HUD agent's ARMIES > COSMETICS page, main's per-seat apply and the room's player info):
##   OPTIONS[family] -> Array of ids; families "vat", "machinegoon", "laser", "forge", "monster_hub", "monster"
##   label(family, id, faction) -> String            "DEFAULT", "VEX", "GRADUATE", "SPITTER", "SKYRIG"...
##   set_loadout(seat, {family: id}) / loadout(seat) -> {family: id} (every family present, "default" if unset)
##   set_factions(sim.factions) at match start / faction_of(seat) (a monster hub, the monster and the
##       "faction" vat set follow the owner's faction)
##   scene_for(family, id, faction, tier) -> PackedScene or null   the default look loads at once; a skin
##       starts a threaded load and returns null until it is in (callers show the default meanwhile)
##   points(model_name) -> {"muzzles": [Vector3], "emitter": Vector3, "lift": float, "gate": Vector3,
##       "stand": Vector3, "spin": {"axis": Vector2, "r": float, "z0": float}} in the model's own Godot space
##       (metres, y up, front +Z) - whichever of those the model has
## Also key_for(family, seat, tier) -> the kit key MapBuilder places ("Vat_T2", "skins/Skin_Hive_T2").
##
## SKINS LOAD ONLY WHEN NEEDED (Daniele: "like in other games skin are loaded only when necessary"): nothing
## under assets/kit/skins is preloaded. The first time a node (or a menu preview) asks for a skin it gets a
## ResourceLoader threaded request and the default model meanwhile; once loaded the next ask returns it and
## the node swaps. A skin nobody asked for in UNUSED_FRAMES frames is dropped from the cache, so its scene is
## freed once the last node showing it is gone.
## WEB: assets/kit/skins is not in index.pck (the "Web" preset excludes it); it ships as skins.pck beside it
## (the "Web Skins" preset, BUILD-LOG sec10). The first skin a web player needs downloads skins.pck once from
## the page's own folder (HTTPRequest -> user://skins.pck), ProjectSettings.load_resource_pack mounts it, then
## the lazy threaded load runs as on desktop. Until then - and for good if the download fails - the default
## model shows. Desktop and editor runs load the skins straight from res://.
## Skin vats live like the default ones (Scenery's liquid and residents, HordeView's drops out of the tanks):
## is_vat_key / drops_from say which models are vats, TANKS holds each skin vat's tanks.

const FAMILIES := ["vat", "machinegoon", "laser", "forge", "monster_hub", "monster"]
const OPTIONS := {
	"vat": ["default", "faction", "graduate", "biopod", "crystal", "distillery", "hive", "reactor"],
	"machinegoon": ["default", "spitter", "pepperbox"],
	"laser": ["default", "obelisk", "tesla"],
	"forge": ["default", "anvil", "heartforge"],
	"monster_hub": ["default", "hatchery", "pit"],
	"monster": ["default", "alt"],
}
const MONSTER_ALT := {"vex": "Skyrig", "null": "Monolith", "bloom": "Maneater", "ember": "Titan", "solar": "Eclipse"}
const SKIN_LINE := {"biopod": "BioPod", "crystal": "Crystal", "distillery": "Distillery", "hive": "Hive", "reactor": "Reactor"}
const KIT := "res://assets/kit/%s.glb"
const UNUSED_FRAMES := 600           # ~10 s at 60 fps without a single ask: the skin leaves the cache
const LIFT := 0.56                   # ATTACH_Z - SOCKET_Z: the laser looks stand on a relay's attachment socket

static var _loadouts := {}           # seat -> {family: id}
static var _factions := {}           # seat -> faction
static var _keys := {}               # "family|id|faction|tier" -> kit key (built once per combination)
static var _seat_keys := {}          # seat -> family -> tier -> kit key of the seat's pick (key_for's cache)
static var _cache := {}              # skin key -> PackedScene (loaded)
static var _pending := {}            # skin key -> true while its threaded load runs
static var _asked := {}              # skin key -> last frame someone asked for it
static var _failed := {}             # skin key -> true: missing file or failed load (the default stays)
static var _last_prune := 0
const SKINS_PACK := "skins.pck"
const SKINS_FILE := "user://skins.pck"
static var _pack := ""                # web: "" not asked yet / "loading" / "ready" / "failed"
static var _http: HTTPRequest


# ------------------------------------------------------------------ loadouts
static func set_loadout(seat: String, looks: Dictionary) -> void:
	var d := {}
	for f in FAMILIES:
		var id := str(looks.get(f, "default"))
		d[f] = id if id in OPTIONS[f] else "default"
	_loadouts[seat] = d
	_seat_keys.erase(seat)


static func loadout(seat: String) -> Dictionary:
	if not _loadouts.has(seat):
		set_loadout(seat, {})
	return (_loadouts[seat] as Dictionary).duplicate()


static func set_factions(seat_factions: Dictionary) -> void:
	_factions = seat_factions.duplicate()
	_seat_keys = {}
	if _pack == "failed":                            # a new match may try the skins pack again
		_pack = ""
		_failed = {}


static func faction_of(seat: String) -> String:
	return str(_factions.get(seat, "null"))


static func clear() -> void:
	## A new match: forget the seats (the cache of loaded skins stays until it expires).
	_loadouts = {}
	_factions = {}
	_seat_keys = {}


static func label(family: String, id: String, faction: String) -> String:
	match id:
		"default":
			return "DEFAULT"
		"faction":
			return faction.to_upper()
		"alt":
			return str(MONSTER_ALT.get(faction, "ALT")).to_upper()
	return id.to_upper()


# ------------------------------------------------------------------ models
static func model_key(family: String, id: String, faction: String, tier: int) -> String:
	## The kit key of a look ("Vat_T2", "skins/NULL_Vat_T2", "MonsterVat_EMBER"...). Cached per combination.
	var ck := "%s|%s|%s|%d" % [family, id, faction, tier]
	if _keys.has(ck):
		return _keys[ck]
	var race := (faction if faction in MONSTER_ALT else "null").to_upper()
	var t := clampi(tier, 1, 4)
	var key := ""
	match family:
		"vat":
			match id:
				"faction":
					key = "skins/%s_Vat_T%d" % [race, t]
				"graduate":
					key = "skins/Vat_Graduate_T%d" % t
				"default":
					key = "Vat_T%d" % t
				_:
					key = "skins/Skin_%s_T%d" % [SKIN_LINE[id], t] if SKIN_LINE.has(id) else "Vat_T%d" % t
		"machinegoon":
			t = clampi(t, 1, 3)
			key = {"spitter": "skins/GooGun_T%d_Spitter" % t, "pepperbox": "skins/GooGun_T%d_Pepperbox" % t}.get(id, "Machinegoon_T%d" % t)
		"laser":
			key = {"obelisk": "skins/Laser_Obelisk", "tesla": "skins/Laser_Tesla"}.get(id, "Laser")
		"forge":
			key = {"anvil": "skins/Forge_Anvil", "heartforge": "skins/Forge_Heartforge"}.get(id, "Forge")
		"monster_hub":
			key = {"hatchery": "skins/MonsterHub_%s_Hatchery" % race, "pit": "skins/MonsterHub_%s_Pit" % race}.get(id, "MonsterVat_%s" % race)
		"monster":
			key = "skins/Monster_%s_%s" % [race, MONSTER_ALT.get(race.to_lower(), "Skyrig")] if id == "alt" else "Monster_%s" % race
	_keys[ck] = key
	return key


static func key_for(family: String, seat: String, tier: int) -> String:
	## What a node of `seat` shows for `family` right now: its skin once loaded, the default until then
	## (the ask starts the load). Called per node per frame (MapBuilder.model_for): tables and nested
	## caches only, no string formatting after the first ask.
	var faction: String = _factions.get(seat, "null")
	var lo = _loadouts.get(seat)
	var id: String = "default" if lo == null else str((lo as Dictionary).get(family, "default"))
	if id == "default":
		return default_key(family, faction, tier)
	var by_seat: Dictionary = _seat_keys.get(seat, {})
	if by_seat.is_empty():
		_seat_keys[seat] = by_seat
	var by_family: Dictionary = by_seat.get(family, {})
	if by_family.is_empty():
		by_seat[family] = by_family
	var key: String = by_family.get(tier, "")
	if key == "":
		key = model_key(family, id, faction, tier)
		by_family[tier] = key
	if not key.begins_with("skins/"):
		return key
	return key if _ready(key) else default_key(family, faction, tier)


const _VAT := ["Vat_T1", "Vat_T1", "Vat_T2", "Vat_T3", "Vat_T4"]
const _MG := ["Machinegoon_T1", "Machinegoon_T1", "Machinegoon_T2", "Machinegoon_T3", "Machinegoon_T3"]
const _HUB := {"vex": "MonsterVat_VEX", "null": "MonsterVat_NULL", "bloom": "MonsterVat_BLOOM", "ember": "MonsterVat_EMBER", "solar": "MonsterVat_SOLAR"}
const _MONSTER := {"vex": "Monster_VEX", "null": "Monster_NULL", "bloom": "Monster_BLOOM", "ember": "Monster_EMBER", "solar": "Monster_SOLAR"}


static func default_key(family: String, faction: String, tier: int) -> String:
	match family:
		"vat":
			return _VAT[clampi(tier, 0, 4)]
		"machinegoon":
			return _MG[clampi(tier, 0, 4)]
		"laser":
			return "Laser"
		"forge":
			return "Forge"
		"monster_hub":
			return _HUB.get(faction, "MonsterVat_NULL")
		"monster":
			return _MONSTER.get(faction, "Monster_NULL")
	return ""


static func scene_for(family: String, id: String, faction: String, tier: int) -> PackedScene:
	var key := model_key(family, id, faction, tier)
	if not key.begins_with("skins/"):
		return load(KIT % key) as PackedScene
	return _cache.get(key) if _ready(key) else null


static func cached(key: String) -> PackedScene:
	## MapBuilder.piece: the loaded scene of a skin key (null if it is not in the cache).
	if _cache.has(key):
		_asked[key] = Engine.get_process_frames()
		return _cache[key]
	return null


static func _ready(key: String) -> bool:
	var frame := Engine.get_process_frames()
	_asked[key] = frame
	if frame - _last_prune > 120:
		_prune(frame)
	if _cache.has(key):
		return true
	if _failed.has(key):
		return false
	var path := KIT % key
	if _pending.has(key):
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_pending.erase(key)
			var res := ResourceLoader.load_threaded_get(path) as PackedScene
			if res:
				_cache[key] = res
				return true
			_failed[key] = true
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_pending.erase(key)
			_failed[key] = true
		return false
	if not ResourceLoader.exists(path):
		if OS.has_feature("web") and _pack in ["", "loading"]:
			_fetch_pack()                             # web: the skins come in skins.pck, asked for once
			return false
		_failed[key] = true                         # a file missing from the build: the default stays
		return false
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		_failed[key] = true
		return false
	_pending[key] = true
	return false


static func _prune(frame: int) -> void:
	_last_prune = frame
	for key in _cache.keys():
		if frame - int(_asked.get(key, 0)) > UNUSED_FRAMES:
			_cache.erase(key)                         # freed once no node holds its meshes any more
			_asked.erase(key)


static func _fetch_pack() -> void:
	## Web: download skins.pck from beside index.pck once and mount it (every failure: the defaults stay).
	if _pack != "":
		return
	_pack = "loading"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_pack = "failed"
		return
	var url := str(JavaScriptBridge.eval("new URL('%s?v=%s', window.location.href).href" % [SKINS_PACK, Rules.VERSION], true))
	_http = HTTPRequest.new()
	_http.download_file = SKINS_FILE
	# GitHub Pages serves the .pck gzip-encoded: the browser's fetch already inflates it, and HTTPRequest's own
	# gunzip of the same (already plain) body failed with RESULT_BODY_DECOMPRESS_FAILED on the live 0.19.1
	# ("skins don't look implemented"). Never gunzip here.
	_http.accept_gzip = false
	tree.root.add_child(_http)
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and ProjectSettings.load_resource_pack(SKINS_FILE, false)
		_pack = "ready" if ok else "failed"
		print("Cosmetics: %s %s (result %d, HTTP %d)" % [SKINS_PACK, "loaded" if ok else "not available - default looks", result, code])
		_http.queue_free()
		_http = null)
	print("Cosmetics: fetching ", url)
	if _http.request(url) != OK:
		_pack = "failed"


static func pack_state() -> String:
	## Debug / tests: the web skins pack's state ("" before any skin was needed).
	return _pack


static func loaded_skins() -> Array:
	## Debug / tests: the skin keys in the cache now.
	return _cache.keys()


# ------------------------------------------------------------------ attach points
# Godot space of the model (Blender x, y, z -> x, z, -y): front +Z, up +Y, metres, origin = the node centre.
# Muzzles and emitters are from the builders' printed contracts (Models/2.0/structures_2_1/build_*.py); the
# spin block is the barrel cluster that turns (axis parallel to +Z through (x, y); every mesh island wholly
# within r of it and in front of z0 turns, see MapBuilder.split_spinner). Gate pivots are read from the
# model's own `*_Gate` node at run time (MonsterView); "gate" here is the fallback.
const POINTS := {
	"Machinegoon_T1": {"muzzles": [Vector3(0, 2.72, 3.69)]},
	"Machinegoon_T2": {"muzzles": [Vector3(-0.39, 2.81, 4.42), Vector3(0.39, 2.81, 4.42)]},
	"Machinegoon_T3": {"muzzles": [Vector3(0, 2.92, 5.31)], "spin": {"axis": Vector2(0, 2.92), "r": 0.7, "z0": 1.3}},
	"GooGun_T1_Spitter": {"muzzles": [Vector3(0, 2.35, 1.89)]},
	"GooGun_T2_Spitter": {"muzzles": [Vector3(-0.32, 2.40, 2.30), Vector3(0.32, 2.40, 2.30)]},
	"GooGun_T3_Spitter": {"muzzles": [Vector3(0, 2.77, 2.87), Vector3(-0.34, 2.31, 2.87), Vector3(0.34, 2.31, 2.87)]},
	"GooGun_T1_Pepperbox": {"muzzles": [Vector3(0, 2.44, 2.03)], "spin": {"axis": Vector2(0, 2.44), "r": 0.34, "z0": 0.42}},
	"GooGun_T2_Pepperbox": {"muzzles": [Vector3(0, 2.50, 2.45)], "spin": {"axis": Vector2(0, 2.50), "r": 0.44, "z0": 0.48}},
	"GooGun_T3_Pepperbox": {"muzzles": [Vector3(0, 2.57, 2.97)], "spin": {"axis": Vector2(0, 2.57), "r": 0.54, "z0": 0.56}},
	"Laser": {"emitter": Vector3(0, 7.85, 0), "lift": LIFT},
	"Laser_Obelisk": {"emitter": Vector3(0, 7.51, 0), "lift": LIFT},
	"Laser_Tesla": {"emitter": Vector3(0, 6.42, 0), "lift": LIFT},
	"Forge": {},
	"Forge_Anvil": {},
	"Forge_Heartforge": {},
	"MonsterVat_VEX": {"gate": Vector3(0, 0.31, 2.35), "stand": Vector3(0, 1.44, 0)},
	"MonsterVat_NULL": {"gate": Vector3(0, 0.31, 2.24), "stand": Vector3(0, 1.44, 0)},
	"MonsterVat_BLOOM": {"gate": Vector3(0, 0.31, 2.19), "stand": Vector3(0, 1.44, 0)},
	"MonsterVat_EMBER": {"gate": Vector3(0, 0.31, 2.35), "stand": Vector3(0, 1.44, 0)},
	"MonsterVat_SOLAR": {"gate": Vector3(0, 0.31, 2.35), "stand": Vector3(0, 1.44, 0)},
	"MonsterHub_VEX_Hatchery": {"gate": Vector3(0, 0.31, 2.55), "stand": Vector3(0, 0.78, 0)},
	"MonsterHub_NULL_Hatchery": {"gate": Vector3(0, 0.31, 2.43), "stand": Vector3(0, 0.78, 0)},
	"MonsterHub_BLOOM_Hatchery": {"gate": Vector3(0, 0.31, 2.37), "stand": Vector3(0, 0.78, 0)},
	"MonsterHub_EMBER_Hatchery": {"gate": Vector3(0, 0.31, 2.55), "stand": Vector3(0, 0.78, 0)},
	"MonsterHub_SOLAR_Hatchery": {"gate": Vector3(0, 0.31, 2.55), "stand": Vector3(0, 0.78, 0)},
	"MonsterHub_VEX_Pit": {"gate": Vector3(0, 0.31, 2.30), "stand": Vector3(0, 0.68, 0)},
	"MonsterHub_NULL_Pit": {"gate": Vector3(0, 0.31, 2.18), "stand": Vector3(0, 0.68, 0)},
	"MonsterHub_BLOOM_Pit": {"gate": Vector3(0, 0.31, 2.12), "stand": Vector3(0, 0.68, 0)},
	"MonsterHub_EMBER_Pit": {"gate": Vector3(0, 0.31, 2.30), "stand": Vector3(0, 0.68, 0)},
	"MonsterHub_SOLAR_Pit": {"gate": Vector3(0, 0.31, 2.30), "stand": Vector3(0, 0.68, 0)},
}


static func points(model_name: String) -> Dictionary:
	## Attach points of a model by name, with or without the "skins/" prefix ({} for a plain model). A skin
	## vat's entry carries "tanks": [{"c": Vector3 (x, 0, z), "r", "y0", "y1"}] (Scenery.tank_info's shape).
	var name := model_name.trim_prefix("skins/")
	if TANKS.has(name):
		var d: Dictionary = POINTS.get(name, {}).duplicate()
		d["tanks"] = (TANKS[name] as Array).map(func(t): return {"c": Vector3(t[0], 0.0, t[1]), "r": t[2], "y0": t[3], "y1": t[4]})
		return d
	return POINTS.get(name, {})


# MACHINEGOON SIZE (0.19.2, Daniele on 0.19.1: "too big and when they shoot it looks weird as the enemies are
# under them"): every Machinegoon look is shown at MG_SCALE (about a vat's footprint) and sunk into its socket
# so its highest muzzle sits MG_MUZZLE_Y above the deck - the stream arcs out onto the line's bodies instead of
# pouring straight down. Applied to the model's children by MapBuilder.piece (the root keeps scale 1 for the
# build / pump / tier-down animations); the muzzles above stay in model space (the view reads them through
# the turret's global transform, so they follow the scale and the drop).
const MG_SCALE := 0.65
const MG_MUZZLE_Y := 1.15
const MG_LOOK_SCALE := {"Spitter": 1.45, "Pepperbox": 1.3}   # the skins are modelled smaller: same footprint


static func fit(model_name: String) -> Dictionary:
	## {"scale", "drop"} for a model shown smaller than modelled (the Machinegoon looks), {} otherwise.
	var pt: Dictionary = POINTS.get(model_name.trim_prefix("skins/"), {})
	if not pt.has("muzzles"):
		return {}
	var top := 0.0
	for m in pt["muzzles"]:
		top = maxf(top, (m as Vector3).y)
	var k: float = MG_SCALE * float(MG_LOOK_SCALE.get(model_name.trim_prefix("skins/").get_slice("_", 2), 1.0))
	return {"scale": k, "drop": maxf(0.0, top * k - MG_MUZZLE_Y)}


static func is_vat_key(key: String) -> bool:
	## A vat model (default or skin): it gets the living liquid and the residents (Scenery).
	return key.begins_with("Vat_") or TANKS.has(key.trim_prefix("skins/"))


static func drops_from(key: String) -> bool:
	## A T1-T3 vat model (default or skin): its lines drop out of its tanks (HordeView.vat_drop). T4's core
	## is the vat: its lines leave from the door.
	return is_vat_key(key) and not key.ends_with("_T4")


# Each skin vat's tanks, measured from its GLB's OS_Ooze mesh islands (stacked islands on one axis = one
# column; honeycomb cells and goo sheets under r 0.38 left out): [x, z, r, y0, y1] in the model's Godot space.
const TANKS := {
	"BLOOM_Vat_T1": [[-2.00, 0.00, 0.62, 1.00, 2.42], [-0.00, -0.00, 0.66, 3.20, 4.52]],
	"BLOOM_Vat_T2": [[-2.00, 0.00, 0.62, 1.00, 2.42], [-0.00, -0.00, 0.66, 4.60, 5.92], [2.00, 0.00, 0.62, 2.85, 4.27]],
	"BLOOM_Vat_T3": [[-2.00, 0.00, 0.62, 1.10, 5.02], [-0.00, -0.00, 0.66, 5.90, 7.22], [2.00, 0.00, 0.62, 1.10, 5.02]],
	"BLOOM_Vat_T4": [[-2.30, 0.00, 0.62, 1.85, 5.77], [-0.00, -0.00, 0.91, 1.10, 8.52], [2.30, 0.00, 0.62, 1.85, 5.77]],
	"EMBER_Vat_T1": [[-2.10, 0.00, 0.60, 0.51, 2.61]],
	"EMBER_Vat_T2": [[-2.10, 0.00, 0.60, 0.51, 2.61], [2.10, 0.00, 0.60, 2.36, 4.46]],
	"EMBER_Vat_T3": [[-2.10, 0.00, 0.60, 0.61, 5.21], [2.10, 0.00, 0.60, 0.61, 5.21]],
	"EMBER_Vat_T4": [[-2.35, 0.00, 0.60, 1.36, 5.96], [0.00, -0.03, 0.87, 1.66, 6.89], [2.35, 0.00, 0.60, 1.36, 5.96]],
	"NULL_Vat_T1": [[-2.10, 0.00, 0.50, 1.17, 2.22]],
	"NULL_Vat_T2": [[-2.10, 0.00, 0.50, 1.17, 2.22], [2.10, 0.00, 0.50, 3.01, 4.07]],
	"NULL_Vat_T3": [[-2.10, 0.00, 0.50, 1.26, 4.82], [2.10, 0.00, 0.50, 1.26, 4.82]],
	"NULL_Vat_T4": [[-2.40, 0.00, 0.50, 2.01, 5.57], [0.00, 0.00, 0.78, 0.70, 6.77], [2.40, 0.00, 0.50, 2.01, 5.57]],
	"SOLAR_Vat_T1": [[-2.15, 0.00, 0.52, 1.21, 2.21], [0.00, 0.00, 0.40, 3.33, 4.13]],
	"SOLAR_Vat_T2": [[-2.15, 0.00, 0.52, 1.21, 2.21], [0.00, 0.00, 0.40, 4.73, 5.53], [2.15, 0.00, 0.52, 3.06, 4.06]],
	"SOLAR_Vat_T3": [[-2.15, 0.00, 0.52, 1.31, 4.81], [0.00, 0.00, 0.40, 6.03, 6.83], [2.15, 0.00, 0.52, 1.31, 4.81]],
	"SOLAR_Vat_T4": [[-2.40, 0.00, 0.52, 2.06, 5.56], [0.00, 0.00, 0.92, 1.28, 8.13], [2.40, 0.00, 0.52, 2.06, 5.56]],
	"Skin_BioPod_T1": [[-2.05, 0.00, 0.52, 1.13, 2.33], [0.00, -0.00, 0.55, 3.37, 4.59]],
	"Skin_BioPod_T2": [[-2.05, 0.00, 0.52, 1.13, 2.33], [0.00, 0.00, 0.64, 4.75, 6.15], [2.05, 0.00, 0.52, 2.98, 4.18]],
	"Skin_BioPod_T3": [[-2.05, 0.00, 0.52, 1.23, 4.93], [0.00, -0.00, 0.72, 6.02, 7.61], [2.05, 0.00, 0.52, 1.23, 4.93]],
	"Skin_BioPod_T4": [[-2.35, 0.00, 0.52, 1.98, 5.68], [0.00, -0.00, 0.86, 1.96, 9.07], [2.35, 0.00, 0.52, 1.98, 5.68]],
	"Skin_Crystal_T1": [[-2.05, 0.00, 0.40, 1.25, 2.20], [0.00, 0.00, 0.62, 0.66, 4.09]],
	"Skin_Crystal_T2": [[-2.05, 0.00, 0.40, 1.25, 2.20], [0.00, 0.00, 0.62, 0.66, 5.49], [2.05, 0.00, 0.40, 3.11, 4.05]],
	"Skin_Crystal_T3": [[-2.05, 0.00, 0.40, 1.36, 4.80], [0.00, 0.00, 0.62, 0.66, 6.79], [2.05, 0.00, 0.40, 1.36, 4.80]],
	"Skin_Crystal_T4": [[-2.35, 0.00, 0.40, 2.11, 5.55], [0.00, 0.00, 0.78, 0.73, 8.10], [2.35, 0.00, 0.40, 2.11, 5.55]],
	"Skin_Distillery_T1": [[-2.05, 0.00, 0.42, 1.21, 2.21]],
	"Skin_Distillery_T2": [[-2.05, 0.00, 0.42, 1.21, 2.21], [2.05, 0.00, 0.42, 3.06, 4.06]],
	"Skin_Distillery_T3": [[-2.05, 0.00, 0.42, 1.31, 4.81], [2.05, 0.00, 0.42, 1.31, 4.81]],
	"Skin_Distillery_T4": [[-2.35, 0.00, 0.42, 2.06, 5.56], [0.00, 0.00, 0.70, 3.37, 7.02], [2.35, 0.00, 0.42, 2.06, 5.56]],
	"Skin_Hive_T1": [[-2.05, 0.00, 0.45, 1.22, 2.16]],
	"Skin_Hive_T2": [[-2.05, 0.00, 0.45, 1.22, 2.16], [2.05, 0.00, 0.45, 3.07, 4.01]],
	"Skin_Hive_T3": [[-2.05, 0.00, 0.45, 1.31, 4.76], [2.05, 0.00, 0.45, 1.31, 4.76]],
	"Skin_Hive_T4": [[-2.35, 0.00, 0.45, 2.07, 5.51], [0.00, 0.00, 0.74, 0.70, 6.82], [2.35, 0.00, 0.45, 2.07, 5.51]],
	"Skin_Reactor_T1": [[-2.05, 0.00, 0.38, 1.28, 2.18], [0.00, -0.00, 0.77, 1.84, 3.38]],
	"Skin_Reactor_T2": [[-2.05, 0.00, 0.38, 1.28, 2.18], [0.00, 0.00, 0.82, 2.56, 4.20], [2.05, 0.00, 0.38, 3.13, 4.03]],
	"Skin_Reactor_T3": [[-2.05, 0.00, 0.38, 1.38, 4.78], [0.00, 0.00, 0.87, 1.96, 5.99], [2.05, 0.00, 0.38, 1.38, 4.78]],
	"Skin_Reactor_T4": [[-2.35, 0.00, 0.38, 2.13, 5.53], [0.00, 0.00, 0.88, 1.71, 6.72], [2.35, 0.00, 0.38, 2.13, 5.53]],
	"VEX_Vat_T1": [[-2.05, 0.00, 0.52, 1.24, 2.28]],
	"VEX_Vat_T2": [[-2.05, 0.00, 0.52, 1.24, 2.28], [2.05, 0.00, 0.52, 3.09, 4.13]],
	"VEX_Vat_T3": [[-2.05, 0.00, 0.52, 1.34, 4.89], [2.05, 0.00, 0.52, 1.34, 4.89]],
	"VEX_Vat_T4": [[-2.35, 0.00, 0.52, 2.09, 5.64], [-0.22, 0.00, 0.67, 1.66, 6.72], [2.35, 0.00, 0.52, 2.09, 5.64]],
	"Vat_Graduate_T1": [[-2.15, -0.00, 0.86, 0.92, 2.17]],
	"Vat_Graduate_T2": [[-2.15, -0.00, 0.86, 0.92, 2.17], [2.15, 0.00, 0.86, 2.77, 4.02]],
	"Vat_Graduate_T3": [[-2.20, -0.00, 0.86, 1.02, 4.77], [2.20, 0.00, 0.86, 1.02, 4.77]],
	"Vat_Graduate_T4": [[-2.60, -0.00, 0.86, 1.77, 5.52], [0.00, 0.00, 0.95, 1.53, 6.53], [2.60, 0.00, 0.86, 1.77, 5.52]],
}


# ------------------------------------------------------------------ ARMIES previews (0.19.2)
static func make_preview(family: String, id: String, faction: String, size: Vector2) -> Control:
	## A small turning 3D preview of one look for the ARMIES > COSMETICS rows (menu.gd): the model in its own
	## world, lit, framed to fit, in the faction's colours. A skin shows the default model until it has loaded
	## (on the web that fetches skins.pck, as a match would), then swaps. Free it with its row.
	var p := Preview.new()
	p.family = family
	p.id = id
	p.faction = faction
	p.custom_minimum_size = size
	p.size = size
	return p


class Preview extends SubViewportContainer:
	var family := ""
	var id := "default"
	var faction := "null"
	var _vp: SubViewport
	var _pivot: Node3D
	var _cam: Camera3D
	var _key := ""
	var _t := 0.0

	func _ready() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.msaa_3d = Viewport.MSAA_2X
		add_child(_vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.55, 0.6, 0.75)
		env.environment.ambient_light_energy = 0.8
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		_vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
		sun.light_energy = 1.3
		_vp.add_child(sun)
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		_cam = Camera3D.new()
		_cam.fov = 32.0
		_vp.add_child(_cam)
		_refresh()

	func _process(dt: float) -> void:
		_t += dt
		_pivot.rotation.y = 0.6 * sin(_t * 0.6) + 0.35
		if Engine.get_process_frames() % 15 == 0:
			_refresh()                                    # a skin that finished loading takes over

	func _refresh() -> void:
		var key := Cosmetics.model_key(family, id, faction, 2 if family in ["vat", "machinegoon"] else 1)
		var show := key
		if key.begins_with("skins/"):
			if not Cosmetics._ready(key):
				show = Cosmetics.model_key(family, "default", faction, 2 if family in ["vat", "machinegoon"] else 1)
		if show == _key:
			return
		var node := MapBuilder.piece(show)
		if node == null:                                  # a scene freed mid-load (0.20.1): try again next refresh
			return
		_key = show
		for c in _pivot.get_children():
			c.queue_free()
		_pivot.add_child(node)
		var seat := "A"
		if family == "monster":
			MonsterView.dress(node, faction, seat)
		else:
			MapBuilder.apply_owner([node], seat)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
			var par := (mi as Node3D).get_parent()
			while par != node and par is Node3D:
				box = (par as Node3D).transform * box
				par = par.get_parent()
			lo = lo.min(box.position)
			hi = hi.max(box.end)
		if lo.x == INF:
			return
		var c := (lo + hi) / 2.0
		node.position = -Vector3(c.x, lo.y, c.z)
		var r := maxf((hi - lo).length() * 0.5, 0.5)
		var d := r / tan(deg_to_rad(_cam.fov * 0.5)) * 1.1
		var h := (hi.y - lo.y) * 0.5
		_cam.position = Vector3(0, h + d * 0.45, d * 0.9)
		_cam.look_at(Vector3(0, h, 0), Vector3.UP)

