-- WINS THIS SEASON only counts rounds with at least two human seats (a seat with no ai_level), so a room filled with
-- AI can't farm the board. Guests with an anonymous account count like any account.
create or replace function public.leaderboard_season_wins(lim int default 50)
returns table (rank bigint, name text, wins bigint, is_me boolean)
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
  )
  select rank() over (order by w.wins desc), p.name, w.wins, w.user_id = (select auth.uid())
  from w join public.profiles p on p.id = w.user_id
  order by w.wins desc, p.name
  limit least(greatest(lim, 1), 100)
$$;
revoke execute on function public.leaderboard_season_wins(int) from public;
grant execute on function public.leaderboard_season_wins(int) to anon, authenticated;
