"""GMN-2: cuts the art director's production boards into the per-folder file set tools/hud_noir_import.py takes.

    python tools/board_cut.py "<...>/hud-redo/generated/glass-metal-neon/gmn-2/boards" "<out>/delivery"
    python tools/hud_noir_import.py "<out>/delivery"            (HUD: A_top, B_send, C_right, D_board)
    python tools/hud_noir_import.py --node "<out>/delivery"     (E_node)

The boards folder holds board-<n>.png (colour) + board-<n>W.png (white tint twin, same layout) + boards.json (the cut map:
name, folder, board, box x,y,w,h, canvas, body_rect, slice, drip_height, has_tint, socket / ring metadata; boards.txt is the
same map for people). Each box IS the piece's canvas (body at 48,48), so a cut is a plain crop, never a scale.

Which board a piece comes from (the game tints white layers per seat / faction and draws everything else as painted):
    no tint pixels                         the colour board (metal, glass, bolts, dark panels, fixed alert colours, shine)
    tint only (every colour pixel is in W) the W board: pure white, shading in alpha - the game tints it
    node_slice_lit_*                       the W board: the lit SIGNAL only; the game draws node_slice_off_* (same metal and
                                           bolts) under it and tints the signal (README: "OFF colour piece plus the LIT W signal")
    other mixed pieces (metal + gel)       the colour board as painted; the W mask goes to <out>/_masks/ for a later material
Writes <out>/<folder>/<file>.png + <folder>/parts-list.txt (GMN-1 format, socket / ring centre in BODY px), <out>/cut.json
(every piece's metadata + which board it came from) and checks every crop (canvas size, not empty unless the W box is meant
to be empty). The boards are only read.
"""
import json
import sys
from pathlib import Path

from PIL import Image

HEAD = "file | canvas px | slice L,T,R,B or fixed | drip px | body rect | socket centre in body"


def tint_only(col: Image.Image, white: Image.Image) -> bool:
    """True when every visible colour pixel is also in the white twin (a pure gel / neon layer)."""
    ca, wa = col.getchannel("A"), white.getchannel("A")
    cm = ca.point(lambda v: 255 if v > 8 else 0)
    wm = wa.point(lambda v: 255 if v > 8 else 0)
    if not wm.getbbox():
        return False
    from PIL import ImageChops
    return ImageChops.subtract(cm, wm).getbbox() is None


def main(boards: Path, out: Path) -> int:
    meta = json.loads((boards / "boards.json").read_text(encoding="utf-8"))
    sheets = {}
    for b in meta["boards"]:
        n = b["board"]
        sheets[n] = (Image.open(boards / f"board-{n}.png").convert("RGBA"), Image.open(boards / f"board-{n}W.png").convert("RGBA"))
        for im in sheets[n]:
            if list(im.size) != list(b["canvas"]):
                print(f"board {n}: size {im.size} != boards.json {b['canvas']}")
                return 1
    out.mkdir(parents=True, exist_ok=True)
    rows, report, bad = {}, [], 0
    for p in meta["pieces"]:
        col, white = sheets[p["board"]]
        x, y, w, h = p["box"]
        if [w, h] != list(p["canvas"]):
            print(f"{p['name']}: box {w}x{h} != canvas {p['canvas']}")
            bad += 1
            continue
        c = col.crop((x, y, x + w, y + h))
        wt = white.crop((x, y, x + w, y + h))
        if p["name"].startswith("node_slice_lit_"):
            src, im = "W signal", wt
        elif p.get("has_tint") and tint_only(c, wt):
            src, im = "W", wt
        else:
            src, im = "colour", c
            if p.get("has_tint") and wt.getchannel("A").getbbox():
                (out / "_masks").mkdir(exist_ok=True)
                wt.save(out / "_masks" / f"{p['name']}_mask.png")
                src = "colour (+ _masks)"
        if not im.getchannel("A").getbbox():
            print(f"{p['name']}: empty crop ({src})")
            bad += 1
        folder = out / p["folder"]
        folder.mkdir(exist_ok=True)
        im.save(folder / p["file"])
        bx, by = p["body_rect"][0], p["body_rect"][1]
        sock = p.get("socket_centre_body")
        if sock is None and "ring_centre_canvas" in p:            # radial sectors: the ring centre (outside the canvas, left)
            sock = [p["ring_centre_canvas"][0] - bx, p["ring_centre_canvas"][1] - by]
        sl = p["slice"] if isinstance(p["slice"], list) else "fixed"
        fmt = lambda v: "%g" % v
        rows.setdefault(p["folder"], []).append(" | ".join([
            p["file"], "[%d, %d]" % tuple(p["canvas"]), sl if sl == "fixed" else "[%s]" % ", ".join(str(v) for v in sl),
            str(p.get("drip_height", 0)), "[%s]" % ", ".join(str(v) for v in p["body_rect"]),
            "-" if sock is None else "[%s]" % ", ".join(fmt(v) for v in sock)]))
        report.append(dict(p, source=src))
    for folder, lines in rows.items():
        (out / folder / "parts-list.txt").write_text("\n".join([HEAD] + lines) + "\n", encoding="utf-8", newline="\n")
    (out / "cut.json").write_text(json.dumps({"boards": str(boards), "pieces": report}, indent=1), encoding="utf-8")
    counts = {}
    for r in report:
        counts[r["source"]] = counts.get(r["source"], 0) + 1
    print(f"{len(report)} pieces -> {out} ({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))}); {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
