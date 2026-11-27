class_name TapPick
extends RefCounted
## NEAREST-NODE TAP (Ooze 3.0 WP4; LAB WP3, Daniele 2026-11-23 clusters): the node a ground point picks. Touching platforms
## (joint edges, 15.2 m apart at R 7.6) have tap discs that overlap; the NEAREST centre among the discs that hold the point
## wins (never the lowest id), so a tap on either platform of a joint takes that platform. main._node_at calls it after the
## relay buttons, the count screens and the badges; tests/test_joints.gd checks it on the Z cluster maps.

const PAD_MOBILE := 2.5             # m past the rim a finger still picks the node (phones)
const PAD_DESKTOP := 1.0


static func nearest(sim, p: Vector3, mobile: bool) -> int:
	if p == Vector3.INF:
		return -1
	var best := -1
	var best_d := INF
	for n in sim.nodes:
		if sim.collapsed.get(n["id"], false) or n.get("node_kind", "") == "junction":   # JUNCTION: not tappable
			continue
		var dn := (n["pos"] as Vector3).distance_to(p)
		if dn <= Rules.R + (PAD_MOBILE if mobile else PAD_DESKTOP) and dn < best_d:
			best = n["id"]
			best_d = dn
	return best
