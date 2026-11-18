"""43B-pack-ARMIES -> assets/ui/armies43: the body of the ARMIES screen (faction row, section tabs, hero cabinet,
ultimate cabinet, reset, 14 skill cards) at 2x (half the 4x cut; 1 px = 0.5 pt) + a trimmed layout.json.
Header / nav / plate are left out: the shell (43B-menu-paint) draws those. Alpha-mask-tinted parts are saved as white
silhouettes (alpha kept) so a modulate gives the exact tint. Geometry untouched (bounds copied as delivered, 4x px)."""
import sys, os, json
from PIL import Image
D = r"H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries/43B-pack-ARMIES/"
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
L = json.load(open(D + "layout.json", encoding="utf-8"))
Y0, Y1 = 190, 1300
els = [e for e in L["elements"] if Y0 <= e["y"] < Y1]
ids = {e["id"] for e in els}
ctrls = [c for c in L["controls"] if any(ch in ids for ch in c["children"])]
tinted = set()
files = set()
for e in els:
    if e.get("file"):
        files.add(e["file"])
        if "alpha_mask_tint" in e:
            tinted.add(e["file"])
for c in ctrls:
    for b in c["state_bindings"]:
        for f in b.get("files", {}).values():
            files.add(f)
for f in os.listdir(D + "parts"):                      # every hero + ultimate icon (the faction on show swaps them)
    if f.startswith("HERO-") and f != "HERO-CABINET.png" and f != "HERO-TITLE-BAR.png" and f != "HERO-WELL.png":
        files.add("parts/" + f)
tot = 0
for f in sorted(files):
    im = Image.open(D + f).convert("RGBA")
    im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    if f in tinted:
        a = im.getchannel("A")
        im = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im.putalpha(a)
    p = os.path.join(OUT, os.path.basename(f))
    im.save(p, optimize=True)
    tot += os.path.getsize(p)
for e in els:
    if e.get("file"):
        e["file"] = os.path.basename(e["file"])
for c in ctrls:
    for b in c["state_bindings"]:
        if "files" in b:
            b["files"] = {k: os.path.basename(v) for k, v in b["files"].items()}
out = {"source": "43B-pack-ARMIES/layout.json (body only, y %d..%d at 4x)" % (Y0, Y1), "canvas": L["canvas"],
       "body": [64, 196, 3120, 1100], "elements": els, "controls": ctrls}
json.dump(out, open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8"), indent=0)
print("files", len(files), "elements", len(els), "controls", len(ctrls), "TOTAL png bytes", tot)
