extends RefCounted
## LAB BUILD test cards (05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md, "Test cards"): the one table the LAB screen
## (lab_menu.gd) lists. A card = one question for Daniele's phone, one map, one vs-AI 1v1 match.
## Fields: id (short, shown in the overlay and on the LAB screen), title, question, map (4-character map code, MapPool.LAB),
## mode ("1v1"), ai (Rules.AI_LEVELS key), faction / rival (seat A / seat B), lab_opts (overrides merged into Rules.lab_opts
## for the match, reset when the LAB screen opens again), live (false = greyed, not tappable), coming (the build it lands in),
## choices (lab4 jobs 2 + 5: a card with choices opens a CHOICE SHEET on tap - one row of chips per choice, PLAY starts the match;
## each choice = {key (a Rules.lab_opts key), label, values, names}; values[0] is the default and today's behaviour; the pick is
## merged over lab_opts and shown on the card, in the overlay's folded line and in its rule line).

# lab4 job 2 (Daniele: "slow trops movement to 0.90 maybe we need a test with different unit traverse speed")
const SPEED := {"key": "unit_speed", "label": "UNIT SPEED", "values": [1.0, 0.9, 0.8], "names": ["x1.0", "x0.9", "x0.8"]}
# lab4 job 5 (Daniele: "not powerful enough and its range is too little ... shouldn t be a 1 to 1 bu lower ratio"). 6 m = the
# platform radius = gat_own_platform's reach (today's lab card); 10 m = MACHINEGOON_RANGE (the real game).
const GAT_RANGE := {"key": "gat_range", "label": "RANGE", "values": [6.0, 8.0, 10.0], "names": ["6 m", "8 m", "10 m"]}
const GAT_POWER := {"key": "gat_power", "label": "POWER", "values": [1.0, 1.5, 2.0], "names": ["x1", "x1.5", "x2"]}
const GAT_AMMO := {"key": "gat_ammo", "label": "AMMO", "values": [1.0, 0.5, 0.0], "names": ["1 PER KILL", "1 PER 2", "FREE"]}

const CARDS: Array[Dictionary] = [
	{"id": "read-9", "title": "READING 9", "question": "Does the board read on your phone?", "map": "L09P", "mode": "1v1",
			"ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {}, "live": true},
	{"id": "read-11", "title": "READING 11", "question": "Does the board read on your phone?", "map": "L11P", "mode": "1v1",
			"ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {}, "live": true},
	{"id": "read-13", "title": "READING 13", "question": "Does the board read on your phone?", "map": "L13P", "mode": "1v1",
			"ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {}, "live": true},
	{"id": "clus-9", "title": "CLUSTERS 9", "question": "Where does the board stop reading well, with clusters?", "map": "L09C",
			"mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {"joints": true}, "live": true},
	{"id": "clus-11", "title": "CLUSTERS 11", "question": "Where does the board stop reading well, with clusters?", "map": "L11C",
			"mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {"joints": true}, "live": true},
	{"id": "clus-13", "title": "CLUSTERS 13", "question": "Where does the board stop reading well, with clusters?", "map": "L13C",
			"mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {"joints": true}, "live": true},
	{"id": "count", "title": "COUNT SIZE", "question": "Vat-screen count at x1.0 / x1.15 / x1.3: which size reads?",
			"map": "", "mode": "1v1", "ai": "Standard", "lab_opts": {}, "live": false, "coming": "lab3"},
	{"id": "hop", "title": "CLUSTER HOP", "question": "Is the hop from vat to vat enough warning? Try each unit speed.", "map": "L09C",
			"mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {"joints": true}, "live": true,
			"choices": [SPEED]},
	{"id": "relay-kill", "title": "RELAY KILL", "question": "Does killing a column on the bridge feel like a big deal?",
			"map": "L09R", "mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null",
			"lab_opts": {"relay_set": true, "gat_own_platform": true}, "live": true},
	{"id": "gat", "title": "GOOGATLING ON A CLUSTER", "question": "Pick range, power and ammo: which makes it worth building?",
			"map": "L09C", "mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null",
			"lab_opts": {"joints": true, "gat_own_platform": true, "gat_start": true}, "live": true,
			"choices": [GAT_RANGE, GAT_POWER, GAT_AMMO]},
	{"id": "quota", "title": "QUOTA BY TIER", "question": "1 point per tier, relays do not launch: does the score read and matter?",
			"map": "L11P", "mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null",
			"lab_opts": {"quota_tier": true, "gat_own_platform": true, "relay_set": true}, "live": true},
]


static func find(id: String) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return {}


static func map_path(code: String) -> String:
	## The baked map file for a 4-character code ("" when none is baked).
	for p in MapPool.all():
		if p.get_file().substr(0, 4) == code:
			return p
	return ""
