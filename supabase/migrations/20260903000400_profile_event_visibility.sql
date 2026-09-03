-- Surface upcoming hosted events on member profiles and let each member decide
-- whether confirmed past activity is visible to other authenticated members.
-- Past activity is private by default and privacy is enforced inside the RPC.

alter table public.profiles
  add column show_past_events_public boolean not null default false;

grant select (show_past_events_public) on public.profiles to authenticated;
grant update (show_past_events_public) on public.profiles to authenticated;

drop function public.get_public_profile(uuid);

create function public.get_public_profile(p_profile_id uuid)
returns table (
  id uuid,
  display_name text,
  username text,
  bio text,
  city text,
  has_avatar boolean,
  avatar_version timestamptz,
  followers_count bigint,
  following_count bigint,
  viewer_is_following boolean,
  viewer_is_self boolean,
  past_events_public boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.username,
    p.bio,
    p.city,
    p.avatar_image_key is not null,
    p.updated_at,
    (select pg_catalog.count(*) from public.profile_follows f where f.followed_id = p.id),
    (select pg_catalog.count(*) from public.profile_follows f where f.follower_id = p.id),
    exists (
      select 1
      from public.profile_follows f
      where f.follower_id = current_user_id and f.followed_id = p.id
    ),
    p.id = current_user_id,
    p.show_past_events_public
  from public.profiles p
  where p.id = p_profile_id;
end;
$$;

create function public.list_profile_events(
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
    (current_user_id = p_profile_id or e.visibility = 'public')
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

revoke all on function public.get_public_profile(uuid)
  from public, anon, authenticated;
revoke all on function public.list_profile_events(uuid, text)
  from public, anon, authenticated;

grant execute on function public.get_public_profile(uuid) to authenticated;
grant execute on function public.list_profile_events(uuid, text) to authenticated;

comment on column public.profiles.show_past_events_public is
  'Opt-in visibility for confirmed attended and hosted past events on public profiles.';
comment on function public.list_profile_events(uuid, text) is
  'Lists profile events while enforcing blocks, event visibility, and owner-controlled past privacy.';
