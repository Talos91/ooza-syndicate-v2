# Ooze Syndicate 2.0

Fresh Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network
game. Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

## First slice: Two Piers (starter map 1)

- Map built from `maps/004-two-piers.json` with the Blender kit, at honest lengths
  (1 deck module = 4 m = 2 s; piers count as part of the platform).
- Drag from one of your nodes to any node to send; side buttons set 25 / 50 / 75 / 100 %.
- Hordes are long lines of patches (goo + creatures) that leave the vat only as the door reveals
  them (still-inside units stay orderable), flow along the decks, curve AROUND the centre structure
  of every node they pass, and land on the destination's platform from whichever pier they came by.
- **The whole platform is the node.** A ring of goo rivers the tower, owned or split by whoever is
  fighting there; a besieged platform's garrison is beaten down where it stands, then the node
  flips and the survivors become the new garrison. Own nodes: reinforce.
- **No free glide through a node.** Every waypoint on a route - not just the final target - fights
  whoever is currently passing through it, at the same rates as a real siege. Only an arrival can
  capture a node, though: grinding a waypoint's garrison to zero while merely passing through
  leaves it undefended but still owned by whoever held it.
- Opposing hordes meeting on a deck stop at a frontline and fight.
- Owned vats produce up to their cap. Seat B is a simple AI.
- Ownership = material: seat-colour lights, vat ooze, goo; creature body hue = seat, race = accent.
- Per-match telemetry JSON in `user://telemetry/`.

All tunable numbers are in `scripts/rules.gd`; army numbers there are PROVISIONAL placeholders.
Not in this slice yet: relays, vat upgrades, cannons/forges in play, abilities, Last Stand,
multiplayer, pinch-zoom on touch.

## Play the current build

**https://talos91.github.io/ooza-syndicate-v2/** - the web export of `main`, published to the `gh-pages`
branch after every pass that changes play or looks (see `docs/BUILD-LOG.md` §10). Phone: open in
Safari/Chrome, landscape. **After a new publish, reload twice**: the PWA service worker serves the
cached build first and fetches the new one in the background (the top-left clock restarting at 0:00
with the new feature visible tells you it landed).

**Debug panel** (bottom-left `Debug` button, live, resets on reload): deck speed (m/s), platform
speed (x deck), door rate (units/s) and platform fight (x combat rate) sliders, plus Reset to rules.

## Run

```
Godot_v4.6.1-stable_win64.exe --path .                          # play
Godot_v4.6.1-stable_win64.exe --path . -- --demo                # AI vs AI
Godot_v4.6.1-stable_win64.exe --path . -- --demo --shots=9,24 --out=C:/tmp
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
```

Godot is in `Tools/Godot` of the project folder.

See **docs/BUILD-LOG.md** for the full record of what was built and every decision taken.

## Layout

| Path | What |
|---|---|
| `scripts/rules.gd` | every number: kit sizes, speeds, caps, production, combat, colours |
| `scripts/sim.gd` | rules and state, no visuals (routes, paths, production, capture, frontlines) |
| `scripts/map_builder.gd` | honest layout from map JSON, kit placement, ownership materials |
| `scripts/horde_view.gd` | hordes as patch chains |
| `scripts/mats.gd`, `shaders/creature.gdshader` | seat materials, creature hue shift + race rim |
| `scripts/seat_ai.gd`, `scripts/telemetry.gd` | opponent, match log |
| `scripts/main.gd` | world, camera, input, HUD, demo/screenshot mode |
| `assets/kit`, `assets/horde` | GLBs exported from `Models/2.0/OozeKit-2.0.blend` and `OozeHordePatches-2.0.blend` |
| `maps/` | the starter seven (copies of the roster JSON) |
| `tests/test_sim.gd` | headless rules checks |
