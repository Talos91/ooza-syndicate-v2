-- Ooze Syndicate 2.0 accounts, cloud saves, server-written match results (PROGRESSION-DESIGN §7 / §7a).
-- Trust rule: matches / match_seats / faction_stats are written only by the match-result edge function (service
-- role, HMAC-signed reports from the room server's match host). cloud_saves is the player's own device snapshot
-- (untrusted; restore only). Leaderboards read server-written tables only.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 3 and 16),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cloud_saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  save jsonb not null,
  build text,
  updated_at timestamptz not null default now()
);

create table public.matches (
  match_id text primary key,
  build text,
  map text,
  mode text,
  rules jsonb,
  started_at timestamptz,
  duration_s real,
  outcome jsonb,
  reported_at timestamptz not null default now()
);

create table public.match_seats (
  match_id text not null references public.matches(match_id) on delete cascade,
  seat text not null,
  team int,
  faction text,
  user_id uuid references auth.users(id) on delete set null,
  ai_level text,
  left_early boolean not null default false,
  placed int,
  won boolean not null default false,
  stats jsonb,
  primary key (match_id, seat)
);
create index match_seats_user_idx on public.match_seats (user_id);

create table public.faction_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  faction text not null,
  plays int not null default 0,
  wins int not null default 0,
  primary key (user_id, faction)
);

alter table public.profiles enable row level security;
alter table public.cloud_saves enable row level security;
alter table public.matches enable row level security;
alter table public.match_seats enable row level security;
alter table public.faction_stats enable row level security;

create policy "own profile: read" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "own save: read" on public.cloud_saves for select to authenticated using ((select auth.uid()) = user_id);
create policy "own save: insert" on public.cloud_saves for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own save: update" on public.cloud_saves for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own seats: read" on public.match_seats for select to authenticated using ((select auth.uid()) = user_id);
create policy "own faction stats: read" on public.faction_stats for select to authenticated using ((select auth.uid()) = user_id);
-- matches: no client policy (read through leaderboard functions only); no client write policies anywhere else.

-- a profile for every new account (guest or linked), with a playful default name
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name)
  values (new.id, 'SLIME-' || upper(substr(replace(new.id::text, '-', ''), 1, 5)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- the player renames themselves (3-16 letters, digits, space, - or _)
create function public.set_name(new_name text) returns text
language plpgsql security definer set search_path = '' as $$
declare n text := upper(btrim(new_name));
begin
  if (select auth.uid()) is null then raise exception 'not signed in'; end if;
  if n !~ '^[A-Z0-9 _-]{3,16}$' then raise exception 'names are 3-16 letters, digits, space, - or _'; end if;
  update public.profiles set name = n, updated_at = now() where id = (select auth.uid());
  return n;
end $$;
revoke execute on function public.set_name(text) from public, anon;
grant execute on function public.set_name(text) to authenticated;

-- a match report from the room server's match host (called by the match-result edge function with the service role):
-- idempotent on match_id; seats with a user_id update that player's faction stats.
create function public.ingest_match(r jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare s jsonb; uid uuid;
begin
  insert into public.matches (match_id, build, map, mode, rules, started_at, duration_s, outcome)
  values (r->>'match_id', r->>'build', r->>'map', r->>'mode', r->'rules',
          to_timestamp((r->>'started_at')::double precision), (r->>'duration_s')::real, r->'outcome')
  on conflict (match_id) do nothing;
  if not found then return 'duplicate'; end if;
  for s in select * from jsonb_array_elements(coalesce(r->'seats', '[]'::jsonb)) loop
    uid := nullif(s->>'user_id', '')::uuid;
    if uid is not null and not exists (select 1 from auth.users where id = uid) then uid := null; end if;
    insert into public.match_seats (match_id, seat, team, faction, user_id, ai_level, left_early, placed, won, stats)
    values (r->>'match_id', s->>'seat', (s->>'team')::int, s->>'faction', uid, nullif(s->>'ai_level', ''),
            coalesce((s->>'left_early')::boolean, false), (s->>'placed')::int, coalesce((s->>'won')::boolean, false), s->'stats');
    if uid is not null and not coalesce((s->>'left_early')::boolean, false) then
      insert into public.faction_stats as f (user_id, faction, plays, wins)
      values (uid, s->>'faction', 1, case when coalesce((s->>'won')::boolean, false) then 1 else 0 end)
      on conflict (user_id, faction) do update
        set plays = f.plays + 1, wins = f.wins + excluded.wins;
    end if;
  end loop;
  return 'recorded';
end $$;
revoke execute on function public.ingest_match(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_match(jsonb) to service_role;

-- WINS THIS SEASON (a season = the UTC calendar month until seasons are designed): online wins in server-hosted
-- rooms by signed-in players. Returns names only (no user ids) plus which row is you.
create function public.leaderboard_season_wins(lim int default 50)
returns table (rank bigint, name text, wins bigint, is_me boolean)
language sql security definer set search_path = '' stable as $$
  with w as (
    select ms.user_id, count(*) as wins
    from public.match_seats ms join public.matches m on m.match_id = ms.match_id
    where ms.won and not ms.left_early and ms.user_id is not null
      and m.started_at >= date_trunc('month', now() at time zone 'utc') at time zone 'utc'
    group by ms.user_id
  )
  select rank() over (order by w.wins desc), p.name, w.wins, w.user_id = (select auth.uid())
  from w join public.profiles p on p.id = w.user_id
  order by w.wins desc, p.name
  limit least(greatest(lim, 1), 100)
$$;
revoke execute on function public.leaderboard_season_wins(int) from public;
grant execute on function public.leaderboard_season_wins(int) to anon, authenticated;
