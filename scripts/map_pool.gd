class_name MapPool
## Every playable map: the starter seven first (teaching order), then the rest of the 100-map roster
## by code. Files are split from Docs/.../02 Maps/roster/maps-100.json - all 100 since Alpha 14
## (team and FFA seats exist now; a map without 1v1 seats opens in its first mode).

const STARTER := [
	"res://maps/004-two-piers.json", "res://maps/007-long-span.json",
	"res://maps/008-strait.json", "res://maps/010-first-switch.json",
	"res://maps/011-remote-span.json", "res://maps/061-switchback-foundry.json",
	"res://maps/047-trident-exchange.json",
]


# Roster data errors, left out until the roster generator fixes them (never hand-edit roster geometry -
# AGENT-BRIEF): 030 Aurelia Siding's centre node 4 has no decks at all, so nothing can reach it.
const BROKEN := ["res://maps/030-aurelia-siding.json"]


static func all() -> Array:
	var out: Array = STARTER.duplicate()
	var rest: Array = []
	for f in DirAccess.get_files_at("res://maps"):
		var path: String = "res://maps/" + f.trim_suffix(".remap")
		if path.ends_with(".json") and not path in out and not path in rest and not path in BROKEN:
			rest.append(path)
	rest.sort()
	return out + rest
