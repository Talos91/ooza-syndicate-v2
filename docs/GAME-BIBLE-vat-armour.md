# GAME-BIBLE addition - Vat armour (sim-armour, 2026-11-03; for GAME-BIBLE §4 "Nodes and structures")

**Vat armour** (Daniele, 2026-11-03). An owned vat's garrison takes less damage the higher its tier: armour T1 x1.0, T2 x1.2, T3 x1.4, T4 x1.6
(`Rules.ARMOUR_TIER`), multiplied with Fortify / Aegis and the forge's defence in `Sim.garrison_div`. A capture keeps the tier rules as before
(T1-T3 lose one, a T4 stays T4) but the armour starts again at x1.0 and regains 0.01 a second (`ARMOUR_REGAIN_PER_S`) up to its tier's value:
T2 in 20 s, T3 40 s, T4 60 s. An upgrade climbs the same way to the new tier; a swap to another structure drops it to 1.0. Neutral nodes have none.
Readout: the node inspector's "Armour x1.30 -> x1.6 in 30 s" line. Telemetry (same branch): the match event carries `match_id` and `relay_types`.
