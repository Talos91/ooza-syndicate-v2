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

## Known gaps in this slice (not playtest findings)

- Vat upgrades, cannons/forges in play, relays, abilities, Last Stand, multiplayer.
- Army numbers in `scripts/rules.gd` are placeholders (army scale and base caps are open questions).
