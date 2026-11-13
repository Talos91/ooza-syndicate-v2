extends SceneTree
## Headless UI-kit check:  Godot --headless --path . --script res://tests/test_ui_kit.gd
## The Alpha 21 shell pieces that need no running menu: the last played faction (save / load / fallbacks), every
## faction's accent and tag, the CAMPAIGN view switch, FrameCard's button per state, NavBar's tabs, TouchScroll's horizontal mode.
## (The pages' phone sizes are checked on screenshots: --window=1136x640 --mobile --menu-page=... --menu-shot=...)
## Exit code 0 = all passed.

var failures := 0
const CFG := "user://test_ui_kit.cfg"


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	UiKit.path = CFG
	check(UiKit.last_faction() == "vex", "no ui.cfg yet: HOME shows VEX")
	check(UiKit.save_last_faction("ember") and UiKit.last_faction() == "ember", "the faction played last is saved")
	check(not UiKit.save_last_faction("nope") and UiKit.last_faction() == "ember", "an unknown faction is never saved")
	var c := ConfigFile.new()
	c.set_value("home", "faction", "stale")
	c.save(CFG)
	check(UiKit.last_faction() == "vex", "a stale saved faction falls back to VEX")
	check(UiKit.campaign_view() == "map", "CAMPAIGN opens on the city map by default")
	check(UiKit.save_campaign_view("cards") and UiKit.campaign_view() == "cards" and UiKit.last_faction() == "vex",
			"the CARDS switch is remembered, next to the faction")
	check(UiKit.save_campaign_view("nope") and UiKit.campaign_view() == "map", "anything else is the city map")
	UiKit.path = "user://no/such/dir/ui.cfg"
	check(UiKit.last_faction() == "vex" and not UiKit.save_last_faction("null"), "no storage: VEX, and the save says no")
	for f in UiKit.ORDER:
		check(Rules.FACTIONS.has(f) and UiKit.ACCENTS.has(f) and UiKit.accent(f) == UiKit.ACCENTS[f], "UI accent of " + f)
		check(ResourceLoader.exists(UiKit.hero_path(f)) and UiKit.background(f) != null, "character cutout + environment of " + f)
		check(UiKit.TAGS.has(f), "HOME tag of " + f)
		check(UiKit.hero_art(f) != null, "hero art of " + f)
	check(UiKit.accent("nope") == UiKit.CYAN, "an unknown faction's accent is the neon cyan")
	# ARMIES trait = the real stat leans (Daniele 2026-10-27), written from Rules.FACTION_STATS
	for f in UiKit.ORDER:
		var tr: Array = Rules.faction_trait(f)
		print("      trait %s: %s - %s" % [f, tr[0], tr[1]])
		check(str(tr[0]) != "" and str(tr[1]).ends_with(".") and not str(tr[1]).contains("No stat"), "ARMIES trait of " + f + " names its stat leans")
	check(Rules.faction_trait("vex")[1].contains("15 % faster") and Rules.faction_trait("vex")[1].contains("8 % more damage"),
			"VEX's trait reads its speed 1.15 / garrison 0.93 (%s)" % Rules.faction_trait("vex")[1])
	var card := FrameCard.new()
	var want := {"next": "CONTINUE  →", "open": "PLAY", "won": "REPLAY", "locked": "LOCKED", "coming": "COMING LATER", "dev": ""}
	for s in want:
		card.state = s
		check(card._button_text() == want[s], "FrameCard button for " + s)
	card.state = "locked"
	card.buyable = true
	check(card._button_text() == "UNLOCK" and card.dimmed(), "a buyable locked card: UNLOCK, still dimmed")
	card.action = "OPEN"
	check(card._button_text() == "OPEN", "set_action overrides the state's text")
	card.free()
	var ids := NavBar.TABS.map(func(t): return t[0])
	check(ids == ["home", "armies", "profile", "guide"], "NavBar: HOME / ARMIES / PROFILE / GUIDE (no PLAY tab; CAMPAIGN is a HOME tile since 2026-11-05)")
	var sc := TouchScroll.new()
	check(not sc.horizontal, "TouchScroll is vertical by default")
	sc.horizontal = true
	check(sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "TouchScroll.horizontal pages sideways only (no bar)")
	check(sc.pages.size() == 1 and sc.page == 0, "TouchScroll starts on page 1 of 1 (Daniele 2026-11-04: pages, never scrolling)")
	sc.free()
	# SETTING PICK (2026-11-13; it supersedes BATTLEFIELD > BACKGROUND): THE LAB by default, a pick saved, an unknown one refused
	UiKit.path = CFG
	check(UiKit.setting_choice() == "lab", "SETTING is THE LAB by default")
	check(UiKit.save_setting_choice("golden_hour") and UiKit.setting_choice() == "golden_hour", "a SETTING pick is saved")
	check(not UiKit.save_setting_choice("nope") and UiKit.setting_choice() == "golden_hour", "an unknown setting is refused")
	check(LookTheme.room_value("wellness_retreat") == "4" and LookTheme.of_room_value("4") == "wellness_retreat"
			and LookTheme.of_room_value("auto") == "lab", "SETTING <-> the room's value (0..4; auto = the map's own = lab)")
	check(LookTheme.pick("R-01") == "lab", "headless: the map's own setting, whatever the pick (a server's match host)")
	for id in LookTheme.IDS:
		check(LookTheme.preview(id) != null and LookTheme.NAMES.has(id) and LookTheme.TAGLINES.has(id), "SETTING %s has its preview, name and line" % id)
	check(not ResourceLoader.exists("res://assets/art/backdrops/battle-forecast-liability.jpg") or Scenery.backdrop_for("R-01") == Scenery.DEFAULT_BACKDROP,
			"the old battle backdrops are retired")
	UiKit.save_setting_choice("lab")
	# COLOUR-BLIND MODE: off by default, saved, and every seat of a match on its palette
	Rules.settings_path = CFG
	Rules._colour_blind = -1
	check(not Rules.colour_blind(), "COLOUR-BLIND is off by default")
	Rules.assign_colors(["A", "B", "C", "D", "E"], {}, "A", "A", {})
	var before: Dictionary = Rules.seat_colors.duplicate()
	Rules.apply_colour_blind(["A", "B", "C", "D", "E"], {}, "A")
	check(Rules.seat_colors == before, "COLOUR-BLIND off: the match keeps its colours")
	check(Rules.set_colour_blind(true), "COLOUR-BLIND is saved")
	Rules._colour_blind = -1
	check(Rules.colour_blind(), "... and read back")
	Rules.apply_colour_blind(["A", "B", "C", "D", "E"], {}, "C")
	check(Rules.seat_colors["C"] == Rules.CB_FFA[0] and Rules.seat_colors["A"] == Rules.CB_FFA[1]
			and Rules.seat_colors["E"] == Rules.CB_FFA[4], "FFA 5: you first, then the seats in order, on CB_FFA")
	Rules.apply_colour_blind(["A", "B", "C", "D"], {"A": 1, "B": 0, "C": 1, "D": 0}, "A")
	check(Rules.seat_colors["A"] == Rules.CB_TEAMS[0][0] and Rules.seat_colors["C"] == Rules.CB_TEAMS[0][1]
			and Rules.seat_colors["B"] == Rules.CB_TEAMS[1][0] and Rules.seat_colors["D"] == Rules.CB_TEAMS[1][1],
			"2v2: your team the first family, each teammate a different colour")
	Rules.apply_colour_blind(["A", "B", "C", "D", "E", "F"], {"A": 0, "B": 1, "C": 2, "D": 0, "E": 1, "F": 2}, "A")
	check(Rules.seat_colors["F"] == Rules.CB_TEAMS_3[2][1], "2v2v2: three families")
	Rules.set_colour_blind(false)
	Rules.settings_path = "user://settings.cfg"
	Rules._colour_blind = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	print("test_ui_kit: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
