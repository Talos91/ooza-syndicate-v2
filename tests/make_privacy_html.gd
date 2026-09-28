extends SceneTree
## Writes web/privacy.html from Telemetry.privacy_text() (the PRIVACY page), so the page beside the game - the one the
## store listings link - always says the same:  Godot --headless --path . --script res://tests/make_privacy_html.gd
## test_telemetry fails when they differ. The release copies web/privacy.html into build/web.


const UPDATED := "2026-09-28"                       # change when privacy_text() changes (not per build)


func _initialize() -> void:
	var body := ""
	for para in Telemetry.privacy_text().split("\n\n"):
		body += ("<h2>%s</h2>\n" if para == para.to_upper() else "<p>%s</p>\n") % para.xml_escape()
	var html := """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ooze Syndicate - Privacy</title>
<style>
:root{color-scheme:dark}body{margin:0;background:#061016;color:#c5d2da;font:17px/1.55 system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 16px 64px}h1{color:#fff;font-size:30px;margin:0 0 4px}
h2{color:#19dce8;font-size:17px;letter-spacing:.06em;margin:28px 0 6px}p{margin:0 0 12px}.v{color:#7795a4;font-size:14px}
</style></head><body><main>
<h1>Ooze Syndicate - Privacy</h1>
<p class="v">Updated %s. The same text is in the game: SETTINGS or ACCOUNT &gt; PRIVACY.</p>
%s</main></body></html>
""" % [UPDATED, body]
	var f := FileAccess.open("res://web/privacy.html", FileAccess.WRITE)
	f.store_string(html)
	f.close()
	print("wrote web/privacy.html")
	quit(0)
