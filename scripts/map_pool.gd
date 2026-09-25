class_name MapPool
## Every playable map: maps 3.0 (References/Ooze Syndicate maps 3.0, baked for the game by
## Models/2.0/export_maps_3_0_game.py into maps3/), 100 maps - tutorials first, then core (both
## modes), brawl, siege and the crazy ones, each by code. The 2.0 roster in maps/ is archive: only the
## rules tests still load it.

const GROUP_ORDER := ["T", "C", "B", "S", "X", "D"]    # D = debug / test maps (References/Ooze Syndicate debug maps)
const DIR := "res://maps3"


static func all() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		var path: String = DIR + "/" + f.trim_suffix(".remap")
		if path.ends_with(".json") and not path in out:
			out.append(path)
	out.sort_custom(func(a, b):
		var ga := GROUP_ORDER.find(a.get_file().substr(0, 1))
		var gb := GROUP_ORDER.find(b.get_file().substr(0, 1))
		return ga < gb if ga != gb else a < b)
	return out


static func thumb(code: String) -> String:
	return "res://assets/maps3/thumbs/%s.png" % code
