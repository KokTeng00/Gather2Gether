-- Practical member controls and event operations: onboarding, notification
-- preferences, recommendation controls, moderation, host attendance, series
-- editing, data export, and discussion read cursors.

alter table public.profiles
  add column interests text[] not null default '{}',
  add column accessibility_preferences text[] not null default '{}',
  add column onboarding_completed_at timestamptz;

alter table public.profiles
  add constraint profiles_interests_check check (
    pg_catalog.cardinality(interests) <= 12
  ),
  add constraint profiles_accessibility_preferences_check check (
    pg_catalog.cardinality(accessibility_preferences) <= 8
  );

grant select (interests, accessibility_preferences, onboarding_completed_at)
  on public.profiles to authenticated;

create table public.member_notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  reminders_enabled boolean not null default true,
  announcements_enabled boolean not null default true,
  discussion_enabled boolean not null default true,
  recommendations_enabled boolean not null default true,
  quiet_start_minute integer check (
    quiet_start_minute is null or quiet_start_minute between 0 and 1439
  ),
  quiet_end_minute integer check (
    quiet_end_minute is null or quiet_end_minute between 0 and 1439
  ),
  timezone_offset_minutes integer not null default 0 check (
    timezone_offset_minutes between -840 and 840
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint quiet_hours_pair check (
    (quiet_start_minute is null) = (quiet_end_minute is null)
  )
);

create trigger member_notification_preferences_set_updated_at
before update on public.member_notification_preferences
for each row execute function public.set_updated_at();

alter table public.member_notification_preferences enable row level security;
revoke all on public.member_notification_preferences from anon, authenticated;

create table public.recommendation_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  hidden_categories text[] not null default '{}',
  updated_at timestamptz not null default pg_catalog.now(),
  constraint hidden_categories_check check (
    pg_catalog.cardinality(hidden_categories) <= 24
  )
);

create table public.hidden_recommendation_content (
  user_id uuid not null references public.profiles(id) on delete cascade,
  content_kind text not null check (content_kind in ('event', 'forum_post')),
  content_id uuid not null,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, content_kind, content_id)
);

create trigger recommendation_preferences_set_updated_at
before update on public.recommendation_preferences
for each row execute function public.set_updated_at();

alter table public.recommendation_preferences enable row level security;
alter table public.hidden_recommendation_content enable row level security;
revoke all on public.recommendation_preferences from anon, authenticated;
revoke all on public.hidden_recommendation_content from anon, authenticated;

create table public.event_discussion_reads (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  last_seen_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, event_id)
);

alter table public.event_discussion_reads enable row level security;
revoke all on public.event_discussion_reads from anon, authenticated;

create table public.moderation_actions (
  id bigint generated always as identity primary key,
  moderator_id uuid not null references public.profiles(id) on delete restrict,
  report_kind text not null check (
    report_kind in ('event', 'forum_post', 'forum_comment', 'discussion')
  ),
  report_id uuid not null,
  action text not null check (
    action in ('reviewing', 'resolved', 'dismissed', 'hidden')
  ),
  note text not null default '' check (pg_catalog.char_length(note) <= 1000),
  created_at timestamptz not null default pg_catalog.now()
);

create index moderation_actions_report_idx
  on public.moderation_actions (report_kind, report_id, created_at desc);
alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon, authenticated;
revoke all on sequence public.moderation_actions_id_seq from anon, authenticated;

create function public._is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and coalesce(
    auth.jwt() -> 'app_metadata' ->> 'role', ''
  ) in ('moderator', 'admin');
$$;

revoke all on function public._is_moderator() from public, anon, authenticated;

create function public.get_moderation_status()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select public._is_moderator(); $$;

create function public.complete_onboarding(
  p_interests text[],
  p_accessibility_preferences text[],
  p_radius_km double precision,
  p_latitude double precision,
  p_longitude double precision
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_interests text[];
  clean_accessibility text[];
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select coalesce(pg_catalog.array_agg(value order by value), '{}'::text[])
  into clean_interests
  from (
    select distinct pg_catalog.btrim(item) value
    from pg_catalog.unnest(coalesce(p_interests, '{}')) item
    where pg_catalog.btrim(item) <> ''
  ) values_to_keep;
  select coalesce(pg_catalog.array_agg(value order by value), '{}'::text[])
  into clean_accessibility
  from (
    select distinct pg_catalog.btrim(item) value
    from pg_catalog.unnest(coalesce(p_accessibility_preferences, '{}')) item
    where pg_catalog.btrim(item) <> ''
  ) values_to_keep;

  if pg_catalog.cardinality(clean_interests) > 12
    or exists (
      select 1 from pg_catalog.unnest(clean_interests) value
      where pg_catalog.char_length(value) not between 1 and 60
    )
    or pg_catalog.cardinality(clean_accessibility) > 8
    or exists (
      select 1 from pg_catalog.unnest(clean_accessibility) value
      where value not in (
        'wheelchair_accessible', 'beginner_friendly', 'quiet_space',
        'step_free_access', 'accessible_toilet', 'hearing_support'
      )
    )
    or p_radius_km not between 1 and 100
    or ((p_latitude is null) <> (p_longitude is null))
    or (p_latitude is not null and p_latitude not between -90 and 90)
    or (p_longitude is not null and p_longitude not between -180 and 180) then
    raise exception using errcode = '22023', message = 'onboarding_validation';
  end if;

  update public.profiles p set
    interests = clean_interests,
    accessibility_preferences = clean_accessibility,
    preferred_radius_km = p_radius_km,
    approximate_latitude = case when p_latitude is null then p.approximate_latitude
      else pg_catalog.round(p_latitude::numeric, 2)::double precision end,
    approximate_longitude = case when p_longitude is null then p.approximate_longitude
      else pg_catalog.round(p_longitude::numeric, 2)::double precision end,
    onboarding_completed_at = pg_catalog.now()
  where p.id = auth.uid();
  return found;
end;
$$;

create function public.get_notification_preferences()
returns table (
  push_enabled boolean, reminders_enabled boolean,
  announcements_enabled boolean, discussion_enabled boolean,
  recommendations_enabled boolean, quiet_start_minute integer,
  quiet_end_minute integer, timezone_offset_minutes integer
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
  select coalesce(p.push_enabled, true), coalesce(p.reminders_enabled, true),
    coalesce(p.announcements_enabled, true), coalesce(p.discussion_enabled, true),
    coalesce(p.recommendations_enabled, true), p.quiet_start_minute,
    p.quiet_end_minute, coalesce(p.timezone_offset_minutes, 0)
  from (select auth.uid() user_id) owner
  left join public.member_notification_preferences p using (user_id);
end;
$$;

create function public.update_notification_preferences(
  p_push_enabled boolean,
  p_reminders_enabled boolean,
  p_announcements_enabled boolean,
  p_discussion_enabled boolean,
  p_recommendations_enabled boolean,
  p_quiet_start_minute integer,
  p_quiet_end_minute integer,
  p_timezone_offset_minutes integer
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
  if p_push_enabled is null or p_reminders_enabled is null
    or p_announcements_enabled is null or p_discussion_enabled is null
    or p_recommendations_enabled is null
    or p_timezone_offset_minutes not between -840 and 840
    or ((p_quiet_start_minute is null) <> (p_quiet_end_minute is null))
    or (p_quiet_start_minute is not null and p_quiet_start_minute not between 0 and 1439)
    or (p_quiet_end_minute is not null and p_quiet_end_minute not between 0 and 1439) then
    raise exception using errcode = '22023', message = 'notification_preferences_validation';
  end if;
  insert into public.member_notification_preferences (
    user_id, push_enabled, reminders_enabled, announcements_enabled,
    discussion_enabled, recommendations_enabled, quiet_start_minute,
    quiet_end_minute, timezone_offset_minutes
  ) values (
    auth.uid(), p_push_enabled, p_reminders_enabled, p_announcements_enabled,
    p_discussion_enabled, p_recommendations_enabled, p_quiet_start_minute,
    p_quiet_end_minute, p_timezone_offset_minutes
  ) on conflict (user_id) do update set
    push_enabled = excluded.push_enabled,
    reminders_enabled = excluded.reminders_enabled,
    announcements_enabled = excluded.announcements_enabled,
    discussion_enabled = excluded.discussion_enabled,
    recommendations_enabled = excluded.recommendations_enabled,
    quiet_start_minute = excluded.quiet_start_minute,
    quiet_end_minute = excluded.quiet_end_minute,
    timezone_offset_minutes = excluded.timezone_offset_minutes;
  return true;
end;
$$;

create function public._push_notification_category_allowed(
  p_user_id uuid,
  p_kind text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare prefs public.member_notification_preferences%rowtype;
begin
  select * into prefs from public.member_notification_preferences p
  where p.user_id = p_user_id;
  if not found then return true; end if;
  if not prefs.push_enabled then return false; end if;
  if p_kind = 'reminder' and not prefs.reminders_enabled then return false; end if;
  if p_kind = 'announcement' and not prefs.announcements_enabled then return false; end if;
  if p_kind = 'discussion_reply' and not prefs.discussion_enabled then return false; end if;
  if p_kind in ('saved_search_match', 'followed_host_event')
    and not prefs.recommendations_enabled then return false; end if;
  return true;
end;
$$;

create function public._push_notification_allowed(
  p_user_id uuid,
  p_kind text,
  p_at timestamptz default pg_catalog.now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  prefs public.member_notification_preferences%rowtype;
  local_minute integer;
  in_quiet_hours boolean := false;
  essential boolean := p_kind in ('event_cancelled', 'waitlist_promoted');
begin
  if not public._push_notification_category_allowed(p_user_id, p_kind) then
    return false;
  end if;
  select * into prefs from public.member_notification_preferences p
  where p.user_id = p_user_id;
  if not found then return true; end if;

  if prefs.quiet_start_minute is not null
    and prefs.quiet_start_minute <> prefs.quiet_end_minute then
    local_minute := (
      pg_catalog.date_part('hour', p_at + pg_catalog.make_interval(
        mins => prefs.timezone_offset_minutes
      ))::integer * 60
      + pg_catalog.date_part('minute', p_at + pg_catalog.make_interval(
        mins => prefs.timezone_offset_minutes
      ))::integer
    );
    if prefs.quiet_start_minute < prefs.quiet_end_minute then
      in_quiet_hours := local_minute >= prefs.quiet_start_minute
        and local_minute < prefs.quiet_end_minute;
    else
      in_quiet_hours := local_minute >= prefs.quiet_start_minute
        or local_minute < prefs.quiet_end_minute;
    end if;
  end if;
  return essential or not in_quiet_hours;
end;
$$;

revoke all on function public._push_notification_category_allowed(uuid, text)
  from public, anon, authenticated;
revoke all on function public._push_notification_allowed(uuid, text, timestamptz)
  from public, anon, authenticated;

create or replace function public._queue_member_notification_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public._push_notification_category_allowed(new.user_id, new.kind) then
    insert into public.push_deliveries (notification_id, device_id)
    select new.id, d.id from public.push_devices d
    where d.user_id = new.user_id and d.enabled
    on conflict do nothing;
  end if;
  return new;
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

create function public.get_recommendation_preferences()
returns table (enabled boolean, hidden_categories text[], hidden_count bigint)
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
  select coalesce(p.enabled, true), coalesce(p.hidden_categories, '{}'),
    (select pg_catalog.count(*) from public.hidden_recommendation_content h
      where h.user_id = auth.uid())
  from (select auth.uid() user_id) owner
  left join public.recommendation_preferences p using (user_id);
end;
$$;

create function public.update_recommendation_preferences(
  p_enabled boolean,
  p_hidden_categories text[]
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare clean_categories text[];
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select coalesce(pg_catalog.array_agg(value order by value), '{}'::text[]) into clean_categories
  from (
    select distinct pg_catalog.btrim(item) value
    from pg_catalog.unnest(coalesce(p_hidden_categories, '{}')) item
    where pg_catalog.btrim(item) <> ''
  ) values_to_keep;
  if p_enabled is null or pg_catalog.cardinality(clean_categories) > 24
    or exists (
      select 1 from pg_catalog.unnest(clean_categories) value
      where pg_catalog.char_length(value) not between 1 and 60
    ) then
    raise exception using errcode = '22023', message = 'recommendation_preferences_validation';
  end if;
  insert into public.recommendation_preferences (user_id, enabled, hidden_categories)
  values (auth.uid(), p_enabled, clean_categories)
  on conflict (user_id) do update set enabled = excluded.enabled,
    hidden_categories = excluded.hidden_categories;
  return true;
end;
$$;

create function public.hide_recommendation(
  p_content_kind text,
  p_content_id uuid
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
  if p_content_kind not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'recommendation_validation';
  end if;
  insert into public.hidden_recommendation_content (user_id, content_kind, content_id)
  values (auth.uid(), p_content_kind, p_content_id) on conflict do nothing;
  return true;
end;
$$;

create function public.reset_recommendation_controls()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from public.hidden_recommendation_content h where h.user_id = auth.uid();
  delete from public.recommendation_signals s where s.user_id = auth.uid();
  delete from public.recommendation_preferences p where p.user_id = auth.uid();
  return true;
end;
$$;

create function public.list_hidden_recommendation_ids(p_content_kind text)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_content_kind not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'recommendation_validation';
  end if;
  return coalesce((
    select pg_catalog.array_agg(h.content_id)
    from public.hidden_recommendation_content h
    where h.user_id = auth.uid() and h.content_kind = p_content_kind
  ), '{}');
end;
$$;

create function public.get_event_host_dashboard(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null or not public._can_manage_event(p_event_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  select pg_catalog.jsonb_build_object(
    'joined', pg_catalog.count(*) filter (where r.status = 'joined'),
    'tentative', pg_catalog.count(*) filter (where r.status = 'tentative'),
    'waitlisted', pg_catalog.count(*) filter (where r.status = 'waitlisted'),
    'attended', pg_catalog.count(*) filter (where r.status = 'attended'),
    'no_show', pg_catalog.count(*) filter (where r.status = 'no_show'),
    'saved', (select pg_catalog.count(*) from public.event_saves s where s.event_id = p_event_id),
    'feedback_count', (select pg_catalog.count(*) from public.event_feedback f where f.event_id = p_event_id),
    'average_rating', (select pg_catalog.round(pg_catalog.avg(f.rating), 1)
      from public.event_feedback f where f.event_id = p_event_id and f.rating is not null)
  ) into result
  from public.event_rsvps r where r.event_id = p_event_id;
  return result;
end;
$$;

create function public.list_event_host_attendees(p_event_id uuid)
returns table (
  profile_id uuid, display_name text, username text, rsvp_status text,
  reconfirmed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public._can_manage_event(p_event_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  return query select p.id, p.display_name, coalesce(p.username, ''),
    r.status, r.reconfirmed_at
  from public.event_rsvps r join public.profiles p on p.id = r.user_id
  where r.event_id = p_event_id and r.status <> 'cancelled'
  order by case r.status
    when 'joined' then 0 when 'tentative' then 1 when 'waitlisted' then 2
    when 'attended' then 3 else 4 end, p.display_name, p.id;
end;
$$;

create function public.set_event_attendance(
  p_event_id uuid,
  p_profile_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare event_start timestamptz;
begin
  if auth.uid() is null or not public._can_manage_event(p_event_id, auth.uid()) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if p_status not in ('joined', 'attended', 'no_show') then
    raise exception using errcode = '22023', message = 'attendance_validation';
  end if;
  select e.start_at into event_start from public.events e where e.id = p_event_id;
  if event_start is null or pg_catalog.now() < event_start - interval '6 hours'
    or pg_catalog.now() > event_start + interval '30 days' then
    raise exception using errcode = 'P0001', message = 'attendance_window_closed';
  end if;
  update public.event_rsvps r set status = p_status
  where r.event_id = p_event_id and r.user_id = p_profile_id
    and r.status in ('joined', 'tentative', 'attended', 'no_show');
  if not found then
    raise exception using errcode = 'P0001', message = 'attendee_not_found';
  end if;
  return true;
end;
$$;

create function public.update_event_series_v1(
  p_event_id uuid, p_scope text,
  p_title text, p_description text, p_category text,
  p_venue_name text, p_address text,
  p_latitude double precision, p_longitude double precision,
  p_start_at timestamptz, p_end_at timestamptz,
  p_max_participants integer, p_beginner_friendly boolean,
  p_wheelchair_accessible boolean, p_event_setting text,
  p_event_language text, p_age_guidance text, p_what_to_bring text,
  p_status text, p_visibility text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  anchor public.events%rowtype;
  target record;
  shifted_start timestamptz;
  shifted_end timestamptz;
  updated_count integer := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_scope not in ('this', 'future', 'all') then
    raise exception using errcode = '22023', message = 'series_scope_validation';
  end if;
  select e.* into anchor from public.events e
  where e.id = p_event_id and public._can_manage_event(e.id, auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  for target in
    select e.id, e.start_at, e.end_at from public.events e
    where e.status in ('draft', 'published') and e.start_at > pg_catalog.now()
      and public._can_manage_event(e.id, auth.uid())
      and (
        e.id = p_event_id
        or (p_scope <> 'this' and anchor.series_id is not null
          and e.series_id = anchor.series_id
          and (p_scope = 'all' or e.start_at >= anchor.start_at))
      )
    order by e.start_at
  loop
    shifted_start := p_start_at + (target.start_at - anchor.start_at);
    shifted_end := shifted_start + (p_end_at - p_start_at);
    perform public.update_own_event_v3(
      target.id, p_title, p_description, p_category, p_venue_name, p_address,
      p_latitude, p_longitude, shifted_start, shifted_end,
      p_max_participants, p_beginner_friendly, p_wheelchair_accessible,
      p_event_setting, p_event_language, p_age_guidance, p_what_to_bring,
      p_status, p_visibility
    );
    updated_count := updated_count + 1;
  end loop;
  return updated_count;
end;
$$;

create function public.get_event_discussion_last_seen(p_event_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare seen_at timestamptz;
begin
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

create function public.mark_event_discussion_seen(p_event_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare seen_at timestamptz := pg_catalog.now();
begin
  perform public.get_event_discussion_last_seen(p_event_id);
  insert into public.event_discussion_reads (user_id, event_id, last_seen_at)
  values (auth.uid(), p_event_id, seen_at)
  on conflict (user_id, event_id) do update set last_seen_at = excluded.last_seen_at;
  return seen_at;
end;
$$;

create function public.list_my_reports()
returns table (
  report_kind text, report_id uuid, reason text, status text,
  target_title text, created_at timestamptz
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
  select q.report_kind, q.report_id, q.reason, q.status,
    q.target_title, q.created_at
  from (
    select 'event'::text, r.id, r.reason, r.status, e.title, r.created_at
    from public.reports r join public.events e on e.id = r.event_id
    where r.reporter_id = auth.uid()
    union all
    select case when f.post_id is null then 'forum_comment' else 'forum_post' end,
      f.id, f.reason, f.status, coalesce(p.title, 'Forum comment'), f.created_at
    from public.forum_reports f
    left join public.forum_posts p on p.id = f.post_id
    where f.reporter_id = auth.uid()
    union all
    select 'discussion'::text, d.id, d.reason, d.status, e.title, d.created_at
    from public.event_discussion_reports d
    join public.event_discussion_messages m on m.id = d.message_id
    join public.events e on e.id = m.event_id
    where d.reporter_id = auth.uid()
  ) q(report_kind, report_id, reason, status, target_title, created_at)
  order by q.created_at desc, q.report_id;
end;
$$;

create function public.moderation_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public._is_moderator() then
    raise exception using errcode = '42501', message = 'moderator_required';
  end if;
  return pg_catalog.jsonb_build_object(
    'open', (select pg_catalog.count(*) from (
      select id from public.reports where status = 'open'
      union all select id from public.forum_reports where status = 'open'
      union all select id from public.event_discussion_reports where status = 'open'
    ) reports),
    'reviewing', (select pg_catalog.count(*) from (
      select id from public.reports where status = 'reviewing'
      union all select id from public.forum_reports where status = 'reviewing'
      union all select id from public.event_discussion_reports where status = 'reviewing'
    ) reports),
    'resolved_today', (select pg_catalog.count(*) from public.moderation_actions a
      where a.action in ('resolved', 'dismissed', 'hidden')
        and a.created_at >= pg_catalog.date_trunc('day', pg_catalog.now()))
  );
end;
$$;

create function public.list_moderation_reports(p_status text default 'open')
returns table (
  report_kind text, report_id uuid, reason text, status text,
  target_title text, excerpt text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public._is_moderator() then
    raise exception using errcode = '42501', message = 'moderator_required';
  end if;
  if p_status not in ('open', 'reviewing', 'resolved', 'dismissed', 'all') then
    raise exception using errcode = '22023', message = 'moderation_status_validation';
  end if;
  return query
  select q.report_kind, q.report_id, q.reason, q.status,
    q.target_title, q.excerpt, q.created_at
  from (
    select 'event'::text, r.id, r.reason, r.status, e.title,
      pg_catalog.left(e.description, 240), r.created_at
    from public.reports r join public.events e on e.id = r.event_id
    where p_status = 'all' or r.status = p_status
    union all
    select case when f.post_id is null then 'forum_comment' else 'forum_post' end,
      f.id, f.reason, f.status, coalesce(p.title, 'Forum comment'),
      pg_catalog.left(coalesce(p.body, c.body, ''), 240), f.created_at
    from public.forum_reports f
    left join public.forum_posts p on p.id = f.post_id
    left join public.forum_comments c on c.id = f.comment_id
    where p_status = 'all' or f.status = p_status
    union all
    select 'discussion'::text, d.id, d.reason, d.status, e.title,
      pg_catalog.left(m.body, 240), d.created_at
    from public.event_discussion_reports d
    join public.event_discussion_messages m on m.id = d.message_id
    join public.events e on e.id = m.event_id
    where p_status = 'all' or d.status = p_status
  ) q(report_kind, report_id, reason, status, target_title, excerpt, created_at)
  order by q.created_at desc, q.report_id;
end;
$$;

create function public.moderate_report(
  p_report_kind text, p_report_id uuid, p_action text, p_note text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare target_id uuid;
declare normalized_status text;
begin
  if not public._is_moderator() then
    raise exception using errcode = '42501', message = 'moderator_required';
  end if;
  if p_report_kind not in ('event', 'forum_post', 'forum_comment', 'discussion')
    or p_action not in ('reviewing', 'resolved', 'dismissed', 'hidden')
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_note, ''))) > 1000 then
    raise exception using errcode = '22023', message = 'moderation_action_validation';
  end if;
  normalized_status := case when p_action = 'hidden' then 'resolved' else p_action end;
  if p_report_kind = 'event' then
    update public.reports r set status = normalized_status
      where r.id = p_report_id returning r.event_id into target_id;
    if p_action = 'hidden' and target_id is not null then
      insert into public.member_notifications (user_id, event_id, kind, title, body)
      select recipients.user_id, target_id, 'event_cancelled', 'Event removed',
        'An event in your plans was removed after a safety review.'
      from (
        select r.user_id from public.event_rsvps r
        where r.event_id = target_id
          and r.status in ('joined', 'tentative', 'waitlisted')
        union
        select s.user_id from public.event_saves s where s.event_id = target_id
      ) recipients
      on conflict do nothing;
      update public.events e set status = 'cancelled' where e.id = target_id;
    end if;
  elsif p_report_kind in ('forum_post', 'forum_comment') then
    update public.forum_reports r set status = normalized_status
      where r.id = p_report_id
      returning coalesce(r.post_id, r.comment_id) into target_id;
    if p_action = 'hidden' and target_id is not null then
      if p_report_kind = 'forum_post' then
        update public.forum_posts p set status = 'hidden' where p.id = target_id;
      else
        update public.forum_comments c set status = 'hidden' where c.id = target_id;
      end if;
    end if;
  else
    update public.event_discussion_reports r set status = normalized_status
      where r.id = p_report_id returning r.message_id into target_id;
    if p_action = 'hidden' and target_id is not null then
      update public.event_discussion_messages m set status = 'hidden'
        where m.id = target_id;
    end if;
  end if;
  if target_id is null then
    raise exception using errcode = 'P0001', message = 'report_not_found';
  end if;
  insert into public.moderation_actions (
    moderator_id, report_kind, report_id, action, note
  ) values (
    auth.uid(), p_report_kind, p_report_id, p_action,
    pg_catalog.btrim(coalesce(p_note, ''))
  );
  return true;
end;
$$;

create function public.export_own_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return pg_catalog.jsonb_build_object(
    'exported_at', pg_catalog.now(),
    'profile', (select pg_catalog.to_jsonb(p) - 'avatar_image_key'
      from public.profiles p where p.id = auth.uid()),
    'hosted_events', coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.to_jsonb(e) - 'location' - 'embedding' - 'search_document'
    )
      from public.events e where e.organizer_id = auth.uid()), '[]'::jsonb),
    'rsvps', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from public.event_rsvps r where r.user_id = auth.uid()), '[]'::jsonb),
    'saved_events', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s))
      from public.event_saves s where s.user_id = auth.uid()), '[]'::jsonb),
    'event_reminders', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from public.event_reminders r where r.user_id = auth.uid()), '[]'::jsonb),
    'event_announcements', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a))
      from public.event_announcements a where a.author_id = auth.uid()), '[]'::jsonb),
    'event_discussion_messages', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(m))
      from public.event_discussion_messages m where m.author_id = auth.uid()), '[]'::jsonb),
    'event_feedback', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(f))
      from public.event_feedback f where f.user_id = auth.uid()), '[]'::jsonb),
    'cohosted_events', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c))
      from public.event_cohosts c where c.profile_id = auth.uid()), '[]'::jsonb),
    'saved_searches', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s))
      from public.saved_event_searches s where s.user_id = auth.uid()), '[]'::jsonb),
    'forum_posts', coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.to_jsonb(p) - 'image_key' - 'embedding' - 'search_document'
    )
      from public.forum_posts p where p.author_id = auth.uid()), '[]'::jsonb),
    'forum_comments', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c))
      from public.forum_comments c where c.author_id = auth.uid()), '[]'::jsonb),
    'forum_likes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(l))
      from public.forum_post_likes l where l.user_id = auth.uid()), '[]'::jsonb),
    'assistant_messages', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(m))
      from public.assistant_messages m where m.user_id = auth.uid()), '[]'::jsonb),
    'notifications', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(n))
      from public.member_notifications n where n.user_id = auth.uid()), '[]'::jsonb),
    'following', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(f))
      from public.profile_follows f where f.follower_id = auth.uid()), '[]'::jsonb),
    'blocked_members', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(b))
      from public.blocks b where b.blocker_id = auth.uid()), '[]'::jsonb),
    'reports', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from public.list_my_reports() r), '[]'::jsonb),
    'notification_preferences', (select pg_catalog.to_jsonb(p)
      from public.member_notification_preferences p where p.user_id = auth.uid()),
    'event_notification_preferences', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p))
      from public.event_notification_preferences p where p.user_id = auth.uid()), '[]'::jsonb),
    'recommendation_preferences', (select pg_catalog.to_jsonb(p)
      from public.recommendation_preferences p where p.user_id = auth.uid()),
    'hidden_recommendations', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(h))
      from public.hidden_recommendation_content h where h.user_id = auth.uid()), '[]'::jsonb),
    'recommendation_signals', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s))
      from public.recommendation_signals s where s.user_id = auth.uid()), '[]'::jsonb)
  );
end;
$$;

alter table public.ai_tool_usage drop constraint if exists ai_tool_usage_tool_check;
alter table public.ai_tool_usage add constraint ai_tool_usage_tool_check check (
  tool in (
    'event_draft', 'translation', 'summary', 'event_quality',
    'natural_filters', 'discussion_changes', 'moderation_triage'
  )
);

create or replace function public.claim_ai_tool_use(p_tool text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_window timestamptz := pg_catalog.date_trunc('hour', pg_catalog.now());
  tool_limit integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_tool not in (
    'event_draft', 'translation', 'summary', 'event_quality',
    'natural_filters', 'discussion_changes', 'moderation_triage'
  ) then
    raise exception using errcode = '22023', message = 'assistant_validation';
  end if;
  if p_tool = 'moderation_triage' and not public._is_moderator() then
    raise exception using errcode = '42501', message = 'moderator_required';
  end if;
  if not coalesce((select p.assistant_enabled from public.profiles p
    where p.id = current_user_id), false) then
    raise exception using errcode = '42501', message = 'assistant_disabled';
  end if;
  tool_limit := case when p_tool = 'translation' then 20
    when p_tool = 'moderation_triage' then 20 else 10 end;
  insert into public.ai_tool_usage (user_id, tool, window_start, usage_count)
  values (current_user_id, p_tool, current_window, 1)
  on conflict (user_id, tool, window_start) do update
    set usage_count = ai_tool_usage.usage_count + 1
    where ai_tool_usage.usage_count < tool_limit;
  return found;
end;
$$;

revoke all on function public.get_moderation_status() from public, anon;
revoke all on function public.complete_onboarding(text[], text[], double precision, double precision, double precision) from public, anon;
revoke all on function public.get_notification_preferences() from public, anon;
revoke all on function public.update_notification_preferences(boolean, boolean, boolean, boolean, boolean, integer, integer, integer) from public, anon;
revoke all on function public.get_recommendation_preferences() from public, anon;
revoke all on function public.update_recommendation_preferences(boolean, text[]) from public, anon;
revoke all on function public.hide_recommendation(text, uuid) from public, anon;
revoke all on function public.reset_recommendation_controls() from public, anon;
revoke all on function public.list_hidden_recommendation_ids(text) from public, anon;
revoke all on function public.get_event_host_dashboard(uuid) from public, anon;
revoke all on function public.list_event_host_attendees(uuid) from public, anon;
revoke all on function public.set_event_attendance(uuid, uuid, text) from public, anon;
revoke all on function public.update_event_series_v1(uuid, text, text, text, text, text, text, double precision, double precision, timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text, text, text) from public, anon;
revoke all on function public.get_event_discussion_last_seen(uuid) from public, anon;
revoke all on function public.mark_event_discussion_seen(uuid) from public, anon;
revoke all on function public.list_my_reports() from public, anon;
revoke all on function public.moderation_overview() from public, anon;
revoke all on function public.list_moderation_reports(text) from public, anon;
revoke all on function public.moderate_report(text, uuid, text, text) from public, anon;
revoke all on function public.export_own_data() from public, anon;

grant execute on function public.get_moderation_status() to authenticated;
grant execute on function public.complete_onboarding(text[], text[], double precision, double precision, double precision) to authenticated;
grant execute on function public.get_notification_preferences() to authenticated;
grant execute on function public.update_notification_preferences(boolean, boolean, boolean, boolean, boolean, integer, integer, integer) to authenticated;
grant execute on function public.get_recommendation_preferences() to authenticated;
grant execute on function public.update_recommendation_preferences(boolean, text[]) to authenticated;
grant execute on function public.hide_recommendation(text, uuid) to authenticated;
grant execute on function public.reset_recommendation_controls() to authenticated;
grant execute on function public.list_hidden_recommendation_ids(text) to authenticated;
grant execute on function public.get_event_host_dashboard(uuid) to authenticated;
grant execute on function public.list_event_host_attendees(uuid) to authenticated;
grant execute on function public.set_event_attendance(uuid, uuid, text) to authenticated;
grant execute on function public.update_event_series_v1(uuid, text, text, text, text, text, text, double precision, double precision, timestamptz, timestamptz, integer, boolean, boolean, text, text, text, text, text, text) to authenticated;
grant execute on function public.get_event_discussion_last_seen(uuid) to authenticated;
grant execute on function public.mark_event_discussion_seen(uuid) to authenticated;
grant execute on function public.list_my_reports() to authenticated;
grant execute on function public.moderation_overview() to authenticated;
grant execute on function public.list_moderation_reports(text) to authenticated;
grant execute on function public.moderate_report(text, uuid, text, text) to authenticated;
grant execute on function public.export_own_data() to authenticated;

comment on function public.complete_onboarding is
  'Atomically stores bounded onboarding preferences and approximate discovery location.';
comment on function public._push_notification_allowed is
  'Applies global push, category, timezone, and quiet-hour preferences at delivery time.';
comment on function public.moderate_report is
  'Performs an app-metadata-gated moderation action and appends an audit record.';
comment on function public.export_own_data is
  'Returns a portable JSON snapshot of the authenticated member data without device tokens.';
