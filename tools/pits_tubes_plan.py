"""PITS / TUBES top-down plan (dev tool) from the clipping probe's dump:

    PITS_CLIP_DUMP=<json> Godot --headless --path . res://tests/pits_tubes_clip.tscn
    python tools/pits_tubes_plan.py <json> <out png>

Every potential tube (T3 max) as its 0.27 m capsule outline, coloured by socket; the Locals' lanes dashed (pool centre ->
rim exit -> door); the column bases' 1.92 m reach as circles.
"""
import json
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle

d = json.load(open(sys.argv[1]))
fig, ax = plt.subplots(figsize=(9.0, 4.16), dpi=90)
fig.patch.set_facecolor("white")
colors = ["tab:red", "tab:blue", "tab:green", "tab:orange"]
for r in d["runs"]:
    p = r["pts"]
    ax.plot([q[0] for q in p], [q[2] for q in p], "-", color=colors[r["sock"]], lw=0.9)
for ln in d["lanes"]:
    p = ln["pts"]
    ax.plot([q[0] for q in p], [q[1] for q in p], "--", color="gray", lw=0.6)
for k, c in d["cols"].items():
    ax.add_patch(Circle((c[0], c[1]), 1.92, fill=False, color="k", lw=0.8))
ax.set_aspect("equal")
ax.set_xticks([]); ax.set_yticks([])
ax.invert_yaxis()
plt.tight_layout(pad=0.2)
plt.savefig(sys.argv[2])
print("plan", sys.argv[2])
