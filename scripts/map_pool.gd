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

const GROUP_ORDER := ["G", "T", "R", "N", "E", "A", "M", "C", "B", "S", "X", "P", "D", "H"]   # G = the forward pool (0.24.5, POOL G); R = round R proto maps; E = experimental E-01..E-10; P = Relays 3.0 prototype test maps (never pooled); A = Alpha 11 classics; M = maps 4.3 / 4.4 classic + 4.6 relay;
                                                              # MAPS 5.0: N = the map builder's new maps (References/Ooze Syndicate maps 5.0)
                                                              # (Mushroom Wars style); D = debug / test maps
const DIR := "res://maps4"
static var dir := DIR                                   # tests/test_net.gd points it at the legacy roster
# Baked but kept out of the pool (OPEN-QUESTIONS): none on maps 4.1 so far (maps 4.0 withheld B-30 for deck
# clashes and D-08 for 27 pt tap targets; neither is in the 4.1 partial pack).
const WITHHELD: Array[String] = []
# Baked and pooled, but not offered in these modes (mode_offered; a map left with no offered mode leaves battlefield()).
# SEAT BIAS (balance study 2026-10-27, Expert AI vs Expert AI, every faction pair from both seats): seat A wins 92 % on
# N-24 K-Crossing and 78 % on N-04 Console - map geometry, not factions. Out of 1v1 (their only mode) until 🗺️ moves
# the spawns (Daniele 2026-10-27: "withhold N-24 / N-04 from 1v1 until the map builder fixes their seats").
# Daniele 2026-11-01, Desk vls-fair: the Very Last Stand tie-break (Sim._islands) fixed the seat bias, N-24 / N-04 are back in 1v1.
const WITHHELD_MODES := {}
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
# POOL G (Daniele 2026-11-15, map-pool-g: "the 14 pass and the 5 close fail remain (give them a new letter these identify the ones we
# move forward with) the one that fail remove them from the next staging build but keep them around as we ll rework them"): the pool is
# the G maps only. 2026-11-10 it was N / P / R / E (+ MULTI_KEEP); those maps are now G (re-coded) or REWORK (below).
const POOL_GROUPS: Array[String] = ["G"]


static func battlefield() -> Array:
	## all() minus TUTORIAL_ONLY, limited to POOL_GROUPS: what the player actually gets offered (02 BATTLEFIELD,
	## REMATCH ON A RANDOM MAP) and what test_map_pool / test_ai_curve run their coverage over.
	## 0.23.0: the new maps (POOL_GROUPS) are the pool for every mode they offer; a mode NO pooled map offers yet (the N maps are
	## 1v1 / 2v2 only - FFA 3/4/5, 3v3, 2v2v2) keeps the older maps that offer it, so no mode disappears (conservative reading of
	## Daniele's "replace current pool with the new ones"; OPEN-QUESTIONS). Cached: the map files don't change at run time.
	if not _battlefield_cache.is_empty():
		return _battlefield_cache
	var offered := all().filter(func(p): return not p.get_file().substr(0, 4) in TUTORIAL_ONLY and not archived(p) and not rework(p))
	if Rules.demo:                                    # DEMO BUILD: R-01 STRAIT only
		_battlefield_cache = offered.filter(func(p): return p.get_file().substr(0, 4) in DEMO)
		return _battlefield_cache
	if Rules.proto_debug:
		_battlefield_cache = offered.filter(func(p): return p.get_file().substr(0, 4) in PROTO)
		return _battlefield_cache
	if POOL_GROUPS.is_empty():
		_battlefield_cache = offered
		return offered
	offered = offered.filter(func(p): return not _offered_modes(p).is_empty())   # WITHHELD_MODES took every mode it seats
	var pooled := offered.filter(func(p): return p.get_file().substr(0, 1) in POOL_GROUPS or p.get_file().substr(0, 4) in MULTI_KEEP)
	var modes := {}
	for p in pooled:
		for m in _offered_modes(p):
			modes[m] = true
	_pooled_modes = modes
	var fill := offered.filter(func(p):
		if p.get_file().substr(0, 1) in POOL_GROUPS or p.get_file().substr(0, 4) in MULTI_KEEP:
			return false
		for m in _offered_modes(p):
			if not modes.has(m):
				return true
		return false)
	_battlefield_cache = pooled + fill
	return _battlefield_cache


# MAP KEEP LIST (Daniele 2026-11-10): the old maps he keeps playable. Every other old map is ARCHIVED = withheld from play (never in
# battlefield() / mode_offered), its file stays baked in maps4/ and in all() - nothing is deleted; campaign placeholders and the
# tutorial still load theirs by path. Per-map suites (test_maps4, test_map_pool, phone_fit) check TEST_SCOPE = PROTO + KEEP_OLD.
const KEEP_OLD: Array[String] = []   # 2026-11-15 (POOL G): every kept old map is now a G map or on REWORK
# MULTI-PLAYER KEEP (Daniele 2026-11-10: "M15 N-05 and N-06 for now keep these has 2v2 and FFA but they all need major rework to be at the level of what we have now"):
# playable for the modes they seat (M-15 2v2 + FFA4, N-06 2v2; N-05 seats 1v1 only, already in KEEP_OLD). REWORK NEEDED: not a baseline of quality.
const MULTI_KEEP: Array[String] = []   # 2026-11-15 (POOL G): N-05 is G-19; M-15 / N-06 are on REWORK
const ARCHIVED: Array[String] = [
	"A-01", "A-02", "A-03", "A-04", "B-01", "B-02", "B-03", "B-04", "B-05", "C-01", "C-02", "C-03", "C-04",
	"C-05", "M-01", "M-02", "M-03", "M-04", "M-05", "M-06", "M-07", "M-08", "M-09", "M-10", "M-11", "M-12",
	"M-13", "M-14", "M-16", "M-17", "M-18", "M-19", "M-20", "M-21", "M-22", "M-23", "M-24", "M-25",
	"M-26", "M-27", "M-28", "M-29", "M-30", "M-31", "M-32", "M-33", "M-34", "M-35", "M-36", "M-37", "M-38",
	"M-39", "M-40", "M-51", "M-52", "M-53", "M-54", "M-55", "M-56", "M-57", "M-58", "M-59", "M-60", "N-01",
	"N-04", "N-07", "N-08", "N-09", "N-10", "N-11", "N-12", "N-13", "N-14", "N-15", "N-18", "N-19",
	"N-21", "N-23", "N-24", "N-25", "N-26", "N-27", "N-28", "N-29", "N-30", "R-03", "R-04", "S-01", "S-02",
	"S-03", "S-04", "S-05"
]   # A, B, C, M, S packs + N maps not on the keep list + R-03 (merged into R-01) / R-04 (removed); regenerate = baked A/B/C/M/S/N/R codes minus KEEP_OLD minus PROTO


static func test_scope() -> Array[String]:
	## The maps the per-map suites verify (test_maps4, test_map_pool, phone_fit): the G pool (Daniele 2026-11-15; before: PROTO + KEEP_OLD).
	## REWORK maps are not checked and their failures are no blockers (TEST RULE 2026-11-06).
	var out: Array[String] = []
	out.append_array(PROTO)
	return out


# REWORK (Daniele 2026-11-15): the 18 maps that failed the >= 60 pt start-view limit at decks 2 / 4 / 6 m (References/Map size 2026-11/
# SHRINK-36.md). Out of battlefield(), out of every pool and every mode, NOT archived: their files stay baked in maps4/ (2 / 4 / 6 m)
# and in all(), to be reworked (fewer platforms / rows) and then re-coded into G.
const REWORK: Array[String] = ["R-01", "R-05", "R-09", "R-11", "R-13", "R-15", "R-16", "P-02", "P-04", "E-03", "E-05", "E-09", "N-06", "N-16", "N-17", "N-20", "N-22", "M-15"]


static func rework(code_or_path: String) -> bool:
	return code_or_path.get_file().substr(0, 4) in REWORK


# OLD -> NEW CODES (POOL G, 2026-11-15): G-01..G-19 in the SHRINK-36 table order; names and file slugs kept; each map json says `was`.
const RECODED := {"R-02": "G-01", "R-06": "G-02", "R-10": "G-03", "R-12": "G-04", "R-14": "G-05", "R-17": "G-06", "P-01": "G-07", "P-03": "G-08", "P-05": "G-09", "E-01": "G-10", "E-02": "G-11", "E-04": "G-12", "E-06": "G-13", "E-07": "G-14", "E-08": "G-15", "E-10": "G-16", "N-02": "G-17", "N-03": "G-18", "N-05": "G-19"}


static func archived(code_or_path: String) -> bool:
	return code_or_path.get_file().substr(0, 4) in ARCHIVED


# PROTO PICKER (Daniele 2026-11-03: "in the proto build the map picker must list ONLY the prototype maps"): a proto build
# (Rules.proto_debug) offers just these - the Relays 3.0 test maps - and no older map fills a mode they lack (they are 1v1 only,
# so the picker shows only the 1v1 chip). The release line never reaches this: its VERSION has no "-proto".
const PROTO: Array[String] = ["G-01", "G-02", "G-03", "G-04", "G-05", "G-06", "G-07", "G-08", "G-09", "G-10", "G-11", "G-12", "G-13", "G-14", "G-15", "G-16", "G-17", "G-18", "G-19"]   # POOL G (2026-11-15): the G maps (was the round R + P maps; the kept ones are G now, the rest REWORK)
# THEMES (2026-11-13): map code -> LookTheme id (corporate_campus / golden_hour / quota_parade / wellness_retreat). Empty = the LAB
# on every map until Daniele assigns the round-32 settings; dev --theme=<id> forces one for shots.
const THEMES := {}
const DEMO: Array[String] = ["G-01", "G-02", "G-03", "G-04", "G-05", "G-06", "G-07", "G-08", "G-09", "G-10", "G-11", "G-12", "G-13", "G-14", "G-15", "G-16", "G-17", "G-18", "G-19",
		"HX-1", "HX-2", "HX-3", "HX-4", "HX-5", "HX-6", "HX-7", "HX-8"]   # DEMO BUILD (Rules.demo): the G pool (2026-11-15; the REWORK maps left it) + the HX size ladder
# HX SIZE LADDER (map-size study 2026-11-15; Daniele: "lets do it in the demo staging, simply make lets say 4/8 maps with just a
# honeycomb of nodes so we get the general idea of max limits"): HX-1..HX-8, generator References/Ooze Syndicate maps - size ladder
# HX 2026-11/generator/honeycomb.py. DEMO ONLY: group "H" is not in POOL_GROUPS and the codes are not in PROTO.
static var _battlefield_cache: Array = []
static var _pooled_modes: Dictionary = {}              # the modes the new pool (POOL_GROUPS) offers


static func _offered_modes(path: String) -> Array:
	## The modes this map seats, minus its WITHHELD_MODES.
	var out: Array = (MapBuilder.load_map(path)["seats"] as Dictionary).keys()
	return out.filter(func(m): return not m in WITHHELD_MODES.get(path.get_file().substr(0, 4), []))


static func mode_offered(code_or_path: String, mode: String) -> bool:
	## 0.23.0: may this map be played in `mode`? A pooled (new) map: every mode it seats. A kept older map: only the modes the
	## new pool doesn't offer (it fills a gap, it doesn't compete with the new maps). Never a WITHHELD_MODES mode.
	if mode in WITHHELD_MODES.get(code_or_path.get_file().substr(0, 4), []) or archived(code_or_path) or rework(code_or_path):
		return false
	if POOL_GROUPS.is_empty():
		return true
	var c := code_or_path.get_file().substr(0, 1)
	if c in POOL_GROUPS or code_or_path.get_file().substr(0, 4) in MULTI_KEEP:
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
