class_name Calm
extends RefCounted
## CALM PASS (Daniele on staging 0.24.1, 2026-11-12: "all colors i feel are way too bright and compete too much for attention,
## also all looks messy"). Three dev variants, one flag each; with no flag the game is exactly 0.24.1:
##   --calm=a  WORLD ONLY: the fog darker and neutral (a faint owner tint at most, no cyan + red -> green mix), the floor's
##             transport tubes dimmed to a hint, the backdrop darker. Board, units and HUD untouched.
##   --calm=b  A + LABEL DIET: neutral garrison badges smaller and grey, the tier chip folded into the badge, IN / FERRY /
##             timer tags only while they matter, redundant badge sub lines (unit dots, PAUSED %) dropped where another
##             readout already says it (see calm-pass report for where each readout went).
##   --calm=c  B + COLOUR DISCIPLINE: player colour on units, owned-node rims and the HUD score only; structures, walkways,
##             decks and tubes neutral.
## Pure view: no sim state, no net traffic, never changes a rule.

static var level := _arg()


static func _arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--calm="):
			var v := a.substr(7).to_lower()
			return v if v in ["a", "b", "c"] else ""
	return ""


static func world() -> bool:
	return level != ""


static func labels() -> bool:
	return level == "b" or level == "c"


static func colour() -> bool:
	return level == "c"


# --- A: world ---
# Daniele 2026-11-12 (via UI designer 4): the world is already "gray and boring ... should be more alive and happy, not grim" -
# so A does NOT darken or grey the floor / backdrop; calm comes from hierarchy. A only drops the cyan + red -> green fog mix
# ("a colour not belonging to anything") and dims the floor tubes. The world's mood is round 24 MOOD FRAMES (designer).
const FOG_GRAY := FogLead.FOG_GRAY            # the fog's own 0.24.1 neutral tone (unchanged), no seat hues mixed in
const FOG_OWNER_TINT := 0.18                  # a faint tint of the LEADING seat only, by its lead (tie = neutral; 0.24.1: the hue mix)
const LEAD_MAX_TINT := 0.18                   # FogLead's air tint at a full lead (0.24.1: 0.35)
const TUBE_GOO_DIM := 0.18                    # transport-tube goo (0.24.1: 0.6)
const TUBE_GLOW := 0.12                       # the tube glass's own glow (0.24.1 shader default 0.42)
const TUBE_SAT := 0.35                        # how much colour the tube goo keeps (1 = the seat colour)


# --- B: labels ---
const NEUTRAL_BADGE_K := 0.78                 # a neutral garrison's badge, x its size (box and words)
const NEUTRAL_BADGE_MOD := Color(0.62, 0.64, 0.68, 0.85)   # its frame, greyed
const NEUTRAL_INK := Color(0.72, 0.74, 0.78)  # its words
const IN_TAG_S := 5.0                         # a ferry lane's "IN n" shows only in its last n seconds


# --- C: goo = the approved units' body tones, neon = the only fully bright colour (Daniele with UI designer 4, 2026-11-12:
# "the goo is the body, the neon is the signal"; median body samples from R1G-lineup-APPROVED, lifted ~12 % for the vat)
const GOO_TONE := {"vex": Color("#267193"), "ember": Color("#E76414"), "solar": Color("#E4B14E"), "bloom": Color("#7DAF2E"), "null": Color("#A91A56")}
const GOO_LIFT := 0.12
static var factions: Dictionary = {}          # seat -> faction (main sets it once the Sim is set up)


static func goo(seat: String, fallback: Color) -> Color:
	## C only: a seat's goo in its faction's body tone; anything else keeps `fallback`.
	if not colour() or seat == "":
		return fallback
	var f := str(factions.get(seat, ""))
	if not GOO_TONE.has(f):
		return fallback
	return (GOO_TONE[f] as Color).lightened(GOO_LIFT)


static func desat(c: Color, keep: float) -> Color:
	## `c` with only `keep` (0..1) of its saturation, same value.
	return Color.from_hsv(c.h, c.s * keep, c.v, c.a)
