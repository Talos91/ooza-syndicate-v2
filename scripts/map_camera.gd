class_name MapCamera
## Camera pitch per map, in degrees above the horizon. Daniele, Map Lab, 2026-09-29: "34deg is best" -
## a lower, more diagonal camera for EVERY map, no per-map overrides; let the phone-fit probe
## (tests/phone_fit.tscn) flag any map that stops fitting at 34 (scripts/map_pool.gd PHONE_UNFIT) rather
## than giving that map its own pitch back. PITCH stays here, empty, so a future per-map override is
## still one line away if a map ever needs it again; until then every map falls through to
## Rules.CAM_PITCH (34.0). History: this table held 58.0 for every maps 4.2 / Alpha 11 classics / maps
## 4.3-4.6 / tutorial map from Alpha 18 ("a bit more from the top") through 0.22.x.
## T-11 (quick start) / T-12 (team play 2v2), the rewritten tutorial's maps (2026-09-30): rows at the current CAM_PITCH, from the
## phone-fit probe (1266x585, 844 x 390 pt): T-11 tap 58.5 pt, T-12 tap 55.3 pt at 41 (34: 54.7 / 45.7, 50: 63.6 / 66.3,
## 58: 67.3 / 70.8 - all clear 44 pt, nothing off screen or under the HUD, no badge overlaps).
## E-01..E-10, the experimental maps (2026-10-28, maps-exp; pooled as group E): the lowest pitch of the sweep 41-58 whose smallest
## tap clears 44 pt with no badge off screen / on another badge / on a platform (probe 1266x585, 844 x 390 pt, pieces skipped -
## they are never tapped): E-01 46.0 pt @50, E-02 51.4 @41, E-03 51.7 @54, E-04 46.8 @45, E-05 45.0 @54, E-06 45.0 @50, E-07 45.7 @50,
## E-08 54.8 @54, E-09 49.5 @58 (one badge on a platform at every pitch; 46.3 @54), E-10 44.5 @45; nothing off screen or under the HUD.
const PITCH := {
	"T-11": 41.0,
	"T-12": 41.0,
	"E-01": 50.0,
	"E-02": 41.0,
	"E-03": 54.0,
	"E-04": 45.0,
	"E-05": 54.0,
	"E-06": 50.0,
	"E-07": 50.0,
	"E-08": 54.0,
	"E-09": 58.0,
	"E-10": 45.0,
}


static func pitch_for(code: String, size := "") -> float:
	## A per-map override first, then by the map's size tag (tags.size): LARGE maps keep the original top-down pitch
	## (Rules.CAM_PITCH_LARGE; Daniele 2026-09-30: "on large maps the tilt makes it very hard to play ... switch back to the
	## original one; keep only mid, small and tiny tilted"), the rest Rules.CAM_PITCH.
	## 0.23.13: by size step (Rules.CAM_PITCH_BY_SIZE: XS 41 -> XL 66; Daniele: "for big maps the camera is too tilted").
	if PITCH.has(code):
		return PITCH[code]
	return float(Rules.CAM_PITCH_BY_SIZE.get(size, Rules.CAM_PITCH))
