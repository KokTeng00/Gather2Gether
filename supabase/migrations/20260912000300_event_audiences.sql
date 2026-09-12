-- Event audiences are checked at read time and resolved to stable profile IDs.
alter table public.events drop constraint events_visibility_check;
alter table public.events add constraint events_visibility_check check (
  visibility in ('public', 'unlisted', 'followers', 'following', 'selected')
);
alter table public.events add constraint restricted_event_preview check (
  visibility in ('public', 'unlisted') or not invite_preview_enabled
);

create table public.event_audience_members (
  event_id uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (event_id, profile_id)
);
create index event_audience_members_profile_idx on public.event_audience_members(profile_id, event_id);
alter table public.event_audience_members enable row level security;
revoke all on public.event_audience_members from public, anon, authenticated;

-- Internal helper: callers still enforce event status and their own action rules.
create function public._event_audience_allows(p_event_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_user_id is not null and exists (
    select 1 from public.events e where e.id = p_event_id
      and not exists (select 1 from public.blocks b where
        (b.blocker_id = p_user_id and b.blocked_id = e.organizer_id) or
        (b.blocked_id = p_user_id and b.blocker_id = e.organizer_id))
      and (public._can_manage_event(e.id, p_user_id)
        or e.visibility in ('public', 'unlisted')
        or (e.visibility = 'followers' and exists (select 1 from public.profile_follows f
          where f.follower_id = p_user_id and f.followed_id = e.organizer_id))
        or (e.visibility = 'following' and exists (select 1 from public.profile_follows f
          where f.follower_id = e.organizer_id and f.followed_id = p_user_id))
        or (e.visibility = 'selected' and exists (select 1 from public.event_audience_members a
          where a.event_id = e.id and a.profile_id = p_user_id)))
  );
$$;
revoke all on function public._event_audience_allows(uuid,uuid) from public,anon,authenticated;

-- Fixed viewer identity makes this safe for use by RLS and direct authenticated calls.
create function public.can_view_event(p_event_id uuid, p_via_invite boolean default false)
returns boolean language sql stable security definer set search_path = '' as $$
  select public._event_audience_allows(p_event_id, auth.uid()) and exists (
    select 1 from public.events e where e.id = p_event_id and (
      public._can_manage_event(e.id, auth.uid())
      or (e.status <> 'draft' and (
        (e.status = 'published' and (e.visibility <> 'unlisted' or p_via_invite))
        or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
        or exists (select 1 from public.event_saves s where s.event_id = e.id and s.user_id = auth.uid())
      ))
    )
  );
$$;
revoke all on function public.can_view_event(uuid,boolean) from public,anon;
grant execute on function public.can_view_event(uuid,boolean) to authenticated;

drop policy events_select_visible on public.events;
create policy events_select_visible on public.events for select to authenticated
  using (public.can_view_event(id, false));
-- Event writes go through validated RPCs; direct writes could bypass audience validation.
revoke update on public.events from authenticated;

create or replace function public.create_event_v3(
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
    or p_visibility not in ('public', 'unlisted', 'followers', 'following', 'selected')
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

create or replace function public.update_own_event_v3(
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
    or p_visibility not in ('public', 'unlisted', 'followers', 'following', 'selected') then
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

create or replace function public.save_event_plan(p_event_id uuid,p_scope text,p_event jsonb,p_details jsonb,p_poll_post_id uuid default null,p_poll_option_id uuid default null)
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[];
  audience_names text[];
  audience_ids uuid[];
  audience_owner uuid := auth.uid();
  target_id uuid;
  anchor public.events%rowtype;
  candidate record;
  option_row public.forum_poll_options%rowtype;
  poll_row public.forum_planning_polls%rowtype;
  meeting_lat double precision := (p_details->>'meeting_latitude')::double precision;
  meeting_lon double precision := (p_details->>'meeting_longitude')::double precision;
  image_key text := p_details->>'meeting_image_key';
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if p_scope is null or p_scope not in ('this','future','all') or jsonb_typeof(p_details) is distinct from 'object'
    or (meeting_lat is null) <> (meeting_lon is null) or meeting_lat not between -90 and 90 or meeting_lon not between -180 and 180
    or char_length(coalesce(p_details->>'meeting_instructions',''))>500 or char_length(coalesce(p_details->>'preview_area',''))>120
    or coalesce((p_details->>'timezone_offset_minutes')::integer,0) not between -840 and 840 then
    raise exception using errcode='22023',message='event_validation';
  end if;
  if p_event_id is not null then
    select organizer_id into audience_owner from public.events
      where id = p_event_id and public._can_manage_event(id, auth.uid());
    if not found then raise exception using errcode='42501',message='permission_denied'; end if;
  end if;
  if jsonb_typeof(coalesce(p_details->'audience_usernames','[]'::jsonb)) is distinct from 'array' then
    raise exception using errcode='22023',message='audience_validation';
  end if;
  if jsonb_array_length(coalesce(p_details->'audience_usernames','[]'::jsonb)) > 50
    or exists (select 1 from jsonb_array_elements(coalesce(p_details->'audience_usernames','[]'::jsonb)) n
      where jsonb_typeof(n) <> 'string') then
    raise exception using errcode='22023',message='audience_validation';
  end if;
  select coalesce(array_agg(distinct lower(regexp_replace(trim(n), '^@', ''))), '{}'::text[])
    into audience_names from jsonb_array_elements_text(coalesce(p_details->'audience_usernames','[]'::jsonb)) n;
  if exists (select 1 from unnest(audience_names) n where n !~ '^[a-z0-9_]{3,30}$')
    or ((p_event->>'p_visibility' = 'selected') is distinct from (cardinality(audience_names) > 0))
    or (p_event->>'p_visibility' not in ('public','unlisted')
      and coalesce((p_details->>'invite_preview_enabled')::boolean, false)) then
    raise exception using errcode='22023',message='audience_validation';
  end if;
  select coalesce(array_agg(p.id), '{}'::uuid[]) into audience_ids from public.profiles p
    where lower(p.username) = any(audience_names) and p.id <> audience_owner
      and not exists (select 1 from public.blocks b where
        (b.blocker_id = audience_owner and b.blocked_id = p.id) or
        (b.blocked_id = audience_owner and b.blocker_id = p.id));
  if cardinality(audience_ids) <> cardinality(audience_names) then
    raise exception using errcode='22023',message='audience_not_found';
  end if;
  if image_key is not null and image_key !~ ('^events/' || auth.uid()::text || '/[0-9a-f-]{36}\.jpg$') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if (p_poll_post_id is null) <> (p_poll_option_id is null) or (p_poll_post_id is not null and p_event_id is not null) then
    raise exception using errcode='22023',message='poll_validation';
  end if;
  if p_poll_post_id is not null then
    -- The poll row serializes conversion, so two taps cannot create two events.
    select * into poll_row from public.forum_planning_polls where post_id=p_poll_post_id for update;
    if not found or not exists(select 1 from public.forum_posts where id=p_poll_post_id and author_id=auth.uid() and status='active') then
      raise exception using errcode='42501',message='permission_denied';
    end if;
    if poll_row.closed_at is not null then raise exception using errcode='P0001',message='poll_closed'; end if;
    select * into option_row from public.forum_poll_options where post_id=p_poll_post_id and id=p_poll_option_id;
    if not found or option_row.start_at <= now() or (p_event->>'p_start_at')::timestamptz is distinct from option_row.start_at
      or (p_event->>'p_end_at')::timestamptz is distinct from option_row.end_at
      or p_event->>'p_status' is distinct from 'published' or p_event->>'p_visibility' is distinct from 'public'
      or (p_event->>'p_repeat_count')::integer is distinct from 1 then
      raise exception using errcode='22023',message='poll_validation';
    end if;
  end if;
  if p_event_id is null then
    ids := public.create_event_v3(
      (p_event->>'p_title')::text,
      (p_event->>'p_description')::text,
      (p_event->>'p_category')::text,
      (p_event->>'p_venue_name')::text,
      (p_event->>'p_address')::text,
      (p_event->>'p_latitude')::double precision,
      (p_event->>'p_longitude')::double precision,
      (p_event->>'p_start_at')::timestamptz,
      (p_event->>'p_end_at')::timestamptz,
      (p_event->>'p_max_participants')::integer,
      (p_event->>'p_beginner_friendly')::boolean,
      (p_event->>'p_wheelchair_accessible')::boolean,
      (p_event->>'p_event_setting')::text,
      (p_event->>'p_event_language')::text,
      (p_event->>'p_age_guidance')::text,
      (p_event->>'p_what_to_bring')::text,
      (p_event->>'p_status')::text,
      (p_event->>'p_visibility')::text,
      (p_event->>'p_repeat_interval')::text,
      (p_event->>'p_repeat_count')::integer);
  else
    select * into anchor from public.events where id=p_event_id and public._can_manage_event(id,auth.uid());
    if not found then raise exception using errcode='42501',message='permission_denied'; end if;
    select array_agg(e.id order by e.start_at,e.id) into ids from public.events e
    where e.status in ('draft','published') and e.start_at>now() and public._can_manage_event(e.id,auth.uid())
      and (e.id=p_event_id or (p_scope<>'this' and anchor.series_id is not null and e.series_id=anchor.series_id and (p_scope='all' or e.start_at>=anchor.start_at)));
    if coalesce(cardinality(ids),0)=0 then raise exception using errcode='P0001',message='event_started'; end if;
  end if;
  foreach target_id in array ids loop
    perform pg_advisory_xact_lock(hashtextextended(target_id::text,0));
    delete from public.event_audience_members where event_id = target_id;
    insert into public.event_audience_members(event_id, profile_id)
      select target_id, profile_id from unnest(audience_ids) profile_id;
    update public.events set
      meeting_instructions=coalesce(p_details->>'meeting_instructions',''),
      meeting_latitude=meeting_lat,meeting_longitude=meeting_lon,
      meeting_image_key=case when p_details ? 'meeting_image_key' then image_key else meeting_image_key end,
      allow_guest=coalesce((p_details->>'allow_guest')::boolean,false),
      invite_preview_enabled=case when visibility in ('public','unlisted') then coalesce((p_details->>'invite_preview_enabled')::boolean,false) else false end,
      preview_area=coalesce(p_details->>'preview_area',''),
      timezone_offset_minutes=coalesce((p_details->>'timezone_offset_minutes')::integer,0)
    where id=target_id;
  end loop;
  if p_event_id is not null then
    perform public.update_event_series_v1(p_event_id,p_scope,
      (p_event->>'p_title')::text,
      (p_event->>'p_description')::text,
      (p_event->>'p_category')::text,
      (p_event->>'p_venue_name')::text,
      (p_event->>'p_address')::text,
      (p_event->>'p_latitude')::double precision,
      (p_event->>'p_longitude')::double precision,
      (p_event->>'p_start_at')::timestamptz,
      (p_event->>'p_end_at')::timestamptz,
      (p_event->>'p_max_participants')::integer,
      (p_event->>'p_beginner_friendly')::boolean,
      (p_event->>'p_wheelchair_accessible')::boolean,
      (p_event->>'p_event_setting')::text,
      (p_event->>'p_event_language')::text,
      (p_event->>'p_age_guidance')::text,
      (p_event->>'p_what_to_bring')::text,
      (p_event->>'p_status')::text,
      (p_event->>'p_visibility')::text);
  end if;
  update public.events set invite_preview_enabled=coalesce((p_details->>'invite_preview_enabled')::boolean,false) where id=any(ids);
  if image_key is not null then
    insert into public.event_meeting_images(image_key,owner_id) values(image_key,auth.uid()) on conflict do nothing;
  end if;
  if p_poll_post_id is not null then
    update public.forum_planning_polls set event_id=ids[1],closed_at=now() where post_id=p_poll_post_id;
    update public.forum_posts set last_activity_at=now() where id=p_poll_post_id;
  end if;
  return ids;
end;
$$;

create or replace function public.get_event_details_v3(
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
    and public.can_view_event(e.id, p_via_invite)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = e.organizer_id)
    );
$$;

create or replace function public.get_event_plan(p_event_id uuid,p_via_invite boolean default false)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object(
    'joined_count',public._event_places(e.id),'guest_count',coalesce(r.guest_count,0),
    'allow_guest',e.allow_guest,'meeting_instructions',e.meeting_instructions,
    'meeting_latitude',e.meeting_latitude,'meeting_longitude',e.meeting_longitude,
    'has_meeting_image',e.meeting_image_key is not null,
    'invite_preview_enabled',e.invite_preview_enabled,'preview_area',e.preview_area,
    'timezone_offset_minutes',e.timezone_offset_minutes,
    'audience_usernames',case when public._can_manage_event(e.id,auth.uid()) then
      (select coalesce(jsonb_agg(p.username order by p.username),'[]'::jsonb)
       from public.event_audience_members a join public.profiles p on p.id=a.profile_id
       where a.event_id=e.id) else '[]'::jsonb end)
  from public.get_event_details_v3(p_event_id,p_via_invite) d
  join public.events e on e.id=d.id
  left join public.event_rsvps r on r.event_id=e.id and r.user_id=auth.uid();
$$;

create or replace function public.get_event_invite_preview(p_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('title',e.title,'description',e.description,'category',e.category,
    'start_at',e.start_at,'end_at',e.end_at,'area',e.preview_area,
    'timezone_offset_minutes',e.timezone_offset_minutes,'cancelled',e.status='cancelled')
  from public.events e where e.id=p_event_id and e.invite_preview_enabled
    and e.visibility in ('public','unlisted')
    and e.status in ('published','cancelled') and e.end_at>now();
$$;

create or replace function public.list_event_conflicts(p_event_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare target public.events%rowtype;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if public.get_event_plan(p_event_id,true) is null then raise exception using errcode='42501',message='permission_denied'; end if;
  select * into target from public.events where id=p_event_id;
  return query select jsonb_build_object('id',e.id,'title',e.title,'start_at',e.start_at,'end_at',e.end_at)
  from public.events e where public.can_view_event(e.id,false) and e.id<>p_event_id and e.status='published' and e.end_at>now()
    and e.start_at<target.end_at and e.end_at>target.start_at
    and (public._can_manage_event(e.id,auth.uid()) or exists(select 1 from public.event_rsvps r where r.event_id=e.id and r.user_id=auth.uid() and r.status='joined'))
  order by e.start_at,e.id limit 20;
end;
$$;

create or replace function public._rank_event_recommendations(
  p_latitude double precision, p_longitude double precision,
  p_radius_km double precision, p_filters jsonb default '{}'
)
returns table (id uuid, distance_meters double precision, score double precision, reason text)
language sql stable security definer set search_path = '' as $$
  with owner as materialized (
    select p.id, coalesce(r.enabled, true) enabled,
      case when coalesce(r.enabled, true) then p.interests else '{}'::text[] end interests,
      coalesce(r.hidden_categories, '{}'::text[]) hidden_categories,
      extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography origin,
      nullif(trim(p_filters->>'interest'), '') search_text,
      (p_filters->>'query_embedding')::extensions.vector(384) query_embedding,
      coalesce((p_filters->>'timezone_offset_minutes')::integer, 0) offset_minutes
    from public.profiles p left join public.recommendation_preferences r on r.user_id = p.id
    where p.id = auth.uid() and p_latitude between -90 and 90
      and p_longitude between -180 and 180 and p_radius_km between 1 and 100
  ), history as materialized (
    select * from public._recommendation_history('event')
  ), categories as (
    select lower(h.category) category, sum(h.weight) / greatest(8.0, (select sum(weight) from history)) affinity
    from history h group by lower(h.category)
  ), creators as (
    select h.creator_id, sum(h.weight) / greatest(8.0, (select sum(weight) from history)) affinity
    from history h group by h.creator_id
  ), eligible as materialized (
    select e.*, o.enabled, o.search_text, o.query_embedding,
      extensions.st_distance(e.location, o.origin) distance_meters,
      public._recommendation_interest_match(o.interests, e.category, e.search_document) matched_interest,
      coalesce(c.affinity, 0.0) category_affinity,
      coalesce(a.affinity, 0.0) creator_affinity,
      coalesce((select max(greatest(0.0, 1 - (e.embedding operator(extensions.<=>) h.embedding))
        * least(1.0, h.weight / 8.0)) from history h where h.embedding is not null), 0.0) semantic_affinity,
      r.status rsvp_status,
      exists(select 1 from public.profile_follows f
        where f.follower_id = o.id and f.followed_id = e.organizer_id) follows_creator
    from public.events e cross join owner o
    left join categories c on c.category = lower(e.category)
    left join creators a on a.creator_id = e.organizer_id
    left join public.event_rsvps r on r.event_id = e.id and r.user_id = o.id
    where e.status = 'published' and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid())) and e.start_at > now()
      and extensions.st_dwithin(e.location, o.origin, p_radius_km * 1000)
      and (nullif(p_filters->>'start_from', '') is null or e.start_at >= (p_filters->>'start_from')::timestamptz)
      and (nullif(p_filters->>'start_before', '') is null or e.start_at < (p_filters->>'start_before')::timestamptz)
      and (nullif(p_filters->>'category', '') is null or e.category = p_filters->>'category')
      and (not coalesce((p_filters->>'spots_only')::boolean, false) or public._event_places(e.id) < e.max_participants)
      and (not coalesce((p_filters->>'following_only')::boolean, false) or exists (
        select 1 from public.profile_follows f where f.follower_id = o.id and f.followed_id = e.organizer_id))
      and (not coalesce((p_filters->>'beginner_friendly_only')::boolean, false) or e.beginner_friendly)
      and (not coalesce((p_filters->>'wheelchair_accessible_only')::boolean, false) or e.wheelchair_accessible)
      and (coalesce(p_filters->>'event_setting', 'any') = 'any' or e.event_setting = p_filters->>'event_setting')
      and (nullif(p_filters->>'event_language', '') is null or lower(e.event_language) = lower(p_filters->>'event_language'))
      and (coalesce(p_filters->>'age_guidance', 'any') = 'any' or e.age_guidance = p_filters->>'age_guidance')
      and (coalesce(p_filters->>'time_filter', 'any') = 'any' or case p_filters->>'time_filter'
        when 'morning' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 5
          and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) < 12
        when 'afternoon' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 12
          and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) < 17
        when 'evening' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins => o.offset_minutes)) >= 17
        else false end)
      and (o.search_text is null or (o.query_embedding is not null and e.embedding is not null)
        or e.search_document @@ websearch_to_tsquery('english', o.search_text)
        or strpos(lower(e.title || ' ' || e.category || ' ' || e.description), lower(o.search_text)) > 0)
      and not (e.category = any(o.hidden_categories))
      and not exists (select 1 from public.hidden_recommendation_content h
        where h.user_id = o.id and h.content_kind = 'event' and h.content_id = e.id)
      and not exists (select 1 from public.blocks b
        where (b.blocker_id = o.id and b.blocked_id = e.organizer_id)
          or (b.blocked_id = o.id and b.blocker_id = e.organizer_id))
  ), candidates as materialized (
    select e.* from eligible e
    -- Include interest matches before limiting; nearby unrelated items cannot
    -- crowd a new member's selected topics out of the candidate pool.
    order by case when not e.enabled and e.search_text is null then e.start_at end,
      case when e.search_text is not null then
      (case when e.search_document @@ websearch_to_tsquery('english', e.search_text) then 1.0 else 0.0 end
       + coalesce(1 - (e.embedding operator(extensions.<=>) e.query_embedding), 0))
      else (case when e.matched_interest is not null then 4.0 else 0.0 end
       + 3.0 * e.category_affinity + 1.5 * e.semantic_affinity
       + 1.0 / (1.0 + e.distance_meters / 5000.0)) end desc,
      e.start_at, e.id
    limit 500
  ), scored as (
    select c.id, c.distance_meters, c.start_at,
      case when c.search_text is not null then
        (case when c.search_document @@ websearch_to_tsquery('english', c.search_text) then 1.0 else 0.0 end
          + coalesce(1 - (c.embedding operator(extensions.<=>) c.query_embedding), 0))
      else
        (case when c.matched_interest is not null then 4.0 else 0.0 end)
        + 3.0 * c.category_affinity + 0.5 * c.creator_affinity
        + c.semantic_affinity * 1.5
        + case when c.enabled and c.follows_creator then 0.75 else 0.0 end
        + 1.0 / (1.0 + c.distance_meters / 5000.0)
        + 1.0 / (1.0 + extract(epoch from (c.start_at - now())) / 604800.0)
        - case when c.enabled and (c.rsvp_status in ('joined', 'attended') or c.organizer_id = auth.uid()) then 4.0 else 0.0 end
        - case when c.enabled and public._event_places(c.id) >= c.max_participants then 1.0 else 0.0 end
      end::double precision score,
      case when c.search_text is not null then 'Matches your search'
        when not c.enabled then 'Near your chosen area'
        when c.matched_interest is not null then 'Matches your interest in ' || c.matched_interest
        when c.category_affinity >= 0.4 then 'Based on your recent event choices'
        when c.follows_creator then 'From an organizer you follow'
        else 'Upcoming near you' end reason,
      c.enabled, c.search_text
    from candidates c
  )
  select s.id, s.distance_meters, s.score, s.reason from scored s
  order by case when s.enabled or s.search_text is not null then s.score end desc,
    s.start_at, s.distance_meters, s.id
  limit 100;
$$;

create or replace function public.filter_event_ids_by_details(
  p_event_ids uuid[],
  p_beginner_friendly_only boolean,
  p_wheelchair_accessible_only boolean,
  p_event_setting text,
  p_event_language text,
  p_age_guidance text
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare matching_ids uuid[];
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if coalesce(pg_catalog.array_length(p_event_ids, 1), 0) > 100
    or p_event_setting not in ('any', 'indoor', 'outdoor', 'mixed')
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_event_language, ''))) > 80
    or p_age_guidance not in ('any', 'all_ages', 'families', 'teens', 'adults') then
    raise exception using errcode = '22023', message = 'invalid_event_filters';
  end if;

  select coalesce(
    pg_catalog.array_agg(candidate.id order by candidate.ordinality),
    array[]::uuid[]
  ) into matching_ids
  from pg_catalog.unnest(p_event_ids) with ordinality as candidate(id, ordinality)
  join public.events e on e.id = candidate.id
  where e.status = 'published'
    and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
    and e.start_at > pg_catalog.now()
    and (not p_beginner_friendly_only or e.beginner_friendly)
    and (not p_wheelchair_accessible_only or e.wheelchair_accessible)
    and (p_event_setting = 'any' or e.event_setting = p_event_setting)
    and (
      nullif(pg_catalog.btrim(coalesce(p_event_language, '')), '') is null
      or pg_catalog.lower(e.event_language) = pg_catalog.lower(pg_catalog.btrim(p_event_language))
    )
    and (p_age_guidance = 'any' or e.age_guidance = p_age_guidance)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocked_id = auth.uid() and b.blocker_id = e.organizer_id)
    );
  return matching_ids;
end;
$$;

create or replace function public.list_followed_nearby_events(
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
    and e.status = 'published' and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
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
    and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
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

create or replace function public.recommend_nearby_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision,
  p_query_embedding extensions.vector(384),
  p_limit integer default 30
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
    profile.display_name,
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
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'joined'
    ),
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'tentative'
    ),
    extensions.st_distance(e.location, origin.point),
    (
      select r.status
      from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
    )
  from public.events e
  join public.profiles profile on profile.id = e.organizer_id
  cross join origin
  where auth.uid() is not null
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and e.embedding is not null
    and e.status = 'published'
    and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
    and e.start_at > pg_catalog.now()
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
  order by
    e.embedding operator(extensions.<=>) p_query_embedding,
    e.location operator(extensions.<->) origin.point,
    e.start_at
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.recommend_nearby_events_v2(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision,
  p_query_embedding extensions.vector(384),
  p_query text,
  p_limit integer default 30
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
  with input as materialized (
    select
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude),
        4326
      )::extensions.geography as origin,
      websearch_to_tsquery(
        'english'::regconfig,
        btrim(left(coalesce(p_query, ''), 240))
      ) as query,
      least(greatest(p_limit * 5, 50), 250) as candidate_limit
  ),
  semantic_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.semantic_distance, ranked.id
      ) as semantic_rank,
      ranked.semantic_distance
    from (
      select
        e.id,
        e.embedding operator(extensions.<=>) p_query_embedding as semantic_distance
      from public.events e
      cross join input
      where auth.uid() is not null
        and p_latitude between -90 and 90
        and p_longitude between -180 and 180
        and e.embedding is not null
        and e.status = 'published'
        and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
        and e.start_at > pg_catalog.now()
        and extensions.st_dwithin(
          e.location,
          input.origin,
          least(greatest(p_radius_km, 1), 100) * 1000
        )
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
            or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
        )
      order by e.embedding operator(extensions.<=>) p_query_embedding
      limit (select candidate_limit from input)
    ) ranked
  ),
  keyword_candidates as materialized (
    select
      ranked.id,
      pg_catalog.row_number() over (
        order by ranked.keyword_rank desc, ranked.id
      ) as keyword_position,
      ranked.keyword_rank
    from (
      select
        e.id,
        pg_catalog.ts_rank_cd(e.search_document, input.query, 32) as keyword_rank
      from public.events e
      cross join input
      where auth.uid() is not null
        and p_latitude between -90 and 90
        and p_longitude between -180 and 180
        and e.status = 'published'
        and (e.visibility <> 'unlisted' and public._event_audience_allows(e.id, auth.uid()))
        and e.start_at > pg_catalog.now()
        and e.search_document @@ input.query
        and extensions.st_dwithin(
          e.location,
          input.origin,
          least(greatest(p_radius_km, 1), 100) * 1000
        )
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
            or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
        )
      order by keyword_rank desc, e.id
      limit (select candidate_limit from input)
    ) ranked
  ),
  candidate_ids as materialized (
    select id from semantic_candidates
    union
    select id from keyword_candidates
  )
  select
    e.id,
    e.organizer_id,
    profile.display_name,
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
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'joined'
    ),
    (
      select pg_catalog.count(*)
      from public.event_rsvps r
      where r.event_id = e.id and r.status = 'tentative'
    ),
    extensions.st_distance(e.location, input.origin),
    (
      select r.status
      from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
    )
  from candidate_ids candidate
  join public.events e on e.id = candidate.id
  join public.profiles profile on profile.id = e.organizer_id
  cross join input
  left join semantic_candidates semantic on semantic.id = e.id
  left join keyword_candidates keyword on keyword.id = e.id
  order by
    coalesce(1.0 / (60.0 + semantic.semantic_rank), 0.0) +
      coalesce(1.0 / (60.0 + keyword.keyword_position), 0.0) desc,
    coalesce(semantic.semantic_distance, 2.0),
    extensions.st_distance(e.location, input.origin),
    e.start_at,
    e.id
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.list_profile_events(
  p_profile_id uuid,
  p_filter text
)
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text,
  description text, category text, venue_name text, address text,
  latitude double precision, longitude double precision,
  start_at timestamptz, end_at timestamptz, max_participants integer,
  joined_count bigint, tentative_count bigint, distance_meters double precision,
  user_rsvp_status text, event_status text, is_saved boolean,
  reminder_at timestamptz, waitlist_position bigint, viewer_is_organizer boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  past_is_public boolean;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_filter not in ('hosting', 'past') then
    raise exception using errcode = '22023', message = 'invalid_profile_event_filter';
  end if;

  select p.show_past_events_public into past_is_public
  from public.profiles p
  where p.id = p_profile_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  -- Owners always retain their own history. Everyone else receives no past
  -- rows unless the owner has explicitly enabled public past activity.
  if p_filter = 'past'
     and current_user_id <> p_profile_id
     and not past_is_public then
    return;
  end if;

  return query
  select
    e.id,
    e.organizer_id,
    organizer.display_name,
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
    (
      select pg_catalog.count(*)
      from public.event_rsvps joined_rsvp
      where joined_rsvp.event_id = e.id and joined_rsvp.status = 'joined'
    ),
    (
      select pg_catalog.count(*)
      from public.event_rsvps tentative_rsvp
      where tentative_rsvp.event_id = e.id and tentative_rsvp.status = 'tentative'
    ),
    0::double precision,
    viewer_rsvp.status,
    e.status,
    viewer_save.user_id is not null,
    viewer_reminder.remind_at,
    case when viewer_rsvp.status = 'waitlisted' then (
      select pg_catalog.count(*)
      from public.event_rsvps queued
      where queued.event_id = e.id and queued.status = 'waitlisted'
        and (queued.created_at, queued.user_id)
          <= (viewer_rsvp.created_at, viewer_rsvp.user_id)
    ) else null end,
    e.organizer_id = current_user_id
  from public.events e
  join public.profiles organizer on organizer.id = e.organizer_id
  left join public.event_rsvps target_rsvp
    on target_rsvp.event_id = e.id and target_rsvp.user_id = p_profile_id
  left join public.event_rsvps viewer_rsvp
    on viewer_rsvp.event_id = e.id and viewer_rsvp.user_id = current_user_id
  left join public.event_saves viewer_save
    on viewer_save.event_id = e.id and viewer_save.user_id = current_user_id
  left join public.event_reminders viewer_reminder
    on viewer_reminder.event_id = e.id and viewer_reminder.user_id = current_user_id
  where
    public.can_view_event(e.id, false)
    and (current_user_id = p_profile_id or e.visibility <> 'unlisted')
    and case p_filter
      when 'hosting' then
        e.organizer_id = p_profile_id
        and e.end_at >= pg_catalog.now()
        and e.status = 'published'
      when 'past' then
        e.end_at < pg_catalog.now()
        and e.status in ('published', 'completed')
        and (
          e.organizer_id = p_profile_id
          or target_rsvp.status = 'attended'
          or (
            current_user_id = p_profile_id
            and target_rsvp.status in ('joined', 'tentative')
          )
        )
    end
  order by
    case when p_filter = 'past' then e.end_at end desc,
    case when p_filter = 'hosting' then e.start_at end,
    e.id;
end;
$$;

create or replace function public.list_my_events(p_filter text default 'going')
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text,
  description text, category text, venue_name text, address text,
  latitude double precision, longitude double precision,
  start_at timestamptz, end_at timestamptz, max_participants integer,
  joined_count bigint, tentative_count bigint, distance_meters double precision,
  user_rsvp_status text, event_status text, is_saved boolean,
  reminder_at timestamptz, waitlist_position bigint, viewer_is_organizer boolean
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
  if p_filter not in ('going', 'tentative', 'hosting', 'past', 'saved') then
    raise exception using errcode = '22023', message = 'invalid_event_filter';
  end if;

  return query
  select
    e.id, e.organizer_id, p.display_name, e.title, e.description, e.category,
    e.venue_name, e.address,
    extensions.st_y(e.location::extensions.geometry),
    extensions.st_x(e.location::extensions.geometry),
    e.start_at, e.end_at, e.max_participants,
    (select count(*) from public.event_rsvps c where c.event_id = e.id and c.status = 'joined'),
    (select count(*) from public.event_rsvps c where c.event_id = e.id and c.status = 'tentative'),
    0::double precision,
    r.status,
    e.status,
    (s.user_id is not null),
    reminder.remind_at,
    case when r.status = 'waitlisted' then (
      select count(*) from public.event_rsvps queued
      where queued.event_id = e.id and queued.status = 'waitlisted'
        and (queued.created_at, queued.user_id) <= (r.created_at, r.user_id)
    ) else null end,
    (e.organizer_id = auth.uid())
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  left join public.event_rsvps r
    on r.event_id = e.id and r.user_id = auth.uid()
  left join public.event_saves s
    on s.event_id = e.id and s.user_id = auth.uid()
  left join public.event_reminders reminder
    on reminder.event_id = e.id and reminder.user_id = auth.uid()
  where public.can_view_event(e.id, false) and case p_filter
      when 'going' then e.end_at >= pg_catalog.now() and r.status = 'joined'
      when 'tentative' then e.end_at >= pg_catalog.now() and r.status in ('tentative', 'waitlisted')
      when 'hosting' then e.end_at >= pg_catalog.now() and e.organizer_id = auth.uid()
      when 'saved' then e.end_at >= pg_catalog.now() and s.user_id is not null
      when 'past' then e.end_at < pg_catalog.now() and (
        e.organizer_id = auth.uid() or r.status in ('joined', 'tentative', 'attended', 'no_show')
      )
    end
  order by
    case when p_filter = 'past' then e.end_at end desc,
    case when p_filter <> 'past' then e.start_at end,
    e.id;
end;
$$;

create or replace function public.list_my_events_v2(p_filter text default 'going')
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
  where public.can_view_event(e.id, false) and case p_filter
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

create or replace function public.get_event_details(p_event_id uuid)
returns table (
  id uuid, organizer_id uuid, organizer_name text, title text,
  description text, category text, venue_name text, address text,
  latitude double precision, longitude double precision,
  start_at timestamptz, end_at timestamptz, max_participants integer,
  joined_count bigint, tentative_count bigint, distance_meters double precision,
  user_rsvp_status text, event_status text, is_saved boolean,
  reminder_at timestamptz, waitlist_position bigint, viewer_is_organizer boolean
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
    (select count(*) from public.event_rsvps c where c.event_id = e.id and c.status = 'joined'),
    (select count(*) from public.event_rsvps c where c.event_id = e.id and c.status = 'tentative'),
    0::double precision,
    r.status, e.status, (s.user_id is not null), reminder.remind_at,
    case when r.status = 'waitlisted' then (
      select count(*) from public.event_rsvps queued
      where queued.event_id = e.id and queued.status = 'waitlisted'
        and (queued.created_at, queued.user_id) <= (r.created_at, r.user_id)
    ) else null end,
    (e.organizer_id = auth.uid())
  from public.events e
  join public.profiles p on p.id = e.organizer_id
  left join public.event_rsvps r on r.event_id = e.id and r.user_id = auth.uid()
  left join public.event_saves s on s.event_id = e.id and s.user_id = auth.uid()
  left join public.event_reminders reminder
    on reminder.event_id = e.id and reminder.user_id = auth.uid()
  where e.id = p_event_id
    and auth.uid() is not null
    and public.can_view_event(e.id, false)
    and (
      (e.status = 'published' and e.visibility <> 'unlisted')
      or e.organizer_id = auth.uid()
      or r.user_id is not null
      or s.user_id is not null
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
         or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
    );
$$;

create or replace function public.get_event_details_v2(p_event_id uuid)
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
    and public.can_view_event(e.id, false)
    and (
      (e.status = 'published' and e.visibility <> 'unlisted')
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

create or replace function public.list_event_announcements(p_event_id uuid)
returns table (id uuid, event_id uuid, body text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, a.event_id, a.body, a.created_at
  from public.event_announcements a
  join public.events e on e.id = a.event_id
  where a.event_id = p_event_id and auth.uid() is not null
    and public.can_view_event(e.id, false)
    and (
      (e.status = 'published' and e.visibility <> 'unlisted')
      or e.organizer_id = auth.uid()
      or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
    )
  order by a.created_at desc limit 20;
$$;

create or replace function public.list_event_discussion(p_event_id uuid)
returns table (
  id uuid, event_id uuid, author_id uuid, author_name text,
  body text, created_at timestamptz, viewer_is_author boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.event_id, m.author_id, p.display_name, m.body, m.created_at,
    (m.author_id = auth.uid())
  from public.event_discussion_messages m
  join public.profiles p on p.id = m.author_id
  join public.events e on e.id = m.event_id
  where m.event_id = p_event_id and m.status = 'visible'
    and auth.uid() is not null
    and public.can_view_event(e.id, false)
    and (
      e.organizer_id = auth.uid()
      or exists (
        select 1 from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
          and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
      )
    )
  order by m.created_at limit 200;
$$;

create or replace function public.set_event_rsvp_with_guest(p_event_id uuid, p_status text, p_guest_count integer)
returns text language plpgsql security definer set search_path = '' as $$
declare
  target public.events%rowtype;
  previous public.event_rsvps%rowtype;
  saved_status text := p_status;
  requested_guests integer := case when p_status = 'cancelled' then 0 else p_guest_count end;
  occupied bigint;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  if p_status is null or p_status not in ('joined','tentative','cancelled') or p_guest_count is null or p_guest_count not between 0 and 1 then
    raise exception using errcode = '22023', message = 'invalid_rsvp_status';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_event_id::text, 0));
  select * into target from public.events where id = p_event_id for update;
  if not found or target.status <> 'published' then raise exception using errcode = 'P0001', message = 'event_unavailable'; end if;
  if p_status <> 'cancelled' and not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_status <> 'cancelled' and target.start_at <= now() then raise exception using errcode = 'P0001', message = 'event_started'; end if;
  if (target.organizer_id = auth.uid() and p_status <> 'joined') or (p_status <> 'cancelled' and exists (
    select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = target.organizer_id)
      or (b.blocked_id = auth.uid() and b.blocker_id = target.organizer_id))) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if requested_guests > 0 and not target.allow_guest then raise exception using errcode = '22023', message = 'guests_not_allowed'; end if;
  select * into previous from public.event_rsvps where event_id = p_event_id and user_id = auth.uid();
  occupied := public._event_places(p_event_id) - case when previous.status in ('joined','attended') then 1 + previous.guest_count else 0 end;
  if p_status = 'joined' and occupied + 1 + requested_guests > target.max_participants then
    -- Adding a guest must never silently give up an existing confirmed place.
    if previous.status in ('joined','attended') then raise exception using errcode = 'P0001', message = 'guest_place_unavailable'; end if;
    saved_status := 'waitlisted';
  elsif p_status = 'joined' and coalesce(previous.status,'') not in ('joined','attended') and exists (
    select 1 from public.event_rsvps r where r.event_id = p_event_id and r.status = 'waitlisted'
      and r.user_id <> auth.uid() and (previous.status is distinct from 'waitlisted' or (r.created_at,r.user_id) < (previous.created_at,previous.user_id))
  ) then
    saved_status := 'waitlisted';
  end if;
  insert into public.event_rsvps (event_id,user_id,status,guest_count) values (p_event_id,auth.uid(),saved_status,requested_guests)
  on conflict (event_id,user_id) do update set status=excluded.status,guest_count=excluded.guest_count,
    created_at=case when excluded.status='waitlisted' and event_rsvps.status is distinct from 'waitlisted' then now() else event_rsvps.created_at end;
  if previous.status in ('joined','attended') or saved_status = 'waitlisted' then
    while public._promote_event_waitlist(p_event_id) is not null loop end loop;
  end if;
  select status into saved_status from public.event_rsvps where event_id=p_event_id and user_id=auth.uid();
  return saved_status;
end;
$$;

create or replace function public._promote_event_waitlist(p_event_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target public.events%rowtype;
  waiting public.event_rsvps%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_event_id::text, 0));
  select * into target from public.events where id = p_event_id for update;
  if not found or target.status <> 'published' or target.start_at <= now() then return null; end if;
  select r.* into waiting from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'waitlisted'
    and public._event_audience_allows(p_event_id, r.user_id)
    and not exists (select 1 from public.blocks b where
      (b.blocker_id = r.user_id and b.blocked_id = target.organizer_id) or
      (b.blocked_id = r.user_id and b.blocker_id = target.organizer_id))
  order by r.created_at, r.user_id limit 1 for update;
  -- Keep a party together, preserving queue order when only one seat opens.
  if not found or public._event_places(p_event_id) + 1 + waiting.guest_count > target.max_participants then return null; end if;
  update public.event_rsvps set status = 'joined' where event_id = p_event_id and user_id = waiting.user_id;
  perform public._enqueue_event_notification(waiting.user_id, p_event_id, null,
    'waitlist_promoted', 'Your place is ready',
    'You' || case when waiting.guest_count = 1 then ' and your friend are' else ' are' end || ' now going to ' || target.title || '.');
  return waiting.user_id;
end;
$$;

create or replace function public.set_event_saved(p_event_id uuid, p_saved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not p_saved then
    delete from public.event_saves where event_id=p_event_id and user_id=auth.uid();
    return false;
  end if;
  if not exists (
    select 1 from public.events e
    where e.id = p_event_id and e.status = 'published'
      and public.can_view_event(e.id, true) and e.end_at > pg_catalog.now()
  ) then
    raise exception using errcode = 'P0001', message = 'event_unavailable';
  end if;
  if p_saved then
    insert into public.event_saves (event_id, user_id)
    values (p_event_id, auth.uid()) on conflict do nothing;
  else
    delete from public.event_saves
    where event_id = p_event_id and user_id = auth.uid();
  end if;
  return p_saved;
end;
$$;

create or replace function public.set_event_reminder(p_event_id uuid, p_remind_at timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare event_start timestamptz;
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select e.start_at into event_start from public.events e
  where e.id = p_event_id and e.status = 'published';
  if event_start is null or p_remind_at <= pg_catalog.now() or p_remind_at >= event_start then
    raise exception using errcode = '22023', message = 'invalid_reminder_time';
  end if;
  insert into public.event_reminders (event_id, user_id, remind_at)
  values (p_event_id, auth.uid(), p_remind_at)
  on conflict (event_id, user_id)
  do update set remind_at = excluded.remind_at, updated_at = pg_catalog.now();
  delete from public.member_notifications
  where user_id = auth.uid() and event_id = p_event_id and kind = 'reminder';
  return p_remind_at;
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
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.list_event_attendees(p_event_id uuid)
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
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.list_event_attendees_v2(p_event_id uuid)
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
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.set_event_attendee_visibility(
  p_event_id uuid,
  p_visible boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.set_event_discussion_notifications(
  p_event_id uuid,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.confirm_event_rsvp(p_event_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare confirmed_at timestamptz := pg_catalog.now();
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
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

create or replace function public.submit_event_feedback(
  p_event_id uuid, p_attended boolean, p_rating integer, p_comment text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare organizer_id uuid; event_title text;
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if (p_attended and p_rating not between 1 and 5)
    or (not p_attended and p_rating is not null)
    or char_length(trim(coalesce(p_comment, ''))) > 1000 then
    raise exception using errcode = '22023', message = 'feedback_validation';
  end if;
  select e.organizer_id, e.title into organizer_id, event_title
  from public.events e
  where e.id = p_event_id and e.end_at <= pg_catalog.now()
    and e.organizer_id <> auth.uid()
    and exists (
      select 1 from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
        and r.status in ('joined', 'tentative', 'attended', 'no_show')
    );
  if organizer_id is null then
    raise exception using errcode = '42501', message = 'feedback_unavailable';
  end if;
  insert into public.event_feedback (event_id, user_id, rating, comment, attended)
  values (
    p_event_id, auth.uid(), case when p_attended then p_rating else null end,
    trim(coalesce(p_comment, '')), p_attended
  )
  on conflict (event_id, user_id) do update set
    rating = excluded.rating, comment = excluded.comment,
    attended = excluded.attended, updated_at = pg_catalog.now();
  update public.event_rsvps set
    status = case when p_attended then 'attended' else 'no_show' end,
    updated_at = pg_catalog.now()
  where event_id = p_event_id and user_id = auth.uid();
  perform public._enqueue_event_notification(
    organizer_id, p_event_id, auth.uid(), 'feedback_received',
    'New event feedback',
    case when p_attended
      then event_title || ' received a new rating.'
      else 'An attendee updated their attendance for ' || event_title || '.'
    end
  );
  return true;
end;
$$;

create or replace function public.get_event_discussion_last_seen(p_event_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare seen_at timestamptz;
begin
  if not public.can_view_event(p_event_id, true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not public._can_manage_event(p_event_id, auth.uid()) and not exists (
    select 1 from public.event_rsvps r where r.event_id = p_event_id
      and r.user_id = auth.uid()
      and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  select r.last_seen_at into seen_at from public.event_discussion_reads r
  where r.user_id = auth.uid() and r.event_id = p_event_id;
  return seen_at;
end;
$$;

create or replace function public.get_ai_recommendation_state(p_surface text, p_candidate_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  preference_query text;
  history_key text;
  profile_key text;
  candidate_key text;
  computed_cache_key text;
  cached_ranked_ids uuid[];
  strong_count integer;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_surface is null or p_surface not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'invalid_recommendation_surface';
  end if;
  if p_candidate_ids is null or cardinality(p_candidate_ids) not between 2 and 24
    or (select count(distinct id) from unnest(p_candidate_ids) id) <> cardinality(p_candidate_ids) then
    raise exception using errcode = '22023', message = 'invalid_recommendation_candidates';
  end if;

  if p_surface = 'event' and exists (select 1 from unnest(p_candidate_ids) candidate_id
    left join public.events e on e.id=candidate_id
    where e.id is null or e.visibility <> 'public' or not public.can_view_event(e.id,false)) then
    return jsonb_build_object('eligible', false);
  end if;
  -- One deliberate choice is enough. Passive views alone never trigger a
  -- model call. Interests are used only inside PostgreSQL, not in this query.
  select count(*) filter (where h.signal_type <> 'view'),
    string_agg('Action: ' || h.signal_type || ' | Category: ' || h.category || ' | ' || h.summary,
      E'\n' order by h.occurred_at desc, h.content_id),
    string_agg(h.content_id::text || ':' || h.signal_type || ':' || h.occurred_at::text || ':' || h.summary,
      '|' order by h.content_id)
  into strong_count, preference_query, history_key
  from public._recommendation_history(p_surface) h
  where h.signal_type <> 'view';

  if strong_count = 0 then
    return jsonb_build_object('eligible', false, 'preference_query', null, 'cache_key', null, 'ranked_ids', null);
  end if;
  select p.interests::text || coalesce(r.hidden_categories::text, '')
    || coalesce(r.history_reset_at::text, '') into profile_key
  from public.profiles p left join public.recommendation_preferences r on r.user_id = p.id
  where p.id = auth.uid();
  if p_surface = 'event' then
    select string_agg(e.id::text || ':' || e.updated_at::text, '|' order by ids.ordinality)
    into candidate_key from unnest(p_candidate_ids) with ordinality ids(id, ordinality)
    join public.events e on e.id = ids.id;
  else
    select string_agg(p.id::text || ':' || p.updated_at::text, '|' order by ids.ordinality)
    into candidate_key from unnest(p_candidate_ids) with ordinality ids(id, ordinality)
    join public.forum_posts p on p.id = ids.id;
  end if;
  computed_cache_key := md5('interest-first-v1|' || p_surface || '|' || history_key || '|'
    || profile_key || '|' || coalesce(candidate_key, '') || '|' || array_to_string(p_candidate_ids, ','));
  select c.ranked_ids into cached_ranked_ids from public.ai_recommendation_cache c
  where c.user_id = auth.uid() and c.surface = p_surface
    and c.cache_key = computed_cache_key and c.expires_at > now();
  return jsonb_build_object('eligible', true, 'preference_query', left(preference_query, 4000),
    'cache_key', computed_cache_key, 'ranked_ids', cached_ranked_ids);
end;
$$;

create or replace function public.list_member_notifications()
returns table (
  id uuid, event_id uuid, kind text, title text, body text,
  read_at timestamptz, created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  insert into public.member_notifications (user_id, event_id, kind, title, body)
  select reminder.user_id, reminder.event_id, 'reminder', 'Event reminder',
    e.title || ' starts ' || pg_catalog.to_char(e.start_at, 'FMDay at HH24:MI') || '.'
  from public.event_reminders reminder
  join public.events e on e.id = reminder.event_id
  where reminder.user_id = auth.uid() and reminder.remind_at <= pg_catalog.now()
    and e.status = 'published' and e.start_at > pg_catalog.now()
  on conflict do nothing;

  return query
  select n.id, n.event_id, n.kind, n.title, n.body, n.read_at, n.created_at
  from public.member_notifications n
  where n.user_id = auth.uid()
    and (n.event_id is null or public._event_audience_allows(n.event_id, n.user_id))
  order by n.created_at desc limit 100;
end;
$$;

create or replace function public.claim_push_delivery_batch(p_limit integer default 50)
returns table (
  delivery_id bigint, device_token text, device_platform text,
  title text, body text, event_id uuid, attempt integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'service_role_required';
  end if;
  delete from public.push_deliveries d
  where d.delivered_at < pg_catalog.now() - interval '7 days';
  update public.push_deliveries d set
    delivered_at = pg_catalog.now(), claimed_at = null,
    last_error = 'disabled_by_member_preferences'
  from public.member_notifications n
  where n.id = d.notification_id and d.delivered_at is null
    and not public._push_notification_category_allowed(n.user_id, n.kind);

  return query
  with picked as (
    select d.id
    from public.push_deliveries d
    join public.push_devices p on p.id = d.device_id and p.enabled
    join public.member_notifications n
      on n.id = d.notification_id and n.user_id = p.user_id
    where d.delivered_at is null and d.available_at <= pg_catalog.now()
      and d.attempts < 8
      and (n.event_id is null or public._event_audience_allows(n.event_id, n.user_id))
      and public._push_notification_allowed(n.user_id, n.kind, pg_catalog.now())
      and (d.claimed_at is null or d.claimed_at < pg_catalog.now() - interval '5 minutes')
    order by d.available_at, d.id
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    for update of d skip locked
  ), claimed as (
    update public.push_deliveries d
    set claimed_at = pg_catalog.now(), attempts = d.attempts + 1
    from picked where d.id = picked.id
    returning d.id, d.device_id, d.notification_id, d.attempts
  )
  select c.id, p.token, p.platform, n.title, n.body, n.event_id, c.attempts
  from claimed c
  join public.push_devices p on p.id = c.device_id
  join public.member_notifications n on n.id = c.notification_id
  order by c.id;
end;
$$;

create function public._guard_event_audience_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.event_id is not null and not public._event_audience_allows(new.event_id, new.user_id) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public._guard_event_audience_notification() from public,anon,authenticated;
create trigger member_notifications_guard_event_audience before insert on public.member_notifications
  for each row execute function public._guard_event_audience_notification();
