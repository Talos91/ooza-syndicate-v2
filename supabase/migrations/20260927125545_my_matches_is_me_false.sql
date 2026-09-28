-- is_me is false (not null) for guest and AI seats
create or replace function public.my_matches(lim int default 20, before timestamptz default null)
returns table (match_id text, started_at timestamptz, map text, mode text, duration_s real, outcome jsonb, seats jsonb)
language sql security definer set search_path = '' stable as $$
  select m.match_id, m.started_at, m.map, m.mode, m.duration_s, m.outcome,
         (select jsonb_agg(jsonb_build_object(
                    'seat', s.seat, 'team', s.team, 'faction', s.faction, 'won', s.won, 'placed', s.placed,
                    'left_early', s.left_early, 'ai_level', s.ai_level,
                    'is_me', coalesce(s.user_id = (select auth.uid()), false),
                    'name', case when s.ai_level is null then p.name end) order by s.seat)
            from public.match_seats s left join public.profiles p on p.id = s.user_id
           where s.match_id = m.match_id) as seats
  from public.matches m
  where exists (select 1 from public.match_seats x where x.match_id = m.match_id and x.user_id = (select auth.uid()))
    and (before is null or m.started_at < before)
  order by m.started_at desc
  limit least(greatest(lim, 1), 50)
$$;
revoke execute on function public.my_matches(int, timestamptz) from public, anon;
grant execute on function public.my_matches(int, timestamptz) to authenticated;
