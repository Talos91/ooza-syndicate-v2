class_name MapPool
## Every playable map: maps 4.0 (References/Ooze Syndicate maps 4.0, landscape phone pack, baked for the
## game by Models/2.0/export_maps_4_0_game.py into maps4/): every map baked into maps4/ except WITHHELD,
## ordered by code prefix (GROUP_ORDER; D = debug maps), each by code; on a phone also without PHONE_UNFIT. The 2.0 roster in maps/ is
## archive: only the rules tests still load it.

const GROUP_ORDER := ["T", "C", "B", "S", "X", "D"]    # D = debug / test maps (the pack's debug/ folder)
const DIR := "res://maps4"
# Baked but kept out of the pool (OPEN-QUESTIONS, maps 4.0): B-30 Sable Halo keeps 24 deck clashes at every
# scale the planner tried (1.4-3.0 m per unit); D-08 Ring Bench (41 nodes) is not phone-fit - its smallest
# node tap target stays at 27 pt even from 74 degrees (phone-fit probe; the rest reach 33 pt). Both go back
# to the pack for a fix.
const WITHHELD := ["B-30", "D-08"]
# Not on phones (Daniele, Alpha 18: "if some map is not good for mobile still flag them and remove them"):
# the 3v3 / 2v2v2 maps - 31 nodes on a round board that uses a third of a phone's width; the pack itself
# says "tablet recommended". They pass the probe (taps 34-36 pt, nothing overflows) but up to five badges
# touch a neighbour's platform. Tablets and desktop keep them.
const PHONE_UNFIT := ["B-27", "B-28", "B-29", "C-27", "C-28", "C-29", "C-30", "S-27", "S-28", "S-29", "S-30", "D-09"]
static var phone := false                               # set by main at startup: a phone-sized screen


static func all() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		var path: String = DIR + "/" + f.trim_suffix(".remap")
		var code := path.get_file().substr(0, 4)
		if path.ends_with(".json") and not path in out and not code in WITHHELD and not (phone and code in PHONE_UNFIT):
			out.append(path)
	out.sort_custom(func(a, b):
		var ga := GROUP_ORDER.find(a.get_file().substr(0, 1))
		var gb := GROUP_ORDER.find(b.get_file().substr(0, 1))
		return ga < gb if ga != gb else a < b)
	return out


static func phone_screen(mobile: bool) -> bool:
	## A phone rather than a tablet: the phone profile on a screen whose short side is under 600 CSS px
	## (web); a desktop run with --mobile counts as a phone.
	if not mobile:
		return false
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var side = JavaScriptBridge.eval("Math.min(screen.width, screen.height)", true)
		if side != null:
			return float(side) < 600.0
	return true


static func thumb(code: String) -> String:
	return "res://assets/maps4/thumbs/%s.png" % code
