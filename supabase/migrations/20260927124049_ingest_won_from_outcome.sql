-- A seat's "won" comes from the report's outcome when the seat doesn't say (the §7a seats carry "placed", not "won"):
-- the winning seat, or every seat of the winning team; a draw has no winner.
create or replace function public.ingest_match(r jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare s jsonb; uid uuid; w boolean;
begin
  insert into public.matches (match_id, build, map, mode, rules, started_at, duration_s, outcome)
  values (r->>'match_id', r->>'build', r->>'map', r->>'mode', r->'rules',
          to_timestamp((r->>'started_at')::double precision), (r->>'duration_s')::real, r->'outcome')
  on conflict (match_id) do nothing;
  if not found then return 'duplicate'; end if;
  for s in select * from jsonb_array_elements(coalesce(r->'seats', '[]'::jsonb)) loop
    uid := nullif(s->>'user_id', '')::uuid;
    if uid is not null and not exists (select 1 from auth.users where id = uid) then uid := null; end if;
    w := coalesce((s->>'won')::boolean,
                  not coalesce((r->'outcome'->>'draw')::boolean, false) and (
                    (r->'outcome'->>'winner_seat') = (s->>'seat')
                    or (nullif(r->'outcome'->>'winner_team', '') is not null and (s->>'team') = (r->'outcome'->>'winner_team'))),
                  false);
    insert into public.match_seats (match_id, seat, team, faction, user_id, ai_level, left_early, placed, won, stats)
    values (r->>'match_id', s->>'seat', (s->>'team')::int, s->>'faction', uid, nullif(s->>'ai_level', ''),
            coalesce((s->>'left_early')::boolean, false), (s->>'placed')::int, w, s->'stats');
    if uid is not null and not coalesce((s->>'left_early')::boolean, false) then
      insert into public.faction_stats as f (user_id, faction, plays, wins)
      values (uid, s->>'faction', 1, case when w then 1 else 0 end)
      on conflict (user_id, faction) do update
        set plays = f.plays + 1, wins = f.wins + excluded.wins;
    end if;
  end loop;
  return 'recorded';
end $$;
revoke execute on function public.ingest_match(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_match(jsonb) to service_role;
