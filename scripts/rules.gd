class_name Rules
extends RefCounted
## Every tunable number of the prototype in one place.
## Kit sizes match Models/2.0/build_kit_2_0.py. Army numbers follow Alpha 11's logic scaled by
## SCALE (PARAMETERS.md: army scale ~5x; vat caps are still an open question) - change here only.

# Bump this with every published playtest build (Daniele, 2026-09-25: "start versioning and have
# it in the interface and a changelog") - shown in the HUD; see CHANGELOG.md for what changed.
const VERSION := "0.16.2"
const VERSION_NAME := "Alpha 16"

# kit geometry (metres)
const R := 6.0                       # platform radius
const PIER := 1.6                    # connector length beyond the rim
const S := 4.0                       # one deck module (short bridge)
const W := 2.8                       # deck width
# OVERPASS (GAME-RULES sec 7: "overpasses cross at different heights without joining"): an L deck
# built as ramp up + raised span on pylons + ramp down (kit Deck_Overpass_*, OVER_H in
# build_kit_2_0.py). Hordes follow the rise; a line on an overpass never touches another deck's line.
const OVERPASS_H := 2.6
const SOCKET_Z := 0.06

# movement: travel time counts deck modules only (1 module = 2 s); platforms and piers are
# part of the node, crossed quickly
const MODULE_SECONDS := 2.0          # routing cost per module only (relative); real speed below
# Daniele (Alpha 13 playtest): "deck speed at default 5 m/s... deck speed and platform speed need to
# match, no point in it being different". Was 2 m/s on decks, x6 on platforms.
const DECK_SPEED_DEFAULT := 5.0
const NODE_SPEED_MULT_DEFAULT := 1.0
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
const RIVER_OUTER_R := 5.35          # second ring out to the rim: the goo covers the whole platform (Alpha 16)

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
const DOOR_RATE_DEFAULT := 48.0      # units/s out of the door - kept at the Alpha 12 throughput when
                                      # deck and platform speeds were unified (it was derived from them)
static var door_rate: float = DOOR_RATE_DEFAULT        # live-tunable (Debug panel)

# BRAWL MOVES LIKE ALPHA 11 (Daniele, Alpha 16: "same exit and entrance speed and deck and platform
# speed of units as Alpha 11 ... the feel exactly the same"). Alpha 11: 115 px/s everywhere (no
# platform difference), one unit leaves every 12 px (0.104 s), each lands on arrival at that spacing.
# Its mean hop is 284 px centre to centre; 2.0's is 21.9 m over the 99 maps (1.68 modules), so one
# Alpha 11 px = 0.077 m: 115 px/s = 8.9 m/s, the same 2.5 s per hop, and 12 px = 0.93 m per shown
# unit. Exit = entrance = 9.6 shown units/s (x SCALE internally). SIEGE keeps its own tunables.
const BRAWL_SPEED := 8.9                                   # m/s on decks and platforms alike
const BRAWL_DOOR_RATE := 115.0 / 12.0 * 5.0               # internal units/s out of the door (and in)
# Alpha 11's route (simulation.gd route/arc): out of the vat's FRONT (the side facing the camera),
# round the platform on its route ring to the bridge, and at the target round the ring back to the
# front and in. Its ring is 122 px (~ the platform edge); here 4.8 m inside the 6 m platform.
const BRAWL_RING := 4.8
const BRAWL_SPACING := 12.0 * 21.9 / 284.0                # 0.93 m between bodies (Alpha 11: 12 px)
const BRAWL_EXPAND := 85.0 * 21.9 / 284.0                 # 6.6 m: columns widen from single file (85 px)


static func front_dir() -> Vector3:
	## The side of every platform that faces the camera (every structure faces the viewer).
	return Vector3(0, 0, 1).rotated(Vector3.UP, view_yaw)


static func move_speed() -> float:
	return deck_speed if bridge_combat else BRAWL_SPEED


static func platform_mult() -> float:
	return node_speed_mult if bridge_combat else 1.0


static func exit_rate() -> float:
	return door_rate if bridge_combat else BRAWL_DOOR_RATE


static func metres_per_unit() -> float:
	## Line density: SIEGE's blob length, or Alpha 11's column spacing (speed / rate).
	return METRES_PER_UNIT if bridge_combat else BRAWL_SPEED / BRAWL_DOOR_RATE


static func max_chain() -> float:
	return MAX_CHAIN if bridge_combat else 100000.0     # Alpha 11 columns are as long as the send
static var node_fight_mult: float = 1.0                # live-tunable: x combat rates on a platform
# BRIDGE COMBAT toggle (Daniele: "combat like Alpha 11 or like Alpha 12 - combat on bridges, not sure
# it's fun, I wanna try with and without"). true = Alpha 12: hordes fight wherever they meet and
# queue behind friends; false = Alpha 11: hordes pass each other and only fight at nodes.
static var bridge_combat: bool = true
# LAST STAND toggle (Daniele: "add a toggle for Last Stand on or off in the match settings").
# Off: no collapse; the 7:00 safety net still ends a stalled match by strength.
static var last_stand: bool = true
# CAMERA (Daniele, Alpha 14 playtest: "map size should be fixed, no zoom... too vertical"; "vats and
# buildings should all face the viewer on every map"). The camera is fitted once per screen size,
# never zoomed or panned; VIEW_YAW is set per map before it is built so every structure faces it.
const CAM_PITCH := 42.0              # degrees above the horizon (was 55)
static var view_yaw := 0.0
# TUG-OF-WAR (bridge-combat mode): the front slides toward the weaker side at up to this fraction of
# deck speed (total dominance); 2:1 odds move it at a third of that.
const TUG_SPEED := 0.35
# GOO HOME ADVANTAGE (Daniele, Alpha 14): a horde on another player's goo corridor moves at GOO_SLOW
# of its speed and pushes at GOO_PUSH of its weight in a tug-of-war.
const GOO_SLOW := 0.7
const GOO_PUSH := 0.67
# LOW DETAIL (Debug panel): fewer river patches, no shield rings, half the horde patches - to test
# whether the build is what makes a machine "run like crazy" (Daniele, Alpha 13 playtest).
static var low_detail: bool = false
# HIDE ENEMY COUNTS (Daniele, Alpha 16: a toggle in the options and Debug). On: no unit numbers on any
# enemy node, in either mode (badges show the seat letter). Off: BRAWL shows every count as Alpha 11
# did; SIEGE never shows enemy numbers (an identity rule of 2.0).
static var hide_enemy_counts: bool = false

# CONTACT (Alpha 12, Daniele: "whenever an enemy crosses the hitbox of a unit they fight... a unit
# crossing an enemy unit should always start a combat to death"): contact is geometric, anywhere -
# decks, piers, platform arcs - a horde's head within CONTACT_R of any patch of an enemy line
# engages it; the fight then lasts until one side is gone.
const CONTACT_R := 2.1               # metres: about one deck width across, one patch along
const CONTACT_CELL := 3.0            # spatial hash cell for the contact scan

# RELAYS (GAME-RULES sec8): player-fired; 3 s warning previews the outcome, then the authoritative
# tick applies the per-kind troop fate over RELAY_MOVE seconds of visible motion (rotation pivots,
# retract slides in, switch/remote dissolve), then RELAY_COOLDOWN before the next fire.
const RELAY_WARNING := 3.0
const RELAY_COOLDOWN := 5.0        # Daniele (Alpha 13 playtest): "relay cooldown I'd set at 5 s"
const RELAY_MOVE := 1.4              # seconds the deck visibly moves/dissolves; hordes on it ride

# LAST STAND (GAME-RULES sec10; Daniele 2026-09-25: 2:00 "seems ok" for now, not 3:00). The method
# (inward / outward / chaos, from the map's eligible list) is hidden until the start, then the
# whole order is revealed; every node gets a 10 s warning before it falls; everything on a falling
# node or its decks dies. The final node is never dropped. Wave interval per map so the collapse
# is over well before the hard end.
const LAST_STAND_TIME := 120.0
const LAST_STAND_WARNING := 10.0
const LAST_STAND_WAVE_MIN := 12.0
const LAST_STAND_WAVE_MAX := 30.0
const MATCH_HARD_END := 420.0        # 7:00 safety net: still undecided -> stronger seat wins outright

# economy - Alpha 11 logic x SCALE (Daniele, Alpha 12: "start from the logic of Alpha 11... upgrades
# are free" - they are not any more). Alpha 11: caps 30/40/80/160, upgrades 10/20/30 units paid from
# the vat, cannon tiers 15/25/35, forge 20 (single tier here), 5 s builds (10 s here: PARAMETERS).
const SCALE := 5.0
const CAPS := {1: 150, 2: 200, 3: 400, 4: 800}       # Alpha 11 owned caps x5
const PROD := {1: 5.0, 2: 8.0, 3: 12.0, 4: 17.5}     # Alpha 11 1.0/1.6/2.4/3.5 units/s x5
const HOME_TIER := 2
const VAT_COST := {1: 50, 2: 100, 3: 150}            # tier t -> t+1
const CANNON_COST := {1: 75, 2: 125, 3: 175}         # build T1, then upgrade to T2, T3
const FORGE_COST := 100
const BUILD_SECONDS := 10.0          # vat upgrade or attachment build/upgrade time (GAME-RULES sec6)
const SWAP_COOLDOWN := 10.0          # after an attachment swap completes, before the next swap
const CANNON_RANGE := 12.0           # metres from the node's centre: covers its piers + first module
# Alpha 11 cannon: a burst lasts 2 s and kills at most 10/25/40 bodies (x5 here), recharge AFTER
# the burst 4/2.4/1.6 s; body kills bypass fight math.
const CANNON_STATS := {1: {"recharge": 4.0, "kill": 50.0}, 2: {"recharge": 2.4, "kill": 125.0},
		3: {"recharge": 1.6, "kill": 200.0}}
const CANNON_BURST := 2.0
# Alpha 11 forge: strongest completed forge adds +50 on the 100 attack scale (+0.5 displayed attack)
# - a +50 % damage bonus to everything its owner's troops deal. Single tier in 2.0 (GAME-RULES
# sec6); a mixed allied garrison defends at the population-weighted average (Sim.forge_of).
static var forge_bonus: float = 0.5  # live-tunable
const HOME_UNITS := 80
const NEUTRAL_UNITS := {1: 30, 2: 60, 3: 120, 4: 200}
const SEND_FRACTIONS := [0.25, 0.5, 0.75, 1.0]

# SHIELD (Daniele, 2026-09-25 / Alpha 12 clarification): passing through an enemy node is allowed -
# the goo RING around the tower is a shield worth SHIELD_FRACTION of the garrison; a transiting
# force fights the shield, never the garrison (only an arrival touches that), while the garrison
# fires back. Breaking it does NOT destroy any bridge: the BOND is the goo trail between two of a
# player's adjacent nodes - shown only while BOTH shields are up - and it disappears when either
# shield breaks. A broken shield is DOWN (free passage) until it has regenerated to full.
const SHIELD_FRACTION := 0.2
const SHIELD_REGEN := 3.0            # units/s, whenever the shield is below its cap

# frontline combat - PROVISIONAL: each side loses BASE + K * enemy units per second
const FIGHT_RATE_BASE := 12.0
const FIGHT_RATE_K := 0.08

const SEATS := {
	"A": Color("#2ee6ff"), "B": Color("#7dff5a"), "C": Color("#b48cff"),
	"D": Color("#ff5a5a"), "E": Color("#ffd23f"), "F": Color("#ff8fc8"),
}
const NEUTRAL := Color("#a9b8c8")
# relay state colours - the roster legend (BUILDING-PIECES.md B): the deck a state controls carries
# its colour on its edge lights, the relay tower's symbol glows in the current state's colour
const STATE_COLORS := {
	"r1": Color("#ffd23f"), "r2": Color("#ff8c2a"), "r3": Color("#ff4f9a"), "retract": Color("#ff5a5a"),
	"s1": Color("#ffffff"), "s2": Color("#8fb3ff"), "s3": Color("#c9a3ff"),
	"m1": Color("#ff9ecf"), "m2": Color("#9be7c4"), "warn": Color("#ff5a5a"), "build": Color("#ffd23f"),
}
const RELAY_GLYPH := {"rotation": "↻", "retract": "⇤", "switch": "⇄", "remote": "⌁"}
# texture hue of each Alpha 11 creature map, and the race accent colour
const FACTIONS := {
	"vex": [0.518, Color("#19e5ff")], "null": [0.894, Color("#ff19ab")],
	"bloom": [0.236, Color("#6fff2a")], "ember": [0.085, Color("#ff3b1f")],
	"solar": [0.12, Color("#ffbe19")],
}
# FACTION STAT PROFILES - Alpha 11's provisional tuning (faction_balance.gd), the GAME-RULES sec3
# leans: one readable strength, one readable weakness each. speed = travel speed, health = damage
# a horde takes (divides it), attack = damage dealt, production = vat output, garrison = damage a
# garrison takes (divides it). Baseline 1.0 everywhere.
const FACTION_STATS := {
	"vex": {"speed": 1.15, "garrison": 0.90},
	"null": {},
	"bloom": {"speed": 0.90, "production": 1.15},
	"ember": {"attack": 1.15, "production": 0.90},
	"solar": {"health": 1.10, "garrison": 1.05, "speed": 0.90, "production": 0.90},
}
const FACTION_NAMES := {"vex": ["VEX", "BIOENGINEERS"], "null": ["NULL", "DATA CARTEL"], "bloom": ["VIRIDIAN", "BLOOM"],
		"ember": ["EMBER", "MAW"], "solar": ["SOLAR", "SHELLS"]}
const FACTION_TAGLINES := {"vex": "ADAPT. CONNECT. REDIRECT.", "null": "SAME SIGNAL. DIFFERENT TRUTH.",
		"bloom": "A WILDER TOMORROW.", "ember": "PRESSURE BREEDS PROGRESS.", "solar": "HOLD THE LIGHT."}
const FACTION_TRAITS := {"vex": ["Efficient routing", "Faster travel on owned connections."],
		"null": ["Obscured intel", "Hide precise counts from enemies."],
		"bloom": ["Biomass recovery", "Recover a portion of nearby losses."],
		"ember": ["Siege pressure", "Pressure defended structures."],
		"solar": ["Connected defense", "Protect connected friendly nodes."]}
const FACTION_ULTIMATE := {"vex": ["Route Hack", "the route and relay specialist"], "null": ["Echo Split", "decoys, disruption of enemy control"],
		"bloom": ["Spore Bloom", "growth"], "ember": ["Core Meltdown", "siege"], "solar": ["Relay Aegis", "protecting a crossing"]}
const FACTION_BLURB := {
	"vex": "VEX Bioengineers - mobility and routes. Faster, weaker garrison.",
	"null": "NULL Data Cartel - deception and disruption. Near baseline.",
	"bloom": "Viridian Bloom - growth. Faster production, slower movement.",
	"ember": "Ember Maw - siege. Stronger attack, slower production.",
	"solar": "Solar Shells - defense. More HP and defense, slower to move and produce.",
}
# AI levels (Alpha 11 had five; three here - no economy or combat cheats, only how often it thinks
# and how much margin it wants before attacking)
const AI_LEVELS := {
	"Casual": {"period": 4.0, "margin": 1.5, "relays": false},
	"Standard": {"period": 2.5, "margin": 1.15, "relays": true},
	"Veteran": {"period": 1.6, "margin": 1.0, "relays": true},
}


# NUMBERS ON SCREEN (Daniele, Alpha 12 playtest: "big numbers don't look good - back to what Alpha 11
# had, with Alpha 12's amount of troops"): the sim runs at SCALE x Alpha 11 so hordes stay long, but
# every number the player sees is divided by SCALE - caps read 30/40/80/160, upgrades 10/20/30.
static func shown(units: float) -> int:
	return int(round(units / SCALE))


static func shown_f(units: float) -> float:
	return units / SCALE


static func stat(faction: String, key: String) -> float:
	return float(FACTION_STATS.get(faction, {}).get(key, 1.0))


# SEAT COLOURS for the current match (Daniele, Alpha 14: "implement faction colour selection").
# Filled by assign_colors() at match start: your pick, the rest from the palette; "faction" mode uses
# each seat's faction colour (Alpha 11 style); team modes give each team one hue, light and dark.
static var seat_colors: Dictionary = SEATS.duplicate()
const PALETTE := ["A", "B", "C", "D", "E", "F"]        # cyan, green, purple, red, gold, rose


static func seat_color(seat: String) -> Color:
	return seat_colors.get(seat, SEATS.get(seat, NEUTRAL))


# Player colours, Alpha 16 (Daniele: "in 2v2 and team matches the hue must be very recognisable from
# one player to another, and in FFA the colours very different - green, red, blue, purple"). FFA: each
# seat takes the next far-apart hue. Teams: each team is one family (cool / warm) and every player in
# it still has a clearly different hue, so you read both "which team" and "which player".
const HUES := {
	"red": Color("#ff4545"), "green": Color("#6dff4a"), "blue": Color("#4a78ff"), "gold": Color("#ffd23f"),
	"purple": Color("#b36bff"), "cyan": Color("#2ee6ff"), "rose": Color("#ff5ab8"), "orange": Color("#ff9a2e"),
}
const FFA_ORDER := ["red", "green", "blue", "gold", "purple", "cyan", "rose", "orange"]
const TEAM_FAMILIES := [["cyan", "green", "blue"], ["red", "gold", "rose"]]   # 2v2: cyan+green vs red+gold


static func _hue_gap(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d)


static func assign_colors(seats: Array, factions: Dictionary, human: String, choice: String, teams: Dictionary) -> void:
	## choice: a palette key ("A".."F") for your colour, or "faction".
	seat_colors = {}
	var mine: Color = FACTIONS[factions.get(human, "null")][1] if choice == "faction" else SEATS.get(choice, SEATS["A"])
	if not teams.is_empty():
		# your team takes the family closest to your pick (your pick first), the other team the other
		var cool := TEAM_FAMILIES[0].map(func(k): return HUES[k])
		var warm := TEAM_FAMILIES[1].map(func(k): return HUES[k])
		var near_cool: float = cool.map(func(c): return _hue_gap(c, mine)).min()
		var near_warm: float = warm.map(func(c): return _hue_gap(c, mine)).min()
		var own: Array = cool if near_cool <= near_warm else warm
		var other: Array = warm if own == cool else cool
		own = [mine] + own.filter(func(c): return _hue_gap(c, mine) > 0.07)
		var family := {teams.get(human, 0): own}
		for s in seats:
			if not family.has(teams.get(s, 0)):
				family[teams.get(s, 0)] = other
		var count := {}
		for s in ([human] + seats.filter(func(x): return x != human)):
			var t = teams.get(s, 0)
			var list: Array = family.get(t, other)
			var i: int = count.get(t, 0)
			seat_colors[s] = list[i % list.size()] if i < list.size() else (list[i % list.size()] as Color).darkened(0.35)
			count[t] = i + 1
		return
	var used := [mine]
	seat_colors[human] = mine
	for s in seats:
		if s == human:
			continue
		var c: Color = HUES["red"]
		var want: Color = FACTIONS[factions.get(s, "null")][1] if choice == "faction" else Color(0, 0, 0, 0)
		if choice == "faction" and used.all(func(u): return _hue_gap(u, want) > 0.07):
			c = want
		else:
			var picked := false
			for k in FFA_ORDER:
				if used.all(func(u): return _hue_gap(u, HUES[k]) > 0.12):
					c = HUES[k]
					picked = true
					break
			if not picked:
				c = (HUES[FFA_ORDER[used.size() % FFA_ORDER.size()]] as Color).darkened(0.35)
		seat_colors[s] = c
		used.append(c)


static func state_color(state: String) -> Color:
	return STATE_COLORS.get(state, Color.WHITE)


static func span(modules: int) -> float:
	## Centre-to-centre distance of an honest edge of `modules` deck modules.
	return 2.0 * (R + PIER) + modules * S


static func heading(d: Vector3) -> float:
	## Kit rotation.y for a piece whose local +X should point along d (kit authored in Blender).
	return atan2(-d.z, d.x)
