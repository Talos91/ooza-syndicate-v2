class_name ArmyPresets
extends RefCounted
## ARMY PRESETS (0.18.7). Daniele: "time to add armies presets and skills (its own new menu item where you
## select what skill each of your factions will use, follow the skill file from faction ultimates and
## ability pool)". One preset per faction: 1 active skill (Rules.ACTIVE_SKILLS) + 1 map skill
## (Rules.MAP_SKILLS); the ultimate comes with the faction (Rules.FACTION_ULTIMATE_ID). Defaults =
## Rules.FACTION_LOADOUT. Saved to user:// as a ConfigFile; a browser with no storage still plays (the picks
## live for the session and `saved` reports false). Also the skills' icons and their one-line effects, built
## from the Rules.SKILLS numbers (shown at Alpha 11 scale) so the menu, lobby and dock say the same thing.

static var path := "user://armies.cfg"             # tests point this elsewhere
static var picks := {}                              # faction -> {"active": id, "map": id} (only valid ids)
static var saved := true                           # false: the last save failed (no storage) - the menu says so
static var _loaded := false


static func load_all() -> void:
	## Reads the saved presets once (again after `path` changes: call reload()). Unknown or stale ids are
	## dropped, so a preset always falls back to the faction's default.
	_loaded = true
	picks = {}
	var cf := ConfigFile.new()
	if cf.load(path) != OK:                         # none yet, or no storage at all (private browsing)
		return
	for f in Rules.FACTION_LOADOUT:
		var one := {}
		for slot in ["active", "map"]:
			var id := str(cf.get_value(f, slot, ""))
			if id in (Rules.ACTIVE_SKILLS if slot == "active" else Rules.MAP_SKILLS):
				one[slot] = id
		if not one.is_empty():
			picks[f] = one


static func reload() -> void:
	_loaded = false
	load_all()


static func _ensure() -> void:
	if not _loaded:
		load_all()


static func loadout_for(faction: String) -> Dictionary:
	## The preset for a faction: {"active": id, "map": id}, always both, always valid (defaults fill in).
	_ensure()
	var d: Dictionary = Rules.FACTION_LOADOUT.get(faction, Rules.FACTION_LOADOUT["null"])
	var p: Dictionary = picks.get(faction, {})
	return {"active": str(p.get("active", d["active"])), "map": str(p.get("map", d["map"]))}


static func effective(faction: String, lo: Dictionary, has_relays: bool) -> Dictionary:
	## What a loadout plays as on a map: {"active", "map", "ultimate", "swapped": the replaced relay skill or ""}
	## (Sim._setup_skills' rule: a relay skill on a map without relays -> the faction's "map_no_relays").
	var out := {"active": Rules.skill_slot_id(faction, lo, "active"), "map": Rules.skill_slot_id(faction, lo, "map"),
			"ultimate": Rules.skill_slot_id(faction, lo, "ultimate"), "swapped": ""}
	if not has_relays and Rules.SKILLS[out["map"]].get("needs_relays", false):
		out["swapped"] = out["map"]
		out["map"] = str(Rules.FACTION_LOADOUT.get(faction, Rules.FACTION_LOADOUT["null"])["map_no_relays"])
	return out


static func set_pick(faction: String, slot: String, id: String) -> bool:
	## Equip a skill in a faction's preset and save. Returns whether it was saved (false: no storage).
	_ensure()
	if not Rules.FACTION_LOADOUT.has(faction) or not slot in ["active", "map"]:
		return false
	if not id in (Rules.ACTIVE_SKILLS if slot == "active" else Rules.MAP_SKILLS):
		return false
	var p: Dictionary = picks.get(faction, {})
	p[slot] = id
	picks[faction] = p
	return save_all()


static func reset(faction: String) -> bool:
	_ensure()
	picks.erase(faction)
	return save_all()


static func is_default(faction: String) -> bool:
	var d: Dictionary = Rules.FACTION_LOADOUT.get(faction, Rules.FACTION_LOADOUT["null"])
	var lo := loadout_for(faction)
	return lo["active"] == d["active"] and lo["map"] == d["map"]


static func save_all() -> bool:
	var cf := ConfigFile.new()
	for f in picks:
		for slot in picks[f]:
			cf.set_value(f, slot, picks[f][slot])
	saved = cf.save(path) == OK
	return saved


static func map_has_relays(m: Dictionary) -> bool:
	## A map's data (MapBuilder.load_map) has a relay that moves something (Sim.has_relays, before setup).
	for n in m.get("nodes", []):
		if n.get("relay") != null and str(n.get("relay")) != "":
			return true
	return false


# ------------------------------------------------------------------ the room (menu -> Net)
static func send_to(net: Node, f: String) -> void:
	## Your preset for faction f becomes your room loadout: before JOIN / CREATE it rides in the register and
	## the roster, in a room it goes to the host (Net.set_loadout). `net` is the Net autoload or a test's Net.
	net.set_loadout(loadout_for(f))


static func room_faction(net: Node, f: String) -> void:
	## The lobby's faction pick: the faction, and that faction's preset as your loadout.
	net.set_faction(f)
	send_to(net, f)


static func room_toggle_abilities(net: Node) -> void:
	## The lobby's ABILITIES ON / OFF (the host's room setting).
	net.toggle_abilities()


# ------------------------------------------------------------------ icons and texts
static var _icons := {}


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var p := "res://assets/ui/skills/%s.svg" % id
		_icons[id] = load(p) if ResourceLoader.exists(p) else null
	return _icons[id]


static func skill_name(id: String) -> String:
	return str(Rules.SKILLS.get(id, {}).get("name", id))


static func cd_text(id: String) -> String:
	## "28 s" for the pools; the ultimate's charge: "~120 s charge".
	var sk: Dictionary = Rules.SKILLS.get(id, {})
	if str(sk.get("slot", "")) == "ultimate":
		return "~%d s charge" % int(Rules.ULT_CHARGE_TIME)
	return "%d s" % int(sk.get("cd", 0.0))


static func line(id: String) -> String:
	## One short line per skill, in shown numbers (Rules.SKILLS; the full sentence is Rules.SKILLS[id].desc).
	var s: Dictionary = Rules.SKILLS.get(id, {})
	match id:
		"surge":
			return "A line of yours +%d %% speed for %d s" % [_pct(s["mult"]), int(s["dur"])]
		"spore_burst":
			return "A vat makes %sx for %d s, within its cap" % [_x(s["mult"]), int(s["dur"])]
		"fortify":
			return "A garrison takes %sx less damage for %d s" % [_x(s["div"]), int(s["dur"])]
		"scorch":
			return "A deck burns %d s: enemy lines lose up to %d" % [int(s["dur"]), int(s["cap_shown"])]
		"ghost_line":
			return "A decoy line: looks real, draws fire, never fights"
		"demolish":
			return "A deck falls after %d s, rebuilt after %d s" % [int(s["warn"]), int(s["down"])]
		"mire":
			return "Enemy lines on a deck %d %% slower for %d s" % [roundi((1.0 - float(s["slow"])) * 100.0), int(s["dur"])]
		"anchor":
			return "Lock a deck %d s: no relay moves it, no Demolish" % int(s["dur"])
		"bypass":
			return "A relay holds both of its states for %d s" % int(s["dur"])
		"relay_hack":
			return "Fire an enemy relay, or jam it +%d s" % int(s["jam"])
		"rewire":
			return "%d s: lines +%d %% speed, fire any %d relays" % [int(s["dur"]), _pct(s["mult"]), int(s["fires"])]
		"echo_split":
			return "%d moving lines spawn decoys that jam %d s" % [int(s["echoes"]), int(s["disrupt"])]
		"superbloom":
			return "Every vat %sx for %d s (at most +%d units)" % [_x(s["mult"]), int(s["dur"]), int(s["cap_shown"])]
		"core_meltdown":
			return "Sacrifice %d %% of an attacking line: %d kills a unit" % [roundi(float(s["share"]) * 100.0), int(s["kills_per"])]
		"relay_aegis":
			return "A node + neighbours: %sx less damage, %d s" % [_x(s["div"]), int(s["dur"])]
	return str(s.get("desc", ""))


static func target_hint(id: String, stage := 0) -> String:
	## What the dock asks you to tap while a slot is armed.
	match str(Rules.SKILLS.get(id, {}).get("target", "none")):
		"own_line":
			return "tap one of your attacking lines" if id == "core_meltdown" else "tap one of your lines"
		"own_vat":
			return "tap one of your vats"
		"own_node":
			return "tap one of your nodes"
		"deck", "fixed_deck":
			return "tap a deck"
		"relay":
			return "tap a relay"
		"enemy_relay":
			return "tap an enemy or neutral relay"
		"vat_to_node":
			return "tap the node it starts from" if stage == 0 else "tap where it goes"
	return ""


static func _pct(mult) -> int:
	return roundi((float(mult) - 1.0) * 100.0)


static func _x(v) -> String:
	var f := float(v)
	return str(int(f)) if f == floorf(f) else ("%.2f" % f).rstrip("0")
