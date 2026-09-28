-- Ooze Syndicate 2.0 telemetry + crash reports (TELEMETRY-PRIVACY-DESIGN §3-§5), Alpha 21.
-- Written only by the telemetry edge function (the player's own JWT verified there, then the service role calls
-- ingest_telemetry). No client policies: players never read or write these tables directly.
-- telemetry_events carry the account id (deleted with the account, cascade); crash_reports are an aggregate per
-- signature + build with no account id at all (samples are scrubbed on the device and again in the function).

create table public.telemetry_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  t timestamptz not null default now(),          -- when the server took it
  client_t timestamptz,                           -- when the device recorded it (may be hours earlier: offline queue)
  build text check (char_length(build) <= 24),
  kind text not null check (kind in ('session', 'match', 'perf', 'funnel', 'crash')),
  data jsonb not null default '{}'::jsonb check (octet_length(data::text) <= 2048)
);
create index telemetry_events_user_t_idx on public.telemetry_events (user_id, t);
create index telemetry_events_t_idx on public.telemetry_events (t);

create table public.crash_reports (
  signature text not null check (char_length(signature) between 1 and 200),
  build text not null check (char_length(build) <= 24),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  count int not null default 1,                   -- player-days hit (one per player per signature per UTC day)
  samples jsonb not null default '[]'::jsonb,     -- at most 5 scrubbed samples {where, message, stack, platform}
  primary key (signature, build)
);
create index crash_reports_last_seen_idx on public.crash_reports (last_seen);

alter table public.telemetry_events enable row level security;
alter table public.crash_reports enable row level security;
-- no policies on purpose: service role only

-- one batch from one player (the edge function has already checked the JWT, whitelisted fields and scrubbed text).
-- Enforces the daily cap (300 events per player per UTC day) and the crash dedupe; returns {accepted, dropped, capped}.
create function public.ingest_telemetry(uid uuid, build text, events jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cap constant int := 300;
  day_start timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  used int;
  e jsonb;
  k text;
  d jsonb;
  sig text;
  accepted int := 0;
  dropped int := 0;
  capped boolean := false;
begin
  if uid is null or not exists (select 1 from auth.users where id = uid) then
    raise exception 'unknown user';
  end if;
  if jsonb_typeof(events) <> 'array' then raise exception 'events must be an array'; end if;
  select count(*) into used from public.telemetry_events where user_id = uid and t >= day_start;
  for e in select * from jsonb_array_elements(events) loop
    k := e->>'kind';
    d := coalesce(e->'data', '{}'::jsonb);
    if k is null or k not in ('session', 'match', 'perf', 'funnel', 'crash') or jsonb_typeof(d) <> 'object'
        or octet_length(d::text) > 2048 then
      dropped := dropped + 1;
      continue;
    end if;
    if used >= cap then
      capped := true;
      dropped := dropped + 1;
      continue;
    end if;
    if k = 'crash' then
      sig := left(coalesce(d->>'sig', ''), 200);
      if sig = '' then
        dropped := dropped + 1;
        continue;
      end if;
      -- one crash per player per signature per day: a repeating error counts once
      if exists (select 1 from public.telemetry_events where user_id = uid and kind = 'crash' and t >= day_start
                 and data->>'sig' = sig) then
        dropped := dropped + 1;
        continue;
      end if;
      insert into public.crash_reports as c (signature, build, samples)
      values (sig, left(coalesce(build, ''), 24),
              jsonb_build_array(d - 'sig'))
      on conflict (signature, build) do update
        set last_seen = now(), count = c.count + 1,
            samples = case when jsonb_array_length(c.samples) < 5 then c.samples || jsonb_build_array(d - 'sig')
                           else c.samples end;
      d := jsonb_build_object('sig', sig);        -- the per-player row keeps only the signature
    end if;
    insert into public.telemetry_events (user_id, client_t, build, kind, data)
    values (uid, case when (e->>'t') ~ '^[0-9]{9,11}(\.[0-9]+)?$'
                      then least(now(), to_timestamp((e->>'t')::double precision)) end,
            left(build, 24), k, d);
    used := used + 1;
    accepted := accepted + 1;
  end loop;
  return jsonb_build_object('accepted', accepted, 'dropped', dropped, 'capped', capped);
end $$;
revoke execute on function public.ingest_telemetry(uuid, text, jsonb) from public, anon, authenticated;

-- retention (Daniele, 2026-09-28): events 60 days, crash reports 90 days after they were last seen
create function public.purge_telemetry() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev int; cr int;
begin
  delete from public.telemetry_events where t < now() - interval '60 days';
  get diagnostics ev = row_count;
  delete from public.crash_reports where last_seen < now() - interval '90 days';
  get diagnostics cr = row_count;
  return jsonb_build_object('events', ev, 'crashes', cr);
end $$;
revoke execute on function public.purge_telemetry() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('ooze-telemetry-purge', '17 3 * * *', $$select public.purge_telemetry()$$);
