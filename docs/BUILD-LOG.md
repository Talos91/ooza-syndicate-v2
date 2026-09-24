# Ooze Syndicate 2.0 — build log

**Sessions of 2026-09-24 → 2026-09-25** · Daniele (design) with Claude (build)

From a design package to a playable phone prototype in one stretch: the 2.0 direction was adopted,
the whole 3D kit was built in Blender, the horde was reinvented as a long blob, and a fresh Godot
project now plays Two Piers in a phone browser.

> Design authority stays in the Drive package `Docs/Game Design/Ooze Syndicate 2.0/`
> (rules, maps, parameters, open questions). This log records what was built and every decision
> taken along the way, so the next session can start cold.

---

## Contents

1. [Where things live](#1-where-things-live)
2. [Decisions taken](#2-decisions-taken)
3. [The Blender kit](#3-the-blender-kit)
4. [The horde](#4-the-horde)
5. [The Godot prototype](#5-the-godot-prototype)
6. [Phones](#6-phones)
7. [Findings that shaped the build](#7-findings-that-shaped-the-build)
8. [Open questions](#8-open-questions)
9. [What's next](#9-whats-next)
10. [How to run things](#10-how-to-run-things)

---

## 1. Where things live

| What | Where |
|---|---|
| Design package (authority) | `H:\My Drive\PROJECTS\Ooze Syndicate\Docs\Game Design\Ooze Syndicate 2.0\` |
| Blender kit generator | `Models/2.0/build_kit_2_0.py` → `Models/2.0/OozeKit-2.0.blend` |
| Horde patches + behaviour boards | `Models/2.0/build_horde_patches_2_0.py` → `Models/2.0/OozeHordePatches-2.0.blend` |
| Early horde look test | `Models/2.0/build_horde_2_0.py` → `Models/2.0/OozeHorde-2.0.blend` (superseded by patches) |
| Godot project (this repo) | `Game/2.0` · github.com/Talos91/ooza-syndicate-v2 |
| Playtest notes | `PLAYTEST-NOTES.md` (this repo) |
| Legacy game | `Game/Alpha 11` — untouched, still playable |

The Blender files are **generated**: change the numbers at the top of a script and re-run it inside
Blender (`exec(open(r"<script>", encoding="utf-8").read())`); the file rebuilds from scratch.

---

## 2. Decisions taken

Every design call Daniele made during the sessions, in order. All are written into the design package.

### Direction
- **2.0 supersedes everything.** Much of Alpha 11 is outdated or wrong for 2.0; all root docs, the
  agent instructions and the old design docs were re-pointed or marked superseded.
- **Fresh project**, not a stripped Alpha 11: `Game/2.0` with its own repo.
- **Mobile first.** Targets: major Samsung and Apple phones in landscape (~19.5:9).

### Geometry
- **Travel time counts deck modules only** — piers/connectors belong to the platform, so S : M : L
  stays 1 : 2 : 3 (a retracting deck retracts at the socket, so the maths holds).
- **Keep the blockout detail level for now** — silhouettes, lights and colour carry on a phone;
  a detail pass (greebles, baked normals) waits until sizes lock.
- **Rewrite maps that don't fit** honest lengths rather than forcing them.

### Structures
- **Vat T4** = the central column itself becomes a tall glass vat (approved lineup).
- **Laser tower** (stacked glowing rings, T1–T3) replaces the old swivel-turret placeholder,
  which animated badly. **Forge** from the Faction Industry T3 sheet, single tier.
- **Relay nodes**: the cannon/forge sits **in the middle, like a vat**; the relay's own tower stands
  on a **ledge bolted outside the rim**, so the blob never crashes into it.
- **Retract** is a socket that pulls the deck in and out — its gate must be **hollow**.
- **Relay identity**: the rules' symbols ↻ ⇤ ⇄ ⌁ on each tower; **state colours** from the roster
  legend (r1 yellow · r2 orange · r3 pink · retract red · s1 white · s2 lavender · m1 pink · m2 mint).

### Hordes
- A horde is **one blob**, not single units — sprites/patches stand for many units.
- Inside the blob: **many creatures of mixed sizes, mostly tiny**, unified by the goo.
- **Creature body hue = seat colour; race colour = accent.**
- **Blobs block the deck**: attacks from **any direction** — frontline, **rear attack**, friendly queue.
- **Length is the count** — the Mushroom Wars horde feeling without its endgame chaos. A long line
  on its way tells you to split the next send (25 / 50 %).
- **Falls are waterfalls of ooze** — epic, with faces visible.
- **Enter through the door; exit by draining from the tank bottoms.**

---

## 3. The Blender kit

One platform, three node categories, structure = model, ownership = material.

### Placeholder sizes (`build_kit_2_0.py`, top of file)

| | |
|---|---|
| Platform diameter | 12 m |
| Deck width | 2.8 m (one width for every deck) |
| One module (S) | 4 m = 2 s at base speed; M = 2, L = 3 modules |
| Pier / connector | 1.6 m, concave end fits the rim **at any angle** |

The rim is plain all the way round — 56 % of the roster's bridge directions are off 45° steps, so
fixed sockets could never work. Neighbouring bridges ~30° apart still fit (a bridge takes ~27° of rim).

### Pieces

| Group | Pieces |
|---|---|
| Nodes | `Platform_Standard`, `Platform_Pillar` (column into the void, never falls), `Platform_Rotation` (turntable, gear ring, flush pivot), `Socket_Attachment` |
| Bridges | `Pier_Connector`, `Deck_S` (M/L = 2/3 modules), `Deck_Remote`, `Deck_Retract` (telescoping), `Deck_Overpass_Ramp` + `Deck_Overpass_Span` (2.6 m rise, pylons into the void), `Deck_S_Frag_*` (fall pieces) |
| Structures | `Vat_T1`–`Vat_T4`, `Cannon_T1`–`T3` (laser tower), `Forge` |
| Relays | `Relay_Retract` (hollow tunnel gate), `Relay_Switch_Hub` + `Pier_Switch`, `Relay_Remote` (+ lit conduits), `Relay_Rotation_Tower`, `Relay_Mount` (rim ledge) |
| Special | `Anchor_Stub` (temporary bridge), `Pier_Eject` (team modes) |
| Materials | neutral + seats A–F + team light/dark shades; relay state colours; construction / expiry for temp bridges |

### Demo scenes in the kit file
Two Piers · a 3-way node · every relay (current state solid, next state as a tinted ghost) ·
overpass crossing · temporary bridge (build / expiry) · fall cascade · eject bridge ·
**roster maps 055 Halcyon Siding and 082 Halcyon Gantry** built from their JSON.

---

## 4. The horde

### From look test to patches
1. First test: a seat-coloured metaball blob with a few creatures — too much goo, too few creatures.
2. Then: many creatures, mostly tiny, a thin goo film — the horde look.
3. Now: **patches**. One patch = a 2.3 m chunk of goo + ~16 creatures merged into **one mesh with
   two material slots** (goo = seat colour; creatures = seat hue + race rim). Per faction: head,
   body ×3, tail, plus light copies of the body.

| Patch | Polys | Creatures |
|---|---|---|
| full detail (head + next one) | ~5–9 k | large ones keep a 40 % copy — **faces read** |
| light body (`*_lod1`) | ~2.2 k | low-detail copies only |

A 100-unit horde ≈ 43 k polygons.

### Behaviour board (Blender, `OozeHordePatches-2.0.blend`)
1. straight run · 2. **crossing a node — the chain flows around the vat** (arc 3.8 m, never through it) ·
3. riding a rotation mid-turn · 4. overpass over a second horde · 5. frontline squash and splash ·
6. fall · 7. entering a node · 8. pull on a retracting deck · 9. LOD row.

### Waterfall board — every fall is a waterfall of ooze
| | |
|---|---|
| A | switch dissolves under a horde — the whole horde drops as a curtain |
| B | retract — momentum pours it off the moving end like a tap |
| C | rotation into the void — off the tip and the leading edge |
| D | overpass destroyed — onto the lower deck, splash, then off its sides |
| E | Last Stand — a dropping node pours over its rim all the way round |
| F | in through the door, out by draining from the tank bottoms |
| G | **meat grinder** — the rotating deck mid-sweep flings its hordes in a spiral |
| H | attacking a building — ring it, leap at the tanks, beat the garrison down |
| I | laser tower vs the blob — the burst blows a gap in the chain |

---

## 5. The Godot prototype

Godot 4.6.1 · GL Compatibility · **Two Piers**, the first of the starter seven.

### What plays
- **All seven starter maps** (pass of 2026-09-25, PLAYTEST-NOTES 11): a title screen lists them in
  build order; pick one to play it exactly like Two Piers. Relay-controlled and retract decks are
  drawn/simulated as ordinary fixed open decks (the real per-map relay art/behaviour is later).
  `--map=` on the command line (or `--demo`/`--scenario`/`--shots=`) skips the menu as before.
- **Rudimentary relay cycling and Last Stand** (same pass, PLAYTEST-NOTES 12 - "without them the
  game is eternal, test with the real maps even if rudimentary", Daniele): every relay state prefix
  (rotation/switch/remote) on a map cycles together every `Rules.RELAY_PERIOD` (18 s); a `retracts`
  deck toggles open/closed on the same period - only fresh pathfinding respects this, an in-flight
  horde keeps going. Last Stand starts at 3:00, always the "inward" method, one rim node dropped
  every 14 s, centre never dropped; a 7:00 safety net decides the match outright by total strength
  if it still hasn't ended by conquest. Also fixed: a node whose garrison falls under simultaneous
  arrival sieges from BOTH seats used to stay captureless forever - now the stronger side takes it.
- **Structures** (same pass, PLAYTEST-NOTES 13 - "implement all we have already model wise... all
  structures and their functions"): vat upgrade (T1-T4, 10 s build), a single-tier cannon (bursts
  10 units off an enemy horde within 10 m every 4 s, bypassing fight math) and forge (owner takes
  15% less damage everywhere). Double-tap an owned node to act on it; the Upgrade/Cannon/Forge
  buttons (side HUD) pick which. AI has the same options, no cheats.
- **Debug panel ranges widened a lot, platform speed can go below deck speed** (same pass -
  Daniele: "increase the limits... by a lot... platform filling speed lower than deck speed"): deck
  speed 0.2-30 m/s, platform speed 0.1-30x deck, door rate 1-500 units/s, platform fight 0.05-20x.
- **Switch feedback, Alpha 11 tap convention, corridor goo** (pass of 2026-09-25, PLAYTEST-NOTES
  15-19): a relay-controlled or retracting deck now visibly disappears while closed and reappears
  while open, so cycling is something you SEE. Replaced the unreliable engine double-click with a
  manual tap timer and the Alpha 11 interaction: single-tap an empty attachment slot opens a
  Cannon/Forge popup; double-tap upgrades whatever's there (vat, or a cannon's tier T1-T3). A
  transiting fight at an intermediate node now gets the same meniscus/splash as an arrival siege,
  anchored to the platform's rim, so it reads as combat AT the platform instead of generic
  corridor attrition. A deck between two of your own nodes is covered in your goo. Last Stand moved
  to 2:00 (was 3:00). Confirmed already-working: blobs always fight when they cross (deck contact
  has no gap), a platform's goo river counts as a blob, and several attackers can share one target.
- Map built from `maps/004-two-piers.json` with the kit GLBs, at **honest lengths**.
- **Drag** from your node to any node to send; **25 / 50 / 75 / 100 %** buttons.
- Routes along the deck network (fastest by deck time).
- **Long hordes**: a send streams out of the vat as one line; **length = size**
  (0.25 m per unit, 40 m cap, then thicker); arrival pours in over time; the line shrinks with
  losses, thickens where it piles up, tapers at the tail.
- Paths leave from the tank bottoms, curve **around** every node's structure, enter through the door.
- **Capture**: the garrison is beaten down, then the node flips; own nodes are reinforced.
- **Contact from any direction** on a deck: frontline, rear attack, friendly queue; several fights at once.
- **The whole platform is the node** (pass of 2026-09-25, PLAYTEST-NOTES 9): arriving hordes spread
  onto the platform from whichever pier they came by, up to the tower's footprint, instead of
  funnelling through one door point. A besieged platform splits into each side's share of a goo
  **river** ringing the tower, seamed with the fight's meniscus/splash where shares meet; the node
  flips when the garrison falls, survivors become the new garrison. Sends still start their
  animation at the tower and flow out through the ring toward whichever pier leads to the target.
- **Units leave the vat only as they become blob** (same pass, note 8): a send is an order the vat's
  door reveals at `Rules.door_rate` units/s; units not yet revealed stay in the vat's count and are
  still orderable - a new send re-spends the vat's current total, cutting the old order down to
  whatever already left.
- **No free glide through a node** (pass of 2026-09-25, PLAYTEST-NOTES 10): a route's intermediate
  waypoints are not scenery - every node a horde's line currently overlaps, not just its final
  target, counts its present units as an attacking force there, fought at the same rates as a real
  siege. A weak waypoint costs the passing force some losses; a strong one can wipe it out before
  it reaches its destination. Only an actual arrival captures a node, though - transit combat alone
  can grind a garrison to zero without flipping ownership (design call: the alternative let an
  unrelated order, e.g. a rear-attack pursuer, get hijacked into conquering a waypoint instead of
  reaching its real target). Friendly waypoints are a pure pass-through, matching GAME-RULES §6.
- **Blob fights read as blob fights** (pass of 2026-09-25): the drawn line trails the real count by a
  fraction of a second and recedes from the contact as it loses units, thinning as it empties; every
  contact grows a goo **meniscus** (two lobes of the two owners' goo joined by a hot seam; one colour
  for a friendly queue) so the lines merge into one mass; the patch in contact is **squashed** (board
  case 5), the front of the line **shoves** (rock back, lunge), a pressure ripple runs down the line,
  and goo **splashes** off the seam in proportion to each side's loss rate. A rear attack does the same
  to the caught horde's tail.
- Production up to the vat cap · simple AI opponent · count badges (never on enemy nodes).
- **Ownership = material** at runtime; creature hue-shift + race-rim shader.
- **Telemetry** per match (duration, sends, captures, deciding event, winner-was-behind, losses)
  → `user://telemetry/`.

### Debug panel (2026-09-25, growing)
Bottom-left `Debug` button opens live sliders for playtests, thumb-sized, reset on reload, WIDE
ranges on purpose (a real debug tool needs room past "reasonable" - Daniele, 2026-09-25): deck
speed (0.2-30 m/s), platform speed (0.1-30x deck - can go BELOW 1x, i.e. slower than the deck, not
just faster), door rate (1-500 units/s), platform fight (0.05-20x combat rate) -
`Rules.deck_speed` / `node_speed_mult` / `door_rate` / `node_fight_mult` are static vars for this -
plus "Reset to rules". Add further debug controls here (`_build_debug` in `main.gd`). Playtest
builds carry the panel; it is not a player feature.

### Code map
| File | Role |
|---|---|
| `scripts/rules.gd` | every number (kit sizes, speeds, caps, production, combat, colours, relay/Last Stand/structure timings) |
| `scripts/sim.gd` | rules and state, no visuals; nodes carry `streaming`/`siege`/`siege_dir`/`transit`/`attachment`/`build_kind`; relay cycling, Last Stand, cannon/forge/vat upgrade |
| `scripts/map_builder.gd` | honest layout, kit placement, ownership materials, vat-tier/attachment model swap |
| `scripts/horde_view.gd` | hordes as long patch lines; fight look (eased shrink, meniscus, shoves, splash); platform rivers |
| `scripts/mats.gd`, `shaders/creature.gdshader` | seat materials, creature shader |
| `scripts/seat_ai.gd`, `scripts/telemetry.gd` | opponent (routing + structures), match log |
| `scripts/main.gd` | world, camera, input (drag to send, double-tap to build), HUD, map-select menu, phone profile, demo/screenshot mode |
| `tests/test_sim.gd` | 46 headless rules checks — all passing |

AI vs AI on Two Piers now lasts **~1-1.5 minutes** with all seven starter maps' AI-vs-AI matches
verified to finish (relay cycling + rudimentary Last Stand keep any map from turtling forever).

---

## 6. Phones

| | |
|---|---|
| Tested shapes | Galaxy S24 **2340×1080** · iPhone 15/16 **2556×1179** (landscape) |
| Camera | fits the whole map into the area left of the send buttons, any aspect |
| HUD | clear of notch / Dynamic Island / rounded corners; thumb-sized buttons |
| Touch | one finger drag = send (or pan on empty space); **two-finger pinch zoom and pan** |
| Quality profile | no realtime shadows · 3D at 75 % · no MSAA · 60 fps cap — neon + glow carry the look |
| Orientation | landscape; portrait shows a "rotate your phone" screen |
| Web build | no-threads templates (Safari-safe), mobile texture compression, PWA (Add to Home Screen) |

Checked in desktop emulation at phone sizes. **Real-device frame rate and touch feel are still to
be measured.**

---

## 7. Findings that shaped the build

- **Rim sockets can't be fixed** — the roster uses arbitrary angles → connectors clamp anywhere.
- **Honest lengths vs schematic maps** — every edge carries ~15 m of platform + piers, so schematic
  angles and S/M/L lengths can't both hold. An X of L diagonals in a ladder cell is only honest when
  the node footprint equals one module (d² = c² + ab) — maps 055/082 stretch their diagonals ×1.37.
  → rewrite such maps (e.g. diagonals M).
- **Seat palette ≈ faction hues** (cyan ≈ VEX, green ≈ Bloom…) → solved by seat-coloured bodies with
  race accents.
- **Decimating creatures to 12 % erased their faces** → size-based detail.
- **A horde passing a node must go around the structure**, never through it.
- **GDScript lambdas capture packed arrays by value** — use plain Arrays in path building.
- **Windows reports safe areas in virtual-desktop coordinates** — only trust them on native phone builds.

---

## 8. Open questions

Tracked in `05 Handoff/OPEN-QUESTIONS.md`; the ones that matter next:

- **Army scale** (~5× Alpha 11 or "thousands per send") and the **1× vat-cap baseline**
  (12/48/120 vs Alpha 11's 30/40/80/160).
- **T4**: an upgrade after T3 or a map-placed centrepiece?
- **Rear attack bonus?** Same rates as a frontline today.
- **Edge lights on relay-controlled decks** show state colour instead of the owner's — confirm (rules §7).
- Map rewrites for honest lengths; skills draft review.

---

## 9. What's next

From `PLAYTEST-NOTES.md` (Daniele's first demo):

1. ~~**Blob fight pass**~~ — done 2026-09-25 (eased shrink, goo meniscus, shoving frontline with
   splash, rear-contact visual; see §5). Left for a later animation pass: creature poses in the
   fight (leaping, biting) and a creature death effect, not only goo.
2. ~~**Entrances on every side, horde blocking on platforms**~~ — done 2026-09-25 as "the whole
   platform is the node" (see §5); a Debug-panel slider tunes the platform fight rate.
3. **Platform speed vs bridge speed** — node crossings look too fast next to decks.
   Debug-panel sliders for both speeds now let this be tuned live in play (2026-09-25); still open
   is which values to bake into `rules.gd`.
4. Animation and effects work in general (the mechanic works; the motion needs love).
5. ~~Vat upgrades~~ — done 2026-09-25, alongside cannon/forge (see §5 "Structures"); all seven
   starter maps are playable via the title screen with rudimentary relay cycling and Last Stand so
   every match resolves. Real-phone test is still open.
6. Next: the real per-map relay behaviour and art (rotation tower, switch hub, remote conduit),
   real Last Stand (per-map method choice, hidden reveal, falls), attachment swap/cooldown, cannon
   T2/T3, forge's mixed-garrison weighting, then a real-phone test.

---

## 10. How to run things

```bash
# play (Godot is in Tools/Godot of the project folder) - opens the starter-seven title screen
Godot_v4.6.1-stable_win64.exe --path "Game/2.0"

# play one map directly, skipping the title screen
Godot_v4.6.1-stable_win64.exe --path "Game/2.0" -- --map=res://maps/008-strait.json

# AI vs AI, phone-shaped, with screenshots (also skips the title screen)
Godot_v4.6.1-stable_win64_console.exe --path "Game/2.0" -- --map=res://maps/008-strait.json --demo --mobile --window=2340x1080 --shots=12,28 --out=C:/tmp

# stage a contact on the deck between nodes 1 and 0 and look at it up close (no AI):
#   fight = head-on frontline, rear = a slow line caught from behind, queue = friend behind friend
Godot_v4.6.1-stable_win64_console.exe --path "Game/2.0" -- --scenario=fight --zoom=13 --window=1600x740
Godot_v4.6.1-stable_win64_console.exe --path "Game/2.0" -- --scenario=rear --shots=9,11,13 --out=C:/tmp

# rules tests
Godot_v4.6.1-stable_win64_console.exe --headless --path "Game/2.0" --script res://tests/test_sim.gd

# PUBLISH THE PLAYTEST BUILD - do this after every pass that changes play or looks (Daniele, 2026-09-25),
# then send the link:  https://talos91.github.io/ooza-syndicate-v2/
# 1. commit + push main; 2. export; 3. replace the orphan gh-pages branch with build/web (Pages source =
#    gh-pages, root, set 2026-09-25); 4. wait until index.pck answers 200 on the link (~1 min).
Godot_v4.6.1-stable_win64_console.exe --headless --path "Game/2.0" --export-release "Web" build/web/index.html
git worktree add --detach /tmp/ghpages && cd /tmp/ghpages && git checkout --orphan gh-pages && git rm -rqf .
cp "Game/2.0/build/web/"index.* . && rm -f *.import && touch .nojekyll
git add -A && git commit -m "Playtest build: <what changed> (source main <sha>)" && git push -f origin gh-pages

# web build for the phone, then serve it on the local network
Godot_v4.6.1-stable_win64_console.exe --headless --path "Game/2.0" --export-release "Web" build/web/index.html
python -m http.server 8060 --bind 0.0.0.0     # from Game/2.0/build/web; open http://<pc-ip>:8060 on the phone
```

Blender (with the MCP addon connected, or by hand in Blender's Python console):

```python
exec(open(r"H:\My Drive\PROJECTS\Ooze Syndicate\Models\2.0\build_kit_2_0.py", encoding="utf-8").read())
exec(open(r"H:\My Drive\PROJECTS\Ooze Syndicate\Models\2.0\build_horde_patches_2_0.py", encoding="utf-8").read())
```

Re-exporting the kit / patches to `Game/2.0/assets/` is scripted in the session (select a piece,
zero its transform, `export_scene.gltf` as GLB) — worth turning into its own script next time.
