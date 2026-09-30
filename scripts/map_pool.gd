class_name MapPool
## Every playable map: maps 4.2 (References/Ooze Syndicate maps 4.2, compact maps at the kit's sizes) and the
## Alpha 11 classics (A-, References/Ooze Syndicate maps 4.2 - Alpha 11 classics) and maps 4.3 / 4.4 classic and 4.6 relay (M-01..M-20 /
## M-21..M-40 / M-51..M-60, References/Ooze Syndicate maps 4.3 classic / 4.4 classic / 4.6 relay, Mushroom Wars style fields), baked for the game by
## Models/2.0/export_maps_4_2_game.py into maps4/: every map baked into maps4/ except WITHHELD,
## ordered by code prefix (GROUP_ORDER; D = debug maps), each by code; on a phone also without PHONE_UNFIT. The 2.0 roster in maps/ is
## archive: only the rules tests still load it. `battlefield()` is `all()` minus TUTORIAL_ONLY: the list
## the player actually picks from (02 BATTLEFIELD, REMATCH ON A RANDOM MAP) and test_map_pool /
## test_ai_curve run over. `all()` itself still carries the tutorial-only maps - test_maps4 (every baked
## map) and the rules tests that walk MapPool.all() for coverage still need to see them.

const GROUP_ORDER := ["T", "N", "A", "M", "C", "B", "S", "X", "D"]   # A = Alpha 11 classics; M = maps 4.3 / 4.4 classic + 4.6 relay;
                                                              # MAPS 5.0: N = the map builder's new maps (References/Ooze Syndicate maps 5.0)
                                                              # (Mushroom Wars style); D = debug / test maps
const DIR := "res://maps4"
static var dir := DIR                                   # tests/test_net.gd points it at the legacy roster
# Baked but kept out of the pool (OPEN-QUESTIONS): none on maps 4.1 so far (maps 4.0 withheld B-30 for deck
# clashes and D-08 for 27 pt tap targets; neither is in the 4.1 partial pack).
const WITHHELD: Array[String] = []
# Not on phones (Daniele, Alpha 18: "if some map is not good for mobile still flag them and remove them"):
# maps the phone-fit probe (tests/phone_fit.tscn) finds crowded on a phone; tablets and desktop keep them.
# Maps 4.0 listed its 3v3 / 2v2v2 maps here; the 4.1 partial pack has none, and every 4.1 map passes.
# 34 deg camera (Daniele 2026-09-29, "34 everywhere for now, I wanna test, as we're making new maps so it might not matter"):
# the phone-fit probe at pitch 34 puts 64 of 88 pooled maps under the 33 pt tap minimum (table: 05 Handoff/handoffs/
# architect-specs/cam-34-report.md) - kept IN the pool on his call; re-judge with the Alpha 23 maps.
const PHONE_UNFIT: Array[String] = []
# Teaching boards, not fair matches (the interactive tutorial, References/Ooze Syndicate maps 4.2 -
# tutorial): never on 02 BATTLEFIELD, never a REMATCH ON A RANDOM MAP pick, never in test_map_pool /
# test_ai_curve's pools. T-01 / T-02 (the older tutorial pair in the main maps 4.2 pack) joined them in 0.20.4
# (Daniele: "Hide T-01 / T-02 too" - a server room had defaulted to T-01); the tutorial's first match still
# loads T-02 by path. T-11 (quick start) / T-12 (team play 2v2) are the rewritten tutorial's maps (2026-09-30); the prefix
# match below is the first four characters of the file name, so two-digit codes work the same.
const TUTORIAL_ONLY: Array[String] = ["T-01", "T-02", "T-03", "T-04", "T-05", "T-06", "T-07", "T-08", "T-09", "T-10", "T-11", "T-12"]
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


# MAPS 5.0 (Daniele 2026-09-29: "replace current pool with the new ones"): the player's pool is the map builder's
# N- maps only. Every older map stays baked in maps4/ - the campaign's placeholder missions and the tutorial load
# theirs by path, and test_maps4 still checks them all - but none is offered on 02 BATTLEFIELD or as a random rematch.
const POOL_GROUPS: Array[String] = ["N"]


static func battlefield() -> Array:
	## all() minus TUTORIAL_ONLY, limited to POOL_GROUPS: what the player actually gets offered (02 BATTLEFIELD,
	## REMATCH ON A RANDOM MAP) and what test_map_pool / test_ai_curve run their coverage over.
	## 0.23.0: the new maps (POOL_GROUPS) are the pool for every mode they offer; a mode NO pooled map offers yet (the N maps are
	## 1v1 / 2v2 only - FFA 3/4/5, 3v3, 2v2v2) keeps the older maps that offer it, so no mode disappears (conservative reading of
	## Daniele's "replace current pool with the new ones"; OPEN-QUESTIONS). Cached: the map files don't change at run time.
	if not _battlefield_cache.is_empty():
		return _battlefield_cache
	var offered := all().filter(func(p): return not p.get_file().substr(0, 4) in TUTORIAL_ONLY)
	if POOL_GROUPS.is_empty():
		_battlefield_cache = offered
		return offered
	var pooled := offered.filter(func(p): return p.get_file().substr(0, 1) in POOL_GROUPS)
	var modes := {}
	for p in pooled:
		for m in (MapBuilder.load_map(p)["seats"] as Dictionary).keys():
			modes[m] = true
	_pooled_modes = modes
	var fill := offered.filter(func(p):
		if p.get_file().substr(0, 1) in POOL_GROUPS:
			return false
		for m in (MapBuilder.load_map(p)["seats"] as Dictionary).keys():
			if not modes.has(m):
				return true
		return false)
	_battlefield_cache = pooled + fill
	return _battlefield_cache


static var _battlefield_cache: Array = []
static var _pooled_modes: Dictionary = {}              # the modes the new pool (POOL_GROUPS) offers


static func mode_offered(code_or_path: String, mode: String) -> bool:
	## 0.23.0: may this map be played in `mode`? A pooled (new) map: every mode it seats. A kept older map: only the modes the
	## new pool doesn't offer (it fills a gap, it doesn't compete with the new maps).
	if POOL_GROUPS.is_empty():
		return true
	var c := code_or_path.get_file().substr(0, 1)
	if c in POOL_GROUPS:
		return true
	if _pooled_modes.is_empty():
		battlefield()
	return not _pooled_modes.has(mode)

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
