alter table public.events
  add column if not exists series_id uuid;

create index if not exists events_series_idx
  on public.events (series_id, start_at)
  where series_id is not null;

create table public.event_cohosts (
  event_id uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, profile_id)
);

create index event_cohosts_profile_idx
  on public.event_cohosts (profile_id, event_id);

alter table public.event_cohosts enable row level security;
revoke all on table public.event_cohosts from anon, authenticated;

create function public._can_manage_event(p_event_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id
      and (
        e.organizer_id = p_user_id
        or exists (
          select 1 from public.event_cohosts cohost
          where cohost.event_id = e.id and cohost.profile_id = p_user_id
        )
      )
  );
$$;

revoke all on function public._can_manage_event(uuid, uuid)
from public, anon, authenticated;

create function public.list_event_cohosts(p_event_id uuid)
returns table (
  profile_id uuid,
  display_name text,
  username text,
  role text,
  viewer_can_edit boolean
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
  if not public._can_manage_event(p_event_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  return query
  select members.profile_id, members.display_name, members.username,
    members.role, members.viewer_can_edit
  from (
    select p.id as profile_id, p.display_name,
      coalesce(p.username, '') as username, 'Owner'::text as role,
      (e.organizer_id = auth.uid()) as viewer_can_edit
    from public.events e
    join public.profiles p on p.id = e.organizer_id
    where e.id = p_event_id
    union all
    select p.id as profile_id, p.display_name,
      coalesce(p.username, '') as username, 'Co-host'::text as role,
      (e.organizer_id = auth.uid()) as viewer_can_edit
    from public.event_cohosts cohost
    join public.events e on e.id = cohost.event_id
    join public.profiles p on p.id = cohost.profile_id
    where cohost.event_id = p_event_id
  ) members
  order by members.role desc, members.display_name, members.profile_id;
end;
$$;

create function public.set_event_cohost(
  p_event_id uuid,
  p_username text,
  p_enabled boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid;
  event_owner_id uuid;
  target_username text := lower(trim(leading '@' from trim(p_username)));
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(target_username) not between 3 and 32 then
    raise exception using errcode = '22023', message = 'invalid_cohost';
  end if;

  select e.organizer_id into event_owner_id
  from public.events e
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status in ('draft', 'published') and e.end_at > pg_catalog.now()
  for update;
  if event_owner_id is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  select p.id into target_profile_id
  from public.profiles p
  where lower(p.username) = target_username;
  if target_profile_id is null then
    raise exception using errcode = 'P0001', message = 'cohost_not_found';
  end if;
  if target_profile_id = event_owner_id then
    raise exception using errcode = '22023', message = 'invalid_cohost';
  end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = event_owner_id and b.blocked_id = target_profile_id)
       or (b.blocker_id = target_profile_id and b.blocked_id = event_owner_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  if p_enabled then
    if (
      select pg_catalog.count(*) from public.event_cohosts cohost
      where cohost.event_id = p_event_id
        and cohost.profile_id <> target_profile_id
    ) >= 5 then
      raise exception using errcode = 'P0001', message = 'cohost_limit_reached';
    end if;
    insert into public.event_cohosts (event_id, profile_id, invited_by)
    values (p_event_id, target_profile_id, auth.uid())
    on conflict do nothing;
  else
    delete from public.event_cohosts cohost
    where cohost.event_id = p_event_id
      and cohost.profile_id = target_profile_id;
  end if;
  return target_profile_id;
end;
$$;

create function public._remove_blocked_event_cohosts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.event_cohosts cohost
  using public.events e
  where e.id = cohost.event_id
    and (
      (e.organizer_id = new.blocker_id and cohost.profile_id = new.blocked_id)
      or (e.organizer_id = new.blocked_id and cohost.profile_id = new.blocker_id)
    );
  return new;
end;
$$;

revoke all on function public._remove_blocked_event_cohosts()
from public, anon, authenticated;

create trigger blocks_remove_event_cohosts
after insert on public.blocks
for each row execute function public._remove_blocked_event_cohosts();

create function public.create_event_v3(
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
  p_what_to_bring text,
  p_status text,
  p_visibility text,
  p_repeat_interval text,
  p_repeat_count integer
)
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_ids uuid[] := '{}'::uuid[];
  created_id uuid;
  recurrence_id uuid;
  occurrence integer;
  occurrence_start timestamptz;
  occurrence_end timestamptz;
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
    or char_length(trim(coalesce(p_what_to_bring, ''))) > 500
    or p_status not in ('draft', 'published')
    or p_visibility not in ('public', 'unlisted')
    or p_repeat_interval not in ('none', 'weekly', 'monthly')
    or p_repeat_count not between 1 and 12
    or (p_repeat_interval = 'none' and p_repeat_count <> 1)
    or (p_repeat_interval <> 'none' and p_repeat_count < 2)
    or (p_status = 'draft' and (p_repeat_interval <> 'none' or p_repeat_count <> 1)) then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  if p_repeat_count > 1 then
    recurrence_id := pg_catalog.gen_random_uuid();
  end if;

  for occurrence in 0..(p_repeat_count - 1) loop
    if p_repeat_interval = 'weekly' then
      occurrence_start := p_start_at + (occurrence * interval '7 days');
      occurrence_end := p_end_at + (occurrence * interval '7 days');
    elsif p_repeat_interval = 'monthly' then
      occurrence_start := p_start_at + pg_catalog.make_interval(months => occurrence);
      occurrence_end := p_end_at + pg_catalog.make_interval(months => occurrence);
    else
      occurrence_start := p_start_at;
      occurrence_end := p_end_at;
    end if;

    insert into public.events (
      organizer_id, title, description, category, venue_name, address, location,
      start_at, end_at, max_participants, status, visibility, series_id,
      beginner_friendly, wheelchair_accessible, event_setting, event_language,
      age_guidance, what_to_bring
    ) values (
      auth.uid(), trim(p_title), trim(p_description), trim(p_category),
      trim(p_venue_name), trim(p_address),
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude), 4326
      )::extensions.geography,
      occurrence_start, occurrence_end, p_max_participants, p_status,
      p_visibility, recurrence_id, p_beginner_friendly,
      p_wheelchair_accessible, p_event_setting,
      trim(coalesce(p_event_language, '')), p_age_guidance,
      trim(coalesce(p_what_to_bring, ''))
    ) returning id into created_id;

    insert into public.event_rsvps (
      event_id, user_id, status, visible_to_attendees, reconfirmed_at
    ) values (
      created_id, auth.uid(), 'joined', true, pg_catalog.now()
    );
    created_ids := pg_catalog.array_append(created_ids, created_id);
  end loop;

  return created_ids;
end;
$$;

create function public.update_own_event_v3(
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
  p_what_to_bring text,
  p_status text,
  p_visibility text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  joined_total integer;
  previous_start timestamptz;
  previous_status text;
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
    or char_length(trim(coalesce(p_what_to_bring, ''))) > 500
    or p_status not in ('draft', 'published')
    or p_visibility not in ('public', 'unlisted') then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_event_id::text, 0)
  );
  select e.start_at, e.status into previous_start, previous_status
  from public.events e
  where e.id = p_event_id
    and public._can_manage_event(e.id, auth.uid())
    and e.status in ('draft', 'published') and e.start_at > pg_catalog.now()
  for update;
  if previous_start is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if previous_status = 'published' and p_status = 'draft' then
    raise exception using errcode = '22023', message = 'event_validation';
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
    max_participants = p_max_participants, status = p_status,
    visibility = p_visibility, beginner_friendly = p_beginner_friendly,
    wheelchair_accessible = p_wheelchair_accessible,
    event_setting = p_event_setting,
    event_language = trim(coalesce(p_event_language, '')),
    age_guidance = p_age_guidance,
    what_to_bring = trim(coalesce(p_what_to_bring, ''))
  where e.id = p_event_id;

  update public.event_reminders reminder set
    remind_at = p_start_at - (previous_start - reminder.remind_at)
  where reminder.event_id = p_event_id and reminder.remind_at < previous_start;

  if previous_status = 'published' then
    insert into public.member_notifications (user_id, event_id, kind, title, body)
    select recipients.user_id, p_event_id, 'event_updated', 'Event updated',
      trim(p_title) || ' has new details. Please review your plan.'
    from (
      select r.user_id from public.event_rsvps r
      where r.event_id = p_event_id and r.status in ('joined', 'tentative', 'waitlisted')
      union
      select s.user_id from public.event_saves s where s.event_id = p_event_id
    ) recipients
    where recipients.user_id <> auth.uid()
    on conflict do nothing;
  end if;

  while joined_total < p_max_participants loop
    exit when public._promote_event_waitlist(p_event_id) is null;
    joined_total := joined_total + 1;
  end loop;
  return true;
end;
$$;

create function public.get_event_details_v3(
  p_event_id uuid,
  p_via_invite boolean default false
)
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
  reconfirmation_deadline_at timestamptz, viewer_reconfirmed_at timestamptz,
  event_visibility text, event_series_id uuid
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
    public._can_manage_event(e.id, auth.uid()),
    e.beginner_friendly, e.wheelchair_accessible, e.event_setting,
    e.event_language, e.age_guidance, e.what_to_bring,
    coalesce(r.visible_to_attendees, false),
    coalesce(preference.discussion_enabled, true),
    e.reconfirmation_deadline_at, r.reconfirmed_at, e.visibility, e.series_id
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
      (e.status = 'published' and (e.visibility = 'public' or p_via_invite))
      or public._can_manage_event(e.id, auth.uid())
      or r.user_id is not null
      or s.user_id is not null
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = e.organizer_id)
    );
$$;

create function public.list_my_events_v2(p_filter text default 'going')
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
  reconfirmation_deadline_at timestamptz, viewer_reconfirmed_at timestamptz,
  event_visibility text, event_series_id uuid
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
  if p_filter not in ('going', 'tentative', 'hosting', 'drafts', 'past', 'saved') then
    raise exception using errcode = '22023', message = 'invalid_event_filter';
  end if;

  return query
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
    public._can_manage_event(e.id, auth.uid()),
    e.beginner_friendly, e.wheelchair_accessible, e.event_setting,
    e.event_language, e.age_guidance, e.what_to_bring,
    coalesce(r.visible_to_attendees, false),
    coalesce(preference.discussion_enabled, true),
    e.reconfirmation_deadline_at, r.reconfirmed_at, e.visibility, e.series_id
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
  where case p_filter
    when 'going' then e.status = 'published' and e.end_at >= pg_catalog.now()
      and r.status = 'joined'
    when 'tentative' then e.status = 'published' and e.end_at >= pg_catalog.now()
      and r.status in ('tentative', 'waitlisted')
    when 'hosting' then e.status in ('published', 'cancelled')
      and e.end_at >= pg_catalog.now()
      and public._can_manage_event(e.id, auth.uid())
    when 'drafts' then e.status = 'draft'
      and public._can_manage_event(e.id, auth.uid())
    when 'saved' then e.status = 'published' and e.end_at >= pg_catalog.now()
      and s.user_id is not null
    when 'past' then e.status <> 'draft' and e.end_at < pg_catalog.now() and (
      e.organizer_id = auth.uid()
      or r.status in ('joined', 'tentative', 'attended', 'no_show')
    )
  end
  order by
    case when p_filter = 'past' then e.end_at end desc,
    case when p_filter <> 'past' then e.start_at end,
    e.id;
end;
$$;

create function public.cancel_managed_event(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare event_title text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.events e set status = 'cancelled'
  where e.id = p_event_id
    and public._can_manage_event(e.id, auth.uid())
    and e.status = 'published' and e.start_at > pg_catalog.now()
  returning e.title into event_title;
  if event_title is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  insert into public.member_notifications (user_id, event_id, kind, title, body)
  select recipients.user_id, p_event_id, 'event_cancelled', 'Event cancelled',
    event_title || ' has been cancelled by a host.'
  from (
    select r.user_id from public.event_rsvps r
    where r.event_id = p_event_id and r.status in ('joined', 'tentative', 'waitlisted')
    union
    select s.user_id from public.event_saves s where s.event_id = p_event_id
  ) recipients
  where recipients.user_id <> auth.uid()
  on conflict do nothing;
  return true;
end;
$$;

create function public.create_event_announcement_v2(p_event_id uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare announcement_id uuid; event_title text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_body)) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'announcement_validation';
  end if;
  select e.title into event_title from public.events e
  where e.id = p_event_id
    and public._can_manage_event(e.id, auth.uid())
    and e.status = 'published';
  if event_title is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if (
    select pg_catalog.count(*) from public.event_announcements a
    where a.event_id = p_event_id
      and a.created_at > pg_catalog.now() - interval '1 hour'
  ) >= 3 then
    raise exception using errcode = 'P0001', message = 'announcement_rate_limited';
  end if;
  insert into public.event_announcements (event_id, author_id, body)
  values (p_event_id, auth.uid(), trim(p_body)) returning id into announcement_id;
  insert into public.member_notifications (
    user_id, event_id, source_id, kind, title, body
  )
  select r.user_id, p_event_id, announcement_id, 'announcement',
    'Update from a host', event_title || ': ' || trim(p_body)
  from public.event_rsvps r
  where r.event_id = p_event_id
    and r.status in ('joined', 'tentative', 'waitlisted')
    and r.user_id <> auth.uid()
  on conflict do nothing;
  return announcement_id;
end;
$$;

create function public.request_event_rsvp_reconfirmation_v2(p_event_id uuid)
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
  where e.id = p_event_id
    and public._can_manage_event(e.id, auth.uid())
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
    and r.user_id <> auth.uid()
  on conflict do nothing;
  return deadline;
end;
$$;

create function public.list_event_attendees_v2(p_event_id uuid)
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
  viewer_is_host := public._can_manage_event(p_event_id, auth.uid());
  if not viewer_is_host and not exists (
    select 1 from public.event_rsvps mine
    where mine.event_id = p_event_id and mine.user_id = auth.uid()
      and mine.status in ('joined', 'tentative', 'waitlisted', 'attended')
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

create function public.list_event_feedback_v2(p_event_id uuid)
returns table (
  attended boolean, rating integer, comment text, created_at timestamptz
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
  if not public._can_manage_event(p_event_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return query
  select f.attended, f.rating, f.comment, f.created_at
  from public.event_feedback f
  where f.event_id = p_event_id
  order by f.created_at desc;
end;
$$;

drop trigger if exists events_notify_published_event on public.events;
create trigger events_notify_published_event
after update of status, visibility on public.events
for each row
when (
  new.status = 'published' and new.visibility = 'public'
  and (old.status <> 'published' or old.visibility <> 'public')
)
execute function public._notify_for_new_event();

revoke all on function public.create_event_v3(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text,
  text, text, text, text, integer
) from public, anon;
revoke all on function public.update_own_event_v3(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text,
  text, text, text
) from public, anon;
revoke all on function public.get_event_details_v3(uuid, boolean) from public, anon;
revoke all on function public.list_my_events_v2(text) from public, anon;
revoke all on function public.list_event_cohosts(uuid) from public, anon;
revoke all on function public.set_event_cohost(uuid, text, boolean) from public, anon;
revoke all on function public.cancel_managed_event(uuid) from public, anon;
revoke all on function public.create_event_announcement_v2(uuid, text) from public, anon;
revoke all on function public.request_event_rsvp_reconfirmation_v2(uuid) from public, anon;
revoke all on function public.list_event_attendees_v2(uuid) from public, anon;
revoke all on function public.list_event_feedback_v2(uuid) from public, anon;

grant execute on function public.create_event_v3(
  text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text,
  text, text, text, text, integer
) to authenticated;
grant execute on function public.update_own_event_v3(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer, boolean, boolean, text, text, text,
  text, text, text
) to authenticated;
grant execute on function public.get_event_details_v3(uuid, boolean) to authenticated;
grant execute on function public.list_my_events_v2(text) to authenticated;
grant execute on function public.list_event_cohosts(uuid) to authenticated;
grant execute on function public.set_event_cohost(uuid, text, boolean) to authenticated;
grant execute on function public.cancel_managed_event(uuid) to authenticated;
grant execute on function public.create_event_announcement_v2(uuid, text) to authenticated;
grant execute on function public.request_event_rsvp_reconfirmation_v2(uuid) to authenticated;
grant execute on function public.list_event_attendees_v2(uuid) to authenticated;
grant execute on function public.list_event_feedback_v2(uuid) to authenticated;

comment on function public.create_event_v3 is
  'Creates one draft or an atomic bounded series of published events.';
comment on function public.update_own_event_v3 is
  'Updates an owned draft or upcoming event and can publish a draft.';
comment on function public.get_event_details_v3 is
  'Returns event details, allowing opaque invite-link access to published unlisted events.';
comment on function public.list_my_events_v2 is
  'Lists member plans including owner-only drafts and event visibility.';
