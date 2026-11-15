"""Paths and the kit's numbers. Game numbers are read from Game/2.0/scripts/rules.gd so the builder never
drifts from the game; the planner's numbers come from the approved builder itself (planner.py)."""
import ast
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.dirname(HERE)
ROOT = os.environ.get("OOZE_ROOT") or os.path.dirname(os.path.dirname(TOOL))   # H:/My Drive/PROJECTS/Ooze Syndicate (MAP-SIZE copy: env)
GAME = os.path.join(ROOT, "Game", "2.0")
RULES_GD = os.environ.get("OOZE_RULES_GD") or os.path.join(GAME, "scripts", "rules.gd")
BUILDER = os.path.join(ROOT, "Models", "2.0", "build_maps_4_2_review.py")
EXPORTER = os.path.join(ROOT, "Models", "2.0", "export_maps_4_2_game.py")
REFS = os.path.join(ROOT, "References")
BAKED = os.path.join(GAME, "maps4")

# every pack the exporter bakes today (export_maps_4_2_game.py), in its order
PACKS = [
    "Ooze Syndicate maps 4.2",
    "Ooze Syndicate maps 4.2 - Alpha 11 classics",
    "Ooze Syndicate maps 4.2 - tutorial",
    "Ooze Syndicate maps 4.3 classic",
    "Ooze Syndicate maps 4.4 classic",
    "Ooze Syndicate maps 4.6 relay",
]


def _num(expr):
    """Evaluate a GDScript numeric constant expression (numbers, + - * / and parentheses only)."""
    tree = ast.parse(expr, mode="eval")
    for n in ast.walk(tree):
        if not isinstance(n, (ast.Expression, ast.BinOp, ast.UnaryOp, ast.Constant, ast.Add, ast.Sub,
                              ast.Mult, ast.Div, ast.USub, ast.UAdd)):
            raise ValueError(expr)
    return float(eval(compile(tree, "<gd>", "eval"), {"__builtins__": {}}))


def game_constants(path=RULES_GD):
    out = {}
    pat = re.compile(r"^\s*(?:static\s+var|const)\s+([A-Z_][A-Z0-9_]*)\s*:?=\s*([-0-9.+*/() ]+?)\s*(?:#.*)?$")
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = pat.match(line)
            if m:
                try:
                    out[m.group(1)] = _num(m.group(2))
                except (ValueError, SyntaxError):
                    pass
    return out


GC = game_constants()
R = GC.get("R", 6.0)                       # platform radius
PIER = GC.get("PIER", 1.6)                 # connector beyond the rim
S = GC.get("S", 4.0)                       # one deck module
EXIT_R = GC.get("EXIT_R", 2.2)             # units leave from the tank bottoms
BRAWL_RING = GC.get("BRAWL_RING", 4.8)     # BRAWL walk ring round the tower
BRAWL_SPEED = GC.get("BRAWL_SPEED", 8.9 * 0.8 * 0.8)
MODS = {"S": 1, "M": 2, "L": 3}
# DECK KNOB (map-shrink 2026-11-15): every deck's honest length = its tier's modules x S x DECK_K. Default 1 = tiers 4 / 8 / 12 m;
# 0.5 = 2 / 4 / 6 m (Daniele 2026-11-15, maps too big on a phone). Set by env OOZE_DECK_K or `--deck-k=` on packs/shrink_pool.py.
# Tier letters keep their design modules; a baked map carries the result per edge in `modules` (mb/shrink.py).
DECK_K = float(os.environ.get("OOZE_DECK_K", "1"))


def deck_m(tier):
    """Honest deck length in metres of a tier at the current knob (4 / 8 / 12 m at DECK_K 1)."""
    return MODS[tier] * S * DECK_K
SECONDS = {"S": 2, "M": 4, "L": 6}         # the pack's legacy "seconds" field (1:2:3), written for compatibility
CENTRE = {t: 2 * (R + PIER) + deck_m(t) for t in MODS}        # 19.2 / 23.2 / 27.2 m centre to centre at DECK_K 1 (17.2 / 19.2 / 21.2 at 0.5)
FRAME_W, FRAME_H = 160.0, 80.0
