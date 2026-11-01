"""bal-audit charts (2026-11-02): <venv python with matplotlib> tests/balance_audit_charts.py <summary.json> <outdir>
Four PNGs for the Ooze Hub Desk cards: abilities (lift per power, today vs proposal), factions (win rate today vs proposal),
rewire (variants), machinegoon (variants). AI-vs-AI Expert data; every picture says so in its footer."""
import json, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

S = json.load(open(sys.argv[1], encoding="utf-8"))
OUT = sys.argv[2]
SURF, INK, INK2, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#8a8984", "#e6e5e1"
TYPE = {"ultimate": "#2a78d6", "active": "#eb6834", "map": "#1baf7a"}    # categorical slots 1-3 (validated all-pairs)
GREY = "#b9b8b2"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK, "figure.facecolor": SURF, "axes.facecolor": SURF})
FOOT = "Ooze Syndicate 0.23.18 live numbers - headless AI vs AI, Expert, 1v1, 28 pooled N maps, skills on, Last Stand, 7:00 end, speed-15. No human played these."


def frame(ax, title, sub):
    ax.set_title(title, loc="left", fontsize=15, fontweight="bold", color=INK, pad=26)
    ax.text(0, 1.015, sub, transform=ax.transAxes, fontsize=10.5, color=INK2, va="bottom")
    for s in ["top", "right", "left"]:
        ax.spines[s].set_visible(False)
    ax.tick_params(axis="y", length=0)


def foot(fig):
    fig.text(0.01, 0.006, FOOT, fontsize=8, color=MUTED)


def abilities():
    rows = S["powers"]                 # [name, type, lift, ci, proposed_lift or null, casts]
    rows.sort(key=lambda r: r[2])
    fig, ax = plt.subplots(figsize=(11, 9.6))
    ax.axvspan(5, 15, color="#eef3fb", zorder=0)
    ax.text(10, len(rows) - 0.35, "healthy band\n+5 .. +15", ha="center", va="bottom", fontsize=9, color=INK2)
    for i, r in enumerate(rows):
        c = TYPE[r[1]]
        ax.barh(i, r[2], height=0.62, color=c, zorder=2)
        ax.plot([r[2] - r[3], r[2] + r[3]], [i, i], color=INK2, lw=1, zorder=3)
        if r[4] is not None:
            ax.plot([r[4]], [i], marker="D", ms=8, color=INK, mec=SURF, mew=2, zorder=4)
            ax.annotate("", xy=(r[4], i), xytext=(r[2], i), arrowprops=dict(arrowstyle="-", color=INK, lw=1, ls=":"), zorder=3)
        ax.text(max(r[2] + r[3], r[4] if r[4] is not None else -99) + 0.8, i, f"{r[2]:+.0f}" + (f" -> {r[4]:+.0f}" if r[4] is not None else ""),
                va="center", fontsize=9.5, color=INK)
    ax.set_yticks(range(len(rows)), [r[0] for r in rows])
    ax.axvline(0, color=INK2, lw=1, zorder=1)
    ax.set_xlim(-6, 33)
    ax.set_xlabel("win-rate lift in points (casting it vs never casting it, same skill both sides)")
    ax.grid(axis="x", color=GRID, zorder=0)
    frame(ax, "Every power: how much casting it wins you",
          "bar = live 0.23.18 (whisker = 95 % range)   ◆ = with the proposed numbers   colour = ultimate / active / map")
    hs = [plt.Rectangle((0, 0), 1, 1, color=TYPE[k]) for k in TYPE] + \
         [plt.Line2D([], [], marker="D", ls="", color=INK, mec=SURF, ms=8)]
    ax.legend(hs, ["ultimate", "active skill", "map skill", "proposed"], loc="lower right", frameon=False)
    fig.tight_layout(rect=(0, 0.02, 1, 1))
    foot(fig)
    fig.savefig(f"{OUT}/bal-audit-abilities.png", dpi=110)


def factions():
    F = ["VEX", "NULL", "BLOOM", "EMBER", "SOLAR"]
    sets = S["factions"]               # {label: [[wr, ci] x5]}
    fig, ax = plt.subplots(figsize=(11, 5.6))
    ax.axhspan(44, 56, color="#eef3fb", zorder=0)
    labels = list(sets.keys())
    w = 0.8 / len(labels)
    cols = ["#2a78d6", "#eb6834", "#1baf7a"]
    for j, lab in enumerate(labels):
        for i, (wr, ci) in enumerate(sets[lab]):
            x = i + (j - (len(labels) - 1) / 2) * w
            ax.bar(x, wr, width=w * 0.9, color=cols[j], zorder=2, label=lab if i == 0 else None)
            ax.plot([x, x], [wr - ci, wr + ci], color=INK2, lw=1, zorder=3)
            ax.text(x, wr + ci + 0.8, f"{wr:.0f}", ha="center", fontsize=9.5, color=INK)
    ax.axhline(50, color=INK2, lw=1)
    ax.set_xticks(range(5), F)
    ax.set_ylim(30, 78)
    ax.set_ylabel("win rate % (vs the other four factions)")
    ax.grid(axis="y", color=GRID, zorder=0)
    frame(ax, "Factions: BLOOM wins two games in three", "shaded = fair band 44-56 %   whisker = 95 % range")
    ax.legend(loc="upper right", frameon=False)
    for s in ["left"]:
        ax.spines[s].set_visible(True)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    foot(fig)
    fig.savefig(f"{OUT}/bal-audit-factions.png", dpi=110)


def variants(key, title, sub, fname, xlabel, rec):
    rows = S[key]                      # [label, lift, ci]
    fig, ax = plt.subplots(figsize=(11, 0.75 * len(rows) + 2.2))
    for i, r in enumerate(rows):
        y = len(rows) - 1 - i
        c = TYPE["ultimate"] if i == 0 else ("#eb6834" if r[0] == rec else GREY)
        ax.barh(y, r[1], height=0.6, color=c, zorder=2)
        ax.plot([r[1] - r[2], r[1] + r[2]], [y, y], color=INK2, lw=1, zorder=3)
        ax.text(max(r[1] + r[2], 0) + 0.5, y, f"{r[1]:+.1f}", va="center", fontsize=10, color=INK)
    ax.set_yticks(range(len(rows)), [r[0] for r in reversed(rows)])
    ax.axvline(0, color=INK2, lw=1)
    lo = min(0, min(r[1] - r[2] for r in rows)) - 1
    hi = max(r[1] + r[2] for r in rows) + 4
    ax.set_xlim(lo, hi)
    ax.set_xlabel(xlabel)
    ax.grid(axis="x", color=GRID, zorder=0)
    frame(ax, title, sub)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    foot(fig)
    fig.savefig(f"{OUT}/{fname}", dpi=110)


abilities()
factions()
variants("rewire", "Rewire (VEX ultimate): what each version is worth",
         "blue = live   orange = recommended   grey = also measured   line = 95 % range",
         "bal-audit-rewire.png", "win-rate lift in points (casting Rewire vs never casting it, VEX vs VEX)", S["rewire_rec"])
variants("mg", "Machinegoon: what building it is worth",
         "blue = live   orange = recommended rework   grey = also measured   line = 95 % range",
         "bal-audit-machinegoon.png", "win-rate points: AI that builds Machinegoons vs the same AI that never does", S["mg_rec"])
