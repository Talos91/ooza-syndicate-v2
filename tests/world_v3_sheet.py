"""WORLD v3 contact sheet (Daniele 2026-11-09/10 on pits-tubes v2 + demo12): R-01 STRAIT, before / after per item.
    python tests/world_v3_sheet.py <phone shots> <desktop shots> <v2 shots (before)> <out png>
Phone = 740x340 window with --mobile, desktop = 1280x720 (both desktop windows, off-screen; no real phone).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 740, 340
PAD = 10
LABEL = 26


def rows(ph: Path, dk: Path, v2: Path) -> list:
    return [
        ("1  PIPES PIT -> NODE BACK (floor pipe props stay off)", [
            (ph / "1-game-before.png", "before = demo12: no transport tubes"),
            (ph / "1-game-after.png", "after - phone 740x340"),
            (dk / "1-game-after.png", "after - desktop 1280x720")]),
        ("2  NO COLLECTOR BAR: each tube climbs over the rim into the goo on its own", [
            (v2 / "f-fan-pit.png", "before = v2: ribbons -> header bar -> one riser"),
            (ph / "2-pit-entry.png", "after - phone (every column T3)"),
            (dk / "2-pit-entry.png", "after - desktop")]),
        ("3  RACK AT 2 m, COUPLING ANGLED UP; Locals walk under", [
            (v2 / "c-t3-foot.png", "before = v2: rack 1.08 m, flat sockets"),
            (ph / "3-rack-foot.png", "after - phone"),
            (dk / "3-rack-foot.png", "after - desktop")]),
        ("4  ONE PIT PER TUBE: a column's 4 tubes go to the 4 pits (span 12 m kept)", [
            (v2 / "z-top-down.png", "before = v2: all tubes of a column to its nearest pit"),
            (ph / "4a-one-column.png", "after - only A's home column (T3): 4 tubes, 4 pits"),
            (dk / "4b-all-columns.png", "after - every column T3 (desktop)")]),
        ("5  GOOGAT: same faction-coloured tubes as a vat", [
            (ph / "5-googat-before.png", "GooGat T3 (seat B), tubes hidden = demo12"),
            (ph / "5-googat-after.png", "after - phone"),
            (dk / "5-googat-after.png", "after - desktop")]),
        ("6  ONE COLOUR PER PLAYER: seat A (cyan) and seat B (red) side by side", [
            (ph / "6-two-seats.png", "A vat + B GooGat - phone"),
            (dk / "6-two-seats.png", "A vat + B GooGat - desktop"),
            (dk / "1-game-after.png", "game camera - desktop")]),
    ]


def fit(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGB")
    img.thumbnail((W, H))
    canvas = Image.new("RGB", (W, H), (30, 32, 38))
    canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    return canvas


def main() -> None:
    ph, dk, v2, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
    rs = rows(ph, dk, v2)
    head = 44
    row_h = 30 + LABEL + H + PAD
    sheet = Image.new("RGB", (3 * (W + PAD) + PAD, head + len(rs) * row_h + PAD), (18, 20, 24))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arialbd.ttf", 17)
        big = ImageFont.truetype("arialbd.ttf", 24)
        mid = ImageFont.truetype("arialbd.ttf", 21)
    except OSError:
        font = big = mid = ImageFont.load_default()
    d.text((PAD, 10), "WORLD v3 - R-01 STRAIT - phone = 740x340 --mobile window, desktop = 1280x720 (desktop windows, off-screen; no real phone)",
           fill=(230, 235, 240), font=big)
    for r, (title, cells) in enumerate(rs):
        y = head + r * row_h
        d.text((PAD, y + 4), title, fill=(255, 214, 90), font=mid)
        for c, (path, cap) in enumerate(cells):
            x = PAD + c * (W + PAD)
            d.text((x, y + 30 + 3), cap, fill=(120, 230, 255), font=font)
            if path.exists():
                sheet.paste(fit(path), (x, y + 30 + LABEL))
            else:
                d.text((x, y + 30 + LABEL + 20), "missing: " + path.name, fill=(255, 90, 90), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print("sheet", out, sheet.size)


if __name__ == "__main__":
    main()
