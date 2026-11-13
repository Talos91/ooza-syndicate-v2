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
## P-01..P-05, the Relays 3.0 prototype test maps (2026-10-28; never pooled): the probe's smallest tap at each map's row (sweep
## 41-58, measured on the rulebook stand-in, same geometry): P-01 43.7 pt, P-02 39.7 (36.5 at its size pitch 50, the tallest
## map, 81 m), P-03 46.8, P-04 36.7 (54 puts a badge on a platform), P-05 45.7; nothing off screen or under the HUD.
## E-01..E-10, the experimental maps (2026-10-28, maps-exp; pooled as group E): the lowest pitch of the sweep 41-58 whose smallest
## tap clears 44 pt with no badge off screen / on another badge / on a platform (probe 1266x585, 844 x 390 pt, pieces skipped -
## they are never tapped): E-01 46.0 pt @50, E-02 51.4 @41, E-03 51.7 @54, E-04 46.8 @45, E-05 45.0 @54, E-06 45.0 @50, E-07 45.7 @50,
## E-08 54.8 @54, E-09 49.5 @58 (one badge on a platform at every pitch; 46.3 @54), E-10 44.5 @45; nothing off screen or under the HUD.
const PITCH := {
	"T-11": 41.0,
	"T-12": 41.0,
	"P-01": 50.0,
	"P-02": 58.0,
	"P-03": 50.0,
	"P-04": 50.0,
	"P-05": 45.0,
	# round R (2026-11-05, maps-r worker): the lowest pitch of the sweep 41-58 whose smallest tap clears 44 pt, nothing off
	# screen or under the HUD (probe 1266x585, desktop emulation): R-01 44.4 pt, R-02 44.1, R-03 44.4, R-04 45.8, R-05 45.6
	"R-01": 52.0,                 # next-pass (Daniele 2026-11-13 "bend a little"): 54 -> 52 with ZOOM 0.92, phone_fit 8 profiles 0/0, min tap 47.3 pt
	"R-02": 50.0,
	"R-03": 50.0,
	"R-04": 41.0,
	"R-05": 58.0,                 # 2026-11-05 rework (mirrored, 78 m tall): 41.7 pt, 5 badges over platforms
	"R-11": 58.0,                 # version B of R-05 (same footprint)
	"R-15": 58.0,                 # R-05 shrunk to 66 m (2026-11-07): 50.3 pt, 2 badge overlaps, 4 badges over platforms
	"R-16": 58.0,                 # R-11 shrunk to 66 m (same footprint as R-15)
	"R-17": 52.0,                 # next-pass: 54 -> 52 with ZOOM 0.90 (8 profiles 0/0, min tap 59.6 pt). R-01 minus its middle crossing (Daniele 2026-11-12), 91 x 50 m: 65.6 pt at 54 (R-01's pitch; 49.7 pt at 41), 1266x585 emulation
	# wave 2 (2026-11-05, maps-r-4; probe 1266x585, desktop emulation): R-06 48.6 pt, R-09 45.1, R-10 45.0, R-12 47.9, R-13 46.3 (6 badges over platforms)
	"R-06": 50.0,
	"R-09": 50.0,
	"R-10": 50.0,
	"R-12": 50.0,
	"R-13": 54.0,
	# experimental maps (main, maps-exp)
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
	"R-14": 54.0,                 # Catapult Bay (2026-11-06): 47.1 pt (50: 43.7)
}


# START-VIEW ZOOM (Daniele 2026-11-13, his phone on staging 0.24.2: "the map now seems zoomed too far, I believe we can bend a
# little bit and zoom in a bit"): the whole-map fit's camera distance x this factor (< 1 = closer), picked per map with
# tests/phone_fit.tscn (nothing off screen or under the HUD, taps >= 33 pt). The player's pinch-out ends at this view.
const ZOOM := {
	"R-01": 0.92,                 # 0.90 at 52: 3 platforms under the HUD on 4 phone profiles
	"R-17": 0.90,                 # 0.88 at 50: 1 under the HUD
}


static func zoom_for(code: String) -> float:
	for a in OS.get_cmdline_user_args():          # probe / shots: --fit-zoom=k for every map
		if a.begins_with("--fit-zoom="):
			return clampf(float(a.substr(11)), 0.5, 1.0)
	return float(ZOOM.get(code, 1.0))


static func pitch_for(code: String, size := "") -> float:
	## A per-map override first, then by the map's size tag (tags.size): LARGE maps keep the original top-down pitch
	## (Rules.CAM_PITCH_LARGE; Daniele 2026-09-30: "on large maps the tilt makes it very hard to play ... switch back to the
	## original one; keep only mid, small and tiny tilted"), the rest Rules.CAM_PITCH.
	## 0.23.13: by size step (Rules.CAM_PITCH_BY_SIZE: XS 41 -> XL 66; Daniele: "for big maps the camera is too tilted").
	if PITCH.has(code):
		return PITCH[code]
	return float(Rules.CAM_PITCH_BY_SIZE.get(size, Rules.CAM_PITCH))
