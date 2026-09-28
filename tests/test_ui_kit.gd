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
	check(ids == ["home", "play", "armies", "campaign"], "NavBar: HOME / PLAY / ARMIES / CAMPAIGN")
	var sc := TouchScroll.new()
	check(not sc.horizontal, "TouchScroll is vertical by default")
	sc.horizontal = true
	check(sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "TouchScroll.horizontal swipes sideways only")
	sc.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	print("test_ui_kit: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
