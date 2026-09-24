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

## Known gaps in this slice (not playtest findings)

- Real per-map relay behaviour (rotation/switch/remote/retract art and consequences), abilities,
  real Last Stand (method choice, hidden reveal, "everything on a falling node/deck dies"),
  multiplayer, attachment swap/cooldown, cannon T2/T3, forge's mixed-garrison population weighting.
- Army numbers in `scripts/rules.gd` are placeholders (army scale and base caps are open questions).
