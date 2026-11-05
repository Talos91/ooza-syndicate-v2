"""GMN boards: does a RESTYLED pack keep the locked geometry? Compares every piece's shape (alpha) with the geometry master.

    python tools/board_geo_diff.py "<...>/gmn-2/geometry-master-round-07" "<...>/gmn-2/boards"
    python tools/board_geo_diff.py --spec "<...>/DIRECTOR-RESTART/09-GEOMETRY-SPEC/geometry-spec.json" "<cut folder>" [bolt-stamps.json]

--spec: the INSIDE of the plates (alpha alone can't see it): every dark inset rect measured on the cut piece (tools/board_cut.py
output) must match the spec within TOL px, and every bolt in the pack's QA bolt-stamps.json must have the spec's centre and diameter.

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


TOL = 2

import math
from scipy import ndimage
def rr_radius(m):
    """rounded-rect corner radius from a mask: distance along the 45-deg diagonal from the bbox corner to the edge = r(sqrt2-1)"""
    ys,xs=np.where(m); x0,y0=xs.min(),ys.min(); x1,y1=xs.max()+1,ys.max()+1
    f=m.astype(float); res=[]
    for (cx,cy,sx,sy) in [(x0,y0,1,1),(x1,y0,-1,1),(x0,y1,1,-1),(x1,y1,-1,-1)]:
        t=0.0
        while t<min(x1-x0,y1-y0)/2:
            x=cx+sx*t/math.sqrt(2); y=cy+sy*t/math.sqrt(2)
            if f[int(min(max(y- (0 if sy>0 else 1),0),f.shape[0]-1)), int(min(max(x-(0 if sx>0 else 1),0),f.shape[1]-1))]>0: break
            t+=0.25
        res.append(t/(math.sqrt(2)-1))
    return round(float(np.mean(res)),1), [x0,y0,x1-x0,y1-y0]

def edges(l, a, comp):
    ys,xs=np.where(comp); cy=int((ys.min()+ys.max())//2); cx=int((xs.min()+xs.max())//2)
    d=(l<100)&(a>=128)
    if not d[cy,cx]:   # ring-shaped inset (hole in the middle): its own bbox
        return [int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)]
    x0=cx
    while x0>0 and d[cy,x0-1]: x0-=1
    x1=cx
    while x1<l.shape[1]-1 and d[cy,x1+1]: x1+=1
    y0=cy
    while y0>0 and d[y0-1,cx]: y0-=1
    y1=cy
    while y1<l.shape[0]-1 and d[y1+1,cx]: y1+=1
    return [int(x0),int(y0),int(x1-x0+1),int(y1-y0+1)]
def measure(path, bolts):
    im=Image.open(path); a=np.array(im.getchannel('A')); l=np.array(im.convert('RGB')).astype(float).mean(axis=2)
    orad,orect=rr_radius(a>=128); out={'outline':[int(v) for v in orect],'outline_radius':round(orad)}
    lab,n=ndimage.label((l<62)&(a>=128)); ins=[]
    for k in range(1,n+1):
        comp=lab==k
        if comp.sum()<2000: continue
        rect=edges(l,a,comp); x,y,w,h=rect
        m=np.zeros_like(comp); m[y:y+h,x:x+w]=((l<100)&(a>=128))[y:y+h,x:x+w]
        r=rr_radius(m)[0] if m.any() else 0.0; r=min(r,min(w,h)/2)
        hidden=any(abs(b['centre'][0]-cx)<b['diameter']/2+r and abs(b['centre'][1]-cy)<b['diameter']/2+r for b in bolts for cx in (x,x+w) for cy in (y,y+h))
        ins.append({'rect':rect,'radius':round(r) if not hidden else None,'corner_under_bolt':bool(hidden)})
    out['dark_insets']=sorted(ins,key=lambda d:(d['rect'][1],d['rect'][0])) if ins else []
    return out


def spec_check(spec: Path, cut: Path, stamps: Path | None) -> int:
    s = json.loads(spec.read_text(encoding='utf-8'))
    meta = {p['name']: p for p in json.loads((cut / 'cut.json').read_text(encoding='utf-8'))['pieces']}
    fails = 0
    for n, d in s.items():
        if 'dark_insets' not in d:
            continue
        p = meta[n]
        got = [i['rect'] for i in measure(cut / p['folder'] / p['file'], d.get('bolts', []))['dark_insets']]
        want = [i['rect'] for i in d['dark_insets']]
        steel = [k for k, i in enumerate(d['dark_insets']) if not i.get('glass')]   # glass may carry painted highlights
        if not steel:
            continue
        near = lambda w: any(all(abs(a - b) <= TOL for a, b in zip(g, w)) for g in got)
        if not all(near(want[k]) for k in steel):
            print(f'FAIL {n}: dark inset {got} != spec {want} (+-{TOL} px)')
            fails += 1
    if stamps:
        have = {}
        for b in json.loads(stamps.read_text(encoding='utf-8')):
            have.setdefault(b['piece'], []).append({'centre': b['centre'], 'diameter': b['size']})
        for n, d in s.items():
            if 'bolts' in d and sorted(map(str, have.get(n, []))) != sorted(map(str, d['bolts'])):
                print(f"FAIL {n}: bolts {have.get(n, [])[:1]} != spec {d['bolts'][:1]}")
                fails += 1
    print(f'spec check: {fails} failures')
    return 1 if fails else 0


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
    if sys.argv[1] == "--spec":
        sys.exit(spec_check(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]) if len(sys.argv) > 4 else None))
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
