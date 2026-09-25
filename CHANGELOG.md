# Ooze Syndicate 2.0 - changelog

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
