// telemetry: a batch of play / performance / crash events from the player's own device (TELEMETRY-PRIVACY-DESIGN §2-§4).
// Auth: verify_jwt on - the player's own session (guest or linked); the user id comes from the verified token, never
// from the body. The device only sends when the player has seen the privacy notice and SHARE PLAY & CRASH DATA is on.
// Body: {"build": "0.21.x", "events": [{"kind": "session|match|perf|funnel|crash", "t": <unix s>, "data": {...}}]}
//   <= 50 events, each <= 2 KB; unknown kinds and fields are dropped here, text is scrubbed again (the device already did).
// The database (ingest_telemetry) enforces <= 300 events per player per UTC day and one crash per signature per day.
// Answers {ok, accepted, dropped, capped}; 429 when the day's cap was already full (the device keeps or drops the rest).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_BODY = 128 * 1024;
const MAX_EVENTS = 50;
const MAX_EVENT = 2048;

// the fields each kind may carry (numbers, short ids and enums only - no names, codes or typed text)
const FIELDS: Record<string, string[]> = {
  session: ["platform", "mobile", "screen", "dpr", "renderer", "touch", "graphics", "fps_cap", "lang_region"],
  match: ["map", "mode", "faction", "result", "duration_s", "ai_level", "online", "server_hosted", "abilities",
    "last_stand", "left_early", "placed", "stats"],
  perf: ["where", "frame_ms_p50", "frame_ms_p95", "frame_ms_max", "fps_avg", "fps_min", "draw_p95", "objects",
    "time_s", "long_frames", "graphics", "extra"],
  funnel: ["step", "id", "seconds", "stars", "result"],
  crash: ["sig", "where", "message", "stack", "platform"],
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

// the device's scrub, again: URL queries / fragments, JWT-shaped strings, keys, emails; length caps
export function scrub(s: string, max: number): string {
  return s
    .replace(/(https?:\/\/[^\s?#"']+)[?#][^\s"']*/g, "$1")
    .replace(/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, "<jwt>")
    .replace(/\b(sb_[a-z]+_[A-Za-z0-9_-]{8,}|[A-Za-z0-9_-]{32,})\b/g, "<key>")
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "<email>")
    .slice(0, max);
}

function clean(value: unknown, depth = 0): unknown {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "boolean" || value === null) return value;
  if (typeof value === "string") return scrub(value, 500);
  if (depth >= 2) return null;
  if (Array.isArray(value)) return value.slice(0, 10).map((v) => clean(v, depth + 1));
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>).slice(0, 24)) {
      if (/^[a-z0-9_]{1,32}$/.test(k)) out[k] = clean(v, depth + 1);
    }
    return out;
  }
  return null;
}

export function shape(e: unknown): Record<string, unknown> | null {
  if (typeof e !== "object" || e === null) return null;
  const ev = e as Record<string, unknown>;
  const kind = String(ev.kind ?? "");
  const allowed = FIELDS[kind];
  if (!allowed || typeof ev.data !== "object" || ev.data === null) return null;
  const data: Record<string, unknown> = {};
  for (const f of allowed) {
    if (f in (ev.data as Record<string, unknown>)) data[f] = clean((ev.data as Record<string, unknown>)[f]);
  }
  if (kind === "crash") {
    if (typeof data.sig !== "string" || data.sig === "") return null;
    data.sig = String(data.sig).slice(0, 200);
    if (typeof data.stack === "string") data.stack = data.stack.split("\n").slice(0, 10).join("\n");
  }
  const out = { kind, t: typeof ev.t === "number" ? ev.t : null, data };
  return JSON.stringify(data).length <= MAX_EVENT ? out : null;
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
  const url = Deno.env.get("SUPABASE_URL")!;
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const db = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: who, error: whoErr } = await db.auth.getUser(jwt);
  if (whoErr || !who?.user) return json(401, { ok: false, error: "sign in first" });
  const body = await req.text();
  if (body.length > MAX_BODY) return json(413, { ok: false, error: "batch too large" });
  let batch: Record<string, unknown>;
  try {
    batch = JSON.parse(body);
  } catch {
    return json(400, { ok: false, error: "not JSON" });
  }
  const raw = Array.isArray(batch.events) ? batch.events : [];
  if (raw.length === 0) return json(400, { ok: false, error: "no events" });
  if (raw.length > MAX_EVENTS) return json(413, { ok: false, error: `at most ${MAX_EVENTS} events` });
  const events = raw.map(shape).filter((e) => e !== null);
  const build = String(batch.build ?? "").slice(0, 24);
  const { data, error } = await db.rpc("ingest_telemetry", { uid: who.user.id, build, events });
  if (error) return json(500, { ok: false, error: "not recorded" });
  const r = data as { accepted: number; dropped: number; capped: boolean };
  const dropped = r.dropped + (raw.length - events.length);
  if (r.capped && r.accepted === 0) return json(429, { ok: false, accepted: 0, dropped, capped: true });
  return json(200, { ok: true, accepted: r.accepted, dropped, capped: r.capped });
});
