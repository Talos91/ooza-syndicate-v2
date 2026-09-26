# Ooze Syndicate 2.0 - changelog

## 0.18.8 "Alpha 18" - 2026-09-26 (skills effects, look upgrade with the abyss fog, balance preset)

- **Every skill draws its effect** (`scripts/skill_fx.gd`, from Sim state and fx events, so guests see them): hex
  shield, deck fire with smouldering bodies, sludge, bolted rails and clamps, Demolish's glowing cracks / falling
  pieces / rebuild, Bypass holograms, Relay Hack glitch and jam clamp, Rewire streaks, Echo Split's OFFLINE
  static, Superbloom's +N / 40 counter, Core Meltdown's blast and CAPTURED, Relay Aegis domes; ultimates tint the
  screen edge; ghost lines are translucent for their owner only.
- **Look upgrade** (Daniele: "vats are hard to see ... feel different from the theme ... push the graphic further"):
  vats on an owner-lit plinth ring with glass tanks tinted by owner, neon cap rings that count the tanks (T1 -> T4),
  cannons / forge / relay housings in the same family; **the abyss** (Daniele: "pillars come from the void ... add
  a fog"): height fog below the decks, a hazed backdrop and drifting mist, so pillars, falling bodies, deck
  fragments and collapsing platforms fade out instead of ending mid-air. Vat models carry `Spout_*` markers for
  the unit drops. Phone-fit: 74 maps, min tap 41 pt, no overflow. Frame cost within budget on desktop; not
  measured on a real phone.
- **Balance study** (Daniele: "vat power up cost, production speed etc"): the economy numbers are overridable
  (`Rules.apply_balance`); preset `b187` proposes neutral garrisons 12/16/32/64, Ember attack 1.07, Bloom
  production 1.05, Vex garrison 0.95 - OFF by default (Debug: Balance DEFAULT / B187); the harness is
  `tests/balance_probe.gd`. Findings: PLAYTEST-NOTES 129; decisions: OPEN-QUESTIONS.
- Tests: all five suites pass (BRAWL only). Desktop and phone emulation only.

## 0.18.7 "Alpha 18" - 2026-09-26 (BRAWL only, relay fall rule, skills, lobby teams, maps 4.6, look and AI passes)

Published live as a playable alpha before the pass was complete (Daniele: "push what is safe to push to a playable
alpha now"); the look upgrade with the depth fog, the release docs and the mobile UI pass follow in 0.18.8.

- **BRAWL is the game; SIEGE is deactivated** (Daniele: "brawl is our game ... completely deactivate it"). The mode
  selector is gone from OPTIONS, SETUP, the lobby, the pause menu and Debug; rooms start in BRAWL (they defaulted
  to SIEGE before); `Rules.bridge_combat` cannot be set true. The SIEGE code stays dormant and untested; the
  tests run BRAWL only (test_map_pool and test_ai_curve take half the time).
- **Relay fall rule** (Daniele: "no bridge = bridge down ... units on the bridge have 1 sec to clear the bridge then
  bye bye, this applies to all types including the retract"): during the 1 s warning every deck is still walkable;
  the moment its motion starts, everything on a deck that goes away falls - retract no longer carries anyone in,
  rotation still flings. The rest of the order pours off the lip (waterfall). A line straddling a gone deck splits:
  the part past it walks on as its own line. Toast "N units fell with the retracting / switched / switched-off deck".
- **Last Stand drops rotate round the players' corners** (Daniele: "start randomly from one of the starting corners
  then move to the opposite, then another ... until all nodes that are supposed to fall are gone"): the first corner
  is seeded; then the opposite one, then the others, then back; the cycle carries across rings; never an island.
- **Lobby: teams and colours** (Daniele saw both players as blue; "no way to change a player team"): every player
  picks a room colour shown identically on every screen (team modes: one family per team, cool vs warm); JOIN TEAM
  per team, the host can MOVE players; AI fills free seats. Protocol tag `ooze20-net-2`.
- **Skills 2.0 shipped** (SKILLS-2.0-DRAFT approved): 5 active + 5 map skills shared by every faction, one ultimate
  per faction (Rewire, Echo Split, Superbloom, Core Meltdown, Relay Aegis), the §5.2 rebalance; Superbloom = 1.5x for
  12 s, capped at +40 (Daniele's pick); Demolish waterfalls in BRAWL; everything unlocked; ABILITIES ON/OFF in
  SETUP and the lobby. **ARMIES** menu item: a saved preset per faction (active + map skill; the ultimate is fixed);
  the faction page shows it. In-match **dock** (ACTIVE / MAP / ULTIMATE): tap a slot, valid targets light up, tap
  one; keys 1/2/3; cooldown sweeps, ultimate charge ring; enemy-cast toasts. Every skill has its in-world effect
  (hex shield, deck fire, sludge, clamps, Demolish crack / fall / rebuild, Aegis dome, Meltdown blast, ghost lines
  only their owner sees translucent). The AI casts every skill; online casts are host-validated; ghost lines stay
  private to their caster's client.
- **Forge online surge** (Daniele: "when a forge is created all units and structures of that player should get a
  2 sec animation"): a wave from the forge hits every owned structure and unit by distance; toast
  "FORGE ONLINE: +50% attack"; the inspector shows the bonus.
- **Cannons kill where the laser hits** (Daniele: "towers kill enemies blobs from the bottom instead of from the
  top"): the front of an incoming line dies under the beam; the burst keeps its full kill, so the beam can reach up
  to ~12 m past its range (Daniele: "fine for it to extend its line of sight").
- **Waterfall pour is seamless** (Daniele: "the animation should be seamless and exaggerated ... +20%"): bodies walk
  off the lip at marching pace and arc into the void; at most 1.2x the real losses are drawn.
- **Units drop out of the vats** (Daniele: "goo monsters being dropped from the vats"): each unit spills over a tank
  rim as a blob, splats, forms into its creature and runs to the door, in time with the real stream.
- **TERRITORY: NEON / GOO** option (Daniele: "goo instead of neons ... add it as a toggle"): GOO covers owned
  platforms and deck halves with goo in the player colour (meniscus, drips, bubbles), units in their race colour
  with a player-colour rim; spreads on capture, recedes on loss, falls with the platform. NEON is unchanged.
- **AI uses relays** (Daniele: "the AI tends to avoid relay bridges and almost never builds on relays"): routes judge
  whether a rival relay can cut a deck in time, the AI never fires onto its own pending orders, re-opens its own
  shortcuts, values relay nodes (keeps 6 units on them) and builds cannons / forges on relay slots. Relay-shortcut
  use 42 -> 69 % (Standard), hazardous crossings 3 % -> 0.1 %. BRAWL curve vs Standard: 0 / 5 / 50 / 100 / 100 %.
- **Maps 4.6 relay** (References/Ooze Syndicate maps 4.6 relay): M-51..M-60, relay-packed fields (5-6 relays), 74 maps.
  All bake clean; phone taps 44-54 pt. **Pillars** under relay and strategic (all-structure) nodes (Daniele).
- **Map thumbnails uncropped** (Daniele: "thumbnails often overflow"), in the grid, the preview and setup.
- **Taps open the ring only on your own nodes** (Daniele: "an empty radial menu appears" on enemy vats).
- **Debug tools hidden** behind OPTIONS > DEBUG TOOLS (Daniele: "we are past debug tools").
- **Balance study** (Daniele: "vat power up cost, production speed etc we need to balance better"): the economy
  numbers are now overridable; preset `b187` (OFF by default, Debug toggle) proposes neutral garrisons 12/16/32/64,
  Ember attack 1.07, Bloom production 1.05, Vex garrison 0.95. Findings and the proposal: PLAYTEST-NOTES 129 and
  `tests/balance_probe.gd`. Waiting for Daniele's decision.
- Tests: test_sim, test_net, test_maps4 (11,038 checks), test_map_pool, test_ai_curve - all pass, BRAWL only.
  Everything was checked on desktop and in phone emulation; the online lobby in two browsers on one PC; nothing on
  a real phone or across networks.

## 0.18.6 "Alpha 18" - 2026-09-26 (waterfall, Last Stand at 3:00, neon connectors, fixed badges, fight / tier-down / laser, maps 4.4 classic, map filters)

- **Waterfall** (Daniele: "if someone retract a bridge and your troops had order to go on said bridge they should
  go even if the bridge is no longer there hence....waterfall"): an order across a deck that a relay takes away
  (retract, switch, remote, rotation) or that is already gone is still obeyed - the vat keeps sending and every
  unit behind the missing deck marches off its lip into the void (fall losses). Retract riders are still carried
  into the relay node. Before, the order was cut and what was left re-routed.
- **Last Stand starts at 3:00** (was 2:00) and the **relay warning is 1 s** (was 3 s) (Daniele: "last stand reset
  to be starting at 3 m, bridge alert cooldown just 1 sec"). Every map's collapse still ends by 4:25.
- **Remote fixed on Neon Delta** (Daniele: "the relay remote does nothing"): a remote or switch whose decks all
  share one state now toggles them off and back on.
- **Dark connectors fixed, neon on connectors and platform edges** (Daniele: "a few dark socket connectors, also
  sockets miss the neon stripe on top like normal bridge ... same neon stripe at the edge of nodes"): mirrored
  angled piers are real mirrored meshes (a negative-scale instance lit its top faces from below); every pier
  carries the deck's two neon strips, and every platform a neon rim in the owner's colour that opens where the
  strips arrive and falls with the platform.
- **Badges: one fixed size, translucent, content always inside** (Daniele: "a bit transparent ... the word final
  isn't necessary ... fixed size ... never get out of the box"): 44 x 33 (51 x 38 on phones), see-through fill,
  text shrinks to fit and clips; sub line at most two tags (T2 / CN3 / FRG / relay state, then one timer: fall
  countdown, relay warning, build or cooldown seconds, or the drop ring). FINAL is gone.
- **Fight for a tower** (new): a contest ring round the platform (the attacker's arc from the side they came,
  sized by strength), a hot glow where they clash, sparks, splats and flashes by the kill rate; BRAWL and SIEGE.
- **Capture that lowers the tier** (new): the old model sinks and fades with a debris burst, the new tier rises,
  and a "T3 -> T2" label with a falling chevron in the new owner's colour.
- **Cannon laser** (Daniele: "laser needs to be made looking good"): a glowing ribbon beam with a white core,
  owner-colour glow, pulses and tapered ends, muzzle flash, impact flare, sparks and scorch; muzzles at the real
  dome heights.
- **Camera lower as the map shrinks** (Daniele: "a bit too vertical when less nodes are present"): the Last Stand
  zoom also lowers the pitch, down to 14 degrees below the map's (never under 44) as platforms fall.
- **Maps 4.4 classic** (References/Ooze Syndicate maps 4.4 classic): M-21..M-40, 20 more Mushroom Wars style
  maps (five relay-heavy), added to the M group - 64 maps. All bake clean; camera 58 degrees; phone taps 44-54 pt.
- **Map filters** (Daniele: "add in game filters for maps like 1v1 2v2 ffa etc"): 02 BATTLEFIELD has a players
  row (ALL, 1V1, 2V2, FFA 3, FFA 4 - the modes the pool has) and a TYPE button (ALL, BRAWL, SIEGE, CORE,
  ALPHA 11, TRAINING), with an "N OF 64 MAPS" count; a players filter also sets up that mode.
- Tests: test_sim, test_net, test_maps4 (8,854 checks), test_map_pool, test_ai_curve - all pass; phone-fit probe
  on all 64 maps: nothing off screen, under the HUD or colliding. Checked on desktop and in phone emulation
  only; not on a real phone.

## 0.18.5 "Alpha 18" - 2026-09-26 (maps 4.3 classic: 20 Mushroom Wars style maps added)

- **Maps 4.3 classic added** (References/Ooze Syndicate maps 4.3 classic): M-01..M-20, open fields of scattered
  platforms with every neighbour linked, homes at the screen edges and one or two relays each - the original
  Mushroom Wars feel - at the kit's sizes (decks 4 / 8 / 12 m). 8 x 1v1, 3 x 2v2, 5 x FFA 4 (three also 2v2),
  4 x FFA 3; brawl, siege and core groups. Listed after the Alpha 11 classics as the "M" group; maps 4.2 and
  the classics stay.
- Baked by `Models/2.0/export_maps_4_2_game.py`, which now also reads the 4.3 classic folder: all 44 maps
  clean (no clashes, every deck within 1.5 m of its tier's length). Camera 58 degrees; phone tap targets
  45-54 pt, nothing overflows.
- Tests: test_sim, test_net, test_maps4 (5,846 checks), test_map_pool, test_ai_curve - all pass. Curve vs
  Standard over the larger pool: Training 0 %, Casual 20 %, Standard 50 %, Veteran 85 %, Expert 95 %;
  FFA 4 seat A draws 29 % of attacks (even 33 %). Not tried on a real phone.

## 0.18.4 "Alpha 18" - 2026-09-26 (rotating decks fling, ring by ring falls, camera closes in, emblems)

- **A rotating deck shakes its lines into the void** (Daniele: "when a rotating bridge turns all units that
  are on it are shaken down into the void as if the fall due to centrifugal power"). Every line on a
  turning deck - any owner, the relay owner's own included - is flung outward and sideways off the deck
  and tumbles down (SIEGE goo, BRAWL Alpha 11 creature bodies); counted as fall losses; toast "N units
  flung off the turning deck". Retract, switch and remote relays are unchanged. The AI fires a rotation
  when it kills more enemy than it costs, never with its own or allied lines on the deck. BRAWL plain
  falls now drop creature bodies too, instead of goo.
- **A Last Stand ring falls platform by platform** (Daniele: "don't make all outward rings fall at the same
  time but one after the other, 5 s distance from each, following the rule we set for falling bridges").
  After the ring's 10 s warning its platforms drop one every 5 s, in an order that never leaves another
  platform cut off (relays last, the far side first); each badge counts down to its own drop; the next
  ring waits for the last drop. test_maps4 checks the map stays connected after every single drop.
- **The camera closes in as the Last Stand eats the map** (Daniele: "if the borders are gone have the camera
  zoom in to make it more epic"): 1 s after a platform falls the view eases (1.5 s) onto what is left,
  never wider than the start and at most 2.5x closer; guests zoom too.
- **Owner emblems instead of seat letters** (Daniele: "don't use A B and C but use emblems in the color of the
  owner"): badges that hide a count show the owner's faction emblem in the owner's colour; the inspector
  header, and toasts that name a player, show the emblem and faction name in that colour.
- **BRAWL 20 % slower again** (Daniele: "deck speed on brawl should be a bit slower ... reduce by 20% brawl
  unit movement speed"): 5.7 m/s on decks and platforms (Alpha 11's speed less 20 % twice); spacing
  follows.
- **BRAWL door entry is orderly** (Daniele: "units entering the building ... as if violently shaking toward
  the door"): every body keeps its place, lane and step for the whole trip, walks on at the marching pace
  into the door and turns smoothly round corners (measured: 0 frame-to-frame jumps, was 316; 0 heading
  snaps, was 100).
- Tests: test_sim, test_net, test_maps4 (2,796 checks), test_map_pool, test_ai_curve - all pass (curve on
  maps 4.2 + the classics: 8 / 33 / 50 / 92 / 83 %). Not tried on a real phone or in a live online room.

## 0.18.3 "Alpha 18" - 2026-09-26 (the four main Alpha 11 maps, at the kit's sizes)

**Alpha 11's four main arenas are back** (Daniele: "pick up the main 4 map of the alpha 11, aurora trident
and the other 2"): A-01 Orbital Nexus, A-02 Switchback Foundry, A-03 Aurora Concourse, A-04 Trident
Exchange - Alpha 11's own layouts (same nodes, same bridges, same arrangement; maps 4.2 only reuses the
names), listed right after the tutorials as the "Alpha 11" group.
- Redrawn at the kit's sizes in the maps 4.2 format (`References/Ooze Syndicate maps 4.2 - Alpha 11
  classics`, a derived pack: `generator/classics.py`, positions fitted by `generator/embed.py`): every bridge
  an honest S / M / L deck, symmetric where Alpha 11 was (Orbital and Aurora four ways, Trident left/right),
  no relays or plazas (Alpha 11 had none). Footprints 54 x 38, 56 x 31, 54 x 27 and 84 x 51 m.
- Modes (seats fair by travel time): Orbital Nexus 1v1 (left vs right, Alpha 11's own duel seats) / 2v2 /
  FFA 4 (the diagonals); Switchback Foundry 1v1 (not symmetric, as in Alpha 11: tiers give both seats the same
  distance to every node); Aurora Concourse 1v1 (opposite corners) / 2v2 / FFA 4; Trident Exchange 1v1 (outer
  corners) / 2v2 (left island vs right island). Combat: SIEGE and BRAWL.
- 4.2 rules where Alpha 11 had none: neutral tiers by distance (almost all T1, as in Alpha 11), a strategic
  centre on each map (Orbital's hub was Alpha 11's central objective), Last Stand rings with safe orders
  only (Aurora: inward only - its rows meet only through the middle pair).
- Baked by `Models/2.0/export_maps_4_2_game.py`, which now also reads the classics folder (`-- --only=A-`
  bakes just these): all four clean - no clashes, no decks over platforms, decks 4.0-4.6 / 8.0 /
  11.6-12.1 m, piers within 27 degrees; Orbital's hub keeps its eight bridges. Menu thumbnails in the 4.2
  schematic style. Camera 58 degrees (phone taps 56-88 pt, nothing overflows, no badge collides).
- Tests: test_sim, test_net, test_maps4 (2,761 checks, 24 maps), test_map_pool (24 maps; the classics in
  SIEGE and BRAWL), test_ai_curve (8 / 33 / 50 / 92 / 75 % - its maps are unchanged) - all pass; every
  classic mode (1v1, 2v2, FFA 4) also played AI vs AI to the end in both combat modes. Not tried on a
  real phone.

## 0.18.2 "Alpha 18" - 2026-09-26 (maps 4.2: 20 compact maps at the kit's sizes)

**Maps 4.2 replace maps 4.1** (References/Ooze Syndicate maps 4.2): 20 compact maps drawn in metres at
the kit's sizes, sized like the Alpha 11 arenas (Orbital Nexus, Aurora Concourse, Switchback Foundry,
Trident Exchange), **no plazas** - a pocket is home + two neutrals, each one short deck away.
- Baked at 1 m per unit (`Models/2.0/build_maps_4_2_review.py`, `export_maps_4_2_game.py`): all 20 clean -
  no clashes, no decks over platforms, every deck within 1.5 m of its tier's honest 4 / 8 / 12 m.
- Maps: T-01, T-02; brawl B-01..B-05; siege S-01..S-05; core C-01..C-05; debug D-01..D-03. Modes 1v1,
  FFA 3 (B-03, S-03, C-03), FFA 4 (B-04, S-04, C-04) and 2v2 (B-04, S-04, B-05, S-05, C-05). No 5- or
  6-seat maps (they do not fit 160 x 80 at real size), so FFA 5, 3v3 and 2v2v2 have no maps for now.
- Camera 58 degrees on every map: every node's tap target 45-66 pt on an 844 pt phone, nothing overflows,
  no badge collides (phone-fit probe).
- Tests: test_sim, test_net, test_maps4 (2,378 checks), test_map_pool, test_ai_curve - all pass. Curve vs
  Standard on these 6 duel maps: Training 8 %, Casual 33 %, Standard 50 %, Veteran 92 %, Expert 75 %
  (Expert below Veteran on this small set - watch in play); FFA 4 seat A draws 25 % of attacks (even 33 %).
  Not tried on a real phone.

## 0.18.1 "Alpha 18" - 2026-09-25 (maps 4.1 at the kit's sizes, partial pack)

**Maps 4.1 replace maps 4.0** (Daniele, after the phone check: "the bridge should be like 1/3 of now";
decks on 4.0 were 3.6x the kit's honest length). The new pack (References/Ooze Syndicate maps 4.1
(partial)) is drawn in metres at the kit's own sizes: platform radius 6, pier 1.6, deck module 4, honest
centre distances 19.2 / 23.2 / 27.2, at least 15 m between node centres.
- Baked at **1 m per map unit** - nothing stretched (`Models/2.0/build_maps_4_1_review.py`,
  `export_maps_4_1_game.py`; plaza templates read off the maps). Decks now measure 4.1 / 8.3 / 12.4 m
  (S / M / L median; honest 4 / 8 / 12; 4.0 had 6.9 / 28.8 / 44.2). Maps span ~130 x 55 m.
- **18 maps so far**: T-01..T-05, B-01..B-05, B-07, X-01, X-03, X-04 and debug D-01, D-02, D-05, D-07 (the
  pack's generator failed B-06 and B-08; the core and siege groups are still to come). Only X-01 offers
  FFA 4 / 2v2 for now; every other map is 1v1.
- All 18 bake clean (no clashes, no decks over platforms, no docks needed). `test_maps4` now also checks
  that every ground deck keeps its tier's honest length (fails past 2.5 m; D-07 and T-05 each have one
  short deck off by 2.8 / 1.6 m - reported).
- **Camera**: each map from 58 degrees (most) to 66: every node's tap target is now 44-67 pt on an 844 pt
  phone (Apple's 44 pt guideline met on every map; 4.0 reached 33), nothing overflows, no badge collides.
- `tests/test_net.gd` no longer depends on the shipped pack (it points the pool at the legacy roster,
  which offers every mode).
- Tests: test_sim, test_net, test_maps4 (2,477 checks), test_map_pool, test_ai_curve (Training 0 %,
  Casual 25 %, Standard 50 %, Veteran 50 %, Expert 92 % vs Standard; FFA 4 seat A 19 % of attacks) - all
  pass. Not tried on a real phone yet.

## 0.18.0 "Alpha 18" - 2026-09-25 (maps 4.0 for phones, per-map camera, optimization pass)

**Maps 4.0 replace maps 3.0** (Daniele: "the maps are waaaay too big for mobile"; References/Ooze
Syndicate maps 4.0: 100 maps + 9 debug maps on a 160 x 80 landscape frame, average 19.9 nodes).
- Baked through the same pipeline: `Models/2.0/build_maps_4_0_review.py` (the approved 3.0 builder with
  only the pack path, the 160 x 80 frame, the gen4 plaza templates and K changed) and
  `Models/2.0/export_maps_4_0_game.py` -> `maps4/*.json` + `assets/maps4/<code>.glb`.
- **1.7 m per map unit** (3.0: 3 m): the smallest scale the planner leaves clean on 106 of 109 maps
  (sweep 1.4-3.0). A platform now spans 5.2 % of the screen width on the median map (Alpha 17: 2.9 %),
  4.8-11 % across the pool, before the steeper camera adds to the depth axis.
- **Docks**: a node set right in front of a home plaza left no room for two piers (the 3.0 planner bent
  the piers back and lines zigzagged out into space and back). The hop is now a straight connector from
  the plaza rim to the node's rim, or plain contact where the platform reaches the plaza - no stray pier
  stubs (424 hops).
- Withheld from the pool: **B-30** (24 deck clashes at every scale) and **D-08** (41 nodes, not
  phone-fit: 27 pt tap targets at best). Piers steeper than the kit's 80 degrees on 7 ring maps are
  clamped (reported by the test, invisible in renders).
- **On phones** the 3v3 / 2v2v2 maps are not offered (the pack's "tablet recommended"; 31 nodes on a
  round board use a third of a phone's width). Tablets and desktop keep them.
- `tests/test_maps4.gd` (renamed from test_maps3) checks docks, steep piers, the withheld maps and two
  map invariants (node ids, one edge per pair).

**Camera: more from the top, per map** (Daniele: "a bit more from the top so there's more bird's-eye
view ... different maps might want different camera angle ... make sure all nodes and their functions
are clickable on mobile and that nothing overflows").
- `scripts/map_camera.gd` gives every map its own pitch (50-74 degrees, most 62-70; was 42 for all):
  the lowest angle at which its smallest tap target reaches 33 pt on an 844 x 390 pt phone with no badge
  colliding or overflowing. Measured by the new phone-fit probe `tests/phone_fit.tscn` (run it again
  after a map pack changes; `--pitch=N` overrides the table for tests).
- Badges now treat the top bar, bottom strip, send panel and right-hand buttons as off-limits and slide
  clear of them: 0 overflowing badges on 107 maps (was 1-4 on most maps).
- The inspector's X is no longer hidden under its info panel (it sits at the ring's top right).
- Relay symbols (↻ ⇤ ⇄ ⌁) drew as empty boxes in the browser: the HUD font now falls back to DejaVu
  Sans Mono (bundled with its licence).

**Optimization pass** (read-only audit of every script: 112 findings, 110 confirmed by a second
reviewer, 95 judged safe; all safe ones applied, each reviewed again against its diff).
- Frame cost at the same view (desktop): C-05 SIEGE 1,875 -> 1,125 draw calls and 1.31 M -> 0.78 M
  primitives; D-09 3v3 3,525 -> 1,147 draw calls (815 at its own pitch). Godot's process-time monitor
  swings 6-18 ms between identical runs here, so no CPU figure is claimed. SIEGE river rings are one
  MultiMesh per platform and skip quiet platforms; BRAWL trims, relay arcs, goo corridors, vat liquids
  and badges no longer rebuild every frame; surface-detail textures are shared.
- Dead code removed: the shield mechanic (never read since Alpha 14: sim keys, badge bar, dome effect,
  constants), unused Rules constants, legacy menu tables (STARTER_MAPS, PROVES), unused API and signals.
  Stale comments and headers rewritten.
- Bugs fixed: 2v2v2 gave two teams the same colour family (now three families); in team modes the 7:00
  forced end goes to the **stronger team** (was the strongest single seat); a relay collapsing mid-motion
  froze its riders; Last Stand collapse goo was always seat A's colour; recall on a plaza socket could
  crash a collapse and a guest's path rebuild; drag released over the HUD stuck; a quick drag counted as
  the first tap of a double-tap upgrade; the Last Stand countdown ran negative with Last Stand off;
  'Relay fired' showed as a warning; CANNON / FORGE looked available during the swap cooldown; on six
  maps a retract relay with two gates lit only one gate's symbol; BRAWL could silently drop bodies past
  1,024 per seat.
- AI: no longer cancels its own sends within one think, stops investing in nodes the Last Stand is
  about to drop, keeps trying other recalls when one is refused, never builds on a relay slot under
  attack. Curve vs Standard: Training 0 %, Casual 25 %, Standard 50 %, Veteran 60 %, Expert 90 %.
- Online: a signalling blip no longer closes the host's room; a publish no longer reloads a tab in the
  middle of a match or room (the new build waits for the menu); chat marks your messages by player,
  not seat letter; a refused join says why; guests get a fresh lobby after a rematch with a missing
  player; the host stops re-sending the end state 10 times a second and builds no snapshots with no
  guest connected; the export no longer packs build/web.
- Tests: test_sim, test_net, test_maps4 (17,441 checks), test_map_pool (every pooled map played to the
  end by the AI), test_ai_curve - all pass. The online and auto-update changes are covered by test_net
  and review only: not tried in a live two-player room, on a phone or across networks.

## 0.17.1 - 2026-09-25

- **Units keep one constant speed everywhere** (Daniele: "units accelerate on long bridges - speed is
  always constant"). 0.17.0 sped lines up on decks drawn longer than their tier so every deck kept its
  tier's time; that factor is gone. A longer bridge now simply takes longer to cross.

## 0.17.0 "Alpha 17" - 2026-09-25 (maps 3.0, ring Last Stand, five-level AI)

**Maps 3.0 replace the 2.0 roster** (References/Ooze Syndicate maps 3.0, 100 maps: tutorial, core,
brawl, siege, crazy) plus the **nine debug maps** D-01..D-09 (References/Ooze Syndicate debug maps),
listed last in the map list for testing.
- The approved Blender layout (Models/2.0/build_maps_3_0_review.py) is baked, not re-planned:
  `Models/2.0/export_maps_3_0_game.py` runs the builder's own planner headless in Blender and writes
  `maps3/<map>.json` (the pack's map + node / plaza positions, each bridge's rim exits, pier leans and
  lengths, deck heights 0 / +4 / -4 / +8 and ramps, relay mounts, verification) and
  `assets/maps3/<code>.glb` (the map's plazas and exact-cut plaza piers). 3 m per map unit.
- The game places the kit from that: platforms, angled piers (Pier_Angled_00..80, mirrored for
  negative leans, _Switch where a switch fires), ground decks tiled from near-true 4 m modules, high
  overpasses and underpasses with their ramps, relay towers on the clearest rim ledge or on the socket
  (12 relays; their structure slot then stands in front of the tower), retract gates, remote conduits.
- **Plazas**: every socket of a plaza reaches every other across the plate (free movement, travel by
  distance); a plaza's plate falls with its last socket.
- **Lines only meet on the same height** (decks at 0 / +4 / -4 / +8; paths climb the ramps).
- (0.17.1: the deck-time factor this release shipped was removed - one constant speed everywhere.)
- Nodes use the pack's neutral tiers and structures (T1 pocket nodes, T2-T4 farther out, strategic T4
  nodes and centres that may start with a cannon or forge); new modes 3v3 and 2v2v2 (offline and in
  online rooms, up to six players).
- Test `tests/test_maps3.gd` (11,599 checks) re-checks the baked layout in game coordinates: deck
  edges at least 0.3 m apart wherever two decks share a height, no deck over a foreign platform or
  plaza unless raised, no bridge too short, piers within 80 degrees, the builder's verification clean,
  every plaza plate and pier present; seats per mode and team; the Last Stand rules; the heights.
  D-04 keeps one deck clash the approved planner leaves (a raised L deck over a retracting half-deck
  with no room for its ramps); the test reports it and requires the game to see exactly that one.

**Last Stand - ring logic** (Daniele): no designated first and last node any more. Each wave drops a
whole ring, in the order of the revealed method (inward / outward from the map, chaos = one of the
map's connected orders); the order's last ring never falls and conquest decides there. A relay only
falls once every ring it connects to has fallen. The collapse NEVER leaves a platform unconnected:
anything a wave would cut off from the surviving map (over fixed decks and plaza links only) falls
with that wave. Badges show the wave (R1, R2...), the inspector "falls in wave N" / "THE LAST RING",
the status line "RING N FALLS IN 10 s (k nodes)". Tutorials T-01..T-04 have no Last Stand (the pack
gives them no method).

**AI - Alpha 11's five levels** (Training, Casual, Standard, Veteran, Expert) with its decision loop:
defend threatened nodes first, invest once per level interval, one offensive per attack gap planned
from up to 1 / 1 / 2 / 2 / 3 nodes against a garrison it estimates (error 40 % .. 12 %, refreshed
10 s .. 3 s, growth forecast 0 .. 75 %), a grace before it attacks players (75 s .. 12 s), and a pick
among its best 4 .. 2 plans. **No ganging up on the human**: Alpha 11's rival adjustment (its own
border first, answer whoever attacks it, contain the strongest, avoid a node someone else is already
attacking). **Relays used properly**: never fired onto its own lines; Standard reacts to enemies on
a deck it can drop or pull in (a retract only if its garrison can take them); Veteran and Expert fire
ahead, for the lines that will be on the deck when it moves; Expert also opens a shorter route to its
target. Measured (`tests/test_ai_curve.gd`, each level vs a fixed Standard on 10 maps x 2 seats):
Training 10 %, Casual 15 %, Standard 50 %, Veteran 90 %, Expert 95 %; in FFA 4 seat A draws 30 % of
the attacks on players (even share 33 %).

**BRAWL**: units 20 % slower (7.1 m/s; still the same speed on decks and platforms, exit and entrance
at Alpha 11's rate, so columns are a little denser). Bodies now shrink and dip into the door over
their last 1.6 m, and grow out of it when they leave, instead of clipping in.

## 0.16.4 - 2026-09-25 (visual pass, while the new maps are modelled)

Daniele: "a background (what we had in Alpha 1 is a good start), better notifications in the same
style as the rest of the UI, better lighting, better textures; the vats were supposed to fill their
liquids based on how many units are inside, and the liquids in Alpha 11 contained small creatures
with a small animation."
- **Sky**: the cloud city with its planet (`assets/art/city-background.png`, Alpha 1's palette without
  its baked-in arena) behind every match, drifting slowly, darker at the edges and behind the board so
  the map still reads first (`shaders/backdrop.gdshader`, `scripts/scenery.gd`).
- **Lighting**: violet ambient from that sky, a warm key light, a cool violet fill and a back rim
  light that lifts the platform edges off the background.
- **Vat liquid is the unit gauge**: every tank's liquid fills to garrison / cap, easing up and down;
  a wobbling, glowing surface, sparse rising bubbles, and it churns while the node builds or is under
  attack. Translucent, in the owner's colour (grey when neutral) (`shaders/vat_liquid.gdshader`).
- **Residents**: small creatures of the owner's faction float in each tank (Alpha 11's tank
  residents) - one or two per tank as it fills (one on phones / low detail), bobbing, circling and
  breathing under the surface; they change on capture.
- **Surface detail**: the kit's flat colours get world-space detail - soft cell seams and wear on
  plates, a brushed grain on dark metal and steel (phones skip the normal maps).
- **Notifications** in the UI's own frame: a panel with a colour bar (info cyan, good news in your
  colour, builds gold, warnings red), up to three stacked under the top bar, popping in and fading
  out; a repeated line refreshes instead of stacking. The Last Stand banner is framed the same way.

Tested: rules / net / map-pool suites pass; desktop renders (Strait, Two Piers close-ups, Brawl) and
the web build in the browser. Not measured: frame rate on a real phone with the transparent liquids.

## 0.16.3 - 2026-09-25

- The self-update also catches a new build that finished installing before the page started listening
  (checked every 2 s for 30 s after load). Verified in the browser: an old copy swapped itself for the
  new one and reloaded.

## 0.16.2 - 2026-09-25

- **Brawl enters and exits like Alpha 11** (Daniele: "the same exact feeling, also entering and
  exiting"). Alpha 11's route: out of the vat's front (the side facing the camera), round the platform
  on its route ring to the bridge, and at the target round the ring back to the front and in; waypoints
  are rounded on the same ring. Alpha 11's column: one body every 0.93 m (its 12 px), lane = body
  index % 3, single file near both ends of the route and spreading to three across over 6.6 m (its
  85 px), every body facing its own way; arriving bodies keep walking in at their spacing. Every body
  is drawn (up to 200 per send, was 60).
- **Badges much smaller and always in the void beside their node** (Daniele: "UI way too big and keeps
  covering the bases"): about half the size, and each is placed on screen at its real size in the spot
  round its platform that covers no platform, deck or other badge.
- **HIDE ENEMY COUNTS** toggle in OPTIONS and Debug: no unit numbers on enemy nodes in either mode.
  Off, BRAWL shows every count as Alpha 11 did; SIEGE always hides them. Online the host's setting
  applies to everyone.
- **New builds arrive by themselves** (Daniele: "cache in browser still reads Alpha 14"). Godot's
  service worker serves the cached game first and a new build waited until every tab of the game was
  closed. `web/update.js` now checks for a new build on every load (and every 10 minutes) and makes it
  take over and reload the page. One last time, an old copy must be cleared by hand (close every tab of
  the game, or clear the site's data); after that every publish shows up on the next load.

## 0.16.1 - 2026-09-25 (Daniele's Alpha 16 feedback)

**Online**
- **EMPTY SEATS** lobby setting (host): PLAYERS ONLY, or AI CASUAL / STANDARD / VETERAN. With AI on,
  DEPLOY opens with any number of players and the AI plays the empty seats (the host runs it).
- **RECONNECT**: a player who drops mid-match keeps their seat - the match goes on, everyone is told,
  and with EMPTY SEATS on the AI plays that seat meanwhile. Their ONLINE page shows RECONNECT <code>
  (also after reloading the tab); it puts them back into the same seat in the running match, with a
  secret per-player token so nobody else can take it. Guests now wait **10 s** for a silent host.
- **REMATCH** on the results screen (online: needs every connected player; offline: renamed from
  PLAY AGAIN). A player still missing at the rematch is replaced by the AI, or - without AI - the room
  goes back to the lobby.

**BRAWL feels like Alpha 11**
- Units move at Alpha 11's speed, the same on decks and platforms: 115 px/s -> **8.9 m/s** (Alpha 11's
  mean hop is 284 px, 2.0's 21.9 m, so the same ~2.5 s per hop). They leave one every 12 px (9.6 shown
  units/s) and **enter at that same rate**, in columns as long as the send (no length cap). SIEGE keeps
  its own speeds.
- Alpha 11's troop animation: 8 rad/s hop with a phase per body (only upward), a +-0.07 roll,
  11 % squash-and-stretch (Ember and Solar softer), bodies turned three-quarters to the camera toward
  where they're going instead of along the path.
- **No RECALL in Brawl** (tap, AI and the hint); it stays in SIEGE.

**SIEGE**: the goo covers the whole platform again - a second ring out to the rim, and a low vat only
thins it slightly (it was shrinking to 40 %).

**Colours**: FFA seats take far-apart hues (red, green, blue, gold, purple, cyan, rose) with at least
0.12 of hue between any two; team modes give each team a family - cyan + green (+ blue) against
red + gold (+ rose) - so every player is still a different hue. **Emblems take the player's colour**
(badges and the top bar) instead of their faction colour.

**Phones**: the fullscreen gate is now a native page overlay (`web/fullscreen-gate.js`): PLAY
FULLSCREEN asks inside the real tap, a page already covering the screen counts as fullscreen, and
CLOSE / "continue in the browser" dismiss it for the tab (Alpha 15's stayed up after going
fullscreen and could not be closed). **Map selection scrolls with a finger swipe** (Alpha 11's touch
scroll; a swipe never picks a map, and picking keeps your place in the list).

Tested: test_sim 210 checks (new: Brawl speed / exit = entrance rate / no recall, FFA and 2v2 hue
separation), test_net 93 (new: EMPTY SEATS, a drop holds the seat, wrong token refused, reconnect
into the running round, rematch with AI or back to the lobby), every map to the end; browser (two
instances): EMPTY SEATS lobby -> FFA 3 with an AI seat, a guest dropping (AI takes over) and
RECONNECT into the same seat; phone emulation: the gate overlay and CLOSE. Not tested: the swipe
(browser emulation sends mouse, not touch) and a real phone.

## 0.16.0 "Alpha 16" - 2026-09-25 (online rooms)

**Peer-to-peer multiplayer** (Daniele: "let's start using Alpha 11 peer to peer"). Alpha 11's PeerJS
rooms, ported to 2.0 (`scripts/net.gd`, autoload `Net`, from `Game/Alpha 11/scripts/network.gd`).
- **MAIN -> ONLINE**: pick your faction, CREATE ROOM (you host) or JOIN ROOM (the host's
  four-character code, typed in a native browser field so phone keyboards paste and copy).
- **Lobby**: seats A-E in join order (host-assigned), each player's faction, open seats; the host picks
  PLAYERS (FFA 2 / 3 / 4 / 5 or 2 V 2), the map (only maps that offer that mode), SIEGE / BRAWL and
  LAST STAND; everyone picks their own view colour. SHARE CODE, CHAT, LEAVE ROOM; DEPLOY opens for the
  host when every seat is filled.
- **The host's game is the match.** Guests send their orders (send, recall, upgrade, cannon, forge,
  restore, relay switch); the host checks the seat owns the node or line, the numbers are sane, the
  round is current and the rate is under 20 a second, runs it, and answers with the same line the
  offline game toasts ("Sending 16 units to node 2", "Upgrade needs 30 units"). The host sends the
  state ~10 times a second (paths only when they change, a full keyframe every second) plus the
  one-off effects (bursts, falls, relay ticks, collapses); guests keep lines moving between updates.
- **Alpha 11 room rules**: version check (a stale cached build is refused), everyone loads before
  the clock starts, round numbers keep old orders out, REMATCH on the results screen (needs every
  player, fresh match, same room and chat), a guest leaving mid-match returns everyone to the lobby,
  the host leaving closes the room, 8 s without the host ends it. The pause menu online does not
  pause (RESUME / LEAVE ROOM); Debug is hidden online.
- **Chat**: CHAT button in the lobby and under PAUSE (with an unread count); 256 characters, 50
  messages, 5 per 10 s, sender stamped by the host as seat + faction, shown as plain text; kept
  between rounds, cleared on leaving; never pauses.
- Fixed while here: in team modes the results screen said DEFEAT to the winner's team-mate.

Tested: `tests/test_net.gd` (76 checks: every mode fills, seats, version and full-room refusals,
the loading barrier, host validation, snapshots and paths, captures, effects, chat limits, rematch,
departures) and two game instances side by side in the in-app browser (create, join, lobby, chat,
deploy, guest orders, captures, a guest leaving). Not tested: separate networks, phones, 3-5 real
players, a full match to the rematch in the browser.

Known limits (as Alpha 11): no relay server (some networks cannot connect directly), no host
migration, and a host tab in the background freezes the match for everyone.

## 0.15.0 "Alpha 15" - 2026-09-25 (Brawl and Siege)

**Two named modes** (Daniele: "new name for the mode selector is Brawl and Siege"). SIEGE = the goo
hordes that fight on bridges (tug-of-war, recall, corridors). BRAWL = Alpha 11's core rules. The
switch is on 03 SETUP (MODE / SIEGE or BRAWL), on OPTIONS, in the pause menu and in Debug. The
player-count row on setup is now called PLAYERS.

**Brawl = Alpha 11, exactly** (Daniele: "I want exactly the core rule of Alpha 11 in the no bridge
fight mode")
- Each arriving unit is resolved the moment it reaches the node, as Alpha 11's `land()`: it trades
  blows with the garrison (attack / health / garrison stats, one-for-one at baseline) and the
  survivors take the node. No siege, nobody waiting outside; waypoints are free; lines pass each
  other on bridges.
- Units walk straight in through the door and vanish (they no longer stand queued at the entrance).
- Alpha 11's half-bridge neon: each half of a bridge glows in the colour of the node it touches,
  neutral halves amber.
- Alpha 11 badges: a round badge with the count and the owner's faction emblem, counts on every node
  (as Alpha 11 did). Kit buttons for SEND and PAUSE.

**Both modes**
- **Conquest costs a tier**: a conquered vat or cannon drops one tier (minimum 1). Neutral captures
  and forges are unaffected.
- **LAST STAND ON / OFF** toggle on setup, OPTIONS and the pause menu (off: no collapse; the 7:00
  safety net still ends a stalled match).
- **HUD never covers the map**: the camera now projects every platform rim and badge and fits them
  inside the area the HUD leaves free. Badges sit just outside each platform in the gap furthest from
  its bridges. The empty ability dock is hidden until abilities exist; Debug sits under PAUSE.

**Multiplayer groundwork**: PeerJS 1.5.5 and Alpha 11's transport shim are in `web/` and loaded by
the page (room prefix `ooze20-`, up to 5 guests). The Godot side (lobby, host authority, snapshots)
is NOT built yet - next session.

## 0.14.5 - 2026-09-25

- **Overpasses where decks cross.** The roster leaves many crossings unmarked (24 maps, including
  Trident Exchange and the other maps Daniele flagged). On load, every pair of crossing decks now gets
  one raised as an overpass - a fixed deck in preference to a relay deck, the longer if both. No
  crossing on any of the 99 maps is left flat. The roster files are not edited.
- **Last Stand varies**: inward and outward orders shuffle the nodes that sit on the same ring, so the
  first node to fall changes from match to match (seeded, still never cutting the map).
- **Send controls on the left**, Alpha 11 style; Debug moved bottom-right; the camera frames the
  map in the space right of the panel with more margin.
- **Menu: one background**, full screen; the page no longer draws a second copy of the art.

## 0.14.4 - 2026-09-25

- The menu's full-screen backdrop uses the clean part of the art: on wide phone screens the old
  Alpha 11 buttons baked into the art's left edge were peeking out beside the page.

## 0.14.3 - 2026-09-25

- Fixed: the inspector's UPGRADE / CANNON / FORGE buttons printed the raw internal price (150 for a
  T3 vat) instead of the Alpha 11-scale one (30) everything else shows. The SWITCH button now says
  the real 5 s relay cooldown instead of a stale 15 s. (Daniele: "the info for upgrades of vat are
  wrong, still say 150".)

## 0.14.2 - 2026-09-25 (Daniele's mobile and readability fixes)

- **Phones play fullscreen.** In a phone browser a gate covers the game until it is fullscreen:
  Android gets a PLAY FULLSCREEN button (browsers only grant it from a tap) and landscape lock;
  iPhone/iPad Safari shows the Add to Home Screen steps, and the home-screen app now opens
  fullscreen and landscape. The gate comes back if you leave fullscreen; a small "continue in the
  browser" link is the escape hatch if detection is wrong.
- **The menu fits any screen shape**: it scales and centres instead of sitting at 1280x720 on the
  left of a wider phone screen; the backdrop fills the whole screen. Ability text wraps in its box.
- **Fixed camera**: no zoom or pan (pinch, wheel, trackpad, drag), lower angle (42 degrees, was
  55). **Every vat, cannon, forge and socket faces the viewer** on every map.
- **Relays and falls**: every deck a line overlaps is checked, not only the one under its head -
  a tail still on a deck that dissolved, retracted or collapsed falls, and a line that walked onto
  a deck mid-motion falls when the motion ends.
- **Double-tap no longer flashes the inspector**: a single tap inspects only after the double-tap
  window passes, and the release that ends a double tap is swallowed.
- **Counts easier to read**: badges hang from each platform's near rim with a bigger outlined count;
  horde labels are smaller.
- **Classic mode**: unit models take their owner's colour (three players on one faction no longer
  look alike); no garrison loitering round the vat, the platform neon shows the owner; badges carry
  Alpha 11's numbers (production per second, upgrade price) and the inspector has Alpha 11's status
  line (production, "Double-tap: N units" / MAX TIER, plus garrison / attack / speed).

## 0.14.1 - 2026-09-25 (merged maps-overpass: the whole roster, overpasses, multiplayer map prep)

- **Merged the `maps-overpass` branch** (another session's commit bd1f527) into Alpha 14. Its
  "Unreleased" notes are kept below. Combined where both changed the same code: goo corridors are
  segmented and follow overpass ramps (branch) and are always on, pour in and drain out (Alpha 14);
  the contact scan keeps Alpha 14's tug-of-war and recall and the branch's overpass rule (a line on
  an overpass only meets lines on the same deck). The battlefield page lists every map and shows
  its modes.
- **All 100 roster maps**, not only the 1v1 ones: the 17 the branch left out are in, since team and
  FFA seats exist now. 3v3 joins the mode list. 15 of them had 1v1 seats after all (the branch
  filtered on the roster's `modes` field, the seats say otherwise). Maps without a preview SVG got a
  rendered 3D thumbnail.
- **One map held back:** 030 Aurelia Siding. The roster gives its centre node no decks, so it can't
  be reached; logged in OPEN-QUESTIONS rather than hand-edited. The pool plays 99 maps.
- `tests/test_map_pool.gd` plays each map in its own mode (1v1, else its first team/FFA mode) with
  one AI per seat.

## 0.14.0 "Alpha 14" - 2026-09-25 (two modes that look and feel different, teams and FFA)

**Bridge-fight mode (BRIDGE COMBAT ON)**
- **Tug-of-war fronts.** The front no longer stands still while both lines shrink: it slides
  toward the weaker side at up to 35 % of deck speed, set by the gap in fighting weight (units x
  attack x health). 2:1 odds move it at a third of that. Rear attacks push both lines the same way.
  Pushing a fight onto a relay deck and then firing the relay is now the big play.
- **Recall.** Tap one of your own lines to turn it round: it flows back the way it came to the node
  it left, and anything still in the vat stays there. It keeps moving while an enemy is on it, so a
  pursuer still trades losses with its tail: a retreat under pressure costs, but it gets out. The AI
  recalls lines it is losing badly.
- **Goo corridors are always on** between any two adjacent nodes one player owns. Enemies on your
  goo move at 70 % speed and push at 67 % of their weight in a tug-of-war: a built-in home
  advantage. Capture either end and the corridor drains back toward the end still held.
- **No hidden shield pool.** Passing through an enemy node fights its garrison, the number on the
  badge; only an arrival captures. A near-empty garrison is a weak toll: its flat base damage fades
  in over its first 20 units. The goo ring round the tower stays and now just means "mine". The
  shield ring, badge bar and inspector line are gone.

**Classic mode (BRIDGE COMBAT OFF)**
- No goo. Sends are columns of the approved faction creature models (Alpha 11's own meshes), three
  across, one model per unit as the player counts them, each on a disc in its owner's colour.
  Garrisons stand in a ring round the tower. Lines pass each other and fight only at nodes.

**Modes and colours**
- **2v2 and FFA 3 / 4 / 5.** MODE row on the setup page, offering only the modes the map supports.
  Allies never fight each other, sending to an ally reinforces its node, and a team wins together;
  you and your team see each other's counts. Added four roster maps: 012 Ladder and 016 Concourse
  (1v1 / 2v2 / FFA4), 036 Khepri Carousel and 037 Aurelia Orbital (FFA5); Trident Exchange offers
  2v2 and FFA4, Switchback Foundry FFA3. Extra AI seats get the factions not yet taken.
- **Colour selection.** YOUR COLOUR row: cyan, green, purple, red, gold, rose, or FACTION (every
  seat in its own faction colour, Alpha 11 style; a clash falls back to the palette). Team modes
  give each team one hue, light and dark shades.

**Fixes**
- The door rate is pinned at 48 units/s. Unifying deck and platform speed in 0.13.2 had dropped it
  to 20 as a side effect, so sends trickled out and arrived too thin to take anything.
- Tests: 180 checks, including tug-of-war, recall mid-fight, corridors and drain, home advantage,
  2v2 reinforcement and AI matches in 2v2 and on both FFA5 maps.
### From the maps-overpass branch (was "Unreleased")

- **83 maps in the pool** (was the starter seven): every map in the 100-map roster whose modes list
  1v1, split from `Docs/.../02 Maps/roster/maps-100.json` into `maps/NNN-name.json` with a preview
  SVG in `assets/maps/` in the starter seven's style. `scripts/map_pool.gd` lists them (starter
  seven first, then by code); the battlefield page scrolls through all of them and describes
  roster maps by tier, layout family and overpass count. Left out until 2.0 has team/FFA seats: the
  17 maps without 1v1 in their modes (001-003, 025-030, 036, 037, 062, 092, 094-097). New maps
  show the SVG, not a 3D thumbnail (`--thumb=` renders can follow).
- **Overpass bridges are real** (GAME-RULES sec 7: "cross at different heights without joining"):
  an overpass deck is laid from the kit's `Deck_Overpass_Ramp` + `Deck_Overpass_Span` (on pylons) +
  ramp down, rising `Rules.OVERPASS_H` = 2.6 m (the kit's OVER_H). Hordes climb the ramp and run
  raised (`Sim.deck_points`); a line on an overpass only meets lines on that same deck, so the
  horde passing under it no longer fights or queues through the bridge above. The shield-bond goo
  follows the ramps. 16 pool maps have overpasses (044, 045, 049, 054, 055, 065, 066, 073, 074,
  076, 079, 081-083, 086, 100).
- `tests/test_map_pool.gd`: every pool map lays out fully and finishes an AI vs AI match with
  captures; on Oberon Keep a horde over and an enemy horde under pass the same spot without engaging.

## 0.13.2 - 2026-09-25 (Daniele's numbers)

- Deck speed 5 m/s (was 2), platform speed = deck speed (was x6), relay cooldown 5 s (was 15).
  The door rate follows the speed (20 units/s). The Debug panel's Reset to rules uses the new
  defaults. (Daniele: "relay cooldown 5 s, deck speed 5 m/s... deck and platform speed need to
  match, no point in it being different".)
- Noted for the next pass: the blob model needs a readability redo - enemy attacks are harder to
  scan than in Alpha 11 (PLAYTEST-NOTES 49).

## 0.13.1 - 2026-09-25 (Daniele: "I want the damn menu as for Alpha 11")

- **The front menu is Alpha 11's, page for page**: its backdrop art, neon-cut frames, per-faction
  kit buttons, stepper strip, wordmark and Russo One headings, at Alpha 11's own coordinates
  (scaled from its 1672x941 canvas). MAIN (NEW GAME / OPTIONS / FULLSCREEN or QUIT; TUTORIAL and
  ONLINE greyed out - not in 2.0 yet) -> 01 FACTION -> 02 BATTLEFIELD with real 3D thumbnails of
  the starter seven (`assets/map-thumbnails`, rendered by `--thumb=`) -> 03 SETUP (your faction,
  rival, difficulty, BRIDGE COMBAT where Alpha 11 had ABILITIES ON/OFF) -> DEPLOY.
- **OPTIONS page** with the match switches: bridge combat (also in the pause menu and Debug) and
  DETAIL full/low.
- **Performance**: the frame rate is capped at 60 everywhere (the menu used to spin uncapped);
  the shield is a flat ring instead of a translucent dome (13 large alpha spheres were pure
  fill-rate); DETAIL: LOW halves horde and river patches and hides the shield rings; the Debug
  FPS line now also prints draw calls and triangles for the browser console. Measured on the dev
  PC: 60 fps, ~1,900 draw calls / ~1.9 M triangles per frame on Switchback Foundry at full
  detail - the hordes and rivers, not the interface. If a machine still "runs like crazy",
  OPTIONS -> DETAIL: LOW is the test.
- `--perf` prints frame timing every 3 s; `--menu-page=` opens a menu page for screenshots.

## 0.13.0 "Alpha 13" - 2026-09-25 (Daniele: "fix and implement all the above, this will be alpha 13")

- **Factions now play differently.** Alpha 11's stat profiles are in the 2.0 sim (`Rules.FACTION_STATS`,
  GAME-RULES sec3 leans): VEX travels 15 % faster with a 10 % weaker garrison; Viridian Bloom
  produces 15 % more and moves 10 % slower; Ember Maw hits 15 % harder and produces 10 % less;
  Solar Shells take 10 % less damage, hold a 5 % stronger garrison, move and produce 10 % slower;
  NULL is baseline. Ownership colour stays the seat's (A cyan, B green) per GAME-RULES sec2 -
  faction is shape, stats and accent. (Daniele: "why have we not introduced all the factions?")
- **Alpha 11's front menu, ported**: MAIN (logo, NEW GAME, QUICK MATCH, FULLSCREEN/QUIT) ->
  01 FACTION (illustrated portrait left, stats + persistent trait middle, the three Ooze Factory
  ability slots right with the faction's ultimate from the rules, illustrated faction tabs below)
  -> 02 BATTLEFIELD (the starter seven with previews, relay kinds, what each proves, Last Stand
  methods) -> 03 SETUP (your faction card, the rival's faction - random or chosen - and the AI
  level) -> DEPLOY. Play again / main menu keep your choices. (Daniele: "why didn't we introduce
  the rest of the UX/UI, main menu, race selection?")
- **Numbers on screen are Alpha 11's again.** The sim keeps Alpha 12's army scale (hordes stay
  long) but every number the player sees is divided by 5: caps read 30 / 40 / 80 / 160, upgrades
  10 / 20 / 30, cannon 15 / 25 / 35, forge 20, production 1.0 / 1.6 / 2.4 / 3.5 per second.
  (Daniele: "big numbers don't look good".)
- **A missing deck is the void.** Units ordered across a deck that has been retracted, switched
  away or dropped since the order was given now walk off the pier and fall, pouring off at deck
  speed, instead of re-routing (v0.12.1's reading) or crossing thin air (v0.12.0). (Daniele: "even
  if a bridge got retracted, enemy units with the order to cross it still crossed it instead of
  falling in the void".)
- **Bridge combat toggle** on the setup page and in the Debug panel: ON = Alpha 12 (hordes fight
  wherever they meet, queue behind friends), OFF = Alpha 11 (hordes pass each other, fights only
  at nodes). (Daniele: "not sure combat on bridges is fun, I wanna try with and without".)
- Fixed: a fallen platform's goo river stayed floating in the void (Trident Exchange screenshot).
  Note: a relay node reading 0 is alive but empty - it has no vat, so a spent garrison stays at 0
  until fed; a retracted deck is gone by design, not fallen.
- Badges moved further out: below the rim and under the deck plane, never over a tower.
- Tests: 158 checks.

## 0.12.1 - 2026-09-25 (Daniele's first Alpha 12 playtest)

- **No horde crosses a deck that is gone.** A route is computed when the order is given; if a deck
  on it has closed (relay) or fallen (Last Stand) by the time the horde reaches that pier, it now
  re-routes from the node it stands on, or stops there (reinforce / siege) when no route is left.
  Anything already out on the missing deck falls. (Daniele: "the enemy crossed a bridge even if
  there was no bridge".)
- **The Last Stand never cuts the map into islands.** Every drop order (inward, outward, chaos) is
  built so each surviving node keeps a physical path to the final. Chaos keeps home nodes as late
  as connectivity allows and is only offered where no home would have to fall in the first half
  of the order; otherwise it falls back to inward (so it never activates on Two Piers). (Daniele:
  "the map got cut on chaos... we can't leave isolated nodes".)
- **Badges moved below the platform rim** and shrunk; the inspector ring is a ring only - the vat
  and its river stay visible. (Daniele: "the UX covers the whole vat".)
- Tests: 150 checks.

## 0.12.0 "Alpha 12" - 2026-09-25

The "bring it back to something we can call an alpha" pass (Daniele: "implement all mechanics, all
controls, all UX/UI... otherwise we don't know if our game choices are bad or not"). Everything
designed so far is now in the build; textures and better models are the only thing deliberately
left for later.

### Mechanics
- **The shield bond is the goo trail, not the bridge** (Daniele's correction of v0.6's reading):
  two adjacent nodes of one player are bonded while BOTH shields are up - the deck between them is
  covered in goo. Breaking a shield drops the bond until the shield regenerates to full; passage
  through that node is free meanwhile. No bridge is ever destroyed by a shield break any more
  (that was what left nodes isolated by the time Last Stand started).
- **Relays for real** (GAME-RULES sec8). Firing a relay starts a 3 s warning (the tower's symbol
  and the deck's lights blink to the next state's colour, a ghost of the next deck appears, the
  ring on the platform fills), then the tick moves the deck over 1.4 s and applies the per-kind
  troop fate, then 15 s cooldown. Rotation: the turntable and its deck pivot to the next pier pair
  and every horde on the deck RIDES it, re-routed from where it now points. Retract: the deck
  slides into its gate and everything on it is carried into the relay's node (own troops come home,
  enemies land as an early assault on the platform). Switch and remote: the deck dissolves and
  everything on it FALLS (a fall loss, no combat credit); the next state's deck assembles. Remote's
  console at the centre controls the diagonal decks elsewhere (lit conduits show which). Capturing a
  relay during its warning cancels the pending switch. Only NEW routes see a relay's state; a deck
  mid-motion is closed to routing.
- **Real Last Stand** (GAME-RULES sec10). Starts at 2:00 (kept, per Daniele). The method is
  hidden until then and picked from the map's eligible list (inward / outward / chaos, seeded),
  then the whole drop order is revealed on the badges (#1, #2... and FINAL). Every node gets a 10 s
  warning (red ring, threatened decks flash, countdown on its badge and in the status line), then
  it falls: the platform tumbles, its decks break into the kit's fragment pieces, goo pours over
  the rim, and everything on the node or its decks dies - garrison, siege and every horde portion
  there (they tumble into the void). The final node never drops. A seat whose last node falls is
  eliminated on the spot. Wave interval is per map (12-30 s) so the collapse ends well before the
  7:00 safety net.
- **Combat: contact anywhere, to the death** (Daniele: "whenever an enemy crosses the hitbox of a
  unit they fight... units crossing each other on a platform without a fight"). Contact detection
  is now geometric via a spatial hash over every patch of every line, on decks, piers and platform
  arcs alike: a head within one deck-width of any enemy patch engages it (frontline if the heads
  face each other, rear otherwise) and the fight lasts until one side is gone. Friendly queueing
  works the same way. A horde crossing an enemy platform whose shield is up slows to deck speed
  while it pays the shield toll, so the fight at the platform is visible.
- **Alpha 11 costs and logic for every structure** (Daniele: "start from the logic of Alpha 11...
  upgrades seem free"). Vat upgrades cost 50/100/150 units paid from the vat (Alpha 11's 10/20/30
  x5), cannon 75 to build then 125/175 per tier (15/25/35 x5), forge 100 (20 x5). Caps 150/200/
  400/800 and production 5/8/12/17.5 per second are Alpha 11's x5. A cannon bursts for 2 s killing
  up to 50/125/200 bodies (10/25/40 x5), then recharges 4/2.4/1.6 s AFTER the burst, with a beam
  and impact flash. A forge gives +50 % attack to everything its owner's troops deal (Alpha 11's
  +50 on the 100 scale); mixed garrisons weight it by population. Relay nodes have no vat and
  produce nothing (GAME-RULES sec6) - their garrison must be fed. Attachment swaps (cannon <->
  forge, vat -> cannon/forge on a final) are a 10 s rebuild with a 10 s cooldown; RESTORE VAT is
  free. Construction is visible: the new structure grows out of the socket under a turning build
  ring, with a progress bar on the badge and in the inspector.
- **AI**: three levels (Casual / Standard / Veteran) picked on the title screen - only thinking
  rate, attack margin and relay use differ, no cheats. Relays are fired to drop or redirect enemy
  hordes on the decks they control, to pull them in only when the garrison can take them, or to
  open routes - never on a blind timer. It evacuates a node under Last Stand warning and pays the
  same build costs.

### Interface (Alpha 11's, in full)
- Title screen: logo, faction picker with emblem and blurb, opponent level, the starter seven as
  cards with their map preview, node count, relay kind and what each one proves.
- Top bar with emblem, your total, timer, rivals and the strength bar; PAUSE with resume / restart /
  main menu; Last Stand countdown and status line.
- Side command panel (100/75/50/25, slide to pick) with the selected vat's send count.
- Node badges: count (never on an enemy node - seat letter only), tier or attachment, relay kind +
  state + cooldown, build countdown, shield bar (turns red while down), build bar, Last Stand drop
  order. Badges are tap targets.
- Tap any node for the ring inspector: owner, structure, units/cap, production, shield, relay
  state -> next state and readiness, cannon status, build progress, swap cooldown - with costed
  actions (UPGRADE T{n}, CANNON, FORGE, RESTORE VAT, SWITCH) that disable when unaffordable, on
  cooldown or under construction. Double-tap your own node still upgrades (Alpha 11 convention).
- Drag preview follows the real route along the decks with an arrowhead and a label (TAKE /
  ATTACK / REINFORCE · units · seconds); "NO ROUTE" in red when there is none. Every action toasts
  what happened or why it couldn't.
- Ability dock with the three Ooze Factory slots present but disabled ("coming soon") until the
  2.0 skill pools are approved. Results panel with captures, combat and fall losses, Last Stand
  method; play again / main menu. Debug panel gains a forge-bonus slider and prints FPS to the
  console every 5 s while open.

### In-world animation
- Selection ring, capture pulse, shield dome over the river (height = shield strength, flashes
  when hit, red pulse when broken, pulse when back up), exit puddle at the tank bottoms while an
  order drains out, owner-coloured deck lights on held corridors, state-coloured lights on relay
  decks and towers, relay towers on their rim ledge in the widest free gap (retract gate straddles
  the rim where its deck enters), switch piers on switched decks, remote conduits.

### Tests
- 139 headless checks (was 55): costs, swaps, restore, relay warning/tick/fates per kind, remote
  control, the shield bond, contact on a neutral platform, Last Stand method/order/warning/drop/
  elimination, AI vs AI on all seven maps with relay fires and falls.

## 0.8.0 - 2026-09-25

- **Relays are player-fired, not automatic** (Daniele: "there are no touch controls for relays...
  how do I switch them?" - GAME-RULES sec8: "on relays - fire the switch"). Owning a relay lets you
  tap it and press Switch to advance it to its next state, 15 s cooldown between fires; an
  unclaimed relay sits at its first authored state. The AI fires its own relays too.
- **Relay/attachment alignment fixed** (Daniele: "the structures on the relays are all fucked up").
  The relay housing is now centred on the node instead of guessed at a rim-ledge offset that didn't
  come across from the Blender kit's authoring; a built cannon or forge now REPLACES the centre
  slot (vat or socket) at the exact same spot instead of floating beside it.
- **Last Stand destruction animation.** A collapsed node's platform and every bridge it still has
  now fall away (sink and tumble) instead of silently vanishing - a rudimentary stand-in for the
  design's waterfall-of-ooze fall.
- **Alpha 11 look and a player/faction selector** (Daniele: "add all the part of interface that
  alpha 11 had... take away this ugly one"). Reused Alpha 11's actual panel/button recipe and font
  (Rajdhani-SemiBold) across the title screen and HUD's buttons and panels. Added a faction picker
  to the title screen (previously hardcoded to "null").

Versioned from **2026-09-25** (Daniele: "start versioning and have it in the interface and a
changelog"). The version shows bottom-right in the HUD and on the title screen. Numbering is
retroactive for the same-day passes before this file existed - each one bumps the minor number.
See `docs/BUILD-LOG.md` for the full narrative record and design rationale behind every change.

## 0.7.0 - 2026-09-25

- **Relay housings, for real.** Relay nodes now show their actual modelled tower per kind
  (`Relay_Rotation_Tower`, `Relay_Retract`, `Relay_Switch_Hub`, `Relay_Remote`) on a rim-mounted
  ledge (`Relay_Mount`), with `Socket_Attachment` in the middle instead of a vat (GAME-RULES sec6:
  a relay node has no vat). Rotation hubs also use `Platform_Rotation` instead of the standard
  platform. `retracts` and remote-state (`m1`/`m2`) decks use their own `Deck_Retract`/`Deck_Remote`
  models instead of the generic deck module.
- **Toast feedback on every tap** (Alpha 11 convention): tapping an owned node always says
  something instead of silently doing nothing.
- The build popup is styled as a ring closer to Alpha 11's circular inspector.
- Versioning: this file, plus the version number in the HUD and the title screen.

## 0.6.0 - 2026-09-25

- Transit fighting (an order passing through a node that isn't its target) now only triggers at an
  ENEMY-owned node - a neutral one is a free glide-through.
- The shield: every owned node has a shield worth 20% of its current garrison, regenerating from
  "excess minions" over time. A transiting force fights the shield, never the real garrison -
  only an actual arrival ever touches that. (The "bond breaks" reading of this version - a deck
  destroyed - was wrong; corrected in 0.12.0.)

## 0.5.0 - 2026-09-25

- A relay-controlled or retracting deck now visibly disappears while closed and reappears while
  open - relay cycling is something you can see, not just a routing change.
- Replaced the unreliable engine double-click with a manual tap timer and the Alpha 11 convention:
  single-tap an empty attachment slot to choose Cannon or Forge; double-tap upgrades whatever's
  already there (vat, or a cannon's tier).
- A transiting fight at an intermediate node gets the same goo meniscus/splash as an arrival siege,
  anchored to the platform's rim, so it reads as combat AT the platform.
- A deck between two of your own adjacent nodes is covered in your goo.
- Last Stand moved to 2:00 (was 3:00).

## 0.4.0 - 2026-09-25

- All seven starter maps playable from a title screen; every map verified fully connected with
  AI vs AI finishing.
- Rudimentary relay cycling (every relay's states cycle together every 18 s; retract decks toggle
  open/closed the same way) and rudimentary Last Stand (starts 3:00, always inward, one rim node
  every 14 s, centre never dropped; a 7:00 safety net decides by strength if still undecided) - so
  no map turtles forever.
- Fixed a stalemate bug: a node whose garrison fell under simultaneous arrival sieges from both
  seats used to stay captureless forever; now the stronger side takes it.
- Implemented the modelled structures: vat upgrade (T1-T4), a single-tier cannon (bursts enemy
  hordes in range, bypassing fight math) and forge (owner takes less damage everywhere).
- Debug panel ranges widened a lot; platform speed can go below deck speed.

## 0.3.0 - 2026-09-25

- "The whole platform is the node": arriving hordes spread onto the platform from whichever pier
  they came by; a besieged platform splits into a goo river per attacker, seamed at the fight.
- "An order passing through a node always counts as passing through that node": every waypoint on
  a route fights whoever's transiting it, at siege rates; only an arrival can capture, though.
- Units leave the vat only as the door reveals them; a new send re-spends the vat's current total.

## 0.2.0 - 2026-09-25

- Blob fight pass: the drawn line recedes smoothly with its losses; a goo meniscus with a hot seam
  merges two lines where they meet; the contact patch squashes and the front shoves and ripples;
  goo splashes off the seam with the loss rate.

## 0.1.0 - 2026-09-24

- First playable slice: Two Piers. Drag-to-send, long hordes, capture, frontline combat, a simple
  AI opponent, phone profile and web export.
