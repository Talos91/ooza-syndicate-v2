class_name Board3
## OOZE 3.0 BOARD: the one fixed start camera and the ZOOM BOX every 3.0 map (MapPool.POOL3, group Z) is built into
## (plan 05 Handoff/handoffs/3.0-ARCHITECTURE-PLAN 2026-11-27.md section 2.3; owner: the map worker, WP2).
## Kept out of rules.gd so the map worker and the rules worker never share a file.
##
## CAMERA: yaw 0, pitch CAM_PITCH, distance CAM_DIST, aimed CAM_AIM_Z m (+z, towards the viewer) off the map frame's centre
## (layout 0, 0 = the generator's frame point (80, 40)). Start values = lab4's locked camera (the lab4 locked camera, Daniele's
## phone test of lab3: "the maps need to be buildt at zoom in target").
## BOX: the ground a platform RIM (BOX_RIM = the owner band's outer edge, Rules.R + 0.14) may reach at that camera and still show
## inside main.pit_rect() (HUD columns, top band, bottom strip and side safe areas out) on BOTH reference phones (844 x 390 pt with
## 47 pt notch insets; 812 x 375 pt with 44 pt): a trapezoid in metres from the frame centre, +z towards the viewer (the map's +y):
## far edge z = BOX_FAR_Z (half-width BOX_FAR_HALF_W), near edge z = BOX_NEAR_Z (half-width BOX_NEAR_HALF_W), linear between;
## the far edge also keeps a 7.5 m tower on its platform in view.
##
## THE BOX IS A HARD CHECK IN THREE PLACES:
##   1. the generator (References/Ooze Syndicate maps 3.0/generator/maps3.py) reads these lines and refuses a map outside (exit 2);
##   2. the bake stamps frame.box = BOX_ID; tests/test_maps4.gd fails a pooled map whose stamp differs or whose rim leaves the box;
##   3. tests/box_probe.gd re-measures the box on both phones and fails when it is smaller than these constants.
## Change any number below -> change BOX_ID -> re-run box_probe, re-bake every Z map (maps3.py --game=<clone>), run test_maps4.
## Measured 2026-11-27 by tests/box_probe.gd at R 7.6 (BOX_R), numbers in the WP2 report (worker-reports 2026-11/wp2-maps-report.md).

const BOX_ID := "b3-r76-p45-d745-2"   # changes whenever any constant below changes
const BOX_R := 7.6                    # the platform radius the box was measured for (test_maps4: must equal Rules.R)
const CAM_PITCH := 45.0
const CAM_DIST := 74.5
const CAM_AIM_Z := 0.4                # lab4's aim kept (probe at R 7.6: each phone's own centring aim 1.37 / 0.98); the box below = the overlap
const BOX_RIM := 7.74                 # BOX_R + 0.14 (Look.RIM_OUT at R 7.6)
const BOX_FAR_Z := -28.8            # probe 2026-11-27 from aim 0.4: -29.72 (844 x 390) / -28.86 (812 x 375); the far edge is set by the tower top
const BOX_NEAR_Z := 27.6            # probe: 27.78 / 27.70
const BOX_FAR_HALF_W := 52.6       # probe: 53.43 / 52.68 at the far edge
const BOX_NEAR_HALF_W := 30.5      # probe: 30.75 / 30.55 at the near edge
const TOWER := 7.5                    # the tallest tower the far edge keeps in view (main._fit_nodes)


static func half_w(z: float) -> float:
	## The box's half-width at depth z (linear from the far edge to the near edge).
	return BOX_FAR_HALF_W + (BOX_NEAR_HALF_W - BOX_FAR_HALF_W) * (z - BOX_FAR_Z) / (BOX_NEAR_Z - BOX_FAR_Z)


static func rim_margin(x: float, z: float, rim: float = BOX_RIM) -> float:
	## The worst margin in metres of a platform rim (radius `rim`, centre x, z from the frame centre) against the box:
	## >= 0 = inside. 24 points round the rim, as the generator checks.
	var worst := INF
	for k in range(24):
		var a := TAU * k / 24.0
		var px := x + rim * cos(a)
		var pz := z + rim * sin(a)
		worst = minf(worst, minf(minf(pz - BOX_FAR_Z, BOX_NEAR_Z - pz), half_w(pz) - absf(px)))
	return worst
