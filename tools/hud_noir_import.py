"""Alpha 24 Neon Noir: drops the art director's cut HUD parts into the game - each replaces its NoirBox placeholder.

    python tools/hud_noir_import.py "<...>/hud-redo/generated/parts/revision-6/delivery"
    python tools/hud_noir_import.py --node "<...>/hud-redo/generated/node/revision-<n>/delivery"

--node (Alpha 24 step 4, NODE UI): the node parts of NODE-PROMPTS.md (folder E_node: node_select, node_hub, node_wedge,
node_card, node_tier_chip, node_shield_*, node_target_ring, node_send_head, node_label_pill, node_relay_ring,
node_capture_burst) go to assets/ui/node_noir/ + scripts/node_noir_data.gd instead, so a node drop never touches the HUD's
parts (and a HUD drop never touches the node's). Same parts-list format; HudNoir reads both tables.

Re-runnable; the References are only read. The delivery holds part folders (A_top, B_send, C_right, D_board), each with
transparent PNG layers and a `parts-list.txt`:
    file | canvas px | slice L,T,R,B from canvas | drip px | body rect x,y,w,h | socket centre in body
    send_housing_fill.png | [546, 1614] | [124, 124, 124, 356] | 108 | [48, 48, 450, 1410] | -
Every layer shares its part's canvas: the body (the control's rect) sits at (48, 48), a 48 px band of glow round it (and
`drip` px of drips below a housing). Slices are measured from the CANVAS edge; "fixed" = drawn whole.
Layers are grouped into parts by name:
    <id>_fill + <id>_rim   one part <id> (the rim is pure white: the game tints it per seat / faction)
    <id>_ooze, <id>_shine  extra layers of <id>: the ooze is tinted to the faction, the shine is drawn untinted on top
    anything else          a part of its own (status_pill, skill_vessel_liquid, alert_sign_red, build_bar_fill, ...)
Writes
    assets/ui/hud_noir/<file>.png                  the layers (at 3x the phone shot)
    scripts/hud_noir_data.gd                       PARTS: what HudNoir / SkinBox / HudLiquid / BadgeLayer read
then run Godot `--import` once, then this script again (it turns mipmaps on in the new .import files), then `--import`.
"""
import json
import re
import shutil
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent
OUT = GAME / "assets/ui/hud_noir"
DATA = "scripts/hud_noir_data.gd"
LAYERS = ("_rim", "_ooze", "_shine")


def nums(cell: str):
    return [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", cell)]


def gel_top(png: Path, body) -> int:
    """The canvas row where a housing's pooled ooze starts inside its body (the words sit above it)."""
    from PIL import Image
    with Image.open(png) as im:
        a = im.convert("RGBA").getchannel("A")
        x, y, w, h = body
        box = a.crop((int(x), int(y), int(x + w), int(y + h)))
        bb = box.point(lambda v: 255 if v > 24 else 0).getbbox()
        return int(y + bb[1]) if bb else int(y + h)


def main(delivery: Path) -> int:
    rows = {}
    for pl in sorted(delivery.glob("*/parts-list.txt")):
        for line in pl.read_text(encoding="utf-8").splitlines():
            cells = [c.strip() for c in line.split("|")]
            if len(cells) < 5 or not cells[0].endswith(".png"):
                continue
            sl = nums(cells[2])
            rows[cells[0][:-4]] = {
                "src": pl.parent / cells[0], "size": [int(v) for v in nums(cells[1])],
                "slice": [int(v) for v in sl] if len(sl) == 4 else None, "drip": int(nums(cells[3])[0]) if nums(cells[3]) else 0,
                "body": [int(v) for v in nums(cells[4])], "socket": nums(cells[5]) if len(cells) > 5 and nums(cells[5]) else None,
            }
    if not rows:
        print("no parts-list.txt under", delivery)
        return 1
    if OUT.exists():                                          # a clean drop: no stale layer of an older revision
        for f in OUT.glob("*.png"):
            f.unlink()
    OUT.mkdir(parents=True, exist_ok=True)
    for lid, r in rows.items():
        shutil.copyfile(r["src"], OUT / f"{lid}.png")
    res = lambda lid: f"res://{OUT.relative_to(GAME).as_posix()}/{lid}.png"
    used = set()
    parts = {}
    for lid, r in rows.items():                               # pairs first: <id>_fill + <id>_rim
        if lid.endswith("_fill") and lid[:-5] + "_rim" in rows:
            pid = lid[:-5]
            parts[pid] = dict(r, file=res(lid), rim=res(pid + "_rim"))
            used |= {lid, pid + "_rim"}
    for lid, r in rows.items():                               # then single layers (a part's own _rim states stay parts)
        if lid in used:
            continue
        base = next((lid[: -len(s)] for s in ("_ooze", "_shine") if lid.endswith(s)), None)
        if base is not None and base in parts:
            continue
        parts[lid] = dict(r, file=res(lid), rim="")
    for pid, p in parts.items():                              # extra layers
        for s in ("_ooze", "_shine"):
            p[s[1:]] = res(pid + s) if pid + s in rows else ""
        p["gel"] = 0
        if p["ooze"]:
            gt = gel_top(rows[pid + "_ooze"]["src"], p["body"])
            p["gel"] = max(0, p["body"][1] + p["body"][3] - gt)
    gd = ["## GENERATED by tools/hud_noir_import.py from the art director's delivery (References/UI direction 2026-11-02 round-3/",
          "## hud-redo/generated/parts/revision-<n>/delivery) - do not edit; re-run it. PARTS: HUD part id ->",
          "##   file   res:// path of the base layer (fill, or the only layer)      rim / ooze / shine   extra layers (\"\": none)",
          "##   size   the canvas [w, h] (px, 3x the phone shot)                     body  [x, y, w, h] of the control's rect in it",
          "##   slice  [l, t, r, b] 9-slice margins from the canvas edge (null: fixed, drawn whole)",
          "##   drip   px of drips under a housing's body band      gel  px of pooled ooze inside the body's bottom (words sit above)",
          "##   socket [x, y] centre of a skill card's vessel socket in body px (null: none)",
          ""]
    gd.append("const PARTS := {")
    for pid in sorted(parts):
        p = parts[pid]
        sl = "null" if not p["slice"] else "[%s]" % ", ".join(str(v) for v in p["slice"])
        so = "null" if not p["socket"] else "[%s]" % ", ".join(str(v) for v in p["socket"])
        gd.append('\t"%s": {"file": "%s", "rim": "%s", "ooze": "%s", "shine": "%s", "size": [%d, %d], "body": [%s], "slice": %s, '
                  '"drip": %d, "gel": %d, "socket": %s},'
                  % (pid, p["file"], p["rim"], p["ooze"], p["shine"], p["size"][0], p["size"][1],
                     ", ".join(str(v) for v in p["body"]), sl, p["drip"], p["gel"], so))
    gd.append("}")
    (GAME / DATA).write_text("\n".join(gd) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(rows)} layers, {len(parts)} parts -> {OUT.relative_to(GAME)}, {DATA}")
    for imp in OUT.glob("*.png.import"):                      # the HUD draws them at ~1/3: mipmaps on
        t = imp.read_text(encoding="utf-8")
        if "mipmaps/generate=false" in t:
            imp.write_text(t.replace("mipmaps/generate=false", "mipmaps/generate=true"), encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--node":
        OUT = GAME / "assets/ui/node_noir"
        DATA = "scripts/node_noir_data.gd"
        args = args[1:]
    sys.exit(main(Path(args[0])))
