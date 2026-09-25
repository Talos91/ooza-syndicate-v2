# Next session - start here

State at the end of the 2026-09-25 sessions: **v0.16.2 "Alpha 16"** (online rooms, Alpha 11 Brawl feel, player colours, self-updating build), source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: this file,
`README.md`, the top of `CHANGELOG.md` (0.12.0 to 0.16.0), `PLAYTEST-NOTES.md` notes 26-71, then the
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

## NEXT ALPHA (Alpha 17) - Daniele, 2026-09-25: "we are going to redo all maps and change the Last Stand
mechanic". Get his new Last Stand rules and the map brief before coding. Where it lives now: maps in
`maps/` (copies of the roster `maps-100.json`, generated - never hand-edit geometry; the generator is
the roster HTML in the design package), `scripts/map_pool.gd` (the pool), `scripts/map_builder.gd`
(layout, overpasses, relays), Last Stand in `scripts/sim.gd` (`_step_last_stand`, `_start_last_stand`,
`_collapse_order`, `_drop_node`) with the HUD status line in `hud.gd` and effects in `fx.gd`;
menu thumbnails `assets/map-thumbnails/` (`--thumb=`). Online needs nothing map-specific: maps list
their seats per mode (`seats`) and the lobby offers any map with the chosen mode.

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
