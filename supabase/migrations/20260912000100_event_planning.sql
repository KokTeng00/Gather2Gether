-- Practical event planning. All writes remain transactional and user scoped.
alter table public.events
  add column meeting_instructions text not null default '' check (char_length(meeting_instructions) <= 500),
  add column meeting_latitude double precision check (meeting_latitude between -90 and 90),
  add column meeting_longitude double precision check (meeting_longitude between -180 and 180),
  add column meeting_image_key text,
  add column allow_guest boolean not null default false,
  add column invite_preview_enabled boolean not null default false,
  add column preview_area text not null default '' check (char_length(preview_area) <= 120),
  add column timezone_offset_minutes integer not null default 0 check (timezone_offset_minutes between -840 and 840),
  add constraint meeting_coordinates_pair check ((meeting_latitude is null) = (meeting_longitude is null));
alter table public.event_rsvps add column guest_count integer not null default 0 check (guest_count between 0 and 1);

create table public.forum_planning_polls (
  post_id uuid primary key references public.forum_posts(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.forum_poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.forum_planning_polls(post_id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null check (end_at > start_at),
  unique (post_id, start_at),
  unique (post_id, id)
);
create table public.forum_poll_votes (
  post_id uuid not null,
  option_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (option_id, user_id),
  foreign key (post_id, option_id) references public.forum_poll_options(post_id, id) on delete cascade
);
alter table public.forum_planning_polls enable row level security;
alter table public.forum_poll_options enable row level security;
alter table public.forum_poll_votes enable row level security;
revoke all on public.forum_planning_polls, public.forum_poll_options, public.forum_poll_votes from public, anon, authenticated;

create function public._event_places(p_event_id uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(sum(1 + r.guest_count), 0)::bigint
  from public.event_rsvps r where r.event_id = p_event_id and r.status in ('joined', 'attended');
$$;
revoke all on function public._event_places(uuid) from public, anon, authenticated;

-- Protect every existing editor and old mobile client from understating capacity.
create function public._guard_event_places()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.max_participants < public._event_places(new.id) then
    raise exception using errcode = '22023', message = 'capacity_below_attendance';
  end if;
  if not new.allow_guest and exists (select 1 from public.event_rsvps r
    where r.event_id = new.id and r.guest_count > 0 and r.status in ('joined', 'attended', 'waitlisted', 'tentative')) then
    raise exception using errcode = '22023', message = 'guests_already_registered';
  end if;
  return new;
end;
$$;
revoke all on function public._guard_event_places() from public, anon, authenticated;
create trigger events_guard_places before update on public.events
  for each row execute function public._guard_event_places();

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

create function public.set_event_rsvp_with_guest(p_event_id uuid, p_status text, p_guest_count integer)
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
create or replace function public.set_event_rsvp(p_event_id uuid,p_status text)
returns text language sql security definer set search_path = '' as $$
  select public.set_event_rsvp_with_guest(p_event_id,p_status,coalesce((select guest_count from public.event_rsvps where event_id=p_event_id and user_id=auth.uid()),0));
$$;
revoke all on function public.set_event_rsvp_with_guest(uuid,text,integer) from public,anon;
grant execute on function public.set_event_rsvp_with_guest(uuid,text,integer) to authenticated;

-- Early check-in keeps the whole party's places reserved. Host corrections use
-- the same event lock as RSVPs, including when moving a tentative party to going.
create or replace function public.set_event_attendance(p_event_id uuid,p_profile_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target public.events%rowtype; previous public.event_rsvps%rowtype;
begin
  if auth.uid() is null or not public._can_manage_event(p_event_id,auth.uid()) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_status is null or p_status not in ('joined','attended','no_show') then
    raise exception using errcode='22023',message='attendance_validation';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
  select * into target from public.events where id=p_event_id for update;
  if not found or now()<target.start_at-interval '6 hours' or now()>target.start_at+interval '30 days' then
    raise exception using errcode='P0001',message='attendance_window_closed';
  end if;
  select * into previous from public.event_rsvps where event_id=p_event_id and user_id=p_profile_id for update;
  if not found or previous.status not in ('joined','tentative','attended','no_show') then
    raise exception using errcode='P0001',message='attendee_not_found';
  end if;
  if p_status in ('joined','attended') and previous.status not in ('joined','attended')
    and public._event_places(p_event_id)+1+previous.guest_count>target.max_participants then
    raise exception using errcode='P0001',message='guest_place_unavailable';
  end if;
  update public.event_rsvps set status=p_status where event_id=p_event_id and user_id=p_profile_id;
  if p_status='no_show' and previous.status in ('joined','attended') then
    while public._promote_event_waitlist(p_event_id) is not null loop end loop;
  end if;
  return true;
end;
$$;

-- Reuse the existing visibility contract, returning only an authorized event.
create function public.get_event_plan(p_event_id uuid,p_via_invite boolean default false)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object(
    'joined_count',public._event_places(e.id),'guest_count',coalesce(r.guest_count,0),
    'allow_guest',e.allow_guest,'meeting_instructions',e.meeting_instructions,
    'meeting_latitude',e.meeting_latitude,'meeting_longitude',e.meeting_longitude,
    'has_meeting_image',e.meeting_image_key is not null,
    'invite_preview_enabled',e.invite_preview_enabled,'preview_area',e.preview_area,
    'timezone_offset_minutes',e.timezone_offset_minutes)
  from public.get_event_details_v3(p_event_id,p_via_invite) d
  join public.events e on e.id=d.id
  left join public.event_rsvps r on r.event_id=e.id and r.user_id=auth.uid();
$$;
revoke all on function public.get_event_plan(uuid,boolean) from public,anon;
grant execute on function public.get_event_plan(uuid,boolean) to authenticated;

create function public.get_event_plan_extras(p_event_ids uuid[])
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if cardinality(p_event_ids)>200 then raise exception using errcode='22023',message='invalid_parameter'; end if;
  return query select public.get_event_plan(e.id,false) from public.events e
    where e.id=any(p_event_ids) and public.get_event_plan(e.id,false) is not null;
end;
$$;
revoke all on function public.get_event_plan_extras(uuid[]) from public,anon;
grant execute on function public.get_event_plan_extras(uuid[]) to authenticated;

create function public.get_event_meeting_image_key(p_event_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select e.meeting_image_key from public.events e
  where e.id=p_event_id and public.get_event_plan(e.id,true) is not null;
$$;
revoke all on function public.get_event_meeting_image_key(uuid) from public,anon;
grant execute on function public.get_event_meeting_image_key(uuid) to authenticated;

-- Public invitations use an explicit allow-list, never address, pin, photos or attendees.
create function public.get_event_invite_preview(p_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('title',e.title,'description',e.description,'category',e.category,
    'start_at',e.start_at,'end_at',e.end_at,'area',e.preview_area,
    'timezone_offset_minutes',e.timezone_offset_minutes,'cancelled',e.status='cancelled')
  from public.events e where e.id=p_event_id and e.invite_preview_enabled
    and e.status in ('published','cancelled') and e.end_at>now();
$$;
revoke all on function public.get_event_invite_preview(uuid) from public;
grant execute on function public.get_event_invite_preview(uuid) to anon,authenticated;

create function public.list_event_conflicts(p_event_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare target public.events%rowtype;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if public.get_event_plan(p_event_id,true) is null then raise exception using errcode='42501',message='permission_denied'; end if;
  select * into target from public.events where id=p_event_id;
  return query select jsonb_build_object('id',e.id,'title',e.title,'start_at',e.start_at,'end_at',e.end_at)
  from public.events e where e.id<>p_event_id and e.status='published' and e.end_at>now()
    and e.start_at<target.end_at and e.end_at>target.start_at
    and (public._can_manage_event(e.id,auth.uid()) or exists(select 1 from public.event_rsvps r where r.event_id=e.id and r.user_id=auth.uid() and r.status='joined'))
  order by e.start_at,e.id limit 20;
end;
$$;
revoke all on function public.list_event_conflicts(uuid) from public,anon;
grant execute on function public.list_event_conflicts(uuid) to authenticated;

create table public.event_meeting_images (
  image_key text primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.event_meeting_images enable row level security;
revoke all on public.event_meeting_images from public,anon,authenticated;

create function public.save_event_plan(p_event_id uuid,p_scope text,p_event jsonb,p_details jsonb,p_poll_post_id uuid default null,p_poll_option_id uuid default null)
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[];
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
    update public.events set
      meeting_instructions=coalesce(p_details->>'meeting_instructions',''),
      meeting_latitude=meeting_lat,meeting_longitude=meeting_lon,
      meeting_image_key=case when p_details ? 'meeting_image_key' then image_key else meeting_image_key end,
      allow_guest=coalesce((p_details->>'allow_guest')::boolean,false),
      invite_preview_enabled=coalesce((p_details->>'invite_preview_enabled')::boolean,false),
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
revoke all on function public.save_event_plan(uuid,text,jsonb,jsonb,uuid,uuid) from public,anon;
grant execute on function public.save_event_plan(uuid,text,jsonb,jsonb,uuid,uuid) to authenticated;

create function public.create_forum_post_with_poll(p_title text,p_body text,p_category text,p_image_key text,p_place_name text,p_place_address text,p_options jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare post_id uuid; item jsonb; starts timestamptz; ends timestamptz;
begin
  if jsonb_typeof(p_options) is distinct from 'array' or jsonb_array_length(p_options) not between 2 and 3 then
    raise exception using errcode='22023',message='poll_validation';
  end if;
  post_id := public.create_forum_post(p_title,p_body,p_category,p_image_key,p_place_name,p_place_address);
  insert into public.forum_planning_polls(post_id) values(post_id);
  for item in select * from jsonb_array_elements(p_options) loop
    starts := (item->>'start_at')::timestamptz; ends := (item->>'end_at')::timestamptz;
    if starts is null or ends is null or starts<=now() or starts>now()+interval '1 year' or ends<=starts or ends>starts+interval '1 day' then
      raise exception using errcode='22023',message='poll_validation';
    end if;
    insert into public.forum_poll_options(post_id,start_at,end_at) values(post_id,starts,ends);
  end loop;
  return post_id;
end;
$$;
revoke all on function public.create_forum_post_with_poll(text,text,text,text,text,text,jsonb) from public,anon;
grant execute on function public.create_forum_post_with_poll(text,text,text,text,text,text,jsonb) to authenticated;

create function public.get_forum_poll(p_post_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if not exists(select 1 from public.get_forum_post(p_post_id)) then raise exception using errcode='42501',message='permission_denied'; end if;
  select jsonb_build_object('post_id',poll.post_id,'event_id',poll.event_id,'closed',poll.closed_at is not null,
    'can_vote',post.status='active' and poll.closed_at is null,
    'viewer_is_author',post.author_id=auth.uid(),'options',coalesce((
      select jsonb_agg(jsonb_build_object('id',o.id,'start_at',o.start_at,'end_at',o.end_at,
        'vote_count',(select count(*) from public.forum_poll_votes v where v.option_id=o.id and not exists(select 1 from public.blocks b where
          (b.blocker_id=auth.uid() and b.blocked_id=v.user_id) or (b.blocked_id=auth.uid() and b.blocker_id=v.user_id))),
        'voted',exists(select 1 from public.forum_poll_votes v where v.option_id=o.id and v.user_id=auth.uid())) order by o.start_at)
      from public.forum_poll_options o where o.post_id=poll.post_id),'[]'::jsonb)) into result
  from public.forum_planning_polls poll join public.forum_posts post on post.id=poll.post_id where poll.post_id=p_post_id;
  return result;
end;
$$;
revoke all on function public.get_forum_poll(uuid) from public,anon;
grant execute on function public.get_forum_poll(uuid) to authenticated;

create function public.set_forum_poll_vote(p_post_id uuid,p_option_id uuid,p_available boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare poll public.forum_planning_polls%rowtype;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if p_available is null then raise exception using errcode='22023',message='poll_validation'; end if;
  select * into poll from public.forum_planning_polls where post_id=p_post_id for update;
  if not found or not exists(select 1 from public.get_forum_post(p_post_id) p where p.status='active') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if poll.closed_at is not null then raise exception using errcode='P0001',message='poll_closed'; end if;
  if not exists(select 1 from public.forum_poll_options where post_id=p_post_id and id=p_option_id and start_at>now()) then
    raise exception using errcode='22023',message='poll_option_unavailable';
  end if;
  if p_available then
    insert into public.forum_poll_votes(post_id,option_id,user_id) values(p_post_id,p_option_id,auth.uid()) on conflict do nothing;
  else delete from public.forum_poll_votes where post_id=p_post_id and option_id=p_option_id and user_id=auth.uid(); end if;
  return public.get_forum_poll(p_post_id);
end;
$$;
revoke all on function public.set_forum_poll_vote(uuid,uuid,boolean) from public,anon;
grant execute on function public.set_forum_poll_vote(uuid,uuid,boolean) to authenticated;

create function public.get_forum_poll_ids(p_post_ids uuid[])
returns uuid[] language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if cardinality(p_post_ids)>100 then raise exception using errcode='22023',message='invalid_parameter'; end if;
  return coalesce((select array_agg(p.post_id) from public.forum_planning_polls p
    where p.post_id=any(p_post_ids) and exists(select 1 from public.get_forum_post(p.post_id))),array[]::uuid[]);
end;
$$;
revoke all on function public.get_forum_poll_ids(uuid[]) from public,anon;
grant execute on function public.get_forum_poll_ids(uuid[]) to authenticated;

create function public.discover_event_plans(p_latitude double precision,p_longitude double precision,p_radius_km double precision,p_filters jsonb)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  center_point extensions.geography;
  starts timestamptz := (p_filters->>'start_from')::timestamptz;
  ends timestamptz := (p_filters->>'start_before')::timestamptz;
  search_text text := nullif(trim(p_filters->>'interest'),'');
  offset_minutes integer := coalesce((p_filters->>'timezone_offset_minutes')::integer,0);
  query_embedding extensions.vector(384) := (nullif(p_filters->>'query_embedding','null'))::extensions.vector(384);
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if p_latitude is null or p_longitude is null or p_radius_km is null or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180 or p_radius_km not between 1 and 100
    or ends<=starts or offset_minutes not between -840 and 840 or char_length(search_text)>240 then
    raise exception using errcode='22023',message='invalid_parameter';
  end if;
  center_point := extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326)::extensions.geography;
  return query select public.get_event_plan(e.id,false) || jsonb_build_object('distance_meters',extensions.st_distance(e.location,center_point))
  from public.events e
  where e.status='published' and e.visibility='public' and e.start_at>now()
    and extensions.st_dwithin(e.location,center_point,p_radius_km*1000)
    and (starts is null or e.start_at>=starts) and (ends is null or e.start_at<ends)
    and (nullif(p_filters->>'category','') is null or e.category=p_filters->>'category')
    and (not coalesce((p_filters->>'spots_only')::boolean,false) or public._event_places(e.id)<e.max_participants)
    and (not coalesce((p_filters->>'following_only')::boolean,false) or exists(select 1 from public.profile_follows f where f.follower_id=auth.uid() and f.followed_id=e.organizer_id))
    and (not coalesce((p_filters->>'beginner_friendly_only')::boolean,false) or e.beginner_friendly)
    and (not coalesce((p_filters->>'wheelchair_accessible_only')::boolean,false) or e.wheelchair_accessible)
    and (coalesce(p_filters->>'event_setting','any')='any' or e.event_setting=p_filters->>'event_setting')
    and (nullif(p_filters->>'event_language','') is null or lower(e.event_language)=lower(p_filters->>'event_language'))
    and (coalesce(p_filters->>'age_guidance','any')='any' or e.age_guidance=p_filters->>'age_guidance')
    and (coalesce(p_filters->>'time_filter','any')='any' or case p_filters->>'time_filter'
      when 'morning' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins=>offset_minutes))>=5 and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins=>offset_minutes))<12
      when 'afternoon' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins=>offset_minutes))>=12 and extract(hour from e.start_at at time zone 'UTC' + make_interval(mins=>offset_minutes))<17
      when 'evening' then extract(hour from e.start_at at time zone 'UTC' + make_interval(mins=>offset_minutes))>=17 else false end)
    and (search_text is null or (query_embedding is not null and e.embedding is not null) or e.search_document @@ websearch_to_tsquery('english',search_text)
      or strpos(lower(e.title || ' ' || e.category || ' ' || e.venue_name || ' ' || e.address || ' ' || e.description),lower(search_text))>0)
    and not exists(select 1 from public.blocks b where (b.blocker_id=auth.uid() and b.blocked_id=e.organizer_id) or (b.blocked_id=auth.uid() and b.blocker_id=e.organizer_id))
    and not exists(select 1 from public.hidden_recommendation_content h where h.user_id=auth.uid() and h.content_kind='event' and h.content_id=e.id)
    and not exists(select 1 from public.recommendation_preferences rp where rp.user_id=auth.uid() and e.category=any(rp.hidden_categories))
  order by case when search_text is not null then (case when e.search_document @@ websearch_to_tsquery('english',search_text) then 1.0 else 0.0 end + coalesce(1 - (e.embedding operator(extensions.<=>) query_embedding), 0)) end desc,
    e.start_at,extensions.st_distance(e.location,center_point),e.id
  limit 60;
end;
$$;
revoke all on function public.discover_event_plans(double precision,double precision,double precision,jsonb) from public,anon;
grant execute on function public.discover_event_plans(double precision,double precision,double precision,jsonb) to authenticated;

alter table public.saved_event_searches
  add column search_latitude double precision check (search_latitude between -90 and 90),
  add column search_longitude double precision check (search_longitude between -180 and 180),
  add column search_area text not null default '' check (char_length(search_area)<=160),
  add column custom_start timestamptz,
  add column custom_end timestamptz,
  add constraint saved_search_coordinates_pair check ((search_latitude is null)=(search_longitude is null)),
  add constraint saved_search_dates_pair check ((custom_start is null)=(custom_end is null) and (custom_end is null or custom_end>custom_start));
create function public.list_saved_event_search_plans()
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  return query select (to_jsonb(s)-'user_id') || jsonb_build_object('date_filter',case when s.custom_start is not null then 'custom' else s.date_filter end)
  from public.saved_event_searches s where s.user_id=auth.uid() order by s.created_at desc,s.id;
end;
$$;
revoke all on function public.list_saved_event_search_plans() from public,anon;
grant execute on function public.list_saved_event_search_plans() to authenticated;
create function public.save_event_search_plan(p_search_id uuid,p_input jsonb,p_context jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare search_id uuid; updated boolean;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if jsonb_typeof(p_context) is distinct from 'object' then raise exception using errcode='22023',message='saved_search_validation'; end if;
  if p_search_id is null then
    search_id := public.create_saved_event_search(
      (p_input->>'p_name')::text,
      (p_input->>'p_interest')::text,
      (p_input->>'p_radius_km')::double precision,
      (p_input->>'p_category')::text,
      (p_input->>'p_date_filter')::text,
      (p_input->>'p_time_filter')::text,
      (p_input->>'p_timezone_offset_minutes')::integer,
      (p_input->>'p_spots_only')::boolean,
      (p_input->>'p_following_only')::boolean,
      (p_input->>'p_beginner_friendly_only')::boolean,
      (p_input->>'p_wheelchair_accessible_only')::boolean,
      (p_input->>'p_event_setting')::text,
      (p_input->>'p_event_language')::text,
      (p_input->>'p_age_guidance')::text,
      (p_input->>'p_alerts_enabled')::boolean);
  else
    updated := public.update_saved_event_search(p_search_id,
      (p_input->>'p_name')::text,
      (p_input->>'p_interest')::text,
      (p_input->>'p_radius_km')::double precision,
      (p_input->>'p_category')::text,
      (p_input->>'p_date_filter')::text,
      (p_input->>'p_time_filter')::text,
      (p_input->>'p_timezone_offset_minutes')::integer,
      (p_input->>'p_spots_only')::boolean,
      (p_input->>'p_following_only')::boolean,
      (p_input->>'p_beginner_friendly_only')::boolean,
      (p_input->>'p_wheelchair_accessible_only')::boolean,
      (p_input->>'p_event_setting')::text,
      (p_input->>'p_event_language')::text,
      (p_input->>'p_age_guidance')::text,
      (p_input->>'p_alerts_enabled')::boolean);
    if not updated then raise exception using errcode='42501',message='permission_denied'; end if;
    search_id := p_search_id;
  end if;
  update public.saved_event_searches set
    search_latitude=(p_context->>'latitude')::double precision, search_longitude=(p_context->>'longitude')::double precision,
    search_area=coalesce(p_context->>'area',''),custom_start=(p_context->>'start_from')::timestamptz,custom_end=(p_context->>'start_before')::timestamptz
  where id=search_id and user_id=auth.uid();
  return search_id;
end;
$$;
revoke all on function public.save_event_search_plan(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.save_event_search_plan(uuid,jsonb,jsonb) to authenticated;

create or replace function public._notify_for_new_event()
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
    new.title || ' matches your saved search.'
  from public.saved_event_searches s
  join public.profiles p on p.id = s.user_id
  where s.alerts_enabled
    and s.user_id <> new.organizer_id
    and (s.custom_start is null or new.start_at>=s.custom_start)
    and (s.custom_end is null or new.start_at<s.custom_end)
    and coalesce(s.search_latitude,p.approximate_latitude) is not null
    and coalesce(s.search_longitude,p.approximate_longitude) is not null
    and extensions.st_dwithin(
      new.location,
      extensions.st_setsrid(
        extensions.st_makepoint(coalesce(s.search_longitude,p.approximate_longitude), coalesce(s.search_latitude,p.approximate_latitude)),
        4326
      )::extensions.geography,
      s.radius_km * 1000
    )
    and (s.category is null or s.category = new.category)
    and (not s.beginner_friendly_only or new.beginner_friendly)
    and (not s.wheelchair_accessible_only or new.wheelchair_accessible)
    and (s.event_setting = 'any' or s.event_setting = new.event_setting)
    and (
      s.event_language = ''
      or pg_catalog.lower(s.event_language) = pg_catalog.lower(new.event_language)
    )
    and (s.age_guidance = 'any' or s.age_guidance = new.age_guidance)
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
        pg_catalog.date_part(
          'isodow',
          new.start_at + pg_catalog.make_interval(mins => s.timezone_offset_minutes)
        ) in (6, 7)
        and new.start_at < pg_catalog.now() + interval '7 days'
      else true
    end
    and case s.time_filter
      when 'morning' then pg_catalog.date_part('hour', new.start_at + pg_catalog.make_interval(mins => s.timezone_offset_minutes)) between 5 and 11
      when 'afternoon' then pg_catalog.date_part('hour', new.start_at + pg_catalog.make_interval(mins => s.timezone_offset_minutes)) between 12 and 16
      when 'evening' then pg_catalog.date_part('hour', new.start_at + pg_catalog.make_interval(mins => s.timezone_offset_minutes)) between 17 and 23
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

create or replace function public.export_own_data()
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
    'poll_votes', coalesce((select jsonb_agg(to_jsonb(v)) from public.forum_poll_votes v where v.user_id=auth.uid()),'[]'::jsonb),
    'planning_polls', coalesce((select jsonb_agg(to_jsonb(poll)) from public.forum_planning_polls poll join public.forum_posts p on p.id=poll.post_id where p.author_id=auth.uid()),'[]'::jsonb),
    'exported_at', pg_catalog.now(),
    'profile', (select pg_catalog.to_jsonb(p) - 'avatar_image_key'
      from public.profiles p where p.id = auth.uid()),
    'hosted_events', coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.to_jsonb(e) - 'location' - 'embedding' - 'search_document' - 'meeting_image_key'
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

create or replace function public.delete_own_account(p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  avatar_key text;
  post_keys text[];
  result jsonb;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_confirmation is distinct from 'DELETE' then
    raise exception using errcode = '22023', message = 'account_deletion_confirmation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delete-account:' || current_user_id::text, 0)
  );
  select p.avatar_image_key into avatar_key
  from public.profiles p
  where p.id = current_user_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  select coalesce(
    pg_catalog.array_agg(p.image_key order by p.id)
      filter (where p.image_key is not null),
    array[]::text[]
  ) into post_keys
  from public.forum_posts p
  where p.author_id = current_user_id;

  result := pg_catalog.jsonb_build_object(
    'avatar_image_key', avatar_key,
    'forum_image_keys', post_keys,
    'event_image_keys', coalesce((select jsonb_agg(image_key) from public.event_meeting_images where owner_id=current_user_id),'[]'::jsonb)
  );

  update public.events set meeting_image_key=null where meeting_image_key in (select image_key from public.event_meeting_images where owner_id=current_user_id);
  -- Hosted events must be removed first because the organizer foreign key is
  -- deliberately restrictive. Event-owned rows then disappear by cascade.
  delete from public.events e where e.organizer_id = current_user_id;
  delete from auth.users u where u.id = current_user_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;
  return result;
end;
$$;

create or replace function public.get_event_host_dashboard(p_event_id uuid)
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
    'joined', coalesce(pg_catalog.sum(1+r.guest_count) filter (where r.status = 'joined'),0),
    'tentative', coalesce(pg_catalog.sum(1+r.guest_count) filter (where r.status = 'tentative'),0),
    'waitlisted', coalesce(pg_catalog.sum(1+r.guest_count) filter (where r.status = 'waitlisted'),0),
    'attended', coalesce(pg_catalog.sum(1+r.guest_count) filter (where r.status = 'attended'),0),
    'no_show', coalesce(pg_catalog.sum(1+r.guest_count) filter (where r.status = 'no_show'),0),
    'saved', (select pg_catalog.count(*) from public.event_saves s where s.event_id = p_event_id),
    'feedback_count', (select pg_catalog.count(*) from public.event_feedback f where f.event_id = p_event_id),
    'average_rating', (select pg_catalog.round(pg_catalog.avg(f.rating), 1)
      from public.event_feedback f where f.event_id = p_event_id and f.rating is not null)
  ) into result
  from public.event_rsvps r where r.event_id = p_event_id;
  return result;
end;
$$;
create function public.list_event_host_parties(p_event_id uuid)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(a)||jsonb_build_object('guest_count',r.guest_count) from public.list_event_host_attendees(p_event_id) a
  join public.event_rsvps r on r.event_id=p_event_id and r.user_id=a.profile_id;
$$;
revoke all on function public.list_event_host_parties(uuid) from public,anon;
grant execute on function public.list_event_host_parties(uuid) to authenticated;
