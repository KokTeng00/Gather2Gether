-- Gather2Gether MVP: nearby free events with Join/Tentative RSVP.
-- Client-facing tables use RLS. Elevated functions have fixed search paths,
-- derive identity from auth.uid(), validate inputs, and expose minimal data.

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  bio text not null default '' check (char_length(bio) <= 500),
  city text check (city is null or char_length(city) <= 120),
  approximate_latitude double precision check (
    approximate_latitude is null or approximate_latitude between -90 and 90
  ),
  approximate_longitude double precision check (
    approximate_longitude is null or approximate_longitude between -180 and 180
  ),
  preferred_radius_km double precision not null default 10 check (
    preferred_radius_km between 1 and 100
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint approximate_location_pair check (
    (approximate_latitude is null) = (approximate_longitude is null)
  )
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.profiles(id) on delete restrict,
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 1 and 2000),
  category text not null check (char_length(category) between 2 and 60),
  venue_name text not null check (char_length(venue_name) between 2 and 160),
  address text not null check (char_length(address) between 3 and 300),
  location extensions.geography(point, 4326) not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  max_participants integer not null check (max_participants between 2 and 500),
  status text not null default 'published' check (
    status in ('draft', 'published', 'cancelled', 'completed')
  ),
  visibility text not null default 'public' check (
    visibility in ('public', 'unlisted')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_event_time check (end_at > start_at)
);

create table public.event_rsvps (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (
    status in ('joined', 'tentative', 'cancelled', 'attended', 'no_show')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  reason text not null check (
    reason in (
      'spam',
      'unsafe_behaviour',
      'inappropriate_content',
      'misleading',
      'other'
    )
  ),
  status text not null default 'open' check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  created_at timestamptz not null default now()
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint cannot_block_self check (blocker_id <> blocked_id)
);

create index events_location_gix on public.events using gist (location);
create index events_discovery_idx
  on public.events (status, visibility, start_at);
create index events_organizer_idx on public.events (organizer_id, start_at desc);
create index event_rsvps_status_idx on public.event_rsvps (event_id, status);
create index reports_status_idx on public.reports (status, created_at);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger events_set_updated_at
before update on public.events
for each row execute function public.set_updated_at();

create trigger event_rsvps_set_updated_at
before update on public.event_rsvps
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  inferred_name text;
begin
  inferred_name := nullif(
    left(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 80),
    ''
  );

  if inferred_name is null then
    inferred_name := left(coalesce(split_part(new.email, '@', 1), 'Member'), 80);
  end if;

  insert into public.profiles (id, display_name)
  values (new.id, inferred_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.event_rsvps enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

create policy profiles_select_own
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy profiles_update_own
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy events_select_visible
on public.events for select to authenticated
using (
  (status = 'published' and visibility = 'public')
  or organizer_id = (select auth.uid())
);

create policy events_update_own
on public.events for update to authenticated
using (organizer_id = (select auth.uid()))
with check (organizer_id = (select auth.uid()));

create policy rsvps_select_relevant
on public.event_rsvps for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.events e
    where e.id = event_rsvps.event_id
      and e.organizer_id = (select auth.uid())
  )
);

create policy reports_insert_own
on public.reports for insert to authenticated
with check (reporter_id = (select auth.uid()));

create policy blocks_manage_own
on public.blocks for all to authenticated
using (blocker_id = (select auth.uid()))
with check (blocker_id = (select auth.uid()));

create or replace function public.create_event(
  p_title text,
  p_description text,
  p_category text,
  p_venue_name text,
  p_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_max_participants integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_event_id uuid;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if char_length(trim(p_title)) not between 3 and 120
    or char_length(trim(p_description)) not between 1 and 2000
    or char_length(trim(p_category)) not between 2 and 60
    or char_length(trim(p_venue_name)) not between 2 and 160
    or char_length(trim(p_address)) not between 3 and 300
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
    or p_start_at <= now()
    or p_end_at <= p_start_at
    or p_max_participants not between 2 and 500 then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  insert into public.events (
    organizer_id,
    title,
    description,
    category,
    venue_name,
    address,
    location,
    start_at,
    end_at,
    max_participants
  ) values (
    current_user_id,
    trim(p_title),
    trim(p_description),
    trim(p_category),
    trim(p_venue_name),
    trim(p_address),
    extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography,
    p_start_at,
    p_end_at,
    p_max_participants
  ) returning id into new_event_id;

  insert into public.event_rsvps (event_id, user_id, status)
  values (new_event_id, current_user_id, 'joined');

  return new_event_id;
end;
$$;

create or replace function public.nearby_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 10
)
returns table (
  id uuid,
  organizer_id uuid,
  organizer_name text,
  title text,
  description text,
  category text,
  venue_name text,
  address text,
  latitude double precision,
  longitude double precision,
  start_at timestamptz,
  end_at timestamptz,
  max_participants integer,
  joined_count bigint,
  tentative_count bigint,
  distance_meters double precision,
  user_rsvp_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with origin as (
    select extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography as point
  )
  select
    e.id,
    e.organizer_id,
    p.display_name,
    e.title,
    e.description,
    e.category,
    e.venue_name,
    e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at,
    e.end_at,
    e.max_participants,
    count(r.user_id) filter (where r.status = 'joined'),
    count(r.user_id) filter (where r.status = 'tentative'),
    extensions.st_distance(e.location, origin.point),
    max(r.status) filter (where r.user_id = auth.uid())
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  cross join origin
  left join public.event_rsvps r on r.event_id = e.id
  where auth.uid() is not null
    and e.status = 'published'
    and e.visibility = 'public'
    and e.start_at > now()
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and extensions.st_dwithin(
      e.location,
      origin.point,
      least(greatest(p_radius_km, 1), 100) * 1000
    )
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
        or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
    )
  group by e.id, p.display_name, origin.point
  order by e.location operator(extensions.<->) origin.point, e.start_at
  limit 100;
$$;

create or replace function public.get_event_details(p_event_id uuid)
returns table (
  id uuid,
  organizer_id uuid,
  organizer_name text,
  title text,
  description text,
  category text,
  venue_name text,
  address text,
  latitude double precision,
  longitude double precision,
  start_at timestamptz,
  end_at timestamptz,
  max_participants integer,
  joined_count bigint,
  tentative_count bigint,
  distance_meters double precision,
  user_rsvp_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id,
    e.organizer_id,
    p.display_name,
    e.title,
    e.description,
    e.category,
    e.venue_name,
    e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at,
    e.end_at,
    e.max_participants,
    (select count(*) from public.event_rsvps r where r.event_id = e.id and r.status = 'joined'),
    (select count(*) from public.event_rsvps r where r.event_id = e.id and r.status = 'tentative'),
    0::double precision,
    (select r.status from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  where e.id = p_event_id
    and auth.uid() is not null
    and (
      (e.status = 'published' and e.visibility = 'public')
      or e.organizer_id = auth.uid()
      or exists (
        select 1
        from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
      )
    )
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
        or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
    );
$$;

create or replace function public.set_event_rsvp(
  p_event_id uuid,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  event_limit integer;
  event_start timestamptz;
  event_status text;
  current_status text;
  joined_total integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_status not in ('joined', 'tentative', 'cancelled') then
    raise exception using errcode = '22023', message = 'invalid_rsvp_status';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_event_id::text, 0)
  );

  select e.max_participants, e.start_at, e.status
  into event_limit, event_start, event_status
  from public.events e
  where e.id = p_event_id
  for update;

  if not found or event_status <> 'published' then
    raise exception using errcode = 'P0001', message = 'event_unavailable';
  end if;
  if p_status in ('joined', 'tentative') and event_start <= now() then
    raise exception using errcode = 'P0001', message = 'event_started';
  end if;

  select r.status into current_status
  from public.event_rsvps r
  where r.event_id = p_event_id and r.user_id = current_user_id;

  if p_status = 'joined' and current_status is distinct from 'joined' then
    select count(*) into joined_total
    from public.event_rsvps r
    where r.event_id = p_event_id and r.status = 'joined';

    if joined_total >= event_limit then
      raise exception using errcode = 'P0001', message = 'event_full';
    end if;
  end if;

  insert into public.event_rsvps (event_id, user_id, status)
  values (p_event_id, current_user_id, p_status)
  on conflict (event_id, user_id)
  do update set status = excluded.status, updated_at = now();

  return p_status;
end;
$$;

revoke all on public.profiles from anon, authenticated;
revoke all on public.events from anon, authenticated;
revoke all on public.event_rsvps from anon, authenticated;
revoke all on public.reports from anon, authenticated;
revoke all on public.blocks from anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select, update on public.events to authenticated;
grant select on public.event_rsvps to authenticated;
grant insert on public.reports to authenticated;
grant select, insert, update, delete on public.blocks to authenticated;

revoke all on function public.create_event(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer
) from public, anon;
revoke all on function public.nearby_events(
  double precision, double precision, double precision
) from public, anon;
revoke all on function public.get_event_details(uuid) from public, anon;
revoke all on function public.set_event_rsvp(uuid, text) from public, anon;

grant execute on function public.create_event(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer
) to authenticated;
grant execute on function public.nearby_events(
  double precision, double precision, double precision
) to authenticated;
grant execute on function public.get_event_details(uuid) to authenticated;
grant execute on function public.set_event_rsvp(uuid, text) to authenticated;

comment on table public.profiles is
  'Private user profile. Approximate coordinates are rounded client-side and protected by RLS.';
comment on table public.events is
  'Free nearby events. No price or payment fields are stored in this MVP.';
comment on function public.set_event_rsvp(uuid, text) is
  'Atomically sets Join/Tentative/Cancelled and enforces event capacity.';
