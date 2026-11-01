"""MAP SCORECARD - pictures (🗺️ map-score, 2026-11-02).
  python tests/map_score_charts.py <scorecard.json> <thumbs dir> <out dir>
Writes map-scorecard-sheet.png (ranked thumbnails with score), chart-score.png (score by part), chart-fairness.png
(seat A win % and Veteran-vs-Standard % with 95 % intervals), chart-pace.png (median length, middle half, 7:00 hard ends)."""
import json, sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw, ImageFont

SURF, INK, INK2, GRID = "#1a1a19", "#f0efec", "#c3c2b7", "#383835"
SERIES = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#9085e9"]   # dark-mode categorical, fixed order
PARTS = [("fair", "Fairness (25)"), ("skill", "Skill matters (20)"), ("pace", "Pace (15)"), ("drama", "Comebacks (15)"),
         ("relays", "Relays (15)"), ("phone", "Phone (10)")]
W = {"fair": 25, "skill": 20, "pace": 15, "drama": 15, "relays": 15, "phone": 10}


def style(ax):
    ax.set_facecolor(SURF)
    for s in ax.spines.values():
        s.set_visible(False)
    ax.tick_params(colors=INK2, labelsize=8, length=0)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def fig(h):
    f = plt.figure(figsize=(11, h), dpi=120, facecolor=SURF)
    plt.rcParams["font.family"] = "Segoe UI"
    return f


def chart_score(rows, out):
    rows = rows[::-1]
    f = fig(0.26 * len(rows) + 1.6)
    ax = f.add_axes([0.2, 0.06, 0.62, 0.86]); style(ax)
    y = range(len(rows))
    wsum = [sum(W[k] for k in W if r["parts"][k] is not None) for r in rows]
    left = [0.0] * len(rows)
    for i, (k, lab) in enumerate(PARTS):
        vals = [100 * W[k] * (r["parts"][k] or 0) / ws for r, ws in zip(rows, wsum)]
        ax.barh(list(y), vals, left=left, height=0.72, color=SERIES[i], edgecolor=SURF, linewidth=1.5, label=lab)
        left = [a + b for a, b in zip(left, vals)]
    for yy, r in zip(y, rows):
        ax.text(r["score"] + 1, yy, "%.0f" % r["score"], va="center", color=INK, fontsize=8)
    ax.set_yticks(list(y)); ax.set_yticklabels(["%s %s  (%s)" % (r["code"], r["name"], r["size"]) for r in rows], color=INK, fontsize=8)
    ax.set_xlim(0, 100); ax.set_ylim(-0.6, len(rows) - 0.4)
    ax.set_title("Map score 0-100, by part (weights in brackets) - 38 pooled 1v1 maps, AI vs AI", color=INK, fontsize=11, loc="left")
    ax.legend(loc="center left", bbox_to_anchor=(1.01, 0.5), frameon=False, labelcolor=INK, fontsize=8)
    f.savefig(out, facecolor=SURF); plt.close(f)


def chart_fair(rows, out):
    rows = rows[::-1]
    f = fig(0.26 * len(rows) + 1.6)
    for j, (key, title, band) in enumerate([("seatA", "Seat A win % (Expert mirror, 95 % CI)", (45, 55)),
                                            ("vet", "Veteran beats Standard % (95 % CI)", None)]):
        ax = f.add_axes([0.16 + j * 0.42, 0.06, 0.36, 0.86]); style(ax)
        y = list(range(len(rows)))
        if band:
            ax.axvspan(*band, color=GRID, alpha=0.6, linewidth=0)
            ax.axvline(50, color=INK2, linewidth=0.8)
        else:
            ax.axvline(50, color=INK2, linewidth=0.8)
        for yy, r in zip(y, rows):
            p, lo, hi = 100 * r[key + "_win"], 100 * r[key + "_lo"], 100 * r[key + "_hi"]
            c = SERIES[0] if j == 0 else SERIES[2]
            ax.plot([lo, hi], [yy, yy], color=c, linewidth=2, solid_capstyle="round")
            ax.plot([p], [yy], "o", color=c, markersize=6, markeredgecolor=SURF, markeredgewidth=1.5)
        ax.set_xlim(20, 100 if j else 80); ax.set_ylim(-0.6, len(rows) - 0.4)
        ax.set_yticks(y)
        ax.set_yticklabels([r["code"] + " " + r["name"] if j == 0 else "" for r in rows], color=INK, fontsize=8)
        ax.set_title(title, color=INK, fontsize=10, loc="left")
    f.savefig(out, facecolor=SURF); plt.close(f)


def chart_pace(rows, out):
    rows = rows[::-1]
    f = fig(0.26 * len(rows) + 1.6)
    ax = f.add_axes([0.16, 0.06, 0.5, 0.86]); style(ax)
    y = list(range(len(rows)))
    ax.axvspan(240, 360, color=GRID, alpha=0.6, linewidth=0)
    ax.axvline(420, color=INK2, linewidth=0.8, linestyle=":")
    for yy, r in zip(y, rows):
        ax.plot([r["p25_s"], r["p75_s"]], [yy, yy], color=SERIES[3], linewidth=2, solid_capstyle="round")
        ax.plot([r["median_s"]], [yy], "o", color=SERIES[3], markersize=6, markeredgecolor=SURF, markeredgewidth=1.5)
    ax.set_yticks(y); ax.set_yticklabels([r["code"] + " " + r["name"] for r in rows], color=INK, fontsize=8)
    ax.set_xlim(60, 440); ax.set_ylim(-0.6, len(rows) - 0.4)
    ax.set_title("Match length s: median, middle half (band = 4:00-6:00 target, dotted = 7:00 hard end)", color=INK, fontsize=10, loc="left")
    ax2 = f.add_axes([0.7, 0.06, 0.26, 0.86]); style(ax2)
    ax2.barh(y, [100 * r["hard_end"] for r in rows], height=0.6, color=SERIES[4], edgecolor=SURF, linewidth=1.5, label="7:00 hard end")
    ax2.barh(y, [100 * r["comeback"] for r in rows], height=0.25, color=SERIES[2], label="comeback (winner was < 40 %)")
    ax2.set_yticks(y); ax2.set_yticklabels([""] * len(rows))
    ax2.set_xlim(0, 100); ax2.set_ylim(-0.6, len(rows) - 0.4)
    ax2.set_title("% of matches", color=INK, fontsize=10, loc="left")
    ax2.legend(loc="lower right", frameon=False, labelcolor=INK, fontsize=7)
    f.savefig(out, facecolor=SURF); plt.close(f)


def sheet(rows, thumbs, out, cols=6, tw=320, th=180):
    pad, lab = 10, 46
    n = len(rows)
    rws = (n + cols - 1) // cols
    W_, H_ = cols * (tw + pad) + pad, rws * (th + lab + pad) + pad + 50
    im = Image.new("RGB", (W_, H_), SURF)
    d = ImageDraw.Draw(im)
    fb = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 15)
    fr = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 12)
    ft = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 20)
    d.text((pad, 12), "Map scorecard 2026-11-02 - 38 pooled 1v1 maps ranked (score 0-100; AI vs AI, live 0.23.20 rules)", font=ft, fill=INK)
    for i, r in enumerate(rows):
        x = pad + (i % cols) * (tw + pad)
        y = 50 + pad + (i // cols) * (th + lab + pad)
        p = os.path.join(thumbs, r["code"] + ".png")
        if os.path.exists(p):
            t = Image.open(p).convert("RGB").resize((tw, th))
            im.paste(t, (x, y))
        sc = r["score"]
        col = "#0ca30c" if sc >= 60 else ("#fab219" if sc >= 45 else "#d03b3b")
        d.rectangle([x, y, x + 52, y + 26], fill=SURF)
        d.text((x + 6, y + 2), "%.0f" % sc, font=fb, fill=col)
        d.text((x + tw - 30, y + 4), "#%d" % r["rank"], font=fr, fill=INK)
        d.text((x, y + th + 3), "%s %s  ·  %s %d plat" % (r["code"], r["name"], r["size"], r["platforms"]), font=fb, fill=INK)
        d.text((x, y + th + 23), "A %.0f%%  Vet %.0f%%  %.0fs  7:00 %.0f%%  relays %d" % (
            100 * r["seatA_win"], 100 * r["vet_win"], r["median_s"], 100 * r["hard_end"], r["relay_nodes"]), font=fr, fill=INK2)
    im.save(out)


if __name__ == "__main__":
    rows = json.load(open(sys.argv[1], encoding="utf-8"))
    for r in rows:
        r["seatA_win"], r["seatA_lo"], r["seatA_hi"] = r["seatA_win"], r["seatA_lo"], r["seatA_hi"]
    o = sys.argv[3]
    os.makedirs(o, exist_ok=True)
    sheet(rows, sys.argv[2], os.path.join(o, "map-scorecard-sheet.png"))
    chart_score(rows, os.path.join(o, "chart-score.png"))
    chart_fair(rows, os.path.join(o, "chart-fairness.png"))
    chart_pace(rows, os.path.join(o, "chart-pace.png"))
    print("written", o)
