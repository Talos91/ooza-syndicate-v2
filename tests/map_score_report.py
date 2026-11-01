"""MAP SCORECARD - report (🗺️ map-score, 2026-11-02; measurement only).
  python tests/map_score_report.py <data dir> <out dir>
Reads <data dir>/static.json, fair_*.jsonl, skill_*.jsonl, phone.txt (tests/phone_fit.tscn output, optional) and writes
<out dir>/map-scorecard.csv, scorecard.json and the markdown table (scorecard-table.md). Weighting in WEIGHTS below."""
import json, sys, os, glob, math, statistics as st, re
from collections import defaultdict

# One overall score 0-100 per map. Each part maps a measured value onto 0..1, times its weight.
WEIGHTS = {
    "fair": 25,    # seat A win rate (Expert mirror): 1 at 50 %, 0 at 35 / 65 %
    "skill": 20,   # Veteran beats Standard: 0 at 50 %, 1 at 80 %+
    "pace": 15,    # median length in 240..360 s and few 7:00 hard ends
    "drama": 15,   # comebacks + lead changes
    "relays": 15,  # relays get used and using them pays
    "phone": 10,   # smallest tap target: 0 at 33 pt, 1 at 44 pt+
}


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (p, c - h, c + h)


def leads(share, start=4):
    """Lead changes with a 55 / 45 band (seat A's share of total strength, 5 s samples, from 20 s)."""
    state, ch = None, 0
    for s in share[start - 1:]:
        cur = "A" if s > 0.55 else ("B" if s < 0.45 else state)
        if state is not None and cur != state:
            ch += 1
        state = cur
    return ch


def load(pattern):
    out = []
    for f in sorted(glob.glob(pattern)):
        for line in open(f, encoding="utf-8"):
            if line.strip():
                out.append(json.loads(line))
    return out


def phone_rows(path):
    rows = {}
    if not os.path.exists(path):
        return rows
    for line in open(path, encoding="utf-8"):
        m = re.match(r"CHOICE\s+(\S+).*?pitch\s*=?\s*([\d.]+).*?tap\s*=?\s*([\d.]+)", line)
        if m:
            rows[m.group(1)[:4]] = {"pitch": float(m.group(2)), "tap": float(m.group(3))}
    return rows


def main(d, outd):
    os.makedirs(outd, exist_ok=True)
    S = json.load(open(os.path.join(d, "static.json"), encoding="utf-8"))
    fair = defaultdict(list)
    for r in load(os.path.join(d, "fair_*.jsonl")):
        fair[r["map"]].append(r)
    skill = defaultdict(list)
    for r in load(os.path.join(d, "skill_*.jsonl")):
        skill[r["map"]].append(r)
    phone = phone_rows(os.path.join(d, "phone.txt"))
    out = []
    for code, s in S.items():
        F = fair.get(code, [])
        n = len(F)
        a_pts = sum(1.0 if r["winner"] == "A" else (0.5 if r["winner"] == "" else 0.0) for r in F)
        p, lo, hi = wilson(a_pts, n)
        t = [r["t"] for r in F]
        forced = sum(1 for r in F if r["forced"]) / max(1, n)
        ls = sum(1 for r in F if r["ls_t"] > 0) / max(1, n)
        lc, cb = [], 0
        for r in F:
            lc.append(leads(r["share"]))
            w = r["winner"]
            if w in ("A", "B"):
                ws = [x if w == "A" else 1 - x for x in r["share"][12:]]          # after 60 s
                if ws and min(ws) < 0.40:
                    cb += 1
        fires = [r["fires"]["A"] + r["fires"]["B"] for r in F]
        rkill = [r["relay_kill"]["A"] + r["relay_kill"]["B"] for r in F]
        more, more_w, kmore, kmore_w = 0, 0, 0, 0
        for r in F:
            fa, fb = r["fires"]["A"], r["fires"]["B"]
            if fa != fb and r["winner"] in ("A", "B"):
                more += 1
                more_w += 1 if (r["winner"] == "A") == (fa > fb) else 0
            ka, kb = r["relay_kill"]["A"], r["relay_kill"]["B"]
            if abs(ka - kb) >= 5 and r["winner"] in ("A", "B"):
                kmore += 1
                kmore_w += 1 if (r["winner"] == "A") == (ka > kb) else 0
        node_fires = defaultdict(int)
        kinds = {}
        for r in F:
            for k, v in r["fires_by_node"].items():
                node_fires[k] += v
            kinds.update(r["relay_kinds"])
        per_kind = defaultdict(float)
        for k, v in node_fires.items():
            per_kind[kinds.get(k, "?")] += v / max(1, n)
        idle_relays = sum(1 for k in kinds if node_fires.get(k, 0) / max(1, n) < 0.25)
        K = skill.get(code, [])
        vk = sum(1.0 if r["winner"] and r["spec"][r["winner"]][1] == "Veteran" else (0.5 if r["winner"] == "" else 0.0) for r in K)
        vp, vlo, vhi = wilson(vk, len(K))
        tK = [r["t"] for r in K]
        ph = phone.get(code, {})
        row = dict(s)
        row.update({
            "n_fair": n, "seatA_win": round(p, 3), "seatA_lo": round(lo, 3), "seatA_hi": round(hi, 3),
            "median_s": round(st.median(t), 1) if t else None, "p25_s": round(sorted(t)[len(t) // 4], 1) if t else None,
            "p75_s": round(sorted(t)[3 * len(t) // 4], 1) if t else None,
            "hard_end": round(forced, 3), "ls_reached": round(ls, 3),
            "lead_changes": round(st.mean(lc), 2) if lc else None, "comeback": round(cb / max(1, n), 3),
            "relay_fires": round(st.mean(fires), 2) if fires else None, "relay_kills": round(st.mean(rkill), 1) if rkill else None,
            "relay_fire_more_win": round(more_w / more, 3) if more else None, "relay_fire_n": more,
            "relay_kill_more_win": round(kmore_w / kmore, 3) if kmore else None, "relay_kill_n": kmore,
            "fires_per_kind": {k: round(v, 2) for k, v in per_kind.items()}, "idle_relays": idle_relays,
            "n_skill": len(K), "vet_win": round(vp, 3), "vet_lo": round(vlo, 3), "vet_hi": round(vhi, 3),
            "median_s_skill": round(st.median(tK), 1) if tK else None,
            "tap_pt": ph.get("tap"), "pitch": ph.get("pitch"),
        })
        # parts
        parts = {}
        parts["fair"] = clamp(1 - abs(p - 0.5) / 0.15)
        parts["skill"] = clamp((vp - 0.5) / 0.30)
        med = row["median_s"] or 0
        off = max(0.0, 240 - med, med - 360) / 120.0
        parts["pace"] = clamp(1 - off - forced)
        parts["drama"] = 0.5 * clamp(row["comeback"] / 0.25) + 0.5 * clamp((row["lead_changes"] or 0) / 1.5)
        rm = row["relay_fire_more_win"] if row["relay_fire_more_win"] is not None else 0.5
        parts["relays"] = 0.5 * clamp((row["relay_fires"] or 0) / 6.0) + 0.5 * clamp((rm - 0.5) / 0.2)
        parts["phone"] = clamp(((ph.get("tap") or 33.0) - 33.0) / 11.0) if ph else None
        tot, wsum = 0.0, 0.0
        for k, w in WEIGHTS.items():
            if parts[k] is None:
                continue
            tot += w * parts[k]; wsum += w
        row["parts"] = {k: (None if v is None else round(v, 3)) for k, v in parts.items()}
        row["score"] = round(100 * tot / wsum, 1)
        out.append(row)
    out.sort(key=lambda r: -r["score"])
    for i, r in enumerate(out):
        r["rank"] = i + 1
        r["ls_pieces_fixed"] = max(v["pieces_fixed"] for v in r["last_stand"].values())
    json.dump(out, open(os.path.join(outd, "scorecard.json"), "w", encoding="utf-8"), indent=1)
    cols = ["rank", "code", "name", "score", "size", "platforms", "junctions", "bridges", "relay_nodes", "relay_decks", "relay_kinds",
            "footprint", "lanes_min", "chokes", "relay_only", "longest_walk_s", "home_gap_s", "walk_sorted_gap_s", "ls_pieces_fixed",
            "n_fair", "seatA_win", "seatA_lo", "seatA_hi", "median_s", "p25_s", "p75_s", "hard_end", "ls_reached", "lead_changes",
            "comeback", "relay_fires", "relay_kills", "relay_fire_more_win", "relay_kill_more_win", "idle_relays", "fires_per_kind",
            "n_skill", "vet_win", "vet_lo", "vet_hi", "tap_pt", "pitch", "rule_hard", "modes",
            "p_fair", "p_skill", "p_pace", "p_drama", "p_relays", "p_phone"]
    with open(os.path.join(outd, "map-scorecard.csv"), "w", encoding="utf-8", newline="") as f:
        f.write(",".join(cols) + "\n")
        for r in out:
            for k in WEIGHTS:
                r["p_" + k] = r["parts"][k]
            vals = []
            for c in cols:
                v = r.get(c)
                if isinstance(v, (dict, list)):
                    v = json.dumps(v, separators=(" ", ":")).replace(",", ";").replace('"', "")
                vals.append("" if v is None else str(v).replace(",", ";"))
            f.write(",".join(vals) + "\n")
    md = ["| # | map | score | size | plat | relays | seat A win % (95 % CI) | Vet vs Std % | median s | 7:00 end | comeback | lead ch. | relay fires | fired-more wins | tap pt |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in out:
        rk = " ".join("%s %d" % (k[:3], v) for k, v in r["relay_kinds"].items())
        md.append("| %d | %s %s | **%.0f** | %s | %d | %s | %.0f (%.0f-%.0f) | %.0f (%.0f-%.0f) | %.0f | %.0f %% | %.0f %% | %.2f | %.1f | %s | %s |" % (
            r["rank"], r["code"], r["name"], r["score"], r["size"], r["platforms"], rk, 100 * r["seatA_win"], 100 * r["seatA_lo"],
            100 * r["seatA_hi"], 100 * r["vet_win"], 100 * r["vet_lo"], 100 * r["vet_hi"], r["median_s"] or 0, 100 * r["hard_end"],
            100 * r["comeback"], r["lead_changes"] or 0, r["relay_fires"] or 0,
            "-" if r["relay_fire_more_win"] is None else "%.0f %%" % (100 * r["relay_fire_more_win"]),
            "-" if r["tap_pt"] is None else "%.1f" % r["tap_pt"]))
    open(os.path.join(outd, "scorecard-table.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
