class_name MapPool
## Every playable map: the starter seven first (teaching order), then the rest of the 100-map roster
## by code. Files are split from Docs/.../02 Maps/roster/maps-100.json; the 17 roster maps whose
## modes do not include 1v1 (001-003, 025-030, 036, 037, 062, 092, 094-097) are left out until 2.0
## has team and free-for-all seats.

const STARTER := [
	"res://maps/004-two-piers.json", "res://maps/007-long-span.json",
	"res://maps/008-strait.json", "res://maps/010-first-switch.json",
	"res://maps/011-remote-span.json", "res://maps/061-switchback-foundry.json",
	"res://maps/047-trident-exchange.json",
]


static func all() -> Array:
	var out: Array = STARTER.duplicate()
	var rest: Array = []
	for f in DirAccess.get_files_at("res://maps"):
		var path: String = "res://maps/" + f.trim_suffix(".remap")
		if path.ends_with(".json") and not path in out and not path in rest:
			rest.append(path)
	rest.sort()
	return out + rest
