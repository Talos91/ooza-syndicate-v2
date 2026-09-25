# Next session - start here

State at the end of the 2026-09-25 marathon session: **v0.15.0 "Alpha 15"**, source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: this file,
`README.md`, the top of `CHANGELOG.md` (0.12.0 to 0.15.0), `PLAYTEST-NOTES.md` notes 26-70, then the
design package `Docs/Game Design/Ooze Syndicate 2.0/00 README.md` and `05 Handoff/AGENT-BRIEF.md`.

## Standing rules (Daniele)

- **Publish after every pass** that changes play or looks: commit + push `main`, export Web, copy
  `web/*.js` into `build/web`, replace the `gh-pages` branch (recipe in `docs/BUILD-LOG.md` §10),
  verify the live `index.pck` size matches, hand back the link. Bump `Rules.VERSION` every publish.
- **Every mechanic ships with its animation, HUD readout and control** in the same pass. Only
  textures and better models may wait.
- **Start numbers from Alpha 11's logic**, shown to the player at Alpha 11 scale (`Rules.shown`).
- **BRAWL must be exactly Alpha 11's core rules**; SIEGE is where 2.0 experiments live.
- Ask before assuming what to work on; Daniele drives from his own playtests.
- Reference the design package; never hand-edit roster geometry (`maps-100.json`).

## Next priority: multiplayer (Daniele: "let's start using Alpha 11 peer to peer")

Plan agreed: **PeerJS peer-to-peer now**, Vercel + Neon later (Vercel for site / room list /
sign-in functions, Neon Postgres for accounts, match history, leaderboards, telemetry). Vercel cannot
relay a live match itself (no long-lived WebSockets).

Done: `web/peerjs.min.js` (1.5.5) and `web/peer-transport.js` (Alpha 11's shim, prefix `ooze20-`, up
to 5 guests) are loaded by the page (`export_presets.cfg` head_include).

To build (port `Game/Alpha 11/scripts/network.gd`, the P2P half):
1. `scripts/net.gd` autoload: host/join via `JavaScriptBridge.get_interface("OozePeer")`, 4-letter
   room codes, roster (seat, faction, team), lobby publish, host-assigned seats, version check,
   rate limits, loading barrier, round epochs, rematch, chat (256 chars, 50 history).
2. Host authority: the host's `Sim` is the only simulation. Guests send commands (send, recall,
   upgrade, build, switch, restore) validated by the host; the host broadcasts compressed snapshots
   (nodes, hordes, relay/Last Stand state) ~10 Hz; guests render snapshots with light prediction.
3. Menu: enable ONLINE on MAIN -> CREATE ROOM / JOIN (code) -> lobby (players, faction, mode,
   map, SIEGE/BRAWL, Last Stand) -> DEPLOY by host.
4. Guest departure returns others to the lobby; host departure closes the room (Alpha 11 rules).
5. Test with two browser tabs; do not claim cross-network or phone validation.

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
- The PWA cache serves stale builds; in the in-app browser clear it with
  `navigator.serviceWorker.getRegistrations()` + `caches.keys()` via the JS tool.
- `git branch -D gh-pages` locally before recreating the orphan branch (see BUILD-LOG §10).
- No system Python on this PC; use Godot headless scripts for data work.
- Files merged from other sessions may have CRLF endings - normalise before perl/sed edits.
