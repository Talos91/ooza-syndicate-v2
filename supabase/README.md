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
  (its own auth). Answers 503 until the secret is set.
- RPCs: `set_name(new_name)`, `leaderboard_season_wins(lim)` (a season = the UTC calendar month for now),
  `ingest_match(r)` (service role only).

## Dashboard switches Daniele sets (the tools can't)

1. Authentication > Sign In / Providers: **Allow anonymous sign-ins** on (every player starts as a guest).
2. Authentication > Sign In / Providers: **Allow manual linking** on (a guest adds an email or Google later).
3. Authentication > URL Configuration: Site URL `https://talos91.github.io/ooza-syndicate-v2/`, and the same URL in
   Redirect URLs (email links and Google sign-in come back to the game).
4. Authentication > Providers > Google: a Google Cloud OAuth client (Web) - its client ID and secret, entered by Daniele.
5. Edge Functions > Secrets: `OOZE_MATCH_SECRET` = the secret the server session generates (handed over by Daniele,
   never through chat or files).

Deploying: the MCP tools (apply_migration, deploy_edge_function) or `supabase db push` / `supabase functions deploy
match-result --no-verify-jwt` from this folder.
