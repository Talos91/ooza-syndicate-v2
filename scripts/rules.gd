class_name Rules
extends RefCounted
## Every tunable number of the prototype in one place.
## Kit sizes match Models/2.0/build_kit_2_0.py. Army numbers follow Alpha 11's logic scaled by
## SCALE (PARAMETERS.md: army scale ~5x; vat caps are still an open question) - change here only.
##
## SIEGE IS DEACTIVATED since 0.18.7 (Daniele: "for now completely deactivate it, i don't wanna waste
## resources on a mode we are less and less keeping into consideration, if we will pick it up later we
## will simply do, brawl is our game"). The game is BRAWL only: bridge_combat is locked false (SIEGE_ON),
## no UI or flag can switch it, and the tests no longer cover SIEGE. Its numbers and code paths stay,
## dormant and untested - re-enable with SIEGE_ON and expect to re-test everything.

# Bump this with every published playtest build (Daniele, 2026-09-25: "start versioning and have
# it in the interface and a changelog") - shown in the HUD; see CHANGELOG.md for what changed.
const VERSION := "0.22.2"
const VERSION_NAME := "Alpha 22"


static func version_label() -> String:
	## What the screens show (Daniele, 2026-09-29: "shouldn't it be just alpha 22.0x"): "ALPHA 22.2" from VERSION 0.22.2 - the
	## internal VERSION stays x.y.z (pack URLs ?v=, the exact-match rule online).
	var parts := VERSION.split(".")
	if parts.size() == 3 and parts[0] == "0":
		return "ALPHA %s.%s" % [parts[1], parts[2]]
	return "%s v%s" % [VERSION_NAME.to_upper(), VERSION]

# kit geometry (metres)
const R := 6.0                       # platform radius
const PIER := 1.6                    # connector length beyond the rim
const S := 4.0                       # one deck module (short bridge)
const W := 2.8                       # deck width
# OVERPASS (GAME-RULES sec 7: "overpasses cross at different heights without joining"): an L deck
# built as ramp up + raised span on pylons + ramp down (kit Deck_Overpass_*, OVER_H in
# build_kit_2_0.py). Hordes follow the rise; a line on an overpass never touches another deck's line.
# legacy maps/ only - maps 3.0 use MapBuilder.OVER_H levels
const OVERPASS_H := 2.6

# legacy maps/ routing cost per deck module (Sim.edge_cost, non-v3 only); maps 3.0 route by
# drawn length / move_speed()
const MODULE_SECONDS := 2.0          # routing cost per module only (relative); real speed below
const ROUTE_NODE_SECONDS := 1.0      # routing: what crossing a node adds to a route (Sim.find_route; relative)
# the pour (a line walking off a missing deck's lip, Sim._cut_range / step): a head at most POUR_STEP m past the
# lip walked off it this step (view only); a line pouring into its target enters at least POUR_MIN_RATE units/s
const POUR_STEP := 1.0
const POUR_MIN_RATE := 4.0
# Daniele (Alpha 13 playtest): "deck speed at default 5 m/s... deck speed and platform speed need to
# match, no point in it being different". Was 2 m/s on decks, x6 on platforms.
const DECK_SPEED_DEFAULT := 5.0
const NODE_SPEED_MULT_DEFAULT := 1.0
# live-tunable from the in-game Debug panel (PLAYTEST-NOTES 5: platform speed vs bridge speed)
# - SIEGE only (BRAWL uses BRAWL_SPEED)
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

# UNITS LEAVE THE VAT ONLY AS THEY BECOME BLOB (Daniele, 2026-09-25): a send is an order; the door
# emits units into the line at DOOR_RATE. Units still inside stay in the vat's count and can be
# re-ordered - a new send takes over the previous order's not-yet-emitted part.
const DOOR_RATE_DEFAULT := 48.0      # units/s out of the door - kept at the Alpha 12 throughput when
                                      # deck and platform speeds were unified (it was derived from them)
static var door_rate: float = DOOR_RATE_DEFAULT        # live-tunable (Debug panel) - SIEGE only (BRAWL uses BRAWL_DOOR_RATE)

# BRAWL MOVES LIKE ALPHA 11 (Daniele, Alpha 16: "same exit and entrance speed and deck and platform
# speed of units as Alpha 11 ... the feel exactly the same"). Alpha 11: 115 px/s everywhere (no
# platform difference), one unit leaves every 12 px (0.104 s), each lands on arrival at that spacing.
# Its mean hop is 284 px centre to centre; 2.0's is 21.9 m over the 99 maps (1.68 modules), so one
# Alpha 11 px = 0.077 m: 115 px/s = 8.9 m/s, the same 2.5 s per hop, and 12 px = 0.93 m per shown
# unit. Exit = entrance = 9.6 shown units/s (x SCALE internally). SIEGE keeps its own tunables.
# (Those figures predate Alpha 17's and Alpha 18's -20 % each: now 5.7 m/s, ~0.59 m per shown unit.)
const BRAWL_SPEED := 8.9 * 0.8 * 0.8                       # m/s, decks and platforms alike (Daniele, Alpha 17: "20% slower";
                                                           # 0.18.4: "deck speed on brawl a bit slower ... reduce by 20%")
const BRAWL_DOOR_RATE := 115.0 / 12.0 * 5.0               # internal units/s out of the door (and in)
# Alpha 11's route (simulation.gd route/arc): out of the vat's FRONT (the side facing the camera),
# round the platform on its route ring to the bridge, and at the target round the ring back to the
# front and in. Its ring is 122 px (~ the platform edge); here 4.8 m inside the 6 m platform.
const BRAWL_RING := 4.8
const BRAWL_SPACING := BRAWL_SPEED / BRAWL_DOOR_RATE * 5.0   # metres between bodies: speed / Alpha 11 rate
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
const NODE_FIGHT_MULT_DEFAULT := 1.0
static var node_fight_mult: float = NODE_FIGHT_MULT_DEFAULT   # live-tunable: x combat rates on a platform
# BRIDGE COMBAT toggle (Daniele: "combat like Alpha 11 or like Alpha 12 - combat on bridges, not sure
# it's fun, I wanna try with and without"). true = Alpha 12: hordes fight wherever they meet and
# queue behind friends; false = Alpha 11: hordes pass each other and only fight at nodes.
const SIEGE_ON := false                   # 0.18.7: SIEGE deactivated - bridge_combat can't be switched on
static var bridge_combat: bool = false:   # BRAWL (Daniele, 2026-09-26: "brawl is back as the main game mode
	set(v):                               # and siege is just an abandoned test for now"); locked since 0.18.7
		bridge_combat = v and SIEGE_ON
# LAST STAND toggle (Daniele: "add a toggle for Last Stand on or off in the match settings").
# Off: no ring collapse; the Very Last Stand still runs at 6:00 and the 7:00 end still decides.
static var last_stand: bool = true
# CAMERA (Daniele, Alpha 14 playtest: "map size should be fixed, no zoom... too vertical"; "vats and
# buildings should all face the viewer on every map"). The camera is fitted once per screen size,
# never zoomed or panned; VIEW_YAW is set per map before it is built so every structure faces it.
const CAM_PITCH := 58.0              # degrees above the horizon for a map MapCamera doesn't list (Alpha 14: 42,
                                     # "too vertical" at 55 on the deep maps 3.0; Alpha 18, maps 4.0: "a bit more
                                     # from the top" - each map gets its own pitch, 58 on every maps 4.2 map, see MapCamera)
static var view_yaw := 0.0
# TUG-OF-WAR (bridge-combat mode): the front slides toward the weaker side at up to this fraction of
# deck speed (total dominance); 2:1 odds move it at a third of that.
const TUG_SPEED := 0.35
# GOO HOME ADVANTAGE (Daniele, Alpha 14): a horde on another player's goo corridor moves at GOO_SLOW
# of its speed and pushes at GOO_PUSH of its weight in a tug-of-war.
const GOO_SLOW := 0.7
const GOO_PUSH := 0.67
# LOW DETAIL (Debug panel / options): half the river ring and no outer ring, one resident per tank,
# no surface normal maps (for materials built after it is set) - to test whether the build is what
# makes a machine "run like crazy" (Daniele, Alpha 13 playtest).
static var low_detail: bool = false
# HIDE ENEMY COUNTS (Daniele, Alpha 16: a toggle in the options and Debug). On: no unit numbers on any
# enemy node, in either mode (badges show the seat letter). Off: BRAWL shows every count as Alpha 11
# did; SIEGE never shows enemy numbers (an identity rule of 2.0).
static var hide_enemy_counts: bool = false
# DEBUG TOOLS (Daniele, 0.18.7: "we are past debug tools ... you can hide them (in case we want to reactivate
# them later maybe put in options)"): the in-match Debug button and panel, off unless switched on in OPTIONS.
static var debug_tools: bool = false
# TERRITORY LOOK (Daniele, 0.18.7: "the lane fight chat did some try with goo instead of neons, can you
# try adding it so i can get the feel of it and add it as a toggle (could be a cosmetic later on)").
# false = NEON (today's owner-colour neon trims, pier stripes and rims); true = GOO: owned platforms and
# deck halves under goo in the player colour, units in their race colour with a player-colour rim
# (GooTerritory, UnitView). BRAWL only - SIEGE's hordes are goo already and keep today's look. Pure view.
static var goo_territory: bool = false


static func goo_look() -> bool:
	return goo_territory and not bridge_combat

# CONTACT (Alpha 12, Daniele: "whenever an enemy crosses the hitbox of a unit they fight... a unit
# crossing an enemy unit should always start a combat to death"): contact is geometric, anywhere -
# decks, piers, platform arcs - a horde's head within CONTACT_R of any patch of an enemy line
# engages it; the fight then lasts until one side is gone.
const CONTACT_R := 2.1               # metres: about one deck width across, one patch along
const CONTACT_CELL := 3.0            # spatial hash cell for the contact scan

# RELAYS (GAME-RULES sec8): player-fired; the warning previews the outcome (the deck is still there and
# walkable: lines on it have RELAY_WARNING s to clear it), then the authoritative tick takes the going
# decks away at once - every body still on one falls, whatever the kind (Daniele, 0.18.7: "no bridge =
# bridge down") - while RELAY_MOVE seconds of visible motion play (rotation pivots and flings, retract
# slides in, switch/remote dissolve); an appearing deck is walkable once its motion ends; then
# RELAY_COOLDOWN before the next fire.
const RELAY_WARNING := 1.0          # Daniele (0.18.6): "bridge alert ... just 1 sec" (was 3 s)
const RELAY_COOLDOWN := 5.0        # Daniele (Alpha 13 playtest): "relay cooldown I'd set at 5 s"
# Daniele (2026-09-28): rotors can be used as "meat grinders" (always connected, dropping what is on their decks) -> a longer
# cooldown for ROTATION relays ("10 is fine for now"); other kinds keep RELAY_COOLDOWN.
const RELAY_COOLDOWN_BY_KIND := {"rotation": 10.0}


static func relay_cooldown(kind: String) -> float:
	return float(RELAY_COOLDOWN_BY_KIND.get(kind, RELAY_COOLDOWN))

const RELAY_MOVE := 1.4              # seconds the deck visibly moves/dissolves (its troops fell when it started)
# RELAY V2 (the relay redo, Alpha 22 - Daniele 2026-09-28 "they good"; Models/2.0/structures_2_1/relay_v2.json +
# build_relay_v2.py): one standard BUTTON PLATFORM per relay off the rim (Relay_Button_<Kind>_v2, the tap target),
# a MECHANISM on the pier of every relay bridge, marked relay decks and violet GHOSTS of where the bridge will be.
# The node centre holds the structure (laser / forge / monster hub); a double-tap on the button or the node fires it.
const RELAY_RIM_DIST := 8.45         # json RIM_DIST: the pad centre from the node centre (R + pad + 0.45)
const RELAY_PAD_R := 2.0             # json pad_radius
const RELAY_BUTTON_Y := 0.22         # json buttons[*][2]: the "Button" empty (tap target) above the pad
const RELAY_BUTTON_CLEAR := RELAY_PAD_R + W / 2.0 + 0.3   # pad radius + half a deck + 0.3 m: pad and bridge never touch
const RELAY_MIN_SEP := 25.97         # json min_separation_deg_from_any_bridge = asin(CLEAR / RIM_DIST): a node needs a
                                     # 51.9 deg gap between two bridges (json node_needs_a_gap_of_deg; test_maps4 checks it);
                                     # a smaller gap moves the pad out to CLEAR / sin(gap / 2) and stretches its Strut
const RELAY_HIT_PT := 44.0           # the button's tap disc on a phone, points across (Apple's minimum; tests/phone_fit)
const RELAY_HIT_PAD := 1.15          # the disc is at least the pad's projected radius x this (desktop / close-ups)
const RELAY_GHOST := Color(0.85, 0.78, 1.0, 0.28)       # OS_Ghost: the neutral violet floor (the Pier_Ghost_v2 fallback)
const RELAY_GHOST_EDGE := Color(0.92, 0.88, 1.0)        # OS_Ghost_Edge: its bright frame
# v2g (Daniele: "the ghost should have also different colour so even as ghost you can see what is switch and what is
# rotation"): each kind's ghost in its own hue (relay_v2.json ghost_colors; OS_Ghost_<Kind> floor + OS_Ghost_<Kind>_Edge)
const RELAY_GHOST_COLORS := {"rotation": Color("#4f8bff"), "switch": Color("#ffb238"), "remote": Color("#5cffb0"),
		"retract": Color("#ff6a5a")}         # switch = Hud.RELAY_ACCENT
const RELAY_GHOST_ALPHA := 0.45      # json: the kind ghosts' floor alpha (see-through; the edges are emissive)
const RELAY_GHOST_WARN := 2.4        # x the ghost's brightness while its relay's warning runs (it is about to be real)
# The remote's LINK (Daniele 2026-09-28: "the cable looks too weird, time to improve its look"): a thin glowing arc in
# the relay's state colour from its button up over the map to the receiver masts of the Relay_Gate_Remote_v2 on the
# far bridge (RelayView.add_link). Faint at rest; small pulses run button -> gate while the relay is ready; a quick
# bright blink along it while it fires; dim on cooldown; hidden once an end has dropped.
const RELAY_LINK_MAST := Vector3(7.3, 3.15, 0.0)   # gate local point between the receiver dishes (json: pylons x 7.3, masts 3.27)
const RELAY_LINK_W := 0.3            # m ribbon width (soft edges)
const RELAY_LINK_RISE := 0.28        # apex height x the link's length ...
const RELAY_LINK_RISE_MIN := 5.0     # ... at least (m; over every structure on the way) ...
const RELAY_LINK_RISE_MAX := 16.0    # ... at most
const RELAY_LINK_REST := 0.22        # alpha at rest (ready, or firing)
const RELAY_LINK_DIM := 0.12         # alpha on cooldown / neutral
const RELAY_LINK_PULSE := 0.75       # pulse brightness while ready
const RELAY_LINK_GAP := 7.0          # m between two pulses
const RELAY_LINK_SPEED := 9.0        # m/s the pulses travel
const RELAY_LINK_NEAR := 16.0        # m: a remote bridge whose gate is this close to the button needs no link
# AI relay sense (0.18.7 - Daniele: "the ai tends to avoid relay bridges all together and almost never
# build structure on relays"). From Standard up (AI_LEVELS "relays" >= 1) an order crosses a relay deck
# unless somebody hostile can change that deck before the whole line is over it (estimated crossing
# x AI_RELAY_SLACK + AI_RELAY_PAD s, the door's emission included); a safe detour is taken when it costs
# at most AI_RELAY_DETOUR s (or doubles the trip), otherwise the risky route is priced at AI_RELAY_RISK.
const AI_RELAY_SLACK := 1.25
const AI_RELAY_PAD := 1.0
const AI_RELAY_DETOUR := 8.0
const AI_RELAY_RISK := 14.0          # target-score penalty for a plan whose only route is at risk
const AI_EVAC_MARGIN := 6.0          # s: a warned ring platform empties when its drop is this much beyond trip + one think
const AI_RELAY_VALUE := 10.0         # target-score bonus for a relay node (control of shortcuts), + its traffic
# (0.18.10: the fixed 6-unit relay garrison AI_RELAY_HOLD is gone - Daniele, 2026-09-27: relay nodes are held and
# built on like any node; the AI garrisons them by threat like its other nodes, knowing they produce nothing.)
# AI STRUCTURES 2.1 (0.18.10): a machinegoon goes on a frontline common node that keeps taking small raids - at
# least AI_TRICKLE_RAIDS hostile lines of at most AI_TRICKLE_UNITS sim units in the last AI_TRICKLE_WINDOW s - and
# never on its home or its only vats (it needs AI_MACHINEGOON_VATS vats). Monsters: Veteran / Expert launch at the
# best target worth AI_MONSTER_VALUE sim units (garrison taken + hostile bodies kicked); the lower levels launch
# rarely (AI_MONSTER_CHANCE per think with a ready hub) at any hostile node in reach. EJECT (team modes): only to
# save stored allied troops from a node about to drop in the Last Stand.
const AI_TRICKLE_UNITS := 100.0
const AI_TRICKLE_RAIDS := 2
const AI_TRICKLE_WINDOW := 60.0
const AI_MACHINEGOON_VATS := 4
const AI_MONSTER_VALUE := 60.0
const AI_MONSTER_CHANCE := {"Training": 0.05, "Casual": 0.08, "Standard": 0.12}
# AI TEAMWORK (0.21.5, Daniele 2026-09-28: "make sure ai take advantage of coop mode and is more strong (but not
# unbeatable)"). Team modes only; decisions only - no economy or combat number changes. The AI seats of one team
# share a board on the match (SeatAI._board): who is on it, the team's common enemy and open calls for a joint
# offensive. AI_LEVELS "teamwork" tiers: 1 reinforces an ally's node that would fall from its nodes next door (it
# covers "assist" of the ally's shortfall, after leaving the ally one think to answer, and only if it can cover most
# of it); 2 also from any node whose help lands in time, goes after the team's common enemy (target-score bonus
# "focus"), backs up an ally's offensive that is short, answers an ally's call (bringing its own offensive forward by
# up to "sync" s) and moves rear surplus to the team front; 3 also calls joint offensives on the common enemy's nodes
# it cannot take alone (it pledges its share and sends once an answer is on the way). The common enemy is the
# weakest, most exposed rival seat, a human preferred (AI_TEAM_HUMAN_BONUS), held AI_TEAM_FOCUS_HOLD s (a current
# focus keeps AI_TEAM_FOCUS_STICK). Measured by tests/test_ai_coop.gd (teamwork on vs off, same level).
const AI_TEAM_FOCUS_HOLD := 20.0
const AI_TEAM_FOCUS_STICK := 3.0
const AI_TEAM_HUMAN_BONUS := 4.0
const AI_TEAM_HUMAN_AFTER := 6.0       # s: a seat no AI thinks for by then is a human (every level thinks within 5 s)
const AI_TEAM_CALL_TTL := 8.0          # s an ally's call for a joint offensive stays open
const AI_TEAM_CALL_BONUS := 40.0       # target-score bonus for answering an ally's call (and it is taken first)
const AI_TEAM_JOIN_BONUS := 10.0       # target-score bonus for a node an ally's line is already attacking, short
const AI_TEAM_JOINT_SHARE := 0.35      # a joint offensive: the caller brings at least this share of what it needs
const AI_TEAM_SURPLUS := 0.9           # a rear node this full (of its cap) sends surplus to the team front
const AI_TEAM_SURPLUS_TRAVEL := 25.0   # s: the farthest front a surplus send goes to
const AI_TEAM_DEFEND_LATE := 4.0       # s: an ally's node is reinforced only if help lands at most this long after the threat

# LAST STAND (GAME-RULES sec10; Daniele 2026-09-25: 2:00 "seems ok" for now, not 3:00). The method
# (inward / outward / chaos, from the map's eligible list) is hidden until the start, then the
# whole order is revealed; every node gets a 10 s warning before it falls; everything on a falling
# node or its decks dies. The final node is never dropped. Wave interval per map so the collapse
# is over well before the hard end.
const LAST_STAND_TIME := 240.0       # Daniele (2026-09-28): "last stand starts too early push it to 4 minutes" (was 3:00; VLS stays 6:00)
const LAST_STAND_WARNING := 10.0
const LAST_STAND_WAVE_MIN := 12.0
const LAST_STAND_WAVE_MAX := 30.0
const LAST_STAND_WAVE_SPARE := 90.0  # s before the hard end the ring waves' spacing leaves free (Sim.last_stand_wave)
const LAST_STAND_FIT_SPARE := 3.0    # s of slack the adaptive ring gap keeps before the Very Last Stand (Sim._fit_gap)
# A ring falls platform by platform (Daniele, 0.18.4: "don't make all outward rings fall at the same time but one
# after the other ... following the rule we set for falling bridges"): after the ring's 10 s warning its platforms
# drop one at a time, never leaving the rest of the map cut off, the rings back to back.
# ADAPTIVE GAP (Daniele, 2026-09-27: "instead of a platform every 5 seconds, we do every 20; I think it makes it
# more fair" - "Aim for 20 s, fit the time"): the gap between drops is fixed per match at the Last Stand's start
# (Sim.last_stand_gap) - as slow as possible up to LAST_STAND_DROP_GAP_MAX, never under _MIN, sized so every wave's
# warning and drops end before the Very Last Stand (VERY_LAST_STAND_TIME). If even _MIN can't fit, _MIN it is and
# the leftovers go to the Very Last Stand.
const LAST_STAND_DROP_GAP_MAX := 20.0
const LAST_STAND_DROP_GAP_MIN := 8.0
const LAST_STAND_DROP_GAP := 5.0     # the old fixed ring gap - no longer the rule (see Sim.last_stand_gap); the
                                     # tutorial's staged Very Last Stand (tutorial.gd vls_gap "warning+gap") reads it
const MATCH_HARD_END := 420.0        # 7:00 end: the side owning the Very Last Stand's last platform wins (Sim._force_end)
# 7:00 DRAW (Daniele, 2026-09-27: "I d say DRAW and we say something funny ... for no one to have it means they
# didn t even tried ... we can kinda call them out"): a still-neutral last platform is a draw with one of these
# call-out lines (picked by the match seed; Sim.draw_line, the {"type": "draw", "line"} event).
const DRAW_LINES := [
	"DRAW - nobody even tried for the last platform.",
	"DRAW - the last vat sat there. Alone. Waiting.",
	"DRAW - bold strategy: let the neutrals win.",
	"DRAW - the neutrals held the last platform. Against everyone.",
	"DRAW - seven minutes, and the last vat never met a single one of you.",
]

# VERY LAST STAND (Daniele, 0.18.9: "Very Last Stand: at 6 every 10 sec a node with 2 or 1
# connection falls randomly until only 1 node is left"; a stalemate breaker for whatever the ring
# Last Stand left standing, which used to stall matches to the 7:00 hard end (26% of Standard AI
# matches). Follow-up: "whatever the number of nodes left, they drop one by one in the same time
# span until one is left at 7; the time between falls is due to the number of nodes" - so the
# interval is derived at 6:00 from how many platforms survive (Sim.very_last_stand_gap), not a fixed
# number: it spreads the drops evenly so the last one lands exactly at MATCH_HARD_END. Tweak only
# this start time for a shorter/longer window (Daniele: "only tweak if we want them to be 1 min or
# 1.5 min").
const VERY_LAST_STAND_TIME := 360.0   # runs on every map, LAST STAND ON or OFF (Daniele, 2026-09-27: "Very Last Stand anyway")

# economy - Alpha 11 logic x SCALE (Daniele, Alpha 12: "start from the logic of Alpha 11... upgrades
# are free" - they are not any more). Alpha 11: caps 30/40/80/160, upgrades 10/20/30 units paid from
# the vat, cannon tiers 15/25/35, forge 20 (single tier here), 5 s builds (10 s here: PARAMETERS).
# The economy numbers are static vars (0.18.7) so a balance preset or the balance probe can change
# them (apply_balance below); these values are the default game and nothing changes them by default.
const SCALE := 5.0
# 0.18.10 (Daniele, 2026-09-27: "30 40 80 160 is good but i d change them slightly: 30/60/120/200"): owned
# caps 30 / 60 / 120 / 200 shown; production unchanged.
static var CAPS := {1: 150, 2: 300, 3: 600, 4: 1000}      # shown 30 / 60 / 120 / 200
static var PROD := {1: 5.0, 2: 8.0, 3: 12.0, 4: 17.5}     # Alpha 11 1.0/1.6/2.4/3.5 units/s x5
# NEUTRAL REGEN (Daniele, 0.18.9: "make neutral villages regenerate at the speed of their vat"): a chipped
# neutral vat node grows back at its tier's PROD (no faction bonus), up to its starting garrison NEUTRAL_UNITS.
const NEUTRAL_REGEN := true
# HOMES (Daniele, 2026-09-27: "T1 like the packs", "they start at 1" - Alpha 11's start): T1 with 1 unit shown.
static var HOME_TIER := 1
static var HOME_UNITS := 5
# OWNED VATS STOP AT T3 (Daniele, 2026-09-27: "Map-placed only"): no T3 -> T4 upgrade; a T4 exists only where a
# map places it (special nodes), and conquest never downgrades it ("Keeps T4").
const VAT_MAX_UPGRADE := 3
static var VAT_COST := {1: 50, 2: 100, 3: 150}            # tier t -> t+1 (3 -> 4 is never offered)
static var BUILD_SECONDS := 10.0          # every build / upgrade / swap takes this long (GAME-RULES sec6)
static var SWAP_COOLDOWN := 10.0          # after a structure swap completes, before the next swap
# STRUCTURES 2.1 (Daniele, 2026-09-27; OPEN-QUESTIONS "Structures 2.1 numbers"). What a node can hold:
#   common (normal vat node): a vat T1-T3 OR a Machinegoon T1-T3 in its place (swapping = a BUILD_SECONDS build,
#       then SWAP_COOLDOWN; the tier carries over);
#   relay: one of Laser tower / Forge / Monster hub (single tier, swappable like the old attachments);
#   special (strategic nodes, T4 neutrals): only its vat (no machinegoon, no relay structure).
const NODE_BUILDS := {"common": ["vat", "machinegoon"], "relay": ["laser", "forge", "monster_hub"], "special": ["vat"]}
# MACHINEGOON: a continuous goo stream at the nearest enemy line whose head is within MACHINEGOON_RANGE of the node
# centre, 2 / 3.5 / 5 kills/s shown; body kills bypass combat math like the laser; the node produces nothing
# while it holds one (it keeps and can be reinforced its garrison). Build 15, upgrades 20 / 30 shown.
static var MACHINEGOON_COST := {1: 75, 2: 100, 3: 150}     # build (T1), then upgrade to T2, T3
static var VAT_RESTORE_COST := 75         # machinegoon -> vat, 15 shown (Daniele, 2026-09-27: "cost price of a tier 1 vat ... maybe 15")
static var MACHINEGOON_RATE := {1: 8.0, 2: 14.0, 3: 20.0} # kills/s (shown 1.6 / 2.8 / 4; -20 %, Daniele 2026-09-28)
static var MACHINEGOON_RANGE := 10.0
# LASER TOWER (replaces the three cannon tiers; Daniele: "give or take half way between current t2 and t3"):
# a LASER_BURST s burst killing at most LASER_KILL bodies split across the lines in range (the cannon's code
# path), then LASER_RECHARGE s. ~8 kills/s shown, below the door's 9.6/s.
static var LASER_COST := 200              # 40 shown
static var LASER_KILL := 96.0             # 19 shown per burst (-40 %, Daniele 2026-09-28: "laser tower is waaaay too powerful"; was 160)
static var LASER_BURST := 2.0
static var LASER_RECHARGE := 2.0
static var LASER_RANGE := 12.0            # metres from the node's centre: covers its piers + first module
# FORGE: +50 % attack to everything its owner deals AND the defence half (Daniele, 2026-09-27: "Attack +
# defence", "All garrisons -20 %"): while the owner holds a completed forge every one of its garrisons takes
# 20 % less damage (incoming / FORGE_DEFENCE). Forges do not stack.
static var FORGE_COST := 100              # 20 shown
const FORGE_DEFENCE := 1.25
const FORGE_BONUS_DEFAULT := 0.5
static var forge_bonus: float = FORGE_BONUS_DEFAULT  # live-tunable (Alpha 11: +50 on the 100 attack scale)
# MONSTER HUB (one per player): a monster costs MONSTER_COST units of the hub's garrison, then MONSTER_COOLDOWN s
# (charging from the hub's completion); it walks the fastest route to a node up to MONSTER_REACH bridges away at
# MONSTER_SPEED of the BRAWL unit speed, kicks every unit on its decks off the bridge (friend or foe), passes
# through the nodes on the way (their garrisons untouched; lines crossing those platforms are kicked too) and takes the end node empty (a friendly end node loses a tier instead). Nothing
# can shoot it; only a fall kills it.
static var MONSTER_HUB_COST := 150        # 30 shown
static var MONSTER_COST := 100            # 20 shown
static var MONSTER_COOLDOWN := 40.0          # Daniele, 2026-09-27: "change charge to 40 seconds" (was 90)
static var MONSTER_SPEED := 0.6           # x BRAWL_SPEED (~3.4 m/s)
static var MONSTER_REACH := 1             # bridges (plaza links don't count); Daniele 2026-09-28: "attack radius limited to 1 node" (was 3)
const MONSTER_R := 1.4                    # metres: the monster's reach along the deck (half a deck width)
const MONSTER_PLATFORM_R := 2.0           # metres: on a platform it crosses, bodies of lines in transit this close to its path are kicked
const MONSTER_FALL_TIME := 1.2            # seconds a falling monster tumbles before it is gone
const MONSTER_GONE := 0.5                 # seconds a "done" monster stays listed for the views, then goes
# LEGACY ALIASES (read-only, for scripts not yet on Structures 2.1 - tests/balance_probe.gd and old HUD
# lines): the one-tier laser seen through the old cannon names. Nothing in the rules reads them.
static var CANNON_COST := {1: 200, 2: 0, 3: 0}
static var CANNON_STATS := {1: {"recharge": 2.0, "kill": 160.0}, 2: {"recharge": 2.0, "kill": 160.0},
		3: {"recharge": 2.0, "kill": 160.0}}
static var CANNON_BURST := 2.0
static var CANNON_RANGE := 12.0
# NEUTRAL GARRISONS = half their tier's cap (Daniele, 2026-09-27: "neutral start at half their tier cap and
# refill up to that"): 15 / 30 / 60 / 100 shown, derived from CAPS (apply_balance re-derives them unless a
# preset names its own NEUTRAL_UNITS).
static var NEUTRAL_UNITS := neutral_from_caps(CAPS)


static func neutral_from_caps(caps: Dictionary) -> Dictionary:
	var out := {}
	for t in caps:
		out[t] = int(caps[t] / 2)
	return out


# frontline combat - PROVISIONAL: each side loses BASE + K * enemy units per second
static var FIGHT_RATE_BASE := 12.0
static var FIGHT_RATE_K := 0.08

const SEATS := {
	"A": Color("#2ee6ff"), "B": Color("#7dff5a"), "C": Color("#b48cff"),
	"D": Color("#ff5a5a"), "E": Color("#ffd23f"), "F": Color("#ff8fc8"),
}
const NEUTRAL := Color("#a9b8c8")
# relay state colours - the roster legend (BUILDING-PIECES.md B): the deck a state controls carries
# its colour on its edge lights, the relay tower's symbol glows in the current state's colour
# Relay states up to six a relay (Daniele 2026-09-28: states 4-6 fell back to white). The new ones (and s3, which read as s2
# for colour-blind players: dE 1.8) were picked so every state stays apart from the others of its relay kind under normal
# vision, protanopia, deuteranopia and tritanopia (Machado 2009 + CIEDE2000: >= 8.7 against its kind, 🧩 UI's
# states_search.py) and as far as a light can from the 20 seat colours (both palettes, COLOUR-BLIND's too: >= 5).
const STATE_COLORS := {
	"r1": Color("#ffd23f"), "r2": Color("#ff8c2a"), "r3": Color("#ff4f9a"), "retract": Color("#ff5a5a"),
	"r4": Color("#b88ae6"), "r5": Color("#ebff99"), "r6": Color("#bfffd9"),
	"s1": Color("#ffffff"), "s2": Color("#8fb3ff"), "s3": Color("#ffab73"),
	"s4": Color("#bfffd2"), "s5": Color("#ffbfd2"), "s6": Color("#e0ff99"),
	"m1": Color("#ff9ecf"), "m2": Color("#9be7c4"),
	"m3": Color("#cae68a"), "m4": Color("#ffbfff"), "m5": Color("#ae8ae6"), "m6": Color("#ff824d"),
	"warn": Color("#ff5a5a"), "build": Color("#ffd23f"),
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
static var FACTION_STATS := {
	"vex": {"speed": 1.15, "garrison": 0.90},
	"null": {},
	"bloom": {"speed": 0.90, "production": 1.10},   # 1.15 -> 1.10 (Daniele, 0.18.9 balance)
	"ember": {"attack": 1.10, "production": 0.90},   # 1.15 -> 1.10 (Daniele, 0.18.9 balance)
	"solar": {"health": 1.10, "garrison": 1.05, "speed": 0.90, "production": 0.90},
}

# BALANCE PRESETS (0.18.7 balance study - Daniele: "another thing we should revisit is balancing ... vat
# power up cost, production speed etc we need to balance better"). A preset is a PROPOSAL: OFF by default
# (BALANCE_PRESET ""), switched on only from the Debug panel or by tests/balance_probe.gd, and it travels
# with an online room's rules. Values are internal units (shown x SCALE). Only BALANCE_KEYS can change.
const BALANCE_KEYS := ["CAPS", "PROD", "HOME_TIER", "HOME_UNITS", "NEUTRAL_UNITS", "VAT_COST", "BUILD_SECONDS",
		"SWAP_COOLDOWN", "MACHINEGOON_COST", "MACHINEGOON_RATE", "MACHINEGOON_RANGE", "LASER_COST", "LASER_KILL",
		"LASER_BURST", "LASER_RECHARGE", "LASER_RANGE", "FORGE_COST", "MONSTER_HUB_COST", "MONSTER_COST",
		"MONSTER_COOLDOWN", "MONSTER_SPEED", "MONSTER_REACH", "VAT_RESTORE_COST", "FIGHT_RATE_BASE", "FIGHT_RATE_K", "FACTION_STATS",
		"forge_bonus"]
const BALANCE_PRESETS := {
	# The 0.18.7 balance study (tests/balance_probe.gd, BRAWL) proposed b187: neutrals 12/16/32/64 shown, Ember
	# attack 1.07, Bloom production 1.05, Vex garrison 0.95. Daniele (0.18.9) took the neutrals, set Ember and
	# Bloom to 1.10 and kept Vex. "legacy" restores the pre-0.18.9 numbers for comparison (Debug: Balance
	# DEFAULT / LEGACY): caps 30/40/80/160, T2 homes with 16, neutrals 6/12/24/40 and the 1.15 faction leans.
	"legacy": {
		"CAPS": {1: 150, 2: 200, 3: 400, 4: 800},
		"HOME_TIER": 2,
		"HOME_UNITS": 80,
		"NEUTRAL_UNITS": {1: 30, 2: 60, 3: 120, 4: 200},
		"FACTION_STATS": {"ember": {"attack": 1.15}, "bloom": {"production": 1.15}},
	},
}
static var BALANCE_PRESET := ""
static var _balance_base := {}                 # the default numbers, captured before the first change


static func apply_balance(preset: String, overrides: Dictionary = {}) -> void:
	## Back to the default numbers, then the named preset ("" = none), then `overrides` on top (the
	## balance probe's A/B cells). Dictionaries merge key by key (JSON "1" keys become tier ints), so
	## {"VAT_COST": {"1": 75}} changes only T1's upgrade. NEUTRAL_UNITS follows CAPS (half of each tier's
	## cap) unless the preset or the overrides name it.
	if _balance_base.is_empty():
		for k in BALANCE_KEYS:
			_balance_base[k] = _balance_get(k).duplicate(true) if _balance_get(k) is Dictionary else _balance_get(k)
		_balance_base["forge_bonus"] = FORGE_BONUS_DEFAULT   # not whatever the Debug slider holds now
	for k in BALANCE_KEYS:
		_balance_set(k, _balance_base[k].duplicate(true) if _balance_base[k] is Dictionary else _balance_base[k])
	BALANCE_PRESET = preset if BALANCE_PRESETS.has(preset) else ""
	var own_neutrals := false
	for layer in [BALANCE_PRESETS.get(BALANCE_PRESET, {}), overrides]:
		for k in layer:
			if k in BALANCE_KEYS:
				_balance_set(k, _balance_merge(_balance_get(k), layer[k]))
				own_neutrals = own_neutrals or k == "NEUTRAL_UNITS"
			else:
				push_warning("Rules.apply_balance: %s is not a balance key" % k)
	if not own_neutrals:
		NEUTRAL_UNITS = neutral_from_caps(CAPS)


static func _balance_merge(base, over):
	if base is Dictionary and over is Dictionary:
		var out: Dictionary = base.duplicate(true)
		for k in over:
			var key = int(k) if k is String and k.is_valid_int() and base.has(int(k)) else k
			out[key] = _balance_merge(base.get(key), over[k]) if base.has(key) else over[k]
		return out
	if base is int and (over is float or over is int):
		return int(round(over))
	if base is float and (over is float or over is int):
		return float(over)
	return over


static func _balance_get(k: String):
	match k:
		"CAPS": return CAPS
		"PROD": return PROD
		"HOME_TIER": return HOME_TIER
		"HOME_UNITS": return HOME_UNITS
		"NEUTRAL_UNITS": return NEUTRAL_UNITS
		"VAT_COST": return VAT_COST
		"BUILD_SECONDS": return BUILD_SECONDS
		"SWAP_COOLDOWN": return SWAP_COOLDOWN
		"MACHINEGOON_COST": return MACHINEGOON_COST
		"MACHINEGOON_RATE": return MACHINEGOON_RATE
		"MACHINEGOON_RANGE": return MACHINEGOON_RANGE
		"LASER_COST": return LASER_COST
		"LASER_KILL": return LASER_KILL
		"LASER_BURST": return LASER_BURST
		"LASER_RECHARGE": return LASER_RECHARGE
		"LASER_RANGE": return LASER_RANGE
		"FORGE_COST": return FORGE_COST
		"MONSTER_HUB_COST": return MONSTER_HUB_COST
		"MONSTER_COST": return MONSTER_COST
		"MONSTER_COOLDOWN": return MONSTER_COOLDOWN
		"MONSTER_SPEED": return MONSTER_SPEED
		"MONSTER_REACH": return MONSTER_REACH
		"VAT_RESTORE_COST": return VAT_RESTORE_COST
		"FIGHT_RATE_BASE": return FIGHT_RATE_BASE
		"FIGHT_RATE_K": return FIGHT_RATE_K
		"FACTION_STATS": return FACTION_STATS
		"forge_bonus": return forge_bonus
	return null


static func _balance_set(k: String, v) -> void:
	match k:
		"CAPS": CAPS = v
		"PROD": PROD = v
		"HOME_TIER": HOME_TIER = v
		"HOME_UNITS": HOME_UNITS = v
		"NEUTRAL_UNITS": NEUTRAL_UNITS = v
		"VAT_COST": VAT_COST = v
		"BUILD_SECONDS": BUILD_SECONDS = v
		"SWAP_COOLDOWN": SWAP_COOLDOWN = v
		"MACHINEGOON_COST": MACHINEGOON_COST = v
		"MACHINEGOON_RATE": MACHINEGOON_RATE = v
		"MACHINEGOON_RANGE": MACHINEGOON_RANGE = v
		"LASER_COST": LASER_COST = v
		"LASER_KILL": LASER_KILL = v
		"LASER_BURST": LASER_BURST = v
		"LASER_RECHARGE": LASER_RECHARGE = v
		"LASER_RANGE": LASER_RANGE = v
		"FORGE_COST": FORGE_COST = v
		"MONSTER_HUB_COST": MONSTER_HUB_COST = v
		"MONSTER_COST": MONSTER_COST = v
		"MONSTER_COOLDOWN": MONSTER_COOLDOWN = v
		"MONSTER_SPEED": MONSTER_SPEED = v
		"MONSTER_REACH": MONSTER_REACH = v
		"VAT_RESTORE_COST": VAT_RESTORE_COST = v
		"FIGHT_RATE_BASE": FIGHT_RATE_BASE = v
		"FIGHT_RATE_K": FIGHT_RATE_K = v
		"FACTION_STATS": FACTION_STATS = v
		"forge_bonus": forge_bonus = v
const FACTION_NAMES := {"vex": ["VEX", "BIOENGINEERS"], "null": ["NULL", "DATA CARTEL"], "bloom": ["VIRIDIAN", "BLOOM"],
		"ember": ["EMBER", "MAW"], "solar": ["SOLAR", "SHELLS"]}
const FACTION_TAGLINES := {"vex": "ADAPT. CONNECT. REDIRECT.", "null": "SAME SIGNAL. DIFFERENT TRUTH.",
		"bloom": "A WILDER TOMORROW.", "ember": "PRESSURE BREEDS PROGRESS.", "solar": "HOLD THE LIGHT."}
const FACTION_TRAITS := {"vex": ["Efficient routing", "Faster travel on owned connections."],
		"null": ["Obscured intel", "Hide precise counts from enemies."],
		"bloom": ["Biomass recovery", "Recover a portion of nearby losses."],
		"ember": ["Siege pressure", "Pressure defended structures."],
		"solar": ["Connected defense", "Protect connected friendly nodes."]}
# the approved ultimates (SKILLS-2.0-DRAFT sec5 / sec5.2, Daniele 2026-09-26); [name, one short line]
const FACTION_ULTIMATE := {"vex": ["Rewire", "faster lines, fire any 3 relays"],
		"null": ["Echo Split", "moving lines spawn jamming decoys"],
		"bloom": ["Superbloom", "every vat 1.5x for 12 s"],
		"ember": ["Core Meltdown", "sacrifice part of a line to gut a garrison"],
		"solar": ["Relay Aegis", "a node and its neighbours shielded"]}

# ------------------------------------------------------------------ SKILLS 2.0 (0.18.7)
# Daniele (0.18.7): "time to add armies presets and skills (its own new menu item where you select
# what skill each of your factions will use, follow the skill file from faction ultimates and ability
# pool)". Source: Docs/Game Design/Ooze Syndicate 2.0/01 Rules/SKILLS-2.0-DRAFT.md (draft 2, approved):
# 5 shared active skills + 5 shared map skills + one ultimate per faction. A loadout = the faction
# (fixes the ultimate) + 1 active + 1 map skill; everything unlocked for now.
# UNITS: the draft's numbers are SHOWN (Alpha 11 scale). Keys ending in "_shown" hold shown units; the
# Sim multiplies them by SCALE (sim units = shown x 5, as Rules.shown divides by 5). Seconds, speed and
# damage multipliers are scale-free. Every value is provisional (draft sec5.2: measure, then retune).
# "target" kinds (what the dock asks the player to tap):
#   own_line    one of your lines (horde id)            own_vat   one of your vat nodes (node id)
#   own_node    one of your nodes (node id)             deck      any deck, relay decks too (edge index)
#   fixed_deck  a deck no relay moves (edge index)      relay     any relay node (node id)
#   enemy_relay an enemy or neutral relay (node id)     vat_to_node [source node id, destination node id]
#   none        no target (cast at once)
const SKILLS := {
	# ---- active pool (combat), every map
	# 0.19.2 (Daniele, 2026-09-27): +75 % speed (was +50 %) and its units leave and enter doors twice as fast
	# ("door": the door-rate multiplier, Sim.door_mult)
	"surge": {"name": "Surge", "slot": "active", "cd": 28.0, "target": "own_line",
			"desc": "One of your lines moves 75 % faster for 8 s, and pours out of and into doors twice as fast.",
			"mult": 1.75, "door": 2.0, "dur": 8.0},
	"spore_burst": {"name": "Spore Burst", "slot": "active", "cd": 35.0, "target": "own_vat",
			"desc": "One vat produces 1.8x for 10 s, within its cap.", "mult": 1.8, "dur": 10.0},
	"fortify": {"name": "Fortify", "slot": "active", "cd": 35.0, "target": "own_node",
			"desc": "One node's garrison takes 1.65x less damage for 10 s.", "div": 1.65, "dur": 10.0},
	# Alpha 11 Scorch: 25 HP/s per unit caught (100 HP a unit), at most 1000 HP (10 units) per cast
	"scorch": {"name": "Scorch", "slot": "active", "cd": 32.0, "target": "deck",
			"desc": "A deck burns for 5 s: enemy lines on it lose units (up to 10).", "dur": 5.0,
			"rate": 0.25, "cap_shown": 10.0},
	# the decoy's length is the send fraction of the source vat (the fraction the player has set); no units spent
	"ghost_line": {"name": "Ghost Line", "slot": "active", "cd": 32.0, "target": "vat_to_node",
			"desc": "A decoy line that looks real and draws Laser tower and Machinegoon fire, but never fights.", "fraction": 0.5},
	# ---- map pool (network skills)
	"demolish": {"name": "Demolish", "slot": "map", "cd": 60.0, "target": "fixed_deck",
			"desc": "A deck collapses after 1.5 s; lines pour off it; it rebuilds after 20 s.", "warn": 1.5, "down": 20.0},   # warn 1.5 s: 0.19.2 (was 3 s)
	# speed x0.6 = 40 % slower; in SIEGE the stronger of this and the goo corridor slow applies (no stacking)
	"mire": {"name": "Mire", "slot": "map", "cd": 32.0, "target": "deck",
			"desc": "Enemy lines on one deck are 40 % slower for 8 s.", "slow": 0.6, "dur": 8.0},
	"anchor": {"name": "Anchor", "slot": "map", "cd": 45.0, "target": "deck",
			"desc": "A deck is locked for 10 s: no relay moves it, Demolish fails, half the Laser tower and Machinegoon kills on your lines.",
			"dur": 10.0, "cannon_mult": 0.5},
	"bypass": {"name": "Bypass", "slot": "map", "cd": 45.0, "target": "relay", "needs_relays": true,
			"desc": "A relay holds both of its states for 8 s.", "dur": 8.0},
	# target: the relay id fires it once (its normal warning); [relay id, "jam"] adds `jam` s to its cooldown
	"relay_hack": {"name": "Relay Hack", "slot": "map", "cd": 45.0, "target": "enemy_relay", "needs_relays": true,
			"desc": "Fire an enemy or neutral relay once, or jam it (+10 s cooldown).", "jam": 10.0},
	# ---- ultimates (one per faction; "cd" is the natural charge time, see ULT_CHARGE_TIME)
	# Rewire: while it lasts, the ultimate slot fires any relay once (target = relay id), `fires` at most
	"rewire": {"name": "Rewire", "slot": "ultimate", "faction": "vex", "cd": 120.0, "target": "none",
			"desc": "10 s: all your lines +50 % speed; fire up to 3 relays anywhere, enemy ones too.",
			"dur": 10.0, "mult": 1.5, "fires": 3},
	"echo_split": {"name": "Echo Split", "slot": "ultimate", "faction": "null", "cd": 120.0, "target": "none",
			"desc": "Up to 3 moving lines spawn decoy echoes; an echo landing on an enemy node stops its vat, Laser tower and Machinegoon for 8 s.",
			"echoes": 3, "disrupt": 8.0},
	# Daniele (0.18.7): "i don't like that super bloom can be casted only under attack but i like the cap"
	"superbloom": {"name": "Superbloom", "slot": "ultimate", "faction": "bloom", "cd": 120.0, "target": "none",
			"desc": "Every vat produces 1.5x for 12 s (at most 40 extra units).", "mult": 1.5, "dur": 12.0, "cap_shown": 40.0},
	# sacrifice `share` of the line (at least min_shown, no upper cap), kills_per defenders each (at most
	# cap_shown); a garrison at zero -> the rest of the line captures. The line must be attacking: headed for
	# a node that isn't yours or an ally's, and within `range` metres of it (or pouring in).
	"core_meltdown": {"name": "Core Meltdown", "slot": "ultimate", "faction": "ember", "cd": 120.0, "target": "own_line",
			"desc": "Sacrifice 25 % of an arriving line: 3 defenders die per unit; a garrison at zero is captured.",
			"share": 0.25, "min_shown": 4.0, "kills_per": 3.0, "cap_shown": 60.0, "range": 12.0},
	# the node + its adjacent own nodes: garrison damage / div, production x prod, the decks between them anchored
	# and any relay among them locked (nobody can fire it)
	"relay_aegis": {"name": "Relay Aegis", "slot": "ultimate", "faction": "solar", "cd": 120.0, "target": "own_node",
			"desc": "A node and its neighbours: 1.8x less garrison damage, +20 % production, decks locked, 12 s.",
			"div": 1.8, "dur": 12.0, "prod": 1.2},
}
const ACTIVE_SKILLS := ["surge", "spore_burst", "fortify", "scorch", "ghost_line"]
const MAP_SKILLS := ["demolish", "mire", "anchor", "bypass", "relay_hack"]
const FACTION_ULTIMATE_ID := {"vex": "rewire", "null": "echo_split", "bloom": "superbloom", "ember": "core_meltdown", "solar": "relay_aegis"}
# default loadouts per faction - a seat without a chosen loadout (and every AI seat) gets its faction's;
# between them the five cover every shared skill. "map_no_relays" replaces a relay skill on a map without
# relays (the Ooze Factory greys Bypass / Relay Hack out there, draft sec4).
const FACTION_LOADOUT := {
	"vex": {"active": "surge", "map": "relay_hack", "map_no_relays": "mire"},
	"null": {"active": "ghost_line", "map": "bypass", "map_no_relays": "demolish"},
	"bloom": {"active": "spore_burst", "map": "mire", "map_no_relays": "mire"},
	"ember": {"active": "scorch", "map": "demolish", "map_no_relays": "demolish"},
	"solar": {"active": "fortify", "map": "anchor", "map_no_relays": "anchor"},
}
# SKILLS START ON COOLDOWN (0.19.2, Daniele 2026-09-27: every active and map skill is on its full cooldown at the
# match start "as if they just got used" - otherwise e.g. the production skill is overpowered at second 1). The
# ultimate still charges from 0 (below).
const SKILLS_START_ON_COOLDOWN := true
# ULTIMATE CHARGE (draft sec1, locked): ~120 s of natural charge; enemy combat kills speed it up, but a
# charge never completes sooner than ULT_MIN_TIME after the match start or the last cast. No charge from
# neutrals, friendly fire, sacrifices, decoys, ultimate kills or falls. Each SHOWN enemy unit your troops,
# cannons or Scorch kill adds ULT_KILL_SECONDS of charge.
const ULT_CHARGE_TIME := 120.0
const ULT_MIN_TIME := 90.0
const ULT_KILL_SECONDS := 0.3
# Superbloom variant (Daniele, 0.18.7, "cap" chosen): "cap" = castable any time, extra production capped
# at SKILLS.superbloom.cap_shown; "under_attack" = no cap, castable only while one of your nodes is under
# attack (a hostile line headed for it, or hostile units on its platform).
static var SUPERBLOOM_MODE := "cap"
# ABILITIES ON/OFF (draft sec1, Alpha 11's match setting). Off: nothing casts. Default ON now that the skill
# dock, targeting and ARMIES menu ship; the switch is in 03 SETUP (offline) and the room lobby (the host's).
static var abilities_on := true
# AI casting rhythm: the least time between two of its casts, per level (it also only looks at its skills
# when it thinks, every Rules.AI_LEVELS period)
const AI_SKILL_GAP := {"Training": 24.0, "Casual": 16.0, "Standard": 9.0, "Veteran": 6.0, "Expert": 4.0}


static func skill_slot_id(faction: String, loadout: Dictionary, slot: String) -> String:
	## The skill id in `slot` ("active" / "map" / "ultimate") of a loadout for this faction.
	if slot == "ultimate":
		return FACTION_ULTIMATE_ID.get(faction, "echo_split")
	var d: Dictionary = FACTION_LOADOUT.get(faction, FACTION_LOADOUT["null"])
	var id := str(loadout.get(slot, d[slot]))
	var pool: Array = ACTIVE_SKILLS if slot == "active" else MAP_SKILLS
	return id if id in pool else str(d[slot])
# AI levels - Alpha 11's five (ai_balance.gd PROFILES, Daniele Alpha 17: "5 levels of difficulty with
# scaling aggressiveness"). Identical economy and combat at every level: only reaction time, how many
# nodes join an attack, how wrong its garrison estimates are and how often they refresh, the grace
# before it attacks players, the gap between offensives, how far ahead it forecasts growth, how
# randomly it picks among its best plans, how often it invests, the margin it wants, and relays:
# 0 never, 1 reacts to enemies on its decks, 2 also fires ahead (where lines will be when the deck
# moves), 3 also opens shorter routes to its targets. intel (0.18.10, Daniele 2026-09-27: "Veteran + Expert only"):
# 1 = its garrison estimates count the defender's forge (attack and the -20 % defence), Fortify / Aegis and faction
# stats (health, garrison, attack); 0 keeps the blind spot (the defender's health only). Teamwork (0.21.5, team
# modes only, see AI_TEAM_*): "teamwork" 0-3 how much it plays with its allies, "focus" the target-score bonus for the
# team's common enemy, "assist" the share of an ally's shortfall it covers when an allied node is attacked, "sync" the
# seconds it brings its next offensive forward to answer an ally's call. Training and Casual barely coordinate.
# Expert's coordination is 2 since 0.21.5 (Daniele 2026-09-28: the five levels must be "a nice scale for a new
# player"): a third, farther node in each offensive left it thin and made Expert win less vs Standard than
# Veteran (67 vs 72 %); with 2 the curve is strictly monotonic (tests/test_ai_curve.gd).
const AI_LEVELS := {
	"Training": {"period": 5.0, "coordination": 1, "error": 0.40, "observe": 10.0, "grace": 75.0, "attack_gap": 22.0,
			"forecast": 0.0, "choice": 4, "invest": 26.0, "margin": 1.5, "relays": 0, "intel": 0,
			"teamwork": 0, "focus": 0.0, "assist": 0.0, "sync": 0.0},
	"Casual": {"period": 4.0, "coordination": 1, "error": 0.32, "observe": 8.0, "grace": 50.0, "attack_gap": 17.0,
			"forecast": 0.2, "choice": 3, "invest": 22.0, "margin": 1.35, "relays": 0, "intel": 0,
			"teamwork": 1, "focus": 0.0, "assist": 0.3, "sync": 0.0},
	"Standard": {"period": 2.5, "coordination": 2, "error": 0.27, "observe": 7.0, "grace": 45.0, "attack_gap": 15.0,
			"forecast": 0.4, "choice": 3, "invest": 18.0, "margin": 1.2, "relays": 1, "intel": 0,
			"teamwork": 2, "focus": 10.0, "assist": 0.9, "sync": 3.0},
	"Veteran": {"period": 1.8, "coordination": 2, "error": 0.18, "observe": 4.0, "grace": 20.0, "attack_gap": 9.0,
			"forecast": 0.6, "choice": 2, "invest": 15.0, "margin": 1.1, "relays": 2, "intel": 1,
			"teamwork": 3, "focus": 16.0, "assist": 1.0, "sync": 6.0},
	"Expert": {"period": 1.3, "coordination": 2, "error": 0.12, "observe": 3.0, "grace": 12.0, "attack_gap": 6.5,
			"forecast": 0.75, "choice": 2, "invest": 12.0, "margin": 1.05, "relays": 3, "intel": 1,
			"teamwork": 3, "focus": 18.0, "assist": 1.0, "sync": 8.0},
}


# NUMBERS ON SCREEN (Daniele, Alpha 12 playtest: "big numbers don't look good - back to what Alpha 11
# had, with Alpha 12's amount of troops"): the sim runs at SCALE x Alpha 11 so hordes stay long, but
# every number the player sees is divided by SCALE - caps read 30/40/80/160, upgrades 10/20/30.
static func shown(units: float) -> int:
	return int(round(units / SCALE))


static func shown_f(units: float) -> float:
	return units / SCALE


static func stat(faction: String, key: String) -> float:
	## A faction's stat (1.0 when unknown) - no default dictionary per call (audit B3: called per unit per step).
	var fs = FACTION_STATS.get(faction)
	return float(fs.get(key, 1.0)) if fs != null else 1.0


# SEAT COLOURS for the current match (Daniele, Alpha 14: "implement faction colour selection").
# Filled by assign_colors() at match start: your pick, the rest from the palette; "faction" mode uses
# each seat's faction colour (Alpha 11 style); team modes give each team one hue, light and dark.
static var seat_colors: Dictionary = SEATS.duplicate()


static func seat_color(seat: String) -> Color:
	return seat_colors.get(seat, SEATS.get(seat, NEUTRAL))


# Player colours, Alpha 16 (Daniele: "in 2v2 and team matches the hue must be very recognisable from
# one player to another, and in FFA the colours very different - green, red, blue, purple"). FFA: each
# seat takes the next far-apart hue. Teams: each team is one family (cool / warm; in three-team modes
# cool, warm and violet) and every player in it still has a clearly different hue, so you read both
# "which team" and "which player".
const HUES := {
	"red": Color("#ff4545"), "green": Color("#6dff4a"), "blue": Color("#4a78ff"), "gold": Color("#ffd23f"),
	"purple": Color("#b36bff"), "cyan": Color("#2ee6ff"), "rose": Color("#ff5ab8"), "orange": Color("#ff9a2e"),
}
const FFA_ORDER := ["red", "green", "blue", "gold", "purple", "cyan", "rose", "orange"]
const TEAM_FAMILIES := [["cyan", "green", "blue"], ["red", "gold", "rose"]]   # 2v2: cyan+green vs red+gold
const TEAM_FAMILIES_3 := [["cyan", "green", "blue"], ["red", "gold", "orange"], ["purple", "rose"]]   # three-team modes (2v2v2)
const FAMILY_NAMES := {"cyan": "COOL", "red": "WARM", "purple": "VIOLET"}   # a family by its first hue


# ONLINE ROOM COLOURS (Daniele, 0.18.7: "my gf saw herself blue in her game and me i saw myself blue";
# his decision: the same colours on every screen). Every player picks a hue (a HUES key) in the room
# lobby, unique in the room; in team modes each team shares one family above and every teammate has a
# different hue of it. The host sends the seat -> hue map with the launch (Net.room_colours) and every
# browser applies it with use_colours, so nobody is recoloured on their own screen.
static func colour_families(team_count: int) -> Array:
	return TEAM_FAMILIES if team_count <= 2 else TEAM_FAMILIES_3


static func use_colours(keys: Dictionary) -> void:
	seat_colors = {}
	for s in keys:
		seat_colors[s] = HUES.get(str(keys[s]), SEATS.get(s, NEUTRAL))


static func _hue_gap(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d)


static func assign_colors(seats: Array, factions: Dictionary, human: String, choice: String, teams: Dictionary) -> void:
	## choice: a palette key ("A".."F") for your colour, or "faction".
	seat_colors = {}
	var mine: Color = FACTIONS[factions.get(human, "null")][1] if choice == "faction" else SEATS.get(choice, SEATS["A"])
	if not teams.is_empty():
		# your team takes the family closest to your pick (your pick first), every other team one of the
		# remaining families in seat order (a tie keeps the first family, as before)
		var team_ids := []
		for s in seats:
			if not (teams.get(s, 0) in team_ids):
				team_ids.append(teams.get(s, 0))
		var fams: Array = (TEAM_FAMILIES if team_ids.size() <= 2 else TEAM_FAMILIES_3).map(func(f): return f.map(func(k): return HUES[k]))
		var best := 0
		var best_gap: float = fams[0].map(func(c): return _hue_gap(c, mine)).min()
		for i in range(1, fams.size()):
			var g: float = fams[i].map(func(c): return _hue_gap(c, mine)).min()
			if g < best_gap:
				best_gap = g
				best = i
		var rest := []
		for i in range(fams.size()):
			if i != best:
				rest.append(fams[i])
		var own: Array = [mine] + fams[best].filter(func(c): return _hue_gap(c, mine) > 0.07)
		var family := {teams.get(human, 0): own}
		var r := 0
		for s in seats:
			if not family.has(teams.get(s, 0)):
				family[teams.get(s, 0)] = rest[r % rest.size()]
				r += 1
		var count := {}
		for s in ([human] + seats.filter(func(x): return x != human)):
			var t = teams.get(s, 0)
			var list: Array = family.get(t, rest[0])
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


# COLOUR-BLIND MODE (Daniele 2026-09-28: "yes add color blind mode in settings"; SETTINGS > DISPLAY, saved on the
# device). At match start every seat takes its colour from these palettes instead - on your screen only (an online
# room still sends the same hue keys to everyone). Picked so every pair a mode puts on one board stays apart under
# protanopia, deuteranopia and tritanopia (Machado 2009 simulation, CIEDE2000; 🧩 UI's cvd.py): free-for-all pairs
# >= 15 (the default palette's worst: 1.1, blue / purple), 2v2 / 3v3 teams >= 26 apart and teammates >= 14 (27 in
# 2v2), 2v2v2 teams >= 21 apart and teammates >= 11. You take the first colour (your team the first family).
const CB_FFA := [Color("#ff4019"), Color("#8cbcff"), Color("#ffd400"), Color("#d977a8"), Color("#19ffb2"), Color("#a666ff")]
const CB_TEAMS := [[Color("#9077d9"), Color("#00ffea"), Color("#77b8d9")], [Color("#d95f36"), Color("#ffff66"), Color("#d9b816")]]
const CB_TEAMS_3 := [[Color("#ff4000"), Color("#d97790")], [Color("#8c8cff"), Color("#40ffef")], [Color("#ffe28c"), Color("#ffff00")]]
static var settings_path := "user://settings.cfg"   # tests point this elsewhere ([display] colour_blind)
static var _colour_blind := -1                        # -1 until read


static func colour_blind() -> bool:
	if _colour_blind < 0:
		var c := ConfigFile.new()
		_colour_blind = 1 if c.load(settings_path) == OK and bool(c.get_value("display", "colour_blind", false)) else 0
		if "--colour-blind" in OS.get_cmdline_user_args():   # screenshots: on for this run, nothing saved
			_colour_blind = 1
	return _colour_blind == 1


static func set_colour_blind(on: bool) -> bool:
	## Saved next to the other settings (PerfProfile / Sfx keep their own sections). False when nothing could be saved.
	_colour_blind = 1 if on else 0
	var c := ConfigFile.new()
	c.load(settings_path)
	c.set_value("display", "colour_blind", on)
	return c.save(settings_path) == OK


static func apply_colour_blind(seats: Array, teams: Dictionary, human: String) -> void:
	## After assign_colors / use_colours: COLOUR-BLIND MODE's palettes for this match's seats (nothing when it's off).
	if not colour_blind():
		return
	var order := [human] if human in seats else []
	for s in seats:
		if not (s in order):
			order.append(s)
	if teams.is_empty():
		for i in range(order.size()):
			var c: Color = CB_FFA[i % CB_FFA.size()]
			seat_colors[order[i]] = c if i < CB_FFA.size() else c.darkened(0.35)
		return
	var team_ids := []                                 # in order of first seat: yours first
	for s in order:
		if not (teams.get(s, 0) in team_ids):
			team_ids.append(teams.get(s, 0))
	var fams: Array = CB_TEAMS if team_ids.size() <= 2 else CB_TEAMS_3
	var count := {}
	for s in order:
		var t = teams.get(s, 0)
		var fam: Array = fams[team_ids.find(t) % fams.size()]
		var i: int = count.get(t, 0)
		seat_colors[s] = fam[i % fam.size()] if i < fam.size() else (fam[i % fam.size()] as Color).darkened(0.35)
		count[t] = i + 1


static func state_color(state: String) -> Color:
	return STATE_COLORS.get(state, Color.WHITE)


static func span(modules: int) -> float:
	## Centre-to-centre distance of an honest edge of `modules` deck modules.
	return 2.0 * (R + PIER) + modules * S


static func heading(d: Vector3) -> float:
	## Kit rotation.y for a piece whose local +X should point along d (kit authored in Blender).
	return atan2(-d.z, d.x)


# ================================================================ PROGRESSION (Leaderboard, progression, and currency session)
# XP / level, the two currencies, unlock prices and the challenge pools (01 Rules/PROGRESSION-DESIGN.md §9;
# Daniele 2026-09-27: SCRAP / SYNDICATE CHIPS, a skill costs 1 250 SCRAP, small chips from weeklies and levels,
# Surge + Demolish free, 140 SCRAP per tutorial lesson, 25 wins for a faction vat, easy AI pays XP only, resets
# 00:00 UTC). Scripts/progression.gd applies them; nothing here changes play.
const CURRENCY_NAMES := {"soft": "SCRAP", "premium": "SYNDICATE CHIPS"}
const CURRENCY_SHORT := {"soft": "SCRAP", "premium": "CHIPS"}
# Everything unlocked while testing (Daniele, 2026-09-27: "all open until lock switch"). false = the locks are live.
# The Graduate vat stays locked until the tutorial is done either way (TUTORIAL-DESIGN §7).
const UNLOCK_ALL_TESTING := true
const PROGRESSION := {
	"finish_soft": 20, "finish_xp": 100,          # any finished match (not left early; tutorial lessons excluded)
	"win_soft": 20, "win_xp": 50,                 # on top of finishing
	"first_win_soft": 100, "first_win_xp": 200,   # the first win of the UTC day
	"full_pay_ai": ["Veteran", "Expert"],         # vs AI below these a match pays XP only (no SCRAP); only these AI wins
	                                              # count toward a faction vat (online wins always count)
	"level_base": 800, "level_step": 100,         # level n -> n + 1 needs level_base + level_step * (n - 1) XP
	"level_soft": 100,                            # every level-up
	"level_premium_every": 5, "level_premium": 25, # every 5th level also pays a few chips
	"daily_count": 3, "daily_soft": 50, "daily_xp": 150,
	"weekly_count": 3, "weekly_soft": 250, "weekly_xp": 500, "weekly_premium": 10,
	"tutorial_lesson": 140,                       # lessons 1-9, first completion: 9 x 140 = 1 260 = a 3rd skill
	# a campaign mission's one-off SCRAP (3 stars + its optional objective in one run), by mission kind (proposal,
	# CAMPAIGN-DESIGN §5a; was Campaign.REWARD)
	"campaign_reward": {"main": 150, "duel": 200, "side": 200, "finale": 300},
	"faction_vat_wins": 25,
	"free_skills": ["surge", "demolish"],         # the two the tutorial teaches; every other shared skill is bought
	"ledger_keep": 200,                           # recent wallet entries kept on the device (the PROFILE history)
}
# TUTORIAL (tutorial.gd, coach_overlay.gd): L9's scripted relay-kill push (TutorialDirector._tick_match) - the opening
# card closes itself after card_close s; the push waits for the rival to hold push_min_shown units (shown); every rival
# garrison of muster_min_shown+ gathers on the muster node, which launches after muster_wait s at the latest (the push
# is given up after launch_wait s); a push not decided after push_wait s is a miss.
const L9_MATCH := {"card_close": 12.0, "push_min_shown": 20.0, "muster_min_shown": 3.0, "muster_wait": 25.0,
		"launch_wait": 40.0, "push_wait": 45.0}
const TUTORIAL_HANDLER_FPS := 20.0   # the coach card's 3D handler renders this often (its own SubViewport; audit B4)
# Prices by item kind ({} or a missing currency = not sold for it). Skills never for chips (no power for money).
const PRICES := {
	"skill": {"soft": 1250},
	"vat_faction": {"soft": 4000, "premium": 400},
	"vat_line": {"soft": 3000, "premium": 300},    # Bio-Pod, Crystal, Distillery, Hive, Reactor (all tiers)
	"structure": {"soft": 1500, "premium": 150},   # a Machinegoon / Laser / Forge / Monster hub look
	"monster_alt": {"soft": 2000, "premium": 200},
}
# Challenge pools. stat: what a match adds (Progression.match_stats); target: how much; "faction": true = the text's
# %s is a faction the day's seed picks (win_as). Texts use the tutorial's standard vocabulary (TUTORIAL-SCRIPT.md).
const CHALLENGES := {
	"daily": [
		{"id": "finish3", "stat": "finish", "target": 3, "text": "Finish 3 matches"},
		{"id": "win2", "stat": "win", "target": 2, "text": "Win 2 matches"},
		{"id": "win_as", "stat": "win_as", "target": 1, "faction": true, "text": "Win a match as %s"},
		{"id": "capture15", "stat": "captures", "target": 15, "text": "Capture 15 nodes"},
		{"id": "fire5", "stat": "relay_fires", "target": 5, "text": "Fire relays 5 times"},
		{"id": "drop40", "stat": "void_drops", "target": 40, "text": "Drop 40 enemy units into the void with relays"},
		{"id": "kick40", "stat": "monster_kicked", "target": 40, "text": "Kick 40 enemy units off the decks with your monster"},
		{"id": "skills8", "stat": "skills", "target": 8, "text": "Use 8 skills"},
		{"id": "win_relay", "stat": "win_relay_map", "target": 1, "text": "Win on a map with relays"},
		{"id": "win_home", "stat": "win_home_kept", "target": 1, "text": "Win without losing your home"},
	],
	"weekly": [
		{"id": "win10", "stat": "win", "target": 10, "text": "Win 10 matches"},
		{"id": "capture80", "stat": "captures", "target": 80, "text": "Capture 80 nodes"},
		{"id": "fire30", "stat": "relay_fires", "target": 30, "text": "Fire relays 30 times"},
		{"id": "drop250", "stat": "void_drops", "target": 250, "text": "Drop 250 enemy units into the void with relays"},
		{"id": "kick250", "stat": "monster_kicked", "target": 250, "text": "Kick 250 enemy units off the decks with your monster"},
		{"id": "factions3", "stat": "win_factions", "target": 3, "text": "Win with 3 different factions"},
		{"id": "win_home5", "stat": "win_home_kept", "target": 5, "text": "Win 5 matches without losing your home"},
	],
}

# --- PROGRESSION: telemetry, crash reports, privacy (01 Rules/TELEMETRY-PRIVACY-DESIGN.md; Alpha 21) ---
# consent (Daniele, 2026-09-28): "opt_in_eu_uk" = the switch starts OFF for players in the EU / EEA / UK / Switzerland
# (time zone / locale; unsure = EU) and ON elsewhere; "opt_out" = ON for everyone. Nothing leaves the device before the
# privacy notice has been answered, and never while the switch is OFF.
const TELEMETRY := {
	"consent": "opt_in_eu_uk",
	"queue_max": 200,           # events kept on the device (oldest dropped)
	"batch": 50,                # events per upload (the telemetry function's limit)
	"event_bytes": 2048,        # one event's JSON
	"flush_s": 120.0,           # upload every 2 min (and at match end / back in the menu)
	"crashes_per_run": 10,      # distinct crash reports one run may queue
	"match_logs_kept": 20,      # user://telemetry/match_*.json kept on the device
	"menu_perf_s": 60.0,        # phones: one menu perf event per minute in the menu
	"long_frame_ms": 50,        # a frame this long counts as a long frame (heat / stutter proxy)
	"retention_days": 60,       # shown in the notice; the purge is the database's (purge_telemetry)
	"crash_retention_days": 90,
	"contact": "info@oozesyndicate.com",   # Daniele, 2026-09-28 (the domain is to be registered)
	"policy_url": "https://oozesyndicate.com/privacy.html",   # the domain move (2026-09-28)
	"min_age": 13,
}
# --- end PROGRESSION: telemetry ---

# --- Alpha 21 OPT-RENDER: render budget (tests/perf_check.tscn) ---
# The heaviest real map (M-39: 18 nodes, 31 bridges, relays) at a busy moment (AI vs AI, fast-forwarded to
# PERF_CHECK_FF, then PERF_CHECK_SECONDS of real play) in the PHONE profile at 1266x585 must stay under these
# (the frame's draw calls / primitives / objects, 2D HUD included; max over the last 3 s). Before Alpha 21's
# batching M-39 drew ~1,090 draw calls / 655 k primitives / 1,350 objects; batched ~440 / 347 k / 700, of which
# the HUD is ~160 draw calls. The spec's targets (< 400 / < 300 k / < 800) need the lighter kit (OPT-MESH) for
# the primitives and fewer HUD draw calls: lower these as those land.
const PERF_CHECK_MAP := "res://maps4/M-39-circuit-warren.json"
const PERF_CHECK_FF := 120.0
const PERF_CHECK_SECONDS := 10.0
const PERF_BUDGET_DRAW_CALLS := 500
const PERF_BUDGET_PRIMITIVES := 400000
const PERF_BUDGET_OBJECTS := 800
# --- end OPT-RENDER ---

# --- PERF PASS (2026-09-28): view numbers ---
const RELAY_ARC_STEPS := 48.0           # a relay's cooldown / warning arc is rebuilt once per 1/48 of its sweep (Fx._relay)
# tests/perf_check.tscn -- --full: the FULL profile's own budget (desktop: shadows, the HD kit) on the 2v2 map Daniele's
# telemetry drew the most on (0.22.0: M-57 p95 740 draw calls on his desktop), at 1600x900; measured 2026-09-28 at the
# check's moment: ~465 draw calls / 408 k primitives / 1,190 objects (M-57 FULL, the Last Stand: ~590 / 457 k / 1,250).
const PERF_CHECK_FULL_MAP := "res://maps4/M-57-relay-quarry.json"
const PERF_BUDGET_FULL_DRAW_CALLS := 600
const PERF_BUDGET_FULL_PRIMITIVES := 550000
const PERF_BUDGET_FULL_OBJECTS := 1400
# --- end PERF PASS ---

# --- HUD pass (2026-09-28, Daniele's "option A": no notification box - each message where it belongs) ---
# HudCallouts: a short callout at the node / deck / spot it is about (Fx.floater's look + a small icon), one per
# place, an edge arrow when that place is off screen; sizes in canvas units x Hud.ui_scale, phones floored in real
# points (UiKit.pt_per_px). Seconds include the fade.
const HUD_CALLOUT_LIFE := 2.6          # a map callout (monster, forge, handover, eject, a refused order at its node)
const HUD_CALLOUT_POP := 0.16          # pop-in
const HUD_CALLOUT_FADE := 0.45         # fade-out at the end of its life
const HUD_CALLOUT_RISE := 14.0         # canvas units it drifts up over its life
const HUD_CALLOUT_FONT := 21           # desktop font (x ui_scale)
const HUD_CALLOUT_MIN_PT := 14.0       # phones: never smaller than this on the glass
const HUD_CALLOUT_LIFT := 3.0          # m above the node's centre it points at
const HUD_CALLOUT_ARROW := 15.0        # the off-screen edge arrow's length (x ui_scale)
const HUD_REFUSAL_LIFE := 1.5          # a skill-dock refusal, just above the slot that was tapped
const HUD_REFUSAL_FONT := 17
const HUD_REFUSAL_MIN_PT := 12.0
const HUD_BANNER_LIFE := 1.6           # the match-start banner (map, who you are, the dock's start note)
const HUD_BANNER_FONT := 30
const HUD_LINE_LIFE := 2.4             # a line with no place of its own (tutorial / campaign / debug), under the top bar
const HUD_LS_PULSE := 4.5              # the Last Stand status line pulses and explains the method this long
const HUD_DOCK_MIN_PT := 11.0          # the dock's ACTIVE / MAP / ULTIMATE and status words on a phone (iPhone sweep)
const HUD_DOCK_PHONE_W := 212.0        # the dock slot's width on a phone (desktop: SkillDock.SLOT_SIZE.x) for those words
const HUD_NAME_MAX := 12               # characters of a player's name before it is cut with an ellipsis
# --- end HUD pass ---

# --- SOUND (first pass: Set 4 "Mix 2+3", alternate 1 - Daniele's pick in the sound demo, 2026-09-28; sfx.gd) ---
# Started from the numbers the demo (branch sound-demo) was heard with. Throttle: one event type plays at most every
# SOUND_GAP s (real time, so a busy map stays readable and a 2x speed never doubles the noise); the alarms 1 s, the win
# 2 s. Match feel (Daniele's phone test, 2026-09-28: "right now it's obnoxious (but a good starting point)"): the
# frequent battle noise (SOUND_BED) is a soft bed under the cues - one every 0.6-1 s at most (was 0.2-0.45), 4-6 dB
# quieter, a little pitch spread, only for lines of your side or on screen, and held off for SOUND_DUCK s after a cue.
const SOUND_GAP := {"send": 0.8, "fight": 0.9, "hit": 0.7, "capture": 0.2, "node_lost": 0.25, "rival_capture": 0.8, "upgrade": 0.3,
		"build": 0.3, "laser": 0.6, "machinegoon": 1.0, "skill": 0.3, "fall": 0.6, "collapse_warning": 0.3,
		"collapse": 0.3, "last_stand": 1.0, "very_last_stand": 1.0, "eliminated": 0.5, "win": 2.0}
const SOUND_GAP_DEFAULT := 0.3            # an event not listed above (monsters, relays)
const SOUND_VOICES := 12                  # match voices; all busy: a new sound is dropped, except SOUND_PRIORITY's
const SOUND_PRIORITY := ["win", "last_stand", "very_last_stand", "eliminated", "collapse"]   # these take the oldest voice
const SOUND_PRIORITY_VOICES := 2          # spare voices only SOUND_PRIORITY may use (so they rarely have to cut one off)
const SOUND_UI_VOICES := 3                # menu taps (they outlive a scene reload: DEPLOY's confirm keeps playing)
const SOUND_UI_GAP := 0.06                # s between two UI sounds (a double tap is one sound)
# Per event its level in dB (the demo's mix; the VOLUME setting scales them all on the Sfx bus).
# Match feel, with music (Daniele: "the sounds are too overpowering vs the background music, make them less loud and
# that they fade more seamlessly"): the bed 6 dB under the demo's mix, every cue 3 dB under it.
const SOUND_VOL := {"send": -16.0, "fight": -14.0, "hit": -15.0, "capture": -7.0, "node_lost": -7.0, "rival_capture": -18.0, "upgrade": -8.0,
		"build": -9.0, "laser": -14.0, "machinegoon": -22.0, "monster_launch": -7.0, "monster_stomp": -7.0,
		"monster_take": -7.0, "monster_fall": -7.0, "skill": -8.0, "relay_warning": -12.0, "relay_switch": -10.0,
		"fall": -14.0, "collapse_warning": -9.0, "collapse": -6.0, "last_stand": -3.0, "very_last_stand": -3.0,
		"eliminated": -6.0, "win": -3.0}
const SOUND_UI_VOL := {"tap": -14.0, "confirm": -9.0, "back": -12.0, "error": -9.0}
const SOUND_BED := ["send", "fight", "hit", "machinegoon", "laser", "fall", "rival_capture"]   # the frequent battle noise (the soft bed)
const SOUND_BED_PITCH := 0.06             # +- pitch spread of a bed sound (the same sample never repeats identically)
const SOUND_DUCK := 0.6                   # s the bed stays quiet after one of SOUND_CUES
const SOUND_CUES := ["capture", "node_lost", "last_stand", "very_last_stand", "eliminated", "win", "collapse"]
# The envelope (Sfx._play): every match sound fades in over SOUND_FADE_IN s from SOUND_ATTACK_DB under its level (no click
# on), and its last SOUND_FADE_OUT s fade SOUND_TAIL_DB down (no cut off); a repeat of an event still sounding fades the
# old one out over SOUND_XFADE s on its own voice instead of restarting it.
const SOUND_FADE_IN := 0.02
const SOUND_FADE_OUT := 0.22
const SOUND_XFADE := 0.12
const SOUND_ATTACK_DB := 18.0
const SOUND_TAIL_DB := 40.0
# Buses (Sfx.ensure_buses, made at startup): "Sfx" and "Music" both under Master - every sound plays on Sfx, the
# soundtrack on Music (music.gd). SOUND / VOLUME drive the Sfx bus, MUSIC / MUSIC VOLUME the Music bus (Master stays
# 0 dB), so the two are independent. SOUND_MUSIC_BUS_DB is only the level the bus is made at: Music sets its level.
const SOUND_SFX_BUS := "Sfx"
const SOUND_MUSIC_BUS := "Music"
const SOUND_SFX_BUS_DB := 0.0
const SOUND_MUSIC_BUS_DB := 0.0
# SETTINGS > DISPLAY > AUDIO: VOLUME's choices (percent of full level; silence is SOUND OFF) and the first-run default.
# Match feel: 30 % (-10.5 dB on the Sfx bus; the demo played at 50 %). A level the player already saved is kept.
const SOUND_VOLUME_STEPS := [15, 30, 60, 100]
const SOUND_VOLUME_DEFAULT := 30
# --- end SOUND ---

# --- MUSIC (the soundtrack, music.gd: the spectate demo's slots and mix, branch sound-demo 912ee68, Daniele 2026-09-28) ---
# Cyberpunk Music Pack by SmellyCatCafe (smellycatcafe.itch.io; bought, "free and commercial projects, crediting
# appreciated"). The tracks are NOT in git (public repo): tools/copy_music.py copies the ones below into
# assets/audio/music/ before an import / export (BUILD-LOG sec10); Web gets them in music.pck ("Web Music"), fetched
# the first time music is needed. Slot -> its tracks (file names without .ogg). BATTLE is a playlist (the next track
# each time one ends or a match starts); a one-track slot loops with the playlist crossfade; VICTORY / DEFEAT are
# stingers - the track's first MUSIC_STINGER_LEN s, the last MUSIC_STINGER_FADE of them fading, cut into the file by
# tools/copy_music.py (it reads these numbers from here) - played once at the match's end.
const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_PACK := "music.pck"                  # web: beside index.pck, fetched once (Music._fetch_pack)
const MUSIC_TRACKS := {"MENU": ["Cyber Sunrise"], "BATTLE": ["Drone Patrol", "Neon Street", "Synth Syndicate"],
		"LAST STAND": ["Midnight Hack"], "VERY LAST STAND": ["Boss Battle"],
		"VICTORY": ["Ending Theme (stinger)"], "DEFEAT": ["Game Over (stinger)"]}
const MUSIC_STINGERS := ["VICTORY", "DEFEAT"]    # played once, never looped
const MUSIC_STINGER_LEN := 7.0                   # s of the source track a stinger keeps (tools/copy_music.py) ...
const MUSIC_STINGER_FADE := 1.5                  # ... its last 1.5 s fading out
const MUSIC_ENCODE_KBPS := 80                    # tools/copy_music.py --encode: Vorbis bitrate for the web (the pack's own copy: 96)
# Crossfades (equal power), s: from silence, MENU <-> BATTLE, into (Very) Last Stand (the alarm leads), BATTLE track to
# track and a slot looping, into a stinger.
const MUSIC_XFADE_START := 0.5
const MUSIC_XFADE_PHASE := 1.5
const MUSIC_XFADE_LAST_STAND := 1.0
const MUSIC_XFADE_PLAYLIST := 2.0
const MUSIC_XFADE_STINGER := 0.4
# The mix: the demo heard the music at 0 dB against the SFX table (Rules.SOUND_VOL) under one master volume. The
# settings are separate now, so the Music bus sits MUSIC_LEVEL_DB under full: at the defaults (SOUND 30 %, MUSIC 60 %)
# the music is exactly where the demo put it against the sounds (30 % vs 60 %: -6 dB).
const MUSIC_LEVEL_DB := -6.0
# Ducking under the big cues (Sfx plays one of these: Music.duck): the music MUSIC_DUCK_DB down over MUSIC_DUCK_IN s,
# held MUSIC_DUCK_HOLD s after the last one, back up over MUSIC_DUCK_OUT s.
const MUSIC_DUCK_EVENTS := ["capture", "last_stand", "very_last_stand", "win"]
const MUSIC_DUCK_DB := -2.0
const MUSIC_DUCK_IN := 0.3
const MUSIC_DUCK_HOLD := 0.5
const MUSIC_DUCK_OUT := 0.8
# SETTINGS > DISPLAY > AUDIO (and PAUSE > SETTINGS): MUSIC ON / OFF and MUSIC VOLUME (percent), user://settings.cfg
# [audio] music_on / music_volume. First run: ON, 60 %.
const MUSIC_VOLUME_STEPS := [15, 30, 60, 100]
const MUSIC_VOLUME_DEFAULT := 60
const MUSIC_ON_DEFAULT := false           # HOTFIX 0.22.2 (Daniele 2026-09-29: the music made phones lag and OFF did not stop it): OFF until switched on
const MUSIC_CREDIT := "Music: Cyberpunk Music Pack by SmellyCatCafe (smellycatcafe.itch.io)"
# --- end MUSIC ---

# --- MATCH FEEL (2026-09-28, Daniele's phone test; fx.gd, combat_fx.gd, hud.gd, sfx.gd, warmup.gd) ---
# Last Stand ring (Fx._last_stand_warning; "too in your face since we have already the alert tag"): the alert tag
# (HudOverlay's danger symbol + countdown) and the pulsing status line carry the warning; the ring is a thin, faint
# outline breathing slowly round the node that drops NEXT only, and only that node's decks blink.
static var ls_ring_loud := false         # debug: the old ring - thick, bright, blinking faster toward the drop, on every warned node
const LS_RING_ALPHA := 0.3               # the thin ring's peak opacity
const LS_RING_BREATHE := 2.4             # rad/s of its slow breath (0.6..1 of LS_RING_ALPHA; the next node's decks blink with it)
const LS_RING_R := 0.35                  # m beyond the platform radius
const LS_FRAGMENTS := 18                 # fall pieces a dropping node's decks break into (Fx._collapse; at least 1 a module; was 6 a module)
# Under attack (CombatFx._alarm; "we need an animation that shows when a building is under attack"): YOUR node while
# an enemy line pours in at its door - the rim on the side it comes from flickers red and short sparks jump there;
# an ally's node the same, dimmer (team modes). On the platform's lip, never over the count badge (beside the node).
const ALARM_COLOR := Color("#ff3b30")
const ALARM_ARC := 0.34                  # fraction of the rim lit, centred on the attack's side
const ALARM_R := 1.2                     # m beyond the platform radius: the arc's outer edge (just outside the lip's bumpers)
const ALARM_INNER := 0.9                 # its inner edge, x its outer radius (a band ~0.7 m wide)
const ALARM_POWER := 1.5                 # your node's brightness (additive)
const ALARM_ALLY := 0.45                 # an ally's node: x this (the arc and its sparks)
const ALARM_FLICKER := 3.5               # Hz: bright / dim steps while it pours in
const ALARM_DIM := 0.3                   # the dim step's brightness
const ALARM_HOLD := 0.6                  # s the cue fades out after the last unit poured in
const ALARM_SPARK_GAP := 0.45            # s between two spark bursts at one node (the throttle)
const ALARM_SPARKS := 7                  # sparks per burst
# Contest ring (CombatFx._progress, shaders/contest_ring.gdshader; "the ring should give me an idea" of how close the
# attack is, "no exact numbers"): the attacker's colour sweeps clockwise from the top of the ring over the share of the
# fight it is winning - attackers pouring in plus those within CONTEST_REACH m of the door, x the Sim's exchange rate,
# against the garrison left; 0 = holds, 1 = taken. Eased at CONTEST_EASE 1/s so it creeps, never jumps.
const CONTEST_REACH := 16.0
const CONTEST_EASE := 3.0
const CONTEST_TRACK := 0.28              # the garrison's (unswept) track brightness
const CONTEST_TICKS := 4                 # faint marks on the track (quarters; 0 = none)
# First-use hitches ("lags only on first time you send and first time you enter a tower"): Warmup draws every effect
# material once, tiny, at match start (behind the VERSUS card), so the GL shader compiles happen there.
const WARMUP_FRAMES := 3                 # frames the warm-up pieces stay drawn
# Badges during camera motion (the Last Stand zoom "still slows the game down"): Hud._layout_badges scores 24 spots x 3
# reaches against every platform, deck and badge (~10 ms a frame on M-39 on desktop, every frame of the 1.5 s zoom);
# while the camera moves the badges now follow their platforms' screen position and scale, and the full layout runs
# once the camera has held still this many frames.
const BADGE_SETTLE_FRAMES := 2
# --- end MATCH FEEL ---
