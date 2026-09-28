# Supabase backend - accounts, cloud saves, match results, leaderboards

Owner: the "Leaderboard, progression, and currency" session. Design: `Docs/Game Design/Ooze Syndicate 2.0/01 Rules/PROGRESSION-DESIGN.md`
(§7 accounts, §7a the match report). Created 2026-09-27 with Daniele's yes.

| | |
|---|---|
| Project | `ooze-syndicate` (ref `uqwxorxdnucrdgaqpjpp`), free plan, region Singapore (ap-southeast-1) |
| API URL | https://uqwxorxdnucrdgaqpjpp.supabase.co |
| Client key | the project's publishable key (safe in the game build); never the service-role key |
| Dashboard | https://supabase.com/dashboard/project/uqwxorxdnucrdgaqpjpp |

## Trust rule

- **Server-written only:** `matches`, `match_seats`, `faction_stats` - by the `match-result` edge function, from HMAC-signed
  reports sent by the room server's match host. Leaderboards read only these.
- **The player's own:** `profiles` (read own; rename through `set_name`), `cloud_saves` (the device's progress snapshot,
  read / write own; used to restore progress on another device, never for leaderboards).
- Every table has RLS on; no client write policy exists on server-written tables.

## Pieces

- `migrations/` - the SQL applied to the project, in order (keep this folder the same as the live project).
- `functions/match-result/index.ts` - POST from the match host. Headers `x-ooze-ts` (unix seconds, +-60 s) and
  `x-ooze-sig` = hex HMAC-SHA256(`OOZE_MATCH_SECRET`, ts + "." + raw body). Idempotent on `match_id`. `verify_jwt` off
  (its own auth). Answers 503 until the secret is set. `x-ooze-dry-run: 1` verifies the same way and writes nothing
  (answers "dry-run") - for end-to-end checks.
- RPCs: `set_name(new_name)`, `leaderboard_season_wins(lim)` (a season = the UTC calendar month for now),
  `ingest_match(r)` (service role only).
- **Alpha 21 - telemetry, crash reports, deletion** (`01 Rules/TELEMETRY-PRIVACY-DESIGN.md`):
  - `migrations/telemetry_and_crashes.sql` - tables `telemetry_events` (account id, kind, data <= 2 KB; cascade on
    account deletion) and `crash_reports` (per signature + build, no account id, <= 5 samples), both RLS on with **no
    client policy**; `ingest_telemetry(uid, build, events)` (service role: <= 300 events per player per UTC day, one
    crash per player per signature per day); `purge_telemetry()` run nightly by pg_cron (`ooze-telemetry-purge`,
    03:17 UTC: events 60 days, crash reports 90 days after last seen). **Not applied yet** - rename the file after
    the version `list_migrations` shows once it is.
  - `functions/telemetry/index.ts` (verify_jwt **on**): the player's batch (<= 50 events), fields whitelisted per kind,
    text scrubbed again; 429 when the day's cap is full.
  - `functions/delete-account/index.ts` (verify_jwt **on**, body `{"confirm": "DELETE"}`): deletes the caller's auth
    user; profiles / cloud_saves / faction_stats / telemetry_events cascade, match_seats keep the round with user_id null.
  - Deploy: `apply_migration` with the file's SQL, `deploy_edge_function` for both (verify_jwt true), then
    `tests/test_telemetry.gd -- --live` (it deletes its own test user).

## Dashboard switches Daniele sets (the tools can't)

1. Authentication > Sign In / Providers: **Allow anonymous sign-ins** on (every player starts as a guest).
2. Authentication > Sign In / Providers: **Allow manual linking** on (a guest adds an email or Google later).
3. Authentication > URL Configuration: Site URL `https://talos91.github.io/ooza-syndicate-v2/`; Redirect URLs
   `https://talos91.github.io/ooza-syndicate-v2/**` and `https://45-32-126-20.sslip.io/**` (email links and Google
   sign-in come back to the game). Then set `Account.EMAIL_LINKS = true` (scripts/account.gd) so the email buttons
   turn on.
4. Google (optional): Google Cloud Console > APIs & Services > Credentials > OAuth client ID (Web application),
   authorized redirect URI `https://uqwxorxdnucrdgaqpjpp.supabase.co/auth/v1/callback`, JavaScript origin
   `https://talos91.github.io`; its client ID + secret go in Authentication > Sign In / Providers > Google (Daniele
   enters them). The game reads the provider's state itself and enables its Google buttons.
5. Edge Functions > Secrets: `OOZE_MATCH_SECRET` = the secret the server session generates (handed over by Daniele,
   never through chat or files).

Deploying: the MCP tools (apply_migration, deploy_edge_function) or `supabase db push` / `supabase functions deploy
match-result --no-verify-jwt` from this folder.
