class_name Rules
extends RefCounted
## Every tunable number of the prototype in one place.
## Kit sizes match Models/2.0/build_kit_2_0.py. Army numbers are PROVISIONAL placeholders
## (PARAMETERS.md: army scale and vat caps are open questions) - change here only.

# kit geometry (metres)
const R := 6.0                       # platform radius
const PIER := 1.6                    # connector length beyond the rim
const S := 4.0                       # one deck module (short bridge)
const W := 2.8                       # deck width
const SOCKET_Z := 0.06

# movement: travel time counts deck modules only (1 module = 2 s); platforms and piers are
# part of the node, crossed quickly
const MODULE_SECONDS := 2.0
const DECK_SPEED := S / MODULE_SECONDS
const NODE_SPEED_MULT := 6.0         # a node crossing (pier, arc round the structure, door) ~1-1.5 s
const ARC_R := 3.8                   # hordes flow around a node's centre structure at this radius
const DOOR := Vector3(0.0, 0.0, 1.7) # vat door, local to the node (Blender -Y = Godot +Z)
const EXIT_R := 2.2                  # hordes leave from the tank bottoms

# horde rendering
const UNITS_PER_PATCH := 60
const PATCH_SPACING := 1.8
const MAX_PATCHES := 40

# economy - PROVISIONAL (~5x the 12/48/120 placeholder caps)
const CAPS := {1: 60, 2: 240, 3: 600, 4: 1000}
const PROD := {1: 2.0, 2: 4.0, 3: 7.0, 4: 10.0}     # units per second while below cap
const HOME_TIER := 2
const HOME_UNITS := 80
const NEUTRAL_UNITS := {1: 30, 2: 60, 3: 120, 4: 200}
const SEND_FRACTIONS := [0.25, 0.5, 0.75, 1.0]

# frontline combat - PROVISIONAL: each side loses BASE + K * enemy units per second
const FIGHT_RATE_BASE := 12.0
const FIGHT_RATE_K := 0.08
const FRONT_CONTACT := 1.4           # metres between heads that starts a frontline

const SEATS := {
	"A": Color("#2ee6ff"), "B": Color("#7dff5a"), "C": Color("#b48cff"),
	"D": Color("#ff5a5a"), "E": Color("#ffd23f"),
}
const NEUTRAL := Color("#a9b8c8")
# texture hue of each Alpha 11 creature map, and the race accent colour
const FACTIONS := {
	"vex": [0.518, Color("#19e5ff")], "null": [0.894, Color("#ff19ab")],
	"bloom": [0.236, Color("#6fff2a")], "ember": [0.085, Color("#ff3b1f")],
	"solar": [0.12, Color("#ffbe19")],
}


static func span(modules: int) -> float:
	## Centre-to-centre distance of an honest edge of `modules` deck modules.
	return 2.0 * (R + PIER) + modules * S


static func heading(d: Vector3) -> float:
	## Kit rotation.y for a piece whose local +X should point along d (kit authored in Blender).
	return atan2(-d.z, d.x)
