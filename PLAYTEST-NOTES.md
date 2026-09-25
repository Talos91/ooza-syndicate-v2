# Playtest notes

## 2026-09-25 - Daniele, first Two Piers demo (to do next)

1. **Fight losses must show on the blob.** When hordes fight, the blob shrinks in step with the
   losses - not just numbers on screen.
   *Done (2026-09-25, blob fight pass):* the drawn count trails the real one by a fraction of a
   second, so the line recedes smoothly from the contact (head stays put, tail comes forward) and
   thins as it empties; goo splashes off the seam in proportion to each side's loss rate.
2. **Structures need entrances on every side** (all four cardinal sides, or at least top and bottom),
   so hordes don't all detour to one door.
3. **Blobs that reach each other merge**, at least visually: e.g. a bumper / meniscus of goo at the
   contact so two chains read as one mass, even if the sim keeps them separate.
   *Done (2026-09-25):* every contact gets a goo meniscus - two lobes in the two owners' goo joined
   by a hot white seam, pulsing with the shoves; a friendly queue gets a single-colour bumper so the
   two lines read as one. The sim still keeps the hordes separate.
4. **The blob must be longer** - it is a blob fight, not a small unit.
   *Done (2026-09-25):* sends stream out of the vat as one long line, length = size (0.25 m per unit,
   40 m cap, then thicker), pour in over time on arrival, shrink with losses (also covers note 1's
   "shrink with losses" in a first form), thicken where they pile up, taper at the tail. Two head
   patches full detail, the body light. Design pillar written into GAME-RULES §5: length is the count,
   no Mushroom Wars endgame chaos, and a long line on its way tells you to split the next send.
5. **Platform speed is too fast compared with bridge speed.** (Today nodes are crossed at 6x deck
   speed so travel time counts decks only - needs another way to keep the timing honest, e.g. a
   shorter visual path across the node, or a lower multiplier with deck speeds re-tuned.)
   *Tooling (2026-09-25):* the in-game Debug panel (bottom-left) has live sliders for deck speed and
   platform speed, so the right ratio can be found in play; tell me the values and they go into
   `rules.gd`. Note the sim's travel-time promise (1 module = 2 s) only holds at the defaults.
6. **A proper frontline animation** for bridge fights - the current stop-and-count looks bad.
   *First pass (2026-09-25):* the patch in contact is squashed (0.7 along, 1.35 up, 1.12 across, as
   on the Blender board), the front four patches rock back and lunge into the contact in shoves
   (~2 per second, travelling up from behind), a pressure ripple runs down the whole line and the
   front jostles sideways. Numbers in `scripts/horde_view.gd`. Stage a fight to look at it:
   `--scenario=fight --zoom=13` (also `rear`, `queue`; see BUILD-LOG §10). Still to do: creature
   poses (leaping, biting) and a death effect for creatures, not only goo.
7. **Attack from behind, not only frontal** - a horde on a bridge is a blob that blocks it.
   *Done in the sim (2026-09-25):* contact from any direction on a deck - frontline (enemy coming
   toward), rear attack (enemy catching up from behind), friendly queue (no passing through a friend
   going the same way; friends going opposite ways squeeze past). A horde can fight front and rear at
   once. Still to do: the same blocking on platforms.
   *Rear-contact visual done (2026-09-25):* the caught horde's tail is squashed and shoved forward,
   the meniscus and splash sit between the pursuer's head and that tail.

## 2026-09-25 - Daniele, second pass: door timing and the platform as the node

8. **Units leave the vat only as they become blob.** Sending doesn't instantly move a whole order
   out - it stays queued at the door, revealed at a rate, and units not yet emitted are still the
   vat's and still orderable: a new send re-counts the vat's current total (streamed part cut away
   from the old order) rather than double-spending.
   *Done (2026-09-25):* a node's `streaming` field holds the one order the door is emitting
   (`Rules.door_rate` units/s, default 48 = the old fixed door speed so nothing regresses at
   defaults); `send()` cuts a live order down to what already left and starts a fresh one from the
   vat's current count. Your own horde's label shows `out +still-inside` while it streams.
9. **Structures need entrances on every side, and the platform is the node.** Instead of a single
   door, treat the whole platform as the node: an arriving horde lands from whichever pier it
   travelled and spreads onto the platform up to the tower - contact happens there, not at one
   point. If contested, the platform fills in the fight's ratio, the attacker's share centred on
   the side it arrived from; the "hit box" for anyone attacking is the tower itself, with the ring
   between tower and rim being where the fight actually happens (this also gives you a natural
   place for a defence-vs-attack order concept later). Sends leaving a tower start their animation
   at the tower and flow out through this ring on whichever side leads to the target.
   *Done (2026-09-25):* replaces the old goo-emitting door entirely (note 2 was expanded into this,
   note 7's blocking-on-platforms is now this too - closes the previous "still to do"). Every
   platform draws a ring of goo patches around its tower (`Rules.RIVER_R`/`RIVER_SLOTS`), coloured
   by owner and scaled by how full the vat/siege total is; a besieged platform splits the ring by
   each side's share, seamed with the same meniscus/splash as a deck fight; when the garrison falls
   the node flips and the survivors become the new garrison. Sim: `node.siege` (seat -> units
   fighting there), `node.siege_dir` (the side each attacker landed from), `node.node_loss` (view
   hook). Not yet done: a distinct defend/attack order at a node (today arrival = automatic siege).

**Debug panel additions:** Door rate (units/s) and Platform fight (x combat rate) sliders, next to
the existing deck/platform speed ones - open `Debug` bottom-left. Reset to rules restores all four.

## 2026-09-25 - Daniele, third pass: no free glide through a node

10. **An order passing through a node always counts as passing through that node.** A route from
    A to C via waypoint B should not glide past B for free regardless of who holds it - B's
    garrison (or whoever else is passing through at the same time) gets to fight it.
    *Done (2026-09-25):* every node on a route - not just the final target - now has an arc window
    (`node_spans`) where the passing horde's CURRENT units count as an attacking force at that
    node, fought with the same rate math as a real siege (`Rules.node_fight_mult` applies here
    too). A weak waypoint just grinds down some of the passing force (real losses, real risk); a
    strong one can wipe the passing force out entirely before it reaches its destination.
    **Design call, open for correction:** transit does NOT capture the node - only an actual
    arrival (an order whose target that node is) can flip it, even if transit combat alone grinds
    the garrison to zero (it sits at 0, still owned, open to whoever arrives next). I chose this
    after the alternative (transit captures too) hijacked unrelated orders - e.g. a rear-attack
    pursuer ending up conquering a waypoint instead of ever reaching its target - which felt like
    a surprising, un-asked-for side effect. Friendly waypoints (owned by the horde's own seat) are
    a pure pass-through, no fight, matching GAME-RULES §6 ("troops passing through don't count").
    Two new rules tests cover both outcomes (grind-and-continue, wiped-out-en-route).

## 2026-09-25 - Daniele, fourth pass: all seven maps, rudimentary relay/Last Stand, structures

11. **All seven starter maps, playable.** *Done:* a title screen (shown unless a map is named on
    the command line, or this is an automated run) lists the starter seven in build order; picking
    one loads it exactly like Two Piers did. Every map lays out fully connected and an AI vs AI
    match on each one finishes (headless rules tests). Relay-controlled decks and retract decks are
    drawn and simulated as ordinary FIXED open decks for now - the true relay ART/behaviour per map
    (a rotation tower, a switch hub, a lit remote conduit) is not built; every node just gets the
    ordinary platform + vat placeholder.
12. **"Without rotation/Last Stand the game is eternal - test with the real maps even if
    rudimentary" (Daniele).** Confirmed on Strait (the shared central node became a permanent 0-unit
    stalemate neither side could ever capture) before this pass.
    *Done:* two RUDIMENTARY systems so every map actually resolves:
    - **Relay cycling.** Every distinct relay state prefix on a map (rotation r/switch s/remote m)
      cycles through its states together every `Rules.RELAY_PERIOD` (18 s: GAME-RULES sec8's 3 s
      warning + 15 s cooldown, no warning phase modelled); a `retracts` deck toggles open/closed on
      the same period. Only NEW pathfinding respects this; a horde already committed to a route
      keeps moving even if its deck later "closes" - no warning, no fall, no carry.
    - **Last Stand.** Starts at 3:00 (GAME-RULES sec10), always the "inward" method regardless of
      what the map lists (rim collapses first, one node every 14 s, the centre is never dropped).
      A dropped node's units/siege/attachments/build vanish and it's excluded from all future
      routing - it just goes away, it doesn't take troops on it down too (a real per-map method
      choice, the hidden reveal and "everything on a falling node/deck dies" are a later pass).
    - **Safety net.** If a match is still undecided at 7:00, the stronger seat (by total strength)
      wins outright - conquest should always decide it before then; this exists for automated
      testing and to guarantee no match is truly eternal.
    - Also fixed a real bug the Strait stalemate exposed: a node whose garrison falls while BOTH
      seats have simultaneous arrival sieges on it (both cheaply grinding a shared hub) used to stay
      captureless forever (my "transit can't capture" rule from the previous pass only checked for
      exactly one attacker present); now the side holding more ground there right now takes it.
13. **Structures now do something** (Daniele: "implement all we have already model wise... all
    structures and their functions"). Vat_T1-4, Cannon_T1-3 and Forge were modelled but inert.
    *Done, rudimentary (real costs/tiers/swap rules wait on the army-scale decision):*
    - **Vat upgrade** (T1->T4, GAME-RULES sec6's 10 s build, no unit cost yet).
    - **Cannon** (single tier only so far): every 4 s bursts up to 10 units off any enemy horde
      within 10 m, a direct kill bypassing normal fight math (matches Alpha 11's "cannon body kills
      bypass HP").
    - **Forge** (single tier): its owner takes 15 % less damage everywhere (deck fights, node
      sieges, transit fights) - the "attack" half of GAME-RULES sec6's bonus is folded into this one
      defensive multiplier for now rather than implemented as a separate knob.
    - Double-tap one of your own nodes to act on it: the new Upgrade/Cannon/Forge buttons (top of
      the side HUD) pick what a double-tap does; it silently does nothing where the map's roster
      JSON doesn't allow that structure there. The AI has the same options (no cheats): it upgrades
      a flush vat, builds one forge, then cannons wherever it can.
    - The 3D model swaps live (vat tier, cannon/forge appearing) - seen working via the sim
      (headless tests) and the vat-tier swap in play; a longer session is needed to see the AI
      actually place a cannon/forge model on screen, not yet specifically watched for.
14. **Debug panel: wider ranges, platform speed can go below deck speed** (Daniele: "increase the
    limits... by a lot... platform filling speed lower than deck speed"). Deck speed 0.2-30 m/s,
    platform speed 0.1-30x deck (was floored at 1x - now testable as SLOWER than the deck, the
    actual open question in note 5), door rate 1-500 units/s, platform fight 0.05-20x.

## 2026-09-25 - Daniele, fifth pass: switch feedback, Alpha 11 tap convention, corridor goo

15. **"I don't see switch implemented yet" / cannon-forge doesn't work.** Two real gaps: relay
    cycling had no visual feedback (a deck's open/closed state never showed - a "switch" changing
    nothing you could see isn't implemented as far as the player can tell), and the double-tap
    build/upgrade gesture relied on the engine's `double_click`, which proved unreliable (at least
    on the Web export).
    *Done:* a relay-controlled or `retracts` deck now actually **disappears while closed and
    reappears while open** - the switch/rotation/retract is now something you SEE, not just a
    routing change (`vis["edge_decks"]`, synced every frame against `Sim.is_edge_open`). Replaced
    engine double-click with a manual tap timer, and switched the whole interaction to the **Alpha
    11 convention**: single-tap an owned node with an empty attachment slot to open a small popup
    and choose Cannon or Forge; double-tap upgrades whatever's already there - the vat, or a built
    cannon's tier (T1->T2->T3, GAME-RULES sec6). A forge is single-tier, nothing to upgrade. AI has
    the same options via `Sim.upgrade_structure`.
16. **"Not fun that on corridors they fight while not on the platform."** The fight itself was
    always happening at the right place (an intermediate node's platform, per PLAYTEST-NOTES 10),
    but a passing-through fight got none of the visual treatment an arrival siege gets, so it read
    as generic attrition somewhere along the corridor instead of combat AT the platform.
    *Done:* a transiting engagement now gets the same goo meniscus/splash as everything else,
    anchored to the platform's rim (not wherever the horde's long tail happens to be).
17. **"If two platforms owned by a player are adjacent, the corridor should be covered in goo."**
    *Done:* a deck between two of your own nodes now shows a strip of your goo along its whole
    length - a held corridor reads as safely yours, the same way a held platform's river does.
18. **Blobs always fight when they cross, including the base's surrounding blob.** Confirmed this
    is already how it works: deck contact detection fights any overlapping enemy segment (no gap),
    a platform's goo river IS a blob for this purpose (arrival siege and transit both engage it),
    and several attacking hordes can be engaged with the same enemy force at once (a shared
    platform's `siege`/`transit` totals combine per seat; a deck horde can be fighting front and
    rear simultaneously) - see `sim.gd _node_fights`/`_detect_contacts`. No change needed there.
19. **Last Stand moved to 2:00** (was 3:00) to keep matches shorter for this rudimentary pass.
20. **"Make sure enemies can't pass a platform without automatically attacking the tower if
    occupied - neutral don't count."** *Done:* transit fighting (note 10) now only triggers at an
    ENEMY-owned node; a neutral one is a free glide-through (it has no shield either - see note 21).
21. **The shield idea: allow passing through, but the goo ring is a toll, not a wall.** Daniele:
    "we allow passing through the tower, but the outside goo (the ring) counts as a percentage of
    what is inside (20%) - to pass through the attacker needs to clear that, then can go on. Think
    of it like a shield that regenerates with excess minions; if broken, the bond with the other
    node disappears."
    *Done, with one reading I chose where the request was ambiguous:* every owned node has a
    **shield** worth `Rules.SHIELD_FRACTION` (20%) of its CURRENT garrison, regenerating at
    `Rules.SHIELD_REGEN` units/s whenever below that cap. A transiting force now fights the shield,
    never the real garrison directly - only an actual ARRIVAL still touches the garrison itself
    (note 10's "only an arrival captures" still holds, now for an even stronger reason: transit
    can't even dent the garrison any more). The garrison still fires back at the transiting force
    exactly as before, so a strong node is still lethal to weak passers-through. If the shield hits
    zero, the bond breaks: **my reading of "the bond with the other node"** is the ONE deck the
    attacking force is using right now to approach - not every connection the node has - and that
    deck is destroyed outright (`Sim.broken_edges`, excluded from all future routing, and the deck
    model itself disappears in play, same visual as a closed relay deck but permanent). An
    already-moving horde isn't stopped by its own bond-breaking; it continues on its precomputed
    path. **Flag for Daniele:** if "the bond" was meant to mean something else - every edge the
    node has, the edge toward its OWN home, or a repairable state rather than permanent - say so
    and I'll adjust; this is the most literal reading of "the bond with the OTHER node" I could
    make without more specifics.

## 2026-09-25 - Daniele, sixth pass: relays are player-fired, alignment, Alpha 11 look

22. **"There are no touch controls for relays... how do I switch them?"** Relays cycled on a blind
    timer with no player input at all - a real miss (GAME-RULES sec8 explicitly lists "fire the
    switch" as part of a node's control surface). *Done:* owning a relay lets you tap it and press
    Switch to advance it, 15 s cooldown, added to the same popup Cannon/Forge already use. AI does
    the same. `Sim.fire_relay(node_id)`.
23. **"The structures on the relays are all fucked up and not aligned properly... why not using
    their tower models?"** Two related bugs from the previous pass's rushed relay-housing work:
    the tower was offset toward a guessed rim-ledge position/rotation that didn't match the
    Blender kit's authoring, and a built cannon/forge floated beside the vat slot instead of
    replacing it. *Done:* housing centred on the node (simpler, guaranteed not to float); a built
    attachment now replaces the centre slot exactly, matching GAME-RULES sec6 (one slot: vat, or
    cannon, or forge - never more than one at once, now actually enforced in `upgrade_vat` too).
24. **"Last Stand works but the platform and connected bridges need to disappear using the
    destruction animation."** A collapsed node just sat there unchanged before - the Last Stand
    mechanic worked in the sim but was invisible. *Done:* a rudimentary fall (sink + tumble, ~1.3s)
    for the platform and every bridge still attached to it.
25. **"Add all the part of interface that Alpha 11 had... take away this ugly one" + a player
    selector.** *Done, scoped:* reused Alpha 11's actual panel/button styling (dark translucent
    panel, coloured border, angular corner radius) and its Rajdhani-SemiBold font across the title
    screen and the HUD's buttons/panels, replacing default Godot chrome. Added a faction picker to
    the title screen (previously hardcoded). **Not done:** a full port of Alpha 11's whole
    interface (its inspector layout, badges, toast styling already have their own 2.0-shaped
    versions from earlier passes) - flagging this as a deliberate scope call given everything else
    in this session, not an oversight.

## 2026-09-25 - Daniele, seventh pass: "bring us back to something we can call an alpha" (Alpha 12)

Daniele's answers to the v0.8.0 open items, and the brief: "full implementation of everything we
already created... the complete lack of animation, HUD, UX/UI makes it unplayable and hard to
decide if mechanics are good or not... only thing I can save on is textures or better models".

26. **The bond is the goo trail, not the bridge.** "2 vats form a bond when both have the shield
    active; when active the road becomes covered in goo; if one of the two loses a shield the path
    is gone." *Done:* `Sim.bonded(edge)` - both ends one owner AND both shields up - drives the
    corridor goo; a broken shield (`shield_up = false`) drops the bond until the shield regenerates
    to full, and passage through that node is free meanwhile. `broken_edges` and the deck
    destruction are gone entirely (they were what left nodes isolated by the Last Stand).
27. **Last Stand at 2:00 "seems ok".** Kept at 2:00 (`Rules.LAST_STAND_TIME`); GAME-RULES sec10's
    3:00 stays the design value until Daniele locks one.
28. **Relays "almost all broken... isolated nodes... no falling animation".** *Done:* the real
    per-kind behaviour (GAME-RULES sec8) with a 3 s warning, visible deck motion and the troop
    fate: rotation pivots the turntable + deck and hordes ride it (re-routed from the new pier),
    retract slides the deck into its gate and carries everything on it into the node, switch and
    remote dissolve the deck and drop everything on it (fall losses, patches tumbling, droplets).
    Remote's console controls its far-away decks via lit conduits. Capture during the warning
    cancels the switch. AI fires relays only when it gains from it.
29. **Last Stand "units don't fall, nodes don't fall, nothing happens".** *Done:* per-map method
    (inward / outward / chaos from the JSON's `methods`, seeded, hidden until 2:00), the order
    revealed on badges (#n / FINAL), a 10 s warning ring with flashing decks and a countdown,
    then the platform tumbles, decks break into `Deck_S_Frag_*` pieces, goo pours over the rim,
    and garrison + siege + every horde portion on the node or its decks die. Losing your last
    node = elimination.
30. **Costs "seem random, upgrades are free" - start from Alpha 11.** *Done:* Alpha 11's logic x5
    (`Rules.SCALE`): vat 50/100/150 paid from the vat, cannon 75 then 125/175, forge 100, caps
    150/200/400/800, production 5/8/12/17.5, cannon 2 s bursts of 50/125/200 bodies with recharge
    after (4/2.4/1.6 s), forge +50 % attack (Alpha 11's +50 on the 100 scale; the "defense" half
    of GAME-RULES sec6 is NOT applied - flagged in OPEN-QUESTIONS). Swaps: 10 s rebuild + 10 s
    cooldown; RESTORE VAT free. Relay nodes produce nothing (no vat).
31. **Mobile touch / on-phone performance: "do it".** *Partly:* the web build was exercised in
    the desktop app's browser at a phone-shaped viewport (see BUILD-LOG §6) and the Debug panel
    now prints FPS to the console. **Not done, cannot be done from here:** touch on a real phone
    and a real-device frame rate - the built-in browser delivers mouse events even in phone
    emulation. Daniele's own phone test remains the only real measurement.
32. **"Movement and combat still crooked... enemy units crossing each other on a platform without
    a fight... a unit crossing an enemy should always start a combat to death."** *Done:* contact
    is geometric (spatial hash over every patch of every line, anywhere on the board); a head
    within `Rules.CONTACT_R` of any enemy patch engages, and the pair fights until one is gone.
    A horde crossing a shielded enemy platform slows to deck speed so the toll fight is visible.
33. **"No building animations for construction nor anything."** *Done:* the new structure grows
    out of the socket under a turning yellow build ring (Alpha 11's scale-up), badge + inspector
    progress bars, a pulse when done; capture pulses; shield dome with hit flash / break / return;
    cannon beam + impact flash; relay warning blink + next-deck ghost + cooldown ring; exit puddle
    while an order drains; falls for nodes, decks and hordes.
34. **"All menus are missing... all past interface."** *Done:* Alpha 11's interface in full - see
    CHANGELOG 0.12.0 "Interface". Still open by design: the ability dock is present but disabled
    (skill pools unapproved), no multiplayer/team UI (2v2/3v3/FFA modes not built).
35. **"Nothing is finalized regarding speed on the board or exit of units from towers."** Left as
    Debug-panel sliders with the same defaults (deck 2 m/s, platform x6, door 48/s) - the numbers
    to bake into `rules.gd` are still Daniele's call from play.

## 2026-09-25 - Daniele, first Alpha 12 playtest (v0.12.1)

36. **"Enemy managed to cross a bridge even if there was no bridge."** Routes were fixed at order
    time; a deck that fell or closed afterwards was still walked. *Done:* `Sim._check_missing_decks`
    - reaching the pier of a missing deck re-routes from that node (or stops there), anything
    already on it falls.
37. **"The map got cut on chaos; chaos cannot activate on maps like Two Piers; we can't leave
    isolated nodes."** *Done:* every drop order keeps the remaining map connected to the final;
    chaos keeps homes as late as connectivity allows and is refused (inward instead) where a home
    would have to fall in the first half - which is Two Piers and the other line/tree maps.
    Design note in OPEN-QUESTIONS: rules §10's "home nodes never before the end" cannot hold
    literally where homes are leaves.
38. **"The UX covers the whole vat and can't see what's going on."** *Done:* badges sit below the
    platform's near rim, smaller; the inspector ring has no fill.

39. **"Why have we not introduced all the factions and different colours? Why not the rest of the
    UX/UI like main menu, race selection?"** (Alpha 13) Both were my scope cuts, not blockers. *Done:*
    Alpha 11's faction stat profiles now drive speed, health, attack, production and garrison in
    the 2.0 sim; the rival's faction is chosen (or random) on the setup page; Alpha 11's full
    front menu is ported with its portraits, stats/trait/abilities composition and faction tabs.
    Colours: ownership stays seat colour by the 2.0 rules (A cyan, B green); the faction shows in
    creature shape, accent and stats. Say so if you want faction colour back as ownership.
40. **"Chaos should NEVER leave nodes alone."** Rule since v0.12.1: no drop may leave a surviving
    node without a physical path to the final, for every method. The screenshot showing it was the
    cached v0.12.0 build (badges still on the towers give it away) - reload twice.

41. **"Big numbers don't look good - back to what Alpha 11 had, with Alpha 12's amount of
    troops."** *Done:* `Rules.shown()` divides every displayed count by `SCALE` (5); the sim and
    the horde length are unchanged.
42. **"Even if a bridge got retracted, enemy units with the order to cross it still crossed it
    instead of falling in the void."** *Done:* a horde reaching the pier of a missing deck
    (retracted, switched away, fallen) walks off and falls, pouring off at deck speed. Replaces
    v0.12.1's re-route reading.

43. **"Add a toggle: combat like Alpha 11 or like Alpha 12 (combat on bridges) - I wanna try with and
    without."** *Done:* `Rules.bridge_combat`, on the setup page and in the Debug panel. OFF = hordes
    pass each other on decks and fight only at nodes (Alpha 11); ON = Alpha 12.
44. **Trident Exchange: "platform not fully falling, relays showing as if they fell but not
    falling."** The floating goo rings were the rivers of collapsed nodes - fixed. The relay nodes
    reading 0 are alive but empty (no vat, garrison spent) and a retracted deck is gone by design;
    say so if you want relay nodes to read differently.

45. **"I want the damn menu as for Alpha 11."** (v0.13.1) *Done:* Alpha 11's `front_menu.gd`
    ported with its art, kit, frames and coordinates - see CHANGELOG 0.13.1. The battlefield page
    shows rendered 3D thumbnails of the seven maps.
46. **"Where is the toggle for the mode?"** It is on 03 SETUP (BRIDGE COMBAT / ON-OFF, where Alpha
    11 had ABILITIES), on the OPTIONS page, in the pause menu and in the Debug panel.
47. **"The latest version is making my PC run like crazy - is it that or something else?"**
    Measured: 60 fps capped, ~1,900 draw calls and ~1.9 M triangles per frame on the 13-node map
    at full detail; the load is the horde and river patches, not the interface. Two Alpha 12
    additions were pure cost and are fixed in v0.13.1: the menu ran uncapped (now 60 fps
    everywhere) and the shield domes were 13 big translucent spheres (now flat rings). If it still
    runs hot, OPTIONS -> DETAIL: LOW (half the patches) tells us whether it is the build; the
    Debug FPS line prints draw calls to the browser console for a report.

48. **"Deck speed at default 5 m/s, relay cooldown 5 s, deck speed and platform speed need to
    match."** (v0.13.2) *Done:* `DECK_SPEED_DEFAULT` 5.0, `NODE_SPEED_MULT_DEFAULT` 1.0,
    `RELAY_COOLDOWN` 5.0 (the door rate follows: 20 units/s keeps the tail at the door). Note for
    the design package: at 5 m/s one 4 m module is 0.8 s, not the rules' 2 s - PARAMETERS still
    says 2 s per module; Daniele to lock the new value.
49. **"We need to redo the blob model... it is hard now to scan enemy units attacking vs
    before."** Open - next pass. The horde patches (`Models/2.0/build_horde_patches_2_0.py`) need
    a readability redo: enemy lines must be scannable at a glance (which line is attacking what).
    Candidates: a clearer head, a direction cue along the line, stronger seat colour on the goo
    and less on the creatures, a contact marker on the target's badge.

## 2026-09-25 - Daniele, Alpha 14 brief: two modes, teams, colours

50. **Bridge-fight mode as a tug-of-war, plus a recall order.** *Done:* `Sim._tug_of_war`, `Sim.recall`
    (tap your own line), AI `_retreats`. See CHANGELOG 0.14.0.
51. **Bridge-fight mode rules:** always-on goo corridors, enemies on your goo slower and weaker in
    the tug, transit fights the real garrison (no hidden shield), capture drains the corridor, the
    tower ring means "mine". *Done* - the shield pool is removed from sim, effects and HUD.
52. **Classic mode (bridge combat off) with Alpha 11 unit models instead of goo.** *Done:*
    `scripts/unit_view.gd`.
53. **2v2 and FFA up to 5, faction colour selection.** *Done:* MODE and YOUR COLOUR rows on setup,
    `Sim.teams` / `allied()`, `Rules.assign_colors`, four roster maps added.
54. **"Add a server for multiplayer via Vercel."** *Not done - needs Daniele's decision.* Vercel
    functions are short-lived HTTP handlers and cannot hold the long-lived WebSocket connections a
    realtime match needs. See OPEN-QUESTIONS for the options.

## 2026-09-25 - Daniele, mobile and readability pass (v0.14.2 - v0.14.4)

55. **Phones: interface shrunk to the left, mandate fullscreen.** *Done:* the menu scales and
    centres on any screen shape; `scripts/fullscreen_gate.gd` requires fullscreen (Android button,
    iPhone Add to Home Screen; the PWA opens fullscreen). Verified in the browser at a 2.17:1
    viewport; real-phone test still Daniele's.
56. **Classic: same-faction players share a colour.** *Done:* units take the owner's colour.
57. **Unit counts hard to read.** *Done:* badges hang from each platform's near rim, bigger count.
58. **Relay decks: units still don't consistently fall.** *Done:* every deck a line overlaps is
    checked, including tails and lines that walked on mid-motion.
59. **Double-tap upgrade still shows the upgrade interface.** *Done:* the inspector opens only after
    the double-tap window, and the second release is swallowed.
60. **Classic: Alpha 11 stats; no units loitering round the vat.** *Done.*
61. **Fixed map size, no zoom, less vertical camera.** *Done:* no zoom or pan, pitch 42 degrees.
62. **Vats and buildings face the viewer on every map.** *Done.*
63. **Vat upgrade info said 150.** *Done (0.14.3):* the inspector buttons now use the display scale.

## 2026-09-25 - Daniele, Alpha 15 pass (v0.14.5 - v0.15.0)

64. **Home screen: background on top of a background.** *Done:* one full-screen backdrop.
65. **Trident Exchange and other maps: crossings with no overpass.** *Done:* every crossing pair
    gets one deck raised on load (24 roster maps had unmarked crossings; roster files untouched).
66. **Inward Last Stand always drops the same node first.** *Done:* same-ring nodes shuffle (seeded).
67. **Send controls on the left.** *Done* (Alpha 11 layout); Debug under PAUSE.
68. **No-bridge mode = exactly Alpha 11's core rules; units just go in; half-bridge neon; Alpha 11
    HUD.** *Done:* Brawl landing (`Sim._land_classic`), walking-in columns, half-bridge trims, round
    badges with emblems and counts on every node, kit buttons.
69. **Last Stand on/off toggle; conquest downgrades a vat or tower one tier (min 1).** *Done.*
70. **HUD must never overlap corridors or platforms; mode names Brawl and Siege.** *Done:* projection
    camera fit, badges outside platforms, empty dock hidden; MODE / SIEGE or BRAWL.
71. **Multiplayer: start with Alpha 11's peer-to-peer, Neon/Vercel later.** *Done (0.16.0):* ONLINE rooms,
    lobby, host-authoritative play, rematch, chat (`scripts/net.gd`). Neon/Vercel still later. Only
    tested with two browser instances on one PC - separate networks and phones are Daniele's test.

## Known gaps after Alpha 13 (not playtest findings)

- Abilities / Ooze Factory (pending SKILLS-2.0-DRAFT approval), team modes and multiplayer,
  overpasses, Big Drop and Production Halt variants, the rotation "into the void" fall case (none
  of the starter seven has one), textures and the model detail pass.
- Army numbers are Alpha 11 x5 and provisional; the T4 role and the 1x baseline remain open.
- Real-phone touch feel and frame rate are unmeasured.

## 2026-09-25 - Daniele, Alpha 16 feedback (v0.16.1)

72. **Empty seats filled by AI, as a setting.** *Done:* lobby EMPTY SEATS (players only / AI level).
73. **10 s grace; a reconnect button; a rematch button after victory/loss.** *Done:* 10 s host
    grace, dropped players keep their seat and RECONNECT from the ONLINE page, REMATCH on results.
74. **Brawl: Alpha 11's exit, entrance, deck and platform speed - the feel exactly the same.**
    *Done:* 8.9 m/s everywhere (Alpha 11's 115 px/s at 2.0's map scale), 9.6 units/s out and in.
75. **Recall only in Siege.** *Done.*
76. **Siege: the goo round a base shrank and looks worse; it was nice covering the platform.** *Done:*
    two rings to the rim, near full size at any count.
77. **Brawl animations matching Alpha 11.** *Done:* Alpha 11's hop, roll, squash and three-quarter facing.
78. **2v2 / FFA: everyone looks the same; teams need distinct hues, FFA very different colours; emblems
    in the player's colour.** *Done:* new FFA hue order and team families, tinted emblems.
79. **Android: fullscreen prompt stays after going fullscreen and can't be left.** *Done:* native
    overlay gate with CLOSE (needs Daniele's phone to confirm).
80. **Map selection doesn't scroll with the finger on mobile.** *Done:* swipe scroll (needs the phone).
81. **Next alpha: redo all maps and change the Last Stand mechanic.** *Open* - waiting for the brief.
82. **Browser cache still shows Alpha 14.** *Done (0.16.2):* `web/update.js` swaps in new builds.
83. **Badges way too big, covering bases; they must float in the void next to a node, much smaller.** *Done.*
84. **Toggle to hide enemy node unit counts, in options and Debug.** *Done.*
85. **Brawl still doesn't feel like Alpha 11, entering and exiting.** *Done:* Alpha 11's front-door
    route round the platform ring and its single-file-to-three-across column. Needs Daniele's feel check.

## 2026-09-25 - Daniele, visual pass brief (v0.16.4)

86. **Background like Alpha 1.** *Done:* the cloud-city sky, drifting, vignetted.
87. **Better notifications in the UI style.** *Done:* framed, colour-coded, stacked, animated.
88. **Better lighting and textures.** *Done:* violet ambient, warm key, rim light; surface detail.
89. **Vats fill by units; Alpha 11's creatures in the liquid, animated.** *Done:* liquid gauge + residents.

## 2026-09-25 - Daniele, Alpha 17 brief (v0.17.0)

90. **Integrate maps 3.0 (100 maps) in the approved Blender layout.** *Done:* baked by
    `Models/2.0/export_maps_3_0_game.py`, placed by `MapBuilder.build3`, verified by `tests/test_maps3.gd`.
91. **Debug maps D-01..D-09 for testing.** *Done:* same pipeline, last in the map list.
92. **Last Stand: ring logic, relays fall only after their rings, never unconnected platforms.** *Done.*
93. **Brawl units 20 % slower.** *Done* (7.1 m/s).
94. **Brawl: units entering a building clip.** *Done:* bodies shrink and dip into the door, and grow out.
95. **AI: use switches properly; the curve is brutal and all AIs gang up on the human; Alpha 11's five
    levels with scaling aggressiveness.** *Done:* Alpha 11's loop and profiles, rival adjustment, relay
    rules; measured curve 10 / 15 / 50 / 90 / 95 % vs Standard, seat A 30 % of FFA attacks.
96. **Units accelerate on long bridges - speed is always constant.** *Done (0.17.1):* no deck pace factor.

## 2026-09-25 - Daniele, Alpha 18 brief (v0.18.0)

97. **"The maps are waaaay too big for mobile."** *Done:* maps 4.0 (Daniele's new landscape pack, 160 x 80
    frame, max ~21 nodes for 2v2) baked at 1.7 m per unit; a platform spans 5.2 % of the screen width on
    the median map (was 2.9 %). Pocket hops too short for piers are docks.
98. **"Make it a bit more from the top so there's more bird's-eye view, run some test."** *Done:* renders
    at 42 / 50 / 58 / 66 degrees compared; the camera is now 50-74 degrees (most 62-70).
99. **"Different maps might want different camera angle; make sure all nodes and their functions are
    clickable on mobile and that nothing overflows; if some map is not good for mobile flag and remove
    it."** *Done:* the phone-fit probe (`tests/phone_fit.tscn`) measured every map at seven angles on an
    844 x 390 pt phone; each map got its own pitch (`scripts/map_camera.gd`): smallest tap target >= 33 pt,
    no node or badge off screen or under the HUD, no badge collisions. Badges now avoid the HUD; the
    inspector's X is no longer covered. Flagged and removed: D-08 (27 pt at best) and B-30 (deck clashes)
    everywhere; the 3v3 / 2v2v2 maps on phones (crowded; the pack says tablet). Relay symbols fixed on web.
100. **Optimization pass: no stray code, nothing that makes no sense, no errors, smooth, same look.**
     *Done:* audit of every script (112 findings, 110 confirmed, 95 safe - all applied and reviewed);
     draw calls -40 % on 1v1 maps and -67 % on the six-seat stress map at the same view; shield leftovers
     and other dead code removed; bugs fixed (see CHANGELOG 0.18.0). Before / after renders identical.

## 2026-09-25 - Daniele, Alpha 18 phone check (v0.18.0 live)

101. **"All maps are still waaay too big ... the bridge should be like 1/3 of now, game is unplayable."**
     Measured: baked decks were 6.9 / 28.8 / 44.2 m (median, S / M / L) against the kit's honest 4 / 8 /
     12 m - M and L about 3.6x too long. Cause: maps 4.0 draw a deck module as 12 units but nodes only
     ~9 units apart, so no uniform scale fits both the 12 m platforms and short decks; the scale was
     chosen for clearance only and deck length was never checked against the kit (my miss). **Decided
     (Daniele): regenerate the pack at the kit's sizes** ("maps 4.1": 1 unit = 1 m, platform R 6, pier
     1.6, module 4, S / M / L centre-to-centre 19.2 / 23.2 / 27.2, >= 15 between node centres, 160 x 80
     frame); the game bakes it at 1 m per unit with no stretching. Next bake adds a deck-length check.
102. **Maps 4.1 (partial): "remove old ones and start implement these".** *Done (0.18.1):* maps 4.0 removed from the
     game; the 18 maps of 4.1 baked at 1 m per unit with honest decks (4.1 / 8.3 / 12.4 m); tap targets 44-67 pt
     at 58-66 degrees; deck-length check added to test_maps4.
103. **Maps 4.2: "implement them and replace the old ones, then push to live".** *Done (0.18.2):* 20 compact
     maps at the kit's sizes, no plazas, Alpha 11 arena scale; all bake clean; camera 58 degrees, taps 45-66 pt.
104. **"Pick up the main 4 map of the alpha 11, aurora trident and the other 2".** *Done (0.18.3):* A-01 Orbital
     Nexus, A-02 Switchback Foundry, A-03 Aurora Concourse, A-04 Trident Exchange - Alpha 11's own layouts (the
     4.2 maps of those names are new layouts), redrawn at the kit's sizes with honest decks, fair seats, no
     relays; all bake clean, taps 56-88 pt at 58 degrees. Open: relays from the design guide's retrofit plan,
     the duplicate names, Alpha 11's any-vat cannons (OPEN-QUESTIONS 2026-09-26).

## 2026-09-26 - Daniele, 0.18.4 brief

105. **"When a rotating bridge turns all units that are on it are shaken down into the void (centrifugal)."**
     *Done:* rotation flings every line on its turning decks off into the void; animation, toast, AI.
106. **"Deck speed on brawl a bit slower ... reduce by 20% brawl unit movement speed."** *Done:* 5.7 m/s.
107. **"If the borders are gone have the camera zoom in to make it more epic."** *Done:* the view eases onto
     the survivors after each Last Stand drop.
108. **"On brawl units entering the building ... violently shaking toward the door instead of orderly
     entering."** *Done:* stable body identities, continuous pour-in, smooth corners.
109. **"Don't use A B and C but use emblems in the color of the owner; the emblem identifies their race."**
     *Done:* badges, inspector and toasts.
110. **"Don't make all outward rings fall at the same time but one after the other, 5 s apart, following the
     rule for falling bridges."** *Done:* platforms drop one by one, 5 s apart, never leaving an island.

