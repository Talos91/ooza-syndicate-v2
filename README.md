# Ooze Syndicate 2.0 - Alpha 13

Fresh Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network
game. Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

## What Alpha 13 is

Every mechanic and every piece of interface designed so far, in one build, so the game's choices
can finally be judged (Daniele, 2026-09-25). Textures and better models are deliberately later.

- **Front menu** (Alpha 11's): NEW GAME -> 01 FACTION (illustrated portrait, stats, persistent
  trait, the three Ooze Factory slots, faction tabs) -> 02 BATTLEFIELD (the starter seven with
  previews and what each proves) -> 03 SETUP (rival faction, random or chosen; Casual / Standard /
  Veteran) -> DEPLOY. Factions differ in stats (Alpha 11's leans: VEX faster / weaker garrison,
  Bloom more production / slower, Ember harder-hitting / less production, Solar tougher / slower).
- **Numbers on screen** are Alpha 11's (caps 30/40/80/160, upgrades 10/20/30, cannon 15/25/35,
  forge 20): the sim runs at five times that so the hordes stay long, and every displayed count is
  divided by `Rules.SCALE`.
- **Sending**: drag from your node to any node; 100 / 75 / 50 / 25 % on the side panel (slide a
  finger across them); the preview follows the real route along the decks with an arrowhead and
  TAKE / ATTACK / REINFORCE · units · seconds. Hordes are long lines of goo + creatures that leave
  the vat only as the door reveals them (a puddle swells at the tank bottoms meanwhile), flow along
  the decks, curve around every tower they pass and land on the destination's platform.
- **The whole platform is the node.** A ring of goo rivers the tower; arrivals fight the garrison
  there and the node flips when it falls. Own nodes: reinforce.
- **Contact anywhere, to the death.** A horde's head touching any part of an enemy line - on a
  deck, a pier or a platform arc - starts a fight that ends when one side is gone (frontline if
  the heads face each other, rear attack otherwise). Friends queue behind friends.
- **The shield and the bond.** An owned node's shield is 20 % of its garrison, regenerating. A
  force passing through an enemy node fights the shield (slowed to deck speed while it does), never
  the garrison; if the shield breaks, passage is free until it regenerates to full. Two adjacent
  nodes of one player are **bonded** while both shields are up: the deck between them is covered
  in their goo. A broken shield drops the bond - the goo trail, not the bridge.
- **Structures, Alpha 11 logic x5.** Tap a node for the ring inspector; double-tap your own node to
  upgrade. Vat T1-T4 (50 / 100 / 150 units, paid from the vat, 10 s build, the new tier grows out
  of the socket under a build ring). Relay and final nodes take a **cannon** (75, then 125 / 175
  per tier: a 2 s beam burst kills up to 50 / 125 / 200 bodies, recharge 4 / 2.4 / 1.6 s after)
  or a **forge** (100, single tier, +50 % attack for everything you deal). Swaps are a 10 s rebuild
  with a 10 s cooldown; RESTORE VAT is free. Relay nodes have no vat: their garrison must be fed.
- **A missing deck is the void.** Units ordered across a deck that was retracted, switched away or
  dropped after the order walk off the pier and fall.
- **Relays** (rotation ↻, retract ⇤, switch ⇄, remote ⌁): tap yours, press SWITCH. 3 s warning
  (lights and symbol blink to the next state's colour, a ghost of the next deck appears), the deck
  moves, 15 s cooldown. Rotation: the turntable pivots and troops ride the deck. Retract: the deck
  slides into the gate and troops on it are carried into that node (enemies as an early assault).
  Switch / remote: the deck dissolves and troops on it fall. Capturing a relay during its warning
  cancels the switch.
- **Last Stand** at 2:00: the method (inward / outward / chaos, from the map's list) is hidden
  until then, then the drop order shows on every badge. 10 s warning per node (red ring, flashing
  decks, countdown), then the platform and its decks fall - fragments, a waterfall of goo - and
  everything on them dies. The final never falls; a seat that loses its last node is out. 7:00
  safety net if it still isn't decided.
- **HUD** (Alpha 11's): top bar with emblem, your total, timer, rivals and strength bar; PAUSE
  (resume / restart / menu); badges with count (never on enemy nodes), tier or attachment, relay
  state and cooldown, build and shield bars; toasts on every action; results with stats. The
  ability dock's three slots are present but disabled until the 2.0 skill pools are approved.
- Per-match telemetry JSON in `user://telemetry/` (sends, captures, relay fires, falls, Last Stand).

All tunable numbers are in `scripts/rules.gd`. Army numbers follow Alpha 11 x5 and are PROVISIONAL.
Not in Alpha 13: abilities (pending approval), multiplayer / team modes, overpasses, Big Drop and
Production Halt variants, real-phone measurement (see below), textures.

## Play the current build

**https://talos91.github.io/ooza-syndicate-v2/** - the web export of `main`, published to the `gh-pages`
branch after every pass that changes play or looks (see `docs/BUILD-LOG.md` §10). Phone: open in
Safari/Chrome, landscape. **After a new publish, reload twice**: the PWA service worker serves the
cached build first and fetches the new one in the background (the version bottom-right tells you
which build you have).

**Debug panel** (bottom-left `Debug` button, live, resets on reload, wide ranges): deck speed,
platform speed, door rate, platform fight rate and forge bonus sliders, Reset to rules, and an FPS
line printed to the browser console every 5 s while it is open.

## Run

```
Godot_v4.6.1-stable_win64.exe --path .                          # play: title screen
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps/008-strait.json --ai=Veteran
Godot_v4.6.1-stable_win64.exe --path . -- --demo --seed=3       # AI vs AI, skips the title screen
Godot_v4.6.1-stable_win64.exe --path . -- --demo --shots=9,24 --out=C:/tmp
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps/010-first-switch.json --scenario=switch --zoom=40
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
```

Scenarios (`--scenario=`): `fight`, `rear`, `queue` (Two Piers deck contacts), `build` and
`inspect` (Strait, node 1), `switch` (First Switch), `rotate` (Switchback Foundry).
Godot is in `Tools/Godot` of the project folder.

See **docs/BUILD-LOG.md** for the full record of what was built and every decision taken.

## Layout

| Path | What |
|---|---|
| `scripts/rules.gd` | every number: kit sizes, speeds, caps, costs, combat, colours, relay/Last Stand/structure timings |
| `scripts/sim.gd` | rules and state, no visuals (routes, paths, production, capture, contacts, shield bond, relays with warning/tick/fates, Last Stand, structures) |
| `scripts/seat_ai.gd` | opponent levels; hazard-aware relay use; cost-aware building |
| `scripts/map_builder.gd` | honest layout from map JSON, kit placement, ownership materials, state colours, relay ledges, conduits |
| `scripts/horde_view.gd` | hordes as patch chains, fight look, rivers, bond corridors, exit puddles |
| `scripts/fx.gd` | in-world effects: construction, shield dome, cannon beam, relay warning/motion, Last Stand warning and falls |
| `scripts/hud.gd` | the interface: top bar, pause, side panel, badges, inspector, dock, toasts, results, debug |
| `scripts/main.gd` | title screen, world, camera, input (drag / tap / double-tap / pan / pinch), orchestration |
| `scripts/mats.gd`, `shaders/creature.gdshader` | seat materials, state colours, effect materials, creature shader |
| `scripts/telemetry.gd` | match log |
| `assets/kit`, `assets/horde`, `assets/maps`, `assets/ui` | GLBs from the Blender kit and patches, map preview SVGs, emblems and logo |
| `maps/` | the starter seven (copies of the roster JSON) |
| `tests/test_sim.gd` | 139 headless rules checks |
