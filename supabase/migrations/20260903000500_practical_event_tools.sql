-- Practical event tools: structured discovery filters, reusable searches,
-- followed-host alerts, event templates, privacy-aware attendee lists,
-- RSVP reconfirmation, and per-event discussion notification controls.

alter table public.events
  add column beginner_friendly boolean not null default false,
  add column wheelchair_accessible boolean not null default false,
  add column event_setting text not null default 'unspecified' check (
    event_setting in ('unspecified', 'indoor', 'outdoor', 'mixed')
  ),
  add column event_language text not null default '' check (
    char_length(event_language) <= 80
  ),
  add column age_guidance text not null default 'all_ages' check (
    age_guidance in ('all_ages', 'families', 'teens', 'adults')
  ),
  add column what_to_bring text not null default '' check (
    char_length(what_to_bring) <= 500
  ),
  add column reconfirmation_deadline_at timestamptz,
  add constraint event_reconfirmation_before_start check (
    reconfirmation_deadline_at is null or reconfirmation_deadline_at < start_at
  );

alter table public.event_rsvps
  add column visible_to_attendees boolean not null default false,
  add column reconfirmed_at timestamptz;

alter table public.member_notifications
  drop constraint if exists member_notifications_kind_check;
alter table public.member_notifications
  add constraint member_notifications_kind_check check (
    kind in (
      'reminder', 'waitlist_promoted', 'event_updated', 'event_cancelled',
      'announcement', 'discussion_reply', 'feedback_received',
      'saved_search_match', 'followed_host_event', 'rsvp_reconfirmation'
    )
  );

create table public.saved_event_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  interest text not null default '' check (char_length(interest) <= 240),
  radius_km double precision not null check (radius_km between 1 and 100),
  category text check (category is null or char_length(category) between 2 and 60),
  date_filter text not null default 'any' check (
    date_filter in ('any', 'today', 'tomorrow', 'weekend')
  ),
  time_filter text not null default 'any' check (
    time_filter in ('any', 'morning', 'afternoon', 'evening')
  ),
  timezone_offset_minutes integer not null default 0 check (
    timezone_offset_minutes between -840 and 840
  ),
  spots_only boolean not null default false,
  following_only boolean not null default false,
  alerts_enabled boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  unique (user_id, name)
);

create table public.event_notification_preferences (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  discussion_enabled boolean not null default true,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, user_id)
);

create index saved_event_searches_user_idx
  on public.saved_event_searches (user_id, created_at desc);
create index event_notification_preferences_event_idx
  on public.event_notification_preferences (event_id, discussion_enabled);

alter table public.saved_event_searches enable row level security;
alter table public.event_notification_preferences enable row level security;
revoke all on public.saved_event_searches from public, anon, authenticated;
revoke all on public.event_notification_preferences from public, anon, authenticated;

create trigger event_notification_preferences_set_updated_at
before update on public.event_notification_preferences
for each row execute function public.set_updated_at();

create function public.list_followed_profile_ids()
returns table (profile_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select f.followed_id
  from public.profile_follows f
  where auth.uid() is not null
    and f.follower_id = auth.uid()
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = f.followed_id)
         or (b.blocker_id = f.followed_id and b.blocked_id = auth.uid())
    );
$$;

create function public.list_followed_nearby_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision,
  p_query text default null
)
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text,
  description text, category text, venue_name text, address text,
  latitude double precision, longitude double precision,
  start_at timestamptz, end_at timestamptz, max_participants integer,
  joined_count bigint, tentative_count bigint, distance_meters double precision,
  user_rsvp_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with origin as (
    select extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude), 4326
    )::extensions.geography as point
  )
  select
    e.id, e.organizer_id, p.display_name, e.title, e.description, e.category,
    e.venue_name, e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at, e.end_at, e.max_participants,
    (select pg_catalog.count(*) from public.event_rsvps r
      where r.event_id = e.id and r.status = 'joined'),
    (select pg_catalog.count(*) from public.event_rsvps r
      where r.event_id = e.id and r.status = 'tentative'),
    extensions.st_distance(e.location, origin.point),
    (select r.status from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid())
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  join public.profile_follows f
    on f.followed_id = e.organizer_id and f.follower_id = auth.uid()
  cross join origin
  where auth.uid() is not null
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and e.status = 'published' and e.visibility = 'public'
    and e.start_at > pg_catalog.now()
    and extensions.st_dwithin(
      e.location, origin.point,
      least(greatest(p_radius_km, 1), 100) * 1000
    )
    and (
      nullif(trim(coalesce(p_query, '')), '') is null
      or e.search_document @@ websearch_to_tsquery('english'::regconfig, p_query)
      or e.title ilike '%' || trim(p_query) || '%'
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = e.organizer_id)
    )
  order by e.start_at, e.location operator(extensions.<->) origin.point, e.id
  limit 100;
$$;

create function public.list_saved_event_searches()
returns table (
  id uuid, name text, interest text, radius_km double precision,
  category text, date_filter text, time_filter text, spots_only boolean,
  following_only boolean, alerts_enabled boolean,
  timezone_offset_minutes integer, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return query
  select s.id, s.name, s.interest, s.radius_km, s.category, s.date_filter,
    s.time_filter, s.spots_only, s.following_only, s.alerts_enabled,
    s.timezone_offset_minutes, s.created_at
  from public.saved_event_searches s
  where s.user_id = auth.uid()
  order by s.created_at desc, s.id;
end;
$$;

create function public.create_saved_event_search(
  p_name text,
  p_interest text,
  p_radius_km double precision,
  p_category text,
  p_date_filter text,
  p_time_filter text,
  p_timezone_offset_minutes integer,
  p_spots_only boolean,
  p_following_only boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare search_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_name)) not between 1 and 80
    or char_length(trim(coalesce(p_interest, ''))) > 240
    or p_radius_km not between 1 and 100
    or (p_category is not null and char_length(trim(p_category)) not between 2 and 60)
    or p_date_filter not in ('any', 'today', 'tomorrow', 'weekend')
    or p_time_filter not in ('any', 'morning', 'afternoon', 'evening')
    or p_timezone_offset_minutes not between -840 and 840 then
    raise exception using errcode = '22023', message = 'saved_search_validation';
  end if;
  if (
    select pg_catalog.count(*) from public.saved_event_searches s
    where s.user_id = auth.uid()
  ) >= 12 then
    raise exception using errcode = 'P0001', message = 'saved_search_limit';
  end if;

  insert into public.saved_event_searches (
    user_id, name, interest, radius_km, category, date_filter, time_filter,
    timezone_offset_minutes, spots_only, following_only
  ) values (
    auth.uid(), trim(p_name), trim(coalesce(p_interest, '')), p_radius_km,
    nullif(trim(coalesce(p_category, '')), ''), p_date_filter, p_time_filter,
    p_timezone_offset_minutes, p_spots_only, p_following_only
  )
  on conflict (user_id, name) do update set
    interest = excluded.interest,
    radius_km = excluded.radius_km,
    category = excluded.category,
    date_filter = excluded.date_filter,
    time_filter = excluded.time_filter,
    timezone_offset_minutes = excluded.timezone_offset_minutes,
    spots_only = excluded.spots_only,
    following_only = excluded.following_only,
    alerts_enabled = true
  returning id into search_id;
  return search_id;
end;
$$;

create function public.delete_saved_event_search(p_search_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.saved_event_searches s
  where s.id = p_search_id and s.user_id = auth.uid();
  return found;
end;
$$;

create function public._notify_for_new_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'published' or new.visibility <> 'public' then
    return new;
  end if;

  insert into public.member_notifications (
    user_id, event_id, kind, title, body
  )
  select f.follower_id, new.id, 'followed_host_event',
    'New event from someone you follow',
    p.display_name || ' published ' || new.title || '.'
  from public.profile_follows f
  join public.profiles p on p.id = new.organizer_id
  where f.followed_id = new.organizer_id
    and f.follower_id <> new.organizer_id
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = f.follower_id and b.blocked_id = new.organizer_id)
         or (b.blocker_id = new.organizer_id and b.blocked_id = f.follower_id)
    );

  insert into public.member_notifications (
    user_id, event_id, source_id, kind, title, body
  )
  select s.user_id, new.id, s.id, 'saved_search_match',
    'New event matching ' || s.name,
    new.title || ' was just published near you.'
  from public.saved_event_searches s
  join public.profiles p on p.id = s.user_id
  where s.alerts_enabled
    and s.user_id <> new.organizer_id
    and p.approximate_latitude is not null
    and p.approximate_longitude is not null
    and extensions.st_dwithin(
      new.location,
      extensions.st_setsrid(
        extensions.st_makepoint(
          p.approximate_longitude,
          p.approximate_latitude
        ),
        4326
      )::extensions.geography,
      s.radius_km * 1000
    )
    and (s.category is null or s.category = new.category)
    and (
      s.interest = ''
      or new.search_document @@ websearch_to_tsquery('english'::regconfig, s.interest)
      or new.title ilike '%' || s.interest || '%'
    )
    and (
      not s.following_only
      or exists (
        select 1 from public.profile_follows f
        where f.follower_id = s.user_id and f.followed_id = new.organizer_id
      )
    )
    and case s.date_filter
      when 'today' then
        (new.start_at + make_interval(mins => s.timezone_offset_minutes))::date =
        (pg_catalog.now() + make_interval(mins => s.timezone_offset_minutes))::date
      when 'tomorrow' then
        (new.start_at + make_interval(mins => s.timezone_offset_minutes))::date =
        (pg_catalog.now() + make_interval(mins => s.timezone_offset_minutes) + interval '1 day')::date
      when 'weekend' then
        extract(isodow from new.start_at + make_interval(mins => s.timezone_offset_minutes)) in (6, 7)
        and new.start_at < pg_catalog.now() + interval '7 days'
      else true
    end
    and case s.time_filter
      when 'morning' then extract(hour from new.start_at + make_interval(mins => s.timezone_offset_minutes)) between 5 and 11
      when 'afternoon' then extract(hour from new.start_at + make_interval(mins => s.timezone_offset_minutes)) between 12 and 16
      when 'evening' then extract(hour from new.start_at + make_interval(mins => s.timezone_offset_minutes)) between 17 and 23
      else true
    end
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = s.user_id and b.blocked_id = new.organizer_id)
         or (b.blocker_id = new.organizer_id and b.blocked_id = s.user_id)
    )
  on conflict do nothing;

  return new;
end;
$$;

create trigger events_notify_new_event
after insert on public.events
for each row execute function public._notify_for_new_event();

create function public.create_event_v2(
  p_title text,
  p_description text,
  p_category text,
  p_venue_name text,
  p_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_max_participants integer,
  p_beginner_friendly boolean,
  p_wheelchair_accessible boolean,
  p_event_setting text,
  p_event_language text,
  p_age_guidance text,
  p_what_to_bring text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_event_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_title)) not between 3 and 120
    or char_length(trim(p_description)) not between 1 and 2000
    or char_length(trim(p_category)) not between 2 and 60
    or char_length(trim(p_venue_name)) not between 2 and 160
    or char_length(trim(p_address)) not between 3 and 300
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
    or p_start_at <= pg_catalog.now()
    or p_end_at <= p_start_at
    or p_max_participants not between 2 and 500
    or p_event_setting not in ('unspecified', 'indoor', 'outdoor', 'mixed')
    or char_length(trim(coalesce(p_event_language, ''))) > 80
    or p_age_guidance not in ('all_ages', 'families', 'teens', 'adults')
    or char_length(trim(coalesce(p_what_to_bring, ''))) > 500 then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  insert into public.events (
    organizer_id, title, description, category, venue_name, address, location,
    start_at, end_at, max_participants, beginner_friendly,
    wheelchair_accessible, event_setting, event_language, age_guidance,
    what_to_bring
  ) values (
    auth.uid(), trim(p_title), trim(p_description), trim(p_category),
    trim(p_venue_name), trim(p_address),
    extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude), 4326
    )::extensions.geography,
    p_start_at, p_end_at, p_max_participants, p_beginner_friendly,
    p_wheelchair_accessible, p_event_setting,
    trim(coalesce(p_event_language, '')), p_age_guidance,
    trim(coalesce(p_what_to_bring, ''))
  ) returning id into new_event_id;

  insert into public.event_rsvps (
    event_id, user_id, status, visible_to_attendees, reconfirmed_at
  ) values (
    new_event_id, auth.uid(), 'joined', true, pg_catalog.now()
  );
  return new_event_id;
end;
$$;

create function public.update_own_event_v2(
  p_event_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_venue_name text,
  p_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_max_participants integer,
  p_beginner_friendly boolean,
  p_wheelchair_accessible boolean,
  p_event_setting text,
  p_event_language text,
  p_age_guidance text,
  p_what_to_bring text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  joined_total integer;
  previous_start timestamptz;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_title)) not between 3 and 120
    or char_length(trim(p_description)) not between 1 and 2000
    or char_length(trim(p_category)) not between 2 and 60
    or char_length(trim(p_venue_name)) not between 2 and 160
    or char_length(trim(p_address)) not between 3 and 300
    or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
    or p_start_at <= pg_catalog.now() or p_end_at <= p_start_at
    or p_max_participants not between 2 and 500
    or p_event_setting not in ('unspecified', 'indoor', 'outdoor', 'mixed')
    or char_length(trim(coalesce(p_event_language, ''))) > 80
    or p_age_guidance not in ('all_ages', 'families', 'teens', 'adults')
    or char_length(trim(coalesce(p_what_to_bring, ''))) > 500 then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_event_id::text, 0)
  );
  select e.start_at into previous_start
  from public.events e
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published' and e.start_at > pg_catalog.now()
  for update;
  if previous_start is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  select pg_catalog.count(*) into joined_total
  from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'joined';
  if p_max_participants < joined_total then
    raise exception using errcode = '22023', message = 'capacity_below_attendance';
  end if;

  update public.events e set
    title = trim(p_title), description = trim(p_description),
    category = trim(p_category), venue_name = trim(p_venue_name),
    address = trim(p_address),
    location = extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude), 4326
    )::extensions.geography,
    start_at = p_start_at, end_at = p_end_at,
    max_participants = p_max_participants,
    beginner_friendly = p_beginner_friendly,
    wheelchair_accessible = p_wheelchair_accessible,
    event_setting = p_event_setting,
    event_language = trim(coalesce(p_event_language, '')),
    age_guidance = p_age_guidance,
    what_to_bring = trim(coalesce(p_what_to_bring, ''))
  where e.id = p_event_id;

  update public.event_reminders reminder set
    remind_at = p_start_at - (previous_start - reminder.remind_at)
  where reminder.event_id = p_event_id and reminder.remind_at < previous_start;

  insert into public.member_notifications (user_id, event_id, kind, title, body)
  select recipients.user_id, p_event_id, 'event_updated', 'Event updated',
    trim(p_title) || ' has new details. Please review your plan.'
  from (
    select r.user_id from public.event_rsvps r
    where r.event_id = p_event_id and r.status in ('joined', 'tentative', 'waitlisted')
    union
    select s.user_id from public.event_saves s where s.event_id = p_event_id
  ) recipients
  where recipients.user_id <> auth.uid();

  while joined_total < p_max_participants loop
    exit when public._promote_event_waitlist(p_event_id) is null;
    joined_total := joined_total + 1;
  end loop;
  return true;
end;
$$;

create function public.get_event_details_v2(p_event_id uuid)
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text,
  description text, category text, venue_name text, address text,
  latitude double precision, longitude double precision,
  start_at timestamptz, end_at timestamptz, max_participants integer,
  joined_count bigint, tentative_count bigint, distance_meters double precision,
  user_rsvp_status text, event_status text, is_saved boolean,
  reminder_at timestamptz, waitlist_position bigint, viewer_is_organizer boolean,
  beginner_friendly boolean, wheelchair_accessible boolean,
  event_setting text, event_language text, age_guidance text,
  what_to_bring text, attendee_visible boolean,
  discussion_notifications_enabled boolean,
  reconfirmation_deadline_at timestamptz, viewer_reconfirmed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id, e.organizer_id, p.display_name, e.title, e.description, e.category,
    e.venue_name, e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at, e.end_at, e.max_participants,
    (select pg_catalog.count(*) from public.event_rsvps c
      where c.event_id = e.id and c.status = 'joined'),
    (select pg_catalog.count(*) from public.event_rsvps c
      where c.event_id = e.id and c.status = 'tentative'),
    0::double precision,
    r.status, e.status, (s.user_id is not null), reminder.remind_at,
    case when r.status = 'waitlisted' then (
      select pg_catalog.count(*) from public.event_rsvps queued
      where queued.event_id = e.id and queued.status = 'waitlisted'
        and (queued.created_at, queued.user_id) <= (r.created_at, r.user_id)
    ) else null end,
    (e.organizer_id = auth.uid()),
    e.beginner_friendly, e.wheelchair_accessible, e.event_setting,
    e.event_language, e.age_guidance, e.what_to_bring,
    coalesce(r.visible_to_attendees, false),
    coalesce(preference.discussion_enabled, true),
    e.reconfirmation_deadline_at, r.reconfirmed_at
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  left join public.event_rsvps r
    on r.event_id = e.id and r.user_id = auth.uid()
  left join public.event_saves s
    on s.event_id = e.id and s.user_id = auth.uid()
  left join public.event_reminders reminder
    on reminder.event_id = e.id and reminder.user_id = auth.uid()
  left join public.event_notification_preferences preference
    on preference.event_id = e.id and preference.user_id = auth.uid()
  where e.id = p_event_id
    and auth.uid() is not null
    and (
      (e.status = 'published' and e.visibility = 'public')
      or e.organizer_id = auth.uid()
      or r.user_id is not null
      or s.user_id is not null
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = e.organizer_id)
    );
$$;

create function public.list_event_attendees(p_event_id uuid)
returns table (
  profile_id uuid, display_name text, username text, rsvp_status text,
  visible_to_attendees boolean, is_self boolean, reconfirmed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare viewer_is_host boolean;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select e.organizer_id = auth.uid() into viewer_is_host
  from public.events e where e.id = p_event_id;
  if viewer_is_host is null or (
    not viewer_is_host and not exists (
      select 1 from public.event_rsvps mine
      where mine.event_id = p_event_id and mine.user_id = auth.uid()
        and mine.status in ('joined', 'tentative', 'waitlisted', 'attended')
    )
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  return query
  select p.id, p.display_name, coalesce(p.username, ''), r.status,
    r.visible_to_attendees, (r.user_id = auth.uid()), r.reconfirmed_at
  from public.event_rsvps r
  join public.profiles p on p.id = r.user_id
  where r.event_id = p_event_id
    and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
    and (viewer_is_host or r.user_id = auth.uid()
      or (r.status = 'joined' and r.visible_to_attendees))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = r.user_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = r.user_id)
    )
  order by
    case r.status when 'joined' then 0 when 'tentative' then 1 else 2 end,
    r.created_at, r.user_id;
end;
$$;

create function public.set_event_attendee_visibility(
  p_event_id uuid,
  p_visible boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.event_rsvps r set visible_to_attendees = p_visible
  where r.event_id = p_event_id and r.user_id = auth.uid()
    and r.status in ('joined', 'tentative', 'waitlisted', 'attended');
  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return p_visible;
end;
$$;

create function public.set_event_discussion_notifications(
  p_event_id uuid,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (
    select 1 from public.events e
    where e.id = p_event_id and (
      e.organizer_id = auth.uid() or exists (
        select 1 from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
          and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
      )
    )
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  insert into public.event_notification_preferences (
    event_id, user_id, discussion_enabled
  ) values (p_event_id, auth.uid(), p_enabled)
  on conflict (event_id, user_id) do update set
    discussion_enabled = excluded.discussion_enabled,
    updated_at = pg_catalog.now();
  return p_enabled;
end;
$$;

create or replace function public.create_event_discussion_message(
  p_event_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  message_id uuid;
  event_title text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_body)) not between 1 and 1200 then
    raise exception using errcode = '22023', message = 'discussion_validation';
  end if;
  if (
    select pg_catalog.count(*) from public.event_discussion_messages recent
    where recent.author_id = auth.uid()
      and recent.created_at > pg_catalog.now() - interval '1 minute'
  ) >= 8 then
    raise exception using errcode = 'P0001', message = 'discussion_rate_limited';
  end if;
  select e.title into event_title
  from public.events e
  where e.id = p_event_id and e.status = 'published'
    and (e.organizer_id = auth.uid() or exists (
      select 1 from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
        and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
    ));
  if event_title is null then
    raise exception using errcode = '42501', message = 'discussion_unavailable';
  end if;

  insert into public.event_discussion_messages (event_id, author_id, body)
  values (p_event_id, auth.uid(), trim(p_body)) returning id into message_id;

  insert into public.member_notifications (
    user_id, event_id, source_id, kind, title, body
  )
  select recipients.user_id, p_event_id, message_id, 'discussion_reply',
    'New event message', event_title || ' has a new attendee message.'
  from (
    select e.organizer_id as user_id from public.events e where e.id = p_event_id
    union
    select r.user_id from public.event_rsvps r
    where r.event_id = p_event_id
      and r.status in ('joined', 'tentative', 'waitlisted')
  ) recipients
  left join public.event_notification_preferences preference
    on preference.event_id = p_event_id
    and preference.user_id = recipients.user_id
  where recipients.user_id <> auth.uid()
    and coalesce(preference.discussion_enabled, true)
  on conflict do nothing;
  return message_id;
end;
$$;

create function public.request_event_rsvp_reconfirmation(p_event_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_title text;
  event_start timestamptz;
  deadline timestamptz;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select e.title, e.start_at into event_title, event_start
  from public.events e
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published'
    and (
      e.reconfirmation_deadline_at is null
      or e.reconfirmation_deadline_at <= pg_catalog.now()
    )
  for update;
  if event_start is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  deadline := least(
    pg_catalog.now() + interval '24 hours',
    event_start - interval '2 hours'
  );
  if deadline <= pg_catalog.now() + interval '15 minutes' then
    raise exception using errcode = 'P0001', message = 'reconfirmation_too_late';
  end if;

  update public.events e set reconfirmation_deadline_at = deadline
  where e.id = p_event_id;
  update public.event_rsvps r set reconfirmed_at = null
  where r.event_id = p_event_id and r.status = 'joined'
    and r.user_id <> auth.uid();

  insert into public.member_notifications (
    user_id, event_id, kind, title, body
  )
  select r.user_id, p_event_id, 'rsvp_reconfirmation',
    'Please confirm your place',
    'Confirm that you are still going to ' || event_title || ' before the deadline.'
  from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'joined'
    and r.user_id <> auth.uid();
  return deadline;
end;
$$;

create function public.confirm_event_rsvp(p_event_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare confirmed_at timestamptz := pg_catalog.now();
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.event_rsvps r set reconfirmed_at = confirmed_at
  from public.events e
  where r.event_id = p_event_id and r.user_id = auth.uid()
    and r.status = 'joined' and e.id = r.event_id
    and e.reconfirmation_deadline_at > pg_catalog.now();
  if not found then
    raise exception using errcode = 'P0001', message = 'reconfirmation_unavailable';
  end if;
  return confirmed_at;
end;
$$;

create function public.process_due_event_reconfirmations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_event record;
  released integer := 0;
  released_for_event integer;
  event_limit integer;
  joined_total integer;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  for due_event in
    select e.id, e.organizer_id, e.title
    from public.events e
    where e.status = 'published'
      and e.reconfirmation_deadline_at <= pg_catalog.now()
      and e.start_at > pg_catalog.now()
    order by e.reconfirmation_deadline_at
    limit 20
    for update skip locked
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(due_event.id::text, 0)
    );
    with released_rows as (
      update public.event_rsvps r
      set status = 'cancelled', updated_at = pg_catalog.now()
      where r.event_id = due_event.id and r.status = 'joined'
        and r.user_id <> due_event.organizer_id and r.reconfirmed_at is null
      returning r.user_id
    )
    insert into public.member_notifications (
      user_id, event_id, kind, title, body
    )
    select released_rows.user_id, due_event.id, 'rsvp_reconfirmation',
      'Your event place was released',
      'Your place for ' || due_event.title || ' was released because it was not reconfirmed.'
    from released_rows;
    get diagnostics released_for_event = row_count;
    released := released + released_for_event;

    select e.max_participants into event_limit
    from public.events e where e.id = due_event.id;
    select pg_catalog.count(*) into joined_total
    from public.event_rsvps r
    where r.event_id = due_event.id and r.status = 'joined';
    while joined_total < event_limit loop
      exit when public._promote_event_waitlist(due_event.id) is null;
      joined_total := joined_total + 1;
    end loop;
    update public.events e set reconfirmation_deadline_at = null
    where e.id = due_event.id;
  end loop;
  return released;
end;
$$;

create function public._mark_new_join_reconfirmed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'joined' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'joined' then
    return new;
  end if;
  if exists (
      select 1 from public.events e
      where e.id = new.event_id
        and e.reconfirmation_deadline_at > pg_catalog.now()
    ) then
    new.reconfirmed_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

create trigger event_rsvps_mark_new_join_reconfirmed
before insert or update on public.event_rsvps
for each row execute function public._mark_new_join_reconfirmed();

revoke all on function public.list_followed_profile_ids() from public, anon;
revoke all on function public.list_followed_nearby_events(
  double precision, double precision, double precision, text
) from public, anon;
revoke all on function public.list_saved_event_searches() from public, anon;
revoke all on function public.create_saved_event_search(
  text, text, double precision, text, text, text, integer, boolean, boolean
) from public, anon;
revoke all on function public.delete_saved_event_search(uuid) from public, anon;
revoke all on function public.create_event_v2(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text
) from public, anon;
revoke all on function public.update_own_event_v2(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text
) from public, anon;
revoke all on function public.get_event_details_v2(uuid) from public, anon;
revoke all on function public.list_event_attendees(uuid) from public, anon;
revoke all on function public.set_event_attendee_visibility(uuid, boolean) from public, anon;
revoke all on function public.set_event_discussion_notifications(uuid, boolean) from public, anon;
revoke all on function public.request_event_rsvp_reconfirmation(uuid) from public, anon;
revoke all on function public.confirm_event_rsvp(uuid) from public, anon;
revoke all on function public.process_due_event_reconfirmations() from public, anon;

grant execute on function public.list_followed_profile_ids() to authenticated;
grant execute on function public.list_followed_nearby_events(
  double precision, double precision, double precision, text
) to authenticated;
grant execute on function public.list_saved_event_searches() to authenticated;
grant execute on function public.create_saved_event_search(
  text, text, double precision, text, text, text, integer, boolean, boolean
) to authenticated;
grant execute on function public.delete_saved_event_search(uuid) to authenticated;
grant execute on function public.create_event_v2(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text
) to authenticated;
grant execute on function public.update_own_event_v2(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text
) to authenticated;
grant execute on function public.get_event_details_v2(uuid) to authenticated;
grant execute on function public.list_event_attendees(uuid) to authenticated;
grant execute on function public.set_event_attendee_visibility(uuid, boolean) to authenticated;
grant execute on function public.set_event_discussion_notifications(uuid, boolean) to authenticated;
grant execute on function public.request_event_rsvp_reconfirmation(uuid) to authenticated;
grant execute on function public.confirm_event_rsvp(uuid) to authenticated;
grant execute on function public.process_due_event_reconfirmations() to authenticated;

comment on table public.saved_event_searches is
  'Private reusable discovery filters that may create in-app match alerts.';
comment on table public.event_notification_preferences is
  'Private per-member event notification controls; essential lifecycle alerts cannot be muted.';
