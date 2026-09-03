-- Complete the event lifecycle: plans, saves, reminders, waitlists,
-- organizer updates, announcements, attendee discussion, notifications,
-- and post-event attendance/feedback.

alter table public.event_rsvps
  drop constraint if exists event_rsvps_status_check;

alter table public.event_rsvps
  add constraint event_rsvps_status_check check (
    status in ('joined', 'tentative', 'waitlisted', 'cancelled', 'attended', 'no_show')
  );

create table public.event_saves (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, user_id)
);

create table public.event_reminders (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  remind_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, user_id)
);

create table public.event_announcements (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default pg_catalog.now()
);

create table public.event_discussion_messages (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1200),
  status text not null default 'visible' check (status in ('visible', 'hidden')),
  created_at timestamptz not null default pg_catalog.now()
);

create table public.event_discussion_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  message_id uuid not null references public.event_discussion_messages(id) on delete cascade,
  reason text not null check (
    reason in (
      'spam', 'harassment', 'unsafe_behaviour', 'personal_information',
      'inappropriate_content', 'other'
    )
  ),
  status text not null default 'open' check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  created_at timestamptz not null default pg_catalog.now(),
  unique (reporter_id, message_id)
);

create table public.event_feedback (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer check (rating between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 1000),
  attended boolean not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (event_id, user_id),
  constraint attended_feedback_rating check (
    (attended and rating is not null) or (not attended and rating is null)
  )
);

create table public.member_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  source_id uuid,
  kind text not null check (
    kind in (
      'reminder', 'waitlist_promoted', 'event_updated', 'event_cancelled',
      'announcement', 'discussion_reply', 'feedback_received'
    )
  ),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 1000),
  read_at timestamptz,
  created_at timestamptz not null default pg_catalog.now()
);

create index event_saves_user_idx
  on public.event_saves (user_id, created_at desc);
create index event_reminders_due_idx
  on public.event_reminders (user_id, remind_at);
create index event_announcements_event_idx
  on public.event_announcements (event_id, created_at desc);
create index event_discussion_event_idx
  on public.event_discussion_messages (event_id, created_at);
create index member_notifications_user_idx
  on public.member_notifications (user_id, created_at desc);
create unique index member_notifications_single_event_kind_idx
  on public.member_notifications (user_id, event_id, kind)
  where kind in ('reminder', 'waitlist_promoted', 'event_cancelled');
create unique index member_notifications_source_idx
  on public.member_notifications (user_id, event_id, source_id, kind)
  where source_id is not null;

create trigger event_reminders_set_updated_at
before update on public.event_reminders
for each row execute function public.set_updated_at();

create trigger event_feedback_set_updated_at
before update on public.event_feedback
for each row execute function public.set_updated_at();

alter table public.event_saves enable row level security;
alter table public.event_reminders enable row level security;
alter table public.event_announcements enable row level security;
alter table public.event_discussion_messages enable row level security;
alter table public.event_discussion_reports enable row level security;
alter table public.event_feedback enable row level security;
alter table public.member_notifications enable row level security;

-- Access is deliberately kept behind fixed-signature functions below.
revoke all on public.event_saves from anon, authenticated;
revoke all on public.event_reminders from anon, authenticated;
revoke all on public.event_announcements from anon, authenticated;
revoke all on public.event_discussion_messages from anon, authenticated;
revoke all on public.event_discussion_reports from anon, authenticated;
revoke all on public.event_feedback from anon, authenticated;
revoke all on public.member_notifications from anon, authenticated;

create function public._enqueue_event_notification(
  p_user_id uuid,
  p_event_id uuid,
  p_source_id uuid,
  p_kind text,
  p_title text,
  p_body text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.member_notifications (
    user_id, event_id, source_id, kind, title, body
  ) values (
    p_user_id, p_event_id, p_source_id, p_kind,
    left(p_title, 120), left(p_body, 1000)
  )
  on conflict do nothing;
$$;

revoke all on function public._enqueue_event_notification(
  uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;

create function public._promote_event_waitlist(p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  promoted_user_id uuid;
  event_title text;
  capacity integer;
  joined_total integer;
begin
  select e.title, e.max_participants
  into event_title, capacity
  from public.events e
  where e.id = p_event_id and e.status = 'published'
  for update;

  if not found then return null; end if;

  select count(*) into joined_total
  from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'joined';

  if joined_total >= capacity then return null; end if;

  select r.user_id into promoted_user_id
  from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'waitlisted'
  order by r.created_at, r.user_id
  for update skip locked
  limit 1;

  if promoted_user_id is null then return null; end if;

  update public.event_rsvps
  set status = 'joined', updated_at = pg_catalog.now()
  where event_id = p_event_id and user_id = promoted_user_id;

  perform public._enqueue_event_notification(
    promoted_user_id, p_event_id, null, 'waitlist_promoted',
    'You have a place',
    'A place opened for ' || event_title || '. You are now going.'
  );
  return promoted_user_id;
end;
$$;

revoke all on function public._promote_event_waitlist(uuid)
from public, anon, authenticated;

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
  event_organizer uuid;
  current_status text;
  joined_total integer;
  saved_status text := p_status;
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

  select e.max_participants, e.start_at, e.status, e.organizer_id
  into event_limit, event_start, event_status, event_organizer
  from public.events e
  where e.id = p_event_id
  for update;

  if not found or event_status <> 'published' then
    raise exception using errcode = 'P0001', message = 'event_unavailable';
  end if;
  if p_status in ('joined', 'tentative') and event_start <= pg_catalog.now() then
    raise exception using errcode = 'P0001', message = 'event_started';
  end if;
  if event_organizer = current_user_id and p_status <> 'joined' then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  select r.status into current_status
  from public.event_rsvps r
  where r.event_id = p_event_id and r.user_id = current_user_id;

  if p_status = 'joined' and current_status is distinct from 'joined' then
    select count(*) into joined_total
    from public.event_rsvps r
    where r.event_id = p_event_id and r.status = 'joined';
    if joined_total >= event_limit then saved_status := 'waitlisted'; end if;
  end if;

  insert into public.event_rsvps (event_id, user_id, status)
  values (p_event_id, current_user_id, saved_status)
  on conflict (event_id, user_id)
  do update set
    status = excluded.status,
    created_at = case
      when excluded.status = 'waitlisted'
        and event_rsvps.status is distinct from 'waitlisted'
      then pg_catalog.now()
      else event_rsvps.created_at
    end,
    updated_at = pg_catalog.now();

  if p_status = 'cancelled' and current_status = 'joined' then
    perform public._promote_event_waitlist(p_event_id);
  end if;

  return saved_status;
end;
$$;

create function public.list_my_events(p_filter text default 'going')
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
  where
    case p_filter
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

drop function if exists public.get_event_details(uuid);

create function public.get_event_details(p_event_id uuid)
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
    and (
      (e.status = 'published' and e.visibility = 'public')
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

create function public.set_event_saved(p_event_id uuid, p_saved boolean)
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
    where e.id = p_event_id and e.status = 'published'
      and e.visibility = 'public' and e.end_at > pg_catalog.now()
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

create function public.set_event_reminder(p_event_id uuid, p_remind_at timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare event_start timestamptz;
begin
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

create function public.clear_event_reminder(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.event_reminders
  where event_id = p_event_id and user_id = auth.uid();
  delete from public.member_notifications
  where user_id = auth.uid() and event_id = p_event_id and kind = 'reminder';
  return true;
end;
$$;

create function public.update_own_event(
  p_event_id uuid, p_title text, p_description text, p_category text,
  p_venue_name text, p_address text, p_latitude double precision,
  p_longitude double precision, p_start_at timestamptz,
  p_end_at timestamptz, p_max_participants integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare joined_total integer; previous_start timestamptz;
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
    or p_max_participants not between 2 and 500 then
    raise exception using errcode = '22023', message = 'event_validation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_event_id::text, 0));
  select e.start_at into previous_start from public.events e
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published' and e.start_at > pg_catalog.now()
  for update;
  if previous_start is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  select count(*) into joined_total from public.event_rsvps r
  where r.event_id = p_event_id and r.status = 'joined';
  if p_max_participants < joined_total then
    raise exception using errcode = '22023', message = 'capacity_below_attendance';
  end if;

  update public.events e set
    title = trim(p_title), description = trim(p_description), category = trim(p_category),
    venue_name = trim(p_venue_name), address = trim(p_address),
    location = extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude), 4326
    )::extensions.geography,
    start_at = p_start_at, end_at = p_end_at,
    max_participants = p_max_participants
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published' and e.start_at > pg_catalog.now();
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

create function public.cancel_own_event(p_event_id uuid)
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
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published' and e.start_at > pg_catalog.now()
  returning e.title into event_title;
  if event_title is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  insert into public.member_notifications (user_id, event_id, kind, title, body)
  select recipients.user_id, p_event_id, 'event_cancelled', 'Event cancelled',
    event_title || ' has been cancelled by the host.'
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

create function public.create_event_announcement(p_event_id uuid, p_body text)
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
  where e.id = p_event_id and e.organizer_id = auth.uid()
    and e.status = 'published';
  if event_title is null then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if (
    select count(*) from public.event_announcements a
    where a.event_id = p_event_id and a.created_at > pg_catalog.now() - interval '1 hour'
  ) >= 3 then
    raise exception using errcode = 'P0001', message = 'announcement_rate_limited';
  end if;
  insert into public.event_announcements (event_id, author_id, body)
  values (p_event_id, auth.uid(), trim(p_body)) returning id into announcement_id;
  insert into public.member_notifications (
    user_id, event_id, source_id, kind, title, body
  )
  select r.user_id, p_event_id, announcement_id, 'announcement',
    'Update from the host', event_title || ': ' || trim(p_body)
  from public.event_rsvps r
  where r.event_id = p_event_id
    and r.status in ('joined', 'tentative', 'waitlisted')
    and r.user_id <> auth.uid()
  on conflict do nothing;
  return announcement_id;
end;
$$;

create function public.list_event_announcements(p_event_id uuid)
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
    and (
      (e.status = 'published' and e.visibility = 'public')
      or e.organizer_id = auth.uid()
      or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
    )
  order by a.created_at desc limit 20;
$$;

create function public.list_event_discussion(p_event_id uuid)
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

create function public.create_event_discussion_message(p_event_id uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare message_id uuid; organizer_id uuid; event_title text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(trim(p_body)) not between 1 and 1200 then
    raise exception using errcode = '22023', message = 'discussion_validation';
  end if;
  if (
    select count(*) from public.event_discussion_messages recent
    where recent.author_id = auth.uid()
      and recent.created_at > pg_catalog.now() - interval '1 minute'
  ) >= 10 then
    raise exception using errcode = 'P0001', message = 'discussion_rate_limited';
  end if;
  select e.organizer_id, e.title into organizer_id, event_title
  from public.events e where e.id = p_event_id
    and e.status in ('published', 'completed')
    and (
      e.organizer_id = auth.uid()
      or exists (
        select 1 from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
          and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
      )
    );
  if organizer_id is null then
    raise exception using errcode = '42501', message = 'discussion_unavailable';
  end if;
  insert into public.event_discussion_messages (event_id, author_id, body)
  values (p_event_id, auth.uid(), trim(p_body)) returning id into message_id;
  if organizer_id <> auth.uid() then
    perform public._enqueue_event_notification(
      organizer_id, p_event_id, message_id, 'discussion_reply',
      'New event question', event_title || ' has a new attendee message.'
    );
  end if;
  return message_id;
end;
$$;

create function public.report_event_discussion_message(
  p_message_id uuid, p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare message_author uuid; message_event uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_reason not in (
    'spam', 'harassment', 'unsafe_behaviour', 'personal_information',
    'inappropriate_content', 'other'
  ) then
    raise exception using errcode = '22023', message = 'invalid_report_reason';
  end if;
  select m.author_id, m.event_id into message_author, message_event
  from public.event_discussion_messages m
  join public.events e on e.id = m.event_id
  where m.id = p_message_id and (
    e.organizer_id = auth.uid()
    or exists (
      select 1 from public.event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()
        and r.status in ('joined', 'tentative', 'waitlisted', 'attended')
    )
  );
  if message_author is null then
    raise exception using errcode = 'P0001', message = 'discussion_unavailable';
  end if;
  if message_author = auth.uid() then
    raise exception using errcode = '22023', message = 'cannot_report_own_content';
  end if;
  insert into public.event_discussion_reports (reporter_id, message_id, reason)
  values (auth.uid(), p_message_id, p_reason) on conflict do nothing;
  return true;
end;
$$;

create function public.submit_event_feedback(
  p_event_id uuid, p_attended boolean, p_rating integer, p_comment text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare organizer_id uuid; event_title text;
begin
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

create function public.list_event_feedback(p_event_id uuid)
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
  if not exists (
    select 1 from public.events e
    where e.id = p_event_id and e.organizer_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return query
  select f.attended, f.rating, f.comment, f.created_at
  from public.event_feedback f
  where f.event_id = p_event_id
  order by f.created_at desc;
end;
$$;

create function public.list_member_notifications()
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
  order by n.created_at desc limit 100;
end;
$$;

create function public.mark_member_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.member_notifications n set read_at = pg_catalog.now()
  where n.id = p_notification_id and n.user_id = auth.uid();
  return found;
end;
$$;

create function public.mark_all_member_notifications_read()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update public.member_notifications n set read_at = pg_catalog.now()
  where n.user_id = auth.uid() and n.read_at is null;
  return true;
end;
$$;

revoke all on function public.list_my_events(text) from public, anon;
revoke all on function public.get_event_details(uuid) from public, anon;
revoke all on function public.set_event_saved(uuid, boolean) from public, anon;
revoke all on function public.set_event_reminder(uuid, timestamptz) from public, anon;
revoke all on function public.clear_event_reminder(uuid) from public, anon;
revoke all on function public.update_own_event(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer
) from public, anon;
revoke all on function public.cancel_own_event(uuid) from public, anon;
revoke all on function public.create_event_announcement(uuid, text) from public, anon;
revoke all on function public.list_event_announcements(uuid) from public, anon;
revoke all on function public.list_event_discussion(uuid) from public, anon;
revoke all on function public.create_event_discussion_message(uuid, text) from public, anon;
revoke all on function public.report_event_discussion_message(uuid, text) from public, anon;
revoke all on function public.submit_event_feedback(uuid, boolean, integer, text) from public, anon;
revoke all on function public.list_event_feedback(uuid) from public, anon;
revoke all on function public.list_member_notifications() from public, anon;
revoke all on function public.mark_member_notification_read(uuid) from public, anon;
revoke all on function public.mark_all_member_notifications_read() from public, anon;

grant execute on function public.list_my_events(text) to authenticated;
grant execute on function public.get_event_details(uuid) to authenticated;
grant execute on function public.set_event_saved(uuid, boolean) to authenticated;
grant execute on function public.set_event_reminder(uuid, timestamptz) to authenticated;
grant execute on function public.clear_event_reminder(uuid) to authenticated;
grant execute on function public.update_own_event(
  uuid, text, text, text, text, text, double precision, double precision,
  timestamptz, timestamptz, integer
) to authenticated;
grant execute on function public.cancel_own_event(uuid) to authenticated;
grant execute on function public.create_event_announcement(uuid, text) to authenticated;
grant execute on function public.list_event_announcements(uuid) to authenticated;
grant execute on function public.list_event_discussion(uuid) to authenticated;
grant execute on function public.create_event_discussion_message(uuid, text) to authenticated;
grant execute on function public.report_event_discussion_message(uuid, text) to authenticated;
grant execute on function public.submit_event_feedback(uuid, boolean, integer, text) to authenticated;
grant execute on function public.list_event_feedback(uuid) to authenticated;
grant execute on function public.list_member_notifications() to authenticated;
grant execute on function public.mark_member_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_member_notifications_read() to authenticated;

comment on function public.list_my_events(text) is
  'Returns only the authenticated member plans, hosted events, history, or saves.';
comment on table public.member_notifications is
  'Private in-app event updates and due reminders; never directly client-readable.';
