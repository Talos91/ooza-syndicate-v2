-- leaderboard_season_wins: is_me was `w.user_id = auth.uid()`, which is NULL (not false) for a caller who isn't signed
-- in, and the client's bool(null) crashed (🧩 UI fixed the client in 0.21.12). Same body, is_me coalesced to false
-- (my_matches already does). NOT APPLIED: needs Daniele's go; rename to the live version once applied.
create or replace function public.leaderboard_season_wins(lim integer default 50)
returns table(rank bigint, name text, wins bigint, is_me boolean)
language sql stable security definer set search_path to '' as $function$
  with human_rounds as (
    select m.match_id from public.matches m
    join public.match_seats hs on hs.match_id = m.match_id
    where m.started_at >= date_trunc('month', now() at time zone 'utc') at time zone 'utc' and hs.ai_level is null
    group by m.match_id having count(*) >= 2
  ), w as (
    select ms.user_id, count(*) as wins from public.match_seats ms
    join human_rounds h on h.match_id = ms.match_id
    where ms.won and not ms.left_early and ms.user_id is not null
    group by ms.user_id
  )
  select rank() over (order by w.wins desc), p.name, w.wins, coalesce(w.user_id = (select auth.uid()), false)
  from w join public.profiles p on p.id = w.user_id
  order by w.wins desc, p.name
  limit least(greatest(lim, 1), 100)
$function$;
