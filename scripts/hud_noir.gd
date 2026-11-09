class_name HudNoir
extends RefCounted
## Alpha 24 step 2, Neon Noir (Daniele 2026-11-02 picked board C of his art director's HUD boards; STYLE MASTER in
## References/UI direction 2026-11-02 round-3/hud-redo/HUD-PROMPTS.md): the in-match HUD's look, by named part.
##   dark only            the match forces UiTheme dark (UiTheme.match_dark); the light theme stays for the menus
##   accent channel       the player's own faction colour (ACCENT): rims, haze, container drips, the SEND pick
##   fixed channel        never recoloured: ENEMY red, NEUTRAL grey, GOOD green, AMBER (seconds), the skill rings per slot
##                        (RING: ACTIVE icy cyan, MAP violet, ULTIMATE amber with a white-hot core), skill icons white
##   drips                only on the two container housings (SEND, the skill column); buttons and badges are clean glass
## DROP-IN: box(id) is the only way the HUD gets a part's look. A part listed in HudNoirData.PARTS (the director's cut sprite,
## imported by tools/hud_noir_import.py) draws as a SkinBox - FILL plus a white RIM layer tinted like the placeholder's rim -;
## any other part draws its NoirBox placeholder from PRESETS. Layout code never changes when a sprite lands.

const DATA := preload("res://scripts/hud_noir_data.gd")
const NODE_DATA := preload("res://scripts/node_noir_data.gd")   # ui-node: the node parts (tools/hud_noir_import.py --node)
const ACCENT := {"vex": Color("19d6ea"), "null": Color("f327c3"), "bloom": Color("a1eb39"), "ember": Color("ff7c19"),
		"solar": Color("ffce58")}
const ENEMY := Color("ff3b4e")
const NEUTRAL := Color("8a96a8")
const GOOD := Color("3ee07a")
const AMBER := Color("ffc23d")
const RING := [Color("87ebff"), Color("a45cff"), Color("ffc23d")]   # ACTIVE / MAP / ULTIMATE, every faction (2026-11-02; ACTIVE icy cyan = the director's neon halo, Daniele 2026-11-05: ice-white on ice-white goo hid the ring)
const INK := Color("e8f6fa")
# ui-neon-apply (Daniele 2026-11-09: "the whole interface should have the backlit neon in the same color of the vat goo,
# especially the skills"): the steel frames keep their delivered metal; their rim layer (the delivery's COLOUR rim, a greyscale
# soft spill) and the delivery's W *_rim_glow halo BEHIND them take the goo colour (the faction accent).
const STEEL := ["top_capsule", "square_button", "square_button_hover", "square_button_pressed", "square_button_disabled",
		"node_card", "node_hub", "skill_card", "skill_card_armed", "skill_card_ultimate_fill", "hint_pill"]
const BACKLIT := 0.4                                 # the halo's strength (its PNG alpha tops at 115 / 255); Daniele 2026-11-09:
const SPILL_A := 0.55                                # "reduce the boxes neon colour (now is way too much)" - halo 1.0 -> 0.4, spill 0.55
# THE SWITCH (designer 2026-11-09, until Daniele's answer is final): true = the goo colour everywhere (his "backlit neon in the
# same color of the vat goo"; the lit radial tube = the W tube tinted); false = the delivery's own colours (icy cyan spill, the
# amber lit radial tube) as on his START KIT | NEON RESTYLE 1:1 sheet.
const GOO_NEON := true
const DELIVERED_SPILL := Color("87ebff")
const MUTED := Color("a6bfca")
const SPRITE_K := 3.45                              # a cut sprite is drawn at 3x the phone shot, where ui_scale is 1.15
# the placeholder of each part (NoirBox fields; radius / rim_w / drip / ooze in px x ui_scale); "rim" names the channel:
# accent (default), the colour the caller passes (seat / slot), or a fixed one
const PRESETS := {
	"top_capsule": {"radius": 14.0, "glow": 0.8, "fill_a": 0.8},
	"score_pill": {"radius": 9.0, "glow": 0.45, "fill_a": 0.66, "rim_a": 0.8, "gloss": false},
	"score_pill_mine": {"radius": 9.0, "glow": 1.0, "fill_a": 0.9, "gloss": false},
	"score_pill_out": {"radius": 9.0, "dim": true, "fill_a": 0.5, "gloss": false},
	"clock_well": {"radius": 8.0, "glow": 0.0, "rim_a": 0.0, "fill_a": 0.55, "gloss": false},
	"status_pill": {"radius": 16.0, "rim": "enemy", "tint": "enemy", "glow": 0.75, "fill_a": 0.8, "gloss": false},
	"status_secs": {"radius": 8.0, "rim": "amber", "tint": "amber", "glow": 0.6, "fill_a": 0.0, "gloss": false, "rim_w": 1.6},
	"catchup_tag": {"radius": 9.0, "rim": "good", "glow": 0.7, "fill_a": 0.85, "gloss": false},
	"send_housing": {"radius": 16.0, "glow": 0.85, "fill_a": 0.8, "drip": 22.0, "ooze": 14.0, "gloss": false},
	"send_button": {"radius": 12.0, "glow": 0.35, "rim_a": 0.7, "fill_a": 0.86},
	"send_button_hover": {"radius": 12.0, "glow": 0.9, "fill_a": 0.9},
	"send_button_picked": {"radius": 12.0, "glow": 1.0, "filled": true},
	"send_button_disabled": {"radius": 12.0, "dim": true},
	"square_button": {"radius": 12.0, "glow": 0.7, "fill_a": 0.86},
	"square_button_hover": {"radius": 12.0, "glow": 1.1, "fill_a": 0.9},
	"square_button_pressed": {"radius": 12.0, "glow": 1.0, "filled": true},
	"square_button_disabled": {"radius": 12.0, "dim": true},
	"skill_housing": {"radius": 16.0, "glow": 0.85, "fill_a": 0.8, "drip": 22.0, "ooze": 14.0, "gloss": false},
	"skill_card": {"radius": 12.0, "glow": 0.0, "rim_a": 0.28, "fill_a": 0.5, "gloss": false, "rim_w": 1.2},
	"skill_card_armed": {"radius": 12.0, "glow": 1.0, "rim_a": 1.0, "fill_a": 0.7, "gloss": false},
	"hint_pill": {"radius": 12.0, "glow": 0.8, "fill_a": 0.9, "gloss": false},
	"node_card": {"radius": 10.0, "glow": 0.7, "fill_a": 0.9, "gloss": false, "rim": "given"},   # ui-node: the compact node card
}

static var accent := Color("19d6ea")
static var faction := "vex"
static var ui_scale := 1.0
static var _tex := {}                               # res path -> Texture2D


static func setup(faction_id: String, scale: float) -> void:
	## The match's HUD is built for this player (Hud.setup): the accent channel = the player's faction colour.
	faction = faction_id
	accent = ACCENT.get(faction_id, ACCENT["vex"])
	ui_scale = scale


static func has(id: String) -> bool:
	return DATA.PARTS.has(id) or NODE_DATA.PARTS.has(id)


static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func part_texture(id: String) -> Texture2D:
	## A part's cut sprite (its FILL layer), or null while the part is a placeholder.
	return texture(str(part_data(id)["file"])) if has(id) else null


static func channel(name: String, given: Color) -> Color:
	match name:
		"enemy":
			return ENEMY
		"amber":
			return AMBER
		"good":
			return GOOD
		"neutral":
			return NEUTRAL
		"given":
			return given
	return given if given.a > 0.0 else accent


static func on_accent() -> Color:
	## Words on a lit-ooze fill (the SEND pick): near-black with the accent's hue.
	return Color(accent.darkened(0.86), 1.0)


static func box(id: String, rim := Color(0, 0, 0, 0), content := Vector4(6, 6, 6, 6)) -> StyleBox:
	## The look of HUD part `id`: the cut sprite when imported, else its NoirBox placeholder. `rim` replaces the accent channel
	## (a seat's colour on its score pill, a slot's ring colour); content = margins l, t, r, b in px (the drips' zone is added).
	var p: Dictionary = PRESETS.get(id, {})
	var drip := drip_px(id)
	var col := channel(str(p.get("rim", "")), rim)
	if has(id) and id in STEEL:
		col = steel_rim(id)
	var sb: StyleBox
	var pool := float(p.get("ooze", 0.0)) * ui_scale * 0.6     # (words sit above the pooled ooze)
	if has(id):
		var t := texture(str(part_data(id)["file"]))
		if t != null:
			sb = sprite_box(id, col)
			if id.ends_with("_picked") or id.ends_with("_pressed"):   # lit gel: the neutral fill takes your colour
				(sb as SkinBox).modulate = accent
			pool = float(part_data(id).get("gel", 0)) * ui_scale / SPRITE_K
	if sb == null:
		var b := NoirBox.new()
		b.rim = col
		b.tint = Color(channel(str(p["tint"]), rim), 0.35) if p.has("tint") else Color(0, 0, 0, 0)
		b.radius = float(p.get("radius", 12.0)) * ui_scale
		b.rim_w = float(p.get("rim_w", 2.0)) * ui_scale
		b.rim_a = float(p.get("rim_a", 0.95))
		b.glow = float(p.get("glow", 1.0))
		b.fill_a = float(p.get("fill_a", 0.84))
		b.drip = drip
		b.ooze = float(p.get("ooze", 0.0)) * ui_scale
		b.filled = bool(p.get("filled", false))
		b.dim = bool(p.get("dim", false))
		b.gloss = bool(p.get("gloss", true))
		b.seed = hash(id) % 997
		sb = b
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w + drip + pool
	return sb


static func steel_rim(id: String) -> Color:
	## A steel frame's spill: the goo colour, dimmed on a disabled button.
	var c := accent if GOO_NEON else DELIVERED_SPILL
	return Color(c, SPILL_A * (0.45 if id.ends_with("_disabled") else 1.0))


static func glow_texture(id: String) -> Texture2D:
	## A steel frame's backlight: the delivery's W <id>_rim_glow halo (same canvas as the part), or null.
	if not id in STEEL:
		return null
	var base := id.trim_suffix("_fill")
	if base == "skill_card_ultimate":
		base = "skill_card"
	var dir := "node_noir" if base.begins_with("node_") else "hud_noir"
	return texture("res://assets/ui/%s/%s_rim_glow.png" % [dir, base])


static func part_data(id: String) -> Dictionary:
	var parts: Dictionary = DATA.PARTS
	return parts.get(id, (NODE_DATA.PARTS as Dictionary).get(id, {}))


static func sprite_box(id: String, rim: Color, k := -1.0) -> SkinBox:
	## Part `id`'s cut layers as a SkinBox sized to its BODY: fill, the white rim tinted `rim`, a housing's ooze in the accent and
	## its shine untinted; the director's 48 px glow band (and a housing's drips) spill outside the box. k: source px -> canvas
	## units (default: ui_scale / SPRITE_K, the phone shot's 1/3).
	var s := part_data(id)
	var t := texture(str(s.get("file", "")))
	if t == null:
		return null
	var b := SkinBox.new()
	b.texture = t
	b.region = Rect2(Vector2.ZERO, t.get_size())
	var sl = s.get("slice")
	b.slice = Vector4(sl[0], sl[1], sl[2], sl[3]) if sl is Array else Vector4.ZERO
	b.axis = "xy" if sl is Array else "fixed"
	b.scale = k if k > 0.0 else ui_scale / SPRITE_K
	var body: Array = s.get("body", [0, 0, 0, 0])
	var size: Array = s.get("size", [0, 0])
	b.band = Vector4(body[0], body[1], float(size[0]) - body[0] - body[2], float(size[1]) - body[1] - body[3] - float(s.get("drip", 0)))
	b.rim = texture(str(s.get("rim", "")))
	b.rim_modulate = rim
	b.glow = glow_texture(id)
	b.glow_modulate = Color(steel_rim(id), BACKLIT * (0.45 if id.ends_with("_disabled") else 1.0))
	b.ooze = texture(str(s.get("ooze", "")))
	b.ooze_modulate = accent
	b.whole_bottom = b.ooze != null
	b.shine = texture(str(s.get("shine", ""))) if str(s.get("ooze", "")) != "" else null   # (a vat's shine rides its liquid)
	return b


static func gel_px(id: String) -> float:
	## The pooled ooze inside a housing's body bottom (px; 0 for a placeholder): words and slots keep above it.
	return float(part_data(id).get("gel", 0)) * ui_scale / SPRITE_K if has(id) else 0.0


static func drip_px(id: String) -> float:
	## The drips' zone under a housing (px): layout keeps it clear of what sits below.
	if has(id):
		return float(part_data(id).get("drip", 0.0)) * ui_scale / SPRITE_K
	return float(PRESETS.get(id, {}).get("drip", 0.0)) * ui_scale


# ------------------------------------------------------------------ the round skill button (SkillDock.Slot)
static func draw_skill_button(ci: CanvasItem, c: Vector2, d: float, slot: int, state: String, done: float) -> void:
	## One round skill button centred on c, diameter d: a glass disc, its ring track and the ring filled `done` (0..1, clockwise
	## from the top) in the slot's fixed colour (RING). state: ready | cooling | armed | disabled. Sprites, when imported:
	## skill_button[_armed|_disabled] (the disc, fixed), skill_ring_track (fixed), skill_ring_fill (white, tinted per slot -
	## drawn as a pie of its own texture, so a part-filled ring is the sprite's arc).
	var col: Color = RING[slot]
	var r := Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d))
	var disabled := state == "disabled"
	var armed := state == "armed"
	var s := ui_scale
	var ring_r := d * 0.46
	var ring_w := d * 0.075
	var disc_id := "skill_button" + ("_disabled" if disabled else ("_armed" if armed else ""))
	var disc := part_texture(disc_id)
	if disc != null:
		ci.draw_texture_rect(disc, r, false)
	else:
		if not disabled and state != "cooling":         # a ready / armed button glows in its slot colour
			for k in [[0.62, 0.05], [0.56, 0.09], [0.52, 0.14]]:
				ci.draw_circle(c, d * float(k[0]), Color(col, float(k[1]) * (1.6 if armed else 1.0)))
		ci.draw_circle(c, d * 0.5, Color(NoirBox.GLASS_LOW, 0.92))
		ci.draw_circle(c, d * 0.42, Color(NoirBox.GLASS_TOP, 0.95))
		ci.draw_arc(c, d * 0.36, PI * 1.08, PI * 1.42, 12, Color(1, 1, 1, 0.3), maxf(1.5 * s, 1.0), true)   # the wet streak
		ci.draw_arc(c, d * 0.5 - 0.5 * s, 0.0, TAU, 48, Color(accent, 0.35 if not disabled else 0.15), 1.2 * s, true)   # the glass's own rim
	var track := part_texture("skill_ring_track")
	if track != null:
		ci.draw_texture_rect(track, r, false)
	else:
		ci.draw_arc(c, ring_r, 0.0, TAU, 48, Color(0.02, 0.03, 0.05, 0.85), ring_w * 1.35, true)
		ci.draw_arc(c, ring_r, 0.0, TAU, 48, Color(col, 0.16 if not disabled else 0.08), ring_w, true)
	if disabled or done <= 0.0:
		return
	var fill := part_texture("skill_ring_fill")
	var a0 := -PI / 2.0
	var a1 := a0 + TAU * clampf(done, 0.0, 1.0)
	if fill != null:
		var pts := PackedVector2Array([c])
		var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
		var n := maxi(3, int(64.0 * done))
		for k in range(n + 1):
			var a := lerpf(a0, a1, float(k) / float(n))
			var p := c + Vector2(cos(a), sin(a)) * d * 0.71
			pts.append(p)
			uvs.append((p - r.position) / r.size)
		ci.draw_colored_polygon(pts, col, uvs, fill)
		return
	ci.draw_arc(c, ring_r, a0, a1, 64, Color(col, 0.25), ring_w * 2.2, true)      # its glow
	ci.draw_arc(c, ring_r, a0, a1, 64, Color(col, 0.98), ring_w, true)
	var core := 0.55 if slot == 2 else 0.25                                         # the ultimate's white-hot core
	ci.draw_arc(c, ring_r, a0, a1, 64, Color(1, 1, 1, core * (1.0 if done >= 1.0 or armed else 0.7)), ring_w * 0.32, true)
	if done < 1.0:
		var tip := c + Vector2(cos(a1), sin(a1)) * ring_r
		ci.draw_circle(tip, ring_w * 0.75, Color(1, 1, 1, 0.95))
