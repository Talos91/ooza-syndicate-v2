-- LEADERBOARD's "YOU" line (0.20.13): the signed-in player's own WINS THIS SEASON and rank, by the same rules as
-- leaderboard_season_wins (the UTC month, server rounds with 2+ human seats). 0 wins = rank null.
create function public.my_season_wins()
returns table (rank bigint, name text, wins bigint)
language sql security definer set search_path = '' stable as $$
  with human_rounds as (
    select m.match_id
    from public.matches m join public.match_seats hs on hs.match_id = m.match_id
    where m.started_at >= date_trunc('month', now() at time zone 'utc') at time zone 'utc'
      and hs.ai_level is null
    group by m.match_id
    having count(*) >= 2
  ), w as (
    select ms.user_id, count(*) as wins
    from public.match_seats ms join human_rounds h on h.match_id = ms.match_id
    where ms.won and not ms.left_early and ms.user_id is not null
    group by ms.user_id
  ), ranked as (
    select user_id, wins, rank() over (order by wins desc) as rank from w
  )
  select r.rank, p.name, coalesce(r.wins, 0)
  from public.profiles p left join ranked r on r.user_id = p.id
  where p.id = (select auth.uid())
$$;
revoke execute on function public.my_season_wins() from public, anon;
grant execute on function public.my_season_wins() to authenticated;
