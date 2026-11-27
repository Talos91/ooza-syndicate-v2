class_name Slots3
extends RefCounted
## MODEL SLOTS (Ooze 3.0, plan 3.0-ARCHITECTURE-PLAN 2026-11-27 sec 2.5). ONE place decides which model stands where: every
## node platform and every structure on a node in a match is made here, so the export-r1 art (OOZE3_Platform, OOZE3_VatT1-4,
## GooGatling_T1-3, Laser, Juicer, ...) replaces the grey-box kit pieces without touching sim, map or HUD code.
## - A slot is a small scene in res://slots/ (its root script holds the contract); the ART is its child "Art", today the
##   kit piece MapBuilder.piece loads (light / HD / skins as before), later the new GLB.
## - platform: slots/Platform_slot.tscn (named "Platform_*" so MapBatch batches it as a static kit piece); origin = deck
##   centre, deck top y 0; the art is scaled Rules.R / ART_R["platform"] (7.6 / 6.0 in this build: no pier); set_seat(seat,
##   faction) and the conquest parameter 0..1 drive today's owner rim (the conquest texture swaps the shader next round).
## - structure_<kind>_t<n>.tscn: origin = deck centre; Marker3D ScreenMount over the model (the count screen mounts there,
##   WP4); structures are NOT scaled in this build. Node categories (Daniele 2026-11-27) each have their slots:
##     normal         vat T1-T3, Googatling (kit Machinegoon) T1-T3 - no upgrade to T4
##     special        vat T4 (own category, indestructible; the existing T4 vat look for now)
##     relay          laser, juicer (the forge's new name; kit Forge for now), socket (bare: a sinkhole emptied it)
##     relay_special  launcher (next structure, after 0.30.0; the proto launcher's cannon stands in)
##     legacy         monster hub (old maps only)
## - MapBuilder.put / set_centre_model / build3 route every platform and structure key here (owns()), so effects that
##   drop a ghost of a structure (CombatFx) get the same slot.
## - Hook, pck: slot scenes load by path, so the new art can live in an on-demand pack (as skins do).

const DIR := "res://slots/"
const ART_R := {"platform": 6.0}      # the radius the art was modelled at (7.66 for OOZE3_Platform when it lands)
const PLATFORM_SCENE := "res://slots/Platform_slot.tscn"
const PLATFORM_KEYS := ["Platform_Standard", "Platform_Pillar", "Platform_Rotation"]   # (+ _D18 deep twins)
# slot name -> [kind, tier, category]
const STRUCTURES := {
	"structure_vat_t1": ["vat", 1, "normal"], "structure_vat_t2": ["vat", 2, "normal"], "structure_vat_t3": ["vat", 3, "normal"],
	"structure_vat_t4": ["vat", 4, "special"],
	"structure_gatling_t1": ["gatling", 1, "normal"], "structure_gatling_t2": ["gatling", 2, "normal"],
	"structure_gatling_t3": ["gatling", 3, "normal"],
	"structure_laser_t1": ["laser", 1, "relay"], "structure_juicer_t1": ["juicer", 1, "relay"],
	"structure_socket_t1": ["socket", 1, "relay"],
	"structure_launcher_t1": ["launcher", 1, "relay_special"], "structure_launcher_t2": ["launcher", 2, "relay_special"],
	"structure_launcher_t3": ["launcher", 3, "relay_special"],
	"structure_hub_t1": ["hub", 1, "legacy"],
}

const COUNT_SCREEN_SCENE := "res://slots/count_screen.tscn"   # WP4: the count screen, one per node, on the structure's ScreenMount

static var _scenes := {}
static var _slot_of := {}             # model key -> slot name ("" = not a slot key), cached (called per structure swap)


static func k() -> float:
	## the platform art's scale: Rules.R over the radius it was modelled at
	return Rules.R / float(ART_R["platform"])


static func is_platform(key: String) -> bool:
	return key.trim_suffix("_D18") in PLATFORM_KEYS


static func slot_of(key: String) -> String:
	## The slot a kit / skin model key stands in ("" when the key is not a platform or a structure).
	if _slot_of.has(key):
		return _slot_of[key]
	var s := ""
	var bare := key.get_file()                        # "skins/NULL_Vat_T2" -> "NULL_Vat_T2"
	if is_platform(key):
		s = "platform"
	elif bare.contains("Vat_T") and not bare.contains("MonsterVat"):
		s = "structure_vat_t%d" % clampi(int(bare.substr(bare.find("Vat_T") + 5, 1)), 1, 4)
	elif bare.contains("Machinegoon_T"):
		s = "structure_gatling_t%d" % clampi(int(bare.substr(bare.find("Machinegoon_T") + 13, 1)), 1, 3)
	elif bare.contains("Laser") and not bare.begins_with("Relay_"):
		s = "structure_laser_t1"
	elif bare.contains("Forge") or bare.contains("Juicer"):
		s = "structure_juicer_t1"
	elif bare == "Socket_Attachment":
		s = "structure_socket_t1"
	elif bare.begins_with("Relay_Cannon_v4") or bare == "Relay_Launcher_v3":
		var t := 1
		if bare.contains("_T2"):
			t = 2
		elif bare.contains("_T3"):
			t = 3
		s = "structure_launcher_t%d" % t
	elif bare.begins_with("MonsterVat_"):
		s = "structure_hub_t1"
	_slot_of[key] = s
	return s


static func owns(key: String) -> bool:
	return slot_of(key) != ""


static func scene_path(slot: String) -> String:
	return PLATFORM_SCENE if slot == "platform" else DIR + slot + ".tscn"


static func make(key: String) -> Node3D:
	## The slot node for a model key, its art mounted; the caller places it (MapBuilder.put).
	var slot := slot_of(key)
	var path := scene_path(slot)
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var node: Node3D = (_scenes[path] as PackedScene).instantiate()
	node.call("mount", key)
	return node


static func make_count_screen() -> Node3D:
	## The count screen model (slots/count_screen.tscn; VatCount mounts it on the structure slot's ScreenMount).
	if not _scenes.has(COUNT_SCREEN_SCENE):
		_scenes[COUNT_SCREEN_SCENE] = load(COUNT_SCREEN_SCENE)
	return (_scenes[COUNT_SCREEN_SCENE] as PackedScene).instantiate()


static func screen_mount(slot_node: Node) -> Marker3D:
	## A structure slot's ScreenMount (null for anything else).
	if slot_node == null or not is_instance_valid(slot_node):
		return null
	return slot_node.get_node_or_null("ScreenMount") as Marker3D


static func art(slot_node: Node) -> Node3D:
	## The model inside a slot (the node itself when it is not a slot).
	if slot_node != null and slot_node.has_method("mount"):
		return slot_node.get_node_or_null("Art") as Node3D
	return slot_node as Node3D


static func category(slot_node: Node) -> String:
	return str(slot_node.get("category")) if slot_node != null and slot_node.get("category") != null else ""


static func set_seat(part: Node, seat: String, faction := "") -> void:
	## MapBuilder.apply_owner: a slot platform's owner (rim + conquest); a no-op for anything else.
	if is_instance_valid(part) and part.has_method("set_seat"):
		part.call("set_seat", seat, faction)
