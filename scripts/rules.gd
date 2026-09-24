class_name Rules
extends RefCounted
## Every tunable number of the prototype in one place.
## Kit sizes match Models/2.0/build_kit_2_0.py. Army numbers are PROVISIONAL placeholders
## (PARAMETERS.md: army scale and vat caps are open questions) - change here only.

# Bump this with every published playtest build (Daniele, 2026-09-25: "start versioning and have
# it in the interface and a changelog") - shown in the HUD; see CHANGELOG.md for what changed.
const VERSION := "0.7.0"

# kit geometry (metres)
const R := 6.0                       # platform radius
const PIER := 1.6                    # connector length beyond the rim
const S := 4.0                       # one deck module (short bridge)
const W := 2.8                       # deck width
const SOCKET_Z := 0.06

# movement: travel time counts deck modules only (1 module = 2 s); platforms and piers are
# part of the node, crossed quickly
const MODULE_SECONDS := 2.0
const DECK_SPEED_DEFAULT := S / MODULE_SECONDS
const NODE_SPEED_MULT_DEFAULT := 6.0 # a node crossing (pier, arc round the structure, door) ~1-1.5 s
# live-tunable from the in-game Debug panel (PLAYTEST-NOTES 5: platform speed vs bridge speed)
static var deck_speed: float = DECK_SPEED_DEFAULT          # m/s along a deck
static var node_speed_mult: float = NODE_SPEED_MULT_DEFAULT # x deck speed on platforms, piers, doors
const ARC_R := 3.8                   # hordes flow around a node's centre structure at this radius
const EXIT_R := 2.2                  # hordes leave from the tank bottoms (sends start at the tower)
# THE WHOLE PLATFORM IS THE NODE (Daniele, 2026-09-25): entrances on every side - an arriving horde
# lands on the platform from whichever pier it came by and pours onto it up to the tower's footprint
# (ARC_R). Its units then sit on the platform ("siege") and fight the garrison there.
const RIVER_R := 4.4                 # the goo river around the tower sits at this radius
const RIVER_SLOTS := 14              # patches in the river ring

# hordes are LONG: a send streams out of the vat as one line whose length reads as its size at a
# glance (Mushroom Wars' horde feeling without its endgame chaos). PROVISIONAL density.
const METRES_PER_UNIT := 0.25        # 100 units = a 25 m line
const MAX_CHAIN := 40.0              # beyond this a horde gets thicker, not longer
const MAX_THICKEN := 0.35
const PATCH_SPACING := 1.8
const MAX_PATCHES := 24              # 40 m / 1.8 m + head
const UNITS_PER_PATCH := 60          # legacy: only the capture drain estimate below uses it

# UNITS LEAVE THE VAT ONLY AS THEY BECOME BLOB (Daniele, 2026-09-25): a send is an order; the door
# emits units into the line at DOOR_RATE. Units still inside stay in the vat's count and can be
# re-ordered - a new send takes over the previous order's not-yet-emitted part.
const DOOR_RATE_DEFAULT := DECK_SPEED_DEFAULT * NODE_SPEED_MULT_DEFAULT / METRES_PER_UNIT   # 48 units/s: the tail stays at the door
static var door_rate: float = DOOR_RATE_DEFAULT        # live-tunable (Debug panel)
static var node_fight_mult: float = 1.0                # live-tunable: x combat rates on a platform

# RUDIMENTARY relay cycling and Last Stand (Daniele, 2026-09-25: "without the rotating platforms
# and Last Stand the game is eternal - test with the real maps even if rudimental"). Real per-map
# authoring (fixed state order, warnings, ride/fall/carry consequences, hidden Last Stand method,
# waves per map) is a separate later pass; this is the minimum that makes every starter map END.
const RELAY_PERIOD := 18.0           # GAME-RULES sec8: 3 s warning + 15 s cooldown, no warning phase here
const LAST_STAND_TIME := 120.0       # Daniele, 2026-09-25: moved earlier than GAME-RULES sec10's
                                      # 3:00 for this rudimentary pass, to keep matches shorter
const LAST_STAND_WAVE := 14.0        # seconds between collapse waves; always "inward" (rim first) here
const MATCH_HARD_END := 420.0        # 7:00 safety net: still undecided -> stronger seat wins outright

# economy - PROVISIONAL (~5x the 12/48/120 placeholder caps)
const CAPS := {1: 60, 2: 240, 3: 600, 4: 1000}
const PROD := {1: 2.0, 2: 4.0, 3: 7.0, 4: 10.0}     # units per second while below cap
const HOME_TIER := 2

# RUDIMENTARY structures (Daniele, 2026-09-25: "implement all we have already model wise... all
# structures and their functions"). Real costs, tiers and swap rules (GAME-RULES sec6) wait on the
# army-scale/vat-cap decision (BUILD-LOG open questions); this is enough to make every modelled
# piece (Vat_T1-4, Cannon_T1-3, Forge) functional, not just decorative, on any starter map.
const BUILD_SECONDS := 10.0          # vat upgrade or attachment build/upgrade time (GAME-RULES sec6)
const CANNON_RANGE := 10.0           # metres from the node's centre a burst reaches
# T1->T2->T3, double-tap to upgrade (Alpha 11 convention) - rudimentary rate/kill scaling
const CANNON_STATS := {1: {"period": 4.0, "kill": 10.0}, 2: {"period": 3.0, "kill": 16.0},
		3: {"period": 2.0, "kill": 25.0}}
static var forge_bonus: float = 0.15 # live-tunable: a forge's attack/defence bonus for its owner

# SHIELD (Daniele, 2026-09-25): passing through an enemy node is now allowed - the goo RING around
# the tower (not the tower/garrison itself) is a shield worth SHIELD_FRACTION of the current
# garrison, regenerating from "excess minions" while below that cap. A transiting force fights the
# shield, not the real garrison (only an actual arrival ever touches that); the garrison still
# fires back at the transiting force as before. If the shield breaks, the specific deck the
# attacker is using to approach is destroyed outright ("the bond with the other node disappears") -
# rudimentary reading: the ONE edge on the attacker's route immediately before this node, not every
# edge the node has. Neutral nodes have no shield (already a free glide - see _register_transit).
const SHIELD_FRACTION := 0.2
const SHIELD_REGEN := 3.0            # units/s, whenever the shield is below its cap
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


static func seat_color(seat: String) -> Color:
	return SEATS.get(seat, NEUTRAL)


static func span(modules: int) -> float:
	## Centre-to-centre distance of an honest edge of `modules` deck modules.
	return 2.0 * (R + PIER) + modules * S


static func heading(d: Vector3) -> float:
	## Kit rotation.y for a piece whose local +X should point along d (kit authored in Blender).
	return atan2(-d.z, d.x)
