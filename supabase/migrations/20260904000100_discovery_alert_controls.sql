-- Make the practical event attributes usable during discovery and let members
-- rename, update, pause, and resume saved-search alerts.

alter table public.saved_event_searches
  add column beginner_friendly_only boolean not null default false,
  add column wheelchair_accessible_only boolean not null default false,
  add column event_setting text not null default 'any' check (
    event_setting in ('any', 'indoor', 'outdoor', 'mixed')
  ),
  add column event_language text not null default '' check (
    pg_catalog.char_length(event_language) <= 80
  ),
  add column age_guidance text not null default 'any' check (
    age_guidance in ('any', 'all_ages', 'families', 'teens', 'adults')
  );

create function public.filter_event_ids_by_details(
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
    and e.visibility = 'public'
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

drop function public.list_saved_event_searches();
create function public.list_saved_event_searches()
returns table (
  id uuid, name text, interest text, radius_km double precision,
  category text, date_filter text, time_filter text, spots_only boolean,
  following_only boolean, beginner_friendly_only boolean,
  wheelchair_accessible_only boolean, event_setting text,
  event_language text, age_guidance text, alerts_enabled boolean,
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
    s.time_filter, s.spots_only, s.following_only,
    s.beginner_friendly_only, s.wheelchair_accessible_only, s.event_setting,
    s.event_language, s.age_guidance, s.alerts_enabled,
    s.timezone_offset_minutes, s.created_at
  from public.saved_event_searches s
  where s.user_id = auth.uid()
  order by s.created_at desc, s.id;
end;
$$;

drop function public.create_saved_event_search(
  text, text, double precision, text, text, text, integer, boolean, boolean
);
create function public.create_saved_event_search(
  p_name text,
  p_interest text,
  p_radius_km double precision,
  p_category text,
  p_date_filter text,
  p_time_filter text,
  p_timezone_offset_minutes integer,
  p_spots_only boolean,
  p_following_only boolean,
  p_beginner_friendly_only boolean,
  p_wheelchair_accessible_only boolean,
  p_event_setting text,
  p_event_language text,
  p_age_guidance text,
  p_alerts_enabled boolean
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
  if pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 80
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_interest, ''))) > 240
    or p_radius_km not between 1 and 100
    or (p_category is not null and pg_catalog.char_length(pg_catalog.btrim(p_category)) not between 2 and 60)
    or p_date_filter not in ('any', 'today', 'tomorrow', 'weekend')
    or p_time_filter not in ('any', 'morning', 'afternoon', 'evening')
    or p_timezone_offset_minutes not between -840 and 840
    or p_event_setting not in ('any', 'indoor', 'outdoor', 'mixed')
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_event_language, ''))) > 80
    or p_age_guidance not in ('any', 'all_ages', 'families', 'teens', 'adults') then
    raise exception using errcode = '22023', message = 'saved_search_validation';
  end if;
  if (
    select pg_catalog.count(*) from public.saved_event_searches s
    where s.user_id = auth.uid()
  ) >= 12 and not exists (
    select 1 from public.saved_event_searches s
    where s.user_id = auth.uid() and s.name = pg_catalog.btrim(p_name)
  ) then
    raise exception using errcode = 'P0001', message = 'saved_search_limit';
  end if;

  insert into public.saved_event_searches (
    user_id, name, interest, radius_km, category, date_filter, time_filter,
    timezone_offset_minutes, spots_only, following_only,
    beginner_friendly_only, wheelchair_accessible_only, event_setting,
    event_language, age_guidance, alerts_enabled
  ) values (
    auth.uid(), pg_catalog.btrim(p_name),
    pg_catalog.btrim(coalesce(p_interest, '')), p_radius_km,
    nullif(pg_catalog.btrim(coalesce(p_category, '')), ''),
    p_date_filter, p_time_filter, p_timezone_offset_minutes, p_spots_only,
    p_following_only, p_beginner_friendly_only,
    p_wheelchair_accessible_only, p_event_setting,
    pg_catalog.btrim(coalesce(p_event_language, '')),
    p_age_guidance, p_alerts_enabled
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
    beginner_friendly_only = excluded.beginner_friendly_only,
    wheelchair_accessible_only = excluded.wheelchair_accessible_only,
    event_setting = excluded.event_setting,
    event_language = excluded.event_language,
    age_guidance = excluded.age_guidance,
    alerts_enabled = excluded.alerts_enabled
  returning id into search_id;
  return search_id;
end;
$$;

create function public.update_saved_event_search(
  p_search_id uuid,
  p_name text,
  p_interest text,
  p_radius_km double precision,
  p_category text,
  p_date_filter text,
  p_time_filter text,
  p_timezone_offset_minutes integer,
  p_spots_only boolean,
  p_following_only boolean,
  p_beginner_friendly_only boolean,
  p_wheelchair_accessible_only boolean,
  p_event_setting text,
  p_event_language text,
  p_age_guidance text,
  p_alerts_enabled boolean
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
  if pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 80
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_interest, ''))) > 240
    or p_radius_km not between 1 and 100
    or (p_category is not null and pg_catalog.char_length(pg_catalog.btrim(p_category)) not between 2 and 60)
    or p_date_filter not in ('any', 'today', 'tomorrow', 'weekend')
    or p_time_filter not in ('any', 'morning', 'afternoon', 'evening')
    or p_timezone_offset_minutes not between -840 and 840
    or p_event_setting not in ('any', 'indoor', 'outdoor', 'mixed')
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_event_language, ''))) > 80
    or p_age_guidance not in ('any', 'all_ages', 'families', 'teens', 'adults') then
    raise exception using errcode = '22023', message = 'saved_search_validation';
  end if;

  begin
    update public.saved_event_searches s set
      name = pg_catalog.btrim(p_name),
      interest = pg_catalog.btrim(coalesce(p_interest, '')),
      radius_km = p_radius_km,
      category = nullif(pg_catalog.btrim(coalesce(p_category, '')), ''),
      date_filter = p_date_filter,
      time_filter = p_time_filter,
      timezone_offset_minutes = p_timezone_offset_minutes,
      spots_only = p_spots_only,
      following_only = p_following_only,
      beginner_friendly_only = p_beginner_friendly_only,
      wheelchair_accessible_only = p_wheelchair_accessible_only,
      event_setting = p_event_setting,
      event_language = pg_catalog.btrim(coalesce(p_event_language, '')),
      age_guidance = p_age_guidance,
      alerts_enabled = p_alerts_enabled
    where s.id = p_search_id and s.user_id = auth.uid();
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'saved_search_name_taken';
  end;
  return found;
end;
$$;

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
        extensions.st_makepoint(p.approximate_longitude, p.approximate_latitude),
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

revoke all on function public.filter_event_ids_by_details(
  uuid[], boolean, boolean, text, text, text
) from public, anon;
revoke all on function public.list_saved_event_searches() from public, anon;
revoke all on function public.create_saved_event_search(
  text, text, double precision, text, text, text, integer, boolean, boolean,
  boolean, boolean, text, text, text, boolean
) from public, anon;
revoke all on function public.update_saved_event_search(
  uuid, text, text, double precision, text, text, text, integer, boolean,
  boolean, boolean, boolean, text, text, text, boolean
) from public, anon;

grant execute on function public.filter_event_ids_by_details(
  uuid[], boolean, boolean, text, text, text
) to authenticated;
grant execute on function public.list_saved_event_searches() to authenticated;
grant execute on function public.create_saved_event_search(
  text, text, double precision, text, text, text, integer, boolean, boolean,
  boolean, boolean, text, text, text, boolean
) to authenticated;
grant execute on function public.update_saved_event_search(
  uuid, text, text, double precision, text, text, text, integer, boolean,
  boolean, boolean, boolean, text, text, text, boolean
) to authenticated;

comment on function public.filter_event_ids_by_details(
  uuid[], boolean, boolean, text, text, text
) is 'Preserves candidate order while applying practical event-detail filters.';
comment on function public.update_saved_event_search(
  uuid, text, text, double precision, text, text, text, integer, boolean,
  boolean, boolean, boolean, text, text, text, boolean
) is 'Updates or pauses one saved search owned by the authenticated member.';
