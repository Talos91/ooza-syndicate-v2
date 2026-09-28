-- ingest_telemetry: the parameter `build` clashed with crash_reports.build ("column reference is ambiguous", every batch
-- answered 500). Same signature (the telemetry function calls it with named args), the variable wins, and the upsert
-- names its constraint instead of listing columns.
create or replace function public.ingest_telemetry(uid uuid, build text, events jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  cap constant int := 300;
  day_start timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  b text := left(coalesce(build, ''), 24);
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
  select count(*) into used from public.telemetry_events te where te.user_id = uid and te.t >= day_start;
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
      if exists (select 1 from public.telemetry_events te where te.user_id = uid and te.kind = 'crash'
                 and te.t >= day_start and te.data->>'sig' = sig) then
        dropped := dropped + 1;
        continue;
      end if;
      insert into public.crash_reports as c (signature, build, samples)
      values (sig, b, jsonb_build_array(d - 'sig'))
      on conflict on constraint crash_reports_pkey do update
        set last_seen = now(), count = c.count + 1,
            samples = case when jsonb_array_length(c.samples) < 5 then c.samples || jsonb_build_array(d - 'sig')
                           else c.samples end;
      d := jsonb_build_object('sig', sig);        -- the per-player row keeps only the signature
    end if;
    insert into public.telemetry_events (user_id, client_t, build, kind, data)
    values (uid, case when (e->>'t') ~ '^[0-9]{9,11}(\.[0-9]+)?$'
                      then least(now(), to_timestamp((e->>'t')::double precision)) end,
            b, k, d);
    used := used + 1;
    accepted := accepted + 1;
  end loop;
  return jsonb_build_object('accepted', accepted, 'dropped', dropped, 'capped', capped);
end $$;
revoke execute on function public.ingest_telemetry(uuid, text, jsonb) from public, anon, authenticated;
