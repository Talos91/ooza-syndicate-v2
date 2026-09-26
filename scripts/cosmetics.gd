class_name Cosmetics
extends RefCounted
## Cosmetic looks per player (0.19.0 "Alpha 19"; Lane fight fun batch 2, Daniele 2026-09-27). One generic
## system: each seat picks one look per structure family (its loadout); a node shows the look its OWNER
## picked, looked up when it is built or captured (MapBuilder.model_for asks key_for every frame, so a
## capture swaps the model like a tier change does). Pure view: the rules never read it.
##
## CONTRACT (the HUD agent's ARMIES > COSMETICS page, main's per-seat apply and the room's player info):
##   OPTIONS[family] -> Array of ids; families "vat", "machingoon", "laser", "forge", "monster_hub", "monster"
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

const FAMILIES := ["vat", "machingoon", "laser", "forge", "monster_hub", "monster"]
const OPTIONS := {
	"vat": ["default", "faction", "graduate", "biopod", "crystal", "distillery", "hive", "reactor"],
	"machingoon": ["default", "spitter", "pepperbox"],
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
		"machingoon":
			t = clampi(t, 1, 3)
			key = {"spitter": "skins/GooGun_T%d_Spitter" % t, "pepperbox": "skins/GooGun_T%d_Pepperbox" % t}.get(id, "Machingoon_T%d" % t)
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
const _MG := ["Machingoon_T1", "Machingoon_T1", "Machingoon_T2", "Machingoon_T3", "Machingoon_T3"]
const _HUB := {"vex": "MonsterVat_VEX", "null": "MonsterVat_NULL", "bloom": "MonsterVat_BLOOM", "ember": "MonsterVat_EMBER", "solar": "MonsterVat_SOLAR"}
const _MONSTER := {"vex": "Monster_VEX", "null": "Monster_NULL", "bloom": "Monster_BLOOM", "ember": "Monster_EMBER", "solar": "Monster_SOLAR"}


static func default_key(family: String, faction: String, tier: int) -> String:
	match family:
		"vat":
			return _VAT[clampi(tier, 0, 4)]
		"machingoon":
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
	"Machingoon_T1": {"muzzles": [Vector3(0, 2.72, 3.69)]},
	"Machingoon_T2": {"muzzles": [Vector3(-0.39, 2.81, 4.42), Vector3(0.39, 2.81, 4.42)]},
	"Machingoon_T3": {"muzzles": [Vector3(0, 2.92, 5.31)], "spin": {"axis": Vector2(0, 2.92), "r": 0.7, "z0": 1.3}},
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
	## Attach points of a model by name, with or without the "skins/" prefix ({} for a plain model).
	var name := model_name.trim_prefix("skins/")
	return POINTS.get(name, {})
