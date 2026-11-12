class_name GooTone
extends RefCounted
## GOO = BODY, NEON = SIGNAL (Daniele 2026-11-12 on the calm pass: "at the very least should tone down goo color as per the new
## models"; with UI designer 4: "the goo is the body, the neon is the signal"). Every place goo shows - transport tubes, pits,
## the conquest hologram's fill, vat liquid and ooze, swarms / rivers / falling bodies, the SEND tank, the skill vessels - takes the
## owner's FACTION body tone sampled from the approved unit line-up (R1G-lineup-APPROVED), not the bright neon / seat hue.
## Neon (platform rims, HUD neon, selection rings, badges, score pills, unit accents) is unchanged.
## Dev: --goo-neon = 0.24.1's goo (the before shot).

const TONE := {   # unit art goo (was: current neon)
	"vex": Color("#267193"),     # was #00E5FF
	"ember": Color("#E76414"),   # was #FF742B
	"solar": Color("#E4B14E"),   # was #FFD35A
	"bloom": Color("#7DAF2E"),   # was #9CFF18
	"null": Color("#A91A56"),    # was #FF2BC2
}
const LIQUID_LIFT := 0.12        # vat / tank liquids: the median samples are shadowed, lift the mid-tone (designer: ~10-15 %)

static var on := not ("--goo-neon" in OS.get_cmdline_user_args())
static var factions: Dictionary = {}   # seat -> faction (main sets it once the Sim is set up)
static var human := "A"


static func of_faction(f: String, fallback: Color) -> Color:
	if not on or not TONE.has(f):
		return fallback
	return TONE[f]


static func of_seat(seat: String, fallback: Color) -> Color:
	## The goo of `seat`'s faction; `fallback` (its old colour) for no seat, an unknown faction or --goo-neon.
	if seat == "":
		return fallback
	return of_faction(str(factions.get(seat, "")), fallback)


static func liquid(seat: String, fallback: Color) -> Color:
	## A vat's / tank's liquid: the body tone, mid-tone lifted.
	var c := of_seat(seat, fallback)
	return c if c == fallback else c.lightened(LIQUID_LIFT)


static func mine(fallback: Color) -> Color:
	## The local player's goo (HUD: SEND tank, skill vessels), lifted like a liquid.
	return liquid(human, fallback)
