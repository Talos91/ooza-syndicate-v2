class_name MapCamera
## Camera pitch per map, in degrees above the horizon. Daniele, Map Lab, 2026-09-29: "34deg is best" -
## a lower, more diagonal camera for EVERY map, no per-map overrides; let the phone-fit probe
## (tests/phone_fit.tscn) flag any map that stops fitting at 34 (scripts/map_pool.gd PHONE_UNFIT) rather
## than giving that map its own pitch back. PITCH stays here, empty, so a future per-map override is
## still one line away if a map ever needs it again; until then every map falls through to
## Rules.CAM_PITCH (34.0). History: this table held 58.0 for every maps 4.2 / Alpha 11 classics / maps
## 4.3-4.6 / tutorial map from Alpha 18 ("a bit more from the top") through 0.22.x.
const PITCH := {}


static func pitch_for(code: String, size := "") -> float:
	## A per-map override first, then by the map's size tag (tags.size): LARGE maps keep the original top-down pitch
	## (Rules.CAM_PITCH_LARGE; Daniele 2026-09-30: "on large maps the tilt makes it very hard to play ... switch back to the
	## original one; keep only mid, small and tiny tilted"), the rest Rules.CAM_PITCH.
	if PITCH.has(code):
		return PITCH[code]
	return Rules.CAM_PITCH_LARGE if size in Rules.CAM_LARGE_SIZES else Rules.CAM_PITCH
