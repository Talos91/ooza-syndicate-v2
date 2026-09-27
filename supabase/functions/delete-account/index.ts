// delete-account: ACCOUNT > DELETE ACCOUNT (TELEMETRY-PRIVACY-DESIGN §7; the app stores require in-app deletion).
// Auth: verify_jwt on - the player's own session; only that account is ever deleted (the id comes from the token).
// Deletes the auth user; the database then removes what hangs off it:
//   profiles, cloud_saves, faction_stats, telemetry_events  -> deleted (on delete cascade)
//   match_seats                                             -> kept, user_id set to null (other players' rounds stay right)
//   crash_reports                                           -> never held an account id
// Body: {"confirm": "DELETE"} (a stray call can't delete anything). Answers {ok, deleted: true}.
// The device then forgets its session; its local progress stays on the device (Daniele, 2026-09-28).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, apikey, content-type",
        "Access-Control-Allow-Methods": "POST",
      },
    });
  }
  if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
  let body: Record<string, unknown> = {};
  try {
    body = JSON.parse(await req.text());
  } catch {
    return json(400, { ok: false, error: "not JSON" });
  }
  if (body.confirm !== "DELETE") return json(400, { ok: false, error: "confirm: DELETE is required" });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: who, error: whoErr } = await db.auth.getUser(jwt);
  if (whoErr || !who?.user) return json(401, { ok: false, error: "sign in first" });
  const { error } = await db.auth.admin.deleteUser(who.user.id);
  if (error) return json(500, { ok: false, error: "not deleted, try again" });
  return json(200, { ok: true, deleted: true });
});
