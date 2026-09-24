# Ooze Syndicate 2.0

Fresh Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network
game. Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

## The starter seven

A title screen lists all seven starter maps in build order; pick one to play (or skip it with
`--map=res://maps/<file>.json`). Every map is built from its roster JSON with the Blender kit, at
honest lengths (1 deck module = 4 m = 2 s; piers count as part of the platform). Relay-controlled
and retract decks cycle open/closed together every 18 s (rudimentary - the real per-map relay art
and behaviour isn't built); a rudimentary Last Stand starts at 3:00 and collapses the rim inward so
no match is eternal, with a 7:00 safety net if it still somehow is.
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
- Owned vats produce up to their cap; double-tap an owned node to upgrade its vat, or build a
  cannon (bursts enemy hordes in range, bypassing fight math) or forge (owner takes less damage
  everywhere) where the map allows it - pick which with the Upgrade/Cannon/Forge buttons. Seat B+
  is a simple AI with the same options, no cheats.
- Ownership = material: seat-colour lights, vat ooze, goo; creature body hue = seat, race = accent.
- Per-match telemetry JSON in `user://telemetry/`.

All tunable numbers are in `scripts/rules.gd`; army numbers there are PROVISIONAL placeholders.
Not in this slice yet: real per-map relay art/behaviour, abilities, real Last Stand (method choice,
hidden reveal, falls), attachment swap/cooldown, cannon T2/T3, multiplayer, pinch-zoom on touch.

## Play the current build

**https://talos91.github.io/ooza-syndicate-v2/** - the web export of `main`, published to the `gh-pages`
branch after every pass that changes play or looks (see `docs/BUILD-LOG.md` §10). Phone: open in
Safari/Chrome, landscape. **After a new publish, reload twice**: the PWA service worker serves the
cached build first and fetches the new one in the background (the top-left clock restarting at 0:00
with the new feature visible tells you it landed).

**Debug panel** (bottom-left `Debug` button, live, resets on reload, wide ranges): deck speed
(0.2-30 m/s), platform speed (0.1-30x deck - can go slower than the deck, not just faster), door
rate (1-500 units/s) and platform fight (0.05-20x combat rate) sliders, plus Reset to rules.

## Run

```
Godot_v4.6.1-stable_win64.exe --path .                          # play: pick a map from the title screen
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps/008-strait.json   # play one map directly
Godot_v4.6.1-stable_win64.exe --path . -- --demo                # AI vs AI, skips the title screen
Godot_v4.6.1-stable_win64.exe --path . -- --demo --shots=9,24 --out=C:/tmp
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
```

Godot is in `Tools/Godot` of the project folder.

See **docs/BUILD-LOG.md** for the full record of what was built and every decision taken.

## Layout

| Path | What |
|---|---|
| `scripts/rules.gd` | every number: kit sizes, speeds, caps, production, combat, colours, relay/Last Stand/structure timings |
| `scripts/sim.gd` | rules and state, no visuals (routes, paths, production, capture, frontlines, relay cycling, Last Stand, structures) |
| `scripts/map_builder.gd` | honest layout from map JSON, kit placement, ownership materials, vat-tier/attachment swap |
| `scripts/horde_view.gd` | hordes as patch chains |
| `scripts/mats.gd`, `shaders/creature.gdshader` | seat materials, creature hue shift + race rim |
| `scripts/seat_ai.gd`, `scripts/telemetry.gd` | opponent (routing + structures), match log |
| `scripts/main.gd` | world, camera, input (drag to send, double-tap to build), HUD, map-select title screen, demo/screenshot mode |
| `assets/kit`, `assets/horde` | GLBs exported from `Models/2.0/OozeKit-2.0.blend` and `OozeHordePatches-2.0.blend` |
| `maps/` | the starter seven (copies of the roster JSON) - all seven playable |
| `tests/test_sim.gd` | headless rules checks |
