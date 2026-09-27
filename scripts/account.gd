class_name Account
extends Node
## ACCOUNTS (PROGRESSION-DESIGN §7; Daniele 2026-09-27: guest first, then an email link or Google on the web / APK;
## Play Games / Game Center with the store builds; a sign-in onto an account that already has progress keeps the
## account's). Supabase Auth + REST over HTTPRequest - no SDK. Optional: the game plays fully offline without it.
##
## - Every player gets a silent guest (anonymous) account the first time the game is online; it becomes permanent when
##   they add an email (a link, no password) or Google.
## - Cloud save: the device's own save files (Progression, ARMIES picks, the tutorial, the campaign) as they are, pushed
##   when one of them changes; restored on another device when that account signs in there ("account wins").
## - The session (refresh token) lives in user://account.cfg; Net.auth_token carries the access token into rooms, where
##   the server's match host verifies it and reports results against the account (supabase/README.md).
## One node, made on first use under the tree's root: Account.get_instance().

signal changed                                      # session, profile or state changed (pages redraw)

const URL := "https://uqwxorxdnucrdgaqpjpp.supabase.co"
const KEY := "sb_publishable_3aX4T8IcNbI_BBg4wENMhA_3NNclYw2"   # publishable: meant to ship in the client
const SITE := "https://talos91.github.io/ooza-syndicate-v2/"     # where email links / Google come back (web)
const REFRESH_EARLY := 600                          # refresh the access token 10 min before it expires
const SAVE_CHECK := 20.0                            # seconds between "did a save file change?" checks
# Email links need the dashboard's Site URL + Redirect URLs (supabase/README.md, switch 3): until Daniele has set them the
# ACCOUNT page shows the email buttons disabled ("coming soon") instead of sending a link that lands nowhere.
const EMAIL_LINKS := false

static var path := "user://account.cfg"             # tests point this elsewhere
static var enabled := true                          # false: never touch the network (tests, headless runs)

var access_token := ""
var refresh_token := ""
var expires_at := 0
var user_id := ""
var is_anonymous := true
var email := ""
var pending_email := ""                             # an email added, waiting for its link to be clicked
var providers: Array = []
var player_name := ""                             # the profile name (SLIME-xxxxx until renamed)
var state := "offline"                              # offline | signing_in | guest | linked | error
var google_ready := false                          # the project's Google provider is on (read from /auth/v1/settings)
var last_error := ""
var _save_hash := ""
var _save_t := 0.0
var _refresh_busy := false

static var _instance: Account = null


static func get_instance() -> Account:
	if _instance == null or not is_instance_valid(_instance):
		_instance = Account.new()
		_instance.name = "Account"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(_instance)
	return _instance


# ------------------------------------------------------------------ start / session
func start(auto_guest := true) -> void:
	## Reads the stored session, adopts one coming back from an email link / Google (web: the page's #fragment),
	## refreshes it, or makes a guest account. Silent when offline: the game plays on.
	if not enabled:
		return
	_load()
	var cfg := await _call("GET", "/auth/v1/settings", null, false)
	if cfg["ok"] and cfg["json"] is Dictionary:
		google_ready = bool((cfg["json"] as Dictionary).get("external", {}).get("google", false))
	var back := _redirect_session()
	if not back.is_empty():
		await _adopt(back)
	elif refresh_token != "":
		await refresh()
	elif auto_guest:
		await sign_in_guest()
	changed.emit()


func signed_in() -> bool:
	return access_token != "" and user_id != ""


func sign_in_guest() -> bool:
	state = "signing_in"
	var r := await _call("POST", "/auth/v1/signup", {}, false)
	if r["ok"]:
		await _adopt(r["json"])
		return true
	_fail(r)
	return false


func refresh() -> bool:
	if refresh_token == "" or _refresh_busy:
		return false
	_refresh_busy = true
	var r := await _call("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, false)
	_refresh_busy = false
	if r["ok"]:
		await _adopt(r["json"])
		return true
	if int(r["code"]) in [400, 401, 403]:           # the refresh token is gone: start over as a new guest
		_clear()
	_fail(r)
	return false


func _adopt(s: Dictionary) -> void:
	## A session from sign-up, a refresh, or a redirect. When the account differs from the one this device had,
	## the account's cloud save replaces the device's progress (Daniele: "keep the account's").
	var u: Dictionary = s.get("user", {}) if s.get("user") is Dictionary else {}
	var before := user_id
	access_token = str(s.get("access_token", ""))
	refresh_token = str(s.get("refresh_token", refresh_token))
	expires_at = int(s.get("expires_at", Time.get_unix_time_from_system() + int(s.get("expires_in", 3600))))
	if u.is_empty():                                # a redirect carries only tokens: ask who this is
		var me := await _call("GET", "/auth/v1/user", null, true)
		u = me["json"] if me["ok"] and me["json"] is Dictionary else {}
	_read_user(u)
	_save()
	_share_token()
	await fetch_profile()
	await _sync_save(before != "" and before != user_id)
	changed.emit()


func _read_user(u: Dictionary) -> void:
	user_id = str(u.get("id", user_id))
	is_anonymous = bool(u.get("is_anonymous", false))
	email = str(u.get("email", ""))
	pending_email = str(u.get("new_email", ""))
	providers = []
	for i in u.get("identities", []):
		if i is Dictionary and not str(i.get("provider", "")) in providers:
			providers.append(str(i.get("provider", "")))
	state = "guest" if is_anonymous else "linked"


func _share_token() -> void:
	## The room's register carries it as "auth" (the server session's Net.auth_token).
	var net := get_node_or_null("/root/Net")
	if net != null and "auth_token" in net:
		net.set("auth_token", access_token)


func _process(dt: float) -> void:
	if not signed_in():
		return
	if expires_at - int(Time.get_unix_time_from_system()) < REFRESH_EARLY:
		refresh()
	_save_t += dt
	if _save_t >= SAVE_CHECK:
		_save_t = 0.0
		var h := str(JSON.stringify(pack_save()).hash())
		if h != _save_hash:
			push_save()


# ------------------------------------------------------------------ linking (email link / Google)
func add_email(address: String) -> bool:
	## A guest keeps their progress on any device: Supabase emails a link; once clicked the account is permanent.
	var r := await _call("PUT", "/auth/v1/user?redirect_to=" + SITE.uri_encode(), {"email": address.strip_edges()}, true)
	if r["ok"]:
		_read_user(r["json"])
		pending_email = address.strip_edges()
		changed.emit()
		return true
	_fail(r)
	return false


func email_sign_in(address: String) -> bool:
	## Sign in on this device to an account that has an email (a link to click); its progress replaces this device's.
	var r := await _call("POST", "/auth/v1/otp?redirect_to=" + SITE.uri_encode(), {"email": address.strip_edges(), "create_user": false}, false)
	if r["ok"]:
		return true
	_fail(r)
	return false


func google(link := true) -> bool:
	## Web only: leaves the page for Google and comes back signed in (link: add Google to this guest account).
	if not OS.has_feature("web"):
		last_error = "Google sign-in works in the browser build"
		changed.emit()
		return false
	var target := ""
	if link and signed_in():
		var r := await _call("GET", "/auth/v1/user/identities/authorize?provider=google&skip_http_redirect=true&redirect_to=" + SITE.uri_encode(), null, true)
		if not r["ok"]:
			_fail(r)
			return false
		target = str((r["json"] as Dictionary).get("url", ""))
	else:
		target = URL + "/auth/v1/authorize?provider=google&redirect_to=" + SITE.uri_encode()
	if target != "":
		JavaScriptBridge.eval("window.location.href = %s" % JSON.stringify(target), true)
	return target != ""


func _redirect_session() -> Dictionary:
	## Web: an email link or Google lands back on the page with the session in the #fragment; read it, then wipe it.
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {}
	var h := str(JavaScriptBridge.eval("window.location.hash || ''", true))
	var d := parse_fragment(h)
	if d.has("access_token"):
		JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)", true)
		return d
	if d.has("error_description"):
		last_error = str(d["error_description"])
	return {}


static func parse_fragment(h: String) -> Dictionary:
	## "#access_token=..&refresh_token=..&expires_in=3600&type=magiclink" -> {access_token, refresh_token, expires_in, ...}
	var out := {}
	for part in h.trim_prefix("#").split("&", false):
		var kv := part.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0].uri_decode()] = kv[1].uri_decode()
	if out.has("expires_in"):
		out["expires_in"] = int(out["expires_in"])
	if out.has("expires_at"):
		out["expires_at"] = int(out["expires_at"])
	return out


# ------------------------------------------------------------------ profile / leaderboard
func fetch_profile() -> void:
	var r := await _call("GET", "/rest/v1/profiles?select=name&id=eq." + user_id, null, true)
	if r["ok"] and r["json"] is Array and not (r["json"] as Array).is_empty():
		player_name = str(r["json"][0].get("name", ""))


func rename(new_name: String) -> bool:
	var r := await _call("POST", "/rest/v1/rpc/set_name", {"new_name": new_name}, true)
	if r["ok"]:
		player_name = str(r["json"])
		changed.emit()
		return true
	_fail(r)
	return false


func leaderboard(board := "season_wins", lim := 50) -> Array:
	## [{rank, name, wins, is_me}] - server-written results only (supabase/README.md). [] when offline.
	var r := await _call("POST", "/rest/v1/rpc/leaderboard_" + board, {"lim": lim}, signed_in())
	return r["json"] if r["ok"] and r["json"] is Array else []


func match_history(lim := 20, before := "") -> Array:
	## MATCH HISTORY: this account's server-recorded rounds, newest first (before: an ISO time for the next page).
	## [] when signed out or offline - the page then shows the device's own log only.
	if not signed_in():
		return []
	var body := {"lim": lim}
	if before != "":
		body["before"] = before
	var r := await _call("POST", "/rest/v1/rpc/my_matches", body, true)
	return r["json"] if r["ok"] and r["json"] is Array else []


# ------------------------------------------------------------------ cloud save
static func pack_save() -> Dictionary:
	## The device's progress: each save file's text as it is, plus the campaign's own copy when it exists.
	var files := {}
	for key in _save_files():
		var p: String = _save_files()[key]
		files[key] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	var out := {"v": 1, "files": files}
	var campaign = _campaign_script()
	if campaign != null:
		out["campaign"] = campaign.to_dict()
	return out


static func restore_save(d: Dictionary) -> bool:
	## Replaces the device's progress with a cloud copy (account wins), then reloads every store. Order (Campaign
	## session): Progression first, then the campaign's copy, then its pending payouts.
	if int(d.get("v", 0)) != 1 or not d.get("files") is Dictionary:
		return false
	var files: Dictionary = d["files"]
	for key in _save_files():
		var p: String = _save_files()[key]
		var text := str(files.get(key, ""))
		if text == "":
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f == null:
				return false
			f.store_string(text)
			f.close()
	Progression.reload_all()
	ArmyPresets.reload_presets()
	TutorialDirector.reload_progress()
	var campaign = _campaign_script()
	if campaign != null and d.get("campaign") is Dictionary:
		campaign.from_dict(d["campaign"])
		if campaign.has_method("pay_pending"):
			campaign.pay_pending()
	return true


static func _save_files() -> Dictionary:
	return {"progress": Progression.path, "armies": ArmyPresets.path, "tutorial": TutorialDirector.path}


static func _campaign_script():
	## The campaign (0.20.4) when this build has it - no hard dependency.
	var p := "res://scripts/campaign.gd"
	if not ResourceLoader.exists(p):
		return null
	var s = load(p)
	return s if s != null and s.has_method("to_dict") and s.has_method("from_dict") else null


func push_save() -> bool:
	var pack := pack_save()
	var r := await _call("POST", "/rest/v1/cloud_saves?on_conflict=user_id",
			{"user_id": user_id, "save": pack, "build": Rules.VERSION}, true, ["Prefer: resolution=merge-duplicates,return=minimal"])
	if r["ok"]:
		_save_hash = str(JSON.stringify(pack).hash())
		return true
	_fail(r)
	return false


func _sync_save(switched: bool) -> void:
	## A new account on this device: restore its cloud copy when it has one (account wins), otherwise upload ours.
	var r := await _call("GET", "/rest/v1/cloud_saves?select=save&user_id=eq." + user_id, null, true)
	var rows: Array = r["json"] if r["ok"] and r["json"] is Array else []
	if switched and not rows.is_empty() and rows[0].get("save") is Dictionary:
		restore_save(rows[0]["save"])
		_save_hash = str(JSON.stringify(pack_save()).hash())
	elif r["ok"]:
		await push_save()


# ------------------------------------------------------------------ plumbing
func _call(method: String, route: String, body, auth: bool, extra := []) -> Dictionary:
	## One REST call: {ok, code, json}. Never throws; offline gives ok false, code 0.
	if not enabled:
		return {"ok": false, "code": 0, "json": null}
	if not is_inside_tree():
		await ready
	var h := HTTPRequest.new()
	h.timeout = 15.0
	h.accept_gzip = not OS.has_feature("web")          # web: the browser already decompresses; Godot's second pass fails
	                                                   # (stream_peer_gzip error; seen on /auth/v1/settings in 0.20.5)
	add_child(h)
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	if auth and access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	for e in extra:
		headers.append(str(e))
	var m: int = {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT}[method]
	var err := h.request(URL + route, headers, m, "" if body == null else JSON.stringify(body))
	if err != OK:
		h.queue_free()
		return {"ok": false, "code": 0, "json": null}
	var res: Array = await h.request_completed
	h.queue_free()
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var js = JSON.parse_string(text) if text != "" else null
	return {"ok": code >= 200 and code < 300, "code": code, "json": js}


func _fail(r: Dictionary) -> void:
	var js = r.get("json")
	var msg := ""
	if js is Dictionary:
		msg = str(js.get("msg", js.get("message", js.get("error_description", js.get("error", "")))))
	last_error = msg if msg != "" else ("offline" if int(r["code"]) == 0 else "error %d" % int(r["code"]))
	if not signed_in():
		state = "offline" if int(r["code"]) == 0 else "error"
	changed.emit()


func _clear() -> void:
	access_token = ""
	refresh_token = ""
	expires_at = 0
	user_id = ""
	state = "offline"
	_save()
	_share_token()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	refresh_token = str(cf.get_value("session", "refresh_token", ""))
	user_id = str(cf.get_value("session", "user_id", ""))
	is_anonymous = bool(cf.get_value("session", "is_anonymous", true))
	email = str(cf.get_value("session", "email", ""))
	player_name = str(cf.get_value("session", "name", ""))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("session", "refresh_token", refresh_token)
	cf.set_value("session", "user_id", user_id)
	cf.set_value("session", "is_anonymous", is_anonymous)
	cf.set_value("session", "email", email)
	cf.set_value("session", "name", player_name)
	cf.save(path)
