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

## Known gaps in this slice (not playtest findings)

- Vat upgrades, cannons/forges in play, relays, abilities, Last Stand, multiplayer.
- Army numbers in `scripts/rules.gd` are placeholders (army scale and base caps are open questions).
