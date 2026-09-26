# Next session - start here

State at the end of the 2026-09-26 sessions: **v0.18.6 "Alpha 18"** (maps 4.2 - 20 compact maps at the kit's sizes - plus the four main Alpha 11 maps A-01..A-04, per-map camera, optimization pass; on top of Alpha 17: ring Last Stand, five-level AI; Alpha 16: online rooms, visual pass), source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: `GAME-BIBLE.md` (project root - the whole game as built), this file,
`README.md`, the top of `CHANGELOG.md` (0.17.0 to 0.18.0), `PLAYTEST-NOTES.md` notes 90-100, then the
design package `Docs/Game Design/Ooze Syndicate 2.0/00 README.md` and `05 Handoff/AGENT-BRIEF.md`.

## Standing rules (Daniele)

- **Publish after every pass** that changes play or looks: commit + push `main`, export Web, copy
  `web/*.js` (PeerJS, transport, room-ui, chat-ui) into `build/web`, replace the `gh-pages` branch (recipe in `docs/BUILD-LOG.md` §10),
  verify the live `index.pck` size matches, hand back the link. Bump `Rules.VERSION` every publish.
- **Every mechanic ships with its animation, HUD readout and control** in the same pass. Only
  textures and better models may wait.
- **Start numbers from Alpha 11's logic**, shown to the player at Alpha 11 scale (`Rules.shown`).
- **BRAWL must be exactly Alpha 11's core rules**; SIEGE is where 2.0 experiments live.
- Ask before assuming what to work on; Daniele drives from his own playtests.
- Reference the design package; never hand-edit roster geometry (`maps-100.json`).

## 0.18.6 (2026-09-26): waterfall, 3:00 Last Stand, neon, badges, combat effects, maps 4.4, filters

- Sim: `_cut_range(..., reroute=false)` (relays and missing decks) keeps the vat streaming and parks the head at the
  lip, so `_check_missing_decks` pours the rest into the void; Last Stand drops still re-route (reroute true).
  `_states_of(prefix)`: a one-state remote / switch group toggles on / off. Rules: RELAY_WARNING 1.0,
  LAST_STAND_TIME 180 (every collapse ends by 4:25, 7:00 hard end).
- Look: `MapBuilder.mirror_z` (real mirrored meshes for negative-lean piers - the dark connectors); Fx `_build_neon`
  (deck halves, pier strips, platform rims; SIEGE pier stubs can be switched off with `SIEGE_PIER_STRIPES`);
  new `scripts/combat_fx.gd` (CombatFx: contest rings, tier-down, cannon laser, all from Sim state, no net
  traffic) + `shaders/beam|spark|flare|contest_ring.gdshader`; Hud fixed badges (`BADGE_SIZE`, `_place_badge`,
  `_fit_text`); main.gd `_survivor_fit` lowers the pitch (COLLAPSE_PITCH_DROP 14, _MIN 44).
- Maps 4.4 classic M-21..M-40 via `export_maps_4_2_game.py` (MW2_DIR); thumbs from the pack PNGs at 512 x 288.
- Menu: `Menu.map_filter_mode` / `map_filter_type` (static), `_filtered_maps`, `_pool_modes`.
- Open (not asked yet): the double ring on rotation platforms (kit ring + new rim); BRAWL Last Stand badges drop
  the small emblem when the sub line is long; tier-down label covers a neighbour badge for ~2 s; HEAT_RATE
  and spark rates are the agent's choice. Additive glow not yet looked at on a real phone.
- Next: discuss SIEGE with Daniele ("boring and messy").

## 0.18.5 (2026-09-26): maps 4.3 classic added

- M-01..M-20 (References/Ooze Syndicate maps 4.3 classic) baked with maps 4.2 and the Alpha 11 classics by
  `Models/2.0/export_maps_4_2_game.py` (MW_DIR). Pool: 44 maps (T, A, M, C, B, S, D groups). The re-bake
  only changes the classics' `thumbnail` metadata field (svg -> png); keep the committed classics if you
  re-bake (`git checkout -- maps4/A-*.json`) unless their pack changed.

## 0.18.4 (2026-09-26): rotation fling, ring by ring falls, Last Stand zoom, emblems, BRAWL pace

- Rotation relays fling riders (Sim._relay_fling -> fx "fling" -> Fx._fling_horde; main.gd toast;
  SeatAI rotation branch with _fling_toll / _fling_cost). Retract / switch / remote still ride
  (Sim._relay_board). BRAWL plain falls use creature bodies (Fx._fall_horde BRAWL branch).
- Last Stand: Sim._drop_sequence orders a ring's platforms (never an island, relays last, far side first),
  Sim.last_stand_queue + drop_in(id); Rules.LAST_STAND_DROP_GAP 5 s; snapshots carry the queue (ls[12]).
- Camera: main._fit_nodes / _survivor_fit / _collapse_zoom (COLLAPSE_ZOOM_DELAY 1 s, _SECONDS 1.5 s,
  _MAX 2.5 - the 2.5x limit is the agent's choice, confirm with Daniele).
- HUD: Hud.emblem_texture (mipmapped SVG copies), owner emblems replace seat letters in badges, inspector
  and toasts (regex _SEAT_WORD). Check the web build's emblems on a phone (readback fallback).
- BRAWL: Rules.BRAWL_SPEED 8.9 * 0.8 * 0.8 (5.7 m/s); UnitView pour-in (_pour per horde, BEND 1 m chord
  headings, eased facing).
- Open for Daniele: should the part of a line behind a flung / vanished deck stay on its pier (split the
  line) instead of walking off the lip (today, as for switch and Last Stand decks)?

## Maps 4.2 - built in 0.18.2 (current)

- `References/Ooze Syndicate maps 4.2`: 20 compact maps in metres at the kit's sizes, no plazas, Alpha 11
  arena scale. Baked by `Models/2.0/export_maps_4_2_game.py` (builder `build_maps_4_2_review.py`, K 1.0) into
  `maps4/` (+ `assets/maps4/thumbs`; no plaza GLBs since 4.2 has no plazas). Files keep the pack's slugs
  (`maps4/T-01-first-steps.json`). All clean; decks within 1.5 m of 4 / 8 / 12 m.
- Modes on 4.2: 1v1, FFA 3, FFA 4, 2v2. **No FFA 5, 3v3 or 2v2v2 maps** (they do not fit 160 x 80 at real
  size) - the menu and lobby grey those modes out. Ask Daniele whether to bring them back on bigger maps.
- Camera: 58 degrees on every map (taps 45-66 pt). AI curve on the 6 duel maps: Expert (75 %) came out
  below Veteran (92 %) - a small sample; watch it in play before retuning.
- Next pack: same steps (new builder / exporter copy for the pack path, bake, `--import`, LODs off in any
  new `.glb.import`, `test_maps4`, phone-fit probe -> `scripts/map_camera.gd`, full suites, publish).
  Maps 4.1 (0.18.1, 18 maps) and 4.0 (0.18.0) are in git history and `References/`. A new pack's exporter
  copy must keep reading the classics folder (below), or the A- maps drop out of the next bake.

## Alpha 11 classics A-01..A-04 - built in 0.18.3

- Daniele: "pick up the main 4 map of the alpha 11, aurora trident and the other 2". Alpha 11's own layouts
  (`Game/Alpha 11/assets/arenas/{orbital-nexus,switchback-foundry,aurora-concourse,trident-exchange}.json`; the
  4.2 maps with those names are new layouts) redrawn at the kit's sizes in a derived pack,
  `References/Ooze Syndicate maps 4.2 - Alpha 11 classics` (README there): `generator/classics.py` builds the
  JSONs from written-out positions (plain Python); `generator/embed.py` (numpy, Blender's Python) is how the
  positions were fitted (`embed.py final` re-derives them). Pool group "A", right after the tutorials.
- `export_maps_4_2_game.py` bakes the 4.2 pack and then this folder; `-- --only=A-` bakes just the classics.
  Thumbnails: the pack's SVGs rendered by Edge headless (960 x 540), downscaled to 512 x 288 into
  `assets/maps4/thumbs/A-0N.png` (4.2 schematic style).
- Seats fair by travel time (Switchback: not symmetric, tiers chosen so both seats see the same distances);
  no relays, no plazas; Orbital's hub keeps Alpha 11's eight bridges. Open questions (relay retrofits from
  MAP-DESIGN-GUIDE §10, duplicate names with 4.2, modes, any-vat cannons, centre tiers): OPEN-QUESTIONS 2026-09-26.

## Alpha 18 (2026-09-25): maps 4.0, per-map camera, optimization pass - built

- **Maps 4.0** (`References/Ooze Syndicate maps 4.0`, 160 x 80 frame): `Models/2.0/build_maps_4_0_review.py`
  (the 3.0 builder with the 4.0 frame, gen4 plaza templates and K 1.7) + `export_maps_4_0_game.py` (adds
  docks) -> `maps4/`, `assets/maps4/`. After a bake: `Godot --headless --import`, re-apply
  `generate_lods=false` / `create_shadow_meshes=false` in the new `assets/maps4/*.glb.import` (then
  reimport), `tests/test_maps4.gd`, `test_map_pool`, and the phone-fit probe (below).
- **K sweep** (`clashes / over-platform`, 109 maps): 1.4: 67/110, 1.5: 61/31, 1.6: 35/23, 1.7: 25/13
  (only B-30 and D-04), 1.8+: B-19 gains clashes. Steep piers (> 80 degrees) persist even at 3.0 on the
  ring maps: a layout property, clamped by the kit.
- **Pool**: `MapPool.WITHHELD` = B-30 (24 clashes), D-08 (not phone-fit); `MapPool.PHONE_UNFIT` = the
  3v3 / 2v2v2 maps, hidden when `MapPool.phone` (phone profile + short screen side < 600 CSS px).
- **Camera**: `scripts/map_camera.gd` (generated table, per-map pitch), `main.cam_pitch`,
  `--pitch=N` (sets `pitch_forced`). **Phone-fit probe**: run windowed as a scene (the Net autoload is
  needed): `Godot_v4.6.1-stable_win64_console.exe --path . --resolution 1266x585 res://tests/phone_fit.tscn -- out=<file> pitches=auto`
  (or `pitches=50,54,...` to sweep; `maps=C-05,...` to filter). Rule used: lowest pitch with the
  smallest tap >= 33 pt (844 pt wide phone), no badge over the HUD / screen edge, no badge collisions,
  then fewest badges touching a neighbour's platform. Final: 107 maps, 0 overflow, 0 collisions, min tap
  33.0 pt, 34 badge-touches-platform (FFA 5 / 3v3).
- **Optimization pass**: audit + fixes by two workflows (8 reviewers + skeptics; 7 file-disjoint fix
  groups, an integrator, 7 reviewers). Audit table and every applied change: CHANGELOG 0.18.0. Deferred
  (need Daniele or a measured pass): MultiMesh for moving horde patches (perf-05), AI route caching
  (ai-04), menu map-summary cache (main-06), host signalling reconnect (net-02), shadows (the sun's
  100 m shadow range is still out of reach at 1.7 m per unit; if a future pack brings the camera closer,
  goo should stop casting), phone lighting (sun.shadow_enabled off on phones changes the look slightly).
- Frame cost now (desktop, 1280x720, `--perf`, pitch 42 for comparison): C-05 SIEGE ~1,125 draw calls,
  D-09 3v3 ~1,147 (were 1,875 and 3,525 on maps 4.0 before the pass).
- The other session's uncommitted kit pieces (`assets/kit/Park_*`, `Plaza_*`, `Pier_Park*`,
  `Pier_Plaza_*`) are still untracked: add them to `exclude_filter` for the export only (as every
  publish since 0.17.0 has), never commit them for that session.

## Alpha 17 (2026-09-25): maps 3.0 (superseded by 4.0), ring Last Stand, five-level AI - built

- Maps: `Models/2.0/export_maps_3_0_game.py` bakes the approved layout (run it headless in Blender
  5.2 after any change to the pack or to `build_maps_3_0_review.py`; BUILD-LOG sec10), then
  `tests/test_maps3.gd` must pass. The game never re-plans: `MapBuilder.build3` only places pieces,
  `Sim._build_path3` / `_deck_points3` follow the baked exits and heights.
- Last Stand: `Sim._start_rings` / `_plan_waves` / `_islands` / `_step_rings`.
- AI: `scripts/seat_ai.gd` (Alpha 11 loop) + `Rules.AI_LEVELS`; `tests/test_ai_curve.gd`.
- Open (maps handoff): homes start T2 (game) vs T1 (pack); The Knot has two levels in the data (README
  says three); plaza sockets ~0.5 module apart; retract housings / switch emitters are radial pieces on
  angled exits; D-04 keeps one planner clash. The big maps render small at 3 m per unit - check on a
  phone. Last Stand starts at 2:00 (pack README says 3:00).

## Multiplayer: built in Alpha 16 (PeerJS peer-to-peer, Alpha 11's approach)

`scripts/net.gd` (autoload `Net`) + `web/peer-transport.js`, `web/room-ui.js` (code field),
`web/chat-ui.js` (chat panel). MAIN -> ONLINE -> CREATE / JOIN -> lobby -> DEPLOY by host. The host's
`Sim` is the only simulation: guests call `main.node_action` -> `Net.order` -> host `Net._execute` ->
`main.perform(seat, ...)` (the same checks and feedback lines as offline); the host streams
`Net.snapshot()` ~10 Hz and `Net.push_effects()`; guests `Net.apply_snapshot()` (fires `captured` /
`finished` like a local Sim) and `Net.predict()` between updates. Tests: `tests/test_net.gd`; two
players on one PC: `tests/duo.html` (BUILD-LOG sec10). Main's `HUMAN` is now a variable (your seat).

Still open on multiplayer:
- Real separate-network and phone tests (Daniele). No relay (TURN) server: strict networks fail.
- A host tab in the background freezes the match; 10 s later guests drop (they can RECONNECT).
- Built in 0.16.1: EMPTY SEATS (AI), RECONNECT into a held seat, 10 s host grace, REMATCH.
- Not built: seat swapping in the lobby, spectators.
- Later: Vercel (site, room list, sign-in functions) + Neon Postgres (accounts, match history,
  leaderboards, telemetry). Vercel cannot relay a live match itself (no long-lived WebSockets).

## Other open work

- **Blob readability redo** (SIEGE): enemy attacks are hard to scan (PLAYTEST-NOTES 49) - Blender
  patch generator `Models/2.0/build_horde_patches_2_0.py`.
- **Badges** now sit outside platforms in the widest gap; on dense maps some still touch a deck.
- **Abilities / Ooze Factory**: waiting on SKILLS-2.0-DRAFT approval; the dock is hidden meanwhile.
- **Team eject, halo tiers** (GAME-RULES sec11) not built.
- **Open questions for Daniele** are listed at the end of `05 Handoff/OPEN-QUESTIONS.md` (bond as
  mechanic, forge defence, cannon numbers, Last Stand 2:00 vs 3:00, speed 5 m/s vs 2 s modules,
  relay cooldown 5 s vs 15 s, chaos vs homes, map 030).
- Real-phone touch and frame rate are still unmeasured (only browser emulation).

## Gotchas

- New `class_name` scripts need `Godot --headless --import --path .` before they resolve.
- Since 0.16.2 `web/update.js` swaps in a new build by itself. If an old one still sticks, in the in-app browser clear it with
  `navigator.serviceWorker.getRegistrations()` + `caches.keys()` via the JS tool.
- `git branch -D gh-pages` locally before recreating the orphan branch (see BUILD-LOG §10).
- No system Python on this PC; use Godot headless scripts for data work.
- Files merged from other sessions may have CRLF endings - normalise before perl/sed edits.
- Autoloads are not global names inside `--script` test files: tests reach `Net` through an instance
  (`load("res://scripts/net.gd").new()`), never the `Net` identifier.
- In the in-app browser only the front tab runs its game loop; test two players with `tests/duo.html`
  (both iframes visible), and hover before clicking - Godot buttons need a mouse move first.
