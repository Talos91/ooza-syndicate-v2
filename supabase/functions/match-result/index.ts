// match-result: the room server's match host reports one finished round (PROGRESSION-DESIGN.md §7a).
// Auth: not a user JWT (verify_jwt off) - an HMAC-SHA256 signature with a secret only the room server and this
// function know (OOZE_MATCH_SECRET, a Supabase function secret; on the VPS in /opt/ooze/secrets.env).
//   x-ooze-ts:  unix seconds when the host signed it (rejected when more than 60 s away from now)
//   x-ooze-sig: lowercase hex of HMAC-SHA256(secret, x-ooze-ts + "." + raw request body)
// Body: the §7a JSON ({match_id, build, map, mode, rules, started_at, duration_s, outcome, seats: [...]}).
// Idempotent on match_id (a retried POST records nothing twice). Answers {ok, result: "recorded" | "duplicate"}.
// x-ooze-dry-run: 1 checks the signature and the body the same way, writes nothing, answers result "dry-run"
// (the room server's end-to-end check).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_SKEW_S = 60;
const MAX_BODY = 64 * 1024;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" },
    false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sameHex(a: string, b: string): boolean {
  // constant-time compare of two hex strings
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
  const secret = Deno.env.get("OOZE_MATCH_SECRET") ?? "";
  if (secret.length < 32) return json(503, { ok: false, error: "match reports are not configured" });
  const ts = req.headers.get("x-ooze-ts") ?? "";
  const sig = (req.headers.get("x-ooze-sig") ?? "").toLowerCase();
  const body = await req.text();
  if (body.length > MAX_BODY) return json(413, { ok: false, error: "report too large" });
  const t = Number(ts);
  if (!Number.isFinite(t) || Math.abs(Date.now() / 1000 - t) > MAX_SKEW_S) {
    return json(401, { ok: false, error: "stale or missing timestamp" });
  }
  if (!sameHex(sig, await hmacHex(secret, `${ts}.${body}`))) return json(401, { ok: false, error: "bad signature" });
  let report: Record<string, unknown>;
  try {
    report = JSON.parse(body);
  } catch {
    return json(400, { ok: false, error: "not JSON" });
  }
  if (typeof report.match_id !== "string" || report.match_id.length < 3 || report.match_id.length > 96 ||
      !Array.isArray(report.seats) || report.seats.length > 8) {
    return json(400, { ok: false, error: "match_id and seats (at most 8) are required" });
  }
  if (req.headers.get("x-ooze-dry-run") === "1") return json(200, { ok: true, result: "dry-run" });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data, error } = await db.rpc("ingest_match", { r: report });
  if (error) return json(500, { ok: false, error: error.message });
  return json(200, { ok: true, result: data });
});
