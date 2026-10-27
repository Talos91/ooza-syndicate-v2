"""A/B tables: python -I tests/balance_ab.py <dir> <prefix>  (habit / power / override studies of tests/balance_study.gd)."""
import glob, json, sys
from collections import defaultdict
d, prefix = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for p in glob.glob(f"{d}/{prefix}*.jsonl") for l in open(p) if l.strip()]
g = defaultdict(list); gf = defaultdict(lambda: defaultdict(list))
for r in rows:
    w = r["winner"]; v = r["vseat"]
    s = 0.5 if w == "" else (1.0 if w == v else 0.0)
    g[r["study"]].append(s); gf[r["study"]][r["spec"][v]].append(s)
def ci(x):
    n = len(x); p = sum(x) / n; return 1.96 * (p * (1 - p) / n) ** 0.5 * 100
print(len(rows), "matches")
for k in sorted(g, key=lambda k: -sum(g[k]) / len(g[k])):
    x = g[k]
    print(f"{k:<28} WR {sum(x)/len(x)*100:5.1f} +-{ci(x):4.1f} n={len(x):4d} | " + " ".join(f"{f}:{sum(v)/len(v)*100:3.0f}" for f, v in sorted(gf[k].items())))
