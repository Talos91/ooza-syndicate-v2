class_name LookTheme
extends RefCounted
## THEMES (2026-11-13, Daniele on the round-32 settings: "Yes, wire them"). A theme = the setting around and under the board:
##  - the WALLS surround (phone / wide plate, as 26B2: deliveries/32-<setting>/background/SURROUND-*-WALLS.png),
##  - the floor tile (floor/TILE-<S>.png, 16 m, as 26F-B TILE-LAB),
##  - the kit material set (structure/MATERIALS-<S>.md: base / trim / roughness / metalness per zone, walkway included),
##  - the HUD shell set (hud/: 14 painted shells on the 29-FINAL canvases, 0 px silhouette change; masks, goo, glass,
##    glyphs and FLOW stay the lab's).
## Derivatives: tools/themes/make_themes.py -> assets/world/themes/<id>/, assets/ui/themes/<id>/ (originals untouched).
## The LAB is the default theme of every map (MapPool.THEMES is empty until Daniele assigns them). Pure view: no rules.
## Only on the lab look (Look.v2, the 0.24.2 default); --look-old ignores themes. Dev: --theme=<id|short> forces one.

const LAB := "lab"
const IDS: Array[String] = ["lab", "corporate_campus", "golden_hour", "quota_parade", "wellness_retreat"]
const SHORT := {"corporate": "corporate_campus", "campus": "corporate_campus", "golden": "golden_hour", "quota": "quota_parade",
		"parade": "quota_parade", "wellness": "wellness_retreat", "retreat": "wellness_retreat"}
const WORLD := "res://assets/world/themes/%s/%s.png"
const UI := "res://assets/ui/themes/%s/%s.png"
const HUD_SHELLS := ["key-shell", "vat-shell", "button-shell", "r30-tube-shell", "r30-skill-feed-shell", "r30-vat-feed-shell",
		"paint-badge", "paint-banner", "paint-card", "paint-close", "paint-slice-40", "paint-slice-50", "paint-tier-tag", "paint-toast"]

# zone: [base, trim, roughness, base metalness, trim metalness] (sRGB hex from MATERIALS-<S>.md; corporate / wellness give
# metalness in prose: corporate rims + sleeves 0.65, smaller hardware 0.45, stone / porcelain / liner 0; wellness 0.55 on the
# rim, relay hardware and tube couplings, dielectric elsewhere). glass: the separate glass surface tint (roughness 0.12).
const SETS := {
	"corporate_campus": {
		"deck": ["#FDE4C9", "#FDE2C6", 0.57, 0.0, 0.0], "rim": ["#D38F6F", "#D25426", 0.38, 0.65, 0.65],
		"pillar": ["#FEDEB0", "#F8AD73", 0.60, 0.0, 0.0], "vat": ["#F3DCC0", "#424339", 0.50, 0.45, 0.45],
		"relay": ["#F3F0F6", "#8F6859", 0.41, 0.45, 0.45], "pit": ["#2E201F", "#B68667", 0.79, 0.0, 0.45],
		"tubes": ["#E7AE8B", "#BCBFB1", 0.33, 0.65, 0.45], "walkway": ["#A5635A", "#B18378", 0.66, 0.45, 0.45],
		"glass": "#EFC6B5"},
	"golden_hour": {
		"deck": ["#E6B3CA", "#E4AEC8", 0.57, 0.0, 0.0], "rim": ["#CE7264", "#E4AFBE", 0.34, 0.58, 0.58],
		"pillar": ["#A0707E", "#7C4C54", 0.50, 0.35, 0.35], "vat": ["#EBCAD8", "#8C5246", 0.42, 0.35, 0.35],
		"relay": ["#845350", "#F9EEF4", 0.34, 0.67, 0.67], "pit": ["#382B45", "#3E314D", 0.77, 0.12, 0.12],
		"tubes": ["#7B5C6F", "#D07A7C", 0.45, 0.42, 0.42], "walkway": ["#9C6B7A", "#643B50", 0.59, 0.44, 0.44],
		"glass": "#FBF9F9"},
	"quota_parade": {
		"deck": ["#FDEED6", "#FCE9D0", 0.57, 0.0, 0.0], "rim": ["#B23038", "#F09478", 0.34, 0.0, 0.0],
		"pillar": ["#9D8A76", "#F8E8CB", 0.50, 0.42, 0.42], "vat": ["#F2E7D3", "#9A6A5B", 0.42, 0.0, 0.0],
		"relay": ["#8A6959", "#F6F7F8", 0.34, 0.67, 0.67], "pit": ["#0E2E56", "#B78E77", 0.77, 0.12, 0.12],
		"tubes": ["#174671", "#F8E8CB", 0.45, 0.38, 0.38], "walkway": ["#8E98B8", "#B78E77", 0.59, 0.43, 0.43],
		"glass": "#36588A"},
	"wellness_retreat": {
		"deck": ["#F5E6E3", "#CADAFD", 0.55, 0.0, 0.0], "rim": ["#9C8787", "#CE8241", 0.42, 0.55, 0.55],
		"pillar": ["#726D99", "#415378", 0.61, 0.0, 0.0], "vat": ["#E3E5EE", "#CCDDEA", 0.46, 0.0, 0.0],
		"relay": ["#86849B", "#F5F5F9", 0.37, 0.55, 0.55], "pit": ["#263957", "#9E9EB2", 0.79, 0.0, 0.0],
		"tubes": ["#415079", "#8E96BC", 0.35, 0.0, 0.55], "walkway": ["#656F9F", "#A3A2DA", 0.68, 0.0, 0.0],
		"glass": "#BFC6E4"},
}

# lab kit material -> zone per piece kind (the kit's lab colours: cream #E1CEAD / #E9D8BB = shell, plate; detail #708982;
# dark #3F5859 = undersides / recesses -> the setting's darkest shade, the pit well). [zone, 0 = base | 1 = trim]
const ROLES := {
	"deck":    {"OS_Plate": ["deck", 0], "OS_Shell": ["deck", 0], "OS_Steel": ["rim", 0], "OS_Detail": ["rim", 1]},
	"pillar":  {"OS_Plate": ["deck", 0], "OS_Shell": ["deck", 0], "OS_Steel": ["pillar", 0], "OS_Detail": ["pillar", 1]},
	"walkway": {"OS_Plate": ["walkway", 0], "OS_Shell": ["walkway", 0], "OS_Steel": ["walkway", 1], "OS_Detail": ["walkway", 1]},
	"vat":     {"OS_Plate": ["vat", 1], "OS_Shell": ["vat", 0], "OS_Steel": ["vat", 1], "OS_Detail": ["vat", 1]},
	"relay":   {"OS_Plate": ["relay", 0], "OS_Shell": ["relay", 0], "OS_Steel": ["relay", 1], "OS_Detail": ["relay", 1], "OS_Gunmetal": ["relay", 1]},
	"pit":     {"OS_Shell": ["pit", 1], "OS_Detail": ["pit", 1], "OS_Plate": ["pit", 1], "OS_Steel": ["pit", 1]},
	"tubes":   {"OS_Shell": ["tubes", 0], "OS_Detail": ["tubes", 1], "OS_Plate": ["tubes", 0], "OS_Steel": ["tubes", 1]},
}
const DARK := ["OS_Dark", "OS_Recess"]

static var current := LAB


static func forced() -> String:
	## --theme=<id|short> (dev, shots): "" when not given or unknown.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--theme="):
			var v := a.substr(8).to_lower()
			v = SHORT.get(v, v)
			if v in IDS:
				return v
			push_warning("THEME: unknown --theme=%s (%s)" % [v, ", ".join(IDS)])
	return ""


# SETTING PICK (Daniele 2026-11-13: "themes are independent of AI, it's just the new background selector, which completely
# supersedes the old backgrounds"; "when you pick AI there should also be a pick of the setting"). The player picks the
# setting in PLAY VS AI's SETTING (UiKit.setting_choice, remembered); online the room owner picks it for everyone through
# the old BACKGROUND field (Net.room_backdrop "0".."4" -> match_info "backdrop" = the index in IDS; Net.BACKDROP_COUNT ==
# IDS.size(), so net.gd and the protocol are unchanged; "auto" = the map's own = MapPool.THEMES, lab when unassigned).
# Campaign missions and the tutorial / debug maps keep the map's own.
const NAMES := {"lab": "THE LAB", "corporate_campus": "CORPORATE CAMPUS", "golden_hour": "GOLDEN HOUR",
		"quota_parade": "QUOTA PARADE", "wellness_retreat": "WELLNESS RETREAT"}
const SHORT_NAMES := {"lab": "LAB", "corporate_campus": "CAMPUS", "golden_hour": "GOLDEN HOUR",
		"quota_parade": "QUOTA PARADE", "wellness_retreat": "WELLNESS"}
const TAGLINES := {"lab": "Where it all started", "corporate_campus": "Thrive together", "golden_hour": "Protected for extraction",
		"quota_parade": "Record output", "wellness_retreat": "Mandatory relaxation"}
const PREVIEW := "res://assets/ui/settings/%s.jpg"     # tools/themes/make_setting_previews.py (R-01 at 1:40, per setting)


static func preview(id: String) -> Texture2D:
	var p := PREVIEW % id
	return load(p) if ResourceLoader.exists(p) else null


static func pick(map_code: String, use_choice := true) -> String:
	## The match's setting, called before the map is built: the dev flag; else online the room's (match_info "backdrop");
	## else (use_choice: not a campaign mission) your SETTING pick on a battle map; else the map's own (MapPool.THEMES, lab).
	var f := forced()
	var room := room_index()
	if f != "":
		current = f
	elif room >= 0:
		current = IDS[room % IDS.size()]
	elif room == -2 and use_choice and map_code != "" and not map_code.begins_with("T-") and not map_code.begins_with("D-") 			and DisplayServer.get_name() != "headless":
		current = UiKit.setting_choice()
	else:
		current = str(MapPool.THEMES.get(map_code, LAB))
	if not current in IDS:
		current = LAB
	print("THEME ", current, " (map ", map_code, ")")
	return current


static func room_index() -> int:
	## -2 = not in an online match (your own pick applies); -1 = the room plays the map's own; else the owner's index.
	## Net by path: headless --script runs have no autoloads.
	var tree := Engine.get_main_loop() as SceneTree
	var net = tree.root.get_node_or_null("Net") if tree != null else null
	if net == null or not bool(net.get("active")):
		return -2
	return int((net.get("match_info") as Dictionary).get("backdrop", -1))


static func room_value(id: String) -> String:
	## The Net.room_backdrop value for a setting ("0".."4").
	return str(maxi(0, IDS.find(id)))


static func of_room_value(v: String, map_code := "") -> String:
	## Net.room_backdrop -> a setting id ("auto" = the map's own; "rotate", an old room value, reads as the map's own too).
	if v.is_valid_int() and int(v) >= 0 and int(v) < IDS.size():
		return IDS[int(v)]
	return str(MapPool.THEMES.get(map_code, LAB))


static func active() -> bool:
	## A non-lab theme on the lab look path.
	return current != LAB and Look.v2


static func world(name: String, lab_path: String) -> String:
	## A world plate (surround_phone / surround_wide / tile): the theme's when active and present, else the lab's.
	if active():
		var p := WORLD % [current, name]
		if ResourceLoader.exists(p):
			return p
	return lab_path


static func hud_path(n: String) -> String:
	## A HUD shell of the theme ("" = use the lab's); only the 14 shells are themed.
	if not active() or not n in HUD_SHELLS:
		return ""
	var p := UI % [current, n]
	return p if ResourceLoader.exists(p) else ""


static func kind_of(path: String) -> String:
	## The piece kind from its scene path (assets/kit/labkit/<key>.glb, _lab2 twins, normal kit).
	var f := path.get_file()
	if f.begins_with("Vat_T"):
		return "vat"
	if f.begins_with("Deck_Conveyor") or f.begins_with("Walkway_"):
		return "walkway"
	if f.begins_with("Platform_Pillar"):
		return "pillar"
	if f.begins_with("Platform_") or f.begins_with("Pier_") or f.begins_with("Deck_") or f.begins_with("Relay_Mount") or f.begins_with("Node_Base"):
		return "deck"
	if f.begins_with("Pit_Tube") or f.begins_with("Floor_Tube") or f.begins_with("Node_Tube") or f.begins_with("Tube_Connector"):
		return "tubes"
	if f.begins_with("Pit"):
		return "pit"
	for k in ["Cannon_", "Laser", "Machinegoon", "Forge", "Relay_Cannon", "Monster", "Launcher", "Hub"]:
		if f.begins_with(k):
			return "relay"
	return ""


static func zone(z: String) -> Array:
	return (SETS[current] as Dictionary).get(z, []) if active() else []


static func role(kind: String, mat_name: String) -> Array:
	## [Color, roughness, metalness] for a kit material on a piece kind, or [] (untouched: lights, goo, state, glass, ...).
	if not active() or kind == "":
		return []
	var nm := mat_name.get_slice(".", 0)          # OS_Detail.001 -> OS_Detail
	var r: Array = []
	if nm in DARK:
		r = ["pit", 0]
	elif (ROLES.get(kind, {}) as Dictionary).has(nm):
		r = ROLES[kind][nm]
	if r.is_empty():
		return []
	var z := zone(r[0])
	if z.is_empty():
		return []
	return [Color(z[r[1]]), float(z[2]), float(z[3 + int(r[1])])]


static func glass() -> Color:
	return Color((SETS[current] as Dictionary)["glass"]) if active() else Look.GLASS


static func c3(zone_name: String, i: int, fallback: Vector3) -> Vector3:
	## A zone colour as a shader vec3 (display values, as the world shaders' lab constants).
	var z := zone(zone_name)
	if z.is_empty():
		return fallback
	var c := Color(z[i])
	return Vector3(c.r, c.g, c.b)
