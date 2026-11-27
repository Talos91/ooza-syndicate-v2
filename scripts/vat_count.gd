extends Node3D
## UNIT COUNT ON THE COUNT SCREENS (Ooze 3.0, WP4; lab4 job 3 / Daniele 11-23: the unit count lives ON a screen in the world, no
## HUD badge; Daniele 11-27: "count size: OPTIONS stepper, 5 sizes (lab 3 + 2 smaller), default 1.0"). Main adds one of these to
## every match (not the room server): every node gets a COUNT SCREEN, the separate model slots/count_screen.tscn (Slots3), mounted
## on its structure slot's ScreenMount (over the model; a node with no structure: FALLBACK_Y over its centre) - a dark panel with
## a seat-colour neon frame (neon = seat) and the count in the seat colour, brightened, with a dark outline. The HUD draws no
## count badge and no node notice (NOTICES below).
##
## FIXED to the structure, not a billboard: the panel turns to the camera's yaw and leans back to the Board3 camera's pitch (main's
## cam_pitch on a non-3.0 map), so at the start view it faces the eye squarely and still reads as a mounted screen that does not
## swim when the player pinches.
##
## SIZE: x1.0 = DIGIT_H m digits, set so the digits are >= 12.5 pt on an 812 x 375 pt phone at the Board3 camera on every node of
## the Z pool (tests/count_probe.gd measures it; lab4's 1.15 m gave 7.9 pt at R 7.6). Rules.count_scale() (OPTIONS > GAME >
## Count size, Rules.COUNT_SIZES 0.7 / 0.85 / 1.0 / 1.15 / 1.3) scales the digits and the panel; a change rebuilds the screens.
## digit_pt() is the projected digit height in pt at the node nearest the view's aim.
##
## NOTICES (WP4b, Daniele 2026-11-27: the vat screens "should eat most of the current notifications and clear up the map"): every
## node-level notice is on that node's screen, nothing floats over the map any more. Highest first:
##   - a word flashed by notice(id, text, col) for FLASH_S: TAKEN / LOST (main._on_captured), ▼T2 / SUNK (CombatFx tier-downs),
##     and every Hud.callout_node line (JUICER ON, HANDED OVER, a refused order's reason ...) - one or two short lines;
##   - LAST STAND: a warned node's frame in its alarm colour (DANGER_COL: red the next to launch, amber the one after, grey the
##     rest; the red one blinks) and, NOTICE_S of every CYCLE_S, its seconds ("LAUNCH 6s" on the red one, "9s" on the others);
##     the count comes back for the rest of the cycle (Daniele's screen states: "the count returning often");
##   - UNDER ATTACK (your node): the frame blinks warn red, the count stays;
##   - the tab over the frame (your node): the relay's glyph in Hud.RELAY_ACCENT when its double-tap fire is ready, else ▲ in
##     your colour when a double-tap would upgrade it (the old HUD chips, Daniele 2026-11-14 / ui-neon).
## The tutorial's reveal set still gates them (Hud.shows: danger, upgrade_arrow, relay, floaters).

const DIGIT_H := 2.22               # m at x1.0: >= 12.5 pt on every Z-pool node at the Board3 camera on 812 x 375 (count_probe; lab4 1.15 m = 7.9 pt)
const FALLBACK_Y := 4.6             # m above the node when it has no structure slot (an empty socket, other kits)
const LIFT := 0.1                   # m between the ScreenMount and the panel's lower edge
const FLASH_S := 1.8                # s a notice word holds the screen
const CYCLE_S := 2.4                # s of one Last Stand cycle on a warned screen: NOTICE_S the seconds, then the count
const NOTICE_S := 1.6
const BLINK_HZ := 2.0               # the under-attack / next-launch frame blink
const WORD_CHARS := 11              # a notice line wraps past this many characters (two lines at most)
const DANGER_COL := [Color(1.0, 0.17, 0.22), Color(1.0, 0.82, 0.12), Color(0.64, 0.69, 0.77)]   # (the old ui-neon alarm signs)
const ATTACK_COL := Color(1.0, 0.24, 0.2)
const RELAY_ACCENT := Color("ffb238")   # = Hud.RELAY_ACCENT (not via Hud: tests load this script without the HUD)

var main: Node
var hud                             # Hud (untyped: a test may load this script before the autoloads exist)
var scale_k := 1.0
var screens := {}                   # node id -> {"pivot" (the count_screen slot), "vat", "owner", "text", "look"}
var flashes := {}                   # node id -> {"text", "col", "t" (s left)}
var _t := 0.0
var _clock := 0.0
var _yaw := INF
var _log := "--screen-log" in OS.get_cmdline_user_args()


func setup(m: Node) -> void:
	main = m
	hud = m.hud
	name = "VatCount"
	_build()


func _build() -> void:
	for id in screens:
		(screens[id]["pivot"] as Node).queue_free()
	screens = {}
	scale_k = Rules.count_scale()
	for n in main.sim.nodes:
		if n.get("node_kind", "") == "junction":
			continue
		var scr: Node3D = Slots3.make_count_screen()
		add_child(scr)
		scr.call("build", digit_height_m())
		screens[n["id"]] = {"pivot": scr, "vat": null, "owner": "?", "text": ""}
	sync(true)


func notice(id: int, text: String, col: Color) -> void:
	## A node-level notice on node id's screen for FLASH_S (the same node again replaces it).
	if not screens.has(id) or text.strip_edges() == "":
		return
	flashes[id] = {"text": word(text), "col": col.lerp(Color.WHITE, 0.25), "t": FLASH_S}
	if _log:                                          # dev --screen-log: when each notice showed (picks a shot's time)
		print("SCREEN t=%.1f node %d %s" % [float(main.sim.time), id, word(text).replace("\n", " / ")])
	sync()


static func word(text: String) -> String:
	## A notice as the screen shows it: upper case, wrapped at WORD_CHARS, two lines at most (the rest is dropped).
	var lines := [""]
	for w in text.to_upper().replace("·", " ").split(" ", false):
		var cur: String = lines[-1]
		if cur == "" or cur.length() + 1 + w.length() <= WORD_CHARS:
			lines[-1] = (cur + " " + w).strip_edges()
		elif lines.size() < 2:
			lines.append(w)
		else:
			break
	return "\n".join(lines)


func _process(dt: float) -> void:
	_t += dt
	_clock += dt
	for id in flashes.keys():
		flashes[id]["t"] = float(flashes[id]["t"]) - dt
		if float(flashes[id]["t"]) <= 0.0:
			flashes.erase(id)
	if _t >= 0.1:                                     # 10 Hz is live enough for a count; positions follow tier swaps
		_t = 0.0
		if Rules.count_scale() != scale_k:            # OPTIONS > Count size changed: new screens at the new size
			_build()
			return
		var yaw: float = float(main.get("cam_yaw")) if main.get("cam_yaw") != null else 0.0
		sync(yaw != _yaw)                             # the camera turned (its first fit): face it again
		_yaw = yaw


func sync(force := false) -> void:
	var tiers := danger_tiers()
	for n in main.sim.nodes:
		if not screens.has(n["id"]):
			continue
		var s: Dictionary = screens[n["id"]]
		var pivot: Node3D = s["pivot"]
		if main.sim.collapsed.get(n["id"], false):
			pivot.visible = false
			continue
		pivot.visible = true
		var entry: Dictionary = main.vis.get(n["id"], {})
		var vat = entry.get("vat_node")
		if force or vat != s["vat"]:
			s["vat"] = vat
			_place(n, pivot, vat)
			s["base"] = pivot.global_transform
		_keep_clear(pivot, s)
		_show(n, pivot, s, tiers)


func _show(n: Dictionary, pivot: Node3D, s: Dictionary, tiers: Dictionary) -> void:
	## What node n's screen says now (see NOTICES); the slot is touched only when something changed.
	var sim = main.sim
	var id: int = n["id"]
	var owner: String = n["owner"]
	var seat_col: Color = Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
	var frame := seat_col
	var ink := seat_col.lerp(Color.WHITE, 0.35)
	var text := count_text(n)
	var blink := fmod(_clock * BLINK_HZ, 1.0) < 0.5
	var human: String = hud.human if hud != null else "A"
	if tiers.has(id) and _shows("danger"):            # LAST STAND: the launch countdown in the alarm colour
		var tier: int = tiers[id]
		frame = DANGER_COL[tier] if (tier > 0 or blink) else seat_col
		if fmod(_clock, CYCLE_S) < NOTICE_S:
			var secs := maxi(int(ceil(sim.drop_in(id) if sim.v3 else sim.last_stand_warn_t)), 0)
			text = ("%s %ds" % ["LAUNCH" if Rules.quota else "DROP", secs]) if tier == 0 else "%ds" % secs
			ink = (DANGER_COL[tier] as Color).lightened(0.45)
	elif owner != "" and sim.allied(owner, human) and sim.node_under_attack(id, human) and blink:
		frame = ATTACK_COL                             # UNDER ATTACK: the frame blinks, the count stays
	var f: Dictionary = flashes.get(id, {})
	if not f.is_empty():
		text = f["text"]
		ink = f["col"]
	var tab := ""
	var tab_col := Color.WHITE
	var lift := 0.0
	if owner == human and f.is_empty():
		var bob := 0.5 + 0.5 * sin(_clock * 2.4 + float(id))
		if _shows("relay") and relay_ready(id):
			tab = str(Rules.RELAY_GLYPH.get(n["relay"], "?"))
			tab_col = Color(RELAY_ACCENT, 0.55 + 0.45 * bob)
		elif _shows("upgrade_arrow") and upgrade_ready(id):
			tab = "▲"
			tab_col = seat_col.lerp(Color.WHITE, 0.2)
			lift = digit_height_m() * 0.15 * bob
	var look := [frame, ink, text, tab, tab_col, snappedf(lift, 0.02)]
	if look == s.get("look", []):
		return
	s["look"] = look
	s["text"] = text
	s["owner"] = owner
	pivot.call("set_frame", frame)
	pivot.call("set_ink", ink)
	pivot.call("set_text", text)
	pivot.call("set_tab", tab, tab_col, lift)


func _shows(part: String) -> bool:
	## The tutorial's reveal set (Hud.shows); everything outside a lesson.
	return hud == null or not hud.has_method("shows") or hud.shows(part)


func danger_tiers() -> Dictionary:
	## Every warned node -> its alarm tier: 0 the next to launch, 1 the one after, 2 the rest (by sim.drop_in, so a warned node
	## missing from the queue never jumps to red). Outside a v3 ring there is one warned node: red.
	var sim = main.sim
	var warned := []
	for n in sim.nodes:
		var id: int = n["id"]
		if not sim.collapsed.get(id, false) and sim.is_warned(id):
			warned.append([sim.drop_in(id) if sim.v3 else 0.0, id])
	warned.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out := {}
	for i in range(warned.size()):
		out[warned[i][1]] = mini(i, 2)
	return out


func upgrade_ready(id: int) -> bool:
	## Your node a double-tap would upgrade right now (Sim.can_upgrade; not while its inspector is open).
	var sim = main.sim
	if sim.collapsed.get(id, false) or (hud != null and int(hud.inspector_id) == id):
		return false
	return sim.nodes[id]["owner"] == hud.human and sim.can_upgrade(id, hud.human) == ""


func relay_ready(id: int) -> bool:
	## Your relay whose double-tap fire is available right now (off cooldown, not mid-warning, not locked, not fixed).
	var sim = main.sim
	var n: Dictionary = sim.nodes[id]
	if n["relay"] == "" or n["owner"] != hud.human or sim.collapsed.get(id, false) or sim.relay_fixed(id):
		return false
	return n["relay_cd"] <= 0.0 and n["relay_phase"] == "" and not sim.is_relay_locked(id) and not sim.relay_states(n).is_empty()


func _keep_clear(pivot: Node3D, s: Dictionary) -> void:
	## TOP BAND (as TopBand.keep_clear does for the Label3Ds): a screen whose top is under the score bar / the status line slides
	## down along its own up axis until it clears them; back to its place as soon as the band no longer covers it.
	if not s.has("base"):
		return
	pivot.global_transform = s["base"]
	var cam = main.get("cam")
	if hud == null or not is_instance_valid(hud) or not hud.has_method("top_band_rects") or not (cam is Camera3D) 			or not (cam as Camera3D).is_inside_tree():
		return
	var c: Camera3D = cam
	var up := pivot.global_transform.basis.y.normalized()
	var half := float(pivot.get("size").y) * 0.5 + digit_height_m() * 0.12
	var top := c.unproject_position(pivot.global_position + up * half)
	var bottom := c.unproject_position(pivot.global_position - up * half)
	var w := (c.unproject_position(pivot.global_position + pivot.global_transform.basis.x.normalized() * float(pivot.get("size").x) * 0.5)
			- c.unproject_position(pivot.global_position)).length()
	var r := Rect2(Vector2(top.x - w, top.y), Vector2(2.0 * w, bottom.y - top.y))
	var drop := 0.0
	for b in hud.top_band_rects():
		var br: Rect2 = b
		if r.position.x < br.end.x and r.end.x > br.position.x and r.position.y < br.end.y + 6.0:
			drop = maxf(drop, br.end.y + 6.0 - r.position.y)
	if drop <= 0.0 or r.size.y <= 0.0:
		return
	var m_per_px := 2.0 * half / r.size.y
	pivot.global_position -= up * drop * m_per_px


func screen_at(p: Vector2, cam: Camera3D) -> int:
	## The node whose count screen holds screen point p (main._node_at: a tap on a screen picks its node), -1 when none; the
	## nearest screen centre wins where two overlap.
	if cam == null or not cam.is_inside_tree():
		return -1
	var best := -1
	var best_d := INF
	for id in screens:
		var pivot: Node3D = screens[id]["pivot"]
		if not pivot.visible or str(screens[id]["text"]) == "":
			continue
		var xf := pivot.global_transform
		var sz: Vector2 = pivot.get("size")
		var poly := PackedVector2Array()
		for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			poly.append(cam.unproject_position(xf * Vector3(k.x * sz.x * 0.5, k.y * sz.y * 0.5, 0.0)))
		if Geometry2D.is_point_in_polygon(p, poly):
			var d := p.distance_to(cam.unproject_position(xf.origin))
			if d < best_d:
				best = id
				best_d = d
	return best


func count_text(n: Dictionary) -> String:
	## What this node's count shows (the rule the deleted HUD badge used): the count, "?" under a rival's Fog, "" when masked.
	var sim = main.sim
	var human: String = hud.human
	var owner: String = n["owner"]
	var masked: bool = not (owner == "" or sim.allied(owner, human) or (not Rules.hide_enemy_counts and hud.shows("rival_counts")))   # Brawl only (the old HUD badge's rule since the 0.25.2 cleanup)
	var fogged: bool = sim.node_hidden(n["id"], human) and (owner == "" or not sim.allied(owner, human))
	if fogged:
		return "?"
	if masked:
		return ""
	var units: float = sim.visible_units(n, human)
	return str(Rules.shown(units))


func _place(n: Dictionary, pivot: Node3D, vat) -> void:
	## On the structure slot's ScreenMount (the panel's lower edge just over it), else FALLBACK_Y over the node; turned to the
	## camera's yaw, leaned back to the start camera's pitch.
	var front := Vector3(0, 0, 1)
	if main.cam is Camera3D and (main.cam as Camera3D).is_inside_tree():
		var cz := (main.cam as Camera3D).global_transform.basis.z
		front = Vector3(cz.x, 0.0, cz.z)
		front = front.normalized() if front.length() > 0.001 else Vector3(0, 0, 1)
	var pitch: float = Board3.CAM_PITCH if main.has_method("board3_cam") and main.board3_cam() else float(main.cam_pitch)
	var basis := Basis(Vector3.UP, atan2(front.x, front.z)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch))
	var half_h: float = float(pivot.get("size").y) * 0.5 + digit_height_m() * 0.12
	var base := Vector3(n["pos"]) + Vector3(0.0, FALLBACK_Y, 0.0)
	var mount := Slots3.screen_mount(vat)
	if mount != null and mount.is_inside_tree():
		base = mount.global_position + Vector3(0.0, LIFT, 0.0)
	else:
		half_h = 0.0
	pivot.global_transform = Transform3D(basis, base + basis.y * half_h)


func digit_height_m() -> float:
	return DIGIT_H * scale_k


func digit_pt_at(id: int, cam: Camera3D) -> float:
	## The digit height in pt on screen at node id (the label's centre +- half a digit along the panel's up).
	if not screens.has(id) or cam == null or not cam.is_inside_tree():
		return 0.0
	var pivot: Node3D = screens[id]["pivot"]
	var up := pivot.global_transform.basis.y.normalized() * digit_height_m() * 0.5
	var p := pivot.global_position
	var vp := get_viewport().get_visible_rect().size
	return (cam.unproject_position(p + up) - cam.unproject_position(p - up)).length() * UiKit.pt_per_px(vp)


func digit_pt(cam: Camera3D) -> float:
	## At the node nearest the view's aim point (what the overlay shows).
	var best := -1
	var bd := INF
	var aim: Vector3 = main.cam_target
	for n in main.sim.nodes:
		if not screens.has(n["id"]):
			continue
		var d := Vector3(n["pos"]).distance_to(aim)
		if d < bd:
			bd = d
			best = n["id"]
	return digit_pt_at(best, cam)
