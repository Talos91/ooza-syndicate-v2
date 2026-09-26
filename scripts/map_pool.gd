class_name MapPool
## Every playable map: maps 4.2 (References/Ooze Syndicate maps 4.2, compact maps at the kit's sizes) and the
## Alpha 11 classics (A-, References/Ooze Syndicate maps 4.2 - Alpha 11 classics) and maps 4.3 / 4.4 classic (M-01..M-20 /
## M-21..M-40, References/Ooze Syndicate maps 4.3 classic / 4.4 classic, Mushroom Wars style fields), baked for the game by
## Models/2.0/export_maps_4_2_game.py into maps4/: every map baked into maps4/ except WITHHELD,
## ordered by code prefix (GROUP_ORDER; D = debug maps), each by code; on a phone also without PHONE_UNFIT. The 2.0 roster in maps/ is
## archive: only the rules tests still load it.

const GROUP_ORDER := ["T", "A", "M", "C", "B", "S", "X", "D"]   # A = Alpha 11 classics; M = maps 4.3 / 4.4 classic
                                                              # (Mushroom Wars style); D = debug / test maps
const DIR := "res://maps4"
static var dir := DIR                                   # tests/test_net.gd points it at the legacy roster
# Baked but kept out of the pool (OPEN-QUESTIONS): none on maps 4.1 so far (maps 4.0 withheld B-30 for deck
# clashes and D-08 for 27 pt tap targets; neither is in the 4.1 partial pack).
const WITHHELD: Array[String] = []
# Not on phones (Daniele, Alpha 18: "if some map is not good for mobile still flag them and remove them"):
# maps the phone-fit probe (tests/phone_fit.tscn) finds crowded on a phone; tablets and desktop keep them.
# Maps 4.0 listed its 3v3 / 2v2v2 maps here; the 4.1 partial pack has none, and every 4.1 map passes.
const PHONE_UNFIT: Array[String] = []
static var phone := false                               # set by main at startup: a phone-sized screen


static func all() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		var path: String = dir + "/" + f.trim_suffix(".remap")
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
