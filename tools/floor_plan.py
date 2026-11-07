"""FLOOR PLAN of a map's world floor, for the art director who paints it (2026-11-07).

Input: the folder tests/floor_plan_probe.tscn wrote (probe.json, board.bin, frame.png, id_XX.png).
Output (to --out, names prefixed with the map code):
  <code>-floor-plan.png          top-down floor plane, world metres, 16 px/m: +x right, +z DOWN (the floor texture's own
                                 u/v directions); 16 m tile grid from the shader's tile origin (0, 0); tube feet; the
                                 board's footprints projected straight down; scale bars; camera arrow
  <code>-floor-visible-mask.png  white = seen at the default camera, gray = seen only after a player pan / zoom,
                                 black = never (ID pass: the real camera, floor flat magenta, everything else drawn)
  <code>-floor-plan-overlay.png  mask tinted over the plan, and the in-game frame with the 16 m grid projected
  <code>-floor-grid-frame.png    that frame alone at 812x375 (phone points)
  <code>-floor-plan.json         rect, px/m, tubes, camera, pan / zoom range, tile origin, class areas, open spots
Usage: python tools/floor_plan.py <probe dir> --out <dir>
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

PX_M = 16
MARGIN = 30.0                 # metres beyond the map radius
TUBE_FOOT_R = 1.45            # metres: the foot circle drawn for the painter
HUD_LEFT = 0.12               # share of the frame the HUD covers (brief: left 12 %, bottom 18 %)
HUD_BOTTOM = 0.18
PHONE = (812, 375)

BG = (14, 16, 22)
GRID = (60, 72, 96)
GRID_TXT = (90, 104, 130)
NODE = (120, 200, 255)
BRIDGE = (255, 190, 90)
TUBE = (120, 255, 150)
TXT = (220, 226, 236)


def font(sz):
    for f in ("C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def project(st, cam, vp, xs, ys, zs):
    """World points -> screen pixels (Godot Camera3D, KEEP_HEIGHT, vertical fov)."""
    o = np.array(st["origin"])
    bx, by, bz = (np.array(st[k]) for k in ("basis_x", "basis_y", "basis_z"))
    dx, dy, dz = xs - o[0], ys - o[1], zs - o[2]
    cx = dx * bx[0] + dy * bx[1] + dz * bx[2]
    cy = dx * by[0] + dy * by[1] + dz * by[2]
    cz = dx * bz[0] + dy * bz[1] + dz * bz[2]
    depth = -cz
    t = math.tan(math.radians(cam["fov_v"]) / 2.0)
    w, h = vp
    with np.errstate(divide="ignore", invalid="ignore"):
        sx = (cx / (depth * t * (w / h)) + 1.0) * 0.5 * w
        sy = (1.0 - cy / (depth * t)) * 0.5 * h
    return sx, sy, depth


def is_floor(rgb):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    return (r - g > 60) & (b - g > 60) & (np.abs(r - b) < 90)


def outline(mask):
    return mask & ~ndimage.binary_erosion(mask, iterations=2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("probe")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    d = json.load(open(os.path.join(a.probe, "probe.json")))
    code, fl, cam, vp = d["map"], d["floor"], d["camera"], d["viewport"]
    os.makedirs(a.out, exist_ok=True)
    cx, cz = fl["centre_xz"]
    reach = fl["radius"] + MARGIN
    t = fl["tile_m"]
    ox, oz = fl["tile_origin_xz"]
    x0 = ox + t * math.floor((cx - reach - ox) / t)     # snapped out to whole 16 m tiles
    x1 = ox + t * math.ceil((cx + reach - ox) / t)
    z0 = oz + t * math.floor((cz - reach - oz) / t)
    z1 = oz + t * math.ceil((cz + reach - oz) / t)
    W, H = int(round((x1 - x0) * PX_M)), int(round((z1 - z0) * PX_M))

    def px(x, z):
        return ((x - x0) * PX_M, (z - z0) * PX_M)

    # ---- board footprints projected straight down
    tris = np.fromfile(os.path.join(a.probe, "board.bin"), dtype=np.float32).reshape(-1, 3, 3)
    masks = {}
    for group, cats in (("node", ("platform", "part")), ("bridge", ("bridge", "other"))):
        im = Image.new("L", (W, H), 0)
        dr = ImageDraw.Draw(im)
        for m in d["meshes"]:
            if m["cat"] not in cats:
                continue
            for tri in tris[m["tri0"]:m["tri1"]]:
                pts = [px(float(v[0]), float(v[2])) for v in tri]
                dr.polygon(pts, fill=255)
        masks[group] = np.asarray(im) > 0
    masks["bridge"] &= ~masks["node"]

    # ---- plan
    plan = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(plan)
    f_s, f_m, f_l = font(18), font(26), font(40)
    for k in range(int(round((x1 - x0) / t)) + 1):
        x = x0 + k * t
        dr.line([px(x, z0), px(x, z1)], fill=GRID, width=2 if abs(x - ox) < 1e-6 else 1)
    for k in range(int(round((z1 - z0) / t)) + 1):
        z = z0 + k * t
        dr.line([px(x0, z), px(x1, z)], fill=GRID, width=2 if abs(z - oz) < 1e-6 else 1)
    for i in range(int(round((x1 - x0) / t))):
        for j in range(int(round((z1 - z0) / t))):
            ci, cj = int(round((x0 - ox) / t)) + i, int(round((z0 - oz) / t)) + j
            dr.text((px(x0 + i * t, z0 + j * t)[0] + 6, px(x0 + i * t, z0 + j * t)[1] + 4), "%d,%d" % (ci, cj),
                    fill=GRID_TXT, font=f_s)
    # fade / crust ring
    r0 = fl["fade_r0"]
    for k in range(180):
        if k % 2:
            continue
        a0, a1 = 2 * math.pi * k / 180, 2 * math.pi * (k + 1) / 180
        dr.line([px(cx + r0 * math.cos(a0), cz + r0 * math.sin(a0)), px(cx + r0 * math.cos(a1), cz + r0 * math.sin(a1))],
                fill=(150, 80, 80), width=2)
    arr = np.asarray(plan).copy()
    arr[outline(masks["node"])] = NODE
    arr[outline(masks["bridge"])] = BRIDGE
    plan = Image.fromarray(arr)
    dr = ImageDraw.Draw(plan)
    for tb in d["tubes"]:
        p = px(tb["x"], tb["z"])
        rr = TUBE_FOOT_R * PX_M
        dr.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], outline=TUBE, width=3)
        rt = tb["r"] * PX_M
        dr.ellipse([p[0] - rt, p[1] - rt, p[0] + rt, p[1] + rt], outline=(60, 140, 80), width=1)
        dr.line([p[0] - 4, p[1], p[0] + 4, p[1]], fill=TUBE)
        dr.line([p[0], p[1] - 4, p[0], p[1] + 4], fill=TUBE)
        dr.text((p[0] + rr + 4, p[1] - rr - 26), "T%d" % tb["id"], fill=TUBE, font=f_m)
    # scale bars (bottom left), camera arrow (top right)
    sx, sy = 40, H - 60
    dr.rectangle([sx, sy, sx + 10 * PX_M, sy + 10], fill=TXT)
    for k in range(11):
        dr.line([sx + k * PX_M, sy - (12 if k in (0, 10) else 6), sx + k * PX_M, sy], fill=TXT, width=2)
    dr.text((sx, sy - 44), "10 m = 160 px", fill=TXT, font=f_m)
    dr.rectangle([sx + 200, sy, sx + 200 + PX_M, sy + 10], fill=TXT)
    dr.text((sx + 200, sy - 44), "1 m = 16 px", fill=TXT, font=f_m)
    yaw = cam["yaw"]
    vdir = (-math.sin(yaw), -math.cos(yaw))   # camera looks along -back: back = (sin yaw, cos yaw) in (x, z)
    ax, az = W - 150, 170
    dr.line([ax - vdir[0] * 90, az - vdir[1] * 90, ax + vdir[0] * 90, az + vdir[1] * 90], fill=TXT, width=6)
    tip = (ax + vdir[0] * 110, az + vdir[1] * 110)
    nx, nz = -vdir[1], vdir[0]
    dr.polygon([tip, (ax + vdir[0] * 70 + nx * 25, az + vdir[1] * 70 + nz * 25),
                (ax + vdir[0] * 70 - nx * 25, az + vdir[1] * 70 - nz * 25)], fill=TXT)
    dr.text((ax - 120, az + 110), "N = -z = camera\nlooks this way", fill=TXT, font=f_s)
    dr.text((40, 30), "%s FLOOR PLAN  y = %.1f m  x %.0f..%.0f  z %.0f..%.0f m  16 px/m  +x right, +z down" %
            (code, fl["y"], x0, x1, z0, z1), fill=TXT, font=f_l)
    dr.text((40, H - 110), "rect: world x %.0f..%.0f, z %.0f..%.0f m = %d x %d px; pixel (0,0) = world (%.0f, %.0f)" %
            (x0, x1, z0, z1, W, H, x0, z0), fill=TXT, font=f_s)
    dr.text((40, 80), "grid: 16 m floor tiles, origin (0,0) = shader tile origin; labels = tile cell (i,j)   "
            "blue: platforms  orange: bridges/relays (straight down)  green: tube foot r 1.45 m (inner: tube r)   "
            "red dashed: fade start / crust ring r %.1f m" % r0, fill=TXT, font=f_s)
    plan.save(os.path.join(a.out, "%s-floor-plan.png" % code))

    # ---- visibility mask (ID pass, the real camera per state)
    jj, ii = np.mgrid[0:H, 0:W]
    wx = x0 + (ii + 0.5) / PX_M
    wz = z0 + (jj + 0.5) / PX_M
    wy = np.full_like(wx, fl["y"])
    seen_default = np.zeros((H, W), bool)
    seen_any = np.zeros((H, W), bool)
    errs = []
    for st in d["states"]:
        idimg = np.asarray(Image.open(os.path.join(a.probe, "id_%02d.png" % st["k"])).convert("RGB"))
        ih, iw = idimg.shape[:2]
        for q, s in st["probe"]:
            qx, qy, _ = project(st, cam, (iw, ih), np.array(q[0]), np.array(q[1]), np.array(q[2]))
            errs.append(math.hypot(float(qx) - s[0] * iw / vp[0], float(qy) - s[1] * ih / vp[1]))   # Godot reports in the stretched base size
        fx, fy, dep = project(st, cam, (iw, ih), wx, wy, wz)
        ok = (dep > 0) & (fx >= iw * HUD_LEFT) & (fx < iw) & (fy >= 0) & (fy < ih * (1.0 - HUD_BOTTOM))
        xi = np.clip(fx.astype(int), 0, iw - 1)
        yi = np.clip(fy.astype(int), 0, ih - 1)
        vis = ok & is_floor(idimg[yi, xi])
        seen_any |= vis
        if st["k"] == 0:
            seen_default = vis.copy()
    gray = seen_any & ~seen_default
    mask = np.zeros((H, W), np.uint8)
    mask[gray] = 128
    mask[seen_default] = 255
    Image.fromarray(mask, "L").save(os.path.join(a.out, "%s-floor-visible-mask.png" % code))
    n = float(W * H)
    disc = (wx - cx) ** 2 + (wz - cz) ** 2 <= fl["radius"] ** 2
    share = {"white": seen_default.mean() * 100, "gray": gray.mean() * 100, "black": (mask == 0).mean() * 100}
    share_disc = {"white": seen_default[disc].mean() * 100, "gray": gray[disc].mean() * 100,
                  "black": (mask[disc] == 0).mean() * 100}

    # open spots: the widest white discs (crater candidates), greedy on the distance transform
    def open_spots(reach_m, count):
        inner = seen_default & ((wx - cx) ** 2 + (wz - cz) ** 2 <= reach_m ** 2)
        dist = ndimage.distance_transform_edt(np.pad(inner, 1))[1:-1, 1:-1] / PX_M   # the rect edge and ring bound it
        spots = []
        dd = dist.copy()
        for _ in range(count):
            j, i = np.unravel_index(np.argmax(dd), dd.shape)
            r = dd[j, i]
            if r < 3.0:
                break
            x, z = x0 + (i + 0.5) / PX_M, z0 + (j + 0.5) / PX_M
            spots.append({"x": round(float(x), 1), "z": round(float(z), 1), "clear_r_m": round(float(r), 1),
                          "from_centre_m": round(math.hypot(x - cx, z - cz), 1)})
            dd[(wx - x) ** 2 + (wz - z) ** 2 <= (r * 2.0) ** 2] = 0
        return spots
    spots = open_spots(fl["fade_r0"], 5)                  # full-strength floor (inside the fade ring)
    spots_in = open_spots(fl["radius"], 4)                # inside the board's own radius
    # white regions
    lab, nlab = ndimage.label(seen_default)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, nlab + 1)) / PX_M ** 2 if nlab else []
    regions = []
    for k in np.argsort(sizes)[::-1][:6]:
        ys_, xs_ = np.nonzero(lab == k + 1)
        regions.append({"area_m2": round(float(sizes[k])), "centroid_xz": [round(float(x0 + xs_.mean() / PX_M), 1),
                        round(float(z0 + ys_.mean() / PX_M), 1)]})

    # ---- overlay
    base = np.asarray(plan).astype(float)
    tint = base.copy()
    tint[seen_default] = base[seen_default] * 0.55 + np.array([40, 200, 120]) * 0.45
    tint[gray] = base[gray] * 0.55 + np.array([230, 170, 40]) * 0.45
    blk = mask == 0
    tint[blk] = base[blk] * 0.45
    ov = Image.fromarray(tint.clip(0, 255).astype(np.uint8))
    od = ImageDraw.Draw(ov)
    for s in spots + spots_in:
        p = px(s["x"], s["z"])
        r = s["clear_r_m"] * PX_M
        od.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], outline=(255, 255, 255), width=3)
        od.text((p[0] - 60, p[1] - 14), "open r %.0f m" % s["clear_r_m"], fill=(255, 255, 255), font=f_m)
    od.text((40, 120), "green = seen at the default camera (%.1f %%)   amber = only after pan / zoom (%.1f %%)   "
            "dark = never (%.1f %%)   white rings = widest open floor" % (share["white"], share["gray"], share["black"]),
            fill=TXT, font=f_m)

    # in-game frame with the grid projected onto the floor
    st0 = d["states"][0]
    fr = Image.open(os.path.join(a.probe, "frame.png")).convert("RGB")
    idimg = np.asarray(Image.open(os.path.join(a.probe, "id_00.png")).convert("RGB"))
    iw, ih = fr.size
    fl_mask = is_floor(idimg)
    layer = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    hidden = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hidden)

    def seg(xa, za, xb, zb, col, w):
        ss = np.linspace(0, 1, 200)
        X, Z = xa + (xb - xa) * ss, za + (zb - za) * ss
        sx_, sy_, dep = project(st0, cam, (iw, ih), X, np.full_like(X, fl["y"]), Z)
        for k in range(len(ss) - 1):
            if dep[k] > 0 and dep[k + 1] > 0:
                ld.line([sx_[k], sy_[k], sx_[k + 1], sy_[k + 1]], fill=col, width=w)
                hd.line([sx_[k], sy_[k], sx_[k + 1], sy_[k + 1]], fill=col[:3] + (70,), width=1)
    gx0, gx1 = x0 - 4 * t, x1 + 4 * t
    gz0, gz1 = z0 - 4 * t, z1 + 4 * t
    for k in range(int(round((gx1 - gx0) / t)) + 1):
        x = gx0 + k * t
        seg(x, gz0, x, gz1, (255, 230, 60, 255) if abs(x - ox) > 1e-6 else (255, 80, 80, 255), 1)
    for k in range(int(round((gz1 - gz0) / t)) + 1):
        z = gz0 + k * t
        seg(gx0, z, gx1, z, (255, 230, 60, 255) if abs(z - oz) > 1e-6 else (255, 80, 80, 255), 1)
    for tb in d["tubes"]:
        aa = np.linspace(0, 2 * math.pi, 40)
        X, Z = tb["x"] + TUBE_FOOT_R * np.cos(aa), tb["z"] + TUBE_FOOT_R * np.sin(aa)
        sx_, sy_, _ = project(st0, cam, (iw, ih), X, np.full_like(X, fl["y"]), Z)
        ld.line(list(zip(sx_, sy_)), fill=(120, 255, 150, 255), width=2)
        hd.line(list(zip(sx_, sy_)), fill=(120, 255, 150, 90), width=1)
    la = np.asarray(layer).copy()
    la[~fl_mask] = 0                                     # solid only where the floor is really seen
    frame = fr.convert("RGBA")
    frame = Image.alpha_composite(frame, hidden)
    frame = Image.alpha_composite(frame, Image.fromarray(la, "RGBA"))
    fd = ImageDraw.Draw(frame)
    fd.line([iw * HUD_LEFT, 0, iw * HUD_LEFT, ih], fill=(255, 255, 255, 160), width=1)
    fd.line([0, ih * (1 - HUD_BOTTOM), iw, ih * (1 - HUD_BOTTOM)], fill=(255, 255, 255, 160), width=1)
    fd.rectangle([iw * HUD_LEFT, 0, iw * HUD_LEFT + 440, 15], fill=(0, 0, 0, 200))
    fd.text((iw * HUD_LEFT + 6, 2), "16 m floor grid (red = x 0 / z 0), tube feet; "
            "solid = floor seen, faint = behind the board; HUD lines 12 % / 18 %", fill=(255, 255, 255, 255), font=font(10))
    frame = frame.convert("RGB")
    frame.resize(PHONE, Image.LANCZOS).save(os.path.join(a.out, "%s-floor-grid-frame.png" % code))
    canvas = Image.new("RGB", (W, H + ih + 40), BG)
    canvas.paste(ov, (0, 0))
    canvas.paste(frame, ((W - iw) // 2, H + 20))
    canvas.save(os.path.join(a.out, "%s-floor-plan-overlay.png" % code))

    out = {
        "map": code, "px_per_m": PX_M,
        "world_rect_m": {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "y": fl["y"]},
        "image_px": [W, H], "image_axes": "pixel (0,0) = world (x0, z0) corner; +x right, +z down; pixel centre i = x0 + (i+0.5)/16",
        "tile": {"size_m": t, "origin_xz": [ox, oz], "tile_px": t * PX_M,
                 "note": "shader: cell = floor(world.xz / 16), uv = world.xz / 16 (texture +u = +x, +v = +z)"},
        "floor": fl,
        "tubes": [{"node": tb["id"], "x": round(tb["x"], 3), "z": round(tb["z"], 3), "r_foot_drawn": TUBE_FOOT_R,
                   "r_tube": tb["r"], "px": [round(c, 1) for c in px(tb["x"], tb["z"])]} for tb in d["tubes"]],
        "camera": {"pitch_deg": cam["pitch"], "yaw_rad": cam["yaw"], "fov_v_deg": cam["fov_v"],
                   "default_target": cam["fit_target"], "default_dist_m": cam["fit_dist"],
                   "zoom_range": [cam["zoom_min"], 1.0], "zoom_note": "cam_dist = fit_dist * zoom (player pinch/wheel, main._zoom_at)",
                   "pan_half_m_at_zoom": {"x": cam["map_half"][0], "z": cam["map_half"][2]},
                   "pan_note": "target within fit_target +- map_half * (1 - zoom)",
                   "states_sampled": len(d["states"]), "zooms": sorted({s["zoom"] for s in d["states"]}),
                   "frame_rendered_px": vp, "frame_phone_pt": list(PHONE),
                   "hud_zones_used": {"left": HUD_LEFT, "bottom": HUD_BOTTOM},
                   "hud_real_px": {"side_right": cam["hud_side_right_px"], "top": cam["hud_top_px"],
                                   "bottom": cam["hud_bottom_px"]},
                   "projection_check_px_max_err": round(max(errs), 3)},
        "mask_method": "ID pass: the game's own camera per state, floor material swapped for flat magenta (unshaded, "
                       "no fog), mist sheet / floor decals / glow / fog / HUD hidden; a floor sample counts as seen when "
                       "it projects inside the frame, outside the HUD zones, onto a magenta pixel",
        "share_pct_rect": {k: round(v, 1) for k, v in share.items()},
        "share_pct_map_disc": {k: round(v, 1) for k, v in share_disc.items()},
        "open_spots_default_view": spots,
        "open_spots_inside_map_radius": spots_in,
        "white_regions": regions,
    }
    json.dump(out, open(os.path.join(a.out, "%s-floor-plan.json" % code), "w"), indent=1)
    print(json.dumps({k: out[k] for k in ("world_rect_m", "image_px", "share_pct_rect", "share_pct_map_disc",
                                          "open_spots_default_view", "open_spots_inside_map_radius")}, indent=1))
    print("proj err", max(errs))


if __name__ == "__main__":
    main()
