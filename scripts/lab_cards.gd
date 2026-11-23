extends RefCounted
## LAB BUILD test cards (05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md, "Test cards"): the one table the LAB screen
## (lab_menu.gd) lists. A card = one question for Daniele's phone, one map, one vs-AI 1v1 match.
## Fields: id (short, shown in the overlay and on the LAB screen), title, question, map (4-character map code, MapPool.LAB),
## mode ("1v1"), ai (Rules.AI_LEVELS key), faction / rival (seat A / seat B), lab_opts (overrides merged into Rules.lab_opts
## for the match, reset when the LAB screen opens again), live (false = greyed, not tappable), coming (the build it lands in).

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
	{"id": "hop", "title": "CLUSTER HOP", "question": "Is the hop from vat to vat enough warning?", "map": "L09C",
			"mode": "1v1", "ai": "Standard", "faction": "vex", "rival": "null", "lab_opts": {"joints": true}, "live": true},
	{"id": "relay-kill", "title": "RELAY KILL", "question": "On a long deck: does it feel like a big deal?",
			"map": "", "mode": "1v1", "ai": "Standard", "lab_opts": {}, "live": false, "coming": "lab3"},
	{"id": "gat", "title": "GOOGATLING", "question": "On a cluster node, own platform only: useful without spawn kill?",
			"map": "", "mode": "1v1", "ai": "Standard", "lab_opts": {}, "live": false, "coming": "lab3"},
	{"id": "quota", "title": "QUOTA BY TIER", "question": "1 point per tier, relays do not launch: does the score read and matter?",
			"map": "", "mode": "1v1", "ai": "Standard", "lab_opts": {}, "live": false, "coming": "lab3"},
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
