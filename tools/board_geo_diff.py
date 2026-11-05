"""GMN boards: does a RESTYLED pack keep the locked geometry? Compares every piece's shape (alpha) with the geometry master.

    python tools/board_geo_diff.py "<...>/gmn-2/geometry-master-round-07" "<...>/gmn-2/boards"

Geometry first, style second (Daniele, 2026-11-05): the master pack fixes every outline, bolt, window, socket, radius and
9-slice margin; a restyle may repaint colour, texture, light and glow only INSIDE those shapes. Both folders hold
board-<n>.png + board-<n>W.png + boards.json. Per piece: the cut map must be identical, and the alpha masks (alpha > 128, colour
and W) may differ by at most MAX_PCT of the piece's shape, except the organic layers (ORGANIC: goo, shine, drips, splash, neon
halo outside the shape) which are reported but never fail. Exit 1 on any failure.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MAX_PCT = 0.5
ORGANIC = ("_liquid", "_shine", "_surface", "send_tank_drip", "node_send_", "node_capture_burst", "alert_sign_pulse", "_lit_")


def load(d: Path):
    j = json.loads((d / "boards.json").read_text(encoding="utf-8"))
    sheets = {b["board"]: [np.array(Image.open(d / f"board-{b['board']}{s}.png").getchannel("A")) for s in ("", "W")] for b in j["boards"]}
    return {p["name"]: p for p in j["pieces"]}, sheets


def main(master: Path, new: Path) -> int:
    mp, ms = load(master)
    np_, ns = load(new)
    fails = 0
    for name, p in mp.items():
        q = np_.get(name)
        if q is None:
            print(f"FAIL {name}: missing")
            fails += 1
            continue
        keys = ("box", "canvas", "body_rect", "slice", "board", "socket_centre_body", "ring_centre_canvas")
        if any(p.get(k) != q.get(k) for k in keys):
            print(f"FAIL {name}: cut map changed")
            fails += 1
            continue
        x, y, w, h = p["box"]
        worst = 0.0
        for i in (0, 1):
            a = ms[p["board"]][i][y:y + h, x:x + w] > 128
            b = ns[q["board"]][i][y:y + h, x:x + w] > 128
            worst = max(worst, 100.0 * (a ^ b).sum() / max(a.sum(), 1))
        organic = any(o in name for o in ORGANIC)
        if worst > MAX_PCT:
            print(f"{'note' if organic else 'FAIL'} {name}: shape differs {worst:.2f} %{' (organic layer)' if organic else ''}")
            fails += 0 if organic else 1
    print(f"{len(mp)} pieces checked against the master; {fails} geometry failures")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
