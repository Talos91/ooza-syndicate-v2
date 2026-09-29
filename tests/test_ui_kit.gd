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
	check(ids == ["home", "play", "armies", "campaign", "profile"], "NavBar: HOME / PLAY / ARMIES / CAMPAIGN / PROFILE")
	var sc := TouchScroll.new()
	check(not sc.horizontal, "TouchScroll is vertical by default")
	sc.horizontal = true
	check(sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "TouchScroll.horizontal swipes sideways only")
	sc.free()
	# BATTLEFIELD > BACKGROUND: AUTO by default, a pick / ROTATE saved; a screenless run (a server's match host) keeps the map's own
	UiKit.path = CFG
	check(UiKit.backdrop_choice() == "auto", "BACKGROUND is AUTO by default")
	check(UiKit.save_backdrop_choice("2") and UiKit.backdrop_choice() == "2", "a BACKGROUND pick is saved")
	check(UiKit.save_backdrop_choice("rotate") and UiKit.backdrop_choice() == "rotate", "... and ROTATE")
	check(UiKit.save_backdrop_choice("nope") and UiKit.backdrop_choice() == "auto", "an unknown pick falls back to AUTO")
	check(UiKit.backdrop_name(7, "res://assets/art/backdrops/battle-rent-is-due.jpg") == "RENT IS DUE", "a sixth background is named after its file")
	check(UiKit.battle_backdrop(3, 5) == 3, "headless: the map's own background, whatever the pick")
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
